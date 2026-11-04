// The cat renderer: draws one cat into a Canvas 2D context, no images. A port of the drawing in
// design/prototype/notchmeow.html, which is the visual source of truth for the characters.
//
// Everything geometric comes from layout() in geometry.ts. The pass order is `PASSES`: a *behind* pass
// (glow, trails, ruff and bib, paws, ears), the head and its face, then a *front* pass (folded ears,
// whiskers, badge, particles, balls), so outfits (sub-project I) can sit on either side of the head.
//
// Below head width Ø28 the cat is the compact drawing: small coloured eyes (an iris in the coat's colours, a slit pupil, a catchlight and a thin rim: `smallEye`
// of smalleye.ts, given the coat's id; the black coats' are flat and bright; the expression shapes stay ink), no whiskers, and FLAT FILLS (`flatFillColors` and `FLAT_FILL` of geometry.ts:
// one colour for the head, the ears and the ruff, no rim gradient, a flat tabby crown and point mask), because a gradient cannot be seen at
// that size. Every compact cat wears the compact ear scale, and in the compact island the ears are also fitted under the top of the strip
// (`earCeiling`). Both are the contract's (A-0b, merged `6adf584`).

import { collarGeometry } from "./collar.ts";
import type { CollarGeometry } from "./collar.ts";
import { smallEye } from "./smalleye.ts";
import type { SmallEye } from "./smalleye.ts";
import { outfitEdge } from "./outfit.ts";
import type { OutfitShape } from "./outfit.ts";
import { outfitShapes, paintOutfit } from "./outfitdraw.ts";
import { FLAT_FILL, MOMO_WHITE, detailLevel, earFit, earScale, flatFillColors, layout, pupilOffset, supPoints } from "./geometry.ts";
import type { EarLayout, FlatColors, Layout } from "./geometry.ts";
import { COL, EZ, TAU, clamp, hex, lerp, rng } from "./base.ts";
import type { BadgeKind, StateName } from "./base.ts";
import type { Ball, CatPreset, EyeShape, Particle, Pose } from "./types.ts";
import { THEME } from "../theme.generated.ts";

type Ctx = CanvasRenderingContext2D;

/** What the renderer reads from a cat. The engine (BotEngine) satisfies it, and so does stillView(). */
export interface CatView {
  p: CatPreset;
  s: Pose;
  state: StateName;
  /** The state colour now, 0 to 255 (it fades between states). */
  col: number[];
  /** The glow colour now, 0 to 255, and its strength. */
  gc: number[];
  ga: number;
  /** How fast the cat is sliding sideways in R per second (zoomies leave a trail). */
  zv: number;
  parts: Particle[];
  balls: Ball[];
  badge: BadgeKind | null;
  /** Overrides the state colour of the badge. */
  badgeCol: string | null;
  blushBase: number;
  waveStart: number;
  waveUntil: number;
  eyeShape(): EyeShape;
  mouthOpen(): number;
  /** Milliseconds. */
  now(): number;
  /** The renderer leaves these for the next frame: where the cat was drawn (R, px), and where its mouth is (hairballs and files go there). */
  base: { x: number; y: number; R: number } | null;
  at: { x: number; y: number; R: number; D: number } | null;
  mouthAt: { x: number; y: number } | null;
}

/** A paw to draw behind the head: position in head-local px, how far it is out (0 to 1), rotation, toe beans showing. */
export interface PawSpec { x: number; y: number; k: number; rot: number; beans: boolean }

export interface DrawOptions {
  /** Optional fur strands. Flat colour is the default. */
  fur?: boolean;
  /** The state tint over the lower face, on by default. */
  tint?: boolean;
  /** The soft glow behind the head. */
  glow?: boolean;
  /** Paws to draw instead of the engine's wave paws. */
  paws?: readonly PawSpec[];
  /** Forces the detail level; by default head width Ø28 and up is full. */
  detail?: "full" | "compact";
  /** 1 puts the badge on the right of the head, -1 on the left (the compact notch). */
  badgeSide?: number;
  /** false hides the badge. */
  badge?: boolean;
  /** Extra squash on top of the pose, and extra tilt in radians: the drop view's travelling cat. */
  squash?: readonly [number, number];
  tilt?: number;
  /**
   * The y of the top of the strip the cat lives in, in the canvas's own coordinates: the ears are shrunk just enough that no tip rises
   * above it (the contract's earFit, on top of the compact ear scale; A-0b, merged `6adf584`). The compact island passes it, because the top of its strip
   * is the top of the screen.
   */
  earCeiling?: number;
  /**
   * The agent's collar (stage 6): a style (`tag`, `band` or `kerchief`; `off` or anything else draws nothing) and its colour as "#RRGGBB" (anything
   * else draws nothing). Drawn in the front pass, from the contract's `collarGeometry`, at every size from Ø12 up.
   */
  collar?: { style: string; col: string } | null;
  /** The device pixel ratio the collar's readability floors are in: default `min(2, devicePixelRatio)`, and 1 where there is no screen. */
  dpr?: number;
  /**
   * The outfit this cat wears (sub-project I): one of the 16 drawn outfit IDs, already resolved (never `auto`; `none`, null and anything else draw nothing). The caller decides who
   * wears it by the cat's role (outfitWorn): only a big cat gets one here. It is drawn at the contract's three slots, from `outfitGeometry`, and needs `earCeiling` for the compact island's room.
   */
  outfit?: string | null;
  /**
   * The y of the top of the canvas the outfit may use, in the canvas's own coordinates, when that is tighter than the strip (the desktop cat's canvas, whose top is the window's). The
   * outfit alone takes it: a hat is shortened to the room under it (outfitRoom, never below the floor) and the ears are still fitted by `earCeiling` alone. Without it the outfit uses `earCeiling`.
   */
  outfitCeiling?: number;
  /** `ink` draws the compact cat's plain resting eyes as the flat ink shapes they were before the small coloured eyes: the `?dev` contact sheet and frame-time check compare with them. */
  eyes?: "ink";
}

/** The ratio to size a collar for: the option, else the screen's (held to 2, as the canvases are sized). */
const dprOf = (o: DrawOptions): number =>
  typeof o.dpr === "number" && o.dpr > 0 ? o.dpr : Math.min(2, (typeof devicePixelRatio === "number" && devicePixelRatio) || 1);

/** A cat that never moves: icons, the contact sheet's first frame and tests. */
export function stillView(p: CatPreset, s: Pose, state: StateName = "idle"): CatView {
  return {
    p, s, state, col: hex(COL[state]), gc: [255, 255, 255], ga: 0.12, zv: 0, parts: [], balls: [], badge: null, badgeCol: null,
    blushBase: 0, waveStart: 0, waveUntil: 0, eyeShape: () => "pill", mouthOpen: () => 0, now: () => 0,
    base: null, at: null, mouthAt: null,
  };
}

// ── Little helpers ────────────────────────────────────────────────────────────

/** Rounded rectangle path. */
function rr(c: Ctx, x: number, y: number, w: number, h: number, r: number) {
  r = Math.max(0, Math.min(r, w / 2, h / 2));
  c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r);
  c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath();
}
function heartP(c: Ctx, s: number) {
  c.beginPath(); c.moveTo(0, 0.38 * s); c.bezierCurveTo(-1.05 * s, -0.15 * s, -0.5 * s, -0.95 * s, 0, -0.38 * s);
  c.bezierCurveTo(0.5 * s, -0.95 * s, 1.05 * s, -0.15 * s, 0, 0.38 * s); c.fill();
}
function starP(c: Ctx, o: number, i: number) {
  c.beginPath();
  for (let k = 0; k < 10; k++) { const r = k % 2 ? i : o, a = -Math.PI / 2 + (k * Math.PI) / 5; c.lineTo(Math.cos(a) * r, Math.sin(a) * r); }
  c.closePath(); c.fill();
}

/** A flat colour of `flatFillColors` (0 to 255, not rounded) as an "rgb()" string: the compact cat's one colour where a gradient cannot be seen. */
const rgbOf = (c: readonly number[]): string => `rgb(${c.map(Math.round).join(",")})`;

/** Superellipse as a Path2D; the points come from supPoints. */
function sup(rx: number, ry: number, n: number, dy: number, spike: number, count: number, steps = 200, bend: readonly [number, number] | null = null) {
  const path = new Path2D();
  supPoints(rx, ry, n, dy, spike, count, steps, bend).forEach(([x, y], i) => (i ? path.lineTo(x, y) : path.moveTo(x, y)));
  path.closePath();
  return path;
}

