# A-0 The Cat Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the prototype's pure maths into one shared module, `design/prototype/cat-core.js`, and generate from it the fixture files that both app engines (A-tauri and A-mac) will be tested against, with a CI check that fails on any drift.

**Architecture:** `cat-core.js` is a plain script that sets one global (`CatCore`) and also works as a Node module (`module.exports`), so the prototype page and Node share one file with no build step. It holds numbers-in, numbers-out code only: the page keeps the canvas drawing and is refactored to call the core. `scripts/gen-cat-fixtures.mjs` (Node, no npm packages) writes seven fixture files to `tests/fixtures/cat/`, and `scripts/test-cat-contract.sh` regenerates them in memory, fails on any drift, runs the core's self-checks and proves that two runs write identical bytes. It is the same pattern as E1's AI contract: fixtures, a reference runner, a CI step and a no-drift check.

**Tech Stack:** JavaScript (one file for both a browser and Node 22), `node:test` and `node:assert` (no npm packages), Bash, GitHub Actions, and headless Chromium through `playwright-cli` for the one-off page check.

**Spec:** `docs/superpowers/specs/2026-10-04-cats-in-app-design.md` (§2 and the A-0 row of §1, the "Room for later sub-projects" note, the greeting decision and the `voice` field). The parent spec's approved character rules are in `docs/superpowers/specs/2026-10-03-notchmeow-design.md`, "Sub-project A, steps" §2. The prototype `design/prototype/notchmeow.html` at commit `683163f` is the source of every number. Read all three before starting.

**Base:** branch `notchmeow/rebrand` at `683163f` (E1 merged) or later, run in a git worktree. The prototype page must still be the one from `683163f`: Task 7 checks its hash. This plan touches no file under `NotchBuddy/` or `windows/`.

## Global Constraints

Every task's requirements include this section. Values are copied from the specs.

- **Cat IDs are frozen, in this order:** `shrimpy`, `momo`, `ginger`, `midnight`, `latte`, `patches`, `blue`, `snow`, `oreo`, `mocha`, `silver`, `cloud`, `leo`, `button`, `puff`, `noodle`. An unknown stored ID falls back to `shrimpy`. The prototype's old keys `siamese`, `calico`, `ragdoll`, `bengal`, `fold`, `persian` and `sphynx` become `latte`, `patches`, `cloud`, `leo`, `button`, `puff` and `noodle`. (The coat *type* `calico` stays.)
- **`voice`** (a pitch offset in semitones, for sub-project C): Shrimpy −1, Momo +1, the extra coats 0, kittens +3.
- **Tolerance:** apps compare numbers within **1e-9 R** (Swift and JavaScript can differ in the last bit of `sin`/`cos`). Fixtures store 12 significant digits. There are no pixel tests.
- **Randomness:** every random choice (idle bleps, winks, ear flicks and the like) draws from an injected `rand()`, and the fixtures fix the random sequence. The core never calls `Math.random()` except as the late-bound default of an engine, and never reads a clock except as the default `now()`.
- **`cat-core.js` is the tie-breaker:** if an app and a fixture disagree, the module decides.
- **One file, no build step:** a plain script that sets one global (`CatCore`) and also works as a Node module. No canvas and no DOM in it: drawing stays in `notchmeow.html`.
- **Detail levels:** head width Ø28 and up draws the full cat; below Ø28 the compact cat (ink eyes; no irises, "M" stripes, cheek bars or whiskers).
- **Face warp:** the face takes 82 % of the 0.62 rad gaze yaw, 60 % of the 0.5 rad pitch looking up and 32 % looking down; the muzzle stands proud by +0.12 and the nose by another 0.05 R; the outline leans 0.1 rx and the head shifts 0.08 R toward the cursor; the near eye never foreshortens below 55 %; the pupils travel up to 0.24 of the eye width; the cursor curve is tanh over 240 px across and 180 px up and down.
- **Badge:** beside the right ear, 1.4 R right and 0.92 R up; on the left in the compact notch.
- **Mouth:** the upstream slot spring, ω₀ = 2π/0.25 and ζ = 0.6; six animatable values (open, smile, tongue, round, skew, wavy).
- **Hairball** 2.4 s. **Zoomies** 2 s, and they play after an agent finishes **5 minutes** of working, thinking or searching (12 s in the prototype page); approval and question pauses don't reset that clock. **Sleeping** starts after **10 minutes** with no agent event and never during an approval or a question.
- **File catch, four steps:** open wide while a file hovers; snap wider on the drop while the file flies in; gulp with a squash; chew for 0.85 s with happy eyes.
- **Greeting:** the new greeting (`GT2`/`greetPose2`) becomes *the* greeting and the old timeline is dropped. The total stays 5.74 s. No upstream sound.
- **The prototype page must behave exactly as before,** except for the greeting (and the comparison panel that showed the old one).
- **Dependencies and code style:** Node standard library only, no npm packages. Code moved from the prototype stays as written; new code is plain and commented.
- **Commits:** local only, never pushed. End every commit message with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Review Focus

The spec says what the cats must do. It is silent on these inputs, and each would bite a person (or a port) first. Each line names its test.

1. **An unknown name where a name is expected** (a stored cat ID, a state, an emote, a motion style, a personality preset). Expected: a fallback (Shrimpy, Playful, Balanced) or a no-op, and never a throw. Tests: Task 2 `catById`, Task 4 `personaNamed` and `slide`, Task 6 "unknown names never throw".
2. **A bad frame time:** zero, negative, NaN or huge `dt`, as from a sleeping laptop or the Mac's clock bug that mixes two clocks. Expected: the pose stays finite and `dt` is held to 0 up to 0.25 s. Test: Task 6 "hostile frame times".
3. **A hand-edited personality:** a trait outside 0 to 1, missing, or the wrong type. Expected: held to 0 to 1, missing counts as 0.5, nothing goes negative or NaN. Test: Task 4 "hand-edited values", and the same inputs in `personality-cases.json`.
4. **A head pushed past what it can show:** rolled over the top, turned away, or a head width of 0. Expected: the face fades, eyes and nose are hidden, `mouth` is null, no number is NaN. Test: Task 3 "extreme poses never produce NaN".
5. **The edges of a rule:** exactly 5 minutes of work against 1 ms short, exactly 10 minutes of quiet, a run that starts at clock 0, an approval pause inside a run, and a clock that steps backwards. Expected: the rule fires at the stated line, and never on a negative time. Test: Task 5 (zoomies, sleep and the work clock).

---

## File Structure

| Path | Responsibility |
|---|---|
| `design/prototype/cat-core.js` | The contract. Every pure part of the cat in one plain script: it sets `CatCore` in a page and is `module.exports` in Node. |
| `design/prototype/notchmeow.html` | The prototype page. After Task 7 it loads `cat-core.js` and keeps only the renderer and the controls. |
| `scripts/gen-cat-fixtures.mjs` | Writes `tests/fixtures/cat/*.json` from the core, or checks them with `--check`. Also exports the file helpers and the test harness (`makeEngine`, `frameMs`). |
| `scripts/test-cat-contract.sh` | The runner: self-checks, the no-drift check, the determinism check. CI runs it. |
| `tests/cat/*.test.mjs` | The core's self-checks, one file per area, run with `node --test`. |
| `tests/fixtures/cat/*.json` | The seven generated fixtures: `presets`, `geometry-cases`, `warp-cases`, `motion-cases`, `personality-cases`, `sequence-cases`, `search-tools`. |
| `docs/CAT-CONTRACT.md` | Fixture shapes, units, the seeding rule, the tolerance and "`cat-core.js` is the tie-breaker". |
| `.github/workflows/build.yml` | One CI step next to the AI contract. |
| `CLAUDE.md`, `ARCHITECT.md` | One pointer each. |

One-off checks (Tasks 2, 5, 6 and 7) live in `${TMPDIR:-/tmp}/a0-check/` and are never committed.

**Agents** (CLAUDE.md: the lightest model that fits). Tasks 1 to 6 and 8 give their full code, so they are transcription: `nm-implementer-light`. If the engine check in Task 6 fails and the cause is not obvious, hand that task to `nm-implementer-deep`. Task 7 runs a browser and judges screenshots: `nm-implementer`. Task reviews: `nm-reviewer`; the final whole-branch review: `nm-reviewer-deep`. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; reviewers load `ponytail:ponytail-review`.

**Order of tasks:** each task adds one section to `cat-core.js` and the matching fixture builders, test first.

1. Core skeleton, helpers, tables, the runner
2. Presets, kittens and the frozen IDs
3. Geometry and the face warp
4. Personality
5. Rules and timelines: work clock, sleep, search tools, greeting, file flight
6. Motion profiles and the engine
7. Refactor the prototype page to use the core
8. Docs, CI and the final checks

---

### Task 1: Core skeleton, helpers, tables and the runner

**Files:**
- Create: `design/prototype/cat-core.js`
- Create: `scripts/gen-cat-fixtures.mjs`
- Create: `scripts/test-cat-contract.sh`
- Create: `tests/cat/basics.test.mjs`
- Create: `tests/cat/fixture-util.test.mjs`

**Interfaces:**
- Consumes: nothing.
- Produces `CatCore`, a global in a page and `module.exports` in Node: `VERSION` (1); the helpers `TAU`, `EZ` (`out`, `inOut`, `back`, `lin`, `in`, each `t => number`), `lerp(a, b, t)`, `clamp(v, a, b)`, `seg(t, a, b)` (0 to 1 over a to b), `hex('#RRGGBB')` to `[r, g, b]`, `wrapA(rad)` to `[-π, π)`, `rng(seed)` to a `() => number` in `[0, 1)` (a 32-bit LCG: `s = (imul(s, 1103515245) + 12345) >>> 0`, then `s / 2^32`), `tm(v, lo, hi)` (lo at 0, 1 at 0.5, hi at 1) and `own(obj, key)`; the tables `STATES` (11 names), `COL`, `TINT`, `GLOW`, `BADGE`, `MOUTH` (state to six numbers), `MKEYS`, `EMOUTH`, `BUSY` (a `Set`) and `mouthFx(state, seconds)`.
- Produces `scripts/gen-cat-fixtures.mjs`: exports `fix(value)` (12 significant digits, tiny values to 0, throws on non-finite), `format(obj)`, `compare(got, want)` (a list of differences, numbers within `TOLERANCE`), `finish(obj)` and `TOLERANCE` (1e-9). Later tasks register fixtures with `FILES['name.json'] = () => ({ version: 1, ... })` above the `@@BUILDERS` marker. Command line: no flag writes `tests/fixtures/cat/`, `--check` regenerates in memory and exits 1 on drift, `--out DIR` writes elsewhere.
- Produces the marker line `// @@END-OF-CORE` at the end of `cat-core.js`. Every later task inserts its section immediately above it.

- [ ] **Step 1: Write the failing tests**

Create `tests/cat/basics.test.mjs`:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const core = require('../../design/prototype/cat-core.js');
const near = (a, b, eps = 1e-12) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);

test('rng is the seeded uint32 LCG (known answers computed independently in Python)', () => {
  const first = seed => { const r = core.rng(seed); return [r(), r(), r(), r()]; };
  assert.deepEqual(first(0), [2.8742942959070206e-06, 0.8275770242325962, 0.6524071616586298, 0.8374803168699145]);
  assert.deepEqual(first(1), [0.25693503906950355, 0.5878706516232342, 0.15432575810700655, 0.767266943352297]);
  assert.deepEqual(first(13), [0.3401210163719952, 0.7113941803108901, 0.17734891548752785, 0.924706461140886]);
  assert.deepEqual(first(29), [0.45103565277531743, 0.876092218561098, 0.20804645866155624, 0.8012924848590046]);
});

test('rng: the same seed repeats, different seeds differ, the seed wraps to uint32, values stay in [0, 1)', () => {
  const a = core.rng(7), b = core.rng(7), c = core.rng(8);
  const sa = Array.from({ length: 50 }, a), sb = Array.from({ length: 50 }, b), sc = Array.from({ length: 50 }, c);
  assert.deepEqual(sa, sb);
  assert.notDeepEqual(sa, sc);
  assert.deepEqual(Array.from({ length: 5 }, core.rng(2 ** 32 + 7)), sa.slice(0, 5));
  assert.ok(sa.every(v => v >= 0 && v < 1));
});

test('easings, lerp, seg, clamp, wrapA and tm', () => {
  for (const k of ['out', 'inOut', 'back', 'lin', 'in']) { near(core.EZ[k](0), 0); near(core.EZ[k](1), 1); }
  near(core.EZ.inOut(.5), .5);
  near(core.EZ.out(.5), .875);
  near(core.EZ.in(.5), .125);
  assert.ok(core.EZ.back(.8) > 1, 'back overshoots');
  near(core.lerp(2, 10, .25), 4);
  assert.equal(core.clamp(5, 0, 1), 1);
  assert.equal(core.seg(-1, 0, 2), 0);
  near(core.seg(1, 0, 2), .5);
  assert.equal(core.seg(9, 0, 2), 1);
  near(core.wrapA(Math.PI * 2.5), Math.PI / 2, 1e-9);
  near(core.wrapA(Math.PI), -Math.PI, 1e-9); // the range is [-π, π)
  near(core.wrapA(-Math.PI * 2.5), -Math.PI / 2, 1e-9);
  near(core.tm(0, .3, 2), .3); near(core.tm(.5, .3, 2), 1); near(core.tm(1, .3, 2), 2); near(core.tm(.25, .3, 2), .65);
  assert.deepEqual(core.hex('#3B9EFF'), [59, 158, 255]);
});

test('the eleven states and their tables', () => {
  assert.deepEqual(core.STATES, ['idle', 'working', 'thinking', 'searching', 'approval', 'question', 'error', 'finished', 'ratelimit', 'sleeping', 'dizzy']);
  for (const t of [core.COL, core.TINT, core.MOUTH]) assert.deepEqual(Object.keys(t), core.STATES);
  assert.deepEqual(Object.keys(core.GLOW), ['working', 'thinking', 'searching', 'approval', 'error', 'finished', 'ratelimit']);
  assert.deepEqual(Object.keys(core.BADGE), ['working', 'thinking', 'searching', 'approval', 'question', 'error', 'finished', 'ratelimit']);
  assert.deepEqual(core.MKEYS, ['mouth', 'smile', 'tongue', 'mround', 'mskew', 'wavy']);
  for (const row of Object.values(core.MOUTH)) assert.equal(row.length, 6);
  assert.deepEqual(Object.keys(core.EMOUTH), ['love', 'surprised', 'proud', 'wink', 'yawn', 'happy', 'annoyed']);
  assert.deepEqual([...core.BUSY], ['working', 'thinking', 'searching']);
});

test('mouthFx: hunting chatter, meows, panting and snoring', () => {
  assert.equal(core.mouthFx('searching', 0), 0);
  assert.equal(core.mouthFx('searching', 2.0), 0, 'quiet part of the 2.6 s cycle');
  assert.ok(core.mouthFx('searching', .55) > .15, 'mid burst');
  near(core.mouthFx('approval', .196), .5);
  assert.equal(core.mouthFx('approval', .7), 0);
  near(core.mouthFx('ratelimit', 1 / (4 * 2.8)), .07);
  near(core.mouthFx('sleeping', Math.PI / 3), .07);
  assert.equal(core.mouthFx('idle', 1.234), 0);
});

test('one file serves both worlds: require() and a plain script that sets one global', () => {
  const src = fs.readFileSync(new URL('../../design/prototype/cat-core.js', import.meta.url), 'utf8');
  const sandbox = {};
  vm.runInNewContext(src, sandbox);
  assert.equal(typeof sandbox.CatCore, 'object');
  assert.equal(sandbox.CatCore.VERSION, 1);
  assert.deepEqual(Object.keys(sandbox.CatCore).sort(), Object.keys(core).sort());
  assert.equal(Object.keys(sandbox).length, 1, 'the page sees exactly one new global');
  assert.ok(!/\bMath\.random\b/.test(src.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, '').replace(/\(\)=>Math\.random\(\)/g, '')), 'the only Math.random is the late-bound default');
});
```

Create `tests/cat/fixture-util.test.mjs`:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { fix, format, compare, finish, TOLERANCE } from '../../scripts/gen-cat-fixtures.mjs';

test('fix keeps 12 significant digits and snaps libm noise to zero', () => {
  assert.equal(fix(0.1 + 0.2), 0.3);
  assert.equal(fix(Math.sin(Math.PI)), 0);
  assert.equal(fix(-0), 0);
  assert.ok(Object.is(fix(-1e-15), 0), 'a tiny negative becomes +0');
  assert.equal(fix(1234.5678901234567), 1234.56789012);
  assert.deepEqual(fix({ a: [1 / 3, 'x', null, true], b: { c: 2 / 3 } }), { a: [0.333333333333, 'x', null, true], b: { c: 0.666666666667 } });
  assert.throws(() => fix({ x: NaN }), /non-finite/);
  assert.throws(() => fix([Infinity]), /non-finite/);
});

test('format writes one case per line for arrays of objects and one entry per line for maps of objects', () => {
  const text = format({ version: 1, tags: ['a', 'b'], cases: [{ n: 1 }, { n: 2 }], cats: { x: { v: 1 }, y: { v: 2 } } });
  assert.equal(text, [
    '{',
    '  "version": 1,',
    '  "tags": ["a","b"],',
    '  "cases": [',
    '    {"n":1},',
    '    {"n":2}',
    '  ],',
    '  "cats": {',
    '    "x": {"v":1},',
    '    "y": {"v":2}',
    '  }',
    '}',
    ''
  ].join('\n'));
  assert.deepEqual(JSON.parse(text), { version: 1, tags: ['a', 'b'], cases: [{ n: 1 }, { n: 2 }], cats: { x: { v: 1 }, y: { v: 2 } } });
});

test('compare allows 1e-9 on numbers and nothing on structure, strings or key sets', () => {
  assert.equal(TOLERANCE, 1e-9);
  assert.deepEqual(compare({ a: [1, 2], s: 'x' }, { a: [1 + 5e-10, 2 - 5e-10], s: 'x' }), []);
  assert.equal(compare({ a: 1 }, { a: 1 + 2e-9 }).length, 1);
  assert.equal(compare({ a: [1, 2] }, { a: [1] }).length, 1);
  assert.equal(compare({ a: 1 }, { a: 1, b: 2 }).length, 1);
  assert.equal(compare({ s: 'x' }, { s: 'y' }).length, 1);
  assert.equal(compare({ a: null }, { a: 0 }).length, 1);
  assert.match(compare({ a: { b: [0, 1] } }, { a: { b: [0, 2] } })[0], /\$\.a\.b\[1\]/);
});

test('finish puts the version first, then the tolerance apps compare with', () => {
  assert.deepEqual(Object.keys(finish({ cases: [], version: 1, note: 'x' })), ['version', 'tolerance', 'cases', 'note']);
  assert.equal(finish({ version: 1 }).tolerance, 1e-9);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `node --test tests/cat/*.test.mjs`
Expected: FAIL. Both files fail to load with `ERR_MODULE_NOT_FOUND` (`cat-core.js` and `gen-cat-fixtures.mjs` don't exist yet).

- [ ] **Step 3: Create the core**

Create `design/prototype/cat-core.js`:

```js
/**
 * cat-core.js: NotchMeow's cat contract. Everything pure about Shrimpy, Momo and the other
 * coats: presets, face warp and geometry, state/mouth/emote tables, both motion profiles,
 * personality, the greeting and file-catch timelines, and the zoomies, sleep and search rules.
 *
 * Numbers in, numbers out. No canvas, no DOM, no clock of its own and no Math.random: an engine
 * is given `now()` and `rand()`, and a test gives it a fake clock and a seeded `rng(seed)`.
 * Units are R, the head radius, unless a name says px or ms.
 *
 * One file serves both worlds. A page loads it with <script src>, which sets `CatCore`.
 * Node loads it with require(), which returns the same object. There is no build step.
 *
 * This file is the tie-breaker. If an app and a fixture in tests/fixtures/cat/ disagree,
 * the fixture was generated from here, so the app is wrong. See docs/CAT-CONTRACT.md.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.CatCore = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
'use strict';
const api = { VERSION: 1 };

// ── Helpers ──────────────────────────────────────────────────────────────────
const TAU=Math.PI*2;
const EZ={out:t=>1-Math.pow(1-t,3),inOut:t=>t<.5?4*t*t*t:1-Math.pow(-2*t+2,3)/2,back:t=>1+2.7*Math.pow(t-1,3)+1.7*Math.pow(t-1,2),lin:t=>t,in:t=>t*t*t};
const lerp=(a,b,t)=>a+(b-a)*t,clamp=(v,a,b)=>Math.max(a,Math.min(b,v)),seg=(t,a,b)=>clamp((t-a)/(b-a),0,1);
const hex=h=>[parseInt(h.slice(1,3),16),parseInt(h.slice(3,5),16),parseInt(h.slice(5,7),16)];
const wrapA=a=>((a+Math.PI)%TAU+TAU)%TAU-Math.PI;
/** The seeded PRNG: a 32-bit LCG. Same seed, same sequence, on every platform (uint32 wrap-around maths). */
function rng(seed){let s=seed>>>0;return()=>((s=(Math.imul(s,1103515245)+12345)>>>0)/4294967296)}
/** Maps a trait to a multiplier: lo at 0, 1 at 0.5, hi at 1. */
const tm=(v,lo,hi)=>v<.5?lerp(lo,1,v/.5):lerp(1,hi,(v-.5)/.5);
const own=(o,k)=>Object.prototype.hasOwnProperty.call(o,k);

// ── State tables (colours and tints from upstream engine.ts) ─────────────────
const COL={idle:'#E6E9EE',working:'#3B9EFF',thinking:'#8B5CF6',searching:'#6366F1',approval:'#F5A524',question:'#22D3EE',error:'#F4505E',finished:'#34D399',ratelimit:'#FB923C',sleeping:'#94A3B8',dizzy:'#F472B6'};
const TINT={idle:0,working:.72,thinking:.72,searching:.72,approval:.78,question:.75,error:.78,finished:.35,ratelimit:.72,sleeping:.32,dizzy:.7};
const GLOW={working:'#3B9EFF',thinking:'#A78BFA',searching:'#6366F1',approval:'#F5A524',error:'#F4505E',finished:'#34D399',ratelimit:'#F59E0B'};
const BADGE={working:'dots',thinking:'dots',searching:'dots',approval:'bang',question:'question',error:'dot',finished:'dot',ratelimit:'dot'};
const STATES=Object.keys(COL);

// ── Mouth ────────────────────────────────────────────────────────────────────
// Rest mouth per state: open, smile (-1 frown … 1 smile), tongue, round (D … 'o'), skew, wavy.
const MOUTH={idle:[0,0,0,0,0,0],working:[0,.05,.35,0,0,0],thinking:[0,-.15,0,0,.7,0],searching:[0,0,0,0,0,0],approval:[0,.1,0,.35,0,0],question:[.13,0,0,1,0,0],error:[0,-.8,0,0,0,0],finished:[0,1,0,0,0,0],ratelimit:[.3,0,.85,.2,0,0],sleeping:[0,.1,0,1,0,0],dizzy:[0,0,.45,0,0,1]};
const MKEYS=['mouth','smile','tongue','mround','mskew','wavy'];
// Emote mouths, shared by both motion styles: [pose, duration ms].
const EMOUTH={love:[{smile:.8},1800],surprised:[{mouth:.6,mround:1},1000],proud:[{smile:.75,mskew:.45},1800],wink:[{tongue:.8,smile:.4,mskew:.3},1100],yawn:[{tongue:.35,mround:.15},1100],happy:[{mouth:.5,smile:1},1300],annoyed:[{smile:-.7,mskew:-.6},850]};
/** Per-frame mouth motion on top of the rest shape: hunting chatter, meows, panting, snoring. */
function mouthFx(st,T){switch(st){
 case 'searching':{const ph=T%2.6;return ph<1.1?Math.sin(Math.PI*ph/1.1)*(.24+.07*Math.sin(T*TAU*9)):0}
 case 'approval':{const ph=(T%1.4)/1.4;return ph<.28?.5*Math.sin(Math.PI*ph/.28):0}
 case 'ratelimit':return .07*Math.sin(T*TAU*2.8);
 case 'sleeping':return .07*Math.max(0,Math.sin(T*1.5));
 default:return 0}}
const BUSY=new Set(['working','thinking','searching']);

Object.assign(api,{TAU,EZ,lerp,clamp,seg,hex,wrapA,rng,tm,own,COL,TINT,GLOW,BADGE,STATES,MOUTH,MKEYS,EMOUTH,mouthFx,BUSY});

