// The desktop cat (sub-project H): the big cat leaves the notch and lives on the desktop. These are the pure rules of it, a port of "The desktop cat" in
// design/prototype/cat-core.js (the tie-breaker; fixture tests/fixtures/cat/desktop-cases.json; docs/CAT-CONTRACT.md "The desktop cat (H-0)"): the trip `desktopStep`
// (seven phases) and the flight `desktopFlightAt`, the sizes, the frame rate `desktopFps`, the kittens' slots `desktopKittenSlots`, the spots on the screens
// (`screenKey`, `clampSpot`, `spotFor`, `rememberSpot`) and the stored settings `cleanDesktopSettings`. All new names: nothing in the older rules changes. Pure: no clock,
// no DOM, nothing is changed in place, and every function takes input of any shape and never throws. A spot is the head centre in points, y down, the origin at the top left of
// the main screen. Imports base.ts only, so the plain-Node checks (npm run check:cat) can load it.

import { EZ, clamp, own } from "./base.ts";

const isPlain = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);
const isKittenId = (v: unknown): v is string => typeof v === "string" && v.length > 0 && v.length <= 128;

// ── The trip ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

/** The seven phases of the trip. Frozen contract values, like the cat IDs. */
export const DESKTOP_PHASES = ["home", "flyingOut", "onDesktop", "retracting", "atNotchForAlert", "returning", "flyingHome"] as const;
export type DesktopPhase = (typeof DESKTOP_PHASES)[number];

export interface DesktopPhaseInfo { flight: boolean; dir: "out" | "in" | null; drawn: boolean; notchEmpty: boolean; on: boolean }
/** What a phase means to the app: in the air or not, which way it flies, whether the desktop window draws the cat, whether the notch's big-cat spot is empty, and whether Settings stores "out". */
export const DESKTOP_PHASE_INFO: Readonly<Record<DesktopPhase, DesktopPhaseInfo>> = {
  home: { flight: false, dir: null, drawn: false, notchEmpty: false, on: false },
  flyingOut: { flight: true, dir: "out", drawn: true, notchEmpty: true, on: true },
  onDesktop: { flight: false, dir: null, drawn: true, notchEmpty: true, on: true },
  retracting: { flight: true, dir: "in", drawn: true, notchEmpty: true, on: true },
  atNotchForAlert: { flight: false, dir: null, drawn: false, notchEmpty: false, on: true },
  returning: { flight: true, dir: "out", drawn: true, notchEmpty: true, on: true },
  flyingHome: { flight: true, dir: "in", drawn: true, notchEmpty: true, on: false },
};

export const DESKTOP_EVENTS = ["dragOut", "move", "toggle", "sendHome", "alertOn", "alertOff", "flightDone", "launch", "screensChanged"] as const;
export type DesktopEventType = (typeof DESKTOP_EVENTS)[number];
/** An event for the machine; `dragOut` and `move` carry the `spot` the cat was released at. */
export type DesktopEvent = { type: DesktopEventType; spot?: Spot };

export const DESKTOP_ACTS = ["place", "flyOut", "flyHome", "retract", "turn", "keep", "land", "dock", "goHome", "move", "resettle"] as const;
export type DesktopAct = (typeof DESKTOP_ACTS)[number];

/** phase, then event, then [next phase, act]. An event that is not listed makes no sense in that phase and changes nothing. */
export const DESKTOP_NEXT: Readonly<Record<DesktopPhase, Readonly<Partial<Record<DesktopEventType, readonly [DesktopPhase, DesktopAct]>>>>> = {
  home: { dragOut: ["onDesktop", "place"], toggle: ["flyingOut", "flyOut"], launch: ["flyingOut", "flyOut"] },
  flyingOut: { toggle: ["flyingHome", "turn"], sendHome: ["flyingHome", "turn"], alertOn: ["retracting", "turn"], flightDone: ["onDesktop", "land"], screensChanged: ["flyingOut", "resettle"] },
  onDesktop: { move: ["onDesktop", "move"], toggle: ["flyingHome", "flyHome"], sendHome: ["flyingHome", "flyHome"], alertOn: ["retracting", "retract"], screensChanged: ["onDesktop", "resettle"] },
  retracting: { toggle: ["flyingHome", "keep"], sendHome: ["flyingHome", "keep"], alertOff: ["returning", "turn"], flightDone: ["atNotchForAlert", "dock"] },
  atNotchForAlert: { toggle: ["home", "goHome"], sendHome: ["home", "goHome"], alertOff: ["returning", "flyOut"] },
  returning: { toggle: ["flyingHome", "turn"], sendHome: ["flyingHome", "turn"], alertOn: ["retracting", "turn"], flightDone: ["onDesktop", "land"], screensChanged: ["returning", "resettle"] },
  flyingHome: { toggle: ["flyingOut", "turn"], flightDone: ["home", "dock"] },
};

