import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import * as W from "../../src/island/wing.ts";

// The cases of tests/IslandWingTests.swift (the Mac), in the same order. The Mac's y axis points up and the page's down: the island's strip is y 0..32 here, the Mac's 288..320.
const tick = (y, t, zone, { active = true, button = false } = {}) => y.step(t, zone, active, () => button);
const out = (faded, passThrough) => ({ faded, passThrough });
const near = (a, b) => assert.ok(Math.abs(a - b) <= 1e-9, `${a} is not ${b}`);

test("the numbers the owner chose, and the Mac's file still says the same", () => {
  near(W.FADE_OUT, 0.15);
  near(W.RETURN_DELAY, 1.0);
  assert.ok(W.FADE_IN >= W.FADE_OUT && W.FADE_IN < W.RETURN_DELAY);
  near(W.SPRING_RESPONSE, 0.22);
  assert.ok(W.SPRING_DAMPING < 1 && W.SPRING_DAMPING > 0.5);
  near(W.LEFT_DWELL, 0.4);
  // The drift pin: the Swift constants are read from the Swift file, so changing one side alone fails here.
  const swift = fs.readFileSync(new URL("../../../NotchBuddy/Sources/App/IslandWing.swift", import.meta.url), "utf8");
  const num = (name) => Number(new RegExp(`static let ${name}: (?:TimeInterval|Double) = ([0-9.]+)`).exec(swift)?.[1]);
  near(num("fadeOut"), W.FADE_OUT);
  near(num("fadeIn"), W.FADE_IN);
  near(num("returnDelay"), W.RETURN_DELAY);
  near(num("leftDwell"), W.LEFT_DWELL);
  near(num("springResponse"), W.SPRING_RESPONSE);
  near(num("springDamping"), W.SPRING_DAMPING);
});

test("the two wings: the parts beside the notch", () => {
  const island = { x: 188, y: 0, w: 344, h: 32 };
  const w = W.wings(island, 184);
  assert.deepEqual([w.left.x, w.left.x + w.left.w], [188, 268], "the left wing runs from the island's left edge to the notch's left edge");
  assert.deepEqual([w.right.x, w.right.x + w.right.w], [452, 532]);
  assert.deepEqual([w.left.y, w.left.y + w.left.h, w.right.y, w.right.y + w.right.h], [0, 32, 0, 32], "both are the strip's height");
  const inAny = (x, y) => W.zoneOf(w, x, y) !== null;
  assert.ok(!inAny(360, 16) && !inAny(268.1, 16) && !inAny(451.9, 16), "the notch is in neither: it is the hover-open zone");
  assert.ok(inAny(188, 16) && inAny(267.9, 16) && inAny(452, 16) && inAny(531.9, 16), "the first and last points of each wing are in it");
  const slopped = W.wings(island, 184, 6);
  assert.deepEqual([slopped.left.x, slopped.left.x + slopped.left.w, slopped.right.x, slopped.right.x + slopped.right.w, slopped.left.y, slopped.right.y + slopped.right.h], [182, 268, 452, 538, -6, 38],
    "with the hover slop each wing reaches further out, up and down, and not towards the notch");
  const bar = W.wings({ x: 240, y: 0, w: 240, h: 24 }, 80);
  assert.deepEqual([bar.left.w, bar.right.w, bar.right.h], [80, 80, 24], "the same rule around an 80 px bar");
  const none = W.wings({ x: 100, y: 0, w: 50, h: 30 }, 184);
  assert.deepEqual([none.left.w, none.right.w], [0, 0], "an island narrower than its notch has no wing at all");
  // The PC's compact island: 288 wide, the 184 px middle, 52 px a side; the page's hit margin is 14 px.
  const pc = W.wings({ x: 216, y: 0, w: 288, h: 32 }, 184, 14);
  assert.deepEqual([pc.left.x, pc.left.w, pc.right.x, pc.right.w], [202, 66, 452, 66]);
});

test("what the island folds to", () => {
  assert.equal(W.foldedWidth(184), 184);
  assert.equal(W.widthAt(344, 184, 0), 344);
  assert.equal(W.widthAt(344, 184, 1), 184);
  assert.equal(W.widthAt(344, 184, 0.5), 264);
});

