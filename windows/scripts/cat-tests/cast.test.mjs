import test from "node:test";
import assert from "node:assert/strict";
import { STATES } from "../../src/cat/base.ts";
import { CAT_IDS } from "../../src/cat/presets.ts";
import { DISPLAY_MODES } from "../../src/cat/display.ts";
import { PILL_ROW, busyRank, castOf } from "../../src/cat/cast.ts";
import { load, same } from "./util.mjs";

// Which cat appears where, replayed from tests/fixtures/cat/cast-cases.json (B-0) in all three modes, and the situations a JSON file cannot hold.
const fx = load("cast-cases.json");
const T = (id, state = "idle", last = 0) => ({ id, state, last });
const ISLAND = [T("integration_claude", "working", 100), T("agent_codex", "approval", 90), T("agent_gemini", "thinking", 80), T("agent_antigravity", "idle", 10), T("integration_stripe", "idle", 5), T("integration_music", "idle", 1)];
const IN = (o = {}) => ({ tasks: ISLAND, focusId: "integration_claude", mainCat: "ginger", pair: ["latte", "cloud"], agentCats: { agent_gemini: "oreo", agent_antigravity: "leo" }, ...o });
const catsOf = (c) => c.pills.map((p) => `${p.pill}:${p.cat}`);

test("the frozen values and the ranks of the states are the fixture's", () => {
  assert.deepEqual(fx.ids, [...CAT_IDS]);
  assert.deepEqual(fx.modes, [...DISPLAY_MODES]);
  assert.equal(fx.pillRow, PILL_ROW);
  assert.deepEqual(fx.states, [...STATES]);
  for (const r of fx.busyRank) assert.equal(busyRank(r.state), r.rank, r.state);
  assert.deepEqual(fx.busyRank.map((r) => r.rank), [3, 2, 2, 2, 0, 0, 1, 3, 3, 3, 3, 3]);
});

test("castOf replays every case of the fixture: the scenarios, the rankings and the hostile inputs, in all three modes and for unknown modes", () => {
  assert.ok(fx.cases.length >= 136);
  for (const c of fx.cases) same(castOf(c.mode, c.input), c.out, `${c.name} (${c.mode})`);
});

test("One cat: the Main cat in every place and nothing in the second spot; A cat for each agent: each agent pill in its own cat, integrations in the Main cat", () => {
  const one = castOf("one", IN());
  assert.deepEqual(one.big, { pill: "integration_claude", cat: "ginger" });
  assert.equal(one.second, null);
  assert.deepEqual(catsOf(one), ["agent_codex:ginger", "agent_gemini:ginger", "agent_antigravity:ginger", "integration_stripe:ginger"]);
  assert.deepEqual(one.greeting, { cat: "ginger", pair: null, sessions: ["ginger", "ginger", "ginger", "ginger"] });
  const per = castOf("perAgent", IN({ focusId: "agent_gemini" }));
  assert.deepEqual(per.big, { pill: "agent_gemini", cat: "oreo" });
  assert.deepEqual(catsOf(per), ["integration_claude:shrimpy", "agent_codex:momo", "agent_antigravity:leo", "integration_stripe:ginger"]);
  assert.equal(per.drop, "oreo");
  assert.deepEqual(per.greeting.sessions, ["shrimpy", "momo", "leo", "ginger"]);
  assert.deepEqual(castOf("perAgent", IN({ focusId: "integration_stripe" })).big, { pill: "integration_stripe", cat: "ginger" }, "an integration in focus: the Main cat");
  assert.equal(castOf("perAgent", IN({ focusId: "agent_unseen" })).big.cat, "ginger", "an agent with no coat yet wears the Main cat until it is given one");
});

test("Two cats: cat 1 is the focused pill in the pair's first coat, cat 2 the busiest other agent in the second, who leaves the row", () => {
  const two = castOf("two", IN());
  assert.deepEqual(two.big, { pill: "integration_claude", cat: "latte" });
  assert.deepEqual(two.second, { pill: "agent_codex", cat: "cloud" }, "Codex waits for approval");
  assert.deepEqual(catsOf(two), ["agent_gemini:ginger", "agent_antigravity:ginger", "integration_stripe:ginger", "integration_music:ginger"]);
  assert.equal(two.drop, "latte");
  assert.deepEqual(two.greeting.pair, ["latte", "cloud"]);
  assert.equal(castOf("two", IN({ pair: ["momo", "momo"] })).second.cat, "ginger", "the same coat twice: cat 2 is the next one");
  assert.deepEqual(castOf("two", { tasks: [T("integration_claude", "working", 1)], focusId: "integration_claude", mainCat: "ginger" }).second, { pill: null, cat: "momo" }, "no other agent: cat 2 idles, with no pill");
});

test("tasks that are not a list, pills that are not pill IDs, a time that is not a time and a state that is not a state never throw", () => {
  for (const mode of DISPLAY_MODES) for (const tasks of [null, undefined, 7, "x", [null, 7, "x", [], {}, { id: 7 }, { id: "Bad Id" }], [{ id: "agent_a", state: "bogus", last: NaN }, { id: "agent_a" }]]) {
    const c = castOf(mode, { tasks, focusId: null, mainCat: "tiger" });
    assert.ok(c.pills.length <= PILL_ROW && c.pills.every((p) => CAT_IDS.includes(p.cat)));
    assert.equal(c.big.cat, "shrimpy", "no Main cat that is a cat, and no pair: Shrimpy");
  }
  assert.equal(castOf("two", { tasks: [T("integration_claude"), { id: "agent_a", state: "bogus", last: NaN }], focusId: "integration_claude" }).second.pill, "agent_a");
  assert.equal(castOf("two", undefined).mode, "two");
  assert.equal(castOf("bogus", IN()).mode, "one");
});
