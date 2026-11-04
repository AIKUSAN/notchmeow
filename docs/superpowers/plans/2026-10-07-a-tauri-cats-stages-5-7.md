# A-tauri Cats, Stages 5 to 7 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Windows/Linux Tauri app gets the cat's **Settings section** (which of the 16 cats, its motion style, personality, collar and fur lines, saved in a `cat` block that cannot fail the settings file), the **collar** in three styles drawn from the agent colour at every size from Ø12 up, **searching** and **sleeping** (ten minutes, one timer, no polling), the **music bob**, then the **theme tokens** in place of the hard-coded colours (no pixel changed, proved), the **dead code** of the old character gone, and no Mochi name left in `windows/`.

**Architecture:** Everything stays a TypeScript port of `design/prototype/cat-core.js`, the tie-breaker, and is tested in plain Node against the fixtures in `tests/fixtures/cat/`, within 1e-9, with the clock and the randomness injected. The stored settings are cleaned by a TypeScript port (`src/cat/settings.ts`) and a Rust port (`src-tauri/src/cat_settings.rs`) of A-0d's `cleanCatSettings`, both replaying `settings-cases.json`; `Settings.cat` is a `serde_json::Value`, so one bad field cannot make `load` move the whole `settings.json` aside. Settings fill the engine's shared `catCfg`; an engine built without a preset follows the chosen character. The collar is `collarGeometry` plus a painter in the renderer's front pass. Sleeping is a pure clock (`island/sleep.ts`) with an injected timer. The theme swap is proved by a recorded drawing (every coat, the greeting, the glow) and a fingerprint of the `?dev` page that must be equal before and after.

**Tech Stack:** TypeScript 5 and Vite 6 (already in `windows/`), Canvas 2D, Node 22 (`node --test` reading the TypeScript source with `--experimental-strip-types`), Rust with `serde_json` only (no new crate), `playwright-cli` (headless Chromium, for the eye checks only). No new npm or cargo dependency.

**Spec:** `docs/superpowers/specs/2026-10-04-cats-in-app-design.md`: §3 "Wiring in the apps" (searching, sleeping, collar, music, removed dead code), §4 "Settings" (rows, defaults, persistence, frozen IDs), §5 "Theme tokens" and "Checks" (**icons are not in this plan**: branch `a-icons/c-peek` did them), "Stages" 5 to 7 and "Done means". The contract: `docs/CAT-CONTRACT.md` and `tests/fixtures/cat/` (`settings-cases.json`, `collar-cases.json`, `search-tools.json`, `sequence-cases.json`), and the approved shared plan `docs/superpowers/plans/2026-10-07-a0d-cat-settings-theme.md` (its "Interface for the app plans" is what this plan consumes: `cleanCatSettings` and its helpers, `settings-cases.json`, `shared/theme.json`, `windows/src/theme.generated.ts` and `.css`, `docs/THEME.md`). The stage 1 to 4 plan, `docs/superpowers/plans/2026-10-04-a-tauri-cats-stages-1-4.md`, is the format and the conventions; its "Next plan" section is where this plan came from. The Mac twin is `docs/superpowers/plans/2026-10-07-a-mac-cats-stages-5-7.md`; "Parity with macOS" below says what differs. Read the Windows cat code first (`windows/src/cat/`, `windows/src/island/`, `windows/src-tauri/src/settings.rs`) and `.claude/archive/owner-manual-checks.md` (the sections on the Windows cats, the Gemini and Antigravity port and the greeting).

**Base:** branch `a-tauri/stages-5-7`, in a git worktree, from `notchmeow/rebrand` **after A-0d is merged** (A-0d adds `cleanCatSettings`, `settings-cases.json`, `shared/theme.json` and the generated theme files; this plan reads them and edits none), with the stage 1 to 4 cats (`d5ec1a7`), the greeting's last beat (`a5f1473`), E3 (`3297071`) and the icons (`f704178`) in its history. Nothing is pushed.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec; a line marked "(plan decision)" is a choice this plan makes where the spec is silent, and is listed again under "Open questions for the owner".

- **Cat IDs are frozen, in this order:** `shrimpy`, `momo`, `ginger`, `midnight`, `latte`, `patches`, `blue`, `snow`, `oreo`, `mocha`, `silver`, `cloud`, `leo`, `button`, `puff`, `noodle`. An unknown stored ID falls back to `shrimpy`. **Collar style IDs are frozen:** `tag`, `band`, `kerchief` and `off`; an unknown stored style falls back to `off`. **Pill IDs are frozen** (`agent_gemini` and `agent_antigravity` keep their IDs; only their colour changes, by the owner's decision of 2026-10-06).
- **The Cat section's rows and defaults (spec §4):** Character (one of the 16, Shrimpy first and Momo second, each in a small live preview) `shrimpy`; Motion style Playful or Classic, Playful; This cat's motion, follow the global style or override it, Follow; Personality Balanced, Chill, Grumpy, Sweet, Hyper or Chatty, and moving any slider turns it into Custom, Balanced; the six trait sliders (Energy, Curiosity, Chattiness, Affection, Sass, Mischief), each 0 to 1, 0.5; Collar Band and tag, Band, Neckerchief or Off, **Off**; This cat's collar, follow or a style, Follow; Apply to every cat, copies this cat's motion, personality and collar to all 16; Fur lines, Off. **Each cat keeps its own motion override and personality.** "The preview animates only while Settings is visible."
- **Persistence (spec §4):** "Windows/Linux: a `cat` block in `settings.rs` with the same fields." Held as a `serde_json::Value` and cleaned in Rust, because a typed struct would fail the whole file for one bad field (A-0d). The TypeScript side cleans again before it uses a value. Nothing that did not go through the clean-up is stored, sent or used.
- **Unknown or hostile values never throw:** an unknown cat ID is Shrimpy, an unknown motion style plays Playful, a per-cat override that is not valid is `follow`, a trait outside 0 to 1 is held to it and a missing or non-number one is 0.5, fur lines are on only for a real boolean `true`, a collar colour that is not `#RRGGBB` draws no collar.
- **Collar (spec §3):** `task.color` becomes the collar, in the style the user picks, **drawn at every size from 12 px up in the renderer's front pass**, between the folded ears and the whiskers; readability floors in **device** pixels: band 3 px thick, tag 6 px across, neckerchief 7 px wide and 5 px deep. Small cats wear their agent's collar; the big cat wears the collar of the agent driving its current state and none when idle; the coat never changes; with the collar off each mini cat's pill still names its agent.
- **Searching (spec §3):** a PreToolUse or PostToolUse event whose tool name is in `search-tools.json` sets "searching"; the next non-search tool goes back to "working". **Sleeping:** an idle cat sleeps after 10 minutes with no agent event, never during an approval or a question; any hook event, hover or click wakes it, and Playful wakes with zoomies; a one-shot timer is reset on each event, with no polling. **Music:** the Apple Music dance bounce drives a head-bob, with the ears bouncing on the beat.
- **Theme tokens (spec §5):** only the character, branding and greeting colours change, and only the Windows sites of A-0d's inventory (`docs/THEME.md`, "Where each colour is hard-coded today"), with no pixel changed, proved by a before and after record. Existing views keep their colours, even where they use the same hex value. Nothing here edits `shared/theme.json`, `scripts/gen-theme.mjs` or the generated files.
- **Removed (dead code, spec §3), as it applies to Windows:** permanent emotes, `miniEye`, the `cup` eye and the mailbox morph; `engine.greet()` **stays** (it plays the contract's `hello` paw-wave emote). "No mochi/Mochi identifiers remain."
- **Tolerance and tie-breaker:** numbers compare within **1e-9** against the fixtures (12 significant digits). No pixel tests: the look is checked by eye and, for the theme swap, by a before and after record. **`cat-core.js` is the tie-breaker.** This plan never edits `design/prototype/cat-core.js`, `tests/fixtures/cat/`, `shared/theme.json` or `docs/CAT-CONTRACT.md`: a change there is the main session's. The cat code never calls `Math.random()` and reads a clock only as the late-bound default of a constructor.
- **Never restyle what ships.** The one exception is the colour of the Gemini CLI and Antigravity pills (Task 5). The Cat section is built from the Settings window's own row styles; the new CSS rules are new class names only. Never rename a pill ID or a contract string (`nm-hook`, `nm.sock`, `notchmeow-hook`, `nm_kind`, `nm_agent`). The relay and the Rust hooks are untouched: searching and sleeping change the front-end hook **handlers** only.
- **Files loaded by `npm run check:cat`** (everything under `windows/src/cat/` except `dev.ts` and `minibots.ts`, plus `core/layout.ts`, `core/sound.ts`, `core/state.ts`, `core/pills.ts`, `island/sleep.ts` and `upload/sequence.ts`, `upload/refusal.ts`) use erasable TypeScript only (no `enum`, no `namespace`, no constructor parameter properties), `import type` for types, and relative imports **with the `.ts` extension**, because Node reads the source as it is. Files outside that set keep the repo's extension-less imports.
- **No new dependency.** No `npm install` of anything, and **no change to `Cargo.toml` or `Cargo.lock`**. Rust runs **only** through `windows/scripts/cargo-linux.sh` (Docker Desktop running), with this plan's own target directory, because other worktrees share that script's Docker volume: `windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/a-tauri-57`. Never install a toolchain on the host.
- **Performance:** 0 % CPU while the island is hidden and Settings is closed. The island's frame loop already stops when it is hidden and nothing here restarts it; the Settings previews run only while their page is visible and focused; the sleep clock is one timer, never a poll.
- **Commits:** local only, never pushed. End every commit message with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; a task a light agent ran names `Claude Haiku 4.5` instead.
- **House rules for every session and every subagent brief (the SUBAGENT RULES block):**
  1. **Never launch, quit or replace any NotchMeow app, and never start the Tauri app** (`npm run tauri dev`, a built `notchmeow.exe`): the owner runs it. Serving the front end with `npx --no-install vite` and looking at it in the headless `playwright-cli` browser is allowed, and only that.
  2. **Install nothing and download nothing.** `npx --no-install` only; never `npm install`, `npm ci`, `npm run build`, `npm run dev` or `npm run tauri`.
  3. **Rust only through `windows/scripts/cargo-linux.sh`** with `--target-dir /repo/windows/target/a-tauri-57`. Check the image first (`docker image inspect notchmeow-linux-dev`): if it is missing or the daemon is down, stop and say so; the script would build it, which pulls a base image.
  4. **Use `trash`, never `rm -rf`;** unique scratch names; screenshots and the one-off scripts go in `${TMPDIR:-/tmp}/a-tauri-57-shots` and `…/a-tauri-57-check`, never in the repository. Stop every server you start (`kill $(lsof -ti tcp:14571)`) and every browser session (`playwright-cli close-all`).
  5. **Never push.** Commit only in a task's commit step. Never edit `CLAUDE.md` or `ARCHITECT.md` except where Task 17 says so.
  6. **If a command is denied by a permission prompt, stop and report it.** Do not look for a workaround.

## Review Focus

The spec says what the cats and Settings must do. It is silent on these inputs, and each would bite a person first. Each line names its test.

1. **A `cat` block in `settings.json` that is hand-edited, from an older build, or half written** (`5`, a trait of `"high"`, a personality that is not JSON, an unknown cat). Expected: the app starts, the rest of the file is kept and no `settings.json.bad-…` appears; the cat block is the defaults, or the valid parts of it, never NaN. Tests: Task 1 "hostile values never throw…" and "a real NaN…"; Task 2 `one_bad_field_in_the_cat_block_never_fails_the_settings_file`, `hostile_values_never_panic…`, `a_good_cat_block_survives_a_round_trip_and_what_the_webview_sends_is_cleaned`.
2. **The Settings window is created hidden at launch and never destroyed.** A preview loop that runs all the time costs CPU with Settings closed, and one that stops for good never comes back. Expected: the previews move only while the page is visible and focused, start again on show or focus, and a clock that stepped back or a long gap never gives a negative or huge frame time. Tests: Task 4 `loop.test.mjs` (all five tests); the owner's check at Checkpoint 1.
3. **A collar at the sizes and inputs a person meets:** Ø12 on a 1x and a 2x screen, a kitten, a head turned away, an agent colour that is not `#RRGGBB`. Expected: the band, tag and neckerchief never fall under their device-pixel floors, stay on the head, draw nothing for `off` or a bad colour, and never put a NaN on the canvas. Tests: Task 6 (the floors, "every coat, style, pose and size…", "a head of width 0, or a bad pixel ratio…"); Task 7 ("off, no collar and a colour that is not #RRGGBB draw nothing", "the readability floors reach the canvas", "without a dpr option…"); Task 9's eye check at 2x.
4. **The sleep clock under real traffic:** a burst of hook events, an approval or a question waiting for ten minutes, a pill that finished and went back to idle by itself, a timer that fires early, a hover while the island is hidden. Expected: one timer at a time, never asleep through an approval or a question, ten minutes counted from the last event, a hidden island costs one frame and nothing more. Tests: Task 11 (`sleep.test.mjs`: "every event starts the ten minutes again…", "it never sleeps through an approval or a question…", "a pill that finished…", "a timer that fires early…", "State: an idle cat shows as sleeping…").
5. **A colour edited to a value that is not the old one, in a swap that must change no pixel,** and a refusal that arrives after the cat has already begun to chew. Expected: the before and after record is equal; a refusal never makes the cat teleport back or lick while it gags. Tests: Task 13 (the recorded drawing, the `?dev` fingerprint and "prove the check bites"); Task 16 "a refusal after the cat began to chew clears the chew's lick…" and "a refusal that comes late holds the timeline where it is…".

---

## File Structure

All paths are under `windows/` unless they say otherwise.

| Path | Responsibility |
|---|---|
| `src/cat/settings.ts` | New. The stored cat settings: `cleanCatSettings`, `cleanPersonality`, the frozen words (`FOLLOW`, `MOTION_STYLES`, `COLLAR_STYLES`), `applyToAllCats`, `motionFor`, `collarFor`, `engineCfg`, `applyCatSettings` (fills the shared `catCfg`) and the seven `with…` edit helpers the Settings rows use. A port of A-0d's section of `cat-core.js`. |
| `src-tauri/src/cat_settings.rs` | New. The Rust port of the clean-up on a `serde_json::Value`, replayed from `settings-cases.json`. `settings.rs` holds `Settings.cat` as that value and cleans it on load and on everything the webview saves. |
| `src/cat/loop.ts` | New. `VisibleLoop`: a frame loop that runs only while its page is visible. |
| `src/settings/cat.ts`, `src/settings/main.ts`, `src/settings/settings.css` | The Cat section of the Settings window (new file, a mount, and new CSS classes only). |
| `src/cat/collar.ts` | New. `collarGeometry`, `COLLAR_MIN`, `COLLAR_PASS`, `bigCatCollar`: the collar's maths, from `collar-cases.json`. |
| `src/cat/renderer.ts` | The collar painter in the front pass (`DrawOptions.collar`, `dpr`), then the theme tokens (Task 13) and one eye shape fewer (Task 15). |
| `src/cat/engine.ts` | An engine without a preset follows the chosen cat; `collarColor`; the dance (`isDancing`, `dancingLevel`); `CATCH` (one table for the catch's numbers); the dead code of the old character gone. |
| `src/cat/dance.ts` | New. The music bob: `dancePose`, `applyDance`, `danceLevel`, `danceEars`, `shouldDance`. |
| `src/cat/base.ts` | The search tools (`SEARCH_TOOLS`, `isSearchTool`, `toolState`), the sleep rule (`SLEEP_AFTER_MS`, `sleepDelay`, `wakes`), and the state colours and glows from the theme. |
| `src/island/sleep.ts` | New. `SleepClock`: one timer, injected clock, timer and cat. |
| `src/core/pills.ts` | New. The agent pills' colours (the Mac's `PillCatalog` values) and `agentColor`. |
| `src/core/state.ts`, `src/island/island.ts`, `src/island/hooks.ts`, `src/cat/minibots.ts`, `src/upload/canvas.ts`, `src/cat/greeting.ts` | The wiring: `Settings.cat`, the chosen cat in every canvas, the collar colours, searching in the hook handlers, sleeping (`asleep`, `shownState`, `noteActivity`), the dance's seam (`musicPlaying`), the greeting's clock. |
| `src/upload/sequence.ts` | The old mailbox's fields go; a late refusal holds the timeline where it is. |
| `src/cat/dev.ts` | The `?dev` sheet: a Collar panel, a wake button, a dance button, the theme tokens. |
| `src/core/layout.ts` | Only if the owner agrees (Task 14): the island glow's seven literals read the theme. |
| `scripts/cat-tests/*.test.mjs` | One new file per area: `settings`, `settings-edit`, `loop`, `follow`, `pills`, `collar`, `collar-draw`, `collar-wiring`, `search`, `sleep`, `dance`, `deadcode`, `leftovers`, `names`; `fake-canvas.mjs` also records stroke colours and line widths; `engine.test.mjs` loses the names of the removed members. |
| `README.md`, `../CLAUDE.md`, `../ARCHITECT.md`, `../.github/workflows/windows-tests.yml` | The docs of what was added, the Windows lines of the two guides, and one CI path (the Windows checks read `PillCatalog.swift`). |

**Staged edits.** Most tasks edit files earlier tasks created. Every edit below is an exact find text (which must occur exactly once) and its replacement; the text is what the tree has after the tasks before it. Apply an edit with nothing else changed. If a find text occurs zero or two times, stop and report: the tree is not what the plan expects.

## Tasks and agents

CLAUDE.md: the lightest model that fits. Tasks 1, 5, 6, 10, 14 and 17 give every line of their code, and a run or two of a test: transcription, so `nm-implementer-light` (Haiku 4.5). The others are multi-file with their code given, and some run a browser, Docker or the island: `nm-implementer` (Sonnet 5.5, medium). Each task is then reviewed by `nm-reviewer`, and the whole branch by `nm-reviewer-deep` after Checkpoint 3. If a step's expected output differs and the cause is not obvious (a fixture replay that fails after a careful transcription, a Rust compile error), hand that task to `nm-implementer-deep`.

| # | Task | Agent | Review |
|---|---|---|---|
| 1 | The stored cat settings in TypeScript (replays `settings-cases.json`) | `nm-implementer-light` | `nm-reviewer` |
| 2 | The `cat` block in `settings.rs`, cleaned in Rust | `nm-implementer` | `nm-reviewer` |
| 3 | Settings feed the engine: the chosen cat, motion, personality and fur lines reach every canvas | `nm-implementer` | `nm-reviewer` |
| 4 | The Settings "Cat" section | `nm-implementer` | `nm-reviewer` |
| | **Checkpoint 1:** the owner looks at the Cat section | the executing session | |
| 5 | Gemini CLI and Antigravity get the Mac's pill colours | `nm-implementer-light` | `nm-reviewer` |
| 6 | The collar's geometry, from the contract | `nm-implementer-light` | `nm-reviewer` |
| 7 | The renderer paints the collar, in the front pass, from Ø12 up | `nm-implementer` | `nm-reviewer` |
| 8 | The collar reaches the cats, and its two Settings rows | `nm-implementer` | `nm-reviewer` |
| 9 | The `?dev` sheet wears collars | `nm-implementer` | `nm-reviewer` |
| | **Checkpoint 2:** the owner looks at the collars, and answers question 1 | the executing session | |
| 10 | Searching | `nm-implementer-light` | `nm-reviewer` |
| 11 | Sleeping | `nm-implementer` | `nm-reviewer` |
| 12 | The music bob | `nm-implementer` | `nm-reviewer` |
| 13 | The theme tokens replace the hard-coded colours, with no pixel changed | `nm-implementer` | `nm-reviewer` |
| 14 | The island's glow (only if the owner says yes at Checkpoint 2) | `nm-implementer-light` | `nm-reviewer` |
| 15 | Dead code goes | `nm-implementer` | `nm-reviewer` |
| 16 | The small things the reviews left for stage 7 | `nm-implementer` | `nm-reviewer` |
| 17 | The last Mochi names, the docs, CI and the final checks | `nm-implementer-light` | `nm-reviewer` |
| | **Checkpoint 3:** the owner signs off | the executing session | |
| Final | Whole-branch review | `nm-reviewer-deep` | none |

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). Ponytail never cuts what this plan or the spec asks for, nor tests, security or privacy rules.

**Controller brief** (what the main session sends the worktree session once its model is set):

> Run `docs/superpowers/plans/2026-10-07-a-tauri-cats-stages-5-7.md` with `superpowers:subagent-driven-development`, task by task, on branch `a-tauri/stages-5-7`. Do its Setup first. Dispatch each task to the agent the plan's "Tasks and agents" table names, then to `nm-reviewer`; fix what the review finds before the next task. Put the plan's SUBAGENT RULES block (Global Constraints) in every brief. Run Tasks 1 to 4, then stop and report to the main session for Checkpoint 1; after the owner's reply run Tasks 5 to 9 and stop for Checkpoint 2, where the owner also answers question 1 (the island's glow): run Task 14 only on a yes. Then run Tasks 10 to 13, 15 and 16 (and 14 if it was a yes), then 17, and stop for Checkpoint 3; after the owner's OK dispatch `nm-reviewer-deep` over the whole branch. No agent ever starts the Tauri app, launches or quits a NotchMeow build, installs anything or uses the network; Rust only through `windows/scripts/cargo-linux.sh` with `--target-dir /repo/windows/target/a-tauri-57`. Commit only as the plan's commit steps say, never push. Report: the commits; for `windows/`: `npx --no-install tsc --noEmit`, `npm run check:cat`, `npm run check:ai`, `npm run check:claude` and the `cargo test --workspace` counts; the output of `bash scripts/test-cat-contract.sh` and `bash scripts/test-theme.sh`; the equal before and after records of Task 13 and whether Task 14 ran; the screenshots of the three checkpoints; the Windows `cargo check` (owed to CI); and anything you could not settle.

## Execution

**One worktree chat session** runs the whole plan: branch `a-tauri/stages-5-7`, model **Sonnet 5.5 at high effort** (`ARCHITECT.md`: the app plans have many cross-task interfaces and platform APIs). It runs **after A-0d is merged** into `notchmeow/rebrand`, and in parallel with the Mac's stages 5 to 7 plan, which has its own worktree. Nothing is pushed. The session never starts the Tauri app: the owner's manual checks are listed at each checkpoint.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run `git switch -c a-tauri/stages-5-7 notchmeow/rebrand`, then the Setup block of `docs/superpowers/plans/2026-10-07-a-tauri-cats-stages-5-7.md`. If any check in it fails, say so and stop. Read `CLAUDE.md`, `ARCHITECT.md`, `windows/README.md`, that plan and `docs/superpowers/specs/2026-10-04-cats-in-app-design.md`. Reply "ready" and stop. Do not start any task.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief above as the next message.

Before any follow-up turn, the main session checks the session is still on its configured model and effort.

## Setup (the controller, once)

- [ ] Put the session's worktree on the plan's branch, check that its base has what the plan reads, and copy the main checkout's front-end packages. This plan adds no package, so nothing is downloaded: no `npm install` or `npm ci`. `cp -c` makes an APFS clone, which is instant and takes no extra disk space. It must be a real folder, not a symlink, because `windows/.gitignore` ignores `node_modules/` only as a folder.

```bash
git status                                   # must be clean
git switch -c a-tauri/stages-5-7 notchmeow/rebrand
git log --oneline -3
for c in 947e2d3 d5ec1a7 a5f1473 3297071 f704178; do git merge-base --is-ancestor $c HEAD || echo "MISSING $c"; done
ls tests/fixtures/cat/settings-cases.json shared/theme.json scripts/gen-theme.mjs windows/src/theme.generated.ts windows/src/theme.generated.css
git ls-files docs/superpowers/plans/2026-10-07-a-tauri-cats-stages-5-7.md   # this plan's path: it is tracked, so the worktree has it
cp -cR "/path/to/notchmeow/windows/node_modules" windows/node_modules
git status --short                           # still empty: the copy is ignored
cd windows && node --version                 # 22.6 or newer
```

The `for` loop must print nothing (a line `MISSING …` means the base is older than the plan expects: stop); `ls` must list all five paths (if one is missing A-0d is not merged: stop); `git ls-files` must print the plan's path (if it prints nothing, the plan is not committed on this branch: stop).

- [ ] Check that the starting point is green.

```bash
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"
npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1
(cd .. && bash scripts/test-cat-contract.sh 2>&1 | tail -1 && bash scripts/test-theme.sh 2>&1 | tail -1)
docker image inspect notchmeow-linux-dev >/dev/null && echo "image ok"
```

Expected: `tsc exit 0` with no type error before it, `ℹ tests 89`, `ℹ pass 89`, `ℹ fail 0`, `All AI UI checks passed`, `All Claude Code UI checks passed`, `✓ two generator runs write identical bytes`, `✓ 3 theme files match shared/theme.json` and `image ok`. If `image ok` does not print, do the TypeScript tasks only and report it (Task 2 needs the image).

## How to run this plan

**Blocks.** A code step is one of: a block titled `create` (the file's exact content), a pair of blocks titled `old` and `new` (the find text, which occurs exactly once in the file, and its replacement), or a `bash` block (run it as it is, from the repository root). Never type a block from memory and never "improve" one. Every `Run:` line is run from the repository root (the worktree's top folder); `Expected:` says what it prints. A `Run:` line that ends in `; cd ..` ran from `windows/` and came back.

**Red first.** Each task writes its tests, runs them to see them fail, writes the code, and runs them to see them pass. A step that proves a check can bite changes a line, runs the check, and puts the line back: it is never committed.

**Pixels.** There are no pixel tests. The look is checked by eye in a headless browser (`playwright-cli`, with Vite alone, never the Tauri app), and the theme swap is checked by a before and after record. Keep every screenshot in `${TMPDIR:-/tmp}/a-tauri-57-shots`, and say what you saw.

**The owner's checkpoints** are marked `Checkpoint N`: the session stops there, sends the owner the pictures and the list, and waits. Never start the next stage before the owner's OK.

---

# Stage 5: the Settings "Cat" section and persistence

### Task 1: The stored cat settings in TypeScript

**Agent:** `nm-implementer-light`.

**Files:**
- Create: `windows/src/cat/settings.ts`
- Create: `windows/scripts/cat-tests/settings.test.mjs`

**Interfaces:**
- Consumes (A-0d, merged): `tests/fixtures/cat/settings-cases.json` (`ids`, `follow`, `motionStyles`, `collarStyles`, `defaults`, `cases`, `personalities`, `applyAll`, `derived`), and `design/prototype/cat-core.js` "Stored settings", which decides. From this app: `CAT_IDS` (`presets.ts`), `PERSONAS`, `TRAIT_KEYS`, `normPers`, `personaNamed`, `slide` (`personality.ts`), `own`, `rng` (`base.ts`).
- Produces `src/cat/settings.ts`, with A-0d's names exactly: `FOLLOW`, `MOTION_STYLES`, `motionStyleOf(v)`, `motionOverrideOf(v)`, `collarOverrideOf(v)`, `catIdOf(v)`, `cleanPersonality(raw)`, `cleanCatSettings(raw)`, `defaultCatSettings()`, `applyToAllCats(settings, id)`, `motionFor(settings, id)`, `collarFor(settings, id)`, `engineCfg(settings)`. It adds the A-0b names `COLLAR_STYLES` (`tag`, `band`, `kerchief`, `off`, frozen, in that order) and `collarStyleOf(v)` (an unknown style is `off`), because the clean-up needs them and stage 6 imports them from here. The types `CatSettings`, `CatEntry`, `MotionStyle`, `CollarStyle`, `EngineCfg` and `LiveCfg`. One function that is not in the contract: `applyCatSettings(cfg, settings)` copies a clean `engineCfg`, the character, the collar of that character and the fur-lines switch into the shared `catCfg` (Task 3), in place, because engines hold a reference to it.

- [ ] **Step 1: Write the failing tests**

```js title="windows/scripts/cat-tests/settings.test.mjs" create
import test from "node:test";
import assert from "node:assert/strict";
import { rng } from "../../src/cat/base.ts";
import { PERSONAS, TRAIT_KEYS, personaNamed, slide } from "../../src/cat/personality.ts";
import { CAT_IDS } from "../../src/cat/presets.ts";
import * as S from "../../src/cat/settings.ts";
import { load, same } from "./util.mjs";

// The stored settings, replayed from tests/fixtures/cat/settings-cases.json (A-0d), and the cases a JSON file cannot hold.
const fx = load("settings-cases.json");
const IDS = [...CAT_IDS];
const BALANCED = { preset: "balanced", energy: 0.5, curiosity: 0.5, chatty: 0.5, affection: 0.5, sass: 0.5, mischief: 0.5 };
const deepFreeze = (v) => { if (v && typeof v === "object") { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };

test("the frozen words and the cat IDs are the fixture's", () => {
  assert.deepEqual(IDS, fx.ids);
  assert.equal(S.FOLLOW, fx.follow);
  assert.deepEqual([...S.MOTION_STYLES], fx.motionStyles);
  assert.deepEqual([...S.COLLAR_STYLES], fx.collarStyles);
  assert.deepEqual(IDS.slice(0, 2), ["shrimpy", "momo"]);
  assert.ok(!S.MOTION_STYLES.includes("follow") && !S.COLLAR_STYLES.includes("follow"), "follow is an override, never a style");
});

test("a fresh install is the fixture's: Shrimpy, Playful, collar off, no fur lines, 16 cats that follow the globals and are Balanced", () => {
  same(S.defaultCatSettings(), fx.defaults, "defaults");
  const d = S.defaultCatSettings();
  assert.deepEqual([d.character, d.motionStyle, d.collar, d.furLines], ["shrimpy", "playful", "off", false]);
  assert.deepEqual(Object.keys(d.cats), IDS);
  for (const id of IDS) assert.deepEqual(d.cats[id], { motion: "follow", collar: "follow", personality: BALANCED }, id);
  assert.notEqual(S.defaultCatSettings().cats.momo, d.cats.momo, "every call gives fresh objects");
});

test("cleanCatSettings replays every case of the fixture: bad JSON, wrong types, unknown IDs, a valid value", () => {
  assert.ok(fx.cases.length >= 37);
  for (const c of fx.cases) same(S.cleanCatSettings(c.raw), c.out, c.name);
});

test("cleanPersonality replays every case of the fixture: objects and JSON text, presets, Custom, out-of-range traits", () => {
  assert.ok(fx.personalities.length >= 47);
  for (const c of fx.personalities) same(S.cleanPersonality(c.raw), c.out, c.name);
});

test("applyToAllCats, motionFor, collarFor and engineCfg replay the fixture", () => {
  for (const c of fx.applyAll) same(S.applyToAllCats(c.settings, c.from), c.out, c.name);
  for (const c of fx.derived) {
    same(S.engineCfg(c.settings), c.engineCfg, `${c.name}: engineCfg`);
    assert.deepEqual(IDS.map((id) => S.motionFor(c.settings, id)), c.motionFor, `${c.name}: motionFor`);
    assert.deepEqual(IDS.map((id) => S.collarFor(c.settings, id)), c.collarFor, `${c.name}: collarFor`);
  }
});

test("a real NaN, an infinity or minus zero in a trait counts as 0.5, 0 or 1, never as NaN (a JSON file cannot hold them: the fixture's port note)", () => {
  const wild = S.cleanPersonality({ energy: NaN, curiosity: Infinity, chatty: -Infinity, affection: 7, sass: -2, mischief: -0 });
  assert.deepEqual([wild.energy, wild.curiosity, wild.chatty, wild.affection, wild.sass, wild.mischief], [0.5, 0.5, 0.5, 1, 0, 0]);
  assert.equal(Object.is(wild.mischief, -0), false, "minus zero is stored as 0");
  assert.equal(wild.preset, "custom");
  const out = S.cleanCatSettings({ cats: { momo: { personality: { energy: NaN, sass: NaN } } } });
  for (const v of TRAIT_KEYS.map((k) => out.cats.momo.personality[k])) assert.ok(Number.isFinite(v));
});

test("Custom is the word custom with the six traits: a slider move stays Custom, even back on a preset's numbers", () => {
  const moved = slide(personaNamed("chill"), "sass", 0.9);
  assert.equal(moved.preset, "custom");
  assert.deepEqual(S.cleanPersonality(moved), moved);
  assert.deepEqual(S.cleanPersonality(JSON.stringify(moved)), moved, "the Mac stores JSON text; so can a file");
  const back = slide(personaNamed("chill"), "energy", 0.12);
  assert.equal(S.cleanPersonality(back).preset, "custom");
  assert.ok(!("custom" in PERSONAS), "custom is not one of the six presets");
  for (const name of Object.keys(PERSONAS)) assert.deepEqual(S.cleanPersonality(personaNamed(name)), personaNamed(name), name);
});

test("a stored word that no longer exists is the neutral one: Shrimpy, Playful, Off for the globals, follow for a cat's own override", () => {
  for (const bad of ["tiger", "Momo", " momo", "", "siamese", "__proto__", "constructor", "toString", null, undefined, 7, true, {}, ["momo"]]) assert.equal(S.catIdOf(bad), "shrimpy", String(bad));
  for (const bad of ["follow", "Classic", "bogus", "", null, 7, ["classic"]]) assert.equal(S.motionStyleOf(bad), "playful", String(bad));
  for (const bad of ["follow", "scarf", "Tag", "", null, 7, ["band"]]) assert.equal(S.collarStyleOf(bad), "off", String(bad));
  for (const bad of ["Classic", "bogus", "", null, 7, {}]) assert.equal(S.motionOverrideOf(bad), "follow", String(bad));
  for (const bad of ["scarf", "Tag", "", null, 7, {}]) assert.equal(S.collarOverrideOf(bad), "follow", String(bad));
  assert.equal(S.collarOverrideOf("off"), "off", "off is a real override");
  assert.equal(S.motionOverrideOf("follow"), "follow");
});

test("fur lines are on only for a real boolean true", () => {
  assert.equal(S.cleanCatSettings({ furLines: true }).furLines, true);
  for (const bad of [false, 1, 0, "true", "yes", null, [true], { value: true }, 7]) assert.equal(S.cleanCatSettings({ furLines: bad }).furLines, false, JSON.stringify(bad));
});

test("hostile values never throw: 600 random settings come out valid, cleaning them again changes nothing, and the input is left alone", () => {
  const r = rng(2026), pool = ["momo", "tiger", "classic", "playful", "follow", "off", "band", "tag", "kerchief", "", " ", "chill", "custom", "{", "{\"energy\":2}",
    "{\"preset\":\"sweet\",\"affection\":1,\"energy\":0.5,\"curiosity\":0.55,\"chatty\":0.55,\"sass\":0.1,\"mischief\":0.3}", "__proto__", "constructor", null, true, false, 0, 1, -1, 0.5, 7, 1e300, NaN, Infinity,
    [], [1], {}, { energy: 9 }, { preset: "hyper" }];
  const pick = () => pool[Math.floor(r() * pool.length)];
  const entry = () => ({ motion: pick(), collar: pick(), personality: pick() });
  const valid = (s) => IDS.includes(s.character) && S.MOTION_STYLES.includes(s.motionStyle) && S.COLLAR_STYLES.includes(s.collar) && typeof s.furLines === "boolean"
    && JSON.stringify(Object.keys(s.cats)) === JSON.stringify(IDS)
    && IDS.every((id) => ["follow", ...S.MOTION_STYLES].includes(s.cats[id].motion) && ["follow", ...S.COLLAR_STYLES].includes(s.cats[id].collar)
      && TRAIT_KEYS.every((k) => Number.isFinite(s.cats[id].personality[k]) && s.cats[id].personality[k] >= 0 && s.cats[id].personality[k] <= 1)
      && (s.cats[id].personality.preset === "custom" || Object.hasOwn(PERSONAS, s.cats[id].personality.preset)));
  for (let i = 0; i < 600; i++) {
    const raw = { character: pick(), motionStyle: pick(), collar: pick(), furLines: pick(), cats: r() < 0.1 ? pick() : Object.fromEntries(IDS.filter(() => r() < 0.5).map((id) => [id, r() < 0.1 ? pick() : entry()])) };
    const out = S.cleanCatSettings(deepFreeze(structuredClone(raw)));
    assert.ok(valid(out), JSON.stringify(raw));
    assert.deepEqual(S.cleanCatSettings(out), out);
    assert.ok(valid(S.applyToAllCats(raw, pick())));
    assert.doesNotThrow(() => S.engineCfg(raw));
  }
  const evil = JSON.parse('{"__proto__":{"motion":"classic"},"constructor":{"prototype":{"x":1}},"cats":{"__proto__":{"motion":"classic"},"constructor":{"motion":"classic"}}}');
  const out = S.cleanCatSettings(evil);
  assert.equal(Object.getPrototypeOf(out.cats), Object.prototype);
  assert.deepEqual(Object.keys(out.cats), IDS);
  assert.equal(({}).motion, undefined, "nothing leaked into Object.prototype");
});

test("applyToAllCats copies one cat's motion override, collar override and personality to all 16, and nothing else", () => {
  const s = S.cleanCatSettings({ character: "momo", motionStyle: "classic", collar: "band", furLines: true, cats: { ginger: { motion: "playful", collar: "off", personality: personaNamed("hyper") } } });
  const before = JSON.stringify(s);
  const out = S.applyToAllCats(s, "ginger");
  assert.equal(JSON.stringify(s), before, "the input is not touched");
  assert.deepEqual([out.character, out.motionStyle, out.collar, out.furLines], ["momo", "classic", "band", true]);
  for (const id of IDS) assert.deepEqual(out.cats[id], { motion: "playful", collar: "off", personality: personaNamed("hyper") }, id);
  out.cats.momo.personality.energy = 0.01;
  assert.equal(out.cats.ginger.personality.energy, 1, "no two cats share one personality object");
  assert.equal(S.applyToAllCats(s, "shrimpy").cats.noodle.motion, "follow", "follow is copied as follow");
  assert.deepEqual(S.applyToAllCats(s, "tiger"), S.applyToAllCats(s, "shrimpy"), "an unknown cat is Shrimpy");
});

test("applyCatSettings fills the shared config in place: style, overrides, personalities, the character, its collar and the fur lines", () => {
  const cfg = { motion: "playful", override: {}, pers: {}, zoomAfter: 300000 };
  const keep = cfg;
  const raw = { character: "momo", motionStyle: "classic", collar: "band", furLines: true, cats: { momo: { motion: "playful", collar: "kerchief", personality: personaNamed("sweet") }, ginger: { collar: "tag" } } };
  const s = S.applyCatSettings(cfg, raw);
  assert.equal(cfg, keep, "the same object: engines hold a reference to it");
  assert.equal(cfg.zoomAfter, 300000, "what Settings does not own stays");
  assert.deepEqual([cfg.motion, cfg.character, cfg.collar, cfg.fur], ["classic", "momo", "kerchief", true]);
  assert.deepEqual(cfg.override, { momo: "playful" });
  assert.deepEqual(Object.keys(cfg.pers), IDS);
  assert.deepEqual(cfg.pers.momo, personaNamed("sweet"));
  assert.deepEqual(s, S.cleanCatSettings(raw), "it returns the clean settings");
  S.applyCatSettings(cfg, "junk");
  assert.deepEqual([cfg.motion, cfg.character, cfg.collar, cfg.fur, cfg.override], ["playful", "shrimpy", "off", false, {}], "junk is the defaults");
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/settings.test.mjs 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|^# (pass|fail)"; cd ..`
Expected: `ERR_MODULE_NOT_FOUND` for `src/cat/settings.ts` and `# fail 1`.

- [ ] **Step 3: Write the module**

```ts title="windows/src/cat/settings.ts" create
// The Cat section's stored settings: what Settings → Cat saves, cleaned. A port of "Stored settings" in design/prototype/cat-core.js (the
// tie-breaker; fixture tests/fixtures/cat/settings-cases.json, docs/CAT-CONTRACT.md "Stored settings"). A settings file can be hand-edited,
// copied from an older build or half written, so everything that reads one passes it through cleanCatSettings first and uses only the result.
// Raw in, clean out, never a throw. The shape is the same raw or clean, and the Rust side (cat_settings.rs) holds the same value:
//   { character, motionStyle, collar, furLines, cats: { <catId>: { motion, collar, personality } } }   with all 16 cat IDs once clean.
// Imports only base.ts, presets.ts and personality.ts, so the plain-Node checks (npm run check:cat) can load it.

import { own } from "./base.ts";
import { CAT_IDS } from "./presets.ts";
import { PERSONAS, TRAIT_KEYS, normPers, personaNamed } from "./personality.ts";
import type { Persona, Traits } from "./types.ts";

/** "No override: use the global setting." Stored as this word. It is not a motion style and not a collar style. */
export const FOLLOW = "follow";
export type Follow = typeof FOLLOW;
/** The motion styles, in the order Settings lists them. Playful is the default; an unknown stored style plays Playful. */
export const MOTION_STYLES = ["playful", "classic"] as const;
export type MotionStyle = (typeof MOTION_STYLES)[number];
/** The collar styles, frozen contract values in this order (A-0b): band and tag, band, neckerchief, and off, the default. */
export const COLLAR_STYLES = ["tag", "band", "kerchief", "off"] as const;
export type CollarStyle = (typeof COLLAR_STYLES)[number];

const isMotion = (v: unknown): v is MotionStyle => (MOTION_STYLES as readonly unknown[]).includes(v);
const isCollar = (v: unknown): v is CollarStyle => (COLLAR_STYLES as readonly unknown[]).includes(v);
const isPlain = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);

/** A stored global motion style to a style; anything else (`follow` included) is Playful. */
export const motionStyleOf = (v: unknown): MotionStyle => (isMotion(v) ? v : "playful");
/** A stored global collar style to a style; anything else (`follow` included) is `off`. */
export const collarStyleOf = (v: unknown): CollarStyle => (isCollar(v) ? v : "off");
/** A cat's own motion: `follow` or a style. Anything else is `follow`: no valid override. */
export const motionOverrideOf = (v: unknown): Follow | MotionStyle => (isMotion(v) ? v : FOLLOW);
/** A cat's own collar: `follow` or one of the four styles (`off` is an override like any other). Anything else is `follow`. */
export const collarOverrideOf = (v: unknown): Follow | CollarStyle => (isCollar(v) ? v : FOLLOW);
/** A stored cat ID to a cat ID. An unknown ID, or anything that is not a string, is Shrimpy. */
export const catIdOf = (v: unknown): string => ((CAT_IDS as readonly unknown[]).includes(v) ? (v as string) : "shrimpy");

const sameTraits = (a: Traits, b: Traits) => TRAIT_KEYS.every((k) => Math.abs(a[k] - b[k]) <= 1e-9);

/**
 * A stored personality to a clean one: {preset, energy, curiosity, chatty, affection, sass, mischief}. It may be an object, or the JSON text of
 * one. Text that is not JSON, and JSON that is not an object, give Balanced. The traits go through normPers (held to 0…1, missing or not a
 * number is 0.5). `custom` is how a hand-tuned personality is stored: the preset is kept only when it names one of the six AND the traits are
 * still that preset's (within 1e-9); anything else, a missing or unknown name included, is `custom`.
 */
export function cleanPersonality(raw: unknown): Persona {
  let v = raw;
  if (typeof v === "string") {
    try { v = JSON.parse(v); } catch { return personaNamed("balanced"); }
  }
  if (!isPlain(v)) return personaNamed("balanced");
  const o = v, traits = normPers(o), name = o.preset;
  const named = typeof name === "string" && own(PERSONAS, name) ? name : null;
  return { preset: named && sameTraits(traits, PERSONAS[named]) ? named : "custom", ...traits };
}

export interface CatEntry { motion: Follow | MotionStyle; collar: Follow | CollarStyle; personality: Persona }
export interface CatSettings {
  character: string;
  motionStyle: MotionStyle;
  collar: CollarStyle;
  furLines: boolean;
  cats: Record<string, CatEntry>;
}

/** Everything Settings saves, cleaned. Never throws; unknown keys are dropped; the result always holds all 16 cats, in CAT_IDS order. */
export function cleanCatSettings(raw: unknown): CatSettings {
  const r: Record<string, unknown> = isPlain(raw) ? raw : {};
  const cats: Record<string, unknown> = isPlain(r.cats) ? r.cats : {};
  const out: CatSettings = { character: catIdOf(r.character), motionStyle: motionStyleOf(r.motionStyle), collar: collarStyleOf(r.collar), furLines: r.furLines === true, cats: {} };
  for (const id of CAT_IDS) {
    const c = own(cats, id) && isPlain(cats[id]) ? cats[id] : {};
    out.cats[id] = { motion: motionOverrideOf(c.motion), collar: collarOverrideOf(c.collar), personality: cleanPersonality(c.personality) };
  }
  return out;
}

/** What a fresh install holds: Shrimpy, Playful, collar off, no fur lines, every cat following the globals with a Balanced personality. */
export const defaultCatSettings = (): CatSettings => cleanCatSettings(null);

/** "Apply to every cat": every cat gets the motion override, collar override and personality of cat `id` (an unknown ID is Shrimpy). The character and the global settings stay. */
export function applyToAllCats(settings: unknown, id: unknown): CatSettings {
  const s = cleanCatSettings(settings), from = s.cats[catIdOf(id)], out: CatSettings = { ...s, cats: {} };
  for (const c of CAT_IDS) out.cats[c] = { motion: from.motion, collar: from.collar, personality: { ...from.personality } };
  return out;
}

/** The motion style a cat plays: its own override, else the global style. */
export function motionFor(settings: unknown, id: unknown): MotionStyle {
  const s = cleanCatSettings(settings), m = s.cats[catIdOf(id)].motion;
  return m === FOLLOW ? s.motionStyle : m;
}

/** The collar style a cat wears (when it has a colour to wear): its own override, else the global style. */
export function collarFor(settings: unknown, id: unknown): CollarStyle {
  const s = cleanCatSettings(settings), c = s.cats[catIdOf(id)].collar;
  return c === FOLLOW ? s.collar : c;
}

export interface EngineCfg { motion: MotionStyle; override: Record<string, MotionStyle>; pers: Record<string, Persona> }

/** The shared settings an engine reads (the `cfg` of BotEngine, without zoomAfter): the global style, an override for each cat that has one, every cat's personality. */
export function engineCfg(settings: unknown): EngineCfg {
  const s = cleanCatSettings(settings), override: Record<string, MotionStyle> = {}, pers: Record<string, Persona> = {};
  for (const id of CAT_IDS) {
    const c = s.cats[id];
    if (c.motion !== FOLLOW) override[id] = c.motion;
    pers[id] = c.personality;
  }
  return { motion: s.motionStyle, override, pers };
}

/** The part of the engine's shared `catCfg` that Settings fills (engine.ts declares the rest). */
export interface LiveCfg {
  motion: string;
  override: Record<string, string | null | undefined>;
  pers: Record<string, Persona | undefined>;
  /** The cat the island, the pills, the drop view and the greeting wear: a cat ID. */
  character?: string;
  /** The collar that cat wears: its own style, else the global one. */
  collar?: string;
  /** Optional fur strands on the big cat. */
  fur?: boolean;
}

/** Puts clean settings into the shared config, in place: engines hold a reference to it. Returns the clean settings. */
export function applyCatSettings(cfg: LiveCfg, settings: unknown): CatSettings {
  const s = cleanCatSettings(settings), e = engineCfg(s);
  cfg.motion = e.motion;
  cfg.override = e.override;
  cfg.pers = e.pers;
  cfg.character = s.character;
  cfg.collar = collarFor(s, s.character);
  cfg.fur = s.furLines;
  return s;
}
```

- [ ] **Step 4: Run the tests and the type check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/settings.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; npx --no-install tsc --noEmit; echo "tsc exit $?"; cd ..`
Expected: `# tests 12`, `# pass 12`, `# fail 0`, then `tsc exit 0`.

- [ ] **Step 5: Prove the strict-boolean check bites (not committed)**

```bash
python3 - <<'PY'
p = 'windows/src/cat/settings.ts'
s = open(p, encoding='utf-8').read()
was = 'furLines: r.furLines === true'
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, 'furLines: !!r.furLines'))
PY
(cd windows && node --experimental-strip-types --test scripts/cat-tests/settings.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)")
python3 - <<'PY'
p = 'windows/src/cat/settings.ts'
s = open(p, encoding='utf-8').read()
was = 'furLines: !!r.furLines'
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, 'furLines: r.furLines === true'))
PY
(cd windows && node --experimental-strip-types --test scripts/cat-tests/settings.test.mjs 2>&1 | grep -E "^# (pass|fail)")
```

Expected: first run lists `not ok 3 - cleanCatSettings replays every case of the fixture…` and `not ok 9 - fur lines are on only for a real boolean true`, then `# pass 10` and `# fail 2`; after putting the line back, `# pass 12` and `# fail 0`.

- [ ] **Step 6: Run the whole cat check**

Run: `cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `ℹ tests 101`, `ℹ pass 101`, `ℹ fail 0` (the 89 from before, and the 12 new ones).

- [ ] **Step 7: Commit**

Run: `git status --short`
Expected: `?? windows/scripts/cat-tests/settings.test.mjs` and `?? windows/src/cat/settings.ts`, and nothing else. (In a dry-run clone, A-0d's uncommitted files and the `windows/node_modules` link are listed too: never `git add` them.)

```bash
git add windows/src/cat/settings.ts windows/scripts/cat-tests/settings.test.mjs
git commit -m "feat(cat): the stored cat settings are cleaned in TypeScript, as cat-core.js and the fixture say

cleanCatSettings, cleanPersonality, applyToAllCats, motionFor, collarFor and engineCfg are replayed from
settings-cases.json. A real NaN in a trait counts as 0.5. applyCatSettings fills the shared catCfg in place.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 2: The `cat` block in `settings.rs`, cleaned in Rust

**Agent:** `nm-implementer`.

**Files:**
- Create: `windows/src-tauri/src/cat_settings.rs`
- Modify: `windows/src-tauri/src/lib.rs` (one `mod` line), `windows/src-tauri/src/settings.rs` (the `cat` field, its default, `sanitized`, tests)

**Interfaces:**
- Consumes: `tests/fixtures/cat/settings-cases.json` and `personality-cases.json` (read by the tests through `CARGO_MANIFEST_DIR/../../tests/fixtures/cat/`).
- Produces `cat_settings.rs`: `CAT_IDS: [&str; 16]`, `clean_cat_settings(&Value) -> Value`, `clean_personality(&Value) -> Value`, `default_value() -> Value`. And in `settings.rs`: `Settings.cat: serde_json::Value`, camelCase on the wire like the rest (`"cat": {character, motionStyle, collar, furLines, cats}`), always clean after `load` and after `sanitized`, which `save_settings` already runs on everything the webview sends.

Why a `Value`: A-0d's rule. A typed struct for the block would make one bad field (a hand edit, an old build) fail the **whole** `settings.json`, which `load` would then rename to `settings.json.bad-<stamp>` and replace with defaults: every preference lost for one wrong word in the Cat section. A `Value` always parses, and `clean_cat_settings` is the one way in. `serde_json` has `preserve_order` on in this crate, so the block keeps the order it is written in; nothing depends on it (the front end reads the cats through the 16 IDs).

Rust runs only through `windows/scripts/cargo-linux.sh`, with this plan's own target directory (the Docker volume is shared by every worktree). The first build of a fresh target directory compiles every crate and takes several minutes.

- [ ] **Step 1: Check the Linux image and the baseline**

Run: `docker image inspect notchmeow-linux-dev >/dev/null && echo "image ok"`
Expected: `image ok`. If it prints an error, stop: the script would build the image, which pulls a base image. Report it to the main session, and do the TypeScript tasks only.

Run: `windows/scripts/cargo-linux.sh test -p notchmeow settings:: --target-dir /repo/windows/target/a-tauri-57 2>&1 | grep -E "^test result: .* [1-9][0-9]* passed|error"`
Expected: `test result: ok. 7 passed; 0 failed; 0 ignored; 0 measured; 222 filtered out; finished in …`: the seven existing settings tests.

- [ ] **Step 2: Write the module and its tests**

```rust title="windows/src-tauri/src/cat_settings.rs" create
// The Cat section of settings.json (spec §4), cleaned: a port of "Stored settings" in design/prototype/cat-core.js, which decides
// (tests/fixtures/cat/settings-cases.json; docs/CAT-CONTRACT.md "Stored settings"). settings.json is plain text a user can edit and the
// webview hands over whatever it holds, so the block is held as a serde_json::Value, never as a typed struct: one bad field in a typed
// struct would fail the whole settings file. `clean_cat_settings` is the one way in. Raw in, clean out, never a panic. The TypeScript side
// (src/cat/settings.ts) cleans the same way again before it uses a value, and both replay the same fixture.
//
//   { character, motionStyle, collar, furLines, cats: { <catId>: { motion, collar, personality } } }   with all 16 cat IDs once clean.

use serde_json::{json, Map, Value};

/// The cat IDs: frozen contract values, in this order. An unknown stored ID is Shrimpy.
pub const CAT_IDS: [&str; 16] = [
    "shrimpy", "momo", "ginger", "midnight", "latte", "patches", "blue", "snow", "oreo", "mocha", "silver", "cloud", "leo", "button", "puff", "noodle",
];
const MOTION_STYLES: [&str; 2] = ["playful", "classic"];
/// The collar style IDs: frozen, in this order. An unknown stored style is `off`.
const COLLAR_STYLES: [&str; 4] = ["tag", "band", "kerchief", "off"];
/// "No override: use the global setting." Not a motion style and not a collar style.
const FOLLOW: &str = "follow";
const TRAIT_KEYS: [&str; 6] = ["energy", "curiosity", "chatty", "affection", "sass", "mischief"];
/// The six presets and their traits, in TRAIT_KEYS order (personality.ts and personality-cases.json say the same).
const PERSONAS: [(&str, [f64; 6]); 6] = [
    ("balanced", [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]),
    ("chill", [0.12, 0.35, 0.3, 0.65, 0.3, 0.2]),
    ("grumpy", [0.4, 0.3, 0.45, 0.15, 0.95, 0.3]),
    ("sweet", [0.5, 0.55, 0.55, 1.0, 0.1, 0.3]),
    ("hyper", [1.0, 0.9, 0.75, 0.5, 0.3, 1.0]),
    ("chatty", [0.6, 0.7, 1.0, 0.6, 0.35, 0.5]),
];
static NULL: Value = Value::Null;

/// The stored word if it is one of `allowed` (matched exactly: case, spaces and the JSON type all count), else `other`.
fn word(v: Option<&Value>, allowed: &[&'static str], other: &'static str) -> &'static str {
    match v {
        Some(Value::String(s)) => allowed.iter().copied().find(|a| a == s).unwrap_or(other),
        _ => other,
    }
}

/// A trait as stored: a number is held to 0…1; anything else (missing, text, a boolean, null) is 0.5. Minus zero is stored as 0.
fn trait_value(v: Option<&Value>) -> f64 {
    match v.and_then(Value::as_f64) {
        Some(x) if x.is_finite() => (if x < 0.0 { 0.0 } else if x > 1.0 { 1.0 } else { x }) + 0.0,
        _ => 0.5,
    }
}

fn personality(preset: &str, traits: [f64; 6]) -> Value {
    let mut m = Map::new();
    m.insert("preset".into(), json!(preset));
    for (k, v) in TRAIT_KEYS.iter().zip(traits) {
        m.insert((*k).into(), json!(v));
    }
    Value::Object(m)
}

fn balanced() -> Value {
    personality("balanced", PERSONAS[0].1)
}

/// A stored personality to a clean one: an object, or the JSON text of one. Text that is not JSON, and JSON that is not an object, give
/// Balanced. The six traits are held to 0…1 (missing or not a number is 0.5). The preset is kept only when it names one of the six AND the
/// traits are still that preset's (within 1e-9); anything else, a missing or unknown name included, is `custom`.
pub fn clean_personality(raw: &Value) -> Value {
    let parsed;
    let v = match raw {
        Value::String(text) => match serde_json::from_str::<Value>(text) {
            Ok(p) => {
                parsed = p;
                &parsed
            }
            Err(_) => return balanced(),
        },
        other => other,
    };
    let Value::Object(o) = v else { return balanced() };
    let traits: [f64; 6] = std::array::from_fn(|i| trait_value(o.get(TRAIT_KEYS[i])));
    let named = o
        .get("preset")
        .and_then(Value::as_str)
        .and_then(|n| PERSONAS.iter().find(|(name, t)| *name == n && t.iter().zip(&traits).all(|(a, b)| (a - b).abs() <= 1e-9)));
    personality(named.map_or("custom", |p| p.0), traits)
}

/// Everything Settings saves, cleaned. Never panics; unknown keys are dropped; the result always holds all 16 cats.
pub fn clean_cat_settings(raw: &Value) -> Value {
    let none = Map::new();
    let r = raw.as_object().unwrap_or(&none);
    let stored = r.get("cats").and_then(Value::as_object).unwrap_or(&none);
    let mut cats = Map::new();
    for id in CAT_IDS {
        let c = stored.get(id).and_then(Value::as_object).unwrap_or(&none);
        cats.insert(
            id.into(),
            json!({
                "motion": word(c.get("motion"), &MOTION_STYLES, FOLLOW),
                "collar": word(c.get("collar"), &COLLAR_STYLES, FOLLOW),
                "personality": clean_personality(c.get("personality").unwrap_or(&NULL)),
            }),
        );
    }
    json!({
        "character": word(r.get("character"), &CAT_IDS, "shrimpy"),
        "motionStyle": word(r.get("motionStyle"), &MOTION_STYLES, "playful"),
        "collar": word(r.get("collar"), &COLLAR_STYLES, "off"),
        "furLines": r.get("furLines") == Some(&Value::Bool(true)),
        "cats": Value::Object(cats),
    })
}

/// What a fresh install holds: Shrimpy, Playful, collar off, no fur lines, every cat following the globals with a Balanced personality.
pub fn default_value() -> Value {
    clean_cat_settings(&Value::Null)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn fixture(name: &str) -> Value {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/cat").join(name);
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        serde_json::from_str(&text).unwrap_or_else(|e| panic!("parse {}: {e}", path.display()))
    }

    /// Where two values differ: numbers within 1e-9, objects by key (order does not matter), everything else exactly.
    fn differences(a: &Value, b: &Value, at: &str, out: &mut Vec<String>) {
        match (a, b) {
            (Value::Number(x), Value::Number(y)) => {
                if (x.as_f64().unwrap() - y.as_f64().unwrap()).abs() > 1e-9 {
                    out.push(format!("{at}: {x} vs {y}"));
                }
            }
            (Value::Array(x), Value::Array(y)) => {
                if x.len() != y.len() {
                    out.push(format!("{at}: length {} vs {}", x.len(), y.len()));
                }
                for (i, (p, q)) in x.iter().zip(y).enumerate() {
                    differences(p, q, &format!("{at}[{i}]"), out);
                }
            }
            (Value::Object(x), Value::Object(y)) => {
                let (mut kx, mut ky): (Vec<_>, Vec<_>) = (x.keys().collect(), y.keys().collect());
                kx.sort();
                ky.sort();
                if kx != ky {
                    out.push(format!("{at}: keys {kx:?} vs {ky:?}"));
                }
                for (k, p) in x {
                    if let Some(q) = y.get(k) {
                        differences(p, q, &format!("{at}.{k}"), out);
                    }
                }
            }
            _ => {
                if a != b {
                    out.push(format!("{at}: {a} vs {b}"));
                }
            }
        }
    }

    fn assert_same(got: &Value, want: &Value, what: &str) {
        let mut d = Vec::new();
        differences(got, want, "$", &mut d);
        assert!(d.is_empty(), "{what}: {} difference(s), first: {:?}", d.len(), &d[..d.len().min(4)]);
    }

    #[test]
    fn the_ids_words_and_presets_are_the_fixtures() {
        let fx = fixture("settings-cases.json");
        let ids: Vec<&str> = fx["ids"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
        assert_eq!(ids, CAT_IDS);
        assert_eq!(fx["follow"], FOLLOW);
        assert_eq!(fx["motionStyles"], json!(MOTION_STYLES));
        assert_eq!(fx["collarStyles"], json!(COLLAR_STYLES));
        let presets = &fixture("personality-cases.json")["presets"];
        for (name, traits) in PERSONAS {
            for (k, v) in TRAIT_KEYS.iter().zip(traits) {
                assert_eq!(presets[name][*k].as_f64(), Some(v), "{name}.{k}");
            }
        }
        assert_eq!(presets.as_object().unwrap().len(), PERSONAS.len());
    }

    #[test]
    fn a_fresh_install_is_the_fixtures_defaults() {
        assert_same(&default_value(), &fixture("settings-cases.json")["defaults"], "defaults");
        let d = default_value();
        assert_eq!((&d["character"], &d["motionStyle"], &d["collar"], &d["furLines"]), (&json!("shrimpy"), &json!("playful"), &json!("off"), &json!(false)));
        let keys: Vec<&str> = d["cats"].as_object().unwrap().keys().map(String::as_str).collect();
        assert_eq!(keys, CAT_IDS);
    }

    #[test]
    fn every_settings_case_of_the_fixture_replays() {
        let cases = fixture("settings-cases.json")["cases"].clone();
        assert!(cases.as_array().unwrap().len() >= 37);
        for c in cases.as_array().unwrap() {
            assert_same(&clean_cat_settings(&c["raw"]), &c["out"], c["name"].as_str().unwrap());
        }
    }

    #[test]
    fn every_personality_case_of_the_fixture_replays() {
        let cases = fixture("settings-cases.json")["personalities"].clone();
        assert!(cases.as_array().unwrap().len() >= 47);
        for c in cases.as_array().unwrap() {
            assert_same(&clean_personality(&c["raw"]), &c["out"], c["name"].as_str().unwrap());
        }
    }

    #[test]
    fn a_number_that_cannot_be_written_in_json_has_no_value_and_a_huge_one_is_held_to_1() {
        // Python's NaN cannot be written in JSON, and serde_json cannot hold NaN or an infinity in a Value at all (the fixture's port note).
        assert!(serde_json::Number::from_f64(f64::NAN).is_none() && serde_json::Number::from_f64(f64::INFINITY).is_none());
        let p = clean_personality(&json!({"energy": u64::MAX, "curiosity": -5, "chatty": 1e300, "affection": -0.0, "sass": "0.9", "mischief": true}));
        let got: Vec<f64> = TRAIT_KEYS.iter().map(|k| p[*k].as_f64().unwrap()).collect();
        assert_eq!(got, [1.0, 0.0, 1.0, 0.0, 0.5, 0.5]);
        assert!(p["affection"].as_f64().unwrap().is_sign_positive(), "minus zero is stored as 0");
        assert_eq!(p["preset"], "custom");
    }

    #[test]
    fn a_preset_name_is_kept_only_while_the_traits_are_still_that_presets() {
        let chill = json!({"preset": "chill", "energy": 0.12, "curiosity": 0.35, "chatty": 0.3, "affection": 0.65, "sass": 0.3, "mischief": 0.2});
        assert_eq!(clean_personality(&chill)["preset"], "chill");
        let mut moved = chill.clone();
        moved["energy"] = json!(0.9);
        assert_eq!(clean_personality(&moved)["preset"], "custom");
        assert_eq!(clean_personality(&json!({"preset": "chill"}))["preset"], "custom", "a name alone: the traits are missing, so 0.5");
        assert_eq!(clean_personality(&json!({"preset": "balanced"}))["preset"], "balanced");
        assert_eq!(clean_personality(&Value::String(chill.to_string()))["preset"], "chill", "the Mac stores JSON text; so can a file");
        assert_eq!(clean_personality(&json!("{\"energy\":")), balanced(), "text that is not JSON");
        assert_eq!(clean_personality(&json!("[1,2]")), balanced(), "JSON that is not an object");
        let deep = format!("{}1{}", "[".repeat(5000), "]".repeat(5000));
        assert_eq!(clean_personality(&Value::String(deep)), balanced(), "nesting past serde_json's limit is an error, not a stack overflow");
    }

    /// Everything a clean value promises.
    fn valid(s: &Value) -> bool {
        let Some(o) = s.as_object() else { return false };
        let is = |k: &str, list: &[&str]| o.get(k).and_then(Value::as_str).is_some_and(|w| list.contains(&w));
        let with_follow = |list: &[&'static str]| -> Vec<&'static str> { list.iter().copied().chain([FOLLOW]).collect() };
        let (motions, collars) = (with_follow(&MOTION_STYLES), with_follow(&COLLAR_STYLES));
        let entry_ok = |e: &Value| {
            let Some(e) = e.as_object() else { return false };
            let word_ok = |k: &str, list: &[&str]| e.get(k).and_then(Value::as_str).is_some_and(|w| list.contains(&w));
            let Some(p) = e.get("personality").and_then(Value::as_object) else { return false };
            let preset = p.get("preset").and_then(Value::as_str).unwrap_or("");
            word_ok("motion", &motions)
                && word_ok("collar", &collars)
                && (preset == "custom" || PERSONAS.iter().any(|(n, _)| *n == preset))
                && TRAIT_KEYS.iter().all(|k| p.get(*k).and_then(Value::as_f64).is_some_and(|x| (0.0..=1.0).contains(&x)))
        };
        is("character", &CAT_IDS)
            && is("motionStyle", &MOTION_STYLES)
            && is("collar", &COLLAR_STYLES)
            && o.get("furLines").is_some_and(Value::is_boolean)
            && o.get("cats").and_then(Value::as_object).is_some_and(|c| c.keys().map(String::as_str).eq(CAT_IDS) && c.values().all(entry_ok))
    }

    #[test]
    fn hostile_values_never_panic_come_out_valid_and_cleaning_twice_changes_nothing() {
        let pool = vec![
            json!("momo"), json!("tiger"), json!("classic"), json!("playful"), json!("follow"), json!("off"), json!("band"), json!("tag"), json!("kerchief"),
            json!(""), json!(" "), json!("chill"), json!("custom"), json!("{"), json!("{\"energy\":2}"), json!("__proto__"), json!("constructor"),
            Value::String(json!({"preset":"sweet","affection":1,"energy":0.5,"curiosity":0.55,"chatty":0.55,"sass":0.1,"mischief":0.3}).to_string()),
            Value::Null, json!(true), json!(false), json!(0), json!(1), json!(-1), json!(0.5), json!(7), json!(1e300), json!(u64::MAX), json!([]), json!([1]), json!({}),
            json!({"energy": 9}), json!({"preset": "hyper"}),
        ];
        let mut state: u32 = 2026;
        let mut next = move || {
            state = state.wrapping_mul(1_103_515_245).wrapping_add(12_345);
            (state >> 8) as usize
        };
        for _ in 0..600 {
            let pick = |n: usize| pool[n % pool.len()].clone();
            let cats = if next() % 10 == 0 {
                pick(next())
            } else {
                let mut m = Map::new();
                for id in CAT_IDS {
                    if next() % 2 == 0 {
                        m.insert(id.into(), if next() % 10 == 0 { pick(next()) } else { json!({"motion": pick(next()), "collar": pick(next()), "personality": pick(next())}) });
                    }
                }
                Value::Object(m)
            };
            let raw = json!({"character": pick(next()), "motionStyle": pick(next()), "collar": pick(next()), "furLines": pick(next()), "cats": cats});
            let out = clean_cat_settings(&raw);
            assert!(valid(&out), "{raw}");
            assert_eq!(clean_cat_settings(&out), out, "{raw}");
        }
        for raw in [Value::Null, json!(5), json!("junk"), json!([]), json!({}), json!({"cats": []}), json!({"cats": "x"})] {
            assert_eq!(clean_cat_settings(&raw), default_value(), "{raw}");
        }
        let evil: Value = serde_json::from_str(r#"{"__proto__":{"motion":"classic"},"cats":{"__proto__":{"motion":"classic"},"constructor":{"motion":"classic"}}}"#).unwrap();
        let out = clean_cat_settings(&evil);
        assert!(valid(&out) && out["cats"].as_object().unwrap().len() == 16);
    }
}
```

Then the `mod` line:

```rust title="windows/src-tauri/src/lib.rs" old
mod agent_hooks;
mod ai;
mod files;
```

```rust title="windows/src-tauri/src/lib.rs" new
mod agent_hooks;
mod ai;
mod cat_settings;
mod files;
```

- [ ] **Step 3: Run the module's tests**

Run: `windows/scripts/cargo-linux.sh test -p notchmeow cat_settings:: --target-dir /repo/windows/target/a-tauri-57 2>&1 | grep -E "^test |^test result: .* [1-9][0-9]* passed|^error"`
Expected: seven lines `test cat_settings::tests::… ... ok`, then `test result: ok. 7 passed; 0 failed; 0 ignored; 0 measured; 229 filtered out`, a second `test result: ok. 0 passed` line for the doc tests, and no `error`. (The compiler also prints 14 `never used` warnings for the module, which nothing calls yet: Step 4 uses it.)

- [ ] **Step 4: Hold the block in `Settings`, clean it on load and on every save**

```rust title="windows/src-tauri/src/settings.rs" old
    #[serde(default)]
    pub ai: AiSettings,
}
```

```rust title="windows/src-tauri/src/settings.rs" new
    #[serde(default)]
    pub ai: AiSettings,
    /// The Cat section of Settings (spec §4): `{character, motionStyle, collar, furLines, cats}`. Held as a JSON value, never as a typed
    /// struct, so that one bad field cannot fail the whole file; `sanitized` runs it through `cat_settings::clean_cat_settings`.
    #[serde(default = "crate::cat_settings::default_value")]
    pub cat: serde_json::Value,
}
```

```rust title="windows/src-tauri/src/settings.rs" old
            model: None,
            ai: AiSettings::default(),
```

```rust title="windows/src-tauri/src/settings.rs" new
            model: None,
            ai: AiSettings::default(),
            cat: crate::cat_settings::default_value(),
```

```rust title="windows/src-tauri/src/settings.rs" old
    settings.ai.claude_code_model = crate::ai::claude_code::model_or_default(&settings.ai.claude_code_model);
    settings
}
```

```rust title="windows/src-tauri/src/settings.rs" new
    settings.ai.claude_code_model = crate::ai::claude_code::model_or_default(&settings.ai.claude_code_model);
    settings.cat = crate::cat_settings::clean_cat_settings(&settings.cat);
    settings
}
```

The doc comment above `sanitized` says what it keeps; add the cat block to it:

```rust title="windows/src-tauri/src/settings.rs" old
/// What may be kept and shown: the server the user added loses a typed `user:pass@` (and any
/// query), because settings.json is plain text and the webview sees it. Applied on load and
/// to everything the webview saves; the server's key lives in the keychain, never in a URL.
```

```rust title="windows/src-tauri/src/settings.rs" new
/// What may be kept and shown: the server the user added loses a typed `user:pass@` (and any
/// query), because settings.json is plain text and the webview sees it; the Cat block is
/// cleaned to its 16 cats and its frozen words. Applied on load and to everything the webview
/// saves; the server's key lives in the keychain, never in a URL.
```

- [ ] **Step 5: Test the file as a user could break it**

```rust title="windows/src-tauri/src/settings.rs" old
        assert!(!logged.is_empty() && !logged.contains("locked-note"), "{logged}");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
```

```rust title="windows/src-tauri/src/settings.rs" new
        assert!(!logged.is_empty() && !logged.contains("locked-note"), "{logged}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    const OLD_FILE: &str = r#"{"soundEnabled":false,"soundVolume":0.12,"autoCloseInterval":15,"absenceInterval":180,
        "activeIntegrations":[],"screen":"cursor","autostart":false,"hooksInstalled":false"#;

    #[test]
    fn a_settings_file_from_before_the_cat_section_gets_the_default_cat() {
        let s = sanitized(migrate(serde_json::from_str(&format!("{OLD_FILE}}}")).unwrap()));
        assert_eq!(s.cat, crate::cat_settings::default_value());
        assert_eq!(s.cat["character"], "shrimpy");
        assert_eq!(s.cat["cats"].as_object().unwrap().len(), 16);
        assert_eq!(serde_json::to_value(&s).unwrap()["cat"], s.cat, "the block is written back as it is held");
    }

    /// A typed `cat` field would reject every one of these, and `load` would then move the whole file aside.
    #[test]
    fn one_bad_field_in_the_cat_block_never_fails_the_settings_file() {
        let dir = std::env::temp_dir().join(format!("notchmeow-bad-cat-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        for cat in [
            "5",
            r#""junk""#,
            "[1,2]",
            "null",
            r#"{"character":7,"motionStyle":[],"collar":{"a":1},"furLines":"yes","cats":"x"}"#,
            r#"{"cats":{"momo":{"personality":"{not json","motion":9},"ginger":[1],"tiger":{}}}"#,
        ] {
            std::fs::write(&path, format!(r#"{OLD_FILE},"cat":{cat}}}"#)).unwrap();
            let s = load_from(&path);
            assert!(!s.sound_enabled && s.screen == "cursor", "the rest of the file is kept: {cat}");
            assert_eq!(s.cat, crate::cat_settings::default_value(), "{cat}");
            assert!(path.exists(), "the file is not moved aside: {cat}");
        }
        let backups = std::fs::read_dir(&dir).unwrap().filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().starts_with("settings.json.bad-")).count();
        assert_eq!(backups, 0);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_good_cat_block_survives_a_round_trip_and_what_the_webview_sends_is_cleaned() {
        let mut s = Settings::default();
        s.cat = serde_json::json!({
            "character": "momo", "motionStyle": "classic", "collar": "band", "furLines": true,
            "cats": {"momo": {"motion": "playful", "collar": "off", "personality": {"preset": "custom", "energy": 0.27, "curiosity": 0.83, "chatty": 0.41, "affection": 0.58, "sass": 0.12, "mischief": 0.99}}}
        });
        let kept = sanitized(s.clone());
        let back: Settings = serde_json::from_value(serde_json::to_value(&kept).unwrap()).unwrap();
        assert_eq!(back.cat, kept.cat);
        assert_eq!(kept.cat["character"], "momo");
        assert_eq!(kept.cat["cats"]["momo"]["motion"], "playful");
        assert_eq!(kept.cat["cats"]["momo"]["collar"], "off");
        assert_eq!(kept.cat["cats"]["momo"]["personality"]["energy"].as_f64(), Some(0.27));
        assert_eq!(kept.cat["cats"]["ginger"]["motion"], "follow");
        // The webview is not trusted: a hostile block is cleaned before it is stored, saved or shared (`save_settings` runs `sanitized`).
        s.cat = serde_json::json!({"character": "tiger", "motionStyle": 3, "furLines": "true", "cats": {"momo": {"motion": "bogus"}}, "extra": 1});
        let cleaned = sanitized(s);
        assert_eq!(cleaned.cat["character"], "shrimpy");
        assert_eq!(cleaned.cat["furLines"], false);
        assert_eq!(cleaned.cat["cats"]["momo"]["motion"], "follow");
        assert!(cleaned.cat.get("extra").is_none());
    }
}
```

- [ ] **Step 6: Run the settings tests and the whole Rust suite**

Run: `windows/scripts/cargo-linux.sh test -p notchmeow settings:: --target-dir /repo/windows/target/a-tauri-57 2>&1 | grep -E "^test result: .* [1-9][0-9]* passed|^error|^warning"`
Expected: `test result: ok. 17 passed; 0 failed; 0 ignored; 0 measured; 222 filtered out`: the seven old settings tests, the three new ones, and the seven of `cat_settings` (its path contains `settings::` too). No `error`, no `warning`.

Run: `windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/a-tauri-57 2>&1 | grep -E "^test result|^error|^warning|FAILED"`
Expected: four `test result: ok.` lines and no `error`, `warning` or `FAILED`: the app's library `239 passed` (the 229 from before, and the 10 new ones), the relay `23 passed`, and two empty doc-test lines with `0 passed`.

- [ ] **Step 7: Commit**

Run: `git status --short`
Expected: ` M windows/src-tauri/src/lib.rs`, ` M windows/src-tauri/src/settings.rs`, `?? windows/src-tauri/src/cat_settings.rs` (and, in a dry-run clone, A-0d's files and the `windows/node_modules` link). `windows/Cargo.lock` is unchanged: the block adds no crate.

```bash
git add windows/src-tauri/src/cat_settings.rs windows/src-tauri/src/lib.rs windows/src-tauri/src/settings.rs
git commit -m "feat(settings): the cat block is held as a JSON value and cleaned in Rust, so one bad field cannot fail the file

cat_settings.rs is the Rust port of cleanCatSettings, replayed from settings-cases.json. Settings.cat is cleaned on load and on
everything the webview saves. No crate added.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Settings feed the engine: the chosen cat, motion, personality and fur lines reach every canvas

**Agent:** `nm-implementer`.

**Files:**
- Modify: `windows/src/cat/engine.ts` (`CatCfg`, the constructor, `update`, `draw`), `windows/src/core/state.ts` (`Settings.cat`), `windows/src/island/island.ts` (`applySettings`), `windows/src/cat/greeting.ts` (`start`), `windows/src/upload/canvas.ts` (the drop view's cat)
- Create: `windows/scripts/cat-tests/follow.test.mjs`

**Interfaces:**
- Consumes (Task 1): `applyCatSettings(cfg, settings)` and `defaultCatSettings()` from `src/cat/settings.ts`.
- Produces: `CatCfg` gains `character?`, `collar?` and `fur?` (the three fields Task 1's `LiveCfg` fills). A `BotEngine` built **without** a preset *follows* `cfg.character`: it wears that cat from the first frame and changes when Settings changes it (`engine.follow`, `engine.p` is no longer read-only); one built with a preset keeps it (the contact sheet, the Settings previews, the tests). `Settings.cat: CatSettings` in `core/state.ts`. `Island.applySettings()` puts `State.settings.cat` through `applyCatSettings(catCfg, …)`, which runs at boot and on every `settings-changed` event, so the island, the pills, the compact grid and the drop view change with the Settings window, with no restart. `Greeting.start()` wears the chosen cat.
- The wiring: `main.ts` already calls `island.applySettings()` after `Bridge.boot()` and in the `settings-changed` handler, so it needs no edit.

- [ ] **Step 1: Write the failing tests**

```js title="windows/scripts/cat-tests/follow.test.mjs" create
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { BotEngine, catCfg } from "../../src/cat/engine.ts";
import { Greeting } from "../../src/cat/greeting.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { applyCatSettings } from "../../src/cat/settings.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

installBrowserStubs();
const cfgOf = (extra = {}) => ({ motion: "playful", override: {}, pers: {}, zoomAfter: 300000, ...extra });
const make = (preset, cfg) => new BotEngine(preset, { cfg, quiet: true, now: () => 0, rand: () => 0.5 });
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("an engine built without a preset wears the chosen cat and changes with it; one built with a preset keeps it", () => {
  const cfg = cfgOf({ character: "momo" });
  const follows = make(undefined, cfg), fixed = make(PRESETS.latte, cfg);
  assert.deepEqual([follows.follow, fixed.follow], [true, false]);
  assert.deepEqual([follows.p.name, fixed.p.name], ["momo", "latte"]);
  cfg.character = "ginger";
  follows.update(1 / 60); fixed.update(1 / 60);
  assert.deepEqual([follows.p.name, fixed.p.name], ["ginger", "latte"]);
  for (const bad of ["tiger", "", "Momo", "__proto__", undefined, null, 7]) {
    cfg.character = bad;
    follows.update(1 / 60);
    assert.equal(follows.p.name, "shrimpy", `an unknown character (${String(bad)}) is Shrimpy`);
  }
  assert.equal(make(undefined, cfgOf()).p.name, "shrimpy", "nothing chosen yet: Shrimpy");
});

test("Settings change the cat, the motion and the personality of an engine that is already running", () => {
  const cfg = cfgOf(), e = make(undefined, cfg);
  applyCatSettings(cfg, { character: "momo", motionStyle: "classic", cats: { momo: { motion: "playful", personality: { preset: "hyper" } } } });
  e.update(1 / 60);
  assert.equal(e.p.name, "momo");
  assert.equal(e.motion, "playful", "momo's own motion beats the global style");
  assert.equal(e.pers.preset, "custom", "a personality with only a name is Custom, with the missing traits at 0.5");
  applyCatSettings(cfg, { character: "ginger", motionStyle: "classic" });
  e.update(1 / 60);
  assert.deepEqual([e.p.name, e.motion], ["ginger", "classic"]);
});

test("the fur lines setting reaches the drawing: a big cat grows strands, a small one does not", () => {
  const strokes = (fur, head) => {
    const cfg = cfgOf({ character: "shrimpy", fur }), e = make(undefined, cfg), ctx = fakeCanvas();
    e.draw(ctx, head / 0.6, head / 0.6 + 40);
    return ctx.calls.stroke || 0;
  };
  assert.ok(strokes(true, 100) > strokes(false, 100) + 100, "Ø100 with fur lines draws hundreds of strands");
  assert.equal(strokes(true, 24), strokes(false, 24), "a small cat is flat");
});

test("the greeting wears the chosen cat", () => {
  globalThis.window = { setTimeout: () => 0, clearTimeout: () => {} };
  try {
    for (const id of ["momo", "latte", "tiger"]) {
      catCfg.character = id;
      const g = new Greeting();
      g.start();
      assert.equal(g.view.p.name, id === "tiger" ? "shrimpy" : id, id);
      assert.equal(g.minis.p.name, g.view.p.name);
    }
  } finally {
    delete catCfg.character;
    delete globalThis.window;
  }
});

test("the wiring: Island.applySettings fills catCfg, the drop view's cat follows, the state holds the cat block", () => {
  assert.match(source("island/island.ts"), /applySettings\(\) \{[^}]*State\.settings\.cat = applyCatSettings\(catCfg, State\.settings\.cat\);/s);
  assert.match(source("upload/canvas.ts"), /readonly cat = new BotEngine\(\);/);
  assert.match(source("cat/greeting.ts"), /this\.view = greetView\(catCfg\.character \?\? DEFAULT_CAT,/);
  assert.match(source("core/state.ts"), /cat: CatSettings;/);
  assert.match(source("core/state.ts"), /cat: defaultCatSettings\(\),/);
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/follow.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; cd ..`
Expected: `# tests 5`, `# pass 0`, `# fail 5`.

- [ ] **Step 3: The engine follows the chosen cat**

```ts title="windows/src/cat/engine.ts" old
import { catById, DEFAULT_CAT } from "./presets.ts";
```

```ts title="windows/src/cat/engine.ts" new
import { catById } from "./presets.ts";
```

```ts title="windows/src/cat/engine.ts" old
export interface CatCfg {
  motion: string;
  override: Record<string, string | null | undefined>;
  pers: Record<string, Persona | undefined>;
  zoomAfter: number;
}
```

```ts title="windows/src/cat/engine.ts" new
export interface CatCfg {
  motion: string;
  override: Record<string, string | null | undefined>;
  pers: Record<string, Persona | undefined>;
  zoomAfter: number;
  /** The cat everything wears (a cat id): the island, the pills, the drop view and the greeting. Settings fills it; an unknown or missing one is Shrimpy. */
  character?: string;
  /** The collar style that cat wears (cat/settings.ts, `collarFor`): `tag`, `band`, `kerchief` or `off`. Drawn from stage 6 on. */
  collar?: string;
  /** Optional fur strands, drawn on a big cat only (the renderer's own size rule). */
  fur?: boolean;
}
```

```ts title="windows/src/cat/engine.ts" old
  readonly p: CatPreset;
  isMini: boolean;
```

```ts title="windows/src/cat/engine.ts" new
  /** The cat this engine animates. */
  p: CatPreset;
  /** True for an engine built without a preset: it wears `cfg.character`, whichever cat that is now, and `update` keeps it so. */
  readonly follow: boolean;
  isMini: boolean;
```

```ts title="windows/src/cat/engine.ts" old
  constructor(p: CatPreset = catById(DEFAULT_CAT), o: EngineOptions = {}) {
    this.p = p;
    this.isMini = !!o.mini;
    this.now = o.now || (() => performance.now());
    this.rand = o.rand || (() => Math.random());
    this.cfg = o.cfg || catCfg;
```

```ts title="windows/src/cat/engine.ts" new
  /** Built without a preset, the engine wears the cat Settings chose (`cfg.character`) and follows it when it changes; with a preset it keeps that cat. */
  constructor(p?: CatPreset, o: EngineOptions = {}) {
    this.cfg = o.cfg || catCfg;
    this.follow = p === undefined;
    this.p = p ?? catById(this.cfg.character);
    this.isMini = !!o.mini;
    this.now = o.now || (() => performance.now());
    this.rand = o.rand || (() => Math.random());
```

```ts title="windows/src/cat/engine.ts" old
  update(dt: number) {
    dt = Number.isFinite(dt) ? Math.min(Math.max(dt, 0), 0.25) : 0;
```

```ts title="windows/src/cat/engine.ts" new
  update(dt: number) {
    dt = Number.isFinite(dt) ? Math.min(Math.max(dt, 0), 0.25) : 0;
    if (this.follow) this.p = catById(this.cfg.character);
```

```ts title="windows/src/cat/engine.ts" old
    drawCat(x, this, W / 2, cy, W * 0.6, { badgeSide: this.badgeLeft ? -1 : 1, earCeiling: this.earRoom === null ? undefined : cy - this.earRoom });
```

```ts title="windows/src/cat/engine.ts" new
    drawCat(x, this, W / 2, cy, W * 0.6, { badgeSide: this.badgeLeft ? -1 : 1, earCeiling: this.earRoom === null ? undefined : cy - this.earRoom, fur: this.cfg.fur });
```

- [ ] **Step 4: The state, the island, the greeting and the drop view**

```ts title="windows/src/core/state.ts" old
import type { EyeShape } from "../cat/engine";
```

```ts title="windows/src/core/state.ts" new
import type { EyeShape } from "../cat/engine";
import { defaultCatSettings, type CatSettings } from "../cat/settings.ts";
```

```ts title="windows/src/core/state.ts" old
  /** Which models answer (settings::AiSettings). */
  ai: AiSettings;
}
```

```ts title="windows/src/core/state.ts" new
  /** Which models answer (settings::AiSettings). */
  ai: AiSettings;
  /** The Cat section of Settings (cat/settings.ts), clean: the character, the motion style, the collar, the fur lines and each cat's own motion, collar and personality. */
  cat: CatSettings;
}
```

```ts title="windows/src/core/state.ts" old
  hooksInstalled: false,
  ai: { ...DEFAULT_AI },
};
```

```ts title="windows/src/core/state.ts" new
  hooksInstalled: false,
  ai: { ...DEFAULT_AI },
  cat: defaultCatSettings(),
};
```

```ts title="windows/src/island/island.ts" old
import { BotEngine, hexToRGB } from "../cat/engine";
```

```ts title="windows/src/island/island.ts" new
import { BotEngine, catCfg, hexToRGB } from "../cat/engine";
import { applyCatSettings } from "../cat/settings";
```

```ts title="windows/src/island/island.ts" old
    this.fsm.homeToPetitDelay = State.settings.autoCloseInterval;
    State.notify();
  }
```

```ts title="windows/src/island/island.ts" new
    this.fsm.homeToPetitDelay = State.settings.autoCloseInterval;
    // The cat block comes from Rust already clean; cleaning it again costs nothing and keeps a bad value out of every engine.
    State.settings.cat = applyCatSettings(catCfg, State.settings.cat);
    State.notify();
  }
```

```ts title="windows/src/cat/greeting.ts" old
import { DEFAULT_CAT, catById } from "./presets.ts";
```

```ts title="windows/src/cat/greeting.ts" new
import { DEFAULT_CAT, catById } from "./presets.ts";
import { catCfg } from "./engine.ts";
```

```ts title="windows/src/cat/greeting.ts" old
    this.view = greetView(DEFAULT_CAT, () => this.eye);
    this.minis = miniView(this.view.p);
```

```ts title="windows/src/cat/greeting.ts" new
    this.view = greetView(catCfg.character ?? DEFAULT_CAT, () => this.eye);
    this.minis = miniView(this.view.p);
```

```ts title="windows/src/upload/canvas.ts" old
import { DEFAULT_CAT, catById } from "../cat/presets";
import { drawCat } from "../cat/renderer";
```

```ts title="windows/src/upload/canvas.ts" new
import { drawCat } from "../cat/renderer";
```

```ts title="windows/src/upload/canvas.ts" old
  /** The drop view's cat. */
  readonly cat = new BotEngine(catById(DEFAULT_CAT));
```

```ts title="windows/src/upload/canvas.ts" new
  /** The drop view's cat: the one Settings chose. */
  readonly cat = new BotEngine();
```

- [ ] **Step 5: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/follow.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 5`, `# pass 5`, `# fail 0`, `tsc exit 0` with no type error before it, then `ℹ tests 106`, `ℹ pass 106`, `ℹ fail 0`.

- [ ] **Step 6: Commit**

```bash
git add windows/src/cat/engine.ts windows/src/cat/greeting.ts windows/src/core/state.ts windows/src/island/island.ts windows/src/upload/canvas.ts windows/scripts/cat-tests/follow.test.mjs
git commit -m "feat(cat): the island, the pills, the drop view and the greeting wear the cat Settings chose

A BotEngine built without a preset follows catCfg.character. Island.applySettings puts the cat block through
applyCatSettings at boot and on every settings-changed. The fur lines setting reaches the drawing.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The Settings "Cat" section

**Agent:** `nm-implementer`.

**Files:**
- Create: `windows/src/cat/loop.ts`, `windows/src/settings/cat.ts`
- Create: `windows/scripts/cat-tests/loop.test.mjs`, `windows/scripts/cat-tests/settings-edit.test.mjs`
- Modify: `windows/src/cat/settings.ts` (the seven edit helpers), `windows/src/settings/main.ts` (mount the section), `windows/src/settings/settings.css` (new rules only)

**Interfaces:**
- Consumes: Task 1's `settings.ts`; Task 3's followable engine (`new BotEngine()` wears `catCfg.character`; `new BotEngine(preset)` keeps its cat); `PERSONAS`, `TRAITS`, `personaNamed`, `slide`; `CAT_IDS`, `PRESETS`.
- Produces `src/cat/loop.ts`: `VisibleLoop` and its `LoopEnv` (`raf`, `caf`, `visible`). A frame loop that runs only while it can be seen: `sync()` starts it when `visible()` and stops it when not. Pure (no DOM), so the Node checks drive it with a fake clock.
- Produces in `settings.ts`: `withCharacter(s, id)`, `withMotionStyle(s, v)`, `withCollar(s, v)`, `withFurLines(s, on)`, `withCatMotion(s, id, v)`, `withCatCollar(s, id, v)`, `withPersonality(s, id, p)`: each takes a clean `CatSettings` and returns a new clean one with that one thing changed (an unknown value is the neutral one, an unknown cat is Shrimpy), and never touches its input.
- Produces `src/settings/cat.ts`: `catSection(host): { el, sync() }` with `CatHost = { cat(): CatSettings; put(next: CatSettings, final: boolean): void }`. The rows of spec §4, in its order: **Character** (sixteen live previews, Shrimpy first and Momo second, and one big live preview of the chosen cat, where fur lines and later the collar can be seen), **Motion style**, **This cat's motion**, **Personality** (a preset menu; "Custom" shows once a slider has moved) and the six **trait sliders**, **Apply to every cat**, **Fur lines**. The two collar rows land in Task 7 with the collar. Existing rows and rules are not touched: the new CSS is new class names only.
- The window is created **hidden at launch and kept** (`lib.rs`, `create_settings_window`), so its page lives all the time. The previews therefore draw only while the page is visible *and* has focus (`visibilitychange`, `focus`, `blur`): a hidden or unfocused Settings window runs no frame loop. Like the AI box (`refreshOnOpen`), this relies on the page's own visibility and focus events; the owner checks it on a real build (Checkpoint 1).

- [ ] **Step 1: Write the failing tests**

```js title="windows/scripts/cat-tests/loop.test.mjs" create
import test from "node:test";
import assert from "node:assert/strict";
import { VisibleLoop } from "../../src/cat/loop.ts";

/** A frame clock the test turns by hand, and a page that can be shown and hidden. */
function page() {
  const p = { visible: true, pending: new Map(), next: 1, cancelled: 0 };
  p.env = {
    raf: (cb) => { const id = p.next++; p.pending.set(id, cb); return id; },
    caf: (id) => { if (p.pending.delete(id)) p.cancelled++; },
    visible: () => p.visible,
  };
  p.frame = (ms) => { const cbs = [...p.pending.values()]; p.pending.clear(); for (const cb of cbs) cb(ms); };
  return p;
}

test("nothing is scheduled until the page can be seen, and a hidden page schedules nothing", () => {
  const p = page(), dts = [];
  const loop = new VisibleLoop((dt) => dts.push(dt), p.env);
  assert.equal(loop.running, false);
  p.visible = false;
  loop.sync();
  assert.equal(p.pending.size, 0);
  assert.equal(loop.running, false);
  p.visible = true;
  loop.sync();
  assert.equal(p.pending.size, 1);
  assert.equal(loop.running, true);
  loop.sync(); loop.sync();
  assert.equal(p.pending.size, 1, "syncing again does not schedule a second frame");
});

test("a frame draws, then asks for the next; the first dt is 0 and a long gap is held to 0.05 s", () => {
  const p = page(), dts = [];
  const loop = new VisibleLoop((dt) => dts.push(dt), p.env);
  loop.sync();
  p.frame(1000); p.frame(1016); p.frame(5000); p.frame(5010);
  assert.deepEqual(dts.map((d) => Math.round(d * 1000) / 1000), [0, 0.016, 0.05, 0.01]);
  assert.equal(p.pending.size, 1);
});

test("a clock that steps back gives a dt of 0, never a negative or a NaN", () => {
  const p = page(), dts = [];
  new VisibleLoop((dt) => dts.push(dt), p.env).sync();
  p.frame(1000); p.frame(900); p.frame(NaN);
  assert.ok(dts.every((d) => Number.isFinite(d) && d >= 0), String(dts));
});

test("hiding the page stops the loop at once: the pending frame is cancelled, and a frame already due draws nothing", () => {
  const p = page(); let drawn = 0;
  const loop = new VisibleLoop(() => { drawn++; }, p.env);
  loop.sync();
  p.frame(1000);
  assert.equal(drawn, 1);
  p.visible = false;
  loop.sync();
  assert.equal(p.pending.size, 0);
  assert.equal(p.cancelled, 1);
  assert.equal(loop.running, false);
  // The page was hidden between two syncs (no event yet): the due frame notices and stops by itself.
  p.visible = true; loop.sync();
  p.visible = false;
  p.frame(2000);
  assert.equal(drawn, 1, "no drawing while hidden");
  assert.equal(p.pending.size, 0, "and no next frame");
  assert.equal(loop.running, false);
});

test("showing the page again restarts it, with a first dt of 0 rather than the whole time it was away", () => {
  const p = page(), dts = [];
  const loop = new VisibleLoop((dt) => dts.push(dt), p.env);
  loop.sync(); p.frame(1000);
  p.visible = false; loop.sync();
  p.visible = true; loop.sync();
  p.frame(600000);
  assert.deepEqual(dts, [0, 0]);
});
```

```js title="windows/scripts/cat-tests/settings-edit.test.mjs" create
import test from "node:test";
import assert from "node:assert/strict";
import { PERSONAS, personaNamed, slide } from "../../src/cat/personality.ts";
import * as S from "../../src/cat/settings.ts";

const plain = (v) => JSON.parse(JSON.stringify(v));
const deepFreeze = (v) => { if (v && typeof v === "object") { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };
/** The dotted paths at which two settings differ. */
function changed(a, b) {
  const out = [];
  const walk = (x, y, at) => {
    if (x && y && typeof x === "object" && typeof y === "object") for (const k of new Set([...Object.keys(x), ...Object.keys(y)])) walk(x[k], y[k], at ? `${at}.${k}` : k);
    else if (x !== y) out.push(at);
  };
  walk(plain(a), plain(b), "");
  return out;
}

test("each row changes exactly one thing, and the input is not touched (it is frozen here)", () => {
  const s = deepFreeze(S.defaultCatSettings());
  assert.deepEqual(changed(s, S.withCharacter(s, "momo")), ["character"]);
  assert.deepEqual(changed(s, S.withMotionStyle(s, "classic")), ["motionStyle"]);
  assert.deepEqual(changed(s, S.withCollar(s, "band")), ["collar"]);
  assert.deepEqual(changed(s, S.withFurLines(s, true)), ["furLines"]);
  assert.deepEqual(changed(s, S.withCatMotion(s, "momo", "classic")), ["cats.momo.motion"]);
  assert.deepEqual(changed(s, S.withCatCollar(s, "momo", "off")), ["cats.momo.collar"]);
  const sweet = changed(s, S.withPersonality(s, "ginger", personaNamed("sweet")));
  assert.ok(sweet.includes("cats.ginger.personality.preset") && sweet.every((p) => p.startsWith("cats.ginger.personality.")), sweet.join());
});

test("a bad value is the neutral one, so it changes nothing; an unknown cat is Shrimpy", () => {
  const s = deepFreeze(S.defaultCatSettings());
  assert.deepEqual(changed(s, S.withCharacter(s, "tiger")), []);
  assert.deepEqual(changed(s, S.withMotionStyle(s, "follow")), [], "follow is a per-cat word, not a global style");
  assert.deepEqual(changed(s, S.withCollar(s, "scarf")), []);
  assert.deepEqual(changed(s, S.withFurLines(s, 1)), [], "only a real true switches fur lines on");
  assert.deepEqual(changed(s, S.withCatMotion(s, "momo", "bogus")), [], "a bad override is follow");
  assert.deepEqual(changed(s, S.withPersonality(s, "momo", "not json")), [], "a personality that is not JSON is Balanced");
  assert.deepEqual(changed(s, S.withCatMotion(s, "tiger", "classic")), ["cats.shrimpy.motion"]);
});

test("moving a slider makes the cat's personality Custom with that trait changed, and the engine's config sees it", () => {
  let s = S.defaultCatSettings();
  s = S.withPersonality(s, "momo", personaNamed("chill"));
  assert.equal(s.cats.momo.personality.preset, "chill");
  s = S.withPersonality(s, "momo", slide(s.cats.momo.personality, "sass", 0.9));
  const { label: _label, ...chill } = PERSONAS.chill;
  assert.deepEqual(plain(s.cats.momo.personality), { preset: "custom", ...chill, sass: 0.9 }, "Custom, with the one trait moved and the others as they were");
  assert.equal(S.engineCfg(s).pers.momo.sass, 0.9);
  assert.equal(S.engineCfg(s).pers.ginger.preset, "balanced", "other cats keep theirs");
  s = S.withPersonality(s, "momo", personaNamed("sweet"));
  assert.equal(s.cats.momo.personality.preset, "sweet", "picking a preset again replaces the Custom values");
});

test("a whole session of edits ends where a person would expect", () => {
  let s = S.defaultCatSettings();
  s = S.withCharacter(s, "momo");
  s = S.withMotionStyle(s, "classic");
  s = S.withCatMotion(s, "momo", "playful");
  s = S.withPersonality(s, "momo", personaNamed("hyper"));
  s = S.withFurLines(s, true);
  s = S.applyToAllCats(s, "momo");
  assert.equal(s.character, "momo");
  assert.deepEqual(S.engineCfg(s).override, Object.fromEntries(Object.keys(s.cats).map((id) => [id, "playful"])));
  assert.ok(Object.values(s.cats).every((c) => c.personality.preset === "hyper"));
  assert.equal(S.motionFor(s, "ginger"), "playful", "every cat now has the override");
  assert.equal(s.motionStyle, "classic");
  assert.equal(s.furLines, true);
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/loop.test.mjs scripts/cat-tests/settings-edit.test.mjs 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|^# (tests|pass|fail)"; cd ..`
Expected: `ERR_MODULE_NOT_FOUND` for `src/cat/loop.ts`, then `# tests 5`, `# pass 0`, `# fail 5` (the loop file cannot load, and the four edit tests fail on `S.withCharacter is not a function`).

- [ ] **Step 3: The frame loop that runs only while it can be seen**

```ts title="windows/src/cat/loop.ts" create
// A frame loop that runs only while its page can be seen. The Settings window is created hidden at launch and kept for the whole run, so a
// loop that ran all the time would cost CPU with Settings closed. `sync()` is the only control: call it on load and whenever the page may
// have been shown or hidden (visibilitychange, focus, blur). Plain data in, no DOM, so the plain-Node checks (npm run check:cat) can drive it.

export interface LoopEnv {
  /** requestAnimationFrame. */
  raf(cb: (ms: number) => void): number;
  /** cancelAnimationFrame. */
  caf(id: number): void;
  /** Whether anyone can see the page right now. */
  visible(): boolean;
}

export class VisibleLoop {
  private id: number | null = null;
  private last = -1;
  private readonly frame: (dt: number) => void;
  private readonly env: LoopEnv;

  /** `frame` gets the seconds since the last frame: 0 on the first, never negative, never more than 0.05. */
  constructor(frame: (dt: number) => void, env: LoopEnv) {
    this.frame = frame;
    this.env = env;
  }

  /** True while a frame is scheduled. */
  get running(): boolean { return this.id !== null; }

  /** Starts the loop if the page can be seen and it is stopped; stops it if the page cannot be seen. */
  sync(): void {
    if (!this.env.visible()) {
      if (this.id !== null) { this.env.caf(this.id); this.id = null; }
      return;
    }
    if (this.id !== null) return;
    this.last = -1;
    this.id = this.env.raf(this.tick);
  }

  private tick = (ms: number) => {
    this.id = null;
    if (!this.env.visible()) return;
    const dt = this.last < 0 ? 0 : Math.min(0.05, Math.max(0, (ms - this.last) / 1000));
    this.last = Number.isFinite(ms) ? ms : this.last;
    this.frame(Number.isFinite(dt) ? dt : 0);
    this.id = this.env.raf(this.tick);
  };
}
```

- [ ] **Step 4: The edit helpers**

```ts title="windows/src/cat/settings.ts" old
  cfg.fur = s.furLines;
  return s;
}
```

```ts title="windows/src/cat/settings.ts" new
  cfg.fur = s.furLines;
  return s;
}

// ── Edits: each Settings row changes one thing and gets a whole clean value back ───────────────────────────────────────────────────────────
// They take a clean CatSettings and return a new one, never touching the input; the result goes through cleanCatSettings, so a bad value is the
// neutral one and an unknown cat is Shrimpy.
const edited = (s: CatSettings, patch: Partial<CatSettings>): CatSettings => cleanCatSettings({ ...s, ...patch });
const entryEdited = (s: CatSettings, id: unknown, patch: Partial<CatEntry>): CatSettings => {
  const k = catIdOf(id);
  return edited(s, { cats: { ...s.cats, [k]: { ...s.cats[k], ...patch } } });
};
/** The Character row. */
export const withCharacter = (s: CatSettings, id: unknown): CatSettings => edited(s, { character: catIdOf(id) });
/** The Motion style row. */
export const withMotionStyle = (s: CatSettings, v: unknown): CatSettings => edited(s, { motionStyle: motionStyleOf(v) });
/** The Collar row. */
export const withCollar = (s: CatSettings, v: unknown): CatSettings => edited(s, { collar: collarStyleOf(v) });
/** The Fur lines row. */
export const withFurLines = (s: CatSettings, on: unknown): CatSettings => edited(s, { furLines: on === true });
/** The This cat's motion row: `follow` or a style, for one cat. */
export const withCatMotion = (s: CatSettings, id: unknown, v: unknown): CatSettings => entryEdited(s, id, { motion: motionOverrideOf(v) });
/** The This cat's collar row: `follow` or a style, for one cat. */
export const withCatCollar = (s: CatSettings, id: unknown, v: unknown): CatSettings => entryEdited(s, id, { collar: collarOverrideOf(v) });
/** The Personality row and its sliders: a whole personality (a preset from `personaNamed`, or what `slide` returns) for one cat. */
export const withPersonality = (s: CatSettings, id: unknown, p: unknown): CatSettings => entryEdited(s, id, { personality: cleanPersonality(p) });
```

- [ ] **Step 5: The section**

```ts title="windows/src/settings/cat.ts" create
// Settings → Cat (spec §4): which cat lives in the notch, how it moves, its personality and the fur lines (the collar rows come with the collar).
// Built from the window's own rows (.row, select, range, .switch); the new rules in settings.css are new class names only. The previews are live
// engines that draw only while this window can be seen: it is created hidden at launch and kept, so a loop that ran all the time would cost CPU
// with Settings closed (cat/loop.ts).

import { BotEngine, catCfg } from "../cat/engine";
import { VisibleLoop } from "../cat/loop";
import { PERSONAS, TRAITS, personaNamed, slide } from "../cat/personality";
import { CAT_IDS, PRESETS } from "../cat/presets";
import {
  FOLLOW, MOTION_STYLES, applyCatSettings, applyToAllCats, cleanCatSettings, withCatMotion, withCharacter, withFurLines, withMotionStyle, withPersonality,
  type CatSettings,
} from "../cat/settings";
import { h } from "../views/dom";

/** What the section needs from the window: the Cat block as it is now, and a place to put the new one. */
export interface CatHost {
  cat(): CatSettings;
  /** `final` is false while a slider is still moving: update, but do not save yet. */
  put(next: CatSettings, final: boolean): void;
}

const CELL = 48;
const PREVIEW_W = 140;
const PREVIEW_H = 150;
const WORDS: Record<string, string> = { playful: "Playful", classic: "Classic" };

function sized(cv: HTMLCanvasElement, w: number, ht: number) {
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  cv.width = Math.round(w * dpr);
  cv.height = Math.round(ht * dpr);
  cv.style.width = `${w}px`;
  cv.style.height = `${ht}px`;
}

function menu(options: readonly (readonly [string, string])[], onChange: (v: string) => void): HTMLSelectElement {
  const el = h("select", {});
  for (const [value, text] of options) el.append(h("option", { value, text }));
  el.addEventListener("change", () => onChange(el.value));
  return el;
}

const row = (label: string, ...controls: (Node | string)[]) => h("div", { class: "row" }, h("label", { text: label }), ...controls);

export function catSection(host: CatHost): { el: HTMLElement; sync(): void } {
  const now = (): CatSettings => cleanCatSettings(host.cat());
  const change = (next: CatSettings, final = true) => {
    host.put(next, final);
    paint();
  };

  // Character: sixteen small live previews, and one big one of the chosen cat.
  const cells = new Map<string, { btn: HTMLButtonElement; cv: HTMLCanvasElement; e: BotEngine }>();
  const grid = h("div", { class: "cat-grid", role: "group", "aria-label": "Character" });
  for (const id of CAT_IDS) {
    const cv = h("canvas", {});
    sized(cv, CELL, CELL);
    const btn = h("button", { class: "cat-cell", "aria-pressed": "false", title: PRESETS[id].desc ? `${PRESETS[id].label} · ${PRESETS[id].desc}` : PRESETS[id].label, onclick: () => change(withCharacter(now(), id)) },
      cv, h("span", { text: PRESETS[id].label }));
    cells.set(id, { btn, cv, e: new BotEngine(PRESETS[id], { mini: true }) });
    grid.append(btn);
  }
  const previewCv = h("canvas", {});
  sized(previewCv, PREVIEW_W, PREVIEW_H);
  const preview = new BotEngine(); // wears catCfg.character: the cat chosen above
  preview.particleOverhang = 40;

  const whose = h("span", { class: "hint" });
  const motion = menu(MOTION_STYLES.map((m) => [m, WORDS[m]] as const), (v) => change(withMotionStyle(now(), v)));
  const catMotion = menu([[FOLLOW, "Follow the global style"], ...MOTION_STYLES.map((m) => [m, WORDS[m]] as const)], (v) => { const s = now(); change(withCatMotion(s, s.character, v)); });
  const catWhose = h("span", { class: "hint" });

  // Personality: a preset menu (Custom shows once a slider has moved) and the six sliders.
  const custom = h("option", { value: "custom", text: "Custom", disabled: true });
  const preset = menu(Object.keys(PERSONAS).map((k) => [k, PERSONAS[k].label] as const), (v) => { const s = now(); change(withPersonality(s, s.character, personaNamed(v))); });
  preset.append(custom);
  const sliders = TRAITS.map(([key, label, low, high]) => {
    const input = h("input", { type: "range", min: "0", max: "1", step: "0.01", value: "0.5", "aria-label": label });
    const move = (final: boolean) => () => {
      const s = now();
      change(withPersonality(s, s.character, slide(s.cats[s.character].personality, key, Number(input.value))), final);
    };
    input.addEventListener("input", move(false));
    input.addEventListener("change", move(true));
    return { key, input, el: row(label, h("span", { class: "hint cat-low", text: low }), input, h("span", { class: "hint cat-high", text: high })) };
  });

  const applied = h("span", { class: "hint" });
  const apply = h("button", { text: "Copy this cat's settings", onclick: () => {
    const s = now();
    change(applyToAllCats(s, s.character));
    applied.textContent = "Done: all 16 cats now move and feel like this one.";
    window.setTimeout(() => { applied.textContent = ""; }, 3000);
  } });

  const fur = h("button", { class: "switch", "aria-pressed": "false", onclick: () => change(withFurLines(now(), !now().furLines)) });

  const paint = () => {
    const s = now(), id = s.character, mine = s.cats[id];
    applyCatSettings(catCfg, s);
    for (const [cid, c] of cells) c.btn.setAttribute("aria-pressed", String(cid === id));
    motion.value = s.motionStyle;
    catMotion.value = mine.motion;
    preset.value = mine.personality.preset;
    for (const sl of sliders) { const v = String(mine.personality[sl.key]); if (sl.input.value !== v) sl.input.value = v; }
    fur.classList.toggle("on", s.furLines);
    fur.setAttribute("aria-pressed", String(s.furLines));
    whose.textContent = catWhose.textContent = `for ${PRESETS[id].label}`;
  };

  const drawOne = (e: BotEngine, cv: HTMLCanvasElement, w: number, ht: number, dt: number) => {
    const ctx = cv.getContext("2d");
    if (!ctx) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, ht);
    e.update(dt);
    e.draw(ctx, w, ht);
  };
  const loop = new VisibleLoop(
    (dt) => {
      for (const c of cells.values()) drawOne(c.e, c.cv, CELL, CELL, dt);
      drawOne(preview, previewCv, PREVIEW_W, PREVIEW_H, dt);
    },
    { raf: (cb) => requestAnimationFrame(cb), caf: (id) => cancelAnimationFrame(id), visible: () => document.visibilityState === "visible" && document.hasFocus() },
  );
  document.addEventListener("visibilitychange", () => loop.sync());
  window.addEventListener("focus", () => loop.sync());
  window.addEventListener("blur", () => loop.sync());

  const el = h("section", {},
    h("h2", {}, h("span", { text: "Cat" })),
    h("div", { class: "hint", text: "Pick the cat that lives in your notch. Each cat keeps its own motion and personality." }),
    h("div", { class: "cat-top" }, grid, h("div", { class: "cat-preview" }, previewCv)),
    row("Motion style", motion, h("span", { class: "hint", text: "Classic moves like the original character." })),
    row("This cat's motion", catMotion, catWhose),
    row("Personality", preset, whose),
    ...sliders.map((sl) => sl.el),
    row("Apply to every cat", apply, applied),
    row("Fur lines", fur, h("span", { class: "hint", text: "Strands on a big cat. Flat colour is the default." })),
  );

  paint();
  loop.sync();
  return { el, sync: paint };
}
```

- [ ] **Step 6: Mount it in the Settings window, and style the new classes**

```ts title="windows/src/settings/main.ts" old
import { keyCheckFailure } from "../core/feature";
```

```ts title="windows/src/settings/main.ts" new
import { keyCheckFailure } from "../core/feature";
import { cleanCatSettings } from "../cat/settings";
import { catSection } from "./cat";
```

```ts title="windows/src/settings/main.ts" old
  clear(root);
  root.append(
    h("h1", {}, h("span", { text: "NotchMeow" }), h("span", { class: "version", text: version })),
```

```ts title="windows/src/settings/main.ts" new
  settings.cat = cleanCatSettings(settings.cat);
  const cat = catSection({
    cat: () => settings.cat,
    put: (next, final) => {
      settings.cat = next;
      if (final) void save();
    },
  });

  clear(root);
  root.append(
    h("h1", {}, h("span", { text: "NotchMeow" }), h("span", { class: "version", text: version })),
```

```ts title="windows/src/settings/main.ts" old
    integrationsSection(present),
    generalSection(),
```

```ts title="windows/src/settings/main.ts" new
    integrationsSection(present),
    cat.el,
    generalSection(),
```

```ts title="windows/src/settings/main.ts" old
  void onEvent<Settings>("settings-changed", (s) => {
    settings = { ...settings, ...s };
  });
```

```ts title="windows/src/settings/main.ts" new
  void onEvent<Settings>("settings-changed", (s) => {
    settings = { ...settings, ...s };
    cat.sync();
  });
```

New rules at the end of `settings.css` (no existing rule changes):

```css title="windows/src/settings/settings.css" old
.hint.warn {
  color: var(--amber);
}
```

```css title="windows/src/settings/settings.css" new
.hint.warn {
  color: var(--amber);
}

/* ── Cat section: the character picker and its live preview ────────────── */

.cat-top {
  display: flex;
  gap: 16px;
  align-items: flex-start;
  flex-wrap: wrap;
}

.cat-grid {
  display: grid;
  grid-template-columns: repeat(4, 56px);
  gap: 6px;
}

.cat-cell {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 2px;
  padding: 4px 0 5px;
  border: 1px solid transparent;
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.05);
  font: 400 10.5px var(--font);
  color: var(--dim);
}

.cat-cell:hover:not(:disabled) {
  background: rgba(255, 255, 255, 0.09);
}

.cat-cell[aria-pressed="true"] {
  border-color: rgba(255, 255, 255, 0.55);
  background: rgba(255, 255, 255, 0.1);
  color: var(--ink);
}

.cat-cell canvas {
  display: block;
  width: 48px;
  height: 48px;
}

.cat-preview {
  width: 140px;
  height: 150px;
  flex: 0 0 auto;
  border-radius: 14px;
  background: #000;
}

.cat-preview canvas {
  display: block;
}

/* The two ends of a trait slider: fixed widths, so the six sliders line up. */
.cat-low {
  min-width: 84px;
  text-align: right;
}

.cat-high {
  min-width: 84px;
}
```

- [ ] **Step 7: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/loop.test.mjs scripts/cat-tests/settings-edit.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 9`, `# pass 9`, `# fail 0`, `tsc exit 0` (no type error before it), then `ℹ tests 115`, `ℹ pass 115`, `ℹ fail 0`.

- [ ] **Step 8: Look at it, in a browser, with no Tauri window**

The Settings page renders outside Tauri with the defaults (every Bridge call is a no-op there). Serve it with Vite alone on a free port, open it headless and screenshot the Cat section. Keep the screenshots in a scratch folder, never in the repository.

```bash
SHOTS="${TMPDIR:-/tmp}/a-tauri-57-shots"; mkdir -p "$SHOTS"; WT="$(git rev-parse --show-toplevel)"
(cd "$WT/windows" && npx --no-install vite --port 14571 > "$SHOTS/vite.log" 2>&1 &)
sleep 3
cd "$SHOTS"
playwright-cli -s=settings open "http://127.0.0.1:14571/settings.html"
playwright-cli -s=settings resize 640 1500
playwright-cli -s=settings run-code "async page => { await page.bringToFront(); await page.waitForTimeout(800); const s = page.locator('section', { has: page.getByRole('heading', { name: 'Cat', exact: true }) }); await s.screenshot({ path: 'cat-section.png' }); }"
playwright-cli -s=settings click "getByRole('button', { name: 'Momo' })"
playwright-cli -s=settings run-code "async page => { await page.waitForTimeout(600); const s = page.locator('section', { has: page.getByRole('heading', { name: 'Cat', exact: true }) }); await s.screenshot({ path: 'cat-momo.png' }); }"
playwright-cli -s=settings close
kill $(lsof -ti tcp:14571) 2>/dev/null; ls "$SHOTS"
```

Expected: `cat-momo.png  cat-section.png  vite.log` in the folder (and a `.playwright-cli` folder, which `ls` hides). Open both. The browser console has one error, the missing `favicon.ico`, and nothing else. `cat-section.png`: the heading "Cat"; sixteen cells in a 4 by 4 grid, Shrimpy first and Momo second, each with its small live cat and its name, Shrimpy outlined as the chosen one; a black preview box to the right with a big Shrimpy; then the rows Motion style (Playful), This cat's motion (Follow the global style), Personality (Balanced) and six sliders at the middle, Apply to every cat, Fur lines (off). `cat-momo.png`: Momo is outlined and the big preview is Momo, the "for …" hints say Momo, and the sliders are still at the middle. If a cell is blank, a cat is cut off at the top or the layout overflows the window, fix `cat.ts` or the CSS and look again. Say what you saw to the controller.

- [ ] **Step 9: Commit**

```bash
git add windows/src/cat/loop.ts windows/src/cat/settings.ts windows/src/settings/cat.ts windows/src/settings/main.ts windows/src/settings/settings.css windows/scripts/cat-tests/loop.test.mjs windows/scripts/cat-tests/settings-edit.test.mjs
git commit -m "feat(settings): the Cat section: character, motion, personality and fur lines, with live previews

Sixteen small previews and a big one animate only while the Settings window can be seen. Each row edits one thing through
a pure helper that returns a clean value. New CSS rules only; no existing row changes.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Checkpoint 1: the owner looks at the Settings Cat section

**Owner checkpoint** (the executing session; no agent). Stage 5 is done when the owner says so.

- [ ] Send the owner, in the chat, `cat-section.png` and `cat-momo.png` from Task 4 Step 8, with four lines of text: the section is built from the Settings window's own rows, so nothing else in Settings moved; the sixteen cells and the big preview are live cats, and they are drawn only while the window can be seen and has focus; Shrimpy is first and Momo second, as the spec says; **Fur lines show only on a big cat** (the renderer draws strands when the head's radius is 30 px or more, which is a head of about Ø70), and the biggest cat in the island is Ø66, so the switch is visible in this preview only (see the open questions).
- [ ] Say what the owner should check by hand in a real build (`cd windows && npm run tauri dev`, on Windows or Linux): Settings → Cat: pick Momo, and the island's cat, the pills and the drop view become Momo with no restart; move a slider, close Settings, reopen it, and the slider and "Custom" are where they were left; quit and start the app again, and the choice is still Momo (it is in `settings.json`, `cat` block); edit `settings.json` by hand to put junk in the `cat` block (`"cat": 5`, or a trait of `"high"`) and start the app: it loads with the default cat and the rest of the file intact, and no `settings.json.bad-…` file appears; with Settings **closed**, Task Manager shows the app at 0 % CPU with the island hidden (the previews stop when the window is hidden), and with Settings open but another window focused the previews stand still.
- [ ] Wait for the owner's OK. Do not start Task 5 before it.

---

# Stage 6: the collar, searching and sleeping, the music bob

### Task 5: Gemini CLI and Antigravity get the Mac's pill colours

**Agent:** `nm-implementer-light`.

The collar is drawn from `task.color`. Today the Windows app gives the two external agents a colour by hashing their name into four fallback colours (`hooks.ts`, `agentColor`), so **Gemini CLI is pink and Antigravity is green**, while the Mac's `PillCatalog` has Gemini CLI `#8AB4F8` (blue) and Antigravity `#E879F9` (pink). The owner decided on 2026-10-06 that Windows gets the Mac's two colours in this stage, so their collars have a colour that means the same on both apps. This is the one change in this plan to how an existing view looks: those two pills (their tinted border, hover glow and badge) change colour. Pill IDs do not change: `agent_gemini` and `agent_antigravity` are frozen contract values, and the relay's `--agent gemini` and `--agent antigravity` still make them.

**Files:**
- Create: `windows/src/core/pills.ts`, `windows/scripts/cat-tests/pills.test.mjs`
- Modify: `windows/src/island/hooks.ts` (the import, and the hashing function moves out)

**Interfaces:**
- Consumes: `NotchBuddy/Sources/App/PillCatalog.swift` (read by the test: the Mac's colours are the reference) and `windows/hook/src/agents.rs` (the relay's agent tags).
- Produces `src/core/pills.ts`: `AGENT_PILL_COLORS` (`agent_gemini`, `agent_antigravity`) and `agentColor(name)`: a known agent's pill colour, else the same stable hash colour as before (so an agent started with `--agent my-agent` keeps the colour it has today). Loadable in plain Node (no DOM, no imports).

- [ ] **Step 1: Write the failing tests**

```js title="windows/scripts/cat-tests/pills.test.mjs" create
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { AGENT_PILL_COLORS, agentColor } from "../../src/core/pills.ts";

const read = (rel) => fs.readFileSync(new URL(rel, import.meta.url), "utf8");
const swift = read("../../../NotchBuddy/Sources/App/PillCatalog.swift");
const relay = read("../../hook/src/agents.rs");

test("the agent pills have the Mac's colours, as PillCatalog.swift declares them", () => {
  assert.deepEqual(Object.keys(AGENT_PILL_COLORS), ["agent_gemini", "agent_antigravity"]);
  for (const [id, color] of Object.entries(AGENT_PILL_COLORS)) {
    const m = swift.match(new RegExp(`id:\\s*"${id}",[^\\n]*?color:\\s*"(#[0-9A-Fa-f]{6})"`));
    assert.ok(m, `${id} is in PillCatalog.swift`);
    assert.equal(color, m[1].toUpperCase(), id);
  }
});

test("the pill IDs are the relay's agent tags behind agent_, and they are frozen", () => {
  const tags = [...relay.matchAll(/pub const (?:GEMINI|ANTIGRAVITY): &str = "([a-z-]+)";/g)].map((m) => m[1]);
  assert.deepEqual(tags, ["gemini", "antigravity"]);
  assert.deepEqual(Object.keys(AGENT_PILL_COLORS), tags.map((t) => `agent_${t}`));
});

test("agentColor: a known agent wears its pill's colour, any other keeps the stable colour it always had, odd names are just names", () => {
  assert.equal(agentColor("gemini"), "#8AB4F8");
  assert.equal(agentColor("antigravity"), "#E879F9");
  assert.equal(agentColor("my-agent"), "#22C55E", "the hashed colours of other agents are what they were");
  assert.equal(agentColor("codex"), "#E879F9");
  assert.equal(agentColor("cursor"), "#60A5FA");
  for (const odd of ["constructor", "__proto__", "toString", "hasOwnProperty", "agent_gemini", ""]) assert.match(agentColor(odd), /^#[0-9A-F]{6}$/, odd);
  assert.equal(agentColor("gemini"), agentColor("gemini"), "stable");
});

test("hooks.ts gives the pill it creates that colour, and no longer hashes by itself", () => {
  const hooks = read("../../src/island/hooks.ts");
  assert.match(hooks, /import \{ agentColor \} from "\.\.\/core\/pills\.ts";/);
  assert.match(hooks, /State\.upsertExternalAgent\(agentId, validAgent!, agentColor\(validAgent!\)\)/);
  assert.doesNotMatch(hooks, /FALLBACK_COLORS/, "the hash lives in pills.ts only");
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/pills.test.mjs 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|^# (tests|pass|fail)"; cd ..`
Expected: `ERR_MODULE_NOT_FOUND` for `src/core/pills.ts` and `# fail 1`.

- [ ] **Step 3: The colours, in one small module**

```ts title="windows/src/core/pills.ts" create
// The colours of the agent pills. The Mac's PillCatalog (NotchBuddy/Sources/App/PillCatalog.swift) is the reference: a collar is drawn from a
// task's colour, so the same agent must have the same colour on both apps. Pill IDs are frozen contract values: `agent_<tag>` for the tag a
// relay puts in `nm_agent` (windows/hook/src/agents.rs). No imports, so the plain-Node checks can load it.

/** The pills of the two agents that have a relay tag (`--agent gemini`, `--agent antigravity`). */
export const AGENT_PILL_COLORS: Readonly<Record<string, string>> = {
  agent_gemini: "#8AB4F8",
  agent_antigravity: "#E879F9",
};

/** What any other tagged agent gets: a stable pick by name, as before the collar. */
const FALLBACK_COLORS = ["#22C55E", "#EAB308", "#60A5FA", "#E879F9"];

/** The colour of the pill for `nm_agent` = `name`: its catalogue colour, else a stable hash of the name. */
export function agentColor(name: string): string {
  const id = `agent_${name}`;
  if (Object.hasOwn(AGENT_PILL_COLORS, id)) return AGENT_PILL_COLORS[id];
  let h = 0;
  for (let i = 0; i < name.length; i++) {
    h = (Math.imul(31, h) + name.charCodeAt(i)) | 0;
  }
  return FALLBACK_COLORS[Math.abs(h) % FALLBACK_COLORS.length];
}
```

```ts title="windows/src/island/hooks.ts" old
import { approvalTarget, lastPathComponent, stepLabel } from "../core/steps.ts";
```

```ts title="windows/src/island/hooks.ts" new
import { agentColor } from "../core/pills.ts";
import { approvalTarget, lastPathComponent, stepLabel } from "../core/steps.ts";
```

```ts title="windows/src/island/hooks.ts" old
const FALLBACK_COLORS = ["#22C55E", "#EAB308", "#60A5FA", "#E879F9"];

function agentColor(name: string): string {
  let h = 0;
  for (let i = 0; i < name.length; i++) {
    h = (Math.imul(31, h) + name.charCodeAt(i)) | 0;
  }
  return FALLBACK_COLORS[Math.abs(h) % FALLBACK_COLORS.length];
}

const PROJECT_ALIASES: Record<string, string> = {
```

```ts title="windows/src/island/hooks.ts" new
const PROJECT_ALIASES: Record<string, string> = {
```

- [ ] **Step 4: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/pills.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 4`, `# pass 4`, `# fail 0`, `tsc exit 0`, then `ℹ tests 119`, `ℹ pass 119`, `ℹ fail 0`.

- [ ] **Step 5: Commit**

```bash
git add windows/src/core/pills.ts windows/src/island/hooks.ts windows/scripts/cat-tests/pills.test.mjs
git commit -m "feat(pills): Gemini CLI and Antigravity wear the Mac's pill colours on Windows and Linux

agent_gemini is #8AB4F8 and agent_antigravity #E879F9, as PillCatalog.swift has them, so a collar means the same agent on both
apps. Other tagged agents keep their hashed colour. The pill IDs are unchanged.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 6: The collar's geometry, from the contract

**Agent:** `nm-implementer-light`.

**Files:**
- Create: `windows/src/cat/collar.ts`, `windows/scripts/cat-tests/collar.test.mjs`

**Interfaces:**
- Consumes: `tests/fixtures/cat/collar-cases.json` (`styles`, `min`, `resolve`, and 164 `cases` of cat, kitten, style, head width, pixel ratio and pose, each with its `out`) and `geometry-cases.json` (`collarPass`, `passes`); `layout`, `supPoints`, `newPose`, `PASSES` from `geometry.ts`; `COLLAR_STYLES` and `collarStyleOf` from `settings.ts` (Task 1).
- Produces `src/cat/collar.ts`, with the contract's names: `COLLAR_STYLES` and `collarStyleOf` (re-exported), `COLLAR_MIN` (`{ band: 3, tag: 6, kerchiefW: 7, kerchiefDrop: 5 }`, in **device** pixels), `COLLAR_PASS` (`"front"`), and `collarGeometry(p, s, D, style, { dpr, detail })`: `null` for `off` (or an unknown style), else `{ style, R, width, band, tag }` for `tag`, `{ style, R, width, band }` for `band` and `{ style, R, kerchief: { pts, apex } }` for `kerchief`, in head-local px (before the tilt and the squash), turning with the face warp. The types `CollarGeometry` and `CollarOptions`. Loadable in plain Node.

Why the pixel ratio is an input: the floors are in device pixels (a band at least 3 px thick, a tag 6 px across, a neckerchief 7 px wide and 5 px deep), so a head of Ø12 on a 2× screen can have a band that is 1.5 CSS px thick. The renderer passes `min(2, devicePixelRatio)`, as the island's canvases are sized.

- [ ] **Step 1: Write the failing tests**

```js title="windows/scripts/cat-tests/collar.test.mjs" create
import test from "node:test";
import assert from "node:assert/strict";
import { COLLAR_MIN, COLLAR_PASS, COLLAR_STYLES, collarGeometry, collarStyleOf } from "../../src/cat/collar.ts";
import { PASSES, newPose } from "../../src/cat/geometry.ts";
import { CAT_IDS, PRESETS, kittenOf } from "../../src/cat/presets.ts";
import { finite, load, same } from "./util.mjs";

// The collar's geometry, replayed from tests/fixtures/cat/collar-cases.json (A-0b), and the facts the contract's own tests check.
const fx = load("collar-cases.json");
const geo = load("geometry-cases.json");
const pose = (o = {}) => ({ ...newPose(), ...o });
const STYLES = ["tag", "band", "kerchief"]; // the three that draw something; "off" draws nothing
const onHead = (pts, p, R, k = 1.02) => pts.every(([x, y]) => (x / (p.rx * R)) ** 2 + (y / (p.ry * R)) ** 2 <= k * k);

test("the four style IDs, the floors and the pass are the fixture's, and an unknown stored style is off", () => {
  assert.deepEqual([...COLLAR_STYLES], fx.styles);
  assert.deepEqual([...COLLAR_STYLES], ["tag", "band", "kerchief", "off"]);
  assert.deepEqual({ ...COLLAR_MIN }, fx.min);
  for (const r of fx.resolve) assert.equal(collarStyleOf(r.id), r.style, String(r.id));
  assert.equal(COLLAR_PASS, geo.collarPass);
  assert.deepEqual(PASSES, geo.passes, "PASSES is the line A-0 wrote");
  const front = PASSES[COLLAR_PASS];
  assert.equal(front.indexOf("whiskers"), front.indexOf("foldEars") + 1, "the collar's slot: between the folded ears and the whiskers");
});

test("every case of collar-cases.json replays from its own inputs: each style, at Ø12 to Ø66, at pixel ratio 1 and 2, at rest and with the head turned", () => {
  assert.ok(fx.cases.length >= 100);
  for (const k of fx.cases) {
    const p = k.kitten ? kittenOf(PRESETS[k.cat]) : PRESETS[k.cat];
    same(collarGeometry(p, pose(k.pose), k.D, k.style, { dpr: k.dpr }), k.out, `${k.cat}${k.kitten ? " kitten" : ""} ${k.style} D${k.D} dpr${k.dpr}`);
  }
  for (const style of STYLES) for (const D of [12, 20, 66]) for (const dpr of [1, 2]) assert.ok(fx.cases.some((k) => k.style === style && k.D === D && k.dpr === dpr), `${style} D${D} dpr${dpr} is in the fixture`);
  assert.ok(fx.cases.some((k) => k.style === "off" && k.out === null), "off is in the fixture");
});

test("the readability floors hold at Ø12 to Ø20 and at any pixel density: band 3 px, tag 6 px across, neckerchief 7 wide and 5 deep (device pixels)", () => {
  for (const dpr of [1, 2, 3]) for (const D of [12, 16, 20]) for (const style of STYLES) {
    const g = collarGeometry(PRESETS.shrimpy, pose(), D, style, { dpr });
    if (style !== "kerchief") assert.ok(g.width * dpr >= COLLAR_MIN.band - 1e-9, `band ${g.width * dpr} at D${D} dpr${dpr}`);
    if (style === "tag") assert.ok(g.tag.r * 2 * dpr >= COLLAR_MIN.tag - 1e-9, `tag at D${D} dpr${dpr}`);
    if (style === "kerchief") {
      const xs = g.kerchief.pts.map((q) => q[0]);
      assert.ok((Math.max(...xs) - Math.min(...xs)) * dpr >= COLLAR_MIN.kerchiefW - 1e-9, `kerchief width at D${D} dpr${dpr}`);
      assert.ok((g.kerchief.apex[1] - Math.max(...g.kerchief.pts.map((q) => q[1]))) * dpr >= COLLAR_MIN.kerchiefDrop - 1e-9, `kerchief drop at D${D} dpr${dpr}`);
    }
  }
});

test("off draws nothing, an unknown style is off, and each style has exactly its own parts", () => {
  for (const style of ["off", "scarf", "", null, undefined, 7, "follow"]) assert.equal(collarGeometry(PRESETS.momo, pose(), 40, style), null, String(style));
  const g = (style) => collarGeometry(PRESETS.momo, pose(), 40, style);
  assert.deepEqual(Object.keys(g("tag")).sort(), ["R", "band", "style", "tag", "width"]);
  assert.deepEqual(Object.keys(g("band")).sort(), ["R", "band", "style", "width"]);
  assert.deepEqual(Object.keys(g("kerchief")).sort(), ["R", "kerchief", "style"]);
  assert.equal(g("tag").band.length, 26);
  assert.ok(g("kerchief").kerchief.pts.length > 4);
  for (const style of STYLES) assert.equal(g(style).style, style);
});

test("large sizes scale with the head: the band a tenth of R, the tag 0.16 R, the neckerchief about 0.34 R deep", () => {
  const at = (style) => collarGeometry(PRESETS.momo, pose(), 66, style);
  assert.ok(Math.abs(at("band").width / at("band").R - 0.1) < 1e-9);
  assert.ok(Math.abs(at("tag").tag.r / at("tag").R - 0.16) < 1e-9);
  const k = at("kerchief"), drop = k.kerchief.apex[1] - Math.max(...k.kerchief.pts.map((q) => q[1]));
  assert.ok(drop >= 0.34 * k.R - 1e-9 && drop < 0.36 * k.R, `the drop is ${drop / k.R} R`);
});

test("every coat, style, pose and size, at either pixel density: the collar is finite and stays on the head", () => {
  for (const id of CAT_IDS) for (const style of STYLES) for (const s of [pose(), pose({ yaw: 0.6 }), pose({ yaw: -0.6, pitch: 0.4 }), pose({ pitch: -0.3 })]) for (const D of [12, 20, 28, 66]) for (const dpr of [1, 2]) {
    const g = collarGeometry(PRESETS[id], s, D, style, { dpr });
    finite(g, `${id} ${style} D${D}`);
    assert.ok(onHead(g.band || g.kerchief.pts, PRESETS[id], g.R), `${id} ${style} D${D} dpr${dpr}`);
  }
});

test("a head of width 0, or a bad pixel ratio, never produces NaN, and a bad ratio means 2", () => {
  for (const style of STYLES) {
    finite(collarGeometry(PRESETS.shrimpy, pose(), 0, style), `${style} at Ø0`);
    const two = collarGeometry(PRESETS.momo, pose(), 20, style, { dpr: 2 });
    for (const dpr of [NaN, 0, -1, undefined, null, "2"]) assert.deepEqual(collarGeometry(PRESETS.momo, pose(), 20, style, { dpr }), two, `${style} dpr ${dpr}`);
  }
});

test("the tag sits at centre front at rest and follows the face when the head turns; the pose is left alone", () => {
  const p = PRESETS.shrimpy, rest = collarGeometry(p, pose(), 66, "tag"), turned = collarGeometry(p, pose({ yaw: 0.6 }), 66, "tag");
  assert.ok(Math.abs(rest.tag.x) < 1e-9 && rest.tag.y > 0);
  assert.ok(turned.tag.x > rest.tag.x + 1, "the tag moves toward the side the face turned to");
  assert.ok(Math.abs(collarGeometry(p, pose(), 66, "kerchief").kerchief.apex[0]) < 1e-9, "the neckerchief points straight down at rest");
  const s = pose({ yaw: 0.3 }), before = JSON.stringify(s);
  assert.deepEqual(collarGeometry(PRESETS.momo, s, 28, "kerchief"), collarGeometry(PRESETS.momo, s, 28, "kerchief"));
  assert.equal(JSON.stringify(s), before);
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/collar.test.mjs 2>&1 | grep -E "ERR_MODULE_NOT_FOUND|^# (tests|pass|fail)"; cd ..`
Expected: `ERR_MODULE_NOT_FOUND` for `src/cat/collar.ts` and `# fail 1`.

- [ ] **Step 3: Port the geometry**

```ts title="windows/src/cat/collar.ts" create
// The collar: the agent colour, worn as a thin collar (spec §3 and §4; A-0b). A port of `collarGeometry` in design/prototype/cat-core.js, the
// tie-breaker (fixture tests/fixtures/cat/collar-cases.json; docs/CAT-CONTRACT.md "Collar, ear fit and flat fills"). Pure maths: the renderer
// paints what collarGeometry returns, in the front pass between the folded ears and the whiskers. The style IDs are frozen contract values
// (`tag`, `band`, `kerchief`, `off`); they live in settings.ts with the other stored words and are re-exported here under the contract's names.
// Imports only geometry.ts and settings.ts, so the plain-Node checks (npm run check:cat) can load it.

import { layout, supPoints } from "./geometry.ts";
import { collarStyleOf } from "./settings.ts";
import type { CollarStyle } from "./settings.ts";
import type { CatPreset, Pose } from "./types.ts";

export { COLLAR_STYLES, collarStyleOf } from "./settings.ts";

/** Smallest sizes, in DEVICE pixels, so a collar still reads as a colour at Ø12 and Ø20. */
export const COLLAR_MIN = { band: 3, tag: 6, kerchiefW: 7, kerchiefDrop: 5 } as const;
/** The renderer pass the collar is drawn in: between `foldEars` and `whiskers` of `PASSES.front`. `PASSES` itself stays as A-0 wrote it. */
export const COLLAR_PASS = "front";

type Pt = readonly [number, number];

/** Where one collar sits, in head-local px (before the tilt and the squash). Which parts are there depends on the style. */
export interface CollarGeometry {
  style: Exclude<CollarStyle, "off">;
  R: number;
  /** tag and band: the band's stroke width, a tenth of R and never under COLLAR_MIN.band device px. */
  width?: number;
  /** tag and band: a polyline along the lower outline, left to right, inset so its outer edge stays inside the head. */
  band?: Pt[];
  /** tag: a round tag at centre front. */
  tag?: { x: number; y: number; r: number };
  /** kerchief: a triangle under the chin, `pts` along the lower outline and `apex` below them. */
  kerchief?: { pts: Pt[]; apex: Pt };
}

export interface CollarOptions {
  /** The device pixel ratio, default 2 (and 2 for anything that is not above 0). */
  dpr?: number;
  /** As in layout(). */
  detail?: "full" | "compact";
}

/** The collar of one cat, or null for `off` (an unknown style is `off`). Turns with the face warp; D is the head width in px. */
export function collarGeometry(p: CatPreset, s: Pose, D: number, style: unknown, o: CollarOptions = {}): CollarGeometry | null {
  const id = collarStyleOf(style);
  if (id === "off") return null;
  const dpr = typeof o.dpr === "number" && o.dpr > 0 ? o.dpr : 2;
  const { R, W } = layout(p, s, 0, 0, D, { detail: o.detail });
  const px = (n: number) => n / dpr / R; // device px to R-units
  const width = Math.max(0.1 * R, COLLAR_MIN.band / dpr);
  const k = Math.max(0.7, Math.min(0.92, 1 - (width / 2 + 0.5 / dpr) / (p.ry * R)));
  const N = 90;
  const ring = supPoints(p.rx * k, p.ry * k, p.n, 0, 0, 0, N).slice(0, N); // R-units; index i is angle i/N of a turn, y down
  const out: CollarGeometry = { style: id, R };
  if (id === "kerchief") {
    const hw = Math.min(p.rx * k, Math.max(0.5 * p.rx, px(COLLAR_MIN.kerchiefW) * 0.65));
    const arc = ring.filter(([x, y]) => y > 0 && Math.abs(x) <= hw).sort((a, b) => a[0] - b[0]);
    const [ax, ay] = W(0, p.ry * k);
    const top = Math.max(...arc.map((q) => W(...q)[1]));
    out.kerchief = { pts: arc.map((q) => W(...q)), apex: [ax, Math.max(ay, top) + Math.max(0.34 * R, COLLAR_MIN.kerchiefDrop / dpr)] };
  } else {
    const lower = ring.slice((N * 40) / 360, (N * 140) / 360 + 1).reverse(); // left to right, 40° to 140°
    out.width = width;
    out.band = lower.map(([x, y]) => W(x, y));
    if (id === "tag") {
      const [x, y] = W(0, p.ry * k);
      out.tag = { x, y, r: Math.max(0.16 * R, COLLAR_MIN.tag / dpr / 2) };
    }
  }
  return out;
}
```

- [ ] **Step 4: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/collar.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 8`, `# pass 8`, `# fail 0`, `tsc exit 0`, then `ℹ tests 127`, `ℹ pass 127`, `ℹ fail 0`.

- [ ] **Step 5: Prove the replay bites (not committed)**

```bash
python3 - <<'PY'
p = 'windows/src/cat/collar.ts'
s = open(p, encoding='utf-8').read()
was = 'const width = Math.max(0.1 * R, COLLAR_MIN.band / dpr);'
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, 'const width = Math.max(0.1 * R, 0);'))
PY
(cd windows && node --experimental-strip-types --test scripts/cat-tests/collar.test.mjs 2>&1 | grep -E "^not ok|^# (pass|fail)")
python3 - <<'PY'
p = 'windows/src/cat/collar.ts'
s = open(p, encoding='utf-8').read()
was = 'const width = Math.max(0.1 * R, 0);'
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, 'const width = Math.max(0.1 * R, COLLAR_MIN.band / dpr);'))
PY
(cd windows && node --experimental-strip-types --test scripts/cat-tests/collar.test.mjs 2>&1 | grep -E "^# (pass|fail)")
```

Expected: first run lists `not ok 2 - every case of collar-cases.json replays…` and `not ok 3 - the readability floors hold…`, then `# pass 6` and `# fail 2`; after putting the line back, `# pass 8` and `# fail 0`.

- [ ] **Step 6: Commit**

```bash
git add windows/src/cat/collar.ts windows/scripts/cat-tests/collar.test.mjs
git commit -m "feat(cat): the collar's geometry, ported from the contract and replayed from collar-cases.json

tag, band and kerchief at every size from Ø12 up, with the device-pixel readability floors. Pure maths: the renderer paints it next.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 7: The renderer paints the collar, in the front pass, at every size from Ø12 up

**Agent:** `nm-implementer`.

**Files:**
- Modify: `windows/src/cat/renderer.ts` (the option, the painter, the front pass), `windows/scripts/cat-tests/fake-canvas.mjs` (it also records stroke colours and line widths)
- Create: `windows/scripts/cat-tests/collar-draw.test.mjs`

**Interfaces:**
- Consumes: Task 6's `collarGeometry`; the page's `drawCollar` and `tintW` in `design/prototype/notchmeow.html` (the reference for the look, which is not tested).
- Produces: `DrawOptions.collar?: { style: string; col: string } | null`: the style (`tag`, `band`, `kerchief`; `off` or anything else draws nothing) and the agent's colour as `#RRGGBB` (a colour that is not draws nothing, and never throws), and `DrawOptions.dpr?: number`, the device pixel ratio the readability floors are in (default `min(2, devicePixelRatio)`, 1 outside a browser). The collar is painted in the **front** pass, over the head and the folded ears and under the whiskers, in the head's own frame, so it tilts, squashes and turns with the face. The coat is never recoloured. The fake canvas now also records `seen.strokeStyles` and `seen.lineWidths`.

- [ ] **Step 1: Write the failing tests**

```js title="windows/scripts/cat-tests/fake-canvas.mjs" old
  const calls = {}, seen = { fillStyles: [], ellipses: [] };
```

```js title="windows/scripts/cat-tests/fake-canvas.mjs" new
  const calls = {}, seen = { fillStyles: [], ellipses: [], strokeStyles: [], lineWidths: [] };
```

```js title="windows/scripts/cat-tests/fake-canvas.mjs" old
      if (k === "fillStyle" && typeof v === "string") seen.fillStyles.push(v);
```

```js title="windows/scripts/cat-tests/fake-canvas.mjs" new
      if (k === "fillStyle" && typeof v === "string") seen.fillStyles.push(v);
      if (k === "strokeStyle" && typeof v === "string") seen.strokeStyles.push(v);
      if (k === "lineWidth" && typeof v === "number") seen.lineWidths.push(v);
```

```js title="windows/scripts/cat-tests/collar-draw.test.mjs" create
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { drawBehindPass, drawCat, drawFrontPass, drawHeadPass, frameOf, stillView } from "../../src/cat/renderer.ts";
import { newPose } from "../../src/cat/geometry.ts";
import { CAT_IDS, PRESETS, kittenOf } from "../../src/cat/presets.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

installBrowserStubs();
const STYLES = ["tag", "band", "kerchief"];
const COL = "#8AB4F8";
const draw = (p, D, collar, extra = {}) => { const ctx = fakeCanvas(); drawCat(ctx, stillView(p, newPose()), 100, 80, D, { collar, dpr: 2, ...extra }); return ctx; };
const total = (ctx) => Object.values(ctx.calls).reduce((a, b) => a + b, 0);

test("every coat and kitten wears every style at every size from Ø12 up, with only finite numbers, and it adds drawing", () => {
  for (const id of CAT_IDS) for (const kit of [false, true]) for (const D of [12, 16, 20, 28, 40, 66]) for (const style of STYLES) for (const dpr of [1, 2]) {
    const p = kit ? kittenOf(PRESETS[id]) : PRESETS[id];
    const bare = draw(p, D, null, { dpr }), worn = draw(p, D, { style, col: COL }, { dpr });
    assert.ok(total(worn) > total(bare), `${id}${kit ? " kitten" : ""} Ø${D} ${style}: something was added`);
    assert.ok((worn.calls.stroke || 0) > (bare.calls.stroke || 0), `${id} Ø${D} ${style}: it strokes an edge`);
    assert.equal(worn.calls.save, worn.calls.restore, "every save is restored");
  }
});

test("off, no collar and a colour that is not #RRGGBB draw nothing and never throw", () => {
  const p = PRESETS.momo, bare = draw(p, 40, undefined);
  for (const collar of [null, undefined, { style: "off", col: COL }, { style: "scarf", col: COL }, { style: "", col: COL }, { style: "tag", col: "red" }, { style: "tag", col: "#FFF" },
    { style: "band", col: "" }, { style: "band", col: "#GGGGGG" }, { style: "kerchief", col: 7 }, { style: "kerchief", col: null }, { style: "tag" }]) {
    assert.deepEqual(draw(p, 40, collar).calls, bare.calls, JSON.stringify(collar));
  }
});

test("the collar is in the front pass only: the behind pass and the head are drawn as without it", () => {
  const view = () => stillView(PRESETS.shrimpy, newPose());
  const count = (collar) => {
    const f = frameOf(view(), 100, 80, 66, { collar, dpr: 2 }), behind = fakeCanvas(), head = fakeCanvas(), front = fakeCanvas();
    drawBehindPass(behind, f); drawHeadPass(head, f); drawFrontPass(front, f);
    return { behind: total(behind), head: total(head), front: total(front) };
  };
  const bare = count(null), worn = count({ style: "tag", col: COL });
  assert.equal(worn.behind, bare.behind);
  assert.equal(worn.head, bare.head);
  assert.ok(worn.front > bare.front);
});

test("the collar sits between the folded ears and the whiskers (the contract's collarPass), and the coat is never recoloured", () => {
  const src = fs.readFileSync(new URL("../../src/cat/renderer.ts", import.meta.url), "utf8");
  const ears = src.indexOf("if (p.ear.fold) for (const ear of L.ears) drawEar(c, p, ear, R, full, flat, true);");
  const collar = src.indexOf("drawCollar(c, G, o.collar.col, full, dpr)");
  const whiskers = src.indexOf("// Whiskers rooted on the pad grid");
  assert.ok(ears > 0 && collar > ears && whiskers > collar, `${ears} < ${collar} < ${whiskers}`);
  const a = draw(PRESETS.latte, 28, null), b = draw(PRESETS.latte, 28, { style: "band", col: "#FF0000" });
  assert.deepEqual(b.seen.fillStyles, a.seen.fillStyles, "no fill of the coat changes: a band is stroked");
});

test("the readability floors reach the canvas: at Ø12 on a 1x screen the band is 3 px, on a 2x screen 1.5 CSS px, and its dark edge is 2 device px wider", () => {
  const widths = (dpr) => draw(PRESETS.shrimpy, 12, { style: "band", col: COL }, { dpr }).seen.lineWidths;
  assert.ok(widths(1).includes(3) && widths(1).includes(5), String(widths(1)));
  assert.ok(widths(2).includes(1.5) && widths(2).includes(2.5), String(widths(2)));
  assert.ok(draw(PRESETS.shrimpy, 12, { style: "tag", col: COL }, { dpr: 1 }).seen.strokeStyles.includes(COL), "the band is painted in the agent's colour");
});

test("without a dpr option the screen's pixel ratio is used, at most 2, and 1 outside a browser", () => {
  const band = (g) => { globalThis.devicePixelRatio = g; try { return draw(PRESETS.shrimpy, 12, { style: "band", col: COL }, { dpr: undefined }).seen.lineWidths; } finally { delete globalThis.devicePixelRatio; } };
  assert.ok(band(undefined).includes(3), "no ratio: 1");
  assert.ok(band(1.25).includes(3 / 1.25), "a 1.25 screen");
  assert.ok(band(3).includes(1.5), "a 3x screen is held to 2");
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/collar-draw.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; cd ..`
Expected: `# tests 6`, `# pass 1`, `# fail 5` (the renderer ignores `collar` yet; only the test that a bad collar draws nothing passes).

- [ ] **Step 3: Paint it**

```ts title="windows/src/cat/renderer.ts" old
import { FLAT_FILL, MOMO_WHITE, detailLevel, earFit, earScale, flatFillColors, layout, pupilOffset, supPoints } from "./geometry.ts";
```

```ts title="windows/src/cat/renderer.ts" new
import { collarGeometry } from "./collar.ts";
import type { CollarGeometry } from "./collar.ts";
import { FLAT_FILL, MOMO_WHITE, detailLevel, earFit, earScale, flatFillColors, layout, pupilOffset, supPoints } from "./geometry.ts";
```

```ts title="windows/src/cat/renderer.ts" old
  earCeiling?: number;
}

/** A cat that never moves: icons, the contact sheet's first frame and tests. */
```

```ts title="windows/src/cat/renderer.ts" new
  earCeiling?: number;
  /**
   * The agent's collar (stage 6): a style (`tag`, `band` or `kerchief`; `off` or anything else draws nothing) and its colour as "#RRGGBB" (anything
   * else draws nothing). Drawn in the front pass, from the contract's `collarGeometry`, at every size from Ø12 up.
   */
  collar?: { style: string; col: string } | null;
  /** The device pixel ratio the collar's readability floors are in: default `min(2, devicePixelRatio)`, and 1 where there is no screen. */
  dpr?: number;
}

/** The ratio to size a collar for: the option, else the screen's (held to 2, as the canvases are sized). */
const dprOf = (o: DrawOptions): number =>
  typeof o.dpr === "number" && o.dpr > 0 ? o.dpr : Math.min(2, (typeof devicePixelRatio === "number" && devicePixelRatio) || 1);

/** A cat that never moves: icons, the contact sheet's first frame and tests. */
```

```ts title="windows/src/cat/renderer.ts" old
/** The front pass: a Scottish Fold's flaps, the whiskers, then the badge, the particles and the hairballs. */
```

```ts title="windows/src/cat/renderer.ts" new
/** A "#RRGGBB" colour lightened toward white by k (0 to 1), as "rgb()". */
const tintW = (h: string, k: number): string => `rgb(${hex(h).map((v) => Math.round(v + (255 - v) * k))})`;
const HEX6 = /^#[0-9A-Fa-f]{6}$/;

/**
 * Paints a collar in the head's own frame. The maths is `collarGeometry`; this only paints it: the agent's colour with a thin dark edge so a light
 * collar stays apart from a light coat, a lighter tag, and at full detail a crease on the neckerchief and a shine on the tag. The page's `drawCollar`
 * is the reference for the look (it is not tested).
 */
function drawCollar(c: Ctx, G: CollarGeometry, col: string, full: boolean, dpr: number) {
  const e1 = 1 / dpr, edge = "rgba(0,0,0,.42)";
  const poly = (pts: readonly (readonly [number, number])[]) => { c.beginPath(); pts.forEach(([x, y], i) => (i ? c.lineTo(x, y) : c.moveTo(x, y))); };
  c.save(); c.lineCap = "round"; c.lineJoin = "round";
  if (G.kerchief) {
    const S = G.kerchief;
    poly([...S.pts, S.apex]); c.closePath(); c.fillStyle = col; c.fill(); c.strokeStyle = edge; c.lineWidth = 1.5 * e1; c.stroke();
    if (full) {
      const m = S.pts[S.pts.length >> 1];
      c.strokeStyle = tintW(col, 0.45); c.lineWidth = Math.max(e1, G.R * 0.025);
      poly([[m[0], m[1] + G.R * 0.05], [S.apex[0], S.apex[1] - G.R * 0.08]]); c.stroke();
    }
  } else if (G.band) {
    const w = G.width ?? 0;
    poly(G.band); c.strokeStyle = edge; c.lineWidth = w + 2 * e1; c.stroke(); c.strokeStyle = col; c.lineWidth = w; c.stroke();
    if (G.tag) {
      const T = G.tag;
      c.beginPath(); c.arc(T.x, T.y, T.r, 0, TAU); c.fillStyle = tintW(col, 0.55); c.fill(); c.strokeStyle = edge; c.lineWidth = 1.5 * e1; c.stroke();
      if (full) { c.fillStyle = "rgba(255,255,255,.85)"; c.beginPath(); c.arc(T.x - T.r * 0.3, T.y - T.r * 0.3, T.r * 0.25, 0, TAU); c.fill(); }
    }
  }
  c.restore();
}

/** The front pass: a Scottish Fold's flaps, the collar, the whiskers, then the badge, the particles and the hairballs. */
```

```ts title="windows/src/cat/renderer.ts" old
    if (p.ear.fold) for (const ear of L.ears) drawEar(c, p, ear, R, full, flat, true);
```

```ts title="windows/src/cat/renderer.ts" new
    if (p.ear.fold) for (const ear of L.ears) drawEar(c, p, ear, R, full, flat, true);
    // The collar: over the head and the folded ears, under the whiskers (the contract's collarPass). Every size from Ø12 up; `off` and a bad colour draw nothing.
    if (o.collar && HEX6.test(o.collar.col)) {
      const dpr = dprOf(o), G = collarGeometry(p, s, f.D, o.collar.style, { dpr });
      if (G) drawCollar(c, G, o.collar.col, full, dpr);
    }
```

- [ ] **Step 4: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/collar-draw.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 6`, `# pass 6`, `# fail 0`, `tsc exit 0`, then `ℹ tests 133`, `ℹ pass 133`, `ℹ fail 0`.

- [ ] **Step 5: Commit**

```bash
git add windows/src/cat/renderer.ts windows/scripts/cat-tests/fake-canvas.mjs windows/scripts/cat-tests/collar-draw.test.mjs
git commit -m "feat(cat): the renderer paints the collar in the front pass, from Ø12 up

tag, band and kerchief from collarGeometry, between the folded ears and the whiskers, in the agent's colour with a thin dark edge.
Off, no colour and a colour that is not #RRGGBB draw nothing. The coat is never recoloured.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The collar reaches the cats, and its two Settings rows

**Agent:** `nm-implementer`.

**Files:**
- Modify: `windows/src/cat/engine.ts` (`collarColor` replaces the unused `bodyColor`; `draw` passes the collar), `windows/src/cat/collar.ts` (`bigCatCollar`), `windows/src/cat/minibots.ts`, `windows/src/island/island.ts`, `windows/src/settings/cat.ts` (the two rows), `windows/scripts/cat-tests/engine.test.mjs` (one test names `bodyColor`)
- Create: `windows/scripts/cat-tests/collar-wiring.test.mjs`

**Interfaces:**
- Consumes: Task 7's `DrawOptions.collar`; Task 1's `collarFor`/`applyCatSettings` (the style is already in `catCfg.collar`: the collar of the **chosen** cat, its own style else the global one); Task 4's `withCollar` and `withCatCollar`.
- Produces: `BotEngine.collarColor: string | null` (the colour of the collar this cat wears now, `#RRGGBB`; null for none). The engine draws it in the style of `cfg.collar`, so changing the style in Settings changes every cat at once. `bodyColor` (an unused field since stage 1) is gone. `bigCatCollar(state, color)` in `collar.ts`: the big cat wears the colour of the agent driving its state, and **none when idle**, asleep or dizzy (those are the cat's own states, not an agent's). The mini cats (pills Ø24 and the compact grid Ø13) wear their own pill's colour, whatever their state, "so small cats wear their agent's collar"; with the collar off, each mini cat's pill still names its agent.
- The Settings rows **Collar** (global: Band and tag, Band, Neckerchief or Off; default Off) and **This cat's collar** (follow the global collar, or one style for this cat), and "Apply to every cat" now copies the collar too. The big preview of the Cat section wears a sample colour, so the collar can be tried there.
- Not decided by the spec, decided here: the collar's colour for the big cat comes from `State.focusTask.color` for **every** pill that drives it, including the external agents (`agent_gemini`, `agent_antigravity`); the old `isIntegration` test, which only the unused `bodyColor` had, is dropped.

- [ ] **Step 1: Write the failing tests**

```js title="windows/scripts/cat-tests/collar-wiring.test.mjs" create
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { bigCatCollar } from "../../src/cat/collar.ts";
import { BotEngine } from "../../src/cat/engine.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { applyCatSettings } from "../../src/cat/settings.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

installBrowserStubs();
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const cfgOf = (extra = {}) => ({ motion: "playful", override: {}, pers: {}, zoomAfter: 300000, ...extra });
const strokes = (e, head) => { const ctx = fakeCanvas(); e.draw(ctx, head / 0.6, head / 0.6); return ctx.calls.stroke || 0; };
const make = (cfg, colour) => { const e = new BotEngine(PRESETS.momo, { cfg, quiet: true, now: () => 0, rand: () => 0.5, mini: true }); e.collarColor = colour; return e; };

test("the big cat wears the colour of the agent driving its state, and none when idle, asleep or dizzy", () => {
  for (const state of ["working", "thinking", "searching", "approval", "question", "error", "finished", "ratelimit"]) assert.equal(bigCatCollar(state, "#8AB4F8"), "#8AB4F8", state);
  for (const state of ["idle", "sleeping", "dizzy"]) assert.equal(bigCatCollar(state, "#8AB4F8"), null, state);
  for (const none of [null, undefined, ""]) assert.equal(bigCatCollar("working", none), null, String(none));
});

test("an engine draws its collar in the style of the shared config, and nothing when it has no colour or the style is off", () => {
  for (const head of [13, 24, 66]) {
    const bare = strokes(make(cfgOf({ collar: "band" }), null), head);
    for (const style of ["tag", "band", "kerchief"]) assert.ok(strokes(make(cfgOf({ collar: style }), "#8AB4F8"), head) > bare, `Ø${head} ${style}`);
    assert.equal(strokes(make(cfgOf({ collar: "off" }), "#8AB4F8"), head), bare, `Ø${head} off`);
    assert.equal(strokes(make(cfgOf({}), "#8AB4F8"), head), bare, `Ø${head}: no style chosen means off`);
    assert.equal(strokes(make(cfgOf({ collar: "scarf" }), "#8AB4F8"), head), bare, `Ø${head}: an unknown style is off`);
  }
});

test("changing the collar in Settings changes a running engine at once", () => {
  const cfg = cfgOf(), e = make(cfg, "#8AB4F8");
  const bare = strokes(e, 40);
  applyCatSettings(cfg, { character: "momo", collar: "band" });
  assert.ok(strokes(e, 40) > bare, "a band appeared");
  applyCatSettings(cfg, { character: "momo", collar: "band", cats: { momo: { collar: "off" } } });
  assert.equal(strokes(e, 40), bare, "this cat's own Off beats the global Band");
  applyCatSettings(cfg, { character: "momo", collar: "off", cats: { momo: { collar: "kerchief" } } });
  assert.ok(strokes(e, 40) > bare, "this cat's own Neckerchief beats the global Off");
});

test("bodyColor is gone, and the wiring is in place: the big cat, the pills and the compact grid", () => {
  const engine = source("cat/engine.ts"), mini = source("cat/minibots.ts"), island = source("island/island.ts");
  assert.doesNotMatch(engine + mini + island, /bodyColor/);
  assert.match(engine, /collar: this\.collarColor \? \{ style: this\.cfg\.collar \?\? "off", col: this\.collarColor \} : null/);
  assert.match(island, /this\.engine\.collarColor = bigCatCollar\(State\.effectiveState, focus\?\.color\);/);
  assert.equal([...mini.matchAll(/engine\.collarColor = task\.color;/g)].length, 2, "when a mini cat is made, and each time the tasks sync");
});
```

```js title="windows/scripts/cat-tests/engine.test.mjs" old
test("the engine keeps the old character's members: setState, blink, slap, gulp, update, draw, busy, isMini, bodyColor, lookX/Y, tgEs, slotH*, onDizzy", () => {
```

```js title="windows/scripts/cat-tests/engine.test.mjs" new
test("the engine keeps the old character's members: setState, blink, slap, gulp, update, draw, busy, isMini, collarColor, lookX/Y, tgEs, slotH*, onDizzy", () => {
```

```js title="windows/scripts/cat-tests/engine.test.mjs" old
  assert.deepEqual([e.isMini, e.bodyColor, e.lookX, e.lookY, e.slotH, e.slotHTarget, e.slotHVel, e.morph, e.onDizzy, e.particleOverhang, e.earRoom], [false, null, 0, 0, 0, 0, 0, 0, null, 0, null]);
```

```js title="windows/scripts/cat-tests/engine.test.mjs" new
  assert.deepEqual([e.isMini, e.collarColor, e.lookX, e.lookY, e.slotH, e.slotHTarget, e.slotHVel, e.morph, e.onDizzy, e.particleOverhang, e.earRoom], [false, null, 0, 0, 0, 0, 0, 0, null, 0, null]);
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/collar-wiring.test.mjs scripts/cat-tests/engine.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; cd ..`
Expected: `not ok 1 - scripts/cat-tests/collar-wiring.test.mjs` (the file cannot import `bigCatCollar`) and `not ok 5 - the engine keeps the old character's members…`, then `# tests 12`, `# pass 10`, `# fail 2`.

- [ ] **Step 3: The engine wears the collar; the island and the pills give it its colour**

```ts title="windows/src/cat/engine.ts" old
// isMini, bodyColor, lookX and lookY, tgEs, slotH*, onDizzy, hexToRGB and EyeShape.
```

```ts title="windows/src/cat/engine.ts" new
// isMini, collarColor, lookX and lookY, tgEs, slotH*, onDizzy, hexToRGB and EyeShape.
```

```ts title="windows/src/cat/engine.ts" old
  // What the island uses and the old engine had; some of it waits for later stages (see the Next plan).
  /** Solid colour of an integration pill or an agent. It becomes the collar in sub-project A's stage 6. */
  bodyColor: RGB | null = null;
```

```ts title="windows/src/cat/engine.ts" new
  // What the island uses and the old engine had; some of it is removed in stage 7.
  /** The colour of the collar this cat wears now ("#RRGGBB"), or null for none: the agent driving the big cat's state, or a mini cat's own pill. The style is `cfg.collar`. */
  collarColor: string | null = null;
```

```ts title="windows/src/cat/engine.ts" old
earCeiling: this.earRoom === null ? undefined : cy - this.earRoom, fur: this.cfg.fur });
```

```ts title="windows/src/cat/engine.ts" new
earCeiling: this.earRoom === null ? undefined : cy - this.earRoom, fur: this.cfg.fur,
      collar: this.collarColor ? { style: this.cfg.collar ?? "off", col: this.collarColor } : null });
```

```ts title="windows/src/cat/collar.ts" old
  return out;
}
```

```ts title="windows/src/cat/collar.ts" new
  return out;
}

/**
 * The colour the big cat wears: the collar of the agent driving its current state, and none when idle. A sleeping cat is an idle one, and a dizzy
 * one has been poked: those states are the cat's own, not an agent's. `color` is the focused pill's colour.
 */
export function bigCatCollar(state: string, color: string | null | undefined): string | null {
  return color && state !== "idle" && state !== "sleeping" && state !== "dizzy" ? color : null;
}
```

```ts title="windows/src/cat/minibots.ts" old
import { BotEngine, hexToRGB } from "./engine";
```

```ts title="windows/src/cat/minibots.ts" new
import { BotEngine } from "./engine";
```

```ts title="windows/src/cat/minibots.ts" old
  engine.isMini = true;
  engine.bodyColor = hexToRGB(task.color);
```

```ts title="windows/src/cat/minibots.ts" new
  engine.isMini = true;
  engine.collarColor = task.color;
```

```ts title="windows/src/cat/minibots.ts" old
    mb.engine.bodyColor = hexToRGB(task.color);
```

```ts title="windows/src/cat/minibots.ts" new
    mb.engine.collarColor = task.color;
```

```ts title="windows/src/island/island.ts" old
import { BotEngine, catCfg, hexToRGB } from "../cat/engine";
```

```ts title="windows/src/island/island.ts" new
import { bigCatCollar } from "../cat/collar";
import { BotEngine, catCfg } from "../cat/engine";
```

```ts title="windows/src/island/island.ts" old
    this.engine.bodyColor = focus?.isIntegration ? hexToRGB(focus.color) : null;
```

```ts title="windows/src/island/island.ts" new
    this.engine.collarColor = bigCatCollar(State.effectiveState, focus?.color);
```

- [ ] **Step 4: The two Settings rows, and a sample collar on the big preview**

```ts title="windows/src/settings/cat.ts" old
import {
  FOLLOW, MOTION_STYLES, applyCatSettings, applyToAllCats, cleanCatSettings, withCatMotion, withCharacter, withFurLines, withMotionStyle, withPersonality,
  type CatSettings,
} from "../cat/settings";
```

```ts title="windows/src/settings/cat.ts" new
import {
  COLLAR_STYLES, FOLLOW, MOTION_STYLES, applyCatSettings, applyToAllCats, cleanCatSettings, withCatCollar, withCatMotion, withCharacter, withCollar, withFurLines,
  withMotionStyle, withPersonality, type CatSettings,
} from "../cat/settings";
```

```ts title="windows/src/settings/cat.ts" old
const WORDS: Record<string, string> = { playful: "Playful", classic: "Classic" };
```

```ts title="windows/src/settings/cat.ts" new
const WORDS: Record<string, string> = { playful: "Playful", classic: "Classic" };
const COLLARS: Record<string, string> = { tag: "Band and tag", band: "Band", kerchief: "Neckerchief", off: "Off" };
/** The big preview's collar colour: no agent is driving it, so it wears a sample, to show the style. */
const SAMPLE_COLLAR = "#F29B38";
```

```ts title="windows/src/settings/cat.ts" old
  preview.particleOverhang = 40;
```

```ts title="windows/src/settings/cat.ts" new
  preview.particleOverhang = 40;
  preview.collarColor = SAMPLE_COLLAR;
```

```ts title="windows/src/settings/cat.ts" old
  const catWhose = h("span", { class: "hint" });
```

```ts title="windows/src/settings/cat.ts" new
  const catWhose = h("span", { class: "hint" });
  const collar = menu(COLLAR_STYLES.map((m) => [m, COLLARS[m]] as const), (v) => change(withCollar(now(), v)));
  const catCollar = menu([[FOLLOW, "Follow the global collar"], ...COLLAR_STYLES.map((m) => [m, COLLARS[m]] as const)], (v) => { const s = now(); change(withCatCollar(s, s.character, v)); });
  const collarWhose = h("span", { class: "hint" });
```

```ts title="windows/src/settings/cat.ts" old
    applied.textContent = "Done: all 16 cats now move and feel like this one.";
```

```ts title="windows/src/settings/cat.ts" new
    applied.textContent = "Done: all 16 cats now share this cat's motion, personality and collar.";
```

```ts title="windows/src/settings/cat.ts" old
    catMotion.value = mine.motion;
```

```ts title="windows/src/settings/cat.ts" new
    catMotion.value = mine.motion;
    collar.value = s.collar;
    catCollar.value = mine.collar;
```

```ts title="windows/src/settings/cat.ts" old
    whose.textContent = catWhose.textContent = `for ${PRESETS[id].label}`;
```

```ts title="windows/src/settings/cat.ts" new
    whose.textContent = catWhose.textContent = collarWhose.textContent = `for ${PRESETS[id].label}`;
```

```ts title="windows/src/settings/cat.ts" old
    row("Apply to every cat", apply, applied),
```

```ts title="windows/src/settings/cat.ts" new
    row("Collar", collar, h("span", { class: "hint", text: "The agent's colour, worn by every cat. Off by default." })),
    row("This cat's collar", catCollar, collarWhose),
    row("Apply to every cat", apply, applied),
```

- [ ] **Step 5: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/collar-wiring.test.mjs scripts/cat-tests/engine.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# fail 0`, `tsc exit 0` with no type error, then `ℹ tests 137`, `ℹ pass 137`, `ℹ fail 0`.

- [ ] **Step 6: Commit**

```bash
git add windows/src/cat/engine.ts windows/src/cat/collar.ts windows/src/cat/minibots.ts windows/src/island/island.ts windows/src/settings/cat.ts windows/scripts/cat-tests/engine.test.mjs windows/scripts/cat-tests/collar-wiring.test.mjs
git commit -m "feat(cat): the agent colour is the cat's collar, and Settings has its two rows

The big cat wears the collar of the agent driving its state and none when idle; the pills and the compact grid wear their own colour.
The style is the chosen cat's own, else the global one, and defaults to Off. Apply to every cat copies it. bodyColor is gone.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 9: The `?dev` sheet wears collars, and the owner looks at them

**Agent:** `nm-implementer`.

**Files:**
- Modify: `windows/src/cat/dev.ts` (a Collar panel; the ladder, the States strip, the Compact notch and the big cat wear it)

**Interfaces:**
- Consumes: Task 7's `DrawOptions.collar`, Task 8's `BotEngine.collarColor`, `catCfg.collar` and `bigCatCollar`, and Task 5's `AGENT_PILL_COLORS`.
- Produces: a **Collar** panel at the top of the `?dev` page: Style (Off, Band and tag, Band, Neckerchief) and Agent (the colours the app really has: the VS Code pill, Gemini CLI, Antigravity, Resend, Stripe). The coat ladder wears the collar at every size from Ø12 up, on all 16 coats and their kittens, as the pills and the compact grid do; the States strip, the big cat and the Compact notch panel wear it by the island's rule (none while idle, asleep or dizzy). Dev server only: `main.ts` loads `dev.ts` behind `import.meta.env.DEV`, so a release build has none of it. No unit test: the look is checked by eye, and the numbers are Tasks 6 to 8's.

- [ ] **Step 1: The panel, and the cats wear it**

```ts title="windows/src/cat/dev.ts" old
import { Greeting } from "./greeting.ts";
```

```ts title="windows/src/cat/dev.ts" new
import { Greeting } from "./greeting.ts";
import { bigCatCollar } from "./collar.ts";
import { AGENT_PILL_COLORS } from "../core/pills.ts";
```

```ts title="windows/src/cat/dev.ts" old
  const state = { fur: false, tint: true };
```

```ts title="windows/src/cat/dev.ts" new
  const state = { fur: false, tint: true, collar: "off", col: AGENT_PILL_COLORS.agent_gemini };
  /** The collar a cat that always wears one (the ladder, the pills) is drawn with. */
  const worn = () => (state.collar === "off" ? null : { style: state.collar, col: state.col });
```

```ts title="windows/src/cat/dev.ts" old
        drawCat(c, cell.v, cx, cy, cell.d, { tint: state.tint, fur: state.fur && cell.d >= 60 });
```

```ts title="windows/src/cat/dev.ts" new
        drawCat(c, cell.v, cx, cy, cell.d, { tint: state.tint, fur: state.fur && cell.d >= 60, collar: worn() });
```

```ts title="windows/src/cat/dev.ts" old
  const dev = { cat: "shrimpy", motion: "playful" };
```

```ts title="windows/src/cat/dev.ts" new
  // ── Stage 6: the collar ──
  const STYLES: readonly (readonly [string, string])[] = [["off", "Off"], ["tag", "Band and tag"], ["band", "Band"], ["kerchief", "Neckerchief"]];
  const AGENTS: readonly (readonly [string, string])[] = [
    ["#F5F6F8", "VS Code pill"], ["#8AB4F8", "Gemini CLI"], ["#E879F9", "Antigravity"], ["#22C55E", "Resend"], ["#0570DE", "Stripe"],
  ];
  const collarBox = section("Collar", "The agent colour as a thin collar, at every size from Ø12 up, never under 3 px of band, a 6 px tag or a 7 by 5 px neckerchief on the screen. The coat ladder wears it as the pills and the compact grid do; the States strip, the big cat and the Compact notch wear it by the island's rule: none while idle, asleep or dizzy.");
  collarBox.append(
    choice("Style", STYLES, () => state.collar, (v) => { state.collar = v; }),
    choice("Agent", AGENTS, () => state.col, (v) => { state.col = v; }),
  );
  root.insertBefore(collarBox, wrap);
  ticks.push(() => { catCfg.collar = state.collar; });

  const dev = { cat: "shrimpy", motion: "playful" };
```

```ts title="windows/src/cat/dev.ts" old
      e.particleOverhang = 20;
```

```ts title="windows/src/cat/dev.ts" new
      e.particleOverhang = 20;
      e.collarColor = state.collar === "off" ? null : bigCatCollar(e.state, state.col);
```

```ts title="windows/src/cat/dev.ts" old
    drawCat(c, notchCat, 40, 16, 20, { badgeSide: -1, earCeiling: notch.ears ? 0 : undefined });
```

```ts title="windows/src/cat/dev.ts" new
    const wear = state.collar === "off" ? null : bigCatCollar(notch.state, state.col);
    drawCat(c, notchCat, 40, 16, 20, { badgeSide: -1, earCeiling: notch.ears ? 0 : undefined, collar: wear ? { style: state.collar, col: wear } : null });
```

```ts title="windows/src/cat/dev.ts" old
    stage.particleOverhang = 60;
```

```ts title="windows/src/cat/dev.ts" new
    stage.particleOverhang = 60;
    stage.collarColor = state.collar === "off" ? null : bigCatCollar(stageState, state.col);
```

- [ ] **Step 2: Type check and the cat check**

Run: `cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `tsc exit 0` with no type error before it, then `ℹ tests 137`, `ℹ pass 137`, `ℹ fail 0` (this task adds no test).

- [ ] **Step 3: Look at it, in a browser, at 2x**

Serve the front end with Vite alone, and open the `?dev` page headless in a browser context with a 2x pixel ratio (the small sizes are where the readability floors bite, and on a real 2x screen a band that is 3 device pixels thick is 1.5 CSS px). Screenshot the first three rows of the ladder (Shrimpy, Momo, Ginger: Ø12 to Ø66 and two kitten sizes) and the Latte and Patches rows, once for each style. Keep the screenshots in a scratch folder, never in the repository.

```bash
SHOTS="${TMPDIR:-/tmp}/a-tauri-57-shots"; mkdir -p "$SHOTS"; WT="$(git rev-parse --show-toplevel)"
(cd "$WT/windows" && npx --no-install vite --port 14571 > "$SHOTS/vite.log" 2>&1 &)
sleep 3
cd "$SHOTS"
playwright-cli -s=sheet open about:blank
playwright-cli -s=sheet run-code "async page => { const ctx = await page.context().browser().newContext({ deviceScaleFactor: 2, viewport: { width: 1300, height: 4400 } }); const p = await ctx.newPage(); await p.goto('http://127.0.0.1:14571/?dev'); await p.waitForTimeout(800); const panel = p.locator('section', { has: p.getByRole('heading', { name: 'Collar', exact: true }) }); const b = await p.locator('canvas').last().boundingBox(); for (const [name, file] of [['Off', 'off'], ['Band and tag', 'band-and-tag'], ['Band', 'band'], ['Neckerchief', 'neckerchief']]) { await panel.getByRole('button', { name, exact: true }).click(); await p.waitForTimeout(500); await p.screenshot({ path: 'collar-' + file + '-top.png', clip: { x: b.x, y: b.y, width: b.width, height: 450 } }); await p.screenshot({ path: 'collar-' + file + '-light.png', clip: { x: b.x, y: b.y + 600, width: b.width, height: 300 } }); } await ctx.close(); }"
playwright-cli -s=sheet close
kill $(lsof -ti tcp:14571) 2>/dev/null; ls "$SHOTS"/collar-*.png
```

Expected: eight files, `collar-off-top.png`, `collar-off-light.png`, `collar-band-and-tag-top.png`, `collar-band-and-tag-light.png`, `collar-band-top.png`, `collar-band-light.png`, `collar-neckerchief-top.png` and `collar-neckerchief-light.png`. The page's agent is Gemini CLI (blue) until you change it. Open the three styles and the Off baseline and check, by eye, against the prototype page's Collar panel: at **every size from Ø12 to Ø66**, on every coat in the shots, the collar is a visible band or neckerchief of the agent's colour under the chin; at Ø12 and Ø16 it is still a band you can tell from the coat (a thin dark edge keeps a light collar apart from a light coat: Latte and Patches are the light ones); the tag is round, centred under the chin and lighter than the band; the neckerchief is a small triangle under the chin; the kittens wear it too; nothing is cut off, and the coat itself is the colour it is in the Off shot. The collar turns with the face where a cat looks at the pointer. If a size shows no collar, or it covers the mouth or a whisker, fix the painter and look again. Say what you saw to the controller.

- [ ] **Step 4: Commit**

```bash
git add windows/src/cat/dev.ts
git commit -m "feat(cat): the ?dev sheet has a Collar panel: style and agent, on the ladder, the States strip and the notch

The coat ladder wears it at every size from Ø12 up on all 16 coats and their kittens; the big cats by the island's rule.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Checkpoint 2: the owner looks at the collars

**Owner checkpoint** (the executing session; no agent). Task 10 starts only after the owner's OK.

- [ ] Send the owner, in the chat, the eight screenshots of Task 9 Step 3 (the Off baseline, Band and tag, Band and Neckerchief, each as `-top` and `-light`), **next to** the prototype page's Collar panel (`playwright-cli -s=proto open "http://127.0.0.1:8791/notchmeow.html"`, serve `design/prototype` with `python3 -m http.server 8791 --bind 127.0.0.1` first, then click the style in its Collar panel and screenshot `#ladder`), with three lines of text: the collars are drawn from the contract's geometry (`collar-cases.json`, replayed to 1e-9) and the sheet shows them at a 2x pixel ratio, where the readability floors are 3 device pixels of band, a 6 px tag and a 7 by 5 px neckerchief; the default is Off; and Gemini CLI and Antigravity now have the Mac's colours on Windows (blue and pink), which changes how those two pills look.
- [ ] Ask the owner the open questions that belong here (they are in "Open questions for the owner"): the big cat wears no collar while idle, asleep or dizzy; the Gemini CLI and Antigravity pills changing colour; and **question 1, the island's glow**: may stage 7 swap the island's glow literals in `core/layout.ts` for the theme tokens (same values, no change of look)? Task 14 runs on a yes and is skipped on a no.
- [ ] Say what the owner should check by hand in a real build (`cd windows && npm run tauri dev`): Settings → Cat → Collar: pick Band and tag, and start a Gemini CLI or Claude Code session: the small cats in the pills and in the compact grid wear their agent's colour and the big cat wears the colour of the agent that is working, and none when idle; "This cat's collar" set to Off for the chosen cat turns it off for that cat only; "Apply to every cat" copies it to all 16; with the collar Off, each mini cat's pill still names its agent.
- [ ] Wait for the owner's OK.

---

### Task 10: Searching

**Agent:** `nm-implementer-light`.

An agent that runs a search tool makes the cat search; the next tool that is not a search puts it back to working (spec §3, "Searching").

**Files:**
- Modify: `windows/src/cat/base.ts` (the tool list and two small functions), `windows/src/island/hooks.ts` (the two hook cases)
- Create: `windows/scripts/cat-tests/search.test.mjs`

**Interfaces:**
- Consumes: `tests/fixtures/cat/search-tools.json` (`agents` of the three agents' tool names, `match`, and `cases` of tool, searching, state).
- Produces in `base.ts`, with the contract's names: `SEARCH_TOOLS` (`claude`, `gemini`, `codex`), `isSearchTool(name)` (exact and case-sensitive on the `tool_name` the relay delivers, no prefix or MCP matching; anything that is not a string is not a search), `toolState(name)` (`"searching"` or `"working"`). In `hooks.ts`, `PreToolUse` and `PostToolUse` set the task's state to `toolState(payload.tool_name)`. This touches the hook **handlers** in the front end only: the relay and the Rust hooks are untouched. Gemini CLI and Antigravity events arrive already translated to `PreToolUse` and `PostToolUse` by the relay. Codex is not hooked on Windows yet, so its two names are in the list and unused. `searching` is an existing state of the cat (it has its own look in both motion styles), the pills and the compact grid show it like any other.

- [ ] **Step 1: Write the failing tests**

```js title="windows/scripts/cat-tests/search.test.mjs" create
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { SEARCH_TOOLS, isSearchTool, toolState } from "../../src/cat/base.ts";
import { load } from "./util.mjs";

const fx = load("search-tools.json");

test("the tool names that mean searching are the fixture's, for Claude Code, Gemini CLI and Codex", () => {
  assert.deepEqual(JSON.parse(JSON.stringify(SEARCH_TOOLS)), fx.agents);
  assert.ok(fx.cases.length >= 25);
});

test("every case of the fixture: a search tool searches, any other tool works", () => {
  for (const c of fx.cases) {
    assert.equal(isSearchTool(c.tool), c.searching, c.tool);
    assert.equal(toolState(c.tool), c.state, c.tool);
  }
  for (const name of Object.values(fx.agents).flat()) assert.equal(toolState(name), "searching", name);
});

test("matching is exact and case-sensitive, and anything that is not a string is not a search", () => {
  for (const bad of ["websearch", "WEBSEARCH", "Web_Search", "web_search ", " Grep", "mcp__brave__web_search", "", "Task", "Bash"]) assert.equal(isSearchTool(bad), false, JSON.stringify(bad));
  for (const odd of [undefined, null, 7, true, {}, [], ["Grep"], Symbol.iterator]) {
    assert.equal(isSearchTool(odd), false, String(typeof odd));
    assert.equal(toolState(odd), "working");
  }
  for (const proto of ["__proto__", "constructor", "toString", "hasOwnProperty"]) assert.equal(isSearchTool(proto), false, proto);
});

test("hooks.ts: before and after a tool, the pill's state is the tool's state", () => {
  const hooks = fs.readFileSync(new URL("../../src/island/hooks.ts", import.meta.url), "utf8");
  assert.match(hooks, /import \{ toolState \} from "\.\.\/cat\/base\.ts";/);
  const pre = hooks.match(/case "PreToolUse": \{[\s\S]*?break;\s*\}/)[0], post = hooks.match(/case "PostToolUse":[\s\S]*?break;/)[0];
  assert.match(pre, /State\.updateTask\(agentId, toolState\(payload\.tool_name\)\);/);
  assert.match(post, /State\.updateTask\(agentId, toolState\(payload\.tool_name\)\);/);
  assert.doesNotMatch(pre + post, /updateTask\(agentId, "working"\)/);
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/search.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; cd ..`
Expected: `not ok 1 - scripts/cat-tests/search.test.mjs`, `# tests 1`, `# pass 0`, `# fail 1` (the names are not exported yet, so the file cannot load).

- [ ] **Step 3: The tool list**

```ts title="windows/src/cat/base.ts" old
export const zoomiesOnFinish = (workedForMs: number, thresholdMs = ZOOM_AFTER_MS) => workedForMs >= thresholdMs;
```

```ts title="windows/src/cat/base.ts" new
export const zoomiesOnFinish = (workedForMs: number, thresholdMs = ZOOM_AFTER_MS) => workedForMs >= thresholdMs;

// ── Searching ─────────────────────────────────────────────────────────────────

/**
 * The tool names that mean "searching" (tests/fixtures/cat/search-tools.json): web search, web fetch, grep and glob. Claude Code's come from the repo's
 * hook mapping, Gemini CLI's from the installed CLI, Codex's are unverified. Exact and case-sensitive on the `tool_name` the hook relay delivers:
 * no prefix or MCP matching. A name that is missing only means the cat stays in "working" for that tool.
 */
export const SEARCH_TOOLS = {
  claude: ["WebSearch", "WebFetch", "Grep", "Glob"],
  gemini: ["google_web_search", "web_fetch", "grep_search", "search_file_content", "glob"],
  codex: ["web_search", "grep_files"],
} as const;
const SEARCH_SET: ReadonlySet<string> = new Set<string>(Object.values(SEARCH_TOOLS).flat());
/** True for a tool name that means searching. Anything that is not a string is not a search. */
export const isSearchTool = (name: unknown): boolean => typeof name === "string" && SEARCH_SET.has(name);
/** The state of an agent that is running this tool: `searching` for a search tool, `working` for any other. */
export const toolState = (name: unknown): "searching" | "working" => (isSearchTool(name) ? "searching" : "working");
```

```ts title="windows/src/island/hooks.ts" old
import { agentColor } from "../core/pills.ts";
```

```ts title="windows/src/island/hooks.ts" new
import { toolState } from "../cat/base.ts";
import { agentColor } from "../core/pills.ts";
```

```ts title="windows/src/island/hooks.ts" old
    case "PreToolUse": {
      ensurePill();
      State.updateTask(agentId, "working");
```

```ts title="windows/src/island/hooks.ts" new
    case "PreToolUse": {
      ensurePill();
      State.updateTask(agentId, toolState(payload.tool_name));
```

```ts title="windows/src/island/hooks.ts" old
    case "PostToolUse":
      State.updateTask(agentId, "working");
      break;
```

```ts title="windows/src/island/hooks.ts" new
    case "PostToolUse":
      State.updateTask(agentId, toolState(payload.tool_name));
      break;
```

- [ ] **Step 4: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/search.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 4`, `# pass 4`, `# fail 0`, `tsc exit 0`, then `ℹ tests 141`, `ℹ pass 141`, `ℹ fail 0`.

- [ ] **Step 5: Commit**

```bash
git add windows/src/cat/base.ts windows/src/island/hooks.ts windows/scripts/cat-tests/search.test.mjs
git commit -m "feat(cat): an agent that runs a search tool makes the cat search

SEARCH_TOOLS, isSearchTool and toolState come from the contract's search-tools.json. Before and after a tool the pill is searching for a
search tool and working for any other. Front-end handlers only: the relay and the Rust hooks are untouched.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 11: Sleeping

**Agent:** `nm-implementer`.

An idle cat falls asleep after 10 minutes with no agent event. It never sleeps through an approval or a question. Any hook event, hover or click wakes it, and Playful wakes with zoomies (spec §3, "Sleeping"). One timer, started by every event, with no polling.

**Files:**
- Modify: `windows/src/cat/base.ts` (the rule), `windows/src/core/state.ts` (`asleep`, `shownState`, `fallAsleep`, `wake`), `windows/src/cat/minibots.ts`, `windows/src/island/island.ts`, `windows/src/island/hooks.ts`, `windows/src/cat/dev.ts` (two buttons)
- Create: `windows/src/island/sleep.ts`, `windows/scripts/cat-tests/sleep.test.mjs`

**Interfaces:**
- Consumes: `tests/fixtures/cat/sequence-cases.json` `sleep` (`afterMs`, 56 `cases` of state, quiet time and delay, and `wake` kinds).
- Produces in `base.ts`, with the contract's names: `SLEEP_AFTER_MS` (600000), `sleepDelay(state, quietMs)` (the time left until a cat in that state falls asleep: only `idle` has one, every other state is `null`; a quiet time that is negative or not a number counts as 0), `WAKE_EVENTS` (`hook`, `hover`, `click`) and `wakes(kind)`.
- Produces `src/island/sleep.ts`: `SleepClock` and its `SleepEnv`. It arms **one** timer for the full ten minutes at start-up and on every waking event, and when it fires it asks the contract's rule: is the cat idle, and is nothing waiting for an answer? Then it falls asleep. If not, it does nothing and arms nothing: every change out of a non-idle state comes with a hook event (a Stop, a SessionEnd), which arms it again. It is armed whatever the state is when the event arrives (a `finished` pill goes back to idle 5 s later, and the ten minutes are counted from the event, not from that moment). A timer that fires early waits for the rest. It never polls.
- `State.asleep` (the cats are asleep), `State.shownState(state)` (`idle` shows as `sleeping` while asleep; every other state shows as itself), `State.fallAsleep()` and `State.wake()` (each notifies only when it changes something). `effectiveState`, the big cat and every mini cat use `shownState`, so the pills and the compact grid sleep with the big cat. An approval card, a question, a working agent or a dizzy cat is never overridden, and an approval is never slept through: the clock's `blocked` is true while the user's own approval, a chat's approval card or any pill's approval or question is waiting. `Island.noteActivity(kind)` is the one door the hook handlers use; the island calls it itself on a hover and on a click.
- The waking zoomies are not new: Playful's `enter` already starts them on the way out of `sleeping` (`prev === "sleeping"`, 220 ms later), except into dizzy; Classic wakes quietly.
- A sleeping cat while the island is **hidden** costs nothing: the timer fires once, `State.notify()` runs one frame, and the island's loop stops again (it never runs while hidden).

- [ ] **Step 1: Write the failing tests**

```js title="windows/scripts/cat-tests/sleep.test.mjs" create
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { SLEEP_AFTER_MS, WAKE_EVENTS, sleepDelay, wakes } from "../../src/cat/base.ts";
import { State } from "../../src/core/state.ts";
import { SleepClock } from "../../src/island/sleep.ts";
import { load } from "./util.mjs";

const fx = load("sequence-cases.json").sleep;
const MIN = 60_000;
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

/** A clock and a timer queue the test turns by hand, and a cat that records what happens to it. */
function world() {
  const w = { t: 0, state: "idle", blocked: false, timers: new Map(), id: 1, sets: 0, clears: 0, falls: 0, wakes: 0 };
  const env = {
    now: () => w.t, state: () => w.state, blocked: () => w.blocked,
    set: (fn, ms) => { const id = w.id++; w.sets++; w.timers.set(id, { fn, at: w.t + ms }); return id; },
    clear: (id) => { w.clears++; w.timers.delete(id); },
    fall: () => { w.falls++; }, wake: () => { w.wakes++; },
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

test("the rule is the contract's: ten minutes, only an idle cat, and a hook, a hover or a click wakes it", () => {
  assert.equal(SLEEP_AFTER_MS, fx.afterMs);
  assert.equal(SLEEP_AFTER_MS, 10 * MIN);
  assert.ok(fx.cases.length >= 50);
  for (const c of fx.cases) assert.equal(sleepDelay(c.state, c.quietMs), c.delayMs, `${c.state} after ${c.quietMs} ms`);
  for (const w of fx.wake) assert.equal(wakes(w.kind), w.wakes, JSON.stringify(w.kind));
  assert.deepEqual([...WAKE_EVENTS], ["hook", "hover", "click"]);
  for (const odd of [undefined, null, 7, {}, ["hook"], "Hook"]) assert.equal(wakes(odd), false, String(odd));
  for (const bad of [NaN, Infinity, -Infinity, -5000]) assert.equal(sleepDelay("idle", bad), SLEEP_AFTER_MS, `a quiet time of ${bad} counts as 0`);
});

test("an idle cat falls asleep after exactly ten minutes without an event, once, and the timer is not re-armed", () => {
  const { w } = world();
  assert.equal(w.timers.size, 1, "armed at start-up");
  w.advance(10 * MIN - 1);
  assert.equal(w.falls, 0);
  w.advance(1);
  assert.equal(w.falls, 1);
  assert.equal(w.timers.size, 0, "nothing left to fire: no polling");
  w.advance(60 * MIN);
  assert.equal(w.falls, 1);
});

test("every event starts the ten minutes again, with one timer at a time and no polling", () => {
  const { w, clock } = world();
  w.advance(5 * MIN);
  clock.event("hook");
  w.advance(10 * MIN - 1);
  assert.equal(w.falls, 0, "the first event moved it to 15 minutes");
  w.advance(1);
  assert.equal(w.falls, 1);
  const busy = world();
  for (let i = 0; i < 100; i++) { busy.w.advance(1000); busy.clock.event(i % 2 ? "hover" : "hook"); }
  assert.equal(busy.w.timers.size, 1, "one timer, however many events");
  assert.equal(busy.w.sets, 101, "one set at start-up and one per event, nothing in between");
  assert.equal(busy.w.falls, 0);
  assert.doesNotMatch(source("island/sleep.ts"), /setInterval/);
});

test("it never sleeps through an approval or a question, nor while the cat is not idle, and the next event starts it again", () => {
  const a = world();
  a.w.state = "approval";
  a.w.advance(10 * MIN);
  assert.deepEqual([a.w.falls, a.w.timers.size], [0, 0], "an approval is not slept through");
  for (const state of ["question", "working", "thinking", "searching", "finished", "error", "ratelimit", "dizzy"]) {
    const x = world(); x.w.state = state; x.w.advance(10 * MIN);
    assert.equal(x.w.falls, 0, state);
  }
  const b = world();
  b.w.blocked = true;
  b.w.advance(10 * MIN);
  assert.equal(b.w.falls, 0, "a card is waiting for an answer");
  b.w.blocked = false; b.w.state = "idle";
  b.clock.event("hook");
  b.w.advance(10 * MIN);
  assert.equal(b.w.falls, 1, "after the next event it works as ever");
});

test("a pill that finished goes back to idle on its own: the ten minutes are counted from the event, not from then", () => {
  const { w, clock } = world();
  w.state = "finished";
  clock.event("hook");
  w.advance(5200);
  w.state = "idle";
  w.advance(10 * MIN - 5200);
  assert.equal(w.falls, 1);
});

test("a hook, a hover and a click wake the cat and restart the clock; a key, a scroll or a drag change nothing", () => {
  const { w, clock } = world();
  for (const kind of WAKE_EVENTS) { clock.event(kind); assert.equal(w.wakes, WAKE_EVENTS.indexOf(kind) + 1, kind); }
  const sets = w.sets;
  for (const kind of ["key", "scroll", "drag", "", undefined, null, 7]) clock.event(kind);
  assert.deepEqual([w.wakes, w.sets], [3, sets], "ignored events do not wake it and do not touch the timer");
});

test("a timer that fires early waits for the rest, and a clock that steps back is not a reason to sleep", () => {
  const { w } = world();
  const fire = (x) => { const [[id, t]] = [...x.timers.entries()]; x.timers.delete(id); t.fn(); };
  w.t = 10 * MIN - 2;
  fire(w);
  assert.equal(w.falls, 0);
  assert.equal(w.timers.size, 1, "two milliseconds to go: armed again for them");
  assert.equal([...w.timers.values()][0].at, w.t + 2);
  const back = world();
  back.w.t = -5000;
  fire(back.w);
  assert.equal(back.w.falls, 0);
  assert.equal([...back.w.timers.values()][0].at, back.w.t + 10 * MIN, "the full ten minutes again");
});

test("State: an idle cat shows as sleeping while asleep, nothing else does, and falling asleep and waking notify only when they change something", () => {
  State.loadIntegrationTasks();
  const seen = []; const off = State.subscribe(() => seen.push(State.effectiveState));
  try {
    assert.equal(State.asleep, false);
    assert.equal(State.effectiveState, "idle");
    State.fallAsleep(); State.fallAsleep();
    assert.equal(State.effectiveState, "sleeping");
    assert.equal(seen.length, 1, "the second call changed nothing");
    assert.deepEqual(["idle", "working", "thinking", "searching", "approval", "question", "error", "finished", "ratelimit", "dizzy"].map((s) => State.shownState(s)),
      ["sleeping", "working", "thinking", "searching", "approval", "question", "error", "finished", "ratelimit", "dizzy"]);
    State.updateTask("integration_claude", "approval");
    assert.equal(State.effectiveState, "approval", "an approval is never overridden");
    State.updateTask("integration_claude", "idle");
    State.stateOverride = "dizzy";
    assert.equal(State.effectiveState, "dizzy", "a poked cat is dizzy, asleep or not");
    State.stateOverride = null;
    State.wake(); State.wake();
    assert.equal(State.effectiveState, "idle");
    assert.deepEqual(seen, ["sleeping", "approval", "sleeping", "idle"], "one notification per change: falling asleep, the approval, back to idle (asleep), waking; the second wake changed nothing");
  } finally { off(); State.asleep = false; State.stateOverride = null; }
});

test("the wiring: the hook handlers, the island's hover and click, and the mini cats", () => {
  const island = source("island/island.ts"), hooks = source("island/hooks.ts"), mini = source("cat/minibots.ts");
  assert.match(island, /private sleep = new SleepClock\(\{/);
  assert.match(island, /fall: \(\) => State\.fallAsleep\(\),/);
  assert.match(island, /wake: \(\) => State\.wake\(\),/);
  assert.match(island, /noteActivity\(kind: "hook" \| "hover" \| "click"\) \{\s*this\.sleep\.event\(kind\);/);
  assert.match(island, /if \(inIsland && !this\.wasInIsland\) \{\s*this\.sleep\.event\("hover"\);/);
  assert.match(island, /addEventListener\("mousedown", \(e\) => \{\s*Sound\.resume\(\);\s*this\.sleep\.event\("click"\);/);
  assert.match(hooks, /function handleHook\(island: Island, payload: HookPayload\) \{\s*island\.noteActivity\("hook"\);/);
  assert.equal([...mini.matchAll(/State\.shownState\(task\.state\)/g)].length, 2, "when a mini cat is made, and each time the tasks sync");
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/sleep.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; cd ..`
Expected: `not ok 1 - scripts/cat-tests/sleep.test.mjs`, `# tests 1`, `# pass 0`, `# fail 1` (the names are not exported yet).

- [ ] **Step 3: The rule, the clock and the state**

```ts title="windows/src/cat/base.ts" old
export const toolState = (name: unknown): "searching" | "working" => (isSearchTool(name) ? "searching" : "working");
```

```ts title="windows/src/cat/base.ts" new
export const toolState = (name: unknown): "searching" | "working" => (isSearchTool(name) ? "searching" : "working");

// ── Sleeping ──────────────────────────────────────────────────────────────────

/** An idle cat falls asleep after this long with no agent event (ms). */
export const SLEEP_AFTER_MS = 10 * 60 * 1000;
/**
 * How long until a cat in `state` falls asleep, `quietMs` after the last agent event: 0 once it is due. Only an idle cat sleeps; every other state,
 * an approval and a question included, is null. A quiet time that is negative or not a number counts as 0 (a clock that stepped back).
 */
export const sleepDelay = (state: string, quietMs: number): number | null =>
  state === "idle" ? Math.max(0, SLEEP_AFTER_MS - Math.max(0, Number.isFinite(quietMs) ? quietMs : 0)) : null;
/** What wakes a sleeping cat: an agent event (`hook`), a hover or a click. A key, a scroll or a drag does not. In Playful it wakes with zoomies. */
export const WAKE_EVENTS: readonly string[] = ["hook", "hover", "click"];
export const wakes = (kind: unknown): boolean => typeof kind === "string" && WAKE_EVENTS.includes(kind);
```

```ts title="windows/src/island/sleep.ts" create
// The cat's ten-minute nap (spec §3): one timer, started by every event, never a poll. The rule is the contract's (`sleepDelay`, `wakes` in cat/base.ts,
// tests/fixtures/cat/sequence-cases.json). Pure: the clock, the timer and the cat are injected, so the plain-Node checks can turn time by hand.

import { sleepDelay, wakes } from "../cat/base.ts";

export interface SleepEnv {
  /** Milliseconds. */
  now(): number;
  /** The state the cat shows when awake: only `idle` can fall asleep. */
  state(): string;
  /** An approval or a question is waiting for the user: the cat never sleeps through one. */
  blocked(): boolean;
  set(fn: () => void, ms: number): number;
  clear(id: number): void;
  /** The cat falls asleep. */
  fall(): void;
  /** The cat is woken (called on every waking event; it must do nothing when the cat is awake). */
  wake(): void;
}

export class SleepClock {
  private timer: number | null = null;
  private last: number;
  private readonly env: SleepEnv;

  /** Starts the first ten minutes: an app that starts and sees no event falls asleep too. */
  constructor(env: SleepEnv) {
    this.env = env;
    this.last = env.now();
    this.arm(sleepDelay("idle", 0) ?? 0);
  }

  /**
   * An agent event (`hook`), a hover or a click: the cat wakes and its ten minutes start again. Any other kind (a key, a scroll, a drag) is ignored.
   * The timer is armed whatever the cat is doing: a pill that finished goes back to idle on its own, and the ten minutes are counted from the event.
   */
  event(kind: unknown): void {
    if (!wakes(kind)) return;
    this.last = this.env.now();
    this.env.wake();
    this.arm(sleepDelay("idle", 0) ?? 0);
  }

  private arm(ms: number): void {
    if (this.timer !== null) this.env.clear(this.timer);
    this.timer = this.env.set(() => this.expire(), ms);
  }

  /** The timer fired: sleep if the cat is idle, ten minutes have passed and nothing waits for an answer; wait the rest if it fired early. */
  private expire(): void {
    this.timer = null;
    const left = sleepDelay(this.env.state(), this.env.now() - this.last);
    if (left === 0 && !this.env.blocked()) this.env.fall();
    else if (left !== null && left > 0) this.arm(left);
  }
}
```

```ts title="windows/src/core/state.ts" old
  stateOverride: BotStateName | null = null;
```

```ts title="windows/src/core/state.ts" new
  stateOverride: BotStateName | null = null;

  /** The cats are asleep: ten minutes with no agent event, hover or click (island/sleep.ts). An idle cat then shows `sleeping`; one that is working, asking or finished does not. */
  asleep = false;
```

```ts title="windows/src/core/state.ts" old
  get effectiveState(): BotStateName {
    return this.stateOverride ?? this.focusTask?.state ?? "idle";
  }
```

```ts title="windows/src/core/state.ts" new
  get effectiveState(): BotStateName {
    return this.stateOverride ?? this.shownState(this.focusTask?.state ?? "idle");
  }

  /** The state a cat shows for a task state: an idle cat sleeps while the cats are asleep; every other state shows as itself. */
  shownState(state: BotStateName): BotStateName {
    return state === "idle" && this.asleep ? "sleeping" : state;
  }

  fallAsleep() {
    if (this.asleep) return;
    this.asleep = true;
    this.notify();
  }

  /** An event woke the cats. Playful's `enter` starts the waking zoomies when the cat leaves `sleeping`. */
  wake() {
    if (!this.asleep) return;
    this.asleep = false;
    this.notify();
  }
```

- [ ] **Step 4: The mini cats, the island and the hook handlers**

```ts title="windows/src/cat/minibots.ts" old
import type { AgentTask } from "../core/state";
```

```ts title="windows/src/cat/minibots.ts" new
import { State, type AgentTask } from "../core/state";
```

```ts title="windows/src/cat/minibots.ts" old
  engine.setState(task.state, true);
```

```ts title="windows/src/cat/minibots.ts" new
  engine.setState(State.shownState(task.state), true);
```

```ts title="windows/src/cat/minibots.ts" old
    mb.engine.setState(task.state);
```

```ts title="windows/src/cat/minibots.ts" new
    mb.engine.setState(State.shownState(task.state));
```

```ts title="windows/src/island/island.ts" old
import { IslandStateMachine } from "./fsm";
```

```ts title="windows/src/island/island.ts" new
import { IslandStateMachine } from "./fsm";
import { SleepClock } from "./sleep";
```

```ts title="windows/src/island/island.ts" old
  readonly fsm = new IslandStateMachine();
```

```ts title="windows/src/island/island.ts" new
  readonly fsm = new IslandStateMachine();

  /** The cats' ten-minute nap: one timer, started by every event, never a poll (island/sleep.ts). */
  private sleep = new SleepClock({
    now: () => performance.now(),
    state: () => State.stateOverride ?? State.focusTask?.state ?? "idle",
    blocked: () => State.pendingApproval !== null || State.chatApprovals.length > 0 || State.tasks.some((t) => t.state === "approval" || t.state === "question"),
    set: (fn, ms) => window.setTimeout(fn, ms),
    clear: (id) => window.clearTimeout(id),
    fall: () => State.fallAsleep(),
    wake: () => State.wake(),
  });
```

```ts title="windows/src/island/island.ts" old
    this.islandEl.addEventListener("mousedown", (e) => {
      Sound.resume();
```

```ts title="windows/src/island/island.ts" new
    this.islandEl.addEventListener("mousedown", (e) => {
      Sound.resume();
      this.sleep.event("click");
```

```ts title="windows/src/island/island.ts" old
    if (inIsland && !this.wasInIsland) {
      if (this.fsm.state === "hello") this.greeting.hover();
```

```ts title="windows/src/island/island.ts" new
    if (inIsland && !this.wasInIsland) {
      this.sleep.event("hover");
      if (this.fsm.state === "hello") this.greeting.hover();
```

```ts title="windows/src/island/island.ts" old
  /** Cursor in window-logical coordinates. */
  onCursor(x: number, y: number) {
```

```ts title="windows/src/island/island.ts" new
  /** An agent event, a hover or a click: wakes a sleeping cat and starts its ten minutes again (island/sleep.ts). The hook handlers call it for every event. */
  noteActivity(kind: "hook" | "hover" | "click") {
    this.sleep.event(kind);
  }

  /** Cursor in window-logical coordinates. */
  onCursor(x: number, y: number) {
```

```ts title="windows/src/island/hooks.ts" old
function handleHook(island: Island, payload: HookPayload) {
  if (State.paused) {
```

```ts title="windows/src/island/hooks.ts" new
function handleHook(island: Island, payload: HookPayload) {
  island.noteActivity("hook");
  if (State.paused) {
```

- [ ] **Step 5: Two buttons on the `?dev` sheet, to watch it**

```ts title="windows/src/cat/dev.ts" old
    strip,
  );
  const readout = document.createElement("p");
```

```ts title="windows/src/cat/dev.ts" new
    (() => {
      // The sleeping cat of the strip: wake it to see what Playful does (zoomies after 220 ms) and what Classic does (nothing).
      const r = row("Sleep");
      const sleeper = () => live.find((l) => l.st === "sleeping")?.e;
      r.append(button("Wake the sleeping cat", () => sleeper()?.setState("idle")), button("Put it back to sleep", () => sleeper()?.setState("sleeping")));
      return r;
    })(),
    strip,
  );
  const readout = document.createElement("p");
```

- [ ] **Step 6: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/sleep.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 9`, `# pass 9`, `# fail 0`, `tsc exit 0`, then `ℹ tests 150`, `ℹ pass 150`, `ℹ fail 0`.

- [ ] **Step 7: Look at the waking zoomies**

Run the sheet as in Task 9 Step 3 (Vite on a free port, the `?dev` page in a headless browser) and watch the States strip: the **sleeping** cat has its eyes closed and a "z" now and then; press "Wake the sleeping cat" and, in Playful, it jumps into zoomies about a quarter of a second later, then settles; switch the Motion to Classic, put it back to sleep and wake it: no zoomies.

```bash
SHOTS="${TMPDIR:-/tmp}/a-tauri-57-shots"; mkdir -p "$SHOTS"; WT="$(git rev-parse --show-toplevel)"
(cd "$WT/windows" && npx --no-install vite --port 14571 > "$SHOTS/vite.log" 2>&1 &)
sleep 3
cd "$SHOTS"
playwright-cli -s=sheet open "http://127.0.0.1:14571/?dev"
playwright-cli -s=sheet resize 1300 1500
playwright-cli -s=sheet run-code "async page => { const strip = page.locator('figure', { has: page.getByText('sleeping', { exact: true }) }); await page.waitForTimeout(600); await strip.screenshot({ path: 'sleep-asleep.png' }); await page.getByRole('button', { name: 'Wake the sleeping cat' }).click(); await page.waitForTimeout(700); await strip.screenshot({ path: 'sleep-wake-playful.png' }); }"
playwright-cli -s=sheet close
kill $(lsof -ti tcp:14571) 2>/dev/null; ls "$SHOTS"/sleep-*.png
```

Expected: `sleep-asleep.png` and `sleep-wake-playful.png`. In the first the cat sleeps; in the second it is awake and moving: its eyes open and wide (zoomies blow the pupils up) and its position off centre (the caption still says "sleeping": it names the strip's slot). If it does not wake, or wakes quietly in Playful, look at `enter` in `motion/playful.ts` and at the button's wiring. Say what you saw to the controller.

- [ ] **Step 8: Commit**

```bash
git add windows/src/cat/base.ts windows/src/island/sleep.ts windows/src/core/state.ts windows/src/cat/minibots.ts windows/src/island/island.ts windows/src/island/hooks.ts windows/src/cat/dev.ts windows/scripts/cat-tests/sleep.test.mjs
git commit -m "feat(cat): an idle cat sleeps after ten minutes with no agent event, and any hook, hover or click wakes it

One timer, reset by every event, never a poll. It never sleeps through an approval or a question. The pills and the compact grid sleep with
the big cat. Playful wakes with zoomies (already in its enter). Nothing runs while the island is hidden.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 12: The music bob

**Agent:** `nm-implementer`.

Spec §3, "Music": the existing Apple Music dance bounce drives a head-bob, with the ears bouncing on the beat. **The Windows and Linux app has no music source today** (no media reader, no `integration_music` pill, no `musicPlaying`, and no dance in the cat engine: the Mac's `CatEngine.setDancing` and `CatEffects.applyDance` were never ported). So this task builds the cat's side of the bob and a switch for it, and leaves the source of "music is playing" to a later plan (a Windows media-session reader and Linux MPRIS, see the open questions). It is its own task, and the last of stage 6, so the owner can cut it without touching the rest.

**Files:**
- Create: `windows/src/cat/dance.ts`, `windows/scripts/cat-tests/dance.test.mjs`
- Modify: `windows/src/cat/engine.ts` (`isDancing`, `dancingLevel`, `setDancing`, the beat in `draw`, the ears in `computeTargets`), `windows/src/core/state.ts` (`musicPlaying`), `windows/src/island/island.ts`, `windows/src/cat/dev.ts` (one button)

**Interfaces:**
- Consumes: nothing new from the contract: "The Apple Music dance is an existing member of each app's engine (`setDancing`, `applyDance`); the prototype has no music, so the core adds nothing for it" (`docs/CAT-CONTRACT.md`). The numbers are the Mac's `CatEffects.applyDance` and `CatEngine`'s dancing level (112 BPM; a hop of 0.20 R with a sway of 0.08 R and a roll of 0.10 rad; a landing squash of 0.045 wide and 0.06 flat; the level fades in over 0.3 s and out over 0.5 s).
- Produces `src/cat/dance.ts` (pure, loadable in plain Node): `DANCE_BPM` (112), `dancePose(level, seconds, R)` (`{ dx, dy, rot, sx, sy }`), `applyDance(ctx, level, seconds, px, py, R)` (translate, roll and squash around the bottom of the head, as the Mac does), `danceLevel(level, on, dt)` (the fade), `danceEars(level, seconds)` and `shouldDance(playing, state, mode)`. In `BotEngine`: `isDancing`, `dancingLevel` (0 to 1), `setDancing(on)`; `draw` applies the bob around the whole cat, and the ears **bounce on the landing beat** (`earU` target up to 0.14 above rest, scaled by the level), which is the one Windows addition: the Mac's `applyDance` moves the head and the ears ride with it. At level 0 nothing changes, so every fixture row is as it was. `State.musicPlaying` (false, and nothing sets it yet), and the island: `engine.setDancing(shouldDance(State.musicPlaying, State.effectiveState, State.mode))` on every frame it draws the big cat. Like the Mac, only the **compact** island's cat dances (the Mac's expanded case is the music pill's card, which Windows does not have), only in `idle`, `working`, `thinking`, `searching` and `finished`, never asleep.
- On the `?dev` sheet, a "dance" button on the big cat, to see it.

- [ ] **Step 1: Write the failing tests**

```js title="windows/scripts/cat-tests/dance.test.mjs" create
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { DANCE_BPM, applyDance, danceEars, danceLevel, dancePose, shouldDance } from "../../src/cat/dance.ts";
import { BotEngine } from "../../src/cat/engine.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { State } from "../../src/core/state.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";
import { near } from "./util.mjs";

installBrowserStubs();
const BEAT = 60 / DANCE_BPM;
const make = (extra = {}) => { const clock = { t: 0 }; const e = new BotEngine(PRESETS.momo, { now: () => clock.t, rand: () => 0.5, quiet: true, ...extra }); return { e, clock, step: (ms) => { clock.t += ms; e.update(ms / 1000); } }; };

test("the bob is the Mac's: a hop of 0.20 R, a sway of 0.08 R, a roll of 0.10 rad and a landing squash, on the 112 BPM beat", () => {
  assert.equal(DANCE_BPM, 112);
  const land = dancePose(1, 0, 10), air = dancePose(1, BEAT / 2, 10);
  near(land.dx, 0); near(land.dy, 0); near(land.rot, 0); near(land.sx, 1.045); near(land.sy, 0.94);
  near(air.dx, 0.8); near(air.dy, -2); near(air.rot, 0.1); near(air.sx, 1); near(air.sy, 1);
  const half = dancePose(0.5, BEAT / 2, 10);
  near(half.dy, -1); near(half.dx, 0.4);
  const rest = dancePose(0, 0.123, 10);
  for (const k of ["dx", "dy", "rot"]) near(rest[k], 0);
  near(rest.sx, 1); near(rest.sy, 1);
  near(dancePose(1, 5 * BEAT + 0.01, 10).dy, dancePose(1, 0.01, 10).dy, 1e-9);
});

test("applyDance turns, rolls and squashes around the bottom of the head, and does nothing at level 0 or for a bad number", () => {
  const log = [], c = { translate: (...a) => log.push(["translate", ...a]), rotate: (...a) => log.push(["rotate", ...a]), scale: (...a) => log.push(["scale", ...a]) };
  applyDance(c, 1, BEAT / 2, 50, 70, 10);
  assert.deepEqual(log.map((l) => l[0]), ["translate", "rotate", "scale", "translate"]);
  near(log[0][1], 50.8); near(log[0][2], 68); near(log[1][1], 0.1); assert.deepEqual(log[3], ["translate", -50, -70]);
  log.length = 0;
  for (const level of [0, 0.001, -1, NaN, Infinity - Infinity]) applyDance(c, level, 1, 50, 70, 10);
  assert.equal(log.length, 0);
});

test("the dancing level fades in over 0.3 s and out over 0.5 s, and a bad frame time changes nothing", () => {
  let l = 0;
  for (let i = 0; i < 10; i++) l = danceLevel(l, true, 0.03);
  near(l, 1);
  assert.equal(danceLevel(1, true, 5), 1, "held at 1");
  let o = 1;
  for (let i = 0; i < 10; i++) o = danceLevel(o, false, 0.05);
  near(o, 0);
  assert.equal(danceLevel(0, false, 5), 0, "held at 0");
  for (const dt of [NaN, -1, Infinity - Infinity]) assert.equal(danceLevel(0.4, true, dt), 0.4, String(dt));
});

test("the ears bounce on the landing beat: up to 0.14 at the landing, none in the air, scaled by the level", () => {
  near(danceEars(1, 0), 0.14);
  near(danceEars(1, BEAT / 2), 0);
  near(danceEars(0.5, 0), 0.07);
  assert.equal(danceEars(0, 0), 0);
});

test("only the compact island's cat dances, only in the states the Mac allows, never asleep, and only while music plays", () => {
  for (const state of ["idle", "working", "thinking", "searching", "finished"]) assert.equal(shouldDance(true, state, "compact"), true, state);
  for (const state of ["approval", "question", "error", "ratelimit", "sleeping", "dizzy"]) assert.equal(shouldDance(true, state, "compact"), false, state);
  assert.equal(shouldDance(false, "idle", "compact"), false);
  for (const mode of ["hidden", "expanded"]) assert.equal(shouldDance(true, "idle", mode), false, mode);
});

test("an engine bobs while music plays: the level rises over 0.3 s, the canvas is moved and put back, and the ears bounce; at level 0 nothing changes", () => {
  const { e, step } = make();
  const calls = () => { const ctx = fakeCanvas(); e.draw(ctx, 100, 100); return ctx.calls; };
  assert.equal(e.isDancing, false);
  assert.equal(e.dancingLevel, 0);
  const still = calls();
  e.setDancing(true);
  for (let i = 0; i < 20; i++) step(16);
  assert.equal(e.dancingLevel, 1);
  const moving = calls();
  assert.ok(moving.translate > still.translate && moving.rotate > (still.rotate || 0), "the bob translates and rolls the canvas");
  assert.equal(moving.save, moving.restore, "and puts it back");
  e.setDancing(false);
  for (let i = 0; i < 40; i++) step(16);
  assert.equal(e.dancingLevel, 0);
  const back = calls();
  assert.deepEqual([back.translate, back.rotate || 0, back.scale], [still.translate, still.rotate || 0, still.scale], "the canvas is no longer moved");
  const earsOn = make(), earsOff = make();
  earsOn.e.setDancing(true);
  for (let i = 0; i < 30; i++) { earsOn.step(16); earsOff.step(16); }
  earsOn.e.computeTargets(0, 0); earsOff.e.computeTargets(0, 0);
  near(earsOn.e.tg.earU - earsOff.e.tg.earU, 0.14, 1e-9);
});

test("the seam: music is not playing, and the island asks shouldDance every frame it draws the big cat", () => {
  assert.equal(State.musicPlaying, false);
  const island = fs.readFileSync(new URL("../../src/island/island.ts", import.meta.url), "utf8");
  assert.match(island, /this\.engine\.setDancing\(shouldDance\(State\.musicPlaying, State\.effectiveState, State\.mode\)\);/);
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/dance.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; cd ..`
Expected: `not ok 1 - scripts/cat-tests/dance.test.mjs`, `# tests 1`, `# pass 0`, `# fail 1`.

- [ ] **Step 3: The module**

```ts title="windows/src/cat/dance.ts" create
// The music bob (spec §3, "Music"): the cat hops and sways to the beat while music plays, with its ears bouncing as it lands. The numbers are the Mac's
// (CatEffects.applyDance and CatEngine's dancing level: 112 BPM, a hop of 0.20 R, a sway of 0.08 R, a roll of 0.10 rad, a landing squash, a fade in
// over 0.3 s and out over 0.5 s). The ear bounce is this app's own: the Mac's bob moves the head and the ears ride with it. Pure, so the plain-Node
// checks (npm run check:cat) can load it. Nothing on Windows or Linux says "music is playing" yet: `State.musicPlaying` is the seam.

/** The tempo of the dance. */
export const DANCE_BPM = 112;

const beatOf = (seconds: number) => (seconds * DANCE_BPM) / 60;
/** 1 as the head lands, 0 in the air: the landing squash and the ears follow it. */
const landing = (beat: number) => Math.pow(1 - Math.abs(Math.sin(Math.PI * beat)), 6);

export interface DancePose { dx: number; dy: number; rot: number; sx: number; sy: number }

/** Where the head is on the beat: moved by (dx, dy) px, rolled by `rot` rad, squashed by (sx, sy). `level` (0 to 1) is how much it dances, R the head radius in px. */
export function dancePose(level: number, seconds: number, R: number): DancePose {
  const beat = beatOf(seconds), s = Math.sin(Math.PI * beat), hop = Math.abs(s), land = landing(beat);
  return { dx: 0.08 * R * s * level, dy: -0.2 * R * hop * level, rot: 0.1 * s * level, sx: 1 + 0.045 * land * level, sy: 1 - 0.06 * land * level };
}

/** The part of a canvas context the bob needs. */
export interface DanceCtx { translate(x: number, y: number): void; rotate(a: number): void; scale(x: number, y: number): void }

/** Applies the bob to the context around the bottom of the head (px, py) before the cat is drawn. Does nothing at level 0 or for a bad number. */
export function applyDance(c: DanceCtx, level: number, seconds: number, px: number, py: number, R: number): void {
  if (!(level > 0.001)) return;
  const p = dancePose(level, seconds, R);
  c.translate(px + p.dx, py + p.dy);
  c.rotate(p.rot);
  c.scale(p.sx, p.sy);
  c.translate(-px, -py);
}

/** The dancing level one frame later: it rises over 0.3 s while music plays and falls over 0.5 s after. A bad frame time changes nothing. */
export function danceLevel(level: number, on: boolean, dt: number): number {
  if (!(dt >= 0) || !Number.isFinite(dt)) return level;
  return on ? Math.min(1, level + dt / 0.3) : Math.max(0, level - dt / 0.5);
}

/** How much higher the ears stand than at rest (a delta on the `earU` target): they spring up as the head lands and settle as it rises. */
export const danceEars = (level: number, seconds: number): number => 0.14 * level * landing(beatOf(seconds));

/** The states in which the Mac's cat dances: not asleep, not asking, not hurt. */
const DANCE_STATES: ReadonlySet<string> = new Set(["idle", "working", "thinking", "searching", "finished"]);

/** Whether the cat bobs now: music plays, the island is compact (the Mac's expanded case is the music pill's card, which this app does not have), and the cat is in a calm state. */
export const shouldDance = (playing: boolean, state: string, mode: string): boolean => playing && mode === "compact" && DANCE_STATES.has(state);
```

- [ ] **Step 4: The engine, the state and the island**

```ts title="windows/src/cat/engine.ts" old
import { catById } from "./presets.ts";
```

```ts title="windows/src/cat/engine.ts" new
import { applyDance, danceEars, danceLevel } from "./dance.ts";
import { catById } from "./presets.ts";
```

```ts title="windows/src/cat/engine.ts" old
  onDizzy: (() => void) | null = null;
```

```ts title="windows/src/cat/engine.ts" new
  onDizzy: (() => void) | null = null;
  /** Music is playing: the cat bobs to it (cat/dance.ts). Set with `setDancing`; `dancingLevel` follows it, 0 to 1. */
  isDancing = false;
  dancingLevel = 0;
```

```ts title="windows/src/cat/engine.ts" old
    tg.yaw = ty; tg.pitch = tp;
  }
```

```ts title="windows/src/cat/engine.ts" new
    tg.yaw = ty; tg.pitch = tp;
    // The ears bounce on the landing beat while the cat dances (nothing at level 0, so every fixture row is as it was).
    if (this.dancingLevel > 0.001) tg.earU += danceEars(this.dancingLevel, T);
  }
```

```ts title="windows/src/cat/engine.ts" old
    this.chew = t >= this.chewStart && t < this.chewUntil ? 0.16 * (0.5 - 0.5 * Math.cos((TAU * 4.2 * (t - this.chewStart)) / 1000)) : 0;
  }
```

```ts title="windows/src/cat/engine.ts" new
    this.chew = t >= this.chewStart && t < this.chewUntil ? 0.16 * (0.5 - 0.5 * Math.cos((TAU * 4.2 * (t - this.chewStart)) / 1000)) : 0;
    this.dancingLevel = danceLevel(this.dancingLevel, this.isDancing, dt);
  }
```

```ts title="windows/src/cat/engine.ts" old
  /** The island's emotes. The duration the old engine took is gone: each emote has its own length now. */
```

```ts title="windows/src/cat/engine.ts" new
  /** Music starts or stops: the cat bobs to it, fading in over 0.3 s and out over 0.5 s. */
  setDancing(on: boolean) { this.isDancing = on; }

  /** The island's emotes. The duration the old engine took is gone: each emote has its own length now. */
```

```ts title="windows/src/cat/engine.ts" old
    const cy = H / 2 + this.particleOverhang / 2;
    drawCat(x, this, W / 2, cy, W * 0.6, { badgeSide: this.badgeLeft ? -1 : 1, earCeiling: this.earRoom === null ? undefined : cy - this.earRoom, fur: this.cfg.fur,
      collar: this.collarColor ? { style: this.cfg.collar ?? "off", col: this.collarColor } : null });
```

```ts title="windows/src/cat/engine.ts" new
    const cy = H / 2 + this.particleOverhang / 2, D = W * 0.6, dance = this.dancingLevel > 0.001;
    // The bob moves the whole cat around the bottom of its head: head, ears, collar, badge and all.
    if (dance) { x.save(); applyDance(x, this.dancingLevel, this.now() / 1000, W / 2, cy + D * 0.45, D / 2); }
    drawCat(x, this, W / 2, cy, D, { badgeSide: this.badgeLeft ? -1 : 1, earCeiling: this.earRoom === null ? undefined : cy - this.earRoom, fur: this.cfg.fur,
      collar: this.collarColor ? { style: this.cfg.collar ?? "off", col: this.collarColor } : null });
    if (dance) x.restore();
```

```ts title="windows/src/core/state.ts" old
  asleep = false;
```

```ts title="windows/src/core/state.ts" new
  asleep = false;

  /** Music is playing: the cat in the compact island bobs to it (cat/dance.ts). Nothing sets this on Windows and Linux yet: there is no media reader, so it is the seam a later plan fills. */
  musicPlaying = false;
```

```ts title="windows/src/island/island.ts" old
import { bigCatCollar } from "../cat/collar";
```

```ts title="windows/src/island/island.ts" new
import { bigCatCollar } from "../cat/collar";
import { shouldDance } from "../cat/dance";
```

```ts title="windows/src/island/island.ts" old
    this.engine.lookX = this.lookX();
```

```ts title="windows/src/island/island.ts" new
    this.engine.setDancing(shouldDance(State.musicPlaying, State.effectiveState, State.mode));
    this.engine.lookX = this.lookX();
```

```ts title="windows/src/cat/dev.ts" old
  emoteRow.append(button("hairball", () => stage.emote("hairball")));
```

```ts title="windows/src/cat/dev.ts" new
  emoteRow.append(button("hairball", () => stage.emote("hairball")));
  emoteRow.append(button("dance (music)", () => stage.setDancing(!stage.isDancing)));
```

- [ ] **Step 5: Run the tests, the type check and the whole cat check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/dance.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 7`, `# pass 7`, `# fail 0`, `tsc exit 0`, then `ℹ tests 157`, `ℹ pass 157`, `ℹ fail 0` (the fixture rows of the engine, the emotes and the catch are among them and still pass: the dance is 0 there).

- [ ] **Step 6: Look at it**

Serve the sheet as in Task 9 Step 3, press "dance (music)" on the big cat of the Emotes panel and take four frames a tenth of a second apart. The cat should hop and sway around the bottom of its head, squash as it lands, and its ears should stand a little taller on the landing.

```bash
SHOTS="${TMPDIR:-/tmp}/a-tauri-57-shots"; mkdir -p "$SHOTS"; WT="$(git rev-parse --show-toplevel)"
(cd "$WT/windows" && npx --no-install vite --port 14571 > "$SHOTS/vite.log" 2>&1 &)
sleep 3
cd "$SHOTS"
playwright-cli -s=sheet open "http://127.0.0.1:14571/?dev"
playwright-cli -s=sheet resize 1300 1500
playwright-cli -s=sheet run-code "async page => { const cv = page.locator('#stage-cat'); await page.getByRole('button', { name: 'dance (music)' }).click(); await page.waitForTimeout(700); for (let i = 0; i < 6; i++) { await cv.screenshot({ path: 'dance-' + i + '.png' }); await page.waitForTimeout(90); } }"
playwright-cli -s=sheet close
kill $(lsof -ti tcp:14571) 2>/dev/null; ls "$SHOTS"/dance-*.png
```

Expected: `dance-0.png` to `dance-5.png`. Across the six frames the head moves up and down by up to a fifth of its radius, leans left and right, and is a little squashed on the landing frame. If it does not move, look at `draw` in `engine.ts` and at `setDancing`. Say what you saw to the controller.

- [ ] **Step 7: Commit**

```bash
git add windows/src/cat/dance.ts windows/src/cat/engine.ts windows/src/core/state.ts windows/src/island/island.ts windows/src/cat/dev.ts windows/scripts/cat-tests/dance.test.mjs
git commit -m "feat(cat): the cat bobs to music: the Mac's dance, ears bouncing on the landing beat

setDancing and dancingLevel on the engine, applyDance around the bottom of the head. State.musicPlaying is the seam: Windows and Linux have no
media reader yet, so nothing sets it. Only the compact island's cat dances, in the calm states, never asleep.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

# Stage 7: theme tokens, dead code and the Mochi sweep

### Task 13: The theme tokens replace the hard-coded colours, with no pixel changed

**Agent:** `nm-implementer`.

A-0d wrote `shared/theme.json`, its generator and the three generated files, and listed every place where the character, branding and greeting colours are hard-coded (`docs/THEME.md`, "Where each colour is hard-coded today"). This task replaces **exactly the Windows and Linux sites of that list** with `THEME` (`windows/src/theme.generated.ts`), and changes no pixel. The one exception, the island's glow literals in `core/layout.ts`, is an existing view's code and waits for the owner's answer: it is Task 14. Colours that look the same in an existing view (`#F5A524` in the island, `#F4505E` in `style.css`, the `--card` of the two stylesheets) are upstream's UI colours and **stay**.

**Files:**
- Modify: `windows/src/cat/renderer.ts` (14 sites), `windows/src/cat/greeting.ts` (7 sites), `windows/src/cat/base.ts` (the state colours and glows), `windows/src/cat/dev.ts` (the 14 sites of the fork's own page palette)
- One-off, not committed: `${TMPDIR:-/tmp}/a-tauri-57-check/snap.mjs` and `dev-fingerprint.js`

**Interfaces:**
- Consumes (A-0d, merged): `THEME` and `THEME_RGB` from `windows/src/theme.generated.ts`: `THEME.cat.pupil`, `mouthInside`, `tongue`, `teeth`, `heart`, `star`, `sweat`, `paper`, `paperFold`, `paperLabel`; `THEME.greeting.badge`, `headerDim`, `card`, `streaks`, and `THEME_RGB.greeting.tint`, `haloGold`, `haloBlue`; `THEME.state.color` and `THEME.state.glow`; `THEME.brand.accent`, `page`, `panel`, `line`, `ink`, `dim`, `button`. Every value is the one that is hard-coded today, in capitals; a colour is the same colour whatever its case.
- Produces: no new name. `COL` and `GLOW` in `base.ts` are now the generated state colours (`THEME.state.color`, `THEME.state.glow`), with the same keys and the same values, so every fixture row is unchanged. `base.ts` and `greeting.ts` import `../theme.generated.ts` (plain data, no imports of its own), so the plain-Node checks still load them. The CSS file `theme.generated.css` is not used by the Windows app: none of the Windows sites is in a stylesheet.

**The proof.** There are no pixel tests, so the proof is a before and after comparison, run on the tree before the first edit and again after the last. `snap.mjs` draws, into a canvas that records every call and every style in order (colours in lower case, so `#8d9098` and `#8D9098` are one colour), all 16 coats and their kittens at four sizes in three moods (idle; in love, with hearts, stars, sweat, an open mouth and its tongue; proud, with a file in a hairball), the file icon, thirteen moments of the greeting, the state tables and the island's glow, and prints one SHA-256 per scene. `dev-fingerprint.js` fingerprints the `?dev` page: its HTML (in lower case, with the live timing line left out) and the coat ladder's pixels. Both must come out the same before and after. They also say which colours they saw, so a scene that never drew a token would be caught (`"uncovered": []`).

- [ ] **Step 1: Write the two one-off scripts**

```bash
CHK="${TMPDIR:-/tmp}/a-tauri-57-check"; mkdir -p "$CHK"
cat > "$CHK/snap.mjs" <<'EOF'
// One-off, never committed: a before/after proof that swapping hard-coded colours for the theme tokens changes no pixel. It draws the cats, the file
// icon, the hairball, the greeting and the island glow into a canvas that records every call and every style in order (colours in lower case), and
// prints one SHA-256 and a line count per scene. Run it from the repository root: node --experimental-strip-types <this file>
import crypto from "node:crypto";
import { pathToFileURL } from "node:url";

// The greeting's cat reads the clock itself: stop it, so the same drawing gives the same record every time.
Object.defineProperty(globalThis, "performance", { value: { now: () => 5000 }, configurable: true });
const root = `${process.cwd()}/windows/`;
const load = (rel) => import(pathToFileURL(root + rel).href);
const { installBrowserStubs } = await load("scripts/cat-tests/fake-canvas.mjs");
installBrowserStubs();
const { drawCat, drawFileIcon, stillView } = await load("src/cat/renderer.ts");
const { newPose } = await load("src/cat/geometry.ts");
const { CAT_IDS, PRESETS, kittenOf } = await load("src/cat/presets.ts");
const { COL, GLOW, TINT, BADGE, STATES } = await load("src/cat/base.ts");
const { Greeting } = await load("src/cat/greeting.ts");
const { botGlowColor, botGlowOpacity } = await load("src/core/layout.ts");

const fmt = (v) => (typeof v === "number" ? String(Math.round(v * 1e6) / 1e6) : typeof v === "string" ? v.toLowerCase().replace(/\s+/g, "") : Array.isArray(v) ? `[${v.map(fmt)}]` : typeof v);
function recorder() {
  const log = [], store = {}, grad = { addColorStop: (...a) => log.push(`stop ${a.map(fmt)}`) };
  const ctx = new Proxy(store, {
    get(t, k) {
      if (k in t) return t[k];
      if (k === "createLinearGradient" || k === "createRadialGradient") return (...a) => { log.push(`${String(k)} ${a.map(fmt)}`); return grad; };
      if (k === "measureText") return () => ({ width: 10 });
      if (k === "isPointInPath") return () => false;
      return (...a) => { log.push(`${String(k)} ${a.map(fmt)}`); };
    },
    set(t, k, v) { log.push(`set ${String(k)} ${fmt(v)}`); t[k] = v; return true; },
  });
  return { log, ctx };
}
const out = {}, everything = [];
const done = (name, lines) => { for (const l of lines) everything.push(l); out[name] = { sha256: crypto.createHash("sha256").update(lines.join("\n")).digest("hex").slice(0, 24), lines: lines.length }; };

// 1. Every coat and kitten, at four sizes: idle, in love (hearts, stars, sweat, an open mouth with its tongue) and proud (a file in a hairball).
{
  const { log, ctx } = recorder();
  const part = (k) => ({ k, x: 0.3, y: -0.9, vx: 0, vy: 0, age: 0.4, life: 1.5, size: 0.2, rot: 1 });
  const kinds = [
    { eye: null, pose: {}, parts: [], balls: [] },
    { eye: "heart", pose: { blush: 1, tongue: 1, mouth: 0.6, smile: 0.5, mround: 0.3 }, parts: ["heart", "star", "sweat", "spark", "dust", "hair", "z"], balls: [] },
    { eye: "star", pose: { mouth: 0.9, tongue: 0.4, mround: 0.6, smile: -0.4 }, parts: [], balls: [{ x: 0.5, y: 1, vx: 0, vy: 0, rot: 0.3, age: 0.5, life: 2.4, file: null, seed: 7, floor: 1.1 }, { x: -0.5, y: 1, vx: 0, vy: 0, rot: 0.1, age: 0.5, life: 2.6, file: "PDF", seed: 9, floor: 1.1 }] },
  ];
  for (const id of CAT_IDS) for (const kit of [false, true]) for (const D of [12, 20, 28, 66]) for (const k of kinds) {
    const v = stillView(kit ? kittenOf(PRESETS[id]) : PRESETS[id], { ...newPose(), ...k.pose });
    if (k.eye) v.eyeShape = () => k.eye;
    v.mouthOpen = () => k.pose.mouth ?? 0;
    v.parts = k.parts.map(part);
    v.balls = k.balls;
    log.push(`-- ${id} ${kit} ${D} ${k.eye}`);
    drawCat(ctx, v, 100, 80, D, { glow: true, collar: null, dpr: 2 });
  }
  drawFileIcon(ctx, 10, 10, 30, 0.2, "PDF");
  done("cats", log);
}

// 2. The greeting, at thirteen moments of its timeline.
{
  const { log, ctx } = recorder();
  globalThis.window = { setTimeout: () => 0, clearTimeout: () => {} };
  for (const t of [0.2, 0.7, 1.3, 1.9, 2.4, 2.8, 3.4, 4.0, 4.9, 5.2, 5.6, 6.1, 6.5]) {
    const g = new Greeting();
    g.start();
    Object.defineProperty(g, "elapsed", { get: () => t });
    log.push(`-- greeting ${t}`);
    g.draw(ctx);
  }
  delete globalThis.window;
  done("greeting", log);
}

// 3. The state tables and the island's glow.
done("tables", [JSON.stringify({ COL, TINT, GLOW, BADGE, STATES })]);
done("glow", STATES.map((s) => `${s} ${botGlowColor(s).toLowerCase()} ${botGlowOpacity(s)}`));

// What the scenes must have drawn, or the proof proves nothing: each colour the swap touches (a hex, or its r, g, b), as the renderer, the greeting and the glow use it.
const NEEDLES = ["#0e0b09", "#3a1218", "#e8798c", "#fbf7f0", "#ff4d6d", "#f7b32b", "#7cc7ff", "#f4f5f7", "#c9cdd4", "#3b9eff", "#3ba0f5", "#141518", "#8d9098",
  "127,180,234", "232,195,154", "59,158,255", "#f29b38", "#ff5a4e", "#2ec4a0", "#a78bfa", "#8b5cf6", "#f59e0b"];
const text = everything.join("\n").toLowerCase();
out.uncovered = NEEDLES.filter((n) => !text.includes(n));
console.log(JSON.stringify(out, null, 1));
EOF
cat > "$CHK/dev-fingerprint.js" <<'EOF'
async () => {
  const sha = async (s) => [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 16);
  await new Promise((r) => setTimeout(r, 800));
  // In lower case: a hex colour written in an attribute is the same colour in any case (the tokens are in capitals).
  const html = document.documentElement.outerHTML.replace(/Drawing per frame:[^<]*/g, "").toLowerCase();
  const ladder = document.querySelector('canvas[aria-label="Every coat at every size"]').toDataURL();
  return JSON.stringify({ html: await sha(html), ladder: await sha(ladder) });
}
EOF
ls "$CHK"
```

Expected: `dev-fingerprint.js  snap.mjs`.

- [ ] **Step 2: Record the "before"**

```bash
CHK="${TMPDIR:-/tmp}/a-tauri-57-check"
node --experimental-strip-types "$CHK/snap.mjs" > "$CHK/before.json"; node --experimental-strip-types "$CHK/snap.mjs" > "$CHK/before2.json"
cmp "$CHK/before.json" "$CHK/before2.json" && echo "the record is the same twice"
tr -d '\n ' < "$CHK/before.json"; echo
WT="$(git rev-parse --show-toplevel)"
(cd "$WT/windows" && npx --no-install vite --port 14571 > "$CHK/vite.log" 2>&1 &)
sleep 3
cd "$CHK"   # playwright-cli leaves a .playwright-cli folder in its working directory: not the repository
playwright-cli -s=theme open "http://127.0.0.1:14571/?dev" > /dev/null
playwright-cli -s=theme eval "$(cat "$CHK/dev-fingerprint.js")" | sed -n 2p | tee "$CHK/dev-before.txt"
playwright-cli -s=theme close > /dev/null
kill $(lsof -ti tcp:14571) 2>/dev/null; true
```

Expected: `the record is the same twice`; then one line with the four scenes, `{"cats":{"sha256":"…","lines":416506},"greeting":{"sha256":"…","lines":24414},"tables":{"sha256":"…","lines":1},"glow":{"sha256":"…","lines":11},"uncovered":[]}` (the hashes depend on the tree: only that they match after the edits matters); then a line such as `"{\"html\":\"…\",\"ladder\":\"…\"}"`. `"uncovered":[]` must be empty: if a colour is listed, a scene does not draw it and the proof is weaker than it should be: stop and report.

- [ ] **Step 3: The renderer's 14 sites**

```ts title="windows/src/cat/renderer.ts" old
import type { Ball, CatPreset, EyeShape, Particle, Pose } from "./types.ts";
```

```ts title="windows/src/cat/renderer.ts" new
import type { Ball, CatPreset, EyeShape, Particle, Pose } from "./types.ts";
import { THEME } from "../theme.generated.ts";
```

```ts title="windows/src/cat/renderer.ts" old
c.fillStyle = "#0E0B09";
```

```ts title="windows/src/cat/renderer.ts" new
c.fillStyle = THEME.cat.pupil;
```

```ts title="windows/src/cat/renderer.ts" old
c.fillStyle = "#FF4D6D"; heartP(c, 1.2 * w);
```

```ts title="windows/src/cat/renderer.ts" new
c.fillStyle = THEME.cat.heart; heartP(c, 1.2 * w);
```

```ts title="windows/src/cat/renderer.ts" old
c.fillStyle = "#F7B32B"; c.rotate(T * 1.5 * sd);
```

```ts title="windows/src/cat/renderer.ts" new
c.fillStyle = THEME.cat.star; c.rotate(T * 1.5 * sd);
```

```ts title="windows/src/cat/renderer.ts" old
c.fillStyle = "#FF4D6D"; heartP(c, sz * 1.6);
```

```ts title="windows/src/cat/renderer.ts" new
c.fillStyle = THEME.cat.heart; heartP(c, sz * 1.6);
```

```ts title="windows/src/cat/renderer.ts" old
c.fillStyle = "#F7B32B"; starP(c, sz, sz * 0.45);
```

```ts title="windows/src/cat/renderer.ts" new
c.fillStyle = THEME.cat.star; starP(c, sz, sz * 0.45);
```

```ts title="windows/src/cat/renderer.ts" old
c.fillStyle = "#7CC7FF";
```

```ts title="windows/src/cat/renderer.ts" new
c.fillStyle = THEME.cat.sweat;
```

```ts title="windows/src/cat/renderer.ts" old
c.fillStyle = "#3A1218"; path(); c.fill();
```

```ts title="windows/src/cat/renderer.ts" new
c.fillStyle = THEME.cat.mouthInside; path(); c.fill();
```

```ts title="windows/src/cat/renderer.ts" old
c.fillStyle = "#E8798C"; c.beginPath(); c.ellipse(cxm, top + h * 0.95,
```

```ts title="windows/src/cat/renderer.ts" new
c.fillStyle = THEME.cat.tongue; c.beginPath(); c.ellipse(cxm, top + h * 0.95,
```

```ts title="windows/src/cat/renderer.ts" old
c.fillStyle = "#FBF7F0";
```

```ts title="windows/src/cat/renderer.ts" new
c.fillStyle = THEME.cat.teeth;
```

```ts title="windows/src/cat/renderer.ts" old
c.fillStyle = "#E8798C"; c.beginPath(); c.moveTo(cxm - tw, top + h * 0.7);
```

```ts title="windows/src/cat/renderer.ts" new
c.fillStyle = THEME.cat.tongue; c.beginPath(); c.moveTo(cxm - tw, top + h * 0.7);
```

```ts title="windows/src/cat/renderer.ts" old
c.fillStyle = "#E8798C"; c.beginPath(); c.ellipse(cxm, y0 + 0.035 * R + th * 0.5,
```

```ts title="windows/src/cat/renderer.ts" new
c.fillStyle = THEME.cat.tongue; c.beginPath(); c.ellipse(cxm, y0 + 0.035 * R + th * 0.5,
```

```ts title="windows/src/cat/renderer.ts" old
c.fillStyle = "#F4F5F7";
```

```ts title="windows/src/cat/renderer.ts" new
c.fillStyle = THEME.cat.paper;
```

```ts title="windows/src/cat/renderer.ts" old
c.fillStyle = "#C9CDD4";
```

```ts title="windows/src/cat/renderer.ts" new
c.fillStyle = THEME.cat.paperFold;
```

```ts title="windows/src/cat/renderer.ts" old
c.fillStyle = "#3B9EFF"; rr(c, -w / 2 + s * 0.07,
```

```ts title="windows/src/cat/renderer.ts" new
c.fillStyle = THEME.cat.paperLabel; rr(c, -w / 2 + s * 0.07,
```

- [ ] **Step 4: The greeting's 7 sites and the state tables**

```ts title="windows/src/cat/greeting.ts" old
import { catCfg } from "./engine.ts";
```

```ts title="windows/src/cat/greeting.ts" new
import { catCfg } from "./engine.ts";
import { THEME, THEME_RGB } from "../theme.generated.ts";
```

```ts title="windows/src/cat/greeting.ts" old
const r = rng(7), cols = ["#3B9EFF", "#F29B38", "#FF5A4E", "#2EC4A0", "#A78BFA"];
```

```ts title="windows/src/cat/greeting.ts" new
const r = rng(7), cols = THEME.greeting.streaks;
```

```ts title="windows/src/cat/greeting.ts" old
  const v = stillView(p, { ...newPose(), tint: 0.6 });
  v.col = [127, 180, 234];
```

```ts title="windows/src/cat/greeting.ts" new
  const v = stillView(p, { ...newPose(), tint: 0.6 });
  v.col = [...THEME_RGB.greeting.tint];
```

```ts title="windows/src/cat/greeting.ts" old
  v.badgeCol = "#3BA0F5";
  v.col = [127, 180, 234];
```

```ts title="windows/src/cat/greeting.ts" new
  v.badgeCol = THEME.greeting.badge;
  v.col = [...THEME_RGB.greeting.tint];
```

```ts title="windows/src/cat/greeting.ts" old
x.fillStyle = "#141518";
```

```ts title="windows/src/cat/greeting.ts" new
x.fillStyle = THEME.greeting.card;
```

```ts title="windows/src/cat/greeting.ts" old
      const bl = P.haloBlue, c = [lerp(232, 59, bl), lerp(195, 158, bl), lerp(154, 255, bl)].map(Math.round);
```

```ts title="windows/src/cat/greeting.ts" new
      const bl = P.haloBlue, gold = THEME_RGB.greeting.haloGold, blue = THEME_RGB.greeting.haloBlue, c = [0, 1, 2].map((i) => Math.round(lerp(gold[i], blue[i], bl)));
```

```ts title="windows/src/cat/greeting.ts" old
x.fillStyle = "#8d9098";
```

```ts title="windows/src/cat/greeting.ts" new
x.fillStyle = THEME.greeting.headerDim;
```

```ts title="windows/src/cat/base.ts" old
// Imports nothing at run time, so the plain-Node checks (npm run check:cat) can load it as it is.

export const TAU = Math.PI * 2;
```

```ts title="windows/src/cat/base.ts" new
// Imports only the generated theme (plain data), so the plain-Node checks (npm run check:cat) can load it as it is.

import { THEME } from "../theme.generated.ts";

export const TAU = Math.PI * 2;
```

```ts title="windows/src/cat/base.ts" old
export const COL: Record<StateName, string> = {
  idle: "#E6E9EE", working: "#3B9EFF", thinking: "#8B5CF6", searching: "#6366F1", approval: "#F5A524",
  question: "#22D3EE", error: "#F4505E", finished: "#34D399", ratelimit: "#FB923C", sleeping: "#94A3B8",
  dizzy: "#F472B6",
};
```

```ts title="windows/src/cat/base.ts" new
/** The colour of each state. The cat core pins them (tests/fixtures/cat/), and shared/theme.json's generator reads them from it into the theme file. */
export const COL: Record<StateName, string> = THEME.state.color;
```

```ts title="windows/src/cat/base.ts" old
export const GLOW: Partial<Record<StateName, string>> = {
  working: "#3B9EFF", thinking: "#A78BFA", searching: "#6366F1", approval: "#F5A524",
  error: "#F4505E", finished: "#34D399", ratelimit: "#F59E0B",
};
```

```ts title="windows/src/cat/base.ts" new
/** The glow behind a working cat, for the states that have one (the cat core pins it, as it pins COL). */
export const GLOW: Partial<Record<StateName, string>> = THEME.state.glow;
```

- [ ] **Step 5: The `?dev` page's palette (14 sites)**

```ts title="windows/src/cat/dev.ts" old
import { AGENT_PILL_COLORS } from "../core/pills.ts";
```

```ts title="windows/src/cat/dev.ts" new
import { AGENT_PILL_COLORS } from "../core/pills.ts";
import { THEME } from "../theme.generated.ts";
```

```ts title="windows/src/cat/dev.ts" old
const FONT = "system-ui,-apple-system,'Segoe UI',sans-serif";
```

```ts title="windows/src/cat/dev.ts" new
const FONT = "system-ui,-apple-system,'Segoe UI',sans-serif";
const B = THEME.brand;
```

```ts title="windows/src/cat/dev.ts" old
const BTN = "font:inherit;font-size:12px;color:#ececee;background:#202227;border:1px solid #2a2c31;border-radius:8px;padding:4px 10px;cursor:pointer";
```

```ts title="windows/src/cat/dev.ts" new
const BTN = `font:inherit;font-size:12px;color:${B.ink};background:${B.button};border:1px solid ${B.line};border-radius:8px;padding:4px 10px;cursor:pointer`;
```

```ts title="windows/src/cat/dev.ts" old
  s.style.cssText = "background:#17181b;border:1px solid #2a2c31;border-radius:16px;padding:16px;margin-bottom:20px";
```

```ts title="windows/src/cat/dev.ts" new
  s.style.cssText = `background:${B.panel};border:1px solid ${B.line};border-radius:16px;padding:16px;margin-bottom:20px`;
```

```ts title="windows/src/cat/dev.ts" old
<p style="color:#9a9ca3;margin:0 0 12px;font-size:13px">
```

```ts title="windows/src/cat/dev.ts" new
<p style="color:${B.dim};margin:0 0 12px;font-size:13px">
```

```ts title="windows/src/cat/dev.ts" old
  h.style.cssText = "font-size:12px;color:#9a9ca3;width:72px;flex:none"; h.textContent = label;
```

```ts title="windows/src/cat/dev.ts" new
  h.style.cssText = `font-size:12px;color:${B.dim};width:72px;flex:none`; h.textContent = label;
```

```ts title="windows/src/cat/dev.ts" old
b.style.borderColor = get() === v ? "#5EEAD4" : "#2a2c31"; b.style.color = get() === v ? "#5EEAD4" : "#ececee";
```

```ts title="windows/src/cat/dev.ts" new
b.style.borderColor = get() === v ? B.accent : B.line; b.style.color = get() === v ? B.accent : B.ink;
```

```ts title="windows/src/cat/dev.ts" old
{ background: "#0f1012", overflow: "auto"
```

```ts title="windows/src/cat/dev.ts" new
{ background: B.page, overflow: "auto"
```

```ts title="windows/src/cat/dev.ts" old
color: "#ececee" });
```

```ts title="windows/src/cat/dev.ts" new
color: B.ink });
```

```ts title="windows/src/cat/dev.ts" old
<p style="color:#9a9ca3;margin:0 0 14px">
```

```ts title="windows/src/cat/dev.ts" new
<p style="color:${B.dim};margin:0 0 14px">
```

```ts title="windows/src/cat/dev.ts" old
b.style.borderColor = on ? "#5EEAD4" : "#2a2c31";
```

```ts title="windows/src/cat/dev.ts" new
b.style.borderColor = on ? B.accent : B.line;
```

```ts title="windows/src/cat/dev.ts" old
c.fillStyle = "#ececee"; c.font =
```

```ts title="windows/src/cat/dev.ts" new
c.fillStyle = B.ink; c.font =
```

```ts title="windows/src/cat/dev.ts" old
c.strokeStyle = "#2a2c31";
```

```ts title="windows/src/cat/dev.ts" new
c.strokeStyle = B.line;
```

```ts title="windows/src/cat/dev.ts" old
c.fillStyle = "#9a9ca3";
```

```ts title="windows/src/cat/dev.ts" new
c.fillStyle = B.dim;
```

```ts title="windows/src/cat/dev.ts" old
  readout.style.cssText = "color:#9a9ca3;font-size:12px;margin:10px 0 0";
```

```ts title="windows/src/cat/dev.ts" new
  readout.style.cssText = `color:${B.dim};font-size:12px;margin:10px 0 0`;
```

```ts title="windows/src/cat/dev.ts" old
      cap.style.cssText = "font-size:11px;color:#9a9ca3"; cap.textContent = st;
```

```ts title="windows/src/cat/dev.ts" new
      cap.style.cssText = `font-size:11px;color:${B.dim}`; cap.textContent = st;
```

- [ ] **Step 6: Record the "after" and compare**

```bash
CHK="${TMPDIR:-/tmp}/a-tauri-57-check"
node --experimental-strip-types "$CHK/snap.mjs" > "$CHK/after.json"
cmp "$CHK/before.json" "$CHK/after.json" && echo "cats, greeting, tables and glow: the same record"
WT="$(git rev-parse --show-toplevel)"
(cd "$WT/windows" && npx --no-install vite --port 14571 > "$CHK/vite.log" 2>&1 &)
sleep 3
cd "$CHK"
playwright-cli -s=theme open "http://127.0.0.1:14571/?dev" > /dev/null
playwright-cli -s=theme eval "$(cat "$CHK/dev-fingerprint.js")" | sed -n 2p > "$CHK/dev-after.txt"
playwright-cli -s=theme close > /dev/null
kill $(lsof -ti tcp:14571) 2>/dev/null
cmp "$CHK/dev-before.txt" "$CHK/dev-after.txt" && echo "the ?dev page: the same HTML and the same ladder pixels"
```

Expected: both lines print, `cats, greeting, tables and glow: the same record` and `the ?dev page: the same HTML and the same ladder pixels`. If either `cmp` complains, a value or a place was changed: find the difference (`diff "$CHK/before.json" "$CHK/after.json"`), fix the edit, never the token, and run this step again.

- [ ] **Step 7: Prove the check bites (not committed)**

```bash
CHK="${TMPDIR:-/tmp}/a-tauri-57-check"
python3 - <<'PY'
p = 'windows/src/cat/renderer.ts'
s = open(p, encoding='utf-8').read()
was = 'c.fillStyle = THEME.cat.teeth;'
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, 'c.fillStyle = THEME.cat.paper;'))
PY
node --experimental-strip-types "$CHK/snap.mjs" | cmp - "$CHK/before.json"
python3 - <<'PY'
p = 'windows/src/cat/renderer.ts'
s = open(p, encoding='utf-8').read()
was = 'c.fillStyle = THEME.cat.paper;'
assert s.count(was) == 2
i = s.index(was)
open(p, 'w', encoding='utf-8').write(s[:i] + 'c.fillStyle = THEME.cat.teeth;' + s[i + len(was):])
PY
node --experimental-strip-types "$CHK/snap.mjs" | cmp - "$CHK/before.json" && echo "put back: the same record again"
```

Expected: the first `cmp` prints `stdin … before.json differ: char …` (a wrong token is caught: the teeth drawn in the file's colour); after putting it back, `put back: the same record again`.

- [ ] **Step 8: Nothing the swap should have changed is left behind, and nothing it should not have touched was changed**

Run: `grep -niE '#(0e0b09|3a1218|e8798c|fbf7f0|ff4d6d|f7b32b|7cc7ff|f4f5f7|c9cdd4|3ba0f5|7fb4ea|e8c39a|8d9098|141518|5eead4|0f1012|17181b|2a2c31|ececee|9a9ca3|202227)\b' windows/src/cat/renderer.ts windows/src/cat/greeting.ts windows/src/cat/base.ts windows/src/cat/dev.ts; echo "grep exit $?"`
Expected: no match, and `grep exit 1`. (`windows/src/style.css` and `settings.css` still hold `#141518` as their own `--card`, which stays.)

Run: `git diff --stat -- windows | tail -8`
Expected: in a worktree where Tasks 1 to 12 are committed, exactly four files: `windows/src/cat/base.ts`, `dev.ts`, `greeting.ts` and `renderer.ts` (the file list of the step above), and no stylesheet, no `core/layout.ts` (Task 14), no Rust. (A dry-run clone commits nothing, so there the earlier tasks' files are listed as well, 16 in all: look only for the absence of `core/layout.ts` and of `windows/src/style.css`.)

Run: `git diff --name-only -- windows/src/core/layout.ts windows/src/style.css | wc -l | tr -d ' '`
Expected: `0` (the island's glow literals are Task 14's and `style.css` is never touched by this plan: it holds for a worktree and for a dry-run clone alike).

Run: `cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `tsc exit 0`, then `ℹ tests 157`, `ℹ pass 157`, `ℹ fail 0` (no test is added: the fixtures and the recorder are the proof).

- [ ] **Step 9: Commit**

```bash
git add windows/src/cat/renderer.ts windows/src/cat/greeting.ts windows/src/cat/base.ts windows/src/cat/dev.ts
git commit -m "refactor(theme): the cat's details, the greeting and the ?dev palette read the generated theme tokens

The 14 renderer sites, the greeting's seven, the state colours and glows in base.ts and the ?dev page's 14: the same values, so no pixel
changes (a recorded drawing of every coat, the greeting and the glow, and a fingerprint of the ?dev page, are equal before and after).

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 14: The island's glow (only if the owner says yes)

**Agent:** `nm-implementer-light`.

**Run this task only if the owner answered yes to question 1 at Checkpoint 2** (open question 1: may stage 7 swap the island's glow literals in `core/layout.ts` for the tokens, with the same values and no change of look?). `botGlowColor` is the code of an existing view, the radial glow behind the big cat in the expanded island, and it draws the same seven colours as `GLOW`; replacing its literals with `THEME.state.glow` changes no pixel. On a no, skip the task, and say in the final report that those seven literals stay (they are in A-0d's inventory, as "every other line of `core/layout.ts:163-175`").

**Files:**
- Modify: `windows/src/core/layout.ts` (the import and `botGlowColor`)

**Interfaces:**
- Consumes: `THEME.state.glow` (`working`, `thinking`, `searching`, `approval`, `error`, `finished`, `ratelimit`) from `windows/src/theme.generated.ts`, and Task 13's `snap.mjs` and `before.json` (its `glow` scene records `botGlowColor` and `botGlowOpacity` for all 11 states).
- Produces: nothing new. `botGlowColor` returns the same string for every state (a state with no glow, and the default, still give `#FFFFFF`), and `core/layout.ts` still loads in plain Node (the generated file has no imports).

- [ ] **Step 1: Swap the seven literals**

```ts title="windows/src/core/layout.ts" old
export function botGlowColor(s: BotStateName): string {
  switch (s) {
    case "working":
      return "#3B9EFF";
    case "thinking":
      return "#A78BFA";
    case "searching":
      return "#6366F1";
    case "approval":
      return "#F5A524";
    case "error":
      return "#F4505E";
    case "finished":
      return "#34D399";
    case "ratelimit":
      return "#F59E0B";
    default:
      return "#FFFFFF";
  }
}
```

```ts title="windows/src/core/layout.ts" new
export function botGlowColor(s: BotStateName): string {
  switch (s) {
    case "working":
      return THEME.state.glow.working;
    case "thinking":
      return THEME.state.glow.thinking;
    case "searching":
      return THEME.state.glow.searching;
    case "approval":
      return THEME.state.glow.approval;
    case "error":
      return THEME.state.glow.error;
    case "finished":
      return THEME.state.glow.finished;
    case "ratelimit":
      return THEME.state.glow.ratelimit;
    default:
      return "#FFFFFF";
  }
}
```

```ts title="windows/src/core/layout.ts" old
export type IslandMode = "hidden" | "compact" | "expanded";
```

```ts title="windows/src/core/layout.ts" new
import { THEME } from "../theme.generated.ts";

export type IslandMode = "hidden" | "compact" | "expanded";
```

- [ ] **Step 2: The same record as before**

```bash
CHK="${TMPDIR:-/tmp}/a-tauri-57-check"
node --experimental-strip-types "$CHK/snap.mjs" | cmp - "$CHK/before.json" && echo "the glow, the cats and the greeting: the same record as before Task 13"
```

Expected: `the glow, the cats and the greeting: the same record as before Task 13` (Task 13's `before.json` is the tree before any swap, so this also proves Task 13's edits and this one together). If it complains, `diff` the two files: the `glow` scene names the state.

- [ ] **Step 3: Type check, the cat check and the sites**

Run: `cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `tsc exit 0`, then `ℹ tests 157`, `ℹ pass 157`, `ℹ fail 0`.

Run: `grep -nE '"#(3B9EFF|A78BFA|6366F1|F5A524|F4505E|34D399|F59E0B)"' windows/src/core/layout.ts; echo "grep exit $?"`
Expected: no match and `grep exit 1`.

- [ ] **Step 4: Commit**

```bash
git add windows/src/core/layout.ts
git commit -m "refactor(theme): the island's glow reads the theme's state glows (the owner agreed)

The same seven colours as before, so no pixel changes: the recorded glow, cats and greeting are equal to the record taken before the swap.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 15: Dead code goes

**Agent:** `nm-implementer`.

Spec §3, "Removed (dead code)": permanent emotes, `miniEye`, the `morph` and `cup` eyes, `BotStateCfg.sound` and the mailbox morph; `engine.greet()` **stays** (it plays the contract's `hello` paw-wave emote, which the greeting and the fixtures use). On Windows and Linux that is:

- **Permanent emotes and `miniEye`:** `BotEngine.setPermanentEmote`, `permanentEye`, `EMOTE_EYE`, the `eyeOverride` and `eyeOverrideUntil` accessors that only they used, and `AgentTask.emote` and `AgentTask.miniEye` with their five lines in `minibots.ts`. Nothing ever set the two task fields.
- **The `cup` eye** of the old character: in `EyeShape` and in the renderer's `case "pill": case "cup"`.
- **The mailbox morph:** `BotEngine.morph`, `animateMorph`, `resetMorph` and the `slotHTarget` and `slotHVel` aliases; `engine.gulp()` and the seven calls and the block of them in `island.ts`; and the fields of `UploadFrame` that only drew the old mailbox: `morph`, `mouth`, `mouthRect` and `eye` (with `UploadEyeShape`, `MouthRect` and the mouth spring that fed them). The drop view draws the cat's catch with the engine's own spring (`slotT`, `slotH`, `slotV`), which stays.
- **`bodyColor`'s companions:** `hexToRGB`, `RGB` and the `EyeShape` re-export of `engine.ts`, which nothing used once the collar replaced the body colour.
- **`BotStateCfg.sound`:** there is no such thing on Windows and Linux, so there is nothing to remove.
- **Kept on purpose:** `USC.MOUTH_*` and `USC.T_CLOSE_END` (the sequence's constants are a mirror of the Mac's `USC`; they are numbers, not code that runs) and `eIn` (the progress curve uses it). `eyeUntil = Infinity` is the catch's own sentinel and stays.

**Files:**
- Modify: `windows/src/cat/engine.ts`, `windows/src/cat/minibots.ts`, `windows/src/cat/types.ts`, `windows/src/cat/renderer.ts`, `windows/src/core/state.ts`, `windows/src/island/island.ts`, `windows/src/upload/sequence.ts`, `windows/scripts/cat-tests/engine.test.mjs`
- Create: `windows/scripts/cat-tests/deadcode.test.mjs`

**Interfaces:**
- Consumes: nothing new.
- Produces: no new name. The engine keeps the members the island and the views use: `setState`, `triggerEmote`, `slap`, `blink`, `update`, `draw`, `busy`, `isMini`, `collarColor`, `lookX`, `lookY`, `tgEs`, `onDizzy`, `particleOverhang`, `badgeLeft`, `earRoom` and the file-catch calls. `deadcode.test.mjs` keeps the removed names from coming back: it reads every file of `src/` and `dev/`.

- [ ] **Step 1: Write the failing tests**

```js title="windows/scripts/cat-tests/deadcode.test.mjs" create
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

// Names that were removed on purpose (spec §3, "Removed (dead code)") and must not come back. Every file of src/ and dev/ is read.
const root = new URL("../../", import.meta.url).pathname;
const sources = ["src", "dev"].flatMap((dir) => fs.readdirSync(path.join(root, dir), { withFileTypes: true, recursive: true })
  .filter((e) => e.isFile() && /\.(ts|css|html)$/.test(e.name)).map((e) => path.join(e.parentPath, e.name)));

const GONE = {
  "permanent emotes and miniEye": ["setPermanentEmote", "permanentEye", "EMOTE_EYE", "eyeOverride", "eyeOverrideUntil", "miniEye"],
  "the mailbox morph": ["animateMorph", "resetMorph", "slotHTarget", "slotHVel", "mouthRect", "MouthRect", "UploadEyeShape"],
  "the body colour": ["bodyColor", "hexToRGB"],
};

test("the removed names are not in any source file", () => {
  assert.ok(sources.length > 40, `${sources.length} files read`);
  for (const [why, names] of Object.entries(GONE)) for (const name of names) {
    const hits = sources.filter((f) => new RegExp(`\\b${name}\\b`).test(fs.readFileSync(f, "utf8"))).map((f) => path.relative(root, f));
    assert.deepEqual(hits, [], `${name} (${why})`);
  }
});

test("the cup eye, engine.gulp() and the engine's morph are gone too, and the cat's own hello wave stays", () => {
  const text = (rel) => fs.readFileSync(path.join(root, rel), "utf8");
  assert.doesNotMatch(text("src/cat/types.ts"), /"cup"/);
  assert.doesNotMatch(text("src/cat/renderer.ts"), /"cup"/);
  assert.doesNotMatch(text("src/upload/sequence.ts"), /"cup"|\bmorph\b/);
  assert.doesNotMatch(text("src/island/island.ts"), /\.gulp\(|\bmorph\b/);
  assert.doesNotMatch(text("src/cat/engine.ts"), /\bgulp\(\)|\bmorph\b/);
  assert.match(text("src/cat/engine.ts"), /greet\(\) \{/, "the contract's hello emote still plays through greet()");
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/deadcode.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; cd ..`
Expected: `not ok 1 - the removed names are not in any source file`, `not ok 2 - the cup eye, engine.gulp() and the engine's morph are gone too…`, `# tests 2`, `# pass 0`, `# fail 2`.

- [ ] **Step 3: The engine**

```ts title="windows/src/cat/engine.ts" old
// The cat engine: the state machine that moves a cat. A port of CatEngine in design/prototype/cat-core.js,
// the tie-breaker, with the same public members as the engine it replaces (the old mochi engine) so the island,
// the views and the mini cats keep working: setState, triggerEmote, slap, blink, gulp, update, draw, busy,
// isMini, collarColor, lookX and lookY, tgEs, slotH*, onDizzy, hexToRGB and EyeShape.
```

```ts title="windows/src/cat/engine.ts" new
// The cat engine: the state machine that moves a cat. A port of CatEngine in design/prototype/cat-core.js, the tie-breaker.
// The island, the views and the mini cats use: setState, triggerEmote, slap, blink, update, draw, busy, isMini, collarColor,
// lookX and lookY, tgEs and onDizzy, and the file catch.
```

```ts title="windows/src/cat/engine.ts" old
export type { EyeShape } from "./types.ts";

/** Components 0…1, as the island's integration colours use them. */
export type RGB = readonly [number, number, number];

export function hexToRGB(h: string): RGB {
  const v = parseInt(h.replace("#", ""), 16);
  return [((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255];
}

/** One step of a tween: the value to reach, how long it takes (ms) and the easing. */
```

```ts title="windows/src/cat/engine.ts" new
/** One step of a tween: the value to reach, how long it takes (ms) and the easing. */
```

```ts title="windows/src/cat/engine.ts" old
  // What the island uses and the old engine had; some of it is removed in stage 7.
```

```ts title="windows/src/cat/engine.ts" new
  // What the island and the views set.
```

```ts title="windows/src/cat/engine.ts" old
  /** The eye shape a mini cat keeps (never set today; removed with the other permanent emotes in stage 7). */
  permanentEye: EyeShape | null = null;
  /** True in the compact notch: the badge sits on the left of the head, away from the camera housing. */
```

```ts title="windows/src/cat/engine.ts" new
  /** True in the compact notch: the badge sits on the left of the head, away from the camera housing. */
```

```ts title="windows/src/cat/engine.ts" old
  /** The mailbox morph of the old character is gone; kept at 0 until stage 7 removes its callers. */
  readonly morph = 0;
  private esHover = 1;
```

```ts title="windows/src/cat/engine.ts" new
  private esHover = 1;
```

```ts title="windows/src/cat/engine.ts" old
  get eyeOverride(): EyeShape | null { return this.eyeOv; }
  set eyeOverride(v: EyeShape | null) { this.eyeOv = v; }
  get eyeOverrideUntil(): number { return this.eyeUntil; }
  set eyeOverrideUntil(v: number) { this.eyeUntil = v; }
  /** The eyes' size while the pointer rests on the cat (the island sets 1.08 and puts 1 back). */
  get tgEs(): number { return this.esHover; }
  set tgEs(v: number) { this.esHover = v; }
  get slotHTarget(): number { return this.slotT; }
  set slotHTarget(v: number) { this.slotT = v; }
  get slotHVel(): number { return this.slotV; }
  set slotHVel(v: number) { this.slotV = v; }
```

```ts title="windows/src/cat/engine.ts" new
  /** The eyes' size while the pointer rests on the cat (the island sets 1.08 and puts 1 back). */
  get tgEs(): number { return this.esHover; }
  set tgEs(v: number) { this.esHover = v; }
```

```ts title="windows/src/cat/engine.ts" old
  /** The file has arrived: gulp and chew. */
  gulp() { this.catchArrive(); }
  /** The mailbox morph of the old character is gone. Kept until stage 7 removes its callers in island.ts. */
  animateMorph(_target: number, _durationMs?: number) {}
  resetMorph() {}
  /** Mini cats keep the eye shape they are given. */
  setPermanentEmote(emote: string | null) {
    this.permanentEye = emote ? EMOTE_EYE[emote] ?? null : null;
    if (this.permanentEye) { this.eyeOv = this.permanentEye; this.eyeUntil = Infinity; }
    else if (this.eyeUntil === Infinity) { this.eyeOv = null; this.eyeUntil = 0; }
  }

  /**
   * True while the island must keep drawing frames.
```

```ts title="windows/src/cat/engine.ts" new
  /**
   * True while the island must keep drawing frames.
```

```ts title="windows/src/cat/engine.ts" old
    if (dance) x.restore();
  }
}

/** The eyes an emote shows. */
const EMOTE_EYE: Record<string, EyeShape> = { love: "heart", surprised: "dot", proud: "star", wink: "wink", yawn: "tired", happy: "happy", annoyed: "line" };
```

```ts title="windows/src/cat/engine.ts" new
    if (dance) x.restore();
  }
}
```

```ts title="windows/src/cat/minibots.ts" old
  engine.setState(State.shownState(task.state), true);
  if (task.emote) engine.setPermanentEmote(task.emote);
  if (task.miniEye) {
    engine.permanentEye = task.miniEye;
    engine.eyeOverride = task.miniEye;
    engine.eyeOverrideUntil = Number.POSITIVE_INFINITY;
  }
```

```ts title="windows/src/cat/minibots.ts" new
  engine.setState(State.shownState(task.state), true);
```

```ts title="windows/src/cat/types.ts" old
  | "spiral" | "heart" | "star" | "tired" | "wink" | "cup";
```

```ts title="windows/src/cat/types.ts" new
  | "spiral" | "heart" | "star" | "tired" | "wink";
```

```ts title="windows/src/cat/renderer.ts" old
    case "pill": case "cup": pill(w, h); break;
```

```ts title="windows/src/cat/renderer.ts" new
    case "pill": pill(w, h); break;
```

```ts title="windows/src/core/state.ts" old
import type { BotEmoteName, BotStateName, IslandMode, IslandViewName } from "./layout";
import type { EyeShape } from "../cat/engine";
```

```ts title="windows/src/core/state.ts" new
import type { BotStateName, IslandMode, IslandViewName } from "./layout";
```

```ts title="windows/src/core/state.ts" old
  emote?: BotEmoteName | null;
  miniEye?: EyeShape | null;
  pillBadge?: PillBadge | null;
```

```ts title="windows/src/core/state.ts" new
  pillBadge?: PillBadge | null;
```

- [ ] **Step 4: The island and the drop sequence**

```ts title="windows/src/island/island.ts" old
    if (mode !== "expanded") {
      this.engine.resetMorph();
      // Nothing can be seen of the sequence once the island is shut, and leaving
```

```ts title="windows/src/island/island.ts" new
    if (mode !== "expanded") {
      // Nothing can be seen of the sequence once the island is shut, and leaving
```

```ts title="windows/src/island/island.ts" old
        State.fileDragOver = true;
        this.engine.animateMorph(1);
```

```ts title="windows/src/island/island.ts" new
        State.fileDragOver = true;
```

```ts title="windows/src/island/island.ts" old
        State.fileDragOver = false;
        this.engine.animateMorph(0);
        // The island deliberately stays open: the drag session is still alive.
```

```ts title="windows/src/island/island.ts" new
        State.fileDragOver = false;
        // The island deliberately stays open: the drag session is still alive.
```

```ts title="windows/src/island/island.ts" old
        if (!path) {
          this.engine.animateMorph(0);
          this.setView(State.defaultView());
```

```ts title="windows/src/island/island.ts" new
        if (!path) {
          this.setView(State.defaultView());
```

```ts title="windows/src/island/island.ts" old
    this.engine.gulp();
    this.engine.triggerEmote("happy");
    this.engine.animateMorph(0);
```

```ts title="windows/src/island/island.ts" new
    this.engine.triggerEmote("happy");
```

```ts title="windows/src/island/island.ts" old
          State.noteMessage = message;
          this.engine.animateMorph(0);
          this.setView("note");
```

```ts title="windows/src/island/island.ts" new
          State.noteMessage = message;
          this.setView("note");
```

```ts title="windows/src/island/island.ts" old
    if (this.engine.morph > 0.3) {
      this.engine.slotHTarget = State.fileDragOver ? 0.2 : 0;
    } else {
      this.engine.slotHTarget = 0;
      if (this.engine.morph < 0.05) {
        this.engine.slotH = 0;
        this.engine.slotHVel = 0;
      }
    }
    this.engine.update(dt);
```

```ts title="windows/src/island/island.ts" new
    this.engine.update(dt);
```

```ts title="windows/src/upload/sequence.ts" old
export type UploadEyeShape = "pill" | "cup" | "content";

export interface MouthRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface UploadFrame {
```

```ts title="windows/src/upload/sequence.ts" new
export interface UploadFrame {
```

```ts title="windows/src/upload/sequence.ts" old
  cursorY: number;
  morph: number;
  x: number;
```

```ts title="windows/src/upload/sequence.ts" new
  cursorY: number;
  x: number;
```

```ts title="windows/src/upload/sequence.ts" old
  hop: number;
  mouth: number;
  mouthRect: MouthRect;
  eye: UploadEyeShape;
  lookX: number;
```

```ts title="windows/src/upload/sequence.ts" new
  hop: number;
  lookX: number;
```

```ts title="windows/src/upload/sequence.ts" old
    cursorY: 280,
    morph: 0,
    x: USC.REST_X,
```

```ts title="windows/src/upload/sequence.ts" new
    cursorY: 280,
    x: USC.REST_X,
```

```ts title="windows/src/upload/sequence.ts" old
    hop: 0,
    mouth: 0,
    mouthRect: { x: 0, y: 0, w: 0, h: 0 },
    eye: "pill",
    lookX: 0,
```

```ts title="windows/src/upload/sequence.ts" new
    hop: 0,
    lookX: 0,
```

```ts title="windows/src/upload/sequence.ts" old
  private tilt = 0;
  private mouth = new USSpring(0);
  private locked = false;
```

```ts title="windows/src/upload/sequence.ts" new
  private tilt = 0;
  private locked = false;
```

```ts title="windows/src/upload/sequence.ts" old
    this.tilt = 0;
    this.mouth = new USSpring(0);
    this.locked = false;
```

```ts title="windows/src/upload/sequence.ts" new
    this.tilt = 0;
    this.locked = false;
```

```ts title="windows/src/upload/sequence.ts" old
    this.tilt = lerp(this.tilt, tiltTarget, 1 - Math.pow(0.0005, dt));

    // Mouth. The post-drop close only runs once the drop has actually happened.
    const t = this.t;
    if (!isDragging && t >= USC.T_SUCK_END) {
      this.mouth.v = Math.max(0, lerp(USC.MOUTH_MAX, 0, eIn(seg(t, USC.T_SUCK_END, USC.T_CLOSE_END))));
    } else {
      let mt = 0;
      if (this.entered >= 0) mt = this.locked || !isDragging ? USC.MOUTH_OPEN : USC.MOUTH_AJAR;
      if (!isDragging && t < USC.T_SUCK_END) mt = USC.MOUTH_MAX;
      this.mouth.step(mt, 0.25, 0.6, dt);
      if (this.mouth.v < 0) this.mouth.v = 0;
    }
  }
```

```ts title="windows/src/upload/sequence.ts" new
    this.tilt = lerp(this.tilt, tiltTarget, 1 - Math.pow(0.0005, dt));
  }
```

```ts title="windows/src/upload/sequence.ts" old
    const entered = this.entered >= 0 ? this.entered : 1e9;
    const isDragging = this.dropWall == null;
```

```ts title="windows/src/upload/sequence.ts" new
    const isDragging = this.dropWall == null;
```

```ts title="windows/src/upload/sequence.ts" old
    // Morph: 0→1 on entry, 1→0 shrinking to a ball, 0→1 growing back at choose.
    let morph: number;
    if (pt < USC.T_CHEW_END) morph = eBack(seg(pt, entered, entered + 0.38));
    else if (pt < growStart) morph = 1 - eOut(seg(pt, USC.T_CHEW_END, USC.T_SHRINK_END));
    else morph = eBack(seg(pt, growStart, growEnd));
    f.morph = Math.max(0, Math.min(morph, 1.08));

    // Position and diameter.
```

```ts title="windows/src/upload/sequence.ts" new
    // Position and diameter.
```

```ts title="windows/src/upload/sequence.ts" old
    f.mouth = this.mouth.v;

    // Eyes.
    let eye: UploadEyeShape = "pill";
    if (this.locked && pt < USC.T_SUCK_END) eye = "cup";
    if (pt >= USC.T_SUCK_END && pt < USC.T_CHEW_END + 0.1) eye = "content";
    if (pt >= progEnd && pt < growEnd + 0.3) eye = "content";
    f.eye = eye;

    const lkx = pt < USC.T_SUCK_END
```

```ts title="windows/src/upload/sequence.ts" new
    const lkx = pt < USC.T_SUCK_END
```

```ts title="windows/src/upload/sequence.ts" old
    f.chooseAlpha = seg(pt, growStart + 0.15, growEnd);

    // Mouth rect in island coordinates — the file is clipped against it.
    const R = f.d / 2 / 1.04;
    const mc = Math.max(0, Math.min(f.morph, 1));
    const rx = R * (1.04 - 0.04 * mc);
    const ry = R * (0.97 - 0.03 * mc);
    const mh = f.mouth * R * mc;
    const mw = 2 * rx - 0.24 * R;
    f.mouthRect = {
      x: x + (-mw / 2) * sx,
      y: y + f.hop + (-ry + 0.1 * R) * sy,
      w: mw * sx,
      h: mh * sy,
    };
    return f;
```

```ts title="windows/src/upload/sequence.ts" new
    f.chooseAlpha = seg(pt, growStart + 0.15, growEnd);
    return f;
```

- [ ] **Step 5: The tests that named the removed members**

```js title="windows/scripts/cat-tests/engine.test.mjs" old
import { BotEngine, catCfg, hexToRGB } from "../../src/cat/engine.ts";
```

```js title="windows/scripts/cat-tests/engine.test.mjs" new
import { BotEngine, catCfg } from "../../src/cat/engine.ts";
```

```js title="windows/scripts/cat-tests/engine.test.mjs" old
test("the engine keeps the old character's members: setState, blink, slap, gulp, update, draw, busy, isMini, collarColor, lookX/Y, tgEs, slotH*, onDizzy", () => {
  const e = new BotEngine();
  assert.equal(e.p.name, "shrimpy", "the default cat is Shrimpy");
  for (const m of ["setState", "triggerEmote", "slap", "blink", "gulp", "update", "draw", "animateMorph", "resetMorph", "setPermanentEmote"]) assert.equal(typeof e[m], "function", m);
  assert.deepEqual([e.isMini, e.collarColor, e.lookX, e.lookY, e.slotH, e.slotHTarget, e.slotHVel, e.morph, e.onDizzy, e.particleOverhang, e.earRoom], [false, null, 0, 0, 0, 0, 0, 0, null, 0, null]);
  assert.deepEqual(hexToRGB("#FF8000"), [1, 128 / 255, 0]);
  e.tgEs = 1.08;
```

```js title="windows/scripts/cat-tests/engine.test.mjs" new
test("the engine has the members the island and the views use: setState, triggerEmote, slap, blink, update, draw, busy, isMini, collarColor, lookX/Y, tgEs, onDizzy", () => {
  const e = new BotEngine();
  assert.equal(e.p.name, "shrimpy", "the default cat is Shrimpy");
  for (const m of ["setState", "triggerEmote", "slap", "blink", "update", "draw", "greet", "catchOpen", "catchDrop", "catchArrive", "catchReject", "fileHover", "fileDrop", "fileArrived", "fileRefuse"]) assert.equal(typeof e[m], "function", m);
  assert.deepEqual([e.isMini, e.collarColor, e.lookX, e.lookY, e.slotH, e.onDizzy, e.particleOverhang, e.earRoom], [false, null, 0, 0, 0, null, 0, null]);
  for (const gone of ["gulp", "animateMorph", "resetMorph", "setPermanentEmote", "slotHTarget", "slotHVel", "morph", "permanentEye", "bodyColor", "eyeOverride"]) assert.ok(!(gone in e), `${gone} was removed`);
  e.tgEs = 1.08;
```

```js title="windows/scripts/cat-tests/engine.test.mjs" old
  e.slotHTarget = 0.4;
  assert.equal(e.slotT, 0.4);
  e.isMini = true;
```

```js title="windows/scripts/cat-tests/engine.test.mjs" new
  e.isMini = true;
```

The spring's own tests read and write `slotT` and `slotV` now (the engine's own names, which the aliases pointed at). The line that checks the aliases are gone keeps the old names:

```bash
python3 - <<'PY'
p = 'windows/scripts/cat-tests/engine.test.mjs'
lines = open(p, encoding='utf-8').read().split('\n')
n = 0
for i, line in enumerate(lines):
    if 'gone of' in line:
        continue
    n += line.count('slotHTarget') + line.count('slotHVel')
    lines[i] = line.replace('slotHTarget', 'slotT').replace('slotHVel', 'slotV')
assert n == 7, n
open(p, 'w', encoding='utf-8').write('\n'.join(lines))
PY
grep -n "slotHTarget\|slotHVel" windows/scripts/cat-tests/engine.test.mjs | cut -c1-80
```

Expected: one line, the `for (const gone of …` check, which names the aliases to prove they are gone.

- [ ] **Step 6: Run the tests, the type check and every front-end check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/deadcode.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1; cd ..`
Expected: `# tests 2`, `# pass 2`, `# fail 0`, `tsc exit 0` with no type error (an unused import or local would show here), then `ℹ tests 159`, `ℹ pass 159`, `ℹ fail 0`, `All AI UI checks passed` and `All Claude Code UI checks passed`.

- [ ] **Step 7: Watch the drop still play**

The drop view's harness replays the whole choreography on a loop, and the refused sequence with `?refuse`: serve Vite as before and take a shot in each, looking only for a broken page.

```bash
SHOTS="${TMPDIR:-/tmp}/a-tauri-57-shots"; mkdir -p "$SHOTS"; WT="$(git rev-parse --show-toplevel)"
(cd "$WT/windows" && npx --no-install vite --port 14571 > "$SHOTS/vite.log" 2>&1 &)
sleep 3
cd "$SHOTS"
playwright-cli -s=drop open about:blank
playwright-cli -s=drop run-code "async page => { const errors = []; page.on('pageerror', (e) => errors.push(String(e))); for (const [q, file] of [['', 'drop-ok'], ['?refuse', 'drop-refuse']]) { await page.goto('http://127.0.0.1:14571/dev/upload-preview.html' + q); await page.waitForTimeout(3200); await page.screenshot({ path: file + '.png' }); } if (errors.length) throw new Error('page errors: ' + errors.join(' | ')); }"
playwright-cli -s=drop close
kill $(lsof -ti tcp:14571) 2>/dev/null; ls "$SHOTS"/drop-*.png
```

Expected: `drop-ok.png` and `drop-refuse.png`, and no `Error: page errors:` line. Open both: the cat is in the drop view with the file near its mouth or already swallowed; nothing is blank or broken. (The look of the catch itself is unchanged: this task removes code that nothing drew.)

- [ ] **Step 8: Commit**

```bash
git add windows/src/cat/engine.ts windows/src/cat/minibots.ts windows/src/cat/types.ts windows/src/cat/renderer.ts windows/src/core/state.ts windows/src/island/island.ts windows/src/upload/sequence.ts windows/scripts/cat-tests/engine.test.mjs windows/scripts/cat-tests/deadcode.test.mjs
git commit -m "refactor(cat): remove the old character's dead code: permanent emotes, the cup eye and the mailbox morph

setPermanentEmote, miniEye, animateMorph, resetMorph, gulp, the slotH aliases, hexToRGB, the cup eye and the UploadFrame fields that only
drew the mailbox. engine.greet() stays: it plays the contract's hello emote. A test keeps the names from coming back.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 16: The small things the reviews left for stage 7

**Agent:** `nm-implementer`.

The owner's manual checks (`.claude/archive/owner-manual-checks.md`, "Cats on Windows/Linux, stages 1–4" and "Greeting's last beat") list what the reviewers rated "can wait". Six are fixed here, each with a test. Two are not, and say why.

1. **The file catch's numbers live in two places.** `HAIRBALL_S` in `island.ts` repeats the engine's 120 ms and 2.4 s, and `fileEnd`'s 2300 and 3830 ms follow the sparks' and the ball's timings. They become one table in the engine, `CATCH`, which the island reads.
2. **`Greeting` reads `performance.now()` directly, keeps two flags and `end()` leaves its timers running.** It takes a clock (default `performance.now`), keeps one flag (`running`), and `end()` cancels its sounds and its completion timer, as `interrupt()` already does.
3. **A very late refusal snaps the drop timeline back to `T_SUCK_END`.** `UploadSeq.refuse()` held the timeline at the moment the file reaches the mouth, 0.38 s after the drop. A refusal that comes later (a big file is copied before it is refused) threw the picture back by up to a second: the cat teleported from the way to the progress bar to where it had caught the file. Now the timeline holds where it is when the refusal comes, but never later than the end of the chew (`T_CHEW_END`), and an early refusal still waits for the file to reach the mouth.
4. **An unknown emote still logs.** `emote("nope")` changed nothing but wrote `emote:nope` in the engine's log. Now it returns first.
5. **A one-shot lick can fire inside the hairball tail.** A refusal after the cat has begun to chew left the chew's lick (950 ms after the arrival) and sparks queued, so the cat licked its lips while it was gagging. A refusal now clears the file flow's pending beats before it queues the hairball.
6. **The `?dev` readout says "twelve small cats" and draws eleven.** It now says how many it draws.

**Not fixed:** the wiring of `syncDom` (the island's DOM sync, which needs a browser with the whole island; the greeting's and the hand-over's own logic are tested, and Checkpoint 3 has the owner watch it), and `eIn`, which the owner list called unused: it is not, `uploadProgressCurve` uses it, and it is exported with the rest of the sequence's easing.

**Files:**
- Modify: `windows/src/cat/engine.ts` (`CATCH`, `emote`, `catchArrive`, `catchReject`, `hairball`, `spitBall`), `windows/src/island/island.ts` (`HAIRBALL_S`), `windows/src/cat/greeting.ts`, `windows/src/upload/sequence.ts` (the late refusal, and a plain field for the one parameter property, so the Node checks can load it), `windows/src/cat/dev.ts` (one line of text)
- Create: `windows/scripts/cat-tests/leftovers.test.mjs`

**Interfaces:**
- Consumes: the existing `fileDrop`, `fileArrived`, `fileRefuse`, `catchReject`, `fileStep` of the engine, `Greeting`, `UploadSeq` (`enterZone`, `performDrop`, `refuse`, `frame`).
- Produces: `CATCH` (`{ lick: 950, sparks: 1000, end: 2300, gag: 120, hairball: 2400, ballUp: 1110, fileBall: 2600 }`, in ms, exported from `engine.ts`); `new Greeting(now?)`; no other new name. Every fixture row of the engine, the emotes, the catch and the greeting is unchanged: the numbers did not change, only where they are written.

- [ ] **Step 1: Write the failing tests**

```js title="windows/scripts/cat-tests/leftovers.test.mjs" create
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { CATCH } from "../../src/cat/engine.ts";
import { GT, GT3, Greeting } from "../../src/cat/greeting.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { USC, UploadSeq } from "../../src/upload/sequence.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";
import { makeEngine } from "./engine-util.mjs";

installBrowserStubs();
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("the file catch's numbers are in one table: the engine and the island's note wait on the same ones", () => {
  assert.deepEqual({ ...CATCH }, { lick: 950, sparks: 1000, end: 2300, gag: 120, hairball: 2400, ballUp: 1110, fileBall: 2600 });
  assert.match(source("island/island.ts"), /const HAIRBALL_S = \(CATCH\.gag \+ CATCH\.hairball\) \/ 1000;/);
  const engine = source("cat/engine.ts");
  for (const old of ["this.later(950,", "this.later(1000,", "this.fileEnd(1000 + 1300)", "this.later(120,", "this.fileEnd(120 + 1110 + 2600)", "this.later(1110,", "life: file ? 2.6 : 2.4"]) assert.ok(!engine.includes(old), old);
  // The flow ends when the table says: 2.3 s after a file is taken, 3.83 s after a refusal.
  const taken = makeEngine(PRESETS.momo), refused = makeEngine(PRESETS.momo);
  for (const { e } of [taken, refused]) { e.fileDrop("a.pdf"); }
  taken.e.fileArrived();
  refused.e.fileRefuse(); refused.e.fileArrived();
  const until = (w, ms) => { w.f ??= 0; const target = Math.round(ms / (1000 / 60)); while (w.f < target) w.step(++w.f); }; // runs to `ms` since the start
  until(taken, CATCH.end - 40); assert.equal(taken.e.fileStep, "arrived", "not yet");
  until(taken, CATCH.end + 40); assert.equal(taken.e.fileStep, "none", "done");
  const gone = CATCH.gag + CATCH.ballUp + CATCH.fileBall;
  until(refused, gone - 40); assert.equal(refused.e.fileStep, "arrived", "the hairball is still coming up");
  until(refused, gone + 40); assert.equal(refused.e.fileStep, "none");
});

test("an unknown emote is ignored and not logged; every known one is", () => {
  const { e } = makeEngine(PRESETS.momo, { log: [] });
  for (const bad of ["nope", "", "__proto__", "toString", "Love", undefined, null, 7]) e.emote(bad);
  assert.deepEqual(e.log, []);
  for (const good of ["love", "surprised", "proud", "wink", "yawn", "happy", "annoyed", "hello", "zoomies", "hairball"]) e.emote(good);
  assert.deepEqual(e.log.filter((l) => l[1].startsWith("emote:")).map((l) => l[1].slice(6)), ["love", "surprised", "proud", "wink", "yawn", "happy", "annoyed", "hello", "zoomies", "hairball"]);
});

test("a refusal after the cat began to chew clears the chew's lick: the cat licks its lips once, after the hairball, and not while it gags", () => {
  const { e, step } = makeEngine(PRESETS.momo, { log: [] });
  e.fileDrop("movie.mov");
  const at = (ms) => Math.round(ms / (1000 / 60));
  let f = 0;
  const run = (ms) => { for (const end = f + at(ms); f < end;) step(++f); };
  run(380); e.fileArrived();
  run(300); e.fileRefuse();
  const refusedAt = f * (1000 / 60);
  run(4000);
  const licks = e.log.filter((l) => l[1] === "lick").map((l) => l[0] - refusedAt);
  assert.equal(licks.length, 1, `licks at ${licks}`);
  assert.ok(licks[0] > CATCH.gag + CATCH.ballUp, `the lick comes after the ball is up, at ${licks[0]} ms`);
  assert.equal(e.log.filter((l) => l[1] === "hairball").length, 1, "one hairball");
});

test("Greeting takes a clock, keeps one flag, and end() cancels its timers", () => {
  const set = [], cleared = [];
  globalThis.window = { setTimeout: (fn, ms) => { set.push([fn, ms]); return set.length; }, clearTimeout: (id) => cleared.push(id) };
  try {
    let now = 1000;
    const g = new Greeting(() => now);
    assert.equal(g.live, false, "not before it starts");
    g.start();
    assert.equal(g.live, true);
    assert.equal(set.length, 3, "the greet sound, the blip, and the completion");
    now = 2500;
    assert.equal(g.elapsed, 1.5, "the injected clock, in seconds since start");
    const view = g.view;
    now = 4000;
    assert.equal(view.now(), 4000, "the cat's own clock is the same one");
    g.interrupt();
    assert.equal(g.tc, 3, "interrupt() reads the injected clock");
    assert.deepEqual(cleared, [1, 2, 3], "and cancels what was pending, as before");
    cleared.length = 0;
    let ended = 0, completed = 0;
    g.onEnd = () => { ended++; }; g.onComplete = () => { completed++; };
    g.start();
    g.end();
    assert.equal(g.live, false);
    assert.deepEqual(cleared.slice(-3), [4, 5, 6], "end() cancels the three timers the new start() set");
    assert.deepEqual([ended, completed], [0, 0], "silently");
    const ctx = fakeCanvas();
    g.draw(ctx);
    assert.equal(ended, 0, "a greeting that is not running does not finish again");
    g.start();
    now += (GT.leave + GT3.end) * 1000;
    g.draw(ctx);
    assert.equal(g.live, false);
    assert.equal(ended, 1, "the last beat says so once");
  } finally { delete globalThis.window; }
});

test("a refusal that comes late holds the timeline where it is, never past the chew; an early one waits for the file to reach the mouth", () => {
  let ms = 0;
  Object.defineProperty(globalThis, "performance", { value: { now: () => ms }, configurable: true });
  const scene = (refuseAfter) => {
    ms = 0; UploadSeq.deactivate(); UploadSeq.enterZone(300, 100);
    ms = 400; UploadSeq.performDrop(2.4);
    ms = 400 + refuseAfter * 1000; UploadSeq.refuse();
    return (later) => { ms = 400 + (refuseAfter + later) * 1000; return UploadSeq.frame().t; };
  };
  const late = scene(1.2);
  assert.ok(Math.abs(late(0) - USC.T_CHEW_END) < 1e-9, `a late refusal holds at the end of the chew, not back at ${USC.T_SUCK_END}: ${late(0)}`);
  assert.ok(Math.abs(late(5) - USC.T_CHEW_END) < 1e-9, "and stays there");
  const mid = scene(0.5);
  assert.ok(Math.abs(mid(0) - (USC.T_DROP + 0.5)) < 1e-9, "a refusal while the cat chews holds right there");
  assert.ok(Math.abs(mid(3) - (USC.T_DROP + 0.5)) < 1e-9);
  const early = scene(0.1);
  assert.ok(Math.abs(early(0) - (USC.T_DROP + 0.1)) < 1e-9, "an early refusal does not stop the file in the air");
  assert.ok(Math.abs(early(0.15) - (USC.T_DROP + 0.25)) < 1e-9, "it keeps flying");
  assert.ok(Math.abs(early(3) - USC.T_SUCK_END) < 1e-9, "and holds when it reaches the mouth, as before");
  UploadSeq.deactivate();
});

test("the ?dev readout says how many cats it draws, not a number it does not", () => {
  const dev = source("cat/dev.ts");
  assert.ok(!dev.includes("twelve small cats plus the big one on a Mac"));
  assert.match(dev, /the \$\{live\.length\} live cats/);
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/leftovers.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; cd ..`
Expected: `not ok 1 - scripts/cat-tests/leftovers.test.mjs` (the file cannot load: it imports `CATCH`), `# tests 1`, `# pass 0`, `# fail 1`.

- [ ] **Step 3: One table for the catch, the emote guard and the late lick**

```ts title="windows/src/cat/engine.ts" old
const TARGET_KEYS: readonly (keyof Targets)[] = [
```

```ts title="windows/src/cat/engine.ts" new
/**
 * The file catch and the hairball, in ms: the numbers the cat, the drop view's note (island.ts) and the engine's own end-of-flow timer all wait on.
 * After the arrival: the lick, the sparks, and the end of the flow (the sparks have faded). A refusal: the pause before the first heave, the whole
 * hairball, when the ball leaves the mouth and how long a ball wrapping a file rolls.
 */
export const CATCH = { lick: 950, sparks: 1000, end: 2300, gag: 120, hairball: 2400, ballUp: 1110, fileBall: 2600 } as const;

const TARGET_KEYS: readonly (keyof Targets)[] = [
```

```ts title="windows/src/cat/engine.ts" old
  emote(n: string) {
    this.note("emote:" + n);
```

```ts title="windows/src/cat/engine.ts" new
  emote(n: string) {
    if (!own(EMOUTH, n) && n !== "hello" && n !== "zoomies" && n !== "hairball") return; // an unknown emote changes nothing, and is not logged
    this.note("emote:" + n);
```

```ts title="windows/src/cat/engine.ts" old
    this.later(950, () => this.lick(), "file");
    this.later(1000, () => this.emit("spark", 3), "file");
    this.fileEnd(1000 + 1300); // the sparks live 0.9 to 1.3 s
```

```ts title="windows/src/cat/engine.ts" new
    this.later(CATCH.lick, () => this.lick(), "file");
    this.later(CATCH.sparks, () => this.emit("spark", 3), "file");
    this.fileEnd(CATCH.end);
```

```ts title="windows/src/cat/engine.ts" old
    this.eyeUntil = 0;
    Sound.play("annoyed");
    this.later(120, () => this.hairball(ext), "file");
    this.fileEnd(120 + 1110 + 2600); // the ball comes up 1110 ms into the hairball and rolls for 2.6 s
```

```ts title="windows/src/cat/engine.ts" new
    this.eyeUntil = 0;
    // A refusal that comes after the cat began to chew: the chew's lick and sparks are not for a cat that is gagging.
    this.q = this.q.filter((x) => x.tag !== "file");
    Sound.play("annoyed");
    this.later(CATCH.gag, () => this.hairball(ext), "file");
    this.fileEnd(CATCH.gag + CATCH.ballUp + CATCH.fileBall);
```

```ts title="windows/src/cat/engine.ts" old
    this.later(1110, () => { if (tok === this.hbTok) this.spitBall(file); });
```

```ts title="windows/src/cat/engine.ts" new
    this.later(CATCH.ballUp, () => { if (tok === this.hbTok) this.spitBall(file); });
```

```ts title="windows/src/cat/engine.ts" old
age: 0, life: file ? 2.6 : 2.4,
```

```ts title="windows/src/cat/engine.ts" new
age: 0, life: (file ? CATCH.fileBall : CATCH.hairball) / 1000,
```

```ts title="windows/src/island/island.ts" old
import { BotEngine, catCfg } from "../cat/engine";
```

```ts title="windows/src/island/island.ts" new
import { BotEngine, CATCH, catCfg } from "../cat/engine";
```

```ts title="windows/src/island/island.ts" old
/** Seconds from the cat's refusal to the note: the 120 ms it takes to start heaving, and the hairball's 2.4 s. */
const HAIRBALL_S = 0.12 + 2.4;
```

```ts title="windows/src/island/island.ts" new
/** Seconds from the cat's refusal to the note: the pause before it starts heaving, and the hairball (the engine's `CATCH`). */
const HAIRBALL_S = (CATCH.gag + CATCH.hairball) / 1000;
```

- [ ] **Step 4: The greeting's clock, flag and timers**

```ts title="windows/src/cat/greeting.ts" old
function greetView(id: string, eye: () => EyeShape): CatView {
```

```ts title="windows/src/cat/greeting.ts" new
function greetView(id: string, eye: () => EyeShape, now: () => number): CatView {
```

```ts title="windows/src/cat/greeting.ts" old
  v.now = () => performance.now();
```

```ts title="windows/src/cat/greeting.ts" new
  v.now = now;
```

```ts title="windows/src/cat/greeting.ts" old
  private fired = false;
  private started = false;
  private ended = false;
  private timers: number[] = [];
  private eye: EyeShape = "pill";
  private view: CatView = greetView(DEFAULT_CAT, () => this.eye);
  private minis: CatView = miniView(catById(DEFAULT_CAT));

  onComplete: (() => void) | null = null;
  /** Fires once when the last beat is over, so the island can hand over to its own cat and grid. */
  onEnd: (() => void) | null = null;

  start() {
    this.startMs = performance.now();
    this.tc = Number.POSITIVE_INFINITY;
    this.fired = false;
    this.started = true;
    this.ended = false;
    this.view = greetView(catCfg.character ?? DEFAULT_CAT, () => this.eye);
```

```ts title="windows/src/cat/greeting.ts" new
  private fired = false;
  /** From start() until the last beat is over (or end()): the greeting canvas is up. */
  private running = false;
  private timers: number[] = [];
  private eye: EyeShape = "pill";
  private view: CatView;
  private minis: CatView;
  private readonly now: () => number;

  onComplete: (() => void) | null = null;
  /** Fires once when the last beat is over, so the island can hand over to its own cat and grid. */
  onEnd: (() => void) | null = null;

  /** `now` is the clock in milliseconds, `performance.now` unless a test gives it another. */
  constructor(now: () => number = () => performance.now()) {
    this.now = now;
    this.view = greetView(DEFAULT_CAT, () => this.eye, now);
    this.minis = miniView(catById(DEFAULT_CAT));
  }

  start() {
    this.startMs = this.now();
    this.tc = Number.POSITIVE_INFINITY;
    this.fired = false;
    this.running = true;
    this.view = greetView(catCfg.character ?? DEFAULT_CAT, () => this.eye, this.now);
```

```ts title="windows/src/cat/greeting.ts" old
    const t = (performance.now() - this.startMs) / 1000;
    if (!Number.isFinite(this.tc) || this.tc > t) this.tc = t;
```

```ts title="windows/src/cat/greeting.ts" new
    const t = (this.now() - this.startMs) / 1000;
    if (!Number.isFinite(this.tc) || this.tc > t) this.tc = t;
```

```ts title="windows/src/cat/greeting.ts" old
  get elapsed(): number { return (performance.now() - this.startMs) / 1000; }
  get done(): boolean { return this.fired; }
  /** True from start() until the last beat is over: the island keeps this canvas up through the compact island's tail. */
  get live(): boolean { return this.started && !this.ended; }
```

```ts title="windows/src/cat/greeting.ts" new
  get elapsed(): number { return (this.now() - this.startMs) / 1000; }
  get done(): boolean { return this.fired; }
  /** True from start() until the last beat is over: the island keeps this canvas up through the compact island's tail. */
  get live(): boolean { return this.running; }
```

```ts title="windows/src/cat/greeting.ts" old
  end() { this.ended = true; }
  private finish() {
    this.ended = true;
    this.onEnd?.();
  }
```

```ts title="windows/src/cat/greeting.ts" new
  end() {
    this.running = false;
    this.cancelTimers(); // the two sounds and the completion it still had to fire must not play for a greeting that is over
  }
  private finish() {
    this.running = false;
    this.onEnd?.();
  }
```

```ts title="windows/src/cat/greeting.ts" old
    if (!this.ended && t >= leave + GT3.end) this.finish();
```

```ts title="windows/src/cat/greeting.ts" new
    if (this.running && t >= leave + GT3.end) this.finish();
```

- [ ] **Step 5: The late refusal, and the readout's words**

`sequence.ts` is now loaded by the Node checks, so its one constructor parameter property (`public v`, which `--experimental-strip-types` cannot erase) becomes a plain field:

```ts title="windows/src/upload/sequence.ts" old
  vel = 0;
  constructor(public v: number) {}
```

```ts title="windows/src/upload/sequence.ts" new
  vel = 0;
  v: number;
  constructor(v: number) {
    this.v = v;
  }
```

```ts title="windows/src/upload/sequence.ts" old
  refused = false;

  cursorX = 600;
```

```ts title="windows/src/upload/sequence.ts" new
  refused = false;
  /**
   * Where a refused file's timeline stops: when the file reaches the mouth, or where it already was if the refusal came later (a big file is copied
   * before it is refused), but never past the chew: after that the cat leaves for the progress bar, and holding it there would show it in mid-air.
   */
  private holdAt: number = USC.T_SUCK_END;

  cursorX = 600;
```

```ts title="windows/src/upload/sequence.ts" old
  refuse() {
    this.refused = true;
  }
```

```ts title="windows/src/upload/sequence.ts" new
  refuse() {
    this.refused = true;
    this.holdAt = this.dropWall == null ? USC.T_SUCK_END : Math.min(Math.max(USC.T_DROP + (this.now() - this.dropWall), USC.T_SUCK_END), USC.T_CHEW_END);
  }
```

```ts title="windows/src/upload/sequence.ts" old
      return this.refused ? Math.min(t, USC.T_SUCK_END) : t;
```

```ts title="windows/src/upload/sequence.ts" new
      return this.refused ? Math.min(t, this.holdAt) : t;
```

```ts title="windows/src/cat/dev.ts" old
the live cats ${liveMs.toFixed(2)} ms (the budget is 2 ms for twelve small cats plus the big one on a Mac)
```

```ts title="windows/src/cat/dev.ts" new
the ${live.length} live cats ${liveMs.toFixed(2)} ms (the Mac's budget is 2 ms for twelve small cats plus the big one)
```

- [ ] **Step 6: Run the tests, the type check and every check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/leftovers.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: `# tests 6`, `# pass 6`, `# fail 0`, `tsc exit 0`, then `ℹ tests 165`, `ℹ pass 165`, `ℹ fail 0` (the greeting's, the catch's and the emotes' fixture rows among them, unchanged).

- [ ] **Step 7: Commit**

```bash
git add windows/src/cat/engine.ts windows/src/island/island.ts windows/src/cat/greeting.ts windows/src/upload/sequence.ts windows/src/cat/dev.ts windows/scripts/cat-tests/leftovers.test.mjs
git commit -m "fix(cat): the catch's numbers in one table, a clock for the greeting, no lick in a hairball, no snap on a late refusal

CATCH replaces five copies of the same timings. Greeting takes a clock, keeps one flag, and end() cancels its timers. A refusal after the cat
began to chew clears the chew's lick and holds the timeline where it is (never past the chew). An unknown emote is not logged. The ?dev
readout counts the cats it draws.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 17: The last Mochi names, the docs, CI and the final checks

**Agent:** `nm-implementer-light`.

"No mochi/Mochi identifiers remain" (the spec's Done means). Task 15 already rewrote the engine's header comment (`engine.ts:2`). Three mentions are left in the Windows and Linux code: `cat/minibots.ts:1` and `:17` and `upload/sequence.ts:364`. This task renames them and adds a guard that reads the whole of `windows/` (code, comments, scripts, the README, the manifests). It also documents what stages 5 to 7 added and lets CI watch the one file the Windows checks read from the Mac's tree.

**Files:**
- Modify: `windows/src/cat/minibots.ts`, `windows/src/upload/sequence.ts`, `windows/README.md`, `CLAUDE.md`, `ARCHITECT.md`, `.github/workflows/windows-tests.yml`
- Create: `windows/scripts/cat-tests/names.test.mjs`

**Interfaces:**
- Consumes: nothing new.
- Produces: `names.test.mjs`, which fails when the old character's name appears anywhere under `windows/` (folders that are build output are skipped: `node_modules`, `target`, `dist`, `release`, `gen`). It does not sweep what is outside `windows/`: the historical plans, specs, `CHANGELOG.md`, the French `docs/SPEC.md` and the issue template still say Mochi, and the Mac plan sweeps `NotchBuddy/`. See the open questions.

- [ ] **Step 1: Write the failing test**

```js title="windows/scripts/cat-tests/names.test.mjs" create
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

// The upstream character's name is gone from the Windows and Linux app: code, comments, scripts, the README and the manifests. Historical plans,
// specs and the git history are not swept. The word is built from two halves, so that this file does not contain it.
const NAME = new RegExp("mo" + "chi", "i");
const root = new URL("../../", import.meta.url).pathname;
const SKIP = new Set(["node_modules", "target", "dist", "release", "gen", ".playwright-cli"]);
const BINARY = /\.(png|ico|icns|wav|mp3|woff2?|bin|exe|dll|node|zip|gz)$/i;

function* walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) yield* walk(p);
    else yield p;
  }
}

test("no file of windows/, and no file name, says the old character's name", () => {
  const hits = [];
  let read = 0;
  for (const f of walk(root)) {
    const rel = path.relative(root, f);
    if (NAME.test(rel)) hits.push(`${rel} (its name)`);
    if (BINARY.test(f)) continue;
    read++;
    if (NAME.test(fs.readFileSync(f, "utf8"))) hits.push(rel);
  }
  assert.ok(read > 100, `${read} files read`);
  assert.deepEqual(hits, []);
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/names.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)|minibots|sequence"; cd ..`
Expected: `not ok 1 - no file of windows/, and no file name, says the old character's name`, then the two files in the failure's difference, `src/cat/minibots.ts` and `src/upload/sequence.ts`, then `# tests 1`, `# pass 0`, `# fail 1`.

- [ ] **Step 3: The three mentions**

```ts title="windows/src/cat/minibots.ts" old
// Mini Mochis (pills + compact grid) — port of MiniBotCanvasView.
```

```ts title="windows/src/cat/minibots.ts" new
// Mini cats (pills + compact grid) — port of MiniBotCanvasView.
```

```ts title="windows/src/cat/minibots.ts" old
 * Creates a mini Mochi whose **body** is `bodySize` CSS pixels across.
```

```ts title="windows/src/cat/minibots.ts" new
 * Creates a mini cat whose **body** is `bodySize` CSS pixels across.
```

```ts title="windows/src/upload/sequence.ts" old
    // Tilt follows how fast Mochi is sliding.
```

```ts title="windows/src/upload/sequence.ts" new
    // Tilt follows how fast the cat is sliding.
```

- [ ] **Step 4: The README, the guides and CI**

```md title="windows/README.md" old
| Rest the pointer on the cat for two seconds | Hearts |
```

```md title="windows/README.md" new
| Rest the pointer on the cat for two seconds | Hearts |
| Leave the cat alone for ten minutes, with no agent running | It falls asleep. A hook event, a hover or a click wakes it, with a burst of zoomies if it is in Playful. It never sleeps through an approval or a question |
```

```md title="windows/README.md" old
your integrations sit in the coloured pills next to the cat.

## Claude Code
```

```md title="windows/README.md" new
your integrations sit in the coloured pills next to the cat.

## Your cat

**Settings… → Cat** chooses which of the 16 cats lives at the top of your screen, how it moves (Playful or Classic), its personality (six sliders and six presets, and "Custom" once you move one), and whether it wears a **collar** in the colour of the agent it is watching: Band and tag, Band, Neckerchief, or Off, which is the default. Each cat keeps its own motion, personality and collar, **Apply to every cat** copies one cat's to all 16, and **Fur lines** draws strands on a big cat. The previews in that section move only while the window is open and has focus.

The cat reacts to what your agents do: it searches while one runs a search tool (web search, web fetch, grep, glob), and the small cats in the pills and in the compact island wear their agent's collar. Gemini CLI is blue and Antigravity pink, as on the Mac.

## Claude Code
```

```md title="windows/README.md" old
`http://127.0.0.1:1420/dev/upload-preview.html` plays the file catch (add `?refuse` for the hairball).
```

```md title="windows/README.md" new
`http://127.0.0.1:1420/dev/upload-preview.html` plays the file catch (add `?refuse` for the hairball).

`?dev` also has a **Collar** panel (a style and an agent colour, worn by the coat ladder at every size from Ø12 up, the States strip and the Compact notch), a "Wake the sleeping cat" button and a "dance (music)" button on the big cat. `npm run check:cat` covers the stored settings (replayed from `settings-cases.json`, with the Rust twin in `src-tauri/src/cat_settings.rs`, which `cargo test` replays too), the collar's geometry and its painting, the search tools, the sleep clock, the dance, the dead-code and old-name guards. The island's own glue (the Settings window, the hook handlers' wiring, the `?dev` page) is checked by eye and by source pins.

The app has no music source on Windows or Linux yet: the cat's bob is built (`src/cat/dance.ts`) and `State.musicPlaying` is the switch, which nothing turns on today.
```

```md title="CLAUDE.md" old
`npx vite` then `http://127.0.0.1:1420/?dev` is the contact sheet.
```

```md title="CLAUDE.md" new
`npx vite` then `http://127.0.0.1:1420/?dev` is the contact sheet. The Cat settings are `cat/settings.ts` (the Rust twin is `src-tauri/src/cat_settings.rs`, which cleans the `cat` block of `settings.json`; both replay `tests/fixtures/cat/settings-cases.json`), their Settings section is `settings/cat.ts`, and the collar is `cat/collar.ts`, the music bob `cat/dance.ts` and the ten-minute sleep `island/sleep.ts`.
```

```md title="ARCHITECT.md" old
Checked by `npm run check:cat` against `tests/fixtures/cat/`.
```

```md title="ARCHITECT.md" new
Checked by `npm run check:cat` against `tests/fixtures/cat/`. Settings → Cat (`settings/cat.ts`) saves a `cat` block that `settings.rs` holds as a JSON value and cleans (`cat_settings.rs`), as `cleanCatSettings` does in `cat/settings.ts`; the engines read the result through the shared `catCfg`. The collar (`collar.ts`), searching (`toolState` in `island/hooks.ts`), the ten-minute sleep (`island/sleep.ts`) and the music bob (`dance.ts`) follow the contract.
```

```yaml title=".github/workflows/windows-tests.yml" old
      - 'tests/fixtures/cat/**'
```

```yaml title=".github/workflows/windows-tests.yml" new
      - 'tests/fixtures/cat/**'
      - 'NotchBuddy/Sources/App/PillCatalog.swift'
```

- [ ] **Step 5: The guard, the type check and every front-end check**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/names.test.mjs 2>&1 | grep -E "^not ok|^# (tests|pass|fail)"; npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1; cd ..`
Expected: `# tests 1`, `# pass 1`, `# fail 0`, `tsc exit 0`, `ℹ tests 166`, `ℹ pass 166`, `ℹ fail 0`, `All AI UI checks passed` and `All Claude Code UI checks passed`.

Run: `grep -rniI "mochi" windows --exclude-dir=node_modules --exclude-dir=target --exclude-dir=dist | grep -v "^windows/scripts/cat-tests/names.test.mjs" | head -3; echo "grep done"`
Expected: no match before `grep done`.

- [ ] **Step 6: The final checks**

Run the Rust suite, the contracts, and prove nothing outside this plan's files changed.

Run: `windows/scripts/cargo-linux.sh test --workspace --target-dir /repo/windows/target/a-tauri-57 2>&1 | grep -E "^test result|^error|^warning|FAILED"`
Expected: four `test result: ok.` lines, no `error`, `warning` or `FAILED`: the app's library `239 passed` (the 229 that were there and the 10 of Task 2), the relay `23 passed`, and two empty doc-test lines.

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓ [0-9]+ fixture files|✓ two"; bash scripts/test-theme.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓ 3 theme"`
Expected: `# tests 138`, `# pass 138`, `# fail 0`, `✓ 9 fixture files match cat-core.js`, `✓ two generator runs write identical bytes`; then `# tests 8`, `# pass 8`, `# fail 0` and `✓ 3 theme files match shared/theme.json`. (This plan changes neither the contract nor the theme source.)

Run: `git status --short | grep -vE "^( M|\?\?) (windows/|docs/superpowers/plans/|CLAUDE.md|ARCHITECT.md|\.github/workflows/windows-tests.yml)"; echo "nothing else changed"`
Expected: only `nothing else changed`, and, in a dry-run clone, the lines of A-0d's uncommitted files above it (`NotchBuddy/…`, `design/…`, `shared/`, `scripts/…`, `tests/…`, `docs/CAT-CONTRACT.md`, `docs/THEME.md`, `.github/workflows/build.yml`): this plan touches none of them. In a worktree that has this plan's commits, run `git diff --stat notchmeow/rebrand -- NotchBuddy design tests shared scripts docs/CAT-CONTRACT.md docs/THEME.md` instead: it prints nothing.

Not run here, by rule: the Windows `cargo check` (the Rust of this plan is plain `serde_json`, with no `cfg(windows)` line, but only the Windows CI job compiles for Windows) and a release build (`npm run build` runs a host build of the relay). Both are owed to the `windows-tests.yml` and `windows.yml` jobs on the owner's next push.

- [ ] **Step 7: Commit**

```bash
git add windows/src/cat/minibots.ts windows/src/upload/sequence.ts windows/scripts/cat-tests/names.test.mjs windows/README.md CLAUDE.md ARCHITECT.md .github/workflows/windows-tests.yml
git commit -m "chore(cat): the last Mochi names in windows/, a guard for them, and the docs and CI for stages 5 to 7

The README describes Settings -> Cat, the collar, searching and sleeping, and what ?dev and check:cat cover. CLAUDE.md and
ARCHITECT.md name the new files. The Windows tests also run when PillCatalog.swift changes, because a test reads its colours.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Checkpoint 3: the owner signs off

**Owner checkpoint** (the executing session; no agent). Stages 5 to 7 are done when the owner says so. Then the whole-branch review (`nm-reviewer-deep`).

- [ ] Send the owner, in the chat: the checkpoint images already sent (Settings → Cat, the collars), the greeting's and the island's `?dev` shots from Task 15 Step 7 (`drop-ok.png`, `drop-refuse.png`), and the report: the commits, the test counts (`check:cat`, `check:ai`, `check:claude`, `cargo test --workspace`, the contract and theme runners), the before and after record of Task 13 (equal), whether Task 14 ran, and what was not done (the Windows `cargo check` and a release build, owed to CI; the `syncDom` wiring test).
- [ ] Say what the owner should check by hand in a real build (`cd windows && npm run tauri dev`, on Windows or Linux, never started by the session): the **launch greeting** (and again with the pointer leaving halfway); **Settings → Cat**: the sixteen previews move while the window is open and stand still when another window has focus, the choice, motion, personality and collar changes reach the island with no restart, and a hand-edited bad `cat` block loads the defaults and leaves the rest of the file alone; a real **file drop**, a refused one (a `.zip`, an `.exe`, a file over 25 MB, the big one for the late refusal) and a folder: as before; **searching**: a real Claude Code or Gemini CLI session that runs a web search or a grep puts the pill's cat in the searching look and the next tool puts it back to working; **sleeping**: ten minutes with nothing running (the cats sleep, the pills too), then the pointer over the island wakes them, with zoomies in Playful, and a pending approval or question is never slept through; the **collar** of Gemini CLI (blue) and Antigravity (pink) in their pills; **0 % CPU** in Task Manager with the island hidden and Settings closed, and with Settings open but unfocused; and that **nothing looks different** from before in the greeting, the file catch, the island's glow and the cat's details (the theme swap).
- [ ] Wait for the owner's OK.


---

## Parity with macOS

**macOS is the primary platform**: the Mac gets at least what Windows and Linux get. The Mac twin is `docs/superpowers/plans/2026-10-07-a-mac-cats-stages-5-7.md`; when this plan was written it was still a skeleton whose task list (a clean-up port, the engine feed, fur lines, the Settings section, the collar in three tasks, searching, sleeping, the music bob, the theme tokens, the dead code, the Mochi sweep) matches this plan's stages one for one. The main session reads the two together. Everything below is **in this plan and not (known to be) in the Mac's**; each line says whether the Mac should add it or whether it is Windows-only on purpose.

**What both apps do the same, on purpose.** The stored settings (`cleanCatSettings`, the same fixture, `Personality.sanitized` on the Mac and `cleanPersonality` here), the Cat section's rows in spec §4's order, the collar's geometry and floors from `collar-cases.json`, the front-pass slot, the style IDs, the search tools from `search-tools.json`, the 10-minute rule from `sequence-cases.json`, the 0.3 s and 0.5 s dance fade and the 112 BPM beat, the theme tokens (`THEME.cat.pupil` and `Theme.Cat.pupil`), the removed dead code with `greet()` kept, and the owner's checkpoints.

**Added here that the Mac plan should consider:**

1. **A big live preview of the chosen cat in the Cat section** (Task 4). The spec asks for a small live preview of each cat. The renderer draws fur strands only on a head of radius 30 px or more (about Ø70: the contract page's own rule), and the biggest cat in either app's island is Ø66, so the **Fur lines switch has no visible effect on a cat the user can see**, here or on the Mac. A big preview makes it (and the collar) visible. *Mac: add the same, or say that Fur lines stay invisible.*
2. **The previews also stop when the Settings window is not focused,** not only when it is hidden (Task 4). The Windows Settings window is created hidden at launch and kept, and the webview's own visibility event is the only signal, so the loop also requires focus. *Windows-only: the Mac uses its window's visibility.*
3. **An ear bounce on the landing beat** (Task 12, `danceEars`: the `earU` target up to 0.14 above rest, scaled by the dancing level). The spec says "with the ears bouncing on the beat"; the Mac's existing `CatEffects.applyDance` moves the whole head and the ears ride with it, and has no ear term. *Mac: add `danceEars`, or drop it here: it is the one Windows number with no Mac source, and Task 12 is its own task for that reason.*
4. **The big cat's collar rule** (Task 8): the focused pill's colour when the cat's state is anything but `idle`, `sleeping` or `dizzy`, with **no `isIntegration` test**. The Mac's stage 1 to 4 code sets `engine.collar` only when `focusTask.isIntegration`. The Windows external agents (`agent_gemini`, `agent_antigravity`) are created with `isIntegration: false`, which would have left them without a collar. *Mac: check how its `agent_*` pills are flagged and use the same rule.*
5. **Sleeping covers every idle cat,** the pills and the compact grid as well as the big one (`State.shownState`, Task 11); the spec says "an idle cat sleeps". *Mac: decide the same.*
6. **The sleep clock arms on every event for the full ten minutes and checks the state when it fires** (Task 11), instead of arming only when the state is idle: every transition into idle comes with a hook event (a Stop, a SessionEnd, or the 5.2 s return of a `finished` pill, which is counted from the Stop). Never a poll. A timer that fires early waits the rest. *Mac: the same design avoids a second timer per state change.*
7. **The pills' colours are checked against the other platform's file** (Task 5): a Windows test reads `NotchBuddy/Sources/App/PillCatalog.swift`, and `windows-tests.yml` runs when that file changes (Task 17). *Mac: the reverse guard (a test that reads `windows/src/core/pills.ts`) would close the loop.*
8. **Window-level fixes of the Windows catch** that have no Mac twin because the Mac code differs (Task 16): `CATCH` (one table for the catch's numbers), a refusal after the chew began clears the chew's lick and holds the timeline, an unknown emote is not logged, `Greeting` takes a clock. The Mac's own "left for stage 7" list (owner-manual-checks) is a different list.
9. **A before and after record for the theme swap** (Task 13): a recording canvas (every call and style of 16 coats, the greeting and the glow) and a `?dev` fingerprint. The Mac plan has its own (contact sheets rendered by `render-cats.sh`); *both prove the same thing, and the Mac's sheets can stay as they are.*
10. **Pure edit helpers** for the Settings rows (`withCharacter`, `withMotionStyle`, `withCatMotion`, `withPersonality`, …, Task 4) so a row can only change its own field. *Mac: SwiftUI bindings do the same job; a small test that one edit changes one key is the same safety.*
11. **`names.test.mjs`, a guard against the old name in the whole `windows/` tree** (Task 17), and **`deadcode.test.mjs`**, a guard against the removed names (Task 15). *Mac: the Mochi sweep "+ guard" in its skeleton is the same idea.*

**Windows-only on purpose (platform extras):** the Gemini CLI and Antigravity pill colours (the Mac already has them: this is Windows catching up, Task 5); the Rust twin of the clean-up and the `Value`-typed `cat` block (the Mac stores `UserDefaults` keys and goes through `Personality.sanitized`); the Settings window's hidden-but-alive lifetime; no music source (the Mac has the Apple Music pill and poller; here only the cat's side and a switch, `State.musicPlaying`, exist, which nothing sets: see the open questions); the Windows CSS file `theme.generated.css`, which no Windows site uses.

**What the Mac has that Windows already has:** fur strands (the Mac draws none today and its plan adds `CatFur`; the Windows renderer has drawn them since stage 1).

**Docs.** `docs/THEME.md` still says the apps do not use the tokens yet. This plan does not edit it, and the Mac plan should not either: the main session updates it once both stage 7 branches have merged (two plans editing one paragraph would conflict). The Windows lines of `CLAUDE.md` and `ARCHITECT.md` are edited in Task 17, in lines the Mac plan's edits do not touch.

---

## Open questions for the owner

Each has the answer this plan assumes, so nothing blocks. The ones marked **ask at Checkpoint N** are put to the owner there.

1. **The island's glow** (`core/layout.ts`, seven literals). May stage 7 swap them for `THEME.state.glow`? Same values, no change of look (the before and after record proves it). *Ask at Checkpoint 2.* Assumed: yes. Task 14 runs on a yes and is skipped on a no.
2. **No music source on Windows and Linux.** The spec's music bob needs "music is playing", and the Windows app has no media reader (no pill, no poller, no dance in the engine). Task 12 builds the cat's side (the Mac's dance numbers, the engine's level, `shouldDance`, a `?dev` button) and a switch, `State.musicPlaying`, that nothing sets. A real source is a platform feature of its own (Windows' media session, Linux MPRIS over D-Bus), a new Rust dependency or `windows` crate features, so it is **not** in this plan. Assumed: build the cat's side now, plan the source later, and drop Task 12 if you would rather not carry an unused switch.
3. **The big cat's collar.** It wears the focused pill's colour in every state except idle, asleep and dizzy, whichever pill drives it (Gemini CLI's blue, Antigravity's pink included). The spec says "the agent driving its current state, and none when idle". Dizzy (three pokes) and sleeping are the cat's own states, so they carry none (plan decision). OK?
4. **A collar over the integration pills' colours.** The mini cats in the pills wear their pill's colour whatever their state, Resend green and Stripe blue included, because "small cats wear their agent's collar" and every pill has a colour. With the collar Off (the default) nothing changes. OK? (plan decision)
5. **Two pills change colour on Windows and Linux** (Task 5): Gemini CLI from pink to the Mac's blue `#8AB4F8`, Antigravity from green to the Mac's pink `#E879F9`. Their tinted border, hover glow and badge follow. It is the one existing view this plan restyles, by your decision of 2026-10-06. *Ask at Checkpoint 2 with the pictures.*
6. **Fur lines have nothing to show on a cat of Ø66 or less** (see Parity 1). The Windows Cat section therefore has a big preview (Ø84, so its radius is over 30 px). Keep it? Without it the switch is invisible; with it, Windows shows something the Mac's Settings does not, unless the Mac plan adds one too. Assumed: keep it.
7. **Sleeping covers the pills and the compact grid too** (Parity 5), and the previews in Settings stand still while the window is unfocused (Parity 2). Assumed: both OK.
8. **The ear bounce is Windows' own** (Parity 3). Assumed: keep it with the music bob, and drop both if you drop Task 12.
9. **A refusal that comes very late** (Task 16) now holds the drop timeline at the end of the chew (2.88 s of the 4 s choreography) and no longer snaps back to the 2.33 s mark. A refusal that comes after the cat has left for the progress bar still moves the picture back to the end of the chew, a shorter jump than before and not a smooth one. A cleaner behaviour (cut straight to the note, or let the bar finish first) is a design choice for you: Assumed: this smaller fix is enough for now.
10. **Mochi outside `windows/`.** `docs/SPEC.md` (the French behaviour spec: "Le personnage : Mochi", the menu bar icon), `.github/ISSUE_TEMPLATE/feature_request.md`, and `CHANGELOG.md` (history) still name the old character. `windows/` is clean and guarded; the Mac plan sweeps `NotchBuddy/`. These three are neither app's code. Assumed: leave `CHANGELOG.md` as history, and rewrite the other two in a docs chore after the stages merge.
11. **`windows/src/theme.generated.css`** has no Windows site: every Windows colour to replace is in TypeScript, and the Settings window's colours are upstream's own. A-0d generates the file for the apps; Windows does not import it. Assumed: leave it generated and unused.
12. **`syncDom`'s wiring** (the island's DOM sync during the greeting's hand-over) has no test: it needs a browser with the whole island. The greeting's and the hand-over's own logic are tested, and Checkpoint 3 has you watch it. Assumed: fine.

---

## Self-review notes

- **Spec coverage.** §4: Character (the sixteen previews and the big one, Task 4), Motion style and This cat's motion (Tasks 1, 3, 4), Personality and the six sliders with Custom (Tasks 1, 4), Collar and This cat's collar (Task 8), Apply to every cat (Tasks 1, 4, 8), Fur lines (Tasks 3, 4); persistence and the frozen IDs (Tasks 1, 2); "the preview animates only while Settings is visible" (Task 4). §3: collar (Tasks 5 to 9), searching (10), sleeping (11), music (12), removed dead code (15), the Greeting and drop leftovers (16). §5: theme tokens (13, 14); checks (every task, 17). Stage 7's Mochi sweep (15, 17). Icons: left out entirely. The spec's "Fixes" (the Mac clock bug and the ear room) are Mac and stage 1 to 4 items.
- **Placeholders.** None: every code step is a full `create` block or an exact find and replacement, generated from the files the dry run ran.
- **Type consistency.** The names are the ones A-0d's interface table fixes (`FOLLOW`, `MOTION_STYLES`, `motionStyleOf`, `motionOverrideOf`, `collarOverrideOf`, `catIdOf`, `cleanPersonality`, `cleanCatSettings`, `defaultCatSettings`, `applyToAllCats`, `motionFor`, `collarFor`, `engineCfg`), and A-0b's (`COLLAR_STYLES`, `collarStyleOf`, `collarGeometry`, `COLLAR_MIN`, `COLLAR_PASS`, `isSearchTool`, `toolState`, `SEARCH_TOOLS`, `sleepDelay`, `SLEEP_AFTER_MS`, `wakes`, `WAKE_EVENTS`); the plan's own are used with one spelling (`applyCatSettings`, `LiveCfg`, `catCfg.character`, `collar`, `fur`, `collarColor`, `bigCatCollar`, `shownState`, `noteActivity`, `CATCH`).
- **Review Focus** lines 1 to 5 each have named tests above.
- **What this plan deliberately does not do:** icons; sound wiring; Codex on Windows; B, H and I; a music source; a Windows `cargo check` and a release build (owed to CI).

---

## Dry run (2026-10-07)

The plan was run before it was handed over, on a throwaway clone, task by task and then once more from the top, so that every `create` / `old` / `new` block applies and every `Run:` line prints what its `Expected:` says. Nothing was committed or pushed, no NotchMeow app was started, nothing was installed or downloaded, and no network was used.

**Set-up.** `git clone --local --shared` of this repository on `notchmeow/rebrand` at `f704178` (the base this plan names), in the session scratchpad. `windows/node_modules` is a symlink to the main checkout's (nothing was installed). **A-0d was applied first, exactly as its plan is written** (its Tasks 1 to 4, with the commit steps and the Mac Debug `xcodebuild` skipped), because this plan's base is "after A-0d": its 45 blocks and runs ran with 35 `Expected:` lines checked and 0 edit failures, and left the clone with `windows/src/theme.generated.ts` and `.css`, `shared/theme.json`, `tests/fixtures/cat/settings-cases.json` and the other A-0d files that Task 1 of this plan reads. The Rust side ran in `notchmeow-linux-dev` through `windows/scripts/cargo-linux.sh … --target-dir /repo/windows/target/a-tauri-57` (`docker image inspect notchmeow-linux-dev` first: present). Headless eye checks (Tasks 4, 9, 13, 15) used `npx --no-install vite` on port 14571 and `playwright-cli`, then the server and the sessions were stopped.

**Method.** Each task was applied from the plan's text only (a small runner reads the blocks and the `Run:` lines of one task, applies them to the clone, and prints the real output next to the plan's `Expected:`), and a snapshot of the clone was kept after each task so that the next task started from the state the plan promises. A failed step was fixed **in the plan**, never in the clone, and the task was run again from its snapshot. Then the **whole plan was replayed from the A-0d base** (Tasks 1 to 17 in one go, about four minutes): 291 blocks and runs, **0 edit failures**, and **all 57 `Expected:` comparisons that carry a count or a literal output matched**.

| Task | Agent | What the run printed (the plan's Expected) |
|---|---|---|
| 1 | light | `settings.test.mjs` 12 pass; `tsc exit 0`; `check:cat` 101 |
| 2 | nm-implementer | existing `settings::` 7 pass first; `cat_settings::` 7 pass; `settings::` 17 pass; workspace: app lib 239 passed, relay 23 passed, no warning |
| 3 | nm-implementer | `follow.test.mjs` 5 pass; `check:cat` 106 |
| 4 | nm-implementer | `loop` + `settings-edit` 9 pass; `check:cat` 115; screenshots `cat-section.png`, `cat-momo.png` made |
| 5 | light | `pills.test.mjs` 4 pass; `check:cat` 119 |
| 6 | light | `collar.test.mjs` 8 pass (164 fixture cases); `check:cat` 127 |
| 7 | nm-implementer | `collar-draw.test.mjs` 6 pass; `check:cat` 133 |
| 8 | nm-implementer | `collar-wiring` + `engine` pass; `check:cat` 137 |
| 9 | nm-implementer | `tsc exit 0`; `check:cat` 137; the eight collar shots (band, band and tag, neckerchief and Off, each on a light and on a dark island) made at 2x |
| 10 | light | `search.test.mjs` 4 pass; `check:cat` 141 |
| 11 | nm-implementer | `sleep.test.mjs` 9 pass; `check:cat` 150 |
| 12 | nm-implementer | `dance.test.mjs` 7 pass; `check:cat` 157; six dance frames made |
| 13 | nm-implementer | before and after records equal (`cmp` silent); the deliberately wrong token **is** caught (`differ`), then put back; `check:cat` 157 |
| 14 | light | recorder still equal after the glow swap; `check:cat` 157 |
| 15 | nm-implementer | `deadcode.test.mjs` 2 pass; `check:cat` 159; `check:ai` and `check:claude` pass |
| 16 | nm-implementer | `leftovers.test.mjs` 6 pass; `check:cat` 165 |
| 17 | light | `names.test.mjs` pass; `check:cat` 166; `check:ai`, `check:claude`, the contract tests (138) and the theme tests (8) pass; the last `git status` shows nothing outside what the plan lists |

**What the dry run changed in the plan** (everything below was a defect in an earlier draft, found because a step failed or printed something else, and is now fixed in the text):

- **Rust (Task 2).** The first `cat_settings.rs` and its tests did not compile (a `json!` form that moved a `Value`, and some integer-versus-float mismatches between `Value` numbers and the test's literals). The text in the plan is the version that compiled and passed against `settings-cases.json`; the module's 14 `never used` warnings before it is wired (Step 4) are in the Expected line, and the workspace run after wiring prints none.
- **TypeScript that `check:cat` loads.** `node --experimental-strip-types` erases types and cannot run a **constructor parameter property**; one class had one, and it is a plain field with an assignment now. The "Files loaded by `npm run check:cat`" constraint at the top of the plan states the rule (no `enum`, no `namespace`, no parameter property, `.ts` extensions on relative imports).
- **Counts and expected text.** Many `Expected:` lines were written from the code's intent and corrected to the real output: the running `check:cat` total after each task, the number of warnings Rust prints before a module is wired, the `git status` and `git diff --stat` lines, and the number of fixture cases a test replays.
- **Task 13, Step 8.** `git diff --stat -- windows` printed 16 files in a clone that commits nothing, so its Expected line could not be true there. It now says what to expect in a worktree where the earlier tasks are committed and in a clone that is not, and a second `Run:` (`git diff --name-only -- windows/src/core/layout.ts windows/src/style.css | wc -l`, Expected `0`) holds in both (re-run in the clone after the edit: `0`).
- **Shell and screenshot steps.** Steps that nest one heredoc inside another use distinct end markers (`PY`, `EOF`) or a `create` block. `playwright-cli` leaves a `.playwright-cli` folder in its working directory, so the steps run it from the scratch folder and never from the repository (and `names.test.mjs` skips such a folder). The 2x shots go through a second browser context made with `deviceScaleFactor: 2`. The `?dev` fingerprint and the recording canvas lower-case every colour, because the generated tokens are written in capitals and the old literals in lower case: the same colour in any case, so that comparison does not report a case change as a pixel change.
- **`names.test.mjs` (Task 17).** Its "files read" floor (`read > 100`) is a number the real tree exceeds, so the test cannot pass by reading an empty folder; Step 2 shows it fail on `src/cat/minibots.ts` and `src/upload/sequence.ts` before the sweep, and Step 4 shows it pass after.

**Not run, and owed.**

- **The Windows `cargo check` and a release build** (`npm run build` also runs a host build of the relay): by rule not run here, and owed to the `windows-tests.yml` and `windows.yml` jobs on the owner's next push. This plan adds Rust only in `cat_settings.rs` and a field in `settings.rs`, both plain `serde_json` with no `cfg(windows)` line, which the Linux build in the container compiled and tested.
- **Any commit step.** Every `git add` / `git commit` block was skipped in the clone and has to be run by the executing session in its worktree. The owner's rule stays: the plan's executor commits on its branch, never pushes.
- **The Tauri app itself.** No window of the real app was opened, so the Settings window's hidden-but-alive lifetime, the real focus events, the island with a real hook event, the greeting's hand-over (`syncDom`) and the 0 % CPU rule with the island hidden are Checkpoint 3's list for the owner, not something this run proved. The `?dev` page and `settings.html` under Vite were looked at headlessly, which proves the drawing and the layout and nothing about the shell around them.
- **The Mac.** `xcodebuild` and `scripts/render-cats.sh` were not run (A-0d's Debug build step was skipped); this plan touches nothing under `NotchBuddy/`, which Task 17's last `git status` shows.

The clones, the snapshots and the shot folder were moved to the Trash afterwards (`trash`, never `rm -rf`).

## The owner's answers (2026-10-07)

- **Plan:** approved, run in a worktree session on Sonnet 5.5, effort high, in parallel with the Mac twin, on `notchmeow/rebrand` after A-0d (merged as `ac30fac`; the icon swap `f704178` is in the base too).
- **Open questions 2 to 12:** as assumed (question 5, the Gemini and Antigravity pill colours, is the owner's 2026-10-06 decision). **Question 1, the island glow,** is asked at checkpoint 2, as planned.
- The Mac keeps its 8-segment whisker taper (the Mac plan's question 14), so the icons stay as approved; Windows keeps its 16.
- The feature-request template's old character name was fixed separately (`2a07b50`), so question 10 leaves only `docs/SPEC.md` for a later docs pass.
