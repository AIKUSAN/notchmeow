// The Wardrobe items of a native right-click menu (sub-project I), shared by the desktop cat's menu (desktop/body.ts) and the island cat's (island/island.ts): the 18 choices in the contract's order
// (`OUTFIT_GROUPS`), the groups apart with a separator and a disabled heading each, and a tick on the stored choice. It only builds and ticks items; what a pick does is the caller's. Tauri's menu API
// is not available to the plain-Node checks, so this file is pinned by source (scripts/cat-tests/wardrobe-desktop-menu.test.mjs) and looked at in the real build.

import { CheckMenuItem, MenuItem, PredefinedMenuItem } from "@tauri-apps/api/menu";
import { OUTFIT_GROUPS, OUTFIT_IDS, OUTFIT_NAMES, outfitIdOf } from "../cat/wardrobe";
import type { OutfitId } from "../cat/wardrobe";

/** The items for a Submenu named Wardrobe, and the 18 check items in the order of `OUTFIT_IDS` (the ones `tickWardrobe` moves the tick between). */
export interface WardrobeItems {
  items: (CheckMenuItem | MenuItem | PredefinedMenuItem)[];
  ticks: CheckMenuItem[];
}

/** Builds the items once (a native menu's items are resources in Rust that nothing frees, so a menu is built once and reused). `pick` is called with the ID of the item the user chose. */
export async function buildWardrobeItems(pick: (id: OutfitId) => void): Promise<WardrobeItems> {
  const ticks = await Promise.all(OUTFIT_IDS.map((id) => CheckMenuItem.new({ id: `outfit-${id}`, text: OUTFIT_NAMES[id], checked: false, action: () => pick(id) })));
  const items: WardrobeItems["items"] = [];
  for (const [gi, g] of OUTFIT_GROUPS.entries()) {
    if (gi) items.push(await PredefinedMenuItem.new({ item: "Separator" }));
    if (g.name) items.push(await MenuItem.new({ id: `outfit-group-${g.id}`, text: g.name, enabled: false }));
    for (const id of g.ids) items.push(ticks[OUTFIT_IDS.indexOf(id)]);
  }
  return { items, ticks };
}

/** Puts the tick on the stored choice (anything that is not one of the 18 IDs is `auto`), and takes it off the others. Call it before every popup: only the tick changes between two right-clicks. */
export async function tickWardrobe(w: WardrobeItems, choice: unknown): Promise<void> {
  const id = outfitIdOf(choice);
  await Promise.all(w.ticks.map((c, i) => c.setChecked(OUTFIT_IDS[i] === id)));
}
