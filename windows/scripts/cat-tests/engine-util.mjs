// Builds an engine the way the fixtures were generated (docs/CAT-CONTRACT.md, "The harness"): a fake clock that
// starts at 0, a seeded rand, R = 1 so that a hairball lands in units of R, and one update per frame at 60 fps.
import { BotEngine } from "../../src/cat/engine.ts";
import { layout } from "../../src/cat/geometry.ts";
import { ZOOM_AFTER_MS, rng } from "../../src/cat/base.ts";

export const FPS = 60;
/** The time of frame f in ms. A fixture row's `tMs` is this, stored to 12 digits (so it can be off by up to 5e-9): rows are matched by `f`, never by `tMs`. */
export const frameMs = (f) => (f * 1000) / FPS;

export function makeEngine(preset, { profile = "playful", pers = {}, seed = 1, quiet = true, state = "idle", log = null, zoomAfter = ZOOM_AFTER_MS } = {}) {
  const clock = { t: 0 };
  const cfg = { motion: profile, override: {}, pers, zoomAfter };
  const e = new BotEngine(preset, { now: () => clock.t, rand: rng(seed), cfg, quiet, state, log });
  const L = layout(preset, e.s, 0, 0, 2 * preset.rx);
  e.base = L.base;
  e.mouthAt = L.mouth;
  return { e, clock, step: (f) => { clock.t = frameMs(f); e.update(1 / FPS); } };
}

/** One fixture row: mouth openness, spring, chew, particle and ball counts, the first ball, then the pose in the fixture's column order. */
export const rowOf = (e, columns) => [
  e.mouthOpen(), e.slotH, e.chew, e.parts.length, e.balls.length, e.balls[0] ? e.balls[0].x : 0, e.balls[0] ? e.balls[0].y : 0,
  ...columns.slice(7).map((k) => e.s[k]),
];

/** Runs from frame 0, calls `start(e)` there, and returns one { f, eye, v } per sample frame. */
export function sample(preset, opts, start, frames, columns) {
  const { e, step } = makeEngine(preset, opts);
  start(e);
  const rows = [], last = frames[frames.length - 1];
  for (let f = 0; f <= last; f++) {
    if (f > 0) step(f);
    if (frames.includes(f)) rows.push({ f, eye: e.eyeShape(), v: rowOf(e, columns) });
  }
  return rows;
}
