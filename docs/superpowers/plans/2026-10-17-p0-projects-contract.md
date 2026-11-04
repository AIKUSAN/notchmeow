# P-0 Projects Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write the Projects feature's rules once, in a pure JavaScript module `shared/projects-core.js`, pinned by seven JSON fixtures under `tests/fixtures/projects/` that a generator writes from it, so that the Mac plan (P-mac) and the Windows/Linux plan (P-tauri) port the same rules: which project and role a Claude Code session has, the session registry fed by hook events, each session's and project's state at a given time, the pill order, the big card's project, the waiting count, "Claude only" and the layout switch, a project's cat and the clean-up of stored project cats, and the view snapshot the island draws. The apps use none of it yet.

**Architecture:** The sidekick contract's shape (F1-0, `docs/superpowers/plans/2026-10-14-f1-0-sidekick-contract.md`), as the spec's call 2 chose: one pure module that loads in Node (`require`) and in a page (`globalThis.ProjectsCore`), and `scripts/gen-projects-fixtures.mjs`, which writes `tests/fixtures/projects/*.json` from it, with `--check` (fail on drift) and `--out DIR` (the runner writes twice to prove the bytes are identical). Every case in the generator lists its input and, **typed by hand beside it**, the answer it must get; the generator stops when the core disagrees, so a fixture is never just a copy of the core. Each task adds one group of rules to the core above the marker `// @@NEXT`, one section to the generator above `// @@SECTIONS`, and one test file. `scripts/test-projects-contract.sh` runs the tests, the no-drift check and the determinism check; CI runs it. `docs/PROJECTS-CONTRACT.md` documents the rules and the decisions this plan makes where the spec is silent. **It changes no pixel and no behaviour in either app.**

**Tech Stack:** JavaScript (CommonJS module in a UMD wrapper; Node 22 ES-module scripts), `node:test`, Bash, JSON. Node standard library only.

**Spec:** `docs/superpowers/specs/2026-10-17-projects-view-design.md` (approved 2026-10-17, commit `139ccc19`): "The rules (the contract)" (rules 1 to 12, the time-based states, the fixture list) and "Calls made by the main session" (calls 1, 2, 5, 6, 7, 8, 9). Read the whole spec before starting. This plan implements only P-0; the island, the Projects screen, the peek, Settings and the ports are P-mac and P-tauri.

**Base:** branch `p0/projects-contract`, created from `main` at `c66a07ce` or later, with this plan file already committed to `main`. This plan touches no file under `NotchBuddy/`, `windows/`, `design/prototype/` or an existing `tests/fixtures/` folder.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec; lines marked "(plan decision)" are choices this plan makes where the spec is silent, and Task 7 lists them in `docs/PROJECTS-CONTRACT.md`.

