# A-0b The Cat Contract Additions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add to the cat contract the three things both apps must draw the same way, now that A-0 has merged: the collar styles, the ear fit and the compact flat fills. Each gets numbers in `cat-core.js`, cases in the fixtures and a rule in `docs/CAT-CONTRACT.md`. The prototype page shows exactly what the apps will draw: the three additions, and the compact ear scale together with the ear fit.

**Architecture:** Everything stays in the one plain script, `design/prototype/cat-core.js`: the comparison-only collar code becomes final (style IDs, `collarGeometry`), and two new sections hold `earFit` and the flat-fill switch (`detailLevel`, `FLAT_FILL`, `flatFillColors`). `scripts/gen-cat-fixtures.mjs` writes one new file, `collar-cases.json`, and six new keys in `geometry-cases.json`, all before `passes` (`collarPass`, `earFit`, `earFitCases`, `flatFill`, `detailLevels`, `flatColors`). No existing fixture line changes, `passes` included, and `scripts/check-fixtures-additive.mjs` proves it against `a6ec93c`. The prototype page gets a collar style selector (Off by default), the compact ear scale and the ear fit on its compact cats and the flat fills below Ø28, and a pixel check proves nothing else on it moved.

**Tech Stack:** JavaScript (one file for a browser and Node 22), `node:test` and `node:assert` (no npm packages), Bash, and headless Chromium through `playwright-cli` for the one-off page check.

**Spec:** `docs/superpowers/specs/2026-10-04-cats-in-app-design.md`: §2 "A-0b, contract additions" and the `collar-cases.json` row, the "Agent colour" decision, §3 "Collar", §4 "Collar" and "Collar style IDs are frozen". It extends `docs/CAT-CONTRACT.md` and `design/prototype/cat-core.js` as merged by A-0 (plan: `docs/superpowers/plans/2026-10-04-a0-cat-contract.md`, for style). The ear fit and the flat fills come from the macOS plan draft (`CatGeometry.earFit` and its compact-detail shortcuts); this plan carries every number and every line of code, so it does not need that draft. One number differs from the draft: the flat point mask is tuned to match the gradient it replaces (Task 4).

**Base:** branch `a0b/contract-additions`, created from `notchmeow/rebrand` at `3bef6e1` or later (the merge of the mix picker, which touched only the sounds files), with this plan file already committed to `notchmeow/rebrand`. The cat contract, its fixtures and the prototype page must still be the ones from `a6ec93c`: Task 5 checks the page's hash, and the additive check compares the fixtures with `a6ec93c`. This plan touches nothing under `NotchBuddy/` or `windows/`.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec; the three lines marked "(controller's ruling)" are the controller's answers to the questions the first draft left open.

- **Collar style IDs are frozen contract values:** `tag`, `band`, `kerchief` and `off`. An unknown stored style falls back to `off`. (Settings names: Band and tag, Band, Neckerchief, Off.)
- **Readability floor in device pixels:** band 3 px thick, tag 6 px across, neckerchief 7 px wide and 5 px deep.
- **The collar** is drawn at every size from 12 px up in the renderer's front pass. All three styles live in the contract (`collarGeometry` in `cat-core.js`, with fixture cases). The default is Off. The pass is a key of its own in `geometry-cases.json`, `collarPass: "front"`; the existing `passes` line is not touched (controller's ruling).
- **Ear fit:** the compact island's top is the screen's top, so `earFit` shrinks the ears just enough that no tip leaves the strip.
- **Flat fills:** the compact detail level draws flat fills (no rim, crown or point gradients) below Ø28, shown in the prototype too. The flat point mask (Latte, Cloud) keeps the visible extent of the gradient it replaces, at Ø20 and at Ø28 (controller's ruling).
- **The compact ear scale** (0.8 at Ø20 and below, easing to 1 at Ø28) stays provisional and its value is not changed here. The prototype page applies it, together with the ear fit, so that the page shows exactly what the apps draw (controller's ruling).
- **The mouth spring steps at most 1/60 s per update,** which A-0 already does.
- **Tolerance:** fixtures store 12 significant digits and apps compare within **1e-9 R**. There are no pixel tests in the contract.
- **`cat-core.js` is the tie-breaker:** if an app and a fixture disagree, the module decides. It stays numbers in, numbers out: no canvas, no DOM, no clock, no `Math.random`.
- **Fixtures change only by addition:** the new file, plus new keys in `geometry-cases.json`. Every existing line stays byte-identical, the `passes` line included. `node scripts/check-fixtures-additive.mjs a6ec93c` proves it.
- **The prototype page behaves exactly as before,** except for the collar selector, the compact ear scale and the ear fit on its compact cats, and the flat fills below Ø28.
- **Node standard library only, no npm packages.** Same code style as A-0: compact one-liners in the core, plain commented code elsewhere.
- **Commits:** local only, never pushed. End every commit message with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`, or with the model that wrote it when an implementer runs on another one (the light tasks below name `Claude Haiku 4.5`).

## Review Focus

The spec says what the collar, the ear fit and the flat fills must do. It is silent on these inputs, and each would bite a person (or a port) first. Each line names its test.

1. **A stored collar style that is not one of the four:** a hand-edited settings file, a name from an old build (the comparison used `scarf`), a number. Expected: `off`, and never a throw. Tests: Task 2 "the four style IDs are frozen…" and "off draws nothing…".
2. **A bad pixel ratio, or a head of width 0, given to the collar** (0, NaN, negative, missing). Expected: finite numbers and the floors held (a bad ratio counts as 2). Test: Task 2 "a head of width 0, or a bad pixel ratio…".
3. **A cat too close to the ceiling for any ears to fit, a head of width 0, a cat upside down, or a pose that is not a number (NaN, Infinity) given to `earFit`.** Expected: a number from 0.35 to 1, never NaN (a pose that is not a number gives 1). Tests: Task 3 "a cat too close to the top…" and "a head of width 0, a cat upside down and a pose that is not a number…".
4. **The poses the engine really reaches in the compact notch:** every state and emote in both motion styles, for tall-eared Noodle in the 24 pt strip of a screen without a notch. Expected: no ear tip above the strip. Test: Task 3 "every state and emote…".
5. **An explicit detail that disagrees with the head width** (`compact` at Ø66, `full` at Ø12). Expected: the flat fills follow the detail the cat is drawn at, and `layout()` agrees. Tests: Task 4 "detailLevel…" and "layout() and detailLevel() always agree…".

---

## File Structure

| Path | Responsibility |
|---|---|
| `design/prototype/cat-core.js` | The contract. The collar section becomes final (`COLLAR_STYLES`, `collarStyleOf`, `COLLAR_MIN`, `COLLAR_PASS`, `collarGeometry`). New sections: ear fit (`EAR_FIT`, `earFit`) and compact detail (`detailLevel`, `FLAT_FILL`, `mixHex`, `flatFillColors`). `layout()` reads the detail through `detailLevel`. |
| `design/prototype/notchmeow.html` | The prototype page. The Collar comparison becomes a style selector; `drawCat` uses the compact ear scale, the ear fit (`o.earCeiling`), the flat fills and the final collar API; two panel texts are made true. |
| `scripts/gen-cat-fixtures.mjs` | Gains the `collar-cases.json` builder and six keys in `geometry-cases.json`: `collarPass`, `earFit`, `earFitCases`, `flatFill`, `detailLevels`, `flatColors`. |
| `scripts/check-fixtures-additive.mjs` | New. Proves the fixtures changed only by addition since a commit. Not part of the runner, because CI checks out one commit. |
| `tests/cat/additive.test.mjs`, `earfit.test.mjs`, `flatfill.test.mjs` | New self-checks. |
| `tests/cat/collar.test.mjs`, `tests/cat/fixtures.test.mjs` | Rewritten for the final collar; the fixture list gains `collar-cases.json`. |
| `tests/fixtures/cat/collar-cases.json` | New fixture. |
| `tests/fixtures/cat/geometry-cases.json` | The six new keys, inserted before `passes`. Every old line stays, `passes` included. |
| `docs/CAT-CONTRACT.md` | The collar styles and IDs, the ear fit, the flat-fill rule, the additive rule and pointers to the mouth-spring and `tMs` notes that were already there. |

One-off checks (Tasks 1 and 5) live in `${TMPDIR:-/tmp}/a0b-check/` and are never committed.

**Agents** (CLAUDE.md: the lightest model that fits). Every task gives its full code, so the plain ones are transcription: Tasks 1, 2, 3, 4 and 6 are `nm-implementer-light` (Haiku 4.5). If a step's expected output differs and the cause is not obvious, hand that task to `nm-implementer`. Task 5 runs a browser and judges screenshots: `nm-implementer` (Sonnet 5.5, medium). Task reviews: `nm-reviewer`; the final whole-branch review: `nm-reviewer-deep`. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; reviewers load `ponytail:ponytail-review`.

**Order of tasks:** the contract grows first, one section per task with its own fixtures, test first. The page and the docs come last.

1. The additive-fixtures check
2. Collar styles become contract
3. The ear fit
4. Compact flat fills
5. The prototype page
6. Docs and the final checks

## Execution

One worktree chat session runs the whole plan: branch `a0b/contract-additions`, model **Sonnet 5.5 at medium effort** (ARCHITECT.md: a plan whose tasks are mostly given in full). Nothing is pushed.

**Before the session starts,** the plan file is committed to `notchmeow/rebrand` (a docs-only commit): the controller does this, with the owner's OK, so the branch the session starts from already holds the plan it runs. **The base is `3bef6e1` or later:** the session's branch is made from `notchmeow/rebrand` as it is then, and `git merge-base --is-ancestor 3bef6e1 HEAD` must succeed.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run `git switch -c a0b/contract-additions notchmeow/rebrand`, then `git merge-base --is-ancestor 3bef6e1 HEAD` and `git ls-files docs/superpowers/plans/2026-10-04-a0b-contract-additions.md`: the first must succeed and the second must print the plan's path. If either fails, say so and stop. Read `CLAUDE.md`, `ARCHITECT.md`, `docs/superpowers/plans/2026-10-04-a0b-contract-additions.md` and `docs/superpowers/specs/2026-10-04-cats-in-app-design.md`. Reply "ready" and stop. Do not start any task.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at medium effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message:

   > Run `docs/superpowers/plans/2026-10-04-a0b-contract-additions.md` with `superpowers:subagent-driven-development`, task by task, on this branch. Dispatch each task to the agent the plan names for it, then to `nm-reviewer`; fix what the review finds before the next task. After Task 6, dispatch `nm-reviewer-deep` over the whole branch. Commit only as the plan's commit steps say, and never push. When you are done, report: the commits, the new and changed fixture cases, the output of `node scripts/check-fixtures-additive.mjs a6ec93c`, the screenshot comparison (`identical=… differ-only-where-expected=… unexpected=…`, and the `ears` part of the page run's output), and anything you could not settle.

Before any follow-up turn, the main session checks the session is still on its configured model and effort.

---

### Task 1: The additive-fixtures check

**Files:**
- Create: `scripts/check-fixtures-additive.mjs`
- Create: `tests/cat/additive.test.mjs`

**Interfaces:**
- Consumes: nothing. Run it from the repository root, with `git` available.
- Produces `scripts/check-fixtures-additive.mjs`: exports `checkAdditive(oldText, newText)` to `{problems: string[], added: string[]}` (`problems` is empty when the new text only adds to the old one: every old line is still there, in order, byte for byte, apart from a trailing comma; `added` lists the new top-level keys). Command line: `node scripts/check-fixtures-additive.mjs [BASE_REF]` compares every `tests/fixtures/cat/*.json` with the version at `BASE_REF` (default `HEAD`), prints one line per file and exits 0, 1 (not only addition) or 2 (cannot read the ref). Later tasks and the final check run it with `a6ec93c`.

- [ ] **Step 1: Write the failing test**

Create `tests/cat/additive.test.mjs`:

```bash
cat > tests/cat/additive.test.mjs <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import { checkAdditive } from '../../scripts/check-fixtures-additive.mjs';

const OLD = ['{', '  "version": 1,', '  "cases": [', '    {"n":1},', '    {"n":2}', '  ],', '  "passes": {"a":["x"]}', '}', ''].join('\n');
const withLines = (at, ...lines) => { const l = OLD.split('\n'); l.splice(at, 0, ...lines); return l.join('\n'); };

test('the same file, and a file that only gains a key, pass', () => {
  assert.deepEqual(checkAdditive(OLD, OLD), { problems: [], added: [] });
  assert.deepEqual(checkAdditive(OLD, withLines(6, '  "extra": {"k":1},')), { problems: [], added: ['extra'] });
});

test('a key appended after the last one passes: the old last line only gains a comma', () => {
  const l = OLD.split('\n'); l[6] += ','; l.splice(7, 0, '  "extra": 1');
  assert.deepEqual(checkAdditive(OLD, l.join('\n')), { problems: [], added: ['extra'] });
});

test('a new case inside an old array passes: old cases are still there, byte for byte', () => {
  assert.deepEqual(checkAdditive(OLD, withLines(4, '    {"n":1.5},')).problems, []);
});

test('a changed number, a deleted line and a reordered case all fail', () => {
  assert.equal(checkAdditive(OLD, OLD.replace('{"n":2}', '{"n":2.000000000001}')).problems.length, 1);
  assert.equal(checkAdditive(OLD, OLD.replace('    {"n":1},\n', '')).problems.length, 1);
  assert.equal(checkAdditive(OLD, OLD.replace('    {"n":1},\n    {"n":2}', '    {"n":2},\n    {"n":1}')).problems.length, 1);
});

test('a new version that is not valid JSON fails', () => {
  assert.match(checkAdditive(OLD, withLines(6, '  "broken": ,')).problems[0], /not valid JSON/);
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run: `node --test tests/cat/additive.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `scripts/check-fixtures-additive.mjs`.

- [ ] **Step 3: Write the check**

```bash
cat > scripts/check-fixtures-additive.mjs <<'EOF'
#!/usr/bin/env node
// Proves the cat fixtures changed only by addition since a base ref (default HEAD).
//   node scripts/check-fixtures-additive.mjs [BASE_REF]
// A fixture file may be added, and a file may gain new keys or new cases. Every line the base version had must still be
// there, byte for byte and in the same order (a trailing comma may come or go, because a key appended last gains one).
// Apps read these files, so once they do, change them like this. Not part of test-cat-contract.sh: CI checks out one commit.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIR = 'tests/fixtures/cat';
const noComma = line => line.replace(/,$/, '');

/** Compares one file's old and new text. `problems` is empty when the new text only adds to the old; `added` lists new top-level keys. */
export function checkAdditive(oldText, newText) {
  const problems = [];
  let now;
  try { now = JSON.parse(newText); } catch { return { problems: ['the new version is not valid JSON'], added: [] }; }
  const was = oldText.split('\n').map(noComma), next = newText.split('\n').map(noComma);
  let j = 0;
  for (const [i, line] of was.entries()) {
    while (j < next.length && next[j] !== line) j++;
    if (j === next.length) { problems.push(`old line ${i + 1} is gone or changed: ${line.trim().slice(0, 90)}`); break; }
    j++;
  }
  return { problems, added: Object.keys(now).filter(k => !(k in JSON.parse(oldText))) };
}

function main(ref = 'HEAD') {
  const git = (...args) => execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', maxBuffer: 1 << 26 });
  let names;
  try { names = git('ls-tree', '--name-only', ref, `${DIR}/`).split('\n').filter(f => f.endsWith('.json')); } catch { console.error(`cannot read ${DIR}/ at ${ref}`); process.exit(2); }
  let failed = false;
  for (const file of names) {
    const name = path.basename(file), now = path.join(ROOT, file);
    if (!fs.existsSync(now)) { failed = true; console.log(`  ✗ ${name} was removed`); continue; }
    const text = fs.readFileSync(now, 'utf8'), old = git('show', `${ref}:${file}`), { problems, added } = checkAdditive(old, text);
    if (problems.length) { failed = true; console.log(`  ✗ ${name}`); problems.forEach(p => console.log(`      ${p}`)); }
    else console.log(`  ✓ ${name}: ${old.split('\n').length - 1} old lines unchanged${text === old ? '' : `, ${text.split('\n').length - old.split('\n').length} lines added${added.length ? ` (new keys: ${added.join(', ')})` : ''}`}`);
  }
  for (const f of fs.readdirSync(path.join(ROOT, DIR)).filter(f => f.endsWith('.json') && !names.includes(`${DIR}/${f}`))) console.log(`  + ${f} is new`);
  if (failed) { console.log(`Fixtures changed by more than addition since ${ref}.`); process.exit(1); }
  console.log(`✓ fixtures changed only by addition since ${ref}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(fs.realpathSync(process.argv[1])).href) main(process.argv[2]);
EOF
```

- [ ] **Step 4: Run the test**

Run: `node --test tests/cat/additive.test.mjs`
Expected: `# pass 5`, `# fail 0`.

- [ ] **Step 5: Run it on the real fixtures, then prove it bites**

```bash
node scripts/check-fixtures-additive.mjs a6ec93c
echo "--- tamper with an old case:"
python3 - <<'PY'
p = 'tests/fixtures/cat/geometry-cases.json'
s = open(p, encoding='utf-8').read()
assert s.count('"compactMin":0.8') == 1
open(p, 'w', encoding='utf-8').write(s.replace('"compactMin":0.8', '"compactMin":0.81'))
PY
node scripts/check-fixtures-additive.mjs a6ec93c; echo "exit code $? (expected 1)"
git checkout tests/fixtures/cat/geometry-cases.json
echo "--- a ref that does not exist:"
node scripts/check-fixtures-additive.mjs nosuchref; echo "exit code $? (expected 2)"
git status --short
```

Expected: first, seven `✓ <file>: N old lines unchanged` lines (`geometry-cases.json` 51, `motion-cases.json` 713, `personality-cases.json` 62, `presets.json` 42, `search-tools.json` 36, `sequence-cases.json` 137, `warp-cases.json` 121) and `✓ fixtures changed only by addition since a6ec93c`. Then, for the tampered file, `✗ geometry-cases.json`, a line `old line 6 is gone or changed: "earScale": {"compactMin":0.8,...`, `Fixtures changed by more than addition since a6ec93c.` and `exit code 1 (expected 1)`. Then `fatal: Not a valid object name nosuchref`, `cannot read tests/fixtures/cat/ at nosuchref` and `exit code 2 (expected 2)`. The last `git status --short` shows only the two new files from this task (`scripts/check-fixtures-additive.mjs`, `tests/cat/additive.test.mjs`) as untracked, and no fixture changed.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-fixtures-additive.mjs tests/cat/additive.test.mjs
git commit -m "test(cat): prove the fixtures only grow, with a check against a base commit

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Collar styles become contract

**Files:**
- Modify: `design/prototype/cat-core.js` (the "Collar (COMPARISON ONLY)" section, 26 lines, becomes the final collar section)
- Modify: `scripts/gen-cat-fixtures.mjs` (a new builder above the `@@BUILDERS` marker, and one key in the `geometry-cases.json` builder)
- Modify: `tests/cat/collar.test.mjs` (rewritten), `tests/cat/fixtures.test.mjs` (eight files, not seven)
- Create: `tests/fixtures/cat/collar-cases.json` (generated)
- Modify: `tests/fixtures/cat/geometry-cases.json` (generated: one new key, `collarPass`, before `passes`)

**Interfaces:**
- Consumes: `layout`, `supPoints`, `newPose`, `PRESETS`, `kittenOf` from the core; `compare` and `fix`, `format` from the generator; `check-fixtures-additive.mjs` (Task 1).
- Produces in `CatCore`: `COLLAR_STYLES` (`['tag', 'band', 'kerchief', 'off']`, frozen, in this order); `collarStyleOf(id)` to a style (anything that is not one of the four, a non-string included, gives `'off'`); `COLLAR_MIN` (`{band: 3, tag: 6, kerchiefW: 7, kerchiefDrop: 5}`, in device px); `COLLAR_PASS` (`'front'`: the renderer pass the collar is drawn in, a key of `PASSES`, which this plan does not touch); `collarGeometry(preset, pose, D, style, {dpr, detail})` to `null` for `off`, else `{style, R, width, band, tag}` for `tag`, `{style, R, width, band}` for `band` and `{style, R, kerchief}` for `kerchief`, in head-local px: `band` is 26 points `[x, y]` left to right, `tag` is `{x, y, r}`, `kerchief` is `{pts: [[x, y], …], apex: [x, y]}`. `dpr` defaults to 2 (and is 2 for anything not above 0). The old comparison names (`COLLAR_OPTIONS`, `scarf`, `scarfW`, `scarfDrop`) are gone. Fixture `collar-cases.json`: `{version, tolerance, units, styles, min, resolve, cases}` where a case is `{cat, kitten, style, D, dpr, pose, out}`. In `geometry-cases.json` a new key `collarPass` (`"front"`) sits beside the old `passes` line, which stays byte for byte as A-0 wrote it: the collar is not added to `passes`, so the fixtures change only by addition.

- [ ] **Step 1: Write the failing tests**

This replaces the comparison tests with the final ones (the replay of the fixture file comes in Step 6).

```bash
cat > tests/cat/collar.test.mjs <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const pose = (o = {}) => ({ ...core.newPose(), ...o });
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const STYLES = ['tag', 'band', 'kerchief']; // the three that draw something; 'off' draws nothing
const finite = v => (Array.isArray(v) ? v.every(finite) : v && typeof v === 'object' ? Object.values(v).every(finite) : typeof v === 'number' ? Number.isFinite(v) : true);
const onHead = (pts, p, R, k = 1.02) => pts.every(([x, y]) => (x / (p.rx * R)) ** 2 + (y / (p.ry * R)) ** 2 <= k * k);

test('the four style IDs are frozen, in order, and an unknown stored one falls back to off', () => {
  assert.deepEqual(core.COLLAR_STYLES, ['tag', 'band', 'kerchief', 'off']);
  for (const id of core.COLLAR_STYLES) assert.equal(core.collarStyleOf(id), id);
  for (const bad of ['scarf', 'Tag', ' tag', 'tag ', '', 'bowtie', null, undefined, 7, true, {}, ['tag']]) assert.equal(core.collarStyleOf(bad), 'off', String(bad));
});

test('off draws nothing, and an unknown style is off, never a throw', () => {
  const p = core.PRESETS.momo;
  for (const style of ['off', 'scarf', '', null, undefined, 7]) assert.equal(core.collarGeometry(p, pose(), 40, style), null, String(style));
});

test('the device-pixel floors: band 3, tag 6, neckerchief 7 wide and 5 deep, at Ø12 to Ø20 and any pixel density', () => {
  assert.deepEqual(core.COLLAR_MIN, { band: 3, tag: 6, kerchiefW: 7, kerchiefDrop: 5 });
  for (const dpr of [1, 2, 3]) for (const D of [12, 16, 20]) for (const style of STYLES) {
    const g = core.collarGeometry(core.PRESETS.shrimpy, pose(), D, style, { dpr });
    if (style !== 'kerchief') assert.ok(g.width * dpr >= core.COLLAR_MIN.band - 1e-9, `band ${g.width * dpr} at D${D} dpr${dpr}`);
    if (style === 'tag') assert.ok(g.tag.r * 2 * dpr >= core.COLLAR_MIN.tag - 1e-9, `tag at D${D} dpr${dpr}`);
    if (style === 'kerchief') {
      const xs = g.kerchief.pts.map(q => q[0]);
      assert.ok((Math.max(...xs) - Math.min(...xs)) * dpr >= core.COLLAR_MIN.kerchiefW - 1e-9, `kerchief width at D${D} dpr${dpr}`);
      assert.ok((g.kerchief.apex[1] - Math.max(...g.kerchief.pts.map(q => q[1]))) * dpr >= core.COLLAR_MIN.kerchiefDrop - 1e-9, `kerchief drop at D${D} dpr${dpr}`);
    }
  }
});

test('each style has exactly its own parts', () => {
  const g = style => core.collarGeometry(core.PRESETS.momo, pose(), 40, style);
  assert.deepEqual(Object.keys(g('tag')), ['style', 'R', 'width', 'band', 'tag']);
  assert.deepEqual(Object.keys(g('band')), ['style', 'R', 'width', 'band']);
  assert.deepEqual(Object.keys(g('kerchief')), ['style', 'R', 'kerchief']);
  assert.equal(g('tag').band.length, 26);
  assert.ok(g('kerchief').kerchief.pts.length > 4);
  for (const style of STYLES) assert.equal(g(style).style, style);
});

test('the collar is drawn in the front pass, in the one slot between the folded ears and the whiskers', () => {
  assert.equal(core.COLLAR_PASS, 'front');
  const front = core.PASSES[core.COLLAR_PASS];
  assert.equal(front.indexOf('whiskers'), front.indexOf('foldEars') + 1);
});

test('large sizes scale with the head: the band a tenth of R, the tag 0.16 R, the neckerchief about 0.34 R deep', () => {
  const p = core.PRESETS.momo, at = style => core.collarGeometry(p, pose(), 66, style);
  near(at('band').width / at('band').R, .1);
  near(at('tag').tag.r / at('tag').R, .16);
  const k = at('kerchief'), drop = k.kerchief.apex[1] - Math.max(...k.kerchief.pts.map(q => q[1]));
  assert.ok(drop >= .34 * k.R - 1e-9 && drop < .36 * k.R, `the drop is ${drop / k.R} R`); // 0.34 R below the chin, plus the gap between the chin and the nearest sampled point
});

test('every coat, style, pose and size, at either pixel density: the collar is finite and stays on the head', () => {
  for (const p of Object.values(core.PRESETS)) for (const style of STYLES) for (const s of [pose(), pose({ yaw: .6 }), pose({ yaw: -.6, pitch: .4 }), pose({ pitch: -.3 })]) for (const D of [12, 20, 28, 66]) for (const dpr of [1, 2]) {
    const g = core.collarGeometry(p, s, D, style, { dpr });
    assert.ok(finite(g), `${p.name} ${style} D${D}`);
    assert.ok(onHead(g.band || g.kerchief.pts, p, g.R), `${p.name} ${style} D${D} dpr${dpr}`);
  }
});

test('a head of width 0, or a bad pixel ratio, never produces NaN', () => {
  for (const style of STYLES) {
    assert.ok(finite(core.collarGeometry(core.PRESETS.shrimpy, pose(), 0, style)), `${style} at Ø0`);
    const two = core.collarGeometry(core.PRESETS.momo, pose(), 20, style, { dpr: 2 });
    for (const dpr of [NaN, 0, -1, undefined, null]) assert.deepEqual(core.collarGeometry(core.PRESETS.momo, pose(), 20, style, { dpr }), two, `${style} dpr ${dpr}`);
  }
});

test('the tag sits at centre front at rest and follows the face when the head turns', () => {
  const p = core.PRESETS.shrimpy, rest = core.collarGeometry(p, pose(), 66, 'tag'), turned = core.collarGeometry(p, pose({ yaw: .6 }), 66, 'tag');
  assert.ok(Math.abs(rest.tag.x) < 1e-9 && rest.tag.y > 0);
  assert.ok(turned.tag.x > rest.tag.x + 1, 'the tag moves toward the side the face turned to');
  const k = core.collarGeometry(p, pose(), 66, 'kerchief');
  assert.ok(Math.abs(k.kerchief.apex[0]) < 1e-9, 'the neckerchief points straight down at rest');
});

test('the pose is not touched and the same input gives the same output', () => {
  const s = pose({ yaw: .3 }), before = JSON.stringify(s);
  const a = core.collarGeometry(core.PRESETS.momo, s, 28, 'kerchief'), b = core.collarGeometry(core.PRESETS.momo, s, 28, 'kerchief');
  assert.equal(JSON.stringify(s), before);
  assert.deepEqual(a, b);
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test tests/cat/collar.test.mjs`
Expected: FAIL, all ten (`# pass 0`, `# fail 10`): the comparison code has no `COLLAR_STYLES`, no `collarStyleOf`, no `COLLAR_PASS` and no `kerchief`.

- [ ] **Step 3: Make the collar section final**

This replaces everything from the `// ── Collar (COMPARISON ONLY)` heading to `Object.assign(api,{COLLAR_OPTIONS,COLLAR_MIN,collarGeometry});` with the final section. The kerchief and the band come out of the same maths as before, to the digit: only the names and the shape of the result change.

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
start = '// ── Collar (COMPARISON ONLY)'
end = 'Object.assign(api,{COLLAR_OPTIONS,COLLAR_MIN,collarGeometry});'
assert s.count(start) == 1 and s.count(end) == 1
a, b = s.index(start), s.index(end) + len(end)
new = r'''// ── Collar: the agent colour, worn as a thin collar ──────────────────────────
// The colour that used to fill the upstream figure (task.color) is worn as a collar in one of three styles, or not at all.
// Style IDs are frozen contract values (they are stored in settings), in this order: tag (Band and tag), band (Band),
// kerchief (Neckerchief) and off (the default). Pure maths: the renderer paints what collarGeometry returns.
const COLLAR_STYLES=['tag','band','kerchief','off'];
/** The renderer pass the collar is drawn in: between 'foldEars' and 'whiskers' of PASSES.front. PASSES itself stays as A-0 pinned it (fixtures only grow). */
const COLLAR_PASS='front';
/** A stored collar style to a style. An unknown ID, or anything that is not a string, falls back to 'off'. */
const collarStyleOf=id=>typeof id==='string'&&COLLAR_STYLES.includes(id)?id:'off';
/** Smallest sizes, in DEVICE pixels, so a collar still reads as a colour at Ø12 and Ø20. */
const COLLAR_MIN={band:3,tag:6,kerchiefW:7,kerchiefDrop:5};
/**
 * Where one collar sits, in head-local px (before tilt and squash), turning with the face warp. `null` for 'off'.
 *   tag:      {style, R, width, band, tag}   band: a polyline along the lower outline, left to right, inset so its outer edge stays
 *   band:     {style, R, width, band}        inside the head; width: its stroke width (a tenth of R, never under COLLAR_MIN.band
 *   kerchief: {style, R, kerchief}           device px); tag: {x, y, r}, a round tag at centre front; kerchief: {pts, apex}, a
 *                                            triangle under the chin (pts along the lower outline, apex below them).
 * o.dpr is the device pixel ratio (default 2, and 2 for anything that is not above 0); o.detail is as in layout().
 */
function collarGeometry(p,s,D,style,o={}){
 const id=collarStyleOf(style);if(id==='off')return null;
 const dpr=o.dpr>0?o.dpr:2,{R,W}=layout(p,s,0,0,D,{detail:o.detail}),px=n=>n/dpr/R; // device px to R-units
 const width=Math.max(.1*R,COLLAR_MIN.band/dpr),k=Math.max(.7,Math.min(.92,1-(width/2+.5/dpr)/(p.ry*R)));
 const N=90,ring=supPoints(p.rx*k,p.ry*k,p.n,0,0,0,N).slice(0,N); // R-units; index i is angle i/N of a turn, y down
 const out={style:id,R};
 if(id==='kerchief'){const hw=Math.min(p.rx*k,Math.max(.5*p.rx,px(COLLAR_MIN.kerchiefW)*.65)),arc=ring.filter(([x,y])=>y>0&&Math.abs(x)<=hw).sort((a,b)=>a[0]-b[0]),
  [ax,ay]=W(0,p.ry*k),top=Math.max(...arc.map(q=>W(...q)[1]));
  out.kerchief={pts:arc.map(q=>W(...q)),apex:[ax,Math.max(ay,top)+Math.max(.34*R,COLLAR_MIN.kerchiefDrop/dpr)]}}
 else{const lower=ring.slice(N*40/360,N*140/360+1).reverse(); // left to right, 40° to 140°
  out.width=width;out.band=lower.map(([x,y])=>W(x,y));
  if(id==='tag'){const [x,y]=W(0,p.ry*k);out.tag={x,y,r:Math.max(.16*R,COLLAR_MIN.tag/dpr/2)}}}
 return out}
Object.assign(api,{COLLAR_STYLES,collarStyleOf,COLLAR_MIN,COLLAR_PASS,collarGeometry});
'''.rstrip('\n')
open(p, 'w', encoding='utf-8').write(s[:a] + new + s[b:])
PY
git diff --stat design/prototype/cat-core.js
```

Expected: `1 file changed, 26 insertions(+), 19 deletions(-)`.

- [ ] **Step 4: Run the tests**

Run: `node --test tests/cat/collar.test.mjs`
Expected: `# pass 10`, `# fail 0`.

- [ ] **Step 5: Prove the floor test bites (not committed)**

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = 'const width=Math.max(.1*R,COLLAR_MIN.band/dpr)'
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, 'const width=Math.max(.1*R,COLLAR_MIN.band/dpr/2)'))
PY
node --test tests/cat/collar.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = 'const width=Math.max(.1*R,COLLAR_MIN.band/dpr/2)'
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, 'const width=Math.max(.1*R,COLLAR_MIN.band/dpr)'))
PY
node --test tests/cat/collar.test.mjs 2>&1 | grep -E "^# (pass|fail)"
```

Expected: first run `not ok 3 - the device-pixel floors…` and `# fail 1`; after putting the line back, `# pass 10` and `# fail 0`.

