// The guard around a drag out of the island (sub-project G1). While a shelf item is being dragged away, and for a moment after, a drop event that comes back to the island is the item's
// own: it must not be taken as a new drop (an item dragged out and back in is not added twice, and the drop view must not open under the drag). The system reports the drop on its own
// schedule, sometimes after the drag call has returned, so the guard outlasts the call by a short grace. Pure, so the plain-Node checks load it.

/** How long after a drag ends a drop event still counts as the drag's own (ms). */
export const DRAG_OUT_GRACE_MS = 600;

export class DragOutGuard {
  private on = false;
  private endedAt = -Infinity;

  /** A drag out has started. */
  start(): void { this.on = true; }

  /** The drag call has returned (dropped, cancelled or failed). `now` in ms. */
  end(now: number): void { this.on = false; this.endedAt = now; }

  /** A drag out is under way: a second one is not started. */
  get active(): boolean { return this.on; }

  /** Whether a drag or drop event at `now` belongs to the item's own drag: during it, and for the grace after. */
  blocks(now: number): boolean { return this.on || now - this.endedAt < DRAG_OUT_GRACE_MS; }
}
