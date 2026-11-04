import test from "node:test";
import assert from "node:assert/strict";
import { rng } from "../../src/cat/base.ts";
import { PERSONAS, TRAIT_KEYS, personaNamed, slide } from "../../src/cat/personality.ts";
import { CAT_IDS } from "../../src/cat/presets.ts";
import * as S from "../../src/cat/settings.ts";
import { load, same } from "./util.mjs";

// The stored settings, replayed from tests/fixtures/cat/settings-cases.json (A-0d), and the cases a JSON file cannot hold.
const fx = load("settings-cases.json");
const IDS = [...CAT_IDS];
const BALANCED = { preset: "balanced", energy: 0.5, curiosity: 0.5, chatty: 0.5, affection: 0.5, sass: 0.5, mischief: 0.5 };
const deepFreeze = (v) => { if (v && typeof v === "object") { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };

test("the frozen words and the cat IDs are the fixture's", () => {
  assert.deepEqual(IDS, fx.ids);
  assert.equal(S.FOLLOW, fx.follow);
  assert.deepEqual([...S.MOTION_STYLES], fx.motionStyles);
  assert.deepEqual([...S.COLLAR_STYLES], fx.collarStyles);
  assert.deepEqual(IDS.slice(0, 2), ["shrimpy", "momo"]);
  assert.ok(!S.MOTION_STYLES.includes("follow") && !S.COLLAR_STYLES.includes("follow"), "follow is an override, never a style");
});

test("a fresh install is the fixture's: Shrimpy, Playful, collar off, no fur lines, 16 cats that follow the globals and are Balanced", () => {
  same(S.defaultCatSettings(), fx.defaults, "defaults");
  const d = S.defaultCatSettings();
  assert.deepEqual([d.character, d.motionStyle, d.collar, d.furLines], ["shrimpy", "playful", "off", false]);
  assert.deepEqual(Object.keys(d.cats), IDS);
  for (const id of IDS) assert.deepEqual(d.cats[id], { motion: "follow", collar: "follow", personality: BALANCED }, id);
  assert.notEqual(S.defaultCatSettings().cats.momo, d.cats.momo, "every call gives fresh objects");
});

test("cleanCatSettings replays every case of the fixture: bad JSON, wrong types, unknown IDs, a valid value", () => {
  assert.ok(fx.cases.length >= 37);
  for (const c of fx.cases) same(S.cleanCatSettings(c.raw), c.out, c.name);
});

test("cleanPersonality replays every case of the fixture: objects and JSON text, presets, Custom, out-of-range traits", () => {
  assert.ok(fx.personalities.length >= 47);
  for (const c of fx.personalities) same(S.cleanPersonality(c.raw), c.out, c.name);
});

test("applyToAllCats, motionFor, collarFor and engineCfg replay the fixture", () => {
  for (const c of fx.applyAll) same(S.applyToAllCats(c.settings, c.from), c.out, c.name);
  for (const c of fx.derived) {
    same(S.engineCfg(c.settings), c.engineCfg, `${c.name}: engineCfg`);
    assert.deepEqual(IDS.map((id) => S.motionFor(c.settings, id)), c.motionFor, `${c.name}: motionFor`);
    assert.deepEqual(IDS.map((id) => S.collarFor(c.settings, id)), c.collarFor, `${c.name}: collarFor`);
  }
});

test("a real NaN, an infinity or minus zero in a trait counts as 0.5, 0 or 1, never as NaN (a JSON file cannot hold them: the fixture's port note)", () => {
  const wild = S.cleanPersonality({ energy: NaN, curiosity: Infinity, chatty: -Infinity, affection: 7, sass: -2, mischief: -0 });
  assert.deepEqual([wild.energy, wild.curiosity, wild.chatty, wild.affection, wild.sass, wild.mischief], [0.5, 0.5, 0.5, 1, 0, 0]);
  assert.equal(Object.is(wild.mischief, -0), false, "minus zero is stored as 0");
  assert.equal(wild.preset, "custom");
  const out = S.cleanCatSettings({ cats: { momo: { personality: { energy: NaN, sass: NaN } } } });
  for (const v of TRAIT_KEYS.map((k) => out.cats.momo.personality[k])) assert.ok(Number.isFinite(v));
});

test("Custom is the word custom with the six traits: a slider move stays Custom, even back on a preset's numbers", () => {
  const moved = slide(personaNamed("chill"), "sass", 0.9);
  assert.equal(moved.preset, "custom");
  assert.deepEqual(S.cleanPersonality(moved), moved);
  assert.deepEqual(S.cleanPersonality(JSON.stringify(moved)), moved, "the Mac stores JSON text; so can a file");
  const back = slide(personaNamed("chill"), "energy", 0.12);
  assert.equal(S.cleanPersonality(back).preset, "custom");
  assert.ok(!("custom" in PERSONAS), "custom is not one of the six presets");
  for (const name of Object.keys(PERSONAS)) assert.deepEqual(S.cleanPersonality(personaNamed(name)), personaNamed(name), name);
});

test("a stored word that no longer exists is the neutral one: Shrimpy, Playful, Off for the globals, follow for a cat's own override", () => {
  for (const bad of ["tiger", "Momo", " momo", "", "siamese", "__proto__", "constructor", "toString", null, undefined, 7, true, {}, ["momo"]]) assert.equal(S.catIdOf(bad), "shrimpy", String(bad));
  for (const bad of ["follow", "Classic", "bogus", "", null, 7, ["classic"]]) assert.equal(S.motionStyleOf(bad), "playful", String(bad));
  for (const bad of ["follow", "scarf", "Tag", "", null, 7, ["band"]]) assert.equal(S.collarStyleOf(bad), "off", String(bad));
  for (const bad of ["Classic", "bogus", "", null, 7, {}]) assert.equal(S.motionOverrideOf(bad), "follow", String(bad));
  for (const bad of ["scarf", "Tag", "", null, 7, {}]) assert.equal(S.collarOverrideOf(bad), "follow", String(bad));
  assert.equal(S.collarOverrideOf("off"), "off", "off is a real override");
  assert.equal(S.motionOverrideOf("follow"), "follow");
});

test("fur lines are on only for a real boolean true", () => {
  assert.equal(S.cleanCatSettings({ furLines: true }).furLines, true);
  for (const bad of [false, 1, 0, "true", "yes", null, [true], { value: true }, 7]) assert.equal(S.cleanCatSettings({ furLines: bad }).furLines, false, JSON.stringify(bad));
});

test("hostile values never throw: 600 random settings come out valid, cleaning them again changes nothing, and the input is left alone", () => {
  const r = rng(2026), pool = ["momo", "tiger", "classic", "playful", "follow", "off", "band", "tag", "kerchief", "", " ", "chill", "custom", "{", "{\"energy\":2}",
    "{\"preset\":\"sweet\",\"affection\":1,\"energy\":0.5,\"curiosity\":0.55,\"chatty\":0.55,\"sass\":0.1,\"mischief\":0.3}", "__proto__", "constructor", null, true, false, 0, 1, -1, 0.5, 7, 1e300, NaN, Infinity,
    [], [1], {}, { energy: 9 }, { preset: "hyper" }];
  const pick = () => pool[Math.floor(r() * pool.length)];
  const entry = () => ({ motion: pick(), collar: pick(), personality: pick() });
  const valid = (s) => IDS.includes(s.character) && S.MOTION_STYLES.includes(s.motionStyle) && S.COLLAR_STYLES.includes(s.collar) && typeof s.furLines === "boolean"
    && JSON.stringify(Object.keys(s.cats)) === JSON.stringify(IDS)
    && IDS.every((id) => ["follow", ...S.MOTION_STYLES].includes(s.cats[id].motion) && ["follow", ...S.COLLAR_STYLES].includes(s.cats[id].collar)
      && TRAIT_KEYS.every((k) => Number.isFinite(s.cats[id].personality[k]) && s.cats[id].personality[k] >= 0 && s.cats[id].personality[k] <= 1)
      && (s.cats[id].personality.preset === "custom" || Object.hasOwn(PERSONAS, s.cats[id].personality.preset)));
  for (let i = 0; i < 600; i++) {
    const raw = { character: pick(), motionStyle: pick(), collar: pick(), furLines: pick(), cats: r() < 0.1 ? pick() : Object.fromEntries(IDS.filter(() => r() < 0.5).map((id) => [id, r() < 0.1 ? pick() : entry()])) };
    const out = S.cleanCatSettings(deepFreeze(structuredClone(raw)));
    assert.ok(valid(out), JSON.stringify(raw));
    assert.deepEqual(S.cleanCatSettings(out), out);
    assert.ok(valid(S.applyToAllCats(raw, pick())));
    assert.doesNotThrow(() => S.engineCfg(raw));
  }
  const evil = JSON.parse('{"__proto__":{"motion":"classic"},"constructor":{"prototype":{"x":1}},"cats":{"__proto__":{"motion":"classic"},"constructor":{"motion":"classic"}}}');
  const out = S.cleanCatSettings(evil);
  assert.equal(Object.getPrototypeOf(out.cats), Object.prototype);
  assert.deepEqual(Object.keys(out.cats), IDS);
  assert.equal(({}).motion, undefined, "nothing leaked into Object.prototype");
});

test("applyToAllCats copies one cat's motion override, collar override and personality to all 16, and nothing else", () => {
  const s = S.cleanCatSettings({ character: "momo", motionStyle: "classic", collar: "band", furLines: true, cats: { ginger: { motion: "playful", collar: "off", personality: personaNamed("hyper") } } });
  const before = JSON.stringify(s);
  const out = S.applyToAllCats(s, "ginger");
  assert.equal(JSON.stringify(s), before, "the input is not touched");
  assert.deepEqual([out.character, out.motionStyle, out.collar, out.furLines], ["momo", "classic", "band", true]);
  for (const id of IDS) assert.deepEqual(out.cats[id], { motion: "playful", collar: "off", personality: personaNamed("hyper") }, id);
  out.cats.momo.personality.energy = 0.01;
  assert.equal(out.cats.ginger.personality.energy, 1, "no two cats share one personality object");
  assert.equal(S.applyToAllCats(s, "shrimpy").cats.noodle.motion, "follow", "follow is copied as follow");
  assert.deepEqual(S.applyToAllCats(s, "tiger"), S.applyToAllCats(s, "shrimpy"), "an unknown cat is Shrimpy");
});

test("applyCatSettings fills the shared config in place: style, overrides, personalities, the character, its collar and the fur lines", () => {
  const cfg = { motion: "playful", override: {}, pers: {}, zoomAfter: 300000 };
  const keep = cfg;
  const raw = { character: "momo", motionStyle: "classic", collar: "band", furLines: true, cats: { momo: { motion: "playful", collar: "kerchief", personality: personaNamed("sweet") }, ginger: { collar: "tag" } } };
  const s = S.applyCatSettings(cfg, raw);
  assert.equal(cfg, keep, "the same object: engines hold a reference to it");
  assert.equal(cfg.zoomAfter, 300000, "what Settings does not own stays");
  assert.deepEqual([cfg.motion, cfg.character, cfg.collar, cfg.fur], ["classic", "momo", "kerchief", true]);
  assert.deepEqual(cfg.override, { momo: "playful" });
  assert.deepEqual(Object.keys(cfg.pers), IDS);
  assert.deepEqual(cfg.pers.momo, personaNamed("sweet"));
  assert.deepEqual(s, S.cleanCatSettings(raw), "it returns the clean settings");
  S.applyCatSettings(cfg, "junk");
  assert.deepEqual([cfg.motion, cfg.character, cfg.collar, cfg.fur, cfg.override], ["playful", "shrimpy", "off", false, {}], "junk is the defaults");
});
