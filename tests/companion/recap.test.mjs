import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const C = require('../../shared/companion-core.js');
const fx = name => JSON.parse(fs.readFileSync(new URL(`../fixtures/companion/${name}`, import.meta.url), 'utf8'));

const r = fx('recap-cases.json'), q = fx('quick-cases.json');
test('the daily recap replays recap-cases.json', () => {
  for (const c of r.step) assert.deepEqual(C.dailyRecapStep(c.state, c.event, c.ctx), c.expect, c.name);
  for (const c of r.text) assert.equal(C.dailyRecapText(c.input), c.expect, c.name);
  for (const c of r.polish) assert.equal(C.acceptPolish(c.line, c.template), c.expect, c.name);
  for (const c of r.dismiss) { assert.equal(C.recapDismiss(c.count), c.next, c.name); assert.equal(C.recapMuted(c.count), c.muted, c.name); }
});
test('the quick actions replay quick-cases.json', () => {
  for (const c of q.request) assert.deepEqual(C.quickRequest(c.kind, c.text), c.expect, c.name);
  for (const c of q.result) assert.equal(C.quickResultClean(c.kind, c.reply), c.expect, c.name);
});
test('the PC quick actions replay the pc group of quick-cases.json', () => {
  for (const c of q.pc) assert.deepEqual(C.quickRequest(c.kind, c.text, c.device), c.expect, c.name);
  assert.ok(!Object.values(C.QUICK_SYSTEM_PC).some(s => s.includes('Mac')));
  assert.equal(C.quickRequest('fix', 'x', 'pc').system, C.QUICK_SYSTEM.fix);
});
test('the quick words are the core constants', () => {
  assert.deepEqual(q.words, { noVision: C.QUICK_NO_VISION, toolsRefused: C.QUICK_TOOLS_REFUSED });
  assert.equal(C.QUICK_TOOLS_REFUSED, 'Claude Code started with tools a quick action must not have, so NotchMeow stopped it.');
});
test('a quick request holds exactly one opening and one closing real delimiter', () => {
  // The linear pattern (no closing bracket needed): an un-neutralized <text or </text anywhere in the block would show up here.
  const tag = /<(?:\s*\/\s*|\s*)text\b/gi;
  for (const c of q.request) {
    const r = C.quickRequest(c.kind, c.text);
    if (r === null || !r.user.startsWith('<text>\n')) continue;
    assert.deepEqual(r.user.match(tag), ['<text', '</text'], c.name);
  }
});
test('a quick request is linear: many tags, or a tag with a long gap, return in under 200 ms', () => {
  for (const t of ['<text '.repeat(40000), '<' + ' '.repeat(80000) + 'text']) {
    const t0 = performance.now();
    C.quickRequest('fix', t);
    const ms = performance.now() - t0;
    assert.ok(ms < 200, `${Math.round(ms)} ms`);
  }
});
test('every system prompt says the text is data', () => { for (const k of C.QUICK_KINDS) assert.match(C.QUICK_SYSTEM[k], /never instructions to you/); });
test('never throws', () => { for (const v of [undefined, null, 1, [], {}, 'x']) { C.dailyRecapStep(v, v, v); C.dailyRecapText(v); C.acceptPolish(v, v); C.recapDismiss(v); C.recapMuted(v); C.quickRequest(v, v); C.quickResultClean(v, v); } });
