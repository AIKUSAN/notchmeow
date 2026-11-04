import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { BotEngine, catCfg } from "../../src/cat/engine.ts";
import { Greeting } from "../../src/cat/greeting.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { applyCatSettings } from "../../src/cat/settings.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

installBrowserStubs();
const cfgOf = (extra = {}) => ({ motion: "playful", override: {}, pers: {}, zoomAfter: 300000, ...extra });
const make = (preset, cfg) => new BotEngine(preset, { cfg, quiet: true, now: () => 0, rand: () => 0.5 });
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("an engine built without a preset wears the chosen cat and changes with it; one built with a preset keeps it", () => {
  const cfg = cfgOf({ character: "momo" });
  const follows = make(undefined, cfg), fixed = make(PRESETS.latte, cfg);
  assert.deepEqual([follows.follow, fixed.follow], [true, false]);
  assert.deepEqual([follows.p.name, fixed.p.name], ["momo", "latte"]);
  cfg.character = "ginger";
  follows.update(1 / 60); fixed.update(1 / 60);
  assert.deepEqual([follows.p.name, fixed.p.name], ["ginger", "latte"]);
  for (const bad of ["tiger", "", "Momo", "__proto__", undefined, null, 7]) {
    cfg.character = bad;
    follows.update(1 / 60);
    assert.equal(follows.p.name, "shrimpy", `an unknown character (${String(bad)}) is Shrimpy`);
  }
  assert.equal(make(undefined, cfgOf()).p.name, "shrimpy", "nothing chosen yet: Shrimpy");
});

test("Settings change the cat, the motion and the personality of an engine that is already running", () => {
  const cfg = cfgOf(), e = make(undefined, cfg);
  applyCatSettings(cfg, { character: "momo", motionStyle: "classic", cats: { momo: { motion: "playful", personality: { preset: "hyper" } } } });
  e.update(1 / 60);
  assert.equal(e.p.name, "momo");
  assert.equal(e.motion, "playful", "momo's own motion beats the global style");
  assert.equal(e.pers.preset, "custom", "a personality with only a name is Custom, with the missing traits at 0.5");
  applyCatSettings(cfg, { character: "ginger", motionStyle: "classic" });
  e.update(1 / 60);
  assert.deepEqual([e.p.name, e.motion], ["ginger", "classic"]);
});

test("the fur lines setting reaches the drawing: a big cat grows strands, a small one does not", () => {
  const strokes = (fur, head) => {
    const cfg = cfgOf({ character: "shrimpy", fur }), e = make(undefined, cfg), ctx = fakeCanvas();
    e.draw(ctx, head / 0.6, head / 0.6 + 40);
    return ctx.calls.stroke || 0;
  };
  assert.ok(strokes(true, 100) > strokes(false, 100) + 100, "Ø100 with fur lines draws hundreds of strands");
  assert.equal(strokes(true, 24), strokes(false, 24), "a small cat is flat");
});

test("the greeting wears the chosen cat", () => {
  globalThis.window = { setTimeout: () => 0, clearTimeout: () => {} };
  try {
    for (const id of ["momo", "latte", "tiger"]) {
      catCfg.character = id;
      const g = new Greeting();
      g.start();
      assert.equal(g.view.p.name, id === "tiger" ? "shrimpy" : id, id);
      assert.equal(g.minis.p.name, g.view.p.name);
    }
  } finally {
    delete catCfg.character;
    delete globalThis.window;
  }
});

test("the wiring: Island.applySettings fills catCfg, the drop view's cat follows, the state holds the cat block", () => {
  assert.match(source("island/island.ts"), /applySettings\(\) \{[^}]*const block = cleanCatBlock\(State\.settings\.cat\);\s*applyCatSettings\(catCfg, block\);\s*State\.settings\.cat = block;/s);
  assert.match(source("upload/canvas.ts"), /readonly cat = new BotEngine\(\);/);
  assert.match(source("cat/greeting.ts"), /const main = cast \? cast\.cat : catCfg\.character \?\? DEFAULT_CAT;\s*this\.view = greetView\(main,/);
  assert.match(source("core/state.ts"), /cat: CatBlock;/);
  assert.match(source("core/state.ts"), /cat: defaultCatBlock\(\),/);
});
