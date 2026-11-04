import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { State } from "../../src/core/state.ts";

// The shelf view (G1). It needs the DOM, so the checks are source pins; what it draws is looked at in the `?dev` page's Shelf panel (the checkpoint's pictures).
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const view = source("views/shelf.ts");

test("the shelf view is a new view and no existing view changes: the header, the upload views and the style sheet only gain", () => {
  const views = source("views/views.ts");
  assert.match(views, /map\.set\("shelf", buildShelf\(actions\.shelf\)\);/);
  assert.match(views, /\/\*\* What the shelf view's tiles do \(sub-project G1\)\. \*\/\s*shelf: ShelfActions;/);
  const header = views.slice(views.indexOf("export function buildHeader"), views.indexOf("// ── Overview"));
  assert.doesNotMatch(header, /shelf/i, "no new tab or button in the header");
  assert.doesNotMatch(source("views/upload.ts"), /shelf/i);
  assert.doesNotMatch(source("views/icons.ts"), /shelf|tray/i, "the shelf's icons are its own");
});

test("the tiles show the file's icon, name and size, and the four buttons the spec lists; only Remove is there for a missing original", () => {
  assert.match(view, /e\.folder \? SHELF_ICONS\.folder : SHELF_ICONS\.file/);
  assert.match(view, /e\.missing \? "Missing" : e\.folder \? "Folder" : sizeLabel\(e\.size\)/);
  for (const label of ["Ask about it", "Show in folder", "Remove from the shelf"]) assert.match(view, new RegExp(label));
  assert.match(view, /e\.missing \? null : button\("Ask about it", SHELF_ICONS\.ask, \(\) => act\.ask\(e\.id\), !State\.shelf\.canAsk\(e\.id\)\)/, "Ask is off where the store says so");
  assert.match(view, /e\.missing \|\| !State\.shelfCaps\.send \? null : button\(ids\(\)\.length > 1/, "Send only where the system has one, and for the ticked items");
  assert.match(view, /button\("Remove from the shelf", SHELF_ICONS\.remove, \(\) => void State\.shelf\.remove\(e\.id\)\)/);
  assert.match(view, /text: "Clear all", onclick: \(\) => void State\.shelf\.clear\(\)/);
});

test("a press on a tile is a click (it ticks) or, moved 4 px, a drag out where the system can do it; the view holds ids and never a path", () => {
  assert.match(view, /new PressDrag\(\)/, "the same press-or-drag rule as the big cat's");
  assert.match(view, /if \(State\.shelfCaps\.dragOut && !e\.missing\) act\.dragOut\(ids\(\)\);/);
  assert.match(view, /if \(press\.release\(\) === "click"\) State\.shelf\.toggle\(e\.id\);/);
  assert.match(view, /if \(ev\.button !== 0 \|\| \(ev\.target as HTMLElement\)\.closest\("\.sh-acts"\)\) return;/, "a press on a button is the button's");
  assert.doesNotMatch(view, /\.path|\.link|bridge|Bridge|setInterval|setTimeout|requestAnimationFrame/, "no path, no call out, no timer");
});

test("it redraws only when what it shows changed, so a tile under the pointer is not replaced while it is pressed", () => {
  assert.match(view, /const key = JSON\.stringify\(\[s\.entries, \[\.\.\.s\.selected\], s\.note, caps\]\);\s*if \(key === drawn\) return;/);
});

test("the empty placeholder is hidden while a note is set, so a failed read shows its note and not 'Nothing on the shelf.'", () => {
  assert.match(view, /empty\.style\.display = s\.count > 0 \|\| s\.note !== null \? "none" : "";/);
});

test("State starts with no system abilities, so a view built before Rust says shows only Ask, Show in folder and Remove", () => {
  assert.deepEqual(State.shelfCaps, { dragOut: false, send: false });
});

test("the Shelf panel of the ?dev page is registered behind the dev server's own check, and the release build does not hold it", () => {
  assert.match(source("cat/dev.ts"), /mountShelfDev\(root, wrap\);/);
  assert.match(source("main.ts"), /if \(import\.meta\.env\.DEV && new URLSearchParams\(location\.search\)\.has\("dev"\)\) \{\s*const \{ mountDev \} = await import\("\.\/cat\/dev"\);/, "dev.ts, and with it the panel, is only ever imported dynamically behind DEV");
});
