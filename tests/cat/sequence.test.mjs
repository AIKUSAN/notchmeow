import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const require = createRequire(import.meta.url);
const core = require('../../design/prototype/cat-core.js');
const load = name => JSON.parse(fs.readFileSync(new URL(`../fixtures/cat/${name}`, import.meta.url), 'utf8'));
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const clock = steps => steps.reduce((c, [t, st]) => core.workClockStep(c, st, t), { busySince: null, workedFor: 0 });
const MIN = 60000;

test('zoomies: 5 minutes of working, thinking or searching, counted until the agent finishes', () => {
  assert.equal(core.ZOOM_AFTER_MS, 5 * MIN);
  assert.equal(core.zoomiesOnFinish(clock([[0, 'working'], [5 * MIN - 1, 'finished']]).workedFor), false, 'one millisecond short');
  assert.equal(core.zoomiesOnFinish(clock([[0, 'working'], [5 * MIN, 'finished']]).workedFor), true, 'exactly 5 minutes');
  assert.equal(core.zoomiesOnFinish(clock([[0, 'thinking'], [5 * MIN, 'finished']]).workedFor), true, 'a run that starts at time 0 still counts');
  assert.equal(core.zoomiesOnFinish(clock([[1000, 'working'], [100000, 'thinking'], [200000, 'searching'], [301000, 'finished']]).workedFor), true, 'busy states chain');
  assert.equal(core.zoomiesOnFinish(12000, 12000), true, 'the prototype page passes its own 12 s threshold');
  assert.equal(core.zoomiesOnFinish(11999, 12000), false);
});

test('zoomies: approval and question pauses neither stop nor reset the clock; every other state ends the run', () => {
  for (const pause of ['approval', 'question']) assert.equal(core.zoomiesOnFinish(clock([[0, 'working'], [100000, pause], [250000, 'working'], [5 * MIN, 'finished']]).workedFor), true, pause);
  assert.equal(core.zoomiesOnFinish(clock([[0, 'working'], [10000, 'approval'], [290000, 'finished']]).workedFor), false, '4 min 50 s in total');
  const mid = clock([[0, 'working'], [100000, 'approval']]);
  assert.deepEqual(mid, { busySince: 0, workedFor: 0 }, 'the run stays open during an approval');
  for (const end of ['error', 'ratelimit', 'idle', 'sleeping', 'dizzy']) {
    const c = clock([[0, 'working'], [100000, end]]);
    assert.deepEqual(c, { busySince: null, workedFor: 100000 }, end);
    assert.equal(core.zoomiesOnFinish(clock([[0, 'working'], [100000, end], [110000, 'working'], [400000, 'finished']]).workedFor), false, `${end} resets: 290 s after it`);
  }
  assert.equal(clock([[5000, 'finished']]).workedFor, 0);
});

test('the work clock never goes negative and never mutates its input', () => {
  assert.equal(clock([[1000, 'working'], [500, 'finished']]).workedFor, 0);
  const c0 = { busySince: null, workedFor: 0 }, c1 = core.workClockStep(c0, 'working', 5);
  assert.deepEqual(c0, { busySince: null, workedFor: 0 }); assert.deepEqual(c1, { busySince: 5, workedFor: 0 });
  assert.deepEqual(core.workClockStep(c1, 'working', 99), c1, 'already busy: unchanged');
});

test('sleep: an idle cat sleeps after 10 minutes without an event, and nothing else ever sleeps', () => {
  assert.equal(core.SLEEP_AFTER_MS, 10 * MIN);
  assert.equal(core.sleepDelay('idle', 0), 10 * MIN);
  assert.equal(core.sleepDelay('idle', 10 * MIN - 1), 1);
  assert.equal(core.sleepDelay('idle', 10 * MIN), 0);
  assert.equal(core.sleepDelay('idle', 60 * MIN), 0);
  assert.equal(core.sleepDelay('idle', -5000), 10 * MIN, 'a clock that stepped back counts as just now');
  assert.equal(core.sleepDelay('idle', NaN), 10 * MIN);
  assert.equal(core.sleepDelay('idle', undefined), 10 * MIN);
  for (const st of core.STATES.filter(s => s !== 'idle')) for (const q of [0, 10 * MIN, 99 * MIN]) assert.equal(core.sleepDelay(st, q), null, `${st} at ${q}`);
  assert.equal(core.sleepDelay('bogus', 99 * MIN), null);
  for (const kind of ['hook', 'hover', 'click']) assert.equal(core.wakes(kind), true);
  for (const kind of ['scroll', 'key', '', undefined, null, 'Hook']) assert.equal(core.wakes(kind), false);
});