// @@END-OF-CORE: every later task inserts its section immediately above this line.
return api;
});
```

- [ ] **Step 4: Create the generator and the runner**

Create `scripts/gen-cat-fixtures.mjs`:

```js
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
```

Create `scripts/test-cat-contract.sh`:

```bash
#!/usr/bin/env bash
# Runs the cat contract: cat-core.js self-checks, a no-drift check of tests/fixtures/cat/ against
# the module, and a determinism check (two generator runs must write identical bytes).
set -euo pipefail
cd "$(dirname "$0")/.."
command -v node >/dev/null || { echo "node (22 or newer) is required" >&2; exit 1; }
node --test tests/cat/*.test.mjs
node scripts/gen-cat-fixtures.mjs --check
a=$(mktemp -d); b=$(mktemp -d)
trap 'rm -rf "$a" "$b"' EXIT
node scripts/gen-cat-fixtures.mjs --out "$a" >/dev/null
node scripts/gen-cat-fixtures.mjs --out "$b" >/dev/null
diff -r "$a" "$b" >/dev/null || { echo "✗ two generator runs wrote different bytes" >&2; exit 1; }
echo "✓ two generator runs write identical bytes"
```

Then make both executable: `chmod +x scripts/test-cat-contract.sh scripts/gen-cat-fixtures.mjs`

- [ ] **Step 5: Run everything and verify it passes**

Run: `bash scripts/test-cat-contract.sh`
Expected: `# tests 10`, `# pass 10`, `# fail 0`, then `✓ 0 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`. There are no fixtures yet, so the check is empty on purpose; Task 2 writes the first one.

- [ ] **Step 6: Commit**

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs scripts/test-cat-contract.sh tests/cat/basics.test.mjs tests/cat/fixture-util.test.mjs
git commit -m "feat(cat): cat-core.js skeleton, fixture generator and contract runner

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Presets, kittens and the frozen IDs

**Files:**
- Modify: `design/prototype/cat-core.js` (insert a section above `@@END-OF-CORE`)
- Modify: `scripts/gen-cat-fixtures.mjs` (insert a builder above `@@BUILDERS`)
- Create: `tests/cat/presets.test.mjs`
- Create: `tests/fixtures/cat/presets.json` (generated)

**Interfaces:**
- Consumes: `own` from Task 1.
- Produces: `PRESETS` (ID to preset, in units of R), `CAT_IDS` (the 16 frozen IDs, Shrimpy first and Momo second), `MORE` (the 14 extra coats), `makeCat(overrides)` (the shorthair template), `kittenOf(preset)` (a deep copy with `kitten: true`, `base`, `label + ' kitten'` and `voice: 3`), `catById(id)` (the preset, or Shrimpy for anything unknown). Every preset has `voice`.
- Produces: `tests/fixtures/cat/presets.json`, shaped `{version, tolerance, note, ids[16], cats{id: preset}, kittens{id: preset}}`.

The presets are the prototype's `PRESETS` block (lines 133 to 214 of `design/prototype/notchmeow.html` at `683163f`), moved as written. Only three things change: the seven IDs that don't match the frozen list are renamed, `voice` is added, and `catById` is new.

- [ ] **Step 1: Write the failing tests**

Create `tests/cat/presets.test.mjs`:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const core = require('../../design/prototype/cat-core.js');
const fixture = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/presets.json', import.meta.url), 'utf8'));
const near = (a, b, eps = 1e-12) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);

// The frozen cat IDs, written out here on purpose: renaming one in cat-core.js and regenerating must fail this test.
const FROZEN_IDS = ['shrimpy', 'momo', 'ginger', 'midnight', 'latte', 'patches', 'blue', 'snow', 'oreo', 'mocha', 'silver', 'cloud', 'leo', 'button', 'puff', 'noodle'];

test('sixteen cats with frozen IDs, Shrimpy first and Momo second', () => {
  assert.deepEqual(core.CAT_IDS, FROZEN_IDS);
  assert.deepEqual(fixture.ids, FROZEN_IDS);
  assert.deepEqual(Object.keys(core.PRESETS).sort(), [...FROZEN_IDS].sort());
  for (const id of FROZEN_IDS) assert.equal(core.PRESETS[id].name, id, `${id}: name equals its key`);
  assert.deepEqual(core.MORE, FROZEN_IDS.slice(2));
});

test('voice: Shrimpy -1, Momo +1, the extra coats 0, every kitten +3', () => {
  assert.equal(core.PRESETS.shrimpy.voice, -1);
  assert.equal(core.PRESETS.momo.voice, 1);
  for (const id of core.MORE) assert.equal(core.PRESETS[id].voice, 0, id);
  for (const id of FROZEN_IDS) assert.equal(core.kittenOf(core.PRESETS[id]).voice, 3, `${id} kitten`);
  for (const id of FROZEN_IDS) {
    assert.equal(fixture.cats[id].voice, id === 'shrimpy' ? -1 : id === 'momo' ? 1 : 0, `fixture ${id}`);
    assert.equal(fixture.kittens[id].voice, 3, `fixture ${id} kitten`);
  }
});

test('the approved Shrimpy and Momo numbers (spec: approved character design)', () => {
  const m = core.PRESETS.momo, s = core.PRESETS.shrimpy;
  assert.deepEqual([m.rx, m.ry, m.n, m.fluff], [1.12, .9, 2.2, 0]);
  assert.deepEqual([m.ear.h, m.ear.bw, m.ear.rot], [.8, .56, .5]);
  assert.equal(m.top, '#3D3D41'); assert.equal(m.white, '#F6F4F1'); assert.equal(m.inner, '#B98288'); assert.equal(m.nose, '#E89AA6');
  assert.deepEqual(m.iris, ['#7E8A45', '#D1B85F']); assert.equal(m.lidTint, '#D9BE62'); assert.equal(m.ink, '#E4D592');
  assert.deepEqual([s.rx, s.ry, s.n, s.fluff], [1.16, .92, 2.2, 1]);
  assert.deepEqual(s.ruff, { rx: 1.3, ry: .97, dy: .2, col: ['#B49C7A', '#7E6750'] });
  assert.deepEqual([s.ear.h, s.ear.bw, s.ear.rot, s.ear.tuft], [.8, .4, .44, 1]);
  assert.equal(s.top, '#A08A70'); assert.equal(s.bot, '#6E5B49'); assert.equal(s.stripe, '#2E241D'); assert.equal(s.nose, '#C07A62');
  assert.deepEqual(s.iris, ['#C9D18A', '#6F8445']); assert.equal(s.ink, '#231A14');
  assert.deepEqual([m.whisk2.rows, m.whisk2.cols, m.whisk2.brow], [3, 2, 2]);
  assert.deepEqual([s.whisk2.rows, s.whisk2.cols, s.whisk2.brow], [3, 3, 3]);
});

test('makeCat fills the shorthair template and merges nested overrides', () => {
  const c = core.makeCat({ name: 'x', ear: { h: .9 }, eye: { w: .3 }, whisk2: { len: 1 }, top: '#000000' });
  assert.deepEqual([c.coat, c.rx, c.ry, c.n, c.voice, c.fluff, c.ruff], ['solid', 1.12, .9, 2.2, 0, 0, null]);
  assert.deepEqual([c.ear.h, c.ear.bw, c.ear.rot, c.ear.cx], [.9, .5, .46, .7]);
  assert.deepEqual([c.eye.w, c.eye.h, c.eye.round], [.3, .17, 1]);
  assert.deepEqual([c.whisk2.len, c.whisk2.rows, c.whisk2.cols], [1, 3, 2]);
  assert.equal(c.top, '#000000');
});

test('kittenOf follows the approved rules and never touches its parent', () => {
  for (const id of ['shrimpy', 'momo', 'puff', 'noodle']) {
    const p = core.PRESETS[id], before = JSON.stringify(p), k = core.kittenOf(p);
    assert.equal(JSON.stringify(p), before, `${id}: parent unchanged`);
    assert.deepEqual([k.kitten, k.base, k.label], [true, id, `${p.label} kitten`]);
    near(k.rx, p.rx * .97); near(k.ry, p.ry * 1.02); assert.equal(k.n, 2.05);
    near(k.ear.h, p.ear.h * 1.12); near(k.ear.bw, p.ear.bw * 1.06); assert.equal(k.ear.tuft, 0);
    near(k.eye.w, p.eye.w * 1.2); near(k.eye.h, p.eye.h * 1.32); assert.equal(k.eye.round, 1); near(k.eye.th, p.eye.th + .02);
    near(k.nosePh, p.nosePh + .08); near(k.noseW, p.noseW * .85); near(k.noseH, p.noseH * .85);
    near(k.whisk2.len, p.whisk2.len * .7); assert.equal(k.whisk2.brow, 1);
    near(k.pupil0, Math.max(p.pupil0, .18));
    if (p.ruff) { near(k.ruff.rx, p.ruff.rx * .94); near(k.ruff.ry, p.ruff.ry * .92); } else assert.equal(k.ruff, null);
    assert.equal(k.top, p.top); assert.equal(k.coat, p.coat);
  }
});

test('catById: an unknown, odd or inherited ID falls back to Shrimpy', () => {
  assert.equal(core.catById('momo'), core.PRESETS.momo);
  assert.equal(core.catById('noodle'), core.PRESETS.noodle);
  for (const bad of ['', 'SHRIMPY', 'siamese', 'calico', 'constructor', '__proto__', 'toString', 'hasOwnProperty', null, undefined, 42, {}, ['momo']]) {
    assert.equal(core.catById(bad), core.PRESETS.shrimpy, `${String(bad)} falls back`);
  }
});

test('every coat has what the renderer reads', () => {
  const coats = new Set(['tuxedo', 'tabby', 'point', 'calico', 'solid']);
  for (const id of FROZEN_IDS) {
    const p = core.PRESETS[id];
    assert.ok(coats.has(p.coat), `${id}: coat type ${p.coat}`);
    for (const k of ['top', 'bot', 'inner', 'nose', 'noseLine', 'liner', 'ink', 'mouthLine', 'whisk', 'padDot', 'paw', 'bean', 'hair', 'hairDark', 'hairLight']) assert.match(p[k], /^(#[0-9A-Fa-f]{6}|rgba\()/, `${id}.${k}`);
    assert.equal(p.iris.length, 2, `${id}: iris`);
    for (const k of ['rx', 'ry', 'n', 'earSpread', 'noseW', 'noseH', 'nosePh', 'pupil0']) assert.equal(typeof p[k], 'number', `${id}.${k}`);
    for (const k of ['h', 'bw', 'rot', 'tip']) assert.equal(typeof p.ear[k], 'number', `${id}.ear.${k}`); // ear.cx is optional (default .95)
    for (const k of ['th', 'ph', 'w', 'h', 'round']) assert.equal(typeof p.eye[k], 'number', `${id}.eye.${k}`);
    assert.equal(p.blushAt.length, 2, `${id}: blushAt`);
    if (p.coat === 'calico') assert.ok(Array.isArray(p.patches) && p.patches.length > 0, `${id}: patches`);
    if (p.coat === 'point') assert.ok(p.point && p.earCols, `${id}: point colours`);
    if (p.coat === 'tabby') assert.ok(p.stripe && p.light && p.chinCol, `${id}: tabby colours`);
    if (p.coat === 'tuxedo') assert.ok(p.white, `${id}: white`);
  }
  assert.deepEqual(FROZEN_IDS.filter(id => core.PRESETS[id].ear.fold), ['button']);
  assert.deepEqual(FROZEN_IDS.filter(id => core.PRESETS[id].hairless), ['noodle']);
  assert.deepEqual(FROZEN_IDS.filter(id => core.PRESETS[id].wrinkles), ['noodle']);
});

test('presets.json is the resolved table, kittens included', () => {
  assert.deepEqual(Object.keys(fixture.cats), FROZEN_IDS);
  assert.deepEqual(Object.keys(fixture.kittens), FROZEN_IDS);
  assert.deepEqual(fixture.cats.momo, JSON.parse(JSON.stringify(core.PRESETS.momo)));
  assert.equal(fixture.kittens.shrimpy.kitten, true);
  assert.equal(fixture.kittens.shrimpy.n, 2.05);
  assert.equal(fixture.cats.shrimpy.kitten, undefined);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test tests/cat/presets.test.mjs`
Expected: FAIL (it cannot read `tests/fixtures/cat/presets.json`, and `core.CAT_IDS` doesn't exist).

- [ ] **Step 3: Add the presets section to the core**

Insert the block below into `design/prototype/cat-core.js`, immediately above the line containing `@@END-OF-CORE`:

```js
// ── Presets (from the approved reference board, units of R) ──────────────────
// Cat IDs are frozen contract values (they are stored in settings), in this order:
// shrimpy, momo, ginger, midnight, latte, patches, blue, snow, oreo, mocha, silver, cloud,
// leo, button, puff, noodle. `voice` is a pitch offset in semitones for sub-project C:
// Shrimpy -1, Momo +1, the extra coats 0, every kitten +3.
const PRESETS={
 momo:{name:'momo',label:'Momo',voice:1,coat:'tuxedo',rx:1.12,ry:.9,n:2.2,fluff:0,ruff:null,
  furOpts:{n:700,l0:.025,l1:.03,w:.008,dark:'rgba(24,24,27,.45)',light:'rgba(112,114,122,.42)',wDark:'rgba(196,190,184,.55)',wLight:'rgba(255,255,255,.5)'},
  earSpread:.8,ear:{h:.8,bw:.56,rot:.5,tip:.09,tuft:0,cx:.62},
  top:'#3D3D41',bot:'#3D3D41',rimLight:1,white:'#F6F4F1',inner:'#B98288',nose:'#E89AA6',noseLine:'#B86F7C',noseW:.25,noseH:.15,nosePh:-.48,
  iris:['#7E8A45','#D1B85F'],lidTint:'#D9BE62',liner:'#16171A',ink:'#E4D592',mouthLine:'#9A8C88',whisk:'#F6F4F1',padDot:'rgba(150,142,138,.6)',
  whisk2:{rows:3,cols:2,x0:.17,dx:.065,y0:-.01,dy:.06,slope:.02,dot:.014,wcols:[0,1],a0:-.1,da:.2,len:1.32,dl:.1,droop:.1,w:.021,alpha:.95,brow:2},
  eye:{th:.43,ph:-.02,w:.19,h:.17,round:1},pupil0:.235,blushAt:[.5,.32],paw:'#F6F4F1',bean:'#E89AA6',hair:'#56575E',hairDark:'#2E2F33',hairLight:'#9A9BA2'},
 shrimpy:{name:'shrimpy',label:'Shrimpy',voice:-1,coat:'tabby',rx:1.16,ry:.92,n:2.2,fluff:1,
  ruff:{rx:1.3,ry:.97,dy:.2,col:['#B49C7A','#7E6750']},bib:'#F3EEE6',
  furOpts:{n:420,l0:.04,l1:.05,w:.01,dark:'rgba(60,46,36,.28)',light:'rgba(214,190,150,.32)'},
  earSpread:.8,ear:{h:.8,bw:.4,rot:.44,tip:.1,tuft:1},
  top:'#A08A70',bot:'#6E5B49',light:'#D9B68A',chinCol:'#E6D0AD',stripe:'#2E241D',inner:'#DCC39A',nose:'#C07A62',noseLine:'#5E3526',noseW:.19,noseH:.12,nosePh:-.36,
  iris:['#C9D18A','#6F8445'],liner:'#231A14',ink:'#231A14',mouthLine:'#5E3526',whisk:'#F7F3EC',padDot:'#2E241D',
  whisk2:{rows:3,cols:3,x0:.14,dx:.065,y0:-.01,dy:.065,slope:.022,dot:.017,wcols:[1,2],a0:-.14,da:.2,len:1.45,dl:.12,droop:.12,w:.022,alpha:.95,brow:3},
  eye:{th:.42,ph:-.02,w:.21,h:.16,round:0},pupil0:.08,blushAt:[.6,.22],paw:'#B89C78',bean:'#6B3B2C',hair:'#9A8064',hairDark:'#5A4634',hairLight:'#D2B791'}};

/** Shorthair template for the extra coats; each cat only overrides what differs. */
function makeCat(o){const base={voice:0,coat:'solid',rx:1.12,ry:.9,n:2.2,fluff:0,ruff:null,earSpread:.8,ear:{h:.8,bw:.5,rot:.46,tip:.09,tuft:0,cx:.7},noseW:.2,noseH:.13,nosePh:-.42,
 whisk2:{rows:3,cols:2,x0:.16,dx:.065,y0:-.01,dy:.06,slope:.02,dot:.014,wcols:[0,1],a0:-.1,da:.2,len:1.32,dl:.1,droop:.1,w:.021,alpha:.95,brow:2},
 eye:{th:.43,ph:-.02,w:.19,h:.17,round:1},pupil0:.2,blushAt:[.55,.25]};
 const r={...base,...o};r.ear={...base.ear,...(o.ear||{})};r.eye={...base.eye,...(o.eye||{})};r.whisk2={...base.whisk2,...(o.whisk2||{})};return r}
Object.assign(PRESETS,{
 ginger:makeCat({name:'ginger',label:'Ginger',desc:'orange tabby',coat:'tabby',top:'#E39B52',bot:'#C46F2E',light:'#F7DDB8',chinCol:'#FCEFDD',stripe:'#A9541C',inner:'#F2B8A8',
  nose:'#E88E80',noseLine:'#A85A4E',iris:['#E9D27A','#C99A2E'],liner:'#3A2416',ink:'#3A2416',mouthLine:'#A0624A',whisk:'#FFF6EA',padDot:'#B7682F',
  eye:{w:.2,h:.16,round:0},pupil0:.1,blushAt:[.58,.22],paw:'#F3C894',bean:'#E88E80',hair:'#D98B45',hairDark:'#9C5524',hairLight:'#F6CF9E'}),
 midnight:makeCat({name:'midnight',label:'Midnight',desc:'black shorthair',top:'#2C2C31',bot:'#1F1F23',rimLight:1,inner:'#6E5A5E',nose:'#56474D',noseLine:'#2A2024',
  iris:['#F7D45C','#D9921C'],liner:'#0E0E10',ink:'#F2D06A',mouthLine:'#77696E',whisk:'#D8D8DD',padDot:'rgba(140,140,150,.5)',eye:{w:.2,h:.18},
  paw:'#2E2E33',bean:'#56474D',hair:'#38383E',hairDark:'#1A1A1D',hairLight:'#6A6A72'}),
 latte:makeCat({name:'latte',label:'Latte',desc:'Siamese seal point',coat:'point',rx:1.04,ry:.92,n:2,top:'#F1E6D4',bot:'#DCCBB2',point:'#4A3528',earCols:['#4A3528','#4A3528'],
  ear:{h:.95,bw:.55,rot:.5,tip:.08},inner:'#7A5A4E',nose:'#3E2C24',noseLine:'#2A1C16',iris:['#B9E3FA','#3F86CF'],liner:'#2A1C16',ink:'#CFE6F5',mouthLine:'#8A7266',
  whisk:'#F5EFE6',padDot:'rgba(30,20,15,.5)',eye:{w:.21,h:.15,round:0},pupil0:.1,paw:'#4A3528',bean:'#7A5A50',hair:'#D8C6AC',hairDark:'#8A7058',hairLight:'#F4EADA'}),
 patches:makeCat({name:'patches',label:'Patches',desc:'calico',coat:'calico',top:'#F7F3EE',bot:'#E6DFD6',earCols:['#E3994E','#2C2B2F'],
  patches:[[-.48,-.36,.5,.4,.3,'#E3994E',1],[.52,-.56,.55,.36,-.4,'#2C2B2F',2],[.66,.3,.22,.15,.2,'#E3994E',3],[-.78,.36,.16,.12,-.3,'#2C2B2F',4]],
  inner:'#F2B6B8',nose:'#F0A0AE',noseLine:'#C07884',iris:['#C9DA7A','#6F9A3A'],liner:'#2A2420',ink:'#2A2420',mouthLine:'#B09A94',whisk:'#CFC8C0',padDot:'rgba(170,150,140,.55)',
  paw:'#F7F3EE',bean:'#F0A0AE',hair:'#D9B48C',hairDark:'#8A6A4A',hairLight:'#F4E6D4'}),
 blue:makeCat({name:'blue',label:'Blue',desc:'British shorthair',rx:1.22,ry:.92,n:2.5,top:'#9AA4B2',bot:'#7A8494',muzzle:'#A9B2BF',ear:{h:.62,bw:.5,rot:.55,tip:.12,cx:.8},
  inner:'#B8A0A8',nose:'#6E6C7A',noseLine:'#4C4A56',noseW:.17,nosePh:-.4,iris:['#F6B44A','#D2741E'],liner:'#2E3038',ink:'#2E3038',mouthLine:'#5A5C68',whisk:'#EEF0F4',
  padDot:'rgba(70,76,90,.45)',eye:{w:.21,h:.19},pupil0:.22,paw:'#9AA4B2',bean:'#6E6C7A',hair:'#8E98A6',hairDark:'#5E6878',hairLight:'#C2CAD4'}),
 snow:makeCat({name:'snow',label:'Snow',desc:'white longhair, odd-eyed',fluff:1,ruff:{rx:1.24,ry:.92,dy:.16,col:['#F2EFEA','#D9D3CA']},bib:'#FFFFFF',top:'#F5F3EF',bot:'#E2DED7',
  ear:{h:.82,bw:.48,tuft:1},inner:'#F4B8BE',nose:'#F2A6B0',noseLine:'#C9808C',iris:['#BCE4FA','#4A90D6'],irisR:['#F4DC7A','#D49A2A'],liner:'#3A3433',ink:'#3A3433',
  mouthLine:'#C0B4B0',whisk:'#D8D2CC',padDot:'rgba(180,165,160,.55)',paw:'#F5F3EF',bean:'#F2A6B0',hair:'#EDE8E0',hairDark:'#B8B0A6',hairLight:'#FFFFFF'}),
 oreo:makeCat({name:'oreo',label:'Oreo',desc:'black-and-white tuxedo',coat:'tuxedo',top:'#1C1C1F',bot:'#131315',rimLight:1,white:'#F6F4F1',
  furOpts:{n:700,l0:.025,l1:.03,w:.008,dark:'rgba(0,0,0,.5)',light:'rgba(96,98,108,.42)',wDark:'rgba(196,190,184,.55)',wLight:'rgba(255,255,255,.5)'},
  ear:{h:.86,bw:.54,rot:.46,tip:.08,cx:.66},inner:'#8A646C',nose:'#F2A4B2',noseLine:'#C27886',noseW:.22,noseH:.14,nosePh:-.46,
  iris:['#7FA82A','#DDEB5A'],liner:'#0B0B0D',ink:'#D8EE5E',mouthLine:'#A39A98',whisk:'#FFFFFF',padDot:'rgba(150,142,138,.6)',
  whisk2:{x0:.17,len:1.4},eye:{w:.2,h:.18},pupil0:.22,paw:'#F6F4F1',bean:'#F2A4B2',hair:'#2A2A2E',hairDark:'#101012',hairLight:'#F2F0EC'}),
 mocha:makeCat({name:'mocha',label:'Mocha',desc:'tortoiseshell',coat:'calico',top:'#30241F',bot:'#1F1713',rimLight:1,earCols:['#C9772F','#30241F'],
  patches:[[-.52,-.5,.17,.11,.6,'#C9772F',1],[-.4,-.62,.07,.05,.2,'#E2A866',2],[.06,-.62,.06,.2,.1,'#C9772F',3],[.56,-.3,.15,.09,-.5,'#C9772F',4],[.84,.12,.11,.08,.4,'#E2A866',5],
   [-.82,.16,.14,.1,-.5,'#C9772F',6],[-.32,.6,.13,.07,.25,'#E2A866',7],[.4,.58,.11,.07,-.3,'#C9772F',8],[.36,-.74,.09,.05,.3,'#E2A866',9],[-.66,.42,.07,.05,0,'#E2A866',10]],
  inner:'#7A5A54',nose:'#6E4A42',noseLine:'#3A2420',iris:['#F6C44C','#C2761A'],liner:'#120C0A',ink:'#F2C45C',mouthLine:'#8A6E64',whisk:'#EADFD0',padDot:'rgba(150,120,100,.5)',
  eye:{w:.2,h:.17},paw:'#6A4630',bean:'#2A1C18',hair:'#6A4A34',hairDark:'#2A1F1A',hairLight:'#D89A58'}),
 silver:makeCat({name:'silver',label:'Silver',desc:'silver tabby',coat:'tabby',top:'#D6DADF',bot:'#A8AEB6',light:'#EEF0F2',chinCol:'#FFFFFF',stripe:'#1D1F23',inner:'#E6BDB8',
  nose:'#C2655C',noseLine:'#7C3832',iris:['#CBE27A','#4C983C'],liner:'#16171A',ink:'#1D1F23',mouthLine:'#6E6A6C',whisk:'#FFFFFF',padDot:'#2A2C30',
  eye:{w:.2,h:.16,round:0},pupil0:.1,blushAt:[.58,.22],paw:'#D6DADF',bean:'#C2655C',hair:'#BCC1C8',hairDark:'#3A3C42',hairLight:'#F2F4F6'}),
 cloud:makeCat({name:'cloud',label:'Cloud',desc:'Ragdoll',coat:'point',fluff:1,ruff:{rx:1.3,ry:.98,dy:.2,col:['#F7F2E9','#DED4C4']},bib:'#FFFFFF',rx:1.14,ry:.92,n:2.3,
  top:'#F4EFE6',bot:'#DCD3C6',point:'#7D8796',earCols:['#7D8796','#7D8796'],muzzle:'#FBF9F6',ear:{h:.84,bw:.5,tuft:1},inner:'#C4A8AE',nose:'#D49AA4',noseLine:'#A0707A',
  iris:['#6FA8F2','#2C64D6'],liner:'#232A36',ink:'#8FC0F8',mouthLine:'#A89CA0',whisk:'#FFFFFF',padDot:'rgba(110,116,130,.45)',eye:{w:.22,h:.2},pupil0:.22,
  paw:'#FFFFFF',bean:'#D49AA4',hair:'#E8E2D8',hairDark:'#8A92A0',hairLight:'#FFFFFF'}),
 leo:makeCat({name:'leo',label:'Leo',desc:'Bengal',coat:'calico',top:'#D9A050',bot:'#B97A30',muzzle:'#F4E2C0',ear:{h:.74,bw:.5,rot:.5,tip:.1,cx:.75},
  patches:[[-.1,-.6,.024,.17,.14,'#3E2412',11],[.1,-.6,.024,.17,-.14,'#3E2412',12],[0,-.7,.022,.12,0,'#3E2412',13],[-.84,.1,.15,.022,-.3,'#3E2412',14],[.84,.1,.15,.022,.3,'#3E2412',15],
   ...[[-.6,-.42,.4,1],[.62,-.4,-.3,2],[-.34,-.76,.2,3],[.36,-.76,-.2,4],[-.84,.36,.3,5],[.86,.36,-.3,6],[-.55,.6,.2,7],[.57,.6,-.2,8]].flatMap(([x,y,r,sd])=>[[x,y,.12,.095,r,'#4A2A14',sd],[x,y,.06,.045,r,'#9C5E24',sd]])],
  inner:'#E2B49A',nose:'#C66E58',noseLine:'#7A3A28',iris:['#DADC62','#6C9A32'],liner:'#24160C',ink:'#24160C',mouthLine:'#7A5034',whisk:'#FFF6E6',padDot:'#3A2412',
  eye:{w:.2,h:.15,round:0},pupil0:.1,blushAt:[.58,.24],paw:'#E2B470',bean:'#4A2C18',hair:'#D09048',hairDark:'#4A2C16',hairLight:'#F2D29A'}),
 button:makeCat({name:'button',label:'Button',desc:'Scottish Fold',rx:1.2,ry:.94,n:2.5,top:'#BCA9B3',bot:'#988592',ear:{h:.58,bw:.46,rot:.62,tip:.2,cx:.9,fold:1},
  inner:'#C9A4AC',nose:'#B88A96',noseLine:'#7E5A66',noseW:.17,iris:['#F8A642','#C2561A'],liner:'#2E2630',ink:'#2E2630',mouthLine:'#6E6068',whisk:'#F4EEF0',
  padDot:'rgba(90,70,80,.4)',eye:{w:.22,h:.21},pupil0:.24,paw:'#BCA9B3',bean:'#B88A96',hair:'#ADA0A6',hairDark:'#7A6C74',hairLight:'#D8CED2'}),
 puff:makeCat({name:'puff',label:'Puff',desc:'Persian',fluff:1,ruff:{rx:1.46,ry:1.08,dy:.2,col:['#F3E4C8','#D8C09A']},bib:'#FFFFFF',rx:1.24,ry:.94,n:2.6,
  top:'#EED8B4',bot:'#D4B488',earSpread:.86,ear:{h:.5,bw:.42,rot:.62,tip:.12,cx:.8,tuft:1},nosePh:-.3,noseW:.15,noseH:.1,
  inner:'#F0B8B0',nose:'#E89A94',noseLine:'#B06A64',iris:['#F8B04A','#C8601A'],liner:'#3A2A20',ink:'#3A2A20',mouthLine:'#A88A78',whisk:'#FFF8EE',padDot:'rgba(170,140,110,.5)',
  whisk2:{len:1.2},eye:{th:.45,w:.22,h:.21},pupil0:.24,paw:'#F3E4C8',bean:'#E89A94',hair:'#EAD6B4',hairDark:'#B89A70',hairLight:'#FFF6E6'}),
 noodle:makeCat({name:'noodle',label:'Noodle',desc:'Sphynx',hairless:1,wrinkles:1,rx:1.04,ry:.94,n:2,top:'#E8C1AE',bot:'#CF9F8C',earSpread:.86,ear:{h:1.1,bw:.62,rot:.58,tip:.1,cx:.75},
  inner:'#EBA898',nose:'#D88A7C',noseLine:'#A45E50',iris:['#F6F07A','#C9C42E'],liner:'#3A2620',ink:'#3A2620',mouthLine:'#A87464',whisk:'#F4E2D8',padDot:'rgba(170,110,95,.4)',
  whisk2:{wcols:[1],len:.85,alpha:.5,brow:1},eye:{w:.21,h:.15,round:0},pupil0:.1,paw:'#E8C1AE',bean:'#D88A7C',hair:'#E0B6A2',hairDark:'#A87A66',hairLight:'#F6DED2'})});
const MORE=['ginger','midnight','latte','patches','blue','snow','oreo','mocha','silver','cloud','leo','button','puff','noodle'];

/** Kittens keep the parent's coat; rounder head, bigger eyes and ears, shorter muzzle. */
function kittenOf(p){const k=JSON.parse(JSON.stringify(p));k.kitten=true;k.base=p.name;k.label=p.label+' kitten';k.voice=3;
 k.rx=p.rx*.97;k.ry=p.ry*1.02;k.n=2.05;k.ear.h*=1.12;k.ear.bw*=1.06;k.ear.tuft=0;
 k.eye.w*=1.2;k.eye.h*=1.32;k.eye.round=1;k.eye.th+=.02;k.pupil0=Math.max(p.pupil0,.18);
 k.nosePh=p.nosePh+.08;k.noseW*=.85;k.noseH*=.85;k.whisk2.len*=.7;k.whisk2.brow=1;
 if(k.ruff){k.ruff.rx*=.94;k.ruff.ry*=.92}return k}

const CAT_IDS=['shrimpy','momo',...MORE];
/** A stored cat ID to its preset. An unknown ID (or anything that is not a string) falls back to Shrimpy. */
const catById=id=>typeof id==='string'&&own(PRESETS,id)?PRESETS[id]:PRESETS.shrimpy;

Object.assign(api,{PRESETS,MORE,CAT_IDS,makeCat,kittenOf,catById});
```

- [ ] **Step 4: Add the fixture builder**

Insert the block below into `scripts/gen-cat-fixtures.mjs`, immediately above the line containing `@@BUILDERS`:

```js
FILES['presets.json'] = () => ({
  version: 1,
  note: 'Every number is in units of R, the head radius. The IDs and the voice offsets (semitones) are frozen contract values.',
  ids: core.CAT_IDS,
  cats: Object.fromEntries(core.CAT_IDS.map(id => [id, core.PRESETS[id]])),
  kittens: Object.fromEntries(core.CAT_IDS.map(id => [id, core.kittenOf(core.PRESETS[id])])),
});
```

- [ ] **Step 5: Write the fixture and run everything**

Run: `node scripts/gen-cat-fixtures.mjs && bash scripts/test-cat-contract.sh`
Expected: `wrote 1 fixture files to tests/fixtures/cat`, then `# tests 18`, `# pass 18`, `# fail 0`, `✓ presets.json`, `✓ 1 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 6: One-off check against the prototype (not committed)**

