import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const core = require('../../design/prototype/cat-core.js');
const load = name => JSON.parse(fs.readFileSync(new URL(`../fixtures/cat/${name}`, import.meta.url), 'utf8'));
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const finite = (v, at = '$') => {
  if (typeof v === 'number') assert.ok(Number.isFinite(v), `${at} is ${v}`);
  else if (typeof v === 'function') return;
  else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) finite(x, `${at}.${k}`);
};
const pose = (o = {}) => ({ ...core.newPose(), ...o });

test('the detail switch is at head width 28', () => {
  assert.equal(core.DETAIL_FULL_MIN, 28);
  assert.deepEqual([12, 20, 27.999, 28, 28.001, 66].map(core.detailOf), ['compact', 'compact', 'compact', 'full', 'full', 'full']);
  const p = core.PRESETS.momo;
  assert.equal(core.layout(p, pose(), 0, 0, 27.9).full, false);
  assert.equal(core.layout(p, pose(), 0, 0, 28).full, true);
  assert.equal(core.layout(p, pose(), 0, 0, 66, { detail: 'compact' }).full, false, 'an explicit detail wins');
  assert.equal(core.layout(p, pose(), 0, 0, 12, { detail: 'full' }).full, true);
  assert.equal(core.outlineSteps(19.9), 72);
  assert.equal(core.outlineSteps(20), 200);
});

test('compact ears: 1 from Ø28 up, easing to 0.8 at Ø20 and below, never jumping', () => {
  assert.equal(core.COMPACT_EAR_SCALE, .8);
  for (const D of [28, 44, 66]) assert.equal(core.earScale(D), 1);
  for (const D of [0, 12, 16, 20]) near(core.earScale(D), .8);
  let prev = 0;
  for (let D = 20; D <= 28; D += .5) { const k = core.earScale(D); assert.ok(k >= prev && k <= 1); prev = k; }
  near(core.earScale(27.999), 1, 1e-3);
  const p = core.PRESETS.shrimpy, full = core.layout(p, pose(), 0, 0, 20).ears[1], small = core.layout(p, pose(), 0, 0, 20, { earScale: core.earScale(20) }).ears[1];
  near(small.h, full.h * .8); near(small.bw, full.bw * .8); near(small.tip, full.tip * .8); near(small.bx, full.bx); near(small.by, full.by);
});

test('supPoints: a closed superellipse, and a fluffy edge that is fixed, not random', () => {
  const a = core.supPoints(1.12, .9, 2.2, 0, 0, 14, 200), b = core.supPoints(1.12, .9, 2.2, 0, 0, 14, 200);
  assert.equal(a.length, 201);
  assert.deepEqual(a, b);
  near(a[0][0], a[200][0]); near(a[0][1], a[200][1], 1e-9);
  for (const [x, y] of a) near(Math.pow(Math.abs(x / 1.12), 2.2) + Math.pow(Math.abs(y / .9), 2.2), 1, 1e-9);
  near(Math.max(...a.map(q => q[0])), 1.12); near(Math.max(...a.map(q => q[1])), .9);
  const fluff = core.supPoints(1.16, .92, 2.2, 0, .035, 14, 200);
  assert.deepEqual(fluff, core.supPoints(1.16, .92, 2.2, 0, .035, 14, 200));
  const k = q => Math.pow(Math.pow(Math.abs(q[0] / 1.16), 2.2) + Math.pow(Math.abs(q[1] / .92), 2.2), 1 / 2.2); // 1 on the plain superellipse
  const lower = fluff.filter(q => q[1] > 0), upper = fluff.filter(q => q[1] < -.6 * .92);
  assert.ok(Math.max(...lower.map(k)) > 1.01, 'the lower edge is fluffy');
  assert.ok(Math.max(...lower.map(k)) <= 1.035 + 1e-9, 'and never more than the spike amount');
  upper.forEach(q => near(k(q), 1));
  const ruff = core.supPoints(1.3, .97, 2.4, .2, .06, 18, 72);
  assert.equal(ruff.length, 73);
  assert.ok(Math.max(...ruff.map(q => q[1])) > .97 + .2, 'the ruff sits lower by dy and spikes past it');
  const bent = core.supPoints(1.12, .9, 2.2, 0, 0, 14, 200, [.05, -.02]);
  near(Math.max(...bent.map(q => q[0])), 1.12 * 1.05, 1e-3); // the widest point leans out by bend[0] of rx
});

