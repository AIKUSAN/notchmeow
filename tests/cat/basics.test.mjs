import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const core = require('../../design/prototype/cat-core.js');
const near = (a, b, eps = 1e-12) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);

test('rng is the seeded uint32 LCG (known answers computed independently in Python)', () => {
  const first = seed => { const r = core.rng(seed); return [r(), r(), r(), r()]; };
  assert.deepEqual(first(0), [2.8742942959070206e-06, 0.8275770242325962, 0.6524071616586298, 0.8374803168699145]);
  assert.deepEqual(first(1), [0.25693503906950355, 0.5878706516232342, 0.15432575810700655, 0.767266943352297]);
  assert.deepEqual(first(13), [0.3401210163719952, 0.7113941803108901, 0.17734891548752785, 0.924706461140886]);
  assert.deepEqual(first(29), [0.45103565277531743, 0.876092218561098, 0.20804645866155624, 0.8012924848590046]);
});

test('rng: the same seed repeats, different seeds differ, the seed wraps to uint32, values stay in [0, 1)', () => {
  const a = core.rng(7), b = core.rng(7), c = core.rng(8);
  const sa = Array.from({ length: 50 }, a), sb = Array.from({ length: 50 }, b), sc = Array.from({ length: 50 }, c);
  assert.deepEqual(sa, sb);
  assert.notDeepEqual(sa, sc);
  assert.deepEqual(Array.from({ length: 5 }, core.rng(2 ** 32 + 7)), sa.slice(0, 5));
  assert.ok(sa.every(v => v >= 0 && v < 1));
});

test('easings, lerp, seg, clamp, wrapA and tm', () => {
  for (const k of ['out', 'inOut', 'back', 'lin', 'in']) { near(core.EZ[k](0), 0); near(core.EZ[k](1), 1); }
  near(core.EZ.inOut(.5), .5);
  near(core.EZ.out(.5), .875);
  near(core.EZ.in(.5), .125);
  assert.ok(core.EZ.back(.8) > 1, 'back overshoots');
  near(core.lerp(2, 10, .25), 4);
  assert.equal(core.clamp(5, 0, 1), 1);
  assert.equal(core.seg(-1, 0, 2), 0);
  near(core.seg(1, 0, 2), .5);
  assert.equal(core.seg(9, 0, 2), 1);
  near(core.wrapA(Math.PI * 2.5), Math.PI / 2, 1e-9);
  near(core.wrapA(Math.PI), -Math.PI, 1e-9); // the range is [-π, π)
  near(core.wrapA(-Math.PI * 2.5), -Math.PI / 2, 1e-9);
  near(core.tm(0, .3, 2), .3); near(core.tm(.5, .3, 2), 1); near(core.tm(1, .3, 2), 2); near(core.tm(.25, .3, 2), .65);
  assert.deepEqual(core.hex('#3B9EFF'), [59, 158, 255]);
});

test('the eleven states and their tables', () => {
  assert.deepEqual(core.STATES, ['idle', 'working', 'thinking', 'searching', 'approval', 'question', 'error', 'finished', 'ratelimit', 'sleeping', 'dizzy']);
  for (const t of [core.COL, core.TINT, core.MOUTH]) assert.deepEqual(Object.keys(t), core.STATES);
  assert.deepEqual(Object.keys(core.GLOW), ['working', 'thinking', 'searching', 'approval', 'error', 'finished', 'ratelimit']);
  assert.deepEqual(Object.keys(core.BADGE), ['working', 'thinking', 'searching', 'approval', 'question', 'error', 'finished', 'ratelimit']);
  assert.deepEqual(core.MKEYS, ['mouth', 'smile', 'tongue', 'mround', 'mskew', 'wavy']);
  for (const row of Object.values(core.MOUTH)) assert.equal(row.length, 6);
  assert.deepEqual(Object.keys(core.EMOUTH), ['love', 'surprised', 'proud', 'wink', 'yawn', 'happy', 'annoyed']);
  assert.deepEqual([...core.BUSY], ['working', 'thinking', 'searching']);
});

test('mouthFx: hunting chatter, meows, panting and snoring', () => {
  assert.equal(core.mouthFx('searching', 0), 0);
  assert.equal(core.mouthFx('searching', 2.0), 0, 'quiet part of the 2.6 s cycle');
  assert.ok(core.mouthFx('searching', .55) > .15, 'mid burst');
  near(core.mouthFx('approval', .196), .5);
  assert.equal(core.mouthFx('approval', .7), 0);
  near(core.mouthFx('ratelimit', 1 / (4 * 2.8)), .07);
  near(core.mouthFx('sleeping', Math.PI / 3), .07);
  assert.equal(core.mouthFx('idle', 1.234), 0);
});

test('one file serves both worlds: require() and a plain script that sets one global', () => {
  const src = fs.readFileSync(new URL('../../design/prototype/cat-core.js', import.meta.url), 'utf8');
  const sandbox = {};
  vm.runInNewContext(src, sandbox);
  assert.equal(typeof sandbox.CatCore, 'object');
  assert.equal(sandbox.CatCore.VERSION, 1);
  assert.deepEqual(Object.keys(sandbox.CatCore).sort(), Object.keys(core).sort());
  assert.equal(Object.keys(sandbox).length, 1, 'the page sees exactly one new global');
  assert.ok(!/\bMath\.random\b/.test(src.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, '').replace(/\(\)=>Math\.random\(\)/g, '')), 'the only Math.random is the late-bound default');
});