The presets were moved, so prove they are the same numbers. This runs the prototype's own `PRESETS` and `kittenOf` text from git next to the core.

```bash
T=${TMPDIR:-/tmp}/a0-check; mkdir -p "$T"
git show 683163f:design/prototype/notchmeow.html > "$T/old.html"
cat > "$T/equiv-presets.mjs" <<'EOF'
// One-off, not committed: the presets and kittens in cat-core.js against the pre-A-0 prototype, run in Node.
// Usage: node equiv-presets.mjs <cat-core.js> <old notchmeow.html>
import fs from 'node:fs'; import vm from 'node:vm'; import assert from 'node:assert/strict'; import { createRequire } from 'node:module';
const require = createRequire(import.meta.url), core = require(process.argv[2]);
const old = vm.runInNewContext(fs.readFileSync(process.argv[3], 'utf8').split('\n').slice(132, 214).join('\n') + '\n;({PRESETS,kittenOf})');
const renamed = { siamese: 'latte', calico: 'patches', ragdoll: 'cloud', bengal: 'leo', fold: 'button', persian: 'puff', sphynx: 'noodle' };
const plain = p => { const q = JSON.parse(JSON.stringify(p)); delete q.voice; return q; };
let n = 0;
for (const [key, p] of Object.entries(old.PRESETS)) {
  const id = renamed[key] || key, was = plain(p), kitten = plain(old.kittenOf(p));
  was.name = id; kitten.name = id; kitten.base = id;                 // only the ID changed
  assert.deepEqual(plain(core.PRESETS[id]), was, id);
  assert.deepEqual(plain(core.kittenOf(core.PRESETS[id])), kitten, `${id} kitten`);
  n += 2;
}
console.log(`presets: ${n} comparisons identical to the prototype, apart from the renamed IDs and the new voice field`);
EOF
node "$T/equiv-presets.mjs" "$PWD/design/prototype/cat-core.js" "$T/old.html"
```

Expected: `presets: 32 comparisons identical to the prototype, apart from the renamed IDs and the new voice field`.

- [ ] **Step 7: Commit**

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/presets.test.mjs tests/fixtures/cat/presets.json
git commit -m "feat(cat): presets, kittens and the frozen cat IDs in cat-core.js

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Geometry and the face warp

**Files:**
- Modify: `design/prototype/cat-core.js` (insert a section above `@@END-OF-CORE`)
- Modify: `scripts/gen-cat-fixtures.mjs` (insert two builders above `@@BUILDERS`)
- Create: `tests/cat/geometry.test.mjs`
- Create: `tests/fixtures/cat/geometry-cases.json`, `tests/fixtures/cat/warp-cases.json` (generated)

**Interfaces:**
- Consumes: `TAU`, `lerp`, `clamp`, `wrapA` from Task 1; `PRESETS`, `CAT_IDS`, `kittenOf` from Task 2 (in tests and builders).
- Produces: `newPose()` (the neutral pose: 29 animatable properties at rest), `FACE` (the warp constants), `DETAIL_FULL_MIN` (28), `detailOf(D)` (`'full'` or `'compact'`), `COMPACT_EAR_SCALE` (0.8) and `earScale(D)`, `outlineSteps(R)` (72 under R = 20, else 200), `badgeSide(compactNotch)` (1 or -1), `CURSOR` and `cursorLook(dx, dy)` (`{x, y}`), `pupilOffset(yaw, pitch, w, h)` (`[x, y]`), `faceAngles(pose)` (`{yf, pf, pt, fa}`), `supPoints(rx, ry, n, dy, spike, count, steps, bend)` (a list of `[x, y]`), `mkWarp(preset, yf, pt, R)` (a function `(x, y) => [X, Y]`), `flatten(commands)`, `MOMO_WHITE` (points), `earGeom(preset, pose, sd, R, yf, pf, earScale)`, `layout(preset, pose, cx, cy, D, opts)` and `PASSES`.
- `layout` returns `{R, D, full, rx, ry, base, at, head, yf, pf, pt, fa, W, steps, bend, ruff, eyes[2], nose, mouth, ears[2], badge}`. Positions are px; `eyes`, `nose` and `ears` are head-local (relative to the head centre, before tilt and squash); `mouth` is in world px, or null while the nose is turned out of sight; `W` maps flat-view R-units to head-local px. Options: `T` (seconds, for the purr shake), `detail`, `badgeSide`, `earScale` (default 1).
- Produces: `geometry-cases.json` `{detail, earScale, outline[9], anchors[30], passes}` and `warp-cases.json` `{face, cursor, angles[24], pupil[8], warp[32], eyes[24], head[16]}`.

`supPoints`, `mkWarp`, `flatten` and `MOMO_WHITE` are the prototype's `sup`, `mkWarp`, `flatten` and `MOMO_WHITE` (lines 226 to 254), moved as written; `sup` now returns points and the page builds the `Path2D` (Task 7). `layout` collects the numbers `drawCat` computed inline, in the same order and with the same formulas, so the page draws the same pixels.

The compact ear scale is new, and provisional. The spec says ears are scaled down at Ø20 and gives no number, so the constant is 0.8 at Ø20 and below, easing to 1 at Ø28. It is a named constant, and `docs/CAT-CONTRACT.md` says so. The page does not apply it yet.

- [ ] **Step 1: Write the failing tests**

Create `tests/cat/geometry.test.mjs`:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const core = require('../../design/prototype/cat-core.js');
const load = name => JSON.parse(fs.readFileSync(new URL(`../fixtures/cat/${name}`, import.meta.url), 'utf8'));
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const finite = (v, at = '$') => {
  if (typeof v === 'number') assert.ok(Number.isFinite(v), `${at} is ${v}`);
  else if (typeof v === 'function') return;
  else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) finite(x, `${at}.${k}`);
};
const pose = (o = {}) => ({ ...core.newPose(), ...o });

test('the detail switch is at head width 28', () => {
  assert.equal(core.DETAIL_FULL_MIN, 28);
  assert.deepEqual([12, 20, 27.999, 28, 28.001, 66].map(core.detailOf), ['compact', 'compact', 'compact', 'full', 'full', 'full']);
  const p = core.PRESETS.momo;
  assert.equal(core.layout(p, pose(), 0, 0, 27.9).full, false);
  assert.equal(core.layout(p, pose(), 0, 0, 28).full, true);
  assert.equal(core.layout(p, pose(), 0, 0, 66, { detail: 'compact' }).full, false, 'an explicit detail wins');
  assert.equal(core.layout(p, pose(), 0, 0, 12, { detail: 'full' }).full, true);
  assert.equal(core.outlineSteps(19.9), 72);
  assert.equal(core.outlineSteps(20), 200);
});

test('compact ears: 1 from Ø28 up, easing to 0.8 at Ø20 and below, never jumping', () => {
  assert.equal(core.COMPACT_EAR_SCALE, .8);
  for (const D of [28, 44, 66]) assert.equal(core.earScale(D), 1);
  for (const D of [0, 12, 16, 20]) near(core.earScale(D), .8);
  let prev = 0;
  for (let D = 20; D <= 28; D += .5) { const k = core.earScale(D); assert.ok(k >= prev && k <= 1); prev = k; }
  near(core.earScale(27.999), 1, 1e-3);
  const p = core.PRESETS.shrimpy, full = core.layout(p, pose(), 0, 0, 20).ears[1], small = core.layout(p, pose(), 0, 0, 20, { earScale: core.earScale(20) }).ears[1];
  near(small.h, full.h * .8); near(small.bw, full.bw * .8); near(small.tip, full.tip * .8); near(small.bx, full.bx); near(small.by, full.by);
});

test('supPoints: a closed superellipse, and a fluffy edge that is fixed, not random', () => {
  const a = core.supPoints(1.12, .9, 2.2, 0, 0, 14, 200), b = core.supPoints(1.12, .9, 2.2, 0, 0, 14, 200);
  assert.equal(a.length, 201);
  assert.deepEqual(a, b);
  near(a[0][0], a[200][0]); near(a[0][1], a[200][1], 1e-9);
  for (const [x, y] of a) near(Math.pow(Math.abs(x / 1.12), 2.2) + Math.pow(Math.abs(y / .9), 2.2), 1, 1e-9);
  near(Math.max(...a.map(q => q[0])), 1.12); near(Math.max(...a.map(q => q[1])), .9);
  const fluff = core.supPoints(1.16, .92, 2.2, 0, .035, 14, 200);
  assert.deepEqual(fluff, core.supPoints(1.16, .92, 2.2, 0, .035, 14, 200));
  const k = q => Math.pow(Math.pow(Math.abs(q[0] / 1.16), 2.2) + Math.pow(Math.abs(q[1] / .92), 2.2), 1 / 2.2); // 1 on the plain superellipse
  const lower = fluff.filter(q => q[1] > 0), upper = fluff.filter(q => q[1] < -.6 * .92);
  assert.ok(Math.max(...lower.map(k)) > 1.01, 'the lower edge is fluffy');
  assert.ok(Math.max(...lower.map(k)) <= 1.035 + 1e-9, 'and never more than the spike amount');
  upper.forEach(q => near(k(q), 1));
  const ruff = core.supPoints(1.3, .97, 2.4, .2, .06, 18, 72);
  assert.equal(ruff.length, 73);
  assert.ok(Math.max(...ruff.map(q => q[1])) > .97 + .2, 'the ruff sits lower by dy and spikes past it');
  const bent = core.supPoints(1.12, .9, 2.2, 0, 0, 14, 200, [.05, -.02]);
  near(Math.max(...bent.map(q => q[0])), 1.12 * 1.05, 1e-3); // the widest point leans out by bend[0] of rx
});

test('mkWarp is the identity at rest and keeps points outside the head where they are', () => {
  const p = core.PRESETS.momo, R = 30, W = core.mkWarp(p, 0, 0, R);
  for (const [x, y] of [[0, 0], [.3, -.5], [-.7, .2], [1.3, .9], [0, -.6]]) assert.deepEqual(W(x, y), [x * R, y * R]);
  const T = core.mkWarp(p, .5, .2, R);
  assert.deepEqual(T(1.3, .9), [1.3 * R, .9 * R], 'outside the outline: untouched');
  assert.ok(T(0, 0)[0] > 0, 'a positive yaw turns the face toward +x');
  assert.ok(core.mkWarp(p, -.5, 0, R)(0, 0)[0] < 0);
  assert.ok(T(0, -.3)[1] < core.mkWarp(p, .5, 0, R)(0, -.3)[1], 'looking up lifts the face');
});

test('the muzzle stands proud of the head, so the nose swings further than a cheek', () => {
  assert.equal(core.FACE.muzzle, .12);
  const p = core.PRESETS.shrimpy, yaw = .5, W = core.mkWarp(p, yaw, 0, 1);
  const noseY = -Math.sin(p.nosePh) * p.ry, v = -noseY / p.ry, q = 1 - v * v, vm = Math.sin(p.nosePh) - .12;
  const flat = Math.sqrt(q) * Math.sin(yaw) * p.rx, dv = (v - vm) / .45;
  near(W(0, noseY)[0] - flat, core.FACE.muzzle * Math.exp(-dv * dv) * Math.sin(yaw) * p.rx);
  assert.ok(W(0, noseY)[0] > flat);
});

test('faceAngles: the face takes 82 % of the yaw, looking up 60 % of the pitch and down only 32 %', () => {
  const a = core.faceAngles(pose({ yaw: .62, pitch: .5 })), d = core.faceAngles(pose({ pitch: -.5 }));
  near(a.yf, .62 * .82); near(a.pf, .5 * .6); near(d.pf, -.5 * .32);
  near(core.faceAngles(pose({ roll: Math.PI })).pt, -Math.PI);
  assert.equal(core.faceAngles(pose()).fa, 1);
  assert.equal(core.faceAngles(pose({ roll: Math.PI })).fa, 0);
  near(core.faceAngles(pose({ lift: .28 })).pt, .28);
});

test('the cursor curve is tanh over 240 px across and 180 px up and down', () => {
  assert.deepEqual(core.CURSOR, { x: 240, y: 180 });
  near(core.cursorLook(240, 0).x, Math.tanh(1)); near(core.cursorLook(0, 180).y, -Math.tanh(1));
  near(core.cursorLook(-480, 0).x, -Math.tanh(2));
  near(core.cursorLook(0, 0).x, 0); near(core.cursorLook(0, 0).y, 0);
  near(core.cursorLook(1e6, -1e6).x, 1); near(core.cursorLook(1e6, -1e6).y, 1);
  assert.ok(core.cursorLook(0, 100).y < 0, 'a cursor below the cat looks down (negative)');
});

test('the pupils travel up to 0.24 of the eye width and 0.18 of its height', () => {
  assert.deepEqual(core.pupilOffset(0, 0, 10, 8).map(v => v + 0), [0, 0]);
  near(core.pupilOffset(.62, 0, 10, 8)[0], 2.4); near(core.pupilOffset(5, 0, 10, 8)[0], 2.4); near(core.pupilOffset(-5, 0, 10, 8)[0], -2.4);
  near(core.pupilOffset(0, .5, 10, 8)[1], -1.44); near(core.pupilOffset(0, -9, 10, 8)[1], 1.44);
});

test('layout at rest: the cat is where you put it, the eyes, ears, nose and badge sit where the board says', () => {
  for (const id of core.CAT_IDS) {
    const p = core.PRESETS[id], D = 66, R = D / (2 * p.rx), L = core.layout(p, pose({ badgeS: 1 }), 100, 50, D);
    near(L.R, R); assert.equal(L.full, true); assert.equal(L.steps, 200);
    assert.deepEqual(L.base, { x: 100, y: 50, R }); assert.deepEqual(L.at, { x: 100, y: 50, R, D }); assert.deepEqual(L.head, { x: 100, y: 50 });
    assert.equal(L.fa, 1);
    for (const e of L.eyes) {
      assert.equal(e.visible, true); near(e.fx, 1); near(e.fy, 1);
      near(e.x, e.sd * Math.sin(p.eye.th) * Math.cos(p.eye.ph) * p.rx * R); near(e.y, -Math.sin(p.eye.ph) * p.ry * R);
    }
    assert.equal(L.nose.visible, true); near(L.nose.nx, 0); near(L.nose.nf, 1); near(L.nose.ny, -Math.sin(p.nosePh) * p.ry * R);
    near(L.mouth.x, 100); near(L.mouth.y, 50 + (L.nose.my + .12 * R));
    const [l, r] = L.ears; assert.equal(l.sd, -1); assert.equal(r.sd, 1);
    near(l.bx, -r.bx); near(l.by, r.by); near(l.rot, -r.rot); near(l.h, r.h);
    near(r.h, p.ear.h * R); near(r.bw, p.ear.bw * R * Math.cos(.6)); near(r.bx, Math.sin(.6) * p.earSpread * p.rx * R);
    near(L.badge.x, 100 + 1.4 * R); near(L.badge.y, 50 - .92 * R); assert.equal(L.badge.k, 1);
  }
});

test('the badge: right of the head, left in the compact notch, scaled up a little when compact', () => {
  assert.equal(core.badgeSide(false), 1); assert.equal(core.badgeSide(true), -1);
  const p = core.PRESETS.momo, s = pose({ badgeS: 1, sx: 1.1, sy: .9 });
  const R = L => L.R, right = core.layout(p, s, 0, 0, 66), left = core.layout(p, s, 0, 0, 20, { badgeSide: core.badgeSide(true) });
  near(right.badge.x, 1.4 * R(right) * 1.1); near(right.badge.y, -.92 * R(right) * .9); assert.equal(right.badge.k, 1);
  near(left.badge.x, -1.4 * R(left) * 1.1); assert.equal(left.badge.side, -1); assert.equal(left.badge.k, 1.25); assert.equal(left.badge.small, true);
});

test('turning the head leans the outline, shifts the head toward the cursor and moves the nose', () => {
  const p = core.PRESETS.shrimpy, R = 66 / (2 * p.rx), L = core.layout(p, pose({ yaw: .62 }), 0, 0, 66);
  near(L.head.x, Math.sin(.62) * .08 * R); near(L.head.y, 0);
  near(L.bend[0], Math.sin(.62 * .82) * .1); near(L.ruff.dx, -Math.sin(.62) * .08 * 1.1 * R);
  const rest = core.layout(p, pose(), 0, 0, 66);
  assert.ok(L.nose.nx > rest.nose.nx && L.mouth.x > rest.mouth.x);
  const up = core.layout(p, pose({ pitch: .5 }), 0, 0, 66);
  assert.ok(up.head.y < 0, 'looking up lifts the head centre');
});

test('the near eye never foreshortens below 55 %, and a face turned past the limit hides its far eye', () => {
  const p = core.PRESETS.momo;
  const fx = yaw => core.layout(p, pose({ yaw }), 0, 0, 66).eyes.map(e => e.fx);
  for (const yaw of [0, .31, .62, .9, 1.2, 1.3]) for (const v of fx(yaw)) assert.ok(v >= .55 - 1e-12 && v <= 1.08 + 1e-12, `yaw ${yaw}: ${v}`);
  assert.deepEqual(fx(1.3).map(v => +v.toFixed(6)).includes(.55), true, 'the floor is reached');
  const far = core.layout(p, pose({ yaw: 1.7 }), 0, 0, 66);
  assert.equal(far.eyes[0].visible, true); assert.equal(far.eyes[1].visible, false);
});

test('extreme poses never produce NaN: rolled over the top, turned away, or a head of width 0', () => {
  const p = core.PRESETS.shrimpy;
  const over = core.layout(p, pose({ roll: Math.PI }), 0, 0, 66);
  assert.equal(over.fa, 0); assert.ok(over.eyes.every(e => !e.visible)); assert.equal(over.nose.visible, false); assert.equal(over.mouth, null);
  finite(over);
  const away = core.layout(p, pose({ yaw: 3 }), 0, 0, 66); finite(away);
  assert.ok(away.eyes.every(e => !e.visible) && away.mouth === null);
  const zero = core.layout(p, pose({ badgeS: 1 }), 5, 7, 0); finite(zero);
  assert.equal(zero.R, 0); assert.deepEqual(zero.head, { x: 5, y: 7 });
  for (const id of core.CAT_IDS) finite(core.layout(core.PRESETS[id], pose({ yaw: .62, pitch: .5, roll: 1, tilt: .3, earU: 1.4, earF: 1 }), 0, 0, 12));
});

test('the draw order is split into a behind pass, the head and a front pass', () => {
  const all = [...core.PASSES.behind, ...core.PASSES.head, ...core.PASSES.front];
  assert.equal(new Set(all).size, all.length);
  assert.deepEqual(core.PASSES.behind.slice(-2), ['paws', 'ears']);
  assert.ok(core.PASSES.front.includes('foldEars') && core.PASSES.front.includes('badge'));
});

test('geometry-cases.json: every case replays through layout() from its own inputs', () => {
  const g = load('geometry-cases.json');
  assert.equal(g.version, 1);
  assert.equal(g.detail.fullMinD, 28);
  for (const c of g.detail.cases) assert.equal(core.detailOf(c.D), c.detail);
  for (const c of g.earScale.cases) near(core.earScale(c.D), c.scale);
  for (const c of g.outline) {
    const pts = core.supPoints(c.rx, c.ry, c.n, c.dy, c.spike, c.count, c.steps, c.bend);
    c.indices.forEach((i, k) => { near(pts[i][0], c.points[k][0]); near(pts[i][1], c.points[k][1]); });
  }
  assert.ok(g.anchors.length >= 30);
  for (const c of g.anchors) {
    const base = core.PRESETS[c.cat], p = c.kitten ? core.kittenOf(base) : base;
    const { W, ...L } = core.layout(p, pose(c.pose), c.cx, c.cy, c.D, { T: c.T, earScale: c.earScale, badgeSide: c.badgeSide });
    assert.deepEqual(JSON.parse(JSON.stringify(L)).eyes.map(e => e.visible), c.layout.eyes.map(e => e.visible));
    near(L.badge.x, c.layout.badge.x); near(L.mouth.x, c.layout.mouth.x); near(L.ears[0].h, c.layout.ears[0].h);
  }
  assert.deepEqual(g.passes, core.PASSES);
  assert.ok(g.anchors.some(c => c.D === 20 && c.badgeSide === -1 && c.earScale === .8), 'the compact notch case is there');
});

test('warp-cases.json: the warp, the angles, the pupils and the cursor replay from their inputs', () => {
  const w = load('warp-cases.json');
  assert.deepEqual(w.face, core.FACE);
  assert.deepEqual(w.cursor.px, { x: 240, y: 180 });
  for (const c of w.cursor.cases) { near(core.cursorLook(c.dx, c.dy).x, c.x); near(core.cursorLook(c.dx, c.dy).y, c.y); }
  for (const c of w.angles) { const a = core.faceAngles(pose({ yaw: c.yaw, pitch: c.pitch, lift: c.lift, roll: c.roll })); near(a.yf, c.yf); near(a.pf, c.pf); near(a.pt, c.pt); near(a.fa, c.fa); }
  for (const c of w.pupil) { const o = core.pupilOffset(c.yaw, c.pitch, c.w, c.h); near(o[0], c.offset[0]); near(o[1], c.offset[1]); }
  assert.ok(w.warp.length >= 24);
  for (const c of w.warp) {
    const W = core.mkWarp(core.PRESETS[c.cat], c.yf, c.pt, 1);
    c.probes.forEach((q, i) => { const o = W(q[0], q[1]); near(o[0], c.out[i][0]); near(o[1], c.out[i][1]); });
  }
  assert.ok(w.eyes.some(c => c.eyes.some(e => e.fx === .55)), 'the 55 % floor is in the fixture');
  assert.ok(w.eyes.some(c => c.eyes.some(e => !e.visible)), 'a hidden far eye is in the fixture');
});
```

This file pins Review Focus 4: the test "extreme poses never produce NaN" rolls the head over the top, turns it away and gives it a width of 0.

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test tests/cat/geometry.test.mjs`
Expected: FAIL (`core.newPose is not a function`, and the two fixture files are missing).

- [ ] **Step 3: Add the geometry section to the core**

Insert the block below into `design/prototype/cat-core.js`, immediately above the line containing `@@END-OF-CORE`:

```js
// ── Geometry: outline, face warp, anchors ────────────────────────────────────
/**
 * Head turn toward the cursor. The face is a real 3D rotation of the head ellipsoid,
 * with the muzzle standing proud of it so it swings further than the cheeks, and the
 * head outline leans into the turn. yaw/pitch are the share of upstream's 0.62/0.5 rad
 * gaze the face takes; the pupils carry the rest.
 */
const FACE={yaw:.82,pitch:.6,pitchDown:.32,lean:.08,bend:.1,muzzle:.12,nose:.05};
/** Head width D (px) from which the full cat is drawn; below it the compact drawing (ink eyes, no irises, stripes or whiskers). */
const DETAIL_FULL_MIN=28;
const detailOf=D=>D>=DETAIL_FULL_MIN?'full':'compact';
/**
 * Ear scale for the compact drawing, so the ears keep their headroom in the compact notch:
 * 1 from Ø28 up, easing down to COMPACT_EAR_SCALE at Ø20 and below.
 * PROVISIONAL: the spec only says "ears scaled down at Ø20"; the owner confirms the value on the
 * stage-1 contact sheet. To change it, edit the constant and regenerate the fixtures.
 */
const COMPACT_EAR_SCALE=.8;
const earScale=D=>D>=DETAIL_FULL_MIN?1:lerp(COMPACT_EAR_SCALE,1,clamp((D-20)/(DETAIL_FULL_MIN-20),0,1));
/** Outline sample count: small heads (R under 20 px) use fewer points. */
const outlineSteps=R=>R<20?72:200;
/** The badge sits beside the right ear, and moves to the left in the compact notch so it never sits under the camera housing. */
const badgeSide=compactNotch=>compactNotch?-1:1;
/** Cursor to gaze: how far the cursor is from the cat in px, to -1…1 (tanh over 240 px across, 180 px up and down). */
const CURSOR={x:240,y:180};
const cursorLook=(dx,dy)=>({x:Math.tanh(dx/CURSOR.x),y:-Math.tanh(dy/CURSOR.y)});
/** Pupil travel inside the eye: up to 0.24 of the eye width across and 0.18 of its height up and down. */
const pupilOffset=(yaw,pitch,w,h)=>[clamp(yaw/.62,-1,1)*.24*w,-clamp(pitch/.5,-1,1)*.18*h];
/** The share of the gaze the face takes (FACE) and the roll fade: yf, pf, the warp pitch pt and the face opacity fa. */
function faceAngles(s){const yf=s.yaw*FACE.yaw,pf=s.pitch*(s.pitch>0?FACE.pitch:FACE.pitchDown),pt=wrapA(pf+s.lift+s.roll);return{yf,pf,pt,fa:clamp((Math.cos(pt)-.05)/.3,0,1)}}

/** The neutral pose: every animatable property at rest. The engine's `s` starts here, and layout() reads one. */
const newPose=()=>({yaw:0,pitch:0,roll:0,tilt:0,open:1,sx:1,sy:1,oy:0,ox:0,tint:0,blush:0,es:1,badgeS:0,earL:0,earR:0,earU:1,earF:0,pupil:.45,mouth:0,purr:0,lid:0,lift:0,wh:0,paws:0,smile:0,tongue:0,mround:0,mskew:0,wavy:0});

/**
 * Superellipse outline as points [x, y], optionally with a fluffy edge (spike) on the lower half.
 * The fluff is a fixed sum of sines, so it needs no random numbers and is identical everywhere.
 */
function supPoints(rx,ry,n,dy,spike,count,steps=200,bend=null){const e=2/n,pts=[];
 for(let i=0;i<=steps;i++){const a=i/steps*TAU,c=Math.cos(a),s=Math.sin(a);let k=1;
  if(spike){const low=Math.max(0,s+.55)/1.55,vary=.55+.45*Math.sin(a*5.3+1.1)*Math.sin(a*2.7+.4);k+=low*spike*vary*Math.pow(Math.abs(Math.cos(a*count)),1.8)}
  let x=Math.sign(c)*Math.pow(Math.abs(c),e)*rx*k,y=Math.sign(s)*Math.pow(Math.abs(s),e)*ry*k+dy;
  if(bend){const tx=x/rx,ty=y/ry;x+=bend[0]*rx*Math.max(0,1-ty*ty);y+=bend[1]*ry*Math.max(0,1-tx*tx)}
  pts.push([x,y])}
 return pts}

/**
 * Face warp: maps a point drawn on the flat front view (units of R) onto the head
 * ellipsoid rotated by yaw and pitch, so markings, whisker pads and the muzzle turn with
 * the eyes. Points outside the head outline stay put. Identity at rest, so the rest pose
 * matches the board exactly.
 */
function mkWarp(p,yaw,pt,R){const a=p.rx,b=p.ry,vm=Math.sin(p.nosePh)-.12;
 if(Math.abs(yaw)<1e-4&&Math.abs(pt)<1e-4)return(x,y)=>[x*R,y*R];
 const cY=Math.cos(yaw),sY=Math.sin(yaw),cP=Math.cos(pt),sP=Math.sin(pt);
 return(x,y)=>{const u=x/a,v=-y/b,q=1-u*u-v*v;if(q<=0)return[x*R,y*R];
  const du=u/.55,dv=(v-vm)/.45,w=Math.sqrt(q)+FACE.muzzle*Math.exp(-(du*du+dv*dv)),u1=u*cY+w*sY,w1=w*cY-u*sY,v1=v*cP+w1*sP;
  return[u1*a*R,-v1*b*R]}}

/** Flattens M/Q/L commands (units of R) into a dense point list, so the warp can bend every edge. */
function flatten(cmds){const out=[];let px=0,py=0;
 for(const c of cmds){if(c[0]==='M'){px=c[1];py=c[2];out.push([px,py])}
  else if(c[0]==='Q'){for(let i=1;i<=10;i++){const t=i/10,m=1-t;out.push([m*m*px+2*m*t*c[1]+t*t*c[3],m*m*py+2*m*t*c[2]+t*t*c[4]])}px=c[3];py=c[4]}
  else{for(let i=1;i<=8;i++){const t=i/8;out.push([px+(c[1]-px)*t,py+(c[2]-py)*t])}px=c[1];py=c[2]}}return out}
const MOMO_WHITE=flatten([['M',0,-.6],['Q',-.13,-.4,-.17,-.12],['Q',-.19,.1,-.26,.2],['Q',-.5,.38,-.8,.36],['L',-1.3,.3],['L',-1.3,1.3],['L',1.3,1.3],['L',1.3,.3],['L',.8,.36],['Q',.5,.38,.26,.2],['Q',.19,.1,.17,-.12],['Q',.13,-.4,0,-.6]]);

/** One ear, in head-local px before tilt and squash. `ek` is the compact ear scale (earScale), 1 when not compact. */
function earGeom(p,s,sd,R,yf,pf,ek=1){const E=p.ear,rx=p.rx*R,ry=p.ry*R,th=sd*.6+yf*.85,f=Math.max(.3,Math.cos(th));
 return{bx:Math.sin(th)*p.earSpread*rx+Math.sin(yf)*FACE.bend*.54*rx,by:-.68*ry-Math.sin(pf+s.lift)*.12*ry,
  rot:sd*(E.rot+(sd<0?s.earL:s.earR)+.95*s.earF),h:E.h*R*s.earU*(1-.4*s.earF)*ek,bw:E.bw*R*f*ek,tip:E.tip*R*ek,cx:E.cx||.95}}

/**
 * Everything geometric about one cat in one pose, in px: where the head is, the warp, the eyes, the
 * nose and mouth, the ears, the badge. Drawing code only consumes this.
 *   p preset, s pose (the engine's `s`), cx/cy the cat's resting centre, D the head width.
 *   o.T seconds (for the purr shake), o.detail 'full'|'compact', o.badgeSide 1|-1, o.earScale (default 1).
 * Head-local means relative to the head centre, before the tilt and squash. `mouth` is in world px
 * and null while the nose is turned out of sight. `W` maps flat-view R-units to head-local px.
 */
function layout(p,s,cx,cy,D,o={}){const R=D/(2*p.rx),full=o.detail?o.detail==='full':D>=DETAIL_FULL_MIN,T=o.T||0,ek=o.earScale===undefined?1:o.earScale,rx=p.rx*R,ry=p.ry*R;
 const base={x:cx,y:cy,R},purr=s.purr>.01?Math.sin(T*TAU*24)*.007*s.purr:0;
 cx+=(s.ox+purr)*R;cy+=s.oy*R;const at={x:cx,y:cy,R,D};
 const {yf,pf,pt,fa}=faceAngles(s);
 cx+=Math.sin(s.yaw)*FACE.lean*R;cy-=Math.sin(s.pitch)*FACE.lean*.8*R;
 const W=mkWarp(p,yf,pt,R);
 const eyes=[-1,1].map(sd=>{const th=sd*p.eye.th+yf,cp=Math.cos(p.eye.ph+pt),[x,y]=W(Math.sin(sd*p.eye.th)*Math.cos(p.eye.ph)*p.rx,-Math.sin(p.eye.ph)*p.ry);
  return{sd,visible:Math.cos(th)*cp>.04,x,y,fx:clamp(Math.cos(th)/Math.cos(p.eye.th),.55,1.08),fy:clamp(cp/Math.cos(p.eye.ph),.18,1.08)}});
 let nose={visible:false},mouth=null;
 if(Math.cos(yf)*Math.cos(p.nosePh+pt)>.04){const [nx0,ny0]=W(0,-Math.sin(p.nosePh)*p.ry),nx=nx0+Math.sin(yf)*FACE.nose*R,ny=ny0-Math.sin(pf)*FACE.nose*.8*R,nf=Math.max(.3,Math.cos(yf)),nw=p.noseW*R*nf,nh=p.noseH*R,my=ny+nh/2;
  nose={visible:true,nx,ny,nf,nw,nh,my};
  const lx=nx*s.sx,ly=(my+.12*R)*s.sy,c=Math.cos(s.tilt),sn=Math.sin(s.tilt);mouth={x:cx+lx*c-ly*sn,y:cy+lx*sn+ly*c}}
 const side=o.badgeSide||1;
 return{R,D,full,rx,ry,base,at,head:{x:cx,y:cy},yf,pf,pt,fa,W,steps:outlineSteps(R),
  bend:[Math.sin(yf)*FACE.bend,-Math.sin(pf)*FACE.bend*.7],ruff:{dx:-Math.sin(s.yaw)*FACE.lean*1.1*R,dy:Math.sin(s.pitch)*FACE.lean*.9*R},
  eyes,nose,mouth,ears:[-1,1].map(sd=>({sd,...earGeom(p,s,sd,R,yf,pf,ek)})),
  badge:{x:cx+side*1.4*R*s.sx,y:cy-.92*R*s.sy,k:s.badgeS*(full?1:1.25),small:!full,side}}}

/**
 * The draw order, as named layers. The renderer draws a *behind* pass, the head, then a *front* pass,
 * so outfits (sub-project I) can sit behind or in front of the head. Each layer's data comes from layout().
 */
const PASSES={behind:['glow','zoomTrails','ruff','bib','paws','ears'],head:['head','markings','tint','rim','blush','eyes','mouth','nose'],front:['foldEars','whiskers','badge','particles','balls']};

Object.assign(api,{newPose,FACE,DETAIL_FULL_MIN,detailOf,COMPACT_EAR_SCALE,earScale,outlineSteps,badgeSide,CURSOR,cursorLook,pupilOffset,faceAngles,supPoints,mkWarp,flatten,MOMO_WHITE,earGeom,layout,PASSES});
```

