# F1-0 Sidekick Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give both apps what sub-project F1 (the agent sidekick) needs from the shared contract before the app plans run: the sidekick's rules written once in a pure JavaScript module, `shared/sidekick-core.js`, and pinned by ten JSON fixtures under `tests/fixtures/sidekick/` that a generator writes from it. The rules are the risk label under a permission request (`explain`), the hook adapter and the session ledger (`eventFrom`, `ledgerApply`), the stuck nudges (`stuckStep`), the recap, the status answer and the question matcher (`recapOf`, `statusOf`, `matchStatusQuestion`), dismissal memory and the stored settings (`dismiss`, `muted`, `unmute`, `cleanSidekickSettings`), away detection (`presenceStep`), the show gate (`shouldShow`) and the local voice's sanity check (`acceptNicerLine`). The apps use none of it yet: those are the F1-mac and F1-tauri plans.

**Architecture:** This contract has the shape of the cat contract (sub-projects B and H), because the spec chose it: one pure module that loads in Node and in a page (`shared/sidekick-core.js`, beside `theme.json`), and `scripts/gen-sidekick-fixtures.mjs`, which writes `tests/fixtures/sidekick/*.json` from it, with `--check` (fail on drift) and `--out DIR` (the runner writes twice to prove the bytes are identical). The difference from the cat contract is where the truth of each case lives: every case in the generator lists its input and, **typed by hand beside it**, the answer it must get, and the generator stops if the core disagrees. So a fixture is never just a copy of what the core says. Each task adds one rule to the core at a marker line, one section to the generator at another, and the tests for them; nothing existing is edited except at those markers. `scripts/test-sidekick-contract.sh` runs the tests, the no-drift check and the determinism check; CI runs it. `docs/SIDEKICK-CONTRACT.md` documents the rules and the decisions this plan makes where the spec is silent. **It changes no pixel and no behaviour in either app.**

**Tech Stack:** JavaScript (CommonJS module, Node 22 ES-module scripts), `node:test`, Bash, JSON. Node standard library only.

**Spec:** `docs/superpowers/specs/2026-10-14-agent-sidekick-design.md`, sections "Risk rules", "The ledger", "Stuck rules", "Away and recap", "What's Claude doing?", "Dismissal memory", "The show gate", "The local voice", "Storage" and "Contract". Read the whole spec before starting. This plan implements only F1-0; F1-mac, F1-tauri and the prerequisite plan (`2026-10-14-mac-all-terminals.md`) are other plans.

**Base:** branch `f1-0/sidekick-contract`, created from `notchmeow/rebrand` at `793b502` or later, with this plan file and the spec already committed to `notchmeow/rebrand`. This plan touches no app code under `NotchBuddy/` or `windows/`, no `design/prototype/` file and no existing fixture.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec; the lines marked "(plan decision)" are choices this plan makes where the spec is silent, and are listed in `docs/SIDEKICK-CONTRACT.md`.

- **The sidekick labels and remembers.** It never blocks, allows or denies anything; only the user's click does. `explain` returns a label and a line, nothing else.
- **What it keeps (spec "The ledger"):** a basename (`project` is the basename of `cwd`), a command key (a hash), counts and times. **Never** the prompt, the assistant's text, `transcript_path`, a tool's output, a command, a full path or a file's content. Every line carries a basename, a count, an agent's name or a number of minutes and nothing else. Tests plant a marker in each of those inputs and assert it never comes out.
- **Ledger limits (spec):** a ring of the last **40** entries per session; at most **8** sessions, a finished one going first, the oldest first; a session ends at `SessionEnd` plus **30 minutes**, or **12 hours** after its last event when it never ended; memory only.
- **Stuck thresholds (spec):** the same step **4** times in the last **8** calls within **10 minutes** with no successful edit or write after the first; **3** failures in a row within 10 minutes (Claude Code only); a request unanswered **60 s** with its card off screen (the Mac gives up at **115 s**, Windows at **110 s**); quiet **5 minutes** after a finished step, prompt or subagent stop and **15 minutes** after a step that began and never ended, never while a helper is under **10 minutes** old; once per session; never while away or in the rate-limit state.
- **Dismissals (spec):** five frozen kinds `recap`, `stuck.loop`, `stuck.errors`, `stuck.waiting`, `stuck.silent`; two dismissals mute a kind; Unmute sets it to 0; the risk badge and the line are never muted; counts are 0 to 2.
- **Away (spec):** lock, sleep, screen off, or **300 s** idle; back when the last reason ends; a recap needs at least **2 minutes** away; a note is held **30 s** (a recap **2 minutes**); a note at most every **60 s**.
- **Local voice (spec):** a sentence replaces a template only if it is one line of at most **200** characters, with no URL, `/`, `\`, backtick or markdown, only numbers from the facts, and the agent's name.
- **Frozen values.** The five dismissal kinds and the reason IDs are contract values: a reason may be added, none is renamed. Pill IDs and cat IDs are untouched. **Only new files.** `tests/fixtures/cat/`, `tests/fixtures/ai/`, `tests/fixtures/mac/`, `design/prototype/` and `shared/theme.json` stay byte for byte (`node scripts/check-fixtures-additive.mjs 793b502` and `git diff --quiet 793b502 -- ...` must pass). The only existing files edited are `.github/workflows/build.yml` (one step), `CLAUDE.md` and `ARCHITECT.md` (one bullet each) and the spec (its F1-0 lines).
- **Node standard library only; no npm package, no new dependency.** The fixtures hold whole numbers, text, booleans and null only.
- **No telemetry, no network, nothing outside the repository.** The scripts read and write only `tests/fixtures/sidekick/` (and print to the terminal).
- **Nothing of Coucou's comes back, and the names Coucou and Mochi appear in no new file.** `scripts/check-no-leftovers.sh` must stay green.
- **Commits:** local only, never pushed. End every commit message with `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>` when a Haiku agent wrote it, or `Claude Sonnet 5.5` when an `nm-implementer-deep` did.

## SUBAGENT RULES

Every subagent and the controller follow these; the controller puts them in each brief.

- **Never launch, quit or replace a NotchMeow app or the Tauri app.** The work is files and Node.
- **Install and download nothing.** No `npm install`, no network.
- **Delete with `trash`, never `rm -rf`,** and give scratch files unique names (the prefix `f10-`, in `${TMPDIR:-/tmp}`). (`scripts/test-sidekick-contract.sh` removes its own `mktemp` folders with `rm -rf` in a `trap`, as `scripts/test-cat-contract.sh` does: that is the repo's convention, not a command an agent runs.)
- **Never run the real `claude` binary, never read tokens, never sign in, never read the real `~/.claude`, `~/.gemini` or `~/.codex`.**
- **Never write to `~/Library/Logs/NotchMeow/` or to an app's preferences.** Nothing in this plan touches `UserDefaults`.
- **No Coucou or Mochi names.**
- **Commit only in a task's commit step, and never push.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder, the second `f1-0/sidekick-contract`. If either is wrong, stop and report.
- **Never edit an existing fixture, `cat-core.js` or `gen-cat-fixtures.mjs`.**
- **Subagents are the `nm-*` agents** (Haiku 5.5 first; Sonnet 5.5 only on a named CLAUDE.md trigger; never Opus or Fable). The table below says which one runs each task.
- **If a command is denied by a permission prompt, stop and report it. Do not look for a workaround.**
- **If a `find` text of an edit step is not found exactly once, stop and report.** Do not edit the anchor. **If the generator stops with "the core says X, the case says Y", stop and report:** a typed answer and the core disagree, and which one is right is a design question.

## Review Focus

The spec says what the rules are. It is silent on these inputs, and each would bite a person (or a port) first, most likely first. Each line names its test.

1. **A permission request that hides its danger:** a risky command behind `cd x &&`, `env VAR=1`, `sudo` or `time`; inside `bash -c "..."`; as a redirect into a dotfile (`echo x >> ~/.zshrc`); with the dangerous word only in quotes (`echo "rm -rf /"`, which is not dangerous); as `rm -rf .`; piped (`curl ... | sudo bash`); a path that climbs out of the project and back (`src/../../other`); a sibling folder with the same prefix (`proj-old`); a Windows path in another letter case; a 100,000-character command; unbalanced quotes. Expected: the highest risk of the parts, `unsure` for what can't be read, never a throw. Tests: Task 1 (the near-miss rows, "hostile input never throws", the 3000-input fuzz).
2. **Something secret reaching a line, an event, the ledger, a recap or a status:** a marker in a command, a prompt, a parent folder, a tool's output, a file's content, an assistant message and a transcript path. Expected: the marker is in none of them. Tests: Task 1 ("a line never carries the command, a path or an argument"), Task 2 ("nothing secret reaches an event or the ledger"), Task 4 ("no command, path, prompt or message reaches a recap or a status").
3. **A nudge that fires when it should not:** after the turn ended, while a question waits, while a helper is young, with a notification as the last event, for a session that was nudged, on a second session, with the card on screen, while away, in the rate-limit state. Expected: nothing, or one nudge per session. Tests: Task 3 (the timelines and the 6000-probe fuzz).
4. **A hostile or growing ledger:** session ids such as `__proto__`, `constructor` or `toString`, a 50-entry burst, ten sessions, a session that comes back after it ended, events out of order. Expected: caps hold, keys are unique, nothing lands on `Object.prototype`. Tests: Task 2 ("hostile ids and names", "the ring keeps the last 40", "only eight sessions", the 4000-event fuzz).
5. **Stored settings from a damaged or newer file:** `dismissals` as a list, counts of `-3`, `1.5`, `"2"`, `9`, unknown kinds, an `__proto__` key, switches that are text. Expected: switches on, counts 0 to 2, unknown things dropped, cleaning twice is cleaning once. Tests: Task 5 (every row of `settings-cases.json` and the 3000-value fuzz).

---

## File Structure

| Path | Responsibility |
|---|---|
| `shared/sidekick-core.js` | The rules. Grown a section per task at the marker `// @@NEXT`; Task 8 removes the marker. |
| `scripts/gen-sidekick-fixtures.mjs` | Writes the ten fixture files; every case types its answer by hand. Grown a section per task at the marker `// @@SECTIONS`; Task 8 removes it. |
| `tests/sidekick/*.test.mjs` | The rules' own tests (`node --test`): one file per rule group. |
| `tests/fixtures/sidekick/*.json` | `explain-cases`, `hook-cases`, `stuck-cases`, `recap-cases`, `status-cases`, `dismiss-cases`, `settings-cases`, `presence-cases`, `show-cases` and `voice-cases` (generated, about 210 KB in all). |
| `scripts/test-sidekick-contract.sh` | Runs the tests, the no-drift check and the determinism check. CI runs it. |
| `scripts/print-sidekick-tables.mjs` | Prints the rules as tables for the owner's checkpoint (Task 7). |
| `docs/SIDEKICK-CONTRACT.md` | The document the app plans cite: the rules, the shapes, the decisions, the known limits. |
| `.github/workflows/build.yml` | One step after "Cat contract". |
| `CLAUDE.md`, `ARCHITECT.md` | One bullet each. |
| `docs/superpowers/specs/2026-10-14-agent-sidekick-design.md` | Five small edits to its F1-0 lines (what the tasks turned out to be, and the added reasons). |

The "bite" steps are one-offs and are never committed. **CI needs no other change:** the Windows tests workflow gets `shared/sidekick-core.js` and `tests/fixtures/sidekick/**` in its path filter in the F1-tauri plan, which adds a TypeScript replay.

**Order of tasks:**

1. `explain`: the risk rules, the first fixture, and the test script
2. `eventFrom` and `ledgerApply`: the adapter and the ledger
3. `stuckStep`: the four nudges
4. `recapOf`, `statusOf` and `matchStatusQuestion`
5. `dismiss`, `muted`, `unmute` and `cleanSidekickSettings`
6. `presenceStep` and `shouldShow`
7. `acceptNicerLine`, and the owner's tables (**owner checkpoint**)
8. Docs, CI, the spec's lines and the final checks

## Tasks and agents

CLAUDE.md: the lightest model that fits. Every task gives all its code, tests and docs, so all eight are transcription: `nm-implementer-light` (Haiku 5.5, medium). Each task is then reviewed by `nm-reviewer` (Haiku 5.5, high); the whole branch by `nm-reviewer-deep` (Sonnet 5.5, high, trigger 4: it is the code that decides what an agent's request is called and what is kept of a session) after Task 8. If a step's expected output differs and the cause is not obvious, hand that task to `nm-implementer-deep` (trigger 2) and say so in the ledger.

| Task | Deliverable | Agent | Review |
|---|---|---|---|
| 0. Worktree and baseline | the branch, the checks as they stand | the session | none |
| 1. `explain` | the core's first section, the generator, `explain-cases.json`, the test script | `nm-implementer-light` | `nm-reviewer` |
| 2. The ledger | `eventFrom`, `ledgerApply`, `hook-cases.json` | `nm-implementer-light` | `nm-reviewer` |
| 3. `stuckStep` | the nudges, `stuck-cases.json` | `nm-implementer-light` | `nm-reviewer` |
| 4. Recap and status | `recap-cases.json`, `status-cases.json` | `nm-implementer-light` | `nm-reviewer` |
| 5. Dismissals and settings | `dismiss-cases.json`, `settings-cases.json` | `nm-implementer-light` | `nm-reviewer` |
| 6. Presence and the gate | `presence-cases.json`, `show-cases.json` | `nm-implementer-light` | `nm-reviewer` |
| 7. The local voice's check, and the owner's tables | `voice-cases.json`, `print-sidekick-tables.mjs` | `nm-implementer-light` | `nm-reviewer`, then the owner |
| 8. Docs, CI, the spec, final checks | `SIDEKICK-CONTRACT.md`, the CI step, three pointers, the spec's lines | `nm-implementer-light` | `nm-reviewer` |
| After 8 | The whole branch: the rules against the spec, hostile inputs, what a port could read two ways | `nm-reviewer-deep` | n/a |

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`).

## Execution

One worktree chat session runs the whole plan: branch `f1-0/sidekick-contract`, model **Haiku 5.5 at medium effort** (CLAUDE.md: a plan whose tasks are given in full: contracts, fixtures, docs). It is not trigger 5: there is no platform API, no concurrency, and every interface between tasks is a function name given here. Nothing is pushed.

**Before the session starts,** this plan and the spec are committed to `notchmeow/rebrand` (a docs-only commit): the controller does this, with the owner's OK, so the branch the session starts from already holds them. **The base is `793b502` or later:** `git merge-base --is-ancestor 793b502 HEAD` must succeed.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up (it carries the owner's advance approval of the brief in step 3):

   > Run `git switch -c f1-0/sidekick-contract notchmeow/rebrand`, then `git merge-base --is-ancestor 793b502 HEAD` and `git ls-files docs/superpowers/plans/2026-10-14-f1-0-sidekick-contract.md docs/superpowers/specs/2026-10-14-agent-sidekick-design.md`: the first must succeed and the second must print both paths. If either fails, say so and stop. Read `CLAUDE.md`, `ARCHITECT.md`, that plan and that spec. Reply "ready" and stop. Do not start any task. The owner approves in advance the controller brief the main session will send as your next message.

2. **Model.** Once the owner starts the chip, the main session sets that session to Haiku 5.5 at medium effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-14-f1-0-sidekick-contract.md` with `superpowers:subagent-driven-development`, task by task, on branch `f1-0/sidekick-contract`. Dispatch each task to the agent the plan's "Tasks and agents" table names (Haiku 5.5 first: `nm-implementer-light`, `nm-reviewer`; Sonnet 5.5 only for a task Haiku failed twice, or the final whole-branch review, and then the CLAUDE.md trigger goes in the ledger), then to `nm-reviewer`; fix what the review finds before the next task. Rules for you and for every subagent (put the plan's SUBAGENT RULES block in every brief):
>
> - **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder, the second `f1-0/sidekick-contract`. If either is wrong, stop and report. Commit with `git commit -F <file>`, with the trailer of the model that did the task. **Never push.** Commit once per task, in the task's commit step, with only the files that step names.
> - **Ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-14-f1-0-sidekick-contract/progress.md`: one line per task with its agent, model, commit hash, test lines and review verdict, and any escalation with its trigger. The SDD skill's plugin scripts may be refused by the auto-mode permission check: if so, do not call them; write each task brief with the Write tool just before you dispatch it, and each review's diff with `git diff` to a file under the ledger folder.
> - **Briefs are task-sized.** A brief carries one task: its text, the Global Constraints, the SUBAGENT RULES and the files it names. Never hand a subagent the whole plan.
> - **Reviews** read `git diff notchmeow/rebrand...HEAD` (three dots), narrowed to the task's files.
> - **Every shell block passes `bash -n`** before it is run.
> - **Stop after Task 7:** run `node scripts/print-sidekick-tables.mjs`, save its output under the ledger folder, and report the printed tables to the main session and wait for its go (the owner approves the rules at this checkpoint; their answers may change a rule, which is one edit in `shared/sidekick-core.js` and the typed answer beside its case in `scripts/gen-sidekick-fixtures.mjs`, and a regenerate, made before Task 8 documents it). Then run Task 8 and dispatch `nm-reviewer-deep` over the whole branch.
> - **Servers and processes.** None are needed. Never launch a NotchMeow app. Install and download nothing. Never read the real `~/.claude`.
> - **Stop and report on any refusal** (a denied command, a permission prompt), **on any `find` text that is not found exactly once** and **on "the core says X, the case says Y" from the generator:** do not look for a workaround.
> - **Ping the main session.** Its name in the agent list is `NotchMeow — fork research & cat design`. At the owner checkpoint (after Task 7), at the end, and whenever you stop (a refusal, a failed check, a question), send your report with `SendMessage` addressed to that name, as well as writing it in your own chat, so the main session can double-check the work (its own clone and checks) before anything reaches the owner.
> - **When you are done, report:** the commits; the output of `bash scripts/test-sidekick-contract.sh`; the `# tests` line of `bash scripts/test-cat-contract.sh`; the output of `node scripts/check-fixtures-additive.mjs 793b502`; and anything you could not settle.

## Interface for the app plans

What the Mac (F1-mac) and Windows/Linux (F1-tauri) plans consume. Each app ports the rules natively (Swift: pure `Sidekick*.swift` files with no AppKit; TypeScript: `windows/src/sidekick/`; Rust: the settings cleaner only) and replays `tests/fixtures/sidekick/*.json`. `docs/SIDEKICK-CONTRACT.md` (Task 8) has the full text.

| Rule | Signature | Answer |
|---|---|---|
| `explain` | `(agent, tool, toolInput, cwd, home)` | `{risk, reasonId, line, target}` |
| `eventFrom` | `(payload, now, opts)` | the event, or `null` |
| `ledgerApply` | `(ledger, event)` | the new ledger; `emptyLedger()`, `approvalAnsweredEvent(agentId, sessionId, now)`, `ledgerPrune`, `liveSessions`, `aliveSubagents`, `commandKey`, `agentName` |
| `stuckStep` | `(ledger, now, ctx)` | `{nudge, nextAt}`; `nudgeText`, `markNudged` |
| `recapOf`, `statusOf` | `({awaySince, now, sessions})`, `({now, sessions}, agentId?)` | `{lines, facts}` or `null` |
| `matchStatusQuestion` | `(text)` | `{matched, agentId}` |
| `dismiss`, `unmute`, `muted`, `cleanSidekickSettings` | `(state, kind)`, `(raw)` | the new state, a boolean, `{on, local, dismissals}` |
| `presenceStep` | `(state, signal, now)` | `{state, back}` |
| `shouldShow` | `(input)` | `{show, reason, replace}` |
| `acceptNicerLine` | `(line, facts)` | a boolean |

## How to run this plan

**Blocks.** A code step is either **Create `path`** (the file's exact content) or **Edit `path`** (a find text that occurs exactly once, and its replacement). Apply an edit by replacing the find text with the replacement and nothing else; if the find text occurs zero or two times, stop and report: the tree is not what the plan expects. Never type a block from memory and never "improve" one. Every `Run:` line is run from the repository root (the worktree's top folder); `Expected: FAIL` and `Expected: PASS` say which way it must go, and the text after it says what to see.

**Commands.** `node --test tests/sidekick/*.test.mjs` runs the rules' tests; `node scripts/gen-sidekick-fixtures.mjs` writes the fixtures (and stops with an error that starts "the core says" if a typed answer and the core disagree); `bash scripts/test-sidekick-contract.sh` runs it all. Pipe a long output through `grep` as the steps show.

**Bite steps.** Some steps break the code on purpose to prove a test fails. Back the file up into a folder you made with `mktemp -d`, change it with the `sed` given, run the test, and copy the backup back; the next step starts from the restored file. After each bite, `git diff --stat` must show only what the task has done so far.

---
## Tasks

### Task 0: Worktree and baseline

No code and no commit. Its first two steps are what the chip's prompt runs before the model is set (see "Execution").

- [ ] **Step 1: Put the session's worktree on the plan's branch**

```bash
git status                                    # must be clean
git switch -c f1-0/sidekick-contract notchmeow/rebrand
git merge-base --is-ancestor 793b502 HEAD && echo "the base (793b502) is in the history"
git ls-files docs/superpowers/plans/2026-10-14-f1-0-sidekick-contract.md docs/superpowers/specs/2026-10-14-agent-sidekick-design.md
git log --oneline -3
```

Expected: `the base (793b502) is in the history` and the two paths. If either is missing, the worktree was cut from an older base or before the owner committed this plan and the spec: stop and tell the owner. Every later command runs from the root of this worktree. Never push.

- [ ] **Step 2: Check the places this plan edits are as it expects**

```bash
test -e shared/sidekick-core.js && echo "sidekick-core.js exists already" || echo "sidekick-core.js is new"
test -e tests/fixtures/sidekick && echo "fixtures exist already" || echo "fixtures are new"
ls shared
grep -c "Cat contract (cat-core.js self-checks, fixtures, determinism)" .github/workflows/build.yml
grep -c "^- \`docs/SPEC.md\`, \`docs/INTEGRATIONS.md\`" CLAUDE.md
grep -c "^## Code map (graphify)" ARCHITECT.md
grep -c "About 8 tasks: the core's \`explain\`;" docs/superpowers/specs/2026-10-14-agent-sidekick-design.md
node --version
```

Expected: `sidekick-core.js is new`, `fixtures are new`, `theme.json`, then `1`, `1`, `1`, `1`, and a Node version of 22 or newer. Anything else: stop and report.

- [ ] **Step 3: Baseline: the checks this plan must not move**

```bash
bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|identical"
node scripts/check-fixtures-additive.mjs 793b502 | tail -1
bash scripts/check-no-leftovers.sh 2>&1 | tail -1
```

Expected: `# tests 288`, `# pass 288`, `# fail 0`, `✓ two generator runs write identical bytes`, `✓ fixtures changed only by addition since 793b502`, and a `✓` line from the leftovers guard.

- [ ] **Step 4: Read the base once**

Read, without changing: `design/prototype/cat-core.js` (its first 30 lines and its `SEARCH_TOOLS` / `toolState` lines), `scripts/gen-cat-fixtures.mjs` (its `format` and `main`), `scripts/test-cat-contract.sh`, and the spec's "Risk rules" and "Stuck rules". Write one sentence in the ledger on how the cat contract keeps its generator, its fixtures and its test script apart.

---
### Task 1: `explain`, the risk rules, and the test script

**Files:**
- Create: `shared/sidekick-core.js`, `scripts/gen-sidekick-fixtures.mjs`, `tests/sidekick/explain.test.mjs`, `scripts/test-sidekick-contract.sh`, and (generated) `tests/fixtures/sidekick/explain-cases.json`

**Interfaces:**
- Produces: `SidekickCore.explain(agent, tool, toolInput, cwd, home) -> {risk, reasonId, line, target}`, `SidekickCore.REASONS` (`[{id, risk, line}]`), `SidekickCore.WRITE_TOOLS` (the names of the tools that write files), `resolvePath(p, cwd, home)`, `baseName(p)`; in the generator, `SECTIONS` (file name to builder), `expectEqual(what, got, want)` and `format(obj)`. Later tasks add their rules at the line `// @@NEXT` of the core and their fixtures at the line `// @@SECTIONS` of the generator.

- [ ] **Step 1: Write the test first**

**Create `tests/sidekick/explain.test.mjs`**

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
const core = createRequire(import.meta.url)('../../shared/sidekick-core.js');
const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/sidekick/explain-cases.json', import.meta.url), 'utf8'));

const explain = (tool, input, cwd = '/Users/me/proj', home = '/Users/me') => core.explain('integration_claude', tool, input, cwd, home);

test('the fixture rows are what the core says, row by row', () => {
  for (const c of fx.cases) {
    const got = core.explain(c.agent, c.tool ?? undefined, c.input ?? undefined, c.cwd, c.home);
    assert.deepEqual([got.risk, got.reasonId, got.line, got.target], [c.risk, c.reasonId, c.line, c.target], c.name);
  }
});

test('every reason has at least two positive rows and at least one near miss', () => {
  for (const r of core.REASONS) {
    const positive = fx.cases.filter(c => c.reasonId === r.id && !c.near).length;
    const near = fx.cases.filter(c => c.near === r.id).length;
    assert.ok(positive >= 2, `${r.id}: ${positive} positive rows`);
    // The reasons that are the answer for "anything else" have no trigger to miss.
    if (!['unknown_command', 'local_command', 'outside_project'].includes(r.id)) assert.ok(near >= 1, `${r.id}: no near miss`);
  }
});

test('the table is the spec table: 12 high, the medium and the low reasons, every id once', () => {
  const ids = core.REASONS.map(r => r.id);
  assert.equal(new Set(ids).size, ids.length);
  assert.equal(core.REASONS.filter(r => r.risk === 'high').length, 12);
  for (const id of ['rm_recursive', 'sudo', 'pipe_to_shell', 'chmod_recursive', 'git_force_push', 'git_reset_hard', 'git_clean', 'disk_write', 'sql_drop', 'sql_delete_all', 'sensitive_file', 'write_outside',
    'git_push', 'install', 'network_fetch', 'container', 'lockfile_ci', 'mcp_tool', 'unknown_tool', 'unsure', 'read_only', 'test_build', 'edit_in_project', 'web', 'subagent']) assert.ok(ids.includes(id), id);
  assert.equal(core.REASONS.find(r => r.id === 'sudo').line, 'Runs a command with admin rights.');
});

test('a line never carries the command, a path or an argument', () => {
  const secret = 'SECRET-MARKER-123';
  const risky = [`echo ${secret}`, `curl https://${secret}.example.com/x`, `rm -rf /${secret}/x`, `git push --force https://${secret}@host/r.git`, `psql -c "DROP TABLE ${secret}"`, `sudo cat /${secret}/file`, `cd ${secret} && npm install ${secret}`, `FOO=${secret} ls`];
  for (const command of risky) {
    const r = explain('Bash', { command });
    assert.ok(!JSON.stringify(r).includes(secret), `${command} -> ${JSON.stringify(r)}`);
  }
  for (const file_path of [`/${secret}/a.js`, `/Users/me/proj/${secret}/b.js`, `/Users/me/.ssh/${secret}/config`]) {
    const r = explain('Write', { file_path });
    assert.ok(!r.line.includes(secret) || r.target === r.line.match(/Changes (.+?)(,| outside| in)/)?.[1], file_path);
    assert.ok(!/[\\/]/.test(r.line) && !/[\\/]/.test(r.target), `${file_path} -> ${r.line}`);
  }
});

test('a name in a line is a basename of at most 60 code points without control characters', () => {
  const long = 'a'.repeat(200) + '.js';
  const r = explain('Write', { file_path: `/Users/me/proj/${long}` });
  assert.ok(Array.from(r.target).length <= 60);
  assert.equal(explain('Write', { file_path: '/Users/me/proj/a\u0007b\n.js' }).target, 'ab.js');
  assert.equal(explain('Write', { file_path: '/Users/me/proj/' + '😀'.repeat(100) }).target, '😀'.repeat(59) + '…');
});

test('it labels only: the same request gives the same answer, and the input is not changed', () => {
  const input = { command: 'git push --force', nested: { a: [1, 2] } };
  const copy = JSON.stringify(input);
  assert.deepEqual(explain('Bash', input), explain('Bash', input));
  assert.equal(JSON.stringify(input), copy);
});

test('hostile input never throws and always gives a well-formed answer', () => {
  let seed = 12345;
  const rnd = n => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  const bits = ['rm', '-rf', '/', '~', '..', '"', "'", '`', '$(', ')', '|', '&&', ';', '>', '>>', '<<', '\\', 'sudo', 'git', 'push', '-f', 'curl', 'sh', ' ', '\n', 'a', 'b/c', '*', '$HOME', 'C:\\', '\u0000', '😀', '=', '-c', 'bash', 'DROP TABLE', 'psql'];
  const tools = ['Bash', 'PowerShell', 'Write', 'Edit', 'apply_patch', 'Read', 'mcp__a__b', 'Zzz', '', 'shell', 'run_shell_command'];
  const values = [null, undefined, 0, NaN, true, [], {}, 'x', ['a', 'b'], { command: null }, { file_path: 7 }];
  for (let i = 0; i < 3000; i++) {
    const text = Array.from({ length: 1 + rnd(8) }, () => bits[rnd(bits.length)]).join(rnd(3) ? ' ' : '');
    const tool = tools[rnd(tools.length)];
    const input = rnd(4) === 0 ? values[rnd(values.length)] : tool === 'Write' || tool === 'Edit' ? { file_path: text } : { command: text, file_path: text, path: text };
    const r = core.explain('x', tool, input, rnd(5) === 0 ? '' : '/Users/me/proj', rnd(5) === 0 ? '' : '/Users/me');
    assert.ok(['low', 'medium', 'high'].includes(r.risk));
    assert.ok(core.REASONS.some(x => x.id === r.reasonId && x.risk === r.risk));
    assert.equal(typeof r.line, 'string');
    assert.ok(r.line.length > 0 && !r.line.includes('{name}'));
    assert.equal(typeof r.target, 'string');
  }
  assert.doesNotThrow(() => core.explain(undefined, undefined, undefined, undefined, undefined));
  assert.doesNotThrow(() => core.explain('a', 'Bash', { command: 'x'.repeat(100000) }, '/p', '/h'));
});

test('paths: ~, $HOME, .. and Windows drive letters', () => {
  assert.equal(core.resolvePath('~/a', '/p', '/Users/me'), '/Users/me/a');
  assert.equal(core.resolvePath('$HOME/a', '/p', '/Users/me'), '/Users/me/a');
  assert.equal(core.resolvePath('../x', '/p/q', '/h'), '/p/x');
  assert.equal(core.resolvePath('a/./b/../c', '/p', '/h'), '/p/a/c');
  assert.equal(core.resolvePath('C:\\Users\\me\\a', '', ''), 'C:/Users/me/a');
  assert.equal(core.resolvePath('/', '/p', '/h'), '/');
  assert.equal(core.baseName('C:\\Users\\me\\a.txt'), 'a.txt');
  assert.equal(core.baseName('/a/b/'), 'b');
});
```

**Create `scripts/test-sidekick-contract.sh`**

```bash
#!/usr/bin/env bash
# Runs the sidekick contract: the rules' own tests, a no-drift check of tests/fixtures/sidekick/ against sidekick-core.js, and a determinism check (two generator runs
# must write identical bytes).
set -euo pipefail
cd "$(dirname "$0")/.."
command -v node >/dev/null || { echo "node (22 or newer) is required" >&2; exit 1; }
node --test tests/sidekick/*.test.mjs
node scripts/gen-sidekick-fixtures.mjs --check
a=$(mktemp -d); b=$(mktemp -d)
trap 'rm -rf "$a" "$b"' EXIT
node scripts/gen-sidekick-fixtures.mjs --out "$a" >/dev/null
node scripts/gen-sidekick-fixtures.mjs --out "$b" >/dev/null
diff -r "$a" "$b" >/dev/null || { echo "✗ two generator runs wrote different bytes" >&2; exit 1; }
echo "✓ two generator runs write identical bytes"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash -n scripts/test-sidekick-contract.sh && node --test tests/sidekick/*.test.mjs 2>&1 | grep -E "^# (tests|fail)|Cannot find"`
Expected: FAIL: `Cannot find module '../../shared/sidekick-core.js'`, `# tests 1`, `# fail 1`.

- [ ] **Step 3: Write the rules**

**Create `shared/sidekick-core.js`**

```js
/**
 * The agent sidekick's rules, written once and shared (sub-project F1, docs/SIDEKICK-CONTRACT.md).
 *
 * Pure: no clock, no network, no files, no randomness. Every rule takes the time it needs as an argument. Both apps port these rules and replay
 * tests/fixtures/sidekick/*.json, which scripts/gen-sidekick-fixtures.mjs writes from this file. If an app and a fixture disagree, this file decides.
 *
 * The sidekick labels and remembers. It never blocks, allows or denies anything, and it keeps no prompt, no assistant text, no command, no full
 * path and no file content: lines carry basenames and counts only.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.SidekickCore = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
'use strict';
const api = { VERSION: 1 };

// ── Helpers ──────────────────────────────────────────────────────────────────
const MIN = 60000;
const isObj = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const isStr = x => typeof x === 'string';
const isNum = x => typeof x === 'number' && Number.isFinite(x);
/** The last component of a path, `/` or `\` alike, without control characters, at most 60 code points. Lines carry nothing else of a path. */
const baseName = p => {
  const s = String(p).replace(/[\\/]+$/, '');
  const i = Math.max(s.lastIndexOf('/'), s.lastIndexOf('\\'));
  const cps = Array.from((i >= 0 ? s.slice(i + 1) : s).replace(/[\u0000-\u001f\u007f-\u009f]/g, ''));
  return cps.length > 60 ? cps.slice(0, 59).join('') + '…' : cps.join('');
};

// ── Task 1: explain, the risk rules ─────────────────────────────────────────

