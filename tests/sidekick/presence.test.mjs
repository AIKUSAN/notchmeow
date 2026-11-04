import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
const core = createRequire(import.meta.url)('../../shared/sidekick-core.js');
const read = n => JSON.parse(fs.readFileSync(new URL(`../fixtures/sidekick/${n}`, import.meta.url), 'utf8'));
const presenceFx = read('presence-cases.json'), showFx = read('show-cases.json');

test('the fixtures: every signal and every gate input gives what it records', () => {
  for (const c of presenceFx.cases) {
    let state = c.start;
    for (const st of c.steps) { const r = core.presenceStep(state, st.signal, st.at); assert.deepEqual(r, { state: st.state, back: st.back }, `${c.name} @${st.at}`); state = r.state; }
  }
  for (const c of showFx.cases) assert.deepEqual(core.shouldShow(c.input), c.show, c.name);
});

test('the constants are the spec\'s: away at 300 s, back under 3 s, a note every 60 s, held 30 s and 2 minutes', () => {
  assert.deepEqual(core.IDLE, { AWAY_S: 300, BACK_S: 3 });
  assert.equal(core.NOTE_GAP_MS, 60000);
  assert.deepEqual(core.HOLD_MS, { nudge: 30000, recap: 120000 });
});

test('a fuzz of presence signals: back is told exactly when the last reason lets go, and never twice', () => {
  let seed = 3;
  const rnd = n => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  const types = ['lock', 'unlock', 'sleep', 'wake', 'displayOff', 'displayOn', 'idle', 'idle', 'idle', 'bogus'];
  for (let round = 0; round < 60; round++) {
    let state = round % 7 === 0 ? null : core.presenceInit(), t = 1_000_000, tellings = 0, awayStarts = 0;
    for (let i = 0; i < 200; i++) {
      t += rnd(400) * 1000;
      const sig = { type: types[rnd(types.length)] };
      if (sig.type === 'idle') sig.seconds = [0, 1, 2, 3, 100, 299, 300, 301, 900][rnd(9)];
      const wasAway = !!state && state.reasons.length > 0;
      const r = core.presenceStep(state, sig, t);
      const isAway = r.state.reasons.length > 0;
      assert.equal(r.state.wasAway, wasAway);
      assert.equal(r.back !== false, wasAway && !isAway);
      assert.deepEqual(r.state.reasons, ['lock', 'sleep', 'display', 'idle'].filter(x => r.state.reasons.includes(x)));
      assert.equal(r.state.awaySince === null, !isAway);
      if (r.back) { assert.ok(r.back.awayMs >= 0 && r.back.awaySince <= t && r.back.awayMs === t - r.back.awaySince); tellings++; }
      if (!wasAway && isAway) awayStarts++;
      state = r.state;
    }
    assert.equal(tellings, awayStarts - (state.reasons.length > 0 ? 1 : 0),`${tellings} backs for ${awayStarts} aways`);
  }
});

test('presenceStep does not change the state it is given', () => {
  const s = { reasons: ['lock'], awaySince: 5, wasAway: true };
  const frozen = JSON.stringify(s);
  core.presenceStep(s, { type: 'unlock' }, 10);
  assert.equal(JSON.stringify(s), frozen);
});

test('the gate: the same input always gives the same answer, and every answer is well-formed', () => {
  let seed = 8;
  const rnd = n => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  const REASONS = ['ok', 'off', 'kind', 'muted', 'away', 'ratelimit', 'card', 'typing', 'busy', 'recent', 'nudged', 'recapGiven'];
  for (let i = 0; i < 3000; i++) {
    const input = {
      on: [true, false, undefined, 'x'][rnd(4)], kind: [...core.DISMISS_KINDS, 'x', undefined][rnd(7)], dismissals: rnd(3) ? undefined : Object.fromEntries(core.DISMISS_KINDS.map(k => [k, rnd(4)])),
      away: rnd(2) === 0, ratelimit: rnd(2) === 0, card: [null, 'approval', 'question', 'other'][rnd(4)], ownCard: rnd(2) === 0, inputFocused: rnd(2) === 0,
      visible: rnd(3) ? null : { kind: core.DISMISS_KINDS[rnd(5)], seen: rnd(2) === 0 }, lastShownAt: rnd(2) ? null : 1000 - rnd(120000), now: 1000, nudged: rnd(2) === 0, recapGiven: rnd(2) === 0,
    };
    const a = core.shouldShow(input), b = core.shouldShow(JSON.parse(JSON.stringify(input)));
    assert.deepEqual(a, b);
    assert.ok(REASONS.includes(a.reason));
    assert.equal(a.show, a.reason === 'ok');
    if (a.replace) assert.ok(a.show && input.kind === 'recap');
    if (a.show) { assert.notEqual(input.on, false); assert.ok(!core.muted(input.dismissals, input.kind)); }
  }
});
