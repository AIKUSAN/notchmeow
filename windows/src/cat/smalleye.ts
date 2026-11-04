// The small coloured eye (sub-project B, spec §4): below a head of Ø28 the plain resting eyes (pill, wide, dot and tired) are a round iris in the coat's
// colours, a slit pupil, one catchlight and a thin rim, instead of the cat's flat ink pill. A port of "Small eyes" in design/prototype/cat-core.js (the
// tie-breaker; fixture tests/fixtures/cat/small-eye-cases.json; docs/CAT-CONTRACT.md "Small coloured eyes"). This is the geometry only, in px of the eye's
// own frame (its centre is the origin, y down, before the renderer's foreshortening); the renderer paints it with the coat's colours (smallEyeDraw).
// The three black coats (and their kittens) glow: `cat` names the coat, and a bright eye comes back `flat` with no rim and a thinner pupil.
// Imports nothing, so the plain-Node checks (npm run check:cat) can load it.

/** The resting shapes that become a small coloured eye. The left eye of a wink is one too (the right is an ink arc). */
export const SMALL_EYE_SHAPES = ["pill", "wide", "dot", "tired"] as const;

/**
 * The numbers, pinned by small-eye-cases.json. Sizes are fractions of u = R * es (the head radius times the expression scale) and are full widths and
 * heights. wide is the iris times (1.16, 1.12); dot is a round iris with a round, dilated pupil; tired shows at most `open` 0.42 of the eye. The pupil moves
 * with the gaze (yaw / 0.62, pitch / 0.5, each held to -1 to 1) by at most `travel` of the iris's half-axes, so it never leaves it. A blink or a squint
 * under `closeBelow` of the eye's height closes it to a line. A kitten's eye is `kitten.w` times wider and `kitten.h` times taller. The black coats
 * `bright` (an explicit list, so the other coats do not move) are drawn with a flat fill of the lighter iris colour, no rim, and a slit pupil `brightPupil.w` wide.
 */
export const SMALL_EYE = {
  iris: { w: 0.42, h: 0.46 }, pupil: { w: 0.18, h: 0.4 }, wide: { w: 1.16, h: 1.12 }, dot: { iris: [0.42, 0.42], pupil: [0.26, 0.26] }, tired: { open: 0.42 },
  light: { x: -0.11, y: -0.1, r: 0.075, minR: 0.45 }, rim: { k: 0.05, min: 0.5 }, travel: { x: 0.2, y: 0.08 }, closeBelow: 0.22, pupilFit: 0.87,
  kitten: { w: 1.2, h: 1.32 }, line: { width: 0.045, minWidth: 1, curve: 0.4 }, bright: ["midnight", "oreo", "mocha"], brightPupil: { w: 0.12 },
} as const;

/** True when the renderer draws shape `shape` of the eye `sd` (-1 left, 1 right) with smallEye at the compact level, and false when it stays ink. */
export const usesSmallEye = (shape: unknown, sd: unknown): boolean =>
  (SMALL_EYE_SHAPES as readonly unknown[]).includes(shape) || (shape === "wink" && typeof sd === "number" && sd < 0);

export interface SmallEyeOpts {
  /** -1 the left eye (the default), 1 the right. */
  sd?: number;
  /** The head radius in px, held to 0 up to 10000. */
  R?: number;
  /** The pose's expression scale, held to 0 up to 10 (default 1). */
  es?: number;
  /** The pose's `open * (1 - lid)`, held to 0…1 (default 1). */
  open?: number;
  yaw?: number;
  pitch?: number;
  /** The preset's `kitten` flag. */
  kitten?: boolean;
  /** The coat's id: only an exact string in `SMALL_EYE.bright` makes a bright eye; anything else (or nothing) is a normal one. A kitten keeps its coat's id. */
  cat?: string;
}
export interface SmallEyeOpen {
  shape: string;
  closed: false;
  iris: { rx: number; ry: number; r: number };
  pupil: { x: number; y: number; rx: number; ry: number };
  light: { x: number; y: number; r: number };
  rim: number;
  /** Present (true) only for a bright coat's eye: the renderer fills the iris flat, with the lighter of the coat's two iris colours, and draws no rim (`rim` is 0). */
  flat?: true;
}
export interface SmallEyeShut {
  shape: string;
  closed: true;
  line: { x0: number; y0: number; cx: number; cy: number; x1: number; y1: number; width: number };
}
export type SmallEye = SmallEyeOpen | SmallEyeShut;

const num = (v: unknown, d: number): number => (typeof v === "number" && Number.isFinite(v) ? v : d);

/**
 * One small eye: null for a shape that is not a small eye (draw the ink shape), else the open eye or, for a blink or squint under 0.22, the closed line (an
 * arc in the ink colour at alpha 0.9). A value that is not a number is taken as its default; nothing is ever NaN.
 */
export function smallEye(shape: unknown, opts?: SmallEyeOpts | null): SmallEye | null {
  const o: SmallEyeOpts = opts !== null && typeof opts === "object" && !Array.isArray(opts) ? opts : {};
  if (!usesSmallEye(shape, o.sd === 1 ? 1 : -1)) return null;
  const S = SMALL_EYE, name = shape as string;
  const R = Math.max(0, Math.min(1e4, num(o.R, 0))), u = R * Math.max(0, Math.min(10, num(o.es, 1)));
  const sh = name === "wink" ? "pill" : name, kit = o.kitten === true, kw = kit ? S.kitten.w : 1, kh = kit ? S.kitten.h : 1;
  const bri = typeof o.cat === "string" && (S.bright as readonly string[]).includes(o.cat);
  const open = Math.max(0, Math.min(1, num(o.open, 1))), op = sh === "tired" ? Math.min(open, S.tired.open) : open;
  const base: readonly number[] = sh === "dot" ? S.dot.iris : [S.iris.w * (sh === "wide" ? S.wide.w : 1), S.iris.h * (sh === "wide" ? S.wide.h : 1)];
  const rx0 = (base[0] / 2) * kw * u, ry0 = (base[1] / 2) * kh * u;
  if (op < S.closeBelow) {
    return { shape: name, closed: true, line: { x0: -rx0, y0: 0, cx: 0, cy: S.line.curve * ry0, x1: rx0, y1: 0, width: Math.max(S.line.minWidth, S.line.width * u) } };
  }
  const ry = ry0 * op, pw = ((sh === "dot" ? S.dot.pupil[0] : bri ? S.brightPupil.w : S.pupil.w) / 2) * kw * u;
  const pry = Math.min(((sh === "dot" ? S.dot.pupil[1] : S.pupil.h) / 2) * kh * u, S.pupilFit * ry);
  const gx = Math.max(-1, Math.min(1, num(o.yaw, 0) / 0.62)), gy = Math.max(-1, Math.min(1, num(o.pitch, 0) / 0.5));
  const px = gx * S.travel.x * rx0, py = -gy * S.travel.y * ry;
  return {
    shape: name, closed: false, iris: { rx: rx0, ry, r: Math.max(rx0, ry) }, pupil: { x: px, y: py, rx: pw, ry: pry },
    light: { x: (S.light.x / (S.iris.w / 2)) * rx0, y: (S.light.y / (S.iris.h / 2)) * ry, r: Math.max(S.light.r * u, S.light.minR) },
    rim: bri ? 0 : Math.max(S.rim.k * u, S.rim.min), ...(bri ? { flat: true as const } : {}),
  };
}
