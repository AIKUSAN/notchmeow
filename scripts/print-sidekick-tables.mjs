#!/usr/bin/env node
// Prints the sidekick's rules as tables for the owner to read: the risk reasons with a sample request and its line, the stuck rules with their thresholds and a timeline of
// each, and the recap and status samples. It reads shared/sidekick-core.js and tests/fixtures/sidekick/ and writes nothing.
//   node scripts/print-sidekick-tables.mjs
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const core = require('../shared/sidekick-core.js');
const FIX = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../tests/fixtures/sidekick');
const read = name => JSON.parse(fs.readFileSync(path.join(FIX, name), 'utf8'));
const pad = (s, n) => String(s).padEnd(n);
const clip = (s, n) => (s.length > n ? s.slice(0, n - 1) + '…' : s);
const head = t => console.log(`\n== ${t} ${'='.repeat(Math.max(0, 76 - t.length))}`);
const sec = ms => `${ms < 0 ? '-' : '+'}${Math.abs(Math.round(ms / 1000))}s`;

head('1. Risk rules: what a permission request is called, and the line under it');
const explain = read('explain-cases.json');
console.log(`${pad('risk', 7)}${pad('reason', 17)}${pad('sample request', 40)}line`);
for (const r of core.REASONS) {
  const c = explain.cases.find(x => x.reasonId === r.id && !x.near);
  const sample = c ? (c.input && (c.input.command ?? c.input.file_path) !== undefined ? `${c.tool}: ${Array.isArray(c.input.command) ? c.input.command.join(' ') : String(c.input.command ?? c.input.file_path).split('\n')[0]}` : `${c.tool}`) : '';
  console.log(`${pad(r.risk, 7)}${pad(r.id, 17)}${pad(clip(sample, 38), 40)}${c ? c.line : r.line}`);
}
const near = explain.cases.filter(c => c.near).slice(0, 6);
console.log('\nNear misses (a look-alike that is NOT the reason in the left column):');
for (const c of near) console.log(`  ${pad(c.near, 17)}${pad(clip(`${c.tool}: ${c.input.command ?? c.input.file_path}`, 36), 38)} -> ${c.reasonId}`);
console.log(`\n${explain.cases.length} rows pin ${core.REASONS.length} reasons. A label never allows or denies: only the user's click does.`);

head('2. Stuck rules: when an agent looks stuck (at most one nudge per session)');
const S = core.STUCK;
const stuckRows = [
  ['stuck.loop', `the same step ${S.LOOP_SAME} times in the last ${S.LOOP_CALLS} calls, within ${S.WINDOW_MS / 60000} min, with no successful edit between`, '{Agent} has run the same step 4 times.'],
  ['stuck.errors', `${S.ERRORS} failures in a row within ${S.WINDOW_MS / 60000} min (Claude Code only)`, '{Agent} hit 3 errors in a row.'],
  ['stuck.waiting', `a request unanswered for ${S.WAIT_MS / 1000} s, its card not on screen`, '{Agent} is still waiting for your OK.'],
  ['', `...and once the app has given up (${S.GIVE_UP_MS.mac / 1000} s on the Mac, ${S.GIVE_UP_MS.windows / 1000} s on Windows and Linux)`, '{Agent} is waiting for your OK in the terminal.'],
  ['stuck.silent', `${S.SILENT_MS / 60000} min after a finished step or a prompt, ${S.SILENT_PRE_MS / 60000} min after a step that never ended; not while a helper is under ${S.KITTEN_MS / 60000} min old`, '{Agent} has been quiet for {n} minutes.'],
];
for (const [kind, when, words] of stuckRows) { console.log(`${pad(kind, 14)}${when}`); console.log(`${pad('', 14)}says: ${words}`); }
console.log('Never while the user is away, never in the rate-limit state, once per session; after 2 dismissals a kind is muted.');
const stuck = read('stuck-cases.json');
for (const name of ['loop: the same step four times, then once per session', 'waiting, Mac: "still waiting" until 115 s, then the terminal line once', 'waiting, Windows: the terminal line from 110 s', 'silent: five minutes after a finished step']) {
  const c = stuck.cases.find(x => x.name === name);
  console.log(`\nTimeline: ${c.name}`);
  const t0 = c.steps[0].at;
  for (const st of c.steps) {
    if (st.payload) console.log(`  ${pad(sec(st.at - t0), 8)}${st.payload.hook_event_name}${st.payload.tool_input ? ' ' + clip(String(st.payload.tool_input.command ?? st.payload.tool_input.file_path ?? ''), 24) : ''}`);
    else console.log(`  ${pad(sec(st.at - t0), 8)}asked: ${st.expect ? `${st.expect}  "${st.text}"` : 'nothing'}${typeof st.nextAt === 'number' ? `   (timer set for ${sec(st.nextAt - t0)})` : '   (no timer)'}`);
  }
}

head('3. Recap: what the cat says when you come back (after at least 2 minutes away)');
for (const c of read('recap-cases.json').cases.filter(x => x.recap).slice(0, 14)) {
  console.log(`- ${c.name}`);
  for (const l of c.recap.lines) console.log(`    ${l}`);
}
console.log('- and no recap at all when nothing happened, or when you were away less than 2 minutes.');

head('4. "What\'s Claude doing?": the answer in the chat, from this Mac only');
for (const c of read('status-cases.json').cases.slice(0, 8)) {
  console.log(`- ${c.name}`);
  for (const l of c.status.lines) console.log(`    ${l}`);
}

head('5. When a note may show (in this order)');
console.log('off, kind, muted, away (a recap waits for the return, and so does a nudge), rate limit (a stuck nudge is held; a recap is allowed), card in front (the waiting nudge only needs its own card off screen), typing, another note (a recap replaces an unseen nudge), a note in the last 60 s (not the recap), already nudged, recap already given.');
console.log(`A refused nudge is kept ${core.HOLD_MS.nudge / 1000} s, a recap ${core.HOLD_MS.recap / 60000} min, then dropped silently. Away: lock, sleep, screen off, or ${core.IDLE.AWAY_S / 60} min idle; back when the last of them ends.`);
