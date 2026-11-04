import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const eye = core.smallEye;
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const SHAPES = core.SMALL_EYE_SHAPES;
const INK = ['line', 'flat', 'happy', 'closed', 'spiral', 'heart', 'star'];

test('the starting values of the spec are the contract\'s: a 0.42 by 0.46 iris, a 0.18 by 0.40 pupil, the catchlight and the rim', () => {
  const S = core.SMALL_EYE;
  assert.deepEqual([S.iris.w, S.iris.h, S.pupil.w, S.pupil.h], [.42, .46, .18, .40]);
  assert.deepEqual(S.light, { x: -.11, y: -.10, r: .075, minR: .45 });
  assert.deepEqual(S.rim, { k: .05, min: .5 });
  assert.equal(S.closeBelow, .22, 'the realistic eye\'s own threshold');
  assert.deepEqual(SHAPES, ['pill', 'wide', 'dot', 'tired']);
  assert.ok(.42 > .34 && .46 > .40, 'a little bigger than the ink pill it replaces (0.34 by 0.40)');
});

test('which eyes are small coloured eyes: the plain resting shapes and the left eye of a wink; every expression stays ink', () => {
  for (const s of SHAPES) for (const sd of [-1, 1]) assert.equal(core.usesSmallEye(s, sd), true, `${s} ${sd}`);
  for (const s of INK) for (const sd of [-1, 1]) assert.equal(core.usesSmallEye(s, sd), false, `${s} ${sd}`);
  assert.equal(core.usesSmallEye('wink', -1), true);
  assert.equal(core.usesSmallEye('wink', 1), false);
  for (const s of ['bogus', '', 'PILL', undefined, null, 7, {}]) assert.equal(core.usesSmallEye(s, -1), false, String(s));
  for (const s of INK) assert.equal(eye(s, { R: 10 }), null, s);
  assert.equal(eye('wink', { sd: 1, R: 10 }), null);
  assert.equal(eye('bogus', { R: 10 }), null);
});

test('the resting eye at R = 10: the iris 4.2 by 4.6, the pupil 1.8 by 4, the catchlight at (-1.1, -1.0), the rim 0.5', () => {
  const e = eye('pill', { sd: -1, R: 10 });
  assert.equal(e.closed, false);
  near(e.iris.rx * 2, 4.2); near(e.iris.ry * 2, 4.6); near(e.iris.r, 2.3);
  near(e.pupil.rx * 2, 1.8); near(e.pupil.ry * 2, 4); near(e.pupil.x, 0); near(e.pupil.y, 0);
  near(e.light.x, -1.1); near(e.light.y, -1.0); near(e.light.r, .75);
  near(e.rim, .5);
  assert.deepEqual(Object.keys(e), ['shape', 'closed', 'iris', 'pupil', 'light', 'rim']);
});

test('the floors: the catchlight never under 0.45 px and the rim never under 0.5 px, and both grow with the head', () => {
  for (const R of [0, 1, 3, 5, 5.9, 6]) { const e = eye('pill', { R }); near(e.light.r, .45); near(e.rim, .5); }
  const big = eye('pill', { R: 20 });
  near(big.light.r, 1.5); near(big.rim, 1);
  near(eye('pill', { R: 8 }).light.r, .6);
  near(eye('pill', { R: 12 }).rim, .6);
});

test('wide is the iris times (1.16, 1.12); dot is round with a round, bigger pupil; tired shows at most 0.42 of the eye', () => {
  const p = eye('pill', { R: 10 }), w = eye('wide', { R: 10 }), d = eye('dot', { R: 10 }), t = eye('tired', { R: 10 }), t2 = eye('tired', { R: 10, open: .3 });
  near(w.iris.rx / p.iris.rx, 1.16); near(w.iris.ry / p.iris.ry, 1.12);
  near(d.iris.rx, d.iris.ry); near(d.iris.rx * 2, 4.2); near(d.pupil.rx, d.pupil.ry); near(d.pupil.rx * 2, 2.6);
  assert.ok(d.pupil.rx > p.pupil.rx, 'dilated');
  near(t.iris.ry / p.iris.ry, .42);
  near(t2.iris.ry / p.iris.ry, .3, 1e-12);
  assert.equal(eye('tired', { R: 10, open: .2 }).closed, true);
  assert.equal(eye('wink', { sd: -1, R: 10 }).shape, 'wink');
  assert.deepEqual({ ...eye('wink', { sd: -1, R: 10 }), shape: 'pill' }, eye('pill', { sd: -1, R: 10 }), 'the left eye of a wink is a pill');
});

