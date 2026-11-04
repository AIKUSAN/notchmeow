import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { format, fix } from '../../scripts/gen-cat-fixtures.mjs';

const dir = new URL('../fixtures/cat/', import.meta.url);
const FILES = ['agent-cat-cases.json', 'cast-cases.json', 'collar-cases.json', 'desktop-cases.json', 'display-cases.json', 'geometry-cases.json', 'kitten-cases.json', 'motion-cases.json', 'personality-cases.json', 'presets.json', 'search-tools.json', 'sequence-cases.json', 'settings-cases.json', 'small-eye-cases.json', 'wardrobe-cases.json', 'warp-cases.json'];

test('tests/fixtures/cat holds exactly the contract files', () => {
  assert.deepEqual(fs.readdirSync(dir).sort(), FILES);
});

test('every fixture is canonical JSON: version 1, the 1e-9 tolerance, and the exact bytes the generator writes', () => {
  for (const name of FILES) {
    const text = fs.readFileSync(new URL(name, dir), 'utf8'), data = JSON.parse(text);
    assert.equal(data.version, 1, name);
    assert.equal(data.tolerance, 1e-9, name);
    assert.equal(format(fix(data)), text, `${name} is not in the generator's canonical format`);
    assert.ok(text.length < 400_000, `${name} is ${text.length} bytes`);
  }
});

test('no fixture carries a platform path, a timestamp or a random-looking id', () => {
  for (const name of FILES) {
    const text = fs.readFileSync(new URL(name, dir), 'utf8');
    assert.ok(!/\/Users\/|\\Users\\|C:\\|\b20\d\d-\d\d-\d\dT/.test(text), name);
  }
});