export interface Spot { x: number; y: number }
const SPOT_LIMIT = 1e5;
/** A spot is {x, y} of finite numbers no larger than 100000 in size; anything else is not a spot (null). The result has only x and y. */
export const spotOf = (v: unknown): Spot | null => (isPlain(v) && typeof v.x === "number" && typeof v.y === "number" && Math.abs(v.x) <= SPOT_LIMIT && Math.abs(v.y) <= SPOT_LIMIT ? { x: v.x, y: v.y } : null);

export interface DesktopStep { state: DesktopPhase; act: DesktopAct | null }

/** The trip's machine: `state` is a phase (anything else counts as home), `ev` an event. The next phase and what the app does, or the same phase and `act: null` when the event makes no sense there. */
export function desktopStep(state: unknown, ev: unknown): DesktopStep {
  const s: DesktopPhase = (DESKTOP_PHASES as readonly unknown[]).includes(state) ? (state as DesktopPhase) : "home";
  const same: DesktopStep = { state: s, act: null };
  if (!isPlain(ev) || typeof ev.type !== "string" || !own(DESKTOP_NEXT[s], ev.type)) return same;
  if ((ev.type === "dragOut" || ev.type === "move") && !spotOf(ev.spot)) return same;
  const [next, act] = DESKTOP_NEXT[s][ev.type as DesktopEventType] as readonly [DesktopPhase, DesktopAct];
  return { state: next, act };
}

/** The flight between the notch spot and the desktop spot takes this long (ms). */
export const DESKTOP_FLIGHT_MS = 600;
/** The arc bows `lift` of the distance away from the straight line, never more than `max` points, always upwards (a vertical flight bows to the right). */
export const DESKTOP_ARC = { lift: 0.25, max: 90 } as const;

/** Where the cat is `t` of the way along a flight (held to 0..1, a `t` that is not a number is 0): the position and scale 1 (the cat keeps its full size). The path is the same both ways. */
export function desktopFlightAt(from: unknown, to: unknown, t: unknown): { x: number; y: number; scale: number } {
  const f = spotOf(from) ?? { x: 0, y: 0 }, g = spotOf(to) ?? { x: 0, y: 0 };
  const k = typeof t === "number" && !Number.isNaN(t) ? clamp(t, 0, 1) : 0, q = EZ.inOut(k);
  const dx = g.x - f.x, dy = g.y - f.y, len = Math.hypot(dx, dy);
  let nx = 0, ny = 0;
  if (len > 0) { nx = dy / len; ny = -dx / len; if (ny > 0 || (ny === 0 && nx < 0)) { nx = -nx; ny = -ny; } }
  const lift = Math.min(len * DESKTOP_ARC.lift, DESKTOP_ARC.max), cx = (f.x + g.x) / 2 + nx * lift, cy = (f.y + g.y) / 2 + ny * lift, u = 1 - q;
  return { x: u * u * f.x + 2 * u * q * cx + q * q * g.x, y: u * u * f.y + 2 * u * q * cy + q * q * g.y, scale: 1 };
}

// ── Size, frame rate and kittens ────────────────────────────────────────────────────────────────────────────────────────────────────────

/** The three sizes, as the head width in points. The IDs are frozen contract values; `medium` is the default. */
export const DESKTOP_SIZES = { small: 48, medium: 64, large: 96 } as const;
export const DESKTOP_SIZE_IDS = ["small", "medium", "large"] as const;
export type DesktopSizeId = (typeof DESKTOP_SIZE_IDS)[number];
export const DEFAULT_DESKTOP_SIZE: DesktopSizeId = "medium";
/** A stored size to one of the three IDs; anything else, the case and the type included, is `medium`. */
export const desktopSizeOf = (v: unknown): DesktopSizeId => ((DESKTOP_SIZE_IDS as readonly unknown[]).includes(v) ? (v as DesktopSizeId) : DEFAULT_DESKTOP_SIZE);

