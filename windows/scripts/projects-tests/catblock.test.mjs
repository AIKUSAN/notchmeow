import test from "node:test";
import assert from "node:assert/strict";
import * as D from "../../src/cat/display.ts";

// The projectCats key of the cat block (sub-project P, docs/PROJECTS-CONTRACT.md): a folder's own cat, cleaned with the block and edited by two helpers that
// refuse what the clean-up would drop (the Mac's updateProjectCats guard).

test("projectCats is cleaned with the block and edited by two helpers", () => {
  assert.deepEqual(D.cleanCatBlock(null).projectCats, {});
  assert.deepEqual(D.cleanCatBlock({ projectCats: { notchmeow: "oreo", "a/b": "momo", x: "tiger", constructor: "momo" } }).projectCats, { notchmeow: "oreo" });
  const b = D.withProjectCat(D.defaultCatBlock(), "notchmeow", "oreo");
  assert.deepEqual(b.projectCats, { notchmeow: "oreo" });
  assert.equal(D.withProjectCat(b, "C:\\x", "momo"), b, "a key that looks like a path is never stored: the block comes back as it was");
  assert.deepEqual(D.withoutProjectCat(b, "notchmeow").projectCats, {});
  assert.deepEqual(D.defaultCatBlock().projectCats, {}, "the input is not changed");
  assert.deepEqual(D.cleanCatBlock(b), b, "cleaning twice changes nothing");
  assert.equal(D.withDisplayMode(b, "two").projectCats.notchmeow, "oreo", "another row's edit keeps it");
});

test("a project key with an invisible character is dropped", () => {
  assert.deepEqual(D.cleanCatBlock({ projectCats: { "a\u200Bb": "momo", "a\u202Eb": "momo", "a\u{E0001}b": "momo", ab: "momo" } }).projectCats, { ab: "momo" });
});

test("at 256 stored cats a pick that would push one out is refused; a stored one can still change", () => {
  const full = D.cleanCatBlock({ projectCats: Object.fromEntries(Array.from({ length: 256 }, (_, i) => [`k${String(i).padStart(3, "0")}`, "momo"])) });
  assert.equal(Object.keys(full.projectCats).length, 256);
  assert.equal(D.withProjectCat(full, "a-new-one", "oreo"), full, "'a-new-one' sorts first and would evict k255");
  assert.equal(D.withProjectCat(full, "k255", "oreo").projectCats.k255, "oreo");
});

test("at 256 stored cats a new key that sorts after all of them is refused too, and the block comes back as it was", () => {
  const full = D.cleanCatBlock({ projectCats: Object.fromEntries(Array.from({ length: 256 }, (_, i) => [`k${String(i).padStart(3, "0")}`, "momo"])) });
  assert.equal(D.withProjectCat(full, "zzz-new", "oreo"), full, "'zzz-new' sorts after k255 and would be the one dropped");
  assert.equal(Object.keys(D.withProjectCat(full, "k000", "oreo").projectCats).length, 256, "a stored key can still change, and the count holds");
});
