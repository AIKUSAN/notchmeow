import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const roundTrip = v => JSON.parse(JSON.stringify(v));
const PHASES = core.DESKTOP_PHASES, EVENTS = core.DESKTOP_EVENTS, INFO = core.DESKTOP_PHASE_INFO;
const SPOT = { x: 640, y: 300 };
const ev = type => (type === 'dragOut' || type === 'move' ? { type, spot: SPOT } : { type });
const step = (state, type) => core.desktopStep(state, ev(type));
const near = (a, b, msg) => assert.ok(Math.abs(a - b) <= 1e-9, `${msg}: ${a} vs ${b}`);

test('the frozen values: seven phases, nine events, the acts, a flight of 600 ms', () => {
  assert.deepEqual(PHASES, ['home', 'flyingOut', 'onDesktop', 'retracting', 'atNotchForAlert', 'returning', 'flyingHome']);
  assert.deepEqual(EVENTS, ['dragOut', 'move', 'toggle', 'sendHome', 'alertOn', 'alertOff', 'flightDone', 'launch', 'screensChanged']);
  assert.deepEqual(core.DESKTOP_ACTS, ['place', 'flyOut', 'flyHome', 'retract', 'turn', 'keep', 'land', 'dock', 'goHome', 'move', 'resettle']);
  assert.equal(core.DESKTOP_FLIGHT_MS, 600);
  assert.deepEqual(Object.keys(INFO), PHASES);
  assert.deepEqual(Object.keys(core.DESKTOP_NEXT), PHASES);
});

test('the older flight is untouched: flightAt and FLIGHT_MS still belong to the file catch', () => {
  assert.equal(typeof core.desktopFlightAt, 'function');
  assert.equal(core.FLIGHT_MS, 380);
  assert.deepEqual(Object.keys(core.flightAt({ x: 0, y: 0 }, { x: 10, y: 10 }, 20, .5)).sort(), ['rot', 'size', 'x', 'y']);
  assert.notEqual(core.desktopFlightAt, core.flightAt);
});

test('every phase and event pair answers with a phase and an act, and the table says which ones do something', () => {
  let moves = 0;
  for (const s of PHASES) for (const type of EVENTS) {
    const r = step(s, type), listed = Object.prototype.hasOwnProperty.call(core.DESKTOP_NEXT[s], type);
    assert.deepEqual(Object.keys(r), ['state', 'act'], `${s} + ${type}`);
    assert.ok(PHASES.includes(r.state), `${s} + ${type}`);
    if (listed) { moves++; assert.ok(core.DESKTOP_ACTS.includes(r.act), `${s} + ${type} has an act`); assert.deepEqual(core.DESKTOP_NEXT[s][type], [r.state, r.act]); }
    else assert.deepEqual(r, { state: s, act: null }, `${s} + ${type} makes no sense and changes nothing`);
  }
  assert.equal(PHASES.length * EVENTS.length, 63);
  assert.equal(moves, 27, 'the table lists 27 pairs that do something');
});

test('the whole trip: out, an alert to the notch and back, home', () => {
  const run = (from, types) => types.reduce((acc, t) => { const r = step(acc.at(-1).state, t); return [...acc, r]; }, [{ state: from, act: null }]).slice(1);
  assert.deepEqual(run('home', ['toggle', 'flightDone', 'alertOn', 'flightDone', 'alertOff', 'flightDone', 'sendHome', 'flightDone']).map(r => `${r.state}:${r.act}`), [
    'flyingOut:flyOut', 'onDesktop:land', 'retracting:retract', 'atNotchForAlert:dock', 'returning:flyOut', 'onDesktop:land', 'flyingHome:flyHome', 'home:dock']);
  assert.deepEqual(step('home', 'dragOut'), { state: 'onDesktop', act: 'place' }, 'dropping the cat on the desktop places it, no flight');
  assert.deepEqual(step('home', 'launch'), { state: 'flyingOut', act: 'flyOut' }, 'a cat that was out flies out after the greeting');
});

test('an alert clearing mid-flight turns the cat around, and so does every change of mind', () => {
  assert.deepEqual(step('retracting', 'alertOff'), { state: 'returning', act: 'turn' });
  assert.deepEqual(step('returning', 'alertOn'), { state: 'retracting', act: 'turn' });
  assert.deepEqual(step('flyingOut', 'alertOn'), { state: 'retracting', act: 'turn' });
  assert.deepEqual(step('flyingOut', 'sendHome'), { state: 'flyingHome', act: 'turn' });
  assert.deepEqual(step('returning', 'sendHome'), { state: 'flyingHome', act: 'turn' });
  assert.deepEqual(step('flyingHome', 'toggle'), { state: 'flyingOut', act: 'turn' });
  // The rule behind the three words: both phases fly, the direction differs: turn; the same direction: keep. Nothing else is turn or keep.
  for (const a of PHASES) for (const type of EVENTS) {
    const r = step(a, type), flights = INFO[a].flight && INFO[r.state].flight && r.state !== a;
    assert.equal(r.act === 'turn', flights && INFO[a].dir !== INFO[r.state].dir, `${a} + ${type}`);
    assert.equal(r.act === 'keep', flights && INFO[a].dir === INFO[r.state].dir, `${a} + ${type}`);
  }
});

test('a sendHome during an alert ends the trip at home, and an alert at home takes nothing out', () => {
  assert.deepEqual(step('retracting', 'sendHome'), { state: 'flyingHome', act: 'keep' }, 'already flying to the notch: it just carries on, and ends at home');
  assert.deepEqual(step('atNotchForAlert', 'sendHome'), { state: 'home', act: 'goHome' });
  assert.deepEqual(step('atNotchForAlert', 'toggle'), { state: 'home', act: 'goHome' });
  assert.deepEqual(step('flyingHome', 'flightDone'), { state: 'home', act: 'dock' });
  assert.deepEqual(step('flyingHome', 'alertOn'), { state: 'flyingHome', act: null }, 'an alert during the flight home does not bring it back out');
  assert.deepEqual(step('home', 'alertOn'), { state: 'home', act: null });
  assert.deepEqual(step('home', 'alertOff'), { state: 'home', act: null });
  assert.deepEqual(step('home', 'sendHome'), { state: 'home', act: null });
  assert.deepEqual(step('onDesktop', 'alertOff'), { state: 'onDesktop', act: null });
  assert.deepEqual(step('atNotchForAlert', 'alertOn'), { state: 'atNotchForAlert', act: null });
});

test('the phases agree with their acts, and there are never two copies of one cat', () => {
  for (const s of PHASES) {
    assert.ok(!INFO[s].drawn || INFO[s].notchEmpty, `${s}: drawn on the desktop means the notch spot is empty`);
    assert.equal(INFO[s].flight, INFO[s].dir !== null, `${s}: a direction exactly when it flies`);
    for (const [type, [next, act]] of Object.entries(core.DESKTOP_NEXT[s])) {
      const N = INFO[next], at = `${s} + ${type}`;
      if (act === 'flyOut') assert.ok(N.flight && N.dir === 'out', at);
      if (act === 'flyHome' || act === 'retract') assert.ok(N.flight && N.dir === 'in', at);
      if (act === 'land') assert.ok(INFO[s].flight && next === 'onDesktop', at);
      if (act === 'dock') assert.ok(INFO[s].flight && !N.flight && !N.drawn && !N.notchEmpty, at);
      if (act === 'goHome') assert.ok(next === 'home' && !INFO[s].flight, at);
      if (act === 'place') assert.ok(s === 'home' && next === 'onDesktop', at);
      if (act === 'move' || act === 'resettle') assert.equal(next, s, at);
    }
  }
  assert.deepEqual(PHASES.filter(p => INFO[p].on), ['flyingOut', 'onDesktop', 'retracting', 'atNotchForAlert', 'returning'], 'the five that Settings stores as "out"');
});

test('every phase can get home, and no event sequence ever leaves the seven phases: 20000 random events', () => {
  const home = new Set(['home']);
  for (let again = true; again;) { again = false; for (const s of PHASES) if (!home.has(s) && EVENTS.some(t => home.has(step(s, t).state))) { home.add(s); again = true; } }
  assert.equal(home.size, 7, 'a path to home from every phase');
  const r = core.rng(8), pick = a => a[Math.floor(r() * a.length)];
  let s = 'home';
  for (let i = 0; i < 20000; i++) { const t = pick(EVENTS), out = core.desktopStep(s, ev(t)); assert.ok(PHASES.includes(out.state)); s = out.state; }
});

