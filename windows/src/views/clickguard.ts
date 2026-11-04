// A fresh permission card ignores clicks for its first 600 ms: it opens under a pointer that was busy with the window underneath, and a click meant for that window
// must not land on Allow or Deny. The keyboard (Y and N) is not a click and is not guarded. Pure: the clock is passed in.

export const CLICK_GUARD_MS = 600;

export class ClickGuard {
  private shownFor: string | null = null;
  private shownAt = 0;

  /** Tells the guard which request the card shows now. A request it has not seen starts the 600 ms; the same request again changes nothing. */
  shown(requestId: string | null, now: number): void {
    if (requestId === this.shownFor) return;
    this.shownFor = requestId;
    this.shownAt = now;
  }

  /** True while a click on the card's buttons must be ignored. */
  blocks(now: number): boolean {
    return now - this.shownAt < CLICK_GUARD_MS;
  }
}
