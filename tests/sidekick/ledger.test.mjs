import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
const core = createRequire(import.meta.url)('../../shared/sidekick-core.js');
const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/sidekick/hook-cases.json', import.meta.url), 'utf8'));

const T0 = 9_000_000;
const hook = (name, extra = {}) => ({ hook_event_name: name, session_id: 'S1', cwd: '/Users/me/proj', ...extra });
const run = (steps, ledger = core.emptyLedger()) => steps.reduce((l, [at, payload]) => core.ledgerApply(l, core.eventFrom(payload, T0 + at * 1000)), ledger);

test('the fixture: every payload gives the event it records, every sequence the ledger it records', () => {
  for (const c of fx.cases) assert.deepEqual(core.eventFrom(c.payload, c.now, c.opts), c.event, c.name);
  for (const s of fx.sequences) {
    let l = core.emptyLedger();
    for (const st of s.steps) l = core.ledgerApply(l, st.answered ? core.approvalAnsweredEvent(st.answered.agentId, st.answered.sessionId, st.at) : core.eventFrom(st.payload, st.at, st.opts));
    assert.deepEqual(l, s.ledger, s.name);
  }
});

test('the four agents are all there, and the payloads from the docs are marked as such', () => {
  const agents = new Set(fx.cases.map(c => c.event && c.event.agentId));
  for (const a of ['integration_claude', 'agent_codex', 'agent_gemini', 'agent_antigravity', 'agent_cursor']) assert.ok(agents.has(a), a);
  assert.ok(fx.cases.every(c => c.source === 'repo' || c.source === 'docs'));
  for (const name of ['PostToolUseFailure', 'StopFailure', 'Notification', 'SubagentStop']) assert.ok(fx.cases.some(c => c.payload && c.payload.hook_event_name === name), `${name} has a fixture`);
  assert.ok(fx.cases.some(c => c.payload && /^C:\\/.test(c.payload.cwd || '')), 'a Windows-shaped payload');
});

test('the command key: FNV-1a over canonical JSON, pinned', () => {
  assert.equal(core.fnv1a(''), '811c9dc5');
  assert.equal(core.fnv1a('a'), 'e40c292c');
  assert.equal(core.commandKey('Bash', { command: 'ls -la' }), 'Bash#d3abe9d5');
  assert.equal(core.commandKey('Bash', { command: '  ls   -la ' }), 'Bash#d3abe9d5');
  assert.equal(core.commandKey('X', null), 'X#77074ba4');
  assert.equal(core.commandKey('X', { x: [1, 'é', null, true], file_path: '/a' }), 'X#63e27ca3');
  assert.equal(core.commandKey('X', { a: 1, b: 2 }), core.commandKey('X', { b: 2, a: 1 }), 'key order does not matter');
  assert.notEqual(core.commandKey('Bash', { command: 'ls' }), core.commandKey('Read', { command: 'ls' }), 'the tool is part of the key');
});

test('nothing secret reaches an event or the ledger', () => {
  const secrets = ['SECRET-PROMPT', 'SECRET-OUTPUT', 'SECRET-MSG', 'SECRET-CONTENT', 'SECRET-DIR', 'SECRET-CMD', 'SECRET-TRANSCRIPT'];
  const l = run([
    [0, hook('UserPromptSubmit', { prompt: secrets[0], transcript_path: `/Users/me/.claude/${secrets[6]}.jsonl`, cwd: `/Users/${secrets[4]}/proj` })],
    [1, hook('PostToolUse', { tool_name: 'Bash', tool_input: { command: `echo ${secrets[5]}` }, tool_response: { stdout: secrets[1] }, cwd: `/Users/${secrets[4]}/proj` })],
    [2, hook('PostToolUse', { tool_name: 'Write', tool_input: { file_path: `/Users/${secrets[4]}/proj/a.js`, content: secrets[3] }, cwd: `/Users/${secrets[4]}/proj` })],
    [3, hook('PermissionRequest', { tool_name: 'Bash', tool_input: { command: `curl https://${secrets[5]}` }, cwd: `/Users/${secrets[4]}/proj` })],
    [4, hook('Stop', { last_assistant_message: secrets[2], cwd: `/Users/${secrets[4]}/proj` })],
  ]);
  const text = JSON.stringify(l);
  for (const s of secrets) assert.ok(!text.includes(s), `${s} is in the ledger`);
  assert.equal(l.sessions[0].project, 'proj');
  assert.deepEqual(Object.keys(l.sessions[0]).sort(), ['agentId', 'endedAt', 'key', 'last', 'lastEventAt', 'nudgedAt', 'pendingApprovalAt', 'pendingKey', 'project', 'ring', 'sessionId', 'startedAt', 'state', 'subagents']);
  assert.deepEqual(Object.keys(l.sessions[0].ring[0]), ['at', 'kind', 'tool', 'target', 'file', 'key', 'ok']);
});

