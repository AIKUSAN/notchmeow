import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const pose = (o = {}) => ({ ...core.newPose(), ...o });
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const nearAll = (got, want) => { assert.equal(got.length, want.length); got.forEach((v, i) => near(v, want[i])); };

test('detailLevel: compact and flat below Ø28, full from Ø28, and an explicit detail wins', () => {
  assert.deepEqual(core.detailLevel(27.999), { detail: 'compact', full: false, flatFill: true });
  assert.deepEqual(core.detailLevel(28), { detail: 'full', full: true, flatFill: false });
  for (const D of [0, 12, 20, 27.9]) assert.equal(core.detailLevel(D).flatFill, true, `Ø${D}`);
  for (const D of [28, 44, 66]) assert.equal(core.detailLevel(D).flatFill, false, `Ø${D}`);
  assert.deepEqual(core.detailLevel(66, 'compact'), { detail: 'compact', full: false, flatFill: true });
  assert.deepEqual(core.detailLevel(12, 'full'), { detail: 'full', full: true, flatFill: false });
  assert.deepEqual(core.detailLevel(12, undefined), core.detailLevel(12));
});

test('layout() and detailLevel() always agree on the detail, and on the old detailOf()', () => {
  const p = core.PRESETS.shrimpy;
  for (const D of [0, 12, 20, 27.999, 28, 66]) {
    assert.equal(core.detailLevel(D).detail, core.detailOf(D));
    for (const o of [undefined, 'full', 'compact']) assert.equal(core.layout(p, pose(), 0, 0, D, { detail: o }).full, core.detailLevel(D, o).full, `Ø${D} ${o}`);
  }
});

test('FLAT_FILL: the numbers of the flat drawing', () => {
  assert.deepEqual(core.FLAT_FILL, { headMix: .5, earMix: .5, ruffMix: .6, rimGradient: false, crown: { rx: .4, ry: .26, alpha: .5 }, point: { rx: .86, ry: .54, alpha: .85 } });
});

// The gradient the flat point mask replaced (the page drew it before A-0b): a radial fade from 0.05 R to 0.66 R on its short axis, stretched
// 1.55 times wider than tall, 0.97 strong in the middle, 0.82 at 60 % of the way and 0 at the edge. rho is a radius in R on the short axis.
const STRETCH = 1.55, R0 = .05, R1 = .66;
const gradAlpha = rho => { const t = Math.min(1, Math.max(0, (rho - R0) / (R1 - R0))); return t <= .6 ? .97 + (.82 - .97) * t / .6 : .82 * (1 - t) / .4; };
const contour = frac => { let lo = 0, hi = R1; for (let i = 0; i < 60; i++) { const mid = (lo + hi) / 2; if (gradAlpha(mid) > frac * .97) lo = mid; else hi = mid; } return lo; }; // rho where the fade is down to frac of its middle strength

test('FLAT_FILL.point keeps what the gradient it replaced showed: the same ink, and an edge between its half-strength and quarter-strength contours', () => {
  const { rx, ry, alpha } = core.FLAT_FILL.point;
  let ink = 0; const N = 20000;
  for (let i = 0; i < N; i++) { const rho = (i + .5) * R1 / N; ink += gradAlpha(rho) * 2 * Math.PI * STRETCH * rho * R1 / N; }
  near(alpha * Math.PI * rx * ry / ink, 1, .02);                                       // alpha times the flat area is the gradient's total ink, to 2 %
  assert.ok(ry >= contour(.5) && ry <= contour(.25), `ry ${ry} is not between ${contour(.5)} and ${contour(.25)}`);
  assert.ok(rx >= STRETCH * contour(.5) && rx <= STRETCH * contour(.25), `rx ${rx} is not between ${STRETCH * contour(.5)} and ${STRETCH * contour(.25)}`);
  near(rx / ry / STRETCH, 1, .05);                                                     // and about as stretched as the gradient was
});

test('mixHex goes from the first colour to the second without rounding', () => {
  nearAll(core.mixHex('#3B9EFF', '#8B5CF6', 0), [59, 158, 255]);
  nearAll(core.mixHex('#3B9EFF', '#8B5CF6', 1), [139, 92, 246]);
  nearAll(core.mixHex('#000000', '#010101', .5), [.5, .5, .5]);
});

test('flatFillColors, checked by hand: the head and ears halfway, the ruff 0.6 of the way, ears with their own colour keep it, the point mask is the point colour', () => {
  const sh = core.flatFillColors(core.PRESETS.shrimpy);   // top #A08A70, bot #6E5B49, ruff #7E6750 to #B49C7A
  nearAll(sh.head, [135, 114.5, 92.5]); nearAll(sh.ears[0], [135, 114.5, 92.5]); nearAll(sh.ears[1], [135, 114.5, 92.5]);
  nearAll(sh.ruff, [158.4, 134.8, 105.2]);
  const pa = core.flatFillColors(core.PRESETS.patches);   // ears #E3994E and #2C2B2F
  nearAll(pa.ears[0], [227, 153, 78]); nearAll(pa.ears[1], [44, 43, 47]); assert.equal(pa.ruff, null);
  nearAll(core.flatFillColors(core.PRESETS.momo).head, [61, 61, 65]);
  nearAll(core.flatFillColors(core.PRESETS.latte).point, [74, 53, 40]);      // #4A3528
  nearAll(core.flatFillColors(core.PRESETS.cloud).point, [125, 135, 150]);   // #7D8796
  assert.equal(sh.point, null); assert.equal(pa.point, null);
});

test('every coat and kitten has finite flat colours in 0 to 255, a ruff only when it has one and a point colour only on a point coat', () => {
  for (const id of core.CAT_IDS) for (const p of [core.PRESETS[id], core.kittenOf(core.PRESETS[id])]) {
    const c = core.flatFillColors(p);
    for (const rgb of [c.head, ...c.ears, ...(c.ruff ? [c.ruff] : []), ...(c.point ? [c.point] : [])]) assert.ok(rgb.length === 3 && rgb.every(v => Number.isFinite(v) && v >= 0 && v <= 255), `${p.name}`);
    assert.equal(c.ruff === null, !p.ruff, p.name);
    assert.equal(c.point === null, p.coat !== 'point', p.name);
  }
  assert.deepEqual(core.flatFillColors(core.kittenOf(core.PRESETS.shrimpy)), core.flatFillColors(core.PRESETS.shrimpy), 'a kitten keeps its parent coat');
});

test('geometry-cases.json: the detail levels and the flat colours replay from their inputs', () => {
  const g = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/geometry-cases.json', import.meta.url), 'utf8'));
  assert.deepEqual(g.flatFill, core.FLAT_FILL);
  assert.ok(g.detailLevels.length >= 12);
  for (const c of g.detailLevels) assert.deepEqual(core.detailLevel(c.D, c.override ?? undefined), c.level, `Ø${c.D} ${c.override}`);
  assert.ok(g.detailLevels.some(c => c.level.flatFill) && g.detailLevels.some(c => !c.level.flatFill));
  assert.deepEqual(Object.keys(g.flatColors), core.CAT_IDS);
  for (const id of core.CAT_IDS) assert.deepEqual(compare(JSON.parse(JSON.stringify(core.flatFillColors(core.PRESETS[id]))), g.flatColors[id]), [], id);
});
