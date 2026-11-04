/**
 * The Projects rules, written once and shared (sub-project P, docs/PROJECTS-CONTRACT.md).
 *
 * Pure: no clock, no network, no files, no randomness. Every rule takes the time it needs as an argument. Both apps port these rules and replay
 * tests/fixtures/projects/*.json, which scripts/gen-projects-fixtures.mjs writes from this file. If an app and a fixture disagree, this file decides.
 *
 * A full path is held in the registry in memory only and never reaches a display field: names, labels, steps and keys carry no path separator.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.ProjectsCore = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
'use strict';
const api = { VERSION: 1 };

// ── Constants: the Interface table of the P-0 plan ──────────────────────────
api.VERSION = 1;
api.QUIET_IDLE_MS = 600000;
api.DIM_MS = 1800000;
api.REMOVE_MS = 7200000;
api.FINISHED_MS = 5200;
api.APP_WAIT_MS = 600000;
api.CARD_APPROVAL_MS = 120000;
api.CARD_QUESTION_MS = 130000;
api.PEEK_DWELL_MS = 400;
api.AGO_TICK_MS = 60000;
api.SUBAGENTS_MAX = 8;
api.SESSIONS_MAX = 64;
api.NAME_MAX = 60;
api.STEP_MAX = 80;
api.PROJECT_CATS_MAX = 256;
api.CWD_MAX_BYTES = 4096;
api.PENDING_MAX = 16;
api.APP_WAIT_LABEL = 'Waiting in Claude App';
api.HOME_NAME = 'Home';
api.STATES = ['approval', 'question', 'working', 'finished', 'idle'];
/** The cats' IDs, in cat-core's order (frozen: stored in settings). */
api.CAT_IDS = ['shrimpy', 'momo', 'ginger', 'midnight', 'latte', 'patches', 'blue', 'snow', 'oreo', 'mocha', 'silver', 'cloud', 'leo', 'button', 'puff', 'noodle'];
/** Folder names that show as a product name (lower-case keys). */
api.PROJECT_ALIASES = { 'notch-buddy': 'Notch Buddy', notchbuddy: 'Notch Buddy', notch_buddy: 'Notch Buddy' };