/** Every reason, in the order that breaks a tie between two of the same risk (the earlier one wins). `{name}` is a basename, never a path or a command. */
const REASONS = [
  ['rm_recursive', 'high', 'Deletes {name} and everything inside it.'],
  ['sudo', 'high', 'Runs a command with admin rights.'],
  ['pipe_to_shell', 'high', 'Downloads a script and runs it at once.'],
  ['chmod_recursive', 'high', 'Changes permissions on {name} and everything inside it.'],
  ['git_force_push', 'high', 'Overwrites the remote branch history.'],
  ['git_reset_hard', 'high', 'Throws away local changes.'],
  ['git_clean', 'high', "Deletes files git doesn't track."],
  ['disk_write', 'high', 'Writes straight to a disk.'],
  ['sql_drop', 'high', 'Deletes a database table or database.'],
  ['sql_delete_all', 'high', 'Changes every row in a table.'],
  ['sensitive_file', 'high', 'Changes {name}, which can hold secrets or settings.'],
  ['write_outside', 'high', 'Changes {name}, outside this project.'],
  ['git_push', 'medium', 'Sends commits to a remote.'],
  ['install', 'medium', 'Installs software.'],
  ['network_fetch', 'medium', 'Talks to another computer.'],
  ['container', 'medium', 'Controls containers.'],
  ['lockfile_ci', 'medium', 'Changes {name}, which affects every build.'],
  ['mcp_tool', 'medium', 'Uses a tool from an add-on.'],
  ['unknown_tool', 'medium', 'Uses a tool NotchMeow doesn’t know.'],
  ['unsure', 'medium', 'NotchMeow can’t tell what this does.'],
  ['outside_project', 'medium', 'Touches {name}, outside this project.'],
  ['rm_in_project', 'medium', 'Deletes {name} in this project.'],
  ['unknown_command', 'medium', 'Runs a command NotchMeow doesn’t recognise.'],
  ['read_only', 'low', 'Only reads files.'],
  ['test_build', 'low', "Runs the project's tests or build."],
  ['edit_in_project', 'low', 'Edits {name} in this project.'],
  ['web', 'low', 'Reads a web page.'],
  ['subagent', 'low', 'Starts a helper agent.'],
  ['local_command', 'low', 'Does a simple local step.'],
];
const REASON = Object.fromEntries(REASONS.map(([id, risk, line], order) => [id, { id, risk, line, order }]));
const RISK_RANK = { low: 0, medium: 1, high: 2 };
api.REASONS = REASONS.map(([id, risk, line]) => ({ id, risk, line }));

// ── Paths ────────────────────────────────────────────────────────────────────
/** `p` against `cwd`: `~` and `$HOME` become `home`, `.` and `..` fold away, `\` is `/`. A relative path with no `cwd` stays relative. */
function resolvePath(p, cwd, home) {
  let s = String(p).replace(/\\/g, '/');
  if (home) s = s.replace(/^(~|\$HOME|\$\{HOME\})(?=\/|$)/, String(home).replace(/\\/g, '/').replace(/\/+$/, ''));
  if (!/^(\/|[A-Za-z]:\/|~)/.test(s)) s = (cwd ? String(cwd).replace(/\\/g, '/').replace(/\/+$/, '') : '.') + '/' + s;
  const m = /^((?:[A-Za-z]:)?\/|~\/?)?([\s\S]*)$/.exec(s);
  const root = m[1] || '', out = [];
  for (const seg of m[2].split('/')) {
    if (seg === '' || seg === '.') continue;
    if (seg === '..') { if (out.length && out[out.length - 1] !== '..') out.pop(); else if (!root) out.push('..'); } else out.push(seg);
  }
  const r = root + out.join('/');
  return r.length > 1 && r.endsWith('/') && !/^[A-Za-z]:\/$/.test(r) ? r.slice(0, -1) : (r || '.');
}
const isAbs = r => /^(\/|[A-Za-z]:\/|~)/.test(r);
const lc = r => (/^[A-Za-z]:\//.test(r) ? r.toLowerCase() : r);
const under = (r, root) => { const a = lc(r), b = lc(root); return a === b || a.startsWith(b.endsWith('/') ? b : b + '/'); };
/** 'inside', 'outside' or 'unknown' (an absolute path when the project folder is not known). */
function where(p, cwd, home) {
  const r = resolvePath(p, cwd, home);
  if (!cwd) return isAbs(r) ? 'unknown' : r.startsWith('..') ? 'outside' : 'inside';
  return under(r, resolvePath(cwd, '', home)) ? 'inside' : 'outside';
}
const isHomeFolder = (r, home) => (home && lc(r) === lc(resolvePath(home, '', ''))) || /^(\/(Users|home)\/[^/]+|[A-Za-z]:\/Users\/[^/]+)$/i.test(r) || r === '~';

// ── What a file path means ───────────────────────────────────────────────────
const SHELL_RC = new Set(['.bashrc', '.bash_profile', '.bash_login', '.bash_logout', '.profile', '.zshrc', '.zshenv', '.zprofile', '.zlogin', '.zlogout', 'config.fish']);
const LOCKFILES = new Set(['package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'bun.lockb', 'Cargo.lock', 'Gemfile.lock', 'poetry.lock', 'Pipfile.lock', 'composer.lock', 'go.sum', 'Podfile.lock', 'Package.resolved', '.gitlab-ci.yml', 'Jenkinsfile', 'azure-pipelines.yml']);
function sensitivePath(r, home) {
  const b = baseName(r), h = home ? resolvePath(home, '', '') : null;
  if (b.startsWith('.env') || /\.(pem|key|p12|pfx)$/i.test(b) || b.startsWith('id_') || SHELL_RC.has(b)) return true;
  if (/\/\.git\/hooks\//.test(r) || /\/\.claude\/settings[^/]*\.json$/.test(r)) return true;
  return ['.ssh', '.aws', '.gnupg'].some(d => (h ? under(r, `${h}/${d}`) : false) || new RegExp(`^(/Users/[^/]+|/home/[^/]+|[A-Za-z]:/Users/[^/]+|~)/${d}(/|$)`, 'i').test(r));
}
const lockOrCi = r => LOCKFILES.has(baseName(r)) || /\/\.github\/workflows\//.test(r) || /\/\.circleci\//.test(r);

/** The candidate for writing to one path: `{reason, target}`. */
function writeCandidate(p, cwd, home) {
  const r = resolvePath(p, cwd, home), w = where(p, cwd, home);
  if (sensitivePath(r, home)) return { reason: 'sensitive_file', target: baseName(r) };
  if (w === 'outside') return { reason: 'write_outside', target: baseName(r) };
  if (w === 'unknown') return { reason: 'unsure', target: '' };
  if (lockOrCi(r)) return { reason: 'lockfile_ci', target: baseName(r) };
  return { reason: 'edit_in_project', target: baseName(r) };
}

// ── Shell commands ───────────────────────────────────────────────────────────
/**
 * Splits a command at `&&`, `||`, `;`, `|`, `&` and newlines, respecting quotes. Each part is `{args, writes, op}`: the words (`{text, quoted}`), the targets
 * of `>` and `>>` redirects and the operator that follows. `ps` (PowerShell) reads `\` as a path separator, not an escape. Returns null for what can't be read safely: an open quote, `$(…)`, backticks, `<(…)` and here-documents.
 */
function splitShell(cmd, ps) {
  const s = String(cmd), parts = [];
  let toks = [], cur = '', has = false, quoted = false, q = '';
  const push = () => { if (has) toks.push({ text: cur, quoted }); cur = ''; has = false; quoted = false; };
  const end = op => {
    push();
    const args = [], writes = [];
    for (let k = 0; k < toks.length; k++) {
      if (toks[k].redir) { const t = toks[k + 1]; if (t && !toks[k].input && !t.text.startsWith('&')) writes.push(t.text); k++; } else args.push(toks[k]);
    }
    parts.push({ args, writes, op });
    toks = [];
  };
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (q === "'") { if (c === "'") q = ''; else cur += c; continue; }
    if (q === '"') {
      if (c === '"') q = '';
      else if (c === '\\' && !ps && i + 1 < s.length && '$`"\\\n'.includes(s[i + 1])) cur += s[++i];
      else if (c === '`' || (c === '$' && s[i + 1] === '(')) return null;
      else cur += c;
      continue;
    }
    if (c === "'" || c === '"') { q = c; has = true; quoted = true; continue; }
    if (c === '\\') { if (ps) { cur += c; has = true; } else if (i + 1 < s.length) { cur += s[++i]; has = true; } continue; }
    if (c === '`' || (c === '$' && s[i + 1] === '(') || ((c === '<' || c === '>') && s[i + 1] === '(')) return null;
    if (c === '<' && s[i + 1] === '<') return null;
    if (c === ' ' || c === '\t' || c === '\r') { push(); continue; }
    if (c === '\n') { end('\n'); continue; }
    if (c === ';') { end(';'); continue; }
    if (c === '&' && s[i + 1] === '&') { end('&&'); i++; continue; }
    if (c === '|' && s[i + 1] === '|') { end('||'); i++; continue; }
    if (c === '|') { if (s[i + 1] === '&') i++; end('|'); continue; }
    if (c === '&') { if (s[i + 1] === '>' || s[i - 1] === '>') { cur += c; has = true; } else end('&'); continue; }
    if (c === '>' || c === '<') {
      if (!/^\d*$/.test(cur) || quoted) push(); else { cur = ''; has = false; }
      let op = c; while (s[i + 1] === c) { op += s[++i]; }
      if (s[i + 1] === '|') i++;
      if (s[i + 1] === '&') { toks.push({ text: op + s[i + 1], quoted: false }); i++; continue; }   // 2>&1: not a file
      toks.push({ text: op, quoted: false, redir: true, input: c === '<' });
      continue;
    }
    cur += c; has = true;
  }
  if (q) return null;
  end('');
  return parts.filter(p => p.args.length || p.writes.length);
}

const SHELLS = new Set(['sh', 'bash', 'zsh', 'dash', 'fish', 'ksh']);
const READ_CMDS = new Set(['ls', 'cat', 'head', 'tail', 'wc', 'grep', 'egrep', 'fgrep', 'rg', 'ag', 'pwd', 'which', 'whoami', 'date', 'tree', 'stat', 'file', 'diff', 'sort', 'uniq', 'cut', 'basename', 'dirname', 'realpath', 'env', 'printenv', 'true', 'false', 'sleep', 'less', 'more', 'du', 'df', 'ps', 'uname', 'id', 'hostname', 'jq', 'tr', 'nl', 'column', 'xxd', 'od', 'md5', 'shasum', 'sha256sum', 'test', '[']);
const LOCAL_CMDS = new Set(['echo', 'printf', 'mkdir', 'touch', 'mv', 'cp', 'ln', 'rmdir', 'export', 'unset', 'set', 'alias', ':']);
const GIT_READ = new Set(['status', 'diff', 'log', 'show', 'rev-parse', 'ls-files', 'blame', 'describe', 'shortlog', 'grep', 'ls-tree', 'cat-file', 'reflog']);
const GIT_LOCAL = new Set(['add', 'commit', 'switch', 'stash', 'merge', 'tag', 'mv', 'rm', 'init', 'config']);
const GIT_NET = new Set(['fetch', 'pull', 'clone']);
const INSTALL_SUBS = new Set(['install', 'i', 'add', 'ci', 'update', 'upgrade', 'remove', 'uninstall', 'link', 'sync', 'require', 'reinstall']);
const NET_CMDS = new Set(['curl', 'wget', 'ssh', 'scp', 'sftp', 'rsync', 'nc', 'ncat', 'ftp', 'telnet']);
const CONTAINER_CMDS = new Set(['docker', 'podman', 'kubectl', 'helm', 'docker-compose', 'minikube']);
const SQL_CLIS = new Set(['psql', 'mysql', 'mariadb', 'sqlite3', 'sqlcmd', 'mongosh']);
const TEST_BIN = new Set(['pytest', 'jest', 'vitest', 'mocha', 'tsc', 'eslint', 'prettier', 'xcodebuild', 'swiftlint', 'rubocop', 'ruff', 'mypy', 'phpunit', 'rspec']);
const TEST_SUB = { make: ['all', 'build', 'test', 'check', 'lint', 'clean'], swift: ['build', 'test'], gradle: ['build', 'test', 'check'], gradlew: ['build', 'test', 'check'], mvn: ['test', 'package', 'verify', 'compile'], dotnet: ['build', 'test'] };
const CARGO_GO = { cargo: ['build', 'test', 'check', 'clippy', 'fmt', 'doc'], go: ['build', 'test', 'vet', 'fmt'] };
const NPM_RUN_OK = new Set(['test', 'build', 'lint', 'check', 'typecheck', 'format', 'tsc']);
const plain = args => args.filter(a => !/^-/.test(a.text) || a.quoted);

/** Looks through the words that only prefix a command: `VAR=1`, `env`, `time`, `command`, `nohup`, `sudo` and `doas` (which is remembered). */
function skipPrefix(args) {
  const a = args.slice();
  let sudo = false;
  for (;;) {
    const t = a[0] && a[0].text, b = t && baseName(t);
    if (!t) break;
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(t) && !a[0].quoted) { a.shift(); continue; }
    if (b === 'sudo' || b === 'doas') { sudo = true; a.shift(); while (a[0] && !a[0].quoted && /^-/.test(a[0].text)) { const f = a.shift().text; if (/^-[ugCpD]$/.test(f)) a.shift(); } continue; }
    if (b === 'env') { a.shift(); while (a[0] && (/^-/.test(a[0].text) || /^[A-Za-z_][A-Za-z0-9_]*=/.test(a[0].text))) a.shift(); continue; }
    if (['time', 'command', 'nohup', 'builtin', 'nice', 'exec'].includes(b)) { a.shift(); continue; }
    break;
  }
  return { sudo, args: a };
}

/** The candidates of one command line, `[{reason, target}]`; null when it can't be read. */
function shellCandidates(cmd, cwd, home, depth, ps) {
  const parts = splitShell(cmd, ps);
  if (!parts || !parts.length) return null;
  const found = [];
  const add = (reason, target = '') => found.push({ reason, target });
  const name = p => baseName(resolvePath(p, cwd, home));
  const outsideOf = paths => paths.find(p => where(p, cwd, home) !== 'inside');
  parts.forEach((part, idx) => {
    const { sudo, args } = skipPrefix(part.args);
    if (sudo) add('sudo');
    for (const w of part.writes) {
      if (/^\/dev\/(null|stdout|stderr|tty|zero)$/.test(w)) continue;
      if (/^\/dev\//.test(w)) { add('disk_write'); continue; }
      const c = writeCandidate(w, cwd, home);
      if (c.reason === 'sensitive_file' || c.reason === 'write_outside' || c.reason === 'unsure') found.push(c);
    }
    if (!args.length) return;
    const cmdName = baseName(args[0].text), rest = args.slice(1), pl = plain(rest).map(a => a.text);
    const nextArgs = parts[idx + 1] && part.op === '|' ? skipPrefix(parts[idx + 1].args).args : [];
    if (nextArgs.length && (cmdName === 'curl' || cmdName === 'wget') && SHELLS.has(baseName(nextArgs[0].text))) { add('pipe_to_shell'); return; }
    if (cmdName === 'cd' || cmdName === 'pushd' || cmdName === 'popd') return;
    if (SHELLS.has(cmdName)) {
      const ci = rest.findIndex(a => !a.quoted && /^-[A-Za-z]*c$/.test(a.text));
      if (ci >= 0 && rest[ci + 1] && depth < 2) { const inner = shellCandidates(rest[ci + 1].text, cwd, home, depth + 1, ps); if (inner) found.push(...inner); else add('unsure'); } else add('unsure');
      return;
    }
    if (['eval', 'source', '.', 'xargs', 'watch', 'xcrun'].includes(cmdName)) { add('unsure'); return; }
    if (cmdName === 'rm' || cmdName.toLowerCase() === 'remove-item') {
      const rec = rest.some(a => !a.quoted && (/^-[A-Za-z]*[rR][A-Za-z]*$/.test(a.text) || a.text === '--recursive' || /^-recurse$/i.test(a.text)));
      const bad = pl.find(t => { const r = resolvePath(t, cwd, home); return r === '/' || /^[A-Za-z]:\/$/.test(r) || isHomeFolder(r, home) || where(t, cwd, home) !== 'inside' || (cwd && lc(r) === lc(resolvePath(cwd, '', home))); });
      if (rec && bad !== undefined) { const rb = resolvePath(bad, cwd, home); add('rm_recursive', isHomeFolder(rb, home) ? '~' : /^([A-Za-z]:)?\/$/.test(rb) ? rb : name(bad)); }
      else if (!rec && outsideOf(pl) !== undefined) add('outside_project', name(outsideOf(pl)));
      else add('rm_in_project', pl.length ? name(pl[0]) : '');
      return;
    }
    if (cmdName === 'chmod' || cmdName === 'chown' || cmdName === 'chgrp') {
      const rec = rest.some(a => !a.quoted && (/^-[A-Za-z]*R[A-Za-z]*$/.test(a.text) || a.text === '--recursive'));
      const paths = pl.slice(1);
      if (rec) add('chmod_recursive', name(paths[paths.length - 1] || '.') || '/');
      else if (outsideOf(paths) !== undefined) add('outside_project', name(outsideOf(paths)));
      else add('local_command');
      return;
    }
    if (cmdName === 'dd' || cmdName.startsWith('mkfs') || cmdName === 'fdisk' || (cmdName === 'diskutil' && /^(erase|partition|zero|secure)/i.test(pl[0] || ''))) { add('disk_write'); return; }
    if (cmdName === 'git') {
      const g = rest.slice();
      while (g[0] && /^-/.test(g[0].text)) { const f = g.shift().text; if (f === '-C' || f === '-c') g.shift(); }
      const sub = g[0] ? g[0].text : '', fl = g.slice(1).map(a => a.text);
      if (sub === 'push') add(fl.some(f => f === '--force' || /^-[A-Za-z]*f[A-Za-z]*$/.test(f) || /^\+/.test(f)) ? 'git_force_push' : 'git_push');
      else if (sub === 'reset') add(fl.includes('--hard') ? 'git_reset_hard' : 'local_command');
      else if (sub === 'clean') add(fl.some(f => f === '--force' || /^-[A-Za-z]*f/.test(f)) ? 'git_clean' : 'local_command');
      else if (GIT_READ.has(sub)) add('read_only');
      else if (sub === 'branch') add(fl.length && fl.some(f => !/^-[arv]$|^--list$/.test(f)) ? 'local_command' : 'read_only');
      else if (sub === 'remote') add(!fl.length || fl.every(f => f === '-v') ? 'read_only' : 'unknown_command');
      else if (GIT_LOCAL.has(sub)) add('local_command');
      else if (GIT_NET.has(sub)) add('network_fetch');
      else add('unknown_command');
      return;
    }
    if (NET_CMDS.has(cmdName)) { add('network_fetch'); return; }
    if (CONTAINER_CMDS.has(cmdName)) { add('container'); return; }
    if (SQL_CLIS.has(cmdName)) {
      for (const st of String(cmd).split(';')) {
        if (/\bDROP\s+(TABLE|DATABASE|SCHEMA|INDEX|VIEW)\b/i.test(st)) { add('sql_drop'); return; }
        if ((/\bDELETE\s+FROM\b/i.test(st) || /\bUPDATE\s+\S+\s+SET\b/i.test(st) || /\bTRUNCATE\b/i.test(st)) && !/\bWHERE\b/i.test(st)) { add('sql_delete_all'); return; }
      }
      add('unknown_command');
      return;
    }
    if (['npm', 'pnpm', 'yarn', 'bun'].includes(cmdName)) {
      const sub = pl[0] || '';
      if (INSTALL_SUBS.has(sub)) add('install');
      else if (sub === 'test' || sub === 't') add('test_build');
      else if (sub === 'run' || sub === 'run-script') add(NPM_RUN_OK.has(pl[1] || '') ? 'test_build' : 'unknown_command');
      else add(NPM_RUN_OK.has(sub) ? 'test_build' : 'unknown_command');
      return;
    }
    if (['pip', 'pip3', 'pipx', 'uv', 'brew', 'gem', 'apt', 'apt-get', 'composer', 'poetry', 'conda', 'port'].includes(cmdName)) { add(pl.some(x => INSTALL_SUBS.has(x)) ? 'install' : 'unknown_command'); return; }
    if (cmdName in CARGO_GO) { const sub = pl[0] || ''; add(['install', 'add', 'get'].includes(sub) ? 'install' : CARGO_GO[cmdName].includes(sub) ? 'test_build' : 'unknown_command'); return; }
    if (cmdName in TEST_SUB) { add(TEST_SUB[cmdName].includes(pl[0] || (cmdName === 'make' ? 'all' : '')) ? 'test_build' : 'unknown_command'); return; }
    if (TEST_BIN.has(cmdName)) { add('test_build'); return; }
    if (/^python[0-9.]*$/.test(cmdName) || ['node', 'deno', 'ruby', 'perl'].includes(cmdName)) {
      const mi = rest.findIndex(a => a.text === '-m');
      add(mi >= 0 && ['pytest', 'unittest'].includes((rest[mi + 1] || {}).text) ? 'test_build' : 'unknown_command');
      return;
    }
    if (cmdName === 'find') { add(rest.some(a => !a.quoted && ['-delete', '-exec', '-execdir', '-ok', '-okdir'].includes(a.text)) ? 'unsure' : 'read_only'); return; }
    if (cmdName === 'sed' || cmdName === 'awk') { add(rest.some(a => !a.quoted && /^(-i.*|--in-place.*)$/.test(a.text)) ? 'unknown_command' : 'read_only'); return; }
    if (cmdName === 'tee') { const o = outsideOf(pl); if (o !== undefined) { const c = writeCandidate(o, cwd, home); add(c.reason, c.target); } else add('local_command'); return; }
    if (READ_CMDS.has(cmdName) || /^get-/i.test(cmdName)) { add('read_only'); return; }
    if (LOCAL_CMDS.has(cmdName)) {
      const o = ['mkdir', 'touch', 'mv', 'cp', 'ln', 'rmdir'].includes(cmdName) ? outsideOf(pl) : undefined;
      if (o !== undefined) add('outside_project', name(o)); else add('local_command');
      return;
    }
    add('unknown_command');
  });
  return found.length ? found : [{ reason: 'local_command', target: '' }];
}

const SHELL_TOOLS = new Set(['Bash', 'PowerShell', 'run_shell_command', 'shell', 'local_shell', 'exec_command']);
const READ_TOOLS = new Set(['Read', 'Glob', 'Grep', 'LS', 'NotebookRead', 'read_file', 'read_many_files', 'list_directory', 'search_file_content', 'grep_search', 'glob', 'grep_files']);
const WEB_TOOLS = new Set(['WebFetch', 'WebSearch', 'web_fetch', 'google_web_search', 'web_search']);
const WRITE_TOOLS = new Set(['Write', 'Edit', 'MultiEdit', 'NotebookEdit', 'write_file', 'replace', 'edit_file']);
const QUIET_TOOLS = new Set(['TodoWrite', 'ExitPlanMode', 'AskUserQuestion', 'write_todos', 'Skill']);
api.WRITE_TOOLS = [...WRITE_TOOLS, 'apply_patch'];

/** The command of a shell tool's input: a string, or an array like `["bash","-lc","ls"]` (Codex). */
function commandOf(input) {
  const c = input.command;
  if (isStr(c)) return c;
  if (Array.isArray(c) && c.every(isStr)) return c.length >= 3 && SHELLS.has(baseName(c[0])) && /^-[A-Za-z]*c$/.test(c[1]) ? c[2] : c.join(' ');
  return null;
}
/** The files a tool writes, from its input: `file_path`, `path`, `notebook_path`, or the `*** Update File:` lines of a Codex patch. */
function pathsOf(tool, input) {
  if (tool === 'apply_patch') {
    const t = isStr(input.command) ? input.command : isStr(input.patch) ? input.patch : '';
    return [...t.matchAll(/^\*\*\* (?:Add|Update|Delete) File: (.+)$/gm)].map(m => m[1].trim());
  }
  const p = [input.file_path, input.path, input.notebook_path, input.target_file].find(isStr);
  return p ? [p] : [];
}

/**
 * Says in plain words how risky one permission request is. Labels only: it never allows, denies or blocks. `agent` is the pill ID (reserved: every agent is read the
 * same way today). Returns `{risk, reasonId, line, target}`; the line is a fixed template with a basename in it and never holds a command, a path or an argument.
 * It never throws: anything it can't read is `medium` with the reason `unsure`.
 */
function explain(agent, tool, toolInput, cwd, home) {
  const finish = (reason, target) => {
    const r = REASON[reason], name = target === '~' || /^([A-Za-z]:)?\/$/.test(target) ? target : target ? baseName(target) : '';
    return { risk: r.risk, reasonId: r.id, line: r.line.replace('{name}', name || 'a file'), target: r.line.includes('{name}') ? name : '' };
  };
  try {
    const t = isStr(tool) ? tool : '', input = isObj(toolInput) ? toolInput : {}, dir = isStr(cwd) ? cwd : '', h = isStr(home) ? home : '';
    let cands = null;
    if (SHELL_TOOLS.has(t)) { const c = commandOf(input); cands = c === null ? null : shellCandidates(c, dir, h, 0, t === 'PowerShell'); }
    else if (t === 'apply_patch' || WRITE_TOOLS.has(t)) { const ps = pathsOf(t, input); cands = ps.length ? ps.map(p => writeCandidate(p, dir, h)) : null; }
    else if (READ_TOOLS.has(t)) cands = [{ reason: 'read_only', target: '' }];
    else if (WEB_TOOLS.has(t)) cands = [{ reason: 'web', target: '' }];
    else if (t === 'Task' || t === 'Agent') cands = [{ reason: 'subagent', target: '' }];
    else if (QUIET_TOOLS.has(t)) cands = [{ reason: 'local_command', target: '' }];
    else if (t.startsWith('mcp__')) cands = [{ reason: 'mcp_tool', target: '' }];
    else if (t) cands = [{ reason: 'unknown_tool', target: '' }];
    if (!cands || !cands.length) return finish('unsure', '');
    const rank = c => RISK_RANK[REASON[c.reason].risk] * 100 - REASON[c.reason].order;
    const best = cands.reduce((a, b) => (rank(b) > rank(a) ? b : a));
    return finish(best.reason, best.target);
  } catch (e) { return finish('unsure', ''); }
}
api.explain = explain;
api.baseName = baseName;
api.resolvePath = resolvePath;

// @@NEXT (the next task's rules go above this line)

return api;
});
```

- [ ] **Step 4: Write the generator, with the first fixture**

Every row types the answer beside the input: `[risk, reasonId, target]`. The generator stops if the core says something else.

**Create `scripts/gen-sidekick-fixtures.mjs`**

```js
#!/usr/bin/env node
// Writes tests/fixtures/sidekick/*.json from shared/sidekick-core.js, the single source of truth (docs/SIDEKICK-CONTRACT.md).
//   node scripts/gen-sidekick-fixtures.mjs             write the fixtures
//   node scripts/gen-sidekick-fixtures.mjs --check     regenerate in memory and fail on any drift
//   node scripts/gen-sidekick-fixtures.mjs --out DIR   write somewhere else (the runner uses it twice, to prove determinism)
// Every case lists its input and, typed by hand next to it, the answer it must get: the generator stops if the core disagrees, so the fixtures are
// never just a copy of what the core says. No npm dependencies. Fixtures hold whole numbers, text, booleans and null only.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
const core = require('../shared/sidekick-core.js');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const FIXTURES = path.join(ROOT, 'tests/fixtures/sidekick');

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
    } else lines.push(`${head}${JSON.stringify(v)}${comma}`);
  });
  return `{\n${lines.join('\n')}\n}\n`;
}

/** Stops the generator when the core's answer is not the one typed next to the case. */
function expectEqual(what, got, want) {
  if (JSON.stringify(got) !== JSON.stringify(want)) throw new Error(`${what}: the core says ${JSON.stringify(got)}, the case says ${JSON.stringify(want)}`);
}

/** file name -> a function that builds the file's object. */
export const SECTIONS = {};

const HOME = '/Users/me', CWD = '/Users/me/proj';

