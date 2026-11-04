import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
const core = createRequire(import.meta.url)('../../shared/sidekick-core.js');
const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/sidekick/stuck-cases.json', import.meta.url), 'utf8'));

test('the fixture: every timeline gives the typed answers (the nudge, and the deadline and words where typed)', () => {
  for (const c of fx.cases) {
    let ledger = core.emptyLedger();
    for (const st of c.steps) {
      if (st.payload) { ledger = core.ledgerApply(ledger, core.eventFrom(st.payload, st.at)); continue; }
      const ctx = st.probe.ctx, r = core.stuckStep(ledger, st.at, ctx);
      assert.equal(r.nudge ? r.nudge.kind : null, st.expect, `${c.name} @${st.at}`);
      if (st.nextAt !== undefined) assert.equal(r.nextAt, st.nextAt, `${c.name} @${st.at} nextAt`);
      if (st.text !== undefined) assert.equal(r.nudge ? core.nudgeText(r.nudge, ledger, st.at, ctx) : null, st.text, `${c.name} @${st.at} words`);
      if (st.probe.mark && r.nudge) ledger = core.markNudged(ledger, r.nudge.key, st.at);
    }
  }
});

test('the thresholds are the spec\'s', () => {
  assert.deepEqual(core.STUCK, { LOOP_CALLS: 8, LOOP_SAME: 4, WINDOW_MS: 600000, ERRORS: 3, WAIT_MS: 60000, SILENT_MS: 300000, SILENT_PRE_MS: 900000, KITTEN_MS: 600000, GIVE_UP_MS: { mac: 115000, windows: 110000, linux: 110000 } });
  assert.deepEqual(core.NUDGE_KINDS, ['stuck.loop', 'stuck.errors', 'stuck.waiting', 'stuck.silent']);
});

test('the words are fixed templates with the agent\'s name and nothing else of the work', () => {
  const l = core.ledgerApply(core.emptyLedger(), core.eventFrom({ hook_event_name: 'PostToolUse', session_id: 'S', cwd: '/p/SECRET-DIR', nm_agent: 'gemini', tool_name: 'Bash', tool_input: { command: 'SECRET-CMD' } }, 1000));
  const s = l.sessions[0];
  for (const kind of core.NUDGE_KINDS) {
    const text = core.nudgeText({ kind, reasonId: kind.slice(6), key: s.key, agentId: s.agentId }, l, 1000 + 7 * 60000, {});
    assert.ok(text.startsWith('Gemini CLI '), text);
    assert.ok(!/SECRET/.test(text) && !/[\\/]/.test(text), text);
  }
  assert.equal(core.nudgeText(null, l, 0), '');
  assert.equal(core.nudgeText({ kind: 'nope' }, l, 0), '');
});

test('with nothing running there is nothing to wait for: no deadline, no nudge', () => {
  assert.deepEqual(core.stuckStep(core.emptyLedger(), 5, {}), { nudge: null, nextAt: null });
  for (const bad of [null, undefined, {}, { sessions: 'x' }, 5]) assert.deepEqual(core.stuckStep(bad, 5, {}), { nudge: null, nextAt: null });
  assert.deepEqual(core.stuckStep(core.emptyLedger(), NaN, {}), { nudge: null, nextAt: null });
  const done = ['Stop', 'SessionEnd'].reduce((l, n) => core.ledgerApply(l, core.eventFrom({ hook_event_name: n, session_id: 'S' }, 10)), core.ledgerApply(core.emptyLedger(), core.eventFrom({ hook_event_name: 'PostToolUse', session_id: 'S', tool_name: 'Bash', tool_input: {} }, 1)));
  assert.deepEqual(core.stuckStep(done, 10 ** 9, {}), { nudge: null, nextAt: null });
});

test('stuckStep and markNudged do not change the ledger they are given', () => {
  const l = core.ledgerApply(core.emptyLedger(), core.eventFrom({ hook_event_name: 'PostToolUse', session_id: 'S', tool_name: 'Bash', tool_input: {} }, 1000));
  const frozen = JSON.stringify(l);
  core.stuckStep(l, 10 ** 7, {});
  const l2 = core.markNudged(l, l.sessions[0].key, 5);
  assert.equal(JSON.stringify(l), frozen);
  assert.equal(l2.sessions[0].nudgedAt, 5);
  assert.equal(l.sessions[0].nudgedAt, null);
});

