import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
test('the tables print and name the numbers', () => {
  const out = execFileSync(process.execPath, [fileURLToPath(new URL('../../scripts/print-companion-tables.mjs', import.meta.url))], { encoding: 'utf8' });
  for (const h of ['== 1. The numbers', '== 2. A memory file', '== 3. The system prompt', '== 4. Right now', '== 5. The daily recap', '== 6. Quick actions', '== 7. What a note may not hold']) assert.ok(out.includes(h), h);
  for (const s of ['200 notes', '4000 tokens', '14 days', '600', '50 conversations', 'Remember this?', 'Still open:', 'Settings → AI and chat → Companion', 'Waiting in Ghostty', 'another agent than Claude Code']) assert.ok(out.includes(s), s);
  assert.doesNotMatch(out, /\/Users\//);
});