test('events that are not events, spots that are not spots and states that are not phases change nothing', () => {
  for (const bad of [null, undefined, 'toggle', 7, [], ['toggle'], {}, { type: 7 }, { type: ['toggle'] }, { type: null }, { type: 'Toggle' }, { type: 'toggle ' }, { type: '__proto__' }, { type: 'constructor' }, { type: 'hasOwnProperty' }, { type: 'launch2' }])
    assert.deepEqual(core.desktopStep('onDesktop', bad), { state: 'onDesktop', act: null }, JSON.stringify(bad));
  for (const type of ['dragOut', 'move']) {
    const from = type === 'dragOut' ? 'home' : 'onDesktop';
    assert.equal(core.desktopStep(from, { type, spot: { x: 1, y: 2 } }).act, type === 'dragOut' ? 'place' : 'move');
    for (const spot of [undefined, null, 7, 'x', [], [1, 2], {}, { x: 1 }, { y: 2 }, { x: '1', y: 2 }, { x: NaN, y: 2 }, { x: 1, y: Infinity }, { x: true, y: 2 }, { x: 1e6, y: 2 }, { x: 1, y: -1e6 }])
      assert.deepEqual(core.desktopStep(from, { type, spot }), { state: from, act: null }, `${type} ${String(JSON.stringify(spot))}`);
  }
  for (const bad of ['', 'Home', 'home ', 'fly', null, undefined, 7, ['home'], {}, '__proto__', 'constructor']) {
    assert.deepEqual(core.desktopStep(bad, { type: 'sendHome' }), { state: 'home', act: null }, String(bad));
    assert.deepEqual(core.desktopStep(bad, { type: 'toggle' }), { state: 'flyingOut', act: 'flyOut' }, 'a state that is not a phase counts as home');
  }
  const frozen = Object.freeze({ type: 'move', spot: Object.freeze({ x: 5, y: 6 }) });
  assert.doesNotThrow(() => core.desktopStep('onDesktop', frozen));
});

test('desktopFlightAt: the ends, the clamping and the full size', () => {
  const a = { x: 480, y: 16 }, b = { x: 576, y: 180 };
  assert.deepEqual(core.desktopFlightAt(a, b, 0), { x: 480, y: 16, scale: 1 });
  const end = core.desktopFlightAt(a, b, 1);
  near(end.x, 576, 'x at 1'); near(end.y, 180, 'y at 1'); assert.equal(end.scale, 1);
  for (const t of [-5, -0.001, -Infinity]) assert.deepEqual(core.desktopFlightAt(a, b, t), core.desktopFlightAt(a, b, 0), `t ${t}`);
  for (const t of [1.001, 2, 1e9, Infinity]) assert.deepEqual(core.desktopFlightAt(a, b, t), core.desktopFlightAt(a, b, 1), `t ${t}`);
  for (const t of [NaN, undefined, null, '0.5', [], {}]) assert.deepEqual(core.desktopFlightAt(a, b, t), core.desktopFlightAt(a, b, 0), `t ${String(t)}`);
  for (let i = 0; i <= 100; i++) assert.equal(core.desktopFlightAt(a, b, i / 100).scale, 1, 'the cat keeps its size the whole way');
});

test('desktopFlightAt: an arc that bows upwards, eased, that never overshoots its ends', () => {
  const a = { x: 480, y: 16 }, b = { x: 576, y: 180 }, mid = core.desktopFlightAt(a, b, .5);
  assert.ok(mid.y < (a.y + b.y) / 2 - 1, 'the middle of the flight is above the straight line');
  assert.ok(mid.x > (a.x + b.x) / 2, 'and so to the right of it, on a flight that goes down and right');
  const slow = core.desktopFlightAt(a, b, .1), fast = core.desktopFlightAt(a, b, .4);
  assert.ok(Math.hypot(slow.x - a.x, slow.y - a.y) < Math.hypot(fast.x - slow.x, fast.y - slow.y), 'it starts slowly: the first tenth covers less than the next three');
  let prev = 0;
  for (let i = 1; i <= 200; i++) { const p = core.desktopFlightAt(a, b, i / 200), d = Math.hypot(p.x - a.x, p.y - a.y); assert.ok(d >= prev - 1e-9 || i / 200 > .5, 'the distance from the start grows until the middle'); prev = d; }
  // The lift is a quarter of the distance, never more than 90 points, and a flight of no distance does not move.
  const far = core.desktopFlightAt({ x: 0, y: 0 }, { x: 3000, y: 0 }, .5);
  near(far.x, 1500, 'a flat flight, x'); near(far.y, -45, 'the lift is 90 at the top of the curve, so 45 at the middle of the path (half of it)');
  assert.deepEqual(core.desktopFlightAt({ x: 5, y: 5 }, { x: 5, y: 5 }, .5), { x: 5, y: 5, scale: 1 });
  const down = core.desktopFlightAt({ x: 100, y: 0 }, { x: 100, y: 400 }, .5);
  assert.ok(down.x > 100, 'a vertical flight bows to the right');
  const up = core.desktopFlightAt({ x: 100, y: 400 }, { x: 100, y: 0 }, .5);
  near(up.x, down.x, 'the same bow on the way back');
});

test('desktopFlightAt: the path is the same both ways, so a flight that turns around retraces itself', () => {
  const r = core.rng(3), pt = () => ({ x: Math.round(r() * 3000 - 500), y: Math.round(r() * 1600 - 200) });
  for (let i = 0; i < 400; i++) {
    const a = pt(), b = pt(), t = r();
    const there = core.desktopFlightAt(a, b, t), back = core.desktopFlightAt(b, a, 1 - t);
    near(there.x, back.x, `x ${JSON.stringify([a, b, t])}`); near(there.y, back.y, `y ${JSON.stringify([a, b, t])}`);
  }
  for (const [a, b] of [[{ x: 0, y: 0 }, { x: 0, y: 300 }], [{ x: 0, y: 0 }, { x: 300, y: 0 }], [{ x: 50, y: 50 }, { x: 50, y: 50 }]])
    for (const t of [0, .25, .5, .8, 1]) { const p = core.desktopFlightAt(a, b, t), q = core.desktopFlightAt(b, a, 1 - t); near(p.x, q.x, 'x'); near(p.y, q.y, 'y'); }
});

test('desktopFlightAt: ends that are not points count as 0, 0 and nothing throws', () => {
  for (const bad of [null, undefined, 7, 'x', [], {}, { x: 1 }, { x: NaN, y: 1 }, { x: '1', y: 1 }, { x: 1e9, y: 1 }]) {
    assert.deepEqual(core.desktopFlightAt(bad, { x: 100, y: 100 }, 0), { x: 0, y: 0, scale: 1 }, String(JSON.stringify(bad)));
    const end = core.desktopFlightAt({ x: 100, y: 100 }, bad, 1); near(end.x, 0, 'x'); near(end.y, 0, 'y');
  }
  const r = core.rng(21), junk = [null, undefined, NaN, Infinity, -1, 0, 1, 2, 1e300, 'a', {}, [], { x: 1, y: 2 }, { x: 1e5, y: -1e5 }];
  for (let i = 0; i < 2000; i++) { const p = core.desktopFlightAt(junk[Math.floor(r() * junk.length)], junk[Math.floor(r() * junk.length)], junk[Math.floor(r() * junk.length)]); assert.ok(Number.isFinite(p.x) && Number.isFinite(p.y) && p.scale === 1); }
});

const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/desktop-cases.json', import.meta.url), 'utf8'));

test('desktop-cases.json: the frozen values and the phase table are the core\'s', () => {
  assert.deepEqual(fx.phaseIds, PHASES);
  assert.deepEqual(fx.phases, INFO);
  assert.deepEqual(fx.events, EVENTS);
  assert.deepEqual(fx.acts, core.DESKTOP_ACTS);
  assert.equal(fx.flightMs, 600);
  assert.deepEqual(compare(fx.arc, core.DESKTOP_ARC), []);
});

test('desktop-cases.json: every step replays from its own input, and all 63 pairs are there', () => {
  for (const c of fx.steps) assert.deepEqual(core.desktopStep(c.state, c.event), c.out, JSON.stringify([c.state, c.event]));
  const pairs = new Set(fx.steps.filter(c => PHASES.includes(c.state) && c.event && EVENTS.includes(c.event.type) && (c.event.spot || !['dragOut', 'move'].includes(c.event.type))).map(c => `${c.state}|${c.event.type}`));
  assert.equal(pairs.size, 63);
  assert.ok(fx.steps.length >= 85, 'and the input that is not a phase or an event');
  assert.ok(fx.steps.some(c => c.state === null) && fx.steps.some(c => c.event === null) && fx.steps.some(c => c.event && c.event.type === '__proto__'));
});

test('desktop-cases.json: every trip replays, and the three stories of the spec are in it', () => {
  for (const t of fx.trips) {
    let s = t.from;
    t.events.forEach((e, i) => { const r = core.desktopStep(s, e); assert.deepEqual(r, t.out[i], `${t.name} step ${i}`); s = r.state; });
    assert.equal(t.out.length, t.events.length, t.name);
  }
  const named = n => fx.trips.find(t => t.name.startsWith(n));
  assert.deepEqual(named('an alert that clears mid-flight').out.map(r => r.state), ['retracting', 'returning', 'onDesktop']);
  assert.deepEqual(named('sendHome during an alert, in flight').out.map(r => r.state), ['retracting', 'flyingHome', 'flyingHome', 'flyingHome', 'home']);
  assert.deepEqual(named('sendHome during an alert, in the notch').out.map(r => r.state), ['retracting', 'atNotchForAlert', 'home', 'home', 'home']);
  assert.ok(fx.trips.length >= 11);
});

