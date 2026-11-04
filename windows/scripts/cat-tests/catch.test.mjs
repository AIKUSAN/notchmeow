import test from "node:test";
import assert from "node:assert/strict";
import { FLIGHT_MS, flightAt } from "../../src/cat/geometry.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { Sound } from "../../src/core/sound.ts";
import { load, near, same } from "./util.mjs";
import { frameMs, makeEngine, rowOf } from "./engine-util.mjs";

const seq = load("sequence-cases.json");
const { columns } = load("motion-cases.json");

test("a dropped file arcs into the mouth: where it is, how big, how turned, along its flight", () => {
  assert.equal(FLIGHT_MS, seq.flight.flightMs);
  for (const c of seq.flight.cases) same(flightAt(c.from, c.to, c.R, c.k), c.out, `k = ${c.k}`);
  near(flightAt({ x: 0, y: 0 }, { x: 10, y: 10 }, 30, 1).size, 30 * 0.14);
});

test("rows are matched by frame f, the authority: their tMs is derived (f * 1000 / 60, stored to 12 digits) and agrees within 1e-8", () => {
  const motion = load("motion-cases.json");
  for (const r of [...motion.enters, ...motion.emotes, ...seq.catch.flatMap((c) => c.rows)]) near(r.tMs, frameMs(r.f), 1e-8);
});

test("the file catch, in four steps, in both motion styles, for a file taken and a file refused, is the fixture's", () => {
  const flightFrames = seq.catchHarness.flightFrames;
  assert.equal(flightFrames, Math.ceil(FLIGHT_MS / frameMs(1)));
  for (const c of seq.catch) {
    const { e, step } = makeEngine(PRESETS.momo, { profile: c.profile });
    const want = new Map(c.rows.map((r) => [r.f, r])), last = c.rows[c.rows.length - 1].f;
    e.catchOpen(true); // 1. open wide while the file hovers
    for (let f = 0; f <= last; f++) {
      if (f > 0) step(f);
      if (f === c.dropFrame) e.catchDrop(); // 2. snap wider on the drop, the file flies in
      if (f === c.arriveFrame) { if (c.refused) e.catchReject("EXE"); else e.catchArrive(); } // 3. gulp with a squash, 4. chew with happy eyes
      const r = want.get(f);
      if (r) { assert.equal(e.eyeShape(), r.eye, `${c.profile} refused=${c.refused} f${f}: eye`); same(rowOf(e, columns), r.v, `${c.profile} refused=${c.refused} f${f}`); }
    }
  }
});

test("the catch behaves: open while hovering, closed again when the file leaves, chewing for 0.85 s, and a refused file comes back as a hairball", () => {
  const { e, step } = makeEngine(PRESETS.shrimpy);
  e.catchOpen(true);
  for (let f = 1; f <= 30; f++) step(f);
  assert.ok(e.mouthOpen() > 0.3, "open wide while the file hovers");
  e.catchOpen(false);
  for (let f = 31; f <= 90; f++) step(f);
  assert.ok(e.mouthOpen() < 0.02, "closed again when it leaves");
  assert.equal(e.eyeOv, null);
  e.catchArrive();
  let chewing = 0;
  for (let f = 91; f <= 91 + 90; f++) { step(f); if (e.chew > 0) chewing++; }
  assert.ok(chewing > 40 && chewing < 60, `chewed for about 0.85 s, not ${chewing / 60} s`);
  const refused = makeEngine(PRESETS.shrimpy);
  refused.e.catchReject("ZIP");
  let ball = null;
  for (let f = 1; f <= 60 * 4; f++) { refused.step(f); if (refused.e.balls.length) ball = refused.e.balls[0]; }
  assert.ok(ball && ball.file === "ZIP", "the file comes back wrapped in fur");
  assert.equal(refused.e.balls.length, 0, "and rolls away");
});

test("a hairball without a known mouth position is skipped, not thrown", () => {
  const { e, step } = makeEngine(PRESETS.momo);
  e.mouthAt = null;
  e.hairball();
  for (let f = 1; f <= 200; f++) step(f);
  assert.equal(e.balls.length, 0);
});

