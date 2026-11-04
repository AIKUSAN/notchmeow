import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const require = createRequire(import.meta.url);
const core = require('../../design/prototype/cat-core.js');
const seq = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/sequence-cases.json', import.meta.url), 'utf8'));
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const ROW = { grid: 0, four: 0 }, GRID = { grid: 1, four: 1 };

/**
 * What the compact island really lays out, written the way the views write it and not the way the contract does: a 28 x 28 frame with two
 * columns of 12 pt cells 4 apart, scaled about its centre by min(1, (H - 4) / 28) (IslandRootView.swift: CompactMiniGrid, miniGridScale)
 * and centred 40 in from the island's right edge, level with the middle of the strip. On Windows the cells are 13 px and the gap 3
 * (style.css: #mini-grid), which is the same 16 between centres. Returns the four cells' centres in the 640-wide canvas, whose centre is the island's.
 */
function realGrid(W, H, cell, gap) {
  const k = Math.min(1, Math.max(0, H - 4) / 28), frame = 2 * cell + gap;
  return [[0, 0], [1, 0], [0, 1], [1, 1]].map(([c, r]) => ({
    x: 320 - W / 2 + (W - 40) + (c * (cell + gap) + cell / 2 - frame / 2) * k,
    y: H / 2 + (r * (cell + gap) + cell / 2 - frame / 2) * k,
    d: cell * k,
  }));
}

test('GREET_LEN stays 5.74 s; the greeting as a whole now ends at GREET_END, 1.6 s after the island starts to fold', () => {
  near(core.GREET_LEN, 5.74);
  assert.deepEqual(core.GT3, { glide0: 0.8, glide1: 1.3, four0: 1, end: 1.6 });
  near(core.GREET_END, core.GT.leave + 1.6);
  near(core.GREET_END, 6.5);
  assert.ok(core.GREET_END > core.GREET_LEN);
  assert.ok(core.GT3.glide0 > 0.42, 'the row has finished popping in (collapsePose: 0.24 to 0.42 s after leave) before it glides');
  assert.ok(core.GT3.glide1 < core.GT3.end, 'and the grid holds for a moment before the hand-over');
  assert.ok(core.GT3.four0 > core.GT3.glide0 && core.GT3.four0 < core.GT3.glide1, 'the fourth cat pops in while the others land');
});

test('the glide: nothing before it, the grid after it, and it follows `leave`', () => {
  const L = core.GT.leave;
  const is = (g, want) => { near(g.grid, want.grid); near(g.four, want.four); };   // EZ.back(0) is -2.2e-16, as `minis` is before the row pops in
  is(core.miniGlide(0), ROW);
  is(core.miniGlide(L + core.GT3.glide0), ROW);
  is(core.miniGlide(L + core.GT3.glide1), GRID);
  is(core.miniGlide(1e6), GRID);
  is(core.miniGlide(-5), ROW);
  let prev = 0, top = 0;
  for (let i = 0; i <= 4000; i++) {
    const g = core.miniGlide(L + i / 1000), t = L + i / 1000;
    assert.ok(g.grid >= prev - 1e-12 && g.grid <= 1, `the glide is monotone and never past the grid (${g.grid} at ${t})`);
    assert.ok(g.four >= -1e-12 && g.four < 1.11, `the fourth cat's pop stays between 0 and 1.1 (${g.four} at ${t})`);
    prev = g.grid; top = Math.max(top, g.four);
  }
  assert.ok(top > 1.05, `the fourth cat pops with a little overshoot, like the row (${top})`);
  for (const leave of [0.3, 1.0, 2.5, 4.9]) for (const o of [0, 0.5, 0.9, 1.1, 1.3, 2]) {
    const a = core.miniGlide(leave + o, leave), b = core.miniGlide(L + o);
    near(a.grid, b.grid); near(a.four, b.four);
  }
});

test('the row: three cats, the prototype\'s numbers, and no fourth cat yet', () => {
  const s = core.miniSlots(1, ROW);
  assert.equal(s.length, 4);
  // The grid's cells run top left, top right, bottom left, bottom right; the row cats come from MINI_FROM = [2, 1, none, 0].
  const right = 320 + core.COMPACT / 2;
  for (const [cell, from] of [[0, 2], [1, 1], [3, 0]]) {
    near(s[cell].x, right - (12 + 14 * from)); near(s[cell].y, 17); near(s[cell].d, 11);
  }
  assert.equal(s[2].d, 0, 'the bottom left is empty in the row');
  assert.deepEqual(core.miniSlots(0, ROW).map(c => c.d), [0, 0, 0, 0], 'before the pop-in nothing is drawn');
  near(core.miniSlots(1, ROW)[0].x, 320 + core.COMPACT / 2 - 40, 1e-9);   // the row's left-most cat sits where the grid's centre is
});

test('the end of the glide is the compact island\'s real grid, on the Mac, on the Windows app, on a notch and without one', () => {
  for (const [W, H, d, cell, gap] of [[288, 32, 12, 12, 4], [344, 38, 12, 12, 4], [344, 32, 12, 12, 4], [240, 24, 12, 12, 4], [288, 32, 13, 13, 3], [300, 20, 13, 13, 3]]) {
    const want = realGrid(W, H, cell, gap), got = core.miniSlots(1, GRID, { W, H, d });
    got.forEach((s, i) => { near(s.x, want[i].x); near(s.y, want[i].y); near(s.d, want[i].d); });
  }
});