/** The frame rates (per second): `asleep` is one still frame every 2 s, `off` draws nothing. */
export const DESKTOP_FPS = { motion: 60, active: 20, idle: 5, asleep: 0.5, off: 0 } as const;
/** The cursor is "near" the cat within this many points of the cat's centre. */
export const DESKTOP_NEAR = 150;

/** What the frame rate depends on; leave `cursorDist` out when the app cannot know it (Wayland). Only `true` counts for a flag. */
export interface DesktopFpsInput {
  phase: DesktopPhase; hidden?: boolean; dragging?: boolean; emote?: boolean; kittenMotion?: boolean; dance?: boolean; asleep?: boolean; working?: boolean; cursorDist?: number;
}
/** The frame rate to aim for: 0 when the phase is not drawn on the desktop or the cat is hidden; 60 for any motion (a flight included); 0.5 asleep; 20 working or the cursor near; else 5. */
export function desktopFps(i: unknown): number {
  if (!isPlain(i) || !(DESKTOP_PHASES as readonly unknown[]).includes(i.phase)) return DESKTOP_FPS.off;
  const info = DESKTOP_PHASE_INFO[i.phase as DesktopPhase];
  if (!info.drawn || i.hidden === true) return DESKTOP_FPS.off;
  if (info.flight || i.dragging === true || i.emote === true || i.kittenMotion === true || i.dance === true) return DESKTOP_FPS.motion;
  if (i.asleep === true) return DESKTOP_FPS.asleep;
  if (i.working === true || (typeof i.cursorDist === "number" && Number.isFinite(i.cursorDist) && i.cursorDist <= DESKTOP_NEAR)) return DESKTOP_FPS.active;
  return DESKTOP_FPS.idle;
}

/** Where the desktop cat's kittens sit, in D (the head width) from its head centre, x right, y down: up to 3 in a row at the lower right, then "+N" at the next slot. */
export const DESKTOP_KITTEN_PLACE = { unit: "D", max: 3, d: 0.3, x0: 0.82, y0: 0.22, step: 0.33, moreSize: 0.2 } as const;

export interface DesktopKittenSlots {
  place: "desktop"; unit: "D"; count: number; shown: { id: string; state: string; x: number; y: number; d: number }[]; more: number; moreAt: { x: number; y: number; size: number } | null; label: null;
}
/** The slots for the cat's kittens (`kittens` is what kittenView returned, already in order). `side` -1 mirrors every x (a cat in the right half of its screen); anything else is 1. */
export function desktopKittenSlots(kittens: unknown, side?: unknown): DesktopKittenSlots {
  const P = DESKTOP_KITTEN_PLACE, m = side === -1 ? -1 : 1;
  const L = (Array.isArray(kittens) ? kittens : []).filter((k): k is Record<string, unknown> => isPlain(k) && isKittenId(k.id)), count = L.length, n = Math.min(count, P.max), more = count - n;
  return {
    place: "desktop", unit: "D", count,
    shown: L.slice(0, n).map((k, i) => ({ id: k.id as string, state: typeof k.state === "string" ? k.state : "working", x: m * (P.x0 + i * P.step), y: P.y0, d: P.d })),
    more, moreAt: more > 0 ? { x: m * (P.x0 + P.max * P.step), y: P.y0, size: P.moreSize } : null, label: null,
  };
}

// ── Spots on the screens ────────────────────────────────────────────────────────────────────────────────────────────────────────────────

/** The cat keeps this many points between its head and the edge of the visible frame. */
export const DESKTOP_MARGIN = 24;
/** The first spot ever: this fraction of the main screen's visible frame across and down. */
export const DESKTOP_DEFAULT = { x: 0.6, y: 1 / 3 } as const;
/** A stored map keeps the spots of at most this many screen arrangements. */
export const MAX_DESKTOP_SPOTS = 32;

export interface Rect { x: number; y: number; w: number; h: number }
/** A screen: `frame` the whole screen, `visible` what the menu bar and the taskbar leave, `main` the screen with the primary taskbar. In points, y down. */
export interface Screen { frame: Rect; visible: Rect; main: boolean }

