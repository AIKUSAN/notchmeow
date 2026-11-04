// Where an outfit sits on a head and the shapes it is made of (sub-project I). A port of the second half of "The wardrobe (sub-project I)" in design/prototype/cat-core.js, the
// tie-breaker (fixture tests/fixtures/cat/wardrobe-cases.json; docs/CAT-CONTRACT.md "The wardrobe (I-0)"). Pure maths in head-local px (before the tilt and squash, like
// collarGeometry): outfitAnchors says where the parts attach, outfitGeometry returns the shapes with colour roles, and outfitdraw.ts paints them. Nothing here reads a coat list, a
// clock or a canvas. Imports geometry.ts, collar.ts and wardrobe.ts, so the plain-Node checks (npm run check:cat) can load it.

import { TAU, clamp } from "./base.ts";
import { collarGeometry, COLLAR_MIN } from "./collar.ts";
import { DETAIL_FULL_MIN, EAR_FIT, FLAT_FILL, earScale, layout, mixHex, supPoints } from "./geometry.ts";
import { OUTFIT_DRAWN } from "./wardrobe.ts";
import type { CatPreset, Pose } from "./types.ts";

/** Where in the draw order a shape goes: `behind` (after the ears in the behind pass), `neck` (the front pass after the collar) and `top` (after `neck`, before the whiskers). */
export const OUTFIT_SLOTS = ["behind", "neck", "top"] as const;
export type OutfitSlot = (typeof OUTFIT_SLOTS)[number];
/** The whole draw order with the outfit's three places in it (PASSES itself stays as A-0 wrote it). */
export const OUTFIT_ORDER = {
  behind: ["glow", "zoomTrails", "ruff", "bib", "paws", "ears", "outfit.behind"],
  head: ["head", "markings", "tint", "rim", "blush", "eyes", "mouth", "nose"],
  front: ["foldEars", "collar", "outfit.neck", "outfit.top", "whiskers", "badge", "particles", "balls"],
};
/** Smallest sizes, in DEVICE pixels (as COLLAR_MIN is), so an outfit still reads on the compact notch's Ø20 cat (40 device pixels wide at 2x). */
export const OUTFIT_MIN = { height: 6, line: 1, rim: 2, ball: 3, span: 6 } as const;

/** Whether a coat's head is dark enough that an outfit's thin edge must be light to show: `light` for a dark head, `dark` for a light one (the flat head colour's luminance under 100). */
export function outfitEdge(p: CatPreset): "light" | "dark" {
  const c = mixHex(p.top, p.bot, FLAT_FILL.headMix);
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2] < 100 ? "light" : "dark";
}

/** The room above the crown for a hat, in px: from the crown to `ceiling` (the y of the strip's top, in the coordinates of `headY`) less the ear fit's margin. null without a number ceiling: no limit. */
export const outfitRoom = (a: { top: { y: number } }, headY: unknown, ceiling: unknown): number | null =>
  typeof ceiling === "number" && Number.isFinite(ceiling) && typeof headY === "number" && Number.isFinite(headY) ? Math.max(0, headY + a.top.y - ceiling - EAR_FIT.margin) : null;

export interface OutfitOptions {
  /** The device pixel ratio, default 2. */
  dpr?: number;
  detail?: "full" | "compact";
  /** The ear scale the cat's ears were drawn with (layout's `earScale`); default what the renderer uses: 1 from Ø28, else earScale(D). */
  earScale?: number;
  /** The collar style the cat wears (the bell hangs from it). */
  collar?: string;
  /** From outfitRoom: the height a hat may rise above the crown. */
  room?: number | null;
}

type Pt = [number, number];
export interface OutfitAnchors {
  R: number; rx: number; ry: number; D: number; full: boolean; dpr: number;
  top: { x: number; y: number }; gap: number; half: number; lean: number;
  ears: { sd: number; bx: number; by: number; rot: number; h: number; tipX: number; tipY: number }[];
  eyes: { sd: number; visible: boolean; x: number; y: number; fx: number; fy: number }[];
  chin: { pts: Pt[]; front: Pt };
  neck: { x: number; y: number };
  edge: "light" | "dark";
}

