import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { rng } from "../../src/cat/base.ts";
import { State, AGENT_SWITCHES, DEFAULT_SETTINGS } from "../../src/core/state.ts";
import { agentColor, agentPillName } from "../../src/core/pills.ts";

// The agent switches on the island (the Mac's hidden-pill rule): an agent switched on stays on the island, idle, when its session ends; an agent switched off is
// transient, as it always was. The hook path and island/hooks.ts do not change.
const source = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const fresh = (active) => {
  State.settings = { ...State.settings, activeIntegrations: [...active] };
  State.tasks = [];
  State.focusId = null;
  State.rand = rng(11);
  State.persistSettings = null;
  State.kittens = {};
  State.loadIntegrationTasks();
};
const find = (id) => State.tasks.find((t) => t.id === id);

test("the switches are the two agents that have a relay tag, and no switch is on by default", () => {
  assert.deepEqual(AGENT_SWITCHES, [{ id: "agent_gemini", tag: "gemini" }, { id: "agent_antigravity", tag: "antigravity" }]);
  assert.ok(!State.settings.activeIntegrations.some((id) => id.startsWith("agent_")), "a new or existing user keeps today's behaviour");
});

test("a fresh install holds four services, so both agent switches start disabled: a change to the default shows up here", () => {
  assert.equal(DEFAULT_SETTINGS.activeIntegrations.length, 4);
  assert.ok(DEFAULT_SETTINGS.activeIntegrations.every((id) => id.startsWith("integration_")), "all four are services");
});

test("fresh() clears the kittens, so one test's subagents never reach the next", () => {
  fresh(["agent_gemini"]);
  State.kittenEvent("agent_gemini", { type: "start", id: "k9", t: 1 });
  assert.ok(State.kittens.agent_gemini, "a kitten is set");
  fresh(["integration_stripe"]);
  assert.deepEqual(State.kittens, {});
});

test("with an integration on and no agent switched on, no agent pill is loaded", () => {
  fresh(["integration_stripe"]);
  assert.equal(State.tasks.some((t) => t.id.startsWith("agent_")), false);
  assert.ok(find("integration_stripe"));
});

test("a transient agent pill is removed when its session ends: upsertExternalAgent then removeTask, with the switch off", () => {
  fresh(["integration_stripe"]);
  State.upsertExternalAgent("agent_gemini", "gemini", "#8AB4F8");
  assert.ok(find("agent_gemini"));
  State.removeTask("agent_gemini");
  assert.equal(find("agent_gemini"), undefined);
});

test("a switched-on agent is loaded idle at start, with the pill a new agent would get", () => {
  fresh(["agent_gemini"]);
  const pill = find("agent_gemini");
  assert.ok(pill, "loaded");
  assert.equal(pill.state, "idle");
  assert.equal(pill.name, agentPillName("gemini"));
  assert.equal(pill.color, agentColor("gemini"));
  assert.equal(pill.source, "agent");
  assert.equal(pill.isIntegration, false);
});

test("removeTask keeps a switched-on agent's pill and resets it to idle: its steps, step index and badge go, its name comes back", () => {
  fresh(["agent_gemini"]);
  const pill = find("agent_gemini");
  State.updateTask("agent_gemini", "working");
  State.appendStep("agent_gemini", "Reading a file");
  State.setPillBadge("agent_gemini", "finished");
  pill.name = "renamed";
  State.removeTask("agent_gemini");
  const after = find("agent_gemini");
  assert.ok(after, "the pill is still there");
  assert.equal(after.state, "idle");
  assert.equal(after.steps.length, 0);
  assert.equal(after.stepIndex, 0);
  assert.equal(after.pillBadge, null);
  assert.equal(after.name, agentPillName("gemini"));
});

test("a switched-off agent stays while it is busy and goes at the next load once it is idle (the hidden-pill rule)", () => {
  fresh(["agent_gemini"]);
  State.updateTask("agent_gemini", "working");
  State.settings = { ...State.settings, activeIntegrations: [] };
  State.loadIntegrationTasks();
  assert.ok(find("agent_gemini"), "a busy pill is not removed by the settings change");
  State.updateTask("agent_gemini", "idle");
  State.loadIntegrationTasks();
  assert.equal(find("agent_gemini"), undefined, "an idle pill that is off goes");
});