// The drop view reports a file in whatever order things happen: the app's refusal can come before the file
// reaches the mouth, after it, or never. The cat must cough up exactly one hairball, or none, and never get stuck.
const hairballs = (log) => log.filter((l) => l[1] === "hairball").length;
const run = (script) => {
  const log = [], { e, step } = makeEngine(PRESETS.shrimpy, { log });
  let f = 0;
  const wait = (frames) => { for (let i = 0; i < frames; i++) step(++f); };
  script(e, wait);
  wait(60 * 4);
  return { e, log };
};

test("a refusal that comes before the file arrives: the cat takes it, then coughs it up, once", () => {
  const { e, log } = run((e, wait) => { e.fileHover(true); wait(30); e.fileDrop("setup.exe"); e.fileRefuse(); wait(10); e.fileArrived(); });
  assert.equal(hairballs(log), 1);
  assert.equal(e.fileStep, "none", "the flow is over");
  assert.equal(e.balls.length, 0, "and the ball has rolled away");
});

test("a refusal that comes after the file has arrived: the cat has swallowed it and coughs it up, once", () => {
  const { log } = run((e, wait) => { e.fileHover(true); e.fileDrop("a.zip"); wait(23); e.fileArrived(); wait(5); e.fileRefuse(); e.fileRefuse(); });
  assert.equal(hairballs(log), 1);
});

test("a file that is taken is chewed, with no hairball; and a stray arrival without a drop does nothing", () => {
  const { log } = run((e, wait) => { e.fileArrived(); wait(3); e.fileHover(true); e.fileArrived(); e.fileDrop("notes.pdf"); wait(23); e.fileArrived(); e.fileArrived(); });
  assert.equal(hairballs(log), 0);
  const chew = makeEngine(PRESETS.shrimpy);
  chew.e.fileDrop("a.pdf"); chew.e.fileArrived();
  let chewed = 0;
  for (let f = 1; f <= 90; f++) { chew.step(f); if (chew.e.chew > 0) chewed++; }
  assert.ok(chewed > 40);
});

test("a new drag after a refused drop starts clean; a file that leaves closes the mouth; the extension is shown in capitals", () => {
  const { e, log } = run((e, wait) => { e.fileHover(true); e.fileDrop("x.exe"); e.fileRefuse(); wait(23); e.fileArrived(); wait(60 * 4); e.fileHover(true); e.fileDrop("b.pdf"); wait(23); e.fileArrived(); wait(30); e.fileHover(false); });
  assert.equal(hairballs(log), 1, "the second file is not refused");
  assert.equal(e.catching, false);
  const ball = makeEngine(PRESETS.momo);
  ball.e.fileDrop("archive.tar.gz"); ball.e.fileRefuse(); ball.e.fileArrived();
  let ext = null;
  for (let f = 1; f <= 120; f++) { ball.step(f); if (ball.e.balls[0]) ext = ball.e.balls[0].file; }
  assert.equal(ext, "GZ");
  const bare = makeEngine(PRESETS.momo);
  bare.e.fileDrop("Makefile"); bare.e.fileRefuse(); bare.e.fileArrived();
  let ext2 = null;
  for (let f = 1; f <= 120; f++) { bare.step(f); if (bare.e.balls[0]) ext2 = bare.e.balls[0].file; }
  assert.equal(ext2, "FILE", "a file with no extension shows FILE");
});

// What the cat plays during a catch. `Sound.play` is swapped for a recorder while the script runs (in plain Node it plays nothing anyway), so each sound
// comes with the frame it was played at. The cat's one sound for a refused file is `annoyed`, once, as the gag starts (the file has reached the mouth and
// the app has refused it, whichever came last); the hairball and the note after it are silent. Stage 3 of the sound spec adds `pop` at the cough.
const heard = (script) => {
  const played = [], { e, step } = makeEngine(PRESETS.shrimpy);
  let f = 0;
  Sound.play = (name) => { played.push([f, name]); };
  try {
    script(e, (frames) => { for (let i = 0; i < frames; i++) step(++f); });
    for (let i = 0; i < 60 * 4; i++) step(++f); // the heaves, the hairball and the roll that follow
  } finally {
    delete Sound.play; // back to the engine's own method
  }
  return played;
};