/** Where the outfit parts attach to one cat in one pose, in head-local px. `o.dpr` defaults to 2. */
export function outfitAnchors(p: CatPreset, s: Pose, D: number, o: OutfitOptions = {}): OutfitAnchors {
  const dpr = typeof o.dpr === "number" && o.dpr > 0 ? o.dpr : 2, ek = o.earScale === undefined ? (D >= DETAIL_FULL_MIN ? 1 : earScale(D)) : o.earScale;
  const L = layout(p, s, 0, 0, D, { detail: o.detail, earScale: ek }), { R, rx, ry, W } = L, [eL, eR] = L.ears;
  const mx = (eL.bx + eR.bx) / 2, gap = Math.abs(eR.bx - eL.bx), tx = clamp(mx / rx, -0.95, 0.95);
  const top = { x: mx, y: -ry * Math.pow(Math.max(0, 1 - Math.pow(Math.abs(tx), p.n)), 1 / p.n) + L.bend[1] * ry * (1 - tx * tx) };
  const N = 90, ring = supPoints(rx, ry, p.n, 0, p.fluff ? 0.035 : 0, 14, N, L.bend).slice(0, N);
  const arc = ring.slice((N * 40) / 360, (N * 140) / 360 + 1).reverse(), front: Pt = [(arc[12][0] + arc[13][0]) / 2, (arc[12][1] + arc[13][1]) / 2];
  const width = Math.max(0.1 * R, COLLAR_MIN.band / dpr), k = Math.max(0.7, Math.min(0.92, 1 - (width / 2 + 0.5 / dpr) / (p.ry * R))), [nx, ny] = W(0, p.ry * k);
  return {
    R, rx, ry, D, full: L.full, dpr, top, gap, half: gap / 2, lean: Math.sin(L.yf) * 0.15,
    ears: L.ears.map((e) => ({ sd: e.sd, bx: e.bx, by: e.by, rot: e.rot, h: e.h, tipX: e.bx + e.h * Math.sin(e.rot), tipY: e.by - e.h * Math.cos(e.rot) })),
    eyes: L.eyes.map((e) => ({ sd: e.sd, visible: e.visible, x: e.x, y: e.y, fx: e.fx, fy: e.fy })),
    chin: { pts: arc, front }, neck: { x: nx, y: ny }, edge: outfitEdge(p),
  };
}

/** A shape of an outfit, in head-local px. `fill` and `stroke` are colour roles (the keys of THEME.outfits) or `edge`; `a` is the alpha, `sw` the stroke width in px. */
export interface PolyShape { k: "poly"; slot: OutfitSlot; fill: string | null; stroke: string | null; sw: number; a: number; fine: boolean; pts: Pt[] }
export interface CurveShape { k: "curve"; slot: OutfitSlot; stroke: string; sw: number; a: number; fine: boolean; pts: Pt[] }
export interface EllipseShape { k: "ellipse"; slot: OutfitSlot; fill: string | null; stroke: string | null; sw: number; a: number; fine: boolean; x: number; y: number; rx: number; ry: number; rot: number }
export type OutfitShape = PolyShape | CurveShape | EllipseShape;

interface Style { stroke?: string | null; sw?: number; a?: number; fine?: boolean }

/**
 * The shapes of one outfit on one cat, in paint order. A hat rises by a natural height, shortened to `o.room` and never below the floor; a `fine` shape (a glint, a star, a rib) is left out
 * below Ø28, as the cat's own fine details are. An ID that is not one of the 16 drawn outfits (`none`, `auto`, anything else) gives [].
 */
