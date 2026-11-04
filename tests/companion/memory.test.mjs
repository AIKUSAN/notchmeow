import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const C = require('../../shared/companion-core.js');
const fx = name => JSON.parse(fs.readFileSync(new URL(`../fixtures/companion/${name}`, import.meta.url), 'utf8'));

const f = fx('memory-cases.json'), g = fx('daylog-cases.json');
test('memoryRead replays memory-cases.json', () => { for (const c of f.read) assert.deepEqual(C.memoryRead(c.text, c.today), c.expect, c.name); });
test('memoryText replays memory-cases.json', () => { for (const c of f.text) assert.equal(C.memoryText(c.memory), c.expect, c.name); });
test('noteAdd, noteEdit, noteRemove replay memory-cases.json', () => {
  for (const c of f.add) assert.deepEqual(C.noteAdd(c.memory, c.section, c.text, c.day, c.source), c.expect, c.name);
  for (const c of f.edit) assert.deepEqual(C.noteEdit(c.memory, c.index, c.text), c.expect, c.name);
  for (const c of f.remove) assert.deepEqual(C.noteRemove(c.memory, c.index), c.expect, c.name);
});
test('dayLogAdd replays daylog-cases.json', () => { for (const c of g.add) assert.deepEqual(C.dayLogAdd(c.memory, c.day, c.project), c.expect, c.name); });
test('memoryPromptBlock replays memory-cases.json', () => { for (const c of f.block) assert.equal(C.memoryPromptBlock(c.memory, c.maxTokens), c.expect, c.name); });
test('text, read, text is stable', () => {
  for (const c of f.read) { const t = C.memoryText(c.expect); assert.equal(C.memoryText(C.memoryRead(t, c.today)), t, c.name); }
});
test('the cap keeps the 200 newest notes, in file order', () => {
  const lines = ['## About you']; for (let i = 0; i < 205; i++) lines.push(`- Note ${i} (2026-10-${String(1 + (i % 17)).padStart(2, '0')}, you said)`);
  const m = C.memoryRead(lines.join('\n'), '2026-10-17');
  // 13 notes are on the 1st, the oldest day; the five oldest of all are the first five of them, in file order (i = 0, 17, 34, 51, 68).
  const dropped = [0, 17, 34, 51, 68];
  const kept = []; for (let i = 0; i < 205; i++) if (!dropped.includes(i)) kept.push(`Note ${i}`);
  assert.deepEqual(m.notes.map(n => n.text), kept);
});
const tok = s => Math.ceil(2 * Array.from(s).length / 7);
test('the block fits its budget, Day log first, oldest notes next', () => {
  const lines = ['## About you']; for (let i = 0; i < 200; i++) lines.push(`- Fact number ${i} about the user, kept short. (2026-10-${String(1 + (i % 17)).padStart(2, '0')}, you said)`);
  lines.push('## Day log'); for (let d = 4; d <= 17; d++) lines.push(`- 2026-10-${String(d).padStart(2, '0')}: notchmeow 2, gracegrip 1`);
  const m = C.memoryRead(lines.join('\n'), '2026-10-17');
  for (const budget of [768, 4000, 60]) {
    const b = C.memoryPromptBlock(m, budget);
    assert.ok(tok(b) <= budget, `${budget}: ${tok(b)}`);
  }
  const small = C.memoryPromptBlock(m, 768);
  assert.ok(!small.includes('Day log'), 'the Day log goes first');
  assert.ok(small.includes('Fact number 199'), 'a newest note stays');
  assert.equal(C.memoryPromptBlock(m, 10), '', 'nothing fits: empty');
});
test('never throws, and never changes its input', () => {
  const m = C.memoryRead('## About you\n- Hi (2026-10-10, you said)', '2026-10-17'), copy = JSON.stringify(m);
  C.noteAdd(m, 'Projects', 'x', '2026-10-17', 'you said'); C.noteEdit(m, 0, 'y'); C.noteRemove(m, 0); C.dayLogAdd(m, '2026-10-17', 'p'); C.memoryPromptBlock(m, 100);
  assert.equal(JSON.stringify(m), copy);
  for (const v of [undefined, null, 1, [], {}, { notes: 5, dayLog: 'x' }]) { C.memoryParse(v); C.memoryClean(v, v); C.memoryText(v); C.noteAdd(v, v, v, v, v); C.noteEdit(v, v, v); C.noteRemove(v, v); C.dayLogAdd(v, v, v); C.memoryPromptBlock(v, v); }
});
test('MEMORY_INTRO is the spec text', () => {
  assert.equal(C.MEMORY_INTRO, 'This file is yours. NotchMeow sends it with your messages when Use memory is on. Edit or delete anything.');
});
