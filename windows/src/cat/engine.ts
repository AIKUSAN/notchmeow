// The cat engine: the state machine that moves a cat. A port of CatEngine in design/prototype/cat-core.js, the tie-breaker.
// The island, the views and the mini cats use: setState, triggerEmote, slap, blink, update, draw, busy, isMini, collarColor,
// lookX and lookY, tgEs and onDizzy, and the file catch.
//
// The engine owns no clock and no random numbers: `now()` (ms) and `rand()` are injected, so a test gives it a fake
// clock and a seeded rng(seed) and gets the same numbers on every platform. The order of the rand() calls is part of
// the contract (docs/CAT-CONTRACT.md): the fixtures pin it.

import { Sound } from "../core/sound.ts";
import { BADGE, COL, EZ, GLOW, MKEYS, MOUTH, TAU, TINT, ZOOM_AFTER_MS, clamp, hex, lerp, mouthFx, own, workClockStep, EMOUTH } from "./base.ts";
import type { BadgeKind, EaseName, MouthKey, StateName } from "./base.ts";
import { applyDance, danceEars, danceLevel } from "./dance.ts";
import { catById } from "./presets.ts";
import { PERSONAS, persMultipliers } from "./personality.ts";
import type { Multipliers } from "./personality.ts";
import { drawCat } from "./renderer.ts";
import type { CatView } from "./renderer.ts";
import { newPose } from "./geometry.ts";
import { CLASSIC } from "./motion/classic.ts";
import { PLAYFUL } from "./motion/playful.ts";
import type { Ball, CatPreset, EyeShape, Particle, ParticleKind, Persona, Pose, PoseKey, Targets } from "./types.ts";

/** One step of a tween: the value to reach, how long it takes (ms) and the easing. */
export type TweenKey = readonly [target: number, ms: number, ease: EaseName];
interface Tween { from: number; keys: readonly TweenKey[]; i: number; t0: number; done?: () => void }

/**
 * A motion style. Classic moves 1:1 like upstream; Playful has the cat's body language. Both are tables and small
 * functions over the same engine, so a cat can switch between them live.
 */
export interface MotionProfile {
  key: string;
  label: string;
  /** The eye shape a state shows when nothing overrides it. */
  eye(st: StateName): EyeShape;
  /** What the cat does on entering a state. */
  enter(c: BotEngine, st: StateName, prev: StateName): void;
  /** Fills the pose targets for the state; returns the gaze [yaw, pitch] the face turns toward. */
  targets(c: BotEngine, st: StateName, T: number, tg: Targets): [number, number];
  /** Per-frame motion applied straight to the pose, after the smoothing. */
  post(c: BotEngine, st: StateName, T: number, kG: number): void;
  /** Idle habits and the drifting z's and sweat. */
  ambient(c: BotEngine, t: number): void;
  /** The squash a slap gives: [height, width]. */
  squash: readonly [number, number];
  /** The body language of one emote. */
  emote(c: BotEngine, n: string): void;
}

const PROFILES: Record<string, MotionProfile> = { classic: CLASSIC, playful: PLAYFUL };

/**
 * Shared settings every engine reads unless it is given its own: the global motion style, a per-cat motion override
 * (by cat id), a per-cat personality (preset name plus six traits), and how long a run of work earns zoomies (ms).
 */
export interface CatCfg {
  motion: string;
  override: Record<string, string | null | undefined>;
  pers: Record<string, Persona | undefined>;
  zoomAfter: number;
  /** The cat everything wears (a cat id): the island, the pills, the drop view and the greeting. Settings fills it; an unknown or missing one is Shrimpy. */
  character?: string;
  /** The collar style the Main cat wears (cat/settings.ts, `collarFor`): `tag`, `band`, `kerchief` or `off`. What an engine whose coat has no entry in `collars` wears. */
  collar?: string;
  /** The collar style each coat wears (`collarFor` of every cat ID): in A cat for each agent mode a pill's cat is not the Main cat, and a kitten wears its parent's coat's. */
  collars?: Record<string, string>;
  /** Optional fur strands, drawn on a big cat only (the renderer's own size rule). */
  fur?: boolean;
}
export const catCfg: CatCfg = { motion: "playful", override: {}, pers: {}, zoomAfter: ZOOM_AFTER_MS };

export interface EngineOptions {
  /** A mini cat (pills, the compact grid): it wanders with its eyes instead of following the cursor. */
  mini?: boolean;
  /** Milliseconds, default performance.now. */
  now?: () => number;
  /** 0 up to, not including, 1, default Math.random. */
  rand?: () => number;
  /** Default: the shared `catCfg`. */
  cfg?: CatCfg;
  /** Turns off every random idle habit (blinks, ear flicks, bleps, personality), leaving only what is asked for. */
  quiet?: boolean;
  state?: StateName;
  /** Collects [ms, 'name'] for blinks, flicks, bleps, licks, emotes, zoomies and hairballs. */
  log?: [number, string][] | null;
}

/**
 * The file catch and the hairball, in ms: the numbers the cat, the drop view's note (island.ts) and the engine's own end-of-flow timer all wait on.
 * After the arrival: the lick, the sparks, and the end of the flow (the sparks have faded). A refusal: the pause before the first heave, the whole
 * hairball, when the ball leaves the mouth and how long a ball wrapping a file rolls.
 */
