#!/usr/bin/env node
// Writes tests/fixtures/projects/*.json from shared/projects-core.js, the single source of truth (docs/PROJECTS-CONTRACT.md).
//   node scripts/gen-projects-fixtures.mjs             write the fixtures
//   node scripts/gen-projects-fixtures.mjs --check     regenerate in memory and fail on any drift
//   node scripts/gen-projects-fixtures.mjs --out DIR   write somewhere else (the runner uses it twice, to prove determinism)
// Every case lists its input and, typed by hand next to it, the answer it must get: the generator stops if the core disagrees, so the fixtures are
// never just a copy of what the core says. No npm dependencies. Fixtures hold whole numbers, text, booleans and null only.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
const core = require('../shared/projects-core.js');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const FIXTURES = path.join(ROOT, 'tests/fixtures/projects');

const isObj = x => x !== null && typeof x === 'object' && !Array.isArray(x);

/** Compact, diff-friendly JSON: an array of objects gets one element per line, a map of objects one entry per line. */
export function format(obj) {
  const keys = Object.keys(obj), lines = [];
  keys.forEach((k, i) => {
    const v = obj[k], comma = i < keys.length - 1 ? ',' : '', head = `  ${JSON.stringify(k)}: `;
    if (Array.isArray(v) && v.length && v.every(isObj)) {
      lines.push(`${head}[`);
      v.forEach((x, j) => lines.push(`    ${JSON.stringify(x)}${j < v.length - 1 ? ',' : ''}`));
      lines.push(`  ]${comma}`);
    } else lines.push(`${head}${JSON.stringify(v)}${comma}`);
  });
  return `{\n${lines.join('\n')}\n}\n`;
}

/** Stops the generator when the core's answer is not the one typed next to the case. */
function expectEqual(what, got, want) {
  if (JSON.stringify(got) !== JSON.stringify(want)) throw new Error(`${what}: the core says ${JSON.stringify(got)}, the case says ${JSON.stringify(want)}`);
}

/** file name -> a function that builds the file's object. */
export const SECTIONS = {};

const T = 1760000000000, MIN = 60000; const R = '/Users/sam/Code/notchmeow', WT = R + '/.claude/worktrees/p0-plan', SUB = R + '/windows/src', G = '/Users/sam/Code/gracegrip', SITE = '/Users/sam/Code/site', HOME = '/Users/sam';

// ── project-cases.json: project of a session, names, roles, order inside a project ──
SECTIONS['project-cases.json'] = () => {
  const projectOf = [], names = [], roles = [], order = [];
  const po = (name, cwd, roots, expect, home = HOME) => { expectEqual(name, core.projectOf(cwd, roots, home), expect); projectOf.push({ name, cwd, roots, home, expect }); };
  po('a repository root is its own project', R, [], { root: R, worktree: '' });
  po('a worktree belongs to the repository before /.claude/worktrees/', WT, [], { root: R, worktree: 'p0-plan' });
  po('a folder inside a worktree is still that worktree', WT + '/windows', [], { root: R, worktree: 'p0-plan' });
  po('a subfolder joins a known project', SUB, [R], { root: R, worktree: '' });
  po('a subfolder with no known project is its own project', SUB, [], { root: SUB, worktree: '' });
  po('a sibling with the same prefix is not inside it', '/Users/sam/Code/notchmeow-old', [R], { root: '/Users/sam/Code/notchmeow-old', worktree: '' });
  po('the longest known root wins', SUB, ['/Users/sam/Code', R], { root: R, worktree: '' });
  po('doubled and trailing slashes fold away', '/Users/sam/Code//notchmeow/', [], { root: R, worktree: '' });
  po('a path with spaces', '/Users/sam/GitHub Local Repos/notchmeow', [], { root: '/Users/sam/GitHub Local Repos/notchmeow', worktree: '' });
  po('a worktree in a worktree: the repository, and the innermost name', R + '/.claude/worktrees/a/.claude/worktrees/b', [], { root: R, worktree: 'b' });
  po('a worktree outside /.claude/worktrees/ is its own project', '/Users/sam/Code/notchmeow-wt', [R], { root: '/Users/sam/Code/notchmeow-wt', worktree: '' });
  po('a Windows path: backslashes and the drive letter', 'c:\\Users\\sam\\Code\\notchmeow\\.claude\\worktrees\\x', [], { root: 'C:/Users/sam/Code/notchmeow', worktree: 'x' });
  po('the root folder / matches only itself', '/Users/sam/x', ['/'], { root: '/Users/sam/x', worktree: '' });
  po('the root folder itself', '/', [], { root: '/', worktree: '' });
  po('an empty cwd is no project', '', [R], null);
  po('a cwd that is not text is no project', 7, [R], null);
  po('roots that are not text are skipped', SUB, [null, 3, R], { root: R, worktree: '' });
  po('the home folder is its own project', HOME, [], { root: HOME, worktree: '' });
  po('the home folder is never a root that others join', R, [HOME], { root: R, worktree: '' });
  po('under the home folder, a known project still takes its subfolders', SUB, [HOME, R], { root: R, worktree: '' });
  po('the home folder as given is normalized', R, [HOME], { root: R, worktree: '' }, '/Users/sam/');
  po('a worktree of a repository at the home folder belongs to it', HOME + '/.claude/worktrees/w1', [], { root: HOME, worktree: 'w1' });
  po('a Windows home folder', 'c:\\Users\\sam\\Code\\x', ['C:/Users/sam'], { root: 'C:/Users/sam/Code/x', worktree: '' }, 'C:\\Users\\sam');
  po('another parent folder still takes in sessions under it', R, ['/Users/sam/Code'], { root: '/Users/sam/Code', worktree: '' });
  po('no home folder given: the plain rule', R, [HOME], { root: HOME, worktree: '' }, '');
  const nm = (name, roots, expect, home = HOME) => { expectEqual(name, core.projectNames(roots, home), expect); names.push({ name, roots, home, expect }); };
  nm('a project is named by its folder', [R], [{ root: R, name: 'notchmeow', catKey: 'notchmeow' }]);
  nm('two projects with the same folder name show the parent folder', ['/Users/sam/GitHub Local Repos/notchmeow', R],
    [{ root: '/Users/sam/GitHub Local Repos/notchmeow', name: 'notchmeow — GitHub Local Repos', catKey: 'notchmeow' }, { root: R, name: 'notchmeow — Code', catKey: 'notchmeow' }]);
  nm('same folder and same parent: a number in first-seen order', ['/a/x/site', '/b/x/site'],
    [{ root: '/a/x/site', name: 'site — x', catKey: 'site' }, { root: '/b/x/site', name: 'site — x · 2', catKey: 'site' }]);
  nm('a root with no parent folder keeps the bare name', ['/proj', '/x/proj'], [{ root: '/proj', name: 'proj', catKey: 'proj' }, { root: '/x/proj', name: 'proj — x', catKey: 'proj' }]);
  nm('the alias table', ['/Users/sam/notch-buddy'], [{ root: '/Users/sam/notch-buddy', name: 'Notch Buddy', catKey: 'Notch Buddy' }]);
  nm('the root folder is Session', ['/'], [{ root: '/', name: 'Session', catKey: 'Session' }]);
  nm('a bidi override is removed', ['/Users/sam/Code/notch\u202Emeow'], [{ root: '/Users/sam/Code/notch\u202Emeow', name: 'notchmeow', catKey: 'notchmeow' }]);
  const long = 'n'.repeat(100);
  nm('a long folder name is cut at 60 code points', ['/Users/sam/' + long], [{ root: '/Users/sam/' + long, name: 'n'.repeat(59) + '…', catKey: 'n'.repeat(59) + '…' }]);
  nm('a Windows root', ['C:/Users/sam/notchmeow'], [{ root: 'C:/Users/sam/notchmeow', name: 'notchmeow', catKey: 'notchmeow' }]);
  nm('the home folder is Home', [HOME], [{ root: HOME, name: 'Home', catKey: 'Home' }]);
  nm('a folder named Home beside the home folder shows its parent; Home stays Home', [HOME, '/Users/sam/x/Home'],
    [{ root: HOME, name: 'Home', catKey: 'Home' }, { root: '/Users/sam/x/Home', name: 'Home — x', catKey: 'Home' }]);
  nm('no home folder given: named by its folder', [HOME], [{ root: HOME, name: 'sam', catKey: 'sam' }], '');
  const n100 = 'n'.repeat(100), cut55 = 'n'.repeat(55) + '…';
  nm('two long folder names that collide keep the parent folder and differ, each at most 60 code points', ['/a/x/' + n100, '/b/y/' + n100],
    [{ root: '/a/x/' + n100, name: cut55 + ' — x', catKey: 'n'.repeat(59) + '…' }, { root: '/b/y/' + n100, name: cut55 + ' — y', catKey: 'n'.repeat(59) + '…' }]);
  nm('a bare Home beside the home folder is numbered; the home folder stays exactly Home', ['/Home', HOME],
    [{ root: '/Home', name: 'Home · 2', catKey: 'Home' }, { root: HOME, name: 'Home', catKey: 'Home' }]);
  // A numbered label is taken before a later root can take it (distinct names), and a name is cut by code points at 59/60.
  nm('a numbered label is taken before a later root can take it', ['/a/p/site', '/b/p/site', '/c/site — p · 2'],
    [{ root: '/a/p/site', name: 'site — p', catKey: 'site' }, { root: '/b/p/site', name: 'site — p · 2', catKey: 'site' }, { root: '/c/site — p · 2', name: 'site — p · 2 · 2', catKey: 'site — p · 2' }]);
  const astral = 'a'.repeat(58) + '😀' + 'bc', comb = 'a'.repeat(58) + 'é' + 'x', zwj = 'a'.repeat(57) + '👨‍👩‍👧' + 'b';
  nm('an astral character at the cut: 58, the character, then …', ['/Users/sam/' + astral], [{ root: '/Users/sam/' + astral, name: 'a'.repeat(58) + '😀…', catKey: 'a'.repeat(58) + '😀…' }]);
  nm('a combining mark at the cut: the base letter stays, the mark goes with the cut', ['/Users/sam/' + comb], [{ root: '/Users/sam/' + comb, name: 'a'.repeat(58) + 'e…', catKey: 'a'.repeat(58) + 'e…' }]);
  nm('a ZWJ sequence straddling the cut: the joiners go first, the cut keeps two emoji', ['/Users/sam/' + zwj], [{ root: '/Users/sam/' + zwj, name: 'a'.repeat(57) + '👨👩…', catKey: 'a'.repeat(57) + '👨👩…' }]);
  // A parent folder longer than 58 code points: the tail is cut first and the number kept (fitName's last branch).
  const pp = 'p'.repeat(70);
  nm('a parent folder over 58 code points: the tail is cut, the number kept', ['/a/' + pp + '/site', '/b/' + pp + '/site'],
    [{ root: '/a/' + pp + '/site', name: ' — ' + 'p'.repeat(56) + '…', catKey: 'site' }, { root: '/b/' + pp + '/site', name: ' — ' + 'p'.repeat(52) + '… · 2', catKey: 'site' }]);
  const rl = (name, sessions, expect) => { expectEqual(name, core.rolesOf(sessions), expect); roles.push({ name, sessions, expect }); };
  rl('main, a side session, a second main', [{ id: 's1', worktree: '', seq: 1 }, { id: 's2', worktree: 'p0-plan', seq: 2 }, { id: 's3', worktree: '', seq: 3 }],
    [{ id: 's1', role: 'main', label: 'main' }, { id: 's2', role: 'side', label: 'p0-plan' }, { id: 's3', role: 'main', label: 'main · 2' }]);
  rl('mains are numbered in start order, whatever the input order', [{ id: 's3', worktree: '', seq: 3 }, { id: 's1', worktree: '', seq: 1 }],
    [{ id: 's3', role: 'main', label: 'main · 2' }, { id: 's1', role: 'main', label: 'main' }]);
  rl('two sessions in one worktree', [{ id: 'a', worktree: 'x', seq: 1 }, { id: 'b', worktree: 'x', seq: 2 }],
    [{ id: 'a', role: 'side', label: 'x' }, { id: 'b', role: 'side', label: 'x · 2' }]);
  rl('a session with no worktree value (undefined or null) is main, like the empty text', [{ id: 'u', seq: 1 }, { id: 'n', worktree: null, seq: 2 }],
    [{ id: 'u', role: 'main', label: 'main' }, { id: 'n', role: 'main', label: 'main · 2' }]);
  const so = (name, rows, expect) => { expectEqual(name, core.sessionOrder(rows), expect); order.push({ name, rows, expect }); };
  so('mains in start order, then sides by most recent activity', [{ id: 'm2', role: 'main', seq: 2, lastAt: 500 }, { id: 's-a', role: 'side', seq: 3, lastAt: 100 }, { id: 'm1', role: 'main', seq: 1, lastAt: 50 }, { id: 's-b', role: 'side', seq: 4, lastAt: 900 }], ['m1', 'm2', 's-b', 's-a']);
  so('sides with the same time: by id', [{ id: 'z', role: 'side', seq: 1, lastAt: 5 }, { id: 'y', role: 'side', seq: 2, lastAt: 5 }], ['y', 'z']);
  // The id is 'p-' plus the FNV-1a of the root, over UTF-8 (the expected values are computed apart from the core, in Python, and typed here).
  const ids = [];
  const pid = (name, root, expect) => { const got = core.projectsView(core.registryApply(core.emptyRegistry(), core.projectEventFrom({ hook_event_name: 'UserPromptSubmit', session_id: 's1', cwd: root }, T)), T).projects[0].id; expectEqual(name, got, expect); ids.push({ name, root, expect }); };
  pid('a non-ASCII root is hashed as UTF-8', '/Users/sam/Café/notchmeow', 'p-4109677a');
  pid('an astral root is hashed as UTF-8', '/Users/sam/🚀/notchmeow', 'p-747b001d');
  return { version: 1, note: 'projectOf(cwd, roots, home) -> {root, worktree} | null; projectNames(roots, home) -> [{root, name, catKey}] (the home folder is Home and never a root others join; an empty home is none); rolesOf(sessions) -> [{id, role, label}]; sessionOrder(rows) -> ids; ids: the view\'s project id of a root (p- plus fnv1a). Paths here are inputs only: nothing displayed holds one.', projectOf, names, roles, order, ids };
};

