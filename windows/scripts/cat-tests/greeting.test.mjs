import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { GREET_END, GREET_LEN, GT, GT2, GT3, Greeting, MINI_CELL, MINI_FROM, MINI_GRID, MINI_MIN_D, MINI_ROW, STREAKS, greetingPose, greetingShown, miniGlide, miniSlots, streakTime } from "../../src/cat/greeting.ts";
import { COMPACT_W, NOTCH_H } from "../../src/core/layout.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";
import { finite, load, near, same } from "./util.mjs";

const seq = load("sequence-cases.json");

test("the greeting's beats and streaks are the fixture's, and it is still 5.74 s", () => {
  assert.equal(GREET_LEN, seq.greetingLengthS);
  near(GREET_LEN, 5.74);
  const tl = seq.greetingTimeline;
  same({ ...GT }, Object.fromEntries(Object.keys(GT).map((k) => [k, tl[k]])), "GT");
  same({ ...GT2 }, Object.fromEntries(Object.keys(GT2).map((k) => [k, tl[`v2_${k}`]])), "GT2");
  same(STREAKS, seq.greetingStreaks, "streaks");
  near(streakTime(GT2.land), 0.1);
});

test("the greeting pose, every 100 ms and at each beat, is the fixture's", () => {
  assert.ok(seq.greetingSamples.length > 60);
  for (const s of seq.greetingSamples) same(greetingPose(s.tMs / 1000), s.pose, `t = ${s.tMs} ms`);
});

test("a greeting cut short (the pointer left) continues from where the cat is, and settles in the compact notch", () => {
  for (const tc of [0.3, 1.0, 2.0, 3.0, 4.0, 4.6]) {
    const here = greetingPose(tc), start = greetingPose(tc, tc);
    for (const k of ["x", "y", "hb", "sx", "sy", "tilt", "lookX", "lookY", "handL", "handR", "badge", "tint"]) near(start[k], here[k], 1e-9);
    const end = greetingPose(tc + GT.COLLAPSE + 0.6, tc);
    near(end.hb * 1.34, 20);
    near(end.x, 320 - 288 / 2 + 40);
    near(end.y, 16);
    assert.equal(end.minis, 1);
    assert.equal(end.handR, 0);
  }
  same(greetingPose(5, GT.leave), greetingPose(5), "the default leave is GT.leave");
});

test("the greeting never gives a bad number, before it starts or long after it ends", () => {
  for (const t of [-5, -0.001, 0, 3, GT.leave, GREET_LEN, 60, 1e6]) finite(greetingPose(t), `t = ${t}`);
  assert.equal(greetingPose(-1).card, 0);
});

/** Draws the greeting at second `t` on a canvas that records its text and translations; the clock is the test's. `tc` is when the pointer left, if it did. */
function drawAt(t, tc) {
  installBrowserStubs();
  const g = new Greeting();
  if (tc !== undefined) g.tc = tc;
  Object.defineProperty(g, "elapsed", { get: () => t });
  const ctx = fakeCanvas(), texts = [], moves = [], scales = [];
  ctx.fillText = (text, x, y) => texts.push({ text, x, y, alpha: ctx.globalAlpha, align: ctx.textAlign });
  const translate = ctx.translate, scale = ctx.scale;
  ctx.translate = (x, y) => { moves.push([x, y]); return translate(x, y); };
  ctx.scale = (x, y) => { scales.push([x, y]); return scale(x, y); };
  g.draw(ctx);
  return { g, texts, moves, scales };
}

test("the header is drawn: the app's name on the left and the greeting on the right, fading in with the card", () => {
  assert.deepEqual(drawAt(0.2).texts, [], "not before the card starts to fade in");
  const half = drawAt(0.475).texts;
  assert.equal(half.length, 2);
  near(half[0].alpha, 0.5);
  const full = drawAt(2).texts;
  assert.deepEqual(full.map((x) => [x.text, x.x, x.y, x.align, x.alpha]), [
    ["NotchMeow", 20, 20, "left", 1],
    ["Hi! Shrimpy is watching your agents.", 620, 20, "right", 1],
  ]);
  assert.deepEqual(drawAt(5.5).texts, [], "gone once the island has collapsed");
});

/** The session cats a draw at `t` put on the canvas: the translations near the compact island's right end, in the order drawn. */
const catsAt = (t, tc) => drawAt(t, tc).moves.filter(([x, y]) => x > 400 && y < 30);
/** The slots the contract says are on screen at `t`, for the greeting's own island (the pose's `minis` and the glide at the same `leave`). */
const slotsAt = (t, leave = GT.leave) => miniSlots(greetingPose(t, leave).minis, miniGlide(t, leave), { d: MINI_GRID.d }).filter((c) => c.d >= MINI_MIN_D);

