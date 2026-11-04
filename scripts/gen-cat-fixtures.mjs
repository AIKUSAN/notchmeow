#!/usr/bin/env node
// Writes tests/fixtures/cat/*.json from design/prototype/cat-core.js, the single source of truth.
//   node scripts/gen-cat-fixtures.mjs             write the fixtures
//   node scripts/gen-cat-fixtures.mjs --check     regenerate in memory and fail on any drift
//   node scripts/gen-cat-fixtures.mjs --out DIR   write somewhere else (the runner uses it twice, to prove determinism)
// No npm dependencies. Numbers are written with 12 significant digits; apps compare within 1e-9 R.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
const core = require('../design/prototype/cat-core.js');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const FIXTURES = path.join(ROOT, 'tests/fixtures/cat');
export const TOLERANCE = 1e-9;

/** Rounds every number to 12 significant digits and snaps |x| < 1e-12 to 0, so libm last-bit noise never reaches a fixture. */
export function fix(v) {
  if (typeof v === 'number') {
    if (!Number.isFinite(v)) throw new Error(`non-finite number in a fixture: ${v}`);
    return Math.abs(v) < 1e-12 ? 0 : Number(v.toPrecision(12));
  }
  if (Array.isArray(v)) return v.map(fix);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, fix(x)]));
  return v;
}

const isObj = x => x !== null && typeof x === 'object' && !Array.isArray(x);

/** Compact, diff-friendly JSON: an array of objects gets one element per line, a map of objects one entry per line. */
export function format(obj) {
  const keys = Object.keys(obj), lines = [];
  keys.forEach((k, i) => {
    const v = obj[k], comma = i < keys.length - 1 ? ',' : '', head = `  ${JSON.stringify(k)}: `;
    if (Array.isArray(v) && v.length && v.every(isObj)) {
      lines.push(`${head}[`);
      v.forEach((x, j) => lines.push(`    ${JSON.stringify(x)}${j < v.length - 1 ? ',' : ''}`));
      lines.push(`  ]${comma}`);
    } else if (isObj(v) && Object.keys(v).length && Object.values(v).every(isObj)) {
      const ks = Object.keys(v);
      lines.push(`${head}{`);
      ks.forEach((kk, j) => lines.push(`    ${JSON.stringify(kk)}: ${JSON.stringify(v[kk])}${j < ks.length - 1 ? ',' : ''}`));
      lines.push(`  }${comma}`);
    } else lines.push(`${head}${JSON.stringify(v)}${comma}`);
  });
  return `{\n${lines.join('\n')}\n}\n`;
}

/** Deep compare with a numeric tolerance. Returns the list of differences, empty when equal. */
export function compare(got, want, at = '$', out = []) {
  if (typeof got === 'number' && typeof want === 'number') {
    if (!(Math.abs(got - want) <= TOLERANCE)) out.push(`${at}: ${got} vs ${want}`);
  } else if (Array.isArray(got) && Array.isArray(want)) {
    if (got.length !== want.length) out.push(`${at}: length ${got.length} vs ${want.length}`);
    for (let i = 0; i < Math.min(got.length, want.length); i++) compare(got[i], want[i], `${at}[${i}]`, out);
  } else if (isObj(got) && isObj(want)) {
    const gk = Object.keys(got).sort(), wk = Object.keys(want).sort();
    if (gk.join() !== wk.join()) out.push(`${at}: keys ${gk.join()} vs ${wk.join()}`);
    for (const k of gk) if (k in want) compare(got[k], want[k], `${at}.${k}`, out);
  } else if (got !== want) out.push(`${at}: ${JSON.stringify(got)} vs ${JSON.stringify(want)}`);
  return out;
}

/** Every fixture file starts with its version and the tolerance apps compare with. */
export function finish(obj) {
  const { version, ...rest } = obj;
  return { version, tolerance: TOLERANCE, ...rest };
}

const FILES = {};

FILES['presets.json'] = () => ({
  version: 1,
  note: 'Every number is in units of R, the head radius. The IDs and the voice offsets (semitones) are frozen contract values.',
  ids: core.CAT_IDS,
  cats: Object.fromEntries(core.CAT_IDS.map(id => [id, core.PRESETS[id]])),
  kittens: Object.fromEntries(core.CAT_IDS.map(id => [id, core.kittenOf(core.PRESETS[id])])),
});

// ── Geometry and warp ────────────────────────────────────────────────────────
const pose = (o = {}) => ({ ...core.newPose(), ...o });
const noW = L => { const { W, ...rest } = L; return rest; };
const presetOf = (cat, kitten) => (kitten ? core.kittenOf(core.PRESETS[cat]) : core.PRESETS[cat]);
const SIDE = D => core.badgeSide(D < core.DETAIL_FULL_MIN);

/** Ear fit: the factor for the ears of a cat in a strip, as the compact island uses it (a 32 pt notch strip, or 24 pt without a notch). */
const earFitCases = () => {
  const POSES = [{}, { earU: 1.4 }, { earU: 1.4, oy: -.26 }, { earU: 1.22, oy: -.26 }, { earU: 1.4, oy: -.3, tilt: .24 }, { earU: 1.4, oy: -.3, tilt: -.24 }, { earU: 1.1, earF: .45, oy: -.1, tilt: .1 }];
  const cases = [];
  const add = (cat, kitten, D, cy, delta, { ceiling = 0, margin = core.EAR_FIT.margin, minimum = core.EAR_FIT.minimum, ek = D < core.DETAIL_FULL_MIN ? core.earScale(D) : 1 } = {}) => {
    const p = presetOf(cat, kitten), s = pose(delta), L = core.layout(p, s, 40, cy, D, { earScale: ek });
    cases.push({ cat, kitten, D, cx: 40, cy, earScale: ek, pose: delta, ceiling, margin, minimum, fit: core.earFit(L, s, ceiling, margin, minimum) });
  };
  for (const cat of ['momo', 'shrimpy', 'puff', 'noodle', 'button', 'latte']) for (const [strip, D] of [[32, 20], [24, 18]]) for (const delta of POSES) add(cat, false, D, strip / 2, delta);
  add('shrimpy', true, 16, 12, { earU: 1.4, oy: -.26 });                        // a kitten in a 24 pt strip
  add('momo', false, 20, 9, {}, { ek: 1 });                                      // close to the top: some shrinking
  add('momo', false, 20, -30, {}, { ek: 1 });                                    // so close that even the smallest ears do not fit: the minimum
  add('momo', false, 20, 16, { earU: 1.4, oy: -.26 }, { ceiling: 5 });           // a ceiling that is not the top of the strip
  add('momo', false, 20, 16, { earU: 1.4, oy: -.3 }, { margin: 0 });             // no margin
  add('momo', false, 20, 8, {}, { minimum: .5 });                                // a higher minimum
  add('momo', false, 0, 16, {});                                                 // a head of width 0
  add('noodle', false, 20, 16, { tilt: Math.PI, earU: 1.4 });                    // upside down
  return cases;
};

/** The levels of detail for a head width, and with an explicit override. */
const detailLevelCases = () => [[0], [12], [20], [27.999], [28], [28.001], [44], [66], [66, 'compact'], [12, 'full'], [28, 'compact'], [27.999, 'full']]
  .map(([D, override]) => ({ D, override: override ?? null, level: core.detailLevel(D, override) }));

FILES['geometry-cases.json'] = () => {
  const outline = [];
  const addOutline = (name, p, kind, steps, bend = null) => {
    const r = kind === 'ruff' ? p.ruff : p;
    const args = kind === 'ruff' ? [r.rx, r.ry, 2.4, r.dy, .06, 18] : [p.rx, p.ry, p.n, 0, p.fluff ? .035 : 0, 14];
    const stride = steps / (steps === 200 ? 20 : 18), indices = [];
    for (let i = 0; i <= steps; i += stride) indices.push(i);
    const pts = core.supPoints(...args, steps, bend);
    outline.push({ name, rx: args[0], ry: args[1], n: args[2], dy: args[3], spike: args[4], count: args[5], steps, bend, indices, points: indices.map(i => pts[i]) });
  };
  addOutline('momo head', core.PRESETS.momo, 'head', 200);
  addOutline('momo head, compact (72 steps)', core.PRESETS.momo, 'head', 72);
  addOutline('shrimpy head, fluffy edge', core.PRESETS.shrimpy, 'head', 200);
  addOutline('shrimpy head, fluffy edge, compact', core.PRESETS.shrimpy, 'head', 72);
  addOutline('shrimpy head turned (bend)', core.PRESETS.shrimpy, 'head', 200, [Math.sin(.5) * core.FACE.bend, -Math.sin(.2) * core.FACE.bend * .7]);
  addOutline('shrimpy ruff', core.PRESETS.shrimpy, 'ruff', 200);
  addOutline('puff ruff', core.PRESETS.puff, 'ruff', 200);
  addOutline('shrimpy kitten head', core.kittenOf(core.PRESETS.shrimpy), 'head', 200);
  addOutline('noodle head', core.PRESETS.noodle, 'head', 200);

  const anchors = [];
  const addAnchor = (cat, kitten, D, delta = {}, T = 0) => {
    const compact = D < core.DETAIL_FULL_MIN, c = { cat, kitten, D, cx: 100, cy: 50, T, pose: delta, earScale: compact ? core.earScale(D) : 1, badgeSide: SIDE(D) };
    anchors.push({ ...c, layout: noW(core.layout(presetOf(cat, kitten), pose(delta), c.cx, c.cy, D, { T, earScale: c.earScale, badgeSide: c.badgeSide })) });
  };
  for (const cat of ['shrimpy', 'momo', 'latte', 'patches', 'cloud', 'button', 'puff', 'noodle']) for (const D of [66, 28, 20]) addAnchor(cat, false, D, { badgeS: 1 });
  for (const cat of ['shrimpy', 'momo']) for (const D of [40, 16]) addAnchor(cat, true, D, { badgeS: 1 });
  addAnchor('shrimpy', false, 44, { badgeS: 1, sx: 1.12, sy: .9, tilt: .1, oy: -.1, ox: .05, earL: .2, earR: -.1, earU: 1.3, earF: .5, lift: .2, purr: 1 }, .0125);
  addAnchor('momo', false, 20, { badgeS: 1, earU: 1.4, earF: 1, sx: .94, sy: 1.12 });

  return {
    version: 1,
    units: 'R (head radius) for supPoints; px for layout. A case pose lists only the fields that differ from newPose().',
    detail: { fullMinD: core.DETAIL_FULL_MIN, cases: [0, 12, 16, 20, 24, 27.999, 28, 28.001, 44, 66].map(D => ({ D, detail: core.detailOf(D) })) },
    earScale: { compactMin: core.COMPACT_EAR_SCALE, provisional: true, cases: [0, 12, 16, 20, 22, 24, 26, 27.999, 28, 44, 66].map(D => ({ D, scale: core.earScale(D) })) },
    outline,
    anchors,
    collarPass: core.COLLAR_PASS,
    earFit: core.EAR_FIT,
    earFitCases: earFitCases(),
    flatFill: core.FLAT_FILL,
    detailLevels: detailLevelCases(),
    flatColors: Object.fromEntries(core.CAT_IDS.map(id => [id, core.flatFillColors(core.PRESETS[id])])),
    passes: core.PASSES,
  };
};

FILES['warp-cases.json'] = () => {
  const R = 1, PROBES = [[0, 0], [0, -.6], [0, -.3], [.3, -.5], [-.3, -.5], [.5, 0], [-.5, 0], [.8, .3], [-.8, .3], [0, .3], [0, .5], [1.3, .9]];
  const POSES = [[0, 0], [.31, 0], [.62, 0], [-.62, 0], [0, .5], [0, -.5], [.62, .5], [-.62, -.5]];
  const angles = [], warp = [], eyes = [], head = [];
  for (const [yaw, pitch] of POSES) for (const [lift, roll] of [[0, 0], [.28, 0], [0, 1.2]]) angles.push({ yaw, pitch, lift, roll, ...core.faceAngles(pose({ yaw, pitch, lift, roll })) });
  for (const cat of ['momo', 'shrimpy', 'latte', 'puff']) {
    const p = core.PRESETS[cat];
    const probes = [...PROBES, [0, -Math.sin(p.nosePh) * p.ry], ...core.MOMO_WHITE.filter((_, i) => i % 8 === 0)];
    for (const [yaw, pitch] of POSES) {
      const a = core.faceAngles(pose({ yaw, pitch })), W = core.mkWarp(p, a.yf, a.pt, R);
      warp.push({ cat, yaw, pitch, yf: a.yf, pt: a.pt, probes, out: probes.map(([x, y]) => W(x, y)) });
    }
  }
  for (const cat of ['momo', 'shrimpy', 'button']) for (const yaw of [0, .31, .62, .9, 1.2, 1.3, 1.4, 1.6]) {
    const L = core.layout(core.PRESETS[cat], pose({ yaw }), 0, 0, 2 * core.PRESETS[cat].rx);
    eyes.push({ cat, yaw, eyes: L.eyes });
  }
  for (const cat of ['shrimpy', 'momo']) for (const [yaw, pitch] of POSES) {
    const D = 66, L = core.layout(core.PRESETS[cat], pose({ yaw, pitch }), 0, 0, D);
    head.push({ cat, D, yaw, pitch, head: L.head, bend: L.bend, ruff: L.ruff, nose: L.nose, mouth: L.mouth });
  }
  const pupil = [];
  for (const [yaw, pitch] of [[0, 0], [.62, 0], [-.62, 0], [.31, .25], [1.2, 0], [0, .5], [0, -.5], [0, -1]]) pupil.push({ yaw, pitch, w: .21, h: .16, offset: core.pupilOffset(yaw, pitch, .21, .16) });
  const cursor = [[0, 0], [240, 0], [-240, 0], [480, 0], [0, 180], [0, -180], [0, -360], [120, 90], [1e6, -1e6]].map(([dx, dy]) => ({ dx, dy, ...core.cursorLook(dx, dy) }));
  return {
    version: 1,
    units: 'R for warp (R = 1) and the pose angles in radians; px for head, nose and mouth (D = 66, cat at 0,0).',
    face: core.FACE,
    cursor: { px: core.CURSOR, cases: cursor },
    angles,
    pupil,
    warp,
    eyes,
    head,
  };
};

// ── Personality ──────────────────────────────────────────────────────────────
FILES['personality-cases.json'] = () => {
  const cases = [];
  const add = (name, traits) => cases.push({ name, traits, out: core.persMultipliers(traits) });
  for (const [name, p] of Object.entries(core.PERSONAS)) add(`preset ${name}`, Object.fromEntries(core.TRAIT_KEYS.map(k => [k, p[k]])));
  add('all zero', { energy: 0, curiosity: 0, chatty: 0, affection: 0, sass: 0, mischief: 0 });
  add('all one', { energy: 1, curiosity: 1, chatty: 1, affection: 1, sass: 1, mischief: 1 });
  add('custom mix', { energy: .8, curiosity: .2, chatty: .65, affection: .9, sass: .6, mischief: .4 });
  add('custom mix (slider values i/100)', { energy: .27, curiosity: .83, chatty: .41, affection: .58, sass: .12, mischief: .99 });
  for (const [k, vs] of Object.entries({ energy: [.29, .3], chatty: [.7, .71], affection: [.75, .76], sass: [.7, .71, .75, .76], mischief: [.65, .66, .75, .76] })) {
    for (const v of vs) add(`threshold ${k} ${v}`, { [k]: v });
  }
  add('threshold zoomies energy .71 mischief .76', { energy: .71, mischief: .76 });
  add('threshold poke love affection .76 sass .39', { affection: .76, sass: .39 });
  add('threshold poke annoyed affection .76 sass .4', { affection: .76, sass: .4 });
  add('out of range high', { energy: 7, curiosity: 2, chatty: 1.5, affection: 100, sass: 3, mischief: 9 });
  add('out of range low', { energy: -1, curiosity: -.5, chatty: -9, affection: -2, sass: -3, mischief: -.1 });
  add('missing traits', {});
  add('missing some traits', { sass: .9 });
  add('wrong types', { energy: 'high', curiosity: null, chatty: true, affection: [1], sass: {}, mischief: '0.9' });
  const slide = [['chill', 'sass', .9], ['sweet', 'affection', .2], ['balanced', 'energy', 1.5], ['grumpy', 'mischief', -1], ['hyper', 'nonsense', .5]]
    .map(([from, trait, value]) => ({ from, trait, value, out: core.slide(core.personaNamed(from), trait, value) }));
  return {
    version: 1,
    note: 'Input traits may be out of range or missing: persMultipliers holds them to 0..1 and counts anything else as 0.5.',
    traits: core.TRAITS.map(([key, label, low, high]) => ({ key, label, low, high })),
    presets: core.PERSONAS,
    cases,
    slide,
  };
};

