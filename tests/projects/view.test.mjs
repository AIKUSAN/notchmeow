import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const P = require('../../shared/projects-core.js');
const fx = name => JSON.parse(fs.readFileSync(new URL(`../fixtures/projects/${name}`, import.meta.url), 'utf8'));

const T = 1760000000000, MIN = 60000;
const brief = v => v.projects.map(p => ({ name: p.name, state: p.state, dim: p.dim, waiting: p.waiting,
  sessions: p.sessions.map(s => `${s.label}:${s.state}${s.dim ? ':dim' : ''}${s.waitingInApp ? ':app' : ''}${s.subagents.length ? ' +' + s.subagents.map(k => k.type).join(',') : ''}`) }));
test('registry-cases.json: every view, and its typed short form', () => {
  for (const c of fx('registry-cases.json').cases) {
    let reg = P.emptyRegistry(c.home);
    for (const s of c.steps) {
      if (s.payload) reg = P.registryApply(reg, P.projectEventFrom(s.payload, s.at, s.waitIn));
      else {
        const v = P.projectsView(reg, s.at, {}); assert.deepEqual(v, s.view, c.name); assert.deepEqual(brief(v), s.expect, c.name);
        if (s.notes) assert.deepEqual(v.projects.flatMap(p => p.sessions.filter(x => x.note !== '').map(x => `${x.label}:${x.note}`)), s.notes, c.name);
      }
    }
  }
});
test('waitLabel: the host as a name, or Claude App when no host is given', () => {
  assert.equal(P.waitLabel('Terminal'), 'Waiting in Terminal');
  assert.equal(P.waitLabel(''), 'Waiting in Claude App');
  assert.equal(P.waitLabel(), 'Waiting in Claude App');
  assert.equal(P.waitLabel('Claude App'), P.APP_WAIT_LABEL);
  assert.doesNotMatch(P.waitLabel('a/b'), /[\/\\]/);
  assert.doesNotMatch(P.waitLabel('c:\\x'), /[\/\\]/);
  assert.equal(P.waitLabel('a\u202Eb'), 'Waiting in ab');
  assert.equal(P.waitLabel('/'), 'Waiting in Claude App');
  assert.equal(P.waitLabel('   '), 'Waiting in Claude App');
  assert.equal(P.waitLabel(' '.repeat(80)), 'Waiting in Claude App');
});
test('a waitIn given as a path loses its separators', () => {
  const e = P.projectEventFrom({ hook_event_name: 'PermissionRequest', session_id: 's1', cwd: '/Users/sam/Code/notchmeow', tool_name: 'Bash' }, T, '/Users/sam/MARKER-WAIT/x');
  assert.equal(e.waitIn, 'UserssamMARKER-WAITx');
  assert.doesNotMatch(e.waitIn, /[\/\\]/);
});
test('registry-cases.json presentation: the host words and the step of the newest row', () => {
  for (const c of fx('registry-cases.json').presentation) {
    let reg = P.emptyRegistry(c.home);
    for (const s of c.payloads) reg = P.registryApply(reg, P.projectEventFrom(s.payload, s.at));
    const v = P.projectsView(reg, c.at, c.opts);
    assert.deepEqual(v, c.view, c.name);
    const p = v.projects[0] || {};
    const got = { projects: v.projects.length, step: p.step, host: p.host, rows: (p.sessions || []).map(s => `${s.label}:${s.host}`), state: p.state, waiting: p.waiting };
    assert.deepEqual(Object.fromEntries(Object.keys(c.expect).map(k => [k, got[k]])), c.expect, c.name);
  }
});
const o = fx('order-cases.json');
test('projectOrder replays order-cases.json', () => { for (const c of o.order) assert.deepEqual(P.projectOrder(c.projects).map(p => p.id), c.expect, c.name); });
test('bigCardOf replays order-cases.json', () => { for (const c of o.bigCard) assert.deepEqual(P.bigCardOf(c.projects, c.pinned, c.clicked), c.expect, c.name); });
test('waitingCount replays order-cases.json', () => { for (const c of o.waiting) assert.equal(P.waitingCount(c.projects), c.expect, c.name); });
test('cleanStep', () => {
  assert.equal(P.cleanStep('Editing /Users/sam/Code/notchmeow/a.swift'), 'Editing a.swift');
  assert.equal(P.cleanStep('Reading C:\\x\\b.ts now'), 'Reading b.ts now');
  assert.equal(P.cleanStep('  Run   tests  '), 'Run tests');
  assert.equal(P.cleanStep('a/'), 'a'); assert.equal(P.cleanStep('/'), '…');
  assert.equal(P.cleanStep('x'.repeat(100)), 'x'.repeat(79) + '…');
  assert.equal(P.cleanStep(null), ''); assert.equal(P.cleanStep('a\u202Eb'), 'a b');
});
test('project ids carry no path', () => {
  const reg = P.registryApply(P.emptyRegistry(), P.projectEventFrom({ hook_event_name: 'UserPromptSubmit', session_id: 's1', cwd: '/Users/sam/Code/notchmeow' }, T));
  assert.equal(P.projectsView(reg, T).projects[0].id, 'p-39f5156f');
});
test('nothing in the view carries a path, a prompt or a message', () => {
  const A = '/Users/sam/MARKER-GP/Code/notchmeow', B = '/Users/sam/MARKER-GP2/Work/notchmeow';
  const steps = [
    [A, { hook_event_name: 'UserPromptSubmit', prompt: 'MARKER-PROMPT', transcript_path: '/Users/sam/MARKER-TRANSCRIPT.jsonl' }],
    [A + '/.claude/worktrees/wt1', { hook_event_name: 'PermissionRequest', tool_name: 'Bash', tool_input: { command: 'rm /Users/sam/MARKER-CMD' }, session_id: 's2' }],
    [A, { hook_event_name: 'Notification', message: 'Open /Users/sam/MARKER-MSG?' }],
    [A, { hook_event_name: 'SubagentStart', agent_id: 'k1', agent_type: 'MARKER-TYPE/../x' }],
    [B, { hook_event_name: 'UserPromptSubmit', session_id: 's3' }],
    ['/Users/sam/Code/notch\u202Emeow-x', { hook_event_name: 'UserPromptSubmit', session_id: 's4' }],
  ];
  let reg = P.emptyRegistry();
  steps.forEach(([cwd, x], i) => { reg = P.registryApply(reg, P.projectEventFrom({ session_id: 's1', cwd, ...x }, T + i)); });
  const v = P.projectsView(reg, T + 10, { steps: { s1: 'Editing /Users/sam/MARKER-GP/Code/notchmeow/a.swift', s2: 'C:\\Users\\sam\\MARKER-GP\\b.ts' } });
  const json = JSON.stringify(v);
  for (const m of ['MARKER-PROMPT', 'MARKER-TRANSCRIPT', 'MARKER-CMD', 'MARKER-MSG', 'MARKER-GP', 'Users', '\u202E']) assert.ok(!json.includes(m), m);
  const walk = (x, key) => {
    if (typeof x === 'string') { if (key !== 'id') assert.doesNotMatch(x, /[\/\\]/, `${key}: ${x}`); }
    else if (Array.isArray(x)) x.forEach(y => walk(y, key));
    else if (x && typeof x === 'object') for (const [k, y] of Object.entries(x)) walk(y, k);
  };
  walk(v, '');
  assert.deepEqual(v.projects.map(p => p.name).sort(), ['notchmeow — Code', 'notchmeow — Work', 'notchmeow-x']);
});
test('the home folder never reaches the view', () => {
  const H = '/Users/MARKER-HOME';
  let reg = P.emptyRegistry(H);
  [[H, 'h1'], [H + '/Code/notchmeow', 's1'], [H + '/x/Home', 's2'], [H + '/.claude/worktrees/w1', 's3']]
    .forEach(([cwd, sid], i) => { reg = P.registryApply(reg, P.projectEventFrom({ hook_event_name: 'UserPromptSubmit', session_id: sid, cwd }, T + i)); });
  const v = P.projectsView(reg, T + 10, { steps: { h1: 'Editing ' + H + '/notes.md' } });
  assert.ok(!JSON.stringify(v).includes('MARKER-HOME'));
  assert.deepEqual(v.projects.map(p => p.name).sort(), ['Home', 'Home — x', 'notchmeow']);
  assert.deepEqual(v.projects.find(p => p.name === 'Home').sessions.map(s => s.label), ['main', 'w1']);
});
test("a subagent's state follows its live card", () => {
  let reg = P.emptyRegistry('/Users/sam');
  const feed = (dt, x) => { reg = P.registryApply(reg, P.projectEventFrom({ session_id: 's1', cwd: '/Users/sam/Code/notchmeow', ...x }, T + dt)); };
  feed(0, { hook_event_name: 'UserPromptSubmit' });
  feed(100, { hook_event_name: 'SubagentStart', agent_id: 'k1', agent_type: 'Explore' });
  feed(1000, { hook_event_name: 'PermissionRequest', tool_name: 'Bash', agent_id: 'k1' });
  const kitten = dt => P.projectsView(reg, T + dt).projects[0].sessions[0].subagents[0].state;
  assert.equal(kitten(1000 + 119000), 'approval'); assert.equal(kitten(1000 + 121000), 'working');
});
test('a fuzz of 3000 events never throws, keeps the caps and never shows a path', () => {
  let s = 12345; const rnd = n => ((s = (Math.imul(s, 1103515245) + 12345) >>> 0) % n);
  const hooks = ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PermissionRequest', 'Notification', 'Stop', 'StopFailure', 'SubagentStart', 'SubagentStop', 'SessionEnd', 'Bogus'];
  const cwds = ['/Users/sam/Code/a', '/Users/sam/Code/a/sub', '/Users/sam/Code/a/.claude/worktrees/w', '/Users/sam/Code/b', 'C:\\Users\\sam\\c', '', '/', '/Users/sam'];
  let reg = P.emptyRegistry('/Users/sam');
  for (let i = 0; i < 3000; i++) {
    const payload = { hook_event_name: hooks[rnd(hooks.length)], session_id: 's' + rnd(80), cwd: cwds[rnd(cwds.length)], agent_id: rnd(3) ? undefined : 'k' + rnd(12), agent_type: 't/' + rnd(4), tool_name: rnd(5) ? 'Bash' : 'AskUserQuestion', nm_agent: rnd(20) ? undefined : 'claude-desktop', message: rnd(2) ? 'ok?' : 'ok' };
    reg = P.registryApply(reg, P.projectEventFrom(payload, T + i * 1000));
    assert.ok(reg.sessions.length <= 64); assert.ok(reg.sessions.every(x => x.subagents.length <= 8));
  }
  const v = P.projectsView(reg, T + 3000 * 1000);
  assert.ok(!v.projects.some(p => p.name === 'sam'));
  for (const p of v.projects) { assert.doesNotMatch(p.name, /[\/\\]/); for (const x of p.sessions) { assert.doesNotMatch(x.label, /[\/\\]/); x.subagents.forEach(k => assert.doesNotMatch(k.type, /[\/\\]/)); } }
  assert.equal(v.waiting, P.waitingCount(v.projects));
});
test('step-cases.json replays cleanStep and the views (own steps keys only)', () => {
  const sc = fx('step-cases.json');
  for (const c of sc.steps) assert.equal(P.cleanStep(c.text), c.expect, c.name);
  for (const c of sc.views) {
    let reg = P.emptyRegistry(c.home);
    for (const x of c.payloads) reg = P.registryApply(reg, P.projectEventFrom(x.payload, x.at));
    const v = P.projectsView(reg, c.at, c.opts);
    assert.deepEqual(v, c.view, c.name);
    assert.deepEqual({ step: v.projects[0].step, rows: v.projects[0].sessions.map(s => `${s.label}:${s.step}`) }, c.expect, c.name);
  }
});
test('a root that is not normalized still names its project, and never throws', () => {
  const sess = (id, seq, root) => ({ id, cwd: root, root, worktree: '', seq, startedAt: T, lastAt: T, run: 'working', finishedAt: null, pending: [], fromApp: false, termProgram: '', bundleId: '', subagents: [] });
  const reg = { version: 1, home: '', sessions: [sess('s1', 1, '/a/'), sess('s2', 2, 'c:\\x')], otherAgentSeen: false, nextSeq: 3 };
  const v = P.projectsView(reg, T);
  assert.deepEqual(v.projects.map(p => p.name).sort(), ['a', 'x']);
  assert.equal(v.sessionCount, 2);
});
test('a subagent type in the registry is cleaned in the view as at the event (slashes to -, 64 code points)', () => {
  const reg = P.registryApply(P.emptyRegistry(), P.projectEventFrom({ hook_event_name: 'UserPromptSubmit', session_id: 's1', cwd: '/Users/sam/Code/notchmeow' }, T));
  reg.sessions[0].subagents.push({ id: 'k1', type: 'plugin/x\\y', state: 'working', born: T, last: T });
  reg.sessions[0].subagents.push({ id: 'k2', type: 'z'.repeat(70), state: 'working', born: T + 1, last: T + 1 });
  const v = P.projectsView(reg, T + 1);
  assert.deepEqual(v.projects[0].sessions[0].subagents.map(k => k.type).sort(), ['plugin-x-y', 'z'.repeat(64)]);
});
test('project ids replay project-cases.json (the id is p- and the FNV-1a of the root, over UTF-8)', () => {
  for (const c of fx('project-cases.json').ids) {
    const reg = P.registryApply(P.emptyRegistry(), P.projectEventFrom({ hook_event_name: 'UserPromptSubmit', session_id: 's1', cwd: c.root }, T));
    assert.equal(P.projectsView(reg, T).projects[0].id, c.expect, c.name);
  }
});
