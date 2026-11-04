import test from "node:test";
import assert from "node:assert/strict";
import { BotEngine } from "../../src/cat/engine.ts";
import { CAT_IDS, PRESETS, kittenOf } from "../../src/cat/presets.ts";
import { applyCatSettings } from "../../src/cat/settings.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

installBrowserStubs();

// A cat's coat comes from the caller (the cast), never from the Main cat behind its back; and its collar style is looked up for its own coat.
const cfgOf = (extra = {}) => ({ motion: "playful", override: {}, pers: {}, zoomAfter: 300000, ...extra });
const make = (preset, cfg, extra = {}) => new BotEngine(preset, { cfg, quiet: true, now: () => 0, rand: () => 0.5, ...extra });
const strokes = (e, head = 40) => { const ctx = fakeCanvas(); e.draw(ctx, head / 0.6, head / 0.6); return ctx.calls.stroke || 0; };

test("setCoat fixes the engine on a cat, and update never overwrites it with the Main cat; setCoat(null) follows the Main cat again", () => {
  const cfg = cfgOf({ character: "momo" }), e = make(undefined, cfg);
  assert.deepEqual([e.follow, e.p.name], [true, "momo"]);
  e.setCoat("oreo");
  assert.deepEqual([e.follow, e.p.name], [false, "oreo"]);
  cfg.character = "ginger";
  e.update(1 / 60);
  assert.equal(e.p.name, "oreo", "the per-agent coat stays through every frame");
  e.setCoat(null);
  e.update(1 / 60);
  assert.deepEqual([e.follow, e.p.name], [true, "ginger"]);
  for (const bad of ["tiger", "", "__proto__", "Momo", undefined, 7]) { e.setCoat(bad); assert.equal(e.p.name, "shrimpy", String(bad)); assert.equal(e.follow, false); }
});

test("an engine's motion style and personality follow its coat, so Codex's Momo moves with Momo's settings", () => {
  const cfg = cfgOf({ character: "shrimpy", override: { momo: "classic" }, pers: { momo: { preset: "hyper" } } }), e = make(undefined, cfg);
  assert.equal(e.motion, "playful");
  e.setCoat("momo");
  assert.deepEqual([e.motion, e.pers.preset], ["classic", "hyper"]);
  const kit = make(kittenOf(PRESETS.momo), cfg);
  assert.deepEqual([kit.motion, kit.pers.preset], ["classic", "hyper"], "a kitten moves like its parent's coat");
});

test("the collar style is looked up per coat: two cats in one config wear their own styles, a kitten its parent's, and a coat with no entry the Main cat's", () => {
  const cfg = cfgOf();
  applyCatSettings(cfg, { character: "momo", collar: "band", cats: { ginger: { collar: "kerchief" }, momo: { collar: "off" }, oreo: { collar: "off" } } });
  assert.deepEqual([cfg.collar, cfg.collars.momo, cfg.collars.ginger, cfg.collars.oreo, cfg.collars.latte], ["off", "off", "kerchief", "off", "band"]);
  assert.deepEqual(Object.keys(cfg.collars), [...CAT_IDS], "every one of the 16 coats has its style");
  const mk = (preset) => { const e = make(preset, cfg, { mini: true }); e.collarColor = "#8AB4F8"; return e; };
  const bare = (preset, head) => strokes(make(preset, cfg, { mini: true }), head);
  assert.equal(strokes(mk(PRESETS.momo)), bare(PRESETS.momo), "Momo's own Off beats the global Band");
  assert.ok(strokes(mk(PRESETS.ginger)) > bare(PRESETS.ginger), "Ginger wears a neckerchief in the same config");
  assert.ok(strokes(mk(PRESETS.latte)) > bare(PRESETS.latte), "a coat with no override of its own wears the global Band");
  assert.ok(strokes(mk(kittenOf(PRESETS.ginger)), 16) > bare(kittenOf(PRESETS.ginger), 16), "a kitten of Ginger wears Ginger's collar");
  assert.equal(strokes(mk(kittenOf(PRESETS.momo)), 16), bare(kittenOf(PRESETS.momo), 16), "a kitten of Momo wears none: its parent's Off");
  const e = mk(PRESETS.latte);
  assert.equal(e.collarStyle, "band");
  e.setCoat("ginger");
  assert.equal(e.collarStyle, "kerchief", "an engine that changes coat changes collar style with it");
});

test("a config with no per-coat table still draws the Main cat's collar for every coat: the engines of the older tests and the Settings window's previews", () => {
  const cfg = cfgOf({ collar: "band" });
  for (const id of ["momo", "ginger", "snow"]) assert.equal(make(PRESETS[id], cfg).collarStyle, "band", id);
  assert.equal(make(PRESETS.momo, cfgOf()).collarStyle, "off");
  assert.equal(make(PRESETS.momo, cfgOf({ collars: {}, collar: "tag" })).collarStyle, "tag", "an empty table falls back to the Main cat's style");
  assert.equal(make(PRESETS.momo, cfgOf({ collars: { momo: "scarf" } })).collarStyle, "scarf", "an unknown style is passed on; the renderer draws nothing for it");
});