// ── Rules and timelines ──────────────────────────────────────────────────────
FILES['search-tools.json'] = () => ({
  version: 1,
  match: 'Exact and case-sensitive on the tool name the hook relay delivers as tool_name. No prefix or MCP matching.',
  agents: core.SEARCH_TOOLS,
  cases: ['WebSearch', 'WebFetch', 'Grep', 'Glob', 'google_web_search', 'web_fetch', 'grep_search', 'search_file_content', 'glob', 'web_search', 'grep_files',
    'Bash', 'Read', 'Edit', 'Write', 'Task', 'LS', 'TodoWrite', 'AskUserQuestion', 'run_shell_command', 'read_file', 'list_directory', 'apply_patch',
    'websearch', 'WEBSEARCH', 'Web_Search', 'mcp__brave__web_search', ''].map(tool => ({ tool, searching: core.isSearchTool(tool), state: core.toolState(tool) })),
});

// sequence-cases.json is assembled from parts; each part returns top-level keys.
const SEQUENCE_PARTS = [];
FILES['sequence-cases.json'] = () => Object.assign({ version: 1 }, ...SEQUENCE_PARTS.map(part => part()));

SEQUENCE_PARTS.push(() => {
  const beats = [50, 620, 1180, 1250, 1650, 1720, 2720, 2750, 3250, 4900, 5240, 5740];
  const tMs = [...new Set([...Array.from({ length: 59 }, (_, i) => i * 100), ...beats])].sort((a, b) => a - b);
  return {
    units: 'Greeting: seconds in a 640x150 space (px). The sample times are integer milliseconds; t = tMs / 1000.',
    greetingLengthS: core.GREET_LEN,
    greetingTimeline: { ...core.GT, ...Object.fromEntries(Object.entries(core.GT2).map(([k, v]) => [`v2_${k}`, v])), notchW: core.NOTCH.W, notchH: core.NOTCH.H, compact: core.COMPACT },
    greetingStreaks: core.STREAKS,
    greetingSamples: tMs.map(t => ({ tMs: t, pose: core.greetingPose(t / 1000) })),
    flight: { flightMs: core.FLIGHT_MS, cases: [0, .25, .5, .75, 1].map(k => ({ from: { x: 200, y: 40 }, to: { x: 100, y: 120 }, R: 30, k, out: core.flightAt({ x: 200, y: 40 }, { x: 100, y: 120 }, 30, k) })) },
  };
});

SEQUENCE_PARTS.push(() => {
  const S = (name, steps) => {
    let clock = { busySince: null, workedFor: 0 };
    const after = steps.map(([t, state]) => { clock = core.workClockStep(clock, state, t); return { tMs: t, state, busySince: clock.busySince, workedFor: clock.workedFor }; });
    const last = steps[steps.length - 1];
    return { name, steps, after, zoomiesAtFinish: last[1] === 'finished' ? core.zoomiesOnFinish(clock.workedFor) : null };
  };
  const sleepStates = core.STATES, quiet = [0, 1000, 599999, 600000, 600001, 3600000, -5000];
  return {
    zoomAfterMs: core.ZOOM_AFTER_MS,
    workClock: [
      S('5 minutes of work earns zoomies', [[0, 'working'], [300000, 'finished']]),
      S('one millisecond short', [[0, 'working'], [299999, 'finished']]),
      S('the clock starts at time zero', [[0, 'thinking'], [300000, 'finished']]),
      S('working, thinking and searching add up', [[1000, 'working'], [100000, 'thinking'], [200000, 'searching'], [301000, 'finished']]),
      S('an approval pause does not reset the clock', [[0, 'working'], [100000, 'approval'], [250000, 'working'], [300000, 'finished']]),
      S('a question pause does not reset the clock', [[0, 'working'], [100000, 'question'], [250000, 'thinking'], [310000, 'finished']]),
      S('waiting on an approval is not work, but it is not a reset either', [[0, 'working'], [10000, 'approval'], [290000, 'finished']]),
      S('an error ends the run', [[0, 'working'], [100000, 'error'], [110000, 'working'], [400000, 'finished']]),
      S('a rate limit ends the run', [[0, 'working'], [200000, 'ratelimit'], [200500, 'working'], [400000, 'finished']]),
      S('idle in the middle ends the run', [[0, 'working'], [100000, 'idle'], [100001, 'finished']]),
      S('finishing straight away', [[5000, 'finished']]),
      S('the clock stepping backwards never goes negative', [[1000, 'working'], [500, 'finished']]),
    ],
    sleep: {
      afterMs: core.SLEEP_AFTER_MS,
      cases: sleepStates.flatMap(state => quiet.map(quietMs => ({ state, quietMs, delayMs: core.sleepDelay(state, quietMs) }))),
      wake: ['hook', 'hover', 'click', 'scroll', 'key', 'drag', ''].map(kind => ({ kind, wakes: core.wakes(kind) })),
    },
  };
});

// ── Motion: rest targets, enters, emotes, ambient habits; and the file catch and the zoomies and wake rules ──
const FPS = 60;
export const frameMs = f => f * 1000 / FPS;                    // frame f is at f*1000/60 ms; the engine is updated with dt = 1/60
const POSE_KEYS = Object.keys(core.newPose());
const SAMPLE_FRAMES = [0, 5, 10, 16, 24, 34, 46, 60, 78, 102, 132, 180];   // 0, 83, 167, 267, 400, 567, 767, 1000, 1300, 1700, 2200, 3000 ms
const EMOTES = ['love', 'happy', 'surprised', 'proud', 'wink', 'yawn', 'annoyed', 'hello', 'zoomies', 'hairball'];
const PROFILES = ['playful', 'classic'];
const COLUMNS = ['mouthOpen', 'slotH', 'chew', 'parts', 'balls', 'ballX', 'ballY', ...POSE_KEYS];

/** An engine on a fake clock and a seeded rand, the way every app test builds one. `step(f)` moves to frame f and updates once. */
export function makeEngine(preset, { profile = 'playful', pers = {}, seed = 1, quiet = true, state = 'idle', log = null, zoomAfter = core.ZOOM_AFTER_MS } = {}) {
  const clock = { t: 0 }, cfg = { motion: profile, override: {}, pers, zoomAfter };
  const e = new core.CatEngine(preset, { now: () => clock.t, rand: core.rng(seed), cfg, quiet, state, log });
  const L = core.layout(preset, e.s, 0, 0, 2 * preset.rx);                      // R = 1, so the hairball is placed in units of R
  e._base = L.base; e._mouth = L.mouth;
  return { e, clock, step: f => { clock.t = frameMs(f); e.update(1 / FPS); } };
}
const row = e => [e.mouthOpen(), e.slotH, e.chew, e.parts.length, e.balls.length, e.balls[0] ? e.balls[0].x : 0, e.balls[0] ? e.balls[0].y : 0, ...POSE_KEYS.map(k => e.s[k])];
/** Runs from frame 0, calling `start(e)` there, and returns one row per sample frame. */
function sample(preset, opts, start, frames = SAMPLE_FRAMES) {
  const { e, step } = makeEngine(preset, opts);
  start(e);
  const rows = [], last = frames[frames.length - 1];
  for (let f = 0; f <= last; f++) { if (f > 0) step(f); if (frames.includes(f)) rows.push({ f, eye: e.eyeShape(), v: row(e) }); }
  return rows;
}

FILES['motion-cases.json'] = () => {
  const ease = Object.keys(core.EZ).map(name => ({ name, samples: [0, .1, .25, .5, .75, .9, 1].map(t => ({ t, v: core.EZ[name](t) })) }));
  const prng = [0, 1, 7, 13, 29, 4294967295, 4294967296].map(seed => { const r = core.rng(seed); return { seed, values: Array.from({ length: 8 }, r) }; });

  const tween = [
    { prop: 'sx', keys: [[1.2, 100, 'out'], [1, 200, 'inOut']] },
    { prop: 'sy', keys: [[.88, 110, 'out'], [1.1, 170, 'out'], [1, 340, 'back']] },
    { prop: 'oy', keys: [[-.2, 150, 'out'], [0, 300, 'back']] },
    { prop: 'blush', keys: [[1, 300, 'out'], [1, 700, 'lin'], [0, 300, 'inOut']] },
    { prop: 'tilt', keys: [[.3, 220, 'in'], [.24, 300, 'inOut']] },
  ].map(c => {
    const { e, step } = makeEngine(core.PRESETS.momo), from = e.s[c.prop];
    e.anim(c.prop, c.keys);
    const frames = Array.from({ length: 30 }, (_, i) => i * 2), out = [];
    for (let f = 0; f <= frames[frames.length - 1]; f++) { if (f > 0) step(f); if (frames.includes(f)) out.push([f, e.s[c.prop]]); }
    return { ...c, from, values: out };
  });

  const rest = [];
  for (const profile of PROFILES) for (const state of core.STATES) for (const [T, look] of [[0, [0, 0]], [.4, [0, 0]], [1, [0, 0]], [2.7, [0, 0]], [.4, [.6, -.3]]]) {
    const { e } = makeEngine(core.PRESETS.momo, { profile, state });
    e.lookX = look[0]; e.lookY = look[1]; e.computeTargets(T * 1000, T);
    rest.push({ profile, state, T, look, eye: e.prof.eye(state), tint: core.TINT[state], badge: core.BADGE[state] || null, color: core.COL[state], glow: core.GLOW[state] || null, mfx: e.mfx, blushBase: e.blushBase, targets: { ...e.tg } });
  }

  const enters = [], emotes = [];
  for (const profile of PROFILES) {
    for (const state of core.STATES) for (const r of sample(core.PRESETS.momo, { profile }, e => e.setState(state))) enters.push({ profile, cat: 'momo', state, f: r.f, tMs: frameMs(r.f), eye: r.eye, v: r.v });
    for (const name of EMOTES) for (const cat of (name === 'hairball' || name === 'zoomies') ? ['momo', 'shrimpy'] : ['momo']) {
      for (const r of sample(core.PRESETS[cat], { profile }, e => e.emote(name))) emotes.push({ profile, cat, emote: name, f: r.f, tMs: frameMs(r.f), eye: r.eye, v: r.v });
    }
  }

  const ambient = [];
  for (const profile of PROFILES) for (const persona of Object.keys(core.PERSONAS)) {
    const log = [], { e, step } = makeEngine(core.PRESETS.momo, { profile, quiet: false, seed: 7, log, pers: { momo: core.personaNamed(persona) } });
    for (let f = 1; f <= 45 * FPS; f++) step(f);
    ambient.push({ profile, persona, seconds: 45, seed: 7, events: log });
  }

  return {
    version: 1,
    units: 'Pose values are the engine pose `s` (R for oy/ox, radians for tilt/yaw/pitch/roll). Frame f is at f*1000/60 ms and the engine is updated once per frame with dt = 1/60.',
    clock: { fps: FPS, frameMs: '1000/60', sampleFrames: SAMPLE_FRAMES },
    harness: { cat: 'momo unless the case says otherwise', rand: 'rng(seed)', quiet: 'true except in ambient', base: { x: 0, y: 0, R: 1 }, note: 'rest: engine built in the state, lookX/lookY set, computeTargets(T*1000, T) called. enters/emotes: engine idle, setState/emote called at frame 0, then updated once per frame.' },
    columns: COLUMNS,
    ease,
    tween,
    prng,
    rest,
    enters,
    emotes,
    ambient,
  };
};

// The file catch and the zoomies and wake rules, run through the engine.
const CATCH_FRAMES = [0, 6, 12, 24, 36, 48, 59, 60, 62, 66, 72, 80, 83, 84, 86, 90, 96, 108, 120, 132, 150, 168, 200, 240];
SEQUENCE_PARTS.push(() => {
  const catchCases = [];
  const FLIGHT_FRAMES = Math.ceil(core.FLIGHT_MS / frameMs(1));            // 23: the first frame at or after 380 ms
  for (const profile of PROFILES) for (const refused of [false, true]) {
    const { e, step } = makeEngine(core.PRESETS.momo, { profile });
    const rows = [];
    e.catchOpen(true);                                                       // 1. open wide while the file hovers
    for (let f = 0; f <= CATCH_FRAMES[CATCH_FRAMES.length - 1]; f++) {
      if (f > 0) step(f);
      if (f === 60) e.catchDrop();                                           // 2. snap wider on the drop, the file flies in
      if (f === 60 + FLIGHT_FRAMES) refused ? e.catchReject('EXE') : e.catchArrive();   // 3. gulp with a squash, 4. chew with happy eyes
      if (CATCH_FRAMES.includes(f)) rows.push({ f, tMs: frameMs(f), eye: e.eyeShape(), v: row(e) });
    }
    catchCases.push({ profile, refused, dropFrame: 60, arriveFrame: 60 + FLIGHT_FRAMES, rows });
  }

  const run = (profile, script) => {
    const log = [], clock = { t: 0 }, e = new core.CatEngine(core.PRESETS.momo, { now: () => clock.t, rand: core.rng(1), quiet: true, log, cfg: { motion: profile, override: {}, pers: {}, zoomAfter: core.ZOOM_AFTER_MS } });
    const L = core.layout(core.PRESETS.momo, e.s, 0, 0, 2 * core.PRESETS.momo.rx); e._base = L.base; e._mouth = L.mouth;
    for (const [tMs, fn] of script) { clock.t = tMs; fn(e); }
    for (let f = 0; f < 60; f++) { clock.t += 1000 / FPS; e.update(1 / FPS); }
    return log;
  };
  const events = [];
  const add = (name, profile, script) => events.push({ name, profile, script: script.map(([t, what]) => [t, what]), log: run(profile, script.map(([t, what]) => [t, e => what.startsWith('wake:') ? e.setState('idle') : e.setState(what)])) });
  for (const profile of PROFILES) {
    add('5 minutes of work, then finished', profile, [[0, 'working'], [300000, 'finished']]);
    add('4:59 of work, then finished', profile, [[0, 'working'], [299000, 'finished']]);
    add('an approval pause keeps the clock', profile, [[0, 'working'], [100000, 'approval'], [250000, 'working'], [300000, 'finished']]);
    add('an error resets the clock', profile, [[0, 'working'], [100000, 'error'], [110000, 'working'], [400000, 'finished']]);
    add('waking from sleep', profile, [[0, 'sleeping'], [5000, 'wake:idle']]);
    add('sleeping straight into dizzy', profile, [[0, 'sleeping'], [5000, 'dizzy']]);
    add('sleeping into an approval', profile, [[0, 'sleeping'], [5000, 'approval']]);
  }
  return { catchHarness: { drop: 'catchDrop() at frame 60', flightFrames: FLIGHT_FRAMES, arrive: 'catchArrive() (or catchReject("EXE") when refused) after the flight', columns: COLUMNS }, catch: catchCases, zoomiesAndWake: events };
});

// ── Collar ───────────────────────────────────────────────────────────────────
FILES['collar-cases.json'] = () => {
  const cases = [];
  const add = (cat, kitten, style, D, dpr, delta = {}) => cases.push({ cat, kitten, style, D, dpr, pose: delta, out: core.collarGeometry(presetOf(cat, kitten), pose(delta), D, style, { dpr }) });
  const DRAWN = ['tag', 'band', 'kerchief'];
  for (const cat of ['shrimpy', 'momo']) for (const style of DRAWN) for (const D of [12, 16, 20, 28, 44, 66]) for (const dpr of [1, 2]) add(cat, false, style, D, dpr);
  for (const cat of ['puff', 'noodle']) for (const style of DRAWN) for (const D of [12, 20, 66]) for (const dpr of [1, 2]) add(cat, false, style, D, dpr);
  for (const cat of ['shrimpy', 'momo']) for (const style of DRAWN) for (const D of [20, 66]) for (const delta of [{ yaw: .6 }, { yaw: -.6, pitch: .4 }, { pitch: -.3 }, { lift: .28, roll: .5 }]) add(cat, false, style, D, 2, delta);
  for (const style of DRAWN) for (const D of [12, 40]) add('shrimpy', true, style, D, 2);
  add('momo', false, 'off', 20, 2); add('momo', false, 'off', 66, 1);
  return {
    version: 1,
    units: 'px, head-local (before the tilt and the squash), turning with the face warp. D is the head width in px and dpr the device pixel ratio. A case pose lists only the fields that differ from newPose(). out is null for off.',
    styles: core.COLLAR_STYLES,
    min: core.COLLAR_MIN,
    resolve: [...core.COLLAR_STYLES, 'scarf', 'Tag', ' tag', '', 'bowtie', null, 7, true].map(id => ({ id, style: core.collarStyleOf(id) })),
    cases,
  };
};

