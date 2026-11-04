// Where a right-click opens the island cat's menu (sub-project I): on a big cat the island is showing, and nowhere else. Pure: the circles are the island's, in its window's px. The press that
// opens the menu is the right button's; a left press, a click and a drag out of the notch are decided elsewhere (pressdrag.ts) and are not touched by this.

import { catClickTarget } from "../core/layout.ts";
import type { Circle } from "../core/layout.ts";

/** What the island is showing at the moment of the right-click. */
export interface MenuScene {
  /** The island's mode (`hidden`, `compact` or `expanded`). */
  mode: string;
  /** The launch greeting's canvas is up: it draws its own cat. */
  greeting: boolean;
  /** The drop sequence owns the island. */
  upload: boolean;
  /** The big cat's spot in the notch is empty: the desktop cat is out (cat 2 in Two cats mode is still there). */
  desktopOut: boolean;
  /** The big cat's circle, and cat 2's in Two cats mode (null otherwise). */
  bot: Circle;
  bot2: Circle | null;
}

/** Whether a right-click at (x, y) is on a big cat the island is showing. In Two cats mode a click where the circles overlap is the nearer cat's, as for a press. */
export function wardrobeMenuHit(x: number, y: number, s: MenuScene): boolean {
  if (s.mode === "hidden" || s.greeting || s.upload) return false;
  const hit = catClickTarget(x, y, s.bot, s.bot2);
  return hit === 2 || (hit === 1 && !s.desktopOut);
}