export function outfitGeometry(id: unknown, p: CatPreset, s: Pose, D: number, o: OutfitOptions = {}): OutfitShape[] {
  if (typeof id !== "string" || !(OUTFIT_DRAWN as readonly string[]).includes(id)) return [];
  const A = outfitAnchors(p, s, D, o), { R, dpr, top, full } = A, fl = (n: keyof typeof OUTFIT_MIN) => OUTFIT_MIN[n] / dpr, ln = Math.max(fl("line"), 0.03 * R), g = A.half, ca = Math.cos(A.lean), sa = Math.sin(A.lean);
  const out: OutfitShape[] = [];
  const Q = (x: number, y: number, b: Pt = [top.x, top.y]): Pt => [b[0] + x * ca - y * sa, b[1] + x * sa + y * ca];
  const room = typeof o.room === "number" && Number.isFinite(o.room) ? o.room : Infinity, hatH = (nat: number) => Math.max(fl("height"), Math.min(nat * R, room));
  const poly = (slot: OutfitSlot, pts: Pt[], fill: string | null, st: Style = {}) =>
    out.push({ k: "poly", slot, fill, stroke: st.stroke === undefined ? "edge" : st.stroke, sw: st.stroke === null ? 0 : st.sw || ln, a: st.a === undefined ? 1 : st.a, fine: !!st.fine, pts });
  const curve = (slot: OutfitSlot, pts: Pt[], stroke: string, sw: number, st: Style = {}) =>
    out.push({ k: "curve", slot, stroke, sw: Math.max(sw, fl("line")), a: st.a === undefined ? 1 : st.a, fine: !!st.fine, pts });
  const ell = (slot: OutfitSlot, x: number, y: number, rx: number, ry: number, rot: number, fill: string | null, st: Style = {}) =>
    out.push({ k: "ellipse", slot, fill, stroke: st.stroke === undefined ? "edge" : st.stroke, sw: st.stroke === null ? 0 : st.sw || ln, a: st.a === undefined ? 1 : st.a, fine: !!st.fine, x, y, rx, ry, rot });
  const arcPts = (cx: number, cy: number, rx: number, ry: number, a0: number, a1: number, n = 10): Pt[] => Array.from({ length: n + 1 }, (_, i) => {
    const a = a0 + ((a1 - a0) * i) / n;
    return [cx + Math.cos(a) * rx, cy + Math.sin(a) * ry];
  });
  const star = (cx: number, cy: number, ro: number, ri: number): Pt[] => Array.from({ length: 10 }, (_, i) => {
    const r = i % 2 ? ri : ro, a = -Math.PI / 2 + (i * Math.PI) / 5;
    return [cx + Math.cos(a) * r, cy + Math.sin(a) * r];
  });
  /** A stadium shape, `w` its outer half width. */
  const pill = (slot: OutfitSlot, w: number, yc: number, hh: number, fill: string) =>
    poly(slot, [...arcPts(w - hh, yc, hh, hh, -Math.PI / 2, Math.PI / 2, 6), ...arcPts(hh - w, yc, hh, hh, Math.PI / 2, Math.PI * 1.5, 6)].map((q) => Q(q[0], q[1])), fill);
  const ear = (sd: number) => A.ears.find((e) => e.sd === sd)!;
  const ball = (r: number) => Math.max(fl("ball"), r);
  /** A tapered leaf along a centre line: `c(t)` the centre, `w(t)` the half width, both for t from 0 to 1. */
  const leaf = (c: (t: number) => Pt, w: (t: number) => number, n = 14): Pt[] => {
    const Lf: Pt[] = [], Rr: Pt[] = [];
    for (let i = 0; i <= n; i++) {
      const t = i / n, a = c(t), b = c(Math.min(1, t + 0.02)), d = c(Math.max(0, t - 0.02)), tx = b[0] - d[0], ty = b[1] - d[1], l = Math.hypot(tx, ty) || 1, nx = -ty / l, ny = tx / l, ww = w(t);
      Lf.push([a[0] + nx * ww, a[1] + ny * ww]);
      Rr.push([a[0] - nx * ww, a[1] - ny * ww]);
    }
    return [...Lf, ...Rr.reverse()];
  };

  // ── Hats: they stand between the ear bases, so they are as wide as the gap and no wider
  if (id === "partyhat") {
    const Hh = hatH(1.35), b: Pt = [top.x, top.y + 0.05 * R], w = 0.7, tx = 0.3, H = (x: number, y: number) => Q(x * g, y * Hh, b);
    const Lf = (t: number) => H(-w + (tx + w) * t, -t), Rt = (t: number) => H(w + (tx - w) * t, -t), tip = H(tx, -1);
    poly("top", [...arcPts(0, 0, w * g, 0.1 * R, Math.PI, 0, 8).map((q) => Q(q[0], -q[1], b)), tip], "partyA");
    for (const [t0, t1] of [[0.16, 0.32], [0.5, 0.64]]) poly("top", [Lf(t0), Lf(t1), Rt(t1), Rt(t0)], "partyB", { stroke: null });
    poly("top", star(tip[0], tip[1] - 0.04 * R, 0.2 * R, 0.09 * R), "partyStar", { fine: true, sw: ln });
  } else if (id === "santahat") {
    const Hh = hatH(0.95), b: Pt = [top.x, top.y + 0.1 * R], hw = 0.82, H = (x: number, y: number) => Q(x * g, y * Hh, b);
    poly("top", [H(-hw, 0), H(-0.74, -0.45), H(-0.4, -0.86), H(0, -1), H(0.42, -0.88), H(0.74, -0.5), H(hw, 0)], "santaRed");
    const c = (t: number): Pt => { const m = 1 - t; return H(2 * m * t * -0.5 + t * t * -0.58, m * m * -0.95 + 2 * m * t * -1.02 + t * t * -0.5); }, tip = c(1);
    poly("top", leaf(c, (t) => (0.26 - 0.18 * t) * g, 10), "santaRed", { stroke: null });
    ell("top", tip[0], tip[1], ball(0.17 * R), ball(0.17 * R), 0, "fur");
    pill("top", 0.95 * g, 0, Math.max(fl("line") * 2, 0.12 * R), "fur");
  } else if (id === "witchhat") {
    const Hh = hatH(1.5), b: Pt = [top.x, top.y + 0.04 * R], H = (x: number, y: number) => Q(x * g, y * Hh, b);
    const q0 = Q(0, 0, b);
    ell("top", q0[0], q0[1], 0.95 * g, Math.max(0.12 * R, fl("line") * 2), A.lean, "witchHat");
    poly("top", [H(-0.52, 0), H(-0.36, -0.4), H(-0.08, -0.72), H(0.1, -0.82), H(0.62, -1), H(0.4, -0.66), H(0.34, -0.45), H(0.52, 0)], "witchHat");
    poly("top", [H(-0.5, -0.1), H(0.5, -0.1), H(0.45, -0.3), H(-0.42, -0.3)], "witchBand", { stroke: null });
    poly("top", [H(-0.12, -0.06), H(0.12, -0.06), H(0.12, -0.34), H(-0.12, -0.34)], "gold", { sw: ln });
  } else if (id === "bunnyears") {
    const cm = !full, Hh = hatH(cm ? 1.9 : 1.45), b: Pt = [top.x, top.y + (cm ? 0.1 : 0.5) * R], H = (x: number, y: number) => Q(x * g, y * Hh, b);
    // Below Ø28 the ears are taller (their base sits nearer the crown) and wider, so they show above the head at Ø18 and Ø20; the open size is unchanged.
    for (const sd of [-1, 1]) {
      const bend = sd > 0 ? 0.9 : 0, c = (t: number): Pt => { const x = sd * (0.4 + 0.22 * t) + bend * Math.pow(Math.max(0, t - 0.55), 2) * 1.2; return H(x, -t); };
      const wm = Math.max((cm ? 0.5 : 0.3) * g, fl("span") / 2), w = (t: number) => wm * Math.pow(Math.sin(Math.PI * (0.2 + 0.8 * t)), 0.8);
      poly("behind", leaf(c, w), "bunnyOuter");
      poly("behind", leaf((t) => c(0.06 + 0.74 * t), (t) => w(0.06 + 0.74 * t) * 0.55), "bunnyInner", { stroke: null });
    }
  } else if (id === "beanie") {
    const Hh = hatH(0.78), b: Pt = [top.x, top.y + 0.26 * R], hw = 0.95, H = (x: number, y: number) => Q(x * g, y * Hh, b);
    poly("top", arcPts(0, 0, hw, 1, Math.PI, Math.PI * 2, 14).map((q) => H(q[0], q[1])), "beanieBody");
    for (const x of [-0.5, 0, 0.5]) curve("top", [H(x * 0.9, -0.15), H(x, -0.62), H(x * 0.5, -0.92)], "beanieCuff", ln * 0.9, { fine: true, a: 0.7 });
    pill("top", 0.96 * g, 0, Math.max(0.14 * R, fl("span") / 2), "beanieCuff");
    const t = H(0, -1.0);
    ell("top", t[0], t[1] - 0.04 * R, ball(0.17 * R), ball(0.17 * R), 0, "fur");
  } else if (id === "crown") {
    const Hh = hatH(0.55), b: Pt = [top.x, top.y + 0.12 * R], hw = 0.7, H = (x: number, y: number) => Q(x * g, y * Hh, b);
    poly("top", [H(-hw, 0), H(-hw, -0.72), H(-0.4, -0.4), H(0, -1), H(0.4, -0.4), H(hw, -0.72), H(hw, 0)], "gold");
    poly("top", [H(-hw, 0), H(hw, 0), H(hw, -0.22), H(-hw, -0.22)], "goldDark", { stroke: null, a: 0.85 });
    ([[-hw, -0.72, "gemA"], [0, -1, "gemB"], [hw, -0.72, "gemC"]] as const).forEach(([x, y, r]) => {
      const q = H(x, y), gr = ball(0.09 * R);
      ell("top", q[0], q[1] + gr, gr, gr, 0, r);
    });
  // ── Glasses: they follow the eye frames and flatten with the face turn
  } else if (id === "sunglasses" || id === "roundglasses") {
    const sun = id === "sunglasses", E = p.eye, lr = (sun ? 1.75 : 1.95) * E.w * R, lv = (sun ? 1.55 : 1.7) * Math.max(E.h, 0.85 * E.w) * R, fr = Math.max(fl("rim"), sun ? 0.06 * R : 0.045 * R);
    const eyes = A.eyes.filter((e) => e.visible);
    for (const e of eyes) {
      const rx = Math.max(lr * e.fx, fl("ball")), ry = Math.max(lv * e.fy, fl("ball"));
      if (sun) {
        const rim = A.edge === "light"; // a dark head: the frame's dark would vanish, so a thin light rim (the edge role) outlines the lens
        ell("top", e.x, e.y, rx, ry, 0, "lens", rim ? { stroke: "edge", sw: ln, a: 0.93 } : { stroke: "frame", sw: fr, a: 0.93 });
        poly("top", [[e.x - rx * 0.5, e.y - ry * 0.15], [e.x - rx * 0.12, e.y - ry * 0.62], [e.x + rx * 0.12, e.y - ry * 0.62], [e.x - rx * 0.3, e.y + ry * 0.08]], "glint", { stroke: null, a: 0.55, fine: true });
      } else {
        ell("top", e.x, e.y, rx, ry, 0, "glassTint", { stroke: "rim", sw: fr, a: 0.22 });
        ell("top", e.x, e.y, rx, ry, 0, null, { stroke: "rim", sw: fr });
        curve("top", arcPts(e.x, e.y, rx * 0.72, ry * 0.72, Math.PI * 1.05, Math.PI * 1.4, 5), "glint", ln, { fine: true, a: 0.8 });
      }
    }
    if (eyes.length === 2) {
      const [a, b2] = eyes.sort((u, v) => u.sd - v.sd), ax = a.x + Math.max(lr * a.fx, fl("ball")), bx = b2.x - Math.max(lr * b2.fx, fl("ball")), my = (a.y + b2.y) / 2;
      curve("top", [[ax, a.y], [(ax + bx) / 2, my - (sun ? 0.06 : 0.1) * R], [bx, b2.y]], sun ? "frame" : "rim", fr);
    }
    for (const e of eyes) {
      const ox = e.x + e.sd * Math.max(lr * e.fx, fl("ball"));
      curve("top", [[ox, e.y - lv * e.fy * 0.2], [ox + e.sd * 0.3 * R * e.fx, e.y - lv * e.fy * 0.05]], sun ? "frame" : "rim", fr);
    }
  // ── Clips, the bow and the flower: at an ear base, turning with the ear
  } else if (id === "bow") {
    const e = ear(1), cx = e.bx - 0.12 * R, cy = e.by + 0.02 * R, u = Math.max(R * 0.9, fl("span") * 1.6), rot = e.rot * 0.6;
    for (const sd of [-1, 1]) ell("top", cx + sd * 0.3 * u * Math.cos(rot), cy + sd * 0.3 * u * Math.sin(rot), 0.3 * u, 0.21 * u, rot + sd * 0.35, "bowRed");
    poly("top", [[cx - 0.05 * u, cy + 0.1 * u], [cx - 0.2 * u, cy + 0.55 * u], [cx - 0.05 * u, cy + 0.45 * u]], "bowKnot", { fine: true });
    poly("top", [[cx + 0.05 * u, cy + 0.1 * u], [cx + 0.2 * u, cy + 0.55 * u], [cx + 0.05 * u, cy + 0.45 * u]], "bowKnot", { fine: true });
    ell("top", cx, cy, ball(0.1 * u), ball(0.1 * u), 0, "bowKnot");
  } else if (id === "fishclip") {
    const e = ear(-1), cx = e.bx + 0.24 * R, cy = e.by + 0.1 * R, u = Math.max(R, fl("span") * 1.7), rot = e.rot * 0.5;
    ell("top", cx, cy, 0.27 * u, 0.13 * u, rot, "fishBody");
    poly("top", [[cx + 0.25 * u * Math.cos(rot), cy + 0.25 * u * Math.sin(rot)], [cx + 0.45 * u, cy - 0.14 * u], [cx + 0.45 * u, cy + 0.14 * u]], "fishFin");
    ell("top", cx - 0.13 * u, cy - 0.02 * u, 0.025 * u, 0.025 * u, 0, "lens", { stroke: null, fine: true });
  } else if (id === "flower") {
    const e = ear(1), cx = e.bx - 0.22 * R, cy = e.by + 0.1 * R, u = Math.max(R, fl("span") * 1.7);
    for (let i = 0; i < 5; i++) {
      const a = -Math.PI / 2 + (i * TAU) / 5;
      ell("top", cx + Math.cos(a) * 0.15 * u, cy + Math.sin(a) * 0.15 * u, ball(0.13 * u), ball(0.09 * u), a, "petal");
    }
    ell("top", cx, cy, ball(0.07 * u), ball(0.07 * u), 0, "gold", { sw: ln });
  } else if (id === "shrimpclip" && !full) {
    // Below Ø28 (the detail cut) the shrimp is simple and bold: one thick curled C, one fanned tail with three tips, both in the shrimp colour with the edge round them.
    const e = ear(-1), cx = e.bx + 0.24 * R, cy = e.by + 0.12 * R, u = Math.max(R, fl("span") * 1.7), r = 0.3 * u, sw = Math.max(0.2 * u, fl("span") / 2), a0 = Math.PI * 0.25, a1 = Math.PI * 1.45;
    const tx = cx + r * Math.cos(a1), ty = cy + r * Math.sin(a1), td = [-Math.sin(a1), Math.cos(a1)], nd = [Math.cos(a1), Math.sin(a1)], L2 = 0.55 * u, w = 0.22 * u;
    const at = (a: number, b: number): Pt => [tx + a * td[0] + b * nd[0], ty + a * td[1] + b * nd[1]];
    curve("top", arcPts(cx, cy, r, r, a0, a1, 10), "edge", sw + 2 * ln);
    curve("top", arcPts(cx, cy, r, r, a0, a1, 10), "shrimp", sw);
    poly("top", [at(0, w * 0.5), at(L2 * 0.9, w), at(L2 * 0.45, w * 0.35), at(L2 * 1.1, 0), at(L2 * 0.45, -w * 0.35), at(L2 * 0.9, -w), at(0, -w * 0.5)], "shrimp");
  } else if (id === "shrimpclip") {
    const e = ear(-1), cx = e.bx + 0.24 * R, cy = e.by + 0.12 * R, u = Math.max(R, fl("span") * 1.7), r = 0.15 * u, sw = Math.max(0.12 * u, fl("span") / 2);
    // a curled, segmented body: four segments along a C, a fine dark joint between each pair
    for (let i = 0; i < 4; i++) {
      const a0 = Math.PI * (0.25 + i * 0.3);
      curve("top", arcPts(cx, cy, r, r, a0, a0 + Math.PI * 0.3, 4), "shrimp", sw);
    }
    for (let i = 1; i < 4; i++) {
      const a = Math.PI * (0.25 + i * 0.3);
      curve("top", [[cx + 0.8 * r * Math.cos(a), cy + 0.8 * r * Math.sin(a)], [cx + 1.25 * r * Math.cos(a), cy + 1.25 * r * Math.sin(a)]], "shrimpDark", ln);
    }
    // a fanned tail: three spikes, between notches, off the end of the C
    const a1 = Math.PI * 1.45, tx = cx + r * Math.cos(a1), ty = cy + r * Math.sin(a1);
    poly("top", [[tx, ty], [tx + 0.2 * u, ty - 0.14 * u], [tx + 0.13 * u, ty - 0.03 * u], [tx + 0.26 * u, ty], [tx + 0.13 * u, ty + 0.03 * u], [tx + 0.2 * u, ty + 0.14 * u]], "shrimp", {});
    poly("top", [[tx, ty], [tx + 0.2 * u, ty - 0.12 * u], [tx + 0.12 * u, ty - 0.02 * u]], "shrimpDark", { fine: true });
    // two small feelers from the head end of the C
    const a2 = Math.PI * 0.25, hx = cx + r * Math.cos(a2), hy = cy + r * Math.sin(a2);
    curve("top", [[hx, hy], [hx + 0.1 * u, hy - 0.16 * u]], "shrimpDark", ln);
    curve("top", [[hx, hy], [hx + 0.04 * u, hy - 0.2 * u]], "shrimpDark", ln);
  } else if (id === "blossomclip") {
    const e = ear(1), cx = e.bx - 0.22 * R, cy = e.by + 0.1 * R, u = Math.max(R, fl("span") * 1.7);
    for (const sd of [-1, 1]) ell("top", cx + sd * 0.2 * u, cy + 0.14 * u, ball(0.13 * u), ball(0.06 * u), sd * 0.6, "leaf");
    for (let i = 0; i < 5; i++) {
      const a = -Math.PI / 2 + (i * TAU) / 5;
      ell("top", cx + Math.cos(a) * 0.13 * u, cy + Math.sin(a) * 0.13 * u, ball(0.11 * u), ball(0.11 * u), a, i % 2 ? "blossomDeep" : "blossom");
    }
    ell("top", cx, cy, ball(0.05 * u), ball(0.05 * u), 0, "gold", { stroke: null });
  // ── Neck: over the collar
  } else if (id === "scarf" || id === "bandana" || id === "bell") {
    const inw = (q: Pt, d: number): Pt => { const l = Math.hypot(q[0], q[1]) || 1; return [q[0] * (1 - d / l), q[1] * (1 - d / l)]; }, pts = A.chin.pts.map((q) => inw(q, 0.12 * R));
    if (id === "scarf") {
      const wd = Math.max(0.42 * R, fl("span"));
      curve("neck", pts, "edge", wd + 2 * ln, { a: 0.9 });
      curve("neck", pts, "scarfA", wd);
      curve("neck", pts.map((q) => inw(q, -0.1 * R)), "scarfB", Math.max(0.07 * R, fl("line") * 1.5));
      curve("neck", pts.map((q) => inw(q, 0.1 * R)), "scarfB", Math.max(0.07 * R, fl("line") * 1.5));
      const t0 = pts[5], tw = Math.max(0.27 * R, fl("span")), tl = 0.5 * R;
      poly("neck", [[t0[0] - tw / 2, t0[1] - 0.05 * R], [t0[0] + tw / 2, t0[1] - 0.05 * R], [t0[0] + tw / 2 - 0.06 * R, t0[1] + tl], [t0[0] - tw / 2 - 0.06 * R, t0[1] + tl]], "scarfA");
      poly("neck", [[t0[0] - tw / 2 - 0.015 * R, t0[1] + tl * 0.55], [t0[0] + tw / 2 - 0.045 * R, t0[1] + tl * 0.55], [t0[0] + tw / 2 - 0.05 * R, t0[1] + tl * 0.7], [t0[0] - tw / 2 - 0.02 * R, t0[1] + tl * 0.7]], "scarfB", { stroke: null });
    } else if (id === "bandana") {
      const apex: Pt = [A.chin.front[0], Math.max(...pts.map((q) => q[1])) + 0.48 * R];
      poly("neck", [...pts.map((q) => inw(q, -0.06 * R)), apex], "bandanaRed");
      const kn = pts[2];
      poly("neck", [[kn[0] - 0.12 * R, kn[1]], [kn[0] - 0.4 * R, kn[1] + 0.3 * R], [kn[0] - 0.05 * R, kn[1] + 0.26 * R]], "bandanaRed", {});
      ell("neck", kn[0], kn[1], ball(0.1 * R), ball(0.1 * R), 0, "bandanaRed");
      ([[0, 0.34], [-0.28, 0.18], [0.28, 0.18]] as const).forEach(([x, y]) => ell("neck", A.chin.front[0] + x * R, A.chin.front[1] + y * R, ball(0.045 * R), ball(0.045 * R), 0, "white", { stroke: null, fine: true }));
    } else {
      const G = collarGeometry(p, s, D, o.collar, { dpr: A.dpr, detail: o.detail });
      let at: Pt = [A.neck.x, A.neck.y];
      if (G && G.tag) at = [G.tag.x, G.tag.y + G.tag.r]; else if (G && G.band) at = G.band[G.band.length >> 1] as Pt; else if (G && G.kerchief) at = G.kerchief.apex as Pt;
      const r = ball(0.2 * R);
      ell("neck", at[0], at[1] - 0.1 * R, ball(0.07 * R), ball(0.07 * R), 0, null, { stroke: "silver", sw: Math.max(ln * 1.4, fl("line")) });
      ell("neck", at[0], at[1] + 0.12 * R, r, r, 0, "gold");
      curve("neck", [[at[0] - r * 0.7, at[1] + 0.1 * R], [at[0] + r * 0.7, at[1] + 0.1 * R]], "goldDark", ln, { fine: true });
      ell("neck", at[0], at[1] + 0.12 * R + r * 0.55, ball(0.04 * R), ball(0.04 * R), 0, "goldDark", { stroke: null, fine: true });
    }
  }
  return full ? out : out.filter((sh) => !sh.fine);
}

/** A digest two implementations can compare within the tolerance: the number of shapes and points, the box that holds them (an ellipse counts as its axis-aligned box and its centre as a point) and the mean point. */
export function outfitDigest(shapes: readonly OutfitShape[]): { n: number; pts: number; bbox: number[]; mx: number; my: number } {
  let pts = 0, sx = 0, sy = 0, x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  const add = (x: number, y: number) => { pts++; sx += x; sy += y; x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); };
  for (const sh of shapes) {
    if (sh.k === "ellipse") { add(sh.x, sh.y); x0 = Math.min(x0, sh.x - sh.rx); x1 = Math.max(x1, sh.x + sh.rx); y0 = Math.min(y0, sh.y - sh.ry); y1 = Math.max(y1, sh.y + sh.ry); }
    else for (const q of sh.pts) add(q[0], q[1]);
  }
  return shapes.length ? { n: shapes.length, pts, bbox: [x0, y0, x1, y1], mx: sx / pts, my: sy / pts } : { n: 0, pts: 0, bbox: [0, 0, 0, 0], mx: 0, my: 0 };
}
