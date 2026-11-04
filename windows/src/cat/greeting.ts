// The launch greeting. Everything is laid out in a 640×150 space, as on macOS (GreetingCanvasView.swift).
// The timeline is Greeting v2 from design/prototype/cat-core.js, the tie-breaker: the cat falls in with a landing
// squash, bounces, slides aside, pops up for a quick paw wave, slides back and settles with the badge and the tint.
// The pose is pure (`greetingPose`, tested against tests/fixtures/cat/sequence-cases.json); the Greeting class below
// owns the clock, the sounds and the drawing.

import { COMPACT_W, NOTCH_H, NOTCH_W, PAIR } from "../core/layout.ts";
import { Sound } from "../core/sound.ts";
import { EZ, TAU, lerp, rng, seg } from "./base.ts";
import { DEFAULT_CAT, catById } from "./presets.ts";
import { catCfg } from "./engine.ts";
import { THEME, THEME_RGB } from "../theme.generated.ts";
import { newPose } from "./geometry.ts";
import { drawCat, stillView } from "./renderer.ts";
import type { CatView, PawSpec } from "./renderer.ts";
import type { Cast } from "./cast.ts";
import type { CatPreset, EyeShape } from "./types.ts";
import type { IslandMode, IslandViewName } from "../core/layout.ts";

const NOTCH = { W: NOTCH_W, H: NOTCH_H };
const COMPACT = COMPACT_W;
const FONT = 'system-ui, "Segoe UI Variable Text", "Segoe UI", sans-serif';

/**
 * The compact island's mini grid, which takes over from the greeting's session cats once the greeting ends and which the last beat glides
 * into: four Ø13 cats, 16 px apart, centred 40 px in from the island's right edge and level with the middle of the strip (`applyGeometry`
 * in island.ts, `#mini-grid` in style.css and `createMiniBot(t, 13)`; a check keeps them together). In the greeting's 640 px canvas the
 * island is centred.
 */
export const MINI_GRID = { d: 13, step: 16, x: 320 + COMPACT_W / 2 - 40, y: NOTCH_H / 2 };

/** The shared beats: the island's growth, badge, blink and tint, and when it collapses. */
export const GT = { grow: 0.45, badge: 2.72, blink2: 3.8, tint0: 3.85, tint1: 4.15, leave: 4.9, COLLAPSE: 0.34 };
/** The new greeting's beats: fall, land, bounce, slide aside, pop up, wave, slide back. */
export const GT2 = { fall0: 0.05, land: 0.62, bounce1: 1.18, slide0: 1.25, slide1: 1.65, pop0: 1.65, wave0: 1.72, wave1: 2.72, back0: 2.75, back1: 3.25, SLIDE: 150 };
export const GREET_LEN = GT.leave + GT.COLLAPSE + 0.5;

// ── The last beat: the session cats ────────────────────────────────────────────
// A port of GT3, miniGlide and miniSlots in design/prototype/cat-core.js (the tie-breaker; sequence-cases.json pins them). Once the island has
// folded the session cats pop in as a row of three, hold a moment, glide into the compact island's 2×2 grid, and a fourth pops into the empty
// cell. Times are seconds after `leave`, the moment the island starts to fold. GREET_LEN stays 5.74 s; GREET_END is where it all ends.
export const GT3 = { glide0: 0.8, glide1: 1.3, four0: 1, end: 1.6 };
export const GREET_END = GT.leave + GT3.end;
export interface MiniGlide { grid: number; four: number }
/** The glide's two progress values: `grid` is the row becoming the grid, 0…1; `four` is the fourth cat's pop, 0…1 and a little over. */
export const miniGlide = (t: number, leave = GT.leave): MiniGlide => ({
  grid: EZ.inOut(seg(t, leave + GT3.glide0, leave + GT3.glide1)),
  four: EZ.back(seg(t, leave + GT3.four0, leave + GT3.glide1)),
});
/** The prototype's row: head width, spacing, the first cat's inset from the island's right edge, and how far it sits below the strip's middle (px). */
export const MINI_ROW = { d: 11, step: 14, inset: 12, dy: 1 };
/** The compact island's grid cells: centres `step` apart, the grid's centre `inset` px in from the island's right edge. The cat's size is MINI_GRID.d. */
export const MINI_CELL = { step: 16, inset: 40 };
/** Grid cell (top left, top right, bottom left, bottom right) to the row cat that glides into it, 0 being the row's right-most; the bottom left has none. */
export const MINI_FROM: readonly (number | null)[] = [2, 1, null, 0];
/** A session cat narrower than this (px) is not drawn: the first frames of a pop, or a strip too short to hold it. */
export const MINI_MIN_D = 2;
export interface MiniSlot { x: number; y: number; d: number }
/**
 * The four session cats in the order of the grid's cells: centre and head width in px in the 640×150 space, d = 0 for a cat that is not there.
 * `minis` is the row's pop-in (GreetPose.minis), `g` is miniGlide(t, leave), W and H the compact island, d the grid cat's head width.
 * A strip shorter than 32 px shrinks everything the way the Mac's miniGridScale does: min(1, (H - 4) / 28).
 */