export const CATCH = { lick: 950, sparks: 1000, end: 2300, gag: 120, hairball: 2400, ballUp: 1110, fileBall: 2600 } as const;

const TARGET_KEYS: readonly (keyof Targets)[] = ["tilt", "sx", "sy", "es", "oy", "earL", "earR", "earU", "earF", "pupil", "purr", "lid", ...MKEYS];

export class BotEngine implements CatView {
  /** The cat this engine animates. */
  p: CatPreset;
  /**
   * True for an engine built without a preset, or given `setCoat(null)`: it wears `cfg.character`, whichever cat that is now, and `update` keeps it so. An engine built with
   * a preset, or given a coat with `setCoat`, keeps that cat: `update` never overwrites a per-agent coat with the Main cat.
   */
  follow: boolean;
  isMini: boolean;
  now: () => number;
  rand: () => number;
  cfg: CatCfg;
  quiet: boolean;
  log: [number, string][] | null;
  s: Pose = newPose();
  tg: Targets = {
    yaw: 0, pitch: 0, tilt: 0, sx: 1, sy: 1, es: 1, oy: 0, earL: 0, earR: 0, earU: 1, earF: 0, pupil: 0.45, purr: 0, lid: 0,
    mouth: 0, smile: 0, tongue: 0, mround: 0, mskew: 0, wavy: 0,
  };
  tw: Partial<Record<PoseKey, Tween>> = {};
  q: { at: number; fn: () => void; tag?: string }[] = [];
  parts: Particle[] = [];
  balls: Ball[] = [];
  col: number[] = hex(COL.idle);
  colT: number[] = hex(COL.idle);
  gc: number[] = [255, 255, 255];
  ga = 0.12;
  state: StateName = "idle";
  badge: BadgeKind | null = null;
  badgeCol: string | null = null;
  eyeOv: EyeShape | null = null;
  eyeUntil = 0;
  bt = 0;
  lookX = 0;
  lookY = 0;
  slaps: number[] = [];
  dizzyUntil = 0;
  saved: StateName | null = null;
  slotH = 0;
  slotT = 0;
  slotV = 0;
  chew = 0;
  chewStart = 0;
  chewUntil = 0;
  catching = false;
  waveStart = 0;
  waveUntil = 0;
  greetTok = 0;
  hbTok = 0;
  zoomTok = 0;
  zoomUntil = 0;
  zv = 0;
  mfx = 0;
  busySince: number | null = null;
  workedFor = 0;
  nextBlink: number;
  nextTw: number;
  nextSB: number;
  nextAmb: number;
  nextYawn = 0;
  nextBlep: number;
  nextPers: number;
  blushBase = 0;
  miniNext = 0;
  miniLook = { x: 0, y: 0 };
  private oxPrev: number | null = null;
  base: CatView["base"] = null;
  at: CatView["at"] = null;
  mouthAt: CatView["mouthAt"] = null;

  // What the island and the views set.
  /** The colour of the collar this cat wears now ("#RRGGBB"), or null for none: the agent driving the big cat's state, or a mini cat's own pill. The style is `cfg.collar`. */
  collarColor: string | null = null;
  /**
   * The outfit this cat wears (sub-project I): a resolved ID (never `auto`) or null for none. Only the views that show a big cat set it (the island's main cat, cat 2 in Two cats mode,
   * the desktop cat); a mini cat, a kitten and every other engine keep null and stay bare, whatever their size.
   */
  outfit: string | null = null;
  /** Extra canvas height above the cat so hearts can fly out without clipping. */
  particleOverhang = 0;
  /** True in the compact notch: the badge sits on the left of the head, away from the camera housing. */
  badgeLeft = false;
  /**
   * In the compact strip: the distance in px from the cat's centre up to the top of the island, which is the top of the screen, where an ear is
   * cut off. `draw` passes `cy - earRoom` to `drawCat` as `earCeiling`, so the ears are fitted under it with the contract's `earFit` (A-0b, merged `6adf584`): the room is the app's, the ceiling is the contract's. null everywhere else.
   */
  earRoom: number | null = null;
  /**
   * The y of the top of the canvas, in its own coordinates, when a hat must stay inside it (the desktop cat's window): `draw` passes it as `outfitCeiling`, so an outfit is shortened to the
   * room under the canvas's top and the ears keep `earRoom`. null everywhere else, where the outfit uses `earRoom` as it always did.
   */
  outfitCeiling: number | null = null;
  /** Fired when three slaps land inside 1.7 s (the island then shows the confused view and recovers). */
  onDizzy: (() => void) | null = null;
  /** Music is playing: the cat bobs to it (cat/dance.ts). Set with `setDancing`; `dancingLevel` follows it, 0 to 1. */
  isDancing = false;
  dancingLevel = 0;
  private esHover = 1;

  /** Built without a preset, the engine wears the cat Settings chose (`cfg.character`) and follows it when it changes; with a preset it keeps that cat. */
  constructor(p?: CatPreset, o: EngineOptions = {}) {
    this.cfg = o.cfg || catCfg;
    this.follow = p === undefined;
    this.p = p ?? catById(this.cfg.character);
    this.isMini = !!o.mini;
    this.now = o.now || (() => performance.now());
    this.rand = o.rand || (() => Math.random());
    this.quiet = !!o.quiet;
    this.log = o.log || null;
    const t = this.now();
    this.nextBlink = t + this.u(1500, 3500);
    this.nextTw = t + this.u(2000, 5000);
    this.nextSB = t + this.u(6000, 10000);
    this.nextAmb = t + 1300;
    this.nextBlep = t + this.u(5000, 9000);
    this.nextPers = t + this.u(3000, 6000);
    this.setState(o.state || "idle", true);
  }

