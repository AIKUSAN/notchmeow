#!/usr/bin/env node
// Prints the companion contract's rules as tables for the owner to read: the numbers, a memory file, the system prompt, the Right now block, the daily recap, the quick actions and what a note may not hold.
// It reads shared/companion-core.js and writes nothing. Every sample is built from made-up names.
//   node scripts/print-companion-tables.mjs
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const C = require('../shared/companion-core.js');
const TODAY = '2026-10-17';
const pad = (s, n) => String(s).padEnd(n);
const head = t => console.log(`\n== ${t} ${'='.repeat(Math.max(0, 76 - t.length))}`);
const indent = (s, p = '   ') => s.split('\n').map(l => p + l).join('\n');
const cut = (s, n) => { const a = Array.from(s); return a.length > n ? a.slice(0, n - 1).join('') + '\u2026' : a.join(''); };

// The sample memory: two notes in two sections, an open thread and two Day log days.
let memory = { notes: [], dayLog: [] };
const note = (section, text, day, source) => {
  const r = C.noteAdd(memory, section, text, day, source);
  if (!r.ok) throw new Error(`sample note refused: ${r.reason}`);
  memory = r.memory;
};
const log = (day, project, times) => { for (let i = 0; i < times; i++) memory = C.dayLogAdd(memory, day, project); };
note('About you', 'Sam designs apps and codes on a Mac', '2026-10-10', 'you said');
note('Preferences', 'Prefers short answers with a code example', '2026-10-12', 'you said');
note('Projects', 'notchmeow is a notch app with a cat in it', '2026-10-15', 'companion');
note('Open threads', 'Decide the order of the Projects pills', '2026-10-16', 'you said');
log('2026-10-15', 'notchmeow', 2);
log('2026-10-15', 'site', 1);
log('2026-10-16', 'notchmeow', 1);

// The sample sessions, in projectsView's shape: one project with a working main and a worktree, one waiting in Ghostty.
const view = {
  projects: [
    { name: 'notchmeow', waiting: 0, sessions: [
      { role: 'main', label: '', state: 'working', step: 'Reading the plan in ~/Code/plan.md', note: '', waitingInApp: false },
      { role: 'side', label: 'f3a0', state: 'working', step: 'Running tests', note: '', waitingInApp: false },
    ] },
    { name: 'site', waiting: 1, sessions: [
      { role: 'main', label: '', state: 'approval', step: '', note: 'Waiting in Ghostty', waitingInApp: true },
    ] },
  ],
  waiting: 1,
  otherAgentSeen: true,
};
const rightNow = C.rightNowOf(view);

head('1. The numbers');
const numbers = [
  ['Notes in the memory, at most', `${C.NOTES_MAX} notes`, 'the oldest by day go first'],
  ['A note, at most', `${C.NOTE_MAX} code points`, 'a longer one is refused in the app; a longer line typed by hand is cut'],
  ['The memory in a prompt, at most', `${C.MEMORY_TOKENS_MAX} tokens`, 'a cloud model'],
  ['The memory on a local model', `${C.memoryTokensFor('local', 4096)} tokens`, 'a quarter of a 4,096-token model\'s input budget'],
  ['The Day log keeps', `${C.DAY_LOG_DAYS} days`, ''],
  ['Projects named per Day log day, at most', `${C.DAY_LOG_PROJECTS_MAX}`, ''],
  ['Right now, at most', `${C.RIGHT_NOW_MAX} code points`, 'a longer list says "and N more projects"'],
  ['Conversations kept, at most', `${C.CONVERSATIONS_MAX} conversations`, 'the oldest unpinned goes first'],
  ['A conversation title, at most', `${C.TITLE_MAX} code points`, ''],
  ['Messages per conversation, at most', `${C.MESSAGES_MAX}`, 'the newest are kept'],
  ['A message text, at most', `${C.MESSAGE_TEXT_MAX} code points`, ''],
  ['A quick action\'s text, at most', `${C.QUICK_TEXT_MAX} code points`, 'the rest is cut and the result says so'],
  ['Dismissals that mute the daily recap', `${C.RECAP_MUTE_AT}`, ''],
  ['The chat\'s offer to remember a line', C.REMEMBER_CHIP, ''],
];
for (const [what, value, then] of numbers) console.log(`${pad(what, 40)}${pad(value, 26)}${then}`);
console.log('');
for (const level of C.HUMOR_LEVELS) console.log(`Humor ${pad(level, 8)}${C.HUMOR_LINES[level]}`);