test('desktop-cases.json: every flight replays, and every route is sampled at the ends, the middle and out of range', () => {
  for (const c of fx.flights) assert.deepEqual(compare(roundTrip(core.desktopFlightAt(c.from, c.to, c.t)), c.out), [], c.name + ' ' + c.t);
  const by = new Map();
  for (const c of fx.flights) by.set(c.name, [...(by.get(c.name) || []), c.t]);
  const routes = [...by].filter(([, ts]) => ts.length === 9);
  assert.equal(routes.length, 9);
  for (const [name, ts] of routes) assert.deepEqual(ts, [-.5, 0, .1, .25, .5, .75, .9, 1, 1.5], name);
  const cut = fx.flights.filter(c => c.name === 'down and right: the default spot');
  assert.deepEqual(cut.find(c => c.t === -.5).out, cut.find(c => c.t === 0).out, 'before the start is the start');
  assert.deepEqual(cut.find(c => c.t === 1.5).out, cut.find(c => c.t === 1).out, 'after the end is the end');
  assert.ok(fx.flights.every(c => c.out.scale === 1));
  assert.ok(fx.flights.every(c => Math.abs(c.out.x) < 1000 && Math.abs(c.out.y) < 1000), 'positions stay under 1000 points, so that 12 significant digits keep the 1e-9 tolerance');
});

// ── Sizes, frame rate and kittens ────────────────────────────────────────────
const DRAWN = PHASES.filter(p => INFO[p].drawn);
const fps = (phase, o = {}) => core.desktopFps({ phase, ...o });
const kits = n => Array.from({ length: n }, (_, i) => ({ id: 'k' + i, type: 'Explore', session: null, state: i === 0 ? 'approval' : 'working', born: i, last: i, until: null }));

test('the sizes: three frozen IDs at Ø48, Ø64 and Ø96, and anything else is medium', () => {
  assert.deepEqual(core.DESKTOP_SIZES, { small: 48, medium: 64, large: 96 });
  assert.deepEqual(core.DESKTOP_SIZE_IDS, ['small', 'medium', 'large']);
  assert.equal(core.DEFAULT_DESKTOP_SIZE, 'medium');
  for (const id of core.DESKTOP_SIZE_IDS) assert.equal(core.desktopSizeOf(id), id);
  for (const bad of ['Small', 'LARGE', ' large', 'large ', 'huge', 'tiny', '', '48', 48, 64, null, undefined, true, ['small'], {}, '__proto__', 'constructor', 'medium\n']) assert.equal(core.desktopSizeOf(bad), 'medium', String(JSON.stringify(bad)));
});

test('the frame rate: every row of the table', () => {
  assert.deepEqual(core.DESKTOP_FPS, { motion: 60, active: 20, idle: 5, asleep: .5, off: 0 });
  assert.equal(core.DESKTOP_NEAR, 150);
  // 60: dragging, flying, an emote, a kitten arriving or leaving, the dance.
  for (const flag of ['dragging', 'emote', 'kittenMotion', 'dance']) assert.equal(fps('onDesktop', { [flag]: true }), 60, flag);
  for (const p of PHASES.filter(p => INFO[p].flight)) assert.equal(fps(p), 60, `${p} flies`);
  // 20: an agent working, thinking or searching, or the cursor within 150 points.
  assert.equal(fps('onDesktop', { working: true }), 20);
  assert.equal(fps('onDesktop', { cursorDist: 0 }), 20);
  assert.equal(fps('onDesktop', { cursorDist: 150 }), 20, '150 points is near');
  assert.equal(fps('onDesktop', { cursorDist: 150.01 }), 5, 'a hair further is not');
  // 5: idle and awake. A still frame every 2 s asleep. Nothing when it cannot be seen.
  assert.equal(fps('onDesktop'), 5);
  assert.equal(fps('onDesktop', { cursorDist: 900 }), 5);
  assert.equal(fps('onDesktop', { asleep: true }), .5);
  assert.equal(fps('onDesktop', { hidden: true }), 0);
});

test('the frame rate: home, and the cat sitting in the notch, draw nothing on the desktop, whatever else is going on', () => {
  const all = { hidden: false, dragging: true, emote: true, kittenMotion: true, dance: true, asleep: true, working: true, cursorDist: 0 };
  for (const p of PHASES.filter(p => !INFO[p].drawn)) { assert.equal(fps(p), 0, p); assert.equal(fps(p, all), 0, p); }
  assert.deepEqual(PHASES.filter(p => !INFO[p].drawn), ['home', 'atNotchForAlert']);
  assert.equal(fps('home', { working: true, dance: true }), 0);
});

test('the frame rate: the order of the rules', () => {
  assert.equal(fps('onDesktop', { hidden: true, dragging: true, working: true }), 0, 'hidden beats everything, motion included');
  assert.equal(fps('flyingOut', { hidden: true }), 0, 'a flight under a fullscreen app is not drawn');
  assert.equal(fps('onDesktop', { dragging: true, asleep: true, working: true }), 60, 'motion beats sleep and work');
  assert.equal(fps('onDesktop', { asleep: true, working: true, cursorDist: 10 }), .5, 'a sleeping cat does not watch the cursor');
  assert.equal(fps('onDesktop', { working: true, cursorDist: 10 }), 20);
  assert.equal(fps('retracting', { asleep: true }), 60, 'a flight is always 60');
});

test('the frame rate: only true counts, and input that is not input draws nothing', () => {
  for (const v of ['true', 1, 'yes', {}, [], null, undefined, 0, NaN]) for (const flag of ['hidden', 'dragging', 'emote', 'kittenMotion', 'dance', 'asleep', 'working'])
    assert.equal(fps('onDesktop', { [flag]: v }), 5, `${flag}: ${String(JSON.stringify(v))} is not true`);
  for (const d of ['10', null, undefined, NaN, Infinity, -Infinity, {}, [5], true]) assert.equal(fps('onDesktop', { cursorDist: d }), 5, `cursorDist ${String(d)}`);
  for (const bad of [null, undefined, 7, 'onDesktop', [], ['onDesktop'], {}, { phase: null }, { phase: 'Home' }, { phase: 'flying' }, { phase: ['onDesktop'] }, { phase: '__proto__' }, { phase: 'constructor' }]) assert.equal(core.desktopFps(bad), 0, String(JSON.stringify(bad)));
  assert.equal(core.desktopFps(Object.freeze({ phase: 'onDesktop' })), 5);
});

test('the frame rate: 6000 random inputs give one of the five rates, the same as the rules written as a table', () => {
  const r = core.rng(99), flags = ['hidden', 'dragging', 'emote', 'kittenMotion', 'dance', 'asleep', 'working'], phases = [...PHASES, 'nowhere', null], dists = [undefined, null, 0, 149.9, 150, 150.1, 5000, NaN, '3'];
  const rates = new Set([0, .5, 5, 20, 60]), pick = a => a[Math.floor(r() * a.length)];
  for (let n = 0; n < 6000; n++) {
    const i = { phase: pick(phases), cursorDist: pick(dists) };
    for (const f of flags) if (r() < .3) i[f] = r() < .85;
    const got = core.desktopFps(i);
    assert.ok(rates.has(got), JSON.stringify(i));
    const drawn = PHASES.includes(i.phase) && INFO[i.phase].drawn && i.hidden !== true;
    const motion = drawn && (INFO[i.phase].flight || i.dragging === true || i.emote === true || i.kittenMotion === true || i.dance === true);
    const near = typeof i.cursorDist === 'number' && Number.isFinite(i.cursorDist) && i.cursorDist <= 150;
    const want = !drawn ? 0 : motion ? 60 : i.asleep === true ? .5 : (i.working === true || near) ? 20 : 5;
    assert.equal(got, want, JSON.stringify(i));
  }
});