  /**
   * Which cat this engine wears, from the cast (cat/cast.ts). A cat ID fixes it there (an unknown one is Shrimpy) and the engine stops following the Main cat; `null` makes it
   * follow `cfg.character` again. The island, the pills, the grid, the greeting and the drop view call it with the coat the cast names, so a per-agent coat is never overwritten.
   */
  setCoat(id: string | null) {
    this.follow = id === null;
    this.p = catById(id === null ? this.cfg.character : id);
  }

  /** The collar style this cat wears: the one `cfg.collars` holds for its coat (a kitten's is its parent's), else the Main cat's `cfg.collar`, else `off`. */
  get collarStyle(): string {
    const id = this.p.base || this.p.name;
    return (this.cfg.collars && own(this.cfg.collars, id) ? this.cfg.collars[id] : this.cfg.collar) ?? "off";
  }

  /** The motion style in force for this cat: its own override, else the global style; an unknown stored value means Playful. */
  get motion(): string {
    const m = this.cfg.override[this.p.base || this.p.name] || this.cfg.motion;
    return own(PROFILES, m) ? m : "playful";
  }
  get prof(): MotionProfile { return PROFILES[this.motion]; }
  get pers(): Persona | (typeof PERSONAS)[string] { return this.cfg.pers[this.p.base || this.p.name] || PERSONAS.balanced; }
  /** What this cat's personality changes (persMultipliers). */
  pm(): Multipliers { return persMultipliers(this.pers); }
  u(a: number, b: number): number { return a + this.rand() * (b - a); }
  note(ev: string) { if (this.log) this.log.push([Math.round(this.now()), ev]); }
  anim(k: PoseKey, keys: readonly TweenKey[], done?: () => void) { this.tw[k] = { from: this.s[k], keys, i: 0, t0: this.now(), done }; }
  later(d: number, fn: () => void, tag?: string) { this.q.push({ at: this.now() + d, fn, tag }); }
  ov(shape: EyeShape, d: number) { this.eyeOv = shape; this.eyeUntil = this.now() + d; }
  /** Holds a mouth pose for d ms, then eases back to the state's mouth. */
  mpose(v: Partial<Record<MouthKey, number>>, d: number, i = 150, o = 250) {
    for (const k of Object.keys(v) as MouthKey[]) this.anim(k, [[v[k]!, i, "out"], [v[k]!, Math.max(0, d - i - o), "lin"], [this.tg[k], o, "inOut"]]);
  }

  eyeShape(): EyeShape { return this.eyeOv && this.now() < this.eyeUntil ? this.eyeOv : this.prof.eye(this.state); }
  blink() { if (this.tw.open) return; this.note("blink"); this.anim("open", [[0.06, 70, "inOut"], [1, 130, "out"]]); }
  twitch(ear: "earL" | "earR") {
    this.note("twitch:" + ear);
    const b = this.tg[ear];
    this.anim(ear, [[b + 0.5, 60, "out"], [b, 280, "back"]]);
    this.anim("wh", [[0.25, 60, "out"], [0, 300, "inOut"]]);
  }
  emit(k: ParticleKind, n: number) {
    for (let i = 0; i < n; i++) {
      this.parts.push({
        k, x: (this.rand() - 0.5) * 0.9 + (k === "z" ? 0.55 : 0) + this.s.ox / 1.3, y: -0.85 - this.rand() * 0.2 + this.s.oy / 1.3,
        vx: (this.rand() - 0.5) * 0.35 + (k === "z" ? 0.18 : 0), vy: -(0.45 + this.rand() * 0.35), age: -0.14 * i, life: 1.3 + this.rand() * 0.5,
        size: 0.15 + this.rand() * 0.08, rot: this.rand() * 6,
      });
    }
  }
  setBadge(b: BadgeKind | null) {
    const tok = ++this.bt;
    this.anim("badgeS", [[0, 90, "inOut"]]);
    this.later(100, () => { if (tok !== this.bt) return; this.badge = b; if (b) this.anim("badgeS", [[1, 280, "back"]]); });
  }
  /** Moves the cat to a state. An unknown state is ignored. */
  setState(st: StateName | string, force = false) {
    if (!own(COL, st)) return;
    const next = st as StateName;
    if (!force && next === this.state) return;
    const prev = this.state;
    this.state = next;
    this.q = this.q.filter((x) => x.tag !== "st");
    if (next !== "dizzy") this.dizzyUntil = 0;
    this.colT = hex(COL[next]);
    this.s.tint = TINT[next];
    const b = BADGE[next] || null;
    if (b !== this.badge || force) this.setBadge(b);
    for (const k of ["oy", "ox", "roll", "sx", "sy", "tilt", "earF", "earU", "lid", ...MKEYS] as PoseKey[]) delete this.tw[k];
    this.s.roll = 0;
    const wc = workClockStep({ busySince: this.busySince, workedFor: this.workedFor }, next, this.now());
    this.busySince = wc.busySince;
    this.workedFor = wc.workedFor;
    if (this.eyeUntil !== Infinity) this.eyeOv = null;
    this.prof.enter(this, next, prev);
  }
  /** A poke: a squash, and three inside 1.7 s make the cat dizzy. */
  slap() {
    this.interruptGreet();
    const t = this.now();
    this.slaps = this.slaps.filter((x) => t - x < 1700);
    this.slaps.push(t);
    const [a, b] = this.prof.squash;
    this.anim("sy", [[a, 70, "out"], [1.1, 130, "out"], [1, 170, "inOut"]]);
    this.anim("sx", [[b, 70, "out"], [0.95, 130, "out"], [1, 170, "inOut"]]);
    if (this.state === "dizzy") return;
    Sound.play("slap");
    if (this.slaps.length >= 3) {
      this.slaps = [];
      // The island, when it is listening, shows the confused view and puts the cat back itself.
      if (this.onDizzy) { this.onDizzy(); return; }
      this.saved = this.state;
      this.setState("dizzy");
      this.dizzyUntil = t + 3300;
      return;
    }
    const M = this.pm();
    if (M.poke === "love") { this.emote("love"); return; }
    this.emote("annoyed");
    this.later(60, () => Sound.play("annoyed"));
    if (M.pokeHiss) this.mpose({ mouth: 0.6, smile: -1, mround: 0 }, 500, 60, 180);
  }
  interruptGreet() {
    if (this.s.paws <= 0.01 && this.now() >= this.waveUntil) return;
    this.greetTok++;
    this.waveUntil = 0;
    this.waveStart = 0;
    this.anim("paws", [[0, 150, "inOut"]]);
  }