// ── event-cases.json: what the registry takes from a hook payload ──
SECTIONS['event-cases.json'] = () => {
  const cases = [];
  // stepped: the raw waitIn is a non-blank text (an in-app wait even when its host cleans to nothing).
  const E = (kind, o = {}) => ({ at: T, agent: 'claude', kind, sessionId: 's1', cwd: R, subagentId: '', subagentType: '', fromApp: false, termProgram: '', bundleId: '', waitIn: '', stepped: false, ...o });
  const O = agent => E('other', { agent, sessionId: '', cwd: '' });
  const ev = (name, payload, expect, now = T, waitIn) => {
    expectEqual(name, core.projectEventFrom(payload, now, waitIn), expect);
    cases.push({ name, payload, now, ...(waitIn === undefined ? {} : { waitIn }), expect });
  };
  const p = (hook, x = {}) => ({ hook_event_name: hook, session_id: 's1', cwd: R, ...x });
  ev('a prompt, without the prompt', p('UserPromptSubmit', { prompt: 'fix it' }), E('prompt'));
  ev('SessionStart', p('SessionStart'), E('start'));
  ev('a tool about to run', p('PreToolUse', { tool_name: 'Bash', tool_input: { command: 'ls' } }), E('preTool'));
  ev('AskUserQuestion before it runs is a question', p('PreToolUse', { tool_name: 'AskUserQuestion' }), E('question'));
  ev('a permission request', p('PermissionRequest', { tool_name: 'Bash' }), E('approval'));
  ev('a permission request for AskUserQuestion is a question', p('PermissionRequest', { tool_name: 'AskUserQuestion' }), E('question'));
  ev('a tool that ran', p('PostToolUse', { tool_name: 'Read' }), E('tool'));
  ev('a tool that failed is a tool event', p('PostToolUseFailure', { tool_name: 'Bash' }), E('tool'));
  ev('a notification that asks is a question', p('Notification', { message: 'Which file should I use?' }), E('question'));
  ev('a question mark followed by spaces', p('Notification', { message: '  Ready?  ' }), E('question'));
  ev('any other notification is a note', p('Notification', { message: 'Claude is waiting for your input' }), E('note'));
  ev('a notification with no message is a note', p('Notification'), E('note'));
  ev('Stop', p('Stop'), E('stop'));
  ev('StopFailure halts', p('StopFailure'), E('halt'));
  ev('Interrupt halts', p('Interrupt'), E('halt'));
  ev('SessionEnd', p('SessionEnd'), E('end'));
  ev('a subagent starts', p('SubagentStart', { agent_id: 'k1', agent_type: 'Explore' }), E('subStart', { subagentId: 'k1', subagentType: 'Explore' }));
  ev('a subagent stops', p('SubagentStop', { agent_id: 'k1' }), E('subStop', { subagentId: 'k1' }));
  ev("a subagent's tool event carries its id", p('PreToolUse', { tool_name: 'Grep', agent_id: 'k1', agent_type: 'Explore' }), E('preTool', { subagentId: 'k1', subagentType: 'Explore' }));
  ev('a subagent type loses its slashes', p('SubagentStart', { agent_id: 'k2', agent_type: 'plugin/x\\y' }), E('subStart', { subagentId: 'k2', subagentType: 'plugin-x-y' }));
  ev('a session from the Claude app is Claude Code, marked fromApp', p('PreToolUse', { nm_agent: 'claude-desktop' }), E('preTool', { fromApp: true }));
  ev('the tag claude is Claude Code', p('Stop', { nm_agent: 'claude' }), E('stop'));
  ev('an invalid tag is Claude Code, as the pill routing does', p('Stop', { nm_agent: 'Bad Tag!' }), E('stop'));
  ev('the terminal and the bundle are kept', p('Stop', { term_program: 'vscode', bundle_id: 'com.microsoft.VSCode' }), E('stop', { termProgram: 'vscode', bundleId: 'com.microsoft.VSCode' }));
  ev('conversation_id stands in for session_id', { hook_event_name: 'Stop', conversation_id: 'c1', cwd: R }, E('stop', { sessionId: 'c1' }));
  ev('a cwd that is not text is empty', { hook_event_name: 'Stop', session_id: 's1', cwd: 3 }, E('stop', { cwd: '' }));
  ev('Codex is another agent', p('UserPromptSubmit', { nm_agent: 'codex' }), O('agent_codex'));
  ev('another agent with its own event names', p('BeforeTool', { nm_agent: 'gemini-cli' }), O('agent_gemini-cli'));
  ev('Cursor is told by its bundle', p('PreToolUse', { bundle_id: 'com.todesktop.230313mzl4w4u92' }), O('agent_cursor'));
  ev('an event name Claude Code does not send', p('Whatever'), null);
  ev('no session id', { hook_event_name: 'Stop', cwd: R }, null);
  ev('no event name', { session_id: 's1', cwd: R }, null);
  ev('not an object', 'Stop', null);
  ev('a time that is not a number', p('Stop'), null, null);
  // The third argument, waitIn: the host a session steps back to (focus awareness, call A). Cleaned as a name, cut to 32 code points.
  ev('a permission request that steps back to Terminal keeps the host', p('PermissionRequest', { tool_name: 'Bash' }), E('approval', { waitIn: 'Terminal', stepped: true }), T, 'Terminal');
  // The in-app rule follows the raw text, not the cleaned host: invisible characters or a slash alone are a wait with no host (the label falls back).
  ev('a waitIn of invisible characters only is a stepped-back wait with no host', p('PermissionRequest', { tool_name: 'Bash' }), E('approval', { stepped: true }), T, '​');
  ev('a waitIn of a slash only is a stepped-back wait with no host', p('PermissionRequest', { tool_name: 'Bash' }), E('approval', { stepped: true }), T, '/');
  // Caps on the text the event keeps: ids at 128 code points (the cut keeps an ellipsis), a subagent type at 64 (a hard cut), a waitIn at 32.
  ev('a session id of 128 code points is kept', p('Stop', { session_id: 'x'.repeat(128) }), E('stop', { sessionId: 'x'.repeat(128) }));
  ev('a session id of 129 code points is cut to 127 and …', p('Stop', { session_id: 'x'.repeat(129) }), E('stop', { sessionId: 'x'.repeat(127) + '…' }));
  ev('a subagent id of 129 code points is cut to 127 and …', p('SubagentStart', { agent_id: 'k'.repeat(129), agent_type: 'Explore' }), E('subStart', { subagentId: 'k'.repeat(127) + '…', subagentType: 'Explore' }));
  ev('a subagent type of 64 code points is kept', p('SubagentStart', { agent_id: 'k2', agent_type: 'y'.repeat(64) }), E('subStart', { subagentId: 'k2', subagentType: 'y'.repeat(64) }));
  ev('a subagent type of 65 code points is cut to 64, no …', p('SubagentStart', { agent_id: 'k2', agent_type: 'y'.repeat(65) }), E('subStart', { subagentId: 'k2', subagentType: 'y'.repeat(64) }));
  ev('a waitIn of 32 code points is kept', p('PermissionRequest', { tool_name: 'Bash' }), E('approval', { waitIn: 'h'.repeat(32), stepped: true }), T, 'h'.repeat(32));
  ev('a waitIn of 33 code points is cut to 31 and …', p('PermissionRequest', { tool_name: 'Bash' }), E('approval', { waitIn: 'h'.repeat(31) + '…', stepped: true }), T, 'h'.repeat(33));
  ev('a very long waitIn is cut to 31 and …', p('PermissionRequest', { tool_name: 'Bash' }), E('approval', { waitIn: 'h'.repeat(31) + '…', stepped: true }), T, 'h'.repeat(300));
  ev('a waitIn that is not text is empty', p('PermissionRequest', { tool_name: 'Bash' }), E('approval'), T, 42);
  ev('a Claude App approval has no wait text, so the label falls back to Claude App', p('PermissionRequest', { nm_agent: 'claude-desktop', tool_name: 'Bash' }), E('approval', { fromApp: true }));
  ev('a waitIn of spaces only is no host', p('PermissionRequest', { tool_name: 'Bash' }), E('approval'), T, '   ');
  ev('a waitIn of more spaces than a name holds is no host', p('PermissionRequest', { tool_name: 'Bash' }), E('approval'), T, ' '.repeat(80));
  ev('a Claude App approval keeps no host, whatever waitIn it is given', p('PermissionRequest', { nm_agent: 'claude-desktop', tool_name: 'Bash' }), E('approval', { fromApp: true }), T, 'Terminal');
  // The cwd cap: a cwd longer than CWD_MAX_BYTES (4096) UTF-8 bytes reads as none, and a multi-byte cwd is counted in bytes, not code points.
  ev('a cwd of exactly 4096 bytes is kept', p('UserPromptSubmit', { cwd: '/' + 'a'.repeat(4095) }), E('prompt', { cwd: '/' + 'a'.repeat(4095) }));
  ev('a cwd of 4097 bytes reads as none', p('UserPromptSubmit', { cwd: '/' + 'a'.repeat(4096) }), E('prompt', { cwd: '' }));
  ev('a cwd is measured in UTF-8 bytes, not code points', p('UserPromptSubmit', { cwd: '/' + 'é'.repeat(2048) }), E('prompt', { cwd: '' }));
  return { version: 1, note: 'projectEventFrom(payload, now, waitIn) -> event | null. The event never holds the prompt, transcript_path, tool input or output, or a message. waitIn (optional) is the host a session steps back to: cleaned as a name, cut to 32 code points, \'\' when absent or not text.', cases };
};

