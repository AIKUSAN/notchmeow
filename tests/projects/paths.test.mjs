import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const P = require('../../shared/projects-core.js');
const fx = name => JSON.parse(fs.readFileSync(new URL(`../fixtures/projects/${name}`, import.meta.url), 'utf8'));

test('constants are the spec values', () => {
  assert.equal(P.VERSION, 1);
  assert.equal(P.QUIET_IDLE_MS, 600000); assert.equal(P.DIM_MS, 1800000); assert.equal(P.REMOVE_MS, 7200000);
  assert.equal(P.FINISHED_MS, 5200); assert.equal(P.APP_WAIT_MS, 600000); assert.equal(P.PEEK_DWELL_MS, 400);
  assert.equal(P.CARD_APPROVAL_MS, 120000); assert.equal(P.CARD_QUESTION_MS, 130000); assert.equal(P.HOME_NAME, 'Home');
  assert.equal(P.AGO_TICK_MS, 60000); assert.equal(P.SUBAGENTS_MAX, 8); assert.equal(P.SESSIONS_MAX, 64);
  assert.equal(P.NAME_MAX, 60); assert.equal(P.STEP_MAX, 80); assert.equal(P.PROJECT_CATS_MAX, 256);
  assert.equal(P.CWD_MAX_BYTES, 4096); assert.equal(P.PENDING_MAX, 16);
  assert.equal(P.APP_WAIT_LABEL, 'Waiting in Claude App');
  assert.deepEqual(P.STATES, ['approval', 'question', 'working', 'finished', 'idle']);
  assert.deepEqual(P.PROJECT_ALIASES, { 'notch-buddy': 'Notch Buddy', notchbuddy: 'Notch Buddy', notch_buddy: 'Notch Buddy' });
  assert.equal(P.CAT_IDS.length, 16);
});
test('fnv1a', () => { assert.equal(P.fnv1a('notchmeow'), 'f4e9d251'); assert.equal(P.fnv1a('café'), 'a82b5049'); assert.equal(P.fnv1a(''), '811c9dc5'); });
test('normPath', () => {
  assert.equal(P.normPath('/Users/sam/Code//notchmeow/'), '/Users/sam/Code/notchmeow');
  assert.equal(P.normPath('c:\\Users\\sam'), 'C:/Users/sam');
  assert.equal(P.normPath('/'), '/'); assert.equal(P.normPath(''), ''); assert.equal(P.normPath(42), ''); assert.equal(P.normPath(null), '');
});
const f = fx('project-cases.json');
test('projectOf replays project-cases.json', () => { for (const c of f.projectOf) assert.deepEqual(P.projectOf(c.cwd, c.roots, c.home), c.expect, c.name); });
test('projectNames replays project-cases.json', () => { for (const c of f.names) assert.deepEqual(P.projectNames(c.roots, c.home), c.expect, c.name); });
test('rolesOf replays project-cases.json', () => { for (const c of f.roles) assert.deepEqual(P.rolesOf(c.sessions), c.expect, c.name); });
test('sessionOrder replays project-cases.json', () => { for (const c of f.order) assert.deepEqual(P.sessionOrder(c.rows), c.expect, c.name); });
test('names and keys never hold a path separator', () => {
  for (const c of f.names) for (const n of c.expect) { assert.doesNotMatch(n.name, /[\/\\]/); assert.doesNotMatch(n.catKey, /[\/\\]/); }
});
test('every name is at most NAME_MAX code points', () => {
  for (const c of f.names) for (const n of c.expect) assert.ok(Array.from(n.name).length <= P.NAME_MAX, n.name);
});
test('never throws on junk', () => {
  for (const v of [undefined, null, 1, {}, [], [null, 3, {}], '\u0000']) {
    P.projectOf(v, v, v); P.projectNames(v, v); P.rolesOf(v); P.sessionOrder(v); P.normPath(v);
  }
});
