// A click outside the open island folds it (Windows, and Linux under X11). The rules, as plain values: when a click counts, and when the island stays. Port of
// NotchBuddy/Sources/App/IslandOutsideClick.swift, case for case (windows/scripts/cat-tests/outside-click.test.mjs). No DOM, no Tauri: the island page owns the facts
// (`OutsideContext`) and the OS gives it the button edges (Rust `pointer-button`, island.rs). Nothing here listens to anything on its own.

/** A press that moves farther than this (logical px) before it is released is a drag (a file taken out of Explorer, a window moved, a selection), not a click. */
export const CLICK_SLOP = 4;

/** What the page knows when a click is pressed. */
export interface OutsideContext {
  /** The island is expanded. */
  expanded: boolean;
  /** The island is pinned open (an approval pins it, and so does a chat card). */
  pinned: boolean;
  /** Something holds the island open: a permission request or question waiting, the shelf's drag-out or share hold, a native menu of the island. */
  held: boolean;
  /** The user is typing in the chat: the chat view is showing and a text field has the keyboard. */
  typing: boolean;
  /** The press is over the island (with its hit margin) or over another window of this app (Settings, the desktop cat, the tray menu): not outside. */
  pointerInIsland: boolean;
  /** The cat's head is being dragged out of the notch, a file is being dragged in, or a shelf tile is dragged out. */
  busy: boolean;
}

/** Whether a click outside folds the island now. */
export function shouldFold(c: OutsideContext): boolean {
  return c.expanded && !c.pinned && !c.held && !c.typing && !c.pointerInIsland && !c.busy;
}

/** Tells a click from a drag: remembers where the button went down, and says on release whether the pair was a click (it did not move more than `CLICK_SLOP`). */
export class ClickTracker {
  private downAt: { x: number; y: number } | null = null;

  down(x: number, y: number): void {
    this.downAt = { x, y };
  }

  /** The release. True when it ends a click; the press is forgotten either way. A release with no press seen is not a click. */
  up(x: number, y: number): boolean {
    const d = this.downAt;
    this.downAt = null;
    if (!d) return false;
    return Math.hypot(x - d.x, y - d.y) <= CLICK_SLOP;
  }

  /** Forget a press (the watch was switched off). */
  reset(): void {
    this.downAt = null;
  }
}

/** A mouse button edge from the OS, in the island window's logical px. `own`: the point is over a window of this app. */
export interface ButtonEvent {
  down: boolean;
  x: number;
  y: number;
  own: boolean;
}

/**
 * The glue: feed it the button edges while the island is expanded. What the page knew at the press decides (a press can take the keyboard away from the chat before it is
 * released); the release folds when the pair was a click and not a drag.
 */
export class OutsideClick {
  private readonly tracker = new ClickTracker();
  private atDown: OutsideContext | null = null;
  private readonly context: (e: ButtonEvent) => OutsideContext;
  private readonly fold: () => void;

  constructor(context: (e: ButtonEvent) => OutsideContext, fold: () => void) {
    this.context = context;
    this.fold = fold;
  }

  onButton(e: ButtonEvent): void {
    if (e.down) {
      this.tracker.down(e.x, e.y);
      this.atDown = this.context(e);
      return;
    }
    const ctx = this.atDown;
    this.atDown = null;
    if (!this.tracker.up(e.x, e.y) || !ctx) return;
    if (shouldFold(ctx)) this.fold();
  }

  /** The watch was switched off (the island is no longer expanded): forget a press in flight. */
  reset(): void {
    this.tracker.reset();
    this.atDown = null;
  }
}