test('the desktop kittens: the slots at the three sizes, with 0, 1, 3 and 8 kittens', () => {
  const P = core.DESKTOP_KITTEN_PLACE;
  assert.deepEqual(P, { unit: 'D', max: 3, d: .3, x0: .82, y0: .22, step: .33, moreSize: .2 });
  for (const n of [0, 1, 3, 8]) {
    const s = core.desktopKittenSlots(kits(n));
    assert.deepEqual(Object.keys(s), ['place', 'unit', 'count', 'shown', 'more', 'moreAt', 'label']);
    assert.equal(s.place, 'desktop'); assert.equal(s.unit, 'D'); assert.equal(s.count, n); assert.equal(s.label, null);
    assert.equal(s.shown.length, Math.min(n, 3), `${n} kittens`);
    assert.equal(s.more, Math.max(0, n - 3));
    s.shown.forEach((q, i) => { assert.equal(q.id, 'k' + i); near(q.x, P.x0 + i * P.step, 'x'); assert.equal(q.y, P.y0); assert.equal(q.d, P.d); });
    if (n > 3) { near(s.moreAt.x, P.x0 + 3 * P.step, '"+N" x'); assert.equal(s.moreAt.y, P.y0); assert.equal(s.moreAt.size, P.moreSize); } else assert.equal(s.moreAt, null);
    // The numbers are multiples of the head width, so each size is the same layout scaled: Ø48 kittens are 14.4 points across, Ø64 19.2 and Ø96 28.8.
    for (const [id, d] of Object.entries(core.DESKTOP_SIZES)) s.shown.forEach(q => { near(q.d * d, { small: 14.4, medium: 19.2, large: 28.8 }[id], `${id} kitten`); assert.ok(q.x * d > d / 2, 'a kitten stands beside the head, not on it'); });
  }
  assert.equal(core.desktopKittenSlots(kits(8)).shown[0].state, 'approval', 'the state travels with the kitten');
});

test('the desktop kittens: the left side is the right side mirrored, and any other side is the right', () => {
  for (const n of [0, 1, 3, 8]) {
    const R = core.desktopKittenSlots(kits(n), 1), L = core.desktopKittenSlots(kits(n), -1);
    R.shown.forEach((q, i) => { near(L.shown[i].x, -q.x, 'x'); assert.equal(L.shown[i].y, q.y); assert.equal(L.shown[i].d, q.d); });
    if (R.moreAt) { near(L.moreAt.x, -R.moreAt.x, '"+N" x'); assert.equal(L.moreAt.y, R.moreAt.y); } else assert.equal(L.moreAt, null);
  }
  for (const side of [undefined, null, 0, 2, -2, '-1', 'left', NaN, true, [-1], {}]) assert.deepEqual(core.desktopKittenSlots(kits(4), side), core.desktopKittenSlots(kits(4), 1), String(JSON.stringify(side)));
});

test('the desktop kittens: clear of the badge and of the head and ruff, on every coat at every size', () => {
  for (const id of core.CAT_IDS) for (const d of Object.values(core.DESKTOP_SIZES)) {
    const p = core.PRESETS[id], s = core.newPose(); s.badgeS = 1;
    const L = core.layout(p, s, 0, 0, d, { badgeSide: 1 }), ruff = p.ruff ? p.ruff.rx * L.R : 0, badge = { x: L.badge.x, y: L.badge.y, r: .3 * L.R }, slots = core.desktopKittenSlots(kits(4));
    for (const q of [...slots.shown, { ...slots.moreAt, d: slots.moreAt.size }]) {
      const x = q.x * d, y = q.y * d, r = q.d * d / 2;
      assert.ok(x - r > Math.max(L.rx, ruff) + .02 * d, `${id} Ø${d}: a kitten overlaps the head or the ruff`);
      assert.ok(Math.hypot(x - badge.x, y - badge.y) > r + badge.r + .02 * d, `${id} Ø${d}: a kitten touches the badge`);
    }
  }
});

test('the desktop kittens: B\'s tables are untouched, and what is not a kitten is skipped', () => {
  assert.deepEqual(Object.keys(core.KITTEN_PLACES), ['bigExpanded', 'bigCompact', 'pairCompact', 'pairExpanded', 'pill']);
  assert.equal(core.kittenSlots('desktop', kits(2)).shown.length, 0, 'kittenSlots does not know the desktop place');
  const list = [kits(1)[0], null, 7, 'k', { id: '' }, { id: 5 }, { state: 'working' }, [], { id: 'ok', state: 7 }];
  const s = core.desktopKittenSlots(list);
  assert.deepEqual(s.shown.map(q => q.id), ['k0', 'ok']);
  assert.equal(s.shown[1].state, 'working', 'a state that is not text counts as working');
  for (const bad of [null, undefined, 'k0', 7, {}, { length: 2 }]) assert.deepEqual(core.desktopKittenSlots(bad).shown, [], String(JSON.stringify(bad)));
  const frozen = Object.freeze(kits(4).map(Object.freeze));
  assert.doesNotThrow(() => core.desktopKittenSlots(frozen, -1));
});

test('desktop-cases.json: the sizes and the frame-rate table replay, every row of the spec\'s table is there', () => {
  assert.deepEqual(fx.sizes, core.DESKTOP_SIZES);
  assert.deepEqual(fx.sizeIds, core.DESKTOP_SIZE_IDS);
  assert.equal(fx.defaultSize, 'medium');
  for (const c of fx.sizeCases) assert.equal(core.desktopSizeOf(c.raw), c.out, JSON.stringify(c.raw));
  assert.deepEqual(fx.fps, core.DESKTOP_FPS);
  assert.equal(fx.near, 150);
  for (const c of fx.fpsCases) assert.equal(core.desktopFps(c.input), c.out, c.name);
  const rate = name => fx.fpsCases.find(c => c.name === name).out;
  assert.equal(rate('home, nothing going on'), 0);
  assert.equal(rate('dragging'), 60); assert.equal(rate('an emote'), 60); assert.equal(rate('a kitten arriving or leaving'), 60); assert.equal(rate('the dance'), 60); assert.equal(rate('flyingOut, nothing going on'), 60);
  assert.equal(rate('an agent working'), 20); assert.equal(rate('the cursor exactly 150 points away'), 20); assert.equal(rate('the cursor 150.01 points away'), 5);
  assert.equal(rate('idle and awake'), 5); assert.equal(rate('asleep'), .5); assert.equal(rate('hidden: the screen is asleep, locked or covered'), 0);
  assert.deepEqual([...new Set(fx.fpsCases.map(c => c.out))].sort((a, b) => a - b), [0, .5, 5, 20, 60], 'all five rates occur');
});

test('desktop-cases.json: the kitten slots replay, and the same layout at each size is a multiple of the head width', () => {
  assert.deepEqual(fx.kittenPlace, core.DESKTOP_KITTEN_PLACE);
  for (const c of fx.kittenSlots) assert.deepEqual(compare(roundTrip(core.desktopKittenSlots(c.kittens, c.side)), c.out), [], c.name);
  assert.deepEqual(fx.kittenSlots.filter(c => /^\d+ kittens/.test(c.name)).map(c => c.out.shown.length), [0, 0, 1, 1, 2, 2, 3, 3, 3, 3, 3, 3]);
  assert.deepEqual(fx.kittenSlots.filter(c => /^(0|1|3|8) kittens/.test(c.name)).map(c => c.out.count), [0, 0, 1, 1, 3, 3, 8, 8]);
  assert.equal(fx.kittenSizes.length, 12);
  for (const c of fx.kittenSizes) {
    assert.equal(core.DESKTOP_SIZES[c.size], c.d, c.size);
    const s = core.desktopKittenSlots(fx.kittenSlots.find(r => r.name === `${c.count} kittens, side 1`).kittens);
    assert.deepEqual(compare(roundTrip(c.shown.map(q => ({ id: q.id, state: q.state, x: q.x / c.d, y: q.y / c.d, d: q.d / c.d }))), s.shown), [], `${c.size} ${c.count}`);
    assert.equal(c.more, s.more);
  }
  assert.deepEqual(compare(fx.kittenSizes.find(c => c.size === 'small' && c.count === 3).shown.map(q => q.d), [14.4, 14.4, 14.4]), []);
  assert.deepEqual(compare(fx.kittenSizes.find(c => c.size === 'large' && c.count === 8).moreAt, { x: 96 * (.82 + .99), y: 96 * .22, size: 96 * .2 }), []);
});

// ── Spots on the screens ─────────────────────────────────────────────────────
// A 14-inch laptop (menu bar 37 points, the Dock 70 at the bottom), a monitor to its right whose top is 100 points higher, and one to its left.
const LAPTOP = { frame: { x: 0, y: 0, w: 1512, h: 982 }, visible: { x: 0, y: 37, w: 1512, h: 875 }, main: true };
const MONITOR = { frame: { x: 1512, y: -100, w: 2560, h: 1440 }, visible: { x: 1512, y: -100, w: 2560, h: 1415 } };
const LEFT = { frame: { x: -1920, y: 0, w: 1920, h: 1080 }, visible: { x: -1920, y: 0, w: 1920, h: 1080 } };
const SIZES = Object.entries(core.DESKTOP_SIZES);
const inset = d => 24 + d / 2;

test('the spot constants: a 24 point margin, a default right of centre and a third down, 32 arrangements', () => {
  assert.equal(core.DESKTOP_MARGIN, 24);
  assert.deepEqual(core.DESKTOP_DEFAULT, { x: .6, y: 1 / 3 });
  assert.equal(core.MAX_DESKTOP_SPOTS, 32);
});