// ── explain-cases.json: the risk rules ──────────────────────────────────────
// Each row: name, tool, input, the answer typed by hand [risk, reasonId, target], and options: cwd, home, `near: 'reason_id'` for a near miss of that reason.
SECTIONS['explain-cases.json'] = () => {
  const rows = [];
  const row = (name, tool, input, expect, o = {}) => rows.push({ name, tool, input, expect, ...o });
  const sh = (name, command, expect, o) => row(name, 'Bash', { command }, expect, o);
  const H = 'high', M = 'medium', L = 'low';

  // High
  sh('rm -rf / deletes the root', 'rm -rf /', [H, 'rm_recursive', '/']);
  sh('rm -rf ~ deletes the home folder', 'rm -rf ~', [H, 'rm_recursive', '~']);
  sh('rm -rf in the home folder is outside the project', 'rm -rf ~/Documents', [H, 'rm_recursive', 'Documents']);
  sh('rm -rf .. is outside the project', 'rm -rf ../x', [H, 'rm_recursive', 'x']);
  sh('rm -rf . deletes the project itself', 'rm -rf .', [H, 'rm_recursive', 'proj']);
  sh('rm -rf looks through sudo and VAR=1', 'FOO=1 sudo rm -rf /tmp/x', [H, 'rm_recursive', 'x']);
  sh('a quoted rm is only a word', 'echo "rm -rf /"', [L, 'local_command', ''], { near: 'rm_recursive' });
  sh('rm -r inside the project is not rm_recursive', 'rm -r ./build', [M, 'rm_in_project', 'build'], { near: 'rm_recursive' });
  sh('rm -rf of a name inside the project is not rm_recursive', 'rm -rf node_modules', [M, 'rm_in_project', 'node_modules'], { near: 'rm_recursive' });

  sh('sudo with a command', 'sudo ls', [H, 'sudo', '']);
  sh('sudo with an option that takes a value', 'sudo -u bob npm i', [H, 'sudo', '']);
  sh('doas is sudo', 'doas reboot', [H, 'sudo', '']);
  sh('the word sudo in quotes is not sudo', 'echo "sudo"', [L, 'local_command', ''], { near: 'sudo' });
  sh('sudoku is not sudo', 'sudoku', [M, 'unknown_command', ''], { near: 'sudo' });

  sh('curl piped to sh', 'curl https://x.sh | sh', [H, 'pipe_to_shell', '']);
  sh('wget piped to bash, no spaces', 'wget -qO- https://x|bash', [H, 'pipe_to_shell', '']);
  sh('curl piped to a shell through sudo', 'curl -fsSL https://x | sudo bash', [H, 'sudo', ''], { near: 'pipe_to_shell' });
  sh('curl to a file is a fetch, not pipe_to_shell', 'curl https://x -o x.sh', [M, 'network_fetch', ''], { near: 'pipe_to_shell' });
  sh('curl piped to jq is a fetch', 'curl https://x | jq .', [M, 'network_fetch', ''], { near: 'pipe_to_shell' });

  sh('chmod -R', 'chmod -R 755 build', [H, 'chmod_recursive', 'build']);
  sh('chown -R on the project', 'chown -R me .', [H, 'chmod_recursive', 'proj']);
  sh('chmod on one file', 'chmod 644 a.txt', [L, 'local_command', ''], { near: 'chmod_recursive' });
  sh('chmod +x on one file', 'chmod +x run.sh', [L, 'local_command', ''], { near: 'chmod_recursive' });

  sh('git push --force', 'git push --force', [H, 'git_force_push', '']);
  sh('git push -f', 'git push -f origin main', [H, 'git_force_push', '']);
  sh('git push of a + refspec', 'git push origin +main', [H, 'git_force_push', '']);
  sh('git push --force-with-lease is a force push', 'git push --force-with-lease', [H, 'git_force_push', '']);
  sh('git push --set-upstream is a push', 'git push -u origin main', [M, 'git_push', ''], { near: 'git_force_push' });

  sh('git reset --hard', 'git reset --hard', [H, 'git_reset_hard', '']);
  sh('git reset --hard HEAD~3', 'git reset --hard HEAD~3', [H, 'git_reset_hard', '']);
  sh('git reset of one file', 'git reset HEAD file.txt', [L, 'local_command', ''], { near: 'git_reset_hard' });
  sh('git reset --soft', 'git reset --soft HEAD~1', [L, 'local_command', ''], { near: 'git_reset_hard' });

  sh('git clean -fd', 'git clean -fd', [H, 'git_clean', '']);
  sh('git clean -f', 'git clean -f', [H, 'git_clean', '']);
  sh('git clean -n is a dry run', 'git clean -n', [L, 'local_command', ''], { near: 'git_clean' });
  sh('git clean -nd is a dry run', 'git clean -nd', [L, 'local_command', ''], { near: 'git_clean' });

  sh('dd to a disk', 'dd if=/dev/zero of=/dev/disk2', [H, 'disk_write', '']);
  sh('mkfs', 'mkfs.ext4 /dev/sda1', [H, 'disk_write', '']);
  sh('a redirect into a device', 'echo x > /dev/sda', [H, 'disk_write', '']);
  sh('a redirect into /dev/null is nothing', 'ls > /dev/null', [L, 'read_only', ''], { near: 'disk_write' });
  sh('a redirect of the error stream is nothing', 'ls 2>&1', [L, 'read_only', ''], { near: 'disk_write' });

  sh('DROP TABLE through psql', 'psql -c "DROP TABLE users"', [H, 'sql_drop', '']);
  sh('drop database through sqlite3, lower case', 'sqlite3 db.sqlite "drop database x;"', [H, 'sql_drop', '']);
  sh('DROP in a string with no database tool', 'echo "DROP TABLE users"', [L, 'local_command', ''], { near: 'sql_drop' });
  sh('a SELECT through psql', 'psql -c "SELECT 1"', [M, 'unknown_command', ''], { near: 'sql_drop' });

  sh('DELETE FROM with no WHERE', 'psql -c "DELETE FROM users"', [H, 'sql_delete_all', '']);
  sh('UPDATE with no WHERE', 'mysql -e "UPDATE users SET admin=1"', [H, 'sql_delete_all', '']);
  sh('DELETE FROM with a WHERE', 'psql -c "DELETE FROM users WHERE id=1"', [M, 'unknown_command', ''], { near: 'sql_delete_all' });
  sh('update with a where, lower case', 'mysql -e "update t set a=1 where b=2"', [M, 'unknown_command', ''], { near: 'sql_delete_all' });

  row('Write of .env', 'Write', { file_path: '/Users/me/proj/.env' }, [H, 'sensitive_file', '.env']);
  row('Edit of an SSH config', 'Edit', { file_path: '/Users/me/.ssh/config' }, [H, 'sensitive_file', 'config']);
  row('Write of a key', 'Write', { file_path: '/Users/me/proj/deploy/server.pem' }, [H, 'sensitive_file', 'server.pem']);
  row('Write of a git hook', 'Write', { file_path: '/Users/me/proj/.git/hooks/pre-commit' }, [H, 'sensitive_file', 'pre-commit']);
  row("Edit of the agent's own settings", 'Edit', { file_path: '/Users/me/proj/.claude/settings.json' }, [H, 'sensitive_file', 'settings.json']);
  sh('a redirect into a shell start-up file', 'echo hi >> ~/.zshrc', [H, 'sensitive_file', '.zshrc']);
  row('Write of env.ts is a source file', 'Write', { file_path: '/Users/me/proj/src/env.ts' }, [L, 'edit_in_project', 'env.ts'], { near: 'sensitive_file' });
  row('Edit of envelope.js is a source file', 'Edit', { file_path: '/Users/me/proj/src/envelope.js' }, [L, 'edit_in_project', 'envelope.js'], { near: 'sensitive_file' });

  row('Edit of /etc/hosts', 'Edit', { file_path: '/etc/hosts' }, [H, 'write_outside', 'hosts']);
  row('Write beside the project', 'Write', { file_path: '../other/a.js' }, [H, 'write_outside', 'a.js']);
  row('Write that climbs out and back in', 'Write', { file_path: 'src/../../other/a.js' }, [H, 'write_outside', 'a.js']);
  row('Write inside the project', 'Write', { file_path: '/Users/me/proj/src/a.js' }, [L, 'edit_in_project', 'a.js'], { near: 'write_outside' });
  row('Write of a sibling folder with the same prefix', 'Write', { file_path: '/Users/me/proj-old/a.js' }, [H, 'write_outside', 'a.js']);

  // Medium
  sh('git push', 'git push', [M, 'git_push', '']);
  sh('git push to a branch', 'git push origin main', [M, 'git_push', '']);
  sh('git status is not a push', 'git status', [L, 'read_only', ''], { near: 'git_push' });
  sh('git pull talks to the remote', 'git pull', [M, 'network_fetch', ''], { near: 'git_push' });

  sh('npm install', 'npm install left-pad', [M, 'install', '']);
  sh('pip install', 'pip install requests', [M, 'install', '']);
  sh('brew install', 'brew install jq', [M, 'install', '']);
  sh('cargo add', 'cargo add serde', [M, 'install', '']);
  sh('a leading cd is looked through', 'cd sub && npm install', [M, 'install', '']);
  sh('env VAR=1 is looked through', 'env A=1 npm i', [M, 'install', '']);
  sh('npm test is not an install', 'npm test', [L, 'test_build', ''], { near: 'install' });
  sh('pip --version is not an install', 'pip --version', [M, 'unknown_command', ''], { near: 'install' });

  sh('curl', 'curl https://example.com', [M, 'network_fetch', '']);
  sh('ssh', 'ssh host ls', [M, 'network_fetch', '']);
  sh('scp', 'scp a.txt host:b.txt', [M, 'network_fetch', '']);
  sh('the word curl in an echo', 'echo curl', [L, 'local_command', ''], { near: 'network_fetch' });
  sh('curlie is not curl', 'curlie https://x', [M, 'unknown_command', ''], { near: 'network_fetch' });

  sh('docker', 'docker ps', [M, 'container', '']);
  sh('kubectl', 'kubectl get pods', [M, 'container', '']);
  sh('the word docker in an echo', 'echo docker', [L, 'local_command', ''], { near: 'container' });

  row('Edit of a lockfile', 'Edit', { file_path: '/Users/me/proj/package-lock.json' }, [M, 'lockfile_ci', 'package-lock.json']);
  row('Write of a CI workflow', 'Write', { file_path: '/Users/me/proj/.github/workflows/ci.yml' }, [M, 'lockfile_ci', 'ci.yml']);
  row('Edit of package.json is a source file', 'Edit', { file_path: '/Users/me/proj/package.json' }, [L, 'edit_in_project', 'package.json'], { near: 'lockfile_ci' });

  row('an MCP tool', 'mcp__github__create_issue', { title: 'x' }, [M, 'mcp_tool', '']);
  row('another MCP tool', 'mcp__x', {}, [M, 'mcp_tool', '']);
  row('mcp_github is not an MCP name', 'mcp_github', {}, [M, 'unknown_tool', ''], { near: 'mcp_tool' });

  row('a tool nobody knows', 'Frobnicate', { a: 1 }, [M, 'unknown_tool', '']);
  row('another unknown tool', 'NewTool', {}, [M, 'unknown_tool', '']);
  row('Task is a helper agent', 'Task', { description: 'x' }, [L, 'subagent', ''], { near: 'unknown_tool' });

  sh('a script file can not be read', 'bash run.sh', [M, 'unsure', '']);
  sh('command substitution can not be read', 'cat $(ls)', [M, 'unsure', '']);
  sh('an open quote can not be read', 'echo "open', [M, 'unsure', '']);
  sh('eval can not be read', 'eval "$X"', [M, 'unsure', '']);
  sh('backticks can not be read', 'echo `date`', [M, 'unsure', '']);
  sh('a here-document can not be read', 'cat <<EOF', [M, 'unsure', '']);
  sh('an empty command', '', [M, 'unsure', '']);
  row('a write with no path', 'Write', {}, [M, 'unsure', '']);
  row('a write when the project is not known', 'Write', { file_path: '/Users/me/proj/a.js' }, [M, 'unsure', ''], { cwd: '' });
  sh('bash -c is read through', 'bash -c "ls"', [L, 'read_only', ''], { near: 'unsure' });
  sh('bash -c is read through, and so is what is in it', 'bash -c "rm -rf /"', [H, 'rm_recursive', '/'], { near: 'unsure' });
  sh('find -delete can not be read', 'find . -delete', [M, 'unsure', '']);

  sh('mkdir outside the project', 'mkdir ../up', [M, 'outside_project', 'up']);
  sh('cp to /tmp', 'cp a.txt /tmp/a.txt', [M, 'outside_project', 'a.txt']);
  sh('rm of one file outside the project', 'rm /tmp/x.txt', [M, 'outside_project', 'x.txt']);
  sh('mkdir inside the project', 'mkdir sub', [L, 'local_command', ''], { near: 'outside_project' });

  sh('rm of one file', 'rm a.txt', [M, 'rm_in_project', 'a.txt']);
  sh('rm -rf of a folder in the project', 'rm -rf dist', [M, 'rm_in_project', 'dist']);
  sh('rm -rf of the root is not a delete in the project', 'rm -rf /', [H, 'rm_recursive', '/'], { near: 'rm_in_project' });

  sh('make install', 'make install', [M, 'unknown_command', '']);
  sh('npm run dev', 'npm run dev', [M, 'unknown_command', '']);
  sh('git checkout', 'git checkout main', [M, 'unknown_command', '']);
  sh('a command nobody knows', 'unknowncmd --x', [M, 'unknown_command', '']);
  sh('make test is a test', 'make test', [L, 'test_build', ''], { near: 'unknown_command' });

  // Low
  row('Read', 'Read', { file_path: '/Users/me/proj/src/a.js' }, [L, 'read_only', '']);
  row('Read of a private key is still only a read: the sensitive-file rule is for writes', 'Read', { file_path: '/Users/me/.ssh/id_rsa' }, [L, 'read_only', ''], { near: 'sensitive_file' });
  row('Grep', 'Grep', { pattern: 'x' }, [L, 'read_only', '']);
  sh('ls', 'ls -la', [L, 'read_only', '']);
  sh('git status', 'git status', [L, 'read_only', '']);
  sh('git diff piped to head', 'git diff | head', [L, 'read_only', '']);
  sh('a pipe of reads', 'cat f | grep x', [L, 'read_only', '']);
  sh('find without -delete', 'find . -name x', [L, 'read_only', '']);
  sh('sed -i writes files', 'sed -i s/a/b/ f.txt', [M, 'unknown_command', ''], { near: 'read_only' });

  sh('npm test', 'npm test', [L, 'test_build', '']);
  sh('pytest', 'pytest -q', [L, 'test_build', '']);
  sh('cargo test', 'cargo test --workspace', [L, 'test_build', '']);
  sh('make', 'make', [L, 'test_build', '']);
  sh('python -m pytest', 'python3 -m pytest tests', [L, 'test_build', '']);
  sh('python of a script', 'python3 run.py', [M, 'unknown_command', ''], { near: 'test_build' });

  row('Edit in the project', 'Edit', { file_path: '/Users/me/proj/src/a.js' }, [L, 'edit_in_project', 'a.js']);
  row('Edit beside the project is not an edit in it', 'Edit', { file_path: '/Users/me/other/a.js' }, [H, 'write_outside', 'a.js'], { near: 'edit_in_project' });
  row('Edit of a lockfile is not a plain edit', 'Edit', { file_path: '/Users/me/proj/yarn.lock' }, [M, 'lockfile_ci', 'yarn.lock'], { near: 'edit_in_project' });
  row('Write of a relative path', 'Write', { file_path: 'notes.md' }, [L, 'edit_in_project', 'notes.md']);
  row('a Codex patch', 'apply_patch', { command: '*** Begin Patch\n*** Update File: src/a.js\n*** End Patch' }, [L, 'edit_in_project', 'a.js']);
  row('a Codex patch that adds an .env', 'apply_patch', { command: '*** Begin Patch\n*** Add File: .env\n*** Update File: src/a.js\n*** End Patch' }, [H, 'sensitive_file', '.env']);
  row('MultiEdit', 'MultiEdit', { file_path: '/Users/me/proj/src/b.js', edits: [] }, [L, 'edit_in_project', 'b.js']);

  row('WebFetch', 'WebFetch', { url: 'https://example.com' }, [L, 'web', '']);
  row('WebSearch', 'WebSearch', { query: 'x' }, [L, 'web', '']);
  sh('curl is not a web page read', 'curl https://example.com', [M, 'network_fetch', ''], { near: 'web' });

  row('Task', 'Task', {}, [L, 'subagent', '']);
  row('Agent', 'Agent', {}, [L, 'subagent', '']);
  row('Tasks is not the helper agent tool', 'Tasks', {}, [M, 'unknown_tool', ''], { near: 'subagent' });

  sh('echo', 'echo hi', [L, 'local_command', '']);
  sh('mkdir', 'mkdir build', [L, 'local_command', '']);
  sh('cd alone', 'cd sub', [L, 'local_command', '']);
  sh('git commit', 'git commit -m x', [L, 'local_command', '']);
  sh('a redirect to a file in the project', 'echo hi > notes.txt', [L, 'local_command', '']);
  row('TodoWrite', 'TodoWrite', { todos: [] }, [L, 'local_command', '']);
  sh('git push is not a local step', 'git push', [M, 'git_push', ''], { near: 'local_command' });

  // The highest risk of the parts wins; on a tie the earlier reason of the table does
  sh('the worst of the parts: push after tests', 'npm test && git push', [M, 'git_push', '']);
  sh('the worst of the parts: a force push after reads', 'ls && git push --force', [H, 'git_force_push', '']);
  sh('the worst of the parts: rm after a semicolon', 'ls; rm -rf ~', [H, 'rm_recursive', '~']);
  sh('a tie between two high reasons: the earlier one', 'cd sub && sudo rm -rf /', [H, 'rm_recursive', '/']);
  sh('a newline separates commands', 'ls\nrm -rf /', [H, 'rm_recursive', '/']);
  sh('a background & separates commands', 'sleep 1 & rm -rf /', [H, 'rm_recursive', '/']);

  // Windows paths and tools
  row('Windows: Write inside the project', 'Write', { file_path: 'C:\\Users\\me\\proj\\src\\a.ts' }, [L, 'edit_in_project', 'a.ts'], { cwd: 'C:\\Users\\me\\proj', home: 'C:\\Users\\me' });
  row('Windows: Write with the drive letter in the other case', 'Write', { file_path: 'c:\\users\\me\\proj\\src\\a.ts' }, [L, 'edit_in_project', 'a.ts'], { cwd: 'C:\\Users\\me\\proj', home: 'C:\\Users\\me' });
  row('Windows: a private key', 'Write', { file_path: 'C:\\Users\\me\\.ssh\\id_rsa' }, [H, 'sensitive_file', 'id_rsa'], { cwd: 'C:\\Users\\me\\proj', home: 'C:\\Users\\me' });
  row('Windows: outside the project', 'Write', { file_path: 'C:\\Windows\\System32\\x.dll' }, [H, 'write_outside', 'x.dll'], { cwd: 'C:\\Users\\me\\proj', home: 'C:\\Users\\me' });
  row('Windows: PowerShell Remove-Item -Recurse on a drive', 'PowerShell', { command: 'Remove-Item -Recurse -Force C:\\' }, [H, 'rm_recursive', 'C:/'], { cwd: 'C:\\Users\\me\\proj', home: 'C:\\Users\\me' });
  row('Windows: PowerShell Get-ChildItem', 'PowerShell', { command: 'Get-ChildItem' }, [L, 'read_only', ''], { cwd: 'C:\\Users\\me\\proj', home: 'C:\\Users\\me' });

  // Other agents' shapes
  row("Gemini's shell tool", 'run_shell_command', { command: 'git push --force' }, [H, 'git_force_push', '']);
  row("Codex's shell tool with an argv array", 'shell', { command: ['bash', '-lc', 'sudo ls'] }, [H, 'sudo', '']);
  row("Gemini's file write", 'write_file', { file_path: '/Users/me/proj/.env' }, [H, 'sensitive_file', '.env']);

  // Hostile input never throws
  row('no tool', undefined, {}, [M, 'unsure', '']);
  row('a tool that is not text', 42, {}, [M, 'unsure', '']);
  row('an input that is not an object', 'Bash', 'ls', [M, 'unsure', '']);
  row('a command that is not text', 'Bash', { command: 7 }, [M, 'unsure', '']);

  const cases = rows.map(r => {
    const got = core.explain('integration_claude', r.tool, r.input, r.cwd ?? CWD, r.home ?? HOME);
    expectEqual(r.name, [got.risk, got.reasonId, got.target], r.expect);
    const c = { name: r.name, agent: 'integration_claude' };
    if (r.near) c.near = r.near;
    c.tool = r.tool === undefined ? null : r.tool; c.input = r.input === undefined ? null : r.input;
    c.cwd = r.cwd ?? CWD; c.home = r.home ?? HOME;
    return { ...c, risk: got.risk, reasonId: got.reasonId, line: got.line, target: got.target };
  });
  return { version: 1, note: 'explain(agent, tool, toolInput, cwd, home) -> {risk, reasonId, line, target}. `near` marks a near miss of that reason. A null tool or input stands for a missing one.', reasons: core.REASONS, cases };
};

// @@SECTIONS (the next task's fixtures go above this line)

/** Every fixture file as text, by name. */
export function build() {
  const out = {};
  for (const [name, make] of Object.entries(SECTIONS)) out[name] = format(make());
  return out;
}

function main(argv) {
  const check = argv.includes('--check');
  const oi = argv.indexOf('--out');
  const outDir = oi >= 0 ? path.resolve(argv[oi + 1]) : FIXTURES;
  const files = build();
  if (check) {
    let drift = 0;
    for (const [name, text] of Object.entries(files)) {
      const file = path.join(FIXTURES, name);
      const now = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
      if (now !== text) { drift++; console.log(`  ✗ ${name} ${now === null ? 'is missing' : 'differs from what the core writes'}`); } else console.log(`  ✓ ${name} matches sidekick-core.js`);
    }
    if (drift) { console.log(`✗ ${drift} fixture file(s) out of date: run node scripts/gen-sidekick-fixtures.mjs`); process.exit(1); }
    console.log(`✓ ${Object.keys(files).length} fixture files match sidekick-core.js`);
    return;
  }
  fs.mkdirSync(outDir, { recursive: true });
  for (const [name, text] of Object.entries(files)) fs.writeFileSync(path.join(outDir, name), text);
  console.log(`wrote ${Object.keys(files).length} fixture files to ${path.relative(ROOT, outDir) || '.'}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(fs.realpathSync(process.argv[1])).href) main(process.argv.slice(2));
```

- [ ] **Step 5: Write the fixture**

Run: `node scripts/gen-sidekick-fixtures.mjs`
Expected: `wrote 1 fixture files to tests/fixtures/sidekick`. If it stops with `the core says ... the case says ...`, stop and report.

- [ ] **Step 6: Run the tests and watch them pass**

Run: `node --test tests/sidekick/*.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)" && bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "✓|✗"`
Expected: PASS: `# tests 8`, `# pass 8`, `# fail 0`, then `✓ explain-cases.json matches sidekick-core.js`, `✓ 1 fixture files match sidekick-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 7: Bite: change a number on purpose and watch the checks catch it**

```bash
BK="$(mktemp -d "${TMPDIR:-/tmp}/nm-bite.XXXXXX")" && cp shared/sidekick-core.js "$BK/"
sed -i '' "s/\['rm_recursive', 'high'/['rm_recursive', 'medium'/" shared/sidekick-core.js
bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|^not ok"
cp "$BK/sidekick-core.js" shared/sidekick-core.js
bash scripts/test-sidekick-contract.sh 2>&1 | tail -2
```

Expected: `not ok` for "the fixture rows are what the core says, row by row" and for "the table is the spec table: 12 high, the medium and the low reasons, every id once" and `# fail 2`; then after the copy back `✓ 1 fixture files match sidekick-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree's folder, and f1-0/sidekick-contract
MSG="$(mktemp "${TMPDIR:-/tmp}/nm-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): the risk rules and the contract script

explain() says in plain words how risky a permission request is: twelve high reasons,
the medium and the low ones, a fixed line with a basename in it. It labels only. The
generator types every answer by hand beside its input, so the fixture is not a copy of
the core. 169 rows, a 3000-input fuzz, and a test that no line carries a command or a path.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add shared/sidekick-core.js \
  scripts/gen-sidekick-fixtures.mjs \
  scripts/test-sidekick-contract.sh \
  tests/sidekick/explain.test.mjs \
  tests/fixtures/sidekick/explain-cases.json
git status --short
git commit -F "$MSG"
```

Expected: `git status --short` lists only the files above (all staged). Never push.

---
### Task 2: `eventFrom` and `ledgerApply`: the adapter and the ledger

**Files:**
- Edit: `shared/sidekick-core.js`, `scripts/gen-sidekick-fixtures.mjs`
- Create: `tests/sidekick/ledger.test.mjs`, and (generated) `tests/fixtures/sidekick/hook-cases.json`

**Interfaces:**
- Consumes: Task 1's `baseName`, `pathsOf` (inside the core), `api.WRITE_TOOLS`, the generator's `SECTIONS`, `expectEqual`, `core`.
- Produces: `eventFrom(payload, now, opts) -> event | null`, `emptyLedger()`, `ledgerApply(ledger, event) -> ledger`, `ledgerPrune(ledger, now)`, `approvalAnsweredEvent(agentId, sessionId, now)`, `liveSessions(ledger)`, `aliveSubagents(session)`, `commandKey(tool, input)`, `fnv1a(text)`, `agentName(agentId)`, `RING_MAX`, `SESSIONS_MAX`. A session is `{key, agentId, sessionId, startedAt, lastEventAt, endedAt, state, last, project, ring, pendingApprovalAt, pendingKey, subagents, nudgedAt}`.

- [ ] **Step 1: Write the test first**

**Create `tests/sidekick/ledger.test.mjs`**

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
const core = createRequire(import.meta.url)('../../shared/sidekick-core.js');
const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/sidekick/hook-cases.json', import.meta.url), 'utf8'));

const T0 = 9_000_000;
const hook = (name, extra = {}) => ({ hook_event_name: name, session_id: 'S1', cwd: '/Users/me/proj', ...extra });
const run = (steps, ledger = core.emptyLedger()) => steps.reduce((l, [at, payload]) => core.ledgerApply(l, core.eventFrom(payload, T0 + at * 1000)), ledger);

test('the fixture: every payload gives the event it records, every sequence the ledger it records', () => {
  for (const c of fx.cases) assert.deepEqual(core.eventFrom(c.payload, c.now, c.opts), c.event, c.name);
  for (const s of fx.sequences) {
    let l = core.emptyLedger();
    for (const st of s.steps) l = core.ledgerApply(l, st.answered ? core.approvalAnsweredEvent(st.answered.agentId, st.answered.sessionId, st.at) : core.eventFrom(st.payload, st.at, st.opts));
    assert.deepEqual(l, s.ledger, s.name);
  }
});

test('the four agents are all there, and the payloads from the docs are marked as such', () => {
  const agents = new Set(fx.cases.map(c => c.event && c.event.agentId));
  for (const a of ['integration_claude', 'agent_codex', 'agent_gemini', 'agent_antigravity', 'agent_cursor']) assert.ok(agents.has(a), a);
  assert.ok(fx.cases.every(c => c.source === 'repo' || c.source === 'docs'));
  for (const name of ['PostToolUseFailure', 'StopFailure', 'Notification', 'SubagentStop']) assert.ok(fx.cases.some(c => c.payload && c.payload.hook_event_name === name), `${name} has a fixture`);
  assert.ok(fx.cases.some(c => c.payload && /^C:\\/.test(c.payload.cwd || '')), 'a Windows-shaped payload');
});

test('the command key: FNV-1a over canonical JSON, pinned', () => {
  assert.equal(core.fnv1a(''), '811c9dc5');
  assert.equal(core.fnv1a('a'), 'e40c292c');
  assert.equal(core.commandKey('Bash', { command: 'ls -la' }), 'Bash#d3abe9d5');
  assert.equal(core.commandKey('Bash', { command: '  ls   -la ' }), 'Bash#d3abe9d5');
  assert.equal(core.commandKey('X', null), 'X#77074ba4');
  assert.equal(core.commandKey('X', { x: [1, 'é', null, true], file_path: '/a' }), 'X#63e27ca3');
  assert.equal(core.commandKey('X', { a: 1, b: 2 }), core.commandKey('X', { b: 2, a: 1 }), 'key order does not matter');
  assert.notEqual(core.commandKey('Bash', { command: 'ls' }), core.commandKey('Read', { command: 'ls' }), 'the tool is part of the key');
});

test('nothing secret reaches an event or the ledger', () => {
  const secrets = ['SECRET-PROMPT', 'SECRET-OUTPUT', 'SECRET-MSG', 'SECRET-CONTENT', 'SECRET-DIR', 'SECRET-CMD', 'SECRET-TRANSCRIPT'];
  const l = run([
    [0, hook('UserPromptSubmit', { prompt: secrets[0], transcript_path: `/Users/me/.claude/${secrets[6]}.jsonl`, cwd: `/Users/${secrets[4]}/proj` })],
    [1, hook('PostToolUse', { tool_name: 'Bash', tool_input: { command: `echo ${secrets[5]}` }, tool_response: { stdout: secrets[1] }, cwd: `/Users/${secrets[4]}/proj` })],
    [2, hook('PostToolUse', { tool_name: 'Write', tool_input: { file_path: `/Users/${secrets[4]}/proj/a.js`, content: secrets[3] }, cwd: `/Users/${secrets[4]}/proj` })],
    [3, hook('PermissionRequest', { tool_name: 'Bash', tool_input: { command: `curl https://${secrets[5]}` }, cwd: `/Users/${secrets[4]}/proj` })],
    [4, hook('Stop', { last_assistant_message: secrets[2], cwd: `/Users/${secrets[4]}/proj` })],
  ]);
  const text = JSON.stringify(l);
  for (const s of secrets) assert.ok(!text.includes(s), `${s} is in the ledger`);
  assert.equal(l.sessions[0].project, 'proj');
  assert.deepEqual(Object.keys(l.sessions[0]).sort(), ['agentId', 'endedAt', 'key', 'last', 'lastEventAt', 'nudgedAt', 'pendingApprovalAt', 'pendingKey', 'project', 'ring', 'sessionId', 'startedAt', 'state', 'subagents']);
  assert.deepEqual(Object.keys(l.sessions[0].ring[0]), ['at', 'kind', 'tool', 'target', 'ok']);
});

test('ledgerApply does not change the ledger it is given, and a bad event changes nothing', () => {
  const l1 = run([[0, hook('PreToolUse', { tool_name: 'Bash', tool_input: { command: 'ls' } })]]);
  const frozen = JSON.stringify(l1);
  const l2 = core.ledgerApply(l1, core.eventFrom(hook('PostToolUse', { tool_name: 'Bash', tool_input: { command: 'ls' } }), T0 + 5000));
  assert.equal(JSON.stringify(l1), frozen);
  assert.notEqual(JSON.stringify(l2), frozen);
  for (const bad of [null, undefined, 5, 'x', {}, { agentId: 'a' }, { agentId: 'a', sessionId: 's', kind: 'tool', at: NaN }, { agentId: 'a', sessionId: 's', kind: 'tool', at: 'now' }]) assert.deepEqual(core.ledgerApply(l1, bad), l1);
  assert.deepEqual(core.ledgerApply(null, null), { sessions: [] });
  assert.deepEqual(core.ledgerApply({ sessions: 'x' }, null), { sessions: [] });
});

test('hostile ids and names: an Object.prototype key is just text', () => {
  const l = run([
    [0, hook('SubagentStart', { session_id: '__proto__', agent_id: '__proto__' })],
    [1, hook('SubagentStart', { session_id: 'constructor', agent_id: 'constructor' })],
    [2, hook('PostToolUse', { session_id: 'toString', tool_name: '__proto__', tool_input: JSON.parse('{"__proto__":{"x":1},"command":"ls"}') })],
  ]);
  assert.equal(l.sessions.length, 3);
  assert.deepEqual(Object.keys(l.sessions[0].subagents), []);
  assert.deepEqual(Object.keys(l.sessions[1].subagents), ['constructor']);
  assert.equal({}.x, undefined);
});

test('the agent names', () => {
  assert.deepEqual(['integration_claude', 'agent_cursor', 'agent_codex', 'agent_gemini', 'agent_antigravity', 'agent_my-tool', 'agent_', 'x', null, '__proto__', 'constructor'].map(core.agentName),
    ['Claude Code', 'Cursor', 'Codex', 'Gemini CLI', 'Antigravity', 'My-tool', 'An agent', 'An agent', 'An agent', 'An agent', 'An agent']);
});

test('a fuzz of 4000 events keeps the invariants: at most 8 sessions, 40 ring entries, keys once, and every ring sorted by time', () => {
  let seed = 7;
  const rnd = n => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  const names = ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'PermissionRequest', 'Stop', 'StopFailure', 'SubagentStart', 'SubagentStop', 'SessionEnd', 'Notification', 'Interrupt', 'Nope'];
  let l = core.emptyLedger(), t = T0;
  for (let i = 0; i < 4000; i++) {
    t += rnd(5) === 0 ? rnd(40) * 60000 : rnd(20) * 1000;
    const p = { hook_event_name: names[rnd(names.length)], session_id: 'S' + rnd(14), cwd: '/p/' + rnd(3), tool_name: ['Bash', 'Edit', 'Grep'][rnd(3)], tool_input: { command: 'c' + rnd(4), file_path: '/p/f' + rnd(4) }, agent_id: 'a' + rnd(3), nm_agent: ['', '', 'gemini'][rnd(3)] };
    const ev = core.eventFrom(p, t);
    if (!ev) continue;
    l = core.ledgerApply(l, rnd(9) === 0 ? core.approvalAnsweredEvent(ev.agentId, ev.sessionId, t) : ev);
    assert.ok(l.sessions.length <= 8);
    assert.equal(new Set(l.sessions.map(s => s.key)).size, l.sessions.length);
    for (const s of l.sessions) {
      assert.ok(s.ring.length <= 40);
      assert.ok(s.ring.every((r, j) => j === 0 || s.ring[j - 1].at <= r.at));
      assert.ok(Object.keys(s.subagents).length <= 20);
      assert.ok(s.startedAt <= s.lastEventAt);
      assert.ok(s.pendingApprovalAt === null || s.state === 'approval' || s.pendingKey !== null);
    }
  }
});