// ── The greeting's last beat (A-0c): the session cats pop in as a row, glide into the compact island's 2×2 grid, and a fourth joins ──
// Appended to sequence-cases.json as new keys only, so every line of the existing cases stays byte for byte.
SEQUENCE_PARTS.push(() => {
  const geometries = [
    { name: "the contract's compact island", W: 288, H: 32, d: 12 },
    { name: 'a Mac with a notch: 184 pt of notch and 160 of ears, 38 pt high', W: 344, H: 38, d: 12 },
    { name: 'a Mac without a notch: a 24 pt strip', W: 240, H: 24, d: 12 },
    { name: 'the Windows app: 13 px cats', W: 288, H: 32, d: 13 },
    { name: 'a strip too short to hold a cat', W: 288, H: 6, d: 12 },
  ];
  const leaves = [core.GT.leave, 1.0, 3.0];
  const after = [0, 0.2, 0.3, 0.42, 0.7, 0.8, 0.9, 1.0, 1.1, 1.15, 1.3, 1.45, 1.6, 2.0];     // seconds after `leave`
  const pop = (t, leave) => core.EZ.back(core.seg(t, leave + 0.24, leave + 0.42));        // collapsePose's `minis`, for any leave
  const beats = [0.2, 0.3, 0.42, 0.8, 0.9, 1.05, 1.15, 1.3, 1.6];
  return {
    miniUnits: "The last beat of the greeting, in the greeting's 640x150 space (px, the island centred at x = 320). Times are seconds after `leave`, the moment the island starts to fold. A slot is {x, y, d}: centre and head width in px, d = 0 when the cat is not there. Slots are in the grid's cell order: top left, top right, bottom left, bottom right. miniSlots takes the pop-in (minis), the glide ({grid, four}) and the compact island (W, H, d).",
    miniTimeline: { ...core.GT3, greetEnd: core.GREET_END },
    miniGeometry: { row: core.MINI_ROW, grid: core.MINI_GRID, from: core.MINI_FROM, minD: core.MINI_MIN_D },
    miniGlideSamples: leaves.flatMap(leave => after.map(o => {
      const tMs = Math.round((leave + o) * 1000);
      return { leave, tMs, glide: core.miniGlide(tMs / 1000, leave) };
    })),
    miniSlotCases: geometries.flatMap(({ name, W, H, d }) => beats.map(o => {
      const leave = core.GT.leave, tMs = Math.round((leave + o) * 1000), t = tMs / 1000, minis = pop(t, leave), glide = core.miniGlide(t, leave);
      return { name, W, H, d, tMs, minis, grid: glide.grid, four: glide.four, slots: core.miniSlots(minis, glide, { W, H, d }) };
    })),
  };
});

// ── Stored cat settings (A-0d): what the Cat section of Settings saves, cleaned ──
// Every `raw` is something a settings file could hold, written as JSON (so no NaN or Infinity: the self-checks cover those, and
// a number that no JSON parser reads the same way, such as 1e999, is left out on purpose). `out` is what cleanCatSettings returns.
FILES['settings-cases.json'] = () => {
  const J = JSON.stringify, P = n => core.personaNamed(n), clean = core.cleanCatSettings;
  const custom = { preset: 'custom', energy: .27, curiosity: .83, chatty: .41, affection: .58, sass: .12, mischief: .99 };
  const noise = '{"preset":"chill","energy":0.12000000000000001,"curiosity":0.35,"chatty":0.3,"affection":0.65,"sass":0.3,"mischief":0.2}';
  const wrongTypes = { energy: 'high', curiosity: null, chatty: true, affection: [1], sass: {}, mischief: '0.9' };
  const one = (id, entry, rest = {}) => ({ ...rest, cats: { [id]: entry } });
  const rows = [
    ['nothing stored', null],
    ['an empty object', {}],
    ['text instead of an object', 'junk'],
    ['a number instead of an object', 7],
    ['an array instead of an object', [1, 2, 3]],
    ['true instead of an object', true],
    ['a fully valid value', { character: 'momo', motionStyle: 'classic', collar: 'band', furLines: true, cats: {
      momo: { motion: 'playful', collar: 'kerchief', personality: P('chill') },
      shrimpy: { motion: 'classic', collar: 'off', personality: P('sweet') },
      ginger: { motion: 'follow', collar: 'tag', personality: custom } } }],
    ['only the global settings', { character: 'momo', motionStyle: 'classic', collar: 'tag', furLines: true }],
    ['an unknown character', { character: 'tiger' }],
    ['a character in the wrong case', { character: 'Momo' }],
    ['a kitten is not a character', { character: 'momo kitten' }],
    ['a prototype name as the character', { character: '__proto__' }],
    ['another prototype name as the character', { character: 'constructor' }],
    ['a number as the character', { character: 7 }],
    ['styles that do not exist', { motionStyle: 'bogus', collar: 'scarf' }],
    ['follow is not a global style', { motionStyle: 'follow', collar: 'follow' }],
    ['styles in the wrong case', { motionStyle: 'Classic', collar: 'Band' }],
    ['styles of the wrong type', { motionStyle: 7, collar: true }],
    ['fur lines true', { furLines: true }],
    ['fur lines as the number 1', { furLines: 1 }],
    ['fur lines as the text true', { furLines: 'true' }],
    ['fur lines as null', { furLines: null }],
    ['valid overrides for some cats', { cats: { momo: { motion: 'classic', collar: 'band' }, ginger: { motion: 'playful', collar: 'off' }, noodle: { motion: 'follow', collar: 'kerchief' } } }],
    ['overrides that are not valid', { cats: { momo: { motion: 'bogus', collar: 'scarf' }, ginger: { motion: 7, collar: null }, noodle: { motion: 'Classic', collar: 'Tag' } } }],
    ['off is an override, not a missing collar', { collar: 'tag', cats: { momo: { collar: 'off' } } }],
    ['cats is an array', { cats: [] }],
    ['cats is text', { cats: 'x' }],
    ['cats is null', { cats: null }],
    ['cat entries that are not objects', { cats: { momo: 'x', ginger: null, noodle: [], puff: 7 } }],
    ['unknown cats and unknown keys', { theme: 'dark', cats: { tiger: { motion: 'classic' }, momo: { wardrobe: 'hat' } } }],
    ['prototype names as cats', { cats: { constructor: { motion: 'classic' }, ['__proto__']: { motion: 'classic' } } }],
    ['a personality stored as JSON text', one('momo', { personality: J(P('grumpy')) }, { character: 'momo' })],
    ['a personality that is not JSON', one('momo', { personality: '{"energy":' })],
    ['a personality that is not an object', { cats: { momo: { personality: 7 }, ginger: { personality: [1] }, noodle: { personality: null } } }],
    ['a personality with the wrong types', one('momo', { personality: wrongTypes })],
    ['a preset whose traits were changed', one('momo', { personality: { ...P('chill'), energy: .9 } })],
    ['a preset name that matches the traits', one('momo', { personality: P('hyper') })],
  ];
  const people = [
    ...Object.keys(core.PERSONAS).map(n => [`preset ${n} as an object`, P(n)]),
    ...Object.keys(core.PERSONAS).map(n => [`preset ${n} as JSON text`, J(P(n))]),
    ['custom values as an object', custom],
    ['custom values as JSON text', J(custom)],
    ['float noise on a preset is still the preset', noise],
    ['a preset changed by one slider', { ...P('chill'), sass: .9 }],
    ['a preset changed by 1e-6', { ...P('chill'), energy: .120001 }],
    ['custom with the numbers of a preset', { ...P('chill'), preset: 'custom' }],
    ['a name that does not match the traits', { ...P('chill'), preset: 'sweet' }],
    ['a preset name in the wrong case', { ...P('chill'), preset: 'Chill' }],
    ['an unknown preset name', { ...P('chill'), preset: 'moody' }],
    ['a preset name that is not text', { ...P('chill'), preset: 7 }],
    ['traits without a preset name', { energy: .12, curiosity: .35, chatty: .3, affection: .65, sass: .3, mischief: .2 }],
    ['a preset name alone', { preset: 'chill' }],
    ['balanced alone', { preset: 'balanced' }],
    ['an empty object', {}],
    ['an empty object as text', '{}'],
    ['traits out of range', { preset: 'custom', energy: 7, curiosity: -2, chatty: 1.5, affection: 100, sass: -.1, mischief: 2 }],
    ['wrong types', wrongTypes],
    ['wrong types as JSON text', J(wrongTypes)],
    ['numbers as text', { preset: 'custom', energy: '0.9', curiosity: '1' }],
    ['unknown keys are dropped', { ...P('sweet'), label: 'Sweet', hat: 1 }],
    ['nothing stored', null],
    ['text that is not JSON', 'not json'],
    ['an empty string', ''],
    ['a cut-off object', '{"preset":"chill","energy":0.12'],
    ['single quotes', "{'energy':0.2}"],
    ['a trailing comma', '{"energy":0.2,}'],
    ['NaN written in the text', '{"energy":NaN}'],
    ['garbage after the object', '{"energy":0.2} x'],
    ['JSON that is an array', '[1,2]'],
    ['JSON that is null', 'null'],
    ['JSON that is a number', '42'],
    ['JSON that is a string', '"x"'],
    ['a number instead of an object', 7],
    ['an array instead of an object', [0.1, 0.2]],
    ['true instead of an object', true],
  ];
  const applySource = clean({ character: 'momo', motionStyle: 'classic', collar: 'band', furLines: true, cats: {
    ginger: { motion: 'playful', collar: 'off', personality: P('hyper') }, momo: { motion: 'classic', collar: 'tag', personality: P('grumpy') }, noodle: { personality: custom } } });
  const apply = [
    ['a customised cat to every cat', applySource, 'ginger'],
    ['a cat that follows to every cat', applySource, 'shrimpy'],
    ['a personality that is Custom to every cat', applySource, 'noodle'],
    ['an unknown cat is Shrimpy', applySource, 'tiger'],
    ['a default install', core.defaultCatSettings(), 'momo'],
  ].map(([name, settings, from]) => ({ name, settings, from, out: core.applyToAllCats(settings, from) }));
  const derive = [
    ['a default install', core.defaultCatSettings()],
    ['global Classic with a few overrides', clean({ motionStyle: 'classic', collar: 'band', cats: { momo: { motion: 'playful', collar: 'off' }, ginger: { motion: 'follow', collar: 'kerchief' }, noodle: { motion: 'classic', collar: 'tag', personality: P('sweet') } } })],
    ['global Playful, every cat overridden', core.applyToAllCats(clean({ cats: { momo: { motion: 'classic', collar: 'kerchief', personality: P('chatty') } } }), 'momo')],
  ].map(([name, settings]) => ({ name, settings, engineCfg: core.engineCfg(settings), motionFor: core.CAT_IDS.map(id => core.motionFor(settings, id)), collarFor: core.CAT_IDS.map(id => core.collarFor(settings, id)) }));
  return {
    version: 1,
    note: 'Raw is what a settings file might hold, written as JSON. cases: cleanCatSettings(raw) is out. personalities: cleanPersonality(raw) is out; a raw string is JSON text. applyAll, derived: settings are already clean. motionFor and collarFor list one value per cat in ids order.',
    ids: core.CAT_IDS,
    follow: core.FOLLOW,
    motionStyles: core.MOTION_STYLES,
    collarStyles: core.COLLAR_STYLES,
    defaults: core.defaultCatSettings(),
    cases: rows.map(([name, raw]) => ({ name, raw, out: clean(raw) })),
    personalities: people.map(([name, raw]) => ({ name, raw, out: core.cleanPersonality(raw) })),
    applyAll: apply,
    derived: derive,
  };
};

// ── Display settings (B-0): what Settings → Cat → Display saves, cleaned ──────
// Every `raw` is something a settings file could hold, written as JSON (so no undefined, NaN or Infinity: a port adds its own test for a value that is not
// there at all). `out` is what cleanDisplaySettings returns. The 300-pill map is built here and written out in full.
FILES['display-cases.json'] = () => {
  const J = JSON.stringify, clean = core.cleanDisplaySettings;
  const many = Object.fromEntries(Array.from({ length: 300 }, (_, i) => ['agent_a' + String(i).padStart(3, '0'), core.CAT_IDS[i % 16]]));
  const rows = [
    ['nothing stored', null],
    ['an empty object', {}],
    ['text instead of an object', 'junk'],
    ['a number instead of an object', 7],
    ['an array instead of an object', [1, 2, 3]],
    ['true instead of an object', true],
    ['a fully valid value', { displayMode: 'perAgent', pair: ['momo', 'ginger'], agentCats: { integration_claude: 'oreo', agent_codex: 'momo', agent_gemini: 'latte', ai_openai: 'blue' } }],
    ['Two cats with the default pair', { displayMode: 'two', pair: ['shrimpy', 'momo'] }],
    ['an unknown mode', { displayMode: 'both' }],
    ['a mode in the wrong case', { displayMode: 'Two' }],
    ['a mode with a space', { displayMode: 'two ' }],
    ['a number as the mode', { displayMode: 2 }],
    ['a prototype name as the mode', { displayMode: '__proto__' }],
    ['the pair as JSON text, as the Mac stores it', { displayMode: 'two', pair: '["noodle","leo"]' }],
    ['a pair with an unknown coat', { pair: ['momo', 'tiger'] }],
    ['a pair of the same coat', { pair: ['leo', 'leo'] }],
    ['a pair of the last coat twice', { pair: ['noodle', 'noodle'] }],
    ['a pair of three', { pair: ['momo', 'ginger', 'latte'] }],
    ['a pair that is not a pair', { pair: 'momo' }],
    ['agent coats with a bad one for Claude Code', { agentCats: { integration_claude: 'tiger', agent_codex: 'momo' } }],
    ['agent coats with a bad one for Gemini CLI', { agentCats: { agent_gemini: 'tiger', agent_cursor: 7 } }],
    ['agent coats for pills that are not known', { agentCats: { agent_zed: 'noodle', integration_stripe: 'blue', ai_openai: 'puff' } }],
    ['agent coats whose pill IDs are not pill IDs', { agentCats: { Agent_Zed: 'momo', 'agent zed': 'momo', '': 'momo', a: 'momo', '1agent': 'momo', 'agent/zed': 'momo' } }],
    ['prototype names as pills', { agentCats: { constructor: 'momo', prototype: 'momo', ['__proto__']: 'momo', agent_ok: 'ginger' } }],
    ['agent coats that are not an object', { agentCats: ['momo'] }],
    ['agent coats that are text', { agentCats: 'agent_x=momo' }],
    ['agent coats that are null', { agentCats: null }],
    ['agent coats written out of order', { agentCats: { integration_claude: 'shrimpy', agent_zed: 'momo', agent_alpha: 'ginger', ai_x: 'blue' } }],
    ['three hundred pills keep the first 256', { agentCats: many }],
    ['the Cat settings are not display settings', { character: 'momo', motionStyle: 'classic', collar: 'band', furLines: true, cats: {} }],
  ];
  const pairs = [
    ['the default pair', ['shrimpy', 'momo']],
    ['the pair swapped', ['momo', 'shrimpy']],
    ['two extra coats', ['ginger', 'noodle']],
    ['the same coat twice', ['ginger', 'ginger']],
    ['Shrimpy twice', ['shrimpy', 'shrimpy']],
    ['Momo twice', ['momo', 'momo']],
    ['the last coat twice wraps to the first', ['noodle', 'noodle']],
    ['the one before the last, twice', ['puff', 'puff']],
    ['as JSON text', '["latte","cloud"]'],
    ['as JSON text with the same coat', '["latte","latte"]'],
    ['as JSON text with spaces', ' [ "latte" , "cloud" ] '],
    ['an empty array', []],
    ['one coat', ['momo']],
    ['three coats', ['momo', 'ginger', 'latte']],
    ['an unknown coat first', ['tiger', 'momo']],
    ['an unknown coat second', ['momo', 'tiger']],
    ['a coat in the wrong case', ['Momo', 'shrimpy']],
    ['a coat with a space', ['momo ', 'shrimpy']],
    ['a kitten is not a coat', ['momo kitten', 'shrimpy']],
    ['a number as a coat', ['momo', 7]],
    ['null as a coat', [null, 'momo']],
    ['a nested array as a coat', [['momo'], ['ginger']]],
    ['prototype names as coats', ['constructor', '__proto__']],
    ['an object instead of an array', { 0: 'momo', 1: 'ginger' }],
    ['a plain coat name', 'momo'],
    ['two names with a comma', 'shrimpy,momo'],
    ['an empty string', ''],
    ['a blank string', ' '],
    ['JSON text that is not an array', '{"a":"momo","b":"ginger"}'],
    ['JSON text with one coat', '["momo"]'],
    ['JSON text cut off', '["momo","ginger"'],
    ['JSON text with single quotes', "['momo','ginger']"],
    ['JSON text with a trailing comma', '["momo","ginger",]'],
    ['JSON text with garbage after it', '["momo","ginger"] x'],
    ['JSON text that is null', 'null'],
    ['JSON text that is a number', '42'],
    ['JSON text with an unknown coat', '["momo","tiger"]'],
    ['nothing stored', null],
    ['a number', 7],
    ['true', true],
  ];
  const agents = [
    ['nothing stored', null],
    ['an empty map', {}],
    ['only defaults', { integration_claude: 'shrimpy', agent_codex: 'momo' }],
    ['the defaults changed', { integration_claude: 'oreo', agent_codex: 'blue' }],
    ['a pill that is not known is kept', { agent_zed: 'noodle' }],
    ['an AI provider and an integration are kept too', { ai_openai: 'blue', integration_stripe: 'puff' }],
    ['a bad coat for Claude Code is its default', { integration_claude: 'tiger' }],
    ['a bad coat for Codex is its default', { agent_codex: 7 }],
    ['a bad coat for another agent is dropped', { agent_gemini: 'tiger' }],
    ['a coat in the wrong case is bad', { agent_gemini: 'Momo', integration_claude: 'SHRIMPY' }],
    ['a kitten is not a coat', { agent_gemini: 'momo kitten' }],
    ['null and an array are bad coats', { agent_a: null, agent_b: ['momo'], agent_c: {}, agent_d: true }],
    ['out of order comes back in order', { integration_claude: 'shrimpy', agent_zed: 'momo', agent_alpha: 'ginger', ai_x: 'blue' }],
    ['pill IDs with a capital, a space, a slash or too short', { Agent_X: 'momo', 'agent x': 'momo', 'agent/x': 'momo', a: 'momo', '': 'momo' }],
    ['a hyphen and a digit are fine', { 'agent_my-tool-2': 'snow' }],
    ['a 64-character pill ID is fine and a 65-character one is not', { ['a' + 'b'.repeat(63)]: 'leo', ['a' + 'b'.repeat(64)]: 'leo' }],
    ['prototype names', { constructor: 'momo', prototype: 'momo', ['__proto__']: 'momo' }],
    ['not an object: an array', ['momo']],
    ['not an object: text', 'agent_x=momo'],
    ['not an object: a number', 7],
    ['300 pills', many],
  ];
  const ids = [
    'integration_claude', 'agent_codex', 'agent_gemini', 'agent_antigravity', 'agent_cursor', 'agent_my-tool-2', 'agent_', 'agent', 'agentcodex', 'integration_claude2', 'integration_stripe', 'integration_music', 'ai_openai',
    'Agent_codex', 'agent codex', 'agent_x\n', 'agent_x ', 'a', 'ab', '1agent', '_agent', 'constructor', 'prototype', '__proto__', 'toString', '', ' ', 'a' + 'b'.repeat(63), 'a' + 'b'.repeat(64),
  ].map(id => ({ id, pill: core.isPillId(id), agent: core.isAgentPill(id), default: core.defaultAgentCat(id) }));
  return {
    version: 1,
    note: 'Raw is what a settings file might hold, written as JSON (undefined, NaN and Infinity cannot be written: a port adds its own tests for a value that is not there). cases: cleanDisplaySettings(raw) is out. pairs: cleanPair(raw) is out; a raw string is JSON text. agentCats: cleanAgentCats(raw) is out. pillIds: isPillId, isAgentPill and defaultAgentCat. The map with 300 pills is agent_a000 to agent_a299, each with the cat of that number in ids order.',
    ids: core.CAT_IDS,
    modes: core.DISPLAY_MODES,
    defaultPair: core.DEFAULT_PAIR,
    defaultAgentCats: core.DEFAULT_AGENT_CATS,
    maxAgentCats: core.MAX_AGENT_CATS,
    pillIdPattern: core.PILL_ID.source,
    defaults: core.defaultDisplaySettings(),
    cases: rows.map(([name, raw]) => ({ name, raw, out: clean(raw) })),
    pairs: pairs.map(([name, raw]) => ({ name, raw, out: core.cleanPair(raw) })),
    agentCats: agents.map(([name, raw]) => ({ name, raw, out: core.cleanAgentCats(raw) })),
    pillIds: ids,
  };
};

