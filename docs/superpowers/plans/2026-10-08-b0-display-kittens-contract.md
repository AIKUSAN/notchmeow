# B-0 Display Modes, Kittens and Small Eyes Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give both apps what sub-project B needs from the shared contract before the app plans run: the pure rules for the Display settings, the agents' coats, the cast of each display mode, the subagent kittens and the small coloured eyes, all in `design/prototype/cat-core.js` and pinned by five new fixtures, and the prototype page that draws them, which the owner approves at a checkpoint. The apps use none of it yet: that is the B-mac and B-tauri plans.

**Architecture:** Five new sections go into the one plain script, above the end-of-core marker, each reusing what is already there (`CAT_IDS`, `catIdOf`, `kittenOf`, `toolState`, `STATES`, `BUSY`, `SLEEP_AFTER_MS`, `isPlain`, `own`). The Display settings get a clean-up of their own, `cleanDisplaySettings`, and not new fields on `cleanCatSettings`: new fields would change every line of `settings-cases.json`, and the fixtures may change only by addition. `scripts/gen-cat-fixtures.mjs` gains five builders and writes five new files; `scripts/check-fixtures-additive.mjs 6c14947` proves that no existing line moved. The prototype page gets a Display switch whose mocks are driven by `castOf`, kittens drawn from `kittenStep` and `kittenSlots`, the coloured small eyes drawn from `smallEye`, and a small-eye contact sheet. The owner's screenshots are taken headless with `playwright-cli` against a local static server.

**Tech Stack:** JavaScript (one file for a browser and Node 22), `node:test` and `node:assert` (no npm packages), Bash, Python 3 for the patches, `playwright-cli` with its cached browsers for the screenshots.

**Spec:** `docs/superpowers/specs/2026-10-08-display-modes-kittens-design.md`, section 5 step 1 (the contract) with sections 1 to 4 for the rules: §1 "Settings and persistence", §2 "Which cat appears where", §3 "Kittens", §4 "Coloured eyes for small cats". It extends `docs/CAT-CONTRACT.md` and `design/prototype/cat-core.js` as merged by A (plan `2026-10-07-a0d-cat-settings-theme.md` is the format). Read the whole spec before starting.

**Base:** branch `b0/display-kittens-contract`, created from `notchmeow/rebrand` at `6c14947` or later, with this plan file already committed to `notchmeow/rebrand`. The cat contract must still be the one from `6c14947` (138 self-checks, 9 fixtures): the additive check compares with that commit. This plan touches no app code under `NotchBuddy/` or `windows/`. **It changes no pixel and no behaviour in either app.** In the prototype page it changes the look of compact cats on purpose (their eyes: spec §4) and adds the Display mocks.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec; the lines marked "(plan decision)" are choices this plan makes where the spec is silent, and are listed again under "Open questions for the owner".

- **Cat IDs are frozen contract values, in this order:** `shrimpy`, `momo`, `ginger`, `midnight`, `latte`, `patches`, `blue`, `snow`, `oreo`, `mocha`, `silver`, `cloud`, `leo`, `button`, `puff`, `noodle`. **Collar style IDs:** `tag`, `band`, `kerchief`, `off`. **Pill IDs** are stable contract values. **The display mode IDs `one`, `perAgent` and `two` are frozen from now on**, in that order; an unknown stored mode is `one`.
- **The modes (spec §1, §2):** One cat (the default, the Main cat everywhere); A cat for each agent; Two cats (a pair, Shrimpy and Momo by default, both pickable; if both are the same coat, cat 2 becomes the next coat in `CAT_IDS` order). "Character" is renamed "Main cat".
- **Agent pills** are `integration_claude` (despite its prefix) and every `agent_*` pill; **integration pills** are the other declared pills (spec §2).
- **Agents' cats (spec §1):** `integration_claude` is `shrimpy` and `agent_codex` is `momo` by default. Any other agent pill, the first time it is seen, gets a random coat used neither by another agent nor as the Main cat, and keeps it; when all 16 are taken, the least-used coat, ties in `CAT_IDS` order. The random source is injected (`rand()`, 0 up to, not including, 1).
- **Storage (spec §1):** macOS `cat.displayMode`, `cat.pair` (JSON, two cat IDs), `cat.agentCat.<pillId>`; Windows/Linux `displayMode`, `pair` and `agentCats` in the `cat` block. An unknown mode is `one`, a bad pair is Shrimpy and Momo, an unknown or bad agent coat is that agent's default (dropped for an agent without a default), an unknown pill ID is kept. Kittens are never stored.
- **The busiest other agent (spec §2):** among the agent pills other than the focused one: a waiting approval or question, then an error, then working, thinking or searching, then the most recent event. The pills show the tasks other than the focus, the first four; in Two cats mode the second agent leaves the row too.
- **Kittens (spec §3):** `SubagentStart` adds one; tool events with an `agent_id` set its state (searching for a tool in `search-tools.json`, else working; approval while its permission request waits); `SubagentStop` plays a happy blink of about 0.6 s and removes it; the parent's stop or the session ending removes all; the 10-minute sleep timer sweeps the stale; at most 8 per agent, the oldest dropped first; order: approval first, then the newest. Placement: up to 3 under the big cat (expanded), up to 2 beside it (compact), a count only by the pair (compact), up to 3 under each pair cat (expanded), up to 3 at the trailing end of an agent pill, then "+N". Sizes from the brainstorm mockup: Ø15 under a Ø58 cat, Ø12 beside a Ø20 cat, Ø15 in a 28-high pill.
- **Small eyes (spec §4), the starting values:** iris 0.42 R wide and 0.46 R tall, pupil 0.18 R by 0.40 R, catchlight radius max(0.075 R, 0.45 pt) at (-0.11 R, -0.10 R), rim max(0.05 R, 0.5 px); kittens keep their larger, rounder eyes; a blink or squint closes the eye to a line; the expression shapes stay ink; colours are the coat's `iris` / `irisR` and the theme's pupil colour.
- **Tolerance:** fixtures store 12 significant digits and apps compare within **1e-9**. There are no pixel tests.
- **`cat-core.js` is the tie-breaker:** it stays numbers in, numbers out: no canvas, no DOM, no clock, no `Math.random`. Randomness comes in only through an injected `rand()`.
- **Fixtures change only by addition:** five new files (`display-cases.json`, `agent-cat-cases.json`, `cast-cases.json`, `kitten-cases.json`, `small-eye-cases.json`). Every existing line stays byte-identical. `node scripts/check-fixtures-additive.mjs 6c14947` proves it.
- **Never restyle what ships.** The prototype is the visual source of truth for new character work. Its existing panels stay as they are. The deliberate exceptions, all in the page and all named in Task 6: the compact cats' eyes (spec §4), the "Character" row label (spec §1 renames it "Main cat"), one sentence of the Size ladder's text (it said "ink eyes"), the notch mock's expanded size and rows (now driven by the cast), and a `data:` favicon so the console stays empty.
- **Node standard library only, no npm packages;** Node 22 or newer. Same code style as the core: compact one-liners with a comment above, plain commented code elsewhere.
- **Nothing of Coucou's comes back, and the names Coucou and Mochi appear in no new code** (`mocha` is a coat). `scripts/check-no-leftovers.sh` reads `scripts/` and `tests/`: it must stay green.
- **Commits:** local only, never pushed. End every commit message with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`, or with the model that wrote it when an implementer runs on another one (the light tasks below name `Claude Haiku 4.5`).
- **House rules for the session:** install nothing and download nothing (`npx --no-install` only, never `npm install`, `npm run build` or `npm run dev`; `playwright-cli` uses the browsers already cached); never launch, quit or replace a NotchMeow app; use `trash` and not `rm -rf` for anything you delete by hand; the static server listens on `127.0.0.1` only, and every server and browser you start is stopped before the task ends; screenshots are saved outside the repository, in `${TMPDIR:-/tmp}/b0-shots`; if a command is denied by a permission prompt, stop and report it.

## Review Focus

The spec says what the rules are. It is silent on these inputs, and each would bite a person (or a port) first. Each line names its test.

1. **A hostile settings file for the pair and the agents' coats:** a pair that is cut-off JSON text, has three IDs or an unknown coat; an `agentCats` map with `__proto__`, `constructor`, capital letters, a trailing newline in an ID, or 300 entries. Expected: Shrimpy and Momo, a map without the bad keys, never a throw, nothing on `Object.prototype`. Tests: Task 1 "the pair…", "pill IDs…", "the agent coats: hostile maps…", "at most 256…" and the 3000-case fuzz; the fixture's `pairs`, `agentCats` and `pillIds` rows.
2. **A new agent when the coats run out, or the dice and the random source misbehave:** all 16 coats in use, the Main cat equal to a default coat, a default coat replaced by a stored one, `rand()` returning 1, NaN or text. Expected: the least-used coat with ties in `CAT_IDS` order and no random draw; a freed default is free again; the dice never gives the same coat back; a bad `rand` is 0. Tests: Task 2 "when all 16 coats are taken…", "a default coat that a stored coat has replaced…", "the dice…", "a random source that misbehaves…", and the 2000-state comparison with the rule written the long way.
3. **Lost, late and repeated subagent events:** a stop that never comes, a tool or permission event after the stop or for an id that never started, a repeated start, a ninth kitten, a parent that ends while kittens leave, two sessions of one agent in one pill, an event with no time. Expected: stale kittens go on the parent's stop, the session's end or the sleep sweep; a late event brings nothing back; at most 8; malformed events change nothing. Tests: Task 4 "a tool event for an id with no kitten…", "SubagentStop…", "the sleep timer's sweep…", "at most eight kittens…", "two sessions…", "an event that is malformed…" and the 4000-event fuzz.
4. **An island with nothing to show:** no other agent, a focus that is an integration, null or not in the list, a pill listed twice, more than four pills, a state or a time that is not valid. Expected: cat 2 idles with no pill, integrations are never the second cat, the row is at most four with nothing shown twice, an invalid state is idle. Tests: Task 3 "with no other agent…", "the row and the grid…", "hostile input never throws…" and the 500-island comparison.
5. **The smallest and the blinking eye:** Ø6 heads (the floors of the catchlight and the rim), a squint just above and below the threshold, the biggest gaze, a kitten, an expression scale of 0 or 1.5, and numbers that are not numbers. Expected: the floors hold, the pupil never leaves the iris, under 0.22 the eye is the closed line, nothing is NaN. Tests: Task 5 "the floors…", "a blink or a squint…", "the pupil never leaves the iris…", "numbers that are not numbers…".

---

## File Structure

| Path | Responsibility |
|---|---|
| `design/prototype/cat-core.js` | The contract. Five new sections above the end-of-core marker: "Display modes: the stored settings" (`DISPLAY_MODES`, `displayModeOf`, `DEFAULT_PAIR`, `DEFAULT_AGENT_CATS`, `MAX_AGENT_CATS`, `PILL_ID`, `isPillId`, `isAgentPill`, `defaultAgentCat`, `cleanPair`, `cleanAgentCats`, `cleanDisplaySettings`, `defaultDisplaySettings`); "giving agents their cats" (`pickCat`, `agentCatFor`, `rerollAgentCat`, `assignAgentCats`); "which cat appears where" (`PILL_ROW`, `busyRank`, `castOf`); "Kittens" (`KITTEN_MAX`, `KITTEN_LEAVE_MS`, `KITTEN_STATES`, `cleanKittens`, `kittenStep`, `kittenOrder`, `kittenView`, `KITTEN_PLACES`, `kittenPlaceOf`, `kittenSlots`); "Small eyes" (`SMALL_EYE_SHAPES`, `SMALL_EYE`, `usesSmallEye`, `smallEye`). |
| `scripts/gen-cat-fixtures.mjs` | Gains five builders above the `@@BUILDERS` marker, and exports `randFor`, the harness's random source. |
| `tests/fixtures/cat/display-cases.json`, `agent-cat-cases.json`, `cast-cases.json`, `kitten-cases.json`, `small-eye-cases.json` | New fixtures (generated: about 38, 17, 93, 49 and 61 KB). |
| `tests/cat/display.test.mjs`, `agentcat.test.mjs`, `cast.test.mjs`, `kittens.test.mjs`, `smalleye.test.mjs` | New self-checks (14, 14, 11, 25 and 11) and fixture replays (3 each). |
| `tests/cat/fixtures.test.mjs` | The file list gains the five files (14 files) and its title loses the number. |
| `design/prototype/notchmeow.html` | The Display switch and the cast-driven mocks, kittens beside their parent, the coloured small eyes, the small-eye contact sheet. |
| `docs/CAT-CONTRACT.md` | Three rows of the API table, five rows of the fixture table, a section "Display modes, agent coats, kittens and small eyes" and six decisions. |
| `CLAUDE.md`, `ARCHITECT.md` | One pointer each. |
| `docs/superpowers/specs/2026-10-08-display-modes-kittens-design.md` | Three small edits, so the spec says what the contract does (the separate clean-up). |
| `${TMPDIR:-/tmp}/b0-shots/` | The owner's screenshots. Outside the repository, never committed. |

The "prove it bites" steps (Tasks 1 to 5) are one-offs and are never committed. **CI needs no change:** `scripts/test-cat-contract.sh`, which CI already runs, globs `tests/cat/*.test.mjs` and its `--check` covers every builder in the generator, so the five new test files and fixtures are picked up on their own.

**Order of tasks:** the rules and their fixtures one by one, each with its own tests (1 Display settings, 2 agents' coats, 3 the cast, 4 kittens, 5 small eyes), then the prototype, then the screenshots for the owner's checkpoint, then the docs.

1. Display settings: `cleanDisplaySettings` and `display-cases.json`
2. Giving agents their cats: `agentCatFor` and `agent-cat-cases.json`
3. The cast of each mode: `castOf` and `cast-cases.json`
4. Kittens: `kittenStep`, `kittenSlots` and `kitten-cases.json`
5. Small coloured eyes: `smallEye` and `small-eye-cases.json`
6. The prototype
7. Owner checkpoint: screenshots
8. Docs and the final checks

## Tasks and agents

CLAUDE.md: the lightest model that fits. Tasks 1 to 5 and 8 give every line of their code and docs, so they are transcription: `nm-implementer-light` (Haiku 4.5). Task 6 also gives its patch in full, but it loads a page in a headless browser and judges what it draws, and Task 7 reads screenshots and reports what they show, so both are `nm-implementer` (Sonnet 5.5, medium). Each task is then reviewed by `nm-reviewer`; the whole branch by `nm-reviewer-deep` after Task 8. If a step's expected output differs and the cause is not obvious, hand that task to `nm-implementer-deep`.

| Task | Deliverable | Agent | Review |
|---|---|---|---|
| 1. Display settings | `cat-core.js` section, `tests/cat/display.test.mjs` (14 self-checks, 3 replays), `display-cases.json` | `nm-implementer-light` | `nm-reviewer` |
| 2. Agents' cats | `cat-core.js` section, `tests/cat/agentcat.test.mjs` (14 + 3), `agent-cat-cases.json` | `nm-implementer-light` | `nm-reviewer` |
| 3. The cast | `cat-core.js` section, `tests/cat/cast.test.mjs` (11 + 3), `cast-cases.json` | `nm-implementer-light` | `nm-reviewer` |
| 4. Kittens | `cat-core.js` section, `tests/cat/kittens.test.mjs` (25 + 3), `kitten-cases.json` | `nm-implementer-light` | `nm-reviewer` |
| 5. Small eyes | `cat-core.js` section, `tests/cat/smalleye.test.mjs` (11 + 3), `small-eye-cases.json` | `nm-implementer-light` | `nm-reviewer` |
| 6. The prototype | `notchmeow.html` patched, loaded and clicked through in a headless browser, console empty | `nm-implementer` | `nm-reviewer` |
| 7. Owner checkpoint | 8 screenshots in `${TMPDIR:-/tmp}/b0-shots`, and a stop | `nm-implementer` | the owner |
| 8. Docs, final checks | `CAT-CONTRACT.md`, two pointers, three spec edits, every check | `nm-implementer-light` | `nm-reviewer` |
| After Task 8 | The whole branch: cross-task contracts, privacy and security rules | `nm-reviewer-deep` | n/a |

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). The Task 6 and 7 agents also load `playwright-cli`.

## Execution

One worktree chat session runs the whole plan: branch `b0/display-kittens-contract`, model **Sonnet 5.5 at medium effort** (ARCHITECT.md: a plan whose tasks are mostly given in full; the prototype's visual judgement is one task and a screenshot review). Nothing is pushed. The Mac and Windows/Linux B plans are drafted from this plan's "Interface for the app plans" and start once the owner has approved the checkpoint and this branch is merged.

**Before the session starts,** the plan file is committed to `notchmeow/rebrand` (a docs-only commit): the controller does this, with the owner's OK, so the branch the session starts from already holds the plan it runs. **The base is `6c14947` or later:** `git merge-base --is-ancestor 6c14947 HEAD` must succeed.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run `git switch -c b0/display-kittens-contract notchmeow/rebrand`, then `git merge-base --is-ancestor 6c14947 HEAD` and `git ls-files docs/superpowers/plans/2026-10-08-b0-display-kittens-contract.md`: the first must succeed and the second must print the plan's path. If either fails, say so and stop. Read `CLAUDE.md`, `ARCHITECT.md`, `docs/superpowers/plans/2026-10-08-b0-display-kittens-contract.md` and `docs/superpowers/specs/2026-10-08-display-modes-kittens-design.md`. Reply "ready" and stop. Do not start any task.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at medium effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message:

   > Run `docs/superpowers/plans/2026-10-08-b0-display-kittens-contract.md` with `superpowers:subagent-driven-development`, task by task, on this branch. Dispatch each task to the agent the plan's "Tasks and agents" table names, then to `nm-reviewer`; fix what the review finds before the next task. **Stop after Task 7**: report the screenshot folder and file names and what each shows, and wait for the main session's go (the owner approves the look at this checkpoint; their notes may change numbers in the core, which Task 8 then documents). After the go, run Task 8, then dispatch `nm-reviewer-deep` over the whole branch. Commit only as the plan's commit steps say, and never push. Never launch a NotchMeow app. The work installs and downloads nothing (`npx --no-install` only; `playwright-cli` uses the cached browsers). Stop every server and browser you start. When you are done, report: the commits; the output of `node scripts/check-fixtures-additive.mjs 6c14947`; the test count of `bash scripts/test-cat-contract.sh` and the `✓ 14 fixture files match cat-core.js` line; the Windows cat tests' count; and anything you could not settle.

Before any follow-up turn, the main session checks the session is still on its configured model and effort.

## Interface for the app plans

What the Mac and Windows/Linux B plans consume. Names are exact: every one is a member of `CatCore` (the global on a page, `require()` in Node). Each app ports the rules natively and replays the fixtures; the prototype page is the look. `docs/CAT-CONTRACT.md`, "Display modes, agent coats, kittens and small eyes", has the notes for ports (Task 8 writes it).

### 1. Display settings: `cleanDisplaySettings`, next to `cleanCatSettings`

| Name | Signature and meaning |
|---|---|
| `DISPLAY_MODES` | `['one', 'perAgent', 'two']`, in the order Settings lists them. Frozen. |
| `displayModeOf(v)` | A stored mode to one of the three; anything else is `'one'`. |
| `DEFAULT_PAIR` | `['shrimpy', 'momo']`. |
| `DEFAULT_AGENT_CATS` | `{integration_claude: 'shrimpy', agent_codex: 'momo'}`. |
| `MAX_AGENT_CATS` | 256. |
| `PILL_ID`, `isPillId(v)` | The shape of a pill ID: `^[a-z][a-z0-9_-]{1,63}$`, matched against the whole string, and not `constructor` or `prototype`. |
| `isAgentPill(v)` | A pill ID that is `integration_claude` or starts with `agent_` and has more after it. |
| `defaultAgentCat(id)` | The default coat of an agent pill, or `null`. |
| `cleanPair(raw)` | An array or JSON text of two cat IDs to `[catId, catId]`. Anything but two valid IDs, whole, is `['shrimpy', 'momo']`; the same coat twice makes cat 2 the next one in `CAT_IDS` order. |
| `cleanAgentCats(raw)` | A stored map to `{pillId: catId}`: pill IDs that are not pill IDs dropped, unknown pills kept, a bad coat the pill's default or dropped, keys in code-point order, at most 256. |
| `cleanDisplaySettings(raw)` | Anything to `{displayMode, pair, agentCats}`. Never throws. |
| `defaultDisplaySettings()` | `cleanDisplaySettings(null)`: `{displayMode: 'one', pair: ['shrimpy', 'momo'], agentCats: {}}`. |

**The raw shape and where it comes from.**

| macOS (`UserDefaults`) | Raw field |
|---|---|
| `cat.displayMode` | `displayMode` |
| `cat.pair` | `pair`, as JSON text of two cat IDs |
| `cat.agentCat.<pillId>` | `agentCats.<pillId>` (list the keys with that prefix) |

Windows and Linux: the `cat` block of `settings.json` holds `displayMode`, `pair` and `agentCats` beside the Cat settings (camelCase, `pair` an array, `agentCats` an object).

- **Call both functions on the same raw block.** `cleanCatSettings` still returns only `{character, motionStyle, collar, furLines, cats}` and drops the display keys, which is why `settings-cases.json` did not change. **Windows/Linux:** `windows/src-tauri/src/settings.rs` (`sanitized`, line 150) sets `settings.cat = clean_cat_settings(&settings.cat)`, which rebuilds the block from the Cat settings alone: B-tauri must carry the three display keys through (a `clean_display_settings` next to `clean_cat_settings` in `cat_settings.rs`, merged into the block), or the next save drops them. The TypeScript side (`windows/src/cat/settings.ts`) gets the same port.
- **Mac:** `CatSettingsStore` builds the raw value from UserDefaults as plain JSON values, runs a Swift port of `cleanDisplaySettings` next to `CatSettings.clean`, and uses only the result. It writes back the clean values (the pair as JSON text).
- **Main cat.** `cat.character` is unchanged; the Settings row is renamed "Main cat".
- **Settings screens:** Mac `CatSettingsView` and Windows `windows/src/settings/cat.ts` get the Display picker (with the pair pickers and, in A cat for each agent mode, the agents' list); both read and write through the clean values above.

### 2. Giving agents their cats

| Name | Signature and meaning |
|---|---|
| `agentCatFor(pillId, agentCats, mainCat, rand)` | Returns `{cat, agentCats, assigned}`: the stored coat, else the default, else a random coat that no other agent and not the Main cat uses (a default that no stored coat has replaced counts as taken); all 16 taken: the least-used, ties in `CAT_IDS` order. `assigned` true means `agentCats` gained the pill: store it, never change it by itself. A pill that is not an agent pill gets the Main cat and is never stored. |
| `rerollAgentCat(pillId, agentCats, mainCat, rand)` | The dice: `{cat, agentCats}`, never the agent's current coat, always stored. |
| `assignAgentCats(pillIds, agentCats, mainCat, rand)` | `agentCatFor` for each ID in turn; returns the map. "Reset to defaults" is this with `{}`. |
| `pickCat(taken, rand, avoid)` | The pure choice behind the three: `taken` the cat IDs in use (repeats count), `avoid` a coat never chosen. |

- **`rand()` is called once, and only when a coat is chosen at random** (a free one exists). The least-used rule, stored coats, defaults and non-agent pills draw nothing. A non-finite number is 0, and 1 or more is the last free coat. Mac: `Double.random(in: 0..<1)` in the app, a counted seeded source in tests; Windows/Linux: `Math.random`, and the same in tests.
- **When to call it.** Whenever an agent pill is first created (the Mac's `HookServer` when it makes the pill; Windows' `upsertExternalAgent` in `core/state.ts`) and once at load for the pills that exist, before anything is drawn. Store the result when `assigned`.
- **The Settings picker** (`CatSettingsView`, `settings/cat.ts`) writes `cleanAgentCats({...agentCats, [pillId]: catId})`; its dice calls `rerollAgentCat`, and "Reset to defaults" `assignAgentCats(agentPillIds, {}, mainCat, rand)`. The "Cats for your agents" list is one row per agent, most recent first.

### 3. The cast: `castOf`

`castOf(mode, {tasks, focusId, mainCat, pair, agentCats})` returns `{mode, big, second, pills, drop, greeting}`:

| Output | Meaning | Mac call site | Windows/Linux call site |
|---|---|---|---|
| `big` | `{pill, cat}`: the big cat's pill (the focus, or `null`) and coat | `BotCanvasView` of the big cat, compact and expanded | the big-cat canvas of `island/island.ts` |
| `second` | `null`, or in Two cats mode `{pill, cat}`: the busiest other agent (`pill` is `null` with no other agent: idle, no badge) and pair cat 2. Tapping cat 2 focuses `second.pill` | a second cat view beside the first, compact and expanded | the same, in `island/island.ts` |
| `pills` | `[{pill, cat}]`, at most `PILL_ROW` (4): the tasks other than the focus (and in Two cats mode other than `second.pill`), in the app's order | `CompactMiniGrid.others` (`IslandRootView.swift`) and `AgentPillsView.displayTasks` (`IslandViewContent.swift`), which today take `tasks.filter { $0.id != focusId }.prefix(4)` | `State.otherTasks.slice(0, 4)` in `island/island.ts` and `views/views.ts` |
| `drop` | The coat of the drop view and the drag ghost: the big cat's | `UploadCanvasView`, `UploadCatDriver` | `upload/canvas.ts` |
| `greeting` | `{cat, pair, sessions}`: the cat that falls in (the Main cat); `pair`, `null` or the pair that arrives together in Two cats mode; four session cats in the grid's cell order (the cats of `pills`, so the glide ends where the grid begins) | `CatGreeting`, `GreetingCanvasView` | `cat/greeting.ts`, `cat/minibots.ts` |

- **`tasks` is `[{id, state, last}]`** in the app's order. `state` is one of `STATES`; `last` is the time of the pill's last event (ms, any one clock). **Neither app keeps a per-pill last-event time today** (`AppState.lastActivity` and `State.lastActivity` are global): B-mac and B-tauri add one, updated on every hook event the pill gets. It decides the busiest other agent.
- **Coats:** the cast reads stored coats and defaults only. An agent with neither wears the Main cat until `agentCatFor` has given it one (section 2), which the app does when it first sees the agent, before it draws it.
- **Per-agent coats are parameters of the cat views.** `useCharacter`/the per-frame "follow the Main cat" must not overwrite them (spec §5 Risks): each cat view takes its coat from the cast.
- **Kittens' coat:** a kitten is `kittenOf(parent's coat)`, with the parent the cat drawn at that spot: `big.cat`, `second.cat`, or a pill's `cat`.

### 4. Kittens

| Name | Signature and meaning |
|---|---|
| `kittenStep(list, event)` | The one reducer over a pill's kitten list (`[{id, type, session, state, born, last, until}]`); returns a new list. Events below. |
| `kittenOrder(list)` | A kitten waiting on an approval first, then the newest. |
| `kittenView(list, now)` | What to draw at `now` (ms): the order, without the leaving kittens whose time is up. No timer is needed. |
| `kittenSlots(place, kittens)` | `{place, unit, count, shown: [{id, state, x, y, d}], more, moreAt, label}` for one parent in one place; `kittens` is a `kittenView`. Numbers are multiples of a unit: `'D'` the parent's head width from its centre, `'H'` the pill's height from its trailing edge and the middle of its height. |
| `kittenPlaceOf(mode, expanded)` | The place for the big cat (and cat 2): `bigExpanded`, `bigCompact`, `pairExpanded` or `pairCompact`. An agent pill uses `pill`. |
| `KITTEN_PLACES`, `KITTEN_MAX` (8), `KITTEN_LEAVE_MS` (600), `KITTEN_STATES` | The tables and limits, pinned by `kitten-cases.json`. |
| `cleanKittens(list)` | A list made safe (for an app that holds one badly). |

| Hook | Event for `kittenStep` |
|---|---|
| `SubagentStart` (`agent_id`, `agent_type`, `session_id`) | `{type: 'start', id, agentType, session, t}` |
| `PreToolUse`, `PostToolUse` with an `agent_id` | `{type: 'tool', id, tool: tool_name, t}` (no `agent_id`: not a kitten event) |
| `PermissionRequest` with an `agent_id`; its answer | `{type: 'permission', id, t}`; `{type: 'resolved', id, t}` |
| `SubagentStop` | `{type: 'stop', id, t}` |
| the parent's `Stop`, or `SessionEnd` | `{type: 'end', session, t}` (no `session`: every kitten) |
| the cat's 10-minute sleep timer fires | `{type: 'sweep', t}` |

- **Where it runs.** One mutation point per app, the code that already switches on these hook names: Mac `HookServer.processEvent` (`case "SubagentStart"`, `case "SubagentStop"`, and the tool and permission cases); Windows `island/hooks.ts` (`case "SubagentStart"`). The sleep timers are `CatSleep.swift` and `island/sleep.ts`. `t` is the app's own clock in ms (the Mac's `CACurrentMediaTime() * 1000`, the page's `performance.now()`).
- **The lists are state per agent pill,** not per session, and never stored. The pills' kitten counts feed the compact pair's "×N".
- **Draw** each `shown` kitten as a cat of head width `d * unit` at `parent centre + (x, y) * unit` (an agent pill: `trailing edge + x * H`), in `kittenOf(parent coat)`, with the parent's collar (the agent's colour), its own state badge and `leaving` drawn as a happy blink. `moreAt` is the "+N" label, `label` the pair's "×N".

### 5. Small coloured eyes

| Name | Signature and meaning |
|---|---|
| `usesSmallEye(shape, sd)` | True for `pill`, `wide`, `dot`, `tired` and the left eye (`sd` -1) of a `wink`: draw these with `smallEye` at the compact detail level. False for every expression shape: they stay ink. |
| `smallEye(shape, {sd, R, es, open, yaw, pitch, kitten, cat})` | `null` for a shape that stays ink, else `{shape, closed: false, iris: {rx, ry, r}, pupil: {x, y, rx, ry}, light: {x, y, r}, rim}` (for a bright coat also `flat: true`, with `rim: 0`), or for a blink or squint under 0.22, `{shape, closed: true, line: {x0, y0, cx, cy, x1, y1, width}}`. px in the eye's own frame (centre at the origin, y down), inside the renderer's `translate` and `scale(fx, fy)`. `R` is the head radius, `es` the pose's `es`, `open` is `pose.open * (1 - pose.lid)`, `yaw` and `pitch` the pose's, `kitten` the preset's `kitten`, `cat` the coat id: only an exact string in `SMALL_EYE.bright` makes a bright eye. |
| `SMALL_EYE`, `SMALL_EYE_SHAPES` | The numbers (with `bright`: `midnight`, `oreo`, `mocha`, and `brightPupil` 0.12) and the shape list, pinned by `small-eye-cases.json`. |

- **Colours (the renderer's):** for a normal coat the iris is a radial gradient from the preset's `iris[0]` at the centre to `iris[1]` at radius `iris.r` (`irisR` for the right eye when the coat has one); the pupil `Theme.Cat.pupil`; the catchlight white at 0.92; the rim stroked in the preset's `liner` at width `rim` on the iris's edge; the closed line stroked in the preset's `ink` at 0.9 alpha, round caps. The prototype's `smallEyeDraw` is the reference. For a bright coat (the three black ones) the iris is a flat fill of the lighter of the coat's two iris colours by luminance (Midnight #F7D45C, Oreo #DDEB5A, Mocha #F6C44C) instead of the gradient, there is no rim, the catchlight stays, kittens too, and the slit pupil is 0.12 wide.
- **Call sites:** the compact branch of `CatFace.drawEyes` (the `inkEye(... 0.34 * R * s.es, 0.4 * R * s.es ...)` call) and the same branch in `windows/src/cat/renderer.ts` (the `inkEye(c, shape, sd, 0.34 * R * s.es ...)` call). The renderer passes the coat id as `cat`. Every cat drawn at the compact level gets it: the compact notch, pill cats, the 2×2 grid, kittens and the greeting's session cats.

### 6. The fixtures

| File | Keys | Replay |
|---|---|---|
| `display-cases.json` | `ids`, `modes`, `defaultPair`, `defaultAgentCats`, `maxAgentCats`, `pillIdPattern`, `defaults`, `cases` (30 rows `{name, raw, out}`: `cleanDisplaySettings`), `pairs` (40: `cleanPair`), `agentCats` (21: `cleanAgentCats`), `pillIds` (29: `{id, pill, agent, default}`) | `cleanDisplaySettings`, `cleanPair`, `cleanAgentCats`, `isPillId`, `isAgentPill`, `defaultAgentCat` |
| `agent-cat-cases.json` | `ids`, `defaults`, `cases` (34 `{name, pill, agentCats, mainCat, rand, out: {cat, agentCats, assigned}, draws}`), `rerolls` (11, `out: {cat, agentCats}`), `assigns` (6, `pills`, `out: {agentCats}`) | `agentCatFor`, `rerollAgentCat`, `assignAgentCats` with the random source `rand` names: `{seed: n}` is `rng(n)`, `{values: [..]}` those numbers then 0, `{none: true}` must never be called; and check `draws` |
| `cast-cases.json` | `ids`, `modes`, `pillRow`, `states`, `busyRank`, `cases` (136 rows `{name, mode, input, out}`: 44 scenarios, rankings and hostile inputs in each of the 3 modes, and 4 unknown modes) | `castOf`, `busyRank` |
| `kitten-cases.json` | `limits`, `states`, `places`, `scripts` (21: `{name, from, steps: [{ev, list}]}`), `order` (5), `views` (4), `cleans` (5), `slots` (35), `placeOf` (8) | `kittenStep` one event at a time and compare the whole list, `kittenOrder`, `kittenView`, `cleanKittens`, `kittenSlots`, `kittenPlaceOf` |
| `small-eye-cases.json` | `constants`, `shapes`, `uses` (26), `sizes` (56), `squints` (72), `gazes` (72), `scales` (20), `others` (20), `hostile` (19): rows are `{shape, o, out}` | `usesSmallEye`, `smallEye` |

Every file has `version` 1 and `tolerance` 1e-9. **JSON cannot hold `undefined`, NaN or Infinity,** so the fixtures use a missing key or `null` for "not there", and each port adds its own tests for a time that is not finite (a kitten event changes nothing), a `rand` that misbehaves, and NaN in `smallEye`'s inputs (taken as the default).

### 7. The look: what the prototype shows, for the app plans to match

`design/prototype/notchmeow.html` after Task 6: `smallEyeDraw` (the eye), `drawKittens` (kittens, "+N" and "×N"), `drawDesk` (the notch mock, driven by `castOf`: in Two cats mode the compact cats are Ø20 at 30 and 54 px from the island's left edge, the expanded ones Ø58 at (56, 98) and Ø46 at (114, 106), and the ticker gains a second line, "Codex · needs approval", for cat 2), `sessionWho` (the grid's cats), `greetPair` (cat 2 pops in beside the settled cat at the end of the greeting), `drawEyeSheet` (the contact sheet). The page's layout numbers are a reference, not part of the contract.

**Not in B-0:** any app code; the Settings rows and the live preview; the exact choreography of the pair's arrival in the greeting (the page shows one way); the frame-time bench with the new eyes (the app plans re-measure it).

---

### Task 1: Display settings: `cleanDisplaySettings` and `display-cases.json`

**Files:**
- Modify: `design/prototype/cat-core.js` (a new section above the `@@END-OF-CORE` marker), `scripts/gen-cat-fixtures.mjs` (a builder above the `@@BUILDERS` marker), `tests/cat/fixtures.test.mjs` (the file list)
- Create: `tests/cat/display.test.mjs`, `tests/fixtures/cat/display-cases.json` (generated)

**Interfaces:**
- Consumes from the core: `own`, `isPlain`, `CAT_IDS`, `catIdOf`, `cleanCatSettings`, `defaultCatSettings`, `rng`; from the generator: `compare`, `fix`, `format`, `finish`, `FILES`.
- Produces in `CatCore`: `DISPLAY_MODES`, `displayModeOf`, `DEFAULT_PAIR`, `DEFAULT_AGENT_CATS`, `MAX_AGENT_CATS`, `PILL_ID`, `isPillId`, `isAgentPill`, `defaultAgentCat`, `cleanPair`, `cleanAgentCats`, `cleanDisplaySettings`, `defaultDisplaySettings`, exactly as in "Interface for the app plans" section 1; and `display-cases.json`.

- [ ] **Step 1: Write the failing tests**

```bash
cat > tests/cat/display.test.mjs <<'EOF'
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
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test tests/cat/display.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"`
Expected: `# tests 14`, `# pass 0`, `# fail 14`: the core has no `cleanDisplaySettings` yet.

- [ ] **Step 3: Add the section to the core**

This inserts "Display modes: the stored settings" above the `@@END-OF-CORE` marker, after the stored settings. It reuses `isPlain`, `own`, `CAT_IDS` and `catIdOf`; nothing else in the file changes.

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
marker = '// @@END-OF-CORE: every later task inserts its section immediately above this line.'
assert s.count(marker) == 1
new = r'''// ── Display modes: the stored settings (sub-project B) ───────────────────────
// Settings → Cat → Display picks how the cats are shown: one cat everywhere (the default and what shipped), a cat for each agent, or the user's two
// cats side by side. What it saves goes through cleanDisplaySettings, a function of its own: cleanCatSettings and every settings-cases.json
// line stay exactly as they were, and an app cleans the same raw block with both. Raw in, clean out, never a throw.
//   raw or clean:  {displayMode, pair, agentCats: {<pillId>: <catId>}}
//   macOS keys:    cat.displayMode, cat.pair (JSON text of two cat IDs), cat.agentCat.<pillId>   Windows and Linux: the same three fields of the `cat` block.
/** The display modes, in the order Settings lists them. Frozen contract values, like the cat IDs: an unknown stored mode is 'one'. */
const DISPLAY_MODES=['one','perAgent','two'];
const displayModeOf=v=>DISPLAY_MODES.includes(v)?v:'one';
/** Two cats mode's pair before the user picks: Shrimpy and Momo. */
const DEFAULT_PAIR=['shrimpy','momo'];
/** What an agent pill wears before the user picks: Claude Code is Shrimpy and Codex is Momo. Every other agent gets a coat when it is first seen (agentCatFor). */
const DEFAULT_AGENT_CATS={integration_claude:'shrimpy',agent_codex:'momo'};
/** A stored map keeps at most this many pills (the first by code-point order of their IDs), so a hostile file cannot grow it without end. */
const MAX_AGENT_CATS=256;
/** A pill ID: a lowercase letter, then lowercase letters, digits, `_` and `-`, 2 to 64 characters (`agent_` pills are lowercase, digits and hyphens). Names that are prototype members are refused. */
const PILL_ID=/^[a-z][a-z0-9_-]{1,63}$/;
const isPillId=v=>typeof v==='string'&&PILL_ID.test(v)&&v!=='constructor'&&v!=='prototype';
/** Agent pills are Claude Code's pill (integration_claude, despite its prefix) and every agent_* pill. Every other pill is an integration or an AI provider. */
const isAgentPill=v=>isPillId(v)&&(v==='integration_claude'||(v.startsWith('agent_')&&v.length>6));
/** The default coat of an agent pill (Claude Code Shrimpy, Codex Momo), or null for a pill that has none. */
const defaultAgentCat=id=>isPillId(id)&&own(DEFAULT_AGENT_CATS,id)?DEFAULT_AGENT_CATS[id]:null;
const isCatId=v=>typeof v==='string'&&CAT_IDS.includes(v);
/**
 * A stored pair to two cat IDs. It may be an array or the JSON text of one (the Mac stores text). Anything that is not two valid cat IDs, whole,
 * is Shrimpy and Momo. Two of the same coat make cat 2 the next coat in CAT_IDS order (after the last one, the first).
 */
