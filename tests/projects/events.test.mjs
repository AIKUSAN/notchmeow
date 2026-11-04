import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const P = require('../../shared/projects-core.js');
const fx = name => JSON.parse(fs.readFileSync(new URL(`../fixtures/projects/${name}`, import.meta.url), 'utf8'));

const f = fx('event-cases.json');
test('projectEventFrom replays event-cases.json', () => { for (const c of f.cases) assert.deepEqual(P.projectEventFrom(c.payload, c.now, c.waitIn), c.expect, c.name); });
test('an event keeps no prompt, transcript, tool input, message or answer', () => {
  const p = { hook_event_name: 'PermissionRequest', session_id: 's1', cwd: '/Users/sam/Code/notchmeow', prompt: 'MARKER-PROMPT', transcript_path: '/Users/sam/MARKER-TRANSCRIPT.jsonl',
    tool_name: 'Bash', tool_input: { command: 'rm MARKER-CMD' }, tool_response: 'MARKER-OUT', message: 'MARKER-MSG?', last_assistant_message: 'MARKER-ASSIST' };
  const s = JSON.stringify(P.projectEventFrom(p, 1));
  for (const m of ['MARKER-PROMPT', 'MARKER-TRANSCRIPT', 'MARKER-CMD', 'MARKER-OUT', 'MARKER-MSG', 'MARKER-ASSIST']) assert.ok(!s.includes(m), m);
});
test('ids are cut at 128 code points', () => {
  const e = P.projectEventFrom({ hook_event_name: 'Stop', session_id: 'x'.repeat(300), cwd: '/a' }, 1);
  assert.equal(e.sessionId.length, 128);
});
test('never throws', () => { for (const v of [undefined, null, 3, 'x', [], { hook_event_name: 5 }, { hook_event_name: 'Stop', session_id: {} }]) P.projectEventFrom(v, 1); });
