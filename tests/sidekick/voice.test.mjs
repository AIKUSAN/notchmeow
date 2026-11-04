import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
const core = createRequire(import.meta.url)('../../shared/sidekick-core.js');
const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/sidekick/voice-cases.json', import.meta.url), 'utf8'));
const recapFx = JSON.parse(fs.readFileSync(new URL('../fixtures/sidekick/recap-cases.json', import.meta.url), 'utf8'));

test('the fixture: every sentence is accepted or refused as it records', () => {
  for (const c of fx.cases) assert.equal(core.acceptNicerLine(c.line, c.facts), c.ok, c.name);
  assert.ok(fx.cases.filter(c => c.ok).length >= 10 && fx.cases.filter(c => !c.ok).length >= 20);
});

test('the template of a recap always passes its own sanity check, except where it names a path-like thing', () => {
  for (const c of recapFx.cases) if (c.recap) {
    for (const [i, line] of c.recap.lines.entries()) {
      if (/^\+\d+ more$/.test(line)) continue;
      assert.equal(core.acceptNicerLine(line, c.recap.facts), true, `${c.name}: ${line}`);
    }
  }
});

test('a sentence is never accepted for facts it does not match', () => {
  const facts = [{ agent: 'Claude Code', steps: 3, files: [], more: 0 }];
  for (const bad of ['Claude Code ran 4 steps.', 'Claude Code ran 3 steps at 10.', 'Claude Code ran 3 steps. http://x', 'Claude Code' + String.fromCharCode(0x2028) + 'ran 3 steps.']) assert.equal(core.acceptNicerLine(bad, facts), false, bad);
});

test('it never throws', () => {
  for (const line of [null, undefined, 5, {}, [], 'x'.repeat(100000)]) for (const facts of [null, undefined, 5, 'x', [], [null], [{}], { agent: 5 }]) assert.doesNotThrow(() => core.acceptNicerLine(line, facts));
});

test('facts that are cyclic or very deep are refused, never thrown', () => {
  const cyclic = { agent: 'Claude Code', steps: 3 };
  cyclic.self = cyclic;
  let deep = { agent: 'Claude Code' };
  for (let i = 0; i < 100000; i++) deep = { x: deep };
  assert.equal(core.acceptNicerLine('Claude Code ran 3 steps.', [cyclic]), false);
  assert.equal(core.acceptNicerLine('Claude Code finished.', deep), false);
  assert.equal(core.acceptNicerLine('Claude Code finished.', [deep]), false);
});