function cleanPair(raw){let v=raw;
 if(typeof v==='string'){try{v=JSON.parse(v)}catch{return[...DEFAULT_PAIR]}}
 if(!Array.isArray(v)||v.length!==2||!v.every(isCatId))return[...DEFAULT_PAIR];
 return v[0]===v[1]?[v[0],CAT_IDS[(CAT_IDS.indexOf(v[1])+1)%CAT_IDS.length]]:[v[0],v[1]]}
/**
 * A stored map from pill ID to cat ID, cleaned. A pill ID that does not have the shape of one is dropped (`__proto__` and `constructor` included); an
 * unknown pill ID is kept, because agents come and go. A bad coat becomes the pill's default when it has one, and is dropped otherwise (agentCatFor
 * gives that agent a coat again). The result has its pills in code-point order, at most MAX_AGENT_CATS of them.
 */
function cleanAgentCats(raw){const out={};if(!isPlain(raw))return out;let n=0;
 for(const id of Object.keys(raw).filter(isPillId).sort()){if(n>=MAX_AGENT_CATS)break;
  const c=raw[id],d=defaultAgentCat(id);if(isCatId(c)){out[id]=c;n++}else if(d){out[id]=d;n++}}
 return out}
/** Everything Display saves, cleaned: {displayMode, pair, agentCats}. Never throws. */
function cleanDisplaySettings(raw){const r=isPlain(raw)?raw:{};return{displayMode:displayModeOf(r.displayMode),pair:cleanPair(r.pair),agentCats:cleanAgentCats(r.agentCats)}}
/** What a fresh install holds: One cat, Shrimpy and Momo, no stored agent coats. */
const defaultDisplaySettings=()=>cleanDisplaySettings(null);
Object.assign(api,{DISPLAY_MODES,displayModeOf,DEFAULT_PAIR,DEFAULT_AGENT_CATS,MAX_AGENT_CATS,PILL_ID,isPillId,isAgentPill,defaultAgentCat,cleanPair,cleanAgentCats,cleanDisplaySettings,defaultDisplaySettings});

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, new + marker))
PY
git diff --stat design/prototype/cat-core.js
```

Expected: `1 file changed, 46 insertions(+)`.

- [ ] **Step 4: Run the tests**

Run: `node --test tests/cat/display.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"`
Expected: `# tests 14`, `# pass 14`, `# fail 0`.

- [ ] **Step 5: Prove the prototype-name guard bites (not committed)**

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "PILL_ID.test(v)&&v!=='constructor'&&v!=='prototype'"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, 'PILL_ID.test(v)'))
PY
node --test tests/cat/display.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = 'PILL_ID.test(v)'
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "PILL_ID.test(v)&&v!=='constructor'&&v!=='prototype'"))
PY
node --test tests/cat/display.test.mjs 2>&1 | grep -E "^# (pass|fail)"
```

Expected: first run `not ok 8 - pill IDs: the shape of one, and no prototype names` and `not ok 10 - the agent coats: hostile maps and keys never throw and never pollute`, `# pass 12`, `# fail 2`; after putting the line back, `# pass 14` and `# fail 0`.

- [ ] **Step 6: Run the whole contract**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓|✗"`
Expected: `# tests 152`, `# pass 152`, `# fail 0`; nine `✓` fixture lines, `✓ 9 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`. (No fixture changed yet: the 138 old tests and the 14 new ones.)

- [ ] **Step 7: Add the replay tests and the fixture to the file list**

```bash
cat >> tests/cat/display.test.mjs <<'EOF'

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
EOF
python3 - <<'PY'
p = 'tests/cat/fixtures.test.mjs'
s = open(p, encoding='utf-8').read()
for was, now in [("'collar-cases.json', 'geometry-cases.json'", "'collar-cases.json', 'display-cases.json', 'geometry-cases.json'"), ('holds exactly the nine contract files', 'holds exactly the contract files')]:
    assert s.count(was) == 1, was
    s = s.replace(was, now)
open(p, 'w', encoding='utf-8').write(s)
PY
node --test tests/cat/display.test.mjs tests/cat/fixtures.test.mjs 2>&1 | grep -E "^(not ok|# (pass|fail))|ENOENT" | head
```

Expected: `not ok` lines for the fixtures tests (the list now has `display-cases.json`, which does not exist yet), `ENOENT` lines that name `display-cases.json`, and `not ok … - tests/cat/display.test.mjs`: the replay part of that file cannot load without the fixture. The 14 self-checks from Step 1 still pass on their own.

- [ ] **Step 8: Add the builder and generate the fixture**

The builder goes above the `@@BUILDERS` marker. Its rows are what a settings file could hold, written as JSON. The 300-pill map is built in the builder and written out in full.

```bash
python3 - <<'PY'
p = 'scripts/gen-cat-fixtures.mjs'
s = open(p, encoding='utf-8').read()
marker = '// @@BUILDERS: each task adds'
assert s.count(marker) == 1
snippet = r'''// ── Display settings (B-0): what Settings → Cat → Display saves, cleaned ──────
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

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, snippet + marker))
PY
node scripts/gen-cat-fixtures.mjs
ls -l tests/fixtures/cat/display-cases.json
```

Expected: `wrote 10 fixture files to tests/fixtures/cat` and a `display-cases.json` of about 38 KB (under the 400 KB the fixtures test allows).

- [ ] **Step 9: Run the tests, then prove the fixture is additive and that no-drift covers it**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|^not ok|✓|✗"`
Expected: `# tests 155`, `# pass 155`, `# fail 0`; ten `✓` fixture lines (`display-cases.json` among them), `✓ 10 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

Run: `node scripts/check-fixtures-additive.mjs 6c14947 | tail -3`
Expected: `  ✓ warp-cases.json: 121 old lines unchanged`, `  + display-cases.json is new` and `✓ fixtures changed only by addition since 6c14947`.

Run: `git diff --stat -- tests/fixtures/cat`
Expected: no output (no existing fixture changed; the new one is untracked).

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "return v[0]===v[1]?[v[0],CAT_IDS[(CAT_IDS.indexOf(v[1])+1)%CAT_IDS.length]]:[v[0],v[1]]}"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "return[v[0],v[1]]}"))
PY
node scripts/gen-cat-fixtures.mjs --check 2>&1 | grep -E "✗|Fixtures drifted"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "return[v[0],v[1]]}"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "return v[0]===v[1]?[v[0],CAT_IDS[(CAT_IDS.indexOf(v[1])+1)%CAT_IDS.length]]:[v[0],v[1]]}"))
PY
node scripts/gen-cat-fixtures.mjs --check | tail -1
```

Expected: first `✗ display-cases.json drifted from cat-core.js (` followed by a number of differences, and `Fixtures drifted. cat-core.js is the tie-breaker…`; after putting the line back, `✓ 10 fixture files match cat-core.js`.

- [ ] **Step 10: Commit**

Run: `git status --short`
Expected: ` M design/prototype/cat-core.js`, ` M scripts/gen-cat-fixtures.mjs`, ` M tests/cat/fixtures.test.mjs`, `?? tests/cat/display.test.mjs`, `?? tests/fixtures/cat/display-cases.json`.

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/fixtures.test.mjs tests/cat/display.test.mjs tests/fixtures/cat/display-cases.json
git commit -m "feat(cat): the Display settings are cleaned by cleanDisplaySettings, in the core

A mode (one, perAgent, two), a pair and the agents' coats, with a clean-up of their own so cleanCatSettings and
settings-cases.json stay as they were. A bad pair is Shrimpy and Momo, an unknown pill is kept, prototype names are
dropped. display-cases.json pins it for both apps; the other nine fixtures are untouched.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Giving agents their cats: `agentCatFor` and `agent-cat-cases.json`

**Files:**
- Modify: `design/prototype/cat-core.js` (a new section above the `@@END-OF-CORE` marker), `scripts/gen-cat-fixtures.mjs` (a builder above the `@@BUILDERS` marker), `tests/cat/fixtures.test.mjs` (the file list)
- Create: `tests/cat/agentcat.test.mjs`, `tests/fixtures/cat/agent-cat-cases.json` (generated)

**Interfaces:**
- Consumes: from the core: `own`, `isPlain`, `CAT_IDS`, `catIdOf`, `rng`, and Task 1's `cleanAgentCats`, `isAgentPill`, `defaultAgentCat`, `DEFAULT_AGENT_CATS`; from the generator: `compare`, `FILES`, `core`.
- Produces in `CatCore`: `pickCat`, `agentCatFor`, `rerollAgentCat`, `assignAgentCats`, exactly as in "Interface for the app plans" section 2; and `agent-cat-cases.json`.

- [ ] **Step 1: Write the failing tests**

```bash
cat > tests/cat/agentcat.test.mjs <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const IDS = core.CAT_IDS;
const deepFreeze = v => { if (v && typeof v === 'object') { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };
/** A seeded rand that counts its calls. */
const counted = seed => { const r = core.rng(seed), f = () => { f.n++; return r(); }; f.n = 0; return f; };
const fixed = v => { const f = () => { f.n++; return v; }; f.n = 0; return f; };
const noRand = () => { throw new Error('rand() must not be called here'); };
/** The rule written out the long way, from the spec, to check agentCatFor against: a free coat at random, else the least-used, ties in CAT_IDS order. */
function reference(taken, rand, avoid = null) {
  const pool = IDS.filter(c => c !== avoid), uses = c => taken.filter(t => t === c).length, free = pool.filter(c => uses(c) === 0);
  if (free.length) return free[Math.floor(rand() * free.length)];
  const least = Math.min(...pool.map(uses));
  return pool.find(c => uses(c) === least);
}
const OTHER = IDS.slice(2); // ginger ... noodle: the 14 coats that are neither Claude Code's nor Codex's default

test('Claude Code is Shrimpy and Codex is Momo, with no random number and nothing to store', () => {
  for (const [pill, cat] of [['integration_claude', 'shrimpy'], ['agent_codex', 'momo']]) {
    const out = core.agentCatFor(pill, {}, 'ginger', noRand);
    assert.deepEqual(out, { cat, agentCats: {}, assigned: false }, pill);
    assert.equal(core.defaultAgentCat(pill), cat);
  }
});

test('a stored coat wins over the default, with no random number and nothing new to store', () => {
  const map = { integration_claude: 'oreo', agent_codex: 'blue', agent_gemini: 'latte' };
  for (const [pill, cat] of [['integration_claude', 'oreo'], ['agent_codex', 'blue'], ['agent_gemini', 'latte']]) assert.deepEqual(core.agentCatFor(pill, map, 'momo', noRand), { cat, agentCats: map, assigned: false }, pill);
});

test('a pill that is not an agent gets the Main cat and is never stored, nor is an ID that is not a pill ID', () => {
  for (const pill of ['integration_stripe', 'integration_music', 'ai_openai', 'agent_', 'agent', 'Agent_x', '__proto__', 'constructor', '', null, undefined, 7, {}, ['agent_x']]) {
    assert.deepEqual(core.agentCatFor(pill, { agent_y: 'momo' }, 'cloud', noRand), { cat: 'cloud', agentCats: { agent_y: 'momo' }, assigned: false }, String(pill));
  }
  assert.equal(core.agentCatFor('integration_stripe', {}, 'tiger', noRand).cat, 'shrimpy', 'a Main cat that is not a cat ID is Shrimpy');
});

test('a new agent gets a coat that no other agent and not the Main cat uses, keeps it, and is not given another one', () => {
  for (let seed = 1; seed <= 200; seed++) {
    const rand = counted(seed), map = { agent_a: 'blue', agent_b: 'ginger' };
    const out = core.agentCatFor('agent_new', map, 'cloud', rand);
    assert.ok(!['shrimpy', 'momo', 'blue', 'ginger', 'cloud'].includes(out.cat), `${seed}: ${out.cat}`);
    assert.equal(out.assigned, true);
    assert.equal(rand.n, 1, 'one random number');
    assert.deepEqual(out.agentCats, { agent_a: 'blue', agent_b: 'ginger', agent_new: out.cat });
    assert.deepEqual(core.agentCatFor('agent_new', out.agentCats, 'cloud', noRand), { cat: out.cat, agentCats: out.agentCats, assigned: false }, 'the second time it only reads');
    assert.deepEqual(map, { agent_a: 'blue', agent_b: 'ginger' }, 'the input is not changed');
  }
});

test('the random choice is repeatable and uses the whole range of free coats: the first free one at 0, the last at just under 1', () => {
  assert.equal(core.agentCatFor('agent_x', {}, 'shrimpy', fixed(0)).cat, 'ginger', 'Shrimpy and Momo are taken by the defaults, so the first free coat is Ginger');
  assert.equal(core.agentCatFor('agent_x', {}, 'shrimpy', fixed(0.9999999)).cat, 'noodle');
  assert.equal(core.agentCatFor('agent_x', {}, 'ginger', fixed(0)).cat, 'midnight', 'the Main cat is taken too');
  assert.equal(core.agentCatFor('agent_x', {}, 'noodle', fixed(0.9999999)).cat, 'puff');
  for (const seed of [1, 7, 13, 2026]) assert.equal(core.agentCatFor('agent_x', {}, 'momo', core.rng(seed)).cat, core.agentCatFor('agent_x', {}, 'momo', core.rng(seed)).cat);
  const seen = new Set();
  for (let seed = 1; seed <= 400; seed++) seen.add(core.agentCatFor('agent_x', {}, 'shrimpy', core.rng(seed)).cat);
  assert.deepEqual([...seen].sort(), [...OTHER].sort(), 'every one of the 14 free coats comes up');
});

test('a default coat that a stored coat has replaced is free again', () => {
  const map = { integration_claude: 'oreo', agent_codex: 'ginger' };
  assert.equal(core.agentCatFor('agent_x', map, 'midnight', fixed(0)).cat, 'shrimpy');
  assert.equal(core.agentCatFor('agent_x', { ...map, agent_y: 'shrimpy' }, 'midnight', fixed(0)).cat, 'momo');
  assert.equal(core.agentCatFor('agent_x', {}, 'midnight', fixed(0)).cat, 'ginger', 'with both defaults in force, they are taken');
});

test('when all 16 coats are taken, the least-used one is chosen, ties in CAT_IDS order, and no random number is drawn', () => {
  const agents = coats => Object.fromEntries(coats.map((c, i) => ['agent_a' + String(i).padStart(2, '0'), c]));
  // Shrimpy and Momo by the defaults, the other 14 by agents (13 of them) and the Main cat (the 14th): every coat once.
  const once = agents(OTHER.slice(0, 13));
  let rand = counted(5);
  assert.deepEqual(core.agentCatFor('agent_new', once, 'noodle', rand), { cat: 'shrimpy', agentCats: { ...once, agent_new: 'shrimpy' }, assigned: true });
  assert.equal(rand.n, 0);
  // Shrimpy is also the Main cat: it is used twice, so the first coat used once is Momo.
  const fourteen = agents(OTHER);
  assert.equal(core.agentCatFor('agent_new', fourteen, 'shrimpy', noRand).cat, 'momo');
  // Every coat but Leo is used at least twice: Leo is the least used.
  const dup = { ...fourteen, ...Object.fromEntries(IDS.filter(c => c !== 'leo').map(c => ['agent_d_' + c, c])) };
  assert.equal(core.agentCatFor('agent_new', dup, 'shrimpy', noRand).cat, 'leo');
  // A coat used once where the rest are used twice or more wins whatever its place.
  assert.equal(core.agentCatFor('agent_new', { ...dup, agent_leo2: 'leo' }, 'shrimpy', noRand).cat, 'momo', 'Leo is now used twice, Momo (default and the duplicate) too, but Momo comes first');
});

test('agentCatFor agrees with the rule written the long way, over 2000 random states', () => {
  const r = core.rng(99);
  for (let i = 0; i < 2000; i++) {
    const n = Math.floor(r() * 24), map = {}, pick = () => IDS[Math.floor(r() * 16)];
    for (let k = 0; k < n; k++) map['agent_s' + String(k).padStart(2, '0')] = pick();
    if (r() < .3) map.integration_claude = pick();
    if (r() < .3) map.agent_codex = pick();
    const main = pick(), seed = Math.floor(r() * 1e6), eff = { integration_claude: 'shrimpy', agent_codex: 'momo', ...map };
    const want = reference([...Object.values(eff), main], core.rng(seed)), got = core.agentCatFor('agent_new', map, main, core.rng(seed));
    assert.equal(got.cat, want, JSON.stringify({ map, main, seed }));
  }
});

test('a random source that misbehaves never breaks it: 0 for no function, NaN, a number out of range or text', () => {
  for (const rand of [undefined, null, 'x', 7, () => NaN, () => Infinity, () => -3, () => 2, () => '0.5', () => undefined, () => 1]) {
    const out = core.agentCatFor('agent_x', {}, 'shrimpy', rand);
    assert.ok(OTHER.includes(out.cat), String(rand));
  }
  assert.equal(core.agentCatFor('agent_x', {}, 'shrimpy', () => 1).cat, 'noodle', '1 is held to the last free coat');
  assert.equal(core.agentCatFor('agent_x', {}, 'shrimpy', () => -3).cat, 'ginger');
});

test('hostile maps and Main cats never throw: a map that is not an object, a Main cat that is not a cat', () => {
  for (const map of [null, undefined, 'x', 7, [], ['momo'], { __proto__: null }, JSON.parse('{"__proto__":"momo","constructor":"momo","agent_ok":"tiger"}')]) {
    const out = core.agentCatFor('agent_x', map, undefined, fixed(0));
    assert.ok(IDS.includes(out.cat) && out.assigned === true);
    assert.deepEqual(Object.keys(out.agentCats), ['agent_x']);
  }
  assert.doesNotThrow(() => core.agentCatFor('agent_x', deepFreeze({ agent_y: 'momo' }), 'momo', fixed(0)));
  assert.equal({}.agent_x, undefined);
});

test('the dice: a new random coat, never the current one, always stored, and the rest of the rule is the same', () => {
  for (let seed = 1; seed <= 200; seed++) {
    const rand = counted(seed), map = { agent_a: 'blue', agent_b: 'snow' }, out = core.rerollAgentCat('agent_a', map, 'cloud', rand);
    assert.ok(out.cat !== 'blue' && !['shrimpy', 'momo', 'snow', 'cloud'].includes(out.cat), `${seed}: ${out.cat}`);
    assert.deepEqual(out.agentCats, { agent_a: out.cat, agent_b: 'snow' });
    assert.equal(rand.n, 1);
  }
  const claude = core.rerollAgentCat('integration_claude', {}, 'cloud', fixed(0));
  assert.deepEqual(claude, { cat: 'ginger', agentCats: { integration_claude: 'ginger' } }, 'Claude Code: not Shrimpy again, and Momo (Codex) and Cloud (Main) are taken');
  assert.equal(core.rerollAgentCat('agent_new', {}, 'cloud', fixed(0)).cat, 'ginger', 'an agent with no coat yet: the same as agentCatFor');
  assert.deepEqual(core.rerollAgentCat('integration_stripe', { agent_y: 'momo' }, 'cloud', noRand), { cat: 'cloud', agentCats: { agent_y: 'momo' } });
  // All 16 taken: the least-used coat that is not the current one.
  const once = Object.fromEntries(OTHER.slice(0, 13).map((c, i) => ['agent_a' + String(i).padStart(2, '0'), c]));
  assert.equal(core.rerollAgentCat('agent_a00', once, 'noodle', noRand).cat, 'shrimpy', 'Ginger (its own) is set aside; every other coat is used once; the first is Shrimpy');
  assert.equal(core.rerollAgentCat('integration_claude', once, 'noodle', noRand).cat, 'momo', 'Claude Code is Shrimpy: set aside, and Momo is the first of the rest');
});

test('assignAgentCats gives every agent in the list a coat, in order, and skips integrations and repeats', () => {
  const pills = ['agent_codex', 'agent_gemini', 'integration_stripe', 'agent_cursor', 'agent_gemini', 'integration_claude', 'ai_openai', 'Bad Id', 'agent_gemini'];
  const out = core.assignAgentCats(pills, {}, 'cloud', core.rng(3));
  assert.deepEqual(Object.keys(out), ['agent_cursor', 'agent_gemini'], 'the defaults are not stored, integrations and bad IDs are skipped');
  const [a, b] = [out.agent_gemini, out.agent_cursor];
  assert.ok(a !== b && ![a, b].some(c => ['shrimpy', 'momo', 'cloud'].includes(c)));
  assert.deepEqual(core.assignAgentCats(pills, {}, 'cloud', core.rng(3)), out, 'repeatable');
  assert.deepEqual(core.assignAgentCats(pills, out, 'cloud', noRand), out, 'a second pass changes nothing and draws nothing');
  assert.deepEqual(core.assignAgentCats(null, { agent_x: 'momo' }, 'cloud', noRand), { agent_x: 'momo' });
  const many = Array.from({ length: 20 }, (_, i) => 'agent_m' + String(i).padStart(2, '0')), all = core.assignAgentCats(many, {}, 'shrimpy', core.rng(8));
  assert.equal(Object.keys(all).length, 20);
  const uses = c => Object.values(all).filter(x => x === c).length + (c === 'shrimpy' ? 2 : 0) + (c === 'momo' ? 1 : 0);
  assert.ok(Math.max(...IDS.map(uses)) - Math.min(...IDS.map(uses)) <= 1, 'after the free coats are gone the least-used are chosen, so the coats stay evenly used');
});

test('"Reset to defaults" is assignAgentCats with an empty map: the defaults are back, the others are chosen again', () => {
  const before = { integration_claude: 'oreo', agent_codex: 'blue', agent_gemini: 'latte' };
  const after = core.assignAgentCats(['integration_claude', 'agent_codex', 'agent_gemini'], {}, 'shrimpy', core.rng(4));
  assert.deepEqual(Object.keys(after), ['agent_gemini']);
  assert.ok(!['shrimpy', 'momo'].includes(after.agent_gemini));
  assert.notDeepEqual(after, before);
});

test('hostile values never throw: 3000 random calls give a valid coat and a clean map', () => {
  const r = core.rng(31337), pool = ['agent_a', 'agent_b', 'agent_codex', 'integration_claude', 'integration_stripe', 'ai_openai', 'Bad', '__proto__', 'constructor', '', null, 7, 'agent_', 'agent_x'];
  for (let i = 0; i < 3000; i++) {
    const map = Object.fromEntries(Array.from({ length: Math.floor(r() * 8) }, () => [pool[Math.floor(r() * pool.length)], r() < .7 ? IDS[Math.floor(r() * 16)] : pool[Math.floor(r() * pool.length)]]).filter(([k]) => typeof k === 'string'));
    const pill = pool[Math.floor(r() * pool.length)], main = r() < .8 ? IDS[Math.floor(r() * 16)] : pool[Math.floor(r() * pool.length)];
    for (const fn of [core.agentCatFor, core.rerollAgentCat]) {
      const out = fn(pill, map, main, core.rng(i));
      assert.ok(IDS.includes(out.cat), JSON.stringify({ pill, map, main }));
      assert.deepEqual(core.cleanAgentCats(out.agentCats), out.agentCats);
    }
    assert.deepEqual(core.cleanAgentCats(core.assignAgentCats([pill, 'agent_x', pill], map, main, core.rng(i))), core.assignAgentCats([pill, 'agent_x', pill], map, main, core.rng(i)));
  }
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test tests/cat/agentcat.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"`
Expected: `# tests 14`, `# pass 0`, `# fail 14`: the core has no `agentCatFor` yet.

