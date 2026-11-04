import test from 'node:test';
import assert from 'node:assert/strict';
import { checkAdditive, linkDirApplies } from '../../scripts/check-fixtures-additive.mjs';

const OLD = ['{', '  "version": 1,', '  "cases": [', '    {"n":1},', '    {"n":2}', '  ],', '  "passes": {"a":["x"]}', '}', ''].join('\n');
const withLines = (at, ...lines) => { const l = OLD.split('\n'); l.splice(at, 0, ...lines); return l.join('\n'); };

test('the same file, and a file that only gains a key, pass', () => {
  assert.deepEqual(checkAdditive(OLD, OLD), { problems: [], added: [] });
  assert.deepEqual(checkAdditive(OLD, withLines(6, '  "extra": {"k":1},')), { problems: [], added: ['extra'] });
});

test('a key appended after the last one passes: the old last line only gains a comma', () => {
  const l = OLD.split('\n'); l[6] += ','; l.splice(7, 0, '  "extra": 1');
  assert.deepEqual(checkAdditive(OLD, l.join('\n')), { problems: [], added: ['extra'] });
});

test('a new case inside an old array passes: old cases are still there, byte for byte', () => {
  assert.deepEqual(checkAdditive(OLD, withLines(4, '    {"n":1.5},')).problems, []);
});

test('a changed number, a deleted line and a reordered case all fail', () => {
  assert.equal(checkAdditive(OLD, OLD.replace('{"n":2}', '{"n":2.000000000001}')).problems.length, 1);
  assert.equal(checkAdditive(OLD, OLD.replace('    {"n":1},\n', '')).problems.length, 1);
  assert.equal(checkAdditive(OLD, OLD.replace('    {"n":1},\n    {"n":2}', '    {"n":2},\n    {"n":1}')).problems.length, 1);
});

test('a new version that is not valid JSON fails', () => {
  assert.match(checkAdditive(OLD, withLines(6, '  "broken": ,')).problems[0], /not valid JSON/);
});

test('a reworded case in a link fixture fails, as in the base from before G2-0b', () => {
  const was = '{\n  "frames": [\n    {"name": "a decline: busy: one transfer per peer", "n": 3},\n    {"name": "a cancel", "n": 6}\n  ]\n}\n';
  const now = was.replace('busy: one transfer per peer', 'busy: this machine already has a transfer running');
  assert.equal(checkAdditive(was, now).problems.length, 1);
  assert.deepEqual(checkAdditive(was, was.replace('"n": 6}', '"n": 6},\n    {"name": "a new case", "n": 7}')).problems, []);
});

test('the link fixtures are compared only against a base that has G2-0b', () => {
  assert.equal(linkDirApplies(() => true), true);
  assert.equal(linkDirApplies(() => false), false);
  const asked = [];
  linkDirApplies((c) => { asked.push(c); return true; });
  assert.deepEqual(asked, ['d2b23670']);
});