test('screenKey: the frames, rounded, sorted, in one string, and the order the screens come in does not matter', () => {
  assert.equal(core.screenKey([LAPTOP]), '0,0,1512,982');
  assert.equal(core.screenKey([LAPTOP, MONITOR]), '0,0,1512,982|1512,-100,2560,1440');
  assert.equal(core.screenKey([MONITOR, LAPTOP]), core.screenKey([LAPTOP, MONITOR]));
  assert.equal(core.screenKey([LEFT, MONITOR, LAPTOP]), '-1920,0,1920,1080|0,0,1512,982|1512,-100,2560,1440');
  const all = [LEFT, LAPTOP, MONITOR], perms = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]];
  assert.equal(new Set(perms.map(p => core.screenKey(p.map(i => all[i])))).size, 1, 'six orders, one key');
  assert.notEqual(core.screenKey([LAPTOP]), core.screenKey([LAPTOP, MONITOR]), 'a laptop alone and a laptop with a monitor are two arrangements');
  assert.notEqual(core.screenKey([LAPTOP, MONITOR]), core.screenKey([LAPTOP, { ...MONITOR, frame: { ...MONITOR.frame, y: 0 } }]), 'and so are two places for the same monitor');
});

test('screenKey: only the frames count, fractions round half up, and what is not a screen is left out', () => {
  assert.equal(core.screenKey([{ ...LAPTOP, visible: { x: 0, y: 25, w: 1512, h: 800 }, main: false }]), '0,0,1512,982', 'the Dock and the main flag are not part of the key');
  assert.equal(core.screenKey([{ frame: { x: .4, y: -.4, w: 1511.5, h: 981.49 } }]), '0,0,1512,981');
  assert.equal(core.screenKey([{ frame: { x: -.5, y: 2.5, w: 100.5, h: 100.4 } }]), '0,3,101,100', 'half rounds up, towards plus infinity, also below zero');
  assert.equal(core.screenKey([{ frame: { x: .3, y: 9, w: 100, h: 100 } }, { frame: { x: .4, y: 5, w: 100, h: 100 } }]), '0,5,100,100|0,9,100,100', 'sorted after the rounding, not before');
  assert.equal(core.screenKey([LAPTOP, LAPTOP]), '0,0,1512,982|0,0,1512,982', 'mirrored screens are two frames');
  for (const bad of [null, undefined, 'screens', 7, {}, [], [null], [7], [{}], [{ frame: null }], [{ frame: { x: 0, y: 0, w: 0, h: 100 } }], [{ frame: { x: 0, y: 0, w: 100, h: -5 } }], [{ frame: { x: 0, y: 0, w: .4, h: 100 } }],
    [{ frame: { x: '0', y: 0, w: 100, h: 100 } }], [{ frame: { x: NaN, y: 0, w: 100, h: 100 } }], [{ frame: { x: 0, y: 0, w: Infinity, h: 100 } }], [{ frame: { x: 2e6, y: 0, w: 100, h: 100 } }], [{ x: 0, y: 0, w: 100, h: 100 }]])
    assert.equal(core.screenKey(bad), '', String(JSON.stringify(bad)));
  assert.equal(core.screenKey([null, LAPTOP, 7, { frame: 1 }]), '0,0,1512,982', 'the good ones stay');
  const many = Array.from({ length: 40 }, (_, i) => ({ frame: { x: i * 100, y: 0, w: 100, h: 100 } }));
  assert.equal(core.screenKey(many).split('|').length, 16, 'at most sixteen');
  assert.equal(core.screenKey(many), core.screenKey([...many].reverse()));
});

test('isScreenKey: exactly what screenKey writes', () => {
  const r = core.rng(5);
  for (let i = 0; i < 300; i++) {
    const n = 1 + Math.floor(r() * 4), S = Array.from({ length: n }, () => ({ frame: { x: Math.round(r() * 8000 - 4000), y: Math.round(r() * 4000 - 2000), w: 1 + Math.round(r() * 5000), h: 1 + Math.round(r() * 3000) } }));
    assert.ok(core.isScreenKey(core.screenKey(S)), core.screenKey(S));
  }
  assert.ok(core.isScreenKey('0,0,1512,982') && core.isScreenKey('-1920,0,1920,1080|0,0,1512,982'));
  for (const bad of ['', '0,0,1512', '0,0,1512,982,1', '0,0,1512,982|', '|0,0,1512,982', '0,0,1512,982\n', ' 0,0,1512,982', '0,0,1512,982 ', '00,0,1512,982', '-0,0,1512,982', '0,0,0,982', '0,0,1512,0', '0,0,-1512,982', '1512,0,10,10|0,0,10,10',
    '0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10|0,0,10,10', '0,0,10000000,10', '1.5,0,10,10', '0x1,0,10,10',
    '__proto__', 'constructor', 'prototype', null, undefined, 7, [], ['0,0,1512,982'], {}])
    assert.ok(!core.isScreenKey(bad), String(JSON.stringify(bad)));
});

test('clampSpot: each edge of a laptop, at each size, keeps the cat 24 points from the visible frame (never under the menu bar or the Dock)', () => {
  for (const [id, d] of SIZES) {
    const m = inset(d), c = (x, y) => core.clampSpot({ x, y }, [LAPTOP], id);
    assert.deepEqual(c(0, 400), { x: m, y: 400 }, `${id} left`);
    assert.deepEqual(c(1511, 400), { x: 1512 - m, y: 400 }, `${id} right`);
    assert.deepEqual(c(700, 5), { x: 700, y: 37 + m }, `${id} in the menu bar: below it`);
    assert.deepEqual(c(700, 37), { x: 700, y: 37 + m }, `${id} at the menu bar's lower edge`);
    assert.deepEqual(c(700, 970), { x: 700, y: 37 + 875 - m }, `${id} in the Dock: above it`);
    assert.deepEqual(c(0, 0), { x: m, y: 37 + m }, `${id} top left corner`);
    assert.deepEqual(c(1511, 981), { x: 1512 - m, y: 912 - m }, `${id} bottom right corner`);
    assert.deepEqual(c(700, 400), { x: 700, y: 400 }, `${id}: a spot that is fine stays`);
  }
  assert.deepEqual(core.clampSpot({ x: -50, y: 400 }, [LAPTOP], 'small'), core.defaultDesktopSpot([LAPTOP], 'small'), 'a point outside every frame is on no screen: see below');
  assert.deepEqual(core.clampSpot({ x: 5, y: 5 }, [LAPTOP]), { x: 56, y: 93 }, 'no size is medium');
  assert.deepEqual(core.clampSpot({ x: 5, y: 5 }, [LAPTOP], 'huge'), { x: 56, y: 93 }, 'a size that is not a size is medium');
});

test('clampSpot: a Dock on the side, a menu bar that is gone, and a screen too small for the cat', () => {
  const side = { frame: { x: 0, y: 0, w: 1440, h: 900 }, visible: { x: 80, y: 25, w: 1360, h: 875 }, main: true };
  assert.deepEqual(core.clampSpot({ x: 20, y: 400 }, [side], 'medium'), { x: 80 + 56, y: 400 }, 'a Dock on the left');
  const small = { frame: { x: 0, y: 0, w: 100, h: 90 }, visible: { x: 0, y: 10, w: 100, h: 80 }, main: true };
  assert.deepEqual(core.clampSpot({ x: 90, y: 5 }, [small], 'medium'), { x: 50, y: 50 }, 'a visible frame smaller than the cat and its margins holds the centre');
  assert.deepEqual(core.clampSpot({ x: 90, y: 5 }, [small], 'small'), { x: 100 - 48, y: 10 + 40 }, 'the small size fits across the 100 points, but not down the 80');
  const novis = { frame: { x: 0, y: 0, w: 800, h: 600 } };
  assert.deepEqual(core.clampSpot({ x: 0, y: 0 }, [novis], 'small'), { x: 48, y: 48 }, 'no visible frame: the frame');
  const outside = { frame: { x: 0, y: 0, w: 800, h: 600 }, visible: { x: 900, y: 900, w: 50, h: 50 } };
  assert.deepEqual(core.clampSpot({ x: 0, y: 0 }, [outside], 'small'), { x: 48, y: 48 }, 'a visible frame outside the frame is the frame');
  const wide = { frame: { x: 0, y: 0, w: 800, h: 600 }, visible: { x: -100, y: -100, w: 2000, h: 2000 } };
  assert.deepEqual(core.clampSpot({ x: 799, y: 599 }, [wide], 'small'), { x: 800 - 48, y: 600 - 48 }, 'a visible frame that sticks out is held inside the frame');
});

