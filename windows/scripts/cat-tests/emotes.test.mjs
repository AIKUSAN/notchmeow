import test from "node:test";
import assert from "node:assert/strict";
import { BotEngine } from "../../src/cat/engine.ts";
import { ZOOM_AFTER_MS, rng } from "../../src/cat/base.ts";
import { layout } from "../../src/cat/geometry.ts";
import { PERSONAS, personaNamed } from "../../src/cat/personality.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { finite, load, same } from "./util.mjs";
import { makeEngine, sample } from "./engine-util.mjs";

const fx = load("motion-cases.json");
const seq = load("sequence-cases.json");
const { columns } = fx;
const frames = fx.clock.sampleFrames;

// The hairball is stage 4's: until BotEngine has one its rows are not checked (catch.test.mjs checks them after).
const hasHairball = typeof BotEngine.prototype.hairball === "function";
const HAIRBALL_LATER = (r) => !hasHairball && r.emote === "hairball";

test("every emote, in both motion styles, is the fixture's pose frame by frame (eyes, ears, body and the six mouth values)", () => {
  assert.ok(fx.emotes.length > 200);
  for (const r of fx.emotes) {
    if (HAIRBALL_LATER(r)) continue;
    const got = sample(PRESETS[r.cat], { profile: r.profile }, (e) => e.emote(r.emote), [r.f], columns)[0];
    assert.equal(got.eye, r.eye, `${r.profile} ${r.emote} f${r.f}: eye`);
    same(got.v, r.v, `${r.profile} ${r.emote} f${r.f}`);
  }
});

test("45 seconds of idle habits (blinks, ear flicks, bleps, yawns, purrs...) for each personality are the fixture's, in order", () => {
  for (const a of fx.ambient) {
    const log = [];
    const { step } = makeEngine(PRESETS.momo, { profile: a.profile, quiet: false, seed: a.seed, log, pers: { momo: personaNamed(a.persona) } });
    for (let f = 1; f <= a.seconds * 60; f++) step(f);
    assert.deepEqual(log, a.events, `${a.profile} ${a.persona}`);
  }
  assert.ok(fx.ambient.some((a) => a.events.some((ev) => ev[1] === "blep")), "the fixture does have bleps");
});

test("zoomies after 5 minutes of work and on waking, and not otherwise, are the fixture's", () => {
  for (const z of seq.zoomiesAndWake) {
    const log = [], clock = { t: 0 };
    const e = new BotEngine(PRESETS.momo, { now: () => clock.t, rand: rng(1), quiet: true, log, cfg: { motion: z.profile, override: {}, pers: {}, zoomAfter: ZOOM_AFTER_MS } });
    const L = layout(PRESETS.momo, e.s, 0, 0, 2 * PRESETS.momo.rx);
    e.base = L.base; e.mouthAt = L.mouth;
    for (const [tMs, what] of z.script) { clock.t = tMs; e.setState(what.startsWith("wake:") ? "idle" : what); }
    for (let f = 0; f < 60; f++) { clock.t += 1000 / 60; e.update(1 / 60); }
    assert.deepEqual(log, z.log, `${z.profile}: ${z.name}`);
  }
});

test("a poke: annoyed by default, love from a cuddly cat, a hiss from a grumpy one, and Classic does the same", () => {
  const poke = (name, profile = "playful") => {
    const log = [];
    const { e, step } = makeEngine(PRESETS.momo, { profile, log, pers: { momo: personaNamed(name) } });
    e.slap();
    for (let f = 1; f <= 20; f++) step(f);
    return { e, log };
  };
  assert.deepEqual(poke("balanced").log.map((l) => l[1]), ["emote:annoyed"]);
  assert.deepEqual(poke("sweet").log.map((l) => l[1]), ["emote:love"]);
  assert.deepEqual(poke("sweet", "classic").log.map((l) => l[1]), ["emote:love"]);
  assert.deepEqual(poke("grumpy").log.map((l) => l[1]), ["emote:annoyed"]);
  assert.ok(poke("grumpy").e.s.mouth > poke("balanced").e.s.mouth, "a grumpy cat opens its mouth to hiss");
  assert.ok(PERSONAS.grumpy.sass > 0.7);
});

test("an unknown emote changes nothing, and the dizzy recovery ends with a happy emote", () => {
  const control = makeEngine(PRESETS.momo), poked = makeEngine(PRESETS.momo);
  poked.e.emote("nope"); poked.e.emote("__proto__"); poked.e.triggerEmote("toString");
  for (let f = 1; f <= 30; f++) { control.step(f); poked.step(f); }
  same(poked.e.s, JSON.parse(JSON.stringify(control.e.s)), "the pose is the quiet cat's");
  finite(poked.e.s);
  const lone = makeEngine(PRESETS.momo, { log: [] });
  lone.e.slap(); lone.e.slap(); lone.e.slap();
  for (let f = 1; f <= 60 * 4; f++) lone.step(f);
  assert.ok(lone.e.log.some((l) => l[1] === "emote:happy"), "the cat is happy to be back");
});

test("the island's triggerEmote plays the emote; the old duration argument is accepted and ignored", () => {
  const { e, step } = makeEngine(PRESETS.momo, { log: [] });
  e.triggerEmote("love", 5);
  step(10);
  assert.equal(e.log[0][1], "emote:love");
  assert.ok(e.s.blush > 0);
});
