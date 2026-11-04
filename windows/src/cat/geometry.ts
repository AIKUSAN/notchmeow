// The cat's geometry: the neutral pose, the head turn (face warp), the outline, and where everything
// sits on the head. A port of the geometry section of design/prototype/cat-core.js, the tie-breaker.
// Numbers in, numbers out: no canvas here, so the plain-Node checks (npm run check:cat) can load it.
// Units are R, the head radius, unless a name says px.

import { TAU, clamp, hex, lerp, wrapA, EZ } from "./base.ts";
import type { CatPreset, Pose } from "./types.ts";

/** The neutral pose: every animatable property at rest. The engine's `s` starts here, and layout() reads one. */
export const newPose = (): Pose => ({
  yaw: 0, pitch: 0, roll: 0, tilt: 0, open: 1, sx: 1, sy: 1, oy: 0, ox: 0, tint: 0, blush: 0, es: 1, badgeS: 0,
  earL: 0, earR: 0, earU: 1, earF: 0, pupil: 0.45, mouth: 0, purr: 0, lid: 0, lift: 0, wh: 0, paws: 0,
  smile: 0, tongue: 0, mround: 0, mskew: 0, wavy: 0,
});

/**
 * Head turn toward the cursor. The face is a real 3D rotation of the head ellipsoid, with the muzzle
 * standing proud of it so it swings further than the cheeks, and the head outline leans into the turn.
 * yaw/pitch are the share of upstream's 0.62/0.5 rad gaze the face takes; the pupils carry the rest.
 */
export const FACE = { yaw: 0.82, pitch: 0.6, pitchDown: 0.32, lean: 0.08, bend: 0.1, muzzle: 0.12, nose: 0.05 };

/** Head width D (px) from which the full cat is drawn; below it the compact drawing (ink eyes, no irises, stripes or whiskers). */
export const DETAIL_FULL_MIN = 28;
export const detailOf = (D: number): "full" | "compact" => (D >= DETAIL_FULL_MIN ? "full" : "compact");

/**
 * Ear scale for the compact drawing, so the ears keep their headroom in the compact notch:
 * 1 from Ø28 up, easing down to COMPACT_EAR_SCALE at Ø20 and below.
 * PROVISIONAL: the spec only says "ears scaled down at Ø20"; the owner confirms the value on the
 * stage-1 contact sheet. If the owner changes it, the main session changes it once in cat-core.js and
 * regenerates the fixtures, this branch merges that, and this constant is set to the same number
 * (the geometry check fails until it is). This file never decides the value.
 */
export const COMPACT_EAR_SCALE = 0.8;
export const earScale = (D: number): number =>
  D >= DETAIL_FULL_MIN ? 1 : lerp(COMPACT_EAR_SCALE, 1, clamp((D - 20) / (DETAIL_FULL_MIN - 20), 0, 1));

/** Outline sample count: small heads (R under 20 px) use fewer points. */
export const outlineSteps = (R: number): number => (R < 20 ? 72 : 200);

/** The badge sits beside the right ear, and moves to the left in the compact notch so it never sits under the camera housing. */
export const badgeSide = (compactNotch: boolean): 1 | -1 => (compactNotch ? -1 : 1);

// ── Detail level and the flat fills (A-0b, merged `6adf584`: detailLevel, FLAT_FILL, mixHex and flatFillColors of cat-core.js) ──

/**
 * What the renderer draws at head width D: `detail`, `full`, and `flatFill`, which is on exactly when the cat is compact (below Ø28), that is
 * `!layout().full`. `override` is layout()'s `detail` option: an explicit "full" or "compact" wins over D.
 */
export interface DetailLevel { detail: "full" | "compact"; full: boolean; flatFill: boolean }
export const detailLevel = (D: number, override?: "full" | "compact" | null): DetailLevel => {
  const full = override ? override === "full" : D >= DETAIL_FULL_MIN;
  return { detail: full ? "full" : "compact", full, flatFill: !full };
};

