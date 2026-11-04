import test from "node:test";
import assert from "node:assert/strict";
import { DESKTOP_FPS, desktopFps } from "../../src/cat/desktop.ts";
import { FrameGovernor, MAX_DT } from "../../src/cat/desktopgov.ts";

// The frame-rate governor (sub-project H, spec §3): it keeps to the rate the rule gives with one timer, and stops everything at 0.
function clock() {
  const c = { t: 0, timers: [], rafs: [], frames: [], nextId: 1 };
  c.env = {
    now: () => c.t,
    raf: (cb) => { const id = c.nextId++; c.rafs.push({ id, cb }); return id; },
    caf: (id) => { c.rafs = c.rafs.filter((r) => r.id !== id); },
    set: (fn, ms) => { const id = c.nextId++; c.timers.push({ id, at: c.t + ms, fn }); return id; },
    clear: (id) => { c.timers = c.timers.filter((x) => x.id !== id); },
  };
  c.gov = new FrameGovernor(c.env, (dt) => c.frames.push({ t: c.t, dt }));
  /** Runs `ms` of time: timers fire at their time, the display's frame callback every 1000/60 ms. */
  c.run = (ms) => {
    const end = c.t + ms;
    for (;;) {
      const next = Math.min(...c.timers.map((x) => x.at), c.rafs.length ? c.t + 1000 / 60 : Infinity, end + 0.0001);
      if (next > end) { c.t = end; return; }
      c.t = next;
      for (const x of c.timers.filter((q) => q.at <= c.t)) { c.timers = c.timers.filter((q) => q !== x); x.fn(); }
      if (c.rafs.length && Math.abs(next - (Math.round(next / (1000 / 60)) * (1000 / 60))) < 1e-6) { const r = c.rafs.splice(0); r.forEach((q) => q.cb()); }
    }
  };
  return c;
}

test("rate 0 schedules nothing: no timer and no frame callback, so a cat that cannot be seen costs nothing", () => {
  const c = clock();
  c.gov.setRate(0);
  c.run(10_000);
  assert.deepEqual([c.frames.length, c.timers.length, c.rafs.length, c.gov.running], [0, 0, 0, false]);
  c.gov.setRate(5);
  c.run(1100);
  c.gov.setRate(0);
  assert.deepEqual([c.timers.length, c.rafs.length, c.gov.running], [0, 0, false], "stopping clears both");
});

test("each rate draws about that many frames a second: 5 idle, 20 working, 0.5 asleep with the long gap's dt held to MAX_DT, 60 on the display's own callback", () => {
  for (const [fps, expect] of [[5, 5], [20, 20], [60, 60]]) {
    const c = clock();
    c.gov.setRate(fps);
    c.run(2000);
    assert.ok(Math.abs(c.frames.length / 2 - expect) <= expect * 0.1 + 1, `${fps} fps drew ${c.frames.length / 2} a second`);
  }
  const c = clock();
  c.gov.setRate(DESKTOP_FPS.asleep);
  c.run(7000);
  assert.deepEqual(c.frames.map((f) => Math.round(f.t)), [2000, 4000, 6000]);
  assert.equal(c.frames[0].dt, 0, "the first frame after a start has no dt");
  assert.equal(c.frames[1].dt, MAX_DT, "a 2 s gap is held to MAX_DT");
});

test("a new rate takes effect at once and the same rate leaves the schedule alone; a rate that is not a number is 0; 120 is 60", () => {
  const c = clock();
  c.gov.setRate(5);
  const timer = c.timers[0];
  c.gov.setRate(5);
  assert.equal(c.timers[0], timer, "the same rate: the same timer");
  c.gov.setRate(20);
  assert.equal(c.timers.length, 1);
  assert.equal(c.timers[0].at, 50);
  for (const bad of [NaN, Infinity, -5, "20", null, undefined]) { c.gov.setRate(bad); assert.equal(c.gov.fps, 0, String(bad)); assert.equal(c.gov.running, false); }
  c.gov.setRate(120);
  assert.equal(c.gov.fps, 60);
  assert.equal(c.rafs.length, 1);
});

test("poke() draws one frame now and carries on at the rate; it does nothing at rate 0; a rate set from inside a frame is not scheduled twice", () => {
  const c = clock();
  c.gov.poke();
  assert.equal(c.frames.length, 0);
  c.gov.setRate(5);
  c.run(50);
  c.gov.poke();
  assert.equal(c.frames.length, 1);
  assert.equal(c.timers.length, 1, "one timer, not two");
  const d = clock();
  let g;
  g = new FrameGovernor(d.env, () => { g.setRate(20); });
  g.setRate(5);
  d.run(500);
  assert.ok(d.timers.length + d.rafs.length === 1, "one schedule after a frame that changed the rate");
});

test("the frame-rate rule and the governor agree: a cat on the desktop idles at 5, works at 20, sleeps at 0.5, is still at 60 only in motion and costs nothing hidden", () => {
  const rate = (o) => desktopFps({ phase: "onDesktop", ...o });
  assert.deepEqual([rate({}), rate({ working: true }), rate({ asleep: true }), rate({ dragging: true }), rate({ hidden: true })], [5, 20, 0.5, 60, 0]);
});