test('a fuzz: at most one nudge, always for a live session that has had none, and the deadline is in the future', () => {
  let seed = 99;
  const rnd = n => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  const names = ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'PermissionRequest', 'Stop', 'SubagentStart', 'SubagentStop', 'SessionEnd', 'Notification'];
  for (let round = 0; round < 40; round++) {
    let l = core.emptyLedger(), t = 1_000_000;
    for (let i = 0; i < 150; i++) {
      t += rnd(6) === 0 ? rnd(20) * 60000 : rnd(30) * 1000;
      const ev = core.eventFrom({ hook_event_name: names[rnd(names.length)], session_id: 'S' + rnd(3), tool_name: ['Bash', 'Edit'][rnd(2)], tool_input: { command: 'c' + rnd(2), file_path: '/p/f' + rnd(2) }, agent_id: 'a' + rnd(2), cwd: '/p' }, t);
      if (ev) l = core.ledgerApply(l, ev);
      const ctx = { away: rnd(8) === 0, ratelimit: rnd(8) === 0, cardShown: rnd(2) === 0 };
      const r = core.stuckStep(l, t, ctx);
      if (r.nudge) {
        const s = l.sessions.find(x => x.key === r.nudge.key);
        assert.ok(s && s.endedAt === null && s.nudgedAt === null && !ctx.away && !ctx.ratelimit);
        assert.ok(core.NUDGE_KINDS.includes(r.nudge.kind));
        assert.ok(core.nudgeText(r.nudge, l, t, ctx).length > 10);
        l = core.markNudged(l, r.nudge.key, t);
        const again = core.stuckStep(l, t, ctx);
        assert.equal(again.nudge === null || again.nudge.key !== r.nudge.key, true);
      }
      if (r.nextAt !== null) assert.ok(r.nextAt > t);
      if (ctx.away || ctx.ratelimit) assert.equal(r.nextAt, null);
    }
  }
});

// ctx.muted: a muted kind is skipped when the nudge is chosen and its deadline is left out of nextAt.
const NK = core.NUDGE_KINDS;
const stuckLedger = (...payloads) => payloads.reduce((l, [p, at]) => core.ledgerApply(l, core.eventFrom({ session_id: 'S', cwd: '/p', ...p }, at)), core.emptyLedger());
const bash = c => ({ hook_event_name: 'PostToolUse', tool_name: 'Bash', tool_input: { command: c } });
const loopLedger = () => stuckLedger(...[0, 1, 2, 3].map(i => [bash('npm test'), 1000 + i * 1000]));

test('muted: a muted loop lets the quiet rule fire for the same session, with the deadline kept', () => {
  const l = loopLedger();
  assert.equal(core.stuckStep(l, 5000, {}).nudge.kind, 'stuck.loop');
  assert.deepEqual(core.stuckStep(l, 5000, { muted: ['stuck.loop'] }), { nudge: null, nextAt: 4000 + 300000 });
  const r = core.stuckStep(l, 4000 + 300000, { muted: ['stuck.loop'] });
  assert.equal(r.nudge.kind, 'stuck.silent');
  assert.equal(r.nudge.key, l.sessions[0].key);
});

test('muted: a muted waiting or quiet deadline is left out of nextAt, an unmuted one is kept', () => {
  const l = stuckLedger([bash('ls'), 0], [{ hook_event_name: 'PermissionRequest', session_id: 'S2', tool_name: 'Bash', tool_input: { command: 'git push' } }, 10000]);
  assert.equal(core.stuckStep(l, 20000, {}).nextAt, 70000);
  assert.equal(core.stuckStep(l, 20000, { muted: ['stuck.waiting'] }).nextAt, 300000);
  assert.equal(core.stuckStep(l, 20000, { muted: ['stuck.silent'] }).nextAt, 70000);
  assert.equal(core.stuckStep(l, 20000, { muted: ['stuck.waiting', 'stuck.silent'] }).nextAt, null);
  assert.equal(core.stuckStep(l, 80000, { muted: ['stuck.waiting'] }).nudge, null);
  assert.equal(core.stuckStep(l, 80000, { muted: ['stuck.loop', 'stuck.errors', 'stuck.silent'] }).nudge.kind, 'stuck.waiting');
});

test('muted: every kind muted gives nothing and asks for no deadline', () => {
  const l = loopLedger();
  assert.deepEqual(core.stuckStep(l, 5000, { muted: [...NK] }), { nudge: null, nextAt: null });
});

test('muted: what is not a kind, a non-array and duplicates are ignored and never throw', () => {
  const l = loopLedger(), plain = core.stuckStep(l, 5000, {});
  for (const m of [undefined, null, [], 'stuck.loop', 7, true, { 'stuck.loop': true }, ['recap'], ['nope', 42, null, {}, ['stuck.loop']], ['recap', 'recap']]) {
    assert.deepEqual(core.stuckStep(l, 5000, { muted: m }), plain, JSON.stringify(m));
  }
  assert.deepEqual(core.stuckStep(l, 5000, { muted: ['stuck.loop', 'stuck.loop', 'nope', 'recap'] }), core.stuckStep(l, 5000, { muted: ['stuck.loop'] }));
  assert.doesNotThrow(() => core.stuckStep(l, 5000, { muted: ['x', () => 1, Symbol('s')] }));
});

test('muted: it does not change the ledger or the ctx it is given', () => {
  const l = loopLedger(), frozen = JSON.stringify(l), ctx = { muted: ['stuck.loop'] };
  core.stuckStep(l, 5000, ctx);
  assert.equal(JSON.stringify(l), frozen);
  assert.deepEqual(ctx, { muted: ['stuck.loop'] });
});
