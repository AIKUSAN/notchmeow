// Auto's one-shot (sub-project I, spec "Auto rules"): the outfit the big cats wear is the stored choice resolved for today (`resolveOutfit`, cat/wardrobe.ts, the contract's rules), and while the
// choice is `auto` it is looked at again at the next local midnight with ONE timer, never a poll. The timer exists only while the stored value is `auto`: an explicit outfit or `none` cancels it.
// A timer that fires late (the computer was asleep) recomputes from the date then. Pure: the clock, the timer and the island are injected, so the plain-Node checks can turn time by hand.

import { outfitIdOf, resolveOutfit } from "../cat/wardrobe.ts";
import type { OutfitId } from "../cat/wardrobe.ts";

/** Milliseconds from `now` to the next local midnight, by the calendar (a day with a daylight-saving change is 23 or 25 hours long), and never under a second, so a timer that fires a moment early cannot spin. */
export function msToNextMidnight(now: Date): number {
  const next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 0, 0);
  const ms = next.getTime() - now.getTime();
  return Number.isFinite(ms) ? Math.max(1000, ms) : 3_600_000;
}

export interface WardrobeEnv {
  /** The local clock. */
  now(): Date;
  /** The stored choice (State.settings.cat.outfit): any value, cleaned here. */
  choice(): unknown;
  set(fn: () => void, ms: number): number;
  clear(id: number): void;
  /** The outfit to draw changed (never `auto`): the island keeps it in State and redraws. */
  apply(outfit: OutfitId): void;
}

export class WardrobeClock {
  private timer: number | null = null;
  private shown: OutfitId | null = null;
  private readonly env: WardrobeEnv;

  constructor(env: WardrobeEnv) { this.env = env; }

  /** The outfit being drawn now, or null before the first `sync`. */
  get outfit(): OutfitId | null { return this.shown; }

  /** The app started or the stored choice may have changed: resolve it for today, tell the island if it differs, and keep a midnight timer exactly while the choice is `auto`. */
  sync(): void {
    if (this.timer !== null) { this.env.clear(this.timer); this.timer = null; }
    const d = this.env.now(), choice = outfitIdOf(this.env.choice()), out = resolveOutfit(choice, d.getFullYear(), d.getMonth() + 1, d.getDate());
    if (out !== this.shown) { this.shown = out; this.env.apply(out); }
    if (choice === "auto") this.timer = this.env.set(() => { this.timer = null; this.sync(); }, msToNextMidnight(d));
  }
}
