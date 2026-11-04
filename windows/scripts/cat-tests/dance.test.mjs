import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { DANCE_BPM, applyDance, danceEars, danceLevel, dancePose, shouldDance } from "../../src/cat/dance.ts";
import { BotEngine } from "../../src/cat/engine.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { State } from "../../src/core/state.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";
import { near } from "./util.mjs";

installBrowserStubs();
const BEAT = 60 / DANCE_BPM;
const make = (extra = {}) => { const clock = { t: 0 }; const e = new BotEngine(PRESETS.momo, { now: () => clock.t, rand: () => 0.5, quiet: true, ...extra }); return { e, clock, step: (ms) => { clock.t += ms; e.update(ms / 1000); } }; };

test("the bob is the Mac's: a hop of 0.20 R, a sway of 0.08 R, a roll of 0.10 rad and a landing squash, on the 112 BPM beat", () => {
  assert.equal(DANCE_BPM, 112);
  const land = dancePose(1, 0, 10), air = dancePose(1, BEAT / 2, 10);
  near(land.dx, 0); near(land.dy, 0); near(land.rot, 0); near(land.sx, 1.045); near(land.sy, 0.94);
  near(air.dx, 0.8); near(air.dy, -2); near(air.rot, 0.1); near(air.sx, 1); near(air.sy, 1);
  const half = dancePose(0.5, BEAT / 2, 10);
  near(half.dy, -1); near(half.dx, 0.4);
  const rest = dancePose(0, 0.123, 10);
  for (const k of ["dx", "dy", "rot"]) near(rest[k], 0);
  near(rest.sx, 1); near(rest.sy, 1);
  near(dancePose(1, 5 * BEAT + 0.01, 10).dy, dancePose(1, 0.01, 10).dy, 1e-9);
});

test("applyDance turns, rolls and squashes around the bottom of the head, and does nothing at level 0 or for a bad number", () => {
  const log = [], c = { translate: (...a) => log.push(["translate", ...a]), rotate: (...a) => log.push(["rotate", ...a]), scale: (...a) => log.push(["scale", ...a]) };
  applyDance(c, 1, BEAT / 2, 50, 70, 10);
  assert.deepEqual(log.map((l) => l[0]), ["translate", "rotate", "scale", "translate"]);
  near(log[0][1], 50.8); near(log[0][2], 68); near(log[1][1], 0.1); assert.deepEqual(log[3], ["translate", -50, -70]);
  log.length = 0;
  for (const level of [0, 0.001, -1, NaN, Infinity - Infinity]) applyDance(c, level, 1, 50, 70, 10);
  assert.equal(log.length, 0);
});

test("the dancing level fades in over 0.3 s and out over 0.5 s, and a bad frame time changes nothing", () => {
  let l = 0;
  for (let i = 0; i < 10; i++) l = danceLevel(l, true, 0.03);
  near(l, 1);
  assert.equal(danceLevel(1, true, 5), 1, "held at 1");
  let o = 1;
  for (let i = 0; i < 10; i++) o = danceLevel(o, false, 0.05);
  near(o, 0);
  assert.equal(danceLevel(0, false, 5), 0, "held at 0");
  for (const dt of [NaN, -1, Infinity - Infinity]) assert.equal(danceLevel(0.4, true, dt), 0.4, String(dt));
});

test("the ears bounce on the landing beat: up to 0.14 at the landing, none in the air, scaled by the level", () => {
  near(danceEars(1, 0), 0.14);
  near(danceEars(1, BEAT / 2), 0);
  near(danceEars(0.5, 0), 0.07);
  assert.equal(danceEars(0, 0), 0);
});

test("only the compact island's cat dances, only in the states the Mac allows, never asleep, and only while music plays", () => {
  for (const state of ["idle", "working", "thinking", "searching", "finished"]) assert.equal(shouldDance(true, state, "compact"), true, state);
  for (const state of ["approval", "question", "error", "ratelimit", "sleeping", "dizzy"]) assert.equal(shouldDance(true, state, "compact"), false, state);
  assert.equal(shouldDance(false, "idle", "compact"), false);
  for (const mode of ["hidden", "expanded"]) assert.equal(shouldDance(true, "idle", mode), false, mode);
});

test("an engine bobs while music plays: the level rises over 0.3 s, the canvas is moved and put back, and the ears bounce; at level 0 nothing changes", () => {
  const { e, step } = make();
  const calls = () => { const ctx = fakeCanvas(); e.draw(ctx, 100, 100); return ctx.calls; };
  assert.equal(e.isDancing, false);
  assert.equal(e.dancingLevel, 0);
  const still = calls();
  e.setDancing(true);
  for (let i = 0; i < 20; i++) step(16);
  assert.equal(e.dancingLevel, 1);
  const moving = calls();
  assert.ok(moving.translate > still.translate && moving.rotate > (still.rotate || 0), "the bob translates and rolls the canvas");
  assert.equal(moving.save, moving.restore, "and puts it back");
  e.setDancing(false);
  for (let i = 0; i < 40; i++) step(16);
  assert.equal(e.dancingLevel, 0);
  const back = calls();
  assert.deepEqual([back.translate, back.rotate || 0, back.scale], [still.translate, still.rotate || 0, still.scale], "the canvas is no longer moved");
  const earsOn = make(), earsOff = make();
  earsOn.e.setDancing(true);
  for (let i = 0; i < 30; i++) { earsOn.step(16); earsOff.step(16); }
  earsOn.e.computeTargets(0, 0); earsOff.e.computeTargets(0, 0);
  near(earsOn.e.tg.earU - earsOff.e.tg.earU, 0.14, 1e-9);
});

test("the seam: music is not playing, and the island asks shouldDance every frame it draws the big cat", () => {
  assert.equal(State.musicPlaying, false);
  const island = fs.readFileSync(new URL("../../src/island/island.ts", import.meta.url), "utf8");
  assert.match(island, /this\.engine\.setDancing\(shouldDance\(State\.musicPlaying, look\.state, State\.mode\)\);/);
});
