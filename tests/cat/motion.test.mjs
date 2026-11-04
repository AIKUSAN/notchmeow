import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare, makeEngine, frameMs } from '../../scripts/gen-cat-fixtures.mjs';

const require = createRequire(import.meta.url);
const core = require('../../design/prototype/cat-core.js');
const load = name => JSON.parse(fs.readFileSync(new URL(`../fixtures/cat/${name}`, import.meta.url), 'utf8'));
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const momo = core.PRESETS.momo;
/** Runs to frame f (1 update per frame), calling `at[frame](e)` on the way. */
const run = (h, to, at = {}) => { for (let f = 1; f <= to; f++) { h.step(f); if (at[f]) at[f](h.e); } return h.e; };
const targets = (profile, state, T = 0, look = [0, 0], pers = {}) => {
  const { e } = makeEngine(momo, { profile, state, pers });
  e.lookX = look[0]; e.lookY = look[1]; e.computeTargets(T * 1000, T); return e;
};
const finiteAll = o => { for (const [k, v] of Object.entries(o)) if (typeof v === 'number') assert.ok(Number.isFinite(v), `${k} is ${v}`); };

test('the eye shape of every state, in both styles', () => {
  const want = {
    playful: { idle: 'pill', working: 'pill', thinking: 'pill', searching: 'wide', approval: 'wide', question: 'pill', error: 'flat', finished: 'happy', ratelimit: 'tired', sleeping: 'closed', dizzy: 'spiral' },
    classic: { idle: 'pill', working: 'pill', thinking: 'pill', searching: 'pill', approval: 'wide', question: 'pill', error: 'flat', finished: 'happy', ratelimit: 'tired', sleeping: 'closed', dizzy: 'spiral' },
  };
  for (const [profile, table] of Object.entries(want)) for (const [state, eye] of Object.entries(table)) assert.equal(core.PROFILES[profile].eye(state), eye, `${profile} ${state}`);
  assert.deepEqual(Object.keys(core.PROFILES), ['classic', 'playful']);
});

test('at rest a Balanced cat sits exactly on the profile table: ears, tilt, pupil and the six mouth values', () => {
  for (const state of ['idle', 'working', 'thinking', 'approval', 'question', 'error', 'finished', 'ratelimit', 'sleeping']) {
    const r = core.PLAYFUL.rest[state], tg = targets('playful', state).tg;
    near(tg.tilt, r[1]); near(tg.earL, r[2]); near(tg.earR, r[3]); near(tg.earU, r[4]); near(tg.earF, r[5]); near(tg.pupil, r[6]); near(tg.oy, r[7]);
    core.MKEYS.forEach((k, i) => near(tg[k], core.MOUTH[state][i], 1e-12));
    near(tg.lid, 0); near(tg.purr, 0); near(tg.es, 1);
  }
  for (const state of ['idle', 'working', 'thinking', 'approval', 'error', 'finished']) {
    const tg = targets('classic', state).tg;
    near(tg.tilt, core.CLASSIC.rest[state][1]); near(tg.earU, 1); near(tg.earL, 0); near(tg.pupil, .45);
  }
  assert.equal(targets('playful', 'error').tg.earF, 1, 'Playful flattens the ears to pin them back on an error');
});

test('gaze: the cursor drives 0.62 rad of yaw and 0.5 of pitch, thinking looks away, searching scans', () => {
  near(targets('playful', 'idle', 0, [1, 0]).tg.yaw, .62); near(targets('playful', 'idle', 0, [-1, 0]).tg.yaw, -.62);
  near(targets('playful', 'idle', 0, [0, 1]).tg.pitch, .5);
  near(targets('playful', 'thinking').tg.yaw, -.3025); near(targets('classic', 'thinking').tg.yaw, .3025);
  near(targets('playful', 'thinking').tg.pitch, .275);
  near(targets('playful', 'searching', .4).tg.yaw, Math.sin(2.2 * .4) * .55); near(targets('classic', 'searching', .4).tg.yaw, Math.sin(2.6 * .4) * .6);
  near(targets('playful', 'sleeping').tg.pitch, -.14);
  near(targets('playful', 'idle', 0, [1, 0], { momo: { ...core.personaNamed('balanced'), curiosity: 0 } }).tg.yaw, .62 * .35, 1e-12);
});

