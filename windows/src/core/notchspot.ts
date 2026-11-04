// Where the big cat's spot in the notch is on the desktop, and back (sub-project H, spec §1). The desktop cat's flight starts and ends there, and a cat dragged out of the notch is
// carried by the pointer, so the island's window pixels have to be turned into the points the contract's rules use (desktop.ts: the primary screen's scale as the one unit, the origin
// at the top left of the main screen) and back. Rust says where the island's screen is (`desktop_screens`); this is the arithmetic. Pure, so the plain-Node checks (npm run check:cat) can load it.

import type { Spot } from "../cat/desktop.ts";
import type { DesktopWorld } from "../cat/desktopview.ts";
import { PANEL_W, botPosition, islandSize, pairPlacement } from "./layout.ts";
import type { IslandMode, IslandViewName } from "./layout.ts";

/** The big cat's centre in the island window's px: where the compact cat sits (the hidden island counts as compact), or where the view puts it; the first of the pair in Two cats mode. */
export function notchCatLocal(mode: IslandMode, view: IslandViewName, pair: boolean): { x: number; y: number } {
  const m: IslandMode = mode === "hidden" ? "compact" : mode, size = islandSize(m, view);
  const p = (pair ? pairPlacement(m, view, size.h)?.first : null) ?? botPosition(m, view, size.h);
  return { x: (PANEL_W - size.w) / 2 + p.cx, y: p.cy };
}

/** A point of the island window (CSS px, the window is PANEL_W wide while the island is open) as a spot on the desktop. */
export const islandToSpot = (w: DesktopWorld, x: number, y: number): Spot => ({ x: w.island.x + w.island.w / 2 + (x - PANEL_W / 2) * w.islandK, y: w.island.y + y * w.islandK });

/** The inverse: a spot as a point of the island window. */
export const spotToIsland = (w: DesktopWorld, s: Spot): { x: number; y: number } => ({ x: PANEL_W / 2 + (s.x - (w.island.x + w.island.w / 2)) / w.islandK, y: (s.y - w.island.y) / w.islandK });