- [ ] **Step 4: Add the fixture builders**

Insert the block below into `scripts/gen-cat-fixtures.mjs`, immediately above the line containing `@@BUILDERS`:

```js
// ── Geometry and warp ────────────────────────────────────────────────────────
const pose = (o = {}) => ({ ...core.newPose(), ...o });
const noW = L => { const { W, ...rest } = L; return rest; };
const presetOf = (cat, kitten) => (kitten ? core.kittenOf(core.PRESETS[cat]) : core.PRESETS[cat]);
const SIDE = D => core.badgeSide(D < core.DETAIL_FULL_MIN);

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
```

- [ ] **Step 5: Write the fixtures and run everything**

Run: `node scripts/gen-cat-fixtures.mjs && bash scripts/test-cat-contract.sh`
Expected: `wrote 3 fixture files to tests/fixtures/cat`, then `# tests 34`, `# pass 34`, `# fail 0`, `✓ geometry-cases.json`, `✓ presets.json`, `✓ warp-cases.json`, `✓ 3 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

The geometry is proven against the prototype's pixels in Task 7, where `drawCat` starts drawing from `layout()`.

- [ ] **Step 6: Commit**

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/geometry.test.mjs tests/fixtures/cat/geometry-cases.json tests/fixtures/cat/warp-cases.json
git commit -m "feat(cat): geometry, face warp and layout in cat-core.js

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Personality

**Files:**
- Modify: `design/prototype/cat-core.js` (insert a section above `@@END-OF-CORE`)
- Modify: `scripts/gen-cat-fixtures.mjs` (insert a builder above `@@BUILDERS`)
- Create: `tests/cat/personality.test.mjs`
- Create: `tests/fixtures/cat/personality-cases.json` (generated)

**Interfaces:**
- Consumes: `clamp`, `tm`, `own` from Task 1; `compare` from `scripts/gen-cat-fixtures.mjs` (in the test).
- Produces: `TRAITS` (six `[key, label, low, high]` rows), `TRAIT_KEYS`, `PERSONAS` (six presets, each `{label, energy, curiosity, chatty, affection, sass, mischief}`), `normPers(traits)` (the six traits, each held to 0 to 1, missing or non-numeric as 0.5), `persMultipliers(traits)`, `personaNamed(name)` (`{preset, ...traits}`, Balanced for an unknown name) and `slide(pers, trait, value)` (the new value held to 0 to 1 and `preset: 'custom'`; an unknown trait or a non-finite value changes nothing).
- `persMultipliers` returns `{speed, hop, blinkEvery, gaze, earFlickEvery, chatter, slowBlinkEvery}` (multipliers, 1 at neutral), `{pupil, smile, skew, blush, lid, earBack}` (added to the resting pose, 0 at neutral), `idle: {yawn, zoomies, mew, purr, hmph, wink}` (booleans), `poke` (`'love'` or `'annoyed'`) and `pokeHiss` (boolean). The engine in Task 6 reads only these.
- Produces: `personality-cases.json` `{traits[6], presets{6}, cases[32], slide[5]}`.

The traits and presets are the prototype's `TRAITS` and `PERSONAS` (lines 561 to 568), moved as written. `persMultipliers` is the same formulas the prototype's engine had inline in `update`, `slap` and `persAmbient`, gathered in one place so a fixture can pin them.

- [ ] **Step 1: Write the failing tests**

Create `tests/cat/personality.test.mjs`:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const require = createRequire(import.meta.url);
const core = require('../../design/prototype/cat-core.js');
const fixture = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/personality-cases.json', import.meta.url), 'utf8'));
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const M = t => core.persMultipliers(t);

test('six traits and six presets, exactly as approved', () => {
  assert.deepEqual(core.TRAITS.map(t => t[0]), ['energy', 'curiosity', 'chatty', 'affection', 'sass', 'mischief']);
  assert.deepEqual(core.TRAITS.map(t => t[1]), ['Energy', 'Curiosity', 'Chattiness', 'Affection', 'Sass', 'Mischief']);
  assert.deepEqual(core.TRAITS.map(t => [t[2], t[3]]), [['sleepy', 'bouncy'], ['aloof', 'nosy'], ['quiet', 'talkative'], ['independent', 'cuddly'], ['easy-going', 'grumpy'], ['well-behaved', 'troublemaker']]);
  assert.deepEqual(Object.keys(core.PERSONAS), ['balanced', 'chill', 'grumpy', 'sweet', 'hyper', 'chatty']);
  const row = n => core.TRAIT_KEYS.map(k => core.PERSONAS[n][k]);
  assert.deepEqual(row('balanced'), [.5, .5, .5, .5, .5, .5]);
  assert.deepEqual(row('chill'), [.12, .35, .3, .65, .3, .2]);
  assert.deepEqual(row('grumpy'), [.4, .3, .45, .15, .95, .3]);
  assert.deepEqual(row('sweet'), [.5, .55, .55, 1, .1, .3]);
  assert.deepEqual(row('hyper'), [1, .9, .75, .5, .3, 1]);
  assert.deepEqual(row('chatty'), [.6, .7, 1, .6, .35, .5]);
});

test('Balanced changes nothing: every multiplier is 1, every addition 0, no idle habit, a poke annoys', () => {
  const m = M(core.PERSONAS.balanced);
  for (const k of ['speed', 'hop', 'blinkEvery', 'gaze', 'earFlickEvery', 'chatter', 'slowBlinkEvery']) near(m[k], 1);
  for (const k of ['pupil', 'smile', 'skew', 'blush', 'lid', 'earBack']) near(m[k], 0);
  assert.deepEqual(m.idle, { yawn: false, zoomies: false, mew: false, purr: false, hmph: false, wink: false });
  assert.equal(m.poke, 'annoyed'); assert.equal(m.pokeHiss, false);
});

test('each preset switches on its own habits', () => {
  assert.equal(M(core.PERSONAS.chill).idle.yawn, true); assert.ok(M(core.PERSONAS.chill).lid > .3); near(M(core.PERSONAS.chill).speed, core.tm(.12, .55, 1.5));
  const grumpy = M(core.PERSONAS.grumpy);
  assert.equal(grumpy.idle.hmph, true); assert.equal(grumpy.pokeHiss, true); assert.ok(grumpy.skew > .4 && grumpy.smile < 0 && grumpy.earBack > .15 && grumpy.lid > .2);
  const sweet = M(core.PERSONAS.sweet);
  assert.equal(sweet.idle.purr, true); assert.equal(sweet.poke, 'love'); assert.ok(sweet.blush > .3 && sweet.smile > .2);
  const hyper = M(core.PERSONAS.hyper);
  assert.equal(hyper.idle.zoomies, true); assert.equal(hyper.idle.wink, true); near(hyper.speed, 1.5); near(hyper.hop, 1.4); near(hyper.blinkEvery, .75);
  assert.equal(M(core.PERSONAS.chatty).idle.mew, true); near(M(core.PERSONAS.chatty).chatter, 1.4);
});

test('the thresholds are strict: the behaviour switches on just past the line, not on it', () => {
  assert.equal(M({ energy: .29 }).idle.yawn, true); assert.equal(M({ energy: .3 }).idle.yawn, false);
  assert.equal(M({ chatty: .7 }).idle.mew, false); assert.equal(M({ chatty: .71 }).idle.mew, true);
  assert.equal(M({ affection: .75 }).idle.purr, false); assert.equal(M({ affection: .76 }).idle.purr, true);
  assert.equal(M({ sass: .75 }).idle.hmph, false); assert.equal(M({ sass: .76 }).idle.hmph, true);
  assert.equal(M({ mischief: .65 }).idle.wink, false); assert.equal(M({ mischief: .66 }).idle.wink, true);
  assert.equal(M({ mischief: .75, energy: .8 }).idle.zoomies, false); assert.equal(M({ mischief: .76, energy: .7 }).idle.zoomies, false); assert.equal(M({ mischief: .76, energy: .71 }).idle.zoomies, true);
  assert.equal(M({ affection: .75, sass: .1 }).poke, 'annoyed'); assert.equal(M({ affection: .76, sass: .4 }).poke, 'annoyed'); assert.equal(M({ affection: .76, sass: .39 }).poke, 'love');
  assert.equal(M({ sass: .7 }).pokeHiss, false); assert.equal(M({ sass: .71 }).pokeHiss, true);
});

test('hand-edited values: out of range is held to 0…1, missing or odd values count as 0.5', () => {
  assert.deepEqual(M({ energy: 7, sass: -3 }), M({ energy: 1, sass: 0 }));
  assert.deepEqual(M(undefined), M(core.PERSONAS.balanced));
  assert.deepEqual(M(null), M(core.PERSONAS.balanced));
  assert.deepEqual(M({}), M(core.PERSONAS.balanced));
  assert.deepEqual(M({ energy: 'high', curiosity: NaN, chatty: Infinity }), M(core.PERSONAS.balanced));
  for (const k of ['speed', 'hop', 'gaze', 'chatter', 'blinkEvery', 'earFlickEvery', 'slowBlinkEvery']) {
    for (const v of [-5, 5]) assert.ok(M({ energy: v, curiosity: v, chatty: v, affection: v })[k] > 0, `${k} stays positive at ${v}`);
  }
  assert.deepEqual(core.normPers({ energy: 2, sass: 'x', extra: 1, preset: 'custom' }), { energy: 1, curiosity: .5, chatty: .5, affection: .5, sass: .5, mischief: .5 });
});

test('moving a slider turns the preset into Custom without touching the original', () => {
  const sweet = core.personaNamed('sweet'), before = JSON.stringify(sweet);
  assert.equal(sweet.preset, 'sweet'); assert.equal(sweet.affection, 1);
  const moved = core.slide(sweet, 'sass', .9);
  assert.equal(JSON.stringify(sweet), before);
  assert.equal(moved.preset, 'custom'); assert.equal(moved.sass, .9); assert.equal(moved.affection, 1);
  assert.equal(core.slide(sweet, 'sass', 4).sass, 1);
  assert.equal(core.slide(sweet, 'sass', -1).sass, 0);
  assert.equal(core.slide(sweet, 'nonsense', .3).preset, 'sweet', 'an unknown trait changes nothing');
  assert.equal(core.slide(sweet, 'sass', NaN).preset, 'sweet', 'NaN changes nothing');
  assert.equal(core.personaNamed('nope').preset, 'balanced');
  assert.equal(core.personaNamed('constructor').preset, 'balanced');
});

test('personality-cases.json: the presets table and every case replay from their inputs', () => {
  assert.equal(fixture.version, 1);
  assert.deepEqual(fixture.traits.map(t => t.key), core.TRAIT_KEYS);
  assert.deepEqual(Object.keys(fixture.presets), Object.keys(core.PERSONAS));
  for (const [name, p] of Object.entries(fixture.presets)) assert.deepEqual(p, core.PERSONAS[name]);
  assert.ok(fixture.cases.length >= 30);
  for (const c of fixture.cases) assert.deepEqual(compare(JSON.parse(JSON.stringify(M(c.traits))), c.out), [], c.name);
  for (const c of fixture.slide) assert.deepEqual(compare(core.slide(core.personaNamed(c.from), c.trait, c.value), c.out), [], `${c.from} ${c.trait}`);
  assert.ok(fixture.cases.some(c => c.name.includes('out of range')) && fixture.cases.some(c => c.name.includes('missing')));
});
```

This file pins Review Focus 3 in "hand-edited values": out-of-range, missing, `NaN`, `Infinity`, a string and `null` are all held to 0 to 1 or counted as 0.5.

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test tests/cat/personality.test.mjs`
Expected: FAIL (it cannot read `tests/fixtures/cat/personality-cases.json`, and `core.persMultipliers` doesn't exist).

- [ ] **Step 3: Add the personality section to the core**

Insert the block below into `design/prototype/cat-core.js`, immediately above the line containing `@@END-OF-CORE`:

```js
// ── Personality ──────────────────────────────────────────────────────────────
// Six traits, 0…1, that bend the behaviour a cat already has. 0.5 is neutral, so the
// Balanced preset is exactly the approved motion. Any coat can wear any personality.
const TRAITS=[['energy','Energy','sleepy','bouncy'],['curiosity','Curiosity','aloof','nosy'],['chatty','Chattiness','quiet','talkative'],['affection','Affection','independent','cuddly'],['sass','Sass','easy-going','grumpy'],['mischief','Mischief','well-behaved','troublemaker']];
const PERSONAS={
 balanced:{label:'Balanced',energy:.5,curiosity:.5,chatty:.5,affection:.5,sass:.5,mischief:.5},
 chill:{label:'Chill',energy:.12,curiosity:.35,chatty:.3,affection:.65,sass:.3,mischief:.2},
 grumpy:{label:'Grumpy',energy:.4,curiosity:.3,chatty:.45,affection:.15,sass:.95,mischief:.3},
 sweet:{label:'Sweet',energy:.5,curiosity:.55,chatty:.55,affection:1,sass:.1,mischief:.3},
 hyper:{label:'Hyper',energy:1,curiosity:.9,chatty:.75,affection:.5,sass:.3,mischief:1},
 chatty:{label:'Chatty',energy:.6,curiosity:.7,chatty:1,affection:.6,sass:.35,mischief:.5}};
const TRAIT_KEYS=TRAITS.map(t=>t[0]);
/** Traits as stored: a missing, non-numeric or NaN trait becomes 0.5, anything else is held to 0…1 (a settings file can be hand-edited). */
function normPers(P){const o={};for(const k of TRAIT_KEYS){const v=P&&typeof P[k]==='number'&&Number.isFinite(P[k])?P[k]:.5;o[k]=clamp(v,0,1)}return o}
/**
 * What a personality changes, as numbers. The engine reads only these.
 *   speed, hop, blinkEvery, gaze, earFlickEvery, chatter, slowBlinkEvery are multipliers (1 at neutral);
 *   pupil, smile, skew, blush, lid and earBack are added to the resting pose (0 at neutral);
 *   idle says which idle habits are on; poke is the reaction to a poke; pokeHiss adds a hiss to it.
 */
function persMultipliers(P0){const P=normPers(P0),energy=P.energy,sass=P.sass,aff=P.affection;
 return{speed:tm(energy,.55,1.5),hop:tm(energy,.45,1.4),blinkEvery:tm(energy,1.4,.75),pupil:(energy-.5)*.3,
  lid:Math.max(Math.max(0,.5-energy),Math.max(0,sass-.55)*.55),
  gaze:tm(P.curiosity,.35,1.2),earFlickEvery:tm(P.curiosity,1.6,.6),chatter:tm(P.chatty,.3,1.4),
  smile:(aff-.5)*.5-Math.max(0,sass-.5)*1.1,blush:Math.max(0,aff-.6)*.9,slowBlinkEvery:tm(aff,1.6,.5),
  skew:Math.max(0,sass-.5)*.9,earBack:Math.max(0,sass-.55)*.45,
  idle:{yawn:energy<.3,zoomies:P.mischief>.75&&energy>.7,mew:P.chatty>.7,purr:aff>.75,hmph:sass>.75,wink:P.mischief>.65},
  poke:aff>.75&&sass<.4?'love':'annoyed',pokeHiss:sass>.7}}
/** A preset as a cat stores it: its name plus the six traits. An unknown name gives Balanced. */
const personaNamed=name=>{const k=own(PERSONAS,name)?name:'balanced',{label,...traits}=PERSONAS[k];return{preset:k,...traits}};
/** Moving a slider: the new value (held to 0…1) and the preset becomes 'custom'. An unknown trait changes nothing. */
const slide=(pers,trait,value)=>TRAIT_KEYS.includes(trait)&&typeof value==='number'&&Number.isFinite(value)?{...pers,[trait]:clamp(value,0,1),preset:'custom'}:{...pers};

Object.assign(api,{TRAITS,TRAIT_KEYS,PERSONAS,normPers,persMultipliers,personaNamed,slide});
```

- [ ] **Step 4: Add the fixture builder**

Insert the block below into `scripts/gen-cat-fixtures.mjs`, immediately above the line containing `@@BUILDERS`:

```js
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
```

- [ ] **Step 5: Write the fixture and run everything**

Run: `node scripts/gen-cat-fixtures.mjs && bash scripts/test-cat-contract.sh`
Expected: `# tests 41`, `# pass 41`, `# fail 0`, `✓ personality-cases.json` among four `✓` lines, `✓ 4 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 6: Commit**

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/personality.test.mjs tests/fixtures/cat/personality-cases.json
git commit -m "feat(cat): personality traits, presets and multipliers in cat-core.js

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Rules and timelines: work clock, sleep, search tools, greeting, file flight

**Files:**
- Modify: `design/prototype/cat-core.js` (insert a section above `@@END-OF-CORE`)
- Modify: `scripts/gen-cat-fixtures.mjs` (insert the builders above `@@BUILDERS`)
- Create: `tests/cat/sequence.test.mjs`
- Create: `tests/fixtures/cat/search-tools.json`, `tests/fixtures/cat/sequence-cases.json` (generated)

**Interfaces:**
- Consumes: `EZ`, `lerp`, `seg`, `rng`, `TAU`, `BUSY`, `STATES` from Task 1; `compare` from the generator (in the test).
- Produces the rules: `ZOOM_AFTER_MS` (300000), `workClockStep(clock, state, nowMs)` (a new `{busySince, workedFor}`; `busySince` is null while no run is open), `zoomiesOnFinish(workedForMs, thresholdMs = ZOOM_AFTER_MS)`, `SLEEP_AFTER_MS` (600000), `sleepDelay(state, quietMs)` (ms until sleep, 0 meaning now, or null for any state but `idle`), `WAKE_EVENTS` (`hook`, `hover`, `click`) and `wakes(kind)`, `SEARCH_TOOLS` (`{claude, gemini, codex}`), `isSearchTool(name)` and `toolState(name)` (`'searching'` or `'working'`).
- Produces the timelines: `NOTCH`, `COMPACT`, `GT`, `GT2`, `GREET_LEN` (5.74), `STREAKS`, `streakTime(t)`, `islandBase(t)`, `greetingPose(t)` (the whole pose at `t` seconds, in the 640×150 space; the fields are listed in its comment), `FLIGHT_MS` (380) and `flightAt(from, to, R, k)` (`{x, y, size, rot}`).
- Produces: `search-tools.json` `{match, agents, cases[28]}` and `sequence-cases.json` with the keys `greetingLengthS`, `greetingTimeline`, `greetingStreaks[16]`, `greetingSamples[70]`, `flight`, `zoomAfterMs`, `workClock[12]`, `sleep`. The file is assembled from parts: `SEQUENCE_PARTS.push(() => ({ ...top-level keys }))`, and Task 6 adds the engine-driven keys with the same call.
- `workClockStep` replaces the work clock that lived inside the prototype's `setState`, which treated a start time of 0 as "no run". `busySince` is now null for "no run", so a run that starts at clock 0 counts.

The greeting is the prototype's `GT2` and `greetPose2` (lines 895 to 915) with the old cat motion dropped. What it still needs from the old `greetPose`, namely the island's growth, the blinks, the badge, tint, halo and header, is kept as `islandBase`; the collapse after `GT.leave` is the old `pose()` with its zero terms written as zeros. `GT` loses `squint`, `dip`, `pop`, `content`, `tuck` and `down`, which only the old timeline used.

Where the Gemini CLI and Codex names come from (they are not all verified):
- Claude Code: `WebSearch`, `WebFetch`, `Grep`, `Glob` are the names in `HookServer.swift`'s `frenchStep` and `windows/src/island/hooks.ts`'s `TOOL_LABELS`.
- Gemini CLI: `google_web_search`, `web_fetch`, `glob` and `grep_search` are in the installed CLI (0.39.1). `grep_search` was called `search_file_content` before, and the CLI keeps that as a legacy alias, so both are listed. The repo itself has no Gemini tool names.
- Codex: `web_search` and `grep_files` are not verified; there is no Codex install here and the repo only knows `apply_patch`, `update_plan`, `spawn_agent` and `mcp__*`. A name that is wrong only means the cat stays in "working" for that tool.

- [ ] **Step 1: Write the failing tests**

Create `tests/cat/sequence.test.mjs`:

```js
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
```

This file pins Review Focus 5: one millisecond short of 5 minutes against exactly 5 minutes, exactly 10 minutes of quiet, a run that starts at clock 0, an approval pause inside a run, and a clock that steps backwards.

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test tests/cat/sequence.test.mjs`
Expected: FAIL (it cannot read `tests/fixtures/cat/search-tools.json`, and `core.workClockStep` doesn't exist).

- [ ] **Step 3: Add the rules and timelines to the core**

Insert the block below into `design/prototype/cat-core.js`, immediately above the line containing `@@END-OF-CORE`:

```js
// ── Rules: work clock and zoomies, sleep, wake, search ───────────────────────
/** An agent that finishes after this much working, thinking or searching earns zoomies (ms). The prototype page shortens it to 12 s to be watchable. */
const ZOOM_AFTER_MS=5*60*1000;
/**
 * The work clock. Working, thinking and searching keep it running; approval and question pauses neither stop nor reset it;
 * every other state ends the run and stores how long it lasted in `workedFor` (never negative, even if the clock steps back).
 * Pure: pass the clock in, get the next one back.
 * `busySince` is null while no run is open.
 */
function workClockStep(clock,state,nowMs){const c={busySince:clock.busySince,workedFor:clock.workedFor};
 if(BUSY.has(state)){if(c.busySince===null)c.busySince=nowMs}
 else if(state!=='approval'&&state!=='question'){c.workedFor=c.busySince===null?0:Math.max(0,nowMs-c.busySince);c.busySince=null}
 return c}
const zoomiesOnFinish=(workedForMs,thresholdMs=ZOOM_AFTER_MS)=>workedForMs>=thresholdMs;
/** An idle cat falls asleep after this long with no agent event (ms). */
const SLEEP_AFTER_MS=10*60*1000;
/**
 * Milliseconds until the cat should fall asleep, for arming a one-shot timer (no polling): 10 minutes after the last
 * agent event. Only an idle cat sleeps, so any other state (approval and question included) gives null.
 * A negative or non-numeric quiet time counts as 0. 0 means: asleep now.
 */
const sleepDelay=(state,quietMs)=>state==='idle'?Math.max(0,SLEEP_AFTER_MS-Math.max(0,Number.isFinite(quietMs)?quietMs:0)):null;
/** Anything that wakes a sleeping cat. In Playful it wakes with zoomies (see the Playful profile). */
const WAKE_EVENTS=['hook','hover','click'];
const wakes=kind=>WAKE_EVENTS.includes(kind);
/** Tool names that mean "searching" (exact, case-sensitive match on the tool name the hook relay delivers). */
const SEARCH_TOOLS={claude:['WebSearch','WebFetch','Grep','Glob'],gemini:['google_web_search','web_fetch','grep_search','search_file_content','glob'],codex:['web_search','grep_files']};
const SEARCH_SET=new Set(Object.values(SEARCH_TOOLS).flat());
const isSearchTool=name=>typeof name==='string'&&SEARCH_SET.has(name);
/** The state a tool event puts an agent in: a search tool is 'searching', any other tool 'working'. */
const toolState=name=>isSearchTool(name)?'searching':'working';