test('mouth motion: hunting chatter, meows, panting and snoring come from mouthFx and scale with chattiness', () => {
  near(targets('playful', 'approval', .196).mfx, .5);
  near(targets('playful', 'approval', .196, [0, 0], { momo: { ...core.personaNamed('chatty') } }).mfx, .5 * 1.4);
  near(targets('playful', 'approval', .196, [0, 0], { momo: { ...core.personaNamed('balanced'), chatty: 0 } }).mfx, .5 * .3);
  assert.ok(targets('playful', 'searching', .55).mfx > .15);
  near(targets('playful', 'idle', .55).mfx, 0);
});

test('personality bends the targets: grumpy frowns and flattens ears, chill droops, sweet blushes, never in sleep', () => {
  const grumpy = targets('playful', 'idle', 0, [0, 0], { momo: core.personaNamed('grumpy') }), g = core.persMultipliers(core.personaNamed('grumpy'));
  near(grumpy.tg.smile, core.MOUTH.idle[1] + g.smile); near(grumpy.tg.mskew, g.skew); near(grumpy.tg.lid, g.lid); near(grumpy.tg.earF, g.earBack);
  assert.ok(grumpy.tg.smile < 0 && grumpy.tg.earF > .15);
  assert.ok(targets('playful', 'idle', 0, [0, 0], { momo: core.personaNamed('chill') }).tg.lid > .3);
  assert.equal(targets('playful', 'sleeping', 0, [0, 0], { momo: core.personaNamed('chill') }).tg.lid, 0);
  assert.ok(targets('playful', 'idle', 0, [0, 0], { momo: core.personaNamed('sweet') }).blushBase > .3);
  assert.equal(targets('playful', 'sleeping', 0, [0, 0], { momo: core.personaNamed('sweet') }).blushBase, 0);
  near(targets('playful', 'approval', .35, [0, 0], { momo: core.personaNamed('hyper') }).tg.oy, targets('playful', 'approval', .35).tg.oy * 1.4, 1e-12); // a bouncy cat hops 1.4 times as high
});

test('randomness and time are injected: no Math.random, no performance.now, and the same seed repeats exactly', () => {
  const realRandom = Math.random, realNow = performance.now.bind(performance);
  const once = seed => { const log = [], h = makeEngine(momo, { quiet: false, seed, log, pers: { momo: core.personaNamed('hyper') } });
    h.e.emote('love'); h.e.slap(); for (let f = 1; f <= 45 * 60; f++) h.step(f); return { log, pose: { ...h.e.s } }; };
  Math.random = () => { throw new Error('Math.random was called'); };
  performance.now = () => { throw new Error('performance.now was called'); };
  let a, b, c;
  try { a = once(7); b = once(7); c = once(8); } finally { Math.random = realRandom; performance.now = realNow; }
  assert.deepEqual(a, b);
  assert.notDeepEqual(a.log, c.log);
  assert.ok(a.log.some(([, ev]) => ev === 'blink') && a.log.some(([, ev]) => ev.startsWith('twitch')));
});

test('quiet engines never do anything on their own', () => {
  const log = [], h = makeEngine(momo, { quiet: true, log, pers: { momo: core.personaNamed('hyper') } });
  for (let f = 1; f <= 30 * 60; f++) h.step(f);
  assert.deepEqual(log, []);
  const open = makeEngine(momo, { quiet: false, seed: 3, log: [] });
  for (let f = 1; f <= 30 * 60; f++) open.step(f);
  assert.ok(open.e.log.length > 5);
});

test('unknown names never throw: a state, an emote, a motion style, a personality', () => {
  const h = makeEngine(momo);
  for (const bad of ['bogus', '', 'constructor', '__proto__', 'toString', undefined, null, 5]) { h.e.setState(bad); assert.equal(h.e.state, 'idle', String(bad)); }
  for (const bad of ['bogus', '', 'constructor', '__proto__', 'hasOwnProperty', undefined, null]) assert.doesNotThrow(() => h.e.emote(bad), String(bad));
  run(h, 30);
  finiteAll(h.e.s);
  const odd = makeEngine(momo, { profile: 'nonsense' });
  assert.equal(odd.e.motion, 'playful'); run(odd, 10); finiteAll(odd.e.s);
  const o2 = makeEngine(momo); o2.e.cfg.override.momo = 'nonsense'; assert.equal(o2.e.motion, 'playful');
  const o3 = makeEngine(momo, { pers: { momo: { energy: 9, curiosity: -3, chatty: 'x', affection: NaN, sass: null } } });
  run(o3, 120); finiteAll(o3.e.s);
});

