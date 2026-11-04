// The collar: the agent colour, worn as a thin collar (spec §3 and §4; A-0b). A port of `collarGeometry` in design/prototype/cat-core.js, the
// tie-breaker (fixture tests/fixtures/cat/collar-cases.json; docs/CAT-CONTRACT.md "Collar, ear fit and flat fills"). Pure maths: the renderer
// paints what collarGeometry returns, in the front pass between the folded ears and the whiskers. The style IDs are frozen contract values
// (`tag`, `band`, `kerchief`, `off`); they live in settings.ts with the other stored words and are re-exported here under the contract's names.
// Imports only geometry.ts and settings.ts, so the plain-Node checks (npm run check:cat) can load it.

import { layout, supPoints } from "./geometry.ts";
import { collarStyleOf } from "./settings.ts";
import type { CollarStyle } from "./settings.ts";
import type { CatPreset, Pose } from "./types.ts";

export { COLLAR_STYLES, collarStyleOf } from "./settings.ts";

/** Smallest sizes, in DEVICE pixels, so a collar still reads as a colour at Ø12 and Ø20. */
export const COLLAR_MIN = { band: 3, tag: 6, kerchiefW: 7, kerchiefDrop: 5 } as const;
/** The renderer pass the collar is drawn in: between `foldEars` and `whiskers` of `PASSES.front`. `PASSES` itself stays as A-0 wrote it. */
export const COLLAR_PASS = "front";

type Pt = readonly [number, number];

/** Where one collar sits, in head-local px (before the tilt and the squash). Which parts are there depends on the style. */
export interface CollarGeometry {
  style: Exclude<CollarStyle, "off">;
  R: number;
  /** tag and band: the band's stroke width, a tenth of R and never under COLLAR_MIN.band device px. */
  width?: number;
  /** tag and band: a polyline along the lower outline, left to right, inset so its outer edge stays inside the head. */
  band?: Pt[];
  /** tag: a round tag at centre front. */
  tag?: { x: number; y: number; r: number };
  /** kerchief: a triangle under the chin, `pts` along the lower outline and `apex` below them. */
  kerchief?: { pts: Pt[]; apex: Pt };
}

export interface CollarOptions {
  /** The device pixel ratio, default 2 (and 2 for anything that is not above 0). */
  dpr?: number;
  /** As in layout(). */
  detail?: "full" | "compact";
}

/** The collar of one cat, or null for `off` (an unknown style is `off`). Turns with the face warp; D is the head width in px. */
export function collarGeometry(p: CatPreset, s: Pose, D: number, style: unknown, o: CollarOptions = {}): CollarGeometry | null {
  const id = collarStyleOf(style);
  if (id === "off") return null;
  const dpr = typeof o.dpr === "number" && o.dpr > 0 ? o.dpr : 2;
  const { R, W } = layout(p, s, 0, 0, D, { detail: o.detail });
  const px = (n: number) => n / dpr / R; // device px to R-units
  const width = Math.max(0.1 * R, COLLAR_MIN.band / dpr);
  const k = Math.max(0.7, Math.min(0.92, 1 - (width / 2 + 0.5 / dpr) / (p.ry * R)));
  const N = 90;
  const ring = supPoints(p.rx * k, p.ry * k, p.n, 0, 0, 0, N).slice(0, N); // R-units; index i is angle i/N of a turn, y down
  const out: CollarGeometry = { style: id, R };
  if (id === "kerchief") {
    const hw = Math.min(p.rx * k, Math.max(0.5 * p.rx, px(COLLAR_MIN.kerchiefW) * 0.65));
    const arc = ring.filter(([x, y]) => y > 0 && Math.abs(x) <= hw).sort((a, b) => a[0] - b[0]);
    const [ax, ay] = W(0, p.ry * k);
    const top = Math.max(...arc.map((q) => W(...q)[1]));
    out.kerchief = { pts: arc.map((q) => W(...q)), apex: [ax, Math.max(ay, top) + Math.max(0.34 * R, COLLAR_MIN.kerchiefDrop / dpr)] };
  } else {
    const lower = ring.slice((N * 40) / 360, (N * 140) / 360 + 1).reverse(); // left to right, 40° to 140°
    out.width = width;
    out.band = lower.map(([x, y]) => W(x, y));
    if (id === "tag") {
      const [x, y] = W(0, p.ry * k);
      out.tag = { x, y, r: Math.max(0.16 * R, COLLAR_MIN.tag / dpr / 2) };
    }
  }
  return out;
}

/**
 * The colour the big cat wears: the collar of the agent driving its current state, and none when idle. A sleeping cat is an idle one, and a dizzy
 * one has been poked: those states are the cat's own, not an agent's. `color` is the focused pill's colour.
 */
export function bigCatCollar(state: string, color: string | null | undefined): string | null {
  return color && state !== "idle" && state !== "sleeping" && state !== "dizzy" ? color : null;
}