test('the expression scale grows everything with the head; the eye\'s side does not change its shape', () => {
  const a = eye('pill', { R: 10, es: 1.25 }), b = eye('pill', { R: 12.5 });
  assert.deepEqual(a, b);
  assert.deepEqual(eye('pill', { R: 10, sd: 1 }), eye('pill', { R: 10, sd: -1 }), 'the iris colour is the renderer\'s: the geometry is the same for both eyes');
  assert.deepEqual(eye('pill', { R: 10, es: 0 }).iris, { rx: 0, ry: 0, r: 0 });
});

test('a kitten\'s eye is 1.2 times wider and 1.32 times taller, the ratio kittenOf gives a kitten\'s eyes', () => {
  const kw = core.kittenOf(core.PRESETS.momo).eye.w / core.PRESETS.momo.eye.w, kh = core.kittenOf(core.PRESETS.momo).eye.h / core.PRESETS.momo.eye.h;
  near(kw, 1.2); near(kh, 1.32);
  for (const s of SHAPES) {
    const a = eye(s, { R: 9 }), k = eye(s, { R: 9, kitten: true });
    near(k.iris.rx / a.iris.rx, kw); near(k.iris.ry / a.iris.ry, kh);
    near(k.pupil.rx / a.pupil.rx, kw);
  }
  assert.deepEqual(eye('pill', { R: 9, kitten: 'yes' }), eye('pill', { R: 9 }), 'only a real true counts');
});

test('a blink or a squint under 0.22 of the eye closes it to a line, as the realistic eye does; at 0.22 it is still open', () => {
  assert.equal(eye('pill', { R: 10, open: .22 }).closed, false);
  assert.equal(eye('pill', { R: 10, open: .2199 }).closed, true);
  const c = eye('pill', { R: 10, open: 0 });
  assert.deepEqual(compare(c, { shape: 'pill', closed: true, line: { x0: -2.1, y0: 0, cx: 0, cy: .4 * 2.3, x1: 2.1, y1: 0, width: 1 } }), []);
  near(eye('pill', { R: 40, open: 0 }).line.width, 1.8);
  assert.equal(eye('pill', { R: 10, open: -1 }).closed, true, 'open is held to 0 up to 1');
  assert.equal(eye('pill', { R: 10, open: 7 }).closed, false);
  assert.deepEqual(eye('pill', { R: 10, open: 7 }), eye('pill', { R: 10, open: 1 }));
  const half = eye('pill', { R: 10, open: .5 }), full = eye('pill', { R: 10 });
  near(half.iris.rx, full.iris.rx); near(half.iris.ry, full.iris.ry / 2);
  assert.ok(half.pupil.ry < full.pupil.ry && half.pupil.ry <= .87 * half.iris.ry + 1e-12, 'the pupil keeps inside the smaller iris');
  near(half.light.y, full.light.y / 2);
});

test('the pupil follows the gaze a little: 0.2 of the iris\'s half-width across at yaw 0.62, 0.08 of its half-height up at pitch 0.5', () => {
  const rest = eye('pill', { R: 10 }), right = eye('pill', { R: 10, yaw: .62 }), left = eye('pill', { R: 10, yaw: -.62 }), up = eye('pill', { R: 10, pitch: .5 }), down = eye('pill', { R: 10, pitch: -.5 });
  near(right.pupil.x, .2 * rest.iris.rx); near(left.pupil.x, -.2 * rest.iris.rx);
  near(up.pupil.y, -.08 * rest.iris.ry); near(down.pupil.y, .08 * rest.iris.ry);
  near(eye('pill', { R: 10, yaw: 9, pitch: 9 }).pupil.x, right.pupil.x);
  near(eye('pill', { R: 10, yaw: .31 }).pupil.x, right.pupil.x / 2);
  assert.deepEqual(eye('pill', { R: 10, yaw: 'x', pitch: null }), rest, 'a gaze that is not a number is straight ahead');
});