test("the session cats pop in as a row of three, glide into the compact island's grid, and a fourth joins, blue-tinted", () => {
  assert.equal(catsAt(4).length, 0, "none before the island collapses");
  assert.equal(catsAt(GT.leave + 0.2).length, 0, "nor before the row starts to pop in, 0.24 s after the island starts to fold");
  const row = catsAt(GT.leave + 0.6), right = 320 + 288 / 2;
  assert.deepEqual(row.map(([x, y]) => [Math.round(x), Math.round(y)]).sort((a, b) => a[0] - b[0]), [[right - 40, 17], [right - 26, 17], [right - 12, 17]], "the prototype's row: three cats, 14 px apart, 12 px in from the right edge");
  const mid = catsAt(GT.leave + 1.1);
  assert.equal(mid.length, 4, "the fourth cat has started to pop in by the middle of the glide's second half");
  for (const [t, n] of [[GT.leave + 0.3, 3], [GT.leave + 0.6, 3], [GT.leave + 0.95, 3], [GT.leave + 1.05, 4], [GT.leave + GT3.end, 4]]) {
    const want = slotsAt(t), got = catsAt(t);
    assert.equal(got.length, n, `${n} cats at ${t - GT.leave} s after the fold starts`);
    assert.deepEqual(got.map(([x, y]) => [Math.round(x * 1e6), Math.round(y * 1e6)]), want.map((c) => [Math.round(c.x * 1e6), Math.round(c.y * 1e6)]), `drawn where the contract puts them at ${t}`);
  }
  const { g } = drawAt(GT.leave + 1);
  assert.equal(g.minis.s.tint, 0.6);
  assert.deepEqual(g.minis.col, [127, 180, 234]);
});

test("the last frame of the greeting is the grid's four cells, level with the island's right end", () => {
  const end = catsAt(GREET_END + 0.5).map(([x, y]) => [x, y]);
  const cells = [[-1, -1], [1, -1], [-1, 1], [1, 1]].map(([dx, dy]) => [MINI_GRID.x + (dx * MINI_GRID.step) / 2, MINI_GRID.y + (dy * MINI_GRID.step) / 2]);
  assert.equal(end.length, 4);
  end.forEach(([x, y], i) => { near(x, cells[i][0]); near(y, cells[i][1]); });
});

test("the glide's beats, samples and slot cases are the fixture's", () => {
  same({ ...GT3, greetEnd: GREET_END }, seq.miniTimeline, "timeline");
  const geo = seq.miniGeometry;
  same({ row: MINI_ROW, from: MINI_FROM, minD: MINI_MIN_D, grid: { step: MINI_CELL.step, inset: MINI_CELL.inset } }, { row: geo.row, from: geo.from, minD: geo.minD, grid: { step: geo.grid.step, inset: geo.grid.inset } }, "geometry");
  assert.equal(MINI_GRID.d, 13, "this app's cats are Ø13: the fixture's Ø12 is the Mac's, and the cases pass d");
  assert.ok(seq.miniGlideSamples.length >= 40 && seq.miniSlotCases.length >= 40);
  for (const c of seq.miniGlideSamples) same(miniGlide(c.tMs / 1000, c.leave), c.glide, `leave ${c.leave}, ${c.tMs} ms`);
  for (const c of seq.miniSlotCases) same(miniSlots(c.minis, { grid: c.grid, four: c.four }, { W: c.W, H: c.H, d: c.d }), c.slots, `${c.name}, ${c.tMs} ms`);
  near(GREET_LEN, 5.74);
  near(GREET_END, 6.5);
});

test("a greeting cut short (the pointer left) runs the same beat from where it left, and never moves it later", () => {
  for (const tc of [0.3, 2.0, 3.0]) {
    assert.equal(catsAt(tc + 0.2, tc).length, 0, `leave ${tc}: nothing yet`);
    assert.equal(catsAt(tc + 0.6, tc).length, 3, `leave ${tc}: the row`);
    const end = catsAt(tc + GT3.end, tc), cells = slotsAt(GT.leave + GT3.end);
    assert.equal(end.length, 4, `leave ${tc}: the grid`);
    end.forEach(([x, y], i) => { near(x, cells[i].x); near(y, cells[i].y); });
  }
  // Collapse pressed while the glide is under way: the greeting has been folding since 4.9 s already, so the glide goes on untouched.
  for (const t of [GT.leave + 0.9, GT.leave + 1.1]) assert.deepEqual(catsAt(t, t - 0.05), catsAt(t), `an interrupt at ${t - 0.05} s changes nothing`);
});