test("click-through while folded, and the fade, one frame at a time", () => {
  assert.deepEqual(W.foldedHitRect(720, 32, 184, 14), { x: 282, y: 0, w: 156, h: 32 }, "the middle shrunk by the 14 px margin on each side: the window adds it back and covers exactly the notch-wide middle");
  const r = W.foldedHitRect(720, 32, 184, 14);
  assert.deepEqual([r.x - 14, r.x + r.w + 14], [268, 452], "no dead band beside the middle: the wing zones start where it ends");
  assert.equal(W.foldedHitRect(720, 32, 20, 14).w, 0, "a margin wider than the middle leaves nothing");
  near(W.stepFade(1, true, 0.15), 0);
  near(W.stepFade(1, true, 0.075), 0.5);
  near(W.stepFade(0, false, 0.25), 1);
  near(W.stepFade(0, false, 0.125), 0.5);
  near(W.stepFade(0.2, true, 5), 0);
  near(W.stepFade(0.8, false, 5), 1);
});

test("when the island can step aside", () => {
  assert.ok(W.isActive(true, false, false, false));
  assert.ok(!W.isActive(false, false, false, false), "not hidden or expanded");
  assert.ok(!W.isActive(true, true, false, false), "not while the greeting's tail draws the session cats");
  assert.ok(!W.isActive(true, false, true, false), "not while the cat's head is being dragged");
  assert.ok(!W.isActive(true, false, false, true), "not while an alert wants the island");
});

test("the fold: in at once, out one second after the pointer has left both wings", () => {
  const y = new W.WingYield();
  assert.deepEqual(tick(y, 0, null), out(false, false));
  assert.deepEqual(tick(y, 1.0, "right"), out(true, true), "the pointer reaches a wing: folded, and the mouse passes through on that very tick");
  assert.deepEqual(tick(y, 11.0, "right"), out(true, true), "it stays while the pointer stays (ten seconds)");
  assert.deepEqual(tick(y, 12.0, null), out(true, false), "the pointer leaves: still folded, the mouse no longer passed on");
  assert.deepEqual(tick(y, 12.9, null), out(true, false));
  assert.deepEqual(tick(y, 13.0, null), out(false, false), "1 s after the pointer was first seen away it swooshes back out");
  assert.deepEqual(tick(y, 20.0, null), out(false, false));
});

test("the left wing folds the island only after a 0.4 s rest with no button; the right wing at once", () => {
  let y = new W.WingYield();
  assert.deepEqual(tick(y, 5.0, "left"), out(false, false));
  assert.deepEqual(tick(y, 5.399, "left"), out(false, false));
  assert.deepEqual(tick(y, 5.4, "left"), out(true, true));
  assert.deepEqual(tick(y, 9.0, "left"), out(true, true));
  y = new W.WingYield();
  tick(y, 1.0, "left");
  assert.deepEqual(tick(y, 1.2, "left", { button: true }), out(false, false), "a press at 200 ms cancels the dwell");
  assert.deepEqual(tick(y, 1.4, "left"), out(false, false), "the button released at 400 ms: the dwell starts over");
  assert.deepEqual(tick(y, 1.799, "left"), out(false, false));
  assert.deepEqual(tick(y, 1.8, "left"), out(true, true));
  y = new W.WingYield();
  tick(y, 0, "left");
  tick(y, 0.3, null);
  assert.deepEqual(tick(y, 0.5, "left"), out(false, false), "leaving before the dwell is over cancels it");
  assert.deepEqual(tick(y, 0.899, "left"), out(false, false));
  assert.deepEqual(tick(y, 0.9, "left"), out(true, true));
  y = new W.WingYield();
  assert.deepEqual(tick(y, 0, "right"), out(true, true), "the right wing needs no dwell");
  const held = new W.WingYield();
  for (let t = 0; t <= 3.0001; t += 0.1) tick(held, t, "left", { button: true });
  assert.deepEqual(tick(held, 3.1, "left", { button: true }), out(false, false), "a button held the whole time never folds it");
  const lazy = new W.WingYield();
  let leftAsked = 0;
  for (let i = 0; i < 20; i++) lazy.step(i * 0.01, i < 10 ? null : "left", true, () => (leftAsked++, false));
  assert.equal(leftAsked, 10, "the button is asked only while the pointer is on the left wing");
  const folded = new W.WingYield();
  tick(folded, 0, "right");
  let askedFolded = 0;
  for (let i = 1; i < 10; i++) folded.step(i, "left", true, () => (askedFolded++, false));
  assert.equal(askedFolded, 0, "once folded, the left wing asks nothing and keeps the fold");
});