test('the pupil never leaves the iris and the catchlight stays in it, at every size, squint, gaze and kitten', () => {
  let worst = 0;
  for (const shape of SHAPES) for (const kitten of [false, true]) for (const es of [.8, 1, 1.25]) for (let open = .22; open <= 1.0001; open += .026) for (const yaw of [-1, -.62, -.3, 0, .62, 1]) for (const pitch of [-1, -.5, 0, .25, .5, 1]) {
    const e = eye(shape, { sd: 1, R: 8, es, open, yaw, pitch, kitten });
    if (e.closed) continue;
    for (let a = 0; a < 360; a += 2) { const t = a * Math.PI / 180, x = e.pupil.x + e.pupil.rx * Math.cos(t), y = e.pupil.y + e.pupil.ry * Math.sin(t); worst = Math.max(worst, (x / e.iris.rx) ** 2 + (y / e.iris.ry) ** 2); }
    assert.ok((e.light.x / e.iris.rx) ** 2 + (e.light.y / e.iris.ry) ** 2 < 1, `${shape} light`);
    assert.ok(e.iris.r === Math.max(e.iris.rx, e.iris.ry) && e.rim >= .5 && e.light.r >= .45);
  }
  assert.ok(worst < 1, `the pupil leaves the iris: ${worst}`);
});

test('numbers that are not numbers are taken as their default, and nothing is ever NaN: 5000 random calls', () => {
  assert.deepEqual(eye('pill', { R: 'x' }), eye('pill', { R: 0 }));
  assert.deepEqual(eye('pill', { R: NaN, es: NaN, open: NaN, yaw: NaN, pitch: NaN }), eye('pill', { R: 0 }));
  assert.deepEqual(eye('pill', { R: -4 }), eye('pill', { R: 0 }), 'a negative head is no head');
  assert.deepEqual(eye('pill', { R: 10, es: -1 }), eye('pill', { R: 10, es: 0 }));
  assert.deepEqual(eye('pill'), eye('pill', {}));
  assert.doesNotThrow(() => eye('pill', null));
  assert.doesNotThrow(() => eye(undefined, undefined));
  const r = core.rng(5), pool = [0, 1, -1, .5, 99, -99, NaN, Infinity, -Infinity, 'x', null, undefined, true, {}, [], 1e300, 5e-324];
  const pick = () => pool[Math.floor(r() * pool.length)], fin = v => typeof v === 'string' || typeof v === 'boolean' || (typeof v === 'number' && Number.isFinite(v)) || (v && typeof v === 'object' && Object.values(v).every(fin));
  for (let i = 0; i < 5000; i++) {
    const out = eye([...SHAPES, 'wink', 'happy', 'bogus'][Math.floor(r() * 7)], { sd: pick(), R: pick(), es: pick(), open: pick(), yaw: pick(), pitch: pick(), kitten: pick() });
    assert.ok(out === null || fin(out), JSON.stringify(out));
  }
});

const BRIGHT = ['midnight', 'oreo', 'mocha'];

test('bright coats (Midnight, Oreo, Mocha): flat iris with no rim and a thinner slit pupil; every other coat is numerically unchanged', () => {
  assert.deepEqual(core.SMALL_EYE.bright, BRIGHT);
  assert.deepEqual(core.SMALL_EYE.brightPupil, { w: .12 });
  const n = eye('pill', { R: 10 });
  assert.equal(n.flat, undefined, 'a normal eye has no flat key: old output is untouched');
  for (const cat of BRIGHT) {
    const b = eye('pill', { R: 10, cat });
    assert.equal(b.flat, true); assert.equal(b.rim, 0);
    near(b.pupil.rx * 2, 1.2); near(b.pupil.ry, n.pupil.ry);
    assert.deepEqual(b.iris, n.iris); assert.deepEqual(b.light, n.light);
    assert.deepEqual(Object.keys(b), ['shape', 'closed', 'iris', 'pupil', 'light', 'rim', 'flat']);
  }
  for (const cat of ['momo', 'ginger', 'MIDNIGHT', 'midnight ', '', undefined, null, 7, {}, [], ['midnight'], '__proto__', 'constructor']) assert.deepEqual(eye('pill', { R: 10, cat }), n, String(cat));
});