  /** Plays an emote: love, surprised, proud, wink, yawn, happy, annoyed, hello, zoomies or hairball. An unknown name is ignored. */
  emote(n: string) {
    if (!own(EMOUTH, n) && n !== "hello" && n !== "zoomies" && n !== "hairball") return; // an unknown emote changes nothing, and is not logged
    this.note("emote:" + n);
    if (n === "hello") return this.greet();
    if (n === "zoomies") return this.zoomies();
    if (n === "hairball") return this.hairball();
    this.prof.emote(this, n);
    if (own(EMOUTH, n)) { const m = EMOUTH[n]; this.mpose(m[0], m[1]); }
  }
  blep() { this.note("blep"); this.anim("tongue", [[0.7, 150, "out"], [0.7, 1300, "lin"], [this.tg.tongue, 220, "inOut"]]); }
  lick() { this.note("lick"); this.anim("mouth", [[0.16, 90, "out"], [this.tg.mouth, 170, "inOut"]]); this.anim("tongue", [[1, 90, "out"], [this.tg.tongue, 180, "inOut"]]); }
  slowBlink() { this.note("slowblink"); this.anim("lid", [[0.75, 380, "inOut"], [0.75, 320, "lin"], [0, 480, "inOut"]]); }
  /** Idle habits that come from personality: yawns, zoomies, mews, purrs, hmphs, winks. */
  persAmbient(t: number) {
    const I = this.pm().idle;
    if (this.state !== "idle" || t < this.nextPers) return;
    this.nextPers = t + this.u(6000, 11000);
    const r = this.rand();
    if (I.yawn && r < 0.5) return this.emote("yawn");
    if (I.zoomies && r < 0.35) return this.zoomies();
    if (I.mew && r < 0.6) return this.mpose({ mouth: 0.42, mround: 0.4, smile: 0.2 }, 420, 100, 180);
    if (I.purr && r < 0.55) { this.anim("lid", [[0.75, 380, "inOut"], [0.75, 600, "lin"], [0, 480, "inOut"]]); return this.anim("purr", [[1, 200, "out"], [1, 1000, "lin"], [0, 300, "inOut"]]); }
    if (I.hmph && r < 0.55) return this.mpose({ smile: -0.85, mskew: -0.7 }, 1000);
    if (I.wink && r < 0.5) { this.ov("wink", 550); this.blep(); }
  }
  /** Zoomies: pupils blown, ears back, side-to-side dashes with skids, then a happy flop. */
  zoomies() {
    this.note("zoomies");
    const a = this.anim.bind(this), pl = this.motion === "playful", tok = ++this.zoomTok, tg = this.tg;
    this.interruptGreet();
    this.zoomUntil = this.now() + 1950;
    this.ov("wide", 1900);
    a("pupil", [[1, 120, "out"], [1, 1750, "lin"], [tg.pupil, 400, "inOut"]]);
    a("earF", [[0.55, 150, "out"], [0.55, 1750, "lin"], [tg.earF, 400, "inOut"]]);
    a("ox", [[-0.05, 70, "inOut"], [0.04, 70, "inOut"], [-0.05, 70, "inOut"], [0.04, 70, "inOut"], [0, 60, "inOut"], [0.88, 240, "in"], [0.97, 90, "out"], [0.84, 110, "inOut"], [-0.88, 380, "inOut"], [-0.97, 90, "out"], [-0.84, 110, "inOut"], [0.3, 320, "inOut"], [0, 260, "back"]]);
    this.mpose({ mouth: 0.32, tongue: 0.9, smile: 0.6, mround: 0 }, 1950, 150, 300);
    this.later(670, () => { if (tok === this.zoomTok) this.dust(1); });
    this.later(1250, () => { if (tok === this.zoomTok) this.dust(-1); });
    this.later(1950, () => {
      if (tok !== this.zoomTok) return;
      this.ov("happy", 900);
      a("sy", [[0.84, 90, "out"], [1.06, 150, "out"], [1, 220, "back"]]);
      a("sx", [[1.14, 90, "out"], [0.96, 150, "out"], [1, 220, "back"]]);
      this.emit("spark", 3);
      if (pl) a("blush", [[0.5, 200, "out"], [0, 800, "inOut"]]);
    });
  }
  dust(dir: number) {
    const y = (this.p.ruff ? 1.1 : 0.88) / 1.3;
    for (let i = 0; i < 4; i++) {
      this.parts.push({
        k: "dust", x: (this.s.ox + dir * 0.45) / 1.3 + (this.rand() - 0.5) * 0.2, y: y + (this.rand() - 0.5) * 0.06,
        vx: -dir * this.u(0.12, 0.35), vy: -this.u(0.03, 0.12), age: -i * 0.04, life: 0.55 + this.rand() * 0.2, size: 0.09 + this.rand() * 0.05, rot: 0,
      });
    }
  }
  /** Paw wave, upstream's greet() timings with paws for hands. */
  greet() {
    const t = this.now(), tok = ++this.greetTok, a = this.anim.bind(this), ok = () => tok === this.greetTok;
    this.waveStart = t + 450;
    this.waveUntil = t + 1550;
    this.ov("happy", 2000);
    a("oy", [[-0.06, 220, "out"], [0, 220, "back"]]);
    this.later(250, () => {
      if (!ok()) return;
      a("paws", [[1, 280, "out"]]);
      a("sy", [[0.95, 100, "out"], [1, 260, "back"]]);
      a("sx", [[1.04, 100, "out"], [1, 260, "back"]]);
      if (this.motion === "playful") a("earU", [[1.15, 200, "out"], [1.15, 900, "lin"], [1, 400, "inOut"]]);
      Sound.play("greet");
    });
    this.later(450, () => { if (ok()) this.mpose({ mouth: 0.45, mround: 0.45, smile: 0.35 }, 650, 90, 200); });
    this.later(550, () => { if (ok()) this.blink(); });
    this.later(1500, () => { if (ok()) this.blink(); });
    this.later(1550, () => { if (!ok()) return; this.waveUntil = 0; a("paws", [[0, 200, "inOut"]]); });
    this.later(1750, () => { if (ok()) this.ov("happy", 300); });
  }