type W = (x: number, y: number) => [number, number];

/** An ellipse on the flat face, bent by the warp. */
function wEll(Wp: W, x: number, y: number, a: number, b: number, n = 20) {
  const P = new Path2D();
  for (let i = 0; i <= n; i++) { const t = (i / n) * TAU, [X, Y] = Wp(x + a * Math.cos(t), y + b * Math.sin(t)); i ? P.lineTo(X, Y) : P.moveTo(X, Y); }
  P.closePath();
  return P;
}
/** A wobbly patch (calico), bent by the warp. */
function wBlob(Wp: W, x: number, y: number, a: number, b: number, rot: number, seed: number, n = 32) {
  const P = new Path2D(), c = Math.cos(rot), s = Math.sin(rot);
  for (let i = 0; i <= n; i++) {
    const t = (i / n) * TAU, k = 1 + 0.12 * Math.sin(3 * t + seed) + 0.06 * Math.sin(5 * t + 2 * seed);
    const lx = a * Math.cos(t) * k, ly = b * Math.sin(t) * k;
    const [X, Y] = Wp(x + lx * c - ly * s, y + lx * s + ly * c);
    i ? P.lineTo(X, Y) : P.moveTo(X, Y);
  }
  P.closePath();
  return P;
}
/** A curved stroke on the flat face, bent by the warp. */
function wStroke(c: Ctx, Wp: W, col: string, w: number, pts: readonly number[]) {
  const [x0, y0, cx, cy, x1, y1] = pts;
  c.strokeStyle = col; c.lineWidth = w; c.lineCap = "round"; c.lineJoin = "round"; c.beginPath();
  for (let i = 0; i <= 12; i++) {
    const t = i / 12, m = 1 - t, [X, Y] = Wp(m * m * x0 + 2 * m * t * cx + t * t * x1, m * m * y0 + 2 * m * t * cy + t * t * y1);
    i ? c.lineTo(X, Y) : c.moveTo(X, Y);
  }
  c.stroke();
}
function momoWhite(Wp: W) {
  const P = new Path2D();
  MOMO_WHITE.forEach(([x, y], i) => { const [X, Y] = Wp(x, y); i ? P.lineTo(X, Y) : P.moveTo(X, Y); });
  P.closePath();
  return P;
}

// ── Optional fur lines: seeded strands, built once per preset (same seeds as the board) ──

interface Fur { head: { x: number; y: number; x2: number; y2: number; c: string }[]; ruff: { x: number; y: number; ux: number; uy: number; L: number; c: string }[] }
const FURC = new WeakMap<CatPreset, Fur>();
const FURDEF = { n: 420, l0: 0.04, l1: 0.05, w: 0.01, dark: "rgba(0,0,0,.22)", light: "rgba(255,255,255,.2)" };
let HIT: CanvasRenderingContext2D | null = null;

function furStrands(p: CatPreset): Fur {
  const cached = FURC.get(p);
  if (cached) return cached;
  const o = (p.furOpts || FURDEF) as typeof FURDEF & { wDark?: string; wLight?: string }, rx = p.rx, ry = p.ry;
  const head: Fur["head"] = [], ruff: Fur["ruff"] = [];
  let white: Path2D | null = null;
  if (p.coat === "tuxedo") { HIT ??= document.createElement("canvas").getContext("2d"); white = momoWhite((x, y) => [x * 100, y * 100]); }
  const eyes = [-1, 1].map((sd) => [Math.sin(sd * p.eye.th) * Math.cos(p.eye.ph) * rx, -Math.sin(p.eye.ph) * ry]);
  const nz = [0, -Math.sin(p.nosePh) * ry];
  let rand = rng(13);
  for (let i = 0; i < o.n; i++) {
    const x = (rand() * 2 - 1) * rx, y = (rand() * 2 - 1) * ry;
    if ((x / rx) ** 2 + (y / ry) ** 2 > 1) continue;
    if (eyes.some((q) => Math.hypot(x - q[0], (y - q[1]) * 1.25) < 0.3) || Math.hypot(x - nz[0], y - nz[1] - 0.1) < 0.32) continue;
    let dx: number, dy: number;
    if (y < -0.32) { dx = x * 0.35; dy = -1; } else { dx = x; dy = y + 0.5; }
    const m = Math.hypot(dx, dy) || 1, L = o.l0 + rand() * o.l1;
    const onW = !!(white && HIT && HIT.isPointInPath(white, x * 100, y * 100));
    head.push({ x, y, x2: x + (dx / m) * L, y2: y + (dy / m) * L, c: rand() < 0.55 ? (onW ? o.wDark! : o.dark) : (onW ? o.wLight! : o.light) });
  }
  if (p.ruff) {
    const r = p.ruff, e = 2 / 2.4;
    rand = rng(7);
    for (let i = 0; i < 300; i++) {
      const a = rand() * TAU, c = Math.cos(a), s = Math.sin(a);
      const ex = Math.sign(c) * Math.pow(Math.abs(c), e) * r.rx, ey = Math.sign(s) * Math.pow(Math.abs(s), e) * r.ry;
      const f = 0.7 + rand() * 0.32, x = ex * f, y = ey * f + r.dy;
      let dx = ex, dy = ey + 0.35 * Math.max(0, s);
      const m = Math.hypot(dx, dy) || 1;
      dx /= m; dy /= m;
      const j = (rand() - 0.5) * 0.5, ux = dx * Math.cos(j) - dy * Math.sin(j), uy = dx * Math.sin(j) + dy * Math.cos(j), L = 0.05 + rand() * 0.08;
      ruff.push({ x, y, ux, uy, L, c: rand() < 0.5 ? "rgba(214,192,156,.45)" : "rgba(84,66,50,.38)" });
    }
  }
  const out = { head, ruff };
  FURC.set(p, out);
  return out;
}

/** A whisker: a curve that thins toward its tip. */
function taper(c: Ctx, x0: number, y0: number, cx: number, cy: number, x1: number, y1: number, w0: number, col: string, a0: number) {
  const N = 16;
  c.strokeStyle = col; c.lineCap = "round";
  let px = x0, py = y0;
  for (let i = 1; i <= N; i++) {
    const s = i / N, m = 1 - s, x = m * m * x0 + 2 * m * s * cx + s * s * x1, y = m * m * y0 + 2 * m * s * cy + s * s * y1;
    c.globalAlpha = a0 * (1 - 0.7 * s); c.lineWidth = Math.max(0.35, w0 * (1 - 0.88 * s));
    c.beginPath(); c.moveTo(px, py); c.lineTo(x, y); c.stroke();
    px = x; py = y;
  }
  c.globalAlpha = 1;
}

// ── Ears, eyes ────────────────────────────────────────────────────────────────