// ── Helpers ──────────────────────────────────────────────────────────────────
const isObj = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const isStr = x => typeof x === 'string';
const isNum = x => typeof x === 'number' && Number.isFinite(x);
const numOr0 = x => (isNum(x) ? x : 0);
const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
/** The invisible and control characters sidekick-core.js's baseName strips (bidi overrides, zero-width marks, line separators). */
const INVISIBLE = new RegExp('[\\u0000-\\u001f\\u007f-\\u009f\\u00AD\\u061C\\u180E\\u200B-\\u200F\\u202A-\\u202E\\u2028\\u2029\\u2060\\u2066-\\u2069\\uFEFF\\uFFF9-\\uFFFB\\u{E0000}-\\u{E007F}]', 'gu');
/** A text cut to `max` code points: kept whole when it fits, else cut with `…` at the end. */
const cutTo = (s, max) => {
  const cps = Array.from(s);
  return cps.length > max ? cps.slice(0, max - 1).join('') + '…' : cps.join('');
};
/** A display name: no invisible characters, at most NAME_MAX code points (the last one `…` when cut). */
const cleanName = s => cutTo(isStr(s) ? s.replace(INVISIBLE, '') : '', api.NAME_MAX);
/** A host's name as display text: the invisible characters and path separators out, the spaces at both ends out, then cut to NAME_MAX (so a blank host is no host, however long its spaces). */
const hostText = s => cutTo(isStr(s) ? s.replace(INVISIBLE, '').replace(/[\/\\]/g, '').trim() : '', api.NAME_MAX);
/** A project's name from its folder part, its parent part (` — parent`) and its number (` · k`). The folder part is cut first, so the parent part and the number survive; when those alone are too long, the parent part is cut and the number kept. At most NAME_MAX code points. */
const fitName = (head, tail, num) => {
  if (Array.from(head + tail + num).length <= api.NAME_MAX) return head + tail + num;
  const room = api.NAME_MAX - Array.from(tail + num).length;
  if (room >= 1) return cutTo(head, room) + tail + num;
  return cutTo(tail, api.NAME_MAX - Array.from(num).length) + num;
};
const byId = (a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

/** FNV-1a 32 over UTF-8, as 8 lower-case hex digits (the same function as sidekick-core.js). */
function fnv1a(s) {
  let h = 0x811c9dc5;
  for (const b of new TextEncoder().encode(s)) { h ^= b; h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16).padStart(8, '0');
}
api.fnv1a = fnv1a;

/** A path as one text: `/` separators, no doubled or trailing `/` (the root `/` stays), an upper-case drive letter. `''` when it is not a non-empty text. */
function normPath(cwd) {
  if (!isStr(cwd) || cwd === '') return '';
  let s = cwd.replace(/\\/g, '/').replace(/\/+/g, '/');
  if (s.length > 1 && s.endsWith('/')) s = s.slice(0, -1);
  return s.replace(/^([a-z]):(?=\/|$)/, (m, d) => `${d.toUpperCase()}:`);
}
api.normPath = normPath;

// ── Project of a session ─────────────────────────────────────────────────────
const WORKTREES = '/.claude/worktrees/';
/** Which project a session's folder belongs to: `{root, worktree}` (worktree `''` for a repository's own folder), or `null`. A worktree belongs to the repository before its path; its name is the segment after the last marker. The home folder is never a root that another session joins. */
function projectOf(cwd, roots, home) {
  const n = normPath(cwd);
  if (n === '') return null;
  const h = normPath(home);
  if (n.includes(WORKTREES)) {
    const first = n.indexOf(WORKTREES), last = n.lastIndexOf(WORKTREES);
    return { root: n.slice(0, first) || '/', worktree: cleanName(n.slice(last + WORKTREES.length).split('/')[0]) };
  }
  if (h !== '' && n === h) return { root: h, worktree: '' };
  let best = '';
  for (const r0 of Array.isArray(roots) ? roots : []) {
    if (!isStr(r0)) continue;
    const r = normPath(r0);
    if (r === '' || (h !== '' && r === h)) continue;
    const bare = r === '/' || /^[A-Z]:$/.test(r);
    const inside = n === r || (!bare && n.startsWith(r + '/'));
    if (inside && r.length > best.length) best = r;
  }
  return { root: best || n, worktree: '' };
}
api.projectOf = projectOf;

/** The name of each project root, in input order: `[{root, name, catKey}]`. The root folder is `Session`; the home folder is `HOME_NAME` and never shares a name. Two roots with one folder name show their parent folder, and two with the same label get a number. */
function projectNames(roots, home) {
  const h = normPath(home);
  const list = (Array.isArray(roots) ? roots : []).filter(isStr).map(normPath).filter(r => r !== '');
  const info = list.map(r => {
    const segs = r.split('/').filter(x => x !== '');
    const base = cleanName(segs.length ? segs[segs.length - 1] : '');
    const lc = base.toLowerCase();
    const isHome = r === h;
    const catKey = isHome ? api.HOME_NAME : base === '' ? 'Session' : own(api.PROJECT_ALIASES, lc) ? api.PROJECT_ALIASES[lc] : base;
    const parent = segs.length >= 2 ? cleanName(segs[segs.length - 2]) : '';
    return { root: r, isHome, catKey, parent };
  });
  const count = new Map();
  for (const i of info) count.set(i.catKey, (count.get(i.catKey) || 0) + 1);
  // A collision (two roots, one folder name) shows the parent folder; the home folder is never numbered and never shares its name.
  const tails = info.map(i => (!i.isHome && count.get(i.catKey) >= 2 && i.parent ? ` — ${i.parent}` : ''));
  const plain = info.map((i, j) => fitName(i.catKey, tails[j], ''));
  // Every name given so far is taken: a numbered label is recorded too, so a later root whose plain name is that label gets the next number (DR1).
  const taken = new Set(info.some(i => i.isHome) ? [api.HOME_NAME] : []);
  const used = new Map();
  return info.map((i, j) => {
    if (i.isHome) return { root: i.root, name: api.HOME_NAME, catKey: i.catKey };
    let k = (used.get(plain[j]) || 0) + 1;
    let name = k === 1 ? plain[j] : fitName(i.catKey, tails[j], ` · ${k}`);
    while (taken.has(name)) name = fitName(i.catKey, tails[j], ` · ${++k}`);
    taken.add(name);
    used.set(plain[j], k);
    return { root: i.root, name, catKey: i.catKey };
  });
}
api.projectNames = projectNames;

// ── Roles and order inside a project ─────────────────────────────────────────
/** Each session's role and label, in input order: a session in no worktree is `main`, one in a worktree is `side` (labelled by the worktree's name). The mains are numbered in start order (`main`, `main · 2`, …), and so are the sides of one worktree. */
function rolesOf(sessions) {
  const list = (Array.isArray(sessions) ? sessions : []).filter(isObj);
  const byStart = list.map((_, i) => i).sort((a, b) => numOr0(list[a].seq) - numOr0(list[b].seq));
  const roles = new Array(list.length), labels = new Array(list.length);
  let mains = 0;
  const sideCount = new Map();
  for (const i of byStart) {
    // A worktree that is not text (undefined, null) is no worktree, as the empty text is (SF8).
    const name = cleanName(isStr(list[i].worktree) ? list[i].worktree : '');
    if (name === '') {
      mains++;
      roles[i] = 'main';
      labels[i] = mains === 1 ? 'main' : `main · ${mains}`;
    } else {
      const k = (sideCount.get(name) || 0) + 1;
      sideCount.set(name, k);
      roles[i] = 'side';
      labels[i] = k === 1 ? name : `${name} · ${k}`;
    }
  }
  return list.map((s, i) => ({ id: s.id, role: roles[i], label: labels[i] }));
}
api.rolesOf = rolesOf;

/** The order sessions show in: the mains first, by start; then the sides, most recent activity first; a tie is broken by id. Returns the ids. */
function sessionOrder(rows) {
  const list = (Array.isArray(rows) ? rows : []).filter(isObj);
  const mains = list.filter(r => r.role === 'main').sort((a, b) => numOr0(a.seq) - numOr0(b.seq) || byId(a, b));
  const sides = list.filter(r => r.role !== 'main').sort((a, b) => numOr0(b.lastAt) - numOr0(a.lastAt) || byId(a, b));
  return [...mains, ...sides].map(r => r.id);
}
api.sessionOrder = sessionOrder;

// ── Hook events: what the registry takes from a hook payload ─────────────────
/** Claude Code's hook events by name. Any other name is no event for the registry. */
const CLAUDE_EVENTS = { SessionStart: 'start', UserPromptSubmit: 'prompt', PreToolUse: 'preTool', PostToolUse: 'tool', PostToolUseFailure: 'tool', PermissionRequest: 'approval', Notification: 'note', Stop: 'stop', StopFailure: 'halt', Interrupt: 'halt', SubagentStart: 'subStart', SubagentStop: 'subStop', SessionEnd: 'end' };
const CLAUDE_TAG = 'claude', CLAUDE_APP_TAG = 'claude-desktop', CURSOR_BUNDLE = 'com.todesktop.230313mzl4w4u92';
const AGENT_TAG = /^[a-z0-9-]{1,24}$/;
/** A text cut to 128 code points for an id, a terminal or a bundle; `''` when it is not text. */
const idText = s => (isStr(s) ? cutTo(s, 128) : '');
/** A subagent's type as text: invisible characters out, `/` and `\` as `-`, at most 64 code points (a hard cut, no `…`); `''` when not text. Used at the event and again in the view. */
const subTypeText = s => (isStr(s) ? Array.from(s.replace(INVISIBLE, '').replace(/[\/\\]/g, '-')).slice(0, 64).join('') : '');
/** True when the UTF-8 encoding of text `s` is longer than `max` bytes. Counts per code unit without encoding the whole text: 1, 2 or 3 bytes, 4 for a surrogate pair, 3 for a lone surrogate (it encodes as U+FFFD); stops as soon as it passes `max`. */
function utf8Over(s, max) {
  let n = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x80) n += 1;
    else if (c < 0x800) n += 2;
    else if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length && s.charCodeAt(i + 1) >= 0xdc00 && s.charCodeAt(i + 1) <= 0xdfff) { n += 4; i++; }
    else n += 3;
    if (n > max) return true;
  }
  return false;
}

