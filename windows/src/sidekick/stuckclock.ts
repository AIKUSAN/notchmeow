// The stuck clock (sub-project F1, spec "Stuck rules", "The clock"): ONE one-shot timer, set to the nearest deadline of the rules that wait (a request that has waited a minute, an
// agent that has been quiet for five), and not set at all while nothing is live. It is the same idea as the cats' ten-minute nap (island/sleep.ts): no interval, no polling, nothing
// that wakes while the hidden island costs nothing. Every change in the ledger and in the user's presence sets it again. Pure: the timer is given. Loaded by the plain-Node checks.

export interface ClockEnv {
  set(fn: () => void, ms: number): number;
  clear(id: number): void;
  now(): number;
}

/** The longest delay a browser timer takes (about 24.8 days): a deadline further away is set for this long and looked at again when it fires. */
export const MAX_DELAY_MS = 2_147_483_647;

export class StuckClock {
  private readonly env: ClockEnv;
  private readonly fire: () => void;
  private id: number | null = null;
  private at: number | null = null;

  constructor(env: ClockEnv, fire: () => void) {
    this.env = env;
    this.fire = fire;
  }

  /** The clock is set. */
  get armed(): boolean {
    return this.id !== null;
  }

  /** The time (ms, the app's clock) it will fire at, or null while it is not set. */
  get due(): number | null {
    return this.id === null ? null : this.at;
  }

  /** Sets the clock to `at`, or stops it for null (or a time that is not a time). Setting it to the time it already has changes nothing. */
  arm(at: number | null): void {
    if (at === null || !Number.isFinite(at)) {
      this.stop();
      return;
    }
    if (this.id !== null && this.at === at) return;
    this.stop();
    this.at = at;
    const wait = Math.min(MAX_DELAY_MS, Math.max(0, at - this.env.now()));
    this.id = this.env.set(() => {
      this.id = null;
      this.at = null;
      this.fire();
    }, wait);
  }

  stop(): void {
    if (this.id !== null) this.env.clear(this.id);
    this.id = null;
    this.at = null;
  }
}