/** One ear. `front` draws the folded flap of a Scottish Fold in the front pass, over the head. */
function drawEar(c: Ctx, p: CatPreset, ear: EarLayout, R: number, full: boolean, flat: FlatColors | null, front = false) {
  const E = p.ear, { bx, by, rot, h, bw, tip, cx, sd } = ear;
  c.save(); c.translate(bx, by); c.rotate(rot);
  const path = (k: number) => {
    c.beginPath(); c.moveTo(-bw * k, 0.25 * R); c.quadraticCurveTo(-bw * k * cx, -h * k * 0.4, -tip * 0.9, -h * k + tip * 1.3);
    c.quadraticCurveTo(0, -h * k - tip * 0.35, tip * 0.9, -h * k + tip * 1.3); c.quadraticCurveTo(bw * k * cx, -h * k * 0.4, bw * k, 0.25 * R); c.closePath();
  };
  const ec = p.earCols && p.earCols[sd < 0 ? 0 : 1];
  // Below Ø28 the ear's top-to-bottom shading cannot be seen: the flat colour of flatFillColors (the ear's own colour, if it has one) instead of a gradient.
  let g: string | CanvasGradient;
  if (flat) g = rgbOf(flat.ears[sd < 0 ? 0 : 1]);
  else { g = c.createLinearGradient(0, -h, 0, 0.25 * R); g.addColorStop(0, ec || p.top); g.addColorStop(1, ec || p.bot); }
  if (front) {
    const fw = bw * 0.62, yc = -h + tip * 0.8, ty = -h * 0.05;
    const flap = () => {
      c.beginPath(); c.moveTo(-fw, yc); c.quadraticCurveTo(0, yc - fw * 0.75, fw, yc); c.quadraticCurveTo(fw * 0.7, (yc + ty) / 2, 0, ty);
      c.quadraticCurveTo(-fw * 0.7, (yc + ty) / 2, -fw, yc); c.closePath();
    };
    c.save(); c.translate(0, 0.025 * R); c.fillStyle = "rgba(0,0,0,.2)"; flap(); c.fill(); c.restore();
    c.fillStyle = g; flap(); c.fill();
    if (full) {
      c.strokeStyle = "rgba(0,0,0,.2)"; c.lineWidth = 0.016 * R; c.lineCap = "round"; c.beginPath(); c.moveTo(-fw * 0.8, yc + 0.02 * R);
      c.quadraticCurveTo(0, yc - fw * 0.5, fw * 0.8, yc + 0.02 * R); c.stroke();
    }
    c.restore();
    return;
  }
  c.fillStyle = g; path(1); c.fill();
  if (p.rimLight) { c.strokeStyle = "rgba(255,255,255,.22)"; c.lineWidth = Math.max(0.8, 0.013 * R); path(1); c.stroke(); }
  c.fillStyle = p.inner; c.globalAlpha = 0.9; path(0.6); c.fill(); c.globalAlpha = 1;
  if (E.tuft && full) {
    c.strokeStyle = p.inner; c.globalAlpha = 0.7; c.lineCap = "round"; c.lineWidth = 0.022 * R;
    for (const k of [-1, 0, 1]) { c.beginPath(); c.moveTo(k * bw * 0.3, 0.06 * R); c.quadraticCurveTo(k * bw * 0.5, -h * 0.25, k * bw * 0.42 + (k >= 0 ? 1 : -1) * 0.02 * R, -h * 0.5); c.stroke(); }
    c.globalAlpha = 1; c.strokeStyle = p.top; c.lineWidth = 0.025 * R; c.beginPath(); c.moveTo(0, -h + tip * 0.2); c.lineTo(sd * 0.015 * R, -h - 0.05 * R); c.stroke();
  }
  c.restore();
}

function almondPath(c: Ctx, p: CatPreset, sd: number, R: number, open: number) {
  const E = p.eye, w = E.w * R, h = E.h * R * Math.max(open, 0.06), H = E.h * R, k = E.round ? 2.2 : 1.85;
  const iy = (E.round ? 0.04 : 0.12) * H, oy = (E.round ? -0.04 : -0.18) * H, ix = -sd * w, ox = sd * w;
  c.beginPath(); c.moveTo(ix, iy); c.quadraticCurveTo(0, -h * k, ox, oy); c.quadraticCurveTo(0, H * (0.55 + 0.45 * Math.max(open, 0.06)) * k, ix, iy); c.closePath();
}

/** The realistic eye: iris gradient, dilating pupil, Momo's yellow lid ring, catchlights, liner. */
function almondEye(c: Ctx, s: Pose, p: CatPreset, sd: number, R: number, pupil: number, open: number) {
  const E = p.eye, w = E.w * R, h = E.h * R, a0 = c.globalAlpha;
  if (open < 0.22) {
    c.strokeStyle = p.ink; c.globalAlpha = a0 * 0.9; c.lineWidth = Math.max(1, 0.045 * R); c.lineCap = "round"; c.beginPath();
    c.moveTo(-w, 0); c.quadraticCurveTo(0, 0.4 * h, w, 0); c.stroke(); c.globalAlpha = a0;
    return;
  }
  c.save(); almondPath(c, p, sd, R, open); c.clip();
  const g = c.createRadialGradient(0, 0, 0, 0, 0, w * 1.1), ir = (sd > 0 && p.irisR) || p.iris;
  g.addColorStop(0, ir[0]); g.addColorStop(1, ir[1]); c.fillStyle = g; c.fillRect(-w * 1.3, -h * 3, w * 2.6, h * 6);
  const [px, py] = pupilOffset(s.yaw, s.pitch, w, h);
  c.fillStyle = THEME.cat.pupil; c.beginPath(); c.ellipse(px, py, w * (p.pupil0 + 0.5 * pupil), h * 1.1, 0, 0, TAU); c.fill();
  if (p.lidTint) { c.save(); c.strokeStyle = p.lidTint; c.globalAlpha = a0 * 0.85; c.lineWidth = 0.04 * R; c.scale(0.92, 0.88); almondPath(c, p, sd, R, open); c.stroke(); c.restore(); }
  c.fillStyle = "rgba(255,255,255,.92)"; c.beginPath(); c.arc(-0.32 * w, -0.32 * h, 0.2 * w, 0, TAU); c.fill();
  c.beginPath(); c.arc(0.22 * w, 0.3 * h, 0.09 * w, 0, TAU); c.fill();
  c.restore(); c.strokeStyle = p.liner; c.lineWidth = 0.05 * R; almondPath(c, p, sd, R, open); c.stroke();
}

/** Expression eyes (upstream's shapes), in the cat's ink colour. They are the eyes of every compact cat. */
function inkEye(c: Ctx, shape: EyeShape, sd: number, w: number, h: number, open: number, T: number, col: string) {
  c.fillStyle = col; c.strokeStyle = col; c.lineCap = "round";
  const pill = (W: number, H: number) => { const hh = Math.max(H * open, 0.3 * W); rr(c, -W / 2, -hh / 2, W, hh, Math.min(W, hh) / 2); c.fill(); };
  const hap = () => { c.lineWidth = 0.5 * w; c.beginPath(); c.arc(0, 0.18 * h, 0.82 * w, 1.12 * Math.PI, 1.88 * Math.PI); c.stroke(); };
  switch (shape) {
    case "pill": pill(w, h); break;
    case "wide": pill(w * 1.16, h * 1.12); break;
    case "dot": c.beginPath(); c.arc(0, 0, 0.45 * w, 0, TAU); c.fill(); break;
    case "line": c.rotate(-sd * 0.2); rr(c, -0.78 * w, -0.21 * w, 1.56 * w, 0.42 * w, 0.21 * w); c.fill(); break;
    case "flat": rr(c, -0.72 * w, -0.2 * w, 1.44 * w, 0.4 * w, 0.2 * w); c.fill(); break;
    case "happy": hap(); break;
    case "closed": c.lineWidth = 0.36 * w; c.beginPath(); c.arc(0, -0.08 * h, 0.78 * w, 0.15 * Math.PI, 0.85 * Math.PI); c.stroke(); break;
    case "spiral": {
      c.lineWidth = 0.22 * w; c.rotate(T * 9 * sd); c.beginPath();
      for (let a = 0; a < 4.4 * Math.PI; a += 0.2) { const r = 0.06 * w + 0.058 * w * a, x = Math.cos(a) * r, y = Math.sin(a) * r; a ? c.lineTo(x, y) : c.moveTo(x, y); }
      c.stroke(); break;
    }
    case "heart": c.fillStyle = THEME.cat.heart; heartP(c, 1.2 * w); break;
    case "star": c.fillStyle = THEME.cat.star; c.rotate(T * 1.5 * sd); starP(c, 1.05 * w, 0.46 * w); break;
    case "tired": rr(c, -w / 2, -0.02 * h, w, 0.38 * h, Math.min(w, 0.38 * h) / 2); c.fill(); rr(c, -0.62 * w, -0.12 * h - 0.11 * w, 1.24 * w, 0.22 * w, 0.11 * w); c.fill(); break;
    case "wink": if (sd < 0) pill(w, h); else hap(); break;
  }
}
const REAL: ReadonlySet<EyeShape> = new Set<EyeShape>(["pill", "wide", "dot", "tired"]);

/**
 * The small coloured eye of the compact level, painted in the eye's own frame from `smallEye`'s geometry: the iris is a radial gradient from the coat's
 * `iris[0]` at the centre to `iris[1]` at the edge (`irisR` for the right eye when the coat has one), the pupil is the theme's pupil colour, the catchlight
 * white at 0.92, the rim the coat's liner colour; a blink or squint is the closed line in the ink colour at 0.9. The black coats (Midnight, Oreo, Mocha, and their
 * kittens: `smallEye` says `flat`) glow like the old pill instead: one flat fill of the lighter of the coat's two iris colours by luminance, no rim, the
 * catchlight kept. The prototype's `smallEyeDraw` is the reference.
 */
