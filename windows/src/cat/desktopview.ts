// Where the desktop cat's window is and what in it takes the mouse (sub-project H, spec §2): the window is sized for the cat, its badge and its kittens, and no larger,
// and only the head, the badge and the kitten slots take the mouse; everything else passes through. Pure: sizes in px (CSS), no DOM, so the plain-Node checks (npm run check:cat) can
// load it. `DesktopWorld` is what Rust knows about the screens (src-tauri/src/desktop.rs `desktop_screens`), in the points the contract's rules use. The cat is drawn by `BotEngine.draw(ctx, W, H)` into a canvas W wide (the head is 0.6 W across) and `overhang` taller than wide, with the head's centre at
// (W/2, W/2 + overhang): the layout puts that canvas in the window so the head's centre is at (headX, headY).

import { DESKTOP_SIZES, desktopKittenSlots, desktopSizeOf } from "./desktop.ts";
import type { Rect, Screen } from "./desktop.ts";
import { BADGE_RIGHT } from "./kittendraw.ts";
import { catById } from "./presets.ts";

/** What Rust knows about the screens (src-tauri/src/desktop.rs `desktop_screens`), in points: the connected screens, the one the island is on, and the scales. */
export interface DesktopWorld {
  screens: Screen[];
  /** The frame of the screen the island lives on. */
  island: Rect;
  /** The island's screen scale divided by the primary screen's: one CSS px of the island is this many points. */
  islandK: number;
  /** The primary screen's scale factor, the one unit of the points: a CSS px of a window whose page has `devicePixelRatio` is `devicePixelRatio / scale` points. */
  scale: number;
  /** Whether the app can put the desktop window where it wants (false on GNOME, a Wayland session without layer-shell). */
  positioned: boolean;
}

/** An empty world: one 1920 x 1080 screen, for a page that runs outside Tauri (the dev server). */
export const defaultWorld = (): DesktopWorld => {
  const f = { x: 0, y: 0, w: 1920, h: 1080 };
  return { screens: [{ frame: f, visible: { x: 0, y: 0, w: 1920, h: 1040 }, main: true }], island: f, islandK: 1, scale: 1, positioned: true };
};

/** A circle that takes the mouse, in window px. */
export interface HitCircle { x: number; y: number; r: number }

export interface DesktopWindowLayout {
  /** The window, in px. */
  w: number; h: number;
  /** The head's centre in the window. */
  headX: number; headY: number;
  /** The head width D, and the canvas the engine draws into: W = D / 0.6 wide, W + overhang tall, with its top-left at (canvasX, 0). */
  D: number; canvasW: number; canvasH: number; canvasX: number; overhang: number;
  /** Which side the kittens are on: 1 right, -1 left. */
  side: 1 | -1;
  /** What takes the mouse: the head (with the ears), the badge, and one circle per kitten and for the "+N". */
  shapes: HitCircle[];
}

/** Room above the head for ears and the particles that fly out (hearts, z's), as a fraction of D: 40/58, the Mac's number (44 px at Medium). */
export const OVERHANG_K = 40 / 58;
/** The head's hit circle is this fraction of D across the radius, so the ears count as the cat. */
export const HEAD_HIT_K = 0.55;

/** The window for a cat of this size and coat with `kittenCount` kittens on `side`. A size ID that is unknown is Medium, a coat that is unknown is Shrimpy, a count is held to 0..8. */
export function desktopWindowLayout(size: unknown, coat: unknown, kittenCount: unknown, side: unknown): DesktopWindowLayout {
  const D = DESKTOP_SIZES[desktopSizeOf(size)], W = D / 0.6, overhang = Math.round(D * OVERHANG_K), s: 1 | -1 = side === -1 ? -1 : 1;
  const n = typeof kittenCount === "number" && Number.isFinite(kittenCount) ? Math.max(0, Math.min(8, Math.floor(kittenCount))) : 0;
  const slots = desktopKittenSlots(Array.from({ length: n }, (_, i) => ({ id: `k${i}` })), s);
  const half = W / 2;
  // How far the kittens reach on their side, in D from the head's centre: the last kitten's state badge (it sticks out beside its head), or the end of the "+N" label (about 2.2 label heights wide).
  let reach = 0;
  for (const q of slots.shown) reach = Math.max(reach, Math.abs(q.x) + q.d * BADGE_RIGHT);
  if (slots.moreAt) reach = Math.max(reach, Math.abs(slots.moreAt.x) + slots.moreAt.size * 2.2);
  const rx = catById(typeof coat === "string" ? coat : "shrimpy").rx, R = D / (2 * rx);
  // The badge is at the upper right of the head, 1.4 R across and about 0.36 R wide: the window holds it on that side whatever the coat's head shape.
  const kit = Math.ceil(reach * D), badge = Math.ceil(1.4 * R + 0.36 * R);
  const left = Math.max(half, s === -1 ? kit : 0), right = Math.max(half, badge, s === 1 ? kit : 0);
  const headX = Math.ceil(left), w = headX + Math.ceil(right), headY = Math.round(half + overhang), canvasH = Math.round(W) + overhang;
  const shapes: HitCircle[] = [
    { x: headX, y: headY, r: D * HEAD_HIT_K },
    { x: headX + 1.4 * R, y: headY - 0.92 * R, r: 0.36 * R },
    ...slots.shown.map((q) => ({ x: headX + q.x * D, y: headY + q.y * D, r: (q.d * D) / 2 })),
    ...(slots.moreAt ? [{ x: headX + slots.moreAt.x * D + s * slots.moreAt.size * D * 1.1, y: headY + slots.moreAt.y * D, r: slots.moreAt.size * D * 1.1 }] : []),
  ];
  return { w, h: canvasH, headX, headY, D, canvasW: W, canvasH, canvasX: headX - half, overhang, side: s, shapes };
}

/** True when (x, y), in window px, is on the cat: inside any shape, `slack` px wider. */
export const hitsCat = (shapes: readonly HitCircle[], x: number, y: number, slack = 0): boolean =>
  shapes.some((c) => Math.hypot(x - c.x, y - c.y) <= c.r + slack);

/** The side the kittens are on for a cat at `x` on a screen whose visible frame is `[left, left + width)`: the left half keeps them on the right, the right half on the left. */
export const kittenSide = (x: number, left: number, width: number): 1 | -1 => (x >= left + width / 2 ? -1 : 1);