test('ledgerApply does not change the ledger it is given, and a bad event changes nothing', () => {
  const l1 = run([[0, hook('PreToolUse', { tool_name: 'Bash', tool_input: { command: 'ls' } })]]);
  const frozen = JSON.stringify(l1);
  const l2 = core.ledgerApply(l1, core.eventFrom(hook('PostToolUse', { tool_name: 'Bash', tool_input: { command: 'ls' } }), T0 + 5000));
  assert.equal(JSON.stringify(l1), frozen);
  assert.notEqual(JSON.stringify(l2), frozen);
  for (const bad of [null, undefined, 5, 'x', {}, { agentId: 'a' }, { agentId: 'a', sessionId: 's', kind: 'tool', at: NaN }, { agentId: 'a', sessionId: 's', kind: 'tool', at: 'now' }]) assert.deepEqual(core.ledgerApply(l1, bad), l1);
  assert.deepEqual(core.ledgerApply(null, null), { sessions: [] });
  assert.deepEqual(core.ledgerApply({ sessions: 'x' }, null), { sessions: [] });
});

test('hostile ids and names: an Object.prototype key is just text', () => {
  const l = run([
    [0, hook('SubagentStart', { session_id: '__proto__', agent_id: '__proto__' })],
    [1, hook('SubagentStart', { session_id: 'constructor', agent_id: 'constructor' })],
    [2, hook('PostToolUse', { session_id: 'toString', tool_name: '__proto__', tool_input: JSON.parse('{"__proto__":{"x":1},"command":"ls"}') })],
  ]);
  assert.equal(l.sessions.length, 3);
  assert.deepEqual(Object.keys(l.sessions[0].subagents), []);
  assert.deepEqual(Object.keys(l.sessions[1].subagents), ['constructor']);
  assert.equal({}.x, undefined);
});

test('the agent names', () => {
  assert.deepEqual(['integration_claude', 'agent_cursor', 'agent_codex', 'agent_gemini', 'agent_antigravity', 'agent_my-tool', 'agent_', 'x', null, '__proto__', 'constructor'].map(core.agentName),
    ['Claude Code', 'Cursor', 'Codex', 'Gemini CLI', 'Antigravity', 'My-tool', 'An agent', 'An agent', 'An agent', 'An agent', 'An agent']);
});

test('a fuzz of 4000 events keeps the invariants: at most 8 sessions, 40 ring entries, keys once, and every ring sorted by time', () => {
  let seed = 7;
  const rnd = n => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  const names = ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'PermissionRequest', 'Stop', 'StopFailure', 'SubagentStart', 'SubagentStop', 'SessionEnd', 'Notification', 'Interrupt', 'Nope'];
  let l = core.emptyLedger(), t = T0;
  for (let i = 0; i < 4000; i++) {
    t += rnd(5) === 0 ? rnd(40) * 60000 : rnd(20) * 1000;
    const p = { hook_event_name: names[rnd(names.length)], session_id: 'S' + rnd(14), cwd: '/p/' + rnd(3), tool_name: ['Bash', 'Edit', 'Grep'][rnd(3)], tool_input: { command: 'c' + rnd(4), file_path: '/p/f' + rnd(4) }, agent_id: 'a' + rnd(3), nm_agent: ['', '', 'gemini'][rnd(3)] };
    const ev = core.eventFrom(p, t);
    if (!ev) continue;
    l = core.ledgerApply(l, rnd(9) === 0 ? core.approvalAnsweredEvent(ev.agentId, ev.sessionId, t) : ev);
    assert.ok(l.sessions.length <= 8);
    assert.equal(new Set(l.sessions.map(s => s.key)).size, l.sessions.length);
    for (const s of l.sessions) {
      assert.ok(s.ring.length <= 40);
      assert.ok(s.ring.every((r, j) => j === 0 || s.ring[j - 1].at <= r.at));
      assert.ok(Object.keys(s.subagents).length <= 20);
      assert.ok(s.startedAt <= s.lastEventAt);
      assert.ok(s.pendingApprovalAt === null || s.state === 'approval' || s.pendingKey !== null);
    }
  }
});

