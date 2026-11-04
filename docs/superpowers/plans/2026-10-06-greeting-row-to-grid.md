# Greeting: the session cats glide from a row into the grid. Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The launch greeting ends on the prototype's row of three session cats, which then glide into the 2×2 grid the compact island really shows (a fourth cat pops into the empty cell), so the hand-over to the real compact island never jumps, on the prototype page, on the Mac and on Windows/Linux.

**Architecture:** The pure contract `design/prototype/cat-core.js` gains the last beat of the greeting as new constants and two functions (`miniGlide`, `miniSlots`), with fixtures added to `sequence-cases.json` by addition only. The prototype page and both apps draw it from those slots. After the island folds, the greeting canvas stays up through the beat (`AppState.greetingTail` on the Mac, `greetingShown()` and `Greeting.onEnd` on Windows), while the real `CompactMiniGrid` / `#mini-grid` is hidden and fades in as the canvas fades out; their own looks do not change. Each app proves that the last frame is its compact island's grid.

**Tech Stack:** JavaScript (`cat-core.js`, Node 22 `node:test`), Swift 6 with `swiftc` test programs, SwiftUI, TypeScript (Tauri front end, `node --experimental-strip-types --test`), one static HTML page. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-04-cats-in-app-design.md`, the **Greeting** paragraph and the amendment of 2026-10-06 that Task 0 adds. Also read `docs/CAT-CONTRACT.md`, `ARCHITECT.md` and `CLAUDE.md`.

**Base:** `notchmeow/rebrand` at `89a1344` (both cat branches are merged). Branch `a0c/greeting-grid`, in a worktree. Every edit below is anchored by exact text, never by line number.

## Global Constraints

Every task's requirements include this section.

- **Owner's decision, 2026-10-06:** the greeting's last beat brings in the session cats as the prototype's **row of three** beside the main cat in the compact island, then they **glide into the 2×2 grid** the shipping compact island shows, so the hand-over never jumps.
- **Order of work (the owner's):** the prototype and `cat-core.js`, then the regenerated fixtures, then the Mac, then Windows/Linux. The Mac gets at least what Windows gets.
- **`cat-core.js` is the tie-breaker.** If an app and a fixture disagree, the app is wrong. After changing the core, run `node scripts/gen-cat-fixtures.mjs` and commit the fixtures with it.
- **Fixtures change only by addition** (`docs/CAT-CONTRACT.md`): every line of every existing case stays byte for byte, proved by `node scripts/check-fixtures-additive.mjs`. So `greetingPose()` gains no key, `GT` and `GT2` gain no key and `GREET_LEN` stays 5.74 s. The new beat has its own constants (`GT3`, `GREET_END`) and functions.
- **The shipping compact island does not change** (`CLAUDE.md`: never restyle what ships). On the Mac the `CompactMiniGrid` struct and the `.scaleEffect(...)`/`.position(...)` lines that place it stay byte-identical; `IslandContainer` only gains a wrapper opacity on the `Group` around it. On Windows `#mini-grid` in `style.css`, `createMiniBot(t, 13)` and the `miniGrid.style.left/top` lines in `applyGeometry` stay byte-identical. The greeting adapts to them, never the reverse. A test pins their numbers on each app.
- **The tail.** After the island folds, the greeting canvas stays up for its last beat: the row gliding into the 2×2. Meanwhile the real `CompactMiniGrid` is hidden (opacity 0) and fades in over 0.25 s as the canvas fades out, together with the real cat. Mac: `AppState.greetingTail` and the `IslandContainer` changes. Windows: `greetingShown()` and `Greeting.onEnd`. The tail ends by itself 1.6 s after the fold, ends at once when the island leaves the compact mode, and never outlives the visible island (0 % CPU when hidden).
- **Units.** The greeting's space is 640×150 px with the island centred at x = 320. Times in the new fixtures are integer milliseconds (`t = tMs / 1000`); numbers compare within 1e-9; the new beat's times are in seconds **after `leave`** (the moment the island starts to fold: `GT.leave` = 4.9 s, or earlier when the pointer left).
- **Platform numbers (read from the code):** Mac grid: 12 pt cats (`MiniBotCanvasView` 20 × 0.6), 12 pt cells with a 4 pt gap, 28 × 28 frame, scaled by `miniGridScale = min(1, (height - 4) / 28)`, centred 40 pt in from the island's right edge and at `height / 2`. Windows grid: 13 px cats, 13 px cells with a 3 px gap, 29 × 29 box, centred 40 px in from the right edge and at `height / 2`. Both are 16 between cell centres. The prototype's row: Ø11 cats, 14 apart, the first 12 in from the right edge, 1 below the strip's middle.
- **Mac:** Swift 6, SwiftUI and AppKit, no third-party dependency; `project.yml` through XcodeGen (never edit the `.xcodeproj`); new Swift tests are `swiftc` programs under `scripts/test-cat-*.sh`; no `UserDefaults` suite in any test.
- **Windows/Linux:** TypeScript strict with `noUnusedLocals` and `noUnusedParameters`; install nothing (`npx --no-install` only).
- **Repo rules (`CLAUDE.md`):** commits are local and only as each task's commit step says; never push; nothing of Coucou's comes back; `main` is the App Store build. Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`, or `Claude Haiku 4.5` when a light task ran on it.
- **House rules for this session:** never launch, quit or replace the installed NotchMeow app; a Debug build for the owner's checkpoint is the main session's to start.

## Review Focus

The spec says what the beat is. It is silent on these, and each would bite a person first. Each line names its test.

1. **Collapse during the glide** (the pointer leaves, or the cat panel's "Collapse now", after the island has already started to fold). Expected: nothing restarts or jumps; an interrupt never moves `leave` later, and the beat is counted from the first `leave`. Tests: Task 6 "a greeting cut short ... never moves it later" (Windows); Task 3 "leaving early" (Mac contract); Task 5 keeps the Mac canvas's own `if tc.isInfinite || tc > t` rule.
2. **The user expands the island during the tail** (a click on the compact island, Esc, a settings shortcut). Expected: the tail ends at once, with no stuck canvas, no hidden grid and no hidden cat. Tests: Task 7 `greetingShown` (pure: expanded outside the greeting view, hidden, compact after the beat are all false); on the Mac `AppState.mode`'s `didSet` clears the flag for every mode change, checked by the build and by checkpoint step 3 (no unit test can compile `AppState` alone; the review must read it).
3. **A hook event during the tail** (a new session, an approval that expands the island, a session that ends and hides it). Expected: the real grid is rebuilt from the sessions at hand-over time, not at the fold; an alert that expands the island is case 2; a hide ends the tail. Tests: Task 7 `greetingShown`; Windows rebuilds the grid's children only when it is shown (`showGrid`), Task 7 Step 6, item 3.
4. **The pointer leaves mid-greeting (an early leave).** Expected: the row, the glide and the end follow it (the row 0.24 s after the fold starts, the grid 1.3 s, the end 1.6 s). Tests: Task 1 `miniGlide` follows `leave`, `miniGlideSamples` with leaves 1.0 and 3.0; Tasks 3 and 6 "leaving early".
5. **Small islands, other coats, reduced motion.** A strip shorter than 32 pt shrinks the grid (the Mac's `miniGridScale`), one too short to hold a cat draws none, and a head under 2 px is not drawn (Task 1 `MINI_MIN_D`, fixture cases H = 24 and H = 6). Every one of the 16 coats draws its session cats in the row, mid-glide and in the grid, in time and cut short (Task 4). Neither app honours reduced motion anywhere (`grep -ri "reduceMotion\|reduced-motion"` over `NotchBuddy/Sources`, `windows/src` and `design` finds nothing), so the glide plays like the rest of the greeting; see the open questions.
6. **The hand-over is the compact island.** Expected: the last frame is the island's grid to the pixel, and both pop-ins are finite and clamped. Tests: Task 4 (a pixel comparison on three islands, worst alpha difference 0) and Task 3 (`IslandRestingLayout` arithmetic plus a pin on `CompactMiniGrid`'s source); Task 6 (the pin on `#mini-grid` and `applyGeometry`).

---

## File Structure

No new Swift file, so `project.yml` and the `.xcodeproj` do not change. One new test file (`tests/cat/minis.test.mjs`).

| Path | Responsibility |
|---|---|
| `design/prototype/cat-core.js` | The contract gains `GT3`, `GREET_END`, `miniGlide`, `MINI_ROW`, `MINI_GRID`, `MINI_FROM`, `MINI_MIN_D` and `miniSlots`. `greetingPose`, `GT`, `GT2` and `GREET_LEN` stay as they are. |
| `scripts/gen-cat-fixtures.mjs` | One more part of `sequence-cases.json`: five new keys. |
| `tests/fixtures/cat/sequence-cases.json` | Generated. Gains `miniUnits`, `miniTimeline`, `miniGeometry`, `miniGlideSamples`, `miniSlotCases`; every old line unchanged. |
| `tests/cat/minis.test.mjs` | New. The contract's own checks, written from the compact island's real layout and not from the formula under test. |
| `design/prototype/notchmeow.html` | Draws the row, the glide and the grid from `CatCore.miniSlots`, in the greeting and at rest in the compact island. |
| `docs/CAT-CONTRACT.md`, `docs/superpowers/specs/2026-10-04-cats-in-app-design.md` | The amendment of 2026-10-06 (Task 0). |
| `NotchBuddy/Sources/App/CatGreeting.swift` | Port of the new contract: `GT3`, `greetEnd`, `Glide`, `miniGlide`, `Mini`, `miniSlots`, `Compact.miniScale`. |
| `NotchBuddy/Sources/App/CatGreetingRenderer.swift` | Draws the slots the way the real grid draws a cat. |
| `NotchBuddy/Sources/App/AppState.swift`, `IslandWindowController.swift`, `GreetingCanvasView.swift`, `IslandRootView.swift` | The tail: `greetingTail` is set when the island folds at the end of the greeting, ends with the beat, and ends at once on any other mode; the canvas is mounted as a sibling so that it survives the fold; the real grid waits. |
| `tests/CatGreetingTests.swift`, `tests/CatRendererTests.swift`, `scripts/test-cat-greeting.sh`, `scripts/test-cat-renderer.sh`, `scripts/render-cats.swift` | Fixture replay, the compact-grid pin, the pixel comparison, the contact sheet beats. |
| `windows/src/cat/greeting.ts`, `windows/src/island/island.ts`, `windows/scripts/cat-tests/greeting.test.mjs` | Port, drawing, `greetingShown`, `live`, `onEnd`, the island's use of them, and their tests. |

## Tasks and agents

Each task goes to the agent below, then to `nm-reviewer`; fix what the review finds before the next task. Per `CLAUDE.md` the lightest model that fits: Task 0 is docs, so Haiku; Tasks 1 to 4, 6 and 7 are multi-file with their code given, so Sonnet 5.5 medium; Task 5 is SwiftUI view identity across a mode change, which no unit test reaches, so Sonnet 5.5 high. If a step's expected output differs and the cause is not obvious, hand that task to `nm-implementer-deep`. The worktree session itself runs on Sonnet 5.5 medium (the tasks are mostly given in full; the main session sets model and effort after the chip starts, as `ARCHITECT.md` says).

