// The one tick and the peek's dwell (ProjectsClock.nextDelay and ProjectsModel's arm, rearm and peek). Pure apart from the injected one-shot timer and clock:
// no setInterval, no requestAnimationFrame, no thread. Each class arms at most one timer through the `OneShot` it is given.

import { AGO_TICK_MS, APP_WAIT_MS, CARD_APPROVAL_MS, CARD_QUESTION_MS, FINISHED_MS, PEEK_DWELL_MS, QUIET_IDLE_MS } from "./core.ts";
import type { Registry } from "./core.ts";

/** The one-shot timer the island gives: `set` returns an id, `clear` drops it. Nothing repeats. */
export interface OneShot { set(fn: () => void, ms: number): number; clear(id: number): void }

const FLOOR_MS = 50;

/**
 * The delay of the one tick: the nearest of the next "… ago" minute (AGO_TICK_MS), a shown finished ending, an open ask's end and a working session's turn to idle.
 * Only a boundary strictly after `now` counts (one at exactly `now` has passed); the result is never below 50 ms.
 */
export function nextDelay(reg: Registry, now: number): number {
  let best = AGO_TICK_MS;
  const consider = (at: number) => {
    const d = at - now;
    if (d > 0 && d < best) best = d;
  };
  for (const s of reg.sessions) {
    if (s.run === "working") consider(s.lastAt + QUIET_IDLE_MS);
    if (s.run === "finished" && s.finishedAt !== null) consider(s.finishedAt + FINISHED_MS);
    for (const ask of s.pending) {
      if (ask.kind !== "approval" && ask.kind !== "question") continue;
      const wait = ask.inApp ? APP_WAIT_MS : ask.kind === "approval" ? CARD_APPROVAL_MS : CARD_QUESTION_MS;
      consider(ask.at + wait);
    }
  }
  return Math.max(FLOOR_MS, best);
}

/**
 * The tick: one one-shot while the island is open. `sync(true)` arms it for the delay from now, and re-arms only when that is earlier than the armed one,
 * so a stream of events never pushes it back. `sync(false)` clears it. When it fires it is no longer armed and `fire` runs; the owner syncs again.
 */
export class ProjectsTick {
  private id: number | null = null;
  private due = 0;
  private readonly timer: OneShot;
  private readonly now: () => number;
  private readonly delay: () => number;
  private readonly onFire: () => void;

  constructor(timer: OneShot, now: () => number, delay: () => number, fire: () => void) {
    this.timer = timer;
    this.now = now;
    this.delay = delay;
    this.onFire = fire;
  }

  sync(open: boolean): void {
    if (!open) return this.disarm();
    const ms = this.delay();
    const due = this.now() + ms;
    if (this.id !== null && due >= this.due) return;
    this.disarm();
    this.due = due;
    this.id = this.timer.set(() => {
      this.id = null;
      this.onFire();
    }, ms);
  }

  get armed(): boolean {
    return this.id !== null;
  }

  private disarm(): void {
    if (this.id !== null) this.timer.clear(this.id);
    this.id = null;
  }
}

/**
 * The peek's dwell: a pill shows its peek after PEEK_DWELL_MS on it. Entering another pill replaces the pending one; leaving clears the timer and hides a shown peek.
 */
export class PeekDwell {
  private id: number | null = null;
  private pending: string | null = null;
  private current: string | null = null;
  private readonly timer: OneShot;
  private readonly show: (id: string) => void;
  private readonly hide: () => void;

  constructor(timer: OneShot, show: (id: string) => void, hide: () => void) {
    this.timer = timer;
    this.show = show;
    this.hide = hide;
  }

  enter(id: string): void {
    if (id === this.pending) return;
    this.clearTimer();
    this.pending = id;
    this.id = this.timer.set(() => {
      this.id = null;
      this.current = id;
      this.show(id);
    }, PEEK_DWELL_MS);
  }

  leave(): void {
    this.clearTimer();
    this.pending = null;
    if (this.current !== null) {
      this.current = null;
      this.hide();
    }
  }

  get shown(): string | null {
    return this.current;
  }

  private clearTimer(): void {
    if (this.id !== null) this.timer.clear(this.id);
    this.id = null;
  }
}
