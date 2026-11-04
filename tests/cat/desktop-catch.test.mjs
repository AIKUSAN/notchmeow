import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';

// The file catch (fixes after H): a file on its way into the island is an alert to the desktop cat. No new phase, event or act; one rule for "something wants the cat at the notch",
// one test the catch waits on, and one constant. docs/CAT-CONTRACT.md, "The file catch".
const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/desktop-cases.json', import.meta.url), 'utf8'));
const PHASES = core.DESKTOP_PHASES, INFO = core.DESKTOP_PHASE_INFO;

test('the file catch adds no phase, event or act, and a drop waits longer than the surprise and the flight together', () => {
  assert.equal(PHASES.length, 7);
  assert.equal(core.DESKTOP_EVENTS.length, 9);
  assert.equal(core.DESKTOP_ACTS.length, 11);
  assert.equal(core.DESKTOP_CATCH_WAIT_MS, 1500);
  assert.ok(core.DESKTOP_CATCH_WAIT_MS > core.DESKTOP_FLIGHT_MS + 450, 'the surprise is 450 ms and the flight 600');
});

test('desktopAlert: a flag counts only when it is exactly true, and so does a pill in the approval or question state', () => {
  const a = core.desktopAlert;
  for (const k of ['approval', 'question', 'chatApproval', 'fileCatch']) assert.equal(a({ [k]: true }), true, k);
  assert.equal(a({ pillStates: ['working', 'approval'] }), true);
  assert.equal(a({ pillStates: ['question'] }), true);
  assert.equal(a({ pillStates: ['error', 'ratelimit', 'dizzy', 'idle', 'working', 'finished'] }), false);
  for (const v of ['true', 1, null, [true], {}, undefined]) assert.equal(a({ fileCatch: v, approval: v }), false, JSON.stringify(v));
  for (const v of [null, undefined, 'approval', 1, true, [true], () => true]) assert.equal(a(v), false, String(v));
  assert.equal(a({ pillStates: 'approval' }), false);
  assert.equal(a({ pillStates: [{}, null, 7, ['approval']] }), false);
});

test('desktopCatchReady is the notch spot not being empty, so the island and the desktop never both draw the cat', () => {
  for (const p of PHASES) {
    assert.equal(core.desktopCatchReady(p), !INFO[p].notchEmpty, p);
    assert.equal(core.desktopCatchReady(p), !INFO[p].drawn, p + ': ready exactly when the desktop window does not draw it');
  }
  assert.deepEqual(PHASES.filter(p => core.desktopCatchReady(p)), ['home', 'atNotchForAlert']);
  for (const v of [null, undefined, 7, '', 'Home', 'flying', '__proto__', ['home'], {}]) assert.equal(core.desktopCatchReady(v), true, String(v));
});

test('desktop-cases.json: the file catch keys replay, and the four trips tell the story', () => {
  assert.equal(fx.catchWaitMs, core.DESKTOP_CATCH_WAIT_MS);
  assert.equal(typeof fx.catchNote, 'string');
  for (const c of fx.alertCases) assert.equal(core.desktopAlert(c.input), c.out, c.name);
  for (const c of fx.catchReady) assert.equal(core.desktopCatchReady(c.phase), c.out, JSON.stringify(c.phase));
  assert.ok(fx.alertCases.length >= 20 && fx.catchReady.length >= 15);
  const catches = fx.trips.filter(t => t.name.startsWith('a file catch'));
  assert.equal(catches.length, 4);
  assert.deepEqual(catches[0].out.map(r => r.state), ['retracting', 'atNotchForAlert', 'returning', 'onDesktop']);
  assert.deepEqual(catches[0].out.map(r => r.act), ['retract', 'dock', 'flyOut', 'land']);
  assert.deepEqual(catches[1].out.map(r => r.state), ['retracting', 'returning', 'onDesktop']);
  assert.deepEqual(catches[2].out.map(r => r.state), ['flyingOut', 'retracting', 'atNotchForAlert', 'returning', 'onDesktop']);
  assert.deepEqual(catches[3].out.map(r => `${r.state}:${r.act}`), ['home:null', 'home:null', 'home:null'], 'with the cat at home a file catch changes nothing');
});
