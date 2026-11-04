// A press on the desktop cat is a click, a double-click or the start of a drag (sub-project H, spec §2). A click waits one double-click interval before it acts, so a double-click
// never also opens the island. Pure: the timer is injected and the points are the caller's (any one coordinate space), so the plain-Node checks (npm run check:cat) turn time by hand.

export type Gesture =
  | { k: "click" }
  | { k: "double" }
  | { k: "dragStart" }
  /** The pointer is (dx, dy) from where it was pressed. The caller moves what is dragged by that, and the pointer is back at the press point: the next step is the pointer's next move. */
  | { k: "drag"; dx: number; dy: number }
  | { k: "dragEnd" };

export interface GestureEnv {
  set(fn: () => void, ms: number): number;
  clear(id: number): void;
  emit(g: Gesture): void;
}

/** Pixels the pointer must move before a press is a drag. */
export const DRAG_PX = 4;
/** The double-click interval (ms) when the system's cannot be read (the page asks Rust for it, Task 8b): 0.5 s, the Mac's fallback too. */
export const DOUBLE_MS = 500;

export class Gestures {
  private down: { x: number; y: number } | null = null;
  private dragging = false;
  private pending: number | null = null;
  private readonly env: GestureEnv;
  private readonly dragPx: number;
  /** The click's wait (ms): set from the system's double-click time when the page can read it. */
  doubleMs: number;

  constructor(env: GestureEnv, dragPx = DRAG_PX, doubleMs = DOUBLE_MS) {
    this.env = env;
    this.dragPx = dragPx;
    this.doubleMs = doubleMs;
  }

  /** The pointer went down on the cat. */
  press(x: number, y: number): void {
    if (![x, y].every(Number.isFinite)) return;
    this.down = { x, y };
    this.dragging = false;
  }

  /** The pointer moved with the button down. */
  move(x: number, y: number): void {
    if (!this.down || ![x, y].every(Number.isFinite)) return;
    if (!this.dragging) {
      if (Math.hypot(x - this.down.x, y - this.down.y) < this.dragPx) return;
      this.cancelPending();
      this.dragging = true;
      this.env.emit({ k: "dragStart" });
      // The handler may have cancelled the press (the system moves the window itself): no step follows.
      if (!this.down) return;
    }
    this.env.emit({ k: "drag", dx: x - this.down.x, dy: y - this.down.y });
  }

  /** The button was released. */
  release(): void {
    if (!this.down) return;
    this.down = null;
    if (this.dragging) {
      this.dragging = false;
      this.env.emit({ k: "dragEnd" });
      return;
    }
    if (this.pending !== null) {
      this.cancelPending();
      this.env.emit({ k: "double" });
      return;
    }
    this.pending = this.env.set(() => { this.pending = null; this.env.emit({ k: "click" }); }, this.doubleMs);
  }

  /** The press was cancelled (the pointer left the window, or a menu opened): nothing is emitted, and a drag ends. */
  cancel(): void {
    const wasDragging = this.dragging;
    this.down = null;
    this.dragging = false;
    if (wasDragging) this.env.emit({ k: "dragEnd" });
  }

  private cancelPending(): void {
    if (this.pending !== null) { this.env.clear(this.pending); this.pending = null; }
  }

  get isDragging(): boolean { return this.dragging; }
}
