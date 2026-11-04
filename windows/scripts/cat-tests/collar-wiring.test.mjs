import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { bigCatCollar } from "../../src/cat/collar.ts";
import { BotEngine } from "../../src/cat/engine.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { applyCatSettings } from "../../src/cat/settings.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

installBrowserStubs();
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const cfgOf = (extra = {}) => ({ motion: "playful", override: {}, pers: {}, zoomAfter: 300000, ...extra });
const strokes = (e, head) => { const ctx = fakeCanvas(); e.draw(ctx, head / 0.6, head / 0.6); return ctx.calls.stroke || 0; };
const make = (cfg, colour) => { const e = new BotEngine(PRESETS.momo, { cfg, quiet: true, now: () => 0, rand: () => 0.5, mini: true }); e.collarColor = colour; return e; };

test("the big cat wears the colour of the agent driving its state, and none when idle, asleep or dizzy", () => {
  for (const state of ["working", "thinking", "searching", "approval", "question", "error", "finished", "ratelimit"]) assert.equal(bigCatCollar(state, "#8AB4F8"), "#8AB4F8", state);
  for (const state of ["idle", "sleeping", "dizzy"]) assert.equal(bigCatCollar(state, "#8AB4F8"), null, state);
  for (const none of [null, undefined, ""]) assert.equal(bigCatCollar("working", none), null, String(none));
});

test("an engine draws its collar in the style of the shared config, and nothing when it has no colour or the style is off", () => {
  for (const head of [13, 24, 66]) {
    const bare = strokes(make(cfgOf({ collar: "band" }), null), head);
    for (const style of ["tag", "band", "kerchief"]) assert.ok(strokes(make(cfgOf({ collar: style }), "#8AB4F8"), head) > bare, `Ø${head} ${style}`);
    assert.equal(strokes(make(cfgOf({ collar: "off" }), "#8AB4F8"), head), bare, `Ø${head} off`);
    assert.equal(strokes(make(cfgOf({}), "#8AB4F8"), head), bare, `Ø${head}: no style chosen means off`);
    assert.equal(strokes(make(cfgOf({ collar: "scarf" }), "#8AB4F8"), head), bare, `Ø${head}: an unknown style is off`);
  }
});

test("changing the collar in Settings changes a running engine at once", () => {
  const cfg = cfgOf(), e = make(cfg, "#8AB4F8");
  const bare = strokes(e, 40);
  applyCatSettings(cfg, { character: "momo", collar: "band" });
  assert.ok(strokes(e, 40) > bare, "a band appeared");
  applyCatSettings(cfg, { character: "momo", collar: "band", cats: { momo: { collar: "off" } } });
  assert.equal(strokes(e, 40), bare, "this cat's own Off beats the global Band");
  applyCatSettings(cfg, { character: "momo", collar: "off", cats: { momo: { collar: "kerchief" } } });
  assert.ok(strokes(e, 40) > bare, "this cat's own Neckerchief beats the global Off");
});

test("bodyColor is gone, and the wiring is in place: the big cat, the pills and the compact grid", () => {
  const engine = source("cat/engine.ts"), mini = source("cat/minibots.ts"), island = source("island/island.ts");
  assert.doesNotMatch(engine + mini + island, /bodyColor/);
  assert.match(engine, /collar: this\.collarColor \? \{ style: this\.collarStyle, col: this\.collarColor \} : null/);
  assert.match(island, /this\.engine\.collarColor = bigCatCollar\(look\.state, focus\?\.color\);/);
  assert.equal([...mini.matchAll(/engine\.collarColor = task\.color;/g)].length, 2, "when a mini cat is made, and each time the tasks sync");
});