export function miniSlots(minis: number, g: MiniGlide, { W = COMPACT_W, H = NOTCH_H, d = MINI_GRID.d } = {}): MiniSlot[] {
  const k = Math.min(1, Math.max(0, H - 4) / 28), right = 320 + W / 2, gx = right - MINI_CELL.inset, gy = H / 2, s = (MINI_CELL.step / 2) * k;
  return MINI_FROM.map((from, i) => {
    const x1 = gx + (i % 2 ? s : -s), y1 = gy + (i < 2 ? -s : s);
    const x = from === null ? x1 : lerp(right - (MINI_ROW.inset + MINI_ROW.step * from) * k, x1, g.grid);
    const y = from === null ? y1 : lerp(gy + MINI_ROW.dy * k, y1, g.grid);
    const dd = (from === null ? d * g.four : lerp(MINI_ROW.d, d, g.grid) * minis) * k;
    return { x, y, d: dd < MINI_MIN_D ? 0 : dd };
  });
}

/** What the cast says the greeting wears (cat/cast.ts `greeting`): the cat that falls in, the pair that arrives together in Two cats mode, and the four session cats in the grid's cell order. */
export type GreetingCast = Cast["greeting"];

/** The streak burst: 16 coloured streaks from seed 7, the same on every platform. */
export const STREAKS = (() => {
  const r = rng(7), cols = THEME.greeting.streaks;
  return Array.from({ length: 16 }, (_, i) => ({ a: (i / 16) * TAU + (r() - 0.5) * 0.3, sp: 230 + r() * 260, len: 6 + r() * 9, t0: 0.08 + r() * 0.14, col: cols[i % 5] }));
})();
/** Streak burst time: it starts when the cat lands. */
export const streakTime = (t: number) => t - (GT2.land - 0.1);

export type GreetEye = "dot" | "happy" | "content";

/**
 * The greeting pose at t seconds, all in the 640×150 space: island iw×ih, cat centre x,y and head width hb×1.34,
 * squash sx/sy, tilt, eye shape, gaze lookX/lookY, paw raise handL/handR, wave clock (-1 = off), blink open,
 * and the 0…1 fades badge, tint, halo, haloBlue, header, card, fx (streaks), minis (the session cats).
 */
export interface GreetPose {
  iw: number; ih: number; hb: number; x: number; y: number; sx: number; sy: number; tilt: number;
  eye: GreetEye; lookX: number; lookY: number; handL: number; handR: number; wave: number; open: number;
  badge: number; tint: number; halo: number; haloBlue: number; header: number; card: number; fx: number; minis: number;
}
interface Base { iw: number; ih: number; hb: number; base: number; open: number; badge: number; tint: number; halo: number; haloBlue: number; header: number; card: number }

/** The island and the shared beats: size, blink, badge, tint, halo, header. Everything but the cat's own motion. */
function islandBase(t: number): Base {
  const gx = seg(t, 0, 0.5), g = Math.sin((Math.PI * gx) / 2) + 0.04 * Math.sin(Math.PI * gx) * gx, gg = EZ.back(seg(t, 0.02, GT.grow));
  const blink = (tb: number) => { const k = seg(t, tb, tb + 0.12); return k > 0 && k < 1 ? 1 - Math.sin(Math.PI * k) * 0.94 : 1; };
  return {
    iw: lerp(NOTCH.W, 640, g), ih: lerp(NOTCH.H, 150, g), hb: lerp(3, 58, gg), base: lerp(16, 86, EZ.out(seg(t, 0.02, GT.grow))),
    open: Math.min(blink(1.95), blink(GT.blink2)),
    badge: EZ.back(seg(t, GT.badge, GT.badge + 0.28)), tint: 0.6 * EZ.inOut(seg(t, GT.tint0, GT.tint1)), halo: EZ.out(seg(t, 0.3, 0.7)),
    haloBlue: seg(t, GT.tint0, GT.tint1), header: seg(t, 0.35, 0.6), card: seg(t, 0.18, 0.45),
  };
}