function smallEyeDraw(c: Ctx, p: CatPreset, sd: number, G: SmallEye) {
  const a0 = c.globalAlpha;
  if (G.closed) {
    const l = G.line;
    c.strokeStyle = p.ink; c.globalAlpha = a0 * 0.9; c.lineWidth = l.width; c.lineCap = "round"; c.beginPath(); c.moveTo(l.x0, l.y0);
    c.quadraticCurveTo(l.cx, l.cy, l.x1, l.y1); c.stroke(); c.globalAlpha = a0;
    return;
  }
  const I = G.iris, P = G.pupil, Lt = G.light, ir = (sd > 0 && p.irisR) || p.iris;
  if (G.flat) c.fillStyle = lum(ir[0]) >= lum(ir[1]) ? ir[0] : ir[1];
  else {
    const g = c.createRadialGradient(0, 0, 0, 0, 0, I.r);
    g.addColorStop(0, ir[0]); g.addColorStop(1, ir[1]);
    c.fillStyle = g;
  }
  c.beginPath(); c.ellipse(0, 0, I.rx, I.ry, 0, 0, TAU); c.fill();
  c.fillStyle = THEME.cat.pupil; c.beginPath(); c.ellipse(P.x, P.y, P.rx, P.ry, 0, 0, TAU); c.fill();
  c.fillStyle = "rgba(255,255,255,.92)"; c.beginPath(); c.arc(Lt.x, Lt.y, Lt.r, 0, TAU); c.fill();
  if (!G.flat) { c.strokeStyle = p.liner; c.lineWidth = G.rim; c.beginPath(); c.ellipse(0, 0, I.rx, I.ry, 0, 0, TAU); c.stroke(); }
}

/** The relative luminance of a #RRGGBB colour: which of a bright coat's two iris colours is the lighter. */
function lum(hex: string): number {
  const n = parseInt(hex.slice(1), 16);
  return 0.2126 * ((n >> 16) & 255) + 0.7152 * ((n >> 8) & 255) + 0.0722 * (n & 255);
}

// ── Paws, badge, particles, mouth, hairballs, files ───────────────────────────

export function drawPaw(c: Ctx, p: CatPreset, R: number, q: PawSpec) {
  const k = q.k, w = 0.2 * R * k, h = 0.18 * R * k;
  if (w < 0.6) return;
  c.save(); c.translate(q.x, q.y); c.rotate(q.rot || 0);
  const toes = [-1, 0, 1].map((i) => [i * w * 0.55, -h * 0.62]);
  c.fillStyle = p.paw; c.strokeStyle = "rgba(0,0,0,.28)"; c.lineWidth = Math.max(0.6, 0.012 * R);
  c.beginPath();
  for (const [x, y] of toes) { c.moveTo(x + w * 0.36, y); c.ellipse(x, y, w * 0.36, h * 0.38, 0, 0, TAU); }
  c.moveTo(w, 0); c.ellipse(0, 0, w, h * 0.85, 0, 0, TAU); c.stroke(); c.fill();
  if (q.beans) {
    c.fillStyle = p.bean; c.beginPath(); c.ellipse(0, h * 0.12, w * 0.42, h * 0.32, 0, 0, TAU); c.fill();
    for (const [x, y] of toes) { c.beginPath(); c.ellipse(x, y + h * 0.02, w * 0.16, h * 0.17, 0, 0, TAU); c.fill(); }
  } else {
    c.strokeStyle = "rgba(0,0,0,.25)";
    for (const s of [-1, 1]) { c.beginPath(); c.moveTo(s * w * 0.28, -h * 0.85); c.lineTo(s * w * 0.24, -h * 0.35); c.stroke(); }
  }
  c.restore();
}

/** Paw positions for the engine's wave (upstream greet timings), head-local. */
export function enginePaws(e: CatView, rx: number, ry: number): PawSpec[] {
  const s = e.s;
  if (s.paws <= 0.01) return [];
  const n = e.now(), bodyH = 2 * ry, waving = e.waveStart > 0 && n >= e.waveStart && n < e.waveUntil, out: PawSpec[] = [];
  for (const sd of [-1, 1]) {
    let x = sd * rx * 1.0, y = ry * 0.78, rot = 0, beans = false;
    if (sd > 0 && waving) {
      const wt = (n - e.waveStart) / 1000, rise = EZ.out(Math.min(1, wt / 0.18));
      x = lerp(x, rx * 1.12 + Math.cos(13 * wt) * 0.06 * bodyH, rise);
      y = lerp(y, -ry * 0.12 - Math.sin(13 * wt) * 0.12 * bodyH, rise);
      rot = (0.35 + Math.sin(13 * wt) * 0.3) * rise;
      beans = rise > 0.5;
    } else if (sd < 0 && waving) y += Math.sin((6 * (n - e.waveStart)) / 1000) * 0.04 * bodyH;
    out.push({ x, y, k: s.paws, rot, beans });
  }
  return out;
}

function drawBadge(c: Ctx, kind: BadgeKind, col: string, x: number, y: number, R: number, k: number, small: boolean, T: number) {
  c.save(); c.translate(x, y); c.scale(k, k);
  if (kind === "dots" && small) {
    const r = R * 0.22 * (1 + 0.25 * Math.sin(((T * 2.4) % 1) * TAU));
    c.fillStyle = "#000"; c.beginPath(); c.arc(0, 0, R * 0.26, 0, TAU); c.fill(); c.fillStyle = col; c.beginPath(); c.arc(0, 0, r, 0, TAU); c.fill();
  } else if (kind === "dots") {
    c.fillStyle = col; rr(c, -0.36 * R, -0.18 * R, 0.72 * R, 0.36 * R, 0.18 * R); c.fill(); c.fillStyle = "#fff";
    for (let i = 0; i < 3; i++) {
      const ph = (((2.4 * T - 0.22 * i) % 1) + 1) % 1, r = 0.055 * R * (1 + 0.4 * Math.max(0, Math.sin(TAU * ph)));
      c.beginPath(); c.arc((i - 1) * 0.18 * R, 0, r, 0, TAU); c.fill();
    }
  } else if (kind === "bang" || kind === "question") {
    c.fillStyle = "#000"; c.beginPath(); c.arc(0, 0, 0.3 * R, 0, TAU); c.fill(); c.fillStyle = col; c.beginPath(); c.arc(0, 0, 0.23 * R, 0, TAU); c.fill();
    if (!small) {
      c.fillStyle = "#fff"; c.font = `900 ${0.32 * R}px system-ui,sans-serif`; c.textAlign = "center"; c.textBaseline = "middle"; c.fillText(kind === "bang" ? "!" : "?", 0, 0.02 * R);
    }
  } else {
    c.fillStyle = "#000"; c.beginPath(); c.arc(0, 0, 0.2 * R, 0, TAU); c.fill(); c.fillStyle = col; c.beginPath(); c.arc(0, 0, 0.135 * R, 0, TAU); c.fill();
  }
  c.restore();
}

function drawParticles(c: Ctx, e: CatView, cx: number, cy: number, R: number) {
  for (const p of e.parts) {
    if (p.age < 0) continue;
    const k = p.age / p.life, al = k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8;
    const x = cx + (p.x + p.vx * p.age) * R * 1.3, y = cy + (p.y + p.vy * p.age) * R * 1.3, sz = R * p.size * (1 + 0.4 * k);
    c.save(); c.globalAlpha = Math.max(0, al); c.translate(x, y);
    switch (p.k) {
      case "heart": c.rotate(Math.sin(6 * p.age) * 0.3); c.fillStyle = THEME.cat.heart; heartP(c, sz * 1.6); break;
      case "star": c.rotate(p.rot + 2 * p.age); c.fillStyle = THEME.cat.star; starP(c, sz, sz * 0.45); break;
      case "spark": c.rotate(p.rot); c.fillStyle = "#fff"; starP(c, sz * 0.8, sz * 0.18); break;
      case "sweat": c.fillStyle = THEME.cat.sweat; c.beginPath(); c.moveTo(0, -sz); c.quadraticCurveTo(sz * 0.8, sz * 0.3, 0, sz * 0.8); c.quadraticCurveTo(-sz * 0.8, sz * 0.3, 0, -sz); c.fill(); break;
      case "dust": c.fillStyle = "rgba(225,225,232,.55)"; c.beginPath(); c.arc(0, 0, sz * (0.6 + k * 0.9), 0, TAU); c.fill(); break;
      case "hair": c.rotate(p.rot + p.age * 1.5); c.strokeStyle = e.p.hairLight; c.lineWidth = Math.max(0.6, R * 0.014); c.lineCap = "round"; c.beginPath(); c.moveTo(-sz * 0.6, 0); c.quadraticCurveTo(0, -sz * 0.5, sz * 0.6, 0); c.stroke(); break;
      case "z": c.fillStyle = "rgb(209,219,235)"; c.font = `700 ${1.9 * sz}px system-ui,sans-serif`; c.textAlign = "center"; c.textBaseline = "middle"; c.fillText("z", 0, 0); break;
    }
    c.restore();
  }
}

