import test from "node:test";
import assert from "node:assert/strict";
import { PRESETS, CAT_IDS, DEFAULT_CAT, catById, kittenOf } from "../../src/cat/presets.ts";
import { load, same } from "./util.mjs";

const fx = load("presets.json");

test("the cat ids are the frozen contract values, Shrimpy first and Momo second", () => {
  assert.deepEqual([...CAT_IDS], fx.ids);
  assert.deepEqual([...CAT_IDS].slice(0, 2), ["shrimpy", "momo"]);
  assert.equal(CAT_IDS.length, 16);
  assert.equal(DEFAULT_CAT, "shrimpy");
  assert.deepEqual(Object.keys(PRESETS).sort(), [...fx.ids].sort(), "no coat without an id, no id without a coat");
});

test("every coat is exactly the fixture's, voice included", () => {
  for (const id of fx.ids) same(PRESETS[id], fx.cats[id], `cat ${id}`);
  assert.equal(PRESETS.shrimpy.voice, -1);
  assert.equal(PRESETS.momo.voice, 1);
  assert.equal(PRESETS.ginger.voice, 0);
});

test("every kitten is exactly the fixture's, voice +3", () => {
  for (const id of fx.ids) {
    same(kittenOf(PRESETS[id]), fx.kittens[id], `kitten ${id}`);
    assert.equal(kittenOf(PRESETS[id]).voice, 3);
    assert.equal(kittenOf(PRESETS[id]).base, id);
  }
});

test("kittenOf copies: the parent is not changed", () => {
  const before = JSON.stringify(PRESETS.shrimpy);
  const k = kittenOf(PRESETS.shrimpy);
  k.ear.h = 99;
  assert.equal(JSON.stringify(PRESETS.shrimpy), before);
});

test("an unknown stored id, or anything that is not a string, is Shrimpy; it never throws", () => {
  for (const bad of ["", "nope", "toString", "__proto__", "SHRIMPY", null, undefined, 3, {}, []]) {
    assert.equal(catById(bad), PRESETS.shrimpy, String(bad));
  }
  assert.equal(catById("momo"), PRESETS.momo);
  assert.equal(catById("noodle").name, "noodle");
});