- **Pure.** `shared/projects-core.js` has no clock, no files, no network, no randomness: every rule is given the time it needs (`now`, `at`, in whole milliseconds). It never throws on any input.
- **Times (spec rules 3, 4, 7 and the polish):** quiet **10 min** → a working session shows `idle` (`QUIET_IDLE_MS = 600000`); no event for **30 min** → dimmed (`DIM_MS = 1800000`); none for **2 h** → it leaves (`REMOVE_MS = 7200000`); `finished` shows for **5.2 s** (`FINISHED_MS = 5200`); a Claude App session's waiting mark ends by itself after **10 min** (`APP_WAIT_MS = 600000`); on a session with notch cards (every session not from the Claude App) an approval's mark ends after **120 s** (`CARD_APPROVAL_MS = 120000`, the PermissionRequest hook's `timeout: 120`) and a question's after **130 s** (`CARD_QUESTION_MS = 130000`, the `--ask` hook's `timeout: 130`), besides the ending events; the peek opens after **0.4 s** (`PEEK_DWELL_MS = 400`); the "… ago" labels refresh once a **minute** while the island is open (`AGO_TICK_MS = 60000`). A boundary is inclusive on the later side: at exactly 10 min the session is `idle`, at exactly 5200 ms it is no longer `finished`, at exactly 120 s a card's approval is no longer open (130 s for a question), at exactly 30 min it is dim, at exactly 2 h it is gone.
- **The home folder (spec rule 1, owner 2026-10-17):** the app gives the rules its user's home folder once, as `emptyRegistry(home)`; the registry keeps it (`registry.home`, normalized, in memory only, like `cwd`) and passes it to `projectOf(cwd, roots, home)` and `projectNames(roots, home)`. A session whose `cwd` is the home folder is its own project named `HOME_NAME` (`'Home'`), and the home folder is never a root that a later session joins. The home path never reaches the view. An empty `home` means none given: the plain rule 1 (the apps always give it).
- **Caps:** at most **8** subagents per session (`SUBAGENTS_MAX = 8`, the cat's `KITTEN_MAX`); at most **64** sessions in the registry (`SESSIONS_MAX = 64`, plan decision); names at most **60** code points (`NAME_MAX`), a step at most **80** (`STEP_MAX`), at most **256** stored project cats (`PROJECT_CATS_MAX`, like `MAX_AGENT_CATS`).
- **Privacy (spec call 1, anti-goal 2):** the registry holds a session's full `cwd` **in memory only**. Nothing the view returns for display carries a `/` or `\`: names, labels, steps, types, notes. A project's `id` is `p-` plus the FNV-1a of its root, never the root. Events and the registry never hold a prompt, `transcript_path`, a tool's input or output, a notification's message or assistant text. Fixture inputs use made-up paths under `/Users/sam/…`, never a real name.
- **Frozen values.** Pill IDs, cat IDs and display mode IDs are untouched. The view's state words (`approval`, `question`, `working`, `finished`, `idle`), roles (`main`, `side`), hosts (`claude-app`, `vscode`, `terminal`) and layouts (`projects`, `agents`) are contract values from now on: a value may be added, none renamed.
- **Only new files,** except one step in `.github/workflows/build.yml`, one bullet in `CLAUDE.md` and one paragraph in `ARCHITECT.md` (Task 7). `design/prototype/cat-core.js`, `shared/sidekick-core.js`, `shared/theme.json` and every existing fixture stay byte for byte: `git diff --quiet main -- design shared/sidekick-core.js shared/theme.json tests/fixtures/cat tests/fixtures/sidekick tests/fixtures/shelf tests/fixtures/link tests/fixtures/ai tests/fixtures/mac` must succeed at the end of every task.
- **Node standard library only;** no npm package. Fixtures hold whole numbers, text, booleans, null, lists and objects only.
- **No Coucou or Mochi name in any new file.** `bash scripts/check-no-leftovers.sh` stays green.
- **Commits:** local only, never pushed. End every commit message with `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>` (or `Claude Sonnet 5.5` when an `nm-implementer-deep` wrote it).

## SUBAGENT RULES

The controller puts these in every brief.

- **Never launch, quit or replace a NotchMeow app or the Tauri app.** The work is files and Node.
- **Install and download nothing.** No `npm install`, no network.
- **Delete with `trash`, never `rm -rf`;** scratch files go in `mktemp -d` folders with the prefix `p0-`. (`scripts/test-projects-contract.sh` removes its own `mktemp` folders in a `trap`, as the sidekick runner does.)
- **Never read the real `~/.claude`, `~/.gemini` or `~/.codex`, never run the real `claude`.**
- **Never edit `design/prototype/cat-core.js`, `shared/sidekick-core.js` or an existing fixture.** The tests only `require` them.
- **Commit only in a task's commit step, never push.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder, the second `p0/projects-contract`. Otherwise stop and report.
- **If the generator stops with "the core says X, the case says Y", stop and report.** A typed answer and the core disagree; which one is right is a design question for the controller, never something to "fix" by changing the typed answer.
- **If a command is refused by a permission prompt, stop and report.** No workaround.

## Review Focus

The spec is silent on these inputs; each would bite the owner first. Each line names the test that pins it.

1. **Claude Code started in a parent folder.** The home folder (`/Users/sam`): its own project "Home", never grouping later sessions, and the user name never shown. Another parent folder (`~/Code`): rule 1 as written, later sessions under it join it (a known limit). Tests: Task 1, `projectOf` cases "the home folder is never a root that others join", "another parent folder still takes in sessions under it", `projectNames` case "the home folder is Home"; Task 4, registry cases "a session in the home folder is its own project, named Home", "a later session under the home folder is not taken in by Home", "a session under the home folder before any home session works as before", and "the home folder never reaches the view".
2. **A waiting mark that lies:** a Claude App ask never followed by an event (ends at 10 min), a subagent's tool event while the main session's approval is open (must not end it), a terminal session's card left unanswered (the approval ends at 120 s, a question at 130 s, when the hook gives up and Claude Code asks in its own window), a subagent's card that timed out (its kitten must not stay amber). Tests: Task 3, state cases "a notch card approval at 119 s" … "a notch card question at 131 s", "a Claude App approval outlives the card wait"; Task 4, registry cases "a subagent's tool event does not end the main session's approval", "the Claude App mark ends by itself after 10 min", "a notch card approval ends after 120 s, the hook's wait", "a notch card question ends after 130 s", and the test "a subagent's state follows its live card".
3. **A path reaching the screen:** a grandparent folder, a step text with a full path, a subagent type with `/`, a folder name with a bidi override, a collision label. Expected: none of it shows; only folder names, the parent's folder name in a collision label, and basenames in steps. Test: Task 4, "nothing in the view carries a path, a prompt or a message".
4. **A hostile or flooding hook stream:** 100 session ids, a 1 MB session id, `__proto__` as a session or subagent id, 20 subagents, events out of order, a payload that is not an object. Expected: caps hold (64, 8, 128), `Object.prototype` untouched, no throw, the input registry never mutated. Tests: Task 3 ("caps and hostile ids", "never mutates its input"), Task 4 (the 3000-event fuzz).
5. **Stored project cats from a damaged or newer file:** a list instead of an object, unknown coats, keys with `/`, `__proto__`, 300 keys, an empty key. Expected: the bad entries dropped, at most 256 kept, cleaning twice is cleaning once, an unknown coat falls back to the picked default. Test: Task 5, every row of `cat-cases.json` and "cleaning twice is cleaning once".

---

## File Structure

| Path | Responsibility |
|---|---|
| `shared/projects-core.js` | The rules. Grows one section per task above `// @@NEXT`; Task 7 removes the marker. |
| `scripts/gen-projects-fixtures.mjs` | Writes the seven fixture files; every case types its answer by hand. Grows one section per task above `// @@SECTIONS`; Task 7 removes the marker. |
| `tests/projects/*.test.mjs` | `paths`, `events`, `registry`, `view`, `cats`, `print`: the rules' own tests (`node --test`), each replaying its fixture file plus the checks a fixture can't hold. |
| `tests/fixtures/projects/*.json` | `project-cases`, `event-cases`, `state-cases`, `registry-cases`, `order-cases`, `claude-only-cases`, `cat-cases` (generated). |
| `scripts/test-projects-contract.sh` | Runs the tests, the no-drift check and the determinism check. CI runs it. |
| `scripts/print-projects-tables.mjs` | Prints the rules as tables for the owner's checkpoint (Task 6). |
| `docs/PROJECTS-CONTRACT.md` | What the app plans cite: the rules, the shapes, the decisions, the known limits (Task 7). |
| `.github/workflows/build.yml`, `CLAUDE.md`, `ARCHITECT.md` | One step, one bullet, one paragraph (Task 7). |

## Tasks and agents

The tasks give the exact interfaces, values and test assertions but not the function bodies, so Tasks 1 to 5 need some judgement: `nm-implementer` (Haiku 5.5, high). Tasks 6 and 7 are a small script and docs: `nm-implementer-light` (Haiku 5.5, medium). Each task is reviewed by `nm-reviewer` (Haiku 5.5, high); the whole branch by `nm-reviewer-deep` (Sonnet 5.5, high, CLAUDE.md trigger 4: the code decides what of a session's path may reach a screen). A task Haiku fails twice goes to `nm-implementer-deep` (trigger 2), recorded in the ledger.

| Task | Deliverable | Agent |
|---|---|---|
| 0. Worktree and baseline | the branch, the checks as they stand | the session |
| 1. Paths, names and roles | the core's shell and first section, the generator, the runner, `project-cases.json` | `nm-implementer` |
| 2. The hook adapter | `projectEventFrom`, `event-cases.json` | `nm-implementer` |
| 3. The registry and the states | `emptyRegistry`, `registryApply`, `registryPrune`, `sessionStateAt`, `projectStateOf`, `state-cases.json` | `nm-implementer` |
| 4. The view, the order and the big card | `projectsView`, `cleanStep`, `projectOrder`, `bigCardOf`, `waitingCount`, `registry-cases.json`, `order-cases.json`, the leak test | `nm-implementer` |
| 5. Claude only and the project cats | `claudeOnly`, `islandLayout`, `projectCatOf`, `cleanProjectCats`, `claude-only-cases.json`, `cat-cases.json` | `nm-implementer` |
| 6. The owner's tables (**owner checkpoint**) | `print-projects-tables.mjs` | `nm-implementer-light` |
| 7. Docs, CI, pointers, final checks | `PROJECTS-CONTRACT.md`, the CI step, `CLAUDE.md`, `ARCHITECT.md` | `nm-implementer-light` |
| After 7 | whole-branch review: the rules against the spec, privacy, what a port could read two ways | `nm-reviewer-deep` |

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; reviewers load `ponytail:ponytail-review`.

## Execution

One worktree chat session runs the plan on branch `p0/projects-contract`, model **Haiku 5.5 at high effort** (CLAUDE.md: a plan that needs some judgement but no platform design; not trigger 5). The three-step start of `ARCHITECT.md` applies (the chip sets up and stops; the main session sets the model; the main session sends the brief). The controller keeps a ledger at `.superpowers/sdd/2026-10-17-p0-projects-contract/progress.md` (one line per task: agent, model, commit, test lines, review verdict, any escalation and its trigger), writes each brief to a file just before dispatch, and sends task-sized briefs only (one task, the Global Constraints, the SUBAGENT RULES). Reviews read `git diff main...HEAD` narrowed to the task's files. **Stop after Task 6**, save the output of `node scripts/print-projects-tables.mjs` in the ledger folder, ping the main session with `SendMessage` and wait for its go; an owner's change is one edit in the core plus the typed answer beside its case, and a regenerate, before Task 7. Ping the main session also at the end and whenever you stop. Final report: the commits, the output of `bash scripts/test-projects-contract.sh`, the `# tests` line of `bash scripts/test-sidekick-contract.sh` and of `bash scripts/test-cat-contract.sh`, and anything unsettled.

## Interface for the app plans

What P-mac (Swift, pure `Projects*.swift` files) and P-tauri (a generated TypeScript copy, like the sidekick's `core.generated.ts`) consume. Every object below is returned with its keys **in the order written** (the generator compares JSON text).

| Export | Signature | Returns |
|---|---|---|
| constants | `VERSION` `1`, `QUIET_IDLE_MS`, `DIM_MS`, `REMOVE_MS`, `FINISHED_MS`, `APP_WAIT_MS`, `CARD_APPROVAL_MS` `120000`, `CARD_QUESTION_MS` `130000`, `PEEK_DWELL_MS`, `AGO_TICK_MS`, `SUBAGENTS_MAX`, `SESSIONS_MAX`, `NAME_MAX`, `STEP_MAX`, `PROJECT_CATS_MAX`, `APP_WAIT_LABEL` `'Waiting in Claude App'`, `HOME_NAME` `'Home'`, `STATES` `['approval','question','working','finished','idle']`, `CAT_IDS`, `PROJECT_ALIASES` | |
| `fnv1a` | `(s: string)` | 8 lower-case hex digits (FNV-1a 32 over UTF-8) |
| `normPath` | `(cwd)` | normalized path text, `''` when not a non-empty string |
| `projectOf` | `(cwd, roots: string[], home)` | `{root, worktree}` or `null` |
| `projectNames` | `(roots: string[], home)` | `[{root, name, catKey}]`, same order |
| `rolesOf` | `(sessions: [{id, worktree, seq}])` | `[{id, role, label}]`, same order |
| `sessionOrder` | `(rows: [{id, role, seq, lastAt}])` | session ids in display order |
| `projectEventFrom` | `(payload, now)` | event `{at, agent, kind, sessionId, cwd, subagentId, subagentType, fromApp, termProgram, bundleId}` or `null` |
| `emptyRegistry` | `(home)` | `{version: 1, home: normPath(home), sessions: [], otherAgentSeen: false, nextSeq: 1}` |
| `registryApply` | `(registry, event)` | a new registry (the input is never changed) |
| `registryPrune` | `(registry, now)` | a new registry without the sessions 2 h quiet |
| `sessionStateAt` | `(session, now)` | `{state, dim, gone, waitingInApp}` |
| `projectStateOf` | `(states: string[])` | one state word |
| `cleanStep` | `(text)` | step text with no path, at most 80 code points |
| `projectsView` | `(registry, now, opts?: {steps?, projectCats?, mainCat?})` | `{projects, waiting, sessionCount, otherAgentSeen}` |
| `projectOrder` | `(projects: [{id, state, lastAt}])` | a new array of the same objects, in pill order |
| `bigCardOf` | `(projects: [{id, lastAt}], pinned, clicked)` | `{project, pinned, clicked}` (ids or `null`) |
| `waitingCount` | `(projects: [{waiting}])` | a whole number |
| `claudeOnly` | `(activePills, otherAgentSeen)` | boolean |
| `islandLayout` | `(current, claudeOnlyNow, open)` | `'projects'` or `'agents'` |
| `projectCatOf` | `(catKey, projectCats, mainCat)` | `{cat, stored}` |
| `cleanProjectCats` | `(raw)` | `{[catKey]: catId}`, keys in UTF-16 code-unit order |

The app makes its registry once with `emptyRegistry(home)`, `home` being its user's home folder (Mac `FileManager.default.homeDirectoryForCurrentUser.path`, Tauri the OS home directory); `registryApply` and `projectsView` read `registry.home` and nothing else names the home folder. Registry session (held by the app, in memory only): `{id, cwd, root, worktree, seq, startedAt, lastAt, run, finishedAt, pending, fromApp, termProgram, bundleId, subagents}`, with `run` one of `working`, `idle`, `finished`; `pending` a list of `{by, kind, at, inApp}` (`by` is `''` for the main agent or a subagent's id; `kind` `approval` or `question`); `subagents` a list of `{id, type, state, born, last}` (`state` `working` or `approval`). The app's jump reads `cwd`, `termProgram`, `bundleId` and `fromApp` from here; nothing of it is displayed.

View project: `{id, name, catKey, cat, state, dim, waiting, sessionCount, lastAt, agoMin, step, host, sessions}`. View session: `{id, role, label, state, dim, waitingInApp, note, step, host, lastAt, agoMin, subagents}`. View subagent: `{id, type, state}`.

**The cat-core decision.** `projects-core.js` does **not** import `cat-core.js` (a page and the generated TypeScript copy load it alone, as `sidekick-core.js` is loaded). It copies four small pieces verbatim in behaviour: `CAT_IDS`, the seeded generator `rng` (cat-core line 31), the pick of `pickCat` for the case `taken = [main]`, and the agent-pill test of `isAgentPill`; plus `fnv1a` and the invisible-character class from `sidekick-core.js`. `tests/projects/cats.test.mjs` `require`s both cores and pins every copy to its original (same `CAT_IDS`, the same pick as `CatCore.pickCat([main], CatCore.rng(seed), null)` for 300 names × 16 Main cats, the same `fnv1a`, `SUBAGENTS_MAX === CatCore.KITTEN_MAX`). Neither `cat-core.js` nor its fixtures change. On the Mac the port may call its existing `CatAgentCats.pickCat` and `CatMath` generator directly.

## How to run this plan

Every `Run:` line runs from the worktree's root. `node --test tests/projects/*.test.mjs` runs the tests; `node scripts/gen-projects-fixtures.mjs` writes the fixtures (and stops with "…: the core says X, the case says Y" on a disagreement); `bash scripts/test-projects-contract.sh` runs it all. A test step's file is given in full; a code step gives the signatures, the rules and the values, and you write the body. Shared test header (every test file starts with it):

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const P = require('../../shared/projects-core.js');
const fx = name => JSON.parse(fs.readFileSync(new URL(`../fixtures/projects/${name}`, import.meta.url), 'utf8'));
```

Shared names used in the generator's cases and in tests: `const T = 1760000000000, MIN = 60000; const R = '/Users/sam/Code/notchmeow', WT = R + '/.claude/worktrees/p0-plan', SUB = R + '/windows/src', G = '/Users/sam/Code/gracegrip', SITE = '/Users/sam/Code/site', HOME = '/Users/sam';`

---

## Tasks

### Task 0: Worktree and baseline

No code, no commit.

- [ ] **Step 1: Branch**

```bash
git status --short                       # must print nothing
git switch -c p0/projects-contract main
git merge-base --is-ancestor c66a07ce HEAD && echo "base ok"
git ls-files docs/superpowers/plans/2026-10-17-p0-projects-contract.md docs/superpowers/specs/2026-10-17-projects-view-design.md
```

Expected: `base ok` and both paths. Otherwise stop and tell the owner.

- [ ] **Step 2: The places this plan touches are as it expects**

```bash
test -e shared/projects-core.js && echo "core exists" || echo "core is new"
test -e tests/fixtures/projects && echo "fixtures exist" || echo "fixtures are new"
grep -c "Sidekick contract (sidekick-core.js tests, fixtures, determinism)" .github/workflows/build.yml
grep -c '^- `shared/sidekick-core.js`' CLAUDE.md
grep -c '^## Code map (graphify)' ARCHITECT.md
node --version
```

Expected: `core is new`, `fixtures are new`, `1`, `1`, `1`, Node 22 or newer.

- [ ] **Step 3: Baseline**

```bash
bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "^# (tests|fail)|identical"
bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|fail)|identical"
bash scripts/check-no-leftovers.sh | tail -1
```

Record the three outputs in the ledger; `# fail 0` for both contracts.

---

### Task 1: Paths, names and roles (the shell, the generator, the runner)

**Files:**
- Create: `shared/projects-core.js`, `scripts/gen-projects-fixtures.mjs`, `scripts/test-projects-contract.sh`, `tests/projects/paths.test.mjs`
- Generated: `tests/fixtures/projects/project-cases.json`

**Interfaces:**
- Consumes: nothing.
- Produces: the module shell (`ProjectsCore` global, `module.exports`), every constant of the Interface table, `fnv1a`, `normPath`, `projectOf`, `projectNames`, `rolesOf`, `sessionOrder`; the generator with its `format`, `expectEqual`, `SECTIONS` and the markers; the runner.

- [ ] **Step 1: Write `tests/projects/paths.test.mjs`**

```js
// (shared test header)
test('constants are the spec values', () => {
  assert.equal(P.VERSION, 1);
  assert.equal(P.QUIET_IDLE_MS, 600000); assert.equal(P.DIM_MS, 1800000); assert.equal(P.REMOVE_MS, 7200000);
  assert.equal(P.FINISHED_MS, 5200); assert.equal(P.APP_WAIT_MS, 600000); assert.equal(P.PEEK_DWELL_MS, 400);
  assert.equal(P.CARD_APPROVAL_MS, 120000); assert.equal(P.CARD_QUESTION_MS, 130000); assert.equal(P.HOME_NAME, 'Home');
  assert.equal(P.AGO_TICK_MS, 60000); assert.equal(P.SUBAGENTS_MAX, 8); assert.equal(P.SESSIONS_MAX, 64);
  assert.equal(P.NAME_MAX, 60); assert.equal(P.STEP_MAX, 80); assert.equal(P.PROJECT_CATS_MAX, 256);
  assert.equal(P.APP_WAIT_LABEL, 'Waiting in Claude App');
  assert.deepEqual(P.STATES, ['approval', 'question', 'working', 'finished', 'idle']);
  assert.deepEqual(P.PROJECT_ALIASES, { 'notch-buddy': 'Notch Buddy', notchbuddy: 'Notch Buddy', notch_buddy: 'Notch Buddy' });
  assert.equal(P.CAT_IDS.length, 16);
});
test('fnv1a', () => { assert.equal(P.fnv1a('notchmeow'), 'f4e9d251'); assert.equal(P.fnv1a('café'), 'a82b5049'); assert.equal(P.fnv1a(''), '811c9dc5'); });
test('normPath', () => {
  assert.equal(P.normPath('/Users/sam/Code//notchmeow/'), '/Users/sam/Code/notchmeow');
  assert.equal(P.normPath('c:\\Users\\sam'), 'C:/Users/sam');
  assert.equal(P.normPath('/'), '/'); assert.equal(P.normPath(''), ''); assert.equal(P.normPath(42), ''); assert.equal(P.normPath(null), '');
});
const f = fx('project-cases.json');
test('projectOf replays project-cases.json', () => { for (const c of f.projectOf) assert.deepEqual(P.projectOf(c.cwd, c.roots, c.home), c.expect, c.name); });
test('projectNames replays project-cases.json', () => { for (const c of f.names) assert.deepEqual(P.projectNames(c.roots, c.home), c.expect, c.name); });
test('rolesOf replays project-cases.json', () => { for (const c of f.roles) assert.deepEqual(P.rolesOf(c.sessions), c.expect, c.name); });
test('sessionOrder replays project-cases.json', () => { for (const c of f.order) assert.deepEqual(P.sessionOrder(c.rows), c.expect, c.name); });
test('names and keys never hold a path separator', () => {
  for (const c of f.names) for (const n of c.expect) { assert.doesNotMatch(n.name, /[\/\\]/); assert.doesNotMatch(n.catKey, /[\/\\]/); }
});
test('never throws on junk', () => {
  for (const v of [undefined, null, 1, {}, [], [null, 3, {}], '\u0000']) {
    P.projectOf(v, v, v); P.projectNames(v, v); P.rolesOf(v); P.sessionOrder(v); P.normPath(v);
  }
});
```

- [ ] **Step 2: Create the runner and the generator from the sidekick's**

```bash
sed -e 's/sidekick/projects/g' scripts/test-sidekick-contract.sh > scripts/test-projects-contract.sh
chmod +x scripts/test-projects-contract.sh
{ sed -n '1,/^export const SECTIONS = {};$/p' scripts/gen-sidekick-fixtures.mjs; printf '\n// @@SECTIONS\n\n'; sed -n '/^\/\*\* Every fixture file as text, by name. \*\/$/,$p' scripts/gen-sidekick-fixtures.mjs; } | sed -e 's/sidekick/projects/g' -e 's/SIDEKICK/PROJECTS/g' > scripts/gen-projects-fixtures.mjs
grep -c "projects-core.js" scripts/gen-projects-fixtures.mjs; grep -c "@@SECTIONS" scripts/gen-projects-fixtures.mjs; bash -n scripts/test-projects-contract.sh && echo ok
```

Expected: `3` (or more), `1`, `ok`. Then, in `scripts/gen-projects-fixtures.mjs`, insert just above `// @@SECTIONS` the shared names line from "How to run this plan" (`const T = …; const R = …;`).

- [ ] **Step 3: Add the `project-cases.json` section above `// @@SECTIONS`**

```js
// ── project-cases.json: project of a session, names, roles, order inside a project ──
SECTIONS['project-cases.json'] = () => {
  const projectOf = [], names = [], roles = [], order = [];
  const po = (name, cwd, roots, expect, home = HOME) => { expectEqual(name, core.projectOf(cwd, roots, home), expect); projectOf.push({ name, cwd, roots, home, expect }); };
  po('a repository root is its own project', R, [], { root: R, worktree: '' });
  po('a worktree belongs to the repository before /.claude/worktrees/', WT, [], { root: R, worktree: 'p0-plan' });
  po('a folder inside a worktree is still that worktree', WT + '/windows', [], { root: R, worktree: 'p0-plan' });
  po('a subfolder joins a known project', SUB, [R], { root: R, worktree: '' });
  po('a subfolder with no known project is its own project', SUB, [], { root: SUB, worktree: '' });
  po('a sibling with the same prefix is not inside it', '/Users/sam/Code/notchmeow-old', [R], { root: '/Users/sam/Code/notchmeow-old', worktree: '' });
  po('the longest known root wins', SUB, ['/Users/sam/Code', R], { root: R, worktree: '' });
  po('doubled and trailing slashes fold away', '/Users/sam/Code//notchmeow/', [], { root: R, worktree: '' });
  po('a path with spaces', '/Users/sam/GitHub Local Repos/notchmeow', [], { root: '/Users/sam/GitHub Local Repos/notchmeow', worktree: '' });
  po('a worktree in a worktree: the repository, and the innermost name', R + '/.claude/worktrees/a/.claude/worktrees/b', [], { root: R, worktree: 'b' });
  po('a worktree outside /.claude/worktrees/ is its own project', '/Users/sam/Code/notchmeow-wt', [R], { root: '/Users/sam/Code/notchmeow-wt', worktree: '' });
  po('a Windows path: backslashes and the drive letter', 'c:\\Users\\sam\\Code\\notchmeow\\.claude\\worktrees\\x', [], { root: 'C:/Users/sam/Code/notchmeow', worktree: 'x' });
  po('the root folder / matches only itself', '/Users/sam/x', ['/'], { root: '/Users/sam/x', worktree: '' });
  po('the root folder itself', '/', [], { root: '/', worktree: '' });
  po('an empty cwd is no project', '', [R], null);
  po('a cwd that is not text is no project', 7, [R], null);
  po('roots that are not text are skipped', SUB, [null, 3, R], { root: R, worktree: '' });
  po('the home folder is its own project', HOME, [], { root: HOME, worktree: '' });
  po('the home folder is never a root that others join', R, [HOME], { root: R, worktree: '' });
  po('under the home folder, a known project still takes its subfolders', SUB, [HOME, R], { root: R, worktree: '' });
  po('the home folder as given is normalized', R, [HOME], { root: R, worktree: '' }, '/Users/sam/');
  po('a worktree of a repository at the home folder belongs to it', HOME + '/.claude/worktrees/w1', [], { root: HOME, worktree: 'w1' });
  po('a Windows home folder', 'c:\\Users\\sam\\Code\\x', ['C:/Users/sam'], { root: 'C:/Users/sam/Code/x', worktree: '' }, 'C:\\Users\\sam');
  po('another parent folder still takes in sessions under it', R, ['/Users/sam/Code'], { root: '/Users/sam/Code', worktree: '' });
  po('no home folder given: the plain rule', R, [HOME], { root: HOME, worktree: '' }, '');
  const nm = (name, roots, expect, home = HOME) => { expectEqual(name, core.projectNames(roots, home), expect); names.push({ name, roots, home, expect }); };
  nm('a project is named by its folder', [R], [{ root: R, name: 'notchmeow', catKey: 'notchmeow' }]);
  nm('two projects with the same folder name show the parent folder', ['/Users/sam/GitHub Local Repos/notchmeow', R],
    [{ root: '/Users/sam/GitHub Local Repos/notchmeow', name: 'notchmeow — GitHub Local Repos', catKey: 'notchmeow' }, { root: R, name: 'notchmeow — Code', catKey: 'notchmeow' }]);
  nm('same folder and same parent: a number in first-seen order', ['/a/x/site', '/b/x/site'],
    [{ root: '/a/x/site', name: 'site — x', catKey: 'site' }, { root: '/b/x/site', name: 'site — x · 2', catKey: 'site' }]);
  nm('a root with no parent folder keeps the bare name', ['/proj', '/x/proj'], [{ root: '/proj', name: 'proj', catKey: 'proj' }, { root: '/x/proj', name: 'proj — x', catKey: 'proj' }]);
  nm('the alias table', ['/Users/sam/notch-buddy'], [{ root: '/Users/sam/notch-buddy', name: 'Notch Buddy', catKey: 'Notch Buddy' }]);
  nm('the root folder is Session', ['/'], [{ root: '/', name: 'Session', catKey: 'Session' }]);
  nm('a bidi override is removed', ['/Users/sam/Code/notch\u202Emeow'], [{ root: '/Users/sam/Code/notch\u202Emeow', name: 'notchmeow', catKey: 'notchmeow' }]);
  const long = 'n'.repeat(100);
  nm('a long folder name is cut at 60 code points', ['/Users/sam/' + long], [{ root: '/Users/sam/' + long, name: 'n'.repeat(59) + '…', catKey: 'n'.repeat(59) + '…' }]);
  nm('a Windows root', ['C:/Users/sam/notchmeow'], [{ root: 'C:/Users/sam/notchmeow', name: 'notchmeow', catKey: 'notchmeow' }]);
  nm('the home folder is Home', [HOME], [{ root: HOME, name: 'Home', catKey: 'Home' }]);
  nm('a folder named Home beside the home folder shows its parent; Home stays Home', [HOME, '/Users/sam/x/Home'],
    [{ root: HOME, name: 'Home', catKey: 'Home' }, { root: '/Users/sam/x/Home', name: 'Home — x', catKey: 'Home' }]);
  nm('no home folder given: named by its folder', [HOME], [{ root: HOME, name: 'sam', catKey: 'sam' }], '');
  const rl = (name, sessions, expect) => { expectEqual(name, core.rolesOf(sessions), expect); roles.push({ name, sessions, expect }); };
  rl('main, a side session, a second main', [{ id: 's1', worktree: '', seq: 1 }, { id: 's2', worktree: 'p0-plan', seq: 2 }, { id: 's3', worktree: '', seq: 3 }],
    [{ id: 's1', role: 'main', label: 'main' }, { id: 's2', role: 'side', label: 'p0-plan' }, { id: 's3', role: 'main', label: 'main · 2' }]);
  rl('mains are numbered in start order, whatever the input order', [{ id: 's3', worktree: '', seq: 3 }, { id: 's1', worktree: '', seq: 1 }],
    [{ id: 's3', role: 'main', label: 'main · 2' }, { id: 's1', role: 'main', label: 'main' }]);
  rl('two sessions in one worktree', [{ id: 'a', worktree: 'x', seq: 1 }, { id: 'b', worktree: 'x', seq: 2 }],
    [{ id: 'a', role: 'side', label: 'x' }, { id: 'b', role: 'side', label: 'x · 2' }]);
  const so = (name, rows, expect) => { expectEqual(name, core.sessionOrder(rows), expect); order.push({ name, rows, expect }); };
  so('mains in start order, then sides by most recent activity', [{ id: 'm2', role: 'main', seq: 2, lastAt: 500 }, { id: 's-a', role: 'side', seq: 3, lastAt: 100 }, { id: 'm1', role: 'main', seq: 1, lastAt: 50 }, { id: 's-b', role: 'side', seq: 4, lastAt: 900 }], ['m1', 'm2', 's-b', 's-a']);
  so('sides with the same time: by id', [{ id: 'z', role: 'side', seq: 1, lastAt: 5 }, { id: 'y', role: 'side', seq: 2, lastAt: 5 }], ['y', 'z']);
  return { version: 1, note: 'projectOf(cwd, roots, home) -> {root, worktree} | null; projectNames(roots, home) -> [{root, name, catKey}] (the home folder is Home and never a root others join; an empty home is none); rolesOf(sessions) -> [{id, role, label}]; sessionOrder(rows) -> ids. Paths here are inputs only: nothing displayed holds one.', projectOf, names, roles, order };
};
```

- [ ] **Step 4: Run the tests to see them fail**

Run: `node --test tests/projects/*.test.mjs 2>&1 | grep -E "^# (pass|fail)"` → Expected: FAIL (`Cannot find module '../../shared/projects-core.js'`).

- [ ] **Step 5: Create `shared/projects-core.js`**

The wrapper is `shared/sidekick-core.js`'s first 16 lines with `SidekickCore` → `ProjectsCore` and a header comment saying: the Projects rules (sub-project P, `docs/PROJECTS-CONTRACT.md`); pure; both apps port these rules and replay `tests/fixtures/projects/*.json`, which `scripts/gen-projects-fixtures.mjs` writes from this file; if an app and a fixture disagree, this file decides; a full path is held in the registry in memory only and never reaches a display field. It ends with `// @@NEXT`, then `return api;` and `});`. Contents of this task:

- Every constant of the Interface table, on `api`. `CAT_IDS` is `['shrimpy','momo','ginger','midnight','latte','patches','blue','snow','oreo','mocha','silver','cloud','leo','button','puff','noodle']` (cat-core's order).
- Private helpers: `isObj`, `isStr`, `isNum`, `own` (hasOwnProperty), `INVISIBLE` (the same character class as `baseName` in `shared/sidekick-core.js` line 27, built with `new RegExp(…, 'gu')`), `cleanName(s)` (remove `INVISIBLE`, cut to `NAME_MAX` code points as 59 + `…`).
- `fnv1a(s)`: copy `shared/sidekick-core.js`'s `fnv1a` exactly.
- `normPath(cwd)`: `''` unless a non-empty string; `\` → `/`; runs of `/` → one; trailing `/` dropped unless the whole path is `/`; a leading lower-case drive letter `x:` upper-cased.
- `projectOf(cwd, roots, home)`: `n = normPath(cwd)`, `null` when empty; `h = normPath(home)` (`''` when not text: no home rule). If `n` contains `/.claude/worktrees/`: `root` is the text before its **first** occurrence (or `/` if that is empty), `worktree` is `cleanName` of the path segment right after its **last** occurrence (a worktree of a repository at the home folder belongs to the home project). Else if `h` and `n === h`: `{root: h, worktree: ''}`. Else: among `roots` (strings only, each through `normPath`, **skipping a root equal to `h`**), the longest `r` with `n === r` or `n` starting with `r + '/'`, where `r === '/'` and a bare drive (`/^[A-Z]:$/`) match only by equality; `root` is that `r`, or `n` when none; `worktree` `''`.
- `projectNames(roots, home)`: for each string root, `catKey` = `cleanName(last segment)`, through `PROJECT_ALIASES` (lookup by lower case), or `'Session'` when empty; a root equal to `normPath(home)` (when not empty) has `catKey` `HOME_NAME` and is always named exactly `HOME_NAME`. When two or more roots share a `catKey`, each of them **but the home root** is labelled `` `${catKey} — ${parent}` `` with `parent` = `cleanName` of the second-to-last segment (the bare `catKey` when there is none). Then among equal labels, the second and later (in input order) get `` ` · ${k}` `` (k = 2, 3, …). Segments are the non-empty parts of `root.split('/')`. (So the home folder's own name, the user name, is never shown.)
- `rolesOf(sessions)`: objects only; a session with `worktree === ''` is `main`, else `side`. In `seq` order, the k-th main is `main` (k = 1) or `` `main · ${k}` ``; the k-th session of one worktree name is that name or `` `${name} · ${k}` ``. Output in input order.
- `sessionOrder(rows)`: objects only; mains first, by `seq` ascending; then sides by `lastAt` descending; ties by `id` ascending (plain `<`).

- [ ] **Step 6: Generate and pass**

Run: `node scripts/gen-projects-fixtures.mjs && node --test tests/projects/*.test.mjs 2>&1 | grep -E "^# (pass|fail)"` → Expected: `wrote 1 fixture files to tests/fixtures/projects`, `# fail 0`. Then `bash scripts/test-projects-contract.sh | tail -2` → `✓ 1 fixture files match projects-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 7: Commit**

```bash
git add shared/projects-core.js scripts/gen-projects-fixtures.mjs scripts/test-projects-contract.sh tests/projects/paths.test.mjs tests/fixtures/projects/project-cases.json
git commit -m "feat(projects): P-0 core shell, project of a session, names and roles

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The hook adapter `projectEventFrom`

**Files:**
- Modify: `shared/projects-core.js` (above `// @@NEXT`), `scripts/gen-projects-fixtures.mjs` (above `// @@SECTIONS`)
- Create: `tests/projects/events.test.mjs`
- Generated: `tests/fixtures/projects/event-cases.json`

**Interfaces:**
- Consumes: Task 1's helpers.
- Produces: `projectEventFrom(payload, now) -> {at, agent, kind, sessionId, cwd, subagentId, subagentType, fromApp, termProgram, bundleId} | null`. `agent` is `'claude'` or another agent's pill ID; `kind` one of `start`, `prompt`, `preTool`, `tool`, `approval`, `question`, `note`, `stop`, `halt`, `subStart`, `subStop`, `end`, and `other` for another agent.

- [ ] **Step 1: Write `tests/projects/events.test.mjs`**

```js
// (shared test header)
const f = fx('event-cases.json');
test('projectEventFrom replays event-cases.json', () => { for (const c of f.cases) assert.deepEqual(P.projectEventFrom(c.payload, c.now), c.expect, c.name); });
test('an event keeps no prompt, transcript, tool input, message or answer', () => {
  const p = { hook_event_name: 'PermissionRequest', session_id: 's1', cwd: '/Users/sam/Code/notchmeow', prompt: 'MARKER-PROMPT', transcript_path: '/Users/sam/MARKER-TRANSCRIPT.jsonl',
    tool_name: 'Bash', tool_input: { command: 'rm MARKER-CMD' }, tool_response: 'MARKER-OUT', message: 'MARKER-MSG?', last_assistant_message: 'MARKER-ASSIST' };
  const s = JSON.stringify(P.projectEventFrom(p, 1));
  for (const m of ['MARKER-PROMPT', 'MARKER-TRANSCRIPT', 'MARKER-CMD', 'MARKER-OUT', 'MARKER-MSG', 'MARKER-ASSIST']) assert.ok(!s.includes(m), m);
});
test('ids are cut at 128 code points', () => {
  const e = P.projectEventFrom({ hook_event_name: 'Stop', session_id: 'x'.repeat(300), cwd: '/a' }, 1);
  assert.equal(e.sessionId.length, 128);
});
test('never throws', () => { for (const v of [undefined, null, 3, 'x', [], { hook_event_name: 5 }, { hook_event_name: 'Stop', session_id: {} }]) P.projectEventFrom(v, 1); });
```

- [ ] **Step 2: Add the `event-cases.json` section**

```js
// ── event-cases.json: what the registry takes from a hook payload ──
SECTIONS['event-cases.json'] = () => {
  const cases = [];
  const E = (kind, o = {}) => ({ at: T, agent: 'claude', kind, sessionId: 's1', cwd: R, subagentId: '', subagentType: '', fromApp: false, termProgram: '', bundleId: '', ...o });
  const O = agent => E('other', { agent, sessionId: '', cwd: '' });
  const ev = (name, payload, expect, now = T) => { expectEqual(name, core.projectEventFrom(payload, now), expect); cases.push({ name, payload, now, expect }); };
  const p = (hook, x = {}) => ({ hook_event_name: hook, session_id: 's1', cwd: R, ...x });
  ev('a prompt, without the prompt', p('UserPromptSubmit', { prompt: 'fix it' }), E('prompt'));
  ev('SessionStart', p('SessionStart'), E('start'));
  ev('a tool about to run', p('PreToolUse', { tool_name: 'Bash', tool_input: { command: 'ls' } }), E('preTool'));
  ev('AskUserQuestion before it runs is a question', p('PreToolUse', { tool_name: 'AskUserQuestion' }), E('question'));
  ev('a permission request', p('PermissionRequest', { tool_name: 'Bash' }), E('approval'));
  ev('a permission request for AskUserQuestion is a question', p('PermissionRequest', { tool_name: 'AskUserQuestion' }), E('question'));
  ev('a tool that ran', p('PostToolUse', { tool_name: 'Read' }), E('tool'));
  ev('a tool that failed is a tool event', p('PostToolUseFailure', { tool_name: 'Bash' }), E('tool'));
  ev('a notification that asks is a question', p('Notification', { message: 'Which file should I use?' }), E('question'));
  ev('a question mark followed by spaces', p('Notification', { message: '  Ready?  ' }), E('question'));
  ev('any other notification is a note', p('Notification', { message: 'Claude is waiting for your input' }), E('note'));
  ev('a notification with no message is a note', p('Notification'), E('note'));
  ev('Stop', p('Stop'), E('stop'));
  ev('StopFailure halts', p('StopFailure'), E('halt'));
  ev('Interrupt halts', p('Interrupt'), E('halt'));
  ev('SessionEnd', p('SessionEnd'), E('end'));
  ev('a subagent starts', p('SubagentStart', { agent_id: 'k1', agent_type: 'Explore' }), E('subStart', { subagentId: 'k1', subagentType: 'Explore' }));
  ev('a subagent stops', p('SubagentStop', { agent_id: 'k1' }), E('subStop', { subagentId: 'k1' }));
  ev("a subagent's tool event carries its id", p('PreToolUse', { tool_name: 'Grep', agent_id: 'k1', agent_type: 'Explore' }), E('preTool', { subagentId: 'k1', subagentType: 'Explore' }));
  ev('a subagent type loses its slashes', p('SubagentStart', { agent_id: 'k2', agent_type: 'plugin/x\\y' }), E('subStart', { subagentId: 'k2', subagentType: 'plugin-x-y' }));
  ev('a session from the Claude app is Claude Code, marked fromApp', p('PreToolUse', { nm_agent: 'claude-desktop' }), E('preTool', { fromApp: true }));
  ev('the tag claude is Claude Code', p('Stop', { nm_agent: 'claude' }), E('stop'));
  ev('an invalid tag is Claude Code, as the pill routing does', p('Stop', { nm_agent: 'Bad Tag!' }), E('stop'));
  ev('the terminal and the bundle are kept', p('Stop', { term_program: 'vscode', bundle_id: 'com.microsoft.VSCode' }), E('stop', { termProgram: 'vscode', bundleId: 'com.microsoft.VSCode' }));
  ev('conversation_id stands in for session_id', { hook_event_name: 'Stop', conversation_id: 'c1', cwd: R }, E('stop', { sessionId: 'c1' }));
  ev('a cwd that is not text is empty', { hook_event_name: 'Stop', session_id: 's1', cwd: 3 }, E('stop', { cwd: '' }));
  ev('Codex is another agent', p('UserPromptSubmit', { nm_agent: 'codex' }), O('agent_codex'));
  ev('another agent with its own event names', p('BeforeTool', { nm_agent: 'gemini-cli' }), O('agent_gemini-cli'));
  ev('Cursor is told by its bundle', p('PreToolUse', { bundle_id: 'com.todesktop.230313mzl4w4u92' }), O('agent_cursor'));
  ev('an event name Claude Code does not send', p('Whatever'), null);
  ev('no session id', { hook_event_name: 'Stop', cwd: R }, null);
  ev('no event name', { session_id: 's1', cwd: R }, null);
  ev('not an object', 'Stop', null);
  ev('a time that is not a number', p('Stop'), null, null);
  return { version: 1, note: 'projectEventFrom(payload, now) -> event | null. The event never holds the prompt, transcript_path, tool input or output, or a message.', cases };
};
```

- [ ] **Step 3: Run to fail** — `node --test tests/projects/events.test.mjs 2>&1 | grep -E "^# fail"` → FAIL (`P.projectEventFrom is not a function` or the missing fixture).

- [ ] **Step 4: Implement `projectEventFrom(payload, now)`**

Rules, in order: `null` unless `payload` is an object and `now` a finite number; `name` = `hook_event_name` if a non-empty string, else `null`. The **agent**: `nm_agent === 'claude-desktop'` → `'claude'`; else a tag other than `'claude'` matching `/^[a-z0-9-]{1,24}$/` → `'agent_' + tag`; else `bundle_id` equal (case-insensitive) to `'com.todesktop.230313mzl4w4u92'` → `'agent_cursor'`; else `'claude'`. Another agent returns the fixed-shape event with `kind: 'other'` and every other field empty (`''`/`false`) for **any** event name. For Claude, `name` maps by this table (anything else → `null`): `SessionStart` start, `UserPromptSubmit` prompt, `PreToolUse` preTool, `PostToolUse` tool, `PostToolUseFailure` tool, `PermissionRequest` approval, `Notification` note, `Stop` stop, `StopFailure` halt, `Interrupt` halt, `SubagentStart` subStart, `SubagentStop` subStop, `SessionEnd` end. Then `tool_name === 'AskUserQuestion'` turns preTool and approval into `question`, and a note whose `message` is a string ending in `?` after trimming becomes `question`. `sessionId` = the first non-empty string of `session_id`, `conversation_id`, cut to 128 code points; none → `null`. `cwd` = the string or `''`. `subagentId` = `agent_id` if a non-empty string (cut to 128), else `''`. `subagentType` = `agent_type` if a string: `INVISIBLE` removed, every `/` and `\` → `-`, cut to 64 code points (no ellipsis); else `''`. `fromApp` = `nm_agent === 'claude-desktop'`. `termProgram`, `bundleId` = the strings cut to 128, else `''`.

- [ ] **Step 5: Generate and pass** — `node scripts/gen-projects-fixtures.mjs && bash scripts/test-projects-contract.sh 2>&1 | grep -E "^# fail|✓ two"` → `# fail 0`, `✓ two generator runs write identical bytes`.

- [ ] **Step 6: Commit** — the two edited files, `tests/projects/events.test.mjs`, `tests/fixtures/projects/event-cases.json`; message `feat(projects): P-0 hook adapter` with the trailer.

---

### Task 3: The registry and the time-based states

**Files:**
- Modify: `shared/projects-core.js`, `scripts/gen-projects-fixtures.mjs`
- Create: `tests/projects/registry.test.mjs`
- Generated: `tests/fixtures/projects/state-cases.json`

**Interfaces:**
- Consumes: `projectOf`, `normPath`, `projectEventFrom` (tests only).
- Produces: `emptyRegistry(home)` (the registry carries `home`), `registryApply(registry, event)`, `registryPrune(registry, now)`, `sessionStateAt(session, now) -> {state, dim, gone, waitingInApp}`, `projectStateOf(states) -> state`, and the registry session shape of the Interface section.

- [ ] **Step 1: Write `tests/projects/registry.test.mjs`**

```js
// (shared test header)
const T = 1760000000000, MIN = 60000, R = '/Users/sam/Code/notchmeow';
const f = fx('state-cases.json');
test('sessionStateAt replays state-cases.json', () => { for (const c of f.sessions) assert.deepEqual(P.sessionStateAt(c.session, c.now), c.expect, c.name); });
test('projectStateOf replays state-cases.json', () => { for (const c of f.projects) assert.deepEqual(P.projectStateOf(c.states), c.expect, c.name); });
const feed = (reg, at, payload) => P.registryApply(reg, P.projectEventFrom(payload, at));
const p = (hook, sid, cwd, x = {}) => ({ hook_event_name: hook, session_id: sid, cwd, ...x });
test('emptyRegistry, and the home folder it carries', () => {
  assert.deepEqual(P.emptyRegistry(), { version: 1, home: '', sessions: [], otherAgentSeen: false, nextSeq: 1 });
  assert.equal(P.emptyRegistry('/Users/sam/').home, '/Users/sam'); assert.equal(P.emptyRegistry(3).home, '');
  assert.equal(P.registryApply(P.emptyRegistry('/Users/sam'), null).home, '/Users/sam');
  assert.equal(P.registryPrune(P.emptyRegistry('/Users/sam'), T).home, '/Users/sam');
});
test('a new session has the documented shape', () => {
  const r = feed(P.emptyRegistry(), T, p('UserPromptSubmit', 's1', R + '/', { term_program: 'iTerm.app', bundle_id: 'com.googlecode.iterm2' }));
  assert.deepEqual(r.sessions, [{ id: 's1', cwd: R, root: R, worktree: '', seq: 1, startedAt: T, lastAt: T, run: 'working', finishedAt: null, pending: [], fromApp: false, termProgram: 'iTerm.app', bundleId: 'com.googlecode.iterm2', subagents: [] }]);
  assert.equal(r.nextSeq, 2);
});
test('another agent makes no session and is remembered', () => {
  const r = feed(P.emptyRegistry(), T, p('UserPromptSubmit', 'x', R, { nm_agent: 'codex' }));
  assert.equal(r.sessions.length, 0); assert.equal(r.otherAgentSeen, true);
});
test('a new session needs a cwd; SessionEnd for an unknown session does nothing', () => {
  let r = feed(P.emptyRegistry(), T, p('UserPromptSubmit', 's1', ''));
  r = feed(r, T, p('SessionEnd', 's2', R));
  assert.deepEqual(r, P.emptyRegistry());
});
test('a null or bad event returns the registry as it was', () => {
  const r = feed(P.emptyRegistry(), T, p('UserPromptSubmit', 's1', R));
  assert.deepEqual(P.registryApply(r, null), r); assert.deepEqual(P.registryApply(r, { at: 'x' }), r);
  assert.deepEqual(P.registryApply('junk', null), P.emptyRegistry());
});
test('events out of order never move lastAt back', () => {
  let r = feed(P.emptyRegistry(), T + 5000, p('UserPromptSubmit', 's1', R));
  r = feed(r, T, p('PostToolUse', 's1', R, { tool_name: 'Read' }));
  assert.equal(r.sessions[0].lastAt, T + 5000);
});
test('the pending list: per asker, replaced, cleared by its own asker', () => {
  let r = feed(P.emptyRegistry(), T, p('PermissionRequest', 's1', R, { tool_name: 'Bash' }));
  r = feed(r, T + 1, p('PermissionRequest', 's1', R, { tool_name: 'Bash' }));
  r = feed(r, T + 2, p('PermissionRequest', 's1', R, { tool_name: 'Bash', agent_id: 'k1' }));
  assert.deepEqual(r.sessions[0].pending, [{ by: '', kind: 'approval', at: T + 1, inApp: false }, { by: 'k1', kind: 'approval', at: T + 2, inApp: false }]);
  r = feed(r, T + 3, p('PostToolUse', 's1', R, { tool_name: 'Bash', agent_id: 'k1' }));
  assert.deepEqual(r.sessions[0].pending.map(x => x.by), ['']);
  r = feed(r, T + 4, p('UserPromptSubmit', 's1', R));
  assert.deepEqual(r.sessions[0].pending, []);
});
test('registryPrune drops sessions 2 h quiet', () => {
  const r = feed(P.emptyRegistry(), T, p('UserPromptSubmit', 's1', R));
  assert.equal(P.registryPrune(r, T + 120 * MIN - 1).sessions.length, 1);
  assert.equal(P.registryPrune(r, T + 120 * MIN).sessions.length, 0);
});
test('caps and hostile ids', () => {
  let r = P.emptyRegistry();
  for (let i = 0; i < 100; i++) r = feed(r, T + i, p('UserPromptSubmit', 's' + i, R + '/x' + i));
  assert.equal(r.sessions.length, 64);
  assert.ok(!r.sessions.some(s => s.id === 's0') && r.sessions.some(s => s.id === 's99'));   // the least recently active went
  for (let i = 0; i < 20; i++) r = feed(r, T + 200 + i, p('SubagentStart', 's99', R, { agent_id: 'k' + i, agent_type: 't' }));
  assert.equal(r.sessions.find(s => s.id === 's99').subagents.length, 8);
  r = feed(r, T + 300, p('UserPromptSubmit', '__proto__', R));
  r = feed(r, T + 301, p('SubagentStart', '__proto__', R, { agent_id: '__proto__', agent_type: 'constructor' }));
  assert.equal(({}).polluted, undefined); assert.equal(Object.getPrototypeOf({}), Object.prototype);
  assert.ok(r.sessions.some(s => s.id === '__proto__'));
});
test('never mutates its input', () => {
  const deepFreeze = o => { Object.values(o).forEach(v => v && typeof v === 'object' && deepFreeze(v)); return Object.freeze(o); };
  let r = feed(P.emptyRegistry(), T, p('UserPromptSubmit', 's1', R));
  r = feed(r, T, p('SubagentStart', 's1', R, { agent_id: 'k1', agent_type: 'Explore' }));
  const frozen = deepFreeze(JSON.parse(JSON.stringify(r)));
  for (const h of ['PreToolUse', 'PermissionRequest', 'Stop', 'StopFailure', 'SubagentStop', 'SessionEnd']) P.registryApply(frozen, P.projectEventFrom(p(h, 's1', R, { agent_id: 'k1' }), T + 1));
  P.registryPrune(frozen, T + 999 * MIN);
});
test('the registry keeps no prompt, transcript, command or message', () => {
  let r = P.emptyRegistry();
  r = feed(r, T, p('UserPromptSubmit', 's1', R, { prompt: 'MARKER-PROMPT', transcript_path: '/x/MARKER-TRANSCRIPT' }));
  r = feed(r, T, p('PermissionRequest', 's1', R, { tool_name: 'Bash', tool_input: { command: 'MARKER-CMD' } }));
  r = feed(r, T, p('Notification', 's1', R, { message: 'MARKER-MSG?' }));
  const s = JSON.stringify(r);
  for (const m of ['MARKER-PROMPT', 'MARKER-TRANSCRIPT', 'MARKER-CMD', 'MARKER-MSG']) assert.ok(!s.includes(m), m);
});
```

- [ ] **Step 2: Add the `state-cases.json` section**

```js
// ── state-cases.json: a session's state at a time, a project's state ──
SECTIONS['state-cases.json'] = () => {
  const sessions = [], projects = [];
  const S = (o = {}) => ({ id: 's1', cwd: R, root: R, worktree: '', seq: 1, startedAt: T, lastAt: T, run: 'working', finishedAt: null, pending: [], fromApp: false, termProgram: '', bundleId: '', subagents: [], ...o });
  const X = (state, o = {}) => ({ state, dim: false, gone: false, waitingInApp: false, ...o });
  const st = (name, session, dt, expect) => { expectEqual(name, core.sessionStateAt(session, T + dt), expect); sessions.push({ name, session, now: T + dt, expect }); };
  st('working just before 10 min quiet', S(), 10 * MIN - 1, X('working'));
  st('quiet for 10 min shows idle', S(), 10 * MIN, X('idle'));
  st('finished just before 5.2 s', S({ run: 'finished', finishedAt: T }), 5199, X('finished'));
  st('finished becomes idle at 5.2 s', S({ run: 'finished', finishedAt: T }), 5200, X('idle'));
  st('not dim just before 30 min', S({ run: 'idle' }), 30 * MIN - 1, X('idle'));
  st('dim at 30 min', S({ run: 'idle' }), 30 * MIN, X('idle', { dim: true }));
  st('not gone just before 2 h', S({ run: 'idle' }), 120 * MIN - 1, X('idle', { dim: true }));
  st('gone at 2 h', S({ run: 'idle' }), 120 * MIN, X('idle', { dim: true, gone: true }));
  st('an open approval outranks a running tool', S({ pending: [{ by: '', kind: 'approval', at: T, inApp: false }] }), 1000, X('approval'));
  st('an approval outranks a question', S({ pending: [{ by: '', kind: 'question', at: T, inApp: false }, { by: 'k1', kind: 'approval', at: T, inApp: false }] }), 1000, X('approval'));
  st('a question', S({ pending: [{ by: '', kind: 'question', at: T, inApp: false }] }), 1000, X('question'));
  const cardA = { pending: [{ by: '', kind: 'approval', at: T, inApp: false }] }, cardQ = { pending: [{ by: '', kind: 'question', at: T, inApp: false }] };
  const appA = { fromApp: true, pending: [{ by: '', kind: 'approval', at: T, inApp: true }] };
  st('a notch card approval at 119 s', S(cardA), 119000, X('approval'));
  st("a notch card approval ends at 120 s, the hook's wait", S(cardA), 120000, X('working'));
  st('a notch card approval at 121 s', S(cardA), 121000, X('working'));
  st('a notch card question at 129 s', S(cardQ), 129000, X('question'));
  st("a notch card question ends at 130 s, the --ask hook's wait", S(cardQ), 130000, X('working'));
  st('a notch card question at 131 s', S(cardQ), 131000, X('working'));
  st("a subagent's approval card ended, the main agent's question still open", S({ pending: [{ by: 'k1', kind: 'approval', at: T, inApp: false }, { by: '', kind: 'question', at: T, inApp: false }] }), 125000, X('question'));
  st('a Claude App approval outlives the card wait', S(appA), 121000, X('approval', { waitingInApp: true }));
  st('the Claude App mark just before 10 min', S(appA), 10 * MIN - 1, X('approval', { waitingInApp: true }));
  st('the Claude App mark ends at 10 min', S(appA), 10 * MIN, X('idle'));
  st('a clock behind the last event counts as no time', S(), -5000, X('working'));
  st('idle stays idle', S({ run: 'idle' }), 0, X('idle'));
  const ps = (name, states, expect) => { expectEqual(name, core.projectStateOf(states), expect); projects.push({ name, states, expect }); };
  ps('working beats idle', ['idle', 'working'], 'working');
  ps('finished beats idle', ['finished', 'idle'], 'finished');
  ps('a question beats working', ['working', 'question'], 'question');
  ps('an approval beats a question', ['question', 'approval'], 'approval');
  ps('no session is idle', [], 'idle');
  ps('an unknown word counts for nothing', ['bogus', 'idle'], 'idle');
  return { version: 1, note: 'sessionStateAt(session, now) -> {state, dim, gone, waitingInApp}; an open ask lasts 10 min from the Claude App, else 120 s (approval) or 130 s (question); projectStateOf(states) -> the most urgent: approval, question, working, finished, idle.', sessions, projects };
};
```

- [ ] **Step 3: Run to fail** — `node --test tests/projects/registry.test.mjs 2>&1 | grep -E "^# fail"` → FAIL.

- [ ] **Step 4: Implement the registry and the states**

- `emptyRegistry(home)` as in the Interface (`home: normPath(home)`).
- A private `cleanRegistry(r)`: an empty registry unless `r` is an object; else a deep copy (`JSON.parse(JSON.stringify(...))`) as `{version: 1, home: normPath(r.home), sessions (objects only), otherAgentSeen === true, nextSeq (finite number, else 1)}`. Every exported function works on such a copy: the input is never changed.
- `registryPrune(registry, now)`: the clean copy without the sessions with `now - lastAt >= REMOVE_MS`.
- `registryApply(registry, ev)`: a clean copy unchanged when `ev` is not an object with a finite `at`. Else, in order:
  1. prune with `ev.at`;
  2. `ev.agent !== 'claude'` → `otherAgentSeen = true`, return;
  3. find the session with `id === ev.sessionId`. None: return unchanged when `ev.kind === 'end'` or `normPath(ev.cwd)` is empty; else create it with `projectOf(ev.cwd, distinct roots of the current sessions, registry.home)`: `{id, cwd: normPath(ev.cwd), root, worktree, seq: nextSeq (then nextSeq + 1), startedAt: ev.at, lastAt: ev.at, run: 'idle', finishedAt: null, pending: [], fromApp: false, termProgram: '', bundleId: '', subagents: []}`, append it, and while there are more than `SESSIONS_MAX` sessions drop the one with the smallest `lastAt` (ties: smallest `seq`); if the new one was dropped, return. **The root is fixed here: later events never move a session to another project** (rule 1, "from the session's first cwd").
  4. `lastAt = max(lastAt, ev.at)`; non-empty `termProgram`/`bundleId` replace the stored ones; `ev.fromApp` sets `fromApp = true` (it never goes back).
  5. by `ev.kind`, with `by = ev.subagentId` (`''` for the main agent): `end` removes the session; `prompt` → `run = 'working'`, `pending = []`; `preTool`, `tool` → `run = 'working'`, drop the pending entries of `by`, and a subagent with that id becomes `working` with `last = max(last, at)`; `approval`, `question` → `run = 'working'`, drop the pending of `by`, append `{by, kind, at: ev.at, inApp: session.fromApp}`, and a subagent with that id becomes `approval` (`last` as above); `stop` → `run = 'finished'`, `finishedAt = ev.at`, `pending = []`, `subagents = []`; `halt` → `run = 'idle'`, `finishedAt = null`, `pending = []`, `subagents = []`; `subStart` (only with a non-empty `by`) → an existing subagent gets `last = max(last, at)` and a non-empty new type; else append `{id: by, type: ev.subagentType, state: 'working', born: ev.at, last: ev.at}` and while more than `SUBAGENTS_MAX` drop the smallest `born`; `subStop` (non-empty `by`) → remove that subagent and its pending; `start`, `note` → nothing more. A tool event for a subagent that never started adds no subagent.
- `sessionStateAt(session, now)`: `age = max(0, now - lastAt)`; the live pending entries are those with `now - at` below their wait: `APP_WAIT_MS` when `inApp`, else `CARD_APPROVAL_MS` for an approval and `CARD_QUESTION_MS` for a question (a clock behind `at` counts as live). Name this test a private `liveAsk(entry, now)`; Task 4 uses it too. `state` = `approval` if any live one is an approval, else `question` if any; then `waitingInApp` = any live entry is `inApp`. Else `run === 'working'` → `working` when `age < QUIET_IDLE_MS`, else `idle`; `run === 'finished'` → `finished` when `now - finishedAt < FINISHED_MS`, else `idle`; else `idle` (and `waitingInApp` false). `dim = age >= DIM_MS`, `gone = age >= REMOVE_MS`. A non-object session is `{state: 'idle', dim: false, gone: true, waitingInApp: false}`.
- `projectStateOf(states)`: the earliest of `STATES` present in the list; `idle` when none (non-arrays and unknown words count for nothing).

- [ ] **Step 5: Generate and pass** — as Task 2 Step 5.

- [ ] **Step 6: Commit** — `feat(projects): P-0 registry and time-based states`, the trailer.

---

### Task 4: The view, the pill order, the big card, the waiting count

**Files:**
- Modify: `shared/projects-core.js`, `scripts/gen-projects-fixtures.mjs`
- Create: `tests/projects/view.test.mjs`
- Generated: `tests/fixtures/projects/registry-cases.json`, `tests/fixtures/projects/order-cases.json`

**Interfaces:**
- Consumes: everything from Tasks 1 to 3, including the private `liveAsk(entry, now)` and `registry.home`. `projectCatOf` comes in Task 5: until then the view's `cat` is the placeholder `'shrimpy'` written through a private `catFor(catKey, opts)` that returns `'shrimpy'`; Task 5 changes only that function's body, and Task 5 Step 5 regenerates `registry-cases.json` (its `view` blocks change only in `cat`).
- Produces: `cleanStep(text)`, `projectsView(registry, now, opts)`, `projectOrder(projects)`, `bigCardOf(projects, pinned, clicked)`, `waitingCount(projects)`, with the view shapes of the Interface section.

- [ ] **Step 1: Write `tests/projects/view.test.mjs`**

```js
// (shared test header)
const T = 1760000000000, MIN = 60000;
const brief = v => v.projects.map(p => ({ name: p.name, state: p.state, dim: p.dim, waiting: p.waiting,
  sessions: p.sessions.map(s => `${s.label}:${s.state}${s.dim ? ':dim' : ''}${s.waitingInApp ? ':app' : ''}${s.subagents.length ? ' +' + s.subagents.map(k => k.type).join(',') : ''}`) }));
test('registry-cases.json: every view, and its typed short form', () => {
  for (const c of fx('registry-cases.json').cases) {
    let reg = P.emptyRegistry(c.home);
    for (const s of c.steps) {
      if (s.payload) reg = P.registryApply(reg, P.projectEventFrom(s.payload, s.at));
      else { const v = P.projectsView(reg, s.at, {}); assert.deepEqual(v, s.view, c.name); assert.deepEqual(brief(v), s.expect, c.name); }
    }
  }
});
const o = fx('order-cases.json');
test('projectOrder replays order-cases.json', () => { for (const c of o.order) assert.deepEqual(P.projectOrder(c.projects).map(p => p.id), c.expect, c.name); });
test('bigCardOf replays order-cases.json', () => { for (const c of o.bigCard) assert.deepEqual(P.bigCardOf(c.projects, c.pinned, c.clicked), c.expect, c.name); });
test('waitingCount replays order-cases.json', () => { for (const c of o.waiting) assert.equal(P.waitingCount(c.projects), c.expect, c.name); });
test('cleanStep', () => {
  assert.equal(P.cleanStep('Editing /Users/sam/Code/notchmeow/a.swift'), 'Editing a.swift');
  assert.equal(P.cleanStep('Reading C:\\x\\b.ts now'), 'Reading b.ts now');
  assert.equal(P.cleanStep('  Run   tests  '), 'Run tests');
  assert.equal(P.cleanStep('a/'), 'a'); assert.equal(P.cleanStep('/'), '…');
  assert.equal(P.cleanStep('x'.repeat(100)), 'x'.repeat(79) + '…');
  assert.equal(P.cleanStep(null), ''); assert.equal(P.cleanStep('a\u202Eb'), 'a b');
});
test('project ids carry no path', () => {
  const reg = P.registryApply(P.emptyRegistry(), P.projectEventFrom({ hook_event_name: 'UserPromptSubmit', session_id: 's1', cwd: '/Users/sam/Code/notchmeow' }, T));
  assert.equal(P.projectsView(reg, T).projects[0].id, 'p-39f5156f');
});
test('nothing in the view carries a path, a prompt or a message', () => {
  const A = '/Users/sam/MARKER-GP/Code/notchmeow', B = '/Users/sam/MARKER-GP2/Work/notchmeow';
  const steps = [
    [A, { hook_event_name: 'UserPromptSubmit', prompt: 'MARKER-PROMPT', transcript_path: '/Users/sam/MARKER-TRANSCRIPT.jsonl' }],
    [A + '/.claude/worktrees/wt1', { hook_event_name: 'PermissionRequest', tool_name: 'Bash', tool_input: { command: 'rm /Users/sam/MARKER-CMD' }, session_id: 's2' }],
    [A, { hook_event_name: 'Notification', message: 'Open /Users/sam/MARKER-MSG?' }],
    [A, { hook_event_name: 'SubagentStart', agent_id: 'k1', agent_type: 'MARKER-TYPE/../x' }],
    [B, { hook_event_name: 'UserPromptSubmit', session_id: 's3' }],
    ['/Users/sam/Code/notch\u202Emeow-x', { hook_event_name: 'UserPromptSubmit', session_id: 's4' }],
  ];
  let reg = P.emptyRegistry();
  steps.forEach(([cwd, x], i) => { reg = P.registryApply(reg, P.projectEventFrom({ session_id: 's1', cwd, ...x }, T + i)); });
  const v = P.projectsView(reg, T + 10, { steps: { s1: 'Editing /Users/sam/MARKER-GP/Code/notchmeow/a.swift', s2: 'C:\\Users\\sam\\MARKER-GP\\b.ts' } });
  const json = JSON.stringify(v);
  for (const m of ['MARKER-PROMPT', 'MARKER-TRANSCRIPT', 'MARKER-CMD', 'MARKER-MSG', 'MARKER-GP', 'Users', '\u202E']) assert.ok(!json.includes(m), m);
  const walk = (x, key) => {
    if (typeof x === 'string') { if (key !== 'id') assert.doesNotMatch(x, /[\/\\]/, `${key}: ${x}`); }
    else if (Array.isArray(x)) x.forEach(y => walk(y, key));
    else if (x && typeof x === 'object') for (const [k, y] of Object.entries(x)) walk(y, k);
  };
  walk(v, '');
  assert.deepEqual(v.projects.map(p => p.name).sort(), ['notchmeow — Code', 'notchmeow — Work', 'notchmeow-x']);
});
test('the home folder never reaches the view', () => {
  const H = '/Users/MARKER-HOME';
  let reg = P.emptyRegistry(H);
  [[H, 'h1'], [H + '/Code/notchmeow', 's1'], [H + '/x/Home', 's2'], [H + '/.claude/worktrees/w1', 's3']]
    .forEach(([cwd, sid], i) => { reg = P.registryApply(reg, P.projectEventFrom({ hook_event_name: 'UserPromptSubmit', session_id: sid, cwd }, T + i)); });
  const v = P.projectsView(reg, T + 10, { steps: { h1: 'Editing ' + H + '/notes.md' } });
  assert.ok(!JSON.stringify(v).includes('MARKER-HOME'));
  assert.deepEqual(v.projects.map(p => p.name).sort(), ['Home', 'Home — x', 'notchmeow']);
  assert.deepEqual(v.projects.find(p => p.name === 'Home').sessions.map(s => s.label), ['main', 'w1']);
});
test("a subagent's state follows its live card", () => {
  let reg = P.emptyRegistry('/Users/sam');
  const feed = (dt, x) => { reg = P.registryApply(reg, P.projectEventFrom({ session_id: 's1', cwd: '/Users/sam/Code/notchmeow', ...x }, T + dt)); };
  feed(0, { hook_event_name: 'UserPromptSubmit' });
  feed(100, { hook_event_name: 'SubagentStart', agent_id: 'k1', agent_type: 'Explore' });
  feed(1000, { hook_event_name: 'PermissionRequest', tool_name: 'Bash', agent_id: 'k1' });
  const kitten = dt => P.projectsView(reg, T + dt).projects[0].sessions[0].subagents[0].state;
  assert.equal(kitten(1000 + 119000), 'approval'); assert.equal(kitten(1000 + 121000), 'working');
});
test('a fuzz of 3000 events never throws, keeps the caps and never shows a path', () => {
  let s = 12345; const rnd = n => ((s = (Math.imul(s, 1103515245) + 12345) >>> 0) % n);
  const hooks = ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PermissionRequest', 'Notification', 'Stop', 'StopFailure', 'SubagentStart', 'SubagentStop', 'SessionEnd', 'Bogus'];
  const cwds = ['/Users/sam/Code/a', '/Users/sam/Code/a/sub', '/Users/sam/Code/a/.claude/worktrees/w', '/Users/sam/Code/b', 'C:\\Users\\sam\\c', '', '/', '/Users/sam'];
  let reg = P.emptyRegistry('/Users/sam');
  for (let i = 0; i < 3000; i++) {
    const payload = { hook_event_name: hooks[rnd(hooks.length)], session_id: 's' + rnd(80), cwd: cwds[rnd(cwds.length)], agent_id: rnd(3) ? undefined : 'k' + rnd(12), agent_type: 't/' + rnd(4), tool_name: rnd(5) ? 'Bash' : 'AskUserQuestion', nm_agent: rnd(20) ? undefined : 'claude-desktop', message: rnd(2) ? 'ok?' : 'ok' };
    reg = P.registryApply(reg, P.projectEventFrom(payload, T + i * 1000));
    assert.ok(reg.sessions.length <= 64); assert.ok(reg.sessions.every(x => x.subagents.length <= 8));
  }
  const v = P.projectsView(reg, T + 3000 * 1000);
  assert.ok(!v.projects.some(p => p.name === 'sam'));
  for (const p of v.projects) { assert.doesNotMatch(p.name, /[\/\\]/); for (const x of p.sessions) { assert.doesNotMatch(x.label, /[\/\\]/); x.subagents.forEach(k => assert.doesNotMatch(k.type, /[\/\\]/)); } }
  assert.equal(v.waiting, P.waitingCount(v.projects));
});
```

- [ ] **Step 2: Add the two sections**

```js
// ── registry-cases.json: hook events in, the view out (the typed short form, and the core's full view for the ports) ──
const brief = v => v.projects.map(p => ({ name: p.name, state: p.state, dim: p.dim, waiting: p.waiting,
  sessions: p.sessions.map(s => `${s.label}:${s.state}${s.dim ? ':dim' : ''}${s.waitingInApp ? ':app' : ''}${s.subagents.length ? ' +' + s.subagents.map(k => k.type).join(',') : ''}`) }));
SECTIONS['registry-cases.json'] = () => {
  const cases = [];
  const p = (hook, sid, cwd, x = {}) => ({ hook_event_name: hook, session_id: sid, cwd, ...x });
  const app = { nm_agent: 'claude-desktop' };
  const W = (name, state, sessions, o = {}) => ({ name, state, dim: false, waiting: 0, sessions, ...o });
  // Each step is [dt, payload] or [dt, expect] (an array of W(...) rows: the typed short form of the view at T + dt).
  const seq = (name, steps, home = HOME) => {
    let reg = core.emptyRegistry(home); const out = [];
    for (const [dt, x] of steps) {
      if (!Array.isArray(x)) { reg = core.registryApply(reg, core.projectEventFrom(x, T + dt)); out.push({ at: T + dt, payload: x }); }
      else { const view = core.projectsView(reg, T + dt, {}); expectEqual(`${name} at +${dt}`, brief(view), x); out.push({ at: T + dt, expect: x, view }); }
    }
    cases.push({ name, home, steps: out });
  };
  seq('a worktree session joins its repository as a side session', [[0, p('UserPromptSubmit', 's-main', R)], [1000, p('PreToolUse', 's-side', WT, { tool_name: 'Bash' })], [2000, [W('notchmeow', 'working', ['main:working', 'p0-plan:working'])]]]);
  seq('a subfolder session is matched to the known project', [[0, p('UserPromptSubmit', 's1', R)], [1000, p('UserPromptSubmit', 's2', SUB)], [2000, [W('notchmeow', 'working', ['main:working', 'main · 2:working'])]]]);
  seq('a subfolder session with no known project is its own', [[0, p('UserPromptSubmit', 's1', SUB)], [1000, [W('src', 'working', ['main:working'])]]]);
  seq('a session that moves cwd stays in its first project', [[0, p('UserPromptSubmit', 's1', R)], [1000, p('PreToolUse', 's1', G, { tool_name: 'Read' })], [2000, [W('notchmeow', 'working', ['main:working'])]]]);
  seq('SessionEnd removes the session, and the project with its last session', [[0, p('UserPromptSubmit', 's1', R)], [0, p('UserPromptSubmit', 's2', G)], [1000, p('SessionEnd', 's1', R)], [2000, [W('gracegrip', 'working', ['main:working'])]]]);
  seq('two repositories whose names collide show their parent', [[0, p('UserPromptSubmit', 's1', '/Users/sam/GitHub Local Repos/notchmeow')], [1000, p('UserPromptSubmit', 's2', R)],
    [2000, [W('notchmeow — Code', 'working', ['main:working']), W('notchmeow — GitHub Local Repos', 'working', ['main:working'])]]]);
  seq('quiet 10 min shows idle, 30 min dims, 2 h leaves', [[0, p('UserPromptSubmit', 's1', R)],
    [10 * MIN - 1, [W('notchmeow', 'working', ['main:working'])]], [10 * MIN, [W('notchmeow', 'idle', ['main:idle'])]],
    [30 * MIN - 1, [W('notchmeow', 'idle', ['main:idle'])]], [30 * MIN, [W('notchmeow', 'idle', ['main:idle:dim'], { dim: true })]],
    [120 * MIN - 1, [W('notchmeow', 'idle', ['main:idle:dim'], { dim: true })]], [120 * MIN, []]]);
  seq('Stop shows finished for 5.2 s, then idle', [[0, p('UserPromptSubmit', 's1', R)], [1000, p('Stop', 's1', R)], [6199, [W('notchmeow', 'finished', ['main:finished'])]], [6200, [W('notchmeow', 'idle', ['main:idle'])]]]);
  seq("an open approval outranks a running tool; a subagent's tool event does not end the main session's approval", [[0, p('UserPromptSubmit', 's1', R)],
    [500, p('SubagentStart', 's1', R, { agent_id: 'k1', agent_type: 'Explore' })], [1000, p('PermissionRequest', 's1', R, { tool_name: 'Bash' })],
    [2000, p('PreToolUse', 's1', R, { tool_name: 'Grep', agent_id: 'k1', agent_type: 'Explore' })], [2500, p('PreToolUse', 's2', R, { tool_name: 'Read' })],
    [3000, [W('notchmeow', 'approval', ['main:approval +Explore', 'main · 2:working'], { waiting: 1 })]]]);
  seq('the Claude App mark, and its end at the next tool event', [[0, p('UserPromptSubmit', 's1', R, app)], [1000, p('PermissionRequest', 's1', R, { ...app, tool_name: 'Bash' })],
    [2000, [W('notchmeow', 'approval', ['main:approval:app'], { waiting: 1 })]], [3000, p('PostToolUse', 's1', R, { ...app, tool_name: 'Bash' })], [4000, [W('notchmeow', 'working', ['main:working'])]]]);
  seq('the Claude App mark ends by itself after 10 min', [[0, p('UserPromptSubmit', 's1', R, app)], [1000, p('PermissionRequest', 's1', R, { ...app, tool_name: 'Bash' })],
    [1000 + 10 * MIN - 1, [W('notchmeow', 'approval', ['main:approval:app'], { waiting: 1 })]], [1000 + 10 * MIN, [W('notchmeow', 'idle', ['main:idle'])]]]);
  seq('a question notification from the Claude app, ended by Stop', [[0, p('UserPromptSubmit', 's1', R, app)], [1000, p('Notification', 's1', R, { ...app, message: 'Which file should I use?' })],
    [1500, [W('notchmeow', 'question', ['main:question:app'], { waiting: 1 })]], [2000, p('Stop', 's1', R, app)], [2100, [W('notchmeow', 'finished', ['main:finished'])]]]);
  seq("a notch card approval ends after 120 s, the hook's wait", [[0, p('UserPromptSubmit', 's1', R)], [1000, p('PermissionRequest', 's1', R, { tool_name: 'Bash' })],
    [1000 + 119000, [W('notchmeow', 'approval', ['main:approval'], { waiting: 1 })]], [1000 + 121000, [W('notchmeow', 'working', ['main:working'])]]]);
  seq('a notch card question ends after 130 s', [[0, p('UserPromptSubmit', 's1', R)], [1000, p('PreToolUse', 's1', R, { tool_name: 'AskUserQuestion' })],
    [1000 + 129000, [W('notchmeow', 'question', ['main:question'], { waiting: 1 })]], [1000 + 131000, [W('notchmeow', 'working', ['main:working'])]]]);
  seq('kittens attach to their own session and leave on SubagentStop and Stop', [[0, p('UserPromptSubmit', 's1', R)], [0, p('UserPromptSubmit', 's2', G)],
    [100, p('SubagentStart', 's1', R, { agent_id: 'k1', agent_type: 'Explore' })], [200, p('SubagentStart', 's2', G, { agent_id: 'k2', agent_type: 'general-purpose' })],
    [300, p('SubagentStart', 's1', R, { agent_id: 'k3', agent_type: 'nm-implementer' })],
    [400, [W('notchmeow', 'working', ['main:working +nm-implementer,Explore']), W('gracegrip', 'working', ['main:working +general-purpose'])]],
    [500, p('SubagentStop', 's1', R, { agent_id: 'k1' })], [600, [W('notchmeow', 'working', ['main:working +nm-implementer']), W('gracegrip', 'working', ['main:working +general-purpose'])]],
    [700, p('Stop', 's1', R)], [800, [W('notchmeow', 'finished', ['main:finished']), W('gracegrip', 'working', ['main:working +general-purpose'])]]]);
  const nine = []; for (let i = 1; i <= 9; i++) nine.push([i * 100, p('SubagentStart', 's1', R, { agent_id: 'k' + i, agent_type: 't' + i })]);
  seq('at most 8 kittens per session: the oldest goes', [[0, p('UserPromptSubmit', 's1', R)], ...nine, [1000, [W('notchmeow', 'working', ['main:working +t9,t8,t7,t6,t5,t4,t3,t2'])]]]);
  seq('the order puts a waiting project first, then the most recent', [[0, p('UserPromptSubmit', 's1', R)], [100, p('PermissionRequest', 's1', R, { tool_name: 'Bash' })],
    [5000, p('UserPromptSubmit', 's2', G)], [6000, p('UserPromptSubmit', 's3', SITE)],
    [7000, [W('notchmeow', 'approval', ['main:approval'], { waiting: 1 }), W('site', 'working', ['main:working']), W('gracegrip', 'working', ['main:working'])]]]);
  seq('mains in start order, then side sessions by most recent activity', [[0, p('UserPromptSubmit', 'm1', R)], [100, p('UserPromptSubmit', 'a', R + '/.claude/worktrees/a')],
    [200, p('UserPromptSubmit', 'b', R + '/.claude/worktrees/b')], [300, p('UserPromptSubmit', 'm2', R)], [400, [W('notchmeow', 'working', ['main:working', 'main · 2:working', 'b:working', 'a:working'])]]]);
  seq("another agent's event makes no session", [[0, p('UserPromptSubmit', 'x1', R, { nm_agent: 'codex' })], [1000, []]]);
  seq('a session in the home folder is its own project, named Home', [[0, p('UserPromptSubmit', 'h', HOME)], [100, [W('Home', 'working', ['main:working'])]]]);
  seq('a later session under the home folder is not taken in by Home', [[0, p('UserPromptSubmit', 'h', HOME)], [100, p('UserPromptSubmit', 's1', R)],
    [200, [W('notchmeow', 'working', ['main:working']), W('Home', 'working', ['main:working'])]]]);
  seq('a session under the home folder before any home session works as before', [[0, p('UserPromptSubmit', 's1', R)], [100, p('UserPromptSubmit', 'h', HOME)], [200, p('UserPromptSubmit', 's2', SUB)],
    [300, [W('notchmeow', 'working', ['main:working', 'main · 2:working']), W('Home', 'working', ['main:working'])]]]);
  return { version: 1, note: 'Each case starts from emptyRegistry(home). Each step is a hook payload at a time, or a view at a time: `view` is projectsView(registry, at, {}) as the core gives it (ports compare it whole) and `expect` its typed short form (label:state[:dim][:app] [+subagent types]).', cases };
};

// ── order-cases.json: the pill order, the big card's project, the waiting count ──
SECTIONS['order-cases.json'] = () => {
  const order = [], bigCard = [], waiting = [];
  const od = (name, projects, expect) => { expectEqual(name, core.projectOrder(projects).map(x => x.id), expect); order.push({ name, projects, expect }); };
  od('a waiting project first, then the most recent', [{ id: 'p-a', state: 'working', lastAt: 100 }, { id: 'p-b', state: 'idle', lastAt: 300 }, { id: 'p-c', state: 'question', lastAt: 50 }], ['p-c', 'p-b', 'p-a']);
  od('waiting projects among themselves by most recent', [{ id: 'p-a', state: 'approval', lastAt: 10 }, { id: 'p-b', state: 'question', lastAt: 20 }, { id: 'p-c', state: 'working', lastAt: 30 }], ['p-b', 'p-a', 'p-c']);
  od('the same time: by id', [{ id: 'p-z', state: 'idle', lastAt: 5 }, { id: 'p-y', state: 'idle', lastAt: 5 }], ['p-y', 'p-z']);
  od('nothing', [], []);
  const three = [{ id: 'p-a', lastAt: 100 }, { id: 'p-b', lastAt: 300 }, { id: 'p-c', lastAt: 200 }];
  const bc = (name, projects, pinned, clicked, expect) => { expectEqual(name, core.bigCardOf(projects, pinned, clicked), expect); bigCard.push({ name, projects, pinned, clicked, expect }); };
  bc('no pin, no click: the most recently active', three, null, null, { project: 'p-b', pinned: null, clicked: null });
  bc('the last clicked', three, null, 'p-a', { project: 'p-a', pinned: null, clicked: 'p-a' });
  bc('a pin beats the last click', three, 'p-c', 'p-a', { project: 'p-c', pinned: 'p-c', clicked: 'p-a' });
  bc('a pin goes with its project', three, 'p-gone', 'p-a', { project: 'p-a', pinned: null, clicked: 'p-a' });
  bc('a click on a project that left is forgotten', three, 'p-gone', 'p-gone2', { project: 'p-b', pinned: null, clicked: null });
  bc('a waiting project does not take the card by itself', [{ id: 'p-a', state: 'approval', lastAt: 500 }, ...three.slice(1)], null, 'p-c', { project: 'p-c', pinned: null, clicked: 'p-c' });
  bc('the same time: the first in the list', [{ id: 'p-x', lastAt: 5 }, { id: 'p-y', lastAt: 5 }], null, null, { project: 'p-x', pinned: null, clicked: null });
  bc('no project', [], 'p-a', 'p-b', { project: null, pinned: null, clicked: null });
  const wc = (name, projects, expect) => { expectEqual(name, core.waitingCount(projects), expect); waiting.push({ name, projects, expect }); };
  wc('the sum over projects', [{ waiting: 1 }, { waiting: 0 }, { waiting: 2 }], 3);
  wc('nothing waits', [], 0);
  wc('a count that is not a whole number is nothing', [{ waiting: 'x' }, { waiting: 1.5 }, { waiting: -1 }, { waiting: 2 }], 2);
  return { version: 1, note: 'projectOrder(projects) -> pill order (ids here); bigCardOf(projects, pinned, clicked) -> {project, pinned, clicked}; waitingCount(projects) -> sessions in approval or question.', order, bigCard, waiting };
};
```

- [ ] **Step 3: Run to fail** — `node --test tests/projects/view.test.mjs 2>&1 | grep -E "^# fail"` → FAIL.

- [ ] **Step 4: Implement**

- `cleanStep(text)`: `''` unless a string; `INVISIBLE` characters become spaces; split on whitespace; each word containing `/` or `\` becomes its last non-empty component (`…` when it has none); join with one space; cut to `STEP_MAX` code points (79 + `…`).
- A private `hostOf(session)`: `fromApp` → `claude-app`; else `vscode` when the bundle is not Cursor's and the lower-cased `termProgram` or `bundleId` contains `vscode` (the Mac's `HookOrigin.isVSCode`); else `terminal`.
- `projectsView(registry, now, opts)`: on the clean copy; an `opts` that is not an object counts as `{}`; `opts.steps` (if an object) read with `own` only. Live sessions: `!sessionStateAt(s, now).gone`. Roots in the order of each root's smallest `seq`; names from `projectNames(roots, registry.home)`. Per project: its sessions' `rolesOf`, rows `{id, role, label, state, dim, waitingInApp, note: waitingInApp ? APP_WAIT_LABEL : '', step: cleanStep(steps[id]) or '', host: hostOf(s), lastAt, agoMin: max(0, floor((now - lastAt) / 60000)), subagents}` in `sessionOrder`; `subagents` = those with `now - last < QUIET_IDLE_MS` (a stop that never came hides it after 10 min, like the cat's kittens), as `{id, type, state}` where `state` is `approval` only while the session holds a live pending entry by that subagent (Task 3's `liveAsk`: a timed-out card leaves it `working`), else `working`; an `approval` one first, then by `born` descending, then later in the list first (`kittenOrder`'s rule). The project: `{id: 'p-' + fnv1a(root), name, catKey, cat: catFor(catKey, opts), state: projectStateOf(row states), dim: every row dim, waiting: rows in approval or question, sessionCount, lastAt: max row lastAt, agoMin, step and host of the most recently active row (ties: the larger seq)}`. Projects in `projectOrder`. Result `{projects, waiting: waitingCount(projects), sessionCount: live count, otherAgentSeen}`.
- `projectOrder(projects)`: objects only, a new array; waiting (`approval`/`question`) first, then `lastAt` descending, then `id` ascending.
- `bigCardOf(projects, pinned, clicked)`: objects only; `pinned` and `clicked` kept only if some project has that `id`, else `null`; `project` = kept pin, else kept click, else the largest `lastAt` (ties: the first in the list), else `null`.
- `waitingCount(projects)`: the sum of each `waiting` that is a whole number ≥ 0.

- [ ] **Step 5: Generate and pass** — as Task 2 Step 5; the runner now prints `✓ 5 fixture files match projects-core.js`.

- [ ] **Step 6: Commit** — `feat(projects): P-0 view, pill order, big card and waiting count`, the trailer.

---

### Task 5: Claude only, the layout switch, the project cats

**Files:**
- Modify: `shared/projects-core.js`, `scripts/gen-projects-fixtures.mjs`
- Create: `tests/projects/cats.test.mjs`
- Generated: `tests/fixtures/projects/claude-only-cases.json`, `tests/fixtures/projects/cat-cases.json`; `registry-cases.json` regenerated

**Interfaces:**
- Consumes: Task 4's private `catFor(catKey, opts)`.
- Produces: `claudeOnly(activePills, otherAgentSeen)`, `islandLayout(current, claudeOnlyNow, open)`, `projectCatOf(catKey, projectCats, mainCat) -> {cat, stored}`, `cleanProjectCats(raw)`; `catFor` now returns `projectCatOf(catKey, opts.projectCats, opts.mainCat).cat`.

- [ ] **Step 1: Write `tests/projects/cats.test.mjs`**

```js
// (shared test header)
const Cat = require('../../design/prototype/cat-core.js'), Side = require('../../shared/sidekick-core.js');
const q = fx('claude-only-cases.json'), c = fx('cat-cases.json');
test('claudeOnly replays claude-only-cases.json', () => { for (const x of q.claudeOnly) assert.equal(P.claudeOnly(x.activePills, x.otherAgentSeen), x.expect, x.name); });
test('islandLayout replays claude-only-cases.json', () => { for (const x of q.layout) assert.equal(P.islandLayout(x.current, x.claudeOnly, x.open), x.expect, x.name); });
test('projectCatOf replays cat-cases.json', () => { for (const x of c.cat) assert.deepEqual(P.projectCatOf(x.catKey, x.projectCats, x.mainCat), x.expect, x.name); });
test('cleanProjectCats replays cat-cases.json', () => { for (const x of c.clean) assert.deepEqual(P.cleanProjectCats(x.raw), x.expect, x.name); });
test('cleaning twice is cleaning once', () => { for (const x of c.clean) assert.deepEqual(P.cleanProjectCats(P.cleanProjectCats(x.raw)), x.expect, x.name); });
test('the copies match cat-core.js and sidekick-core.js', () => {
  assert.deepEqual(P.CAT_IDS, Cat.CAT_IDS);
  assert.equal(P.SUBAGENTS_MAX, Cat.KITTEN_MAX);
  const names = ['café', 'Notch Buddy', '', 'x'.repeat(60)]; for (let i = 0; i < 296; i++) names.push('n' + i);
  for (const n of names) {
    assert.equal(P.fnv1a(n), Side.fnv1a(n));
    if (!n) continue;
    for (const main of Cat.CAT_IDS) assert.equal(P.projectCatOf(n, {}, main).cat, Cat.pickCat([main], Cat.rng(parseInt(Side.fnv1a(n), 16)), null), `${n} / ${main}`);
  }
  for (const id of ['integration_claude', 'agent_codex', 'agent_claude-desktop', 'integration_github', 'agent_', 'Agent_X', 'ai_openai', 'agent_gemini-cli', 'constructor'])
    assert.equal(P.claudeOnly([id], false), !(Cat.isAgentPill(id) && id !== 'integration_claude' && id !== 'agent_claude-desktop'), id);
});
test('the view wears the project cat', () => {
  const reg = P.registryApply(P.emptyRegistry(), P.projectEventFrom({ hook_event_name: 'UserPromptSubmit', session_id: 's1', cwd: '/Users/sam/Code/notchmeow' }, 1));
  assert.equal(P.projectsView(reg, 1).projects[0].cat, 'leo');
  assert.equal(P.projectsView(reg, 1, { projectCats: { notchmeow: 'oreo' } }).projects[0].cat, 'oreo');
  assert.equal(P.projectsView(reg, 1, { mainCat: 'leo' }).projects[0].cat, 'cloud');
});
```

- [ ] **Step 2: Add the two sections**

```js
// ── claude-only-cases.json: Claude only, and when the island may switch layout ──
SECTIONS['claude-only-cases.json'] = () => {
  const claudeOnly = [], layout = [];
  const co = (name, activePills, otherAgentSeen, expect) => { expectEqual(name, core.claudeOnly(activePills, otherAgentSeen), expect); claudeOnly.push({ name, activePills, otherAgentSeen, expect }); };
  co('Claude Code and integrations only', ['integration_claude', 'integration_github', 'integration_stripe'], false, true);
  co('another agent pill is declared', ['integration_claude', 'agent_codex'], false, false);
  co('another agent has sent an event', ['integration_claude'], true, false);
  co('nothing declared, nothing seen', [], false, true);
  co('the Claude app pill counts as Claude', ['integration_claude', 'agent_claude-desktop'], false, true);
  co('a list that is not a list, a flag that is not true', 'agent_codex', 'yes', true);
  co('IDs that are not agent pills', ['agent_', 'Agent_X'], false, true);
  const ly = (name, current, claudeOnlyNow, open, expect) => { expectEqual(name, core.islandLayout(current, claudeOnlyNow, open), expect); layout.push({ name, current, claudeOnly: claudeOnlyNow, open, expect }); };
  ly('folded: it switches to project pills', 'agents', true, false, 'projects');
  ly('open: it waits until the island folds', 'agents', true, true, 'agents');
  ly('open: project pills stay while the owner looks', 'projects', false, true, 'projects');
  ly('folded: back to agent pills', 'projects', false, false, 'agents');
  ly('no layout yet: decided now, even open', null, true, true, 'projects');
  return { version: 1, note: 'claudeOnly(activePills, otherAgentSeen) -> true when no agent pill but Claude Code is declared and no other agent has sent an event; islandLayout(current, claudeOnlyNow, open) -> projects | agents, changing only while folded.', claudeOnly, layout };
};

// ── cat-cases.json: a project's cat, the clean-up of stored project cats ──
SECTIONS['cat-cases.json'] = () => {
  const cat = [], clean = [];
  const pc = (name, catKey, projectCats, mainCat, expect) => { expectEqual(name, core.projectCatOf(catKey, projectCats, mainCat), expect); cat.push({ name, catKey, projectCats, mainCat, expect }); };
  pc('no stored choice: picked from the name', 'notchmeow', {}, 'shrimpy', { cat: 'leo', stored: false });
  pc('a stored choice', 'notchmeow', { notchmeow: 'momo' }, 'shrimpy', { cat: 'momo', stored: true });
  pc('an unknown stored coat falls back to the pick', 'notchmeow', { notchmeow: 'tiger' }, 'shrimpy', { cat: 'leo', stored: false });
  pc('the Main cat is never picked', 'notchmeow', {}, 'leo', { cat: 'cloud', stored: false });
  pc('another name', 'site', {}, 'shrimpy', { cat: 'latte', stored: false });
  pc('an alias name', 'Notch Buddy', {}, 'shrimpy', { cat: 'button', stored: false });
  pc('a name with an accent is hashed as UTF-8', 'café', {}, 'shrimpy', { cat: 'snow', stored: false });
  pc('an unknown Main cat is Shrimpy', 'notchmeow', {}, 'nonsense', { cat: 'leo', stored: false });
  pc('an empty key wears the Main cat', '', {}, 'momo', { cat: 'momo', stored: false });
  pc('a key that is not text wears the Main cat', 3, {}, 'momo', { cat: 'momo', stored: false });
  pc('stored cats that are a list count for nothing', 'notchmeow', ['momo'], 'shrimpy', { cat: 'leo', stored: false });
  const cl = (name, raw, expect) => { expectEqual(name, core.cleanProjectCats(raw), expect); clean.push({ name, raw, expect }); };
  cl('good entries, in code-unit order', { site: 'oreo', notchmeow: 'momo' }, { notchmeow: 'momo', site: 'oreo' });
  cl('__proto__ and constructor are dropped', JSON.parse('{"__proto__":"momo","constructor":"momo","prototype":"momo"}'), {});
  cl('unknown coats are dropped', { a: 'tiger', b: 3, c: null }, {});
  cl('a key with a slash or a backslash is dropped', { 'a/b': 'momo', 'a\\b': 'momo' }, {});
  cl('60 code points is kept, 61 is dropped, empty is dropped', { ['k'.repeat(60)]: 'momo', ['k'.repeat(61)]: 'momo', '': 'momo' }, { ['k'.repeat(60)]: 'momo' });
  cl('a key with a control character is dropped', { 'a\u0007b': 'momo' }, {});
  cl('not an object', ['momo'], {});
  cl('null', null, {});
  const many = {}, kept = {}; for (let i = 0; i < 300; i++) many['k' + String(i).padStart(3, '0')] = 'momo';
  for (let i = 0; i < 256; i++) kept['k' + String(i).padStart(3, '0')] = 'momo';
  cl('at most 256, the first in code-unit order', many, kept);
  return { version: 1, note: 'projectCatOf(catKey, projectCats, mainCat) -> {cat, stored}: the stored coat, else pickCat([main], rng(fnv1a(catKey)), null) as cat-core.js picks; cleanProjectCats(raw) -> at most 256 {catKey: catId}.', cat, clean };
};
```

- [ ] **Step 3: Run to fail** — `node --test tests/projects/cats.test.mjs 2>&1 | grep -E "^# fail"` → FAIL.

- [ ] **Step 4: Implement**

- `claudeOnly(activePills, otherAgentSeen)`: `false` when `otherAgentSeen === true`; else `false` when the list (an array, else `[]`) holds an **other agent pill**: an ID matching `/^[a-z][a-z0-9_-]{1,63}$/`, not `constructor` or `prototype`, that is `integration_claude` or starts with `agent_` and is longer than 6 characters (cat-core's `isAgentPill`), and is neither `integration_claude` nor `agent_claude-desktop`; else `true`.
- `islandLayout(current, claudeOnlyNow, open)`: when `open === true` and `current` is `'projects'` or `'agents'`, `current`; else `claudeOnlyNow === true ? 'projects' : 'agents'`.
- A private `rng(seed)`: copy cat-core's line 31 exactly: `function rng(seed){let s=seed>>>0;return()=>((s=(Math.imul(s,1103515245)+12345)>>>0)/4294967296)}`.
- A private `isCatKey(k)`: a non-empty string of at most `NAME_MAX` code points, with no `/`, no `\`, no `INVISIBLE` character (test with a non-global copy of the class, or reset `lastIndex`), not `__proto__`, `constructor` or `prototype`.
- `cleanProjectCats(raw)`: `{}` unless a plain object; its own keys that pass `isCatKey`, sorted with the default `.sort()` (UTF-16 code units), whose value is in `CAT_IDS`; at most `PROJECT_CATS_MAX` of them. Build the result with plain assignment on `{}` after the key checks (so no prototype key can land).
- `projectCatOf(catKey, projectCats, mainCat)`: `main` = `mainCat` if in `CAT_IDS`, else `'shrimpy'`. Not `isCatKey(catKey)` → `{cat: main, stored: false}`. A cleaned stored coat for `catKey` → `{cat, stored: true}`. Else `free = CAT_IDS.filter(c => c !== main)`, `r = rng(parseInt(fnv1a(catKey), 16))()` (called once), `cat = free[Math.min(free.length - 1, Math.max(0, Math.floor(r * free.length)))]`, `stored: false`. Nothing is ever stored by this function (a project's cat is stored only when the owner picks one in Settings, spec call 10).
- `catFor(catKey, opts)` (Task 4) now returns `projectCatOf(catKey, opts.projectCats, opts.mainCat).cat`.

- [ ] **Step 5: Generate and pass** — `node scripts/gen-projects-fixtures.mjs && bash scripts/test-projects-contract.sh 2>&1 | grep -E "^# fail|✓ 7|✓ two"` → `# fail 0`, `✓ 7 fixture files match projects-core.js`, `✓ two generator runs write identical bytes`. `git diff --stat tests/fixtures/projects/registry-cases.json` shows it changed (the `cat` fields only: `git diff tests/fixtures/projects/registry-cases.json | grep '^[-+] ' | grep -vc '"cat":"'` prints `0`).

- [ ] **Step 6: Commit** — the files above with `registry-cases.json`; `feat(projects): P-0 Claude only, layout switch and project cats`, the trailer.

---

### Task 6: The owner's tables (owner checkpoint)

**Files:**
- Create: `scripts/print-projects-tables.mjs`, `tests/projects/print.test.mjs`

**Interfaces:**
- Consumes: the core's exports and `tests/fixtures/projects/registry-cases.json`. Writes nothing.

- [ ] **Step 1: Write `tests/projects/print.test.mjs`**

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
test('the tables print and name the numbers', () => {
  const out = execFileSync(process.execPath, [fileURLToPath(new URL('../../scripts/print-projects-tables.mjs', import.meta.url))], { encoding: 'utf8' });
  for (const h of ['== 1. The numbers', '== 2. A session as it ages', '== 3. Sample timelines', '== 4. A project\'s cat']) assert.ok(out.includes(h), h);
  for (const s of ['10 min', '30 min', '2 h', '5.2 s', '120 s', '130 s', 'Waiting in Claude App', 'main · 2', 'p0-plan', 'Home']) assert.ok(out.includes(s), s);
  assert.doesNotMatch(out, /\/Users\//);
});
```

- [ ] **Step 2: Run to fail** — `node --test tests/projects/print.test.mjs 2>&1 | grep -E "^# fail"` → FAIL.

- [ ] **Step 3: Write `scripts/print-projects-tables.mjs`**

Header and imports in the style of `scripts/print-sidekick-tables.mjs` (a comment saying it prints the rules for the owner and writes nothing; `createRequire` of `../shared/projects-core.js`; a `head(t)` printing `` `\n== ${t} ` `` padded with `=`). Four sections:

1. `The numbers`: one line each: quiet → idle `10 min`, dim `30 min`, gone `2 h`, finished `5.2 s`, Claude App mark `10 min` with `APP_WAIT_LABEL`, a notch card's approval `120 s` and question `130 s` (`` `${P.CARD_APPROVAL_MS / 1000} s` ``), the home folder's project name `HOME_NAME`, peek `0.4 s`, label refresh `1 min`, `8` subagents per session, `64` sessions. Print each value from the constant (e.g. `` `${P.QUIET_IDLE_MS / 60000} min` ``, `` `${P.FINISHED_MS / 1000} s` ``, `` `${P.REMOVE_MS / 3600000} h` ``).
2. `A session as it ages`: for a working session (`run: 'working'`) and a finished one, `sessionStateAt` at 0 s, 5.1 s, 5.2 s, 9 min 59 s, 10 min, 29 min 59 s, 30 min, 1 h 59 min 59 s, 2 h: a column per session with `state`, plus `dim` and `gone` when true.
3. `Sample timelines`: for every case of `registry-cases.json`, its name, then for each view step `+<seconds>s` and, per project, `name [state] waiting N: label:state, …` (the same short form as the tests' `brief`).
4. `A project's cat`: for `notchmeow`, `gracegrip`, `site`, `Notch Buddy`, `Home`: the cat with Main cat Shrimpy, and with Main cat Leo.

- [ ] **Step 4: Pass** — `node --test tests/projects/*.test.mjs 2>&1 | grep -E "^# fail"` → `# fail 0`; `node scripts/print-projects-tables.mjs | head -30` reads cleanly.

- [ ] **Step 5: Commit** — `feat(projects): P-0 the owner's tables`, the trailer.

- [ ] **Step 6: Owner checkpoint.** The controller saves `node scripts/print-projects-tables.mjs` to the ledger folder, sends it to the main session and waits. A change the owner asks for is one edit in the core plus the typed answer beside its case, regenerated, in its own commit, before Task 7.

---

### Task 7: Docs, CI, pointers and the final checks

**Files:**
- Create: `docs/PROJECTS-CONTRACT.md`
- Modify: `shared/projects-core.js` (remove `// @@NEXT`), `scripts/gen-projects-fixtures.mjs` (remove `// @@SECTIONS`), `.github/workflows/build.yml`, `CLAUDE.md`, `ARCHITECT.md`

- [ ] **Step 1: Remove the two marker lines** (each with the blank line after it, if any). `grep -c "@@" shared/projects-core.js scripts/gen-projects-fixtures.mjs` → `0` for both; `bash scripts/test-projects-contract.sh | tail -2` still green.

- [ ] **Step 2: Write `docs/PROJECTS-CONTRACT.md`**

In the style of `docs/SIDEKICK-CONTRACT.md`. Sections, in order:
1. Title `# The Projects contract (sub-project P-0)`, a paragraph on what the rules are for, the spec's path, and "**`shared/projects-core.js` decides**": pure, the one source of truth; if an app and a fixture disagree, the app is wrong.
2. `## Files`: the table of the File Structure above (core, generator, fixtures, tests, runner, tables), and the ports: Swift `Projects*.swift` (P-mac) and the generated TypeScript copy (P-tauri) replay the same files.
3. `## What never leaves memory, and what is never kept`: the registry holds a session's full `cwd`, and the home folder the app gave it (`registry.home`), in memory only, never shown, logged or stored; the home folder's project shows only `Home`; events and the registry hold no prompt, `transcript_path`, tool input or output, message or assistant text; display fields (names, labels, steps, types, notes) never carry `/` or `\`; a project's id is `p-` + FNV-1a of the root; the only stored thing is a project's cat, keyed by its `catKey` (the folder name through the alias table, without the collision suffix: spec call 9), as `cat.projectCat.<catKey>` on the Mac and `projectCats` in the `cat` block on Windows/Linux. Pins, the last click and the expanded state live in app memory (spec call 5).
4. `## The rules`: one `###` per export of the Interface table, its signature, the shape it returns (keys in order), the fixture file that pins it, and its rules in a few lines (taken from Tasks 1 to 5 Step "Implement"). Include the constants table with values. For `projectEventFrom` give the event-name table. For `projectsView` say what each view field is for (the big card: the first-ordered project's fields are NOT the card; `bigCardOf` decides it).
5. `## Decisions where the spec was silent` — each with the case that pins it:
   - A session's root is fixed when it enters; a later session at a parent folder does not merge an earlier subfolder project, and a session never moves project ("a session that moves cwd stays in its first project").
   - A worktree in a worktree: the repository is before the first `/.claude/worktrees/`, the name after the last.
   - Prefix matching is by whole segments (`notchmeow-old` is not inside `notchmeow`); `/` and a bare drive match only themselves; `\` is `/`, repeated and trailing `/` fold, a drive letter is upper-cased; letter case is otherwise kept.
   - Colliding names: the parent folder, then ` · 2`, ` · 3` in first-seen order; names lose control and invisible characters and are cut at 60 code points; an empty name is `Session`.
   - Roles: mains numbered among live sessions in start order (`main`, `main · 2`); two sessions in one worktree are `name`, `name · 2`.
   - Waiting is kept per asker (the main agent or one subagent): a tool event ends only its own asker's; `UserPromptSubmit`, `Stop`, `StopFailure`, `Interrupt` and `SessionEnd` end all. An ask also ends by itself (rule 4): after 10 min from the Claude App; otherwise after 120 s for an approval and 130 s for a question, the installed hooks' own waits, and every non-App question counts as a card's (a question notification included). A subagent whose ask ended so shows `working`. The session then shows what its run says (usually `working` until 10 min quiet).
   - The home folder (owner, 2026-10-17): its own project `Home`, never a root another session joins; a worktree of a repository at the home folder joins Home; Home takes no collision suffix (another folder named `Home` shows its parent); with no home given (empty) the plain rule applies, so the apps always give it.
   - `StopFailure` and `Interrupt` end work as `idle`, not `finished`.
   - A Claude event with no session id, or a new session's event with no `cwd`, is ignored; another agent's event (Codex, Cursor, any valid `nm_agent` but `claude` and `claude-desktop`) only sets `otherAgentSeen`; `claude-desktop` is Claude Code with `fromApp`; `agent_claude-desktop` in Active pills counts as Claude.
   - Caps: 64 sessions (the least recently active goes), 8 subagents per session (the oldest start goes), ids cut at 128 code points, subagent types at 64 with `/` and `\` turned into `-`. A subagent with no event for 10 min is not shown.
   - A step's word that holds a `/` or `\` is shown as its last component; steps are cut at 80 code points (the view cuts further to the row).
   - A project's cat: the stored coat, else `pickCat([main], rng(fnv1a(catKey)), null)`, so it avoids the Main cat and is the same on every launch while the Main cat is unchanged; a key that is not a valid cat key wears the Main cat; the function never stores.
   - `projects-core.js` copies `CAT_IDS`, `rng`, the pick, the agent-pill test, `fnv1a`, the invisible class and the alias table rather than loading `cat-core.js`; `tests/projects/cats.test.mjs` pins every copy.
6. `## Known limits`: Claude Code started in a parent folder other than the home folder (`~/Code`) takes in every later session under it and shows that folder's name (rule 1 as written; "another parent folder still takes in sessions under it"); paths are compared as text (no symlink or letter-case folding on Windows beyond the drive); a session whose window closed without `SessionEnd` stays up to 2 h (dimmed from 30 min); the time-based states move only when the island reads the registry (no timer: spec).
7. `## Changing it`: change the core and the typed answer beside its case, run `node scripts/gen-projects-fixtures.mjs`, commit the fixtures with the core; a new state word, role, host or layout may be added, none renamed; once an app reads these files, change them only by addition.

- [ ] **Step 3: CI.** In `.github/workflows/build.yml`, right after the two lines of the step `- name: Sidekick contract (sidekick-core.js tests, fixtures, determinism)` (its `run:` line included), add with the same indentation:

```yaml

      - name: Projects contract (projects-core.js tests, fixtures, determinism)
        run: bash scripts/test-projects-contract.sh
```

- [ ] **Step 4: `CLAUDE.md`.** Right after the bullet that starts with ``- `shared/sidekick-core.js` — the agent sidekick's rules``, add this bullet:

```markdown
- `shared/projects-core.js` — the Projects rules (sub-project P-0): which project and role a Claude Code session has (`projectOf`, `projectNames`, `rolesOf`, `sessionOrder`), the hook adapter and the memory-only session registry (`projectEventFrom`, `emptyRegistry`, `registryApply`, `registryPrune`), the time-based states (`sessionStateAt`, `projectStateOf`: 10 min quiet → idle, 30 min dim, 2 h gone, 5.2 s finished, the Claude App mark's 10 min, a notch card's 120 s approval and 130 s question), the home folder as its own project "Home" (`emptyRegistry(home)`), the view the island draws (`projectsView`, `cleanStep`), the pill order, the big card and the waiting count (`projectOrder`, `bigCardOf`, `waitingCount`), Claude only and the layout switch (`claudeOnly`, `islandLayout`) and a project's cat (`projectCatOf`, `cleanProjectCats`, picked like `agentCatFor`). Pure, shared by Node and the apps' tests. `node scripts/gen-projects-fixtures.mjs` writes `tests/fixtures/projects/` from it (`--check` fails on drift), `bash scripts/test-projects-contract.sh` runs the lot, `node scripts/print-projects-tables.mjs` prints the rules as tables, and `docs/PROJECTS-CONTRACT.md` documents them. If an app and a fixture disagree, `projects-core.js` decides. A session's full `cwd` stays in memory; nothing displayed carries a `/`-path. The Mac and Windows/Linux ports are P-mac and P-tauri.
```

- [ ] **Step 5: `ARCHITECT.md`.** Insert, just before the line `## Code map (graphify)` and after one blank line, this paragraph (it continues the numbered list of "Main flows"):

```markdown
7. **Projects (sub-project P).** Every Claude Code project with a live session, its main and side sessions and their subagents, from the hook events both apps already receive: the island's project pills (Claude only) or the expandable Claude panel (with other agents), the Projects screen, the peek and the compact waiting count. The rules are `shared/projects-core.js` (P-0: pure, memory-only registry, tested against `tests/fixtures/projects/`, `docs/PROJECTS-CONTRACT.md`); the Mac port and views are P-mac, the Windows/Linux generated copy and views P-tauri. A session's full `cwd` never leaves memory; only folder names, worktree names, roles and step words are shown; a project's cat is stored by its folder name.
```

- [ ] **Step 6: Final checks**

```bash
bash scripts/test-projects-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓ 7|✓ two"
bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "^# fail"
bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# fail"
bash scripts/check-no-leftovers.sh | tail -1
git diff --quiet main -- design shared/sidekick-core.js shared/theme.json tests/fixtures/cat tests/fixtures/sidekick tests/fixtures/shelf tests/fixtures/link tests/fixtures/ai tests/fixtures/mac && echo "untouched"
git diff --stat main...HEAD -- NotchBuddy windows | tail -1
grep -rhoE '/Users/[^/"]+' tests/fixtures/projects | sort -u
```

Expected: `# fail 0` and `✓ 7 fixture files match projects-core.js`, `✓ two generator runs write identical bytes`; `# fail 0`; `# fail 0`; the leftovers check green; `untouched`; no line for `NotchBuddy windows`; only `/Users/sam`.

- [ ] **Step 7: Commit** — the seven files; `docs(projects): P-0 contract document, CI step and pointers`, the trailer. Then the controller dispatches `nm-reviewer-deep` over `git diff main...HEAD`.

---

## Spec coverage (self-review)

| Spec item | Where |
|---|---|
| Rule 1 project of a session (worktree, subfolder, no `.git` read, the home folder as "Home", display name, collisions) | Task 1 (`projectOf`, `projectNames`, the home cases), Task 3 (root fixed at entry, `emptyRegistry(home)`), Task 4 cases and "the home folder never reaches the view" |
| Rule 2 role (`main`, `main · 2`, side) | Task 1 `rolesOf`, Task 4 cases |
| Rule 3 session state, 10 min quiet, 5.2 s finished, approval outranks | Task 3 `sessionStateAt`, `state-cases.json`, Task 4 cases |
| Rule 4 Claude App mark, its end events and 10 min, the label; a notch card's 120 s approval and 130 s question | Tasks 2 to 4 (`fromApp`, `inApp`, `APP_WAIT_LABEL`, `CARD_APPROVAL_MS`, `CARD_QUESTION_MS`, `liveAsk`, the state cases at 119/120/121 s and 129/130/131 s, four registry cases, "a subagent's state follows its live card") |
| Rule 5 project state | Task 3 `projectStateOf` |
| Rule 6 subagents, at most 8, leave on Stop and SessionEnd | Task 3 (`subStart`, `subStop`, `stop`, `end`), Task 4 cases |
| Rule 7 lifetime, 30 min dim, 2 h removal, project leaves, pin goes | Task 3 `registryPrune`, Task 4 (`projectsView`, `bigCardOf`) |
| Rule 8 pill order and order inside a project | Task 1 `sessionOrder`, Task 4 `projectOrder` |
| Rule 9 big card (pin, last click, most recent; waiting doesn't take it) | Task 4 `bigCardOf` |
| Rule 10 waiting count | Task 4 `waitingCount`, `view.waiting` |
| Rule 11 Claude only; switch only while folded | Task 5 `claudeOnly`, `islandLayout` |
| Rule 12 a project's cat, stored choice cleaned | Task 5 `projectCatOf`, `cleanProjectCats` |
| No timer; one-minute label refresh | constants `AGO_TICK_MS`; `agoMin` in the view; every rule takes `now` |
| Peek 0.4 s | constant `PEEK_DWELL_MS` |
| Fixture list (14 items) | worktree P2/registry 1; subfolder P4–P5/registry 2–3; collision names 2/registry 6; spaces P9; moves cwd registry 4; SessionEnd registry 5; ages registry 7, state 1–8; approval outranks registry 9, state 9; App mark and end registry 10–12 (card waits registry 13–14); kittens registry 15–16; order with waiting registry 17, order 1–2; the home folder registry 20–22; big card with/without pin order bigCard; Claude only with/without another agent claude-only 1–3; cat with/without stored cat 1–2 |
| Call 1 (paths in memory, leak pin) | Global Constraints; Task 2, 3 and 4 leak tests |
| Call 2 (sidekick pattern, generated fixtures) | the whole plan |
| Calls 5, 6, 7, 8, 9 | docs section 3 and decisions; `bigCardOf`; `claudeOnly`; `catKey` |
