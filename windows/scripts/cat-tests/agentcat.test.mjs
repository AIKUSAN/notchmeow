import test from "node:test";
import assert from "node:assert/strict";
import { rng } from "../../src/cat/base.ts";
import { CAT_IDS } from "../../src/cat/presets.ts";
import { assignAgentCats, agentCatFor, pickCat, rerollAgentCat } from "../../src/cat/agentcat.ts";
import { cleanAgentCats, defaultAgentCat } from "../../src/cat/display.ts";
import { load, same } from "./util.mjs";

// Giving agents their cats, replayed from tests/fixtures/cat/agent-cat-cases.json (B-0): the same rows, the same random source, the same number of draws.
const fx = load("agent-cat-cases.json");
const IDS = [...CAT_IDS];
const OTHER = IDS.slice(2); // ginger ... noodle: the 14 coats that are neither Claude Code's nor Codex's default
const counted = (seed) => { const r = rng(seed), f = () => { f.n++; return r(); }; f.n = 0; return f; };
const fixed = (v) => { const f = () => { f.n++; return v; }; f.n = 0; return f; };
const noRand = () => { throw new Error("rand() must not be called here"); };
const deepFreeze = (v) => { if (v && typeof v === "object") { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };
/** The random source of a row: {seed} is rng(seed), {values} those numbers in order and then 0, {none} must never be called. */
const source = (spec) => {
  const seeded = spec.seed !== undefined ? rng(spec.seed) : null;
  const f = () => { f.draws++; if (seeded) return seeded(); if (spec.values) return f.draws <= spec.values.length ? spec.values[f.draws - 1] : 0; throw new Error("rand() must not be called"); };
  f.draws = 0;
  return f;
};

test("agentCatFor, rerollAgentCat and assignAgentCats replay every row of the fixture, with the same number of random draws", () => {
  assert.deepEqual(fx.ids, IDS);
  assert.deepEqual(fx.defaults, { integration_claude: "shrimpy", agent_codex: "momo" });
  assert.ok(fx.cases.length >= 34 && fx.rerolls.length >= 11 && fx.assigns.length >= 6);
  for (const c of fx.cases) { const r = source(c.rand); same(agentCatFor(c.pill, c.agentCats, c.mainCat, r), c.out, c.name); assert.equal(r.draws, c.draws, c.name); }
  for (const c of fx.rerolls) { const r = source(c.rand); same(rerollAgentCat(c.pill, c.agentCats, c.mainCat, r), c.out, c.name); assert.equal(r.draws, c.draws, c.name); }
  for (const c of fx.assigns) { const r = source(c.rand); same({ agentCats: assignAgentCats(c.pills, c.agentCats, c.mainCat, r) }, c.out, c.name); assert.equal(r.draws, c.draws, c.name); }
});

test("Claude Code is Shrimpy and Codex is Momo, with no random number and nothing to store; a stored coat wins over the default", () => {
  for (const [pill, cat] of [["integration_claude", "shrimpy"], ["agent_codex", "momo"]]) assert.deepEqual(agentCatFor(pill, {}, "ginger", noRand), { cat, agentCats: {}, assigned: false }, pill);
  const map = { integration_claude: "oreo", agent_codex: "blue", agent_gemini: "latte" };
  for (const [pill, cat] of [["integration_claude", "oreo"], ["agent_codex", "blue"], ["agent_gemini", "latte"]]) assert.deepEqual(agentCatFor(pill, map, "momo", noRand), { cat, agentCats: map, assigned: false }, pill);
});

test("a pill that is not an agent gets the Main cat and is never stored; a Main cat that is not a cat is Shrimpy", () => {
  for (const pill of ["integration_stripe", "ai_openai", "agent_", "agent", "Agent_x", "__proto__", "constructor", "", null, undefined, 7, {}, ["agent_x"]]) {
    assert.deepEqual(agentCatFor(pill, { agent_y: "momo" }, "cloud", noRand), { cat: "cloud", agentCats: { agent_y: "momo" }, assigned: false }, String(pill));
  }
  assert.equal(agentCatFor("integration_stripe", {}, "tiger", noRand).cat, "shrimpy");
});

test("a new agent gets a coat that no other agent and not the Main cat uses, with one random number, keeps it, and is never given another one", () => {
  for (let seed = 1; seed <= 200; seed++) {
    const rand = counted(seed), map = { agent_a: "blue", agent_b: "ginger" }, out = agentCatFor("agent_new", map, "cloud", rand);
    assert.ok(!["shrimpy", "momo", "blue", "ginger", "cloud"].includes(out.cat), `${seed}: ${out.cat}`);
    assert.equal(out.assigned, true);
    assert.equal(rand.n, 1);
    assert.deepEqual(out.agentCats, { agent_a: "blue", agent_b: "ginger", agent_new: out.cat });
    assert.deepEqual(agentCatFor("agent_new", out.agentCats, "cloud", noRand), { cat: out.cat, agentCats: out.agentCats, assigned: false }, "the second time it only reads");
    assert.deepEqual(map, { agent_a: "blue", agent_b: "ginger" }, "the input is not changed");
  }
  const seen = new Set();
  for (let seed = 1; seed <= 400; seed++) seen.add(agentCatFor("agent_x", {}, "shrimpy", rng(seed)).cat);
  assert.deepEqual([...seen].sort(), [...OTHER].sort(), "every one of the 14 free coats comes up");
});

test("when all 16 coats are taken, the least-used one is chosen, ties in CAT_IDS order, and no random number is drawn", () => {
  const agents = (coats) => Object.fromEntries(coats.map((c, i) => ["agent_a" + String(i).padStart(2, "0"), c]));
  const once = agents(OTHER.slice(0, 13));
  const rand = counted(5);
  assert.deepEqual(agentCatFor("agent_new", once, "noodle", rand), { cat: "shrimpy", agentCats: { ...once, agent_new: "shrimpy" }, assigned: true });
  assert.equal(rand.n, 0);
  assert.equal(agentCatFor("agent_new", agents(OTHER), "shrimpy", noRand).cat, "momo", "Shrimpy is also the Main cat: used twice, so Momo");
  const dup = { ...agents(OTHER), ...Object.fromEntries(IDS.filter((c) => c !== "leo").map((c) => ["agent_d_" + c, c])) };
  assert.equal(agentCatFor("agent_new", dup, "shrimpy", noRand).cat, "leo", "every coat but Leo is used at least twice");
});

test("a default coat that a stored coat has replaced is free again, and the dice never gives the same coat back", () => {
  const map = { integration_claude: "oreo", agent_codex: "ginger" };
  assert.equal(agentCatFor("agent_x", map, "midnight", fixed(0)).cat, "shrimpy");
  assert.equal(agentCatFor("agent_x", {}, "midnight", fixed(0)).cat, "ginger", "with both defaults in force, they are taken");
  for (let seed = 1; seed <= 200; seed++) {
    const out = rerollAgentCat("agent_a", { agent_a: "blue", agent_b: "snow" }, "cloud", counted(seed));
    assert.ok(out.cat !== "blue" && !["shrimpy", "momo", "snow", "cloud"].includes(out.cat), `${seed}: ${out.cat}`);
    assert.deepEqual(out.agentCats, { agent_a: out.cat, agent_b: "snow" });
  }
  assert.deepEqual(rerollAgentCat("integration_claude", {}, "cloud", fixed(0)), { cat: "ginger", agentCats: { integration_claude: "ginger" } }, "Claude Code: not Shrimpy again, and Momo and Cloud are taken");
  assert.deepEqual(rerollAgentCat("integration_stripe", { agent_y: "momo" }, "cloud", noRand), { cat: "cloud", agentCats: { agent_y: "momo" } });
});

test("a random source that misbehaves never breaks it: no function, NaN, a number out of range or text all pick a free coat; 1 is the last one", () => {
  for (const rand of [undefined, null, "x", 7, () => NaN, () => Infinity, () => -3, () => 2, () => "0.5", () => undefined, () => 1]) assert.ok(OTHER.includes(agentCatFor("agent_x", {}, "shrimpy", rand).cat), String(rand));
  assert.equal(agentCatFor("agent_x", {}, "shrimpy", () => 1).cat, "noodle");
  assert.equal(agentCatFor("agent_x", {}, "shrimpy", () => -3).cat, "ginger");
  assert.equal(pickCat(["shrimpy"], () => 0.9999999, "noodle"), "puff", "a coat to avoid is never chosen");
});

test("hostile maps and Main cats never throw and never change their input; a frozen map is fine", () => {
  for (const map of [null, undefined, "x", 7, [], ["momo"], JSON.parse('{"__proto__":"momo","constructor":"momo","agent_ok":"tiger"}')]) {
    const out = agentCatFor("agent_x", map, undefined, fixed(0));
    assert.ok(IDS.includes(out.cat) && out.assigned === true);
    assert.deepEqual(Object.keys(out.agentCats), ["agent_x"]);
  }
  assert.doesNotThrow(() => agentCatFor("agent_x", deepFreeze({ agent_y: "momo" }), "momo", fixed(0)));
  assert.equal({}.agent_x, undefined);
});

test("assignAgentCats gives every agent in the list a coat, in order, skips integrations and repeats, and Reset to defaults is it with an empty map", () => {
  const pills = ["agent_codex", "agent_gemini", "integration_stripe", "agent_cursor", "agent_gemini", "integration_claude", "ai_openai", "Bad Id", "agent_gemini"];
  const out = assignAgentCats(pills, {}, "cloud", rng(3));
  assert.deepEqual(Object.keys(out), ["agent_cursor", "agent_gemini"], "the defaults are not stored, integrations and bad IDs are skipped");
  assert.deepEqual(assignAgentCats(pills, {}, "cloud", rng(3)), out, "repeatable");
  assert.deepEqual(assignAgentCats(pills, out, "cloud", noRand), out, "a second pass changes nothing and draws nothing");
  assert.deepEqual(assignAgentCats(null, { agent_x: "momo" }, "cloud", noRand), { agent_x: "momo" });
  const before = { integration_claude: "oreo", agent_codex: "blue", agent_gemini: "latte" };
  const after = assignAgentCats(["integration_claude", "agent_codex", "agent_gemini"], {}, "shrimpy", rng(4));
  assert.deepEqual(Object.keys(after), ["agent_gemini"]);
  assert.ok(!["shrimpy", "momo"].includes(after.agent_gemini));
  assert.notDeepEqual(after, before);
  assert.equal(defaultAgentCat("integration_claude"), "shrimpy");
});

test("3000 random calls give a valid coat and a clean map", () => {
  const r = rng(31337), pool = ["agent_a", "agent_b", "agent_codex", "integration_claude", "integration_stripe", "ai_openai", "Bad", "__proto__", "constructor", "", null, 7, "agent_", "agent_x"];
  for (let i = 0; i < 3000; i++) {
    const map = Object.fromEntries(Array.from({ length: Math.floor(r() * 8) }, () => [pool[Math.floor(r() * pool.length)], r() < 0.7 ? IDS[Math.floor(r() * 16)] : pool[Math.floor(r() * pool.length)]]).filter(([k]) => typeof k === "string"));
    const pill = pool[Math.floor(r() * pool.length)], main = r() < 0.8 ? IDS[Math.floor(r() * 16)] : pool[Math.floor(r() * pool.length)];
    for (const fn of [agentCatFor, rerollAgentCat]) {
      const out = fn(pill, map, main, rng(i));
      assert.ok(IDS.includes(out.cat), JSON.stringify({ pill, map, main }));
      assert.deepEqual(cleanAgentCats(out.agentCats), out.agentCats);
    }
  }
});