  /** File catch, step 1: open wide while a file hovers over the island. `false` closes the mouth again. */
  catchOpen(on: boolean) {
    if (on === this.catching) return;
    this.catching = on;
    if (on) {
      this.slotT = 0.55;
      this.eyeOv = "wide";
      this.eyeUntil = Infinity;
      this.anim("oy", [[-0.05, 160, "out"], [-0.03, 200, "inOut"]]);
    } else {
      this.slotT = 0;
      if (this.eyeUntil === Infinity) { this.eyeOv = null; this.eyeUntil = 0; }
    }
  }
  /** Step 2: the file is dropped and flies in: snap wider. */
  catchDrop() { this.catching = true; this.slotT = 1.05; this.eyeOv = "wide"; this.eyeUntil = Infinity; }
  /** Steps 3 and 4: the file arrives: gulp with a squash, then chew for 0.85 s with happy eyes. */
  catchArrive() {
    this.catching = false;
    this.slotT = 0;
    const t = this.now(), a = this.anim.bind(this);
    this.chewStart = t + 80;
    this.chewUntil = t + 930;
    this.ov("happy", 1250);
    a("sy", [[0.8, 80, "out"], [1.16, 130, "out"], [1, 220, "back"]]);
    a("sx", [[1.24, 80, "out"], [0.92, 130, "out"], [1, 220, "back"]]);
    if (this.motion === "playful") { a("earU", [[1.15, 150, "out"], [1, 500, "inOut"]]); a("blush", [[0.6, 200, "out"], [0, 800, "inOut"]]); }
    this.later(CATCH.lick, () => this.lick(), "file");
    this.later(CATCH.sparks, () => this.emit("spark", 3), "file");
    this.fileEnd(CATCH.end);
  }
  /**
   * A file the app refuses: the cat caught it, gags and coughs it back up wrapped in fur. `ext` is shown on the file.
   * The gag starts with the cat's `annoyed` sound, once; the hairball 120 ms later, and the note after it, are silent
   * (sound Stage 3 adds the `pop` at the cough).
   */
  catchReject(ext: string) {
    this.catching = false;
    this.slotT = 0;
    this.eyeOv = null;
    this.eyeUntil = 0;
    // A refusal that comes after the cat began to chew: the chew's lick and sparks are not for a cat that is gagging.
    this.q = this.q.filter((x) => x.tag !== "file");
    Sound.play("annoyed");
    this.later(CATCH.gag, () => this.hairball(ext), "file");
    this.fileEnd(CATCH.gag + CATCH.ballUp + CATCH.fileBall);
  }
  /**
   * The drop view's file, in whatever order the events come: hovering over the island, dropped and flying into the mouth,
   * swallowed. The drop view calls these four; the refusal can arrive before the file reaches the mouth, after it, or never.
   */
  fileStep: "none" | "hover" | "flying" | "arrived" = "none";
  private fileExt = "FILE";
  private fileRefused = false;
  private fileRejected = false;
  private fileEndTok = 0;