/**
 * Mouth: a closed ω that can smile, frown, skew or wobble, with an optional tongue blep,
 * or an open mouth that runs from a wide D (meow, hiss, yawn) to a round 'o'.
 */
function drawMouth(c: Ctx, p: CatPreset, s: Pose, R: number, nx: number, my: number, nf: number, full: boolean, mo: number, T: number) {
  const sm = clamp(s.smile, -1, 1), sk = clamp(s.mskew, -1, 1), tg = clamp(s.tongue, 0, 1), rd = clamp(s.mround, 0, 1), wv = clamp(s.wavy, 0, 1);
  const y0 = my + 0.05 * R, cxm = nx + sk * 0.035 * R * nf, lw = 0.03 * R;
  c.lineCap = "round"; c.lineJoin = "round";
  if (mo > 0.04) {
    const m = Math.min(mo, 1.3), w = 0.13 * R * (0.6 + 0.4 * m) * (1 - 0.45 * rd) * (1 + 0.25 * Math.max(0, sm)) * nf, h = 0.21 * R * m * (1 - 0.3 * rd) + 0.012 * R, top = y0 - 0.012 * R;
    // The opening hangs under the ω upper lip; as it rounds into an 'o' the lip lifts into the top of the ring.
    const L = 0.055 * R * (1 - rd), ty = top - h * 0.35 * rd, cty = top - h * 0.3 * rd + L, bot = top + h * (1.15 + 0.15 * rd) + L * 0.5;
    const lip = () => { c.moveTo(cxm - w, top); c.quadraticCurveTo(cxm - w * 0.5, cty, cxm, ty); c.quadraticCurveTo(cxm + w * 0.5, cty, cxm + w, top); };
    const path = () => { c.beginPath(); lip(); c.bezierCurveTo(cxm + w, bot, cxm - w, bot, cxm - w, top); c.closePath(); };
    c.fillStyle = THEME.cat.mouthInside; path(); c.fill();
    c.save(); path(); c.clip(); c.fillStyle = THEME.cat.tongue; c.beginPath(); c.ellipse(cxm, top + h * 0.95, w * 0.62, h * 0.34, 0, 0, TAU); c.fill(); c.restore();
    if (m > 0.45 && rd < 0.5 && full) {
      c.fillStyle = THEME.cat.teeth;
      for (const sd of [-1, 1]) { const fx = cxm + sd * w * 0.55, fy = top + L * 0.55; c.beginPath(); c.moveTo(fx - 0.022 * R, fy); c.lineTo(fx + 0.022 * R, fy); c.lineTo(fx, fy + 0.055 * R); c.closePath(); c.fill(); }
    }
    if (tg > 0.05) {
      const tl = (0.03 + 0.07 * tg) * R, tw = Math.max(w * 0.5, 0.05 * R * nf), ty2 = top + h * 0.9;
      c.fillStyle = THEME.cat.tongue; c.beginPath(); c.moveTo(cxm - tw, top + h * 0.7); c.lineTo(cxm - tw, ty2 + tl * 0.4); c.quadraticCurveTo(cxm - tw, ty2 + tl * 1.2, cxm, ty2 + tl * 1.2);
      c.quadraticCurveTo(cxm + tw, ty2 + tl * 1.2, cxm + tw, ty2 + tl * 0.4); c.lineTo(cxm + tw, top + h * 0.7); c.closePath(); c.fill();
      if (full) { c.strokeStyle = "rgba(150,50,70,.6)"; c.lineWidth = lw * 0.6; c.beginPath(); c.moveTo(cxm, top + h * 0.95); c.lineTo(cxm, ty2 + tl * 0.9); c.stroke(); }
    }
    if (full) {
      c.strokeStyle = p.mouthLine; c.lineWidth = lw; c.beginPath(); c.moveTo(nx, my); c.lineTo(cxm, ty); c.stroke();
      const a0 = c.globalAlpha; c.globalAlpha = a0 * (1 - rd); c.beginPath(); lip(); c.stroke(); c.globalAlpha = a0;
    }
    return;
  }
  if (!full) return;
  if (tg > 0.03) {
    const th = (0.025 + 0.045 * tg) * R;
    c.fillStyle = THEME.cat.tongue; c.beginPath(); c.ellipse(cxm, y0 + 0.035 * R + th * 0.5, 0.042 * R * nf, th, 0, 0, TAU); c.fill();
    c.strokeStyle = "rgba(150,50,70,.55)"; c.lineWidth = lw * 0.5; c.beginPath(); c.moveTo(cxm, y0 + 0.04 * R); c.lineTo(cxm, y0 + 0.035 * R + th * 0.9); c.stroke();
  }
  const mw = 0.15 * R * nf * (1 + 0.18 * Math.max(0, sm));
  c.strokeStyle = p.mouthLine; c.lineWidth = lw; c.beginPath(); c.moveTo(nx, my); c.lineTo(cxm, y0);
  if (wv > 0.05) {
    c.moveTo(cxm - mw, y0 + 0.03 * R);
    for (let i = 1; i <= 24; i++) { const t = i / 24; c.lineTo(cxm - mw + 2 * mw * t, y0 + 0.03 * R + Math.sin(t * TAU * 2.5 + T * 6) * 0.022 * R * wv); }
  } else {
    const lobe = 0.08 * R * (1 - 0.6 * Math.max(0, -sm)), cL = y0 - sm * 0.05 * R - sk * 0.035 * R, cR = y0 - sm * 0.05 * R + sk * 0.035 * R;
    c.moveTo(cxm - mw, cL); c.quadraticCurveTo(cxm - mw / 2, y0 + lobe, cxm, y0); c.quadraticCurveTo(cxm + mw / 2, y0 + lobe, cxm + mw, cR);
  }
  c.stroke();
}

/** A small file icon with its extension on it: what a refused file looks like inside a hairball, and in flight to the mouth. */
export function drawFileIcon(c: Ctx, x: number, y: number, s: number, rot: number, ext: string) {
  c.save(); c.translate(x, y); c.rotate(rot);
  const w = s * 0.78, h = s, f = s * 0.24;
  c.fillStyle = THEME.cat.paper; c.beginPath(); c.moveTo(-w / 2, -h / 2); c.lineTo(w / 2 - f, -h / 2); c.lineTo(w / 2, -h / 2 + f); c.lineTo(w / 2, h / 2); c.lineTo(-w / 2, h / 2); c.closePath(); c.fill();
  c.fillStyle = THEME.cat.paperFold; c.beginPath(); c.moveTo(w / 2 - f, -h / 2); c.lineTo(w / 2 - f, -h / 2 + f); c.lineTo(w / 2, -h / 2 + f); c.closePath(); c.fill();
  c.fillStyle = THEME.cat.paperLabel; rr(c, -w / 2 + s * 0.07, h * 0.06, w - s * 0.14, s * 0.24, s * 0.05); c.fill();
  c.fillStyle = "#fff"; c.font = `700 ${s * 0.15}px system-ui,sans-serif`; c.textAlign = "center"; c.textBaseline = "middle"; c.fillText(ext, 0, h * 0.06 + s * 0.125);
  c.restore();
}

