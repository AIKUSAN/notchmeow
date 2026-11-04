import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const core = require('../../design/prototype/cat-core.js');
const fixture = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/presets.json', import.meta.url), 'utf8'));
const near = (a, b, eps = 1e-12) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);

// The frozen cat IDs, written out here on purpose: renaming one in cat-core.js and regenerating must fail this test.
const FROZEN_IDS = ['shrimpy', 'momo', 'ginger', 'midnight', 'latte', 'patches', 'blue', 'snow', 'oreo', 'mocha', 'silver', 'cloud', 'leo', 'button', 'puff', 'noodle'];

test('sixteen cats with frozen IDs, Shrimpy first and Momo second', () => {
  assert.deepEqual(core.CAT_IDS, FROZEN_IDS);
  assert.deepEqual(fixture.ids, FROZEN_IDS);
  assert.deepEqual(Object.keys(core.PRESETS).sort(), [...FROZEN_IDS].sort());
  for (const id of FROZEN_IDS) assert.equal(core.PRESETS[id].name, id, `${id}: name equals its key`);
  assert.deepEqual(core.MORE, FROZEN_IDS.slice(2));
});

test('voice: Shrimpy -1, Momo +1, the extra coats 0, every kitten +3', () => {
  assert.equal(core.PRESETS.shrimpy.voice, -1);
  assert.equal(core.PRESETS.momo.voice, 1);
  for (const id of core.MORE) assert.equal(core.PRESETS[id].voice, 0, id);
  for (const id of FROZEN_IDS) assert.equal(core.kittenOf(core.PRESETS[id]).voice, 3, `${id} kitten`);
  for (const id of FROZEN_IDS) {
    assert.equal(fixture.cats[id].voice, id === 'shrimpy' ? -1 : id === 'momo' ? 1 : 0, `fixture ${id}`);
    assert.equal(fixture.kittens[id].voice, 3, `fixture ${id} kitten`);
  }
});

test('the approved Shrimpy and Momo numbers (spec: approved character design)', () => {
  const m = core.PRESETS.momo, s = core.PRESETS.shrimpy;
  assert.deepEqual([m.rx, m.ry, m.n, m.fluff], [1.12, .9, 2.2, 0]);
  assert.deepEqual([m.ear.h, m.ear.bw, m.ear.rot], [.8, .56, .5]);
  assert.equal(m.top, '#3D3D41'); assert.equal(m.white, '#F6F4F1'); assert.equal(m.inner, '#B98288'); assert.equal(m.nose, '#E89AA6');
  assert.deepEqual(m.iris, ['#7E8A45', '#D1B85F']); assert.equal(m.lidTint, '#D9BE62'); assert.equal(m.ink, '#E4D592');
  assert.deepEqual([s.rx, s.ry, s.n, s.fluff], [1.16, .92, 2.2, 1]);
  assert.deepEqual(s.ruff, { rx: 1.3, ry: .97, dy: .2, col: ['#B49C7A', '#7E6750'] });
  assert.deepEqual([s.ear.h, s.ear.bw, s.ear.rot, s.ear.tuft], [.8, .4, .44, 1]);
  assert.equal(s.top, '#A08A70'); assert.equal(s.bot, '#6E5B49'); assert.equal(s.stripe, '#2E241D'); assert.equal(s.nose, '#C07A62');
  assert.deepEqual(s.iris, ['#C9D18A', '#6F8445']); assert.equal(s.ink, '#231A14');
  assert.deepEqual([m.whisk2.rows, m.whisk2.cols, m.whisk2.brow], [3, 2, 2]);
  assert.deepEqual([s.whisk2.rows, s.whisk2.cols, s.whisk2.brow], [3, 3, 3]);
});

test('makeCat fills the shorthair template and merges nested overrides', () => {
  const c = core.makeCat({ name: 'x', ear: { h: .9 }, eye: { w: .3 }, whisk2: { len: 1 }, top: '#000000' });
  assert.deepEqual([c.coat, c.rx, c.ry, c.n, c.voice, c.fluff, c.ruff], ['solid', 1.12, .9, 2.2, 0, 0, null]);
  assert.deepEqual([c.ear.h, c.ear.bw, c.ear.rot, c.ear.cx], [.9, .5, .46, .7]);
  assert.deepEqual([c.eye.w, c.eye.h, c.eye.round], [.3, .17, 1]);
  assert.deepEqual([c.whisk2.len, c.whisk2.rows, c.whisk2.cols], [1, 3, 2]);
  assert.equal(c.top, '#000000');
});

