import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { BotEngine, catCfg } from "../../src/cat/engine.ts";
import { GT, GT3, Greeting } from "../../src/cat/greeting.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { createMiniBot, miniBotCoats, pruneMiniBots, syncMiniBotStates, tickMiniBots } from "../../src/cat/minibots.ts";
import { cleanCatBlock } from "../../src/cat/display.ts";
import { State } from "../../src/core/state.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

installBrowserStubs();
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

// Every place that draws a cat takes its coat from the cast, never from the Main cat behind its back: one test per call site.
const makeEl = (tag) => ({ tag, style: {}, className: "", children: [], width: 0, height: 0, isConnected: true, append(...c) { this.children.push(...c); }, getContext: () => fakeCanvas() });
const stubDom = () => { globalThis.document = { createElement: makeEl }; globalThis.window = { devicePixelRatio: 1, setTimeout: () => 0, clearTimeout: () => {} }; };
const unstubDom = () => { delete globalThis.window; installBrowserStubs(); };
const agent = (id, state = "idle") => ({ id, name: id, color: "#8AB4F8", state, stepIndex: 0, steps: [], source: "agent", isIntegration: false });
const setup = (cat) => {
  State.settings = { ...State.settings, cat: cleanCatBlock(cat) };
  State.tasks = [{ ...agent("integration_claude", "working") }, agent("agent_codex", "approval"), agent("agent_gemini"), agent("agent_antigravity"), { ...agent("integration_stripe"), isIntegration: true }];
  State.focusId = "integration_claude";
  State.asleep = false;
};
const PER_AGENT = { character: "ginger", displayMode: "perAgent", agentCats: { agent_gemini: "oreo", agent_antigravity: "leo" } };

test("the big cat: an engine fed the cast wears the focused agent's cat through every frame, whatever the Main cat is", () => {
  setup(PER_AGENT);
  const cfg = { motion: "playful", override: {}, pers: {}, zoomAfter: 3e5, character: "ginger" }, e = new BotEngine(undefined, { cfg, quiet: true, now: () => 0, rand: () => 0.5 });
  e.setCoat(State.cast.big.cat);
  assert.equal(e.p.name, "shrimpy", "Claude Code is Shrimpy");
  e.update(1 / 60);
  assert.equal(e.p.name, "shrimpy", "the per-frame follow no longer overwrites it with the Main cat (Ginger)");
  State.setFocus("agent_gemini");
  e.setCoat(State.cast.big.cat);
  assert.equal(e.p.name, "oreo");
  State.setFocus("integration_stripe");
  e.setCoat(State.cast.big.cat);
  assert.equal(e.p.name, "ginger", "an integration in focus: the Main cat");
  assert.match(source("island/island.ts"), /const focus = State\.focusTask;\s*const look = this\.bigLook\(\);\s*this\.engine\.setCoat\(look\.coat\);/, "island.ts: drawBot sets the big cat's coat from the cast every frame");
});

test("the pills: a pill's mini cat is made in the cast's coat and keeps it through every frame; the pill row asks the cast", () => {
  setup(PER_AGENT);
  stubDom();
  try {
    pruneMiniBots();
    catCfg.character = "momo";
    for (const { task, cat } of State.pillRow) createMiniBot(task, 24, cat);
    assert.deepEqual(miniBotCoats(), { agent_codex: "momo", agent_gemini: "oreo", agent_antigravity: "leo", integration_stripe: "ginger" });
    tickMiniBots(1 / 60);
    assert.equal(miniBotCoats().agent_gemini, "oreo", "a frame does not turn it into the Main cat");
  } finally {
    delete catCfg.character;
    unstubDom();
  }
  const views = source("views/views.ts");
  assert.match(views, /const row = State\.pillRow;/);
  assert.match(views, /createMiniBot\(task, 24, cat\)/);
  assert.doesNotMatch(views, /State\.otherTasks/);
});