const rectOf = (v: unknown): Rect | null => (isPlain(v) && ["x", "y", "w", "h"].every((k) => typeof v[k] === "number" && Math.abs(v[k] as number) <= 1e6) && (v.w as number) >= 1 && (v.h as number) >= 1 ? { x: v.x as number, y: v.y as number, w: v.w as number, h: v.h as number } : null);
/** The screens that are screens, sorted by frame and at most 16; a visible frame that is missing or outside its frame is the frame. */
function screensOf(raw: unknown): Screen[] {
  const out: Screen[] = [];
  for (const s of Array.isArray(raw) ? raw.slice(0, 256) : []) {
    const f = isPlain(s) ? rectOf(s.frame) : null;
    if (!f) continue;
    const v = rectOf((s as Record<string, unknown>).visible), x0 = v ? Math.max(v.x, f.x) : 0, y0 = v ? Math.max(v.y, f.y) : 0, x1 = v ? Math.min(v.x + v.w, f.x + f.w) : 0, y1 = v ? Math.min(v.y + v.h, f.y + f.h) : 0;
    out.push({ frame: f, visible: v && x1 > x0 && y1 > y0 ? { x: x0, y: y0, w: x1 - x0, h: y1 - y0 } : f, main: (s as Record<string, unknown>).main === true });
  }
  return out.sort((a, b) => a.frame.x - b.frame.x || a.frame.y - b.frame.y || a.frame.w - b.frame.w || a.frame.h - b.frame.h).slice(0, 16);
}
const roundHalfUp = (v: number) => Math.floor(v + 0.5);

/** The key an arrangement of screens is remembered under: the frames rounded to whole points (half up), sorted, written `x,y,w,h` and joined with `|`; no usable screen is "". */
export function screenKey(screens: unknown): string {
  return screensOf(screens).map((s) => [s.frame.x, s.frame.y, s.frame.w, s.frame.h].map(roundHalfUp)).sort((a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2] || a[3] - b[3]).map((r) => r.join(",")).join("|");
}
const SCREEN_KEY = /^-?\d{1,7},-?\d{1,7},\d{1,7},\d{1,7}(\|-?\d{1,7},-?\d{1,7},\d{1,7},\d{1,7}){0,15}$/;
/** True for exactly the strings screenKey writes: the whole-string shape, no leading zeros or -0, positive sizes, frames in sorted order, at most 16. */
export const isScreenKey = (k: unknown): k is string =>
  typeof k === "string" && SCREEN_KEY.test(k) && screenKey(k.split("|").map((q) => { const [x, y, w, h] = q.split(",").map(Number); return { frame: { x, y, w, h } }; })) === k;

const holds = (r: Rect, p: Spot) => p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h;
const mainScreen = (S: Screen[]): Screen => S.find((s) => s.main) ?? S.find((s) => holds(s.frame, { x: 0, y: 0 })) ?? S[0];
/** The spot held inside a screen's visible frame, `d` (the head width) and DESKTOP_MARGIN from every edge; a frame too small for that holds the centre. */
function place(s: Screen, p: Spot, d: number): Spot {
  const v = s.visible, m = DESKTOP_MARGIN + d / 2, at = (lo: number, len: number, c: number) => (len <= 2 * m ? lo + len / 2 : clamp(c, lo + m, lo + len - m));
  return { x: at(v.x, v.w, p.x), y: at(v.y, v.h, p.y) };
}

/** The first spot ever, on the main screen, for a size ID. null with no screens. */
export function defaultDesktopSpot(screens: unknown, size?: unknown): Spot | null {
  const S = screensOf(screens);
  if (!S.length) return null;
  const s = mainScreen(S), v = s.visible;
  return place(s, { x: v.x + v.w * DESKTOP_DEFAULT.x, y: v.y + v.h * DESKTOP_DEFAULT.y }, DESKTOP_SIZES[desktopSizeOf(size)]);
}

/** Keeps a spot where the cat may sit: on the screen whose frame holds it, inside that screen's visible frame, 24 points from the head's edge. A spot on no screen goes to the main screen's default spot; null with no screens. */
export function clampSpot(spot: unknown, screens: unknown, size?: unknown): Spot | null {
  const S = screensOf(screens);
  if (!S.length) return null;
  const p = spotOf(spot), s = p && S.find((q) => holds(q.frame, p));
  return s && p ? place(s, p, DESKTOP_SIZES[desktopSizeOf(size)]) : defaultDesktopSpot(screens, size);
}