// ── Timelines: the greeting and the file flight ──────────────────────────────
// The greeting is Greeting v2, in the 640×150 reference space and 5.74 s long: the cat falls in with a landing squash,
// bounces, slides aside, pops up for a quick paw wave, slides back and settles with the badge and tint.
const NOTCH={W:184,H:32},COMPACT=288;
const GT={grow:.45,badge:2.72,blink2:3.8,tint0:3.85,tint1:4.15,leave:4.9,COLLAPSE:.34};
const GT2={fall0:.05,land:.62,bounce1:1.18,slide0:1.25,slide1:1.65,pop0:1.65,wave0:1.72,wave1:2.72,back0:2.75,back1:3.25,SLIDE:150};
const GREET_LEN=GT.leave+GT.COLLAPSE+.5;
const STREAKS=(()=>{const r=rng(7),cols=['#3B9EFF','#F29B38','#FF5A4E','#2EC4A0','#A78BFA'];return Array.from({length:16},(_,i)=>({a:i/16*TAU+(r()-.5)*.3,sp:230+r()*260,len:6+r()*9,t0:.08+r()*.14,col:cols[i%5]}))})();
/** Streak burst time: it starts when the cat lands. */
const streakTime=t=>t-(GT2.land-.1);
/** The island and the shared beats: size, blink, badge, tint, halo, header. Everything but the cat's own motion. */
function islandBase(t){const gx=seg(t,0,.5),g=Math.sin(Math.PI*gx/2)+.04*Math.sin(Math.PI*gx)*gx,gg=EZ.back(seg(t,.02,GT.grow)),
 blink=tb=>{const k=seg(t,tb,tb+.12);return k>0&&k<1?1-Math.sin(Math.PI*k)*.94:1};
 return{iw:lerp(NOTCH.W,640,g),ih:lerp(NOTCH.H,150,g),hb:lerp(3,58,gg),base:lerp(16,86,EZ.out(seg(t,.02,GT.grow))),open:Math.min(blink(1.95),blink(GT.blink2)),
  badge:EZ.back(seg(t,GT.badge,GT.badge+.28)),tint:.6*EZ.inOut(seg(t,GT.tint0,GT.tint1)),halo:EZ.out(seg(t,.3,.7)),haloBlue:seg(t,GT.tint0,GT.tint1),header:seg(t,.35,.6),card:seg(t,.18,.45)}}
/** The cat's fall, bounce, slide, pop and wave. */
function fallPose(t,B){const G=GT2,hb=B.hb,D=hb*1.34,base=B.base;
 let x=320,y=base,sx=1,sy=1,tilt=0,eye='dot',lookX=0,lookY=0,handL=0,handR=0,wave=-1;
 const fall=seg(t,G.fall0,G.land);y-=(1-fall*fall)*(base+70);                       // 1 fall in (accelerating)
 const sq=Math.sin(Math.PI*seg(t,G.land,G.land+.16));sy-=.2*sq;sx+=.14*sq;y+=D*.05*sq; // landing squash
 const b=seg(t,G.land+.16,G.bounce1);y-=4*b*(1-b)*hb*.3;sy+=.05*Math.sin(Math.PI*b);   // 2 small bounce
 const sq2=Math.sin(Math.PI*seg(t,G.bounce1,G.bounce1+.1));sy-=.07*sq2;sx+=.05*sq2;y+=D*.02*sq2;
 const out=EZ.inOut(seg(t,G.slide0,G.slide1)),ret=EZ.inOut(seg(t,G.back0,G.back1));   // 3 slide aside, 5 slide back
 x+=G.SLIDE*out*(1-ret);tilt=.1*Math.sin(Math.PI*seg(t,G.slide0,G.slide1))-.1*Math.sin(Math.PI*seg(t,G.back0,G.back1));
 const ant=Math.sin(Math.PI*seg(t,G.pop0-.1,G.pop0));sy-=.08*ant;y+=D*.03*ant;         // 4 pop up
 const pop=EZ.back(seg(t,G.pop0,G.pop0+.2))*(1-EZ.inOut(seg(t,G.back0,G.back0+.2)));
 y-=hb*.16*pop;sy+=.07*Math.sin(Math.PI*seg(t,G.pop0,G.pop0+.2));
 const flail=.55*(1-seg(t,G.land-.05,G.land+.1))*(t>G.fall0?1:0);                      // paws up while falling
 handL=flail;handR=Math.max(flail,pop);
 if(t>=G.wave0&&t<G.wave1+.2)wave=t-G.wave0;
 if(t>=G.land&&t<G.slide0)eye='happy';
 if(t>=G.slide0&&t<G.pop0)lookX=.5*out;
 if(t>=G.pop0&&t<G.back0){eye='happy';lookX=.3;lookY=-.4}
 if(t>=G.back0){const k=seg(t,G.back0,G.back1+.1);eye=k<.9?'content':'dot';lookX=lerp(.3,0,EZ.inOut(k));lookY=lerp(-.4,0,EZ.inOut(k))}
 return{iw:B.iw,ih:B.ih,hb,x,y,sx,sy,tilt,eye,lookX,lookY,handL,handR,wave,open:B.open,badge:B.badge,tint:B.tint,halo:B.halo,haloBlue:B.haloBlue,header:B.header,card:B.card,fx:1,minis:0}}
/** After GT.leave the island collapses to the compact notch and the cat settles. */
function collapsePose(t){const tc=GT.leave,a=islandBase(tc),e=EZ.inOut(seg(t,tc,tc+GT.COLLAPSE)),bx=320-COMPACT/2+40,bk=seg(t,tc+.14,tc+.26);
 return{iw:lerp(a.iw,COMPACT,e),ih:lerp(a.ih,32,e),hb:lerp(a.hb,20/1.34,e),x:lerp(320,bx,e),y:lerp(a.base,16,e),sx:1,sy:1,tilt:0,eye:'dot',lookX:0,lookY:0,handL:0,handR:0,wave:-1,
  open:bk>0&&bk<1?1-Math.sin(Math.PI*bk)*.94:1,badge:a.badge,tint:a.tint,halo:a.halo*(1-e),haloBlue:a.haloBlue,header:a.header*(1-seg(t,tc,tc+.1)),card:a.card*(1-seg(t,tc,tc+.18)),fx:1-seg(t,tc,tc+.2),minis:EZ.back(seg(t,tc+.24,tc+.42))}}
/**
 * The greeting pose at t seconds (0 … GREET_LEN), all in the 640×150 space: island iw×ih, cat centre x,y and head width hb×1.34,
 * squash sx/sy, tilt, eye shape ('dot' | 'happy' | 'content'), gaze lookX/lookY, paw raise handL/handR, wave clock (-1 = off), blink open,
 * and the 0…1 fades badge, tint, halo, haloBlue, header, card, fx (streaks), minis (the session cats).
 */
const greetingPose=t=>t<GT.leave?fallPose(t,islandBase(t)):collapsePose(t);

/** A dropped file arcs into the cat's mouth over this long (ms). k is 0…1 along the flight. */
const FLIGHT_MS=380;
function flightAt(from,to,R,k){const q=EZ.inOut(k),cx=(from.x+to.x)/2,cy=Math.min(from.y,to.y)-60,u=1-q;
 return{x:u*u*from.x+2*u*q*cx+q*q*to.x,y:u*u*from.y+2*u*q*cy+q*q*to.y,size:lerp(R*.62,R*.14,q),rot:(1-q)*.5-.25}}

Object.assign(api,{ZOOM_AFTER_MS,workClockStep,zoomiesOnFinish,SLEEP_AFTER_MS,sleepDelay,WAKE_EVENTS,wakes,SEARCH_TOOLS,isSearchTool,toolState,NOTCH,COMPACT,GT,GT2,GREET_LEN,STREAKS,streakTime,islandBase,greetingPose,FLIGHT_MS,flightAt});
```

- [ ] **Step 4: Add the fixture builders**

Insert the block below into `scripts/gen-cat-fixtures.mjs`, immediately above the line containing `@@BUILDERS`:

```js
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
```

- [ ] **Step 5: Write the fixtures and run everything**

Run: `node scripts/gen-cat-fixtures.mjs && bash scripts/test-cat-contract.sh`
Expected: `# tests 51`, `# pass 51`, `# fail 0`, six `✓` fixture lines (`geometry-cases.json`, `personality-cases.json`, `presets.json`, `search-tools.json`, `sequence-cases.json`, `warp-cases.json`), `✓ 6 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 6: One-off check of the greeting against the prototype (not committed)**

The old page's `pose2(t)` is the greeting people approved. This runs it from git next to `greetingPose(t)` over 291 times from 0 to 5.8 s.

```bash
T=${TMPDIR:-/tmp}/a0-check; mkdir -p "$T"
git show 683163f:design/prototype/notchmeow.html > "$T/old.html"
cat > "$T/equiv-greeting.mjs" <<'EOF'
// One-off: the greeting in cat-core.js against the pre-A-0 prototype's pose2(t), run in Node (no browser needed).
// Usage: node equiv-greeting.mjs <cat-core.js> <old notchmeow.html>
import fs from 'node:fs'; import vm from 'node:vm'; import { createRequire } from 'node:module';
const require = createRequire(import.meta.url); const core = require(process.argv[2]);
const L = fs.readFileSync(process.argv[3], 'utf8').split('\n'), pick = (a, b) => L.slice(a - 1, b).join('\n');
const code = ['const TAU=Math.PI*2;', pick(116, 117), pick(120, 120), pick(729, 729), pick(744, 765), pick(895, 915), ';({pose2,GT,GT2,GREET_LEN,STREAKS})'].join('\n');
const old = vm.runInNewContext(code);
let worst = 0, n = 0, bad = 0;
for (let i = 0; i <= 290; i++) { const t = i * .02, p = old.pose2(t), q = core.greetingPose(t);
  for (const k of Object.keys(q)) { if (typeof q[k] === 'number') { worst = Math.max(worst, Math.abs(p[k] - q[k])); n++ } else if (p[k] !== q[k]) { bad++; console.log('mismatch', k, t) } } }
const sd = Math.max(...old.STREAKS.map((s, i) => Math.max(Math.abs(s.a - core.STREAKS[i].a), Math.abs(s.sp - core.STREAKS[i].sp), Math.abs(s.t0 - core.STREAKS[i].t0))));
console.log(`greeting: ${n} numbers compared, worst difference ${worst}, string mismatches ${bad}, GREET_LEN ${old.GREET_LEN} vs ${core.GREET_LEN}, streaks ${sd}`);
process.exit(worst < 1e-12 && !bad && sd === 0 ? 0 : 1);
EOF
node "$T/equiv-greeting.mjs" "$PWD/design/prototype/cat-core.js" "$T/old.html"
```

Expected: `greeting: 6402 numbers compared, worst difference 0, string mismatches 0, GREET_LEN 5.74 vs 5.74, streaks 0`. A difference above 1e-12, or any string mismatch, makes the command exit 1.

- [ ] **Step 7: Commit**

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/sequence.test.mjs tests/fixtures/cat/search-tools.json tests/fixtures/cat/sequence-cases.json
git commit -m "feat(cat): zoomies, sleep and search rules, greeting and file flight in cat-core.js

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Motion profiles and the engine

**Files:**
- Modify: `design/prototype/cat-core.js` (insert a section above `@@END-OF-CORE`)
- Modify: `scripts/gen-cat-fixtures.mjs` (insert the builders above `@@BUILDERS`)
- Create: `tests/cat/motion.test.mjs`
- Create: `tests/fixtures/cat/motion-cases.json` (generated); `tests/fixtures/cat/sequence-cases.json` (regenerated, with three more keys)

**Interfaces:**
- Consumes from earlier tasks: `EZ`, `lerp`, `clamp`, `hex`, `tm`, `own`, `TAU`, the state tables, `mouthFx` and `BUSY` (Task 1); `PRESETS` (Task 2); `newPose`, `layout` (Task 3); `persMultipliers`, `PERSONAS` (Task 4); `workClockStep`, `zoomiesOnFinish`, `ZOOM_AFTER_MS` (Task 5); `compare` and the `SEQUENCE_PARTS` registry from the generator.
- Produces: `CLASSIC` and `PLAYFUL` (the two motion profiles; Classic is upstream 1:1), `PROFILES` (`{classic, playful}`), `cfg` (the shared settings `{motion, override, pers, zoomAfter}` an engine reads unless it is given its own), `enginePaws(engine, R, rx, ry)` (the paw list for the greeting wave) and `CatEngine`.
- `new CatEngine(preset, opts)`: `opts.now()` (ms) and `opts.rand()` (0 to 1) are injected, defaulting to `performance.now` and `Math.random`, looked up late; `opts.cfg`, `opts.state`, `opts.mini`; `opts.quiet` turns off every random idle habit; `opts.log` is an array that collects `[ms, name]`. Public members: `s` (the pose, `newPose()` keys), `tg` (targets), `state`, `setState(state, force)` (unknown names are ignored), `emote(name)` (unknown names do nothing), `slap()`, `catchOpen(on)`, `catchDrop()`, `catchArrive()`, `catchReject(ext)`, `greet()`, `zoomies()`, `hairball(file)`, `update(dt)` (`dt` is held to 0 up to 0.25 s), `computeTargets(t, T)`, `mouthOpen()`, `eyeShape()`, `lookX`/`lookY`, `parts`, `balls`, `col`, `gc`, `ga`, `motion` and `pers`. The renderer sets `_base`, `_at` and `_mouth` on it.
- Produces from the generator: `makeEngine(preset, opts)` returning `{e, clock, step(frame)}`, and `frameMs(frame)` (`frame * 1000 / 60`). Tests and fixtures share them.
- Produces: `motion-cases.json` `{clock, harness, columns[36], ease[5], tween[5], prng[7], rest[110], enters[264], emotes[288], ambient[12]}` and, in `sequence-cases.json`, `catchHarness`, `catch[4]` and `zoomiesAndWake[14]`.

The profiles and the engine are the prototype's `CLASSIC`, `PLAYFUL` and `CatEngine` (lines 481 to 693), moved with these changes only:
- `ms()` becomes `this.now()`, `RN()` becomes `this.rand()` and `U(a, b)` becomes `this.u(a, b)`, in the same places and the same order, so the random sequence is identical.
- `MOTION`, `OVERRIDE` and `PERS` become `this.cfg.motion`, `.override` and `.pers`.
- The personality maths moves to `persMultipliers`, the target maths out of `update` into `computeTargets`, and the slow blink into `slowBlink()`.
- The work clock moves to `workClockStep`; the 12 s `ZOOM_AFTER` becomes `cfg.zoomAfter`.
- New: the `quiet` and `log` options, a `dt` guard, `setState` and `emote` ignoring unknown names, an unknown motion style meaning Playful, `mouthOpen()`.

Fixtures run an engine on a fake clock: frame `f` is at `f * 1000 / 60` ms and the engine is updated once per frame with `dt = 1/60`, with `rand = rng(seed)` and `quiet: true` unless a case says otherwise. `docs/CAT-CONTRACT.md` (Task 8) describes this harness for the app plans.

- [ ] **Step 1: Write the failing tests**

Create `tests/cat/motion.test.mjs`:

```js
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
```

This file pins Review Focus 1 ("unknown names never throw") and Review Focus 2 ("hostile frame times"). It also pins the spec's emote and catch timings: hairball over 2.4 s, zoomies over 2 s, and a chew of 0.85 s.

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test tests/cat/motion.test.mjs`
Expected: FAIL (`The requested module '../../scripts/gen-cat-fixtures.mjs' does not provide an export named 'makeEngine'`).

- [ ] **Step 3: Add the profiles and the engine to the core**

Insert the block below into `design/prototype/cat-core.js`, immediately above the line containing `@@END-OF-CORE`:

```js
// ── Motion profiles ──────────────────────────────────────────────────────────
// Classic: upstream timings 1:1. Playful: cat body language on top of the same engine.
const CLASSIC={key:'classic',label:'Classic',
 rest:{idle:['pill',0],working:['pill',0],thinking:['pill',0],searching:['pill',0],approval:['wide',0],question:['pill',.17],error:['flat',0],finished:['happy',0],ratelimit:['tired',0],sleeping:['closed',0],dizzy:['spiral',0]},
 eye(st){return this.rest[st][0]},
 enter(c,st,prev){const a=c.anim.bind(c);switch(st){
  case 'idle':if(prev!=='idle')c.blink();break;
  case 'approval':a('oy',[[-.2,150,'out'],[0,300,'back']]);break;
  case 'error':a('ox',[[.08,50,'out'],[-.08,70,'inOut'],[.05,70,'inOut'],[0,90,'out']]);break;
  case 'finished':a('roll',[[TAU,950,'inOut']],()=>{c.s.roll=0});c.later(500,()=>c.emit('spark',5),'st');break;
  case 'ratelimit':c.emit('sweat',1);break;
  case 'dizzy':a('roll',[[2*TAU,1300,'inOut']],()=>{c.s.roll=0});break;
  default:c.blink()}},
 targets(c,st,T,tg){tg.tilt=this.rest[st][1];tg.earL=0;tg.earR=0;tg.earU=1;tg.earF=0;tg.pupil=.45;tg.oy=0;
  let ty=c.lookX*.62,tp=c.lookY*.5;
  if(st==='thinking'){ty=ty*.35+.55*.55;tp=tp*.3+.55*.5}
  if(st==='sleeping'){ty=0;tp=-.14;tg.sy=1+.035*Math.sin(1.8*T);tg.sx=1-.035*.57*Math.sin(1.8*T)}
  if(st==='searching'){ty=Math.sin(2.6*T)*.6;tp=-.06}
  if(st==='dizzy')ty=Math.sin(9*T)*.25;
  if(st==='approval')tg.oy=-Math.abs(Math.sin(5.2*T))*.07;
  return[ty,tp]},
 post(c,st,T,kG){if(!c.tw.ox)c.s.ox+=(0-c.s.ox)*kG},
 ambient(c,t){if(t<c.nextAmb)return;if(c.state==='sleeping')c.emit('z',1);if(c.state==='ratelimit'&&!c.mini&&c.rand()<.5)c.emit('sweat',1);c.nextAmb=t+1300},
 squash:[.78,1.16],
 emote(c,n){const a=c.anim.bind(c),d=1800;switch(n){
  case 'love':c.ov('heart',d);a('blush',[[1,300,'out'],[1,d-600,'lin'],[0,300,'inOut']]);c.emit('heart',4);a('oy',[[-.1,160,'out'],[0,300,'back']]);break;
  case 'surprised':c.ov('dot',d);a('oy',[[-.3,140,'out'],[0,380,'back']]);a('es',[[1.25,120,'out'],[1,500,'inOut']]);break;
  case 'proud':c.ov('star',d);c.emit('star',5);a('tilt',[[-.14,220,'out'],[-.14,d-500,'lin'],[0,280,'inOut']]);a('blush',[[.7,250,'out'],[.7,d-550,'lin'],[0,300,'inOut']]);break;
  case 'wink':c.ov('wink',d);a('tilt',[[.12,160,'out'],[.12,d-400,'lin'],[0,240,'inOut']]);break;
  case 'yawn':c.ov('tired',d);a('sy',[[1.12,500,'inOut'],[1,500,'inOut']]);a('sx',[[.94,500,'inOut'],[1,500,'inOut']]);a('mouth',[[.8,500,'inOut'],[0,500,'inOut']]);c.later(700,()=>{c.ov('closed',1100);c.emit('z',2)});break;
  case 'happy':c.ov('happy',d);a('blush',[[.6,200,'out'],[0,600,'inOut']]);break;
  case 'annoyed':c.ov('line',800);break}}};

const PLAYFUL={key:'playful',label:'Playful',
 // eye, tilt, earL, earR, earU, earF, pupil, oy
 rest:{idle:['pill',0,0,0,1,0,.45,0],working:['pill',0,-.08,-.08,1.1,0,.5,0],thinking:['pill',.14,0,.38,1,0,.55,0],searching:['wide',0,-.1,-.1,1.15,0,.92,.05],approval:['wide',0,-.12,-.12,1.22,0,.75,0],question:['pill',.24,-.05,.5,1,0,.7,0],error:['flat',0,0,0,1,1,.12,0],finished:['happy',0,.12,.12,1,0,.45,0],ratelimit:['tired',0,0,0,.9,.45,.4,0],sleeping:['closed',0,0,0,1,.25,.45,.08],dizzy:['spiral',0,0,0,1,0,.45,0]},
 eye(st){return this.rest[st][0]},
 enter(c,st,prev){const a=c.anim.bind(c);if(prev==='sleeping'&&st!=='sleeping'&&st!=='dizzy')c.later(220,()=>c.zoomies(),'st');switch(st){
  case 'idle':if(prev!=='idle')c.blink();break;
  case 'working':c.blink();c.twitch('earL');c.later(140,()=>c.twitch('earR'),'st');break;
  case 'thinking':c.blink();break;
  case 'searching':a('oy',[[.12,160,'out'],[.05,300,'inOut']]);break;
  case 'approval':a('oy',[[.08,110,'out'],[-.26,170,'out'],[0,340,'back']]);a('sy',[[.88,110,'out'],[1.1,170,'out'],[1,340,'back']]);a('sx',[[1.08,110,'out'],[.94,170,'out'],[1,340,'back']]);a('earU',[[1.4,140,'out'],[1.22,300,'inOut']]);break;
  case 'question':a('tilt',[[.3,220,'out'],[.24,300,'inOut']]);c.blink();break;
  case 'error':a('sx',[[1.14,80,'out'],[1,450,'inOut']]);a('sy',[[1.1,80,'out'],[1,450,'inOut']]);a('oy',[[.07,80,'out'],[0,420,'inOut']]);a('earF',[[1,90,'out']]);a('wh',[[.35,80,'out'],[0,500,'inOut']]);c.mpose({mouth:.75,smile:-1,mround:0},650,80,220);c.later(900,()=>c.hairball(),'st');break;
  case 'finished':if(zoomiesOnFinish(c.workedFor,c.cfg.zoomAfter)){c.later(150,()=>c.zoomies(),'st');c.later(2200,()=>c.emit('spark',4),'st');break}a('tilt',[[.16,260,'inOut'],[-.16,420,'inOut'],[.08,320,'inOut'],[0,300,'inOut']]);a('blush',[[.8,250,'out'],[.8,900,'lin'],[0,500,'inOut']]);c.later(350,()=>c.emit('spark',5),'st');break;
  case 'ratelimit':c.nextYawn=c.now()+300;break}},
 targets(c,st,T,tg){const r=this.rest[st];tg.tilt=r[1];tg.earL=r[2];tg.earR=r[3];tg.earU=r[4];tg.earF=r[5];tg.pupil=r[6];tg.oy=r[7];
  let ty=c.lookX*.62,tp=c.lookY*.5;
  if(st==='thinking'){ty=ty*.35-.55*.55;tp=tp*.3+.55*.5}
  if(st==='sleeping'){ty=0;tp=-.14;tg.sy=1+.04*Math.sin(1.2*T);tg.sx=1-.04*.57*Math.sin(1.2*T)}
  if(st==='searching'){ty=Math.sin(2.2*T)*.55;tg.earL=-.1-Math.sin(2.2*T)*.28;tg.earR=-.1+Math.sin(2.2*T)*.28}
  if(st==='dizzy'){ty=Math.sin(3.5*T)*.2;tg.tilt=Math.sin(7*T)*.12;tg.earL=Math.sin(9*T)*.45;tg.earR=-Math.sin(9*T+1)*.45}
  if(st==='approval')tg.oy=-Math.pow(Math.max(0,Math.sin(TAU*T/1.4)),4)*.09;
  if(st==='working')tg.oy=-Math.pow(Math.abs(Math.sin(Math.PI*1.6*T)),2)*.035;
  return[ty,tp]},
 post(c,st,T,kG){const s=c.s;if(!c.tw.ox){if(st==='searching')s.ox=Math.sin(16*T)*.012;else if(st==='dizzy')s.ox=Math.cos(7*T)*.07;else s.ox+=(0-s.ox)*kG}if(st==='dizzy'&&!c.tw.oy)s.oy=Math.sin(7*T)*.05},
 ambient(c,t){const st=c.state;
  if(st==='idle'&&t>=c.nextBlep){if(!c.tw.tongue&&!c.tw.mouth)c.rand()<.55?c.blep():c.lick();c.nextBlep=t+c.u(8000,15000)}
  if(['idle','working','thinking','sleeping','finished','question'].includes(st)&&t>=c.nextTw){c.twitch(c.rand()<.5?'earL':'earR');c.nextTw=t+(st==='working'?c.u(1500,3000):st==='sleeping'?c.u(4000,8000):c.u(3000,7000))*c.pm().earFlickEvery}
  if(st==='idle'&&t>=c.nextSB){c.slowBlink();c.nextSB=t+c.u(8000,14000)*c.pm().slowBlinkEvery}
  if(st==='ratelimit'&&t>=c.nextYawn){this.emote(c,'yawn');c.nextYawn=t+4800}
  if(st==='sleeping'&&t>=c.nextAmb){c.emit('z',1);c.nextAmb=t+1600}},
 squash:[.86,1.1],
 emote(c,n){const a=c.anim.bind(c),d=1800;switch(n){
  case 'love':c.ov('closed',d);a('purr',[[1,200,'out'],[1,d-500,'lin'],[0,300,'inOut']]);a('blush',[[1,300,'out'],[1,d-600,'lin'],[0,300,'inOut']]);a('earL',[[.18,250,'out'],[.18,d-500,'lin'],[0,250,'inOut']]);a('earR',[[.18,250,'out'],[.18,d-500,'lin'],[0,250,'inOut']]);a('tilt',[[c.lookX>=0?.12:-.12,400,'inOut'],[0,900,'inOut']]);c.emit('heart',3);break;
  case 'surprised':c.ov('dot',1100);a('earU',[[1.38,90,'out'],[1,600,'inOut']]);a('sx',[[1.12,80,'out'],[1,500,'inOut']]);a('sy',[[1.12,80,'out'],[1,500,'inOut']]);a('oy',[[-.2,120,'out'],[0,400,'back']]);a('pupil',[[1,100,'out'],[1,700,'lin'],[.45,400,'inOut']]);a('wh',[[.4,80,'out'],[0,500,'inOut']]);break;
  case 'proud':c.ov('happy',d);a('lift',[[.28,260,'out'],[.28,d-560,'lin'],[0,300,'inOut']]);a('earU',[[1.15,200,'out'],[1.15,d-500,'lin'],[1,300,'inOut']]);c.emit('spark',4);a('blush',[[.5,250,'out'],[.5,d-550,'lin'],[0,300,'inOut']]);break;
  case 'wink':c.ov('wink',1100);c.twitch('earR');a('tilt',[[.1,180,'out'],[.1,700,'lin'],[0,240,'inOut']]);break;
  case 'yawn':c.ov('closed',1300);a('mouth',[[1,450,'out'],[1,500,'lin'],[0,350,'inOut']]);a('sy',[[1.12,450,'inOut'],[1,800,'inOut']]);a('sx',[[.94,450,'inOut'],[1,800,'inOut']]);a('earF',[[.75,450,'inOut'],[c.tg.earF,800,'inOut']]);break;
  case 'happy':c.ov('happy',1400);a('oy',[[-.06,120,'out'],[0,160,'inOut'],[-.06,120,'out'],[0,200,'back']]);a('earU',[[1.12,150,'out'],[1,600,'inOut']]);a('blush',[[.6,200,'out'],[0,700,'inOut']]);break;
  case 'annoyed':c.ov('line',900);a('earF',[[1,60,'out'],[1,700,'lin'],[c.tg.earF,400,'inOut']]);a('wh',[[.4,60,'out'],[0,400,'inOut']]);break}}};

const PROFILES={classic:CLASSIC,playful:PLAYFUL};

/**
 * Shared settings every engine reads unless it is given its own: the global motion style, a per-cat motion override
 * (by cat ID), a per-cat personality (preset name plus six traits), and how long a run of work earns zoomies (ms).
 */
const cfg={motion:'playful',override:{},pers:{},zoomAfter:ZOOM_AFTER_MS};