/** A hook payload as an event `{at, agent, kind, sessionId, cwd, subagentId, subagentType, fromApp, termProgram, bundleId, waitIn, stepped}`, or `null`. Claude Code's events need a session id; another agent's event is `kind: 'other'` with every other field empty. `cwd` is the payload's text when it is at most CWD_MAX_BYTES (4096) UTF-8 bytes, else `''` (a longer one reads as none). `waitIn` (optional third argument) is the host a session steps back to, as text: a name cut to 32 code points, `''` when absent, not text or blank. `stepped` is true when the raw `waitIn` is a non-blank text (so an in-app wait even when its host cleans to nothing). Never holds a prompt, a transcript path, a tool's input or output, a message or an answer. */
function projectEventFrom(payload, now, waitIn) {
  if (!isObj(payload) || !isNum(now)) return null;
  const tag = isStr(payload.nm_agent) ? payload.nm_agent : '';
  const fromApp = tag === CLAUDE_APP_TAG;
  let agent = CLAUDE_TAG;
  if (!fromApp && tag !== CLAUDE_TAG && AGENT_TAG.test(tag)) agent = `agent_${tag}`;
  else if (!fromApp && isStr(payload.bundle_id) && payload.bundle_id.toLowerCase() === CURSOR_BUNDLE) agent = 'agent_cursor';
  if (agent !== CLAUDE_TAG) return { at: now, agent, kind: 'other', sessionId: '', cwd: '', subagentId: '', subagentType: '', fromApp: false, termProgram: '', bundleId: '', waitIn: '', stepped: false };
  const name = isStr(payload.hook_event_name) ? payload.hook_event_name : '';
  if (!own(CLAUDE_EVENTS, name)) return null;
  let kind = CLAUDE_EVENTS[name];
  if ((kind === 'preTool' || kind === 'approval') && payload.tool_name === 'AskUserQuestion') kind = 'question';
  if (kind === 'note' && isStr(payload.message) && payload.message.trim().endsWith('?')) kind = 'question';
  const sessionId = idText(payload.session_id) || idText(payload.conversation_id);
  if (sessionId === '') return null;
  return { at: now, agent: CLAUDE_TAG, kind, sessionId, cwd: isStr(payload.cwd) && !utf8Over(payload.cwd, api.CWD_MAX_BYTES) ? payload.cwd : '', subagentId: idText(payload.agent_id), subagentType: subTypeText(payload.agent_type), fromApp, termProgram: idText(payload.term_program), bundleId: idText(payload.bundle_id), waitIn: fromApp ? '' : cutTo(hostText(waitIn), 32), stepped: !fromApp && isStr(waitIn) && waitIn.trim() !== '' };
}
api.projectEventFrom = projectEventFrom;

