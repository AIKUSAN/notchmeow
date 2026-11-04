import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const require = createRequire(import.meta.url);
const core = require('../../design/prototype/cat-core.js');
const fixture = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/personality-cases.json', import.meta.url), 'utf8'));
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const M = t => core.persMultipliers(t);

test('six traits and six presets, exactly as approved', () => {
  assert.deepEqual(core.TRAITS.map(t => t[0]), ['energy', 'curiosity', 'chatty', 'affection', 'sass', 'mischief']);
  assert.deepEqual(core.TRAITS.map(t => t[1]), ['Energy', 'Curiosity', 'Chattiness', 'Affection', 'Sass', 'Mischief']);
  assert.deepEqual(core.TRAITS.map(t => [t[2], t[3]]), [['sleepy', 'bouncy'], ['aloof', 'nosy'], ['quiet', 'talkative'], ['independent', 'cuddly'], ['easy-going', 'grumpy'], ['well-behaved', 'troublemaker']]);
  assert.deepEqual(Object.keys(core.PERSONAS), ['balanced', 'chill', 'grumpy', 'sweet', 'hyper', 'chatty']);
  const row = n => core.TRAIT_KEYS.map(k => core.PERSONAS[n][k]);
  assert.deepEqual(row('balanced'), [.5, .5, .5, .5, .5, .5]);
  assert.deepEqual(row('chill'), [.12, .35, .3, .65, .3, .2]);
  assert.deepEqual(row('grumpy'), [.4, .3, .45, .15, .95, .3]);
  assert.deepEqual(row('sweet'), [.5, .55, .55, 1, .1, .3]);
  assert.deepEqual(row('hyper'), [1, .9, .75, .5, .3, 1]);
  assert.deepEqual(row('chatty'), [.6, .7, 1, .6, .35, .5]);
});

test('Balanced changes nothing: every multiplier is 1, every addition 0, no idle habit, a poke annoys', () => {
  const m = M(core.PERSONAS.balanced);
  for (const k of ['speed', 'hop', 'blinkEvery', 'gaze', 'earFlickEvery', 'chatter', 'slowBlinkEvery']) near(m[k], 1);
  for (const k of ['pupil', 'smile', 'skew', 'blush', 'lid', 'earBack']) near(m[k], 0);
  assert.deepEqual(m.idle, { yawn: false, zoomies: false, mew: false, purr: false, hmph: false, wink: false });
  assert.equal(m.poke, 'annoyed'); assert.equal(m.pokeHiss, false);
});

test('each preset switches on its own habits', () => {
  assert.equal(M(core.PERSONAS.chill).idle.yawn, true); assert.ok(M(core.PERSONAS.chill).lid > .3); near(M(core.PERSONAS.chill).speed, core.tm(.12, .55, 1.5));
  const grumpy = M(core.PERSONAS.grumpy);
  assert.equal(grumpy.idle.hmph, true); assert.equal(grumpy.pokeHiss, true); assert.ok(grumpy.skew > .4 && grumpy.smile < 0 && grumpy.earBack > .15 && grumpy.lid > .2);
  const sweet = M(core.PERSONAS.sweet);
  assert.equal(sweet.idle.purr, true); assert.equal(sweet.poke, 'love'); assert.ok(sweet.blush > .3 && sweet.smile > .2);
  const hyper = M(core.PERSONAS.hyper);
  assert.equal(hyper.idle.zoomies, true); assert.equal(hyper.idle.wink, true); near(hyper.speed, 1.5); near(hyper.hop, 1.4); near(hyper.blinkEvery, .75);
  assert.equal(M(core.PERSONAS.chatty).idle.mew, true); near(M(core.PERSONAS.chatty).chatter, 1.4);
});

