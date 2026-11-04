import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const C = require('../../shared/companion-core.js');
const fx = name => JSON.parse(fs.readFileSync(new URL(`../fixtures/companion/${name}`, import.meta.url), 'utf8'));
const f = fx('conversation-cases.json'), s = fx('settings-cases.json');
test('titleOf, conversationClean, conversationsKeep replay conversation-cases.json', () => {
  for (const c of f.title) assert.equal(C.titleOf(c.text), c.expect, c.name);
  for (const c of f.clean) assert.deepEqual(C.conversationClean(c.raw), c.expect, c.name);
  for (const c of f.keep) assert.deepEqual(C.conversationsKeep(c.entries), c.expect, c.name);
});
test('cleanCompanionSettings replays settings-cases.json', () => { for (const c of s.cases) assert.deepEqual(C.cleanCompanionSettings(c.raw), c.expect, c.name); });
test('cleaning twice is cleaning once', () => {
  for (const c of s.cases) assert.deepEqual(C.cleanCompanionSettings(c.expect), c.expect, c.name);
  for (const c of f.clean) if (c.expect) assert.deepEqual(C.conversationClean(c.expect), c.expect, c.name);
});
test('fifty kept at most, whatever comes in', () => {
  const e = Array.from({ length: 80 }, (_, i) => ({ id: `c${i}`, pinned: i % 3 === 0, updatedAt: i }));
  const r = C.conversationsKeep(e);
  assert.equal(r.keep.length, 50); assert.equal(r.evict.length, 30);
  assert.ok(r.evict.every(id => !e.find(x => x.id === id).pinned), 'unpinned go first');
});
test('a long conversation keeps its newest 1000 messages, first and last', () => {
  const row = f.clean.find(c => c.name === 'a conversation of 1005 messages keeps the newest 1000');
  const got = C.conversationClean(row.raw).messages;
  assert.equal(got.length, 1000);
  assert.equal(got[0].text, 'm5');
  assert.equal(got[999].text, 'm1004');
});
test('never throws', () => { for (const v of [undefined, null, 1, 'x', [], {}, [null, 1, {}], { messages: {} }]) { C.titleOf(v); C.conversationClean(v); C.conversationsKeep(v); C.cleanCompanionSettings(v); } });