// ── The registry: the sessions in memory, their states in time (spec rules 1 to 4) ──
const arrOf = x => (Array.isArray(x) ? x.filter(isObj) : []);
/** A deep copy of each object of a list, one at a time: an object that cannot be copied (a cycle, a BigInt) is dropped alone. */
function copyOf(list) {
  const out = [];
  for (const x of list) {
    try { out.push(JSON.parse(JSON.stringify(x))); } catch { /* this one only */ }
  }
  return out;
}
/** An empty registry for the user's home folder (normalized; `''` when none is given). */
function emptyRegistry(home) {
  return { version: 1, home: normPath(home), sessions: [], otherAgentSeen: false, nextSeq: 1 };
}
api.emptyRegistry = emptyRegistry;
/** A copy the rules may change: the input is never changed, and a session's lists are always lists. */
function cleanRegistry(r) {
  if (!isObj(r)) return emptyRegistry('');
  // root and cwd are normalized here, so a view never names a root that the names table does not hold (a '/a/' or 'c:\\x' root).
  const sessions = copyOf(Array.isArray(r.sessions) ? r.sessions.filter(isObj) : []).map(s => ({ ...s, root: normPath(s.root), cwd: normPath(s.cwd), pending: arrOf(s.pending), subagents: arrOf(s.subagents) }));
  return { version: 1, home: normPath(r.home), sessions, otherAgentSeen: r.otherAgentSeen === true, nextSeq: isNum(r.nextSeq) ? r.nextSeq : 1 };
}
/** Drops, on the copy `c`, the sessions 2 h quiet at `now`. */
function pruneIn(c, now) {
  c.sessions = c.sessions.filter(s => now - numOr0(s.lastAt) < api.REMOVE_MS);
  return c;
}
function registryPrune(registry, now) {
  const c = cleanRegistry(registry);
  return isNum(now) ? pruneIn(c, now) : c;
}
api.registryPrune = registryPrune;
/** Drops the least of `list` (by `less`) until at most `max` remain. */
function trimTo(list, max, less) {
  while (list.length > max) {
    let k = 0;
    for (let i = 1; i < list.length; i++) if (less(list[i], list[k])) k = i;
    list.splice(k, 1);
  }
}
/** The least recently active session goes first; a tie goes to the earlier start. */
const lessActive = (a, b) => numOr0(a.lastAt) < numOr0(b.lastAt) || (numOr0(a.lastAt) === numOr0(b.lastAt) && numOr0(a.seq) < numOr0(b.seq));