/** The cat's fall, bounce, slide, pop and wave. */
function fallPose(t: number, B: Base): GreetPose {
  const G = GT2, hb = B.hb, D = hb * 1.34, base = B.base;
  let x = 320, y = base, sx = 1, sy = 1, tilt = 0, eye: GreetEye = "dot", lookX = 0, lookY = 0, wave = -1;
  const fall = seg(t, G.fall0, G.land);
  y -= (1 - fall * fall) * (base + 70); // 1 fall in (accelerating)
  const sq = Math.sin(Math.PI * seg(t, G.land, G.land + 0.16));
  sy -= 0.2 * sq; sx += 0.14 * sq; y += D * 0.05 * sq; // landing squash
  const b = seg(t, G.land + 0.16, G.bounce1);
  y -= 4 * b * (1 - b) * hb * 0.3; sy += 0.05 * Math.sin(Math.PI * b); // 2 small bounce
  const sq2 = Math.sin(Math.PI * seg(t, G.bounce1, G.bounce1 + 0.1));
  sy -= 0.07 * sq2; sx += 0.05 * sq2; y += D * 0.02 * sq2;
  const out = EZ.inOut(seg(t, G.slide0, G.slide1)), ret = EZ.inOut(seg(t, G.back0, G.back1)); // 3 slide aside, 5 slide back
  x += G.SLIDE * out * (1 - ret);
  tilt = 0.1 * Math.sin(Math.PI * seg(t, G.slide0, G.slide1)) - 0.1 * Math.sin(Math.PI * seg(t, G.back0, G.back1));
  const ant = Math.sin(Math.PI * seg(t, G.pop0 - 0.1, G.pop0));
  sy -= 0.08 * ant; y += D * 0.03 * ant; // 4 pop up
  const pop = EZ.back(seg(t, G.pop0, G.pop0 + 0.2)) * (1 - EZ.inOut(seg(t, G.back0, G.back0 + 0.2)));
  y -= hb * 0.16 * pop; sy += 0.07 * Math.sin(Math.PI * seg(t, G.pop0, G.pop0 + 0.2));
  const flail = 0.55 * (1 - seg(t, G.land - 0.05, G.land + 0.1)) * (t > G.fall0 ? 1 : 0); // paws up while falling
  const handL = flail, handR = Math.max(flail, pop);
  if (t >= G.wave0 && t < G.wave1 + 0.2) wave = t - G.wave0;
  if (t >= G.land && t < G.slide0) eye = "happy";
  if (t >= G.slide0 && t < G.pop0) lookX = 0.5 * out;
  if (t >= G.pop0 && t < G.back0) { eye = "happy"; lookX = 0.3; lookY = -0.4; }
  if (t >= G.back0) { const k = seg(t, G.back0, G.back1 + 0.1); eye = k < 0.9 ? "content" : "dot"; lookX = lerp(0.3, 0, EZ.inOut(k)); lookY = lerp(-0.4, 0, EZ.inOut(k)); }
  return {
    iw: B.iw, ih: B.ih, hb, x, y, sx, sy, tilt, eye, lookX, lookY, handL, handR, wave, open: B.open, badge: B.badge, tint: B.tint, halo: B.halo,
    haloBlue: B.haloBlue, header: B.header, card: B.card, fx: 1, minis: 0,
  };
}

/** From `tc` the island collapses to the compact notch and the cat settles, from wherever it is. */
function collapsePose(t: number, tc: number): GreetPose {
  const a = islandBase(tc), f = fallPose(tc, a), e = EZ.inOut(seg(t, tc, tc + GT.COLLAPSE)), bx = 320 - COMPACT / 2 + 40, bk = seg(t, tc + 0.14, tc + 0.26);
  const hands = 1 - seg(t, tc, tc + 0.15);
  return {
    iw: lerp(a.iw, COMPACT, e), ih: lerp(a.ih, 32, e), hb: lerp(f.hb, 20 / 1.34, e), x: lerp(f.x, bx, e), y: lerp(f.y, 16, e),
    sx: lerp(f.sx, 1, e), sy: lerp(f.sy, 1, e), tilt: f.tilt * (1 - e), eye: "dot", lookX: f.lookX * (1 - e), lookY: f.lookY * (1 - e),
    handL: f.handL * hands, handR: f.handR * hands, wave: -1,
    open: bk > 0 && bk < 1 ? 1 - Math.sin(Math.PI * bk) * 0.94 : 1, badge: a.badge, tint: a.tint, halo: a.halo * (1 - e), haloBlue: a.haloBlue,
    header: a.header * (1 - seg(t, tc, tc + 0.1)), card: a.card * (1 - seg(t, tc, tc + 0.18)), fx: 1 - seg(t, tc, tc + 0.2), minis: EZ.back(seg(t, tc + 0.24, tc + 0.42)),
  };
}