- [ ] **Step 3: Add the section to the core**

This inserts "Display modes: giving agents their cats" above the `@@END-OF-CORE` marker, after Task 1's section. It reuses Task 1's pill and coat rules; nothing else in the file changes.

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
marker = '// @@END-OF-CORE: every later task inserts its section immediately above this line.'
assert s.count(marker) == 1
new = r'''// ── Display modes: giving agents their cats ──────────────────────────────────
/**
 * One coat for a new agent. `taken` lists the cat IDs already in use (a coat used twice is listed twice), `rand` returns 0 up to, not including, 1,
 * and `avoid` is a coat that is never chosen. A coat nobody uses is chosen at random (rand() is called once, and only then); when every coat is in use,
 * the least-used one is chosen, ties broken in CAT_IDS order (rand() is not called).
 */
function pickCat(taken,rand,avoid){const use={};for(const c of taken)use[c]=(use[c]||0)+1;
 const pool=CAT_IDS.filter(c=>c!==avoid),free=pool.filter(c=>!use[c]);
 if(free.length){const r=typeof rand==='function'?rand():0;return free[Math.min(free.length-1,Math.max(0,Math.floor(Number.isFinite(r)?r*free.length:0)))]}
 let best=pool[0];for(const c of pool)if((use[c]||0)<(use[best]||0))best=c;return best}
/**
 * The cat of an agent pill: its stored coat, else its default (Claude Code Shrimpy, Codex Momo), else a coat chosen now: random, from those used neither by
 * another agent (a stored one, or a default that no stored coat has replaced) nor as the Main cat; when all 16 are taken, the least-used (see pickCat).
 * Returns {cat, agentCats, assigned}: `agentCats` is the cleaned map, with the new pill added when `assigned` is true, which is the app's cue to store
 * it. A pill that is not an agent pill (an integration, or an ID that is not a pill ID) gets the Main cat and is never stored.
 */
function agentCatFor(pillId,agentCats,mainCat,rand){const map=cleanAgentCats(agentCats),main=catIdOf(mainCat);
 if(!isAgentPill(pillId))return{cat:main,agentCats:map,assigned:false};
 if(own(map,pillId))return{cat:map[pillId],agentCats:map,assigned:false};
 const d=defaultAgentCat(pillId);if(d)return{cat:d,agentCats:map,assigned:false};
 const cat=pickCat([...Object.values({...DEFAULT_AGENT_CATS,...map}),main],rand,null),next=cleanAgentCats({...map,[pillId]:cat});
 return{cat,agentCats:next,assigned:own(next,pillId)}}
/**
 * The dice button: a new random coat for one agent. Its current coat (stored or default) is never chosen again, and the rest is agentCatFor's rule, with
 * this agent's own coat set aside. Always stored, a default agent included. Returns {cat, agentCats}.
 */
function rerollAgentCat(pillId,agentCats,mainCat,rand){const map=cleanAgentCats(agentCats),main=catIdOf(mainCat);
 if(!isAgentPill(pillId))return{cat:main,agentCats:map};
 const eff={...DEFAULT_AGENT_CATS,...map},cur=eff[pillId]||null;delete eff[pillId];
 const cat=pickCat([...Object.values(eff),main],rand,cur);
 return{cat,agentCats:cleanAgentCats({...map,[pillId]:cat})}}
/** agentCatFor for each pill in turn (integrations are skipped): the map after every agent has a coat. "Reset to defaults" is this with an empty map. */
function assignAgentCats(pillIds,agentCats,mainCat,rand){let map=cleanAgentCats(agentCats);
 for(const id of Array.isArray(pillIds)?pillIds:[])map=agentCatFor(id,map,mainCat,rand).agentCats;return map}
Object.assign(api,{pickCat,agentCatFor,rerollAgentCat,assignAgentCats});

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, new + marker))
PY
git diff --stat design/prototype/cat-core.js
```

Expected: `1 file changed, 82 insertions(+)`.

- [ ] **Step 4: Run the tests**

Run: `node --test tests/cat/agentcat.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"`
Expected: `# tests 14`, `# pass 14`, `# fail 0`.

- [ ] **Step 5: Prove the tie rule bites: the least-used coat, ties in `CAT_IDS` order (not committed)**

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "let best=pool[0];for(const c of pool)if((use[c]||0)<(use[best]||0))best=c;return best}"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "let best=pool[0];for(const c of pool)if((use[c]||0)<=(use[best]||0))best=c;return best}"))
PY
node --test tests/cat/agentcat.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "let best=pool[0];for(const c of pool)if((use[c]||0)<=(use[best]||0))best=c;return best}"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "let best=pool[0];for(const c of pool)if((use[c]||0)<(use[best]||0))best=c;return best}"))
PY
node --test tests/cat/agentcat.test.mjs 2>&1 | grep -E "^# (pass|fail)"
```

Expected: `not ok 7 - when all 16 coats are taken…`, `not ok 8 - agentCatFor agrees with the rule written the long way…` and `not ok 11 - the dice…`, `# pass 11`, `# fail 3`; after putting the line back, `# pass 14` and `# fail 0`.

- [ ] **Step 6: Run the whole contract**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓|✗"`
Expected: `# tests 169`, `# pass 169`, `# fail 0`; 10 `✓` fixture lines, `✓ 10 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`. (No fixture changed yet: the 155 earlier tests and the 14 new ones.)

- [ ] **Step 7: Add the replay tests and the fixture to the file list**

```bash
cat >> tests/cat/agentcat.test.mjs <<'EOF'

const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/agent-cat-cases.json', import.meta.url), 'utf8'));
const roundTrip = v => JSON.parse(JSON.stringify(v));
/** The random source of a row: {seed} is rng(seed), {values} those numbers in order and then 0, {none} must never be called. */
const source = spec => {
  const seeded = spec.seed !== undefined ? core.rng(spec.seed) : null;
  const f = () => { f.draws++; if (seeded) return seeded(); if (spec.values) return f.draws <= spec.values.length ? spec.values[f.draws - 1] : 0; throw new Error('rand() must not be called'); };
  f.draws = 0;
  return f;
};

test('agent-cat-cases.json: the cat IDs and the default coats are the core\'s', () => {
  assert.deepEqual(fx.ids, IDS);
  assert.deepEqual(fx.defaults, core.DEFAULT_AGENT_CATS);
});

test('agent-cat-cases.json: every case replays from its own input, with the same number of random draws', () => {
  for (const c of fx.cases) { const r = source(c.rand); assert.deepEqual(compare(roundTrip(core.agentCatFor(c.pill, c.agentCats, c.mainCat, r)), c.out), [], c.name); assert.equal(r.draws, c.draws, c.name); }
  for (const c of fx.rerolls) { const r = source(c.rand); assert.deepEqual(compare(roundTrip(core.rerollAgentCat(c.pill, c.agentCats, c.mainCat, r)), c.out), [], c.name); assert.equal(r.draws, c.draws, c.name); }
  for (const c of fx.assigns) { const r = source(c.rand); assert.deepEqual(compare(roundTrip({ agentCats: core.assignAgentCats(c.pills, c.agentCats, c.mainCat, r) }), c.out), [], c.name); assert.equal(r.draws, c.draws, c.name); }
});

test('agent-cat-cases.json: the inputs the spec worries about are in it (the defaults, the 16-taken tie rule, a stored coat, hostile maps and pills)', () => {
  const names = fx.cases.map(c => c.name);
  for (const n of ['Claude Code is Shrimpy', 'Codex is Momo', 'a stored coat wins over the default', 'an integration gets the Main cat', 'a prototype name gets the Main cat', 'all 16 taken once: the first, Shrimpy', 'all 16 taken, Leo least used', 'a map that is not an object', 'a map with prototype names']) assert.ok(names.includes(n), n);
  assert.ok(fx.cases.filter(c => c.rand.seed !== undefined).length >= 5, 'seeded cases');
  assert.ok(fx.cases.filter(c => c.draws === 0).length >= 15 && fx.cases.filter(c => c.draws === 1).length >= 10, 'rows with and without a draw');
  assert.equal(fx.cases.find(c => c.name === 'all 16 taken, Leo least used').out.cat, 'leo');
  assert.ok(fx.rerolls.every(r => r.out.cat !== (r.agentCats[r.pill] || core.defaultAgentCat(r.pill)) || !core.isAgentPill(r.pill)), 'the dice never gives the same coat back');
});
EOF
python3 - <<'PY'
p = 'tests/cat/fixtures.test.mjs'
s = open(p, encoding='utf-8').read()
was, now = "const FILES = ['collar-cases.json'", "const FILES = ['agent-cat-cases.json', 'collar-cases.json'"
assert s.count(was) == 1, was
open(p, 'w', encoding='utf-8').write(s.replace(was, now))
PY
node --test tests/cat/agentcat.test.mjs tests/cat/fixtures.test.mjs 2>&1 | grep -E "^(not ok|# (pass|fail))|ENOENT" | head
```

Expected: `not ok` lines for the fixtures tests (the list now has `agent-cat-cases.json`, which does not exist yet), `ENOENT` lines that name `agent-cat-cases.json`, and `not ok … - tests/cat/agentcat.test.mjs`: the replay part of that file cannot load without the fixture. The 14 self-checks from Step 1 still pass on their own.

- [ ] **Step 8: Add the builder and generate the fixture**

The builder goes above the `@@BUILDERS` marker, after Task 1's. It exports `randFor`, the random source of a row (the replay test writes its own). The rows are the cases the spec worries about: the defaults, the 16-taken tie rule, a stored coat, hostile maps and pills, and seeded random picks.

```bash
python3 - <<'PY'
p = 'scripts/gen-cat-fixtures.mjs'
s = open(p, encoding='utf-8').read()
marker = '// @@BUILDERS: each task adds'
assert s.count(marker) == 1
snippet = r'''// ── Agent cats (B-0): giving each agent its coat ──────────────────────────────
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

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, snippet + marker))
PY
node scripts/gen-cat-fixtures.mjs
ls -l tests/fixtures/cat/agent-cat-cases.json
```

Expected: `wrote 11 fixture files to tests/fixtures/cat` and a `agent-cat-cases.json` of about 17 KB (under the 400 KB the fixtures test allows).

- [ ] **Step 9: Run the tests, then prove the fixture is additive and that no-drift covers it**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|^not ok|✓|✗"`
Expected: `# tests 172`, `# pass 172`, `# fail 0`; 11 `✓` fixture lines (`agent-cat-cases.json` among them), `✓ 11 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

Run: `node scripts/check-fixtures-additive.mjs 6c14947 | tail -4`
Expected: `  + agent-cat-cases.json is new`, `  + display-cases.json is new` and `✓ fixtures changed only by addition since 6c14947`.

Run: `git diff --stat -- tests/fixtures/cat`
Expected: no output (no existing fixture changed; the new ones are untracked).

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "let best=pool[0];for(const c of pool)if((use[c]||0)<(use[best]||0))best=c;return best}"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "let best=pool[0];for(const c of pool)if((use[c]||0)<=(use[best]||0))best=c;return best}"))
PY
node scripts/gen-cat-fixtures.mjs --check 2>&1 | grep -E "✗|Fixtures drifted"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "let best=pool[0];for(const c of pool)if((use[c]||0)<=(use[best]||0))best=c;return best}"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "let best=pool[0];for(const c of pool)if((use[c]||0)<(use[best]||0))best=c;return best}"))
PY
node scripts/gen-cat-fixtures.mjs --check | tail -1
```

Expected: first `✗ agent-cat-cases.json drifted from cat-core.js (` followed by a number of differences, and `Fixtures drifted. cat-core.js is the tie-breaker…`; after putting the line back, `✓ 11 fixture files match cat-core.js`.

- [ ] **Step 10: Commit**

Run: `git status --short`
Expected: ` M design/prototype/cat-core.js`, ` M scripts/gen-cat-fixtures.mjs`, ` M tests/cat/fixtures.test.mjs`, `?? tests/cat/agentcat.test.mjs`, `?? tests/fixtures/cat/agent-cat-cases.json`.

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/fixtures.test.mjs tests/cat/agentcat.test.mjs tests/fixtures/cat/agent-cat-cases.json
git commit -m "feat(cat): agents get their cats by agentCatFor, in the core

Claude Code is Shrimpy and Codex is Momo; any other agent gets a random coat that no other agent and not the Main cat uses, and keeps it.
All 16 taken: the least-used, ties in CAT_IDS order. The random source is injected. agent-cat-cases.json pins it, with the number of draws.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 3: The cast of each mode: `castOf` and `cast-cases.json`

**Files:**
- Modify: `design/prototype/cat-core.js` (a new section above the `@@END-OF-CORE` marker), `scripts/gen-cat-fixtures.mjs` (a builder above the `@@BUILDERS` marker), `tests/cat/fixtures.test.mjs` (the file list)
- Create: `tests/cat/cast.test.mjs`, `tests/fixtures/cat/cast-cases.json` (generated)

**Interfaces:**
- Consumes: from the core: `own`, `isPlain`, `STATES`, `BUSY`, `catIdOf`, `rng`, and Tasks 1 and 2's `displayModeOf`, `cleanPair`, `cleanAgentCats`, `isPillId`, `isAgentPill`, `defaultAgentCat`; from the generator: `compare`, `FILES`, `core`.
- Produces in `CatCore`: `PILL_ROW`, `busyRank`, `castOf`, exactly as in "Interface for the app plans" section 3; and `cast-cases.json`.

- [ ] **Step 1: Write the failing tests**

```bash
cat > tests/cat/cast.test.mjs <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const IDS = core.CAT_IDS;
const cast = core.castOf;
const T = (id, state = 'idle', last = 0) => ({ id, state, last });
const deepFreeze = v => { if (v && typeof v === 'object') { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };
/** The island as the apps order it: Claude Code, then the agents, then the integrations. */
const ISLAND = [T('integration_claude', 'working', 100), T('agent_codex', 'approval', 90), T('agent_gemini', 'thinking', 80), T('agent_antigravity', 'idle', 10), T('integration_stripe', 'idle', 5), T('integration_music', 'idle', 1)];
const IN = (o = {}) => ({ tasks: ISLAND, focusId: 'integration_claude', mainCat: 'ginger', pair: ['latte', 'cloud'], agentCats: { agent_gemini: 'oreo', agent_antigravity: 'leo' }, ...o });
const catsOf = c => c.pills.map(p => `${p.pill}:${p.cat}`);

test('the cast has the same shape in every mode', () => {
  for (const mode of core.DISPLAY_MODES) {
    const c = cast(mode, IN());
    assert.deepEqual(Object.keys(c), ['mode', 'big', 'second', 'pills', 'drop', 'greeting']);
    assert.equal(c.mode, mode);
    assert.deepEqual(Object.keys(c.big), ['pill', 'cat']);
    assert.deepEqual(Object.keys(c.greeting), ['cat', 'pair', 'sessions']);
    assert.equal(c.greeting.sessions.length, 4);
  }
  assert.equal(core.PILL_ROW, 4);
});

test('One cat: the Main cat in every place, nothing in the second spot, the pills as today', () => {
  const c = cast('one', IN());
  assert.deepEqual(c.big, { pill: 'integration_claude', cat: 'ginger' });
  assert.equal(c.second, null);
  assert.deepEqual(catsOf(c), ['agent_codex:ginger', 'agent_gemini:ginger', 'agent_antigravity:ginger', 'integration_stripe:ginger'], 'the tasks other than the focus, the first four, in the app\'s order');
  assert.equal(c.drop, 'ginger');
  assert.deepEqual(c.greeting, { cat: 'ginger', pair: null, sessions: ['ginger', 'ginger', 'ginger', 'ginger'] });
  assert.deepEqual(cast('one', IN({ focusId: 'agent_gemini' })).big, { pill: 'agent_gemini', cat: 'ginger' }, 'whoever is focused, it is the Main cat');
});

test('A cat for each agent: the focused agent\'s own cat, every agent pill in its own, integrations and the empty focus in the Main cat', () => {
  const c = cast('perAgent', IN({ focusId: 'agent_gemini' }));
  assert.deepEqual(c.big, { pill: 'agent_gemini', cat: 'oreo' });
  assert.equal(c.second, null);
  assert.deepEqual(catsOf(c), ['integration_claude:shrimpy', 'agent_codex:momo', 'agent_antigravity:leo', 'integration_stripe:ginger'], 'Claude Code and Codex by default, a stored coat for the rest, the Main cat for Stripe');
  assert.equal(c.drop, 'oreo');
  assert.deepEqual(c.greeting, { cat: 'ginger', pair: null, sessions: ['shrimpy', 'momo', 'leo', 'ginger'] });
  assert.deepEqual(cast('perAgent', IN()).big, { pill: 'integration_claude', cat: 'shrimpy' });
  assert.deepEqual(cast('perAgent', IN({ focusId: 'integration_stripe' })).big, { pill: 'integration_stripe', cat: 'ginger' }, 'an integration in focus: the Main cat');
  assert.deepEqual(cast('perAgent', IN({ focusId: null })).big, { pill: null, cat: 'ginger' }, 'nothing in focus: the Main cat');
  assert.equal(cast('perAgent', IN({ focusId: 'agent_codex', agentCats: { agent_codex: 'blue' } })).big.cat, 'blue', 'a stored coat beats the default');
  assert.equal(cast('perAgent', IN({ focusId: 'agent_unseen' })).big.cat, 'ginger', 'an agent with no coat yet wears the Main cat until it is given one');
});

test('Two cats: the pair, with the focused pill on cat 1 and the busiest other agent on cat 2, who leaves the row', () => {
  const c = cast('two', IN());
  assert.deepEqual(c.big, { pill: 'integration_claude', cat: 'latte' });
  assert.deepEqual(c.second, { pill: 'agent_codex', cat: 'cloud' }, 'Codex waits for approval');
  assert.deepEqual(catsOf(c), ['agent_gemini:ginger', 'agent_antigravity:ginger', 'integration_stripe:ginger', 'integration_music:ginger'], 'Codex has left the row; every pill wears the Main cat');
  assert.equal(c.drop, 'latte');
  assert.deepEqual(c.greeting, { cat: 'ginger', pair: ['latte', 'cloud'], sessions: ['ginger', 'ginger', 'ginger', 'ginger'] });
  assert.deepEqual(cast('two', IN({ focusId: 'integration_stripe' })).big, { pill: 'integration_stripe', cat: 'latte' }, 'cat 1 shows whatever is focused');
  assert.deepEqual(cast('two', IN({ focusId: null })).big, { pill: null, cat: 'latte' });
  assert.equal(cast('two', IN({ pair: ['momo', 'momo'] })).second.cat, 'ginger', 'the same coat twice: cat 2 is the next one');
  assert.deepEqual(cast('two', IN({ pair: 'junk' })).big.cat, 'shrimpy', 'a bad pair is Shrimpy and Momo');
});

test('the busiest other agent: waiting for you, then an error, then busy, then the most recent event; the focused pill and integrations never count', () => {
  const pick = (tasks, focusId = 'integration_claude') => cast('two', { tasks, focusId }).second.pill;
  const C = T('integration_claude', 'idle', 0);
  assert.equal(pick([C, T('agent_a', 'working', 50), T('agent_b', 'approval', 1)]), 'agent_b', 'a waiting approval beats a busy agent, however old');
  assert.equal(pick([C, T('agent_a', 'error', 50), T('agent_b', 'approval', 1)]), 'agent_b', 'approval beats error');
  assert.equal(pick([C, T('agent_a', 'question', 5), T('agent_b', 'approval', 1)]), 'agent_a', 'a question and an approval are the same rank: the most recent');
  assert.equal(pick([C, T('agent_a', 'working', 50), T('agent_b', 'error', 1)]), 'agent_b', 'error beats busy');
  assert.equal(pick([C, T('agent_a', 'idle', 90), T('agent_b', 'working', 1)]), 'agent_b', 'busy beats idle, however recent');
  assert.equal(pick([C, T('agent_a', 'thinking', 5), T('agent_b', 'searching', 9), T('agent_c', 'working', 7)]), 'agent_b', 'working, thinking and searching are one rank: the most recent');
  assert.equal(pick([C, T('agent_a', 'finished', 5), T('agent_b', 'idle', 9), T('agent_c', 'sleeping', 7)]), 'agent_b', 'the rest by the most recent event');
  assert.equal(pick([C, T('agent_a', 'working', 5), T('agent_b', 'working', 5)]), 'agent_a', 'a tie goes to the first in the app\'s order');
  assert.equal(pick([C, T('agent_a', 'ratelimit', 5), T('agent_b', 'dizzy', 5)]), 'agent_a');
  assert.equal(pick([C, T('integration_stripe', 'approval', 99), T('agent_a', 'idle', 0)]), 'agent_a', 'an integration is never the second cat');
  assert.equal(pick([T('integration_claude', 'working', 1), T('agent_a', 'idle', 0)], 'agent_a'), 'integration_claude', 'Claude Code is an agent, so it can be the second cat when another agent is focused');
  assert.equal(pick([T('agent_a', 'approval', 99), T('integration_stripe', 'error', 5)], 'agent_a'), null, 'the focused agent is never its own second cat, and an integration is not an agent');
  assert.equal(pick([C, T('agent_a', 'bogus', 99), T('agent_b', 'idle', 1)]), 'agent_a', 'an unknown state is idle, and 99 is the most recent');
  assert.equal(pick([C, { id: 'agent_a', state: 'idle' }, T('agent_b', 'idle', 1)]), 'agent_b', 'a missing time is 0');
  assert.equal(pick([C, T('agent_a', 'idle', 5)]), 'agent_a', 'an idle agent, when it is the only one, is shown idle: it is not skipped');
});

test('with no other agent, cat 2 idles with no pill; Claude Code alone is the focused agent', () => {
  assert.deepEqual(cast('two', { tasks: [T('integration_claude', 'working')], focusId: 'integration_claude' }).second, { pill: null, cat: 'momo' });
  assert.deepEqual(cast('two', { tasks: [T('integration_stripe', 'approval'), T('ai_openai', 'error')], focusId: null }).second, { pill: null, cat: 'momo' });
  assert.deepEqual(cast('two', { tasks: [], focusId: null }).second, { pill: null, cat: 'momo' });
});

test('the row and the grid: the first four tasks other than the focus (and in Two cats mode the second cat), in order, each once', () => {
  const many = [T('integration_claude'), ...Array.from({ length: 8 }, (_, i) => T('agent_s' + i)), T('integration_stripe')];
  assert.deepEqual(cast('one', { tasks: many, focusId: 'agent_s2' }).pills.map(p => p.pill), ['integration_claude', 'agent_s0', 'agent_s1', 'agent_s3']);
  assert.deepEqual(cast('two', { tasks: many, focusId: 'integration_claude' }).pills.map(p => p.pill), ['agent_s1', 'agent_s2', 'agent_s3', 'agent_s4'], 'agent_s0 is the second cat (all idle, same time: the first)');
  assert.equal(cast('one', { tasks: many, focusId: 'integration_claude' }).pills.length, 4);
  assert.deepEqual(cast('one', { tasks: [T('agent_a'), T('agent_a'), T('agent_b')], focusId: null }).pills.map(p => p.pill), ['agent_a', 'agent_b'], 'a pill listed twice counts once');
  assert.deepEqual(cast('one', { tasks: [T('agent_a')], focusId: 'agent_a' }).pills, [], 'the focused pill is not in the row');
  assert.deepEqual(cast('one', { tasks: [T('agent_a')], focusId: 'agent_not_listed' }).pills.map(p => p.pill), ['agent_a'], 'a focus that is not in the list takes nothing from it');
});

test('the greeting: the Main cat falls in, the pair comes with it in Two cats mode, and the four session cats are the row\'s cats in the grid\'s cell order', () => {
  assert.deepEqual(cast('perAgent', IN({ focusId: 'integration_claude' })).greeting.sessions, ['momo', 'oreo', 'leo', 'ginger'], 'Codex, Gemini CLI, Antigravity, Stripe: what the grid shows after the hand-over');
  const two = cast('perAgent', { tasks: [T('integration_claude'), T('agent_codex')], focusId: 'integration_claude', mainCat: 'blue' });
  assert.deepEqual(two.greeting.sessions, ['momo', 'blue', 'blue', 'blue'], 'a cell with no pill is the Main cat');
  assert.equal(cast('two', IN({ mainCat: 'blue' })).greeting.cat, 'blue');
  assert.equal(cast('one', IN()).greeting.pair, null);
});

test('hostile input never throws: no tasks, tasks that are not tasks, bad IDs and states, a mode or a pair or a map that is not valid', () => {
  assert.deepEqual(cast('bogus', IN()), cast('one', IN()), 'an unknown mode is One cat');
  for (const mode of [undefined, null, 7, {}, 'Two', 'perAgent ']) assert.equal(cast(mode, IN()).mode, 'one', String(mode));
  for (const input of [undefined, null, 7, 'x', [], {}, { tasks: 'x' }, { tasks: null }, { tasks: [null, 7, 'x', [], {}, { id: 7 }, { id: '__proto__' }, { id: 'Bad Id' }, { id: 'constructor' }] }]) {
    for (const mode of core.DISPLAY_MODES) {
      const c = cast(mode, input);
      assert.equal(c.pills.length, 0);
      assert.equal(c.big.pill, null);
      assert.ok(IDS.includes(c.big.cat) && IDS.includes(c.greeting.cat));
    }
  }
  const c = cast('two', { tasks: [T('agent_a', 'working', NaN), { id: 'agent_b', state: 'approval', last: 'now' }, { id: 'agent_c', state: 7, last: Infinity }], focusId: 7, mainCat: 'tiger', pair: [1, 2], agentCats: 'x' });
  assert.deepEqual(c.big, { pill: null, cat: 'shrimpy' });
  assert.equal(c.second.pill, 'agent_b', 'a time that is not a number is 0, a state that is not one is idle');
  assert.equal(c.greeting.cat, 'shrimpy');
  assert.doesNotThrow(() => cast('perAgent', deepFreeze(IN())));
  assert.deepEqual(cast('two', { tasks: [T('agent_a'), T('agent_b')], focusId: '__proto__' }).big.pill, null);
});

test('a raw settings value is fine: the pair, the map and the Main cat are cleaned the way the settings are', () => {
  const c = cast('two', { tasks: ISLAND, focusId: 'integration_claude', mainCat: 'Momo', pair: '["latte","latte"]', agentCats: { agent_gemini: 'tiger', constructor: 'momo' } });
  assert.deepEqual(c.big, { pill: 'integration_claude', cat: 'latte' });
  assert.equal(c.second.cat, 'patches', 'latte twice: the next coat');
  assert.equal(c.greeting.cat, 'shrimpy');
});

test('500 random islands keep the rules: the second cat ranks first, nothing is shown twice, the row is at most four', () => {
  const r = core.rng(404), states = [...core.STATES, 'bogus'], ids = ['integration_claude', 'agent_codex', 'agent_a', 'agent_b', 'agent_c', 'integration_stripe', 'integration_music', 'ai_openai'];
  const rank = s => ['approval', 'question'].includes(s) ? 0 : s === 'error' ? 1 : ['working', 'thinking', 'searching'].includes(s) ? 2 : 3;
  for (let i = 0; i < 500; i++) {
    const tasks = ids.filter(() => r() < .75).map(id => T(id, states[Math.floor(r() * states.length)], r() < .2 ? 0 : Math.floor(r() * 5))), focusId = r() < .15 ? null : ids[Math.floor(r() * ids.length)];
    const c = cast('two', { tasks, focusId }), others = tasks.filter(t => t.id !== focusId && core.isAgentPill(t.id));
    const st = t => core.STATES.includes(t.state) ? t.state : 'idle';
    const best = others.reduce((b, t) => !b || rank(st(t)) < rank(st(b)) || (rank(st(t)) === rank(st(b)) && t.last > b.last) ? t : b, null);
    assert.equal(c.second.pill, best ? best.id : null, JSON.stringify({ tasks, focusId }));
    const shown = [c.big.pill, c.second.pill, ...c.pills.map(p => p.pill)].filter(Boolean);
    assert.equal(new Set(shown).size, shown.length, 'nothing is shown twice');
    assert.ok(c.pills.length <= 4);
    const one = cast('one', { tasks, focusId });
    assert.ok(one.pills.every(p => p.cat === 'shrimpy') && one.big.cat === 'shrimpy' && one.drop === 'shrimpy');
  }
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test tests/cat/cast.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"`
Expected: `# tests 11`, `# pass 0`, `# fail 11`: the core has no `castOf` yet.