test('hostile frame times (zero, negative, NaN, a sleeping laptop, a clock mixup) keep the engine finite and bounded', () => {
  const after = dt => { const h = makeEngine(momo); h.e.emote('zoomies'); run(h, 39); h.clock.t = frameMs(40); h.e.update(dt); return h.e.s; };
  for (const bad of [0, -1, -1e9, NaN, Infinity, 1e9, undefined]) { const h = makeEngine(momo); h.e.emote('hairball'); run(h, 20); h.clock.t += 1e7; h.e.update(bad); finiteAll(h.e.s); finiteAll(h.e.tg); }
  assert.deepEqual(after(1e9), after(.25), 'a huge dt counts as 0.25 s');
  assert.deepEqual(after(-5), after(0), 'a negative dt counts as 0');
  assert.deepEqual(after(NaN), after(0), 'NaN counts as 0');
});

test('the mouth spring stays stable on slow frames: a hovering file at 4 to 15 fps never turns the mouth into NaN', () => {
  for (const dt of [1 / 15, .1, .25]) {
    const h = makeEngine(momo); h.e.catchOpen(true);
    for (let f = 1; f <= 2000; f++) { h.clock.t += dt * 1000; h.e.update(dt); }
    assert.ok(Number.isFinite(h.e.mouthOpen()), `dt ${dt}`); near(h.e.slotH, .55, 1e-6);
  }
});

test('hairball (2.4 s): ears back, heaves, a hairball that bounces and rolls, then relief', () => {
  const seen = {}, h = makeEngine(momo);
  h.e.emote('hairball');
  run(h, 190, { 30: e => { seen.eye1 = e.eyeShape(); seen.balls1 = e.balls.length; }, 60: e => { seen.balls60 = e.balls.length; }, 78: e => { seen.balls78 = e.balls.length; seen.file = e.balls[0] && e.balls[0].file; },
    90: e => { seen.eye90 = e.eyeShape(); }, 140: e => { seen.eye140 = e.eyeShape(); }, 143: e => { seen.eye143 = e.eyeShape(); }, 190: e => { seen.balls190 = e.balls.length; } });
  assert.equal(seen.eye1, 'closed'); assert.equal(seen.balls60, 0, 'nothing comes up before 1.1 s'); assert.equal(seen.balls78, 1); assert.equal(seen.file, null);
  assert.equal(seen.eye90, 'happy', 'relief from 1.45 s'); assert.equal(seen.eye140, 'happy'); assert.equal(seen.eye143, 'pill', 'the whole thing is over at 2.4 s');
  assert.equal(seen.balls190, 1, 'the hairball lives 2.4 s, so it is still rolling at 3.2 s');
  const m = makeEngine(momo); m.e.emote('hairball'); run(m, 17); assert.ok(m.e.s.earF > .3 || m.e.tw.earF, 'ears go back (Playful)');
  const classic = makeEngine(momo, { profile: 'classic' }); classic.e.emote('hairball'); run(classic, 17); near(classic.e.tg.earF, 0);
});

test('zoomies (2 s): pupils blown, ears back, dashes with skids, then a happy flop', () => {
  const seen = {}, h = makeEngine(momo);
  h.e.emote('zoomies');
  assert.equal(h.e.zoomUntil, 1950);
  let maxOx = 0;
  run(h, 140, { 60: e => { seen.eye1 = e.eyeShape(); seen.pupil = e.s.pupil; seen.earF = e.s.earF; }, 120: e => { seen.eye2 = e.eyeShape(); } });
  const h2 = makeEngine(momo); h2.e.emote('zoomies'); for (let f = 1; f <= 120; f++) { h2.step(f); maxOx = Math.max(maxOx, Math.abs(h2.e.s.ox)); }
  assert.equal(seen.eye1, 'wide'); assert.ok(seen.pupil > .9 && seen.earF > .5); assert.equal(seen.eye2, 'happy', 'the flop');
  assert.ok(maxOx > .8, `it dashes about ${maxOx.toFixed(2)} R to each side`);
});

