import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { makeEngine } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const pose = (o = {}) => ({ ...core.newPose(), ...o });
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const NOTCH = [[32, 20], [24, 18]]; // [height of the strip the cat sits in, head width]: the notch, and a screen without one
const POSES = [{}, { earU: 1.4 }, { earU: 1.4, oy: -.26 }, { earU: 1.22, oy: -.26 }, { earU: 1.4, oy: -.3, tilt: .24 }, { earU: 1.4, oy: -.3, tilt: -.24 }, { earU: 1.1, earF: .45, oy: -.1, tilt: .1 }];
const CATS = ['momo', 'shrimpy', 'puff', 'noodle', 'button', 'latte'];
const { margin: MARGIN, minimum: MIN } = core.EAR_FIT;

/** The highest point of an ear in the world (the smallest y), found by walking the whole outline the renderer draws, not by the formula under test. */
function earTop(L, s, e) {
  const R = L.R, { h, bw, tip, cx } = e;
  const segs = [[[-bw, .25 * R], [-bw * cx, -h * .4], [-tip * .9, -h + tip * 1.3]], [[-tip * .9, -h + tip * 1.3], [0, -h - tip * .35], [tip * .9, -h + tip * 1.3]], [[tip * .9, -h + tip * 1.3], [bw * cx, -h * .4], [bw, .25 * R]]];
  let best = Infinity;
  for (const [a, b, c] of segs) for (let i = 0; i <= 400; i++) {
    const t = i / 400, m = 1 - t, x = m * m * a[0] + 2 * m * t * b[0] + t * t * c[0], y = m * m * a[1] + 2 * m * t * b[1] + t * t * c[1];
    const hx = e.bx + x * Math.cos(e.rot) - y * Math.sin(e.rot), hy = e.by + x * Math.sin(e.rot) + y * Math.cos(e.rot); // ear space to head space
    best = Math.min(best, L.head.y + Math.sin(s.tilt) * s.sx * hx + Math.cos(s.tilt) * s.sy * hy);                     // and to the world
  }
  return best;
}
const top = (L, s) => Math.min(...L.ears.map(e => earTop(L, s, e)));
/** A cat in the strip: its ear fit, and its layout with the fit applied. */
function fit(p, s, cy, D, ek = D < core.DETAIL_FULL_MIN ? core.earScale(D) : 1, ...args) {
  const L = core.layout(p, s, 40, cy, D, { earScale: ek }), f = core.earFit(L, s, args[0] ?? 0, args[1], args[2]);
  return { L, f, after: core.layout(p, s, 40, cy, D, { earScale: ek * f }) };
}

test('the defaults: half a pixel of room, never smaller than 0.35', () => {
  assert.deepEqual(core.EAR_FIT, { margin: .5, minimum: .35 });
});

test('a calm cat in the notch keeps its ears; only tall-eared Noodle in a 24 pt strip loses a little', () => {
  for (const [strip, D] of NOTCH) for (const cat of CATS) {
    const f = fit(core.PRESETS[cat], pose(), strip / 2, D).f;
    if (cat === 'noodle' && strip === 24) assert.ok(f > .9 && f < 1, `${f}`);
    else assert.equal(f, 1, `${cat} Ø${D}`);
  }
});

test('in the notch, no ear leaves the strip, and the fit is tight when it shrinks', () => {
  let shrunk = 0;
  for (const cat of CATS) for (const [strip, D] of NOTCH) for (const delta of POSES) {
    const p = core.PRESETS[cat], s = pose(delta), { L, f, after } = fit(p, s, strip / 2, D), where = `${cat} strip ${strip} Ø${D} ${JSON.stringify(delta)}`;
    assert.ok(f >= MIN && f <= 1, where);
    if (f === 1) assert.ok(top(L, s) >= MARGIN - 1e-3, `an ear that was left alone pokes out: ${where}`);
    else {
      shrunk++;
      if (f > MIN + 1e-9) near(top(after, s), MARGIN, 1e-3);   // exactly as small as it has to be
      else assert.ok(top(after, s) > top(L, s), where);         // held at the minimum: the ears are smaller, so the tips are lower than before
    }
  }
  assert.ok(shrunk > 10, 'the poses do need the fit');
});

