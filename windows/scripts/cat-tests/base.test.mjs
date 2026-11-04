import test from "node:test";
import assert from "node:assert/strict";
import { EZ, rng, tm, wrapA, hex, seg, clamp, lerp, STATES, COL, TINT, BADGE, GLOW, MOUTH, MKEYS, mouthFx, own, ZOOM_AFTER_MS, workClockStep, zoomiesOnFinish } from "../../src/cat/base.ts";
import { load, near, same } from "./util.mjs";

const motion = load("motion-cases.json");

test("rng is the seeded uint32 LCG: the fixture's sequences", () => {
  for (const { seed, values } of motion.prng) {
    const r = rng(seed);
    values.forEach((v) => near(r(), v));
  }
  assert.deepEqual(Array.from({ length: 3 }, rng(2 ** 32 + 7)), Array.from({ length: 3 }, rng(7)), "the seed wraps to uint32");
});

test("the easings match the fixture", () => {
  for (const { name, samples } of motion.ease) for (const { t, v } of samples) near(EZ[name](t), v);
  assert.deepEqual(Object.keys(EZ), ["out", "inOut", "back", "lin", "in"]);
});

test("small helpers", () => {
  near(lerp(2, 10, 0.25), 4);
  assert.equal(clamp(5, 0, 1), 1);
  assert.equal(seg(-1, 0, 2), 0);
  near(seg(1, 0, 2), 0.5);
  near(wrapA(Math.PI * 2.5), Math.PI / 2);
  near(wrapA(Math.PI), -Math.PI);
  near(tm(0, 0.3, 2), 0.3); near(tm(0.5, 0.3, 2), 1); near(tm(1, 0.3, 2), 2); near(tm(0.25, 0.3, 2), 0.65);
  assert.deepEqual(hex("#3B9EFF"), [59, 158, 255]);
  assert.equal(own({ a: 1 }, "a"), true);
  assert.equal(own({}, "toString"), false, "an inherited name is not an own one");
});

test("the eleven states and their tables match the rest fixture", () => {
  assert.equal(STATES.length, 11);
  assert.deepEqual(Object.keys(COL), [...STATES]);
  assert.deepEqual(Object.keys(MOUTH), [...STATES]);
  assert.deepEqual([...MKEYS], ["mouth", "smile", "tongue", "mround", "mskew", "wavy"]);
  for (const r of motion.rest) {
    assert.equal(COL[r.state], r.color, r.state);
    assert.equal(TINT[r.state], r.tint, r.state);
    assert.equal(BADGE[r.state] ?? null, r.badge, r.state);
    assert.equal(GLOW[r.state] ?? null, r.glow, r.state);
  }
});

test("mouthFx (hunting chatter, meows, panting, snoring) matches the rest fixture", () => {
  for (const r of motion.rest) near(mouthFx(r.state, r.T), r.mfx);
  assert.equal(mouthFx("idle", 1.234), 0);
  same(MKEYS.map((k, i) => [k, MOUTH.error[i]]), [["mouth", 0], ["smile", -0.8], ["tongue", 0], ["mround", 0], ["mskew", 0], ["wavy", 0]]);
});

const seq = load("sequence-cases.json");

test("the work clock and the zoomies rule are the fixture's: 5 minutes of work, pauses neither stop nor reset it", () => {
  assert.equal(ZOOM_AFTER_MS, seq.zoomAfterMs);
  assert.equal(ZOOM_AFTER_MS, 300000);
  for (const c of seq.workClock) {
    let clock = { busySince: null, workedFor: 0 };
    const after = c.steps.map(([t, state]) => { clock = workClockStep(clock, state, t); return { tMs: t, state, busySince: clock.busySince, workedFor: clock.workedFor }; });
    same(after, c.after, c.name);
    const last = c.steps[c.steps.length - 1];
    assert.equal(last[1] === "finished" ? zoomiesOnFinish(clock.workedFor) : null, c.zoomiesAtFinish, c.name);
  }
  assert.equal(zoomiesOnFinish(299999), false, "1 ms short");
  assert.equal(zoomiesOnFinish(300000), true, "exactly 5 minutes");
});

test("the work clock never goes negative, even when the clock steps back", () => {
  let c = workClockStep({ busySince: null, workedFor: 0 }, "working", 1000);
  c = workClockStep(c, "finished", 500);
  assert.equal(c.workedFor, 0);
  assert.equal(c.busySince, null);
  assert.equal(workClockStep({ busySince: null, workedFor: 0 }, "working", 0).busySince, 0, "a run that starts at clock 0 is open");
});