/**
 * The flat drawing, for when detailLevel().flatFill is on. At Ø12 to Ø27 a gradient cannot be seen and costs a shading pass each, so:
 *   head: one fill, the preset's top and bot colour mixed headMix of the way (0.5, halfway);
 *   ears: one fill each, the ear's top and bot colour (the ear's own colour, if it has one, is both) mixed earMix of the way;
 *   ruff: one fill, the ruff's inner colour mixed ruffMix of the way (0.6) to its outer one;
 *   rim:  no rim gradient (rimGradient false). The white rim line of the dark coats stays;
 *   tabby crown band: one ellipse, radii crown.rx and crown.ry in R, at the centre where the gradient was, in the stripe colour at crown.alpha;
 *   point mask: one ellipse, radii point.rx and point.ry in R, at the centre where the gradient was, in the point colour at point.alpha.
 *     Tuned to the gradient it replaces (the same total ink, an edge between its half-strength and quarter-strength contours): 0.86 R by 0.54 R,
 *     not the Mac draft's 0.5 by 0.34, which was visibly smaller at Ø20.
 * Everything else (markings, eyes, blush, the state tint) is drawn as in the full cat.
 */
export const FLAT_FILL = { headMix: 0.5, earMix: 0.5, ruffMix: 0.6, rimGradient: false, crown: { rx: 0.4, ry: 0.26, alpha: 0.5 }, point: { rx: 0.86, ry: 0.54, alpha: 0.85 } };

/** `a` mixed `t` of the way to `b`, per channel on the 0 to 255 values (not rounded). */
export const mixHex = (a: string, b: string, t: number): number[] => {
  const y = hex(b);
  return hex(a).map((v, i) => lerp(v, y[i], t));
};

/** The flat colours of a preset, [r, g, b] in 0 to 255 (not rounded): the head, the two ears (left, right), the ruff (null without one) and the point mask (null unless the coat is "point"). */
export interface FlatColors { head: number[]; ears: [number[], number[]]; ruff: number[] | null; point: number[] | null }
export function flatFillColors(p: CatPreset): FlatColors {
  const ear = (sd: number) => {
    const c = p.earCols && p.earCols[sd < 0 ? 0 : 1];
    return mixHex(c || p.top, c || p.bot, FLAT_FILL.earMix);
  };
  return {
    head: mixHex(p.top, p.bot, FLAT_FILL.headMix),
    ears: [ear(-1), ear(1)],
    ruff: p.ruff ? mixHex(p.ruff.col[1], p.ruff.col[0], FLAT_FILL.ruffMix) : null,
    point: p.coat === "point" ? hex(p.point!) : null,
  };
}

/** Cursor to gaze: how far the cursor is from the cat in px, to -1…1 (tanh over 240 px across, 180 px up and down). */
export const CURSOR = { x: 240, y: 180 };
export const cursorLook = (dx: number, dy: number) => ({ x: Math.tanh(dx / CURSOR.x), y: -Math.tanh(dy / CURSOR.y) });

/** Pupil travel inside the eye: up to 0.24 of the eye width across and 0.18 of its height up and down. */
export const pupilOffset = (yaw: number, pitch: number, w: number, h: number): [number, number] => [
  clamp(yaw / 0.62, -1, 1) * 0.24 * w,
  -clamp(pitch / 0.5, -1, 1) * 0.18 * h,
];

/** The share of the gaze the face takes (FACE) and the roll fade: yf, pf, the warp pitch pt and the face opacity fa. */
export function faceAngles(s: Pick<Pose, "yaw" | "pitch" | "lift" | "roll">) {
  const yf = s.yaw * FACE.yaw;
  const pf = s.pitch * (s.pitch > 0 ? FACE.pitch : FACE.pitchDown);
  const pt = wrapA(pf + s.lift + s.roll);
  return { yf, pf, pt, fa: clamp((Math.cos(pt) - 0.05) / 0.3, 0, 1) };
}

/**
 * Superellipse outline as points [x, y], optionally with a fluffy edge (spike) on the lower half.
 * The fluff is a fixed sum of sines, so it needs no random numbers and is identical everywhere.
 */
export function supPoints(
  rx: number, ry: number, n: number, dy: number, spike: number, count: number, steps = 200,
  bend: readonly [number, number] | null = null,
): [number, number][] {
  const e = 2 / n;
  const pts: [number, number][] = [];
  for (let i = 0; i <= steps; i++) {
    const a = (i / steps) * TAU, c = Math.cos(a), s = Math.sin(a);
    let k = 1;
    if (spike) {
      const low = Math.max(0, s + 0.55) / 1.55;
      const vary = 0.55 + 0.45 * Math.sin(a * 5.3 + 1.1) * Math.sin(a * 2.7 + 0.4);
      k += low * spike * vary * Math.pow(Math.abs(Math.cos(a * count)), 1.8);
    }
    let x = Math.sign(c) * Math.pow(Math.abs(c), e) * rx * k;
    let y = Math.sign(s) * Math.pow(Math.abs(s), e) * ry * k + dy;
    if (bend) {
      const tx = x / rx, ty = y / ry;
      x += bend[0] * rx * Math.max(0, 1 - ty * ty);
      y += bend[1] * ry * Math.max(0, 1 - tx * tx);
    }
    pts.push([x, y]);
  }
  return pts;
}