head('2. A memory file');
console.log(indent(C.memoryText(memory), ''));

head('3. The system prompt');
const input = { catName: 'Momo', userName: 'Sam', personality: { energy: 0.5, curiosity: 0.5, chatty: 0.5, affection: 0.5, sass: 0.5, mischief: 0.5 }, humor: 'little', mood: 'working', memory, useMemory: true, placement: 'cloud', seeSessions: true, rightNow, today: TODAY };
console.log('Balanced Momo, humor little, working, memory and sessions on, a cloud model:\n');
console.log(indent(C.promptOf(input)));
console.log('\nThe same while a session waits for an answer (quiet: no joke, no mood):\n');
console.log(indent(C.promptOf({ ...input, quiet: C.companionQuiet({ waiting: 1, card: false }) })));

head('4. Right now');
console.log('The sample sessions:\n');
console.log(indent(rightNow));
console.log('\nNo session:\n');
console.log(indent(C.rightNowOf({ projects: [], waiting: 0, otherAgentSeen: false })));
console.log('\nOnly another agent:\n');
console.log(indent(C.rightNowOf({ projects: [], waiting: 0, otherAgentSeen: true })));
console.log('\nForty projects, cut to the cap:\n');
const many = { projects: Array.from({ length: 40 }, (_, i) => ({ name: `project ${i + 1}`, waiting: 0, sessions: [{ role: 'main', label: '', state: 'working', step: '', note: '', waitingInApp: false }] })), waiting: 0, otherAgentSeen: false };
console.log(indent(C.rightNowOf(many)));
console.log('\nThe first cloud send shows this once, for each provider:\n');
console.log(indent(C.cloudNotice('Anthropic')));

head('5. The daily recap');
console.log(indent(C.dailyRecapText({ memory, today: TODAY, waiting: 1 }) ?? '(nothing to say)'));
console.log(`\nAfter one "not now" the count is ${C.recapDismiss(0)}; after two it is ${C.recapDismiss(1)}, and muted: ${C.recapMuted(C.recapDismiss(1))}.`);

head('6. Quick actions');
for (const kind of C.QUICK_KINDS) {
  const label = C.QUICK_LABELS[kind] === undefined ? '(no label)' : C.QUICK_LABELS[kind];
  const req = C.quickRequest(kind, 'teh cat sat');
  console.log(`\n${kind}: ${label}`);
  console.log('  system:');
  console.log(indent(C.QUICK_SYSTEM[kind], '     '));
  console.log('  user:');
  console.log(indent(req.user, '     '));
}

head('7. What a note may not hold');
const samples = [
  ['a plain note', 'Prefers short answers'],
  ['a password', 'my password is hunter2 and the rest'],
  ['a key shape', 'key sk-abcdefghijklmnop1234 in use'],
  ['a card number', 'card 4111 1111 1111 1111 on file'],
  ['a home path', 'the plan is in ~/Code/plan.md'],
  ['a 201-character line', 'word '.repeat(40) + 'x'],
];
for (const [label, text] of samples) {
  const r = C.noteCheck(text);
  console.log(`${pad(label, 24)}${pad(r.reason, 9)}${cut(r.text, 60)}`);
}
console.log('\nA secret or a path is refused with no text: the text column stays empty.');
