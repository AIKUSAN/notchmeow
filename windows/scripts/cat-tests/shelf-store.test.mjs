import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { ShelfStore, shelfNote, sizeLabel } from "../../src/shelf/store.ts";
import { SHELF_MAX } from "../../src/shelf/rules.ts";
import { State } from "../../src/core/state.ts";

// The page's shelf (G1): the list Rust last gave, the ticks and the note. The backend is faked; the in-memory one the browser uses runs the contract's own rules.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const entry = (id, over = {}) => ({ id, name: `${id}.txt`, size: 10, folder: false, copy: false, addedAt: 1, missing: false, ...over });
function fake(start = []) {
  let list = start;
  const calls = [];
  return {
    calls,
    list: async () => (calls.push("list"), list),
    add: async (paths) => (calls.push(["add", paths]), (list = [...paths.map((p, i) => entry(`n${list.length + i}`, { name: p })), ...list].slice(0, SHELF_MAX)), { entries: list, results: paths.map(() => "added") }),
    remove: async (id) => (calls.push(["remove", id]), (list = list.filter((e) => e.id !== id))),
    clear: async () => (calls.push("clear"), (list = [])),
  };
}

test("the note after a drop: nothing to say when every file went on, one sentence for what was left off", () => {
  assert.equal(shelfNote(["added", "duplicate"]), null);
  assert.match(shelfNote(["added", "full"]), /shelf is full \(30\)\. One file was left off/);
  assert.match(shelfNote(["full", "full", "added"]), /2 files were left off/);
  assert.match(shelfNote(["invalid"]), /can't go on the shelf/);
  assert.match(shelfNote(["full", "invalid"]), /full/, "full comes first");
});

test("sizes read like a file manager's, and a folder has none to show", () => {
  assert.deepEqual([0, 999, 1000, 12345, 3400000, 250000000, 5e12].map(sizeLabel), ["0 B", "999 B", "1 KB", "12.3 KB", "3.4 MB", "250 MB", "5 TB"]);
});

test("nothing is read until refresh, and a store with no backend does nothing", async () => {
  const s = new ShelfStore();
  assert.equal(s.count, 0);
  await s.refresh(); await s.add(["/a"]); await s.remove("x"); await s.clear();
  assert.equal(s.count, 0);
  const b = fake([entry("a")]);
  s.attach(b);
  assert.equal(b.calls.length, 0);
  await s.refresh();
  assert.deepEqual(b.calls, ["list"]);
  assert.equal(s.count, 1);
});

test("add, remove and clear take Rust's answer, tell the page, and drop ticks for items that are gone", async () => {
  let changes = 0;
  const s = new ShelfStore(() => changes++);
  s.attach(fake([entry("a"), entry("b"), entry("c")]));
  await s.refresh();
  s.toggle("a"); s.toggle("b");
  assert.deepEqual([...s.selected], ["a", "b"]);
  await s.remove("a");
  assert.deepEqual([...s.selected], ["b"]);
  assert.deepEqual(s.entries.map((e) => e.id), ["b", "c"]);
  const before = changes;
  assert.deepEqual(await s.add([]), [], "an empty drop asks nobody");
  assert.equal(changes, before);
  assert.deepEqual(await s.add(["/x/new.txt"]), ["added"]);
  assert.equal(s.entries[0].name, "/x/new.txt");
  await s.clear();
  assert.equal(s.count, 0);
  assert.equal(s.selected.size, 0);
  s.toggle("nobody");
  assert.equal(s.selected.size, 0, "an unknown id cannot be ticked");
});

test("a refused file leaves a note that the next change clears", async () => {
  const s = new ShelfStore();
  s.attach({ ...fake(), add: async () => ({ entries: [entry("a")], results: ["added", "full"] }) });
  await s.add(["/a", "/b"]);
  assert.match(s.note, /left off/);
  await s.remove("a");
  assert.equal(s.note, null);
});

test("Send and Show act on the ticked items when the tile is one of several, else on the tile; Ask is off with several ticked, for a folder and for a missing original", async () => {
  const s = new ShelfStore();
  s.attach(fake([entry("a"), entry("b"), entry("c", { folder: true }), entry("d", { missing: true })]));
  await s.refresh();
  assert.deepEqual(s.targets("a"), ["a"]);
  s.toggle("a");
  assert.deepEqual(s.targets("a"), ["a"], "one ticked is just that one");
  assert.equal(s.canAsk("b"), true);
  s.toggle("b");
  assert.deepEqual(s.targets("a"), ["a", "b"]);
  assert.deepEqual(s.targets("c"), ["c"], "a tile outside the ticks is only itself");
  assert.equal(s.canAsk("a"), false, "several ticked");
  s.toggle("b");
  assert.equal(s.canAsk("a"), true);
  assert.equal(s.canAsk("c"), false, "a folder");
  assert.equal(s.canAsk("d"), false, "a missing original");
  assert.equal(s.canAsk("zzz"), false);
});

test("State holds the shelf and notifies the island when it changes; the store imports nothing of Tauri", async () => {
  let n = 0;
  const off = State.subscribe(() => n++);
  State.shelf.attach(fake([entry("a")]));
  await State.shelf.refresh();
  off();
  assert.equal(n, 1);
  assert.doesNotMatch(source("shelf/store.ts"), /bridge|@tauri-apps/, "pure: the plain-Node checks load it");
  assert.match(source("core/state.ts"), /shelf = new ShelfStore\(\(\) => this\.notify\(\)\);/);
});