test('a cat too close to the top gets smaller ears, never smaller than the minimum', () => {
  const p = core.PRESETS.momo, s = pose();
  const close = fit(p, s, 9, 20, 1);
  assert.ok(close.f < 1 && close.f > MIN, `${close.f}`);
  near(top(close.after, s), MARGIN, 1e-3);
  assert.equal(fit(p, s, -30, 20, 1).f, MIN);
});

test('fitting twice changes nothing', () => {
  for (const delta of POSES) {
    const p = core.PRESETS.shrimpy, s = pose(delta), { f, after } = fit(p, s, 16, 20);
    if (f > MIN) near(core.earFit(after, s, 0), 1, 1e-6);
  }
});

test('your own ceiling, margin and minimum', () => {
  const p = core.PRESETS.momo, s = pose({ earU: 1.4, oy: -.26 });
  const base = fit(p, s, 16, 20, .8).f, low = fit(p, s, 16, 20, .8, 5).f, tight = fit(p, s, 16, 20, .8, 0, 0).f;
  assert.ok(low < base, 'a ceiling further down needs smaller ears');
  assert.ok(tight >= base, 'no margin allows bigger ears');
  assert.equal(fit(core.PRESETS.momo, pose(), 8, 20, .8, 0, .5, .5).f, .5);
});

test('a head of width 0, a cat upside down and a pose that is not a number give a number in range, never NaN', () => {
  assert.equal(fit(core.PRESETS.momo, pose(), 16, 0).f, 1);
  for (const s of [pose({ tilt: Math.PI, earU: 1.4 }), pose({ tilt: NaN }), pose({ sy: Infinity }), pose({ sx: NaN, oy: NaN }), pose({ tilt: 20, earU: 9 })]) {
    const f = fit(core.PRESETS.noodle, s, 16, 20).f;
    assert.ok(Number.isFinite(f) && f >= MIN && f <= 1, `${JSON.stringify(s)}: ${f}`);
  }
  assert.equal(fit(core.PRESETS.momo, pose({ tilt: NaN }), 16, 20).f, 1, 'nothing to fit');
});

test('every state and emote, in both motion styles: the ears never leave the compact notch', () => {
  const kinds = [...core.STATES.map(n => ['setState', n]), ...['love', 'happy', 'surprised', 'proud', 'wink', 'yawn', 'annoyed', 'hello', 'zoomies', 'hairball'].map(n => ['emote', n])];
  let shrunk = 0, frames = 0;
  for (const profile of ['playful', 'classic']) for (const cat of ['momo', 'shrimpy', 'noodle']) for (const [strip, D] of NOTCH) for (const [call, name] of kinds) {
    const p = core.PRESETS[cat], { e, step } = makeEngine(p, { profile });
    e[call](name);
    for (let f = 1; f <= 180; f++) {
      step(f);
      if (f % 3) continue;
      const s = e.s, { f: k, after } = fit(p, s, strip / 2, D);
      frames++; if (k < 1) shrunk++;
      if (k > MIN + 1e-9) assert.ok(top(after, s) >= MARGIN - 1e-3, `${profile} ${cat} ${strip}/${D} ${call} ${name} frame ${f}: ${top(after, s)}`);
    }
  }
  assert.ok(shrunk > 100 && shrunk < frames / 2, `${shrunk} of ${frames} frames needed the fit`);
});

test('geometry-cases.json: every ear fit case replays from its own inputs', () => {
  const g = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/geometry-cases.json', import.meta.url), 'utf8'));
  assert.deepEqual(g.earFit, core.EAR_FIT);
  assert.ok(g.earFitCases.length >= 80);
  for (const c of g.earFitCases) {
    const base = core.PRESETS[c.cat], p = c.kitten ? core.kittenOf(base) : base, s = pose(c.pose);
    const L = core.layout(p, s, c.cx, c.cy, c.D, { earScale: c.earScale });
    near(core.earFit(L, s, c.ceiling, c.margin, c.minimum), c.fit);
  }
  assert.ok(g.earFitCases.some(c => c.fit === 1) && g.earFitCases.some(c => c.fit === MIN) && g.earFitCases.some(c => c.fit > MIN && c.fit < 1), 'the cases need no fit, the minimum and something in between');
});