/** Hairballs (and rejected files wrapped in fur) bounce once and roll away. */
function drawBalls(c: Ctx, e: CatView, cx: number, cy: number, R: number) {
  const p = e.p;
  for (const b of e.balls) {
    const a = Math.min(1, (b.life - b.age) / 0.5);
    c.save(); c.translate(cx + b.x * R, cy + b.y * R); c.rotate(b.rot); c.globalAlpha = Math.max(0, a);
    const r = rng(b.seed);
    let fw = 0.17 * R, fh = 0.11 * R;
    if (b.file) { drawFileIcon(c, 0, 0, 0.36 * R, 0, b.file); fw = 0.17 * R; fh = 0.2 * R; }
    else { c.fillStyle = p.hair; c.beginPath(); c.ellipse(0, 0, fw, fh, 0, 0, TAU); c.fill(); }
    c.lineCap = "round"; c.lineWidth = Math.max(0.6, 0.014 * R);
    for (let i = 0; i < (b.file ? 26 : 20); i++) {
      const t = r() * TAU, ex = Math.cos(t) * fw, ey = Math.sin(t) * fh, L = (0.03 + r() * 0.05) * R;
      c.strokeStyle = r() < 0.5 ? p.hairDark : p.hairLight;
      c.beginPath(); c.moveTo(ex * 0.75, ey * 0.75); c.quadraticCurveTo(ex + Math.cos(t + 0.9) * L * 0.6, ey + Math.sin(t + 0.9) * L * 0.6, ex + Math.cos(t + 0.3) * L, ey + Math.sin(t + 0.3) * L); c.stroke();
    }
    if (!b.file) { c.fillStyle = "rgba(255,255,255,.3)"; c.beginPath(); c.ellipse(-fw * 0.3, -fh * 0.4, fw * 0.3, fh * 0.2, -0.3, 0, TAU); c.fill(); }
    c.restore();
  }
}

// ── The cat: a behind pass, the head, a front pass ───────────────────────────

/** Everything one frame of one cat needs, worked out once and shared by the three passes. */
export interface CatFrame {
  e: CatView;
  p: CatPreset;
  /** The pose, with the options' extra squash and tilt applied. */
  s: Pose;
  L: Layout;
  o: DrawOptions;
  /** Seconds. */
  T: number;
  D: number;
  fur: Fur | null;
  /** The compact cat's flat colours (flatFillColors), or null for the full cat: `detailLevel(D, detail).flatFill`, that is `!L.full`. */
  flat: FlatColors | null;
  /** The shapes of the outfit it wears this frame (outfit.ts), or null when it is bare; `edge` is the thin edge's colour on this coat. */
  outfit: OutfitShape[] | null;
  edge: "light" | "dark";
}

/** Works out the frame: the pose, the layout and the fur. Leaves e.base and e.at for the next frame. */
export function frameOf(e: CatView, cx: number, cy: number, D: number, o: DrawOptions = {}): CatFrame {
  const p = e.p, T = e.now() / 1000;
  const s: Pose = o.squash || o.tilt ? { ...e.s, sx: e.s.sx * (o.squash ? o.squash[0] : 1), sy: e.s.sy * (o.squash ? o.squash[1] : 1), tilt: e.s.tilt + (o.tilt || 0) } : e.s;
  const lv = detailLevel(D, o.detail), k0 = lv.full ? 1 : earScale(D); // every compact cat wears the compact ear scale
  const opts = { T, detail: o.detail, badgeSide: o.badgeSide };
  let ek = k0;
  let L = layout(p, s, cx, cy, D, { ...opts, earScale: ek });
  // In the compact island the top of the strip is the top of the screen: shrink the ears just enough that no tip leaves it, on top of the
  // compact ear scale (earScale(D) * f; A-0b, merged `6adf584`).
  if (o.earCeiling !== undefined) {
    const f = earFit(L, s, o.earCeiling);
    if (f < 1) { ek = k0 * f; L = layout(p, s, cx, cy, D, { ...opts, earScale: ek }); }
  }
  e.base = L.base; e.at = L.at;
  const flat = lv.flatFill ? flatFillColors(p) : null;
  const fur = o.fur && L.full && L.R >= 30 && !p.hairless ? furStrands(p) : null;
  // The outfit, if this cat wears one: its shapes for this pose, with the room above the crown that the compact island's strip leaves a hat (the ears' ceiling). A kitten is bare, always.
  const outfit = o.outfit && p.kitten !== true ? outfitShapes(o.outfit, p, s, D, L.head.y, o.outfitCeiling ?? o.earCeiling, { dpr: dprOf(o), detail: o.detail, earScale: ek, collar: o.collar && HEX6.test(o.collar.col) ? o.collar.style : undefined }) : null;
  return { e, p, s, L, o, T, D, fur, flat, outfit, edge: outfit ? outfitEdge(p) : "dark" };
}

/** Draws in the head's own frame: its centre, tilt and squash. */
function inHead(c: Ctx, f: CatFrame, draw: () => void) {
  c.save(); c.translate(f.L.head.x, f.L.head.y); c.rotate(f.s.tilt); c.scale(f.s.sx, f.s.sy);
  draw();
  c.restore();
}

/** The behind pass: the glow, the zoomies' afterimages, the ruff and bib, the paws and the ears. */
export function drawBehindPass(c: Ctx, f: CatFrame) {
  const { e, p, L, o, D, fur, flat } = f, { R, full, rx, ry, steps } = L, { x: cx, y: cy } = L.head;
  if (o.glow && e.ga > 0.005) {
    const gr = c.createRadialGradient(cx, cy, 0, cx, cy, R * 2.3), g = e.gc.map(Math.round);
    gr.addColorStop(0, `rgba(${g},${e.ga})`); gr.addColorStop(1, `rgba(${g},0)`); c.fillStyle = gr; c.fillRect(cx - R * 2.4, cy - R * 2.4, R * 4.8, R * 4.8);
  }
  // Zoomies: afterimages and speed lines behind a cat that is moving fast.
  const zv = e.zv || 0;
  if (Math.abs(zv) > 1.1 && D >= 16) {
    const k = Math.min(1, (Math.abs(zv) - 1.1) / 2.5), dir = Math.sign(zv);
    c.save();
    for (let i = 1; i <= 3; i++) { c.globalAlpha = (0.2 * k) / i; c.fillStyle = p.ruff ? p.ruff.col[0] : p.top; c.beginPath(); c.ellipse(cx - dir * i * 0.3 * R * k, cy, rx, ry, 0, 0, TAU); c.fill(); }
    c.globalAlpha = 0.6 * k; c.strokeStyle = "#fff"; c.lineCap = "round"; c.lineWidth = Math.max(1, 0.025 * R);
    for (const [yy, l] of [[-0.5, 0.7], [-0.08, 1], [0.32, 0.8], [0.68, 0.5]]) { const x0 = cx - dir * (rx + 0.15 * R), y = cy + yy * R; c.beginPath(); c.moveTo(x0, y); c.lineTo(x0 - dir * l * 0.75 * R * k, y); c.stroke(); }
    c.restore();
  }
  inHead(c, f, () => {
    // Ruff and neck bib sit behind the head, with a little parallax.
    if (p.ruff) {
      const r = p.ruff;
      c.save(); c.translate(L.ruff.dx, L.ruff.dy);
      const rp = sup(r.rx * R, r.ry * R, 2.4, r.dy * R, 0.06, 18, steps);
      if (flat?.ruff) c.fillStyle = rgbOf(flat.ruff); // below Ø28 the ruff's shading cannot be seen: one flat colour
      else {
        const g = c.createRadialGradient(0, r.dy * R, 0.55 * R, 0, r.dy * R, 1.55 * R);
        g.addColorStop(0, r.col[1]); g.addColorStop(1, r.col[0]); c.fillStyle = g;
      }
      c.fill(rp);
      if (fur) {
        c.save(); c.clip(rp); c.lineCap = "round"; c.lineWidth = Math.max(0.6, 0.012 * R);
        for (const q of fur.ruff) { const x = q.x * R, y = q.y * R, l = q.L * R; c.strokeStyle = q.c; c.beginPath(); c.moveTo(x - q.ux * l * 0.5, y - q.uy * l * 0.5); c.quadraticCurveTo(x - q.uy * l * 0.15, y + q.ux * l * 0.15, x + q.ux * l * 0.5, y + q.uy * l * 0.5); c.stroke(); }
        c.restore();
      }
      const by = (r.ry + r.dy) * R;
      c.fillStyle = p.bib!; c.beginPath(); c.moveTo(-0.2 * R, by * 0.97); c.quadraticCurveTo(-0.12 * R, by * 0.8, 0, by * 0.72); c.quadraticCurveTo(0.12 * R, by * 0.8, 0.2 * R, by * 0.97);
      c.quadraticCurveTo(0.1 * R, by * 1.03, 0.04 * R, by * 0.99); c.lineTo(0, by * 1.06); c.lineTo(-0.04 * R, by * 0.99); c.quadraticCurveTo(-0.1 * R, by * 1.03, -0.2 * R, by * 0.97); c.fill();
      c.restore();
    }
    for (const q of o.paws || enginePaws(e, rx, ry)) drawPaw(c, p, R, q);
    for (const ear of L.ears) drawEar(c, p, ear, R, full, flat);
    if (f.outfit) paintOutfit(c, f.outfit, "behind", f.edge); // bunny ears: the head covers their roots
  });
}

