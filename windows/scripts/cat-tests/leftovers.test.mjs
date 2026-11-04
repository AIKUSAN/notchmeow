import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { CATCH } from "../../src/cat/engine.ts";
import { GT, GT3, Greeting } from "../../src/cat/greeting.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { USC, UploadSeq } from "../../src/upload/sequence.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";
import { makeEngine } from "./engine-util.mjs";

installBrowserStubs();
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("the file catch's numbers are in one table: the engine and the island's note wait on the same ones", () => {
  assert.deepEqual({ ...CATCH }, { lick: 950, sparks: 1000, end: 2300, gag: 120, hairball: 2400, ballUp: 1110, fileBall: 2600 });
  assert.match(source("island/island.ts"), /const HAIRBALL_S = \(CATCH\.gag \+ CATCH\.hairball\) \/ 1000;/);
  const engine = source("cat/engine.ts");
  for (const old of ["this.later(950,", "this.later(1000,", "this.fileEnd(1000 + 1300)", "this.later(120,", "this.fileEnd(120 + 1110 + 2600)", "this.later(1110,", "life: file ? 2.6 : 2.4"]) assert.ok(!engine.includes(old), old);
  // The flow ends when the table says: 2.3 s after a file is taken, 3.83 s after a refusal.
  const taken = makeEngine(PRESETS.momo), refused = makeEngine(PRESETS.momo);
  for (const { e } of [taken, refused]) { e.fileDrop("a.pdf"); }
  taken.e.fileArrived();
  refused.e.fileRefuse(); refused.e.fileArrived();
  const until = (w, ms) => { w.f ??= 0; const target = Math.round(ms / (1000 / 60)); while (w.f < target) w.step(++w.f); }; // runs to `ms` since the start
  until(taken, CATCH.end - 40); assert.equal(taken.e.fileStep, "arrived", "not yet");
  until(taken, CATCH.end + 40); assert.equal(taken.e.fileStep, "none", "done");
  const gone = CATCH.gag + CATCH.ballUp + CATCH.fileBall;
  until(refused, gone - 40); assert.equal(refused.e.fileStep, "arrived", "the hairball is still coming up");
  until(refused, gone + 40); assert.equal(refused.e.fileStep, "none");
});

test("an unknown emote is ignored and not logged; every known one is", () => {
  const { e } = makeEngine(PRESETS.momo, { log: [] });
  for (const bad of ["nope", "", "__proto__", "toString", "Love", undefined, null, 7]) e.emote(bad);
  assert.deepEqual(e.log, []);
  for (const good of ["love", "surprised", "proud", "wink", "yawn", "happy", "annoyed", "hello", "zoomies", "hairball"]) e.emote(good);
  assert.deepEqual(e.log.filter((l) => l[1].startsWith("emote:")).map((l) => l[1].slice(6)), ["love", "surprised", "proud", "wink", "yawn", "happy", "annoyed", "hello", "zoomies", "hairball"]);
});

test("a refusal after the cat began to chew clears the chew's lick: the cat licks its lips once, after the hairball, and not while it gags", () => {
  const { e, step } = makeEngine(PRESETS.momo, { log: [] });
  e.fileDrop("movie.mov");
  const at = (ms) => Math.round(ms / (1000 / 60));
  let f = 0;
  const run = (ms) => { for (const end = f + at(ms); f < end;) step(++f); };
  run(380); e.fileArrived();
  run(300); e.fileRefuse();
  const refusedAt = f * (1000 / 60);
  run(4000);
  const licks = e.log.filter((l) => l[1] === "lick").map((l) => l[0] - refusedAt);
  assert.equal(licks.length, 1, `licks at ${licks}`);
  assert.ok(licks[0] > CATCH.gag + CATCH.ballUp, `the lick comes after the ball is up, at ${licks[0]} ms`);
  assert.equal(e.log.filter((l) => l[1] === "hairball").length, 1, "one hairball");
});

test("Greeting takes a clock, keeps one flag, and end() cancels its timers", () => {
  const set = [], cleared = [];
  globalThis.window = { setTimeout: (fn, ms) => { set.push([fn, ms]); return set.length; }, clearTimeout: (id) => cleared.push(id) };
  try {
    let now = 1000;
    const g = new Greeting(() => now);
    assert.equal(g.live, false, "not before it starts");
    g.start();
    assert.equal(g.live, true);
    assert.equal(set.length, 3, "the greet sound, the blip, and the completion");
    now = 2500;
    assert.equal(g.elapsed, 1.5, "the injected clock, in seconds since start");
    const view = g.view;
    now = 4000;
    assert.equal(view.now(), 4000, "the cat's own clock is the same one");
    g.interrupt();
    assert.equal(g.tc, 3, "interrupt() reads the injected clock");
    assert.deepEqual(cleared, [1, 2, 3], "and cancels what was pending, as before");
    cleared.length = 0;
    let ended = 0, completed = 0;
    g.onEnd = () => { ended++; }; g.onComplete = () => { completed++; };
    g.start();
    g.end();
    assert.equal(g.live, false);
    assert.deepEqual(cleared.slice(-3), [4, 5, 6], "end() cancels the three timers the new start() set");
    assert.deepEqual([ended, completed], [0, 0], "silently");
    const ctx = fakeCanvas();
    g.draw(ctx);
    assert.equal(ended, 0, "a greeting that is not running does not finish again");
    g.start();
    now += (GT.leave + GT3.end) * 1000;
    g.draw(ctx);
    assert.equal(g.live, false);
    assert.equal(ended, 1, "the last beat says so once");
  } finally { delete globalThis.window; }
});

test("a refusal that comes late holds the timeline where it is, never past the chew; an early one waits for the file to reach the mouth", () => {
  let ms = 0;
  Object.defineProperty(globalThis, "performance", { value: { now: () => ms }, configurable: true });
  const scene = (refuseAfter) => {
    ms = 0; UploadSeq.deactivate(); UploadSeq.enterZone(300, 100);
    ms = 400; UploadSeq.performDrop(2.4);
    ms = 400 + refuseAfter * 1000; UploadSeq.refuse();
    return (later) => { ms = 400 + (refuseAfter + later) * 1000; return UploadSeq.frame().t; };
  };
  const late = scene(1.2);
  assert.ok(Math.abs(late(0) - USC.T_CHEW_END) < 1e-9, `a late refusal holds at the end of the chew, not back at ${USC.T_SUCK_END}: ${late(0)}`);
  assert.ok(Math.abs(late(5) - USC.T_CHEW_END) < 1e-9, "and stays there");
  const mid = scene(0.5);
  assert.ok(Math.abs(mid(0) - (USC.T_DROP + 0.5)) < 1e-9, "a refusal while the cat chews holds right there");
  assert.ok(Math.abs(mid(3) - (USC.T_DROP + 0.5)) < 1e-9);
  const early = scene(0.1);
  assert.ok(Math.abs(early(0) - (USC.T_DROP + 0.1)) < 1e-9, "an early refusal does not stop the file in the air");
  assert.ok(Math.abs(early(0.15) - (USC.T_DROP + 0.25)) < 1e-9, "it keeps flying");
  assert.ok(Math.abs(early(3) - USC.T_SUCK_END) < 1e-9, "and holds when it reaches the mouth, as before");
  UploadSeq.deactivate();
});

test("the ?dev readout says how many cats it draws, not a number it does not", () => {
  const dev = source("cat/dev.ts");
  assert.ok(!dev.includes("twelve small cats plus the big one on a Mac"));
  assert.match(dev, /the \$\{live\.length\} live cats/);
});