// ── state-cases.json: a session's state at a time, a project's state ──
SECTIONS['state-cases.json'] = () => {
  const sessions = [], projects = [];
  const S = (o = {}) => ({ id: 's1', cwd: R, root: R, worktree: '', seq: 1, startedAt: T, lastAt: T, run: 'working', finishedAt: null, pending: [], fromApp: false, termProgram: '', bundleId: '', subagents: [], ...o });
  const X = (state, o = {}) => ({ state, dim: false, gone: false, waitingInApp: false, ...o });
  const st = (name, session, dt, expect) => { expectEqual(name, core.sessionStateAt(session, T + dt), expect); sessions.push({ name, session, now: T + dt, expect }); };
  st('working just before 10 min quiet', S(), 10 * MIN - 1, X('working'));
  st('quiet for 10 min shows idle', S(), 10 * MIN, X('idle'));
  st('finished just before 5.2 s', S({ run: 'finished', finishedAt: T }), 5199, X('finished'));
  st('finished becomes idle at 5.2 s', S({ run: 'finished', finishedAt: T }), 5200, X('idle'));
  st('not dim just before 30 min', S({ run: 'idle' }), 30 * MIN - 1, X('idle'));
  st('dim at 30 min', S({ run: 'idle' }), 30 * MIN, X('idle', { dim: true }));
  st('not gone just before 2 h', S({ run: 'idle' }), 120 * MIN - 1, X('idle', { dim: true }));
  st('gone at 2 h', S({ run: 'idle' }), 120 * MIN, X('idle', { dim: true, gone: true }));
  st('an open approval outranks a running tool', S({ pending: [{ by: '', kind: 'approval', at: T, inApp: false }] }), 1000, X('approval'));
  st('an approval outranks a question', S({ pending: [{ by: '', kind: 'question', at: T, inApp: false }, { by: 'k1', kind: 'approval', at: T, inApp: false }] }), 1000, X('approval'));
  st('a question', S({ pending: [{ by: '', kind: 'question', at: T, inApp: false }] }), 1000, X('question'));
  const cardA = { pending: [{ by: '', kind: 'approval', at: T, inApp: false }] }, cardQ = { pending: [{ by: '', kind: 'question', at: T, inApp: false }] };
  const appA = { fromApp: true, pending: [{ by: '', kind: 'approval', at: T, inApp: true }] };
  st('a notch card approval at 119 s', S(cardA), 119000, X('approval'));
  st("a notch card approval ends at 120 s, the hook's wait", S(cardA), 120000, X('working'));
  st('a notch card approval at 121 s', S(cardA), 121000, X('working'));
  st('a notch card question at 129 s', S(cardQ), 129000, X('question'));
  st("a notch card question ends at 130 s, the --ask hook's wait", S(cardQ), 130000, X('working'));
  st('a notch card question at 131 s', S(cardQ), 131000, X('working'));
  st("a subagent's approval card ended, the main agent's question still open", S({ pending: [{ by: 'k1', kind: 'approval', at: T, inApp: false }, { by: '', kind: 'question', at: T, inApp: false }] }), 125000, X('question'));
  st('a Claude App approval outlives the card wait', S(appA), 121000, X('approval', { waitingInApp: true }));
  st('the Claude App mark just before 10 min', S(appA), 10 * MIN - 1, X('approval', { waitingInApp: true }));
  st('the Claude App mark ends at 10 min', S(appA), 10 * MIN, X('idle'));
  const stepped = { pending: [{ by: '', kind: 'approval', at: T, inApp: true, waitIn: 'Terminal' }] };
  st('a stepped-back approval from Terminal just before 10 min', S(stepped), 10 * MIN - 1, X('approval', { waitingInApp: true }));
  st('a stepped-back approval from Terminal ends at 10 min', S(stepped), 10 * MIN, X('idle'));
  st('a clock behind the last event counts as no time', S(), -5000, X('working'));
  st('idle stays idle', S({ run: 'idle' }), 0, X('idle'));
  // A time that is not a finite number reads as the session's own last event: nothing ages, a waiting session stays waiting (no JSON NaN: null and absent).
  const stRaw = (name, session, now, expect) => { expectEqual(name, core.sessionStateAt(session, now), expect); sessions.push({ name, session, now, expect }); };
  stRaw('a null now: a working session is working, its age is nothing', S(), null, X('working'));
  stRaw('a null now: a card approval stays open', S(cardA), null, X('approval'));
  stRaw('a null now: a finished session is still finished', S({ run: 'finished', finishedAt: T }), null, X('finished'));
  stRaw('an absent now: a card question stays open', S(cardQ), undefined, X('question'));
  stRaw('an absent now: an idle session is not dimmed', S({ run: 'idle' }), undefined, X('idle'));
  const agos = [];
  const ago = (name, now, lastAt, expect) => { expectEqual(name, core.agoOf(now, lastAt), expect); agos.push({ name, now, lastAt, expect }); };
  ago('59 999 ms is still 0 minutes', T + 59999, T, 0);
  ago('60 000 ms is 1 minute', T + 60000, T, 1);
  ago('90 s is 1 minute (whole minutes)', T + 90000, T, 1);
  ago('a clock behind the last event is 0, never negative', T - 5000, T, 0);
  ago('an hour is 60 minutes', T + 60 * MIN, T, 60);
  const ps = (name, states, expect) => { expectEqual(name, core.projectStateOf(states), expect); projects.push({ name, states, expect }); };
  ps('working beats idle', ['idle', 'working'], 'working');
  ps('finished beats idle', ['finished', 'idle'], 'finished');
  ps('a question beats working', ['working', 'question'], 'question');
  ps('an approval beats a question', ['question', 'approval'], 'approval');
  ps('no session is idle', [], 'idle');
  ps('an unknown word counts for nothing', ['bogus', 'idle'], 'idle');
  return { version: 1, note: 'sessionStateAt(session, now) -> {state, dim, gone, waitingInApp}; an open ask lasts 10 min from the Claude App or from a stepped-back wait (inApp), else 120 s (approval) or 130 s (question); projectStateOf(states) -> the most urgent: approval, question, working, finished, idle. A now that is not a number reads the session\'s own lastAt (null or absent in these cases). agoCases: agoOf(now, lastAt) -> the whole minutes since lastAt, never below 0.', sessions, projects, agoCases: agos };
};