- [ ] **Step 6: Add the fixture, its replay test and the file count**

The builder goes above the `@@BUILDERS` marker (the helpers `pose` and `presetOf` are defined earlier in the generator), and the collar's pass becomes one key of the geometry fixture, just above `passes`:

```bash
python3 - <<'PY'
p = 'scripts/gen-cat-fixtures.mjs'
s = open(p, encoding='utf-8').read()
marker = '// @@BUILDERS: each task adds'
assert s.count(marker) == 1
snippet = r'''// ── Collar ───────────────────────────────────────────────────────────────────
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

'''
s = s.replace(marker, snippet + marker)
# The collar's pass is its own key in geometry-cases.json, beside the old passes line, which is not touched.
was = "    passes: core.PASSES,"
assert s.count(was) == 1
s = s.replace(was, "    collarPass: core.COLLAR_PASS,\n" + was)
open(p, 'w', encoding='utf-8').write(s)
PY
cat >> tests/cat/collar.test.mjs <<'EOF'

test('collar-cases.json: every case replays from its own inputs, and the style IDs and floors match', () => {
  const c = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/collar-cases.json', import.meta.url), 'utf8'));
  assert.deepEqual(c.styles, core.COLLAR_STYLES);
  assert.deepEqual(c.min, core.COLLAR_MIN);
  for (const r of c.resolve) assert.equal(core.collarStyleOf(r.id), r.style, String(r.id));
  assert.ok(c.cases.length >= 100);
  for (const k of c.cases) {
    const p = k.kitten ? core.kittenOf(core.PRESETS[k.cat]) : core.PRESETS[k.cat];
    const got = JSON.parse(JSON.stringify(core.collarGeometry(p, pose(k.pose), k.D, k.style, { dpr: k.dpr })));
    assert.deepEqual(compare(got, k.out), [], `${k.cat} ${k.style} D${k.D} dpr${k.dpr}`);
  }
  for (const style of STYLES) for (const D of [12, 20, 66]) for (const dpr of [1, 2]) assert.ok(c.cases.some(k => k.style === style && k.D === D && k.dpr === dpr), `${style} D${D} dpr${dpr} is in the fixture`);
  assert.ok(c.cases.some(k => k.style === 'off' && k.out === null), 'off is in the fixture');
});

test('geometry-cases.json: collarPass names the pass of the collar, and passes is still the line A-0 wrote', () => {
  const g = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/geometry-cases.json', import.meta.url), 'utf8'));
  assert.equal(g.collarPass, core.COLLAR_PASS);
  assert.ok(g.collarPass in g.passes);
  assert.deepEqual(g.passes, core.PASSES);
  assert.ok(!JSON.stringify(g.passes).includes('collar'), 'the collar is not added to passes: fixtures change only by addition');
});
EOF
python3 - <<'PY'
p = 'tests/cat/fixtures.test.mjs'
s = open(p, encoding='utf-8').read()
for was, now in [("const FILES = ['geometry-cases.json',", "const FILES = ['collar-cases.json', 'geometry-cases.json',"), ('holds exactly the seven contract files', 'holds exactly the eight contract files')]:
    assert s.count(was) == 1, was
    s = s.replace(was, now)
open(p, 'w', encoding='utf-8').write(s)
PY
node scripts/gen-cat-fixtures.mjs
ls -l tests/fixtures/cat/collar-cases.json
```

