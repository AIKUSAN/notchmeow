import test from 'node:test';
import assert from 'node:assert/strict';
import { fix, format, compare, finish, TOLERANCE } from '../../scripts/gen-cat-fixtures.mjs';

test('fix keeps 12 significant digits and snaps libm noise to zero', () => {
  assert.equal(fix(0.1 + 0.2), 0.3);
  assert.equal(fix(Math.sin(Math.PI)), 0);
  assert.equal(fix(-0), 0);
  assert.ok(Object.is(fix(-1e-15), 0), 'a tiny negative becomes +0');
  assert.equal(fix(1234.5678901234567), 1234.56789012);
  assert.deepEqual(fix({ a: [1 / 3, 'x', null, true], b: { c: 2 / 3 } }), { a: [0.333333333333, 'x', null, true], b: { c: 0.666666666667 } });
  assert.throws(() => fix({ x: NaN }), /non-finite/);
  assert.throws(() => fix([Infinity]), /non-finite/);
});

test('format writes one case per line for arrays of objects and one entry per line for maps of objects', () => {
  const text = format({ version: 1, tags: ['a', 'b'], cases: [{ n: 1 }, { n: 2 }], cats: { x: { v: 1 }, y: { v: 2 } } });
  assert.equal(text, [
    '{',
    '  "version": 1,',
    '  "tags": ["a","b"],',
    '  "cases": [',
    '    {"n":1},',
    '    {"n":2}',
    '  ],',
    '  "cats": {',
    '    "x": {"v":1},',
    '    "y": {"v":2}',
    '  }',
    '}',
    ''
  ].join('\n'));
  assert.deepEqual(JSON.parse(text), { version: 1, tags: ['a', 'b'], cases: [{ n: 1 }, { n: 2 }], cats: { x: { v: 1 }, y: { v: 2 } } });
});

test('compare allows 1e-9 on numbers and nothing on structure, strings or key sets', () => {
  assert.equal(TOLERANCE, 1e-9);
  assert.deepEqual(compare({ a: [1, 2], s: 'x' }, { a: [1 + 5e-10, 2 - 5e-10], s: 'x' }), []);
  assert.equal(compare({ a: 1 }, { a: 1 + 2e-9 }).length, 1);
  assert.equal(compare({ a: [1, 2] }, { a: [1] }).length, 1);
  assert.equal(compare({ a: 1 }, { a: 1, b: 2 }).length, 1);
  assert.equal(compare({ s: 'x' }, { s: 'y' }).length, 1);
  assert.equal(compare({ a: null }, { a: 0 }).length, 1);
  assert.match(compare({ a: { b: [0, 1] } }, { a: { b: [0, 2] } })[0], /\$\.a\.b\[1\]/);
});

test('finish puts the version first, then the tolerance apps compare with', () => {
  assert.deepEqual(Object.keys(finish({ cases: [], version: 1, note: 'x' })), ['version', 'tolerance', 'cases', 'note']);
  assert.equal(finish({ version: 1 }).tolerance, 1e-9);
});