/** The head: its shape, the markings, the state tint, the blush, the eyes, the mouth and the nose, and the rim light. */
export function drawHeadPass(c: Ctx, f: CatFrame) {
  const { e, p, s, L, o, T, fur, flat } = f, { R, full, rx, ry, fa, W, steps } = L;
  inHead(c, f, () => {
    const head = sup(rx, ry, p.n, 0, p.fluff ? 0.035 : 0, 14, steps, L.bend);
    if (flat) c.fillStyle = rgbOf(flat.head); // below Ø28 the coat's top-to-bottom shading cannot be seen: one flat colour
    else {
      const g = c.createLinearGradient(0.45 * rx, -ry, -0.45 * rx, ry);
      g.addColorStop(0, p.top); g.addColorStop(1, p.bot); c.fillStyle = g;
    }
    c.fill(head);
    c.save(); c.clip(head); c.globalAlpha = fa;
    // Markings, warped onto the turning head.
    if (p.coat === "tuxedo") { c.fillStyle = p.white!; c.fill(momoWhite(W)); }
    else if (p.coat === "tabby") {
      const sc = hex(p.stripe!).join(","), [bx, by] = W(0, -0.88);
      if (flat) { const k = FLAT_FILL.crown; c.fillStyle = `rgba(${sc},${k.alpha})`; c.beginPath(); c.ellipse(bx, by, k.rx * R, k.ry * R, 0, 0, TAU); c.fill(); } // the crown band, flat
      else {
        const cb = c.createRadialGradient(bx, by, 0, bx, by, 0.6 * R);
        cb.addColorStop(0, `rgba(${sc},.9)`); cb.addColorStop(1, `rgba(${sc},0)`); c.fillStyle = cb; c.fillRect(-2 * R, -2 * R, 4 * R, 4 * R);
      }
      wStroke(c, W, p.stripe!, (full ? 0.1 : 0.13) * R, [0, -0.95, 0, -0.62, 0, -0.36]);
      if (full) {
        for (const i of [-2, -1, 1, 2]) wStroke(c, W, p.stripe!, 0.042 * R, [i * 0.05, -0.3 + Math.abs(i) * 0.07, i * 0.09, -0.62, i * 0.17, -0.98]);
        for (const sd of [-1, 1]) {
          wStroke(c, W, p.stripe!, 0.04 * R, [sd * 0.62, 0.04, sd * 0.82, -0.02, sd * 1.02, -0.08]);
          wStroke(c, W, p.stripe!, 0.045 * R, [sd * 0.7, 0.3, sd * 0.88, 0.22, sd * 1.1, 0.22]);
          wStroke(c, W, p.stripe!, 0.045 * R, [sd * 0.72, 0.46, sd * 0.9, 0.42, sd * 1.1, 0.46]);
        }
      }
      const ny = -Math.sin(p.nosePh) * p.ry;
      c.fillStyle = p.light!; for (const sd of [-1, 1]) c.fill(wEll(W, sd * 0.17, ny + 0.12, 0.26, 0.21));
      c.fillStyle = p.chinCol!; c.fill(wEll(W, 0, ny + 0.34, 0.22, 0.16));
    } else if (p.coat === "point") {
      const ny = -Math.sin(p.nosePh) * p.ry, [mx, my] = W(0, ny - 0.12), pc = hex(p.point!).join(",");
      if (flat?.point) { const k = FLAT_FILL.point; c.fillStyle = `rgba(${flat.point.map(Math.round)},${k.alpha})`; c.beginPath(); c.ellipse(mx, my, k.rx * R, k.ry * R, 0, 0, TAU); c.fill(); } // the point mask, flat: the contract's 0.86 R by 0.54 R
      else {
        c.save(); c.translate(mx, my); c.scale(1.55, 1);
        const pg = c.createRadialGradient(0, 0, 0.05 * R, 0, 0, 0.66 * R);
        pg.addColorStop(0, `rgba(${pc},.97)`); pg.addColorStop(0.6, `rgba(${pc},.82)`); pg.addColorStop(1, `rgba(${pc},0)`); c.fillStyle = pg; c.fillRect(-2 * R, -2 * R, 4 * R, 4 * R); c.restore();
      }
    } else if (p.coat === "calico") {
      for (const q of p.patches || []) { c.fillStyle = q[5]; c.fill(wBlob(W, q[0], q[1], q[2], q[3], q[4], q[6] || 1)); }
    }
    if (p.muzzle) {
      const ny = -Math.sin(p.nosePh) * p.ry;
      c.fillStyle = p.muzzle; for (const sd of [-1, 1]) c.fill(wEll(W, sd * 0.16, ny + 0.12, 0.24, 0.19));
      c.fill(wEll(W, 0, ny + 0.32, 0.2, 0.14));
    }
    if (p.wrinkles && full) for (const [y, w] of [[-0.42, 0.2], [-0.54, 0.27], [-0.66, 0.18]]) wStroke(c, W, p.bot, 0.026 * R, [-w, y + 0.03, 0, y - 0.05, w, y + 0.03]);
    if (fur) {
      c.lineCap = "round"; c.lineWidth = Math.max(0.5, (p.furOpts || FURDEF).w * R);
      for (const q of fur.head) { const [a, b] = W(q.x, q.y), [c2, d] = W(q.x2, q.y2); c.strokeStyle = q.c; c.beginPath(); c.moveTo(a, b); c.lineTo(c2, d); c.stroke(); }
    }
    c.globalAlpha = 1;
    if (o.tint !== false && s.tint > 0.01) {
      const col = e.col.map(Math.round), lg = c.createLinearGradient(0, ry, 0, -ry * 0.2);
      lg.addColorStop(0, `rgba(${col},${0.4 * s.tint})`); lg.addColorStop(1, `rgba(${col},0)`); c.fillStyle = lg; c.fillRect(-2 * R, -2 * R, 4 * R, 4 * R);
    }
    // A soft edge: a rim light on dark coats, a shadow on the rest. Below Ø28 it would be a few pixels of shading: skipped (FLAT_FILL.rimGradient).
    if (!flat || FLAT_FILL.rimGradient) {
      const rg = c.createRadialGradient(0, 0, 0.2 * R, 0, 0, 1.35 * R);
      rg.addColorStop(0, "rgba(0,0,0,0)"); rg.addColorStop(0.62, "rgba(0,0,0,0)"); rg.addColorStop(1, p.rimLight ? "rgba(255,255,255,.07)" : "rgba(0,0,0,.25)");
      c.fillStyle = rg; c.fillRect(-2 * R, -2 * R, 4 * R, 4 * R);
    }
    const bl = Math.max(s.blush, e.blushBase || 0);
    if (bl > 0.01) { c.fillStyle = `rgba(255,120,150,${0.5 * bl * fa})`; for (const sd of [-1, 1]) c.fill(wEll(W, sd * p.blushAt[0], p.blushAt[1], 0.17, 0.1, 14)); }
    // Eyes on the sphere (upstream projection), normalised so the rest pose matches the board.
    const shape = e.eyeShape(), open = s.open * (1 - s.lid);
    for (const { sd, visible, x: ex, y: ey, fx, fy } of L.eyes) {
      if (!visible) continue;
      c.save(); c.translate(ex, ey); c.scale(fx, fy); c.globalAlpha = fa;
      if (full) {
        if (p.light) { c.save(); c.scale(1.22, 1.3); c.fillStyle = p.light; almondPath(c, p, sd, R, 1); c.fill(); c.restore(); }
        if (REAL.has(shape) || (shape === "wink" && sd < 0)) almondEye(c, s, p, sd, R * s.es * (shape === "wide" ? 1.12 : 1), shape === "dot" ? 1 : s.pupil, shape === "tired" ? Math.min(open, 0.42) : open);
        else inkEye(c, shape, sd, 0.27 * R * s.es, 0.31 * R * s.es, open, T, p.ink);
      } else {
        // Below Ø28: a small coloured eye for the plain resting shapes (and a wink's left eye), the flat ink shape for every expression.
        const eye = o.eyes === "ink" ? null : smallEye(shape, { sd, R, es: s.es, open, yaw: s.yaw, pitch: s.pitch, kitten: p.kitten === true, cat: p.name });
        if (eye) smallEyeDraw(c, p, sd, eye);
        else inkEye(c, shape, sd, 0.34 * R * s.es, 0.4 * R * s.es, open, T, p.ink);
      }
      c.restore();
    }
    // Nose and mouth (open for yawns and the file catch).
    if (L.nose.visible) {
      const { nx, ny, nf, nw, nh, my } = L.nose as Required<typeof L.nose>, mo = e.mouthOpen();
      c.globalAlpha = fa;
      drawMouth(c, p, s, R, nx, my, nf, full, mo, T);
      c.fillStyle = p.nose; c.beginPath(); c.moveTo(nx - nw / 2, ny - nh / 2); c.quadraticCurveTo(nx, ny - nh * 0.8, nx + nw / 2, ny - nh / 2);
      c.quadraticCurveTo(nx + nw * 0.1, ny + nh * 0.6, nx, ny + nh / 2); c.quadraticCurveTo(nx - nw * 0.1, ny + nh * 0.6, nx - nw / 2, ny - nh / 2); c.fill();
      if (full) { c.strokeStyle = p.noseLine; c.lineWidth = 0.02 * R; c.stroke(); }
      e.mouthAt = L.mouth;
    }
    c.globalAlpha = 1; c.restore();
    if (p.rimLight) { c.strokeStyle = "rgba(255,255,255,.22)"; c.lineWidth = Math.max(1, 0.013 * R); c.stroke(head); }
  });
}