- [ ] **Step 3: Add the section to the core**

This inserts "Display modes: which cat appears where" above the `@@END-OF-CORE` marker, after Task 2's section. It only reads: it never draws a random number.

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
marker = '// @@END-OF-CORE: every later task inserts its section immediately above this line.'
assert s.count(marker) == 1
new = r'''// ── Display modes: which cat appears where (the cast) ────────────────────────
// A cat stands for an agent's pill. The big cat shows the focused pill; castOf says, for the chosen mode, which coat each place wears.
//   one:      the Main cat everywhere.
//   perAgent: the focused agent's cat is the big cat (the Main cat when the focus is an integration or nothing); every agent pill wears its agent's cat;
//             integration pills wear the Main cat.
//   two:      the pair: cat 1 is the big cat and shows the focused pill, cat 2 shows the busiest other agent; pills wear the Main cat.
/** The most pills the row and the 2x2 grid hold (both apps show `others.prefix(4)` / `otherTasks.slice(0, 4)`). */
const PILL_ROW=4;
/** How busy an agent is, for the busiest-other rule: 0 waits for you (approval or question), 1 error, 2 working, thinking or searching, 3 anything else. */
const busyRank=st=>st==='approval'||st==='question'?0:st==='error'?1:BUSY.has(st)?2:3;
const rankKey=(a,b)=>{for(let i=0;i<a.length;i++)if(a[i]!==b[i])return a[i]-b[i];return 0};
/**
 * The cast of one mode. `input`: {tasks, focusId, mainCat, pair, agentCats}.
 *   tasks    the island's pills in the app's own order, each {id, state, last}: `id` the pill ID, `state` one of STATES (anything else is idle),
 *            `last` the time of the pill's last event in ms (any clock; a missing or non-number one is 0). A pill listed twice counts once.
 *   focusId  the focused pill, or null.     mainCat, pair, agentCats  as stored (cleaned here), so a raw value is fine.
 * Returns {mode, big, second, pills, drop, greeting}:
 *   big       {pill, cat}: the big cat, compact or expanded. `pill` is the focused pill (null when there is none).
 *   second    null, or in Two cats mode {pill, cat}: the busiest other agent and pair cat 2. `pill` is null when no other agent pill exists (cat 2 idles, no badge).
 *             The busiest other agent is the agent pill other than the focused one that ranks first by busyRank (waiting on you, then error, then
 *             busy, then anything else), then by the most recent `last`, then by its place in `tasks`.
 *   pills     the row and the 2x2 grid: the tasks other than the focused one and, in Two cats mode, other than `second.pill`, the first PILL_ROW of them,
 *             each {pill, cat}, in the app's order.
 *   drop      the cat of the drop view and the drag ghost: the big cat's.
 *   greeting  {cat, pair, sessions}: `cat` the cat that falls in (the Main cat in every mode); `pair` null, or in Two cats mode the pair, which arrives
 *             together at the settle; `sessions` the four session cats in the grid's cell order (top left, top right, bottom left, bottom right):
 *             the cats of `pills` (in Per agent mode, the agents' own, so the glide hands over to the grid without a change), the Main cat for a cell with no pill.
 * An agent that has no stored coat and no default wears the Main cat here: agentCatFor gives it one when it is first seen, before it is drawn.
 */
function castOf(mode,input){const m=displayModeOf(mode),inp=isPlain(input)?input:{},main=catIdOf(inp.mainCat),pr=cleanPair(inp.pair),map=cleanAgentCats(inp.agentCats),seen=new Set(),list=[];
 for(const t of Array.isArray(inp.tasks)?inp.tasks:[]){if(!isPlain(t)||!isPillId(t.id)||seen.has(t.id))continue;seen.add(t.id);
  list.push({id:t.id,state:STATES.includes(t.state)?t.state:'idle',last:typeof t.last==='number'&&Number.isFinite(t.last)?t.last:0})}
 const focus=isPillId(inp.focusId)?inp.focusId:null,agentCat=id=>own(map,id)?map[id]:defaultAgentCat(id)||main,catOf=id=>m==='perAgent'&&isAgentPill(id)?agentCat(id):main;
 const big={pill:focus,cat:m==='two'?pr[0]:catOf(focus)};
 let second=null;
 if(m==='two'){let best=null;
  list.forEach((t,i)=>{if(t.id===focus||!isAgentPill(t.id))return;const key=[busyRank(t.state),-t.last,i];if(!best||rankKey(key,best.key)<0)best={id:t.id,key}});
  second={pill:best?best.id:null,cat:pr[1]}}
 const pills=list.filter(t=>t.id!==focus&&!(second&&t.id===second.pill)).slice(0,PILL_ROW).map(t=>({pill:t.id,cat:catOf(t.id)}));
 return{mode:m,big,second,pills,drop:big.cat,greeting:{cat:main,pair:m==='two'?pr:null,sessions:[0,1,2,3].map(i=>pills[i]?pills[i].cat:main)}}}
Object.assign(api,{PILL_ROW,busyRank,castOf});

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, new + marker))
PY
git diff --stat design/prototype/cat-core.js
```

Expected: `1 file changed, 124 insertions(+)`.

- [ ] **Step 4: Run the tests**

Run: `node --test tests/cat/cast.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"`
Expected: `# tests 11`, `# pass 11`, `# fail 0`.

- [ ] **Step 5: Prove the ranking bites: a waiting approval or question comes before an error (not committed)**

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "const busyRank=st=>st==='approval'||st==='question'?0:st==='error'?1:BUSY.has(st)?2:3;"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "const busyRank=st=>st==='error'?0:st==='approval'||st==='question'?1:BUSY.has(st)?2:3;"))
PY
node --test tests/cat/cast.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "const busyRank=st=>st==='error'?0:st==='approval'||st==='question'?1:BUSY.has(st)?2:3;"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "const busyRank=st=>st==='approval'||st==='question'?0:st==='error'?1:BUSY.has(st)?2:3;"))
PY
node --test tests/cat/cast.test.mjs 2>&1 | grep -E "^# (pass|fail)"
```

Expected: `not ok 5 - the busiest other agent…` and `not ok 11 - 500 random islands…`, `# pass 9`, `# fail 2`; after putting the line back, `# pass 11` and `# fail 0`.

- [ ] **Step 6: Run the whole contract**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓|✗"`
Expected: `# tests 183`, `# pass 183`, `# fail 0`; 11 `✓` fixture lines, `✓ 11 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`. (No fixture changed yet: the 172 earlier tests and the 11 new ones.)

- [ ] **Step 7: Add the replay tests and the fixture to the file list**

```bash
cat >> tests/cat/cast.test.mjs <<'EOF'

const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/cast-cases.json', import.meta.url), 'utf8'));
const roundTrip = v => JSON.parse(JSON.stringify(v));

test('cast-cases.json: the frozen values are the core\'s, and the ranks of the states', () => {
  assert.deepEqual(fx.ids, IDS);
  assert.deepEqual(fx.modes, core.DISPLAY_MODES);
  assert.equal(fx.pillRow, core.PILL_ROW);
  assert.deepEqual(fx.states, core.STATES);
  for (const r of fx.busyRank) assert.equal(core.busyRank(r.state), r.rank, r.state);
  assert.deepEqual(fx.busyRank.map(r => r.rank), [3, 2, 2, 2, 0, 0, 1, 3, 3, 3, 3, 3], 'idle, working, thinking, searching, approval, question, error, then the rest; an unknown state is last');
});

test('cast-cases.json: every case replays from its own input', () => {
  for (const c of fx.cases) assert.deepEqual(compare(roundTrip(cast(c.mode, c.input)), c.out), [], `${c.name} (${c.mode})`);
});

test('cast-cases.json: every scenario is in every mode, and the rules the spec worries about are in it', () => {
  const names = [...new Set(fx.cases.map(c => c.name))];
  for (const n of ['the island, Claude Code focused', 'the island, nothing focused', 'more pills than the row holds', 'no pills at all', 'a pill listed twice', 'approval beats error', 'an integration is never the second cat', 'the focused agent is never its own second cat', 'pill IDs that are not pill IDs', 'tasks that are not a list', 'nothing']) assert.ok(names.includes(n), n);
  for (const n of names.filter(x => !x.startsWith('the mode '))) assert.deepEqual(fx.cases.filter(c => c.name === n).map(c => c.mode), core.DISPLAY_MODES, n);
  assert.ok(fx.cases.some(c => c.mode === 'two' && c.out.second && c.out.second.pill === 'agent_codex'), 'a second cat');
  assert.ok(fx.cases.some(c => c.mode === 'two' && c.out.second && c.out.second.pill === null), 'a second cat with no agent');
  assert.ok(fx.cases.some(c => c.mode === 'perAgent' && c.out.pills.some(p => p.cat !== c.out.greeting.cat)), 'agent pills in their own cats');
});
EOF
python3 - <<'PY'
p = 'tests/cat/fixtures.test.mjs'
s = open(p, encoding='utf-8').read()
was, now = "'agent-cat-cases.json', 'collar-cases.json'", "'agent-cat-cases.json', 'cast-cases.json', 'collar-cases.json'"
assert s.count(was) == 1, was
open(p, 'w', encoding='utf-8').write(s.replace(was, now))
PY
node --test tests/cat/cast.test.mjs tests/cat/fixtures.test.mjs 2>&1 | grep -E "^(not ok|# (pass|fail))|ENOENT" | head
```

Expected: `not ok` lines for the fixtures tests (the list now has `cast-cases.json`, which does not exist yet), `ENOENT` lines that name `cast-cases.json`, and `not ok … - tests/cat/cast.test.mjs`: the replay part of that file cannot load without the fixture. The 11 self-checks from Step 1 still pass on their own.

- [ ] **Step 8: Add the builder and generate the fixture**

The builder goes above the `@@BUILDERS` marker. Every scenario, ranking and hostile input is replayed in all three modes, because the table of places is the contract.

```bash
python3 - <<'PY'
p = 'scripts/gen-cat-fixtures.mjs'
s = open(p, encoding='utf-8').read()
marker = '// @@BUILDERS: each task adds'
assert s.count(marker) == 1
snippet = r'''// ── The cast of each display mode (B-0): which cat is drawn where ─────────────
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

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, snippet + marker))
PY
node scripts/gen-cat-fixtures.mjs
ls -l tests/fixtures/cat/cast-cases.json
```

Expected: `wrote 12 fixture files to tests/fixtures/cat` and a `cast-cases.json` of about 93 KB (under the 400 KB the fixtures test allows).

- [ ] **Step 9: Run the tests, then prove the fixture is additive and that no-drift covers it**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|^not ok|✓|✗"`
Expected: `# tests 186`, `# pass 186`, `# fail 0`; 12 `✓` fixture lines (`cast-cases.json` among them), `✓ 12 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

Run: `node scripts/check-fixtures-additive.mjs 6c14947 | tail -5`
Expected: `  + agent-cat-cases.json is new`, `  + cast-cases.json is new`, `  + display-cases.json is new` and `✓ fixtures changed only by addition since 6c14947`.

Run: `git diff --stat -- tests/fixtures/cat`
Expected: no output (no existing fixture changed; the new ones are untracked).

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "const busyRank=st=>st==='approval'||st==='question'?0:st==='error'?1:BUSY.has(st)?2:3;"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "const busyRank=st=>st==='error'?0:st==='approval'||st==='question'?1:BUSY.has(st)?2:3;"))
PY
node scripts/gen-cat-fixtures.mjs --check 2>&1 | grep -E "✗|Fixtures drifted"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "const busyRank=st=>st==='error'?0:st==='approval'||st==='question'?1:BUSY.has(st)?2:3;"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "const busyRank=st=>st==='approval'||st==='question'?0:st==='error'?1:BUSY.has(st)?2:3;"))
PY
node scripts/gen-cat-fixtures.mjs --check | tail -1
```

Expected: first `✗ cast-cases.json drifted from cat-core.js (` followed by a number of differences, and `Fixtures drifted. cat-core.js is the tie-breaker…`; after putting the line back, `✓ 12 fixture files match cat-core.js`.

- [ ] **Step 10: Commit**

Run: `git status --short`
Expected: ` M design/prototype/cat-core.js`, ` M scripts/gen-cat-fixtures.mjs`, ` M tests/cat/fixtures.test.mjs`, `?? tests/cat/cast.test.mjs`, `?? tests/fixtures/cat/cast-cases.json`.

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/fixtures.test.mjs tests/cat/cast.test.mjs tests/fixtures/cat/cast-cases.json
git commit -m "feat(cat): castOf says which cat is drawn where in each display mode

One cat, a cat for each agent, and the pair: the big cat, the second cat (the busiest other agent), the row, the drop view and the
greeting's session cats. cast-cases.json pins every scenario in all three modes.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 4: Kittens: `kittenStep`, `kittenSlots` and `kitten-cases.json`

**Files:**
- Modify: `design/prototype/cat-core.js` (a new section above the `@@END-OF-CORE` marker), `scripts/gen-cat-fixtures.mjs` (a builder above the `@@BUILDERS` marker), `tests/cat/fixtures.test.mjs` (the file list)
- Create: `tests/cat/kittens.test.mjs`, `tests/fixtures/cat/kitten-cases.json` (generated)

**Interfaces:**
- Consumes: from the core: `isPlain`, `own`, `toolState`, `SLEEP_AFTER_MS`, `displayModeOf`; from the generator: `compare`, `FILES`, `core`.
- Produces in `CatCore`: `KITTEN_MAX`, `KITTEN_LEAVE_MS`, `KITTEN_STATES`, `cleanKittens`, `kittenStep`, `kittenOrder`, `kittenView`, `KITTEN_PLACES`, `kittenPlaceOf`, `kittenSlots`, exactly as in "Interface for the app plans" section 4; and `kitten-cases.json`.

- [ ] **Step 1: Write the failing tests**

```bash
cat > tests/cat/kittens.test.mjs <<'EOF'
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
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test tests/cat/kittens.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"`
Expected: `# tests 25`, `# pass 0`, `# fail 25`: the core has no `kittenStep` yet.

- [ ] **Step 3: Add the section to the core**

This inserts "Kittens: subagents shown as kittens beside their parent" above the `@@END-OF-CORE` marker, after Task 3's section. The slot numbers are the brainstorm mockup's, written as its pixels over its parent's size.

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
marker = '// @@END-OF-CORE: every later task inserts its section immediately above this line.'
assert s.count(marker) == 1
new = r'''// ── Kittens: subagents shown as kittens beside their parent ──────────────────
// A subagent is a kitten of its parent's cat. Each agent pill keeps a list of kittens, and kittenStep is the one reducer that changes it. The list holds
// plain objects {id, type, session, state, born, last, until}: `id` the subagent's agent_id, `type` its agent_type, `session` the session it belongs to (or null),
// `state` working, searching, approval or leaving, `born` and `last` the times of its start and its last event (ms, any clock, the same one in every event),
// `until` null, or, once it is leaving, the time it is removed. There is no timer: a leaving kitten is dropped by the next event, and kittenView hides it from `until` on.
/** At most this many kittens are tracked per agent; when a ninth starts, the oldest (by `born`) is dropped. */
const KITTEN_MAX=8;
/** A kitten that has stopped plays a happy blink for this long (ms), then goes. */
const KITTEN_LEAVE_MS=600;
const KITTEN_STATES=['working','searching','approval','leaving'];
const isKittenId=v=>typeof v==='string'&&v.length>0&&v.length<=128;
const typeOfAgent=v=>typeof v==='string'?v.slice(0,64):'';
const sessionOf=v=>isKittenId(v)?v:null;
/** A kitten list as an app may hold it, made safe: entries that are not kittens, or repeat an id, are dropped; every entry is a fresh object. */
function cleanKittens(list){const out=[],seen=new Set();
 for(const k of Array.isArray(list)?list:[]){if(!isPlain(k)||!isKittenId(k.id)||seen.has(k.id)||!KITTEN_STATES.includes(k.state)||!Number.isFinite(k.born)||!Number.isFinite(k.last))continue;
  seen.add(k.id);out.push({id:k.id,type:typeOfAgent(k.type),session:sessionOf(k.session),state:k.state,born:k.born,last:k.last,until:k.state==='leaving'&&Number.isFinite(k.until)?k.until:null})}
 return out}
const capKittens=L=>{while(L.length>KITTEN_MAX){let o=0;for(let i=1;i<L.length;i++)if(L[i].born<L[o].born)o=i;L.splice(o,1)}return L};
/**
 * The reducer. `list` is one pill's kittens, `ev` an event {type, t, ...} with `t` the time in ms; the result is a new list and nothing is changed.
 *   start       {id, agentType, session}   SubagentStart: a kitten, working. `session` (the hook's session_id) is optional. A second start for an id that is there only refreshes it.
 *   tool        {id, tool}        a Pre/PostToolUse that carries an agent_id: searching when `tool` is in SEARCH_TOOLS (toolState), else working.
 *   permission  {id}              a PermissionRequest from the subagent: approval.
 *   resolved    {id}              that request was answered: back to working.
 *   stop        {id}              SubagentStop: leaving for KITTEN_LEAVE_MS, then gone.
 *   end         {session}     the parent stopped or its session ended: no kittens. With a `session`, only that session's kittens go, and the ones with no session (two sessions of
 *                             one agent share a pill, and one of them stopping must not take the other's kittens); without one, every kitten goes.
 *   sweep                         the cat's sleep timer fired: a kitten whose last event is SLEEP_AFTER_MS or more ago is gone (its stop never came).
 *   tick                          nothing but the time.
 * Every event first drops the leaving kittens whose time is up. An event for an id with no kitten, or for a kitten that is already leaving, changes
 * nothing: a late tool event must not bring back a kitten that has gone, and without a SubagentStart there is nothing to show. An event that is not
 * an object, has no finite `t` or has an unknown type returns the list as it is (cleaned). Never throws.
 */
function kittenStep(list,ev){let L=cleanKittens(list);
 if(!isPlain(ev)||!Number.isFinite(ev.t))return L;
 const t=ev.t,at=id=>L.findIndex(k=>k.id===id&&k.state!=='leaving'),set=(i,p)=>{L[i]={...L[i],...p}};
 L=L.filter(k=>k.state!=='leaving'||k.until>t);
 switch(ev.type){
  case 'start':{if(!isKittenId(ev.id))break;const i=L.findIndex(k=>k.id===ev.id);
   if(i>=0&&L[i].state!=='leaving'){set(i,{last:t,type:typeOfAgent(ev.agentType)||L[i].type,session:sessionOf(ev.session)||L[i].session});break}
   if(i>=0)L.splice(i,1);
   L.push({id:ev.id,type:typeOfAgent(ev.agentType),session:sessionOf(ev.session),state:'working',born:t,last:t,until:null});capKittens(L);break}
  case 'tool':{const i=at(ev.id);if(i>=0)set(i,{state:toolState(ev.tool),last:t});break}
  case 'permission':{const i=at(ev.id);if(i>=0)set(i,{state:'approval',last:t});break}
  case 'resolved':{const i=at(ev.id);if(i>=0)set(i,{state:L[i].state==='approval'?'working':L[i].state,last:t});break}
  case 'stop':{const i=at(ev.id);if(i>=0)set(i,{state:'leaving',last:t,until:t+KITTEN_LEAVE_MS});break}
  case 'end':{const q=sessionOf(ev.session);L=q===null?[]:L.filter(k=>k.session!==null&&k.session!==q);break}
  case 'sweep':L=L.filter(k=>t-k.last<SLEEP_AFTER_MS);break}
 return L}
/** The order kittens are shown in: a kitten waiting on an approval first, then the newest (by `born`, a later start first when they tie). */
const kittenOrder=list=>cleanKittens(list).map((k,i)=>({k,i})).sort((a,b)=>(b.k.state==='approval')-(a.k.state==='approval')||b.k.born-a.k.born||b.i-a.i).map(x=>x.k);
/** What is drawn at `now` (ms): the kittens in kittenOrder, without a leaving kitten whose time is up. A `now` that is not a number hides nothing. */
const kittenView=(list,now)=>kittenOrder(cleanKittens(list).filter(k=>k.state!=='leaving'||!Number.isFinite(now)||k.until>now));
/**
 * Where kittens sit. Every number is a multiple of a unit: `D`, the parent's head width, with the origin at the parent's head centre (x to the right, y down),
 * or `H`, the pill's height, with the origin at the pill's trailing edge (x positive towards the trailing end, so the kittens' x is negative) and
 * the middle of its height. `d` is a kitten's head width. The numbers are the brainstorm mockup's, divided by its parent's size: Ø15 kittens under a
 * Ø58 big cat (centres 24, 42 and 60 px right of it and 34 px down, 18 apart), Ø12 beside a Ø20 compact cat (22 and 35 px right, 5 down, "+N" 42 right and
 * 10 up), Ø15 in a 28 px pill.
 *   align 'start': the i-th kitten is at x0 + i * step; 'center': the row is centred on x0.   max: the most kittens drawn; the rest is "+N".
 *   moreAt: where the "+N" label is centred (default: the next slot after the last one drawn; the pair's is below the middle of its row, away from the other cat's kittens), and moreSize its text height.
 *   label: for the pair in the compact notch, which has no room beside it: only a count "×N", drawn by the second cat of the pair, at that spot.
 */
const KITTEN_PLACES={
 bigExpanded:{unit:'D',max:3,d:15/58,x0:24/58,y0:34/58,step:18/58,align:'start',moreSize:.2},
 bigCompact:{unit:'D',max:2,d:12/20,x0:22/20,y0:5/20,step:13/20,align:'start',moreAt:[42/20,-10/20],moreSize:.25},
 pairCompact:{unit:'D',max:0,label:{x:1.1,y:.3,size:.5}},
 pairExpanded:{unit:'D',max:3,d:15/58,x0:0,y0:34/58,step:18/58,align:'center',moreAt:[0,50/58],moreSize:.2},
 pill:{unit:'H',max:3,d:15/28,x0:-17.5/28,y0:0,step:-16/28,align:'start',moreSize:.36}};
/** The place kittens go for the big cat (and, in Two cats mode, for cat 2): bigExpanded or bigCompact; in Two cats mode pairExpanded or pairCompact. */
const kittenPlaceOf=(mode,expanded)=>displayModeOf(mode)==='two'?(expanded?'pairExpanded':'pairCompact'):(expanded?'bigExpanded':'bigCompact');
/**
 * The slots for one parent's kittens in one place. `kittens` is what kittenView returned (already in order). Returns
 * {place, unit, count, shown, more, moreAt, label}: `shown` the first `max` kittens as {id, state, x, y, d}; `more` how many are left over;
 * `moreAt` {x, y, size} or null when none is left over; `label` null, or for pairCompact {text: "×N", x, y, size} when there is a kitten. An unknown place shows nothing.
 */
function kittenSlots(place,kittens){const P=own(KITTEN_PLACES,place)?KITTEN_PLACES[place]:null,L=Array.isArray(kittens)?kittens.filter(k=>isPlain(k)&&isKittenId(k.id)):[],count=L.length;
 if(!P)return{place:String(place),unit:null,count,shown:[],more:0,moreAt:null,label:null};
 const n=Math.min(count,P.max),x=i=>P.align==='center'?P.x0+(i-(n-1)/2)*P.step:P.x0+i*P.step,more=P.label?0:count-n;
 return{place,unit:P.unit,count,shown:L.slice(0,n).map((k,i)=>({id:k.id,state:typeof k.state==='string'?k.state:'working',x:x(i),y:P.y0,d:P.d})),more,
  moreAt:more>0?{x:P.moreAt?P.moreAt[0]:P.x0+P.max*P.step,y:P.moreAt?P.moreAt[1]:P.y0,size:P.moreSize}:null,
  label:P.label&&count>0?{text:`×${count}`,x:P.label.x,y:P.label.y,size:P.label.size}:null}}
Object.assign(api,{KITTEN_MAX,KITTEN_LEAVE_MS,KITTEN_STATES,cleanKittens,kittenStep,kittenOrder,kittenView,KITTEN_PLACES,kittenPlaceOf,kittenSlots});

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, new + marker))
PY
git diff --stat design/prototype/cat-core.js
```

Expected: `1 file changed, 209 insertions(+)`.

- [ ] **Step 4: Run the tests**

Run: `node --test tests/cat/kittens.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"`
Expected: `# tests 25`, `# pass 25`, `# fail 0`.

- [ ] **Step 5: Prove the cap bites: at most eight kittens (not committed)**

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "const KITTEN_MAX=8;"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "const KITTEN_MAX=9;"))
PY
node --test tests/cat/kittens.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "const KITTEN_MAX=9;"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "const KITTEN_MAX=8;"))
PY
node --test tests/cat/kittens.test.mjs 2>&1 | grep -E "^# (pass|fail)"
```

Expected: `not ok 1 - the limits…` and `not ok 10 - at most eight kittens…`, `# pass 23`, `# fail 2`; after putting the line back, `# pass 25` and `# fail 0`.

- [ ] **Step 6: Run the whole contract**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓|✗"`
Expected: `# tests 211`, `# pass 211`, `# fail 0`; 12 `✓` fixture lines, `✓ 12 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`. (No fixture changed yet: the 186 earlier tests and the 25 new ones.)

- [ ] **Step 7: Add the replay tests and the fixture to the file list**

```bash
cat >> tests/cat/kittens.test.mjs <<'EOF'

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
EOF
python3 - <<'PY'
p = 'tests/cat/fixtures.test.mjs'
s = open(p, encoding='utf-8').read()
was, now = "'geometry-cases.json', 'motion-cases.json'", "'geometry-cases.json', 'kitten-cases.json', 'motion-cases.json'"
assert s.count(was) == 1, was
open(p, 'w', encoding='utf-8').write(s.replace(was, now))
PY
node --test tests/cat/kittens.test.mjs tests/cat/fixtures.test.mjs 2>&1 | grep -E "^(not ok|# (pass|fail))|ENOENT" | head
```

Expected: `not ok` lines for the fixtures tests (the list now has `kitten-cases.json`, which does not exist yet), `ENOENT` lines that name `kitten-cases.json`, and `not ok … - tests/cat/kittens.test.mjs`: the replay part of that file cannot load without the fixture. The 25 self-checks from Step 1 still pass on their own.

- [ ] **Step 8: Add the builder and generate the fixture**

The builder goes above the `@@BUILDERS` marker. Each script is a list of events replayed through `kittenStep`, with the whole list after each one, so a port compares state at every step. The slots are listed for every place and for 0, 1, 2, 3, 4 and 7 kittens.

```bash
python3 - <<'PY'
p = 'scripts/gen-cat-fixtures.mjs'
s = open(p, encoding='utf-8').read()
marker = '// @@BUILDERS: each task adds'
assert s.count(marker) == 1
snippet = r'''// ── Kittens (B-0): the reducer, the order and the slots ───────────────────────
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

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, snippet + marker))
PY
node scripts/gen-cat-fixtures.mjs
ls -l tests/fixtures/cat/kitten-cases.json
```

Expected: `wrote 13 fixture files to tests/fixtures/cat` and a `kitten-cases.json` of about 49 KB (under the 400 KB the fixtures test allows).

- [ ] **Step 9: Run the tests, then prove the fixture is additive and that no-drift covers it**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|^not ok|✓|✗"`
Expected: `# tests 214`, `# pass 214`, `# fail 0`; 13 `✓` fixture lines (`kitten-cases.json` among them), `✓ 13 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

Run: `node scripts/check-fixtures-additive.mjs 6c14947 | tail -6`
Expected: `  + agent-cat-cases.json is new`, `  + cast-cases.json is new`, `  + display-cases.json is new`, `  + kitten-cases.json is new` and `✓ fixtures changed only by addition since 6c14947`.

Run: `git diff --stat -- tests/fixtures/cat`
Expected: no output (no existing fixture changed; the new ones are untracked).

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "const KITTEN_MAX=8;"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "const KITTEN_MAX=9;"))
PY
node scripts/gen-cat-fixtures.mjs --check 2>&1 | grep -E "✗|Fixtures drifted"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "const KITTEN_MAX=9;"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "const KITTEN_MAX=8;"))
PY
node scripts/gen-cat-fixtures.mjs --check | tail -1
```