  /** A file is over the island (true) or left it (false): the cat opens wide, or closes its mouth again. */
  fileHover(on: boolean) {
    if (on) {
      this.fileLeft();
      this.fileStep = "hover"; this.fileRefused = false; this.fileRejected = false;
    }
    else if (this.fileStep === "hover") this.fileStep = "none";
    else return;
    this.catchOpen(on);
  }
  /**
   * A drop the user left in the middle (the canvas stopped updating the cat when they left): whatever its catch had still pending (the hairball
   * launch, the lick, the sparks) or frozen in the air (a ball) would play on the next drag. Start clean. A finished drop is "none" and is left alone.
   */
  private fileLeft() {
    if (this.fileStep !== "flying" && this.fileStep !== "arrived") return;
    this.q = this.q.filter((x) => x.tag !== "file");
    this.hbTok++;
    this.balls = [];
    this.parts = [];
  }
  /** The catch has run its course `ms` after the file arrived: the flow ends, so a later drag has nothing to clean up. */
  private fileEnd(ms: number) {
    const tok = ++this.fileEndTok; // a refusal after the arrival schedules a later end: the last one wins
    this.later(ms, () => { if (tok === this.fileEndTok) this.fileStep = "none"; }, "file");
  }
  /** The file was dropped. `name` gives the extension that a refused file shows. */
  fileDrop(name: string) {
    const dot = name.lastIndexOf(".");
    this.fileExt = ((dot >= 0 ? name.slice(dot + 1) : "") || "file").slice(0, 4).toUpperCase();
    this.fileLeft();
    this.fileStep = "flying";
    this.fileRefused = false;
    this.fileRejected = false;
    this.catchDrop();
  }
  /** The app can't take this file: the cat coughs it back up once it has swallowed it, at once if it already has. */
  fileRefuse() {
    this.fileRefused = true;
    if (this.fileStep === "arrived" && !this.fileRejected) { this.fileRejected = true; this.catchReject(this.fileExt); }
  }
  /** The file has reached the mouth: gulp and chew, or gag. Ignored unless a file is flying. */
  fileArrived() {
    if (this.fileStep !== "flying") return;
    this.fileStep = "arrived";
    if (this.fileRefused) { this.fileRejected = true; this.catchReject(this.fileExt); }
    else this.catchArrive();
  }
  /** Hairball: ears back, three heaves, then it comes up (with the file, if it was one). */
  hairball(file?: string) {
    this.note("hairball");
    const a = this.anim.bind(this), pl = this.motion === "playful", tok = ++this.hbTok, tg = this.tg;
    this.ov("closed", 1300);
    if (pl) a("earF", [[0.7, 150, "out"], [0.7, 1000, "lin"], [tg.earF, 400, "inOut"]]);
    a("oy", [[0.06, 140, "out"], [0, 180, "inOut"], [0.07, 140, "out"], [0, 180, "inOut"], [0.09, 140, "out"], [-0.02, 160, "inOut"], [0.11, 170, "out"], [0, 320, "back"]]);
    a("sy", [[0.92, 140, "out"], [1.04, 180, "inOut"], [0.9, 140, "out"], [1.05, 180, "inOut"], [0.88, 140, "out"], [1.06, 160, "inOut"], [0.86, 170, "out"], [1, 320, "back"]]);
    a("sx", [[1.05, 140, "out"], [0.98, 180, "inOut"], [1.07, 140, "out"], [0.97, 180, "inOut"], [1.09, 140, "out"], [0.96, 160, "inOut"], [1.1, 170, "out"], [1, 320, "back"]]);
    a("mouth", [[0.22, 140, "out"], [0, 180, "inOut"], [0.28, 140, "out"], [0, 180, "inOut"], [0.34, 140, "out"], [0, 160, "inOut"], [1.05, 170, "out"], [1.05, 160, "lin"], [tg.mouth, 260, "inOut"]]);
    a("mround", [[0.3, 140, "out"], [0.3, 800, "lin"], [0, 170, "out"], [0, 420, "lin"], [tg.mround, 200, "inOut"]]);
    a("smile", [[-0.7, 140, "out"], [-0.7, 970, "lin"], [0.5, 330, "inOut"], [0.5, 700, "lin"], [tg.smile, 300, "inOut"]]);
    this.later(CATCH.ballUp, () => { if (tok === this.hbTok) this.spitBall(file); });
    this.later(1450, () => {
      if (tok !== this.hbTok) return;
      this.ov("happy", 900);
      if (pl) a("blush", [[0.45, 200, "out"], [0, 700, "inOut"]]);
      this.later(320, () => this.lick());
    });
  }
  spitBall(file?: string) {
    const m = this.mouthAt, b0 = this.base;
    if (!m || !b0) return;
    const R = b0.R, dir = this.rand() < 0.5 ? -1 : 1, mx = (m.x - b0.x) / R, my = (m.y - b0.y) / R;
    this.balls.push({
      x: mx, y: my, vx: dir * this.u(0.55, 0.85), vy: this.u(-0.9, -0.6), rot: 0, age: 0, life: (file ? CATCH.fileBall : CATCH.hairball) / 1000, file: file || null,
      seed: (this.rand() * 1e9) | 0, floor: this.p.ruff ? 1.34 : 1.12,
    });
    for (let i = 0; i < 4; i++) {
      this.parts.push({
        k: "hair", x: mx / 1.3 + (this.rand() - 0.5) * 0.15, y: my / 1.3, vx: (this.rand() - 0.5) * 0.5, vy: this.u(-0.35, -0.15),
        age: -0.05 * i, life: 0.9 + this.rand() * 0.4, size: 0.12 + this.rand() * 0.05, rot: this.rand() * 6,
      });
    }
  }

