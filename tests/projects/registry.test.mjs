import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const P = require('../../shared/projects-core.js');
const fx = name => JSON.parse(fs.readFileSync(new URL(`../fixtures/projects/${name}`, import.meta.url), 'utf8'));

const T = 1760000000000, MIN = 60000, R = '/Users/sam/Code/notchmeow';
const f = fx('state-cases.json');
test('sessionStateAt replays state-cases.json', () => { for (const c of f.sessions) assert.deepEqual(P.sessionStateAt(c.session, c.now), c.expect, c.name); });
test('projectStateOf replays state-cases.json', () => { for (const c of f.projects) assert.deepEqual(P.projectStateOf(c.states), c.expect, c.name); });
const feed = (reg, at, payload) => P.registryApply(reg, P.projectEventFrom(payload, at));
const p = (hook, sid, cwd, x = {}) => ({ hook_event_name: hook, session_id: sid, cwd, ...x });
test('emptyRegistry, and the home folder it carries', () => {
  assert.deepEqual(P.emptyRegistry(), { version: 1, home: '', sessions: [], otherAgentSeen: false, nextSeq: 1 });
  assert.equal(P.emptyRegistry('/Users/sam/').home, '/Users/sam'); assert.equal(P.emptyRegistry(3).home, '');
  assert.equal(P.registryApply(P.emptyRegistry('/Users/sam'), null).home, '/Users/sam');
  assert.equal(P.registryPrune(P.emptyRegistry('/Users/sam'), T).home, '/Users/sam');
});
test('a new session has the documented shape', () => {
  const r = feed(P.emptyRegistry(), T, p('UserPromptSubmit', 's1', R + '/', { term_program: 'iTerm.app', bundle_id: 'com.googlecode.iterm2' }));
  assert.deepEqual(r.sessions, [{ id: 's1', cwd: R, root: R, worktree: '', seq: 1, startedAt: T, lastAt: T, run: 'working', finishedAt: null, pending: [], fromApp: false, termProgram: 'iTerm.app', bundleId: 'com.googlecode.iterm2', subagents: [] }]);
  assert.equal(r.nextSeq, 2);
});
test('another agent makes no session and is remembered', () => {
  const r = feed(P.emptyRegistry(), T, p('UserPromptSubmit', 'x', R, { nm_agent: 'codex' }));
  assert.equal(r.sessions.length, 0); assert.equal(r.otherAgentSeen, true);
});
test('a new session needs a cwd; SessionEnd for an unknown session does nothing', () => {
  let r = feed(P.emptyRegistry(), T, p('UserPromptSubmit', 's1', ''));
  r = feed(r, T, p('SessionEnd', 's2', R));
  assert.deepEqual(r, P.emptyRegistry());
});
test('a null or bad event returns the registry as it was', () => {
  const r = feed(P.emptyRegistry(), T, p('UserPromptSubmit', 's1', R));
  assert.deepEqual(P.registryApply(r, null), r); assert.deepEqual(P.registryApply(r, { at: 'x' }), r);
  assert.deepEqual(P.registryApply('junk', null), P.emptyRegistry());
});
test('events out of order never move lastAt back', () => {
  let r = feed(P.emptyRegistry(), T + 5000, p('UserPromptSubmit', 's1', R));
  r = feed(r, T, p('PostToolUse', 's1', R, { tool_name: 'Read' }));
  assert.equal(r.sessions[0].lastAt, T + 5000);
});
test('the pending list: per asker, replaced, cleared by its own asker', () => {
  let r = feed(P.emptyRegistry(), T, p('PermissionRequest', 's1', R, { tool_name: 'Bash' }));
  r = feed(r, T + 1, p('PermissionRequest', 's1', R, { tool_name: 'Bash' }));
  r = feed(r, T + 2, p('PermissionRequest', 's1', R, { tool_name: 'Bash', agent_id: 'k1' }));
  assert.deepEqual(r.sessions[0].pending, [{ by: '', kind: 'approval', at: T + 1, inApp: false, waitIn: '' }, { by: 'k1', kind: 'approval', at: T + 2, inApp: false, waitIn: '' }]);
  r = feed(r, T + 3, p('PostToolUse', 's1', R, { tool_name: 'Bash', agent_id: 'k1' }));
  assert.deepEqual(r.sessions[0].pending.map(x => x.by), ['']);
  r = feed(r, T + 4, p('UserPromptSubmit', 's1', R));
  assert.deepEqual(r.sessions[0].pending, []);
});
test('registryPrune drops sessions 2 h quiet', () => {
  const r = feed(P.emptyRegistry(), T, p('UserPromptSubmit', 's1', R));
  assert.equal(P.registryPrune(r, T + 120 * MIN - 1).sessions.length, 1);
  assert.equal(P.registryPrune(r, T + 120 * MIN).sessions.length, 0);
});
test('caps and hostile ids', () => {
  let r = P.emptyRegistry();
  for (let i = 0; i < 100; i++) r = feed(r, T + i, p('UserPromptSubmit', 's' + i, R + '/x' + i));
  assert.equal(r.sessions.length, 64);
  assert.ok(!r.sessions.some(s => s.id === 's0') && r.sessions.some(s => s.id === 's99'));   // the least recently active went
  for (let i = 0; i < 20; i++) r = feed(r, T + 200 + i, p('SubagentStart', 's99', R, { agent_id: 'k' + i, agent_type: 't' }));
  assert.equal(r.sessions.find(s => s.id === 's99').subagents.length, 8);
  r = feed(r, T + 300, p('UserPromptSubmit', '__proto__', R));
  r = feed(r, T + 301, p('SubagentStart', '__proto__', R, { agent_id: '__proto__', agent_type: 'constructor' }));
  assert.equal(({}).polluted, undefined); assert.equal(Object.getPrototypeOf({}), Object.prototype);
  assert.ok(r.sessions.some(s => s.id === '__proto__'));
});
test('never mutates its input', () => {
  const deepFreeze = o => { Object.values(o).forEach(v => v && typeof v === 'object' && deepFreeze(v)); return Object.freeze(o); };
  let r = feed(P.emptyRegistry(), T, p('UserPromptSubmit', 's1', R));
  r = feed(r, T, p('SubagentStart', 's1', R, { agent_id: 'k1', agent_type: 'Explore' }));
  const frozen = deepFreeze(JSON.parse(JSON.stringify(r)));
  for (const h of ['PreToolUse', 'PermissionRequest', 'Stop', 'StopFailure', 'SubagentStop', 'SessionEnd']) P.registryApply(frozen, P.projectEventFrom(p(h, 's1', R, { agent_id: 'k1' }), T + 1));
  P.registryPrune(frozen, T + 999 * MIN);
});
test('the registry keeps no prompt, transcript, command or message', () => {
  let r = P.emptyRegistry();
  r = feed(r, T, p('UserPromptSubmit', 's1', R, { prompt: 'MARKER-PROMPT', transcript_path: '/x/MARKER-TRANSCRIPT' }));
  r = feed(r, T, p('PermissionRequest', 's1', R, { tool_name: 'Bash', tool_input: { command: 'MARKER-CMD' } }));
  r = feed(r, T, p('Notification', 's1', R, { message: 'MARKER-MSG?' }));
  const s = JSON.stringify(r);
  for (const m of ['MARKER-PROMPT', 'MARKER-TRANSCRIPT', 'MARKER-CMD', 'MARKER-MSG']) assert.ok(!s.includes(m), m);
});
test('agoOf replays state-cases.json (the whole minutes since the last event, never below 0)', () => {
  for (const c of f.agoCases) assert.equal(P.agoOf(c.now, c.lastAt), c.expect, c.name);
});
test('caps and the clock\'s edges replay registry-cases.json (the registry itself)', () => {
  for (const c of fx('registry-cases.json').caps) {
    let reg = P.emptyRegistry(c.home);
    for (const e of c.events) reg = P.registryApply(reg, P.projectEventFrom(e.payload, e.at));
    const got = { sessions: reg.sessions.map(s => `${s.id}#${s.seq}`), nextSeq: reg.nextSeq,
      subagents: Object.fromEntries(reg.sessions.filter(s => s.subagents.length).map(s => [s.id, s.subagents.map(k => k.id)])),
      lastAt: Object.fromEntries(reg.sessions.map(s => [s.id, s.lastAt])) };
    assert.deepEqual(Object.fromEntries(Object.keys(c.expect).map(k => [k, got[k]])), c.expect, c.name);
  }
});
test('a session that cannot be copied is dropped alone: one BigInt among three leaves two', () => {
  let r = P.emptyRegistry();
  for (const id of ['s1', 's2', 's3']) r = feed(r, T, p('UserPromptSubmit', id, R));
  r.sessions[1].big = 10n;
  const cyc = {}; cyc.self = cyc; r.sessions[2].cycle = cyc;
  const after = P.registryApply(r, P.projectEventFrom(p('PostToolUse', 's1', R, { tool_name: 'Read' }), T + 1));
  assert.deepEqual(after.sessions.map(s => s.id), ['s1']);
  assert.deepEqual(P.registryPrune(r, T).sessions.map(s => s.id), ['s1']);
  assert.equal(P.projectsView(r, T).sessionCount, 1);
});
test('a non-finite event time reads as the newest activity: nothing is pruned or aged, the ask is kept', () => {
  const r = feed(P.emptyRegistry(), T, p('UserPromptSubmit', 's1', R));
  const ev = { ...P.projectEventFrom(p('PermissionRequest', 's1', R, { tool_name: 'Bash' }), T), at: NaN };
  const out = P.registryApply(r, ev);
  assert.equal(out.sessions.length, 1);
  assert.equal(out.sessions[0].lastAt, T);
  assert.deepEqual(out.sessions[0].pending.map(x => [x.kind, x.at]), [['approval', T]]);
});
