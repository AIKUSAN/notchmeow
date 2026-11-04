import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const IDS = core.CAT_IDS;
const TRAITS = core.TRAIT_KEYS;
const BALANCED = { preset: 'balanced', energy: .5, curiosity: .5, chatty: .5, affection: .5, sass: .5, mischief: .5 };
const clean = core.cleanCatSettings;
const deepFreeze = v => { if (v && typeof v === 'object') { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };
const cats = (id, entry) => ({ cats: { [id]: entry } });
const NOT_OBJECTS = [null, undefined, 'junk', '', 7, 0, NaN, true, false, [], [1, 2], ['character']];

test('the frozen words: FOLLOW, the two motion styles in Settings order, the four collar styles', () => {
  assert.equal(core.FOLLOW, 'follow');
  assert.deepEqual(core.MOTION_STYLES, ['playful', 'classic']);
  assert.deepEqual([...core.MOTION_STYLES].sort(), Object.keys(core.PROFILES).sort(), 'every motion profile is a style and the other way round');
  assert.ok(!core.MOTION_STYLES.includes('follow') && !core.COLLAR_STYLES.includes('follow'), 'follow is an override, never a style');
});

test('a fresh install: Shrimpy, Playful, collar off, no fur lines, 16 cats that follow the globals and are Balanced', () => {
  const d = core.defaultCatSettings();
  assert.deepEqual(Object.keys(d), ['character', 'motionStyle', 'collar', 'furLines', 'cats']);
  assert.deepEqual([d.character, d.motionStyle, d.collar, d.furLines], ['shrimpy', 'playful', 'off', false]);
  assert.deepEqual(Object.keys(d.cats), IDS);
  assert.deepEqual(IDS.slice(0, 2), ['shrimpy', 'momo']);
  for (const id of IDS) assert.deepEqual(d.cats[id], { motion: 'follow', collar: 'follow', personality: BALANCED }, id);
  assert.notEqual(core.defaultCatSettings().cats.momo, d.cats.momo, 'every call gives fresh objects');
});

test('anything that is not an object gives the defaults, and so does an object with nothing in it', () => {
  for (const raw of [...NOT_OBJECTS, {}, { cats: [] }, { cats: 'x' }, { cats: null }, { cats: 7 }]) assert.deepEqual(clean(raw), core.defaultCatSettings(), String(JSON.stringify(raw)));
});

test('a valid value comes back as it went in, and cleaning twice changes nothing', () => {
  const valid = clean({ character: 'momo', motionStyle: 'classic', collar: 'band', furLines: true, cats: {
    momo: { motion: 'playful', collar: 'kerchief', personality: core.personaNamed('chill') },
    shrimpy: { motion: 'classic', collar: 'off', personality: { ...core.personaNamed('sweet'), preset: 'sweet' } },
    ginger: { motion: 'follow', collar: 'tag', personality: { preset: 'custom', energy: .27, curiosity: .83, chatty: .41, affection: .58, sass: .12, mischief: .99 } } } });
  assert.deepEqual([valid.character, valid.motionStyle, valid.collar, valid.furLines], ['momo', 'classic', 'band', true]);
  assert.deepEqual(valid.cats.momo, { motion: 'playful', collar: 'kerchief', personality: core.personaNamed('chill') });
  assert.deepEqual(valid.cats.shrimpy.personality.preset, 'sweet');
  assert.deepEqual(valid.cats.ginger, { motion: 'follow', collar: 'tag', personality: { preset: 'custom', energy: .27, curiosity: .83, chatty: .41, affection: .58, sass: .12, mischief: .99 } });
  assert.deepEqual(clean(valid), valid);
  assert.deepEqual(clean(JSON.parse(JSON.stringify(valid))), valid, 'it survives being written as JSON and read back');
});

test('the character: the 16 frozen IDs stay, everything else is Shrimpy, prototype names included', () => {
  for (const id of IDS) assert.equal(clean({ character: id }).character, id);
  for (const bad of ['tiger', 'Momo', 'MOMO', ' momo', 'momo ', '', 'momo kitten', 'siamese', '__proto__', 'constructor', 'toString', 'hasOwnProperty', null, undefined, 7, true, {}, ['momo']]) assert.equal(clean({ character: bad }).character, 'shrimpy', String(bad));
});

test('the global motion style and collar: only the frozen words count, and "follow" is not one of them', () => {
  for (const s of core.MOTION_STYLES) assert.equal(clean({ motionStyle: s }).motionStyle, s);
  for (const bad of ['follow', 'Classic', 'PLAYFUL', ' classic', 'bogus', '', null, 7, true, ['classic']]) assert.equal(clean({ motionStyle: bad }).motionStyle, 'playful', String(bad));
  for (const s of core.COLLAR_STYLES) assert.equal(clean({ collar: s }).collar, s);
  for (const bad of ['follow', 'scarf', 'Tag', ' tag', 'bowtie', '', null, 7, true, ['band']]) assert.equal(clean({ collar: bad }).collar, 'off', String(bad));
});

test('fur lines are on only for a real boolean true', () => {
  assert.equal(clean({ furLines: true }).furLines, true);
  for (const bad of [false, 1, 0, 'true', 'yes', 'on', 'TRUE', null, [true], { value: true }, 7]) assert.equal(clean({ furLines: bad }).furLines, false, String(JSON.stringify(bad)));
});

test('a cat\'s own motion and collar: a valid word stays, anything else means "follow", and "off" is a real override', () => {
  for (const m of ['follow', ...core.MOTION_STYLES]) assert.equal(clean(cats('momo', { motion: m })).cats.momo.motion, m);
  for (const bad of ['Classic', 'bogus', '', null, 7, true, ['classic'], {}]) assert.equal(clean(cats('momo', { motion: bad })).cats.momo.motion, 'follow', String(JSON.stringify(bad)));
  for (const c of ['follow', ...core.COLLAR_STYLES]) assert.equal(clean(cats('momo', { collar: c })).cats.momo.collar, c);
  for (const bad of ['scarf', 'Tag', 'bogus', '', null, 7, true, ['tag'], {}]) assert.equal(clean(cats('momo', { collar: bad })).cats.momo.collar, 'follow', String(JSON.stringify(bad)));
  assert.equal(clean({ collar: 'tag', ...cats('momo', { collar: 'off' }) }).cats.momo.collar, 'off', 'a cat can be set to no collar while the global one is on');
});

test('the cats map: always the 16 cats in order, unknown IDs and unknown keys dropped, a bad entry is the defaults', () => {
  const raw = { theme: 'dark', cats: { tiger: { motion: 'classic' }, momo: 'x', ginger: null, noodle: [], puff: { motion: 'classic', wardrobe: 'hat', personality: { preset: 'balanced', label: 'Balanced', hat: 1 } }, constructor: { motion: 'classic' }, ['__proto__']: { motion: 'classic' } } };
  const out = clean(raw);
  assert.deepEqual(Object.keys(out), ['character', 'motionStyle', 'collar', 'furLines', 'cats']);
  assert.deepEqual(Object.keys(out.cats), IDS);
  for (const id of IDS) assert.deepEqual(Object.keys(out.cats[id]), ['motion', 'collar', 'personality'], id);
  assert.deepEqual(out.cats.momo, core.defaultCatSettings().cats.momo);
  assert.deepEqual(out.cats.ginger, core.defaultCatSettings().cats.ginger);
  assert.deepEqual(out.cats.puff, { motion: 'classic', collar: 'follow', personality: BALANCED });
  assert.equal(Object.getPrototypeOf(out.cats), Object.prototype);
  assert.ok(!Object.keys(out.cats).includes('tiger') && !Object.keys(out.cats).includes('constructor'));
});

test('personality: the six presets, as an object and as the JSON text the Mac stores, come back the same', () => {
  for (const name of Object.keys(core.PERSONAS)) {
    const p = core.personaNamed(name);
    assert.deepEqual(core.cleanPersonality(p), p, name);
    assert.deepEqual(core.cleanPersonality(JSON.stringify(p)), p, `${name} as JSON text`);
    assert.deepEqual(Object.keys(core.cleanPersonality(p)), ['preset', ...TRAITS]);
  }
});

test('personality: Custom is the word "custom" with the six traits, and a slider move stays Custom even back on a preset\'s numbers', () => {
  const moved = core.slide(core.personaNamed('chill'), 'sass', .9);
  assert.equal(moved.preset, 'custom');
  assert.deepEqual(core.cleanPersonality(moved), moved);
  assert.deepEqual(core.cleanPersonality(JSON.stringify(moved)), moved);
  const back = core.slide(core.personaNamed('chill'), 'energy', .12);
  assert.deepEqual(back, { ...core.personaNamed('chill'), preset: 'custom' });
  assert.equal(core.cleanPersonality(back).preset, 'custom');
  assert.ok(!('custom' in core.PERSONAS), 'custom is not one of the six presets');
});

test('personality: a preset name is kept only while the traits are still that preset\'s', () => {
  const chill = core.personaNamed('chill');
  assert.equal(core.cleanPersonality({ ...chill, energy: .12000000000000001 }).preset, 'chill', 'float noise is within the tolerance');
  assert.equal(core.cleanPersonality({ ...chill, energy: .120000000001 }).preset, 'chill', '1e-12 away is still Chill');
  assert.equal(core.cleanPersonality({ ...chill, energy: .120001 }).preset, 'custom', '1e-6 away is a different personality');
  assert.equal(core.cleanPersonality({ ...chill, energy: .9 }).preset, 'custom');
  assert.equal(core.cleanPersonality({ ...chill, preset: 'sweet' }).preset, 'custom', 'a name that does not match the traits');
  assert.equal(core.cleanPersonality({ ...chill, preset: 'Chill' }).preset, 'custom');
  assert.equal(core.cleanPersonality({ ...chill, preset: 'moody' }).preset, 'custom');
  assert.equal(core.cleanPersonality({ ...chill, preset: 7 }).preset, 'custom');
  const noName = { ...chill }; delete noName.preset;
  assert.equal(core.cleanPersonality(noName).preset, 'custom', 'traits that equal a preset but name none are Custom');
  assert.deepEqual(core.cleanPersonality({ preset: 'chill' }), { preset: 'custom', ...Object.fromEntries(TRAITS.map(k => [k, .5])) }, 'a name alone: the traits are missing, so 0.5, which is not Chill');
  assert.deepEqual(core.cleanPersonality({ preset: 'balanced' }), BALANCED);
});

test('personality: JSON that is not JSON, or not an object, is Balanced', () => {
  for (const bad of ['', ' ', 'not json', '{', '{"energy":0.2', "{'energy':0.2}", '{"energy":0.2,}', '{"energy":NaN}', '{"energy":Infinity}', '{"energy":0.2} x', 'undefined', '[1,2]', 'null', '"x"', '42', 'true', '[]', '{"preset"', null, undefined, 7, true, [], [1], NaN]) {
    assert.deepEqual(core.cleanPersonality(bad), BALANCED, String(JSON.stringify(bad)));
  }
  assert.deepEqual(core.cleanPersonality('{}'), { preset: 'custom', ...Object.fromEntries(TRAITS.map(k => [k, .5])) }, 'an object with nothing in it is not "nothing stored": its traits are the missing ones');
});

test('personality: traits are held to 0..1, a missing or non-number trait is 0.5, and nothing is NaN', () => {
  const wrong = { energy: 'high', curiosity: null, chatty: true, affection: [1], sass: {}, mischief: '0.9' };
  assert.deepEqual(core.cleanPersonality(wrong), { preset: 'custom', ...Object.fromEntries(TRAITS.map(k => [k, .5])) });
  assert.deepEqual(core.cleanPersonality(JSON.stringify(wrong)), core.cleanPersonality(wrong));
  const wild = core.cleanPersonality({ energy: 7, curiosity: -2, chatty: NaN, affection: Infinity, sass: -Infinity, mischief: 1e300 });
  assert.deepEqual([wild.energy, wild.curiosity, wild.chatty, wild.affection, wild.sass, wild.mischief], [1, 0, .5, .5, .5, 1]);
  for (const v of Object.values(wild)) assert.ok(typeof v === 'string' || Number.isFinite(v));
  assert.equal(Object.is(core.cleanPersonality({ energy: -0 }).energy, -0), false, 'minus zero is stored as 0');
});

test('applyToAllCats copies one cat\'s motion override, collar override and personality to all 16, and nothing else', () => {
  const s = clean({ character: 'momo', motionStyle: 'classic', collar: 'band', furLines: true, cats: {
    ginger: { motion: 'playful', collar: 'off', personality: { ...core.personaNamed('hyper') } }, momo: { motion: 'classic', collar: 'tag', personality: core.personaNamed('grumpy') } } });
  const before = JSON.stringify(s);
  const out = core.applyToAllCats(s, 'ginger');
  assert.equal(JSON.stringify(s), before, 'the input is not touched');
  assert.deepEqual([out.character, out.motionStyle, out.collar, out.furLines], ['momo', 'classic', 'band', true]);
  assert.deepEqual(Object.keys(out.cats), IDS);
  for (const id of IDS) assert.deepEqual(out.cats[id], { motion: 'playful', collar: 'off', personality: core.personaNamed('hyper') }, id);
  out.cats.momo.personality.energy = .01;
  assert.equal(out.cats.ginger.personality.energy, 1, 'no two cats share one personality object');
  assert.equal(core.applyToAllCats(s, 'shrimpy').cats.momo.motion, 'follow', 'follow is copied as follow: the cats keep following the global style');
  assert.deepEqual(core.applyToAllCats(s, 'tiger'), core.applyToAllCats(s, 'shrimpy'), 'an unknown cat is Shrimpy');
  assert.deepEqual(core.applyToAllCats(core.applyToAllCats(s, 'ginger'), 'ginger'), core.applyToAllCats(s, 'ginger'), 'doing it twice changes nothing');
  assert.deepEqual(core.applyToAllCats({ cats: { momo: { motion: 'classic' } } }, 'momo').cats.noodle.motion, 'classic', 'a dirty input is cleaned first');
});

test('motionFor and collarFor: the cat\'s own word, else the global one', () => {
  const s = clean({ motionStyle: 'classic', collar: 'band', cats: { momo: { motion: 'playful', collar: 'off' }, ginger: { motion: 'follow', collar: 'kerchief' } } });
  assert.deepEqual(['momo', 'ginger', 'shrimpy'].map(id => core.motionFor(s, id)), ['playful', 'classic', 'classic']);
  assert.deepEqual(['momo', 'ginger', 'shrimpy'].map(id => core.collarFor(s, id)), ['off', 'kerchief', 'band']);
  assert.equal(core.motionFor(s, 'tiger'), 'classic', 'an unknown cat is Shrimpy, which follows');
  assert.equal(core.collarFor(null, 'momo'), 'off');
  assert.equal(core.motionFor(null, 'momo'), 'playful');
});

test('engineCfg is what the engine reads: the global style, the overrides that exist, every personality', () => {
  const s = clean({ motionStyle: 'classic', cats: { momo: { motion: 'playful', personality: core.personaNamed('sweet') }, ginger: { motion: 'follow' }, noodle: { motion: 'bogus' } } });
  const cfg = core.engineCfg(s);
  assert.deepEqual(Object.keys(cfg), ['motion', 'override', 'pers']);
  assert.equal(cfg.motion, 'classic');
  assert.deepEqual(cfg.override, { momo: 'playful' });
  assert.deepEqual(Object.keys(cfg.pers), IDS);
  assert.deepEqual(cfg.pers.momo, core.personaNamed('sweet'));
  const make = (preset, id) => new core.CatEngine(preset, { cfg: { ...core.engineCfg(s), zoomAfter: core.ZOOM_AFTER_MS }, quiet: true, now: () => 0, rand: core.rng(1), state: 'idle' });
  assert.equal(make(core.PRESETS.momo).motion, 'playful');
  assert.equal(make(core.PRESETS.ginger).motion, 'classic');
  assert.equal(make(core.PRESETS.shrimpy).motion, 'classic');
  assert.equal(make(core.kittenOf(core.PRESETS.momo)).motion, 'playful', 'a kitten plays its parent\'s style');
  assert.equal(make(core.kittenOf(core.PRESETS.momo)).pers.preset, 'sweet', 'and wears its parent\'s personality');
});

test('the input is never changed, even when it is frozen', () => {
  const raw = deepFreeze({ character: 'momo', cats: { momo: { motion: 'classic', personality: { preset: 'chill', energy: .12 } } } });
  assert.doesNotThrow(() => clean(raw));
  assert.doesNotThrow(() => core.applyToAllCats(raw, 'momo'));
});

test('hostile values never throw: 3000 random settings come out valid, and cleaning them again changes nothing', () => {
  const r = core.rng(2026), pool = ['momo', 'tiger', 'classic', 'playful', 'follow', 'off', 'band', 'tag', 'kerchief', '', ' ', 'chill', 'custom', '{', '{"energy":2}', '{"preset":"sweet","affection":1,"energy":0.5,"curiosity":0.55,"chatty":0.55,"sass":0.1,"mischief":0.3}', '__proto__', 'constructor', null, true, false, 0, 1, -1, .5, 7, 1e300, [], [1], {}, { energy: 9 }, { preset: 'hyper' }];
  const pick = () => pool[Math.floor(r() * pool.length)];
  const entry = () => ({ motion: pick(), collar: pick(), personality: pick() });
  const valid = s => IDS.includes(s.character) && core.MOTION_STYLES.includes(s.motionStyle) && core.COLLAR_STYLES.includes(s.collar) && typeof s.furLines === 'boolean'
    && JSON.stringify(Object.keys(s.cats)) === JSON.stringify(IDS)
    && IDS.every(id => ['follow', ...core.MOTION_STYLES].includes(s.cats[id].motion) && ['follow', ...core.COLLAR_STYLES].includes(s.cats[id].collar)
      && TRAITS.every(k => Number.isFinite(s.cats[id].personality[k]) && s.cats[id].personality[k] >= 0 && s.cats[id].personality[k] <= 1)
      && (s.cats[id].personality.preset === 'custom' || own(core.PERSONAS, s.cats[id].personality.preset)));
  const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
  for (let i = 0; i < 3000; i++) {
    const raw = { character: pick(), motionStyle: pick(), collar: pick(), furLines: pick(), cats: r() < .1 ? pick() : Object.fromEntries(IDS.filter(() => r() < .5).map(id => [id, r() < .1 ? pick() : entry()])) };
    const out = clean(raw);
    assert.ok(valid(out), JSON.stringify(raw));
    assert.deepEqual(clean(out), out);
    assert.ok(valid(core.applyToAllCats(raw, pick())));
    assert.doesNotThrow(() => core.engineCfg(raw));
  }
});

const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/settings-cases.json', import.meta.url), 'utf8'));
const roundTrip = v => JSON.parse(JSON.stringify(v));

test('settings-cases.json: the frozen words, the defaults and the cat IDs are the core\'s', () => {
  assert.deepEqual(fx.ids, IDS);
  assert.equal(fx.follow, core.FOLLOW);
  assert.deepEqual(fx.motionStyles, core.MOTION_STYLES);
  assert.deepEqual(fx.collarStyles, core.COLLAR_STYLES);
  assert.deepEqual(compare(roundTrip(core.defaultCatSettings()), fx.defaults), []);
});

test('settings-cases.json: every case replays from its own input', () => {
  for (const c of fx.cases) assert.deepEqual(compare(roundTrip(clean(c.raw)), c.out), [], c.name);
  for (const c of fx.personalities) assert.deepEqual(compare(roundTrip(core.cleanPersonality(c.raw)), c.out), [], c.name);
  for (const c of fx.applyAll) assert.deepEqual(compare(roundTrip(core.applyToAllCats(c.settings, c.from)), c.out), [], c.name);
  for (const c of fx.derived) {
    assert.deepEqual(compare(roundTrip(core.engineCfg(c.settings)), c.engineCfg), [], c.name);
    assert.deepEqual(IDS.map(id => core.motionFor(c.settings, id)), c.motionFor, c.name);
    assert.deepEqual(IDS.map(id => core.collarFor(c.settings, id)), c.collarFor, c.name);
  }
});

test('settings-cases.json: the inputs the spec worries about are in it (bad JSON, wrong types, unknown IDs, out-of-range traits, a valid value)', () => {
  const names = fx.cases.map(c => c.name), people = fx.personalities.map(c => c.name);
  for (const n of ['nothing stored', 'a fully valid value', 'an unknown character', 'follow is not a global style', 'fur lines as the number 1', 'overrides that are not valid', 'cats is an array', 'prototype names as cats', 'a personality that is not JSON', 'a personality stored as JSON text']) assert.ok(names.includes(n), n);
  for (const n of ['a cut-off object', 'NaN written in the text', 'wrong types', 'traits out of range', 'a name that does not match the traits', 'custom with the numbers of a preset', 'float noise on a preset is still the preset', 'JSON that is an array']) assert.ok(people.includes(n), n);
  assert.ok(fx.personalities.filter(c => typeof c.raw === 'string').length >= 14, 'text inputs');
  assert.ok(fx.cases.some(c => c.out.character === 'momo' && c.out.furLines === true), 'a valid value that keeps its settings');
});