test('clampSpot: two screens, one gone, and a spot in the gap between them', () => {
  const m = inset(64), two = [LAPTOP, MONITOR];
  assert.deepEqual(core.clampSpot({ x: 1600, y: -90 }, two, 'medium'), { x: 1600, y: -100 + m }, 'near the top of the monitor, which starts higher than the laptop');
  assert.deepEqual(core.clampSpot({ x: 1600, y: 10 }, two, 'medium'), { x: 1600, y: 10 }, 'the same spot lower down is fine');
  assert.deepEqual(core.clampSpot({ x: 1511.9, y: 400 }, two, 'medium'), { x: 1512 - m, y: 400 }, 'the last point of the laptop is the laptop');
  assert.deepEqual(core.clampSpot({ x: 1512, y: 400 }, two, 'medium'), { x: 1512 + m, y: 400 }, 'the first point of the monitor is the monitor');
  assert.deepEqual(core.clampSpot({ x: 1600, y: 1300 }, two, 'medium'), { x: 1600, y: -100 + 1415 - m }, 'the monitor\'s Dock');
  // The monitor is unplugged: a spot on it is on no screen, so it goes to the main screen's default spot.
  const dflt = core.defaultDesktopSpot([LAPTOP], 'medium');
  assert.deepEqual(core.clampSpot({ x: 3000, y: 500 }, [LAPTOP], 'medium'), dflt, 'the screen is gone');
  assert.deepEqual(core.clampSpot({ x: -10, y: 500 }, [LAPTOP], 'medium'), dflt, 'left of the only screen');
  assert.deepEqual(core.clampSpot({ x: 700, y: 5000 }, [LAPTOP], 'medium'), dflt, 'far below it');
  const gap = [LAPTOP, { frame: { x: 1700, y: 0, w: 800, h: 600 } }];
  assert.deepEqual(core.clampSpot({ x: 1600, y: 300 }, gap, 'medium'), core.defaultDesktopSpot(gap, 'medium'), 'a gap between two screens is no screen');
  assert.deepEqual(core.clampSpot({ x: -1000, y: 500 }, [LEFT, LAPTOP], 'medium'), { x: -1000, y: 500 }, 'a screen to the left, at negative coordinates');
  assert.deepEqual(core.clampSpot({ x: -1900, y: 20 }, [LEFT, LAPTOP], 'small'), { x: -1920 + 48, y: 48 });
  assert.equal(core.clampSpot({ x: 5, y: 5 }, [], 'medium'), null, 'no screens, no spot');
  assert.equal(core.clampSpot({ x: 5, y: 5 }, [null, {}, { frame: 7 }]), null);
});

test('clampSpot: a spot that is not a spot is the default spot, and the result is always a spot', () => {
  const dflt = core.defaultDesktopSpot([LAPTOP], 'large');
  for (const bad of [null, undefined, 7, 'x', [], [1, 2], {}, { x: 1 }, { x: '1', y: 2 }, { x: NaN, y: 2 }, { x: 1, y: Infinity }, { x: 1e6, y: 0 }]) assert.deepEqual(core.clampSpot(bad, [LAPTOP], 'large'), dflt, String(JSON.stringify(bad)));
  const r = core.rng(17), screens = [[LAPTOP], [LAPTOP, MONITOR], [LEFT, LAPTOP, MONITOR], [LAPTOP, { frame: { x: 1700, y: 0, w: 800, h: 600 } }]];
  for (let i = 0; i < 4000; i++) {
    const S = screens[i % 4], id = core.DESKTOP_SIZE_IDS[i % 3], d = core.DESKTOP_SIZES[id], p = { x: Math.round(r() * 8000 - 2500), y: Math.round(r() * 3500 - 800) };
    const c = core.clampSpot(p, S, id), home = S.map(s => s.visible || s.frame).find(v => c.x >= v.x + inset(d) - 1e-9 && c.x <= v.x + v.w - inset(d) + 1e-9 && c.y >= v.y + inset(d) - 1e-9 && c.y <= v.y + v.h - inset(d) + 1e-9);
    assert.ok(home, `${JSON.stringify(p)} ${id} gave ${JSON.stringify(c)}: not inside any screen's margins`);
    assert.deepEqual(core.clampSpot(c, S, id), c, 'clamping twice changes nothing');
  }
});

test('the default spot: right of centre, a third of the way down the main screen\'s visible frame, held inside its margins', () => {
  const d = core.defaultDesktopSpot([LAPTOP], 'medium');
  near(d.x, 907.2, 'x'); near(d.y, 37 + 875 / 3, 'y');
  assert.ok(d.x > 1512 / 2 && d.y > 37, 'right of the centre and below the notch');
  for (const [id] of SIZES) { const s = core.defaultDesktopSpot([LAPTOP], id); assert.deepEqual(core.clampSpot(s, [LAPTOP], id), s, `${id} is where it may sit`); }
  // The main screen: the one marked main, else the one at the origin, else the first.
  assert.deepEqual(core.defaultDesktopSpot([MONITOR, { ...LAPTOP, main: false }], 'medium'), core.defaultDesktopSpot([LAPTOP], 'medium'), 'the one at the origin');
  assert.notDeepEqual(core.defaultDesktopSpot([{ ...LAPTOP, main: false }, { ...MONITOR, main: true }], 'medium'), core.defaultDesktopSpot([LAPTOP], 'medium'), 'a screen marked main wins');
  assert.deepEqual(core.defaultDesktopSpot([LEFT, MONITOR], 'small'), core.defaultDesktopSpot([MONITOR, LEFT], 'small'), 'with none of them, the first by frame');
  assert.equal(core.defaultDesktopSpot([], 'medium'), null);
});

test('cleanDesktopSpots: an object or JSON text of screen keys to spots; anything else is dropped', () => {
  const key = core.screenKey([LAPTOP]), key2 = core.screenKey([LAPTOP, MONITOR]);
  const ok = { [key2]: { x: 2000, y: 300 }, [key]: { x: 700, y: 400 } };
  assert.deepEqual(core.cleanDesktopSpots(ok), ok);
  assert.deepEqual(Object.keys(core.cleanDesktopSpots(ok)), [key, key2].sort(), 'in code-point order');
  assert.deepEqual(core.cleanDesktopSpots(JSON.stringify(ok)), ok, 'as the JSON text the Mac stores');
  assert.deepEqual(core.cleanDesktopSpots({ [key]: { x: 1, y: 2, z: 3, name: 'x' } }), { [key]: { x: 1, y: 2 } }, 'only x and y are kept');
  for (const bad of [null, undefined, 7, true, [], [1], 'junk', '', '{"a":', "{'a':1}", '[]', 'null', '7', '{"a":1}x', {}, { cats: 1 }]) assert.deepEqual(core.cleanDesktopSpots(bad), {}, String(JSON.stringify(bad)));
  const keys = { '': { x: 1, y: 1 }, '0,0,0,0': { x: 1, y: 1 }, '00,0,100,100': { x: 1, y: 1 }, '0,0,100,100\n': { x: 1, y: 1 }, constructor: { x: 1, y: 1 }, prototype: { x: 1, y: 1 }, [key]: { x: 5, y: 5 } };
  assert.deepEqual(core.cleanDesktopSpots(keys), { [key]: { x: 5, y: 5 } });
  const spots = {}; for (const bad of [null, 7, 'x', [1, 2], {}, { x: 1 }, { x: '1', y: 2 }, { x: NaN, y: 2 }, { x: 1, y: 1e6 }, true]) spots[core.screenKey([{ frame: { x: Object.keys(spots).length, y: 0, w: 100, h: 100 } }])] = bad;
  assert.deepEqual(core.cleanDesktopSpots(spots), {}, 'a spot that is not a spot is dropped with its key');
  assert.deepEqual(core.cleanDesktopSpots(core.cleanDesktopSpots(ok)), ok);
});

test('cleanDesktopSpots: hostile files never throw, never pollute, and keep at most 32 arrangements', () => {
  const evil = JSON.parse('{"__proto__":{"x":1,"y":2},"0,0,100,100":{"__proto__":{"x":9},"x":3,"y":4}}');
  const out = core.cleanDesktopSpots(evil);
  assert.deepEqual(out, { '0,0,100,100': { x: 3, y: 4 } });
  assert.equal(Object.getPrototypeOf(out), Object.prototype); assert.equal({}.x, undefined);
  const many = Object.fromEntries(Array.from({ length: 300 }, (_, i) => [`${i},0,100,100`, { x: i, y: 1 }]));
  const cut = core.cleanDesktopSpots(many), keys = Object.keys(cut);
  assert.equal(keys.length, 32);
  assert.deepEqual(keys, Object.keys(many).filter(core.isScreenKey).sort().slice(0, 32), 'the first 32 by code-point order');
  assert.deepEqual(core.cleanDesktopSpots(JSON.stringify(many)), cut, 'and the same from JSON text');
  const raw = { '0,0,100,100': { x: 1, y: 2 } }, a = core.cleanDesktopSpots(raw), b = core.cleanDesktopSpots(raw);
  a['0,0,100,100'].x = 99; assert.equal(b['0,0,100,100'].x, 1); assert.equal(raw['0,0,100,100'].x, 1, 'nothing is shared with the input');
});

