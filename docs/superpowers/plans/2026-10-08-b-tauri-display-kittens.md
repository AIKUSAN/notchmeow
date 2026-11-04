# B-tauri Display Modes, Per-Agent Cats, Kittens and Small Eyes Implementation Plan (Windows and Linux)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Windows/Linux Tauri app gets sub-project B: every cat drawn below Ø28 has **small coloured eyes**; **Settings → Cat → Display** picks One cat, A cat for each agent or Two cats (with a live preview, the pair's pickers and a "Cats for your agents" list), saved in the `cat` block without ever being dropped; every agent has **its own coat** from the first time it is seen; Two cats mode shows a pair side by side; and Claude Code **subagents** appear as kittens beside their parent, with their own state.

**Architecture:** Everything pure is a TypeScript port of `design/prototype/cat-core.js` (the tie-breaker), replayed in plain Node against the five fixtures B-0 added to `tests/fixtures/cat/` within 1e-9, with the random source and the clock injected: `smalleye.ts`, `display.ts`, `agentcat.ts`, `cast.ts`, `kittens.ts`. The Display keys (`displayMode`, `pair`, `agentCats`) live in the same `cat` block as the Cat settings, so a Rust twin (`clean_display_settings` and `clean_cat_block` in `cat_settings.rs`) cleans them and `settings.rs` carries them through every save. `State` holds the cast of the chosen mode, a last-event time per pill, the agents' coats and the kittens' lists (never stored); every `BotEngine` is given its coat from the cast with `setCoat`, and its collar style is looked up per coat. The island gets a second cat (Two cats mode), an overlay canvas for the kittens beside the big cat and a strip on each agent pill. The checkpoints' pictures are drawn headless from the Vite dev server, with a dev-only `window.__nm.hook(...)` that feeds the real hook handler.

**Tech Stack:** TypeScript 5 and Vite 6 (already in `windows/`), Canvas 2D, Node 22 (`node --test` reading the TypeScript source with `--experimental-strip-types`), Rust with `serde_json` only (no new crate), `playwright-cli` (headless Chromium, for the eye and layout checks only). No new npm or cargo dependency.

**Spec:** `docs/superpowers/specs/2026-10-08-display-modes-kittens-design.md`: §5 step 2 (B-tauri) with §1 "Settings and persistence", §2 "Which cat appears where", §3 "Kittens" and §4 "Coloured eyes for small cats". The contract is the approved B-0 plan, `docs/superpowers/plans/2026-10-08-b0-display-kittens-contract.md`, "Interface for the app plans", and what it merged (`e00ad3d`, with the owner's checkpoint changes: the black coats' bright eyes and the pair at 114): `design/prototype/cat-core.js`, `docs/CAT-CONTRACT.md` ("Display modes, agent coats, kittens and small eyes") and the five fixtures `display-cases.json`, `agent-cat-cases.json`, `cast-cases.json`, `kitten-cases.json`, `small-eye-cases.json`. The format and conventions are the last Windows plan's, `docs/superpowers/plans/2026-10-07-a-tauri-cats-stages-5-7.md`. The Mac twin is `docs/superpowers/plans/2026-10-08-b-mac-display-kittens.md`; "Parity with macOS" below says what differs. Read the Windows cat code first (`windows/src/cat/`, `windows/src/island/`, `windows/src/core/state.ts`, `windows/src/settings/cat.ts`, `windows/src-tauri/src/settings.rs`) and `.claude/archive/owner-manual-checks.md` (the sections on the Windows cats).

**Base:** branch `b-tauri/display-kittens`, in a git worktree, from `notchmeow/rebrand` **at `e00ad3d` or later: B-0 is merged, and nothing of the B-0 plan needs applying** (B-0 added `cleanDisplaySettings`, `agentCatFor`, `castOf`, `kittenStep`, `smallEye` to `cat-core.js` and the five fixtures; this plan reads them and edits none; the Setup block checks `git merge-base --is-ancestor e00ad3d HEAD`), with the Windows cats' stages 1 to 7 (`924abca`) in its history. Nothing is pushed.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec; a line marked "(plan decision)" is a choice this plan makes where the spec is silent, and is listed again under "Open questions for the owner".

- **Frozen IDs.** Cat IDs, in this order: `shrimpy`, `momo`, `ginger`, `midnight`, `latte`, `patches`, `blue`, `snow`, `oreo`, `mocha`, `silver`, `cloud`, `leo`, `button`, `puff`, `noodle` (an unknown stored ID is Shrimpy). Collar style IDs: `tag`, `band`, `kerchief`, `off`. **Display mode IDs, from now on: `one`, `perAgent`, `two`**, in that order; an unknown stored mode is `one`. Pill IDs are frozen (`integration_claude`, `agent_<tag>`); a pill ID never changes. Never rename a contract string (`nm-hook`, `nm.sock`, `notchmeow-hook`, `nm_kind`, `nm_agent`).
- **The modes (spec §1, §2).** One cat (the default): the Main cat everywhere, today's layout. A cat for each agent: the big cat is the focused agent's cat (the Main cat when the focus is an integration or nothing), every agent pill wears its agent's cat, integration pills the Main cat. Two cats: a pair (Shrimpy and Momo by default, both pickable; the same coat twice makes cat 2 the next coat in `CAT_IDS` order); cat 1 is the big cat and shows the focused pill, cat 2 shows the busiest other agent (a waiting approval or question, then an error, then working, thinking or searching, then the most recent event) and that agent leaves the pill row and the grid. "Character" is renamed "Main cat".
- **Agent pills** are `integration_claude` (despite its prefix) and every `agent_*` pill; **integration pills** are the other declared pills. **The agents' coats (spec §1):** `integration_claude` is `shrimpy` and `agent_codex` is `momo` by default; any other agent pill, the first time it is seen, gets a random coat used neither by another agent nor as the Main cat, and keeps it; when all 16 are taken, the least-used, ties in `CAT_IDS` order. The random source is injected.
- **Storage (spec §1).** `displayMode`, `pair` and `agentCats` (a map from pill ID to cat ID) sit in the `cat` block of `settings.json`, beside the Cat settings, and go through a clean-up of their own (`cleanDisplaySettings`, B-0's decision: new fields on `cleanCatSettings` would have changed `settings-cases.json`). An unknown mode is `one`, a bad pair is Shrimpy and Momo, an unknown or bad agent coat is that agent's default (dropped for an agent without a default), an unknown pill ID is kept. **A clean-up of the block that uses the Cat settings alone drops the three keys at the next save: every clean-up of the block, in TypeScript and in Rust, cleans both.** Kittens are never stored.
- **Kittens (spec §3).** `SubagentStart` adds one to the parent agent's pill; `PreToolUse`, `PostToolUse` and `PermissionRequest` events that carry an `agent_id` set its state (searching for a tool in `search-tools.json`, else working; approval while its permission request waits); `SubagentStop` plays a happy blink of 0.6 s and removes it; the parent's `Stop`, `StopFailure` (a turn that ended in an error) or `SessionEnd` removes all of that session's; the cat's existing ten-minute sleep timer sweeps the stale **when the cat falls asleep** (never under a working cat: a live subagent in a long, silent step stays); at most 8 per agent; order: approval first, then the newest. Placement: up to 3 under the big cat (expanded), up to 2 beside it (compact), a count "×N" only by the pair (compact), up to 3 under each pair cat (expanded), up to 3 at the trailing end of an agent pill, then "+N". **The parent cat behaves exactly as today.** Gemini CLI and Antigravity send no subagent events, and **Codex has no hooks on Windows and Linux, so there are no Codex kittens here.**
- **Small eyes (spec §4).** Every cat drawn below Ø28 (the compact notch, pill cats, the grid, kittens, the greeting's session cats) has a round iris in its coat's colours (`iris`, `irisR` for the right eye of an odd-eyed coat), a slit pupil in `Theme.Cat.pupil`, one catchlight and a thin rim, instead of the flat ink pill; the expression shapes stay ink; a blink or a squint closes the eye to a line. **The three black coats (Midnight, Oreo, Mocha), and their kittens, glow instead:** `smallEye` takes the coat's id as `cat` and, for a bright coat, returns `flat: true` with `rim: 0` and a thinner pupil (`brightPupil.w`, 0.12 of the head radius instead of 0.18); the renderer fills the iris with one flat colour, the lighter of the coat's two `iris` colours by luminance (Midnight `#F7D45C`, Oreo `#DDEB5A`, Mocha `#F6C44C`), draws no rim and keeps the catchlight; every other coat is unchanged. The numbers are the contract's (`SMALL_EYE`, with `bright` and `brightPupil`).
- **Tolerance and tie-breaker.** Numbers compare within **1e-9** against the fixtures (12 significant digits). **`cat-core.js` is the tie-breaker.** This plan never edits `design/prototype/cat-core.js`, `tests/fixtures/cat/`, `scripts/gen-cat-fixtures.mjs` or `docs/CAT-CONTRACT.md`: a change there is the main session's. If B-0's owner checkpoint changed a number (Setup checks `SMALL_EYE`, with its `bright` list, and `KITTEN_PLACES`), stop and say so: Tasks 1 and 11 hold copies. The cat code never calls `Math.random()` and reads a clock only as the late-bound default of a constructor or a parameter (State's `rand` and `performance.now()` are the two places the app passes real ones in).
- **Never restyle what ships.** The named exceptions: the compact cats' eyes (spec §4), the "Character" label of the Cat section (spec §1), and the island's text in Two cats mode only (`.overview.two`). The new Settings rows are built from the Settings window's own row styles with new CSS class names only; the island's new rules are new class names or sit under `.overview.two`. One cat and A cat for each agent keep today's layout. No pill, card, view or Settings row changes beyond what a task says.
- **Files loaded by `npm run check:cat`** (everything under `windows/src/cat/` except `dev.ts`, plus `core/layout.ts`, `core/sound.ts`, `core/state.ts`, `core/pills.ts`, `island/sleep.ts`, `island/subagents.ts`, `upload/sequence.ts`, `upload/refusal.ts`; `cat/minibots.ts` joins them in Task 9) use erasable TypeScript only (no `enum`, no `namespace`, no constructor parameter properties), `import type` for types, and relative imports **with the `.ts` extension**, because Node reads the source as it is. Files outside that set (`island/island.ts`, `island/hooks.ts`, `views/`, `settings/`, `main.ts`) keep the repo's extension-less imports.
- **No Coucou or Mochi names** anywhere (`mocha` is a coat, not a name to avoid); `names.test.mjs` keeps guarding `windows/`.
- **No new dependency.** No `npm install` of anything, and **no change to `Cargo.toml` or `Cargo.lock`**. Rust runs **only** through `windows/scripts/cargo-linux.sh` (Docker Desktop running), with this plan's own target directory, because other worktrees share that script's Docker volume: `windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/b-tauri`. Never install a toolchain on the host.
- **Performance.** 0 % CPU while the island is hidden and Settings is closed. Nothing new runs a timer or polls: the kittens are drawn by the island's frame loop (which stops while hidden), a leaving kitten is hidden by `kittenView` from its `until` with no timer, the stale are swept when the existing ten-minute sleep timer puts the cat to sleep, and the Settings previews run only while the window is visible and focused (the Cat section's one `VisibleLoop`). The frame time of the small cats is measured before and after (Task 2), and with eight kittens on top (Task 13).
- **Commits:** local only, never pushed. End every commit message with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; a task a light agent ran names `Claude Haiku 4.5` instead.
- **House rules for every session and every subagent brief (the SUBAGENT RULES block):**
  1. **Never launch, quit or replace any NotchMeow app, and never start the Tauri app** (`npm run tauri dev`, a built `notchmeow.exe`): the owner runs it. Serving the front end with `npx --no-install vite` and looking at it in the headless `playwright-cli` browser is allowed, and only that.
  2. **Install nothing and download nothing.** `npx --no-install` only; never `npm install`, `npm ci`, `npm run build`, `npm run dev` or `npm run tauri`.
  3. **Rust only through `windows/scripts/cargo-linux.sh`** with `--target-dir /repo/windows/target/b-tauri`. Check the image first (`docker image inspect notchmeow-linux-dev`): if it is missing or the daemon is down, stop and say so; the script would build it, which pulls a base image.
  4. **Use `trash`, never `rm -rf`;** unique scratch names; screenshots and the one-off scripts go in `${TMPDIR:-/tmp}/b-tauri-shots`, never in the repository. Stop every server you start (`kill $(lsof -ti tcp:14581)`) and every browser session (`playwright-cli close-all`).
  5. **Never push.** Commit only in a task's commit step. Never edit `CLAUDE.md` or `ARCHITECT.md` except where Task 14 says so.
  6. **If a command is denied by a permission prompt, stop and report it.** Do not look for a workaround.

## Review Focus

The spec says what the modes, the coats and the kittens must do. It is silent on these inputs, and each would bite a person first. Each line names its test.

1. **A hand-edited or half-written `cat` block with bad Display keys, and the next save.** A mode that is a number, a pair that is cut-off JSON text or has three coats, an `agentCats` map that is an array, has `__proto__`, a capital letter or 300 entries; then the Cat section saves. Expected: the app starts, the rest of the file and the Cat settings are kept, no `settings.json.bad-…` appears, the display keys are cleaned and **still there after the save** (the Rust `sanitized` used to rebuild the block from the Cat settings alone). Tests: Task 3 "a hostile map…", "3000 random display settings…", "a Cat settings row edit keeps the display keys…"; Task 5 `bad_display_keys_are_cleaned_and_one_of_them_never_fails_the_settings_file`, `the_display_settings_survive_a_save_a_load_and_a_round_trip`, `hostile_display_values_never_panic…`.
2. **A new agent when the coats run out, or the dice and the random source misbehave.** All 16 coats in use, the Main cat equal to a default, a stored coat replacing a default, `rand()` returning 1, NaN or text, an agent that comes back after its pill was removed. Expected: the least-used coat with ties in `CAT_IDS` order and no random draw; a freed default is free again; the dice never gives the same coat back; a bad `rand` is 0; a returning agent keeps the coat it had and nothing more is saved. Tests: Task 4 (`agentcat.test.mjs`: "when all 16 coats are taken…", "a default coat that a stored coat has replaced…", "a random source that misbehaves…"); Task 8 "an agent gets its coat the first time it is seen, once…".
3. **Lost, late and repeated subagent events.** A stop that never comes, a tool or permission event after the stop or for an id that never started, a repeated start, a ninth kitten, two sessions of one agent in one pill, a subagent's own `Stop`, an approval that times out while a kitten waits on it, an event with no time. Expected: stale kittens go on the parent's stop (or its error), the session's end or the sweep that comes with the cat falling asleep (a working cat's timer sweeps nothing, so a live subagent in a long, silent step stays); a late event brings nothing back; at most 8; malformed events change nothing; the kitten stops waiting when the approval is answered or times out. Tests: Task 11 ("a late event brings nothing back…", "a lost stop…", "at most eight kittens…", "a time that is not a finite number…"), `subagents.test.mjs` ("the parent's Stop and SessionEnd…"); Task 12 ("a subagent's own approval…", "falling asleep sweeps the kittens…", "a working cat's timer sweeps nothing…", "a kitten that was busy lately survives the sweep…").
4. **An island with nothing to show in Two cats mode.** No other agent, a focus that is an integration, the second cat's agent focused by a click, the second agent's pill leaving the row, a mode switched while kittens are leaving, a hidden island with kittens. Expected: cat 2 idles with no badge and a click on it does nothing; integrations are never the second cat; nothing is drawn twice; kittens are not drawn in the other expanded views, and a hidden island requests no frame. Tests: Task 4 (`cast.test.mjs`: "Two cats…", "tasks that are not a list…"), `places.test.mjs`; Task 8 "the cast follows the settings…"; Task 10 (`two-cats.test.mjs`: "the island…", "a click on the second cat…"); Task 13 "the island's layer…"; Task 14 Step 3, the zero-frame check for the hidden island.
5. **The smallest and the blinking eye, and the black coats'.** Ø6 heads (the floors of the catchlight and the rim), a squint just above and below the threshold, the biggest gaze, a kitten, an expression scale of 0 or 1.5, numbers that are not numbers, a coat id that is not an exact bright one (`Midnight`, `midnight `, a list, no id), a kitten of a black coat. Expected: the floors hold, the pupil never leaves the iris (bright or not), under 0.22 the eye is the closed line (the same for both), nothing is NaN; only the exact ids `midnight`, `oreo` and `mocha` glow, kittens too, and no other coat changes. Tests: Task 1 ("the pupil never leaves the iris…", "the floors hold…", "a number that is not a number…", "only an exact coat id in the bright list is bright…"); Task 2 `renderer-eyes.test.mjs` ("a blink or a squint…", "every coat and kitten, every resting shape…", "the black coats' eyes glow…").

---

## File Structure

All paths are under `windows/` unless they say otherwise.

| Path | Responsibility |
|---|---|
| `src/cat/smalleye.ts` | New. `SMALL_EYE`, `usesSmallEye`, `smallEye`: the small coloured eye's geometry, a port of "Small eyes" in `cat-core.js`. |
| `src/cat/renderer.ts` | The compact branch draws it (`smallEyeDraw`); `DrawOptions.eyes: "ink"` keeps the old pills for the contact sheet and the bench. |
| `src/cat/display.ts` | New. The Display settings: `DISPLAY_MODES`, `cleanPair`, `cleanAgentCats`, `cleanDisplaySettings`, the whole block (`CatBlock`, `cleanCatBlock`, `withCatSettings`) and the Display rows' edit helpers. |
| `src/cat/agentcat.ts`, `src/cat/cast.ts` | New. `agentCatFor`, `rerollAgentCat`, `assignAgentCats`, `pickCat`; `castOf`, `busyRank`, `PILL_ROW`. |
| `src/cat/kittens.ts`, `src/island/subagents.ts`, `src/cat/kittendraw.ts` | New. `kittenStep` and the places of the kittens; the hook event to kitten event mapping; the kittens' engines and their drawing. |
| `src/cat/engine.ts`, `src/cat/settings.ts` | `BotEngine.setCoat` (a coat from the caller, never overwritten by the Main cat) and `collarStyle` (per coat, from `catCfg.collars`, which `applyCatSettings` fills). |
| `src/core/state.ts`, `src/core/pills.ts`, `src/core/layout.ts` | `Settings.cat` is the whole block; a last-event time per pill, `State.cast`, `pillRow`, `giveCoats`, the kittens' lists; `agentLabel` and `pillColor`; `PAIR` and `pairPlacement`. |
| `src/island/island.ts`, `src/island/hooks.ts`, `src/island/sleep.ts`, `src/main.ts` | The second cat, the kittens' overlay, the coats and the cast at every cat; the hook handlers feed the kittens; the sleep timer sweeps; the dev-only `__nm` and `?display=`. |
| `src/cat/minibots.ts`, `src/views/views.ts`, `src/upload/canvas.ts`, `src/cat/greeting.ts`, `src/style.css` | The pills and the grid wear the cast's coats, the pills' kitten strips, the second line of the Two cats ticker, the drop view's coat, the greeting's session cats and pair; new CSS rules only. |
| `src/settings/display.ts`, `src/settings/cat.ts`, `src/settings/settings.css`, `src/settings/main.ts` | New and changed. The Display rows, their live preview, the pair's pickers and the agents' list; the Cat section's host holds the whole block; new CSS classes only. |
| `src/cat/dev.ts` | The `?dev` page: a "Small eyes" panel (the contact sheet at 2x and 1x) and a frame-time bench. |
| `src-tauri/src/cat_settings.rs`, `src-tauri/src/settings.rs`, `hook/src/main.rs` | The Rust twin of the Display clean-up (`clean_display_settings`, `clean_cat_block`, `block_default`); `sanitized` cleans the whole block; a relay test that `agent_id` and `agent_type` pass through. |
| `scripts/cat-tests/*.test.mjs` | New: `smalleye`, `renderer-eyes`, `display`, `agentcat`, `cast`, `places`, `settings-ui`, `coat`, `state-cast`, `sites`, `two-cats`, `kittens`, `subagents`, `kitten-wiring`, `kittendraw`. Changed: `fake-canvas.mjs` (gradient stops and texts), `renderer`, `collar-wiring`, `follow` and `greeting` (pins that moved). |
| `README.md`, `../CLAUDE.md`, `../ARCHITECT.md` | The docs of what was added and the Windows lines of the two guides. **`../.github/workflows/windows-tests.yml` needs no change:** it already runs on `windows/**` and `tests/fixtures/cat/**`, which cover every new file. |

**Staged edits.** Most tasks edit files earlier tasks created or changed. Every edit below is a Python script whose replacements assert that the find text occurs exactly once; the text is what the tree has after the tasks before it. Apply an edit with nothing else changed. If a find text occurs zero or two times, stop and report: the tree is not what the plan expects.

## Tasks and agents

CLAUDE.md: the lightest model that fits. Tasks 1, 3, 4, 11 and 14 give every line of their code and a run or two of a test: transcription, so `nm-implementer-light` (Haiku 4.5; Task 14 also runs a headless browser for one check). The others are multi-file with their code given, and some run a browser, Docker or the island: `nm-implementer` (Sonnet 5.5, medium). Each task is then reviewed by `nm-reviewer`, and the whole branch by `nm-reviewer-deep` after Checkpoint 3. If a step's expected output differs and the cause is not obvious (a fixture replay that fails after a careful transcription, a Rust compile error, a layout that overlaps), hand that task to `nm-implementer-deep`.

| # | Task | Agent | Review |
|---|---|---|---|
| 1 | The small eye's geometry in TypeScript (replays `small-eye-cases.json`) | `nm-implementer-light` | `nm-reviewer` |
| 2 | The compact cats draw it: the renderer, the `?dev` contact sheet, the frame time | `nm-implementer` | `nm-reviewer` |
| 3 | The Display settings in TypeScript (replays `display-cases.json`) | `nm-implementer-light` | `nm-reviewer` |
| 4 | The agents' coats, the cast and the pair's places (replay `agent-cat-cases.json` and `cast-cases.json`) | `nm-implementer-light` | `nm-reviewer` |
| 5 | The Display settings in Rust, carried through `settings.rs`; the relay keeps `agent_id` | `nm-implementer` | `nm-reviewer` |
| 6 | An engine's coat comes from the caller; the collar is looked up per coat | `nm-implementer` | `nm-reviewer` |
| 7 | The Settings screen: Display, preview, pair, Cats for your agents, Main cat | `nm-implementer` | `nm-reviewer` |
| | **Checkpoint 1:** the owner looks at the eyes and Settings | the executing session | |
| 8 | State: last-event time per pill, the cast, the agents' coats | `nm-implementer` | `nm-reviewer` |
| 9 | Every cat wears the cast: the big cat, pills, grid, greeting session cats, drop view | `nm-implementer` | `nm-reviewer` |
| 10 | The Two cats layout and the pair's arrival in the greeting | `nm-implementer` | `nm-reviewer` |
| 11 | Kittens: the reducer, the places and the hook-event mapping (replay `kitten-cases.json`) | `nm-implementer-light` | `nm-reviewer` |
| 12 | Kittens in State, the hook handlers, the sweep when the cat falls asleep | `nm-implementer` | `nm-reviewer` |
| 13 | Drawing the kittens: beside the big cat and the pair, on the pills | `nm-implementer` | `nm-reviewer` |
| | **Checkpoint 2:** the owner looks at the modes and the kittens | the executing session | |
| 14 | The docs and the final checks | `nm-implementer-light` | `nm-reviewer` |
| | **Checkpoint 3:** the owner signs off | the executing session | |
| Final | Whole-branch review | `nm-reviewer-deep` | none |

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). Ponytail never cuts what this plan or the spec asks for, nor tests, security or privacy rules. The agents of Tasks 2, 7, 10, 13 and 14 also load `playwright-cli`.

**Controller brief** (what the main session sends the worktree session once its model is set):

> Run `docs/superpowers/plans/2026-10-08-b-tauri-display-kittens.md` with `superpowers:subagent-driven-development`, task by task, on branch `b-tauri/display-kittens`. Do its Setup first. Dispatch each task to the agent the plan's "Tasks and agents" table names, then to `nm-reviewer`; fix what the review finds before the next task. Put the plan's SUBAGENT RULES block (Global Constraints) in every brief. Run Tasks 1 to 7, then stop and report to the main session for Checkpoint 1; after the owner's reply run Tasks 8 to 13 and stop for Checkpoint 2; after the owner's reply run Task 14 and stop for Checkpoint 3; after the owner's OK dispatch `nm-reviewer-deep` over the whole branch. No agent ever starts the Tauri app, launches or quits a NotchMeow build, installs anything or uses the network; Rust only through `windows/scripts/cargo-linux.sh` with `--target-dir /repo/windows/target/b-tauri`. Commit only as the plan's commit steps say, never push. Report: the commits; for `windows/`: `npx --no-install tsc --noEmit`, `npm run check:cat`, `npm run check:ai`, `npm run check:claude` and the `cargo test --workspace` counts; the output of `bash scripts/test-cat-contract.sh`; the frame times of Task 2 (before and after); the screenshots of the three checkpoints; the Windows `cargo check` (owed to CI); and anything you could not settle.

## Execution

**One worktree chat session** runs the whole plan: branch `b-tauri/display-kittens`, model **Sonnet 5.5 at high effort** (`ARCHITECT.md`: the app plans have many cross-task interfaces and platform APIs). It runs on a base where **B-0 is merged** (`e00ad3d` on `notchmeow/rebrand`, or any later commit: there is nothing to apply from the B-0 plan), and in parallel with the Mac twin (`2026-10-08-b-mac-display-kittens.md`), which has its own worktree. Nothing is pushed. The session never starts the Tauri app: the owner's manual checks are listed at each checkpoint.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run the Setup block of `docs/superpowers/plans/2026-10-08-b-tauri-display-kittens.md`. If any check in it fails, say so and stop. Read `CLAUDE.md`, `ARCHITECT.md`, `windows/README.md`, that plan and `docs/superpowers/specs/2026-10-08-display-modes-kittens-design.md`. Reply "ready" and stop. Do not start any task.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief above as the next message.

Before any follow-up turn, the main session checks the session is still on its configured model and effort.

## Setup (the controller, once)

- [ ] Put the session's worktree on the plan's branch, check that B-0 is merged (`e00ad3d` is an ancestor of `HEAD`: nothing of the B-0 plan is applied by this plan), check that its base has what the plan reads (B-0's five fixtures, and the contract's numbers that Tasks 1 and 11 copy), and copy the main checkout's front-end packages. This plan adds no package, so nothing is downloaded: no `npm install` or `npm ci`. `cp -c` makes an APFS clone, which is instant and takes no extra disk space. It must be a real folder, not a symlink, because `windows/.gitignore` ignores `node_modules/` only as a folder.

```bash
git status                                   # must be clean
git switch -c b-tauri/display-kittens notchmeow/rebrand
git merge-base --is-ancestor e00ad3d HEAD && echo "B-0 is merged (e00ad3d)"   # if this prints nothing, stop
git log --oneline -3
git ls-files tests/fixtures/cat/display-cases.json tests/fixtures/cat/agent-cat-cases.json tests/fixtures/cat/cast-cases.json tests/fixtures/cat/kitten-cases.json tests/fixtures/cat/small-eye-cases.json
git ls-files docs/superpowers/plans/2026-10-08-b-tauri-display-kittens.md   # this plan's path: it is tracked, so the worktree has it
cp -cR "/path/to/notchmeow/windows/node_modules" windows/node_modules
git status --short                           # still empty: the copy is ignored
cd windows && node --version                 # 22.6 or newer
```

`B-0 is merged (e00ad3d)` must print, and so must the five fixture paths (if one is missing B-0 is not merged: stop) and so must the plan's path (if it prints nothing, the plan is not committed on this branch: stop).

- [ ] Check that the contract is the one this plan was written against: the small eye's numbers (with the black coats' `bright` list and `brightPupil`) and the kittens' places are copied into Tasks 1 and 11, and a later change to either must be copied there first. (The pair's places in `PAIR` are the prototype's, cat 2 at 114, and are not in the core.)

```bash
node -e '
const core = require("./design/prototype/cat-core.js"), assert = require("node:assert/strict");
const json = (v) => JSON.parse(JSON.stringify(v));
assert.deepEqual(json(core.SMALL_EYE), {"iris":{"w":0.42,"h":0.46},"pupil":{"w":0.18,"h":0.4},"wide":{"w":1.16,"h":1.12},"dot":{"iris":[0.42,0.42],"pupil":[0.26,0.26]},"tired":{"open":0.42},"light":{"x":-0.11,"y":-0.1,"r":0.075,"minR":0.45},"rim":{"k":0.05,"min":0.5},"travel":{"x":0.2,"y":0.08},"closeBelow":0.22,"pupilFit":0.87,"kitten":{"w":1.2,"h":1.32},"line":{"width":0.045,"minWidth":1,"curve":0.4},"bright":["midnight","oreo","mocha"],"brightPupil":{"w":0.12}});
assert.deepEqual(json(core.KITTEN_PLACES), {"bigExpanded":{"unit":"D","max":3,"d":0.25862068965517243,"x0":0.41379310344827586,"y0":0.5862068965517241,"step":0.3103448275862069,"align":"start","moreSize":0.2},"bigCompact":{"unit":"D","max":2,"d":0.6,"x0":1.1,"y0":0.25,"step":0.65,"align":"start","moreAt":[2.1,-0.5],"moreSize":0.25},"pairCompact":{"unit":"D","max":0,"label":{"x":1.1,"y":0.3,"size":0.5}},"pairExpanded":{"unit":"D","max":3,"d":0.25862068965517243,"x0":0,"y0":0.5862068965517241,"step":0.3103448275862069,"align":"center","moreAt":[0,0.8620689655172413],"moreSize":0.2},"pill":{"unit":"H","max":3,"d":0.5357142857142857,"x0":-0.625,"y0":0,"step":-0.5714285714285714,"align":"start","moreSize":0.36}});
assert.equal(core.KITTEN_MAX, 8); assert.equal(core.KITTEN_LEAVE_MS, 600); assert.equal(core.PILL_ROW, 4);
assert.deepEqual(core.DISPLAY_MODES, ["one", "perAgent", "two"]);
console.log("the contract is the one this plan was written against");
'
```

Expected: `the contract is the one this plan was written against`. If an assertion fails, stop and tell the main session which number differs.

- [ ] Check that the starting point is green.

```bash
cd windows
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1
(cd .. && bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓ [0-9]+ fixture files|✓ two generator")
docker image inspect notchmeow-linux-dev >/dev/null && echo "image ok"
```

Expected: `tsc exit 0` with no type error before it, `ℹ tests 166`, `ℹ pass 166`, `ℹ fail 0`, `All AI UI checks passed`, `All Claude Code UI checks passed`, `# tests 231`, `# pass 231`, `# fail 0`, `✓ 14 fixture files match cat-core.js`, `✓ two generator runs write identical bytes` and `image ok`. If `image ok` does not print, do the TypeScript tasks only and report it (Task 5 needs the image).

## How to run this plan

**Blocks.** A code step is a `bash` block: either a file written with `cat > path <<'EOF'` (the file's exact content) or a Python script whose `edit` helper replaces text that must occur exactly once in the file it names, or a plain command. Run each block from the repository root, as it is. Never type a block from memory and never "improve" one. Every `Run:` line is run from the repository root; `Expected:` says what it prints. A `Run:` line that starts with `cd windows` ends in `cd ..` and came back.

**Red first.** Each task writes its tests, runs them to see them fail, writes the code, and runs them to see them pass. A step that proves a check can bite changes a line, runs the check, and puts the line back: it is never committed.

**Pixels.** There are no pixel tests. The look is checked by eye in a headless browser (`playwright-cli`, with Vite alone, never the Tauri app), and the frame time by the `?dev` page's own readout and a same-build bench. Keep every screenshot in `${TMPDIR:-/tmp}/b-tauri-shots`, and say what you saw.

**The owner's checkpoints** are marked `Checkpoint N`: the session stops there, sends the owner the pictures and the list, and waits. Never start the next stage before the owner's OK.

---

# Stage 1: the small coloured eyes

### Task 1: The small eye's geometry in TypeScript

**Agent:** `nm-implementer-light`.

**Files:**
- Create: `windows/src/cat/smalleye.ts`
- Test: `windows/scripts/cat-tests/smalleye.test.mjs`

**Interfaces:**
- Consumes: B-0's `small-eye-cases.json` (keys `constants`, `shapes`, `bright`, `uses`, `sizes`, `squints`, `gazes`, `scales`, `others`, `hostile`, `brights`), and from the cat code `kittenOf`, `PRESETS` (a test), `util.mjs`'s `load`, `same`, `near`, `finite`.
- Produces: `SMALL_EYE`, `SMALL_EYE_SHAPES`, `usesSmallEye(shape, sd)`, `smallEye(shape, {sd, R, es, open, yaw, pitch, kitten, cat})` returning `null` (an ink shape), `{shape, closed: false, iris: {rx, ry, r}, pupil: {x, y, rx, ry}, light: {x, y, r}, rim[, flat: true]}` (a black coat's eye, selected by the exact coat id in `cat`, has `flat: true`, `rim: 0` and a pupil `brightPupil.w` wide) or `{shape, closed: true, line: {x0, y0, cx, cy, x1, y1, width}}`; types `SmallEye`, `SmallEyeOpts`. Task 2 draws it.

- [ ] **Step 1: Write the failing test**

It replays every row of the fixture (the bright rows too), and holds the cases a JSON file cannot (NaN, an infinity, text for a number, a `cat` that is not an exact bright id), the pupil-in-the-iris brute force (bright or not), the floors, and the kitten's ratio.

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/smalleye.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { SMALL_EYE, SMALL_EYE_SHAPES, smallEye, usesSmallEye } from "../../src/cat/smalleye.ts";
import { PRESETS, kittenOf } from "../../src/cat/presets.ts";
import { finite, load, near, same } from "./util.mjs";

// The small coloured eye, replayed from tests/fixtures/cat/small-eye-cases.json (B-0), and the inputs a JSON file cannot hold. The black coats' eyes are bright (`cat`).
const fx = load("small-eye-cases.json");
const INK = ["line", "flat", "happy", "closed", "spiral", "heart", "star"];

test("the constants and the shape list are the fixture's", () => {
  same(SMALL_EYE, fx.constants, "SMALL_EYE");
  assert.deepEqual([...SMALL_EYE_SHAPES], fx.shapes);
});

test("usesSmallEye replays the fixture: the four resting shapes and the left eye of a wink; every expression stays ink", () => {
  assert.equal(fx.uses.length, 26);
  for (const c of fx.uses) assert.equal(usesSmallEye(c.shape, c.sd), c.out, `${c.shape} ${c.sd}`);
  for (const s of INK) for (const sd of [-1, 1]) assert.equal(usesSmallEye(s, sd), false, `${s} ${sd}`);
  for (const bad of ["bogus", "", "PILL", undefined, null, 7, {}]) assert.equal(usesSmallEye(bad, -1), false, String(bad));
  assert.equal(usesSmallEye("wink", undefined), false, "a wink with no side is not the left eye");
});

test("smallEye replays every row of the fixture: sizes, squints, gazes, expression scales, other shapes and hostile inputs", () => {
  for (const g of ["sizes", "squints", "gazes", "scales", "others", "hostile"]) {
    assert.ok(fx[g].length > 0, g);
    fx[g].forEach((c, i) => same(smallEye(c.shape, c.o), c.out, `${g} ${i}: ${c.shape} ${JSON.stringify(c.o)}`));
  }
  assert.deepEqual([fx.sizes.length, fx.squints.length, fx.gazes.length, fx.scales.length], [56, 72, 72, 20]);
});

test("smallEye replays the bright rows: the black coats get a flat eye with no rim and a thinner pupil, and the other coats and a hostile `cat` stay normal", () => {
  assert.deepEqual([...SMALL_EYE.bright], fx.bright);
  assert.equal(fx.brights.length, 6);
  fx.brights.forEach((c, i) => same(smallEye(c.shape, c.o), c.out, `brights ${i}: ${c.shape} ${JSON.stringify(c.o)}`));
});

test("only an exact coat id in the bright list is bright (another coat, another case, a padded id, text that is not a string and no cat are normal); a kitten of a black coat keeps it", () => {
  const normal = smallEye("pill", { R: 10 });
  assert.ok(normal && !normal.closed);
  assert.equal("flat" in normal, false, "a normal eye has no flat key");
  for (const cat of ["momo", "shrimpy", "Midnight", "MIDNIGHT", " midnight", "midnight ", "midnight\n", "", "mid", ["midnight"], { 0: "midnight" }, 7, null, undefined, true]) {
    same(smallEye("pill", { R: 10, cat }), normal, `cat ${JSON.stringify(cat)}`);
  }
  for (const cat of SMALL_EYE.bright) for (const kitten of [false, true]) {
    const b = smallEye("pill", { R: 10, cat, kitten }), n = smallEye("pill", { R: 10, kitten });
    assert.ok(b && n && !b.closed && !n.closed);
    assert.equal(b.flat, true, `${cat} kitten ${kitten}`);
    assert.equal(b.rim, 0);
    near(b.pupil.rx / n.pupil.rx, SMALL_EYE.brightPupil.w / SMALL_EYE.pupil.w);
    same({ iris: b.iris, light: b.light, pupilY: b.pupil.ry }, { iris: n.iris, light: n.light, pupilY: n.pupil.ry }, `${cat} kitten ${kitten}: only the pupil's width, the rim and the fill change`);
  }
});

test("a bright eye keeps the dot's round, dilated pupil and the closed line of a blink", () => {
  same(smallEye("dot", { R: 10, cat: "oreo" })?.pupil, smallEye("dot", { R: 10 })?.pupil, "the dot's pupil");
  const shut = smallEye("pill", { R: 10, open: 0.1 }), brightShut = smallEye("pill", { R: 10, open: 0.1, cat: "midnight" });
  assert.equal(shut?.closed, true);
  same(brightShut, shut, "a closed eye is the same line");
  assert.equal("flat" in (brightShut ?? {}), false);
});

test("a number that is not a number (NaN, an infinity, text) is the default, and nothing is ever NaN: what a JSON fixture cannot hold", () => {
  const plain = smallEye("pill", { R: 10 });
  for (const bad of [NaN, Infinity, -Infinity, "9", null, undefined, {}, []]) {
    same(smallEye("pill", { R: 10, es: bad, open: bad, yaw: bad, pitch: bad }), plain, `es, open, yaw and pitch ${String(bad)}`);
  }
  for (const bad of [NaN, Infinity, -Infinity, "9", null, undefined]) {
    const e = smallEye("pill", { R: bad });
    finite(e);
    same(e, smallEye("pill", { R: 0 }), `R ${String(bad)}`);
  }
  finite(smallEye("pill", { R: 1e300, es: 1e300 }));
  finite(smallEye("wide", { R: -5, es: -2, open: 7, yaw: 1e9, pitch: -1e9 }));
  same(smallEye("pill", null), smallEye("pill", { R: 0 }), "no options at all: R 0, a point of an eye");
  assert.equal(smallEye("pill", [])?.shape, "pill");
  assert.equal(smallEye("wink", { sd: 1, R: 10 }), null, "the right eye of a wink stays ink");
  assert.equal(smallEye("wink", { sd: "1", R: 10 })?.shape, "wink", "an sd that is not exactly 1 is the left eye");
});

test("the pupil never leaves the iris, at every squint, gaze, shape, kitten and expression scale", () => {
  for (const shape of ["pill", "wide", "dot", "tired", "wink"]) for (const kitten of [false, true]) for (const cat of [undefined, "midnight"]) for (const es of [0.5, 1, 1.5]) {
    for (let open = 0.25; open <= 1.001; open += 0.125) for (const yaw of [-2, -0.62, 0, 0.62, 2]) for (const pitch of [-1, -0.5, 0, 0.5, 1]) {
      const e = smallEye(shape, { sd: -1, R: 12, es, open, yaw, pitch, kitten, cat });
      if (!e || e.closed) continue;
      // The farthest point of the pupil ellipse from the iris's centre, inside the iris ellipse (a point test on the extreme corners).
      for (const [cx, cy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const x = e.pupil.x + cx * e.pupil.rx, y = e.pupil.y + cy * e.pupil.ry;
        assert.ok((x / e.iris.rx) ** 2 + (y / e.iris.ry) ** 2 <= 1 + 1e-9, `${shape} kitten ${kitten} cat ${cat} es ${es} open ${open} yaw ${yaw} pitch ${pitch}`);
      }
    }
  }
});

test("the floors hold at the smallest heads: a catchlight of 0.45 px and a rim of 0.5 px", () => {
  for (const R of [0, 1, 3, 5, 5.9, 6]) {
    const e = smallEye("pill", { R });
    if (e && !e.closed) { near(e.light.r, 0.45); near(e.rim, 0.5); }
  }
  const big = smallEye("pill", { R: 20 });
  assert.ok(big && !big.closed);
  near(big.light.r, 1.5);
  near(big.rim, 1);
});

test("a kitten's eye is the coat's, 1.2 wider and 1.32 taller: what kittenOf does to a kitten's eyes", () => {
  const cat = smallEye("pill", { R: 10 }), kit = smallEye("pill", { R: 10, kitten: true });
  assert.ok(cat && kit && !cat.closed && !kit.closed);
  near(kit.iris.rx / cat.iris.rx, SMALL_EYE.kitten.w);
  near(kit.iris.ry / cat.iris.ry, SMALL_EYE.kitten.h);
  const k = kittenOf(PRESETS.momo);
  near(k.eye.w / PRESETS.momo.eye.w, SMALL_EYE.kitten.w);
  near(k.eye.h / PRESETS.momo.eye.h, SMALL_EYE.kitten.h);
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/smalleye.test.mjs 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|^# (tests|pass|fail)" | cut -c1-90; cd ..`
Expected: a line with `ERR_MODULE_NOT_FOUND` (the module `smalleye.ts` does not exist yet), `# tests 1`, `# pass 0` and `# fail 1`.

- [ ] **Step 3: Write the module**

```bash
mkdir -p windows/src/cat
cat > windows/src/cat/smalleye.ts <<'EOF'
// The small coloured eye (sub-project B, spec §4): below a head of Ø28 the plain resting eyes (pill, wide, dot and tired) are a round iris in the coat's
// colours, a slit pupil, one catchlight and a thin rim, instead of the cat's flat ink pill. A port of "Small eyes" in design/prototype/cat-core.js (the
// tie-breaker; fixture tests/fixtures/cat/small-eye-cases.json; docs/CAT-CONTRACT.md "Small coloured eyes"). This is the geometry only, in px of the eye's
// own frame (its centre is the origin, y down, before the renderer's foreshortening); the renderer paints it with the coat's colours (smallEyeDraw).
// The three black coats (and their kittens) glow: `cat` names the coat, and a bright eye comes back `flat` with no rim and a thinner pupil.
// Imports nothing, so the plain-Node checks (npm run check:cat) can load it.

/** The resting shapes that become a small coloured eye. The left eye of a wink is one too (the right is an ink arc). */
export const SMALL_EYE_SHAPES = ["pill", "wide", "dot", "tired"] as const;

/**
 * The numbers, pinned by small-eye-cases.json. Sizes are fractions of u = R * es (the head radius times the expression scale) and are full widths and
 * heights. wide is the iris times (1.16, 1.12); dot is a round iris with a round, dilated pupil; tired shows at most `open` 0.42 of the eye. The pupil moves
 * with the gaze (yaw / 0.62, pitch / 0.5, each held to -1 to 1) by at most `travel` of the iris's half-axes, so it never leaves it. A blink or a squint
 * under `closeBelow` of the eye's height closes it to a line. A kitten's eye is `kitten.w` times wider and `kitten.h` times taller. The black coats
 * `bright` (an explicit list, so the other coats do not move) are drawn with a flat fill of the lighter iris colour, no rim, and a slit pupil `brightPupil.w` wide.
 */
export const SMALL_EYE = {
  iris: { w: 0.42, h: 0.46 }, pupil: { w: 0.18, h: 0.4 }, wide: { w: 1.16, h: 1.12 }, dot: { iris: [0.42, 0.42], pupil: [0.26, 0.26] }, tired: { open: 0.42 },
  light: { x: -0.11, y: -0.1, r: 0.075, minR: 0.45 }, rim: { k: 0.05, min: 0.5 }, travel: { x: 0.2, y: 0.08 }, closeBelow: 0.22, pupilFit: 0.87,
  kitten: { w: 1.2, h: 1.32 }, line: { width: 0.045, minWidth: 1, curve: 0.4 }, bright: ["midnight", "oreo", "mocha"], brightPupil: { w: 0.12 },
} as const;

/** True when the renderer draws shape `shape` of the eye `sd` (-1 left, 1 right) with smallEye at the compact level, and false when it stays ink. */
export const usesSmallEye = (shape: unknown, sd: unknown): boolean =>
  (SMALL_EYE_SHAPES as readonly unknown[]).includes(shape) || (shape === "wink" && typeof sd === "number" && sd < 0);

export interface SmallEyeOpts {
  /** -1 the left eye (the default), 1 the right. */
  sd?: number;
  /** The head radius in px, held to 0 up to 10000. */
  R?: number;
  /** The pose's expression scale, held to 0 up to 10 (default 1). */
  es?: number;
  /** The pose's `open * (1 - lid)`, held to 0…1 (default 1). */
  open?: number;
  yaw?: number;
  pitch?: number;
  /** The preset's `kitten` flag. */
  kitten?: boolean;
  /** The coat's id: only an exact string in `SMALL_EYE.bright` makes a bright eye; anything else (or nothing) is a normal one. A kitten keeps its coat's id. */
  cat?: string;
}
export interface SmallEyeOpen {
  shape: string;
  closed: false;
  iris: { rx: number; ry: number; r: number };
  pupil: { x: number; y: number; rx: number; ry: number };
  light: { x: number; y: number; r: number };
  rim: number;
  /** Present (true) only for a bright coat's eye: the renderer fills the iris flat, with the lighter of the coat's two iris colours, and draws no rim (`rim` is 0). */
  flat?: true;
}
export interface SmallEyeShut {
  shape: string;
  closed: true;
  line: { x0: number; y0: number; cx: number; cy: number; x1: number; y1: number; width: number };
}
export type SmallEye = SmallEyeOpen | SmallEyeShut;

const num = (v: unknown, d: number): number => (typeof v === "number" && Number.isFinite(v) ? v : d);

/**
 * One small eye: null for a shape that is not a small eye (draw the ink shape), else the open eye or, for a blink or squint under 0.22, the closed line (an
 * arc in the ink colour at alpha 0.9). A value that is not a number is taken as its default; nothing is ever NaN.
 */
export function smallEye(shape: unknown, opts?: SmallEyeOpts | null): SmallEye | null {
  const o: SmallEyeOpts = opts !== null && typeof opts === "object" && !Array.isArray(opts) ? opts : {};
  if (!usesSmallEye(shape, o.sd === 1 ? 1 : -1)) return null;
  const S = SMALL_EYE, name = shape as string;
  const R = Math.max(0, Math.min(1e4, num(o.R, 0))), u = R * Math.max(0, Math.min(10, num(o.es, 1)));
  const sh = name === "wink" ? "pill" : name, kit = o.kitten === true, kw = kit ? S.kitten.w : 1, kh = kit ? S.kitten.h : 1;
  const bri = typeof o.cat === "string" && (S.bright as readonly string[]).includes(o.cat);
  const open = Math.max(0, Math.min(1, num(o.open, 1))), op = sh === "tired" ? Math.min(open, S.tired.open) : open;
  const base: readonly number[] = sh === "dot" ? S.dot.iris : [S.iris.w * (sh === "wide" ? S.wide.w : 1), S.iris.h * (sh === "wide" ? S.wide.h : 1)];
  const rx0 = (base[0] / 2) * kw * u, ry0 = (base[1] / 2) * kh * u;
  if (op < S.closeBelow) {
    return { shape: name, closed: true, line: { x0: -rx0, y0: 0, cx: 0, cy: S.line.curve * ry0, x1: rx0, y1: 0, width: Math.max(S.line.minWidth, S.line.width * u) } };
  }
  const ry = ry0 * op, pw = ((sh === "dot" ? S.dot.pupil[0] : bri ? S.brightPupil.w : S.pupil.w) / 2) * kw * u;
  const pry = Math.min(((sh === "dot" ? S.dot.pupil[1] : S.pupil.h) / 2) * kh * u, S.pupilFit * ry);
  const gx = Math.max(-1, Math.min(1, num(o.yaw, 0) / 0.62)), gy = Math.max(-1, Math.min(1, num(o.pitch, 0) / 0.5));
  const px = gx * S.travel.x * rx0, py = -gy * S.travel.y * ry;
  return {
    shape: name, closed: false, iris: { rx: rx0, ry, r: Math.max(rx0, ry) }, pupil: { x: px, y: py, rx: pw, ry: pry },
    light: { x: (S.light.x / (S.iris.w / 2)) * rx0, y: (S.light.y / (S.iris.h / 2)) * ry, r: Math.max(S.light.r * u, S.light.minR) },
    rim: bri ? 0 : Math.max(S.rim.k * u, S.rim.min), ...(bri ? { flat: true as const } : {}),
  };
}
EOF
```

- [ ] **Step 4: Run the test and the type check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/smalleye.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"; npx --no-install tsc --noEmit; echo "tsc exit $?"; cd ..`
Expected: `# tests 10`, `# pass 10`, `# fail 0`, `tsc exit 0`.

- [ ] **Step 5: Prove the closing threshold bites (not committed)**

The eye closes to a line under 0.22 of its height, as the realistic eye does. Change that number and the fixture rows for squints must fail.

```bash
python3 - <<'PY'
import subprocess
p = 'windows/src/cat/smalleye.ts'
s = open(p, encoding='utf-8').read()
was = 'closeBelow: 0.22,'
assert s.count(was) == 1
run = lambda: print(subprocess.run('cd windows && node --experimental-strip-types --test scripts/cat-tests/smalleye.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"', shell=True, capture_output=True, text=True).stdout, end='')
open(p, 'w', encoding='utf-8').write(s.replace(was, 'closeBelow: 0.2,'))
run()
open(p, 'w', encoding='utf-8').write(s)
run()
PY
```

Expected: the first run prints `not ok 1 - the constants and the shape list are the fixture's`, `not ok 3 - smallEye replays every row of the fixture: sizes, squints, gazes, expression scales, other shapes and hostile inputs`, `# pass 8` and `# fail 2`; after the line is put back, `# pass 10` and `# fail 0`.

- [ ] **Step 6: Run the whole cat check and commit**

Run: `cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `ℹ tests 176`, `ℹ pass 176`, `ℹ fail 0` (the 166 before, and the 10 of this task).

```bash
git add windows/scripts/cat-tests/smalleye.test.mjs windows/src/cat/smalleye.ts
git commit -m "feat(cat): the small coloured eye's geometry, a port of smallEye

usesSmallEye and smallEye replay small-eye-cases.json within 1e-9, with their own tests for numbers a JSON file cannot hold
and a brute-force check that the pupil never leaves the iris. Nothing draws it yet.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 2: The compact cats draw it: the renderer, the `?dev` contact sheet, the frame time

**Agent:** `nm-implementer`. Loads `playwright-cli`.

**Files:**
- Modify: `windows/src/cat/renderer.ts`, `windows/src/cat/dev.ts`, `windows/scripts/cat-tests/renderer.test.mjs`, `windows/scripts/cat-tests/fake-canvas.mjs`
- Create: `windows/scripts/cat-tests/renderer-eyes.test.mjs`

**Interfaces:**
- Consumes: Task 1's `smallEye` (with its `cat` input), `SmallEye` (with `flat`); the renderer's `drawHeadPass` (the compact branch of the eye loop), `inkEye`, `DrawOptions`, `THEME.cat.pupil`; `dev.ts`'s `section`, `fit`, `button`, `row`, `stillView`, `kittenOf`.
- Produces: `DrawOptions.eyes?: "ink"`; the renderer's `smallEyeDraw` (the iris as a radial gradient from `iris[0]` to `iris[1]` at the iris's radius, `irisR` for the right eye of an odd-eyed coat; the pupil in `THEME.cat.pupil`; the catchlight white at 0.92; the rim in `liner`; the closed line in `ink` at 0.9; **for a black coat (`smallEye` says `flat`) the iris is one flat fill of the lighter of the two iris colours by luminance and there is no rim**; the coat's id, `p.name` (a kitten keeps its coat's), is what the renderer passes as `cat`); the `?dev` panel "Small eyes" with `#eyes2`, `#eyes1` and a **Measure** button writing `#eye-bench`; `fakeCanvas().seen.stops` (every gradient stop colour).

- [ ] **Step 1: Measure the frame time before** (the island's frame budget is re-measured, spec §4)

The `?dev` page has a readout of its own: the time to draw its live cats (and its still sheet) per frame, smoothed. Headless Chromium draws in software, so the numbers are not the app's: they compare this build with itself. Write the two numbers down.

```bash
SHOTS="${TMPDIR:-/tmp}/b-tauri-shots"; mkdir -p "$SHOTS"
cat > "$SHOTS/pw2x.json" <<'PWJSON'
{ "browser": { "contextOptions": { "viewport": { "width": 1280, "height": 900 }, "deviceScaleFactor": 2 } } }
PWJSON
(cd windows && npx --no-install vite --port 14581 > "$SHOTS/vite.log" 2>&1 &)
sleep 4
cd "$SHOTS"
playwright-cli -s=eyes open "http://127.0.0.1:14581/?dev" --config=pw2x.json | grep -E "Console"
sleep 4
playwright-cli -s=eyes --raw eval "[...document.querySelectorAll('p')].map(p => p.textContent).filter(t => t.startsWith('Drawing per frame')).join('|')"
playwright-cli -s=eyes close > /dev/null
kill $(lsof -ti tcp:14581) 2>/dev/null; sleep 1; lsof -ti tcp:14581 | wc -l
```

Expected: `- Console: 1 errors, 0 warnings` (the missing `favicon.ico`, the only error), then a line `"Drawing per frame: the 11 live cats <a> ms (the Mac's budget is 2 ms for twelve small cats plus the big one), the still sheet <b> ms."` where `<a>` is about 1 to 6 and `<b>` about 4 to 15 (the earlier Windows plan measured 2.8 to 3.2 ms for the live cats), and `0` (nothing listens on the port any more). Keep `<a>` and `<b>` as **before**.

- [ ] **Step 2: Write the failing tests**

The renderer's own test of flat fills draws its cats with the eyes as ink from now on (the iris gradient is the eye's own, and has a test of its own); the fake canvas remembers every gradient stop's colour. The black coats' eyes have no gradient at all, and a test of their own.

```bash
python3 - <<'PY'
# Task 2: the two existing test files that must move with the eyes. Run from the repository root. Every replacement asserts that its anchor is there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

# The fake canvas also remembers the colours of every gradient stop.
edit('windows/scripts/cat-tests/fake-canvas.mjs', [
    ('''/** Counts of the calls made, by name (`ctx.calls`), and what the flat-fill checks look at (`ctx.seen`): every string a `fillStyle` was set to, and the arguments of every `ellipse`. */''',
     '''/** Counts of the calls made, by name (`ctx.calls`), and what the checks look at (`ctx.seen`): every string a `fillStyle` was set to, the arguments of every `ellipse`, and the colour of every gradient stop. */'''),
    ('''const calls = {}, seen = { fillStyles: [], ellipses: [], strokeStyles: [], lineWidths: [] };''',
     '''const calls = {}, seen = { fillStyles: [], ellipses: [], strokeStyles: [], lineWidths: [], stops: [] };'''),
    ('''const gradient = { addColorStop: (...a) => note("addColorStop", a.slice(0, 1)) };''',
     '''const gradient = { addColorStop: (...a) => { seen.stops.push(a[1]); note("addColorStop", a.slice(0, 1)); } };'''),
])

# The flat-fill claim is about the coat's fills: the small coloured eyes' iris gradients are not part of it, so it draws the eyes as ink.
edit('windows/scripts/cat-tests/renderer.test.mjs', [
    ('''      drawCat(ctx, stillView(p, newPose()), 100, 80, D);
      assert.equal(gradients(ctx), 0, `${id}${kit ? " kitten" : ""} Ø${D}: flat fills, no gradient`);''',
     '''      drawCat(ctx, stillView(p, newPose()), 100, 80, D, { eyes: "ink" }); // the small coloured eyes have an iris gradient of their own: renderer-eyes.test.mjs
      assert.equal(gradients(ctx), 0, `${id}${kit ? " kitten" : ""} Ø${D}: flat fills, no gradient`);'''),
])
PY
```

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/renderer-eyes.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { drawCat, stillView } from "../../src/cat/renderer.ts";
import { layout, newPose } from "../../src/cat/geometry.ts";
import { smallEye } from "../../src/cat/smalleye.ts";
import { CAT_IDS, PRESETS, kittenOf } from "../../src/cat/presets.ts";
import { TAU } from "../../src/cat/base.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";
import { near } from "./util.mjs";

installBrowserStubs();

// The compact cat's plain resting eyes are small coloured eyes (spec §4); the expression shapes, the full cat and `eyes: "ink"` keep the ink ones. The black coats'
// eyes are bright: a flat fill, no gradient and no rim.
const draw = (p, D, extra = {}, pose = {}, shape = "pill") => {
  const ctx = fakeCanvas(), v = stillView(p, { ...newPose(), ...pose });
  v.eyeShape = () => shape;
  drawCat(ctx, v, 100, 80, D, extra);
  return ctx;
};
const BRIGHT = ["midnight", "oreo", "mocha"];
const ellipseAt = (ctx, x, y, rx, ry) => ctx.seen.ellipses.some((a) => Math.abs(a[0] - x) < 1e-9 && Math.abs(a[1] - y) < 1e-9 && Math.abs(a[2] - rx) < 1e-9 && Math.abs(a[3] - ry) < 1e-9 && a[6] === TAU);
const linerStrokes = (ctx, p) => ctx.seen.strokeStyles.filter((s) => s === p.liner).length;
const radial = (ctx) => ctx.calls.createRadialGradient || 0;
const linear = (ctx) => ctx.calls.createLinearGradient || 0;

test("a compact cat's resting eyes are two coloured irises, one gradient each (the black coats' are flat: none), and nothing else in the head is shaded", () => {
  for (const id of CAT_IDS) for (const kit of [false, true]) for (const D of [12, 20, 27]) {
    const p = kit ? kittenOf(PRESETS[id]) : PRESETS[id];
    assert.equal(radial(draw(p, D)), BRIGHT.includes(id) ? 0 : 2, `${id}${kit ? " kitten" : ""} Ø${D}`);
    assert.equal(linear(draw(p, D)), 0, `${id} Ø${D}: the flat fills stay flat`);
  }
});
test("the black coats' eyes glow: one flat fill of the lighter iris colour for each eye, no gradient, no rim, the thinner pupil and the catchlight; a kitten of the coat too; the other coats keep their rim", () => {
  const lum = (h) => { const n = parseInt(h.slice(1), 16); return 0.2126 * ((n >> 16) & 255) + 0.7152 * ((n >> 8) & 255) + 0.0722 * (n & 255); };
  const want = { midnight: "#F7D45C", oreo: "#DDEB5A", mocha: "#F6C44C" };
  for (const id of BRIGHT) for (const kit of [false, true]) {
    const p = kit ? kittenOf(PRESETS[id]) : PRESETS[id], D = 20, R = layout(p, newPose(), 0, 0, D).R;
    const lighter = lum(p.iris[0]) >= lum(p.iris[1]) ? p.iris[0] : p.iris[1], what = `${id}${kit ? " kitten" : ""}`;
    assert.equal(lighter.toUpperCase(), want[id], `${what}: the lighter of the two iris colours is the contract's`);
    const g = smallEye("pill", { sd: -1, R, es: 1, open: 1, kitten: kit, cat: id });
    assert.ok(g && !g.closed && g.flat === true && g.rim === 0, `${what}: the geometry is bright`);
    const ctx = draw(p, D), ink = draw(p, D, { eyes: "ink" });
    assert.equal(radial(ctx), 0, `${what}: no gradient`);
    assert.equal(ctx.seen.fillStyles.filter((f) => f === lighter).length - ink.seen.fillStyles.filter((f) => f === lighter).length, 2, `${what}: one flat fill of the lighter colour for each eye`);
    assert.ok(ellipseAt(ctx, 0, 0, g.iris.rx, g.iris.ry), `${what}: the iris`);
    assert.ok(ellipseAt(ctx, g.pupil.x, g.pupil.y, g.pupil.rx, g.pupil.ry), `${what}: the thin pupil`);
    assert.ok(ctx.seen.fillStyles.includes("rgba(255,255,255,.92)"), `${what}: the catchlight is kept`);
    assert.equal(linerStrokes(ctx, p), linerStrokes(ink, p), `${what}: no rim is stroked in the liner colour`);
  }
  // A normal coat's rim is the one thing that strokes in the liner colour (for a coat whose liner is its ink colour the ink pills stroke in it too, so those cannot tell).
  const withRim = CAT_IDS.filter((id) => !BRIGHT.includes(id) && PRESETS[id].liner !== PRESETS[id].ink);
  assert.ok(withRim.includes("momo") && withRim.length >= 3, withRim.join());
  for (const id of withRim) assert.equal(linerStrokes(draw(PRESETS[id], 20), PRESETS[id]) - linerStrokes(draw(PRESETS[id], 20, { eyes: "ink" }), PRESETS[id]), 2, `${id}: a normal coat has a rim on each eye`);
});

test("eyes: ink keeps the old ink pills, and the full cat is the same with or without it", () => {
  for (const id of ["momo", "snow", "latte"]) {
    assert.equal(radial(draw(PRESETS[id], 20, { eyes: "ink" })), 0, `${id} Ø20 ink`);
    for (const D of [28, 44, 66]) assert.deepEqual(draw(PRESETS[id], D, { eyes: "ink" }).calls, draw(PRESETS[id], D).calls, `${id} Ø${D}: the option changes nothing at full detail`);
  }
});

test("the expression shapes stay ink: happy, closed, spiral, heart, star, line and flat have no iris, and a wink has one", () => {
  const withIris = draw(PRESETS.momo, 20), plain = radial(withIris);
  for (const shape of ["happy", "closed", "spiral", "heart", "star", "line", "flat"]) assert.equal(radial(draw(PRESETS.momo, 20, {}, {}, shape)), 0, shape);
  assert.equal(radial(draw(PRESETS.momo, 20, {}, {}, "wink")), 1, "the left eye of a wink is coloured, the right one an ink arc");
  assert.equal(plain, 2);
  for (const shape of ["wide", "dot", "tired"]) assert.equal(radial(draw(PRESETS.momo, 20, {}, {}, shape)), 2, shape);
});

test("the iris is the coat's: Momo's gold, and an odd-eyed coat has a second colour for the right eye", () => {
  const momo = draw(PRESETS.momo, 20).seen.stops;
  assert.deepEqual(momo, [...PRESETS.momo.iris, ...PRESETS.momo.iris]);
  const snow = draw(PRESETS.snow, 20).seen.stops;
  assert.deepEqual(snow, [...PRESETS.snow.iris, ...PRESETS.snow.irisR], "Snow: one blue eye, one gold, as at full size");
});

test("the iris, pupil and rim are the contract's geometry at the head's radius, and the pupil and catchlight are the theme's and white", () => {
  const p = PRESETS.momo, D = 20, R = layout(p, newPose(), 0, 0, D).R, g = smallEye("pill", { sd: -1, R, es: 1, open: 1, yaw: 0, pitch: 0, kitten: false });
  assert.ok(g && !g.closed);
  const ctx = draw(p, D), has = (x, y, rx, ry) => ctx.seen.ellipses.some((a) => Math.abs(a[0] - x) < 1e-9 && Math.abs(a[1] - y) < 1e-9 && Math.abs(a[2] - rx) < 1e-9 && Math.abs(a[3] - ry) < 1e-9 && a[6] === TAU);
  assert.ok(has(0, 0, g.iris.rx, g.iris.ry), "the iris");
  assert.ok(has(g.pupil.x, g.pupil.y, g.pupil.rx, g.pupil.ry), "the pupil");
  assert.ok(ctx.seen.fillStyles.includes("rgba(255,255,255,.92)"), "the catchlight is white at 0.92");
  assert.ok(ctx.seen.strokeStyles.includes(p.liner) && ctx.seen.lineWidths.some((w) => Math.abs(w - g.rim) < 1e-9), "the rim is the coat's liner colour at the contract's width");
  near(g.iris.rx, 0.21 * R, 1e-9);
  const kit = kittenOf(p), gk = smallEye("pill", { sd: -1, R: layout(kit, newPose(), 0, 0, D).R, es: 1, open: 1, kitten: true });
  assert.ok(gk && !gk.closed);
  const kctx = draw(kit, D);
  assert.ok(kctx.seen.ellipses.some((a) => Math.abs(a[2] - gk.iris.rx) < 1e-9 && Math.abs(a[3] - gk.iris.ry) < 1e-9), "a kitten's iris is its own, larger one");
});

test("a blink or a squint under 0.22 closes the eye to a line in the ink colour, with no iris", () => {
  const open = draw(PRESETS.momo, 20), shut = draw(PRESETS.momo, 20, {}, { open: 0.1 });
  assert.equal(radial(shut), 0);
  assert.ok(shut.seen.strokeStyles.includes(PRESETS.momo.ink), "the line is the coat's ink");
  assert.ok((shut.calls.quadraticCurveTo || 0) >= (open.calls.quadraticCurveTo || 0) + 2, "an arc for each eye");
  assert.equal(radial(draw(PRESETS.momo, 20, {}, { open: 0.22 })), 2, "0.22 is still open");
});

test("every coat and kitten, every resting shape, squint and gaze at the compact sizes draws only finite numbers", () => {
  for (const id of CAT_IDS) for (const kit of [false, true]) for (const D of [6, 12, 20, 27]) for (const shape of ["pill", "wide", "dot", "tired", "wink"]) {
    const p = kit ? kittenOf(PRESETS[id]) : PRESETS[id];
    for (const pose of [{}, { open: 0.3, yaw: 0.6, pitch: 0.5 }, { open: 0, es: 0 }, { es: 1.5, yaw: -0.62 }]) draw(p, D, {}, pose, shape);
  }
});
EOF
```

- [ ] **Step 3: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/renderer-eyes.test.mjs scripts/cat-tests/renderer.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..`
Expected: `# tests 16`, `# pass 10`, `# fail 6` (six of the eyes test file's eight tests fail; its two tests that hold before the change, and the renderer's own eight, pass).

- [ ] **Step 4: The renderer's compact branch**

```bash
python3 - <<'PY'
# Task 2: the compact eyes of the renderer are the small coloured eyes. Run from the repository root. Every replacement asserts that its anchor is there exactly once.
p = 'windows/src/cat/renderer.ts'
s = open(p, encoding='utf-8').read()

def rep(was, now):
    global s
    assert s.count(was) == 1, was[:70]
    s = s.replace(was, now)

rep('''// Below head width Ø28 the cat is the compact drawing: ink eyes, no whiskers, and FLAT FILLS (`flatFillColors` and `FLAT_FILL` of geometry.ts:''',
    '''// Below head width Ø28 the cat is the compact drawing: small coloured eyes (an iris in the coat's colours, a slit pupil, a catchlight and a thin rim: `smallEye`
// of smalleye.ts, given the coat's id; the black coats' are flat and bright; the expression shapes stay ink), no whiskers, and FLAT FILLS (`flatFillColors` and `FLAT_FILL` of geometry.ts:''')
rep('''import { collarGeometry } from "./collar.ts";
import type { CollarGeometry } from "./collar.ts";
''', '''import { collarGeometry } from "./collar.ts";
import type { CollarGeometry } from "./collar.ts";
import { smallEye } from "./smalleye.ts";
import type { SmallEye } from "./smalleye.ts";
''')
rep('''  /** The device pixel ratio the collar's readability floors are in: default `min(2, devicePixelRatio)`, and 1 where there is no screen. */
  dpr?: number;
}''', '''  /** The device pixel ratio the collar's readability floors are in: default `min(2, devicePixelRatio)`, and 1 where there is no screen. */
  dpr?: number;
  /** `ink` draws the compact cat's plain resting eyes as the flat ink shapes they were before the small coloured eyes: the `?dev` contact sheet and frame-time check compare with them. */
  eyes?: "ink";
}''')
rep('''      } else inkEye(c, shape, sd, 0.34 * R * s.es, 0.4 * R * s.es, open, T, p.ink);
      c.restore();''', '''      } else {
        // Below Ø28: a small coloured eye for the plain resting shapes (and a wink's left eye), the flat ink shape for every expression.
        const eye = o.eyes === "ink" ? null : smallEye(shape, { sd, R, es: s.es, open, yaw: s.yaw, pitch: s.pitch, kitten: p.kitten === true, cat: p.name });
        if (eye) smallEyeDraw(c, p, sd, eye);
        else inkEye(c, shape, sd, 0.34 * R * s.es, 0.4 * R * s.es, open, T, p.ink);
      }
      c.restore();''')
rep('''const REAL: ReadonlySet<EyeShape> = new Set<EyeShape>(["pill", "wide", "dot", "tired"]);
''', '''const REAL: ReadonlySet<EyeShape> = new Set<EyeShape>(["pill", "wide", "dot", "tired"]);

/**
 * The small coloured eye of the compact level, painted in the eye's own frame from `smallEye`'s geometry: the iris is a radial gradient from the coat's
 * `iris[0]` at the centre to `iris[1]` at the edge (`irisR` for the right eye when the coat has one), the pupil is the theme's pupil colour, the catchlight
 * white at 0.92, the rim the coat's liner colour; a blink or squint is the closed line in the ink colour at 0.9. The black coats (Midnight, Oreo, Mocha, and their
 * kittens: `smallEye` says `flat`) glow like the old pill instead: one flat fill of the lighter of the coat's two iris colours by luminance, no rim, the
 * catchlight kept. The prototype's `smallEyeDraw` is the reference.
 */
function smallEyeDraw(c: Ctx, p: CatPreset, sd: number, G: SmallEye) {
  const a0 = c.globalAlpha;
  if (G.closed) {
    const l = G.line;
    c.strokeStyle = p.ink; c.globalAlpha = a0 * 0.9; c.lineWidth = l.width; c.lineCap = "round"; c.beginPath(); c.moveTo(l.x0, l.y0);
    c.quadraticCurveTo(l.cx, l.cy, l.x1, l.y1); c.stroke(); c.globalAlpha = a0;
    return;
  }
  const I = G.iris, P = G.pupil, Lt = G.light, ir = (sd > 0 && p.irisR) || p.iris;
  if (G.flat) c.fillStyle = lum(ir[0]) >= lum(ir[1]) ? ir[0] : ir[1];
  else {
    const g = c.createRadialGradient(0, 0, 0, 0, 0, I.r);
    g.addColorStop(0, ir[0]); g.addColorStop(1, ir[1]);
    c.fillStyle = g;
  }
  c.beginPath(); c.ellipse(0, 0, I.rx, I.ry, 0, 0, TAU); c.fill();
  c.fillStyle = THEME.cat.pupil; c.beginPath(); c.ellipse(P.x, P.y, P.rx, P.ry, 0, 0, TAU); c.fill();
  c.fillStyle = "rgba(255,255,255,.92)"; c.beginPath(); c.arc(Lt.x, Lt.y, Lt.r, 0, TAU); c.fill();
  if (!G.flat) { c.strokeStyle = p.liner; c.lineWidth = G.rim; c.beginPath(); c.ellipse(0, 0, I.rx, I.ry, 0, 0, TAU); c.stroke(); }
}

/** The relative luminance of a #RRGGBB colour: which of a bright coat's two iris colours is the lighter. */
function lum(hex: string): number {
  const n = parseInt(hex.slice(1), 16);
  return 0.2126 * ((n >> 16) & 255) + 0.7152 * ((n >> 8) & 255) + 0.0722 * (n & 255);
}
''')
open(p, 'w', encoding='utf-8').write(s)
PY
```

- [ ] **Step 5: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/renderer-eyes.test.mjs scripts/cat-tests/renderer.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 16`, `# pass 16`, `# fail 0`, `tsc exit 0`, then `ℹ tests 184`, `ℹ pass 184`, `ℹ fail 0`.

- [ ] **Step 6: Prove the coloured eye is what the renderer draws (not committed)**

```bash
python3 - <<'PY'
import subprocess
p = 'windows/src/cat/renderer.ts'
s = open(p, encoding='utf-8').read()
was = 'const eye = o.eyes === "ink" ? null : smallEye('
assert s.count(was) == 1
run = lambda: print(subprocess.run('cd windows && node --experimental-strip-types --test scripts/cat-tests/renderer-eyes.test.mjs 2>&1 | grep -E "^# (pass|fail)"', shell=True, capture_output=True, text=True).stdout, end='')
open(p, 'w', encoding='utf-8').write(s.replace(was, 'const eye = true ? null : smallEye('))
run()
open(p, 'w', encoding='utf-8').write(s)
run()
PY
```

Expected: the first run prints `# pass 2` and `# fail 6` (the compact cats are drawn with ink eyes again); after the line is put back, `# pass 8` and `# fail 0`.

- [ ] **Step 7: The `?dev` panel: the contact sheet and the bench**

```bash
python3 - <<'PY'
# Task 2: the ?dev page gets a "Small eyes" panel: the contact sheet at 2x and 1x, and a frame-time bench. Run from the repository root. Every replacement asserts that its anchor is there exactly once.
p = 'windows/src/cat/dev.ts'
s = open(p, encoding='utf-8').read()

def rep(was, now):
    global s
    assert s.count(was) == 1, was[:70]
    s = s.replace(was, now)

rep('''  // ── Stage 3: emotes, the mouth and personality ──
''', '''  // ── Sub-project B: the small coloured eyes ──
  // Every coat and a kitten of it at the compact sizes, the flat ink pills they had (`eyes: "ink"`, left of each pair) beside the small coloured eyes (right). Drawn once:
  // the cats are stills. Scale 2 draws the compact drawing at twice the head width, so the eyes can be judged; scale 1 is true size.
  const EYE_COLS = [{ d: 12 }, { d: 16 }, { d: 20 }, { d: 24 }, { d: 12, kit: true }, { d: 16, kit: true }, { d: 20, kit: true }];
  const EYE_LEFT = 74, EYE_HEAD = 36;
  const eyeBox = section("Small eyes", "Every coat and a kitten of it at the compact sizes: the flat ink pills they had (left of each pair) beside the small coloured eyes (right). The first sheet is magnified 2 times, as the compact drawing at twice the size; the second is true size. Geometry: smallEye, pinned by small-eye-cases.json.");
  const eyeViews = new Map<string, CatView>();
  const eyeView = (id: string, kit: boolean): CatView => {
    const key = id + (kit ? ":k" : "");
    let v = eyeViews.get(key);
    if (!v) { v = stillView(kit ? kittenOf(PRESETS[id]) : PRESETS[id], newPose()); eyeViews.set(key, v); }
    return v;
  };
  function drawEyeSheet(cv: HTMLCanvasElement, scale: number) {
    const colW = EYE_COLS.map((z) => Math.max(80, z.d * scale * 2 + 34)), rowH = Math.max(34, 24 * scale + 10);
    const W = EYE_LEFT + colW.reduce((a, b) => a + b, 0) + 8, H = EYE_HEAD + CAT_IDS.length * rowH + 6, c = fit(cv, W, H);
    c.fillStyle = "#000"; c.fillRect(0, 0, W, H); c.textBaseline = "alphabetic"; c.textAlign = "center";
    let x = EYE_LEFT;
    EYE_COLS.forEach((z, i) => {
      const w = colW[i];
      c.fillStyle = "#ececee"; c.font = `600 11px ${FONT}`; c.fillText(`${z.kit ? "kitten " : ""}Ø${z.d}`, x + w / 2, 15);
      c.fillStyle = "#9a9ca3"; c.font = `10px ${FONT}`; c.fillText("ink · coloured", x + w / 2, 29);
      c.strokeStyle = "#2a2c31"; c.beginPath(); c.moveTo(x + 0.5, 6); c.lineTo(x + 0.5, H - 6); c.stroke();
      x += w;
    });
    CAT_IDS.forEach((id, ri) => {
      const cy = EYE_HEAD + ri * rowH + rowH / 2;
      c.fillStyle = "#ececee"; c.font = `11px ${FONT}`; c.textAlign = "left"; c.fillText(PRESETS[id].label, 10, cy + 4);
      let cx0 = EYE_LEFT;
      EYE_COLS.forEach((z, i) => {
        const w = colW[i];
        for (const [fx, ink] of [[0.27, true], [0.73, false]] as const) drawCat(c, eyeView(id, !!z.kit), cx0 + w * fx, cy, z.d * scale, { tint: false, badge: false, detail: "compact", eyes: ink ? "ink" : undefined });
        cx0 += w;
      });
    });
  }
  const eyes2 = document.createElement("canvas"), eyes1 = document.createElement("canvas");
  eyes2.id = "eyes2"; eyes1.id = "eyes1";
  eyes2.setAttribute("aria-label", "Small eyes, magnified 2 times"); eyes1.setAttribute("aria-label", "Small eyes, true size");
  for (const cv of [eyes2, eyes1]) { cv.style.display = "block"; }
  const eyes2Wrap = document.createElement("div"), eyes1Wrap = document.createElement("div");
  eyes2Wrap.style.cssText = "overflow-x:auto"; eyes1Wrap.style.cssText = "overflow-x:auto;margin-top:12px";
  eyes2Wrap.append(eyes2); eyes1Wrap.append(eyes1);
  // The cost of the eyes, in the same build: twelve small cats and one Ø66 drawn in turn, with the ink pills and with the coloured eyes, alternating over three rounds.
  const benchCv = document.createElement("canvas");
  const benchNote = document.createElement("p");
  benchNote.id = "eye-bench"; benchNote.style.cssText = `color:${B.dim};font-size:12px;margin:10px 0 0`; benchNote.textContent = "Press Measure to time twelve small cats and a Ø66 with ink and with coloured eyes.";
  const benchViews = CAT_IDS.slice(0, 12).map((id, i) => ({ v: stillView(PRESETS[id], newPose()), d: [12, 16, 20, 24][i % 4], x: 30 + i * 46 })).concat([{ v: stillView(PRESETS.shrimpy, newPose()), d: 66, x: 640 }]);
  function benchOnce(eyes: "ink" | undefined, frames: number): number {
    const c = fit(benchCv, 720, 90), t0 = performance.now();
    for (let f = 0; f < frames; f++) for (const b of benchViews) drawCat(c, b.v, b.x, 45, b.d, { eyes });
    return (performance.now() - t0) / frames;
  }
  const median = (a: number[]) => [...a].sort((x, y) => x - y)[a.length >> 1];
  const measure = () => {
    const ink: number[] = [], col: number[] = [];
    benchOnce(undefined, 20); benchOnce("ink", 20); // warm up
    for (let r = 0; r < 3; r++) { ink.push(benchOnce("ink", 120)); col.push(benchOnce(undefined, 120)); }
    const a = median(ink), b = median(col);
    benchNote.textContent = `Twelve small cats and one Ø66, drawn in turn: ink eyes ${a.toFixed(2)} ms, coloured eyes ${b.toFixed(2)} ms per frame (median of 3 rounds of 120 frames; ${(((b - a) / a) * 100).toFixed(0)}% more).`;
  };
  const benchRow = row("Frame time");
  benchRow.append(button("Measure", measure));
  eyeBox.append(eyes2Wrap, eyes1Wrap, benchRow, benchNote);
  root.insertBefore(eyeBox, wrap);
  drawEyeSheet(eyes2, 2); drawEyeSheet(eyes1, 1);
  // ── Stage 3: emotes, the mouth and personality ──
''')
open(p, 'w', encoding='utf-8').write(s)
PY
```

Run: `cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; cd ..`
Expected: `tsc exit 0` with no type error before it.

- [ ] **Step 8: Look at it and measure again**

The sheet is every coat and a kitten of it at Ø12, 16, 20 and 24, ink pills left of each pair and coloured eyes right, drawn once magnified 2 times (the compact drawing at twice the size) and once at true size. **Measure** draws twelve small cats and one Ø66 in turn with ink and with coloured eyes, three rounds each, and prints the medians.

```bash
SHOTS="${TMPDIR:-/tmp}/b-tauri-shots"
(cd windows && npx --no-install vite --port 14581 > "$SHOTS/vite.log" 2>&1 &)
sleep 4
cd "$SHOTS"
playwright-cli -s=eyes open "http://127.0.0.1:14581/?dev" --config=pw2x.json | grep -E "Console"
sleep 4
playwright-cli -s=eyes --raw eval "[...document.querySelectorAll('p')].map(p => p.textContent).filter(t => t.startsWith('Drawing per frame')).join('|')"
playwright-cli -s=eyes click "getByRole('button', { name: 'Measure' })" > /dev/null
sleep 4
playwright-cli -s=eyes --raw eval "document.getElementById('eye-bench').textContent"
playwright-cli -s=eyes run-code "async page => { await page.locator('#eyes2').screenshot({ path: 'eyes-2x.png' }); await page.locator('#eyes1').screenshot({ path: 'eyes-1x.png' }); }" > /dev/null
playwright-cli -s=eyes close > /dev/null
kill $(lsof -ti tcp:14581) 2>/dev/null; sleep 1; lsof -ti tcp:14581 | wc -l
ls *.png
```

Expected: `- Console: 1 errors, 0 warnings`; the readout line again (the live cats' number within about 25 % of the **before**, which is noise from a machine in software drawing: if it is far higher, say so); `"Twelve small cats and one Ø66, drawn in turn: ink eyes <x> ms, coloured eyes <y> ms per frame (median of 3 rounds of 120 frames; <p>% more)."` with the coloured cost small over the ink one (5 to 10 % on a quiet machine; the black coats' flat eyes cost less than a gradient; on a busy machine it read up to 40 %, which is noise: **press Measure twice more when it is above 25 % and report all three numbers**); `0`; and `eyes-1x.png  eyes-2x.png  …` in the folder. Open both pictures. `eyes-2x.png`: 16 rows (Shrimpy first), seven pairs per row (Ø12, Ø16, Ø20, Ø24, then a kitten at Ø12, Ø16, Ø20), the left cat of each pair with flat ink pills for eyes and the right with small coloured eyes: an iris in the coat's colours (Snow with one blue and one gold eye, Latte and Cloud blue), a dark pupil, a white catchlight, a dark rim; **Midnight, Oreo and Mocha glow**: a flat gold or lime iris with no rim and a thin dark slit, as bright as their old ink pills; kittens' eyes are rounder and larger. `eyes-1x.png` is the same at true size. If a cat is cut off, an eye is blank or a number is NaN, fix `smalleye.ts` or `smallEyeDraw` and look again. **Say what you saw, and both frame times, to the controller.**

- [ ] **Step 9: Commit**

```bash
git add windows/scripts/cat-tests/fake-canvas.mjs windows/scripts/cat-tests/renderer.test.mjs windows/scripts/cat-tests/renderer-eyes.test.mjs windows/src/cat/renderer.ts windows/src/cat/dev.ts
git commit -m "feat(cat): the compact cats have small coloured eyes

Below Ø28 the plain resting eyes (pill, wide, dot, tired and a wink's left eye) are an iris in the coat's colours with a slit
pupil, a catchlight and a thin rim, from smallEye; every expression shape stays ink. DrawOptions.eyes: ink keeps the old pills.
The ?dev page gets a Small eyes panel (every coat and a kitten of it at Ø12 to Ø24, 2x and 1x, ink beside coloured) and a
same-build frame-time bench. The flat-fill test draws its cats with ink eyes: the iris gradient is the eye's own.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

# Stage 2: the Display settings, the agents' coats and the Settings screen

### Task 3: The Display settings in TypeScript

**Agent:** `nm-implementer-light`.

**Files:**
- Create: `windows/src/cat/display.ts`
- Test: `windows/scripts/cat-tests/display.test.mjs`

**Interfaces:**
- Consumes: B-0's `display-cases.json` (`ids`, `modes`, `defaultPair`, `defaultAgentCats`, `maxAgentCats`, `pillIdPattern`, `defaults`, `cases`, `pairs`, `agentCats`, `pillIds`); `settings.ts`'s `cleanCatSettings`, `catIdOf`, `CatSettings`, and the `with…` helpers (a test); `presets.ts`'s `CAT_IDS`; `base.ts`'s `own`, `rng` (a test).
- Produces: `DISPLAY_MODES`, `displayModeOf`, `DEFAULT_PAIR`, `DEFAULT_AGENT_CATS`, `MAX_AGENT_CATS`, `PILL_ID`, `isPillId`, `isAgentPill`, `defaultAgentCat`, `cleanPair`, `cleanAgentCats`, `cleanDisplaySettings`, `defaultDisplaySettings`; the type `CatBlock` and `cleanCatBlock`, `defaultCatBlock`, `withCatSettings`; the Display rows' edits `withDisplayMode`, `withPair`, `withAgentCat`, `withAgentCats`. Tasks 4, 7, 8 and 9 use them.

- [ ] **Step 1: Write the failing test**

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/display.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { rng } from "../../src/cat/base.ts";
import { CAT_IDS } from "../../src/cat/presets.ts";
import { PERSONAS, personaNamed } from "../../src/cat/personality.ts";
import { applyToAllCats, cleanCatSettings, defaultCatSettings, withCatCollar, withCatMotion, withCharacter, withCollar, withFurLines, withMotionStyle, withPersonality } from "../../src/cat/settings.ts";
import * as D from "../../src/cat/display.ts";
import { load, same } from "./util.mjs";

// The Display settings, replayed from tests/fixtures/cat/display-cases.json (B-0), and the cases a JSON file cannot hold.
const fx = load("display-cases.json");
const IDS = [...CAT_IDS];
const DEFAULTS = { displayMode: "one", pair: ["shrimpy", "momo"], agentCats: {} };
const deepFreeze = (v) => { if (v && typeof v === "object") { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };

test("the frozen values are the fixture's: three modes in Settings order, the default pair, the two default agent coats, the pill-ID shape", () => {
  assert.deepEqual([...D.DISPLAY_MODES], fx.modes);
  assert.deepEqual([...D.DISPLAY_MODES], ["one", "perAgent", "two"]);
  assert.deepEqual([...D.DEFAULT_PAIR], fx.defaultPair);
  assert.deepEqual({ ...D.DEFAULT_AGENT_CATS }, fx.defaultAgentCats);
  assert.equal(D.MAX_AGENT_CATS, fx.maxAgentCats);
  assert.equal(D.PILL_ID.source, fx.pillIdPattern);
  assert.deepEqual(fx.ids, IDS);
  same(D.defaultDisplaySettings(), fx.defaults, "defaults");
  assert.deepEqual(D.defaultDisplaySettings(), DEFAULTS);
});

test("cleanDisplaySettings, cleanPair, cleanAgentCats and the pill-ID rules replay every row of the fixture", () => {
  assert.ok(fx.cases.length >= 30 && fx.pairs.length >= 40 && fx.agentCats.length >= 21 && fx.pillIds.length >= 29);
  for (const c of fx.cases) same(D.cleanDisplaySettings(c.raw), c.out, c.name);
  for (const c of fx.pairs) same(D.cleanPair(c.raw), c.out, c.name);
  for (const c of fx.agentCats) same(D.cleanAgentCats(c.raw), c.out, c.name);
  for (const c of fx.pillIds) assert.deepEqual({ id: c.id, pill: D.isPillId(c.id), agent: D.isAgentPill(c.id), default: D.defaultAgentCat(c.id) }, c, JSON.stringify(c.id));
});

test("a value that is not there at all (undefined, NaN, a function, a symbol) is the default, and nothing throws", () => {
  for (const raw of [undefined, NaN, () => 1, Symbol("x"), 10n]) assert.deepEqual(D.cleanDisplaySettings(raw), DEFAULTS, String(typeof raw));
  assert.deepEqual(D.cleanDisplaySettings({ displayMode: undefined, pair: undefined, agentCats: undefined }), DEFAULTS);
  assert.deepEqual(D.cleanPair(NaN), ["shrimpy", "momo"]);
  assert.deepEqual(D.cleanPair([undefined, "momo"]), ["shrimpy", "momo"]);
  assert.deepEqual(D.cleanAgentCats({ agent_x: undefined, agent_y: NaN, agent_codex: undefined }), { agent_codex: "momo" });
  assert.equal(D.displayModeOf(Symbol("two")), "one");
});

test("the pill-ID check matches the whole string: a trailing newline or space is not a pill ID", () => {
  for (const bad of ["agent_x\n", "agent_x ", "agent_x\r\n", "\nagent_x", "agent_x "]) assert.equal(D.isPillId(bad), false, JSON.stringify(bad));
  assert.equal(D.isPillId("agent_x"), true);
  assert.equal(D.isPillId("a" + "b".repeat(63)), true);
  assert.equal(D.isPillId("a" + "b".repeat(64)), false);
});

test("a hostile map never pollutes a prototype and never throws, with __proto__ and constructor as keys", () => {
  const polluted = JSON.parse('{"__proto__":"momo","constructor":"momo","prototype":"momo","agent_ok":"ginger","toString":"momo"}');
  const out = D.cleanAgentCats(polluted);
  assert.deepEqual(out, { agent_ok: "ginger" });
  assert.equal(Object.getPrototypeOf(out), Object.prototype);
  assert.equal({}.agent_ok, undefined, "nothing reached Object.prototype");
  assert.deepEqual(D.cleanAgentCats(JSON.parse('{"__proto__":{"agent_x":"momo"},"agent_y":{"__proto__":"momo"}}')), {});
  assert.equal({}.agent_x, undefined);
});

test("the input is never changed, even when it is frozen; every call gives fresh objects", () => {
  const raw = deepFreeze({ displayMode: "two", pair: ["momo", "momo"], agentCats: { agent_x: "momo", integration_claude: "tiger" } });
  assert.doesNotThrow(() => D.cleanDisplaySettings(raw));
  assert.deepEqual(D.cleanDisplaySettings(raw), { displayMode: "two", pair: ["momo", "ginger"], agentCats: { agent_x: "momo", integration_claude: "shrimpy" } });
  assert.deepEqual(raw.pair, ["momo", "momo"]);
  const d = D.defaultDisplaySettings();
  d.pair[0] = "noodle"; d.agentCats.x = "momo";
  assert.deepEqual(D.defaultDisplaySettings(), DEFAULTS, "changing a result never changes the next one");
  assert.deepEqual(D.DEFAULT_PAIR, ["shrimpy", "momo"], "and never the frozen default");
});

test("3000 random display settings come out valid, and cleaning them again changes nothing", () => {
  const r = rng(2027), pool = ["one", "two", "perAgent", "Two", "", " ", "momo", "shrimpy", "tiger", "noodle", '["momo","ginger"]', '["momo"', "__proto__", "constructor", "agent_x", "agent_codex", "integration_claude", "ai_openai", "Agent_X", null, true, false, 0, 1, -1, 0.5, 7, [], ["momo"], ["momo", "ginger"], ["ginger", "ginger"], [1, 2], {}, { agent_x: "latte" }, { agent_codex: "tiger" }];
  const pick = () => pool[Math.floor(r() * pool.length)];
  const valid = (s) => D.DISPLAY_MODES.includes(s.displayMode) && s.pair.length === 2 && s.pair.every((c) => IDS.includes(c)) && s.pair[0] !== s.pair[1]
    && Object.entries(s.agentCats).every(([k, v]) => D.isPillId(k) && IDS.includes(v)) && JSON.stringify(Object.keys(s.agentCats)) === JSON.stringify(Object.keys(s.agentCats).sort());
  for (let i = 0; i < 3000; i++) {
    const map = r() < 0.15 ? pick() : Object.fromEntries(Array.from({ length: Math.floor(r() * 6) }, () => [pick(), pick()]).filter(([k]) => typeof k === "string"));
    const raw = { displayMode: pick(), pair: pick(), agentCats: map };
    const out = D.cleanDisplaySettings(raw);
    assert.ok(valid(out), JSON.stringify(raw));
    assert.deepEqual(D.cleanDisplaySettings(out), out);
  }
});

test("the whole block: the Cat settings and the Display settings are cleaned together, and a clean-up with the Cat settings alone would drop the display keys", () => {
  const raw = { character: "momo", motionStyle: "classic", collar: "band", furLines: true, cats: { momo: { motion: "playful" } }, displayMode: "two", pair: ["ginger", "latte"], agentCats: { agent_gemini: "oreo" } };
  const block = D.cleanCatBlock(raw);
  assert.deepEqual(Object.keys(block).sort(), ["agentCats", "cats", "character", "collar", "displayMode", "furLines", "motionStyle", "pair"]);
  assert.deepEqual(cleanCatSettings(raw), cleanCatSettings(block), "the Cat settings part is cleanCatSettings's, unchanged");
  assert.equal("displayMode" in cleanCatSettings(raw), false, "cleanCatSettings drops the display keys: that is why the block has a clean-up of its own");
  assert.deepEqual([block.displayMode, block.pair, block.agentCats], ["two", ["ginger", "latte"], { agent_gemini: "oreo" }]);
  assert.deepEqual(D.cleanCatBlock(block), block, "cleaning twice changes nothing");
  assert.deepEqual(D.cleanCatBlock(JSON.parse(JSON.stringify(block))), block, "it survives JSON");
  assert.deepEqual(D.cleanCatBlock(null), { ...defaultCatSettings(), ...DEFAULTS });
  assert.deepEqual(D.defaultCatBlock(), D.cleanCatBlock(5));
});

test("the Display rows edit one thing each and give back a whole clean block", () => {
  const b = D.defaultCatBlock();
  assert.equal(D.withDisplayMode(b, "two").displayMode, "two");
  assert.equal(D.withDisplayMode(b, "Two").displayMode, "one", "an unknown mode is One cat");
  assert.deepEqual(D.withPair(b, 1, "noodle").pair, ["shrimpy", "noodle"]);
  assert.deepEqual(D.withPair(b, 0, "ginger").pair, ["ginger", "momo"]);
  assert.deepEqual(D.withPair(b, 1, "shrimpy").pair, ["shrimpy", "momo"], "the same coat twice: cat 2 is the next one");
  assert.deepEqual(D.withPair(b, 0, "momo").pair, ["momo", "ginger"], "and when cat 1 takes cat 2's coat, cat 2 moves on");
  assert.deepEqual(D.withPair(b, 0, "tiger").pair, ["shrimpy", "momo"], "an unknown coat is Shrimpy");
  assert.deepEqual(D.withAgentCat(b, "agent_gemini", "oreo").agentCats, { agent_gemini: "oreo" });
  assert.deepEqual(D.withAgentCat(D.withAgentCat(b, "agent_gemini", "oreo"), "agent_gemini", "tiger").agentCats, {}, "a bad coat for an agent with no default drops the pill");
  assert.deepEqual(D.withAgentCat(b, "__proto__", "oreo").agentCats, {});
  assert.deepEqual(D.withAgentCats(b, { agent_x: "snow", Bad: "momo" }).agentCats, { agent_x: "snow" });
  for (const edit of [D.withDisplayMode(b, "perAgent"), D.withPair(b, 0, "latte"), D.withAgentCat(b, "agent_x", "snow")]) {
    assert.deepEqual(Object.keys(edit).sort(), Object.keys(b).sort(), "all eight keys");
    assert.deepEqual(edit.cats, b.cats, "the Cat settings are untouched");
  }
  assert.deepEqual(b, D.defaultCatBlock(), "the input is not changed");
});

test("a Cat settings row edit keeps the display keys when it is put into the block, and a Display edit keeps the Cat settings: what the Settings window saves", () => {
  const start = D.withAgentCat(D.withPair(D.withDisplayMode(D.defaultCatBlock(), "two"), 1, "noodle"), "agent_x", "snow");
  const edits = [withCharacter(start, "momo"), withMotionStyle(start, "classic"), withCollar(start, "band"), withFurLines(start, true), withCatMotion(start, "momo", "classic"),
    withCatCollar(start, "momo", "off"), withPersonality(start, "momo", personaNamed("chill")), applyToAllCats(start, "momo")];
  assert.ok("chill" in PERSONAS);
  for (const edit of edits) {
    assert.equal("displayMode" in edit, false, "the Cat settings edits return the Cat settings alone: put as they are, they would drop the display keys");
    const put = D.withCatSettings(start, edit);
    assert.deepEqual([put.displayMode, put.pair, put.agentCats], ["two", ["shrimpy", "noodle"], { agent_x: "snow" }]);
    assert.deepEqual(cleanCatSettings(put), cleanCatSettings(edit), "and the Cat settings are the edit's");
  }
  const shown = D.withDisplayMode(D.cleanCatBlock({ character: "momo", collar: "band" }), "perAgent");
  assert.deepEqual([shown.character, shown.collar, shown.displayMode], ["momo", "band", "perAgent"]);
  assert.deepEqual(D.withCatSettings(shown, shown), shown, "a whole block put into the block is itself");
});
EOF
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/display.test.mjs 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|^# (tests|pass|fail)" | cut -c1-90; cd ..`
Expected: a line with `ERR_MODULE_NOT_FOUND` (`display.ts` does not exist yet), `# tests 1`, `# pass 0` and `# fail 1`.

- [ ] **Step 3: Write the module**

```bash
mkdir -p windows/src/cat
cat > windows/src/cat/display.ts <<'EOF'
// The Display settings (sub-project B, spec §1): how the cats are shown. Settings → Cat → Display picks One cat (the Main cat everywhere, the default), A cat for
// each agent, or Two cats (a pair, side by side), and saves a mode, the pair and each agent's coat. A port of "Display modes: the stored settings" in
// design/prototype/cat-core.js (the tie-breaker; fixture tests/fixtures/cat/display-cases.json; docs/CAT-CONTRACT.md "Display settings"). A settings file can be
// hand-edited or half written, so everything that reads one passes it through cleanDisplaySettings first. Raw in, clean out, never a throw. The Rust side
// (src-tauri/src/cat_settings.rs) holds the same block and cleans it the same way.
//
//   { displayMode, pair: [catId, catId], agentCats: { <pillId>: <catId> } }       in the `cat` block of settings.json, beside the Cat settings
//
// cleanCatSettings (settings.ts) still returns only the five Cat settings and drops these keys, so the block is cleaned with both: `cleanCatBlock`.
// Imports base.ts, presets.ts and settings.ts, so the plain-Node checks (npm run check:cat) can load it.

import { own } from "./base.ts";
import { CAT_IDS } from "./presets.ts";
import { catIdOf, cleanCatSettings } from "./settings.ts";
import type { CatSettings } from "./settings.ts";

/** The display modes, in the order Settings lists them. Frozen contract values, like the cat IDs: an unknown stored mode is `one`. */
export const DISPLAY_MODES = ["one", "perAgent", "two"] as const;
export type DisplayMode = (typeof DISPLAY_MODES)[number];
export const displayModeOf = (v: unknown): DisplayMode => ((DISPLAY_MODES as readonly unknown[]).includes(v) ? (v as DisplayMode) : "one");

/** Two cats mode's pair before the user picks: Shrimpy and Momo. */
export const DEFAULT_PAIR: readonly [string, string] = ["shrimpy", "momo"];
/** What an agent pill wears before the user picks: Claude Code is Shrimpy and Codex is Momo. Every other agent gets a coat when it is first seen (agentcat.ts). */
export const DEFAULT_AGENT_CATS: Readonly<Record<string, string>> = { integration_claude: "shrimpy", agent_codex: "momo" };
/** A stored map keeps at most this many pills (the first by code-point order of their IDs), so a hostile file cannot grow it without end. */
export const MAX_AGENT_CATS = 256;
/** A pill ID: a lowercase letter, then lowercase letters, digits, `_` and `-`, 2 to 64 characters, the whole string. Names that are prototype members are refused. */
export const PILL_ID = /^[a-z][a-z0-9_-]{1,63}$/;
export const isPillId = (v: unknown): v is string => typeof v === "string" && PILL_ID.test(v) && v !== "constructor" && v !== "prototype";
/** Agent pills are Claude Code's pill (`integration_claude`, despite its prefix) and every `agent_*` pill. Every other pill is an integration or an AI provider. */
export const isAgentPill = (v: unknown): v is string => isPillId(v) && (v === "integration_claude" || (v.startsWith("agent_") && v.length > 6));
/** The default coat of an agent pill (Claude Code Shrimpy, Codex Momo), or null for a pill that has none. */
export const defaultAgentCat = (id: unknown): string | null => (isPillId(id) && own(DEFAULT_AGENT_CATS, id) ? DEFAULT_AGENT_CATS[id] : null);

const isCatId = (v: unknown): v is string => typeof v === "string" && (CAT_IDS as readonly string[]).includes(v);
const isPlain = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);

/**
 * A stored pair to two cat IDs. It may be an array or the JSON text of one (the Mac stores text). Anything that is not two valid cat IDs, whole, is Shrimpy and
 * Momo. Two of the same coat make cat 2 the next coat in CAT_IDS order (after the last one, the first).
 */
export function cleanPair(raw: unknown): [string, string] {
  let v = raw;
  if (typeof v === "string") {
    try { v = JSON.parse(v); } catch { return [...DEFAULT_PAIR]; }
  }
  if (!Array.isArray(v) || v.length !== 2 || !v.every(isCatId)) return [...DEFAULT_PAIR];
  return v[0] === v[1] ? [v[0], CAT_IDS[(CAT_IDS.indexOf(v[1]) + 1) % CAT_IDS.length]] : [v[0], v[1]];
}

/**
 * A stored map from pill ID to cat ID, cleaned. A pill ID that does not have the shape of one is dropped (`__proto__` and `constructor` included); an unknown
 * pill ID is kept, because agents come and go. A bad coat becomes the pill's default when it has one, and is dropped otherwise (agentCatFor gives that agent a
 * coat again). The result has its pills in code-point order, at most MAX_AGENT_CATS of them.
 */
export function cleanAgentCats(raw: unknown): Record<string, string> {
  const out: Record<string, string> = {};
  if (!isPlain(raw)) return out;
  let n = 0;
  for (const id of Object.keys(raw).filter(isPillId).sort()) {
    if (n >= MAX_AGENT_CATS) break;
    const c = raw[id], d = defaultAgentCat(id);
    if (isCatId(c)) { out[id] = c; n++; } else if (d) { out[id] = d; n++; }
  }
  return out;
}

export interface DisplaySettings { displayMode: DisplayMode; pair: [string, string]; agentCats: Record<string, string> }

/** Everything Display saves, cleaned: {displayMode, pair, agentCats}. Never throws. */
export function cleanDisplaySettings(raw: unknown): DisplaySettings {
  const r: Record<string, unknown> = isPlain(raw) ? raw : {};
  return { displayMode: displayModeOf(r.displayMode), pair: cleanPair(r.pair), agentCats: cleanAgentCats(r.agentCats) };
}

/** What a fresh install holds: One cat, Shrimpy and Momo, no stored agent coats. */
export const defaultDisplaySettings = (): DisplaySettings => cleanDisplaySettings(null);

// ── The whole `cat` block: the Cat settings and the Display settings ────────────────────────────────────────────────────────────────────────

/** The `cat` block of settings.json, clean: the Cat settings (settings.ts) and the Display settings. */
export type CatBlock = CatSettings & DisplaySettings;

/** Cleans the block with both clean-ups: a clean-up that used cleanCatSettings alone would drop the three display keys at the next save. Never throws. */
export const cleanCatBlock = (raw: unknown): CatBlock => ({ ...cleanCatSettings(raw), ...cleanDisplaySettings(raw) });

/** What a fresh install holds. */
export const defaultCatBlock = (): CatBlock => cleanCatBlock(null);

// ── Edits: each Display row changes one thing and gets a whole clean block back (they never touch their input) ───────────────────────────────

const blockEdited = (b: CatBlock, patch: Partial<DisplaySettings>): CatBlock => cleanCatBlock({ ...b, ...patch });
/** A Cat settings row edit (or a whole new block) put into the block: the display keys the block has are kept, because an edit of the Cat settings does not carry them. */
export const withCatSettings = (b: CatBlock, next: CatSettings | CatBlock): CatBlock => cleanCatBlock({ ...b, ...next });
/** The Display row. */
export const withDisplayMode = (b: CatBlock, v: unknown): CatBlock => blockEdited(b, { displayMode: displayModeOf(v) });
/** One of the pair's pickers: cat 1 (`index` 0) or cat 2 (1). The same coat twice makes cat 2 the next coat (cleanPair). */
export const withPair = (b: CatBlock, index: 0 | 1, id: unknown): CatBlock => {
  const pair: [string, string] = [b.pair[0], b.pair[1]];
  pair[index] = catIdOf(id);
  return blockEdited(b, { pair });
};
/** An agent's cat picker: its coat is stored, and cleanAgentCats keeps the rest. */
export const withAgentCat = (b: CatBlock, pillId: unknown, catId: unknown): CatBlock => blockEdited(b, { agentCats: cleanAgentCats({ ...b.agentCats, [String(pillId)]: catId }) });
/** The dice and "Reset to defaults" give back a whole map (rerollAgentCat's and assignAgentCats'). */
export const withAgentCats = (b: CatBlock, agentCats: unknown): CatBlock => blockEdited(b, { agentCats: cleanAgentCats(agentCats) });
EOF
```

- [ ] **Step 4: Run the test and the type check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/display.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"; npx --no-install tsc --noEmit; echo "tsc exit $?"; cd ..`
Expected: `# tests 10`, `# pass 10`, `# fail 0`, `tsc exit 0`.

- [ ] **Step 5: Prove the prototype-name guard bites (not committed)**

```bash
python3 - <<'PY'
import subprocess
p = 'windows/src/cat/display.ts'
s = open(p, encoding='utf-8').read()
was = ' && v !== "constructor" && v !== "prototype";'
assert s.count(was) == 1
run = lambda: print(subprocess.run('cd windows && node --experimental-strip-types --test scripts/cat-tests/display.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"', shell=True, capture_output=True, text=True).stdout, end='')
open(p, 'w', encoding='utf-8').write(s.replace(was, ';'))
run()
open(p, 'w', encoding='utf-8').write(s)
run()
PY
```

Expected: the first run prints `not ok 2 - cleanDisplaySettings, cleanPair, cleanAgentCats and the pill-ID rules replay every row of the fixture` and `not ok 5 - a hostile map never pollutes a prototype and never throws, with __proto__ and constructor as keys`, then `# pass 8` and `# fail 2`; after the line is put back, `# pass 10` and `# fail 0`.

- [ ] **Step 6: Run the whole cat check and commit**

Run: `cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `ℹ tests 194`, `ℹ pass 194`, `ℹ fail 0` (the 184 before, and the 10 of this task).

```bash
git add windows/scripts/cat-tests/display.test.mjs windows/src/cat/display.ts
git commit -m "feat(cat): the Display settings in TypeScript, a port of cleanDisplaySettings

displayMode, pair and agentCats are cleaned together by cleanDisplaySettings and with the Cat settings by cleanCatBlock, which
a clean-up of the block must use: the Cat settings alone drop the three display keys. withCatSettings keeps them through a
Cat settings row's edit. Replays display-cases.json; the Settings screen and the Rust twin come in the next tasks.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 4: The agents' coats, the cast and the pair's places

**Agent:** `nm-implementer-light`.

**Files:**
- Create: `windows/src/cat/agentcat.ts`, `windows/src/cat/cast.ts`
- Modify: `windows/src/core/pills.ts`, `windows/src/core/layout.ts`
- Test: `windows/scripts/cat-tests/agentcat.test.mjs`, `windows/scripts/cat-tests/cast.test.mjs`, `windows/scripts/cat-tests/places.test.mjs`

**Interfaces:**
- Consumes: Task 3's `cleanAgentCats`, `cleanPair`, `defaultAgentCat`, `displayModeOf`, `isAgentPill`, `isPillId`, `DEFAULT_AGENT_CATS`; `settings.ts`'s `catIdOf`; `base.ts`'s `STATES`, `BUSY`, `own`, `rng`; B-0's `agent-cat-cases.json` and `cast-cases.json`; `layout.ts`'s `botPosition`, `BotPlacement`; `pills.ts`'s `agentColor`, `AGENT_PILL_COLORS`.
- Produces: `pickCat(taken, rand, avoid)`, `agentCatFor(pillId, agentCats, mainCat, rand)` returning `{cat, agentCats, assigned}`, `rerollAgentCat(...)` returning `{cat, agentCats}`, `assignAgentCats(pillIds, agentCats, mainCat, rand)`; `PILL_ROW`, `busyRank`, `castOf(mode, {tasks, focusId, mainCat, pair, agentCats})` returning `{mode, big, second, pills, drop, greeting}`, the types `Cast`, `CastTask`, `CastPill`; `agentLabel(pillId)`, `pillColor(pillId)`; `PAIR`, `pairPlacement(mode, view, islandH)`. Tasks 7, 8, 10 and 13 use them.

- [ ] **Step 1: Write the failing tests**

`agentcat.test.mjs` replays every row of the fixture with the random source each row names (`{seed}`, `{values}`, `{none}`) and checks the number of draws, then the cases a JSON file cannot hold. `cast.test.mjs` replays all 136 rows in the three modes. `places.test.mjs` is the pair's places and the agents' labels and colours.

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/agentcat.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { rng } from "../../src/cat/base.ts";
import { CAT_IDS } from "../../src/cat/presets.ts";
import { assignAgentCats, agentCatFor, pickCat, rerollAgentCat } from "../../src/cat/agentcat.ts";
import { cleanAgentCats, defaultAgentCat } from "../../src/cat/display.ts";
import { load, same } from "./util.mjs";

// Giving agents their cats, replayed from tests/fixtures/cat/agent-cat-cases.json (B-0): the same rows, the same random source, the same number of draws.
const fx = load("agent-cat-cases.json");
const IDS = [...CAT_IDS];
const OTHER = IDS.slice(2); // ginger ... noodle: the 14 coats that are neither Claude Code's nor Codex's default
const counted = (seed) => { const r = rng(seed), f = () => { f.n++; return r(); }; f.n = 0; return f; };
const fixed = (v) => { const f = () => { f.n++; return v; }; f.n = 0; return f; };
const noRand = () => { throw new Error("rand() must not be called here"); };
const deepFreeze = (v) => { if (v && typeof v === "object") { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };
/** The random source of a row: {seed} is rng(seed), {values} those numbers in order and then 0, {none} must never be called. */
const source = (spec) => {
  const seeded = spec.seed !== undefined ? rng(spec.seed) : null;
  const f = () => { f.draws++; if (seeded) return seeded(); if (spec.values) return f.draws <= spec.values.length ? spec.values[f.draws - 1] : 0; throw new Error("rand() must not be called"); };
  f.draws = 0;
  return f;
};

test("agentCatFor, rerollAgentCat and assignAgentCats replay every row of the fixture, with the same number of random draws", () => {
  assert.deepEqual(fx.ids, IDS);
  assert.deepEqual(fx.defaults, { integration_claude: "shrimpy", agent_codex: "momo" });
  assert.ok(fx.cases.length >= 34 && fx.rerolls.length >= 11 && fx.assigns.length >= 6);
  for (const c of fx.cases) { const r = source(c.rand); same(agentCatFor(c.pill, c.agentCats, c.mainCat, r), c.out, c.name); assert.equal(r.draws, c.draws, c.name); }
  for (const c of fx.rerolls) { const r = source(c.rand); same(rerollAgentCat(c.pill, c.agentCats, c.mainCat, r), c.out, c.name); assert.equal(r.draws, c.draws, c.name); }
  for (const c of fx.assigns) { const r = source(c.rand); same({ agentCats: assignAgentCats(c.pills, c.agentCats, c.mainCat, r) }, c.out, c.name); assert.equal(r.draws, c.draws, c.name); }
});

test("Claude Code is Shrimpy and Codex is Momo, with no random number and nothing to store; a stored coat wins over the default", () => {
  for (const [pill, cat] of [["integration_claude", "shrimpy"], ["agent_codex", "momo"]]) assert.deepEqual(agentCatFor(pill, {}, "ginger", noRand), { cat, agentCats: {}, assigned: false }, pill);
  const map = { integration_claude: "oreo", agent_codex: "blue", agent_gemini: "latte" };
  for (const [pill, cat] of [["integration_claude", "oreo"], ["agent_codex", "blue"], ["agent_gemini", "latte"]]) assert.deepEqual(agentCatFor(pill, map, "momo", noRand), { cat, agentCats: map, assigned: false }, pill);
});

test("a pill that is not an agent gets the Main cat and is never stored; a Main cat that is not a cat is Shrimpy", () => {
  for (const pill of ["integration_stripe", "ai_openai", "agent_", "agent", "Agent_x", "__proto__", "constructor", "", null, undefined, 7, {}, ["agent_x"]]) {
    assert.deepEqual(agentCatFor(pill, { agent_y: "momo" }, "cloud", noRand), { cat: "cloud", agentCats: { agent_y: "momo" }, assigned: false }, String(pill));
  }
  assert.equal(agentCatFor("integration_stripe", {}, "tiger", noRand).cat, "shrimpy");
});

test("a new agent gets a coat that no other agent and not the Main cat uses, with one random number, keeps it, and is never given another one", () => {
  for (let seed = 1; seed <= 200; seed++) {
    const rand = counted(seed), map = { agent_a: "blue", agent_b: "ginger" }, out = agentCatFor("agent_new", map, "cloud", rand);
    assert.ok(!["shrimpy", "momo", "blue", "ginger", "cloud"].includes(out.cat), `${seed}: ${out.cat}`);
    assert.equal(out.assigned, true);
    assert.equal(rand.n, 1);
    assert.deepEqual(out.agentCats, { agent_a: "blue", agent_b: "ginger", agent_new: out.cat });
    assert.deepEqual(agentCatFor("agent_new", out.agentCats, "cloud", noRand), { cat: out.cat, agentCats: out.agentCats, assigned: false }, "the second time it only reads");
    assert.deepEqual(map, { agent_a: "blue", agent_b: "ginger" }, "the input is not changed");
  }
  const seen = new Set();
  for (let seed = 1; seed <= 400; seed++) seen.add(agentCatFor("agent_x", {}, "shrimpy", rng(seed)).cat);
  assert.deepEqual([...seen].sort(), [...OTHER].sort(), "every one of the 14 free coats comes up");
});

test("when all 16 coats are taken, the least-used one is chosen, ties in CAT_IDS order, and no random number is drawn", () => {
  const agents = (coats) => Object.fromEntries(coats.map((c, i) => ["agent_a" + String(i).padStart(2, "0"), c]));
  const once = agents(OTHER.slice(0, 13));
  const rand = counted(5);
  assert.deepEqual(agentCatFor("agent_new", once, "noodle", rand), { cat: "shrimpy", agentCats: { ...once, agent_new: "shrimpy" }, assigned: true });
  assert.equal(rand.n, 0);
  assert.equal(agentCatFor("agent_new", agents(OTHER), "shrimpy", noRand).cat, "momo", "Shrimpy is also the Main cat: used twice, so Momo");
  const dup = { ...agents(OTHER), ...Object.fromEntries(IDS.filter((c) => c !== "leo").map((c) => ["agent_d_" + c, c])) };
  assert.equal(agentCatFor("agent_new", dup, "shrimpy", noRand).cat, "leo", "every coat but Leo is used at least twice");
});

test("a default coat that a stored coat has replaced is free again, and the dice never gives the same coat back", () => {
  const map = { integration_claude: "oreo", agent_codex: "ginger" };
  assert.equal(agentCatFor("agent_x", map, "midnight", fixed(0)).cat, "shrimpy");
  assert.equal(agentCatFor("agent_x", {}, "midnight", fixed(0)).cat, "ginger", "with both defaults in force, they are taken");
  for (let seed = 1; seed <= 200; seed++) {
    const out = rerollAgentCat("agent_a", { agent_a: "blue", agent_b: "snow" }, "cloud", counted(seed));
    assert.ok(out.cat !== "blue" && !["shrimpy", "momo", "snow", "cloud"].includes(out.cat), `${seed}: ${out.cat}`);
    assert.deepEqual(out.agentCats, { agent_a: out.cat, agent_b: "snow" });
  }
  assert.deepEqual(rerollAgentCat("integration_claude", {}, "cloud", fixed(0)), { cat: "ginger", agentCats: { integration_claude: "ginger" } }, "Claude Code: not Shrimpy again, and Momo and Cloud are taken");
  assert.deepEqual(rerollAgentCat("integration_stripe", { agent_y: "momo" }, "cloud", noRand), { cat: "cloud", agentCats: { agent_y: "momo" } });
});

test("a random source that misbehaves never breaks it: no function, NaN, a number out of range or text all pick a free coat; 1 is the last one", () => {
  for (const rand of [undefined, null, "x", 7, () => NaN, () => Infinity, () => -3, () => 2, () => "0.5", () => undefined, () => 1]) assert.ok(OTHER.includes(agentCatFor("agent_x", {}, "shrimpy", rand).cat), String(rand));
  assert.equal(agentCatFor("agent_x", {}, "shrimpy", () => 1).cat, "noodle");
  assert.equal(agentCatFor("agent_x", {}, "shrimpy", () => -3).cat, "ginger");
  assert.equal(pickCat(["shrimpy"], () => 0.9999999, "noodle"), "puff", "a coat to avoid is never chosen");
});

test("hostile maps and Main cats never throw and never change their input; a frozen map is fine", () => {
  for (const map of [null, undefined, "x", 7, [], ["momo"], JSON.parse('{"__proto__":"momo","constructor":"momo","agent_ok":"tiger"}')]) {
    const out = agentCatFor("agent_x", map, undefined, fixed(0));
    assert.ok(IDS.includes(out.cat) && out.assigned === true);
    assert.deepEqual(Object.keys(out.agentCats), ["agent_x"]);
  }
  assert.doesNotThrow(() => agentCatFor("agent_x", deepFreeze({ agent_y: "momo" }), "momo", fixed(0)));
  assert.equal({}.agent_x, undefined);
});

test("assignAgentCats gives every agent in the list a coat, in order, skips integrations and repeats, and Reset to defaults is it with an empty map", () => {
  const pills = ["agent_codex", "agent_gemini", "integration_stripe", "agent_cursor", "agent_gemini", "integration_claude", "ai_openai", "Bad Id", "agent_gemini"];
  const out = assignAgentCats(pills, {}, "cloud", rng(3));
  assert.deepEqual(Object.keys(out), ["agent_cursor", "agent_gemini"], "the defaults are not stored, integrations and bad IDs are skipped");
  assert.deepEqual(assignAgentCats(pills, {}, "cloud", rng(3)), out, "repeatable");
  assert.deepEqual(assignAgentCats(pills, out, "cloud", noRand), out, "a second pass changes nothing and draws nothing");
  assert.deepEqual(assignAgentCats(null, { agent_x: "momo" }, "cloud", noRand), { agent_x: "momo" });
  const before = { integration_claude: "oreo", agent_codex: "blue", agent_gemini: "latte" };
  const after = assignAgentCats(["integration_claude", "agent_codex", "agent_gemini"], {}, "shrimpy", rng(4));
  assert.deepEqual(Object.keys(after), ["agent_gemini"]);
  assert.ok(!["shrimpy", "momo"].includes(after.agent_gemini));
  assert.notDeepEqual(after, before);
  assert.equal(defaultAgentCat("integration_claude"), "shrimpy");
});

test("3000 random calls give a valid coat and a clean map", () => {
  const r = rng(31337), pool = ["agent_a", "agent_b", "agent_codex", "integration_claude", "integration_stripe", "ai_openai", "Bad", "__proto__", "constructor", "", null, 7, "agent_", "agent_x"];
  for (let i = 0; i < 3000; i++) {
    const map = Object.fromEntries(Array.from({ length: Math.floor(r() * 8) }, () => [pool[Math.floor(r() * pool.length)], r() < 0.7 ? IDS[Math.floor(r() * 16)] : pool[Math.floor(r() * pool.length)]]).filter(([k]) => typeof k === "string"));
    const pill = pool[Math.floor(r() * pool.length)], main = r() < 0.8 ? IDS[Math.floor(r() * 16)] : pool[Math.floor(r() * pool.length)];
    for (const fn of [agentCatFor, rerollAgentCat]) {
      const out = fn(pill, map, main, rng(i));
      assert.ok(IDS.includes(out.cat), JSON.stringify({ pill, map, main }));
      assert.deepEqual(cleanAgentCats(out.agentCats), out.agentCats);
    }
  }
});
EOF
```

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/cast.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { STATES } from "../../src/cat/base.ts";
import { CAT_IDS } from "../../src/cat/presets.ts";
import { DISPLAY_MODES } from "../../src/cat/display.ts";
import { PILL_ROW, busyRank, castOf } from "../../src/cat/cast.ts";
import { load, same } from "./util.mjs";

// Which cat appears where, replayed from tests/fixtures/cat/cast-cases.json (B-0) in all three modes, and the situations a JSON file cannot hold.
const fx = load("cast-cases.json");
const T = (id, state = "idle", last = 0) => ({ id, state, last });
const ISLAND = [T("integration_claude", "working", 100), T("agent_codex", "approval", 90), T("agent_gemini", "thinking", 80), T("agent_antigravity", "idle", 10), T("integration_stripe", "idle", 5), T("integration_music", "idle", 1)];
const IN = (o = {}) => ({ tasks: ISLAND, focusId: "integration_claude", mainCat: "ginger", pair: ["latte", "cloud"], agentCats: { agent_gemini: "oreo", agent_antigravity: "leo" }, ...o });
const catsOf = (c) => c.pills.map((p) => `${p.pill}:${p.cat}`);

test("the frozen values and the ranks of the states are the fixture's", () => {
  assert.deepEqual(fx.ids, [...CAT_IDS]);
  assert.deepEqual(fx.modes, [...DISPLAY_MODES]);
  assert.equal(fx.pillRow, PILL_ROW);
  assert.deepEqual(fx.states, [...STATES]);
  for (const r of fx.busyRank) assert.equal(busyRank(r.state), r.rank, r.state);
  assert.deepEqual(fx.busyRank.map((r) => r.rank), [3, 2, 2, 2, 0, 0, 1, 3, 3, 3, 3, 3]);
});

test("castOf replays every case of the fixture: the scenarios, the rankings and the hostile inputs, in all three modes and for unknown modes", () => {
  assert.ok(fx.cases.length >= 136);
  for (const c of fx.cases) same(castOf(c.mode, c.input), c.out, `${c.name} (${c.mode})`);
});

test("One cat: the Main cat in every place and nothing in the second spot; A cat for each agent: each agent pill in its own cat, integrations in the Main cat", () => {
  const one = castOf("one", IN());
  assert.deepEqual(one.big, { pill: "integration_claude", cat: "ginger" });
  assert.equal(one.second, null);
  assert.deepEqual(catsOf(one), ["agent_codex:ginger", "agent_gemini:ginger", "agent_antigravity:ginger", "integration_stripe:ginger"]);
  assert.deepEqual(one.greeting, { cat: "ginger", pair: null, sessions: ["ginger", "ginger", "ginger", "ginger"] });
  const per = castOf("perAgent", IN({ focusId: "agent_gemini" }));
  assert.deepEqual(per.big, { pill: "agent_gemini", cat: "oreo" });
  assert.deepEqual(catsOf(per), ["integration_claude:shrimpy", "agent_codex:momo", "agent_antigravity:leo", "integration_stripe:ginger"]);
  assert.equal(per.drop, "oreo");
  assert.deepEqual(per.greeting.sessions, ["shrimpy", "momo", "leo", "ginger"]);
  assert.deepEqual(castOf("perAgent", IN({ focusId: "integration_stripe" })).big, { pill: "integration_stripe", cat: "ginger" }, "an integration in focus: the Main cat");
  assert.equal(castOf("perAgent", IN({ focusId: "agent_unseen" })).big.cat, "ginger", "an agent with no coat yet wears the Main cat until it is given one");
});

test("Two cats: cat 1 is the focused pill in the pair's first coat, cat 2 the busiest other agent in the second, who leaves the row", () => {
  const two = castOf("two", IN());
  assert.deepEqual(two.big, { pill: "integration_claude", cat: "latte" });
  assert.deepEqual(two.second, { pill: "agent_codex", cat: "cloud" }, "Codex waits for approval");
  assert.deepEqual(catsOf(two), ["agent_gemini:ginger", "agent_antigravity:ginger", "integration_stripe:ginger", "integration_music:ginger"]);
  assert.equal(two.drop, "latte");
  assert.deepEqual(two.greeting.pair, ["latte", "cloud"]);
  assert.equal(castOf("two", IN({ pair: ["momo", "momo"] })).second.cat, "ginger", "the same coat twice: cat 2 is the next one");
  assert.deepEqual(castOf("two", { tasks: [T("integration_claude", "working", 1)], focusId: "integration_claude", mainCat: "ginger" }).second, { pill: null, cat: "momo" }, "no other agent: cat 2 idles, with no pill");
});

test("tasks that are not a list, pills that are not pill IDs, a time that is not a time and a state that is not a state never throw", () => {
  for (const mode of DISPLAY_MODES) for (const tasks of [null, undefined, 7, "x", [null, 7, "x", [], {}, { id: 7 }, { id: "Bad Id" }], [{ id: "agent_a", state: "bogus", last: NaN }, { id: "agent_a" }]]) {
    const c = castOf(mode, { tasks, focusId: null, mainCat: "tiger" });
    assert.ok(c.pills.length <= PILL_ROW && c.pills.every((p) => CAT_IDS.includes(p.cat)));
    assert.equal(c.big.cat, "shrimpy", "no Main cat that is a cat, and no pair: Shrimpy");
  }
  assert.equal(castOf("two", { tasks: [T("integration_claude"), { id: "agent_a", state: "bogus", last: NaN }], focusId: "integration_claude" }).second.pill, "agent_a");
  assert.equal(castOf("two", undefined).mode, "two");
  assert.equal(castOf("bogus", IN()).mode, "one");
});
EOF
```

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/places.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { PAIR, VIEW_LAYOUTS, botPosition, pairPlacement } from "../../src/core/layout.ts";
import { AGENT_PILL_COLORS, agentColor, agentLabel, pillColor } from "../../src/core/pills.ts";

// The places of Two cats mode and the names and colours of the agents Settings lists.
test("compact: two Ø20 cats share the left ear, 24 px apart; the one cat is where it always was", () => {
  const p = pairPlacement("compact", "overview", 32);
  assert.deepEqual(p, { first: { cx: 30, cy: 16, diameter: 20, opacity: 1 }, second: { cx: 54, cy: 16, diameter: 20, opacity: 1 } });
  assert.deepEqual(botPosition("compact", "overview", 32), { cx: 40, cy: 16, diameter: 20, opacity: 1 }, "One cat mode keeps today's place");
  assert.equal(p.second.cx - p.first.cx, 24);
});

test("expanded, in the overview: cat 1 at Ø58 and cat 2 at Ø46 side by side around the card's middle; any other view or mode has no pair", () => {
  const h = VIEW_LAYOUTS.overview.height, mid = botPosition("expanded", "overview", h).cy, p = pairPlacement("expanded", "overview", h);
  assert.deepEqual(p.first, { cx: 56, cy: mid - 3, diameter: 58, opacity: 1 });
  assert.deepEqual(p.second, { cx: 114, cy: mid + 5, diameter: 46, opacity: 1 });
  assert.equal(p.second.cx - p.second.diameter / 2 - (p.first.cx + p.first.diameter / 2), 6); // the heads are side by side with a 6 px gap: the prototype's pair, cat 2 at 114
  assert.ok(p.first.cy + p.first.diameter / 2 <= h && p.second.cy + p.second.diameter / 2 <= h, "both heads inside the island");
  for (const view of Object.keys(VIEW_LAYOUTS)) if (view !== "overview") assert.equal(pairPlacement("expanded", view, VIEW_LAYOUTS[view].height), null, view);
  assert.equal(pairPlacement("hidden", "overview", 0), null);
  assert.deepEqual(PAIR.compact, { d: 20, x1: 30, x2: 54 });
});

test("agentLabel names an agent pill as the Mac does, and any other tag by itself; pillColor is the pill's colour", () => {
  for (const [id, name] of [["integration_claude", "Claude Code"], ["agent_gemini", "Gemini CLI"], ["agent_antigravity", "Antigravity"], ["agent_codex", "Codex"], ["agent_cursor", "Cursor"], ["agent_my-tool", "My-tool"], ["agent_x", "X"]]) assert.equal(agentLabel(id), name, id);
  for (const odd of ["agent_", "", "constructor", "__proto__", "integration_stripe"]) assert.equal(typeof agentLabel(odd), "string", odd);
  assert.equal(agentLabel("constructor"), "Constructor", "a prototype name is just a name");
  assert.equal(pillColor("integration_claude"), "#F5F6F8");
  assert.equal(pillColor("agent_gemini"), AGENT_PILL_COLORS.agent_gemini);
  assert.equal(pillColor("agent_my-agent"), agentColor("my-agent"));
  assert.match(pillColor("integration_stripe"), /^#[0-9A-F]{6}$/);
});
EOF
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/agentcat.test.mjs scripts/cat-tests/cast.test.mjs scripts/cat-tests/places.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..`
Expected: `# tests 3`, `# pass 0`, `# fail 3` (no `agentcat.ts`, `cast.ts` or `PAIR` yet).

- [ ] **Step 3: Write the modules and the helpers**

```bash
mkdir -p windows/src/cat
cat > windows/src/cat/agentcat.ts <<'EOF'
// Giving each agent its cat (sub-project B, spec §1): Claude Code is Shrimpy and Codex is Momo; any other agent, the first time it is seen, gets a random coat that
// no other agent and not the Main cat uses, and keeps it. A port of "Display modes: giving agents their cats" in design/prototype/cat-core.js (the tie-breaker;
// fixture tests/fixtures/cat/agent-cat-cases.json). Pure: the random source is injected (`rand()`, 0 up to, not including, 1), so a test repeats.
// Imports base.ts, presets.ts, settings.ts and display.ts, so the plain-Node checks (npm run check:cat) can load it.

import { own } from "./base.ts";
import { CAT_IDS } from "./presets.ts";
import { catIdOf } from "./settings.ts";
import { DEFAULT_AGENT_CATS, cleanAgentCats, defaultAgentCat, isAgentPill } from "./display.ts";

export type Rand = () => number;

/**
 * One coat for a new agent. `taken` lists the cat IDs already in use (a coat used twice is listed twice), `rand` returns 0 up to, not including, 1, and `avoid` is a
 * coat that is never chosen. A coat nobody uses is chosen at random (rand() is called once, and only then); when every coat is in use, the least-used one is chosen,
 * ties broken in CAT_IDS order (rand() is not called). A `rand` that is not a function, or a number that is not finite, is 0, and 1 or more is the last free coat.
 */
export function pickCat(taken: readonly string[], rand?: unknown, avoid?: string | null): string {
  const use = new Map<string, number>();
  for (const c of taken) use.set(c, (use.get(c) ?? 0) + 1);
  const pool = CAT_IDS.filter((c) => c !== avoid), free = pool.filter((c) => !use.has(c));
  if (free.length) {
    const r = typeof rand === "function" ? (rand as Rand)() : 0;
    return free[Math.min(free.length - 1, Math.max(0, Math.floor(typeof r === "number" && Number.isFinite(r) ? r * free.length : 0)))];
  }
  let best = pool[0];
  for (const c of pool) if ((use.get(c) ?? 0) < (use.get(best) ?? 0)) best = c;
  return best;
}

export interface AgentCatResult { cat: string; agentCats: Record<string, string>; assigned: boolean }

/**
 * The cat of an agent pill: its stored coat, else its default (Claude Code Shrimpy, Codex Momo), else a coat chosen now: random, from those used neither by another
 * agent (a stored one, or a default that no stored coat has replaced) nor as the Main cat; when all 16 are taken, the least-used (see pickCat). `agentCats` in the
 * result is the cleaned map, with the new pill added when `assigned` is true, which is the app's cue to store it, and never to change it by itself afterwards.
 * A pill that is not an agent pill (an integration, or an ID that is not a pill ID) gets the Main cat and is never stored.
 */
export function agentCatFor(pillId: unknown, agentCats: unknown, mainCat: unknown, rand?: unknown): AgentCatResult {
  const map = cleanAgentCats(agentCats), main = catIdOf(mainCat);
  if (!isAgentPill(pillId)) return { cat: main, agentCats: map, assigned: false };
  if (own(map, pillId)) return { cat: map[pillId], agentCats: map, assigned: false };
  const d = defaultAgentCat(pillId);
  if (d) return { cat: d, agentCats: map, assigned: false };
  const cat = pickCat([...Object.values({ ...DEFAULT_AGENT_CATS, ...map }), main], rand, null), next = cleanAgentCats({ ...map, [pillId]: cat });
  return { cat, agentCats: next, assigned: own(next, pillId) };
}

/**
 * The dice button: a new random coat for one agent. Its current coat (stored or default) is never chosen again, and the rest is agentCatFor's rule, with this agent's
 * own coat set aside. Always stored, a default agent included. Returns {cat, agentCats}.
 */
export function rerollAgentCat(pillId: unknown, agentCats: unknown, mainCat: unknown, rand?: unknown): { cat: string; agentCats: Record<string, string> } {
  const map = cleanAgentCats(agentCats), main = catIdOf(mainCat);
  if (!isAgentPill(pillId)) return { cat: main, agentCats: map };
  const eff: Record<string, string> = { ...DEFAULT_AGENT_CATS, ...map }, cur = eff[pillId] ?? null;
  delete eff[pillId];
  const cat = pickCat([...Object.values(eff), main], rand, cur);
  return { cat, agentCats: cleanAgentCats({ ...map, [pillId]: cat }) };
}

/** agentCatFor for each pill in turn (integrations are skipped): the map after every agent has a coat. "Reset to defaults" is this with an empty map. */
export function assignAgentCats(pillIds: unknown, agentCats: unknown, mainCat: unknown, rand?: unknown): Record<string, string> {
  let map = cleanAgentCats(agentCats);
  for (const id of Array.isArray(pillIds) ? pillIds : []) map = agentCatFor(id, map, mainCat, rand).agentCats;
  return map;
}
EOF
```

```bash
mkdir -p windows/src/cat
cat > windows/src/cat/cast.ts <<'EOF'
// Which cat appears where (sub-project B, spec §2). A cat stands for an agent's pill, and the big cat shows the focused pill. For the chosen display mode,
// `castOf` says which coat each place wears: the big cat, a second cat (Two cats), the pills and the 2×2 grid, the drop view and the launch greeting. A port of
// "Display modes: which cat appears where (the cast)" in design/prototype/cat-core.js (the tie-breaker; fixture tests/fixtures/cat/cast-cases.json;
// docs/CAT-CONTRACT.md "The cast"). Pure: no clock, no random numbers. Imports base.ts and display.ts, so the plain-Node checks (npm run check:cat) can load it.
//
//   one:      the Main cat everywhere.
//   perAgent: the focused agent's cat is the big cat (the Main cat when the focus is an integration or nothing); every agent pill wears its agent's cat;
//             integration pills wear the Main cat.
//   two:      the pair: cat 1 is the big cat and shows the focused pill, cat 2 shows the busiest other agent; pills wear the Main cat.

import { BUSY, STATES, own } from "./base.ts";
import type { StateName } from "./base.ts";
import { catIdOf } from "./settings.ts";
import { cleanAgentCats, cleanPair, defaultAgentCat, displayModeOf, isAgentPill, isPillId } from "./display.ts";
import type { DisplayMode } from "./display.ts";

/** The most pills the row and the 2×2 grid hold (the island shows `otherTasks.slice(0, 4)`). */
export const PILL_ROW = 4;

/** How busy an agent is, for the busiest-other rule: 0 waits for you (approval or question), 1 error, 2 working, thinking or searching, 3 anything else. */
export const busyRank = (st: unknown): 0 | 1 | 2 | 3 => (st === "approval" || st === "question" ? 0 : st === "error" ? 1 : BUSY.has(st as StateName) ? 2 : 3);
const rankKey = (a: readonly number[], b: readonly number[]): number => {
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i] - b[i];
  return 0;
};

/** One pill of the island, in the app's order: the pill ID, its state (anything that is not one of STATES is idle) and the time of its last event in ms (any one clock). */
export interface CastTask { id: string; state: string; last: number }
export interface CastPill { pill: string; cat: string }
export interface Cast {
  mode: DisplayMode;
  /** The big cat: the focused pill (null when there is none) and its coat. */
  big: { pill: string | null; cat: string };
  /** Two cats mode: the busiest other agent (`pill` is null when no other agent exists: cat 2 idles, no badge) and pair cat 2. Null in the other modes. */
  second: { pill: string | null; cat: string } | null;
  /** The row and the grid: the tasks other than the focus (and other than `second.pill`), the first PILL_ROW of them, in the app's order. */
  pills: CastPill[];
  /** The cat of the drop view and the drag ghost: the big cat's. */
  drop: string;
  /** The launch greeting: the cat that falls in (the Main cat), the pair that arrives together (Two cats mode) or null, and the four session cats in the grid's cell order. */
  greeting: { cat: string; pair: [string, string] | null; sessions: string[] };
}

/**
 * The cast of one mode. `input` is {tasks, focusId, mainCat, pair, agentCats}: `tasks` the island's pills (a pill listed twice counts once, an ID that is not a pill ID
 * is skipped, a `last` that is not a finite number is 0), `focusId` the focused pill or null, and the three settings as stored (they are cleaned here, so a raw value
 * is fine). An agent that has no stored coat and no default wears the Main cat here: agentCatFor gives it one when it is first seen, before it is drawn. Never throws.
 */
export function castOf(mode: unknown, input: unknown): Cast {
  const m = displayModeOf(mode), inp: Record<string, unknown> = input !== null && typeof input === "object" && !Array.isArray(input) ? (input as Record<string, unknown>) : {};
  const main = catIdOf(inp.mainCat), pr = cleanPair(inp.pair), map = cleanAgentCats(inp.agentCats), seen = new Set<string>(), list: CastTask[] = [];
  for (const t of Array.isArray(inp.tasks) ? inp.tasks : []) {
    if (t === null || typeof t !== "object" || Array.isArray(t) || !isPillId(t.id) || seen.has(t.id)) continue;
    seen.add(t.id);
    list.push({ id: t.id, state: (STATES as readonly unknown[]).includes(t.state) ? (t.state as string) : "idle", last: typeof t.last === "number" && Number.isFinite(t.last) ? t.last : 0 });
  }
  const focus = isPillId(inp.focusId) ? inp.focusId : null;
  const agentCat = (id: string): string => (own(map, id) ? map[id] : defaultAgentCat(id) || main);
  const catOf = (id: string | null): string => (m === "perAgent" && id !== null && isAgentPill(id) ? agentCat(id) : main);
  const big = { pill: focus, cat: m === "two" ? pr[0] : catOf(focus) };
  let second: Cast["second"] = null;
  if (m === "two") {
    let bestId: string | null = null, bestKey: number[] = [];
    for (let i = 0; i < list.length; i++) {
      const t = list[i];
      if (t.id === focus || !isAgentPill(t.id)) continue;
      const key = [busyRank(t.state), -t.last, i];
      if (bestId === null || rankKey(key, bestKey) < 0) { bestId = t.id; bestKey = key; }
    }
    second = { pill: bestId, cat: pr[1] };
  }
  const pills = list.filter((t) => t.id !== focus && !(second && t.id === second.pill)).slice(0, PILL_ROW).map((t) => ({ pill: t.id, cat: catOf(t.id) }));
  return { mode: m, big, second, pills, drop: big.cat, greeting: { cat: main, pair: m === "two" ? pr : null, sessions: [0, 1, 2, 3].map((i) => (pills[i] ? pills[i].cat : main)) } };
}
EOF
```

`pills.ts` gets the names and colours Settings lists, and `layout.ts` the pair's places (the prototype's numbers: compact two Ø20 cats at 30 and 54, expanded Ø58 and Ø46 side by side in the overview).

```bash
python3 - <<'PY'
# Task 4: the helpers the lists of agents need (core/pills.ts), and the pair's places in the island (core/layout.ts). Run from the repository root.
# Every replacement asserts that its anchor is there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('windows/src/core/pills.ts', [
('''/** The colour of the pill for `nm_agent` = `name`: its catalogue colour, else a stable hash of the name. */''',
 '''/** The names the Mac's PillCatalog gives the agents. Any other tagged agent is its tag, capitalised. */
const AGENT_NAMES: Readonly<Record<string, string>> = { claude: "Claude Code", gemini: "Gemini CLI", antigravity: "Antigravity", codex: "Codex", cursor: "Cursor" };

/** The colour of the pill for `nm_agent` = `name`: its catalogue colour, else a stable hash of the name. */'''),
])
s = open('windows/src/core/pills.ts', encoding='utf-8').read().rstrip('\n')
s += '''

/**
 * The name of an agent pill for a person (Settings → Cat → Display, the second line of the Two cats ticker): `integration_claude` is Claude Code (its pill on the island is
 * still labelled "VS Code"), `agent_<tag>` is the agent's name. Any other ID is itself.
 */
export function agentLabel(pillId: string): string {
  const tag = pillId === "integration_claude" ? "claude" : pillId.startsWith("agent_") ? pillId.slice(6) : pillId;
  if (Object.hasOwn(AGENT_NAMES, tag)) return AGENT_NAMES[tag];
  return tag ? tag[0].toUpperCase() + tag.slice(1) : pillId;
}

/** The colour of an agent pill: the VS Code pill's for Claude Code, `agentColor` for `agent_<tag>`, a grey for anything else. */
export function pillColor(pillId: string): string {
  if (pillId === "integration_claude") return "#F5F6F8";
  return pillId.startsWith("agent_") ? agentColor(pillId.slice(6)) : "#8D9098";
}
'''
open('windows/src/core/pills.ts', 'w', encoding='utf-8').write(s)

edit('windows/src/core/layout.ts', [
('''export function botGlowColor(s: BotStateName): string {''', '''/**
 * Two cats mode (spec §2): where the pair sits, in px from the island's left edge, and the cats' head widths. Compact: two Ø20 cats share the left ear, at 30 and 54.
 * Expanded, in the overview: cat 1 at Ø58 and cat 2 at Ø46 side by side with a 6 px gap between the heads (the owner made room at B-0's checkpoint: cat 2 at 114), 3 px above
 * and 5 px below the card's middle. The numbers are the prototype's mock-up
 * (design/prototype/notchmeow.html, `drawDesk`), a reference and not part of the contract.
 */
export const PAIR = {
  compact: { d: 20, x1: 30, x2: 54 },
  expanded: { d1: 58, x1: 56, dy1: -3, d2: 46, x2: 114, dy2: 5 },
} as const;

/**
 * The two cats of Two cats mode: compact, or expanded in the overview (every other view keeps its one cat where it is, so the cards' text is never covered). Null when the
 * island is hidden or the view is not the overview. `islandH` is the island's height now.
 */
export function pairPlacement(mode: IslandMode, view: IslandViewName, islandH: number): { first: BotPlacement; second: BotPlacement } | null {
  if (mode === "compact") {
    const c = PAIR.compact;
    return { first: { cx: c.x1, cy: 16, diameter: c.d, opacity: 1 }, second: { cx: c.x2, cy: 16, diameter: c.d, opacity: 1 } };
  }
  if (mode !== "expanded" || view !== "overview") return null;
  const e = PAIR.expanded, cy = botPosition(mode, view, islandH).cy;
  return { first: { cx: e.x1, cy: cy + e.dy1, diameter: e.d1, opacity: 1 }, second: { cx: e.x2, cy: cy + e.dy2, diameter: e.d2, opacity: 1 } };
}

export function botGlowColor(s: BotStateName): string {'''),
])
PY
```

- [ ] **Step 4: Run the tests and the type check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/agentcat.test.mjs scripts/cat-tests/cast.test.mjs scripts/cat-tests/places.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"; npx --no-install tsc --noEmit; echo "tsc exit $?"; cd ..`
Expected: `# tests 18`, `# pass 18`, `# fail 0`, `tsc exit 0`.

- [ ] **Step 5: Prove the least-used tie rule bites (not committed)**

```bash
python3 - <<'PY'
import subprocess
p = 'windows/src/cat/agentcat.ts'
s = open(p, encoding='utf-8').read()
was = 'if ((use.get(c) ?? 0) < (use.get(best) ?? 0)) best = c;'
assert s.count(was) == 1
run = lambda: print(subprocess.run('cd windows && node --experimental-strip-types --test scripts/cat-tests/agentcat.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"', shell=True, capture_output=True, text=True).stdout, end='')
open(p, 'w', encoding='utf-8').write(s.replace(was, 'if ((use.get(c) ?? 0) <= (use.get(best) ?? 0)) best = c;'))
run()
open(p, 'w', encoding='utf-8').write(s)
run()
PY
```

Expected: the first run prints `not ok 1 - agentCatFor, rerollAgentCat and assignAgentCats replay every row of the fixture, with the same number of random draws` and `not ok 5 - when all 16 coats are taken, the least-used one is chosen, ties in CAT_IDS order, and no random number is drawn`, then `# pass 8` and `# fail 2`; after the line is put back, `# pass 10` and `# fail 0`.

- [ ] **Step 6: Run the whole cat check and commit**

Run: `cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `ℹ tests 212`, `ℹ pass 212`, `ℹ fail 0`.

```bash
git add windows/scripts/cat-tests/agentcat.test.mjs windows/scripts/cat-tests/cast.test.mjs windows/scripts/cat-tests/places.test.mjs windows/src/cat/agentcat.ts windows/src/cat/cast.ts windows/src/core/pills.ts windows/src/core/layout.ts
git commit -m "feat(cat): the agents' coats, the cast of each mode and the pair's places

agentCatFor, rerollAgentCat and assignAgentCats give Claude Code Shrimpy, Codex Momo and every other agent a random coat
that is nobody else's, with the random source injected; castOf says which coat the big cat, the second cat, the pills, the
drop view and the greeting wear in each mode. Both replay B-0's fixtures. agentLabel and pillColor name and colour an
agent pill; PAIR and pairPlacement hold Two cats mode's places, the prototype's numbers. Nothing uses them yet.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 5: The Display settings in Rust, carried through `settings.rs`; the relay keeps `agent_id`

**Agent:** `nm-implementer`. Needs Docker (`notchmeow-linux-dev`); without it, stop and report.

**Files:**
- Modify: `windows/src-tauri/src/cat_settings.rs`, `windows/src-tauri/src/settings.rs`, `windows/hook/src/main.rs`

**Interfaces:**
- Consumes: B-0's `display-cases.json`; `cat_settings.rs`'s `clean_cat_settings`, `word`, `CAT_IDS`, `NULL`, and its tests' `fixture`, `assert_same`; `settings.rs`'s `sanitized`, `load_from`, `OLD_FILE`.
- Produces: `DISPLAY_MODES`, `MAX_AGENT_CATS`, `is_pill_id`, `default_agent_cat`, `clean_pair`, `clean_agent_cats`, `clean_display_settings`, `clean_cat_block`, `block_default` (all in `cat_settings.rs`); `Settings.cat` is the whole block, cleaned by `sanitized` and defaulted by `block_default`; `default_value` and `is_agent_pill` are test-only. The TypeScript side already holds the same block (Task 3).

- [ ] **Step 1: Check the image and see the starting point**

```bash
docker image inspect notchmeow-linux-dev >/dev/null && echo "image ok"
bash windows/scripts/cargo-linux.sh test -p notchmeow --target-dir /repo/windows/target/b-tauri -- cat_settings:: settings:: 2>&1 | grep -E "^test result|^error|^warning"
```

Expected: `image ok`, then `test result: ok. 17 passed` for the app's library (the first run in a new target directory compiles every dependency, which takes several minutes) and two more `test result: ok. 0 passed` lines, and no `warning` or `error`.

- [ ] **Step 2: Write the tests**

The Display clean-up's tests, in `cat_settings.rs` (the fixture's every row, a hostile fuzz, the whole block) and `settings.rs` (a save and a load, bad display keys that must not fail the file), a relay test, and the two older `settings.rs` tests that compared with the Cat settings' defaults now compare with the whole block's.

```bash
python3 - <<'PY'
# Task 5, tests first: the Display settings in Rust, which do not compile until the code of the next step is in (`clean_pair`, `clean_cat_block` and `block_default` do not exist yet),
# and a relay test that a subagent's `agent_id` and `agent_type` already reach the island. Run from the repository root.
# Every replacement asserts that its anchor is there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

# The tests of the Display clean-up, at the end of the tests module (the module's last closing brace is the file's last line).
s = open('windows/src-tauri/src/cat_settings.rs', encoding='utf-8').read()
assert s.rstrip().endswith('}')
tests = r'''
    // ── The Display settings ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

    #[test]
    fn the_display_frozen_values_are_the_fixtures() {
        let fx = fixture("display-cases.json");
        assert_eq!(fx["modes"], json!(DISPLAY_MODES));
        assert_eq!(fx["defaultPair"], json!(DEFAULT_PAIR));
        assert_eq!(fx["defaultAgentCats"], json!({"integration_claude": "shrimpy", "agent_codex": "momo"}));
        assert_eq!(fx["maxAgentCats"], json!(MAX_AGENT_CATS));
        assert_eq!(fx["pillIdPattern"], "^[a-z][a-z0-9_-]{1,63}$");
        assert_same(&clean_display_settings(&Value::Null), &fx["defaults"], "defaults");
    }

    #[test]
    fn every_display_case_of_the_fixture_replays() {
        let fx = fixture("display-cases.json");
        let (cases, pairs, agents, ids) = (fx["cases"].as_array().unwrap(), fx["pairs"].as_array().unwrap(), fx["agentCats"].as_array().unwrap(), fx["pillIds"].as_array().unwrap());
        assert!(cases.len() >= 30 && pairs.len() >= 40 && agents.len() >= 21 && ids.len() >= 29);
        for c in cases {
            assert_same(&clean_display_settings(&c["raw"]), &c["out"], c["name"].as_str().unwrap());
        }
        for c in pairs {
            assert_same(&json!(clean_pair(&c["raw"])), &c["out"], c["name"].as_str().unwrap());
        }
        for c in agents {
            assert_same(&clean_agent_cats(&c["raw"]), &c["out"], c["name"].as_str().unwrap());
        }
        for c in ids {
            let id = c["id"].as_str().unwrap();
            let got = json!({"id": id, "pill": is_pill_id(id), "agent": is_agent_pill(id), "default": default_agent_cat(id)});
            assert_eq!(&got, c, "{id:?}");
        }
    }

    #[test]
    fn a_pill_id_is_the_whole_string_and_never_a_prototype_name() {
        for bad in ["agent_x\n", "agent_x ", "agent_x\r\n", "\nagent_x", "agent_é", "Agent_x", "_agent", "a", "", "constructor", "prototype", "__proto__"] {
            assert!(!is_pill_id(bad), "{bad:?}");
        }
        assert!(is_pill_id("agent_x") && is_pill_id(&format!("a{}", "b".repeat(63))) && !is_pill_id(&format!("a{}", "b".repeat(64))));
        assert!(is_agent_pill("integration_claude") && is_agent_pill("agent_x") && !is_agent_pill("agent_") && !is_agent_pill("integration_stripe"));
    }

    #[test]
    fn the_whole_block_keeps_both_parts_and_a_clean_up_with_the_cat_settings_alone_drops_the_display_keys() {
        let raw = json!({"character": "momo", "collar": "band", "displayMode": "two", "pair": ["ginger", "latte"], "agentCats": {"agent_gemini": "oreo", "constructor": "momo"}});
        let block = clean_cat_block(&raw);
        assert_eq!(block["character"], "momo");
        assert_eq!(block["displayMode"], "two");
        assert_eq!(block["pair"], json!(["ginger", "latte"]));
        assert_eq!(block["agentCats"], json!({"agent_gemini": "oreo"}));
        assert_eq!(block["cats"].as_object().unwrap().len(), 16);
        assert!(clean_cat_settings(&raw).get("displayMode").is_none(), "that is why the block has a clean-up of its own");
        assert_eq!(clean_cat_block(&block), block, "cleaning twice changes nothing");
        assert_eq!(block_default()["displayMode"], "one");
        assert_eq!(block_default()["pair"], json!(["shrimpy", "momo"]));
        assert_eq!(block_default()["agentCats"], json!({}));
        assert_same(&clean_cat_settings(&block_default()), &fixture("settings-cases.json")["defaults"], "the Cat part of the default block");
        assert_eq!(clean_cat_block(&json!(5)), block_default());
    }

    #[test]
    fn hostile_display_values_never_panic_come_out_valid_and_cleaning_twice_changes_nothing() {
        let pool = vec![
            json!("one"), json!("two"), json!("perAgent"), json!("Two"), json!(""), json!(" "), json!("momo"), json!("tiger"), json!("[\"momo\",\"ginger\"]"), json!("[\"momo\""),
            json!("__proto__"), json!("constructor"), json!("agent_x"), json!("agent_codex"), json!("integration_claude"), Value::Null, json!(true), json!(0), json!(-1), json!(0.5), json!(7),
            json!(u64::MAX), json!([]), json!(["momo"]), json!(["momo", "ginger"]), json!(["ginger", "ginger"]), json!([1, 2]), json!({}), json!({"agent_x": "latte"}), json!({"agent_codex": "tiger"}),
        ];
        let mut state: u32 = 2027;
        let mut next = move || {
            state = state.wrapping_mul(1_103_515_245).wrapping_add(12_345);
            (state >> 8) as usize
        };
        for _ in 0..600 {
            let pick = |n: usize| pool[n % pool.len()].clone();
            let agents = if next() % 6 == 0 {
                pick(next())
            } else {
                let mut m = Map::new();
                for _ in 0..next() % 6 {
                    if let Some(k) = pick(next()).as_str() {
                        m.insert(k.to_string(), pick(next()));
                    }
                }
                Value::Object(m)
            };
            let raw = json!({"displayMode": pick(next()), "pair": pick(next()), "agentCats": agents});
            let out = clean_display_settings(&raw);
            let pair: Vec<&str> = out["pair"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
            assert!(DISPLAY_MODES.contains(&out["displayMode"].as_str().unwrap()) && pair.len() == 2 && pair.iter().all(|c| CAT_IDS.contains(c)) && pair[0] != pair[1], "{raw}");
            let keys: Vec<&String> = out["agentCats"].as_object().unwrap().keys().collect();
            let mut sorted = keys.clone();
            sorted.sort();
            assert!(keys == sorted && keys.len() <= MAX_AGENT_CATS && keys.iter().all(|k| is_pill_id(k)), "{raw}");
            assert!(out["agentCats"].as_object().unwrap().values().all(|v| cat_id(v).is_some()), "{raw}");
            assert_eq!(clean_display_settings(&out), out, "{raw}");
        }
        for raw in [Value::Null, json!(5), json!("junk"), json!([]), json!({}), json!({"pair": 7, "agentCats": 7, "displayMode": 7})] {
            assert_eq!(clean_display_settings(&raw), clean_display_settings(&Value::Null), "{raw}");
        }
        let evil: Value = serde_json::from_str(r#"{"agentCats":{"__proto__":"momo","constructor":"momo","prototype":"momo","agent_ok":"ginger"}}"#).unwrap();
        assert_eq!(clean_display_settings(&evil)["agentCats"], json!({"agent_ok": "ginger"}));
        let many: Map<String, Value> = (0..300).map(|i| (format!("agent_a{i:03}"), json!(CAT_IDS[i % 16]))).collect();
        let out = clean_agent_cats(&Value::Object(many));
        let keys: Vec<&String> = out.as_object().unwrap().keys().collect();
        assert_eq!((keys.len(), keys[0].as_str(), keys[255].as_str()), (256, "agent_a000", "agent_a255"), "300 pills keep the first 256");
    }
}
'''
s = s.rstrip()
s = s[:-1].rstrip() + '\n' + tests  # replace the module's closing brace with the new tests and a closing brace
open('windows/src-tauri/src/cat_settings.rs', 'w', encoding='utf-8').write(s)

# The two settings.rs tests that compared with the Cat settings' defaults compare with the whole block's now.
edit('windows/src-tauri/src/settings.rs', [
('''        assert_eq!(s.cat, crate::cat_settings::default_value());
        assert_eq!(s.cat["character"], "shrimpy");''', '''        assert_eq!(s.cat, crate::cat_settings::block_default());
        assert_eq!(s.cat["character"], "shrimpy");
        assert_eq!((&s.cat["displayMode"], &s.cat["pair"], &s.cat["agentCats"]), (&serde_json::json!("one"), &serde_json::json!(["shrimpy", "momo"]), &serde_json::json!({})));'''),
('''            assert_eq!(s.cat, crate::cat_settings::default_value(), "{cat}");''', '''            assert_eq!(s.cat, crate::cat_settings::block_default(), "{cat}");'''),
])
s = open('windows/src-tauri/src/settings.rs', encoding='utf-8').read().rstrip()
assert s.endswith('}')
more = r'''

    /// The three display keys sit in the same `cat` block as the Cat settings, which `sanitized` used to rebuild from the Cat settings alone: a save dropped them.
    #[test]
    fn the_display_settings_survive_a_save_a_load_and_a_round_trip() {
        let dir = std::env::temp_dir().join(format!("notchmeow-display-keys-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        let mut s = Settings::default();
        s.cat = serde_json::json!({
            "character": "momo", "collar": "band",
            "displayMode": "perAgent", "pair": ["latte", "cloud"], "agentCats": {"agent_gemini": "oreo", "integration_claude": "leo"}
        });
        // `save_settings` cleans what the webview sends, stores it and writes it: the same three steps, with the file under a temporary folder.
        let sent = sanitized(s);
        assert_eq!(sent.cat["displayMode"], "perAgent");
        std::fs::write(&path, serde_json::to_vec_pretty(&sent).unwrap()).unwrap();
        let back = load_from(&path);
        assert_eq!(back.cat, sent.cat, "what was saved is what loads");
        assert_eq!(back.cat["displayMode"], "perAgent");
        assert_eq!(back.cat["pair"], serde_json::json!(["latte", "cloud"]));
        assert_eq!(back.cat["agentCats"], serde_json::json!({"agent_gemini": "oreo", "integration_claude": "leo"}));
        assert_eq!(back.cat["character"], "momo", "the Cat settings are still there");
        let again: Settings = serde_json::from_value(serde_json::to_value(&back).unwrap()).unwrap();
        assert_eq!(sanitized(again).cat, back.cat, "a second round trip changes nothing");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The webview is not trusted, and a hand-edited file is not either: bad display keys are cleaned without failing the file or touching the rest of the block.
    #[test]
    fn bad_display_keys_are_cleaned_and_one_of_them_never_fails_the_settings_file() {
        let dir = std::env::temp_dir().join(format!("notchmeow-bad-display-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        for cat in [
            r#"{"character":"momo","displayMode":7,"pair":"[\"momo\"","agentCats":[1,2]}"#,
            r#"{"character":"momo","displayMode":"both","pair":["momo","tiger"],"agentCats":{"__proto__":"momo","Agent_X":"momo","agent_ok":"tiger","integration_claude":7}}"#,
            r#"{"character":"momo","displayMode":null,"pair":null,"agentCats":null}"#,
        ] {
            std::fs::write(&path, format!(r#"{OLD_FILE},"cat":{cat}}}"#)).unwrap();
            let s = load_from(&path);
            assert!(!s.sound_enabled && s.screen == "cursor", "the rest of the file is kept: {cat}");
            assert_eq!(s.cat["character"], "momo", "the Cat settings next to them are kept: {cat}");
            assert_eq!(s.cat["displayMode"], "one", "{cat}");
            assert_eq!(s.cat["pair"], serde_json::json!(["shrimpy", "momo"]), "{cat}");
            assert!(s.cat["agentCats"].as_object().unwrap().keys().all(|k| crate::cat_settings::is_pill_id(k)), "{cat}");
            assert!(path.exists(), "the file is not moved aside: {cat}");
        }
        // The webview's own save is cleaned the same way.
        let mut s = Settings::default();
        s.cat = serde_json::json!({"displayMode": "two", "pair": ["momo", "momo"], "agentCats": {"agent_x": "snow", "constructor": "momo"}});
        let cleaned = sanitized(s);
        assert_eq!(cleaned.cat["pair"], serde_json::json!(["momo", "ginger"]));
        assert_eq!(cleaned.cat["agentCats"], serde_json::json!({"agent_x": "snow"}));
        let backups = std::fs::read_dir(&dir).unwrap().filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().starts_with("settings.json.bad-")).count();
        assert_eq!(backups, 0);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
'''
s = s[:-1].rstrip() + more
open('windows/src-tauri/src/settings.rs', 'w', encoding='utf-8').write(s)

# ── the relay: a subagent's ids reach the island ─────────────────────────────────────────────────────────────────────────────────────────────
edit('windows/hook/src/main.rs', [
('''    #[test]
    fn a_payload_the_relay_cannot_use_forwards_nothing() {''', '''    /// Subagent kittens (sub-project B): the island reads `agent_id` and `agent_type` from tool, permission and SubagentStart/SubagentStop events. The relay only
    /// drops `tool_response` and `transcript_path`, so both pass through.
    #[test]
    fn a_subagents_agent_id_and_agent_type_reach_the_island() {
        let stdin = r#"{"hook_event_name":"PreToolUse","session_id":"c-1","agent_id":"a1","agent_type":"Explore","tool_name":"Grep","tool_input":{},"tool_response":"big","transcript_path":"/t"}"#;
        let sent = forwarded(&shape(stdin, &["PreToolUse"], &[]).unwrap());
        assert_eq!((&sent["agent_id"], &sent["agent_type"]), (&serde_json::json!("a1"), &serde_json::json!("Explore")));
        assert!(sent.get("tool_response").is_none() && sent.get("transcript_path").is_none());
        for name in ["SubagentStart", "SubagentStop", "PermissionRequest"] {
            let stdin = format!(r#"{{"hook_event_name":"{name}","session_id":"c-1","agent_id":"a1","agent_type":"Plan"}}"#);
            let sent = forwarded(&shape(&stdin, &[name], &[]).unwrap());
            assert_eq!((&sent["agent_id"], &sent["agent_type"]), (&serde_json::json!("a1"), &serde_json::json!("Plan")), "{name}");
        }
    }

    #[test]
    fn a_payload_the_relay_cannot_use_forwards_nothing() {'''),
])
PY
```

Run: `bash windows/scripts/cargo-linux.sh test -p notchmeow --target-dir /repo/windows/target/b-tauri -- cat_settings:: settings:: 2>&1 | grep -E "^error" | sort | uniq -c | head -6`
Expected: six lines, `1 error: could not compile `notchmeow` (lib test) due to 39 previous errors` and `error[E0425]: cannot find function` for `block_default` (7 times), `cat_id`, `clean_agent_cats` and `clean_cat_block`: the code does not exist yet, so the tests do not compile.

- [ ] **Step 3: Write the code**

```bash
python3 - <<'PY'
# Task 5, the code: clean_display_settings, clean_cat_block and block_default in cat_settings.rs, and the whole block cleaned and defaulted by settings.rs.
# Run from the repository root. Every replacement asserts that its anchor is there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

# ── cat_settings.rs: the module ─────────────────────────────────────────────────────────────────────────────────────────────────
edit('windows/src-tauri/src/cat_settings.rs', [
('''//   { character, motionStyle, collar, furLines, cats: { <catId>: { motion, collar, personality } } }   with all 16 cat IDs once clean.
''', '''//   { character, motionStyle, collar, furLines, cats: { <catId>: { motion, collar, personality } } }   with all 16 cat IDs once clean.
//
// The same block also holds the Display settings (sub-project B, spec §1), cleaned by `clean_display_settings`, a port of `cleanDisplaySettings` in the same file
// of the contract (tests/fixtures/cat/display-cases.json): { displayMode, pair: [catId, catId], agentCats: { <pillId>: <catId> } }. `clean_cat_settings` still
// returns only the five Cat settings and drops those keys, so the block is cleaned with both, by `clean_cat_block`: a clean-up with the Cat settings alone would
// drop the three display keys at the next save.
'''),
('''#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
''', '''// ── The Display settings (sub-project B) ──────────────────────────────────────────────────────────────────────────────────────────────────

/// The display modes, in the order Settings lists them: frozen contract values. An unknown stored mode is `one`.
pub const DISPLAY_MODES: [&str; 3] = ["one", "perAgent", "two"];
/// Two cats mode's pair before the user picks: Shrimpy and Momo.
const DEFAULT_PAIR: [&str; 2] = ["shrimpy", "momo"];
/// A stored map keeps at most this many pills (the first by code-point order of their IDs), so a hostile file cannot grow it without end.
pub const MAX_AGENT_CATS: usize = 256;

/// A pill ID: a lowercase letter, then lowercase letters, digits, `_` and `-`, 2 to 64 characters, the whole string (`^[a-z][a-z0-9_-]{1,63}$`), and not a prototype name.
pub fn is_pill_id(v: &str) -> bool {
    let b = v.as_bytes();
    (2..=64).contains(&b.len())
        && b[0].is_ascii_lowercase()
        && b[1..].iter().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == b'_' || *c == b'-')
        && v != "constructor"
        && v != "prototype"
}

/// Agent pills are Claude Code's pill (`integration_claude`, despite its prefix) and every `agent_*` pill. Only the fixture check uses it here: the island decides
/// which pill is an agent's.
#[cfg(test)]
pub fn is_agent_pill(v: &str) -> bool {
    is_pill_id(v) && (v == "integration_claude" || (v.starts_with("agent_") && v.len() > 6))
}

/// The default coat of an agent pill (Claude Code Shrimpy, Codex Momo), or None.
pub fn default_agent_cat(id: &str) -> Option<&'static str> {
    if !is_pill_id(id) {
        return None;
    }
    match id {
        "integration_claude" => Some("shrimpy"),
        "agent_codex" => Some("momo"),
        _ => None,
    }
}

/// The cat ID a stored value names, matched exactly; None for anything else.
fn cat_id(v: &Value) -> Option<&'static str> {
    v.as_str().and_then(|s| CAT_IDS.iter().copied().find(|c| *c == s))
}

/// A stored pair to two cat IDs. It may be an array or the JSON text of one (the Mac stores text). Anything that is not two valid cat IDs, whole, is Shrimpy and
/// Momo. Two of the same coat make cat 2 the next coat in CAT_IDS order (after the last one, the first).
pub fn clean_pair(raw: &Value) -> [&'static str; 2] {
    let parsed;
    let v = match raw {
        Value::String(text) => match serde_json::from_str::<Value>(text) {
            Ok(p) => {
                parsed = p;
                &parsed
            }
            Err(_) => return DEFAULT_PAIR,
        },
        other => other,
    };
    let Value::Array(a) = v else { return DEFAULT_PAIR };
    if a.len() != 2 {
        return DEFAULT_PAIR;
    }
    let (Some(x), Some(y)) = (cat_id(&a[0]), cat_id(&a[1])) else { return DEFAULT_PAIR };
    if x == y {
        let at = CAT_IDS.iter().position(|c| *c == y).unwrap_or(0);
        [x, CAT_IDS[(at + 1) % CAT_IDS.len()]]
    } else {
        [x, y]
    }
}

/// A stored map from pill ID to cat ID, cleaned. A pill ID that does not have the shape of one is dropped (`__proto__` and `constructor` included); an unknown pill ID
/// is kept, because agents come and go. A bad coat becomes the pill's default when it has one, and is dropped otherwise (the island gives that agent a coat again).
/// The result has its pills in code-point order, at most MAX_AGENT_CATS of them.
pub fn clean_agent_cats(raw: &Value) -> Value {
    let mut out = Map::new();
    let Some(o) = raw.as_object() else { return Value::Object(out) };
    let mut ids: Vec<&String> = o.keys().filter(|k| is_pill_id(k)).collect();
    ids.sort();
    for id in ids {
        if out.len() >= MAX_AGENT_CATS {
            break;
        }
        if let Some(c) = cat_id(&o[id]) {
            out.insert(id.clone(), json!(c));
        } else if let Some(d) = default_agent_cat(id) {
            out.insert(id.clone(), json!(d));
        }
    }
    Value::Object(out)
}

/// Everything Display saves, cleaned: { displayMode, pair, agentCats }. Never panics.
pub fn clean_display_settings(raw: &Value) -> Value {
    let none = Map::new();
    let r = raw.as_object().unwrap_or(&none);
    json!({
        "displayMode": word(r.get("displayMode"), &DISPLAY_MODES, "one"),
        "pair": clean_pair(r.get("pair").unwrap_or(&NULL)),
        "agentCats": clean_agent_cats(r.get("agentCats").unwrap_or(&NULL)),
    })
}

/// The whole `cat` block: the Cat settings and the Display settings, each cleaned by its own clean-up. This is what `settings::sanitized` runs the block through.
pub fn clean_cat_block(raw: &Value) -> Value {
    let mut block = clean_cat_settings(raw);
    if let (Some(o), Value::Object(display)) = (block.as_object_mut(), clean_display_settings(raw)) {
        for (k, v) in display {
            o.insert(k, v);
        }
    }
    block
}

/// What a fresh install holds in the `cat` block: the Cat defaults and One cat, Shrimpy and Momo, no stored agent coats.
pub fn block_default() -> Value {
    clean_cat_block(&Value::Null)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
'''),
])

# default_value is now only what the tests compare with (settings.rs starts from block_default): the Cat part of a fresh install, pinned by settings-cases.json.
edit('windows/src-tauri/src/cat_settings.rs', [
('''/// What a fresh install holds: Shrimpy, Playful, collar off, no fur lines, every cat following the globals with a Balanced personality.
pub fn default_value() -> Value {''', '''/// What a fresh install holds in the Cat settings: Shrimpy, Playful, collar off, no fur lines, every cat following the globals with a Balanced personality.
/// (`block_default` is the whole block, with the Display defaults; this is the part `settings-cases.json` pins.)
#[cfg(test)]
pub fn default_value() -> Value {'''),
])

# ── settings.rs: the block is cleaned with both clean-ups, and a fresh install holds the display defaults ───────────────────────────────────
edit('windows/src-tauri/src/settings.rs', [
('''    /// The Cat section of Settings (spec §4): `{character, motionStyle, collar, furLines, cats}`. Held as a JSON value, never as a typed
    /// struct, so that one bad field cannot fail the whole file; `sanitized` runs it through `cat_settings::clean_cat_settings`.
    #[serde(default = "crate::cat_settings::default_value")]''',
 '''    /// The Cat section of Settings (spec §4) and its Display settings (sub-project B): `{character, motionStyle, collar, furLines, cats, displayMode, pair,
    /// agentCats}`. Held as a JSON value, never as a typed struct, so that one bad field cannot fail the whole file; `sanitized` runs it through
    /// `cat_settings::clean_cat_block`, which cleans both parts (cleaning the Cat settings alone would drop the three display keys at the next save).
    #[serde(default = "crate::cat_settings::block_default")]'''),
('''            cat: crate::cat_settings::default_value(),
        }''', '''            cat: crate::cat_settings::block_default(),
        }'''),
('''    settings.cat = crate::cat_settings::clean_cat_settings(&settings.cat);''', '''    settings.cat = crate::cat_settings::clean_cat_block(&settings.cat);'''),
])
PY
```

- [ ] **Step 4: Run the tests**

Run: `bash windows/scripts/cargo-linux.sh test -p notchmeow --target-dir /repo/windows/target/b-tauri -- cat_settings:: settings:: 2>&1 | grep -E "^test result|^error|^warning"`
Expected: `test result: ok. 24 passed` (the 17 before and the 7 new: five `cat_settings` tests and two `settings` tests) and no `warning`: the test-only functions carry `#[cfg(test)]`.

- [ ] **Step 5: Run the whole workspace**

Run: `bash windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/b-tauri 2>&1 | grep -E "^test result|^error|^warning"`
Expected: `test result: ok. 246 passed` (the app's library, 7 more than the 239 before), `test result: ok. 0 passed` for the app's binary, `test result: ok. 24 passed` for the relay (one more than the 23 before: `a_subagents_agent_id_and_agent_type_reach_the_island`) and `test result: ok. 0 passed` for the doc tests; no `warning`, no `error`.

- [ ] **Step 6: Commit**

```bash
git add windows/src-tauri/src/cat_settings.rs windows/src-tauri/src/settings.rs windows/hook/src/main.rs
git commit -m "feat(settings): the Display settings in Rust, kept at every save

clean_display_settings cleans displayMode, pair and agentCats like cleanDisplaySettings, and clean_cat_block cleans them with the
Cat settings: settings::sanitized used to rebuild the cat block from the Cat settings alone, which dropped the three keys at the
next save. A fresh install holds block_default. Replays display-cases.json; tests for a hostile block, a save and a load, and a
relay test that a subagent's agent_id and agent_type reach the island.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: An engine's coat comes from the caller; the collar is looked up per coat

**Agent:** `nm-implementer`.

**Files:**
- Modify: `windows/src/cat/engine.ts`, `windows/src/cat/settings.ts`, `windows/scripts/cat-tests/collar-wiring.test.mjs`
- Test: `windows/scripts/cat-tests/coat.test.mjs`

**Interfaces:**
- Consumes: `engine.ts`'s `BotEngine` (`follow`, `p`, `cfg`, `draw`), `CatCfg`; `settings.ts`'s `applyCatSettings`, `collarFor`, `LiveCfg`; `presets.ts`'s `catById`, `kittenOf`, `CAT_IDS`.
- Produces: `BotEngine.setCoat(id: string | null)`, the getter `BotEngine.collarStyle`, `CatCfg.collars` and `LiveCfg.collars` (the collar style of every coat, filled for all 16 by `applyCatSettings`). Tasks 7 and 9 to 13 use them.

Today an engine built with no preset follows `cfg.character` at every `update`, and `draw` reads one string, `cfg.collar`, computed for the Main cat alone (spec §5, the Windows note). Per-agent cats need neither: an engine given a coat keeps it, and wears the collar its own coat wears.

- [ ] **Step 1: Write the failing test**

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/coat.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { BotEngine } from "../../src/cat/engine.ts";
import { CAT_IDS, PRESETS, kittenOf } from "../../src/cat/presets.ts";
import { applyCatSettings } from "../../src/cat/settings.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

installBrowserStubs();

// A cat's coat comes from the caller (the cast), never from the Main cat behind its back; and its collar style is looked up for its own coat.
const cfgOf = (extra = {}) => ({ motion: "playful", override: {}, pers: {}, zoomAfter: 300000, ...extra });
const make = (preset, cfg, extra = {}) => new BotEngine(preset, { cfg, quiet: true, now: () => 0, rand: () => 0.5, ...extra });
const strokes = (e, head = 40) => { const ctx = fakeCanvas(); e.draw(ctx, head / 0.6, head / 0.6); return ctx.calls.stroke || 0; };

test("setCoat fixes the engine on a cat, and update never overwrites it with the Main cat; setCoat(null) follows the Main cat again", () => {
  const cfg = cfgOf({ character: "momo" }), e = make(undefined, cfg);
  assert.deepEqual([e.follow, e.p.name], [true, "momo"]);
  e.setCoat("oreo");
  assert.deepEqual([e.follow, e.p.name], [false, "oreo"]);
  cfg.character = "ginger";
  e.update(1 / 60);
  assert.equal(e.p.name, "oreo", "the per-agent coat stays through every frame");
  e.setCoat(null);
  e.update(1 / 60);
  assert.deepEqual([e.follow, e.p.name], [true, "ginger"]);
  for (const bad of ["tiger", "", "__proto__", "Momo", undefined, 7]) { e.setCoat(bad); assert.equal(e.p.name, "shrimpy", String(bad)); assert.equal(e.follow, false); }
});

test("an engine's motion style and personality follow its coat, so Codex's Momo moves with Momo's settings", () => {
  const cfg = cfgOf({ character: "shrimpy", override: { momo: "classic" }, pers: { momo: { preset: "hyper" } } }), e = make(undefined, cfg);
  assert.equal(e.motion, "playful");
  e.setCoat("momo");
  assert.deepEqual([e.motion, e.pers.preset], ["classic", "hyper"]);
  const kit = make(kittenOf(PRESETS.momo), cfg);
  assert.deepEqual([kit.motion, kit.pers.preset], ["classic", "hyper"], "a kitten moves like its parent's coat");
});

test("the collar style is looked up per coat: two cats in one config wear their own styles, a kitten its parent's, and a coat with no entry the Main cat's", () => {
  const cfg = cfgOf();
  applyCatSettings(cfg, { character: "momo", collar: "band", cats: { ginger: { collar: "kerchief" }, momo: { collar: "off" }, oreo: { collar: "off" } } });
  assert.deepEqual([cfg.collar, cfg.collars.momo, cfg.collars.ginger, cfg.collars.oreo, cfg.collars.latte], ["off", "off", "kerchief", "off", "band"]);
  assert.deepEqual(Object.keys(cfg.collars), [...CAT_IDS], "every one of the 16 coats has its style");
  const mk = (preset) => { const e = make(preset, cfg, { mini: true }); e.collarColor = "#8AB4F8"; return e; };
  const bare = (preset, head) => strokes(make(preset, cfg, { mini: true }), head);
  assert.equal(strokes(mk(PRESETS.momo)), bare(PRESETS.momo), "Momo's own Off beats the global Band");
  assert.ok(strokes(mk(PRESETS.ginger)) > bare(PRESETS.ginger), "Ginger wears a neckerchief in the same config");
  assert.ok(strokes(mk(PRESETS.latte)) > bare(PRESETS.latte), "a coat with no override of its own wears the global Band");
  assert.ok(strokes(mk(kittenOf(PRESETS.ginger)), 16) > bare(kittenOf(PRESETS.ginger), 16), "a kitten of Ginger wears Ginger's collar");
  assert.equal(strokes(mk(kittenOf(PRESETS.momo)), 16), bare(kittenOf(PRESETS.momo), 16), "a kitten of Momo wears none: its parent's Off");
  const e = mk(PRESETS.latte);
  assert.equal(e.collarStyle, "band");
  e.setCoat("ginger");
  assert.equal(e.collarStyle, "kerchief", "an engine that changes coat changes collar style with it");
});

test("a config with no per-coat table still draws the Main cat's collar for every coat: the engines of the older tests and the Settings window's previews", () => {
  const cfg = cfgOf({ collar: "band" });
  for (const id of ["momo", "ginger", "snow"]) assert.equal(make(PRESETS[id], cfg).collarStyle, "band", id);
  assert.equal(make(PRESETS.momo, cfgOf()).collarStyle, "off");
  assert.equal(make(PRESETS.momo, cfgOf({ collars: {}, collar: "tag" })).collarStyle, "tag", "an empty table falls back to the Main cat's style");
  assert.equal(make(PRESETS.momo, cfgOf({ collars: { momo: "scarf" } })).collarStyle, "scarf", "an unknown style is passed on; the renderer draws nothing for it");
});
EOF
```

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/coat.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..`
Expected: `# tests 4`, `# pass 0`, `# fail 4` (there is no `setCoat` and no `collarStyle` yet).

- [ ] **Step 2: The engine and the shared config**

```bash
python3 - <<'PY'
# Task 6: an engine takes its coat from the caller (setCoat), and its collar style is looked up per coat. Run from the repository root.
# Every replacement asserts that its anchor is there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('windows/src/cat/engine.ts', [
# the shared config gains the collar style of every coat
('''  /** The collar style that cat wears (cat/settings.ts, `collarFor`): `tag`, `band`, `kerchief` or `off`. Drawn from stage 6 on. */
  collar?: string;''', '''  /** The collar style the Main cat wears (cat/settings.ts, `collarFor`): `tag`, `band`, `kerchief` or `off`. What an engine whose coat has no entry in `collars` wears. */
  collar?: string;
  /** The collar style each coat wears (`collarFor` of every cat ID): in A cat for each agent mode a pill's cat is not the Main cat, and a kitten wears its parent's coat's. */
  collars?: Record<string, string>;'''),
# follow is no longer fixed at construction
('''  /** True for an engine built without a preset: it wears `cfg.character`, whichever cat that is now, and `update` keeps it so. */
  readonly follow: boolean;''', '''  /**
   * True for an engine built without a preset, or given `setCoat(null)`: it wears `cfg.character`, whichever cat that is now, and `update` keeps it so. An engine built with
   * a preset, or given a coat with `setCoat`, keeps that cat: `update` never overwrites a per-agent coat with the Main cat.
   */
  follow: boolean;'''),
('''  /** The motion style in force for this cat: its own override, else the global style; an unknown stored value means Playful. */
  get motion(): string {''', '''  /**
   * Which cat this engine wears, from the cast (cat/cast.ts). A cat ID fixes it there (an unknown one is Shrimpy) and the engine stops following the Main cat; `null` makes it
   * follow `cfg.character` again. The island, the pills, the grid, the greeting and the drop view call it with the coat the cast names, so a per-agent coat is never overwritten.
   */
  setCoat(id: string | null) {
    this.follow = id === null;
    this.p = catById(id === null ? this.cfg.character : id);
  }

  /** The collar style this cat wears: the one `cfg.collars` holds for its coat (a kitten's is its parent's), else the Main cat's `cfg.collar`, else `off`. */
  get collarStyle(): string {
    const id = this.p.base || this.p.name;
    return (this.cfg.collars && own(this.cfg.collars, id) ? this.cfg.collars[id] : this.cfg.collar) ?? "off";
  }

  /** The motion style in force for this cat: its own override, else the global style; an unknown stored value means Playful. */
  get motion(): string {'''),
('''      collar: this.collarColor ? { style: this.cfg.collar ?? "off", col: this.collarColor } : null });''',
 '''      collar: this.collarColor ? { style: this.collarStyle, col: this.collarColor } : null });'''),
])

edit('windows/src/cat/settings.ts', [
('''  /** The collar that cat wears: its own style, else the global one. */
  collar?: string;''', '''  /** The collar the Main cat wears: its own style, else the global one. */
  collar?: string;
  /** The collar every coat wears: its own style, else the global one (`collarFor` of each of the 16 cats). */
  collars?: Record<string, string>;'''),
('''  cfg.collar = collarFor(s, s.character);''', '''  cfg.collar = collarFor(s, s.character);
  cfg.collars = Object.fromEntries(CAT_IDS.map((id) => [id, collarFor(s, id)]));'''),
])

# The two tests that pinned the old lines of source move with them.
edit('windows/scripts/cat-tests/collar-wiring.test.mjs', [
('''  assert.match(engine, /collar: this\\.collarColor \\? \\{ style: this\\.cfg\\.collar \\?\\? "off", col: this\\.collarColor \\} : null/);''',
 '''  assert.match(engine, /collar: this\\.collarColor \\? \\{ style: this\\.collarStyle, col: this\\.collarColor \\} : null/);'''),
])
PY
```

- [ ] **Step 3: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/coat.test.mjs scripts/cat-tests/collar-wiring.test.mjs scripts/cat-tests/follow.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 13`, `# pass 13`, `# fail 0`, `tsc exit 0`, then `ℹ tests 216`, `ℹ pass 216`, `ℹ fail 0` (the 212 before and the 4 of this task).

- [ ] **Step 4: Prove the "stay on the coat" rule bites (not committed)**

```bash
python3 - <<'PY'
import subprocess
p = 'windows/src/cat/engine.ts'
s = open(p, encoding='utf-8').read()
was = '    this.follow = id === null;\n    this.p = catById(id === null ? this.cfg.character : id);'
assert s.count(was) == 1
run = lambda: print(subprocess.run('cd windows && node --experimental-strip-types --test scripts/cat-tests/coat.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"', shell=True, capture_output=True, text=True).stdout, end='')
open(p, 'w', encoding='utf-8').write(s.replace(was, '    this.follow = true;\n    this.p = catById(id === null ? this.cfg.character : id);'))
run()
open(p, 'w', encoding='utf-8').write(s)
run()
PY
```

Expected: the first run prints `not ok 1 - setCoat fixes the engine on a cat, and update never overwrites it with the Main cat; setCoat(null) follows the Main cat again`, `# pass 3` and `# fail 1`; after the line is put back, `# pass 4` and `# fail 0`.

- [ ] **Step 5: Commit**

```bash
git add windows/scripts/cat-tests/coat.test.mjs windows/src/cat/engine.ts windows/src/cat/settings.ts windows/scripts/cat-tests/collar-wiring.test.mjs
git commit -m "feat(cat): an engine's coat comes from the caller, and its collar style from its coat

BotEngine.setCoat fixes an engine on a cat, so the per-frame follow of the Main cat no longer overwrites a per-agent coat;
setCoat(null) follows the Main cat again. The collar style is looked up for the engine's coat in catCfg.collars, which
applyCatSettings fills for all 16 cats (a kitten wears its parent coat's): in A cat for each agent mode a pill's cat is not the
Main cat, and one cfg.collar string was the Main cat's alone.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The Settings screen: Display, preview, pair, Cats for your agents, Main cat

**Agent:** `nm-implementer`. Loads `playwright-cli`.

**Files:**
- Create: `windows/src/settings/display.ts`
- Modify: `windows/src/core/state.ts`, `windows/src/island/island.ts`, `windows/src/settings/main.ts`, `windows/src/settings/cat.ts`, `windows/src/settings/settings.css`, `windows/scripts/cat-tests/follow.test.mjs`
- Test: `windows/scripts/cat-tests/settings-ui.test.mjs`

**Interfaces:**
- Consumes: Tasks 3 and 4: `CatBlock`, `cleanCatBlock`, `defaultCatBlock`, `withCatSettings`, `withDisplayMode`, `withPair`, `withAgentCat`, `withAgentCats`, `isAgentPill`, `defaultAgentCat`, `assignAgentCats`, `rerollAgentCat`, `castOf`, `agentLabel`, `pillColor`, `pairPlacement`; the engine and its `setCoat` (Task 6), `bigCatCollar`, `MINI_CELL`, `MINI_GRID`, `COMPACT_W`, `NOTCH_H`, `botPosition`; the Cat section's `menu`, `row`, `sized`, its `VisibleLoop`.
- Produces: `displayRows(host, ui)` returning `{before, after, sync, draw}` (the Display row and the preview; the pair rows and the agents' list); `CatHost.cat(): CatBlock` and `put(next: CatBlock, final)`; `Settings.cat: CatBlock` (state.ts), cleaned on the island's side by `cleanCatBlock` in `applySettings` and in the Settings window by `cleanCatBlock` in `main.ts`; the `.cat-notch`, `.cat-agents-box`, `.cat-agents`, `.cat-agent`, `.cat-agent-cv` and `.dice` CSS classes.

- [ ] **Step 1: Write the failing test**

The Settings window's glue needs a browser, so it is checked by source pins: every row the Cat section had is still there in its order, the Display rows go before and after the Main cat's grid, "Character" is "Main cat", every edit goes through `withCatSettings`, the previews run in the section's one loop and `display.ts` starts none, and the new CSS rules are new class names only.

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/settings-ui.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The Settings window's glue is checked by source pins (it needs a browser): the Cat section keeps every row it had, in its order, and the Display rows are added around them.
const read = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const cat = read("settings/cat.ts"), display = read("settings/display.ts"), css = read("settings/settings.css");

test("the Cat section keeps all its rows in their order, and the Display rows go before and after the Main cat's grid", () => {
  const at = (s) => { const i = cat.indexOf(s); assert.ok(i > 0, s); return i; };
  const rows = ['row("Motion style"', 'row("This cat\'s motion"', 'row("Personality"', "...sliders.map((sl) => sl.el)", 'row("Collar"', 'row("This cat\'s collar"', 'row("Apply to every cat"', 'row("Fur lines"'];
  const places = rows.map(at);
  assert.deepEqual([...places].sort((a, b) => a - b), places, "the existing rows are in the order they had");
  assert.ok(at("...display.before") < at('h("div", { class: "cat-top" }') && at('h("div", { class: "cat-top" }') < at("...display.after") && at("...display.after") < places[0]);
  assert.ok(at("Pick the cat that lives in your notch.") < at("...display.before"), "the section's own hint stays first");
});

test("Character is Main cat: the grid is named so, with a line that says what it is, and the word Character is gone from the section", () => {
  assert.match(cat, /"aria-label": "Main cat"/);
  assert.match(cat, /Main cat: the cat of One cat mode, of the integration pills/);
  assert.doesNotMatch(cat, /"Character"/);
});

test("every edit of the section goes through withCatSettings, so a Cat settings row never drops the display keys", () => {
  assert.match(cat, /host\.put\(withCatSettings\(host\.cat\(\), next\), final\);/);
  assert.match(cat, /cat\(\): CatBlock;/);
  assert.match(cat, /put\(next: CatBlock, final: boolean\): void;/);
  assert.match(read("settings/main.ts"), /settings\.cat = cleanCatBlock\(settings\.cat\);/);
});

test("the Display rows: the picker, the pair's pickers, Cats for your agents with its dice and Reset to defaults, built from the window's own rows", () => {
  for (const s of ['ui.row("Display"', "`Pair, cat ${i + 1}`", "Cats for your agents", '"Reset to defaults"', '"\\u{1F3B2}"', "Roll a new random cat", "withDisplayMode", "withPair", "withAgentCat(", "rerollAgentCat", "assignAgentCats"]) assert.ok(display.includes(s), s);
  assert.match(display, /\["one", "One cat"\], \["perAgent", "A cat for each agent"\], \["two", "Two cats"\]/);
});

test("the previews draw only while Settings can be seen: display.draw is called by the section's one VisibleLoop, and display.ts runs no loop of its own", () => {
  assert.match(cat, /drawOne\(preview, previewCv, PREVIEW_W, PREVIEW_H, dt\);\s*display\.draw\(dt\);/);
  assert.doesNotMatch(display, /requestAnimationFrame|setInterval|setTimeout|VisibleLoop/);
});

test("the new CSS rules are new class names only: the Display block adds .cat-notch, .cat-agents-box, .cat-agents, .cat-agent and .dice, and no existing selector", () => {
  const start = css.indexOf("/* Display (sub-project B)"), end = css.indexOf("/* The two ends of a trait slider");
  assert.ok(start > 0 && end > start);
  const block = css.slice(start, end).replace(/\/\*[\s\S]*?\*\//g, "");
  const selectors = [...block.matchAll(/([^{}]+)\{/g)].map((m) => m[1].trim());
  assert.ok(selectors.length >= 8, `${selectors.length} selectors`);
  for (const sel of selectors) assert.match(sel, /^\.(cat-notch|cat-agents-box|cat-agents|cat-agent|cat-agent-cv|dice)\b/, sel);
});
EOF
```

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/settings-ui.test.mjs 2>&1 | grep -E "ENOENT|^# (tests|pass|fail)" | cut -c1-90; cd ..`
Expected: a line with `ENOENT` (`settings/display.ts` does not exist yet), `# tests 1`, `# pass 0` and `# fail 1`.

- [ ] **Step 2: Write the Display rows**

`displayRows` builds the Display row, the preview (the compact island at 1.5 times, with five sample agents, the real cats, the real `castOf`), the pair's two pickers and the agents' list. A sample agent without a stored coat gets a seeded one that is never stored. It runs no loop: the Cat section's `VisibleLoop` calls its `draw`.

```bash
mkdir -p windows/src/settings
cat > windows/src/settings/display.ts <<'EOF'
// Settings → Cat → Display (sub-project B, spec §1): how the cats are shown. One cat (the Main cat everywhere, the default), A cat for each agent, or Two cats (a
// pair, side by side). The rows are built from the Settings window's own styles (.row, select, .hint, button); the new rules in settings.css are new class names only.
//   - the Display picker, with a small live preview of the compact island in the chosen mode (sample agents, the real cats);
//   - the pair's two pickers (Two cats mode only);
//   - "Cats for your agents" (A cat for each agent mode only): each agent's colour, a live preview, a cat picker, a dice and "Reset to defaults".
// The previews are live engines. They draw only while the Settings window can be seen and has focus: the Cat section's one loop (cat/loop.ts) calls `draw`, and nothing here runs a loop.

import { BotEngine } from "../cat/engine";
import { assignAgentCats, rerollAgentCat } from "../cat/agentcat";
import { bigCatCollar } from "../cat/collar";
import { castOf } from "../cat/cast";
import type { Cast, CastTask } from "../cat/cast";
import { rng } from "../cat/base";
import { MINI_CELL, MINI_GRID } from "../cat/greeting";
import { CAT_IDS, PRESETS } from "../cat/presets";
import { cleanCatBlock, defaultAgentCat, isAgentPill, withAgentCat, withAgentCats, withDisplayMode, withPair } from "../cat/display";
import type { CatBlock, DisplayMode } from "../cat/display";
import { COMPACT_W, NOTCH_H, botPosition, pairPlacement } from "../core/layout";
import { agentLabel, pillColor } from "../core/pills";
import { h } from "../views/dom";

/** What the section needs from the Cat section: the `cat` block as it is now, and a place to put the new one. */
export interface DisplayHost {
  block(): CatBlock;
  put(next: CatBlock, final: boolean): void;
}

/** The Cat section's own helpers (cat.ts), so the rows here look the same and nothing is repeated. */
export interface UiKit {
  menu(options: readonly (readonly [string, string])[], onChange: (v: string) => void): HTMLSelectElement;
  row(label: string, ...controls: (Node | string)[]): HTMLElement;
  sized(cv: HTMLCanvasElement, w: number, ht: number): void;
}

const MODES: readonly (readonly [DisplayMode, string])[] = [["one", "One cat"], ["perAgent", "A cat for each agent"], ["two", "Two cats"]];
const MODE_HINT: Record<DisplayMode, string> = {
  one: "Your Main cat everywhere, as it has always been.",
  perAgent: "Every agent has its own cat. Claude Code is Shrimpy by default; any other agent gets a coat of its own the first time it appears, and keeps it.",
  two: "Your pair side by side: cat 1 shows the focused agent, cat 2 the busiest other agent. They sleep together.",
};

/** The compact island in the preview is drawn at this scale, so the cats can be judged: it is the real compact drawing magnified, never a bigger cat. */
const SCALE = 1.5;
const AGENT_PREVIEW = 40;
/** The agents of the preview, in the island's order; the first is focused. A coat that the user has not stored for one of them is a seeded sample and is never stored. */
const SAMPLE: readonly (CastTask & { color: string })[] = [
  { id: "integration_claude", state: "working", last: 5, color: pillColor("integration_claude") },
  { id: "agent_codex", state: "approval", last: 4, color: "#2DD4BF" },
  { id: "agent_gemini", state: "thinking", last: 3, color: pillColor("agent_gemini") },
  { id: "agent_antigravity", state: "idle", last: 2, color: pillColor("agent_antigravity") },
  { id: "integration_stripe", state: "idle", last: 1, color: "#0570DE" },
];

/** Claude Code first, then every other agent that has a stored coat. */
const agentIds = (b: CatBlock): string[] => ["integration_claude", ...Object.keys(b.agentCats).filter((id) => id !== "integration_claude" && isAgentPill(id))];

/** One cat of the preview: where it sits in the compact island (px), its collar colour, and whether it is a big cat (badge on the left, ears fitted under the top of the strip). */
interface PreviewCat { e: BotEngine; x: number; y: number; d: number; collar: string | null; big: boolean }

export function displayRows(host: DisplayHost, ui: UiKit) {
  const now = (): CatBlock => cleanCatBlock(host.block());
  const change = (next: CatBlock) => host.put(next, true);
  const catOptions = CAT_IDS.map((id) => [id, PRESETS[id].label] as const);

  // The Display row, with what the chosen mode does.
  const mode = ui.menu(MODES, (v) => change(withDisplayMode(now(), v)));
  const hint = h("span", { class: "hint" });
  const modeRow = ui.row("Display", mode, hint);

  // A small live preview of the compact island in the chosen mode: the big cat (or the pair) at the left, the grid of the other agents at the right.
  const notchCv = h("canvas", { "aria-label": "Preview of the compact island in this mode" });
  ui.sized(notchCv, COMPACT_W * SCALE, NOTCH_H * SCALE);
  const notch = h("div", { class: "cat-notch" }, notchCv);
  let cast: Cast = castOf("one", {});
  const engines = new Map<string, BotEngine>();
  let cats: PreviewCat[] = [];
  const engineFor = (key: string, coat: string, state: string): BotEngine => {
    let e = engines.get(key);
    if (!e) { e = new BotEngine(PRESETS[coat], { mini: true }); engines.set(key, e); }
    if (e.p.name !== coat) e.setCoat(coat);
    e.setState(state);
    return e;
  };

  // The pair's two pickers.
  const pair = [0, 1].map((i) => {
    const m = ui.menu(catOptions, (v) => change(withPair(now(), i as 0 | 1, v)));
    return { m, el: ui.row(`Pair, cat ${i + 1}`, m, h("span", { class: "hint", text: i === 0 ? "Shows the focused agent." : "Shows the busiest other agent." })) };
  });

  // Cats for your agents.
  const agentRows = h("div", { class: "cat-agents" });
  const reset = h("button", { text: "Reset to defaults", onclick: () => { const b = now(); change(withAgentCats(b, assignAgentCats(agentIds(b), {}, b.character, Math.random))); } });
  const agents = h("div", { class: "cat-agents-box" },
    h("div", { class: "hint", text: "Cats for your agents: Claude Code and every agent NotchMeow has seen. A dice rolls a new random cat." }), agentRows, reset);
  let agentsKey = "";
  let agentPreviews: { id: string; e: BotEngine; cv: HTMLCanvasElement }[] = [];
  const buildAgents = (b: CatBlock) => {
    agentRows.replaceChildren();
    agentPreviews = [];
    for (const id of agentIds(b)) {
      const coat = b.agentCats[id] ?? defaultAgentCat(id) ?? b.character, color = pillColor(id);
      const cv = h("canvas", { "aria-label": `${agentLabel(id)}'s cat` });
      ui.sized(cv, AGENT_PREVIEW, AGENT_PREVIEW);
      const e = new BotEngine(PRESETS[coat], { mini: true });
      e.collarColor = color;
      agentPreviews.push({ id, e, cv });
      const pick = ui.menu(catOptions, (v) => change(withAgentCat(now(), id, v)));
      pick.value = coat;
      pick.setAttribute("aria-label", `Cat for ${agentLabel(id)}`);
      const dice = h("button", { class: "dice", title: "Roll a new random cat", "aria-label": `A new random cat for ${agentLabel(id)}`, text: "\u{1F3B2}", onclick: () => {
        const b2 = now();
        change(withAgentCats(b2, rerollAgentCat(id, b2.agentCats, b2.character, Math.random).agentCats));
      } });
      agentRows.append(h("div", { class: "row cat-agent" }, h("span", { class: "cat-agent-cv" }, cv), h("i", { class: "dot", style: `background:${color}` }), h("label", { text: agentLabel(id) }), pick, dice));
    }
  };

  /** Everything that follows the stored block: the controls, the agents' list and the preview's cast. */
  function sync() {
    const b = now();
    mode.value = b.displayMode;
    hint.textContent = MODE_HINT[b.displayMode];
    pair.forEach((p, i) => { p.m.value = b.pair[i]; p.el.style.display = b.displayMode === "two" ? "" : "none"; });
    agents.style.display = b.displayMode === "perAgent" ? "" : "none";
    const key = agentIds(b).map((id) => `${id}:${b.agentCats[id] ?? ""}`).join("|");
    if (key !== agentsKey) { agentsKey = key; buildAgents(b); }
    // The preview: the sample agents in the chosen mode, with the user's Main cat, pair and agents' coats. A sample agent with no coat of its own gets a seeded one, never stored.
    const coats = assignAgentCats(SAMPLE.map((s) => s.id), b.agentCats, b.character, rng(7));
    cast = castOf(b.displayMode, { tasks: SAMPLE, focusId: SAMPLE[0].id, mainCat: b.character, pair: b.pair, agentCats: coats });
    const sample = (id: string | null) => SAMPLE.find((s) => s.id === id);
    const two = pairPlacement("compact", "overview", NOTCH_H), one = botPosition("compact", "overview", NOTCH_H);
    const next: PreviewCat[] = [];
    const bigState = sample(cast.big.pill)?.state ?? "idle";
    next.push({ e: engineFor("big", cast.big.cat, bigState), x: cast.second && two ? two.first.cx : one.cx, y: one.cy, d: one.diameter, collar: bigCatCollar(bigState, sample(cast.big.pill)?.color), big: true });
    if (cast.second && two) {
      const st = sample(cast.second.pill)?.state ?? "idle";
      next.push({ e: engineFor("second", cast.second.cat, st), x: two.second.cx, y: two.second.cy, d: two.second.diameter, collar: bigCatCollar(st, sample(cast.second.pill)?.color), big: true });
    }
    const gx = COMPACT_W - MINI_CELL.inset, gy = NOTCH_H / 2, s = MINI_CELL.step / 2;
    cast.pills.slice(0, 4).forEach((p, i) => {
      const t = sample(p.pill);
      if (t) next.push({ e: engineFor(`grid${i}`, p.cat, t.state), x: gx + (i % 2 ? s : -s), y: gy + (i < 2 ? -s : s), d: MINI_GRID.d, collar: t.color, big: false });
    });
    cats = next;
  }

  /** One frame of every preview, `dt` seconds after the last (the Cat section's loop calls it only while the window can be seen and has focus). */
  function draw(dt: number) {
    const dpr = Math.min(2, window.devicePixelRatio || 1), ctx = notchCv.getContext("2d");
    if (ctx) {
      ctx.setTransform(dpr * SCALE, 0, 0, dpr * SCALE, 0, 0);
      ctx.clearRect(0, 0, COMPACT_W, NOTCH_H);
      ctx.fillStyle = "#000"; ctx.beginPath(); ctx.roundRect(0, 0, COMPACT_W, NOTCH_H, [0, 0, 14, 14]); ctx.fill();
      for (const c of cats) {
        const w = c.d / 0.6;
        c.e.collarColor = c.collar; c.e.badgeLeft = c.big; c.e.earRoom = c.big ? c.y : null;
        c.e.update(dt);
        ctx.save(); ctx.translate(c.x - w / 2, c.y - w / 2); c.e.draw(ctx, w, w); ctx.restore();
      }
    }
    for (const a of agentPreviews) {
      const actx = a.cv.getContext("2d");
      if (!actx) continue;
      actx.setTransform(dpr, 0, 0, dpr, 0, 0); actx.clearRect(0, 0, AGENT_PREVIEW, AGENT_PREVIEW);
      a.e.update(dt); a.e.draw(actx, AGENT_PREVIEW, AGENT_PREVIEW);
    }
  }

  return { before: [modeRow, notch], after: [...pair.map((p) => p.el), agents], sync, draw };
}
EOF
```

- [ ] **Step 3: Carry the whole block through, and add the rows to the section**

`Settings.cat` is the whole block; the island and the Settings window clean it with both clean-ups; the Cat section's host holds the block and every row's edit is put through `withCatSettings`; the grid is "Main cat" with a line that says what it is; the Display rows go in. The two Task 7 pins of the older follow test move with the lines they pinned.

```bash
python3 - <<'PY'
# Task 7: the `cat` block of the settings is the Cat settings and the Display settings, on the island's side and in the Settings window. Run from the repository root.
# Every replacement asserts that its anchor is there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('windows/src/core/state.ts', [
('''import { defaultCatSettings, type CatSettings } from "../cat/settings.ts";
''', '''import { defaultCatBlock } from "../cat/display.ts";
import type { CatBlock } from "../cat/display.ts";
'''),
('''  /** The Cat section of Settings (cat/settings.ts), clean: the character, the motion style, the collar, the fur lines and each cat's own motion, collar and personality. */
  cat: CatSettings;''', '''  /**
   * The `cat` block of Settings, clean (cat/display.ts): the Cat settings (the Main cat, the motion style, the collar, the fur lines and each cat's own motion, collar and
   * personality) and the Display settings (the mode, the pair and the agents' coats).
   */
  cat: CatBlock;'''),
('''  cat: defaultCatSettings(),
};''', '''  cat: defaultCatBlock(),
};'''),
])

# The island cleans the block with both clean-ups, so the display keys it holds are the ones it saves back.
edit('windows/src/island/island.ts', [
('''import { applyCatSettings } from "../cat/settings";
''', '''import { cleanCatBlock } from "../cat/display";
import { applyCatSettings } from "../cat/settings";
'''),
('''    // The cat block comes from Rust already clean; cleaning it again costs nothing and keeps a bad value out of every engine.
    State.settings.cat = applyCatSettings(catCfg, State.settings.cat);''', '''    // The cat block comes from Rust already clean; cleaning it again costs nothing and keeps a bad value out of every engine. The Display settings stay in it: it is saved back whole.
    const block = cleanCatBlock(State.settings.cat);
    applyCatSettings(catCfg, block);
    State.settings.cat = block;'''),
])

# The Settings window cleans and keeps the whole block too.
edit('windows/src/settings/main.ts', [
('''import { cleanCatSettings } from "../cat/settings";''', '''import { cleanCatBlock } from "../cat/display";'''),
('''  settings.cat = cleanCatSettings(settings.cat);''', '''  settings.cat = cleanCatBlock(settings.cat);'''),
])

# The wiring pins of the Cat section's tests follow the lines they pinned.
edit('windows/scripts/cat-tests/follow.test.mjs', [
('''  assert.match(source("island/island.ts"), /applySettings\\(\\) \\{[^}]*State\\.settings\\.cat = applyCatSettings\\(catCfg, State\\.settings\\.cat\\);/s);''',
 '''  assert.match(source("island/island.ts"), /applySettings\\(\\) \\{[^}]*const block = cleanCatBlock\\(State\\.settings\\.cat\\);\\s*applyCatSettings\\(catCfg, block\\);\\s*State\\.settings\\.cat = block;/s);'''),
('''  assert.match(source("core/state.ts"), /cat: CatSettings;/);
  assert.match(source("core/state.ts"), /cat: defaultCatSettings\\(\\),/);''', '''  assert.match(source("core/state.ts"), /cat: CatBlock;/);
  assert.match(source("core/state.ts"), /cat: defaultCatBlock\\(\\),/);'''),
])
PY
```

```bash
python3 - <<'PY'
# Task 7: the Cat section gets the Display picker, its live preview, the pair's pickers and the agents' list, built in settings/display.ts; "Character" is "Main cat".
# Run from the repository root. Every replacement asserts that its anchor is there exactly once. No existing row changes.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('windows/src/settings/cat.ts', [
('''// engines that draw only while this window can be seen: it is created hidden at launch and kept, so a loop that ran all the time would cost CPU
// with Settings closed (cat/loop.ts).
''', '''// engines that draw only while this window can be seen: it is created hidden at launch and kept, so a loop that ran all the time would cost CPU
// with Settings closed (cat/loop.ts). The Display rows (One cat, A cat for each agent, Two cats) are in display.ts and share this loop.
'''),
('''import {
  COLLAR_STYLES, FOLLOW, MOTION_STYLES, applyCatSettings, applyToAllCats, cleanCatSettings, withCatCollar, withCatMotion, withCharacter, withCollar, withFurLines,
  withMotionStyle, withPersonality, type CatSettings,
} from "../cat/settings";
import { h } from "../views/dom";

/** What the section needs from the window: the Cat block as it is now, and a place to put the new one. */
export interface CatHost {
  cat(): CatSettings;
  /** `final` is false while a slider is still moving: update, but do not save yet. */
  put(next: CatSettings, final: boolean): void;
}''', '''import { withCatSettings, type CatBlock } from "../cat/display";
import {
  COLLAR_STYLES, FOLLOW, MOTION_STYLES, applyCatSettings, applyToAllCats, cleanCatSettings, withCatCollar, withCatMotion, withCharacter, withCollar, withFurLines,
  withMotionStyle, withPersonality, type CatSettings,
} from "../cat/settings";
import { h } from "../views/dom";
import { displayRows } from "./display";

/** What the section needs from the window: the `cat` block as it is now (the Cat settings and the Display settings), and a place to put the new one. */
export interface CatHost {
  cat(): CatBlock;
  /** `final` is false while a slider is still moving: update, but do not save yet. */
  put(next: CatBlock, final: boolean): void;
}'''),
('''  const now = (): CatSettings => cleanCatSettings(host.cat());
  const change = (next: CatSettings, final = true) => {
    host.put(next, final);
    paint();
  };

  // Character: sixteen small live previews, and one big one of the chosen cat.
  const cells = new Map<string, { btn: HTMLButtonElement; cv: HTMLCanvasElement; e: BotEngine }>();
  const grid = h("div", { class: "cat-grid", role: "group", "aria-label": "Character" });''', '''  const now = (): CatSettings => cleanCatSettings(host.cat());
  // A row edits the Cat settings (the whole block keeps its Display settings) or, from the Display rows, the whole block.
  const change = (next: CatSettings | CatBlock, final = true) => {
    host.put(withCatSettings(host.cat(), next), final);
    paint();
  };
  const display = displayRows({ block: () => host.cat(), put: (next, final) => change(next, final) }, { menu, row, sized });

  // Main cat: sixteen small live previews, and one big one of the chosen cat. It is the cat of One cat mode, of the integration pills and of the big cat when no agent is focused.
  const cells = new Map<string, { btn: HTMLButtonElement; cv: HTMLCanvasElement; e: BotEngine }>();
  const grid = h("div", { class: "cat-grid", role: "group", "aria-label": "Main cat" });'''),
('''    whose.textContent = catWhose.textContent = collarWhose.textContent = `for ${PRESETS[id].label}`;
  };''', '''    whose.textContent = catWhose.textContent = collarWhose.textContent = `for ${PRESETS[id].label}`;
    display.sync();
  };'''),
('''      for (const c of cells.values()) drawOne(c.e, c.cv, CELL, CELL, dt);
      drawOne(preview, previewCv, PREVIEW_W, PREVIEW_H, dt);''', '''      for (const c of cells.values()) drawOne(c.e, c.cv, CELL, CELL, dt);
      drawOne(preview, previewCv, PREVIEW_W, PREVIEW_H, dt);
      display.draw(dt);'''),
('''    h("div", { class: "hint", text: "Pick the cat that lives in your notch. Each cat keeps its own motion, personality and collar." }),
    h("div", { class: "cat-top" }, grid, h("div", { class: "cat-preview" }, previewCv)),''', '''    h("div", { class: "hint", text: "Pick the cat that lives in your notch. Each cat keeps its own motion, personality and collar." }),
    ...display.before,
    h("div", { class: "hint", text: "Main cat: the cat of One cat mode, of the integration pills (Stripe, Vercel…) and of the big cat when no agent is focused or running." }),
    h("div", { class: "cat-top" }, grid, h("div", { class: "cat-preview" }, previewCv)),
    ...display.after,'''),
])

edit('windows/src/settings/settings.css', [
('''/* The two ends of a trait slider: fixed widths, so the six sliders line up. */''', '''/* Display (sub-project B): the compact island's preview, the pair's pickers, the agents' list. */
.cat-notch {
  width: 432px;
  max-width: 100%;
  border-radius: 0 0 21px 21px;
  background: #000;
  overflow: hidden;
}

.cat-notch canvas {
  display: block;
}

.cat-agents-box {
  display: flex;
  flex-direction: column;
  gap: 8px;
  align-items: flex-start;
}

.cat-agents {
  display: flex;
  flex-direction: column;
  gap: 6px;
  align-self: stretch;
}

.cat-agent {
  gap: 10px;
  flex-wrap: nowrap;
}

.cat-agent > label {
  min-width: 96px;
}

.cat-agent-cv {
  width: 40px;
  height: 40px;
  flex: 0 0 40px;
  border-radius: 12px;
  background: #000;
}

.cat-agent-cv canvas {
  display: block;
}

.dice {
  padding: 4px 9px;
  font-size: 14px;
  line-height: 1;
}

/* The two ends of a trait slider: fixed widths, so the six sliders line up. */'''),
])
PY
```

- [ ] **Step 4: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/settings-ui.test.mjs scripts/cat-tests/follow.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 11`, `# pass 11`, `# fail 0`, `tsc exit 0`, then `ℹ tests 222`, `ℹ pass 222`, `ℹ fail 0`.

- [ ] **Step 5: Prove the whole-block rule bites (not committed)**

A Cat settings row returns the Cat settings alone. If `withCatSettings` stopped carrying the block's display keys, the next row edit would drop the mode, the pair and the agents' coats.

```bash
python3 - <<'PY'
import subprocess
p = 'windows/src/cat/display.ts'
s = open(p, encoding='utf-8').read()
was = 'cleanCatBlock({ ...b, ...next });'
assert s.count(was) == 1
run = lambda: print(subprocess.run('cd windows && node --experimental-strip-types --test scripts/cat-tests/display.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"', shell=True, capture_output=True, text=True).stdout, end='')
open(p, 'w', encoding='utf-8').write(s.replace(was, 'cleanCatBlock({ ...next });'))
run()
open(p, 'w', encoding='utf-8').write(s)
run()
PY
```

Expected: the first run prints `not ok 10 - a Cat settings row edit keeps the display keys when it is put into the block, and a Display edit keeps the Cat settings: what the Settings window saves`, `# pass 9` and `# fail 1`; after the line is put back, `# pass 10` and `# fail 0`.

- [ ] **Step 6: Look at it, in a browser, with no Tauri window**

The Settings page renders outside Tauri with the defaults (every Bridge call is a no-op there). Serve it with Vite alone, open it headless and screenshot the Cat section in each mode, at a device scale of 2 and the window's own 560 px width.

```bash
SHOTS="${TMPDIR:-/tmp}/b-tauri-shots"
(cd windows && npx --no-install vite --port 14581 > "$SHOTS/vite.log" 2>&1 &)
sleep 4
cd "$SHOTS"
playwright-cli -s=settings open "http://127.0.0.1:14581/settings.html" --config=pw2x.json | grep -E "Console"
playwright-cli -s=settings resize 560 1900 > /dev/null
playwright-cli -s=settings run-code "async page => { await page.bringToFront(); await page.waitForTimeout(900); const s = page.locator('section', { has: page.getByRole('heading', { name: 'Cat', exact: true }) }); await s.screenshot({ path: 'set-one.png' }); await s.locator('select').first().selectOption('perAgent'); await page.waitForTimeout(800); await s.screenshot({ path: 'set-per.png' }); await s.locator('select').first().selectOption('two'); await page.waitForTimeout(800); await s.screenshot({ path: 'set-two.png' }); }" > /dev/null
playwright-cli -s=settings close > /dev/null
kill $(lsof -ti tcp:14581) 2>/dev/null; sleep 1; lsof -ti tcp:14581 | wc -l
ls set-*.png
```

Expected: `- Console: 1 errors, 0 warnings` (the missing `favicon.ico`), `0`, and `set-one.png  set-per.png  set-two.png`. Open them. `set-one.png`: the heading "Cat" and its hint, then a row "Display" with a menu on "One cat" and a line of text, a black strip (the compact island) with Shrimpy at its left and four small Shrimpys in a 2 by 2 grid at its right, a line "Main cat: the cat of One cat mode, …", the sixteen cells with Shrimpy chosen and the big black preview, and below them every row that was there before (Motion style, This cat's motion, Personality and the six sliders, Collar, This cat's collar, Apply to every cat, Fur lines). `set-per.png`: the Display menu on "A cat for each agent", the strip with the big cat and four different coats in the grid, and, under the grid of cats, "Cats for your agents: …", a row for Claude Code (a live Shrimpy on black, a white dot, the name, a menu on Shrimpy, a dice button) and a "Reset to defaults" button. `set-two.png`: "Two cats", the strip with Shrimpy and Momo side by side at its left and three cats in the grid, and the rows "Pair, cat 1" (Shrimpy) and "Pair, cat 2" (Momo) under the grid of cats. Nothing overflows the window and the cats are not cut off. **Say what you saw to the controller.**

- [ ] **Step 7: Commit**

```bash
git add windows/scripts/cat-tests/settings-ui.test.mjs windows/src/settings/display.ts windows/src/core/state.ts windows/src/island/island.ts windows/src/settings/main.ts windows/scripts/cat-tests/follow.test.mjs windows/src/settings/cat.ts windows/src/settings/settings.css windows/src/cat/display.ts
git commit -m "feat(settings): Display in Settings, with a live preview, the pair's pickers and Cats for your agents

Settings, Cat gets a Display picker (One cat, A cat for each agent, Two cats) with a small live preview of the compact island in
the chosen mode, two pair pickers in Two cats mode, and in A cat for each agent mode a list of the agents with their colour, a live
cat, a picker, a dice and Reset to defaults. Character is Main cat. The Cat section holds the whole cat block, so a Cat settings row
never drops the display keys, and the island and the Settings window clean the block with both clean-ups. The previews draw only
while Settings is visible and focused, in the section's one loop. New CSS classes only; no existing row changes.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

# Checkpoint 1: the owner looks at the eyes and the Display settings

**Owner checkpoint** (the executing session; no agent). Stages 1 and 2 are done when the owner says so.

- [ ] Send the owner, in the chat, `eyes-2x.png` and `eyes-1x.png` (Task 2 Step 8), `set-one.png`, `set-per.png` and `set-two.png` (Task 7 Step 6), and the two frame times of Task 2 (the `?dev` readout before and after, and the bench's ink and coloured medians), with a few lines of text: the **small coloured eyes** are on every cat below Ø28 (the compact notch, pills, the grid, kittens, the greeting's session cats), the expression shapes (happy, closed, wink's right eye, spiral, heart, star) stay ink; the numbers are B-0's and a change is one edit in the core; **the three black coats (Midnight, Oreo, Mocha) and their kittens glow** instead: one flat fill of the lighter iris colour, no rim, a thinner pupil and the catchlight, the look of the prototype's sheet after B-0's checkpoint; the Settings section is built from the window's own rows, **"Character" is now "Main cat"** (the grid, with a line that says what it is), and the Display picker, the pair's pickers and the agents' list sit around it; the previews are live engines that draw only while the window can be seen and has focus; in A cat for each agent mode the list shows Claude Code and every agent that has a stored coat, **in a fixed order** (this window does not see the island's pills, so it cannot sort by the last event); nothing else in Settings moved.
- [ ] Say what the owner should check by hand in a real build (`cd windows && npm run tauri dev`, on Windows or Linux): Settings → Cat → Display: pick each mode and see the preview change; in Two cats mode pick two coats, and a pair of the same coat makes cat 2 the next one; change a cat in the agents' list and press the dice; quit and start the app again, and the mode, the pair and the coats are still there (they are in `settings.json`, in the `cat` block, as `displayMode`, `pair` and `agentCats`); change a Cat row (the Main cat, the collar) and the Display choices are **still there** (they used to be at risk: a save rebuilt the block from the Cat settings alone); put junk in the display keys by hand (`"displayMode": 7`, `"pair": "[\"momo\""`, `"agentCats": [1]`) and start the app: it loads with the defaults for them, the rest of the file intact and no `settings.json.bad-…` file; with Settings **closed**, Task Manager shows the app at 0 % CPU with the island hidden, and with Settings open but another window focused the previews stand still. The island does not use the Display settings yet: that is Tasks 8 to 13.
- [ ] Wait for the owner's OK. Do not start Task 8 before it.

---

# Stage 3: every agent has its own cat, and Two cats

### Task 8: State: last-event time per pill, the cast, the agents' coats

**Agent:** `nm-implementer`.

**Files:**
- Modify: `windows/src/core/state.ts`, `windows/src/island/hooks.ts`, `windows/src/main.ts`
- Test: `windows/scripts/cat-tests/state-cast.test.mjs`

**Interfaces:**
- Consumes: Tasks 3 and 4: `castOf`, `Cast`, `assignAgentCats`, `CatBlock`; `state.ts`'s `State`, `AgentTask`, `upsertExternalAgent`, `removeTask`, `loadIntegrationTasks`; `hooks.ts`'s `handleHook`; `Bridge.saveSettings`.
- Produces: `AgentTask.last`, `State.noteEvent(id, t?)`, the getter `State.cast`, the getter `State.pillRow` (`{task, cat}[]`), `State.giveCoats(ids?)`, `State.rand`, `State.persistSettings`. Tasks 9 to 13 use them.

Neither app keeps a per-pill last-event time today (`State.lastActivity` is global): the busiest other agent needs one. A new agent gets its coat when its pill is first made (`upsertExternalAgent`) and once at load for the pills that exist, before anything is drawn.

- [ ] **Step 1: Write the failing test**

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/state-cast.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { rng } from "../../src/cat/base.ts";
import { cleanCatBlock, defaultCatBlock } from "../../src/cat/display.ts";
import { State } from "../../src/core/state.ts";

// What State adds for the display modes: a last-event time for every pill, the cast of the chosen mode, and the agents' coats given the first time they are seen.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const fresh = (cat = {}, ids = []) => {
  State.settings = { ...State.settings, cat: cleanCatBlock(cat), activeIntegrations: ["integration_stripe"] };
  State.tasks = [];
  State.focusId = null;
  State.rand = rng(11);
  State.persistSettings = null;
  State.loadIntegrationTasks();
  for (const [id, name] of ids) State.upsertExternalAgent(id, name, "#8AB4F8");
  State.persistSettings = null;
};
const ids = (list) => list.map((t) => t.id);

test("every hook event is its pill's last event: noteEvent stamps that pill and ignores an ID that has none", () => {
  fresh({}, [["agent_gemini", "gemini"]]);
  assert.equal(State.tasks.find((t) => t.id === "agent_gemini").last, undefined, "no event yet");
  State.noteEvent("agent_gemini", 1234);
  State.noteEvent("integration_claude", 99);
  State.noteEvent("agent_unknown", 5);
  assert.deepEqual(State.tasks.map((t) => [t.id, t.last]).filter(([, l]) => l !== undefined), [["integration_claude", 99], ["agent_gemini", 1234]]);
  const before = performance.now();
  State.noteEvent("agent_gemini");
  assert.ok(State.tasks.find((t) => t.id === "agent_gemini").last >= before, "the default time is now");
  assert.match(source("island/hooks.ts"), /default:\s*break;\s*\}\s*State\.noteEvent\(agentId\);\s*State\.notify\(\);/, "hooks.ts stamps the pill after every event it handles");
});

test("the cast follows the settings, the pills and the focus: One cat is the Main cat everywhere, Two cats the pair with the busiest other agent", () => {
  fresh({ character: "ginger", displayMode: "one" }, [["agent_gemini", "gemini"], ["agent_antigravity", "antigravity"]]);
  State.updateTask("agent_antigravity", "approval");
  State.noteEvent("agent_gemini", 10);
  State.noteEvent("agent_antigravity", 5);
  let c = State.cast;
  assert.deepEqual([c.mode, c.big, c.second], ["one", { pill: "integration_claude", cat: "ginger" }, null]);
  assert.deepEqual(c.pills.map((p) => p.cat), ["ginger", "ginger", "ginger"], "the three other pills, all in the Main cat");
  State.settings.cat = { ...State.settings.cat, displayMode: "two", pair: ["latte", "cloud"] };
  c = State.cast;
  assert.deepEqual(c.big, { pill: "integration_claude", cat: "latte" });
  assert.deepEqual(c.second, { pill: "agent_antigravity", cat: "cloud" }, "a waiting approval beats a more recent event");
  assert.ok(!ids(State.pillRow.map((r) => r.task)).includes("agent_antigravity"), "the second agent leaves the row");
  State.setFocus("agent_gemini");
  assert.deepEqual(State.cast.big, { pill: "agent_gemini", cat: "latte" }, "focus moves the big cat");
});

test("pillRow is otherTasks.slice(0, 4) in One cat mode, whatever the pills, so the island's row and grid stay as they are", () => {
  fresh({ displayMode: "one" }, [["agent_a", "a"], ["agent_b", "b"], ["agent_c", "c"]]);
  assert.equal(State.tasks.length >= 5, true);
  for (const focus of ["integration_claude", "agent_b", "integration_stripe"]) {
    State.setFocus(focus);
    assert.deepEqual(ids(State.pillRow.map((r) => r.task)), ids(State.otherTasks.slice(0, 4)), focus);
  }
});

test("an agent gets its coat the first time it is seen, once: Claude Code and Codex have defaults, any other agent a stored random coat that is no one else's", () => {
  fresh({ character: "ginger", displayMode: "perAgent" });
  let saved = 0;
  State.persistSettings = () => { saved++; };
  State.upsertExternalAgent("agent_gemini", "gemini", "#8AB4F8");
  const gemini = State.settings.cat.agentCats.agent_gemini;
  assert.ok(gemini && !["shrimpy", "momo", "ginger"].includes(gemini), `Gemini CLI: ${gemini}`);
  assert.equal(saved, 1, "the new coat is saved");
  State.upsertExternalAgent("agent_gemini", "gemini", "#8AB4F8");
  State.removeTask("agent_gemini");
  State.upsertExternalAgent("agent_gemini", "gemini", "#8AB4F8");
  assert.equal(State.settings.cat.agentCats.agent_gemini, gemini, "it keeps its coat when it comes back");
  assert.equal(saved, 1, "and nothing more is saved");
  State.upsertExternalAgent("agent_antigravity", "antigravity", "#E879F9");
  const agy = State.settings.cat.agentCats.agent_antigravity;
  assert.ok(agy && agy !== gemini && !["shrimpy", "momo", "ginger"].includes(agy));
  assert.equal(saved, 2);
  assert.equal(State.settings.cat.agentCats.integration_claude, undefined, "Claude Code's default is not stored");
  assert.equal(State.cast.pills.find((p) => p.pill === "agent_gemini").cat, gemini, "and the cast reads it");
});

test("giveCoats at load covers the agent pills that exist, with nothing to save when they all have a coat; an integration pill never gets one", () => {
  fresh({ displayMode: "perAgent", agentCats: { agent_a: "oreo" } });
  State.tasks.push({ id: "agent_a", name: "a", color: "#fff", state: "idle", stepIndex: 0, steps: [], source: "agent", isIntegration: false }, { id: "agent_b", name: "b", color: "#fff", state: "idle", stepIndex: 0, steps: [], source: "agent", isIntegration: false });
  let saved = 0;
  State.persistSettings = () => { saved++; };
  State.giveCoats();
  assert.equal(State.settings.cat.agentCats.agent_a, "oreo");
  assert.ok(State.settings.cat.agentCats.agent_b);
  assert.equal(State.settings.cat.agentCats.integration_stripe, undefined);
  assert.equal(saved, 1);
  State.giveCoats();
  assert.equal(saved, 1, "a second call changes nothing and saves nothing");
  assert.deepEqual(State.settings.cat, cleanCatBlock(State.settings.cat), "the block stays clean");
  assert.deepEqual(defaultCatBlock().agentCats, {});
});

test("the wiring: main.ts gives the coats once at load and saves them, and upsertExternalAgent gives a new agent its coat", () => {
  const main = source("main.ts"), state = source("core/state.ts");
  assert.match(main, /State\.persistSettings = \(\) => void Bridge\.saveSettings\(State\.settings\);/);
  assert.match(main, /State\.loadIntegrationTasks\(\);[^]*?State\.persistSettings = [^;]*;\s*State\.giveCoats\(\);/);
  assert.match(state, /this\.giveCoats\(\[id\]\);/);
});
EOF
```

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/state-cast.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..`
Expected: `# tests 6`, `# pass 0`, `# fail 6` (none of the new members exists yet).

- [ ] **Step 2: State, the hook handlers and `main.ts`**

```bash
python3 - <<'PY'
# Task 8: State holds each pill's last-event time, the cast of the chosen display mode and the agents' coats; the hook handlers note every event.
# Run from the repository root. Every replacement asserts that its anchor is there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('windows/src/core/state.ts', [
('''import { defaultCatBlock } from "../cat/display.ts";
import type { CatBlock } from "../cat/display.ts";
''', '''import { assignAgentCats } from "../cat/agentcat.ts";
import { castOf } from "../cat/cast.ts";
import type { Cast } from "../cat/cast.ts";
import { defaultCatBlock } from "../cat/display.ts";
import type { CatBlock } from "../cat/display.ts";
'''),
('''  pillBadge?: PillBadge | null;
  sessionCwd?: string | null;
}''', '''  pillBadge?: PillBadge | null;
  sessionCwd?: string | null;
  /** The time of this pill's last hook event (ms, `performance.now()`): it decides the busiest other agent in Two cats mode. Missing until the pill's first event. */
  last?: number;
}'''),
('''  lastActivity = performance.now();

  settings: Settings = { ...DEFAULT_SETTINGS };
''', '''  lastActivity = performance.now();

  settings: Settings = { ...DEFAULT_SETTINGS };

  /** Where `giveCoats` takes its random numbers: `Math.random`, and a test's own. */
  rand: () => number = () => Math.random();

  /** Called when a coat was given to an agent and the settings changed: the island saves them (main.ts), so the agent keeps its cat. Null until it is set. */
  persistSettings: (() => void) | null = null;
'''),
('''  get otherTasks(): AgentTask[] {
    return this.tasks.filter((t) => t.id !== this.focusId);
  }''', '''  get otherTasks(): AgentTask[] {
    return this.tasks.filter((t) => t.id !== this.focusId);
  }

  /**
   * The cast of the chosen display mode (cat/cast.ts): which coat the big cat, the second cat, the pills and the grid, the drop view and the greeting wear. It is a pure
   * function of the settings, the pills and the focus, cheap enough to ask once a frame.
   */
  get cast(): Cast {
    const cat = this.settings.cat;
    return castOf(cat.displayMode, {
      tasks: this.tasks.map((t) => ({ id: t.id, state: t.state, last: t.last ?? 0 })),
      focusId: this.focusTask?.id ?? null, mainCat: cat.character, pair: cat.pair, agentCats: cat.agentCats,
    });
  }

  /** The pills of the row and of the 2×2 grid, with their coats: the cast's `pills`, at most four (in One cat mode, `otherTasks.slice(0, 4)`; in Two cats mode without the second cat's agent). */
  get pillRow(): { task: AgentTask; cat: string }[] {
    const row: { task: AgentTask; cat: string }[] = [];
    for (const p of this.cast.pills) {
      const task = this.tasks.find((t) => t.id === p.pill);
      if (task) row.push({ task, cat: p.cat });
    }
    return row;
  }

  /** A hook event reached this pill: it is the pill's last event now (ms, `performance.now()`). An ID that has no pill is ignored. */
  noteEvent(id: string, t: number = performance.now()) {
    const task = this.tasks.find((x) => x.id === id);
    if (task) task.last = t;
  }

  /** Gives the agent pills in `ids` (default: every pill) the cat they have not got yet (cat/agentcat.ts), and keeps it: a new random coat is stored in the settings and saved. */
  giveCoats(ids: readonly string[] = this.tasks.map((t) => t.id)) {
    const cat = this.settings.cat, next = assignAgentCats(ids, cat.agentCats, cat.character, this.rand);
    if (JSON.stringify(next) === JSON.stringify(cat.agentCats)) return;
    this.settings.cat = { ...cat, agentCats: next };
    this.persistSettings?.();
  }'''),
('''    if (!this.focusId) this.focusId = id;
    this.notify();
  }

  toggleIntegration(id: string) {''', '''    if (!this.focusId) this.focusId = id;
    this.giveCoats([id]);
    this.notify();
  }

  toggleIntegration(id: string) {'''),
])

# Every hook event that reaches a pill is its last event now.
edit('windows/src/island/hooks.ts', [
('''    default:
      break;
  }
  State.notify();
}''', '''    default:
      break;
  }
  State.noteEvent(agentId);
  State.notify();
}'''),
])
PY
```

```bash
python3 - <<'PY'
# Task 8: main.ts saves the coats the island gives, and gives them once at load. Run from the repository root. Every replacement asserts that its anchor is there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('windows/src/main.ts', [
('''  island.applySettings();
  State.loadIntegrationTasks();
  if (boot && !boot.cursorPoll) island.followPageCursor();''', '''  island.applySettings();
  State.loadIntegrationTasks();
  // A coat given to an agent is saved, so it keeps it; the pills that exist now get theirs once, before anything is drawn.
  State.persistSettings = () => void Bridge.saveSettings(State.settings);
  State.giveCoats();
  if (boot && !boot.cursorPoll) island.followPageCursor();'''),
])
PY
```

- [ ] **Step 3: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/state-cast.test.mjs scripts/cat-tests/sleep.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 15`, `# pass 15`, `# fail 0`, `tsc exit 0`, then `ℹ tests 228`, `ℹ pass 228`, `ℹ fail 0` (the 222 before and the 6 of this task).

- [ ] **Step 4: Prove "a coat is saved once" bites (not committed)**

If `giveCoats` saved on every call, the settings would be written at every agent event.

```bash
python3 - <<'PY'
import subprocess
p = 'windows/src/core/state.ts'
s = open(p, encoding='utf-8').read()
was = '    if (JSON.stringify(next) === JSON.stringify(cat.agentCats)) return;\n'
assert s.count(was) == 1
run = lambda: print(subprocess.run('cd windows && node --experimental-strip-types --test scripts/cat-tests/state-cast.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"', shell=True, capture_output=True, text=True).stdout, end='')
open(p, 'w', encoding='utf-8').write(s.replace(was, ''))
run()
open(p, 'w', encoding='utf-8').write(s)
run()
PY
```

Expected: the first run prints `not ok 4 - an agent gets its coat the first time it is seen, once: Claude Code and Codex have defaults, any other agent a stored random coat that is no one else's` and `not ok 5 - giveCoats at load covers the agent pills that exist, with nothing to save when they all have a coat; an integration pill never gets one`, then `# pass 4` and `# fail 2`; after the line is put back, `# pass 6` and `# fail 0`.

- [ ] **Step 5: Commit**

```bash
git add windows/scripts/cat-tests/state-cast.test.mjs windows/src/core/state.ts windows/src/island/hooks.ts windows/src/main.ts
git commit -m "feat(state): a last-event time per pill, the cast of the display mode, and the agents' coats

State.cast is castOf over the settings, the pills and the focus, and pillRow the row and the grid with their coats (in One cat mode
exactly otherTasks.slice(0, 4)). Every hook event stamps its pill's last event, which decides the busiest other agent. An agent gets
its coat from agentCatFor the first time it is seen (upsertExternalAgent) and, for the pills that exist, once at load; a new random
coat is stored in the settings and saved, and an agent that comes back keeps it.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Every cat wears the cast: the big cat, pills, grid, greeting session cats, drop view

**Agent:** `nm-implementer`.

**Files:**
- Modify: `windows/src/cat/minibots.ts`, `windows/src/views/views.ts`, `windows/src/island/island.ts`, `windows/src/upload/canvas.ts`, `windows/src/cat/greeting.ts`, `windows/scripts/cat-tests/greeting.test.mjs`, `windows/scripts/cat-tests/follow.test.mjs`
- Test: `windows/scripts/cat-tests/sites.test.mjs`

**Interfaces:**
- Consumes: Tasks 6 and 8: `BotEngine.setCoat`, `State.cast`, `State.pillRow`; `minibots.ts`'s `createMiniBot`, `syncMiniBotStates`, `tickMiniBots`, `pruneMiniBots`; `greeting.ts`'s `Greeting`, `miniSlots`; `Cast["greeting"]`.
- Produces: `createMiniBot(task, bodySize, cat)` (the coat is required), `miniBotCoats()`; `Greeting.start(cast?)` (without one everything wears the chosen cat, as before), `GreetingCast`, the greeting's `sessionViews`; the island's `drawBot` setting the big cat's coat from the cast and the drop view's `draw` setting its coat from `State.cast.drop`.

Every place that draws a cat has one coat to wear: the big cat (`State.cast.big.cat`), a pill and a grid cell (`State.cast.pills`), a greeting session cat (`State.cast.greeting.sessions`), the drop view and the drag ghost (`State.cast.drop`). Nothing reads the Main cat behind the cast's back: the missed call site would silently show an agent the Main cat (spec §5, Risks). One test per site, below.

- [ ] **Step 1: Write the failing test**

For the big cat (an engine fed the cast keeps the agent's cat through every frame), the pills, the compact grid (their mini cats, with a DOM stub, made in the cast's coats and following it when the mode, the Main cat or a coat changes), the greeting (the four session cats; with no cast, the chosen cat) and the drop view. The island's `drawBot` and the drop canvas need a browser, so those two are pinned by source and by the cast's own value.

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/sites.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { BotEngine, catCfg } from "../../src/cat/engine.ts";
import { GT, GT3, Greeting } from "../../src/cat/greeting.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { createMiniBot, miniBotCoats, pruneMiniBots, syncMiniBotStates, tickMiniBots } from "../../src/cat/minibots.ts";
import { cleanCatBlock } from "../../src/cat/display.ts";
import { State } from "../../src/core/state.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

installBrowserStubs();
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

// Every place that draws a cat takes its coat from the cast, never from the Main cat behind its back: one test per call site.
const makeEl = (tag) => ({ tag, style: {}, className: "", children: [], width: 0, height: 0, isConnected: true, append(...c) { this.children.push(...c); }, getContext: () => fakeCanvas() });
const stubDom = () => { globalThis.document = { createElement: makeEl }; globalThis.window = { devicePixelRatio: 1, setTimeout: () => 0, clearTimeout: () => {} }; };
const unstubDom = () => { delete globalThis.window; installBrowserStubs(); };
const agent = (id, state = "idle") => ({ id, name: id, color: "#8AB4F8", state, stepIndex: 0, steps: [], source: "agent", isIntegration: false });
const setup = (cat) => {
  State.settings = { ...State.settings, cat: cleanCatBlock(cat) };
  State.tasks = [{ ...agent("integration_claude", "working") }, agent("agent_codex", "approval"), agent("agent_gemini"), agent("agent_antigravity"), { ...agent("integration_stripe"), isIntegration: true }];
  State.focusId = "integration_claude";
  State.asleep = false;
};
const PER_AGENT = { character: "ginger", displayMode: "perAgent", agentCats: { agent_gemini: "oreo", agent_antigravity: "leo" } };

test("the big cat: an engine fed the cast wears the focused agent's cat through every frame, whatever the Main cat is", () => {
  setup(PER_AGENT);
  const cfg = { motion: "playful", override: {}, pers: {}, zoomAfter: 3e5, character: "ginger" }, e = new BotEngine(undefined, { cfg, quiet: true, now: () => 0, rand: () => 0.5 });
  e.setCoat(State.cast.big.cat);
  assert.equal(e.p.name, "shrimpy", "Claude Code is Shrimpy");
  e.update(1 / 60);
  assert.equal(e.p.name, "shrimpy", "the per-frame follow no longer overwrites it with the Main cat (Ginger)");
  State.setFocus("agent_gemini");
  e.setCoat(State.cast.big.cat);
  assert.equal(e.p.name, "oreo");
  State.setFocus("integration_stripe");
  e.setCoat(State.cast.big.cat);
  assert.equal(e.p.name, "ginger", "an integration in focus: the Main cat");
  assert.match(source("island/island.ts"), /const focus = State\.focusTask;\s*this\.engine\.setCoat\(State\.cast\.big\.cat\);/, "island.ts: drawBot sets the big cat's coat from the cast every frame");
});

test("the pills: a pill's mini cat is made in the cast's coat and keeps it through every frame; the pill row asks the cast", () => {
  setup(PER_AGENT);
  stubDom();
  try {
    pruneMiniBots();
    catCfg.character = "momo";
    for (const { task, cat } of State.pillRow) createMiniBot(task, 24, cat);
    assert.deepEqual(miniBotCoats(), { agent_codex: "momo", agent_gemini: "oreo", agent_antigravity: "leo", integration_stripe: "ginger" });
    tickMiniBots(1 / 60);
    assert.equal(miniBotCoats().agent_gemini, "oreo", "a frame does not turn it into the Main cat");
  } finally {
    delete catCfg.character;
    unstubDom();
  }
  const views = source("views/views.ts");
  assert.match(views, /const row = State\.pillRow;/);
  assert.match(views, /createMiniBot\(task, 24, cat\)/);
  assert.doesNotMatch(views, /State\.otherTasks/);
});

test("the compact grid: its cats are made in the cast's coats and follow the cast when the mode, the Main cat or an agent's coat changes", () => {
  setup(PER_AGENT);
  stubDom();
  try {
    pruneMiniBots();
    for (const { task, cat } of State.pillRow) createMiniBot(task, 13, cat);
    assert.equal(miniBotCoats().agent_antigravity, "leo");
    State.settings = { ...State.settings, cat: cleanCatBlock({ ...State.settings.cat, agentCats: { agent_gemini: "snow", agent_antigravity: "puff" } }) };
    syncMiniBotStates(State.tasks);
    assert.deepEqual([miniBotCoats().agent_gemini, miniBotCoats().agent_antigravity], ["snow", "puff"], "an agent's coat changed in Settings: the grid follows with no restart");
    State.settings = { ...State.settings, cat: cleanCatBlock({ ...State.settings.cat, displayMode: "one", character: "latte" }) };
    syncMiniBotStates(State.tasks);
    assert.deepEqual(Object.values(miniBotCoats()), ["latte", "latte", "latte", "latte"], "One cat: the Main cat everywhere");
    State.settings = { ...State.settings, cat: cleanCatBlock({ ...State.settings.cat, displayMode: "two", pair: ["momo", "cloud"] }) };
    syncMiniBotStates(State.tasks);
    assert.equal(miniBotCoats().agent_codex, "latte", "Two cats: the pills wear the Main cat (a pill that left the row keeps what it had)");
  } finally {
    unstubDom();
  }
  assert.match(source("island/island.ts"), /const row = State\.pillRow;[^]*createMiniBot\(task, 13, cat\)/);
});

test("the greeting's session cats: each cell wears its pill's coat, the glide ends where the grid begins, and with no cast everything wears the chosen cat", () => {
  globalThis.window = { setTimeout: () => 0, clearTimeout: () => {} };
  try {
    setup(PER_AGENT);
    const clock = { t: 0 }, g = new Greeting(() => clock.t);
    g.start(State.cast.greeting);
    assert.deepEqual(g.sessionViews.map((v) => v.p.name), ["momo", "oreo", "leo", "ginger"], "Codex, Gemini CLI, Antigravity and Stripe (the Main cat)");
    assert.equal(g.view.p.name, "ginger", "the cat that falls in is the Main cat");
    clock.t = (GT.leave + GT3.end - 0.05) * 1000;
    const ctx = fakeCanvas();
    g.draw(ctx);
    // A coat's eyes were drawn: its iris gradient's first stop, or, for a black coat (flat and bright), the lighter of its two iris colours as a flat fill.
    const lum = (h) => { const n = parseInt(h.slice(1), 16); return 0.2126 * ((n >> 16) & 255) + 0.7152 * ((n >> 8) & 255) + 0.0722 * (n & 255); };
    const eyesDrawn = (id) => { const [a, b] = PRESETS[id].iris; return ["midnight", "oreo", "mocha"].includes(id) ? ctx.seen.fillStyles.includes(lum(a) >= lum(b) ? a : b) : ctx.seen.stops.includes(a); };
    for (const id of ["momo", "oreo", "leo"]) assert.ok(eyesDrawn(id), `${id}'s eyes were drawn`);
    catCfg.character = "latte";
    const plain = new Greeting(() => 0);
    plain.start();
    assert.deepEqual(plain.sessionViews.map((v) => v.p.name), ["latte", "latte", "latte", "latte"]);
    assert.equal(plain.minis.p.name, "latte");
  } finally {
    delete catCfg.character;
    delete globalThis.window;
  }
  assert.match(source("island/island.ts"), /this\.greeting\.start\(State\.cast\.greeting\);/);
});

test("the drop view and the drag ghost: the cat wears the big cat's coat, set every frame", () => {
  assert.match(source("upload/canvas.ts"), /this\.cat\.setCoat\(State\.cast\.drop\);\s*this\.cat\.lookX = f\.lookX;/);
  setup(PER_AGENT);
  assert.equal(State.cast.drop, State.cast.big.cat);
  State.setFocus("agent_gemini");
  assert.equal(State.cast.drop, "oreo");
  State.settings = { ...State.settings, cat: cleanCatBlock({ ...State.settings.cat, displayMode: "two", pair: ["blue", "snow"] }) };
  assert.equal(State.cast.drop, "blue", "Two cats: the big cat's, cat 1's");
  State.settings = { ...State.settings, cat: cleanCatBlock({ ...State.settings.cat, displayMode: "one" }) };
  assert.equal(State.cast.drop, "ginger");
});
EOF
```

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/sites.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..`
Expected: `# tests 1`, `# pass 0`, `# fail 1` (`minibots.ts` is not loadable in Node yet: it imports `./engine` with no extension).

- [ ] **Step 2: Wire every site to the cast**

```bash
python3 - <<'PY'
# Task 9: every place that draws a cat takes its coat from the cast: the big cat, the pills, the compact grid, the greeting's session cats and the drop view.
# Run from the repository root. Every replacement asserts that its anchor is there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

# The pills and the compact grid: a mini cat is made in the coat the cast gives its pill, and follows the cast when it changes.
edit('windows/src/cat/minibots.ts', [
# check:cat loads this file now (the pills' and the grid's coats are tested), so its imports name their files
('''import { BotEngine } from "./engine";
import { State, type AgentTask } from "../core/state";''', '''import { BotEngine } from "./engine.ts";
import { State } from "../core/state.ts";
import type { AgentTask } from "../core/state.ts";'''),
('''/**
 * Creates a mini cat whose **body** is `bodySize` CSS pixels across.''', '''/**
 * Creates a mini cat whose **body** is `bodySize` CSS pixels across, in the coat `cat` (the cast's, for its pill: cat/cast.ts `pills`).'''),
('''export function createMiniBot(task: AgentTask, bodySize: number): HTMLElement {''', '''export function createMiniBot(task: AgentTask, bodySize: number, cat: string): HTMLElement {'''),
('''  engine.isMini = true;
  engine.collarColor = task.color;''', '''  engine.isMini = true;
  engine.setCoat(cat);
  engine.collarColor = task.color;'''),
('''export function syncMiniBotStates(tasks: AgentTask[]) {
  for (const mb of live.values()) {
    const task = tasks.find((t) => t.id === mb.taskId);
    if (!task) continue;
    mb.engine.setState(State.shownState(task.state));
    mb.engine.collarColor = task.color;
  }
}''', '''export function syncMiniBotStates(tasks: AgentTask[]) {
  const coats = new Map(State.cast.pills.map((p) => [p.pill, p.cat]));
  for (const mb of live.values()) {
    const task = tasks.find((t) => t.id === mb.taskId);
    if (!task) continue;
    mb.engine.setState(State.shownState(task.state));
    mb.engine.collarColor = task.color;
    // The display mode, the Main cat or an agent's coat changed: the pill's cat follows the cast.
    const coat = coats.get(task.id);
    if (coat) mb.engine.setCoat(coat);
  }
}'''),
('''export const miniBotCount = () => live.size;''', '''export const miniBotCount = () => live.size;

/** The coat of every live mini cat, by pill ID: what the checks look at. */
export const miniBotCoats = (): Record<string, string> => Object.fromEntries([...live.values()].map((mb) => [mb.taskId, mb.engine.p.name]));'''),
])
edit('windows/src/views/views.ts', [
('''      const others = State.otherTasks.slice(0, 4);
      const pillKey = others.map((t) => `${t.id}:${t.pillBadge ?? ""}`).join("|");
      if (pillKey !== pillIds) {
        pillIds = pillKey;
        clear(pills);
        for (const t of others) pills.append(buildPill(t, actions));''', '''      const row = State.pillRow;
      const pillKey = row.map(({ task: t }) => `${t.id}:${t.pillBadge ?? ""}`).join("|");
      if (pillKey !== pillIds) {
        pillIds = pillKey;
        clear(pills);
        for (const { task, cat } of row) pills.append(buildPill(task, cat, actions));'''),
('''function buildPill(task: AgentTask, actions: ViewActions): HTMLElement {
  const label = task.id === "integration_claude" ? "VS Code" : task.name;
  const canvas = createMiniBot(task, 24);''', '''function buildPill(task: AgentTask, cat: string, actions: ViewActions): HTMLElement {
  const label = task.id === "integration_claude" ? "VS Code" : task.name;
  const canvas = createMiniBot(task, 24, cat);'''),
])
edit('windows/src/island/island.ts', [
('''      const others = State.otherTasks.slice(0, 4);
      const key = others.map((t) => t.id).join("|");
      if (this.miniGrid.dataset.key !== key) {
        this.miniGrid.dataset.key = key;
        this.miniGrid.replaceChildren();
        for (const t of others) {
          this.miniGrid.append(createMiniBot(t, 13));
        }''', '''      const row = State.pillRow;
      const key = row.map(({ task }) => task.id).join("|");
      if (this.miniGrid.dataset.key !== key) {
        this.miniGrid.dataset.key = key;
        this.miniGrid.replaceChildren();
        for (const { task, cat } of row) {
          this.miniGrid.append(createMiniBot(task, 13, cat));
        }'''),
('''          this.greeting.start();''', '''          this.greeting.start(State.cast.greeting);'''),
# the big cat
('''    const focus = State.focusTask;
    this.engine.collarColor = bigCatCollar(State.effectiveState, focus?.color);''', '''    const focus = State.focusTask;
    this.engine.setCoat(State.cast.big.cat);
    this.engine.collarColor = bigCatCollar(State.effectiveState, focus?.color);'''),
])
# the drop view
edit('windows/src/upload/canvas.ts', [
('''    this.cat.lookX = f.lookX;
    this.cat.lookY = f.lookY;
    this.cat.update(dt);''', '''    this.cat.setCoat(State.cast.drop);
    this.cat.lookX = f.lookX;
    this.cat.lookY = f.lookY;
    this.cat.update(dt);'''),
('''  /** The drop view's cat: the one Settings chose. */''', '''  /** The drop view's cat: the big cat's, from the cast (set every frame in `draw`). */'''),
])
# the greeting
edit('windows/src/cat/greeting.ts', [
('''import type { CatView, PawSpec } from "./renderer.ts";''', '''import type { CatView, PawSpec } from "./renderer.ts";
import type { Cast } from "./cast.ts";'''),
('''/** The streak burst: 16 coloured streaks from seed 7, the same on every platform. */''', '''/** What the cast says the greeting wears (cat/cast.ts `greeting`): the cat that falls in, the pair that arrives together in Two cats mode, and the four session cats in the grid's cell order. */
export type GreetingCast = Cast["greeting"];

/** The streak burst: 16 coloured streaks from seed 7, the same on every platform. */'''),
('''  private minis: CatView;
''', '''  /** The Main cat's session view: a session cat with no pill of its own wears it. */
  private minis: CatView;
  /** The four session cats in the grid's cell order, each in the coat the cast gives its pill (the Main cat's when it has none), so the glide ends where the grid begins. */
  private sessionViews: CatView[];
  private readonly miniViews = new Map<string, CatView>();
'''),
('''    this.minis = miniView(catById(DEFAULT_CAT));
  }

  start() {''', '''    this.minis = miniView(catById(DEFAULT_CAT));
    this.sessionViews = [this.minis, this.minis, this.minis, this.minis];
  }

  /** The session cat of a coat, made once per greeting. */
  private sessionView(id: string): CatView {
    let v = this.miniViews.get(id);
    if (!v) { v = miniView(catById(id)); this.miniViews.set(id, v); }
    return v;
  }

  /** `cast` is what the cast says the greeting wears (State.cast.greeting); without one, everything wears the chosen cat. */
  start(cast?: GreetingCast) {'''),
('''    this.view = greetView(catCfg.character ?? DEFAULT_CAT, () => this.eye, this.now);
    this.minis = miniView(this.view.p);''', '''    const main = cast ? cast.cat : catCfg.character ?? DEFAULT_CAT;
    this.view = greetView(main, () => this.eye, this.now);
    this.miniViews.clear();
    this.minis = this.sessionView(this.view.p.name);
    this.sessionViews = [0, 1, 2, 3].map((i) => this.sessionView(cast?.sessions[i] ?? main));'''),
('''    for (const s of miniSlots(P.minis, miniGlide(t, leave), { W: COMPACT, H: NOTCH.H, d: MINI_GRID.d })) {
      if (s.d < MINI_MIN_D) continue;
      x.save(); x.translate(s.x, s.y);
      drawCat(x, this.minis, 0, 0, s.d, { badge: false });
      x.restore();
    }''', '''    miniSlots(P.minis, miniGlide(t, leave), { W: COMPACT, H: NOTCH.H, d: MINI_GRID.d }).forEach((s, i) => {
      if (s.d < MINI_MIN_D) return;
      x.save(); x.translate(s.x, s.y);
      drawCat(x, this.sessionViews[i] ?? this.minis, 0, 0, s.d, { badge: false });
      x.restore();
    });'''),
])

# The two older tests that pinned the lines these edits moved.
edit('windows/scripts/cat-tests/greeting.test.mjs', [
('''  const body = Number(island.match(/createMiniBot\\(t, (\\d+)\\)/)[1]);''', '''  const body = Number(island.match(/createMiniBot\\(task, (\\d+), cat\\)/)[1]);'''),
])
edit('windows/scripts/cat-tests/follow.test.mjs', [
('''  assert.match(source("cat/greeting.ts"), /this\\.view = greetView\\(catCfg\\.character \\?\\? DEFAULT_CAT,/);''',
 '''  assert.match(source("cat/greeting.ts"), /const main = cast \\? cast\\.cat : catCfg\\.character \\?\\? DEFAULT_CAT;\\s*this\\.view = greetView\\(main,/);'''),
])
PY
```

- [ ] **Step 3: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/sites.test.mjs scripts/cat-tests/greeting.test.mjs scripts/cat-tests/follow.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 23`, `# pass 23`, `# fail 0`, `tsc exit 0`, then `ℹ tests 233`, `ℹ pass 233`, `ℹ fail 0` (the 228 before and the 5 of this task).

- [ ] **Step 4: Prove the pills' site bites (not committed)**

Without the coat, a pill's mini cat would be the engine's default: the Main cat, whatever the cast says.

```bash
python3 - <<'PY'
import subprocess
p = 'windows/src/cat/minibots.ts'
s = open(p, encoding='utf-8').read()
was = '  engine.setCoat(cat);\n'
assert s.count(was) == 1
run = lambda: print(subprocess.run('cd windows && node --experimental-strip-types --test scripts/cat-tests/sites.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"', shell=True, capture_output=True, text=True).stdout, end='')
open(p, 'w', encoding='utf-8').write(s.replace(was, ''))
run()
open(p, 'w', encoding='utf-8').write(s)
run()
PY
```

Expected: the first run prints `not ok 2 - the pills: a pill's mini cat is made in the cast's coat and keeps it through every frame; the pill row asks the cast` and `not ok 3 - the compact grid: its cats are made in the cast's coats and follow the cast when the mode, the Main cat or an agent's coat changes`, then `# pass 3` and `# fail 2`; after the line is put back, `# pass 5` and `# fail 0`.

- [ ] **Step 5: Commit**

```bash
git add windows/scripts/cat-tests/sites.test.mjs windows/src/cat/minibots.ts windows/src/views/views.ts windows/src/island/island.ts windows/src/upload/canvas.ts windows/src/cat/greeting.ts windows/scripts/cat-tests/greeting.test.mjs windows/scripts/cat-tests/follow.test.mjs
git commit -m "feat(cat): every cat wears the cast's coat: the big cat, the pills, the grid, the greeting's session cats, the drop view

A mini cat is made in the coat the cast gives its pill and follows the cast when the mode, the Main cat or an agent's coat changes;
the island sets the big cat's coat every frame and the drop view's from the cast; the greeting's four session cats wear their
pills' coats, so the glide ends where the grid begins. In One cat mode all of it is the Main cat, as before. minibots.ts is
loaded by the Node checks now (explicit .ts imports) so the pills' and the grid's coats are tested; one test for each call site.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 10: The Two cats layout and the pair's arrival in the greeting

**Agent:** `nm-implementer`. Loads `playwright-cli`.

**Files:**
- Modify: `windows/src/island/island.ts`, `windows/src/island/hooks.ts`, `windows/src/main.ts`, `windows/src/views/views.ts`, `windows/src/cat/greeting.ts`, `windows/src/style.css`
- Test: `windows/scripts/cat-tests/two-cats.test.mjs`

**Interfaces:**
- Consumes: Tasks 4, 6, 8 and 9: `State.cast`, `Cast["second"]`, `pairPlacement`, `PAIR`, `BotEngine.setCoat`, `agentLabel`, `bigCatCollar`, `Greeting.start(cast)`, `GreetingCast`; the island's `Spring`, `botCx`, `drawBot`, `updateBotTargets`, `isBotHit`.
- Produces: the island's second cat (`botCanvas2`, `engine2`, `bot2Cx`, `bot2Cy`, `bot2Size`, `pairShown`, `drawBot2`, `isBot2Hit`); the overview's `.two` class and `.second` line; the greeting's `pairView`; `handleHook` and `HookPayload` exported, and in the dev server only `/?display=<mode>` and `window.__nm` (`island`, `State`, `hook(payload)`): a fake-event path for the checkpoint pictures. A release build contains none of the dev path (`import.meta.env.DEV`).

Two cats mode only (spec §2). Compact: two Ø20 cats share the left ear. Expanded, in the overview: cat 1 at Ø58 (x 56) and cat 2 at Ø46 (x 114) side by side in the left card with a 6 px gap between the heads (the owner made room at B-0's checkpoint), the ticker's text moved right (to 147 px, 10 px after cat 2's edge) with a second line for cat 2's agent ("Antigravity · thinking"), both badges visible. Every other expanded view keeps its one cat (the cards' text starts where the pair would be: plan decision, question 4). Clicking cat 2 focuses its agent. The second agent has left the pill row and the grid (Task 8's cast). In the greeting the pair arrives together (spec §2, the prototype's `greetPair`).

- [ ] **Step 1: Write the failing test**

The glue needs a browser, so it is pinned by source; the greeting's pair arrival is drawn with a fake canvas (Momo's iris colours appear only when cat 2 is drawn).

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/two-cats.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { catCfg } from "../../src/cat/engine.ts";
import { GT, GT3, Greeting } from "../../src/cat/greeting.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

installBrowserStubs();
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

// Two cats mode's layout: the glue is checked by source pins (it needs a browser), the greeting's pair arrival by drawing it.
const arrival = (cast, dt) => {
  globalThis.window = { setTimeout: () => 0, clearTimeout: () => {} };
  try {
    const clock = { t: 0 }, g = new Greeting(() => clock.t);
    g.start(cast);
    clock.t = (GT.leave + dt) * 1000;
    const ctx = fakeCanvas();
    g.draw(ctx);
    return ctx.seen.stops;
  } finally {
    delete globalThis.window;
  }
};
const MAIN = { cat: "ginger", sessions: ["ginger", "ginger", "ginger", "ginger"] };

test("the greeting's pair arrives together: the second cat pops in beside the settled one as the island folds, and not before, and not in the other modes", () => {
  const two = { ...MAIN, pair: ["shrimpy", "momo"] }, momo = PRESETS.momo.iris[0];
  assert.ok(!arrival(two, 0.1).includes(momo), "before the fold is under way: no second cat");
  assert.ok(!arrival(two, 0.2).includes(momo), "and not before the pop's own start");
  assert.ok(arrival(two, 0.5).includes(momo), "once it has popped in, cat 2 is drawn (Momo's eyes)");
  assert.ok(arrival(two, GT3.end - 0.05).includes(momo), "and it is there when the greeting hands over to the real pair");
  for (const none of [{ ...MAIN, pair: null }, MAIN, undefined]) assert.ok(!arrival(none, 0.5).includes(momo), "One cat and A cat for each agent greet with one cat");
  catCfg.character = "momo";
  assert.ok(arrival(undefined, 0.5).includes(momo), "(sanity: with Momo as the Main cat her eyes are drawn anyway)");
  delete catCfg.character;
});

test("the greeting's settled cat makes room for the pair, 10 px left, and only in Two cats mode; the numbers are the layout's", () => {
  const src = source("cat/greeting.ts");
  assert.match(src, /room = this\.pairView \? -\(40 - PAIR\.compact\.x1\) \* fold : 0/);
  assert.match(src, /drawCat\(x, this\.pairView, 320 - COMPACT \/ 2 \+ PAIR\.compact\.x2, 16, PAIR\.compact\.d \* pop, \{ badge: false \}\)/);
  assert.match(src, /this\.pairView = cast\?\.pair \? this\.sessionView\(cast\.pair\[1\]\) : null;/);
});

test("the island: the second cat has its own canvas, engine and springs, only in Two cats mode, compact or in the overview, and its coat is the cast's", () => {
  const island = source("island/island.ts");
  assert.match(island, /const pair = this\.cast\.second \? pairPlacement\(State\.mode, State\.view, this\.height\.value\) : null;\s*const p = pair \? pair\.first : botPosition\(State\.mode, State\.view, this\.height\.value, State\.uploadProgress\);/, "One cat and A cat for each agent keep botPosition");
  assert.match(island, /this\.pairShown = pair !== null && visible;/);
  assert.match(island, /this\.engine2\.setCoat\(second\.cat\);\s*this\.engine2\.setState\(state\);/);
  assert.match(island, /this\.botCanvas,\s*this\.botCanvas2,/);
  assert.match(island, /if \(this\.pairShown\) this\.drawBot2\(dt\);/);
  assert.match(island, /\(this\.pairShown && \(this\.engine2\.busy \|\| !this\.bot2Cx\.settled/, "nothing keeps the loop alive while the island is hidden: pairShown is false then");
});

test("a click on the second cat focuses its agent, as a pill does, only while it is shown and has an agent", () => {
  const island = source("island/island.ts");
  assert.match(island, /const second = this\.cast\.second;\s*if \(second\?\.pill && this\.isBot2Hit\(e\.clientX, e\.clientY\)\) \{\s*State\.setFocus\(second\.pill\);\s*Sound\.play\("blip"\);\s*return;\s*\}/);
  assert.match(island, /private isBot2Hit\(x: number, y: number\): boolean \{\s*if \(!this\.pairShown\) return false;/);
});

test("the overview: the ticker's text moves right of the pair and a second line names cat 2's agent; the other modes are untouched", () => {
  const views = source("views/views.ts"), css = source("style.css");
  assert.match(views, /el\.classList\.toggle\("two", two !== null\);/);
  assert.match(views, /`\$\{agentLabel\(other\.id\)\} · \$\{SECOND_LINE\[other\.state\]\}` : "No other agent"/);
  assert.match(views, /approval: "waiting for you", question: "has a question", error: "hit an error"/, "the prototype's word for a question is \"has a question\", and the Mac's ticker says the same");
  const from = css.lastIndexOf("/*", css.indexOf("Two cats mode (sub-project B)")), kit = css.indexOf("Subagent kittens (sub-project B)"), to = kit < 0 ? css.length : css.lastIndexOf("/*", kit);
  const block = css.slice(from, to).replace(/\/\*[\s\S]*?\*\//g, "");
  const selectors = [...block.matchAll(/([^{}]+)\{/g)].map((m) => m[1].trim());
  assert.deepEqual(selectors, ["#bot2-canvas", ".second", ".overview.two .who", ".overview.two .ticker", ".overview.two .int-card", ".overview.two .second"], "new selectors only; every existing rule applies as before outside `.overview.two`");
  assert.match(block, /\.overview\.two \.who \{\s*padding-left: 147px;/);
});

test("the dev server's fake-event path, for looking at the layout: window.__nm.hook feeds handleHook, behind import.meta.env.DEV, and a display mode in the address; nothing for a release build", () => {
  const main = source("main.ts");
  assert.match(main, /if \(import\.meta\.env\.DEV\) \(window as unknown as \{ __nm: unknown \}\)\.__nm = \{ island, State, hook: \(payload: HookPayload\) => handleHook\(island, payload\) \};/);
  assert.match(main, /if \(import\.meta\.env\.DEV\) \{\s*const mode = new URLSearchParams\(location\.search\)\.get\("display"\);\s*if \(mode\) State\.settings\.cat = withDisplayMode\(State\.settings\.cat, mode\);\s*\}/);
  assert.match(source("island/hooks.ts"), /export function handleHook\(island: Island, payload: HookPayload\)/);
});
EOF
```

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/two-cats.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..`
Expected: `# tests 6`, `# pass 0`, `# fail 6`.

- [ ] **Step 2: The island, the overview, the greeting, the style rules and the dev path**

```bash
python3 - <<'PY'
# Task 10: Two cats mode on the island: a second cat beside the first (compact and in the overview), a click on it focuses its agent, the ticker moves right and gains a
# second line, and the greeting's pair arrives together. One cat and A cat for each agent keep today's layout. Run from the repository root.
# Every replacement asserts that its anchor is there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('windows/src/island/island.ts', [
('''  ROUNDED_CORNER, VIEW_LAYOUTS, botGlowColor, botGlowOpacity, botPosition, chatPromptHeight,
''', '''  ROUNDED_CORNER, VIEW_LAYOUTS, botGlowColor, botGlowOpacity, botPosition, chatPromptHeight, pairPlacement,
'''),
('''import { bigCatCollar } from "../cat/collar";
''', '''import type { Cast } from "../cat/cast";
import { bigCatCollar } from "../cat/collar";
'''),
('''  private botCanvas!: HTMLCanvasElement;
''', '''  private botCanvas!: HTMLCanvasElement;
  /** Two cats mode: the second cat's canvas, beside the first. */
  private botCanvas2!: HTMLCanvasElement;
'''),
('''  private botSize = new Spring(10);
''', '''  private botSize = new Spring(10);
  private bot2Cx = new Spring(46);
  private bot2Cy = new Spring(16);
  private bot2Size = new Spring(10);
'''),
('''  private engine = new BotEngine();
''', '''  private engine = new BotEngine();
  /** Two cats mode: the second cat, in the pair's second coat, showing the busiest other agent. */
  private engine2 = new BotEngine();
  /** The cast of the frame (State.cast): which coat each cat wears. */
  private cast: Cast = State.cast;
  /** The second cat is on screen this frame (Two cats mode, compact or the overview, no greeting or drop on top). */
  private pairShown = false;
'''),
('''  private canvasPx = 0;
''', '''  private canvasPx = 0;
  private canvas2Px = 0;
'''),
('''    this.botCanvas = h("canvas", { id: "bot-canvas" });
''', '''    this.botCanvas = h("canvas", { id: "bot-canvas" });
    this.botCanvas2 = h("canvas", { id: "bot2-canvas" });
'''),
('''      this.botGlow,
      this.botCanvas,
      this.miniGrid,''', '''      this.botGlow,
      this.botCanvas,
      this.botCanvas2,
      this.miniGrid,'''),
('''      if (this.isBotHit(e.clientX, e.clientY)) {
        this.cancelBotHover();
        this.engine.slap();
      }''', '''      // Two cats: a click on the second cat focuses its agent, as a click on a pill does.
      const second = this.cast.second;
      if (second?.pill && this.isBot2Hit(e.clientX, e.clientY)) {
        State.setFocus(second.pill);
        Sound.play("blip");
        return;
      }
      if (this.isBotHit(e.clientX, e.clientY)) {
        this.cancelBotHover();
        this.engine.slap();
      }'''),
('''  private isBotHit(x: number, y: number): boolean {''', '''  private isBot2Hit(x: number, y: number): boolean {
    if (!this.pairShown) return false;
    const rect = this.islandRect();
    const cx = rect.x + this.bot2Cx.value;
    const cy = rect.y + this.bot2Cy.value;
    const radius = this.bot2Size.value / 2;
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius;
  }

  private isBotHit(x: number, y: number): boolean {'''),
('''    const dt = Math.min(0.05, (nowMs - this.lastFrame) / 1000);
    this.lastFrame = nowMs;
''', '''    const dt = Math.min(0.05, (nowMs - this.lastFrame) / 1000);
    this.lastFrame = nowMs;
    this.cast = State.cast;
'''),
('''    this.botCy.step(dt);
    this.botSize.step(dt);

    const greetingActive''', '''    this.botCy.step(dt);
    this.botSize.step(dt);
    this.bot2Cx.step(dt);
    this.bot2Cy.step(dt);
    this.bot2Size.step(dt);

    const greetingActive'''),
('''      this.drawBot(dt);
    }

    const uploadActive''', '''      this.drawBot(dt);
      if (this.pairShown) this.drawBot2(dt);
    }

    const uploadActive'''),
('''        greetingActive || this.engine.busy || UploadSeq.isActive;''', '''        greetingActive || this.engine.busy || UploadSeq.isActive ||
        (this.pairShown && (this.engine2.busy || !this.bot2Cx.settled || !this.bot2Cy.settled || !this.bot2Size.settled));'''),
('''    const p = botPosition(State.mode, State.view, this.height.value, State.uploadProgress);
    this.botCx.target = p.cx;''', '''    // Two cats: the pair's places (compact, and the overview); anywhere else the first cat is where it always was and the second is not drawn.
    const pair = this.cast.second ? pairPlacement(State.mode, State.view, this.height.value) : null;
    const p = pair ? pair.first : botPosition(State.mode, State.view, this.height.value, State.uploadProgress);
    this.botCx.target = p.cx;'''),
('''    this.botCanvas.style.opacity = visible ? "1" : "0";
''', '''    this.botCanvas.style.opacity = visible ? "1" : "0";
    this.pairShown = pair !== null && visible;
    if (pair) {
      this.bot2Cx.target = pair.second.cx;
      this.bot2Cy.target = pair.second.cy;
      this.bot2Size.target = pair.second.diameter / 0.6;
    }
    this.botCanvas2.style.opacity = this.pairShown ? "1" : "0";
'''),
('''  /** BotCanvasView.lookX / lookY — tanh of the distance to the bot. */''', '''  /** The second cat of Two cats mode: the pair's second coat, showing the busiest other agent (idle, with no badge, when there is none). */
  private drawBot2(dt: number) {
    const size = this.bot2Size.value;
    const w = Math.max(1, Math.round(size));
    const hCss = w + BOT_OVERHANG;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    if (this.canvas2Px !== w) {
      this.canvas2Px = w;
      this.botCanvas2.width = Math.round(w * dpr);
      this.botCanvas2.height = Math.round(hCss * dpr);
      this.botCanvas2.style.width = `${w}px`;
      this.botCanvas2.style.height = `${hCss}px`;
    }
    this.botCanvas2.style.left = `${this.bot2Cx.value - w / 2}px`;
    this.botCanvas2.style.top = `${this.bot2Cy.value - BOT_OVERHANG / 2 - hCss / 2}px`;
    const ctx = this.botCanvas2.getContext("2d");
    const second = this.cast.second;
    if (!ctx || !second) return;
    const task = second.pill ? State.tasks.find((t) => t.id === second.pill) : undefined;
    const state = State.shownState(task?.state ?? "idle");
    this.engine2.setCoat(second.cat);
    this.engine2.setState(state);
    this.engine2.collarColor = bigCatCollar(state, task?.color);
    this.engine2.particleOverhang = BOT_OVERHANG;
    this.engine2.badgeLeft = State.mode === "compact";
    this.engine2.earRoom = State.mode === "compact" ? this.bot2Cy.value : null;
    this.engine2.setDancing(shouldDance(State.musicPlaying, state, State.mode));
    const rect = this.islandRect();
    this.engine2.lookX = cursorLook(State.mouse.x - (rect.x + this.bot2Cx.value), 0).x;
    this.engine2.lookY = cursorLook(0, State.mouse.y - this.bot2Cy.value).y;
    this.engine2.update(dt);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, hCss);
    this.engine2.draw(ctx, w, hCss);
  }

  /** BotCanvasView.lookX / lookY — tanh of the distance to the bot. */'''),
])

# The overview: the ticker moves right of the pair and gains a second line for cat 2's agent.
edit('windows/src/views/views.ts', [
('''import { State, type AgentTask } from "../core/state";
import { washRGBA, type BotEmoteName, type IslandViewName, type Wash } from "../core/layout";''', '''import { State, type AgentTask } from "../core/state";
import { agentLabel } from "../core/pills";
import { washRGBA, type BotEmoteName, type BotStateName, type IslandViewName, type Wash } from "../core/layout";'''),
('''// ── Overview ──────────────────────────────────────────────────────────────────
''', '''// ── Overview ──────────────────────────────────────────────────────────────────

/** Two cats mode: what the ticker's second line says about cat 2's agent ("Codex · waiting for you"). */
const SECOND_LINE: Record<BotStateName, string> = {
  idle: "idle", working: "working", thinking: "thinking", searching: "searching", approval: "waiting for you", question: "has a question", error: "hit an error",
  finished: "finished", ratelimit: "rate limited", sleeping: "asleep", dizzy: "dizzy",
};
'''),
('''  const tickerBody = h("div", { class: "card-body" }, who, ticker.el);''', '''  const second = h("div", { class: "second" });
  const tickerBody = h("div", { class: "card-body" }, who, ticker.el, second);'''),
('''    sync() {
      const task = State.focusTask;
      if (task?.id !== lastFocus) {''', '''    sync() {
      // Two cats (spec §2): the text moves right of the pair, and a second line names cat 2's agent.
      const two = State.cast.second;
      el.classList.toggle("two", two !== null);
      const other = two?.pill ? State.tasks.find((t) => t.id === two.pill) : undefined;
      second.textContent = two ? (other ? `${agentLabel(other.id)} · ${SECOND_LINE[other.state]}` : "No other agent") : "";
      const task = State.focusTask;
      if (task?.id !== lastFocus) {'''),
])

s = open('windows/src/style.css', encoding='utf-8').read().rstrip('\n')
s += '''

/* ── Two cats mode (sub-project B) ──────────────────────────────────────── */

/* The second cat of the pair, beside the first. */
#bot2-canvas {
  position: absolute;
  pointer-events: none;
}

/* The pair sits side by side, so the overview's text starts further right, and the ticker's card has a second line for cat 2's agent. */
.second {
  display: none;
}

.overview.two .who {
  padding-left: 147px;
}

.overview.two .ticker {
  margin-left: 147px;
}

.overview.two .int-card {
  padding-left: 147px;
}

.overview.two .second {
  display: block;
  margin: 0 12px 0 147px;
  font: 500 11px var(--font);
  color: var(--dim-2);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
'''
open('windows/src/style.css', 'w', encoding='utf-8').write(s)

# The greeting: in Two cats mode the pair arrives together: the settled cat makes room and the second cat pops in beside it as the island folds.
edit('windows/src/cat/greeting.ts', [
('''import { COMPACT_W, NOTCH_H, NOTCH_W } from "../core/layout.ts";''', '''import { COMPACT_W, NOTCH_H, NOTCH_W, PAIR } from "../core/layout.ts";'''),
('''  private readonly miniViews = new Map<string, CatView>();
''', '''  private readonly miniViews = new Map<string, CatView>();
  /** Two cats mode: the pair's second cat, which pops in beside the settled cat; null in the other modes. */
  private pairView: CatView | null = null;
'''),
('''    this.sessionViews = [0, 1, 2, 3].map((i) => this.sessionView(cast?.sessions[i] ?? main));''', '''    this.sessionViews = [0, 1, 2, 3].map((i) => this.sessionView(cast?.sessions[i] ?? main));
    this.pairView = cast?.pair ? this.sessionView(cast.pair[1]) : null;'''),
('''    drawCat(x, v, P.x, P.y, D, { paws, badgeSide: 1 - 2 * EZ.inOut(seg(t, leave, leave + GT.COLLAPSE)) });''', '''    // Two cats: the settled cat makes room (it ends where the real pair's first cat sits), and the second cat pops in beside it as the island folds.
    const fold = EZ.inOut(seg(t, leave, leave + GT.COLLAPSE)), room = this.pairView ? -(40 - PAIR.compact.x1) * fold : 0;
    drawCat(x, v, P.x + room, P.y, D, { paws, badgeSide: 1 - 2 * fold });
    if (this.pairView) {
      const pop = EZ.back(seg(t, leave + 0.24, leave + 0.42));
      if (t > leave && pop > 0.02) drawCat(x, this.pairView, 320 - COMPACT / 2 + PAIR.compact.x2, 16, PAIR.compact.d * pop, { badge: false });
    }'''),
])

# The dev server only (a release build does not contain it): a display mode in the address, and the hook handler for fake events, so the layout can be looked at without a real agent.
edit('windows/src/island/hooks.ts', [
('''interface HookPayload {''', '''/** The part of a hook event the island reads (the relay forwards the whole JSON). */
export interface HookPayload {'''),
('''function handleHook(island: Island, payload: HookPayload) {''', '''/** Exported so that the dev server can feed it fake hook events (main.ts, `window.__nm`); the relay's events come through `registerHookHandlers`. */
export function handleHook(island: Island, payload: HookPayload) {'''),
])
edit('windows/src/main.ts', [
('''import { Island } from "./island/island";
import { registerHookHandlers } from "./island/hooks";''', '''import { withDisplayMode } from "./cat/display";
import { Island } from "./island/island";
import { handleHook, registerHookHandlers, type HookPayload } from "./island/hooks";'''),
('''  island.applySettings();
  State.loadIntegrationTasks();
  // A coat given''', '''  // Dev server only: `/?display=two` starts in that display mode, for looking at it without the Settings window.
  if (import.meta.env.DEV) {
    const mode = new URLSearchParams(location.search).get("display");
    if (mode) State.settings.cat = withDisplayMode(State.settings.cat, mode);
  }
  island.applySettings();
  State.loadIntegrationTasks();
  // A coat given'''),
('''  registerHookHandlers(island);''', '''  registerHookHandlers(island);
  // Dev server only: `window.__nm.hook({...})` feeds the island the same hook JSON the relay would, so the pair and the kittens can be looked at without a real agent.
  if (import.meta.env.DEV) (window as unknown as { __nm: unknown }).__nm = { island, State, hook: (payload: HookPayload) => handleHook(island, payload) };'''),
])
PY
```

- [ ] **Step 3: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/two-cats.test.mjs scripts/cat-tests/greeting.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 19`, `# pass 19`, `# fail 0`, `tsc exit 0`, then `ℹ tests 239`, `ℹ pass 239`, `ℹ fail 0` (the 233 before and the 6 of this task).

- [ ] **Step 4: Prove the pair's arrival bites (not committed)**

```bash
python3 - <<'PY'
import subprocess
p = 'windows/src/cat/greeting.ts'
s = open(p, encoding='utf-8').read()
was = 'if (t > leave && pop > 0.02) drawCat('
assert s.count(was) == 1
run = lambda: print(subprocess.run('cd windows && node --experimental-strip-types --test scripts/cat-tests/two-cats.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"', shell=True, capture_output=True, text=True).stdout, end='')
open(p, 'w', encoding='utf-8').write(s.replace(was, 'if (false) drawCat('))
run()
open(p, 'w', encoding='utf-8').write(s)
run()
PY
```

Expected: the first run prints `not ok 1 - the greeting's pair arrives together: the second cat pops in beside the settled one as the island folds, and not before, and not in the other modes`, `# pass 5` and `# fail 1`; after the line is put back, `# pass 6` and `# fail 0`.

- [ ] **Step 5: Look at it, with fake events, in a browser**

`isl.sh MODE` opens the island at `/?display=MODE`, waits out the launch greeting, seeds `Math.random` (so the agents' coats repeat), feeds the real hook handler a Claude Code session with four subagents (one searching, one asking for an approval), a Gemini CLI session with two subagents and an Antigravity session, collapses the island for the compact picture, opens the overview for the expanded one, and closes the browser. (Kittens are not drawn yet: that is Task 13.)

```bash
SHOTS="${TMPDIR:-/tmp}/b-tauri-shots"
cat > "$SHOTS/isl.sh" <<'ISLSH'
#!/usr/bin/env bash
# usage: isl.sh MODE   (one | perAgent | two): the island in that display mode, fed fake hook events, compact and expanded
MODE=$1; S=isl-$MODE
playwright-cli -s=$S open "http://127.0.0.1:14581/?display=$MODE" --config=pw2x.json | grep -E "Console"
sleep 7
playwright-cli -s=$S eval "(() => { let s = 7; Math.random = () => (s = (Math.imul(s, 1103515245) + 12345) >>> 0) / 4294967296; return 'seeded' })()" > /dev/null
playwright-cli -s=$S eval "(() => { const h = window.__nm.hook; const c = { cwd: 'C:/work/notchmeow', session_id: 's1' };
 h({ ...c, hook_event_name: 'SessionStart' }); h({ ...c, hook_event_name: 'UserPromptSubmit', prompt: 'refactor the island' });
 h({ ...c, hook_event_name: 'PreToolUse', tool_name: 'Edit', tool_input: { file_path: 'island.ts' } });
 for (const id of ['a1', 'a2', 'a3', 'a4']) h({ ...c, hook_event_name: 'SubagentStart', agent_id: id, agent_type: 'Explore' });
 h({ ...c, hook_event_name: 'PreToolUse', agent_id: 'a2', tool_name: 'Grep', tool_input: { pattern: 'x' } });
 h({ ...c, hook_event_name: 'PermissionRequest', agent_id: 'a3', tool_name: 'Bash', tool_input: { command: 'npm test' }, request_id: 'r1' });
 const g = { cwd: 'C:/work/docs', session_id: 'g1', nm_agent: 'gemini' };
 h({ ...g, hook_event_name: 'SessionStart' }); h({ ...g, hook_event_name: 'UserPromptSubmit', prompt: 'summarise' });
 h({ ...g, hook_event_name: 'PreToolUse', tool_name: 'google_web_search', tool_input: { query: 'x' } });
 for (const id of ['b1', 'b2']) h({ ...g, hook_event_name: 'SubagentStart', agent_id: id, agent_type: 'Explore' });
 const y = { cwd: 'C:/work/site', session_id: 'y1', nm_agent: 'antigravity' };
 h({ ...y, hook_event_name: 'SessionStart' }); h({ ...y, hook_event_name: 'UserPromptSubmit', prompt: 'x' });
 return 'events sent' })()" > /dev/null
playwright-cli -s=$S eval "(() => { window.__nm.island.collapse(); return 'collapsed' })()" > /dev/null
playwright-cli -s=$S run-code "async page => { await page.waitForTimeout(1800); await page.screenshot({ path: 'isl-$MODE-compact.png', clip: { x: 280, y: 0, width: 720, height: 60 } }); }" > /dev/null
playwright-cli -s=$S eval "(() => { window.__nm.island.setView('overview'); return 'ok' })()" > /dev/null
playwright-cli -s=$S run-code "async page => { await page.waitForTimeout(1800); await page.screenshot({ path: 'isl-$MODE-expanded.png', clip: { x: 280, y: 0, width: 720, height: 210 } }); }" > /dev/null
playwright-cli -s=$S close > /dev/null
ISLSH
chmod +x "$SHOTS/isl.sh"
(cd windows && npx --no-install vite --port 14581 > "$SHOTS/vite.log" 2>&1 &)
sleep 4
cd "$SHOTS"
./isl.sh two
./isl.sh one
kill $(lsof -ti tcp:14581) 2>/dev/null; sleep 1; lsof -ti tcp:14581 | wc -l
ls isl-*.png
```

Expected: `- Console: 1 errors, 0 warnings` for each mode (the missing `favicon.ico`), `0`, and `isl-one-compact.png  isl-one-expanded.png  isl-two-compact.png  isl-two-expanded.png`. Open them. `isl-two-compact.png`: the compact island with **two** Ø20 cats at its left, Shrimpy and Momo side by side, the first with an amber badge (Claude Code asks for an approval) and the second with a purple one (Antigravity is thinking), and a 2 by 2 grid of four cats at its right (Gemini CLI, Resend, n8n and Vercel: Antigravity is cat 2 and has left the grid, so the next pill takes its place). `isl-two-expanded.png`: Shrimpy at Ø58 and Momo at Ø46 side by side at the left of the left card **with a thin gap between the two heads** (6 px: only Shrimpy's whiskers and Momo's ear tip reach across it), Shrimpy's amber badge at its upper right above Momo's ear and Momo's purple badge at the right of its head, **both clear of the text and of each other**, the card's name line and ticker moved right of them (starting about 8 px after the purple badge), and under the ticker the second line "Antigravity · thinking" (the project's name on the first line is cut shorter than in One cat mode, because the name column lost the pair's width: the status chip and the arrow button keep their sizes; say so to the controller); the right card's pills are Gemini CLI, Resend, n8n and Vercel (Antigravity is not among them), every pill's cat Shrimpy. `isl-one-compact.png` and `isl-one-expanded.png`: one cat, the pills as before with Antigravity in the first of them: One cat mode looks as it did. If the two cats overlap the text, a badge is hidden or an ear is cut at the top of the compact island, fix the numbers in `PAIR` and look again. **Say what you saw to the controller.**

- [ ] **Step 6: Commit**

```bash
git add windows/scripts/cat-tests/two-cats.test.mjs windows/src/island/island.ts windows/src/views/views.ts windows/src/style.css windows/src/cat/greeting.ts windows/src/island/hooks.ts windows/src/main.ts
git commit -m "feat(island): Two cats mode: a second cat, a click that focuses its agent, a ticker that moves right, and the pair's arrival

In Two cats mode the compact island holds two Ø20 cats and the overview Ø58 and Ø46 side by side (every other view keeps its one
cat where it was); the second cat has its own canvas, engine and springs, wears the pair's second coat and shows the busiest other
agent, idle with no badge when there is none; a click on it focuses its agent. The overview's text moves right and gains a second
line for cat 2's agent. The launch greeting's settled cat makes room and the second cat pops in beside it as the island folds.
One cat and A cat for each agent keep today's layout. The dev server gets ?display=two and window.__nm.hook for looking at it.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

# Stage 4: subagent kittens

### Task 11: Kittens: the reducer, the places and the hook-event mapping

**Agent:** `nm-implementer-light`.

**Files:**
- Create: `windows/src/cat/kittens.ts`, `windows/src/island/subagents.ts`
- Test: `windows/scripts/cat-tests/kittens.test.mjs`, `windows/scripts/cat-tests/subagents.test.mjs`

**Interfaces:**
- Consumes: B-0's `kitten-cases.json` (`limits`, `states`, `places`, `scripts`, `order`, `views`, `cleans`, `slots`, `placeOf`); `base.ts`'s `SLEEP_AFTER_MS`, `toolState`, `own`; `display.ts`'s `displayModeOf`.
- Produces: `KITTEN_MAX` (8), `KITTEN_LEAVE_MS` (600), `KITTEN_STATES`, `cleanKittens`, `kittenStep(list, event)`, `kittenOrder`, `kittenView(list, now)`, `KITTEN_PLACES`, `kittenPlaceOf(mode, expanded)`, `kittenSlots(place, kittens)`; the types `Kitten`, `KittenEvent`, `KittenSlots`; `kittenEventOf(payload, t)` (island/subagents.ts): the hook event to kitten event table of the contract.

The kitten is `{id, type, session, state, born, last, until}`. The event table: `SubagentStart` (`agent_id`, `agent_type`, `session_id`) is `start`; `PreToolUse` and `PostToolUse` with an `agent_id` are `tool`; `PermissionRequest` with an `agent_id` is `permission` (its answer, `resolved`, is sent by the approval's own paths, Task 12); `SubagentStop` is `stop`; the parent's `Stop`, `StopFailure` and `SessionEnd` are `end` (the contract names the first and the last; `StopFailure` is added so that a turn that ended in an error does not leave its kittens waiting for the ten-minute sweep, as the Mac does); the sweep that comes with the cat falling asleep is `sweep`. A tool event with no `agent_id` is the parent's own: a Claude Code that sends none still gets kittens at start and stop, in the working pose (spec §3, the fallback).

- [ ] **Step 1: Write the failing tests**

`kittens.test.mjs` replays every script of the fixture event by event and every order, view, clean, slot and place row, then holds what a JSON file cannot: a time that is not a finite number, events that are not events, late and lost events, the cap, and a 4000-event fuzz. `subagents.test.mjs` is the mapping from hook JSON, with a subagent's whole life through the reducer.

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/kittens.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { SLEEP_AFTER_MS, rng, toolState } from "../../src/cat/base.ts";
import { DISPLAY_MODES } from "../../src/cat/display.ts";
import { KITTEN_LEAVE_MS, KITTEN_MAX, KITTEN_PLACES, KITTEN_STATES, cleanKittens, kittenOrder, kittenPlaceOf, kittenSlots, kittenStep, kittenView } from "../../src/cat/kittens.ts";
import { finite, load, same } from "./util.mjs";

// Subagent kittens, replayed from tests/fixtures/cat/kitten-cases.json (B-0) one event at a time, and the events a JSON file cannot hold.
const fx = load("kitten-cases.json");
const step = kittenStep;
const run = (events, list = []) => events.reduce((l, e) => step(l, e), list);
const ids = (list) => list.map((k) => k.id);
const K = (id, state = "working", born = 0, last = born, extra = {}) => ({ id, type: "", session: null, state, born, last, until: null, ...extra });
const deepFreeze = (v) => { if (v && typeof v === "object") { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };

test("the limits, the states and the places are the fixture's", () => {
  same({ max: KITTEN_MAX, leaveMs: KITTEN_LEAVE_MS, sleepAfterMs: SLEEP_AFTER_MS }, fx.limits, "limits");
  assert.deepEqual([...KITTEN_STATES], fx.states);
  same(KITTEN_PLACES, fx.places, "places");
});

test("every script replays event by event, and every order, view, clean, slot and place case from its own input", () => {
  assert.ok(fx.scripts.length >= 21 && fx.slots.length >= 25 && fx.views.length === 4 && fx.placeOf.length === 8);
  for (const s of fx.scripts) {
    let list = s.from;
    s.steps.forEach((st, i) => { list = step(list, st.ev); same(list, st.list, `${s.name}, event ${i + 1}`); });
  }
  for (const c of fx.order) assert.deepEqual(kittenOrder(c.list).map((k) => k.id), c.out, c.name);
  for (const c of fx.views) assert.deepEqual(kittenView(c.list, c.now).map((k) => k.id), c.out, c.name);
  for (const c of fx.cleans) same(cleanKittens(c.raw), c.out, c.name);
  for (const c of fx.slots) same(kittenSlots(c.place, c.kittens), c.out, c.name);
  for (const c of fx.placeOf) assert.equal(kittenPlaceOf(c.mode, c.expanded), c.out, `${c.mode} ${c.expanded}`);
});

test("a time that is not a finite number changes nothing (a JSON fixture cannot hold one), and a view at such a time hides nothing", () => {
  const list = [K("a"), K("b", "leaving", 1, 2, { until: 5 })];
  for (const t of [NaN, Infinity, -Infinity, "1", null, undefined, {}]) {
    for (const type of ["start", "tool", "permission", "resolved", "stop", "end", "sweep", "tick"]) same(step(list, { type, id: "a", session: "s", tool: "Grep", t }), list, `${type} t ${String(t)}`);
  }
  assert.equal(kittenView(list, NaN).length, 2);
  assert.equal(kittenView(list, "x").length, 2);
  assert.equal(kittenView(list, 4).length, 2);
  assert.equal(kittenView(list, 5).length, 1);
});

test("an event that is not an event, or has a type that is not known, returns the list as it is", () => {
  const list = [K("a")];
  for (const ev of [null, undefined, 7, "start", [], {}, { t: 1 }, { type: "bogus", t: 1 }, { type: "start", t: 1 }, { type: "start", id: "", t: 1 }, { type: "start", id: 7, t: 1 }, { type: "start", id: "x".repeat(129), t: 1 }]) same(step(list, ev), list, JSON.stringify(ev));
  same(step(null, { type: "tick", t: 1 }), []);
  same(step("junk", { type: "tick", t: 1 }), []);
});

test("a late event brings nothing back: a tool or permission event for an id that never started, or has left, creates nothing", () => {
  assert.deepEqual(step([], { type: "tool", id: "ghost", tool: "Bash", t: 5 }), []);
  assert.deepEqual(step([], { type: "permission", id: "ghost", t: 5 }), []);
  const gone = run([{ type: "start", id: "a1", t: 0 }, { type: "stop", id: "a1", t: 10 }, { type: "tick", t: 700 }]);
  assert.deepEqual(step(gone, { type: "tool", id: "a1", tool: "Bash", t: 800 }), []);
  const leaving = run([{ type: "start", id: "a1", t: 0 }, { type: "stop", id: "a1", t: 10 }]);
  assert.equal(step(leaving, { type: "tool", id: "a1", tool: "Bash", t: 20 })[0].state, "leaving", "while it is leaving, a late event changes nothing");
  assert.deepEqual(step(leaving, { type: "permission", id: "a1", t: 20 }), leaving);
});

test("the farewell lasts 600 ms: leaving, then gone at the next event from `until` on, and hidden by kittenView from that moment", () => {
  const s = run([{ type: "start", id: "a1", t: 0 }, { type: "start", id: "a2", t: 5 }, { type: "stop", id: "a1", t: 1000 }]);
  assert.deepEqual(s[0], { id: "a1", type: "", session: null, state: "leaving", born: 0, last: 1000, until: 1600 });
  assert.deepEqual(ids(step(s, { type: "tick", t: 1599 })), ["a1", "a2"]);
  assert.deepEqual(ids(step(s, { type: "tick", t: 1600 })), ["a2"]);
  assert.deepEqual(ids(kittenView(s, 1599)), ["a2", "a1"], "newest first; the leaving one is still drawn");
  assert.deepEqual(ids(kittenView(s, 1600)), ["a2"], "hidden from `until` on, with no event and no timer");
  assert.deepEqual(step(s, { type: "stop", id: "a1", t: 1100 }), s, "a second stop changes nothing");
});

test("a lost stop: the parent's stop or the session's end removes them, the sleep sweep removes the stale, and two sessions of one agent do not take each other's", () => {
  const s = run([{ type: "start", id: "a1", session: "s1", t: 0 }, { type: "start", id: "a2", session: "s2", t: 1 }, { type: "start", id: "a3", t: 2 }]);
  assert.deepEqual(ids(step(s, { type: "end", session: "s1", t: 9 })), ["a2"], "only that session's go, and the ones with no session (a3)");
  assert.deepEqual(step(s, { type: "end", t: 9 }), [], "no session: every kitten");
  assert.deepEqual(step(s, { type: "sweep", t: SLEEP_AFTER_MS + 2 }), [], "all three have been quiet for ten minutes or more");
  const fresh = step(s, { type: "tool", id: "a2", tool: "Bash", t: SLEEP_AFTER_MS });
  assert.deepEqual(ids(step(fresh, { type: "sweep", t: SLEEP_AFTER_MS + 5 })), ["a2"], "one that had a recent event stays");
});

test("at most eight kittens: a ninth start drops the oldest, whatever its state; a repeated start only refreshes", () => {
  let list = [];
  for (let i = 1; i <= 9; i++) list = step(list, { type: "start", id: "k" + i, t: i });
  assert.equal(list.length, KITTEN_MAX);
  assert.deepEqual(ids(list), ["k2", "k3", "k4", "k5", "k6", "k7", "k8", "k9"]);
  const again = step(list, { type: "start", id: "k5", agentType: "Plan", t: 50 });
  assert.equal(again.length, KITTEN_MAX);
  assert.deepEqual(again.find((k) => k.id === "k5"), { id: "k5", type: "Plan", session: null, state: "working", born: 5, last: 50, until: null });
});

test("the order is a kitten waiting on an approval first, then the newest", () => {
  const list = run([{ type: "start", id: "a", t: 1 }, { type: "start", id: "b", t: 2 }, { type: "start", id: "c", t: 3 }, { type: "permission", id: "a", t: 4 }]);
  assert.deepEqual(ids(kittenView(list, 10)), ["a", "c", "b"]);
  assert.equal(toolState("Grep"), "searching");
  assert.equal(step(list, { type: "tool", id: "b", tool: "WebSearch", t: 5 })[1].state, "searching");
});

test("the slots: nothing for an unknown place, and every place holds its numbers for 0 to 7 kittens, with no NaN", () => {
  for (const place of [...Object.keys(KITTEN_PLACES), "bogus", "", null, undefined, 7, "__proto__", "constructor"]) for (let n = 0; n <= 7; n++) {
    const out = kittenSlots(place, Array.from({ length: n }, (_, i) => K("k" + i)));
    finite(out);
    assert.ok(out.shown.length <= (KITTEN_PLACES[place]?.max ?? 0) && out.count === n);
    if (!(typeof place === "string" && Object.hasOwn(KITTEN_PLACES, place))) assert.deepEqual([out.unit, out.shown.length, out.more, out.moreAt, out.label], [null, 0, 0, null, null], String(place));
  }
  assert.equal(kittenSlots("pairCompact", [K("a"), K("b")]).label.text, "×2");
  assert.equal(kittenSlots("bigExpanded", Array.from({ length: 7 }, (_, i) => K("k" + i))).more, 4);
  for (const mode of DISPLAY_MODES) for (const expanded of [true, false]) assert.ok(Object.hasOwn(KITTEN_PLACES, kittenPlaceOf(mode, expanded)));
});

test("a frozen list is fine, and nothing is changed in place; 4000 random events keep every list valid", () => {
  const frozen = deepFreeze([K("a"), K("b", "approval", 2)]);
  assert.doesNotThrow(() => step(frozen, { type: "stop", id: "a", t: 9 }));
  assert.deepEqual(frozen, [K("a"), K("b", "approval", 2)]);
  const r = rng(77), types = ["start", "tool", "permission", "resolved", "stop", "end", "sweep", "tick", "bogus"], names = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "", 7, null];
  let list = [], t = 0;
  for (let i = 0; i < 4000; i++) {
    t += Math.floor(r() * 400_000);
    list = step(list, { type: types[Math.floor(r() * types.length)], id: names[Math.floor(r() * names.length)], session: r() < 0.3 ? "s" + Math.floor(r() * 3) : undefined, tool: r() < 0.5 ? "Grep" : "Bash", t: r() < 0.03 ? NaN : t });
    assert.ok(list.length <= KITTEN_MAX && new Set(ids(list)).size === list.length, `event ${i}`);
    assert.ok(list.every((k) => KITTEN_STATES.includes(k.state) && Number.isFinite(k.born) && Number.isFinite(k.last) && (k.state === "leaving") === (k.until !== null)), `event ${i}`);
  }
});
EOF
```

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/subagents.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import { kittenView, kittenStep } from "../../src/cat/kittens.ts";
import { kittenEventOf } from "../../src/island/subagents.ts";

// The hook events that mean something to a pill's kittens (spec §3), and what the kitten list does with them, end to end.
const ev = (p, t = 1000) => kittenEventOf(p, t);
const ids = (list) => list.map((k) => k.id);

test("SubagentStart is a kitten, with its type and its session; a tool, a permission request and SubagentStop carry the subagent's id", () => {
  assert.deepEqual(ev({ hook_event_name: "SubagentStart", agent_id: "a1", agent_type: "Explore", session_id: "s1" }), { type: "start", id: "a1", agentType: "Explore", session: "s1", t: 1000 });
  assert.deepEqual(ev({ hook_event_name: "SubagentStart", agent_id: "a1" }), { type: "start", id: "a1", t: 1000 });
  for (const name of ["PreToolUse", "PostToolUse"]) assert.deepEqual(ev({ hook_event_name: name, agent_id: "a1", tool_name: "Grep" }), { type: "tool", id: "a1", tool: "Grep", t: 1000 }, name);
  assert.deepEqual(ev({ hook_event_name: "PermissionRequest", agent_id: "a1", tool_name: "Bash" }), { type: "permission", id: "a1", t: 1000 });
  assert.deepEqual(ev({ hook_event_name: "SubagentStop", agent_id: "a1", agent_type: "Explore" }), { type: "stop", id: "a1", t: 1000 });
});

test("a tool or permission event with no agent_id is the parent's own: no kitten event (a Claude Code that sends none still gets kittens at start and stop)", () => {
  for (const name of ["PreToolUse", "PostToolUse", "PermissionRequest", "SubagentStart", "SubagentStop"]) {
    assert.equal(ev({ hook_event_name: name, tool_name: "Bash" }), null, name);
    assert.equal(ev({ hook_event_name: name, agent_id: "", tool_name: "Bash" }), null, `${name} with an empty id`);
    assert.equal(ev({ hook_event_name: name, agent_id: 7, tool_name: "Bash" }), null, `${name} with a number`);
    assert.equal(ev({ hook_event_name: name, agent_id: "x".repeat(129) }), null, `${name} with a very long id`);
  }
});

test("the parent's Stop, StopFailure and SessionEnd end the kittens of their session; the same events inside a subagent do not", () => {
  assert.deepEqual(ev({ hook_event_name: "Stop", session_id: "s1" }), { type: "end", session: "s1", t: 1000 });
  assert.deepEqual(ev({ hook_event_name: "StopFailure", session_id: "s1" }), { type: "end", session: "s1", t: 1000 }, "a turn that ended in an error ends them too");
  assert.deepEqual(ev({ hook_event_name: "SessionEnd", session_id: "s1" }), { type: "end", session: "s1", t: 1000 });
  assert.deepEqual(ev({ hook_event_name: "SessionEnd" }), { type: "end", t: 1000 }, "no session: every kitten");
  assert.equal(ev({ hook_event_name: "Stop", session_id: "s1", agent_id: "a1" }), null, "a subagent's own Stop is not the parent's");
});

test("every other hook event, and every payload that is not an object, is no kitten event; a time that is not a time is none either", () => {
  for (const name of ["SessionStart", "UserPromptSubmit", "PostToolUseFailure", "Notification", "StopFailure", "BeforeTool", "", undefined, 7]) assert.equal(ev({ hook_event_name: name, agent_id: "a1" }), null, String(name));
  for (const p of [null, undefined, 7, "x", [], [{ hook_event_name: "Stop" }]]) assert.equal(ev(p), null, String(JSON.stringify(p)));
  for (const t of [NaN, Infinity, "1", null, undefined]) assert.equal(kittenEventOf({ hook_event_name: "SubagentStop", agent_id: "a1" }, t), null, String(t));
});

test("a whole subagent's life through the reducer: start, search, ask, answer, work, stop, gone; and the fallback with no agent_id on the tool events", () => {
  const feed = (list, p, t) => { const e = kittenEventOf(p, t); return e ? kittenStep(list, e) : list; };
  let l = [];
  l = feed(l, { hook_event_name: "SubagentStart", agent_id: "a1", agent_type: "Explore", session_id: "s1" }, 1);
  l = feed(l, { hook_event_name: "PreToolUse", agent_id: "a1", tool_name: "Grep" }, 2);
  assert.equal(l[0].state, "searching");
  l = feed(l, { hook_event_name: "PermissionRequest", agent_id: "a1", tool_name: "Bash" }, 3);
  assert.equal(l[0].state, "approval");
  l = kittenStep(l, { type: "resolved", id: "a1", t: 4 });
  assert.equal(l[0].state, "working");
  l = feed(l, { hook_event_name: "PostToolUse", agent_id: "a1", tool_name: "Bash" }, 5);
  l = feed(l, { hook_event_name: "SubagentStop", agent_id: "a1" }, 6);
  assert.equal(l[0].state, "leaving");
  assert.deepEqual(ids(kittenView(l, 6 + 599)), ["a1"]);
  assert.deepEqual(ids(kittenView(l, 6 + 600)), []);
  // The fallback: tool events carry no agent_id, so the kitten stays in the working pose from its start to its stop.
  let f = feed([], { hook_event_name: "SubagentStart", agent_id: "b1", session_id: "s1" }, 1);
  f = feed(f, { hook_event_name: "PreToolUse", tool_name: "Grep" }, 2);
  assert.equal(f[0].state, "working");
  f = feed(f, { hook_event_name: "Stop", session_id: "s9" }, 3);
  assert.equal(f.length, 1, "a Stop of another session leaves this session's kitten alone");
  f = feed(f, { hook_event_name: "SessionEnd" }, 4);
  assert.deepEqual(f, []);
});
EOF
```

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/kittens.test.mjs scripts/cat-tests/subagents.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..`
Expected: `# tests 2`, `# pass 0`, `# fail 2`.

- [ ] **Step 2: Write the modules**

The numbers of `KITTEN_PLACES` are B-0's (the mockup's pixels over its parent's size); the fixture's `places` pins them, and Setup checked them.

```bash
mkdir -p windows/src/cat
cat > windows/src/cat/kittens.ts <<'EOF'
// Subagent kittens (sub-project B, spec §3): a subagent is a kitten of its parent's cat. Each agent pill keeps a list of kittens, and `kittenStep` is the one reducer
// that changes it; `kittenView` is what to draw at a given time and `kittenSlots` says where each kitten sits beside its parent. A port of "Kittens" in
// design/prototype/cat-core.js (the tie-breaker; fixture tests/fixtures/cat/kitten-cases.json; docs/CAT-CONTRACT.md "Kittens"). Pure: the time is in the event, no clock is
// read, nothing is changed in place, and there is no timer. Imports base.ts and display.ts, so the plain-Node checks (npm run check:cat) can load it.
//
// A kitten is {id, type, session, state, born, last, until}: `id` the subagent's agent_id, `type` its agent_type, `session` the session it belongs to (or null),
// `state` working, searching, approval or leaving, `born` and `last` the times of its start and its last event (ms, any one clock), `until` null or, once it is
// leaving, the time it is removed. A leaving kitten is dropped by the next event, and kittenView hides it from `until` on.

import { SLEEP_AFTER_MS, own, toolState } from "./base.ts";
import { displayModeOf } from "./display.ts";

/** At most this many kittens are tracked per agent; when a ninth starts, the oldest (by `born`) is dropped. */
export const KITTEN_MAX = 8;
/** A kitten that has stopped plays a happy blink for this long (ms), then goes. */
export const KITTEN_LEAVE_MS = 600;
export const KITTEN_STATES = ["working", "searching", "approval", "leaving"] as const;
export type KittenState = (typeof KITTEN_STATES)[number];

export interface Kitten { id: string; type: string; session: string | null; state: KittenState; born: number; last: number; until: number | null }

/** The events kittenStep takes, each with `t` the time in ms. An event that is anything else changes nothing. */
export type KittenEvent = { t: number } & (
  | { type: "start"; id: string; agentType?: string; session?: string }
  | { type: "tool"; id: string; tool?: string }
  | { type: "permission"; id: string }
  | { type: "resolved"; id: string }
  | { type: "stop"; id: string }
  | { type: "end"; session?: string }
  | { type: "sweep" }
  | { type: "tick" }
);

const isPlain = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);
const finite = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const isKittenId = (v: unknown): v is string => typeof v === "string" && v.length > 0 && v.length <= 128;
const typeOfAgent = (v: unknown): string => (typeof v === "string" ? v.slice(0, 64) : "");
const sessionOf = (v: unknown): string | null => (isKittenId(v) ? v : null);

/** A kitten list as an app may hold it, made safe: entries that are not kittens, or repeat an id, are dropped; every entry is a fresh object. */
export function cleanKittens(list: unknown): Kitten[] {
  const out: Kitten[] = [], seen = new Set<string>();
  for (const k of Array.isArray(list) ? list : []) {
    if (!isPlain(k) || !isKittenId(k.id) || seen.has(k.id) || !(KITTEN_STATES as readonly unknown[]).includes(k.state) || !finite(k.born) || !finite(k.last)) continue;
    seen.add(k.id);
    out.push({ id: k.id, type: typeOfAgent(k.type), session: sessionOf(k.session), state: k.state as KittenState, born: k.born, last: k.last, until: k.state === "leaving" && finite(k.until) ? k.until : null });
  }
  return out;
}

const capKittens = (L: Kitten[]): Kitten[] => {
  while (L.length > KITTEN_MAX) {
    let o = 0;
    for (let i = 1; i < L.length; i++) if (L[i].born < L[o].born) o = i;
    L.splice(o, 1);
  }
  return L;
};

/**
 * The reducer. `list` is one pill's kittens, `ev` an event {type, t, ...} with `t` the time in ms; the result is a new list and nothing is changed.
 *   start       {id, agentType, session}   SubagentStart: a kitten, working. A second start for an id that is there only refreshes it.
 *   tool        {id, tool}                 a Pre/PostToolUse that carries an agent_id: searching when `tool` is a search tool (toolState), else working.
 *   permission  {id}                       a PermissionRequest from the subagent: approval.
 *   resolved    {id}                       that request was answered: back to working.
 *   stop        {id}                       SubagentStop: leaving for KITTEN_LEAVE_MS, then gone.
 *   end         {session}                  the parent stopped or its session ended: with a `session`, only that session's kittens go, and the ones with no session; without one, every kitten goes.
 *   sweep                                  the cat's sleep timer fired: a kitten whose last event is SLEEP_AFTER_MS or more ago is gone (its stop never came).
 *   tick                                   nothing but the time.
 * Every event first drops the leaving kittens whose time is up. An event for an id with no kitten, or for a kitten that is already leaving, changes nothing: a late tool
 * event must not bring back a kitten that has gone, and without a SubagentStart there is nothing to show. An event that is not an object, has no finite `t` or has an
 * unknown type returns the list as it is (cleaned). Never throws.
 */
export function kittenStep(list: unknown, ev: unknown): Kitten[] {
  let L = cleanKittens(list);
  if (!isPlain(ev) || !finite(ev.t)) return L;
  const t = ev.t, at = (id: unknown) => L.findIndex((k) => k.id === id && k.state !== "leaving"), set = (i: number, p: Partial<Kitten>) => { L[i] = { ...L[i], ...p }; };
  L = L.filter((k) => k.state !== "leaving" || (k.until ?? 0) > t);
  switch (ev.type) {
    case "start": {
      if (!isKittenId(ev.id)) break;
      const i = L.findIndex((k) => k.id === ev.id);
      if (i >= 0 && L[i].state !== "leaving") { set(i, { last: t, type: typeOfAgent(ev.agentType) || L[i].type, session: sessionOf(ev.session) || L[i].session }); break; }
      if (i >= 0) L.splice(i, 1);
      L.push({ id: ev.id, type: typeOfAgent(ev.agentType), session: sessionOf(ev.session), state: "working", born: t, last: t, until: null });
      capKittens(L);
      break;
    }
    case "tool": { const i = at(ev.id); if (i >= 0) set(i, { state: toolState(ev.tool), last: t }); break; }
    case "permission": { const i = at(ev.id); if (i >= 0) set(i, { state: "approval", last: t }); break; }
    case "resolved": { const i = at(ev.id); if (i >= 0) set(i, { state: L[i].state === "approval" ? "working" : L[i].state, last: t }); break; }
    case "stop": { const i = at(ev.id); if (i >= 0) set(i, { state: "leaving", last: t, until: t + KITTEN_LEAVE_MS }); break; }
    case "end": { const q = sessionOf(ev.session); L = q === null ? [] : L.filter((k) => k.session !== null && k.session !== q); break; }
    case "sweep": L = L.filter((k) => t - k.last < SLEEP_AFTER_MS); break;
  }
  return L;
}

/** The order kittens are shown in: a kitten waiting on an approval first, then the newest (by `born`, a later start first when they tie). */
export const kittenOrder = (list: unknown): Kitten[] =>
  cleanKittens(list).map((k, i) => ({ k, i })).sort((a, b) => Number(b.k.state === "approval") - Number(a.k.state === "approval") || b.k.born - a.k.born || b.i - a.i).map((x) => x.k);

/** What is drawn at `now` (ms): the kittens in kittenOrder, without a leaving kitten whose time is up. A `now` that is not a number hides nothing. */
export const kittenView = (list: unknown, now: unknown): Kitten[] =>
  kittenOrder(cleanKittens(list).filter((k) => k.state !== "leaving" || !finite(now) || (k.until ?? 0) > now));

export interface KittenPlace {
  unit: "D" | "H";
  max: number;
  d?: number;
  x0?: number;
  y0?: number;
  step?: number;
  align?: "start" | "center";
  moreAt?: readonly [number, number];
  moreSize?: number;
  label?: { x: number; y: number; size: number };
}

/**
 * Where kittens sit, pinned by kitten-cases.json. Every number is a multiple of a unit: `D`, the parent's head width, with the origin at the parent's head centre (x to
 * the right, y down), or `H`, the pill's height, with the origin at the pill's trailing edge (the kittens' x is negative, inside it) and the middle of its height. `d` is
 * a kitten's head width. `align` 'start': the i-th kitten is at x0 + i * step; 'center': the row is centred on x0. `max` is the most kittens drawn; the rest is "+N", at
 * `moreAt` (default: the next slot after the last one) in text `moreSize` high. `label` is for the pair in the compact notch, which has no room beside it: only a count "×N".
 */
export const KITTEN_PLACES: Readonly<Record<string, KittenPlace>> = {
  bigExpanded: { unit: "D", max: 3, d: 15 / 58, x0: 24 / 58, y0: 34 / 58, step: 18 / 58, align: "start", moreSize: 0.2 },
  bigCompact: { unit: "D", max: 2, d: 12 / 20, x0: 22 / 20, y0: 5 / 20, step: 13 / 20, align: "start", moreAt: [42 / 20, -10 / 20], moreSize: 0.25 },
  pairCompact: { unit: "D", max: 0, label: { x: 1.1, y: 0.3, size: 0.5 } },
  pairExpanded: { unit: "D", max: 3, d: 15 / 58, x0: 0, y0: 34 / 58, step: 18 / 58, align: "center", moreAt: [0, 50 / 58], moreSize: 0.2 },
  pill: { unit: "H", max: 3, d: 15 / 28, x0: -17.5 / 28, y0: 0, step: -16 / 28, align: "start", moreSize: 0.36 },
};

/** The place kittens go for the big cat (and, in Two cats mode, for cat 2): bigExpanded or bigCompact; in Two cats mode pairExpanded or pairCompact. An agent pill uses `pill`. */
export const kittenPlaceOf = (mode: unknown, expanded: unknown): string =>
  displayModeOf(mode) === "two" ? (expanded ? "pairExpanded" : "pairCompact") : expanded ? "bigExpanded" : "bigCompact";

export interface KittenSlot { id: string; state: string; x: number; y: number; d: number }
export interface KittenSlots {
  place: string;
  unit: "D" | "H" | null;
  count: number;
  shown: KittenSlot[];
  more: number;
  moreAt: { x: number; y: number; size: number } | null;
  label: { text: string; x: number; y: number; size: number } | null;
}

/**
 * The slots for one parent's kittens in one place. `kittens` is what kittenView returned (already in order). `shown` is the first `max` kittens as {id, state, x, y, d};
 * `more` how many are left over; `moreAt` {x, y, size} or null when none is left over; `label` null, or for pairCompact {text: "×N", x, y, size} when there is a kitten.
 * An unknown place shows nothing.
 */
export function kittenSlots(place: unknown, kittens: unknown): KittenSlots {
  const P = typeof place === "string" && own(KITTEN_PLACES, place) ? KITTEN_PLACES[place] : null;
  const L = (Array.isArray(kittens) ? kittens : []).filter((k): k is Record<string, unknown> => isPlain(k) && isKittenId(k.id)), count = L.length;
  if (!P) return { place: String(place), unit: null, count, shown: [], more: 0, moreAt: null, label: null };
  const n = Math.min(count, P.max), step = P.step ?? 0, x0 = P.x0 ?? 0, y0 = P.y0 ?? 0, x = (i: number) => (P.align === "center" ? x0 + (i - (n - 1) / 2) * step : x0 + i * step), more = P.label ? 0 : count - n;
  return {
    place: place as string, unit: P.unit, count,
    shown: L.slice(0, n).map((k, i) => ({ id: k.id as string, state: typeof k.state === "string" ? k.state : "working", x: x(i), y: y0, d: P.d ?? 0 })),
    more,
    moreAt: more > 0 ? { x: P.moreAt ? P.moreAt[0] : x0 + P.max * step, y: P.moreAt ? P.moreAt[1] : y0, size: P.moreSize ?? 0 } : null,
    label: P.label && count > 0 ? { text: `×${count}`, x: P.label.x, y: P.label.y, size: P.label.size } : null,
  };
}
EOF
```

```bash
mkdir -p windows/src/island
cat > windows/src/island/subagents.ts <<'EOF'
// Subagent hook events → kitten events (sub-project B, spec §3). The hook handlers (hooks.ts) call `kittenEventOf` for every hook event and give what comes back to the
// pill's kitten list (`State.kittenEvent`). Pure, so the plain-Node checks (npm run check:cat) can load it. The table is docs/CAT-CONTRACT.md "Kittens":
//
//   SubagentStart (agent_id, agent_type, session_id)     start       a kitten, working
//   PreToolUse, PostToolUse with an agent_id            tool        searching for a search tool, else working (no agent_id: the parent's own tool, no kitten event)
//   PermissionRequest with an agent_id                  permission  approval (its answer is `resolved`, sent by the approval's paths)
//   SubagentStop                                        stop        a happy blink of 0.6 s, then gone
//   the parent's Stop, StopFailure, and SessionEnd      end         every kitten of that session goes (an event with an agent_id is a subagent's own, not the parent's)
//
// Codex has no hooks on Windows and Linux, so no Codex kittens here; Gemini CLI and Antigravity send no subagent events.

import type { KittenEvent } from "../cat/kittens.ts";

const isId = (v: unknown): v is string => typeof v === "string" && v.length > 0 && v.length <= 128;

/** The kitten event a hook event means, at time `t` (ms, the clock the kitten lists use), or null when it is not one. `payload` is the hook JSON as the relay sent it. */
export function kittenEventOf(payload: unknown, t: number): KittenEvent | null {
  if (payload === null || typeof payload !== "object" || Array.isArray(payload) || typeof t !== "number" || !Number.isFinite(t)) return null;
  const p = payload as Record<string, unknown>, id = isId(p.agent_id) ? p.agent_id : null;
  switch (p.hook_event_name) {
    case "SubagentStart":
      return id === null ? null : { type: "start", id, ...(typeof p.agent_type === "string" ? { agentType: p.agent_type } : {}), ...(isId(p.session_id) ? { session: p.session_id } : {}), t };
    case "SubagentStop":
      return id === null ? null : { type: "stop", id, t };
    case "PreToolUse":
    case "PostToolUse":
      return id === null ? null : { type: "tool", id, ...(typeof p.tool_name === "string" ? { tool: p.tool_name } : {}), t };
    case "PermissionRequest":
      return id === null ? null : { type: "permission", id, t };
    case "Stop":
    case "StopFailure":
    case "SessionEnd":
      return id !== null ? null : { type: "end", ...(isId(p.session_id) ? { session: p.session_id } : {}), t };
    default:
      return null;
  }
}
EOF
```

- [ ] **Step 3: Run the tests and the type check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/kittens.test.mjs scripts/cat-tests/subagents.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"; npx --no-install tsc --noEmit; echo "tsc exit $?"; cd ..`
Expected: `# tests 16`, `# pass 16`, `# fail 0`, `tsc exit 0`.

- [ ] **Step 4: Prove the cap bites (not committed)**

```bash
python3 - <<'PY'
import subprocess
p = 'windows/src/cat/kittens.ts'
s = open(p, encoding='utf-8').read()
was = 'export const KITTEN_MAX = 8;'
assert s.count(was) == 1
run = lambda: print(subprocess.run('cd windows && node --experimental-strip-types --test scripts/cat-tests/kittens.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"', shell=True, capture_output=True, text=True).stdout, end='')
open(p, 'w', encoding='utf-8').write(s.replace(was, 'export const KITTEN_MAX = 9;'))
run()
open(p, 'w', encoding='utf-8').write(s)
run()
PY
```

Expected: the first run prints `not ok 1 - the limits, the states and the places are the fixture's`, `not ok 2 - every script replays event by event, and every order, view, clean, slot and place case from its own input` and `not ok 8 - at most eight kittens: a ninth start drops the oldest, whatever its state; a repeated start only refreshes`, then `# pass 8` and `# fail 3`; after the line is put back, `# pass 11` and `# fail 0`.

- [ ] **Step 5: Run the whole cat check and commit**

Run: `cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `ℹ tests 255`, `ℹ pass 255`, `ℹ fail 0` (the 239 before and the 16 of this task).

```bash
git add windows/scripts/cat-tests/kittens.test.mjs windows/scripts/cat-tests/subagents.test.mjs windows/src/cat/kittens.ts windows/src/island/subagents.ts
git commit -m "feat(cat): subagent kittens: the reducer, the places and the hook-event mapping

kittenStep is the one reducer over a pill's kitten list (start, tool, permission, resolved, stop, end, sweep), kittenView hides a
leaving kitten from its until with no timer, and kittenSlots and kittenPlaceOf say where kittens sit; all replay kitten-cases.json
event by event, with their own tests for a time that is not finite. island/subagents.ts maps a hook event to a kitten event: a
tool or permission event with no agent_id is the parent's own, and a subagent's own Stop is not the parent's. Nothing uses them yet.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 12: Kittens in State, the hook handlers, the sweep when the cat falls asleep

**Agent:** `nm-implementer`.

**Files:**
- Modify: `windows/src/core/state.ts`, `windows/src/island/hooks.ts`, `windows/src/island/island.ts`, `windows/src/island/sleep.ts`
- Test: `windows/scripts/cat-tests/kitten-wiring.test.mjs`

**Interfaces:**
- Consumes: Task 11's `kittenStep`, `kittenView`, `Kitten`, `KittenEvent`, `kittenEventOf`; `State.tasks`, `removeTask`, `pendingApproval`; `hooks.ts`'s `handleHook`, the `PermissionRequest` case and its 108 s timeout; `island.ts`'s `decide` and its `SleepClock`; `sleep.ts`'s `SleepClock`, `SleepEnv`.
- Produces: `State.kittens`, `State.kittenEvent(pillId, event)`, `State.kittenView(pillId, now?)`, `State.sweepKittens(now?)`, `State.subagentApprovalOver(request, t?)`; `ApprovalInfo.agentId`; `SleepEnv.sweep?()`, called by the clock right after the cat falls asleep (never when its timer fires under a working cat). Task 13 draws the lists.

One mutation point: `handleHook` already switches on these hook names, so the kitten events are made there, before anything else changes. The parent cat behaves exactly as today: its state, its ticker's "+ subagent" and "subagent done" lines, its approval cards. The lists are per agent pill, not per session, and never stored; a pill that goes takes its list. No new timer: a leaving kitten is hidden by `kittenView` from its `until`, and the lost ones are swept by the cat's own ten-minute timer, which every hook event already restarts, **when the cat falls asleep**: an idle cat that has heard nothing for ten minutes and has no approval waiting. A timer that fires under a working cat sweeps nothing: a subagent busy in a long, silent step is alive, and its kitten stays (the Mac does the same; the owner chose it).

- [ ] **Step 1: Write the failing test**

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/kitten-wiring.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { SLEEP_AFTER_MS } from "../../src/cat/base.ts";
import { KITTEN_LEAVE_MS } from "../../src/cat/kittens.ts";
import { State } from "../../src/core/state.ts";
import { SleepClock } from "../../src/island/sleep.ts";
import { kittenEventOf } from "../../src/island/subagents.ts";

// The kittens in State, the hook handlers that feed them, the sweep that comes with the cat falling asleep and the approval a subagent asked for. hooks.ts needs a browser, so the handlers are pinned by source.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const MIN = 60_000;
const task = (id) => ({ id, name: id, color: "#8AB4F8", state: "idle", stepIndex: 0, steps: [], source: "agent", isIntegration: false });
const reset = () => { State.tasks = [task("integration_claude"), task("agent_gemini")]; State.kittens = {}; State.pendingApproval = null; };
/** What handleHook does with a hook event's kitten part: map it and give it to the pill. */
const feed = (pill, payload, t) => { const e = kittenEventOf(payload, t); if (e) State.kittenEvent(pill, e); };
const ids = (pill, now) => State.kittenView(pill, now).map((k) => k.id);

test("a subagent's life in State: start, tool, ask, answer, stop, gone; each pill has its own list, and nothing is ever stored", () => {
  reset();
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "a1", agent_type: "Explore", session_id: "s1" }, 1000);
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "a2", session_id: "s1" }, 1001);
  feed("integration_claude", { hook_event_name: "PreToolUse", agent_id: "a1", tool_name: "Grep" }, 1002);
  assert.deepEqual(State.kittenView("integration_claude", 1003).map((k) => [k.id, k.state]), [["a2", "working"], ["a1", "searching"]]);
  feed("integration_claude", { hook_event_name: "PermissionRequest", agent_id: "a1", tool_name: "Bash" }, 1004);
  assert.deepEqual(ids("integration_claude", 1005), ["a1", "a2"], "a kitten waiting on an approval first");
  State.subagentApprovalOver({ requestId: "r", sessionId: "s1", tool: "Bash", command: "ls", agentId: "a1" }, 1006);
  assert.equal(State.kittenView("integration_claude", 1007).find((k) => k.id === "a1").state, "working", "answered: back to working");
  feed("integration_claude", { hook_event_name: "SubagentStop", agent_id: "a1" }, 2000);
  assert.deepEqual(ids("integration_claude", 2000 + KITTEN_LEAVE_MS - 1), ["a2", "a1"], "a1 is leaving: still drawn");
  assert.deepEqual(ids("integration_claude", 2000 + KITTEN_LEAVE_MS), ["a2"], "and gone from 600 ms on, with no event and no timer");
  assert.deepEqual(State.kittenView("agent_gemini", 2000), [], "another pill has none");
  assert.equal(JSON.stringify(State.settings).includes("a2"), false, "kittens are never in the settings");
  assert.equal(JSON.stringify(State.settings.cat).includes("kitten"), false);
});

test("an event for a pill that is not there is ignored; a late event brings nothing back; the parent's Stop and a removed pill take their kittens", () => {
  reset();
  feed("agent_unknown", { hook_event_name: "SubagentStart", agent_id: "x" }, 1);
  assert.deepEqual(State.kittens, {});
  feed("integration_claude", { hook_event_name: "PreToolUse", agent_id: "ghost", tool_name: "Bash" }, 2);
  assert.deepEqual(State.kittens, {}, "a tool event for an id that never started creates nothing");
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "a1", session_id: "s1" }, 3);
  feed("integration_claude", { hook_event_name: "Stop", session_id: "s1" }, 4);
  assert.deepEqual(State.kittens, {}, "the parent stopped: no kittens left, and no empty list is kept");
  feed("agent_gemini", { hook_event_name: "SubagentStart", agent_id: "g1" }, 5);
  assert.equal(State.kittenView("agent_gemini", 6).length, 1);
  State.removeTask("agent_gemini");
  assert.deepEqual(State.kittens, {}, "a pill that goes takes its kittens");
});

test("a subagent's own approval: the request names its agent_id, and the kitten waits until the approval is answered or times out; a parent's approval touches no kitten", () => {
  reset();
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "a1" }, 1);
  feed("integration_claude", { hook_event_name: "PermissionRequest", agent_id: "a1" }, 2);
  assert.equal(State.kittenView("integration_claude", 3)[0].state, "approval");
  State.subagentApprovalOver({ requestId: "r", sessionId: "s", tool: "Bash", command: "ls" }, 4);
  assert.equal(State.kittenView("integration_claude", 5)[0].state, "approval", "the parent's own request (no agentId) leaves it waiting");
  State.subagentApprovalOver(null, 5);
  State.subagentApprovalOver({ requestId: "r", sessionId: "s", tool: "Bash", command: "ls", agentId: "a1" }, 6);
  assert.equal(State.kittenView("integration_claude", 7)[0].state, "working");
  const hooks = source("island/hooks.ts"), island = source("island/island.ts");
  assert.match(hooks, /\.\.\.\(typeof payload\.agent_id === "string" && payload\.agent_id \? \{ agentId: payload\.agent_id \} : \{\}\),/);
  assert.match(hooks, /State\.subagentApprovalOver\(State\.pendingApproval\);\s*State\.pendingApproval = null;/, "the 108 s timeout");
  assert.match(island, /State\.subagentApprovalOver\(req\);\s*State\.pendingApproval = null;/, "Allow and Deny");
});

test("the hook handlers feed the kittens before anything else changes, with the clock the lists use, and the relay's agent_id reaches them", () => {
  const hooks = source("island/hooks.ts");
  assert.match(hooks, /const focused = State\.focusId === agentId;\s*\/\/ Subagent kittens[^\n]*\n\s*const kitten = kittenEventOf\(payload, performance\.now\(\)\);\s*if \(kitten\) State\.kittenEvent\(agentId, kitten\);/);
  assert.match(hooks, /agent_id\?: string;\s*agent_type\?: string;/);
  assert.match(hooks, /case "SubagentStart":\s*State\.appendStep\(agentId, "\+ subagent"\);/, "the ticker's lines are as they were");
  assert.match(hooks, /case "SubagentStop":\s*State\.appendStep\(agentId, "• subagent done"\);/);
  assert.match(fs.readFileSync(new URL("../../hook/src/main.rs", import.meta.url), "utf8"), /DROPPED_FIELDS: &\[&str\] = &\["tool_response", "transcript_path"\];/, "the relay drops only these two");
});

/** A clock and a timer queue turned by hand, and a cat that records the sweeps and the falls asleep. `w.blocked` is an approval waiting for the user. */
function world(state = "idle") {
  const w = { t: 0, state, blocked: false, timers: new Map(), id: 1, sweeps: 0, falls: 0 };
  const env = {
    now: () => w.t, state: () => w.state, blocked: () => w.blocked,
    set: (fn, ms) => { const id = w.id++; w.timers.set(id, { fn, at: w.t + ms }); return id; }, clear: (id) => { w.timers.delete(id); },
    fall: () => { w.falls++; }, wake: () => {}, sweep: () => { w.sweeps++; State.sweepKittens(w.t); },
  };
  w.advance = (ms) => {
    const end = w.t + ms;
    for (;;) {
      const due = [...w.timers.entries()].filter(([, x]) => x.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
      if (!due) break;
      w.t = due[1].at; w.timers.delete(due[0]); due[1].fn();
    }
    w.t = end;
  };
  return { w, clock: new SleepClock(env) };
}

test("falling asleep sweeps the kittens whose stop never came; an event starts the ten minutes again; an approval that waits blocks both; there is no other timer", () => {
  reset();
  const { w, clock } = world("idle");
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "lost" }, 0);
  w.advance(SLEEP_AFTER_MS - 1);
  assert.equal(w.sweeps, 0);
  assert.equal(State.kittenView("integration_claude", w.t).length, 1);
  w.advance(1);
  assert.deepEqual([w.falls, w.sweeps], [1, 1], "ten quiet minutes: the cat falls asleep, and the sweep comes with it");
  assert.deepEqual(State.kittens, {}, "the lost kitten is gone");
  assert.equal(w.timers.size, 0, "and nothing is armed again until the next event");
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "a" }, w.t);
  clock.event("hook");
  w.advance(5 * MIN);
  feed("integration_claude", { hook_event_name: "PreToolUse", agent_id: "a", tool_name: "Bash" }, w.t);
  clock.event("hook");
  w.advance(9 * MIN);
  assert.deepEqual([w.falls, w.sweeps], [1, 1], "each event starts the ten minutes again: nothing fell asleep, nothing was swept");
  w.blocked = true;
  w.advance(MIN);
  assert.deepEqual([w.falls, w.sweeps], [1, 1], "an approval is waiting: the cat does not sleep through it, so nothing is swept either");
  assert.equal(State.kittenView("integration_claude", w.t).length, 1);
  w.blocked = false;
  clock.event("hook");
  w.advance(SLEEP_AFTER_MS);
  assert.deepEqual([w.falls, w.sweeps], [2, 2]);
  assert.match(source("island/island.ts"), /fall: \(\) => State\.fallAsleep\(\),\s*sweep: \(\) => State\.sweepKittens\(\),/);
});

test("a working cat's timer firing sweeps nothing: a subagent in a long, silent step is alive, and its kitten stays", () => {
  reset();
  const { w, clock } = world("working");
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "slow" }, 0);
  w.advance(SLEEP_AFTER_MS + 5 * MIN);
  assert.deepEqual([w.falls, w.sweeps], [0, 0], "a working cat neither falls asleep nor sweeps");
  assert.equal(State.kittenView("integration_claude", w.t).length, 1, "the kitten of the long step is still there");
  assert.equal(w.timers.size, 0, "and nothing is armed again until the next event");
  w.state = "idle";                                    // the turn is over; the stop of the subagent never came
  clock.event("hook");
  w.advance(SLEEP_AFTER_MS);
  assert.deepEqual([w.falls, w.sweeps], [1, 1], "once the cat is idle for ten quiet minutes it falls asleep, and the lost kitten goes");
  assert.deepEqual(State.kittens, {});
});

test("a kitten that was busy lately survives the sweep; one that was quiet for ten minutes does not", () => {
  reset();
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "quiet" }, 0);
  feed("integration_claude", { hook_event_name: "SubagentStart", agent_id: "busy" }, 1);
  feed("integration_claude", { hook_event_name: "PostToolUse", agent_id: "busy", tool_name: "Bash" }, SLEEP_AFTER_MS - 10);
  State.sweepKittens(SLEEP_AFTER_MS + 5);
  assert.deepEqual(ids("integration_claude", SLEEP_AFTER_MS + 5), ["busy"]);
});
EOF
```

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/kitten-wiring.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..`
Expected: `# tests 7`, `# pass 0`, `# fail 7`.

- [ ] **Step 2: State, the hook handlers, the approval and the sweep at the cat's sleep**

```bash
python3 - <<'PY'
# Task 12: the kittens' lists in State, the hook handlers that feed them, the sweep that comes with the cat falling asleep and the approval a subagent asked for. Run from the repository root. Every replacement asserts that its anchor is there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('windows/src/core/state.ts', [
('''import type { CatBlock } from "../cat/display.ts";
''', '''import type { CatBlock } from "../cat/display.ts";
import { kittenStep, kittenView } from "../cat/kittens.ts";
import type { Kitten, KittenEvent } from "../cat/kittens.ts";
'''),
('''  tool: string;
  command: string;
}''', '''  tool: string;
  command: string;
  /** The subagent that asked (the hook's `agent_id`), when one did: its kitten waits on an approval until this one is answered. */
  agentId?: string;
}'''),
('''  /** Where `giveCoats` takes its random numbers: `Math.random`, and a test's own. */''', '''  /** Each agent pill's subagent kittens (cat/kittens.ts), by pill ID. Never stored: `kittenEvent` is the only way they change and `kittenView` says what to draw. */
  kittens: Record<string, Kitten[]> = {};

  /** Where `giveCoats` takes its random numbers: `Math.random`, and a test's own. */'''),
('''    this.settings.cat = { ...cat, agentCats: next };
    this.persistSettings?.();
  }''', '''    this.settings.cat = { ...cat, agentCats: next };
    this.persistSettings?.();
  }

  /** A subagent event for this pill (cat/kittens.ts `kittenStep`; island/subagents.ts maps the hooks to events). An ID that has no pill is ignored. */
  kittenEvent(id: string, ev: KittenEvent) {
    if (!this.tasks.some((t) => t.id === id)) return;
    const next = kittenStep(this.kittens[id] ?? [], ev);
    if (next.length) this.kittens[id] = next;
    else delete this.kittens[id];
    this.notify();
  }

  /** The kittens to draw for this pill at `now` (ms, the clock of the events): in order, without a leaving kitten whose time is up. */
  kittenView(id: string, now: number = performance.now()): Kitten[] {
    return kittenView(this.kittens[id] ?? [], now);
  }

  /** The approval a subagent asked for is over (answered, or timed out): its kitten stops waiting. Nothing for the parent's own approvals. */
  subagentApprovalOver(req: ApprovalInfo | null, t: number = performance.now()) {
    if (req?.agentId) this.kittenEvent("integration_claude", { type: "resolved", id: req.agentId, t });
  }

  /** The cat has fallen asleep (ten quiet minutes): a kitten whose stop never came, and whose own last event is that old, goes (every pill's list gets `sweep`). */
  sweepKittens(now: number = performance.now()) {
    for (const id of Object.keys(this.kittens)) {
      const next = kittenStep(this.kittens[id], { type: "sweep", t: now });
      if (next.length) this.kittens[id] = next;
      else delete this.kittens[id];
    }
    this.notify();
  }'''),
('''    this.tasks.splice(idx, 1);
    if (this.focusId === id) this.focusId = this.tasks[0]?.id ?? "integration_claude";''', '''    this.tasks.splice(idx, 1);
    delete this.kittens[id];
    if (this.focusId === id) this.focusId = this.tasks[0]?.id ?? "integration_claude";'''),
])

edit('windows/src/island/hooks.ts', [
('''import { agentColor } from "../core/pills.ts";
''', '''import { agentColor } from "../core/pills.ts";
import { kittenEventOf } from "./subagents.ts";
'''),
('''  /** Optional agent tag: lowercase, digits and hyphens, ≤ 24 chars. */
  nm_agent?: string;
}''', '''  /** Optional agent tag: lowercase, digits and hyphens, ≤ 24 chars. */
  nm_agent?: string;
  /** Hook events fired inside a subagent carry its id and type (Claude Code); each subagent is a kitten of its parent's pill. */
  agent_id?: string;
  agent_type?: string;
}'''),
('''  const focused = State.focusId === agentId;
''', '''  const focused = State.focusId === agentId;

  // Subagent kittens (spec §3): a SubagentStart, a tool or permission event with an agent_id, a SubagentStop, the parent's Stop or SessionEnd.
  const kitten = kittenEventOf(payload, performance.now());
  if (kitten) State.kittenEvent(agentId, kitten);
'''),
('''        tool,
        command: approvalTarget(tool, input),
      };
      // The relay's short ack window closes in 800 ms; everything below this''', '''        tool,
        command: approvalTarget(tool, input),
        ...(typeof payload.agent_id === "string" && payload.agent_id ? { agentId: payload.agent_id } : {}),
      };
      // The relay's short ack window closes in 800 ms; everything below this'''),
('''        if (!State.pendingApproval) return;
        State.pendingApproval = null;''', '''        if (!State.pendingApproval) return;
        State.subagentApprovalOver(State.pendingApproval);
        State.pendingApproval = null;'''),
])

edit('windows/src/island/island.ts', [
('''        void Bridge.approvalDecision(req.requestId, d);
        State.pendingApproval = null;''', '''        void Bridge.approvalDecision(req.requestId, d);
        State.subagentApprovalOver(req);
        State.pendingApproval = null;'''),
('''    fall: () => State.fallAsleep(),''', '''    fall: () => State.fallAsleep(),
    sweep: () => State.sweepKittens(),'''),
])

edit('windows/src/island/sleep.ts', [
('''  /** The cat is woken (called on every waking event; it must do nothing when the cat is awake). */
  wake(): void;
}''', '''  /** The cat is woken (called on every waking event; it must do nothing when the cat is awake). */
  wake(): void;
  /**
   * The cat has just fallen asleep, after ten quiet minutes: the subagent kittens whose stop never came go. Only here, never when the timer fires under a working cat:
   * a subagent busy in a long, silent step is alive, and its kitten stays. Optional.
   */
  sweep?(): void;
}'''),
('''    if (left === 0 && !this.env.blocked()) this.env.fall();
    else if (left !== null && left > 0) this.arm(left);''', '''    if (left === 0 && !this.env.blocked()) {
      this.env.fall();
      this.env.sweep?.();
    } else if (left !== null && left > 0) this.arm(left);'''),
])
PY
```

- [ ] **Step 3: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/kitten-wiring.test.mjs scripts/cat-tests/sleep.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 16`, `# pass 16`, `# fail 0`, `tsc exit 0`, then `ℹ tests 262`, `ℹ pass 262`, `ℹ fail 0` (the 255 before and the 7 of this task).

- [ ] **Step 4: Prove the sweep belongs to the cat's falling asleep (not committed)**

The rule the owner chose is that the sweep comes with the cat falling asleep. Put the other rule back (sweep whenever the timer fires, whatever the cat is doing, even with an approval waiting) and the two sweep tests must fail.

```bash
python3 - <<'PY'
import subprocess
p = 'windows/src/island/sleep.ts'
s = open(p, encoding='utf-8').read()
was = """      this.env.fall();
      this.env.sweep?.();
"""
assert s.count(was) == 1
# The old rule: sweep whenever the timer fires, whatever the cat is doing.
old = s.replace(was, "      this.env.fall();\n").replace("    this.timer = null;\n", "    this.timer = null;\n    this.env.sweep?.();\n")
assert old != s and old.count("this.env.sweep?.();") == 1
run = lambda: print(subprocess.run('cd windows && node --experimental-strip-types --test scripts/cat-tests/kitten-wiring.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"', shell=True, capture_output=True, text=True).stdout, end='')
open(p, 'w', encoding='utf-8').write(old)
run()
open(p, 'w', encoding='utf-8').write(s)
run()
PY
```

Expected: the first run prints `not ok 5 - falling asleep sweeps the kittens whose stop never came; an event starts the ten minutes again; an approval that waits blocks both; there is no other timer`, `not ok 6 - a working cat's timer firing sweeps nothing: a subagent in a long, silent step is alive, and its kitten stays`, `# pass 5` and `# fail 2`; after the lines are put back, `# pass 7` and `# fail 0`.

- [ ] **Step 5: Commit**

```bash
git add windows/scripts/cat-tests/kitten-wiring.test.mjs windows/src/core/state.ts windows/src/island/hooks.ts windows/src/island/island.ts windows/src/island/sleep.ts
git commit -m "feat(island): subagent kittens in State, fed by the hook handlers, swept when the cat falls asleep

State keeps each agent pill's kitten list (never stored) and a subagent's hook events change it through kittenStep: a start, a tool
or permission event with an agent_id, a stop, and the parent's Stop or SessionEnd. A request a subagent asked for names its
agent_id, so its kitten waits on an approval until the approval is answered or times out. The cat's existing ten-minute sleep
timer sweeps the kittens whose stop never came when the cat falls asleep, and sweeps nothing under a working cat, so a subagent
in a long silent step stays: no new timer, no polling. The parent cat, the ticker's subagent lines and the approval cards work as before.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Drawing the kittens: beside the big cat and the pair, on the pills

**Agent:** `nm-implementer`. Loads `playwright-cli`.

**Files:**
- Create: `windows/src/cat/kittendraw.ts`
- Modify: `windows/src/cat/minibots.ts`, `windows/src/views/views.ts`, `windows/src/island/island.ts`, `windows/src/cat/dev.ts`, `windows/src/style.css`, `windows/scripts/cat-tests/fake-canvas.mjs`
- Test: `windows/scripts/cat-tests/kittendraw.test.mjs`

**Interfaces:**
- Consumes: Tasks 6, 8, 11 and 12: `BotEngine.setCoat`/`collarStyle`, `State.cast`, `State.kittenView`, `kittenSlots`, `kittenPlaceOf`, `Kitten`; the island's springs (`botCx`, `botCy`, `botSize`, `bot2Cx`, …), `uploadActive`, `kittensDrawn`; `minibots.ts`'s registry; `buildPill`.
- Produces: `KittenPool` (`get`, `endFrame`, `size`), `drawKittens(ctx, pool, spot, kittens, dt)` returning the slots, `kittenCatState(state)`, `KittenSpot`; `createKittenStrip(task)`, `tickKittenStrips(dt)`, `kittenStripCount()` (minibots.ts); the island's `drawKittenLayer(dt, covered)` and the `#kitten-canvas` overlay; the `.pill-kits` strip and `.pill.has-kits .lbl` rules; `fakeCanvas().seen.texts`; a **Measure with 8 kittens** button in the `?dev` bench (twelve small cats and a Ø66 with and without eight live kittens).

Each kitten is a live engine of `kittenOf(its parent's coat)`: the parent's motion, personality and collar (in the agent's colour, in the style that coat wears, Task 6), its own state badge, a happy blink (the finished look) while it leaves. It is drawn at the contract's slot: a head of width `d * unit` at the parent's centre plus `(x, y) * unit`; on a pill, `unit` is the pill's height and the origin its trailing edge. The overlay is one canvas over the island, from its left edge; the compact kittens fade out as the island opens and the expanded ones fade in as it is nearly open, which is the canvas's opacity (the cats' own drawing sets the context's alpha). **No new timers and no polling:** the island's frame loop calls `drawKittenLayer` and `tickKittenStrips`, it stops while the island is hidden, and a kitten that has left is hidden by `kittenView`. Kittens are drawn only in the overview (and the compact island): in the other expanded views the cards' text would run under them (plan decision, question 4).

- [ ] **Step 1: Write the failing test**

```bash
mkdir -p windows/scripts/cat-tests
cat > windows/scripts/cat-tests/kittendraw.test.mjs <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { KittenPool, drawKittens, kittenCatState } from "../../src/cat/kittendraw.ts";
import { cleanCatBlock } from "../../src/cat/display.ts";
import { catCfg } from "../../src/cat/engine.ts";
import { kittenStep, kittenView } from "../../src/cat/kittens.ts";
import { createKittenStrip, kittenStripCount, pruneMiniBots, tickKittenStrips } from "../../src/cat/minibots.ts";
import { State } from "../../src/core/state.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

installBrowserStubs();
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

// The kittens' drawing: each is a live kitten engine of its parent's coat, with the parent's collar and its own state; "+N" and "×N" are labels; no timer, no loop.
const K = (id, state = "working", born = 0) => ({ id, type: "", session: null, state, born, last: born, until: state === "leaving" ? 600 : null });
const spot = (o = {}) => ({ place: "bigExpanded", pill: "integration_claude", parentCat: "momo", color: "#8AB4F8", ox: 100, oy: 80, unit: 58, ...o });
const many = (n) => Array.from({ length: n }, (_, i) => K("k" + i, "working", i));

test("a kitten shows its own state, and a happy blink while it leaves", () => {
  assert.deepEqual(["working", "searching", "approval", "leaving", "bogus"].map(kittenCatState), ["working", "searching", "approval", "finished", "working"]);
});

test("each kitten is an engine of kittenOf(its parent's coat), made once and dropped when it has not been drawn for a while", () => {
  const pool = new KittenPool(), e = pool.get("a", "momo", "working");
  assert.deepEqual([e.p.kitten, e.p.base, e.isMini, e.state], [true, "momo", true, "working"]);
  assert.equal(pool.get("a", "momo", "searching"), e, "the same engine, put in its new state");
  assert.equal(e.state, "searching");
  assert.notEqual(pool.get("a", "ginger", "working"), e, "another parent coat, another kitten");
  assert.equal(pool.size, 2);
  for (let i = 0; i < 30; i++) pool.endFrame();
  assert.equal(pool.size, 2, "kept for 30 frames");
  pool.endFrame();
  assert.equal(pool.size, 0, "then gone");
});

test("a row under the big cat: three kittens and a +N, each with the parent's collar colour and its own state, drawn at the slots of the contract", () => {
  const pool = new KittenPool(), ctx = fakeCanvas(), list = [K("k0", "approval", 3), K("k1", "searching", 2), K("k2", "working", 1), K("k3", "leaving", 0)];
  const slots = drawKittens(ctx, pool, spot(), list, 1 / 60);
  assert.equal(slots.shown.length, 3);
  assert.equal(slots.more, 1);
  assert.equal(pool.size, 3);
  assert.deepEqual(ctx.seen.texts, ["+1"], "the overflow label");
  assert.ok(ctx.calls.createRadialGradient >= 3, "a cat each, with its coloured eyes");
  const states = slots.shown.map((q) => pool.get(`bigExpanded:integration_claude:${q.id}`, "momo", kittenCatState(q.state)).state);
  assert.deepEqual(states, ["approval", "searching", "working"]);
  assert.ok(slots.shown.every((q) => pool.get(`bigExpanded:integration_claude:${q.id}`, "momo", "working").collarColor === "#8AB4F8"), "the parent's collar colour");
  const leaving = drawKittens(fakeCanvas(), pool, spot(), [K("z", "leaving")], 1 / 60);
  assert.equal(pool.get(`bigExpanded:integration_claude:${leaving.shown[0].id}`, "momo", "finished").state, "finished", "a leaving kitten blinks happy");
});

test("the pair in the compact notch: no kittens, only the count of them all; the other places, an empty list and an unknown place", () => {
  const pool = new KittenPool(), ctx = fakeCanvas();
  const slots = drawKittens(ctx, pool, spot({ place: "pairCompact", unit: 20 }), many(3), 1 / 60);
  assert.deepEqual([slots.shown.length, slots.label?.text, pool.size, ctx.seen.texts], [0, "×3", 0, ["×3"]]);
  for (const place of ["bigCompact", "pairExpanded", "pill"]) {
    const c = fakeCanvas(), p = new KittenPool();
    assert.equal(drawKittens(c, p, spot({ place, unit: place === "pill" ? 28 : 20 }), many(5), 1 / 60).shown.length, place === "bigCompact" ? 2 : 3, place);
    assert.deepEqual(c.seen.texts, [place === "bigCompact" ? "+3" : "+2"], `${place}: the overflow`);
  }
  const none = fakeCanvas();
  drawKittens(none, new KittenPool(), spot(), [], 1 / 60);
  drawKittens(none, new KittenPool(), spot({ place: "bogus" }), many(4), 1 / 60);
  assert.deepEqual([none.calls.createRadialGradient, none.calls.fill, none.seen.texts], [undefined, undefined, []], "nothing is drawn");
});

test("a kitten of every coat, at the sizes of the places, draws only finite numbers", () => {
  for (const parentCat of ["shrimpy", "momo", "snow", "latte", "noodle"]) for (const place of ["bigExpanded", "bigCompact", "pairExpanded", "pill"]) for (const unit of [0, 20, 58]) {
    drawKittens(fakeCanvas(), new KittenPool(), spot({ place, parentCat, unit }), many(4), 0.05);
  }
});

const el = (tag) => ({ tag, style: { setProperty(k, v) { this[k] = v; } }, className: "", classes: new Set(), width: 0, height: 0, isConnected: true, parentElement: null, append() {}, getContext: () => fakeCanvas(),
  classList: { toggle(n, on) { if (on) this.owner.classes.add(n); else this.owner.classes.delete(n); } } });

test("the pill's strip: kittens at its trailing end, the pill's name makes room, they leave when they stop, and a strip that is gone is forgotten", () => {
  globalThis.document = { createElement: (t) => { const e = el(t); e.classList.owner = e; return e; } };
  globalThis.window = { devicePixelRatio: 1 };
  try {
    State.settings = { ...State.settings, cat: cleanCatBlock({ character: "ginger", displayMode: "perAgent", agentCats: { agent_gemini: "oreo" } }) };
    State.tasks = [{ id: "integration_claude", name: "VS Code", color: "#F5F6F8", state: "working", stepIndex: 0, steps: [], source: "claudeCode", isIntegration: true }, { id: "agent_gemini", name: "gemini", color: "#8AB4F8", state: "idle", stepIndex: 0, steps: [], source: "agent", isIntegration: false }];
    State.focusId = "integration_claude";
    State.kittens = {};
    catCfg.character = undefined;
    const pill = el("div");
    pill.classList.owner = pill;
    const strip = createKittenStrip(State.tasks[1]);
    strip.parentElement = pill;
    assert.deepEqual([strip.className, strip.style.width, strip.style.height], ["pill-kits", "84px", "28px"]);
    tickKittenStrips(1 / 60);
    assert.equal(pill.classes.has("has-kits"), false, "no kitten, nothing drawn, the name where it was");
    const t = performance.now();
    for (let i = 0; i < 4; i++) State.kittenEvent("agent_gemini", { type: "start", id: "g" + i, t: t + i });
    tickKittenStrips(1 / 60);
    assert.equal(pill.classes.has("has-kits"), true);
    assert.ok(parseFloat(pill.style["--kit-w"]) > 56, `room for three kittens and the +N: ${pill.style["--kit-w"]}`);
    State.kittenEvent("agent_gemini", { type: "end", t: t + 10 });
    tickKittenStrips(1 / 60);
    assert.equal(pill.classes.has("has-kits"), false, "the parent stopped: they are gone");
    assert.equal(pill.style["--kit-w"], "0px");
    strip.isConnected = false;
    const before = kittenStripCount();
    tickKittenStrips(1 / 60);
    assert.equal(kittenStripCount(), before - 1, "a strip that is no longer in the document is forgotten");
  } finally {
    delete catCfg.character;
    delete globalThis.window;
    installBrowserStubs();
    pruneMiniBots();
  }
});

test("the island's layer: drawn by the frame loop only, in the place the mode and the size say, never in another expanded view, and cleared once when the last kitten goes", () => {
  const island = source("island/island.ts"), views = source("views/views.ts");
  assert.match(island, /this\.drawKittenLayer\(dt, greetingActive\);\s*tickMiniBots\(dt\);\s*tickKittenStrips\(dt\);/);
  assert.match(island, /const shown = !covered && State\.mode !== "hidden" && !this\.uploadActive && \(!expanded \|\| State\.view === "overview"\);/);
  assert.match(island, /const place = kittenPlaceOf\(cast\.mode, expanded\)/);
  assert.match(island, /if \(this\.kittensDrawn\) \{ ctx\.setTransform\(1, 0, 0, 1, 0, 0\); ctx\.clearRect/);
  assert.doesNotMatch(island + source("cat/kittendraw.ts") + source("cat/minibots.ts"), /setInterval|new Worker/, "no new timers or polling");
  assert.doesNotMatch(source("cat/kittendraw.ts"), /setTimeout|requestAnimationFrame/);
  assert.match(views, /createKittenStrip\(task\),\s*\);/, "buildPill appends the strip");
  assert.equal(kittenView(kittenStep([], { type: "start", id: "a", t: 1 }), 2).length, 1);
});
EOF
```

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/kittendraw.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)"; cd ..`
Expected: `# tests 1`, `# pass 0`, `# fail 1` (`kittendraw.ts` does not exist yet).

- [ ] **Step 2: The kittens' engines and drawing**

```bash
mkdir -p windows/src/cat
cat > windows/src/cat/kittendraw.ts <<'EOF'
// Drawing subagent kittens (sub-project B, spec §3). `kittenSlots` (kittens.ts, the contract) says where each kitten sits beside its parent, in multiples of a unit; this
// draws them: each is a live engine of `kittenOf(the parent's coat)`, with the parent's motion, personality and collar (in the parent's colour, in the style that coat
// wears), its own state badge, and a happy blink while it leaves. The "+N" of a row that is too long and the "×N" count by a pair are small labels. No timer and no loop of
// its own: the island's frame loop calls `drawKittens` for each parent, and an engine nobody has drawn for a while is dropped.
// Imports engine.ts, kittens.ts and presets.ts, so the plain-Node checks (npm run check:cat) can load it.

import { BotEngine } from "./engine.ts";
import { kittenSlots } from "./kittens.ts";
import type { Kitten, KittenSlots } from "./kittens.ts";
import { catById, kittenOf } from "./presets.ts";
import type { StateName } from "./base.ts";

/** The state a kitten shows: its own (working, searching, waiting on an approval), and the finished look, a happy blink, while it leaves. */
export const kittenCatState = (state: string): StateName => (state === "leaving" ? "finished" : state === "approval" ? "approval" : state === "searching" ? "searching" : "working");

/** Frames an engine may go undrawn before it is dropped: a kitten that left, or a parent that is not on screen. */
const KEEP_FRAMES = 30;

/** The engines of the kittens on screen, made when a kitten is first drawn and kept while it is. One pool per page. */
export class KittenPool {
  private readonly engines = new Map<string, { e: BotEngine; used: number }>();
  private frame = 0;

  /** The engine of this kitten, as a kitten of `parentCat`: made once per (key, parent coat), and put in `state`. */
  get(key: string, parentCat: string, state: StateName): BotEngine {
    const k = `${key}:${parentCat}`;
    let slot = this.engines.get(k);
    if (!slot) {
      slot = { e: new BotEngine(kittenOf(catById(parentCat)), { mini: true, state }), used: this.frame };
      this.engines.set(k, slot);
    }
    slot.used = this.frame;
    slot.e.setState(state);
    return slot.e;
  }

  /** Ends a frame: an engine that has not been drawn for a while goes. */
  endFrame() {
    this.frame++;
    for (const [k, slot] of this.engines) if (this.frame - slot.used > KEEP_FRAMES) this.engines.delete(k);
  }

  get size(): number { return this.engines.size; }
}

/** Where one parent's kittens go: the place (kittens.ts `KITTEN_PLACES`), the parent's pill and coat, its collar colour (null for none), and the parent's centre (or, for a pill, its trailing edge and middle) and unit in px. */
export interface KittenSpot { place: string; pill: string; parentCat: string; color: string | null; ox: number; oy: number; unit: number }

/** A small rounded label ("+3", "×4") centred at (x, y), `size` px high. */
function label(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, size: number) {
  const sz = Math.max(8, size);
  ctx.font = `700 ${sz}px system-ui, "Segoe UI", sans-serif`;
  const w = ctx.measureText(text).width + sz * 0.6;
  ctx.fillStyle = "#2a2c31"; ctx.beginPath(); ctx.roundRect(x - w / 2, y - sz * 0.65, w, sz * 1.3, sz * 0.65); ctx.fill();
  ctx.fillStyle = "#cfd0d4"; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(text, x, y + 0.5);
}

/**
 * Draws one parent's kittens (`kittens` is `kittenView`'s list) at `spot`, `dt` seconds after the last frame, and returns the slots it used. Each kitten is a head of width
 * `d * unit` at `(ox, oy) + (x, y) * unit`; the "+N" and the "×N" are labels at their own places. Nothing is drawn for an empty list or an unknown place.
 */
export function drawKittens(ctx: CanvasRenderingContext2D, pool: KittenPool, spot: KittenSpot, kittens: readonly Kitten[], dt: number): KittenSlots {
  const slots = kittenSlots(spot.place, kittens);
  for (const q of slots.shown) {
    const e = pool.get(`${spot.place}:${spot.pill}:${q.id}`, spot.parentCat, kittenCatState(q.state)), head = q.d * spot.unit, w = head / 0.6;
    e.collarColor = spot.color;
    e.update(dt);
    ctx.save(); ctx.translate(spot.ox + q.x * spot.unit - w / 2, spot.oy + q.y * spot.unit - w / 2); e.draw(ctx, w, w); ctx.restore();
  }
  ctx.save();
  if (slots.moreAt) label(ctx, `+${slots.more}`, spot.ox + slots.moreAt.x * spot.unit, spot.oy + slots.moreAt.y * spot.unit, slots.moreAt.size * spot.unit);
  if (slots.label) label(ctx, slots.label.text, spot.ox + slots.label.x * spot.unit, spot.oy + slots.label.y * spot.unit, slots.label.size * spot.unit);
  ctx.restore();
  return slots;
}
EOF
```

- [ ] **Step 3: Draw them: the overlay, the pills' strips and the style rules**

The fake canvas also remembers every text drawn, so a check can read the "+N" and the "×N".

```bash
python3 - <<'PY'
# Task 13: the kittens are drawn: beside the big cat and the pair on an overlay canvas of the island, at the trailing end of an agent pill on a strip of its own. No new timers or
# polling: the island's frame loop draws them. Run from the repository root. Every replacement asserts that its anchor is there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

# The pills' strips.
edit('windows/src/cat/minibots.ts', [
('''import { BotEngine } from "./engine.ts";
''', '''import { BotEngine } from "./engine.ts";
import { KittenPool, drawKittens } from "./kittendraw.ts";
'''),
('''export const miniBotCount = () => live.size;
''', '''export const miniBotCount = () => live.size;

// ── Subagent kittens at the trailing end of an agent pill (spec §3): up to three small kittens and a "+N" ──────────────────────────────────────────────
/** A pill is 28 px high (`H`, the unit of the pill's kitten places); the strip is three heights wide, its right edge the pill's trailing edge. */
const PILL_H = 28;
const STRIP_W = 3 * PILL_H;
const strips = new Map<HTMLCanvasElement, { pill: string; n: number }>();
const stripPool = new KittenPool();

/** The canvas the pill's kittens are drawn on, to be appended to the pill. It draws nothing until the pill has a kitten. */
export function createKittenStrip(task: AgentTask): HTMLCanvasElement {
  const canvas = document.createElement("canvas");
  canvas.className = "pill-kits";
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  canvas.width = Math.round(STRIP_W * dpr);
  canvas.height = Math.round(PILL_H * dpr);
  canvas.style.width = `${STRIP_W}px`;
  canvas.style.height = `${PILL_H}px`;
  strips.set(canvas, { pill: task.id, n: 0 });
  return canvas;
}

/** One frame of every pill's kittens: the cast's coat for the pill is the parent's, and the label of the pill makes room for them. */
export function tickKittenStrips(dt: number) {
  const now = performance.now(), dpr = Math.min(2, window.devicePixelRatio || 1), coats = new Map(State.cast.pills.map((p) => [p.pill, p.cat]));
  for (const [canvas, s] of strips) {
    if (!canvas.isConnected) { strips.delete(canvas); continue; }
    const task = State.tasks.find((t) => t.id === s.pill), list = State.kittenView(s.pill, now), ctx = canvas.getContext("2d");
    if (!ctx || !task) continue;
    if (!list.length && s.n === 0) continue;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, STRIP_W, PILL_H);
    const slots = drawKittens(ctx, stripPool, { place: "pill", pill: s.pill, parentCat: coats.get(s.pill) ?? State.settings.cat.character, color: task.color, ox: STRIP_W, oy: PILL_H / 2, unit: PILL_H }, list, dt);
    s.n = list.length;
    // The pill's name makes room for what is drawn at its trailing end.
    const last = slots.shown[slots.shown.length - 1], room = (slots.moreAt ? -slots.moreAt.x + 0.35 : last ? -last.x + last.d / 2 + 0.2 : 0) * PILL_H;
    const pill = canvas.parentElement;
    if (pill) { pill.classList.toggle("has-kits", list.length > 0); pill.style.setProperty("--kit-w", `${list.length ? room : 0}px`); }
  }
  stripPool.endFrame();
}

/** How many pills have a strip: what the checks look at. */
export const kittenStripCount = () => strips.size;
'''),
])
edit('windows/src/views/views.ts', [
('''import { createMiniBot, pruneMiniBots } from "../cat/minibots";''', '''import { createKittenStrip, createMiniBot, pruneMiniBots } from "../cat/minibots";'''),
('''    canvas,
    h("span", { class: "lbl", text: label }),
  );''', '''    canvas,
    h("span", { class: "lbl", text: label }),
    createKittenStrip(task),
  );'''),
])
edit('windows/src/island/island.ts', [
('''  EXPANDED_CORNER, EXPANDED_W, NOTCH_W, PANEL_H, PANEL_W,
''', '''  EXPANDED_CORNER, EXPANDED_W, NOTCH_H, NOTCH_W, PANEL_H, PANEL_W,
'''),
('''import { createMiniBot, pruneMiniBots, syncMiniBotStates, tickMiniBots } from "../cat/minibots";''', '''import { KittenPool, drawKittens } from "../cat/kittendraw";
import { kittenPlaceOf } from "../cat/kittens";
import { createMiniBot, pruneMiniBots, syncMiniBotStates, tickKittenStrips, tickMiniBots } from "../cat/minibots";'''),
('''import { FLIGHT_MS, cursorLook } from "../cat/geometry";''', '''import { seg } from "../cat/base";
import { FLIGHT_MS, cursorLook } from "../cat/geometry";'''),
('''  private botCanvas2!: HTMLCanvasElement;
''', '''  private botCanvas2!: HTMLCanvasElement;
  /** Subagent kittens beside the big cat and the pair: one overlay canvas over the island (kittendraw.ts). */
  private kittenCanvas!: HTMLCanvasElement;
  private kittenPool = new KittenPool();
  private kittensDrawn = false;
'''),
('''    this.botCanvas2 = h("canvas", { id: "bot2-canvas" });
''', '''    this.botCanvas2 = h("canvas", { id: "bot2-canvas" });
    this.kittenCanvas = h("canvas", { id: "kitten-canvas" });
'''),
('''      this.botCanvas2,
      this.miniGrid,''', '''      this.botCanvas2,
      this.kittenCanvas,
      this.miniGrid,'''),
('''    this.greetingCanvas.style.height = "150px";
''', '''    this.greetingCanvas.style.height = "150px";
    this.kittenCanvas.width = Math.round(KITTEN_W * dpr);
    this.kittenCanvas.height = Math.round(KITTEN_H * dpr);
'''),
('''const BOT_OVERHANG = 40;''', '''const BOT_OVERHANG = 40;
/** The kittens' overlay: from the island's left edge, as wide as the expanded island and as high as its overview plus the kittens under the cat. */
const KITTEN_W = EXPANDED_W;
const KITTEN_H = 170;'''),
('''    tickMiniBots(dt);
''', '''    this.drawKittenLayer(dt, greetingActive);
    tickMiniBots(dt);
    tickKittenStrips(dt);
'''),
('''  /** The second cat of Two cats mode: the pair's second coat, showing the busiest other agent (idle, with no badge, when there is none). */''', '''  /**
   * The subagent kittens of the big cat and, in Two cats mode, of the second cat (kittens.ts places them; kittendraw.ts draws them): compact, up to two tucked beside the cat
   * (one cat, a cat for each agent) or a count by the pair; expanded, in the overview, a row of up to three under each cat. They stay out of every other expanded view, where
   * the cards' text would run under them. Nothing draws while the greeting or the drop sequence owns the island; the canvas is cleared once when the last kitten goes.
   */
  private drawKittenLayer(dt: number, covered: boolean) {
    const ctx = this.kittenCanvas.getContext("2d");
    if (!ctx) return;
    const expanded = State.mode === "expanded", cast = this.cast, now = performance.now();
    const shown = !covered && State.mode !== "hidden" && !this.uploadActive && (!expanded || State.view === "overview");
    const big = shown && cast.big.pill ? State.kittenView(cast.big.pill, now) : [], second = shown && cast.second?.pill ? State.kittenView(cast.second.pill, now) : [];
    if (!big.length && !second.length) {
      if (this.kittensDrawn) { ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, this.kittenCanvas.width, this.kittenCanvas.height); this.kittensDrawn = false; }
      return;
    }
    this.kittensDrawn = true;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, KITTEN_W, KITTEN_H);
    // The compact kittens fade out as the island opens and the expanded ones fade in as it is nearly open. (The cats' own drawing sets the canvas's alpha, so the fade is the canvas's.)
    const grow = clamp((this.height.value - NOTCH_H) / (VIEW_LAYOUTS.overview.height - NOTCH_H), 0, 1);
    this.kittenCanvas.style.opacity = String(expanded ? seg(grow, 0.55, 1) : 1 - seg(grow, 0, 0.25));
    const place = kittenPlaceOf(cast.mode, expanded), colorOf = (pill: string | null) => State.tasks.find((t) => t.id === pill)?.color ?? null;
    const D = this.botSize.value * 0.6, D2 = this.bot2Size.value * 0.6;
    if (place === "pairCompact") {
      // No room beside two Ø20 cats: a count of both cats' kittens by the second cat.
      drawKittens(ctx, this.kittenPool, { place, pill: cast.big.pill ?? "", parentCat: cast.big.cat, color: null, ox: this.bot2Cx.value, oy: this.bot2Cy.value, unit: D2 }, [...big, ...second], dt);
    } else {
      if (big.length) drawKittens(ctx, this.kittenPool, { place, pill: cast.big.pill ?? "", parentCat: cast.big.cat, color: colorOf(cast.big.pill), ox: this.botCx.value, oy: this.botCy.value, unit: D }, big, dt);
      if (second.length && cast.second) drawKittens(ctx, this.kittenPool, { place, pill: cast.second.pill ?? "", parentCat: cast.second.cat, color: colorOf(cast.second.pill), ox: this.bot2Cx.value, oy: this.bot2Cy.value, unit: D2 }, second, dt);
    }
    this.kittenPool.endFrame();
  }

  /** The second cat of Two cats mode: the pair's second coat, showing the busiest other agent (idle, with no badge, when there is none). */'''),
])

s = open('windows/src/style.css', encoding='utf-8').read().rstrip('\n')
s += '''

/* ── Subagent kittens (sub-project B) ───────────────────────────────────── */

/* One overlay over the island, from its left edge, for the kittens beside the big cat and the pair. */
#kitten-canvas {
  position: absolute;
  left: 0;
  top: 0;
  width: 640px;
  height: 170px;
  pointer-events: none;
}

/* The kittens at the trailing end of an agent pill; the pill's name makes room for them. */
.pill-kits {
  position: absolute;
  right: 0;
  top: 50%;
  width: 84px;
  height: 28px;
  transform: translateY(-50%);
  pointer-events: none;
}

.pill.has-kits .lbl {
  left: 36px;
  right: var(--kit-w, 0px);
  text-align: left;
}
'''
open('windows/src/style.css', 'w', encoding='utf-8').write(s)

# The fake canvas also remembers every text drawn, so a check can read the "+N" and the "×N".
edit('windows/scripts/cat-tests/fake-canvas.mjs', [
('''const calls = {}, seen = { fillStyles: [], ellipses: [], strokeStyles: [], lineWidths: [], stops: [] };''', '''const calls = {}, seen = { fillStyles: [], ellipses: [], strokeStyles: [], lineWidths: [], stops: [], texts: [] };'''),
('''      return (...a) => { if (k === "ellipse") seen.ellipses.push(a); return note(String(k), a); };''', '''      return (...a) => { if (k === "ellipse") seen.ellipses.push(a); if (k === "fillText") seen.texts.push(a[0]); return note(String(k), a); };'''),
])

# The ?dev bench also times eight live kittens on top of the twelve small cats and the Ø66 (spec §5: the frame budget is re-measured).
edit('windows/src/cat/dev.ts', [
('''import { Greeting } from "./greeting.ts";
''', '''import { Greeting } from "./greeting.ts";
import { KittenPool, drawKittens } from "./kittendraw.ts";
import type { Kitten } from "./kittens.ts";
'''),
('''  const benchRow = row("Frame time");
  benchRow.append(button("Measure", measure));''', '''  // Eight live kittens on top: three under the big cat, two beside a compact one, three on a pill, each an engine that is updated and drawn.
  const kitPool = new KittenPool();
  const kit = (n: number, o = 0): Kitten[] => Array.from({ length: n }, (_, i) => ({ id: `k${o + i}`, type: "", session: null, state: (o + i) % 3 === 0 ? "searching" : "working", born: o + i, last: o + i, until: null }));
  function benchKittens(withKittens: boolean, frames: number): number {
    const c = fit(benchCv, 720, 90), t0 = performance.now();
    for (let f = 0; f < frames; f++) {
      for (const b of benchViews) drawCat(c, b.v, b.x, 45, b.d);
      if (withKittens) {
        const spot = (place: string, o: Partial<{ ox: number; oy: number; unit: number }>) => ({ place, pill: "bench", parentCat: "shrimpy", color: "#8AB4F8", ox: 400, oy: 45, unit: 20, ...o });
        drawKittens(c, kitPool, spot("bigExpanded", { ox: 640, oy: 20, unit: 66 }), kit(3), 1 / 60);
        drawKittens(c, kitPool, spot("bigCompact", { ox: 100 }), kit(2, 3), 1 / 60);
        drawKittens(c, kitPool, spot("pill", { ox: 340, unit: 28 }), kit(3, 5), 1 / 60);
        kitPool.endFrame();
      }
    }
    return (performance.now() - t0) / frames;
  }
  const measureKittens = () => {
    const none: number[] = [], eight: number[] = [];
    benchKittens(true, 20); benchKittens(false, 20); // warm up
    for (let r = 0; r < 3; r++) { none.push(benchKittens(false, 120)); eight.push(benchKittens(true, 120)); }
    const a = median(none), b = median(eight);
    benchNote.textContent = `Twelve small cats and one Ø66, with their coloured eyes: ${a.toFixed(2)} ms per frame; with eight live kittens on top (three under the big cat, two beside a compact one, three on a pill): ${b.toFixed(2)} ms (median of 3 rounds of 120 frames).`;
  };
  const benchRow = row("Frame time");
  benchRow.append(button("Measure", measure), button("Measure with 8 kittens", measureKittens));'''),
])
PY
```

- [ ] **Step 4: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/kittendraw.test.mjs scripts/cat-tests/two-cats.test.mjs 2>&1 | grep -E "^(not ok|# (tests|pass|fail))"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 13`, `# pass 13`, `# fail 0`, `tsc exit 0`, then `ℹ tests 269`, `ℹ pass 269`, `ℹ fail 0` (the 262 before and the 7 of this task).

- [ ] **Step 5: Prove the parent's collar reaches the kittens (not committed)**

```bash
python3 - <<'PY'
import subprocess
p = 'windows/src/cat/kittendraw.ts'
s = open(p, encoding='utf-8').read()
was = 'e.collarColor = spot.color;'
assert s.count(was) == 1
run = lambda: print(subprocess.run('cd windows && node --experimental-strip-types --test scripts/cat-tests/kittendraw.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)"', shell=True, capture_output=True, text=True).stdout, end='')
open(p, 'w', encoding='utf-8').write(s.replace(was, 'e.collarColor = null;'))
run()
open(p, 'w', encoding='utf-8').write(s)
run()
PY
```

Expected: the first run prints `not ok 3 - a row under the big cat: three kittens and a +N, each with the parent's collar colour and its own state, drawn at the slots of the contract`, `# pass 6` and `# fail 1`; after the line is put back, `# pass 7` and `# fail 0`.

- [ ] **Step 6: Measure the kittens, and look at them, with fake events, in each mode**

The `?dev` bench times twelve small cats and a Ø66 with and without eight live kittens (each an engine that is updated and drawn: three under the big cat, two beside a compact one, three on a pill). Then `isl.sh` (Task 10) shows the kittens: Claude Code has four (one searching, one waiting on an approval), Gemini CLI two, Antigravity none.

```bash
SHOTS="${TMPDIR:-/tmp}/b-tauri-shots"
(cd windows && npx --no-install vite --port 14581 > "$SHOTS/vite.log" 2>&1 &)
sleep 4
cd "$SHOTS"
playwright-cli -s=bench open "http://127.0.0.1:14581/?dev" --config=pw2x.json | grep -E "Console"
sleep 3
playwright-cli -s=bench click "getByRole('button', { name: 'Measure with 8 kittens' })" > /dev/null
sleep 5
playwright-cli -s=bench --raw eval "document.getElementById('eye-bench').textContent"
playwright-cli -s=bench close > /dev/null
./isl.sh one
./isl.sh perAgent
./isl.sh two
kill $(lsof -ti tcp:14581) 2>/dev/null; sleep 1; lsof -ti tcp:14581 | wc -l
ls isl-*.png
```

Expected: `- Console: 1 errors, 0 warnings` four times; `"Twelve small cats and one Ø66, with their coloured eyes: <a> ms per frame; with eight live kittens on top (three under the big cat, two beside a compact one, three on a pill): <b> ms (median of 3 rounds of 120 frames)."` with `<b>` about 1 to 3 ms (headless software drawing again: the Mac's own bench with kittens is about 2.4 ms against its 2 ms budget for the cats without them; **report both numbers to the controller, and the owner decides**); `0`; and the six pictures `isl-one-…`, `isl-perAgent-…`, `isl-two-…` (compact and expanded each; the two of Task 10 are made again). Open them. `isl-one-expanded.png`: the big Shrimpy with **a row of three kittens under it** (the first with an amber badge, the one that waits on an approval) **and a "+1"**, and in the right card Gemini CLI's pill with two small kittens at its right end and its name moved left of them; the Antigravity and Resend pills without any. `isl-one-compact.png`: Shrimpy at the left with **two kittens tucked beside it** and a "+2" above them. `isl-perAgent-expanded.png`: the same, but Antigravity's pill is an Oreo, Gemini CLI's a silver cat and its two kittens silver kittens, Claude Code's kittens Shrimpy kittens. `isl-two-compact.png`: the pair, and **a "×4"** by the second cat. `isl-two-expanded.png`: Shrimpy's kittens under Shrimpy (centred under it, three and a "+1") and none under Momo (Antigravity has none). A kitten's badge is its own state's (dots, a bang, a green dot while it leaves) and the kittens wear the parent's collar colour only when a collar style is on (it is Off by default). If a kitten is cut off, overlaps the card's text or a label hides a cat, fix the numbers in the contract's `KITTEN_PLACES` with the controller, not in this plan, and say so. **Say what you saw to the controller.**

- [ ] **Step 7: Commit**

```bash
git add windows/scripts/cat-tests/kittendraw.test.mjs windows/src/cat/kittendraw.ts windows/src/cat/minibots.ts windows/src/views/views.ts windows/src/island/island.ts windows/src/style.css windows/scripts/cat-tests/fake-canvas.mjs windows/src/cat/dev.ts
git commit -m "feat(island): the kittens are drawn beside the big cat and the pair, and at the trailing end of an agent pill

Each kitten is a live engine of kittenOf(its parent's coat) with the parent's motion, personality and collar (in the agent's colour,
in the style that coat wears), its own state badge and a happy blink while it leaves. Beside the big cat they sit on an overlay canvas
of the island: up to three under it in the overview, up to two tucked beside it in the compact island, a count by the pair, each
pair cat's under it, then +N; on an agent pill a small strip at its trailing end, and the pill's name makes room. Drawn by the
island's frame loop only, never in another expanded view, cleared once when the last kitten goes: no new timer, no polling.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

# Checkpoint 2: the owner looks at the modes and the kittens

**Owner checkpoint** (the executing session; no agent). Stages 3 to 5 are done when the owner says so.

- [ ] Send the owner, in the chat, the six pictures of Task 13 Step 6 (`isl-one-…`, `isl-perAgent-…`, `isl-two-…`, compact and expanded; drawn by the real island from the Vite dev server with fake hook events, not by the Tauri app), with a few lines of text: **One cat looks as it did**, apart from the small eyes and the kittens; **A cat for each agent**: Claude Code is Shrimpy, Codex would be Momo (Windows has no Codex hooks), every other agent has a random coat that is nobody else's and not the Main cat's (seeded in the pictures), kept in `settings.json`, and the agents' collars follow their cats; **Two cats**: the pair side by side, cat 1 the focused agent and cat 2 the busiest other agent (one waiting for you first, then an error, then one working), who is not in the pills or the grid; the second line of the ticker names cat 2's agent; a click on cat 2 focuses its agent; the greeting's pair arrives together; **kittens**: under the big cat (three and "+N"), tucked beside it in the compact island (two and "+N"), a "×N" by the pair, and at the trailing end of an agent's pill (three and "+N"); each shows its own state and leaves with a happy blink; they are not drawn in the other expanded views (approval, chat, …), where the cards' text would run under them; Gemini CLI and Antigravity send no subagent events and **Codex has no hooks on Windows or Linux, so there are no Codex kittens here**.
- [ ] Say what the owner should check by hand in a real build (`cd windows && npm run tauri dev`, on Windows or Linux): **the launch greeting** in each mode (in Two cats the settled cat makes room and the second pops in beside it as the island folds; in A cat for each agent the four session cats are the agents' cats); with real agents running (`gemini`, `agy`, a Claude Code session) the pills and the grid wear each agent's own cat; Settings → Cat → Display: switch modes with the island open and see the island follow with no restart; **a real Claude Code session that starts subagents** (a `Task` call with the Explore agent, for example): a kitten appears beside the big cat at `SubagentStart`, its state follows the subagent's tool calls (`Grep` and `WebSearch` are searching, an edit is working) **if this Claude Code puts `agent_id` on tool events** (Claude Code's documentation says it does; it has not been recorded: with none, the kittens appear and leave in the working pose, which is a planned path), a subagent's own approval shows the kitten waiting until you answer (and the card's Allow and Deny work as before), and the kitten leaves with a happy blink at `SubagentStop`; kill a subagent's session and the kitten goes at the parent's `Stop`, or when the cat falls asleep after ten quiet minutes (a subagent in a long, silent step keeps its kitten as long as the cat is working); the **drop view's** cat wears the big cat's coat (drag a file over the island in each mode); and **0 % CPU** in Task Manager with the island hidden, kittens or not.
- [ ] Wait for the owner's OK. Do not start Task 14 before it.

---

# Stage 5: docs and the final checks

### Task 14: The docs and the final checks

**Agent:** `nm-implementer-light`.

**Files:**
- Modify: `windows/README.md`, `CLAUDE.md`, `ARCHITECT.md`

**Interfaces:**
- Consumes: everything above. Produces: the docs.

`CLAUDE.md` and `ARCHITECT.md` are edited here and only here, in the Windows lines (the Mac plan edits other lines of the same files). **No CI change:** `.github/workflows/windows-tests.yml` runs on `windows/**` and `tests/fixtures/cat/**`, which cover every file this plan adds, so the path filter stays as it is.

- [ ] **Step 1: Write the docs**

`windows/README.md` gets the Display paragraph, the kittens, the small eyes, the `?dev` panel and the dev-only fake-event path, and a line in "What's different from the Mac version"; the two guides get the Windows lines of sub-project B.

```bash
python3 - <<'PY'
# Task 14: the docs. Run from the repository root. Every replacement asserts that its anchor is there exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('windows/README.md', [
('''The cat reacts to what your agents do: it searches while one runs a search tool (web search, web fetch, grep, glob), and the small cats in the pills and in the compact island wear their agent's collar. Gemini CLI is blue and Antigravity pink, as on the Mac.
''', '''The cat reacts to what your agents do: it searches while one runs a search tool (web search, web fetch, grep, glob), and the small cats in the pills and in the compact island wear their agent's collar. Gemini CLI is blue and Antigravity pink, as on the Mac.

**Display** (Settings… → Cat, at the top) chooses how the cats are shown, with a small live preview of the compact island in the chosen mode:

- **One cat** (the default): your **Main cat** everywhere, as it has always been.
- **A cat for each agent**: Claude Code is Shrimpy, and any other agent gets a random coat, different from the others and from your Main cat, the first time it appears, and keeps it. "Cats for your agents" lists them, with a picker, a dice for a new random cat and **Reset to defaults**. The agents' collars follow their cats.
- **Two cats**: a pair, Shrimpy and Momo until you pick, side by side: cat 1 shows the focused agent and cat 2 the busiest other agent (one waiting for you first, then an error, then one working). Click cat 2 to focus its agent. The pair arrives together in the launch greeting, and sleeps together.

A Claude Code **subagent** is a small kitten of its parent's cat. It shows its own state (working, searching, waiting for an approval) and leaves with a happy blink when it stops. The kittens sit under the big cat in the overview (up to three and a "+N"), tucked beside it in the compact island (up to two), as a "×N" count by the pair, and at the trailing end of an agent's pill. A subagent that never reports its end is removed when its agent stops or when the cat falls asleep after ten quiet minutes (a cat that is working sweeps nothing, so a subagent in a long, silent step keeps its kitten). Gemini CLI and Antigravity send no subagent events, and Codex has no hooks on Windows and Linux yet, so they have no kittens. Below a head of Ø28 every cat now has small coloured eyes (an iris in its coat's colours, a slit pupil and a catchlight) in place of the flat ink pills; the three black coats (Midnight, Oreo, Mocha) and their kittens glow instead, with one flat fill of the lighter iris colour and no rim.
'''),
('''The app has no music source on Windows or Linux yet: the cat's bob is built (`src/cat/dance.ts`) and `State.musicPlaying` is the switch, which nothing turns on today.
''', '''The app has no music source on Windows or Linux yet: the cat's bob is built (`src/cat/dance.ts`) and `State.musicPlaying` is the switch, which nothing turns on today.

The Display settings and the kittens are ports of the same contract: `src/cat/display.ts` and `src-tauri/src/cat_settings.rs` (the `displayMode`, `pair` and `agentCats` keys of the `cat` block, cleaned together with the Cat settings and kept at every save), `agentcat.ts` (an agent's coat), `cast.ts` (which cat appears where, read through `State.cast`), `kittens.ts` with `island/subagents.ts` (the hook events that start, change and end a kitten) and `kittendraw.ts`, and `smalleye.ts`. `?dev` has a **Small eyes** panel (every coat and a kitten of it at Ø12 to Ø24, ink pills beside the coloured eyes, magnified 2 times and at true size) and a **Measure** button that times twelve small cats and a big one with each. To look at the island with kittens and the pair without a real agent, open `http://127.0.0.1:1420/?display=two` (or `perAgent`) with `npx vite` and feed it hook events from the browser console, for example `__nm.hook({ hook_event_name: "SubagentStart", cwd: "C:/work/app", session_id: "s1", agent_id: "a1", agent_type: "Explore" })`; `__nm` exists in the dev server only.
'''),
('''- No Apple on-device model: that one is macOS only.
''', '''- No Apple on-device model: that one is macOS only.
- Codex has no hooks here yet, so there is no Codex pill and no Codex kittens; Claude Code's subagents are the only kittens. In Settings → Cat → Display, the list of agents is in a fixed order (Claude Code, then the others by their IDs): this app's Settings window does not see the island's pills, so it cannot sort them by their last event.
'''),
])

edit('CLAUDE.md', [
('''and the ten-minute sleep `island/sleep.ts`.
''', '''and the ten-minute sleep `island/sleep.ts`. Sub-project B on Windows/Linux adds `cat/smalleye.ts` (the coloured small eyes), `cat/display.ts` (the Display settings and the whole `cat` block, `cleanCatBlock`; the Rust twin is `clean_cat_block` in `cat_settings.rs`, and `settings.rs` must keep the three display keys at every save), `cat/agentcat.ts` and `cat/cast.ts` (the agents' coats and which cat appears where, read through `State.cast`), `cat/kittens.ts`, `island/subagents.ts` and `cat/kittendraw.ts` (the subagent kittens), with `settings/display.ts` for the Display rows. Every engine takes its coat from the cast with `setCoat`, and its collar style is looked up per coat (`catCfg.collars`). In the dev server only, `?display=two` and `window.__nm.hook(...)` feed the island fake hook events.
'''),
])
edit('ARCHITECT.md', [
('''the ten-minute sleep (`island/sleep.ts`) and the music bob (`dance.ts`) follow the contract.
''', '''the ten-minute sleep (`island/sleep.ts`) and the music bob (`dance.ts`) follow the contract. **Sub-project B (Windows/Linux):** the `cat` block also holds the Display settings (`displayMode`, `pair`, `agentCats`), cleaned by `cat/display.ts` and, in Rust, `clean_cat_block` (`cat_settings.rs`, called by `settings::sanitized`, so a save keeps them). `State.cast` (`cat/cast.ts`) says which coat each place wears, and every `BotEngine` is given it with `setCoat`. `island/hooks.ts` turns a subagent's hook events into kitten events (`island/subagents.ts`), which change the pill's list in `State.kittens` (`cat/kittens.ts`, never stored); `cat/kittendraw.ts` and the island's overlay canvas draw them, and the ten-minute sleep timer sweeps the ones whose stop never came when the cat falls asleep.
'''),
])
PY
```

Run: `git diff --stat -- windows/README.md | tail -1; grep -c "Sub-project B on Windows/Linux adds" CLAUDE.md; grep -c "Sub-project B (Windows/Linux)" ARCHITECT.md; git diff --stat -- .github | wc -l`
Expected: `1 file changed, 11 insertions(+)` (the README's `git diff` is against the last commit, so this holds in the worktree, where the earlier tasks are committed), `1`, `1` and `0` (the CI file is untouched).

- [ ] **Step 2: Run every check**

Run: `cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1; cd ..`
Expected: `tsc exit 0` with no type error before it, `ℹ tests 269`, `ℹ pass 269`, `ℹ fail 0`, `All AI UI checks passed`, `All Claude Code UI checks passed`.

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓ [0-9]+ fixture files|✓ two generator"`
Expected: `# tests 231`, `# pass 231`, `# fail 0`, `✓ 14 fixture files match cat-core.js`, `✓ two generator runs write identical bytes` (the contract is untouched).

Run: `bash windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/b-tauri 2>&1 | grep -E "^test result|^error|^warning"`
Expected: `test result: ok. 246 passed` (the app's library), `test result: ok. 0 passed` (its binary), `test result: ok. 24 passed` (the relay) and `test result: ok. 0 passed` (the doc tests); no `warning`, no `error`. **The Windows `cargo check` and a release build (`npm run build` also builds the relay for the host) are not run here and are owed to the `windows-tests.yml` and `windows.yml` jobs:** this plan adds Rust only in `cat_settings.rs`, a field and a function in `settings.rs` and a relay test, all plain `serde_json` with no `cfg(windows)` line, which the Linux build in the container compiled and tested.

- [ ] **Step 3: Check that a hidden island costs nothing, kittens or not**

A headless proxy for the 0 % CPU rule: count the animation frames the page asks for. With the island hidden and two kittens alive it must ask for none; open, it asks for one per frame.

```bash
SHOTS="${TMPDIR:-/tmp}/b-tauri-shots"
(cd windows && npx --no-install vite --port 14581 > "$SHOTS/vite.log" 2>&1 &)
sleep 4
cd "$SHOTS"
playwright-cli -s=cpu open "http://127.0.0.1:14581/?display=two" --config=pw2x.json | grep -E "Console"
sleep 7
playwright-cli -s=cpu eval "(() => { window.__frames = 0; const raf = window.requestAnimationFrame.bind(window); window.requestAnimationFrame = (cb) => { window.__frames++; return raf(cb); }; const h = window.__nm.hook, c = { cwd: 'C:/w', session_id: 's1' }; h({ ...c, hook_event_name: 'SessionStart' }); for (const id of ['a1', 'a2']) h({ ...c, hook_event_name: 'SubagentStart', agent_id: id }); return 'two kittens' })()" > /dev/null
sleep 1
playwright-cli -s=cpu eval "(() => { window.__nm.island.fsm.forceHidden(); return 'hidden' })()" > /dev/null
sleep 3
playwright-cli -s=cpu eval "(() => { window.__frames = 0; return 'counting' })()" > /dev/null
sleep 3
echo "frames requested in 3 s with the island hidden and two kittens alive:"
playwright-cli -s=cpu --raw eval "window.__frames"
playwright-cli -s=cpu eval "(() => { window.__nm.island.alert('overview'); return 'open' })()" > /dev/null
sleep 2
echo "frames requested in 2 s with the island open (more than 60):"
playwright-cli -s=cpu --raw eval "window.__frames > 60"
playwright-cli -s=cpu close > /dev/null
kill $(lsof -ti tcp:14581) 2>/dev/null; sleep 1; lsof -ti tcp:14581 | wc -l
```

Expected: `- Console: 1 errors, 0 warnings`, `frames requested in 3 s with the island hidden and two kittens alive:` and `0`, `frames requested in 2 s with the island open (more than 60):` and `true`, then `0` (nothing listens on the port).

- [ ] **Step 4: Check that nothing outside the plan changed, and commit**

Run: `git diff --stat notchmeow/rebrand -- design tests scripts docs/CAT-CONTRACT.md NotchBuddy shared | wc -l`
Expected: `0` (this plan edits no contract file, no fixture and nothing of the Mac app; B-0 is merged, so its files are in the base).

```bash
git add windows/README.md CLAUDE.md ARCHITECT.md
git commit -m "docs(windows): display modes, per-agent cats, kittens and small eyes

windows/README.md describes Display (One cat, A cat for each agent, Two cats), the subagent kittens and the small eyes, the ?dev
Small eyes panel and the dev-only fake-event path, and that Codex has no hooks here yet; CLAUDE.md and ARCHITECT.md get the Windows
lines of sub-project B. The CI path filter already covers every new file.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

Run: `git status --short`
Expected: nothing (everything is committed; `windows/node_modules` is ignored).

---

# Checkpoint 3: the owner signs off

**Owner checkpoint** (the executing session; no agent). Sub-project B on Windows and Linux is done when the owner says so. Then the whole-branch review (`nm-reviewer-deep`).

- [ ] Send the owner, in the chat: the pictures already sent (the small-eye sheets, Settings → Cat in the three modes, the island in the three modes with kittens), the report: the commits, the test counts (`check:cat` 264, `check:ai`, `check:claude`, `cargo test --workspace` 246 and 24, the contract runner 231), the two frame times of Task 2 (before and after) and the bench's ink and coloured medians, the headless zero-frame check, and what was not done: the Windows `cargo check` and a release build (owed to CI), Codex kittens (no hooks on Windows or Linux), kittens in the other expanded views, an agents' list sorted by the last event, and the recorded `agent_id` on a real Claude Code subagent's tool events (the owner's real-agent check).
- [ ] Say what the owner should check by hand in a real build: the list of Checkpoint 1 and Checkpoint 2, again once; and that **nothing looks different in One cat mode** except the eyes and the kittens (the pills, the cards, the Settings rows, the drop view, the greeting).
- [ ] Wait for the owner's OK.

## Parity with macOS

**macOS is the primary platform**: the Mac gets at least what Windows and Linux get. The Mac twin is `docs/superpowers/plans/2026-10-08-b-mac-display-kittens.md`. This section was written against its skeleton and then **checked against the finished Mac plan** (its "Parity with Windows/Linux" table and its Open questions); where the two plans agree, the line says so, and where they differ, it says which side should move. The two plans build the same stages in the same order from the same contract (the small eye, the Display settings, the agents' coats, the cast and the pills' last events, the Settings screen, a coat for every cat view, Two cats, the kittens' rules, the hooks and the drawing, the docs). The main session reads the two together. Everything below is **in this plan and not (known to be) in the Mac's**; each line says whether the Mac should add it or whether it is Windows-only on purpose.

**What both apps do the same, on purpose.** The contract (the five fixtures and the shared rules: `cleanDisplaySettings`, `agentCatFor`, `castOf`, `kittenStep`/`kittenSlots`, `smallEye`), the three modes and their frozen IDs, the layout numbers of the pair and the kittens (B-0's), the coloured eyes at the compact level for every cat, the kitten's state mapping (a leaving kitten blinks with the finished look), kittens only for agent pills, a per-pill last-event time, the busiest-other rule, the collar style looked up per coat, the frame bench before and after (the Mac's draft notes measure 1.70 ms and 1.82 ms; here 0.48 and 0.52 ms in headless Chromium, which only compares this build with itself), and the owner's three checkpoints.

**Added here that the Mac plan should consider:**

1. **The relay keeps `agent_id` and `agent_type`: a test** (Task 5, `hook/src/main.rs`). The relay only drops two big fields, and a test now says that a subagent's ids reach the island. *Mac: the embedded `nm-hook` relay "already passes the payload through"; a one-line pin (the Python shim forwards the whole JSON) closes the same risk.*
2. **Kittens are drawn only in the compact island and the overview, not in the other expanded views** (Task 13): the approval, question, chat and drop views have text where the kittens would sit. *Mac: decide the same, or say where the kittens go in those views; the spec's table says "beside the parent, wherever it is drawn".*
3. **A click on cat 2 focuses its agent only while the overview is open** (Task 10): in the compact island a click opens the island as it always did, and no other expanded view shows cat 2. *Mac: the same, or say what a tap on cat 2 does in the compact notch.*
4. **The ticker's second line's words** (Task 10): "Codex · waiting for you", "has a question", "hit an error", "rate limited", "asleep", … (a table in `views.ts`), and "No other agent" when there is none. *Mac: its plan already uses these words ("hit an error", "rate limited", "No other agent"); check the rest of the table against `views.ts` so the ticker reads the same on both.*
5. **The greeting in Two cats mode**: the settled cat moves 10 px left, to where the real pair's first cat sits (30 px from the island's left edge instead of 40), as cat 2 pops in at 54 (Task 10). The prototype draws only cat 2's pop, so a settled cat at 40 would jump 10 px when the real pair takes over. *Mac: its plan settles cat 1 at 30 pt and pops cat 2 in beside it, which is the same thing (checked).*
6. **The sweep comes with the cat falling asleep, not with a working cat's timer** (Task 12: an optional `sweep` on `SleepEnv`, called by `SleepClock` right after `fall()`). The spec says "when the existing 10-minute sleep timer fires"; the timer also fires under a working cat, and sweeping then would remove a live subagent busy in a long, silent step. This is the Mac's behaviour (its sleep timer is armed for an idle cat only, and its sweep is `if asleep { app?.sweepKittens() }`), and **the owner chose it for both apps** (2026-10-08). A kitten whose stop never came under a parent that is still working goes when that parent stops. *Same on both; the Mac plan's own question 16 says the same.*
7. **A request a subagent asked for names its `agent_id`, so its kitten waits on an approval until the approval is answered or times out** (Task 12: `ApprovalInfo.agentId`, `State.subagentApprovalOver`, called by Allow, Deny and the 108 s timeout). The contract has the events (`permission`, `resolved`) but not where they come from. *Mac: send `resolved` from the paths that clear `pendingApproval` (the answer and the timeout), and test that a parent's own request leaves every kitten alone.*
8. **A subagent's own `Stop` is not the parent's** (Task 11, `kittenEventOf`): a `Stop`, `StopFailure` or `SessionEnd` that carries an `agent_id` ends no kittens. *Mac: the same guard in its event mapping (its notes already have it).*
9. **`pillRow` is a test-pinned equal of today's `otherTasks.slice(0, 4)` in One cat mode** (Task 8), so One cat's row and grid are provably the same list. *Mac: a one-line test for `CompactMiniGrid.others` and `AgentPillsView.displayTasks` does the same job.*
10. **The kitten bench with eight live kittens in `?dev`** (Task 13: 0.52 ms for the cats alone and 1.58 ms with the kittens, in headless Chromium). *Mac: its `--bench-kittens` is the same idea (2.35 to 2.47 ms, over the 2 ms budget the cats alone meet): the owner decides at Checkpoint 2 what the budget is with kittens.*
11. **The pill's name makes room for its kittens** (`.pill.has-kits .lbl`, Task 13) and a pill's kittens are three small ones and a "+N" at its trailing end. *Mac: `pillReserve` in its notes is the same.*
12. **A parent's `StopFailure` ends its kittens too** (Task 11, `kittenEventOf`): a turn that ended in an error leaves no kitten waiting for the cat to fall asleep. The contract names only `Stop` and `SessionEnd`; the Mac plan also takes `StopFailure` and `Interrupt` (the user stopped the turn). Windows has no `Interrupt` hook event, so there is nothing to map for it here. *Same on both for `StopFailure`; the Mac's `Interrupt` is a Mac-only extra.*
13. **The expanded pair has a gap now** (the owner's checkpoint on the prototype, merged in B-0): cat 2 moved from 105 to **114**, so the heads are 6 px apart (cat 1 Ø58 at 56, cat 2 Ø46 at 114 in Windows `PAIR.expanded`, 58 px between their centres, cat 2 8 px lower than cat 1), and the overview's text starts 9 px further right (147 px, was 138). The compact pair is Ø20 at 30 and 54 on both. *Mac: its plan derives its cats from the single cat (cat 1 at 50, cat 2 at 99, the text at 133 pt); cat 2 and the text move by the same +9 (108 and 142), so the spacing is the prototype's on both.*
14. **Bright eyes for the black coats** (Tasks 1 and 2; the owner's checkpoint on the prototype, merged in B-0): `smallEye` takes the coat's id as `cat`, and for Midnight, Oreo and Mocha (kittens too) the renderer fills the iris flat with the lighter of the coat's two iris colours, with no rim and a thinner pupil. A port passes the coat id (here `p.name`, which a kitten keeps). *Mac: `CatSmallEye` and the compact branch of `CatFace.drawEyes` do the same; the icons keep their ink eyes (the owner's answer), and since the Windows icon files are drawn by the Mac renderer, nothing changes in this plan for them.*

**Windows-only on purpose (platform extras):** the Rust twin of the Display clean-up and `settings::sanitized` keeping the three keys (the Mac stores UserDefaults keys); `CatBlock` and `withCatSettings` (one `cat` block holds both kinds of settings here, so a Cat settings row must not drop the Display keys: B-0's decision 1); **the agents' list in Settings is in a fixed order** (Claude Code, then the others by ID), because the Settings window is a separate webview that does not see the island's pills and recency is not in the contract's storage (the Mac's Settings can sort by the last event, and its plan does: most recent first, then the agents that are only stored); `window.__nm.hook` and `/?display=<mode>` in the dev server only, for the pictures (the Mac plan's fake events go through the socket); the headless zero-frame check of Task 14 as a proxy for 0 % CPU; `minibots.ts` joining the Node-checked files.

**What the Mac has that Windows does not need:** the per-coat collar style (the Mac already looks it up per coat: Task 6 is Windows catching up), and Codex kittens (the Mac has Codex's `SubagentStart`; Windows has no Codex hooks).

**Docs.** `CLAUDE.md` and `ARCHITECT.md` are edited in Task 14, in the Windows lines only: the Mac plan edits two other lines of the same files (the bullet before the `docs/superpowers/specs/` line of `CLAUDE.md`, and the `docs/CAT-CONTRACT.md` sentence of `ARCHITECT.md`), so a merge has no conflict. The Mac plan alone edits the root `README.md` (the roadmap row for B), `docs/INTEGRATIONS.md` and `.github/workflows/build.yml`; this plan touches none of them (its CI needs no change), so **the main session sets the roadmap row's final status when both plans have landed**. The Windows README (`windows/README.md`) is edited here only.

---

## Open questions for the owner

Each has the answer this plan assumed. **The owner approved them all as assumed on 2026-10-08, with the changes in "The owner's answers" below** (question 6 was settled at B-0's checkpoint; the sweep, the ticker's question word and the icons were answered). The ones marked **ask at Checkpoint N** are no longer asked.

1. **The agents' list in Settings is in a fixed order** (Claude Code, then the other agents by ID), not "most recent first" (spec §1). The Settings window cannot see the island's pills and the contract stores no recency. A real order needs a new stored field (or an event from the island to Settings), outside B-0's contract. *Ask at Checkpoint 1.* Assumed: fine, since an owner has two to four agents.
2. **Kittens and the second cat appear only in the compact island and the overview.** In the approval, question, chat, drop and note views the cards' text starts where the pair and the kittens would be, so those views keep their one cat and show no kittens (spec §2 and §3 say "wherever the parent is drawn" and give no rule for these views). *Ask at Checkpoint 2.* Assumed: yes.
3. **A click on cat 2 focuses its agent only in the overview.** In the compact island a click opens it, as ever. Assumed: yes (the spec's "like tapping a pill": pills are only on the overview and the compact grid ignores clicks).
4. **The greeting's pair** (spec §2, the prototype): the Main cat falls in as always, then cat 2 pops in beside it as the island folds. The stored pair's first coat may differ from the Main cat, in which case the real pair's cat 1 replaces the Main cat at the hand-over; by default both are Shrimpy. The settled cat moves 10 px left to where the pair's first cat sits (Parity 5). Assumed: as drawn.
5. **A new agent gets its coat in every mode, and it is stored.** A Gemini CLI that first appears in One cat mode keeps the coat it was given there, which is what A cat for each agent shows when the user switches later (spec §1: "the first time it appears, and keeps it"). Assumed: yes. The island saves the settings when it gives one; a change made in the Settings window in the same instant can be overwritten by that save (last write wins, as the sound toggle's save already does).
6. **The black coats' eyes.** Midnight, Oreo and Mocha had bright ink pills (a gold or green shape on a dark head); a gradient iris with a rim read darker at Ø12. The owner's checkpoint on the prototype made them glow: a flat fill of the lighter iris colour, no rim, a thinner pupil (the contract's `bright` and `brightPupil`, merged in B-0). Tasks 1 and 2 build exactly that, and Checkpoint 1 shows the sheet. Answered.
7. **Both badges of the compact pair are on the left of their cats** (the prototype's: `badgeSide` -1 for both), so cat 2's badge overlaps cat 1's right edge a little and stays fully visible (cat 2 is drawn on top). Assumed: as drawn.
8. **The frame budget with kittens.** The `?dev` bench measures eight live kittens on top of twelve small cats and a Ø66: about +1 ms in headless software drawing (0.52 → 1.58 ms). The spec's "under 2 ms" is the Mac's, in an optimised build. The real Windows numbers are the owner's to read from a real build. Assumed: acceptable, and measured again in a real build.
9. **Names.** The Settings list and the ticker's second line call the agents by the Mac's names (Claude Code, Gemini CLI, Antigravity, Codex, Cursor; any other tag capitalised); the pills on the island keep the label they have (`gemini`, `antigravity`, and `VS Code` for the Claude Code pill): no existing pill is restyled. Assumed: yes.
10. **No Codex kittens on Windows or Linux** (spec §3: no Codex hooks there). The plan wires nothing for Codex. Assumed: yes.
11. **`window.__nm` and `/?display=` exist in the dev server only** (`import.meta.env.DEV`), so a release build contains neither. They are how the checkpoint pictures are drawn without the Tauri app. Assumed: yes.

---

## The owner's answers (2026-10-08)

The owner approved this plan. Every open question above is **approved as assumed**, with these answers and changes (all of them are built into the tasks above):

1. **The sweep runs when the cat falls asleep,** not when the ten-minute timer fires under a working cat. It is the Mac's behaviour, and it never removes a live subagent busy in a long, silent step. Task 12 changed (`SleepClock` calls `sweep` right after `fall`; the test "falling asleep sweeps the kittens…" and a new one, "a working cat's timer firing sweeps nothing…"), and so did Review Focus 3, Parity 6 and the docs.
2. **The ticker's question word is "has a question"** (the prototype's `STATE_TXT`), not "asking you": one string in `views.ts` (Task 10) and its test.
3. **The icons keep their ink eyes.** The Windows icon files are drawn by the Mac renderer, so nothing in this plan changes for them.
4. **The black coats' bright eyes** and **the pair at 114** were decided at B-0's owner checkpoint and are merged (`e00ad3d`): Tasks 1 and 2 (the `cat` input, the flat bright eye, the sheet) and Tasks 4 and 10 (cat 2 at 114, the overview's text at 147 px) are written against them.
5. **Every other question** (the fixed order of the agents' list, kittens and cat 2 only in the compact island and the overview, a click on cat 2 only in the overview, the greeting's pair, a coat stored in every mode, the badge sides, the frame budget with kittens, the names, no Codex kittens, the dev-only fake events): approved as assumed.

---

## Self-review notes

- **Spec coverage.** §5 step 2, in its order. (1) Small eyes: the port with its own NaN test (Task 1), the compact branch of the renderer and `eyes: "ink"` (Task 2), the `?dev` contact sheet at 1× and 2× and the frame-time check before and after (Task 2, with the same-build bench), kittens' eight-live-kittens bench (Task 13). (2) Settings: the TypeScript and Rust ports replaying `display-cases.json` (Tasks 3 and 5), `settings.rs` carrying the three keys through every save, with a test that a save keeps them (Task 5), "Main cat", the Display picker with its live preview, the pair's pickers, "Cats for your agents" with colour, preview, picker, dice and Reset to defaults, built from the existing rows, the previews animating only while Settings is visible and focused (Task 7). (3) Per-agent coats: the ports (Tasks 3, 4), a coat for a new agent in `upsertExternalAgent` and once at load, a per-pill last-event time on every hook event, `castOf` (Task 8), every `BotEngine` taking its coat from the cast (Tasks 6 and 9), the collar per coat (Task 6), a test per call site (Task 9). (4) Two cats: compact two Ø20, expanded Ø58 and Ø46, the ticker moved right with a second line, a click on cat 2, the second agent out of the pills and the grid, the greeting's pair (Tasks 4, 8, 10). (5) Kittens: the port, the lists in `State`, the hook mapping and handlers, the sweep, every place with "+N" and "×N", the badge, the parent's collar and the happy blink, no new timers, a fake-event path, no Codex kittens (Tasks 11, 12, 13). (6) Docs (Task 14), CI path filter (no change needed, said in Task 14). Checkpoints 1, 2 and 3; `nm-reviewer-deep` at the end.
- **Placeholders.** None: every code step is a full file or a script whose replacements assert their anchors; every `Run:` has an `Expected:`, taken from the dry run below.
- **Type consistency.** The names are the contract's (`cleanDisplaySettings`, `agentCatFor`, `rerollAgentCat`, `assignAgentCats`, `castOf`, `kittenStep`, `kittenView`, `kittenSlots`, `kittenPlaceOf`, `usesSmallEye`, `smallEye`) with the apps' own (`CatBlock`, `cleanCatBlock`, `withCatSettings`, `State.cast`, `State.pillRow`, `State.giveCoats`, `State.kittenEvent`, `State.kittenView`, `State.sweepKittens`, `State.subagentApprovalOver`, `BotEngine.setCoat`, `collarStyle`, `catCfg.collars`, `createMiniBot(task, size, cat)`, `Greeting.start(cast)`, `kittenEventOf`, `KittenPool`, `drawKittens`, `PAIR`, `pairPlacement`, `agentLabel`, `pillColor`) used with one spelling.
- **Review Focus** lines 1 to 5 each have named tests above.
- **What this plan deliberately does not do:** Codex kittens (no hooks here); a recency-ordered agents' list; kittens or a second cat in the other expanded views; kitten names or labels; sounds for kittens and modes; the desktop cat and the wardrobe; a music source; the Windows `cargo check` and a release build (owed to CI); a real Claude Code run (the owner's check: that tool events inside a subagent carry `agent_id`).

---

## Dry run (2026-10-08)

The plan was run before it was handed over, in a throwaway clone, task by task while it was written; **then again after the owner's approval, on the merged B-0 base and with the owner's answers built in** (the affected tasks one by one, then the whole file from the top as the file you are reading), so that every block applies and every `Run:` line prints what its `Expected:` says. Nothing was committed or pushed (in the clone or in the main checkout), no NotchMeow app and no Tauri app was started, nothing was installed or downloaded, and no network was used.

**Set-up.** A fresh `git clone --local --shared` of this repository on `notchmeow/rebrand` at `e00ad3d` (B-0 is merged: **nothing of the B-0 plan was applied**), in the session scratchpad. The Setup block was run as written, with its own `cp -cR` of the main checkout's `windows/node_modules` into the clone as a real folder (nothing was installed). It printed `B-0 is merged (e00ad3d)`, the five fixture paths, `the contract is the one this plan was written against` (so the guard's `SMALL_EYE` with `bright` and `brightPupil`, and `KITTEN_PLACES`, match the merged core), and the baseline: `tsc exit 0`, `ℹ tests 166`, the AI and Claude Code checks, the contract's `# tests 231` and 14 fixture files, `image ok`. The Rust side ran in `notchmeow-linux-dev` through `windows/scripts/cargo-linux.sh … --target-dir /repo/windows/target/b-tauri` (the baseline first: the app's library 239 tests, the relay 23). Headless checks used `npx --no-install vite` on port 14581 and `playwright-cli`, then the server and the sessions were stopped.

**Method.** A small runner reads the plan's text, runs its `bash` blocks and its `Run:` lines in order in the clone (skipping the commit blocks), and prints each command's output next to the plan's `Expected:` line; a second script then compares every backticked literal of every `Expected:` line (`# tests 10`, `ℹ pass 269`, `tsc exit 0`, `test result: ok. 246 passed`, `not ok 5 - …`, `All AI UI checks passed`, `- Console: …`) with the output. The whole plan (Tasks 1 to 14, **96 blocks and runs, 0 failures, 230 literals compared, 0 missing**, about six minutes) was replayed from the Setup's result in one go; the files the plan's `git add` lines name are exactly the 53 files the run changed or created (none missing, none extra). The pictures were looked at with the same code: the small-eye sheet (the black coats glow), Settings in the three modes, the island in the three modes with kittens (the pair with its 6 px gap).

| Task | Agent | What the run printed (the plan's Expected) |
|---|---|---|
| 1 | light | `smalleye.test.mjs` 10 pass, red first (`ERR_MODULE_NOT_FOUND`); with `closeBelow` at 0.2, 2 fail; `check:cat` 176 |
| 2 | nm-implementer | renderer and eyes tests 16 (red: 6 fail first); with the compact branch drawn in ink again, 6 fail; `check:cat` 184; `?dev` readout before 2.80 ms (live cats) and 8.85 ms (sheet), after 3.30 and 9.96; the bench 0.52 ms ink, 0.54 ms coloured (+3 %; two other runs read +6 % and +40 %: noise); `eyes-1x.png`, `eyes-2x.png` |
| 3 | light | `display.test.mjs` 10 pass; with the prototype-name guard removed, 2 fail; `check:cat` 194 |
| 4 | light | `agentcat`, `cast`, `places` 18 pass (red: 3 fail files first); with the tie rule changed, 2 fail; `check:cat` 212 |
| 5 | nm-implementer | `cat_settings::` and `settings::` 17 pass before; the tests alone do not compile (39 errors); 24 pass after, no warning; workspace: library 246, relay 24, no warning |
| 6 | nm-implementer | `coat.test.mjs` 4 pass (red: 4 fail); with `setCoat` made to keep following, 1 fails; `check:cat` 216 |
| 7 | nm-implementer | `settings-ui` and `follow` 11 pass; with `withCatSettings` made to drop the keys, 1 fails; `check:cat` 222; `set-one.png`, `set-per.png`, `set-two.png` |
| 8 | nm-implementer | `state-cast.test.mjs` 6 pass; with the save-once check removed, 2 fail; `check:cat` 228 |
| 9 | nm-implementer | `sites.test.mjs` 5 pass (with `greeting` and `follow` 23); with a pill's `setCoat` removed, 2 fail; `check:cat` 233 |
| 10 | nm-implementer | `two-cats.test.mjs` 6 pass (with `greeting` 19); with the greeting's pair removed, 1 fails; `check:cat` 239; the four island pictures (`isl-one-…`, `isl-two-…`) |
| 11 | light | `kittens` and `subagents` 16 pass; with the cap at 9, 3 fail; `check:cat` 255 |
| 12 | nm-implementer | `kitten-wiring.test.mjs` 7 pass; with the sweep put back at every firing of the timer, 2 fail; `check:cat` 262 |
| 13 | nm-implementer | `kittendraw.test.mjs` 7 pass; with the parent's collar removed, 1 fails; `check:cat` 269; the bench with eight live kittens 0.50 → 1.44 ms; the six island pictures |
| 14 | light | docs applied; `tsc exit 0`, `check:cat` 269, `check:ai` and `check:claude`, the contract's 231 tests and 14 fixture files, the workspace (library 246, relay 24); a hidden island with two kittens asked for 0 frames in 3 s, an open one more than 60 in 2 s |

**What the owner's approval changed in the plan** (2026-10-08; each change was built into the tasks, and the affected steps, then the whole file, were replayed):

- **The base is the merged B-0** (`e00ad3d`): Setup (which the chip's prompt runs) checks `git merge-base --is-ancestor e00ad3d HEAD`, nothing of the B-0 plan is applied, and the contract's baseline is `# tests 231`.
- **Bright eyes for the black coats** (B-0's checkpoint): Task 1's `SMALL_EYE` copy and `smallEye` take the coat's id as `cat` and return `flat: true`, `rim: 0` and the thinner pupil for Midnight, Oreo and Mocha (three more tests: ten in the file); Task 2's renderer passes `p.name` and fills the iris flat with the lighter of the two colours (a test of its own: eight in the file); the Setup guard pins `bright` and `brightPupil`; the `?dev` sheet shows them with no change of its own.
- **The pair at 114** (B-0's checkpoint): `PAIR.expanded`'s cat 2 is at 114 (Task 4), the overview's text starts at 147 px (was 138, Task 10), and the places test pins the 6 px gap between the heads.
- **The sweep comes with the cat falling asleep** (the owner's answer): `SleepClock` calls `sweep` right after `fall` (Task 12; seven tests in `kitten-wiring.test.mjs`, one new: a working cat's timer firing sweeps nothing).
- **The ticker's question word is "has a question"** (Task 10, one string and its test).
- **The running `check:cat` totals moved** (+4 from Task 3 on, +5 from Task 12 on) and so did every Expected that quotes them.

**What the replay found on the way** (each was a defect in the text, found because a step failed, and is fixed):

- **A rim check that cannot tell for some coats.** Snow and Ginger have a liner colour equal to their ink colour, which the ink pills also stroke in, so "two more strokes in the liner colour" holds only for coats whose liner differs from their ink: the test picks those.
- **A greeting test that looked for an iris gradient** in each session cat's eyes: a black coat has none, so it looks for the lighter iris colour as a flat fill.
- **Task 12's proof step** (put the old rule back) fails two tests, not one: the working cat's and the blocked approval's.
- **Setup's `cp -cR` into a node_modules that already exists** copies the folder inside it: the dry-run clone starts without one and takes the plan's own copy (a real worktree has none either).

Earlier in the day, before the approval, the first replay had found these (all fixed in the text):

- **Task order.** The Settings screen calls `BotEngine.setCoat`, which the first draft added after it: `tsc` said so. The engine's coat and collar task is Task 6 now and the Settings screen Task 7, so Checkpoint 1 comes after both.
- **`minibots.ts` could not be loaded in Node** (extension-less imports), so the pills' and the grid's coats could not be tested. It imports with `.ts` now (Task 9) and joins the Node-checked files (Global Constraints).
- **Four older tests pinned lines these tasks move** and had to move with them, each by a named, exact edit: the renderer's flat-fill test (the coloured eye's iris is a gradient, so the test draws its cats with `eyes: "ink"`), `collar-wiring` (the collar line), `follow` (its source pins of the cat block and of the greeting) and `greeting` (the grid's `createMiniBot` call).
- **Rust.** `block_default` replaced `default_value` as the settings' default, which left two functions used only by tests: they carry `#[cfg(test)]`, so the build prints no warning. The tests are written first and do not compile (`block_default`, `clean_cat_block` and the others do not exist yet), which is the red step.
- **The fake-event path moved to Task 10.** The look step of the Two cats layout needs fake hook events and a display mode in the address, which the first draft added with the kittens' wiring in Task 12.
- **The label of a pill with kittens** was centred and ran under its mini cat; it is left-aligned from 36 px and stops before the kittens (`.pill.has-kits .lbl`).
- **Expected counts and text** were corrected to the real output many times: the running `check:cat` total after each task, the number of tests in the files a task adds, the failing counts of each "prove it bites" step (some mutations fail two tests, not one), the compile errors of Task 5's red step, and the number of pictures.
- **`playwright-cli` needs a short socket path.** Its socket directory must be under about 100 bytes, which the scratchpad's deep folder is not: the dry run set `PWTEST_SOCKETS_DIR=/tmp/pwb` for that reason alone. The owner's `$TMPDIR` is short and needs nothing.

**Not run, and owed.**

- **The Windows `cargo check` and a release build** (`npm run build` also builds the relay for the host): by rule not run here, and owed to the `windows-tests.yml` and `windows.yml` jobs on the owner's next push. This plan adds Rust only in `cat_settings.rs`, a field and a function in `settings.rs` and a relay test, all plain `serde_json` with no `cfg(windows)` line, which the Linux build in the container compiled and tested.
- **Any commit step.** Every `git add` and `git commit` block was skipped in the clone and has to be run by the executing session in its worktree; Task 14's `git status --short` and `git diff --stat notchmeow/rebrand -- …` lines assume the earlier tasks are committed.
- **The Tauri app itself.** No window of the real app was opened, so the Settings window's hidden-but-alive lifetime, the real focus events, the island with a real hook event from a real agent (and whether Claude Code puts `agent_id` on a subagent's tool events), the greeting's hand-over in the real window and the 0 % CPU rule in Task Manager are the checkpoints' lists for the owner, not something this run proved. The island was driven by the real hook handler in a headless browser from the Vite dev server, which proves the drawing, the layout and the wiring, and nothing about the shell around them.
- **The Mac.** Nothing under `NotchBuddy/` is touched; the Mac twin was read in full for the Parity section.

The clones, the snapshots and the shots folder were moved to the Trash afterwards (`trash`, never `rm -rf`).