test('searching: the web, fetch, grep and glob tools of Claude Code, Gemini CLI and Codex', () => {
  assert.deepEqual(core.SEARCH_TOOLS.claude, ['WebSearch', 'WebFetch', 'Grep', 'Glob']);
  assert.deepEqual(core.SEARCH_TOOLS.gemini, ['google_web_search', 'web_fetch', 'grep_search', 'search_file_content', 'glob']);
  assert.deepEqual(core.SEARCH_TOOLS.codex, ['web_search', 'grep_files']);
  for (const t of Object.values(core.SEARCH_TOOLS).flat()) { assert.equal(core.isSearchTool(t), true, t); assert.equal(core.toolState(t), 'searching'); }
  for (const t of ['Bash', 'Read', 'Edit', 'Write', 'Task', 'LS', 'TodoWrite', 'AskUserQuestion', 'run_shell_command', 'read_file', 'apply_patch', 'websearch', 'WEBSEARCH', 'mcp__brave__web_search', '', null, undefined, 42, {}]) {
    assert.equal(core.isSearchTool(t), false, String(t)); assert.equal(core.toolState(t), 'working', String(t));
  }
  const all = Object.values(core.SEARCH_TOOLS).flat();
  assert.equal(new Set(all).size, all.length, 'no tool listed twice');
});

test('the greeting is Greeting v2 alone: the old timeline is gone and the length is still 5.74 s', () => {
  assert.deepEqual(Object.keys(core.GT), ['grow', 'badge', 'blink2', 'tint0', 'tint1', 'leave', 'COLLAPSE']);
  assert.deepEqual(Object.keys(core.GT2), ['fall0', 'land', 'bounce1', 'slide0', 'slide1', 'pop0', 'wave0', 'wave1', 'back0', 'back1', 'SLIDE']);
  near(core.GREET_LEN, 5.74);
  assert.equal(core.STREAKS.length, 16);
  near(core.streakTime(core.GT2.land - .1), 0);
});

test('the greeting starts on the notch, ends compact and never jumps', () => {
  const a = core.greetingPose(0), z = core.greetingPose(core.GREET_LEN);
  assert.deepEqual([a.iw, a.ih], [184, 32]); assert.ok(a.y < 0, 'the cat starts above the island');
  near(z.iw, 288); near(z.ih, 32); near(z.y, 16); near(z.x, 216); near(z.hb, 20 / 1.34); assert.equal(z.eye, 'dot');
  near(z.badge, 1); near(z.tint, .6); near(z.minis, 1); near(z.fx, 0); near(z.header, 0);
  let prev = core.greetingPose(0);
  for (let i = 1; i <= 5800 * 2; i++) {
    const p = core.greetingPose(i / 2000);
    assert.ok(Math.abs(p.x - prev.x) < 1 && Math.abs(p.y - prev.y) < 1 && Math.abs(p.iw - prev.iw) < 2, `a jump at ${i / 2000} s`); // (the paws snap up when the fall starts, by design)
    prev = p;
  }
  for (const t of [-1, 0, 2.5, 5, 5.74, 9]) for (const [k, v] of Object.entries(core.greetingPose(t))) if (typeof v === 'number') assert.ok(Number.isFinite(v), `${k} at ${t}`);
});

