// The Sidekick's memory (sub-project F1, spec "The ledger"): one small record per session, kept from the hook events, in memory only. It holds what the contract's
// `eventFrom` and `ledgerApply` keep (a basename, a command key, counts, times) and nothing else: not the prompt, not the assistant's text, not `transcript_path`, not a
// command, not a full path. It is never written to disk, never logged and gone when the app quits. Loaded by the plain-Node checks.

import { approvalAnsweredEvent, emptyLedger, eventFrom, ledgerApply, ledgerPrune, liveSessions, markNudged } from "./core.ts";
import type { Ledger, Session, SidekickEvent } from "./core.ts";

export class SessionLedger {
  private ledger: Ledger = emptyLedger();

  /**
   * A hook payload comes in and the event it makes goes into the ledger; the event is returned, or null when the payload is not one the ledger knows (an unknown event, a
   * payload that is not an object). `now` is the time the app received it, in ms. There is no Codex on Windows and Linux, so `codex` is off.
   */
  feed(payload: unknown, now: number): SidekickEvent | null {
    const ev = eventFrom(payload, now, { codex: false });
    if (!ev) return null;
    this.ledger = ledgerApply(this.ledger, ev);
    return ev;
  }

  /** The user's click on an approval card: the app makes this event, it is not a hook. */
  answered(agentId: string, sessionId: string, now: number): void {
    this.ledger = ledgerApply(this.ledger, approvalAnsweredEvent(agentId, sessionId, now));
  }

  /** A session was nudged: it gets no second nudge. */
  markNudged(key: string, now: number): void {
    this.ledger = markNudged(this.ledger, key, now);
  }

  /** A nudge that was shown and folded away unseen was never given: its session may be nudged again. */
  unmarkNudged(key: string): void {
    this.ledger = { ...this.ledger, sessions: this.ledger.sessions.map((s) => (s.key === key ? { ...s, nudgedAt: null } : s)) };
  }

  /** Drops what is over: 30 minutes after a session's end, 12 hours after the last event of one that never ended. */
  prune(now: number): void {
    this.ledger = ledgerPrune(this.ledger, now);
  }

  /** The ledger as the pure rules take it. It is never changed in place: every change makes a new one. */
  get snapshot(): Ledger {
    return this.ledger;
  }

  /** The sessions that have not ended. */
  get live(): Session[] {
    return liveSessions(this.ledger);
  }

  clear(): void {
    this.ledger = emptyLedger();
  }
}
