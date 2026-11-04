import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const IDS = core.CAT_IDS;
const cast = core.castOf;
const T = (id, state = 'idle', last = 0) => ({ id, state, last });
const deepFreeze = v => { if (v && typeof v === 'object') { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };
/** The island as the apps order it: Claude Code, then the agents, then the integrations. */
const ISLAND = [T('integration_claude', 'working', 100), T('agent_codex', 'approval', 90), T('agent_gemini', 'thinking', 80), T('agent_antigravity', 'idle', 10), T('integration_stripe', 'idle', 5), T('integration_music', 'idle', 1)];
const IN = (o = {}) => ({ tasks: ISLAND, focusId: 'integration_claude', mainCat: 'ginger', pair: ['latte', 'cloud'], agentCats: { agent_gemini: 'oreo', agent_antigravity: 'leo' }, ...o });
const catsOf = c => c.pills.map(p => `${p.pill}:${p.cat}`);

test('the cast has the same shape in every mode', () => {
  for (const mode of core.DISPLAY_MODES) {
    const c = cast(mode, IN());
    assert.deepEqual(Object.keys(c), ['mode', 'big', 'second', 'pills', 'drop', 'greeting']);
    assert.equal(c.mode, mode);
    assert.deepEqual(Object.keys(c.big), ['pill', 'cat']);
    assert.deepEqual(Object.keys(c.greeting), ['cat', 'pair', 'sessions']);
    assert.equal(c.greeting.sessions.length, 4);
  }
  assert.equal(core.PILL_ROW, 4);
});

test('One cat: the Main cat in every place, nothing in the second spot, the pills as today', () => {
  const c = cast('one', IN());
  assert.deepEqual(c.big, { pill: 'integration_claude', cat: 'ginger' });
  assert.equal(c.second, null);
  assert.deepEqual(catsOf(c), ['agent_codex:ginger', 'agent_gemini:ginger', 'agent_antigravity:ginger', 'integration_stripe:ginger'], 'the tasks other than the focus, the first four, in the app\'s order');
  assert.equal(c.drop, 'ginger');
  assert.deepEqual(c.greeting, { cat: 'ginger', pair: null, sessions: ['ginger', 'ginger', 'ginger', 'ginger'] });
  assert.deepEqual(cast('one', IN({ focusId: 'agent_gemini' })).big, { pill: 'agent_gemini', cat: 'ginger' }, 'whoever is focused, it is the Main cat');
});

test('A cat for each agent: the focused agent\'s own cat, every agent pill in its own, integrations and the empty focus in the Main cat', () => {
  const c = cast('perAgent', IN({ focusId: 'agent_gemini' }));
  assert.deepEqual(c.big, { pill: 'agent_gemini', cat: 'oreo' });
  assert.equal(c.second, null);
  assert.deepEqual(catsOf(c), ['integration_claude:shrimpy', 'agent_codex:momo', 'agent_antigravity:leo', 'integration_stripe:ginger'], 'Claude Code and Codex by default, a stored coat for the rest, the Main cat for Stripe');
  assert.equal(c.drop, 'oreo');
  assert.deepEqual(c.greeting, { cat: 'ginger', pair: null, sessions: ['shrimpy', 'momo', 'leo', 'ginger'] });
  assert.deepEqual(cast('perAgent', IN()).big, { pill: 'integration_claude', cat: 'shrimpy' });
  assert.deepEqual(cast('perAgent', IN({ focusId: 'integration_stripe' })).big, { pill: 'integration_stripe', cat: 'ginger' }, 'an integration in focus: the Main cat');
  assert.deepEqual(cast('perAgent', IN({ focusId: null })).big, { pill: null, cat: 'ginger' }, 'nothing in focus: the Main cat');
  assert.equal(cast('perAgent', IN({ focusId: 'agent_codex', agentCats: { agent_codex: 'blue' } })).big.cat, 'blue', 'a stored coat beats the default');
  assert.equal(cast('perAgent', IN({ focusId: 'agent_unseen' })).big.cat, 'ginger', 'an agent with no coat yet wears the Main cat until it is given one');
});

test('Two cats: the pair, with the focused pill on cat 1 and the busiest other agent on cat 2, who leaves the row', () => {
  const c = cast('two', IN());
  assert.deepEqual(c.big, { pill: 'integration_claude', cat: 'latte' });
  assert.deepEqual(c.second, { pill: 'agent_codex', cat: 'cloud' }, 'Codex waits for approval');
  assert.deepEqual(catsOf(c), ['agent_gemini:ginger', 'agent_antigravity:ginger', 'integration_stripe:ginger', 'integration_music:ginger'], 'Codex has left the row; every pill wears the Main cat');
  assert.equal(c.drop, 'latte');
  assert.deepEqual(c.greeting, { cat: 'ginger', pair: ['latte', 'cloud'], sessions: ['ginger', 'ginger', 'ginger', 'ginger'] });
  assert.deepEqual(cast('two', IN({ focusId: 'integration_stripe' })).big, { pill: 'integration_stripe', cat: 'latte' }, 'cat 1 shows whatever is focused');
  assert.deepEqual(cast('two', IN({ focusId: null })).big, { pill: null, cat: 'latte' });
  assert.equal(cast('two', IN({ pair: ['momo', 'momo'] })).second.cat, 'ginger', 'the same coat twice: cat 2 is the next one');
  assert.deepEqual(cast('two', IN({ pair: 'junk' })).big.cat, 'shrimpy', 'a bad pair is Shrimpy and Momo');
});

test('the busiest other agent: waiting for you, then an error, then busy, then the most recent event; the focused pill and integrations never count', () => {
  const pick = (tasks, focusId = 'integration_claude') => cast('two', { tasks, focusId }).second.pill;
  const C = T('integration_claude', 'idle', 0);
  assert.equal(pick([C, T('agent_a', 'working', 50), T('agent_b', 'approval', 1)]), 'agent_b', 'a waiting approval beats a busy agent, however old');
  assert.equal(pick([C, T('agent_a', 'error', 50), T('agent_b', 'approval', 1)]), 'agent_b', 'approval beats error');
  assert.equal(pick([C, T('agent_a', 'question', 5), T('agent_b', 'approval', 1)]), 'agent_a', 'a question and an approval are the same rank: the most recent');
  assert.equal(pick([C, T('agent_a', 'working', 50), T('agent_b', 'error', 1)]), 'agent_b', 'error beats busy');
  assert.equal(pick([C, T('agent_a', 'idle', 90), T('agent_b', 'working', 1)]), 'agent_b', 'busy beats idle, however recent');
  assert.equal(pick([C, T('agent_a', 'thinking', 5), T('agent_b', 'searching', 9), T('agent_c', 'working', 7)]), 'agent_b', 'working, thinking and searching are one rank: the most recent');
  assert.equal(pick([C, T('agent_a', 'finished', 5), T('agent_b', 'idle', 9), T('agent_c', 'sleeping', 7)]), 'agent_b', 'the rest by the most recent event');
  assert.equal(pick([C, T('agent_a', 'working', 5), T('agent_b', 'working', 5)]), 'agent_a', 'a tie goes to the first in the app\'s order');
  assert.equal(pick([C, T('agent_a', 'ratelimit', 5), T('agent_b', 'dizzy', 5)]), 'agent_a');
  assert.equal(pick([C, T('integration_stripe', 'approval', 99), T('agent_a', 'idle', 0)]), 'agent_a', 'an integration is never the second cat');
  assert.equal(pick([T('integration_claude', 'working', 1), T('agent_a', 'idle', 0)], 'agent_a'), 'integration_claude', 'Claude Code is an agent, so it can be the second cat when another agent is focused');
  assert.equal(pick([T('agent_a', 'approval', 99), T('integration_stripe', 'error', 5)], 'agent_a'), null, 'the focused agent is never its own second cat, and an integration is not an agent');
  assert.equal(pick([C, T('agent_a', 'bogus', 99), T('agent_b', 'idle', 1)]), 'agent_a', 'an unknown state is idle, and 99 is the most recent');
  assert.equal(pick([C, { id: 'agent_a', state: 'idle' }, T('agent_b', 'idle', 1)]), 'agent_b', 'a missing time is 0');
  assert.equal(pick([C, T('agent_a', 'idle', 5)]), 'agent_a', 'an idle agent, when it is the only one, is shown idle: it is not skipped');
});

test('with no other agent, cat 2 idles with no pill; Claude Code alone is the focused agent', () => {
  assert.deepEqual(cast('two', { tasks: [T('integration_claude', 'working')], focusId: 'integration_claude' }).second, { pill: null, cat: 'momo' });
  assert.deepEqual(cast('two', { tasks: [T('integration_stripe', 'approval'), T('ai_openai', 'error')], focusId: null }).second, { pill: null, cat: 'momo' });
  assert.deepEqual(cast('two', { tasks: [], focusId: null }).second, { pill: null, cat: 'momo' });
});

test('the row and the grid: the first four tasks other than the focus (and in Two cats mode the second cat), in order, each once', () => {
  const many = [T('integration_claude'), ...Array.from({ length: 8 }, (_, i) => T('agent_s' + i)), T('integration_stripe')];
  assert.deepEqual(cast('one', { tasks: many, focusId: 'agent_s2' }).pills.map(p => p.pill), ['integration_claude', 'agent_s0', 'agent_s1', 'agent_s3']);
  assert.deepEqual(cast('two', { tasks: many, focusId: 'integration_claude' }).pills.map(p => p.pill), ['agent_s1', 'agent_s2', 'agent_s3', 'agent_s4'], 'agent_s0 is the second cat (all idle, same time: the first)');
  assert.equal(cast('one', { tasks: many, focusId: 'integration_claude' }).pills.length, 4);
  assert.deepEqual(cast('one', { tasks: [T('agent_a'), T('agent_a'), T('agent_b')], focusId: null }).pills.map(p => p.pill), ['agent_a', 'agent_b'], 'a pill listed twice counts once');
  assert.deepEqual(cast('one', { tasks: [T('agent_a')], focusId: 'agent_a' }).pills, [], 'the focused pill is not in the row');
  assert.deepEqual(cast('one', { tasks: [T('agent_a')], focusId: 'agent_not_listed' }).pills.map(p => p.pill), ['agent_a'], 'a focus that is not in the list takes nothing from it');
});

test('the greeting: the Main cat falls in, the pair comes with it in Two cats mode, and the four session cats are the row\'s cats in the grid\'s cell order', () => {
  assert.deepEqual(cast('perAgent', IN({ focusId: 'integration_claude' })).greeting.sessions, ['momo', 'oreo', 'leo', 'ginger'], 'Codex, Gemini CLI, Antigravity, Stripe: what the grid shows after the hand-over');
  const two = cast('perAgent', { tasks: [T('integration_claude'), T('agent_codex')], focusId: 'integration_claude', mainCat: 'blue' });
  assert.deepEqual(two.greeting.sessions, ['momo', 'blue', 'blue', 'blue'], 'a cell with no pill is the Main cat');
  assert.equal(cast('two', IN({ mainCat: 'blue' })).greeting.cat, 'blue');
  assert.equal(cast('one', IN()).greeting.pair, null);
});

test('hostile input never throws: no tasks, tasks that are not tasks, bad IDs and states, a mode or a pair or a map that is not valid', () => {
  assert.deepEqual(cast('bogus', IN()), cast('one', IN()), 'an unknown mode is One cat');
  for (const mode of [undefined, null, 7, {}, 'Two', 'perAgent ']) assert.equal(cast(mode, IN()).mode, 'one', String(mode));
  for (const input of [undefined, null, 7, 'x', [], {}, { tasks: 'x' }, { tasks: null }, { tasks: [null, 7, 'x', [], {}, { id: 7 }, { id: '__proto__' }, { id: 'Bad Id' }, { id: 'constructor' }] }]) {
    for (const mode of core.DISPLAY_MODES) {
      const c = cast(mode, input);
      assert.equal(c.pills.length, 0);
      assert.equal(c.big.pill, null);
      assert.ok(IDS.includes(c.big.cat) && IDS.includes(c.greeting.cat));
    }
  }
  const c = cast('two', { tasks: [T('agent_a', 'working', NaN), { id: 'agent_b', state: 'approval', last: 'now' }, { id: 'agent_c', state: 7, last: Infinity }], focusId: 7, mainCat: 'tiger', pair: [1, 2], agentCats: 'x' });
  assert.deepEqual(c.big, { pill: null, cat: 'shrimpy' });
  assert.equal(c.second.pill, 'agent_b', 'a time that is not a number is 0, a state that is not one is idle');
  assert.equal(c.greeting.cat, 'shrimpy');
  assert.doesNotThrow(() => cast('perAgent', deepFreeze(IN())));
  assert.deepEqual(cast('two', { tasks: [T('agent_a'), T('agent_b')], focusId: '__proto__' }).big.pill, null);
});

test('a raw settings value is fine: the pair, the map and the Main cat are cleaned the way the settings are', () => {
  const c = cast('two', { tasks: ISLAND, focusId: 'integration_claude', mainCat: 'Momo', pair: '["latte","latte"]', agentCats: { agent_gemini: 'tiger', constructor: 'momo' } });
  assert.deepEqual(c.big, { pill: 'integration_claude', cat: 'latte' });
  assert.equal(c.second.cat, 'patches', 'latte twice: the next coat');
  assert.equal(c.greeting.cat, 'shrimpy');
});

test('500 random islands keep the rules: the second cat ranks first, nothing is shown twice, the row is at most four', () => {
  const r = core.rng(404), states = [...core.STATES, 'bogus'], ids = ['integration_claude', 'agent_codex', 'agent_a', 'agent_b', 'agent_c', 'integration_stripe', 'integration_music', 'ai_openai'];
  const rank = s => ['approval', 'question'].includes(s) ? 0 : s === 'error' ? 1 : ['working', 'thinking', 'searching'].includes(s) ? 2 : 3;
  for (let i = 0; i < 500; i++) {
    const tasks = ids.filter(() => r() < .75).map(id => T(id, states[Math.floor(r() * states.length)], r() < .2 ? 0 : Math.floor(r() * 5))), focusId = r() < .15 ? null : ids[Math.floor(r() * ids.length)];
    const c = cast('two', { tasks, focusId }), others = tasks.filter(t => t.id !== focusId && core.isAgentPill(t.id));
    const st = t => core.STATES.includes(t.state) ? t.state : 'idle';
    const best = others.reduce((b, t) => !b || rank(st(t)) < rank(st(b)) || (rank(st(t)) === rank(st(b)) && t.last > b.last) ? t : b, null);
    assert.equal(c.second.pill, best ? best.id : null, JSON.stringify({ tasks, focusId }));
    const shown = [c.big.pill, c.second.pill, ...c.pills.map(p => p.pill)].filter(Boolean);
    assert.equal(new Set(shown).size, shown.length, 'nothing is shown twice');
    assert.ok(c.pills.length <= 4);
    const one = cast('one', { tasks, focusId });
    assert.ok(one.pills.every(p => p.cat === 'shrimpy') && one.big.cat === 'shrimpy' && one.drop === 'shrimpy');
  }
});

const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/cast-cases.json', import.meta.url), 'utf8'));
const roundTrip = v => JSON.parse(JSON.stringify(v));

test('cast-cases.json: the frozen values are the core\'s, and the ranks of the states', () => {
  assert.deepEqual(fx.ids, IDS);
  assert.deepEqual(fx.modes, core.DISPLAY_MODES);
  assert.equal(fx.pillRow, core.PILL_ROW);
  assert.deepEqual(fx.states, core.STATES);
  for (const r of fx.busyRank) assert.equal(core.busyRank(r.state), r.rank, r.state);
  assert.deepEqual(fx.busyRank.map(r => r.rank), [3, 2, 2, 2, 0, 0, 1, 3, 3, 3, 3, 3], 'idle, working, thinking, searching, approval, question, error, then the rest; an unknown state is last');
});

test('cast-cases.json: every case replays from its own input', () => {
  for (const c of fx.cases) assert.deepEqual(compare(roundTrip(cast(c.mode, c.input)), c.out), [], `${c.name} (${c.mode})`);
});

test('cast-cases.json: every scenario is in every mode, and the rules the spec worries about are in it', () => {
  const names = [...new Set(fx.cases.map(c => c.name))];
  for (const n of ['the island, Claude Code focused', 'the island, nothing focused', 'more pills than the row holds', 'no pills at all', 'a pill listed twice', 'approval beats error', 'an integration is never the second cat', 'the focused agent is never its own second cat', 'pill IDs that are not pill IDs', 'tasks that are not a list', 'nothing']) assert.ok(names.includes(n), n);
  for (const n of names.filter(x => !x.startsWith('the mode '))) assert.deepEqual(fx.cases.filter(c => c.name === n).map(c => c.mode), core.DISPLAY_MODES, n);
  assert.ok(fx.cases.some(c => c.mode === 'two' && c.out.second && c.out.second.pill === 'agent_codex'), 'a second cat');
  assert.ok(fx.cases.some(c => c.mode === 'two' && c.out.second && c.out.second.pill === null), 'a second cat with no agent');
  assert.ok(fx.cases.some(c => c.mode === 'perAgent' && c.out.pills.some(p => p.cat !== c.out.greeting.cat)), 'agent pills in their own cats');
});