/** A "#RRGGBB" colour lightened toward white by k (0 to 1), as "rgb()". */
const tintW = (h: string, k: number): string => `rgb(${hex(h).map((v) => Math.round(v + (255 - v) * k))})`;
const HEX6 = /^#[0-9A-Fa-f]{6}$/;

/**
 * Paints a collar in the head's own frame. The maths is `collarGeometry`; this only paints it: the agent's colour with a thin dark edge so a light
 * collar stays apart from a light coat, a lighter tag, and at full detail a crease on the neckerchief and a shine on the tag. The page's `drawCollar`
 * is the reference for the look (it is not tested).
 */
function drawCollar(c: Ctx, G: CollarGeometry, col: string, full: boolean, dpr: number) {
  const e1 = 1 / dpr, edge = "rgba(0,0,0,.42)";
  const poly = (pts: readonly (readonly [number, number])[]) => { c.beginPath(); pts.forEach(([x, y], i) => (i ? c.lineTo(x, y) : c.moveTo(x, y))); };
  c.save(); c.lineCap = "round"; c.lineJoin = "round";
  if (G.kerchief) {
    const S = G.kerchief;
    poly([...S.pts, S.apex]); c.closePath(); c.fillStyle = col; c.fill(); c.strokeStyle = edge; c.lineWidth = 1.5 * e1; c.stroke();
    if (full) {
      const m = S.pts[S.pts.length >> 1];
      c.strokeStyle = tintW(col, 0.45); c.lineWidth = Math.max(e1, G.R * 0.025);
      poly([[m[0], m[1] + G.R * 0.05], [S.apex[0], S.apex[1] - G.R * 0.08]]); c.stroke();
    }
  } else if (G.band) {
    const w = G.width ?? 0;
    poly(G.band); c.strokeStyle = edge; c.lineWidth = w + 2 * e1; c.stroke(); c.strokeStyle = col; c.lineWidth = w; c.stroke();
    if (G.tag) {
      const T = G.tag;
      c.beginPath(); c.arc(T.x, T.y, T.r, 0, TAU); c.fillStyle = tintW(col, 0.55); c.fill(); c.strokeStyle = edge; c.lineWidth = 1.5 * e1; c.stroke();
      if (full) { c.fillStyle = "rgba(255,255,255,.85)"; c.beginPath(); c.arc(T.x - T.r * 0.3, T.y - T.r * 0.3, T.r * 0.25, 0, TAU); c.fill(); }
    }
  }
  c.restore();
}

/** The front pass: a Scottish Fold's flaps, the collar, the whiskers, then the badge, the particles and the hairballs. */
export function drawFrontPass(c: Ctx, f: CatFrame) {
  const { e, p, s, L, o, T, flat } = f, { R, full, yf, fa, W } = L;
  inHead(c, f, () => {
    if (p.ear.fold) for (const ear of L.ears) drawEar(c, p, ear, R, full, flat, true);
    // The collar: over the head and the folded ears, under the whiskers (the contract's collarPass). Every size from Ø12 up; `off` and a bad colour draw nothing.
    if (o.collar && HEX6.test(o.collar.col)) {
      const dpr = dprOf(o), G = collarGeometry(p, s, f.D, o.collar.style, { dpr, detail: o.detail });
      if (G) drawCollar(c, G, o.collar.col, full, dpr);
    }
    // The outfit (sub-project I): the neck slot over the collar, then the top slot, both under the whiskers, the badge and the particles.
    if (f.outfit) { paintOutfit(c, f.outfit, "neck", f.edge); paintOutfit(c, f.outfit, "top", f.edge); }
    // Whiskers rooted on the pad grid beside the nose, plus eyebrow whiskers.
    if (full && fa > 0.01) {
      const Wk = p.whisk2, rand = rng(29), nzy = -Math.sin(p.nosePh) * p.ry;
      for (const sd of [-1, 1]) {
        const fxs = clamp(Math.cos(yf) + sd * 0.37 * Math.sin(yf), 0.15, 1.3), pts: { row: number; col: number; x: number; y: number }[] = [];
        for (let row = 0; row < Wk.rows; row++) for (let col = 0; col < Wk.cols; col++) pts.push({ row, col, x: sd * (Wk.x0 + col * Wk.dx), y: nzy + Wk.y0 + row * Wk.dy + col * Wk.slope });
        c.fillStyle = p.padDot; c.globalAlpha = fa;
        for (const q of pts) { const [X, Y] = W(q.x, q.y); c.beginPath(); c.arc(X, Y, Wk.dot * R, 0, TAU); c.fill(); }
        c.globalAlpha = 1;
        for (const q of pts) {
          if (!Wk.wcols.includes(q.col)) continue;
          const [X, Y] = W(q.x, q.y), ang = Wk.a0 + q.row * Wk.da + q.col * 0.04 + (rand() - 0.5) * 0.06 - s.wh;
          const l = (Wk.len - q.row * Wk.dl - q.col * 0.05 + (rand() - 0.5) * 0.1) * R, dx = sd * Math.cos(ang) * fxs, dy = Math.sin(ang);
          taper(c, X, Y, X + dx * l * 0.5, Y + dy * l * 0.5 - 0.05 * R, X + dx * l, Y + dy * l + (Wk.droop * l * l) / R, Wk.w * R, p.whisk, Wk.alpha * fa);
        }
        const ex = Math.sin(sd * p.eye.th) * Math.cos(p.eye.ph) * p.rx, ey = -Math.sin(p.eye.ph) * p.ry;
        for (let k = 0; k < Wk.brow; k++) {
          const [bx, by] = W(ex + sd * (k * 0.06 - 0.03), ey - p.eye.h * 1.9 - k * 0.015), th = 1.08 - k * 0.2 - s.wh * 0.5, l = (0.38 + k * 0.08) * R;
          taper(c, bx, by, bx + sd * (Math.cos(th) * l * 0.45 * fxs + 0.07 * R), by - Math.sin(th) * l * 0.55, bx + sd * Math.cos(th) * l * fxs, by - Math.sin(th) * l, Wk.w * 0.7 * R, p.whisk, Wk.alpha * 0.85 * fa);
        }
      }
    }
  });
  if (o.badge !== false && e.badge && s.badgeS > 0.01) drawBadge(c, e.badge, e.badgeCol || COL[e.state], L.badge.x, L.badge.y, R, L.badge.k, L.badge.small, T);
  drawParticles(c, e, L.base.x, L.base.y, R);
  drawBalls(c, e, L.base.x, L.base.y, R);
}

/**
 * Draws one cat: the behind pass, the head, the front pass. D is the head width in CSS px; below Ø28 it uses the
 * compact drawing, with the ears scaled down (earScale) so they keep their headroom in the compact notch.
 * (cx, cy) is the cat's resting centre. The renderer leaves e.base, e.at and e.mouthAt for the next frame.
 * The three passes are exported so outfits (sub-project I) can be drawn between them.
 */
export function drawCat(ctx: Ctx, e: CatView, cx: number, cy: number, D: number, o: DrawOptions = {}) {
  const f = frameOf(e, cx, cy, D, o);
  drawBehindPass(ctx, f);
  drawHeadPass(ctx, f);
  drawFrontPass(ctx, f);
}
