// The compact island's two wings step aside for the pointer (Windows, and Linux under X11). The rules, as plain numbers and times: the wings' rectangles, when the island can
// step aside, the swoosh's numbers and the fold's timing. Port of NotchBuddy/Sources/App/IslandWing.swift, case for case (windows/scripts/cat-tests/wing.test.mjs). On a PC the
// compact island is 288 px wide with the 184 px "notch" in the middle, so each wing is 52 px; while the pointer is over EITHER wing the whole island swooshes into the
// notch-wide middle, its cats, grid and badge fade as it shrinks, and the window passes the mouse on to whatever is under the wings. `RETURN_DELAY` seconds after the pointer has left
// both wings it swooshes back out. The right wing (the grid) folds the island at once; the left wing (the big cat) only after the pointer has rested there `LEFT_DWELL` seconds
// with no mouse button pressed. An alert cancels it at once. Unlike the Mac there is no poll tick to feed it every 16 ms (the cursor event comes only when the pointer moves), so
// `WingYield.nextDeadline` tells the page when to wake it again: one one-shot timer, armed only while a dwell or a return is running.

/** How long the cats, the grid and the badge take to fade out as the island shrinks (s), and to fade back in (s). */
export const FADE_OUT = 0.15;
export const FADE_IN = 0.25;
/** How long the pointer must have been away from both wings before the island swooshes back out (s). */
export const RETURN_DELAY = 1.0;
/** How long the pointer must rest on the LEFT wing, with no mouse button pressed, before the island folds (s). The right wing folds it at once. */
export const LEFT_DWELL = 0.4;
/** The swoosh is a spring: about 0.22 s to settle, with a slight overshoot (a damping fraction a little under 1). */
export const SPRING_RESPONSE = 0.22;
export const SPRING_DAMPING = 0.68;
/** The slack the dwell's comparison allows, so that 0.4 s on a clock of binary fractions is 0.4 s. */
const EPSILON = 1e-9;

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export type Zone = "left" | "right";

export interface Wings {
  left: Rect;
  right: Rect;
}

/** Half-open, like CGRect.contains on the Mac: the first point is in, the last edge is not, and an empty rectangle holds nothing. */
function inRect(r: Rect, px: number, py: number): boolean {
  return px >= r.x && px < r.x + r.w && py >= r.y && py < r.y + r.h;
}

/**
 * The two wings in the window's coordinates (y down), each the strip's whole height: the left from the island's left edge to the notch's left edge, the right from the notch's right
 * edge to the island's right edge. `island` is the compact island's FULL frame and `notchWidth` the notch's. `slop` is how far the island's hover area reaches beyond the strip: each
 * wing takes it on its outer side, top and bottom, and not on the side towards the notch.
 */
export function wings(island: Rect, notchWidth: number, slop = 0): Wings {
  const midX = island.x + island.w / 2;
  const notchLeft = midX - notchWidth / 2;
  const notchRight = midX + notchWidth / 2;
  const leftWidth = Math.max(0, notchLeft - (island.x - slop));
  const rightWidth = Math.max(0, island.x + island.w + slop - notchRight);
  return {
    left: { x: island.x - slop, y: island.y - slop, w: leftWidth, h: island.h + 2 * slop },
    right: { x: notchRight, y: island.y - slop, w: rightWidth, h: island.h + 2 * slop },
  };
}

/** Which wing the point is in, if any. */
export function zoneOf(w: Wings, px: number, py: number): Zone | null {
  return inRect(w.left, px, py) ? "left" : inRect(w.right, px, py) ? "right" : null;
}

/** The width the island shrinks to: the notch's own. */
export function foldedWidth(notchWidth: number): number {
  return notchWidth;
}

/** The island's drawn width at `swoosh` (0 at rest, 1 folded into the notch): linear; the page lets a spring move `swoosh`. */
export function widthAt(full: number, notchWidth: number, swoosh: number): number {
  return full - (full - foldedWidth(notchWidth)) * swoosh;
}

