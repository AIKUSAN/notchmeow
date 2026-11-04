import test from "node:test";
import assert from "node:assert/strict";
import { rng } from "../../src/cat/base.ts";
import { CAT_IDS } from "../../src/cat/presets.ts";
import { PERSONAS, personaNamed } from "../../src/cat/personality.ts";
import { applyToAllCats, cleanCatSettings, defaultCatSettings, withCatCollar, withCatMotion, withCharacter, withCollar, withFurLines, withMotionStyle, withPersonality } from "../../src/cat/settings.ts";
import * as D from "../../src/cat/display.ts";
import { load, same } from "./util.mjs";

// The Display settings, replayed from tests/fixtures/cat/display-cases.json (B-0), and the cases a JSON file cannot hold.
const fx = load("display-cases.json");
const IDS = [...CAT_IDS];
const DEFAULTS = { displayMode: "one", pair: ["shrimpy", "momo"], agentCats: {} };
const deepFreeze = (v) => { if (v && typeof v === "object") { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };

test("the frozen values are the fixture's: three modes in Settings order, the default pair, the two default agent coats, the pill-ID shape", () => {
  assert.deepEqual([...D.DISPLAY_MODES], fx.modes);
  assert.deepEqual([...D.DISPLAY_MODES], ["one", "perAgent", "two"]);
  assert.deepEqual([...D.DEFAULT_PAIR], fx.defaultPair);
  assert.deepEqual({ ...D.DEFAULT_AGENT_CATS }, fx.defaultAgentCats);
  assert.equal(D.MAX_AGENT_CATS, fx.maxAgentCats);
  assert.equal(D.PILL_ID.source, fx.pillIdPattern);
  assert.deepEqual(fx.ids, IDS);
  same(D.defaultDisplaySettings(), fx.defaults, "defaults");
  assert.deepEqual(D.defaultDisplaySettings(), DEFAULTS);
});

test("cleanDisplaySettings, cleanPair, cleanAgentCats and the pill-ID rules replay every row of the fixture", () => {
  assert.ok(fx.cases.length >= 30 && fx.pairs.length >= 40 && fx.agentCats.length >= 21 && fx.pillIds.length >= 29);
  for (const c of fx.cases) same(D.cleanDisplaySettings(c.raw), c.out, c.name);
  for (const c of fx.pairs) same(D.cleanPair(c.raw), c.out, c.name);
  for (const c of fx.agentCats) same(D.cleanAgentCats(c.raw), c.out, c.name);
  for (const c of fx.pillIds) assert.deepEqual({ id: c.id, pill: D.isPillId(c.id), agent: D.isAgentPill(c.id), default: D.defaultAgentCat(c.id) }, c, JSON.stringify(c.id));
});

test("a value that is not there at all (undefined, NaN, a function, a symbol) is the default, and nothing throws", () => {
  for (const raw of [undefined, NaN, () => 1, Symbol("x"), 10n]) assert.deepEqual(D.cleanDisplaySettings(raw), DEFAULTS, String(typeof raw));
  assert.deepEqual(D.cleanDisplaySettings({ displayMode: undefined, pair: undefined, agentCats: undefined }), DEFAULTS);
  assert.deepEqual(D.cleanPair(NaN), ["shrimpy", "momo"]);
  assert.deepEqual(D.cleanPair([undefined, "momo"]), ["shrimpy", "momo"]);
  assert.deepEqual(D.cleanAgentCats({ agent_x: undefined, agent_y: NaN, agent_codex: undefined }), { agent_codex: "momo" });
  assert.equal(D.displayModeOf(Symbol("two")), "one");
});

test("the pill-ID check matches the whole string: a trailing newline or space is not a pill ID", () => {
  for (const bad of ["agent_x\n", "agent_x ", "agent_x\r\n", "\nagent_x", "agent_x "]) assert.equal(D.isPillId(bad), false, JSON.stringify(bad));
  assert.equal(D.isPillId("agent_x"), true);
  assert.equal(D.isPillId("a" + "b".repeat(63)), true);
  assert.equal(D.isPillId("a" + "b".repeat(64)), false);
});

test("a hostile map never pollutes a prototype and never throws, with __proto__ and constructor as keys", () => {
  const polluted = JSON.parse('{"__proto__":"momo","constructor":"momo","prototype":"momo","agent_ok":"ginger","toString":"momo"}');
  const out = D.cleanAgentCats(polluted);
  assert.deepEqual(out, { agent_ok: "ginger" });
  assert.equal(Object.getPrototypeOf(out), Object.prototype);
  assert.equal({}.agent_ok, undefined, "nothing reached Object.prototype");
  assert.deepEqual(D.cleanAgentCats(JSON.parse('{"__proto__":{"agent_x":"momo"},"agent_y":{"__proto__":"momo"}}')), {});
  assert.equal({}.agent_x, undefined);
});

test("the input is never changed, even when it is frozen; every call gives fresh objects", () => {
  const raw = deepFreeze({ displayMode: "two", pair: ["momo", "momo"], agentCats: { agent_x: "momo", integration_claude: "tiger" } });
  assert.doesNotThrow(() => D.cleanDisplaySettings(raw));
  assert.deepEqual(D.cleanDisplaySettings(raw), { displayMode: "two", pair: ["momo", "ginger"], agentCats: { agent_x: "momo", integration_claude: "shrimpy" } });
  assert.deepEqual(raw.pair, ["momo", "momo"]);
  const d = D.defaultDisplaySettings();
  d.pair[0] = "noodle"; d.agentCats.x = "momo";
  assert.deepEqual(D.defaultDisplaySettings(), DEFAULTS, "changing a result never changes the next one");
  assert.deepEqual(D.DEFAULT_PAIR, ["shrimpy", "momo"], "and never the frozen default");
});

test("3000 random display settings come out valid, and cleaning them again changes nothing", () => {
  const r = rng(2027), pool = ["one", "two", "perAgent", "Two", "", " ", "momo", "shrimpy", "tiger", "noodle", '["momo","ginger"]', '["momo"', "__proto__", "constructor", "agent_x", "agent_codex", "integration_claude", "ai_openai", "Agent_X", null, true, false, 0, 1, -1, 0.5, 7, [], ["momo"], ["momo", "ginger"], ["ginger", "ginger"], [1, 2], {}, { agent_x: "latte" }, { agent_codex: "tiger" }];
  const pick = () => pool[Math.floor(r() * pool.length)];
  const valid = (s) => D.DISPLAY_MODES.includes(s.displayMode) && s.pair.length === 2 && s.pair.every((c) => IDS.includes(c)) && s.pair[0] !== s.pair[1]
    && Object.entries(s.agentCats).every(([k, v]) => D.isPillId(k) && IDS.includes(v)) && JSON.stringify(Object.keys(s.agentCats)) === JSON.stringify(Object.keys(s.agentCats).sort());
  for (let i = 0; i < 3000; i++) {
    const map = r() < 0.15 ? pick() : Object.fromEntries(Array.from({ length: Math.floor(r() * 6) }, () => [pick(), pick()]).filter(([k]) => typeof k === "string"));
    const raw = { displayMode: pick(), pair: pick(), agentCats: map };
    const out = D.cleanDisplaySettings(raw);
    assert.ok(valid(out), JSON.stringify(raw));
    assert.deepEqual(D.cleanDisplaySettings(out), out);
  }
});

test("the whole block: the Cat settings, the Display settings and the desktop cat's are cleaned together, and a clean-up with the Cat settings alone would drop the display keys", () => {
  const raw = { character: "momo", motionStyle: "classic", collar: "band", furLines: true, cats: { momo: { motion: "playful" } }, displayMode: "two", pair: ["ginger", "latte"], agentCats: { agent_gemini: "oreo" } };
  const block = D.cleanCatBlock(raw);
  assert.deepEqual(Object.keys(block).sort(), ["agentCats", "cats", "character", "collar", "desktop", "displayMode", "furLines", "motionStyle", "outfit", "pair", "projectCats"]);
  assert.deepEqual(cleanCatSettings(raw), cleanCatSettings(block), "the Cat settings part is cleanCatSettings's, unchanged");
  assert.equal("displayMode" in cleanCatSettings(raw), false, "cleanCatSettings drops the display keys: that is why the block has a clean-up of its own");
  assert.deepEqual([block.displayMode, block.pair, block.agentCats], ["two", ["ginger", "latte"], { agent_gemini: "oreo" }]);
  assert.deepEqual(D.cleanCatBlock(block), block, "cleaning twice changes nothing");
  assert.deepEqual(D.cleanCatBlock(JSON.parse(JSON.stringify(block))), block, "it survives JSON");
  assert.deepEqual(D.cleanCatBlock(null), { ...defaultCatSettings(), ...DEFAULTS, desktop: { on: false, size: "medium", spots: {} }, outfit: "auto", projectCats: {} });
  assert.deepEqual(D.defaultCatBlock(), D.cleanCatBlock(5));
});

test("the Display rows edit one thing each and give back a whole clean block", () => {
  const b = D.defaultCatBlock();
  assert.equal(D.withDisplayMode(b, "two").displayMode, "two");
  assert.equal(D.withDisplayMode(b, "Two").displayMode, "one", "an unknown mode is One cat");
  assert.deepEqual(D.withPair(b, 1, "noodle").pair, ["shrimpy", "noodle"]);
  assert.deepEqual(D.withPair(b, 0, "ginger").pair, ["ginger", "momo"]);
  assert.deepEqual(D.withPair(b, 1, "shrimpy").pair, ["shrimpy", "momo"], "the same coat twice: cat 2 is the next one");
  assert.deepEqual(D.withPair(b, 0, "momo").pair, ["momo", "ginger"], "and when cat 1 takes cat 2's coat, cat 2 moves on");
  assert.deepEqual(D.withPair(b, 0, "tiger").pair, ["shrimpy", "momo"], "an unknown coat is Shrimpy");
  assert.deepEqual(D.withAgentCat(b, "agent_gemini", "oreo").agentCats, { agent_gemini: "oreo" });
  assert.deepEqual(D.withAgentCat(D.withAgentCat(b, "agent_gemini", "oreo"), "agent_gemini", "tiger").agentCats, {}, "a bad coat for an agent with no default drops the pill");
  assert.deepEqual(D.withAgentCat(b, "__proto__", "oreo").agentCats, {});
  assert.deepEqual(D.withAgentCats(b, { agent_x: "snow", Bad: "momo" }).agentCats, { agent_x: "snow" });
  for (const edit of [D.withDisplayMode(b, "perAgent"), D.withPair(b, 0, "latte"), D.withAgentCat(b, "agent_x", "snow")]) {
    assert.deepEqual(Object.keys(edit).sort(), Object.keys(b).sort(), "all nine keys");
    assert.deepEqual(edit.cats, b.cats, "the Cat settings are untouched");
  }
  assert.deepEqual(b, D.defaultCatBlock(), "the input is not changed");
});

test("a Cat settings row edit keeps the display keys when it is put into the block, and a Display edit keeps the Cat settings: what the Settings window saves", () => {
  const start = D.withAgentCat(D.withPair(D.withDisplayMode(D.defaultCatBlock(), "two"), 1, "noodle"), "agent_x", "snow");
  const edits = [withCharacter(start, "momo"), withMotionStyle(start, "classic"), withCollar(start, "band"), withFurLines(start, true), withCatMotion(start, "momo", "classic"),
    withCatCollar(start, "momo", "off"), withPersonality(start, "momo", personaNamed("chill")), applyToAllCats(start, "momo")];
  assert.ok("chill" in PERSONAS);
  for (const edit of edits) {
    assert.equal("displayMode" in edit, false, "the Cat settings edits return the Cat settings alone: put as they are, they would drop the display keys");
    const put = D.withCatSettings(start, edit);
    assert.deepEqual([put.displayMode, put.pair, put.agentCats], ["two", ["shrimpy", "noodle"], { agent_x: "snow" }]);
    assert.deepEqual(cleanCatSettings(put), cleanCatSettings(edit), "and the Cat settings are the edit's");
  }
  const shown = D.withDisplayMode(D.cleanCatBlock({ character: "momo", collar: "band" }), "perAgent");
  assert.deepEqual([shown.character, shown.collar, shown.displayMode], ["momo", "band", "perAgent"]);
  assert.deepEqual(D.withCatSettings(shown, shown), shown, "a whole block put into the block is itself");
});
