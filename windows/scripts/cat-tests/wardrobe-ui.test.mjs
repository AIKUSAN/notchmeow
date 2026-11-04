import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { OUTFIT_IDS } from "../../src/cat/wardrobe.ts";
import { autoLabel, localDate, previewOutfit, storedFor, tileOutfit, wardrobeTiles } from "../../src/cat/wardrobeui.ts";

// What Settings → Wardrobe shows (sub-project I): the pure parts replayed, the page's glue pinned by source (it needs a browser; the headless pictures are in the plan's checkpoints).
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const on = (y, m, d) => ({ y, m, d });

test("the tiles are the 18 IDs in the grid's order, in five rows with their headings, and only Auto is wide", () => {
  const groups = wardrobeTiles(on(2025, 7, 4));
  assert.deepEqual(groups.map((g) => g.name), ["", "Seasonal", "Everyday", "Cat extras", "The cats' own"]);
  assert.deepEqual(groups.flatMap((g) => g.tiles.map((t) => t.id)), [...OUTFIT_IDS]);
  assert.deepEqual(groups.flatMap((g) => g.tiles).filter((t) => t.wide).map((t) => t.id), ["auto"]);
  assert.deepEqual(groups[1].tiles.map((t) => t.label), ["Party hat", "Santa hat", "Witch hat", "Bunny ears", "Sunglasses"]);
  assert.equal(groups[0].tiles[1].label, "None");
  assert.equal(groups[0].tiles[1].wears, "none");
});

test("the Auto tile shows today's result: its label and what its cat wears, for the five rules and for a plain day", () => {
  assert.equal(autoLabel(on(2025, 12, 24)), "Auto: today, Santa hat");
  assert.equal(autoLabel(on(2026, 1, 1)), "Auto: today, Party hat");
  assert.equal(autoLabel(on(2025, 10, 31)), "Auto: today, Witch hat");
  assert.equal(autoLabel(on(2025, 4, 18)), "Auto: today, Bunny ears");
  assert.equal(autoLabel(on(2025, 7, 4)), "Auto: today, Sunglasses");
  assert.equal(autoLabel(on(2025, 3, 3)), "Auto: today, none");
  assert.equal(wardrobeTiles(on(2025, 12, 24))[0].tiles[0].wears, "santahat");
  assert.equal(wardrobeTiles(on(2025, 3, 3))[0].tiles[0].wears, "none");
  assert.deepEqual(localDate(new Date(2025, 11, 24, 23, 59)), on(2025, 12, 24));
  assert.equal(tileOutfit("auto", on(2025, 12, 24)), "santahat");
  assert.equal(tileOutfit("bow", on(2025, 12, 24)), "bow");
});

test("the preview wears the tile under the pointer, else the chosen outfit, resolved for today, and null for none", () => {
  const xmas = on(2025, 12, 24), plain = on(2025, 3, 3);
  assert.equal(previewOutfit("crown", null, xmas), "crown", "the chosen one");
  assert.equal(previewOutfit("crown", "bow", xmas), "bow", "the tile under the pointer wins");
  assert.equal(previewOutfit("crown", "auto", xmas), "santahat", "the Auto tile shows today's result");
  assert.equal(previewOutfit("auto", null, xmas), "santahat");
  assert.equal(previewOutfit("auto", null, plain), null, "nothing today: bare");
  assert.equal(previewOutfit("crown", "none", xmas), null, "hovering None shows a bare cat");
  assert.equal(previewOutfit("junk", undefined, xmas), "santahat", "a stored value that is not an ID is auto");
  assert.equal(previewOutfit(undefined, undefined, plain), null);
});

test("a click stores the tile's own ID: Auto stays auto and a made-up ID is auto", () => {
  for (const id of OUTFIT_IDS) assert.equal(storedFor(id), id);
  for (const bad of [undefined, null, 7, "Crown", "", "fancyhat"]) assert.equal(storedFor(bad), "auto", String(bad));
});

test("the section: its own card after Cat, built from the window's own rows, the preview coat stores nothing, and nothing runs a loop of its own", () => {
  const w = source("settings/wardrobe.ts"), cat = source("settings/cat.ts"), app = source("settings/app.ts");
  assert.match(w, /host\.put\(withOutfit\(now\(\), storedFor\(t\.id\)\), true\)/, "a click stores the tile's ID through withOutfit");
  assert.equal((w.match(/host\.put\(/g) || []).length, 1, "that click is the only thing that stores");
  assert.match(w, /\(v\) => \{ coat = v; preview\.setCoat\(coat\); drawTiles\(\); \}/, "the coat picker changes the preview and the stills only");
  assert.match(w, /"Only the preview: nothing is stored\."/);
  assert.doesNotMatch(w, /requestAnimationFrame|setInterval|setTimeout|VisibleLoop/);
  assert.match(w, /preview\.outfit = previewOutfit\(now\(\)\.outfit, hover, localDate\(new Date\(\)\)\);/);
  // Project cats (Task 9) draws and syncs between the display's and the wardrobe's calls: the wardrobe still follows the display directly, with at most that one line between them.
  assert.match(cat, /if \(preview\) drawOne\(preview, previewCv, PREVIEW_W, PREVIEW_H, dt\);\s*display\?\.draw\(dt\);\s*(?:projects\?\.draw\(dt\);\s*)?wardrobe\?\.draw\(dt\);/);
  assert.match(cat, /display\?\.sync\(\);\s*(?:projects\?\.sync\(\);\s*)?wardrobe\?\.sync\(\);/);
  assert.match(cat, /return \{ el, sync: paint, dispose \};/);
  // The Cat page builds the Cat section with its tab (app.ts); the shell shows one page at a time, and the wardrobe's card is inside that section.
  assert.match(app, /return catSection\(\{[\s\S]*?\}, \(place\.tab \?\? "look"\) as CatTab\);/);
});

test("the new CSS is new class names only: the Wardrobe block adds .wardrobe-tiles, .wardrobe-grid and .wardrobe-cell, and no existing selector", () => {
  const css = source("settings/settings.css"), start = css.indexOf("/* Wardrobe (sub-project I)");
  assert.ok(start > 0);
  const block = css.slice(start).replace(/\/\*[\s\S]*?\*\//g, "");
  const selectors = [...block.matchAll(/([^{}]+)\{/g)].map((m) => m[1].trim());
  assert.ok(selectors.length >= 4, `${selectors.length} selectors`);
  for (const sel of selectors) assert.match(sel, /^\.wardrobe-(tiles|grid|cell)\b/, sel);
});