// ── Agent cats (B-0): giving each agent its coat ──────────────────────────────
// A row's `rand` names its random source: {seed: n} is rng(n); {values: [...]} gives those numbers in order, then 0; {none: true} must never be called.
// `draws` is how many random numbers the call drew: the order and the number of draws are part of the contract, because a port that draws one more
// or one fewer drifts from the rows after it. The rows use no NaN or Infinity (JSON cannot hold them): the self-checks cover a source that misbehaves.
export function randFor(spec) {
  const seeded = spec.seed !== undefined ? core.rng(spec.seed) : null;
  const f = () => { f.draws++; if (seeded) return seeded(); if (spec.values) return f.draws <= spec.values.length ? spec.values[f.draws - 1] : 0; throw new Error('rand() must not be called'); };
  f.draws = 0;
  return f;
}
FILES['agent-cat-cases.json'] = () => {
  const IDS = core.CAT_IDS, OTHER = IDS.slice(2), run = (fn, args, spec) => { const rand = randFor(spec), out = fn(...args, rand); return { out, draws: rand.draws }; };
  const named = c => Object.fromEntries(c.map((x, i) => ['agent_a' + String(i).padStart(2, '0'), x]));
  const once = named(OTHER.slice(0, 13)), fourteen = named(OTHER);
  const dup = { ...fourteen, ...Object.fromEntries(IDS.filter(c => c !== 'leo').map(c => ['agent_d_' + c, c])) };
  const NONE = { none: true };
  const rows = [
    ['Claude Code is Shrimpy', 'integration_claude', {}, 'ginger', NONE],
    ['Codex is Momo', 'agent_codex', {}, 'ginger', NONE],
    ['a stored coat wins over the default', 'integration_claude', { integration_claude: 'oreo' }, 'ginger', NONE],
    ['a stored coat for another agent', 'agent_gemini', { agent_gemini: 'latte' }, 'ginger', NONE],
    ['a bad stored coat for Codex is Momo', 'agent_codex', { agent_codex: 'tiger' }, 'ginger', NONE],
    ['an integration gets the Main cat', 'integration_stripe', {}, 'cloud', NONE],
    ['an AI provider gets the Main cat', 'ai_openai', { agent_y: 'momo' }, 'cloud', NONE],
    ['a pill ID that is not one gets the Main cat', 'Agent_X', {}, 'cloud', NONE],
    ['a prototype name gets the Main cat', '__proto__', {}, 'cloud', NONE],
    ['agent_ alone is not an agent', 'agent_', {}, 'cloud', NONE],
    ['a Main cat that is not a cat is Shrimpy', 'integration_stripe', {}, 'tiger', NONE],
    ['a new agent, seed 1', 'agent_gemini', {}, 'shrimpy', { seed: 1 }],
    ['a new agent, seed 2', 'agent_gemini', {}, 'shrimpy', { seed: 2 }],
    ['a new agent, seed 7', 'agent_gemini', {}, 'shrimpy', { seed: 7 }],
    ['a new agent, seed 13', 'agent_gemini', {}, 'shrimpy', { seed: 13 }],
    ['a new agent, seed 2026', 'agent_gemini', {}, 'ginger', { seed: 2026 }],
    ['a new agent with the first number 0 gets the first free coat', 'agent_gemini', {}, 'shrimpy', { values: [0] }],
    ['a new agent with a number just under 1 gets the last free coat', 'agent_gemini', {}, 'shrimpy', { values: [0.9999999] }],
    ['a new agent with 0.5', 'agent_gemini', {}, 'shrimpy', { values: [0.5] }],
    ['a number of 1 is held to the last free coat', 'agent_gemini', {}, 'shrimpy', { values: [1] }],
    ['a negative number is held to the first free coat', 'agent_gemini', {}, 'shrimpy', { values: [-3] }],
    ['the Main cat is taken too', 'agent_gemini', {}, 'ginger', { values: [0] }],
    ['the last coat as the Main cat', 'agent_gemini', {}, 'noodle', { values: [0.9999999] }],
    ['other agents\' coats are taken', 'agent_gemini', { agent_a: 'ginger', agent_b: 'midnight', agent_c: 'latte' }, 'shrimpy', { values: [0] }],
    ['a stored coat frees its default', 'agent_gemini', { integration_claude: 'oreo', agent_codex: 'ginger' }, 'midnight', { values: [0] }],
    ['a stored coat frees Momo only', 'agent_gemini', { integration_claude: 'oreo', agent_codex: 'ginger', agent_y: 'shrimpy' }, 'midnight', { values: [0] }],
    ['a stored coat the user gave Claude Code is taken', 'agent_gemini', { integration_claude: 'oreo' }, 'ginger', { values: [0] }],
    ['all 16 taken once: the first, Shrimpy', 'agent_new', once, 'noodle', NONE],
    ['all 16 taken, Shrimpy twice: Momo', 'agent_new', fourteen, 'shrimpy', NONE],
    ['all 16 taken, Leo least used', 'agent_new', dup, 'shrimpy', NONE],
    ['all 16 taken, Leo used twice: Momo again', 'agent_new', { ...dup, agent_leo2: 'leo' }, 'shrimpy', NONE],
    ['a map that is not an object', 'agent_gemini', 'x', 'shrimpy', { values: [0] }],
    ['a map with prototype names', 'agent_gemini', JSON.parse('{"__proto__":"momo","constructor":"momo","agent_ok":"tiger"}'), 'shrimpy', { values: [0] }],
    ['a map with bad coats', 'agent_gemini', { agent_a: 'tiger', agent_b: 7, agent_c: null }, 'shrimpy', { values: [0] }],
  ];
  const rerolls = [
    ['the dice on an agent with a coat', 'agent_a', { agent_a: 'blue', agent_b: 'snow' }, 'cloud', { seed: 1 }],
    ['the dice, first free coat', 'agent_a', { agent_a: 'blue', agent_b: 'snow' }, 'cloud', { values: [0] }],
    ['the dice, last free coat', 'agent_a', { agent_a: 'blue', agent_b: 'snow' }, 'cloud', { values: [0.9999999] }],
    ['the dice on Claude Code: not Shrimpy again, and stored', 'integration_claude', {}, 'cloud', { values: [0] }],
    ['the dice on Codex: not Momo again', 'agent_codex', {}, 'cloud', { values: [0] }],
    ['the dice on an agent with no coat yet', 'agent_new', {}, 'cloud', { values: [0] }],
    ['the dice on an integration is the Main cat', 'integration_stripe', { agent_y: 'momo' }, 'cloud', NONE],
    ['the dice on a bad pill ID', 'Agent_X', {}, 'cloud', NONE],
    ['the dice with all coats taken: the first that is not its own', 'agent_a00', once, 'noodle', NONE],
    ['the dice on Claude Code with all coats taken', 'integration_claude', once, 'noodle', NONE],
    ['the dice, seed 7', 'agent_gemini', { agent_gemini: 'latte', agent_cursor: 'ginger' }, 'momo', { seed: 7 }],
  ];
  const assigns = [
    ['a few agents, seed 3', ['agent_codex', 'agent_gemini', 'integration_stripe', 'agent_cursor', 'agent_gemini', 'integration_claude', 'ai_openai', 'Bad Id', 'agent_gemini'], {}, 'cloud', { seed: 3 }],
    ['a second pass changes nothing', ['agent_gemini', 'agent_cursor'], { agent_cursor: 'ginger', agent_gemini: 'latte' }, 'cloud', NONE],
    ['reset to defaults: an empty map again', ['integration_claude', 'agent_codex', 'agent_gemini'], {}, 'shrimpy', { seed: 4 }],
    ['twenty agents, seed 8', Array.from({ length: 20 }, (_, i) => 'agent_m' + String(i).padStart(2, '0')), {}, 'shrimpy', { seed: 8 }],
    ['agents that are not a list', null, { agent_x: 'momo' }, 'cloud', NONE],
    ['no agents', [], {}, 'cloud', NONE],
  ];
  return {
    version: 1,
    note: 'cases: agentCatFor(pill, agentCats, mainCat, rand) is out {cat, agentCats, assigned}. rerolls: rerollAgentCat is out {cat, agentCats}. assigns: assignAgentCats(pills, agentCats, mainCat, rand) is out {agentCats}. `rand` names the random source (see the harness note in docs/CAT-CONTRACT.md); `draws` is how many numbers the call drew.',
    ids: IDS,
    defaults: core.DEFAULT_AGENT_CATS,
    cases: rows.map(([name, pill, agentCats, mainCat, rand]) => ({ name, pill, agentCats, mainCat, rand, ...run(core.agentCatFor, [pill, agentCats, mainCat], rand) })),
    rerolls: rerolls.map(([name, pill, agentCats, mainCat, rand]) => ({ name, pill, agentCats, mainCat, rand, ...run(core.rerollAgentCat, [pill, agentCats, mainCat], rand) })),
    assigns: assigns.map(([name, pills, agentCats, mainCat, rand]) => { const { out, draws } = run(core.assignAgentCats, [pills, agentCats, mainCat], rand); return { name, pills, agentCats, mainCat, rand, out: { agentCats: out }, draws }; }),
  };
};

// ── The cast of each display mode (B-0): which cat is drawn where ─────────────
// `input` is castOf's input written as JSON (so a task's `last` is a number, never NaN or Infinity: the self-checks cover those). Every scenario is
// replayed in all three modes, because the table of places is the contract: the same island gives a different cast in each.
FILES['cast-cases.json'] = () => {
  const T = (id, state = 'idle', last = 0) => ({ id, state, last });
  const island = [T('integration_claude', 'working', 100), T('agent_codex', 'approval', 90), T('agent_gemini', 'thinking', 80), T('agent_antigravity', 'idle', 10), T('integration_stripe', 'idle', 5), T('integration_music', 'idle', 1)];
  const base = { tasks: island, focusId: 'integration_claude', mainCat: 'ginger', pair: ['latte', 'cloud'], agentCats: { agent_gemini: 'oreo', agent_antigravity: 'leo' } };
  const idle = ids => ids.map(id => T(id));
  const many = [T('integration_claude'), ...Array.from({ length: 8 }, (_, i) => T('agent_s' + i)), T('integration_stripe')];
  const scenarios = [
    ['the island, Claude Code focused', base],
    ['the island, Gemini CLI focused', { ...base, focusId: 'agent_gemini' }],
    ['the island, Codex focused', { ...base, focusId: 'agent_codex' }],
    ['the island, an integration focused', { ...base, focusId: 'integration_stripe' }],
    ['the island, nothing focused', { ...base, focusId: null }],
    ['the default pair and Main cat', { ...base, mainCat: 'shrimpy', pair: ['shrimpy', 'momo'], agentCats: {} }],
    ['a stored coat for Claude Code and Codex', { ...base, agentCats: { integration_claude: 'oreo', agent_codex: 'blue' }, focusId: 'agent_codex' }],
    ['the pair is one coat twice', { ...base, pair: ['momo', 'momo'] }],
    ['the pair as JSON text', { ...base, pair: '["noodle","puff"]' }],
    ['an agent that has no coat yet', { ...base, agentCats: {}, focusId: 'agent_antigravity' }],
    ['more pills than the row holds', { tasks: many, focusId: 'agent_s2', mainCat: 'blue', pair: ['snow', 'mocha'], agentCats: { agent_s1: 'leo' } }],
    ['the focused pill leaves the row and the second cat leaves it too', { tasks: many, focusId: 'integration_claude', mainCat: 'blue', pair: ['snow', 'mocha'], agentCats: {} }],
    ['only Claude Code', { tasks: [T('integration_claude', 'working')], focusId: 'integration_claude', mainCat: 'ginger', pair: ['latte', 'cloud'], agentCats: {} }],
    ['only integrations', { tasks: idle(['integration_stripe', 'ai_openai']), focusId: 'integration_stripe', mainCat: 'ginger', pair: ['latte', 'cloud'], agentCats: {} }],
    ['no pills at all', { tasks: [], focusId: null, mainCat: 'ginger', pair: ['latte', 'cloud'], agentCats: {} }],
    ['a pill listed twice', { tasks: [T('agent_a', 'working', 5), T('agent_a', 'error', 9), T('agent_b')], focusId: null, mainCat: 'ginger', pair: ['latte', 'cloud'], agentCats: {} }],
  ];
  const rank = (name, tasks, focusId = 'integration_claude') => [name, { tasks: [T('integration_claude', 'idle', 0), ...tasks], focusId, mainCat: 'ginger', pair: ['latte', 'cloud'], agentCats: {} }];
  const ranking = [
    rank('approval beats busy, however old', [T('agent_a', 'working', 50), T('agent_b', 'approval', 1)]),
    rank('approval beats error', [T('agent_a', 'error', 50), T('agent_b', 'approval', 1)]),
    rank('a question and an approval share a rank: the most recent', [T('agent_a', 'question', 5), T('agent_b', 'approval', 1)]),
    rank('error beats busy', [T('agent_a', 'working', 50), T('agent_b', 'error', 1)]),
    rank('busy beats idle, however recent', [T('agent_a', 'idle', 90), T('agent_b', 'working', 1)]),
    rank('working, thinking and searching share a rank: the most recent', [T('agent_a', 'thinking', 5), T('agent_b', 'searching', 9), T('agent_c', 'working', 7)]),
    rank('everything else by the most recent event', [T('agent_a', 'finished', 5), T('agent_b', 'idle', 9), T('agent_c', 'sleeping', 7)]),
    rank('a tie goes to the first in the app\'s order', [T('agent_a', 'working', 5), T('agent_b', 'working', 5)]),
    rank('an integration is never the second cat', [T('integration_stripe', 'approval', 99), T('agent_a', 'idle', 0)]),
    rank('the focused agent is never its own second cat', [T('agent_a', 'approval', 99), T('integration_stripe', 'error', 5)], 'agent_a'),
    rank('Claude Code can be the second cat', [T('agent_a', 'idle', 0)], 'agent_a'),
    rank('an unknown state is idle', [T('agent_a', 'bogus', 99), T('agent_b', 'idle', 1)]),
    rank('a state that is not text is idle', [T('agent_a', 7, 99), T('agent_b', 'idle', 1)]),
    rank('a missing time is 0', [{ id: 'agent_a', state: 'idle' }, T('agent_b', 'idle', 1)]),
    rank('a time that is text is 0', [{ id: 'agent_a', state: 'idle', last: 'now' }, T('agent_b', 'idle', 1)]),
    rank('a negative time is older than 0', [T('agent_a', 'idle', -5), T('agent_b', 'idle', 0)]),
  ];
  const hostile = [
    ['tasks that are not a list', { tasks: 'x', focusId: null, mainCat: 'ginger' }],
    ['tasks that are null', { tasks: null, focusId: 'integration_claude' }],
    ['entries that are not tasks', { tasks: [null, 7, 'x', [], {}, { id: 7 }, T('agent_ok', 'working', 1)], focusId: null }],
    ['pill IDs that are not pill IDs', { tasks: [T('Bad Id'), T('__proto__'), T('constructor'), T('prototype'), T('A'), T('agent_ok')], focusId: '__proto__' }],
    ['a Main cat that is not a cat', { tasks: island, focusId: 'integration_claude', mainCat: 'tiger', pair: ['latte', 'cloud'] }],
    ['a pair that is not a pair', { tasks: island, focusId: 'integration_claude', mainCat: 'ginger', pair: [1, 2] }],
    ['a map that is not a map', { tasks: island, focusId: 'integration_claude', mainCat: 'ginger', agentCats: 'x' }],
    ['a map with bad coats and prototype names', { tasks: island, focusId: 'agent_gemini', mainCat: 'ginger', agentCats: { agent_gemini: 'tiger', constructor: 'momo', integration_claude: 7 } }],
    ['a focus that is a number', { tasks: island, focusId: 7, mainCat: 'ginger' }],
    ['a focus that is not in the list', { tasks: island, focusId: 'agent_not_listed', mainCat: 'ginger' }],
    ['an input that is not an object', 7],
    ['nothing', null],
  ];
  const cases = [];
  for (const [name, input] of [...scenarios, ...ranking, ...hostile]) for (const mode of core.DISPLAY_MODES) cases.push({ name, mode, input, out: core.castOf(mode, input) });
  for (const mode of ['bogus', 'Two', '', 'perAgent ']) cases.push({ name: `the mode ${JSON.stringify(mode)} is One cat`, mode, input: base, out: core.castOf(mode, base) });
  return {
    version: 1,
    note: 'castOf(mode, input) is out {mode, big, second, pills, drop, greeting}. Every scenario, ranking and hostile input is listed once per mode. `last` is a time in ms; a state that is not one of `states` is idle.',
    ids: core.CAT_IDS,
    modes: core.DISPLAY_MODES,
    pillRow: core.PILL_ROW,
    states: core.STATES,
    busyRank: [...core.STATES, 'bogus'].map(state => ({ state, rank: core.busyRank(state) })),
    cases,
  };
};