Expected: `wrote 8 fixture files to tests/fixtures/cat` and a `collar-cases.json` of about 145 KB (under the 400 KB the fixtures test allows). `geometry-cases.json` gains one line, `"collarPass": "front",`, just above `"passes"`.

- [ ] **Step 7: Run the whole contract, then the additive check**

```bash
bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓|✗"
node scripts/check-fixtures-additive.mjs a6ec93c
```

Expected: `# tests 90`, `# pass 90`, `# fail 0`; eight `✓` fixture lines (`collar-cases.json` first), `✓ 8 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`. Then the seven old files unchanged with the same line counts as Task 1 step 5, except `✓ geometry-cases.json: 51 old lines unchanged, 1 lines added (new keys: collarPass)`; then `+ collar-cases.json is new` and `✓ fixtures changed only by addition since a6ec93c`.

- [ ] **Step 8: Commit**

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/collar.test.mjs tests/cat/fixtures.test.mjs tests/fixtures/cat/collar-cases.json tests/fixtures/cat/geometry-cases.json
git commit -m "feat(cat): the collar styles become contract, with collar-cases.json

Frozen style IDs tag, band, kerchief and off (an unknown one is off), the device-pixel floors kept.
The collar's pass is the new key collarPass in geometry-cases.json; the passes line is untouched.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 3: The ear fit

**Files:**
- Modify: `design/prototype/cat-core.js` (a new "Ear fit" section above the collar section)
- Modify: `scripts/gen-cat-fixtures.mjs` (a helper above the `geometry-cases.json` builder, and two keys in it)
- Create: `tests/cat/earfit.test.mjs`
- Modify: `tests/fixtures/cat/geometry-cases.json` (generated: two more new keys before `passes`)

**Interfaces:**
- Consumes: `layout`, `earScale`, `DETAIL_FULL_MIN`, `newPose`, `PRESETS`, `kittenOf`, `clamp` from the core; `makeEngine` from the generator (it builds an engine on a fake clock); Task 1's check.
- Produces in `CatCore`: `EAR_FIT` (`{margin: 0.5, minimum: 0.35}`); `earFit(L, pose, ceiling, margin = EAR_FIT.margin, minimum = EAR_FIT.minimum)` to a factor from `minimum` to 1. `L` is a `layout()` result made with ear scale `ek`; `ceiling` is a y in the layout's own coordinates (0, the top of the strip, in the compact notch); the caller then lays out again with `earScale: ek * factor`. Fixture keys in `geometry-cases.json`: `earFit` (`{margin, minimum}`) and `earFitCases`, each case `{cat, kitten, D, cx, cy, earScale, pose, ceiling, margin, minimum, fit}`.
- The signature, the defaults and the use (`ek * factor`, the draw option `earCeiling`) are the ones both app plans already declare, so adopting it changes only the body. The solve is the macOS draft's, taken to the true highest point of the ear's top edge: both drafts solve for the ear's apex only, which in tilted poses left a tip up to 0.1 px inside the half-pixel margin in a few frames (never outside the strip), so their results differ from `earFitCases` in those poses until they follow this version. A pose that is not a number gives 1, as the Tauri plan's test expects.

- [ ] **Step 1: Write the failing tests**

The oracle in the test walks the whole outline the renderer draws, so the closed form is checked against something it does not share code with.

```bash
cat > tests/cat/earfit.test.mjs <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { makeEngine } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const pose = (o = {}) => ({ ...core.newPose(), ...o });
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const NOTCH = [[32, 20], [24, 18]]; // [height of the strip the cat sits in, head width]: the notch, and a screen without one
const POSES = [{}, { earU: 1.4 }, { earU: 1.4, oy: -.26 }, { earU: 1.22, oy: -.26 }, { earU: 1.4, oy: -.3, tilt: .24 }, { earU: 1.4, oy: -.3, tilt: -.24 }, { earU: 1.1, earF: .45, oy: -.1, tilt: .1 }];
const CATS = ['momo', 'shrimpy', 'puff', 'noodle', 'button', 'latte'];
const { margin: MARGIN, minimum: MIN } = core.EAR_FIT;

/** The highest point of an ear in the world (the smallest y), found by walking the whole outline the renderer draws, not by the formula under test. */
function earTop(L, s, e) {
  const R = L.R, { h, bw, tip, cx } = e;
  const segs = [[[-bw, .25 * R], [-bw * cx, -h * .4], [-tip * .9, -h + tip * 1.3]], [[-tip * .9, -h + tip * 1.3], [0, -h - tip * .35], [tip * .9, -h + tip * 1.3]], [[tip * .9, -h + tip * 1.3], [bw * cx, -h * .4], [bw, .25 * R]]];
  let best = Infinity;
  for (const [a, b, c] of segs) for (let i = 0; i <= 400; i++) {
    const t = i / 400, m = 1 - t, x = m * m * a[0] + 2 * m * t * b[0] + t * t * c[0], y = m * m * a[1] + 2 * m * t * b[1] + t * t * c[1];
    const hx = e.bx + x * Math.cos(e.rot) - y * Math.sin(e.rot), hy = e.by + x * Math.sin(e.rot) + y * Math.cos(e.rot); // ear space to head space
    best = Math.min(best, L.head.y + Math.sin(s.tilt) * s.sx * hx + Math.cos(s.tilt) * s.sy * hy);                     // and to the world
  }
  return best;
}
const top = (L, s) => Math.min(...L.ears.map(e => earTop(L, s, e)));
/** A cat in the strip: its ear fit, and its layout with the fit applied. */
function fit(p, s, cy, D, ek = D < core.DETAIL_FULL_MIN ? core.earScale(D) : 1, ...args) {
  const L = core.layout(p, s, 40, cy, D, { earScale: ek }), f = core.earFit(L, s, args[0] ?? 0, args[1], args[2]);
  return { L, f, after: core.layout(p, s, 40, cy, D, { earScale: ek * f }) };
}

test('the defaults: half a pixel of room, never smaller than 0.35', () => {
  assert.deepEqual(core.EAR_FIT, { margin: .5, minimum: .35 });
});

test('a calm cat in the notch keeps its ears; only tall-eared Noodle in a 24 pt strip loses a little', () => {
  for (const [strip, D] of NOTCH) for (const cat of CATS) {
    const f = fit(core.PRESETS[cat], pose(), strip / 2, D).f;
    if (cat === 'noodle' && strip === 24) assert.ok(f > .9 && f < 1, `${f}`);
    else assert.equal(f, 1, `${cat} Ø${D}`);
  }
});

test('in the notch, no ear leaves the strip, and the fit is tight when it shrinks', () => {
  let shrunk = 0;
  for (const cat of CATS) for (const [strip, D] of NOTCH) for (const delta of POSES) {
    const p = core.PRESETS[cat], s = pose(delta), { L, f, after } = fit(p, s, strip / 2, D), where = `${cat} strip ${strip} Ø${D} ${JSON.stringify(delta)}`;
    assert.ok(f >= MIN && f <= 1, where);
    if (f === 1) assert.ok(top(L, s) >= MARGIN - 1e-3, `an ear that was left alone pokes out: ${where}`);
    else {
      shrunk++;
      if (f > MIN + 1e-9) near(top(after, s), MARGIN, 1e-3);   // exactly as small as it has to be
      else assert.ok(top(after, s) > top(L, s), where);         // held at the minimum: the ears are smaller, so the tips are lower than before
    }
  }
  assert.ok(shrunk > 10, 'the poses do need the fit');
});

test('a cat too close to the top gets smaller ears, never smaller than the minimum', () => {
  const p = core.PRESETS.momo, s = pose();
  const close = fit(p, s, 9, 20, 1);
  assert.ok(close.f < 1 && close.f > MIN, `${close.f}`);
  near(top(close.after, s), MARGIN, 1e-3);
  assert.equal(fit(p, s, -30, 20, 1).f, MIN);
});

test('fitting twice changes nothing', () => {
  for (const delta of POSES) {
    const p = core.PRESETS.shrimpy, s = pose(delta), { f, after } = fit(p, s, 16, 20);
    if (f > MIN) near(core.earFit(after, s, 0), 1, 1e-6);
  }
});

test('your own ceiling, margin and minimum', () => {
  const p = core.PRESETS.momo, s = pose({ earU: 1.4, oy: -.26 });
  const base = fit(p, s, 16, 20, .8).f, low = fit(p, s, 16, 20, .8, 5).f, tight = fit(p, s, 16, 20, .8, 0, 0).f;
  assert.ok(low < base, 'a ceiling further down needs smaller ears');
  assert.ok(tight >= base, 'no margin allows bigger ears');
  assert.equal(fit(core.PRESETS.momo, pose(), 8, 20, .8, 0, .5, .5).f, .5);
});

test('a head of width 0, a cat upside down and a pose that is not a number give a number in range, never NaN', () => {
  assert.equal(fit(core.PRESETS.momo, pose(), 16, 0).f, 1);
  for (const s of [pose({ tilt: Math.PI, earU: 1.4 }), pose({ tilt: NaN }), pose({ sy: Infinity }), pose({ sx: NaN, oy: NaN }), pose({ tilt: 20, earU: 9 })]) {
    const f = fit(core.PRESETS.noodle, s, 16, 20).f;
    assert.ok(Number.isFinite(f) && f >= MIN && f <= 1, `${JSON.stringify(s)}: ${f}`);
  }
  assert.equal(fit(core.PRESETS.momo, pose({ tilt: NaN }), 16, 20).f, 1, 'nothing to fit');
});

test('every state and emote, in both motion styles: the ears never leave the compact notch', () => {
  const kinds = [...core.STATES.map(n => ['setState', n]), ...['love', 'happy', 'surprised', 'proud', 'wink', 'yawn', 'annoyed', 'hello', 'zoomies', 'hairball'].map(n => ['emote', n])];
  let shrunk = 0, frames = 0;
  for (const profile of ['playful', 'classic']) for (const cat of ['momo', 'shrimpy', 'noodle']) for (const [strip, D] of NOTCH) for (const [call, name] of kinds) {
    const p = core.PRESETS[cat], { e, step } = makeEngine(p, { profile });
    e[call](name);
    for (let f = 1; f <= 180; f++) {
      step(f);
      if (f % 3) continue;
      const s = e.s, { f: k, after } = fit(p, s, strip / 2, D);
      frames++; if (k < 1) shrunk++;
      if (k > MIN + 1e-9) assert.ok(top(after, s) >= MARGIN - 1e-3, `${profile} ${cat} ${strip}/${D} ${call} ${name} frame ${f}: ${top(after, s)}`);
    }
  }
  assert.ok(shrunk > 100 && shrunk < frames / 2, `${shrunk} of ${frames} frames needed the fit`);
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test tests/cat/earfit.test.mjs`
Expected: FAIL with `TypeError: Cannot destructure property 'margin' of 'core.EAR_FIT' as it is undefined.` (`# pass 0`, `# fail 1`: the file fails as a whole).

- [ ] **Step 3: Add the ear fit to the core**

It goes immediately above the collar section:

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
marker = '// ── Collar: the agent colour, worn as a thin collar'
assert s.count(marker) == 1
snippet = r'''// ── Ear fit: ears that stay inside the strip ─────────────────────────────────
// The compact island's top edge is the top of the screen, and a mask cannot give ears room above it. So the renderer shrinks the ears
// just enough that no ear rises above the strip. This is the solve, in closed form; the page and both apps use it.
const EAR_FIT={margin:.5,minimum:.35};
/**
 * The factor (EAR_FIT.minimum … 1) to multiply the ear scale by so that no ear rises above `ceiling`, a y in the layout's own
 * coordinates (the top edge of the strip the cat sits in: 0 in the compact notch). 1 means the ears already fit, and a cat so close
 * to the ceiling that even the smallest ears would not fit is held at `minimum`, and a pose that is not a number gives 1 (nothing to fit).
 * `margin` is the room kept under the ceiling, in px.
 *   L is a layout() result made with earScale `ek`; the answer is the factor for ek, so layout(..., {earScale: ek * factor}) fits.
 *   s is the pose that made it (the tilt and squash turn the ears).
 * An ear scales about its own base, so its highest point rises in proportion to the scale and one linear solve replaces a search.
 * The top edge of an ear is a parabola (x = 0.9 tip u, y = -h + tip (0.475 + 0.825 u²) for u in -1…1, in ear space), and the world
 * height of an ear-space point is y0 + A x + B y, so the highest point is where u = -0.9 A / (1.65 B), held to -1…1.
 */
function earFit(L,s,ceiling,margin=EAR_FIT.margin,minimum=EAR_FIT.minimum){
 const ct=Math.cos(s.tilt),st=Math.sin(s.tilt);let f=1;
 for(const e of L.ears){
  const cr=Math.cos(e.rot),sr=Math.sin(e.rot),A=st*s.sx*cr+ct*s.sy*sr,B=ct*s.sy*cr-st*s.sx*sr,y0=L.head.y+st*s.sx*e.bx+ct*s.sy*e.by;
  const rise=u=>.9*A*e.tip*u+B*(-e.h+e.tip*(.475+.825*u*u)); // height of the top edge at u above the ear's base (negative: higher up)
  const d=Math.min(rise(-1),rise(1),rise(B>1e-9?clamp(-.9*A/(1.65*B),-1,1):0));
  if(y0+d>=ceiling+margin||d>=-1e-9)continue;
  f=Math.min(f,Math.max(minimum,(ceiling+margin-y0)/d))}
 return Number.isFinite(f)?Math.max(minimum,Math.min(1,f)):1}
Object.assign(api,{EAR_FIT,earFit});

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, snippet + marker))
PY
```

- [ ] **Step 4: Run the tests**

Run: `node --test tests/cat/earfit.test.mjs`
Expected: `# pass 8`, `# fail 0`.

- [ ] **Step 5: Prove the tight-fit test bites (not committed)**

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = 'f=Math.min(f,Math.max(minimum,(ceiling+margin-y0)/d))'
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, 'f=Math.min(f,Math.max(minimum,(ceiling-y0)/d))'))
PY
node --test tests/cat/earfit.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = 'f=Math.min(f,Math.max(minimum,(ceiling-y0)/d))'
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, 'f=Math.min(f,Math.max(minimum,(ceiling+margin-y0)/d))'))
PY
node --test tests/cat/earfit.test.mjs 2>&1 | grep -E "^# (pass|fail)"
```

Expected: with the margin forgotten, five `not ok` lines (tests 2, 3, 4, 6 and 8, among them `in the notch, no ear leaves the strip, and the fit is tight…` and `a cat too close to the top…`), `# pass 3` and `# fail 5`; after putting it back, `# pass 8` and `# fail 0`.

- [ ] **Step 6: Add the fixture keys and the replay test**

```bash
python3 - <<'PY'
p = 'scripts/gen-cat-fixtures.mjs'
s = open(p, encoding='utf-8').read()
head = "FILES['geometry-cases.json'] = () => {"
assert s.count(head) == 1
snippet = r'''/** Ear fit: the factor for the ears of a cat in a strip, as the compact island uses it (a 32 pt notch strip, or 24 pt without a notch). */
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