/** The greeting pose at t seconds. `leave` is when the island collapses (GT.leave unless the pointer left early). */
export const greetingPose = (t: number, leave = GT.leave): GreetPose => (t < leave ? fallPose(t, islandBase(t)) : collapsePose(t, leave));

// ── The controller and the drawing ────────────────────────────────────────────

/** The controller fires onComplete here (s). The collapse itself waits until GT.leave unless the pointer leaves first. */
export const GREETING_END = 4.6;

const CARD = { x: 10, y: 36, w: 620, h: 104 };
const CARD_R = 20;

function rr(x: CanvasRenderingContext2D, X: number, Y: number, W: number, H: number, R: number) {
  const r = Math.max(0, Math.min(R, W / 2, H / 2));
  x.beginPath(); x.moveTo(X + r, Y); x.arcTo(X + W, Y, X + W, Y + H, r); x.arcTo(X + W, Y + H, X, Y + H, r); x.arcTo(X, Y + H, X, Y, r); x.arcTo(X, Y, X + W, Y, r); x.closePath();
}

/**
 * Whether the greeting canvas is up: in the expanded island's greeting view, and then, after the island has folded, through the compact island's
 * tail until the last beat is over (`live`). Any other mode or view, the expanded overview or a hidden island included, ends it at once.
 */
export const greetingShown = (mode: IslandMode, view: IslandViewName, live: boolean): boolean =>
  (mode === "expanded" && view === "greeting") || (mode === "compact" && live);

/** Whether the greeting's big cat wears the outfit yet (sub-project I): once it has settled after its wave (`GT2.back1`), or as soon as the island folds (`leave`), whichever comes first. */
export const greetingDressed = (t: number, leave = GT.leave): boolean => t >= Math.min(GT2.back1, leave);

/** A session cat of the compact grid, in the greeting's blue: the tint the greeting ends with. */
function miniView(p: CatPreset): CatView {
  const v = stillView(p, { ...newPose(), tint: 0.6 });
  v.col = [...THEME_RGB.greeting.tint];
  return v;
}

/** The greeting cat's view: the pose is driven by the timeline, not by an engine. */
function greetView(id: string, eye: () => EyeShape, now: () => number): CatView {
  const v = stillView(catById(id), newPose());
  v.eyeShape = eye;
  v.badge = "dots";
  v.badgeCol = THEME.greeting.badge;
  v.col = [...THEME_RGB.greeting.tint];
  v.now = now;
  return v;
}

/**
 * Runs the greeting on its own canvas. `onComplete` fires once at GREETING_END (or right after the collapse when
 * interrupted) so the island's state machine can move on.
 */
export class Greeting {
  private startMs = 0;
  private tc = Number.POSITIVE_INFINITY;
  private fired = false;
  /** From start() until the last beat is over (or end()): the greeting canvas is up. */
  private running = false;
  private timers: number[] = [];
  private eye: EyeShape = "pill";
  private view: CatView;
  /** The Main cat's session view: a session cat with no pill of its own wears it. */
  private minis: CatView;
  /** The four session cats in the grid's cell order, each in the coat the cast gives its pill (the Main cat's when it has none), so the glide ends where the grid begins. */
  private sessionViews: CatView[];
  private readonly miniViews = new Map<string, CatView>();
  /** Two cats mode: the pair's second cat, which pops in beside the settled cat; null in the other modes. */
  private pairView: CatView | null = null;
  /** The outfit the big cats wear (State.outfit, resolved): the settled cat and cat 2 wear it; the session cats stay bare. */
  private outfit: string | null = null;
  private readonly now: () => number;

  onComplete: (() => void) | null = null;
  /** Fires once when the last beat is over, so the island can hand over to its own cat and grid. */
  onEnd: (() => void) | null = null;

  /** `now` is the clock in milliseconds, `performance.now` unless a test gives it another. */
  constructor(now: () => number = () => performance.now()) {
    this.now = now;
    this.view = greetView(DEFAULT_CAT, () => this.eye, now);
    this.minis = miniView(catById(DEFAULT_CAT));
    this.sessionViews = [this.minis, this.minis, this.minis, this.minis];
  }

