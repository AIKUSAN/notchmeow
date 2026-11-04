import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Narrowing fixes from the whole-branch review of G1 (the Tauri shelf). Source pins: the island needs the DOM and the bridge to run.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const isl = source("island/island.ts");

test("a stale note timer changes the view only while the note is still the view and is the drop that showed it: a shelf drop or a second note inside 2.4 s is not closed early", () => {
  assert.match(isl, /const shown = this\.dropCount;[\s\S]*?window\.setTimeout\(\(\) => \{ if \(State\.view === "note" && this\.dropCount === shown\) this\.setView\(State\.defaultView\(\)\); \}, 2400\);/);
  assert.doesNotMatch(isl, /window\.setTimeout\(\(\) => this\.setView\(State\.defaultView\(\)\), 2400\);/);
});

// A failed read or change never shows an empty shelf: the list stays as it was and a fixed note says so.
const { ShelfStore } = await import("../../src/shelf/store.ts");
const entry = (id) => ({ id, name: `${id}.txt`, size: 10, folder: false, copy: false, addedAt: 1, missing: false });
const failing = (over = {}) => ({
  list: async () => { throw new Error("boom"); },
  add: async () => { throw new Error("boom"); },
  remove: async () => { throw new Error("boom"); },
  clear: async () => { throw new Error("boom"); },
  ...over,
});

test("a failed shelf read keeps the entries it had and shows a note, not an empty shelf", async () => {
  const s = new ShelfStore();
  s.attach(failing({ list: async () => [entry("a"), entry("b")] }));
  await s.refresh();
  assert.deepEqual(s.entries.map((e) => e.id), ["a", "b"]);
  s.attach(failing());
  await s.refresh();
  assert.deepEqual(s.entries.map((e) => e.id), ["a", "b"], "a failed read does not clear the list");
  assert.equal(s.note, "Couldn't read the shelf.");
});

test("a failed shelf change keeps the entries and shows the change note", async () => {
  const s = new ShelfStore();
  s.attach(failing({ list: async () => [entry("a")], remove: async () => { throw new Error("boom"); }, clear: async () => { throw new Error("boom"); }, add: async () => { throw new Error("boom"); } }));
  await s.refresh();
  await s.remove("a");
  assert.deepEqual(s.entries.map((e) => e.id), ["a"]);
  assert.equal(s.note, "Couldn't change the shelf.");
  await s.clear();
  assert.deepEqual(s.entries.map((e) => e.id), ["a"]);
  assert.equal(s.note, "Couldn't change the shelf.");
  await s.add(["/x"]);
  assert.deepEqual(s.entries.map((e) => e.id), ["a"]);
  assert.equal(s.note, "Couldn't change the shelf.");
});

test("the Tauri backend's list throws on failure, so the store can tell a failed read from an empty shelf", () => {
  const backend = fs.readFileSync(new URL("../../src/shelf/backend.ts", import.meta.url), "utf8");
  const bridge = fs.readFileSync(new URL("../../src/core/bridge.ts", import.meta.url), "utf8");
  assert.match(backend, /list: \(\) => Bridge\.shelfList\(\),/);
  assert.match(bridge, /shelfList: \(\) => callOrThrow<ShelfEntry\[\]>\("shelf_list"\),/);
  assert.doesNotMatch(backend, /\?\? \[\]|\?\? \{ entries: \[\], results: \[\] \}/, "the dead fallbacks are gone");
});

test("a list that started before a change does not overwrite the change when it finishes late", async () => {
  let release;
  const s = new ShelfStore();
  s.attach({
    list: () => new Promise((resolve) => { release = () => resolve([entry("old")]); }),
    add: async () => ({ entries: [entry("new")], results: ["added"] }),
    remove: async () => [],
    clear: async () => [],
  });
  const pending = s.refresh();
  await s.add(["/x"]);
  release();
  await pending;
  assert.deepEqual(s.entries.map((e) => e.id), ["new"]);
});

test("a list read that starts while a change is still in flight does not overwrite the change when it finishes late", async () => {
  let release, settle;
  const s = new ShelfStore();
  s.attach({
    list: () => new Promise((resolve) => { release = () => resolve([entry("old")]); }),
    add: () => new Promise((resolve) => { settle = () => resolve({ entries: [entry("new")], results: ["added"] }); }),
    remove: async () => [],
    clear: async () => [],
  });
  const adding = s.add(["/x"]);
  const pending = s.refresh();
  settle();
  await adding;
  release();
  await pending;
  assert.deepEqual(s.entries.map((e) => e.id), ["new"]);
});

test("a drop event with no position keeps the last drag position, and a leave or a drop clears it", () => {
  assert.doesNotMatch(isl, /this\.dragPos = position \?\? null;/, "the drop path does not overwrite the position with null");
  assert.match(isl, /this\.dragPos = position \?\? this\.dragPos;/);
  assert.match(isl, /if \(!State\.fileDragOver\) return;[\s\S]*?UploadSeq\.exitZone\(\);\s*this\.dragPos = null;/, "leave clears it");
  assert.match(isl, /if \(plan\.kind === "none"\) \{\s*this\.setView\(State\.defaultView\(\)\);\s*return;\s*\}\s*\/\/[^\n]*\s*this\.dragPos = null;/, "drop clears it once the half is decided");
});