'''
s = s.replace(head, snippet + head)
was = "    passes: core.PASSES,"
assert s.count(was) == 1
s = s.replace(was, "    earFit: core.EAR_FIT,\n    earFitCases: earFitCases(),\n" + was)
open(p, 'w', encoding='utf-8').write(s)
PY
cat >> tests/cat/earfit.test.mjs <<'EOF'

test('geometry-cases.json: every ear fit case replays from its own inputs', () => {
  const g = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/geometry-cases.json', import.meta.url), 'utf8'));
  assert.deepEqual(g.earFit, core.EAR_FIT);
  assert.ok(g.earFitCases.length >= 80);
  for (const c of g.earFitCases) {
    const base = core.PRESETS[c.cat], p = c.kitten ? core.kittenOf(base) : base, s = pose(c.pose);
    const L = core.layout(p, s, c.cx, c.cy, c.D, { earScale: c.earScale });
    near(core.earFit(L, s, c.ceiling, c.margin, c.minimum), c.fit);
  }
  assert.ok(g.earFitCases.some(c => c.fit === 1) && g.earFitCases.some(c => c.fit === MIN) && g.earFitCases.some(c => c.fit > MIN && c.fit < 1), 'the cases need no fit, the minimum and something in between');
});
EOF
node scripts/gen-cat-fixtures.mjs
```

Expected: `wrote 8 fixture files to tests/fixtures/cat`.

- [ ] **Step 7: Run the whole contract, then the additive check**

```bash
bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓ [0-9]|✗"
node scripts/check-fixtures-additive.mjs a6ec93c | grep -E "geometry|✓ fixtures|✗"
git diff tests/fixtures/cat/geometry-cases.json | grep -c '^-[^-]' || true
```

Expected: `# tests 99`, `# pass 99`, `# fail 0`, `✓ 8 fixture files match cat-core.js`; then `✓ geometry-cases.json: 51 old lines unchanged, 96 lines added (new keys: collarPass, earFit, earFitCases)` and `✓ fixtures changed only by addition since a6ec93c`; and the last command prints `0` (no old line was removed or changed).

- [ ] **Step 8: Commit**

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/earfit.test.mjs tests/fixtures/cat/geometry-cases.json
git commit -m "feat(cat): the ear fit becomes contract, tested against a brute-force outline

earFit shrinks the compact notch's ears just enough that no tip leaves the strip; cases added to geometry-cases.json.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 4: Compact flat fills

**Files:**
- Modify: `design/prototype/cat-core.js` (a new "Compact detail: flat fills" section above the collar section, and one line in `layout()`)
- Modify: `scripts/gen-cat-fixtures.mjs` (a helper and three keys in the `geometry-cases.json` builder)
- Create: `tests/cat/flatfill.test.mjs`
- Modify: `tests/fixtures/cat/geometry-cases.json` (generated: three more new keys before `passes`)

**Interfaces:**
- Consumes: `DETAIL_FULL_MIN`, `detailOf`, `layout`, `hex`, `lerp`, `PRESETS`, `CAT_IDS`, `kittenOf` from the core; Task 3's generator helpers.
- Produces in `CatCore`: `detailLevel(D, override)` to `{detail: 'full' | 'compact', full: boolean, flatFill: boolean}` (`flatFill` is exactly `!full`; `override` is `layout()`'s `o.detail`: an explicit `'full'` or `'compact'` wins over `D`); `FLAT_FILL` (`{headMix: 0.5, earMix: 0.5, ruffMix: 0.6, rimGradient: false, crown: {rx: 0.4, ry: 0.26, alpha: 0.5}, point: {rx: 0.86, ry: 0.54, alpha: 0.85}}`, radii in R; the point mask is tuned, see below); `mixHex(a, b, t)` to `[r, g, b]` unrounded; `flatFillColors(preset)` to `{head, ears: [left, right], ruff, point}` (each `[r, g, b]` in 0 to 255; `ruff` is null without a ruff and `point` null unless the coat is `point`, Latte and Cloud). `flatFill` is exactly `!layout(...).full`, so an app that already branches on `layout().full` (both app plans do) needs no new function, only the constants. `layout()` still returns the same object (it gains no field: an app comparing whole layouts against `anchors` would see an extra key); the detail it reads now comes from `detailLevel`, so no existing anchor changes. Fixture keys in `geometry-cases.json`: `flatFill` (the constants), `detailLevels` (`{D, override, level}`) and `flatColors` (every cat ID to its flat colours, the point mask's included).
- **The point mask is tuned, not the macOS draft's 0.5 R by 0.34 R.** At Ø20 that drawing was visibly smaller than the gradient it replaces (a radial fade 1.55 R wide by R tall to 0.66 R, 0.97 strong in the middle, 0.82 at 0.42 R). The controller's ruling is that its visible extent matches what the gradient showed at Ø20 and Ø28, so `point` is `{rx: 0.86, ry: 0.54, alpha: 0.85}`: found by a grid search over radii and alpha against the old gradient on Latte and Cloud at Ø20, Ø24 and Ø28, then checked side by side (Task 5, step 6). The numbers have the same total ink as the gradient, and the flat edge lies between where the fade had dropped to half and to a quarter of its strength (0.80 R by 0.52 R and 0.91 R by 0.59 R). `flatFill.test.mjs` pins both facts. The apps' drafts hard-code the old 0.5 and 0.34 and must take these numbers.

- [ ] **Step 1: Write the failing tests**

```bash
cat > tests/cat/flatfill.test.mjs <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const pose = (o = {}) => ({ ...core.newPose(), ...o });
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const nearAll = (got, want) => { assert.equal(got.length, want.length); got.forEach((v, i) => near(v, want[i])); };

test('detailLevel: compact and flat below Ø28, full from Ø28, and an explicit detail wins', () => {
  assert.deepEqual(core.detailLevel(27.999), { detail: 'compact', full: false, flatFill: true });
  assert.deepEqual(core.detailLevel(28), { detail: 'full', full: true, flatFill: false });
  for (const D of [0, 12, 20, 27.9]) assert.equal(core.detailLevel(D).flatFill, true, `Ø${D}`);
  for (const D of [28, 44, 66]) assert.equal(core.detailLevel(D).flatFill, false, `Ø${D}`);
  assert.deepEqual(core.detailLevel(66, 'compact'), { detail: 'compact', full: false, flatFill: true });
  assert.deepEqual(core.detailLevel(12, 'full'), { detail: 'full', full: true, flatFill: false });
  assert.deepEqual(core.detailLevel(12, undefined), core.detailLevel(12));
});

test('layout() and detailLevel() always agree on the detail, and on the old detailOf()', () => {
  const p = core.PRESETS.shrimpy;
  for (const D of [0, 12, 20, 27.999, 28, 66]) {
    assert.equal(core.detailLevel(D).detail, core.detailOf(D));
    for (const o of [undefined, 'full', 'compact']) assert.equal(core.layout(p, pose(), 0, 0, D, { detail: o }).full, core.detailLevel(D, o).full, `Ø${D} ${o}`);
  }
});

test('FLAT_FILL: the numbers of the flat drawing', () => {
  assert.deepEqual(core.FLAT_FILL, { headMix: .5, earMix: .5, ruffMix: .6, rimGradient: false, crown: { rx: .4, ry: .26, alpha: .5 }, point: { rx: .86, ry: .54, alpha: .85 } });
});

// The gradient the flat point mask replaced (the page drew it before A-0b): a radial fade from 0.05 R to 0.66 R on its short axis, stretched
// 1.55 times wider than tall, 0.97 strong in the middle, 0.82 at 60 % of the way and 0 at the edge. rho is a radius in R on the short axis.
const STRETCH = 1.55, R0 = .05, R1 = .66;
const gradAlpha = rho => { const t = Math.min(1, Math.max(0, (rho - R0) / (R1 - R0))); return t <= .6 ? .97 + (.82 - .97) * t / .6 : .82 * (1 - t) / .4; };
const contour = frac => { let lo = 0, hi = R1; for (let i = 0; i < 60; i++) { const mid = (lo + hi) / 2; if (gradAlpha(mid) > frac * .97) lo = mid; else hi = mid; } return lo; }; // rho where the fade is down to frac of its middle strength

test('FLAT_FILL.point keeps what the gradient it replaced showed: the same ink, and an edge between its half-strength and quarter-strength contours', () => {
  const { rx, ry, alpha } = core.FLAT_FILL.point;
  let ink = 0; const N = 20000;
  for (let i = 0; i < N; i++) { const rho = (i + .5) * R1 / N; ink += gradAlpha(rho) * 2 * Math.PI * STRETCH * rho * R1 / N; }
  near(alpha * Math.PI * rx * ry / ink, 1, .02);                                       // alpha times the flat area is the gradient's total ink, to 2 %
  assert.ok(ry >= contour(.5) && ry <= contour(.25), `ry ${ry} is not between ${contour(.5)} and ${contour(.25)}`);
  assert.ok(rx >= STRETCH * contour(.5) && rx <= STRETCH * contour(.25), `rx ${rx} is not between ${STRETCH * contour(.5)} and ${STRETCH * contour(.25)}`);
  near(rx / ry / STRETCH, 1, .05);                                                     // and about as stretched as the gradient was
});

test('mixHex goes from the first colour to the second without rounding', () => {
  nearAll(core.mixHex('#3B9EFF', '#8B5CF6', 0), [59, 158, 255]);
  nearAll(core.mixHex('#3B9EFF', '#8B5CF6', 1), [139, 92, 246]);
  nearAll(core.mixHex('#000000', '#010101', .5), [.5, .5, .5]);
});

test('flatFillColors, checked by hand: the head and ears halfway, the ruff 0.6 of the way, ears with their own colour keep it, the point mask is the point colour', () => {
  const sh = core.flatFillColors(core.PRESETS.shrimpy);   // top #A08A70, bot #6E5B49, ruff #7E6750 to #B49C7A
  nearAll(sh.head, [135, 114.5, 92.5]); nearAll(sh.ears[0], [135, 114.5, 92.5]); nearAll(sh.ears[1], [135, 114.5, 92.5]);
  nearAll(sh.ruff, [158.4, 134.8, 105.2]);
  const pa = core.flatFillColors(core.PRESETS.patches);   // ears #E3994E and #2C2B2F
  nearAll(pa.ears[0], [227, 153, 78]); nearAll(pa.ears[1], [44, 43, 47]); assert.equal(pa.ruff, null);
  nearAll(core.flatFillColors(core.PRESETS.momo).head, [61, 61, 65]);
  nearAll(core.flatFillColors(core.PRESETS.latte).point, [74, 53, 40]);      // #4A3528
  nearAll(core.flatFillColors(core.PRESETS.cloud).point, [125, 135, 150]);   // #7D8796
  assert.equal(sh.point, null); assert.equal(pa.point, null);
});

test('every coat and kitten has finite flat colours in 0 to 255, a ruff only when it has one and a point colour only on a point coat', () => {
  for (const id of core.CAT_IDS) for (const p of [core.PRESETS[id], core.kittenOf(core.PRESETS[id])]) {
    const c = core.flatFillColors(p);
    for (const rgb of [c.head, ...c.ears, ...(c.ruff ? [c.ruff] : []), ...(c.point ? [c.point] : [])]) assert.ok(rgb.length === 3 && rgb.every(v => Number.isFinite(v) && v >= 0 && v <= 255), `${p.name}`);
    assert.equal(c.ruff === null, !p.ruff, p.name);
    assert.equal(c.point === null, p.coat !== 'point', p.name);
  }
  assert.deepEqual(core.flatFillColors(core.kittenOf(core.PRESETS.shrimpy)), core.flatFillColors(core.PRESETS.shrimpy), 'a kitten keeps its parent coat');
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test tests/cat/flatfill.test.mjs`
Expected: FAIL (`core.detailLevel is not a function`).

- [ ] **Step 3: Add the flat-fill section and route `layout()` through it**

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
marker = '// ── Collar: the agent colour, worn as a thin collar'
assert s.count(marker) == 1
snippet = r'''// ── Compact detail: flat fills ───────────────────────────────────────────────
/**
 * What the renderer draws at head width D: `detail` ('full' | 'compact'), `full`, and `flatFill`, which is on exactly when the cat is
 * compact (below Ø28). `override` is layout()'s o.detail: an explicit 'full' or 'compact' wins over D.
 */
const detailLevel=(D,override)=>{const full=override?override==='full':D>=DETAIL_FULL_MIN;return{detail:full?'full':'compact',full,flatFill:!full}};
/**
 * The flat drawing, for when detailLevel().flatFill is on. At Ø12 to Ø27 a gradient cannot be seen and costs a shading pass each, so:
 *   head: one fill, the preset's top and bot colour mixed headMix of the way (0.5, halfway);
 *   ears: one fill each, the ear's top and bot colour (the ear's own colour, if it has one, is both) mixed earMix of the way;
 *   ruff: one fill, the ruff's inner colour mixed ruffMix of the way (0.6) to its outer one;
 *   rim:  no rim gradient (rimGradient false). The white rim line of the dark coats stays;
 *   tabby crown band: one ellipse, radii crown.rx and crown.ry in R, at the centre where the gradient was, in the stripe colour at crown.alpha;
 *   point mask: one ellipse, radii point.rx and point.ry in R, at the centre where the gradient was, in the point colour at point.alpha.
 *     Tuned to the gradient it replaces (a fade 1.55 R wide by R tall to 0.66 R): the same total ink, and an edge between where that fade had
 *     dropped to half and to a quarter of its strength, which is what it showed at Ø20 and at Ø28 on Latte and Cloud.
 * Everything else (markings, eyes, blush, the state tint) is drawn as in the full cat.
 */
const FLAT_FILL={headMix:.5,earMix:.5,ruffMix:.6,rimGradient:false,crown:{rx:.4,ry:.26,alpha:.5},point:{rx:.86,ry:.54,alpha:.85}};
const mixHex=(a,b,t)=>{const y=hex(b);return hex(a).map((v,i)=>lerp(v,y[i],t))};
/** The flat colours of a preset, [r, g, b] in 0…255 (not rounded): the head, the two ears (left, right), the ruff (null without one) and the point mask (null unless the coat is 'point'). */
function flatFillColors(p){const ear=sd=>{const c=p.earCols&&p.earCols[sd<0?0:1];return mixHex(c||p.top,c||p.bot,FLAT_FILL.earMix)};
 return{head:mixHex(p.top,p.bot,FLAT_FILL.headMix),ears:[ear(-1),ear(1)],ruff:p.ruff?mixHex(p.ruff.col[1],p.ruff.col[0],FLAT_FILL.ruffMix):null,point:p.coat==='point'?hex(p.point):null}}
Object.assign(api,{detailLevel,FLAT_FILL,mixHex,flatFillColors});

'''
s = s.replace(marker, snippet + marker)
was = "const R=D/(2*p.rx),full=o.detail?o.detail==='full':D>=DETAIL_FULL_MIN,T=o.T||0"
assert s.count(was) == 1
s = s.replace(was, "const R=D/(2*p.rx),full=detailLevel(D,o.detail).full,T=o.T||0")
open(p, 'w', encoding='utf-8').write(s)
PY
```

- [ ] **Step 4: Run the new tests and the old ones**

```bash
node --test tests/cat/flatfill.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"
node --test tests/cat/*.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"
```

Expected: `# pass 7`, `# fail 0` for the new file (the replay test comes in Step 5). The whole directory: `# pass 106`, `# fail 0`, so `layout()` kept every behaviour the A-0 tests pin (the `explicit detail wins` checks included).

- [ ] **Step 5: Add the fixture keys and the replay test**

```bash
python3 - <<'PY'
p = 'scripts/gen-cat-fixtures.mjs'
s = open(p, encoding='utf-8').read()
head = "FILES['geometry-cases.json'] = () => {"
assert s.count(head) == 1
snippet = r'''/** The levels of detail for a head width, and with an explicit override. */
const detailLevelCases = () => [[0], [12], [20], [27.999], [28], [28.001], [44], [66], [66, 'compact'], [12, 'full'], [28, 'compact'], [27.999, 'full']]
  .map(([D, override]) => ({ D, override: override ?? null, level: core.detailLevel(D, override) }));