// ── Kittens (B-0): the reducer, the order and the slots ───────────────────────
// scripts: each starts from `from` (a list, [] when it is missing), applies the events one by one with kittenStep, and `list` is the whole list after each event.
// Times are ms on any one clock. Events cannot carry undefined, NaN or Infinity in JSON: a missing key or null stands for them, and the self-checks cover the others.
FILES['kitten-cases.json'] = () => {
  const K = (id, state = 'working', born = 0, last = born, extra = {}) => ({ id, type: '', session: null, state, born, last, until: null, ...extra });
  const MIN = 60 * 1000;
  const script = (name, events, from = []) => { let list = from; const steps = events.map(ev => { list = core.kittenStep(list, ev); return { ev, list }; }); return { name, from, steps }; };
  const nine = Array.from({ length: 9 }, (_, i) => ({ type: 'start', id: 'k' + i, agentType: 'Explore', t: 100 + i }));
  const odd = [K('x', 'working', 50), K('y', 'working', 10), K('z', 'working', 30), ...Array.from({ length: 5 }, (_, i) => K('p' + i, 'working', 100 + i))];
  const scripts = [
    script('the mockup scene: three kittens, one searching, one waiting on an approval', [{ type: 'start', id: 'a', agentType: 'Explore', t: 1 }, { type: 'start', id: 'b', agentType: 'general-purpose', t: 2 }, { type: 'start', id: 'c', agentType: 'Explore', t: 3 }, { type: 'tool', id: 'b', tool: 'Grep', t: 4 }, { type: 'permission', id: 'a', t: 5 }]),
    script('a kitten\'s life: tools, an approval, its answer, its farewell and its removal', [{ type: 'start', id: 'a1', agentType: 'Explore', t: 1000 }, { type: 'tool', id: 'a1', tool: 'Read', t: 1100 }, { type: 'tool', id: 'a1', tool: 'WebSearch', t: 1200 }, { type: 'permission', id: 'a1', t: 1300 }, { type: 'resolved', id: 'a1', t: 1400 }, { type: 'tool', id: 'a1', tool: 'Edit', t: 1500 }, { type: 'stop', id: 'a1', t: 2000 }, { type: 'tick', t: 2599 }, { type: 'tick', t: 2600 }]),
    script('the farewell lasts 600 ms and the next event removes it', [{ type: 'start', id: 'a1', t: 0 }, { type: 'start', id: 'a2', t: 5 }, { type: 'stop', id: 'a1', t: 1000 }, { type: 'tool', id: 'a2', tool: 'Bash', t: 1599 }, { type: 'tool', id: 'a2', tool: 'Bash', t: 1600 }]),
    script('a late event after the stop brings nothing back', [{ type: 'start', id: 'a1', t: 0 }, { type: 'stop', id: 'a1', t: 10 }, { type: 'tool', id: 'a1', tool: 'Bash', t: 20 }, { type: 'permission', id: 'a1', t: 30 }, { type: 'tick', t: 700 }, { type: 'tool', id: 'a1', tool: 'Bash', t: 800 }, { type: 'permission', id: 'a1', t: 900 }]),
    script('an event for an id that never started creates nothing', [{ type: 'tool', id: 'ghost', tool: 'Bash', t: 1 }, { type: 'permission', id: 'ghost', t: 2 }, { type: 'resolved', id: 'ghost', t: 3 }, { type: 'stop', id: 'ghost', t: 4 }]),
    script('a repeated start only refreshes', [{ type: 'start', id: 'a1', agentType: 'Explore', t: 10 }, { type: 'start', id: 'a1', agentType: 'Plan', t: 20 }, { type: 'start', id: 'a1', t: 30 }]),
    script('a start for an id that is leaving makes a new kitten', [{ type: 'start', id: 'a1', t: 0 }, { type: 'stop', id: 'a1', t: 10 }, { type: 'start', id: 'a1', t: 20 }]),
    script('nine starts: the oldest goes', nine),
    script('a ninth start drops the oldest by born, not by place', [{ type: 'start', id: 'new', t: 200 }, { type: 'start', id: 'x', t: 201 }], odd),
    script('the parent stops: every kitten goes', [{ type: 'start', id: 'a', t: 1 }, { type: 'start', id: 'b', t: 2 }, { type: 'permission', id: 'b', t: 3 }, { type: 'stop', id: 'a', t: 4 }, { type: 'end', t: 5 }, { type: 'end', t: 6 }]),
    script('two sessions of one agent: a session ending takes only its own kittens and those with no session', [{ type: 'start', id: 'a1', session: 'S1', t: 1 }, { type: 'start', id: 'a2', session: 'S2', t: 2 }, { type: 'start', id: 'a3', t: 3 }, { type: 'start', id: 'a4', session: 'S1', t: 4 }, { type: 'end', session: 'S1', t: 5 }, { type: 'end', session: 'S9', t: 6 }, { type: 'end', session: 'S2', t: 7 }]),
    script('an end with no session, or one that is not text, takes every kitten', [{ type: 'start', id: 'a1', session: 'S1', t: 1 }, { type: 'start', id: 'a2', t: 2 }, { type: 'end', session: 7, t: 3 }, { type: 'start', id: 'a3', session: 'S1', t: 4 }, { type: 'end', t: 5 }]),
    script('a repeated start with a session sets it, and without one keeps it', [{ type: 'start', id: 'a1', session: 'S1', t: 1 }, { type: 'start', id: 'a1', t: 2 }, { type: 'start', id: 'a1', session: 'S2', t: 3 }]),
    script('the sleep timer sweeps the stale', [{ type: 'start', id: 'old', t: 0 }, { type: 'start', id: 'mid', t: 5 * MIN }, { type: 'tool', id: 'old', tool: 'Bash', t: 1000 }, { type: 'sweep', t: 10 * MIN + 999 }, { type: 'sweep', t: 10 * MIN + 1000 }, { type: 'sweep', t: 20 * MIN }]),
    script('a permission answered without a request keeps the state', [{ type: 'start', id: 'a', t: 1 }, { type: 'tool', id: 'a', tool: 'Grep', t: 2 }, { type: 'resolved', id: 'a', t: 3 }]),
    script('a tool event ends an approval', [{ type: 'start', id: 'a', t: 1 }, { type: 'permission', id: 'a', t: 2 }, { type: 'tool', id: 'a', tool: 'Edit', t: 3 }]),
    script('Claude Code without agent_id on tool events: a kitten at start and a farewell at stop', [{ type: 'start', id: 'a1', agentType: 'Explore', t: 0 }, { type: 'tool', tool: 'Grep', t: 1 }, { type: 'tool', id: null, tool: 'Grep', t: 2 }, { type: 'permission', t: 3 }, { type: 'stop', id: 'a1', t: 4 }]),
    script('ids that are not ids', [{ type: 'start', id: '', t: 1 }, { type: 'start', id: 7, t: 2 }, { type: 'start', id: null, t: 3 }, { type: 'start', t: 4 }, { type: 'start', id: 'x'.repeat(129), t: 5 }, { type: 'start', id: 'x'.repeat(128), t: 6 }]),
    script('a type that is long or not text', [{ type: 'start', id: 'a', agentType: 'y'.repeat(100), t: 1 }, { type: 'start', id: 'b', agentType: 7, t: 2 }]),
    script('events that are malformed change nothing', [{ type: 'start', id: 'a', t: 1 }, null, 7, 'start', [], {}, { type: 'tool', id: 'a', tool: 'Grep' }, { type: 'tool', id: 'a', tool: 'Grep', t: '5' }, { type: 'tool', id: 'a', tool: 'Grep', t: null }, { type: 'bogus', id: 'a', t: 9 }, { type: 7, t: 9 }]),
    script('a list that is not clean is cleaned', [{ type: 'tick', t: 1 }], [null, 7, K('e'), K('e', 'approval', 5), K('b', 'sleeping'), { id: '', state: 'working', born: 0, last: 0 }, K('l', 'leaving', 0, 0, { until: 5 })]),
  ];
  const orderLists = [
    ['approvals first, then the newest', [K('old', 'working', 1), K('wait', 'approval', 2), K('new', 'searching', 9), K('mid', 'working', 5), K('wait2', 'approval', 8), K('bye', 'leaving', 7, 7, { until: 99 })]],
    ['a tie in born: the later one in the list is newer', [K('a', 'working', 5), K('b', 'working', 5), K('c', 'working', 5)]],
    ['nothing', []],
    ['a list that is not a list', null],
    ['a list with entries that are not kittens', [null, 7, K('ok', 'working', 1), { id: 'x' }]],
  ];
  const views = [[50, 'before the farewell ends'], [99, 'when the farewell ends'], [1000, 'long after'], [null, 'a time that is not a number']];
  const viewList = orderLists[0][1];
  const sl = (n, st = ['approval', 'searching', 'working']) => Array.from({ length: n }, (_, i) => K('k' + i, st[i % st.length], 10 - i));
  const slotRows = [];
  for (const place of Object.keys(core.KITTEN_PLACES)) for (const n of [0, 1, 2, 3, 4, 7]) slotRows.push([`${place} with ${n}`, place, sl(n)]);
  slotRows.push(['an unknown place', 'nowhere', sl(3)], ['a prototype name as the place', '__proto__', sl(1)], ['a place that is not text', 7, sl(1)], ['kittens that are not kittens', 'bigExpanded', [null, 7, { id: '' }, { id: 'a', state: 7 }, K('ok')]], ['kittens that are not a list', 'pill', null]);
  return {
    version: 1,
    note: 'scripts: kittenStep over the events, `list` after each. order: kittenOrder(list) is the ids in order. views: kittenView(list, now) is the ids. cleans: cleanKittens(raw). slots: kittenSlots(place, kittens) is out, `place` shown as given. placeOf: kittenPlaceOf(mode, expanded). places: KITTEN_PLACES, unit D = the parent\'s head width and H = the pill\'s height; the numbers are the mockup\'s divided by its parent\'s size and are 12-digit rounded.',
    limits: { max: core.KITTEN_MAX, leaveMs: core.KITTEN_LEAVE_MS, sleepAfterMs: core.SLEEP_AFTER_MS },
    states: core.KITTEN_STATES,
    places: core.KITTEN_PLACES,
    scripts,
    order: orderLists.map(([name, list]) => ({ name, list, out: core.kittenOrder(list).map(k => k.id) })),
    views: views.map(([now, name]) => ({ name, list: viewList, now, out: core.kittenView(viewList, now).map(k => k.id) })),
    cleans: [['a list that is not clean', scripts[scripts.length - 1].from], ['nothing', null], ['a repeated id: the first wins', [K('a'), K('a', 'approval', 5)]], ['a leaving kitten with no time', [K('l', 'leaving', 0, 0, { until: 'x' })]], ['a long type is cut', [K('t', 'working', 0, 0, { type: 'y'.repeat(100) })]]].map(([name, raw]) => ({ name, raw, out: core.cleanKittens(raw) })),
    slots: slotRows.map(([name, place, kittens]) => ({ name, place, kittens, out: core.kittenSlots(place, kittens) })),
    placeOf: [].concat(...['one', 'perAgent', 'two', 'bogus'].map(mode => [true, false].map(expanded => ({ mode, expanded, out: core.kittenPlaceOf(mode, expanded) })))),
  };
};

