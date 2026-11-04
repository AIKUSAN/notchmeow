import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
const core = createRequire(import.meta.url)('../../shared/sidekick-core.js');
const read = n => JSON.parse(fs.readFileSync(new URL(`../fixtures/sidekick/${n}`, import.meta.url), 'utf8'));
const recapFx = read('recap-cases.json'), statusFx = read('status-cases.json');

test('the fixtures: every recap, status and question gives what it records', () => {
  for (const c of recapFx.cases) assert.deepEqual(core.recapOf(c.snapshot), c.recap, c.name);
  for (const c of statusFx.cases) assert.deepEqual(core.statusOf(c.snapshot, c.agent), c.status, c.name);
  for (const m of statusFx.matcher) assert.deepEqual(core.matchStatusQuestion(m.text), { matched: m.matched, agentId: m.agentId }, JSON.stringify(m.text));
});

test('a recap is never "nothing happened", and never for a short absence', () => {
  assert.equal(core.RECAP.MIN_AWAY_MS, 120000);
  for (const c of recapFx.cases) if (c.recap) assert.ok(c.recap.lines.length >= 1 && c.recap.lines.every(l => l.length > 10 || /^\+\d+ more$/.test(l)) && !/nothing happened/i.test(c.recap.lines.join(' ')));
  const ledger = recapFx.cases.find(c => c.recap).snapshot.sessions;
  const now = Math.max(...ledger.map(s => s.lastEventAt)) + 10 * 60000;
  assert.equal(core.recapOf({ awaySince: now - 119999, now, sessions: ledger }), null);
  assert.ok(core.recapOf({ awaySince: now - 600000, now, sessions: ledger }));
});

test('there are at most three lines, then "+N more"', () => {
  for (const c of recapFx.cases) if (c.recap) {
    const n = c.recap.lines.length;
    assert.ok(n <= 4);
    if (n === 4) assert.match(c.recap.lines[3], /^\+\d+ more$/);
    assert.equal(c.recap.facts.length, n === 4 ? 3 + Number(c.recap.lines[3].match(/\d+/)[0]) : n);
  }
});

test('the facts are the line\'s numbers and names, and nothing else', () => {
  for (const c of recapFx.cases) if (c.recap) for (const f of c.recap.facts) {
    assert.deepEqual(Object.keys(f), ['agent', 'agentId', 'project', 'steps', 'stepsAtLeast', 'files', 'more', 'errors', 'approvals', 'end', 'quietMinutes']);
    assert.ok(f.files.length <= 3 && f.files.every(x => !/[\\/]/.test(x) && Array.from(x).length <= 60));
    assert.ok(['finished', 'waiting', 'error', 'question', 'working', 'quiet'].includes(f.end));
  }
});

test('no command, path, prompt or message reaches a recap or a status', () => {
  const ev = (p, at) => core.eventFrom({ session_id: 'S', cwd: '/Users/SECRET-DIR/proj', ...p }, at);
  let l = core.emptyLedger();
  for (const [p, at] of [[{ hook_event_name: 'UserPromptSubmit', prompt: 'SECRET-PROMPT' }, 1000], [{ hook_event_name: 'PostToolUse', tool_name: 'Bash', tool_input: { command: 'echo SECRET-CMD' } }, 2000], [{ hook_event_name: 'PostToolUse', tool_name: 'Edit', tool_input: { file_path: '/Users/SECRET-DIR/proj/a.js', new_string: 'SECRET-NEW' } }, 3000], [{ hook_event_name: 'Stop', last_assistant_message: 'SECRET-MSG' }, 4000]]) l = core.ledgerApply(l, ev(p, at));
  const text = JSON.stringify([core.recapOf({ awaySince: 0, now: 10 * 60000, sessions: l.sessions }), core.statusOf({ now: 10 * 60000, sessions: l.sessions })]);
  assert.ok(text.includes('a.js'));
  assert.ok(!/SECRET/.test(text), text);
});

test('hostile snapshots give nothing and never throw', () => {
  for (const bad of [null, undefined, 5, 'x', [], {}, { awaySince: 0 }, { awaySince: 'a', now: 1, sessions: [] }, { awaySince: 0, now: NaN, sessions: [] }, { awaySince: 0, now: 10 ** 9, sessions: 'x' }, { awaySince: 0, now: 10 ** 9, sessions: [] }]) assert.equal(core.recapOf(bad), null);
  for (const bad of [null, undefined, 5, {}, { now: 1 }, { now: 1, sessions: 'x' }, { now: NaN, sessions: [] }]) assert.deepEqual(core.statusOf(bad).lines, ['No agent is running right now.']);
  assert.deepEqual(core.statusOf(null, 'agent_codex').lines, ['Codex is not running right now.']);
  for (const bad of [null, undefined, 5, {}, [], false, 'x'.repeat(81)]) assert.deepEqual(core.matchStatusQuestion(bad), { matched: false, agentId: null });
});

test('recapOf and statusOf do not change the snapshot', () => {
  const c = recapFx.cases.find(x => x.recap);
  const frozen = JSON.stringify(c.snapshot);
  core.recapOf(c.snapshot); core.statusOf({ now: c.snapshot.now, sessions: c.snapshot.sessions });
  assert.equal(JSON.stringify(c.snapshot), frozen);
});

test('the status question is the whole message', () => {
  const yes = ["What's Claude doing?", 'status', 'what is codex doing right now'];
  const no = ["What's Claude doing to my files and why did it delete the build folder?", 'Please give me the status', "what's the status of claude", 'status report for the team', 'claude status update please'];
  for (const t of yes) assert.equal(core.matchStatusQuestion(t).matched, true, t);
  for (const t of no) assert.equal(core.matchStatusQuestion(t).matched, false, t);
});
