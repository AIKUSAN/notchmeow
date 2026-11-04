import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const IDS = core.CAT_IDS;
const clean = core.cleanDisplaySettings;
const DEFAULTS = { displayMode: 'one', pair: ['shrimpy', 'momo'], agentCats: {} };
const deepFreeze = v => { if (v && typeof v === 'object') { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };
const NOT_OBJECTS = [null, undefined, 'junk', '', 7, 0, NaN, true, false, [], [1, 2], ['displayMode']];

test('the frozen values: three modes in Settings order, the default pair, the two default agent coats', () => {
  assert.deepEqual(core.DISPLAY_MODES, ['one', 'perAgent', 'two']);
  assert.deepEqual(core.DEFAULT_PAIR, ['shrimpy', 'momo']);
  assert.deepEqual(core.DEFAULT_AGENT_CATS, { integration_claude: 'shrimpy', agent_codex: 'momo' });
  assert.equal(core.MAX_AGENT_CATS, 256);
});

test('the display mode: the three IDs stay, anything else is "one", the case and the type count', () => {
  for (const m of core.DISPLAY_MODES) assert.equal(core.displayModeOf(m), m);
  for (const bad of ['One', 'PERAGENT', 'peragent', 'per_agent', 'per agent', ' two', 'two ', 'both', 'perAgent\n', '', null, undefined, 2, true, ['two'], {}, '__proto__', 'constructor']) assert.equal(core.displayModeOf(bad), 'one', String(JSON.stringify(bad)));
  assert.equal(clean({ displayMode: 'two' }).displayMode, 'two');
  assert.equal(clean({ displayMode: 'Two' }).displayMode, 'one');
});

test('a fresh install: One cat, Shrimpy and Momo, no stored agent coats; every call gives fresh objects', () => {
  const d = core.defaultDisplaySettings();
  assert.deepEqual(Object.keys(d), ['displayMode', 'pair', 'agentCats']);
  assert.deepEqual(d, DEFAULTS);
  assert.deepEqual(clean(null), d);
  d.pair[0] = 'noodle'; d.agentCats.x = 'momo';
  assert.deepEqual(core.defaultDisplaySettings(), DEFAULTS, 'changing a result never changes the next one');
});

test('anything that is not an object gives the defaults, and so does an object with nothing in it', () => {
  for (const raw of [...NOT_OBJECTS, {}, { pair: 7, agentCats: 7, displayMode: 7 }]) assert.deepEqual(clean(raw), DEFAULTS, String(JSON.stringify(raw)));
});

test('a valid value comes back as it went in, and cleaning twice changes nothing', () => {
  const valid = clean({ displayMode: 'perAgent', pair: ['momo', 'ginger'], agentCats: { agent_gemini: 'latte', integration_claude: 'oreo', agent_codex: 'momo', ai_openai: 'blue' } });
  assert.deepEqual(valid, { displayMode: 'perAgent', pair: ['momo', 'ginger'], agentCats: { agent_codex: 'momo', agent_gemini: 'latte', ai_openai: 'blue', integration_claude: 'oreo' } });
  assert.deepEqual(clean(valid), valid);
  assert.deepEqual(clean(JSON.parse(JSON.stringify(valid))), valid, 'it survives being written as JSON and read back');
});

test('the pair: two valid cat IDs, as an array or as the JSON text the Mac stores; anything else, whole, is Shrimpy and Momo', () => {
  for (const pair of [['momo', 'shrimpy'], ['ginger', 'noodle'], ['noodle', 'shrimpy']]) {
    assert.deepEqual(core.cleanPair(pair), pair);
    assert.deepEqual(core.cleanPair(JSON.stringify(pair)), pair, 'as JSON text');
  }
  const bad = [[], ['momo'], ['momo', 'shrimpy', 'ginger'], ['momo', 'tiger'], ['Momo', 'shrimpy'], ['momo', 7], [null, 'momo'], ['momo', ['shrimpy']], [{}, {}], [['momo'], ['ginger']], ['constructor', 'momo'], ['__proto__', 'momo'],
    'momo', 'shrimpy,momo', '', ' ', '["momo"]', '["momo","tiger"]', '{"a":"momo","b":"ginger"}', '["momo","ginger"', "['momo','ginger']", '["momo","ginger",]', '["momo","ginger"] x', 'null', '42',
    null, undefined, 7, true, {}, { 0: 'momo', 1: 'ginger' }];
  for (const b of bad) assert.deepEqual(core.cleanPair(b), ['shrimpy', 'momo'], String(JSON.stringify(b)));
});

test('the pair: the same coat twice makes cat 2 the next coat in CAT_IDS order, after the last one the first', () => {
  assert.deepEqual(core.cleanPair(['shrimpy', 'shrimpy']), ['shrimpy', 'momo']);
  assert.deepEqual(core.cleanPair(['momo', 'momo']), ['momo', 'ginger']);
  assert.deepEqual(core.cleanPair(['puff', 'puff']), ['puff', 'noodle']);
  assert.deepEqual(core.cleanPair(['noodle', 'noodle']), ['noodle', 'shrimpy']);
  assert.deepEqual(core.cleanPair('["leo","leo"]'), ['leo', 'button']);
  for (const id of IDS) { const [a, b] = core.cleanPair([id, id]); assert.notEqual(a, b); assert.equal(b, IDS[(IDS.indexOf(id) + 1) % 16]); }
  assert.deepEqual(core.cleanPair(['momo', 'shrimpy']), ['momo', 'shrimpy'], 'two different coats are never touched, in either order');
});

test('pill IDs: the shape of one, and no prototype names', () => {
  for (const ok of ['integration_claude', 'agent_codex', 'agent_my-tool-2', 'ai_openai', 'integration_stripe', 'ab', 'a' + 'b'.repeat(63)]) assert.ok(core.isPillId(ok), ok);
  for (const bad of ['', 'a', 'A', 'Agent_codex', 'agent codex', 'agent.codex', '_agent', '1agent', '-agent', 'agent_é', 'agent/codex', 'agent_x\n', 'agent_x ', 'a' + 'b'.repeat(64), '__proto__', 'constructor', 'prototype', 'toString', 'hasOwnProperty', null, undefined, 7, true, [], {}, ['agent_codex']]) assert.ok(!core.isPillId(bad), String(bad));
  assert.ok(core.isAgentPill('integration_claude') && core.isAgentPill('agent_codex') && core.isAgentPill('agent_x'));
  for (const no of ['integration_stripe', 'integration_music', 'ai_openai', 'integration_claude2', 'agent_', 'agent', 'Agent_codex', 'agentcodex', null, 7]) assert.ok(!core.isAgentPill(no), String(no));
  assert.equal(core.defaultAgentCat('integration_claude'), 'shrimpy');
  assert.equal(core.defaultAgentCat('agent_codex'), 'momo');
  for (const none of ['agent_gemini', 'integration_stripe', 'constructor', '__proto__', '', null, 7]) assert.equal(core.defaultAgentCat(none), null, String(none));
});

test('the agent coats: unknown pills are kept, a bad coat is the default or dropped, the result is in code-point order', () => {
  const out = core.cleanAgentCats({ agent_zed: 'noodle', ai_openai: 'blue', integration_claude: 'tiger', agent_codex: 7, agent_gemini: 'Momo', agent_cursor: null, agent_antigravity: 'latte', integration_music: ['momo'], Weird: 'momo', 'agent codex': 'momo' });
  assert.deepEqual(out, { agent_antigravity: 'latte', agent_codex: 'momo', agent_zed: 'noodle', ai_openai: 'blue', integration_claude: 'shrimpy' });
  assert.deepEqual(Object.keys(out), ['agent_antigravity', 'agent_codex', 'agent_zed', 'ai_openai', 'integration_claude'], 'sorted');
  assert.ok(!('agent_gemini' in out) && !('agent_cursor' in out) && !('integration_music' in out), 'a bad coat for a pill without a default is dropped, so assignment fills it in later');
  assert.deepEqual(core.cleanAgentCats(out), out);
  assert.equal(core.cleanAgentCats({ integration_claude: 'tiger' }).integration_claude, 'shrimpy');
  assert.equal(core.cleanAgentCats({ agent_codex: '' }).agent_codex, 'momo');
});

test('the agent coats: hostile maps and keys never throw and never pollute', () => {
  for (const raw of [...NOT_OBJECTS, { cats: 1 }]) assert.deepEqual(core.cleanAgentCats(raw), {}, String(JSON.stringify(raw)));
  const polluted = JSON.parse('{"__proto__":"momo","constructor":"momo","prototype":"momo","agent_ok":"ginger","toString":"momo"}');
  const out = core.cleanAgentCats(polluted);
  assert.deepEqual(out, { agent_ok: 'ginger' });
  assert.equal(Object.getPrototypeOf(out), Object.prototype);
  assert.equal({}.agent_ok, undefined, 'nothing reached Object.prototype');
  const nested = JSON.parse('{"__proto__":{"agent_x":"momo"},"agent_y":{"__proto__":"momo"}}');
  assert.deepEqual(core.cleanAgentCats(nested), {});
  assert.equal({}.agent_x, undefined);
});

test('the agent coats: at most 256 pills, the first by code-point order; the result shares nothing with the input', () => {
  const big = Object.fromEntries(Array.from({ length: 300 }, (_, i) => ['agent_a' + String(i).padStart(3, '0'), IDS[i % 16]]));
  const out = core.cleanAgentCats(big);
  assert.equal(Object.keys(out).length, 256);
  assert.equal(Object.keys(out)[0], 'agent_a000');
  assert.equal(Object.keys(out)[255], 'agent_a255');
  assert.ok(!('agent_a256' in out));
  const raw = { agent_x: 'momo' };
  const a = core.cleanAgentCats(raw), b = core.cleanAgentCats(raw);
  a.agent_x = 'noodle';
  assert.equal(b.agent_x, 'momo');
  assert.equal(raw.agent_x, 'momo');
});

test('the input is never changed, even when it is frozen', () => {
  const raw = deepFreeze({ displayMode: 'two', pair: ['momo', 'momo'], agentCats: { agent_x: 'momo', integration_claude: 'tiger' } });
  assert.doesNotThrow(() => clean(raw));
  assert.deepEqual(clean(raw), { displayMode: 'two', pair: ['momo', 'ginger'], agentCats: { agent_x: 'momo', integration_claude: 'shrimpy' } });
  assert.deepEqual(raw.pair, ['momo', 'momo']);
});

test('cleanCatSettings is unchanged: it still drops the display keys, so an app cleans the same raw block with both functions', () => {
  const raw = { displayMode: 'two', pair: ['momo', 'ginger'], agentCats: { agent_x: 'momo' } };
  assert.deepEqual(core.cleanCatSettings(raw), core.defaultCatSettings());
  assert.deepEqual(Object.keys(core.defaultCatSettings()), ['character', 'motionStyle', 'collar', 'furLines', 'cats']);
  assert.deepEqual(clean({ character: 'momo', collar: 'band', cats: {} }), DEFAULTS, 'and cleanDisplaySettings ignores the Cat settings');
});

test('hostile values never throw: 3000 random display settings come out valid, and cleaning them again changes nothing', () => {
  const r = core.rng(2027), pool = ['one', 'two', 'perAgent', 'Two', '', ' ', 'momo', 'shrimpy', 'tiger', 'noodle', '["momo","ginger"]', '["momo"', '__proto__', 'constructor', 'agent_x', 'agent_codex', 'integration_claude', 'ai_openai', 'Agent_X', null, true, false, 0, 1, -1, .5, 7, [], ['momo'], ['momo', 'ginger'], ['ginger', 'ginger'], [1, 2], {}, { agent_x: 'latte' }, { agent_codex: 'tiger' }];
  const pick = () => pool[Math.floor(r() * pool.length)];
  const valid = s => core.DISPLAY_MODES.includes(s.displayMode) && s.pair.length === 2 && s.pair.every(c => IDS.includes(c)) && s.pair[0] !== s.pair[1]
    && Object.entries(s.agentCats).every(([k, v]) => core.isPillId(k) && IDS.includes(v)) && JSON.stringify(Object.keys(s.agentCats)) === JSON.stringify(Object.keys(s.agentCats).sort());
  for (let i = 0; i < 3000; i++) {
    const map = r() < .15 ? pick() : Object.fromEntries(Array.from({ length: Math.floor(r() * 6) }, () => [pick(), pick()]).filter(([k]) => typeof k === 'string'));
    const raw = { displayMode: pick(), pair: pick(), agentCats: map };
    const out = clean(raw);
    assert.ok(valid(out), JSON.stringify(raw));
    assert.deepEqual(clean(out), out);
  }
});

const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/display-cases.json', import.meta.url), 'utf8'));
const roundTrip = v => JSON.parse(JSON.stringify(v));

test('display-cases.json: the frozen values and the defaults are the core\'s', () => {
  assert.deepEqual(fx.ids, IDS);
  assert.deepEqual(fx.modes, core.DISPLAY_MODES);
  assert.deepEqual(fx.defaultPair, core.DEFAULT_PAIR);
  assert.deepEqual(fx.defaultAgentCats, core.DEFAULT_AGENT_CATS);
  assert.equal(fx.maxAgentCats, core.MAX_AGENT_CATS);
  assert.equal(fx.pillIdPattern, core.PILL_ID.source);
  assert.deepEqual(compare(roundTrip(core.defaultDisplaySettings()), fx.defaults), []);
});

test('display-cases.json: every case replays from its own input', () => {
  for (const c of fx.cases) assert.deepEqual(compare(roundTrip(clean(c.raw)), c.out), [], c.name);
  for (const c of fx.pairs) assert.deepEqual(compare(roundTrip(core.cleanPair(c.raw)), c.out), [], c.name);
  for (const c of fx.agentCats) assert.deepEqual(compare(roundTrip(core.cleanAgentCats(c.raw)), c.out), [], c.name);
  for (const c of fx.pillIds) assert.deepEqual({ id: c.id, pill: core.isPillId(c.id), agent: core.isAgentPill(c.id), default: core.defaultAgentCat(c.id) }, c, JSON.stringify(c.id));
});

test('display-cases.json: the inputs the spec worries about are in it (bad JSON, wrong types, unknown IDs, prototype names, a valid value)', () => {
  const names = fx.cases.map(c => c.name), pairs = fx.pairs.map(c => c.name), agents = fx.agentCats.map(c => c.name);
  for (const n of ['nothing stored', 'a fully valid value', 'an unknown mode', 'the pair as JSON text, as the Mac stores it', 'a pair of the same coat', 'prototype names as pills', 'three hundred pills keep the first 256', 'the Cat settings are not display settings']) assert.ok(names.includes(n), n);
  for (const n of ['the last coat twice wraps to the first', 'JSON text cut off', 'JSON text with single quotes', 'prototype names as coats', 'an unknown coat second']) assert.ok(pairs.includes(n), n);
  for (const n of ['a bad coat for Claude Code is its default', 'a bad coat for another agent is dropped', 'a pill that is not known is kept', 'prototype names', '300 pills']) assert.ok(agents.includes(n), n);
  assert.ok(fx.pairs.filter(c => typeof c.raw === 'string').length >= 14, 'text inputs');
  assert.ok(fx.cases.some(c => c.out.displayMode === 'perAgent' && Object.keys(c.out.agentCats).length === 4), 'a valid value that keeps its settings');
  assert.equal(Object.keys(fx.agentCats.find(c => c.name === '300 pills').out).length, 256);
});