// ── Small coloured eyes (B-0): the geometry of the compact detail level's resting eyes ──
// A row is {shape, o, out}: smallEye(shape, o) is out, null for a shape that stays ink. `o` is written as given, so a missing key is the default.
// R is the head radius in px: 5, 7, 9, 11 and 14 are the heads Ø12 to Ø28 of a Ø = 2 R x 1.12 cat (Ø11 session cats and the Ø12 grid cats are the smallest).
// The hostile rows are the ones JSON can hold (null, text, negative and out-of-range numbers); NaN and Infinity cannot be written, the self-checks cover them.
FILES['small-eye-cases.json'] = () => {
  const S = core.SMALL_EYE_SHAPES, kit = [false, true];
  const row = (shape, o) => ({ shape, o, out: core.smallEye(shape, o) });
  const sizes = [], squints = [], gazes = [], scales = [], others = [], hostile = [], brights = [];
  for (const shape of S) for (const kitten of kit) for (const R of [3, 5, 7, 9, 11, 14, 22]) sizes.push(row(shape, { sd: kitten ? 1 : -1, R, kitten }));
  for (const shape of S) for (const kitten of kit) for (const open of [1, .8, .6, .42, .3, .22, .2, .1, 0]) squints.push(row(shape, { sd: -1, R: 9, open, kitten }));
  for (const shape of S) for (const kitten of kit) for (const [yaw, pitch] of [[0, 0], [.62, 0], [-.62, 0], [0, .5], [0, -.5], [.62, .5], [-.62, -.5], [.31, .25], [2, -2]]) gazes.push(row(shape, { sd: 1, R: 9, yaw, pitch, kitten }));
  for (const shape of S) for (const es of [0, .5, 1, 1.25, 1.5]) scales.push(row(shape, { sd: -1, R: 9, es }));
  for (const sd of [-1, 1]) for (const shape of ['wink', ...S]) others.push(row(shape, { sd, R: 9 }));
  for (const shape of ['line', 'flat', 'happy', 'closed', 'spiral', 'heart', 'star', 'bogus', '', 'PILL']) others.push(row(shape, { sd: -1, R: 9 }));
  for (const o of [{}, { R: null }, { R: 'x' }, { R: -3 }, { R: 1e9 }, { R: 9, es: -1 }, { R: 9, es: 99 }, { R: 9, open: 'x' }, { R: 9, open: -1 }, { R: 9, open: 7 }, { R: 9, yaw: 'x', pitch: null }, { R: 9, yaw: 99, pitch: -99 }, { R: 9, kitten: 'yes' }, { R: 9, kitten: 1 }, { R: 9, sd: 0 }, { R: 9, sd: '1' }]) hostile.push(row('pill', o));
  hostile.push({ shape: 'pill', o: null, out: core.smallEye('pill', null) }, { shape: 'pill', o: 7, out: core.smallEye('pill', 7) }, { shape: null, o: { R: 9 }, out: core.smallEye(null, { R: 9 }) });
  // bright coats: a bright coat, a normal coat, a bright kitten, a bright coat closed, and cat values that are not a bright coat
  brights.push(row('pill', { sd: -1, R: 9, cat: 'midnight' }), row('pill', { sd: -1, R: 9, cat: 'momo' }), row('pill', { sd: 1, R: 9, cat: 'oreo', kitten: true }), row('pill', { sd: -1, R: 9, cat: 'mocha', open: 0 }), row('dot', { sd: -1, R: 9, cat: 'mocha' }), row('pill', { sd: -1, R: 9, cat: ['midnight'] }));
  return {
    version: 1,
    note: 'brights: the same, for the black coats in bright. sizes, squints, gazes, scales, others, hostile: smallEye(shape, o) is out. uses: usesSmallEye(shape, sd). The geometry is in px of the eye\'s own frame (centre at the origin, y down). Colours are the renderer\'s: see docs/CAT-CONTRACT.md "Small coloured eyes".',
    constants: core.SMALL_EYE,
    shapes: S,
    bright: core.SMALL_EYE.bright,
    uses: [...S, 'wink', 'line', 'flat', 'happy', 'closed', 'spiral', 'heart', 'star', 'bogus'].flatMap(shape => [-1, 1].map(sd => ({ shape, sd, out: core.usesSmallEye(shape, sd) }))),
    sizes, squints, gazes, scales, others, hostile, brights,
  };
};