// ── registry-cases.json: hook events in, the view out (the typed short form, and the core's full view for the ports) ──
const brief = v => v.projects.map(p => ({ name: p.name, state: p.state, dim: p.dim, waiting: p.waiting,
  sessions: p.sessions.map(s => `${s.label}:${s.state}${s.dim ? ':dim' : ''}${s.waitingInApp ? ':app' : ''}${s.subagents.length ? ' +' + s.subagents.map(k => k.type).join(',') : ''}`) }));
SECTIONS['registry-cases.json'] = () => {
  const cases = [];
  const p = (hook, sid, cwd, x = {}) => ({ hook_event_name: hook, session_id: sid, cwd, ...x });
  const app = { nm_agent: 'claude-desktop' };
  const W = (name, state, sessions, o = {}) => ({ name, state, dim: false, waiting: 0, sessions, ...o });
  // Each step is [dt, payload] or [dt, expect] (an array of W(...) rows: the typed short form of the view at T + dt).
  // A payload step may carry a third item, waitIn (the host a session steps back to). A view step may carry a third item, notes: the typed
  // `label:note` of every row with a note (the note is not in brief's short form, so it is typed on its own).
  const notesOf = view => view.projects.flatMap(p => p.sessions.filter(s => s.note !== '').map(s => `${s.label}:${s.note}`));
  const seq = (name, steps, home = HOME) => {
    let reg = core.emptyRegistry(home); const out = [];
    for (const [dt, x, third] of steps) {
      if (!Array.isArray(x)) { reg = core.registryApply(reg, core.projectEventFrom(x, T + dt, third)); out.push({ at: T + dt, payload: x, ...(third === undefined ? {} : { waitIn: third }) }); }
      else {
        const view = core.projectsView(reg, T + dt, {});
        expectEqual(`${name} at +${dt}`, brief(view), x);
        if (third !== undefined) expectEqual(`${name} notes at +${dt}`, notesOf(view), third);
        out.push({ at: T + dt, expect: x, view, ...(third === undefined ? {} : { notes: third }) });
      }
    }
    cases.push({ name, home, steps: out });
  };
  seq('a worktree session joins its repository as a side session', [[0, p('UserPromptSubmit', 's-main', R)], [1000, p('PreToolUse', 's-side', WT, { tool_name: 'Bash' })], [2000, [W('notchmeow', 'working', ['main:working', 'p0-plan:working'])]]]);
  seq('a subfolder session is matched to the known project', [[0, p('UserPromptSubmit', 's1', R)], [1000, p('UserPromptSubmit', 's2', SUB)], [2000, [W('notchmeow', 'working', ['main:working', 'main · 2:working'])]]]);
  seq('a subfolder session with no known project is its own', [[0, p('UserPromptSubmit', 's1', SUB)], [1000, [W('src', 'working', ['main:working'])]]]);
  seq('a session that moves cwd stays in its first project', [[0, p('UserPromptSubmit', 's1', R)], [1000, p('PreToolUse', 's1', G, { tool_name: 'Read' })], [2000, [W('notchmeow', 'working', ['main:working'])]]]);
  seq('SessionEnd removes the session, and the project with its last session', [[0, p('UserPromptSubmit', 's1', R)], [0, p('UserPromptSubmit', 's2', G)], [1000, p('SessionEnd', 's1', R)], [2000, [W('gracegrip', 'working', ['main:working'])]]]);
  seq('two repositories whose names collide show their parent', [[0, p('UserPromptSubmit', 's1', '/Users/sam/GitHub Local Repos/notchmeow')], [1000, p('UserPromptSubmit', 's2', R)],
    [2000, [W('notchmeow — Code', 'working', ['main:working']), W('notchmeow — GitHub Local Repos', 'working', ['main:working'])]]]);
  seq('quiet 10 min shows idle, 30 min dims, 2 h leaves', [[0, p('UserPromptSubmit', 's1', R)],
    [10 * MIN - 1, [W('notchmeow', 'working', ['main:working'])]], [10 * MIN, [W('notchmeow', 'idle', ['main:idle'])]],
    [30 * MIN - 1, [W('notchmeow', 'idle', ['main:idle'])]], [30 * MIN, [W('notchmeow', 'idle', ['main:idle:dim'], { dim: true })]],
    [120 * MIN - 1, [W('notchmeow', 'idle', ['main:idle:dim'], { dim: true })]], [120 * MIN, []]]);
  seq('Stop shows finished for 5.2 s, then idle', [[0, p('UserPromptSubmit', 's1', R)], [1000, p('Stop', 's1', R)], [6199, [W('notchmeow', 'finished', ['main:finished'])]], [6200, [W('notchmeow', 'idle', ['main:idle'])]]]);
  seq("an open approval outranks a running tool; a subagent's tool event does not end the main session's approval", [[0, p('UserPromptSubmit', 's1', R)],
    [500, p('SubagentStart', 's1', R, { agent_id: 'k1', agent_type: 'Explore' })], [1000, p('PermissionRequest', 's1', R, { tool_name: 'Bash' })],
    [2000, p('PreToolUse', 's1', R, { tool_name: 'Grep', agent_id: 'k1', agent_type: 'Explore' })], [2500, p('PreToolUse', 's2', R, { tool_name: 'Read' })],
    [3000, [W('notchmeow', 'approval', ['main:approval +Explore', 'main · 2:working'], { waiting: 1 })]]]);
  seq('the Claude App mark, and its end at the next tool event', [[0, p('UserPromptSubmit', 's1', R, app)], [1000, p('PermissionRequest', 's1', R, { ...app, tool_name: 'Bash' })],
    [2000, [W('notchmeow', 'approval', ['main:approval:app'], { waiting: 1 })]], [3000, p('PostToolUse', 's1', R, { ...app, tool_name: 'Bash' })], [4000, [W('notchmeow', 'working', ['main:working'])]]]);
  seq('the Claude App mark ends by itself after 10 min', [[0, p('UserPromptSubmit', 's1', R, app)], [1000, p('PermissionRequest', 's1', R, { ...app, tool_name: 'Bash' })],
    [1000 + 10 * MIN - 1, [W('notchmeow', 'approval', ['main:approval:app'], { waiting: 1 })]], [1000 + 10 * MIN, [W('notchmeow', 'idle', ['main:idle'])]]]);
  seq('a question notification from the Claude app, ended by Stop', [[0, p('UserPromptSubmit', 's1', R, app)], [1000, p('Notification', 's1', R, { ...app, message: 'Which file should I use?' })],
    [1500, [W('notchmeow', 'question', ['main:question:app'], { waiting: 1 })]], [2000, p('Stop', 's1', R, app)], [2100, [W('notchmeow', 'finished', ['main:finished'])]]]);
  seq("a notch card approval ends after 120 s, the hook's wait", [[0, p('UserPromptSubmit', 's1', R)], [1000, p('PermissionRequest', 's1', R, { tool_name: 'Bash' })],
    [1000 + 119000, [W('notchmeow', 'approval', ['main:approval'], { waiting: 1 })]], [1000 + 121000, [W('notchmeow', 'working', ['main:working'])]]]);
  seq('a notch card question ends after 130 s', [[0, p('UserPromptSubmit', 's1', R)], [1000, p('PreToolUse', 's1', R, { tool_name: 'AskUserQuestion' })],
    [1000 + 129000, [W('notchmeow', 'question', ['main:question'], { waiting: 1 })]], [1000 + 131000, [W('notchmeow', 'working', ['main:working'])]]]);
  seq('kittens attach to their own session and leave on SubagentStop and Stop', [[0, p('UserPromptSubmit', 's1', R)], [0, p('UserPromptSubmit', 's2', G)],
    [100, p('SubagentStart', 's1', R, { agent_id: 'k1', agent_type: 'Explore' })], [200, p('SubagentStart', 's2', G, { agent_id: 'k2', agent_type: 'general-purpose' })],
    [300, p('SubagentStart', 's1', R, { agent_id: 'k3', agent_type: 'nm-implementer' })],
    [400, [W('notchmeow', 'working', ['main:working +nm-implementer,Explore']), W('gracegrip', 'working', ['main:working +general-purpose'])]],
    [500, p('SubagentStop', 's1', R, { agent_id: 'k1' })], [600, [W('notchmeow', 'working', ['main:working +nm-implementer']), W('gracegrip', 'working', ['main:working +general-purpose'])]],
    [700, p('Stop', 's1', R)], [800, [W('notchmeow', 'finished', ['main:finished']), W('gracegrip', 'working', ['main:working +general-purpose'])]]]);
  const nine = []; for (let i = 1; i <= 9; i++) nine.push([i * 100, p('SubagentStart', 's1', R, { agent_id: 'k' + i, agent_type: 't' + i })]);
  seq('at most 8 kittens per session: the oldest goes', [[0, p('UserPromptSubmit', 's1', R)], ...nine, [1000, [W('notchmeow', 'working', ['main:working +t9,t8,t7,t6,t5,t4,t3,t2'])]]]);
  seq('the order puts a waiting project first, then the most recent', [[0, p('UserPromptSubmit', 's1', R)], [100, p('PermissionRequest', 's1', R, { tool_name: 'Bash' })],
    [5000, p('UserPromptSubmit', 's2', G)], [6000, p('UserPromptSubmit', 's3', SITE)],
    [7000, [W('notchmeow', 'approval', ['main:approval'], { waiting: 1 }), W('site', 'working', ['main:working']), W('gracegrip', 'working', ['main:working'])]]]);
  seq('mains in start order, then side sessions by most recent activity', [[0, p('UserPromptSubmit', 'm1', R)], [100, p('UserPromptSubmit', 'a', R + '/.claude/worktrees/a')],
    [200, p('UserPromptSubmit', 'b', R + '/.claude/worktrees/b')], [300, p('UserPromptSubmit', 'm2', R)], [400, [W('notchmeow', 'working', ['main:working', 'main · 2:working', 'b:working', 'a:working'])]]]);
  seq("another agent's event makes no session", [[0, p('UserPromptSubmit', 'x1', R, { nm_agent: 'codex' })], [1000, []]]);
  seq('a session in the home folder is its own project, named Home', [[0, p('UserPromptSubmit', 'h', HOME)], [100, [W('Home', 'working', ['main:working'])]]]);
  seq('a later session under the home folder is not taken in by Home', [[0, p('UserPromptSubmit', 'h', HOME)], [100, p('UserPromptSubmit', 's1', R)],
    [200, [W('notchmeow', 'working', ['main:working']), W('Home', 'working', ['main:working'])]]]);
  seq('a session under the home folder before any home session works as before', [[0, p('UserPromptSubmit', 's1', R)], [100, p('UserPromptSubmit', 'h', HOME)], [200, p('UserPromptSubmit', 's2', SUB)],
    [300, [W('notchmeow', 'working', ['main:working', 'main · 2:working']), W('Home', 'working', ['main:working'])]]]);
  seq('a session that stepped back is counted once as Waiting in Terminal, ended by its next PreToolUse', [
    [0, p('UserPromptSubmit', 's1', R, { term_program: 'Apple_Terminal' })],
    [1000, p('PermissionRequest', 's1', R, { tool_name: 'Bash' }), 'Terminal'],
    [2000, [W('notchmeow', 'approval', ['main:approval:app'], { waiting: 1 })], ['main:Waiting in Terminal']],
    [121000, [W('notchmeow', 'approval', ['main:approval:app'], { waiting: 1 })], ['main:Waiting in Terminal']],
    [122000, p('PreToolUse', 's1', R, { tool_name: 'Bash' })],
    [123000, [W('notchmeow', 'working', ['main:working'])], []],
  ]);
  // A first-seen approval or question with no folder is filed under Home (still shown, still counted waiting); another first event with no folder is dropped.
  seq('a first-seen approval with no folder is filed under Home and counts as waiting; other events with no folder are dropped', [
    [0, p('UserPromptSubmit', 's1', '')], [100, p('PermissionRequest', 's2', '', { tool_name: 'Bash' })],
    [200, [W('Home', 'approval', ['main:approval'], { waiting: 1 })]]]);
  // A stepped-back wait whose raw host is invisible: in-app (it lasts 10 min, not 120 s), labelled with the blank-host fallback.
  seq('a stepped-back wait with an invisible host is in-app, labelled Waiting in Claude App', [[0, p('UserPromptSubmit', 's1', R)],
    [1000, p('PermissionRequest', 's1', R, { tool_name: 'Bash' }), '​'],
    [2000, [W('notchmeow', 'approval', ['main:approval:app'], { waiting: 1 })], ['main:Waiting in Claude App']],
    [121000, [W('notchmeow', 'approval', ['main:approval:app'], { waiting: 1 })], ['main:Waiting in Claude App']],
    [1000 + 10 * MIN, [W('notchmeow', 'idle', ['main:idle'])]]]);
  // Kittens: the filter is strictly under 10 min from a kitten's last event (599999 shows, 600000 does not); the session's own activity is kept apart.
  seq('a kitten shows for 599999 ms after its last event and not at 600000', [[0, p('UserPromptSubmit', 's1', R)],
    [100, p('SubagentStart', 's1', R, { agent_id: 'k1', agent_type: 'Explore' })], [500000, p('PostToolUse', 's1', R, { tool_name: 'Read' })],
    [100 + 599999, [W('notchmeow', 'working', ['main:working +Explore'])]], [100 + 600000, [W('notchmeow', 'working', ['main:working'])]]]);
  // A late, older event does not move the last activity back: the session is still working 599999 ms after the newest one.
  seq('a late, older PreToolUse does not move the last activity back', [[0, p('UserPromptSubmit', 's1', R)],
    [1000000, p('PostToolUse', 's1', R, { tool_name: 'Read' })], [500, p('PreToolUse', 's1', R, { tool_name: 'Read' })],
    [1000000 + 599999, [W('notchmeow', 'working', ['main:working'])]], [1000000 + 600000, [W('notchmeow', 'idle', ['main:idle'])]]]);
  // An ask stamped after the view time is open (a clock behind counts it as open).
  seq('an ask stamped after the view time is open', [[0, p('UserPromptSubmit', 's1', R)], [5000, p('PermissionRequest', 's1', R, { tool_name: 'Bash' })],
    [1000, [W('notchmeow', 'approval', ['main:approval'], { waiting: 1 })]]]);
  // Kittens born at the same time: the one listed later shows first.
  seq('kittens born at the same time: the later one listed first', [[0, p('UserPromptSubmit', 's1', R)],
    [100, p('SubagentStart', 's1', R, { agent_id: 'k1', agent_type: 'Explore' })], [100, p('SubagentStart', 's1', R, { agent_id: 'k2', agent_type: 'Plan' })],
    [200, [W('notchmeow', 'working', ['main:working +Plan,Explore'])]]]);
  // A kitten whose card timed out (120 s) is working again, and its session with it.
  seq('a kitten whose card timed out is working again', [[0, p('UserPromptSubmit', 's1', R)], [100, p('SubagentStart', 's1', R, { agent_id: 'k1', agent_type: 'Explore' })],
    [1000, p('PermissionRequest', 's1', R, { tool_name: 'Bash', agent_id: 'k1' })],
    [1000 + 119000, [W('notchmeow', 'approval', ['main:approval +Explore'], { waiting: 1 })]],
    [1000 + 121000, [W('notchmeow', 'working', ['main:working +Explore'])]]]);
  // The pending cap: a session keeps its newest PENDING_MAX (16) open asks. The stepped-back ask (10 min old) is the oldest, so the 17th drops it.
  seq('a 17th asker drops the oldest open ask', [
    [0, p('UserPromptSubmit', 's1', R)],
    [1000, p('PermissionRequest', 's1', R, { tool_name: 'Bash' }), 'Terminal'],
    ...Array.from({ length: 16 }, (_, i) => [2000 + 1000 * i, p('PermissionRequest', 's1', R, { tool_name: 'Bash', agent_id: 'k' + (i + 1) })]),
    [18000, [W('notchmeow', 'approval', ['main:approval'], { waiting: 1 })], []],
    [200000, [W('notchmeow', 'working', ['main:working'])]],
  ]);
  // The caps and the clock's edges, replayed from the registry itself (no view): the sessions as id#seq, the kittens, the last activity and nextSeq.
  const caps = [];
  const cap = (name, events, expect) => {
    let reg = core.emptyRegistry(HOME); const out = [];
    for (const [dt, payload] of events) { reg = core.registryApply(reg, core.projectEventFrom(payload, T + dt)); out.push({ at: T + dt, payload }); }
    const got = { sessions: reg.sessions.map(s => `${s.id}#${s.seq}`), nextSeq: reg.nextSeq,
      subagents: Object.fromEntries(reg.sessions.filter(s => s.subagents.length).map(s => [s.id, s.subagents.map(k => k.id)])),
      lastAt: Object.fromEntries(reg.sessions.map(s => [s.id, s.lastAt])) };
    const pick = Object.fromEntries(Object.keys(expect).map(k => [k, got[k]]));
    expectEqual(name, pick, expect);
    caps.push({ name, home: HOME, events: out, expect });
  };
  const rootOf = i => '/Users/sam/Code/p' + i;
  const first64 = []; for (let i = 1; i <= 64; i++) first64.push(`s${i}#${i + 1}`);
  cap('65 sessions: the least recently active (the oldest) goes; the 65th is kept', Array.from({ length: 65 }, (_, i) => [i * 1000, p('UserPromptSubmit', 's' + i, rootOf(i))]),
    { sessions: first64, nextSeq: 66 });
  cap('65 sessions at one time: the lower seq goes first', Array.from({ length: 65 }, (_, i) => [0, p('UserPromptSubmit', 's' + i, rootOf(i))]),
    { sessions: first64, nextSeq: 66 });
  const first63 = []; for (let i = 0; i <= 63; i++) first63.push(`s${i}#${i + 1}`);
  cap('a 65th session older than all 64 is the one dropped', [...Array.from({ length: 64 }, (_, i) => [1000 + i, p('UserPromptSubmit', 's' + i, rootOf(i))]), [0, p('UserPromptSubmit', 'late', rootOf(99))]],
    { sessions: first63, nextSeq: 66 });
  const eight = []; for (let i = 0; i < 8; i++) eight.push('k' + i);
  cap('a SubagentStart for a kitten already shown refreshes it: no eviction at 8', [[0, p('UserPromptSubmit', 's1', R)],
    ...Array.from({ length: 8 }, (_, i) => [100 + i, p('SubagentStart', 's1', R, { agent_id: 'k' + i, agent_type: 't' + i })]),
    [500, p('SubagentStart', 's1', R, { agent_id: 'k0', agent_type: 't0' })]],
    { sessions: ['s1#1'], subagents: { s1: eight }, nextSeq: 2 });
  cap('a session 2 h quiet is gone at exactly 2 h: a new event is a new session', [[0, p('UserPromptSubmit', 's1', R)], [120 * MIN, p('PostToolUse', 's1', R, { tool_name: 'Read' })]],
    { sessions: ['s1#2'], nextSeq: 3 });
  cap('a session 2 h quiet minus 1 ms is revived by an event', [[0, p('UserPromptSubmit', 's1', R)], [120 * MIN - 1, p('PostToolUse', 's1', R, { tool_name: 'Read' })]],
    { sessions: ['s1#1'], nextSeq: 2 });
  cap('SessionEnd for a session not in the registry changes nothing, nextSeq too', [[0, p('UserPromptSubmit', 's1', R)], [100, p('SessionEnd', 's9', R)]],
    { sessions: ['s1#1'], nextSeq: 2 });
  cap('a late, older event does not move lastAt back', [[1000000, p('UserPromptSubmit', 's1', R)], [500, p('PreToolUse', 's1', R, { tool_name: 'Read' })]],
    { lastAt: { s1: T + 1000000 } });
  // The presentation: a session's host and a project's step and host, typed by hand. Each case has one project; its rows are listed in view order.
  const presentation = [];
  // `at` is an offset from T, or null / absent (a time that is not a number: the view reads the newest activity).
  const nowOf = at => (at === null || at === undefined ? at : T + at);
  const pres = (name, events, at, opts, expect) => {
    let reg = core.emptyRegistry(HOME);
    for (const [dt, payload] of events) reg = core.registryApply(reg, core.projectEventFrom(payload, T + dt));
    const view = core.projectsView(reg, nowOf(at), opts);
    const pr = view.projects[0] || {};
    const got = { projects: view.projects.length, step: pr.step, host: pr.host, rows: (pr.sessions || []).map(s => `${s.label}:${s.host}`), state: pr.state, waiting: pr.waiting };
    expectEqual(name, Object.fromEntries(Object.keys(expect).map(k => [k, got[k]])), expect);
    presentation.push({ name, home: HOME, payloads: events.map(([dt, payload]) => ({ at: T + dt, payload })), at: nowOf(at), opts, view, expect });
  };
  pres('a session in VS Code: its row and its project show vscode', [[0, p('UserPromptSubmit', 's1', R, { term_program: 'vscode' })]], 100, {},
    { projects: 1, step: '', host: 'vscode', rows: ['main:vscode'] });
  pres('a terminal session after a VS Code one: the project shows the newer row host', [[0, p('UserPromptSubmit', 's1', R, { term_program: 'vscode' })], [1000, p('UserPromptSubmit', 's2', R)]], 1100, {},
    { projects: 1, step: '', host: 'terminal', rows: ['main:vscode', 'main · 2:terminal'] });
  pres('a tie of activity goes to the larger seq: the side session gives the step and the host', [[0, p('UserPromptSubmit', 's1', R)], [0, p('UserPromptSubmit', 's2', WT, { term_program: 'vscode' })]], 100,
    { steps: { s1: 'Editing /Users/sam/Code/notchmeow/a.swift', s2: 'Running tests' } },
    { projects: 1, step: 'Running tests', host: 'vscode', rows: ['main:terminal', 'p0-plan:vscode'] });
  pres('a tie of activity: the larger seq wins even when it is the main session', [[0, p('UserPromptSubmit', 's1', WT, { term_program: 'vscode' })], [0, p('UserPromptSubmit', 's2', R)]], 100,
    { steps: { s1: 'Old step', s2: 'New step' } },
    { projects: 1, step: 'New step', host: 'terminal', rows: ['main:terminal', 'p0-plan:vscode'] });
  pres('the newer activity wins over the larger seq', [[0, p('UserPromptSubmit', 's1', R, { term_program: 'vscode' })], [500, p('UserPromptSubmit', 's2', R)], [1000, p('PreToolUse', 's1', R, { tool_name: 'Read' })]], 1100,
    { steps: { s1: 'Newer', s2: 'Old' } },
    { projects: 1, step: 'Newer', host: 'vscode', rows: ['main:vscode', 'main · 2:terminal'] });
  // A non-finite or absent now reads the newest activity (SF4): a waiting session stays waiting, nothing ages.
  const waitingNow = [[0, p('UserPromptSubmit', 's1', R, { term_program: 'Apple_Terminal' })], [1000, p('PermissionRequest', 's1', R, { tool_name: 'Bash' })]];
  pres('a null now reads the newest activity: the waiting session stays waiting', waitingNow, null, {},
    { projects: 1, step: '', host: 'terminal', rows: ['main:terminal'], state: 'approval', waiting: 1 });
  pres('an absent now reads the newest activity too', waitingNow, undefined, {},
    { projects: 1, step: '', host: 'terminal', rows: ['main:terminal'], state: 'approval', waiting: 1 });
  return { version: 1, note: 'Each case starts from emptyRegistry(home). Each step is a hook payload at a time (with waitIn, when the session stepped back), or a view at a time: `view` is projectsView(registry, at, {}) as the core gives it (ports compare it whole) and `expect` its typed short form (label:state[:dim][:app] [+subagent types]); `notes` (where typed) are the rows\' `label:note`. `presentation` replays hook payloads, then projectsView(registry, at, opts): `expect` types the project count, its step and host, and each row as label:host (and state and waiting, where typed); its `at` may be null or absent (a time that is not a number). `caps` replays hook payloads and types the registry itself (the caps, the clock\'s edges, nextSeq): sessions as id#seq, subagents per session, lastAt per session, only the keys `expect` names.', cases, caps, presentation };
};