Expected: first `✗ kitten-cases.json drifted from cat-core.js (` followed by a number of differences, and `Fixtures drifted. cat-core.js is the tie-breaker…`; after putting the line back, `✓ 13 fixture files match cat-core.js`.

- [ ] **Step 10: Commit**

Run: `git status --short`
Expected: ` M design/prototype/cat-core.js`, ` M scripts/gen-cat-fixtures.mjs`, ` M tests/cat/fixtures.test.mjs`, `?? tests/cat/kittens.test.mjs`, `?? tests/fixtures/cat/kitten-cases.json`.

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/fixtures.test.mjs tests/cat/kittens.test.mjs tests/fixtures/cat/kitten-cases.json
git commit -m "feat(cat): subagent kittens are kept by kittenStep and placed by kittenSlots, in the core

A pure reducer over a pill's kittens: start, tool, permission, stop (a 0.6 s farewell, no timer), the parent ending (per session if asked)
and the sleep sweep; at most eight; an event for a kitten that is not there changes nothing. Slots for the five places, from the mockup.
kitten-cases.json pins both.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 5: Small coloured eyes: `smallEye` and `small-eye-cases.json`

**Files:**
- Modify: `design/prototype/cat-core.js` (a new section above the `@@END-OF-CORE` marker), `scripts/gen-cat-fixtures.mjs` (a builder above the `@@BUILDERS` marker), `tests/cat/fixtures.test.mjs` (the file list)
- Create: `tests/cat/smalleye.test.mjs`, `tests/fixtures/cat/small-eye-cases.json` (generated)

**Interfaces:**
- Consumes: from the core: `isPlain`, `kittenOf`, `PRESETS` (in a test), `rng`; from the generator: `compare`, `FILES`, `core`.
- Produces in `CatCore`: `SMALL_EYE_SHAPES`, `SMALL_EYE`, `usesSmallEye`, `smallEye`, exactly as in "Interface for the app plans" section 5; and `small-eye-cases.json`.

- [ ] **Step 1: Write the failing tests**

```bash
cat > tests/cat/smalleye.test.mjs <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const eye = core.smallEye;
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const SHAPES = core.SMALL_EYE_SHAPES;
const INK = ['line', 'flat', 'happy', 'closed', 'spiral', 'heart', 'star'];

test('the starting values of the spec are the contract\'s: a 0.42 by 0.46 iris, a 0.18 by 0.40 pupil, the catchlight and the rim', () => {
  const S = core.SMALL_EYE;
  assert.deepEqual([S.iris.w, S.iris.h, S.pupil.w, S.pupil.h], [.42, .46, .18, .40]);
  assert.deepEqual(S.light, { x: -.11, y: -.10, r: .075, minR: .45 });
  assert.deepEqual(S.rim, { k: .05, min: .5 });
  assert.equal(S.closeBelow, .22, 'the realistic eye\'s own threshold');
  assert.deepEqual(SHAPES, ['pill', 'wide', 'dot', 'tired']);
  assert.ok(.42 > .34 && .46 > .40, 'a little bigger than the ink pill it replaces (0.34 by 0.40)');
});

test('which eyes are small coloured eyes: the plain resting shapes and the left eye of a wink; every expression stays ink', () => {
  for (const s of SHAPES) for (const sd of [-1, 1]) assert.equal(core.usesSmallEye(s, sd), true, `${s} ${sd}`);
  for (const s of INK) for (const sd of [-1, 1]) assert.equal(core.usesSmallEye(s, sd), false, `${s} ${sd}`);
  assert.equal(core.usesSmallEye('wink', -1), true);
  assert.equal(core.usesSmallEye('wink', 1), false);
  for (const s of ['bogus', '', 'PILL', undefined, null, 7, {}]) assert.equal(core.usesSmallEye(s, -1), false, String(s));
  for (const s of INK) assert.equal(eye(s, { R: 10 }), null, s);
  assert.equal(eye('wink', { sd: 1, R: 10 }), null);
  assert.equal(eye('bogus', { R: 10 }), null);
});

test('the resting eye at R = 10: the iris 4.2 by 4.6, the pupil 1.8 by 4, the catchlight at (-1.1, -1.0), the rim 0.5', () => {
  const e = eye('pill', { sd: -1, R: 10 });
  assert.equal(e.closed, false);
  near(e.iris.rx * 2, 4.2); near(e.iris.ry * 2, 4.6); near(e.iris.r, 2.3);
  near(e.pupil.rx * 2, 1.8); near(e.pupil.ry * 2, 4); near(e.pupil.x, 0); near(e.pupil.y, 0);
  near(e.light.x, -1.1); near(e.light.y, -1.0); near(e.light.r, .75);
  near(e.rim, .5);
  assert.deepEqual(Object.keys(e), ['shape', 'closed', 'iris', 'pupil', 'light', 'rim']);
});

test('the floors: the catchlight never under 0.45 px and the rim never under 0.5 px, and both grow with the head', () => {
  for (const R of [0, 1, 3, 5, 5.9, 6]) { const e = eye('pill', { R }); near(e.light.r, .45); near(e.rim, .5); }
  const big = eye('pill', { R: 20 });
  near(big.light.r, 1.5); near(big.rim, 1);
  near(eye('pill', { R: 8 }).light.r, .6);
  near(eye('pill', { R: 12 }).rim, .6);
});

test('wide is the iris times (1.16, 1.12); dot is round with a round, bigger pupil; tired shows at most 0.42 of the eye', () => {
  const p = eye('pill', { R: 10 }), w = eye('wide', { R: 10 }), d = eye('dot', { R: 10 }), t = eye('tired', { R: 10 }), t2 = eye('tired', { R: 10, open: .3 });
  near(w.iris.rx / p.iris.rx, 1.16); near(w.iris.ry / p.iris.ry, 1.12);
  near(d.iris.rx, d.iris.ry); near(d.iris.rx * 2, 4.2); near(d.pupil.rx, d.pupil.ry); near(d.pupil.rx * 2, 2.6);
  assert.ok(d.pupil.rx > p.pupil.rx, 'dilated');
  near(t.iris.ry / p.iris.ry, .42);
  near(t2.iris.ry / p.iris.ry, .3, 1e-12);
  assert.equal(eye('tired', { R: 10, open: .2 }).closed, true);
  assert.equal(eye('wink', { sd: -1, R: 10 }).shape, 'wink');
  assert.deepEqual({ ...eye('wink', { sd: -1, R: 10 }), shape: 'pill' }, eye('pill', { sd: -1, R: 10 }), 'the left eye of a wink is a pill');
});

test('the expression scale grows everything with the head; the eye\'s side does not change its shape', () => {
  const a = eye('pill', { R: 10, es: 1.25 }), b = eye('pill', { R: 12.5 });
  assert.deepEqual(a, b);
  assert.deepEqual(eye('pill', { R: 10, sd: 1 }), eye('pill', { R: 10, sd: -1 }), 'the iris colour is the renderer\'s: the geometry is the same for both eyes');
  assert.deepEqual(eye('pill', { R: 10, es: 0 }).iris, { rx: 0, ry: 0, r: 0 });
});

test('a kitten\'s eye is 1.2 times wider and 1.32 times taller, the ratio kittenOf gives a kitten\'s eyes', () => {
  const kw = core.kittenOf(core.PRESETS.momo).eye.w / core.PRESETS.momo.eye.w, kh = core.kittenOf(core.PRESETS.momo).eye.h / core.PRESETS.momo.eye.h;
  near(kw, 1.2); near(kh, 1.32);
  for (const s of SHAPES) {
    const a = eye(s, { R: 9 }), k = eye(s, { R: 9, kitten: true });
    near(k.iris.rx / a.iris.rx, kw); near(k.iris.ry / a.iris.ry, kh);
    near(k.pupil.rx / a.pupil.rx, kw);
  }
  assert.deepEqual(eye('pill', { R: 9, kitten: 'yes' }), eye('pill', { R: 9 }), 'only a real true counts');
});

test('a blink or a squint under 0.22 of the eye closes it to a line, as the realistic eye does; at 0.22 it is still open', () => {
  assert.equal(eye('pill', { R: 10, open: .22 }).closed, false);
  assert.equal(eye('pill', { R: 10, open: .2199 }).closed, true);
  const c = eye('pill', { R: 10, open: 0 });
  assert.deepEqual(compare(c, { shape: 'pill', closed: true, line: { x0: -2.1, y0: 0, cx: 0, cy: .4 * 2.3, x1: 2.1, y1: 0, width: 1 } }), []);
  near(eye('pill', { R: 40, open: 0 }).line.width, 1.8);
  assert.equal(eye('pill', { R: 10, open: -1 }).closed, true, 'open is held to 0 up to 1');
  assert.equal(eye('pill', { R: 10, open: 7 }).closed, false);
  assert.deepEqual(eye('pill', { R: 10, open: 7 }), eye('pill', { R: 10, open: 1 }));
  const half = eye('pill', { R: 10, open: .5 }), full = eye('pill', { R: 10 });
  near(half.iris.rx, full.iris.rx); near(half.iris.ry, full.iris.ry / 2);
  assert.ok(half.pupil.ry < full.pupil.ry && half.pupil.ry <= .87 * half.iris.ry + 1e-12, 'the pupil keeps inside the smaller iris');
  near(half.light.y, full.light.y / 2);
});

test('the pupil follows the gaze a little: 0.2 of the iris\'s half-width across at yaw 0.62, 0.08 of its half-height up at pitch 0.5', () => {
  const rest = eye('pill', { R: 10 }), right = eye('pill', { R: 10, yaw: .62 }), left = eye('pill', { R: 10, yaw: -.62 }), up = eye('pill', { R: 10, pitch: .5 }), down = eye('pill', { R: 10, pitch: -.5 });
  near(right.pupil.x, .2 * rest.iris.rx); near(left.pupil.x, -.2 * rest.iris.rx);
  near(up.pupil.y, -.08 * rest.iris.ry); near(down.pupil.y, .08 * rest.iris.ry);
  near(eye('pill', { R: 10, yaw: 9, pitch: 9 }).pupil.x, right.pupil.x);
  near(eye('pill', { R: 10, yaw: .31 }).pupil.x, right.pupil.x / 2);
  assert.deepEqual(eye('pill', { R: 10, yaw: 'x', pitch: null }), rest, 'a gaze that is not a number is straight ahead');
});

test('the pupil never leaves the iris and the catchlight stays in it, at every size, squint, gaze and kitten', () => {
  let worst = 0;
  for (const shape of SHAPES) for (const kitten of [false, true]) for (const es of [.8, 1, 1.25]) for (let open = .22; open <= 1.0001; open += .026) for (const yaw of [-1, -.62, -.3, 0, .62, 1]) for (const pitch of [-1, -.5, 0, .25, .5, 1]) {
    const e = eye(shape, { sd: 1, R: 8, es, open, yaw, pitch, kitten });
    if (e.closed) continue;
    for (let a = 0; a < 360; a += 2) { const t = a * Math.PI / 180, x = e.pupil.x + e.pupil.rx * Math.cos(t), y = e.pupil.y + e.pupil.ry * Math.sin(t); worst = Math.max(worst, (x / e.iris.rx) ** 2 + (y / e.iris.ry) ** 2); }
    assert.ok((e.light.x / e.iris.rx) ** 2 + (e.light.y / e.iris.ry) ** 2 < 1, `${shape} light`);
    assert.ok(e.iris.r === Math.max(e.iris.rx, e.iris.ry) && e.rim >= .5 && e.light.r >= .45);
  }
  assert.ok(worst < 1, `the pupil leaves the iris: ${worst}`);
});

test('numbers that are not numbers are taken as their default, and nothing is ever NaN: 5000 random calls', () => {
  assert.deepEqual(eye('pill', { R: 'x' }), eye('pill', { R: 0 }));
  assert.deepEqual(eye('pill', { R: NaN, es: NaN, open: NaN, yaw: NaN, pitch: NaN }), eye('pill', { R: 0 }));
  assert.deepEqual(eye('pill', { R: -4 }), eye('pill', { R: 0 }), 'a negative head is no head');
  assert.deepEqual(eye('pill', { R: 10, es: -1 }), eye('pill', { R: 10, es: 0 }));
  assert.deepEqual(eye('pill'), eye('pill', {}));
  assert.doesNotThrow(() => eye('pill', null));
  assert.doesNotThrow(() => eye(undefined, undefined));
  const r = core.rng(5), pool = [0, 1, -1, .5, 99, -99, NaN, Infinity, -Infinity, 'x', null, undefined, true, {}, [], 1e300, 5e-324];
  const pick = () => pool[Math.floor(r() * pool.length)], fin = v => typeof v === 'string' || typeof v === 'boolean' || (typeof v === 'number' && Number.isFinite(v)) || (v && typeof v === 'object' && Object.values(v).every(fin));
  for (let i = 0; i < 5000; i++) {
    const out = eye([...SHAPES, 'wink', 'happy', 'bogus'][Math.floor(r() * 7)], { sd: pick(), R: pick(), es: pick(), open: pick(), yaw: pick(), pitch: pick(), kitten: pick() });
    assert.ok(out === null || fin(out), JSON.stringify(out));
  }
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test tests/cat/smalleye.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"`
Expected: `# tests 11`, `# pass 0`, `# fail 11`: the core has no `smallEye` yet.

- [ ] **Step 3: Add the section to the core**

This inserts "Small eyes: the coloured eyes of the compact detail level" above the `@@END-OF-CORE` marker, after Task 4's section. The numbers are the spec's starting values; the owner judges them on the contact sheet at the checkpoint, and a change is one edit here plus a regenerate.

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
marker = '// @@END-OF-CORE: every later task inserts its section immediately above this line.'
assert s.count(marker) == 1
new = r'''// ── Small eyes: the coloured eyes of the compact detail level (sub-project B) ─
// Below Ø28 the plain resting eyes (pill, wide, dot and tired) used to be the cat's ink colour, the same for every cat. They are now small coloured eyes:
// a round iris in the coat's colours, a slit pupil, one catchlight and a thin dark rim, so Shrimpy stays green-eyed and Momo gold-eyed down to Ø12.
// This is the geometry only, in px of the eye's own frame (its centre is the origin, y down, before the renderer's foreshortening). The colours are
// the renderer's: the iris is a radial gradient from the preset's iris[0] at the centre to iris[1] at radius `iris.r` (irisR for the right eye, sd = 1,
// when the coat has one), the pupil is Theme.Cat.pupil, the catchlight white at 0.92, the rim the preset's liner colour. The expression shapes
// (happy, closed, wink's right eye, spiral, heart, star, line and flat) stay ink and are not part of this.
/** The resting shapes that become a small coloured eye. The left eye of a wink is one too (the right is an ink arc). */
const SMALL_EYE_SHAPES=['pill','wide','dot','tired'];
/**
 * The numbers. Sizes are fractions of u = R * es, the head radius times the expression scale (the surprised emote makes the eyes bigger), and are
 * full widths and heights. The iris is 0.42 wide and 0.46 tall (the ink pill it replaces was 0.34 by 0.40); the pupil 0.18 by 0.40, held inside the iris.
 * wide is the iris times (1.16, 1.12), as the ink shape was; dot is a round iris (0.42 by 0.42) with a round, dilated pupil (0.26 across); tired
 * shows at most `open` 0.42 of the eye. The pupil moves with the gaze (yaw / 0.62 and pitch / 0.5, held to -1 to 1) by at most travel.x of the iris's
 * half-width across and travel.y of its half-height up or down (0.2 and 0.08: a slit pupil that nearly fills the iris has little room), and so never leaves it. The catchlight has radius max(0.075 u, 0.45 px) at (-0.11 u, -0.10 u), kept to the same
 * share of the iris when the eye is smaller or squinting; the rim is max(0.05 u, 0.5 px) wide. A blink or squint under `closeBelow` of the eye's
 * height closes it to a line, as the realistic eye does (its arc, in the ink colour). A kitten's eye is `kitten.w` times wider and `kitten.h` times
 * taller, the ratio kittenOf gives a kitten's eyes.
 */
const SMALL_EYE={iris:{w:.42,h:.46},pupil:{w:.18,h:.40},wide:{w:1.16,h:1.12},dot:{iris:[.42,.42],pupil:[.26,.26]},tired:{open:.42},
 light:{x:-.11,y:-.10,r:.075,minR:.45},rim:{k:.05,min:.5},travel:{x:.2,y:.08},closeBelow:.22,pupilFit:.87,kitten:{w:1.2,h:1.32},line:{width:.045,minWidth:1,curve:.4}};
/** True when the renderer draws shape `shape` of the eye `sd` (-1 left, 1 right) with smallEye at the compact level, and false when it stays ink. */
const usesSmallEye=(shape,sd)=>SMALL_EYE_SHAPES.includes(shape)||(shape==='wink'&&sd<0);
/**
 * One small eye. `o`: {sd (-1 or 1, default -1), R (head radius, px), es (expression scale, default 1), open (0 to 1: pose.open * (1 - pose.lid), default 1),
 * yaw and pitch (the pose's, default 0), kitten (default false)}. A non-number is taken as its default; R is held to 0 up to 10000, es to 0 up to 10 and `open` to 0 up to 1. Returns null for a
 * shape that is not a small eye (draw the ink shape), else
 *   {shape, closed: false, iris: {rx, ry, r}, pupil: {x, y, rx, ry}, light: {x, y, r}, rim}    the two ellipses' radii, their centres, the gradient radius r
 *   {shape, closed: true, line: {x0, y0, cx, cy, x1, y1, width}}                                  a quadratic arc in the ink colour, drawn at alpha 0.9
 */
function smallEye(shape,opts){const o=isPlain(opts)?opts:{};if(!usesSmallEye(shape,o.sd===1?1:-1))return null;
 const num=(v,d)=>typeof v==='number'&&Number.isFinite(v)?v:d,S=SMALL_EYE,R=Math.max(0,Math.min(1e4,num(o.R,0))),u=R*Math.max(0,Math.min(10,num(o.es,1))),sh=shape==='wink'?'pill':shape,kit=o.kitten===true,kw=kit?S.kitten.w:1,kh=kit?S.kitten.h:1;
 const open=Math.max(0,Math.min(1,num(o.open,1))),op=sh==='tired'?Math.min(open,S.tired.open):open;
 const base=sh==='dot'?S.dot.iris:[S.iris.w*(sh==='wide'?S.wide.w:1),S.iris.h*(sh==='wide'?S.wide.h:1)],rx0=base[0]/2*kw*u,ry0=base[1]/2*kh*u;
 if(op<S.closeBelow)return{shape,closed:true,line:{x0:-rx0,y0:0,cx:0,cy:S.line.curve*ry0,x1:rx0,y1:0,width:Math.max(S.line.minWidth,S.line.width*u)}};
 const ry=ry0*op,pw=(sh==='dot'?S.dot.pupil[0]:S.pupil.w)/2*kw*u,pry=Math.min((sh==='dot'?S.dot.pupil[1]:S.pupil.h)/2*kh*u,S.pupilFit*ry),
  gx=Math.max(-1,Math.min(1,num(o.yaw,0)/.62)),gy=Math.max(-1,Math.min(1,num(o.pitch,0)/.5)),
  px=gx*S.travel.x*rx0,py=-gy*S.travel.y*ry;
 return{shape,closed:false,iris:{rx:rx0,ry,r:Math.max(rx0,ry)},pupil:{x:px,y:py,rx:pw,ry:pry},
  light:{x:S.light.x/(S.iris.w/2)*rx0,y:S.light.y/(S.iris.h/2)*ry,r:Math.max(S.light.r*u,S.light.minR)},rim:Math.max(S.rim.k*u,S.rim.min)}}
Object.assign(api,{SMALL_EYE_SHAPES,SMALL_EYE,usesSmallEye,smallEye});

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, new + marker))
PY
git diff --stat design/prototype/cat-core.js
```

Expected: `1 file changed, 251 insertions(+)`.

- [ ] **Step 4: Run the tests**

Run: `node --test tests/cat/smalleye.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"`
Expected: `# tests 11`, `# pass 11`, `# fail 0`.

- [ ] **Step 5: Prove the closing threshold bites: under 0.22 of the eye it is a line (not committed)**

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "closeBelow:.22,"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "closeBelow:.2,"))
PY
node --test tests/cat/smalleye.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "closeBelow:.2,"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "closeBelow:.22,"))
PY
node --test tests/cat/smalleye.test.mjs 2>&1 | grep -E "^# (pass|fail)"
```

Expected: `not ok 1 - the starting values of the spec…`, `not ok 5 - wide is the iris times…` and `not ok 8 - a blink or a squint…`, `# pass 8`, `# fail 3`; after putting the line back, `# pass 11` and `# fail 0`.

- [ ] **Step 6: Run the whole contract**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓|✗"`
Expected: `# tests 225`, `# pass 225`, `# fail 0`; 13 `✓` fixture lines, `✓ 13 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`. (No fixture changed yet: the 214 earlier tests and the 11 new ones.)

- [ ] **Step 7: Add the replay tests and the fixture to the file list**

```bash
cat >> tests/cat/smalleye.test.mjs <<'EOF'

const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/small-eye-cases.json', import.meta.url), 'utf8'));
const roundTrip = v => JSON.parse(JSON.stringify(v));

test('small-eye-cases.json: the constants and the shapes are the core\'s', () => {
  assert.deepEqual(compare(roundTrip(core.SMALL_EYE), fx.constants), []);
  assert.deepEqual(fx.shapes, SHAPES);
});

test('small-eye-cases.json: every row replays from its own input', () => {
  for (const g of ['sizes', 'squints', 'gazes', 'scales', 'others', 'hostile']) fx[g].forEach((c, i) => assert.deepEqual(compare(roundTrip(eye(c.shape, c.o)), c.out), [], `${g} ${i}: ${c.shape} ${JSON.stringify(c.o)}`));
  for (const c of fx.uses) assert.equal(core.usesSmallEye(c.shape, c.sd), c.out, `${c.shape} ${c.sd}`);
});

test('small-eye-cases.json: sizes from R 3 to R 22 for kittens and cats, every squint and gaze, the shapes that stay ink and the hostile inputs are in it', () => {
  assert.equal(fx.sizes.length, 56); assert.equal(fx.squints.length, 72); assert.equal(fx.gazes.length, 72); assert.equal(fx.scales.length, 20);
  assert.ok(fx.squints.some(c => c.out.closed) && fx.squints.some(c => !c.out.closed), 'both closed and open');
  assert.ok(fx.others.filter(c => c.out === null).length >= 11, 'ink shapes and the right eye of a wink');
  assert.ok(fx.hostile.length >= 19 && fx.hostile.filter(c => c.out === null).length === 1, 'hostile inputs still give an eye, except a shape that is not a shape');
  assert.ok(fx.sizes.some(c => c.o.kitten === true) && fx.sizes.some(c => c.o.kitten === false));
  assert.ok(fx.sizes.filter(c => !c.out.closed && c.out.light.r === .45).length >= 8, 'the catchlight floor bites at the smallest sizes');
});
EOF
python3 - <<'PY'
p = 'tests/cat/fixtures.test.mjs'
s = open(p, encoding='utf-8').read()
was, now = "'settings-cases.json', 'warp-cases.json'", "'settings-cases.json', 'small-eye-cases.json', 'warp-cases.json'"
assert s.count(was) == 1, was
open(p, 'w', encoding='utf-8').write(s.replace(was, now))
PY
node --test tests/cat/smalleye.test.mjs tests/cat/fixtures.test.mjs 2>&1 | grep -E "^(not ok|# (pass|fail))|ENOENT" | head
```

Expected: `not ok` lines for the fixtures tests (the list now has `small-eye-cases.json`, which does not exist yet), `ENOENT` lines that name `small-eye-cases.json`, and `not ok … - tests/cat/smalleye.test.mjs`: the replay part of that file cannot load without the fixture. The 11 self-checks from Step 1 still pass on their own.

- [ ] **Step 8: Add the builder and generate the fixture**

The builder goes above the `@@BUILDERS` marker. The rows cover every shape at the sizes of the compact level, every squint, the gazes, the expression scales, the shapes that stay ink and the hostile inputs JSON can hold.

```bash
python3 - <<'PY'
p = 'scripts/gen-cat-fixtures.mjs'
s = open(p, encoding='utf-8').read()
marker = '// @@BUILDERS: each task adds'
assert s.count(marker) == 1
snippet = r'''// ── Small coloured eyes (B-0): the geometry of the compact detail level's resting eyes ──
// A row is {shape, o, out}: smallEye(shape, o) is out, null for a shape that stays ink. `o` is written as given, so a missing key is the default.
// R is the head radius in px: 5, 7, 9, 11 and 14 are the heads Ø12 to Ø28 of a Ø = 2 R x 1.12 cat (Ø11 session cats and the Ø12 grid cats are the smallest).
// The hostile rows are the ones JSON can hold (null, text, negative and out-of-range numbers); NaN and Infinity cannot be written, the self-checks cover them.
FILES['small-eye-cases.json'] = () => {
  const S = core.SMALL_EYE_SHAPES, kit = [false, true];
  const row = (shape, o) => ({ shape, o, out: core.smallEye(shape, o) });
  const sizes = [], squints = [], gazes = [], scales = [], others = [], hostile = [];
  for (const shape of S) for (const kitten of kit) for (const R of [3, 5, 7, 9, 11, 14, 22]) sizes.push(row(shape, { sd: kitten ? 1 : -1, R, kitten }));
  for (const shape of S) for (const kitten of kit) for (const open of [1, .8, .6, .42, .3, .22, .2, .1, 0]) squints.push(row(shape, { sd: -1, R: 9, open, kitten }));
  for (const shape of S) for (const kitten of kit) for (const [yaw, pitch] of [[0, 0], [.62, 0], [-.62, 0], [0, .5], [0, -.5], [.62, .5], [-.62, -.5], [.31, .25], [2, -2]]) gazes.push(row(shape, { sd: 1, R: 9, yaw, pitch, kitten }));
  for (const shape of S) for (const es of [0, .5, 1, 1.25, 1.5]) scales.push(row(shape, { sd: -1, R: 9, es }));
  for (const sd of [-1, 1]) for (const shape of ['wink', ...S]) others.push(row(shape, { sd, R: 9 }));
  for (const shape of ['line', 'flat', 'happy', 'closed', 'spiral', 'heart', 'star', 'bogus', '', 'PILL']) others.push(row(shape, { sd: -1, R: 9 }));
  for (const o of [{}, { R: null }, { R: 'x' }, { R: -3 }, { R: 1e9 }, { R: 9, es: -1 }, { R: 9, es: 99 }, { R: 9, open: 'x' }, { R: 9, open: -1 }, { R: 9, open: 7 }, { R: 9, yaw: 'x', pitch: null }, { R: 9, yaw: 99, pitch: -99 }, { R: 9, kitten: 'yes' }, { R: 9, kitten: 1 }, { R: 9, sd: 0 }, { R: 9, sd: '1' }]) hostile.push(row('pill', o));
  hostile.push({ shape: 'pill', o: null, out: core.smallEye('pill', null) }, { shape: 'pill', o: 7, out: core.smallEye('pill', 7) }, { shape: null, o: { R: 9 }, out: core.smallEye(null, { R: 9 }) });
  return {
    version: 1,
    note: 'sizes, squints, gazes, scales, others, hostile: smallEye(shape, o) is out. uses: usesSmallEye(shape, sd). The geometry is in px of the eye\'s own frame (centre at the origin, y down). Colours are the renderer\'s: see docs/CAT-CONTRACT.md "Small coloured eyes".',
    constants: core.SMALL_EYE,
    shapes: S,
    uses: [...S, 'wink', 'line', 'flat', 'happy', 'closed', 'spiral', 'heart', 'star', 'bogus'].flatMap(shape => [-1, 1].map(sd => ({ shape, sd, out: core.usesSmallEye(shape, sd) }))),
    sizes, squints, gazes, scales, others, hostile,
  };
};