test('kittenOf follows the approved rules and never touches its parent', () => {
  for (const id of ['shrimpy', 'momo', 'puff', 'noodle']) {
    const p = core.PRESETS[id], before = JSON.stringify(p), k = core.kittenOf(p);
    assert.equal(JSON.stringify(p), before, `${id}: parent unchanged`);
    assert.deepEqual([k.kitten, k.base, k.label], [true, id, `${p.label} kitten`]);
    near(k.rx, p.rx * .97); near(k.ry, p.ry * 1.02); assert.equal(k.n, 2.05);
    near(k.ear.h, p.ear.h * 1.12); near(k.ear.bw, p.ear.bw * 1.06); assert.equal(k.ear.tuft, 0);
    near(k.eye.w, p.eye.w * 1.2); near(k.eye.h, p.eye.h * 1.32); assert.equal(k.eye.round, 1); near(k.eye.th, p.eye.th + .02);
    near(k.nosePh, p.nosePh + .08); near(k.noseW, p.noseW * .85); near(k.noseH, p.noseH * .85);
    near(k.whisk2.len, p.whisk2.len * .7); assert.equal(k.whisk2.brow, 1);
    near(k.pupil0, Math.max(p.pupil0, .18));
    if (p.ruff) { near(k.ruff.rx, p.ruff.rx * .94); near(k.ruff.ry, p.ruff.ry * .92); } else assert.equal(k.ruff, null);
    assert.equal(k.top, p.top); assert.equal(k.coat, p.coat);
  }
});

test('catById: an unknown, odd or inherited ID falls back to Shrimpy', () => {
  assert.equal(core.catById('momo'), core.PRESETS.momo);
  assert.equal(core.catById('noodle'), core.PRESETS.noodle);
  for (const bad of ['', 'SHRIMPY', 'siamese', 'calico', 'constructor', '__proto__', 'toString', 'hasOwnProperty', null, undefined, 42, {}, ['momo']]) {
    assert.equal(core.catById(bad), core.PRESETS.shrimpy, `${String(bad)} falls back`);
  }
});

test('every coat has what the renderer reads', () => {
  const coats = new Set(['tuxedo', 'tabby', 'point', 'calico', 'solid']);
  for (const id of FROZEN_IDS) {
    const p = core.PRESETS[id];
    assert.ok(coats.has(p.coat), `${id}: coat type ${p.coat}`);
    for (const k of ['top', 'bot', 'inner', 'nose', 'noseLine', 'liner', 'ink', 'mouthLine', 'whisk', 'padDot', 'paw', 'bean', 'hair', 'hairDark', 'hairLight']) assert.match(p[k], /^(#[0-9A-Fa-f]{6}|rgba\()/, `${id}.${k}`);
    assert.equal(p.iris.length, 2, `${id}: iris`);
    for (const k of ['rx', 'ry', 'n', 'earSpread', 'noseW', 'noseH', 'nosePh', 'pupil0']) assert.equal(typeof p[k], 'number', `${id}.${k}`);
    for (const k of ['h', 'bw', 'rot', 'tip']) assert.equal(typeof p.ear[k], 'number', `${id}.ear.${k}`); // ear.cx is optional (default .95)
    for (const k of ['th', 'ph', 'w', 'h', 'round']) assert.equal(typeof p.eye[k], 'number', `${id}.eye.${k}`);
    assert.equal(p.blushAt.length, 2, `${id}: blushAt`);
    if (p.coat === 'calico') assert.ok(Array.isArray(p.patches) && p.patches.length > 0, `${id}: patches`);
    if (p.coat === 'point') assert.ok(p.point && p.earCols, `${id}: point colours`);
    if (p.coat === 'tabby') assert.ok(p.stripe && p.light && p.chinCol, `${id}: tabby colours`);
    if (p.coat === 'tuxedo') assert.ok(p.white, `${id}: white`);
  }
  assert.deepEqual(FROZEN_IDS.filter(id => core.PRESETS[id].ear.fold), ['button']);
  assert.deepEqual(FROZEN_IDS.filter(id => core.PRESETS[id].hairless), ['noodle']);
  assert.deepEqual(FROZEN_IDS.filter(id => core.PRESETS[id].wrinkles), ['noodle']);
});

test('presets.json is the resolved table, kittens included', () => {
  assert.deepEqual(Object.keys(fixture.cats), FROZEN_IDS);
  assert.deepEqual(Object.keys(fixture.kittens), FROZEN_IDS);
  assert.deepEqual(fixture.cats.momo, JSON.parse(JSON.stringify(core.PRESETS.momo)));
  assert.equal(fixture.kittens.shrimpy.kitten, true);
  assert.equal(fixture.kittens.shrimpy.n, 2.05);
  assert.equal(fixture.cats.shrimpy.kitten, undefined);
});