'''
s = s.replace(head, snippet + head)
was = "    earFitCases: earFitCases(),\n    passes: core.PASSES,"
assert s.count(was) == 1
s = s.replace(was, "    earFitCases: earFitCases(),\n    flatFill: core.FLAT_FILL,\n    detailLevels: detailLevelCases(),\n    flatColors: Object.fromEntries(core.CAT_IDS.map(id => [id, core.flatFillColors(core.PRESETS[id])])),\n    passes: core.PASSES,")
open(p, 'w', encoding='utf-8').write(s)
PY
cat >> tests/cat/flatfill.test.mjs <<'EOF'

test('geometry-cases.json: the detail levels and the flat colours replay from their inputs', () => {
  const g = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/geometry-cases.json', import.meta.url), 'utf8'));
  assert.deepEqual(g.flatFill, core.FLAT_FILL);
  assert.ok(g.detailLevels.length >= 12);
  for (const c of g.detailLevels) assert.deepEqual(core.detailLevel(c.D, c.override ?? undefined), c.level, `Ø${c.D} ${c.override}`);
  assert.ok(g.detailLevels.some(c => c.level.flatFill) && g.detailLevels.some(c => !c.level.flatFill));
  assert.deepEqual(Object.keys(g.flatColors), core.CAT_IDS);
  for (const id of core.CAT_IDS) assert.deepEqual(compare(JSON.parse(JSON.stringify(core.flatFillColors(core.PRESETS[id]))), g.flatColors[id]), [], id);
});
EOF
node scripts/gen-cat-fixtures.mjs
```

Expected: `wrote 8 fixture files to tests/fixtures/cat`.

- [ ] **Step 6: Run the whole contract, then the additive check**

```bash
bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓ [0-9]|✗"
node scripts/check-fixtures-additive.mjs a6ec93c | grep -E "geometry|✓ fixtures|✗"
git diff tests/fixtures/cat/geometry-cases.json | grep -c '^-[^-]' || true
```

Expected: `# tests 107`, `# pass 107`, `# fail 0`, `✓ 8 fixture files match cat-core.js`; then `✓ geometry-cases.json: 51 old lines unchanged, 129 lines added (new keys: collarPass, earFit, earFitCases, flatFill, detailLevels, flatColors)` and `✓ fixtures changed only by addition since a6ec93c`; and `0` old lines removed or changed.

- [ ] **Step 7: Commit**

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/flatfill.test.mjs tests/fixtures/cat/geometry-cases.json
git commit -m "feat(cat): the compact detail level draws flat fills, as contract (detailLevel, FLAT_FILL)

Below Ø28: flat head, ear and ruff fills, no rim gradient, a flat tabby crown and point mask (tuned to the gradient it replaces). Cases added to geometry-cases.json.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 5: The prototype page

**Files:**
- Modify: `design/prototype/notchmeow.html` (about 54 lines in, 73 out)

**Interfaces:**
- Consumes from `CatCore`: `earScale`, `earFit`, `detailLevel`, `flatFillColors`, `FLAT_FILL`, `COLLAR_STYLES`, `COLLAR_MIN`, `collarGeometry`, and the existing `layout`, `earGeom`.
- Produces: a page whose `drawCat(ctx, e, cx, cy, D, o)` lays every compact cat out with the compact ear scale (`earScale(D)`, as the apps do) and takes two new options, `o.earCeiling` (a y in canvas px: the ears shrink further, by `earFit`, just enough that no tip rises above it, so the ear scale becomes `earScale(D) * f`; the notch cat passes 0) and `o.collar` (`{style, col}`, `style` one of `COLLAR_STYLES`, `'off'` draws nothing); and the page globals `COLLAR` (the style, `'off'` by default), `AGENT`, `AGENTS`, `AGENT_COL`, `collarOf(col)` and `bigCollar(engine)`. The Collar panel is `#collarPanel` with the rows `#colRow` (style) and `#agRow` (agent colour for the big cats and the ladder).
- What changes on the page, and nothing else: the Collar comparison (its CSS, its three-column grid and its live canvases) becomes the selector; every compact cat's ears are drawn at the compact ear scale (0.8 times at Ø20 and below, easing to 1 at Ø28) and the notch cat's ears also obey the ear fit; below Ø28 every cat is drawn with the flat fills; the Greeting panel's "Same island and same cat as in the apps" and the Size ladder's note are made true. The page shows exactly what the apps draw: before this task it applied neither the ear scale nor the fit.

The page is changed by a one-off script, not by hand: it checks the hash of the old page and that each replacement matches exactly one place. The check that "the page behaves exactly as before" is pixel based. A headless browser loads the old page (`a6ec93c`) and the new page with a **virtual clock** (`performance.now` and `requestAnimationFrame` are replaced, so a frame is exactly 1/60 s) and an **order-independent `Math.random`** (its value depends only on the virtual time). It drives every state, emote, poke, both catches, the personalities, both motion styles, fur lines, the island and the greeting, plus the compact island in every state and the approval hop frame by frame, and takes 166 screenshots of the old page and 201 of the new one (35 of them show the new collar selector and exist only there). The old page is run twice first, to prove the check itself is steady. Chromium's canvas is not bit-steady: a stray pixel or two moves by a few levels, which the comparison ignores. On the new page the run also records every ear scale a cat is laid out with, and reports whether each was the compact ear scale (or the ear fit's smaller one).

- [ ] **Step 1: Check the page is the one from `a6ec93c` and set up the check folder**

```bash
T=${TMPDIR:-/tmp}/a0b-check; mkdir -p "$T/old"
git show a6ec93c:design/prototype/notchmeow.html > "$T/old/notchmeow.html"
git show a6ec93c:design/prototype/cat-core.js > "$T/old/cat-core.js"
shasum -a 256 "$T/old/notchmeow.html" design/prototype/notchmeow.html
```

Expected: both lines show `45df0d00fb63f62ca76b961f152d3dec651b29ca301d009147faa8c8b643c616`. If the second differs, stop: the page is not at `a6ec93c`.

- [ ] **Step 2: Write the one-off tools**

Six files, none committed: the run script, its generator, the comparison, the expectation check, a zoom tool for looking, and the browser config.

```bash
T=${TMPDIR:-/tmp}/a0b-check
cat > "$T/shots.js" <<'EOF'
async page => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.addInitScript(() => {
    let t = 0; const cbs = [];
    performance.now = () => t;
    window.requestAnimationFrame = cb => { cbs.push(cb); return cbs.length; };
    window.__step = (n, dt = 1000 / 60) => { for (let i = 0; i < n; i++) { t += dt; const q = cbs.splice(0); q.forEach(f => f(t)); } };
    // Order-independent: the value depends only on the virtual time, so adding or removing an engine cannot shift anyone else's dice.
    Math.random = () => { const x = Math.sin(t * 12.9898 + 78.233) * 43758.5453; return x - Math.floor(x); };
  });
  const errors = [];
  page.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') errors.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  await page.goto(__URL__);
  const OUT = __OUT__, NEW = __NEW__;
  // New page only: note every ear scale a cat is laid out with, per head width, so the run can check the compact ear scale and the ear fit are applied.
  if (NEW) await page.evaluate(() => { const real = CatCore.layout; window.__ear = {}; CatCore.layout = (p, s, cx, cy, D, o = {}) => { (window.__ear[D] ||= new Set()).add(o.earScale); return real(p, s, cx, cy, D, o); }; });
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
  await btn('chRow', 'Shrimpy'); await step(60);
  await page.evaluate(() => gcReplay());
  { let fr = 0; for (const [tag, target] of [['0p5', 30], ['1p0', 60], ['1p7', 102], ['2p2', 132], ['3p0', 180], ['4p0', 240], ['5p0', 300], ['5p7', 342]]) { await step(target - fr); fr = target; await page.locator('#cvG').screenshot({ path: `${OUT}/13-greet-panel-${tag}.png` }); } }
  await btn('nkRow', 'Play greeting'); await step(120); await shot('12-island-greeting-2s', ['#desk']);
  await step(60); await shot('12-island-greeting-3s', ['#desk']); await step(120); await shot('12-island-greeting-5s', ['#desk']); await step(120);
  // A-0b: the compact island in every state, then the approval hop frame by frame (the ears reach the top of the screen)
  await calm();
  for (const st of ['idle', 'working', 'thinking', 'searching', 'approval', 'question', 'error', 'finished', 'ratelimit', 'sleeping', 'dizzy']) { await btn('stRow', st); await step(100); await calm(); await shot('14-compact-' + st, ['#desk']); }
  await btn('stRow', 'idle'); await step(120); await calm();
  await btn('stRow', 'approval');
  { let fr = 0; for (const target of [6, 9, 12, 15, 18, 21, 24, 30]) { await step(target - fr); fr = target; await shot('15-hop-f' + String(target).padStart(2, '0'), ['#desk']); } }
  await btn('stRow', 'idle'); await step(120); await calm();
  await page.locator('#collarPanel').scrollIntoViewIfNeeded(); await shot('16-collar-panel', ['#collarPanel']);
  await page.evaluate(() => window.scrollTo(0, 0));
  if (NEW) {
    await calm(); await shot('20-collar-off-idle', ['#figShrimpy', '#desk', '#ladder']);
    await btn('stRow', 'working'); await step(100); await calm();
    for (const [row, tag] of [['Band and tag', 'tag'], ['Band', 'band'], ['Neckerchief', 'kerchief']]) {
      await btn('colRow', row); await step(30); await calm();
      await shot('21-collar-' + tag, ['#figMomo', '#figShrimpy', '#more', '#desk', '#ladder']);
      await page.locator('#desk').click({ position: { x: 640, y: 120 } }); await step(60); await calm(); await shot('22-collar-' + tag + '-expanded', ['#desk']);
      await page.locator('#desk').click({ position: { x: 640, y: 120 } }); await step(60); await calm();
    }
    await btn('colRow', 'Band and tag');
    for (const ag of ['Gemini CLI', 'Codex', 'Antigravity', 'Stripe \\(dark\\)']) { await btn('agRow', ag); await step(30); await calm(); await shot('23-agent-' + ag.split(' ')[0], ['#figShrimpy', '#ladder']); }
    await btn('agRow', 'Claude Code');
    await btn('stRow', 'idle'); await step(100); await calm(); await shot('24-collar-tag-idle-none', ['#figShrimpy', '#desk']);
    await btn('colRow', 'Off'); await step(30); await calm(); await shot('25-collar-off-again', ['#figShrimpy', '#desk', '#ladder']);
    await page.locator('#collarPanel').scrollIntoViewIfNeeded(); await shot('26-collar-panel-after', ['#collarPanel']);
  }
  const dump = await page.evaluate(() => JSON.stringify({ canvases: document.querySelectorAll('canvas').length, state: curState }));
  // Every size must have been laid out at earScale(D) (1 from Ø28 up), and never above it or below 0.35 of it (the ear fit); and the fit must have engaged.
  const ears = NEW ? await page.evaluate(() => {
    const bad = []; let fitSeen = false;
    for (const [k, vals] of Object.entries(window.__ear)) {
      const want = CatCore.earScale(+k);
      if (!vals.has(want)) bad.push(`Ø${k} was never laid out at ${want}`);
      for (const v of vals) { if (v > want + 1e-12 || v < .35 * want - 1e-12) bad.push(`Ø${k}: ${v}`); if (v < want - 1e-9) fitSeen = true; }
    }
    return { bad, fitSeen };
  }) : null;
  return JSON.stringify(NEW ? { dump, errors, ears } : { dump, errors });
}
EOF
cat > "$T/mkshots.mjs" <<'EOF'
// One-off, not committed: writes the run script for one page to stdout.
// Usage: node mkshots.mjs <page.html> <output folder (or file)> <true|false: is this the new page> [template, default shots.js]
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [page, out, isNew, name = 'shots.js'] = process.argv.slice(2);
const tpl = fs.readFileSync(new URL('./' + name, import.meta.url), 'utf8');
process.stdout.write(tpl.replace('__URL__', JSON.stringify(pathToFileURL(path.resolve(page)).href)).replace('__OUT__', JSON.stringify(path.resolve(out))).replace('__NEW__', isNew));
EOF
cat > "$T/png-compare.mjs" <<'EOF'
// One-off, not committed: compares two folders of same-named PNG screenshots, pixel by pixel.
// Usage: node png-compare.mjs <folderA> <folderB> [skip-regex]
// Chromium's canvas is not bit-steady from run to run (a handful of pixels move by a few levels out of 255), so a pixel only
// counts as different when it is off by more than TOL = 3 levels, and a cluster of SPECK = 8 such pixels or fewer is ignored.
// identical: nothing is left. different: something is; its clusters
// (boxes of nearby differing pixels, as x0,y0-x1,y1) are listed so you can see WHERE it differs.
// Exit status 1 only for a size mismatch or a missing file; "different" is judged by you against the plan's expected list.
import fs from 'node:fs'; import zlib from 'node:zlib'; import { pathToFileURL } from 'node:url';

export function decode(file) {
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

/** Groups differing pixels into clusters: 8x8 cells that hold a difference, joined with their neighbours. Returns {box: [x0, y0, x1, y1], n} for each. */
function clusters(cells, W, H) {
  const CW = Math.ceil(W / 8), seen = new Set(), out = [];
  for (const c of cells.keys()) {
    if (seen.has(c)) continue;
    const stack = [c], box = [Infinity, Infinity, -1, -1]; let n = 0; seen.add(c);
    while (stack.length) {
      const k = stack.pop(), cx = k % CW, cy = (k - cx) / CW; n += cells.get(k);
      box[0] = Math.min(box[0], cx * 8); box[1] = Math.min(box[1], cy * 8); box[2] = Math.max(box[2], cx * 8 + 7); box[3] = Math.max(box[3], cy * 8 + 7);
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const m = (cy + dy) * CW + cx + dx; if (cx + dx >= 0 && cx + dx < CW && cells.has(m) && !seen.has(m)) { seen.add(m); stack.push(m); } }
    }
    out.push({ n, box: [box[0], box[1], Math.min(box[2], W - 1), Math.min(box[3], H - 1)] });
  }
  return out;
}

const TOL = 3, SPECK = 8;
/** {n, max, boxes}: the pixels off by more than TOL levels, in clusters of more than SPECK pixels. n is -1 when the sizes differ. */
export function diff(fa, fb) {
  const A = decode(fa), B = decode(fb);
  if (A.W !== B.W || A.H !== B.H) return { n: -1, size: [A.W, A.H, B.W, B.H] };
  let max = 0; const cells = new Map(), CW = Math.ceil(A.W / 8);
  for (let i = 0; i < A.W * A.H; i++) {
    let m = 0;
    for (let k = 0; k < Math.min(A.bpp, 3); k++) m = Math.max(m, Math.abs(A.data[i * A.bpp + k] - B.data[i * B.bpp + k]));
    if (m > TOL) { max = Math.max(max, m); const c = Math.floor(Math.floor(i / A.W) / 8) * CW + Math.floor((i % A.W) / 8); cells.set(c, (cells.get(c) || 0) + 1); }
  }
  const real = clusters(cells, A.W, A.H).filter(c => c.n > SPECK).sort((p, q) => p.box[0] - q.box[0] || p.box[1] - q.box[1]);
  return { n: real.reduce((t, c) => t + c.n, 0), max, boxes: real.map(c => c.box) };
}

if (import.meta.url === pathToFileURL(fs.realpathSync(process.argv[1])).href) {
  const [A, B, skip] = process.argv.slice(2);
  const tally = { identical: 0, different: 0, missing: 0, size: 0 };
  for (const f of fs.readdirSync(A).filter(f => f.endsWith('.png')).sort()) {
    if (skip && new RegExp(skip).test(f)) continue;
    if (!fs.existsSync(`${B}/${f}`)) { tally.missing++; console.log('MISSING', f); continue; }
    const d = diff(`${A}/${f}`, `${B}/${f}`);
    if (d.n === -1) { tally.size++; console.log('SIZE', f, JSON.stringify(d.size)); }
    else if (d.n === 0) tally.identical++;
    else { tally.different++; console.log('DIFFERENT', f, `${d.n} px, up to ${d.max} levels, in ${d.boxes.length} place(s): ${d.boxes.map(b => `${b[0]},${b[1]}-${b[2]},${b[3]}`).join('  ')}`); }
  }
  console.log(Object.entries(tally).map(([k, v]) => `${k}=${v}`).join(' '));
  process.exit(tally.missing || tally.size ? 1 : 0);
}
EOF
cat > "$T/expect-diffs.mjs" <<'EOF'
// One-off, not committed: checks that the new page differs from the old one ONLY where the plan says it should.
// Usage: node expect-diffs.mjs <before folder> <after folder>
// Allowed: compact cats (the notch cat and the session cats in the compact island, in the expanded rows, and in the end of the greeting),
// and the compact columns of the size ladder (Ø12 to Ø24 and the Ø16 kitten). A compact cat changes for three reasons, and only these: its
// fills are flat; its ears are smaller (the compact ear scale: 0.8 times at Ø20 and below, easing to 1 at Ø28); and while the notch cat
// hops, its ears shrink a little more so that no tip leaves the island (the ear fit). Everything else must be pixel for pixel the same.
import fs from 'node:fs';
import { decode, diff } from './png-compare.mjs';

const [A, B] = process.argv.slice(2);
const NEW_ONLY = /^(16|2\d)-/;                          // screenshots that only the new page takes (the collar panel and the collar styles)
const COMPACT_DESK = [[440, 0, 488, 34], [656, 0, 720, 34]];  // the notch cat (Ø20) and the three session cats (Ø11) in the compact island
const ALLOWED = f =>
  /-ladder\.png$/.test(f) ? [[0, 0, 260, 300], [560, 0, 630, 300]]                    // columns Ø12 to Ø24, and the Ø16 kitten
  : f === '10-island-expand-desk.png' ? [[424, 32, 472, 160], [640, 32, 700, 80]]    // the session rows' cats (Ø22) and the subagent kittens (Ø15)
  : f === '13-greet-panel-5p7.png' ? [[176, 0, 216, 30], [352, 0, 408, 30]]          // the end of the greeting: the compact island
  : /-desk\.png$/.test(f) ? COMPACT_DESK
  : [];
const inside = (b, r) => b[0] >= r[0] && b[1] >= r[1] && b[2] <= r[2] && b[3] <= r[3];
// What the reasons look like in the compact island, in the notch cat's box (48 x 32 px; its ears are the rows above FACE_Y, its face the rows below).
// At rest the ear fit does nothing, so the compact ear scale alone must move the ear tips by a lot (over 100 levels). The face changes only by
// the flat fills and the flat point mask, which is tuned to the gradient it replaces: the first drawing of it changed Latte's face by 140 levels.
const NOTCH = [440, 0, 487, 31], FACE_Y = 12, FACE_MAX = 80;
const ISLAND = f => /-desk\.png$/.test(f) && !/^(10-island-expand|12-island-greeting)/.test(f), REST = /^(14-compact-idle|01-idle)-desk\.png$/;
/** The largest difference, in levels, between two screenshots in rows y0 to y1 of the notch cat's box. */
function zoneMax(fa, fb, y0, y1) {
  const a = decode(fa), b = decode(fb); let m = 0;
  for (let y = y0; y <= y1; y++) for (let x = NOTCH[0]; x <= NOTCH[2]; x++) for (let k = 0; k < 3; k++) m = Math.max(m, Math.abs(a.data[(y * a.W + x) * a.bpp + k] - b.data[(y * b.W + x) * b.bpp + k]));
  return m;
}
let same = 0, expected = 0, bad = 0;
for (const f of fs.readdirSync(A).filter(f => f.endsWith('.png') && !NEW_ONLY.test(f)).sort()) {
  const d = diff(`${A}/${f}`, `${B}/${f}`);
  if (d.n === -1) { bad++; console.log('SIZE', f); continue; }
  if (d.n === 0) { same++; continue; }
  if (ISLAND(f)) {
    if (REST.test(f) && zoneMax(`${A}/${f}`, `${B}/${f}`, NOTCH[1], FACE_Y - 1) < 100) { bad++; console.log('THE EARS DID NOT SHRINK AT REST', f); continue; }
    const face = zoneMax(`${A}/${f}`, `${B}/${f}`, FACE_Y, NOTCH[3]);
    if (face > FACE_MAX) { bad++; console.log('THE FACE CHANGED TOO MUCH', f, `max ${face}`); continue; }
  }
  const out = d.boxes.filter(b => !ALLOWED(f).some(r => inside(b, r)));
  if (out.length) { bad++; console.log('UNEXPECTED', f, out.map(b => b.join(',')).join('  ')); } else expected++;
}
console.log(`identical=${same} differ-only-where-expected=${expected} unexpected=${bad}`);
process.exit(bad ? 1 : 0);
EOF
cat > "$T/png-zoom.mjs" <<'EOF'
// One-off, not committed: crops a region of a PNG and scales it up (nearest neighbour), side by side for several files.
// Usage: node png-zoom.mjs <out.png> <x> <y> <w> <h> <scale> <file1.png> [file2.png ...]
// The crops are laid out left to right with a 4 px gap, so "before" and "after" sit next to each other.
import fs from 'node:fs'; import zlib from 'node:zlib';
import { decode } from './png-compare.mjs';

const [out, X, Y, W, H, K, ...files] = process.argv.slice(2);
const x0 = +X, y0 = +Y, w = +W, h = +H, k = +K, gap = 4, OW = files.length * w * k + (files.length - 1) * gap, OH = h * k;
const buf = Buffer.alloc(OW * OH * 3, 40);
files.forEach((f, n) => {
  const img = decode(f);
  for (let y = 0; y < h * k; y++) for (let x = 0; x < w * k; x++) {
    const sx = x0 + Math.floor(x / k), sy = y0 + Math.floor(y / k);
    if (sx >= img.W || sy >= img.H) continue;
    const o = ((y) * OW + n * (w * k + gap) + x) * 3, i = (sy * img.W + sx) * img.bpp;
    buf[o] = img.data[i]; buf[o + 1] = img.data[i + 1]; buf[o + 2] = img.data[i + 2];
  }
});
const raw = Buffer.alloc(OH * (OW * 3 + 1));
for (let y = 0; y < OH; y++) { raw[y * (OW * 3 + 1)] = 0; buf.copy(raw, y * (OW * 3 + 1) + 1, y * OW * 3, (y + 1) * OW * 3); }
const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]), crc = Buffer.alloc(4); crc.writeUInt32BE(zlib.crc32(td)); return Buffer.concat([len, td, crc]); };
const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(OW, 0); ihdr.writeUInt32BE(OH, 4); ihdr[8] = 8; ihdr[9] = 2;
fs.writeFileSync(out, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
EOF
cat > "$T/cfg.json" <<'EOF'
{"allowUnrestrictedFileAccess":true,"browser":{"contextOptions":{"viewport":{"width":1280,"height":900},"deviceScaleFactor":1}}}
EOF
ls "$T"
```

- [ ] **Step 3: Take the baseline twice from the old page**

This needs `playwright-cli` (the `playwright-cli` skill). It runs from inside `$T`, so its `.playwright-cli` snapshot folder stays out of the repository. (If `open` fails with "Socket directory path is too long", `TMPDIR` is a long path: `export PWTEST_SOCKETS_DIR` to a short folder and run the step again.) Each run takes about two minutes.

```bash
T=${TMPDIR:-/tmp}/a0b-check
for i in 1 2; do
  rm -rf "$T/before$i"; mkdir -p "$T/before$i"
  node "$T/mkshots.mjs" "$T/old/notchmeow.html" "$T/before$i" false > "$T/run-before$i.js"
  (cd "$T" && playwright-cli -s=a0b close >/dev/null 2>&1; playwright-cli -s=a0b open --config="$T/cfg.json" >/dev/null 2>&1; playwright-cli -s=a0b --raw run-code --filename="$T/run-before$i.js" | tail -1)
done
(cd "$T" && playwright-cli -s=a0b close >/dev/null 2>&1)
ls "$T/before1" | wc -l
node "$T/png-compare.mjs" "$T/before1" "$T/before2"
```

Expected: each run prints `"{\"dump\":\"{\\\"canvases\\\":28,\\\"state\\\":\\\"idle\\\"}\",\"errors\":[]}"` (28 canvases: the old page still has the comparison's nine), `166` files, and the comparison ends with `identical=166 different=0 missing=0 size=0`. Any `DIFFERENT` line means the check is not steady: do not go on.

- [ ] **Step 4: Change the page**

```bash
T=${TMPDIR:-/tmp}/a0b-check
cat > "$T/make-page.py" <<'EOF'
#!/usr/bin/env python3
"""One-off, not committed: applies the A-0b changes to the prototype page, in place.

Usage: python3 make-page.py design/prototype/notchmeow.html

The page must be the one from a6ec93c (the script checks its hash). Every replacement must match exactly
one place, so a page that differs fails loudly instead of being half-changed. What changes, and nothing else:
  - the Collar comparison panel, its CSS and its JS become a Collar style selector (Off by default) that drives the page's cats;
  - drawCat uses the compact ear scale (CatCore.earScale: 0.8 at Ø20 and below, easing to 1 at Ø28) on every compact cat and CatCore.earFit
    on top of it (o.earCeiling, set for the notch cat), the flat fills of CatCore.detailLevel/flatFillColors below Ø28, and the final
    collar API (style IDs, no comparison names): the page draws what the apps draw;
  - the Greeting and Size ladder panel copy is made true.
"""
import hashlib, sys

PAGE = sys.argv[1]
OLD_SHA256 = '45df0d00fb63f62ca76b961f152d3dec651b29ca301d009147faa8c8b643c616'
src = open(PAGE, encoding='utf-8').read()
if hashlib.sha256(src.encode('utf-8')).hexdigest() != OLD_SHA256:
    sys.exit('This is not design/prototype/notchmeow.html at a6ec93c (use: git show a6ec93c:design/prototype/notchmeow.html).')


def rep(text, was, now):
    """Replace one exact piece of text, which must occur exactly once."""
    assert text.count(was) == 1, (was[:100], text.count(was))
    return text.replace(was, now)


def cut(text, start, end, now):
    """Replace everything from `start` up to (not including) `end`, each of which must occur exactly once."""
    assert text.count(start) == 1 and text.count(end) == 1, (start[:60], end[:60])
    a, b = text.index(start), text.index(end)
    assert a < b
    return text[:a] + now + text[b:]


s = src

# ── Header comment ───────────────────────────────────────────────────────────
s = rep(s, "cat-core.js, loaded below: presets, geometry and the face warp, the state/mouth/emote tables,",
           "cat-core.js, loaded below: presets, geometry and the face warp, the ear fit, collar geometry, the flat-fill rule, the state/mouth/emote tables,")

# ── CSS: the comparison scaffolding goes ─────────────────────────────────────
s = cut(s, ".col3{display:grid;", "</style></head>", "")

# ── Panel copy ───────────────────────────────────────────────────────────────
s = rep(s, "then slides back and settles with the badge and tint. Same island and same cat as in the apps.</p>",
           "then slides back and settles with the badge and tint. The timeline is defined in cat-core.js and pinned by sequence-cases.json, which the apps are tested against.</p>")
s = rep(s, "Below Ø28 the cats switch to the compact drawing: ink eyes, no irises, stripes or whiskers. Kittens keep",
           "Below Ø28 the cats switch to the compact drawing: ink eyes, no irises, stripes or whiskers, flat fills instead of gradients and smaller ears (0.8 times at Ø20 and below, easing back to full size at Ø28). Kittens keep")

# ── The Collar panel: a style selector ───────────────────────────────────────
s = cut(s, "<!-- COLLAR COMPARISON: temporary.", "</div>\n<script src=\"cat-core.js\"></script>", """<section class="panel" id="collarPanel">
<h2>Collar</h2>
<p class="tag">The colour that used to fill the upstream figure becomes a thin collar, in one of three styles, or none (the default). Small cats wear their agent's collar; the big cat wears the collar of the agent driving its state, and none when idle. The coat is never recoloured. Drawn in the front pass, from Ø12 up. Pick a style and every cat on this page wears it: the stage cats and the notch cat while they are not idle, the session cats, and the size ladder always. The colours are the real ones from the pill catalogue.</p>
<div class="row" id="colRow"><span class="h">Style</span></div>
<div class="row" id="agRow"><span class="h">Agent</span></div>
<p class="note" id="collarNote"></p>
</section>
""")

# ── Renderer: colour helper, ears (fit and flat fill) ────────────────────────
s = rep(s, "function heartP(c,s)", "const rgbOf=c=>`rgb(${c.map(Math.round)})`;\nfunction heartP(c,s)")
s = rep(s, "function drawEar(ctx,p,s,sd,R,rx,ry,full,yf,pf,front){const E=p.ear,{bx,by,rot,h,bw,tip,cx}=CatCore.earGeom(p,s,sd,R,yf,pf);",
           "/** ek is the ears' scale (the compact ear scale, times the ear fit's factor when there is one; 1 at full detail); flat is CatCore.flatFillColors(p) below Ø28, else null. */\nfunction drawEar(ctx,p,s,sd,R,rx,ry,full,yf,pf,front,ek=1,flat=null){const E=p.ear,{bx,by,rot,h,bw,tip,cx}=CatCore.earGeom(p,s,sd,R,yf,pf,ek);")
s = rep(s, " const g=ctx.createLinearGradient(0,-h,0,.25*R),ec=p.earCols&&p.earCols[sd<0?0:1];g.addColorStop(0,ec||p.top);g.addColorStop(1,ec||p.bot);\n",
           " let g;if(flat)g=rgbOf(flat.ears[sd<0?0:1]);else{const ec=p.earCols&&p.earCols[sd<0?0:1];g=ctx.createLinearGradient(0,-h,0,.25*R);g.addColorStop(0,ec||p.top);g.addColorStop(1,ec||p.bot)}\n")

# ── drawCat: the ear fit, the flat fills, the collar ─────────────────────────
s = rep(s, "function drawCat(ctx,e,cx,cy,D,o={}){const p=e.p,s=e.s,T=nowS(),L=CatCore.layout(p,s,cx,cy,D,{T,detail:o.detail,badgeSide:o.badgeSide}),{R,full,rx,ry,yf,pf,pt,fa,W,steps}=L,cx0=L.base.x,cy0=L.base.y;\n",
           "function drawCat(ctx,e,cx,cy,D,o={}){const p=e.p,s=e.s,T=nowS(),lay=ek=>CatCore.layout(p,s,cx,cy,D,{T,detail:o.detail,badgeSide:o.badgeSide,earScale:ek});\n"
           " // Ears, as in the apps: a compact cat wears the compact ear scale (CatCore.earScale: 0.8 at Ø20 and below, easing to 1 at Ø28). The compact\n"
           " // island's top is the top of the screen, so with o.earCeiling the ears shrink further, just enough that no tip leaves the strip.\n"
           " const lv=CatCore.detailLevel(D,o.detail),k0=lv.full?1:CatCore.earScale(D);let ek=k0,L=lay(ek);\n"
           " if(o.earCeiling!==undefined){const f=CatCore.earFit(L,s,o.earCeiling);if(f<1){ek=k0*f;L=lay(ek)}}\n"
           " const {R,full,rx,ry,yf,pf,pt,fa,W,steps}=L,cx0=L.base.x,cy0=L.base.y,flat=lv.flatFill?CatCore.flatFillColors(p):null; // flat: the compact fills\n")
s = rep(s, "const rp=sup(r.rx*R,r.ry*R,2.4,r.dy*R,.06,18,steps),g=ctx.createRadialGradient(0,r.dy*R,.55*R,0,r.dy*R,1.55*R);g.addColorStop(0,r.col[1]);g.addColorStop(1,r.col[0]);ctx.fillStyle=g;ctx.fill(rp);",
           "const rp=sup(r.rx*R,r.ry*R,2.4,r.dy*R,.06,18,steps);\n"
           "  if(flat)ctx.fillStyle=rgbOf(flat.ruff);else{const g=ctx.createRadialGradient(0,r.dy*R,.55*R,0,r.dy*R,1.55*R);g.addColorStop(0,r.col[1]);g.addColorStop(1,r.col[0]);ctx.fillStyle=g}\n"
           "  ctx.fill(rp);")
s = rep(s, " drawEar(ctx,p,s,-1,R,rx,ry,full,yf,pf);drawEar(ctx,p,s,1,R,rx,ry,full,yf,pf);\n",
           " drawEar(ctx,p,s,-1,R,rx,ry,full,yf,pf,false,ek,flat);drawEar(ctx,p,s,1,R,rx,ry,full,yf,pf,false,ek,flat);\n")
s = rep(s, " let g=ctx.createLinearGradient(.45*rx,-ry,-.45*rx,ry);g.addColorStop(0,p.top);g.addColorStop(1,p.bot);ctx.fillStyle=g;ctx.fill(head);\n",
           " let g;if(flat)g=rgbOf(flat.head);else{g=ctx.createLinearGradient(.45*rx,-ry,-.45*rx,ry);g.addColorStop(0,p.top);g.addColorStop(1,p.bot)}ctx.fillStyle=g;ctx.fill(head);\n")
s = rep(s, "[bx,by]=W(0,-.88),cb=ctx.createRadialGradient(bx,by,0,bx,by,.6*R);cb.addColorStop(0,`rgba(${sc},.9)`);cb.addColorStop(1,`rgba(${sc},0)`);ctx.fillStyle=cb;ctx.fillRect(-2*R,-2*R,4*R,4*R);\n",
           "[bx,by]=W(0,-.88);\n"
           "  if(flat){const c=CatCore.FLAT_FILL.crown;ctx.fillStyle=`rgba(${sc},${c.alpha})`;ctx.beginPath();ctx.ellipse(bx,by,c.rx*R,c.ry*R,0,0,TAU);ctx.fill()}\n"
           "  else{const cb=ctx.createRadialGradient(bx,by,0,bx,by,.6*R);cb.addColorStop(0,`rgba(${sc},.9)`);cb.addColorStop(1,`rgba(${sc},0)`);ctx.fillStyle=cb;ctx.fillRect(-2*R,-2*R,4*R,4*R)}\n")
s = rep(s, "pc=hex(p.point).join(',');ctx.save();ctx.translate(mx,my);ctx.scale(1.55,1);const pg=ctx.createRadialGradient(0,0,.05*R,0,0,.66*R);pg.addColorStop(0,`rgba(${pc},.97)`);pg.addColorStop(.6,`rgba(${pc},.82)`);pg.addColorStop(1,`rgba(${pc},0)`);ctx.fillStyle=pg;ctx.fillRect(-2*R,-2*R,4*R,4*R);ctx.restore()}",
           "pc=hex(p.point).join(',');\n"
           "  if(flat){const c=CatCore.FLAT_FILL.point;ctx.fillStyle=`rgba(${flat.point.map(Math.round)},${c.alpha})`;ctx.beginPath();ctx.ellipse(mx,my,c.rx*R,c.ry*R,0,0,TAU);ctx.fill()}\n"
           "  else{ctx.save();ctx.translate(mx,my);ctx.scale(1.55,1);const pg=ctx.createRadialGradient(0,0,.05*R,0,0,.66*R);pg.addColorStop(0,`rgba(${pc},.97)`);pg.addColorStop(.6,`rgba(${pc},.82)`);pg.addColorStop(1,`rgba(${pc},0)`);ctx.fillStyle=pg;ctx.fillRect(-2*R,-2*R,4*R,4*R);ctx.restore()}}")
s = rep(s, " const rg=ctx.createRadialGradient(0,0,.2*R,0,0,1.35*R);rg.addColorStop(0,'rgba(0,0,0,0)');rg.addColorStop(.62,'rgba(0,0,0,0)');rg.addColorStop(1,p.rimLight?'rgba(255,255,255,.07)':'rgba(0,0,0,.25)');ctx.fillStyle=rg;ctx.fillRect(-2*R,-2*R,4*R,4*R);\n",
           " if(!flat||CatCore.FLAT_FILL.rimGradient){const rg=ctx.createRadialGradient(0,0,.2*R,0,0,1.35*R);rg.addColorStop(0,'rgba(0,0,0,0)');rg.addColorStop(.62,'rgba(0,0,0,0)');rg.addColorStop(1,p.rimLight?'rgba(255,255,255,.07)':'rgba(0,0,0,.25)');ctx.fillStyle=rg;ctx.fillRect(-2*R,-2*R,4*R,4*R)}\n")
s = rep(s, " if(p.ear.fold){drawEar(ctx,p,s,-1,R,rx,ry,full,yf,pf,1);drawEar(ctx,p,s,1,R,rx,ry,full,yf,pf,1)}\n",
           " if(p.ear.fold){drawEar(ctx,p,s,-1,R,rx,ry,full,yf,pf,1,ek,flat);drawEar(ctx,p,s,1,R,rx,ry,full,yf,pf,1,ek,flat)}\n")
s = rep(s, " // Collar (front pass, over the head and under the whiskers). COMPARISON: o.collar = {opt, col}. Only the chosen option stays.\n if(o.collar)drawCollar(ctx,CatCore.collarGeometry(p,s,D,o.collar.opt,{dpr:DPR()}),o.collar.col,full);\n",
           " // Collar (front pass, over the head and under the whiskers): o.collar = {style, col}; the style 'off' draws nothing.\n if(o.collar){const G=CatCore.collarGeometry(p,s,D,o.collar.style,{dpr:DPR()});if(G)drawCollar(ctx,G,o.collar.col,full)}\n")
s = rep(s, "// ── Collar drawing (COMPARISON): the maths is CatCore.collarGeometry, this only paints it ──────",
           "// ── Collar drawing: the maths is CatCore.collarGeometry, this only paints it ─────────────────")
s = rep(s, " if(G.scarf){const S=G.scarf;", " if(G.kerchief){const S=G.kerchief;")

# ── Page state: the collar, and who wears which ──────────────────────────────
s = rep(s, "let FUR=false,TINTON=true,CHAR='shrimpy',mx=null,my=null;\n",
           "let FUR=false,TINTON=true,CHAR='shrimpy',mx=null,my=null;\n"
           "// Collar: the agent colour as a thin collar, in the style picked in the Collar panel (Off by default). The colours are the pill catalogue's.\n"
           "const AGENTS=[['Claude Code','#E07950'],['Gemini CLI','#8AB4F8'],['Codex','#2DD4BF'],['Antigravity','#E879F9'],['Stripe (dark)','#0570DE']],AGENT_COL=Object.fromEntries(AGENTS);\n"
           "let COLLAR='off',AGENT='Claude Code';\n"
           "const collarOf=col=>COLLAR==='off'?null:{style:COLLAR,col};\n"
           "/** The big cat wears the collar of the agent driving its state (the agent picked in the panel), and none when idle. */\n"
           "const bigCollar=e=>e.state==='idle'?null:collarOf(AGENT_COL[AGENT]);\n")

# ── Who wears it: stage, notch (with the ear fit), sessions, ladder ──────────
s = rep(s, "drawCat(ctx,S.e,W/2,H*.57,Math.min(W*.4,H*.5),{fur:FUR,tint:TINTON,glow:true})",
           "drawCat(ctx,S.e,W/2,H*.57,Math.min(W*.4,H*.5),{fur:FUR,tint:TINTON,glow:true,collar:bigCollar(S.e)})")
s = rep(s, "drawCat(ctx,notchEng,ncx,ncy,D,{tint:TINTON,fur:FUR,glow:e>.5,badgeSide:e<.5?-1:1})",
           "drawCat(ctx,notchEng,ncx,ncy,D,{tint:TINTON,fur:FUR,glow:e>.5,badgeSide:e<.5?-1:1,collar:bigCollar(notchEng),earCeiling:0})")
s = rep(s, " {name:'Claude Code',sub:'notchmeow · editing engine.ts',e:", " {name:'Claude Code',col:AGENT_COL['Claude Code'],sub:'notchmeow · editing engine.ts',e:")
s = rep(s, " {name:'Codex',sub:'api-server · wants to run npm test',e:", " {name:'Codex',col:AGENT_COL['Codex'],sub:'api-server · wants to run npm test',e:")
s = rep(s, " {name:'Gemini CLI',sub:'docs · done in 42 s',e:", " {name:'Gemini CLI',col:AGENT_COL['Gemini CLI'],sub:'docs · done in 42 s',e:")
s = rep(s, "drawCat(ctx,S.e,x1-(12+i*14)*k,17*k,11*k,{tint:TINTON,badge:false})", "drawCat(ctx,S.e,x1-(12+i*14)*k,17*k,11*k,{tint:TINTON,badge:false,collar:collarOf(S.col)})")
s = rep(s, "drawCat(ctx,S.e,lx+12*k,y,22*k,{tint:TINTON});", "drawCat(ctx,S.e,lx+12*k,y,22*k,{tint:TINTON,collar:collarOf(S.col)});")
s = rep(s, "drawCat(ctx,kt,kx,y,15*k,{tint:TINTON});", "drawCat(ctx,kt,kx,y,15*k,{tint:TINTON,collar:collarOf(S.col)});")
s = rep(s, "drawCat(ctx,c.e,cx,cy,c.d,{tint:TINTON,fur:FUR&&c.d>=60});", "drawCat(ctx,c.e,cx,cy,c.d,{tint:TINTON,fur:FUR&&c.d>=60,collar:collarOf(AGENT_COL[AGENT])});")

# ── The comparison panel's JS becomes the selector ───────────────────────────
s = cut(s, "// ── Collar comparison panel (temporary", "// ── Frame loop", """// ── Collar panel: the one global style every cat on this page wears ──────────
const COLLAR_LABEL={tag:'Band and tag',band:'Band',kerchief:'Neckerchief',off:'Off'},MIN=CatCore.COLLAR_MIN;
group('colRow',CatCore.COLLAR_STYLES.map(id=>[id,COLLAR_LABEL[id]]),()=>COLLAR,v=>{COLLAR=v});
group('agRow',AGENTS.map(([n])=>[n,n]),()=>AGENT,v=>{AGENT=v});
document.getElementById('collarNote').textContent=`In the apps, Settings has this style for every cat (Off is the default) and a "This cat's collar" row for each cat: follow the global style, or pick another style for that cat. This page has the one global style. Readability floor, in device pixels: band ${MIN.band} px thick, tag ${MIN.tag} px across, neckerchief ${MIN.kerchiefW} px wide and ${MIN.kerchiefDrop} px deep. Above that the sizes scale with the head (band a tenth of the head radius). A dark edge keeps light collars apart from light coats.`;

""")

open(PAGE, 'w', encoding='utf-8').write(s)
EOF
python3 "$T/make-page.py" design/prototype/notchmeow.html
git diff --stat -- design/prototype/notchmeow.html
grep -n "COMPARISON\|scarf\|\.opt\b\|dprNote\|colFrame\|col3\|cmpflag" design/prototype/notchmeow.html | wc -l
```

Expected: `1 file changed, 54 insertions(+), 73 deletions(-)` and `0` leftover comparison names. The script exits with a message instead if the old page's hash or any replacement does not match.

- [ ] **Step 5: Take the screenshots of the new page and compare**

```bash
T=${TMPDIR:-/tmp}/a0b-check
rm -rf "$T/after"; mkdir -p "$T/after"
node "$T/mkshots.mjs" design/prototype/notchmeow.html "$T/after" true > "$T/run-after.js"
(cd "$T" && playwright-cli -s=a0b close >/dev/null 2>&1; playwright-cli -s=a0b open --config="$T/cfg.json" >/dev/null 2>&1; playwright-cli -s=a0b --raw run-code --filename="$T/run-after.js" | tail -1)
(cd "$T" && playwright-cli -s=a0b close >/dev/null 2>&1)
ls "$T/after" | wc -l
node "$T/expect-diffs.mjs" "$T/before1" "$T/after"
```

Expected: the run prints `"{\"dump\":\"{\\\"canvases\\\":19,\\\"state\\\":\\\"idle\\\"}\",\"errors\":[],\"ears\":{\"bad\":[],\"fitSeen\":true}}"` (19 canvases, no console error or warning anywhere, every head width laid out at `earScale(D)` with nothing above it and nothing under 0.35 of it, and the ear fit seen at work on the notch cat), `201` files, and the check ends with `identical=108 differ-only-where-expected=57 unexpected=0`. If a line starts `UNEXPECTED`, `THE EARS DID NOT SHRINK AT REST` or `THE FACE CHANGED TOO MUCH`, or `ears` lists anything in `bad` or says `"fitSeen":false`, stop and find out why: the page is then not drawing what the apps draw.

What those numbers say. The 108 identical screenshots are every stage cat (`#figMomo`, `#figShrimpy`), every "More cats" cat, every state, emote, poke, catch, personality, classic and fur frame of them, and the ladder is identical wherever a cat is Ø28 or bigger: nothing at full detail moved. The 57 that differ are all compact cats, and each changes for the reasons the check allows (flat fills, the compact ear scale and, in the hop, the ear fit), by file:
- `*-desk.png`, 44 files: the notch cat (Ø20) and the three session cats (Ø11) in the compact island. All four have flat fills and ears at the compact ear scale, 0.8 times: at rest (`01-idle` and `14-compact-idle`) the notch cat's ears are about a fifth shorter, so the ear rows change by up to 152 levels while the face rows change by at most 30 (the flat fills; the check's `THE EARS DID NOT SHRINK AT REST` and `THE FACE CHANGED TOO MUCH` rules look at exactly these two). `11-char-Latte` and `11-char-Cloud` also show their point masks, one flat ellipse now the size of the soft gradient it replaces (their face rows differ by up to 62 and 39 levels; the macOS draft's smaller ellipse differed by 140 and 91). `10-island-expand-desk.png` shows the session rows' Ø22 cats (ears at 0.85) and the subagent kittens (Ø15, ears at 0.8). The eight `15-hop-*` frames are the approval hop, and in frames 12, 15 and 18 the ears used to be cut off at the top of the screen: there the ear fit shrinks them a little more, so those frames differ from the old page by both the scale and the fit (`fitSeen` above is the proof that the fit ran).
- `*-ladder.png`, 12 files: only the Ø12, Ø16, Ø20, Ø24 and Ø16-kitten columns, with flat fills and ears at 0.8 times (0.9 at Ø24).
- `13-greet-panel-5p7.png`: the end of the greeting, which collapses into the compact island: the notch cat and the session cats, as above.

How the check bites (seen in the dry run, each change undone afterwards): with the page not applying the compact ear scale, `ears.bad` lists every compact size and both rest frames fail with `THE EARS DID NOT SHRINK AT REST`; with the macOS draft's 0.5 R by 0.34 R point mask in `FLAT_FILL`, `THE FACE CHANGED TOO MUCH` names `11-char-Latte` (140 levels) and `11-char-Cloud` (91); with the ear fit switched off, `"fitSeen":false`.

- [ ] **Step 6: Look at the pictures**

```bash
T=${TMPDIR:-/tmp}/a0b-check
node "$T/png-zoom.mjs" "$T/zoom-rest.png" 436 0 56 34 5 "$T/before1/14-compact-idle-desk.png" "$T/after/14-compact-idle-desk.png"
node "$T/png-zoom.mjs" "$T/zoom-hop.png" 436 0 56 34 5 "$T/before1/15-hop-f12-desk.png" "$T/after/15-hop-f12-desk.png" "$T/before1/15-hop-f15-desk.png" "$T/after/15-hop-f15-desk.png"
node "$T/png-zoom.mjs" "$T/zoom-ladder.png" 74 205 186 45 5 "$T/before1/01-idle-ladder.png" "$T/after/01-idle-ladder.png"
node "$T/png-zoom.mjs" "$T/zoom-points.png" 436 0 56 34 5 "$T/before1/11-char-Latte-desk.png" "$T/after/11-char-Latte-desk.png" "$T/before1/11-char-Cloud-desk.png" "$T/after/11-char-Cloud-desk.png"
```

The flat point mask is judged against the soft gradient it replaces, at Ø20 and at Ø28, which the page's screenshots cannot show (the page draws full detail from Ø28). This script draws Latte and Cloud both ways, side by side, at Retina scale, in the new page: with the flat fills switched off (the look before this plan) and on. It is the comparison the numbers of `FLAT_FILL.point` were tuned with.

```bash
T=${TMPDIR:-/tmp}/a0b-check
cat > "$T/mask-side.js" <<'EOF'
async page => {
  await page.setViewportSize({ width: 1000, height: 1000 });
  await page.goto(__URL__);
  await page.evaluate(() => {
    const level = CatCore.detailLevel;
    // Each cat twice at Retina scale (head width D in points, 2 device pixels per point), as in the compact island: with the soft gradient the page
    // drew before this plan (flat fills switched off), and with the flat fills. The detail is compact in both, so only the fills differ.
    const draw = (cat, D, soft) => {
      const W = Math.ceil(D * 1.7) * 2, cv = document.createElement('canvas'); cv.width = cv.height = W;
      const ctx = cv.getContext('2d'); ctx.fillStyle = '#16181c'; ctx.fillRect(0, 0, W, W); ctx.scale(2, 2);
      CatCore.detailLevel = soft ? (d, o) => ({ ...level(d, o), flatFill: false }) : level;
      drawCat(ctx, new CatEngine(PRESETS[cat]), W / 4, W / 4 + D * .12, D, { tint: false, detail: 'compact' });
      CatCore.detailLevel = level;
      const big = document.createElement('canvas'), k = 28 / D * 3; big.width = big.height = Math.round(W * k);
      const c2 = big.getContext('2d'); c2.imageSmoothingEnabled = false; c2.drawImage(cv, 0, 0, big.width, big.height);
      return big;
    };
    document.body.innerHTML = '<div id="cmp" style="background:#16181c;color:#ddd;font:12px sans-serif;padding:8px;display:inline-block"></div>';
    for (const D of [20, 28]) for (const cat of ['latte', 'cloud']) {
      const row = document.createElement('div'); row.style.cssText = 'display:flex;gap:8px;margin-bottom:6px';
      for (const [label, soft] of [['soft gradient (before)', true], ['flat fill (after)', false]]) {
        const box = document.createElement('div');
        box.append(Object.assign(document.createElement('div'), { textContent: `${cat} Ø${D}, ${label}` }), draw(cat, D, soft)); row.append(box);
      }
      document.getElementById('cmp').append(row);
    }
  });
  await page.locator('#cmp').screenshot({ path: __OUT__ });
  return 'ok';
}
EOF
node "$T/mkshots.mjs" design/prototype/notchmeow.html "$T/mask-side.png" true mask-side.js > "$T/mask-side.run.js"
(cd "$T" && playwright-cli -s=a0b close >/dev/null 2>&1; playwright-cli -s=a0b open --config="$T/cfg.json" >/dev/null 2>&1; playwright-cli -s=a0b --raw run-code --filename="$T/mask-side.run.js" | tail -1; playwright-cli -s=a0b close >/dev/null 2>&1)
ls "$T/mask-side.png"
```

Expected: `"ok"` from the run, then the path of `mask-side.png`.

Open each image (the Read tool shows PNGs) and check, left to right (before, after):
- `zoom-rest.png`: the resting notch cat has smaller ears, about a fifth shorter (the compact ear scale; at rest the ear fit does nothing), and flat head and ear fills; the eyes, the nose and the mouth are where they were.
- `zoom-hop.png`: in the "before" frames the ears run off the top edge and are cut; in the "after" frames the ears are smaller still and both tips are inside the island (the compact ear scale, then the ear fit).
- `zoom-ladder.png` (Shrimpy Ø16, Ø20, Ø24): the same cat with a flat head, flat ears and smaller ears (0.8 times at Ø16 and Ø20, 0.9 at Ø24) where there was a soft gradient and full-size ears; nothing else moved.
- `zoom-points.png`: Latte and Cloud keep their pointed look, and the flat mask is about the size the soft one showed (it was visibly smaller with the macOS draft's 0.5 R by 0.34 R).
- `mask-side.png`, four rows (Latte and Cloud at Ø20, then at Ø28), soft gradient left and flat fill right: the flat mask covers the area the soft one showed, to the cheeks and down to the chin, on both cats and at both sizes. Its edge is crisp where the soft one fades out, and a thin rim of coat colour is left under the chin. If it looks clearly smaller or larger, stop and report it: `FLAT_FILL.point` is the controller's ruling.

Then open these files from `$T/after/`:
- `26-collar-panel-after-collarPanel.png`: the panel has a Style row (Band and tag, Band, Neckerchief, Off, with Off lit) and an Agent row (Claude Code lit), and a note that mentions the apps' per-cat override and the pixel floors.
- `21-collar-tag-ladder.png`, `21-collar-band-ladder.png` and `21-collar-kerchief-ladder.png`: every cat in the size ladder wears the Claude collar in the style named, from Ø12 up, and the colour reads even at Ø12.
- `22-collar-tag-expanded-desk.png`: the big cat (state working) wears an orange collar and tag; the three session cats wear their own agents' collars (orange, teal, light blue), and so do the two subagent kittens.
- `24-collar-tag-idle-none-figShrimpy.png` and `25-collar-off-again-figShrimpy.png`: no collar on an idle big cat, and none once the style is Off again.

- [ ] **Step 7: Commit**

```bash
git add design/prototype/notchmeow.html
git commit -m "feat(prototype): a collar style selector, the ear scale and fit on compact cats, and flat fills below Ø28

The Collar comparison becomes a selector (Off by default) that drives every cat on the page. Compact cats wear the apps' compact ear scale and flat fills, and the notch cat the ear fit. The stage, more cats and every full-size cat are pixel for pixel as before.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Docs and the final checks

**Files:**
- Modify: `docs/CAT-CONTRACT.md`

**Interfaces:**
- Consumes: the names the earlier tasks produced.
- Produces: the doc the two app plans read: the names table (Ear fit, Compact detail, Collar rows), the fixtures table (`collar-cases.json` and the new `geometry-cases.json` keys), the section "Collar, ear fit and flat fills (A-0b)" with the rules and numbers and a short "adopting it" list for the two app plans (`earFit` keeps its signature and `earCeiling` its name; `flatFill` is `!layout().full`), the additive rule, and three notes under "Decisions to know about".

The doc is changed by a one-off script that checks each replacement matches exactly one place.

- [ ] **Step 1: Change the doc**

````bash
T=${TMPDIR:-/tmp}/a0b-check; mkdir -p "$T"
cat > "$T/make-doc.py" <<'EOF'
#!/usr/bin/env python3
"""One-off, not committed: adds the A-0b sections to docs/CAT-CONTRACT.md, in place. Every replacement matches exactly one place."""
import sys

PATH = sys.argv[1]
s = open(PATH, encoding='utf-8').read()


def rep(text, was, now):
    assert text.count(was) == 1, (was[:90], text.count(was))
    return text.replace(was, now)


s = rep(s, """node scripts/gen-cat-fixtures.mjs --check
```
""", """node scripts/gen-cat-fixtures.mjs --check
node scripts/check-fixtures-additive.mjs [BASE_REF]   # prove the fixtures changed only by addition since BASE_REF (default HEAD)
```
""")

s = rep(s, "The look is not tested here.", """**Apps read the fixtures, so they change only by addition** (a new file, new keys, new cases): every line of an existing case stays byte for byte. `check-fixtures-additive.mjs` proves it against a commit. It is not part of the runner, because CI checks out one commit.

The look is not tested here.""")

s = rep(s, """| Geometry | `layout`, `mkWarp`, `supPoints`, `earGeom`, `faceAngles`, `cursorLook`, `pupilOffset`, `detailOf`, `earScale`, `badgeSide`, `outlineSteps`, `MOMO_WHITE`, `FACE`, `PASSES`, `newPose` |
""", """| Geometry | `layout`, `mkWarp`, `supPoints`, `earGeom`, `faceAngles`, `cursorLook`, `pupilOffset`, `detailOf`, `earScale`, `badgeSide`, `outlineSteps`, `MOMO_WHITE`, `FACE`, `PASSES`, `newPose` |
| Ear fit | `earFit`, `EAR_FIT` |
| Compact detail | `detailLevel`, `FLAT_FILL`, `flatFillColors`, `mixHex` |
| Collar | `COLLAR_STYLES`, `collarStyleOf`, `collarGeometry`, `COLLAR_MIN`, `COLLAR_PASS` |
""")

s = rep(s, """| `geometry-cases.json` | `detail` (the Ø28 switch), `earScale`, `outline` (head and ruff outline samples, including Shrimpy's fluffy edge), `anchors` (a full `layout()` per cat, size and pose, with the compact notch case), `passes`. |
""", """| `geometry-cases.json` | `detail` (the Ø28 switch), `earScale`, `outline` (head and ruff outline samples, including Shrimpy's fluffy edge), `anchors` (a full `layout()` per cat, size and pose, with the compact notch case), `collarPass` (the pass the collar is drawn in, see below; `passes` itself stays as A-0 wrote it), `earFit` and `earFitCases` (the ear fit, see below), `flatFill`, `detailLevels` and `flatColors` (the flat-fill rule, see below), `passes`. |
""")

s = rep(s, """| `search-tools.json` | The tool names that mean "searching", for Claude Code, Gemini CLI and Codex, and cases. |
""", """| `search-tools.json` | The tool names that mean "searching", for Claude Code, Gemini CLI and Codex, and cases. |
| `collar-cases.json` | `styles` (the frozen IDs), `min` (the device-pixel floors), `resolve` (a stored value to a style), `cases` (each style's geometry at Ø12 to Ø66, at pixel ratio 1 and 2, at rest and with the head turned). |
""")

s = rep(s, "\n## The harness\n", """
## Collar, ear fit and flat fills (A-0b)

Added after A-0 merged, because comparing the two app plans showed four things both apps must draw the same way: the collar styles, the ear fit, the flat fills and the mouth spring. The first three are below. The fourth was already in this file: the spring is stepped at most 1/60 s at a time, so a port sub-steps a slow frame (the harness list). So was the note that a stored `tMs` can be 5e-9 off, so compare it within 1e-8 or compute it from `f` (Conventions, Units).

**Collar.** The colour that used to fill the upstream figure is worn as a thin collar, or not at all.
- **Style IDs are frozen,** like cat IDs, in this order: `tag` (Band and tag), `band` (Band), `kerchief` (Neckerchief) and `off`, the default. `collarStyleOf(id)` maps a stored value to a style: an unknown ID, or anything that is not a string, is `off`.
- **`collarGeometry(preset, pose, D, style, {dpr})`** gives the shape in head-local px (before the tilt and the squash), turning with the face warp, and `null` for `off`. The parts depend on the style:

  | Style | Result | What it holds |
  |---|---|---|
  | `tag` | `{style, R, width, band, tag}` | `band`: a polyline of 26 points along the lower outline, left to right, inset so its outer edge stays inside the head; `width`: its stroke width; `tag`: `{x, y, r}`, a round tag at centre front. |
  | `band` | `{style, R, width, band}` | The band alone. |
  | `kerchief` | `{style, R, kerchief}` | `kerchief`: `{pts, apex}`, a triangle under the chin: `pts` along the lower outline, `apex` below them. No band. |

- **Sizes and floors.** The band is a tenth of R thick, the tag 0.16 R in radius and the kerchief 0.34 R deep, and none of them gets smaller than `COLLAR_MIN` in **device** pixels: band 3 thick, tag 6 across, kerchief 7 wide and 5 deep. So `dpr`, the screen's device pixel ratio, is an input (the page uses `min(2, devicePixelRatio)`; a value that is not above 0 counts as 2). Ø12 and Ø20 are where the floors bite.
- **Drawing.** The renderer draws it in the *front* pass, over the head and the folded ears and under the whiskers, from Ø12 up. `PASSES.front` is `foldEars, whiskers, badge, particles, balls`, and the collar is the one slot between the first two. `PASSES` is the line A-0 wrote and stays as it is (fixtures change only by addition), so the pass is named by its own key, `collarPass` in `geometry-cases.json` (`COLLAR_PASS` in the core). The coat is never recoloured. The paint (a thin dark edge so a light collar stays apart from a light coat, a lighter tag, a crease on the neckerchief at full detail) is the page's `drawCollar`, the reference for the look; it is not tested. Which colour a cat wears is not in the core: small cats wear their agent's, the big cat wears the agent driving its state and none when idle, with the global style and a per-cat override in Settings (`cat.collar`, `cat.collar.<id>`).

**Ear fit.** The compact island's top edge is the top of the screen, and a mask cannot give ears room above it. `earFit(L, pose, ceiling, margin = 0.5, minimum = 0.35)` returns the factor, from `minimum` to 1, to multiply the ear scale by so that no ear rises above `ceiling`. `L` is a `layout()` made with the ear scale `ek`:

```
ek = full ? 1 : earScale(D)
L = layout(preset, pose, cx, cy, D, {earScale: ek})
f = earFit(L, pose, 0)                 // 0: the top edge of the strip the cat sits in, in the layout's own coordinates
if (f < 1) L = layout(preset, pose, cx, cy, D, {earScale: ek * f})
```

- 1 means the ears already fit. A cat so close to the ceiling that even the smallest ears would not fit is held at `minimum`. `margin` is the room kept under the ceiling, in px.
- It is a closed-form solve, not a search: an ear scales about its own base, so the height of its top edge is linear in the scale. It finds the highest point of the ear's top edge, exactly. It does not look at the sides of an ear, so ears folded far back at a large size (a base corner higher than the top edge) are outside what it solves. The compact notch never gets there: `tests/cat/earfit.test.mjs` walks every state and emote in both styles against a brute-force outline.
- A pose that is not a number (NaN, Infinity) gives 1: there is nothing to fit.
- Apps pass the ceiling in the compact notch only (the prototype page does the same for the notch cat). The draw option is called `earCeiling` on the page and in both app plans: the y of the top of the strip, in the canvas's coordinates. An engine that knows the room above its cat's centre (the Windows engine's `earRoom`) passes `cy - room`: the room is the app's, the ceiling is the contract's.
- In `geometry-cases.json`, `earFit` holds the defaults and `earFitCases` the inputs (cat, head width, position, ear scale, pose, ceiling, margin, minimum) and the factor.
- **The scale and the fit compose.** Every compact cat is laid out with the compact ear scale `earScale(D)`; where a ceiling is given, the fit multiplies it. The prototype page does exactly this, so it shows what the apps draw.
- **Adopting it.** Both app plans already declare `earFit(L, s, ceiling, margin = 0.5, minimum = 0.35)` and compose `earScale(D) * f`. Keep the signature and the composition, and take this body, the exact solve of the ear's top edge: the controller ruled that the app plans adopt the contract's version. (The drafts solve for the ear's apex only, which leaves a tip up to 0.1 px inside the margin in some tilted poses, and the fixture cases show it.) Add a loop over `earFitCases`, and keep a brute-force test.

**Flat fills.** At Ø12 to Ø27 a gradient cannot be seen and costs a shading pass each, so a compact cat is drawn with flat fills. `detailLevel(D, override)` returns `{detail, full, flatFill}`, and `flatFill` is on exactly when the cat is compact (below Ø28, or when `override` says `'compact'`). When it is on:

| Part | Flat drawing |
|---|---|
| Head | One fill: the coat's `top` and `bot` colours mixed halfway (`FLAT_FILL.headMix` = 0.5), instead of the 45° gradient. |
| Ears | One fill each: the ear's `top` and `bot` mixed halfway (`earMix` = 0.5); an ear with its own colour (`earCols`) keeps it. The folded-ear flap too. |
| Ruff | One fill: the ruff's inner colour mixed 0.6 of the way to its outer one (`ruffMix`), instead of the radial gradient. |
| Rim | No edge gradient (`rimGradient` = false). The white rim line of the dark coats stays. |
| Tabby crown band | One ellipse of radii 0.4 R by 0.26 R (`crown`) at the centre the gradient had, in the stripe colour at alpha 0.5. |
| Point mask | One ellipse of radii 0.86 R by 0.54 R (`point`) at the centre the gradient had, in the point colour at alpha 0.85. Tuned to the gradient it replaces (see Decisions to know about). |

`flatFill` is exactly `!layout(...).full`, so an app that already branches on `L.full` (both app plans do) needs no new function: only the constants (`FLAT_FILL`: the head, ear, ruff and crown numbers are the ones both plan drafts already hard-code, the point mask is not, see Decisions to know about) and a loop over `detailLevels` that checks `!full` against `flatFill`. Everything else (markings, eyes, blush, the state tint) is drawn as in the full cat. `flatFillColors(preset)` returns the flat head, ear, ruff and point colours as `[r, g, b]` in 0 to 255, unrounded (`ruff` is `null` without a ruff, and `point` unless the coat is `point`). `geometry-cases.json` holds `flatFill` (the constants), `detailLevels` (head widths and overrides to levels) and `flatColors` (every cat's flat colours, the point mask's included). The mix is per channel, on the 0 to 255 values.

## The harness
""")

s = rep(s, """- **The compact ear scale is provisional.** The spec says ears are scaled down at Ø20 and gives no number. `COMPACT_EAR_SCALE` is 0.8 at Ø20 and below, easing to 1 at Ø28. Apps pass `earScale(D)` to `layout()`. The prototype page does not apply it yet, so it still looks as it did. Change the constant and regenerate if the owner wants another value.
""", """- **The compact ear scale is provisional.** The spec says ears are scaled down at Ø20 and gives no number. `COMPACT_EAR_SCALE` is 0.8 at Ø20 and below, easing to 1 at Ø28. Apps pass `earScale(D)` to `layout()`, and so does the prototype page, so its compact ears are the apps' ears. Change the constant and regenerate if the owner wants another value.
- **The ear scale and the ear fit are two things.** The scale makes every compact ear smaller; the fit shrinks further, only when a tip would leave the strip. The apps and the page apply both: `earScale(D)` first, then the fit (`earScale(D) * f`) where a ceiling is given, in the compact notch.
- **The flat point mask is tuned to the gradient it replaces.** The macOS draft's 0.5 R by 0.34 R held about 37 % of the gradient's ink and was visibly smaller at Ø20. `FLAT_FILL.point` is 0.86 R by 0.54 R at alpha 0.85: the same total ink as the gradient, and an edge between where the gradient had fallen to half and to a quarter of its strength. It was checked side by side with the gradient at Ø20 and Ø28 on Latte and Cloud, and `flatfill.test.mjs` pins both facts. If the owner wants it softer or tighter, change `FLAT_FILL.point` once, in the core and the fixtures.
""")

open(PATH, 'w', encoding='utf-8').write(s)
EOF
python3 "$T/make-doc.py" docs/CAT-CONTRACT.md
git diff --stat -- docs/CAT-CONTRACT.md
````

Expected: `1 file changed, 58 insertions(+), 2 deletions(-)`.

- [ ] **Step 2: Check the doc names real things**

```bash
node -e "
const c = require('./design/prototype/cat-core.js');
const names = ['earFit', 'EAR_FIT', 'detailLevel', 'FLAT_FILL', 'flatFillColors', 'mixHex', 'COLLAR_STYLES', 'collarStyleOf', 'collarGeometry', 'COLLAR_MIN', 'COLLAR_PASS'];
const doc = require('fs').readFileSync('docs/CAT-CONTRACT.md', 'utf8');
for (const n of names) { if (!(n in c)) throw new Error('not exported: ' + n); if (!doc.includes('\`' + n)) throw new Error('not in the doc: ' + n); }
for (const k of ['earFitCases', 'detailLevels', 'flatColors', 'collarPass', 'collar-cases.json', 'check-fixtures-additive', 'earCeiling', 'earRoom', '!layout(...).full', 'mouth spring is stepped at most 1/60 s', 'within 1e-8']) if (!doc.includes(k)) throw new Error('not in the doc: ' + k);
console.log('the doc names all', names.length, 'new exports, the new fixture keys, and keeps the mouth-spring and tMs notes');"
```

Expected: `the doc names all 11 new exports, the new fixture keys, and keeps the mouth-spring and tMs notes`.

- [ ] **Step 3: Run the whole contract**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓|✗"`
Expected: `# tests 107`, `# pass 107`, `# fail 0`, eight `✓` fixture lines, `✓ 8 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 4: Prove the old cases are byte-identical to `a6ec93c`**

```bash
node scripts/check-fixtures-additive.mjs a6ec93c
git diff a6ec93c --numstat -- tests/fixtures/cat/
git diff a6ec93c -- tests/fixtures/cat/ | grep -c '^-[^-]' || true
for f in motion-cases personality-cases presets search-tools sequence-cases warp-cases; do git diff --quiet a6ec93c -- "tests/fixtures/cat/$f.json" && echo "$f.json: byte-identical"; done
```

Expected: the check prints seven `✓ … old lines unchanged` lines (`geometry-cases.json` with `129 lines added (new keys: collarPass, earFit, earFitCases, flatFill, detailLevels, flatColors)`), `+ collar-cases.json is new` and `✓ fixtures changed only by addition since a6ec93c`. `--numstat` shows `129	0	tests/fixtures/cat/geometry-cases.json` and `187	0	tests/fixtures/cat/collar-cases.json`; the count of removed lines is `0`; and the six untouched files each print `byte-identical`.

- [ ] **Step 5: Check what changed**

Run: `git status --short; git diff notchmeow/rebrand --stat | tail -1` (against the branch this one was made from, not against `a6ec93c`: the mix picker's sounds files sit between them, and the plan file itself is in `notchmeow/rebrand`)
Expected: `git status --short` prints only ` M docs/CAT-CONTRACT.md` (everything else is committed; no `.bak` files and no `.playwright-cli` folder). The stat's last line, `12 files changed, 929 insertions(+), 130 deletions(-)`, counts only the files this plan names: `design/prototype/cat-core.js`, `design/prototype/notchmeow.html`, `docs/CAT-CONTRACT.md`, `scripts/check-fixtures-additive.mjs`, `scripts/gen-cat-fixtures.mjs`, `tests/cat/additive.test.mjs`, `collar.test.mjs`, `earfit.test.mjs`, `fixtures.test.mjs`, `flatfill.test.mjs`, and the two fixture files. Nothing under `NotchBuddy/` or `windows/`.

- [ ] **Step 6: Commit**

```bash
git add docs/CAT-CONTRACT.md
git commit -m "docs(cat): the collar styles, the ear fit and the flat fills, and the additive rule

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

## Self-review notes

Run against the spec after writing, and again after the controller's rulings:

- **Spec coverage.**
  - §2 "A-0b, contract additions": the three collar styles with `collarGeometry` and `collar-cases.json` (Task 2); the ear fit with geometry cases (Task 3); the flat fills below Ø28, shown in the prototype too (Tasks 4 and 5); the mouth spring sub-step, which A-0 already does, and the `tMs` note, which the doc already had, pointed to from the new section (Task 6).
  - §2 fixtures row for `collar-cases.json`: "each collar style's geometry at several sizes, with the device-pixel floors": Ø12 to Ø66, `min` in the file, pixel ratio 1 and 2, at rest and turned (Task 2).
  - §1 Decisions, "Agent colour": the three styles and Off as the default (Tasks 2 and 5); small cats wear their agent's collar, the big cat the one of the agent driving its state, none when idle (the page, Task 5; the apps decide which colour, not the core).
  - §3 "Collar": every size from 12 px up, front pass, all three styles in the contract, the floors (Tasks 2 and 6). The pass is named by `collarPass` in `geometry-cases.json`.
  - §4 "Collar" rows and the frozen style IDs: the page's selector has Off first-lit by default and a note on the per-cat override; the IDs and the `off` fallback are in the core and the doc (Tasks 2, 5 and 6).
  - Fixtures change only by addition, proven against `a6ec93c` (Tasks 1 to 4 and 6).
  - The prototype page behaves exactly as before except the collar selector, the compact ear scale and the ear fit on its compact cats, and the flat fills below Ø28: proven by 108 identical screenshots and 57 that differ only where expected, each for one of those reasons (Task 5).
  - The Greeting panel copy is made true; so is the Size ladder note (Task 5).
- **Placeholder scan:** none left. Every code step carries its full code, and no step points at another task for it.
- **Type consistency:** the names in each task's Interfaces block are the names the later tasks use: `COLLAR_STYLES`, `collarStyleOf`, `COLLAR_MIN` (`kerchiefW`, `kerchiefDrop`), `COLLAR_PASS`, `collarGeometry` (Task 2); `EAR_FIT`, `earFit(L, pose, ceiling, margin, minimum)` (Task 3); `detailLevel`, `FLAT_FILL` (`headMix`, `earMix`, `ruffMix`, `rimGradient`, `crown`, `point`), `mixHex`, `flatFillColors` (`head`, `ears`, `ruff`, `point`) (Task 4); the page uses all of them, with `earScale` (Task 5), and the doc names them (Task 6).
- **Review Focus:** each of the five lines has its test in the task named there.

### Rulings from the controller (applied above)

1. **The flat point mask (Latte, Cloud) is tuned to the gradient it replaces.** The macOS draft's 0.5 R by 0.34 R was visibly smaller at Ø20. `FLAT_FILL.point` is now `{rx: 0.86, ry: 0.54, alpha: 0.85}`: a grid search against the old gradient on Latte and Cloud at Ø20, Ø24 and Ø28, then judged side by side at Ø20 and Ø28 (Task 5, step 6 reruns that comparison). The numbers are pinned in `FLAT_FILL`, in the `flatColors` cases (which now carry each point cat's point colour) and in `flatfill.test.mjs` (same total ink as the gradient, an edge between its half-strength and quarter-strength contours).
2. **The prototype page applies the compact ear scale** together with the ear fit, so that it shows exactly what the apps draw (Task 5): `earScale(D)` on every compact cat, times the fit where `earCeiling` is given. The screenshot check's list of allowed differences now names the three reasons a compact cat changes (flat fills, the ear scale, the ear fit) and checks the ears at rest and the face, and the run records every ear scale the page used.
3. **`earFit` solves the ear's top edge exactly.** The app plans adopt the contract's version (see the notes below). Nothing changes here.
4. **The collar's pass is a key of its own,** `collarPass: "front"` (Task 2). The existing `passes` line in `geometry-cases.json` is not touched, so the fixtures still change only by addition.

### Notes for the app plans (the sync after A-0b merges)

The two app plans already declare `earFit(L, s, ceiling, margin = 0.5, minimum = 0.35)`, the draw option `earCeiling` and the switch `!layout().full`, so the sync is small. Take from `cat-core.js` and the fixtures, in this order of importance:

- **`earFit`: adopt the contract's body** (ruling 3), the exact solve of the top edge of the ear. The drafts solve for the apex only, so their results differ from `earFitCases` in a few tilted poses until they follow: by up to 0.1 px, never outside the strip. A pose that is not a number gives 1 (the Tauri plan's test expects that). Loop over `earFitCases`. The Tauri engine's `earRoom` stays its own: `earCeiling = cy - earRoom`.
- **The flat point mask changes numbers** (ruling 1): both drafts hard-code 0.5 R by 0.34 R at alpha 0.85. Take `FLAT_FILL.point` (0.86 R by 0.54 R at alpha 0.85; the `flatFill` key of `geometry-cases.json`) and the colour from `flatColors[id].point`. The head, ear, ruff and crown numbers are the drafts' own.
- **The compact ear scale composes with the fit:** `earScale(D)` on every compact cat, then the fit on top (`earScale(D) * f`), where a ceiling is given. The page does exactly this now.
- **`flatFill` is `!layout().full`:** only the constants, a loop over `detailLevels` and one over `flatColors`.
- **The collar:** `collarGeometry` and `collar-cases.json` for the collar stages; the pass is `collarPass` (`"front"`, between `foldEars` and `whiskers`); `passes` is unchanged.

### Still open for the owner

1. **The compact ear scale is provisional** (0.8 at Ø20 and below, easing to 1 at Ø28): the page and the apps now share it, so one constant and one regeneration change it everywhere.
2. **Ears folded far back at a large size are outside `earFit`** (a base corner rises above the top edge: Puff or Button at Ø40 with `earF` 0.45). The compact notch never gets there, and the test sweep covers every state and emote.
