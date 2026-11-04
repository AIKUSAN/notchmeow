// Feeds the wing's rules (island/wing.ts) from what the island page has: the pointer's wing, whether the island can step aside, the mouse button. The Mac asks every 16 ms; here the
// cursor event comes only when the pointer moves, so after every answer the driver arms ONE one-shot timer for the next instant the rules would answer differently (the left wing's
// dwell ending, the return delay ending), and nothing at all when nothing is pending. The clock and the timer are injected so the plain-Node checks can turn time by hand.

import { WingYield, type WingOut, type Zone } from "./wing.ts";

export interface WingEnv {
  /** Seconds, monotonic. */
  now(): number;
  set(fn: () => void, ms: number): number;
  clear(id: number): void;
}

export class WingDriver {
  private readonly rules = new WingYield();
  private out: WingOut = { faded: false, passThrough: false };
  private zone: Zone | null = null;
  private active = false;
  private timer: number | null = null;
  private readonly env: WingEnv;
  private readonly buttonDown: () => boolean;
  private readonly changed: (now: WingOut, before: WingOut) => void;

  constructor(env: WingEnv, buttonDown: () => boolean, changed: (now: WingOut, before: WingOut) => void) {
    this.env = env;
    this.buttonDown = buttonDown;
    this.changed = changed;
  }

  /** The last answer. */
  get state(): WingOut {
    return this.out;
  }

  /** Whether a wake-up is armed (a test and the 0 % pin look at it). */
  get pending(): boolean {
    return this.timer !== null;
  }

  /** The pointer is in `zone` (null: in no wing) and the island may (`active`) or may not step aside now. */
  feed(zone: Zone | null, active: boolean): WingOut {
    this.zone = zone;
    this.active = active;
    return this.run();
  }

  /** Ask again with the last inputs: a mouse button went down or came up. */
  poke(): WingOut {
    return this.run();
  }

  private run(): WingOut {
    const before = this.out;
    this.out = this.rules.step(this.env.now(), this.zone, this.active, this.buttonDown);
    this.rearm();
    if (this.out.faded !== before.faded || this.out.passThrough !== before.passThrough) this.changed(this.out, before);
    return this.out;
  }

  private rearm(): void {
    if (this.timer !== null) {
      this.env.clear(this.timer);
      this.timer = null;
    }
    const seconds = this.rules.nextDeadline(this.env.now());
    if (seconds === null) return;
    this.timer = this.env.set(() => {
      this.timer = null;
      this.run();
    }, Math.ceil(seconds * 1000) + 1);
  }
}
