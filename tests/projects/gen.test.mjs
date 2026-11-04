import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const GEN = fileURLToPath(new URL('../../scripts/gen-projects-fixtures.mjs', import.meta.url));
const FIXTURES = fileURLToPath(new URL('../fixtures/projects/', import.meta.url));
const gen = await import(GEN);

test('--out with no value is a usage error, exit 2', () => {
  const r = spawnSync(process.execPath, [GEN, '--out'], { encoding: 'utf8' });
  assert.equal(r.status, 2);
  assert.match(r.stderr, /usage/);
});
test('the fixtures on disk are exactly what the generator writes, and no other .json is there', () => {
  assert.deepEqual(gen.problemsOf(gen.build(), FIXTURES), []);
});
test('problemsOf: a stray .json file, a missing or different file, and fewer than MIN_FILES files', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'p0-gen-'));
  try {
    const files = gen.build();
    for (const [name, text] of Object.entries(files)) fs.writeFileSync(path.join(dir, name), text);
    assert.deepEqual(gen.problemsOf(files, dir), []);
    fs.writeFileSync(path.join(dir, 'stray.json'), '{}');
    assert.deepEqual(gen.problemsOf(files, dir), ['stray.json is not written by the generator']);
    fs.unlinkSync(path.join(dir, 'stray.json'));
    fs.writeFileSync(path.join(dir, 'state-cases.json'), 'x');
    assert.deepEqual(gen.problemsOf(files, dir), ['state-cases.json differs from what the core writes']);
    fs.unlinkSync(path.join(dir, 'state-cases.json'));
    assert.deepEqual(gen.problemsOf(files, dir), ['state-cases.json is missing']);
    assert.equal(gen.MIN_FILES, 8);
    assert.match(gen.problemsOf({}, dir)[0], /fewer than 8/);
    assert.match(gen.problemsOf({ 'a.json': '1' }, dir).join('\n'), /fewer than 8/);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
