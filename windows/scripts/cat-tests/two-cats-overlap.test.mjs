import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { bigCatPressed, catClickTarget } from "../../src/core/layout.ts";

// Two cats mode: a press in cat 2's part of the overlap with cat 1 drags nothing out of the notch. The numbers are the island's expanded overview: cat 1 (Ø58, circle 29) and cat 2 (Ø46,
// circle 23), 40 px apart.
const island = fs.readFileSync(new URL("../../src/island/island.ts", import.meta.url), "utf8");
const c1 = { cx: 50, cy: 101, r: 29 }, c2 = { cx: 90, cy: 109, r: 23 };

test("a press only cat 1 covers is on the big cat, and so is one in the overlap nearer cat 1", () => {
  assert.equal(bigCatPressed(30, 101, c1, c2), true);
  assert.equal(bigCatPressed(70, 104, c1, c2), true);
});

test("a press in the overlap nearer cat 2 is cat 2's: it is not on the big cat, so it drags nothing out of the notch", () => {
  assert.equal(catClickTarget(72, 105, c1, c2), 2);
  assert.equal(bigCatPressed(72, 105, c1, c2), false);
  assert.equal(bigCatPressed(72, 105, c1, null), true, "the old test (no second circle) took it for the big cat");
  assert.equal(bigCatPressed(105, 109, c1, c2), false, "a press only cat 2 covers is not the big cat either");
  assert.equal(bigCatPressed(200, 101, c1, c2), false);
});

test("without a second cat nothing differs from before", () => {
  for (const [x, y] of [[30, 101], [72, 105], [79, 101], [79.5, 101], [200, 101]]) assert.equal(bigCatPressed(x, y, c1, null), catClickTarget(x, y, c1, null) === 1, `${x},${y}`);
});

test("the island's press-start test is that rule, with cat 2's circle when a second cat is shown", () => {
  assert.match(island, /return bigCatPressed\(x, y, this\.botCircle\(\), this\.cast\.second\?\.pill \? this\.bot2Circle\(\) : null\);/);
  assert.doesNotMatch(island, /catClickTarget\(x, y, this\.botCircle\(\), null\)/);
  assert.match(island, /const hit = catClickTarget\(x, y, this\.botCircle\(\), second\?\.pill \? this\.bot2Circle\(\) : null\);/, "a click's own test is as it was");
});
