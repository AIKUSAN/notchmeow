import test from "node:test";
import assert from "node:assert/strict";
import { PERSONAS, TRAITS, TRAIT_KEYS, normPers, persMultipliers, personaNamed, slide } from "../../src/cat/personality.ts";
import { finite, load, same } from "./util.mjs";

const fx = load("personality-cases.json");

test("the six presets and the six trait labels are the fixture's", () => {
  same(PERSONAS, fx.presets, "presets");
  same(TRAITS.map(([key, label, low, high]) => ({ key, label, low, high })), fx.traits, "traits");
  assert.deepEqual(Object.keys(PERSONAS), ["balanced", "chill", "grumpy", "sweet", "hyper", "chatty"]);
});

test("traits to multipliers and idle habits, thresholds and hand-edited values included, are the fixture's", () => {
  for (const c of fx.cases) same(persMultipliers(c.traits), c.out, c.name);
});

test("Balanced changes nothing", () => {
  const m = persMultipliers(PERSONAS.balanced);
  assert.deepEqual([m.speed, m.hop, m.blinkEvery, m.gaze, m.earFlickEvery, m.chatter, m.slowBlinkEvery], [1, 1, 1, 1, 1, 1, 1]);
  assert.deepEqual([m.pupil, m.smile, m.skew, m.blush, m.lid, m.earBack], [0, 0, 0, 0, 0, 0]);
  assert.deepEqual(Object.values(m.idle), [false, false, false, false, false, false]);
  assert.equal(m.poke, "annoyed");
});

test("moving a slider makes the preset Custom, an unknown preset is Balanced, nothing throws", () => {
  for (const c of fx.slide) same(slide(personaNamed(c.from), c.trait, c.value), c.out, `${c.from} ${c.trait}`);
  assert.equal(personaNamed("nonsense").preset, "balanced");
  assert.equal(personaNamed("toString").preset, "balanced");
  assert.equal(slide(personaNamed("chill"), "sass", NaN).preset, "chill");
});

test("a hand-edited personality is held to 0..1: missing counts as 0.5, wrong types too, nothing is NaN", () => {
  assert.deepEqual(normPers({}), { energy: 0.5, curiosity: 0.5, chatty: 0.5, affection: 0.5, sass: 0.5, mischief: 0.5 });
  assert.deepEqual(normPers(null), normPers(undefined));
  const bad = normPers({ energy: "high", curiosity: null, chatty: true, affection: [1], sass: {}, mischief: "0.9" });
  assert.deepEqual(Object.values(bad), [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]);
  assert.equal(normPers({ energy: 7 }).energy, 1);
  assert.equal(normPers({ energy: -7 }).energy, 0);
  assert.equal(normPers({ energy: NaN }).energy, 0.5);
  for (const t of [{ energy: -9, sass: 99 }, null, { chatty: Infinity }]) finite(persMultipliers(t), "multipliers");
  assert.deepEqual([...TRAIT_KEYS], ["energy", "curiosity", "chatty", "affection", "sass", "mischief"]);
});