'''
open(p, 'w', encoding='utf-8').write(s.replace(marker, snippet + marker))
PY
node scripts/gen-cat-fixtures.mjs
ls -l tests/fixtures/cat/small-eye-cases.json
```

Expected: `wrote 14 fixture files to tests/fixtures/cat` and a `small-eye-cases.json` of about 61 KB (under the 400 KB the fixtures test allows).

- [ ] **Step 9: Run the tests, then prove the fixture is additive and that no-drift covers it**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|^not ok|✓|✗"`
Expected: `# tests 228`, `# pass 228`, `# fail 0`; 14 `✓` fixture lines (`small-eye-cases.json` among them), `✓ 14 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

Run: `node scripts/check-fixtures-additive.mjs 6c14947 | tail -7`
Expected: `  + agent-cat-cases.json is new`, `  + cast-cases.json is new`, `  + display-cases.json is new`, `  + kitten-cases.json is new`, `  + small-eye-cases.json is new` and `✓ fixtures changed only by addition since 6c14947`.

Run: `git diff --stat -- tests/fixtures/cat`
Expected: no output (no existing fixture changed; the new ones are untracked).

```bash
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "closeBelow:.22,"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "closeBelow:.2,"))
PY
node scripts/gen-cat-fixtures.mjs --check 2>&1 | grep -E "✗|Fixtures drifted"
python3 - <<'PY'
p = 'design/prototype/cat-core.js'
s = open(p, encoding='utf-8').read()
was = "closeBelow:.2,"
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, "closeBelow:.22,"))
PY
node scripts/gen-cat-fixtures.mjs --check | tail -1
```

Expected: first `✗ small-eye-cases.json drifted from cat-core.js (` followed by a number of differences, and `Fixtures drifted. cat-core.js is the tie-breaker…`; after putting the line back, `✓ 14 fixture files match cat-core.js`.

- [ ] **Step 10: Commit**

Run: `git status --short`
Expected: ` M design/prototype/cat-core.js`, ` M scripts/gen-cat-fixtures.mjs`, ` M tests/cat/fixtures.test.mjs`, `?? tests/cat/smalleye.test.mjs`, `?? tests/fixtures/cat/small-eye-cases.json`.

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/cat/fixtures.test.mjs tests/cat/smalleye.test.mjs tests/fixtures/cat/small-eye-cases.json
git commit -m "feat(cat): the compact level's resting eyes are small coloured eyes, geometry in the core

smallEye gives the iris, the slit pupil, the catchlight and the rim for pill, wide, dot and tired eyes (and a wink's left eye); a kitten's
eye keeps kittenOf's ratio; a blink or squint under 0.22 closes to a line. small-eye-cases.json pins it for both apps.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 6: The prototype

**Files:**
- Modify: `design/prototype/notchmeow.html`
- One-off, not committed: `${TMPDIR:-/tmp}/b0-shots/` (the config, the port, the server's PID and log)

**Interfaces:**
- Consumes from `CatCore`: `castOf`, `cleanPair`, `assignAgentCats`, `agentCatFor`, `rerollAgentCat`, `isAgentPill`, `DISPLAY_MODES`, `kittenStep`, `kittenView`, `kittenSlots`, `kittenPlaceOf`, `usesSmallEye`, `smallEye`, `rng`; the page's own `drawCat`, `CatEngine`, `collarOf`, `bigCollar`, `group`, `fit`, `pill`.
- Produces in the page: `smallEyeDraw`; `TASKS`, `castNow`, `syncCast`; `poolEng`, `kitPreset`, `kitView`, `drawKittens`, `subStart`, `subStop`, `subAsk`; `sessionWho`, `greetPair`; `drawEyeSheet`; the Display, Main cat, pair, agents' cats and focus rows; the "Small eyes" panel. `drawCat` takes one more option, `eyes: 'ink'`, which keeps the old ink pills for the contact sheet.

What changes in the page, and what does not:
- **The compact cats' eyes** (spec §4): every cat drawn at the compact level (the notch cat, the grid, the rows, kittens, the ladder's small sizes) gets `smallEye`'s coloured eyes. The ink expression shapes are untouched.
- **The notch mock** is driven by `castOf`: five pills (Claude Code, Codex, Gemini CLI, Antigravity, Stripe), a focus row, a Display switch, a pair picker (Two cats), a row of agents' cats with dice (A cat for each agent), and kittens: Claude Code has four (working, searching, one waiting on an approval, working) and Codex two, so the "+N" and the pill kittens show; three buttons start, stop and ask for an approval. The big cat still follows the State buttons. In Two cats mode the greeting's cat 2 pops in beside the settled cat.
- **Named exceptions to "never restyle":** the "Character" row is now "Main cat" (spec §1); the Size ladder's text no longer says "ink eyes"; the expanded island is 600 by 200 (was 560 by 180) and lists the cast's pills rather than three fixed sessions, because the new rows need the room; a `data:` favicon keeps the console empty. Nothing else in the page's other panels changes.

- [ ] **Step 1: Apply the patch**

```bash
python3 - <<'PY'
# Task 6: the prototype. Run from the repository root. Every replacement asserts that its anchor is there exactly once.
p = 'design/prototype/notchmeow.html'
s = open(p, encoding='utf-8').read()

def rep(was, now):
    global s
    assert s.count(was) == 1, was[:70]
    s = s.replace(was, now)

def cut(start, end, now):
    """Replaces everything from `start` up to, but not including, `end`."""
    global s
    assert s.count(start) == 1 and s.count(end) == 1, (start[:50], end[:50])
    i, j = s.index(start), s.index(end)
    assert i < j
    s = s[:i] + now + s[j:]

# ── 1. The page: the Display rows, the Main cat label, the small-eye panel ─────────────────────────────────────
rep('<meta name="color-scheme" content="dark">', '<meta name="color-scheme" content="dark"><link rel="icon" href="data:,">')
rep('''<p class="tag">Compact island with the cat at Ø20, expanded with one cat per agent and kittens for Claude Code subagents. Click the island to expand or collapse it. Drop a file on it to feed the cat.</p>
<div class="row" id="chRow"><span class="h">Character</span></div>
<div class="row" id="nkRow"><span class="h">Island</span></div>''', '''<p class="tag">Compact island with the cat at Ø20 and expanded, in the three Display modes: one cat for everything, a cat for each agent, or the two cats side by side. Who wears which coat is decided by CatCore.castOf; the subagent kittens by CatCore.kittenStep and kittenSlots. Click the island to expand or collapse it. Drop a file on it to feed the cat.</p>
<div class="row" id="dpRow"><span class="h">Display</span></div>
<div class="row" id="chRow"><span class="h">Main cat</span></div>
<div class="row" id="pr1Row"><span class="h">Pair, cat 1</span></div>
<div class="row" id="pr2Row"><span class="h">Pair, cat 2</span></div>
<div class="row" id="acRow"><span class="h">Agents' cats</span></div>
<div class="row" id="fcRow"><span class="h">Focus</span></div>
<div class="row" id="nkRow"><span class="h">Island</span></div>''')
rep('''<p class="tag">Below Ø28 the cats switch to the compact drawing: ink eyes, no irises, stripes or whiskers, flat fills instead of gradients and smaller ears (0.8 times at Ø20 and below, easing back to full size at Ø28). Kittens keep their parent's coat with a rounder head, bigger eyes and ears, and a shorter muzzle.</p>''',
    '''<p class="tag">Below Ø28 the cats switch to the compact drawing: small coloured eyes (an iris in the coat's colours, a slit pupil, a catchlight and a thin rim; the expression shapes stay ink), no stripes or whiskers, flat fills instead of gradients and smaller ears (0.8 times at Ø20 and below, easing back to full size at Ø28). Kittens keep their parent's coat with a rounder head, bigger eyes and ears, and a shorter muzzle.</p>''')
rep('''<section class="panel" id="collarPanel">''', '''<section class="panel" id="eyePanel">
<h2>Small eyes</h2>
<p class="tag">Every coat and a kitten of it, at the compact sizes, with the ink pills they replace (left of each pair) beside the small coloured eyes (right). The first sheet is magnified 2 times, as the compact drawing at twice the size; the second is true size. Geometry: CatCore.smallEye, pinned by small-eye-cases.json.</p>
<div class="scroll"><canvas id="eyes2" aria-label="Small eyes, magnified 2 times"></canvas></div>
<div class="scroll" style="margin-top:12px"><canvas id="eyes1" aria-label="Small eyes, true size"></canvas></div>
</section>

<section class="panel" id="collarPanel">''')

# ── 2. drawCat: the compact resting eyes are small coloured eyes (o.eyes = 'ink' keeps the old ink ones, for the contact sheet) ────
rep('''  else inkEye(ctx,shape,sd,.34*R*s.es,.4*R*s.es,open,T,p.ink);''', '''  else if(o.eyes!=='ink'&&CatCore.usesSmallEye(shape,sd))smallEyeDraw(ctx,p,sd,CatCore.smallEye(shape,{sd,R,es:s.es,open,yaw:s.yaw,pitch:s.pitch,kitten:!!p.kitten}));
  else inkEye(ctx,shape,sd,.34*R*s.es,.4*R*s.es,open,T,p.ink);''')
rep('''const REAL=new Set(['pill','wide','dot','tired']);''', '''/** The small coloured eye of the compact detail level. CatCore.smallEye gives the geometry (px of the eye's own frame); the colours are the coat's: an iris gradient, the pupil colour, a catchlight and a rim in the liner colour. */
function smallEyeDraw(ctx,p,sd,G){const a0=ctx.globalAlpha;
 if(G.closed){const l=G.line;ctx.strokeStyle=p.ink;ctx.globalAlpha=a0*.9;ctx.lineWidth=l.width;ctx.lineCap='round';ctx.beginPath();ctx.moveTo(l.x0,l.y0);ctx.quadraticCurveTo(l.cx,l.cy,l.x1,l.y1);ctx.stroke();ctx.globalAlpha=a0;return}
 const I=G.iris,P=G.pupil,Lt=G.light,ir=(sd>0&&p.irisR)||p.iris,g=ctx.createRadialGradient(0,0,0,0,0,I.r);g.addColorStop(0,ir[0]);g.addColorStop(1,ir[1]);
 ctx.fillStyle=g;ctx.beginPath();ctx.ellipse(0,0,I.rx,I.ry,0,0,TAU);ctx.fill();
 ctx.fillStyle='#0E0B09';ctx.beginPath();ctx.ellipse(P.x,P.y,P.rx,P.ry,0,0,TAU);ctx.fill();
 ctx.fillStyle='rgba(255,255,255,.92)';ctx.beginPath();ctx.arc(Lt.x,Lt.y,Lt.r,0,TAU);ctx.fill();
 ctx.strokeStyle=p.liner;ctx.lineWidth=G.rim;ctx.beginPath();ctx.ellipse(0,0,I.rx,I.ry,0,0,TAU);ctx.stroke()}
const REAL=new Set(['pill','wide','dot','tired']);''')

# ── 3. The notch mock-up: the cast, the pool of small engines, the kittens ───────────────────────────────────────
rep('const EXP={W:560,H:180};', 'const EXP={W:600,H:200};')
cut('const kitP=kittenOf(PRESETS.shrimpy);\n', 'const ISL={exp:0', r'''// ── Display modes: who wears which coat comes from CatCore.castOf ────────────────────────────────────────────────
// The pills of the mock-up, in the order the island lists them (Claude Code, the agents, then the integrations); `last` is the time of the pill's last event.
// Nothing here decides a coat: castOf says it, from the Display mode, the focus, the Main cat (CHAR), the pair and the agents' coats.
let MODE='one',PAIR=CatCore.cleanPair(null),FOCUS='integration_claude',AGENT_CATS={},secondEng=null;
const TASKS=[
 {id:'integration_claude',name:'Claude Code',col:AGENT_COL['Claude Code'],sub:'notchmeow · editing engine.ts',state:'working',last:100},
 {id:'agent_codex',name:'Codex',col:AGENT_COL['Codex'],sub:'api-server · wants to run npm test',state:'approval',last:90},
 {id:'agent_gemini',name:'Gemini CLI',col:AGENT_COL['Gemini CLI'],sub:'docs · done in 42 s',state:'finished',last:80},
 {id:'agent_antigravity',name:'Antigravity',col:AGENT_COL['Antigravity'],sub:'site · thinking',state:'thinking',last:70},
 {id:'integration_stripe',name:'Stripe',col:AGENT_COL['Stripe (dark)'],sub:'3 payments today',state:'idle',last:5}];
const TASK=Object.fromEntries(TASKS.map(t=>[t.id,t]));
// The first time an agent is seen it gets a coat that no other agent and not the Main cat uses. The page seeds the roll, so a screenshot repeats; the dice use Math.random.
AGENT_CATS=CatCore.assignAgentCats(TASKS.map(t=>t.id),AGENT_CATS,CHAR,CatCore.rng(2026));
const castNow=()=>CatCore.castOf(MODE,{tasks:TASKS,focusId:FOCUS,mainCat:CHAR,pair:PAIR,agentCats:AGENT_CATS});
// The small cats of the mock-up (rows, grid cells, kittens, the second cat of the greeting): one engine per (place, pill, coat), made when it is first drawn and updated only while it is drawn.
const POOL=new Map(),KITP={};let POOLN=0;
function poolEng(key,preset,state){let e=POOL.get(key);if(!e){e=new CatEngine(preset,{mini:true,state});POOL.set(key,e)}e._used=POOLN;if(e.state!==state)e.setState(state);return e}
const kitPreset=cat=>KITP[cat]||(KITP[cat]=kittenOf(PRESETS[cat]));
// Kittens: one list per pill, changed only by CatCore.kittenStep. A kitten that is leaving goes by itself: kittenView hides it from its `until`, with no timer.
const KIT={};let kitSeq=0;
const kitEvent=(pill,ev)=>{KIT[pill]=CatCore.kittenStep(KIT[pill]||[],{t:ms(),...ev})};
const kitView=pill=>CatCore.kittenView(KIT[pill]||[],ms());
const kitTarget=()=>CatCore.isAgentPill(FOCUS)?FOCUS:'integration_claude';
function subStart(){kitEvent(kitTarget(),{type:'start',id:'sub'+(++kitSeq),agentType:'Explore'})}
function subStop(){const l=(KIT[kitTarget()]||[]).filter(k=>k.state!=='leaving').sort((a,b)=>b.born-a.born)[0];if(l)kitEvent(kitTarget(),{type:'stop',id:l.id})}
function subAsk(){const l=KIT[kitTarget()]||[],w=l.find(k=>k.state==='approval');if(w)kitEvent(kitTarget(),{type:'resolved',id:w.id});else{const n=l.filter(k=>k.state!=='leaving').sort((a,b)=>b.born-a.born)[0];if(n)kitEvent(kitTarget(),{type:'permission',id:n.id})}}
for(const [pill,evs] of [['integration_claude',[{type:'start',id:'a1',agentType:'Explore'},{type:'start',id:'a2',agentType:'Explore'},{type:'start',id:'a3',agentType:'general-purpose'},{type:'start',id:'a4',agentType:'Explore'},{type:'tool',id:'a2',tool:'Grep'},{type:'permission',id:'a3'}]],['agent_codex',[{type:'start',id:'c1'},{type:'start',id:'c2'},{type:'permission',id:'c2'}]]])for(const ev of evs)kitEvent(pill,ev);
/** Keeps the two big engines on the coats the cast names (a coat change makes a new engine, as picking a Main cat always did). */
function syncCast(C){if(notchEng.p.name!==C.big.cat)notchEng=new CatEngine(PRESETS[C.big.cat],{state:curState});
 if(C.second){const st=C.second.pill?TASK[C.second.pill].state:'idle';if(!secondEng||secondEng.p.name!==C.second.cat)secondEng=new CatEngine(PRESETS[C.second.cat],{state:st});else if(secondEng.state!==st)secondEng.setState(st)}}
''')

# ── 4. The session cats of the grid, the kittens and the island: all from the cast ──────────────────────────────
cut("// The session cats of the compact island, in the order of the grid's cells", '// The launch greeting (Greeting v2):', r'''// The session cats of the compact island, in the order of the grid's cells (top left, top right, bottom left, bottom right): the cats of the cast's pills, and the Main cat
// for a cell with no pill. CatCore.miniSlots places them (a row, the glide, the grid the apps show).
function sessionWho(){const C=castNow();return[0,1,2,3].map(i=>{const P=C.pills[i];return P?{e:poolEng('grid:'+P.pill+':'+P.cat,PRESETS[P.cat],TASK[P.pill].state),col:TASK[P.pill].col}:{e:poolEng('grid:free'+i+':'+C.greeting.sessions[i],PRESETS[C.greeting.sessions[i]],'idle'),col:'#8d9098'}})}
function drawSessionMinis(ctx,cx,k,slots,alpha){if(alpha<=.01)return;const who=sessionWho();ctx.save();ctx.globalAlpha=alpha;
 slots.forEach((s,i)=>{if(s.d<=0)return;drawCat(ctx,who[i].e,cx+(s.x-320)*k,s.y*k,s.d*k,{tint:TINTON,badge:false,collar:collarOf(who[i].col)})});ctx.restore()}
/** In Two cats mode the pair arrives together: cat 2 pops in beside the cat that has settled, as the island folds. */
function greetPair(ctx,t,X,Y,D){const G=castNow().greeting;if(!G.pair||t<=GT.leave)return;const pop=EZ.back(seg(t,GT.leave+.24,GT.leave+.42));if(pop<=.02)return;
 drawCat(ctx,poolEng('greet2:'+G.pair[1],PRESETS[G.pair[1]],'idle'),X+D*1.2,Y,D*pop,{tint:TINTON,badge:false})}
/** One parent's kittens in one place: CatCore.kittenSlots gives the slots in units of `unit` px from (ox, oy). Returns the slots. */
function drawKittens(ctx,place,pill,parentCat,col,ox,oy,unit,alpha,list){const sl=CatCore.kittenSlots(place,list||kitView(pill));if(alpha<=.01)return sl;ctx.save();ctx.globalAlpha=alpha;
 for(const q of sl.shown)drawCat(ctx,poolEng(`kit:${pill}:${q.id}:${parentCat}`,kitPreset(parentCat),q.state==='leaving'?'finished':q.state),ox+q.x*unit,oy+q.y*unit,q.d*unit,{tint:TINTON,collar:collarOf(col)});
 const lab=(text,m)=>{const sz=Math.max(8,m.size*unit);ctx.font=`700 ${sz}px system-ui,sans-serif`;const w=ctx.measureText(text).width+sz*.6,x=ox+m.x*unit,y=oy+m.y*unit;ctx.fillStyle='#2a2c31';rr(ctx,x-w/2,y-sz*.65,w,sz*1.3,sz*.65);ctx.fill();ctx.fillStyle='#cfd0d4';ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillText(text,x,y+.5)};
 if(sl.moreAt)lab('+'+sl.more,sl.moreAt);if(sl.label)lab(sl.label.text,sl.label);
 ctx.restore();return sl}

function drawDesk(){const [ctx,W,H]=fit(desk),k=Math.min(1,(W-24)/640),cx=W/2,r=desk.getBoundingClientRect();
 POOLN++;const C=castNow();syncCast(C);
 drawMenubar(ctx,W,k);
 if(ISL.greet>=0){const t=(ms()-ISL.greet)/1000;if(t>GREET_END){ISL.greet=-1;ISL.exp=ISL.from=ISL.to=0}else{drawGreeting(ctx,t,cx,k,greetEng);return}}
 const ke=seg(ms(),ISL.t0,ISL.t0+(ISL.to>ISL.from?420:340)),e=ISL.exp=lerp(ISL.from,ISL.to,ISL.to>ISL.from?EZ.back(ke):EZ.inOut(ke)),iw=lerp(COMPACT,EXP.W,e)*k,ih=lerp(32,EXP.H,e)*k,x0=cx-iw/2;
 ctx.fillStyle='#000';islandPath(ctx,cx,iw,ih,k);ctx.fill();
 ctx.save();islandPath(ctx,cx,iw,ih,k);ctx.clip();
 const two=!!C.second,ee=clamp(e,0,1.1),D=lerp(20,two?58:64,ee)*k,D2=lerp(20,46,ee)*k,n1x=x0+(two?lerp(30,56,e):lerp(40,74,e))*k,n2x=x0+lerp(54,114,e)*k,ncy=lerp(16,98,e)*k,n2y=lerp(16,106,e)*k,bigPill=C.big.pill&&TASK[C.big.pill];
 look(notchEng,r);drawCat(ctx,notchEng,n1x,ncy,D,{tint:TINTON,fur:FUR,glow:e>.5,badgeSide:e<.5?-1:1,collar:bigCollar(notchEng),earCeiling:0});
 if(two){look(secondEng,r);drawCat(ctx,secondEng,n2x,n2y,D2,{tint:TINTON,glow:e>.5,badgeSide:e<.5?-1:1,collar:C.second.pill?collarOf(TASK[C.second.pill].col):null,earCeiling:0})}
 // Kittens, beside their parent wherever it is drawn (compact: tucked beside the cat, or only a count by the pair; expanded: under it).
 const ca=1-seg(e,0,.25),ea=seg(e,.55,1),place=CatCore.kittenPlaceOf(MODE,false),placeX=CatCore.kittenPlaceOf(MODE,true);
 if(place==='pairCompact'){drawKittens(ctx,place,C.big.pill,C.big.cat,'#fff',n2x,n2y,D2,ca,[...kitView(C.big.pill),...(C.second.pill?kitView(C.second.pill):[])])}
 else if(C.big.pill)drawKittens(ctx,place,C.big.pill,C.big.cat,bigPill.col,n1x,ncy,D,ca);
 if(C.big.pill)drawKittens(ctx,placeX,C.big.pill,C.big.cat,bigPill.col,n1x,ncy,D,ea);
 if(two&&C.second.pill)drawKittens(ctx,placeX,C.second.pill,C.second.cat,TASK[C.second.pill].col,n2x,n2y,D2,ea);
 drawSessionMinis(ctx,cx,k,CatCore.miniSlots(1,{grid:1,four:1},{W:iw/k,H:32}),1-seg(e,0,.25));
 const a=ea;
 if(a>.01){ctx.globalAlpha=a;const lx=x0+176*k,rxx=x0+iw-16*k;
  ctx.fillStyle='#fff';ctx.font=`600 ${13*k}px system-ui,sans-serif`;ctx.textAlign='left';ctx.textBaseline='middle';ctx.fillText(bigPill?bigPill.name:'Nothing in focus',lx,24*k);
  ctx.fillStyle='#8d9098';ctx.font=`${11*k}px system-ui,sans-serif`;ctx.fillText(bigPill?bigPill.sub:'',lx,40*k);
  if(two&&C.second.pill){const T2=TASK[C.second.pill];ctx.fillStyle=COL[T2.state];ctx.fillText(`${T2.name} · ${STATE_TXT[T2.state]}`,lx,55*k)}
  else if(two){ctx.fillStyle='#8d9098';ctx.fillText('No other agent',lx,55*k)}
  ctx.textAlign='right';ctx.fillStyle='#8d9098';ctx.fillText(`Display: ${MODE_LABEL[MODE]}`,rxx,24*k);
  C.pills.forEach((P,i)=>{const T=TASK[P.pill],y=(86+i*30)*k,H=28*k;drawCat(ctx,poolEng('row:'+P.pill+':'+P.cat,PRESETS[P.cat],T.state),lx+12*k,y,22*k,{tint:TINTON,collar:collarOf(T.col)});
   ctx.textAlign='left';ctx.fillStyle='#fff';ctx.font=`600 ${12.5*k}px system-ui,sans-serif`;ctx.fillText(T.name,lx+34*k,y-7*k);
   ctx.fillStyle='#8d9098';ctx.font=`${11*k}px system-ui,sans-serif`;ctx.fillText(T.sub,lx+34*k,y+8*k);
   const sl=CatCore.kittenSlots('pill',kitView(P.pill)),last=sl.shown[sl.shown.length-1],kw=last?(-last.x+last.d/2+.2)*H:0;
   pill(ctx,rxx-kw,y,STATE_TXT[T.state],COL[T.state],k);
   if(last)drawKittens(ctx,'pill',P.pill,P.cat,T.col,rxx,y,H,1)});
  ctx.globalAlpha=1}
 ctx.restore();drawFlights(ctx,deskFlights)}
const MODE_LABEL={one:'one cat',perAgent:'a cat for each agent',two:'two cats'};

''')

