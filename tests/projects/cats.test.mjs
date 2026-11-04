import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const P = require('../../shared/projects-core.js');
const fx = name => JSON.parse(fs.readFileSync(new URL(`../fixtures/projects/${name}`, import.meta.url), 'utf8'));
const Cat = require('../../design/prototype/cat-core.js'), Side = require('../../shared/sidekick-core.js');
const q = fx('claude-only-cases.json'), c = fx('cat-cases.json');
test('claudeOnly replays claude-only-cases.json', () => { for (const x of q.claudeOnly) assert.equal(P.claudeOnly(x.activePills, x.otherAgentSeen), x.expect, x.name); });
test('islandLayout replays claude-only-cases.json', () => { for (const x of q.layout) assert.equal(P.islandLayout(x.current, x.claudeOnly, x.open), x.expect, x.name); });
test('projectCatOf replays cat-cases.json', () => { for (const x of c.cat) assert.deepEqual(P.projectCatOf(x.catKey, x.projectCats, x.mainCat), x.expect, x.name); });
test('cleanProjectCats replays cat-cases.json', () => { for (const x of c.clean) assert.deepEqual(P.cleanProjectCats(x.raw), x.expect, x.name); });
test('cleaning twice is cleaning once', () => { for (const x of c.clean) assert.deepEqual(P.cleanProjectCats(P.cleanProjectCats(x.raw)), x.expect, x.name); });
test('the copies match cat-core.js and sidekick-core.js', () => {
  assert.deepEqual(P.CAT_IDS, Cat.CAT_IDS);
  assert.equal(P.SUBAGENTS_MAX, Cat.KITTEN_MAX);
  const names = ['café', 'Notch Buddy', '', 'x'.repeat(60)]; for (let i = 0; i < 296; i++) names.push('n' + i);
  for (const n of names) {
    assert.equal(P.fnv1a(n), Side.fnv1a(n));
    if (!n) continue;
    for (const main of Cat.CAT_IDS) assert.equal(P.projectCatOf(n, {}, main).cat, Cat.pickCat([main], Cat.rng(parseInt(Side.fnv1a(n), 16)), null), `${n} / ${main}`);
  }
  for (const id of ['integration_claude', 'agent_codex', 'agent_claude-desktop', 'integration_github', 'agent_', 'Agent_X', 'ai_openai', 'agent_gemini-cli', 'constructor'])
    assert.equal(P.claudeOnly([id], false), !(Cat.isAgentPill(id) && id !== 'integration_claude' && id !== 'agent_claude-desktop'), id);
});
test('the view wears the project cat', () => {
  const reg = P.registryApply(P.emptyRegistry(), P.projectEventFrom({ hook_event_name: 'UserPromptSubmit', session_id: 's1', cwd: '/Users/sam/Code/notchmeow' }, 1));
  assert.equal(P.projectsView(reg, 1).projects[0].cat, 'leo');
  assert.equal(P.projectsView(reg, 1, { projectCats: { notchmeow: 'oreo' } }).projects[0].cat, 'oreo');
  assert.equal(P.projectsView(reg, 1, { mainCat: 'leo' }).projects[0].cat, 'cloud');
});