test('the greeting beats: land and squash, slide aside, pop up and wave, slide back and settle', () => {
  const G = core.GT2, at = t => core.greetingPose(t);
  assert.ok(at(G.land + .08).sy < .9 && at(G.land + .08).sx > 1.1, 'landing squash');
  assert.equal(at(G.land + .3).eye, 'happy');
  assert.ok(at(G.slide1).x > 320 + core.GT2.SLIDE * .99, 'slid aside by SLIDE');
  assert.equal(at(1.4).wave, -1);
  assert.ok(at(G.wave0 + .5).wave > 0.49 && at(G.wave0 + .5).wave < .51, 'the wave clock runs from wave0');
  assert.ok(at(2.2).handR > .9, 'the right paw is up while waving');
  assert.equal(at(G.pop0 + .3).eye, 'happy');
  near(at(G.back1 + .2).x, 320, 1e-6); assert.equal(at(G.back0 + .1).eye, 'content'); assert.equal(at(4).eye, 'dot');
  assert.ok(at(core.GT.badge + .4).badge > .99 && at(2).badge < .01, 'the badge pops in late');
});

test('a dropped file arcs from where it was dropped into the mouth over 380 ms', () => {
  assert.equal(core.FLIGHT_MS, 380);
  const from = { x: 200, y: 40 }, to = { x: 100, y: 120 };
  const f0 = core.flightAt(from, to, 30, 0), f1 = core.flightAt(from, to, 30, 1), fm = core.flightAt(from, to, 30, .5);
  near(f0.x, 200); near(f0.y, 40); near(f0.size, 18.6); near(f0.rot, .25);
  near(f1.x, 100); near(f1.y, 120); near(f1.size, 4.2); near(f1.rot, -.25);
  assert.ok(fm.y < 40, 'the arc rises above both ends (control point 60 px above the higher one)');
});

test('search-tools.json and sequence-cases.json replay from their inputs', () => {
  const st = load('search-tools.json');
  assert.deepEqual(st.agents, core.SEARCH_TOOLS);
  for (const c of st.cases) { assert.equal(core.isSearchTool(c.tool), c.searching, c.tool); assert.equal(core.toolState(c.tool), c.state, c.tool); }
  assert.ok(st.cases.some(c => c.tool === 'grep_search' && c.searching) && st.cases.some(c => c.tool === 'Bash' && !c.searching));

  const q = load('sequence-cases.json');
  near(q.greetingLengthS, core.GREET_LEN);
  assert.ok(q.greetingSamples.length >= 60);
  for (const s of q.greetingSamples) assert.deepEqual(compare(JSON.parse(JSON.stringify(core.greetingPose(s.tMs / 1000))), s.pose), [], `t = ${s.tMs} ms`);
  assert.equal(q.greetingStreaks.length, 16);
  for (const c of q.flight.cases) assert.deepEqual(compare(core.flightAt(c.from, c.to, c.R, c.k), c.out), []);
  assert.equal(q.zoomAfterMs, 300000);
  for (const sc of q.workClock) {
    let c = { busySince: null, workedFor: 0 };
    sc.steps.forEach(([t, st2], i) => { c = core.workClockStep(c, st2, t); assert.deepEqual(c, { busySince: sc.after[i].busySince, workedFor: sc.after[i].workedFor }, `${sc.name} step ${i}`); });
    assert.equal(sc.zoomiesAtFinish, sc.steps[sc.steps.length - 1][1] === 'finished' ? core.zoomiesOnFinish(c.workedFor) : null, sc.name);
  }
  assert.equal(q.workClock.find(s => s.name === 'one millisecond short').zoomiesAtFinish, false);
  assert.equal(q.workClock.find(s => s.name === 'an approval pause does not reset the clock').zoomiesAtFinish, true);
  assert.equal(q.sleep.afterMs, 600000);
  assert.equal(q.sleep.cases.length, 11 * 7);
  for (const c of q.sleep.cases) assert.equal(core.sleepDelay(c.state, c.quietMs), c.delayMs, `${c.state} ${c.quietMs}`);
  for (const c of q.sleep.wake) assert.equal(core.wakes(c.kind), c.wakes);
});
