// A press on the big cat in the notch is a click or the start of a drag out of it (sub-project H, spec §1). A click acts when the button is released, as it always did (the
// caller keeps what a press did before); a press that moves 4 px or more is a drag, which never clicks. Pure: the points are the caller's, in any one coordinate space.

import { DRAG_PX } from "./gestures.ts";

export class PressDrag {
  private from: { x: number; y: number } | null = null;
  private drag = false;
  private readonly dragPx: number;

  constructor(dragPx = DRAG_PX) { this.dragPx = dragPx; }

  /** The button went down on the cat. A point that is not a number is no press. */
  press(x: number, y: number): void {
    this.from = Number.isFinite(x) && Number.isFinite(y) ? { x, y } : null;
    this.drag = false;
  }

  /** The pointer moved with the button down: "start" the first time it has moved far enough, "drag" after that, null while it is a click or when no press is on. */
  move(x: number, y: number): "start" | "drag" | null {
    if (!this.from || !Number.isFinite(x) || !Number.isFinite(y)) return null;
    if (this.drag) return "drag";
    if (Math.hypot(x - this.from.x, y - this.from.y) < this.dragPx) return null;
    this.drag = true;
    return "start";
  }

  /** The button was released: "click" for a press that never moved far, "drop" at the end of a drag, null with no press on. */
  release(): "click" | "drop" | null {
    if (!this.from) return null;
    const r = this.drag ? "drop" : "click";
    this.from = null;
    this.drag = false;
    return r;
  }

  /** The press was cancelled (the pointer was lost): nothing happens. */
  cancel(): void { this.from = null; this.drag = false; }

  get active(): boolean { return this.from !== null; }
  get dragging(): boolean { return this.drag; }
}