export type Warp = (x: number, y: number) => [number, number];

/**
 * Face warp: maps a point drawn on the flat front view (units of R) onto the head ellipsoid rotated by
 * yaw and pitch, so markings, whisker pads and the muzzle turn with the eyes. Points outside the head
 * outline stay put. Identity at rest, so the rest pose matches the board exactly.
 */
export function mkWarp(p: Pick<CatPreset, "rx" | "ry" | "nosePh">, yaw: number, pt: number, R: number): Warp {
  const a = p.rx, b = p.ry, vm = Math.sin(p.nosePh) - 0.12;
  if (Math.abs(yaw) < 1e-4 && Math.abs(pt) < 1e-4) return (x, y) => [x * R, y * R];
  const cY = Math.cos(yaw), sY = Math.sin(yaw), cP = Math.cos(pt), sP = Math.sin(pt);
  return (x, y) => {
    const u = x / a, v = -y / b, q = 1 - u * u - v * v;
    if (q <= 0) return [x * R, y * R];
    const du = u / 0.55, dv = (v - vm) / 0.45;
    const w = Math.sqrt(q) + FACE.muzzle * Math.exp(-(du * du + dv * dv));
    const u1 = u * cY + w * sY, w1 = w * cY - u * sY, v1 = v * cP + w1 * sP;
    return [u1 * a * R, -v1 * b * R];
  };
}

/** A path command in units of R: Move, Quadratic curve, Line. */
export type PathCmd = readonly ["M", number, number] | readonly ["Q", number, number, number, number] | readonly ["L", number, number];

/** Flattens M/Q/L commands (units of R) into a dense point list, so the warp can bend every edge. */
export function flatten(cmds: readonly PathCmd[]): [number, number][] {
  const out: [number, number][] = [];
  let px = 0, py = 0;
  for (const c of cmds) {
    if (c[0] === "M") { px = c[1]; py = c[2]; out.push([px, py]); }
    else if (c[0] === "Q") {
      for (let i = 1; i <= 10; i++) {
        const t = i / 10, m = 1 - t;
        out.push([m * m * px + 2 * m * t * c[1] + t * t * c[3], m * m * py + 2 * m * t * c[2] + t * t * c[4]]);
      }
      px = c[3]; py = c[4];
    } else {
      for (let i = 1; i <= 8; i++) {
        const t = i / 8;
        out.push([px + (c[1] - px) * t, py + (c[2] - py) * t]);
      }
      px = c[1]; py = c[2];
    }
  }
  return out;
}

/** Momo's white map (blaze, muzzle, chin and chest), flattened so it can be warped onto the turning head. */
export const MOMO_WHITE = flatten([
  ["M", 0, -0.6], ["Q", -0.13, -0.4, -0.17, -0.12], ["Q", -0.19, 0.1, -0.26, 0.2], ["Q", -0.5, 0.38, -0.8, 0.36],
  ["L", -1.3, 0.3], ["L", -1.3, 1.3], ["L", 1.3, 1.3], ["L", 1.3, 0.3], ["L", 0.8, 0.36], ["Q", 0.5, 0.38, 0.26, 0.2],
  ["Q", 0.19, 0.1, 0.17, -0.12], ["Q", 0.13, -0.4, 0, -0.6],
]);

/** One ear, in head-local px before tilt and squash. `ek` is the compact ear scale (earScale), 1 when not compact. */
export function earGeom(p: CatPreset, s: Pose, sd: number, R: number, yf: number, pf: number, ek = 1) {
  const E = p.ear, rx = p.rx * R, ry = p.ry * R, th = sd * 0.6 + yf * 0.85, f = Math.max(0.3, Math.cos(th));
  return {
    bx: Math.sin(th) * p.earSpread * rx + Math.sin(yf) * FACE.bend * 0.54 * rx,
    by: -0.68 * ry - Math.sin(pf + s.lift) * 0.12 * ry,
    rot: sd * (E.rot + (sd < 0 ? s.earL : s.earR) + 0.95 * s.earF),
    h: E.h * R * s.earU * (1 - 0.4 * s.earF) * ek,
    bw: E.bw * R * f * ek,
    tip: E.tip * R * ek,
    cx: E.cx || 0.95,
  };
}