test('mkWarp is the identity at rest and keeps points outside the head where they are', () => {
  const p = core.PRESETS.momo, R = 30, W = core.mkWarp(p, 0, 0, R);
  for (const [x, y] of [[0, 0], [.3, -.5], [-.7, .2], [1.3, .9], [0, -.6]]) assert.deepEqual(W(x, y), [x * R, y * R]);
  const T = core.mkWarp(p, .5, .2, R);
  assert.deepEqual(T(1.3, .9), [1.3 * R, .9 * R], 'outside the outline: untouched');
  assert.ok(T(0, 0)[0] > 0, 'a positive yaw turns the face toward +x');
  assert.ok(core.mkWarp(p, -.5, 0, R)(0, 0)[0] < 0);
  assert.ok(T(0, -.3)[1] < core.mkWarp(p, .5, 0, R)(0, -.3)[1], 'looking up lifts the face');
});

test('the muzzle stands proud of the head, so the nose swings further than a cheek', () => {
  assert.equal(core.FACE.muzzle, .12);
  const p = core.PRESETS.shrimpy, yaw = .5, W = core.mkWarp(p, yaw, 0, 1);
  const noseY = -Math.sin(p.nosePh) * p.ry, v = -noseY / p.ry, q = 1 - v * v, vm = Math.sin(p.nosePh) - .12;
  const flat = Math.sqrt(q) * Math.sin(yaw) * p.rx, dv = (v - vm) / .45;
  near(W(0, noseY)[0] - flat, core.FACE.muzzle * Math.exp(-dv * dv) * Math.sin(yaw) * p.rx);
  assert.ok(W(0, noseY)[0] > flat);
});

test('faceAngles: the face takes 82 % of the yaw, looking up 60 % of the pitch and down only 32 %', () => {
  const a = core.faceAngles(pose({ yaw: .62, pitch: .5 })), d = core.faceAngles(pose({ pitch: -.5 }));
  near(a.yf, .62 * .82); near(a.pf, .5 * .6); near(d.pf, -.5 * .32);
  near(core.faceAngles(pose({ roll: Math.PI })).pt, -Math.PI);
  assert.equal(core.faceAngles(pose()).fa, 1);
  assert.equal(core.faceAngles(pose({ roll: Math.PI })).fa, 0);
  near(core.faceAngles(pose({ lift: .28 })).pt, .28);
});

test('the cursor curve is tanh over 240 px across and 180 px up and down', () => {
  assert.deepEqual(core.CURSOR, { x: 240, y: 180 });
  near(core.cursorLook(240, 0).x, Math.tanh(1)); near(core.cursorLook(0, 180).y, -Math.tanh(1));
  near(core.cursorLook(-480, 0).x, -Math.tanh(2));
  near(core.cursorLook(0, 0).x, 0); near(core.cursorLook(0, 0).y, 0);
  near(core.cursorLook(1e6, -1e6).x, 1); near(core.cursorLook(1e6, -1e6).y, 1);
  assert.ok(core.cursorLook(0, 100).y < 0, 'a cursor below the cat looks down (negative)');
});

test('the pupils travel up to 0.24 of the eye width and 0.18 of its height', () => {
  assert.deepEqual(core.pupilOffset(0, 0, 10, 8).map(v => v + 0), [0, 0]);
  near(core.pupilOffset(.62, 0, 10, 8)[0], 2.4); near(core.pupilOffset(5, 0, 10, 8)[0], 2.4); near(core.pupilOffset(-5, 0, 10, 8)[0], -2.4);
  near(core.pupilOffset(0, .5, 10, 8)[1], -1.44); near(core.pupilOffset(0, -9, 10, 8)[1], 1.44);
});