test("both wings are one hover", () => {
  const y = new W.WingYield();
  tick(y, 0, "right");
  tick(y, 5.0, null);
  assert.deepEqual(tick(y, 5.8, "right"), out(true, true), "back in the other wing at 5.8 s: still folded");
  tick(y, 6.0, null);
  assert.deepEqual(tick(y, 6.9, null), out(true, false), "away again at 6.0 s: 0.9 s later still folded");
  assert.deepEqual(tick(y, 7.0, null), out(false, false));
});

test("the mouse button held: a file dragged in, or a click that began elsewhere", () => {
  const y = new W.WingYield();
  assert.deepEqual(tick(y, 0, "right", { button: true }), out(false, false));
  assert.deepEqual(tick(y, 0.1, "right"), out(true, true), "releasing it over the wing then folds it");
  assert.deepEqual(tick(y, 0.2, "right", { button: true }), out(true, true), "a button pressed over a folded island leaves it folded");
});

test("an alert cancels the step-aside at once, and an inactive island never folds or asks about the button", () => {
  const y = new W.WingYield();
  tick(y, 0, "right");
  assert.deepEqual(tick(y, 0.5, "right", { active: false }), out(false, false));
  assert.deepEqual(tick(y, 0.6, "right", { active: false }), out(false, false));
  assert.deepEqual(tick(y, 0.7, "right"), out(true, true), "when the alert is over and the pointer is still on the wing, a new fold begins");
  const z = new W.WingYield();
  let asked = 0;
  z.step(0, null, true, () => (asked++, false));
  assert.equal(asked, 0);
  z.step(1, "right", true, () => (asked++, false));
  z.step(2, "right", true, () => (asked++, false));
  assert.equal(asked, 1, "asked once, when the fold begins");
  const quiet = new W.WingYield();
  let q = 0;
  for (let i = 0; i < 50; i++) quiet.step(i, i % 2 === 0 ? "right" : null, false, () => (q++, false));
  assert.equal(q, 0);
});

test("a clock that is not a time", () => {
  const y = new W.WingYield();
  tick(y, 0, "right");
  assert.deepEqual(tick(y, NaN, "right"), out(false, false));
  assert.deepEqual(tick(y, Infinity, "right"), out(false, false));
  assert.deepEqual(tick(y, 3, "right"), out(true, true));
  tick(y, 4, null);
  assert.deepEqual(tick(y, 1, null), out(true, false), "a clock that runs backwards does not bring the island back early");
  assert.equal(y.nextDeadline(NaN), null);
});

test("nextDeadline: the one wake-up the page needs, and nothing when nothing is pending", () => {
  const y = new W.WingYield();
  assert.equal(y.nextDeadline(0), null, "at rest: no timer");
  tick(y, 0, "left");
  const d = y.nextDeadline(0.1);
  assert.ok(Math.abs(d - 0.3) < 1e-9, `the dwell ends in about 0.3 s, got ${d}`);
  assert.deepEqual(tick(y, 0.1 + d, "left"), out(true, true), "waking at the deadline folds it");
  assert.equal(y.nextDeadline(1), null, "folded with the pointer on the wing: no timer");
  tick(y, 2, null);
  const r = y.nextDeadline(2.25);
  assert.ok(Math.abs(r - 0.75) < 1e-9, `the return ends in 0.75 s, got ${r}`);
  assert.deepEqual(tick(y, 2.25 + r, null), out(false, false));
  assert.equal(y.nextDeadline(5), null, "back at rest: no timer");
  const right = new W.WingYield();
  tick(right, 0, "right");
  assert.equal(right.nextDeadline(0), null, "the right wing has no dwell");
});

test("fuzz: 20000 ticks that must keep the rules", () => {
  let seed = 12345;
  const rnd = () => ((seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 2 ** 32);
  const f = new W.WingYield();
  let t = 0, broke = 0, lastIn = -100, wasFaded = false;
  for (let i = 0; i < 20000; i++) {
    t += rnd() * 0.05;
    const p = rnd(), zone = p < 0.15 ? "left" : p < 0.3 ? "right" : null, inWing = zone !== null, active = rnd() < 0.95;
    const o = tick(f, t, zone, { active, button: rnd() < 0.05 });
    if (o.passThrough && !o.faded) broke++;
    if (!active && o.faded) broke++;
    if (o.passThrough && !inWing) broke++;
    if (active && inWing && o.faded) lastIn = t;
    if (active && !inWing && wasFaded && !o.faded && t - lastIn < W.RETURN_DELAY) broke++;
    wasFaded = active && o.faded;
  }
  assert.equal(broke, 0);
});