export interface LayoutOptions {
  /** Seconds, for the purr shake. */
  T?: number;
  detail?: "full" | "compact";
  /** 1 is the right of the head, -1 the left; a value in between slides the badge across (the greeting). */
  badgeSide?: number;
  /** Ear scale, 1 by default; apps pass earScale(D) for a compact cat. */
  earScale?: number;
}

export interface EyeLayout { sd: number; visible: boolean; x: number; y: number; fx: number; fy: number }
export interface NoseLayout { visible: boolean; nx?: number; ny?: number; nf?: number; nw?: number; nh?: number; my?: number }

/**
 * Everything geometric about one cat in one pose, in px: where the head is, the warp, the eyes, the nose
 * and mouth, the ears, the badge. Drawing code only consumes this.
 *   p preset, s pose (the engine's `s`), cx/cy the cat's resting centre, D the head width.
 * Head-local means relative to the head centre, before the tilt and squash. `mouth` is in world px
 * and null while the nose is turned out of sight. `W` maps flat-view R-units to head-local px.
 */
export function layout(p: CatPreset, s: Pose, cx: number, cy: number, D: number, o: LayoutOptions = {}) {
  const R = D / (2 * p.rx);
  const full = detailLevel(D, o.detail).full;
  const T = o.T || 0;
  const ek = o.earScale === undefined ? 1 : o.earScale;
  const rx = p.rx * R, ry = p.ry * R;
  const base = { x: cx, y: cy, R };
  const purr = s.purr > 0.01 ? Math.sin(T * TAU * 24) * 0.007 * s.purr : 0;
  cx += (s.ox + purr) * R;
  cy += s.oy * R;
  const at = { x: cx, y: cy, R, D };
  const { yf, pf, pt, fa } = faceAngles(s);
  cx += Math.sin(s.yaw) * FACE.lean * R;
  cy -= Math.sin(s.pitch) * FACE.lean * 0.8 * R;
  const W = mkWarp(p, yf, pt, R);
  const eyes: EyeLayout[] = [-1, 1].map((sd) => {
    const th = sd * p.eye.th + yf, cp = Math.cos(p.eye.ph + pt);
    const [x, y] = W(Math.sin(sd * p.eye.th) * Math.cos(p.eye.ph) * p.rx, -Math.sin(p.eye.ph) * p.ry);
    return {
      sd, visible: Math.cos(th) * cp > 0.04, x, y,
      fx: clamp(Math.cos(th) / Math.cos(p.eye.th), 0.55, 1.08),
      fy: clamp(cp / Math.cos(p.eye.ph), 0.18, 1.08),
    };
  });
  let nose: NoseLayout = { visible: false };
  let mouth: { x: number; y: number } | null = null;
  if (Math.cos(yf) * Math.cos(p.nosePh + pt) > 0.04) {
    const [nx0, ny0] = W(0, -Math.sin(p.nosePh) * p.ry);
    const nx = nx0 + Math.sin(yf) * FACE.nose * R, ny = ny0 - Math.sin(pf) * FACE.nose * 0.8 * R;
    const nf = Math.max(0.3, Math.cos(yf)), nw = p.noseW * R * nf, nh = p.noseH * R, my = ny + nh / 2;
    nose = { visible: true, nx, ny, nf, nw, nh, my };
    const lx = nx * s.sx, ly = (my + 0.12 * R) * s.sy, c = Math.cos(s.tilt), sn = Math.sin(s.tilt);
    mouth = { x: cx + lx * c - ly * sn, y: cy + lx * sn + ly * c };
  }
  const side = o.badgeSide || 1;
  return {
    R, D, full, rx, ry, base, at, head: { x: cx, y: cy }, yf, pf, pt, fa, W, steps: outlineSteps(R),
    bend: [Math.sin(yf) * FACE.bend, -Math.sin(pf) * FACE.bend * 0.7] as [number, number],
    ruff: { dx: -Math.sin(s.yaw) * FACE.lean * 1.1 * R, dy: Math.sin(s.pitch) * FACE.lean * 0.9 * R },
    eyes, nose, mouth,
    ears: [-1, 1].map((sd) => ({ sd, ...earGeom(p, s, sd, R, yf, pf, ek) })),
    badge: { x: cx + side * 1.4 * R * s.sx, y: cy - 0.92 * R * s.sy, k: s.badgeS * (full ? 1 : 1.25), small: !full, side },
  };
}
export type Layout = ReturnType<typeof layout>;
export type EarLayout = Layout["ears"][number];

