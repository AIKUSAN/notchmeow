import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The ?dev page's Wardrobe panel (sub-project I): the contact sheet is pinned by source (it needs a browser; the headless pictures are the plan's Checkpoint 1) and it runs nothing of its own.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("dev.ts mounts the Wardrobe panel after the Desktop cat's, and the panel is built from the app's renderer and the contract's rules", () => {
  const dev = source("cat/dev.ts"), w = source("cat/devwardrobe.ts");
  assert.match(dev, /import \{ mountWardrobeDev \} from "\.\/devwardrobe\.ts";/);
  assert.match(dev, /mountDesktopDev\(root, wrap, ticks\);\s*\/\/[^\n]*\n\s*mountWardrobeDev\(root, wrap\);/);
  assert.match(w, /import \{ drawCat, stillView \} from "\.\/renderer\.ts";/);
  assert.match(w, /OUTFIT_DRAWN\.forEach/);
  for (const s of ["wardrobe-sheet", "wardrobe-notch", "wardrobe-turned", "wardrobe-neck", "wardrobe-extra", "wardrobe-fits", "wardrobe-auto"]) assert.ok(w.includes(`"${s}"`) || w.includes(`${s}`), s);
  assert.match(w, /const STRIPS: readonly \(readonly \[number, number\]\)\[\] = \[\[20, 32\], \[18, 24\]\];/, "the compact notch's two strips: Ø20 in 32 pt and Ø18 in 24 pt");
});

test("the panel draws stills when a control changes: no timer, no frame callback, no loop", () => {
  const w = source("cat/devwardrobe.ts");
  assert.doesNotMatch(w, /requestAnimationFrame|setInterval|setTimeout|ticks/);
});

test("the release build does not contain the panel: only dev.ts imports it, and dev.ts is loaded behind import.meta.env.DEV", () => {
  assert.match(source("main.ts"), /import\.meta\.env\.DEV/);
  for (const rel of ["main.ts", "island/island.ts", "settings/main.ts", "desktop/main.ts"]) assert.ok(!/devwardrobe/.test(source(rel)), `${rel} does not import it`);
});