// ── order-cases.json: the pill order, the big card's project, the waiting count ──
SECTIONS['order-cases.json'] = () => {
  const order = [], bigCard = [], waiting = [];
  const od = (name, projects, expect) => { expectEqual(name, core.projectOrder(projects).map(x => x.id), expect); order.push({ name, projects, expect }); };
  od('a waiting project first, then the most recent', [{ id: 'p-a', state: 'working', lastAt: 100 }, { id: 'p-b', state: 'idle', lastAt: 300 }, { id: 'p-c', state: 'question', lastAt: 50 }], ['p-c', 'p-b', 'p-a']);
  od('waiting projects among themselves by most recent', [{ id: 'p-a', state: 'approval', lastAt: 10 }, { id: 'p-b', state: 'question', lastAt: 20 }, { id: 'p-c', state: 'working', lastAt: 30 }], ['p-b', 'p-a', 'p-c']);
  od('the same time: by id', [{ id: 'p-z', state: 'idle', lastAt: 5 }, { id: 'p-y', state: 'idle', lastAt: 5 }], ['p-y', 'p-z']);
  od('nothing', [], []);
  const three = [{ id: 'p-a', lastAt: 100 }, { id: 'p-b', lastAt: 300 }, { id: 'p-c', lastAt: 200 }];
  const bc = (name, projects, pinned, clicked, expect) => { expectEqual(name, core.bigCardOf(projects, pinned, clicked), expect); bigCard.push({ name, projects, pinned, clicked, expect }); };
  bc('no pin, no click: the most recently active', three, null, null, { project: 'p-b', pinned: null, clicked: null });
  bc('the last clicked', three, null, 'p-a', { project: 'p-a', pinned: null, clicked: 'p-a' });
  bc('a pin beats the last click', three, 'p-c', 'p-a', { project: 'p-c', pinned: 'p-c', clicked: 'p-a' });
  bc('a pin goes with its project', three, 'p-gone', 'p-a', { project: 'p-a', pinned: null, clicked: 'p-a' });
  bc('a click on a project that left is forgotten', three, 'p-gone', 'p-gone2', { project: 'p-b', pinned: null, clicked: null });
  bc('a waiting project does not take the card by itself', [{ id: 'p-a', state: 'approval', lastAt: 500 }, ...three.slice(1)], null, 'p-c', { project: 'p-c', pinned: null, clicked: 'p-c' });
  bc('the same time: the first in the list', [{ id: 'p-x', lastAt: 5 }, { id: 'p-y', lastAt: 5 }], null, null, { project: 'p-x', pinned: null, clicked: null });
  bc('no project', [], 'p-a', 'p-b', { project: null, pinned: null, clicked: null });
  const wc = (name, projects, expect) => { expectEqual(name, core.waitingCount(projects), expect); waiting.push({ name, projects, expect }); };
  wc('the sum over projects', [{ waiting: 1 }, { waiting: 0 }, { waiting: 2 }], 3);
  wc('nothing waits', [], 0);
  wc('a count that is not a whole number is nothing', [{ waiting: 'x' }, { waiting: 1.5 }, { waiting: -1 }, { waiting: 2 }], 2);
  return { version: 1, note: 'projectOrder(projects) -> pill order (ids here); bigCardOf(projects, pinned, clicked) -> {project, pinned, clicked}; waitingCount(projects) -> sessions in approval or question.', order, bigCard, waiting };
};