/** A stored map from screen key to spot, cleaned: an object or its JSON text, only keys isScreenKey accepts, only values that are spots, in code-point order of the keys, the first 32. */
export function cleanDesktopSpots(raw: unknown): Record<string, Spot> {
  let v = raw;
  if (typeof v === "string") { try { v = JSON.parse(v); } catch { return {}; } }
  const out: Record<string, Spot> = {};
  if (!isPlain(v)) return out;
  let n = 0;
  for (const k of Object.keys(v).filter(isScreenKey).sort()) {
    if (n >= MAX_DESKTOP_SPOTS) break;
    const s = spotOf(v[k]);
    if (s) { out[k] = s; n++; }
  }
  return out;
}

/** The spot to use now: the one remembered for this arrangement, held where the cat may sit, else the default spot. null with no screens. */
export function spotFor(spots: unknown, screens: unknown, size?: unknown): Spot | null {
  if (!screensOf(screens).length) return null;
  const k = screenKey(screens), m = cleanDesktopSpots(spots);
  return own(m, k) ? clampSpot(m[k], screens, size) : defaultDesktopSpot(screens, size);
}

/** The map after the cat was released at `spot` on these screens: this arrangement's spot is the clamped one, the others stay, and the new key is always kept. */
export function rememberSpot(spots: unknown, screens: unknown, spot: unknown, size?: unknown): Record<string, Spot> {
  const m = cleanDesktopSpots(spots), c = clampSpot(spot, screens, size);
  if (!c) return m;
  const k = screenKey(screens), out: Record<string, Spot> = {};
  for (const q of Object.keys(m).filter((q) => q !== k).slice(0, MAX_DESKTOP_SPOTS - 1).concat(k).sort()) out[q] = q === k ? c : m[q];
  return out;
}

// ── The stored settings ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────

/** What the cat's menu and Settings save: whether it is out, its size, and its spot for each arrangement of screens. In settings.json it is the `desktop` object of the `cat` block. */
export interface DesktopSettings { on: boolean; size: DesktopSizeId; spots: Record<string, Spot> }

/** Everything the desktop cat saves, cleaned: `on` is true only for the boolean true, `size` one of the three IDs, `spots` as cleanDesktopSpots. Raw in, clean out, never a throw. */
export function cleanDesktopSettings(raw: unknown): DesktopSettings {
  const r: Record<string, unknown> = isPlain(raw) ? raw : {};
  return { on: r.on === true, size: desktopSizeOf(r.size), spots: cleanDesktopSpots(r.spots) };
}
/** What a fresh install holds: the cat at home, Medium, no spots. */
export const defaultDesktopSettings = (): DesktopSettings => cleanDesktopSettings(null);

// ── The file catch (fixes after H) ─────────────────────────────────────────────

/** How long a dropped file waits for the desktop cat to be at the notch (ms) before the catch plays anyway. */
export const DESKTOP_CATCH_WAIT_MS = 1500;

/**
 * Whether something wants the desktop cat at the notch: an approval, a question, a chat's approval card, a pill whose state is "approval" or "question" (`pillStates`), a file on its way
 * into the island (`fileCatch`: dragged over it, waiting for the cat, or its drop flow on screen), or a file another machine offers on the link (`transferOffer`: the Accept card). A flag counts only when it is exactly `true`; input that is not an object is no alert. To the
 * trip it is `alertOn` / `alertOff`: the file catch adds no phase, event or act.
 */
export function desktopAlert(input: unknown): boolean {
  const o: Record<string, unknown> = isPlain(input) ? input : {};
  return o.approval === true || o.question === true || o.chatApproval === true || o.fileCatch === true || o.transferOffer === true
    || (Array.isArray(o.pillStates) && o.pillStates.some((s) => s === "approval" || s === "question"));
}

/** Whether the big cat is at the notch, so the island may draw it and a catch may play with it: home and atNotchForAlert, the phases the desktop window does not draw. Not a phase: home. */
export function desktopCatchReady(phase: unknown): boolean {
  const p: DesktopPhase = (DESKTOP_PHASES as readonly unknown[]).includes(phase) ? (phase as DesktopPhase) : "home";
  return !DESKTOP_PHASE_INFO[p].notchEmpty;
}