test("the cat plays annoyed once, when the gag starts, and nothing else: not at the hover, the drop, the hairball or the roll", () => {
  // The app's refusal comes before the file reaches the mouth: the gag starts when the file arrives (frame 40), not before.
  assert.deepEqual(heard((e, wait) => { e.fileHover(true); wait(30); e.fileDrop("setup.exe"); e.fileRefuse(); wait(10); e.fileArrived(); }), [[40, "annoyed"]]);
  // It comes after the file has arrived: the gag starts at once (frame 28), and a second refusal does not play it again.
  assert.deepEqual(heard((e, wait) => { e.fileHover(true); e.fileDrop("a.zip"); wait(23); e.fileArrived(); wait(5); e.fileRefuse(); e.fileRefuse(); }), [[28, "annoyed"]]);
  // A refused file, then a taken one: one annoyed in all.
  const two = heard((e, wait) => { e.fileHover(true); e.fileDrop("x.exe"); e.fileRefuse(); wait(23); e.fileArrived(); wait(60 * 4); e.fileHover(true); e.fileDrop("b.pdf"); wait(23); e.fileArrived(); });
  assert.deepEqual(two.map((s) => s[1]), ["annoyed"]);
});

test("a file that is taken makes no sound, and a hairball that is not a refusal makes none either", () => {
  assert.deepEqual(heard((e, wait) => { e.fileHover(true); wait(30); e.fileDrop("notes.pdf"); wait(23); e.fileArrived(); }), []);
  assert.deepEqual(heard((e) => e.emote("hairball")), [], "the hairball's pop is the sound spec's Stage 3, not here");
  assert.deepEqual(heard((e, wait) => { e.fileHover(true); wait(20); e.fileHover(false); }), [], "a file that hovers and leaves");
});

// The drop view's canvas only updates the cat while the drop sequence is active, so when the user leaves (Esc, the island hides) the cat's
// clock of delayed calls freezes. The next drag must not fire what was left over: no ghost hairball or ball with the old file's extension,
// no lick or sparks from the old chew, nothing of the old catch.
test("a left drop's pending callbacks do not fire on the next drag: after a refusal, a short gag, a long idle and a new hover", () => {
  // 4 frames: the gag is 100 ms old and the hairball launch (120 ms) is pending; 18 frames: it has launched and its spit (1110 ms) and lick are pending.
  for (const gag of [4, 18]) {
    const log = [], { e, step } = makeEngine(PRESETS.shrimpy, { log });
    e.fileHover(true); step(1); e.fileDrop("setup.exe"); step(2); e.fileRefuse(); e.fileArrived(); // the gag starts here
    for (let f = 3; f <= 2 + gag; f++) step(f);
    const launched = hairballs(log), back = 2 + gag + 60 * 60; // the user left; a minute later a new drag comes
    assert.equal(launched, gag === 4 ? 0 : 1);
    assert.equal(e.balls.length, 0);
    e.fileHover(true);
    step(back); // the first update of the new drag
    assert.equal(e.balls.length, 0, `${gag}: no ghost ball`);
    assert.equal(hairballs(log), launched, `${gag}: no new hairball launches`);
    assert.equal(e.tw.blush, undefined, `${gag}: and none of its tweens start`);
    for (let f = back + 1; f <= back + 60 * 4; f++) step(f);
    assert.equal(e.balls.length, 0, `${gag}: nothing comes up later either`);
    assert.equal(hairballs(log), launched);
    assert.equal(e.fileStep, "hover");
  }
});

test("a left drop's pending lick and sparks do not fire on the next drag either, and a ball that was frozen mid-flight is gone", () => {
  const log = [], { e, step } = makeEngine(PRESETS.shrimpy, { log });
  e.fileHover(true); e.fileDrop("a.pdf"); step(1); e.fileArrived();
  for (let f = 2; f <= 20; f++) step(f); // the lick (950 ms) and the sparks (1000 ms) have not come yet
  e.fileHover(true);
  step(20 + 60 * 60);
  assert.equal(e.parts.length, 0, "no sparks from the old chew");
  assert.equal(log.filter((l) => l[1] === "lick").length, 0, "no lick");
  const r = makeEngine(PRESETS.shrimpy);
  r.e.fileHover(true); r.e.fileDrop("b.zip"); r.e.fileRefuse(); r.e.fileArrived();
  let f = 0;
  while (!r.e.balls.length && f < 60 * 4) r.step(++f);
  assert.equal(r.e.balls.length, 1, "the ball is out");
  r.e.fileHover(true); // a new drag while the old ball is frozen in the air
  r.step(f + 60 * 60);
  assert.equal(r.e.balls.length, 0, "a new drag starts clean");
});

