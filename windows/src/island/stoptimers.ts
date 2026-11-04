// The return to idle that a Stop event arms, one per pill. The next turn (a prompt, a tool, a failure, a question) cancels it: otherwise the timer fires in the
// middle of that turn and the pill flips to idle while the agent is still working. Pure: the timer is injected, so the plain-Node checks can turn time by hand.

export interface StopTimerEnv {
  set(fn: () => void, ms: number): number;
  clear(id: number): void;
}

const realEnv: StopTimerEnv = {
  set: (fn, ms) => globalThis.setTimeout(fn, ms) as unknown as number,
  clear: (id) => globalThis.clearTimeout(id as unknown as ReturnType<typeof setTimeout>),
};

export class StopTimers {
  private readonly timers = new Map<string, number>();
  private readonly env: StopTimerEnv;

  constructor(env: StopTimerEnv = realEnv) {
    this.env = env;
  }

  /** Arms the return for `id` in `ms`; an earlier one for the same pill is cancelled first. `fn` runs once, and the entry is gone by then. */
  arm(id: string, ms: number, fn: () => void): void {
    this.cancel(id);
    this.timers.set(
      id,
      this.env.set(() => {
        this.timers.delete(id);
        fn();
      }, ms),
    );
  }

  /** Cancels the return armed for `id`. True when there was one. */
  cancel(id: string): boolean {
    const timer = this.timers.get(id);
    if (timer == null) return false;
    this.env.clear(timer);
    this.timers.delete(id);
    return true;
  }

  /** Whether a return is armed for `id`. */
  has(id: string): boolean {
    return this.timers.has(id);
  }
}