test('zoomies and waking, through the engine: Playful only, never for a short run or after an error', () => {
  const q = load('sequence-cases.json'), zoom = (profile, name) => q.zoomiesAndWake.find(c => c.profile === profile && c.name === name).log.filter(([, ev]) => ev === 'zoomies');
  assert.equal(zoom('playful', '5 minutes of work, then finished').length, 1);
  assert.equal(zoom('playful', '4:59 of work, then finished').length, 0);
  assert.equal(zoom('playful', 'an approval pause keeps the clock').length, 1);
  assert.equal(zoom('playful', 'an error resets the clock').length, 0);
  assert.equal(zoom('playful', 'waking from sleep').length, 1);
  assert.equal(zoom('playful', 'sleeping straight into dizzy').length, 0);
  assert.ok(zoom('playful', 'waking from sleep')[0][0] - 5000 <= 250, 'zoomies start 220 ms after waking');
  for (const name of q.zoomiesAndWake.filter(c => c.profile === 'classic').map(c => c.name)) assert.equal(zoom('classic', name).length, 0, `classic: ${name}`);
});

test('the file catch: open wide while a file hovers, snap on the drop, gulp, then chew for 0.85 s with happy eyes', () => {
  const h = makeEngine(momo);
  h.e.catchOpen(true);
  near(h.e.slotT, .55); assert.equal(h.e.eyeShape(), 'wide'); assert.equal(h.e.catching, true);
  run(h, 30); near(h.e.slotH, .55, .08); near(h.e.tg.earU, 1.25); near(h.e.tg.pupil, .95);
  h.e.catchDrop(); near(h.e.slotT, 1.05); run(h, 60); assert.ok(h.e.slotH > .9, 'snapped wider');
  const t0 = h.clock.t; h.e.catchArrive();
  assert.equal(h.e.catching, false); near(h.e.slotT, 0); assert.equal(h.e.chewUntil - h.e.chewStart, 850, 'chew for 0.85 s'); near(h.e.chewStart, t0 + 80);
  let peak = 0, sy = Infinity, sx = 0; const eyes = new Set();
  for (let f = 61; f <= 61 + 90; f++) { h.step(f); peak = Math.max(peak, h.e.chew); sy = Math.min(sy, h.e.s.sy); sx = Math.max(sx, h.e.s.sx); eyes.add(h.e.eyeShape()); }
  near(peak, .16, .01); assert.ok(sy < .9 && sx > 1.1, 'the gulp squashes'); assert.ok(eyes.has('happy'));
  run(h, 61 + 200); assert.equal(h.e.chew, 0); assert.equal(h.e.eyeShape(), 'pill');
  const open = makeEngine(momo); open.e.catchOpen(true); open.e.catchOpen(false); near(open.e.slotT, 0); assert.equal(open.e.eyeShape(), 'pill');
});

test('a refused file is caught, gagged on and coughed back up wrapped in fur', () => {
  const h = makeEngine(momo);
  h.e.catchDrop(); h.e.catchReject('EXE');
  assert.equal(h.e.catching, false);
  run(h, 90);
  assert.equal(h.e.balls.length, 1); assert.equal(h.e.balls[0].file, 'EXE');
  assert.ok(h.e.balls[0].life > 2.5, 'a file ball lives a little longer than a hairball');
});

test('hello: a paw wave from 0.45 s to 1.55 s, with the right paw raised', () => {
  const h = makeEngine(momo);
  assert.deepEqual(core.enginePaws(h.e, 1, momo.rx, momo.ry), []);
  h.e.emote('hello');
  near(h.e.waveStart, 450); near(h.e.waveUntil, 1550);
  run(h, 40);
  const paws = core.enginePaws(h.e, 1, momo.rx, momo.ry);
  assert.equal(paws.length, 2); assert.ok(paws[1].y < paws[0].y, 'the waving paw is raised'); assert.equal(paws[1].beans, true);
  run(h, 140); assert.deepEqual(core.enginePaws(h.e, 1, momo.rx, momo.ry), [], 'paws put away');
});