/** The newest lastAt of some sessions, 0 when none: the time a `now` that is not a number reads as (nothing ages). */
const newestOf = sessions => sessions.reduce((m, x) => Math.max(m, numOr0(x.lastAt)), 0);
const timeOf = (now, sessions) => (isNum(now) ? now : newestOf(sessions));

/** The registry after one event: a new registry, the input never changed. Prunes first; a session takes its project from its first folder and keeps it. An approval or question whose waitIn is non-blank text (`stepped`) is a stepped-back wait: `inApp` (it ends at APP_WAIT_MS, never at a card's wait) and its pending entry keeps the host. A session keeps its newest PENDING_MAX (16) open asks: the oldest goes when a 17th is pushed. */
function registryApply(registry, ev) {
  const c = cleanRegistry(registry);
  if (!isObj(ev) || !isStr(ev.agent)) return c;
  const at = timeOf(ev.at, c.sessions);
  pruneIn(c, at);
  if (ev.agent !== CLAUDE_TAG) { c.otherAgentSeen = true; return c; }
  const by = isStr(ev.subagentId) ? ev.subagentId : '', waitIn = isStr(ev.waitIn) ? ev.waitIn : '';
  let s = c.sessions.find(x => x.id === ev.sessionId);
  if (!s) {
    let cwd = normPath(ev.cwd);
    const asks = ev.kind === 'approval' || ev.kind === 'question';
    if (ev.kind === 'end') return c;
    // A first-seen ask with no usable folder is filed under the home project, so it is still shown and counted waiting (SF3).
    if (cwd === '' && asks && c.home !== '') cwd = c.home;
    if (cwd === '') return c;
    const pr = projectOf(cwd, [...new Set(c.sessions.map(x => x.root))], c.home);
    const seq = c.nextSeq;
    c.nextSeq = seq + 1;
    s = { id: ev.sessionId, cwd, root: pr.root, worktree: pr.worktree, seq, startedAt: at, lastAt: at, run: 'idle', finishedAt: null, pending: [], fromApp: false, termProgram: '', bundleId: '', subagents: [] };
    c.sessions.push(s);
    trimTo(c.sessions, api.SESSIONS_MAX, lessActive);
    if (!c.sessions.includes(s)) return c;
  }
  s.lastAt = Math.max(numOr0(s.lastAt), at);
  if (isStr(ev.termProgram) && ev.termProgram !== '') s.termProgram = ev.termProgram;
  if (isStr(ev.bundleId) && ev.bundleId !== '') s.bundleId = ev.bundleId;
  if (ev.fromApp === true) s.fromApp = true;
  const sub = by === '' ? undefined : s.subagents.find(x => x.id === by);
  const touch = state => { if (sub) { sub.state = state; sub.last = Math.max(numOr0(sub.last), at); } };
  switch (ev.kind) {
    case 'end': c.sessions = c.sessions.filter(x => x !== s); break;
    case 'prompt': s.run = 'working'; s.pending = []; break;
    case 'preTool': case 'tool': s.run = 'working'; s.pending = s.pending.filter(p => p.by !== by); touch('working'); break;
    case 'approval': case 'question':
      s.run = 'working';
      s.pending = s.pending.filter(p => p.by !== by);
      s.pending.push({ by, kind: ev.kind, at, inApp: s.fromApp || ev.stepped === true, waitIn });
      if (s.pending.length > api.PENDING_MAX) s.pending.splice(0, s.pending.length - api.PENDING_MAX);
      touch('approval');
      break;
    case 'stop': s.run = 'finished'; s.finishedAt = at; s.pending = []; s.subagents = []; break;
    case 'halt': s.run = 'idle'; s.finishedAt = null; s.pending = []; s.subagents = []; break;
    case 'subStart':
      if (by === '') break;
      if (sub) {
        sub.last = Math.max(numOr0(sub.last), at);
        if (isStr(ev.subagentType) && ev.subagentType !== '') sub.type = ev.subagentType;
      } else {
        s.subagents.push({ id: by, type: isStr(ev.subagentType) ? ev.subagentType : '', state: 'working', born: at, last: at });
        trimTo(s.subagents, api.SUBAGENTS_MAX, (a, b) => numOr0(a.born) < numOr0(b.born));
      }
      break;
    case 'subStop':
      if (by === '') break;
      s.subagents = s.subagents.filter(x => x.id !== by);
      s.pending = s.pending.filter(p => p.by !== by);
      break;
    default: break;
  }
  return c;
}
api.registryApply = registryApply;

