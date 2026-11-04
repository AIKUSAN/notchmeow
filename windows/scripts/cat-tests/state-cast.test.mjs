import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { rng } from "../../src/cat/base.ts";
import { cleanCatBlock, defaultCatBlock } from "../../src/cat/display.ts";
import { State } from "../../src/core/state.ts";

// What State adds for the display modes: a last-event time for every pill, the cast of the chosen mode, and the agents' coats given the first time they are seen.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const fresh = (cat = {}, ids = []) => {
  State.settings = { ...State.settings, cat: cleanCatBlock(cat), activeIntegrations: ["integration_stripe"] };
  State.tasks = [];
  State.focusId = null;
  State.rand = rng(11);
  State.persistSettings = null;
  State.loadIntegrationTasks();
  for (const [id, name] of ids) State.upsertExternalAgent(id, name, "#8AB4F8");
  State.persistSettings = null;
};
const ids = (list) => list.map((t) => t.id);

test("every hook event is its pill's last event: noteEvent stamps that pill and ignores an ID that has none", () => {
  fresh({}, [["agent_gemini", "gemini"]]);
  assert.equal(State.tasks.find((t) => t.id === "agent_gemini").last, undefined, "no event yet");
  State.noteEvent("agent_gemini", 1234);
  State.noteEvent("integration_claude", 99);
  State.noteEvent("agent_unknown", 5);
  assert.deepEqual(State.tasks.map((t) => [t.id, t.last]).filter(([, l]) => l !== undefined), [["integration_claude", 99], ["agent_gemini", 1234]]);
  const before = performance.now();
  State.noteEvent("agent_gemini");
  assert.ok(State.tasks.find((t) => t.id === "agent_gemini").last >= before, "the default time is now");
  assert.match(source("island/hooks.ts"), /default:\s*break;\s*\}\s*State\.noteEvent\(agentId\);\s*State\.notify\(\);/, "hooks.ts stamps the pill after every event it handles");
});

test("the cast follows the settings, the pills and the focus: One cat is the Main cat everywhere, Two cats the pair with the busiest other agent", () => {
  fresh({ character: "ginger", displayMode: "one" }, [["agent_gemini", "gemini"], ["agent_antigravity", "antigravity"]]);
  State.updateTask("agent_antigravity", "approval");
  State.noteEvent("agent_gemini", 10);
  State.noteEvent("agent_antigravity", 5);
  let c = State.cast;
  assert.deepEqual([c.mode, c.big, c.second], ["one", { pill: "integration_claude", cat: "ginger" }, null]);
  assert.deepEqual(c.pills.map((p) => p.cat), ["ginger", "ginger", "ginger"], "the three other pills, all in the Main cat");
  State.settings.cat = { ...State.settings.cat, displayMode: "two", pair: ["latte", "cloud"] };
  c = State.cast;
  assert.deepEqual(c.big, { pill: "integration_claude", cat: "latte" });
  assert.deepEqual(c.second, { pill: "agent_antigravity", cat: "cloud" }, "a waiting approval beats a more recent event");
  assert.ok(!ids(State.pillRow.map((r) => r.task)).includes("agent_antigravity"), "the second agent leaves the row");
  State.setFocus("agent_gemini");
  assert.deepEqual(State.cast.big, { pill: "agent_gemini", cat: "latte" }, "focus moves the big cat");
});

test("pillRow is otherTasks.slice(0, 4) in One cat mode, whatever the pills, so the island's row and grid stay as they are", () => {
  fresh({ displayMode: "one" }, [["agent_a", "a"], ["agent_b", "b"], ["agent_c", "c"]]);
  assert.equal(State.tasks.length >= 5, true);
  for (const focus of ["integration_claude", "agent_b", "integration_stripe"]) {
    State.setFocus(focus);
    assert.deepEqual(ids(State.pillRow.map((r) => r.task)), ids(State.otherTasks.slice(0, 4)), focus);
  }
});

test("an agent gets its coat the first time it is seen, once: Claude Code and Codex have defaults, any other agent a stored random coat that is no one else's", () => {
  fresh({ character: "ginger", displayMode: "perAgent" });
  let saved = 0;
  State.persistSettings = () => { saved++; };
  State.upsertExternalAgent("agent_gemini", "gemini", "#8AB4F8");
  const gemini = State.settings.cat.agentCats.agent_gemini;
  assert.ok(gemini && !["shrimpy", "momo", "ginger"].includes(gemini), `Gemini CLI: ${gemini}`);
  assert.equal(saved, 1, "the new coat is saved");
  State.upsertExternalAgent("agent_gemini", "gemini", "#8AB4F8");
  State.removeTask("agent_gemini");
  State.upsertExternalAgent("agent_gemini", "gemini", "#8AB4F8");
  assert.equal(State.settings.cat.agentCats.agent_gemini, gemini, "it keeps its coat when it comes back");
  assert.equal(saved, 1, "and nothing more is saved");
  State.upsertExternalAgent("agent_antigravity", "antigravity", "#E879F9");
  const agy = State.settings.cat.agentCats.agent_antigravity;
  assert.ok(agy && agy !== gemini && !["shrimpy", "momo", "ginger"].includes(agy));
  assert.equal(saved, 2);
  assert.equal(State.settings.cat.agentCats.integration_claude, undefined, "Claude Code's default is not stored");
  assert.equal(State.cast.pills.find((p) => p.pill === "agent_gemini").cat, gemini, "and the cast reads it");
});

test("giveCoats at load covers the agent pills that exist, with nothing to save when they all have a coat; an integration pill never gets one", () => {
  fresh({ displayMode: "perAgent", agentCats: { agent_a: "oreo" } });
  State.tasks.push({ id: "agent_a", name: "a", color: "#fff", state: "idle", stepIndex: 0, steps: [], source: "agent", isIntegration: false }, { id: "agent_b", name: "b", color: "#fff", state: "idle", stepIndex: 0, steps: [], source: "agent", isIntegration: false });
  let saved = 0;
  State.persistSettings = () => { saved++; };
  State.giveCoats();
  assert.equal(State.settings.cat.agentCats.agent_a, "oreo");
  assert.ok(State.settings.cat.agentCats.agent_b);
  assert.equal(State.settings.cat.agentCats.integration_stripe, undefined);
  assert.equal(saved, 1);
  State.giveCoats();
  assert.equal(saved, 1, "a second call changes nothing and saves nothing");
  assert.deepEqual(State.settings.cat, cleanCatBlock(State.settings.cat), "the block stays clean");
  assert.deepEqual(defaultCatBlock().agentCats, {});
});

test("the wiring: main.ts gives the coats once at load and saves them, and upsertExternalAgent gives a new agent its coat", () => {
  const main = source("main.ts"), state = source("core/state.ts");
  assert.match(main, /State\.persistSettings = \(\) => void Bridge\.saveSettings\(State\.settings\);/);
  // persistSettings is set before the first loadIntegrationTasks, so the coat that load gives a switched-on agent is saved; giveCoats still follows.
  assert.match(main, /State\.persistSettings = \(\) => void Bridge\.saveSettings\(State\.settings\);\s*\n\s*State\.loadIntegrationTasks\(\);[^]*?State\.giveCoats\(\);/);
  assert.ok(main.indexOf("State.persistSettings = ") < main.indexOf("State.loadIntegrationTasks();"), "the save hook is set before the first load");
  assert.match(state, /this\.giveCoats\(\[id\]\);/);
});