test('a bright kitten scales as before; a bright coat blinking closed keeps the closed-line shape', () => {
  const k = eye('pill', { R: 9, kitten: true, cat: 'oreo' }), nk = eye('pill', { R: 9, kitten: true }), a = eye('pill', { R: 9, cat: 'oreo' });
  near(k.pupil.rx / a.pupil.rx, 1.2); near(k.iris.rx / a.iris.rx, 1.2); near(k.iris.ry / a.iris.ry, 1.32);
  assert.equal(k.flat, true); assert.equal(k.rim, 0); near(k.pupil.rx * 2, .12 * 1.2 * 9 * 1);
  assert.ok(k.pupil.rx < nk.pupil.rx);
  for (const open of [0, .1, .2]) assert.deepEqual(eye('pill', { R: 10, open, cat: 'mocha' }), eye('pill', { R: 10, open }), 'closed line is the same');
});

test('bright coats: the pupil still stays inside the iris at every size, squint, gaze and kitten', () => {
  let worst = 0;
  for (const cat of BRIGHT) for (const shape of SHAPES) for (const kitten of [false, true]) for (const es of [.8, 1.25]) for (let open = .22; open <= 1.0001; open += .13) for (const yaw of [-1, 0, 1]) for (const pitch of [-1, 0, 1]) {
    const e = eye(shape, { sd: 1, R: 8, es, open, yaw, pitch, kitten, cat });
    if (e.closed) continue;
    for (let a = 0; a < 360; a += 3) { const t = a * Math.PI / 180, x = e.pupil.x + e.pupil.rx * Math.cos(t), y = e.pupil.y + e.pupil.ry * Math.sin(t); worst = Math.max(worst, (x / e.iris.rx) ** 2 + (y / e.iris.ry) ** 2); }
  }
  assert.ok(worst < 1, `the pupil leaves the iris: ${worst}`);
});

const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/small-eye-cases.json', import.meta.url), 'utf8'));
const roundTrip = v => JSON.parse(JSON.stringify(v));

test('small-eye-cases.json: the constants and the shapes are the core\'s', () => {
  assert.deepEqual(compare(roundTrip(core.SMALL_EYE), fx.constants), []);
  assert.deepEqual(fx.shapes, SHAPES);
  assert.deepEqual(fx.bright, BRIGHT);
});

test('small-eye-cases.json: every row replays from its own input', () => {
  for (const g of ['sizes', 'squints', 'gazes', 'scales', 'others', 'hostile', 'brights']) fx[g].forEach((c, i) => assert.deepEqual(compare(roundTrip(eye(c.shape, c.o)), c.out), [], `${g} ${i}: ${c.shape} ${JSON.stringify(c.o)}`));
  for (const c of fx.uses) assert.equal(core.usesSmallEye(c.shape, c.sd), c.out, `${c.shape} ${c.sd}`);
});

test('small-eye-cases.json: sizes from R 3 to R 22 for kittens and cats, every squint and gaze, the shapes that stay ink and the hostile inputs are in it', () => {
  assert.equal(fx.sizes.length, 56); assert.equal(fx.squints.length, 72); assert.equal(fx.gazes.length, 72); assert.equal(fx.scales.length, 20);
  assert.ok(fx.squints.some(c => c.out.closed) && fx.squints.some(c => !c.out.closed), 'both closed and open');
  assert.ok(fx.others.filter(c => c.out === null).length >= 11, 'ink shapes and the right eye of a wink');
  assert.ok(fx.hostile.length >= 19 && fx.hostile.filter(c => c.out === null).length === 1, 'hostile inputs still give an eye, except a shape that is not a shape');
  assert.equal(fx.brights.length, 6);
  assert.ok(fx.brights.some(c => c.out.flat && c.o.kitten) && fx.brights.some(c => c.out.flat && c.o.cat === 'midnight') && fx.brights.some(c => c.out.closed && c.o.cat === 'mocha') && fx.brights.some(c => c.out.flat === undefined && c.o.cat === 'momo'));
  assert.ok(fx.sizes.some(c => c.o.kitten === true) && fx.sizes.some(c => c.o.kitten === false));
  assert.ok(fx.sizes.filter(c => !c.out.closed && c.out.light.r === .45).length >= 8, 'the catchlight floor bites at the smallest sizes');
});