test('liveSessions and aliveSubagents', () => {
  const l = run([[0, hook('SubagentStart', { agent_id: 'a1' })], [1, hook('SessionEnd', { session_id: 'S2' })], [2, hook('PreToolUse', { session_id: 'S2', tool_name: 'Bash', tool_input: { command: 'ls' } })], [3, hook('SessionEnd', { session_id: 'S2' })]]);
  assert.deepEqual(core.liveSessions(l).map(s => s.sessionId), ['S1']);
  assert.equal(core.aliveSubagents(l.sessions[0]), 1);
  assert.equal(core.aliveSubagents(null), 0);
  assert.deepEqual(core.liveSessions(null), []);
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `node --test tests/sidekick/*.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)|ENOENT"`
Expected: FAIL: `ENOENT ... hook-cases.json`, `# tests 9`, `# pass 8`, `# fail 1` (the new file cannot read its fixture).

- [ ] **Step 3: Add the adapter and the ledger to the core**

**Edit `shared/sidekick-core.js`**

Find (it occurs once):

```js
// @@NEXT (the next task's rules go above this line)
```

Replace with:

```js
// ── Task 2: the ledger, and the adapter that feeds it ───────────────────────

const hasOwnKey = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
const AGENT_NAMES = { integration_claude: 'Claude Code', agent_cursor: 'Cursor', agent_codex: 'Codex', agent_gemini: 'Gemini CLI', agent_antigravity: 'Antigravity' };
/** The name of an agent for a person: Claude Code for `integration_claude`, `agent_<tag>` is the tag with a capital, and any other ID is "An agent". */
function agentName(agentId) {
  if (!isStr(agentId)) return 'An agent';
  if (hasOwnKey(AGENT_NAMES, agentId)) return AGENT_NAMES[agentId];
  const tag = agentId.startsWith('agent_') ? agentId.slice(6) : '';
  return tag ? tag[0].toUpperCase() + tag.slice(1) : 'An agent';
}
api.agentName = agentName;

// ── The command key ──────────────────────────────────────────────────────────
/** Canonical JSON: keys sorted (by UTF-16 code unit; the fixtures use ASCII keys), no spaces. A number is written by JSON.stringify, so the fixtures use whole numbers. */
const canon = v => (Array.isArray(v) ? '[' + v.map(canon).join(',') + ']' : isObj(v) ? '{' + Object.keys(v).sort().map(k => JSON.stringify(k) + ':' + canon(v[k])).join(',') + '}' : (JSON.stringify(v) ?? 'null'));
/** FNV-1a, 32 bits, over the UTF-8 bytes of a string (valid Unicode), as 8 lower-case hex digits. */
function fnv1a(s) {
  let h = 0x811c9dc5;
  for (const b of new TextEncoder().encode(s)) { h ^= b; h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16).padStart(8, '0');
}
/** What "the same step" means: the tool name and a hash of its input, whitespace in a command folded. Only the hash is ever stored. */
function commandKey(tool, input) {
  let v = input;
  if (isObj(input) && isStr(input.command)) v = { ...input, command: input.command.trim().replace(/\s+/g, ' ') };
  return `${isStr(tool) ? tool : ''}#${fnv1a(canon(v === undefined ? null : v))}`;
}
api.fnv1a = fnv1a;
api.commandKey = commandKey;

// ── eventFrom: a hook payload becomes a normalised event ─────────────────────
const CURSOR_BUNDLE = 'com.todesktop.230313mzl4w4u92';
/** Both the names the relays send and the agents' own (the Mac relay renames BeforeTool to PreToolUse and so on; the Windows one may not). */
const EVENT_KIND = {
  SessionStart: 'sessionStart', startup: 'sessionStart',
  UserPromptSubmit: 'prompt', BeforeAgent: 'prompt', PreInvocation: 'prompt',
  PreToolUse: 'preTool', BeforeTool: 'preTool',
  PostToolUse: 'tool', AfterTool: 'tool',
  PostToolUseFailure: 'failure',
  PermissionRequest: 'approvalAsked',
  Stop: 'stop', AfterAgent: 'stop', PostInvocation: 'stop', Interrupt: 'stop',
  StopFailure: 'stopFailure',
  SubagentStart: 'subagentStart', SubagentStop: 'subagentStop',
  SessionEnd: 'sessionEnd', exit: 'sessionEnd',
  Notification: 'notification',
};
/** Which pill a payload belongs to: a valid `nm_agent` (not "claude"), Codex in the GitHub build, Cursor by its bundle ID, else Claude Code. */
function agentIdOf(payload, opts) {
  const tag = isStr(payload.nm_agent) ? payload.nm_agent : '';
  if (tag === 'codex' && !(opts && opts.codex === false)) return 'agent_codex';
  if (tag !== 'claude' && /^[a-z0-9-]{1,24}$/.test(tag)) return 'agent_' + tag;
  if (isStr(payload.bundle_id) && payload.bundle_id.toLowerCase() === CURSOR_BUNDLE) return 'agent_cursor';
  return 'integration_claude';
}
/**
 * Turns a hook payload into the event the ledger takes, or null for an event it does not know. `now` is the time the app received it (ms). `opts.codex` is false in
 * the App Store build. The event holds a basename, a command key and counts, never the prompt, the assistant's text, a command or a path.
 */
function eventFrom(payload, now, opts) {
  if (!isObj(payload) || !isNum(now)) return null;
  const name = isStr(payload.hook_event_name) ? payload.hook_event_name : '';
  if (!hasOwnKey(EVENT_KIND, name)) return null;
  let kind = EVENT_KIND[name];
  const tool = isStr(payload.tool_name) ? payload.tool_name : '';
  const input = isObj(payload.tool_input) ? payload.tool_input : {};
  if (tool === 'AskUserQuestion' && (kind === 'preTool' || kind === 'approvalAsked')) kind = 'question';
  const sessionId = [payload.session_id, payload.conversation_id].find(x => isStr(x) && x) || 'unknown';
  const cwd = isStr(payload.cwd) ? payload.cwd : '';
  const ev = { at: now, agentId: agentIdOf(payload, opts), sessionId, kind, name, tool, target: '', file: '', key: '', ok: kind !== 'failure' && kind !== 'stopFailure', project: cwd ? baseName(cwd) : '', subagentId: '' };
  if (kind === 'tool' || kind === 'failure' || kind === 'approvalAsked' || kind === 'preTool' || kind === 'question') {
    const files = pathsOf(tool, input);
    ev.key = commandKey(tool, input);
    ev.target = files.length ? baseName(files[0]) : ev.key;
  }
  if (kind === 'subagentStart' || kind === 'subagentStop') ev.subagentId = isStr(payload.agent_id) ? payload.agent_id : '';
  return ev;
}
api.eventFrom = eventFrom;
/** The event for the user's click on an approval card: the app makes it (it is not a hook). */
api.approvalAnsweredEvent = (agentId, sessionId, now) => ({ at: now, agentId, sessionId, kind: 'approvalAnswered', name: '', tool: '', target: '', key: '', ok: true, project: '', subagentId: '' });

// ── The ledger ───────────────────────────────────────────────────────────────
const RING_MAX = 40, SESSIONS_MAX = 8, ENDED_KEEP_MS = 30 * MIN, SILENT_KEEP_MS = 12 * 60 * MIN, SUBAGENTS_MAX = 20;
const SEARCH_SET = new Set(['WebSearch', 'WebFetch', 'Grep', 'Glob', 'google_web_search', 'web_fetch', 'grep_search', 'search_file_content', 'glob', 'web_search', 'grep_files']);
/** The state a tool puts an agent in: a search tool is searching, any other is working (the cat's rule, design/prototype/cat-core.js). */
const toolState = t => (SEARCH_SET.has(t) ? 'searching' : 'working');
api.RING_MAX = RING_MAX; api.SESSIONS_MAX = SESSIONS_MAX;

api.emptyLedger = () => ({ sessions: [] });
const newSession = (ev, key) => ({ key, agentId: ev.agentId, sessionId: ev.sessionId, startedAt: ev.at, lastEventAt: ev.at, endedAt: null, state: 'idle', last: 'sessionStart', project: '', ring: [], pendingApprovalAt: null, pendingKey: null, subagents: {}, nudgedAt: null });
const copy = s => JSON.parse(JSON.stringify(s));
const isDone = s => s.endedAt !== null || s.state === 'finished' || s.state === 'error';

/** Drops the sessions that are over: 30 minutes after SessionEnd, 12 hours after the last event of one that never ended. */
function ledgerPrune(ledger, now) {
  const sessions = (isObj(ledger) && Array.isArray(ledger.sessions) ? ledger.sessions : []).filter(s => (s.endedAt !== null ? now - s.endedAt <= ENDED_KEEP_MS : now - s.lastEventAt <= SILENT_KEEP_MS));
  return { sessions };
}
api.ledgerPrune = ledgerPrune;

function applyEvent(s, ev) {
  s.lastEventAt = Math.max(s.lastEventAt, ev.at);
  if (ev.project) s.project = ev.project;
  if (s.endedAt !== null && ev.kind !== 'sessionEnd') { s.endedAt = null; }
  const ring = (kind, o = {}) => { s.ring.push({ at: ev.at, kind, tool: ev.tool, target: ev.target, file: ev.file, key: ev.key, ok: true, ...o }); if (s.ring.length > RING_MAX) s.ring.splice(0, s.ring.length - RING_MAX); };
  const clearPending = () => { s.pendingApprovalAt = null; s.pendingKey = null; };
  switch (ev.kind) {
    case 'sessionStart': s.state = 'idle'; clearPending(); break;
    case 'prompt': s.state = 'thinking'; clearPending(); break;
    case 'preTool': s.state = toolState(ev.tool); break;
    case 'question': s.state = 'question'; break;
    case 'tool': case 'failure':
      ring(ev.kind, { ok: ev.kind === 'tool' });
      if (s.pendingKey !== null && ev.key === s.pendingKey) clearPending();
      if (s.pendingKey === null) s.state = 'thinking';   // while another request still waits, the cat stays on it
      break;
    case 'approvalAsked': ring('approvalAsked'); s.pendingApprovalAt = ev.at; s.pendingKey = ev.key; s.state = 'approval'; break;
    case 'approvalAnswered': ring('approvalAnswered', { tool: '', target: '' }); clearPending(); if (s.state === 'approval') s.state = 'working'; break;
    case 'stop': ring('stop', { tool: '', target: '' }); s.state = 'finished'; clearPending(); s.subagents = {}; break;
    case 'stopFailure': ring('stopFailure', { tool: '', target: '', ok: false }); s.state = 'error'; clearPending(); s.subagents = {}; break;
    case 'subagentStart': {
      ring('subagentStart', { tool: '', target: '' });
      if (ev.subagentId && ev.subagentId !== '__proto__') { s.subagents[ev.subagentId] = ev.at; const ids = Object.keys(s.subagents); if (ids.length > SUBAGENTS_MAX) delete s.subagents[ids.sort((a, b) => s.subagents[a] - s.subagents[b])[0]]; }
      break;
    }
    case 'subagentStop': ring('subagentStop', { tool: '', target: '' }); delete s.subagents[ev.subagentId]; break;
    case 'sessionEnd': s.endedAt = ev.at; s.state = 'finished'; clearPending(); s.subagents = {}; break;
    default: return;   // notification: only the time of the last event moves
  }
  s.last = ev.kind;
}

/**
 * The ledger after one event. Pure: the ledger it is given is not changed. The key of a session is `agentId|sessionId`. At most 8 sessions are kept (a finished one goes
 * first, the oldest first), each ring keeps its last 40 entries, and the ledger holds no prompt, no text of the assistant, no command, no full path and no file content.
 */
function ledgerApply(ledger, ev) {
  const base = ledger && Array.isArray(ledger.sessions) ? ledger : { sessions: [] };
  if (!isObj(ev) || !isStr(ev.agentId) || !isStr(ev.sessionId) || !isStr(ev.kind) || !isNum(ev.at)) return base;
  const key = `${ev.agentId}|${ev.sessionId}`;
  const sessions = ledgerPrune(base, ev.at).sessions;
  const i = sessions.findIndex(s => s.key === key);
  if (i < 0 && ev.kind === 'sessionEnd') return { sessions };
  const s = i >= 0 ? copy(sessions[i]) : newSession(ev, key);
  applyEvent(s, ev);
  if (i >= 0) sessions[i] = s; else sessions.push(s);
  while (sessions.length > SESSIONS_MAX) {
    const victims = sessions.map((x, j) => ({ x, j })).filter(v => v.x.key !== key);
    const pool = victims.filter(v => isDone(v.x));
    const pick = (pool.length ? pool : victims).reduce((a, b) => (b.x.lastEventAt < a.x.lastEventAt ? b : a));
    sessions.splice(pick.j, 1);
  }
  return { sessions };
}
api.ledgerApply = ledgerApply;
/** The sessions of a ledger that have not ended, as the status answer and the recap's "still working" see them. */
api.liveSessions = ledger => (isObj(ledger) && Array.isArray(ledger.sessions) ? ledger.sessions.filter(s => s.endedAt === null) : []);
api.aliveSubagents = s => Object.keys(isObj(s && s.subagents) ? s.subagents : {}).length;

// @@NEXT (the next task's rules go above this line)
```

- [ ] **Step 4: Add the hook cases to the generator**

The payloads are marked `repo` (a shape the app already sends) or `docs` (only the agent's documentation shows it): replace a `docs` payload with a captured one when there is one.

**Edit `scripts/gen-sidekick-fixtures.mjs`**

Find (it occurs once):

```js
// @@SECTIONS (the next task's fixtures go above this line)
```

Replace with:

```js
// ── hook-cases.json: hook payloads become events, events fill the ledger ─────
// `source` says where a payload's shape comes from: "repo" is an event the app's own scenarios and QA brief already send (tests/fixtures/mac/subagent-scenarios.json,
// docs/QA-MAC.md), "docs" is the agent's documentation, written down before any real session was captured. Replace a "docs" payload with a captured one when there is one.
SECTIONS['hook-cases.json'] = () => {
  const NOW = 1_000_000;
  const rows = [];
  const hook = (name, source, payload, expect, o = {}) => rows.push({ name, source, payload, expect, ...o });
  const claude = (event, ...extras) => ({ hook_event_name: event, session_id: 'S1', cwd: '/Users/me/proj', term_program: 'vscode', ...Object.assign({}, ...extras) });
  const bash = command => ({ tool_name: 'Bash', tool_input: { command } });
  const PROJ = 'proj';

  // [agentId, kind, tool, target, project, sessionId]; a target of 'KEY' means the command key of the tool and its input
  hook('Claude Code: a session starts', 'repo', claude('SessionStart', { source: 'startup' }), ['integration_claude', 'sessionStart', '', '', PROJ, 'S1']);
  hook('Claude Code: a prompt is kept out of the event', 'repo', claude('UserPromptSubmit', { prompt: 'NM-QA: say hello' }), ['integration_claude', 'prompt', '', '', PROJ, 'S1']);
  hook('Claude Code: a step begins', 'repo', claude('PreToolUse', bash('echo NM-QA step')), ['integration_claude', 'preTool', 'Bash', 'KEY', PROJ, 'S1']);
  hook('Claude Code: a step ends, the output is kept out', 'docs', claude('PostToolUse', { ...bash('echo NM-QA step'), tool_response: { stdout: 'SECRET-OUTPUT' } }), ['integration_claude', 'tool', 'Bash', 'KEY', PROJ, 'S1']);
  hook('Claude Code: a step ends, extra spaces in the command do not make another step', 'docs', claude('PostToolUse', bash('echo   NM-QA   step ')), ['integration_claude', 'tool', 'Bash', 'KEY', PROJ, 'S1']);
  hook('Claude Code: a file is written, the content is kept out', 'repo', claude('PostToolUse', { tool_name: 'Write', tool_input: { file_path: '/Users/me/proj/src/a.js', content: 'SECRET-CONTENT' } }), ['integration_claude', 'tool', 'Write', 'a.js', PROJ, 'S1']);
  hook('Claude Code: a file is edited, only its name is kept', 'repo', claude('PostToolUse', { tool_name: 'Edit', tool_input: { file_path: '/Users/me/proj/src/b.js', old_string: 'SECRET-OLD', new_string: 'SECRET-NEW' } }), ['integration_claude', 'tool', 'Edit', 'b.js', PROJ, 'S1']);
  hook('Claude Code: a step fails', 'docs', claude('PostToolUseFailure', { ...bash('npm test'), error: 'Command failed with exit code 1', is_interrupt: false }), ['integration_claude', 'failure', 'Bash', 'KEY', PROJ, 'S1']);
  hook('Claude Code: a permission request', 'repo', claude('PermissionRequest', bash('echo NM-QA-APPROVAL')), ['integration_claude', 'approvalAsked', 'Bash', 'KEY', PROJ, 'S1']);
  hook('Claude Code: a question is not a permission request', 'repo', claude('PreToolUse', { tool_name: 'AskUserQuestion', tool_input: { questions: [{ question: 'NM-QA: which cat?', options: [] }] } }), ['integration_claude', 'question', 'AskUserQuestion', 'KEY', PROJ, 'S1']);
  hook('Claude Code: a question asked as a permission request', 'repo', claude('PermissionRequest', { tool_name: 'AskUserQuestion', tool_input: { questions: [] } }), ['integration_claude', 'question', 'AskUserQuestion', 'KEY', PROJ, 'S1']);
  hook('Claude Code: the turn ends, the last message is kept out', 'repo', claude('Stop', { last_assistant_message: 'NM-QA done.' }), ['integration_claude', 'stop', '', '', PROJ, 'S1']);
  hook('Claude Code: the turn fails', 'docs', claude('StopFailure', { error: 'rate_limit' }), ['integration_claude', 'stopFailure', '', '', PROJ, 'S1']);
  hook('Claude Code: a subagent starts', 'repo', claude('SubagentStart', { agent_id: 'a1', agent_type: 'Explore' }), ['integration_claude', 'subagentStart', '', '', PROJ, 'S1']);
  hook('Claude Code: a subagent stops', 'docs', claude('SubagentStop', { agent_id: 'a1', agent_type: 'Explore' }), ['integration_claude', 'subagentStop', '', '', PROJ, 'S1']);
  hook('Claude Code: a notification only moves the clock', 'docs', claude('Notification', { message: 'Claude needs your permission', notification_type: 'permission_prompt' }), ['integration_claude', 'notification', '', '', PROJ, 'S1']);
  hook('Claude Code: the session ends', 'repo', claude('SessionEnd'), ['integration_claude', 'sessionEnd', '', '', PROJ, 'S1']);
  hook('Claude Code: a session with no id is "unknown"', 'repo', { hook_event_name: 'Stop', cwd: '/Users/me/proj' }, ['integration_claude', 'stop', '', '', PROJ, 'unknown']);
  hook('Claude Code: no folder, no project', 'repo', { hook_event_name: 'Stop', session_id: 'S9' }, ['integration_claude', 'stop', '', '', '', 'S9']);
  hook('Cursor is told apart by its bundle ID', 'repo', claude('PreToolUse', { ...bash('ls'), bundle_id: 'com.todesktop.230313mzl4w4u92' }), ['agent_cursor', 'preTool', 'Bash', 'KEY', PROJ, 'S1']);
  hook('Cursor in capitals is still Cursor', 'repo', claude('PreToolUse', { ...bash('ls'), bundle_id: 'COM.TODESKTOP.230313MZL4W4U92' }), ['agent_cursor', 'preTool', 'Bash', 'KEY', PROJ, 'S1']);
  hook('another ToDesktop app is not Cursor', 'repo', claude('PreToolUse', { ...bash('ls'), bundle_id: 'com.todesktop.999999' }), ['integration_claude', 'preTool', 'Bash', 'KEY', PROJ, 'S1']);

  hook('Codex: a shell step', 'docs', { hook_event_name: 'PreToolUse', session_id: 'C1', cwd: '/Users/me/proj', nm_agent: 'codex', tool_name: 'Bash', tool_input: { command: 'ls -la' } }, ['agent_codex', 'preTool', 'Bash', 'KEY', PROJ, 'C1']);
  hook('Codex: a patch names its files, not their content', 'docs', { hook_event_name: 'PostToolUse', session_id: 'C1', cwd: '/Users/me/proj', nm_agent: 'codex', tool_name: 'apply_patch', tool_input: { command: '*** Begin Patch\n*** Update File: src/a.js\n@@\n-SECRET-OLD\n+SECRET-NEW\n*** End Patch' } }, ['agent_codex', 'tool', 'apply_patch', 'a.js', PROJ, 'C1']);
  hook('Codex: a permission request', 'docs', { hook_event_name: 'PermissionRequest', session_id: 'C1', cwd: '/Users/me/proj', nm_agent: 'codex', tool_name: 'Bash', tool_input: { command: 'git push' } }, ['agent_codex', 'approvalAsked', 'Bash', 'KEY', PROJ, 'C1']);
  hook('Codex: an interrupt is a stop', 'docs', { hook_event_name: 'Interrupt', session_id: 'C1', cwd: '/Users/me/proj', nm_agent: 'codex' }, ['agent_codex', 'stop', '', '', PROJ, 'C1']);
  hook('Codex in the App Store build is an ordinary agent', 'docs', { hook_event_name: 'PreToolUse', session_id: 'C1', cwd: '/Users/me/proj', nm_agent: 'codex', tool_name: 'Bash', tool_input: { command: 'ls' } }, ['agent_codex', 'preTool', 'Bash', 'KEY', PROJ, 'C1'], { opts: { codex: false } });

  hook('Gemini: the agent starts (its own name for a prompt)', 'docs', { hook_event_name: 'BeforeAgent', session_id: 'G1', cwd: '/Users/me/proj', nm_agent: 'gemini', prompt: 'SECRET-PROMPT' }, ['agent_gemini', 'prompt', '', '', PROJ, 'G1']);
  hook('Gemini: a tool begins (the relay already calls it PreToolUse)', 'docs', { hook_event_name: 'PreToolUse', session_id: 'G1', cwd: '/Users/me/proj', nm_agent: 'gemini', tool_name: 'run_shell_command', tool_input: { command: 'ls' } }, ['agent_gemini', 'preTool', 'run_shell_command', 'KEY', PROJ, 'G1']);
  hook('Gemini: a tool ends (its own name AfterTool)', 'docs', { hook_event_name: 'AfterTool', session_id: 'G1', cwd: '/Users/me/proj', nm_agent: 'gemini', tool_name: 'write_file', tool_input: { file_path: '/Users/me/proj/c.md', content: 'SECRET' }, tool_response: { ok: true } }, ['agent_gemini', 'tool', 'write_file', 'c.md', PROJ, 'G1']);
  hook('Gemini: the agent ends (its own name AfterAgent)', 'docs', { hook_event_name: 'AfterAgent', session_id: 'G1', cwd: '/Users/me/proj', nm_agent: 'gemini', prompt_response: 'SECRET' }, ['agent_gemini', 'stop', '', '', PROJ, 'G1']);

  hook('Antigravity: a tool begins, in the relay\'s mapped shape', 'docs', { hook_event_name: 'PreToolUse', session_id: 'conv-1', conversation_id: 'conv-1', cwd: '/Users/me/proj', nm_agent: 'antigravity', tool_name: 'run_command', tool_input: { CommandLine: 'ls', command: 'ls' } }, ['agent_antigravity', 'preTool', 'run_command', 'KEY', PROJ, 'conv-1']);
  hook('Antigravity: only a conversation id', 'docs', { hook_event_name: 'Stop', conversation_id: 'conv-2', cwd: '/Users/me/proj', nm_agent: 'antigravity' }, ['agent_antigravity', 'stop', '', '', PROJ, 'conv-2']);
  hook('Antigravity: the end of an invocation, before the relay renames it', 'docs', { hook_event_name: 'PostInvocation', session_id: 'conv-1', cwd: '/Users/me/proj', nm_agent: 'antigravity' }, ['agent_antigravity', 'stop', '', '', PROJ, 'conv-1']);

  hook('Windows: a backslash folder and a command cut at 2000 bytes', 'docs', { hook_event_name: 'PostToolUse', session_id: 'W1', cwd: 'C:\\Users\\me\\proj', term_program: 'WindowsTerminal', tool_name: 'Bash', tool_input: { command: 'echo ' + 'x'.repeat(1995) } }, ['integration_claude', 'tool', 'Bash', 'KEY', PROJ, 'W1']);
  hook('Windows: a file with backslashes', 'docs', { hook_event_name: 'PostToolUse', session_id: 'W1', cwd: 'C:\\Users\\me\\proj', tool_name: 'Edit', tool_input: { file_path: 'C:\\Users\\me\\proj\\src\\a.ts' } }, ['integration_claude', 'tool', 'Edit', 'a.ts', PROJ, 'W1']);
  hook('Windows: a PowerShell step', 'docs', { hook_event_name: 'PreToolUse', session_id: 'W1', cwd: 'C:\\Users\\me\\proj', tool_name: 'PowerShell', tool_input: { command: 'Get-ChildItem' } }, ['integration_claude', 'preTool', 'PowerShell', 'KEY', PROJ, 'W1']);

  hook('a reserved name is not an agent', 'repo', claude('Stop', { nm_agent: 'claude' }), ['integration_claude', 'stop', '', '', PROJ, 'S1']);
  hook('a name with a capital is not an agent', 'repo', claude('Stop', { nm_agent: 'Gemini' }), ['integration_claude', 'stop', '', '', PROJ, 'S1']);
  hook('a name of 25 characters is not an agent', 'repo', claude('Stop', { nm_agent: 'a'.repeat(25) }), ['integration_claude', 'stop', '', '', PROJ, 'S1']);
  hook('a name of 24 characters is', 'repo', claude('Stop', { nm_agent: 'a'.repeat(24) }), ['agent_' + 'a'.repeat(24), 'stop', '', '', PROJ, 'S1']);
  hook('a made-up agent with digits and hyphens', 'repo', claude('Stop', { nm_agent: 'my-tool-2' }), ['agent_my-tool-2', 'stop', '', '', PROJ, 'S1']);
  hook('a tool name that is not text is no tool', 'repo', claude('PostToolUse', { tool_name: 7, tool_input: { command: 'ls' } }), ['integration_claude', 'tool', '', 'KEY', PROJ, 'S1']);
  hook('a tool input that is not an object is no input', 'repo', claude('PostToolUse', { tool_name: 'Bash', tool_input: 'ls' }), ['integration_claude', 'tool', 'Bash', 'KEY', PROJ, 'S1']);

  const unknown = (name, payload, o) => rows.push({ name, source: 'repo', payload, expect: null, ...o });
  unknown('an event the ledger does not know', claude('SomethingNew'));
  unknown('an event with no name', { session_id: 'S1' });
  unknown('a name that is not text', { hook_event_name: 5 });
  unknown('a payload that is not an object: null', null);
  unknown('a payload that is not an object: text', 'Stop');
  unknown('a payload that is not an object: a list', []);
  unknown('a name that is an Object.prototype key', { hook_event_name: 'constructor' });
  unknown('a time that is not a number', claude('Stop'), { now: 'later' });

  const events = rows.map(r => {
    const now = r.now ?? NOW;
    const ev = core.eventFrom(r.payload, now, r.opts);
    if (r.expect === null) expectEqual(r.name, ev, null);
    else {
      const key = core.commandKey(r.payload.tool_name, isObj(r.payload.tool_input) ? r.payload.tool_input : {});
      const want = [...r.expect]; if (want[3] === 'KEY') want[3] = key;
      if (!ev) throw new Error(`${r.name}: the core returns no event`);
      expectEqual(r.name, [ev.agentId, ev.kind, ev.tool, ev.target, ev.project, ev.sessionId], want);
      for (const secret of ['SECRET', 'NM-QA: say hello', 'NM-QA done', 'NM-QA: which cat']) if (JSON.stringify(ev).includes(secret)) throw new Error(`${r.name}: the event holds ${secret}`);
    }
    const c = { name: r.name, source: r.source, now, payload: r.payload };
    if (r.opts) c.opts = r.opts;
    return { ...c, event: ev };
  });

  // The ledger: a list of steps, each a hook payload (with its time) or the user's click on an approval card.
  const seqs = [];
  const seq = (name, steps, expect) => {
    let ledger = core.emptyLedger();
    for (const st of steps) {
      const ev = st.answered ? core.approvalAnsweredEvent(st.answered.agentId, st.answered.sessionId, st.at) : core.eventFrom(st.payload, st.at, st.opts);
      if (!ev) throw new Error(`${name}: a step is not an event`);
      ledger = core.ledgerApply(ledger, ev);
    }
    expectEqual(name, expect.get(ledger), expect.want);
    seqs.push({ name, steps: steps.map(st => (st.answered ? { at: st.at, answered: st.answered } : { at: st.at, payload: st.payload, ...(st.opts ? { opts: st.opts } : {}) })), ledger });
  };
  const T0 = 5_000_000, sec = n => T0 + n * 1000;
  const at = (n, payload) => ({ at: sec(n), payload });

  seq('a Claude Code turn: tools, an approval, an answer, a stop', [
    at(0, claude('SessionStart')), at(1, claude('UserPromptSubmit', { prompt: 'SECRET-PROMPT' })),
    at(2, claude('PreToolUse', bash('ls'))), at(3, claude('PostToolUse', bash('ls'))),
    at(4, claude('PostToolUse', { tool_name: 'Edit', tool_input: { file_path: '/Users/me/proj/a.js' } })),
    at(5, claude('PermissionRequest', bash('git push'))), { at: sec(9), answered: { agentId: 'integration_claude', sessionId: 'S1' } },
    at(10, claude('PostToolUse', bash('git push'))), at(11, claude('Stop', { last_assistant_message: 'SECRET' })),
  ], { get: l => [l.sessions.length, l.sessions[0].state, l.sessions[0].last, l.sessions[0].ring.map(r => r.kind).join(), l.sessions[0].pendingApprovalAt, l.sessions[0].project], want: [1, 'finished', 'stop', 'tool,tool,approvalAsked,approvalAnswered,tool,stop', null, 'proj'] });

  seq('the cat state follows the tool: a search tool is searching', [
    at(0, claude('SessionStart')), at(1, claude('PreToolUse', { tool_name: 'Grep', tool_input: { pattern: 'x' } })),
  ], { get: l => [l.sessions[0].state, l.sessions[0].last, l.sessions[0].ring.length], want: ['searching', 'preTool', 0] });

  seq('a pending approval is cleared by the same step finishing, not by another', [
    at(0, claude('PermissionRequest', bash('npm test'))), at(1, claude('PostToolUse', bash('ls'))), at(2, claude('PostToolUse', bash('npm   test'))),
  ], { get: l => [l.sessions[0].pendingApprovalAt, l.sessions[0].pendingKey], want: [null, null] });

  seq('a pending approval survives another step finishing', [
    at(0, claude('PermissionRequest', bash('npm test'))), at(1, claude('PostToolUse', bash('ls'))),
  ], { get: l => [l.sessions[0].pendingApprovalAt, l.sessions[0].state], want: [sec(0), 'approval'] });

  seq('a failure and a stop failure', [
    at(0, claude('PostToolUseFailure', bash('npm test'))), at(1, claude('PostToolUseFailure', bash('npm test'))), at(2, claude('StopFailure', { error: 'rate_limit' })),
  ], { get: l => [l.sessions[0].state, l.sessions[0].ring.map(r => `${r.kind}:${r.ok}`).join()], want: ['error', 'failure:false,failure:false,stopFailure:false'] });

  seq('subagents come and go, and the parent\'s stop takes the rest', [
    at(0, claude('SubagentStart', { agent_id: 'a1' })), at(1, claude('SubagentStart', { agent_id: 'a2' })), at(2, claude('SubagentStop', { agent_id: 'a1' })),
  ], { get: l => [Object.keys(l.sessions[0].subagents).join(), l.sessions[0].subagents.a2], want: ['a2', sec(1)] });
  seq('the parent\'s stop ends the subagents that never stopped', [
    at(0, claude('SubagentStart', { agent_id: 'a1' })), at(1, claude('Stop')),
  ], { get: l => [Object.keys(l.sessions[0].subagents).length, l.sessions[0].state], want: [0, 'finished'] });

  seq('two agents, two sessions, one ledger', [
    at(0, claude('PreToolUse', bash('ls'))), at(1, { hook_event_name: 'PreToolUse', session_id: 'G1', cwd: '/Users/me/other', nm_agent: 'gemini', tool_name: 'run_shell_command', tool_input: { command: 'ls' } }),
    at(2, claude('PreToolUse', bash('ls'), { session_id: 'S2' })),
  ], { get: l => l.sessions.map(s => s.key + ':' + s.project), want: ['integration_claude|S1:proj', 'agent_gemini|G1:other', 'integration_claude|S2:proj'] });

  seq('the ring keeps the last 40 entries', Array.from({ length: 50 }, (_, i) => at(i, claude('PostToolUse', { tool_name: 'Read', tool_input: { file_path: `/Users/me/proj/f${i}.txt` } }))),
    { get: l => [l.sessions[0].ring.length, l.sessions[0].ring[0].target, l.sessions[0].ring[39].target], want: [40, 'f10.txt', 'f49.txt'] });

  seq('only eight sessions are kept: a finished one goes first, the oldest first', [
    ...Array.from({ length: 8 }, (_, i) => at(i, claude('PreToolUse', bash('ls'), { session_id: 'S' + i }))),
    at(20, claude('Stop', {}, { session_id: 'S3' })), at(21, claude('Stop', {}, { session_id: 'S5' })),
    at(30, claude('PreToolUse', bash('ls'), { session_id: 'N1' })), at(31, claude('PreToolUse', bash('ls'), { session_id: 'N2' })),
  ], { get: l => [l.sessions.length, l.sessions.map(s => s.sessionId).join()], want: [8, 'S0,S1,S2,S4,S6,S7,N1,N2'] });

  seq('with no finished session the oldest by its last event goes', [
    ...Array.from({ length: 8 }, (_, i) => at(i, claude('PreToolUse', bash('ls'), { session_id: 'S' + i }))),
    at(10, claude('PreToolUse', bash('ls'), { session_id: 'S0' })), at(11, claude('PreToolUse', bash('ls'), { session_id: 'N1' })),
  ], { get: l => [l.sessions.length, l.sessions.map(s => s.sessionId).join()], want: [8, 'S0,S2,S3,S4,S5,S6,S7,N1'] });

  seq('a session that ended is dropped 30 minutes later, at the next event', [
    at(0, claude('PreToolUse', bash('ls'))), at(10, claude('SessionEnd')), { at: sec(10) + 31 * 60000, payload: claude('PreToolUse', bash('ls'), { session_id: 'S2' }) },
  ], { get: l => l.sessions.map(s => s.sessionId).join(), want: 'S2' });

  seq('a session that ended 29 minutes ago is still there', [
    at(0, claude('PreToolUse', bash('ls'))), at(10, claude('SessionEnd')), { at: sec(10) + 29 * 60000, payload: claude('PreToolUse', bash('ls'), { session_id: 'S2' }) },
  ], { get: l => l.sessions.map(s => s.sessionId + ':' + (s.endedAt !== null)).join(), want: 'S1:true,S2:false' });

  seq('a session with no SessionEnd is dropped 12 hours after its last event', [
    at(0, claude('PreToolUse', bash('ls'))), { at: sec(0) + 12 * 3600000 + 1, payload: claude('PreToolUse', bash('ls'), { session_id: 'S2' }) },
  ], { get: l => l.sessions.map(s => s.sessionId).join(), want: 'S2' });

  seq('a session that comes back after it ended is open again', [
    at(0, claude('PreToolUse', bash('ls'))), at(1, claude('SessionEnd')), at(2, claude('UserPromptSubmit')),
  ], { get: l => [l.sessions.length, l.sessions[0].endedAt, l.sessions[0].state], want: [1, null, 'thinking'] });

  seq('a SessionEnd for a session nobody knows makes none', [at(0, claude('SessionEnd'))], { get: l => l.sessions.length, want: 0 });

  return { version: 1, note: 'eventFrom(payload, now, opts) -> the event (or null); ledgerApply folds events into the ledger. `source` is "repo" for a shape the app already sends and "docs" for one only the agent\'s documentation shows. `now` is the time the app received the event, in ms.', cases: events, sequences: seqs };
};

// @@SECTIONS (the next task's fixtures go above this line)
```

- [ ] **Step 5: Write the fixture**

Run: `node scripts/gen-sidekick-fixtures.mjs`
Expected: `wrote 2 fixture files to tests/fixtures/sidekick`.

- [ ] **Step 6: Run the tests and watch them pass**

Run: `node --test tests/sidekick/*.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)" && bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "✓|✗"`
Expected: PASS: `# tests 17`, `# pass 17`, `# fail 0`, then a `✓` line for each of the two files, `✓ 2 fixture files match sidekick-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 7: Bite: change a number on purpose and watch the checks catch it**

```bash
BK="$(mktemp -d "${TMPDIR:-/tmp}/nm-bite.XXXXXX")" && cp shared/sidekick-core.js "$BK/"
sed -i '' "s/RING_MAX = 40, /RING_MAX = 41, /" shared/sidekick-core.js
bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|^not ok"
cp "$BK/sidekick-core.js" shared/sidekick-core.js
bash scripts/test-sidekick-contract.sh 2>&1 | tail -2
```

Expected: `not ok` for "the fixture: every payload gives the event it records, every sequence the ledger it records" and `# fail 1`; then after the copy back `✓ 2 fixture files match sidekick-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree's folder, and f1-0/sidekick-contract
MSG="$(mktemp "${TMPDIR:-/tmp}/nm-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): the hook adapter and the session ledger

eventFrom() turns a hook payload of any of the four agents (and the Windows shape) into a
normalised event with a basename and a command key; ledgerApply() folds events into a
memory-only ledger of at most 8 sessions with a ring of 40 entries. No prompt, text,
command, path or content is kept; a test plants markers to prove it.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add shared/sidekick-core.js \
  scripts/gen-sidekick-fixtures.mjs \
  tests/sidekick/ledger.test.mjs \
  tests/fixtures/sidekick/hook-cases.json
git status --short
git commit -F "$MSG"
```

Expected: `git status --short` lists only the files above (all staged). Never push.

---
### Task 3: `stuckStep`: the four nudges

**Files:**
- Edit: `shared/sidekick-core.js`, `scripts/gen-sidekick-fixtures.mjs`
- Create: `tests/sidekick/stuck.test.mjs`, and (generated) `tests/fixtures/sidekick/stuck-cases.json`

**Interfaces:**
- Consumes: Task 2's ledger sessions (`ring`, `state`, `last`, `pendingApprovalAt`, `subagents`, `nudgedAt`), `agentName`, `copy`, `ACTIVE_STATES` (defined here), `api.WRITE_TOOLS`.
- Produces: `stuckStep(ledger, now, ctx) -> {nudge, nextAt}` (`nudge` is `{kind, reasonId, key, agentId}` or null), `nudgeText(nudge, ledger, now, ctx)`, `markNudged(ledger, key, now)`, `STUCK` (the thresholds), `NUDGE_KINDS`.

- [ ] **Step 1: Write the test first**

**Create `tests/sidekick/stuck.test.mjs`**

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
const core = createRequire(import.meta.url)('../../shared/sidekick-core.js');
const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/sidekick/stuck-cases.json', import.meta.url), 'utf8'));

test('the fixture: every timeline gives the nudges, the deadlines and the words it records', () => {
  for (const c of fx.cases) {
    let ledger = core.emptyLedger();
    for (const st of c.steps) {
      if (st.payload) { ledger = core.ledgerApply(ledger, core.eventFrom(st.payload, st.at)); continue; }
      const ctx = st.probe.ctx, r = core.stuckStep(ledger, st.at, ctx);
      assert.deepEqual([r.nudge, r.nextAt], [st.nudge, st.nextAt], `${c.name} @${st.at}`);
      assert.equal(r.nudge ? core.nudgeText(r.nudge, ledger, st.at, ctx) : null, st.text, `${c.name} @${st.at} words`);
      if (st.probe.mark && r.nudge) ledger = core.markNudged(ledger, r.nudge.key, st.at);
    }
  }
});

test('the thresholds are the spec\'s', () => {
  assert.deepEqual(core.STUCK, { LOOP_CALLS: 8, LOOP_SAME: 4, WINDOW_MS: 600000, ERRORS: 3, WAIT_MS: 60000, SILENT_MS: 300000, SILENT_PRE_MS: 900000, KITTEN_MS: 600000, GIVE_UP_MS: { mac: 115000, windows: 110000, linux: 110000 } });
  assert.deepEqual(core.NUDGE_KINDS, ['stuck.loop', 'stuck.errors', 'stuck.waiting', 'stuck.silent']);
});

test('the words are fixed templates with the agent\'s name and nothing else of the work', () => {
  const l = core.ledgerApply(core.emptyLedger(), core.eventFrom({ hook_event_name: 'PostToolUse', session_id: 'S', cwd: '/p/SECRET-DIR', nm_agent: 'gemini', tool_name: 'Bash', tool_input: { command: 'SECRET-CMD' } }, 1000));
  const s = l.sessions[0];
  for (const kind of core.NUDGE_KINDS) {
    const text = core.nudgeText({ kind, reasonId: kind.slice(6), key: s.key, agentId: s.agentId }, l, 1000 + 7 * 60000, {});
    assert.ok(text.startsWith('Gemini CLI '), text);
    assert.ok(!/SECRET/.test(text) && !/[\\/]/.test(text), text);
  }
  assert.equal(core.nudgeText(null, l, 0), '');
  assert.equal(core.nudgeText({ kind: 'nope' }, l, 0), '');
});

test('with nothing running there is nothing to wait for: no deadline, no nudge', () => {
  assert.deepEqual(core.stuckStep(core.emptyLedger(), 5, {}), { nudge: null, nextAt: null });
  for (const bad of [null, undefined, {}, { sessions: 'x' }, 5]) assert.deepEqual(core.stuckStep(bad, 5, {}), { nudge: null, nextAt: null });
  assert.deepEqual(core.stuckStep(core.emptyLedger(), NaN, {}), { nudge: null, nextAt: null });
  const done = ['Stop', 'SessionEnd'].reduce((l, n) => core.ledgerApply(l, core.eventFrom({ hook_event_name: n, session_id: 'S' }, 10)), core.ledgerApply(core.emptyLedger(), core.eventFrom({ hook_event_name: 'PostToolUse', session_id: 'S', tool_name: 'Bash', tool_input: {} }, 1)));
  assert.deepEqual(core.stuckStep(done, 10 ** 9, {}), { nudge: null, nextAt: null });
});

test('stuckStep and markNudged do not change the ledger they are given', () => {
  const l = core.ledgerApply(core.emptyLedger(), core.eventFrom({ hook_event_name: 'PostToolUse', session_id: 'S', tool_name: 'Bash', tool_input: {} }, 1000));
  const frozen = JSON.stringify(l);
  core.stuckStep(l, 10 ** 7, {});
  const l2 = core.markNudged(l, l.sessions[0].key, 5);
  assert.equal(JSON.stringify(l), frozen);
  assert.equal(l2.sessions[0].nudgedAt, 5);
  assert.equal(l.sessions[0].nudgedAt, null);
});

test('a fuzz: at most one nudge, always for a live session that has had none, and the deadline is in the future', () => {
  let seed = 99;
  const rnd = n => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  const names = ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'PermissionRequest', 'Stop', 'SubagentStart', 'SubagentStop', 'SessionEnd', 'Notification'];
  for (let round = 0; round < 40; round++) {
    let l = core.emptyLedger(), t = 1_000_000;
    for (let i = 0; i < 150; i++) {
      t += rnd(6) === 0 ? rnd(20) * 60000 : rnd(30) * 1000;
      const ev = core.eventFrom({ hook_event_name: names[rnd(names.length)], session_id: 'S' + rnd(3), tool_name: ['Bash', 'Edit'][rnd(2)], tool_input: { command: 'c' + rnd(2), file_path: '/p/f' + rnd(2) }, agent_id: 'a' + rnd(2), cwd: '/p' }, t);
      if (ev) l = core.ledgerApply(l, ev);
      const ctx = { away: rnd(8) === 0, ratelimit: rnd(8) === 0, cardShown: rnd(2) === 0 };
      const r = core.stuckStep(l, t, ctx);
      if (r.nudge) {
        const s = l.sessions.find(x => x.key === r.nudge.key);
        assert.ok(s && s.endedAt === null && s.nudgedAt === null && !ctx.away && !ctx.ratelimit);
        assert.ok(core.NUDGE_KINDS.includes(r.nudge.kind));
        assert.ok(core.nudgeText(r.nudge, l, t, ctx).length > 10);
        l = core.markNudged(l, r.nudge.key, t);
        assert.equal(core.stuckStep(l, t, ctx).nudge === null || core.stuckStep(l, t, ctx).nudge.key !== r.nudge.key, true);
      }
      if (r.nextAt !== null) assert.ok(r.nextAt > t);
      if (ctx.away || ctx.ratelimit) assert.equal(r.nextAt, null);
    }
  }
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `node --test tests/sidekick/*.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)|ENOENT"`
Expected: FAIL: `ENOENT ... stuck-cases.json`, `# tests 18`, `# pass 17`, `# fail 1`.

- [ ] **Step 3: Add the nudges to the core**

**Edit `shared/sidekick-core.js`**

Find (it occurs once):

```js
// @@NEXT (the next task's rules go above this line)
```

Replace with:

```js
// ── Task 3: stuckStep, the nudges ───────────────────────────────────────────

/** The thresholds of the four rules, in ms. `GIVE_UP_MS` is when the app stops waiting on a request (the Mac at about 115 s, Windows at 110 s). */
const STUCK = { LOOP_CALLS: 8, LOOP_SAME: 4, WINDOW_MS: 10 * MIN, ERRORS: 3, WAIT_MS: 60000, SILENT_MS: 5 * MIN, SILENT_PRE_MS: 15 * MIN, KITTEN_MS: 10 * MIN, GIVE_UP_MS: { mac: 115000, windows: 110000, linux: 110000 } };
api.STUCK = STUCK;
/** The kinds in the order they are tried when two fire together; they are the kinds of dismissal too. */
const NUDGE_KINDS = ['stuck.loop', 'stuck.errors', 'stuck.waiting', 'stuck.silent'];
const ACTIVE_STATES = new Set(['thinking', 'working', 'searching']);
const WRITE_SET = new Set(api.WRITE_TOOLS);
const isCall = r => r.kind === 'tool' || r.kind === 'failure';

/** The same tool and key four times in the last eight calls, within ten minutes, with no successful edit or write after the first of them. */
function loopFires(s, now) {
  if (!ACTIVE_STATES.has(s.state) || now - s.lastEventAt > STUCK.WINDOW_MS) return false;
  const calls = s.ring.filter(isCall).slice(-STUCK.LOOP_CALLS);
  if (calls.length < STUCK.LOOP_SAME) return false;
  const newest = calls[calls.length - 1], inWindow = calls.filter(r => newest.at - r.at <= STUCK.WINDOW_MS);
  const groups = new Map();
  for (const r of inWindow) if (r.tool) groups.set(`${r.tool}\u0000${r.target}`, [...(groups.get(`${r.tool}\u0000${r.target}`) || []), r]);
  for (const members of groups.values()) {
    if (members.length < STUCK.LOOP_SAME) continue;
    const after = s.ring.slice(s.ring.indexOf(members[0]) + 1);
    if (!after.some(r => r.kind === 'tool' && r.ok && WRITE_SET.has(r.tool))) return true;
  }
  return false;
}
/** Three failures in a row, within ten minutes, with no success between. Claude Code only: the other agents send no failure event. */
function errorsFires(s, now) {
  if (s.agentId !== 'integration_claude' || !ACTIVE_STATES.has(s.state)) return false;
  const calls = s.ring.filter(isCall), last = calls.slice(-STUCK.ERRORS);
  return last.length === STUCK.ERRORS && last.every(r => r.kind === 'failure') && last[STUCK.ERRORS - 1].at - last[0].at <= STUCK.WINDOW_MS && now - last[STUCK.ERRORS - 1].at <= STUCK.WINDOW_MS;
}
const waitingDue = s => (s.state === 'approval' && s.pendingApprovalAt !== null ? s.pendingApprovalAt + STUCK.WAIT_MS : null);
/** When the quiet rule is due: 5 minutes after a finished step, a prompt or a subagent's stop, 15 after a step that began and never ended; never while a kitten is under 10 minutes old. */
function silentDue(s) {
  if (!ACTIVE_STATES.has(s.state)) return null;
  const gap = s.last === 'preTool' ? STUCK.SILENT_PRE_MS : ['tool', 'failure', 'prompt', 'subagentStop'].includes(s.last) ? STUCK.SILENT_MS : null;
  if (gap === null) return null;
  const kittens = Object.values(s.subagents);
  return Math.max(s.lastEventAt + gap, kittens.length ? Math.max(...kittens) + STUCK.KITTEN_MS : 0);
}

/**
 * At most one nudge, and when the next one could fall due. `ctx` is `{ratelimit, away, cardShown}` (all false when absent): the cat already shows the rate limit, a nudge that falls
 * due while the user is away is dropped (the recap covers it), and the waiting nudge is for a request whose card is not on screen. Each session is nudged once (`nudgedAt`).
 * Returns `{nudge: {kind, reasonId, key, agentId} | null, nextAt: ms | null}`; `nextAt` is the earliest future deadline of the waiting and quiet rules, for the one-shot timer.
 */
function stuckStep(ledger, now, ctx) {
  const c = isObj(ctx) ? ctx : {}, out = { nudge: null, nextAt: null };
  if (!isNum(now) || !isObj(ledger) || !Array.isArray(ledger.sessions) || c.ratelimit === true || c.away === true) return out;
  let best = null;
  for (const s of ledger.sessions) {
    if (s.endedAt !== null || s.nudgedAt !== null) continue;
    const wd = waitingDue(s), sd = silentDue(s);
    const fired = [loopFires(s, now) ? 0 : -1, errorsFires(s, now) ? 1 : -1, wd !== null && now >= wd && c.cardShown !== true ? 2 : -1, sd !== null && now >= sd ? 3 : -1].find(k => k >= 0);
    if (fired !== undefined && (best === null || fired < best.rank)) best = { rank: fired, s };
    for (const due of [wd, sd]) if (due !== null && due > now && (out.nextAt === null || due < out.nextAt)) out.nextAt = due;
  }
  if (best) out.nudge = { kind: NUDGE_KINDS[best.rank], reasonId: NUDGE_KINDS[best.rank].slice(6), key: best.s.key, agentId: best.s.agentId };
  return out;
}
api.stuckStep = stuckStep;
api.NUDGE_KINDS = NUDGE_KINDS;
/** The ledger with that session marked as nudged: it gets no second nudge. */
api.markNudged = (ledger, key, now) => ({ sessions: ledger.sessions.map(s => (s.key === key ? { ...copy(s), nudgedAt: now } : s)) });
/** The words of a nudge: a fixed template with the agent's name and a whole number of minutes. `ctx.platform` (`mac`, `windows` or `linux`) sets when the app stopped waiting on a request. */
function nudgeText(nudge, ledger, now, ctx) {
  const s = isObj(ledger) && Array.isArray(ledger.sessions) ? ledger.sessions.find(x => x.key === (nudge && nudge.key)) : null;
  const agent = agentName(nudge && nudge.agentId);
  switch (nudge && nudge.kind) {
    case 'stuck.loop': return `${agent} has run the same step ${STUCK.LOOP_SAME} times.`;
    case 'stuck.errors': return `${agent} hit ${STUCK.ERRORS} errors in a row.`;
    case 'stuck.waiting': {
      const giveUp = isObj(ctx) && (ctx.platform === 'windows' || ctx.platform === 'linux') ? STUCK.GIVE_UP_MS.windows : STUCK.GIVE_UP_MS.mac;
      return s && s.pendingApprovalAt !== null && now - s.pendingApprovalAt >= giveUp ? `${agent} is waiting for your OK in the terminal.` : `${agent} is still waiting for your OK.`;
    }
    case 'stuck.silent': return `${agent} has been quiet for ${s ? Math.floor((now - s.lastEventAt) / MIN) : 0} minutes.`;
    default: return '';
  }
}
api.nudgeText = nudgeText;

// @@NEXT (the next task's rules go above this line)
```

- [ ] **Step 4: Add the timelines to the generator**

A timeline is a list of hook payloads and probes in time order; each probe types the nudge (or nothing), and where it matters the deadline and the words.

**Edit `scripts/gen-sidekick-fixtures.mjs`**

Find (it occurs once):

```js
// @@SECTIONS (the next task's fixtures go above this line)
```

Replace with:

```js
// ── stuck-cases.json: the four nudges, as timelines ─────────────────────────
// A timeline is a list of steps in time order: a hook payload (the ledger takes it) or a probe (stuckStep is asked at that time). Each probe types the answer it must get.
SECTIONS['stuck-cases.json'] = () => {
  const T0 = 10_000_000, S = n => T0 + n * 1000, M = n => T0 + n * 60000;
  const cases = [];
  const claude = (event, ...extras) => ({ hook_event_name: event, session_id: 'S1', cwd: '/Users/me/proj', ...Object.assign({}, ...extras) });
  const bash = command => ({ tool_name: 'Bash', tool_input: { command } });
  const post = (command, ...x) => claude('PostToolUse', bash(command), ...x);
  const fail = (command, ...x) => claude('PostToolUseFailure', bash(command), ...x);
  const edit = file => claude('PostToolUse', { tool_name: 'Edit', tool_input: { file_path: '/Users/me/proj/' + file } });
  const ev = (at, payload) => ({ at, payload });
  // expect: null, or the kind of the nudge; next: the nextAt typed as a time, null for none, undefined for "not pinned"; text: the words, when typed
  const probe = (at, expect, o = {}) => ({ at, probe: { ctx: o.ctx, mark: o.mark === true }, expect, next: o.next, text: o.text });

  const timeline = (name, steps) => {
    let ledger = core.emptyLedger();
    const out = [];
    for (const st of steps) {
      if (st.payload) { ledger = core.ledgerApply(ledger, core.eventFrom(st.payload, st.at)); out.push({ at: st.at, payload: st.payload }); continue; }
      const r = core.stuckStep(ledger, st.at, st.probe.ctx);
      expectEqual(`${name} @${st.at - T0}ms: the nudge`, r.nudge ? r.nudge.kind : null, st.expect);
      if (st.next !== undefined) expectEqual(`${name} @${st.at - T0}ms: nextAt`, r.nextAt, st.next);
      const text = r.nudge ? core.nudgeText(r.nudge, ledger, st.at, st.probe.ctx) : null;
      if (st.text !== undefined) expectEqual(`${name} @${st.at - T0}ms: the words`, text, st.text);
      out.push({ at: st.at, probe: { ...(st.probe.ctx ? { ctx: st.probe.ctx } : {}), ...(st.probe.mark ? { mark: true } : {}) }, nudge: r.nudge, nextAt: r.nextAt, text });
      if (st.probe.mark && r.nudge) ledger = core.markNudged(ledger, r.nudge.key, st.at);
    }
    cases.push({ name, steps: out });
  };

  // stuck.loop
  timeline('loop: the same step four times, then once per session', [
    ev(S(0), post('npm test')), ev(S(1), post('npm test')), ev(S(2), post('npm test')), probe(S(3), null),
    ev(S(4), post('npm   test')), probe(S(5), 'stuck.loop', { mark: true, text: 'Claude Code has run the same step 4 times.' }),
    ev(S(6), post('npm test')), probe(S(7), null),
  ]);
  timeline('loop: a successful edit between breaks it', [
    ev(S(0), post('npm test')), ev(S(1), post('npm test')), ev(S(2), edit('a.js')), ev(S(3), post('npm test')), ev(S(4), post('npm test')), probe(S(5), null),
  ]);
  timeline('loop: a failed edit does not break it', [
    ev(S(0), post('npm test')), ev(S(1), claude('PostToolUseFailure', { tool_name: 'Edit', tool_input: { file_path: '/Users/me/proj/a.js' } })), ev(S(2), post('npm test')), ev(S(3), post('npm test')), ev(S(4), post('npm test')),
    probe(S(5), 'stuck.loop'),
  ]);
  timeline('loop: four steps spread over twelve minutes are not a loop', [
    ev(M(0), post('npm test')), ev(M(4), post('npm test')), ev(M(8), post('npm test')), ev(M(12), post('npm test')), probe(M(12) + 1000, null),
  ]);
  timeline('loop: four in ten minutes are', [
    ev(M(0), post('npm test')), ev(M(3), post('npm test')), ev(M(6), post('npm test')), ev(M(10), post('npm test')), probe(M(10) + 1000, 'stuck.loop'),
  ]);
  timeline('loop: the same step must be among the last eight calls', [
    ev(S(0), post('a')), ev(S(1), post('a')), ev(S(2), post('a')), ev(S(3), post('b')), ev(S(4), post('c')), ev(S(5), post('d')), ev(S(6), post('e')), ev(S(7), post('f')), ev(S(8), post('g')), ev(S(9), post('a')), probe(S(10), null),
  ]);
  timeline('loop: four different steps are not a loop', [ev(S(0), post('a')), ev(S(1), post('b')), ev(S(2), post('c')), ev(S(3), post('d')), probe(S(4), null)]);
  timeline('loop: reading the same file four times is a loop', [
    ...[0, 1, 2, 3].map(i => ev(S(i), claude('PostToolUse', { tool_name: 'Read', tool_input: { file_path: '/Users/me/proj/a.js' } }))), probe(S(4), 'stuck.loop'),
  ]);
  timeline('loop: not once the turn is over', [...[0, 1, 2, 3].map(i => ev(S(i), post('npm test'))), ev(S(4), claude('Stop')), probe(S(5), null)]);

  // stuck.errors
  timeline('errors: three failures in a row', [ev(S(0), fail('npm test')), ev(S(1), fail('make')), probe(S(2), null), ev(S(3), fail('go test')), probe(S(4), 'stuck.errors', { text: 'Claude Code hit 3 errors in a row.' })]);
  timeline('errors: a success between breaks the row', [ev(S(0), fail('a')), ev(S(1), fail('b')), ev(S(2), post('c')), ev(S(3), fail('d')), probe(S(4), null)]);
  timeline('errors: three failures eleven minutes apart are not a row', [ev(M(0), fail('a')), ev(M(5), fail('b')), ev(M(11), fail('c')), probe(M(11) + 1000, null)]);
  timeline('errors: only Claude Code reports failures, so another agent never nudges for them', [
    ev(S(0), fail('a', { nm_agent: 'codex' })), ev(S(1), fail('b', { nm_agent: 'codex' })), ev(S(2), fail('c', { nm_agent: 'codex' })), probe(S(3), null),
  ]);
  timeline('errors: the loop is tried first when both fire', [ev(S(0), fail('npm test')), ev(S(1), fail('npm test')), ev(S(2), fail('npm test')), ev(S(3), fail('npm test')), probe(S(4), 'stuck.loop')]);

  // stuck.waiting
  timeline('waiting: a request that nobody has answered for a minute', [
    ev(S(0), claude('PermissionRequest', bash('git push'))), probe(S(30), null, { next: S(60) }), probe(S(59), null, { next: S(60) }),
    probe(S(60), 'stuck.waiting', { text: 'Claude Code is still waiting for your OK.' }),
    probe(S(114), 'stuck.waiting', { text: 'Claude Code is still waiting for your OK.' }),
    probe(S(115), 'stuck.waiting', { text: 'Claude Code is waiting for your OK in the terminal.' }),
    probe(S(110), 'stuck.waiting', { ctx: { platform: 'windows' }, text: 'Claude Code is waiting for your OK in the terminal.' }),
  ]);
  timeline('waiting: not while its card is on screen', [ev(S(0), claude('PermissionRequest', bash('git push'))), probe(S(70), null, { ctx: { cardShown: true }, next: null }), probe(S(70), 'stuck.waiting', { ctx: { cardShown: false } })]);
  timeline('waiting: not once the step has been answered in the terminal', [ev(S(0), claude('PermissionRequest', bash('git push'))), ev(S(20), post('git push')), probe(S(90), null, { next: S(320) })]);
  timeline('waiting: Codex asks too', [ev(S(0), { ...claude('PermissionRequest', bash('git push')), nm_agent: 'codex' }), probe(S(61), 'stuck.waiting', { text: 'Codex is still waiting for your OK.' })]);

  // stuck.silent
  timeline('silent: five minutes after a finished step', [
    ev(S(0), claude('UserPromptSubmit')), ev(S(10), post('ls')), probe(S(10) + 299000, null, { next: S(10) + 300000 }), probe(S(10) + 300000, 'stuck.silent', { text: 'Claude Code has been quiet for 5 minutes.' }),
    probe(S(10) + 8 * 60000, 'stuck.silent', { text: 'Claude Code has been quiet for 8 minutes.' }),
  ]);
  timeline('silent: five minutes after a prompt', [ev(S(0), claude('UserPromptSubmit')), probe(S(299), null, { next: S(300) }), probe(S(300), 'stuck.silent')]);
  timeline('silent: fifteen minutes after a step that never ended', [
    ev(S(0), claude('PreToolUse', bash('sleep 9999'))), probe(M(5), null, { next: S(0) + 15 * 60000 }), probe(S(0) + 15 * 60000 - 1, null), probe(S(0) + 15 * 60000, 'stuck.silent', { text: 'Claude Code has been quiet for 15 minutes.' }),
  ]);
  timeline('silent: not while a kitten is under ten minutes old', [
    ev(S(0), claude('SubagentStart', { agent_id: 'a1' })), ev(S(1), post('ls')), probe(M(6), null, { next: S(0) + 10 * 60000 }), probe(M(10) - 1000, null), probe(M(10), 'stuck.silent'),
  ]);
  timeline('silent: not when the turn is over, or the session has not begun', [ev(S(0), claude('SessionStart')), probe(M(30), null, { next: null }), ev(M(31), post('ls')), ev(M(32), claude('Stop')), probe(M(60), null, { next: null })]);
  timeline('silent: not while a question waits', [ev(S(0), claude('PreToolUse', { tool_name: 'AskUserQuestion', tool_input: { questions: [] } })), probe(M(30), null, { next: null })]);
  timeline('silent: a notification counts as an event, and does not change what came before it', [
    ev(S(0), post('ls')), ev(S(60), claude('Notification')), probe(S(301), null, { next: S(360) }), probe(S(361), 'stuck.silent', { text: 'Claude Code has been quiet for 5 minutes.' }),
  ]);

  // All four
  timeline('never while the user is away, and no timer is asked for', [ev(S(0), claude('PermissionRequest', bash('git push'))), probe(S(90), null, { ctx: { away: true }, next: null }), probe(S(90), 'stuck.waiting')]);
  timeline('never in the rate-limit state', [ev(S(0), post('ls')), probe(M(20), null, { ctx: { ratelimit: true }, next: null }), probe(M(20), 'stuck.silent')]);
  timeline('once per session, whatever the kind', [
    ev(S(0), post('ls')), probe(M(6), 'stuck.silent', { mark: true }), ev(M(7), claude('PermissionRequest', bash('git push'))), probe(M(9), null, { next: null }),
  ]);
  timeline('a second session still gets its nudge', [
    ev(S(0), post('ls')), probe(M(6), 'stuck.silent', { mark: true }), ev(M(6) + 1000, post('ls', { session_id: 'S2' })), probe(M(12), 'stuck.silent'),
  ]);
  timeline('two sessions: the earlier kind wins, then the earlier session', [
    ev(S(0), post('ls')), ev(S(1), claude('PermissionRequest', bash('git push'), { session_id: 'S2' })), probe(M(10), 'stuck.waiting'),
  ]);
  timeline('the timer asks for the nearest deadline of all sessions', [
    ev(S(0), post('ls')), ev(S(10), claude('PermissionRequest', bash('git push'), { session_id: 'S2' })), probe(S(20), null, { next: S(70) }),
  ]);
  timeline('a session that ended asks for nothing', [ev(S(0), post('ls')), ev(S(1), claude('SessionEnd')), probe(M(60), null, { next: null })]);
  timeline('an empty ledger asks for nothing', [probe(M(1), null, { next: null })]);

  return { version: 1, note: 'stuckStep(ledger, now, ctx) -> {nudge, nextAt}; nudgeText(nudge, ledger, now, ctx) is the words; markNudged(ledger, key, now) records that a session has had its nudge. A step is a hook payload or a probe; `ctx` is {ratelimit, away, cardShown, platform}. Times are ms on one clock.', thresholds: core.STUCK, kinds: core.NUDGE_KINDS, cases };
};

// @@SECTIONS (the next task's fixtures go above this line)
```

- [ ] **Step 5: Write the fixture**

Run: `node scripts/gen-sidekick-fixtures.mjs`
Expected: `wrote 3 fixture files to tests/fixtures/sidekick`.

- [ ] **Step 6: Run the tests and watch them pass**

Run: `node --test tests/sidekick/*.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)" && bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "✓|✗" | tail -3`
Expected: PASS: `# tests 23`, `# pass 23`, `# fail 0`, then `✓ 3 fixture files match sidekick-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 7: Bite: change a number on purpose and watch the checks catch it**

```bash
BK="$(mktemp -d "${TMPDIR:-/tmp}/nm-bite.XXXXXX")" && cp shared/sidekick-core.js "$BK/"
sed -i '' "s/WAIT_MS: 60000/WAIT_MS: 61000/" shared/sidekick-core.js
bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|^not ok"
cp "$BK/sidekick-core.js" shared/sidekick-core.js
bash scripts/test-sidekick-contract.sh 2>&1 | tail -2
```

Expected: `not ok` for "the fixture: every timeline gives the nudges, the deadlines and the words it records" and for "the thresholds are the spec's" and `# fail 2`; then after the copy back `✓ 3 fixture files match sidekick-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree's folder, and f1-0/sidekick-contract
MSG="$(mktemp "${TMPDIR:-/tmp}/nm-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): the stuck rules

stuckStep() finds a loop, three errors in a row, a request waiting a minute and a quiet
agent, once per session, never while away or rate-limited, and says when its one-shot
timer should next fire. 33 timelines with their answers typed by hand.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add shared/sidekick-core.js \
  scripts/gen-sidekick-fixtures.mjs \
  tests/sidekick/stuck.test.mjs \
  tests/fixtures/sidekick/stuck-cases.json
git status --short
git commit -F "$MSG"
```

Expected: `git status --short` lists only the files above (all staged). Never push.

---
### Task 4: `recapOf`, `statusOf` and `matchStatusQuestion`

**Files:**
- Edit: `shared/sidekick-core.js`, `scripts/gen-sidekick-fixtures.mjs`
- Create: `tests/sidekick/recap.test.mjs`, and (generated) `tests/fixtures/sidekick/recap-cases.json`, `tests/fixtures/sidekick/status-cases.json`

**Interfaces:**
- Consumes: Task 2's sessions and `agentName`, `RING_MAX`; Task 3's `STUCK`, `ACTIVE_STATES`, `isCall` and `WRITE_SET`.
- Produces: `recapOf({awaySince, now, sessions}) -> {lines, facts} | null`, `statusOf({now, sessions}, agentId?) -> {lines, facts}`, `matchStatusQuestion(text) -> {matched, agentId}`, `RECAP`. A fact is `{agent, agentId, project, steps, stepsAtLeast, files, more, errors, approvals, end, quietMinutes}`.

- [ ] **Step 1: Write the test first**

**Create `tests/sidekick/recap.test.mjs`**

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
const core = createRequire(import.meta.url)('../../shared/sidekick-core.js');
const read = n => JSON.parse(fs.readFileSync(new URL(`../fixtures/sidekick/${n}`, import.meta.url), 'utf8'));
const recapFx = read('recap-cases.json'), statusFx = read('status-cases.json');

test('the fixtures: every recap, status and question gives what it records', () => {
  for (const c of recapFx.cases) assert.deepEqual(core.recapOf(c.snapshot), c.recap, c.name);
  for (const c of statusFx.cases) assert.deepEqual(core.statusOf(c.snapshot, c.agent), c.status, c.name);
  for (const m of statusFx.matcher) assert.deepEqual(core.matchStatusQuestion(m.text), { matched: m.matched, agentId: m.agentId }, JSON.stringify(m.text));
});

test('a recap is never "nothing happened", and never for a short absence', () => {
  assert.equal(core.RECAP.MIN_AWAY_MS, 120000);
  for (const c of recapFx.cases) if (c.recap) assert.ok(c.recap.lines.length >= 1 && c.recap.lines.every(l => l.length > 10 || /^\+\d+ more$/.test(l)) && !/nothing happened/i.test(c.recap.lines.join(' ')));
  const ledger = recapFx.cases.find(c => c.recap).snapshot.sessions;
  const now = Math.max(...ledger.map(s => s.lastEventAt)) + 10 * 60000;
  assert.equal(core.recapOf({ awaySince: now - 119999, now, sessions: ledger }), null);
  assert.ok(core.recapOf({ awaySince: now - 600000, now, sessions: ledger }));
});

test('there are at most three lines, then "+N more"', () => {
  for (const c of recapFx.cases) if (c.recap) {
    const n = c.recap.lines.length;
    assert.ok(n <= 4);
    if (n === 4) assert.match(c.recap.lines[3], /^\+\d+ more$/);
    assert.equal(c.recap.facts.length, n === 4 ? 3 + Number(c.recap.lines[3].match(/\d+/)[0]) : n);
  }
});

test('the facts are the line\'s numbers and names, and nothing else', () => {
  for (const c of recapFx.cases) if (c.recap) for (const f of c.recap.facts) {
    assert.deepEqual(Object.keys(f), ['agent', 'agentId', 'project', 'steps', 'stepsAtLeast', 'files', 'more', 'errors', 'approvals', 'end', 'quietMinutes']);
    assert.ok(f.files.length <= 3 && f.files.every(x => !/[\\/]/.test(x) && Array.from(x).length <= 60));
    assert.ok(['finished', 'waiting', 'error', 'question', 'working', 'quiet'].includes(f.end));
  }
});

test('no command, path, prompt or message reaches a recap or a status', () => {
  const ev = (p, at) => core.eventFrom({ session_id: 'S', cwd: '/Users/SECRET-DIR/proj', ...p }, at);
  let l = core.emptyLedger();
  for (const [p, at] of [[{ hook_event_name: 'UserPromptSubmit', prompt: 'SECRET-PROMPT' }, 1000], [{ hook_event_name: 'PostToolUse', tool_name: 'Bash', tool_input: { command: 'echo SECRET-CMD' } }, 2000], [{ hook_event_name: 'PostToolUse', tool_name: 'Edit', tool_input: { file_path: '/Users/SECRET-DIR/proj/a.js', new_string: 'SECRET-NEW' } }, 3000], [{ hook_event_name: 'Stop', last_assistant_message: 'SECRET-MSG' }, 4000]]) l = core.ledgerApply(l, ev(p, at));
  const text = JSON.stringify([core.recapOf({ awaySince: 0, now: 10 * 60000, sessions: l.sessions }), core.statusOf({ now: 10 * 60000, sessions: l.sessions })]);
  assert.ok(text.includes('a.js'));
  assert.ok(!/SECRET/.test(text), text);
});

test('hostile snapshots give nothing and never throw', () => {
  for (const bad of [null, undefined, 5, 'x', [], {}, { awaySince: 0 }, { awaySince: 'a', now: 1, sessions: [] }, { awaySince: 0, now: NaN, sessions: [] }, { awaySince: 0, now: 10 ** 9, sessions: 'x' }, { awaySince: 0, now: 10 ** 9, sessions: [] }]) assert.equal(core.recapOf(bad), null);
  for (const bad of [null, undefined, 5, {}, { now: 1 }, { now: 1, sessions: 'x' }, { now: NaN, sessions: [] }]) assert.deepEqual(core.statusOf(bad).lines, ['No agent is running right now.']);
  assert.deepEqual(core.statusOf(null, 'agent_codex').lines, ['Codex is not running right now.']);
  for (const bad of [null, undefined, 5, {}, [], false, 'x'.repeat(81)]) assert.deepEqual(core.matchStatusQuestion(bad), { matched: false, agentId: null });
});

test('recapOf and statusOf do not change the snapshot', () => {
  const c = recapFx.cases.find(x => x.recap);
  const frozen = JSON.stringify(c.snapshot);
  core.recapOf(c.snapshot); core.statusOf({ now: c.snapshot.now, sessions: c.snapshot.sessions });
  assert.equal(JSON.stringify(c.snapshot), frozen);
});

test('the status question is the whole message', () => {
  const yes = ["What's Claude doing?", 'status', 'what is codex doing right now'];
  const no = ["What's Claude doing to my files and why did it delete the build folder?", 'Please give me the status', "what's the status of claude", 'status report for the team', 'claude status update please'];
  for (const t of yes) assert.equal(core.matchStatusQuestion(t).matched, true, t);
  for (const t of no) assert.equal(core.matchStatusQuestion(t).matched, false, t);
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `node --test tests/sidekick/*.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)|ENOENT"`
Expected: FAIL: `ENOENT ... recap-cases.json`, `# tests 24`, `# pass 23`, `# fail 1`.

- [ ] **Step 3: Add the recap, the status answer and the matcher to the core**

**Edit `shared/sidekick-core.js`**

Find (it occurs once):

```js
// @@NEXT (the next task's rules go above this line)
```

Replace with:

```js
// ── Task 4: recapOf, statusOf and matchStatusQuestion ───────────────────────

const RECAP = { MIN_AWAY_MS: 2 * MIN, MAX_LINES: 3, MAX_FILES: 3, STATUS_FINISHED_MS: 10 * MIN };
api.RECAP = RECAP;
const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

/** How a session stands now: finished, waiting (for an OK), question, error, quiet (active, with nothing heard for 5 minutes) or working. */
function endOf(s, now) {
  if (s.state === 'approval' && s.pendingApprovalAt !== null) return 'waiting';
  if (s.state === 'question') return 'question';
  if (s.state === 'error') return 'error';
  if (s.state === 'finished') return 'finished';
  return ACTIVE_STATES.has(s.state) && now - s.lastEventAt >= STUCK.SILENT_MS ? 'quiet' : 'working';
}
/** What one agent did since `since` (ms; 0 for everything the ledger holds), over all its sessions: counts, up to three file names, and how it stands. */
function factsOf(sessions, since, now) {
  const entries = sessions.flatMap(s => s.ring.filter(r => r.at >= since));
  const files = [];
  for (const r of entries) if (r.kind === 'tool' && r.ok && WRITE_SET.has(r.tool) && r.target && !files.includes(r.target)) files.push(r.target);
  const rep = sessions.reduce((a, b) => (b.lastEventAt > a.lastEventAt ? b : a));
  const end = endOf(rep, now);
  return {
    agent: agentName(rep.agentId), agentId: rep.agentId, project: rep.project,
    steps: entries.filter(isCall).length, stepsAtLeast: sessions.some(s => s.ring.length >= RING_MAX && s.ring[0].at >= since),
    files: files.slice(0, RECAP.MAX_FILES), more: Math.max(0, files.length - RECAP.MAX_FILES),
    errors: entries.filter(r => r.kind === 'failure').length, approvals: entries.filter(r => r.kind === 'approvalAsked').length,
    end, quietMinutes: end === 'quiet' ? Math.floor((now - rep.lastEventAt) / MIN) : 0, lastEventAt: rep.lastEventAt,
  };
}
const nameList = f => (f.more ? `${f.files.join(', ')} and ${f.more} more` : f.files.length > 1 ? `${f.files.slice(0, -1).join(', ')} and ${f.files[f.files.length - 1]}` : f.files[0] || '');
const TAIL = { finished: 'finished', waiting: 'is waiting for your OK', error: 'stopped on an error', question: 'is waiting for your answer', working: 'is still working' };
/** The rest of a line after the subject: what it ran, in brackets what went wrong or was asked, the files it edited, and how it stands. */
function lineBody(f, has) {
  const subject = f.project ? `${f.agent} in ${f.project}` : f.agent;
  const tail = f.end === 'quiet' ? `has been quiet for ${plural(f.quietMinutes, 'minute', 'minutes')}` : TAIL[f.end];
  if (f.steps === 0 && f.approvals === 0) return `${subject} ${tail}.`;
  const did = f.steps > 0 ? `${has}${f.stepsAtLeast ? `${RING_MAX} or more steps` : plural(f.steps, 'step', 'steps')}` : `asked for ${plural(f.approvals, 'approval', 'approvals')}`;
  const counts = [f.errors ? plural(f.errors, 'error', 'errors') : '', f.steps > 0 && f.approvals ? `${plural(f.approvals, 'approval', 'approvals')} asked` : ''].filter(Boolean);
  const edited = f.files.length ? `, edited ${nameList(f)}` : '';
  return `${subject} ${did}${counts.length ? ` (${counts.join(', ')})` : ''}${edited}${edited ? ',' : ''} and ${tail}.`;
}
const publicFacts = f => { const { lastEventAt, ...rest } = f; return rest; };
/** Groups sessions by agent, the agent that spoke last first, and writes at most three lines, then "+N more". */
function linesOf(groups, prefix, has, now, since) {
  const facts = groups.map(g => factsOf(g, since, now)).sort((a, b) => b.lastEventAt - a.lastEventAt || (a.agentId < b.agentId ? -1 : 1));
  const lines = facts.slice(0, RECAP.MAX_LINES).map(f => prefix + lineBody(f, has));
  if (facts.length > RECAP.MAX_LINES) lines.push(`+${facts.length - RECAP.MAX_LINES} more`);
  return { lines, facts: facts.map(publicFacts) };
}
const byAgent = sessions => { const m = new Map(); for (const s of sessions) m.set(s.agentId, [...(m.get(s.agentId) || []), s]); return [...m.values()]; };

/**
 * What happened while the user was away: `{lines, facts}`, or null when the away time was under two minutes or no agent did anything in it (a recap is never "nothing
 * happened"). `snapshot` is `{awaySince, now, sessions}`. It looks only at ring entries at or after `awaySince`.
 */
function recapOf(snapshot) {
  if (!isObj(snapshot) || !isNum(snapshot.awaySince) || !isNum(snapshot.now) || !Array.isArray(snapshot.sessions)) return null;
  const { awaySince, now } = snapshot;
  if (now - awaySince < RECAP.MIN_AWAY_MS) return null;
  const groups = byAgent(snapshot.sessions).map(g => g.filter(s => s.ring.some(r => r.at >= awaySince))).filter(g => g.length);
  if (!groups.length) return null;
  return linesOf(groups, 'While you were away, ', 'ran ', now, awaySince);
}
api.recapOf = recapOf;

/** The answer to "What's Claude doing?": the same templates over everything the ledger holds, for the live sessions (a finished one for 10 minutes), or for one agent. */
function statusOf(snapshot, agent) {
  const none = { lines: [isStr(agent) && agent ? `${agentName(agent)} is not running right now.` : 'No agent is running right now.'], facts: [] };
  if (!isObj(snapshot) || !isNum(snapshot.now) || !Array.isArray(snapshot.sessions)) return none;
  const live = snapshot.sessions.filter(s => s.endedAt === null && (s.state !== 'finished' || snapshot.now - s.lastEventAt <= RECAP.STATUS_FINISHED_MS) && (!isStr(agent) || !agent || s.agentId === agent));
  if (!live.length) return none;
  return linesOf(byAgent(live), '', 'has run ', snapshot.now, 0);
}
api.statusOf = statusOf;

const STATUS_AGENTS = { claude: 'integration_claude', 'claude code': 'integration_claude', codex: 'agent_codex', gemini: 'agent_gemini', 'gemini cli': 'agent_gemini', antigravity: 'agent_antigravity', cursor: 'agent_cursor' };
const STATUS_ALL = new Set(['the agents', 'my agents', 'the agent', 'my agent', 'everyone', 'everybody', 'my cats']);
/**
 * Is this message the status question? It must be the whole message: a short text that, lower-cased and stripped of punctuation, is "what's claude doing", "what is codex
 * doing", "what are the agents doing" or "status" (with an optional agent name and an optional "right now"). Anything longer or different is a normal chat message.
 * Returns `{matched, agentId}`; `agentId` is null for "all of them".
 */
function matchStatusQuestion(text) {
  const no = { matched: false, agentId: null };
  if (!isStr(text) || text.length > 80) return no;
  const t = text.toLowerCase().replace(/[‘’ʼ']/g, '').replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim().replace(/ (right )?now$/, '');
  if (t === 'status' || t === 'agent status' || t === 'agents status') return { matched: true, agentId: null };
  let m = /^(?:whats|what is) (.+?) doing$/.exec(t) || /^what (?:are|is) (.+?) doing$/.exec(t);
  if (m) {
    if (hasOwnKey(STATUS_AGENTS, m[1])) return { matched: true, agentId: STATUS_AGENTS[m[1]] };
    if (STATUS_ALL.has(m[1])) return { matched: true, agentId: null };
    return no;
  }
  m = /^(.+) status$/.exec(t);
  if (m && hasOwnKey(STATUS_AGENTS, m[1])) return { matched: true, agentId: STATUS_AGENTS[m[1]] };
  return no;
}
api.matchStatusQuestion = matchStatusQuestion;

// @@NEXT (the next task's rules go above this line)
```

- [ ] **Step 4: Add the cases to the generator**

Each scenario builds a ledger from hook payloads with the same adapter as the apps, then asks at a time; the lines are typed by hand.

**Edit `scripts/gen-sidekick-fixtures.mjs`**

Find (it occurs once):

```js
// @@SECTIONS (the next task's fixtures go above this line)
```

Replace with:

```js
// ── recap-cases.json and status-cases.json: what the agents did ─────────────
// A scenario builds a ledger from hook payloads (the same adapter as the apps), then asks for the recap or the status at a time. The lines are typed by hand.
const recapWorld = () => {
  const T0 = 20_000_000, M = n => T0 + n * 60000, S = n => T0 + n * 1000;
  const claude = (event, ...extras) => ({ hook_event_name: event, session_id: 'S1', cwd: '/Users/me/proj', ...Object.assign({}, ...extras) });
  const run = (steps, opts) => steps.reduce((l, [at, p]) => core.ledgerApply(l, core.eventFrom(p, at, opts)), core.emptyLedger());
  const post = (tool, input, ...x) => claude('PostToolUse', { tool_name: tool, tool_input: input }, ...x);
  const file = n => ({ file_path: `/Users/me/proj/${n}` });
  const steps = (count, from = 1, ...x) => Array.from({ length: count }, (_, i) => [M(from) + i * 1000, post('Read', file(`r${i}.txt`), ...x)]);
  const edits = (names, from = 1, ...x) => names.map((n, i) => [M(from) + 100000 + i * 1000, post('Edit', file(n), ...x)]);
  return { T0, M, S, claude, run, post, file, steps, edits };
};

SECTIONS['recap-cases.json'] = () => {
  const { M, claude, run, post, file, steps, edits } = recapWorld();
  const cases = [];
  const recap = (name, ledger, awayFrom, nowAt, lines) => {
    const snapshot = { awaySince: awayFrom, now: nowAt, sessions: ledger.sessions };
    const got = core.recapOf(snapshot);
    expectEqual(name, got ? got.lines : null, lines);
    cases.push({ name, snapshot, recap: got });
  };
  const gem = { nm_agent: 'gemini', session_id: 'G1', cwd: '/Users/me/other' };

  recap('finished: steps, three edited files', run([...steps(9), ...edits(['a.js', 'b.js', 'c.js']), [M(5), claude('Stop')]]), M(0), M(30),
    ['While you were away, Claude Code in proj ran 12 steps, edited a.js, b.js and c.js, and finished.']);
  recap('finished: five edited files, three named', run([...steps(2), ...edits(['a.js', 'b.js', 'c.js', 'd.js', 'e.js']), [M(5), claude('Stop')]]), M(0), M(30),
    ['While you were away, Claude Code in proj ran 7 steps, edited a.js, b.js, c.js and 2 more, and finished.']);
  recap('finished: one edited file, written twice, is named once', run([[M(1), post('Edit', file('a.js'))], [M(2), post('Write', file('a.js'))], [M(3), claude('Stop')]]), M(0), M(30),
    ['While you were away, Claude Code in proj ran 2 steps, edited a.js, and finished.']);
  recap('finished: two edited files', run([...edits(['a.js', 'b.js']), [M(5), claude('Stop')]]), M(0), M(30),
    ['While you were away, Claude Code in proj ran 2 steps, edited a.js and b.js, and finished.']);
  recap('finished: reads only, one step', run([[M(1), post('Read', file('a.js'))], [M(2), claude('Stop')]]), M(0), M(30),
    ['While you were away, Claude Code in proj ran 1 step and finished.']);
  recap('waiting for your OK: an approval was asked', run([...steps(3), [M(5), claude('PermissionRequest', { tool_name: 'Bash', tool_input: { command: 'git push' } })]]), M(0), M(8),
    ['While you were away, Claude Code in proj ran 3 steps (1 approval asked) and is waiting for your OK.']);
  recap('waiting for your OK: two approvals and no step', run([[M(1), claude('PermissionRequest', { tool_name: 'Bash', tool_input: { command: 'a' } })], [M(2), claude('PermissionRequest', { tool_name: 'Bash', tool_input: { command: 'b' } })]]), M(0), M(8),
    ['While you were away, Claude Code in proj asked for 2 approvals and is waiting for your OK.']);
  recap('stopped on an error: two errors and a stop failure', run([[M(1), claude('PostToolUseFailure', { tool_name: 'Bash', tool_input: { command: 'a' } })], [M(2), claude('PostToolUseFailure', { tool_name: 'Bash', tool_input: { command: 'b' } })], [M(3), claude('StopFailure')]]), M(0), M(30),
    ['While you were away, Claude Code in proj ran 2 steps (2 errors) and stopped on an error.']);
  recap('a failed edit is a step and an error, not an edited file', run([[M(1), claude('PostToolUseFailure', { tool_name: 'Edit', tool_input: file('a.js') })], [M(2), claude('Stop')]]), M(0), M(30),
    ['While you were away, Claude Code in proj ran 1 step (1 error) and finished.']);
  recap('still working: the last event was a minute ago', run([...steps(4, 28)]), M(0), M(30) + 1000,
    ['While you were away, Claude Code in proj ran 4 steps and is still working.']);
  recap('gone quiet: the last event was eight minutes ago', run([...steps(4, 20)]), M(0), M(28) + 4000,
    ['While you were away, Claude Code in proj ran 4 steps and has been quiet for 8 minutes.']);
  recap('waiting for your answer: a question is open', run([...steps(2), [M(5), claude('PreToolUse', { tool_name: 'AskUserQuestion', tool_input: { questions: [] } })]]), M(0), M(8),
    ['While you were away, Claude Code in proj ran 2 steps and is waiting for your answer.']);
  recap('steps before the user left are not counted', run([...steps(5, 1), [M(5), claude('Stop')], ...steps(2, 12), [M(15), claude('Stop')]]), M(10), M(30),
    ['While you were away, Claude Code in proj ran 2 steps and finished.']);
  recap('nothing happened while away: no recap', run([...steps(5, 1), [M(5), claude('Stop')]]), M(10), M(30), null);
  recap('an empty ledger: no recap', core.emptyLedger(), M(0), M(30), null);
  recap('away for 90 seconds: no recap', run([...steps(3, 1)]), M(0), M(0) + 90000, null);
  recap('away for exactly two minutes: a recap', run([[M(0) + 30000, post('Read', file('a.js'))], [M(0) + 40000, claude('Stop')]]), M(0), M(2),
    ['While you were away, Claude Code in proj ran 1 step and finished.']);
  recap('no project folder: just the agent', run([[M(1), post('Read', file('a.js'), { cwd: '' })], [M(2), claude('Stop', { cwd: '' })]]), M(0), M(30),
    ['While you were away, Claude Code ran 1 step and finished.']);
  recap('a subagent\'s start and stop are not steps', run([[M(1), claude('SubagentStart', { agent_id: 'a1' })], [M(2), claude('SubagentStop', { agent_id: 'a1' })], [M(3), claude('Stop')]]), M(0), M(30),
    ['While you were away, Claude Code in proj finished.']);
  recap('forty or more: the ring was full', run([...steps(45, 1), [M(5), claude('Stop')]]), M(0), M(30),
    ['While you were away, Claude Code in proj ran 40 or more steps and finished.']);
  recap('two agents: the one that spoke last comes first', run([[M(1), post('Read', file('a.js'))], [M(2), claude('Stop')], [M(3), post('Edit', file('g.md'), gem)], [M(4), claude('Stop', gem)]]), M(0), M(30),
    ['While you were away, Gemini CLI in other ran 1 step, edited g.md, and finished.', 'While you were away, Claude Code in proj ran 1 step and finished.']);
  recap('two sessions of one agent make one line', run([[M(1), post('Read', file('a.js'))], [M(2), post('Edit', file('b.js'), { session_id: 'S2' })], [M(3), claude('Stop', { session_id: 'S2' })]]), M(0), M(30),
    ['While you were away, Claude Code in proj ran 2 steps, edited b.js, and finished.']);
  recap('a session that ended is still told about', run([[M(1), post('Read', file('a.js'), gem)], [M(2), claude('Stop', gem)], [M(3), claude('SessionEnd', gem)]]), M(0), M(10),
    ['While you were away, Gemini CLI in other ran 1 step and finished.']);
  recap('four agents: three lines, then "+1 more"', run([
    [M(1), post('Read', file('a.js'), { nm_agent: 'a1', session_id: 'A' })], [M(2), post('Read', file('a.js'), { nm_agent: 'a2', session_id: 'B' })], [M(3), post('Read', file('a.js'), { nm_agent: 'a3', session_id: 'C' })], [M(4), post('Read', file('a.js'))],
  ]), M(0), M(5), ['While you were away, Claude Code in proj ran 1 step and is still working.', 'While you were away, A3 in proj ran 1 step and is still working.', 'While you were away, A2 in proj ran 1 step and is still working.', '+1 more']);
  recap('a file named in the line is a basename of at most 60 characters', run([[M(1), post('Edit', file('x'.repeat(100) + '.js'))], [M(2), claude('Stop')]]), M(0), M(30),
    ['While you were away, Claude Code in proj ran 1 step, edited ' + 'x'.repeat(59) + '…, and finished.']);
  recap('hostile: no sessions, a bad time, a bad snapshot', { sessions: [] }, 0, 10 ** 9, null);
  return { version: 1, note: 'recapOf({awaySince, now, sessions}) -> {lines, facts} or null. The sessions are the ledger\'s. `facts` is what a line says, as numbers and names, and what the local voice may be given.', min: core.RECAP.MIN_AWAY_MS, cases };
};

SECTIONS['status-cases.json'] = () => {
  const { M, claude, run, post, file, steps } = recapWorld();
  const cases = [];
  const status = (name, ledger, nowAt, agent, lines) => {
    const snapshot = { now: nowAt, sessions: ledger.sessions };
    const got = core.statusOf(snapshot, agent);
    expectEqual(name, got.lines, lines);
    cases.push({ name, snapshot, ...(agent ? { agent } : {}), status: got });
  };
  const gem = { nm_agent: 'gemini', session_id: 'G1', cwd: '/Users/me/other' };

  status('nothing is running', core.emptyLedger(), M(5), null, ['No agent is running right now.']);
  status('one agent at work', run([...steps(3), [M(2), claude('PostToolUse', { tool_name: 'Edit', tool_input: file('a.js') })]]), M(3), null,
    ['Claude Code in proj has run 4 steps, edited a.js, and is still working.']);
  status('an agent waiting for your OK', run([[M(1), claude('PermissionRequest', { tool_name: 'Bash', tool_input: { command: 'git push' } })]]), M(2), null,
    ['Claude Code in proj asked for 1 approval and is waiting for your OK.']);
  status('a session that has only begun', run([[M(1), claude('SessionStart')]]), M(2), null, ['Claude Code in proj is still working.']);
  status('two agents, asked about both', run([[M(1), post('Read', file('a.js'))], [M(2), post('Read', file('g.md'), gem)]]), M(3), null,
    ['Gemini CLI in other has run 1 step and is still working.', 'Claude Code in proj has run 1 step and is still working.']);
  status('two agents, asked about one', run([[M(1), post('Read', file('a.js'))], [M(2), post('Read', file('g.md'), gem)]]), M(3), 'agent_gemini', ['Gemini CLI in other has run 1 step and is still working.']);
  status('asked about an agent that is not running', run([[M(1), post('Read', file('a.js'))]]), M(3), 'agent_codex', ['Codex is not running right now.']);
  status('a turn that finished five minutes ago is still told', run([[M(1), post('Read', file('a.js'))], [M(2), claude('Stop')]]), M(7), null, ['Claude Code in proj has run 1 step and finished.']);
  status('a turn that finished twenty minutes ago is not', run([[M(1), post('Read', file('a.js'))], [M(2), claude('Stop')]]), M(22), null, ['No agent is running right now.']);
  status('a session that ended is not', run([[M(1), post('Read', file('a.js'))], [M(2), claude('SessionEnd')]]), M(3), null, ['No agent is running right now.']);
  status('a quiet agent says so', run([[M(1), post('Read', file('a.js'))]]), M(9), null, ['Claude Code in proj has run 1 step and has been quiet for 8 minutes.']);
  status('an unreadable snapshot', { sessions: [] }, 5, null, ['No agent is running right now.']);

  const asks = [
    ["What's Claude doing?", true, 'integration_claude'], ['whats claude doing', true, 'integration_claude'], ['WHAT’S CLAUDE DOING?!', true, 'integration_claude'], ['what is claude doing right now?', true, 'integration_claude'],
    ['what is Claude Code doing', true, 'integration_claude'], ["what's codex doing now", true, 'agent_codex'], ["what's gemini cli doing", true, 'agent_gemini'], ["what's antigravity doing", true, 'agent_antigravity'], ["what's cursor doing", true, 'agent_cursor'],
    ['what are the agents doing', true, null], ['what are my agents doing?', true, null], ["what's everyone doing", true, null], ['status', true, null], ['Status?', true, null], ['claude status', true, 'integration_claude'], ['agent status', true, null],
    ["  what's   claude   doing  ", true, 'integration_claude'],
    ["what's claude doing in the settings file", false, null], ["what's claude doing wrong?", false, null], ['can you tell me what claude is doing', false, null], ['status of the build', false, null], ['what is the status of my PR', false, null],
    ["what's the weather doing", false, null], ['', false, null], ['status status', false, null], ["what's  doing", false, null], ["what's constructor doing", false, null], ["what's __proto__ doing", false, null],
    ['x'.repeat(200), false, null], ["what's claude doing? " + 'x'.repeat(80), false, null],
  ];
  const matcher = asks.map(([text, matched, agentId]) => {
    expectEqual(`matchStatusQuestion(${JSON.stringify(text)})`, core.matchStatusQuestion(text), { matched, agentId });
    return { text, matched, agentId };
  });
  return { version: 1, note: 'statusOf({now, sessions}, agentId?) -> {lines, facts}; matchStatusQuestion(text) -> {matched, agentId}. A match is the whole message, short, and one of a few phrases.', cases, matcher };
};

// @@SECTIONS (the next task's fixtures go above this line)
```

- [ ] **Step 5: Write the fixtures**

Run: `node scripts/gen-sidekick-fixtures.mjs`
Expected: `wrote 5 fixture files to tests/fixtures/sidekick`.

- [ ] **Step 6: Run the tests and watch them pass**

Run: `node --test tests/sidekick/*.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)" && bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "✓|✗" | tail -3`
Expected: PASS: `# tests 31`, `# pass 31`, `# fail 0`, then `✓ 5 fixture files match sidekick-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 7: Bite: change a number on purpose and watch the checks catch it**

```bash
BK="$(mktemp -d "${TMPDIR:-/tmp}/nm-bite.XXXXXX")" && cp shared/sidekick-core.js "$BK/"
sed -i '' "s/MIN_AWAY_MS: 2 \* MIN/MIN_AWAY_MS: 1 * MIN/" shared/sidekick-core.js
bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|^not ok"
cp "$BK/sidekick-core.js" shared/sidekick-core.js
bash scripts/test-sidekick-contract.sh 2>&1 | tail -2
```

Expected: `not ok` for "the fixtures: every recap, status and question gives what it records" and for "a recap is never \"nothing happened\", and never for a short absence" and `# fail 2`; then after the copy back `✓ 5 fixture files match sidekick-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree's folder, and f1-0/sidekick-contract
MSG="$(mktemp "${TMPDIR:-/tmp}/nm-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): the recap, the status answer and the question matcher

recapOf() tells what each agent did while the user was away (two minutes at least, three
lines at most, then "+N more"); statusOf() answers "What's Claude doing?" from the same
templates; matchStatusQuestion() accepts only a short message that is the question and
nothing else. Lines and facts hold basenames and counts only.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add shared/sidekick-core.js \
  scripts/gen-sidekick-fixtures.mjs \
  tests/sidekick/recap.test.mjs \
  tests/fixtures/sidekick/recap-cases.json \
  tests/fixtures/sidekick/status-cases.json
git status --short
git commit -F "$MSG"
```

Expected: `git status --short` lists only the files above (all staged). Never push.

---
### Task 5: `dismiss`, `muted`, `unmute` and `cleanSidekickSettings`

**Files:**
- Edit: `shared/sidekick-core.js`, `scripts/gen-sidekick-fixtures.mjs`
- Create: `tests/sidekick/settings.test.mjs`, and (generated) `tests/fixtures/sidekick/dismiss-cases.json`, `tests/fixtures/sidekick/settings-cases.json`

**Interfaces:**
- Consumes: Task 2's `own`; Task 3's `NUDGE_KINDS`.
- Produces: `DISMISS_KINDS`, `MUTE_AT`, `cleanDismissals(raw)`, `dismiss(state, kind)`, `muted(state, kind)`, `unmute(state, kind)`, `cleanSidekickSettings(raw) -> {on, local, dismissals}`.

- [ ] **Step 1: Write the test first**

**Create `tests/sidekick/settings.test.mjs`**

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
const core = createRequire(import.meta.url)('../../shared/sidekick-core.js');
const read = n => JSON.parse(fs.readFileSync(new URL(`../fixtures/sidekick/${n}`, import.meta.url), 'utf8'));
const dismissFx = read('dismiss-cases.json'), settingsFx = read('settings-cases.json');

test('the fixtures: every operation and every stored value gives what it records', () => {
  for (const c of dismissFx.cases) {
    let state = c.start;
    c.ops.forEach((o, i) => { state = core[o.op](state, o.kind); assert.deepEqual([state, core.DISMISS_KINDS.filter(k => core.muted(state, k))], [c.trail[i].state, c.trail[i].muted], c.name); });
  }
  for (const c of settingsFx.cases) assert.deepEqual(core.cleanSidekickSettings(c.raw), c.clean, c.name);
});

test('the five kinds are frozen, in this order, and two dismissals mute', () => {
  assert.deepEqual(core.DISMISS_KINDS, ['recap', 'stuck.loop', 'stuck.errors', 'stuck.waiting', 'stuck.silent']);
  assert.equal(core.MUTE_AT, 2);
  assert.deepEqual(core.NUDGE_KINDS, core.DISMISS_KINDS.slice(1), 'the nudges are the kinds after the recap');
});

test('the risk badge and the permission line are not a kind, so they can not be muted', () => {
  let s = null;
  for (let i = 0; i < 5; i++) s = core.dismiss(s, 'risk');
  assert.equal(core.muted(s, 'risk'), false);
  assert.deepEqual(s, core.cleanDismissals(null));
});

test('dismiss and unmute do not change the state they are given', () => {
  const s = { recap: 1, 'stuck.loop': 0, 'stuck.errors': 0, 'stuck.waiting': 0, 'stuck.silent': 0 };
  const frozen = JSON.stringify(s);
  core.dismiss(s, 'recap'); core.unmute(s, 'recap');
  assert.equal(JSON.stringify(s), frozen);
});

test('cleaning is idempotent and always gives the same shape, for 3000 random values', () => {
  let seed = 5;
  const rnd = n => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  const atoms = [null, undefined, true, false, 0, 1, 2, 3, -1, 1.5, 2.0, 'x', '2', [], [1], {}, { recap: 1 }, NaN, Infinity];
  const make = d => (d > 2 || rnd(3) === 0 ? atoms[rnd(atoms.length)] : Object.fromEntries(['on', 'local', 'dismissals', 'recap', 'stuck.loop', '__proto__', 'x'].filter(() => rnd(2)).map(k => [k, make(d + 1)])));
  for (let i = 0; i < 3000; i++) {
    const raw = make(0), once = core.cleanSidekickSettings(raw);
    assert.deepEqual(core.cleanSidekickSettings(once), once);
    assert.deepEqual(Object.keys(once), ['on', 'local', 'dismissals']);
    assert.deepEqual(Object.keys(once.dismissals), core.DISMISS_KINDS);
    assert.ok(Object.values(once.dismissals).every(v => [0, 1, 2].includes(v)));
    assert.equal(typeof once.on, 'boolean');
  }
  assert.equal({}.on, undefined);
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `node --test tests/sidekick/*.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)|ENOENT"`
Expected: FAIL: `ENOENT ... dismiss-cases.json`, `# tests 32`, `# pass 31`, `# fail 1`.

- [ ] **Step 3: Add the dismissal memory and the settings cleaner to the core**

**Edit `shared/sidekick-core.js`**

Find (it occurs once):

```js
// @@NEXT (the next task's rules go above this line)
```

Replace with:

```js
// ── Task 5: dismissal memory and the stored settings ────────────────────────

/** The five kinds a note can be, in their frozen order. Each is dismissed and muted on its own. */
const DISMISS_KINDS = ['recap', 'stuck.loop', 'stuck.errors', 'stuck.waiting', 'stuck.silent'];
const MUTE_AT = 2;
api.DISMISS_KINDS = DISMISS_KINDS;
api.MUTE_AT = MUTE_AT;
/** A stored count: a whole number from 1 to 2 stays, anything else (text, a fraction, a negative, null) is 0. */
const cleanCount = v => (Number.isInteger(v) && v > 0 ? Math.min(MUTE_AT, v) : 0);
/** The dismissals as they are kept: every kind once, in order, each a count from 0 to 2. Unknown kinds go. */
const cleanDismissals = raw => Object.fromEntries(DISMISS_KINDS.map(k => [k, cleanCount(isObj(raw) && hasOwnKey(raw, k) ? raw[k] : 0)]));
api.cleanDismissals = cleanDismissals;
/** One more dismissal of a kind (a click on Not now, OK or ×). A kind that is not one of the five changes nothing. Returns the new state. */
api.dismiss = (state, kind) => { const s = cleanDismissals(state); if (DISMISS_KINDS.includes(kind)) s[kind] = Math.min(MUTE_AT, s[kind] + 1); return s; };
/** A kind is muted once it has been dismissed twice. A muted kind never shows. The risk badge and the permission line are not a kind, so they are never muted. */
api.muted = (state, kind) => DISMISS_KINDS.includes(kind) && cleanDismissals(state)[kind] >= MUTE_AT;
/** Unmute in Settings: that kind goes back to 0. */
api.unmute = (state, kind) => { const s = cleanDismissals(state); if (DISMISS_KINDS.includes(kind)) s[kind] = 0; return s; };

/**
 * The Sidekick settings as they are kept (UserDefaults `sidekick.on`, `sidekick.local`, `sidekick.dismissals` on the Mac; one `sidekick` object in settings.json on
 * Windows and Linux): `on` and `local` are booleans that are on unless they are `false`, `dismissals` is cleaned as above. Anything else is dropped. Cleaning twice is cleaning once.
 */
api.cleanSidekickSettings = raw => {
  const o = isObj(raw) ? raw : {};
  return { on: o.on !== false, local: o.local !== false, dismissals: cleanDismissals(o.dismissals) };
};

// @@NEXT (the next task's rules go above this line)
```

- [ ] **Step 4: Add the cases to the generator**

**Edit `scripts/gen-sidekick-fixtures.mjs`**

Find (it occurs once):

```js
// @@SECTIONS (the next task's fixtures go above this line)
```

Replace with:

```js
// ── dismiss-cases.json and settings-cases.json: remembering a dismissal ─────
SECTIONS['dismiss-cases.json'] = () => {
  const K = core.DISMISS_KINDS;
  const zero = Object.fromEntries(K.map(k => [k, 0]));
  const cases = [];
  // ops: ['dismiss' | 'unmute', kind]; after each op the state and which kinds are muted are typed
  const run = (name, start, ops, want) => {
    let state = start;
    const trail = [];
    for (const [op, kind] of ops) {
      state = core[op](state, kind);
      trail.push({ op, kind, state, muted: K.filter(k => core.muted(state, k)) });
    }
    expectEqual(name, trail.map(t => [t.state, t.muted]), want);
    cases.push({ name, start, ops: ops.map(([op, kind]) => ({ op, kind })), trail });
  };
  const s = (o) => ({ ...zero, ...o });
  run('one dismissal is remembered, two mute the kind', null, [['dismiss', 'recap'], ['dismiss', 'recap']], [[s({ recap: 1 }), []], [s({ recap: 2 }), ['recap']]]);
  run('a third dismissal stays at two', null, [['dismiss', 'stuck.loop'], ['dismiss', 'stuck.loop'], ['dismiss', 'stuck.loop']], [[s({ 'stuck.loop': 1 }), []], [s({ 'stuck.loop': 2 }), ['stuck.loop']], [s({ 'stuck.loop': 2 }), ['stuck.loop']]]);
  run('the kinds are separate', null, [['dismiss', 'recap'], ['dismiss', 'stuck.errors'], ['dismiss', 'recap']], [[s({ recap: 1 }), []], [s({ recap: 1, 'stuck.errors': 1 }), []], [s({ recap: 2, 'stuck.errors': 1 }), ['recap']]]);
  run('unmute sets the kind back to zero and leaves the others', s({ recap: 2, 'stuck.waiting': 2 }), [['unmute', 'recap']], [[s({ 'stuck.waiting': 2 }), ['stuck.waiting']]]);
  run('after an unmute it takes two dismissals again', s({ recap: 2 }), [['unmute', 'recap'], ['dismiss', 'recap'], ['dismiss', 'recap']], [[zero, []], [s({ recap: 1 }), []], [s({ recap: 2 }), ['recap']]]);
  run('a kind that does not exist changes nothing', null, [['dismiss', 'stuck.sleepy'], ['unmute', 'nope'], ['dismiss', '__proto__'], ['dismiss', null]], [[zero, []], [zero, []], [zero, []], [zero, []]]);
  run('a stored state is cleaned on the way: unknown kinds, bad counts', { recap: 7, 'stuck.loop': -1, 'stuck.errors': 1.5, 'stuck.waiting': '2', 'stuck.silent': null, extra: 5 }, [['dismiss', 'stuck.silent']], [[s({ recap: 2, 'stuck.silent': 1 }), ['recap']]]);
  run('a state that is not an object is an empty one', 'muted', [['dismiss', 'recap']], [[s({ recap: 1 }), []]]);
  run('a whole number written as 1.0 is 1', JSON.parse('{"recap":1.0}'), [['dismiss', 'recap']], [[s({ recap: 2 }), ['recap']]]);
  return { version: 1, note: 'dismiss(state, kind), unmute(state, kind) -> the new state; muted(state, kind) -> boolean. A state is a count from 0 to 2 for each of the five kinds; two mute a kind. Clicking Not now, OK or × counts, folding the island unseen does not (that is the app\'s call).', kinds: K, muteAt: core.MUTE_AT, cases };
};

SECTIONS['settings-cases.json'] = () => {
  const K = core.DISMISS_KINDS, zero = Object.fromEntries(K.map(k => [k, 0]));
  const cases = [];
  const clean = (name, raw, want) => {
    const got = core.cleanSidekickSettings(raw);
    expectEqual(name, got, want);
    expectEqual(`${name} (twice)`, core.cleanSidekickSettings(got), want);
    cases.push({ name, raw: raw === undefined ? null : raw, clean: got });
  };
  const def = { on: true, local: true, dismissals: zero };
  clean('nothing stored: everything on', null, def);
  clean('an empty object', {}, def);
  clean('not an object: text', 'on', def);
  clean('not an object: a list', [true, false], def);
  clean('not an object: a number', 7, def);
  clean('both off', { on: false, local: false }, { on: false, local: false, dismissals: zero });
  clean('only the recap switch off', { on: false }, { on: false, local: true, dismissals: zero });
  clean('a switch that is not a boolean is on', { on: 'no', local: 0 }, def);
  clean('a switch that is null is on', { on: null, local: null }, def);
  clean('dismissals are kept', { dismissals: { recap: 1, 'stuck.loop': 2 } }, { on: true, local: true, dismissals: { ...zero, recap: 1, 'stuck.loop': 2 } });
  clean('a count above two is two', { dismissals: { recap: 9 } }, { on: true, local: true, dismissals: { ...zero, recap: 2 } });
  clean('a bad count is zero: negative, fraction, text, null, a list', { dismissals: { recap: -3, 'stuck.loop': 0.5, 'stuck.errors': '2', 'stuck.waiting': null, 'stuck.silent': [1] } }, def);
  clean('an unknown kind is dropped', { dismissals: { recap: 1, 'stuck.sleepy': 2, constructor: 2 } }, { on: true, local: true, dismissals: { ...zero, recap: 1 } });
  clean('dismissals that are not an object', { dismissals: [1, 2] }, def);
  clean('unknown fields are dropped and not written back', { on: false, theme: 'dark', dismissals: { recap: 1 }, extra: { a: 1 } }, { on: false, local: true, dismissals: { ...zero, recap: 1 } });
  clean('an Object.prototype key is just text', JSON.parse('{"__proto__":{"on":false},"dismissals":{"__proto__":2}}'), def);
  clean('a whole number written with a point', JSON.parse('{"dismissals":{"recap":2.0}}'), { on: true, local: true, dismissals: { ...zero, recap: 2 } });
  return { version: 1, note: 'cleanSidekickSettings(raw) -> {on, local, dismissals}. A bad switch is on, an unknown kind is dropped, a bad count is 0, a count above 2 is 2. Cleaning twice is cleaning once.', kinds: K, cases };
};

// @@SECTIONS (the next task's fixtures go above this line)
```

- [ ] **Step 5: Write the fixtures**

Run: `node scripts/gen-sidekick-fixtures.mjs`
Expected: `wrote 7 fixture files to tests/fixtures/sidekick`.

- [ ] **Step 6: Run the tests and watch them pass**

Run: `node --test tests/sidekick/*.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)" && bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "✓|✗" | tail -3`
Expected: PASS: `# tests 36`, `# pass 36`, `# fail 0`, then `✓ 7 fixture files match sidekick-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 7: Bite: change a number on purpose and watch the checks catch it**

```bash
BK="$(mktemp -d "${TMPDIR:-/tmp}/nm-bite.XXXXXX")" && cp shared/sidekick-core.js "$BK/"
sed -i '' "s/const MUTE_AT = 2;/const MUTE_AT = 3;/" shared/sidekick-core.js
bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|^not ok"
cp "$BK/sidekick-core.js" shared/sidekick-core.js
bash scripts/test-sidekick-contract.sh 2>&1 | tail -2
```

Expected: `not ok` for "the fixtures: every operation and every stored value gives what it records", for "the five kinds are frozen, in this order, and two dismissals mute" and for "cleaning is idempotent and always gives the same shape, for 3000 random values" and `# fail 3`; then after the copy back `✓ 7 fixture files match sidekick-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree's folder, and f1-0/sidekick-contract
MSG="$(mktemp "${TMPDIR:-/tmp}/nm-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): dismissal memory and the Sidekick settings cleaner

Two dismissals mute one of five kinds; Unmute sets it back to zero; the risk badge is
not a kind and is never muted. cleanSidekickSettings() keeps the two switches on unless
they are false and the counts between 0 and 2, drops everything else, and is idempotent.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add shared/sidekick-core.js \
  scripts/gen-sidekick-fixtures.mjs \
  tests/sidekick/settings.test.mjs \
  tests/fixtures/sidekick/dismiss-cases.json \
  tests/fixtures/sidekick/settings-cases.json
git status --short
git commit -F "$MSG"
```

Expected: `git status --short` lists only the files above (all staged). Never push.

---
### Task 6: `presenceStep` and `shouldShow`

**Files:**
- Edit: `shared/sidekick-core.js`, `scripts/gen-sidekick-fixtures.mjs`
- Create: `tests/sidekick/presence.test.mjs`, and (generated) `tests/fixtures/sidekick/presence-cases.json`, `tests/fixtures/sidekick/show-cases.json`

**Interfaces:**
- Consumes: Task 5's `DISMISS_KINDS` and `muted`.
- Produces: `presenceInit()`, `presenceStep(state, signal, now) -> {state, back}`, `IDLE`, `shouldShow(input) -> {show, reason, replace}`, `HOLD_MS`, `NOTE_GAP_MS`.

- [ ] **Step 1: Write the test first**

**Create `tests/sidekick/presence.test.mjs`**

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
const core = createRequire(import.meta.url)('../../shared/sidekick-core.js');
const read = n => JSON.parse(fs.readFileSync(new URL(`../fixtures/sidekick/${n}`, import.meta.url), 'utf8'));
const presenceFx = read('presence-cases.json'), showFx = read('show-cases.json');

test('the fixtures: every signal and every gate input gives what it records', () => {
  for (const c of presenceFx.cases) {
    let state = c.start;
    for (const st of c.steps) { const r = core.presenceStep(state, st.signal, st.at); assert.deepEqual(r, { state: st.state, back: st.back }, `${c.name} @${st.at}`); state = r.state; }
  }
  for (const c of showFx.cases) assert.deepEqual(core.shouldShow(c.input), c.show, c.name);
});

test('the constants are the spec\'s: away at 300 s, back under 3 s, a note every 60 s, held 30 s and 2 minutes', () => {
  assert.deepEqual(core.IDLE, { AWAY_S: 300, BACK_S: 3 });
  assert.equal(core.NOTE_GAP_MS, 60000);
  assert.deepEqual(core.HOLD_MS, { nudge: 30000, recap: 120000 });
});

test('a fuzz of presence signals: back is told exactly when the last reason lets go, and never twice', () => {
  let seed = 3;
  const rnd = n => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  const types = ['lock', 'unlock', 'sleep', 'wake', 'displayOff', 'displayOn', 'idle', 'idle', 'idle', 'bogus'];
  for (let round = 0; round < 60; round++) {
    let state = round % 7 === 0 ? null : core.presenceInit(), t = 1_000_000, tellings = 0, awayStarts = 0;
    for (let i = 0; i < 200; i++) {
      t += rnd(400) * 1000;
      const sig = { type: types[rnd(types.length)] };
      if (sig.type === 'idle') sig.seconds = [0, 1, 2, 3, 100, 299, 300, 301, 900][rnd(9)];
      const wasAway = !!state && state.reasons.length > 0;
      const r = core.presenceStep(state, sig, t);
      const isAway = r.state.reasons.length > 0;
      assert.equal(r.state.wasAway, wasAway);
      assert.equal(r.back !== false, wasAway && !isAway);
      assert.deepEqual(r.state.reasons, ['lock', 'sleep', 'display', 'idle'].filter(x => r.state.reasons.includes(x)));
      assert.equal(r.state.awaySince === null, !isAway);
      if (r.back) { assert.ok(r.back.awayMs >= 0 && r.back.awaySince <= t && r.back.awayMs === t - r.back.awaySince); tellings++; }
      if (!wasAway && isAway) awayStarts++;
      state = r.state;
    }
    assert.ok(tellings === awayStarts || tellings === awayStarts - 1, `${tellings} backs for ${awayStarts} aways`);
  }
});

test('presenceStep does not change the state it is given', () => {
  const s = { reasons: ['lock'], awaySince: 5, wasAway: true };
  const frozen = JSON.stringify(s);
  core.presenceStep(s, { type: 'unlock' }, 10);
  assert.equal(JSON.stringify(s), frozen);
});

test('the gate: the same input always gives the same answer, and every answer is well-formed', () => {
  let seed = 8;
  const rnd = n => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  const REASONS = ['ok', 'off', 'kind', 'muted', 'away', 'card', 'typing', 'busy', 'recent', 'nudged', 'recapGiven'];
  for (let i = 0; i < 3000; i++) {
    const input = {
      on: [true, false, undefined, 'x'][rnd(4)], kind: [...core.DISMISS_KINDS, 'x', undefined][rnd(7)], dismissals: rnd(3) ? undefined : Object.fromEntries(core.DISMISS_KINDS.map(k => [k, rnd(4)])),
      away: rnd(2) === 0, card: [null, 'approval', 'question', 'other'][rnd(4)], ownCard: rnd(2) === 0, inputFocused: rnd(2) === 0,
      visible: rnd(3) ? null : { kind: core.DISMISS_KINDS[rnd(5)], seen: rnd(2) === 0 }, lastShownAt: rnd(2) ? null : 1000 - rnd(120000), now: 1000, nudged: rnd(2) === 0, recapGiven: rnd(2) === 0,
    };
    const a = core.shouldShow(input), b = core.shouldShow(JSON.parse(JSON.stringify(input)));
    assert.deepEqual(a, b);
    assert.ok(REASONS.includes(a.reason));
    assert.equal(a.show, a.reason === 'ok');
    if (a.replace) assert.ok(a.show && input.kind === 'recap');
    if (a.show) { assert.notEqual(input.on, false); assert.ok(!core.muted(input.dismissals, input.kind)); }
  }
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `node --test tests/sidekick/*.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)|ENOENT"`
Expected: FAIL: `ENOENT ... presence-cases.json`, `# tests 37`, `# pass 36`, `# fail 1`.

- [ ] **Step 3: Add presence and the gate to the core**

**Edit `shared/sidekick-core.js`**

Find (it occurs once):

```js
// @@NEXT (the next task's rules go above this line)
```

Replace with:

```js
// ── Task 6: presenceStep and shouldShow ─────────────────────────────────────

const PRESENCE_ORDER = ['lock', 'sleep', 'display', 'idle'];
const PRESENCE_SIGNALS = { lock: ['lock', true], unlock: ['lock', false], sleep: ['sleep', true], wake: ['sleep', false], displayOff: ['display', true], displayOn: ['display', false] };
/** 300 s without input is away; a sample under 3 s is back. The samples in between change nothing. */
const IDLE = { AWAY_S: 300, BACK_S: 3 };
api.IDLE = IDLE;
api.presenceInit = () => ({ reasons: [], awaySince: null, wasAway: false });

/**
 * Whether the user is away, from the signals the OS gives. `state` is `{reasons, awaySince, wasAway}`: the reasons that hold now (lock, sleep, display, idle), when the
 * away began, and whether the user was away before this signal. `signal` is `{type}` with `type` one of lock, unlock, sleep, wake, displayOff, displayOn, or
 * `{type: 'idle', seconds}`. The user is away while any reason holds, and back when the last one lets go. Returns `{state, back}` where `back` is false or
 * `{back: true, awaySince, awayMs}`. It never throws; a signal it does not know changes nothing.
 */
function presenceStep(state, signal, now) {
  const reasons = new Set(isObj(state) && Array.isArray(state.reasons) ? state.reasons.filter(r => PRESENCE_ORDER.includes(r)) : []);
  let since = isObj(state) && isNum(state.awaySince) ? state.awaySince : null;
  const was = reasons.size > 0;
  const keep = () => ({ state: { reasons: PRESENCE_ORDER.filter(r => reasons.has(r)), awaySince: reasons.size ? since : null, wasAway: was }, back: false });
  if (!isNum(now) || !isObj(signal) || !isStr(signal.type)) return keep();
  let began = now;
  if (hasOwnKey(PRESENCE_SIGNALS, signal.type)) { const [r, on] = PRESENCE_SIGNALS[signal.type]; if (on) reasons.add(r); else reasons.delete(r); }
  else if (signal.type === 'idle' && isNum(signal.seconds)) {
    if (signal.seconds >= IDLE.AWAY_S) { reasons.add('idle'); began = now - signal.seconds * 1000; }
    else if (signal.seconds < IDLE.BACK_S) reasons.delete('idle');
  } else return keep();
  const is = reasons.size > 0;
  if (is) since = !was || since === null ? began : signal.type === 'idle' && reasons.has('idle') ? Math.min(since, began) : since;
  if (was && !is) { const out = { state: { reasons: [], awaySince: null, wasAway: true }, back: { back: true, awaySince: since === null ? now : since, awayMs: now - (since === null ? now : since) } }; return out; }
  return { state: { reasons: PRESENCE_ORDER.filter(r => reasons.has(r)), awaySince: is ? since : null, wasAway: was }, back: false };
}
api.presenceStep = presenceStep;

/** How long a refused note is kept, waiting for the gate to open: 30 s for a nudge, 2 minutes for a recap; and the gap after a note was shown. */
api.HOLD_MS = { nudge: 30000, recap: 2 * MIN };
api.NOTE_GAP_MS = 60000;

/**
 * Whether a note (a recap or a nudge) may show now. Returns `{show, reason, replace}`: `reason` is 'ok' or the first thing that says no, in this order: off (the switch),
 * kind (not one of the five), muted, away (nudges only: a recap is for the return), card (an approval or a question is in front; for the waiting nudge the rule is the
 * reverse: its own card must not be on screen), typing, busy (another note is visible, unless it is a nudge nobody has seen and this is the recap, which replaces it),
 * recent (a note showed in the last 60 s; the recap goes first), nudged (the session has had its nudge), recapGiven (this away period has had its recap).
 * The input is `{on, kind, dismissals, away, card, ownCard, inputFocused, visible: {kind, seen} | null, lastShownAt, now, nudged, recapGiven}`.
 */
api.shouldShow = input => {
  const i = isObj(input) ? input : {}, kind = i.kind, no = (reason) => ({ show: false, reason, replace: false });
  if (i.on === false) return no('off');
  if (!DISMISS_KINDS.includes(kind)) return no('kind');
  if (api.muted(i.dismissals, kind)) return no('muted');
  const recap = kind === 'recap';
  if (!recap && i.away === true) return no('away');
  if (kind === 'stuck.waiting' ? i.ownCard === true : i.card === 'approval' || i.card === 'question') return no('card');
  if (i.inputFocused === true) return no('typing');
  let replace = false;
  if (isObj(i.visible)) { if (recap && isStr(i.visible.kind) && i.visible.kind !== 'recap' && i.visible.seen !== true) replace = true; else return no('busy'); }
  if (!recap && isNum(i.lastShownAt) && isNum(i.now) && i.now - i.lastShownAt < api.NOTE_GAP_MS) return no('recent');
  if (!recap && i.nudged === true) return no('nudged');
  if (recap && i.recapGiven === true) return no('recapGiven');
  return { show: true, reason: 'ok', replace };
};

// @@NEXT (the next task's rules go above this line)
```

- [ ] **Step 4: Add the cases to the generator**

**Edit `scripts/gen-sidekick-fixtures.mjs`**

Find (it occurs once):

```js
// @@SECTIONS (the next task's fixtures go above this line)
```

Replace with:

```js
// ── presence-cases.json and show-cases.json: away, back, and the gate ───────
SECTIONS['presence-cases.json'] = () => {
  const T0 = 30_000_000, S = n => T0 + n * 1000;
  const cases = [];
  const empty = { reasons: [], awaySince: null, wasAway: false };
  // steps: [at, signal]; want: the typed [reasons, awaySince, back-or-false] after each step
  const flow = (name, start, steps, want) => {
    let state = start;
    const trail = [];
    for (const [at, signal] of steps) {
      const r = core.presenceStep(state, signal, at);
      state = r.state;
      trail.push({ at, signal, state: r.state, back: r.back });
    }
    expectEqual(name, trail.map(t => [t.state.reasons, t.state.awaySince, t.back]), want);
    cases.push({ name, start, steps: trail });
  };
  const sig = type => ({ type }), idle = seconds => ({ type: 'idle', seconds });
  const back = (since, ms) => ({ back: true, awaySince: since, awayMs: ms });

  flow('lock and unlock', null, [[S(0), sig('lock')], [S(300), sig('unlock')]], [[['lock'], S(0), false], [[], null, back(S(0), 300000)]]);
  flow('the whole night: lock, display off, sleep, wake, display on, unlock', empty,
    [[S(0), sig('lock')], [S(1), sig('displayOff')], [S(2), sig('sleep')], [S(9000), sig('wake')], [S(9001), sig('displayOn')], [S(9005), sig('unlock')]],
    [[['lock'], S(0), false], [['lock', 'display'], S(0), false], [['lock', 'sleep', 'display'], S(0), false], [['lock', 'display'], S(0), false], [['lock'], S(0), false], [[], null, back(S(0), 9005000)]]);
  flow('sleep alone', empty, [[S(0), sig('sleep')], [S(600), sig('wake')]], [[['sleep'], S(0), false], [[], null, back(S(0), 600000)]]);
  flow('the display off alone', empty, [[S(10), sig('displayOff')], [S(100), sig('displayOn')]], [[['display'], S(10), false], [[], null, back(S(10), 90000)]]);
  flow('idle for 299 seconds is not away', empty, [[S(1000), idle(299)]], [[[], null, false]]);
  flow('idle for 300 seconds is away, since it began', empty, [[S(1000), idle(300)], [S(1005), idle(305)], [S(1100), idle(1)]],
    [[['idle'], S(700), false], [['idle'], S(700), false], [[], null, back(S(700), 400000)]]);
  flow('a sample between 3 and 299 seconds changes nothing', empty, [[S(1000), idle(400)], [S(1010), idle(5)], [S(1020), idle(2.9)]],
    [[['idle'], S(600), false], [['idle'], S(600), false], [[], null, back(S(600), 420000)]]);
  flow('a sample of exactly 3 seconds does not end idle', empty, [[S(1000), idle(400)], [S(1005), idle(3)]], [[['idle'], S(600), false], [['idle'], S(600), false]]);
  flow('idle first, then a lock: back only when both let go', empty,
    [[S(1000), idle(400)], [S(1100), sig('lock')], [S(1200), sig('unlock')], [S(1300), idle(1)]],
    [[['idle'], S(600), false], [['lock', 'idle'], S(600), false], [['idle'], S(600), false], [[], null, back(S(600), 700000)]]);
  flow('a lock, then idle that began before it', empty, [[S(100), sig('lock')], [S(500), idle(400)], [S(600), sig('unlock')], [S(700), idle(0)]],
    [[['lock'], S(100), false], [['lock', 'idle'], S(100), false], [['idle'], S(100), false], [[], null, back(S(100), 600000)]]);
  flow('idle that began before the lock moves the start back', empty, [[S(1000), sig('lock')], [S(1010), idle(900)], [S(1020), sig('unlock')], [S(1030), idle(0)]],
    [[['lock'], S(1000), false], [['lock', 'idle'], S(110), false], [['idle'], S(110), false], [[], null, back(S(110), 920000)]]);
  flow('back is told once', empty, [[S(0), sig('lock')], [S(10), sig('unlock')], [S(20), sig('unlock')], [S(30), sig('wake')]],
    [[['lock'], S(0), false], [[], null, back(S(0), 10000)], [[], null, false], [[], null, false]]);
  flow('an unlock with no lock, a wake with no sleep: nothing', empty, [[S(0), sig('unlock')], [S(1), sig('wake')], [S(2), sig('displayOn')]], [[[], null, false], [[], null, false], [[], null, false]]);
  flow('a lock twice, an unlock once', empty, [[S(0), sig('lock')], [S(5), sig('lock')], [S(9), sig('unlock')]], [[['lock'], S(0), false], [['lock'], S(0), false], [[], null, back(S(0), 9000)]]);
  flow('a signal nobody knows changes nothing', empty, [[S(0), sig('lock')], [S(1), sig('teleport')], [S(2), { type: 'idle' }], [S(3), { type: 'idle', seconds: 'many' }], [S(4), { type: 'idle', seconds: -5 }], [S(5), null], [S(6), 'lock']],
    [[['lock'], S(0), false], [['lock'], S(0), false], [['lock'], S(0), false], [['lock'], S(0), false], [['lock'], S(0), false], [['lock'], S(0), false], [['lock'], S(0), false]]);
  flow('a stored state that is nonsense is an empty one', { reasons: ['fly', 7], awaySince: 'soon', wasAway: 'maybe' }, [[S(0), sig('unlock')]], [[[], null, false]]);
  flow('a state with reasons and no start takes the time of the signal', { reasons: ['sleep'], awaySince: null, wasAway: true }, [[S(50), sig('wake')]], [[[], null, back(S(50), 0)]]);
  flow('a time that is not a number changes nothing', empty, [['now', sig('lock')]], [[[], null, false]]);
  return { version: 1, note: 'presenceStep(state, signal, now) -> {state, back}. `back` is false or {back: true, awaySince, awayMs}. Times are ms on one clock; `idle.seconds` is the OS\'s idle time.', idle: core.IDLE, cases };
};

SECTIONS['show-cases.json'] = () => {
  const NOW = 40_000_000;
  const none = Object.fromEntries(core.DISMISS_KINDS.map(k => [k, 0]));
  const base = { on: true, kind: 'stuck.silent', dismissals: none, away: false, card: null, ownCard: false, inputFocused: false, visible: null, lastShownAt: null, now: NOW, nudged: false, recapGiven: false };
  const cases = [];
  const gate = (name, patch, show, reason, replace = false) => {
    const input = { ...base, ...patch }, got = core.shouldShow(input);
    expectEqual(name, got, { show, reason, replace });
    cases.push({ name, input, show: got });
  };
  gate('a quiet nudge on a quiet screen', {}, true, 'ok');
  gate('a recap on a quiet screen', { kind: 'recap' }, true, 'ok');
  gate('the switch is off', { on: false }, false, 'off');
  gate('the switch is off, for a recap too', { on: false, kind: 'recap' }, false, 'off');
  gate('a kind that is not one of the five', { kind: 'stuck.sleepy' }, false, 'kind');
  gate('no kind at all', { kind: undefined }, false, 'kind');
  gate('a muted nudge', { kind: 'stuck.loop', dismissals: { ...none, 'stuck.loop': 2 } }, false, 'muted');
  gate('a nudge dismissed once is not muted', { kind: 'stuck.loop', dismissals: { ...none, 'stuck.loop': 1 } }, true, 'ok');
  gate('a muted recap', { kind: 'recap', dismissals: { ...none, recap: 2 } }, false, 'muted');
  gate('another kind muted does not mute this one', { kind: 'recap', dismissals: { ...none, 'stuck.loop': 2 } }, true, 'ok');
  gate('a nudge while the user is away', { away: true }, false, 'away');
  gate('a recap is for the return, so away does not stop it', { kind: 'recap', away: true }, true, 'ok');
  gate('an approval is in front', { card: 'approval' }, false, 'card');
  gate('a question is in front', { card: 'question' }, false, 'card');
  gate('an approval is in front of a recap: held', { kind: 'recap', card: 'approval' }, false, 'card');
  gate('the waiting nudge, its own card on screen', { kind: 'stuck.waiting', ownCard: true, card: 'approval' }, false, 'card');
  gate('the waiting nudge, its card folded away', { kind: 'stuck.waiting', ownCard: false }, true, 'ok');
  gate('the waiting nudge is not stopped by some other card in front', { kind: 'stuck.waiting', ownCard: false, card: 'question' }, true, 'ok');
  gate('typing in the island', { inputFocused: true }, false, 'typing');
  gate('typing in the island, for a recap', { kind: 'recap', inputFocused: true }, false, 'typing');
  gate('another note is on screen', { visible: { kind: 'stuck.loop', seen: true } }, false, 'busy');
  gate('a recap does not replace a nudge the user has seen', { kind: 'recap', visible: { kind: 'stuck.loop', seen: true } }, false, 'busy');
  gate('a recap replaces a nudge nobody has seen', { kind: 'recap', visible: { kind: 'stuck.loop', seen: false } }, true, 'ok', true);
  gate('a nudge does not replace a recap', { visible: { kind: 'recap', seen: false } }, false, 'busy');
  gate('a recap does not replace a recap', { kind: 'recap', visible: { kind: 'recap', seen: false } }, false, 'busy');
  gate('a note was shown 59 seconds ago', { lastShownAt: NOW - 59000 }, false, 'recent');
  gate('a note was shown 60 seconds ago', { lastShownAt: NOW - 60000 }, true, 'ok');
  gate('the recap goes first, whatever was shown a moment ago', { kind: 'recap', lastShownAt: NOW - 1000 }, true, 'ok');
  gate('this session has had its nudge', { nudged: true }, false, 'nudged');
  gate('this away period has had its recap', { kind: 'recap', recapGiven: true }, false, 'recapGiven');
  gate('a nudge is not stopped by a recap that was given', { recapGiven: true }, true, 'ok');
  gate('the order: off comes before muted', { on: false, dismissals: { ...none, 'stuck.silent': 2 } }, false, 'off');
  gate('the order: muted comes before away', { away: true, dismissals: { ...none, 'stuck.silent': 2 } }, false, 'muted');
  gate('the order: away comes before a card', { away: true, card: 'approval' }, false, 'away');
  gate('the order: a card comes before typing', { card: 'approval', inputFocused: true }, false, 'card');
  gate('the order: typing comes before another note', { inputFocused: true, visible: { kind: 'recap', seen: true } }, false, 'typing');
  const hostile = [['no input', undefined], ['null', null], ['text', 'recap'], ['a list', []]].map(([name, input]) => {
    const got = core.shouldShow(input);
    expectEqual(name, got, { show: false, reason: 'kind', replace: false });
    return { name: `hostile: ${name}`, input: input === undefined ? null : input, show: got };
  });
  return { version: 1, note: 'shouldShow(input) -> {show, reason, replace}. The reasons are tried in this order: off, kind, muted, away, card, typing, busy, recent, nudged, recapGiven. A refused note is kept 30 s (a recap 2 minutes) and shown if the gate opens.', holdMs: core.HOLD_MS, noteGapMs: core.NOTE_GAP_MS, cases: [...cases, ...hostile] };
};

// @@SECTIONS (the next task's fixtures go above this line)
```

- [ ] **Step 5: Write the fixtures**

Run: `node scripts/gen-sidekick-fixtures.mjs`
Expected: `wrote 9 fixture files to tests/fixtures/sidekick`.

- [ ] **Step 6: Run the tests and watch them pass**

Run: `node --test tests/sidekick/*.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)" && bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "✓|✗" | tail -3`
Expected: PASS: `# tests 41`, `# pass 41`, `# fail 0`, then `✓ 9 fixture files match sidekick-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 7: Bite: change a number on purpose and watch the checks catch it**

```bash
BK="$(mktemp -d "${TMPDIR:-/tmp}/nm-bite.XXXXXX")" && cp shared/sidekick-core.js "$BK/"
sed -i '' "s/AWAY_S: 300,/AWAY_S: 301,/" shared/sidekick-core.js
bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|^not ok"
cp "$BK/sidekick-core.js" shared/sidekick-core.js
bash scripts/test-sidekick-contract.sh 2>&1 | tail -2
```

Expected: `not ok` for "the fixtures: every signal and every gate input gives what it records" and for "the constants are the spec's: away at 300 s, back under 3 s, a note every 60 s, held 30 s and 2 minutes" and `# fail 2`; then after the copy back `✓ 9 fixture files match sidekick-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree's folder, and f1-0/sidekick-contract
MSG="$(mktemp "${TMPDIR:-/tmp}/nm-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): away detection and the show gate

presenceStep() folds lock, sleep, display and 300-second idle signals into away and back,
telling "back" once, when the last reason lets go. shouldShow() says why a recap or a
nudge may not show, in a fixed order, and when a recap replaces an unseen nudge.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add shared/sidekick-core.js \
  scripts/gen-sidekick-fixtures.mjs \
  tests/sidekick/presence.test.mjs \
  tests/fixtures/sidekick/presence-cases.json \
  tests/fixtures/sidekick/show-cases.json
git status --short
git commit -F "$MSG"
```

Expected: `git status --short` lists only the files above (all staged). Never push.

---
### Task 7: `acceptNicerLine`, and the owner's tables

**Files:**
- Edit: `shared/sidekick-core.js`, `scripts/gen-sidekick-fixtures.mjs`
- Create: `scripts/print-sidekick-tables.mjs`, `tests/sidekick/voice.test.mjs`, `tests/sidekick/print.test.mjs`, and (generated) `tests/fixtures/sidekick/voice-cases.json`

**Interfaces:**
- Consumes: Task 4's recap `facts` and `RING_MAX`; Task 2's `isNum`, `isObj`, `isStr` (the helpers at the top of the core).
- Produces: `acceptNicerLine(line, facts) -> boolean`; `node scripts/print-sidekick-tables.mjs`, which reads the core and the fixtures and prints.

- [ ] **Step 1: Write the tests first**

**Create `tests/sidekick/voice.test.mjs`**

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
const core = createRequire(import.meta.url)('../../shared/sidekick-core.js');
const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/sidekick/voice-cases.json', import.meta.url), 'utf8'));
const recapFx = JSON.parse(fs.readFileSync(new URL('../fixtures/sidekick/recap-cases.json', import.meta.url), 'utf8'));

test('the fixture: every sentence is accepted or refused as it records', () => {
  for (const c of fx.cases) assert.equal(core.acceptNicerLine(c.line, c.facts), c.ok, c.name);
  assert.ok(fx.cases.filter(c => c.ok).length >= 10 && fx.cases.filter(c => !c.ok).length >= 20);
});

test('the template of a recap always passes its own sanity check, except where it names a path-like thing', () => {
  for (const c of recapFx.cases) if (c.recap) {
    for (const [i, line] of c.recap.lines.entries()) {
      if (/^\+\d+ more$/.test(line)) continue;
      assert.equal(core.acceptNicerLine(line, c.recap.facts), true, `${c.name}: ${line}`);
    }
  }
});

test('a sentence is never accepted for facts it does not match', () => {
  const facts = [{ agent: 'Claude Code', steps: 3, files: [], more: 0 }];
  for (const bad of ['Claude Code ran 4 steps.', 'Claude Code ran 3 steps at 10.', 'Claude Code ran 3 steps. http://x', 'Claude Code' + String.fromCharCode(0x2028) + 'ran 3 steps.']) assert.equal(core.acceptNicerLine(bad, facts), false, bad);
});

test('it never throws', () => {
  for (const line of [null, undefined, 5, {}, [], 'x'.repeat(100000)]) for (const facts of [null, undefined, 5, 'x', [], [null], [{}], { agent: 5 }]) assert.doesNotThrow(() => core.acceptNicerLine(line, facts));
});
```

**Create `tests/sidekick/print.test.mjs`**

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

test('the owner\'s tables print, with every heading, and write nothing', () => {
  const out = execFileSync(process.execPath, ['scripts/print-sidekick-tables.mjs'], { encoding: 'utf8' });
  for (const h of ['1. Risk rules', '2. Stuck rules', '3. Recap', '4. "What\'s Claude doing?"', '5. When a note may show']) assert.ok(out.includes(h), h);
  for (const id of ['rm_recursive', 'sudo', 'git_force_push', 'sensitive_file', 'unknown_tool', 'edit_in_project']) assert.ok(out.includes(id), id);
  assert.ok(out.includes('While you were away, Claude Code in proj ran 12 steps, edited a.js, b.js and c.js, and finished.'));
  assert.ok(out.includes('Claude Code is still waiting for your OK.'));
});
```

- [ ] **Step 2: Run them and watch them fail**

Run: `node --test tests/sidekick/*.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)|ENOENT|Cannot find"`
Expected: FAIL: `ENOENT ... voice-cases.json` and `Cannot find module ... print-sidekick-tables.mjs`, `# tests 43`, `# pass 41`, `# fail 2`.

- [ ] **Step 3: Add the sanity check to the core**

**Edit `shared/sidekick-core.js`**

Find (it occurs once):

```js
// @@NEXT (the next task's rules go above this line)
```

Replace with:

```js
// ── Task 7: acceptNicerLine, the sanity check of the local voice ────────────

/** A line break of any kind: CR, LF, and the Unicode line and paragraph separators. */
const LINE_BREAK = new RegExp('[\\r\\n' + String.fromCharCode(0x2028, 0x2029) + ']');

/**
 * Whether a sentence from a local model may replace the template. It must be one line of at most 200 characters, with no URL, no `/` or `\`, no backtick and no
 * markdown, use only numbers that are in the facts (their values, the digits in their names, the length of their lists, and 40 when the count is "40 or more"), and name an agent of the facts.
 * `facts` is the `facts` of a recap or a status (a list of facts, or one fact). The template is always right and always shown first; this only guards the swap.
 */
api.acceptNicerLine = (line, facts) => {
  if (!isStr(line)) return false;
  const t = line.trim(), list = Array.isArray(facts) ? facts.filter(isObj) : isObj(facts) ? [facts] : [];
  if (!t || Array.from(t).length > 200 || !list.length) return false;
  if (LINE_BREAK.test(t) || /:\/\/|\bwww\./i.test(t) || /[\/\\`]/.test(t) || /[*_#\[\]<>|~]/.test(t) || /^[-+]\s/.test(t)) return false;
  const allowed = new Set();
  const walk = v => {
    if (isNum(v)) allowed.add(String(Math.abs(Math.trunc(v))));
    else if (isStr(v)) (v.match(/\d+/g) || []).forEach(d => allowed.add(d.replace(/^0+(?=\d)/, '')));
    else if (Array.isArray(v)) { allowed.add(String(v.length)); v.forEach(walk); }
    else if (isObj(v)) Object.values(v).forEach(walk);
  };
  list.forEach(f => { walk(f); if (Array.isArray(f.files) && isNum(f.more)) allowed.add(String(f.files.length + f.more)); if (f.stepsAtLeast === true) allowed.add(String(RING_MAX)); });
  if ((t.match(/\d+/g) || []).some(d => !allowed.has(d.replace(/^0+(?=\d)/, '')))) return false;
  const lower = t.toLowerCase();
  return list.some(f => isStr(f.agent) && f.agent !== '' && lower.includes(f.agent.toLowerCase()));
};

// @@NEXT (the next task's rules go above this line)
```

- [ ] **Step 4: Add the cases to the generator**

**Edit `scripts/gen-sidekick-fixtures.mjs`**

Find (it occurs once):

```js
// @@SECTIONS (the next task's fixtures go above this line)
```

Replace with:

```js
// ── voice-cases.json: the sanity check of a nicer line ──────────────────────
SECTIONS['voice-cases.json'] = () => {
  const one = { agent: 'Claude Code', agentId: 'integration_claude', project: 'proj', steps: 12, stepsAtLeast: false, files: ['a.js', 'b2.js', 'c.js'], more: 2, errors: 1, approvals: 0, end: 'finished', quietMinutes: 0 };
  const quiet = { ...one, agent: 'Codex', agentId: 'agent_codex', steps: 4, files: [], more: 0, errors: 0, end: 'quiet', quietMinutes: 8 };
  const rows = [];
  const line = (name, text, facts, ok) => rows.push({ name, line: text, facts, ok });
  // Accepted
  line('a plain sentence that names the agent', 'Claude Code finished 12 steps in proj.', [one], true);
  line('the agent\'s name in another case', 'claude code is done, 12 steps in all.', [one], true);
  line('a number that is a value of the facts', 'Claude Code hit 1 error on the way and finished.', [one], true);
  line('the number of files, from the list and "more"', 'Claude Code edited 5 files and finished.', [one], true);
  line('the digits in a file name', 'Claude Code changed b2.js and finished.', [one], true);
  line('minutes', 'Codex has been quiet for 8 minutes.', [quiet], true);
  line('no number at all', 'Claude Code is all done.', [one], true);
  line('either of two agents is enough', 'Codex seems to be waiting.', [one, quiet], true);
  line('exactly 200 characters', 'Claude Code ' + 'x'.repeat(188), [one], true);
  line('spaces around are trimmed', '   Claude Code is done.   ', [one], true);
  line('a single fact instead of a list', 'Claude Code finished.', one, true);
  line('an accent and an emoji', 'Claude Code a terminé ✨', [one], true);
  // Refused
  line('201 characters', 'Claude Code ' + 'x'.repeat(189), [one], false);
  line('two lines', 'Claude Code finished.\nIt did well.', [one], false);
  line('a carriage return', 'Claude Code finished.\rDone.', [one], false);
  line('a URL', 'Claude Code finished, see https://example.com for more.', [one], false);
  line('a www address', 'Claude Code finished, see www.example.com.', [one], false);
  line('a slash', 'Claude Code edited src/a.js.', [one], false);
  line('a backslash', 'Claude Code edited src\\a.js.', [one], false);
  line('a backtick', 'Claude Code ran `npm test`.', [one], false);
  line('bold markdown', 'Claude Code **finished** 12 steps.', [one], false);
  line('an underscore', 'Claude Code edited my_file.js.', [one], false);
  line('a heading', '# Claude Code finished', [one], false);
  line('a link', 'Claude Code [finished](x).', [one], false);
  line('a bullet', '- Claude Code finished.', [one], false);
  line('a quote', '> Claude Code finished.', [one], false);
  line('a number that is not in the facts', 'Claude Code finished 13 steps.', [one], false);
  line('a number that is not in the facts: a count of errors', 'Claude Code hit 7 errors.', [one], false);
  line('a made-up number next to a real one', 'Claude Code ran 12 steps in 4 minutes.', [one], false);
  line('a leading zero is the same number', 'Claude Code ran 012 steps.', [one], true);
  line('no agent named', 'The helper finished 12 steps in proj.', [one], false);
  line('the other agent only, not in the facts', 'Gemini CLI finished.', [one], false);
  line('empty', '', [one], false);
  line('only spaces', '    ', [one], false);
  line('not text', 12, [one], false);
  line('no facts', 'Claude Code finished.', [], false);
  line('facts that are not a list or an object', 'Claude Code finished.', 'facts', false);
  line('facts with no agent name', 'Claude Code finished.', [{ steps: 1 }], false);
  line('an empty agent name matches nothing', 'Claude Code finished.', [{ agent: '' }], false);
  const cases = rows.map(r => {
    expectEqual(r.name, core.acceptNicerLine(r.line, r.facts), r.ok);
    return { name: r.name, line: r.line, facts: r.facts, ok: r.ok };
  });
  return { version: 1, note: 'acceptNicerLine(line, facts) -> boolean. One line of at most 200 characters, no URL, `/`, `\\`, backtick or markdown, only numbers from the facts, and the name of an agent of the facts.', cases };
};

// @@SECTIONS (the next task's fixtures go above this line)
```

- [ ] **Step 5: Write the tables script**

**Create `scripts/print-sidekick-tables.mjs`**

```js
#!/usr/bin/env node
// Prints the sidekick's rules as tables for the owner to read: the risk reasons with a sample request and its line, the stuck rules with their thresholds and a timeline of
// each, and the recap and status samples. It reads shared/sidekick-core.js and tests/fixtures/sidekick/ and writes nothing.
//   node scripts/print-sidekick-tables.mjs
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const core = require('../shared/sidekick-core.js');
const FIX = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../tests/fixtures/sidekick');
const read = name => JSON.parse(fs.readFileSync(path.join(FIX, name), 'utf8'));
const pad = (s, n) => String(s).padEnd(n);
const clip = (s, n) => (s.length > n ? s.slice(0, n - 1) + '…' : s);
const head = t => console.log(`\n== ${t} ${'='.repeat(Math.max(0, 76 - t.length))}`);
const sec = ms => `${ms < 0 ? '-' : '+'}${Math.abs(Math.round(ms / 1000))}s`;

head('1. Risk rules: what a permission request is called, and the line under it');
const explain = read('explain-cases.json');
console.log(`${pad('risk', 7)}${pad('reason', 17)}${pad('sample request', 40)}line`);
for (const r of core.REASONS) {
  const c = explain.cases.find(x => x.reasonId === r.id && !x.near);
  const sample = c ? (c.input && (c.input.command ?? c.input.file_path) !== undefined ? `${c.tool}: ${Array.isArray(c.input.command) ? c.input.command.join(' ') : String(c.input.command ?? c.input.file_path).split('\n')[0]}` : `${c.tool}`) : '';
  console.log(`${pad(r.risk, 7)}${pad(r.id, 17)}${pad(clip(sample, 38), 40)}${c ? c.line : r.line}`);
}
const near = explain.cases.filter(c => c.near).slice(0, 6);
console.log('\nNear misses (a look-alike that is NOT the reason in the left column):');
for (const c of near) console.log(`  ${pad(c.near, 17)}${pad(clip(`${c.tool}: ${c.input.command ?? c.input.file_path}`, 36), 38)} -> ${c.reasonId}`);
console.log(`\n${explain.cases.length} rows pin ${core.REASONS.length} reasons. A label never allows or denies: only the user's click does.`);

head('2. Stuck rules: when an agent looks stuck (at most one nudge per session)');
const S = core.STUCK;
const stuckRows = [
  ['stuck.loop', `the same step ${S.LOOP_SAME} times in the last ${S.LOOP_CALLS} calls, within ${S.WINDOW_MS / 60000} min, with no successful edit between`, '{Agent} has run the same step 4 times.'],
  ['stuck.errors', `${S.ERRORS} failures in a row within ${S.WINDOW_MS / 60000} min (Claude Code only)`, '{Agent} hit 3 errors in a row.'],
  ['stuck.waiting', `a request unanswered for ${S.WAIT_MS / 1000} s, its card not on screen`, '{Agent} is still waiting for your OK.'],
  ['', `...and once the app has given up (${S.GIVE_UP_MS.mac / 1000} s on the Mac, ${S.GIVE_UP_MS.windows / 1000} s on Windows and Linux)`, '{Agent} is waiting for your OK in the terminal.'],
  ['stuck.silent', `${S.SILENT_MS / 60000} min after a finished step or a prompt, ${S.SILENT_PRE_MS / 60000} min after a step that never ended; not while a helper is under ${S.KITTEN_MS / 60000} min old`, '{Agent} has been quiet for {n} minutes.'],
];
for (const [kind, when, words] of stuckRows) { console.log(`${pad(kind, 14)}${when}`); console.log(`${pad('', 14)}says: ${words}`); }
console.log('Never while the user is away, never in the rate-limit state, once per session; after 2 dismissals a kind is muted.');
const stuck = read('stuck-cases.json');
for (const name of ['loop: the same step four times, then once per session', 'waiting: a request that nobody has answered for a minute', 'silent: five minutes after a finished step']) {
  const c = stuck.cases.find(x => x.name === name);
  console.log(`\nTimeline: ${c.name}`);
  const t0 = c.steps[0].at;
  for (const st of c.steps) {
    if (st.payload) console.log(`  ${pad(sec(st.at - t0), 8)}${st.payload.hook_event_name}${st.payload.tool_input ? ' ' + clip(String(st.payload.tool_input.command ?? st.payload.tool_input.file_path ?? ''), 24) : ''}`);
    else console.log(`  ${pad(sec(st.at - t0), 8)}asked: ${st.expect ? `${st.expect}  "${st.text}"` : 'nothing'}${typeof st.nextAt === 'number' ? `   (timer set for ${sec(st.nextAt - t0)})` : '   (no timer)'}`);
  }
}

head('3. Recap: what the cat says when you come back (after at least 2 minutes away)');
for (const c of read('recap-cases.json').cases.filter(x => x.recap).slice(0, 14)) {
  console.log(`- ${c.name}`);
  for (const l of c.recap.lines) console.log(`    ${l}`);
}
console.log('- and no recap at all when nothing happened, or when you were away less than 2 minutes.');

head('4. "What\'s Claude doing?": the answer in the chat, from this Mac only');
for (const c of read('status-cases.json').cases.slice(0, 8)) {
  console.log(`- ${c.name}`);
  for (const l of c.status.lines) console.log(`    ${l}`);
}

head('5. When a note may show (in this order)');
console.log('off, kind, muted, away (nudges), card in front, typing, another note, a note in the last 60 s (not the recap), already nudged, recap already given.');
console.log(`A refused nudge is kept ${core.HOLD_MS.nudge / 1000} s, a recap ${core.HOLD_MS.recap / 60000} min, then dropped silently. Away: lock, sleep, screen off, or ${core.IDLE.AWAY_S / 60} min idle; back when the last of them ends.`);
```

- [ ] **Step 6: Write the fixture**

Run: `node scripts/gen-sidekick-fixtures.mjs`
Expected: `wrote 10 fixture files to tests/fixtures/sidekick`.

- [ ] **Step 7: Run the tests and watch them pass**

Run: `node --test tests/sidekick/*.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)" && bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "✓|✗" | tail -3`
Expected: PASS: `# tests 46`, `# pass 46`, `# fail 0`, then `✓ 10 fixture files match sidekick-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 8: Bite: change a number on purpose and watch the checks catch it**

```bash
BK="$(mktemp -d "${TMPDIR:-/tmp}/nm-bite.XXXXXX")" && cp shared/sidekick-core.js "$BK/"
sed -i '' "s/Array.from(t).length > 200/Array.from(t).length > 201/" shared/sidekick-core.js
bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|^not ok"
cp "$BK/sidekick-core.js" shared/sidekick-core.js
bash scripts/test-sidekick-contract.sh 2>&1 | tail -2
```

Expected: `not ok` for "the fixture: every sentence is accepted or refused as it records" and `# fail 1`; then after the copy back `✓ 10 fixture files match sidekick-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 9: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree's folder, and f1-0/sidekick-contract
MSG="$(mktemp "${TMPDIR:-/tmp}/nm-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): the local voice's sanity check and the owner's tables

acceptNicerLine() lets a local model's sentence replace a template only if it is one
short line with no URL, path, backtick or markdown, only numbers from the facts, and the
agent's name. print-sidekick-tables.mjs prints the rules as tables for the owner.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add shared/sidekick-core.js \
  scripts/gen-sidekick-fixtures.mjs \
  scripts/print-sidekick-tables.mjs \
  tests/sidekick/voice.test.mjs \
  tests/sidekick/print.test.mjs \
  tests/fixtures/sidekick/voice-cases.json
git status --short
git commit -F "$MSG"
```

Expected: `git status --short` lists only the files above (all staged). Never push.

- [ ] **Step 10: OWNER CHECKPOINT: print the rules and stop**

```bash
mkdir -p .superpowers/sdd/2026-10-14-f1-0-sidekick-contract
node scripts/print-sidekick-tables.mjs | tee .superpowers/sdd/2026-10-14-f1-0-sidekick-contract/tables.txt | wc -l
```

Expected: a few hundred lines under five headings: "1. Risk rules" (29 reasons, each with a sample request and its line, then six near misses), "2. Stuck rules" (the four rules and three timelines), "3. Recap" (up to fourteen samples), "4. \"What's Claude doing?\"" (eight samples) and "5. When a note may show". **Stop here.** Report the file's path and these points to the main session, which shows the tables to the owner and waits for the owner's go:

- the **sample lines** under permission requests: are the twelve high reasons the ones the owner means, and are the words right?
- the **four reasons this plan added** to the spec's table (`outside_project`, `rm_in_project`, `unknown_command`, `local_command`): is an unrecognised shell command (`npm run dev`, `make install`) being `medium` right, or too noisy?
- `rm -rf .` (the project folder itself) is `rm_recursive` (high); **reading** `~/.ssh/id_rsa` or `.env` is `read_only` (low), because the spec makes the sensitive-file rule a write rule;
- the **stuck timelines** and thresholds;
- the **recap samples**, including the wording of a line with errors or approvals and "40 or more steps";
- that the Codex, Gemini and Antigravity payload shapes are from their documentation (marked `docs` in `hook-cases.json`), so a captured sample of each would pin them.

Task 8 starts only when the main session says go. If the owner changes a rule, change `shared/sidekick-core.js` and the typed answer beside its case in `scripts/gen-sidekick-fixtures.mjs`, run `node scripts/gen-sidekick-fixtures.mjs`, run `bash scripts/test-sidekick-contract.sh`, and commit that as a fix commit before Task 8.

---
### Task 8: Docs, CI, the spec's lines and the final checks

**Files:**
- Create: `docs/SIDEKICK-CONTRACT.md`
- Edit: `shared/sidekick-core.js` and `scripts/gen-sidekick-fixtures.mjs` (their markers go), `.github/workflows/build.yml`, `CLAUDE.md`, `ARCHITECT.md`, `docs/superpowers/specs/2026-10-14-agent-sidekick-design.md`

- [ ] **Step 1: Write the contract document**

**Create `docs/SIDEKICK-CONTRACT.md`**

```
# The sidekick contract (sub-project F1-0)

The agent sidekick gives the cats four small useful things: a recap when you come back, a plain line under each permission request, a nudge when an agent looks stuck, and an
answer to "What's Claude doing?". Its brain is a set of plain rules. This document is the contract those rules keep, so the Mac app, the Windows and Linux app and the tests
agree. The design is `docs/superpowers/specs/2026-10-14-agent-sidekick-design.md`.

**`shared/sidekick-core.js` decides.** It is pure (no clock, no files, no network, no randomness: every rule is given the time it needs) and is the one source of truth, as
`design/prototype/cat-core.js` is for the cats. `node scripts/gen-sidekick-fixtures.mjs` writes `tests/fixtures/sidekick/*.json` from it, and both apps replay those files in
their own language. If an app and a fixture disagree, the core is right and the app is wrong.

## Files

| File | What it is |
|---|---|
| `shared/sidekick-core.js` | The rules. Loads in Node (`require`) and in a page (`globalThis.SidekickCore`). |
| `scripts/gen-sidekick-fixtures.mjs` | Writes the fixtures. Every case lists its input and, typed by hand beside it, the answer it must get: the generator stops if the core disagrees. `--check` fails on drift; `--out DIR` writes elsewhere. |
| `tests/fixtures/sidekick/*.json` | The ten fixture files (below). Generated: never edit by hand. |
| `tests/sidekick/*.test.mjs` | The rules' own tests (`node --test`): the fixtures replayed, the pinned thresholds, the leak checks, the fuzzes. |
| `scripts/test-sidekick-contract.sh` | Runs the tests, the no-drift check and the determinism check (two generator runs write identical bytes). CI runs it. |
| `scripts/print-sidekick-tables.mjs` | Prints the rules as tables for a person to read (the owner's checkpoint). |

Ports: Swift `Sidekick*.swift` (tested by `scripts/test-sidekick-*.sh`) and TypeScript `windows/src/sidekick/` (tested by `npm run check:sidekick`) replay the same files; the
Rust twin is the settings cleaner only. The fixtures hold whole numbers, text, booleans and null only (no `NaN`, no `Infinity`, no fractions): each port adds its own tests
for a non-finite number.

## What the sidekick never keeps

The prompt, the assistant's text, `transcript_path`, a tool's output, a command, a full path, a file's content. Events and the ledger hold a **basename**, a **command key**
(a hash) and counts. Every line the rules write holds a basename, a count, an agent's name or a number of minutes, and nothing else. Tests plant a marker in each of those
inputs and assert it never comes out.

## The rules

### `explain(agent, tool, toolInput, cwd, home) -> {risk, reasonId, line, target}`  (`explain-cases.json`)

Says how risky one permission request is. It **labels only**: it never allows, denies or blocks; only the user's click does. `agent` is reserved (every agent is read the same
way). A shell command is split at `&&`, `||`, `;`, `|`, `&` and newlines (respecting quotes), a leading `cd`, `sudo`, `doas`, `env VAR=1`, `VAR=1`, `time`, `command` and
`nohup` are looked through, `bash -c "..."` is read through to two levels, and the request takes the highest risk of its parts (on a tie the earlier reason of the table).
What it can't read safely (an open quote, `$(...)`, backticks, `<(...)`, a here-document, `eval`, a script file, `find -delete`) is `medium` / `unsure`. It never throws.
Paths are resolved against `cwd` with `~`, `$HOME`, `..` and Windows drive letters; "outside the project" means outside `cwd`.

Reasons (the first twelve are the spec's high ones; the order is the tie-break):

| Risk | Reason ID | Line (`{name}` is a basename, at most 60 characters) |
|---|---|---|
| high | `rm_recursive` | Deletes {name} and everything inside it. |
| high | `sudo` | Runs a command with admin rights. |
| high | `pipe_to_shell` | Downloads a script and runs it at once. |
| high | `chmod_recursive` | Changes permissions on {name} and everything inside it. |
| high | `git_force_push` | Overwrites the remote branch history. |
| high | `git_reset_hard` | Throws away local changes. |
| high | `git_clean` | Deletes files git doesn't track. |
| high | `disk_write` | Writes straight to a disk. |
| high | `sql_drop` | Deletes a database table or database. |
| high | `sql_delete_all` | Changes every row in a table. |
| high | `sensitive_file` | Changes {name}, which can hold secrets or settings. |
| high | `write_outside` | Changes {name}, outside this project. |
| medium | `git_push` | Sends commits to a remote. |
| medium | `install` | Installs software. |
| medium | `network_fetch` | Talks to another computer. |
| medium | `container` | Controls containers. |
| medium | `lockfile_ci` | Changes {name}, which affects every build. |
| medium | `mcp_tool` | Uses a tool from an add-on. |
| medium | `unknown_tool` | Uses a tool NotchMeow doesn’t know. |
| medium | `unsure` | NotchMeow can’t tell what this does. |
| medium | `outside_project` | Touches {name}, outside this project. |
| medium | `rm_in_project` | Deletes {name} in this project. |
| medium | `unknown_command` | Runs a command NotchMeow doesn’t recognise. |
| low | `read_only` | Only reads files. |
| low | `test_build` | Runs the project's tests or build. |
| low | `edit_in_project` | Edits {name} in this project. |
| low | `web` | Reads a web page. |
| low | `subagent` | Starts a helper agent. |
| low | `local_command` | Does a simple local step. |

**Decisions where the spec was silent** (each is pinned by rows in `explain-cases.json`):
- Four reasons were added to the spec's first table, as the spec allows: `outside_project`, `rm_in_project`, `unknown_command` (all medium) and `local_command` (low).
- `rm -rf .` (the project folder itself) is `rm_recursive`; `rm -r ./build` is `rm_in_project`.
- A `>` or `>>` redirect is a write: into a sensitive file or outside the project it is high (`sensitive_file`, `write_outside`); into `/dev/...` it is `disk_write`; into `/dev/null` it is nothing.
- `.env*` includes `.env.example`; `.claude/settings*.json` and `.git/hooks/` are sensitive; `~/.ssh`, `~/.aws` and `~/.gnupg` are sensitive under the home that the caller passes in.
- **Reading the contents** of a secrets file is `reads_secrets` (medium), the owner's answer of 2026-10-14: the Read tool on it, or `cat`, `grep`, `head` and the like on it; writes and edits stay `sensitive_file` (high), and listing it (`ls ~/.ssh`) is not a read.
- `git push --force-with-lease` is a force push (`git_force_push`, high), by the owner's decision; `git push origin +main` is a force push too.
- `psql`, `mysql`, `sqlite3` and the like are read for `DROP` and for `DELETE` / `UPDATE` / `TRUNCATE` with no `WHERE`; any other statement through them is `unknown_command`.
- Codex: `tool_input.command` may be a list like `["bash","-lc","ls"]`, and `apply_patch` names its files in `*** Add/Update/Delete File:` lines. Gemini's `run_shell_command` and `write_file`, and PowerShell's `Remove-Item -Recurse`, `Get-*`, are read as their Claude Code counterparts. Other PowerShell cmdlets are `unknown_command`.

### `eventFrom(payload, now, opts) -> event | null`  (`hook-cases.json`, `cases`)

Turns a hook payload into the event the ledger takes. `now` is the time the app received it (ms). `opts.codex` is false in the App Store build. It accepts the names the
relays send and the agents' own (`BeforeTool`, `AfterTool`, `BeforeAgent`, `AfterAgent`, `PreInvocation`, `PostInvocation`, `startup`, `exit`). An event it doesn't know, a payload
that is not an object and a time that is not a number give `null`.

An event is `{at, agentId, sessionId, kind, name, tool, target, file, key, ok, project, subagentId}`. `kind` is one of `sessionStart`, `prompt`, `preTool`, `question`, `tool`, `failure`,
`approvalAsked`, `approvalAnswered`, `stop`, `stopFailure`, `subagentStart`, `subagentStop`, `sessionEnd`, `notification`. `agentId` is the pill: a valid `nm_agent`
(lower case, digits and hyphens, at most 24, and not `claude`) is `agent_<name>`, Codex is `agent_codex`, Cursor's bundle ID is `agent_cursor`, anything else is
`integration_claude`. A question (`AskUserQuestion`) is `question`, not an approval. `target` is the first file's basename, or the **command key**. `project` is the basename of `cwd`.
The app makes the one event that is not a hook: `approvalAnsweredEvent(agentId, sessionId, now)`, for the user's click.

**The command key** is `tool#` plus the FNV-1a (32 bits, 8 lower-case hex digits) of the canonical JSON of the tool input: keys sorted, no spaces, a command's whitespace
folded and trimmed. Only the hash is stored. It needs valid Unicode; the fixtures' keys are ASCII.

**Where the payload shapes come from.** Each case says `source`: `repo` is an event the app already sends (its scenarios and QA brief), `docs` is the agent's documentation, written
down before a real session was captured (`PostToolUseFailure`, `StopFailure`, `Notification`, `SubagentStop`, and all of Codex, Gemini and Antigravity). Replace a `docs`
payload with a captured one when there is one. The Windows relay drops `tool_response` and `transcript_path` and cuts strings at 2000 bytes: a Windows-shaped case is included.

### `ledgerApply(ledger, event) -> ledger`  (`hook-cases.json`, `sequences`)

One small record per session, keyed `agentId|sessionId`, memory only: `{key, agentId, sessionId, startedAt, lastEventAt, endedAt, state, last, project, ring, pendingApprovalAt,
pendingKey, subagents, nudgedAt}`. `ring` keeps the last 40 entries `{at, kind, tool, target, file, key, ok}` (kinds `tool`, `failure`, `approvalAsked`, `approvalAnswered`, `stop`,
`stopFailure`, `subagentStart`, `subagentStop`). `state` uses the cat's words (idle, thinking, working, searching, approval, question, finished, error); a search tool is
searching. `last` is the kind of the last event; `subagents` maps an alive helper's id to its start (the spec's `subagentsAlive` is its size: `aliveSubagents(session)`). A
session ends at `SessionEnd` plus 30 minutes, or 12 hours after its last event if it never ended (`ledgerPrune`); at most 8 are kept, a finished one going first, the oldest
first. A request waits in `pendingApprovalAt` until the same step finishes (the same command key), the turn ends or the user answers. The ledger given is never changed.

### `stuckStep(ledger, now, ctx) -> {nudge, nextAt}`  (`stuck-cases.json`)

At most one nudge, and the earliest future deadline of the waiting and quiet rules for the one-shot timer (null when nothing is live: the clock then isn't set). `ctx` is
`{ratelimit, away, cardShown, platform}`. Kinds, tried in this order: `stuck.loop` (the same tool and key 4 times in the last 8 calls, within 10 minutes, no successful
edit or write after the first of them), `stuck.errors` (3 failures in a row within 10 minutes, Claude Code only), `stuck.waiting` (a request unanswered for 60 s whose card
is not on screen; its words change in place after the platform's give-up time: the Mac gives up at 115 s, Windows and Linux at 110 s), `stuck.silent` (5 minutes after a finished step, a prompt or a
subagent's stop, 15 minutes after a step that began and never ended; never while a helper is under 10 minutes old). A session is nudged once (`markNudged`); nothing is said
while the user is away or in the rate-limit state. `nudgeText` gives the fixed words. The thresholds are in the fixture so a port can compare its own.

### `recapOf(snapshot)`, `statusOf(snapshot, agent)`, `matchStatusQuestion(text)`  (`recap-cases.json`, `status-cases.json`)

`recapOf({awaySince, now, sessions})` is `{lines, facts}` or null: null when the user was away under 2 minutes or no ring entry is at or after `awaySince`. One line per agent
(sessions of one agent merge), the agent that spoke last first, at most 3, then `+N more`. A line is "While you were away, {Agent} in {project} ran {n} steps (1 error, 2
approvals asked), edited a, b and c, and finished." with at most 3 file names then "and k more", "40 or more steps" when the ring was full, and a tail of `finished`, `is waiting
for your OK`, `stopped on an error`, `is waiting for your answer`, `is still working` or `has been quiet for {n} minutes`. `facts` is the same in numbers and names
(`agent, agentId, project, steps, stepsAtLeast, files, more, errors, approvals, end, quietMinutes`): the only thing the local voice may be given.

`statusOf({now, sessions}, agentId?)` uses the same templates over everything the ledger holds ("has run" for "ran"), for the sessions that have not ended (a finished one for 10
minutes), or one agent; "No agent is running right now." / "{Agent} is not running right now." when there are none. It is answered on this machine and never added to a conversation.

`matchStatusQuestion(text)` is `{matched, agentId}`. The whole message must be short (80 characters) and, lower-cased and stripped of punctuation, one of: `status`, `agent status`,
`{agent} status`, `what is / what's {agent} doing`, `what are the / my agents doing`, with an optional "right now" or "now". Anything longer or different is a normal chat message.

### `dismiss`, `muted`, `unmute`, `cleanSidekickSettings`  (`dismiss-cases.json`, `settings-cases.json`)

The five kinds are frozen: `recap`, `stuck.loop`, `stuck.errors`, `stuck.waiting`, `stuck.silent`. A click on Not now, OK or x is a dismissal (folding the island unseen isn't: that is
the app's call); two mute a kind; Unmute sets it to 0. The risk badge and the permission line are not a kind and are never muted. `cleanSidekickSettings(raw)` is
`{on, local, dismissals}`: a switch is on unless it is `false`, a count is a whole number from 1 to 2 (anything else is 0), unknown kinds and fields are dropped; cleaning twice is cleaning once.
It is a clean-up of its own: no existing settings fixture changes.

### `presenceStep(state, signal, now)`  (`presence-cases.json`)

`state` is `{reasons, awaySince, wasAway}`. Signals: `lock`, `unlock`, `sleep`, `wake`, `displayOff`, `displayOn`, and `{type: 'idle', seconds}`. The user is away while any reason holds;
idle of 300 s or more adds `idle` (the away began `seconds` ago), a sample under 3 s removes it, samples between change nothing. It returns `{state, back}` where `back` is false or
`{back: true, awaySince, awayMs}`, told once when the last reason lets go.

### `shouldShow(input)`  (`show-cases.json`)

`{show, reason, replace}`. The reasons are tried in this order: `off`, `kind`, `muted`, `away` (nudges only), `card` (an approval or a question is in front; for the waiting nudge its own
card must not be on screen), `typing`, `busy` (another note is visible; a recap replaces a nudge nobody has seen), `recent` (a note showed in the last 60 s; not for the recap), `nudged`,
`recapGiven`. A refused note is kept `HOLD_MS` (30 s for a nudge, 2 minutes for a recap) and shown if the gate opens, then dropped silently. The drop's confirmation line is user-started and skips the gate.

### `acceptNicerLine(line, facts)`  (`voice-cases.json`)

Guards the swap of a template for a sentence from a local model: one line, at most 200 characters, no URL, `/`, `\`, backtick or markdown, only numbers from the facts, and the name of an agent of the facts.

## Known limits

- The risk rules are heuristics. They label; `unsure` exists; near misses are pinned. They do not parse every shell: PowerShell is read for a few cmdlets only, and a script file is `unsure`.
- Codex, Gemini and Antigravity payload shapes are from their documentation (marked `docs`), not from captured sessions.
- Canonical JSON sorts keys by UTF-16 code unit; a port must sort ASCII keys the same way (the fixtures' keys are ASCII).
- Away from the OS differs by platform (the apps' plans say how); the rules take the signals as given.

## Changing it

Only new names and new files: `tests/fixtures/cat/`, `tests/fixtures/ai/`, the shelf's fixtures and `design/prototype/cat-core.js` stay byte for byte (`node scripts/check-fixtures-additive.mjs <base>` and `git diff --quiet <base> -- ...`).
The five dismissal kinds and the reason IDs are frozen like the cat and pill IDs: a reason may be added, none is renamed. After changing the core, run `node scripts/gen-sidekick-fixtures.mjs` and commit the fixtures with it.
```

- [ ] **Step 2: Take the markers out, put the test in CI, and add the pointers**

The two marker lines were scaffolding for the tasks. The CI step runs after "Cat contract" (the same Node). `CLAUDE.md` and `ARCHITECT.md` get one bullet each. The spec's F1-0 lines say what the tasks turned out to be.

**Edit `shared/sidekick-core.js`**

Find (it occurs once):

```js
// @@NEXT (the next task's rules go above this line)

return api;
```

Replace with:

```js
return api;
```

**Edit `scripts/gen-sidekick-fixtures.mjs`**

Find (it occurs once):

```js
// @@SECTIONS (the next task's fixtures go above this line)

/** Every fixture file as text, by name. */
```

Replace with:

```js
/** Every fixture file as text, by name. */
```

**Edit `.github/workflows/build.yml`**

Find (it occurs once):

```yaml
      - name: Cat contract (cat-core.js self-checks, fixtures, determinism)
        run: bash scripts/test-cat-contract.sh
```

Replace with:

```yaml
      - name: Cat contract (cat-core.js self-checks, fixtures, determinism)
        run: bash scripts/test-cat-contract.sh

      - name: Sidekick contract (sidekick-core.js tests, fixtures, determinism)
        run: bash scripts/test-sidekick-contract.sh
```

**Edit `CLAUDE.md`**

Find (it occurs once):

```
- `docs/SPEC.md`, `docs/INTEGRATIONS.md` — behaviour, views, states, integrations (in French).
```

Replace with:

```
- `shared/sidekick-core.js` — the agent sidekick's rules (sub-project F1): the risk label under a permission request (`explain`), the session ledger (`eventFrom`, `ledgerApply`), the stuck nudges (`stuckStep`), the recap and the status answer (`recapOf`, `statusOf`, `matchStatusQuestion`), dismissals and the Sidekick settings (`dismiss`, `muted`, `unmute`, `cleanSidekickSettings`), away detection (`presenceStep`), the show gate (`shouldShow`) and the local voice's sanity check (`acceptNicerLine`). Pure, shared by Node and the apps' tests. `node scripts/gen-sidekick-fixtures.mjs` writes `tests/fixtures/sidekick/` from it (`--check` fails on drift), `bash scripts/test-sidekick-contract.sh` runs the lot, `node scripts/print-sidekick-tables.mjs` prints the rules as tables, and `docs/SIDEKICK-CONTRACT.md` documents them. If an app and a fixture disagree, `sidekick-core.js` decides. The sidekick labels and remembers: it never allows or denies, and keeps no prompt, no assistant text, no command and no full path.
- `docs/SPEC.md`, `docs/INTEGRATIONS.md` — behaviour, views, states, integrations (in French).
```

**Edit `ARCHITECT.md`**

Find (it occurs once):

```

## Code map (graphify)
```

Replace with:

```
6. **Sidekick (sub-project F1).** The cats say something useful at task boundaries: a recap on return, a plain line and a risk label under a permission request, a nudge when an agent looks stuck, and "What's Claude doing?" in the chat. The brain is pure rules in `shared/sidekick-core.js` (no AI, always on; a local model may only polish a sentence), fed by a ledger of the hook events each app already receives and tested against `tests/fixtures/sidekick/` (`docs/SIDEKICK-CONTRACT.md`). It labels and remembers, never decides: only the user's click answers a request.

## Code map (graphify)
```

**Edit `docs/superpowers/specs/2026-10-14-agent-sidekick-design.md`**

Find (it occurs once):

```
`echo "sudo"` is not `sudo`).
```

Replace with:

```
`echo "sudo"` is not `sudo`). F1-0 added four reasons the first table did not have, as this section allows: `outside_project`, `rm_in_project` and `unknown_command` (medium) and `local_command` (low), and wrote the decisions where the table was silent in `docs/SIDEKICK-CONTRACT.md`.
```

**Edit `docs/superpowers/specs/2026-10-14-agent-sidekick-design.md`**

Find (it occurs once):

```
Codex's shell tool is read as the shell tool once F1-0 pins its tool name from a real-shaped fixture.
```

Replace with:

```
Codex's shell tool (`Bash`, `shell`, `local_shell` or `exec_command`, with a string or an argv list as its command) and its `apply_patch` are read in F1-0 from the documented shapes. A payload captured from a real Codex session should replace them: every payload in `hook-cases.json` says whether its shape is `repo` (the app already sends it) or `docs` (only the agent's documentation shows it).
```

**Edit `docs/superpowers/specs/2026-10-14-agent-sidekick-design.md`**

Find (it occurs once):

```
- **`docs/SIDEKICK-CONTRACT.md`** documents them.
```

Replace with:

```
- **`docs/SIDEKICK-CONTRACT.md`** documents them, and **`scripts/print-sidekick-tables.mjs`** prints the rules as tables for a person to read.
```

**Edit `docs/superpowers/specs/2026-10-14-agent-sidekick-design.md`**

Find (it occurs once):

```
About 8 tasks: the core's `explain`;
```

Replace with:

```
Eight tasks, in `docs/superpowers/plans/2026-10-14-f1-0-sidekick-contract.md`: the core's `explain`;
```

**Edit `docs/superpowers/specs/2026-10-14-agent-sidekick-design.md`**

Find (it occurs once):

```
- **Owner checkpoint:** a table of sample requests with their risk and line, a sample recap, and a stuck timeline.
```

Replace with:

```
- **Owner checkpoint:** `node scripts/print-sidekick-tables.mjs` prints a table of the risk reasons with a sample request and its line, the stuck thresholds with a timeline for each, and the recap and status samples.
```

- [ ] **Step 3: The final checks**

```bash
bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓|✗"
bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|identical"
node scripts/check-fixtures-additive.mjs 793b502 | tail -1
git diff --quiet 793b502 -- tests/fixtures/ai tests/fixtures/cat tests/fixtures/mac design shared/theme.json && echo "existing fixtures and the prototype untouched"
bash scripts/check-no-leftovers.sh 2>&1 | tail -2
grep -rniE 'coucou|mochi' shared/sidekick-core.js scripts/gen-sidekick-fixtures.mjs scripts/print-sidekick-tables.mjs tests/sidekick docs/SIDEKICK-CONTRACT.md tests/fixtures/sidekick; echo "grep exit $?"
grep -c "@@NEXT\|@@SECTIONS" shared/sidekick-core.js scripts/gen-sidekick-fixtures.mjs
git status --short
```

Expected: `# tests 46`, `# pass 46`, `# fail 0`, ten `✓ ... matches sidekick-core.js` lines, `✓ 10 fixture files match sidekick-core.js` and `✓ two generator runs write identical bytes`; for the cat contract `# tests 288`, `# pass 288`, `# fail 0` and the identical-bytes line; `✓ fixtures changed only by addition since 793b502`; `existing fixtures and the prototype untouched`; two `✓` lines from the leftovers guard; `grep exit 1` (nothing found); `shared/sidekick-core.js:0` and `scripts/gen-sidekick-fixtures.mjs:0`; and a status listing only the files of this task plus `docs/SIDEKICK-CONTRACT.md`.

- [ ] **Step 4: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree's folder, and f1-0/sidekick-contract
MSG="$(mktemp "${TMPDIR:-/tmp}/nm-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
docs(sidekick): the contract document, CI, and the pointers

SIDEKICK-CONTRACT.md documents the rules, the shapes, the decisions made where the spec
was silent and the known limits. CI runs the contract script after the cat contract.
CLAUDE.md and ARCHITECT.md get a bullet each, and the spec's F1-0 lines say what the
tasks turned out to be.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add docs/SIDEKICK-CONTRACT.md \
  shared/sidekick-core.js \
  scripts/gen-sidekick-fixtures.mjs \
  .github/workflows/build.yml \
  CLAUDE.md \
  ARCHITECT.md \
  docs/superpowers/specs/2026-10-14-agent-sidekick-design.md
git status --short
git commit -F "$MSG"
```

Expected: `git status --short` lists only the files above (all staged). Never push.

---

### After Task 8: the whole-branch review

Dispatch `nm-reviewer-deep` (Sonnet 5.5, high; trigger 4) over `git diff notchmeow/rebrand...HEAD`. Its brief names: the five Review Focus items; the spec's "Risk rules", "The ledger", "Stuck rules" and "Contract"; that the privacy rule holds (no prompt, assistant text, `transcript_path`, command, full path or content in any event, ledger, line, fact or fixture: read `hook-cases.json` and the recap fixtures for secrets); that every typed answer in the generator is what the spec says and not merely what the core says; that nothing a port would need is ambiguous (key order, number formats, Unicode); and that no existing fixture changed. Fix what it finds, and re-run Task 8 Step 3.

## The owner's answers (2026-10-14)

The owner approved the spec and this plan, with one change to the risk rules:
- **Reading a secrets file is MEDIUM.** A Read (or a read-only command such as `cat`) of `.env`, a private key, `~/.ssh`, `~/.aws` or a shell rc file gets the reason `reads_secrets`, risk `medium`, line "Reads {name}, which can hold secrets." Writes to them stay `sensitive_file`, `high`. In Task 1, add the reason, its line, and cases (Read of `.env`, Read of `~/.ssh/id_ed25519`, `cat .env`) next to the `Write of .env` row; run the bite step for it.
- The rest as drafted: `rm -rf .` inside the project is high; `npm run dev`, unknown commands and project scripts are medium (grey line only; only high gets the badge); the four added reasons stay; Codex, Gemini and Antigravity payloads come from their docs and are marked so in the fixtures; in One cat mode the grid cats are not drop targets.
