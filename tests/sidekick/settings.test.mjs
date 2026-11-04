import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
const core = createRequire(import.meta.url)('../../shared/sidekick-core.js');
const read = n => JSON.parse(fs.readFileSync(new URL(`../fixtures/sidekick/${n}`, import.meta.url), 'utf8'));
const dismissFx = read('dismiss-cases.json'), settingsFx = read('settings-cases.json');

test('the fixtures: every operation and every stored value gives what it records', () => {
  for (const c of dismissFx.cases) {
    let state = c.start;
    c.ops.forEach((o, i) => { state = core[o.op](state, o.kind); assert.deepEqual([state, core.DISMISS_KINDS.filter(k => core.muted(state, k))], [c.trail[i].state, c.trail[i].muted], c.name); });
  }
  for (const c of settingsFx.cases) assert.deepEqual(core.cleanSidekickSettings(c.raw), c.clean, c.name);
});

test('the five kinds are frozen, in this order, and two dismissals mute', () => {
  assert.deepEqual(core.DISMISS_KINDS, ['recap', 'stuck.loop', 'stuck.errors', 'stuck.waiting', 'stuck.silent']);
  assert.equal(core.MUTE_AT, 2);
  assert.deepEqual(core.NUDGE_KINDS, core.DISMISS_KINDS.slice(1), 'the nudges are the kinds after the recap');
});

test('the risk badge and the permission line are not a kind, so they can not be muted', () => {
  let s = null;
  for (let i = 0; i < 5; i++) s = core.dismiss(s, 'risk');
  assert.equal(core.muted(s, 'risk'), false);
  assert.deepEqual(s, core.cleanDismissals(null));
});

test('dismiss and unmute do not change the state they are given', () => {
  const s = { recap: 1, 'stuck.loop': 0, 'stuck.errors': 0, 'stuck.waiting': 0, 'stuck.silent': 0 };
  const frozen = JSON.stringify(s);
  core.dismiss(s, 'recap'); core.unmute(s, 'recap'); core.mute(s, 'recap');
  assert.equal(JSON.stringify(s), frozen);
});

test('mute is two dismissals at once, for the five kinds only', () => {
  for (const k of core.DISMISS_KINDS) assert.equal(core.mute(null, k)[k], core.MUTE_AT);
  assert.deepEqual(core.mute(null, 'risk'), core.cleanDismissals(null));
  assert.deepEqual(core.mute({ recap: 1 }, 'recap').recap, 2);
  assert.ok(core.muted(core.mute(null, 'stuck.silent'), 'stuck.silent'));
});

test('cleaning is idempotent and always gives the same shape, for 3000 random values', () => {
  let seed = 5;
  const rnd = n => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  const atoms = [null, undefined, true, false, 0, 1, 2, 3, -1, 1.5, 2.0, 'x', '2', [], [1], {}, { recap: 1 }, NaN, Infinity];
  const make = d => (d > 2 || rnd(3) === 0 ? atoms[rnd(atoms.length)] : Object.fromEntries(['on', 'local', 'dismissals', 'recap', 'stuck.loop', '__proto__', 'x'].filter(() => rnd(2)).map(k => [k, make(d + 1)])));
  for (let i = 0; i < 3000; i++) {
    const raw = make(0), once = core.cleanSidekickSettings(raw);
    assert.deepEqual(core.cleanSidekickSettings(once), once);
    assert.deepEqual(Object.keys(once), ['on', 'local', 'dismissals']);
    assert.deepEqual(Object.keys(once.dismissals), core.DISMISS_KINDS);
    assert.ok(Object.values(once.dismissals).every(v => [0, 1, 2].includes(v)));
    assert.equal(typeof once.on, 'boolean');
  }
  assert.equal({}.on, undefined);
});