test('layout at rest: the cat is where you put it, the eyes, ears, nose and badge sit where the board says', () => {
  for (const id of core.CAT_IDS) {
    const p = core.PRESETS[id], D = 66, R = D / (2 * p.rx), L = core.layout(p, pose({ badgeS: 1 }), 100, 50, D);
    near(L.R, R); assert.equal(L.full, true); assert.equal(L.steps, 200);
    assert.deepEqual(L.base, { x: 100, y: 50, R }); assert.deepEqual(L.at, { x: 100, y: 50, R, D }); assert.deepEqual(L.head, { x: 100, y: 50 });
    assert.equal(L.fa, 1);
    for (const e of L.eyes) {
      assert.equal(e.visible, true); near(e.fx, 1); near(e.fy, 1);
      near(e.x, e.sd * Math.sin(p.eye.th) * Math.cos(p.eye.ph) * p.rx * R); near(e.y, -Math.sin(p.eye.ph) * p.ry * R);
    }
    assert.equal(L.nose.visible, true); near(L.nose.nx, 0); near(L.nose.nf, 1); near(L.nose.ny, -Math.sin(p.nosePh) * p.ry * R);
    near(L.mouth.x, 100); near(L.mouth.y, 50 + (L.nose.my + .12 * R));
    const [l, r] = L.ears; assert.equal(l.sd, -1); assert.equal(r.sd, 1);
    near(l.bx, -r.bx); near(l.by, r.by); near(l.rot, -r.rot); near(l.h, r.h);
    near(r.h, p.ear.h * R); near(r.bw, p.ear.bw * R * Math.cos(.6)); near(r.bx, Math.sin(.6) * p.earSpread * p.rx * R);
    near(L.badge.x, 100 + 1.4 * R); near(L.badge.y, 50 - .92 * R); assert.equal(L.badge.k, 1);
  }
});

test('the badge: right of the head, left in the compact notch, scaled up a little when compact', () => {
  assert.equal(core.badgeSide(false), 1); assert.equal(core.badgeSide(true), -1);
  const p = core.PRESETS.momo, s = pose({ badgeS: 1, sx: 1.1, sy: .9 });
  const R = L => L.R, right = core.layout(p, s, 0, 0, 66), left = core.layout(p, s, 0, 0, 20, { badgeSide: core.badgeSide(true) });
  near(right.badge.x, 1.4 * R(right) * 1.1); near(right.badge.y, -.92 * R(right) * .9); assert.equal(right.badge.k, 1);
  near(left.badge.x, -1.4 * R(left) * 1.1); assert.equal(left.badge.side, -1); assert.equal(left.badge.k, 1.25); assert.equal(left.badge.small, true);
});

test('turning the head leans the outline, shifts the head toward the cursor and moves the nose', () => {
  const p = core.PRESETS.shrimpy, R = 66 / (2 * p.rx), L = core.layout(p, pose({ yaw: .62 }), 0, 0, 66);
  near(L.head.x, Math.sin(.62) * .08 * R); near(L.head.y, 0);
  near(L.bend[0], Math.sin(.62 * .82) * .1); near(L.ruff.dx, -Math.sin(.62) * .08 * 1.1 * R);
  const rest = core.layout(p, pose(), 0, 0, 66);
  assert.ok(L.nose.nx > rest.nose.nx && L.mouth.x > rest.mouth.x);
  const up = core.layout(p, pose({ pitch: .5 }), 0, 0, 66);
  assert.ok(up.head.y < 0, 'looking up lifts the head centre');
});

test('the near eye never foreshortens below 55 %, and a face turned past the limit hides its far eye', () => {
  const p = core.PRESETS.momo;
  const fx = yaw => core.layout(p, pose({ yaw }), 0, 0, 66).eyes.map(e => e.fx);
  for (const yaw of [0, .31, .62, .9, 1.2, 1.3]) for (const v of fx(yaw)) assert.ok(v >= .55 - 1e-12 && v <= 1.08 + 1e-12, `yaw ${yaw}: ${v}`);
  assert.deepEqual(fx(1.3).map(v => +v.toFixed(6)).includes(.55), true, 'the floor is reached');
  const far = core.layout(p, pose({ yaw: 1.7 }), 0, 0, 66);
  assert.equal(far.eyes[0].visible, true); assert.equal(far.eyes[1].visible, false);
});