test('spotFor: the spot remembered for this arrangement, held where the cat may sit, else the default', () => {
  const k1 = core.screenKey([LAPTOP]), k2 = core.screenKey([LAPTOP, MONITOR]);
  const spots = { [k1]: { x: 300, y: 400 }, [k2]: { x: 2000, y: 800 } };
  assert.deepEqual(core.spotFor(spots, [LAPTOP], 'medium'), { x: 300, y: 400 }, 'a laptop alone');
  assert.deepEqual(core.spotFor(spots, [MONITOR, LAPTOP], 'medium'), { x: 2000, y: 800 }, 'with the monitor, whichever order the screens come in: its own spot');
  assert.deepEqual(core.spotFor({}, [LAPTOP], 'medium'), core.defaultDesktopSpot([LAPTOP], 'medium'), 'nothing remembered: the default spot');
  assert.deepEqual(core.spotFor(spots, [LEFT, LAPTOP], 'medium'), core.defaultDesktopSpot([LEFT, LAPTOP], 'medium'), 'an arrangement never seen');
  assert.deepEqual(core.spotFor({ [k1]: { x: 5, y: 5 } }, [LAPTOP], 'large'), { x: 72, y: 37 + 72 }, 'a remembered spot the Dock or menu bar now covers is held inside');
  assert.deepEqual(core.spotFor({ [k1]: { x: 5000, y: 5 } }, [LAPTOP], 'medium'), core.defaultDesktopSpot([LAPTOP], 'medium'), 'a remembered spot that is on no screen goes to the default');
  assert.deepEqual(core.spotFor(JSON.stringify(spots), [LAPTOP], 'medium'), { x: 300, y: 400 }, 'the Mac\'s JSON text');
  for (const bad of [null, 'junk', 7, [], { [k1]: 'x' }, { constructor: 1 }]) assert.deepEqual(core.spotFor(bad, [LAPTOP], 'medium'), core.defaultDesktopSpot([LAPTOP], 'medium'), String(JSON.stringify(bad)));
  assert.equal(core.spotFor(spots, [], 'medium'), null);
  assert.equal(core.spotFor(spots, 'screens', 'medium'), null);
});

test('rememberSpot: this arrangement\'s spot is the clamped one, the others stay, and a full map still keeps the new key', () => {
  const k1 = core.screenKey([LAPTOP]), k2 = core.screenKey([LAPTOP, MONITOR]);
  assert.deepEqual(core.rememberSpot({}, [LAPTOP], { x: 5, y: 5 }, 'medium'), { [k1]: { x: 56, y: 93 } }, 'clamped');
  const two = core.rememberSpot({ [k1]: { x: 300, y: 400 } }, [LAPTOP, MONITOR], { x: 2000, y: 800 }, 'medium');
  assert.deepEqual(two, { [k1]: { x: 300, y: 400 }, [k2]: { x: 2000, y: 800 } }, 'the laptop alone keeps its own spot');
  assert.deepEqual(core.rememberSpot(two, [LAPTOP], { x: 600, y: 600 }, 'medium')[k2], { x: 2000, y: 800 });
  assert.deepEqual(core.rememberSpot(two, [LAPTOP], { x: 600, y: 600 }, 'medium')[k1], { x: 600, y: 600 });
  assert.deepEqual(core.rememberSpot({ [k1]: { x: 1, y: 1 } }, [LAPTOP], { x: 9000, y: 9000 }, 'medium')[k1], core.defaultDesktopSpot([LAPTOP], 'medium'), 'a spot on no screen is remembered as the default');
  assert.deepEqual(core.rememberSpot(two, [], { x: 5, y: 5 }, 'medium'), two, 'no screens: nothing changes');
  const full = Object.fromEntries(Array.from({ length: 32 }, (_, i) => [`${i},0,100,100`, { x: i, y: 1 }]));
  const grown = core.rememberSpot(full, [LAPTOP], { x: 600, y: 600 }, 'medium');
  assert.equal(Object.keys(grown).length, 32); assert.deepEqual(grown[k1], { x: 600, y: 600 }, 'the new arrangement is kept, an old one makes room');
  assert.deepEqual(Object.keys(grown), Object.keys(grown).slice().sort());
  const frozen = Object.freeze({ [k1]: Object.freeze({ x: 1, y: 1 }) });
  assert.doesNotThrow(() => core.rememberSpot(frozen, [LAPTOP], { x: 100, y: 200 }, 'small'));
});

test('desktop-cases.json: the spot constants and the screen keys replay, in every order', () => {
  assert.equal(fx.margin, 24); assert.deepEqual(compare(fx.defaultSpot, core.DESKTOP_DEFAULT), []); assert.equal(fx.maxSpots, 32);
  for (const c of fx.screenKeys) assert.equal(core.screenKey(c.screens), c.out, c.name);
  for (const c of fx.isScreenKey) assert.equal(core.isScreenKey(c.key), c.out, JSON.stringify(c.key));
  const named = n => fx.screenKeys.find(c => c.name === n).out;
  assert.equal(named('a laptop and a monitor to its right'), named('the same, the other way round'));
  assert.equal(named('a monitor on each side'), named('the same, in another order'));
  assert.equal(named('a monitor on each side'), named('and another'));
  assert.equal(named('the Dock moved: the same key'), named('a laptop'));
  assert.equal(named('no visible frame: the same key'), named('a laptop'));
  assert.equal(named('nothing'), ''); assert.equal(named('null'), '');
  assert.ok(fx.isScreenKey.filter(c => c.out).length >= 3 && fx.isScreenKey.filter(c => !c.out).length >= 20);
});

test('desktop-cases.json: the clamps replay, on each edge of each size, with two screens and one gone', () => {
  for (const c of fx.clamps) assert.deepEqual(compare(roundTrip(core.clampSpot(c.spot, c.screens, c.size)), c.out), [], c.name);
  assert.equal(fx.clamps.filter(c => /^(small|medium|large): /.test(c.name)).length, 24, 'eight spots at each of the three sizes');
  const at = n => fx.clamps.find(c => c.name === n).out;
  assert.deepEqual(at('medium: on the left edge'), { x: 56, y: 400 }); assert.deepEqual(at('medium: in the menu bar'), { x: 700, y: 93 }); assert.deepEqual(at('large: in the Dock'), { x: 700, y: 840 });
  assert.deepEqual(compare(at('the monitor is unplugged: the spot is on no screen'), core.defaultDesktopSpot([fx.clamps[0].screens[0]], 'medium')), []);
  assert.equal(at('no screens'), null); assert.equal(at('screens that are not screens'), null);
  assert.ok(fx.clamps.every(c => c.out === null || ['x', 'y'].every(k => Number.isInteger(c.out[k] * 2) || Math.abs(c.out[k]) < 1000)), 'a fraction comes only below 1000 points, where 12 significant digits keep the 1e-9 tolerance');
});

test('desktop-cases.json: the default spots, the spot per arrangement and what is remembered replay', () => {
  for (const c of fx.defaultSpots) assert.deepEqual(compare(roundTrip(core.defaultDesktopSpot(c.screens, c.size)), c.out), [], c.name);
  for (const c of fx.spotFor) assert.deepEqual(compare(roundTrip(core.spotFor(c.spots, c.screens, c.size)), c.out), [], c.name);
  for (const c of fx.remembers) assert.deepEqual(compare(roundTrip(core.rememberSpot(c.spots, c.screens, c.spot, c.size)), c.out), [], c.name);
  for (const c of fx.spotMaps) assert.deepEqual(compare(roundTrip(core.cleanDesktopSpots(c.raw)), c.out), [], c.name);
  assert.equal(fx.defaultSpots.find(c => c.name === 'no screens').out, null);
  assert.equal(Object.keys(fx.spotMaps.find(c => c.name.startsWith('33 keep')).out).length, 32);
  assert.equal(Object.keys(fx.spotMaps.find(c => c.name === 'bad values drop before the 32 cap counts').out).length, 32);
  assert.equal(Object.keys(fx.remembers.find(c => c.name === 'a full map makes room for the new arrangement').out).length, 32);
  assert.ok(fx.spotFor.find(c => c.name.startsWith('a laptop alone')).out.x !== fx.spotFor.find(c => c.name.startsWith('with the monitor')).out.x, 'two arrangements, two spots');
});