// ── Engine ───────────────────────────────────────────────────────────────────
class CatEngine{
 /**
  * o.now() milliseconds and o.rand() 0…1 are injected (defaults: performance.now and Math.random, looked up late).
  * o.cfg is the shared settings {motion, override, pers, zoomAfter} (default: the module's `cfg`).
  * o.quiet turns off every random idle habit (blinks, ear flicks, bleps, personality), leaving only what is asked for.
  * o.log, an array, collects [ms, 'name'] for blinks, flicks, bleps, licks, emotes, zoomies and hairballs.
  */
 constructor(p,o={}){this.p=p;this.mini=!!o.mini;
  this.now=o.now||(()=>performance.now());this.rand=o.rand||(()=>Math.random());this.cfg=o.cfg||cfg;this.quiet=!!o.quiet;this.log=o.log||null;
  this.s=newPose();
  this.tg={yaw:0,pitch:0,tilt:0,sx:1,sy:1,es:1,oy:0,earL:0,earR:0,earU:1,earF:0,pupil:.45,purr:0,lid:0,mouth:0,smile:0,tongue:0,mround:0,mskew:0,wavy:0};
  this.tw={};this.q=[];this.parts=[];this.col=hex(COL.idle);this.colT=this.col.slice();this.gc=[255,255,255];this.ga=.12;
  this.state='idle';this.badge=null;this.eyeOv=null;this.eyeUntil=0;this.bt=0;this.lookX=0;this.lookY=0;this.slaps=[];this.dizzyUntil=0;this.saved=null;
  this.slotH=0;this.slotT=0;this.slotV=0;this.chew=0;this.chewStart=0;this.chewUntil=0;this.catching=false;
  this.waveStart=0;this.waveUntil=0;this.greetTok=0;this.balls=[];this.hbTok=0;this.zoomTok=0;this.zoomUntil=0;this.zv=0;this.mfx=0;this.busySince=null;this.workedFor=0;
  const t=this.now();this.nextBlink=t+this.u(1500,3500);this.nextTw=t+this.u(2000,5000);this.nextSB=t+this.u(6000,10000);this.nextAmb=t+1300;this.nextYawn=0;this.nextBlep=t+this.u(5000,9000);this.nextPers=t+this.u(3000,6000);this.blushBase=0;this.miniNext=0;this.miniLook={x:0,y:0};
  this.setState(o.state||'idle',true)}
 /** The motion style in force for this cat: its own override, else the global style; an unknown stored value means Playful. */
 get motion(){const m=this.cfg.override[this.p.base||this.p.name]||this.cfg.motion;return own(PROFILES,m)?m:'playful'}
 get prof(){return PROFILES[this.motion]}
 get pers(){return this.cfg.pers[this.p.base||this.p.name]||PERSONAS.balanced}
 /** What this cat's personality changes (persMultipliers). */
 pm(){return persMultipliers(this.pers)}
 u(a,b){return a+this.rand()*(b-a)}
 note(ev){if(this.log)this.log.push([Math.round(this.now()),ev])}
 anim(k,keys,done){this.tw[k]={from:this.s[k],keys,i:0,t0:this.now(),done}}
 later(d,fn,tag){this.q.push({at:this.now()+d,fn,tag})}
 ov(shape,d){this.eyeOv=shape;this.eyeUntil=this.now()+d}
 /** Holds a mouth pose for d ms, then eases back to the state's mouth. */
 mpose(v,d,i=150,o=250){for(const k in v)this.anim(k,[[v[k],i,'out'],[v[k],Math.max(0,d-i-o),'lin'],[this.tg[k],o,'inOut']])}

 blep(){this.note('blep');this.anim('tongue',[[.7,150,'out'],[.7,1300,'lin'],[this.tg.tongue,220,'inOut']])}

 lick(){this.note('lick');this.anim('mouth',[[.16,90,'out'],[this.tg.mouth,170,'inOut']]);this.anim('tongue',[[1,90,'out'],[this.tg.tongue,180,'inOut']])}
 slowBlink(){this.note('slowblink');this.anim('lid',[[.75,380,'inOut'],[.75,320,'lin'],[0,480,'inOut']])}
 eyeShape(){return this.eyeOv&&this.now()<this.eyeUntil?this.eyeOv:this.prof.eye(this.state)}
 blink(){if(this.tw.open)return;this.note('blink');this.anim('open',[[.06,70,'inOut'],[1,130,'out']])}
 twitch(ear){this.note('twitch:'+ear);const b=this.tg[ear];this.anim(ear,[[b+.5,60,'out'],[b,280,'back']]);this.anim('wh',[[.25,60,'out'],[0,300,'inOut']])}
 emit(k,n){for(let i=0;i<n;i++)this.parts.push({k,x:(this.rand()-.5)*.9+(k==='z'?.55:0)+this.s.ox/1.3,y:-.85-this.rand()*.2+this.s.oy/1.3,vx:(this.rand()-.5)*.35+(k==='z'?.18:0),vy:-(.45+this.rand()*.35),age:-.14*i,life:1.3+this.rand()*.5,size:.15+this.rand()*.08,rot:this.rand()*6})}
 setBadge(b){const tok=++this.bt;this.anim('badgeS',[[0,90,'inOut']]);this.later(100,()=>{if(tok!==this.bt)return;this.badge=b;if(b)this.anim('badgeS',[[1,280,'back']])})}
 setState(st,force){if(!own(COL,st))return;if(!force&&st===this.state)return;const prev=this.state;this.state=st;this.q=this.q.filter(x=>x.tag!=='st');if(st!=='dizzy')this.dizzyUntil=0;
  this.colT=hex(COL[st]);this.s.tint=TINT[st];const b=BADGE[st]||null;if(b!==this.badge||force)this.setBadge(b);
  for(const k of ['oy','ox','roll','sx','sy','tilt','earF','earU','lid',...MKEYS])delete this.tw[k];this.s.roll=0;
  {const wc=workClockStep({busySince:this.busySince,workedFor:this.workedFor},st,this.now());this.busySince=wc.busySince;this.workedFor=wc.workedFor}
  if(this.eyeUntil!==Infinity)this.eyeOv=null;
  this.prof.enter(this,st,prev)}
 emote(n){this.note('emote:'+n);if(n==='hello')return this.greet();if(n==='zoomies')return this.zoomies();if(n==='hairball')return this.hairball();this.prof.emote(this,n);if(own(EMOUTH,n)){const m=EMOUTH[n];this.mpose(m[0],m[1])}}
 slap(){this.interruptGreet();const t=this.now();this.slaps=this.slaps.filter(x=>t-x<1700);this.slaps.push(t);const [a,b]=this.prof.squash;
  this.anim('sy',[[a,70,'out'],[1.1,130,'out'],[1,170,'inOut']]);this.anim('sx',[[b,70,'out'],[.95,130,'out'],[1,170,'inOut']]);
  if(this.state==='dizzy')return;
  if(this.slaps.length>=3){this.slaps=[];this.saved=this.state;this.setState('dizzy');this.dizzyUntil=t+3300;return}
  const M=this.pm();if(M.poke==='love')return this.emote('love');this.emote('annoyed');if(M.pokeHiss)this.mpose({mouth:.6,smile:-1,mround:0},500,60,180)}
 /** Idle habits that come from personality: yawns, zoomies, mews, purrs, hmphs, winks. */
 persAmbient(t){const I=this.pm().idle;if(this.state!=='idle'||t<this.nextPers)return;this.nextPers=t+this.u(6000,11000);const r=this.rand();
  if(I.yawn&&r<.5)return this.emote('yawn');
  if(I.zoomies&&r<.35)return this.zoomies();
  if(I.mew&&r<.6)return this.mpose({mouth:.42,mround:.4,smile:.2},420,100,180);
  if(I.purr&&r<.55){this.anim('lid',[[.75,380,'inOut'],[.75,600,'lin'],[0,480,'inOut']]);return this.anim('purr',[[1,200,'out'],[1,1000,'lin'],[0,300,'inOut']])}
  if(I.hmph&&r<.55)return this.mpose({smile:-.85,mskew:-.7},1000);
  if(I.wink&&r<.5){this.ov('wink',550);this.blep()}}
 /** Paw wave, upstream BotEngine.greet() timings with paws for hands. */
 greet(){const t=this.now(),tok=++this.greetTok,a=this.anim.bind(this),ok=()=>tok===this.greetTok;this.waveStart=t+450;this.waveUntil=t+1550;
  this.ov('happy',2000);a('oy',[[-.06,220,'out'],[0,220,'back']]);
  this.later(250,()=>{if(!ok())return;a('paws',[[1,280,'out']]);a('sy',[[.95,100,'out'],[1,260,'back']]);a('sx',[[1.04,100,'out'],[1,260,'back']]);if(this.motion==='playful')a('earU',[[1.15,200,'out'],[1.15,900,'lin'],[1,400,'inOut']])});
  this.later(450,()=>{if(ok())this.mpose({mouth:.45,mround:.45,smile:.35},650,90,200)});
  this.later(550,()=>{if(ok())this.blink()});this.later(1500,()=>{if(ok())this.blink()});
  this.later(1550,()=>{if(!ok())return;this.waveUntil=0;a('paws',[[0,200,'inOut']])});
  this.later(1750,()=>{if(ok())this.ov('happy',300)})}
 interruptGreet(){if(this.s.paws<=.01&&this.now()>=this.waveUntil)return;this.greetTok++;this.waveUntil=0;this.waveStart=0;this.anim('paws',[[0,150,'inOut']])}
 /** File catch: open wide while a file hovers, snap on the drop, gulp and chew on arrival. */
 catchOpen(on){if(on===this.catching)return;this.catching=on;
  if(on){this.slotT=.55;this.eyeOv='wide';this.eyeUntil=Infinity;this.anim('oy',[[-.05,160,'out'],[-.03,200,'inOut']])}
  else{this.slotT=0;if(this.eyeUntil===Infinity){this.eyeOv=null;this.eyeUntil=0}}}
 catchDrop(){this.catching=true;this.slotT=1.05;this.eyeOv='wide';this.eyeUntil=Infinity}
 catchArrive(){this.catching=false;this.slotT=0;const t=this.now(),a=this.anim.bind(this);this.chewStart=t+80;this.chewUntil=t+930;this.ov('happy',1250);
  a('sy',[[.8,80,'out'],[1.16,130,'out'],[1,220,'back']]);a('sx',[[1.24,80,'out'],[.92,130,'out'],[1,220,'back']]);
  if(this.motion==='playful'){a('earU',[[1.15,150,'out'],[1,500,'inOut']]);a('blush',[[.6,200,'out'],[0,800,'inOut']])}
  this.later(950,()=>this.lick());this.later(1000,()=>this.emit('spark',3))}
 catchReject(ext){this.catching=false;this.slotT=0;this.eyeOv=null;this.eyeUntil=0;this.later(120,()=>this.hairball(ext))}
 /** Hairball: ears back, three heaves, then it comes up (with the file, if it was one). */
 hairball(file){this.note('hairball');const a=this.anim.bind(this),pl=this.motion==='playful',tok=++this.hbTok,tg=this.tg;
  this.ov('closed',1300);if(pl)a('earF',[[.7,150,'out'],[.7,1000,'lin'],[tg.earF,400,'inOut']]);
  a('oy',[[.06,140,'out'],[0,180,'inOut'],[.07,140,'out'],[0,180,'inOut'],[.09,140,'out'],[-.02,160,'inOut'],[.11,170,'out'],[0,320,'back']]);
  a('sy',[[.92,140,'out'],[1.04,180,'inOut'],[.9,140,'out'],[1.05,180,'inOut'],[.88,140,'out'],[1.06,160,'inOut'],[.86,170,'out'],[1,320,'back']]);
  a('sx',[[1.05,140,'out'],[.98,180,'inOut'],[1.07,140,'out'],[.97,180,'inOut'],[1.09,140,'out'],[.96,160,'inOut'],[1.1,170,'out'],[1,320,'back']]);
  a('mouth',[[.22,140,'out'],[0,180,'inOut'],[.28,140,'out'],[0,180,'inOut'],[.34,140,'out'],[0,160,'inOut'],[1.05,170,'out'],[1.05,160,'lin'],[tg.mouth,260,'inOut']]);
  a('mround',[[.3,140,'out'],[.3,800,'lin'],[0,170,'out'],[0,420,'lin'],[tg.mround,200,'inOut']]);
  a('smile',[[-.7,140,'out'],[-.7,970,'lin'],[.5,330,'inOut'],[.5,700,'lin'],[tg.smile,300,'inOut']]);
  this.later(1110,()=>{if(tok===this.hbTok)this.spitBall(file)});
  this.later(1450,()=>{if(tok!==this.hbTok)return;this.ov('happy',900);if(pl)a('blush',[[.45,200,'out'],[0,700,'inOut']]);this.later(320,()=>this.lick())})}
 spitBall(file){const m=this._mouth,b0=this._base;if(!m||!b0)return;const R=b0.R,dir=this.rand()<.5?-1:1,mx=(m.x-b0.x)/R,my=(m.y-b0.y)/R;
  this.balls.push({x:mx,y:my,vx:dir*this.u(.55,.85),vy:this.u(-.9,-.6),rot:0,age:0,life:file?2.6:2.4,file:file||null,seed:(this.rand()*1e9)|0,floor:this.p.ruff?1.34:1.12});
  for(let i=0;i<4;i++)this.parts.push({k:'hair',x:mx/1.3+(this.rand()-.5)*.15,y:my/1.3,vx:(this.rand()-.5)*.5,vy:this.u(-.35,-.15),age:-.05*i,life:.9+this.rand()*.4,size:.12+this.rand()*.05,rot:this.rand()*6})}
 /** Zoomies: pupils blown, ears back, side-to-side dashes with skids, then a happy flop. */
 zoomies(){this.note('zoomies');const a=this.anim.bind(this),pl=this.motion==='playful',tok=++this.zoomTok,tg=this.tg;this.interruptGreet();
  this.zoomUntil=this.now()+1950;this.ov('wide',1900);
  a('pupil',[[1,120,'out'],[1,1750,'lin'],[tg.pupil,400,'inOut']]);a('earF',[[.55,150,'out'],[.55,1750,'lin'],[tg.earF,400,'inOut']]);
  a('ox',[[-.05,70,'inOut'],[.04,70,'inOut'],[-.05,70,'inOut'],[.04,70,'inOut'],[0,60,'inOut'],[.88,240,'in'],[.97,90,'out'],[.84,110,'inOut'],[-.88,380,'inOut'],[-.97,90,'out'],[-.84,110,'inOut'],[.3,320,'inOut'],[0,260,'back']]);
  this.mpose({mouth:.32,tongue:.9,smile:.6,mround:0},1950,150,300);
  this.later(670,()=>{if(tok===this.zoomTok)this.dust(1)});this.later(1250,()=>{if(tok===this.zoomTok)this.dust(-1)});
  this.later(1950,()=>{if(tok!==this.zoomTok)return;this.ov('happy',900);a('sy',[[.84,90,'out'],[1.06,150,'out'],[1,220,'back']]);a('sx',[[1.14,90,'out'],[.96,150,'out'],[1,220,'back']]);this.emit('spark',3);if(pl)a('blush',[[.5,200,'out'],[0,800,'inOut']])})}
 dust(dir){const y=(this.p.ruff?1.1:.88)/1.3;for(let i=0;i<4;i++)this.parts.push({k:'dust',x:(this.s.ox+dir*.45)/1.3+(this.rand()-.5)*.2,y:y+(this.rand()-.5)*.06,vx:-dir*this.u(.12,.35),vy:-this.u(.03,.12),age:-i*.04,life:.55+this.rand()*.2,size:.09+this.rand()*.05,rot:0})}
 /** How open the mouth is right now: the state's mouth plus its motion, or the file-catch spring and chew, whichever is wider. */
 mouthOpen(){return Math.max(this.s.mouth+(this.mfx||0),this.slotH+this.chew)}
 /**
  * Fills `tg`, the targets the pose eases toward, for the current state: the profile's rest pose, the state's mouth,
  * the personality, and the file-catch, wave and zoomies overrides. t is the clock in ms, T the same in seconds.
  * It reads the engine's inputs (state, lookX/lookY, personality) and never the tweens, so fixtures can call it directly.
  */
 computeTargets(t,T){const tg=this.tg,st=this.state,pf=this.prof;
  tg.sx=1;tg.sy=1;tg.es=1;tg.purr=0;tg.lid=0;const Mo=MOUTH[st];MKEYS.forEach((k,i)=>tg[k]=Mo[i]);this.mfx=mouthFx(st,T);
  let [ty,tp]=pf.targets(this,st,T,tg);
  // Personality: gaze, resting mouth, lids, ears, bounce, pupils, blush and chatter.
  const M=this.pm();ty*=M.gaze;tp*=M.gaze;
  tg.smile+=M.smile;tg.mskew+=M.skew;
  if(st!=='sleeping')tg.lid=Math.max(tg.lid,M.lid);
  tg.earF=Math.max(tg.earF,M.earBack);tg.oy*=M.hop;tg.pupil=clamp(tg.pupil+M.pupil,.1,1);
  this.blushBase=st==='sleeping'?0:M.blush;this.mfx*=M.chatter;
  if(this.mini&&!['thinking','searching','sleeping','dizzy'].includes(st)){if(t>this.miniNext){this.miniLook={x:this.u(-.88,.88),y:this.u(-.55,.45)};this.miniNext=t+this.u(500,2000)}ty=this.miniLook.x*.62;tp=this.miniLook.y*.5;tg.sy=1+Math.sin(2.2*T)*.04;tg.sx=1-Math.sin(2.2*T)*.02}
  if(this.catching){tg.earU=1.25;tg.pupil=.95;ty*=.3;tp=tp*.3+.12}
  if(t>this.waveStart&&t<this.waveUntil){const wt=(t-this.waveStart)/1000;tg.tilt=-.06+Math.sin(TAU*1.2*wt)*.07}
  if(t<this.zoomUntil){const zv=this.zv;ty=clamp(zv*.25,-.62,.62);tp=-.05;tg.tilt=clamp(zv*.05,-.2,.2);tg.sx=1+Math.min(.16,Math.abs(zv)*.045);tg.sy=1-Math.min(.09,Math.abs(zv)*.025);tg.oy=-Math.abs(Math.sin(T*TAU*4.5))*.05*Math.min(1,Math.abs(zv)/1.5)}
  tg.yaw=ty;tg.pitch=tp}
 /** One frame. dt is seconds; anything outside 0…0.25 (a sleeping laptop, a clock that stepped back, NaN) is held to that range. */
 update(dt){dt=Number.isFinite(dt)?Math.min(Math.max(dt,0),.25):0;
  const t=this.now(),T=t/1000,s=this.s,tg=this.tg,st=this.state,pf=this.prof;
  for(const k in this.tw){const w=this.tw[k];let el=t-w.t0;while(w.i<w.keys.length){const key=w.keys[w.i],d=Math.max(1,key[1]);if(el<d){s[k]=lerp(w.from,key[0],EZ[key[2]](el/d));break}el-=d;w.t0+=d;w.from=key[0];s[k]=key[0];w.i++}if(w.i>=w.keys.length){delete this.tw[k];w.done&&w.done()}}
  const v=(s.ox-(this._ox??s.ox))/Math.max(dt,1e-3);this._ox=s.ox;this.zv+=(v-this.zv)*Math.min(1,dt*18);
  const due=this.q.filter(x=>x.at<=t);this.q=this.q.filter(x=>x.at>t);due.forEach(x=>x.fn());
  this.computeTargets(t,T);
  const M=this.pm(),ke=M.speed,kL=1-Math.pow(.0025,dt*ke),kG=1-Math.pow(.0008,dt*ke),kC=1-Math.pow(.002,dt);
  for(const k of ['yaw','pitch'])if(!this.tw[k])s[k]+=(tg[k]-s[k])*kL;
  for(const k of ['tilt','sx','sy','es','oy','earL','earR','earU','earF','pupil','purr','lid',...MKEYS])if(!this.tw[k])s[k]+=(tg[k]-s[k])*kG;
  pf.post(this,st,T,kG);
  const gT=hex(GLOW[st]||'#FFFFFF'),gaT=st==='dizzy'?0:(st==='idle'||st==='sleeping'?.12:.42);
  for(let i=0;i<3;i++){this.col[i]+=(this.colT[i]-this.col[i])*kC;this.gc[i]+=(gT[i]-this.gc[i])*kC}this.ga+=(gaT-this.ga)*kC;
  if(!this.quiet&&t>=this.nextBlink){if(st!=='sleeping'&&st!=='dizzy'){this.blink();if(this.rand()<.22)this.later(230,()=>this.blink())}this.nextBlink=t+(2200+this.rand()*3200)*M.blinkEvery}
  if(this.eyeOv&&t>this.eyeUntil)this.eyeOv=null;
  if(!this.quiet){pf.ambient(this,t);this.persAmbient(t)}
  if(this.dizzyUntil&&t>this.dizzyUntil){const b=this.saved||'idle';this.dizzyUntil=0;this.setState(b,true);this.emote('happy')}
  for(const p of this.parts)p.age+=dt;this.parts=this.parts.filter(p=>p.age<p.life);
  for(const b of this.balls){b.age+=dt;b.vy+=5.5*dt;b.x+=b.vx*dt;b.y+=b.vy*dt;if(b.y>b.floor){b.y=b.floor;if(b.vy>.6){b.vy*=-.38;b.vx*=.7}else{b.vy=0;b.vx*=Math.pow(.2,dt)}}b.rot+=b.vx*dt*5}
  this.balls=this.balls.filter(b=>b.age<b.life);
  // Mouth spring, ω₀ = 2π/0.25, ζ = 0.6 (upstream slot spring).
  const om=TAU/.25,acc=om*om*(this.slotT-this.slotH)-2*.6*om*this.slotV;this.slotV+=acc*dt;this.slotH=Math.max(0,this.slotH+this.slotV*dt);
  this.chew=t>=this.chewStart&&t<this.chewUntil?.16*(.5-.5*Math.cos(TAU*4.2*(t-this.chewStart)/1000)):0}}

/** Paw positions for the engine's wave (upstream greet timings), head-local. */
function enginePaws(e,R,rx,ry){const s=e.s;if(s.paws<=.01)return[];const n=e.now(),bodyH=2*ry,waving=e.waveStart>0&&n>=e.waveStart&&n<e.waveUntil,out=[];
 for(const sd of [-1,1]){let x=sd*rx*1.0,y=ry*.78,rot=0,beans=false;
  if(sd>0&&waving){const wt=(n-e.waveStart)/1000,rise=EZ.out(Math.min(1,wt/.18));x=lerp(x,rx*1.12+Math.cos(13*wt)*.06*bodyH,rise);y=lerp(y,-ry*.12-Math.sin(13*wt)*.12*bodyH,rise);rot=(.35+Math.sin(13*wt)*.3)*rise;beans=rise>.5}
  else if(sd<0&&waving)y+=Math.sin(6*(n-e.waveStart)/1000)*.04*bodyH;
  out.push({x,y,k:s.paws,rot,beans})}return out}

Object.assign(api,{CLASSIC,PLAYFUL,PROFILES,cfg,CatEngine,enginePaws});
```

- [ ] **Step 4: Add the fixture builders**

Insert the block below into `scripts/gen-cat-fixtures.mjs`, immediately above the line containing `@@BUILDERS`:

```js
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
```

- [ ] **Step 5: Write the fixtures and run everything**

Run: `node scripts/gen-cat-fixtures.mjs && bash scripts/test-cat-contract.sh`
Expected: `wrote 7 fixture files to tests/fixtures/cat`, then `# tests 69`, `# pass 69`, `# fail 0`, seven `✓` fixture lines, `✓ 7 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`. `motion-cases.json` is about 175 KB and `sequence-cases.json` about 50 KB.

- [ ] **Step 6: One-off check of the engine against the prototype (not committed)**

This is the check that matters most in this task. It builds the prototype's own engine from git next to the core's, gives both the same fake clock and the same seeded `rand`, and compares the whole pose every frame. The scenarios cover all 11 states, every emote, the pokes, both catch paths, wake-up, every personality and both motion styles, on five cats and with mini cats. Because the two share one `rand` stream, a single reordered random call would make them drift.

```bash
T=${TMPDIR:-/tmp}/a0-check; mkdir -p "$T"
git show 683163f:design/prototype/notchmeow.html > "$T/old.html"
cat > "$T/equiv-engine.mjs" <<'EOF'
// One-off, not committed: the engine in cat-core.js against the pre-A-0 prototype's engine, frame by frame, in Node.
// Both run on one fake clock and the same seeded rand, so every random choice must come out in the same order.
// Usage: node equiv-engine.mjs <cat-core.js> <old notchmeow.html>
import fs from 'node:fs'; import vm from 'node:vm'; import { createRequire } from 'node:module';
const require = createRequire(import.meta.url), core = require(process.argv[2]);
const lines = fs.readFileSync(process.argv[3], 'utf8').split('\n'), pick = (a, b) => lines.slice(a - 1, b).join('\n');
const clock = { t: 0 }; let rand = () => 0;
const sandbox = { CLOCK: clock, RAND: () => rand() };
vm.createContext(sandbox);
// The prototype's own text: helpers, state tables, presets, mouth tables, profiles, personality and the engine.
vm.runInContext(['const TAU=Math.PI*2,RN=()=>RAND(),ms=()=>CLOCK.t;', pick(116, 120), pick(126, 130), pick(133, 214), pick(467, 479), pick(481, 556), pick(558, 571), pick(573, 693),
  ';globalThis.OLD={CatEngine,PRESETS,PERSONAS,PERS,OVERRIDE,setMotion:v=>{MOTION=v}};'].join('\n'), sandbox);
const OLD = sandbox.OLD, KEYS = Object.keys(core.newPose());
const oldId = { latte: 'siamese', patches: 'calico', cloud: 'ragdoll', leo: 'bengal', button: 'fold', puff: 'persian', noodle: 'sphynx' };
let worst = 0, frames = 0, bad = 0;

function scenario(profile, persona, id, mini) {
  const was = oldId[id] || id, seed = 11, oldRand = core.rng(seed), newRand = core.rng(seed);
  Object.assign(core.cfg, { motion: profile, override: {}, pers: { [id]: core.personaNamed(persona) }, zoomAfter: 12000 });
  OLD.setMotion(profile); for (const k of Object.keys(OLD.OVERRIDE)) delete OLD.OVERRIDE[k]; for (const k of Object.keys(OLD.PERS)) delete OLD.PERS[k];
  OLD.PERS[was] = { preset: persona, ...OLD.PERSONAS[persona] };
  clock.t = 0; rand = oldRand;
  const o = new OLD.CatEngine(OLD.PRESETS[was], { mini }), n = new core.CatEngine(core.PRESETS[id], { mini, now: () => clock.t, rand: newRand, cfg: core.cfg });
  for (const e of [o, n]) { e._base = { x: 0, y: 0, R: 1 }; e._mouth = { x: 0, y: .35 }; }
  const script = {}, at = (f, fn) => (script[f] = (script[f] || []).concat(fn));
  core.STATES.forEach((st, i) => at(20 + i * 150, e => e.setState(st)));
  [['love', 1800], ['happy', 1950], ['surprised', 2100], ['proud', 2250], ['wink', 2400], ['yawn', 2550], ['annoyed', 2700], ['hello', 2850], ['zoomies', 3200], ['hairball', 3500]].forEach(([em, f]) => at(f, e => e.emote(em)));
  at(4000, e => e.slap()); at(4010, e => e.slap()); at(4020, e => e.slap());
  at(4300, e => e.catchOpen(true)); at(4360, e => e.catchDrop()); at(4383, e => e.catchArrive());
  at(4600, e => e.catchOpen(true)); at(4640, e => e.catchDrop()); at(4663, e => e.catchReject('EXE'));
  at(4900, e => e.setState('working')); at(5600, e => e.setState('thinking')); at(5800, e => e.setState('approval')); at(5900, e => e.setState('working')); at(6000, e => e.setState('finished'));
  at(6300, e => e.setState('sleeping')); at(6500, e => e.setState('idle'));
  for (let f = 1; f <= 7500; f++) {
    clock.t = f * 1000 / 60;
    for (const fn of script[f] || []) { rand = oldRand; fn(o); rand = newRand; fn(n); }
    rand = oldRand; o.update(1 / 60); rand = newRand; n.update(1 / 60); frames++;
    for (const k of KEYS) { const d = Math.abs(o.s[k] - n.s[k]); if (!(d <= 1e-12)) { bad++; if (bad < 8) console.log('DIFF', profile, persona, id, 'frame', f, k, o.s[k], n.s[k]); } worst = Math.max(worst, d || 0); }
    if (o.eyeShape() !== n.eyeShape() || o.parts.length !== n.parts.length || o.balls.length !== n.balls.length || o.state !== n.state) { bad++; if (bad < 8) console.log('STRUCT', profile, persona, id, 'frame', f); }
    for (let i = 0; i < 3; i++) if (Math.abs(o.col[i] - n.col[i]) > 1e-9 || Math.abs(o.gc[i] - n.gc[i]) > 1e-9) bad++;
    if (Math.abs(o.mfx - n.mfx) > 1e-12 || Math.abs((o.slotH + o.chew) - (n.slotH + n.chew)) > 1e-12) bad++;
  }
  if (oldRand() !== newRand()) { bad++; console.log('the random sequences drifted apart', profile, persona, id); }
}
for (const profile of ['playful', 'classic']) for (const persona of Object.keys(core.PERSONAS)) { scenario(profile, persona, 'momo', false); scenario(profile, persona, 'shrimpy', false); }
for (const id of ['latte', 'noodle', 'puff']) scenario('playful', 'balanced', id, false);
scenario('playful', 'hyper', 'momo', true); scenario('classic', 'balanced', 'shrimpy', true);
console.log(`engine: ${frames} frames compared, worst difference ${worst}, problems ${bad}`);
process.exit(bad ? 1 : 0);
EOF
node "$T/equiv-engine.mjs" "$PWD/design/prototype/cat-core.js" "$T/old.html"
```