test("switching an agent off drops its kittens with its pill", () => {
  fresh(["agent_gemini"]);
  State.kittenEvent("agent_gemini", { type: "start", id: "k1", t: 1 });
  assert.ok(State.kittens.agent_gemini);
  State.settings = { ...State.settings, activeIntegrations: [] };
  State.loadIntegrationTasks();
  assert.equal(State.kittens.agent_gemini, undefined);
});

test("State.toggleIntegration (no caller: the real four-slot cap is nextActive in settings/status.ts): with four ids on, nothing changes; with three, it is added and loads", () => {
  fresh(["integration_stripe", "integration_resend", "integration_n8n", "integration_vercel"]);
  State.toggleIntegration("agent_antigravity");
  assert.deepEqual(State.settings.activeIntegrations, ["integration_stripe", "integration_resend", "integration_n8n", "integration_vercel"]);
  assert.equal(find("agent_antigravity"), undefined);

  fresh(["integration_stripe", "integration_resend", "integration_n8n"]);
  State.toggleIntegration("agent_antigravity");
  assert.ok(State.settings.activeIntegrations.includes("agent_antigravity"));
  assert.ok(find("agent_antigravity"), "loaded");
  assert.equal(find("agent_antigravity").name, agentPillName("antigravity"));
});

test("State.toggleIntegration accepts only the toggleable services and the agent switches: any other id changes nothing", () => {
  fresh(["integration_stripe"]);
  State.toggleIntegration("integration_madeup");
  State.toggleIntegration("agent_unknown");
  State.toggleIntegration("integration_claude");
  assert.deepEqual(State.settings.activeIntegrations, ["integration_stripe"], "an id outside the two lists is refused");
  State.toggleIntegration("integration_resend");
  assert.ok(State.settings.activeIntegrations.includes("integration_resend"), "a toggleable service is taken");
});

test("State.toggleIntegration on Claude Code changes nothing (no caller; kept as the island-side rule)", () => {
  fresh(["integration_stripe"]);
  const before = [...State.settings.activeIntegrations];
  State.toggleIntegration("integration_claude");
  assert.deepEqual(State.settings.activeIntegrations, before);
  assert.ok(find("integration_claude"), "still there");
});

test("the hook path is unchanged: island/hooks.ts still calls removeTask twice and does not read the switches; the relay reads neither", () => {
  const hooks = source("src/island/hooks.ts");
  assert.equal(hooks.split("State.removeTask(agentId);").length - 1, 2);
  assert.ok(!hooks.includes("activeIntegrations"));
  const agents = source("hook/src/agents.rs");
  assert.ok(!agents.includes("activeIntegrations"));
  assert.ok(!agents.includes("settings"));
});

test("the Settings switch reaches the island: settings-changed merges the event into State.settings and then reloads the agent pills", () => {
  const main = source("src/main.ts");
  const at = main.indexOf('onEvent<Settings>("settings-changed"');
  assert.ok(at > 0, "the listener exists");
  const block = main.slice(at, main.indexOf("\n  });", at) + "\n  });".length);
  const merge = block.indexOf("State.settings = { ...State.settings, ...s };");
  const reload = block.indexOf("State.loadIntegrationTasks();");
  assert.ok(merge > 0, "the event is merged into State.settings");
  assert.ok(reload > merge, "the agent pills are reloaded after the merge");
});

test("boot: a switched-on agent given its coat at load is saved, because the save hook is set before the first load", () => {
  State.settings = { ...State.settings, activeIntegrations: ["agent_gemini"], cat: { ...State.settings.cat, agentCats: {} } };
  State.tasks = [];
  State.focusId = null;
  State.rand = rng(11);
  let saved = 0;
  State.persistSettings = () => { saved++; };
  State.loadIntegrationTasks();
  assert.ok(State.settings.cat.agentCats.agent_gemini, "the agent got its coat at load");
  assert.equal(saved, 1, "and that coat was saved");
});

test("boot order: main.ts sets persistSettings before its first loadIntegrationTasks, and gives the coats after it", () => {
  const main = source("src/main.ts");
  const save = main.indexOf("State.persistSettings = () => void Bridge.saveSettings(State.settings);");
  const load = main.indexOf("State.loadIntegrationTasks();");
  assert.ok(save > 0 && load > save, "the save hook comes first");
  assert.ok(main.indexOf("State.giveCoats();") > load, "giveCoats still follows the load");
});
