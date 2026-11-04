import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const IDS = core.CAT_IDS;
const deepFreeze = v => { if (v && typeof v === 'object') { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };
/** A seeded rand that counts its calls. */
const counted = seed => { const r = core.rng(seed), f = () => { f.n++; return r(); }; f.n = 0; return f; };
const fixed = v => { const f = () => { f.n++; return v; }; f.n = 0; return f; };
const noRand = () => { throw new Error('rand() must not be called here'); };
/** The rule written out the long way, from the spec, to check agentCatFor against: a free coat at random, else the least-used, ties in CAT_IDS order. */
function reference(taken, rand, avoid = null) {
  const pool = IDS.filter(c => c !== avoid), uses = c => taken.filter(t => t === c).length, free = pool.filter(c => uses(c) === 0);
  if (free.length) return free[Math.floor(rand() * free.length)];
  const least = Math.min(...pool.map(uses));
  return pool.find(c => uses(c) === least);
}
const OTHER = IDS.slice(2); // ginger ... noodle: the 14 coats that are neither Claude Code's nor Codex's default

test('Claude Code is Shrimpy and Codex is Momo, with no random number and nothing to store', () => {
  for (const [pill, cat] of [['integration_claude', 'shrimpy'], ['agent_codex', 'momo']]) {
    const out = core.agentCatFor(pill, {}, 'ginger', noRand);
    assert.deepEqual(out, { cat, agentCats: {}, assigned: false }, pill);
    assert.equal(core.defaultAgentCat(pill), cat);
  }
});

test('a stored coat wins over the default, with no random number and nothing new to store', () => {
  const map = { integration_claude: 'oreo', agent_codex: 'blue', agent_gemini: 'latte' };
  for (const [pill, cat] of [['integration_claude', 'oreo'], ['agent_codex', 'blue'], ['agent_gemini', 'latte']]) assert.deepEqual(core.agentCatFor(pill, map, 'momo', noRand), { cat, agentCats: map, assigned: false }, pill);
});

test('a pill that is not an agent gets the Main cat and is never stored, nor is an ID that is not a pill ID', () => {
  for (const pill of ['integration_stripe', 'integration_music', 'ai_openai', 'agent_', 'agent', 'Agent_x', '__proto__', 'constructor', '', null, undefined, 7, {}, ['agent_x']]) {
    assert.deepEqual(core.agentCatFor(pill, { agent_y: 'momo' }, 'cloud', noRand), { cat: 'cloud', agentCats: { agent_y: 'momo' }, assigned: false }, String(pill));
  }
  assert.equal(core.agentCatFor('integration_stripe', {}, 'tiger', noRand).cat, 'shrimpy', 'a Main cat that is not a cat ID is Shrimpy');
});

test('a new agent gets a coat that no other agent and not the Main cat uses, keeps it, and is not given another one', () => {
  for (let seed = 1; seed <= 200; seed++) {
    const rand = counted(seed), map = { agent_a: 'blue', agent_b: 'ginger' };
    const out = core.agentCatFor('agent_new', map, 'cloud', rand);
    assert.ok(!['shrimpy', 'momo', 'blue', 'ginger', 'cloud'].includes(out.cat), `${seed}: ${out.cat}`);
    assert.equal(out.assigned, true);
    assert.equal(rand.n, 1, 'one random number');
    assert.deepEqual(out.agentCats, { agent_a: 'blue', agent_b: 'ginger', agent_new: out.cat });
    assert.deepEqual(core.agentCatFor('agent_new', out.agentCats, 'cloud', noRand), { cat: out.cat, agentCats: out.agentCats, assigned: false }, 'the second time it only reads');
    assert.deepEqual(map, { agent_a: 'blue', agent_b: 'ginger' }, 'the input is not changed');
  }
});

test('the random choice is repeatable and uses the whole range of free coats: the first free one at 0, the last at just under 1', () => {
  assert.equal(core.agentCatFor('agent_x', {}, 'shrimpy', fixed(0)).cat, 'ginger', 'Shrimpy and Momo are taken by the defaults, so the first free coat is Ginger');
  assert.equal(core.agentCatFor('agent_x', {}, 'shrimpy', fixed(0.9999999)).cat, 'noodle');
  assert.equal(core.agentCatFor('agent_x', {}, 'ginger', fixed(0)).cat, 'midnight', 'the Main cat is taken too');
  assert.equal(core.agentCatFor('agent_x', {}, 'noodle', fixed(0.9999999)).cat, 'puff');
  for (const seed of [1, 7, 13, 2026]) assert.equal(core.agentCatFor('agent_x', {}, 'momo', core.rng(seed)).cat, core.agentCatFor('agent_x', {}, 'momo', core.rng(seed)).cat);
  const seen = new Set();
  for (let seed = 1; seed <= 400; seed++) seen.add(core.agentCatFor('agent_x', {}, 'shrimpy', core.rng(seed)).cat);
  assert.deepEqual([...seen].sort(), [...OTHER].sort(), 'every one of the 14 free coats comes up');
});

test('a default coat that a stored coat has replaced is free again', () => {
  const map = { integration_claude: 'oreo', agent_codex: 'ginger' };
  assert.equal(core.agentCatFor('agent_x', map, 'midnight', fixed(0)).cat, 'shrimpy');
  assert.equal(core.agentCatFor('agent_x', { ...map, agent_y: 'shrimpy' }, 'midnight', fixed(0)).cat, 'momo');
  assert.equal(core.agentCatFor('agent_x', {}, 'midnight', fixed(0)).cat, 'ginger', 'with both defaults in force, they are taken');
});

test('when all 16 coats are taken, the least-used one is chosen, ties in CAT_IDS order, and no random number is drawn', () => {
  const agents = coats => Object.fromEntries(coats.map((c, i) => ['agent_a' + String(i).padStart(2, '0'), c]));
  // Shrimpy and Momo by the defaults, the other 14 by agents (13 of them) and the Main cat (the 14th): every coat once.
  const once = agents(OTHER.slice(0, 13));
  let rand = counted(5);
  assert.deepEqual(core.agentCatFor('agent_new', once, 'noodle', rand), { cat: 'shrimpy', agentCats: { ...once, agent_new: 'shrimpy' }, assigned: true });
  assert.equal(rand.n, 0);
  // Shrimpy is also the Main cat: it is used twice, so the first coat used once is Momo.
  const fourteen = agents(OTHER);
  assert.equal(core.agentCatFor('agent_new', fourteen, 'shrimpy', noRand).cat, 'momo');
  // Every coat but Leo is used at least twice: Leo is the least used.
  const dup = { ...fourteen, ...Object.fromEntries(IDS.filter(c => c !== 'leo').map(c => ['agent_d_' + c, c])) };
  assert.equal(core.agentCatFor('agent_new', dup, 'shrimpy', noRand).cat, 'leo');
  // A coat used once where the rest are used twice or more wins whatever its place.
  assert.equal(core.agentCatFor('agent_new', { ...dup, agent_leo2: 'leo' }, 'shrimpy', noRand).cat, 'momo', 'Leo is now used twice, Momo (default and the duplicate) too, but Momo comes first');
});

test('agentCatFor agrees with the rule written the long way, over 2000 random states', () => {
  const r = core.rng(99);
  for (let i = 0; i < 2000; i++) {
    const n = Math.floor(r() * 24), map = {}, pick = () => IDS[Math.floor(r() * 16)];
    for (let k = 0; k < n; k++) map['agent_s' + String(k).padStart(2, '0')] = pick();
    if (r() < .3) map.integration_claude = pick();
    if (r() < .3) map.agent_codex = pick();
    const main = pick(), seed = Math.floor(r() * 1e6), eff = { integration_claude: 'shrimpy', agent_codex: 'momo', ...map };
    const want = reference([...Object.values(eff), main], core.rng(seed)), got = core.agentCatFor('agent_new', map, main, core.rng(seed));
    assert.equal(got.cat, want, JSON.stringify({ map, main, seed }));
  }
});

test('a random source that misbehaves never breaks it: 0 for no function, NaN, a number out of range or text', () => {
  for (const rand of [undefined, null, 'x', 7, () => NaN, () => Infinity, () => -3, () => 2, () => '0.5', () => undefined, () => 1]) {
    const out = core.agentCatFor('agent_x', {}, 'shrimpy', rand);
    assert.ok(OTHER.includes(out.cat), String(rand));
  }
  assert.equal(core.agentCatFor('agent_x', {}, 'shrimpy', () => 1).cat, 'noodle', '1 is held to the last free coat');
  assert.equal(core.agentCatFor('agent_x', {}, 'shrimpy', () => -3).cat, 'ginger');
});

test('hostile maps and Main cats never throw: a map that is not an object, a Main cat that is not a cat', () => {
  for (const map of [null, undefined, 'x', 7, [], ['momo'], { __proto__: null }, JSON.parse('{"__proto__":"momo","constructor":"momo","agent_ok":"tiger"}')]) {
    const out = core.agentCatFor('agent_x', map, undefined, fixed(0));
    assert.ok(IDS.includes(out.cat) && out.assigned === true);
    assert.deepEqual(Object.keys(out.agentCats), ['agent_x']);
  }
  assert.doesNotThrow(() => core.agentCatFor('agent_x', deepFreeze({ agent_y: 'momo' }), 'momo', fixed(0)));
  assert.equal({}.agent_x, undefined);
});

test('the dice: a new random coat, never the current one, always stored, and the rest of the rule is the same', () => {
  for (let seed = 1; seed <= 200; seed++) {
    const rand = counted(seed), map = { agent_a: 'blue', agent_b: 'snow' }, out = core.rerollAgentCat('agent_a', map, 'cloud', rand);
    assert.ok(out.cat !== 'blue' && !['shrimpy', 'momo', 'snow', 'cloud'].includes(out.cat), `${seed}: ${out.cat}`);
    assert.deepEqual(out.agentCats, { agent_a: out.cat, agent_b: 'snow' });
    assert.equal(rand.n, 1);
  }
  const claude = core.rerollAgentCat('integration_claude', {}, 'cloud', fixed(0));
  assert.deepEqual(claude, { cat: 'ginger', agentCats: { integration_claude: 'ginger' } }, 'Claude Code: not Shrimpy again, and Momo (Codex) and Cloud (Main) are taken');
  assert.equal(core.rerollAgentCat('agent_new', {}, 'cloud', fixed(0)).cat, 'ginger', 'an agent with no coat yet: the same as agentCatFor');
  assert.deepEqual(core.rerollAgentCat('integration_stripe', { agent_y: 'momo' }, 'cloud', noRand), { cat: 'cloud', agentCats: { agent_y: 'momo' } });
  // All 16 taken: the least-used coat that is not the current one.
  const once = Object.fromEntries(OTHER.slice(0, 13).map((c, i) => ['agent_a' + String(i).padStart(2, '0'), c]));
  assert.equal(core.rerollAgentCat('agent_a00', once, 'noodle', noRand).cat, 'shrimpy', 'Ginger (its own) is set aside; every other coat is used once; the first is Shrimpy');
  assert.equal(core.rerollAgentCat('integration_claude', once, 'noodle', noRand).cat, 'momo', 'Claude Code is Shrimpy: set aside, and Momo is the first of the rest');
});

test('assignAgentCats gives every agent in the list a coat, in order, and skips integrations and repeats', () => {
  const pills = ['agent_codex', 'agent_gemini', 'integration_stripe', 'agent_cursor', 'agent_gemini', 'integration_claude', 'ai_openai', 'Bad Id', 'agent_gemini'];
  const out = core.assignAgentCats(pills, {}, 'cloud', core.rng(3));
  assert.deepEqual(Object.keys(out), ['agent_cursor', 'agent_gemini'], 'the defaults are not stored, integrations and bad IDs are skipped');
  const [a, b] = [out.agent_gemini, out.agent_cursor];
  assert.ok(a !== b && ![a, b].some(c => ['shrimpy', 'momo', 'cloud'].includes(c)));
  assert.deepEqual(core.assignAgentCats(pills, {}, 'cloud', core.rng(3)), out, 'repeatable');
  assert.deepEqual(core.assignAgentCats(pills, out, 'cloud', noRand), out, 'a second pass changes nothing and draws nothing');
  assert.deepEqual(core.assignAgentCats(null, { agent_x: 'momo' }, 'cloud', noRand), { agent_x: 'momo' });
  const many = Array.from({ length: 20 }, (_, i) => 'agent_m' + String(i).padStart(2, '0')), all = core.assignAgentCats(many, {}, 'shrimpy', core.rng(8));
  assert.equal(Object.keys(all).length, 20);
  const uses = c => Object.values(all).filter(x => x === c).length + (c === 'shrimpy' ? 2 : 0) + (c === 'momo' ? 1 : 0);
  assert.ok(Math.max(...IDS.map(uses)) - Math.min(...IDS.map(uses)) <= 1, 'after the free coats are gone the least-used are chosen, so the coats stay evenly used');
});

test('"Reset to defaults" is assignAgentCats with an empty map: the defaults are back, the others are chosen again', () => {
  const before = { integration_claude: 'oreo', agent_codex: 'blue', agent_gemini: 'latte' };
  const after = core.assignAgentCats(['integration_claude', 'agent_codex', 'agent_gemini'], {}, 'shrimpy', core.rng(4));
  assert.deepEqual(Object.keys(after), ['agent_gemini']);
  assert.ok(!['shrimpy', 'momo'].includes(after.agent_gemini));
  assert.notDeepEqual(after, before);
});

test('hostile values never throw: 3000 random calls give a valid coat and a clean map', () => {
  const r = core.rng(31337), pool = ['agent_a', 'agent_b', 'agent_codex', 'integration_claude', 'integration_stripe', 'ai_openai', 'Bad', '__proto__', 'constructor', '', null, 7, 'agent_', 'agent_x'];
  for (let i = 0; i < 3000; i++) {
    const map = Object.fromEntries(Array.from({ length: Math.floor(r() * 8) }, () => [pool[Math.floor(r() * pool.length)], r() < .7 ? IDS[Math.floor(r() * 16)] : pool[Math.floor(r() * pool.length)]]).filter(([k]) => typeof k === 'string'));
    const pill = pool[Math.floor(r() * pool.length)], main = r() < .8 ? IDS[Math.floor(r() * 16)] : pool[Math.floor(r() * pool.length)];
    for (const fn of [core.agentCatFor, core.rerollAgentCat]) {
      const out = fn(pill, map, main, core.rng(i));
      assert.ok(IDS.includes(out.cat), JSON.stringify({ pill, map, main }));
      assert.deepEqual(core.cleanAgentCats(out.agentCats), out.agentCats);
    }
    assert.deepEqual(core.cleanAgentCats(core.assignAgentCats([pill, 'agent_x', pill], map, main, core.rng(i))), core.assignAgentCats([pill, 'agent_x', pill], map, main, core.rng(i)));
  }
});

const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/agent-cat-cases.json', import.meta.url), 'utf8'));
const roundTrip = v => JSON.parse(JSON.stringify(v));
/** The random source of a row: {seed} is rng(seed), {values} those numbers in order and then 0, {none} must never be called. */
const source = spec => {
  const seeded = spec.seed !== undefined ? core.rng(spec.seed) : null;
  const f = () => { f.draws++; if (seeded) return seeded(); if (spec.values) return f.draws <= spec.values.length ? spec.values[f.draws - 1] : 0; throw new Error('rand() must not be called'); };
  f.draws = 0;
  return f;
};

test('agent-cat-cases.json: the cat IDs and the default coats are the core\'s', () => {
  assert.deepEqual(fx.ids, IDS);
  assert.deepEqual(fx.defaults, core.DEFAULT_AGENT_CATS);
});

test('agent-cat-cases.json: every case replays from its own input, with the same number of random draws', () => {
  for (const c of fx.cases) { const r = source(c.rand); assert.deepEqual(compare(roundTrip(core.agentCatFor(c.pill, c.agentCats, c.mainCat, r)), c.out), [], c.name); assert.equal(r.draws, c.draws, c.name); }
  for (const c of fx.rerolls) { const r = source(c.rand); assert.deepEqual(compare(roundTrip(core.rerollAgentCat(c.pill, c.agentCats, c.mainCat, r)), c.out), [], c.name); assert.equal(r.draws, c.draws, c.name); }
  for (const c of fx.assigns) { const r = source(c.rand); assert.deepEqual(compare(roundTrip({ agentCats: core.assignAgentCats(c.pills, c.agentCats, c.mainCat, r) }), c.out), [], c.name); assert.equal(r.draws, c.draws, c.name); }
});

test('agent-cat-cases.json: the inputs the spec worries about are in it (the defaults, the 16-taken tie rule, a stored coat, hostile maps and pills)', () => {
  const names = fx.cases.map(c => c.name);
  for (const n of ['Claude Code is Shrimpy', 'Codex is Momo', 'a stored coat wins over the default', 'an integration gets the Main cat', 'a prototype name gets the Main cat', 'all 16 taken once: the first, Shrimpy', 'all 16 taken, Leo least used', 'a map that is not an object', 'a map with prototype names']) assert.ok(names.includes(n), n);
  assert.ok(fx.cases.filter(c => c.rand.seed !== undefined).length >= 5, 'seeded cases');
  assert.ok(fx.cases.filter(c => c.draws === 0).length >= 15 && fx.cases.filter(c => c.draws === 1).length >= 10, 'rows with and without a draw');
  assert.equal(fx.cases.find(c => c.name === 'all 16 taken, Leo least used').out.cat, 'leo');
  assert.ok(fx.rerolls.every(r => r.out.cat !== (r.agentCats[r.pill] || core.defaultAgentCat(r.pill)) || !core.isAgentPill(r.pill)), 'the dice never gives the same coat back');
});