test('extreme poses never produce NaN: rolled over the top, turned away, or a head of width 0', () => {
  const p = core.PRESETS.shrimpy;
  const over = core.layout(p, pose({ roll: Math.PI }), 0, 0, 66);
  assert.equal(over.fa, 0); assert.ok(over.eyes.every(e => !e.visible)); assert.equal(over.nose.visible, false); assert.equal(over.mouth, null);
  finite(over);
  const away = core.layout(p, pose({ yaw: 3 }), 0, 0, 66); finite(away);
  assert.ok(away.eyes.every(e => !e.visible) && away.mouth === null);
  const zero = core.layout(p, pose({ badgeS: 1 }), 5, 7, 0); finite(zero);
  assert.equal(zero.R, 0); assert.deepEqual(zero.head, { x: 5, y: 7 });
  for (const id of core.CAT_IDS) finite(core.layout(core.PRESETS[id], pose({ yaw: .62, pitch: .5, roll: 1, tilt: .3, earU: 1.4, earF: 1 }), 0, 0, 12));
});

test('the draw order is split into a behind pass, the head and a front pass', () => {
  const all = [...core.PASSES.behind, ...core.PASSES.head, ...core.PASSES.front];
  assert.equal(new Set(all).size, all.length);
  assert.deepEqual(core.PASSES.behind.slice(-2), ['paws', 'ears']);
  assert.ok(core.PASSES.front.includes('foldEars') && core.PASSES.front.includes('badge'));
});

test('geometry-cases.json: every case replays through layout() from its own inputs', () => {
  const g = load('geometry-cases.json');
  assert.equal(g.version, 1);
  assert.equal(g.detail.fullMinD, 28);
  for (const c of g.detail.cases) assert.equal(core.detailOf(c.D), c.detail);
  for (const c of g.earScale.cases) near(core.earScale(c.D), c.scale);
  for (const c of g.outline) {
    const pts = core.supPoints(c.rx, c.ry, c.n, c.dy, c.spike, c.count, c.steps, c.bend);
    c.indices.forEach((i, k) => { near(pts[i][0], c.points[k][0]); near(pts[i][1], c.points[k][1]); });
  }
  assert.ok(g.anchors.length >= 30);
  for (const c of g.anchors) {
    const base = core.PRESETS[c.cat], p = c.kitten ? core.kittenOf(base) : base;
    const { W, ...L } = core.layout(p, pose(c.pose), c.cx, c.cy, c.D, { T: c.T, earScale: c.earScale, badgeSide: c.badgeSide });
    assert.deepEqual(JSON.parse(JSON.stringify(L)).eyes.map(e => e.visible), c.layout.eyes.map(e => e.visible));
    near(L.badge.x, c.layout.badge.x); near(L.mouth.x, c.layout.mouth.x); near(L.ears[0].h, c.layout.ears[0].h);
  }
  assert.deepEqual(g.passes, core.PASSES);
  assert.ok(g.anchors.some(c => c.D === 20 && c.badgeSide === -1 && c.earScale === .8), 'the compact notch case is there');
});

test('warp-cases.json: the warp, the angles, the pupils and the cursor replay from their inputs', () => {
  const w = load('warp-cases.json');
  assert.deepEqual(w.face, core.FACE);
  assert.deepEqual(w.cursor.px, { x: 240, y: 180 });
  for (const c of w.cursor.cases) { near(core.cursorLook(c.dx, c.dy).x, c.x); near(core.cursorLook(c.dx, c.dy).y, c.y); }
  for (const c of w.angles) { const a = core.faceAngles(pose({ yaw: c.yaw, pitch: c.pitch, lift: c.lift, roll: c.roll })); near(a.yf, c.yf); near(a.pf, c.pf); near(a.pt, c.pt); near(a.fa, c.fa); }
  for (const c of w.pupil) { const o = core.pupilOffset(c.yaw, c.pitch, c.w, c.h); near(o[0], c.offset[0]); near(o[1], c.offset[1]); }
  assert.ok(w.warp.length >= 24);
  for (const c of w.warp) {
    const W = core.mkWarp(core.PRESETS[c.cat], c.yf, c.pt, 1);
    c.probes.forEach((q, i) => { const o = W(q[0], q[1]); near(o[0], c.out[i][0]); near(o[1], c.out[i][1]); });
  }
  assert.ok(w.eyes.some(c => c.eyes.some(e => e.fx === .55)), 'the 55 % floor is in the fixture');
  assert.ok(w.eyes.some(c => c.eyes.some(e => !e.visible)), 'a hidden far eye is in the fixture');
});
