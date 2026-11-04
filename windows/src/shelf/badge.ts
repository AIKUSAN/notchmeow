// The compact island's shelf badge (sub-project G1): a small count at the right end of the wing, shown only while the island is already compact. It never wakes a hidden island and
// never keeps an island visible: what it shows is a function of the mode, nothing here opens, reveals or expands. Pure, so the plain-Node checks load it.

import type { IslandMode } from "../core/layout.ts";

/** Whether the badge is shown: the island is compact (not hidden, not open), there is something on the shelf, and no greeting is playing. */
export function badgeShown(mode: IslandMode, count: number, greeting: boolean): boolean {
  return mode === "compact" && count > 0 && !greeting;
}

/** What the badge says: the count, "9+" past nine (it is 16 px wide). */
export function badgeLabel(count: number): string {
  return count > 9 ? "9+" : String(Math.max(0, Math.floor(count)));
}

/** Its tooltip. */
export function badgeTitle(count: number): string {
  return count === 1 ? "Shelf: 1 file" : `Shelf: ${count} files`;
}

/** Where it sits in the compact island, in the island's px: the right end of the wing, after the 2x2 grid (which ends 25 px from the right edge). */
export function badgePlace(islandW: number, islandH: number): { left: number; top: number } {
  return { left: islandW - 25, top: islandH / 2 - 8 };
}