  /** How open the mouth is right now: the state's mouth plus its motion, or the file-catch spring and chew, whichever is wider. */
  mouthOpen(): number { return Math.max(this.s.mouth + (this.mfx || 0), this.slotH + this.chew); }

  /**
   * Fills `tg`, the targets the pose eases toward, for the current state: the profile's rest pose, the state's mouth,
   * the personality, and the file-catch, wave and zoomies overrides. t is the clock in ms, T the same in seconds.
   * It reads the engine's inputs (state, lookX/lookY, personality) and never the tweens, so fixtures can call it directly.
   */
  computeTargets(t: number, T: number) {
    const tg = this.tg, st = this.state, pf = this.prof;
    tg.sx = 1; tg.sy = 1; tg.es = this.esHover; tg.purr = 0; tg.lid = 0;
    const Mo = MOUTH[st];
    MKEYS.forEach((k, i) => { tg[k] = Mo[i]; });
    this.mfx = mouthFx(st, T);
    let [ty, tp] = pf.targets(this, st, T, tg);
    // Personality: gaze, resting mouth, lids, ears, bounce, pupils, blush and chatter.
    const M = this.pm();
    ty *= M.gaze; tp *= M.gaze;
    tg.smile += M.smile; tg.mskew += M.skew;
    if (st !== "sleeping") tg.lid = Math.max(tg.lid, M.lid);
    tg.earF = Math.max(tg.earF, M.earBack); tg.oy *= M.hop; tg.pupil = clamp(tg.pupil + M.pupil, 0.1, 1);
    this.blushBase = st === "sleeping" ? 0 : M.blush;
    this.mfx *= M.chatter;
    if (this.isMini && !["thinking", "searching", "sleeping", "dizzy"].includes(st)) {
      if (t > this.miniNext) { this.miniLook = { x: this.u(-0.88, 0.88), y: this.u(-0.55, 0.45) }; this.miniNext = t + this.u(500, 2000); }
      ty = this.miniLook.x * 0.62; tp = this.miniLook.y * 0.5;
      tg.sy = 1 + Math.sin(2.2 * T) * 0.04; tg.sx = 1 - Math.sin(2.2 * T) * 0.02;
    }
    if (this.catching) { tg.earU = 1.25; tg.pupil = 0.95; ty *= 0.3; tp = tp * 0.3 + 0.12; }
    if (t > this.waveStart && t < this.waveUntil) { const wt = (t - this.waveStart) / 1000; tg.tilt = -0.06 + Math.sin(TAU * 1.2 * wt) * 0.07; }
    if (t < this.zoomUntil) {
      const zv = this.zv;
      ty = clamp(zv * 0.25, -0.62, 0.62); tp = -0.05; tg.tilt = clamp(zv * 0.05, -0.2, 0.2);
      tg.sx = 1 + Math.min(0.16, Math.abs(zv) * 0.045); tg.sy = 1 - Math.min(0.09, Math.abs(zv) * 0.025);
      tg.oy = -Math.abs(Math.sin(T * TAU * 4.5)) * 0.05 * Math.min(1, Math.abs(zv) / 1.5);
    }
    tg.yaw = ty; tg.pitch = tp;
    // The ears bounce on the landing beat while the cat dances (nothing at level 0, so every fixture row is as it was).
    if (this.dancingLevel > 0.001) tg.earU += danceEars(this.dancingLevel, T);
  }