  /** The session cat of a coat, made once per greeting. */
  private sessionView(id: string): CatView {
    let v = this.miniViews.get(id);
    if (!v) { v = miniView(catById(id)); this.miniViews.set(id, v); }
    return v;
  }

  /** `cast` is what the cast says the greeting wears (State.cast.greeting); without one, everything wears the chosen cat. */
  start(cast?: GreetingCast, outfit: string | null = null) {
    this.outfit = outfit;
    this.startMs = this.now();
    this.tc = Number.POSITIVE_INFINITY;
    this.fired = false;
    this.running = true;
    const main = cast ? cast.cat : catCfg.character ?? DEFAULT_CAT;
    this.view = greetView(main, () => this.eye, this.now);
    this.miniViews.clear();
    this.minis = this.sessionView(this.view.p.name);
    this.sessionViews = [0, 1, 2, 3].map((i) => this.sessionView(cast?.sessions[i] ?? main));
    this.pairView = cast?.pair ? this.sessionView(cast.pair[1]) : null;
    this.cancelTimers();
    this.timers.push(
      window.setTimeout(() => Sound.play("greet"), GT2.pop0 * 1000),
      window.setTimeout(() => Sound.play("blip"), GT.badge * 1000),
      window.setTimeout(() => this.fire(), (GREETING_END + 0.05) * 1000),
    );
  }

  /** Mouse entered the island during the greeting: hold it open. */
  hover() {
    if (this.tc >= GT.leave) this.tc = Number.POSITIVE_INFINITY;
  }

  /** Mouse left: collapse from now. */
  interrupt() {
    const t = (this.now() - this.startMs) / 1000;
    if (!Number.isFinite(this.tc) || this.tc > t) this.tc = t;
    this.cancelTimers();
  }

  get elapsed(): number { return (this.now() - this.startMs) / 1000; }
  get done(): boolean { return this.fired; }
  /** True from start() until the last beat is over: the island keeps this canvas up through the compact island's tail. */
  get live(): boolean { return this.running; }
  /** When the island starts to fold: GT.leave, or earlier when the pointer left. */
  private get leave(): number { return Number.isFinite(this.tc) ? Math.min(this.tc, GT.leave) : GT.leave; }
  /** The island left the compact mode before the last beat was over: it ends at once, silently (the island is already syncing). */
  end() {
    this.running = false;
    this.cancelTimers(); // the two sounds and the completion it still had to fire must not play for a greeting that is over
  }
  private finish() {
    this.running = false;
    this.onEnd?.();
  }

  private fire() {
    if (this.fired) return;
    this.fired = true;
    this.cancelTimers();
    this.onComplete?.();
  }
  private cancelTimers() {
    this.timers.forEach((id) => window.clearTimeout(id));
    this.timers = [];
  }