// ── The ear fit (A-0b, merged `6adf584`: EAR_FIT and earFit of cat-core.js) ──

/** The ear fit's defaults: the room kept under the ceiling in px, and the smallest factor. */
export const EAR_FIT = { margin: 0.5, minimum: 0.35 };

/**
 * The factor (EAR_FIT.minimum to 1) to multiply the ear scale by so that no ear rises above `ceiling`, a y in the layout's own coordinates
 * (the top edge of the strip the cat sits in: in the compact island that is the top of the screen, where an ear is cut off).
 * 1 means the ears already fit; a cat so close to the ceiling that even the smallest ears would not fit is held at `minimum`; a pose that
 * is not a number gives 1 (nothing to fit). `margin` is the room kept under the ceiling, in px.
 *   L is a layout() made with the ear scale `ek`; the answer is the factor for ek, so layout(..., { earScale: ek * factor }) fits.
 *   s is the pose that made it (the tilt and squash turn the ears).
 * An ear scales about its own base, so the height of its top edge is linear in the scale and one solve replaces a search. The top edge of an
 * ear is a parabola (x = 0.9 tip u, y = -h + tip (0.475 + 0.825 u²) for u in -1 to 1, in ear space), and the world height of an ear-space point
 * is y0 + A x + B y, so the highest point is where u = -0.9 A / (1.65 B), held to -1 to 1. That is the exact top edge, not the apex. It does not look
 * at the sides of an ear, so ears folded far back at a large size are outside what it solves; the compact notch never gets there.
 */
export function earFit(L: Layout, s: Pick<Pose, "tilt" | "sx" | "sy">, ceiling: number, margin = EAR_FIT.margin, minimum = EAR_FIT.minimum): number {
  const ct = Math.cos(s.tilt), st = Math.sin(s.tilt);
  let f = 1;
  for (const e of L.ears) {
    const cr = Math.cos(e.rot), sr = Math.sin(e.rot);
    const A = st * s.sx * cr + ct * s.sy * sr, B = ct * s.sy * cr - st * s.sx * sr;
    const y0 = L.head.y + st * s.sx * e.bx + ct * s.sy * e.by;
    const rise = (u: number) => 0.9 * A * e.tip * u + B * (-e.h + e.tip * (0.475 + 0.825 * u * u)); // height of the top edge at u above the ear's base (negative: higher up)
    const d = Math.min(rise(-1), rise(1), rise(B > 1e-9 ? clamp((-0.9 * A) / (1.65 * B), -1, 1) : 0));
    if (y0 + d >= ceiling + margin || d >= -1e-9) continue;
    f = Math.min(f, Math.max(minimum, (ceiling + margin - y0) / d));
  }
  return Number.isFinite(f) ? Math.max(minimum, Math.min(1, f)) : 1;
}

/**
 * The draw order, as named layers. The renderer draws a *behind* pass, the head, then a *front* pass,
 * so outfits (sub-project I) can sit behind or in front of the head. Each layer's data comes from layout().
 * The collar (stage 6) is drawn in the front pass between `foldEars` and `whiskers`: the contract names that slot `collarPass` (A-0b, merged
 * `6adf584`) and leaves this list as A-0 wrote it.
 */
export const PASSES = {
  behind: ["glow", "zoomTrails", "ruff", "bib", "paws", "ears"],
  head: ["head", "markings", "tint", "rim", "blush", "eyes", "mouth", "nose"],
  front: ["foldEars", "whiskers", "badge", "particles", "balls"],
};

/** A dropped file arcs into the cat's mouth over this long (ms). */
export const FLIGHT_MS = 380;

/** Where the file is, how big and how turned, `k` (0 to 1) of the way along its arc from `from` to the mouth `to`. R is the head radius in px. */
export function flightAt(from: { x: number; y: number }, to: { x: number; y: number }, R: number, k: number) {
  const q = EZ.inOut(k), cx = (from.x + to.x) / 2, cy = Math.min(from.y, to.y) - 60, u = 1 - q;
  return {
    x: u * u * from.x + 2 * u * q * cx + q * q * to.x, y: u * u * from.y + 2 * u * q * cy + q * q * to.y,
    size: lerp(R * 0.62, R * 0.14, q), rot: (1 - q) * 0.5 - 0.25,
  };
}
