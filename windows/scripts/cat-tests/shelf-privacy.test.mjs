import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

// A Shelf drop whose add is rejected (G1, privacy): the island logs one fixed line and never what the rejection said, since its text can carry a path or a file name.
// The island needs the DOM to run, so the shelf drop's catch is taken out of its source and run on its own, with a console that keeps what it is given.
const isl = fs.readFileSync(new URL("../../src/island/island.ts", import.meta.url), "utf8");
const shelfDrop = isl.match(/private shelfDrop\(paths: string\[\]\) \{[\s\S]*?\n  \}\n/)[0];

test("a rejected shelf add logs a fixed line and nothing of what the rejection said", () => {
  const handler = shelfDrop.match(/\.catch\((\(\) => \{[\s\S]*?\n\s*\})\);/)?.[1];
  assert.ok(handler, "the shelf add has a catch");
  const logged = [];
  const fakeConsole = { warn: (...a) => logged.push(a) };
  const onRejected = vm.runInNewContext(`(${handler})`, { console: fakeConsole });
  onRejected(new Error("cannot read /Users/sam/Secret Plans/budget-2026.xlsx"));
  assert.deepEqual(logged, [["shelf add failed"]], "one fixed line, no path, name or id");
  assert.doesNotMatch(JSON.stringify(logged), /Secret Plans|budget-2026|\/Users\//);
});