// ── The stored settings ──────────────────────────────────────────────────────
const KEY = '0,0,1512,982', KEY2 = '0,0,1512,982|1512,-100,2560,1440';
const DESKTOP_DEFAULTS = { on: false, size: 'medium', spots: {} };
const deepFreeze = v => { if (v && typeof v === 'object') { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };
const NOT_OBJECTS = [null, undefined, 'junk', '', 7, 0, NaN, true, false, [], [1, 2], ['on']];

test('a fresh install: at home, Medium, no spots; every call gives fresh objects', () => {
  const d = core.defaultDesktopSettings();
  assert.deepEqual(Object.keys(d), ['on', 'size', 'spots']);
  assert.deepEqual(d, DESKTOP_DEFAULTS);
  assert.deepEqual(core.cleanDesktopSettings(null), d);
  d.spots.x = 1; d.size = 'large';
  assert.deepEqual(core.defaultDesktopSettings(), DESKTOP_DEFAULTS, 'changing a result never changes the next one');
  for (const raw of [...NOT_OBJECTS, {}, { on: 7, size: 7, spots: 7 }]) assert.deepEqual(core.cleanDesktopSettings(raw), DESKTOP_DEFAULTS, String(JSON.stringify(raw)));
});

test('a valid value comes back as it went in, from an object, from JSON, and with the Mac\'s text for the spots', () => {
  const valid = { on: true, size: 'large', spots: { [KEY2]: { x: 2000, y: 800 }, [KEY]: { x: 300, y: 400 } } };
  const clean = core.cleanDesktopSettings(valid);
  assert.deepEqual(clean, valid);
  assert.deepEqual(Object.keys(clean.spots), [KEY, KEY2].sort(), 'the spots in code-point order');
  assert.deepEqual(core.cleanDesktopSettings(clean), clean, 'cleaning twice changes nothing');
  assert.deepEqual(core.cleanDesktopSettings(JSON.parse(JSON.stringify(valid))), clean, 'written as JSON and read back');
  assert.deepEqual(core.cleanDesktopSettings({ ...valid, spots: JSON.stringify(valid.spots) }), clean, 'cat.desktop.spots is JSON text on the Mac');
});

test('on is true only for the boolean true, and the size is one of the three IDs', () => {
  assert.equal(core.cleanDesktopSettings({ on: true }).on, true);
  for (const bad of ['true', 'on', 'yes', 1, -1, 0, null, undefined, [], [true], {}, { on: true }, 'TRUE']) assert.equal(core.cleanDesktopSettings({ on: bad }).on, false, String(JSON.stringify(bad)));
  for (const id of core.DESKTOP_SIZE_IDS) assert.equal(core.cleanDesktopSettings({ size: id }).size, id);
  for (const bad of ['Small', 'LARGE', ' large', 'huge', 'xl', '', '48', '96', 48, 96, null, undefined, true, ['large'], {}, '__proto__', 'constructor', 'large\n']) assert.equal(core.cleanDesktopSettings({ size: bad }).size, 'medium', String(JSON.stringify(bad)));
});

test('the spots: text that is not JSON, wrong types and keys that are not screens are dropped, whole or one by one', () => {
  for (const bad of ['{"0,0,100,100":', "{'0,0,100,100':{'x':1,'y':2}}", '{"0,0,100,100":{"x":1,"y":2},}', '{"0,0,100,100":{"x":1,"y":2}} x', 'null', '[]', '7', '"x"', 'junk', '', null, 7, true, [], [{ x: 1, y: 2 }]])
    assert.deepEqual(core.cleanDesktopSettings({ on: true, size: 'small', spots: bad }), { on: true, size: 'small', spots: {} }, String(JSON.stringify(bad)));
  const out = core.cleanDesktopSettings({ spots: { [KEY]: { x: 1, y: 2 }, nonsense: { x: 3, y: 4 }, '0,0,100,100': { x: NaN, y: 4 }, '1,1,100,100': { x: '5', y: 6 }, '2,2,100,100': [7, 8], '3,3,100,100': { x: 1e6, y: 0 } } });
  assert.deepEqual(out.spots, { [KEY]: { x: 1, y: 2 } });
});

test('hostile files never throw, never pollute, and keep at most 32 arrangements', () => {
  const evil = JSON.parse('{"on":true,"__proto__":{"on":false},"size":"large","spots":{"__proto__":{"x":1,"y":2},"constructor":{"x":1,"y":2},"0,0,100,100":{"x":3,"y":4,"__proto__":{"x":9}}}}');
  const out = core.cleanDesktopSettings(evil);
  assert.deepEqual(out, { on: true, size: 'large', spots: { '0,0,100,100': { x: 3, y: 4 } } });
  assert.equal(Object.getPrototypeOf(out.spots), Object.prototype); assert.equal({}.x, undefined); assert.equal({}.on, undefined);
  const many = Object.fromEntries(Array.from({ length: 300 }, (_, i) => [`${i},0,100,100`, { x: i, y: i }]));
  assert.equal(Object.keys(core.cleanDesktopSettings({ spots: many }).spots).length, 32);
  assert.deepEqual(core.cleanDesktopSettings({ spots: JSON.stringify(many) }), core.cleanDesktopSettings({ spots: many }));
  const raw = deepFreeze({ on: true, size: 'small', spots: { [KEY]: { x: 1, y: 2 } } });
  assert.doesNotThrow(() => core.cleanDesktopSettings(raw));
  const a = core.cleanDesktopSettings(raw), b = core.cleanDesktopSettings(raw);
  a.spots[KEY].x = 99; assert.equal(b.spots[KEY].x, 1, 'nothing is shared between results');
});

test('the Cat settings, the Display settings and these are three clean-ups of one stored block: none sees the others\' keys', () => {
  const block = { character: 'momo', collar: 'band', displayMode: 'two', pair: ['momo', 'ginger'], desktop: { on: true, size: 'large', spots: { [KEY]: { x: 1, y: 2 } } } };
  assert.deepEqual(core.cleanCatSettings(block), core.cleanCatSettings({ character: 'momo', collar: 'band' }), 'the Cat settings drop the desktop block');
  assert.deepEqual(core.cleanDisplaySettings(block), core.cleanDisplaySettings({ displayMode: 'two', pair: ['momo', 'ginger'] }), 'and the Display settings');
  assert.deepEqual(core.cleanDesktopSettings(block), DESKTOP_DEFAULTS, 'the desktop clean-up reads the desktop object, not the block');
  assert.deepEqual(core.cleanDesktopSettings(block.desktop), block.desktop);
  assert.deepEqual(Object.keys(core.defaultCatSettings()), ['character', 'motionStyle', 'collar', 'furLines', 'cats']);
  assert.deepEqual(Object.keys(core.defaultDisplaySettings()), ['displayMode', 'pair', 'agentCats']);
});

test('hostile values never throw: 3000 random desktop settings come out valid, and cleaning them again changes nothing', () => {
  const r = core.rng(2028), pool = [true, false, 'true', 'large', 'small', 'Large', '', ' ', 0, 1, -1, 7, null, [], ['large'], {}, KEY, KEY2, '__proto__', 'constructor', { x: 1, y: 2 }, { x: 'a', y: 1 }, `{"${KEY}":{"x":1,"y":2}}`, '{"0,0', 'junk'];
  const pick = () => pool[Math.floor(r() * pool.length)];
  const valid = s => typeof s.on === 'boolean' && core.DESKTOP_SIZE_IDS.includes(s.size) && Object.keys(s.spots).length <= 32
    && Object.entries(s.spots).every(([k, v]) => core.isScreenKey(k) && Number.isFinite(v.x) && Number.isFinite(v.y) && Object.keys(v).join() === 'x,y') && JSON.stringify(Object.keys(s.spots)) === JSON.stringify(Object.keys(s.spots).sort());
  for (let i = 0; i < 3000; i++) {
    const map = r() < .2 ? pick() : Object.fromEntries(Array.from({ length: Math.floor(r() * 5) }, () => [pick(), pick()]).filter(([k]) => typeof k === 'string'));
    const raw = { on: pick(), size: pick(), spots: map }, out = core.cleanDesktopSettings(raw);
    assert.ok(valid(out), JSON.stringify(raw));
    assert.deepEqual(core.cleanDesktopSettings(out), out);
  }
});

test('desktop-cases.json: every settings case replays, and the inputs the spec worries about are in it', () => {
  assert.deepEqual(fx.settingsDefaults, DESKTOP_DEFAULTS);
  for (const c of fx.settingsCases) assert.deepEqual(compare(roundTrip(core.cleanDesktopSettings(c.raw)), c.out), [], c.name);
  const names = fx.settingsCases.map(c => c.name);
  for (const n of ['nothing stored', 'a fully valid value', 'on as text', 'on as the number 1', 'a size that is not a size', 'the spots as JSON text, as the Mac stores them', 'the spots as JSON text, cut off', 'prototype names as keys', 'spots that are not spots', 'three hundred arrangements keep the first 32', 'the Cat and Display settings are not desktop settings']) assert.ok(names.includes(n), n);
  const at = n => fx.settingsCases.find(c => c.name === n);
  assert.equal(Object.keys(at('three hundred arrangements keep the first 32').out.spots).length, 32);
  assert.equal(Object.keys(at('three hundred arrangements keep the first 32').raw.spots).length, 300);
  assert.deepEqual(at('three hundred as JSON text').out.spots, at('three hundred arrangements keep the first 32').out.spots, 'the same 32 from the Mac\'s text');
  assert.equal(at('on as text').out.on, false); assert.equal(at('a fully valid value').out.on, true);
  assert.deepEqual(at('prototype names as keys').out.spots, { '0,0,1512,982': { x: 2, y: 2 } });
  assert.ok(fx.settingsCases.filter(c => typeof c.raw === 'object' && c.raw && typeof c.raw.spots === 'string').length >= 6, 'text inputs for the spots');
});
