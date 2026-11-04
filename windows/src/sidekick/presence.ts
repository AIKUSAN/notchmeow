// Whether the user is away, from the signals the system gives (sub-project F1, spec "Away and recap"). The rule is the contract's `presenceStep`; this holds its state and adds the
// one thing a lazy sampler needs. On Windows and Linux the idle time is read only when something asks (a hook event, the island opening, an unlock), not many times a second, so a
// sample under 3 s, which the rule calls "back", would almost never be seen. The system also says when the last input was, so a sample that shows input since the last sample tells
// the rule the user came back at that moment, and the recap then counts from the real time away. Pure: the clock is a parameter. Loaded by the plain-Node checks.

import { presenceInit, presenceStep } from "./core.ts";
import type { PresenceState } from "./core.ts";

/** The words of the platform's watchers (src-tauri/src/sidekick_presence.rs `away_signal`): the contract's signals other than `idle`. */
export const AWAY_WORDS = ["lock", "unlock", "sleep", "wake", "displayOff", "displayOn"] as const;
export type AwayWord = (typeof AWAY_WORDS)[number];
export const isAwayWord = (x: unknown): x is AwayWord => typeof x === "string" && (AWAY_WORDS as readonly string[]).includes(x);

/** The user came back: when the away began and how long it lasted (ms). */
export interface Return { awaySince: number; awayMs: number }

/** A moment less than this after the last sample, in seconds, is not input: timers and clocks jitter. */
const JITTER_S = 1;

export class Presence {
  private state: PresenceState = presenceInit();
  private last: { at: number; seconds: number } | null = null;

  /** The user is away while any reason holds (a lock, a sleep, the display off, or 300 s of no input). */
  get away(): boolean {
    return this.state.reasons.length > 0;
  }

  get awaySince(): number | null {
    return this.state.awaySince;
  }

  /** A word from the platform's watchers. A word that is not one of the six changes nothing. Returns the return, once, when the last reason lets go. */
  signal(word: unknown, now: number): Return | null {
    if (!isAwayWord(word)) return null;
    return this.step({ type: word }, now);
  }

  /**
   * An idle sample: `seconds` since the user's last input, read at `now`. A value that is not a number from 0 up is ignored. When the previous sample showed the user idle and this one
   * shows input since, the user came back when that input happened (`now` minus `seconds`), not now: the rule is told so first, and then told the sample itself.
   */
  sample(seconds: unknown, now: number): Return | null {
    if (typeof seconds !== "number" || !Number.isFinite(seconds) || seconds < 0 || !Number.isFinite(now)) return null;
    const prev = this.last;
    this.last = { at: now, seconds };
    let back: Return | null = null;
    if (prev !== null && this.state.reasons.includes("idle") && seconds < prev.seconds + (now - prev.at) / 1000 - JITTER_S) {
      back = this.step({ type: "idle", seconds: 0 }, now - seconds * 1000);
    }
    return this.step({ type: "idle", seconds }, now) ?? back;
  }

  private step(signal: Parameters<typeof presenceStep>[1], now: number): Return | null {
    const r = presenceStep(this.state, signal, now);
    this.state = r.state;
    return r.back ? { awaySince: r.back.awaySince, awayMs: r.back.awayMs } : null;
  }
}