/**
 * The rectangle the window uses for click-through while the island is folded (window coordinates, `viewportW` wide): the notch-wide middle, shrunk by the hit margin on each side
 * because the window adds the margin back. The wings pass the mouse on from the first tick, and no dead band is left beside the middle.
 */
export function foldedHitRect(viewportW: number, h: number, notchWidth: number, margin: number): Rect {
  const w = Math.max(0, foldedWidth(notchWidth) - 2 * margin);
  return { x: (viewportW - w) / 2, y: 0, w, h };
}

/** The cats', grid's and badge's opacity, moved one frame (`dt` seconds): down to 0 in `FADE_OUT` seconds while the island is folded, back up to 1 in `FADE_IN` seconds. */
export function stepFade(level: number, folded: boolean, dt: number): number {
  return folded ? Math.max(0, level - dt / FADE_OUT) : Math.min(1, level + dt / FADE_IN);
}

/**
 * Whether the island can step aside now: only in the compact island, not while the greeting's tail still draws the session cats in the grid's place, not while a drag of the cat's head
 * is under way, and not while an alert wants the island (a permission request or question waits, a file is on its way in, the desktop cat is away from the notch, the shelf holds the island).
 */
export function isActive(compact: boolean, greetingTail: boolean, dragging: boolean, alert: boolean): boolean {
  return compact && !greetingTail && !dragging && !alert;
}

export interface WingOut {
  /** The island is folded into the notch (or folding). */
  faded: boolean;
  /** The pointer is over a wing of the folded island: the window must not take the mouse, and the island must not count the pointer as over it. */
  passThrough: boolean;
}

/** The island's memory between two ticks. */
export class WingYield {
  private faded = false;
  /** When the pointer was first seen away from both wings (while folded); null while it is over one. */
  private leftAt: number | null = null;
  /** When the pointer began to rest on the left wing with no button pressed (before the island has folded); null otherwise. */
  private restSince: number | null = null;

  private reset(): void {
    this.faded = false;
    this.leftAt = null;
    this.restSince = null;
  }

  /**
   * One tick, `now` in seconds. `zone`: the wing the pointer is in, if any. `active`: `isActive`. `buttonDown` says whether any mouse button is held (a file being dragged in, a click
   * that began on the big cat, a right-click): then no fold begins, a dwell on the left wing starts over, and a fold that has begun is not undone by it. It is asked only while the pointer
   * is in a wing and the island has not folded yet.
   */
  step(now: number, zone: Zone | null, active: boolean, buttonDown: () => boolean): WingOut {
    if (!active || !Number.isFinite(now)) {
      this.reset();
      return { faded: false, passThrough: false };
    }
    if (zone) {
      this.leftAt = null;
      if (this.faded) return { faded: true, passThrough: true };
      if (zone === "right") {
        this.restSince = null;
        if (!buttonDown()) this.faded = true;
      } else if (buttonDown()) {
        this.restSince = null;
      } else {
        const since = this.restSince ?? now;
        this.restSince = since;
        if (now - since + EPSILON >= LEFT_DWELL) this.faded = true;
      }
      return { faded: this.faded, passThrough: this.faded };
    }
    this.restSince = null;
    if (this.faded) {
      const since = this.leftAt ?? now;
      this.leftAt = since;
      if (now - since >= RETURN_DELAY) this.reset();
    }
    return { faded: this.faded, passThrough: false };
  }

  /**
   * Seconds from `now` until the next instant at which `step` would answer differently with no new input: the left dwell ending, or the return delay ending. null when nothing is
   * pending (the page arms no timer then).
   */
  nextDeadline(now: number): number | null {
    if (!Number.isFinite(now)) return null;
    if (!this.faded && this.restSince !== null) return Math.max(0, this.restSince + LEFT_DWELL - now);
    if (this.faded && this.leftAt !== null) return Math.max(0, this.leftAt + RETURN_DELAY - now);
    return null;
  }
}
