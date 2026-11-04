#!/usr/bin/env node
// Prints the projects contract's rules as tables for the owner to read: the numbers, one set of sessions as they age, the sample timelines of the registry cases and a project's cat.
// It reads shared/projects-core.js and tests/fixtures/projects/ and writes nothing.
//   node scripts/print-projects-tables.mjs
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const P = require('../shared/projects-core.js');
const FIX = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../tests/fixtures/projects');
const pad = (s, n) => String(s).padEnd(n);
const head = t => console.log(`\n== ${t} ${'='.repeat(Math.max(0, 76 - t.length))}`);
const T = 1760000000000;

// A span as the owner reads it: "0 s", "5.1 s", "9 min 59 s", "10 min", "1 h 59 min 59.9 s", "2 h". Tenths are cut, never rounded, so 599999 ms reads 9 min 59.9 s.
const span = v => {
  const h = Math.floor(v / 3600000), m = Math.floor((v % 3600000) / 60000), secs = Math.floor((v % 60000) / 100) / 10;
  const s = Number.isInteger(secs) ? `${secs} s` : `${secs.toFixed(1)} s`;
  const parts = [h ? `${h} h` : '', m ? `${m} min` : '', secs ? s : ''].filter(Boolean);
  return parts.length ? parts.join(' ') : '0 s';
};

head('1. The numbers');
const numbers = [
  ['A working session with no event for', `${P.QUIET_IDLE_MS / 60000} min`, 'shows idle'],
  ['A session with no event for', `${P.DIM_MS / 60000} min`, 'is dimmed'],
  ['A session with no event for', `${P.REMOVE_MS / 3600000} h`, 'leaves the notch'],
  ['A finished session shows finished for', `${P.FINISHED_MS / 1000} s`, 'then idle'],
  ['A Claude App waiting mark ends by itself after', `${P.APP_WAIT_MS / 60000} min`, `shows "${P.APP_WAIT_LABEL}"`],
  ['A notch card approval mark ends after', `${P.CARD_APPROVAL_MS / 1000} s`, 'the PermissionRequest hook\'s wait'],
  ['A notch card question mark ends after', `${P.CARD_QUESTION_MS / 1000} s`, 'the question hook\'s wait'],
  ['The peek opens after the pointer rests for', `${P.PEEK_DWELL_MS / 1000} s`, ''],
  ['The "ago" labels refresh every', `${P.AGO_TICK_MS / 60000} min`, 'while the island is open'],
  ['Subagents shown per session, at most', `${P.SUBAGENTS_MAX}`, 'the oldest leaves'],
  ['Sessions kept in the registry, at most', `${P.SESSIONS_MAX}`, ''],
  ['A session\'s folder (cwd), at most', `${P.CWD_MAX_BYTES} bytes`, 'a longer one reads as none'],
  ['Open asks kept per session, at most', `${P.PENDING_MAX}`, 'the oldest goes'],
  ['A project name, at most', `${P.NAME_MAX} characters`, ''],
  ['A step, at most', `${P.STEP_MAX} characters`, ''],
  ['Stored project cats, at most', `${P.PROJECT_CATS_MAX}`, ''],
  ['The home folder\'s project is called', P.HOME_NAME, ''],
];
for (const [what, value, then] of numbers) console.log(`${pad(what, 50)}${pad(value, 14)}${then}`);
console.log('\nA boundary belongs to the later side: at exactly 10 min a session is idle, at exactly 30 min it is dim, at exactly 2 h it is gone.');

head('2. A session as it ages');
const kinds = [
  ['working', { run: 'working', lastAt: T, finishedAt: 0, pending: [] }],
  ['finished', { run: 'finished', lastAt: T, finishedAt: T, pending: [] }],
  ['Claude App ask', { run: 'working', lastAt: T, finishedAt: 0, pending: [{ by: '', kind: 'approval', at: T, inApp: true }] }],
  ['card approval', { run: 'working', lastAt: T, finishedAt: 0, pending: [{ by: '', kind: 'approval', at: T, inApp: false }] }],
];
const times = [0, 5100, 5200, 120000, 599000, 600000, 1799000, 1800000, 7199000, 7200000];
const cell = (session, at) => {
  const r = P.sessionStateAt(session, T + at);
  return [r.state, r.dim && 'dim', r.gone && 'gone'].filter(Boolean).join(', ');
};
console.log('Each row is the time since the session\'s last event; a cell is its state, with dim and gone added when they hold.\n');
console.log(pad('since last event', 20) + kinds.map(([name]) => pad(name, 20)).join(''));
for (const at of times) console.log(pad(span(at), 20) + kinds.map(([, session]) => pad(cell(session, at), 20)).join(''));

head('3. Sample timelines');
const cases = JSON.parse(fs.readFileSync(path.join(FIX, 'registry-cases.json'), 'utf8')).cases;
const sessionText = s => `${s.label}:${s.state}${s.dim ? ':dim' : ''}${s.note ? ` (${s.note})` : ''}${s.subagents.length ? ' +' + s.subagents.map(k => k.type).join(',') : ''}`;
for (const c of cases) {
  console.log(`\n${c.name}`);
  const t0 = c.steps[0].at;
  for (const st of c.steps) {
    if (!st.view) continue;
    console.log(`  +${span(st.at - t0)}`);
    if (st.view.projects.length === 0) console.log('     nothing shown');
    for (const p of st.view.projects) {
      console.log(`     ${p.name} [${p.state}]${p.dim ? ' dim' : ''} waiting ${p.waiting}: ${p.sessions.map(sessionText).join(', ')}`);
    }
  }
}

head('4. A project\'s cat');
const names = P.projectNames(['/Users/sam/Code/notchmeow', '/Users/sam/Code/gracegrip', '/Users/sam/Code/site', '/Users/sam/Code/notch-buddy', '/Users/sam'], '/Users/sam');
console.log(pad('project', 18) + pad('Main cat Shrimpy', 20) + 'Main cat Leo');
for (const n of names) {
  const shrimpy = P.projectCatOf(n.catKey, {}, 'shrimpy').cat;
  const leo = P.projectCatOf(n.catKey, {}, 'leo').cat;
  console.log(pad(n.name, 18) + pad(shrimpy, 20) + leo);
}
console.log('\nA project\'s cat is picked from its name, and is never the Main cat.');
