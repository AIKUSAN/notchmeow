import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

test('the owner\'s tables print, with every heading, and write nothing', () => {
  const out = execFileSync(process.execPath, ['scripts/print-sidekick-tables.mjs'], { encoding: 'utf8' });
  for (const h of ['1. Risk rules', '2. Stuck rules', '3. Recap', '4. "What\'s Claude doing?"', '5. When a note may show']) assert.ok(out.includes(h), h);
  for (const id of ['rm_recursive', 'sudo', 'git_force_push', 'sensitive_file', 'unknown_tool', 'edit_in_project']) assert.ok(out.includes(id), id);
  assert.ok(out.includes('While you were away, Claude Code in proj ran 12 steps, edited a.js, b.js and c.js, and finished.'));
  assert.ok(out.includes('Claude Code is still waiting for your OK.'));
  assert.ok(!out.includes('NaN'), 'no timer or time may print as NaN');
});