test('the glide never has two cats on top of each other, and every cat stays inside the strip it is drawn in', () => {
  for (const { W, H, d } of [{ W: 288, H: 32, d: 12 }, { W: 344, H: 38, d: 12 }, { W: 288, H: 32, d: 13 }]) {
    let tightest = Infinity;
    for (let i = 0; i <= 1000; i++) {
      const g = { grid: core.EZ.inOut(i / 1000), four: i / 1000 > 0.65 ? 1 : 0 }, s = core.miniSlots(1, g, { W, H, d });
      for (let a = 0; a < 4; a++) for (let b = a + 1; b < 4; b++) if (s[a].d && s[b].d) tightest = Math.min(tightest, Math.hypot(s[a].x - s[b].x, s[a].y - s[b].y) / ((s[a].d + s[b].d) / 2));
      for (const c of s) if (c.d) assert.ok(c.y - c.d / 2 >= 0 && c.y + c.d / 2 <= Math.max(H, 32), `a cat leaves the strip at ${i / 1000}: ${JSON.stringify(c)}`);
    }
    assert.ok(tightest > 0.85, `two cats come within ${tightest.toFixed(3)} of a head width of each other`);
  }
});

test('a short strip shrinks the cats as the Mac\'s miniGridScale does, and a cat under MINI_MIN_D is not drawn', () => {
  near(core.miniSlots(1, GRID, { H: 24 })[0].d, 12 * 20 / 28);
  near(core.miniSlots(1, GRID, { H: 38 })[0].d, 12);
  assert.deepEqual(core.miniSlots(1, GRID, { H: 4 }).map(c => c.d), [0, 0, 0, 0]);
  assert.deepEqual(core.miniSlots(1, GRID, { H: 0 }).map(c => c.d), [0, 0, 0, 0]);
  assert.deepEqual(core.miniSlots(1, GRID, { H: -10 }).map(c => c.d), [0, 0, 0, 0]);
  assert.equal(core.MINI_MIN_D, 2);
  for (const m of [0.001, 0.1, 0.17, 0.18]) for (const c of core.miniSlots(m, ROW)) assert.ok(c.d === 0 || c.d >= 2, `d = ${c.d} at a pop of ${m}`);
});

test('every slot is finite whatever time, leave or island it is asked for', () => {
  for (const t of [-5, 0, 3, 5.3, 6, 6.5, 100, 1e6]) for (const leave of [0, 1, 4.9, 50]) for (const H of [0, 6, 24, 32, 200]) {
    const g = core.miniGlide(t, leave);
    for (const s of core.miniSlots(core.EZ.back(core.seg(t, leave + 0.24, leave + 0.42)), g, { W: 288, H, d: 12 })) for (const [k, v] of Object.entries(s)) assert.ok(Number.isFinite(v), `${k} at t ${t}, leave ${leave}, H ${H}`);
  }
});

test('sequence-cases.json: the glide timeline, its samples and the slot cases replay from the module', () => {
  assert.deepEqual(seq.miniTimeline, { ...core.GT3, greetEnd: core.GREET_END });
  assert.deepEqual(seq.miniGeometry, { row: core.MINI_ROW, grid: core.MINI_GRID, from: core.MINI_FROM, minD: core.MINI_MIN_D });
  assert.ok(seq.miniGlideSamples.length >= 40 && seq.miniSlotCases.length >= 40);
  for (const c of seq.miniGlideSamples) { const d = compare(core.miniGlide(c.tMs / 1000, c.leave), c.glide); assert.deepEqual(d, [], `leave ${c.leave}, ${c.tMs} ms`); }
  for (const c of seq.miniSlotCases) {
    const d = compare(core.miniSlots(c.minis, { grid: c.grid, four: c.four }, { W: c.W, H: c.H, d: c.d }), c.slots);
    assert.deepEqual(d, [], `${c.name}, ${c.tMs} ms`);
  }
  const leaves = new Set(seq.miniGlideSamples.map(c => c.leave));
  assert.deepEqual([...leaves], [core.GT.leave, 1, 3], 'the timeline\'s own leave and two early ones');
  assert.ok(seq.miniSlotCases.some(c => c.H === 24) && seq.miniSlotCases.some(c => c.d === 13) && seq.miniSlotCases.some(c => c.H === 6), 'a short strip, the Windows cat and a strip too short for a cat are covered');
});

test('the greeting\'s existing fixtures are untouched: no pose gains a key, no length changes', () => {
  assert.deepEqual(Object.keys(core.greetingPose(5.5)), ['iw', 'ih', 'hb', 'x', 'y', 'sx', 'sy', 'tilt', 'eye', 'lookX', 'lookY', 'handL', 'handR', 'wave', 'open', 'badge', 'tint', 'halo', 'haloBlue', 'header', 'card', 'fx', 'minis']);
  assert.equal(seq.greetingLengthS, core.GREET_LEN);
  assert.equal(seq.greetingSamples.at(-1).tMs, 5800);
});