test("a normal sequence still plays after the clean-up: hover, drop, arrive, gulp and chew", () => {
  const log = [], { e, step } = makeEngine(PRESETS.shrimpy, { log });
  let f = 0;
  e.fileHover(true); for (let i = 0; i < 10; i++) step(++f);
  e.fileDrop("n.pdf"); for (let i = 0; i < 23; i++) step(++f);
  e.fileArrived();
  let chewed = 0, sparks = 0;
  for (let i = 0; i < 90; i++) { step(++f); if (e.chew > 0) chewed++; sparks = Math.max(sparks, e.parts.length); }
  assert.ok(chewed > 40, "chews");
  assert.ok(sparks > 0, "sparks");
  assert.equal(log.filter((l) => l[1] === "lick").length, 1, "licks once");
  assert.equal(hairballs(log), 0);
});

// A drop that has finished (its chew, or its hairball and the ball rolling away) is over: the flow ends in "none", so the next drag's clean-up
// (see above) only ever runs for a drop that was left in the middle, and never cuts short a hairball or a dust cloud that has nothing to do with a file.
const finished = (refused) => {  // refused: false (taken), true (refused before it arrives), "after" (refused once it has arrived: the app's usual, asynchronous answer)
  const log = [], { e, step } = makeEngine(PRESETS.shrimpy, { log });
  let f = 0;
  const wait = (frames) => { for (let i = 0; i < frames; i++) step(++f); };
  e.fileHover(true); wait(10); e.fileDrop("a.zip"); if (refused === true) e.fileRefuse(); wait(23); e.fileArrived();
  if (refused === "after") { wait(5); e.fileRefuse(); }
  wait(60 * 5);
  return { e, log, wait };
};

for (const refused of [false, true, "after"]) {
  const kind = refused === "after" ? "refused after it arrived" : refused ? "refused" : "taken";
  test(`a finished drop (${kind}) ends the flow: the next hover does not cut short a hairball that is under way`, () => {
    const { e, log, wait } = finished(refused);
    assert.equal(e.fileStep, "none", "the flow is over");
    e.hairball(); // an unrelated one (the Playful error hiss, say)
    wait(60 * 1.3); // the ball is out and rolling
    assert.equal(e.balls.length, 1, "the ball is in flight");
    e.fileHover(true);
    wait(1);
    assert.equal(e.balls.length, 1, "a new drag leaves it alone");
    assert.equal(hairballs(log), refused ? 2 : 1);
  });

  test(`a finished drop (${kind}) ends the flow: the next hover does not cut short a hairball whose ball is still to come, or a dust cloud`, () => {
    const { e, wait } = finished(refused);
    e.hairball();
    e.zoomies();
    wait(60 * 0.8); // the dust of the first dash is out; the hairball's ball (1110 ms) and the zoomies' second cloud are still pending
    assert.ok(e.parts.some((p) => p.k === "dust"), "dust is in the air");
    const dust = e.parts.length;
    e.fileHover(true);
    wait(1);
    assert.ok(e.parts.length >= dust, "a new drag leaves the dust alone");
    wait(60 * 1);
    assert.equal(e.balls.length, 1, "and the hairball still comes up");
  });
}

test("a refusal that comes after the arrival: the flow lasts until the hairball's ball has rolled away, and a drag left mid-flow is still cleaned up", () => {
  const log = [], { e, step } = makeEngine(PRESETS.shrimpy, { log });
  let f = 0;
  const wait = (frames) => { for (let i = 0; i < frames; i++) step(++f); };
  e.fileHover(true); wait(10); e.fileDrop("a.zip"); wait(23); e.fileArrived(); wait(5); e.fileRefuse();
  wait(60 * 2.4); // past the end of the gulp and chew, with the ball in the air
  assert.equal(e.balls.length, 1, "the ball is airborne");
  assert.equal(e.fileStep, "arrived", "the flow is not over yet");
  e.fileHover(true); // the user left and came back
  assert.equal(e.balls.length, 0, "the frozen ball is cleared");
  wait(60 * 4);
  assert.equal(e.balls.length, 0);
  assert.equal(hairballs(log), 1);
});