  draw(x: CanvasRenderingContext2D) {
    const t = this.elapsed;
    if (!this.fired && t >= GREETING_END && this.tc >= GT.leave) this.fire();
    const leave = this.leave;
    if (this.running && t >= leave + GT3.end) this.finish();
    const P = greetingPose(t, leave);
    x.clearRect(0, 0, 640, 150);

    if (P.card > 0) {
      x.save(); x.globalAlpha = P.card; rr(x, CARD.x, CARD.y, CARD.w, CARD.h, CARD_R); x.fillStyle = THEME.greeting.card; x.fill(); x.restore();
      x.save(); rr(x, CARD.x, CARD.y, CARD.w, CARD.h, CARD_R); x.clip();
      const st = streakTime(t);
      for (const sk of STREAKS) {
        const q = seg(st, sk.t0, sk.t0 + 0.6);
        if (q <= 0 || q >= 1) continue;
        const dist = sk.sp * EZ.out(q) * 0.9 + 10;
        x.strokeStyle = sk.col; x.globalAlpha = (1 - q) * P.fx; x.lineWidth = 1.6; x.lineCap = "round"; x.beginPath();
        x.moveTo(P.x + Math.cos(sk.a) * (dist - sk.len), P.y + Math.sin(sk.a) * (dist - sk.len) * 0.42);
        x.lineTo(P.x + Math.cos(sk.a) * dist, P.y + Math.sin(sk.a) * dist * 0.42);
        x.stroke();
      }
      x.restore();
    }

    const D = P.hb * 1.34;
    if (D <= 0.5) return;
    // Halo: golden, then blue, two passes for a soft aura.
    if (P.halo > 0) {
      const bl = P.haloBlue, gold = THEME_RGB.greeting.haloGold, blue = THEME_RGB.greeting.haloBlue, c = [0, 1, 2].map((i) => Math.round(lerp(gold[i], blue[i], bl)));
      for (const [rad, al] of [[D * 1.3, 0.18], [D * 2.1, 0.07]]) {
        const g = x.createRadialGradient(P.x, P.y, 0, P.x, P.y, rad);
        g.addColorStop(0, `rgba(${c},${al * P.halo})`); g.addColorStop(1, `rgba(${c},0)`);
        x.fillStyle = g; x.fillRect(P.x - rad, P.y - rad, rad * 2, rad * 2);
      }
    }

    // The header: the app's name on the left, a greeting on the right, fading in with the card.
    if (P.header > 0.01) {
      x.save(); x.globalAlpha = P.header; x.textBaseline = "middle";
      x.fillStyle = "#fff"; x.font = `600 13px ${FONT}`; x.textAlign = "left"; x.fillText("NotchMeow", 20, 20);
      x.fillStyle = THEME.greeting.headerDim; x.font = `11.5px ${FONT}`; x.textAlign = "right"; x.fillText(`Hi! ${this.view.p.label} is watching your agents.`, 620, 20);
      x.restore();
    }

    // The cat: the timeline drives the pose directly.
    const v = this.view, s = v.s;
    Object.assign(s, { sx: P.sx, sy: P.sy, tilt: P.tilt, open: P.open, yaw: P.lookX * 0.55, pitch: -P.lookY * 0.45, roll: 0, oy: 0, ox: 0, badgeS: P.badge, tint: P.tint, paws: 0 });
    this.eye = P.eye === "happy" ? "happy" : P.eye === "content" ? "closed" : "pill";
    const R = D / (2 * v.p.rx), rx = v.p.rx * R, ry = v.p.ry * R;
    const on = P.wave >= 0, w = on ? P.wave * TAU * 4.2 : 0, wa = on ? seg(P.wave, 0, 0.12) * (1 - seg(P.wave, 0.9, 1.0)) : 0;
    const paws: PawSpec[] = [
      { x: lerp(-0.35 * rx, -(rx + 0.22 * R), P.handL), y: lerp(0.85 * ry, 0.62 * ry, P.handL), k: P.handL, rot: -0.2, beans: false },
      { x: lerp(0.35 * rx, rx + 0.2 * R, P.handR) + Math.cos(w) * ry * 0.05 * wa, y: lerp(0.85 * ry, 0.05 * ry, P.handR) + Math.sin(w + 0.8) * ry * 0.1 * wa, k: P.handR, rot: 0.3 + Math.sin(w) * 0.45 * wa, beans: true },
    ];
    // Two cats: the settled cat makes room (it ends where the real pair's first cat sits), and the second cat pops in beside it as the island folds.
    const fold = EZ.inOut(seg(t, leave, leave + GT.COLLAPSE)), room = this.pairView ? -(40 - PAIR.compact.x1) * fold : 0;
    // The canvas's top edge is the screen's top: a hat is held under it (`outfitCeiling`), and the ears are left as the greeting always drew them.
    drawCat(x, v, P.x + room, P.y, D, { paws, badgeSide: 1 - 2 * fold, outfit: greetingDressed(t, leave) ? this.outfit : null, outfitCeiling: 0 });
    if (this.pairView) {
      const pop = EZ.back(seg(t, leave + 0.24, leave + 0.42));
      if (t > leave && pop > 0.02) drawCat(x, this.pairView, 320 - COMPACT / 2 + PAIR.compact.x2, 16, PAIR.compact.d * pop, { badge: false, outfit: this.outfit, outfitCeiling: 0 });
    }

    // The session cats: a row of three pops in as the island collapses, then glides into the compact island's 2×2 grid, where a fourth pops in.
    // Every slot carries its own pop and scale (the contract's miniSlots); the real grid takes over when the last beat is over.
    miniSlots(P.minis, miniGlide(t, leave), { W: COMPACT, H: NOTCH.H, d: MINI_GRID.d }).forEach((s, i) => {
      if (s.d < MINI_MIN_D) return;
      x.save(); x.translate(s.x, s.y);
      drawCat(x, this.sessionViews[i] ?? this.minis, 0, 0, s.d, { badge: false });
      x.restore();
    });
  }
}