// ── claude-only-cases.json: Claude only, and when the island may switch layout ──
SECTIONS['claude-only-cases.json'] = () => {
  const claudeOnly = [], layout = [];
  const co = (name, activePills, otherAgentSeen, expect) => { expectEqual(name, core.claudeOnly(activePills, otherAgentSeen), expect); claudeOnly.push({ name, activePills, otherAgentSeen, expect }); };
  co('Claude Code and integrations only', ['integration_claude', 'integration_github', 'integration_stripe'], false, true);
  co('another agent pill is declared', ['integration_claude', 'agent_codex'], false, false);
  co('another agent has sent an event', ['integration_claude'], true, false);
  co('nothing declared, nothing seen', [], false, true);
  co('the Claude app pill counts as Claude', ['integration_claude', 'agent_claude-desktop'], false, true);
  co('a list that is not a list, a flag that is not true', 'agent_codex', 'yes', true);
  co('IDs that are not agent pills', ['agent_', 'Agent_X'], false, true);
  const ly = (name, current, claudeOnlyNow, open, expect) => { expectEqual(name, core.islandLayout(current, claudeOnlyNow, open), expect); layout.push({ name, current, claudeOnly: claudeOnlyNow, open, expect }); };
  ly('folded: it switches to project pills', 'agents', true, false, 'projects');
  ly('open: it waits until the island folds', 'agents', true, true, 'agents');
  ly('open: project pills stay while the owner looks', 'projects', false, true, 'projects');
  ly('folded: back to agent pills', 'projects', false, false, 'agents');
  ly('no layout yet: decided now, even open', null, true, true, 'projects');
  return { version: 1, note: 'claudeOnly(activePills, otherAgentSeen) -> false when another agent pill is declared or another agent has sent an event, else true; islandLayout(current, claudeOnlyNow, open) -> projects | agents, changing only while folded.', claudeOnly, layout };
};

