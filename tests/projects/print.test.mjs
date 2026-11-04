import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
test('the tables print and name the numbers', () => {
  const out = execFileSync(process.execPath, [fileURLToPath(new URL('../../scripts/print-projects-tables.mjs', import.meta.url))], { encoding: 'utf8' });
  for (const h of ['== 1. The numbers', '== 2. A session as it ages', '== 3. Sample timelines', '== 4. A project\'s cat']) assert.ok(out.includes(h), h);
  for (const s of ['10 min', '30 min', '2 h', '5.2 s', '120 s', '130 s', 'Waiting in Claude App', 'main · 2', 'p0-plan', 'Home']) assert.ok(out.includes(s), s);
  assert.doesNotMatch(out, /\/Users\//);
});
