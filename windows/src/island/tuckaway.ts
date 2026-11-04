// Tuck the island away (Settings → General → Behavior): when the compact island hides by itself. Port of NotchBuddy/Sources/App/IslandTuckAway.swift, pure: the state machine (fsm.ts)
// keeps the one timer. Tested by windows/scripts/cat-tests/fsm-tuck.test.mjs (the Mac's cases) and tuck-wiring.test.mjs. Seconds, as the Mac's.

/** "never" (the default: the compact island never hides by itself) or the minutes of quiet before it may hide. */
export type TuckChoice = "never" | "1" | "5" | "15" | "30";

export const TUCK_CHOICES: readonly TuckChoice[] = ["never", "1", "5", "15", "30"];

/** A missing or unknown stored value is never. */
export function cleanTuckChoice(stored: unknown): TuckChoice {
  return (TUCK_CHOICES as readonly unknown[]).includes(stored) ? (stored as TuckChoice) : "never";
}

/** The minutes of quiet before the island may hide; null for never. */
export function tuckMinutes(choice: TuckChoice): number | null {
  return choice === "never" ? null : Number(choice);
}

/** The pill states that are live: working, thinking or searching, or waiting for an answer (an approval or a question). */
export const LIVE_STATES: ReadonlySet<string> = new Set(["working", "thinking", "searching", "approval", "question"]);

/** Live now: a pill in a live state. An open session that is idle does not count, nor does a finished, idle or other pill. */
export function isLive(pillStates: readonly string[]): boolean {
  return pillStates.some((s) => LIVE_STATES.has(s));
}

/** Seconds from `now` until the compact island may hide, counted from the last activity; null while it may not (never, or something is live). 0 is due now. */
export function hideDelay(choice: TuckChoice, lastActivity: number, now: number, live: boolean): number | null {
  const minutes = tuckMinutes(choice);
  if (minutes === null || live) return null;
  return Math.max(0, lastActivity + minutes * 60 - now);
}
