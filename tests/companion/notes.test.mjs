import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const C = require('../../shared/companion-core.js');
const fx = name => JSON.parse(fs.readFileSync(new URL(`../fixtures/companion/${name}`, import.meta.url), 'utf8'));

test('constants are the spec values', () => {
  assert.equal(C.VERSION, 1);
  assert.deepEqual(C.SECTIONS, ['About you', 'Projects', 'Preferences', 'Open threads', 'Day log']);
  assert.deepEqual(C.NOTE_SECTIONS, ['About you', 'Projects', 'Preferences', 'Open threads']);
  assert.deepEqual(C.NOTE_SOURCES, ['you said', 'you edited', 'companion']);
  assert.equal(C.NOTES_MAX, 200); assert.equal(C.NOTE_MAX, 200); assert.equal(C.MEMORY_TOKENS_MAX, 4000);
  assert.equal(C.DAY_LOG_DAYS, 14); assert.equal(C.DAY_LOG_PROJECTS_MAX, 20); assert.equal(C.REMEMBER_CHIP, 'Remember this?');
});
test('isDay', () => {
  for (const d of ['2026-10-17', '2024-02-29', '2026-01-31']) assert.equal(C.isDay(d), true, d);
  for (const d of ['2026-02-30', '2026-13-01', '2026-1-01', '2026-10-17T00:00', '', 20261017, null]) assert.equal(C.isDay(d), false, String(d));
});
const f = fx('note-cases.json');
test('noteCheck replays note-cases.json', () => { for (const c of f.check) assert.deepEqual(C.noteCheck(c.text), c.expect, c.name); });
test('a refused secret or path echoes no text', () => {
  for (const v of ['My password is hunter2', 'The repo is in /Users/sam/Code/notchmeow']) {
    const r = C.noteCheck(v);
    assert.equal(r.ok, false);
    assert.equal(r.text, '');
  }
});
test('rememberOffers replays note-cases.json', () => { for (const c of f.offers) assert.deepEqual(C.rememberOffers(c.text), c.expect, c.name); });
test('an offer always passes noteCheck and is at most two', () => {
  const t = "I'm working on A. I prefer B. Call me C. Remember that D is E. I like F.";
  const o = C.rememberOffers(t);
  assert.equal(o.length, 2);
  for (const x of o) assert.equal(C.noteCheck(x.text).ok, true);
});
test('never throws on junk', () => { for (const v of [undefined, null, 1, {}, [], '\u0000', 'x'.repeat(100000)]) { C.noteCheck(v); C.rememberOffers(v); C.isDay(v); } });

// ── The ports' pins (final review D): one invisible set, a superset of projects-core's, no lookaround in the core ──
const CORE_SRC = fs.readFileSync(new URL('../../shared/companion-core.js', import.meta.url), 'utf8');
const PROJECTS_SRC = fs.readFileSync(new URL('../../shared/projects-core.js', import.meta.url), 'utf8');
// projects-core's INVISIBLE class as code point ranges, and the text it is written with (String.raw keeps the file's own backslashes).
const PROJECTS_RANGES = [[0x0, 0x1f], [0x7f, 0x9f], [0xad, 0xad], [0x61c, 0x61c], [0x180e, 0x180e], [0x200b, 0x200f], [0x202a, 0x202e], [0x2028, 0x2029], [0x2060, 0x2060], [0x2066, 0x2069], [0xfeff, 0xfeff], [0xfff9, 0xfffb], [0xe0000, 0xe007f]];
const PROJECTS_TEXT = String.raw`\\u0000-\\u001f\\u007f-\\u009f\\u00AD\\u061C\\u180E\\u200B-\\u200F\\u202A-\\u202E\\u2028\\u2029\\u2060\\u2066-\\u2069\\uFEFF\\uFFF9-\\uFFFB\\u{E0000}-\\u{E007F}`;
const inRanges = (cp, ranges) => ranges.some(([a, b]) => cp >= a && cp <= b);
test('projects-core still has the INVISIBLE class this test copies', () => {
  assert.ok(PROJECTS_SRC.includes(PROJECTS_TEXT));
});
test('the companion invisible set removes every character projects-core removes (a superset)', () => {
  const mine = new RegExp(C.INVISIBLE_SET, 'u');
  for (let cp = 0; cp <= 0x10ffff; cp++) {
    if (!inRanges(cp, PROJECTS_RANGES)) continue;
    assert.ok(mine.test(String.fromCodePoint(cp)), `U+${cp.toString(16).toUpperCase()}`);
  }
});
test('the quick set is the invisible set minus tab and the line breaks', () => {
  const all = new RegExp(C.INVISIBLE_SET, 'u'), quick = new RegExp(C.QUICK_INVISIBLE_SET, 'u');
  for (let cp = 0; cp <= 0x10ffff; cp++) {
    const ch = String.fromCodePoint(cp), keepsIt = cp === 9 || cp === 10 || cp === 13;
    assert.equal(quick.test(ch), all.test(ch) && !keepsIt, `U+${cp.toString(16).toUpperCase()}`);
  }
});
test('the lone surrogates go with the invisible characters, a valid pair stays', () => {
  assert.equal(C.noteCheck('hi \ud800 there').text, 'hi there');
  assert.equal(C.noteCheck('\u{1F600}').text, '\u{1F600}');
});
test('the core has no lookaround (the Rust regex crate has none)', () => {
  assert.doesNotMatch(CORE_SRC, /\(\?[=!<]/);
});

// ── Linear time (final review H1): no trim is a backtracking regex, so a long run of dots is cheap everywhere ──
test('a long run of dots is trimmed in linear time: every entry point under 200 ms', () => {
  const P = 'a' + '.'.repeat(100000) + 'a';
  const timed = (name, f) => {
    const t0 = performance.now();
    f();
    const ms = performance.now() - t0;
    assert.ok(ms < 200, `${name}: ${Math.round(ms)} ms`);
  };
  timed('noteCheck', () => C.noteCheck(P));
  timed('titleOf', () => C.titleOf(P));
  timed('rightNowOf: a label', () => C.rightNowOf({ projects: [{ name: 'a', waiting: 0, sessions: [{ role: 'main', label: P, state: 'idle', step: '', waitingInApp: false, note: '' }] }], waiting: 0, otherAgentSeen: false }));
  timed('rightNowOf: a step', () => C.rightNowOf({ projects: [{ name: 'a', waiting: 0, sessions: [{ role: 'main', label: 'main', state: 'working', step: P, waitingInApp: false, note: '' }] }], waiting: 0, otherAgentSeen: false }));
  timed('memoryRead', () => C.memoryRead('## About you\n- ' + P, '2026-10-17'));
});