// ── The desktop cat (H-0): the trip, the frame rate, the spots, the settings and the kittens ──────────
// One fixture file for all of it; each task of the plan adds its keys to `out` above the marker below. Every event, spot and screen is JSON (so no undefined, NaN
// or Infinity: a port adds its own tests for a number that is not a number). `out` of a row is what the core function returns.
FILES['desktop-cases.json'] = () => {
  const out = {
    version: 1,
    note: 'The desktop cat (sub-project H). A spot is the cat\'s head centre in points, y down, the origin at the top left of the main screen. phases: the seven phases and what each means. steps: desktopStep(state, event) is out, for every phase and event and for input that is not a phase or an event. trips: desktopStep over a script of events, out is the state and act after each. flights: desktopFlightAt(from, to, t) is out.',
  };
  const SPOT = { x: 640, y: 300 }, evOf = type => (type === 'dragOut' || type === 'move' ? { type, spot: SPOT } : { type });

  // The trip.
  out.phaseIds = core.DESKTOP_PHASES;
  out.phases = core.DESKTOP_PHASE_INFO;
  out.events = core.DESKTOP_EVENTS;
  out.acts = core.DESKTOP_ACTS;
  out.flightMs = core.DESKTOP_FLIGHT_MS;
  out.arc = core.DESKTOP_ARC;
  out.steps = [
    ...core.DESKTOP_PHASES.flatMap(state => core.DESKTOP_EVENTS.map(type => ({ state, event: evOf(type), out: core.desktopStep(state, evOf(type)) }))),
    ...[
      ['home', { type: 'dragOut' }], ['home', { type: 'dragOut', spot: { x: 1 } }], ['home', { type: 'dragOut', spot: { x: '1', y: 2 } }], ['home', { type: 'dragOut', spot: [1, 2] }],
      ['home', { type: 'dragOut', spot: { x: 1e6, y: 2 } }], ['onDesktop', { type: 'move' }], ['onDesktop', { type: 'move', spot: null }], ['onDesktop', { type: 'move', spot: { x: 5, y: 6 } }],
      ['onDesktop', null], ['onDesktop', 'toggle'], ['onDesktop', 7], ['onDesktop', []], ['onDesktop', {}], ['onDesktop', { type: 7 }], ['onDesktop', { type: ['toggle'] }], ['onDesktop', { type: 'Toggle' }],
      ['onDesktop', { type: 'toggle ' }], ['onDesktop', { type: '__proto__' }], ['onDesktop', { type: 'constructor' }],
      [null, { type: 'toggle' }], [7, { type: 'toggle' }], ['', { type: 'toggle' }], ['Home', { type: 'toggle' }], ['flying', { type: 'toggle' }], [['home'], { type: 'toggle' }], ['__proto__', { type: 'toggle' }],
    ].map(([state, event]) => ({ state, event, out: core.desktopStep(state, event) })),
  ];
  const trip = (name, from, events) => ({ name, from, events, out: events.reduce((acc, e) => [...acc, core.desktopStep(acc.length ? acc.at(-1).state : from, e)], []) });
  out.trips = [
    trip('the whole trip: out, an alert to the notch and back, home', 'home', ['toggle', 'flightDone', 'alertOn', 'flightDone', 'alertOff', 'flightDone', 'sendHome', 'flightDone'].map(evOf)),
    trip('dropped on the desktop, moved, the screens change, then home', 'home', [evOf('dragOut'), evOf('move'), evOf('screensChanged'), { type: 'move', spot: { x: 'a', y: 1 } }, evOf('toggle'), evOf('flightDone')]),
    trip('an alert that clears mid-flight turns the cat around', 'onDesktop', ['alertOn', 'alertOff', 'flightDone'].map(evOf)),
    trip('a second alert while the cat flies back out turns it around again', 'atNotchForAlert', ['alertOff', 'alertOn', 'flightDone', 'alertOff', 'flightDone'].map(evOf)),
    trip('sendHome during an alert, in the notch', 'onDesktop', ['alertOn', 'flightDone', 'sendHome', 'alertOff', 'alertOn'].map(evOf)),
    trip('sendHome during an alert, in flight: it ends the trip at home', 'onDesktop', ['alertOn', 'sendHome', 'alertOff', 'alertOn', 'flightDone'].map(evOf)),
    trip('sendHome while the cat flies back out after an alert', 'atNotchForAlert', ['alertOff', 'sendHome', 'flightDone'].map(evOf)),
    trip('an alert at home does not take the cat out', 'home', ['alertOn', 'alertOff', 'toggle', 'alertOn', 'flightDone'].map(evOf)),
    trip('the user changes their mind in flight', 'home', ['toggle', 'toggle', 'toggle', 'flightDone'].map(evOf)),
    trip('a cat that was out flies out after the greeting', 'home', ['launch', 'flightDone', 'launch'].map(evOf)),
    trip('events that make no sense in a resting phase', 'onDesktop', ['dragOut', 'flightDone', 'launch', 'alertOff'].map(evOf)),
  ];
  // desktopFlightAt over six flights and the t that matter: the ends, the middle, either side of the middle, and out of range. `desktopFlightAt(from, to, t)`.
  const NOTCH = { x: 480, y: 16 }, SPOTS = { downRight: { x: 576, y: 180 }, down: { x: 480, y: 300 }, left: { x: 120, y: 200 }, far: { x: 800, y: 560 } };
  const flightRows = [
    ['down and right: the default spot', NOTCH, SPOTS.downRight], ['up and left: back to the notch', SPOTS.downRight, NOTCH], ['straight down', NOTCH, SPOTS.down], ['straight up', SPOTS.down, NOTCH],
    ['down and left', NOTCH, SPOTS.left], ['straight across', { x: 100, y: 200 }, { x: 700, y: 200 }], ['a short hop', { x: 100, y: 100 }, { x: 110, y: 105 }],
    ['no distance', { x: 50, y: 60 }, { x: 50, y: 60 }], ['a long flight: the lift stops at 90', { x: 0, y: 0 }, SPOTS.far],
  ];
  out.flights = [
    ...flightRows.flatMap(([name, from, to]) => [-.5, 0, .1, .25, .5, .75, .9, 1, 1.5].map(t => ({ name, from, to, t, out: core.desktopFlightAt(from, to, t) }))),
    ...[
      ['a start that is not a point', null, SPOTS.downRight, .5], ['an end that is not a point', NOTCH, 'there', .5], ['a start with a missing y', { x: 5 }, SPOTS.downRight, 0], ['an end beyond the limit', NOTCH, { x: 1e6, y: 0 }, 1],
      ['t is a string', NOTCH, SPOTS.downRight, '0.5'], ['t is null', NOTCH, SPOTS.downRight, null], ['t is a huge number', NOTCH, SPOTS.downRight, 1e300], ['t is a huge negative number', NOTCH, SPOTS.downRight, -1e300],
    ].map(([name, from, to, t]) => ({ name, from, to, t, out: core.desktopFlightAt(from, to, t) })),
  ];

  out.note += ' sizeCases: desktopSizeOf(raw) is out. fpsCases: desktopFps(input) is out. kittenSlots: desktopKittenSlots(kittens, side) is out (a missing side is not given). kittenSizes: the same layout in points at each size, side 1.';
  // Sizes: desktopSizeOf(raw) is out.
  out.sizes = core.DESKTOP_SIZES;
  out.sizeIds = core.DESKTOP_SIZE_IDS;
  out.defaultSize = core.DEFAULT_DESKTOP_SIZE;
  out.sizeCases = ['small', 'medium', 'large', 'Small', 'LARGE', ' large', 'large ', 'huge', '', '48', 48, null, true, ['small'], {}, '__proto__', 'constructor'].map(raw => ({ raw, out: core.desktopSizeOf(raw) }));

  // The frame rate: desktopFps(input) is out. `fps` holds the five rates and `near` the distance, in points, that counts as near.
  out.fps = core.DESKTOP_FPS;
  out.near = core.DESKTOP_NEAR;
  const F = (name, input) => ({ name, input, out: core.desktopFps(input) });
  const on = (o = {}) => ({ phase: 'onDesktop', ...o });
  out.fpsCases = [
    ...core.DESKTOP_PHASES.map(p => F(`${p}, nothing going on`, { phase: p })),
    F('dragging', on({ dragging: true })), F('an emote', on({ emote: true })), F('a kitten arriving or leaving', on({ kittenMotion: true })), F('the dance', on({ dance: true })),
    F('an agent working', on({ working: true })), F('the cursor on the cat', on({ cursorDist: 0 })), F('the cursor 149.9 points away', on({ cursorDist: 149.9 })), F('the cursor exactly 150 points away', on({ cursorDist: 150 })),
    F('the cursor 150.01 points away', on({ cursorDist: 150.01 })), F('the cursor far away', on({ cursorDist: 900 })), F('the cursor unknown, as on Wayland', on({ cursorDist: null })),
    F('idle and awake', on()), F('asleep', on({ asleep: true })), F('asleep with the cursor near', on({ asleep: true, cursorDist: 10 })), F('asleep and the agent working', on({ asleep: true, working: true })),
    F('hidden: the screen is asleep, locked or covered', on({ hidden: true })), F('hidden while dragging', on({ hidden: true, dragging: true })), F('hidden in flight', { phase: 'flyingOut', hidden: true }),
    F('motion beats sleep and work', on({ dragging: true, asleep: true, working: true })), F('a flight beats sleep', { phase: 'retracting', asleep: true }),
    F('home with everything going on', { phase: 'home', dragging: true, emote: true, kittenMotion: true, dance: true, working: true, cursorDist: 0 }),
    F('in the notch for an alert, with everything going on', { phase: 'atNotchForAlert', dragging: true, emote: true, dance: true, working: true, cursorDist: 0 }),
    F('the strings "true" and the number 1 are not true', on({ dragging: 'true', emote: 1, working: 'yes', asleep: 1, hidden: 'true' })),
    F('a cursor distance that is a string', on({ cursorDist: '10' })),
    F('no input', null), F('a number', 7), F('text', 'onDesktop'), F('an array', ['onDesktop']), F('an empty object', {}), F('a phase that is not a phase', { phase: 'flying' }), F('a phase in the wrong case', { phase: 'Home' }),
    F('a prototype name as the phase', { phase: '__proto__' }),
  ];

  // The desktop kittens: desktopKittenSlots(kittens, side) is out. `kittens` is [{id, state}], what kittenView returns (the other fields do not matter). `kittenSizes` is the same
  // layout in points at each size (every number is a multiple of the head width), side 1.
  out.kittenPlace = core.DESKTOP_KITTEN_PLACE;
  const kit = (n, states = ['approval', 'searching', 'working']) => Array.from({ length: n }, (_, i) => ({ id: 'k' + i, state: states[i] || 'working' }));
  out.kittenSlots = [
    ...[0, 1, 2, 3, 4, 8].flatMap(n => [1, -1].map(side => ({ name: `${n} kittens, side ${side}`, kittens: kit(n), side, out: core.desktopKittenSlots(kit(n), side) }))),
    ...[
      ['no side given: the right', kit(3), undefined], ['side 0 is the right', kit(2), 0], ['side 2 is the right', kit(2), 2], ['side "-1" as text is the right', kit(2), '-1'], ['side null is the right', kit(2), null],
      ['things that are not kittens are skipped', [null, 7, 'k', { id: '' }, { id: 5 }, { state: 'working' }, [], { id: 'ok', state: 7 }, { id: 'a', state: 'leaving' }], 1],
      ['not a list', 'k0', 1], ['null', null, 1], ['an object', { length: 2 }, 1],
    ].map(([name, kittens, side]) => ({ name, kittens, ...(side === undefined ? {} : { side }), out: core.desktopKittenSlots(kittens, side) })),
  ];
  out.kittenSizes = Object.entries(core.DESKTOP_SIZES).flatMap(([size, d]) => [0, 1, 3, 8].map(count => {
    const s = core.desktopKittenSlots(kit(count));
    return { size, d, count, shown: s.shown.map(q => ({ id: q.id, state: q.state, x: q.x * d, y: q.y * d, d: q.d * d })), more: s.more, moreAt: s.moreAt && { x: s.moreAt.x * d, y: s.moreAt.y * d, size: s.moreAt.size * d } };
  }));

  out.note += ' screenKeys: screenKey(screens) is out. isScreenKey: isScreenKey(key) is out. clamps: clampSpot(spot, screens, size). defaultSpots: defaultDesktopSpot(screens, size). spotFor: spotFor(spots, screens, size). remembers: rememberSpot(spots, screens, spot, size). spotMaps: cleanDesktopSpots(raw). A screen is {frame, visible, main}; a missing size is not given.';
  // Spots on the screens. A screen is {frame, visible, main}: the frame is the whole screen, `visible` what the menu bar and the Dock leave, `main` marks the screen with the menu bar;
  // points, y down, the origin at the top left of the main screen. size is a size ID. `margin` is the room between the head and the visible frame's edge (the centre is margin + d/2 away).
  out.margin = core.DESKTOP_MARGIN;
  out.defaultSpot = core.DESKTOP_DEFAULT;
  out.maxSpots = core.MAX_DESKTOP_SPOTS;
  const LAPTOP = { frame: { x: 0, y: 0, w: 1512, h: 982 }, visible: { x: 0, y: 37, w: 1512, h: 875 }, main: true };
  const MONITOR = { frame: { x: 1512, y: -100, w: 2560, h: 1440 }, visible: { x: 1512, y: -100, w: 2560, h: 1415 } };
  const LEFT = { frame: { x: -1920, y: 0, w: 1920, h: 1080 }, visible: { x: -1920, y: 0, w: 1920, h: 1080 } };
  const WIN = { frame: { x: 0, y: 0, w: 1920, h: 1080 }, visible: { x: 0, y: 0, w: 1920, h: 1040 }, main: true };
  const GAP = { frame: { x: 1700, y: 0, w: 800, h: 600 } };
  out.screenKeys = [
    ['a laptop', [LAPTOP]], ['a laptop and a monitor to its right', [LAPTOP, MONITOR]], ['the same, the other way round', [MONITOR, LAPTOP]], ['a monitor on each side', [LEFT, LAPTOP, MONITOR]],
    ['the same, in another order', [MONITOR, LEFT, LAPTOP]], ['and another', [LAPTOP, MONITOR, LEFT]], ['a Windows desktop with a taskbar', [WIN]],
    ['the Dock moved: the same key', [{ ...LAPTOP, visible: { x: 80, y: 25, w: 1432, h: 957 }, main: false }]], ['no visible frame: the same key', [{ frame: LAPTOP.frame }]],
    ['fractions round half up', [{ frame: { x: -.5, y: 2.5, w: 100.5, h: 100.4 } }]], ['sorted after the rounding, not before', [{ frame: { x: .3, y: 9, w: 100, h: 100 } }, { frame: { x: .4, y: 5, w: 100, h: 100 } }]],
    ['mirrored screens are two frames', [LAPTOP, LAPTOP]], ['screens that are not screens are left out', [null, LAPTOP, 7, { frame: 1 }, { frame: { x: 0, y: 0, w: 0, h: 5 } }, { frame: { x: 0, y: 0, w: .4, h: 5 } }, { frame: { x: '0', y: 0, w: 5, h: 5 } }]],
    ['nothing', []], ['null', null], ['not a list', 'screens'], ['an object', {}], ['a frame beyond the limit', [{ frame: { x: 2e6, y: 0, w: 100, h: 100 } }]],
    ['40 screens: the first 16 by frame', Array.from({ length: 40 }, (_, i) => ({ frame: { x: i * 100, y: 0, w: 100, h: 100 } }))],
  ].map(([name, screens]) => ({ name, screens, out: core.screenKey(screens) }));
  out.isScreenKey = [
    '0,0,1512,982', '0,0,1512,982|1512,-100,2560,1440', '-1920,0,1920,1080|0,0,1512,982|1512,-100,2560,1440', '', '0,0,1512', '0,0,1512,982,1', '0,0,1512,982|', '|0,0,1512,982', '0,0,1512,982\n', ' 0,0,1512,982', '0,0,1512,982 ',
    '00,0,1512,982', '-0,0,1512,982', '0,0,0,982', '0,0,1512,0', '0,0,-1512,982', '1512,0,10,10|0,0,10,10', ['0,0,10,10', '0,0,10,10'].join('|'), Array(17).fill('0,0,10,10').join('|'), Array(16).fill('0,0,10,10').join('|'),
    '0,0,10000000,10', '1.5,0,10,10', '0x1,0,10,10', '__proto__', 'constructor', 'prototype', null, 7, [], {},
  ].map(key => ({ key, out: core.isScreenKey(key) }));
  const C = (name, spot, screens, size) => ({ name, spot, screens, ...(size === undefined ? {} : { size }), out: core.clampSpot(spot, screens, size) });
  out.clamps = [
    ...core.DESKTOP_SIZE_IDS.flatMap(size => [
      C(`${size}: a spot that is fine stays`, { x: 700, y: 400 }, [LAPTOP], size), C(`${size}: on the left edge`, { x: 0, y: 400 }, [LAPTOP], size), C(`${size}: on the right edge`, { x: 1511, y: 400 }, [LAPTOP], size),
      C(`${size}: in the menu bar`, { x: 700, y: 5 }, [LAPTOP], size), C(`${size}: at the menu bar's lower edge`, { x: 700, y: 37 }, [LAPTOP], size), C(`${size}: in the Dock`, { x: 700, y: 970 }, [LAPTOP], size),
      C(`${size}: the top left corner`, { x: 0, y: 0 }, [LAPTOP], size), C(`${size}: the bottom right corner`, { x: 1511, y: 981 }, [LAPTOP], size),
    ]),
    C('no size is medium', { x: 5, y: 5 }, [LAPTOP], undefined), C('a size that is not a size is medium', { x: 5, y: 5 }, [LAPTOP], 'huge'),
    C('a Windows taskbar', { x: 960, y: 1070 }, [WIN], 'large'),
    C('a Dock on the left', { x: 20, y: 400 }, [{ frame: { x: 0, y: 0, w: 1440, h: 900 }, visible: { x: 80, y: 25, w: 1360, h: 875 }, main: true }], 'medium'),
    C('a visible frame smaller than the cat and its margins holds the centre', { x: 90, y: 5 }, [{ frame: { x: 0, y: 0, w: 100, h: 90 }, visible: { x: 0, y: 10, w: 100, h: 80 }, main: true }], 'medium'),
    C('the small size fits across 100 points but not down 80', { x: 90, y: 5 }, [{ frame: { x: 0, y: 0, w: 100, h: 90 }, visible: { x: 0, y: 10, w: 100, h: 80 }, main: true }], 'small'),
    C('no visible frame: the frame', { x: 0, y: 0 }, [{ frame: { x: 0, y: 0, w: 800, h: 600 } }], 'small'),
    C('a visible frame outside the frame is the frame', { x: 0, y: 0 }, [{ frame: { x: 0, y: 0, w: 800, h: 600 }, visible: { x: 900, y: 900, w: 50, h: 50 } }], 'small'),
    C('a visible frame that sticks out is held inside the frame', { x: 799, y: 599 }, [{ frame: { x: 0, y: 0, w: 800, h: 600 }, visible: { x: -100, y: -100, w: 2000, h: 2000 } }], 'small'),
    C('two screens: near the top of the monitor, which starts higher', { x: 1600, y: -90 }, [LAPTOP, MONITOR], 'medium'), C('two screens: the same spot lower down', { x: 1600, y: 10 }, [LAPTOP, MONITOR], 'medium'),
    C('two screens: the last point of the laptop', { x: 1511.5, y: 400 }, [LAPTOP, MONITOR], 'medium'), C('two screens: the first point of the monitor', { x: 1512, y: 400 }, [LAPTOP, MONITOR], 'medium'),
    C('two screens: the monitor\'s bottom edge', { x: 1600, y: 1300 }, [LAPTOP, MONITOR], 'medium'),
    C('a screen to the left, at negative coordinates', { x: -1000, y: 500 }, [LEFT, LAPTOP], 'medium'), C('a screen to the left, in its corner', { x: -1900, y: 20 }, [LEFT, LAPTOP], 'small'),
    C('the monitor is unplugged: the spot is on no screen', { x: 3000, y: 500 }, [LAPTOP], 'medium'), C('left of the only screen', { x: -10, y: 500 }, [LAPTOP], 'medium'), C('far below the only screen', { x: 700, y: 5000 }, [LAPTOP], 'medium'),
    C('a gap between two screens', { x: 1600, y: 300 }, [LAPTOP, GAP], 'medium'),
    ...[['null', null], ['text', 'x'], ['a number', 7], ['an array', [1, 2]], ['an empty object', {}], ['no y', { x: 1 }], ['text coordinates', { x: '1', y: 2 }], ['beyond the limit', { x: 1e6, y: 0 }]].map(([n, spot]) => C(`a spot that is ${n}`, spot, [LAPTOP], 'large')),
    C('no screens', { x: 5, y: 5 }, [], 'medium'), C('screens that are not screens', { x: 5, y: 5 }, [null, {}, { frame: 7 }], 'medium'),
  ];
  out.defaultSpots = [
    ...core.DESKTOP_SIZE_IDS.map(size => ({ name: `a laptop, ${size}`, screens: [LAPTOP], size })), { name: 'a Windows desktop', screens: [WIN], size: 'medium' },
    { name: 'the screen marked main wins', screens: [{ ...LAPTOP, main: false }, { ...MONITOR, main: true }], size: 'medium' }, { name: 'none marked main: the one at the origin', screens: [MONITOR, { ...LAPTOP, main: false }], size: 'medium' },
    { name: 'none marked and none at the origin: the first by frame', screens: [MONITOR, LEFT], size: 'small' }, { name: 'no screens', screens: [], size: 'medium' },
  ].map(c => ({ ...c, out: core.defaultDesktopSpot(c.screens, c.size) }));
  const K1 = core.screenKey([LAPTOP]), K2 = core.screenKey([LAPTOP, MONITOR]);
  const S = (name, spots, screens, size) => ({ name, spots, screens, size, out: core.spotFor(spots, screens, size) });
  const REMEMBERED = { [K1]: { x: 300, y: 400 }, [K2]: { x: 2000, y: 800 } };
  out.spotFor = [
    S('a laptop alone has its own spot', REMEMBERED, [LAPTOP], 'medium'), S('with the monitor it has another, whichever order the screens come in', REMEMBERED, [MONITOR, LAPTOP], 'medium'),
    S('nothing remembered: the default spot', {}, [LAPTOP], 'medium'), S('an arrangement never seen', REMEMBERED, [LEFT, LAPTOP], 'medium'),
    S('a remembered spot the menu bar now covers is held inside', { [K1]: { x: 5, y: 5 } }, [LAPTOP], 'large'), S('a remembered spot on no screen is the default', { [K1]: { x: 5000, y: 5 } }, [LAPTOP], 'medium'),
    S('the Mac\'s JSON text', JSON.stringify(REMEMBERED), [LAPTOP], 'medium'), S('text that is not JSON', '{"a":', [LAPTOP], 'medium'), S('null', null, [LAPTOP], 'medium'),
    S('a spot that is not a spot', { [K1]: 'x' }, [LAPTOP], 'medium'), S('a prototype name as a key', { constructor: 1 }, [LAPTOP], 'medium'), S('no screens', REMEMBERED, [], 'medium'), S('not a list of screens', REMEMBERED, 'screens', 'medium'),
  ];
  const R = (name, spots, screens, spot, size) => ({ name, spots, screens, spot, size, out: core.rememberSpot(spots, screens, spot, size) });
  const FULL = Object.fromEntries(Array.from({ length: 32 }, (_, i) => [`${i},0,100,100`, { x: i, y: 1 }]));
  out.remembers = [
    R('into nothing, clamped', {}, [LAPTOP], { x: 5, y: 5 }, 'medium'), R('beside another arrangement', { [K1]: { x: 300, y: 400 } }, [LAPTOP, MONITOR], { x: 2000, y: 800 }, 'medium'),
    R('over the same arrangement', REMEMBERED, [LAPTOP], { x: 600, y: 600 }, 'medium'), R('a spot on no screen is remembered as the default', { [K1]: { x: 1, y: 1 } }, [LAPTOP], { x: 9000, y: 9000 }, 'medium'),
    R('no screens: nothing changes', REMEMBERED, [], { x: 5, y: 5 }, 'medium'), R('a full map makes room for the new arrangement', FULL, [LAPTOP], { x: 600, y: 600 }, 'medium'),
    R('a full map that already has the arrangement', { ...FULL, [K1]: { x: 1, y: 1 } }, [LAPTOP], { x: 700, y: 700 }, 'small'), R('JSON text in', JSON.stringify({ [K1]: { x: 300, y: 400 } }), [LAPTOP, MONITOR], { x: 2000, y: 800 }, 'large'),
  ];
  out.spotMaps = [
    ['a map', REMEMBERED], ['an empty map', {}], ['the Mac\'s JSON text', JSON.stringify(REMEMBERED)], ['only x and y are kept', { [K1]: { x: 1, y: 2, z: 3, name: 'x' } }],
    ['keys that are not screen keys', { '': { x: 1, y: 1 }, '0,0,0,0': { x: 1, y: 1 }, '00,0,100,100': { x: 1, y: 1 }, '0,0,100,100\n': { x: 1, y: 1 }, '1,0,100,100|0,0,100,100': { x: 1, y: 1 }, constructor: { x: 1, y: 1 }, prototype: { x: 1, y: 1 }, [K1]: { x: 5, y: 5 } }],
    ['values that are not spots', { '0,0,100,100': null, '1,0,100,100': 7, '2,0,100,100': 'x', '3,0,100,100': [1, 2], '4,0,100,100': {}, '5,0,100,100': { x: 1 }, '6,0,100,100': { x: '1', y: 2 }, '7,0,100,100': { x: 1, y: 1e6 }, '8,0,100,100': { x: 1, y: 2 } }],
    ['out of order comes back in order', { [K2]: { x: 2000, y: 300 }, [K1]: { x: 700, y: 400 } }], ['JSON text cut off', '{"0,0,100,100":'], ['JSON text with single quotes', "{'0,0,100,100':{'x':1,'y':2}}"], ['JSON text that is an array', '[]'],
    ['JSON text that is null', 'null'], ['text that is not JSON', 'junk'], ['null', null], ['a number', 7], ['true', true], ['an array', [{ x: 1, y: 2 }]],
    ['32 arrangements fit', FULL], ['33 keep the first 32 by code-point order', { ...FULL, '99,0,100,100': { x: 1, y: 1 }, '5,5,100,100': { x: 1, y: 1 } }],
    ['bad values drop before the 32 cap counts', Object.fromEntries(Array.from({ length: 40 }, (_, i) => [`${i},0,100,100`, i < 8 ? { x: 'bad', y: 1 } : { x: i, y: 1 }]))],
  ].map(([name, raw]) => ({ name, raw, out: core.cleanDesktopSpots(raw) }));

  out.note += ' settingsCases: cleanDesktopSettings(raw) is out.';
  // The stored settings: cleanDesktopSettings(raw) is out. A raw `spots` may be an object or the JSON text of one (the Mac stores text). The block with 300 spots is built here and written out in full.
  out.settingsDefaults = core.defaultDesktopSettings();
  const MANY = Object.fromEntries(Array.from({ length: 300 }, (_, i) => [`${i},0,100,100`, { x: i, y: i % 90 }]));
  out.settingsCases = [
    ['nothing stored', null], ['an empty object', {}], ['text instead of an object', 'junk'], ['a number', 7], ['an array', [1, 2, 3]], ['true', true],
    ['a fully valid value', { on: true, size: 'large', spots: { [K2]: { x: 2000, y: 800 }, [K1]: { x: 300, y: 400 } } }],
    ['the cat is out', { on: true }], ['the cat is home', { on: false, size: 'small' }], ['on as text', { on: 'true' }], ['on as the number 1', { on: 1 }], ['on as null', { on: null }], ['on in a list', { on: [true] }],
    ['small', { size: 'small' }], ['large', { size: 'large' }], ['a size in the wrong case', { size: 'Large' }], ['a size with a space', { size: 'large ' }], ['a size that is not a size', { size: 'huge' }],
    ['the size as its number', { size: 96 }], ['the size as null', { size: null }], ['a prototype name as the size', { size: '__proto__' }],
    ['the spots as JSON text, as the Mac stores them', { on: true, spots: JSON.stringify({ [K1]: { x: 300, y: 400 } }) }], ['the spots as JSON text, cut off', { spots: '{"0,0,1512,982":{"x":3' }],
    ['the spots as JSON text with single quotes', { spots: "{'0,0,1512,982':{'x':1,'y':2}}" }], ['the spots as JSON text with a trailing comma', { spots: '{"0,0,1512,982":{"x":1,"y":2},}' }],
    ['the spots as JSON text with garbage after it', { spots: '{"0,0,1512,982":{"x":1,"y":2}} x' }], ['the spots as JSON text that is an array', { spots: '[]' }], ['the spots as text that is not JSON', { spots: 'junk' }],
    ['the spots as a number', { spots: 7 }], ['the spots as null', { spots: null }], ['the spots as an array', { spots: [{ x: 1, y: 2 }] }],
    ['a key that is not a screen key', { spots: { nonsense: { x: 1, y: 2 }, '': { x: 1, y: 2 }, [K1]: { x: 5, y: 6 } } }], ['keys with leading zeros, a newline or the wrong order', { spots: { '00,0,100,100': { x: 1, y: 1 }, '0,0,100,100\n': { x: 1, y: 1 }, '1,0,100,100|0,0,100,100': { x: 1, y: 1 } } }],
    ['prototype names as keys', { spots: { constructor: { x: 1, y: 1 }, prototype: { x: 1, y: 1 }, ['__proto__']: { x: 1, y: 1 }, [K1]: { x: 2, y: 2 } } }],
    ['spots that are not spots', { spots: { '0,0,100,100': null, '1,0,100,100': 'x', '2,0,100,100': [1, 2], '3,0,100,100': {}, '4,0,100,100': { x: 1 }, '5,0,100,100': { x: '1', y: 2 }, '6,0,100,100': { x: 1, y: 1e6 }, '7,0,100,100': { x: 1, y: 2 } } }],
    ['a spot with more fields keeps x and y', { spots: { [K1]: { x: 1, y: 2, z: 3, name: 'cat' } } }], ['spots out of order come back in order', { spots: { [K2]: { x: 5, y: 6 }, [K1]: { x: 7, y: 8 } } }],
    ['negative coordinates are fine', { spots: { '-1920,0,1920,1080|0,0,1512,982': { x: -1000, y: 500 } } }],
    ['three hundred arrangements keep the first 32', { on: true, spots: MANY }], ['three hundred as JSON text', { spots: JSON.stringify(MANY) }],
    ['the Cat and Display settings are not desktop settings', { character: 'momo', motionStyle: 'classic', collar: 'band', furLines: true, displayMode: 'two', pair: ['momo', 'ginger'], agentCats: { agent_x: 'momo' }, cats: {} }],
  ].map(([name, raw]) => ({ name, raw, out: core.cleanDesktopSettings(raw) }));

  // The file catch (fixes after H): a file on its way into the island is an alert to the desktop cat (alertOn and alertOff to the machine above, so no new phase, event or act). New keys and
  // new trip rows only, so the fixture stays additive and `note` is not touched; `catchNote` says what they are. alertCases: desktopAlert(input) is out. catchReady: desktopCatchReady(phase) is out.
  out.catchNote = 'The file catch. A file on its way into the island (dragged over it, waiting for the cat, or its drop flow on screen) is an alert to the desktop cat: alertOn and alertOff to desktopStep, so there is no new phase, event or act. alertCases: desktopAlert(input) is out (a flag counts only when it is exactly true). catchReady: desktopCatchReady(phase) is out (the cat is at the notch). catchWaitMs: how long a dropped file waits for the cat, in ms. The trips named "a file catch" are desktopStep over the events the file catch sends.';
  out.catchWaitMs = core.DESKTOP_CATCH_WAIT_MS;
  out.alertCases = [
    ['nothing', {}], ['an approval', { approval: true }], ['a question', { question: true }], ['the chat\'s approval card', { chatApproval: true }], ['a file on its way in', { fileCatch: true }],
    ['a file and an approval', { fileCatch: true, approval: true }], ['a pill in the approval state', { pillStates: ['working', 'approval'] }], ['a pill that asks a question', { pillStates: ['question'] }],
    ['an error, a rate limit and a dizzy cat are not alerts', { pillStates: ['error', 'ratelimit', 'dizzy', 'idle', 'working', 'finished'] }],
    ['every flag false', { approval: false, question: false, chatApproval: false, fileCatch: false, pillStates: [] }],
    ['a flag as text', { fileCatch: 'true', approval: 'true' }], ['a flag as the number 1', { fileCatch: 1, question: 1 }], ['a flag as null', { fileCatch: null }], ['a flag in a list', { fileCatch: [true] }],
    ['pill states that are not a list', { pillStates: 'approval' }], ['pill states with junk in them', { pillStates: [7, null, {}, ['approval'], 'error'] }], ['a state in the wrong case', { pillStates: ['Approval'] }],
    ['keys that are not flags', { file: true, drop: true, catch: true }], ['null', null], ['text', 'approval'], ['a number', 1], ['true', true], ['a list', [true]],
  ].map(([name, input]) => ({ name, input, out: core.desktopAlert(input) }));
  out.catchReady = [...core.DESKTOP_PHASES, null, 7, '', 'Home', 'flying', '__proto__', ['home'], {}].map(phase => ({ phase, out: core.desktopCatchReady(phase) }));
  out.trips.push(
    trip('a file catch: the cat flies in, the catch plays, the cat flies back', 'onDesktop', ['alertOn', 'flightDone', 'alertOff', 'flightDone'].map(evOf)),
    trip('a file catch: the drop view folds before the cat has landed, and the cat turns round mid-flight', 'onDesktop', ['alertOn', 'alertOff', 'flightDone'].map(evOf)),
    trip('a file catch: the file arrives while the cat is still flying out, and the cat turns round', 'home', ['toggle', 'alertOn', 'flightDone', 'alertOff', 'flightDone'].map(evOf)),
    trip('a file catch: with the cat at home it changes nothing', 'home', ['alertOn', 'alertOff', 'alertOn'].map(evOf)),
  );
  // The incoming transfer offer (G2-0): a card from another machine waits for a click, which is an alert like an approval, so to desktopStep it is alertOn and alertOff again (no new phase, event or act).
  // New keys and new trip rows only: `alertCases`, `note` and `catchNote` stay exactly as they were, so the apps that replay them today keep passing. offerCases: desktopAlert(input) is out.
  out.offerNote = 'The incoming transfer offer. A card from another machine ("<name> wants to send <file>") waits for a click: an alert to the desktop cat, like an approval, so it is alertOn and alertOff to desktopStep and there is no new phase, event or act. offerCases: desktopAlert(input) is out for inputs that carry transferOffer (a flag counts only when it is exactly true). alertCases is unchanged and holds no transferOffer. The trips named "a transfer offer" are desktopStep over the events an offer sends.';
  out.offerCases = [
    ['an offer', { transferOffer: true }], ['an offer next to false flags', { transferOffer: true, approval: false, question: false, chatApproval: false, fileCatch: false, pillStates: [] }],
    ['an offer and a file on its way in', { transferOffer: true, fileCatch: true }], ['an offer and a pill that is working', { transferOffer: true, pillStates: ['working'] }],
    ['no offer, an approval', { transferOffer: false, approval: true }], ['the flag false', { transferOffer: false }], ['no flags', {}],
    ['a flag as text', { transferOffer: 'true' }], ['a flag as the number 1', { transferOffer: 1 }], ['a flag as null', { transferOffer: null }], ['a flag in a list', { transferOffer: [true] }],
    ['a flag as an object', { transferOffer: {} }], ['keys that are not the flag', { offer: true, transfer: true, transfer_offer: true, TransferOffer: true, transferOffers: true }],
  ].map(([name, input]) => ({ name, input, out: core.desktopAlert(input) }));
  out.trips.push(
    trip('a transfer offer: the cat flies in, the offer is answered, the cat flies back', 'onDesktop', ['alertOn', 'flightDone', 'alertOff', 'flightDone'].map(evOf)),
    trip('a transfer offer: it is answered before the cat has landed, and the cat turns round mid-flight', 'onDesktop', ['alertOn', 'alertOff', 'flightDone'].map(evOf)),
    trip('a transfer offer: with the cat at home it changes nothing', 'home', ['alertOn', 'alertOff'].map(evOf)),
  );
  // @@DESKTOP-SECTIONS: each task adds its keys to `out` immediately above this line.
  return out;
};