/** An ask still open at `now`: an in-app ask (the Claude App, or a stepped-back wait, `inApp`) lasts APP_WAIT_MS; on a notch card a question lasts CARD_QUESTION_MS and an approval CARD_APPROVAL_MS (the hooks' own waits). A clock behind the ask counts it as open. Task 4 uses it too. */
function liveAsk(e, now) {
  if (!isObj(e) || (e.kind !== 'approval' && e.kind !== 'question')) return false;
  const wait = e.inApp === true ? api.APP_WAIT_MS : e.kind === 'approval' ? api.CARD_APPROVAL_MS : api.CARD_QUESTION_MS;
  return now - numOr0(e.at) < wait;
}
/** A session's state at `now`: `{state, dim, gone, waitingInApp}`. The session is not changed. */
function sessionStateAt(session, now) {
  if (!isObj(session)) return { state: 'idle', dim: false, gone: true, waitingInApp: false };
  // A `now` that is not a number reads as the session's own last event: nothing ages, a waiting session stays waiting (SF4).
  const t = isNum(now) ? now : numOr0(session.lastAt);
  const age = Math.max(0, t - numOr0(session.lastAt));
  const dim = age >= api.DIM_MS, gone = age >= api.REMOVE_MS;
  const live = arrOf(session.pending).filter(e => liveAsk(e, t));
  if (live.length) {
    const state = live.some(e => e.kind === 'approval') ? 'approval' : 'question';
    return { state, dim, gone, waitingInApp: live.some(e => e.inApp === true) };
  }
  let state = 'idle';
  if (session.run === 'working' && age < api.QUIET_IDLE_MS) state = 'working';
  else if (session.run === 'finished' && t - numOr0(session.finishedAt) < api.FINISHED_MS) state = 'finished';
  return { state, dim, gone, waitingInApp: false };
}
api.sessionStateAt = sessionStateAt;
/** The most urgent of some states: approval, question, working, finished, idle. Unknown words count for nothing; no state is idle. */
function projectStateOf(states) {
  const list = Array.isArray(states) ? states : [];
  return api.STATES.find(s => list.includes(s)) || 'idle';
}
api.projectStateOf = projectStateOf;

// ── The view: the projects and sessions the notch shows (spec rules 5 to 9) ──
const MINUTE_MS = 60000;
/** A step as the notch shows it: invisible characters become spaces, a word that holds a path keeps its last part (`…` when it has none), at most STEP_MAX code points. `''` when not text. */
function cleanStep(text) {
  if (!isStr(text)) return '';
  const words = text.replace(INVISIBLE, ' ').split(/\s+/).filter(w => w !== '').map(w => {
    if (!/[\/\\]/.test(w)) return w;
    const parts = w.split(/[\/\\]/).filter(x => x !== '');
    return parts.length ? parts[parts.length - 1] : '…';
  });
  return cutTo(words.join(' '), api.STEP_MAX);
}
api.cleanStep = cleanStep;

/** The label of a session that waits in an app: `Waiting in <host>` (the host as a name), or APP_WAIT_LABEL when no host is given. One function for the Claude App wait and a stepped-back wait (focus awareness, call A). */
function waitLabel(host) {
  const h = hostText(host);
  return h === '' ? api.APP_WAIT_LABEL : `Waiting in ${h}`;
}
api.waitLabel = waitLabel;

/** The host a session shows: the Claude App, VS Code (Cursor's bundle is not VS Code), or a terminal. */
function hostOf(s) {
  if (s.fromApp === true) return 'claude-app';
  const bundle = isStr(s.bundleId) ? s.bundleId.toLowerCase() : '';
  const where = `${isStr(s.termProgram) ? s.termProgram.toLowerCase() : ''} ${bundle}`;
  return bundle !== CURSOR_BUNDLE && where.includes('vscode') ? 'vscode' : 'terminal';
}
/** Whole minutes since `lastAt`, never below 0. */
const agoOf = (now, lastAt) => Math.max(0, Math.floor((numOr0(now) - numOr0(lastAt)) / MINUTE_MS));
api.agoOf = agoOf;
/** The cat a project shows: its stored coat, else the one picked from its name (projectCatOf). */
function catFor(catKey, opts) { return projectCatOf(catKey, opts.projectCats, opts.mainCat).cat; }