Expected: `engine: 217500 frames compared, worst difference 0, problems 0`. It takes a few seconds. Any `DIFF`, `STRUCT` or "random sequences drifted apart" line means the move changed behaviour: fix the core, not the check.

- [ ] **Step 7: Commit**

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/motion.test.mjs tests/fixtures/cat/motion-cases.json tests/fixtures/cat/sequence-cases.json
git commit -m "feat(cat): motion profiles and the engine in cat-core.js, with motion and sequence fixtures

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Refactor the prototype page to use the core

**Files:**
- Modify: `design/prototype/notchmeow.html` (about 470 lines come out, about 60 go in; 542 lines remain)

**Interfaces:**
- Consumes `CatCore` from `design/prototype/cat-core.js`, loaded with `<script src="cat-core.js">`: `TAU`, `EZ`, `lerp`, `clamp`, `seg`, `hex`, `rng`, `COL`, `STATES`, `PRESETS`, `MORE`, `kittenOf`, `MOMO_WHITE`, `CatEngine`, `PROFILES`, `PERSONAS`, `TRAITS`, `COMPACT`, `GT`, `STREAKS`, `GREET_LEN`, `FLIGHT_MS`, `cfg`, and through `CatCore.`: `supPoints`, `earGeom`, `pupilOffset`, `layout`, `enginePaws`, `cursorLook`, `flightAt`, `greetingPose`, `streakTime`.
- Produces: the page, with the same look and the same controls, plus the new default greeting. Its globals are unchanged where other code reads them: `CatEngine`, `PRESETS`, `drawCat`, `gcReplay`, `curState`, `mx`.
- What changes on the page, and nothing else: the pure code is gone and read from the core; `drawCat`, `drawEar`, `almondEye`, `look` and `drawFlights` call the core instead of repeating its maths; the island's greeting is the new one; the "Greeting: current vs new" panel is replaced by a "Greeting" panel with one canvas, the new greeting, and a short list of its five beats. The old greeting timeline is dropped, as the spec says. The page does not apply the compact ear scale.

The page is refactored by a one-off script, not by hand: about 470 of its lines move to the core and the renderer stays line for line. The script checks the hash of the old page and that each replacement matches exactly one place. Its own text shows every line that is new.

The check that "the page behaves exactly as before" is pixel based. A headless browser loads the old page and the new page with a **virtual clock** (`performance.now` and `requestAnimationFrame` are replaced, so a frame is exactly 1/60 s) and an **order-independent `Math.random`** (its value depends only on the virtual time, so dropping the second greeting engine cannot shift anybody else's random choices). It drives every state, emote, the pokes, both catches, the personalities, both motion styles, fur lines, the island and the greeting, and takes 146 screenshots. The old page is run twice first, to prove the check itself is steady.

- [ ] **Step 1: Set up the one-off check and take the baseline**

```bash
T=${TMPDIR:-/tmp}/a0-check; mkdir -p "$T"
git show 683163f:design/prototype/notchmeow.html > "$T/old.html"
shasum -a 256 "$T/old.html"
```

Expected: `3a166ac73491597087fd50f5a65aa192d05ac452ce0ef7636dbe149173f53475`. If it differs, stop: the prototype is not at `683163f`.

Write the three one-off files:

```bash
T=${TMPDIR:-/tmp}/a0-check
cat > "$T/shots.js" <<'EOF'
async page => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.addInitScript(() => {
    let t = 0; const cbs = [];
    performance.now = () => t;
    window.requestAnimationFrame = cb => { cbs.push(cb); return cbs.length; };
    window.__step = (n, dt = 1000 / 60) => { for (let i = 0; i < n; i++) { t += dt; const q = cbs.splice(0); q.forEach(f => f(t)); } };
    // Order-independent: the value depends only on the virtual time, so removing or adding an engine cannot shift anyone else's dice.
    Math.random = () => { const x = Math.sin(t * 12.9898 + 78.233) * 43758.5453; return x - Math.floor(x); };
  });
  const errors = [];
  page.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') errors.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  await page.goto('file://__PAGE__');
  const OUT = '__OUT__';
  const step = n => page.evaluate(n => window.__step(n), n);
  const SEL = ['#figMomo', '#figShrimpy', '#more', '#desk', '#ladder'];
  const shot = async (tag, sels = SEL) => { for (const s of sels) await page.locator(s).screenshot({ path: `${OUT}/${tag}-${s.slice(1)}.png` }); };
  const calm = async () => { await page.evaluate(() => { mx = null; }); await step(60); };
  const btn = (row, text) => page.locator(`#${row} button`, { hasText: new RegExp('^' + text + '$') }).click();
  await step(90); await calm(); await shot('01-idle');
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.mouse.move(900, 300); await step(40); await shot('02-look', ['#figMomo', '#figShrimpy']);
  for (const st of ['working', 'thinking', 'searching', 'approval', 'question', 'error', 'finished', 'ratelimit', 'sleeping', 'dizzy']) {
    await btn('stRow', st); await step(100); await calm(); await shot('03-state-' + st);
  }
  await btn('stRow', 'idle'); await step(60);
  for (const em of ['love', 'happy', 'surprised', 'proud', 'wink', 'yawn', 'annoyed', 'hello \\(paw wave\\)']) {
    await btn('emRow', em); await step(34); await calm(); await shot('04-emote-' + em.split(' ')[0], ['#figMomo', '#figShrimpy', '#desk']);
  }
  for (const [em, frames] of [['zoomies', 45], ['zoomies', 90], ['hairball', 70], ['hairball', 110]]) {
    await btn('emRow', em); await step(frames); await shot(`05-${em}-${frames}`, ['#figMomo', '#figShrimpy', '#more']); await step(240);
  }
  await btn('emRow', 'catch a file'); await page.waitForTimeout(700); await step(14); await shot('06-catch-fly', ['#figMomo', '#figShrimpy']); await step(40); await shot('06-catch-chew', ['#figMomo', '#figShrimpy']); await step(120);
  await btn('emRow', 'catch an unsupported file'); await page.waitForTimeout(700); await step(60); await shot('06-reject', ['#figMomo', '#figShrimpy']); await step(200);
  for (const ps of ['Grumpy', 'Hyper', 'Chill', 'Sweet', 'Chatty']) { await btn('ppRow', ps); await step(80); await calm(); await shot('07-pers-' + ps, ['#figMomo', '#figShrimpy']); }
  await btn('ppRow', 'Balanced');
  await btn('moRow', 'Classic');
  for (const st of ['idle', 'thinking', 'approval', 'finished', 'dizzy']) { await btn('stRow', st); await step(100); await calm(); await shot('08-classic-' + st, ['#figMomo', '#figShrimpy', '#more']); }
  await btn('emRow', 'hairball'); await step(70); await shot('08-classic-hairball', ['#figMomo', '#figShrimpy']);
  await btn('moRow', 'Playful'); await btn('stRow', 'idle'); await step(120);
  await btn('opts', 'Fur lines'); await step(5); await shot('09-fur', ['#figMomo', '#figShrimpy', '#ladder']); await btn('opts', 'Plain');
  await page.locator('#desk').click({ position: { x: 640, y: 120 } }); await step(60); await calm(); await shot('10-island-expand', ['#desk']);
  await page.locator('#desk').click({ position: { x: 640, y: 120 } }); await step(60); await shot('10-island-collapse', ['#desk']);
  for (const ch of ['Momo', 'Latte', 'Noodle', 'Cloud']) { await btn('chRow', ch); await step(60); await calm(); await shot('11-char-' + ch, ['#desk']); }
  await page.evaluate(() => gcReplay());
  { let fr = 0; for (const [tag, target] of [['0p5', 30], ['1p0', 60], ['1p7', 102], ['2p2', 132], ['3p0', 180], ['4p0', 240], ['5p0', 300], ['5p7', 342]]) { await step(target - fr); fr = target; await page.locator('__GC__').screenshot({ path: `${OUT}/13-greet-panel-${tag}.png` }); } }
  await btn('nkRow', 'Play greeting'); await step(120); await shot('12-island-greeting-2s', ['#desk']);
  await step(60); await shot('12-island-greeting-3s', ['#desk']); await step(120); await shot('12-island-greeting-5s', ['#desk']);
  const dump = await page.evaluate(() => JSON.stringify({ canvases: document.querySelectorAll('canvas').length, state: curState }));
  return JSON.stringify({ dump, errors });
}
EOF
cat > "$T/png-compare.mjs" <<'EOF'
// One-off, not committed: compares two folders of same-named PNG screenshots, pixel by pixel.
// Usage: node png-compare.mjs <folderA> <folderB> [skip-regex]
// identical: same pixels. noise: at most 40 pixels off by at most 16 levels (text anti-aliasing).
// faint: off by one level out of 255 (gradient dithering). different: anything else, which fails the run.
import fs from 'node:fs'; import zlib from 'node:zlib';

function decode(file) {
  const b = fs.readFileSync(file); let p = 8, W, H, type, idat = [];
  while (p < b.length) {
    const len = b.readUInt32BE(p), kind = b.toString('ascii', p + 4, p + 8), d = b.subarray(p + 8, p + 8 + len);
    if (kind === 'IHDR') { W = d.readUInt32BE(0); H = d.readUInt32BE(4); type = d[9]; } else if (kind === 'IDAT') idat.push(d);
    p += 12 + len;
  }
  const bpp = { 0: 1, 2: 3, 4: 2, 6: 4 }[type], stride = W * bpp, raw = zlib.inflateSync(Buffer.concat(idat)), out = Buffer.alloc(H * stride);
  for (let y = 0; y < H; y++) {
    const filter = raw[y * (stride + 1)], src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const row = out.subarray(y * stride, (y + 1) * stride), prev = y ? out.subarray((y - 1) * stride, y * stride) : Buffer.alloc(stride);
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? row[x - bpp] : 0, u = prev[x], c = x >= bpp ? prev[x - bpp] : 0; let v = src[x];
      if (filter === 1) v += a; else if (filter === 2) v += u; else if (filter === 3) v += (a + u) >> 1;
      else if (filter === 4) { const pa = Math.abs(u - c), pb = Math.abs(a - c), pc = Math.abs(a + u - 2 * c); v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? u : c); }
      row[x] = v & 255;
    }
  }
  return { W, H, bpp, data: out };
}

function diff(fa, fb) {
  const A = decode(fa), B = decode(fb);
  if (A.W !== B.W || A.H !== B.H) return { n: -1, size: [A.W, A.H, B.W, B.H] };
  let n = 0, max = 0;
  for (let i = 0; i < A.W * A.H; i++) {
    let m = 0;
    for (let k = 0; k < Math.min(A.bpp, 3); k++) m = Math.max(m, Math.abs(A.data[i * A.bpp + k] - B.data[i * B.bpp + k]));
    if (m > 0) { n++; max = Math.max(max, m); }
  }
  return { n, max };
}

const [A, B, skip] = process.argv.slice(2);
const tally = { identical: 0, noise: 0, faint: 0, different: 0, missing: 0 };
for (const f of fs.readdirSync(A).filter(f => f.endsWith('.png')).sort()) {
  if (skip && new RegExp(skip).test(f)) continue;
  if (!fs.existsSync(`${B}/${f}`)) { tally.missing++; console.log('MISSING', f); continue; }
  const d = diff(`${A}/${f}`, `${B}/${f}`);
  if (d.n === 0) tally.identical++;
  else if (d.n > 0 && d.max <= 1) { tally.faint++; console.log('faint', f, `${d.n} px, one level`); }
  else if (d.n > 0 && d.n <= 40 && d.max <= 16) { tally.noise++; console.log('noise', f, `${d.n} px, up to ${d.max} levels`); }
  else { tally.different++; console.log('DIFFERENT', f, JSON.stringify(d)); }
}
console.log(Object.entries(tally).map(([k, v]) => `${k}=${v}`).join(' '));
process.exit(tally.different || tally.missing ? 1 : 0);
EOF
cat > "$T/make-page.py" <<'EOF'
#!/usr/bin/env python3
"""One-off, not committed: turns the pre-A-0 prototype page into the refactored one.

Usage: python3 make-page.py <old notchmeow.html> <new notchmeow.html>

The old file is the page at 683163f. Line numbers below are 1-based lines of that file, so the script
first checks its hash. Most of the page is the renderer, which is kept line for line; what changes is:
  - everything pure (presets, warp, tables, profiles, personality, engine, greeting) is removed and read from CatCore;
  - drawCat, drawEar, almondEye, look and drawFlights call CatCore instead of repeating its maths;
  - the greeting panel keeps one canvas, the new greeting, and the old greeting timeline is gone.
Every replacement is checked to match exactly one place, so a page that differs from 683163f fails loudly.
"""
import hashlib, sys

OLD_SHA256 = '3a166ac73491597087fd50f5a65aa192d05ac452ce0ef7636dbe149173f53475'
src = open(sys.argv[1], encoding='utf-8').read()
if hashlib.sha256(src.encode('utf-8')).hexdigest() != OLD_SHA256:
    sys.exit('This is not design/prototype/notchmeow.html at 683163f (use: git show 683163f:design/prototype/notchmeow.html).')
old = src.split('\n')


def L(a, b):
    """Lines a..b of the old page, inclusive."""
    return '\n'.join(old[a - 1:b])


def rep(text, was, now):
    """Replace one exact piece of text, which must occur exactly once."""
    assert text.count(was) == 1, (was[:90], text.count(was))
    return text.replace(was, now)


# ── Head: header comment, the Greeting panel, a little CSS ───────────────────
head = L(1, 111)
head = rep(head, """<!--
  NotchMeow, visual source of truth for Shrimpy and Momo.
  Everything is drawn in Canvas 2D, no images. The sections mirror the planned split in
  windows/src/cat/: presets (PRESETS, kittenOf), renderer (drawCat and helpers), motion
  profiles (CLASSIC, PLAYFUL), engine (CatEngine). Timings, easings and smoothing match
  upstream engine.ts: look 1-0.0025^dt, rest 1-0.0008^dt, colour 1-0.002^dt.
-->""", """<!--
  NotchMeow, visual source of truth for Shrimpy and Momo.
  Everything is drawn in Canvas 2D, no images. Everything that is not drawing lives in
  cat-core.js, loaded below: presets, geometry and the face warp, the state/mouth/emote tables,
  both motion profiles, personality, the engine, the greeting and the file flight. The apps are
  tested against fixtures generated from that file (docs/CAT-CONTRACT.md). This page keeps the
  renderer (drawCat and helpers) and the controls. Timings, easings and smoothing match
  upstream engine.ts: look 1-0.0025^dt, rest 1-0.0008^dt, colour 1-0.002^dt.
-->""")
head = rep(head, """<section class="panel">
<h2>Greeting: current vs new</h2>
<p class="tag">Same island, same cat, two launch greetings side by side. The new one falls in, bounces, slides aside, pops up for a quick paw wave, then slides back and settles with the same badge and tint.</p>
<div class="row" id="gcRow"><span class="h">Cat</span></div>
<div class="cmp">
<figure><canvas id="cvGA" aria-label="Current greeting"></canvas><figcaption><b>Current</b></figcaption></figure>
<figure><canvas id="cvGB" aria-label="New greeting"></canvas><figcaption><b>New</b> · Greeting v2 (upstream-inspired)</figcaption></figure>
</div>
</section>""", """<section class="panel">
<h2>Greeting</h2>
<p class="tag">The launch greeting, 5.74 s: a cat version of upstream's Greeting v2. The cat falls in with a landing squash, bounces, slides aside, pops up for a quick paw wave, then slides back and settles with the badge and tint. Same island and same cat as in the apps.</p>
<div class="row" id="gcRow"><span class="h">Cat</span></div>
<div class="cmp">
<figure><canvas id="cvG" aria-label="Launch greeting"></canvas><figcaption><b>Greeting</b> · 5.74 s</figcaption></figure>
<figure class="beats"><ol>
<li>Falls in and lands with a squash</li>
<li>A small bounce</li>
<li>Slides aside</li>
<li>Pops up and waves a paw</li>
<li>Slides back and settles</li>
</ol></figure>
</div>
</section>""")
head = rep(head, ".cmp figcaption b{color:var(--ink);font-weight:600}\n",
           ".cmp figcaption b{color:var(--ink);font-weight:600}\n.cmp .beats ol{margin:6px 0 0;padding-left:20px;color:var(--dim);font-size:13px;line-height:1.7}\n")

out = [head, '<script src="cat-core.js"></script>', '<script>', "'use strict';"]

# ── What the page takes from the core ────────────────────────────────────────
out.append("""// ── cat-core.js: everything that is not drawing ──────────────────────────────
const {TAU,EZ,lerp,clamp,seg,hex,rng,COL,STATES,PRESETS,MORE,kittenOf,MOMO_WHITE,CatEngine,PROFILES,PERSONAS,TRAITS,COMPACT,GT,STREAKS,GREET_LEN,FLIGHT_MS}=CatCore;
const ms=()=>performance.now(),nowS=()=>performance.now()/1000;
// Settings the engines read. The controls below change them.
const CFG=CatCore.cfg,OVERRIDE=CFG.override,PERS=CFG.pers;
CFG.zoomAfter=12000; // the apps use 5 minutes of work; shortened here so you can watch it
Object.assign(OVERRIDE,{momo:null,shrimpy:null});
""")

# ── Renderer: kept, with the maths replaced by calls into the core ───────────
out.append(L(121, 123))                 # rr, heartP, starP
out.append('')
out.append(L(216, 216))                 # "Renderer" comment
out.append("""/** Superellipse as a Path2D; the points come from CatCore.supPoints. */
function sup(rx,ry,n,dy,spike,count,steps=200,bend=null){const path=new Path2D();
 CatCore.supPoints(rx,ry,n,dy,spike,count,steps,bend).forEach(([x,y],i)=>i?path.lineTo(x,y):path.moveTo(x,y));
 path.closePath();return path}
""")
out.append(L(245, 248))                 # wEll, wBlob, wStroke
out.append(L(255, 275))                 # momoWhite, fur strands, taper
ear = L(276, 294)
ear = rep(ear, L(276, 277), "function drawEar(ctx,p,s,sd,R,rx,ry,full,yf,pf,front){const E=p.ear,{bx,by,rot,h,bw,tip,cx}=CatCore.earGeom(p,s,sd,R,yf,pf);")
out.append(ear)
eye = L(295, 327)
eye = rep(eye, "const px=clamp(e.s.yaw/.62,-1,1)*.24*w,py=-clamp(e.s.pitch/.5,-1,1)*.18*h;", "const [px,py]=CatCore.pupilOffset(e.s.yaw,e.s.pitch,w,h);")
out.append(eye)
out.append(L(334, 390))                 # drawBadge, drawParticles, drawMouth, drawBalls, the drawCat comment

cat = L(391, 464)                       # drawCat
cat = rep(cat, L(391, 393), "function drawCat(ctx,e,cx,cy,D,o={}){const p=e.p,s=e.s,T=nowS(),L=CatCore.layout(p,s,cx,cy,D,{T,detail:o.detail,badgeSide:o.badgeSide}),{R,full,rx,ry,yf,pf,pt,fa,W,steps}=L,cx0=L.base.x,cy0=L.base.y;\n e._base=L.base;e._at=L.at;cx=L.head.x;cy=L.head.y;")
cat = rep(cat, "const pt=wrapA(pf+s.lift+s.roll),W=mkWarp(p,yf,pt,R),fa=clamp((Math.cos(pt)-.05)/.3,0,1),steps=R<20?72:200,fur=", "const fur=")
cat = rep(cat, "ctx.translate(-Math.sin(s.yaw)*FACE.lean*1.1*R,Math.sin(s.pitch)*FACE.lean*.9*R);", "ctx.translate(L.ruff.dx,L.ruff.dy);")
cat = rep(cat, "steps,[Math.sin(yf)*FACE.bend,-Math.sin(pf)*FACE.bend*.7]);", "steps,L.bend);")
cat = rep(cat, "for(const q of (o.paws||enginePaws(e,R,rx,ry)))drawPaw(ctx,p,R,q);", "for(const q of (o.paws||CatCore.enginePaws(e,R,rx,ry)))drawPaw(ctx,p,R,q);")
a = cat.index(" for(const sd of [-1,1]){const th=sd*p.eye.th+yf")                     # eyes: from the layout
b = cat.index("  ctx.save();ctx.translate(ex,ey);ctx.scale(fx,fy);ctx.globalAlpha=fa;")
cat = cat[:a] + " for(const {sd,visible,x:ex,y:ey,fx,fy} of L.eyes){if(!visible)continue;\n" + cat[b:]
a = cat.index(" const nth=yf,nph=p.nosePh+pt,ncp=Math.cos(nph);")                    # nose and mouth: from the layout
b = cat.index("  ctx.globalAlpha=fa;\n  drawMouth(")
cat = cat[:a] + " if(L.nose.visible){const {nx,ny,nf,nw,nh,my}=L.nose,mo=e.mouthOpen();\n" + cat[b:]
cat = rep(cat, "  const lx=nx*s.sx,ly=(my+.12*R)*s.sy,c=Math.cos(s.tilt),sn=Math.sin(s.tilt);e._mouth={x:cx+lx*c-ly*sn,y:cy+lx*sn+ly*c}}", "  e._mouth=L.mouth}")
cat = rep(cat, "drawBadge(ctx,e.badge,e.badgeCol||COL[e.state],cx+(o.badgeSide||1)*1.4*R*s.sx,cy-.92*R*s.sy,R,s.badgeS*(full?1:1.25),!full,T);", "drawBadge(ctx,e.badge,e.badgeCol||COL[e.state],L.badge.x,L.badge.y,R,L.badge.k,L.badge.small,T);")
out.append(cat)
out.append('')

# ── Page: pointer, file flights, stage, notch mock-up ────────────────────────
out.append(L(695, 697))                 # page header, FUR/TINTON, fit
out.append(rep(L(698, 698), "e.lookX=Math.tanh((mx-(rect.left+e._at.x))/240);e.lookY=-Math.tanh((my-(rect.top+e._at.y))/180)}",
               "const g=CatCore.cursorLook(mx-(rect.left+e._at.x),my-(rect.top+e._at.y));e.lookX=g.x;e.lookY=g.y}"))
out.append(L(699, 710))                 # listeners, drawFile, REJECT, launch
out.append(rep(L(711, 713), "k=seg(t,f.t0,f.t0+380),m=f.e._mouth;if(!m)continue;const q=EZ.inOut(k),cx=(f.x+m.x)/2,cy=Math.min(f.y,m.y)-60,u=1-q;\n const x=u*u*f.x+2*u*q*cx+q*q*m.x,y=u*u*f.y+2*u*q*cy+q*q*m.y,R=f.e._at.R;drawFile(ctx,x,y,lerp(R*.62,R*.14,q),(1-q)*.5-.25,f.ext);",
               "k=seg(t,f.t0,f.t0+FLIGHT_MS),m=f.e._mouth;if(!m)continue;\n const w=CatCore.flightAt(f,m,f.e._at.R,k);drawFile(ctx,w.x,w.y,w.size,w.rot,f.ext);"))
out.append(L(714, 728))                 # stage, simulateCatch, the notch mock-up header
out.append("const EXP={W:560,H:180};")   # NOTCH and COMPACT come from the core
out.append(L(730, 742))                 # engines, sessions, island, islandPath, labels, pill
out.append(rep(L(767, 793), "drawGreeting(ctx,t,cx,k);return", "drawGreeting(ctx,t,cx,k,greetEng);return"))   # menubar, session minis, drawDesk

# ── The greeting: the old timeline is gone; this is the v2 drawing, fed by CatCore.greetingPose ──
g2 = L(917, 929)
g2 = rep(g2, "function drawGreeting2(ctx,t,cx,k,ge){const P=pose2(t),iw=P.iw*k,ih=P.ih*k,X=cx+(P.x-320)*k,Y=P.y*k,D=P.hb*1.34*k,s=ge.s,st=t-(GT2.land-.1);",
             "function drawGreeting(ctx,t,cx,k,ge){const P=CatCore.greetingPose(t),iw=P.iw*k,ih=P.ih*k,X=cx+(P.x-320)*k,Y=P.y*k,D=P.hb*1.34*k,s=ge.s,st=CatCore.streakTime(t);")
g2 = rep(g2, "pitch:-P.lookY*.45-P.eyeRoll*1.15,", "pitch:-P.lookY*.45,")
out.append("// The launch greeting (Greeting v2): the pose comes from CatCore.greetingPose(t); this draws the island, halo, streaks, header, cat and paws.")
out.append(g2)
out.append("function playGreeting(){greetEng=new CatEngine(PRESETS[CHAR]);ISL.greet=ms()}")

# ── Controls: the motion style now lives in the shared settings ──────────────
ctl = L(809, 891)
ctl = rep(ctl, "${PROFILES[o||MOTION].label}", "${PROFILES[o||CFG.motion].label}")
ctl = rep(ctl, "()=>MOTION,v=>{MOTION=v;reenter()}", "()=>CFG.motion,v=>{CFG.motion=v;reenter()}")
out.append(ctl)

out.append("""// ── Greeting panel: one canvas on its own clock, so Replay restarts it ──────────
const GC={cat:'shrimpy',loop:false,slow:false,t:0,e:null,cv:document.getElementById('cvG')};
function gcReplay(){GC.e=new CatEngine(PRESETS[GC.cat]);GC.t=0}
(()=>{const row=document.getElementById('gcRow'),mk=(l,fn)=>{const b=document.createElement('button');b.textContent=l;b.onclick=fn;row.appendChild(b);return b},cats=[];
 for(const n of ['shrimpy','momo']){const b=mk(PRESETS[n].label,()=>{GC.cat=n;cats.forEach(([c,m])=>c.classList.toggle('on',m===n));gcReplay()});b.classList.toggle('on',n===GC.cat);cats.push([b,n])}
 mk('Replay',gcReplay);
 const lp=mk('Loop',()=>{GC.loop=!GC.loop;lp.classList.toggle('on',GC.loop)}),sl=mk('Slow ×0.5',()=>{GC.slow=!GC.slow;sl.classList.toggle('on',GC.slow)});
 gcReplay()})();
let gcLast=performance.now();
function gcFrame(now){const dt=Math.min(.05,Math.max(0,(now-gcLast)/1000));gcLast=now;GC.t+=dt*(GC.slow?.5:1);
 if(GC.loop&&GC.t>GREET_LEN+.8)gcReplay();
 const t=Math.min(GC.t,GREET_LEN);GC.e.update(dt);
 const [ctx,W]=fit(GC.cv);drawGreeting(ctx,t,W/2,Math.min(1,(W-24)/640),GC.e);
 requestAnimationFrame(gcFrame)}
requestAnimationFrame(gcFrame);
""")
out.append(L(947, 955))                 # frame loop and the closing tags
open(sys.argv[2], 'w', encoding='utf-8').write('\n'.join(out))
EOF
```

This needs `playwright-cli` (the `playwright-cli` skill). Take the baseline twice from the old page:

```bash
T=${TMPDIR:-/tmp}/a0-check
for i in 1 2; do
  rm -rf "$T/before$i"; mkdir -p "$T/before$i"
  sed "s#__PAGE__#$T/old.html#; s#__OUT__#$T/before$i#; s#__GC__#\#cvGB#" "$T/shots.js" > "$T/shots-before$i.js"
  playwright-cli close >/dev/null 2>&1; playwright-cli open >/dev/null 2>&1
  playwright-cli --raw run-code --filename="$T/shots-before$i.js" | tail -1