test('liveSessions and aliveSubagents', () => {
  const l = run([[0, hook('SubagentStart', { agent_id: 'a1' })], [1, hook('SessionEnd', { session_id: 'S2' })], [2, hook('PreToolUse', { session_id: 'S2', tool_name: 'Bash', tool_input: { command: 'ls' } })], [3, hook('SessionEnd', { session_id: 'S2' })]]);
  assert.deepEqual(core.liveSessions(l).map(s => s.sessionId), ['S1']);
  assert.equal(core.aliveSubagents(l.sessions[0]), 1);
  assert.equal(core.aliveSubagents(null), 0);
  assert.deepEqual(core.liveSessions(null), []);
});

test('a 20,000-deep tool input does not throw: the key is the tool and a fixed marker', () => {
  let deep = { leaf: 1 };
  for (let i = 0; i < 20000; i++) deep = { x: deep };
  const ev = core.eventFrom({ hook_event_name: 'PreToolUse', session_id: 'S1', cwd: '/Users/me/proj', tool_name: 'Grep', tool_input: deep }, T0);
  assert.equal(ev.kind, 'preTool');
  assert.equal(ev.key, 'Grep#too-deep');
});

test('an id, a tool name or a subagent id is kept to 128 code points, so a huge one cannot grow the ledger', () => {
  const huge = 'x'.repeat(1_000_000), emoji = '\u{1F600}'.repeat(200);
  const ev = core.eventFrom({ hook_event_name: 'PreToolUse', session_id: huge, cwd: '/Users/me/proj', tool_name: huge, tool_input: { command: 'ls' } }, T0);
  assert.equal(Array.from(ev.sessionId).length, 128);
  assert.equal(Array.from(ev.tool).length, 128);
  assert.equal(ev.tool, 'x'.repeat(128));
  assert.equal(Array.from(core.eventFrom({ hook_event_name: 'PreToolUse', session_id: emoji, cwd: '/x', tool_name: 'Bash', tool_input: {} }, T0).sessionId).length, 128, 'code points, not UTF-16 units');
  const sub = core.eventFrom({ hook_event_name: 'SubagentStart', session_id: 'S1', cwd: '/x', agent_id: huge }, T0);
  assert.equal(Array.from(sub.subagentId).length, 128);
  assert.equal(core.eventFrom({ hook_event_name: 'Stop', session_id: 'S1', cwd: '/x' }, T0).tool, '', 'a short name is unchanged');
});

test('a malformed ledger or snapshot never throws: an entry that is not an object is dropped, a ring that is not a list is empty', () => {
  const bad = [{ sessions: [null] }, { sessions: [null, 5, [], 'S'] }, { sessions: [{ key: 'k', ring: null }] }, { sessions: [{ key: 'k', endedAt: null, ring: 'x' }] }];
  for (const l of bad) {
    assert.doesNotThrow(() => core.ledgerPrune(l, T0));
    assert.doesNotThrow(() => core.liveSessions(l));
    assert.doesNotThrow(() => core.stuckStep(l, T0, {}));
    assert.doesNotThrow(() => core.statusOf({ now: T0, sessions: l.sessions }, null));
    assert.doesNotThrow(() => core.recapOf({ awaySince: 0, now: 10 * T0, sessions: l.sessions }));
    assert.doesNotThrow(() => core.ledgerApply(l, core.eventFrom(hook('PostToolUse', { tool_name: 'Bash', tool_input: { command: 'ls' } }), T0 + 1000)));
  }
  assert.deepEqual(core.ledgerPrune({ sessions: [null] }, T0), { sessions: [] });
  assert.deepEqual(core.liveSessions({ sessions: [null] }), []);
  assert.deepEqual(core.stuckStep({ sessions: [null] }, T0, {}), { nudge: null, nextAt: null });
  assert.equal(core.statusOf({ now: T0, sessions: [null] }, null).lines[0], 'No agent is running right now.');
  assert.equal(core.recapOf({ awaySince: 0, now: 10 * T0, sessions: [null] }), null);
});

test('a session with a ring that is not a list gets a list when it is next written to', () => {
  const session = { key: 'integration_claude|S1', agentId: 'integration_claude', sessionId: 'S1', startedAt: T0, lastEventAt: T0, endedAt: null, state: 'working', last: 'tool', project: 'proj', ring: null, pendingApprovalAt: null, pendingKey: null, subagents: {}, nudgedAt: null };
  const out = core.ledgerApply({ sessions: [session] }, core.eventFrom(hook('PostToolUse', { tool_name: 'Bash', tool_input: { command: 'ls' } }), T0 + 1000));
  assert.equal(out.sessions.length, 1);
  assert.equal(out.sessions[0].ring.length, 1);
});
