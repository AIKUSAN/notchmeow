import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const step = core.kittenStep;
const deepFreeze = v => { if (v && typeof v === 'object') { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };
const K = (id, state = 'working', born = 0, last = born, extra = {}) => ({ id, type: '', session: null, state, born, last, until: null, ...extra });
const run = (events, list = []) => events.reduce((l, e) => step(l, e), list);
const ids = list => list.map(k => k.id);
const MIN = 60 * 1000;

test('the limits: eight kittens, a 0.6 s farewell, four states, the 10-minute sweep is the sleep timer\'s', () => {
  assert.equal(core.KITTEN_MAX, 8);
  assert.equal(core.KITTEN_LEAVE_MS, 600);
  assert.deepEqual(core.KITTEN_STATES, ['working', 'searching', 'approval', 'leaving']);
  assert.equal(core.SLEEP_AFTER_MS, 10 * MIN);
});

test('SubagentStart adds a working kitten; a repeat only refreshes it; an id that is empty or not text adds nothing', () => {
  const one = step([], { type: 'start', id: 'a1', agentType: 'Explore', t: 1000 });
  assert.deepEqual(one, [{ id: 'a1', type: 'Explore', session: null, state: 'working', born: 1000, last: 1000, until: null }]);
  assert.deepEqual(step(one, { type: 'start', id: 'a1', agentType: 'Plan', t: 2000 }), [{ id: 'a1', type: 'Plan', session: null, state: 'working', born: 1000, last: 2000, until: null }], 'born stays, the type is the newest');
  assert.deepEqual(step(one, { type: 'start', id: 'a1', t: 2000 })[0].type, 'Explore', 'a repeat with no type keeps the old one');
  for (const id of ['', 7, null, undefined, {}, ['a'], 'x'.repeat(129)]) assert.deepEqual(step([], { type: 'start', id, t: 1 }), [], String(id).slice(0, 12));
  assert.equal(step([], { type: 'start', id: 'x'.repeat(128), t: 1 }).length, 1);
  assert.equal(step([], { type: 'start', id: 'a', agentType: 7, t: 1 })[0].type, '', 'a type that is not text is empty');
  assert.equal(step([], { type: 'start', id: 'a', agentType: 'y'.repeat(100), t: 1 })[0].type.length, 64);
});

test('a tool event sets the kitten\'s state from the tool: searching for a search tool, working for any other', () => {
  const start = step([], { type: 'start', id: 'a1', t: 0 });
  for (const tool of ['WebSearch', 'WebFetch', 'Grep', 'Glob', 'google_web_search', 'grep_search', 'web_search', 'grep_files']) assert.equal(step(start, { type: 'tool', id: 'a1', tool, t: 5 })[0].state, 'searching', tool);
  for (const tool of ['Bash', 'Read', 'Edit', 'Write', 'Task', 'websearch', 'mcp__brave__web_search', '', undefined, 7, null]) assert.equal(step(step(start, { type: 'tool', id: 'a1', tool: 'Grep', t: 5 }), { type: 'tool', id: 'a1', tool, t: 6 })[0].state, 'working', String(tool));
  assert.equal(step(start, { type: 'tool', id: 'a1', tool: 'Grep', t: 5 })[0].last, 5);
  assert.deepEqual(core.toolState('Grep'), 'searching', 'the same rule as the parent cat\'s');
});

test('a tool event for an id with no kitten creates none: the start is the only way in, so a late event cannot bring one back', () => {
  assert.deepEqual(step([], { type: 'tool', id: 'ghost', tool: 'Bash', t: 5 }), []);
  assert.deepEqual(ids(step([K('a1')], { type: 'tool', id: 'ghost', tool: 'Bash', t: 5 })), ['a1']);
  const gone = run([{ type: 'start', id: 'a1', t: 0 }, { type: 'stop', id: 'a1', t: 10 }, { type: 'tick', t: 700 }]);
  assert.deepEqual(gone, []);
  assert.deepEqual(step(gone, { type: 'tool', id: 'a1', tool: 'Bash', t: 800 }), [], 'after it has gone');
  const leaving = run([{ type: 'start', id: 'a1', t: 0 }, { type: 'stop', id: 'a1', t: 10 }]);
  assert.equal(step(leaving, { type: 'tool', id: 'a1', tool: 'Bash', t: 20 })[0].state, 'leaving', 'while it is leaving, a late event changes nothing');
  assert.deepEqual(step(leaving, { type: 'permission', id: 'a1', t: 20 }), leaving);
});

test('a permission request from the subagent is approval, until it is answered; a tool event ends it too', () => {
  const s = run([{ type: 'start', id: 'a1', t: 0 }, { type: 'tool', id: 'a1', tool: 'Grep', t: 1 }]);
  const wait = step(s, { type: 'permission', id: 'a1', t: 2 });
  assert.equal(wait[0].state, 'approval');
  assert.equal(step(wait, { type: 'resolved', id: 'a1', t: 3 })[0].state, 'working', 'answered: back to working (the next tool event says more)');
  assert.equal(step(s, { type: 'resolved', id: 'a1', t: 3 })[0].state, 'searching', 'resolved without a request keeps the state');
  assert.equal(step(wait, { type: 'tool', id: 'a1', tool: 'Edit', t: 3 })[0].state, 'working');
  assert.deepEqual(step([], { type: 'permission', id: 'a1', t: 2 }), []);
});

test('SubagentStop: leaving for 0.6 s, then removed by the next event; kittenView hides it from that moment', () => {
  const s = run([{ type: 'start', id: 'a1', t: 0 }, { type: 'start', id: 'a2', t: 5 }, { type: 'stop', id: 'a1', t: 1000 }]);
  assert.deepEqual(s[0], { id: 'a1', type: '', session: null, state: 'leaving', born: 0, last: 1000, until: 1600 });
  assert.deepEqual(ids(step(s, { type: 'tick', t: 1599 })), ['a1', 'a2'], 'still there at 599 ms');
  assert.deepEqual(ids(step(s, { type: 'tick', t: 1600 })), ['a2'], 'gone at 600 ms');
  assert.deepEqual(ids(core.kittenView(s, 1599)), ['a2', 'a1'], 'newest first; the leaving one is still drawn');
  assert.deepEqual(ids(core.kittenView(s, 1600)), ['a2'], 'hidden from `until` on, with no event and no timer');
  assert.deepEqual(core.kittenView(s, NaN).length, 2, 'a time that is not a number hides nothing');
  assert.deepEqual(step(s, { type: 'stop', id: 'a1', t: 1100 }), s, 'a second stop changes nothing');
  assert.deepEqual(step(s, { type: 'stop', id: 'ghost', t: 1100 }), s);
});

test('the parent stopping or the session ending removes every kitten, in whatever state', () => {
  const s = run([{ type: 'start', id: 'a1', t: 0 }, { type: 'start', id: 'a2', t: 1 }, { type: 'permission', id: 'a2', t: 2 }, { type: 'stop', id: 'a1', t: 3 }]);
  assert.equal(s.length, 2);
  assert.deepEqual(step(s, { type: 'end', t: 4 }), []);
  assert.deepEqual(step([], { type: 'end', t: 4 }), []);
});

test('two sessions of one agent share a pill: a session ending takes only its own kittens, and those with no session; an end with no session takes all', () => {
  const s = run([{ type: 'start', id: 'a1', session: 'S1', t: 1 }, { type: 'start', id: 'a2', session: 'S2', t: 2 }, { type: 'start', id: 'a3', t: 3 }, { type: 'start', id: 'a4', session: 'S1', t: 4 }]);
  assert.deepEqual(s.map(k => k.session), ['S1', 'S2', null, 'S1']);
  assert.deepEqual(ids(step(s, { type: 'end', session: 'S1', t: 5 })), ['a2'], 'S2\'s kitten stays; the one with no session goes');
  assert.deepEqual(ids(step(s, { type: 'end', session: 'S2', t: 5 })), ['a1', 'a4']);
  assert.deepEqual(ids(step(s, { type: 'end', session: 'S9', t: 5 })), ['a1', 'a2', 'a4'], 'an unknown session takes only the kittens with no session');
  for (const session of [undefined, null, '', 7, {}, 'x'.repeat(129)]) assert.deepEqual(step(s, { type: 'end', session, t: 5 }), [], String(session).slice(0, 8));
  assert.equal(step(s, { type: 'start', id: 'a1', session: 'S5', t: 9 })[0].session, 'S5', 'a repeated start with a session sets it');
  assert.equal(step(s, { type: 'start', id: 'a1', t: 9 })[0].session, 'S1', 'and without one keeps it');
  assert.equal(step([], { type: 'start', id: 'a', session: 7, t: 1 })[0].session, null, 'a session that is not text is none');
});

test('the sleep timer\'s sweep removes a kitten whose last event is 10 minutes old or more, and keeps the rest', () => {
  const s = run([{ type: 'start', id: 'old', t: 0 }, { type: 'start', id: 'mid', t: 5 * MIN }, { type: 'tool', id: 'old', tool: 'Bash', t: 1000 }]);
  assert.deepEqual(ids(step(s, { type: 'sweep', t: 10 * MIN + 999 })), ['old', 'mid'], 'old: its last event was at 1000, so one ms short of ten minutes it is kept');
  assert.deepEqual(ids(step(s, { type: 'sweep', t: 10 * MIN + 1000 })), ['mid'], 'and at ten minutes it is stale');
  assert.deepEqual(ids(step(s, { type: 'sweep', t: 20 * MIN })), [], 'both stale');
  assert.deepEqual(step([], { type: 'sweep', t: 20 * MIN }), []);
});

test('at most eight kittens: the ninth start drops the oldest by `born`, wherever it is in the list', () => {
  const nine = run(Array.from({ length: 9 }, (_, i) => ({ type: 'start', id: 'k' + i, t: 100 + i })));
  assert.deepEqual(ids(nine), ['k1', 'k2', 'k3', 'k4', 'k5', 'k6', 'k7', 'k8']);
  const odd = [K('x', 'working', 50), K('y', 'working', 10), K('z', 'working', 30), ...Array.from({ length: 5 }, (_, i) => K('p' + i, 'working', 100 + i))];
  assert.equal(odd.length, 8);
  assert.deepEqual(ids(step(odd, { type: 'start', id: 'new', t: 200 })).sort(), ['new', 'p0', 'p1', 'p2', 'p3', 'p4', 'x', 'z'], 'y is the oldest');
  assert.equal(step(odd, { type: 'start', id: 'x', t: 200 }).length, 8, 'a repeat adds nothing');
  const full = run(Array.from({ length: 8 }, (_, i) => ({ type: 'start', id: 'k' + i, t: i })));
  assert.equal(step(full, { type: 'start', id: 'k9', t: 99 }).length, 8);
});

test('a start for an id that is leaving makes a new kitten', () => {
  const s = run([{ type: 'start', id: 'a1', t: 0 }, { type: 'stop', id: 'a1', t: 10 }]);
  assert.deepEqual(step(s, { type: 'start', id: 'a1', t: 20 }), [{ id: 'a1', type: '', session: null, state: 'working', born: 20, last: 20, until: null }]);
});

test('an event that is malformed, of an unknown type or with no usable time changes nothing and never throws', () => {
  const list = [K('a1', 'searching', 5, 7), K('a2', 'approval', 6, 6)];
  for (const ev of [undefined, null, 7, 'start', [], {}, { type: 'start', id: 'x' }, { type: 'start', id: 'x', t: NaN }, { type: 'start', id: 'x', t: '5' }, { type: 'start', id: 'x', t: Infinity }, { type: 'bogus', id: 'a1', t: 9 }, { type: 7, t: 9 }, { type: 'tool', id: 'a1', tool: 'Bash', t: null }]) {
    assert.deepEqual(step(list, ev), list, JSON.stringify(ev));
  }
  assert.deepEqual(step(list, { type: 'tick', t: 9 }), list, 'a tick with nothing to drop');
});

test('the list is never changed and the result shares nothing with it, even when the input is frozen', () => {
  const list = deepFreeze([K('a1'), K('a2', 'leaving', 1, 2, { until: 100 })]);
  for (const ev of [{ type: 'start', id: 'a3', t: 9 }, { type: 'tool', id: 'a1', tool: 'Grep', t: 9 }, { type: 'stop', id: 'a1', t: 9 }, { type: 'end', t: 9 }, { type: 'sweep', t: 1e9 }]) assert.doesNotThrow(() => step(list, ev));
  const out = step(list, { type: 'tick', t: 5 });
  out[0].state = 'approval';
  assert.equal(list[0].state, 'working');
});

test('a list that an app holds badly is made safe: entries that are not kittens, with a repeated id or with a bad time are dropped', () => {
  const bad = [null, 7, 'x', [], {}, { id: 'a' }, { id: '', state: 'working', born: 0, last: 0 }, K('b', 'sleeping'), K('c', 'working', NaN), K('d', 'working', 0, 'x'), K('e'), K('e', 'approval', 5)];
  assert.deepEqual(ids(core.cleanKittens(bad)), ['e']);
  assert.deepEqual(core.cleanKittens(null), []);
  assert.deepEqual(core.cleanKittens([K('l', 'leaving', 0, 0, { until: 'x' })])[0].until, null);
  assert.deepEqual(step(bad, { type: 'tick', t: 1 }).map(k => k.id), ['e']);
});

test('the order: a kitten waiting on an approval first, then the newest; leaving kittens are in the order too', () => {
  const l = [K('old', 'working', 1), K('wait', 'approval', 2), K('new', 'searching', 9), K('mid', 'working', 5), K('wait2', 'approval', 8), K('bye', 'leaving', 7, 7, { until: 99 })];
  assert.deepEqual(ids(core.kittenOrder(l)), ['wait2', 'wait', 'new', 'bye', 'mid', 'old']);
  assert.deepEqual(ids(core.kittenOrder([K('a', 'working', 5), K('b', 'working', 5), K('c', 'working', 5)])), ['c', 'b', 'a'], 'a tie: the one that started later in the list is newer');
  assert.deepEqual(core.kittenOrder([]), []);
  assert.deepEqual(core.kittenOrder(null), []);
  assert.deepEqual(ids(core.kittenView(l, 50)), ['wait2', 'wait', 'new', 'bye', 'mid', 'old']);
  assert.deepEqual(ids(core.kittenView(l, 99)), ['wait2', 'wait', 'new', 'mid', 'old'], 'bye is gone at `until`');
});

test('the mockup\'s scene: three kittens, one working, one searching, one waiting on an approval; the one waiting is first', () => {
  const s = run([{ type: 'start', id: 'a', t: 1 }, { type: 'start', id: 'b', t: 2 }, { type: 'start', id: 'c', t: 3 }, { type: 'tool', id: 'b', tool: 'Grep', t: 4 }, { type: 'permission', id: 'a', t: 5 }]);
  assert.deepEqual(core.kittenView(s, 6).map(k => `${k.id}:${k.state}`), ['a:approval', 'c:working', 'b:searching']);
});

test('the fallback: a Claude Code that sends no agent_id on tool events still gives a kitten at start and a farewell at stop', () => {
  const s = run([{ type: 'start', id: 'a1', agentType: 'Explore', t: 0 }, { type: 'tool', tool: 'Grep', t: 1 }, { type: 'tool', id: undefined, tool: 'Grep', t: 2 }, { type: 'permission', t: 3 }]);
  assert.deepEqual(core.kittenView(s, 4).map(k => k.state), ['working'], 'in the working pose throughout');
  assert.equal(step(s, { type: 'stop', id: 'a1', t: 5 })[0].state, 'leaving');
});

test('kittenPlaceOf: where the big cat\'s kittens go, by mode and size', () => {
  assert.equal(core.kittenPlaceOf('one', true), 'bigExpanded');
  assert.equal(core.kittenPlaceOf('one', false), 'bigCompact');
  assert.equal(core.kittenPlaceOf('perAgent', true), 'bigExpanded');
  assert.equal(core.kittenPlaceOf('perAgent', false), 'bigCompact');
  assert.equal(core.kittenPlaceOf('two', true), 'pairExpanded');
  assert.equal(core.kittenPlaceOf('two', false), 'pairCompact');
  assert.equal(core.kittenPlaceOf('bogus', false), 'bigCompact', 'an unknown mode is One cat');
  assert.deepEqual(Object.keys(core.KITTEN_PLACES), ['bigExpanded', 'bigCompact', 'pairCompact', 'pairExpanded', 'pill']);
});

const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const view = n => Array.from({ length: n }, (_, i) => K('k' + i, ['approval', 'searching', 'working'][i % 3], 10 - i));

test('slots under the big cat, expanded: up to three Ø15 kittens under a Ø58 cat, the mockup\'s numbers over its parent\'s size', () => {
  const s = core.kittenSlots('bigExpanded', view(3));
  assert.equal(s.unit, 'D');
  assert.equal(s.count, 3); assert.equal(s.more, 0); assert.equal(s.moreAt, null); assert.equal(s.label, null);
  assert.deepEqual(s.shown.map(k => k.id), ['k0', 'k1', 'k2']);
  [24, 42, 60].forEach((px, i) => { near(s.shown[i].x * 58, px); near(s.shown[i].y * 58, 34); near(s.shown[i].d * 58, 15); });
  assert.deepEqual(s.shown.map(k => k.state), ['approval', 'searching', 'working']);
  const five = core.kittenSlots('bigExpanded', view(5));
  assert.equal(five.shown.length, 3); assert.equal(five.more, 2); assert.equal(five.count, 5);
  near(five.moreAt.x * 58, 78); near(five.moreAt.y * 58, 34); near(five.moreAt.size, .2);
});

test('slots beside the big cat in the compact notch: two Ø12 kittens beside a Ø20 cat, and "+N" above them', () => {
  const s = core.kittenSlots('bigCompact', view(4));
  assert.equal(s.shown.length, 2); assert.equal(s.more, 2);
  [22, 35].forEach((px, i) => { near(s.shown[i].x * 20, px); near(s.shown[i].y * 20, 5); near(s.shown[i].d * 20, 12); });
  near(s.moreAt.x * 20, 42); near(s.moreAt.y * 20, -10); near(s.moreAt.size, .25);
  assert.equal(core.kittenSlots('bigCompact', view(2)).moreAt, null);
});

test('the pair in the compact notch has no room: only a count, "×N", and no kittens', () => {
  const s = core.kittenSlots('pairCompact', view(3));
  assert.deepEqual(s.shown, []); assert.equal(s.more, 0); assert.equal(s.moreAt, null);
  assert.deepEqual(s.label, { text: '×3', x: 1.1, y: .3, size: .5 });
  assert.equal(core.kittenSlots('pairCompact', view(1)).label.text, '×1');
  assert.equal(core.kittenSlots('pairCompact', []).label, null);
});

test('the pair, expanded: each cat\'s kittens in a row centred under it, up to three', () => {
  const two = core.kittenSlots('pairExpanded', view(2)), three = core.kittenSlots('pairExpanded', view(3)), one = core.kittenSlots('pairExpanded', view(1));
  near(one.shown[0].x, 0);
  near(two.shown[0].x, -9 / 58); near(two.shown[1].x, 9 / 58);
  near(three.shown[0].x, -18 / 58); near(three.shown[1].x, 0); near(three.shown[2].x, 18 / 58);
  for (const s of [one, two, three]) s.shown.forEach(k => { near(k.y * 58, 34); near(k.d * 58, 15); });
  const six = core.kittenSlots('pairExpanded', view(6));
  assert.equal(six.shown.length, 3); assert.equal(six.more, 3);
  near(six.moreAt.x, 0); near(six.moreAt.y * 58, 50); near(six.moreAt.size, .2);
});

test('kittens in a pill: Ø15 in a 28 px pill, from the trailing end inwards, with "+N" after the last', () => {
  const s = core.kittenSlots('pill', view(4));
  assert.equal(s.unit, 'H');
  assert.equal(s.shown.length, 3); assert.equal(s.more, 1);
  [-17.5, -33.5, -49.5].forEach((px, i) => { near(s.shown[i].x * 28, px); near(s.shown[i].y, 0); near(s.shown[i].d * 28, 15); });
  near(s.moreAt.x * 28, -65.5); near(s.moreAt.y, 0); near(s.moreAt.size, .36);
  assert.ok(s.shown.every(k => k.x < 0), 'all inside the pill: negative, towards the leading end');
});

test('no kittens, an unknown place and bad input never throw', () => {
  for (const place of Object.keys(core.KITTEN_PLACES)) {
    const s = core.kittenSlots(place, []);
    assert.deepEqual([s.place, s.count, s.shown, s.more, s.moreAt, s.label], [place, 0, [], 0, null, null], place);
    assert.doesNotThrow(() => core.kittenSlots(place, [null, 7, {}, { id: '' }, K('ok')]));
    assert.equal(core.kittenSlots(place, [null, 7, {}, { id: '' }, K('ok')]).count, 1);
    assert.deepEqual(core.kittenSlots(place, null).shown, []);
  }
  assert.deepEqual(core.kittenSlots('nowhere', view(3)), { place: 'nowhere', unit: null, count: 3, shown: [], more: 0, moreAt: null, label: null });
  for (const p of [undefined, null, 7, '__proto__', 'constructor', 'toString']) assert.deepEqual(core.kittenSlots(p, view(1)).shown, [], String(p));
  assert.equal(core.kittenSlots('bigExpanded', [{ id: 'a', state: 7 }]).shown[0].state, 'working', 'a state that is not text is working');
});

test('hostile events never throw: 4000 random events keep every list valid, at most eight long, and clean already', () => {
  const r = core.rng(8080), types = ['start', 'tool', 'permission', 'resolved', 'stop', 'end', 'sweep', 'tick', 'bogus', undefined, 7], idp = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', '', undefined, 7], tools = ['Bash', 'Grep', 'WebSearch', '', undefined, 7];
  let list = [], t = 0;
  for (let i = 0; i < 4000; i++) {
    t += Math.floor(r() * 400_000);
    const ev = { type: types[Math.floor(r() * types.length)], id: idp[Math.floor(r() * idp.length)], tool: tools[Math.floor(r() * tools.length)], agentType: r() < .5 ? 'Explore' : undefined, t: r() < .05 ? NaN : t };
    list = step(list, ev);
    assert.ok(list.length <= core.KITTEN_MAX);
    assert.equal(new Set(list.map(k => k.id)).size, list.length);
    assert.ok(list.every(k => core.KITTEN_STATES.includes(k.state) && Number.isFinite(k.born) && Number.isFinite(k.last) && (k.state === 'leaving') === (k.until !== null)));
    assert.deepEqual(core.cleanKittens(list), list);
    assert.deepEqual(ids(core.kittenView(list, t)).sort(), ids(list.filter(k => k.state !== 'leaving' || k.until > t)).sort());
    assert.ok(core.kittenSlots('bigExpanded', core.kittenView(list, t)).shown.length <= 3);
  }
});

const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/kitten-cases.json', import.meta.url), 'utf8'));
const roundTrip = v => JSON.parse(JSON.stringify(v));

test('kitten-cases.json: the limits, the states and the places are the core\'s', () => {
  assert.deepEqual(fx.limits, { max: core.KITTEN_MAX, leaveMs: core.KITTEN_LEAVE_MS, sleepAfterMs: core.SLEEP_AFTER_MS });
  assert.deepEqual(fx.states, core.KITTEN_STATES);
  assert.deepEqual(compare(roundTrip(core.KITTEN_PLACES), fx.places), []);
});

test('kitten-cases.json: every script replays event by event, and every order, view, clean, slot and place case from its own input', () => {
  for (const s of fx.scripts) {
    let list = s.from;
    s.steps.forEach((st, i) => { list = step(list, st.ev); assert.deepEqual(compare(roundTrip(list), st.list), [], `${s.name}, event ${i + 1}`); });
  }
  for (const c of fx.order) assert.deepEqual(core.kittenOrder(c.list).map(k => k.id), c.out, c.name);
  for (const c of fx.views) assert.deepEqual(core.kittenView(c.list, c.now).map(k => k.id), c.out, c.name);
  for (const c of fx.cleans) assert.deepEqual(compare(roundTrip(core.cleanKittens(c.raw)), c.out), [], c.name);
  for (const c of fx.slots) assert.deepEqual(compare(roundTrip(core.kittenSlots(c.place, c.kittens)), c.out), [], c.name);
  for (const c of fx.placeOf) assert.equal(core.kittenPlaceOf(c.mode, c.expanded), c.out, `${c.mode} ${c.expanded}`);
});

test('kitten-cases.json: the situations the spec worries about are in it (the fallback, late and lost events, the cap, the sweep, the pair and the overflow)', () => {
  const names = fx.scripts.map(s => s.name);
  for (const n of ['a late event after the stop brings nothing back', 'an event for an id that never started creates nothing', 'nine starts: the oldest goes', 'the parent stops: every kitten goes', 'the sleep timer sweeps the stale', 'the farewell lasts 600 ms and the next event removes it', 'events that are malformed change nothing']) assert.ok(names.includes(n), n);
  assert.ok(names.some(n => n.startsWith('Claude Code without agent_id')), 'the fallback');
  assert.equal(fx.scripts.find(s => s.name === 'nine starts: the oldest goes').steps.at(-1).list.length, 8);
  assert.ok(fx.slots.some(c => c.place === 'pairCompact' && c.out.label && c.out.label.text === '×4'), 'the count by the pair');
  assert.ok(fx.slots.some(c => c.place === 'bigExpanded' && c.out.more === 4), 'an overflow');
  assert.ok(fx.slots.length >= 25 && fx.views.length === 4 && fx.placeOf.length === 8);
});