# ── 5. The greeting: in Two cats mode the pair arrives together ──────────────────────────────────────────────────
rep('drawSessionMinis(ctx,cx,k,CatCore.miniSlots(P.minis,CatCore.miniGlide(t),{W:COMPACT,H:32}),1);ctx.restore()}',
    'drawSessionMinis(ctx,cx,k,CatCore.miniSlots(P.minis,CatCore.miniGlide(t),{W:COMPACT,H:32}),1);greetPair(ctx,t,X,Y,D);ctx.restore()}')

# ── 6. Controls: the engines the page updates, the Main cat, the Display rows ────────────────────────────────────
rep('''const allMain=()=>[...stage.map(S=>S.e),notchEng,...LROWS.flatMap(r=>r.cats.map(c=>c.e))];
const everyone=()=>[...allMain(),...SESS.flatMap(S=>[S.e,...S.kits])];''', '''const allMain=()=>[...stage.map(S=>S.e),notchEng,...(secondEng?[secondEng]:[]),...LROWS.flatMap(r=>r.cats.map(c=>c.e))];
const everyone=()=>[...allMain(),...[...POOL.values()].filter(e=>e._used>=POOLN-1)];''')
rep("v=>{CHAR=v;notchEng=new CatEngine(PRESETS[v],{state:curState})});", "v=>{CHAR=v});")
rep("[['Play greeting',playGreeting],['Expand / collapse',()=>setExpanded(ISL.to<.5)]]", "[['Play greeting',playGreeting],['Expand / collapse',()=>setExpanded(ISL.to<.5)],['Subagent starts',subStart],['Subagent stops',subStop],['Subagent asks',subAsk]]")
rep('// ── Frame loop ───', r'''// ── Display: the mode, the pair, the agents' coats, the focus ──────────────────────────────────────────────────────
const syncDisplay=group('dpRow',CatCore.DISPLAY_MODES.map(m=>[m,MODE_LABEL[m][0].toUpperCase()+MODE_LABEL[m].slice(1)]),()=>MODE,v=>{MODE=v;showRows()});
function showRows(){document.getElementById('pr1Row').style.display=document.getElementById('pr2Row').style.display=MODE==='two'?'':'none';document.getElementById('acRow').style.display=MODE==='perAgent'?'':'none'}
const syncPair=[0,1].map(i=>group('pr'+(i+1)+'Row',ALLCATS.map(n=>[n,PRESETS[n].label]),()=>PAIR[i],v=>{const q=[...PAIR];q[i]=v;PAIR=CatCore.cleanPair(q);syncPair.forEach(f=>f())}));
group('fcRow',[...TASKS.map(t=>[t.id,t.name]),[null,'None']],()=>FOCUS,v=>{FOCUS=v});
/** One button per agent: its cat, and a dice that rolls a new random one (never the current coat, never another agent's or the Main cat's while a free coat is left). */
function renderAgents(){const row=document.getElementById('acRow');row.querySelectorAll('button').forEach(b=>b.remove());
 for(const T of TASKS.filter(t=>CatCore.isAgentPill(t.id))){const b=document.createElement('button');b.textContent=`${T.name}: ${PRESETS[CatCore.agentCatFor(T.id,AGENT_CATS,CHAR,Math.random).cat].label} \u{1F3B2}`;b.title='Roll a new random cat';b.onclick=()=>{AGENT_CATS=CatCore.rerollAgentCat(T.id,AGENT_CATS,CHAR,Math.random).agentCats;renderAgents()};row.appendChild(b)}
 const r=document.createElement('button');r.textContent='Reset to defaults';r.style.marginLeft='12px';r.onclick=()=>{AGENT_CATS=CatCore.assignAgentCats(TASKS.map(t=>t.id),{},CHAR,Math.random);renderAgents()};row.appendChild(r)}
renderAgents();showRows();

// ── Small eyes: every coat and a kitten of it, ink pills beside the coloured eyes ─────────────────────────────────────
const EYE_COLS=[{d:12},{d:16},{d:20},{d:24},{d:12,kit:1},{d:16,kit:1},{d:20,kit:1}],EYE_LEFT=74,EYE_HEAD=36,EYE_ENG=new Map();
function eyeEng(n,kit){const key=n+(kit?':k':'');let e=EYE_ENG.get(key);if(!e){e=new CatEngine(kit?kittenOf(PRESETS[n]):PRESETS[n],{quiet:true,state:'idle'});EYE_ENG.set(key,e)}return e}
/** scale 1 is true size; scale 2 draws each cat at twice the head width with the compact drawing forced, so the sheet is the compact cat magnified. */
function drawEyeSheet(cv,scale){const colW=EYE_COLS.map(z=>Math.max(80,z.d*scale*2+34)),rowH=Math.max(34,24*scale+10),W=EYE_LEFT+colW.reduce((a,b)=>a+b,0)+8,H=EYE_HEAD+ALLCATS.length*rowH+6;
 cv.style.width=W+'px';cv.style.height=H+'px';const [ctx]=fit(cv,W,H);
 ctx.fillStyle='#000';ctx.fillRect(0,0,W,H);ctx.textBaseline='alphabetic';ctx.textAlign='center';
 let x=EYE_LEFT;EYE_COLS.forEach((z,i)=>{const w=colW[i];ctx.fillStyle='#ececee';ctx.font='600 11px system-ui,sans-serif';ctx.fillText(`${z.kit?'kitten ':''}Ø${z.d}`,x+w/2,15);
  ctx.fillStyle='#9a9ca3';ctx.font='10px system-ui,sans-serif';ctx.fillText('ink · coloured',x+w/2,29);ctx.strokeStyle='#2a2c31';ctx.beginPath();ctx.moveTo(x+.5,6);ctx.lineTo(x+.5,H-6);ctx.stroke();x+=w});
 ALLCATS.forEach((n,ri)=>{const cy=EYE_HEAD+ri*rowH+rowH/2;ctx.fillStyle='#ececee';ctx.font='11px system-ui,sans-serif';ctx.textAlign='left';ctx.fillText(PRESETS[n].label,10,cy+4);
  let cx0=EYE_LEFT;EYE_COLS.forEach((z,i)=>{const w=colW[i],e=eyeEng(n,z.kit);for(const [fx,ink] of [[.27,true],[.73,false]])drawCat(ctx,e,cx0+w*fx,cy,z.d*scale,{tint:false,badge:false,detail:'compact',eyes:ink?'ink':undefined});cx0+=w})})}
function drawEyeSheets(){drawEyeSheet(document.getElementById('eyes2'),2);drawEyeSheet(document.getElementById('eyes1'),1)}
drawEyeSheets();addEventListener('resize',drawEyeSheets);

// ── Frame loop ───''')
open(p, 'w', encoding='utf-8').write(s)
PY
git diff --stat design/prototype/notchmeow.html
```

Expected: `1 file changed, 123 insertions(+), 31 deletions(-)`.

- [ ] **Step 2: Serve the page and load it in a headless browser**

`playwright-cli` drives the browsers that are already cached (nothing is downloaded). The server listens on `127.0.0.1` only.

```bash
SHOTS="${TMPDIR:-/tmp}/b0-shots"; mkdir -p "$SHOTS"
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
echo "$PORT" > "$SHOTS/port"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory design/prototype > "$SHOTS/server.log" 2>&1 &
echo $! > "$SHOTS/server.pid"
cat > "$SHOTS/pw-config.json" <<'EOF'
{ "browser": { "contextOptions": { "viewport": { "width": 1280, "height": 900 }, "deviceScaleFactor": 2 } } }
EOF
sleep 1
curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:$PORT/notchmeow.html"
cd "$SHOTS" && playwright-cli open "http://127.0.0.1:$PORT/notchmeow.html" --config=pw-config.json | grep -E "Page Title|Console"
playwright-cli console | head -2
playwright-cli --raw eval "document.title"
playwright-cli --raw eval "[...document.querySelectorAll('h2')].map(h => h.textContent).join(' | ')"
playwright-cli --raw eval "document.querySelectorAll('canvas').length"
```

Expected: `200`, `- Page Title: NotchMeow prototype` (and no `Console:` line with errors), `Total messages: 0 (Errors: 0, Warnings: 0)`, `"NotchMeow prototype"`, `"Cats | Personality | More cats | In the notch | Greeting | Size ladder | Small eyes | Collar"` and `21` (the 19 canvases the page had, plus the two small-eye sheets).

- [ ] **Step 3: Click through the Display switch**

The page's globals are reachable from `playwright-cli eval`. Each line is the cast for the mode just clicked; the focus buttons are scoped to their row because the Collar panel has buttons with the same names.

```bash
cd "${TMPDIR:-/tmp}/b0-shots"
for mode in "A cat for each agent" "Two cats" "One cat"; do
  playwright-cli click "getByRole('button', { name: '$mode' })" > /dev/null
  playwright-cli --raw eval "JSON.stringify({mode: MODE, big: castNow().big, second: castNow().second, row: castNow().pills.map(p => p.pill + ':' + p.cat).join(' ')})"
done
playwright-cli click "getByRole('button', { name: 'A cat for each agent' })" > /dev/null
playwright-cli click "locator('#fcRow').getByRole('button', { name: 'Gemini CLI' })" > /dev/null
playwright-cli --raw eval "JSON.stringify({focus: FOCUS, big: castNow().big, row: castNow().pills.map(p => p.pill).join(' ')})"
playwright-cli click "locator('#fcRow').getByRole('button', { name: 'Claude Code' })" > /dev/null
playwright-cli --raw eval "FOCUS"
playwright-cli console | head -2
```

Expected: five lines and then `Total messages: 0 (Errors: 0, Warnings: 0)`. `--raw` prints the string the page returns as quoted JSON, so the quotes inside are escaped. The coats of the two agents that have no default come from the page's seeded roll, so they are the same every time:
- `"{\"mode\":\"perAgent\",\"big\":{\"pill\":\"integration_claude\",\"cat\":\"shrimpy\"},\"second\":null,\"row\":\"agent_codex:momo agent_gemini:mocha agent_antigravity:latte integration_stripe:shrimpy\"}"`
- `"{\"mode\":\"two\",\"big\":{\"pill\":\"integration_claude\",\"cat\":\"shrimpy\"},\"second\":{\"pill\":\"agent_codex\",\"cat\":\"momo\"},\"row\":\"agent_gemini:shrimpy agent_antigravity:shrimpy integration_stripe:shrimpy\"}"`
- `"{\"mode\":\"one\",\"big\":{\"pill\":\"integration_claude\",\"cat\":\"shrimpy\"},\"second\":null,\"row\":\"agent_codex:shrimpy agent_gemini:shrimpy agent_antigravity:shrimpy integration_stripe:shrimpy\"}"`
- `"{\"focus\":\"agent_gemini\",\"big\":{\"pill\":\"agent_gemini\",\"cat\":\"mocha\"},\"row\":\"integration_claude agent_codex agent_antigravity integration_stripe\"}"`
- `"integration_claude"`

- [ ] **Step 4: Kittens, the dice and a greeting**

```bash
cd "${TMPDIR:-/tmp}/b0-shots"
q() { playwright-cli --raw eval "$1"; }
q "kitView('integration_claude').map(k => k.state).join()"
playwright-cli click "getByRole('button', { name: 'Subagent starts' })" > /dev/null
q "kitView('integration_claude').length"
playwright-cli click "getByRole('button', { name: 'Subagent stops' })" > /dev/null
sleep 1
q "kitView('integration_claude').length + ' drawn, ' + KIT.integration_claude.length + ' kept'"
playwright-cli click "getByRole('button', { name: 'Subagent asks' })" > /dev/null
q "kitView('integration_claude').length + ' drawn, ' + KIT.integration_claude.length + ' kept'"
playwright-cli click "getByRole('button', { name: 'A cat for each agent' })" > /dev/null
q "AGENT_CATS.agent_gemini + ' ' + AGENT_CATS.agent_antigravity"
playwright-cli click "getByRole('button', { name: /Gemini CLI: .*/ })" > /dev/null
q "AGENT_CATS.agent_gemini !== undefined && AGENT_CATS.agent_gemini !== 'shrimpy' && AGENT_CATS.agent_gemini !== 'momo'"
q "JSON.stringify(CatCore.smallEye('pill', {sd: -1, R: 10}).iris)"
playwright-cli click "getByRole('button', { name: 'Two cats' })" > /dev/null
q "playGreeting()"
sleep 7
playwright-cli console | head -2
```

Expected: `"approval,working,searching,working"` (Claude Code's four kittens: the one waiting on an approval first), `5` (a new one), `"4 drawn, 5 kept"` (the stopped one has had its 0.6 s and is no longer drawn; the list still holds it, because nothing has touched the list since), `"4 drawn, 4 kept"` (the next event dropped it), `"mocha latte"` (the seeded coats of Gemini CLI and Antigravity), `true` (the dice gave Gemini CLI a coat that is not Shrimpy or Momo), `"{\"rx\":2.1,\"ry\":2.3000000000000003,\"r\":2.3000000000000003}"` (`smallEye`'s iris at R = 10), `undefined` (`playGreeting()` returns nothing) and `Total messages: 0 (Errors: 0, Warnings: 0)` after the greeting has played for 6.5 s in Two cats mode.

- [ ] **Step 5: Stop the browser and the server**

```bash
cd "${TMPDIR:-/tmp}/b0-shots"
playwright-cli close
kill "$(cat server.pid)"
sleep 1
curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:$(cat port)/notchmeow.html" || true
```

Expected: `000` (nothing is listening any more).

- [ ] **Step 6: Run the contract once more and commit**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✗"`
Expected: `# tests 228`, `# pass 228`, `# fail 0` (the page has no tests of its own).

