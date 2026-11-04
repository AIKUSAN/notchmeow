import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { DRAG_OUT_GRACE_MS, DragOutGuard } from "../../src/shelf/dragguard.ts";

// Dragging a shelf item out of the island (G1): the guard that keeps an item dragged out and back in from being added twice, and how the island wires the native drag source.
const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const isl = read("src/island/island.ts");

test("the guard blocks the item's own drop during the drag and for a short grace after it, and nothing else", () => {
  const g = new DragOutGuard();
  assert.equal(g.blocks(0), false, "nothing is blocked before any drag");
  assert.equal(g.blocks(1e9), false);
  g.start();
  assert.equal(g.active, true);
  assert.equal(g.blocks(5), true);
  assert.equal(g.blocks(1e9), true, "a drag can last as long as the user likes");
  g.end(10_000);
  assert.equal(g.active, false);
  assert.equal(g.blocks(10_000 + DRAG_OUT_GRACE_MS - 1), true, "the drop the system reports after the call returned");
  assert.equal(g.blocks(10_000 + DRAG_OUT_GRACE_MS), false);
  g.start();
  g.end(20_000);
  assert.equal(g.blocks(20_100), true, "a second drag has its own grace");
});

test("the island ignores every drag event during and just after its own drag, before the halves and the Ask drop see it", () => {
  const handler = isl.slice(isl.indexOf("private onDragDrop("), isl.indexOf("switch (e.type) {", isl.indexOf("private onDragDrop(")));
  assert.match(handler, /if \(State\.paused\) return;\s*\/\/ An item dragged out of the shelf[^\n]*\n\s*if \(this\.dragOut\.blocks\(performance\.now\(\)\)\) return;/);
});

test("a drag out keeps the island open while it lasts, asks Rust by id, and lets go of the pin and tells the page when it ends, whatever the end", () => {
  const out = isl.match(/private dragOutShelf\(ids: string\[\]\) \{[\s\S]*?\n  \}\n/)[0];
  assert.match(out, /if \(!State\.shelfCaps\.dragOut \|\| this\.dragOut\.active \|\| ids\.length === 0\) return;\s*this\.dragOut\.start\(\);\s*this\.fsm\.setShelfHold\("drag", true\);/);
  assert.match(out, /Bridge\.shelfDragOut\(ids\)\s*\.catch\(\(err\) => void Bridge\.log\(`drag out failed: \$\{String\(err\)\}`\)\)\s*\.finally\(\(\) => \{\s*this\.dragOut\.end\(performance\.now\(\)\);\s*this\.fsm\.setShelfHold\("drag", false\);\s*State\.notify\(\);/);
  assert.match(isl, /dragOut: \(ids\) => this\.dragOutShelf\(ids\) \},/);
  assert.doesNotMatch(out, /setTimeout|setInterval/, "the guard's grace is a comparison of times, not a timer");
});

test("Rust: the drag-out command resolves ids to the files that exist, and the boot info says what this system can do", () => {
  const lib = read("src-tauri/src/lib.rs");
  assert.match(lib, /async fn shelf_drag_out\(app: AppHandle, ids: Vec<String>\) -> Result<&'static str, String> \{\s*let paths = blocking\(move \|\| shelf_store\(\)\.resolve\(&ids\)\)\.await\?;\s*dragout::start\(&app, paths\)\.await/);
  assert.match(lib, /shelf: ShelfCaps \{ drag_out: dragout::supported\(\), send: [^}]+ \},/, "the drag out comes from the one switch in dragout.rs");
  assert.match(read("src/core/bridge.ts"), /shelf: \{ dragOut: boolean; send: boolean \};/);
  assert.match(read("src/main.ts"), /if \(boot\?\.shelf\) State\.shelfCaps = \{ dragOut: boot\.shelf\.dragOut, send: boot\.shelf\.send \};/);
});

test("with no drag out (the fallback), a press on a tile only ticks it and the view shows no drag", async () => {
  const { State } = await import("../../src/core/state.ts");
  assert.equal(State.shelfCaps.dragOut, false, "off until Rust says it can");
  assert.match(read("src/views/shelf.ts"), /if \(State\.shelfCaps\.dragOut && !e\.missing\) act\.dragOut\(ids\(\)\);/);
});
