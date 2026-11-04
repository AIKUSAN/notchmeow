// The Pin item of a project pill's native right-click menu (sub-project P): one item, Pin or Unpin by the owner's words, that calls `pick` when the user chooses it. The island
// builds the menu once and reuses it, and holds itself open while it is up (island/island.ts showProjectMenu), as the Wardrobe menu does. Tauri's menu API is not
// available to the plain-Node checks, so this file is looked at in the real build; the island's pins are in scripts/projects-tests/views.test.mjs.

import { Menu, MenuItem } from "@tauri-apps/api/menu";

export interface PinMenu { menu: Menu; item: MenuItem }

/** Builds the menu with its one item. The item's text is set by the caller before each popup (`pinTitle`). */
export async function buildPinMenu(pick: () => void): Promise<PinMenu> {
  const item = await MenuItem.new({ text: "Pin", action: pick });
  return { menu: await Menu.new({ items: [item] }), item };
}
