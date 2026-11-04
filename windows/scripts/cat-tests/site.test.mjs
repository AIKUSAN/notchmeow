import test from "node:test";
import assert from "node:assert/strict";
import { CAT_IDS, PRESETS } from "../../src/cat/presets.ts";
import { START, animates, dressing, pickCat, pickCoat } from "../../src/site/rules.ts";

test("the cats animate only while the tab is shown, they are on screen and the visitor has not asked for less motion", () => {
  for (const hidden of [false, true]) for (const inView of [false, true]) for (const reduced of [false, true]) {
    assert.equal(animates({ hidden, inView, reduced }), !hidden && inView && !reduced, JSON.stringify({ hidden, inView, reduced }));
  }
});

test("only a real true or false counts: text and numbers never turn the cats on", () => {
  assert.equal(animates({ hidden: "false", inView: true, reduced: false }), false);
  assert.equal(animates({ hidden: false, inView: 1, reduced: false }), false);
  assert.equal(animates({ hidden: false, inView: true, reduced: 0 }), false);
  assert.equal(animates({ hidden: false, inView: true, reduced: undefined }), false);
  assert.equal(animates({}), false);
});

test("the hero starts with Shrimpy on the left, picked, and Momo on the right", () => {
  assert.deepEqual(START, { coats: ["shrimpy", "momo"], picked: 0 });
});

test("pickCat takes 0 or 1 and nothing else", () => {
  assert.equal(pickCat(START, 1).picked, 1);
  assert.equal(pickCat(pickCat(START, 1), 0).picked, 0);
  for (const bad of [2, -1, 0.5, NaN, Infinity, "1", "0", null, undefined, [], {}, true]) assert.equal(pickCat(START, bad), START, String(bad));
});

test("a coat goes to the picked cat only, and the other keeps its own", () => {
  const left = pickCoat(START, "latte");
  assert.deepEqual(left.coats, ["latte", "momo"]);
  const right = pickCoat(pickCat(START, 1), "ginger");
  assert.deepEqual(right.coats, ["shrimpy", "ginger"]);
  assert.deepEqual(START, { coats: ["shrimpy", "momo"], picked: 0 }, "the start is never changed");
  assert.notEqual(left.coats, START.coats);
});

test("every one of the sixteen coats can be picked, and a coat that is not one changes nothing", () => {
  assert.equal(CAT_IDS.length, 16);
  for (const id of CAT_IDS) assert.equal(pickCoat(START, id).coats[0], id);
  for (const bad of ["", "Shrimpy", "shrimpy ", "nope", "__proto__", "constructor", "toString", "hasOwnProperty", 7, null, undefined, {}, ["momo"]]) assert.equal(pickCoat(START, bad), START, String(bad));
});

test("the line under the cats names the picked cat's coat and its side", () => {
  assert.equal(dressing(START), "Pick a coat for Shrimpy, the left cat.");
  assert.equal(dressing(pickCoat(pickCat(START, 1), "latte")), "Pick a coat for Latte, the right cat.");
  for (const id of CAT_IDS) assert.ok(dressing(pickCoat(START, id)).includes(PRESETS[id].label), id);
});