test('three quick pokes make the cat dizzy, then it settles back with a happy emote', () => {
  const h = makeEngine(momo);
  h.e.slap(); h.e.slap(); assert.notEqual(h.e.state, 'dizzy');
  h.e.slap(); assert.equal(h.e.state, 'dizzy');
  run(h, 3.4 * 60 + 5); assert.equal(h.e.state, 'idle');
  const sweet = makeEngine(momo, { pers: { momo: core.personaNamed('sweet') }, log: [] }); sweet.e.slap();
  assert.ok(sweet.e.log.some(([, ev]) => ev === 'emote:love'), 'a sweet cat answers a poke with love');
  const grumpy = makeEngine(momo, { pers: { momo: core.personaNamed('grumpy') }, log: [] }); grumpy.e.slap();
  assert.ok(grumpy.e.log.some(([, ev]) => ev === 'emote:annoyed'));
});

test('motion-cases.json: ease, prng, tween and rest replay from their inputs', () => {
  const m = load('motion-cases.json');
  assert.equal(m.version, 1); assert.deepEqual(m.clock.sampleFrames, [0, 5, 10, 16, 24, 34, 46, 60, 78, 102, 132, 180]);
  assert.equal(m.columns.length, 7 + Object.keys(core.newPose()).length);
  for (const c of m.ease) for (const s of c.samples) near(core.EZ[c.name](s.t), s.v);
  for (const c of m.prng) { const r = core.rng(c.seed); c.values.forEach(v => assert.equal(Number(v.toPrecision(12)), Number(r().toPrecision(12)))); }
  for (const c of m.tween) {
    const { e, step } = makeEngine(momo); e.anim(c.prop, c.keys);
    const want = new Map(c.values);
    for (let f = 0; f <= 58; f++) { if (f > 0) step(f); if (want.has(f)) near(e.s[c.prop], want.get(f)); }
  }
  assert.equal(m.rest.length, 2 * 11 * 5);
  for (const c of m.rest) {
    const e = targets(c.profile, c.state, c.T, c.look);
    assert.deepEqual(compare({ ...e.tg }, c.targets), [], `${c.profile} ${c.state} T=${c.T}`);
    assert.equal(e.prof.eye(c.state), c.eye); assert.equal(core.TINT[c.state], c.tint); assert.equal(core.BADGE[c.state] || null, c.badge);
    near(e.mfx, c.mfx);
  }
  assert.equal(m.enters.length, 2 * 11 * 12); assert.equal(m.emotes.length, 2 * (10 + 2) * 12);
  for (const r of [...m.enters, ...m.emotes]) assert.equal(r.v.length, m.columns.length);
  assert.equal(m.ambient.length, 12);
  for (const a of m.ambient) assert.ok(a.events.length > 5 && a.events.every(([t, ev]) => Number.isInteger(t) && typeof ev === 'string'));
  assert.ok(m.ambient.find(a => a.profile === 'playful' && a.persona === 'hyper').events.some(([, ev]) => ev === 'zoomies'));
  assert.ok(m.ambient.find(a => a.profile === 'playful' && a.persona === 'chill').events.some(([, ev]) => ev === 'emote:yawn'));
});

test('sequence-cases.json: the catch replays four steps in both styles, refused or not', () => {
  const q = load('sequence-cases.json');
  assert.equal(q.catch.length, 4);
  for (const c of q.catch) {
    assert.equal(c.dropFrame, 60); assert.equal(c.arriveFrame, 83);
    const at = f => c.rows.find(r => r.f === f), slotH = 1, chew = 2, balls = 4;   // indexes into the row's v, see columns
    assert.equal(at(0).eye, 'wide'); assert.ok(at(48).v[slotH] > .4 && at(48).v[slotH] < .7, 'hovering: about .55 open');
    assert.ok(at(72).v[slotH] > .9, 'dropped: wider');
    if (!c.refused) { assert.ok(c.rows.some(r => r.f >= 90 && r.f <= 130 && r.v[chew] > .05), 'chewing'); assert.ok(c.rows.every(r => r.v[balls] === 0), 'no hairball'); }
    else assert.ok(c.rows.some(r => r.f >= 132 && r.v[balls] === 1), 'the file comes back as a ball');
    assert.equal(at(240).v[chew], 0);
  }
});