  /** One frame. dt is seconds; anything outside 0…0.25 (a sleeping laptop, a clock that stepped back, NaN) is held to that range. */
  update(dt: number) {
    dt = Number.isFinite(dt) ? Math.min(Math.max(dt, 0), 0.25) : 0;
    if (this.follow) this.p = catById(this.cfg.character);
    const t = this.now(), T = t / 1000, s = this.s, tg = this.tg, st = this.state, pf = this.prof;
    for (const k of Object.keys(this.tw) as PoseKey[]) {
      const w = this.tw[k]!;
      let el = t - w.t0;
      while (w.i < w.keys.length) {
        const key = w.keys[w.i], d = Math.max(1, key[1]);
        if (el < d) { s[k] = lerp(w.from, key[0], EZ[key[2]](el / d)); break; }
        el -= d; w.t0 += d; w.from = key[0]; s[k] = key[0]; w.i++;
      }
      if (w.i >= w.keys.length) { delete this.tw[k]; if (w.done) w.done(); }
    }
    const v = (s.ox - (this.oxPrev ?? s.ox)) / Math.max(dt, 1e-3);
    this.oxPrev = s.ox;
    this.zv += (v - this.zv) * Math.min(1, dt * 18);
    const due = this.q.filter((x) => x.at <= t);
    this.q = this.q.filter((x) => x.at > t);
    due.forEach((x) => x.fn());
    this.computeTargets(t, T);
    const M = this.pm(), ke = M.speed, kL = 1 - Math.pow(0.0025, dt * ke), kG = 1 - Math.pow(0.0008, dt * ke), kC = 1 - Math.pow(0.002, dt);
    for (const k of ["yaw", "pitch"] as const) if (!this.tw[k]) s[k] += (tg[k] - s[k]) * kL;
    for (const k of TARGET_KEYS) if (!this.tw[k]) s[k] += (tg[k] - s[k]) * kG;
    pf.post(this, st, T, kG);
    const gT = hex(GLOW[st] || "#FFFFFF"), gaT = st === "dizzy" ? 0 : st === "idle" || st === "sleeping" ? 0.12 : 0.42;
    for (let i = 0; i < 3; i++) { this.col[i] += (this.colT[i] - this.col[i]) * kC; this.gc[i] += (gT[i] - this.gc[i]) * kC; }
    this.ga += (gaT - this.ga) * kC;
    if (!this.quiet && t >= this.nextBlink) {
      if (st !== "sleeping" && st !== "dizzy") { this.blink(); if (this.rand() < 0.22) this.later(230, () => this.blink()); }
      this.nextBlink = t + (2200 + this.rand() * 3200) * M.blinkEvery;
    }
    if (this.eyeOv && t > this.eyeUntil) this.eyeOv = null;
    if (!this.quiet) {
      pf.ambient(this, t);
      this.persAmbient(t);
    }
    if (this.dizzyUntil && t > this.dizzyUntil) {
      const b = this.saved || "idle";
      this.dizzyUntil = 0;
      this.setState(b, true);
      this.emote("happy");
    }
    for (const p of this.parts) p.age += dt;
    this.parts = this.parts.filter((p) => p.age < p.life);
    for (const b of this.balls) {
      b.age += dt; b.vy += 5.5 * dt; b.x += b.vx * dt; b.y += b.vy * dt;
      if (b.y > b.floor) { b.y = b.floor; if (b.vy > 0.6) { b.vy *= -0.38; b.vx *= 0.7; } else { b.vy = 0; b.vx *= Math.pow(0.2, dt); } }
      b.rot += b.vx * dt * 5;
    }
    this.balls = this.balls.filter((b) => b.age < b.life);
    // Mouth spring, ω₀ = 2π/0.25, ζ = 0.6 (upstream's slot spring). Stepped at most 1/60 s at a time: exactly one step at 60 fps or
    // faster, as upstream, and several on a slow frame, because a single step of about 0.066 s or more diverges to NaN.
    const om = TAU / 0.25;
    for (let r = dt; r > 0; r -= 1 / 60) {
      const h = Math.min(r, 1 / 60), acc = om * om * (this.slotT - this.slotH) - 2 * 0.6 * om * this.slotV;
      this.slotV += acc * h;
      this.slotH = Math.max(0, this.slotH + this.slotV * h);
    }
    this.chew = t >= this.chewStart && t < this.chewUntil ? 0.16 * (0.5 - 0.5 * Math.cos((TAU * 4.2 * (t - this.chewStart)) / 1000)) : 0;
    this.dancingLevel = danceLevel(this.dancingLevel, this.isDancing, dt);
  }

  // ── What the island and the views call ─────────────────────────────────────

  /** The eyes' size while the pointer rests on the cat (the island sets 1.08 and puts 1 back). */
  get tgEs(): number { return this.esHover; }
  set tgEs(v: number) { this.esHover = v; }

  /** Music starts or stops: the cat bobs to it, fading in over 0.3 s and out over 0.5 s. */
  setDancing(on: boolean) { this.isDancing = on; }

  /** The island's emotes. The duration the old engine took is gone: each emote has its own length now. */
  triggerEmote(emote: string, _duration?: number) {
    if (emote === "annoyed") this.later(60, () => Sound.play("annoyed"));
    this.emote(emote);
  }
  /**
   * True while the island must keep drawing frames. A cat that is not quiet always has an idle habit due (a blink,
   * an ear flick), so a visible island keeps animating: the old rule ("an idle cat is still") froze them.
   * The island itself stops the loop while it is hidden.
   */
  get busy(): boolean {
    return !this.quiet || Object.keys(this.tw).length > 0 || this.q.length > 0 || this.parts.length > 0 || this.balls.length > 0 ||
      Math.abs(this.slotT - this.slotH) > 0.001 || Math.abs(this.slotV) > 0.001;
  }

  /**
   * Draws the cat into a canvas of W×H CSS px (the caller has applied the DPR transform): the head is 60 % of the
   * canvas width across, as the old character's body was, centred, with `particleOverhang` of free space above for
   * hearts to fly out of.
   */
  draw(x: CanvasRenderingContext2D, W: number, H: number) {
    const cy = H / 2 + this.particleOverhang / 2, D = W * 0.6, dance = this.dancingLevel > 0.001;
    // The bob moves the whole cat around the bottom of its head: head, ears, collar, badge and all.
    if (dance) { x.save(); applyDance(x, this.dancingLevel, this.now() / 1000, W / 2, cy + D * 0.45, D / 2); }
    drawCat(x, this, W / 2, cy, D, { badgeSide: this.badgeLeft ? -1 : 1, earCeiling: this.earRoom === null ? undefined : cy - this.earRoom, outfitCeiling: this.outfitCeiling === null ? undefined : this.outfitCeiling, fur: this.cfg.fur,
      collar: this.collarColor ? { style: this.collarStyle, col: this.collarColor } : null, outfit: this.outfit });
    if (dance) x.restore();
  }
}