test("the greeting is live from start() to the end of the last beat, says so once, and a replay is live again", () => {
  installBrowserStubs();
  globalThis.window = { setTimeout: () => 0, clearTimeout: () => {} };
  const g = new Greeting();
  let ended = 0, t = 0;
  g.onEnd = () => { ended += 1; };
  Object.defineProperty(g, "elapsed", { get: () => t });
  assert.equal(g.live, false, "not before it starts");
  g.start();
  assert.equal(g.live, true);
  const ctx = fakeCanvas();
  for (t of [0, 3, GT.leave + GT3.end - 0.01]) { g.draw(ctx); assert.equal(g.live, true, `t = ${t}`); }
  t = GT.leave + GT3.end; g.draw(ctx);
  assert.equal(g.live, false);
  assert.equal(ended, 1);
  g.draw(ctx);
  assert.equal(ended, 1, "once");
  g.start();
  assert.equal(g.live, true, "a replay is live again");
  g.tc = 2;
  t = 2 + GT3.end - 0.01; g.draw(ctx);
  assert.equal(g.live, true);
  t = 2 + GT3.end; g.draw(ctx);
  assert.equal(g.live, false, "an early leave ends the beat 1.6 s after it");
  assert.equal(ended, 2);
  delete globalThis.window;
});

test("end() stops the beat at once without saying so, and a replay is live again", () => {
  globalThis.window = { setTimeout: () => 0, clearTimeout: () => {} };
  const g = new Greeting();
  let ended = 0;
  g.onEnd = () => { ended += 1; };
  g.start();
  g.end();
  assert.equal(g.live, false);
  assert.equal(ended, 0, "silent: the island is already syncing");
  g.start();
  assert.equal(g.live, true, "a replay is live again");
  delete globalThis.window;
});

test("the greeting canvas is up in the greeting view and through the compact tail, and nowhere else", () => {
  assert.equal(greetingShown("expanded", "greeting", false), true, "the greeting view of the expanded island");
  assert.equal(greetingShown("expanded", "greeting", true), true);
  assert.equal(greetingShown("compact", "overview", true), true, "the compact island while the last beat is live");
  assert.equal(greetingShown("compact", "overview", false), false, "the compact island once the beat is over");
  assert.equal(greetingShown("expanded", "overview", true), false, "the user opened the island during the tail: it ends at once");
  assert.equal(greetingShown("expanded", "approval", true), false, "a hook event expanded it");
  assert.equal(greetingShown("hidden", "greeting", true), false, "a hidden island shows nothing");
  assert.equal(greetingShown("hidden", "overview", true), false);
});

test("the session cats sit where the compact island's real mini grid does: this app's grid, not the Mac's", () => {
  const island = fs.readFileSync(new URL("../../src/island/island.ts", import.meta.url), "utf8");
  const css = fs.readFileSync(new URL("../../src/style.css", import.meta.url), "utf8");
  const box = css.match(/#mini-grid \{[^}]*\}/)[0];
  const cell = Number(box.match(/grid-template-columns: (\d+)px/)[1]), gap = Number(box.match(/gap: (\d+)px/)[1]);
  const body = Number(island.match(/createMiniBot\(task, (\d+), cat\)/)[1]);
  const left = island.match(/miniGrid\.style\.left = `\$\{w - (\d+) - ([\d.]+)\}px`/), top = island.match(/miniGrid\.style\.top = `\$\{hh \/ 2 - ([\d.]+)\}px`/);
  const half = (2 * cell + gap) / 2; // the grid's box is 2 cells and a gap wide: its centre is half of that in from its left edge
  assert.deepEqual([MINI_GRID.d, MINI_GRID.step], [body, cell + gap], "the head width and the spacing of the real grid");
  assert.equal(Number(left[2]), half, "the grid's left edge is its centre minus half its width");
  assert.equal(MINI_GRID.x, 320 - COMPACT_W / 2 + (COMPACT_W - Number(left[1])), "40 px in from the island's right edge, in the 640 wide canvas");
  assert.equal(Number(top[1]), half);
  assert.equal(MINI_GRID.y, NOTCH_H / 2, "level with the middle of the strip");
  // The last beat's end state is exactly those four cells: the cell centres are `step / 2` either side of the grid's centre, Ø13, nothing shrunk.
  const end = miniSlots(1, miniGlide(GREET_END), { d: body });
  [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(([dx, dy], i) => {
    near(end[i].x, MINI_GRID.x + (dx * (cell + gap)) / 2); near(end[i].y, MINI_GRID.y + (dy * (cell + gap)) / 2); near(end[i].d, cell);
  });
});