/** The notch's view at `now`: the live projects in pill order, the sessions waiting, the live session count and whether another agent was seen. The registry is not changed. `opts.steps` maps a session id to its step text. A row's note is `waitLabel` of its newest live in-app wait (Waiting in Claude App for the Claude App, Waiting in <host> for a stepped-back wait). */
function projectsView(registry, now, opts) {
  const o = isObj(opts) ? opts : {};
  const steps = isObj(o.steps) ? o.steps : {};
  const c = cleanRegistry(registry);
  const t = timeOf(now, c.sessions);
  const live = c.sessions.filter(s => isStr(s.root) && s.root !== '' && !sessionStateAt(s, t).gone);
  const bySeq = [...live].sort((a, b) => numOr0(a.seq) - numOr0(b.seq));
  const roots = [...new Set(bySeq.map(s => s.root))];
  const names = new Map(projectNames(roots, c.home).map(x => [x.root, x]));
  const projects = roots.map(root => {
    const group = bySeq.filter(s => s.root === root);
    const roles = new Map(rolesOf(group.map(s => ({ id: s.id, worktree: s.worktree, seq: s.seq }))).map(r => [r.id, r]));
    const rowOf = s => {
      const st = sessionStateAt(s, t), lastAt = numOr0(s.lastAt);
      const pending = arrOf(s.pending);
      const appWaits = pending.filter(e => liveAsk(e, t) && e.inApp === true);
      const subagents = arrOf(s.subagents).filter(k => t - numOr0(k.last) < api.QUIET_IDLE_MS)
        .map((k, i) => ({ k, i, state: pending.some(e => e.by === k.id && liveAsk(e, t)) ? 'approval' : 'working' }))
        .sort((a, b) => (a.state === 'approval' ? 0 : 1) - (b.state === 'approval' ? 0 : 1) || numOr0(b.k.born) - numOr0(a.k.born) || b.i - a.i)
        .map(({ k, state }) => ({ id: isStr(k.id) ? k.id : '', type: subTypeText(k.type), state }));
      return { id: s.id, role: roles.get(s.id).role, label: roles.get(s.id).label, state: st.state, dim: st.dim, waitingInApp: st.waitingInApp,
        note: st.waitingInApp ? waitLabel(appWaits[appWaits.length - 1].waitIn) : '', step: cleanStep(own(steps, s.id) ? steps[s.id] : ''), host: hostOf(s), lastAt, agoMin: agoOf(t, lastAt), subagents };
    };
    const rows = new Map(group.map(s => [s.id, rowOf(s)]));
    const order = sessionOrder(group.map(s => ({ id: s.id, role: roles.get(s.id).role, seq: s.seq, lastAt: s.lastAt })));
    const sessions = order.map(id => rows.get(id));
    const seqOf = new Map(group.map(s => [s.id, numOr0(s.seq)]));
    const newest = sessions.reduce((a, b) => (b.lastAt > a.lastAt || (b.lastAt === a.lastAt && seqOf.get(b.id) > seqOf.get(a.id)) ? b : a));
    const named = names.get(root), lastAt = Math.max(...sessions.map(r => r.lastAt));
    return { id: 'p-' + fnv1a(root), name: named.name, catKey: named.catKey, cat: catFor(named.catKey, o), state: projectStateOf(sessions.map(r => r.state)),
      dim: sessions.every(r => r.dim), waiting: sessions.filter(r => r.state === 'approval' || r.state === 'question').length, sessionCount: sessions.length,
      lastAt, agoMin: agoOf(t, lastAt), step: newest.step, host: newest.host, sessions };
  });
  const ordered = projectOrder(projects);
  return { projects: ordered, waiting: waitingCount(ordered), sessionCount: live.length, otherAgentSeen: c.otherAgentSeen };
}
api.projectsView = projectsView;

/** The projects in pill order: a waiting project (approval or question) first, then the most recently active, then by id. A new array of the same objects. */
function projectOrder(projects) {
  const waits = p => (p.state === 'approval' || p.state === 'question' ? 0 : 1);
  return (Array.isArray(projects) ? projects : []).filter(isObj).sort((a, b) => waits(a) - waits(b) || numOr0(b.lastAt) - numOr0(a.lastAt) || byId(a, b));
}
api.projectOrder = projectOrder;

