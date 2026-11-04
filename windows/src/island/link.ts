// What the island does for the link (sub-project G2): when a card comes, goes or changes kind, and when the shelf is on screen. Pure rules over the snapshot, plus two tiny drivers that main.ts
// hands the island to. The island itself changes only by the lines that call these (main.ts) and by `State.linkOfferPending` in two places: the desktop cat's alert and the cats' sleep.

import { State } from "../core/state";
import { cardTransition } from "../link/model.ts";
import type { LinkSnapshot } from "../link/model.ts";
import type { IslandMode, IslandViewName } from "../core/layout";

/** The part of the island the link drives: the island's own methods. */
export interface LinkIslandHost {
  alert(view: IslandViewName): void;
  holdOpen(): void;
  dropPin(): void;
  collapse(): void;
}

/**
 * A card came, went or changed kind. A new card, or one of another kind, opens the island on the link view even when it is hidden (the island's own `alert`), and a card with buttons holds
 * it open against the delayed collapse; when the buttons are gone the hold goes (unless a permission request still holds it); when the card is gone and the link view was showing, the
 * island closes. The order matters: `alert` sets the hold from the permission request, and the link's hold comes after it.
 */
export function linkChanged(host: LinkIslandHost, prev: LinkSnapshot, next: LinkSnapshot, viewIsLink: boolean = State.view === "link", pinnedByRequest: boolean = State.isPinned): void {
  const t = cardTransition(prev.card, next.card, viewIsLink);
  if (t.alert) host.alert("link");
  if (t.hold) host.holdOpen();
  if (t.release && !pinnedByRequest) host.dropPin();
  if (t.collapse) host.collapse();
}

/** The shelf is on screen: its view showing in an open island. Rust looks for the machines only while Devices or the shelf is. */
export function shelfLooking(view: IslandViewName, mode: IslandMode): boolean {
  return view === "shelf" && mode === "expanded";
}

/** Says the shelf is open (or not) when that changes, and not otherwise. */
export class ShelfLook {
  private said: boolean | null = null;
  sync(view: IslandViewName, mode: IslandMode, say: (open: boolean) => void): void {
    const open = shelfLooking(view, mode);
    if (open === this.said) return;
    this.said = open;
    say(open);
  }
}
