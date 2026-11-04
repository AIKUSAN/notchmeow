#!/usr/bin/env node
// Replays tests/fixtures/mac/projects-scenarios.json through shared/projects-core.js (P-mac, fix wave 2). The fixture's header says every `expect` was typed by hand and
// "must agree with shared/projects-core.js"; the Swift model test replays the same file through the Swift port, and this replays it through the core itself, so a
// hand-typed expectation that the core does not hold fails here instead of only ever being compared with the port.
//
// Each scenario's events are fed in order, at `base + at` (a leading `~` in a cwd is the fixture's `home`), and at each step the core's projectsView is read at that
// time; the island's layout is islandLayout over claudeOnly(["integration_claude"], otherAgentSeen) with the island folded, as the model test reads it. Every `expect`
// form the Swift test checks is checked: `projects` (name:state:waiting, in pill order), `rows` (label:state per named project), `notes` (label:note), `waiting`, `layout`.
// An unknown key, a mistyped value, a missing step count and a wrong number of expectations run all fail.
//   node scripts/test-projects-scenarios-core.mjs        (run from anywhere; scripts/test-projects-scenarios-core.sh calls it)
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const P = require('../shared/projects-core.js');
const fixture = JSON.parse(fs.readFileSync(fileURLToPath(new URL('../tests/fixtures/mac/projects-scenarios.json', import.meta.url)), 'utf8'));
const BASE = 1760000000000;

let failures = 0, ran = 0;
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function check(label, got, want) {
  if (same(got, want)) console.log(`  ✓ ${label}`);
  else { console.log(`  ✗ ${label}\n    got:      ${JSON.stringify(got)}\n    expected: ${JSON.stringify(want)}`); failures++; }
}
// An expectation of the fixture's own (counted: the total is pinned below).
function expectation(label, got, want) { ran++; check(label, got, want); }

// The floors, written from today's fixture (a deliberate fixture change updates them, with the Swift test's).
const STEP_COUNTS = { 'claude-app-wait': 4, 'collide-and-home': 7, end: 4, 'other-agent': 2, 'two-projects': 11 };
const STEP_KEYS = new Set(['say', 'at', 'wait_ms', 'event', 'expect', 'waitIn']);
const EXPECT_KEYS = new Set(['projects', 'rows', 'notes', 'waiting', 'layout']);
const TOTAL_EXPECTATIONS = 70;   // 28 projects lists + 25 project row lists + 2 notes + 9 waiting counts + 6 layouts

const isTextList = x => Array.isArray(x) && x.every(s => typeof s === 'string');
const home = typeof fixture.home === 'string' ? fixture.home : '/Users/sam';
const scenarios = fixture.scenarios && typeof fixture.scenarios === 'object' ? fixture.scenarios : {};

console.log('projects-scenarios.json: every scenario replayed through shared/projects-core.js');
check('five scenarios', Object.keys(scenarios).length, 5);
check("the scenarios' step counts", Object.fromEntries(Object.entries(scenarios).map(([n, s]) => [n, Array.isArray(s.steps) ? s.steps.length : -1]).sort(([a], [b]) => (a < b ? -1 : 1))), STEP_COUNTS);
for (const name of Object.keys(scenarios).sort()) {
  const steps = Array.isArray(scenarios[name].steps) ? scenarios[name].steps : [];
  let registry = P.emptyRegistry(home);
  for (const [i, step] of steps.entries()) {
    const label = `${name} step ${i + 1}`;
    check(`${label}: only keys the test reads`, Object.keys(step).filter(k => !STEP_KEYS.has(k)), []);
    check(`${label}: it has its time, its event (an object or null) and its expect`,
      typeof step.at === 'number' && 'event' in step && step.expect !== null && typeof step.expect === 'object' && !Array.isArray(step.expect), true);
    const now = BASE + step.at;
    if (step.event !== null && typeof step.event === 'object') {
      const payload = { ...step.event };
      if (typeof payload.cwd === 'string' && (payload.cwd === '~' || payload.cwd.startsWith('~/'))) payload.cwd = home + payload.cwd.slice(1);
      const ev = P.projectEventFrom(payload, now, typeof step.waitIn === 'string' ? step.waitIn : undefined);
      if (ev) registry = P.registryApply(registry, ev);
    }
    const view = P.projectsView(registry, now, {});
    const layout = P.islandLayout('agents', P.claudeOnly(['integration_claude'], registry.otherAgentSeen), false);
    const want = step.expect ?? {};
    check(`${label}: only expect keys the test reads`, Object.keys(want).filter(k => !EXPECT_KEYS.has(k)), []);
    if ('projects' in want) {
      if (isTextList(want.projects)) expectation(`${label}: projects`, view.projects.map(p => `${p.name}:${p.state}:${p.waiting}`), want.projects);
      else check(`${label}: projects is a list of text`, false, true);
    }
    if ('rows' in want) {
      const rows = want.rows;
      if (rows !== null && typeof rows === 'object' && !Array.isArray(rows) && Object.values(rows).every(isTextList)) {
        for (const pn of Object.keys(rows).sort()) {
          const project = view.projects.find(p => p.name === pn);
          expectation(`${label}: rows of ${pn}`, project ? project.sessions.map(s => `${s.label}:${s.state}`) : [], rows[pn]);
        }
      } else check(`${label}: rows is an object of lists of text`, false, true);
    }
    if ('notes' in want) {
      if (isTextList(want.notes)) expectation(`${label}: notes`, view.projects.flatMap(p => p.sessions).filter(s => s.note !== '').map(s => `${s.label}:${s.note}`), want.notes);
      else check(`${label}: notes is a list of text`, false, true);
    }
    if ('waiting' in want) {
      if (Number.isInteger(want.waiting)) expectation(`${label}: waiting`, view.waiting, want.waiting);
      else check(`${label}: waiting is a number`, false, true);
    }
    if ('layout' in want) {
      if (typeof want.layout === 'string') expectation(`${label}: layout`, layout, want.layout);
      else check(`${label}: layout is text`, false, true);
    }
  }
}
check('the scenarios ran 70 expectations in all (28 projects lists, 25 project row lists, 2 notes, 9 waiting counts, 6 layouts)', ran, TOTAL_EXPECTATIONS);

console.log(failures === 0 ? '\nAll tests passed.' : `\n${failures} test(s) failed.`);
process.exit(failures === 0 ? 0 : 1);
