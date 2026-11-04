import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const C = require('../../shared/companion-core.js');
const CAT = require('../../design/prototype/cat-core.js');
const fx = name => JSON.parse(fs.readFileSync(new URL(`../fixtures/companion/${name}`, import.meta.url), 'utf8'));

const p = fx('prompt-cases.json'), q = fx('quiet-cases.json');
test('promptOf replays prompt-cases.json', () => { for (const c of p.cases) assert.equal(C.promptOf(c.input), c.expect, c.name); });
test('the PC words replay the pc group of prompt-cases.json', () => { for (const c of p.pc) assert.equal(C.promptOf(c.input), c.expect, c.name); });
test('DEVICES are the Mac and the PC; CONDUCT_PC is CONDUCT with this computer for the Mac', () => {
  assert.deepEqual(C.DEVICES, ['mac', 'pc']);
  assert.ok(C.CONDUCT_PC === C.CONDUCT.replace('act on the Mac yet', 'act on this computer yet') && C.CONDUCT_PC !== C.CONDUCT);
  assert.ok(!C.promptOf({ device: 'pc', today: '2026-10-17' }).includes('Mac'));
});
test('companionQuiet, moodHint, memoryTokensFor replay quiet-cases.json', () => {
  for (const c of q.quiet) assert.equal(C.companionQuiet(c.input), c.expect, c.name);
  for (const c of q.mood) assert.equal(C.moodHint(c.state), c.expect, c.name);
  for (const c of q.tokens) assert.equal(C.memoryTokensFor(c.placement, c.contextTokens), c.expect, c.name);
});
test('the order is fixed: personality, conduct, memory, right now, date', () => {
  const t = C.promptOf({ memory: { notes: [{ section: 'About you', text: 'MARK-MEM', day: '', source: 'you said' }], dayLog: [] }, useMemory: true, seeSessions: true, rightNow: 'MARK-NOW', today: '2026-10-17', placement: 'cloud' });
  const at = s => t.indexOf(s);
  assert.ok(at('You are Shrimpy') === 0 && at('How to behave') < at('MARK-MEM') && at('MARK-MEM') < at('MARK-NOW') && at('MARK-NOW') < at('Today is 2026-10-17.'));
});
test('a local model gets at most a quarter of its input budget for the memory', () => {
  const notes = Array.from({ length: 200 }, (_, i) => ({ section: 'About you', text: `Fact ${i} that is about this long, more or less.`, day: '2026-10-10', source: 'you said' }));
  const t = C.promptOf({ memory: { notes, dayLog: [] }, useMemory: true, placement: 'local', contextTokens: 4096, today: '2026-10-17' });
  const block = t.split('\n\n').find(s => s.startsWith('What you remember'));
  assert.ok(Math.ceil(2 * Array.from(block).length / 7) <= 768);
});
test('no fixture and no companion source holds a raw invisible or bidi character', () => {
  // The raw-character check of fixtures and sources: the same set as the generator's RAW_INVISIBLE (code point ranges, written as numbers).
  const RAW_RANGES = [[0, 8], [11, 31], [127, 159], [0xad, 0xad], [0x34f, 0x34f], [0x61c, 0x61c], [0x180e, 0x180e], [0x200b, 0x200f], [0x202a, 0x202e], [0x2028, 0x2029], [0x2060, 0x206f], [0x3164, 0x3164], [0xfe00, 0xfe0f], [0xfeff, 0xfeff], [0xffa0, 0xffa0], [0xfff9, 0xfffb], [0xe0000, 0xe007f], [0xe0100, 0xe01ef]];
  const RAW = { test: text => [...text].some(ch => RAW_RANGES.some(([a, b]) => ch.codePointAt(0) >= a && ch.codePointAt(0) <= b)) };
  const dir = new URL('../fixtures/companion/', import.meta.url);
  const files = [...fs.readdirSync(dir).filter(f => f.endsWith('.json')).map(f => new URL(f, dir)),
    new URL('../../shared/companion-core.js', import.meta.url), new URL('../../scripts/gen-companion-fixtures.mjs', import.meta.url),
    ...fs.readdirSync(new URL('./', import.meta.url)).filter(f => f.endsWith('.mjs')).map(f => new URL(f, import.meta.url))];
  for (const u of files) assert.equal(RAW.test(fs.readFileSync(u, 'utf8')), false, u.pathname);
});
test('quiet: no joke line, no mood, the quiet line', () => {
  const t = C.promptOf({ quiet: true, mood: 'finished', humor: 'more' });
  assert.ok(t.includes(C.QUIET_LINE)); assert.ok(!t.includes(C.MOODS.finished)); assert.ok(!t.includes(C.HUMOR_LINES.more));
});
test('never throws', () => { for (const v of [undefined, null, 1, [], {}, { personality: 'x', memory: 3, today: {} }]) { C.promptOf(v); C.personalityLine(v); C.moodHint(v); C.companionQuiet(v); C.memoryTokensFor(v, v); } });
test('TRAIT_WORDS are the cat\'s trait words, the mischief one with its article', () => {
  for (const [key, , low, high] of CAT.TRAITS) {
    const want = [low, high].map(w => w.replace(/^a /, ''));
    assert.deepEqual(C.TRAIT_WORDS[key].map(w => w.replace(/^a /, '')), want, key);
  }
});