/** The project the big card shows: the pinned one, else the last clicked, each only while that project is still there; else the most recently active (a tie: the first). `{project, pinned, clicked}`, ids or `null`. */
function bigCardOf(projects, pinned, clicked) {
  const list = (Array.isArray(projects) ? projects : []).filter(p => isObj(p) && isStr(p.id));
  const here = id => (isStr(id) && list.some(p => p.id === id) ? id : null);
  const pin = here(pinned), click = here(clicked);
  let best = null;
  for (const p of list) if (best === null || numOr0(p.lastAt) > numOr0(best.lastAt)) best = p;
  return { project: pin || click || (best === null ? null : best.id), pinned: pin, clicked: click };
}
api.bigCardOf = bigCardOf;

/** The sessions waiting (an approval or a question) over the projects: a whole number, never below 0. */
function waitingCount(projects) {
  return (Array.isArray(projects) ? projects : []).reduce((n, p) => n + (isObj(p) && Number.isInteger(p.waiting) && p.waiting >= 0 ? p.waiting : 0), 0);
}
api.waitingCount = waitingCount;

// ── Claude only, the layout switch and the project cats (spec rules 10 and 11, call 10) ──
/** cat-core.js's isPillId (the shape of a pill ID), copied and pinned by tests/projects/cats.test.mjs. */
const PILL_ID = /^[a-z][a-z0-9_-]{1,63}$/;
/** An agent pill other than Claude Code's own two (integration_claude and agent_claude-desktop): cat-core's isAgentPill, copied. */
const isOtherAgentPill = v => typeof v === 'string' && PILL_ID.test(v) && v.startsWith('agent_') && v.length > 6 && v !== 'agent_claude-desktop';
/** Claude only: no other agent's pill is declared and no other agent has sent an event. */
function claudeOnly(activePills, otherAgentSeen) {
  if (otherAgentSeen === true) return false;
  return !(Array.isArray(activePills) ? activePills : []).some(isOtherAgentPill);
}
api.claudeOnly = claudeOnly;
/** The island's layout: while it is open it keeps the layout it has; folded, it shows the projects when Claude only, else the agents. */
function islandLayout(current, claudeOnlyNow, open) {
  if (open === true && (current === 'projects' || current === 'agents')) return current;
  return claudeOnlyNow === true ? 'projects' : 'agents';
}
api.islandLayout = islandLayout;

/** cat-core.js line 31, copied: the seeded generator that picks a project's cat. */
function rng(seed){let s=seed>>>0;return()=>((s=(Math.imul(s,1103515245)+12345)>>>0)/4294967296)}
/** A key that can name a project's cat: 1 to NAME_MAX code points, no path separator, no invisible character, no prototype name. */
function isCatKey(k) {
  return isStr(k) && k !== '' && Array.from(k).length <= api.NAME_MAX && !/[\/\\]/.test(k) && k.replace(INVISIBLE, '') === k
    && k !== '__proto__' && k !== 'constructor' && k !== 'prototype';
}
/** The stored project cats, cleaned: `{catKey: catId}` in UTF-16 code-unit order, at most PROJECT_CATS_MAX; `{}` unless a plain object. */
function cleanProjectCats(raw) {
  const out = {};
  if (!isObj(raw)) return out;
  const keys = Object.keys(raw).filter(k => isCatKey(k) && api.CAT_IDS.includes(raw[k])).sort().slice(0, api.PROJECT_CATS_MAX);
  for (const k of keys) out[k] = raw[k];
  return out;
}
api.cleanProjectCats = cleanProjectCats;
/** The cat a project shows: its stored coat, else the one picked from its name as cat-core.js picks one with the Main cat taken. Stores nothing. `{cat, stored}`. */
function projectCatOf(catKey, projectCats, mainCat) {
  const main = api.CAT_IDS.includes(mainCat) ? mainCat : 'shrimpy';
  if (!isCatKey(catKey)) return { cat: main, stored: false };
  const stored = cleanProjectCats(projectCats);
  if (own(stored, catKey)) return { cat: stored[catKey], stored: true };
  const free = api.CAT_IDS.filter(c => c !== main);
  const r = rng(parseInt(fnv1a(catKey), 16))();
  return { cat: free[Math.min(free.length - 1, Math.max(0, Math.floor(r * free.length)))], stored: false };
}
api.projectCatOf = projectCatOf;

return api;
});