| # | Task | Agent | Review |
|---|---|---|---|
| 0 | The spec amendment and the contract doc | `nm-implementer-light` | `nm-reviewer` |
| 1 | The contract: `GT3`, `miniGlide`, `miniSlots`, their fixtures and tests | `nm-implementer` | `nm-reviewer` |
| 2 | The prototype page draws the morph | `nm-implementer` | `nm-reviewer` |
| 3 | Mac: the port of the contract and its tests, with the compact-grid pin | `nm-implementer` | `nm-reviewer` |
| 4 | Mac: the renderer, the contact sheet and the pixel proof | `nm-implementer` | `nm-reviewer` |
| 5 | Mac: the tail (`AppState.greetingTail`, `IslandContainer`, the canvas) | `nm-implementer-deep` | `nm-reviewer` |
| 6 | Windows/Linux: the port, the drawing and the tests | `nm-implementer` | `nm-reviewer` |
| 7 | Windows/Linux: the tail (`greetingShown`, `live`, `onEnd`, the island) | `nm-implementer` | `nm-reviewer` |
| 9 | Mac: a new drag makes a left drop stale (parity with Windows' `fileLeft`) | `nm-implementer-light` | `nm-reviewer` |
| 8 | Owner checkpoint: the glide on both apps against the prototype | the main session and the owner | none |
| Final | Whole-branch review | `nm-reviewer-deep` | none |

**Controller brief** (what the main session sends the worktree session once its model is set):

> Run `docs/superpowers/plans/2026-10-06-greeting-row-to-grid.md` with `superpowers:subagent-driven-development`, task by task, on branch `a0c/greeting-grid`. Dispatch each task to the agent the plan names for it, then to `nm-reviewer`; fix what the review finds before the next task. Run Task 9 right after Task 7, then stop and report to the main session for the owner checkpoint (Task 8); after the checkpoint, dispatch `nm-reviewer-deep` over the whole branch. Commit only as the plan's commit steps say, never push, and never launch any NotchMeow build. Report the commits, the output of `node --test tests/cat/*.test.mjs`, `bash scripts/test-cat-contract.sh`, `node scripts/check-fixtures-additive.mjs <base>`, `bash scripts/test-cat-greeting.sh`, `bash scripts/test-cat-renderer.sh`, the Debug build line, and in `windows/` `npx --no-install tsc --noEmit` and the cat tests, plus anything you could not settle.

## Tasks

### Task 0: The spec amendment and the contract doc

**Agent:** `nm-implementer-light`. Docs only; the text is given.

**Files:**
- Modify: `docs/superpowers/specs/2026-10-04-cats-in-app-design.md` (one paragraph after **Greeting:**)
- Modify: `docs/CAT-CONTRACT.md` (two table rows and a new section before **The harness**)

**Interfaces:**
- Consumes: nothing.
- Produces: the written decision and the contract's description that Tasks 1 to 7 refer to (`GT3`, `GREET_END`, `miniGlide`, `miniSlots`, `MINI_ROW`, `MINI_GRID`, `MINI_FROM`, `MINI_MIN_D`, the five fixture keys).

- [ ] **Step 1: Add the spec's amendment paragraph**

**Edit `docs/superpowers/specs/2026-10-04-cats-in-app-design.md`**, find this text (it occurs exactly once):

```markdown
**Greeting:** on 2026-10-04 the owner chose the new greeting, a cat version of upstream's Greeting v2. The cat falls in with a landing squash, bounces, slides aside, pops up and does a quick paw wave, then slides back and ends like the old greeting. The total is still 5.74 s, with no upstream sound. It lives in the prototype as `GT2`/`greetPose2`, next to the old one for comparison. A-0 makes it *the* greeting in `cat-core.js` and `sequence-cases.json`. The old timeline is then dropped.
```

and replace it with:

```markdown
**Greeting:** on 2026-10-04 the owner chose the new greeting, a cat version of upstream's Greeting v2. The cat falls in with a landing squash, bounces, slides aside, pops up and does a quick paw wave, then slides back and ends like the old greeting. The total is still 5.74 s, with no upstream sound. It lives in the prototype as `GT2`/`greetPose2`, next to the old one for comparison. A-0 makes it *the* greeting in `cat-core.js` and `sequence-cases.json`. The old timeline is then dropped.

**Greeting, last beat (2026-10-06):** the owner decided that the greeting's last beat brings in the session cats as the prototype's **row of three** beside the main cat in the compact island, and that the row then **glides into the 2×2 grid** the shipping compact island shows (the Mac's `CompactMiniGrid`, the Windows app's `#mini-grid`), so the hand-over to the real island never jumps. A fourth cat pops into the empty cell as the others land, so the greeting ends on the four cats both apps always drew there. The shipping compact island does not change: the glide ends on its grid, proved on the Mac by a pixel comparison and on Windows by its pinned numbers. The beat is counted from the moment the island starts to fold, so an early leave plays it the same way: the row pops in 0.24 to 0.42 s after the fold starts, holds, glides 0.8 to 1.3 s after it, and the greeting ends 1.6 s after it. `GREET_LEN` stays 5.74 s, the greeting up to the settled row; the whole greeting, glide included, ends at `GREET_END`, 6.5 s. The greeting canvas now stays up in the compact island until the beat is over, so the glide is seen live and not only in the cat panel: the real cat and the real grid are hidden meanwhile, and fade in as the canvas fades out. The prototype's resting compact island shows the grid as well.
```

- [ ] **Step 2: Describe the new contract in `docs/CAT-CONTRACT.md`**

**Edit `docs/CAT-CONTRACT.md`**, find this text (it occurs exactly once):

```markdown
| Timelines | `greetingPose`, `GREET_LEN`, `GT`, `GT2`, `STREAKS`, `flightAt`, `FLIGHT_MS` |
```

and replace it with:

```markdown
| Timelines | `greetingPose`, `GREET_LEN`, `GT`, `GT2`, `STREAKS`, `flightAt`, `FLIGHT_MS`; the last beat (A-0c): `GT3`, `GREET_END`, `miniGlide`, `miniSlots`, `MINI_ROW`, `MINI_GRID`, `MINI_FROM`, `MINI_MIN_D` |
```

**Edit `docs/CAT-CONTRACT.md`**, find this text (it occurs exactly once):

```markdown
| `sequence-cases.json` | `greetingSamples` (the 5.74 s greeting, every 100 ms and at each beat), `greetingStreaks`, `flight`, `workClock` (the 5-minute zoomies rule), `sleep` (the 10-minute rule and what wakes the cat), `catch` (the four-step file catch, in both styles, refused or not), `zoomiesAndWake` (when the engine starts zoomies). |
```

and replace it with:

```markdown
| `sequence-cases.json` | `greetingSamples` (the 5.74 s greeting, every 100 ms and at each beat), `greetingStreaks`, `flight`, `workClock` (the 5-minute zoomies rule), `sleep` (the 10-minute rule and what wakes the cat), `catch` (the four-step file catch, in both styles, refused or not), `zoomiesAndWake` (when the engine starts zoomies); and, added in A-0c, `miniUnits`, `miniTimeline`, `miniGeometry`, `miniGlideSamples` and `miniSlotCases` (the greeting's last beat: the row of session cats gliding into the grid). |
```

**Edit `docs/CAT-CONTRACT.md`**, find this text (it occurs exactly once):

```markdown
`flatFill` is exactly `!layout(...).full`, so an app that already branches on `L.full` (both app plans do) needs no new function: only the constants (`FLAT_FILL`: the head, ear, ruff and crown numbers are the ones both plan drafts already hard-code, the point mask is not, see Decisions to know about) and a loop over `detailLevels` that checks `!full` against `flatFill`. Everything else (markings, eyes, blush, the state tint) is drawn as in the full cat. `flatFillColors(preset)` returns the flat head, ear, ruff and point colours as `[r, g, b]` in 0 to 255, unrounded (`ruff` is `null` without a ruff, and `point` unless the coat is `point`). `geometry-cases.json` holds `flatFill` (the constants), `detailLevels` (head widths and overrides to levels) and `flatColors` (every cat's flat colours, the point mask's included). The mix is per channel, on the 0 to 255 values.

## The harness
```

and replace it with:

```markdown
`flatFill` is exactly `!layout(...).full`, so an app that already branches on `L.full` (both app plans do) needs no new function: only the constants (`FLAT_FILL`: the head, ear, ruff and crown numbers are the ones both plan drafts already hard-code, the point mask is not, see Decisions to know about) and a loop over `detailLevels` that checks `!full` against `flatFill`. Everything else (markings, eyes, blush, the state tint) is drawn as in the full cat. `flatFillColors(preset)` returns the flat head, ear, ruff and point colours as `[r, g, b]` in 0 to 255, unrounded (`ruff` is `null` without a ruff, and `point` unless the coat is `point`). `geometry-cases.json` holds `flatFill` (the constants), `detailLevels` (head widths and overrides to levels) and `flatColors` (every cat's flat colours, the point mask's included). The mix is per channel, on the 0 to 255 values.

## The greeting's last beat (A-0c)

Added on 2026-10-06 (the owner's decision, in the cat spec's greeting paragraphs). The greeting used to end with the session cats popping in as the prototype's row of three on the page and as the 2×2 grid in the apps. It now ends on the row and then glides into the grid, so the hand-over to the real compact island never jumps. Everything is new keys, constants and functions: `greetingPose` and every old fixture line are untouched.

- **Timing.** All times are seconds after `leave`, the moment the island starts to fold (`GT.leave`, 4.9 s, or earlier when the pointer left). The row pops in 0.24 to 0.42 s after it (`greetingPose().minis`, as before), holds, glides 0.8 to 1.3 s after it (`GT3.glide0`, `GT3.glide1`), a fourth cat pops in from 1.0 s (`GT3.four0`), and the greeting ends 1.6 s after it (`GT3.end`). `GREET_LEN` stays 5.74 s, the old end, so the fixture line and the app tests that pin it do not move. `GREET_END` = `GT.leave + GT3.end` = 6.5 s is where the whole greeting ends.
- **`miniGlide(t, leave = GT.leave)`** returns `{grid, four}`: `grid` is the row becoming the grid (0 to 1, eased in and out) and `four` is the fourth cat's pop (0 to 1, with the same little overshoot as `minis`).
- **`miniSlots(minis, g, {W, H, d})`** returns the four cats in the order of the grid's cells (top left, top right, bottom left, bottom right) as `{x, y, d}`: centre and head width in px in the 640×150 space, the island centred at x = 320. `minis` is the pose's pop-in, `g` the glide, `W` and `H` the compact island (288×32 by default; on the Mac 344 or so by the notch's height), `d` the grid cat's head width (`MINI_GRID.d`, the Mac's 12; the Windows app passes 13). `d` is 0 for a cat that is not there and already holds the pop and the strip's scale, so an app draws every slot with `d > 0` and nothing else. A head narrower than `MINI_MIN_D` (2 px) counts as not there.
- **Row to grid.** The row is the prototype's: Ø11 cats, 14 px apart, the first 12 px in from the island's right edge and 1 px below the strip's middle (`MINI_ROW`). The grid is the compact island's: cells 16 px between centres, its centre 40 px in from the right edge and level with the strip's middle (`MINI_GRID`); the Mac's 12 pt cells with a 4 pt gap and the Windows app's 13 px cells with a 3 px gap are both 16 apart. The row's three cats glide to the cells top left, top right and bottom right (`MINI_FROM`: cell to row cat, 0 being the right-most), which keeps their paths apart (never closer than 0.88 of a head width), and the fourth pops into the bottom left. A strip shorter than 32 px shrinks the whole thing by `min(1, (H - 4) / 28)`, the Mac's `miniGridScale`.
- **What proves "equal to the compact island".** Not the contract alone, which is only the greeting's side. Each app tests its own compact island's numbers against the glide's last frame: the Mac reads `IslandRestingLayout`, pins the literals of `CompactMiniGrid`'s source and draws the last frame next to a grid laid out the way the view lays it out (a pixel test); the Windows app pins `#mini-grid`'s CSS and `applyGeometry` and compares the slots with the cells.
- **Fixtures.** `sequence-cases.json` gains `miniUnits`, `miniTimeline`, `miniGeometry`, `miniGlideSamples` (`miniGlide` for the timeline's own leave and two early ones) and `miniSlotCases` (`miniSlots` on five islands: the contract's, a Mac with a notch, a Mac without one, the Windows app's 13 px cats and a strip too short to hold a cat). Nothing existing changed: `node scripts/check-fixtures-additive.mjs` proves it.

## The harness
```

- [ ] **Step 3: Check the two docs**

Run: `grep -c "2026-10-06" docs/superpowers/specs/2026-10-04-cats-in-app-design.md && grep -c "A-0c" docs/CAT-CONTRACT.md`
Expected: `1` and `3`.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-10-04-cats-in-app-design.md docs/CAT-CONTRACT.md
git commit -q -m "docs(cat): the greeting's last beat, the row of session cats gliding into the grid" -m "Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

### Task 1: The contract: `GT3`, `miniGlide`, `miniSlots`, their fixtures and tests

**Agent:** `nm-implementer`.

**Files:**
- Create: `tests/cat/minis.test.mjs`
- Modify: `design/prototype/cat-core.js` (the "Timelines" section and its `Object.assign`)
- Modify: `scripts/gen-cat-fixtures.mjs` (one more part of `sequence-cases.json`)
- Modify (generated, never by hand): `tests/fixtures/cat/sequence-cases.json`

**Interfaces:**
- Consumes: `GT`, `COMPACT`, `NOTCH`, `EZ`, `seg`, `lerp` already in `cat-core.js`; `core.greetingPose(t).minis`.
- Produces (every later task ports these, exactly):
  - `GT3 = {glide0: .8, glide1: 1.3, four0: 1, end: 1.6}`, seconds after `leave`; `GREET_END = GT.leave + GT3.end` (6.5).
  - `miniGlide(t, leave = GT.leave) -> {grid, four}`.
  - `MINI_ROW = {d: 11, step: 14, inset: 12, dy: 1}`, `MINI_GRID = {step: 16, inset: 40, d: 12}`, `MINI_FROM = [2, 1, null, 0]`, `MINI_MIN_D = 2`.
  - `miniSlots(minis, g, {W = COMPACT, H = NOTCH.H, d = MINI_GRID.d} = {}) -> [{x, y, d} x 4]`, in the order of the grid's cells (top left, top right, bottom left, bottom right).
  - `sequence-cases.json` keys: `miniUnits`, `miniTimeline` (`glide0`, `glide1`, `four0`, `end`, `greetEnd`), `miniGeometry` (`row`, `grid`, `from`, `minD`), `miniGlideSamples` (`{leave, tMs, glide}`), `miniSlotCases` (`{name, W, H, d, tMs, minis, grid, four, slots}`).

- [ ] **Step 1: Write the failing contract tests**

The tests build the compact island's grid the way the views write it (`realGrid`: a 28 × 28 frame of 12 pt cells 4 apart, scaled about its middle, centred 40 in from the right edge) and not the way `miniSlots` writes it, so they check the formula against the island.

**Create `tests/cat/minis.test.mjs`** with exactly this content:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { compare } from '../../scripts/gen-cat-fixtures.mjs';

const require = createRequire(import.meta.url);
const core = require('../../design/prototype/cat-core.js');
const seq = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/sequence-cases.json', import.meta.url), 'utf8'));
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} is not within ${eps} of ${b}`);
const ROW = { grid: 0, four: 0 }, GRID = { grid: 1, four: 1 };

/**
 * What the compact island really lays out, written the way the views write it and not the way the contract does: a 28 x 28 frame with two
 * columns of 12 pt cells 4 apart, scaled about its centre by min(1, (H - 4) / 28) (IslandRootView.swift: CompactMiniGrid, miniGridScale)
 * and centred 40 in from the island's right edge, level with the middle of the strip. On Windows the cells are 13 px and the gap 3
 * (style.css: #mini-grid), which is the same 16 between centres. Returns the four cells' centres in the 640-wide canvas, whose centre is the island's.
 */
function realGrid(W, H, cell, gap) {
  const k = Math.min(1, Math.max(0, H - 4) / 28), frame = 2 * cell + gap;
  return [[0, 0], [1, 0], [0, 1], [1, 1]].map(([c, r]) => ({
    x: 320 - W / 2 + (W - 40) + (c * (cell + gap) + cell / 2 - frame / 2) * k,
    y: H / 2 + (r * (cell + gap) + cell / 2 - frame / 2) * k,
    d: cell * k,
  }));
}

test('GREET_LEN stays 5.74 s; the greeting as a whole now ends at GREET_END, 1.6 s after the island starts to fold', () => {
  near(core.GREET_LEN, 5.74);
  assert.deepEqual(core.GT3, { glide0: 0.8, glide1: 1.3, four0: 1, end: 1.6 });
  near(core.GREET_END, core.GT.leave + 1.6);
  near(core.GREET_END, 6.5);
  assert.ok(core.GREET_END > core.GREET_LEN);
  assert.ok(core.GT3.glide0 > 0.42, 'the row has finished popping in (collapsePose: 0.24 to 0.42 s after leave) before it glides');
  assert.ok(core.GT3.glide1 < core.GT3.end, 'and the grid holds for a moment before the hand-over');
  assert.ok(core.GT3.four0 > core.GT3.glide0 && core.GT3.four0 < core.GT3.glide1, 'the fourth cat pops in while the others land');
});

test('the glide: nothing before it, the grid after it, and it follows `leave`', () => {
  const L = core.GT.leave;
  const is = (g, want) => { near(g.grid, want.grid); near(g.four, want.four); };   // EZ.back(0) is -2.2e-16, as `minis` is before the row pops in
  is(core.miniGlide(0), ROW);
  is(core.miniGlide(L + core.GT3.glide0), ROW);
  is(core.miniGlide(L + core.GT3.glide1), GRID);
  is(core.miniGlide(1e6), GRID);
  is(core.miniGlide(-5), ROW);
  let prev = 0, top = 0;
  for (let i = 0; i <= 4000; i++) {
    const g = core.miniGlide(L + i / 1000), t = L + i / 1000;
    assert.ok(g.grid >= prev - 1e-12 && g.grid <= 1, `the glide is monotone and never past the grid (${g.grid} at ${t})`);
    assert.ok(g.four >= -1e-12 && g.four < 1.11, `the fourth cat's pop stays between 0 and 1.1 (${g.four} at ${t})`);
    prev = g.grid; top = Math.max(top, g.four);
  }
  assert.ok(top > 1.05, `the fourth cat pops with a little overshoot, like the row (${top})`);
  for (const leave of [0.3, 1.0, 2.5, 4.9]) for (const o of [0, 0.5, 0.9, 1.1, 1.3, 2]) {
    const a = core.miniGlide(leave + o, leave), b = core.miniGlide(L + o);
    near(a.grid, b.grid); near(a.four, b.four);
  }
});

test('the row: three cats, the prototype\'s numbers, and no fourth cat yet', () => {
  const s = core.miniSlots(1, ROW);
  assert.equal(s.length, 4);
  // The grid's cells run top left, top right, bottom left, bottom right; the row cats come from MINI_FROM = [2, 1, none, 0].
  const right = 320 + core.COMPACT / 2;
  for (const [cell, from] of [[0, 2], [1, 1], [3, 0]]) {
    near(s[cell].x, right - (12 + 14 * from)); near(s[cell].y, 17); near(s[cell].d, 11);
  }
  assert.equal(s[2].d, 0, 'the bottom left is empty in the row');
  assert.deepEqual(core.miniSlots(0, ROW).map(c => c.d), [0, 0, 0, 0], 'before the pop-in nothing is drawn');
  near(core.miniSlots(1, ROW)[0].x, 320 + core.COMPACT / 2 - 40, 1e-9);   // the row's left-most cat sits where the grid's centre is
});

test('the end of the glide is the compact island\'s real grid, on the Mac, on the Windows app, on a notch and without one', () => {
  for (const [W, H, d, cell, gap] of [[288, 32, 12, 12, 4], [344, 38, 12, 12, 4], [344, 32, 12, 12, 4], [240, 24, 12, 12, 4], [288, 32, 13, 13, 3], [300, 20, 13, 13, 3]]) {
    const want = realGrid(W, H, cell, gap), got = core.miniSlots(1, GRID, { W, H, d });
    got.forEach((s, i) => { near(s.x, want[i].x); near(s.y, want[i].y); near(s.d, want[i].d); });
  }
});

test('the glide never has two cats on top of each other, and every cat stays inside the strip it is drawn in', () => {
  for (const { W, H, d } of [{ W: 288, H: 32, d: 12 }, { W: 344, H: 38, d: 12 }, { W: 288, H: 32, d: 13 }]) {
    let tightest = Infinity;
    for (let i = 0; i <= 1000; i++) {
      const g = { grid: core.EZ.inOut(i / 1000), four: i / 1000 > 0.65 ? 1 : 0 }, s = core.miniSlots(1, g, { W, H, d });
      for (let a = 0; a < 4; a++) for (let b = a + 1; b < 4; b++) if (s[a].d && s[b].d) tightest = Math.min(tightest, Math.hypot(s[a].x - s[b].x, s[a].y - s[b].y) / ((s[a].d + s[b].d) / 2));
      for (const c of s) if (c.d) assert.ok(c.y - c.d / 2 >= 0 && c.y + c.d / 2 <= Math.max(H, 32), `a cat leaves the strip at ${i / 1000}: ${JSON.stringify(c)}`);
    }
    assert.ok(tightest > 0.85, `two cats come within ${tightest.toFixed(3)} of a head width of each other`);
  }
});

test('a short strip shrinks the cats as the Mac\'s miniGridScale does, and a cat under MINI_MIN_D is not drawn', () => {
  near(core.miniSlots(1, GRID, { H: 24 })[0].d, 12 * 20 / 28);
  near(core.miniSlots(1, GRID, { H: 38 })[0].d, 12);
  assert.deepEqual(core.miniSlots(1, GRID, { H: 4 }).map(c => c.d), [0, 0, 0, 0]);
  assert.deepEqual(core.miniSlots(1, GRID, { H: 0 }).map(c => c.d), [0, 0, 0, 0]);
  assert.deepEqual(core.miniSlots(1, GRID, { H: -10 }).map(c => c.d), [0, 0, 0, 0]);
  assert.equal(core.MINI_MIN_D, 2);
  for (const m of [0.001, 0.1, 0.17, 0.18]) for (const c of core.miniSlots(m, ROW)) assert.ok(c.d === 0 || c.d >= 2, `d = ${c.d} at a pop of ${m}`);
});

test('every slot is finite whatever time, leave or island it is asked for', () => {
  for (const t of [-5, 0, 3, 5.3, 6, 6.5, 100, 1e6]) for (const leave of [0, 1, 4.9, 50]) for (const H of [0, 6, 24, 32, 200]) {
    const g = core.miniGlide(t, leave);
    for (const s of core.miniSlots(core.EZ.back(core.seg(t, leave + 0.24, leave + 0.42)), g, { W: 288, H, d: 12 })) for (const [k, v] of Object.entries(s)) assert.ok(Number.isFinite(v), `${k} at t ${t}, leave ${leave}, H ${H}`);
  }
});

test('sequence-cases.json: the glide timeline, its samples and the slot cases replay from the module', () => {
  assert.deepEqual(seq.miniTimeline, { ...core.GT3, greetEnd: core.GREET_END });
  assert.deepEqual(seq.miniGeometry, { row: core.MINI_ROW, grid: core.MINI_GRID, from: core.MINI_FROM, minD: core.MINI_MIN_D });
  assert.ok(seq.miniGlideSamples.length >= 40 && seq.miniSlotCases.length >= 40);
  for (const c of seq.miniGlideSamples) { const d = compare(core.miniGlide(c.tMs / 1000, c.leave), c.glide); assert.deepEqual(d, [], `leave ${c.leave}, ${c.tMs} ms`); }
  for (const c of seq.miniSlotCases) {
    const d = compare(core.miniSlots(c.minis, { grid: c.grid, four: c.four }, { W: c.W, H: c.H, d: c.d }), c.slots);
    assert.deepEqual(d, [], `${c.name}, ${c.tMs} ms`);
  }
  const leaves = new Set(seq.miniGlideSamples.map(c => c.leave));
  assert.deepEqual([...leaves], [core.GT.leave, 1, 3], 'the timeline\'s own leave and two early ones');
  assert.ok(seq.miniSlotCases.some(c => c.H === 24) && seq.miniSlotCases.some(c => c.d === 13) && seq.miniSlotCases.some(c => c.H === 6), 'a short strip, the Windows cat and a strip too short for a cat are covered');
});

test('the greeting\'s existing fixtures are untouched: no pose gains a key, no length changes', () => {
  assert.deepEqual(Object.keys(core.greetingPose(5.5)), ['iw', 'ih', 'hb', 'x', 'y', 'sx', 'sy', 'tilt', 'eye', 'lookX', 'lookY', 'handL', 'handR', 'wave', 'open', 'badge', 'tint', 'halo', 'haloBlue', 'header', 'card', 'fx', 'minis']);
  assert.equal(seq.greetingLengthS, core.GREET_LEN);
  assert.equal(seq.greetingSamples.at(-1).tMs, 5800);
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test tests/cat/minis.test.mjs 2>&1 | grep -E "^(not ok|ok) "`
Expected: eight `not ok` lines (`core.GT3`, `core.miniGlide` and `core.miniSlots` do not exist) and one `ok`, the last test ("the greeting's existing fixtures are untouched").

- [ ] **Step 3: Add the contract to `cat-core.js`**

The block goes right after `greetingPose`, and the new names join the `Object.assign` that exports the timelines.

**Edit `design/prototype/cat-core.js`**, find this text (it occurs exactly once):

```js
const greetingPose=t=>t<GT.leave?fallPose(t,islandBase(t)):collapsePose(t);

/** A dropped file arcs into the cat's mouth over this long (ms). k is 0…1 along the flight. */
```

and replace it with:

```js
const greetingPose=t=>t<GT.leave?fallPose(t,islandBase(t)):collapsePose(t);

// ── The greeting's last beat: the session cats ───────────────────────────────
// Once the island has folded, the session cats pop in as a ROW of three (the prototype's), hold a moment, then glide into the 2×2 grid
// the compact island really shows; a fourth cat pops into the empty cell as they land. Every time is in seconds after `leave`, the moment
// the island starts to fold (GT.leave, or earlier when the pointer left), so the beat follows an early leave. GREET_LEN stays what it was
// (5.74 s, up to the settled row); GREET_END is where the whole greeting, glide included, ends.
const GT3={glide0:.8,glide1:1.3,four0:1,end:1.6};
const GREET_END=GT.leave+GT3.end;
/** The glide's two progress values: `grid` is the row becoming the grid, 0…1; `four` is the fourth cat's pop, 0…1 and a little over (EZ.back), like `minis`. */
const miniGlide=(t,leave=GT.leave)=>({grid:EZ.inOut(seg(t,leave+GT3.glide0,leave+GT3.glide1)),four:EZ.back(seg(t,leave+GT3.four0,leave+GT3.glide1))});
/** The prototype's row: head width, spacing and the first cat's inset from the island's right edge (px), and how far it sits below the strip's middle. */
const MINI_ROW={d:11,step:14,inset:12,dy:1};
/** The compact island's grid: cells `step` apart (the Mac's 12 pt cells and 4 pt gap, the Windows app's 13 px cells and 3 px gap), its centre `inset` px in from the island's right edge and level with the strip's middle, and the Mac's cat head width (an app with another size passes it as `d`). */
const MINI_GRID={step:16,inset:40,d:12};
/** Grid cell (top left, top right, bottom left, bottom right) to the row cat that glides into it, 0 being the row's right-most. The bottom left has none: the fourth cat pops in there. */
const MINI_FROM=[2,1,null,0];
/** A session cat narrower than this (px) is not drawn: it is the first frames of a pop, or a strip too short to hold it. */
const MINI_MIN_D=2;
/**
 * The four session cats, in the order of the grid's cells, as {x, y, d}: centre and head width in px in the greeting's 640×150 space, where the
 * island is centred at x = 320. `d` is 0 for a cat that is not there (yet), and already holds the pop and the strip's scale, so an app draws
 * every slot with d > 0 and nothing else. `minis` is the row's pop-in (greetingPose().minis), `g` is miniGlide(t, leave), `opts` the compact
 * island: W and H in px, and `d`, the head width of one grid cat in the app (the Mac's 12, the Windows app's 13). A strip shorter than 32 px
 * shrinks the whole thing the way the Mac's miniGridScale does: min(1, (H - 4) / 28).
 */
function miniSlots(minis,g,{W=COMPACT,H=NOTCH.H,d=MINI_GRID.d}={}){
 const k=Math.min(1,Math.max(0,H-4)/28),right=320+W/2,gx=right-MINI_GRID.inset,gy=H/2,s=MINI_GRID.step/2*k;
 return MINI_FROM.map((from,i)=>{
  const x1=gx+(i%2?s:-s),y1=gy+(i<2?-s:s),row=from!==null,
   x=row?lerp(right-(MINI_ROW.inset+MINI_ROW.step*from)*k,x1,g.grid):x1,y=row?lerp(gy+MINI_ROW.dy*k,y1,g.grid):y1,
   dd=(row?lerp(MINI_ROW.d,d,g.grid)*minis:d*g.four)*k;
  return{x,y,d:dd<MINI_MIN_D?0:dd}})}

/** A dropped file arcs into the cat's mouth over this long (ms). k is 0…1 along the flight. */
```

**Edit `design/prototype/cat-core.js`**, find this text (it occurs exactly once):

```js
Object.assign(api,{ZOOM_AFTER_MS,workClockStep,zoomiesOnFinish,SLEEP_AFTER_MS,sleepDelay,WAKE_EVENTS,wakes,SEARCH_TOOLS,isSearchTool,toolState,NOTCH,COMPACT,GT,GT2,GREET_LEN,STREAKS,streakTime,islandBase,greetingPose,FLIGHT_MS,flightAt});
```

and replace it with:

```js
Object.assign(api,{ZOOM_AFTER_MS,workClockStep,zoomiesOnFinish,SLEEP_AFTER_MS,sleepDelay,WAKE_EVENTS,wakes,SEARCH_TOOLS,isSearchTool,toolState,NOTCH,COMPACT,GT,GT2,GREET_LEN,STREAKS,streakTime,islandBase,greetingPose,GT3,GREET_END,miniGlide,MINI_ROW,MINI_GRID,MINI_FROM,MINI_MIN_D,miniSlots,FLIGHT_MS,flightAt});
```

- [ ] **Step 4: Run the tests again**

Run: `node --test tests/cat/minis.test.mjs 2>&1 | grep -E "^(not ok|ok) "`
Expected: eight `ok`, and one `not ok`: "sequence-cases.json: the glide timeline, its samples and the slot cases replay from the module", because the fixtures are not generated yet.

- [ ] **Step 5: Add the fixtures to the generator**

The new part is appended to `sequence-cases.json` as new keys only.

**Edit `scripts/gen-cat-fixtures.mjs`**, find this text (it occurs exactly once):

```js
  };
};

// @@BUILDERS: each task adds `FILES['name.json'] = () => ({ ... })` immediately above this line.
```

and replace it with:

```js
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

// @@BUILDERS: each task adds `FILES['name.json'] = () => ({ ... })` immediately above this line.
```

- [ ] **Step 6: Regenerate the fixtures and prove they only grew**

Run:
```bash
node scripts/gen-cat-fixtures.mjs
node scripts/check-fixtures-additive.mjs HEAD
git diff --numstat -- tests/fixtures
```
Expected: `wrote 8 fixture files to tests/fixtures/cat`; the checker prints `✓ fixtures changed only by addition since HEAD`, with `sequence-cases.json: 137 old lines unchanged, 94 lines added (new keys: miniUnits, miniTimeline, miniGeometry, miniGlideSamples, miniSlotCases)` and no other file changed; the numstat shows one file, `94	0	tests/fixtures/cat/sequence-cases.json` (the old line count may differ if other work landed; the point is zero deletions and only that file).

- [ ] **Step 7: Run the whole contract**

Run:
```bash
node --test tests/cat/*.test.mjs 2>&1 | tail -8
bash scripts/test-cat-contract.sh 2>&1 | tail -4
```
Expected: `# tests 116`, `# pass 116`, `# fail 0` (the 107 that were there plus the 9 new ones); `✓ 8 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

- [ ] **Step 8: Commit**

```bash
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/fixtures/cat/sequence-cases.json tests/cat/minis.test.mjs
git commit -q -m "feat(cat): the greeting's last beat in the contract, the row of session cats gliding into the compact island's grid" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 2: The prototype page draws the morph

**Agent:** `nm-implementer`.

**Files:**
- Modify: `design/prototype/notchmeow.html`

**Interfaces:**
- Consumes: `CatCore.GREET_END`, `CatCore.miniGlide`, `CatCore.miniSlots`, `CatCore.COMPACT` (Task 1).
- Produces: the visual source of truth for the glide, which Tasks 4, 6 and 8 compare against. `drawSessionMinis(ctx, cx, k, slots, alpha)` draws the four slots; the greeting, the "Greeting" panel (Replay, Loop, Slow ×0.5) and the compact island at rest all draw through it, so the greeting's last frame and the island at rest are the same four cats in the same places.

The page's session cats are `SESS[0..2]` and the subagent kitten `SESS[0].kits[0]`. Slot order is the grid's cells: top left `SESS[2]`, top right `SESS[1]`, bottom left the kitten (it pops in), bottom right `SESS[0]`, which is where the row's three glide to (`MINI_FROM`).

- [ ] **Step 1: Edit the page**

**Edit `design/prototype/notchmeow.html`**, find this text (it occurs exactly once):

```html
<p class="tag">The launch greeting, 5.74 s: a cat version of upstream's Greeting v2. The cat falls in with a landing squash, bounces, slides aside, pops up for a quick paw wave, then slides back and settles with the badge and tint. The timeline is defined in cat-core.js and pinned by sequence-cases.json, which the apps are tested against.</p>
<div class="row" id="gcRow"><span class="h">Cat</span></div>
<div class="cmp">
<figure><canvas id="cvG" aria-label="Launch greeting"></canvas><figcaption><b>Greeting</b> · 5.74 s</figcaption></figure>
```

and replace it with:

```html
<p class="tag">The launch greeting, 6.5 s: a cat version of upstream's Greeting v2. The cat falls in with a landing squash, bounces, slides aside, pops up for a quick paw wave, then slides back and settles with the badge and tint. Once the island has folded, the session cats pop in as a row of three, hold a moment and glide into the 2×2 grid the compact island shows, where a fourth cat pops in. The timeline is defined in cat-core.js and pinned by sequence-cases.json, which the apps are tested against.</p>
<div class="row" id="gcRow"><span class="h">Cat</span></div>
<div class="cmp">
<figure><canvas id="cvG" aria-label="Launch greeting"></canvas><figcaption><b>Greeting</b> · 6.5 s</figcaption></figure>
```

**Edit `design/prototype/notchmeow.html`**, find this text (it occurs exactly once):

```html
<li>Slides back and settles</li>
```

and replace it with:

```html
<li>Slides back and settles</li>
<li>The session cats pop in as a row of three</li>
<li>The row glides into the 2×2 grid, and a fourth cat joins</li>
```

**Edit `design/prototype/notchmeow.html`**, find this text (it occurs exactly once):

```html
const {TAU,EZ,lerp,clamp,seg,hex,rng,COL,STATES,PRESETS,MORE,kittenOf,MOMO_WHITE,CatEngine,PROFILES,PERSONAS,TRAITS,COMPACT,GT,STREAKS,GREET_LEN,FLIGHT_MS}=CatCore;
```

and replace it with:

```html
const {TAU,EZ,lerp,clamp,seg,hex,rng,COL,STATES,PRESETS,MORE,kittenOf,MOMO_WHITE,CatEngine,PROFILES,PERSONAS,TRAITS,COMPACT,GT,STREAKS,GREET_LEN,GREET_END,FLIGHT_MS}=CatCore;
```

**Edit `design/prototype/notchmeow.html`**, find this text (it occurs exactly once):

```html
function drawSessionMinis(ctx,x1,k,alpha){if(alpha<=.01)return;ctx.save();ctx.globalAlpha=alpha;SESS.forEach((S,i)=>{drawCat(ctx,S.e,x1-(12+i*14)*k,17*k,11*k,{tint:TINTON,badge:false,collar:collarOf(S.col)})});ctx.restore()}
```

and replace it with:

```html
// The session cats of the compact island, in the order of the grid's cells (top left, top right, bottom left, bottom right): the row's three, the
// left-most first, then the subagent kitten that pops into the empty cell. CatCore.miniSlots places them (a row, the glide, the grid the apps show).
const SLOT_WHO=()=>[SESS[2],SESS[1],{e:SESS[0].kits[0],col:SESS[0].col},SESS[0]];
function drawSessionMinis(ctx,cx,k,slots,alpha){if(alpha<=.01)return;const who=SLOT_WHO();ctx.save();ctx.globalAlpha=alpha;
 slots.forEach((s,i)=>{if(s.d<=0)return;drawCat(ctx,who[i].e,cx+(s.x-320)*k,s.y*k,s.d*k,{tint:TINTON,badge:false,collar:collarOf(who[i].col)})});ctx.restore()}
```

**Edit `design/prototype/notchmeow.html`**, find this text (it occurs exactly once):

```html
 if(ISL.greet>=0){const t=(ms()-ISL.greet)/1000;if(t>GREET_LEN){ISL.greet=-1;ISL.exp=ISL.from=ISL.to=0}else{drawGreeting(ctx,t,cx,k,greetEng);return}}
```

and replace it with:

```html
 if(ISL.greet>=0){const t=(ms()-ISL.greet)/1000;if(t>GREET_END){ISL.greet=-1;ISL.exp=ISL.from=ISL.to=0}else{drawGreeting(ctx,t,cx,k,greetEng);return}}
```

**Edit `design/prototype/notchmeow.html`**, find this text (it occurs exactly once):

```html
 drawSessionMinis(ctx,x0+iw,k,1-seg(e,0,.25));
```

and replace it with:

```html
 drawSessionMinis(ctx,cx,k,CatCore.miniSlots(1,{grid:1,four:1},{W:iw/k,H:32}),1-seg(e,0,.25));
```

**Edit `design/prototype/notchmeow.html`**, find this text (it occurs exactly once):

```html
 drawSessionMinis(ctx,cx+iw/2,k,P.minis);ctx.restore()}
```

and replace it with:

```html
 drawSessionMinis(ctx,cx,k,CatCore.miniSlots(P.minis,CatCore.miniGlide(t),{W:COMPACT,H:32}),1);ctx.restore()}
```

**Edit `design/prototype/notchmeow.html`**, find this text (it occurs exactly once):

```html
 if(GC.loop&&GC.t>GREET_LEN+.8)gcReplay();
 const t=Math.min(GC.t,GREET_LEN);GC.e.update(dt);
```

and replace it with:

```html
 if(GC.loop&&GC.t>GREET_END+.8)gcReplay();
 const t=Math.min(GC.t,GREET_END);GC.e.update(dt);
```

- [ ] **Step 2: Check the page in the Browser pane**

Local files cannot be driven, so serve the folder on localhost (a local dev host):

```bash
cd design/prototype && python3 -m http.server 8765 --bind 127.0.0.1
```

Open `http://127.0.0.1:8765/notchmeow.html` in the Browser pane (`navigate`), then run this in the page (`javascript_exec`). It freezes the page's own loops and draws six strips of the compact island, zoomed 2.5 times, at the beats of the last beat:

```js
(() => {
  window.requestAnimationFrame = () => 0;
  document.querySelectorAll('.__strip').forEach(e => e.remove());
  const times = [5.4, 5.75, 5.9, 6.0, 6.1, 6.5];
  const wrap = document.createElement('div'); wrap.className = '__strip';
  wrap.style.cssText = 'position:fixed;left:0;top:0;width:800px;height:600px;background:#222;z-index:99999';
  times.forEach((t, i) => {
    const c = document.createElement('canvas'); c.width = 800; c.height = 100; c.style.cssText = `position:absolute;left:0;top:${i * 100}px;width:800px;height:100px`;
    wrap.appendChild(c);
    const ctx = c.getContext('2d'); ctx.save(); ctx.scale(2.5, 2.5); ctx.translate(-160, 0);
    drawGreeting(ctx, t, 320, 1, GC.e); ctx.restore();
    ctx.fillStyle = '#9ab'; ctx.font = '12px sans-serif'; ctx.fillText(t.toFixed(2) + ' s', 8, 14);
  });
  document.body.appendChild(wrap); return 'ok';
})()
```

Then take a screenshot. Expected: the main cat on the left of every strip; at 5.40 and 5.75 s a **row of three** at the right end (a tabby, a black-and-white cat, a tabby); at 5.90 s the three part and move left and down; at 6.00 s a 2 × 2 is forming; at 6.10 and 6.50 s a **2 × 2 grid** with the fourth, smaller cat in the bottom left. Then reload the page and scroll to "In the notch": the compact island at rest shows the same 2 × 2 grid at its right end, and clicking the island still expands it. Judge the console only for messages after a `console.log('MARK')` you run before the reload: the Browser pane keeps messages per origin, and a message from an earlier load of a page opened in a background tab is stale. Stop the server when done.

- [ ] **Step 3: Commit**

```bash
git add design/prototype/notchmeow.html
git commit -q -m "feat(prototype): the session cats glide from the row into the compact island's grid, and the island rests on the grid" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 3: Mac: the port of the contract and its tests, with the compact-grid pin

**Agent:** `nm-implementer`.

**Files:**
- Modify: `tests/CatGreetingTests.swift`
- Modify: `scripts/test-cat-greeting.sh` (adds `IslandScreenGeometry.swift`, which is Foundation only, to the compile list)
- Modify: `NotchBuddy/Sources/App/CatGreeting.swift`

**Interfaces:**
- Consumes: Task 1's fixture keys (`miniTimeline`, `miniGeometry`, `miniGlideSamples`, `miniSlotCases`); `IslandRestingLayout` (`IslandScreenGeometry.swift`: `miniGridScale`, `miniGridCenterX`, `botCenterY`), the compact view's own arithmetic; the source of `CompactMiniGrid` in `IslandRootView.swift`, read as text.
- Produces (Tasks 4 and 5 use these):
  - `CatGreeting.GT3` (`glide0`, `glide1`, `four0`, `end`), `CatGreeting.greetEnd` (6.5).
  - `struct Glide { grid, four }`; `static func miniGlide(_ t: Double, leave: Double = GT.leave) -> Glide`, which is `Glide(grid: 0, four: 0)` when `leave` is infinity (the island is held open).
  - `static let miniRow`, `miniCell`, `miniFrom`, `miniMinD`; `struct Mini { x, y, d }`.
  - `static func miniSlots(minis: Double, glide: Glide, width: Double = compact, height: Double = notchH, d: Double = miniCell.d) -> [Mini]`.
  - `Compact.miniScale`, equal to `IslandRestingLayout.miniGridScale` (the test proves it).

- [ ] **Step 1: Write the failing tests**

The new sections replay the fixtures, check the glide's end against the compact view's arithmetic on five islands, pin the view's literals, and walk early leaves and every time and height for finite numbers.

**Edit `tests/CatGreetingTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkTrue("every pose from before the start to well after the end is finite", finite)
```

and replace it with:

```swift
        CT.checkTrue("every pose from before the start to well after the end is finite", finite)

        // The last beat: the session cats pop in as a row of three, glide into the compact island's 2x2 grid, and a fourth joins.
        CT.section("the last beat: the glide's timeline and geometry")
        CT.checkJSON("the beats", got: ["glide0": G.GT3.glide0, "glide1": G.GT3.glide1, "four0": G.GT3.four0, "end": G.GT3.end, "greetEnd": G.greetEnd] as [String: Any], want: seq["miniTimeline"]!)
        CT.checkNear("the whole greeting, glide included, ends at 6.5 s", G.greetEnd, 6.5)
        CT.checkNear("and its first part is still 5.74 s", G.length, 5.74)
        CT.checkJSON("the row, the grid's cells and which row cat glides into which cell", got: [
            "row": ["d": G.miniRow.d, "step": G.miniRow.step, "inset": G.miniRow.inset, "dy": G.miniRow.dy],
            "grid": ["step": G.miniCell.step, "inset": G.miniCell.inset, "d": G.miniCell.d],
            "from": G.miniFrom.map { $0 == nil ? NSNull() : $0! as Any },
            "minD": G.miniMinD,
        ] as [String: Any], want: seq["miniGeometry"]!)

        CT.section("the glide's samples, with the timeline's own leave and two early ones")
        var glideDiffs: [String] = []
        for c in seq["miniGlideSamples"] as! [[String: Any]] {
            let g = G.miniGlide(num(c["tMs"]) / 1000, leave: num(c["leave"]))
            glideDiffs += CT.diffs(["grid": g.grid, "four": g.four] as [String: Any], c["glide"]!).map { "leave \(c["leave"]!), \(c["tMs"]!) ms: \($0)" }
        }
        CT.checkRows("\((seq["miniGlideSamples"] as! [Any]).count) samples", glideDiffs)
        CT.checkTrue("held open (leave is infinity) the island has not folded, so there is no glide", G.miniGlide(60, leave: .infinity) == G.Glide(grid: 0, four: 0))

        CT.section("the slots: the row, the glide and the end, on every island the fixture lists")
        var slotDiffs: [String] = []
        for c in seq["miniSlotCases"] as! [[String: Any]] {
            let slots = G.miniSlots(minis: num(c["minis"]), glide: G.Glide(grid: num(c["grid"]), four: num(c["four"])), width: num(c["W"]), height: num(c["H"]), d: num(c["d"]))
            slotDiffs += CT.diffs(slots.map { ["x": $0.x, "y": $0.y, "d": $0.d] as [String: Any] }, c["slots"]!).map { "\(c["name"]!), \(c["tMs"]!) ms: \($0)" }
        }
        CT.checkRows("\((seq["miniSlotCases"] as! [Any]).count) cases", slotDiffs)

        CT.section("the end of the glide is the compact island's real grid")
        // CompactMiniGrid: a 28 x 28 frame of 12 pt cells 4 apart (cell centres 8 either side of its middle), scaled about its middle by
        // miniGridScale and centred at (width - 40, height / 2) in the island; IslandRestingLayout is the compact view's own arithmetic.
        for (w, h) in [(288.0, 32.0), (344, 38), (344, 32), (240, 24), (200, 20)] {
            let layout = IslandRestingLayout(width: CGFloat(w), height: CGFloat(h)), k = Double(layout.miniGridScale)
            CT.checkNear("\(Int(w)) x \(Int(h)): the greeting's scale is the compact view's miniGridScale", G.Compact(width: w, height: h).miniScale, k)
            let cx = 320 - w / 2 + Double(layout.miniGridCenterX), cy = Double(layout.botCenterY)
            let want = [(-8.0, -8.0), (8, -8), (-8, 8), (8, 8)].map { G.Mini(x: cx + $0.0 * k, y: cy + $0.1 * k, d: 12 * k) }
            let got = G.miniSlots(minis: 1, glide: G.Glide(grid: 1, four: 1), width: w, height: h)
            var off = 0.0
            for (a, b) in zip(got, want) { off = max(off, abs(a.x - b.x), abs(a.y - b.y), abs(a.d - b.d)) }
            CT.checkTrue("\(Int(w)) x \(Int(h)): the four cats are on the grid's four cells (worst \(off))", off < 1e-9)
        }
        // The view's own literals cannot be called from a test, so they are pinned: if one changes, change the contract's grid with it.
        let view = try! String(contentsOfFile: "NotchBuddy/Sources/App/IslandRootView.swift", encoding: .utf8)
        for (what, text) in [
            ("CompactMiniGrid: two columns of 12 pt cells 4 pt apart", "GridItem(.fixed(12), spacing: 4), GridItem(.fixed(12), spacing: 4)"),
            ("4 pt between its rows", "LazyVGrid(columns: cols, spacing: 4)"),
            ("each cat is 20 * 0.6 = 12 pt across", ".frame(width: 12 / 0.6, height: 12 / 0.6)"),
            ("in a 28 x 28 frame", ".frame(width: 28, height: 28)"),
            ("scaled by miniGridScale", ".scaleEffect(IslandRestingLayout(width: islandWidth, height: islandHeight).miniGridScale)"),
            ("centred 40 pt in from the right edge and level with the strip's middle", ".position(x: islandWidth - 40, y: islandHeight / 2)"),
        ] { CT.checkTrue(what, view.contains(text)) }

        CT.section("leaving early: the last beat follows the island's fold")
        for leave in [0.3, 2.0, 3.0, G.GT.leave] {
            let at = { (o: Double) in G.miniSlots(minis: G.pose(leave + o, leave: leave).minis, glide: G.miniGlide(leave + o, leave: leave)).map { $0.d > 0 } }
            CT.check("leave at \(leave): no cat 0.2 s after the fold starts", at(0.2), [false, false, false, false])
            CT.check("leave at \(leave): a row of three at 0.6 s", at(0.6), [true, true, false, true])
            CT.check("leave at \(leave): the grid's four at the end", at(G.GT3.end), [true, true, true, true])
        }
        var slotsFinite = true
        for ms in stride(from: -500, through: 9000, by: 50) {
            for leave in [G.GT.leave, 1.0, .infinity] {
                for h in [0.0, 6, 24, 32, 200] {
                    let t = Double(ms) / 1000
                    let s = G.miniSlots(minis: G.pose(t, leave: leave).minis, glide: G.miniGlide(t, leave: leave), height: h)
                    if s.contains(where: { !$0.x.isFinite || !$0.y.isFinite || !$0.d.isFinite }) { slotsFinite = false }
                }
            }
        }
        CT.checkTrue("every slot is finite, before the start and after the end, held open, on a strip of any height", slotsFinite)
```

**Edit `scripts/test-cat-greeting.sh`**, find this text (it occurs exactly once):

```bash
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatGreeting.swift \
```

and replace it with:

```bash
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatGreeting.swift $APP/IslandScreenGeometry.swift \
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash scripts/test-cat-greeting.sh 2>&1 | tail -6`
Expected: a compile failure naming the missing members, for instance `error: type 'G' (aka 'CatGreeting') has no member 'GT3'`.

- [ ] **Step 3: Add the port to `CatGreeting.swift`**

**Edit `NotchBuddy/Sources/App/CatGreeting.swift`**, find this text (it occurs exactly once):

```swift
            self.width = width; self.height = height; botCenterY = height / 2; botDiameter = min(20, max(0, height - 6))
        }
    }
```

and replace it with:

```swift
            self.width = width; self.height = height; botCenterY = height / 2; botDiameter = min(20, max(0, height - 6))
        }
        /// How much the compact island's mini grid shrinks on a strip shorter than 32 pt: `IslandRestingLayout.miniGridScale`, which the compact view uses.
        var miniScale: Double { min(1, max(0, height - 4) / 28) }
    }
```

**Edit `NotchBuddy/Sources/App/CatGreeting.swift`**, find this text (it occurs exactly once):

```swift
    static let length = GT.leave + GT.collapse + 0.5
```

and replace it with:

```swift
    static let length = GT.leave + GT.collapse + 0.5

    // MARK: The last beat: the session cats

    /// The last beat's timings, in seconds after `leave`, the moment the island starts to fold: the row of session cats holds, glides into the
    /// compact island's 2x2 grid, a fourth cat pops into the empty cell, and the greeting ends. Port of GT3 in cat-core.js.
    enum GT3 { static let glide0 = 0.8, glide1 = 1.3, four0 = 1.0, end = 1.6 }
    /// Where the whole greeting, glide included, ends. `length` stays 5.74 s, up to the settled row.
    static let greetEnd = GT.leave + GT3.end

    /// The glide's two progress values: `grid` is the row becoming the grid (0...1), `four` the fourth cat's pop (0...1 and a little over).
    struct Glide: Equatable { var grid: Double, four: Double }

    /// Port of `miniGlide`. Held open (`leave` is infinity) the island has not started to fold, so there is no glide.
    static func miniGlide(_ t: Double, leave: Double = GT.leave) -> Glide {
        guard leave.isFinite else { return Glide(grid: 0, four: 0) }
        return Glide(grid: CatEase.inOut.at(seg(t, leave + GT3.glide0, leave + GT3.glide1)), four: CatEase.back.at(seg(t, leave + GT3.four0, leave + GT3.glide1)))
    }

    /// The prototype's row: head width, spacing, the first cat's inset from the island's right edge, and how far it sits below the strip's middle (pt).
    static let miniRow = (d: 11.0, step: 14.0, inset: 12.0, dy: 1.0)
    /// The compact island's grid (`CompactMiniGrid`): cells 16 pt between centres, its centre 40 in from the island's right edge, and its cats' head width.
    static let miniCell = (step: 16.0, inset: 40.0, d: 12.0)
    /// Grid cell (top left, top right, bottom left, bottom right) to the row cat that glides into it, 0 being the row's right-most; the bottom left has none.
    static let miniFrom: [Int?] = [2, 1, nil, 0]
    /// A session cat narrower than this is not drawn: the first frames of a pop, or a strip too short to hold it.
    static let miniMinD = 2.0

    /// One session cat: centre and head width in the 640x150 space; d is 0 for a cat that is not there.
    struct Mini: Equatable { var x: Double, y: Double, d: Double }

    /// Port of `miniSlots`: the four session cats in the order of the grid's cells. `minis` is the row's pop-in (`Pose.minis`), `glide` is `miniGlide`,
    /// `width` and `height` the compact island, `d` the grid cat's head width. A strip shorter than 32 pt shrinks everything like `miniGridScale`.
    static func miniSlots(minis: Double, glide g: Glide, width W: Double = compact, height H: Double = notchH, d: Double = miniCell.d) -> [Mini] {
        let k = min(1, max(0, H - 4) / 28), right = 320 + W / 2, gx = right - miniCell.inset, gy = H / 2, s = miniCell.step / 2 * k
        return miniFrom.enumerated().map { i, from in
            let x1 = gx + (i % 2 == 1 ? s : -s), y1 = gy + (i < 2 ? -s : s)
            let x: Double, y: Double, dd: Double
            if let from {
                x = lerp(right - (miniRow.inset + miniRow.step * Double(from)) * k, x1, g.grid)
                y = lerp(gy + miniRow.dy * k, y1, g.grid)
                dd = lerp(miniRow.d, d, g.grid) * minis * k
            } else {
                x = x1; y = y1; dd = d * g.four * k
            }
            return Mini(x: x, y: y, d: dd < miniMinD ? 0 : dd)
        }
    }
```

- [ ] **Step 4: Run the tests again**

Run: `bash scripts/test-cat-greeting.sh 2>&1 | tail -70`
Expected: `All tests passed.` The new sections print, among others: `✓ 42 samples`, `✓ 45 cases`, five `the four cats are on the grid's four cells (worst 0.0)` lines, the six `CompactMiniGrid` pin lines, twelve `leave at ...` lines and `✓ every slot is finite ...`.

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/App/CatGreeting.swift tests/CatGreetingTests.swift scripts/test-cat-greeting.sh
git commit -q -m "feat(cat): the Mac port of the greeting's last beat, pinned to the fixtures and to the compact island's grid" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 4: Mac: the renderer, the contact sheet and the pixel proof

**Agent:** `nm-implementer`.

**Files:**
- Modify: `tests/CatRendererTests.swift`
- Modify: `scripts/test-cat-renderer.sh` (adds `IslandScreenGeometry.swift` to the compile list)
- Modify: `NotchBuddy/Sources/App/CatGreetingRenderer.swift`
- Modify: `scripts/render-cats.swift` (the greeting sheet's beats)

**Interfaces:**
- Consumes: Task 3's `CatGreeting.miniSlots`, `miniGlide`, `greetEnd`, `Mini`, `Compact.miniScale`, `miniMinD`.
- Produces: `CatGreetingRenderer.draw(_:t:leave:engine:end:)` draws the row, the glide and the grid; its `leave` is the same value the pose uses, so an early leave moves the beat with it. `bash scripts/render-cats.sh --greeting` shows the beat for the owner's checkpoint.

How a slot is drawn: the real grid draws a cat of head width 12 pt (`MiniBotCanvasView`: 20 × 0.6) and SwiftUI scales the grid by `miniGridScale`; so each slot is drawn at `D = slot.d / miniScale` inside a `scaleBy(miniScale)` about its own centre, which is the same pipeline, and on a notch (scale 1) the same pixels.

- [ ] **Step 1: Write the failing tests**

The first check puts every one of the 16 coats through the row, the glide and the grid, in time and cut short. The second draws the greeting's last frame next to a grid laid out the way `CompactMiniGrid` lays it out, on three islands, and compares the alpha channel of the right half of the canvas, where only the session cats are.

**Edit `tests/CatRendererTests.swift`**, find this text (it occurs exactly once):

```swift
        }
        CT.finish()
```

and replace it with:

```swift
        }
        CT.section("the greeting's last beat: the row, the glide and the fourth cat on every coat, and the last frame is the real compact grid")
        do {
            let clock = FakeClock(), rng = CatRNG(seed: 4)
            func frame(_ id: String, _ t: Double, leave: Double, end: CatGreeting.Compact = CatGreeting.Compact()) -> [UInt8] {
                clock.t = t * 1000
                let e = CatEngine(CatPresets.byID(id), now: { clock.t }, rand: { rng.next() }, cfg: CatConfig(), quiet: true)
                return render(640, 150) { CatGreetingRenderer.draw($0, t: t, leave: leave, engine: e, end: end) }
            }
            /// What is painted in the right half of the canvas: once the island has folded the greeting's cat sits on the left and the session cats on the right.
            func right(_ px: [UInt8]) -> Int { (0..<150).reduce(0) { n, y in n + (320..<640).filter { alpha(px, $0, y, 640) > 8 }.count } }
            var blanks: [String] = []
            for id in CatPresets.ids {
                for leave in [CatGreeting.GT.leave, 1.0] {
                    for (what, after) in [("the row", 0.6), ("mid-glide", 1.1), ("the grid", 1.6)] where right(frame(id, leave + after, leave: leave)) == 0 { blanks.append("\(id), leave \(leave), \(what)") }
                }
            }
            CT.check("every coat's session cats are on screen in the row, mid-glide and in the grid, whether the greeting runs its course or is cut short", blanks, [])
            let grown = right(frame("shrimpy", CatGreeting.GT.leave + 1.6, leave: CatGreeting.GT.leave)), row = right(frame("shrimpy", CatGreeting.GT.leave + 0.6, leave: CatGreeting.GT.leave))
            CT.checkTrue("four cats paint more than three (\(grown) against \(row) pixels)", grown > row)

            // The last frame is the compact island's real grid. CompactMiniGrid: a 28 x 28 frame centred at (width - 40, height / 2) and scaled about its
            // middle by miniGridScale, with four cells 16 apart, each a MiniBotCanvasView: a cat of head width 20 * 0.6 = 12 in the middle of its cell.
            for (w, h) in [(288.0, 32.0), (344, 38), (240, 24)] {
                let end = CatGreeting.Compact(width: w, height: h), layout = IslandRestingLayout(width: CGFloat(w), height: CGFloat(h)), k = Double(layout.miniGridScale)
                let got = frame("shrimpy", CatGreeting.greetEnd + 0.3, leave: CatGreeting.GT.leave, end: end)
                let want = render(640, 150) { cg in
                    cg.translateBy(x: 320 - w / 2 + Double(layout.miniGridCenterX), y: Double(layout.botCenterY))
                    cg.scaleBy(x: k, y: k)
                    for (dx, dy) in [(-8.0, -8.0), (8, -8), (-8, 8), (8, 8)] {
                        var pose = CatPose(); pose.tint = 0.6
                        R.draw(cg, CatLook(preset: CatPresets.byID("shrimpy"), pose: pose, color: [127, 180, 234]), cx: dx, cy: dy, D: 12, CatDrawOptions(badge: false))
                    }
                }
                var worst = 0
                for y in 0..<150 { for x in 320..<640 { worst = max(worst, abs(alpha(got, x, y, 640) - alpha(want, x, y, 640))) } }
                CT.checkTrue("\(Int(w)) x \(Int(h)): the greeting's last frame is the real compact grid, pixel for pixel (worst alpha difference \(worst) of 255, \(coverage(want)) pixels painted)", worst <= 2 && coverage(want) > 100)
            }
        }
        CT.finish()
```

**Edit `scripts/test-cat-renderer.sh`**, find this text (it occurs exactly once):

```bash
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
```

and replace it with:

```bash
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift $APP/IslandScreenGeometry.swift \
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash scripts/test-cat-renderer.sh 2>&1 | tail -12`
Expected: it compiles, and four checks fail (`4 test(s) failed.`): `✗ four cats paint more than three (488 against 488 pixels)` and the three `✗ ... the greeting's last frame is the real compact grid, pixel for pixel (worst alpha difference 255 of 255, ...)` lines, because the renderer still draws four cats at once, at Ø11 and 6 pt either side.

- [ ] **Step 3: Draw the slots**

**Edit `NotchBuddy/Sources/App/CatGreetingRenderer.swift`**, find this text (it occurs exactly once):

```swift
        drawMinis(cg, P.minis, preset: p, end: end)
    }

    /// The four little cats of the compact grid, which grow in as the island closes (the real grid takes over after the greeting).
    private static func drawMinis(_ cg: CGContext, _ scale: Double, preset: CatPreset, end: Greeting.Compact) {
        guard scale > 0.01 else { return }
        let gridScale = min(1, max(0, end.height - 4) / 28), cx = 320 - end.width / 2 + (end.width - 40), cy = end.botCenterY, sp = 6 * gridScale
        for (dx, dy) in [(-sp, -sp), (sp, -sp), (-sp, sp), (sp, sp)] {
            cg.saveGState()
            cg.translateBy(x: cx + dx, y: cy + dy)
            cg.scaleBy(x: scale * gridScale, y: scale * gridScale)
            var pose = CatPose(); pose.tint = 0.6
            CatRenderer.draw(cg, CatLook(preset: preset, pose: pose, color: [127, 180, 234]), cx: 0, cy: 0, D: 11, CatDrawOptions(badge: false))
```

and replace it with:

```swift
        let slots = Greeting.miniSlots(minis: P.minis, glide: Greeting.miniGlide(t, leave: leave), width: end.width, height: end.height)
        drawMinis(cg, slots, preset: p, scale: end.miniScale)
    }

    /// The session cats: a row of three pops in as the island closes, glides into the compact island's 2x2 grid, and a fourth pops in (the real grid
    /// takes over when the last beat is over). Each is drawn the way the real grid draws one: a cat of head width 12 pt scaled about its own centre
    /// by the strip's `miniScale`. `slot.d` already holds the pop and that scale, so the head width drawn is `slot.d / scale`.
    private static func drawMinis(_ cg: CGContext, _ slots: [Greeting.Mini], preset: CatPreset, scale k: Double) {
        guard k > 0 else { return }
        for s in slots where s.d >= Greeting.miniMinD {
            cg.saveGState()
            cg.translateBy(x: s.x, y: s.y)
            cg.scaleBy(x: k, y: k)
            var pose = CatPose(); pose.tint = 0.6
            CatRenderer.draw(cg, CatLook(preset: preset, pose: pose, color: [127, 180, 234]), cx: 0, cy: 0, D: s.d / k, CatDrawOptions(badge: false))
```

- [ ] **Step 4: Run the tests again**

Run: `bash scripts/test-cat-renderer.sh 2>&1 | tail -14`
Expected: `All tests passed.` with `every coat's session cats are on screen ...`, `four cats paint more than three (592 against 375 pixels)` and three `pixel for pixel (worst alpha difference 0 of 255, ...)` lines for 288 × 32 (592 pixels painted), 344 × 38 (592) and 240 × 24 (324).

- [ ] **Step 5: Put the beat on the contact sheet and look at it**

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
                                         (2.7, "waves"), (3.0, "slides back"), (3.8, "settles"), (4.5, "badge, tint"), (5.0, "collapses"), (5.2, "collapses"), (5.7, "compact")]
```

and replace it with:

```swift
                                         (2.7, "waves"), (3.0, "slides back"), (3.8, "settles"), (4.5, "badge, tint"), (5.0, "collapses"), (5.2, "collapses"),
                                         (5.4, "the row pops in"), (5.75, "the row holds"), (5.9, "glides"), (6.0, "glides"), (6.1, "the fourth pops in"), (6.5, "the grid")]
```

Run: `bash scripts/render-cats.sh --greeting --cats shrimpy --out "$TMPDIR/greeting-sheet.png"` and look at the PNG (the Read tool shows images).
Expected: twenty-odd frames in two columns; the last six (`5.40 s · the row pops in` to `6.50 s · the grid`) are the 288 × 32 compact island with the cat on the left. At 5.40 and 5.75 s three small cats sit in a row at the right end; at 5.90 s they move left and down; at 6.00 s a 2 × 2 is forming; at 6.10 s the fourth appears in the bottom left; at 6.50 s a 2 × 2 grid. Compare with the prototype's six strips (Task 2).

- [ ] **Step 6: Commit**

```bash
git add NotchBuddy/Sources/App/CatGreetingRenderer.swift tests/CatRendererTests.swift scripts/test-cat-renderer.sh scripts/render-cats.swift
git commit -q -m "feat(cat): the Mac greeting draws the row of session cats, the glide and the grid, and its last frame is the compact island's grid pixel for pixel" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 5: Mac: the tail (`AppState.greetingTail`, `IslandContainer`, the canvas)

**Agent:** `nm-implementer-deep`: SwiftUI view identity across a mode change, which no unit test reaches.

**Files:**
- Modify: `NotchBuddy/Sources/App/AppState.swift`
- Modify: `NotchBuddy/Sources/App/IslandWindowController.swift`
- Modify: `NotchBuddy/Sources/App/GreetingCanvasView.swift`
- Modify: `NotchBuddy/Sources/App/IslandRootView.swift`

**Interfaces:**
- Consumes: `CatGreeting.GT3.end` (Task 3); the existing `.greetingInterrupt` notification, which `GreetingCanvasView` turns into `tc`, the fold's start.
- Produces: `AppState.greetingTail: Bool`. It becomes true when the finite state machine folds the island out of `.hello` (right after `.greetingInterrupt` is posted), ends when the canvas says the beat is over (with a 0.25 s animation), and ends at once on **any** change of `AppState.mode` away from `.compact`, whoever makes it (`setMode`, `AppState.syncMode`, a hook's expand). `IslandContainer` shows the canvas for `greetingExpanded || greetingTail` and mounts it as a sibling, so the same view lives across the fold and its timeline does not restart. While the tail lasts, `BotPlacement` is hidden (its existing opacity animation, which already keys on `greetingActive`) and the `Group` that holds `CompactMiniGrid` has opacity 0; both fade in as the canvas fades out.

`CompactMiniGrid` itself, and the `.scaleEffect(...)` and `.position(...)` lines that place it, are not touched: Task 3's pin on them must still pass.

- [ ] **Step 1: Add `greetingTail` to `AppState`**

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
    @Published var mode: IslandMode = .hidden
    @Published var view: IslandView = .overview
```

and replace it with:

```swift
    @Published var mode: IslandMode = .hidden {
        // The greeting's tail (below) only lives in the compact island: any other mode ends it, so a stale flag never brings the canvas back.
        didSet { if mode != .compact { greetingTail = false } }
    }
    @Published var view: IslandView = .overview
    /// True from the moment the island folds at the end of the launch greeting until the greeting's last beat (the session cats' glide into
    /// the grid) is over: the greeting canvas stays up in the compact island until then, and the real cat and mini grid wait for it.
    @Published var greetingTail = false
```

- [ ] **Step 2: Set it when the island folds out of the greeting**

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, find this text (it occurs exactly once):

```swift
                    NotificationCenter.default.post(name: .greetingInterrupt, object: nil)
```

and replace it with:

```swift
                    NotificationCenter.default.post(name: .greetingInterrupt, object: nil)
                    // The canvas stays up in the compact island until the greeting's last beat is over (see AppState.greetingTail)
                    state.greetingTail = true
```

- [ ] **Step 3: Let the canvas end it**

**Edit `NotchBuddy/Sources/App/GreetingCanvasView.swift`**, find this text (it occurs exactly once):

```swift
                if trigger { fireGreetComplete() }
```

and replace it with:

```swift
                if trigger { fireGreetComplete() }
            }
            // The island has folded and the last beat is over: hand over to the island's own cat and mini grid, which fade in as this fades out
            .onChange(of: state.greetingTail && t >= tc + CatGreeting.GT3.end) { _, over in
                if over { withAnimation(.easeInOut(duration: 0.25)) { state.greetingTail = false } }
```

- [ ] **Step 4: Keep the canvas through the fold, and make the real grid wait**

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
        let greetingActive = state.mode == .expanded && state.view == .greeting
```

and replace it with:

```swift
        let greetingExpanded = state.mode == .expanded && state.view == .greeting
        // After the island has folded the greeting canvas stays up until its last beat (the session cats' glide into the grid) is over.
        let greetingTail = state.greetingTail && state.mode == .compact
        let greetingActive = greetingExpanded || greetingTail
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
                if greetingActive {
                    // Greeting canvas: fixed 640-wide, centered by offset so x=320 aligns with island center
                    GreetingCanvasView(state: state)
                        .frame(width: IslandConst.expandedWidth, height: 150)
                        .offset(x: (islandWidth - IslandConst.expandedWidth) / 2)
                        .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                              cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        .transition(.opacity)
```

and replace it with:

```swift
                if greetingExpanded {
                    // The greeting canvas is drawn by the sibling below, so that it survives the island folding.
                    EmptyView()
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
                                              cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        .transition(.opacity)
                }
            }

            // Single BotPlacement — always alive in the view tree so spring animations
```

and replace it with:

```swift
                                              cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        .transition(.opacity)
                }
            }

            // Greeting canvas: fixed 640-wide, centered by offset so x=320 aligns with island center. It stays up after the island has
            // folded, until the last beat is over, so it is not a child of the expanded block above.
            if greetingActive {
                GreetingCanvasView(state: state)
                    .frame(width: IslandConst.expandedWidth, height: 150)
                    .offset(x: (islandWidth - IslandConst.expandedWidth) / 2)
                    .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                          cornerRadius: cornerRadius, topRadius: islandTopRadius))
                    .transition(.opacity)
            }

            // Single BotPlacement — always alive in the view tree so spring animations
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
            .animation(.easeInOut(duration: 0.25), value: state.mode == .compact)
```

and replace it with:

```swift
            .animation(.easeInOut(duration: 0.25), value: state.mode == .compact)
            // While the greeting canvas draws its own session cats the real grid waits, and fades in as the canvas fades out.
            .opacity(greetingTail ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: greetingTail)
```

- [ ] **Step 5: Build, and prove the compact island's own code did not change**

Run:
```bash
cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build 2>&1 | tail -3 && cd ..
git status --short NotchBuddy/NotchBuddy.xcodeproj
git diff -U0 -- NotchBuddy/Sources/App/IslandRootView.swift | grep '^[-+]' | grep -c "GridItem\|LazyVGrid\|miniGridScale\|islandWidth - 40\|frame(width: 28\|frame(width: 12"
bash scripts/test-cat-greeting.sh 2>&1 | tail -3
bash scripts/test-cat-renderer.sh 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`; no line from `git status` (no file was added, so XcodeGen's output equals the tracked project; if it differs, `git checkout -- NotchBuddy/NotchBuddy.xcodeproj` and say so in the report); the `grep -c` prints `0`; both test scripts end in `All tests passed.` (the second one proves `CompactMiniGrid`'s literals are still the ones the contract was written from).

Do **not** run the app: no unit test reaches the tail, and a Debug build of NotchMeow writes to `~/Library/Logs/NotchMeow`. The main session runs it at the checkpoint (Task 8).

- [ ] **Step 6: Read the result against this list (the review does too)**

1. `greetingTail` is set in one place only: the `.petit` branch of `wireFSM` when `from == .hello`, after `.greetingInterrupt` is posted and before `setMode(.compact)`, so no frame has the island compact with neither canvas nor tail.
2. `AppState.mode`'s `didSet` clears it for every change of mode that is not to `.compact`: a click on the compact island (`.home`), Escape, a hook's expand, the island hiding itself. A stale `true` can never bring the canvas back, because the canvas is also gated on `state.mode == .compact`.
3. `GreetingCanvasView(` appears exactly once in `IslandContainer.body`, with no `.id(`, and outside the `if state.mode == .expanded` block, so SwiftUI keeps one instance from the greeting through the fold to the end of the beat.
4. The canvas ends the tail itself, in `withAnimation(.easeInOut(duration: 0.25))`, which animates its removal (`.transition(.opacity)`), `BotPlacement`'s opacity and the grid's opacity together: a cross-fade of identical pictures, since Task 4 proved the last frame is the grid.
5. Known limit, left as it is: a debug "launch greeting" during the 1.6 s of a tail would reuse the mounted canvas without restarting its clock. A real launch never meets it.

- [ ] **Step 7: Commit**

```bash
git add NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/IslandWindowController.swift NotchBuddy/Sources/App/GreetingCanvasView.swift NotchBuddy/Sources/App/IslandRootView.swift
git commit -q -m "feat(island): after the island folds, the greeting canvas stays for the last beat and the real cat and grid fade in as it fades out" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 6: Windows/Linux: the port, the drawing and the tests

**Agent:** `nm-implementer`.

**Files:**
- Modify: `windows/scripts/cat-tests/greeting.test.mjs`
- Modify: `windows/src/cat/greeting.ts`

**Interfaces:**
- Consumes: Task 1's fixture keys; `MINI_GRID` (this file's pinned grid: Ø13, 16 apart, centred 40 px in from the right edge of a 288 px island, at 16), `COMPACT_W`, `NOTCH_H`, `EZ`, `seg`, `lerp`.
- Produces (Task 7 and the dev page use these): `GT3`, `GREET_END`, `MiniGlide`, `miniGlide`, `MINI_ROW`, `MINI_CELL`, `MINI_FROM`, `MINI_MIN_D`, `MiniSlot`, `miniSlots(minis, g, {W, H, d})`, a port of the contract with `d` defaulting to `MINI_GRID.d` (13), and `Greeting.draw` drawing every slot with `d >= MINI_MIN_D` at `s.x, s.y`. `MINI_GRID` stays exported and unchanged in value: the existing pin test reads it against `island.ts` and `style.css`, and now also checks that the glide's last frame is exactly its four cells.

The old test that expected four cats popping in at the grid is replaced: the beat it described is what the owner replaced.

Run everything in this task from `windows/`. Install nothing; `npx --no-install` only.

- [ ] **Step 1: Write the failing tests**

**Edit `windows/scripts/cat-tests/greeting.test.mjs`**, find this text (it occurs exactly once):

```js
import { GREET_LEN, GT, GT2, Greeting, MINI_GRID, STREAKS, greetingPose, streakTime } from "../../src/cat/greeting.ts";
```

and replace it with:

```js
import { GREET_END, GREET_LEN, GT, GT2, GT3, Greeting, MINI_CELL, MINI_FROM, MINI_GRID, MINI_MIN_D, MINI_ROW, STREAKS, greetingPose, miniGlide, miniSlots, streakTime } from "../../src/cat/greeting.ts";
```

**Edit `windows/scripts/cat-tests/greeting.test.mjs`**, find this text (it occurs exactly once):

```js
/** Draws the greeting at second `t` on a canvas that records its text and translations; the clock is the test's. */
function drawAt(t) {
  installBrowserStubs();
  const g = new Greeting();
```

and replace it with:

```js
/** Draws the greeting at second `t` on a canvas that records its text and translations; the clock is the test's. `tc` is when the pointer left, if it did. */
function drawAt(t, tc) {
  installBrowserStubs();
  const g = new Greeting();
  if (tc !== undefined) g.tc = tc;
```

**Edit `windows/scripts/cat-tests/greeting.test.mjs`**, find this text (it occurs exactly once):

```js
test("the session cats pop in with a scale at the compact island's mini grid, blue-tinted", () => {
  assert.equal(drawAt(4).moves.filter(([x, y]) => x > 400 && y < 30).length, 0, "none before the island collapses");
  const t = 5.3, pop = greetingPose(t).minis, { g, moves, scales } = drawAt(t);
  assert.ok(pop > 0.5, `popping in (${pop})`);
  for (const [dx, dy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
    const at = [MINI_GRID.x + (dx * MINI_GRID.step) / 2, MINI_GRID.y + (dy * MINI_GRID.step) / 2];
    assert.ok(moves.some(([x, y]) => x === at[0] && y === at[1]), `a session cat at ${at}`);
  }
  assert.equal(scales.filter(([x, y]) => x === pop && y === pop).length, 4, "each pops in with the same scale, 0 to 1 and a little over");
  assert.equal(g.minis.s.tint, 0.6);
  assert.deepEqual(g.minis.col, [127, 180, 234]);
```

and replace it with:

```js
/** The session cats a draw at `t` put on the canvas: the translations near the compact island's right end, in the order drawn. */
const catsAt = (t, tc) => drawAt(t, tc).moves.filter(([x, y]) => x > 400 && y < 30);
/** The slots the contract says are on screen at `t`, for the greeting's own island (the pose's `minis` and the glide at the same `leave`). */
const slotsAt = (t, leave = GT.leave) => miniSlots(greetingPose(t, leave).minis, miniGlide(t, leave), { d: MINI_GRID.d }).filter((c) => c.d >= MINI_MIN_D);

test("the session cats pop in as a row of three, glide into the compact island's grid, and a fourth joins, blue-tinted", () => {
  assert.equal(catsAt(4).length, 0, "none before the island collapses");
  assert.equal(catsAt(GT.leave + 0.2).length, 0, "nor before the row starts to pop in, 0.24 s after the island starts to fold");
  const row = catsAt(GT.leave + 0.6), right = 320 + 288 / 2;
  assert.deepEqual(row.map(([x, y]) => [Math.round(x), Math.round(y)]).sort((a, b) => a[0] - b[0]), [[right - 40, 17], [right - 26, 17], [right - 12, 17]], "the prototype's row: three cats, 14 px apart, 12 px in from the right edge");
  const mid = catsAt(GT.leave + 1.1);
  assert.equal(mid.length, 4, "the fourth cat has started to pop in by the middle of the glide's second half");
  for (const [t, n] of [[GT.leave + 0.3, 3], [GT.leave + 0.6, 3], [GT.leave + 0.95, 3], [GT.leave + 1.05, 4], [GT.leave + GT3.end, 4]]) {
    const want = slotsAt(t), got = catsAt(t);
    assert.equal(got.length, n, `${n} cats at ${t - GT.leave} s after the fold starts`);
    assert.deepEqual(got.map(([x, y]) => [Math.round(x * 1e6), Math.round(y * 1e6)]), want.map((c) => [Math.round(c.x * 1e6), Math.round(c.y * 1e6)]), `drawn where the contract puts them at ${t}`);
  }
  const { g } = drawAt(GT.leave + 1);
  assert.equal(g.minis.s.tint, 0.6);
  assert.deepEqual(g.minis.col, [127, 180, 234]);
});

test("the last frame of the greeting is the grid's four cells, level with the island's right end", () => {
  const end = catsAt(GREET_END + 0.5).map(([x, y]) => [x, y]);
  const cells = [[-1, -1], [1, -1], [-1, 1], [1, 1]].map(([dx, dy]) => [MINI_GRID.x + (dx * MINI_GRID.step) / 2, MINI_GRID.y + (dy * MINI_GRID.step) / 2]);
  assert.equal(end.length, 4);
  end.forEach(([x, y], i) => { near(x, cells[i][0]); near(y, cells[i][1]); });
});

test("the glide's beats, samples and slot cases are the fixture's", () => {
  same({ ...GT3, greetEnd: GREET_END }, seq.miniTimeline, "timeline");
  const geo = seq.miniGeometry;
  same({ row: MINI_ROW, from: MINI_FROM, minD: MINI_MIN_D, grid: { step: MINI_CELL.step, inset: MINI_CELL.inset } }, { row: geo.row, from: geo.from, minD: geo.minD, grid: { step: geo.grid.step, inset: geo.grid.inset } }, "geometry");
  assert.equal(MINI_GRID.d, 13, "this app's cats are Ø13: the fixture's Ø12 is the Mac's, and the cases pass d");
  assert.ok(seq.miniGlideSamples.length >= 40 && seq.miniSlotCases.length >= 40);
  for (const c of seq.miniGlideSamples) same(miniGlide(c.tMs / 1000, c.leave), c.glide, `leave ${c.leave}, ${c.tMs} ms`);
  for (const c of seq.miniSlotCases) same(miniSlots(c.minis, { grid: c.grid, four: c.four }, { W: c.W, H: c.H, d: c.d }), c.slots, `${c.name}, ${c.tMs} ms`);
  near(GREET_LEN, 5.74);
  near(GREET_END, 6.5);
});

test("a greeting cut short (the pointer left) runs the same beat from where it left, and never moves it later", () => {
  for (const tc of [0.3, 2.0, 3.0]) {
    assert.equal(catsAt(tc + 0.2, tc).length, 0, `leave ${tc}: nothing yet`);
    assert.equal(catsAt(tc + 0.6, tc).length, 3, `leave ${tc}: the row`);
    const end = catsAt(tc + GT3.end, tc), cells = slotsAt(GT.leave + GT3.end);
    assert.equal(end.length, 4, `leave ${tc}: the grid`);
    end.forEach(([x, y], i) => { near(x, cells[i].x); near(y, cells[i].y); });
  }
  // Collapse pressed while the glide is under way: the greeting has been folding since 4.9 s already, so the glide goes on untouched.
  for (const t of [GT.leave + 0.9, GT.leave + 1.1]) assert.deepEqual(catsAt(t, t - 0.05), catsAt(t), `an interrupt at ${t - 0.05} s changes nothing`);
```

**Edit `windows/scripts/cat-tests/greeting.test.mjs`**, find this text (it occurs exactly once):

```js
  assert.equal(MINI_GRID.y, NOTCH_H / 2, "level with the middle of the strip");
```

and replace it with:

```js
  assert.equal(MINI_GRID.y, NOTCH_H / 2, "level with the middle of the strip");
  // The last beat's end state is exactly those four cells: the cell centres are `step / 2` either side of the grid's centre, Ø13, nothing shrunk.
  const end = miniSlots(1, miniGlide(GREET_END), { d: body });
  [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(([dx, dy], i) => {
    near(end[i].x, MINI_GRID.x + (dx * (cell + gap)) / 2); near(end[i].y, MINI_GRID.y + (dy * (cell + gap)) / 2); near(end[i].d, cell);
  });
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/greeting.test.mjs 2>&1 | tail -12`
Expected: the file fails to load: `SyntaxError: The requested module '../../src/cat/greeting.ts' does not provide an export named 'GREET_END'` (or another new name).

- [ ] **Step 3: Port the contract and draw it**

**Edit `windows/src/cat/greeting.ts`**, find this text (it occurs exactly once):

```ts
 * The compact island's mini grid, which takes over from the greeting's session cats once the greeting ends: four Ø13 cats, 16 px apart,
 * centred 40 px in from the island's right edge and level with the middle of the strip (`applyGeometry` in island.ts, `#mini-grid` in style.css
 * and `createMiniBot(t, 13)`; a check keeps them together). In the greeting's 640 px canvas the island is centred.
 */
export const MINI_GRID = { d: 13, step: 16, x: 320 + COMPACT_W / 2 - 40, y: NOTCH_H / 2 };
const MINI_OFFSETS: readonly (readonly [number, number])[] = [[-1, -1], [1, -1], [-1, 1], [1, 1]];
```

and replace it with:

```ts
 * The compact island's mini grid, which takes over from the greeting's session cats once the greeting ends and which the last beat glides
 * into: four Ø13 cats, 16 px apart, centred 40 px in from the island's right edge and level with the middle of the strip (`applyGeometry`
 * in island.ts, `#mini-grid` in style.css and `createMiniBot(t, 13)`; a check keeps them together). In the greeting's 640 px canvas the
 * island is centred.
 */
export const MINI_GRID = { d: 13, step: 16, x: 320 + COMPACT_W / 2 - 40, y: NOTCH_H / 2 };
```

**Edit `windows/src/cat/greeting.ts`**, find this text (it occurs exactly once):

```ts
export const GREET_LEN = GT.leave + GT.COLLAPSE + 0.5;
```

and replace it with:

```ts
export const GREET_LEN = GT.leave + GT.COLLAPSE + 0.5;

// ── The last beat: the session cats ────────────────────────────────────────────
// A port of GT3, miniGlide and miniSlots in design/prototype/cat-core.js (the tie-breaker; sequence-cases.json pins them). Once the island has
// folded the session cats pop in as a row of three, hold a moment, glide into the compact island's 2×2 grid, and a fourth pops into the empty
// cell. Times are seconds after `leave`, the moment the island starts to fold. GREET_LEN stays 5.74 s; GREET_END is where it all ends.
export const GT3 = { glide0: 0.8, glide1: 1.3, four0: 1, end: 1.6 };
export const GREET_END = GT.leave + GT3.end;
export interface MiniGlide { grid: number; four: number }
/** The glide's two progress values: `grid` is the row becoming the grid, 0…1; `four` is the fourth cat's pop, 0…1 and a little over. */
export const miniGlide = (t: number, leave = GT.leave): MiniGlide => ({
  grid: EZ.inOut(seg(t, leave + GT3.glide0, leave + GT3.glide1)),
  four: EZ.back(seg(t, leave + GT3.four0, leave + GT3.glide1)),
});
/** The prototype's row: head width, spacing, the first cat's inset from the island's right edge, and how far it sits below the strip's middle (px). */
export const MINI_ROW = { d: 11, step: 14, inset: 12, dy: 1 };
/** The compact island's grid cells: centres `step` apart, the grid's centre `inset` px in from the island's right edge. The cat's size is MINI_GRID.d. */
export const MINI_CELL = { step: 16, inset: 40 };
/** Grid cell (top left, top right, bottom left, bottom right) to the row cat that glides into it, 0 being the row's right-most; the bottom left has none. */
export const MINI_FROM: readonly (number | null)[] = [2, 1, null, 0];
/** A session cat narrower than this (px) is not drawn: the first frames of a pop, or a strip too short to hold it. */
export const MINI_MIN_D = 2;
export interface MiniSlot { x: number; y: number; d: number }
/**
 * The four session cats in the order of the grid's cells: centre and head width in px in the 640×150 space, d = 0 for a cat that is not there.
 * `minis` is the row's pop-in (GreetPose.minis), `g` is miniGlide(t, leave), W and H the compact island, d the grid cat's head width.
 * A strip shorter than 32 px shrinks everything the way the Mac's miniGridScale does: min(1, (H - 4) / 28).
 */
export function miniSlots(minis: number, g: MiniGlide, { W = COMPACT_W, H = NOTCH_H, d = MINI_GRID.d } = {}): MiniSlot[] {
  const k = Math.min(1, Math.max(0, H - 4) / 28), right = 320 + W / 2, gx = right - MINI_CELL.inset, gy = H / 2, s = (MINI_CELL.step / 2) * k;
  return MINI_FROM.map((from, i) => {
    const x1 = gx + (i % 2 ? s : -s), y1 = gy + (i < 2 ? -s : s);
    const x = from === null ? x1 : lerp(right - (MINI_ROW.inset + MINI_ROW.step * from) * k, x1, g.grid);
    const y = from === null ? y1 : lerp(gy + MINI_ROW.dy * k, y1, g.grid);
    const dd = (from === null ? d * g.four : lerp(MINI_ROW.d, d, g.grid) * minis) * k;
    return { x, y, d: dd < MINI_MIN_D ? 0 : dd };
  });
}
```

**Edit `windows/src/cat/greeting.ts`**, find this text (it occurs exactly once):

```ts
    // The session cats of the compact grid pop in with a scale as the island collapses; the real grid takes over after the greeting.
    if (P.minis > 0.01) {
      for (const [dx, dy] of MINI_OFFSETS) {
        x.save(); x.translate(MINI_GRID.x + (dx * MINI_GRID.step) / 2, MINI_GRID.y + (dy * MINI_GRID.step) / 2); x.scale(P.minis, P.minis);
        drawCat(x, this.minis, 0, 0, MINI_GRID.d, { badge: false });
        x.restore();
      }
```

and replace it with:

```ts
    // The session cats: a row of three pops in as the island collapses, then glides into the compact island's 2×2 grid, where a fourth pops in.
    // Every slot carries its own pop and scale (the contract's miniSlots); the real grid takes over when the last beat is over.
    for (const s of miniSlots(P.minis, miniGlide(t, leave), { W: COMPACT, H: NOTCH.H, d: MINI_GRID.d })) {
      if (s.d < MINI_MIN_D) continue;
      x.save(); x.translate(s.x, s.y);
      drawCat(x, this.minis, 0, 0, s.d, { badge: false });
      x.restore();
```

- [ ] **Step 4: Run the tests again, type-check, and run the whole cat suite**

Run:
```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/greeting.test.mjs 2>&1 | tail -9
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | tail -9
```
Expected: the greeting file has 10 tests and all pass (`# tests 10`, `# fail 0`); `tsc exit 0`; the whole suite passes (`ℹ tests 86`, `ℹ pass 86`, `ℹ fail 0`: the 83 that were there, minus the test that was replaced, plus four).

- [ ] **Step 5: Commit**

```bash
git add windows/src/cat/greeting.ts windows/scripts/cat-tests/greeting.test.mjs
git commit -q -m "feat(cat): the Windows and Linux greeting draws the row of session cats, the glide and the grid, pinned to the fixtures and to its mini grid" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 7: Windows/Linux: the tail (`greetingShown`, `live`, `onEnd`, the island)

**Agent:** `nm-implementer`.

**Files:**
- Modify: `windows/scripts/cat-tests/greeting.test.mjs`
- Modify: `windows/src/cat/greeting.ts`
- Modify: `windows/src/island/island.ts`

**Interfaces:**
- Consumes: Task 6's `GT3`, `miniGlide`, `miniSlots`, `Greeting.draw`.
- Produces:
  - `greetingShown(mode, view, live) -> boolean`, pure: true in the expanded island's greeting view, and in the compact island while `live`; false for every other mode or view.
  - `Greeting.live`: true from `start()` until the beat is over (`leave + GT3.end`, where `leave` is `GT.leave` or the earlier moment the pointer left); `Greeting.onEnd`: fires once when it ends, from inside `draw`, after the last frame has been drawn.
  - In `island.ts`, `greetingShown()` replaces the three `greetingActive` definitions, so the canvas stays up through the compact island's tail; the canvas fades out by opacity (not `display: none`) over its last frame, while `#mini-grid` (hidden during the tail, `showGrid` is false) and the island's own cat fade in by their existing CSS transitions; `onEnd` calls `State.notify()`, which marks the DOM dirty for the next frame.
- `#mini-grid` in `style.css`, `createMiniBot(t, 13)` and the `miniGrid.style.left/top` lines in `applyGeometry` are not touched: Task 6's pin test still passes.

Run everything in this task from `windows/`. Install nothing; `npx --no-install` only.

- [ ] **Step 1: Write the failing tests**

**Edit `windows/scripts/cat-tests/greeting.test.mjs`**, find this text (it occurs exactly once):

```js
import { GREET_END, GREET_LEN, GT, GT2, GT3, Greeting, MINI_CELL, MINI_FROM, MINI_GRID, MINI_MIN_D, MINI_ROW, STREAKS, greetingPose, miniGlide, miniSlots, streakTime } from "../../src/cat/greeting.ts";
```

and replace it with:

```js
import { GREET_END, GREET_LEN, GT, GT2, GT3, Greeting, MINI_CELL, MINI_FROM, MINI_GRID, MINI_MIN_D, MINI_ROW, STREAKS, greetingPose, greetingShown, miniGlide, miniSlots, streakTime } from "../../src/cat/greeting.ts";
```

**Edit `windows/scripts/cat-tests/greeting.test.mjs`**, find this text (it occurs exactly once):

```js
  for (const t of [GT.leave + 0.9, GT.leave + 1.1]) assert.deepEqual(catsAt(t, t - 0.05), catsAt(t), `an interrupt at ${t - 0.05} s changes nothing`);
});

test("the session cats sit where the compact island's real mini grid does: this app's grid, not the Mac's", () => {
```

and replace it with:

```js
  for (const t of [GT.leave + 0.9, GT.leave + 1.1]) assert.deepEqual(catsAt(t, t - 0.05), catsAt(t), `an interrupt at ${t - 0.05} s changes nothing`);
});

test("the greeting is live from start() to the end of the last beat, says so once, and a replay is live again", () => {
  installBrowserStubs();
  globalThis.window = { setTimeout: () => 0, clearTimeout: () => {} };
  const g = new Greeting();
  let ended = 0, t = 0;
  g.onEnd = () => { ended += 1; };
  Object.defineProperty(g, "elapsed", { get: () => t });
  assert.equal(g.live, false, "not before it starts");
  g.start();
  assert.equal(g.live, true);
  const ctx = fakeCanvas();
  for (t of [0, 3, GT.leave + GT3.end - 0.01]) { g.draw(ctx); assert.equal(g.live, true, `t = ${t}`); }
  t = GT.leave + GT3.end; g.draw(ctx);
  assert.equal(g.live, false);
  assert.equal(ended, 1);
  g.draw(ctx);
  assert.equal(ended, 1, "once");
  g.start();
  assert.equal(g.live, true, "a replay is live again");
  g.tc = 2;
  t = 2 + GT3.end - 0.01; g.draw(ctx);
  assert.equal(g.live, true);
  t = 2 + GT3.end; g.draw(ctx);
  assert.equal(g.live, false, "an early leave ends the beat 1.6 s after it");
  assert.equal(ended, 2);
  delete globalThis.window;
});

test("the greeting canvas is up in the greeting view and through the compact tail, and nowhere else", () => {
  assert.equal(greetingShown("expanded", "greeting", false), true, "the greeting view of the expanded island");
  assert.equal(greetingShown("expanded", "greeting", true), true);
  assert.equal(greetingShown("compact", "overview", true), true, "the compact island while the last beat is live");
  assert.equal(greetingShown("compact", "overview", false), false, "the compact island once the beat is over");
  assert.equal(greetingShown("expanded", "overview", true), false, "the user opened the island during the tail: it ends at once");
  assert.equal(greetingShown("expanded", "approval", true), false, "a hook event expanded it");
  assert.equal(greetingShown("hidden", "greeting", true), false, "a hidden island shows nothing");
  assert.equal(greetingShown("hidden", "overview", true), false);
});

test("the session cats sit where the compact island's real mini grid does: this app's grid, not the Mac's", () => {
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/greeting.test.mjs 2>&1 | tail -12`
Expected: the file fails to load: `does not provide an export named 'greetingShown'`.

- [ ] **Step 3: Add `greetingShown`, `live` and `onEnd` to the greeting**

**Edit `windows/src/cat/greeting.ts`**, find this text (it occurs exactly once):

```ts
import type { CatPreset, EyeShape } from "./types.ts";
```

and replace it with:

```ts
import type { CatPreset, EyeShape } from "./types.ts";
import type { IslandMode, IslandViewName } from "../core/layout.ts";
```

**Edit `windows/src/cat/greeting.ts`**, find this text (it occurs exactly once):

```ts
  x.beginPath(); x.moveTo(X + r, Y); x.arcTo(X + W, Y, X + W, Y + H, r); x.arcTo(X + W, Y + H, X, Y + H, r); x.arcTo(X, Y + H, X, Y, r); x.arcTo(X, Y, X + W, Y, r); x.closePath();
}

/** A session cat of the compact grid, in the greeting's blue: the tint the greeting ends with. */
```

and replace it with:

```ts
  x.beginPath(); x.moveTo(X + r, Y); x.arcTo(X + W, Y, X + W, Y + H, r); x.arcTo(X + W, Y + H, X, Y + H, r); x.arcTo(X, Y + H, X, Y, r); x.arcTo(X, Y, X + W, Y, r); x.closePath();
}

/**
 * Whether the greeting canvas is up: in the expanded island's greeting view, and then, after the island has folded, through the compact island's
 * tail until the last beat is over (`live`). Any other mode or view, the expanded overview or a hidden island included, ends it at once.
 */
export const greetingShown = (mode: IslandMode, view: IslandViewName, live: boolean): boolean =>
  (mode === "expanded" && view === "greeting") || (mode === "compact" && live);

/** A session cat of the compact grid, in the greeting's blue: the tint the greeting ends with. */
```

**Edit `windows/src/cat/greeting.ts`**, find this text (it occurs exactly once):

```ts
  private fired = false;
```

and replace it with:

```ts
  private fired = false;
  private started = false;
  private ended = false;
```

**Edit `windows/src/cat/greeting.ts`**, find this text (it occurs exactly once):

```ts
  onComplete: (() => void) | null = null;
```

and replace it with:

```ts
  onComplete: (() => void) | null = null;
  /** Fires once when the last beat is over, so the island can hand over to its own cat and grid. */
  onEnd: (() => void) | null = null;
```

**Edit `windows/src/cat/greeting.ts`**, find this text (it occurs exactly once):

```ts
    this.fired = false;
```

and replace it with:

```ts
    this.fired = false;
    this.started = true;
    this.ended = false;
```

**Edit `windows/src/cat/greeting.ts`**, find this text (it occurs exactly once):

```ts
  get done(): boolean { return this.fired; }
```

and replace it with:

```ts
  get done(): boolean { return this.fired; }
  /** True from start() until the last beat is over: the island keeps this canvas up through the compact island's tail. */
  get live(): boolean { return this.started && !this.ended; }
  /** When the island starts to fold: GT.leave, or earlier when the pointer left. */
  private get leave(): number { return Number.isFinite(this.tc) ? Math.min(this.tc, GT.leave) : GT.leave; }
  private finish() {
    this.ended = true;
    this.onEnd?.();
  }
```

**Edit `windows/src/cat/greeting.ts`**, find this text (it occurs exactly once):

```ts
    const leave = Number.isFinite(this.tc) ? Math.min(this.tc, GT.leave) : GT.leave;
```

and replace it with:

```ts
    const leave = this.leave;
    if (!this.ended && t >= leave + GT3.end) this.finish();
```

- [ ] **Step 4: Use them in the island**

**Edit `windows/src/island/island.ts`**, find this text (it occurs exactly once):

```ts
import { Greeting } from "../cat/greeting";
```

and replace it with:

```ts
import { Greeting, greetingShown } from "../cat/greeting";
```

**Edit `windows/src/island/island.ts`**, find this text (it occurs exactly once):

```ts
    this.greeting.onComplete = () => this.fsm.greetComplete();
```

and replace it with:

```ts
    this.greeting.onComplete = () => this.fsm.greetComplete();
    // The last beat is over: sync the DOM, so the real cat and the real grid fade in as the greeting canvas fades out.
    this.greeting.onEnd = () => State.notify();
```

**Edit `windows/src/island/island.ts`**, find this text (it occurs exactly once):

```ts
  // ── Frame loop ──────────────────────────────────────────────────────────────

  ensureRunning() {
```

and replace it with:

```ts
  // ── Frame loop ──────────────────────────────────────────────────────────────

  /**
   * The greeting canvas is up in the expanded island, and then, after the island has folded, through the compact island's tail: the row of
   * session cats pops in and glides into the grid there. The canvas draws its own cat and cats meanwhile; the real ones take over at the end.
   */
  private greetingShown(): boolean {
    return greetingShown(State.mode, State.view, this.greeting.live);
  }

  ensureRunning() {
```

**Edit `windows/src/island/island.ts`**, find this text (it occurs exactly once):

```ts
    this.botSize.step(dt);

    const greetingActive = State.mode === "expanded" && State.view === "greeting";
```

and replace it with:

```ts
    this.botSize.step(dt);

    const greetingActive = this.greetingShown();
```

**Edit `windows/src/island/island.ts`**, find this text (it occurs exactly once):

```ts
    this.botSize.target = p.diameter / 0.6;

    const greetingActive = State.mode === "expanded" && State.view === "greeting";
```

and replace it with:

```ts
    this.botSize.target = p.diameter / 0.6;

    const greetingActive = this.greetingShown();
```

**Edit `windows/src/island/island.ts`**, find this text (it occurs exactly once):

```ts
    const greetingActive = expanded && State.view === "greeting";
```

and replace it with:

```ts
    const greetingActive = this.greetingShown();
```

**Edit `windows/src/island/island.ts`**, find this text (it occurs exactly once):

```ts
    this.greetingCanvas.style.display = greetingActive ? "block" : "none";
```

and replace it with:

```ts
    // Not display: none, so that the canvas fades out over its last frame (it is not redrawn) while the real cat and grid fade in.
    this.greetingCanvas.style.transition = greetingActive ? "none" : "opacity 0.25s ease-in-out";
    this.greetingCanvas.style.opacity = greetingActive ? "1" : "0";
```

**Edit `windows/src/island/island.ts`**, find this text (it occurs exactly once):

```ts
    const showGrid = State.mode === "compact";
```

and replace it with:

```ts
    const showGrid = State.mode === "compact" && !greetingActive;
```

- [ ] **Step 5: Run the tests, type-check, and prove the compact island's own code did not change**

Run:
```bash
cd windows
node --experimental-strip-types --test scripts/cat-tests/greeting.test.mjs 2>&1 | tail -9
npx --no-install tsc --noEmit; echo "tsc exit $?"
npm run check:cat 2>&1 | tail -9
git diff --stat -- src/style.css
git diff -U0 -- src/island/island.ts | grep '^[-+]' | grep -c "mini-grid\|miniGrid.style.left\|miniGrid.style.top\|createMiniBot"
```
Expected: the greeting file has 12 tests and all pass (`# tests 12`, `# fail 0`); `tsc exit 0`; the suite passes (`ℹ tests 88`, `ℹ pass 88`, `ℹ fail 0`); `git diff --stat` for `style.css` prints nothing; the last `grep -c` prints `0`.

Do **not** run the app. The real island on Windows or Linux can only be seen on such a machine (`cd windows && npm run tauri dev`); the Mac cannot show it, and the dev page's Greeting section stands in at the checkpoint.

- [ ] **Step 6: Read the result against this list (the review does too)**

1. `greetingShown` is the only definition of "the canvas is up": `grep -n "greetingActive" windows/src/island/island.ts` shows three lines, each `const greetingActive = this.greetingShown();`.
2. `onEnd` fires inside `Greeting.draw`, which runs while `greetingActive` is true, so the frame that ends the beat is drawn and the next one syncs the DOM; `busy` in `frame` includes `greetingActive`, so the loop is alive for that next frame, then stops by itself (0 % CPU once the island is idle or hidden).
3. `showGrid` is `State.mode === "compact" && !greetingActive`; the grid's children are rebuilt only inside `if (showGrid)`, so sessions that start or end during the tail show up when the grid fades in, not before.
4. The canvas keeps its last frame while it fades (`transition: opacity 0.25s`) and is set back to `transition: none` and opacity 1 the moment the greeting is up again, so a launch never fades in.
5. An interrupt only ever moves `leave` earlier (`Math.min(tc, GT.leave)`): the pointer leaving after the fold has begun changes nothing.

- [ ] **Step 7: Commit**

```bash
git add windows/src/cat/greeting.ts windows/src/island/island.ts windows/scripts/cat-tests/greeting.test.mjs
git commit -q -m "feat(island): after the island folds, the greeting canvas stays for the last beat and the real cat and grid fade in as it fades out (Windows and Linux)" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 9: Mac: a new drag makes a left drop stale

Agent: `nm-implementer-light`. Runs after Task 7, before the checkpoint.

**Why:** `FileDropHandler.handle` (`FileDropView.swift`) takes a token per drop (`DropGeneration`, commit `3375e7c`), and after every wait it checks `live()`, which is `drops.isCurrent(drop) && UploadSequenceEngine.shared.isActive`. If the user leaves a drop (the engine deactivates) and drags a new file in before the old drop's task has finished, `enterZone` makes the engine active again while the old token is still the current one. The old task then writes over the new hover. Windows closes the same case with `fileLeft()` on a new hover (commit `2cbdf3a`). The Mac does it by taking a new token as soon as a drag enters, so the left drop's token is stale from then on.

**Files:**
- Modify: `NotchBuddy/Sources/App/IslandWindowController.swift` (the `dropView.onDragEntered` closure)

**Proof:** no unit test reaches an AppKit dragging closure. `DropGeneration` itself is already tested in `tests/UploadCatDriverTests.swift` ("a newer drop makes the older token stale"). This task's proof is the build, the grep below, the scoped review of the diff, and the owner's manual check ("leaving a drop, then dropping again within a few seconds", already in the owner's list).

- [ ] **Step 1: Take a new token when a drag enters**

In `NotchBuddy/Sources/App/IslandWindowController.swift`, replace this exact text:

```swift
                let iLoc = self?.windowToIsland(loc) ?? CGPoint(x: 320, y: 88)
                AppState.shared.fileDragOver = true
```

with:

```swift
                let iLoc = self?.windowToIsland(loc) ?? CGPoint(x: 320, y: 88)
                // A new drag makes any earlier drop stale, so a drop the user left can't write over this hover once the zone is active again.
                _ = FileDropHandler.drops.begin()
                AppState.shared.fileDragOver = true
```

- [ ] **Step 2: Check, build and test**

Run: `grep -c 'FileDropHandler.drops.begin()' NotchBuddy/Sources/App/IslandWindowController.swift`
Expected: `1`

Run: `cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E '\*\* BUILD|error:'`
Expected: `** BUILD SUCCEEDED **`, no `error:` line, and `git status --porcelain NotchBuddy/NotchBuddy.xcodeproj` empty.

Run: `bash scripts/test-cat-upload.sh | tail -1` and `bash scripts/test-escape.sh | tail -1`
Expected: `All tests passed.` and `Escape routing: 21 cases passed`.

- [ ] **Step 3: Commit**

```bash
git add NotchBuddy/Sources/App/IslandWindowController.swift
git commit -q -m "fix(cats): a new drag makes a left drop stale, so it can't write over the new hover" -m "Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

### Task 8: Owner checkpoint: the glide on both apps against the prototype

**Who:** the main session runs Step 1 and shows it to the owner; no implementer agent. Nothing here changes code. Step 2 is the owner's own manual check on a Debug build, after quitting the installed app: no session launches, quits or replaces any NotchMeow app.

**What the owner gets:** three strips of the same beat (the prototype, the Mac, Windows/Linux), side by side, at the same moments, and a verdict on the numbers in `GT3`.

- [ ] **Step 1: The same six moments from each source**

The moments are the six of Task 2, counted from the fold: row (0.5 s after the fold starts), row held (0.85 s), glide begins (1.0 s), mid-glide (1.1 s), fourth cat pops in (1.2 s), grid (1.6 s).
- **Prototype:** serve `design/prototype` on localhost, open `notchmeow.html`, take the Task 2 strips (or use the page's Greeting panel with Slow ×0.5).
- **Mac, contact sheet:** `bash scripts/render-cats.sh --greeting --cats shrimpy,momo --out "$TMPDIR/greeting-mac.png"`.
- **Windows/Linux, dev page:** `cd windows && npx vite`, open `http://127.0.0.1:1420/?dev`, press Replay in the Greeting section and capture the Browser pane at the six moments (the page runs on real time, so use short repeated screenshots, or freeze `performance.now` the way Task 2 freezes the page's loops).

- [ ] **Step 2: The real islands**

- **Mac, Debug build** (`cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build`, then start the built app): record the notch for the greeting, from 4 s to 8 s after launch, for instance `for i in $(seq 1 40); do screencapture -x -R0,0,1100,60 "$TMPDIR/nm-$i.png"; sleep 0.1; done` started at launch. Expected: the island folds at about 5.2 s, the row of three pops in beside the cat, holds, glides into the 2 × 2 with a fourth cat, and at about 6.8 s the real cat and the real grid take over with no jump (with no session running the real grid is empty, so the four stand-ins fade out, as they did before this plan).
- **Mac, with a session running** (start a Claude Code session first, so the real grid has cats): the hand-over is a cross-fade of identical pictures.
- **Mac, the three interruptions of Review Focus:** (1) a click on the compact island during the tail: the island expands at once, no frozen canvas, the cat and the grid come back; (2) a hook event that expands the island (an approval) during the tail: same; (3) the pointer leaves mid-greeting: the fold, the row and the glide follow it. And the cat panel's "Collapse now" during the glide changes nothing.
- **Windows/Linux:** the real island only runs on a Windows or Linux machine (`cd windows && npm run tauri dev`). On this Mac the dev page is the stand-in. Say so to the owner, and keep the same three interruptions as a list for whoever runs it there.

- [ ] **Step 3: Ask the owner**

Show the three strips. Ask: is the row held long enough to read as a row (`GT3.glide0`, 0.8 s after the fold starts), is the glide's pace right (0.5 s), is the fourth cat's pop in the bottom left what is wanted, and should the beat be shorter or longer overall (`GT3.end`, 1.6 s)? A change is one edit in `cat-core.js`'s `GT3` (and the prototype page's own copy of nothing: it reads `CatCore`), then `node scripts/gen-cat-fixtures.mjs`, then the ports' `GT3` in `CatGreeting.swift` and `greeting.ts` (their tests fail until they match), and the docs' numbers.

### Final review

**Agent:** `nm-reviewer-deep`, over the whole branch (`git diff 89a1344...a0c/greeting-grid`), after the owner's checkpoint.

Check across tasks: (1) `node scripts/check-fixtures-additive.mjs 89a1344` passes and `greetingLengthS` is still 5.74; (2) the three ports of `GT3`, `miniGlide` and `miniSlots` (JS, Swift, TypeScript) say the same numbers; (3) `git diff 89a1344 -- windows/src/style.css` is empty and the diff of `IslandRootView.swift` has no changed line in `CompactMiniGrid` or on its `.scaleEffect` and `.position` lines; (4) the tail cannot outlive the compact island on either app, and cannot start anywhere but at the fold out of the greeting; (5) no `UserDefaults` suite, no network, nothing launched; (6) the Mac gets everything Windows got: the tail, the pin, the sheet.

## Dry run (2026-10-06)

The plan's blocks were applied, task by task and step by step, to a clean clone of `notchmeow/rebrand` at `89a1344`, and the red and green results above were observed there. The resulting 21 files are byte-identical to the tree the code was first written and verified in. In that clone: `node --test tests/cat/*.test.mjs` 116 pass (107 before); `bash scripts/test-cat-contract.sh` green with two generator runs writing identical bytes, and `node scripts/check-fixtures-additive.mjs 89a1344` green: only `sequence-cases.json` changed, +94 lines and no deletion; `bash scripts/test-cat-greeting.sh` and `bash scripts/test-cat-renderer.sh` pass, with the pixel comparison at a worst alpha difference of 0 on three islands; `xcodegen` leaves the tracked project unchanged and `xcodebuild -scheme NotchBuddy -configuration Debug build` ends in `** BUILD SUCCEEDED **`; in `windows/` `npx --no-install tsc --noEmit` exits 0 and `npm run check:cat` passes 88 tests (83 before). The prototype page was driven in the Browser pane (Task 2's strips). The app itself was not run.

## Open questions for the owner

1. **How many session cats should the greeting show?** Today it always shows a fixed set: three in the row (as in the prototype) and a fourth that joins, in both apps. At launch there is usually no other session, so the real grid is empty and, as before this plan, the four stand-ins fade away at the hand-over. The alternative is to pass the real number of other sessions (0 to 4) into the beat. This plan keeps the fixed set; the contract's `miniSlots` would take a count.
2. **Which cell does the fourth cat take?** The row's three glide to top left, top right and bottom right (their paths never cross), and the fourth pops in at the bottom left. The real grid fills row by row (top left, top right, bottom left, bottom right), so with three real sessions its bottom right is empty instead.
3. **The pace.** Hold 0.8 s after the fold starts, glide 0.5 s, fourth cat from 1.0 s, end 1.6 s (6.5 s in all, against 5.74 s). All in `GT3`.
4. **Reduced motion.** Neither app honours it anywhere today, so the glide does not either. Should the greeting end on the grid at once when it is on?
5. **The tail is a change of behaviour.** Until now both apps dropped the greeting canvas at the instant the island folded (the Mac within a 0.34 s fade, Windows at once), so the row never reached the screen in a normal launch, and on Windows a half-grown grid flashed before the real one. The tail keeps the canvas for 1.6 s more; Tasks 5 and 7 are only these. Drop them and only the cat panels would show the glide.
6. **The prototype's resting island** now shows the 2 × 2 grid, as the apps do (it showed the row).

## The owner's answers (2026-10-06)

- **Plan:** approved, run in a worktree session on Sonnet 5.5 medium.
- **Question 1, how many cats:** always the fixed 3 + 1 stand-ins, as planned.
- **Question 5, the tail:** keep Tasks 5 and 7, so the glide is seen live.
- **Questions 2, 3 and 6 (the fourth cat's cell, the pace, the prototype at rest):** as planned. The pace and the fourth cell are judged at the checkpoint.
- **Question 4, reduced motion:** not taken up. The glide follows the apps, which honour it nowhere today.
- **Added:** Task 9, the Mac's re-hover parity fix, which runs after Task 7.