Run: `git status --short`
Expected: ` M design/prototype/notchmeow.html` and nothing else (the screenshots' folder is outside the repository).

```bash
git add design/prototype/notchmeow.html
git commit -m "feat(prototype): the Display modes, subagent kittens and small coloured eyes

A Display switch whose notch mock is driven by castOf (One cat, A cat for each agent, Two cats), kittens beside their parent from
kittenStep and kittenSlots, the coloured small eyes from smallEye in every compact cat, and a contact sheet of every coat and a kitten
of it at Ø12 to Ø24, at 1 and 2 times, next to the ink pills.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Owner checkpoint: screenshots

**Files:**
- Create (outside the repository, never committed): `${TMPDIR:-/tmp}/b0-shots/display-one-compact.png`, `display-one-expanded.png`, `display-perAgent-compact.png`, `display-perAgent-expanded.png`, `display-two-compact.png`, `display-two-expanded.png`, `small-eyes-2x.png`, `small-eyes-1x.png`

**Interfaces:**
- Consumes: the page from Task 6, and `playwright-cli` with its cached browsers. Produces: eight PNGs at a device scale of 2, and a stop.

The owner looks at these before anything is built on them: the three Display modes in the compact and the expanded island (each with kittens beside Claude Code, and Codex's in its pill or as cat 2), and the small-eye sheet (all 16 coats and a kitten of each at Ø12 to Ø24, ink pills left and coloured eyes right, magnified 2 times and at true size).

- [ ] **Step 1: Serve the page and take the screenshots**

```bash
SHOTS="${TMPDIR:-/tmp}/b0-shots"; mkdir -p "$SHOTS"
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
echo "$PORT" > "$SHOTS/port"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory design/prototype > "$SHOTS/server.log" 2>&1 &
echo $! > "$SHOTS/server.pid"
cat > "$SHOTS/pw-config.json" <<'EOF'
{ "browser": { "contextOptions": { "viewport": { "width": 1280, "height": 900 }, "deviceScaleFactor": 2 } } }
EOF
sleep 1
cd "$SHOTS" && playwright-cli open "http://127.0.0.1:$PORT/notchmeow.html" --config=pw-config.json > /dev/null
playwright-cli eval "document.getElementById('desk').scrollIntoView({block: 'center'})" > /dev/null
for pair in "one:One cat" "perAgent:A cat for each agent" "two:Two cats"; do
  id="${pair%%:*}"; name="${pair#*:}"
  playwright-cli click "getByRole('button', { name: '$name' })" > /dev/null
  playwright-cli eval "setExpanded(false)" > /dev/null; sleep 1
  playwright-cli screenshot "#desk" --filename="display-$id-compact.png" > /dev/null
  playwright-cli eval "setExpanded(true)" > /dev/null; sleep 1.5
  playwright-cli screenshot "#desk" --filename="display-$id-expanded.png" > /dev/null
done
playwright-cli eval "setExpanded(false)" > /dev/null
playwright-cli screenshot "#eyes2" --filename=small-eyes-2x.png > /dev/null
playwright-cli screenshot "#eyes1" --filename=small-eyes-1x.png > /dev/null
playwright-cli console | head -2
ls -1 "$SHOTS"/*.png
```

Expected: `Total messages: 0 (Errors: 0, Warnings: 0)` and the eight file names above, each with the `b0-shots` path in front.

- [ ] **Step 2: Look at them**

Open each PNG (the `Read` tool shows an image) and check, in this order, before reporting:
1. `display-one-compact.png`: one Shrimpy at the left of the notch, two small kittens beside it with a "+2" above them, the four grid cats on the right, all Shrimpy.
2. `display-one-expanded.png`: Shrimpy big on the left with three kittens under it and "+1"; Claude Code's name and line on top; Codex, Gemini CLI, Antigravity and Stripe below, all in Shrimpy, Codex with two kittens at the end of its pill.
3. `display-perAgent-*.png`: the same, but Codex is Momo (black and white), Gemini CLI and Antigravity wear their own random coats, and Stripe is Shrimpy; the big cat is Shrimpy because Claude Code is focused.
4. `display-two-*.png`: Shrimpy and Momo side by side (Momo is Codex, "needs approval", and has left the row), the kittens in a row under each cat, and a "×6" count by the pair in the compact notch.
5. `small-eyes-2x.png` and `small-eyes-1x.png`: for each coat, the ink pills left and the coloured eyes right at Ø12, Ø16, Ø20, Ø24 and a kitten at Ø12, Ø16, Ø20. Shrimpy's eyes are green and Momo's gold at every size.

If something is wrong (an overlap, a wrong coat, an eye outside its iris), say what and where in the report; do not fix numbers in the core on your own.

- [ ] **Step 3: Stop the browser and the server, and stop the plan here**

```bash
cd "${TMPDIR:-/tmp}/b0-shots"
playwright-cli close
kill "$(cat server.pid)"
sleep 1
curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:$(cat port)/notchmeow.html" || true
```

Expected: `000`.

**Stop here and report to the main session:** the folder `${TMPDIR:-/tmp}/b0-shots` with the eight file names, a line on what each shows and anything that looks wrong. The main session shows the owner. **Task 8 starts only when the main session says go.** If the owner wants other numbers (the eye sizes in `SMALL_EYE`, the kitten slots in `KITTEN_PLACES`), the change is one edit in `cat-core.js`, a regenerate and a re-run of the affected self-checks, made by the main session or by a fix task, before Task 8 documents them.

---

### Task 8: Docs and the final checks

**Files:**
- Modify: `docs/CAT-CONTRACT.md`, `CLAUDE.md`, `ARCHITECT.md`, `docs/superpowers/specs/2026-10-08-display-modes-kittens-design.md`

**Interfaces:**
- Consumes: Tasks 1 to 7 and the owner's approval at the checkpoint. Produces: the docs the app plans cite.

- [ ] **Step 1: Write the docs**

The contract doc gains three rows of the API table, five rows of the fixture table, a section "Display modes, agent coats, kittens and small eyes" before "The harness", and six decisions. `CLAUDE.md` and `ARCHITECT.md` get one pointer each. The spec gets three small edits so that it says what the contract does: the Display settings have a clean-up of their own, because new fields on `cleanCatSettings` would have changed `settings-cases.json` (the owner's answer to question 1 below). If the owner's notes at the checkpoint changed a number, change the same number in the section's text before running this.

`````bash
python3 - <<'PY'
# Task 8: the docs. Run from the repository root. Every replacement asserts that its anchor is there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

# ── docs/CAT-CONTRACT.md ──────────────────────────────────────────────────────────────────────────────────────
p = 'docs/CAT-CONTRACT.md'
s = open(p, encoding='utf-8').read()

# 1. The public surface: three more groups, after "Stored settings".
anchor = '| Stored settings | '
assert s.count(anchor) == 1
i = s.index(anchor); j = s.index('\n', i)
rows = '''
| Display modes (B-0) | `DISPLAY_MODES`, `displayModeOf`, `DEFAULT_PAIR`, `DEFAULT_AGENT_CATS`, `MAX_AGENT_CATS`, `PILL_ID`, `isPillId`, `isAgentPill`, `defaultAgentCat`, `cleanPair`, `cleanAgentCats`, `cleanDisplaySettings`, `defaultDisplaySettings`, `pickCat`, `agentCatFor`, `rerollAgentCat`, `assignAgentCats`, `PILL_ROW`, `busyRank`, `castOf` |
| Kittens (B-0) | `KITTEN_MAX`, `KITTEN_LEAVE_MS`, `KITTEN_STATES`, `cleanKittens`, `kittenStep`, `kittenOrder`, `kittenView`, `KITTEN_PLACES`, `kittenPlaceOf`, `kittenSlots` |
| Small eyes (B-0) | `SMALL_EYE_SHAPES`, `SMALL_EYE`, `usesSmallEye`, `smallEye` |'''
s = s[:j] + rows + s[j:]

# 2. The fixture table: five more rows, after settings-cases.json.
anchor = '| `settings-cases.json` | '
assert s.count(anchor) == 1
i = s.index(anchor); j = s.index('\n', i)
rows = '''
| `display-cases.json` | `ids`, `modes`, `defaultPair`, `defaultAgentCats`, `maxAgentCats`, `pillIdPattern`, `defaults`, `cases` (raw Display settings to clean ones), `pairs` (a stored pair, an array or JSON text, to two cats), `agentCats` (a stored map to a clean one), `pillIds` (`isPillId`, `isAgentPill`, `defaultAgentCat`). See "Display modes". |
| `agent-cat-cases.json` | `ids`, `defaults`, `cases` (`agentCatFor`), `rerolls` (`rerollAgentCat`), `assigns` (`assignAgentCats`). Each row names its random source and says how many numbers the call drew. |
| `cast-cases.json` | `ids`, `modes`, `pillRow`, `states`, `busyRank`, `cases` (`castOf`: every scenario, ranking and hostile input once per mode). |
| `kitten-cases.json` | `limits`, `states`, `places` (`KITTEN_PLACES`), `scripts` (`kittenStep` over events, the whole list after each), `order`, `views`, `cleans`, `slots` (`kittenSlots`), `placeOf`. See "Kittens". |
| `small-eye-cases.json` | `constants` (`SMALL_EYE`), `shapes`, `uses` (`usesSmallEye`), `sizes`, `squints`, `gazes`, `scales`, `others`, `hostile` (`smallEye`). See "Small coloured eyes". |'''
s = s[:j] + rows + s[j:]

# 3. The new sections, before "The harness".
anchor = '\n## The harness\n'
assert s.count(anchor) == 1
section = r'''
## Display modes, agent coats, kittens and small eyes (B-0)

Sub-project B (`docs/superpowers/specs/2026-10-08-display-modes-kittens-design.md`) adds four sets of pure rules to the core, each pinned by fixtures. All of it is new names and new files: no existing function, constant or fixture line changed (`node scripts/check-fixtures-additive.mjs 6c14947` proves the fixtures). The prototype page draws all of it (the Display switch, the kittens, the small-eye sheet), so the page is the look and the core is the numbers.

### Display settings

Settings → Cat → Display saves a mode, a pair of cats and the agents' coats. They go through `cleanDisplaySettings`, a function of its own: adding the fields to `cleanCatSettings` would have changed every line of `settings-cases.json`, which apps already replay. **An app cleans the same raw `cat` block with both functions** and keeps both results: `cleanCatSettings` still returns only `{character, motionStyle, collar, furLines, cats}` and drops the display keys.

```text
{ displayMode, pair, agentCats: { <pillId>: <catId> } }
```

| macOS key | Field |
|---|---|
| `cat.displayMode` | `displayMode` |
| `cat.pair` | `pair`, as the JSON text of two cat IDs |
| `cat.agentCat.<pillId>` | `agentCats.<pillId>` (the Mac lists its UserDefaults keys with that prefix) |

| Field | Kept when it is | Anything else becomes |
|---|---|---|
| `displayMode` | `one`, `perAgent` or `two` (frozen, like the cat IDs) | `one` |
| `pair` | two different valid cat IDs, as an array or as the JSON text of one | Shrimpy and Momo, whole: one bad ID spoils the pair. Two of the same coat make cat 2 the next coat in `CAT_IDS` order, the first after the last |
| `agentCats` | an object | no coats stored |
| `agentCats.<pillId>` | a valid cat ID | the pill's default coat when it has one (`integration_claude` Shrimpy, `agent_codex` Momo), else dropped: assignment gives that agent a coat again |

- **A pill ID** matches `^[a-z][a-z0-9_-]{1,63}$` as a whole string, and is not `constructor` or `prototype`. An unknown pill ID is kept (agents come and go); `__proto__` and anything else that is not a pill ID is dropped. The result is in code-point order of the IDs and holds at most `MAX_AGENT_CATS` (256) pills: the first 256 in that order. `pillIds` in the fixture pins the shape.
- **Agent pills** are `integration_claude` (despite its prefix) and every `agent_*` pill (`isAgentPill`). Integrations and AI providers are not agents and never get a coat of their own.

### Giving agents their cats

`agentCatFor(pillId, agentCats, mainCat, rand)` returns `{cat, agentCats, assigned}`: the pill's stored coat, else its default, else a new coat that no other agent and not the Main cat uses, chosen at random; when all 16 are taken, the least-used one, ties in `CAT_IDS` order. A default coat that a stored coat has replaced counts as free; a default that is still in force counts as taken, whether or not that agent has been seen yet. `assigned` is true when `agentCats` gained the pill: store it then, and never change it by itself afterwards. `rerollAgentCat` is the dice button (never the current coat, always stored); `assignAgentCats(pillIds, agentCats, mainCat, rand)` gives every agent in a list a coat, and "Reset to defaults" is that call with an empty map.

- **Random numbers.** `rand()` returns 0 up to, not including, 1. It is called **once, and only when a free coat is chosen at random**; the least-used rule draws nothing, and nor do stored coats, defaults and non-agent pills. A number that is not finite is 0, and the index is held to the last free coat. The rows of `agent-cat-cases.json` name their source (`{seed}` is `rng(seed)`, `{values}` those numbers in order and then 0, `{none}` must never be called) and `draws`, the number of calls: a port that draws one more or one fewer drifts from the rows after it.
- **To change a coat** (the picker in Settings), put `{...agentCats, [pillId]: catId}` through `cleanAgentCats`.

### The cast

`castOf(mode, {tasks, focusId, mainCat, pair, agentCats})` says which coat each place wears. A cat stands for an agent's pill; the big cat shows the focused pill.

| Place | One cat | A cat for each agent | Two cats |
|---|---|---|---|
| Big cat, compact and expanded (`big`) | Main cat | the focused agent's cat; the Main cat when the focus is an integration or nothing | pair cat 1, showing the focused pill |
| Second spot (`second`) | none | none | pair cat 2, showing the busiest other agent |
| Row and 2×2 grid (`pills`) | Main cat | agent pills in their own cats, integrations in the Main cat | Main cat |
| Drop view and drag ghost (`drop`) | Main cat | the big cat's | the big cat's |
| Launch greeting (`greeting`) | the Main cat falls in; four session cats in the Main cat | the Main cat falls in; the four session cats are the cats of `pills` | the Main cat falls in and the pair arrives together; four session cats in the Main cat |

- **`tasks`** are the island's pills in the app's order, each `{id, state, last}`: `last` is the time of the pill's last event in ms (a missing or non-number one is 0), so **each app keeps a last-event time per pill**. A state that is not one of `STATES` is idle. A pill listed twice counts once.
- **The busiest other agent** is, among the agent pills other than the focused one, the first by `busyRank` (0 waiting for you, approval or question; 1 error; 2 working, thinking or searching; 3 anything else), then by the most recent `last`, then by its place in `tasks`. An integration is never chosen, and neither is the focused pill; Claude Code can be, when another agent is focused. With no other agent pill, `second.pill` is null and cat 2 idles with no badge. An idle agent that is the only other one is shown (idle), not skipped.
- **The row** is the first `PILL_ROW` (4) tasks other than the focused one and, in Two cats mode, other than `second.pill`, in the app's order.
- **An agent with no stored coat and no default** wears the Main cat here: the app gives it a coat with `agentCatFor` the first time it sees it, before it draws it.
- **Kittens' parents.** A kitten is `kittenOf` the coat its parent is drawn in at that spot: `big.cat`, `second.cat` or the pill's `cat` in `pills`.

### Kittens

A subagent is a kitten of its parent's cat. Each agent pill keeps a list, and `kittenStep(list, event)` is the one reducer that changes it. It is pure: the time is in the event (`t`, ms, any one clock), nothing is read from a clock, and nothing is changed in place. A kitten is `{id, type, session, state, born, last, until}`: `state` is `working`, `searching`, `approval` or `leaving`.

| Hook | Reducer event |
|---|---|
| `SubagentStart` (`agent_id`, `agent_type`, `session_id`) | `{type: 'start', id, agentType, session, t}`: a working kitten |
| `PreToolUse` or `PostToolUse` with an `agent_id` | `{type: 'tool', id, tool, t}`: searching for a tool in `search-tools.json`, else working |
| `PermissionRequest` with an `agent_id`, and its answer | `{type: 'permission', id, t}`: approval; `{type: 'resolved', id, t}`: working |
| `SubagentStop` | `{type: 'stop', id, t}`: leaving for `KITTEN_LEAVE_MS` (600 ms), then gone |
| the parent's `Stop`, or the session ending | `{type: 'end', session, t}`: every kitten goes; with a `session`, only that session's and those with none |
| the cat's sleep timer fires | `{type: 'sweep', t}`: a kitten whose last event is `SLEEP_AFTER_MS` (10 minutes) or more old goes |

- **Which pill:** the one the event belongs to, found as every other event finds its pill. Tool events without an `agent_id` belong to the parent and change no kitten: that is the fallback for a Claude Code that sends none (kittens still appear at start and leave at stop, in the working pose).
- **No timer.** A leaving kitten is dropped by the next event of any kind (`tick` is the event that only brings the time), and `kittenView(list, now)` hides it from its `until`, so the view is right between events. At most `KITTEN_MAX` (8) are kept: a ninth start drops the oldest by `born`.
- **An event for an id with no kitten, or for one that is leaving, changes nothing.** A late tool event after `SubagentStop` must not bring a kitten back, and without a start there is nothing to show.
- **Order:** `kittenOrder` puts a kitten waiting on an approval first, then the newest (`born`, and a later place in the list when they tie). `kittenView` is the order, without the expired leaving kittens, and is what `kittenSlots` takes.
- **`end` and two sessions.** Two sessions of one agent share a pill. Give `start` the hook's `session_id` and an `end` for one session leaves the other's kittens alone; an `end` with no session takes all, as the spec says.

`kittenSlots(place, kittens)` gives the slots. Every number is a multiple of a unit: `D`, the parent's head width, from its head centre (x right, y down), or `H`, the pill's height, from the pill's trailing edge (so x is negative inside it) and the middle of its height. The numbers are the brainstorm mockup's, divided by its parent's size.

| Place (`kittenPlaceOf(mode, expanded)`) | Unit | Up to | Kitten Ø | First centre (x, y) | Next | Overflow "+N" at |
|---|---|---|---|---|---|---|
| `bigExpanded` (One cat, A cat for each agent) | D | 3 | 15/58 | 24/58, 34/58 | 18/58 right | the next slot |
| `bigCompact` (One cat, A cat for each agent) | D | 2 | 12/20 | 22/20, 5/20 | 13/20 right | 42/20, -10/20 |
| `pairCompact` (Two cats) | D of cat 2 | 0 | none | none | none | a label "×N" at 1.1, 0.3 (the count of both cats' kittens) |
| `pairExpanded` (Two cats, for each cat) | D | 3 | 15/58 | a row centred under the cat, at y 34/58 | 18/58 apart | 0, 50/58 |
| `pill` (an agent pill, not focused) | H | 3 | 15/28 | -17.5/28, 0 | 16/28 inwards | the next slot |

The result is `{place, unit, count, shown: [{id, state, x, y, d}], more, moreAt: {x, y, size} | null, label: {text, x, y, size} | null}`. An unknown place shows nothing.

### Small coloured eyes

Below Ø28 the plain resting eyes (`pill`, `wide`, `dot`, `tired`, and the left eye of a `wink`) are small coloured eyes instead of ink pills; the expression shapes stay ink. `usesSmallEye(shape, sd)` says which, and `smallEye(shape, {sd, R, es, open, yaw, pitch, kitten})` is the geometry, in px of the eye's own frame (the centre at the origin, y down, inside the renderer's foreshortening). It returns `{shape, closed: false, iris: {rx, ry, r}, pupil: {x, y, rx, ry}, light: {x, y, r}, rim}`, or `{shape, closed: true, line: {x0, y0, cx, cy, x1, y1, width}}` for an eye closed to a line, and `null` for an ink shape.

- **Sizes** (`SMALL_EYE`, fractions of `R * es`, full widths): the iris 0.42 by 0.46, the pupil 0.18 by 0.40, the catchlight radius `max(0.075 R, 0.45)` at (-0.11, -0.10) and the rim `max(0.05 R, 0.5)`. `wide` is the iris times (1.16, 1.12), `dot` a round iris (0.42) with a round, dilated pupil (0.26), `tired` shows at most 0.42 of the eye. A kitten's eye is 1.2 times wider and 1.32 times taller, which is what `kittenOf` does to a kitten's eyes.
- **Squint.** `open` (the pose's `open * (1 - lid)`) scales the iris's height, and under 0.22 the eye is the closed line, as the realistic eye does. The pupil's height is held to 0.87 of the iris's and the catchlight keeps its place in the iris, so both follow a squint.
- **Gaze.** The pupil moves with `yaw / 0.62` and `pitch / 0.5` (each held to -1 to 1) by at most 0.2 of the iris's half-width across and 0.08 of its half-height up or down, so it never leaves the iris (a test brute-forces it).
- **Colours are the renderer's.** The iris is a radial gradient from `iris[0]` at the centre to `iris[1]` at radius `iris.r` (`irisR` for the right eye, `sd` 1, when the coat has one); the pupil is `Theme.Cat.pupil`; the catchlight is white at 0.92; the rim is stroked in the preset's `liner` colour on the iris's edge; the closed line is stroked in `ink` at 0.9 alpha. The prototype's `smallEyeDraw` is the reference.
- **Not part of this:** every expression shape (they stay ink), the large cats' realistic eye, and the flat-fill rule.

**Notes for ports:**
- **Settings are read as plain JSON values,** as for the Cat settings (see "Stored settings"). `cleanPair` accepts the JSON text the Mac stores; text that is not strict JSON is "not a pair".
- **The pill-ID pattern is matched against the whole string.** ICU and Swift's `NSRegularExpression` let `$` match before a final newline: use a whole-match, or `\z`. The fixture holds `agent_x\n` and `agent_x ` as not pill IDs.
- **Key order does not matter** in a map; `cleanAgentCats` writes its keys in code-point order, and the cap is on that order, so a port that cannot keep a dictionary's order sorts the keys before taking the first 256.
- **Events cannot carry NaN or Infinity in a fixture,** and a missing key or `null` stands for "not there". A port adds its own tests for a time that is not finite (the event changes nothing) and for NaN in `smallEye`'s inputs (taken as the default; `R` is held to 0 up to 10000, `es` to 0 up to 10).
- **Replay the fixtures:** `display-cases.json` (`cases`, `pairs`, `agentCats`, `pillIds`), `agent-cat-cases.json` (with the harness above), `cast-cases.json` (`cases`), `kitten-cases.json` (`scripts` one event at a time, then the rest) and `small-eye-cases.json` (every group).
'''
s = s.replace(anchor, section + anchor)

# 4. Decisions to know about: six more.
s = s.rstrip('\n') + '''
- **Display settings have their own clean-up.** `cleanDisplaySettings` is separate from `cleanCatSettings` so that no line of `settings-cases.json` moves. An app that stores both in one block must keep the display keys when it writes the block back: a clean-up that rebuilds the block from `cleanCatSettings` alone drops them.
- **A pair is whole or default.** One bad ID in a stored pair makes it Shrimpy and Momo, not a pair with one repaired side.
- **The cast never invents a coat.** An agent with neither a stored coat nor a default wears the Main cat until `agentCatFor` has given it one; random choices happen only there, with an injected `rand`.
- **Kittens come only from a start.** An event for an id that never started, or already left, creates and changes nothing.
- **Cat 2 can be an idle agent.** "The busiest other agent" ends with the most recent event, so when no other agent is busy cat 2 shows the most recent one, idle or finished; it is empty only when there is no other agent pill.
- **The small eye's pupil travels little.** A slit pupil that nearly fills the iris has no room to move; 0.2 and 0.08 of the iris's half-axes are the most that keep it inside at every squint, which a test checks by brute force.
'''
open(p, 'w', encoding='utf-8').write(s)

# ── CLAUDE.md, ARCHITECT.md and the spec ──────────────────────────────────────────────────────────────────────
edit('CLAUDE.md', [("(`docs/THEME.md`). Existing views keep their colours.\n",
 "(`docs/THEME.md`). Existing views keep their colours.\n"
 "- `cat-core.js` also holds sub-project B's rules: the Display settings (`cleanDisplaySettings`, a clean-up of its own, so `cleanCatSettings` and `settings-cases.json` stay as they were), the agents' coats (`agentCatFor`), the cast of each mode (`castOf`), the subagent kittens (`kittenStep`, `kittenSlots`) and the small coloured eyes (`smallEye`). Fixtures: `display-cases.json`, `agent-cat-cases.json`, `cast-cases.json`, `kitten-cases.json`, `small-eye-cases.json`; `docs/CAT-CONTRACT.md`, \"Display modes, agent coats, kittens and small eyes\". Display mode IDs (`one`, `perAgent`, `two`) are frozen like the cat IDs.\n")])
edit('ARCHITECT.md', [("and `shared/theme.json` feeds the generated theme files (`docs/THEME.md`).",
 "and `shared/theme.json` feeds the generated theme files (`docs/THEME.md`). **Sub-project B** (display modes, subagent kittens, coloured small eyes) has its contract in the same file and fixtures (`display-cases.json`, `agent-cat-cases.json`, `cast-cases.json`, `kitten-cases.json`, `small-eye-cases.json`), and the prototype draws it; see `docs/CAT-CONTRACT.md`, \"Display modes, agent coats, kittens and small eyes\".")])
edit('docs/superpowers/specs/2026-10-08-display-modes-kittens-design.md', [
 ("All of them go through A's shared clean-up (`cleanCatSettings`), extended: an unknown mode is `one`",
  "All of them go through a clean-up of their own, `cleanDisplaySettings` (B-0 keeps `cleanCatSettings` and `settings-cases.json` byte for byte, and an app cleans the same raw block with both): an unknown mode is `one`"),
 ("the new settings fields in `cleanCatSettings`;", "the Display settings' clean-up, `cleanDisplaySettings`;"),
 ("and additions to `settings-cases.json`; every existing fixture stays byte-identical;", "and `display-cases.json` for the Display settings; every existing fixture stays byte-identical;"),
])
PY
git diff --stat -- CLAUDE.md ARCHITECT.md docs
`````

Expected: four files: `ARCHITECT.md` (2 lines changed), `CLAUDE.md` (1 added), `docs/CAT-CONTRACT.md` (117 added) and the spec (6 changed), and `4 files changed, 122 insertions(+), 4 deletions(-)`.

- [ ] **Step 2: The final checks**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓|✗"`
Expected: `# tests 231`, `# pass 231`, `# fail 0`, fourteen `✓` fixture lines, `✓ 14 fixture files match cat-core.js`, `✓ two generator runs write identical bytes`.

Run: `node scripts/check-fixtures-additive.mjs 6c14947`
Expected: nine `✓ <file>: N old lines unchanged` lines for the old fixtures (`collar-cases.json` 187, `geometry-cases.json` 180, `motion-cases.json` 713, `personality-cases.json` 62, `presets.json` 42, `search-tools.json` 36, `sequence-cases.json` 231, `settings-cases.json` 110, `warp-cases.json` 121), `+ <file> is new` for the five new ones and `✓ fixtures changed only by addition since 6c14947`.

Run: `bash scripts/check-no-leftovers.sh`
Expected: five `✓` lines.

The apps still pass their own fixture tests (the new files change none of them):

Run: `cd windows && node --experimental-strip-types --test --test-reporter=spec scripts/cat-tests/*.test.mjs 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `ℹ tests 166`, `ℹ pass 166`, `ℹ fail 0`.

Run: `bash scripts/test-cat-personality.sh 2>&1 | tail -1 && bash scripts/test-cat-presets.sh 2>&1 | tail -1`
Expected: `All tests passed.` twice.

Run: `git status --short`
Expected: ` M CLAUDE.md`, ` M ARCHITECT.md`, ` M docs/CAT-CONTRACT.md`, ` M docs/superpowers/specs/2026-10-08-display-modes-kittens-design.md`. Nothing under `NotchBuddy/` or `windows/` is modified, and `git log --oneline 6c14947..HEAD` lists the six commits of Tasks 1 to 6.

- [ ] **Step 3: Commit**

```bash
git add docs/CAT-CONTRACT.md CLAUDE.md ARCHITECT.md docs/superpowers/specs/2026-10-08-display-modes-kittens-design.md
git commit -m "docs(cat): the display, kitten and small-eye contract is documented

CAT-CONTRACT.md gains the section and the fixture rows; CLAUDE.md and ARCHITECT.md point to it; the spec says the Display settings have
a clean-up of their own.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

## Open questions for the owner

Each has the answer this plan assumes, so nothing blocks. A different answer changes `cat-core.js` and one fixture, and the app plans pick it up.

1. **The Display settings have a clean-up of their own.** The spec (§1, §5) says `cleanCatSettings` is "extended" and `settings-cases.json` gains additions. Both would change lines the apps already replay, which the additive rule forbids (`check-fixtures-additive.mjs` fails on a changed line). So `cleanDisplaySettings` is a separate function with `display-cases.json`, an app cleans the same raw block with both, and Task 8 edits those three sentences of the spec. The cost: the Windows plan must carry the three display keys through `settings.rs`'s `sanitized`, which rebuilds the `cat` block from the Cat settings alone. OK? (Assumed: yes.)
2. **A bad pair is whole-or-default.** One unknown ID in `["momo","tiger"]` makes the pair Shrimpy and Momo; it does not keep Momo and repair the other side. The same coat twice is repaired (cat 2 is the next coat). (Assumed: as the spec says, "a bad pair is Shrimpy & Momo".)
3. **Cat 2 can be an idle or finished agent.** The spec's busiest-other rule ends with "then the most recent event", and says "with no other active agent, cat 2 sits idle with no badge". This plan reads it literally: any other agent pill is eligible, the busiest wins, and cat 2 shows that agent's real state (a finished agent shows its dot); cat 2 is empty (idle, no pill) only when there is no other agent pill. The alternative is to make an idle or finished agent ineligible, so cat 2 idles whenever nothing is busy. (Assumed: the literal reading.)
4. **In Two cats mode cat 1 always shows the focused pill,** an integration (Stripe) or nothing included; the spec says "the focused agent". With an integration focused, cat 2 is still the busiest agent. (Assumed: yes. Cat 1 is the big cat in every mode.)
5. **An agent with no stored coat and no default wears the Main cat in the cast** until `agentCatFor` has given it one, which the apps do when they first see the agent, before drawing it. The cast never invents a coat, so it stays pure and never draws a random number. (Assumed: yes.)
6. **The two default coats count as taken for a new agent,** even before Codex has appeared: a Gemini CLI that arrives first never gets Momo, so Codex does not arrive to a duplicate. A default that a stored coat has replaced is free. (Assumed: yes; the spec's "not already in use by another agent" is silent on defaults.)
7. **Two sessions of one agent share a pill, so `end` can name a session.** The spec says the parent's stop or the session's end removes "all"; with two Claude Code windows in one pill, one stopping would take the other's kittens. The reducer's `end` event takes an optional `session` (from the hook's `session_id`, also stored on `start`): with it, only that session's kittens and those with no session go; without it, all go, as the spec says. (Assumed: yes. The apps may leave `session` out and get the spec's behaviour.)
8. **Kittens come only from a start, and nothing times out by itself.** A tool or permission event for an id that never started, or already left, creates nothing (it would bring back a kitten that had gone). A leaving kitten is dropped by the next event and hidden by `kittenView`, so no timer runs while the island is hidden; the 10-minute sleep timer's `sweep` is the only cleanup for a stop that never came. (Assumed: yes; the spec asked for the reason.)
9. **The kitten slots are the mockup's numbers over its parent's size,** with three choices the mockup did not make: the pair's expanded kittens are a row centred under each cat with the "+N" below the row (so cat 1's label does not land on cat 2's kittens); the compact pair shows "×N" to the right of cat 2, counting both cats' kittens; and an agent pill's kittens sit at its trailing end, 16/28 apart, with "+N" after the last, as the spec says (the mockup's only pill example was the rejected option B at the leading end). You see all of them on the Task 7 screenshots. (Assumed: yes.)
10. **The small-eye numbers are the spec's starting values, plus these choices:** `dot` is a round iris (0.42) with a round, dilated pupil (0.26); `tired` shows at most 0.42 of the eye; `wide` is the iris times (1.16, 1.12), as the ink shape was; the pupil moves by at most 0.2 of the iris's half-width and 0.08 of its half-height (a slit pupil that fills the iris has no more room, and a test proves it stays inside); the catchlight keeps its place in the iris through a squint; a kitten's eye is 1.2 wide by 1.32 tall, the ratio `kittenOf` gives; the eye closes to a line under 0.22 of its height, as the realistic eye does; the prototype draws the iris as a soft gradient and the rim in the coat's liner colour. You judge the look on the contact sheet; a different number is one edit in `SMALL_EYE`. (Assumed: yes.)
11. **The prototype's existing panels change in four named places:** the "Character" row is now "Main cat"; the Size ladder's text no longer says "ink eyes"; the expanded island is 600 by 200 and lists the cast's pills (the old three fixed sessions are gone); a `data:` favicon keeps the console empty. The compact cats' new eyes show in every panel that draws one. (Assumed: yes; the spec asks for the rename and the eyes, and the mock needs the room.)
12. **The greeting in Two cats mode:** the Main cat falls in as always and cat 2 pops in beside it when the island folds. The contract carries `greeting.pair`; how the pair arrives is the app plans' choreography, and the page shows one way. The alternative, both cats falling in together, changes `greetingPose`, which is pinned by `sequence-cases.json`. (Assumed: as drawn.)
13. **Pill IDs, as the contract reads them:** `^[a-z][a-z0-9_-]{1,63}$`, never `constructor` or `prototype`, at most 256 pills in a stored map. The Mac's `nm_agent` names are lowercase letters, digits and hyphens up to 24 characters, so every `agent_<name>` fits. (Assumed: yes; a future pill with another shape is a one-line change.)
14. **Both apps must start keeping a per-pill last-event time.** The busiest other agent needs it, and neither app has one (`lastActivity` is global). That is in the B-mac and B-tauri plans, not here.
15. **Helpers beyond the brief:** `rerollAgentCat` (the dice), `assignAgentCats` (first launch and "Reset to defaults"), `pickCat`, `busyRank`, `cleanKittens`, `kittenOrder`, `kittenView`, `kittenPlaceOf`, `usesSmallEye`, `isPillId` and `defaultDisplaySettings`. Each is small, and each stops the two apps reading a rule two ways. Drop any you would rather leave to the apps. (Assumed: keep.)

## Self-review notes

- **Spec coverage.** §1: the three modes and their frozen IDs, the pair, the agents' coats, the storage keys and the clean-up (Task 1), giving an agent its cat, the dice and "Reset to defaults" (Task 2); the Display picker, the live preview and the agent list are UI and belong to the app plans, and the prototype shows the same controls. §2: the table of places and the busiest-other rule (Task 3). §3: the data events, the fallback, the order, the cap, the clean-up and the placement table with its slots and overflow (Task 4). §4: the eye geometry (Task 5) and its look (Task 6). §5 step 1: the rules and fixtures (Tasks 1 to 5), the prototype (Task 6) and the owner checkpoint (Task 7). The frame budget is the app plans' (Risks: re-measured before and after). Out of scope and left out: per-session pills, Codex hooks on Windows/Linux, sounds, the desktop cat, kitten names.
- **Placeholders.** None: every code step carries its full content, generated into this plan from the files the dry run ran.
- **Type consistency.** The names in the interface tables are the ones in the core sections, the tests, the fixture builders, the prototype and the docs; the kitten record `{id, type, session, state, born, last, until}` is the same in `cleanKittens`, `kittenStep` and `kitten-cases.json`.
- **Review Focus** lines 1 to 5 each have named tests above.
- **What this plan deliberately does not do:** touch either app; add Settings rows or a live preview; decide the greeting's choreography for the pair; re-measure the frame time; add sounds for kittens or modes.

## Dry run (2026-10-08)

Run before the plan was handed over, in throwaway clones made with `git clone --local --shared` of the repository, on branch `notchmeow/rebrand` at `6c14947` (nothing was installed or downloaded: the browsers are the ones `playwright-cli` had cached). The first clone was used to write and test the code, task by task, from work files; the later clones ran the plan text from its first line to its last. Each task was applied **exactly as written** by a small script that executes the plan's `bash` blocks and `Run:` lines in order, prints what each printed beside the plan's `Expected:` line, and flags any backticked token of an `Expected:` line that the output lacks (the plan text is generated from the files the first clone ran; the last clone's tree is byte-identical to the first's: `diff -r` on `design/`, `scripts/`, `tests/`, `docs/`, `CLAUDE.md` and `ARCHITECT.md` prints nothing). Every `Run:` line printed what its `Expected:` line says; the only flagged tokens were words of the prose (a function name in "the core has no `castOf` yet", the placeholder `<file>` of Task 8). The static server and the browser were started and stopped by the plan's own steps, and both were gone afterwards. The clones were then moved to the Trash, and nothing was committed or pushed in them or in the main checkout.

| Task | Result |
|---|---|
| Baseline, before any change | `bash scripts/test-cat-contract.sh`: `# tests 138`, `# pass 138`, 9 fixtures, determinism check passes |
| 1 | `display.test.mjs` fails 14 of 14 without the section and passes 14 of 14 with it; with the prototype-name guard removed, tests 8 and 10 fail (`# pass 12`, `# fail 2`); the whole contract `# tests 152`, then `# tests 155` with 10 fixtures; `display-cases.json` is 37,764 bytes (30 cases, 40 pairs, 21 agent maps, 29 pill IDs); `check-fixtures-additive.mjs 6c14947`: the nine old files keep 187, 180, 713, 62, 42, 36, 231, 110 and 121 lines and `✓ fixtures changed only by addition`; with the same-coat rule removed from `cleanPair`, `--check` prints `✗ display-cases.json drifted from cat-core.js (8 differences)` |
| 2 | 14 of 14 self-checks; with the tie rule changed from `<` to `<=`, tests 7, 8 and 11 fail; `# tests 169`, then `# tests 172` with 11 fixtures; `agent-cat-cases.json` is 17,362 bytes (34 + 11 + 6 rows); drift check: 16 differences |
| 3 | 11 of 11; with approval and error swapped in `busyRank`, tests 5 and 11 fail; `# tests 183`, then `# tests 186` with 12 fixtures; `cast-cases.json` is 92,917 bytes (136 rows); drift check: 5 differences |
| 4 | 25 of 25; with the cap at 9, tests 1 and 10 fail; `# tests 211`, then `# tests 214` with 13 fixtures; `kitten-cases.json` is 48,915 bytes (21 scripts, 35 slot rows); drift check: 70 differences |
| 5 | 11 of 11; with the closing threshold at 0.2, tests 1, 5 and 8 fail; `# tests 225`, then `# tests 228` with 14 fixtures; `small-eye-cases.json` is 60,936 bytes (259 rows); drift check: 17 differences |
| 6 | The patch applies (123 insertions, 31 deletions); the page loads with 0 console errors, the 8 panel headings and 21 canvases; the clicks give the casts in Task 6 Step 3 (Per agent: Codex Momo, Gemini CLI Mocha, Antigravity Latte; Two cats: Momo is cat 2 and leaves the row; One cat: Shrimpy everywhere); the kittens go 4, 5, 4 drawn (5 then 4 kept) as the stop, the farewell and the next event say; the dice gives Gemini CLI a coat that is neither Shrimpy nor Momo; the greeting plays for 6.5 s in Two cats mode with 0 console errors; the server is gone afterwards (`000`) |
| 7 | Eight PNGs at a device scale of 2 (about 56 to 276 KB each) in `${TMPDIR}/b0-shots`, console empty. I looked at the three expanded mocks, the one-cat compact one and (during drafting) the two-cats compact one and both eye sheets: they show what Step 2 says they show |
| 8 | The docs apply (`CAT-CONTRACT.md` +115, `CLAUDE.md` +1, `ARCHITECT.md` 2 lines, the spec 6 lines: `4 files changed, 120 insertions(+), 4 deletions(-)`); the final contract run `# tests 228`, 14 fixtures; the additive check as listed; `check-no-leftovers.sh` five `✓`; the Windows cat tests `ℹ tests 166`, `ℹ pass 166`; `test-cat-personality.sh` and `test-cat-presets.sh` `All tests passed.` |

**What drafting and the dry run changed in the plan:**
- **The pupil left the iris.** A brute-force property test of the first `smallEye` found the pupil poking out of the iris (by a few percent of its radius) at a squint with the gaze turned. The travel is now 0.2 and 0.08 of the iris's half-axes, which stay inside at every squint, shape, kitten and expression scale (the test is in Task 5).
- **A huge head or scale made NaN.** The 5000-call fuzz found `R` and `es` of 1e300 turning every number into NaN: `R` is held to 0 up to 10000 and `es` to 0 up to 10, and `smallEye(shape, null)` no longer throws.
- **The "+N" of a pair's kittens landed on the other cat's kittens** in the first screenshot, so the pair's overflow label sits below the middle of its row. The ticker text and the rows moved right (and the island grew to 600 by 200) because the first screenshot showed the big cat's kittens running into the Antigravity row.
- **`pairCompact` has no overflow:** the first slots code gave its "+N" a NaN position; the place now has only its "×N" label.
- **Two sessions of one agent:** `end` takes an optional `session`, because one session stopping must not take the other's kittens (open question 7).
- **A trailing newline in a pill ID.** `$` in a regular expression matches before a final newline in ICU and Swift; the contract says "match the whole string" and the fixture holds `agent_x\n` and `agent_x ` as not pill IDs.
- **The ordering in a `Run:` line:** `playwright-cli eval` takes an expression, not statements; two buttons with the same name (the focus row and the Collar panel's agent row) made a click fail silently, so the focus clicks are scoped to their row; the screenshots need a device scale of 2, which a small config file sets; a missing favicon made one console error, so the page has a `data:` favicon.
- **Plan text that placed a heredoc inside a heredoc** (the plan generator's own) and **a blank line lost between two sections** in the first assembly were found by comparing the clones' trees with `diff -r`, and fixed.

**Not run, by rule:** the commit steps (nothing may be committed in a clone). So in the clone `git status --short` listed every task's files at once, and `git log --oneline 6c14947..HEAD` in Task 8 Step 2 was not run; the plan's `Expected:` lines assume each task was committed before the next. Task 7's stop is a human gate and the run did not wait at it. The Mac and Windows builds were not run (the plan touches no app code); the Windows cat tests and two Mac scripts that replay fixtures were, and pass.

## The owner's answers (2026-10-08)

- **Plan:** approved, run in a worktree session on Sonnet 5.5, effort medium, as "Execution" says; it stops after Task 7 for the owner's checkpoint.
- **Open questions 1 to 15:** approved as assumed.

**Checkpoint changes (2026-10-08):**
- Bright eyes for the three black coats (Midnight, Oreo, Mocha): a flat fill of the lighter iris colour, no rim, a thinner pupil (0.12).
- The pair is at 114 (cat 2 in the expanded Two cats island), for a 6 px gap between the cats.