// ── cat-cases.json: a project's cat, the clean-up of stored project cats ──
SECTIONS['cat-cases.json'] = () => {
  const cat = [], clean = [];
  const pc = (name, catKey, projectCats, mainCat, expect) => { expectEqual(name, core.projectCatOf(catKey, projectCats, mainCat), expect); cat.push({ name, catKey, projectCats, mainCat, expect }); };
  pc('no stored choice: picked from the name', 'notchmeow', {}, 'shrimpy', { cat: 'leo', stored: false });
  pc('a stored choice', 'notchmeow', { notchmeow: 'momo' }, 'shrimpy', { cat: 'momo', stored: true });
  pc('an unknown stored coat falls back to the pick', 'notchmeow', { notchmeow: 'tiger' }, 'shrimpy', { cat: 'leo', stored: false });
  pc('the Main cat is never picked', 'notchmeow', {}, 'leo', { cat: 'cloud', stored: false });
  pc('another name', 'site', {}, 'shrimpy', { cat: 'latte', stored: false });
  pc('an alias name', 'Notch Buddy', {}, 'shrimpy', { cat: 'button', stored: false });
  pc('a name with an accent is hashed as UTF-8', 'café', {}, 'shrimpy', { cat: 'snow', stored: false });
  pc('an unknown Main cat is Shrimpy', 'notchmeow', {}, 'nonsense', { cat: 'leo', stored: false });
  pc('an empty key wears the Main cat', '', {}, 'momo', { cat: 'momo', stored: false });
  pc('a key that is not text wears the Main cat', 3, {}, 'momo', { cat: 'momo', stored: false });
  pc('stored cats that are a list count for nothing', 'notchmeow', ['momo'], 'shrimpy', { cat: 'leo', stored: false });
  const cl = (name, raw, expect) => { expectEqual(name, core.cleanProjectCats(raw), expect); clean.push({ name, raw, expect }); };
  cl('good entries, in code-unit order', { site: 'oreo', notchmeow: 'momo' }, { notchmeow: 'momo', site: 'oreo' });
  cl('__proto__ and constructor are dropped', JSON.parse('{"__proto__":"momo","constructor":"momo","prototype":"momo"}'), {});
  cl('unknown coats are dropped', { a: 'tiger', b: 3, c: null }, {});
  cl('a key with a slash or a backslash is dropped', { 'a/b': 'momo', 'a\\b': 'momo' }, {});
  cl('60 code points is kept, 61 is dropped, empty is dropped', { ['k'.repeat(60)]: 'momo', ['k'.repeat(61)]: 'momo', '': 'momo' }, { ['k'.repeat(60)]: 'momo' });
  cl('a key with a control character is dropped', { 'a\u0007b': 'momo' }, {});
  cl('not an object', ['momo'], {});
  cl('null', null, {});
  const many = {}, kept = {}; for (let i = 0; i < 300; i++) many['k' + String(i).padStart(3, '0')] = 'momo';
  for (let i = 0; i < 256; i++) kept['k' + String(i).padStart(3, '0')] = 'momo';
  cl('at most 256, the first in code-unit order', many, kept);
  return { version: 1, note: 'projectCatOf(catKey, projectCats, mainCat) -> {cat, stored}: the stored coat, else pickCat([main], rng(fnv1a(catKey)), null) as cat-core.js picks; cleanProjectCats(raw) -> at most 256 {catKey: catId}.', cat, clean };
};