test("the compact grid: its cats are made in the cast's coats and follow the cast when the mode, the Main cat or an agent's coat changes", () => {
  setup(PER_AGENT);
  stubDom();
  try {
    pruneMiniBots();
    for (const { task, cat } of State.pillRow) createMiniBot(task, 13, cat);
    assert.equal(miniBotCoats().agent_antigravity, "leo");
    State.settings = { ...State.settings, cat: cleanCatBlock({ ...State.settings.cat, agentCats: { agent_gemini: "snow", agent_antigravity: "puff" } }) };
    syncMiniBotStates(State.tasks);
    assert.deepEqual([miniBotCoats().agent_gemini, miniBotCoats().agent_antigravity], ["snow", "puff"], "an agent's coat changed in Settings: the grid follows with no restart");
    State.settings = { ...State.settings, cat: cleanCatBlock({ ...State.settings.cat, displayMode: "one", character: "latte" }) };
    syncMiniBotStates(State.tasks);
    assert.deepEqual(Object.values(miniBotCoats()), ["latte", "latte", "latte", "latte"], "One cat: the Main cat everywhere");
    State.settings = { ...State.settings, cat: cleanCatBlock({ ...State.settings.cat, displayMode: "two", pair: ["momo", "cloud"] }) };
    syncMiniBotStates(State.tasks);
    assert.equal(miniBotCoats().agent_codex, "latte", "Two cats: the pills wear the Main cat (a pill that left the row keeps what it had)");
  } finally {
    unstubDom();
  }
  assert.match(source("island/island.ts"), /const row = State\.pillRow;[^]*createMiniBot\(task, 13, cat\)/);
});

test("the greeting's session cats: each cell wears its pill's coat, the glide ends where the grid begins, and with no cast everything wears the chosen cat", () => {
  globalThis.window = { setTimeout: () => 0, clearTimeout: () => {} };
  try {
    setup(PER_AGENT);
    const clock = { t: 0 }, g = new Greeting(() => clock.t);
    g.start(State.cast.greeting);
    assert.deepEqual(g.sessionViews.map((v) => v.p.name), ["momo", "oreo", "leo", "ginger"], "Codex, Gemini CLI, Antigravity and Stripe (the Main cat)");
    assert.equal(g.view.p.name, "ginger", "the cat that falls in is the Main cat");
    clock.t = (GT.leave + GT3.end - 0.05) * 1000;
    const ctx = fakeCanvas();
    g.draw(ctx);
    // A coat's eyes were drawn: its iris gradient's first stop, or, for a black coat (flat and bright), the lighter of its two iris colours as a flat fill.
    const lum = (h) => { const n = parseInt(h.slice(1), 16); return 0.2126 * ((n >> 16) & 255) + 0.7152 * ((n >> 8) & 255) + 0.0722 * (n & 255); };
    const eyesDrawn = (id) => { const [a, b] = PRESETS[id].iris; return ["midnight", "oreo", "mocha"].includes(id) ? ctx.seen.fillStyles.includes(lum(a) >= lum(b) ? a : b) : ctx.seen.stops.includes(a); };
    for (const id of ["momo", "oreo", "leo"]) assert.ok(eyesDrawn(id), `${id}'s eyes were drawn`);
    catCfg.character = "latte";
    const plain = new Greeting(() => 0);
    plain.start();
    assert.deepEqual(plain.sessionViews.map((v) => v.p.name), ["latte", "latte", "latte", "latte"]);
    assert.equal(plain.minis.p.name, "latte");
  } finally {
    delete catCfg.character;
    delete globalThis.window;
  }
  assert.match(source("island/island.ts"), /this\.greeting\.start\(State\.cast\.greeting, State\.outfit\);/);
});

test("the drop view and the drag ghost: the cat wears the big cat's coat, set every frame", () => {
  assert.match(source("upload/canvas.ts"), /this\.cat\.setCoat\(State\.cast\.drop\);\s*this\.cat\.lookX = f\.lookX;/);
  setup(PER_AGENT);
  assert.equal(State.cast.drop, State.cast.big.cat);
  State.setFocus("agent_gemini");
  assert.equal(State.cast.drop, "oreo");
  State.settings = { ...State.settings, cat: cleanCatBlock({ ...State.settings.cat, displayMode: "two", pair: ["blue", "snow"] }) };
  assert.equal(State.cast.drop, "blue", "Two cats: the big cat's, cat 1's");
  State.settings = { ...State.settings, cat: cleanCatBlock({ ...State.settings.cat, displayMode: "one" }) };
  assert.equal(State.cast.drop, "ginger");
});
