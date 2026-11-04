// The Cat page's held slider (Task 6, part 2, B11). While a slider is dragged the page works from its drag value (`held.value`, begun from `held.base`), and any change the
// island makes meanwhile is kept in every field the drag did not move. Pure: no DOM, no storage. Tests: windows/scripts/settings-tests/held.test.mjs (check:settings).

import type { CatBlock } from "../cat/display.ts";

/** The block a drag began from and the block the slider has now. */
export interface Held { base: CatBlock; value: CatBlock }

const isPlain = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const same = (a: unknown, b: unknown): boolean => JSON.stringify(a) === JSON.stringify(b);

/** Merges one level at a time: a leaf the drag moved (`value` differs from `base`) takes `moved` (the drag's value, or the base's own when the base is being rebuilt); any
 * other leaf takes the latest block's. Plain objects are merged key by key, so an island change inside the same object as the drag survives. */
function merge(base: unknown, value: unknown, latest: unknown, moved: "value" | "base"): unknown {
  if (isPlain(base) && isPlain(value) && isPlain(latest)) {
    const out: Record<string, unknown> = {};
    for (const k of new Set([...Object.keys(base), ...Object.keys(value), ...Object.keys(latest)])) {
      const v = merge(base[k], value[k], latest[k], moved);
      if (v !== undefined) out[k] = v;
    }
    return out;
  }
  return same(value, base) ? latest : moved === "value" ? value : base;
}

/** What the Cat page works from. With no slider held it is the window's block (`latest`). While one is held, the fields the drag moved keep its value until the slider lets go,
 * and every other field takes the latest block, so an island change that arrives during the drag is shown and is not lost when the drag is saved. Saving at release is
 * `reconcile({ base, value: next }, latest)` with `base` the block the drag began from (the latest block when there was no drag). */
export function reconcile(held: Held | null, latest: CatBlock): CatBlock {
  if (!held) return latest;
  return merge(held.base, held.value, latest, "value") as CatBlock;
}

/** The block a drag is measured from, brought up to date: the fields the drag did not move take the latest block (an island change the page has since shown), the ones it
 * moved keep their first value. Without this a second island change to a field the first one touched would look like the drag's own move and be lost at release. */
function rebased(held: Held | null, latest: CatBlock): CatBlock {
  return held ? (merge(held.base, held.value, latest, "base") as CatBlock) : latest;
}

/** The held state after one more slider event: `next` is the block the page built (from what `reconcile` showed). */
export function hold(held: Held | null, latest: CatBlock, next: CatBlock): Held {
  return { base: rebased(held, latest), value: next };
}

/** The block the page saves when the slider lets go: the drag's fields over the latest block. */
export function released(held: Held | null, latest: CatBlock, next: CatBlock): CatBlock {
  return reconcile({ base: rebased(held, latest), value: next }, latest);
}