// ── step-cases.json: a step as the notch shows it (cleanStep), and a view whose opts.steps has __proto__ and constructor keys ──
SECTIONS['step-cases.json'] = () => {
  const steps = [], views = [];
  const st = (name, text, expect) => { expectEqual(name, core.cleanStep(text), expect); steps.push({ name, text, expect }); };
  st('a Unix path inside a word keeps its last part', 'open(/a/b/c.txt)', 'c.txt)');
  st('a Windows path inside a word keeps its last part', 'C:\\Users\\sam\\b.ts', 'b.ts');
  st('a trailing slash: a/ shows a', 'a/', 'a');
  st('a lone slash shows the ellipsis', '/', '…');
  st('C:\\ shows C:', 'C:\\', 'C:');
  st('exactly 80 code points are kept', 'x'.repeat(80), 'x'.repeat(80));
  st('81 code points are cut to 79 and …', 'x'.repeat(81), 'x'.repeat(79) + '…');
  st('an astral character at the cut: 79 characters, then …', '😀'.repeat(81), '😀'.repeat(79) + '…');
  st('invisible and bidi characters become spaces', 'a\u202Eb\u200Bc', 'a b c');
  st('a word of invisible characters only is nothing', '\u202E\u200B', '');
  st('words are joined by one space', '  Run   tests  ', 'Run tests');
  st('text that is not text is nothing', null, '');
  st('a number is nothing', 42, '');
  // A view whose steps map has own __proto__ and constructor keys: each session gets its own step, the others none, never an inherited one.
  const opts = JSON.parse('{"__proto__":"Editing a.ts","constructor":"Reading b.ts"}');
  const payloads = [[0, 's1'], [100, '__proto__'], [200, 'constructor']].map(([dt, sid]) => ({ at: T + dt, payload: { hook_event_name: 'UserPromptSubmit', session_id: sid, cwd: R } }));
  let reg = core.emptyRegistry(HOME);
  for (const x of payloads) reg = core.registryApply(reg, core.projectEventFrom(x.payload, x.at));
  const view = core.projectsView(reg, T + 200, { steps: opts });
  const expect = { step: 'Reading b.ts', rows: ['main:', 'main · 2:Editing a.ts', 'main · 3:Reading b.ts'] };
  expectEqual('the project step is the newest row\'s; each row has its own step, or none', { step: view.projects[0].step, rows: view.projects[0].sessions.map(s => `${s.label}:${s.step}`) }, expect);
  views.push({ name: 'opts.steps with __proto__ and constructor keys', home: HOME, payloads, at: T + 200, opts: { steps: opts }, view, expect });
  return { version: 1, note: 'cleanStep(text) -> the step the notch shows: invisible characters become spaces, a word that holds a / or \\ keeps its last part (… when none), at most 80 code points (cut with …). views: projectsView(registry, at, {steps}) with the steps map read as own keys only; `expect` types the project step and each row as label:step.', steps, views };
};

/** Every fixture file as text, by name. */
export function build() {
  const out = {};
  for (const [name, make] of Object.entries(SECTIONS)) out[name] = format(make());
  return out;
}

/** The fewest fixture files build() may write: fewer means a build() that wrote (almost) nothing, and a check that proves nothing. */
export const MIN_FILES = 8;

/** The problems of the fixtures in `dir` against `files` (name -> text): fewer than MIN_FILES files, a file missing or different, or a .json file in `dir` that build() did not write. `[]` when all is well. */
export function problemsOf(files, dir) {
  const problems = [], names = Object.keys(files);
  if (names.length < MIN_FILES) problems.push(`build() writes ${names.length} files, fewer than ${MIN_FILES}`);
  for (const [name, text] of Object.entries(files)) {
    const file = path.join(dir, name);
    const now = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
    if (now === null) problems.push(`${name} is missing`);
    else if (now !== text) problems.push(`${name} differs from what the core writes`);
  }
  if (fs.existsSync(dir)) for (const f of fs.readdirSync(dir)) if (f.endsWith('.json') && !names.includes(f)) problems.push(`${f} is not written by the generator`);
  return problems;
}

function main(argv) {
  const check = argv.includes('--check');
  const oi = argv.indexOf('--out');
  if (oi >= 0 && (!argv[oi + 1] || argv[oi + 1].startsWith('--'))) {
    console.error('usage: node scripts/gen-projects-fixtures.mjs [--check | --out DIR]');
    process.exit(2);
  }
  const outDir = oi >= 0 ? path.resolve(argv[oi + 1]) : FIXTURES;
  const files = build();
  if (check) {
    const problems = problemsOf(files, FIXTURES);
    for (const p of problems) console.log(`  ✗ ${p}`);
    if (problems.length) { console.log(`✗ ${problems.length} problem(s) in tests/fixtures/projects: run node scripts/gen-projects-fixtures.mjs`); process.exit(1); }
    console.log(`✓ ${Object.keys(files).length} fixture files match projects-core.js`);
    return;
  }
  fs.mkdirSync(outDir, { recursive: true });
  for (const [name, text] of Object.entries(files)) fs.writeFileSync(path.join(outDir, name), text);
  console.log(`wrote ${Object.keys(files).length} fixture files to ${path.relative(ROOT, outDir) || '.'}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(fs.realpathSync(process.argv[1])).href) main(process.argv.slice(2));