FILES['wardrobe-cases.json'] = () => {
  const out = { version: 1, note: 'The wardrobe (sub-project I). The IDs, their order and the action ID wardrobe are frozen contract values: they are stored. Geometry is in head-local px; shapes carry colour roles, which shared/theme.json resolves.' };
  out.ids = core.OUTFIT_IDS; out.names = core.OUTFIT_NAMES; out.groups = core.OUTFIT_GROUPS; out.drawn = core.OUTFIT_DRAWN; out.defaultOutfit = core.DEFAULT_OUTFIT; out.roles = core.OUTFIT_ROLES;
  out.clean = [
    ...core.OUTFIT_IDS.map(id => [`the ID ${id}`, id]),
    ['a capital', 'Auto'], ['all capitals', 'SANTAHAT'], ['padded', ' bow '], ['a trailing newline', 'bow\n'], ['empty', ''], ['null', null], ['a number', 7], ['true', true], ['a list', []], ['a list of an ID', ['bow']], ['an object', {}], ['an object with the key', { outfit: 'bow' }],
    ['a made-up name', 'fancyhat'], ['a made-up key', 'outfitId'], ['an outfit that is not here', 'fancyhat'], ['another', 'hat'], ['a prototype name', '__proto__'], ['another', 'constructor'], ['another', 'toString'], ['a separator', 'party-hat'],
  ].map(([name, input]) => ({ name, input, out: core.outfitIdOf(input) }));
  out.settings = [
    ['null', null], ['text', 'bow'], ['a list', ['bow']], ['an empty object', {}], ['a clean value', { outfit: 'bow' }], ['a capital', { outfit: 'Bow' }], ['a number', { outfit: 7 }], ['null', { outfit: null }],
    ['none', { outfit: 'none', other: 1 }], ['the whole cat block', { character: 'momo', collar: 'tag', outfit: 'crown', desktop: { on: true } }], ['a prototype key', JSON.parse('{"__proto__": {"outfit": "bow"}}')],
  ].map(([name, input]) => ({ name, input, out: core.cleanWardrobeSettings(input) }));
  out.easter = [1583, 1600, 1700, 1818, 1900, 1943, 1961, 2000, 2008, 2016, 2024, 2025, 2026, 2038, 2100, 2285, 9999, 1582, 0, -5, 10000, 2024.5, '2024', null].map(year => ({ year, out: core.easterOf(year) }));
  const D = (y, m, d) => ({ y, m, d, out: core.autoOutfitFor(y, m, d) });
  out.auto = [
    D(2025, 12, 30), D(2025, 12, 31), D(2026, 1, 1), D(2026, 1, 2), D(2026, 1, 3), D(2025, 11, 30), D(2025, 12, 1), D(2025, 12, 26), D(2025, 12, 27), D(2025, 9, 30), D(2025, 10, 1), D(2025, 10, 31), D(2025, 11, 1), D(2025, 11, 2),
    D(2025, 6, 20), D(2025, 6, 21), D(2025, 8, 31), D(2025, 9, 1), D(2025, 3, 15), D(2025, 5, 5), D(2024, 2, 29), D(2024, 7, 4), D(2023, 2, 29), D(2024, 2, 30), D(2024, 13, 1), D(2024, 0, 1), D(2024, 4, 31), D(0, 1, 1), D(10000, 1, 1),
    D(2024.5, 1, 1), D('2024', 1, 1), D(null, 1, 1), D(1500, 12, 25), D(1500, 4, 1),
  ];
  const E = (y, m, d) => new Date(Date.UTC(y, m - 1, d)), iso = t => ({ y: t.getUTCFullYear(), m: t.getUTCMonth() + 1, d: t.getUTCDate() });
  out.easterWindows = [1818, 1943, 1961, 2000, 2008, 2016, 2024, 2025, 2026, 2038, 2100, 2285].map(year => {
    const e = core.easterOf(year); // the dates are walked with the calendar (Date.UTC), not with the contract's own day count
    return { year, easter: e, days: [-3, -2, -1, 0, 1, 2].map(k => { const t = iso(E(year, e.month, e.day + k)); return { k, ...D(t.y, t.m, t.d) }; }) };
  });
  out.resolve = [
    ['auto', 2025, 12, 24], ['auto', 2025, 3, 3], ['none', 2025, 12, 24], ['bow', 2025, 12, 24], ['Bow', 2025, 12, 24], [null, 2025, 12, 24], ['auto', 2024, 3, 29], ['crown', 2024, 99, 1], ['auto', 2024, 99, 1],
  ].map(([id, y, m, d]) => ({ id, y, m, d, out: core.resolveOutfit(id, y, m, d) }));
  out.worn = ['big', 'small', 'kitten', 'Big', ' big', 'BIG', '', null, 28, 20, 64, true, {}, [], 'bigcat', 'desktop'].map(role => ({ role, out: core.outfitWorn(role) }));
  const POSES = { rest: core.newPose(), turned: { ...core.newPose(), yaw: .6, pitch: .15 } }, FOUR = ['momo', 'shrimpy', 'button', 'midnight'], SIZES = [20, 28, 48, 64];
  out.slots = core.OUTFIT_SLOTS; out.order = core.OUTFIT_ORDER; out.min = core.OUTFIT_MIN;
  out.edge = Object.fromEntries(core.CAT_IDS.map(id => [id, core.outfitEdge(core.PRESETS[id])]));
  out.rooms = [[0, 8, 0], [0, 16, 0], [0, 12, 0], [0, 4.27, 0], [0, 0.2, 0], [0, 12, 4], [0, 12, null], [0, 12, 'x'], [0, null, 0]].map(([, headY, ceiling]) => ({ headY, ceiling, top: -8.04, out: core.outfitRoom({ top: { x: 0, y: -8.04 } }, headY, ceiling) }));
  out.anchors = Object.fromEntries(FOUR.flatMap(cat => SIZES.flatMap(D => Object.entries(POSES).map(([pose, s]) => [`${cat}/${D}/${pose}`, core.outfitAnchors(core.PRESETS[cat], s, D, { dpr: 2 })]))));
  /** The options a renderer would pass: the notch's strips give the compact cat its room above the crown (a 32 pt strip for the Ø20 cat, a 24 pt strip for the Ø18 one on a screen without a notch). */
  const STRIP = { 20: 32, 18: 24 }, opts = (p, s, D, extra = {}) => { const o = { dpr: 2, ...extra }; if (STRIP[D]) o.room = core.outfitRoom(core.outfitAnchors(p, s, D, o), STRIP[D] / 2, 0); return o; };
  out.strips = STRIP;
  out.geometry = Object.fromEntries([['momo', 64, 'rest'], ['momo', 64, 'turned'], ['shrimpy', 20, 'rest'], ['midnight', 28, 'rest']].map(([cat, D, pose]) =>
    [`${cat}/${D}/${pose}`, Object.fromEntries(core.OUTFIT_DRAWN.map(id => [id, core.outfitGeometry(id, core.PRESETS[cat], POSES[pose], D, opts(core.PRESETS[cat], POSES[pose], D))]))]));
  out.digests = Object.fromEntries(core.CAT_IDS.flatMap(cat => core.OUTFIT_DRAWN.flatMap(id => [18, 20, 48, 64].map(D => [`${cat}/${id}/${D}`, core.outfitDigest(core.outfitGeometry(id, core.PRESETS[cat], POSES.rest, D, opts(core.PRESETS[cat], POSES.rest, D)))]))));
  out.collars = Object.fromEntries(['bell', 'bandana', 'scarf'].flatMap(id => core.COLLAR_STYLES.map(style => [`${id}/${style}`, { collar: core.collarGeometry(core.PRESETS.momo, POSES.rest, 64, style, { dpr: 2 }), shapes: core.outfitGeometry(id, core.PRESETS.momo, POSES.rest, 64, { dpr: 2, collar: style }) }])));
  out.unknown = ['none', 'auto', 'fancyhat', '', null, 7, '__proto__'].map(id => ({ id, out: core.outfitGeometry(id, core.PRESETS.momo, POSES.rest, 64, { dpr: 2 }) }));
  out.fine = core.OUTFIT_DRAWN.map(id => ({ id, at27: core.outfitGeometry(id, core.PRESETS.momo, POSES.rest, 27, { dpr: 2 }).length, at28: core.outfitGeometry(id, core.PRESETS.momo, POSES.rest, 28, { dpr: 2 }).length }));
  // The owner's checkpoint: the shrimp clip switches at the detail cut (DETAIL_FULL_MIN). Each row lists the shapes one side draws, as kind, slot, fill role, stroke role and fine.
  const shapesOf = (id, cat, D) => core.outfitGeometry(id, core.PRESETS[cat], POSES.rest, D, opts(core.PRESETS[cat], POSES.rest, D)).map(sh => [sh.k, sh.slot, sh.fill ?? null, sh.stroke ?? null, sh.fine]);
  out.shrimpSwitch = { threshold: core.DETAIL_FULL_MIN, rows: [18, 20, 27, 28, 48].map(D => ({ D, full: D >= core.DETAIL_FULL_MIN, shapes: shapesOf('shrimpclip', 'momo', D) })) };
  // The sunglasses' lenses: a dark head (edge 'light') gets a thin light rim in the edge role; a light head keeps the frame.
  out.lensRims = ['momo', 'midnight', 'ginger', 'snow'].map(cat => ({ cat, edge: core.outfitEdge(core.PRESETS[cat]), lenses: core.outfitGeometry('sunglasses', core.PRESETS[cat], POSES.rest, 64, opts(core.PRESETS[cat], POSES.rest, 64)).filter(sh => sh.k === 'ellipse' && sh.fill === 'lens').map(sh => ({ stroke: sh.stroke, sw: sh.sw })) }));
  // @@WARDROBE-SECTIONS: each task adds its keys to `out` immediately above this line.
  return out;
};
// @@BUILDERS: each task adds `FILES['name.json'] = () => ({ ... })` immediately above this line.

function main(argv) {
  const check = argv.includes('--check');
  const oi = argv.indexOf('--out');
  const outDir = oi >= 0 ? path.resolve(argv[oi + 1]) : FIXTURES;
  const names = Object.keys(FILES).sort();
  let failed = false;
  if (check) {
    for (const name of names) {
      const file = path.join(FIXTURES, name);
      if (!fs.existsSync(file)) { console.log(`  ✗ ${name} is missing (run node scripts/gen-cat-fixtures.mjs)`); failed = true; continue; }
      const diffs = compare(fix(finish(FILES[name]())), JSON.parse(fs.readFileSync(file, 'utf8')));
      if (diffs.length) { failed = true; console.log(`  ✗ ${name} drifted from cat-core.js (${diffs.length} differences)`); diffs.slice(0, 5).forEach(d => console.log(`      ${d}`)); }
      else console.log(`  ✓ ${name}`);
    }
    const stale = fs.existsSync(FIXTURES) ? fs.readdirSync(FIXTURES).filter(f => f.endsWith('.json') && !names.includes(f)) : [];
    for (const f of stale) { failed = true; console.log(`  ✗ ${f} is not produced by the generator`); }
    if (failed) { console.log('Fixtures drifted. cat-core.js is the tie-breaker: if the change is intended, run node scripts/gen-cat-fixtures.mjs and commit the result.'); process.exit(1); }
    console.log(`✓ ${names.length} fixture files match cat-core.js`);
    return;
  }
  fs.mkdirSync(outDir, { recursive: true });
  for (const name of names) fs.writeFileSync(path.join(outDir, name), format(fix(finish(FILES[name]()))));
  console.log(`wrote ${names.length} fixture files to ${path.relative(ROOT, outDir) || '.'}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main(process.argv.slice(2));