done
node "$T/png-compare.mjs" "$T/before1" "$T/before2"
```

Expected: each run prints `{"dump":...,"errors":[]}`, and the comparison ends with `different=0 missing=0`, with all 146 files counted as `identical`, `noise` or `faint`. A few `noise` or `faint` lines are normal (text anti-aliasing and gradient dithering). Any `DIFFERENT` line means the check is not steady: do not go on.

- [ ] **Step 2: Refactor the page**

```bash
T=${TMPDIR:-/tmp}/a0-check
python3 "$T/make-page.py" "$T/old.html" design/prototype/notchmeow.html
wc -l design/prototype/notchmeow.html
git diff --stat -- design/prototype/notchmeow.html
```

Expected: `542 design/prototype/notchmeow.html`, and `62 insertions(+), 474 deletions(-)`. The script exits with a message instead if the old page's hash or any replacement doesn't match.

- [ ] **Step 3: Take the screenshots of the new page and compare**

```bash
T=${TMPDIR:-/tmp}/a0-check
rm -rf "$T/after"; mkdir -p "$T/after"
sed "s#__PAGE__#$PWD/design/prototype/notchmeow.html#; s#__OUT__#$T/after#; s#__GC__#\#cvG#" "$T/shots.js" > "$T/shots-after.js"
playwright-cli close >/dev/null 2>&1; playwright-cli open >/dev/null 2>&1
playwright-cli --raw run-code --filename="$T/shots-after.js" | tail -1
node "$T/png-compare.mjs" "$T/before1" "$T/after" '12-island-greeting'
```

Expected: the run prints `{"dump":"{\"canvases\":19,...}","errors":[]}`: one canvas fewer than before (the old greeting's) and no console error or warning anywhere. The comparison ends with `different=0 missing=0`. When this plan was dry-run it printed `identical=134 noise=0 faint=9`: every state, emote, catch, personality, fur and island screenshot is pixel for pixel the same. The eight `13-greet-panel-*` files are `faint` (one level out of 255 in the panel's background gradient; the cat in them matches, and its pose is the same numbers, Task 5 Step 6), and a `noise` or `faint` line or two elsewhere is text anti-aliasing.

The `12-island-greeting-*` files are skipped on purpose: they now show the new greeting.

- [ ] **Step 4: Look at the new greeting**

Open `$T/after/12-island-greeting-2s-desk.png` and `$T/before1/12-island-greeting-2s-desk.png`. Before: the old greeting, the cat in the middle of the island with both paws out. After: Greeting v2, the cat slid to the right and waving one paw. Then open `$T/after/13-greet-panel-2p2.png`: the same wave in the Greeting panel.

- [ ] **Step 5: Check that the page loads from a file and logs nothing**

```bash
T=${TMPDIR:-/tmp}/a0-check
cat > "$T/probe.js" <<'EOF'
async page => {
  await page.setViewportSize({ width: 1280, height: 900 });
  const errors = [];
  page.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') errors.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  await page.goto('file://__PAGE__');
  await page.waitForTimeout(1500);
  const info = await page.evaluate(() => ({ title: document.title, canvases: document.querySelectorAll('canvas').length, core: typeof CatCore, version: CatCore.VERSION }));
  return JSON.stringify({ info, errors });
}
EOF
sed "s#__PAGE__#$PWD/design/prototype/notchmeow.html#" "$T/probe.js" > "$T/probe-run.js"
playwright-cli close >/dev/null 2>&1; playwright-cli open >/dev/null 2>&1
playwright-cli --raw run-code --filename="$T/probe-run.js" | tail -1
```

Expected: `{"info":{"title":"NotchMeow prototype","canvases":19,"core":"object","version":1},"errors":[]}`.

- [ ] **Step 6: Commit**

```bash
git add design/prototype/notchmeow.html
git commit -m "refactor(prototype): the page loads cat-core.js and keeps only the renderer and controls

The default greeting is the new one; the comparison panel and the old greeting timeline are gone.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Docs, CI and the final checks

**Files:**
- Create: `docs/CAT-CONTRACT.md`
- Create: `tests/cat/fixtures.test.mjs`
- Modify: `.github/workflows/build.yml` (one step, next to the AI contract)
- Modify: `CLAUDE.md` and `ARCHITECT.md` (one pointer each)

**Interfaces:**
- Consumes: `format` and `fix` from `scripts/gen-cat-fixtures.mjs`; the seven fixture files.
- Produces: `docs/CAT-CONTRACT.md` for the A-tauri and A-mac plans, and a CI step `Cat contract (cat-core.js self-checks, fixtures, determinism)` that runs `bash scripts/test-cat-contract.sh` on Node 22.

- [ ] **Step 1: Write the fixtures test**

Create `tests/cat/fixtures.test.mjs`:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { format, fix } from '../../scripts/gen-cat-fixtures.mjs';

const dir = new URL('../fixtures/cat/', import.meta.url);
const FILES = ['geometry-cases.json', 'motion-cases.json', 'personality-cases.json', 'presets.json', 'search-tools.json', 'sequence-cases.json', 'warp-cases.json'];

test('tests/fixtures/cat holds exactly the seven contract files', () => {
  assert.deepEqual(fs.readdirSync(dir).sort(), FILES);
});

test('every fixture is canonical JSON: version 1, the 1e-9 tolerance, and the exact bytes the generator writes', () => {
  for (const name of FILES) {
    const text = fs.readFileSync(new URL(name, dir), 'utf8'), data = JSON.parse(text);
    assert.equal(data.version, 1, name);
    assert.equal(data.tolerance, 1e-9, name);
    assert.equal(format(fix(data)), text, `${name} is not in the generator's canonical format`);
    assert.ok(text.length < 400_000, `${name} is ${text.length} bytes`);
  }
});

test('no fixture carries a platform path, a timestamp or a random-looking id', () => {
  for (const name of FILES) {
    const text = fs.readFileSync(new URL(name, dir), 'utf8');
    assert.ok(!/\/Users\/|\\Users\\|C:\\|\b20\d\d-\d\d-\d\dT/.test(text), name);
  }
});
```

It checks that the folder holds exactly the seven files, that each is in the generator's canonical format (so a hand edit is caught) with `version` 1 and `tolerance` 1e-9, and that none carries a path, a user name or a timestamp.

- [ ] **Step 2: Run it**

Run: `node --test tests/cat/fixtures.test.mjs`
Expected: `# tests 3`, `# pass 3`.

- [ ] **Step 3: Write the contract doc**

Create `docs/CAT-CONTRACT.md`:

````markdown
# The cat contract

`design/prototype/cat-core.js` holds everything about Shrimpy, Momo and the other fourteen coats that can be written as numbers in, numbers out. `tests/fixtures/cat/*.json` are generated from it. The macOS app (Swift) and the Windows/Linux app (TypeScript) each reimplement the core natively and test themselves against those fixtures, the same way both apps test their AI layer against `tests/fixtures/ai/`.

**`cat-core.js` is the tie-breaker.** The fixtures are generated from it, so if an app and a fixture disagree, the app is wrong. If the core itself must change, change it, regenerate the fixtures and commit both together. CI fails when they drift apart.

The look is not tested here. There are no pixel tests; the look is checked by eye against `design/prototype/notchmeow.html`, which draws with the same core.

## Run it

```
bash scripts/test-cat-contract.sh      # self-checks, no-drift check, determinism check
node scripts/gen-cat-fixtures.mjs      # rewrite tests/fixtures/cat/ after an intended change to the core
node scripts/gen-cat-fixtures.mjs --check
```

Node 22 or newer, no npm packages. CI runs the script next to the AI contract.

## One file, two worlds

`cat-core.js` is a plain script. A page loads it with `<script src="cat-core.js">` and gets one global, `CatCore`. Node loads it with `require()` and gets the same object. No build step.

| Group | Names |
|---|---|
| Helpers | `rng`, `EZ`, `lerp`, `clamp`, `seg`, `hex`, `wrapA`, `tm`, `TAU` |
| Tables | `STATES`, `COL`, `TINT`, `GLOW`, `BADGE`, `MOUTH`, `MKEYS`, `EMOUTH`, `mouthFx`, `BUSY` |
| Presets | `PRESETS`, `CAT_IDS`, `MORE`, `makeCat`, `kittenOf`, `catById` |
| Geometry | `layout`, `mkWarp`, `supPoints`, `earGeom`, `faceAngles`, `cursorLook`, `pupilOffset`, `detailOf`, `earScale`, `badgeSide`, `outlineSteps`, `MOMO_WHITE`, `FACE`, `PASSES`, `newPose` |
| Personality | `PERSONAS`, `TRAITS`, `persMultipliers`, `personaNamed`, `slide`, `normPers` |
| Motion | `CLASSIC`, `PLAYFUL`, `PROFILES`, `CatEngine`, `enginePaws`, `cfg` |
| Rules | `workClockStep`, `zoomiesOnFinish`, `ZOOM_AFTER_MS`, `sleepDelay`, `SLEEP_AFTER_MS`, `wakes`, `isSearchTool`, `toolState`, `SEARCH_TOOLS` |
| Timelines | `greetingPose`, `GREET_LEN`, `GT`, `GT2`, `STREAKS`, `flightAt`, `FLIGHT_MS` |

Not in the core, on purpose:
- **Canvas drawing** stays in `notchmeow.html` and in each app's renderer. The core hands the renderer what it needs: `layout()` returns the head centre, warp, eyes, nose, mouth, ears and badge in px, and `PASSES` names the draw order as a *behind* pass, the head and a *front* pass, so outfits (sub-project I) can sit on either side of the head.
- **The Apple Music dance** is an existing member of each app's engine (`setDancing`, `applyDance`). The prototype has no music, so the core adds nothing for it.
- **Fur-line strands** (optional, off by default) are drawn from seeded noise by the renderer. They are not part of the contract.
- **Which files a cat refuses** (apps, archives, disk images, videos, over 25 MB) belongs to the AI contract (`tests/fixtures/ai/attachment-cases.json`, where 25 MB is 26,214,400 bytes). The cat only needs to be told "refused": `catchReject(ext)`.

## Conventions

- **Units.** Presets, the warp and the pose are in **R**, the head radius. `layout()` and the greeting are in px, the greeting in a 640×150 space. Times in a fixture are integer milliseconds or frame numbers.
- **Frames.** A fixture that steps the engine uses 60 frames per second: frame `f` is at `f * 1000 / 60` ms and the engine is updated once per frame with `dt = 1/60`.
- **Tolerance.** Every number is stored with 12 significant digits, and apps compare within **1e-9 R**. Swift and JavaScript can differ in the last bit of `sin`/`cos`/`pow`, so never compare floats exactly. Strings, booleans, nulls and the shape of the data compare exactly. Each fixture file carries `"tolerance": 1e-9`.
- **Seeding.** The core never calls `Math.random()` and never reads a clock. An engine is given `now()` (milliseconds) and `rand()` (0 up to, not including, 1). Fixtures use `rng(seed)`, a 32-bit LCG: `state = (state * 1103515245 + 12345) mod 2^32`, then `state / 2^32`, with the seed taken modulo 2^32. In Swift that is `UInt32` wrapping arithmetic (`&*` and `&+`). The first four values of seed 13 are 0.3401210163719952, 0.7113941803108901, 0.17734891548752785 and 0.924706461140886; `motion-cases.json` lists more. **The order of `rand()` calls is part of the contract**: an engine that draws a random number for a blink, a flick or a bleep must do so at the same moment and in the same order as the core, or its random schedule drifts.
- **Quiet engines.** `quiet: true` switches off every random idle habit (blinks, ear flicks, bleps, personality). Fixtures use it, so an emote is sampled on its own. The `ambient` cases run the other way, with a seeded rand, and list what the cat does by itself.

## The fixtures

| File | Pins |
|---|---|
| `presets.json` | `ids` (the frozen cat IDs, Shrimpy first and Momo second), `cats` and `kittens` by ID: every coat fully resolved, including `voice` (a pitch offset in semitones for sub-project C: Shrimpy −1, Momo +1, extra coats 0, every kitten +3). |
| `geometry-cases.json` | `detail` (the Ø28 switch), `earScale`, `outline` (head and ruff outline samples, including Shrimpy's fluffy edge), `anchors` (a full `layout()` per cat, size and pose, with the compact notch case), `passes`. |
| `warp-cases.json` | `face` constants, `cursor` (tanh over 240/180 px), `angles`, `pupil` travel (0.24), `warp` (probe and marking points through the face warp), `eyes` (near-eye 55 % floor, hidden far eye), `head` (outline lean, nose and mouth depth). |
| `motion-cases.json` | `ease`, `tween`, `prng`; `rest` (every state at rest, in both styles: eye shape, the six mouth values, ears, pupil, lid, tint, badge, colour); `enters` (each state's entry, sampled over 3 s); `emotes` (every emote, hairball 2.4 s and zoomies 2 s included); `ambient` (45 s of idle habits for each personality). Rows are `v` arrays whose meaning is in `columns`. |
| `personality-cases.json` | The six presets, the six trait labels, `cases` (traits to multipliers and idle habits, including thresholds and hand-edited values), `slide` (moving a slider makes the preset Custom). |
| `sequence-cases.json` | `greetingSamples` (the 5.74 s greeting, every 100 ms and at each beat), `greetingStreaks`, `flight`, `workClock` (the 5-minute zoomies rule), `sleep` (the 10-minute rule and what wakes the cat), `catch` (the four-step file catch, in both styles, refused or not), `zoomiesAndWake` (when the engine starts zoomies). |
| `search-tools.json` | The tool names that mean "searching", for Claude Code, Gemini CLI and Codex, and cases. |

## The harness

`motion-cases.json` and `sequence-cases.json` describe how to build the engine, and `makeEngine` in `scripts/gen-cat-fixtures.mjs` is the reference:

1. a fake clock starting at 0, and `rand = rng(seed)`;
2. the cat (Momo unless the case says otherwise) with `motion` set to the case's style, no overrides, Balanced personality unless the case says otherwise, and `zoomAfter` of 5 minutes;
3. `_base = {x:0, y:0, R:1}` and `_mouth` from `layout()` at rest with the head width `2 * rx`, so R is exactly 1 and a hairball lands in units of R;
4. for `rest`: set `lookX`/`lookY`, then `computeTargets(T * 1000, T)`; for `enters`, `emotes` and `catch`: act at frame 0, then update once per frame and read the pose at the sample frames.

## Decisions to know about

- **The compact ear scale is provisional.** The spec says ears are scaled down at Ø20 and gives no number. `COMPACT_EAR_SCALE` is 0.8 at Ø20 and below, easing to 1 at Ø28. Apps pass `earScale(D)` to `layout()`. The prototype page does not apply it yet, so it still looks as it did. Change the constant and regenerate if the owner wants another value.
- **Shrimpy's fluffy edge is a fixed sum of sines**, not noise from a seed, so it needs no random numbers and is identical everywhere. `geometry-cases.json` pins samples of it.
- **Only an idle cat sleeps.** `sleepDelay` is 10 minutes after the last agent event, and `null` for every other state, approval and question included. An app that leaves an agent on `finished` will not see the cat sleep until it returns to idle.
- **Playful wakes with zoomies** on any move out of sleeping except into dizzy, an approval included. That is what the prototype does.
- **The prototype page shortens the zoomies rule to 12 seconds** (`cfg.zoomAfter`), so you can watch it. The apps use `ZOOM_AFTER_MS`, 5 minutes.
- **Search tool names.** Claude Code's come from the repo's hook mapping. Gemini CLI's come from the installed CLI (0.39.1: `grep_search`, with `search_file_content` as its older name). Codex's `web_search` and `grep_files` are unverified, and Antigravity's tool names are not known. A name that is missing only means the cat stays in "working" for that tool.
- **Hostile input.** An unknown cat ID falls back to Shrimpy, an unknown state or emote is ignored, an unknown motion style plays Playful, personality values outside 0 to 1 are held to that range and missing ones count as 0.5, and `update(dt)` holds `dt` to 0 up to 0.25 s. Apps do the same.
````

- [ ] **Step 4: Add the CI step**

In `.github/workflows/build.yml`, replace

```yaml
      - name: AI contract (fixtures + fake server)
        run: bash scripts/test-ai-contract.sh
```

with

```yaml
      - name: AI contract (fixtures + fake server)
        run: bash scripts/test-ai-contract.sh

      - uses: actions/setup-node@v4
        with:
          node-version: '22'

      - name: Cat contract (cat-core.js self-checks, fixtures, determinism)
        run: bash scripts/test-cat-contract.sh
```

Check that the file still parses and the step sits where intended:

Run: `ruby -ryaml -e 'st = YAML.load_file(".github/workflows/build.yml")["jobs"]["build"]["steps"]; i = st.index { |x| x["name"].to_s.start_with?("AI contract") }; puts st[i..i + 2].map { |x| x["name"] || x["uses"] }'`
Expected: `AI contract (fixtures + fake server)`, `actions/setup-node@v4`, `Cat contract (cat-core.js self-checks, fixtures, determinism)`.

- [ ] **Step 5: Point `CLAUDE.md` and `ARCHITECT.md` at the contract**

In `CLAUDE.md`, under "Where things are", replace

```
- `design/prototype/notchmeow.html` — the cat prototype, the visual source of truth for the characters (being built).
```

with

```
- `design/prototype/notchmeow.html` — the cat prototype, the visual source of truth for the characters (being built).
- `design/prototype/cat-core.js` — everything pure about the cats (presets, face warp, motion, personality, greeting, zoomies and sleep rules), shared by the prototype page and Node. `tests/fixtures/cat/` is generated from it and both apps test against it (`docs/CAT-CONTRACT.md`). If an app and a fixture disagree, `cat-core.js` decides. After changing it, run `node scripts/gen-cat-fixtures.mjs` and commit the fixtures.
```

and under "Rules", replace

```
- Pill IDs are stable contract values (Keychain, UserDefaults, hook routing): never rename an existing pill ID.
```

with

```
- Pill IDs are stable contract values (Keychain, UserDefaults, hook routing): never rename an existing pill ID.
- Cat IDs (`shrimpy`, `momo`, `ginger`, `midnight`, `latte`, `patches`, `blue`, `snow`, `oreo`, `mocha`, `silver`, `cloud`, `leo`, `button`, `puff`, `noodle`) are frozen the same way, because they are stored in settings. An unknown stored ID falls back to `shrimpy`.
```

In `ARCHITECT.md`, under "Main flows", item 5 "Character", replace

```
   - **Sub-project A:** these are being replaced by Shrimpy and Momo. `design/prototype/notchmeow.html` is the visual source of truth.
```

with

```
   - **Sub-project A:** these are being replaced by Shrimpy and Momo. `design/prototype/notchmeow.html` is the visual source of truth, and `design/prototype/cat-core.js` holds its pure maths. Both apps are tested against the fixtures generated from it in `tests/fixtures/cat/` (see `docs/CAT-CONTRACT.md`).
```

- [ ] **Step 6: Run the whole contract**

Run: `bash scripts/test-cat-contract.sh`
Expected: `# tests 72`, `# pass 72`, `# fail 0`, seven `✓` fixture lines, `✓ 7 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 7: Prove the drift check bites (not committed)**

A check that never fails proves nothing. Work in a throwaway copy so the real files stay clean.

```bash
T=${TMPDIR:-/tmp}/a0-check; rm -rf "$T/sab"; mkdir -p "$T/sab/design/prototype"
cp design/prototype/cat-core.js "$T/sab/design/prototype/"
cp -r scripts tests "$T/sab/"
cd "$T/sab"
echo "1. a change to the core that nobody regenerated for:"
sed -i.bak 's/muzzle:.12,nose:.05/muzzle:.13,nose:.05/' design/prototype/cat-core.js
bash scripts/test-cat-contract.sh >/dev/null 2>&1; echo "   exit code $? (expected 1)"
node scripts/gen-cat-fixtures.mjs --check 2>&1 | grep -E '✗' | head -3
mv design/prototype/cat-core.js.bak design/prototype/cat-core.js
echo "2. a fixture edited by 1e-6, which is outside the tolerance:"
node -e "
const fs=require('fs'),p='tests/fixtures/cat/personality-cases.json',d=JSON.parse(fs.readFileSync(p,'utf8')),v=d.cases[1].out.speed;
fs.writeFileSync(p,fs.readFileSync(p,'utf8').replace('\"speed\":'+v,'\"speed\":'+(v+1e-6)))"
node scripts/gen-cat-fixtures.mjs --check 2>&1 | grep -E '✗|\$\.' | head -2
node scripts/gen-cat-fixtures.mjs >/dev/null
echo "3. the same fixture edited by 1e-10, inside the tolerance:"
node -e "
const fs=require('fs'),p='tests/fixtures/cat/personality-cases.json',d=JSON.parse(fs.readFileSync(p,'utf8')),v=d.cases[1].out.speed;
fs.writeFileSync(p,fs.readFileSync(p,'utf8').replace('\"speed\":'+v,'\"speed\":'+(v+1e-10)))"
node scripts/gen-cat-fixtures.mjs --check 2>&1 | grep -E 'personality|fixture files'
node scripts/gen-cat-fixtures.mjs >/dev/null
echo "4. a stray file, and 5. a missing one:"
echo '{}' > tests/fixtures/cat/stray.json; node scripts/gen-cat-fixtures.mjs --check 2>&1 | grep stray; rm tests/fixtures/cat/stray.json
mv tests/fixtures/cat/presets.json "$T/presets.bak"; node scripts/gen-cat-fixtures.mjs --check 2>&1 | grep missing; mv "$T/presets.bak" tests/fixtures/cat/presets.json
cd - >/dev/null
```

Expected: step 1 prints `exit code 1` and `✗ geometry-cases.json drifted from cat-core.js` and `✗ warp-cases.json drifted from cat-core.js`; step 2 prints `✗ personality-cases.json drifted from cat-core.js (1 differences)` and a line starting `$.cases[1].out.speed`; step 3 prints `✓ personality-cases.json` and `✓ 7 fixture files match cat-core.js`; step 4 prints `✗ stray.json is not produced by the generator`; step 5 prints `✗ presets.json is missing`.

- [ ] **Step 8: Check determinism and record the hashes**

```bash
a=$(mktemp -d); b=$(mktemp -d)
node scripts/gen-cat-fixtures.mjs --out "$a" >/dev/null; node scripts/gen-cat-fixtures.mjs --out "$b" >/dev/null
(cd "$a" && shasum -a 256 *.json) > "$a.sha"; (cd "$b" && shasum -a 256 *.json) > "$b.sha"
cmp "$a.sha" "$b.sha" && echo "two runs: identical hashes"
(cd tests/fixtures/cat && shasum -a 256 *.json) | cmp - "$a.sha" && echo "committed fixtures: same hashes as a fresh run"
cat "$a.sha"
```

Expected: both `cmp` lines print their `echo`, then the seven hashes. Note the hashes in the hand-off. On the machine that dry-ran this plan (macOS, Node 22.23) they were:

```
cb37e853029585a2fe0888c16001b6fd733b225482739f155a47f1f1d621a308  geometry-cases.json
fc65446e90dbd178e6d2b5c35a34051c7a592a683ff9f73e5ad5f157227ee36b  motion-cases.json
a69de13470b4c6981eda3d9d492d2d22e6995bfef33e3f81a6d8120e3a1b9dd8  personality-cases.json
c8cdccf1d33b1401be1a6faedff791069f4803e78bd27bda0a8256dac5c3131f  presets.json
8da0bb351ca2c918bcd60e53630e8df2d3ddfeab63eaebb090e4c5149792f8c6  search-tools.json
c971065e63066f841e074017858e34a3c691ed3b2c10f2b7ac09bbd1aa4d9c9c  sequence-cases.json
3c22ec6095daa16b2d687b2c8e5ab4a3a2d852140a3c09937ff3b84675c13d2d  warp-cases.json
```

Another platform or Node version may write a different last digit for a `sin` or `pow` result, so a hash that differs from these is not a failure by itself. The two `cmp` lines on your own machine are the test, and `--check` compares within 1e-9 so CI doesn't trip on it.

- [ ] **Step 9: Check what changed**

Run: `git status --short`
Expected: only the files this task names, as modified (`.github/workflows/build.yml`, `CLAUDE.md`, `ARCHITECT.md`) or new (`docs/CAT-CONTRACT.md`, `tests/cat/fixtures.test.mjs`). Nothing under `NotchBuddy/` or `windows/`, and no `.bak` files.

- [ ] **Step 10: Commit**

```bash
git add docs/CAT-CONTRACT.md tests/cat/fixtures.test.mjs .github/workflows/build.yml CLAUDE.md ARCHITECT.md
git commit -m "docs(cat): the cat contract, a CI step and pointers from CLAUDE.md and ARCHITECT.md

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Self-review notes

Run against the spec after writing:

- **Spec coverage.**
  - §2 `cat-core.js` contents: presets, coat types and flags, `makeCat`, `kittenOf` (Task 2); face warp and geometry helpers (Task 3); state, mouth and emote tables (Task 1) and both motion profiles (Task 6); personality (Task 4); the greeting and file-catch timelines (Task 5 and Task 6). "Numbers in, numbers out. Drawing calls stay in the page": Task 7.
  - §2 randomness: the injected `rand()` and `rng(seed)` (Tasks 1 and 6) and the quiet and ambient fixtures.
  - §2 fixtures: `presets.json` (Task 2), `geometry-cases.json` and `warp-cases.json` (Task 3), `motion-cases.json` (Task 6), `personality-cases.json` (Task 4), `sequence-cases.json` (Tasks 5 and 6) and `search-tools.json` (Task 5). Tolerance 1e-9: the generator, every fixture and the docs. "No pixel tests": none are committed. The one-off pixel check in Task 7 only proves the page refactor.
  - §1: the A-0 row (the CI step in Task 8, the runner in Task 1). "Room for later sub-projects": `layout()` exposes the head centre, ears, eyes, nose and badge, and `PASSES` names a behind pass, the head and a front pass (Task 3); `enginePaws` is the paw pass; `lookX` and `lookY` stay engine members (Task 6). The Apple Music dance is an existing app member and not part of the prototype, so the core adds nothing for it (written in the docs).
  - The greeting decision: the new greeting is the only one in the core and in `sequence-cases.json`; the old timeline is dropped (Tasks 5 and 7).
  - The `voice` field: Shrimpy −1, Momo +1, extra coats 0, kittens +3 (Task 2).
  - Parent-spec character rules: detail levels, face warp numbers, kittens, badge, mouth table, emotes, hairball, zoomies, personality and the 14 coats are all moved from the prototype and pinned.
- **Placeholder scan:** none left. Every code step carries its full code, and no step points at another task for it.
- **Type consistency:** the names in each task's Interfaces block are the names later tasks use. `makeEngine`, `frameMs`, `compare`, `fix`, `format`, `finish` and `SEQUENCE_PARTS` are defined in the generator before the tests that import them.
- **Review Focus:** each of the five lines has its test in the task named there.

### Things the spec does not settle, decided here (open questions for the owner)

1. **Compact ear scale.** The spec says "ears scaled down at Ø20" without a number. `COMPACT_EAR_SCALE` is 0.8 at Ø20 and below, easing to 1 at Ø28. Provisional; the page does not apply it yet.
2. **Shrimpy's fluffy edge.** The spec says "fixed-seed noise". The prototype's edge is a fixed sum of sines (no random numbers at all), which already gives identical outlines everywhere, so it is kept unchanged. Switching to seeded noise would change how Shrimpy looks.
3. **Spec §3, "Greeting" row.** It still says the apps "keep their timeline", but §1 says the new greeting replaces it. This plan follows §1. A-tauri and A-mac should draw `greetingPose`, and the §3 row should be corrected.
4. **Gemini CLI and Codex search tool names.** Gemini CLI's come from the installed CLI (0.39.1): `grep_search`, with the older `search_file_content` kept as an alias. Codex's `web_search` and `grep_files` are not verified. Antigravity's tool names are unknown and not listed.
5. **Who sleeps.** Only an `idle` cat sleeps, as the spec says. If an app leaves an agent on `finished` after it is done, that cat will not fall asleep until the app returns it to idle.
6. **Refused files.** The prototype's refusal rule (a list of extensions, or over 25e6 bytes) is page-only. The real rule is E1's attachment contract (25 MB is 26,214,400 bytes). The cat contract only takes "refused".
7. **Waking.** Playful starts zoomies on any move out of `sleeping` except into `dizzy`, an approval included. That is the prototype's behaviour, kept and pinned.
8. **Kitten ruff.** The parent spec says "the ruff ×0.93"; the prototype does ×0.94 across and ×0.92 down. The prototype wins.