test('the thresholds are strict: the behaviour switches on just past the line, not on it', () => {
  assert.equal(M({ energy: .29 }).idle.yawn, true); assert.equal(M({ energy: .3 }).idle.yawn, false);
  assert.equal(M({ chatty: .7 }).idle.mew, false); assert.equal(M({ chatty: .71 }).idle.mew, true);
  assert.equal(M({ affection: .75 }).idle.purr, false); assert.equal(M({ affection: .76 }).idle.purr, true);
  assert.equal(M({ sass: .75 }).idle.hmph, false); assert.equal(M({ sass: .76 }).idle.hmph, true);
  assert.equal(M({ mischief: .65 }).idle.wink, false); assert.equal(M({ mischief: .66 }).idle.wink, true);
  assert.equal(M({ mischief: .75, energy: .8 }).idle.zoomies, false); assert.equal(M({ mischief: .76, energy: .7 }).idle.zoomies, false); assert.equal(M({ mischief: .76, energy: .71 }).idle.zoomies, true);
  assert.equal(M({ affection: .75, sass: .1 }).poke, 'annoyed'); assert.equal(M({ affection: .76, sass: .4 }).poke, 'annoyed'); assert.equal(M({ affection: .76, sass: .39 }).poke, 'love');
  assert.equal(M({ sass: .7 }).pokeHiss, false); assert.equal(M({ sass: .71 }).pokeHiss, true);
});

test('hand-edited values: out of range is held to 0…1, missing or odd values count as 0.5', () => {
  assert.deepEqual(M({ energy: 7, sass: -3 }), M({ energy: 1, sass: 0 }));
  assert.deepEqual(M(undefined), M(core.PERSONAS.balanced));
  assert.deepEqual(M(null), M(core.PERSONAS.balanced));
  assert.deepEqual(M({}), M(core.PERSONAS.balanced));
  assert.deepEqual(M({ energy: 'high', curiosity: NaN, chatty: Infinity }), M(core.PERSONAS.balanced));
  for (const k of ['speed', 'hop', 'gaze', 'chatter', 'blinkEvery', 'earFlickEvery', 'slowBlinkEvery']) {
    for (const v of [-5, 5]) assert.ok(M({ energy: v, curiosity: v, chatty: v, affection: v })[k] > 0, `${k} stays positive at ${v}`);
  }
  assert.deepEqual(core.normPers({ energy: 2, sass: 'x', extra: 1, preset: 'custom' }), { energy: 1, curiosity: .5, chatty: .5, affection: .5, sass: .5, mischief: .5 });
});

test('moving a slider turns the preset into Custom without touching the original', () => {
  const sweet = core.personaNamed('sweet'), before = JSON.stringify(sweet);
  assert.equal(sweet.preset, 'sweet'); assert.equal(sweet.affection, 1);
  const moved = core.slide(sweet, 'sass', .9);
  assert.equal(JSON.stringify(sweet), before);
  assert.equal(moved.preset, 'custom'); assert.equal(moved.sass, .9); assert.equal(moved.affection, 1);
  assert.equal(core.slide(sweet, 'sass', 4).sass, 1);
  assert.equal(core.slide(sweet, 'sass', -1).sass, 0);
  assert.equal(core.slide(sweet, 'nonsense', .3).preset, 'sweet', 'an unknown trait changes nothing');
  assert.equal(core.slide(sweet, 'sass', NaN).preset, 'sweet', 'NaN changes nothing');
  assert.equal(core.personaNamed('nope').preset, 'balanced');
  assert.equal(core.personaNamed('constructor').preset, 'balanced');
});

test('personality-cases.json: the presets table and every case replay from their inputs', () => {
  assert.equal(fixture.version, 1);
  assert.deepEqual(fixture.traits.map(t => t.key), core.TRAIT_KEYS);
  assert.deepEqual(Object.keys(fixture.presets), Object.keys(core.PERSONAS));
  for (const [name, p] of Object.entries(fixture.presets)) assert.deepEqual(p, core.PERSONAS[name]);
  assert.ok(fixture.cases.length >= 30);
  for (const c of fixture.cases) assert.deepEqual(compare(JSON.parse(JSON.stringify(M(c.traits))), c.out), [], c.name);
  for (const c of fixture.slide) assert.deepEqual(compare(core.slide(core.personaNamed(c.from), c.trait, c.value), c.out), [], `${c.from} ${c.trait}`);
  assert.ok(fixture.cases.some(c => c.name.includes('out of range')) && fixture.cases.some(c => c.name.includes('missing')));
});
