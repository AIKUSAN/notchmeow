// The cat's ten-minute nap (spec §3): one timer, started by every event, never a poll. The rule is the contract's (`sleepDelay`, `wakes` in cat/base.ts,
// tests/fixtures/cat/sequence-cases.json). Pure: the clock, the timer and the cat are injected, so the plain-Node checks can turn time by hand.

import { sleepDelay, wakes } from "../cat/base.ts";

export interface SleepEnv {
  /** Milliseconds. */
  now(): number;
  /** The state the cat shows when awake: only `idle` can fall asleep. */
  state(): string;
  /** An approval or a question is waiting for the user: the cat never sleeps through one. */
  blocked(): boolean;
  set(fn: () => void, ms: number): number;
  clear(id: number): void;
  /** The cat falls asleep. */
  fall(): void;
  /** The cat is woken (called on every waking event; it must do nothing when the cat is awake). */
  wake(): void;
  /**
   * The cat has just fallen asleep, after ten quiet minutes: the subagent kittens whose stop never came go. Only here, never when the timer fires under a working cat:
   * a subagent busy in a long, silent step is alive, and its kitten stays. Optional.
   */
  sweep?(): void;
}

export class SleepClock {
  private timer: number | null = null;
  private last: number;
  private readonly env: SleepEnv;

  /** Starts the first ten minutes: an app that starts and sees no event falls asleep too. */
  constructor(env: SleepEnv) {
    this.env = env;
    this.last = env.now();
    this.arm(sleepDelay("idle", 0) ?? 0);
  }

  /**
   * An agent event (`hook`), a hover or a click: the cat wakes and its ten minutes start again. Any other kind (a key, a scroll, a drag) is ignored.
   * The timer is armed whatever the cat is doing: a pill that finished goes back to idle on its own, and the ten minutes are counted from the event.
   */
  event(kind: unknown): void {
    if (!wakes(kind)) return;
    this.last = this.env.now();
    this.env.wake();
    this.arm(sleepDelay("idle", 0) ?? 0);
  }

  private arm(ms: number): void {
    if (this.timer !== null) this.env.clear(this.timer);
    this.timer = this.env.set(() => this.expire(), ms);
  }

  /** The timer fired: sleep if the cat is idle, ten minutes have passed and nothing waits for an answer; wait the rest if it fired early. */
  private expire(): void {
    this.timer = null;
    const left = sleepDelay(this.env.state(), this.env.now() - this.last);
    if (left === 0 && !this.env.blocked()) {
      this.env.fall();
      this.env.sweep?.();
    } else if (left !== null && left > 0) this.arm(left);
  }
}
