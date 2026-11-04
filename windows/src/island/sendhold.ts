// The shelf's send holds the island while the Share window is up and for 15 s after it ran (ShelfHold.afterSendLinger on the Mac). One timer: a send clears the one before it,
// so the last share decides when the island lets go (the Mac re-arms on each picker reading). The island passes in what the hold does, so the timing is tested by
// windows/scripts/cat-tests/shelf-sendhold.test.mjs.

export class SendHold {
  private timer: number | null = null;
  private readonly setHeld: (on: boolean) => void;
  private readonly linger: number;

  constructor(setHeld: (on: boolean) => void, linger: number) {
    this.setHeld = setHeld;
    this.linger = linger;
  }

  /** A send starts: the island is held, and a timer from an earlier send is dropped. */
  start(): void {
    this.cancel();
    this.setHeld(true);
  }

  /** The share ran (or failed): the hold lets go `linger` ms from now, unless another send starts first. */
  finish(): void {
    this.cancel();
    this.timer = window.setTimeout(() => {
      this.timer = null;
      this.setHeld(false);
    }, this.linger);
  }

  private cancel(): void {
    if (this.timer != null) window.clearTimeout(this.timer);
    this.timer = null;
  }
}
