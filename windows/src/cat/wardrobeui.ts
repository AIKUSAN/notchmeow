// What Settings → Wardrobe shows (sub-project I): the tiles in the grid's order with their labels, today's result for the Auto tile, and which outfit the live preview wears. Pure, so the plain-Node
// checks (npm run check:cat) can run it; settings/wardrobe.ts only builds the page from it. The preview and its coat picker store nothing: the only stored value is `outfit`.

import { OUTFIT_GROUPS, OUTFIT_NAMES, outfitIdOf, resolveOutfit } from "./wardrobe.ts";
import type { OutfitId } from "./wardrobe.ts";

/** A local calendar date as the contract's Auto reads it. */
export interface LocalDate { y: number; m: number; d: number }
export const localDate = (now: Date): LocalDate => ({ y: now.getFullYear(), m: now.getMonth() + 1, d: now.getDate() });

/** What a tile stands for today: itself, or for Auto what the calendar says (`none` when nothing is worn). Never `auto`. */
export const tileOutfit = (id: unknown, on: LocalDate): OutfitId => resolveOutfit(id, on.y, on.m, on.d);

/** The Auto tile's label: "Auto: today, Santa hat" or "Auto: today, none". */
export const autoLabel = (on: LocalDate): string => {
  const out = tileOutfit("auto", on);
  return `Auto: today, ${out === "none" ? "none" : OUTFIT_NAMES[out]}`;
};

export interface Tile { id: OutfitId; label: string; /** What the tile's cat wears: a drawn outfit or `none`. */ wears: OutfitId; wide: boolean }
export interface TileGroup { id: string; name: string; tiles: Tile[] }

/** The grid: the two choices first, then the four groups with their headings, in the contract's order. The Auto tile is wide because its label is long. */
export const wardrobeTiles = (on: LocalDate): TileGroup[] =>
  OUTFIT_GROUPS.map((g) => ({
    id: g.id, name: g.name,
    tiles: g.ids.map((id) => ({ id, label: id === "auto" ? autoLabel(on) : OUTFIT_NAMES[id], wears: tileOutfit(id, on), wide: id === "auto" })),
  }));

/** The outfit the live preview draws: the tile under the pointer, else the chosen one, resolved for today; null for none (the engine takes null as bare). */
export const previewOutfit = (stored: unknown, hover: unknown, on: LocalDate): string | null => {
  const out = tileOutfit(hover === null || hover === undefined ? stored : hover, on);
  return out === "none" ? null : out;
};

/** The ID a tile click stores: the tile's own, never its resolved outfit (Auto stays `auto`). */
export const storedFor = (tileId: unknown): OutfitId => outfitIdOf(tileId);
