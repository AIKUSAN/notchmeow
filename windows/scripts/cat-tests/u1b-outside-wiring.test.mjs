import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Where the island page calls the outside click's rules (island.ts, main.ts, bridge.ts), pinned as source text.
const read = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const island = read("island/island.ts"), main = read("main.ts"), bridge = read("core/bridge.ts"), rules = read("island/outsideclick.ts");

test("the glue is built once and folds with collapse(), the same fold as Escape", () => {
  assert.match(island, /private outside = new OutsideClick\(\(e\) => this\.outsideContext\(e\), \(\) => this\.collapse\(\)\);/);
  assert.match(island, /onPointerButton\(e: ButtonEvent\) \{\s*if \(!this\.watchingButtons\) return;\s*this\.outside\.onButton\(e\);/, "an edge that arrives after the watch went off is ignored");
});

test("the OS is asked to read the buttons only while the island is expanded and the OS has a global pointer", () => {
  assert.match(island, /const on = this\.cursorPoll && State\.mode === "expanded";/);
  assert.match(island, /State\.mode = mode;\s*this\.syncGlow\(\);\s*this\.syncPointerWatch\(\);/, "setMode follows the mode");
  assert.match(island, /setCursorPoll\(on: boolean\) \{\s*this\.cursorPoll = on;\s*this\.syncPointerWatch\(\);/, "and so does the boot answer");
  assert.equal((island.match(/Bridge\.watchPointerButtons\(/g) ?? []).length, 1, "one call site");
  assert.match(bridge, /watchPointerButtons: \(on: boolean\) => call<void>\("watch_pointer_buttons", \{ on \}\)/);
  assert.match(bridge, /\{ name: "pointer-button"; payload: \{ down: boolean; x: number; y: number; own: boolean \} \}/);
  assert.match(main, /onEvent<ButtonEvent>\("pointer-button", \(e\) => island\.onPointerButton\(e\)\)/);
});

test("the reasons to stay are the Mac's list, in the PC's own facts", () => {
  assert.match(island, /expanded: State\.mode === "expanded",/);
  assert.match(island, /pinned: State\.isPinned,/);
  assert.match(island, /held: this\.fsm\.held \|\| this\.fsm\.menuOpen,/);
  assert.match(island, /typing: State\.view === "prompt" && document\.hasFocus\(\) && \(field instanceof HTMLTextAreaElement \|\| field instanceof HTMLInputElement\),/);
  assert.match(island, /pointerInIsland: e\.own \|\| this\.hitRectContains\(e\.x, e\.y\),/);
  assert.match(island, /busy: this\.press\.active \|\| this\.dragOut\.active \|\| State\.fileDragOver \|\| this\.uploadActive,/);
});

test("it costs nothing of its own: no timer, no listener, no frame in the rules, and no new interval or frame loop in the island", () => {
  assert.doesNotMatch(rules, /setTimeout|setInterval|addEventListener|requestAnimationFrame|performance\.now/);
  assert.equal((island.match(/setInterval/g) ?? []).length, 0);
  assert.equal((island.match(/requestAnimationFrame/g) ?? []).length, 2, "the island's two existing frame requests, no more");
});
