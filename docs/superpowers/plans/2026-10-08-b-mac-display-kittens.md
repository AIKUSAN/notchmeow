# B-mac: Display Modes, the Agents' Cats, Kittens and Coloured Small Eyes in the macOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sub-project B on the Mac. Stage 1: every cat drawn below a head of Ø28 gets **coloured small eyes**. Stage 2: Settings → Cat gets a **Display** picker (One cat, A cat for each agent, Two cats) with a small live preview of the compact notch, the pair pickers, and a list **"Cats for your agents"**, and the Character row becomes **"Main cat"**. Stage 3: each agent gets **its own cat** (Claude Code Shrimpy, Codex Momo, every other agent a random coat it keeps), and every cat view takes its coat as a parameter. Stage 4: the **Two cats** layout. Stage 5: a subagent is a **kitten** beside its parent, with its own state, leaving with a happy blink.

**Architecture:** Every rule is a pure Foundation file tested against B-0's fixtures by a `swiftc` program, the way sub-project A did it: `CatSmallEye`, `CatDisplay` (`cleanDisplaySettings`), `CatAgentCats` (`agentCatFor` and the dice), `CatCast` (`castOf`) and `CatKittens` (`kittenStep`, `kittenView`, `kittenSlots`). `CatSettingsStore` holds the display settings beside the Cat settings and gives an agent its coat the first time it is seen. `AppState.cast` turns the island and Settings into `CatCast`'s plain values, and every cat view (the big cat, the pill cats, the 2×2 grid, the greeting's session cats, the drop view, the drag ghost) takes its coat from it as a parameter, so the per-frame "follow the Main cat" can no longer overwrite an agent's coat. Two cats adds one view, `PairCatViews.swift`, and one place for every layout number, `CatIslandLayout`. Kittens come from the hooks that are already installed: `CatKittenHooks` reads the hooks' words, `HookServer` applies the result to a per-pill list in `AppState`, and `CatKittenDraw` draws them with the same function in the app and on the contact sheets. Nothing is checked by launching the app: the images come from `render-cats.sh` and `render-cat-settings.sh`, and the fake events go to a socket of the test's own.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, CoreGraphics, Combine, XcodeGen, `swiftc` test programs, Bash, Python 3 (the fake-event sender and the test socket).

**Spec:** `docs/superpowers/specs/2026-10-08-display-modes-kittens-design.md`, §1 to §4 and §5 step 2 (with "Risks" and "Done means"). The contract is B-0's: `design/prototype/cat-core.js` with `docs/CAT-CONTRACT.md` ("Display modes, agent coats, kittens and small eyes") and the five fixtures in `tests/fixtures/cat/` (`display-cases.json`, `agent-cat-cases.json`, `cast-cases.json`, `kitten-cases.json`, `small-eye-cases.json`), as B-0 merged them (`e00ad3d`; its plan, `docs/superpowers/plans/2026-10-08-b0-display-kittens-contract.md`, has "Interface for the app plans"). The format and the Mac code's conventions are the last Mac plan's (`docs/superpowers/plans/2026-10-07-a-mac-cats-stages-5-7.md`). The Windows and Linux twin is `docs/superpowers/plans/2026-10-08-b-tauri-display-kittens.md`; "Parity with Windows/Linux" below lists where the two differ.

**Base:** a new branch `b-mac/display-kittens` in a git worktree, from `notchmeow/rebrand` at B-0's merge, **`e00ad3d` or later** (`git merge-base --is-ancestor e00ad3d HEAD` must succeed). B-0 is merged and this plan applies nothing of it: B-0 added the five sections of `cat-core.js`, the five fixtures, the prototype's Display switch and `docs/CAT-CONTRACT.md`'s section (the contract's suite reads `# tests 231`), and `node scripts/check-fixtures-additive.mjs 6c14947` proves the nine old fixtures did not change. Two rules changed at B-0's owner checkpoint and this plan follows both: **the black coats' small eyes glow** (a flat lighter iris, no rim, a thinner pupil) and **the expanded Two cats pair has a gap** (the prototype's cat 2 moved from 105 to 114, which is 99 to 108 pt here). This plan never edits `cat-core.js`, a fixture of `tests/fixtures/cat/`, `shared/theme.json`, a generated theme file or anything under `windows/`.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec and from B-0's interface; the lines marked "(plan decision)" are choices this plan makes where the spec is silent, and are listed again under "Open questions for the owner".

- **Swift 6, SwiftUI and AppKit, no third-party dependencies.** The cats are drawn in code. The pure files (`CatSmallEye`, `CatDisplay`, `CatAgentCats`, `CatCast`, `CatAgentList`, `CatIslandLayout`, `CatKittens`, `CatKittenHooks`) stay Foundation-only; none has a build condition.
- **0 % CPU when the island is hidden.** No new timer and no polling anywhere: a kitten's farewell ends because `CatKittens.view` stops listing it (the layers redraw with their canvas, and the canvas is paused while the island is hidden), a kitten whose stop never comes is swept by the cat's existing ten-minute sleep timer, and Settings' previews (the Display picture, the pair, the agents' list) are `TimelineView`s paused unless the Settings window is on screen and the key window (`WindowVisibility`).
- **Never restyle a shipping view.** The only changes to an existing view are the ones the spec names: the "Character" row is titled "Main cat" (and, in the other two modes only, says in one more line what it is now); the small cats' eyes; and, **in Two cats mode only**, cat 1's place, a second cat, the overview's ticker text starting further right with a second line, and the pair's greeting. **One cat and A cat for each agent keep the shipping layout byte for byte** (a pin per layout number). No other existing Settings row changes. Never rename a pill ID or a contract string (`nm-hook`, `nm.sock`, `nm_kind`, `nm_agent`, bundle identifiers).
- **Frozen contract values.** Cat IDs, in this order: `shrimpy`, `momo`, `ginger`, `midnight`, `latte`, `patches`, `blue`, `snow`, `oreo`, `mocha`, `silver`, `cloud`, `leo`, `button`, `puff`, `noodle` (an unknown stored ID is `shrimpy`). **The display mode IDs `one`, `perAgent` and `two`**, in that order (an unknown stored mode is `one`). Collar style IDs `tag`, `band`, `kerchief`, `off`. Pill IDs. **The UserDefaults keys** of A (`cat.character`, `cat.motionStyle`, `cat.furLines`, `cat.collar`, `cat.motion.<id>`, `cat.collar.<id>`, `cat.personality.<id>`) and the three new ones: `cat.displayMode`, `cat.pair` (the JSON text of two cat IDs, `["shrimpy","momo"]`) and `cat.agentCat.<pillId>`.
- **Stored values never throw and never skip the clean-up.** Every display value read from UserDefaults goes through `CatDisplaySettings.clean` (B-0's `cleanDisplaySettings`, a clean-up of its own, so `CatSettings.clean` and `settings-cases.json` are as they were), and a value is written only after it was cleaned. A pill ID is matched as a whole string (a trailing newline is not a pill ID), `cat.pair` is strict JSON text (Foundation's lenient extras are refused with `Personality.isStrictJSON`), at most 256 agents are kept, and **kittens are never stored**.
- **Fixtures decide.** Numbers compare within **1e-9**; strings, booleans, nulls and shapes compare exactly. `cat-core.js` is the tie-breaker; this plan never edits it or a fixture. JSON cannot hold NaN, infinity or `undefined`, so each port adds its own tests for a time that is not finite (a kitten event changes nothing, a pill's last event is 0), a random source that misbehaves, and NaN in `smallEye`'s inputs. There are no pixel tests of the look: it is checked on the contact sheets and the Settings render. Where a pixel test is used it samples a colour that cannot be anything else or compares two draws of the same cat.
- **Random numbers come in only through an injected source** (`Double.random(in: 0..<1)` in the app, the contract's seeded `CatRNG` in a test); `rand` is called once, and only when a coat is chosen at random.
- **A cat's coat is a parameter of its view,** from the cast (`AppState.cast`): the big cat's (`BotCanvasView(cat:)`), each pill's (`MiniBotCanvasView(cat:)`), the grid's, the greeting's session cats (`CatGreetingRenderer.draw(sessions:)`), the drop view's and the drag ghost's. No view reads the Main cat on its own. **`useCharacter` is never called on a kitten** (a kitten is `CatPresets.kitten(of:)` of its parent's coat, and its view makes a new engine when the parent's coat changes); the engine also refuses to turn a kitten into an adult.
- **The App Store build keeps compiling and gets kittens from Claude Code's hooks.** Both installers (`buildHooksData` in each build) already list `SubagentStart` and `SubagentStop`, and `HookServer.processEvent` is not inside the `#if !APPSTORE` split: so the App Store build has the kittens of its one agent (Claude Code, the VS Code pill) and the GitHub build also Codex's. Gemini CLI and Antigravity send no subagent events, and Cursor none either. A pin proves that no kitten call of `HookServer` sits inside an `#if` block.
- **Frame time.** The bench (`RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench`: twelve small cats and the big one, in an optimised build) is read before the eyes (Task 0) and after (Task 2): **under 2 ms on average on a quiet machine** (1.70 to 1.84 ms before and 1.82 to 1.85 after in the dry runs; the bench moves by 0.1 to 0.2 ms with the machine's load, so read "after" next to a fresh "before": the eyes cost about 0.12 ms, which is 1.79 to 1.84 against 1.92 to 1.96 back to back on a busy machine). `--bench-kittens` adds eight kittens (Task 14) and is reported, with its cost per kitten (about 0.07 ms), not held to 2 ms (Open question 9).
- **Never edit `NotchBuddy.xcodeproj` by hand.** A task that adds a Swift file to the app runs `cd NotchBuddy && xcodegen` before it builds and commits the regenerated `project.pbxproj`. A new Swift file that a test or render script compiles is added to that script's list; the files every renderer script compiles are added to all of them (Task 2 lists the five).
- **No `UserDefaults` suite, and no `UserDefaults.standard` write, in any test or script.** A test builds `CatSettingsStore(backing:config:rand:)` on a `MemoryBacking` (a dictionary) and a `CatConfig` of its own. `CatSettingsStore.shared` and `AppState.shared` are used by the app only. The tests that talk to a socket use one of their own, in a temp folder, never the app's `nm.sock`.
- **Bright eyes for the black coats (B-0's checkpoint).** `SMALL_EYE.bright` is `midnight`, `oreo` and `mocha`, and `brightPupil.w` is 0.12. `smallEye` takes the coat's ID as `cat`: only an exact string in the list is bright (a capital, a space, an empty string, nothing: a normal coat), and its eye has `flat: true`, `rim: 0` and the thinner pupil. The renderer fills a bright iris flat with the lighter of the coat's two iris colours by luminance (Midnight `#F7D45C`, Oreo `#DDEB5A`, Mocha `#F6C44C`), draws no rim and keeps the catchlight; their kittens (`CatPresets.kitten(of:)` keeps the coat ID) are bright too. Every other coat is numerically unchanged.
- **Icons keep their flat ink eyes** (the owner confirmed it). The coloured eyes are for the app's cats: `gen-icons.swift` draws with `inkEyes = true`, so the 18 shipped icon files regenerate byte for byte (Task 2 proves it; without it six small icon files would differ).
- **Nothing of Coucou's comes back, and the names Coucou and Mochi appear in no new code** (`mocha` is a coat). No sound is added for kittens or modes (sound Stage 3).
- **Commits** are local only, never pushed, and only the files each task lists. Each commit message ends with the `Co-Authored-By` line of the model that wrote it: `Claude Sonnet 5.5` for `nm-implementer` and `nm-implementer-deep`, `Claude Haiku 4.5` for `nm-implementer-light`.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app. A Debug, Release or App Store **build** in the worktree is fine and is only built; the scripts that draw a PNG (`render-cats.sh`, `render-cat-settings.sh`, `render-cat-panel.sh`) are not the app and may run. `scripts/fake-subagent-events.py` is **only for the owner's check on a real build**: no task and no agent runs it against the app's socket (`test-cat-kitten-hooks.sh` sends it to a socket of its own).
  2. Install nothing. No network calls, no downloads (`npx --no-install` only; this plan needs neither `npm` nor `cargo`).
  3. Use `trash`, never `rm -rf`, for anything you delete by hand; put scratch files under `${TMPDIR:-/tmp}` with a unique folder name. (The test scripts clean their own `mktemp` folders with `rm -rf` in a `trap`, as every `scripts/test-*.sh` does: that is the repo's convention, not a command an agent runs.)
  4. No `UserDefaults` suite and no write to `UserDefaults.standard` or to `~/Library` in a test or script; tests write no log outside a temp `NM_LOG_DIR`.
  5. Never edit `design/prototype/cat-core.js`, a fixture of `tests/fixtures/cat/`, `shared/theme.json`, a generated theme file or anything under `windows/`.
  6. Never push. Commit only in a task's commit step.
  7. Subagents run on Sonnet 5.5 at most (Haiku 4.5 for the light tasks), never Opus or Fable.
  8. Never rename a frozen ID (the cat IDs, the display mode IDs `one`, `perAgent` and `two`, the collar styles, the pill IDs, the UserDefaults keys), and write no `Coucou` or `Mochi` name anywhere in code, comments, scripts or tests (`mocha` is a coat; `scripts/check-no-leftovers.sh` must stay green).
  9. If a command is denied by a permission prompt, stop and report it. Do not look for a workaround.

## Review Focus

The spec says what the modes, the coats and the kittens do. It is silent on these inputs and conditions, and each would bite a person first, most likely first. Each line names the test that pins it.

1. **A hand-edited or half-written display setting.** `cat.pair` cut off (`["momo",`), with three IDs, an unknown coat, or the same coat twice; `cat.displayMode` stored as a number or `"Two"`; `cat.agentCat.<id>` keys with a capital, a space, `__proto__`, a trailing newline or 300 of them; `cat.agentCat.integration_claude` stored as `tiger`. Expected: Shrimpy and Momo, One cat, a clean map without the bad keys (Claude Code back to Shrimpy), the first 256 in code-point order, never a throw, and Settings still opens. Tests: Task 3 (the 30, 40, 21 and 29 fixture rows, "a store that is wrong in every way still loads", "three hundred stored agents") and Task 6 ("a store that is wrong in every way still loads the display settings").
2. **A cat view that still follows the Main cat, or a kitten turned into an adult.** One missed call site shows an agent's cat as the Main cat on the next frame. Expected: no file re-reads the Main cat each frame, each view is handed its coat, and a kitten's engine is never given `useCharacter` (and ignores it if it were). Tests: Task 10's call-site pins (big cat, pills, grid, greeting, drop view, drag ghost), the greeting's session-cat pixel tests, "a kitten is never turned into an adult", and Task 14's pins.
3. **Subagent events that arrive late, twice or never.** A stop that never comes, a tool event for a kitten that has left, a repeated start, a ninth kitten, an `agent_id` that is empty, 129 characters or not text, a request from a subagent whose card is answered, dismissed or displaced, two sessions of one agent in one pill. Expected: nothing comes back, at most eight are kept, the sleep timer's sweep and the parent's Stop clean up, one session's end leaves the other's kittens. Tests: Task 12 (the 105 events of the fixture's 21 scripts, a time that is not finite, the 4000-event fuzz), Task 13 (the five scripted scenarios through a socket, the unit rows on the hooks' words) and its pins.
4. **An island with nothing to show in the new modes.** Two cats with one agent, with none, with the focus on an integration; the second agent focused by a tap (cat 2 and cat 1 swap); a new agent whose coat is not assigned yet; more than four pills; Settings with no agent seen. Expected: cat 2 idles with no badge and shows "No other agent", nothing is shown twice, the Main cat is worn until the coat is assigned, the list says so. Tests: Task 5 (the 136 fixture rows, the 500-island fuzz), Task 7 (`CatAgentList`, the sample island) and Task 11's pins.
5. **A coloured eye at Ø12, blinking, on a black coat.** At Ø12 the catchlight must not vanish (and the rim, on every coat but the black ones, which have none by design), a squint under 0.22 closes the eye to a line, the pupil must stay in the iris, the expression shapes (happy, closed, spiral…) must stay ink, and only the exact IDs `midnight`, `oreo` and `mocha` (their kittens too) glow: a coat ID with a capital or a space, or none, is a normal coat. Expected: the contract's floors, no change of a pixel outside the eyes, the icons untouched. Tests: Task 1 (265 rows, the floors, the black coats' own checks, the brute-force pupil test) and Task 2 (iris colours on 16 coats × 2 kinds × 4 sizes, the black coats' flat iris at three points of the eye, the ink shapes unchanged, "only the eyes change", the icons).
6. **Settings that animate behind a closed window.** Seventeen more previews would draw at 30 fps behind a closed or unfocused Settings window. Expected: the Display picture, the pair's previews and the agent rows are paused unless Settings is on screen and key. Tests: Task 7's source pins (`paused: !active`, `WindowVisibility`) and the owner's check on a real build.

---

## File Structure

| Path | Responsibility |
|---|---|
| `NotchBuddy/Sources/App/CatSmallEye.swift` | New. The small eye's geometry: `uses`, `eye` (with the coat's ID, for the black coats' bright eye), `flatIris`, the numbers (`K`). Foundation only. |
| `NotchBuddy/Sources/App/CatFace.swift`, `CatLook.swift` | The compact branch of `drawEyes` draws the coloured eye (`smallEye`: flat and rimless on a black coat); `CatLook.inkEyes` (set only by the contact sheet and the icons) keeps the old ink one. |
| `NotchBuddy/Sources/App/CatDisplay.swift` | New. `CatDisplayMode`, `CatDisplaySettings` (the clean-up, the edits, the three UserDefaults keys, load and save). Foundation only. |
| `NotchBuddy/Sources/App/CatAgentCats.swift` | New. `pickCat`, `agentCatFor`, `rerollAgentCat`, `assignAgentCats`. Foundation only. |
| `NotchBuddy/Sources/App/CatCast.swift`, `CatCast+App.swift` | New. `CatCast.of` and `busyRank` (pure); `AppState.cast`, `displayMode`, `agentName(for:)` and `giveCoat(to:)` (the app's side). |
| `NotchBuddy/Sources/App/CatAgentList.swift`, `CatIslandLayout.swift` | New. The rows of "Cats for your agents" and the Display preview's sample island; every layout number of Two cats and the kitten boxes (pure). |
| `NotchBuddy/Sources/App/CatSettings.swift`, `CatSettingsStore.swift`, `CatSettingsView.swift` | `CatSettingsBacking.allKeys()`; the store's `display` and its setters, the first-sight coat and the dice; the Display group, the pair, the agents' list, "Main cat". |
| `NotchBuddy/Sources/App/CatDisplayPreview.swift`, `CatSettingsSection.swift`, `SettingsView.swift` | New: the live picture of the compact notch, and the wrapper that hands Settings the island's agents; `SettingsView` hosts the wrapper. |
| `NotchBuddy/Sources/App/BotCanvasView.swift`, `IslandRootView.swift`, `IslandViewContent.swift`, `IslandWindowController.swift`, `UploadCanvasView.swift`, `GreetingCanvasView.swift`, `CatGreeting.swift`, `CatGreetingRenderer.swift`, `CatEngine.swift` | Each cat view takes its coat; `botPosition` knows the display mode; cat 2 and the overview's second line (Two cats only); the greeting's session cats and pair; a kitten ignores `useCharacter`. |
| `NotchBuddy/Sources/App/PairCatViews.swift` | New. Cat 2: `SecondCatPlacement`, `PairCatCanvasView`, `secondCatPlace`. |
| `NotchBuddy/Sources/App/CatKittens.swift`, `CatKittenHooks.swift`, `CatKittens+App.swift` | New. The reducer, the order, the view, the slots; the hooks' words; the per-pill lists in `AppState`, the sweep. |
| `NotchBuddy/Sources/App/CatKittenDraw.swift`, `KittenViews.swift` | New. One function draws a parent's kittens (the app and the contact sheets); the transparent layer and the island placement. |
| `NotchBuddy/Sources/App/AppState.swift`, `HookServer.swift`, `AppDelegate.swift`, `CatSleep+App.swift`, `IslandTypes.swift` | Each pill's last event, `kittens`, the store watcher, the coat at a pill's creation and once at launch; the hook server's kitten events and the approval's `subagentId`; the sweep. |
| `tests/CatSmallEyeTests.swift`, `CatDisplayTests.swift`, `CatAgentCatsTests.swift`, `CatCastTests.swift`, `CatAgentListTests.swift`, `CatKittensTests.swift`, `CatKittenHooksTests.swift`, `CatWiringTests.swift` | New. One program each (the wiring program is the source pins of the app files no test program can compile). |
| `tests/CatRendererTests.swift`, `CatGreetingTests.swift`, `CatSettingsStoreTests.swift`, `CatSettingsTests.swift`, `CatSettingsSupport.swift` | New sections (the eyes, the greeting's coats and pair, the store's display settings, a kitten and `useCharacter`); two pins of A's updated; the test store lists its keys. |
| `tests/fixtures/mac/subagent-scenarios.json`, `tests/kitten_socket_server.py`, `scripts/fake-subagent-events.py` | New. The five scripted subagent scenarios (one file for the tests, the sender and the sheets), the test's own socket, and the sender for the owner's check. |
| `scripts/test-cat-small-eye.sh`, `test-cat-display.sh`, `test-cat-agent-cats.sh`, `test-cat-cast.sh`, `test-cat-agent-list.sh`, `test-cat-kittens.sh`, `test-cat-kitten-hooks.sh`, `test-cat-wiring.sh` | New. One script for each new test program. |
| `scripts/render-cats.sh`, `render-cats.swift`, `render-cat-settings.sh`, `render-cat-settings.swift`, `render-cat-panel.sh`, `gen-icons.sh`, `gen-icons.swift`, `test-cat-renderer.sh`, `test-cat-settings-store.sh` | The sheets gain `--eyes`, `--island`, `--kittens`, `--bench-kittens`; Settings is drawn in any mode with `--mode`, `--pair`, `--agents`; the compile lists gain the new files; the icons keep ink eyes. |
| `.github/workflows/build.yml`, `CLAUDE.md`, `ARCHITECT.md`, `docs/INTEGRATIONS.md`, `README.md` | One CI step per new script; the Mac lines; the subagent kittens (in French); the roadmap row. |
| `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` | Regenerated by `xcodegen`, never by hand. |

**Order of tasks.** Stage 1 is Tasks 1 and 2; stage 2 Tasks 3 to 7; stage 3 Tasks 9 and 10; stage 4 Task 11; stage 5 Tasks 12 to 14; docs Task 16. **Two things moved against the spec's list.** The spec puts "per-agent coats" after Settings; here the pure ports it builds on come first (the agents' coats, Task 4, and the cast, Task 5), because Settings' dice and "Reset to defaults" are `rerollAgentCat` and `assignAgentCats`, and the Display preview draws `castOf`; what stays in stage 3 is wiring them to the app (a pill's first sight, `AppState.cast`) and handing every cat view its coat. And the pill's last-event time (B-0 interface §3) is Task 6, because the agents' list is "most recent first".

## Tasks and agents

CLAUDE.md: the lightest model that fits. Tasks whose code and docs are given in full and whose tests prove them (1, 3, 4, 5, 12, 16) are `nm-implementer-light` (Haiku 4.5). Tasks that touch several files with a build, a drawing to look at or a store to wire (2, 6, 7, 9) are `nm-implementer` (Sonnet 5.5, medium). Tasks where one missed call site, one wrong layout number or one wrong hook branch would show on the owner's screen, and where several files and the hook server, the island and the greeting have to work together (10, 11, 13, 14), are `nm-implementer-deep` (Sonnet 5.5, high). Each task is then reviewed by `nm-reviewer`; the whole branch by `nm-reviewer-deep` after Task 16. If a step's expected output differs and the cause is not obvious, hand that task to `nm-implementer-deep`. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion` (the deep agent also `superpowers:systematic-debugging`); reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`).

| # | Task | Agent | Review |
|---|---|---|---|
| 0 | Worktree and baseline | the session | none |
| 1 | Small eyes in Swift, from `small-eye-cases.json` (stage 1) | `nm-implementer-light` | `nm-reviewer` |
| 2 | Small eyes drawn: the compact face, the sheets, the icons and the frame bench (stage 1) | `nm-implementer` | `nm-reviewer` |
| 3 | Display settings in Swift: `cleanDisplaySettings` and the three keys (stage 2) | `nm-implementer-light` | `nm-reviewer` |
| 4 | The agents' coats in Swift: `agentCatFor`, the dice and Reset to defaults (stage 2) | `nm-implementer-light` | `nm-reviewer` |
| 5 | The cast in Swift: `castOf` and `cast-cases.json` (stages 2 and 3) | `nm-implementer-light` | `nm-reviewer` |
| 6 | The store holds the display settings, and each pill remembers its last event (stage 2) | `nm-implementer` | `nm-reviewer` |
| 7 | Settings → Cat → Display: Main cat, the picker and its preview, the pair, the agents' list (stage 2) | `nm-implementer` | `nm-reviewer` |
| 8 | **Owner checkpoint 1:** the eyes and Settings | the main session and the owner | none |
| 9 | The cast in the app: a new agent gets its cat, the island reads the cast (stage 3) | `nm-implementer` | `nm-reviewer` |
| 10 | Every cat view takes its coat (stage 3) | `nm-implementer-deep` | `nm-reviewer` |
| 11 | Two cats: the layout, cat 2, the pair's greeting and the island sheet (stage 4) | `nm-implementer-deep` | `nm-reviewer` |
| 12 | Kittens in Swift: the reducer, the order, the slots, from `kitten-cases.json` (stage 5) | `nm-implementer-light` | `nm-reviewer` |
| 13 | Kittens in the app: the hook events, the lists and the sleep timer's sweep (stage 5) | `nm-implementer-deep` | `nm-reviewer` |
| 14 | Kittens drawn at every place, the sheets and the frame bench (stage 5) | `nm-implementer-deep` | `nm-reviewer` |
| 15 | **Owner checkpoint 2:** the modes and the kittens | the main session and the owner | none |
| 16 | Docs, CI and the final checks | `nm-implementer-light` | `nm-reviewer` |
| After 16 | The whole branch: cross-task contracts, privacy and security rules, the Review Focus | `nm-reviewer-deep` | none |
| 17 | **Owner checkpoint 3:** the final report and the manual checks | the main session and the owner | none |

## Execution

One worktree chat session runs the whole plan: branch `b-mac/display-kittens`, model **Sonnet 5.5 at high effort** (`ARCHITECT.md`: a plan with hard integration, the hook server, the island's views and many cross-task interfaces). Nothing is pushed. It runs in a worktree of its own, in parallel with the Windows and Linux twin, which touches nothing under `NotchBuddy/`.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run `git switch -c b-mac/display-kittens notchmeow/rebrand`, then Task 0 of `docs/superpowers/plans/2026-10-08-b-mac-display-kittens.md`: only its Steps 1 to 3 (the base checks: `git merge-base --is-ancestor e00ad3d HEAD` must succeed, B-0 is merged and nothing of it is applied). Read `CLAUDE.md`, `ARCHITECT.md`, that plan, `docs/superpowers/specs/2026-10-08-display-modes-kittens-design.md` and `docs/superpowers/plans/2026-10-08-b0-display-kittens-contract.md` ("Interface for the app plans"). If a base check fails, say so and stop. Reply "ready" and stop. Do not start Task 1.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-08-b-mac-display-kittens.md` with `superpowers:subagent-driven-development`, task by task, on branch `b-mac/display-kittens`. Dispatch each task to the agent the plan's "Tasks and agents" table names, then to `nm-reviewer`; fix what the review finds before the next task. Put the plan's SUBAGENT RULES block (Global Constraints) in every brief. Never launch, quit or replace a NotchMeow app: the builds are builds, the PNGs come from `render-cats.sh` and `render-cat-settings.sh`, and the fake subagent events go only to the socket of `test-cat-kitten-hooks.sh`, never the app's. Run Tasks 1 to 7, then stop and report to the main session for owner checkpoint 1 (Task 8: the images it names, the bench numbers, and what to look for). After the owner's reply run Tasks 9 to 14, then stop again for checkpoint 2 (Task 15). Then run Task 16, dispatch `nm-reviewer-deep` over the whole branch, and stop for checkpoint 3 (Task 17). Commit only as the plan's commit steps say, and never push. The work installs and downloads nothing. Report: the commits; the output of every `bash scripts/test-cat-*.sh` and `bash scripts/check-no-leftovers.sh`; the Debug, Release and App Store build lines and the three `check-app-binary.sh` lines; the bench lines before the eyes, after them and with eight kittens; `0 icon files differ`; the paths of the PNGs of each checkpoint; and anything you could not settle.

Before any follow-up turn (a fix round, a question, a resumed run), the main session checks the session is still on its configured model and effort.

## How to run this plan

**Blocks.** A code step is either **Create `path`** (the file's exact content) or **Edit `path`** (a find text that occurs exactly once, and its replacement). Apply an edit by replacing the find text with the replacement and nothing else; if the find text occurs zero or two times, stop and report: the tree is not what the plan expects. Never type a block from memory and never "improve" one. Every `Run:` line is run from the repository root (the worktree's top folder); `Expected: FAIL` and `Expected: PASS` say which way it must go, and the text after it says what to see. A test program's failing run prints `✗` lines, and its last line is `N test(s) failed.`; a passing one ends `All tests passed.` A new script is made executable with the `chmod +x` line that follows its block.

**Mac commands.** The test programs are `swiftc` programs run through `scripts/test-cat-*.sh`; none needs Xcode. A build is `cd NotchBuddy && xcodegen && cd ..` and then `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO`; the Release build is `-configuration Release -derivedDataPath NotchBuddy/build/release` and the App Store target `-scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store`, each with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` (git ignores `NotchBuddy/build/`). Add `2>&1 | tail -3` to read the last lines. **Never start a built app.** The scripts that draw PNGs write wherever `--out` says; this plan writes them under `${TMPDIR:-/tmp}/b-mac-1` and `b-mac-2`, and the checkpoints copy the ones the owner sees to `.claude/checkpoints/b-mac-1/` and `b-mac-2/` of the worktree (never committed).

**Looking at an image.** Several steps end with "look at it". The agent that ran the step opens the PNG with its file reader and says in one sentence what it sees against the thing named; a blank or broken image is a failed step. The owner's look is the checkpoint.

**Dry-run clones.** A throwaway clone made with `git clone --local --shared` has no `windows/node_modules` and no Docker; nothing here needs either. Commit steps are not run in a clone, so a `git status` there shows every earlier task's files (B-0 is in the base: a fresh clone of `notchmeow/rebrand` at `e00ad3d` or later is the plan's starting point, with nothing to apply first).

---

## Tasks

### Task 0: Worktree and baseline

No code and no commit: this makes sure the base is the one the plan expects. Its first three steps are what the chip's prompt runs before the model is set (see "Execution").

- [ ] **Step 1: Put the session's worktree on the plan's branch**

```bash
git status                                    # must be clean
git switch -c b-mac/display-kittens notchmeow/rebrand
git merge-base --is-ancestor e00ad3d HEAD && echo "B-0 (e00ad3d) is in the base"
git log --oneline -6                          # B-0's merge is in the history
```

Expected: `B-0 (e00ad3d) is in the base`. If that line is missing, the worktree was cut from an older base: stop and tell the owner. Every later command runs from the root of this worktree. Never push.

- [ ] **Step 2: Check that B-0's files are there and the contract is green**

Run: `for f in design/prototype/cat-core.js tests/fixtures/cat/display-cases.json tests/fixtures/cat/agent-cat-cases.json tests/fixtures/cat/cast-cases.json tests/fixtures/cat/kitten-cases.json tests/fixtures/cat/small-eye-cases.json; do test -f $f && echo "ok $f"; done; grep -c "function cleanDisplaySettings" design/prototype/cat-core.js`
Expected: six `ok …` lines and `1`. If a line is missing, the base is not B-0's merge: stop and tell the owner.

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|fixture files match|identical bytes"`
Expected: `# tests 231`, `# pass 231`, `# fail 0`, `✓ 14 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

Run: `node scripts/check-fixtures-additive.mjs 6c14947 2>&1 | tail -1`
Expected: `✓ fixtures changed only by addition since 6c14947`.

- [ ] **Step 3: Check that the Mac cat tests are green, read the frame time, and build**

Run: `for f in scripts/test-cat-*.sh; do printf '%-42s' "$f"; bash "$f" 2>&1 | tail -1; done`
Expected: seventeen lines: `scripts/test-cat-contract.sh` ends `✓ two generator runs write identical bytes` and the other sixteen (`devpanel`, `effects`, `engine`, `frame-meter`, `fur`, `geometry`, `greeting`, `personality`, `presets`, `renderer`, `rules`, `settings-store`, `settings`, `sleep`, `theme`, `upload`) end `All tests passed.`

Run: `RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench 2>&1 | tail -1`
Expected: one line, `12 small cats (30 fps) + the big one (60 fps), update and draw, CPU time: avg 1.7x ms, p95 …` (the dry runs read 1.70 to 1.84 ms; **write the `avg` down: it is the "before" of Task 2**).

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `Created project at …` and the last lines end with `** BUILD SUCCEEDED **` (a few minutes on a cold build). The build only builds: do not open the app.

- [ ] **Step 4: Read the base once**

Read, without changing: `NotchBuddy/Sources/App/CatFace.swift` (`drawEyes`), `CatSettings.swift`, `CatSettingsStore.swift`, `CatSettingsView.swift`, `BotCanvasView.swift` (`BotCanvasView`, `MiniBotCanvasView`), `IslandRootView.swift` (`botPosition`, `BotPlacement`, `CompactMiniGrid`), `IslandViewContent.swift` (`OverviewView`, `AgentPillsView`, `AgentPill`), `HookServer.swift` (`processEvent`, `processPermissionRequest`), `AppState.swift` (`tasks`, `focusTask`) and B-0's "Interface for the app plans". Nothing to report.

---

### Task 1: Small eyes in Swift, from `small-eye-cases.json` (stage 1)

**Agent:** `nm-implementer-light`. The code is given in full; the tests prove it.

**Files:**
- Create: `NotchBuddy/Sources/App/CatSmallEye.swift`, `tests/CatSmallEyeTests.swift`, `scripts/test-cat-small-eye.sh`

**Interfaces:**
- Consumes: B-0's `usesSmallEye` and `smallEye` (`docs/CAT-CONTRACT.md`, "Small coloured eyes"), `tests/fixtures/cat/small-eye-cases.json` (keys `constants`, `shapes`, `bright`, `uses`, `sizes`, `squints`, `gazes`, `scales`, `others`, `hostile`, `brights`) and `CatEye` from `CatLook.swift`.
- Produces: `CatSmallEye.uses(_ shape: CatEye, sd: Double) -> Bool`; `CatSmallEye.eye(_ shape: CatEye, sd: Double = -1, R: Double, es: Double = 1, open: Double = 1, yaw: Double = 0, pitch: Double = 0, kitten: Bool = false, cat: String? = nil) -> CatSmallEye.Eye?` (nil for a shape that stays ink; `Eye` is `Encodable` and `Equatable` with `shape`, `closed`, `iris`, `pupil`, `light`, `rim`, `line` and `flat`: `flat` is `true` and `rim` 0 for a black coat's eye, and nil for every other); `CatSmallEye.flatIris(_ iris: [String]) -> String` (the lighter of a coat's two iris colours by luminance, which a bright eye is filled with); `CatSmallEye.shapes`; `CatSmallEye.K`, the contract's numbers (`K.bright`, `K.brightPupilW` too).

- [ ] **Step 1: Write the failing test**

The program replays the fixture's eleven groups (265 rows of `smallEye`, among them the six `brights` rows of the black coats, and 26 of `usesSmallEye`), adds a real NaN and infinity that JSON cannot write, pins the floors (the catchlight and the rim at Ø6), checks the black coats' eyes on their own (flat, no rim, a pupil 0.12 wide, kittens too, only an exact coat ID is bright, the flat iris colours of Midnight, Oreo and Mocha), and checks by brute force that the pupil never leaves the iris and that 3000 hostile calls give finite numbers only.

**Create `scripts/test-cat-small-eye.sh`**:

```bash
#!/usr/bin/env bash
# Cat small eyes: the geometry of the coloured eyes of the compact detail level (CatSmallEye) against small-eye-cases.json, a real NaN, the floors,
# and that the pupil never leaves the iris.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-small-eye.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatSmallEye.swift \
    tests/CatTestSupport.swift tests/CatSmallEyeTests.swift \
    -o "$TEST_DIR/cat-small-eye-tests"
"$TEST_DIR/cat-small-eye-tests"
```

**Create `tests/CatSmallEyeTests.swift`**:

```swift
import Foundation

@main
enum CatSmallEyeTests {
    typealias E = CatSmallEye

    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }

    /// A JSON number (a boolean, a string and null are not numbers: the contract takes them as the default).
    static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    /// `smallEye(shape, o)` of the fixture, called the way the app calls it: a missing or odd value is the default.
    static func call(_ shape: Any?, _ o: Any?) -> E.Eye? {
        guard let name = shape as? String, let s = CatEye(rawValue: name) else { return nil }
        let r = o as? [String: Any] ?? [:]
        return E.eye(s, sd: number(r["sd"]) == 1 ? 1 : -1, R: number(r["R"]) ?? 0, es: number(r["es"]) ?? 1, open: number(r["open"]) ?? 1,
                     yaw: number(r["yaw"]) ?? 0, pitch: number(r["pitch"]) ?? 0, kitten: (r["kitten"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false,
                     cat: r["cat"] as? String)
    }

    static func all(_ e: E.Eye) -> [Double] {
        [e.iris?.rx, e.iris?.ry, e.iris?.r, e.pupil?.x, e.pupil?.y, e.pupil?.rx, e.pupil?.ry, e.light?.x, e.light?.y, e.light?.r, e.rim,
         e.line?.x0, e.line?.y0, e.line?.cx, e.line?.cy, e.line?.x1, e.line?.y1, e.line?.width].compactMap { $0 }
    }

    @MainActor static func main() {
        let fx = CT.fixture("small-eye-cases.json")

        CT.section("the numbers and the shape list are the contract's")
        CT.check("the four resting shapes, in the contract's order", E.shapes.map(\.rawValue), fx["shapes"] as! [String])
        let k: [String: Any] = [
            "iris": ["w": E.K.irisW, "h": E.K.irisH], "pupil": ["w": E.K.pupilW, "h": E.K.pupilH], "wide": ["w": E.K.wideW, "h": E.K.wideH],
            "dot": ["iris": [E.K.dotIris, E.K.dotIris], "pupil": [E.K.dotPupil, E.K.dotPupil]], "tired": ["open": E.K.tiredOpen],
            "light": ["x": E.K.lightX, "y": E.K.lightY, "r": E.K.lightR, "minR": E.K.lightMinR], "rim": ["k": E.K.rimK, "min": E.K.rimMin],
            "travel": ["x": E.K.travelX, "y": E.K.travelY], "closeBelow": E.K.closeBelow, "pupilFit": E.K.pupilFit, "kitten": ["w": E.K.kittenW, "h": E.K.kittenH],
            "line": ["width": E.K.lineWidth, "minWidth": E.K.lineMinWidth, "curve": E.K.lineCurve],
            "bright": E.K.bright, "brightPupil": ["w": E.K.brightPupilW],
        ]
        CT.checkJSON("SMALL_EYE", got: k, want: fx["constants"]!)
        CT.check("the bright coats, in the contract's order", E.K.bright, fx["bright"] as! [String])

        CT.section("usesSmallEye: \(rows(fx["uses"]).count) rows")
        var diffs: [String] = []
        for r in rows(fx["uses"]) {
            let got = CatEye(rawValue: r["shape"] as! String).map { E.uses($0, sd: number(r["sd"])!) } ?? false
            if got != (r["out"] as! Bool) { diffs.append("\(r["shape"]!) \(r["sd"]!): \(got)") }
        }
        CT.checkRows("every shape and side is as the fixture says (ink shapes and the right eye of a wink stay ink)", diffs)

        for group in ["sizes", "squints", "gazes", "scales", "others", "hostile", "brights"] {
            CT.section("smallEye, \(group): \(rows(fx[group]).count) rows")
            diffs = []
            for r in rows(fx[group]) {
                let got: Any = call(r["shape"], r["o"]).map { CT.json($0) } ?? NSNull()
                let d = CT.diffs(got, r["out"] ?? NSNull())
                if !d.isEmpty { diffs.append("\(r["shape"] ?? "nil") \(r["o"] ?? "nil"): \(d.first!)") }
            }
            CT.checkRows("every row comes out as the fixture says", diffs)
        }

        CT.section("a real NaN or infinity (JSON cannot write them, a call can)")
        let nan = Double.nan, inf = Double.infinity
        let base = E.eye(.pill, R: 9)!, odd = E.eye(.pill, sd: nan, R: 9, es: nan, open: nan, yaw: nan, pitch: nan)!
        CT.check("NaN in es, open, yaw, pitch and sd is the default", odd, base)
        CT.check("NaN in R is a head of 0", E.eye(.pill, R: nan)!, E.eye(.pill, R: 0)!)
        CT.check("infinity in R is a head of 0 too (it is not a number)", E.eye(.pill, R: inf)!, E.eye(.pill, R: 0)!)
        CT.check("a huge R is held to 10000", E.eye(.pill, R: 1e300)!, E.eye(.pill, R: 1e4)!)
        CT.check("a huge es is held to 10", E.eye(.pill, R: 9, es: 1e300)!, E.eye(.pill, R: 9, es: 10)!)
        CT.check("an ink shape is nil whatever else is wrong", E.eye(.happy, R: nan), nil)

        CT.section("the black coats' eyes glow: flat, no rim, a thinner slit pupil, and nothing else about the eye changes")
        for id in E.K.bright { for kitten in [false, true] {
            let b = E.eye(.pill, R: 9, kitten: kitten, cat: id)!, n = E.eye(.pill, R: 9, kitten: kitten, cat: "momo")!
            CT.check("\(id)\(kitten ? " kitten" : ""): flat, no rim", [b.flat == true, b.rim == 0], [true, true])
            CT.check("\(id)\(kitten ? " kitten" : ""): the same iris and catchlight as a normal coat's, a pupil 0.12 wide instead of 0.18", [b.iris == n.iris, b.light == n.light, abs(b.pupil!.rx / n.pupil!.rx - 0.12 / 0.18) < 1e-12, b.pupil!.ry == n.pupil!.ry], [true, true, true, true])
        } }
        CT.check("a normal coat has no flat key and keeps its rim", [E.eye(.pill, R: 9, cat: "momo")!.flat == nil, E.eye(.pill, R: 9)!.flat == nil, E.eye(.pill, R: 9)!.rim! > 0], [true, true, true])
        CT.check("only an exact coat ID is bright: a capital, a space, an empty string and nil are normal coats", ["Midnight", "midnight ", "", "mocha\n"].map { E.eye(.pill, R: 9, cat: $0)!.flat == nil } + [E.eye(.pill, R: 9, cat: nil)!.flat == nil], [true, true, true, true, true])
        CT.check("the round pupil of a dot keeps its size on a bright coat", E.eye(.dot, R: 9, cat: "oreo")!.pupil, E.eye(.dot, R: 9)!.pupil)
        CT.check("a closed bright eye is the same line as a normal one, and an ink shape is still nil", [E.eye(.pill, R: 9, open: 0, cat: "mocha")! == E.eye(.pill, R: 9, open: 0)!, E.eye(.happy, R: 9, cat: "mocha") == nil], [true, true])
        CT.check("the flat iris is the lighter of the two iris colours: Midnight #F7D45C, Oreo #DDEB5A, Mocha #F6C44C (and the first on a tie)",
                 [E.flatIris(["#F7D45C", "#D9921C"]), E.flatIris(["#7FA82A", "#DDEB5A"]), E.flatIris(["#F6C44C", "#C2761A"]), E.flatIris(["#102030", "#102030"])], ["#F7D45C", "#DDEB5A", "#F6C44C", "#102030"])

        CT.section("the floors: at Ø6 the catchlight and the rim are not thinner than half a point")
        var floors = true
        for s in E.shapes { for kitten in [false, true] {
            let e = E.eye(s, R: 3, kitten: kitten)!
            floors = floors && e.light!.r >= E.K.lightMinR && e.rim! >= E.K.rimMin
            if let b = E.eye(s, R: 3, kitten: kitten, cat: "midnight") { floors = floors && b.light!.r >= E.K.lightMinR && b.rim == 0 }
        } }
        CT.checkTrue("catchlight radius at least 0.45 and rim at least 0.5, every shape, kitten or not", floors)

        CT.section("a blink or a squint closes the eye to a line under 0.22 of its height; a tired eye is never wider than 0.42")
        CT.check("0.21 of an eye is a line", E.eye(.pill, R: 9, open: 0.21)!.closed, true)
        CT.check("0.22 of an eye is an eye", E.eye(.pill, R: 9, open: 0.22)!.closed, false)
        CT.check("a tired eye that is wide open is as open as 0.42", E.eye(.tired, R: 9, open: 1)!, E.eye(.tired, R: 9, open: E.K.tiredOpen)!)
        CT.checkNear("the closed line is never thinner than one point", E.eye(.pill, R: 3, open: 0)!.line!.width, 1)

        CT.section("the pupil never leaves the iris, at every squint, gaze, size, kitten and expression scale")
        var worst = 0.0, count = 0
        for s in E.shapes { for kitten in [false, true] { for es in [0.5, 1, 1.5] { for open in [0.22, 0.3, 0.5, 0.8, 1] {
            for yaw in [-2.0, -0.62, 0, 0.31, 0.62, 2] { for pitch in [-1.0, -0.5, 0, 0.25, 0.5, 1] {
                let e = E.eye(s, R: 9, es: es, open: open, yaw: yaw, pitch: pitch, kitten: kitten)!
                guard !e.closed, let i = e.iris, let p = e.pupil else { continue }
                for a in 0..<48 {
                    let t = Double(a) / 48 * 2 * Double.pi, x = p.x + p.rx * cos(t), y = p.y + p.ry * sin(t)
                    worst = max(worst, (x / i.rx) * (x / i.rx) + (y / i.ry) * (y / i.ry))
                }
                count += 1
            } }
        } } } }
        CT.checkTrue("every pupil edge point is inside the iris (\(count) eyes, the farthest at \(String(format: "%.4f", worst)) of the iris's edge)", worst <= 1 + 1e-9)

        CT.section("nothing is NaN, whatever the inputs")
        var finite = true
        var seed: UInt64 = 7
        func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        let wild: [Double] = [nan, inf, -inf, -1, 0, 1, 1e300, -1e300, 5e-324]
        for _ in 0..<3000 {
            func pick() -> Double { next() < 0.5 ? wild[Int(next() * Double(wild.count))] : (next() - 0.5) * 40 }
            let s = CatEye.allCases[Int(next() * Double(CatEye.allCases.count))]
            let coat = ["midnight", "oreo", "mocha", "momo", "", "MIDNIGHT"]
            if let e = E.eye(s, sd: pick(), R: pick(), es: pick(), open: pick(), yaw: pick(), pitch: pick(), kitten: next() < 0.5, cat: next() < 0.5 ? coat[Int(next() * Double(coat.count))] : nil) { finite = finite && all(e).allSatisfy(\.isFinite) }
        }
        CT.checkTrue("3000 calls with NaN, infinities and huge numbers give finite numbers only", finite)

        CT.finish()
    }
}
```

Run: `chmod +x scripts/test-cat-small-eye.sh`
Expected: no output.

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-small-eye.sh 2>&1 | tail -2`
Expected: FAIL: `error opening input file 'NotchBuddy/Sources/App/CatSmallEye.swift'` (the program cannot be built without the file).

- [ ] **Step 3: Write the implementation**

**Create `NotchBuddy/Sources/App/CatSmallEye.swift`**:

```swift
import Foundation

// The small coloured eyes of the compact detail level: below a head of Ø28 the plain resting eyes (pill, wide, dot and tired, and the left eye of a wink)
// are a round iris in the coat's colours, a slit pupil, one catchlight and a thin rim instead of an ink pill. This is the geometry only, in px of the
// eye's own frame (the centre is the origin, y down, before the renderer's foreshortening); the colours and the drawing are `CatFace`'s. Port of the
// "Small eyes" section of design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/small-eye-cases.json pins it. The black coats (`K.bright`) glow:
// their eye is `flat` (the renderer fills the iris flat with `flatIris`, no rim) with a thinner slit pupil, and `cat` says which coat the eye is on. Foundation only.

enum CatSmallEye {
    /// The numbers of the contract (`SMALL_EYE`). Sizes are fractions of `u = R * es` (the head radius times the expression scale), full widths and heights.
    enum K {
        static let irisW = 0.42, irisH = 0.46
        static let pupilW = 0.18, pupilH = 0.40
        static let wideW = 1.16, wideH = 1.12
        static let dotIris = 0.42, dotPupil = 0.26
        /// A tired eye shows at most this much of itself.
        static let tiredOpen = 0.42
        static let lightX = -0.11, lightY = -0.10, lightR = 0.075, lightMinR = 0.45
        static let rimK = 0.05, rimMin = 0.5
        /// The pupil moves at most this much of the iris's half-width across and half-height up or down, so it never leaves the iris.
        static let travelX = 0.2, travelY = 0.08
        /// Under this much of the eye's height a blink or a squint closes it to a line, as the realistic eye does.
        static let closeBelow = 0.22
        static let pupilFit = 0.87
        /// A kitten's eye is this much wider and taller: what `CatPresets.kitten(of:)` does to a kitten's eyes.
        static let kittenW = 1.2, kittenH = 1.32
        static let lineWidth = 0.045, lineMinWidth = 1.0, lineCurve = 0.4
        /// The black coats glow. An explicit list, not a preset field, so the other coats and the preset fixtures do not move; a kitten keeps its parent's coat ID.
        static let bright = ["midnight", "oreo", "mocha"]
        /// A bright eye's slit pupil is this wide (the round pupil of a dot keeps its size).
        static let brightPupilW = 0.12
    }

    struct Iris: Encodable, Equatable, Sendable { var rx: Double, ry: Double, r: Double }
    struct Pupil: Encodable, Equatable, Sendable { var x: Double, y: Double, rx: Double, ry: Double }
    struct Light: Encodable, Equatable, Sendable { var x: Double, y: Double, r: Double }
    struct Line: Encodable, Equatable, Sendable { var x0: Double, y0: Double, cx: Double, cy: Double, x1: Double, y1: Double, width: Double }

    /// One small eye: the two ellipses' radii and centres, the gradient radius, the catchlight and the rim; or, when a blink or a squint closes it, the arc
    /// (drawn in the coat's ink colour at 0.9 alpha). A bright coat's eye has `flat` true and a rim of 0 (nil for every other eye).
    struct Eye: Encodable, Equatable, Sendable {
        var shape: String
        var closed: Bool
        var iris: Iris?
        var pupil: Pupil?
        var light: Light?
        var rim: Double?
        var line: Line?
        var flat: Bool?
    }

    /// The resting shapes that become a small coloured eye. The left eye of a wink is one too (its right eye is an ink arc).
    static let shapes: [CatEye] = [.pill, .wide, .dot, .tired]

    /// True when shape `shape` of the eye `sd` (-1 the left, 1 the right) is drawn with `eye(...)` at the compact level; false when it stays ink.
    static func uses(_ shape: CatEye, sd: Double) -> Bool { shapes.contains(shape) || (shape == .wink && sd < 0) }

    /// A number that is not finite is the default.
    private static func num(_ v: Double, _ d: Double) -> Double { v.isFinite ? v : d }

    /// One small eye, or nil for a shape that stays ink. `R` is the head radius (held to 0 up to 10000), `es` the pose's expression scale (0 up to 10),
    /// `open` is `pose.open * (1 - pose.lid)` (0 to 1), `yaw` and `pitch` the pose's, `kitten` the preset's `kitten`, `cat` the coat ID (the preset's `name`: only an
    /// exact ID in `K.bright` is a bright coat, anything else, nil too, is a normal one). A value that is not finite is its default.
    static func eye(_ shape: CatEye, sd: Double = -1, R: Double, es: Double = 1, open: Double = 1, yaw: Double = 0, pitch: Double = 0, kitten: Bool = false, cat: String? = nil) -> Eye? {
        guard uses(shape, sd: sd == 1 ? 1 : -1) else { return nil }
        let r = max(0, min(1e4, num(R, 0))), u = r * max(0, min(10, num(es, 1)))
        let sh: CatEye = shape == .wink ? .pill : shape
        let kw = kitten ? K.kittenW : 1, kh = kitten ? K.kittenH : 1, bright = cat.map { K.bright.contains($0) } ?? false
        let o = max(0, min(1, num(open, 1))), op = sh == .tired ? min(o, K.tiredOpen) : o
        let baseW = sh == .dot ? K.dotIris : K.irisW * (sh == .wide ? K.wideW : 1), baseH = sh == .dot ? K.dotIris : K.irisH * (sh == .wide ? K.wideH : 1)
        let rx0 = baseW / 2 * kw * u, ry0 = baseH / 2 * kh * u
        if op < K.closeBelow {
            return Eye(shape: shape.rawValue, closed: true, iris: nil, pupil: nil, light: nil, rim: nil,
                       line: Line(x0: -rx0, y0: 0, cx: 0, cy: K.lineCurve * ry0, x1: rx0, y1: 0, width: max(K.lineMinWidth, K.lineWidth * u)))
        }
        let ry = ry0 * op
        let pw = (sh == .dot ? K.dotPupil : bright ? K.brightPupilW : K.pupilW) / 2 * kw * u
        let pry = min((sh == .dot ? K.dotPupil : K.pupilH) / 2 * kh * u, K.pupilFit * ry)
        let gx = max(-1, min(1, num(yaw, 0) / 0.62)), gy = max(-1, min(1, num(pitch, 0) / 0.5))
        return Eye(shape: shape.rawValue, closed: false,
                   iris: Iris(rx: rx0, ry: ry, r: max(rx0, ry)),
                   pupil: Pupil(x: gx * K.travelX * rx0, y: -gy * K.travelY * ry, rx: pw, ry: pry),
                   light: Light(x: K.lightX / (K.irisW / 2) * rx0, y: K.lightY / (K.irisH / 2) * ry, r: max(K.lightR * u, K.lightMinR)),
                   rim: bright ? 0 : max(K.rimK * u, K.rimMin), line: nil, flat: bright ? true : nil)
    }

    /// What a bright eye's iris is filled with, flat: the lighter of the coat's two iris colours by luminance (Midnight #F7D45C, Oreo #DDEB5A, Mocha #F6C44C).
    static func flatIris(_ iris: [String]) -> String {
        func lum(_ hex: String) -> Double {
            let n = UInt32(hex.dropFirst(), radix: 16) ?? 0
            return 0.2126 * Double(n >> 16 & 255) + 0.7152 * Double(n >> 8 & 255) + 0.0722 * Double(n & 255)
        }
        guard iris.count == 2 else { return iris.first ?? "" }
        return lum(iris[0]) >= lum(iris[1]) ? iris[0] : iris[1]
    }
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `bash scripts/test-cat-small-eye.sh 2>&1 | grep -c "✓"; bash scripts/test-cat-small-eye.sh 2>&1 | tail -1`
Expected: `41`, then `All tests passed.`

- [ ] **Step 5: Prove the test bites (one-off, never committed)**

The closing threshold is a contract number: a blink or a squint under 0.22 of the eye's height closes it to a line. Move it, see the fixture and the self-checks fail, and put it back.

Run: `sed -i '' 's/static let closeBelow = 0.22/static let closeBelow = 0.2/' NotchBuddy/Sources/App/CatSmallEye.swift && bash scripts/test-cat-small-eye.sh 2>&1 | grep -c "✗"`
Expected: `3`.

Run: `sed -i '' 's/static let closeBelow = 0.2$/static let closeBelow = 0.22/' NotchBuddy/Sources/App/CatSmallEye.swift && bash scripts/test-cat-small-eye.sh 2>&1 | tail -1`
Expected: `All tests passed.`

- [ ] **Step 6: Commit**

```bash
git add NotchBuddy/Sources/App/CatSmallEye.swift tests/CatSmallEyeTests.swift scripts/test-cat-small-eye.sh
git commit -m "feat(cat): the small eye's geometry, replayed from small-eye-cases.json

CatSmallEye is the Swift port of usesSmallEye and smallEye: the iris, the slit pupil, the catchlight and the rim of the coloured eyes of the compact detail
level, with the closed line of a blink. Its test replays 265 fixture rows, a real NaN, the floors, the black coats' bright eyes (flat, no rim, a thinner pupil, picked by the exact coat ID) and a brute-force check that the pupil stays in the iris.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Small eyes drawn: the compact face, the sheets, the icons and the frame bench (stage 1)

**Agent:** `nm-implementer`. The code is given in full; this task builds, draws two sheets to look at and measures the frame time.

**Files:**
- Modify: `NotchBuddy/Sources/App/CatFace.swift` (the compact branch of `drawEyes`, and `smallEye`), `NotchBuddy/Sources/App/CatLook.swift` (`CatLook.inkEyes`), `tests/CatRendererTests.swift`, `scripts/test-cat-renderer.sh`, `scripts/render-cats.sh`, `scripts/render-cats.swift` (the `--eyes` sheet), `scripts/render-cat-panel.sh`, `scripts/render-cat-settings.sh`, `scripts/gen-icons.sh`, `scripts/gen-icons.swift`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (by `xcodegen`)

**Interfaces:**
- Consumes: Task 1's `CatSmallEye.eye(...)` (with the coat's ID as `cat`) and `CatSmallEye.flatIris`; `CatEngine`, `CatRenderer`, `CatDraw`.
- Produces: `CatLook.inkEyes` (default `false`: every cat in the app has the coloured eyes; only the contact sheet that shows today's look beside them, and the icons, set it); `bash scripts/render-cats.sh --eyes [--scale 1|2] --out file.png`; `CatSmallEye.swift` in the compile list of the five scripts that compile `CatFace.swift`.

- [ ] **Step 1: Add the new file to the five scripts that compile the face**

Every script that compiles `CatFace.swift` now needs `CatSmallEye.swift` too: the renderer's test, the contact sheets, the panel's and Settings' renders, and the icons.

**Edit `scripts/gen-icons.sh`**, find this text (it occurs exactly once):

```bash
swiftc -swift-version 6 -O \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
```

and replace it with:

```bash
swiftc -swift-version 6 -O \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
```

**Edit `scripts/render-cat-panel.sh`**, find this text (it occurs exactly once):

```bash
swiftc -swift-version 6 -D DEBUG \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/AppLog.swift $APP/CatFrameMeter.swift $APP/CatFrameReadout.swift $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
    $APP/CatFileRule.swift $APP/AI/Core/Attachments.swift $APP/AI/Core/AICatalog.swift $APP/AI/Core/ModelProvider.swift $APP/AI/Core/ContextBudget.swift \
```

and replace it with:

```bash
swiftc -swift-version 6 -D DEBUG \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/AppLog.swift $APP/CatFrameMeter.swift $APP/CatFrameReadout.swift $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
    $APP/CatFileRule.swift $APP/AI/Core/Attachments.swift $APP/AI/Core/AICatalog.swift $APP/AI/Core/ModelProvider.swift $APP/AI/Core/ContextBudget.swift \
```

**Edit `scripts/render-cat-settings.sh`**, find this text (it occurs exactly once):

```bash
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatSettings.swift $APP/CatSettingsStore.swift $APP/CatSettingsView.swift \
    scripts/render-cat-settings.swift \
```

and replace it with:

```bash
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatSettings.swift $APP/CatSettingsStore.swift $APP/CatSettingsView.swift \
    scripts/render-cat-settings.swift \
```

**Edit `scripts/render-cats.sh`**, find this text (it occurs exactly once):

```bash
swiftc -swift-version 6 ${RENDER_CATS_OPT:+-O} \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
```

and replace it with:

```bash
swiftc -swift-version 6 ${RENDER_CATS_OPT:+-O} \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
```

**Edit `scripts/test-cat-renderer.sh`**, find this text (it occurs exactly once):

```bash
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift tests/CatEngineSupport.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift $APP/IslandScreenGeometry.swift \
```

and replace it with:

```bash
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift tests/CatEngineSupport.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift $APP/IslandScreenGeometry.swift \
```

- [ ] **Step 2: Write the failing tests**

Five new sections of the renderer's test, one of the old ones widened, and one probe point moved. The probe: "the compact detail draws flat fills" samples two points of the head "clear of the eyes"; the coloured eye is wider than the ink one was, and at Ø16 the point at -0.8 R now touches its rim, so it moves to -0.85 R (still clear of the ears, the nose and the edge). The new sections draw a cat at 8 pixels to the point and check: the iris is the coat's colour on all 16 coats, as cats and as kittens, at Ø12, 16, 20 and 24 (both eyes, `irisR` for an odd-eyed coat's right eye; the black coats' is the one flat lighter colour); Midnight, Oreo and Mocha, as cats and as kittens, are that same flat colour at 0.45, 0.8 and 0.9 of the iris's half-width, and Momo keeps its rim and its gradient; the expression shapes are the same pixels with and without the switch; on every coat nothing but the eyes differs; a blink gives up the iris colour; and Ø28 and Ø66 do not change.

**Edit `tests/CatRendererTests.swift`**, find this text (it occurs exactly once):

```swift
            let p = CatPresets.byID("ginger"), unit = D / (2 * p.rx), rx = p.rx * unit, ry = p.ry * unit
            let px = render(120, 120) { R.draw($0, CatLook(preset: p), cx: 60, cy: 60, D: D) }
            // two points of the head, clear of the eyes, the nose, the ears and the edge, even at Ø12
            return Set([(0.55, -0.55), (-0.8, 0.0)].map { fx, fy in
                let x = Int((60 + fx * rx).rounded()), y = Int((60 + fy * ry).rounded()), i = (y * 120 + x) * 4
                return [Int(px[i]), Int(px[i + 1]), Int(px[i + 2])]
```

and replace it with:

```swift
            let p = CatPresets.byID("ginger"), unit = D / (2 * p.rx), rx = p.rx * unit, ry = p.ry * unit
            let px = render(120, 120) { R.draw($0, CatLook(preset: p), cx: 60, cy: 60, D: D) }
            // two points of the head, clear of the eyes (the coloured small eyes are wider than the ink ones were), the nose, the ears and the edge, even at Ø12
            return Set([(0.55, -0.55), (-0.85, 0.0)].map { fx, fy in
                let x = Int((60 + fx * rx).rounded()), y = Int((60 + fy * ry).rounded()), i = (y * 120 + x) * 4
                return [Int(px[i]), Int(px[i + 1]), Int(px[i + 2])]
```

**Edit `tests/CatRendererTests.swift`**, find this text (it occurs exactly once):

```swift
        func at(_ s: String) -> Int { rendererText.range(of: s)?.lowerBound.utf16Offset(in: rendererText) ?? -1 }
        CT.checkTrue("the collar is drawn after the folded ears and before the whiskers (source pin)", at("front: true, flat") > 0 && at("front: true, flat") < at("drawCollar") && at("drawCollar") < at("CatFace.drawWhiskers"))
        CT.finish()
    }
```

and replace it with:

```swift
        func at(_ s: String) -> Int { rendererText.range(of: s)?.lowerBound.utf16Offset(in: rendererText) ?? -1 }
        CT.checkTrue("the collar is drawn after the folded ears and before the whiskers (source pin)", at("front: true, flat") > 0 && at("front: true, flat") < at("drawCollar") && at("drawCollar") < at("CatFace.drawWhiskers"))

        // B: the coloured small eyes (CatSmallEye is the geometry; the colours are the renderer's). A cat is drawn at 8 pixels to the point, so the iris
        // covers whole pixels, and the eye is found from the layout the draw returns.
        CT.section("a compact cat's resting eyes are coloured: the iris is the coat's iris colour, on all 16 coats, as cats and as kittens, at Ø12 to Ø24 (the black coats' is flat)")
        let S8 = 8.0, side8 = 60
        func eyeLook(_ p: CatPreset, _ pose: CatPose = CatPose(), _ eye: CatEye = .pill, ink: Bool = false) -> CatLook {
            var l = CatLook(preset: p, pose: pose, eye: eye); l.inkEyes = ink; return l
        }
        func eyeSheet(_ look: CatLook, _ D: Double) -> (px: [UInt8], L: CatGeometry.Layout) {
            var laid: CatGeometry.Layout?
            let px = render(side8 * Int(S8), side8 * Int(S8)) { cg in
                cg.scaleBy(x: S8, y: S8)
                laid = R.draw(cg, look, cx: 30, cy: 30, D: D, CatDrawOptions(tint: false, badge: false))
            }
            return (px, laid!)
        }
        func rgbAt(_ px: [UInt8], _ x: Double, _ y: Double) -> [Double] {
            let i = (Int(y.rounded(.down)) * side8 * Int(S8) + Int(x.rounded(.down))) * 4
            return [Double(px[i]), Double(px[i + 1]), Double(px[i + 2])]
        }
        var wrongIris: [String] = []
        for id in CatPresets.ids {
            for kitten in [false, true] {
                let base = CatPresets.byID(id), p = kitten ? CatPresets.kitten(of: base) : base
                for D in [12.0, 16, 20, 24] {
                    let sheet = eyeSheet(eyeLook(p), D)
                    for e in sheet.L.eyes {
                        let g = CatSmallEye.eye(.pill, sd: e.sd, R: sheet.L.R, es: 1, open: 1, kitten: kitten, cat: id)!, i = g.iris!
                        let ir = (e.sd > 0 ? p.irisR : nil) ?? p.iris, a = hexRGB(ir[0]), b = hexRGB(ir[1]), t = 0.6 * i.rx / i.r
                        let want = g.flat == true ? hexRGB(CatSmallEye.flatIris(ir)) : (0..<3).map { lerp(a[$0], b[$0], t) }
                        let got = rgbAt(sheet.px, (sheet.L.head.x + e.x + 0.6 * i.rx) * S8, (sheet.L.head.y + e.y) * S8)
                        if zip(got, want).contains(where: { abs($0 - $1) > 14 }) { wrongIris.append("\(id)\(kitten ? " kitten" : "") Ø\(Int(D)) \(e.sd < 0 ? "left" : "right"): got \(got.map { Int($0) }), want \(want.map { Int($0) })") }
                    }
                }
            }
        }
        CT.checkRows("32 cats at four sizes: both eyes are the coat's iris colour at 0.6 of the iris's half-width (the odd-eyed coats' right eye is irisR; the black coats' is the flat lighter colour)", wrongIris)

        CT.section("the black coats' eyes glow: the iris is one flat colour to its edge, with no dark rim, a thin pupil and the catchlight; a normal coat keeps its rim")
        var notFlat: [String] = []
        for id in CatSmallEye.K.bright {
            for kitten in [false, true] {
                let base = CatPresets.byID(id), p = kitten ? CatPresets.kitten(of: base) : base
                for D in [16.0, 20, 24] {
                    let sheet = eyeSheet(eyeLook(p), D)
                    for e in sheet.L.eyes {
                        let g = CatSmallEye.eye(.pill, sd: e.sd, R: sheet.L.R, es: 1, open: 1, kitten: kitten, cat: id)!, i = g.iris!
                        let want = hexRGB(CatSmallEye.flatIris((e.sd > 0 ? p.irisR : nil) ?? p.iris)), cx = sheet.L.head.x + e.x, cy = sheet.L.head.y + e.y
                        // the right of the pupil, in the middle of the iris and just inside its edge (a rim would be dark there)
                        for f in [0.45, 0.8, 0.9] {
                            let got = rgbAt(sheet.px, (cx + f * i.rx) * S8, cy * S8)
                            if zip(got, want).contains(where: { abs($0 - $1) > 14 }) { notFlat.append("\(id)\(kitten ? " kitten" : "") Ø\(Int(D)) \(e.sd < 0 ? "left" : "right") at \(f): got \(got.map { Int($0) }), want \(want.map { Int($0) })") }
                        }
                    }
                }
            }
        }
        CT.checkRows("Midnight, Oreo and Mocha, as cats and as kittens, at Ø16, 20 and 24: the same flat colour at 0.45, 0.8 and 0.9 of the iris's half-width", notFlat)
        let rimmed = eyeSheet(eyeLook(CatPresets.byID("momo")), 24), mo = rimmed.L.eyes[0], mg = CatSmallEye.eye(.pill, sd: mo.sd, R: rimmed.L.R, es: 1, open: 1, cat: "momo")!.iris!
        let momoEdge = rgbAt(rimmed.px, (rimmed.L.head.x + mo.x + 0.97 * mg.rx) * S8, (rimmed.L.head.y + mo.y) * S8), momoMid = rgbAt(rimmed.px, (rimmed.L.head.x + mo.x + 0.45 * mg.rx) * S8, (rimmed.L.head.y + mo.y) * S8)
        CT.checkTrue("a normal coat (Momo) keeps its dark rim and its gradient: its edge is darker than its middle", momoEdge.reduce(0, +) < momoMid.reduce(0, +) - 40)

        CT.section("the expression shapes stay ink, and only the eyes change")
        var changedInk: [String] = []
        for shape in [CatEye.happy, .closed, .line, .flat, .spiral, .heart, .star] {
            for D in [12.0, 20, 27.9] {
                let p = CatPresets.byID("momo")
                if eyeSheet(eyeLook(p, CatPose(), shape), D).px != eyeSheet(eyeLook(p, CatPose(), shape, ink: true), D).px { changedInk.append("\(shape.rawValue) at Ø\(Int(D))") }
            }
        }
        CT.checkRows("happy, closed, line, flat, spiral, heart and star are the same pixels with and without the coloured eyes", changedInk)
        var strayed: [String] = []
        for id in CatPresets.ids {
            let p = CatPresets.byID(id), now = eyeSheet(eyeLook(p), 20), was = eyeSheet(eyeLook(p, ink: true), 20), L = now.L
            if now.px == was.px { strayed.append("\(id): nothing changed"); continue }
            for k in stride(from: 0, to: now.px.count, by: 4) where now.px[k..<k + 4] != was.px[k..<k + 4] {
                let x = Double(k / 4 % (side8 * Int(S8))) / S8, y = Double(k / 4 / (side8 * Int(S8))) / S8
                // within the eye's own frame, 3 px of the head's radius around each eye is where the coloured eye and the ink eye can differ
                if !L.eyes.contains(where: { abs(x - (L.head.x + $0.x)) < 0.4 * L.R && abs(y - (L.head.y + $0.y)) < 0.4 * L.R }) { strayed.append("\(id): a pixel at (\(x), \(y))"); break }
            }
        }
        CT.checkRows("on every coat the resting eye's pixels are the only ones that differ, all within 0.4 R of an eye", strayed)

        CT.section("a blink closes the small eye to a line, and the coat's iris colour is gone")
        var blink = CatPose(); blink.open = 0.06
        let shut = eyeSheet(eyeLook(CatPresets.byID("shrimpy"), blink), 20), open = eyeSheet(eyeLook(CatPresets.byID("shrimpy")), 20)
        let e0 = shut.L.eyes[0], g0 = CatSmallEye.eye(.pill, sd: -1, R: shut.L.R, es: 1, open: 1)!.iris!
        let spot = (shut.L.head.x + e0.x + 0.6 * g0.rx, shut.L.head.y + e0.y)
        let iris = hexRGB(CatPresets.byID("shrimpy").iris[0]), shutRGB = rgbAt(shut.px, spot.0 * S8, spot.1 * S8), openRGB = rgbAt(open.px, spot.0 * S8, spot.1 * S8)
        CT.checkTrue("open: green at the spot; shut: not green", abs(openRGB[1] - iris[1]) < 90 && openRGB != shutRGB && shutRGB[1] - shutRGB[0] < 40)
        CT.checkTrue("a blinking cat differs from an open one", shut.px != open.px)

        CT.section("every cat gets them and a full-detail cat keeps its realistic eye: Ø28 is the same pixels with and without the switch")
        CT.checkTrue("Ø28 and Ø66 do not change", [28.0, 66].allSatisfy { eyeSheet(eyeLook(CatPresets.byID("momo")), $0).px == eyeSheet(eyeLook(CatPresets.byID("momo"), ink: true), $0).px })
        CT.finish()
    }
```

Run: `bash scripts/test-cat-renderer.sh 2>&1 | grep -c "has no member 'inkEyes'"`
Expected: FAIL: `2` (the program cannot be built: the look has no inkEyes field yet).

- [ ] **Step 3: Write the implementation**

`CatLook.inkEyes` and the compact branch of `drawEyes`. The prototype's `smallEyeDraw` is the reference: a radial gradient from `iris[0]` at the centre to `iris[1]` at the gradient radius (`irisR` for the right eye of a coat that has one), the pupil in `Theme.Cat.pupil`, one catchlight in white at 0.92, a rim in the coat's liner colour on the iris's edge, and, for a blink, the closed line in the coat's ink at 0.9 alpha. **The black coats** (Midnight, Oreo, Mocha, their kittens too: `CatFace` passes the preset's `name` as `cat`) glow instead: the iris is filled flat with the lighter of the two iris colours (`CatSmallEye.flatIris`), there is no rim, the pupil is the thinner 0.12 slit, and the catchlight stays.

**Edit `NotchBuddy/Sources/App/CatFace.swift`**, find this text (it occurs exactly once):

```swift
                    inkEye(cg, shape, e.sd, 0.27 * R * s.es, 0.31 * R * s.es, open, look.time, CatDraw.color(p.ink))
                }
            } else {
                inkEye(cg, shape, e.sd, 0.34 * R * s.es, 0.4 * R * s.es, open, look.time, CatDraw.color(p.ink))
```

and replace it with:

```swift
                    inkEye(cg, shape, e.sd, 0.27 * R * s.es, 0.31 * R * s.es, open, look.time, CatDraw.color(p.ink))
                }
            } else if !look.inkEyes, let small = CatSmallEye.eye(shape, sd: e.sd, R: R, es: s.es, open: open, yaw: s.yaw, pitch: s.pitch, kitten: p.kitten == true, cat: p.name) {
                smallEye(cg, p, e.sd, small)
            } else {
                inkEye(cg, shape, e.sd, 0.34 * R * s.es, 0.4 * R * s.es, open, look.time, CatDraw.color(p.ink))
```

**Edit `NotchBuddy/Sources/App/CatFace.swift`**, find this text (it occurs exactly once):

```swift
            cg.restoreGState()
        }
    }

```

and replace it with:

```swift
            cg.restoreGState()
        }
    }

    /// The small coloured eye of the compact detail level (`CatSmallEye` is the geometry, in the eye's own frame): a round iris in the coat's colours
    /// (`irisR` for the right eye of an odd-eyed coat) as a soft gradient, a slit pupil, one catchlight and a thin rim in the liner colour; or, when a
    /// blink or a squint has closed it, the arc in the ink colour. The black coats (`CatSmallEye.K.bright`, their kittens too) fill the iris flat with the lighter of the
    /// two iris colours and draw no rim: they glow like the old ink pill. The prototype's `smallEyeDraw` is the reference.
    private static func smallEye(_ cg: CGContext, _ p: CatPreset, _ sd: Double, _ g: CatSmallEye.Eye) {
        if g.closed, let l = g.line {
            cg.stroke(CatDraw.quad(l.x0, l.y0, l.cx, l.cy, l.x1, l.y1), CatDraw.color(p.ink, alpha: 0.9), width: l.width)
            return
        }
        guard let i = g.iris, let pupil = g.pupil, let light = g.light, let rim = g.rim else { return }
        let ir = (sd > 0 ? p.irisR : nil) ?? p.iris
        if g.flat == true {
            cg.fill(CatDraw.ellipse(0, 0, i.rx, i.ry), CatDraw.color(CatSmallEye.flatIris(ir)))
        } else {
            cg.saveGState()
            cg.clip(CatDraw.ellipse(0, 0, i.rx, i.ry))
            CatDraw.radial(cg, [(0, CatDraw.color(ir[0])), (1, CatDraw.color(ir[1]))], center: (0, 0), r0: 0, r1: i.r)
            cg.restoreGState()
        }
        cg.fill(CatDraw.ellipse(pupil.x, pupil.y, pupil.rx, pupil.ry), CatDraw.color(Theme.Cat.pupil))
        cg.fill(CatDraw.circle(light.x, light.y, light.r), CatDraw.white(0.92))
        if g.flat != true { cg.stroke(CatDraw.ellipse(0, 0, i.rx, i.ry), CatDraw.color(p.liner), width: rim) }
    }

```

**Edit `NotchBuddy/Sources/App/CatLook.swift`**, find this text (it occurs exactly once):

```swift
    /// How open the mouth is, 0 (closed) to 1.3 (the engine adds the state's mouth, its motion and the file-catch spring).
    var mouthOpen = 0.0
    /// The state colour, 0...255, for the tint on the lower head.
    var color: [Double] = [230, 233, 238]
```

and replace it with:

```swift
    /// How open the mouth is, 0 (closed) to 1.3 (the engine adds the state's mouth, its motion and the file-catch spring).
    var mouthOpen = 0.0
    /// Draws the compact detail level's resting eyes as the old flat ink shapes. Only the contact sheet that shows today's look beside the coloured
    /// small eyes sets it; every cat in the app has the coloured ones.
    var inkEyes = false
    /// The state colour, 0...255, for the tint on the lower head.
    var color: [Double] = [230, 233, 238]
```

- [ ] **Step 4: Run it to see it pass**

Run: `bash scripts/test-cat-renderer.sh 2>&1 | tail -1`
Expected: `All tests passed.`

- [ ] **Step 5: Prove the test bites (one-off, never committed)**

Run: `sed -i '' 's/else if !look.inkEyes, let small/else if false, let small/' NotchBuddy/Sources/App/CatFace.swift && bash scripts/test-cat-renderer.sh 2>&1 | grep -c "✗"`
Expected: `4` (the iris colours of 32 cats are gone, the black coats' flat iris is gone, and a blinking cat is no longer told from an open one).

Run: `sed -i '' 's/else if false, let small/else if !look.inkEyes, let small/' NotchBuddy/Sources/App/CatFace.swift && bash scripts/test-cat-renderer.sh 2>&1 | tail -1`
Expected: `All tests passed.`

- [ ] **Step 6: The contact sheets: today's eyes next to the coloured ones**

A new mode of `render-cats.sh`: every coat, as a cat and as a kitten, at Ø12 to Ø24, drawn twice (with `inkEyes`, which is today's look, and without), at rest. It is what the owner looks at, at 1× and at 2× (the device pixel ratio).

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
//                                                                  --scale is the device pixel ratio the readability floors are in: try 1 and 2
//   bash scripts/render-cats.sh --dance --cats shrimpy,momo        one beat of the Apple Music dance in eight frames: the hop alone, then with the head-bob and ears
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

```

and replace it with:

```swift
//                                                                  --scale is the device pixel ratio the readability floors are in: try 1 and 2
//   bash scripts/render-cats.sh --dance --cats shrimpy,momo        one beat of the Apple Music dance in eight frames: the hop alone, then with the head-bob and ears
//   bash scripts/render-cats.sh --eyes --scale 1                   the compact cats' eyes: today's flat ink eyes next to the coloured small eyes, every coat and its kitten at Ø12
//                                                                  to Ø24 (--scale is the device pixel ratio: look at 1 and 2)
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case collars
        case dance
    }

```

and replace it with:

```swift
        case collars
        case dance
        case eyes
    }

```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
            case "--collars": a.mode = .collars
            case "--dance": a.mode = .dance
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

and replace it with:

```swift
            case "--collars": a.mode = .collars
            case "--dance": a.mode = .dance
            case "--eyes": a.mode = .eyes
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case .collars: sheet = collarSheet(a)
        case .dance: sheet = danceSheet(a)
        }
        sheet.write(to: a.out)
```

and replace it with:

```swift
        case .collars: sheet = collarSheet(a)
        case .dance: sheet = danceSheet(a)
        case .eyes: sheet = eyeSheet(a)
        }
        sheet.write(to: a.out)
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
    private static func slotW(_ d: Double) -> Double { max(62, d * 2.2) }

    @MainActor static func ladder(_ a: Args) -> Sheet {
        let widths = a.sizes.map(slotW) + a.kittens.map(slotW)
```

and replace it with:

```swift
    private static func slotW(_ d: Double) -> Double { max(62, d * 2.2) }

    // MARK: Small eyes: today's ink eyes next to the coloured ones

    /// Every coat (as a cat, and as a kitten) at the compact sizes, each drawn twice: with the flat ink eyes the compact cats had, and with the coloured small
    /// eyes. Both rest, looking straight ahead, so the sheet shows nothing but the eye.
    @MainActor static func eyeSheet(_ a: Args) -> Sheet {
        let cols: [(d: Double, kitten: Bool)] = [12, 16, 20, 24].map { ($0, false) } + [12, 16, 20].map { ($0, true) }
        func cellW(_ d: Double) -> Double { max(36, d * 1.5 + 12) }
        let left = 120.0, head = 34.0, rowH = 36.0
        let width = left + cols.map { 2 * cellW($0.d) + 6 }.reduce(0, +) + 8
        let sheet = Sheet(width: width, height: head + rowH * Double(a.cats.count) + 6, scale: a.scale)
        let cg = sheet.cg
        var x = left
        for c in cols {
            let w = cellW(c.d)
            CatDraw.text(cg, c.kitten ? "kitten Ø\(Int(c.d))" : "Ø\(Int(c.d))", x: x + w, y: 11, size: 10, bold: true, color: CatDraw.white(0.85))
            CatDraw.text(cg, "ink", x: x + w / 2, y: 25, size: 9, bold: false, color: CatDraw.white(0.5))
            CatDraw.text(cg, "coloured", x: x + w * 1.5, y: 25, size: 9, bold: false, color: CatDraw.white(0.5))
            x += 2 * w + 6
        }
        for (ri, id) in a.cats.enumerated() {
            let top = head + Double(ri) * rowH, p = CatPresets.byID(id)
            CatDraw.text(cg, p.label, x: 12, y: top + rowH / 2, size: 11, bold: true, color: CatDraw.white(0.9), anchor: .left)
            x = left
            for c in cols {
                let w = cellW(c.d), preset = c.kitten ? CatPresets.kitten(of: p) : p
                for (i, ink) in [true, false].enumerated() {
                    var look = CatLook(preset: preset)
                    look.inkEyes = ink
                    cg.fill(CatDraw.roundRect(x + Double(i) * w + 1, top + 2, w - 2, rowH - 4, 6), CatDraw.black(1))
                    CatRenderer.draw(cg, look, cx: x + Double(i) * w + w / 2, cy: top + rowH / 2 + 1, D: c.d, CatDrawOptions(tint: false, badge: false))
                }
                x += 2 * w + 6
            }
        }
        return sheet
    }

    @MainActor static func ladder(_ a: Args) -> Sheet {
        let widths = a.sizes.map(slotW) + a.kittens.map(slotW)
```

Run: `mkdir -p "${TMPDIR:-/tmp}/b-mac-1" && bash scripts/render-cats.sh --eyes --scale 1 --out "${TMPDIR:-/tmp}/b-mac-1/eyes-1x.png"`
Expected: `wrote …/b-mac-1/eyes-1x.png`. Look at it: sixteen coats in rows, seven columns (Ø12, Ø16, Ø20, Ø24 and kitten Ø12, Ø16, Ø20), each with an "ink" and a "coloured" cell; the coloured cells have iris-coloured eyes (Shrimpy green, Momo gold, Latte blue) and nothing else differs; **Midnight, Oreo and Mocha glow** (a flat yellow or lime iris, a thin black slit, no dark rim; their kittens too), as the ink pills did.

Run: `bash scripts/render-cats.sh --eyes --scale 2 --out "${TMPDIR:-/tmp}/b-mac-1/eyes-2x.png"`
Expected: `wrote …/b-mac-1/eyes-2x.png`. Look at it: the same sheet at 2×, with a slit pupil and one catchlight in each coloured eye, and the three black coats' flat glowing iris.

Run: `bash scripts/render-cat-panel.sh --out "${TMPDIR:-/tmp}/b-mac-1/panel.png" | cut -c1-6`
Expected: `wrote ` (the Debug panel's render script builds with the new file too).

- [ ] **Step 7: The icons keep their ink eyes**

The approved icons are drawn with the real renderer, and the smaller ones (16 and 32 px, and the Windows 32 px) are compact cats. The coloured eyes are for the app's cats (the owner confirmed that the icons keep their ink eyes), so `gen-icons.swift` draws with `inkEyes = true` and the 18 shipped files regenerate byte for byte.

**Edit `scripts/gen-icons.swift`**, find this text (it occurs exactly once):

```swift
            var pose = CatPose()
            pose.tilt = c.tilt; pose.yaw = c.yaw; pose.smile = c.smile
            let look = CatLook(preset: CatPresets.byID(c.id), pose: pose)
            var opts = CatDrawOptions(tint: false)
            opts.badge = false
```

and replace it with:

```swift
            var pose = CatPose()
            pose.tilt = c.tilt; pose.yaw = c.yaw; pose.smile = c.smile
            var look = CatLook(preset: CatPresets.byID(c.id), pose: pose)
            look.inkEyes = true   // the approved icons keep the flat ink eyes at the small sizes: the coloured small eyes are for the app's cats
            var opts = CatDrawOptions(tint: false)
            opts.badge = false
```

**Edit `scripts/gen-icons.swift`**, find this text (it occurs exactly once):

```swift
        let tmp = Bitmap(W, H)
        let pose = CatPose()
        let look = CatLook(preset: CatPresets.byID("momo"), pose: pose)
        var opts = CatDrawOptions(tint: false); opts.badge = false; opts.full = false   // the compact drawing: no whiskers, flat fills, ink eyes
        let L = CatRenderer.draw(tmp.cg, look, cx: 12 * Double(ss), cy: 10.6 * Double(ss), D: 16.4 * Double(ss), opts)
```

and replace it with:

```swift
        let tmp = Bitmap(W, H)
        let pose = CatPose()
        var look = CatLook(preset: CatPresets.byID("momo"), pose: pose)
        look.inkEyes = true
        var opts = CatDrawOptions(tint: false); opts.badge = false; opts.full = false   // the compact drawing: no whiskers, flat fills, ink eyes
        let L = CatRenderer.draw(tmp.cg, look, cx: 12 * Double(ss), cy: 10.6 * Double(ss), D: 16.4 * Double(ss), opts)
```

Run: `d="${TMPDIR:-/tmp}/b-mac-icons"; bash scripts/gen-icons.sh "$d" | tail -1 | cut -c1-30; n=0; for f in $(cd "$d" && find . -type f | sort); do cmp -s "$d/$f" "$f" || n=$((n+1)); done; echo "$n icon files differ"`
Expected: `wrote the 18 icon files under`, then `0 icon files differ`.

Run: `sed -i '' 's/look.inkEyes = true/look.inkEyes = false/' scripts/gen-icons.swift; d="${TMPDIR:-/tmp}/b-mac-icons"; bash scripts/gen-icons.sh "$d" | tail -1 | cut -c1-30; n=0; for f in $(cd "$d" && find . -type f | sort); do cmp -s "$d/$f" "$f" || n=$((n+1)); done; echo "$n icon files differ"; sed -i '' 's/look.inkEyes = false/look.inkEyes = true/' scripts/gen-icons.swift`
Expected: `wrote the 18 icon files under`, then `6 icon files differ` (the 16 and 32 px app icons at 1× and 2×, the Windows 32 px png and the Windows icon file): this is why the icons keep ink eyes. The last command put the line back.

- [ ] **Step 8: The frame time, before and after**

The spec's budget: twelve small cats plus the big one under 2 ms on average, in an optimised build (1.70 to 1.84 ms before in the dry runs, 1.82 to 1.85 after on a quiet machine: the eyes cost about 0.12 ms, which a busy machine shows as 1.79 to 1.84 before against 1.92 to 1.96 after, back to back).

Run: `RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench 2>&1 | tail -1`
Expected: `12 small cats (30 fps) + the big one (60 fps), update and draw, CPU time: avg 1.8x ms, p95 2.8 to 3.0 ms, max … ms per frame (540 frames)`. **The `avg` must be under 2 ms on a quiet machine** and within 0.3 ms of the number written down in Task 0 (the numbers move by 0.1 to 0.2 ms with the machine's load, and a busy one read 2.1: run it twice, or read Task 0's command again next to it).

- [ ] **Step 9: Build**

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `Created project at …` and `** BUILD SUCCEEDED **`.

- [ ] **Step 10: Commit**

```bash
git add NotchBuddy/Sources/App/CatFace.swift NotchBuddy/Sources/App/CatLook.swift tests/CatRendererTests.swift scripts/test-cat-renderer.sh scripts/render-cats.sh scripts/render-cats.swift scripts/render-cat-panel.sh scripts/render-cat-settings.sh scripts/gen-icons.sh scripts/gen-icons.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): every compact cat has coloured small eyes

Below a head of Ø28 the resting eyes (pill, wide, dot, tired, and a wink's left eye) are the coat's iris colour with a slit pupil, one catchlight and a thin rim,
instead of a flat ink pill (the black coats' is a flat, rimless, glowing iris); the expression shapes stay ink. render-cats.sh --eyes draws today's look beside the new one at 1x and 2x. The icons keep their ink
eyes, so the 18 shipped files regenerate byte for byte. The frame bench costs about 0.12 ms: 1.82 ms (1.70 before) on a quiet machine.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Display settings in Swift: `cleanDisplaySettings` and the three keys (stage 2)

**Agent:** `nm-implementer-light`. The code is given in full; the tests prove it.

**Files:**
- Create: `NotchBuddy/Sources/App/CatDisplay.swift`, `tests/CatDisplayTests.swift`, `scripts/test-cat-display.sh`
- Modify: `NotchBuddy/Sources/App/CatSettings.swift` (the store protocol lists its keys), `tests/CatSettingsSupport.swift` (the test store does), `scripts/render-cat-settings.swift` (so does the render script's)

**Interfaces:**
- Consumes: B-0's `cleanDisplaySettings`, `cleanPair`, `cleanAgentCats`, `isPillId`, `isAgentPill`, `defaultAgentCat` (`docs/CAT-CONTRACT.md`, "Display settings"), `tests/fixtures/cat/display-cases.json` (keys `ids`, `modes`, `defaultPair`, `defaultAgentCats`, `maxAgentCats`, `pillIdPattern`, `defaults`, `cases`, `pairs`, `agentCats`, `pillIds`), A's `CatSettingsBacking`, `Personality.isStrictJSON`, `CatPresets.ids`.
- Produces: `CatDisplayMode` (`one`, `perAgent`, `two`, raw values frozen); `CatDisplaySettings` with `mode`, `pair: [String]`, `agentCats: [String: String]`; `CatDisplaySettings.clean(_ raw: Any?)`, `cleanPair`, `cleanAgentCats`, `modeOf`, `isPillId`, `isAgentPill`, `defaultAgentCat`, `isCatId`, `defaultPair`, `defaultAgentCats`, `maxAgentCats`; `catFor(agent:main:)` (stored coat, else the default, else the Main cat); the pure edits `withMode`, `withPairCat(_:slot:)`, `withAgentCat(_:_:)`; `CatDisplaySettings.Key` (`cat.displayMode`, `cat.pair`, the prefix `cat.agentCat.`), `load(from:)`, `save(to:replacing:)`, `pairText`, `json`; and `CatSettingsBacking.allKeys() -> [String]` (the agent coats are one key each, found by their prefix).

- [ ] **Step 1: The stores list their keys**

The display settings keep one UserDefaults key for each agent's coat (`cat.agentCat.<pillId>`), so the store protocol gains `allKeys()`. `UserDefaults` answers with its dictionary's keys; the test store and the render script's store (dictionaries) with theirs.

**Edit `NotchBuddy/Sources/App/CatSettings.swift`**, find this text (it occurs exactly once):

```swift
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: CatSettingsBacking {}

struct CatSettings: Equatable, Sendable {
```

and replace it with:

```swift
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    /// Every key the store holds: the display settings keep one key for each agent's coat (`cat.agentCat.<pillId>`), found by their prefix.
    func allKeys() -> [String]
}

extension UserDefaults: CatSettingsBacking {
    func allKeys() -> [String] { Array(dictionaryRepresentation().keys) }
}

struct CatSettings: Equatable, Sendable {
```

**Edit `scripts/render-cat-settings.swift`**, find this text (it occurs exactly once):

```swift
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}

```

and replace it with:

```swift
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    func allKeys() -> [String] { Array(values.keys) }
}

```

**Edit `tests/CatSettingsSupport.swift`**, find this text (it occurs exactly once):

```swift
    func set(_ value: Any?, forKey key: String) { writes.append(key); values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}

```

and replace it with:

```swift
    func set(_ value: Any?, forKey key: String) { writes.append(key); values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    func allKeys() -> [String] { Array(values.keys) }
}

```

- [ ] **Step 2: Write the failing tests**

The program replays the fixture (30 stored values, 40 pairs, 21 agent maps, 29 pill IDs), pins the frozen words, tests the edits, and runs the UserDefaults keys through a dictionary store (the pair as strict JSON text, only changed keys written, an agent that is gone loses its key, a hostile store, 300 stored agents keep the first 256).

**Create `scripts/test-cat-display.sh`**:

```bash
#!/usr/bin/env bash
# Cat display settings: the clean-up of what Settings → Cat → Display saves (cleanDisplaySettings, cleanPair, cleanAgentCats, the pill-ID rules) against
# display-cases.json, and the UserDefaults keys through an injected dictionary store (no UserDefaults suite).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-display.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/CatDisplayTests.swift \
    -o "$TEST_DIR/cat-display-tests"
"$TEST_DIR/cat-display-tests"
```

**Create `tests/CatDisplayTests.swift`**:

```swift
import Foundation

@main
enum CatDisplayTests {
    typealias D = CatDisplaySettings

    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func strings(_ x: Any?) -> [String] { x as! [String] }

    @MainActor static func main() {
        let fx = CT.fixture("display-cases.json")

        CT.section("the frozen words: the display modes, the default pair, the default coats and the limit")
        CT.check("the three modes, One cat first", CatDisplayMode.allCases.map(\.rawValue), strings(fx["modes"]))
        CT.check("the 16 cat IDs are the contract's", CatPresets.ids, strings(fx["ids"]))
        CT.check("the default pair", D.defaultPair, strings(fx["defaultPair"]))
        CT.checkJSON("the default coats: Claude Code Shrimpy, Codex Momo", got: D.defaultAgentCats, want: fx["defaultAgentCats"]!)
        CT.check("at most 256 pills are kept", D.maxAgentCats, fx["maxAgentCats"] as! Int)
        CT.check("the pill-ID rule is the contract's, in words", fx["pillIdPattern"] as! String, "^[a-z][a-z0-9_-]{1,63}$")

        CT.section("a fresh install: One cat, Shrimpy and Momo, no stored agent coats")
        CT.checkJSON("the defaults are the fixture's", got: D().json, want: fx["defaults"]!)
        CT.checkJSON("clean(nothing) is the defaults", got: D.clean(nil).json, want: fx["defaults"]!)

        CT.section("cleanDisplaySettings: \(rows(fx["cases"]).count) stored values, from nothing to a fully valid one")
        var diffs: [String] = []
        for c in rows(fx["cases"]) {
            let d = CT.diffs(D.clean(c["raw"]).json, c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("every case comes out as the fixture says", diffs)
        let valid = D.clean(rows(fx["cases"]).first { ($0["name"] as! String) == "a fully valid value" }!["raw"])
        CT.checkJSON("cleaning twice changes nothing", got: D.clean(valid.json).json, want: valid.json)

        CT.section("cleanPair: \(rows(fx["pairs"]).count) stored pairs (a string is JSON text, and not strict JSON is not JSON)")
        diffs = []
        for c in rows(fx["pairs"]) {
            let d = CT.diffs(D.cleanPair(c["raw"]), c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("every pair comes out as the fixture says", diffs)
        CT.check("bytes that spell a pair are not a pair either: only an array or its text is", D.cleanPair(Data("[\"momo\",\"ginger\"]".utf8)), D.defaultPair)
        CT.check("a byte-order mark before the text is not JSON", D.cleanPair("\u{FEFF}[\"momo\",\"ginger\"]"), D.defaultPair)

        CT.section("cleanAgentCats: \(rows(fx["agentCats"]).count) stored maps")
        diffs = []
        for c in rows(fx["agentCats"]) {
            let d = CT.diffs(D.cleanAgentCats(c["raw"]), c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("every map comes out as the fixture says", diffs)

        CT.section("pill IDs: \(rows(fx["pillIds"]).count) rows (isPillId, isAgentPill, defaultAgentCat), the whole string and not before a final newline")
        diffs = []
        for r in rows(fx["pillIds"]) {
            let id = r["id"] as! String
            let got: [String: Any] = ["pill": D.isPillId(id), "agent": D.isAgentPill(id), "default": D.defaultAgentCat(id) ?? NSNull()]
            let d = CT.diffs(got, ["pill": r["pill"]!, "agent": r["agent"]!, "default": r["default"] ?? NSNull()])
            if !d.isEmpty { diffs.append("\"\(id)\": \(d.first!)") }
        }
        CT.checkRows("every ID is as the fixture says", diffs)
        CT.checkTrue("a number, nothing and a list are not pill IDs", !D.isPillId(7) && !D.isPillId(nil) && !D.isPillId(["agent_x"]) && !D.isAgentPill(nil) && D.defaultAgentCat(nil) == nil)

        CT.section("the edits of the Settings rows: each changes one thing and returns a clean value")
        let base = D.clean(["displayMode": "two", "pair": ["momo", "ginger"], "agentCats": ["agent_gemini": "latte"]])
        CT.check("the mode", base.withMode(.perAgent), D(mode: .perAgent, pair: ["momo", "ginger"], agentCats: ["agent_gemini": "latte"]))
        CT.check("cat 1 of the pair", base.withPairCat("noodle", slot: 0).pair, ["noodle", "ginger"])
        CT.check("cat 2 of the pair", base.withPairCat("noodle", slot: 1).pair, ["momo", "noodle"])
        CT.check("the same coat for cat 1 and cat 2 makes cat 2 the next coat", base.withPairCat("ginger", slot: 0).pair, ["ginger", "midnight"])
        CT.check("an unknown coat leaves the pair as Shrimpy and Momo", base.withPairCat("tiger", slot: 0).pair, ["shrimpy", "momo"])
        CT.check("a slot that is not 0 or 1 changes nothing", base.withPairCat("noodle", slot: 2).pair, ["momo", "ginger"])
        CT.check("an agent's coat", base.withAgentCat("agent_gemini", "blue").agentCats, ["agent_gemini": "blue"])
        CT.check("an agent that is new", base.withAgentCat("agent_zed", "snow").agentCats, ["agent_gemini": "latte", "agent_zed": "snow"])
        CT.check("a bad coat for an agent with no default is dropped", base.withAgentCat("agent_gemini", "tiger").agentCats, [:])
        CT.check("a bad coat for Codex is its default, Momo", base.withAgentCat("agent_codex", "tiger").agentCats["agent_codex"], "momo")
        CT.check("a name that is not a pill ID is not stored", base.withAgentCat("Not A Pill", "momo").agentCats, ["agent_gemini": "latte"])
        CT.check("the input is never touched", base, D.clean(["displayMode": "two", "pair": ["momo", "ginger"], "agentCats": ["agent_gemini": "latte"]]))

        CT.section("the coat an agent wears: stored, else its default, else the Main cat")
        let wear = D(mode: .perAgent, pair: ["momo", "ginger"], agentCats: ["agent_gemini": "latte", "integration_claude": "oreo"])
        CT.check("a stored coat", wear.catFor(agent: "agent_gemini", main: "snow"), "latte")
        CT.check("a stored coat beats the default", wear.catFor(agent: "integration_claude", main: "snow"), "oreo")
        CT.check("Codex's default, Momo", wear.catFor(agent: "agent_codex", main: "snow"), "momo")
        CT.check("an agent with neither wears the Main cat", wear.catFor(agent: "agent_new", main: "snow"), "snow")
        CT.check("an integration wears the Main cat", wear.catFor(agent: "integration_stripe", main: "snow"), "snow")
        CT.check("and a Main cat that is not a cat is Shrimpy", wear.catFor(agent: "agent_new", main: "tiger"), "shrimpy")

        CT.section("the UserDefaults keys, through a dictionary store")
        let store = MemoryBacking()
        CT.check("an empty store loads the defaults", D.load(from: store), D())
        store.values = ["cat.displayMode": "perAgent", "cat.pair": "[\"noodle\",\"leo\"]", "cat.agentCat.agent_zed": "snow", "cat.agentCat.integration_claude": "oreo", "cat.character": "momo"]
        let loaded = D.load(from: store)
        CT.check("what is stored is loaded (and the other cat keys are not read)", loaded, D(mode: .perAgent, pair: ["noodle", "leo"], agentCats: ["agent_zed": "snow", "integration_claude": "oreo"]))
        let fresh = MemoryBacking()
        loaded.save(to: fresh)
        CT.check("the keys it writes: the mode, the pair as JSON text and one key per agent", fresh.writes, ["cat.displayMode", "cat.pair", "cat.agentCat.agent_zed", "cat.agentCat.integration_claude"])
        CT.check("the pair is stored as strict JSON text", fresh.values["cat.pair"] as? String, "[\"noodle\",\"leo\"]")
        CT.check("and loads back as it was", D.load(from: fresh), loaded)
        let next = loaded.withAgentCat("agent_zed", "puff")
        let before = fresh.writes.count
        next.save(to: fresh, replacing: loaded)
        CT.check("only the key that changed is written", Array(fresh.writes[before...]), ["cat.agentCat.agent_zed"])
        var dropped = next
        dropped.agentCats = [:]
        dropped.save(to: fresh, replacing: next)
        CT.check("an agent that is gone from the map loses its key", Set(fresh.values.keys), ["cat.displayMode", "cat.pair"])

        CT.section("a store that is wrong in every way still loads")
        let wild = MemoryBacking()
        wild.values = ["cat.displayMode": 7, "cat.pair": Data("x".utf8), "cat.agentCat.__proto__": "momo", "cat.agentCat.Bad ID": "momo", "cat.agentCat.agent_x": 7,
                       "cat.agentCat.agent_y": "tiger", "cat.agentCat.integration_claude": "tiger", "cat.agentCat.agent_ok": "momo", "cat.agentCat.": "momo"]
        let tough = D.load(from: wild)
        CT.check("the mode is One cat and the pair Shrimpy and Momo", [tough.mode.rawValue] + tough.pair, ["one", "shrimpy", "momo"])
        CT.checkTrue("Claude Code's bad coat is Shrimpy, agent_ok is kept, and none of the bad IDs and coats are", tough.agentCats["integration_claude"] == "shrimpy" && tough.agentCats["agent_ok"] == "momo" && tough.agentCats["agent_x"] == nil && tough.agentCats["agent_y"] == nil && tough.agentCats.keys.allSatisfy { D.isPillId($0) })
        tough.save(to: wild)
        CT.checkTrue("saving it removes the keys the clean-up refused", !wild.values.keys.contains("cat.agentCat.__proto__") && !wild.values.keys.contains("cat.agentCat.Bad ID") && !wild.values.keys.contains("cat.agentCat.agent_x") && !wild.values.keys.contains("cat.agentCat."))

        CT.section("three hundred stored agents keep the first 256 in code-point order, and the next save drops the rest")
        let crowd = MemoryBacking()
        for i in 0..<300 { crowd.values["cat.agentCat.agent_a\(String(format: "%03d", i))"] = CatPresets.ids[i % 16] }
        let kept = D.load(from: crowd)
        CT.check("256 are kept", kept.agentCats.count, 256)
        CT.checkTrue("agent_a255 is the last one", kept.agentCats["agent_a255"] == CatPresets.ids[255 % 16] && kept.agentCats["agent_a256"] == nil)
        kept.save(to: crowd)
        CT.check("the 44 keys over the limit are removed from the store", crowd.values.keys.filter { $0.hasPrefix("cat.agentCat.") }.count, 256)

        CT.finish()
    }
}
```

Run: `chmod +x scripts/test-cat-display.sh`
Expected: no output.

Run: `bash scripts/test-cat-display.sh 2>&1 | tail -2`
Expected: FAIL: `error opening input file 'NotchBuddy/Sources/App/CatDisplay.swift'`.

- [ ] **Step 3: Write the implementation**

Three things need care. The pill-ID rule is matched on the unicode scalars and not with a regular expression: ICU's `$` lets a trailing newline through, and the fixture holds `agent_x\n`. `cat.pair` is strict JSON text: Foundation's parser takes a comma before `]` and a byte-order mark, which `Personality.isStrictJSON` refuses first. And the cap is on the code-point order of the pill IDs.

**Create `NotchBuddy/Sources/App/CatDisplay.swift`**:

```swift
import Foundation

// What Settings → Cat → Display saves, and how it is cleaned: the display mode, the pair of cats of Two cats mode, and the coat of each agent. Port of the
// "Display modes: the stored settings" section of design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/display-cases.json pins it. It is a
// clean-up of its own: `CatSettings.clean` and settings-cases.json are as they were, and the store cleans the same raw values with both. A settings file can be
// hand-edited, copied from an older build or half written, so everything read back goes through `CatDisplaySettings.clean`: raw in, clean out, never a throw.
// Foundation only. The UserDefaults keys are `cat.displayMode`, `cat.pair` (the JSON text of two cat IDs) and `cat.agentCat.<pillId>` (`CatDisplaySettings.Key`).

/// The display modes: One cat (the default and what shipped), A cat for each agent, and Two cats. Frozen contract values, like the cat IDs.
enum CatDisplayMode: String, CaseIterable, Sendable {
    case one, perAgent, two
}

struct CatDisplaySettings: Equatable, Sendable {
    /// Two cats mode's pair before the user picks: Shrimpy and Momo.
    static let defaultPair = ["shrimpy", "momo"]
    /// What an agent pill wears before the user picks: Claude Code is Shrimpy and Codex is Momo. Every other agent gets a coat when it is first seen.
    static let defaultAgentCats = ["integration_claude": "shrimpy", "agent_codex": "momo"]
    /// A stored map keeps at most this many pills (the first by code-point order of their IDs), so a hostile file cannot grow it without end.
    static let maxAgentCats = 256

    var mode: CatDisplayMode = .one
    /// The two cats of Two cats mode, cat 1 and cat 2: two valid cat IDs, never the same.
    var pair = CatDisplaySettings.defaultPair
    /// The coat each agent pill was given or picked, by pill ID.
    var agentCats: [String: String] = [:]

    // MARK: Stored words

    /// A stored mode to one of the three; anything else (a wrong case, a number, a prototype name) is One cat.
    static func modeOf(_ v: Any?) -> CatDisplayMode { (v as? String).flatMap { CatDisplayMode(rawValue: $0) } ?? .one }

    /// A pill ID: a lowercase letter, then lowercase letters, digits, `_` and `-`, 2 to 64 characters, whole (a trailing newline or space is not a pill ID: an ICU
    /// `$` would let one through). `constructor` and `prototype` are refused, as the contract does.
    static func isPillId(_ v: Any?) -> Bool {
        guard let s = v as? String, s != "constructor", s != "prototype" else { return false }
        let u = Array(s.unicodeScalars)
        guard (2...64).contains(u.count), ("a"..."z").contains(u[0]) else { return false }
        return u.dropFirst().allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-" }
    }

    /// Agent pills are Claude Code's pill (`integration_claude`, despite its prefix) and every `agent_*` pill with something after the prefix. Every other
    /// pill is an integration or an AI provider.
    static func isAgentPill(_ v: Any?) -> Bool {
        guard isPillId(v), let s = v as? String else { return false }
        return s == "integration_claude" || (s.hasPrefix("agent_") && s.count > 6)
    }

    /// The default coat of an agent pill (Claude Code Shrimpy, Codex Momo), or nil for a pill that has none.
    static func defaultAgentCat(_ id: Any?) -> String? { isPillId(id) ? defaultAgentCats[id as! String] : nil }

    static func isCatId(_ v: Any?) -> Bool { (v as? String).map { CatPresets.ids.contains($0) } ?? false }

    // MARK: Cleaning

    /// A stored pair to two cat IDs. It may be an array or the JSON text of one (the Mac stores text; text that is not strict JSON is not JSON). Anything that is
    /// not two valid cat IDs, whole, is Shrimpy and Momo. Two of the same coat make cat 2 the next coat in the 16's order (after the last one, the first).
    static func cleanPair(_ raw: Any?) -> [String] {
        var v = raw
        if let text = v as? String {
            let data = Data(text.utf8)
            v = Personality.isStrictJSON(data) ? try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) : nil
        }
        guard let a = v as? [Any], a.count == 2, a.allSatisfy(isCatId), let first = a[0] as? String, let second = a[1] as? String else { return defaultPair }
        guard first == second else { return [first, second] }
        return [first, CatPresets.ids[(CatPresets.ids.firstIndex(of: second)! + 1) % CatPresets.ids.count]]
    }

    /// A stored map from pill ID to cat ID, cleaned. A pill ID that does not have the shape of one is dropped (`__proto__` and `constructor` included); an unknown
    /// pill ID is kept, because agents come and go. A bad coat becomes the pill's default when it has one, and is dropped otherwise (the first sight of that agent
    /// gives it a coat again). The result holds at most `maxAgentCats` pills, the first in code-point order of their IDs.
    static func cleanAgentCats(_ raw: Any?) -> [String: String] {
        guard let r = raw as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for id in r.keys.filter({ isPillId($0) }).sorted(by: { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes(Array($1.unicodeScalars.map(\.value))) }) {
            if out.count >= maxAgentCats { break }
            if isCatId(r[id]) { out[id] = r[id] as? String } else if let d = defaultAgentCat(id) { out[id] = d }
        }
        return out
    }

    /// Everything Display saves, cleaned. `raw` is a dictionary shaped like `{displayMode, pair, agentCats: {<pillId>: <catId>}}`; anything else gives the
    /// defaults. Never throws.
    static func clean(_ raw: Any?) -> CatDisplaySettings {
        let r = raw as? [String: Any] ?? [:]
        return CatDisplaySettings(mode: modeOf(r["displayMode"]), pair: cleanPair(r["pair"]), agentCats: cleanAgentCats(r["agentCats"]))
    }

    /// The settings as the fixtures hold them, a JSON-shaped dictionary.
    var json: [String: Any] { ["displayMode": mode.rawValue, "pair": pair, "agentCats": agentCats] }

    /// The coat an agent pill wears, as the cast reads it: the one stored for it, else its default, else the Main cat. (A coat is chosen at random only when an
    /// agent is first seen: `CatAgentCats.agentCatFor`.)
    func catFor(agent id: String, main: String) -> String { agentCats[id] ?? CatDisplaySettings.defaultAgentCat(id) ?? CatSettings.catIdOf(main) }

    // MARK: Edits

    /// What one row of Settings changes: each takes this clean value and returns a new clean one with one thing changed, and never touches its input.
    func withMode(_ m: CatDisplayMode) -> CatDisplaySettings { var s = self; s.mode = m; return s }
    /// Cat 1 (`slot` 0) or cat 2 (`slot` 1) of the pair. The pair is cleaned again, so two of the same coat make cat 2 the next one.
    func withPairCat(_ id: String, slot: Int) -> CatDisplaySettings {
        var s = self
        var next = pair
        if next.indices.contains(slot) { next[slot] = id }
        s.pair = CatDisplaySettings.cleanPair(next)
        return s
    }
    /// An agent's coat, from the picker: the map goes through the clean-up again (an unknown pill ID is kept, a bad coat is the pill's default or dropped).
    func withAgentCat(_ id: String, _ cat: String) -> CatDisplaySettings {
        var s = self
        s.agentCats = CatDisplaySettings.cleanAgentCats(agentCats.merging([id: cat]) { _, new in new })
        return s
    }

    // MARK: UserDefaults

    /// The keys: `cat.displayMode`, `cat.pair` (JSON text: `["shrimpy","momo"]`), and one `cat.agentCat.<pillId>` for each agent's coat.
    enum Key {
        static let mode = "cat.displayMode", pair = "cat.pair", agentCatPrefix = "cat.agentCat."
        static func agentCat(_ id: String) -> String { agentCatPrefix + id }
    }

    /// What is stored, cleaned. The agent coats are the keys that start with `cat.agentCat.`; each is read as the object it is, and the clean-up refuses a
    /// bad one. Nothing here can throw.
    static func load(from store: any CatSettingsBacking) -> CatDisplaySettings {
        var raw: [String: Any] = [:], cats: [String: Any] = [:]
        if let v = store.object(forKey: Key.mode) { raw["displayMode"] = v }
        if let v = store.object(forKey: Key.pair) { raw["pair"] = v }
        for key in store.allKeys() where key.hasPrefix(Key.agentCatPrefix) {
            if let v = store.object(forKey: key) { cats[String(key.dropFirst(Key.agentCatPrefix.count))] = v }
        }
        raw["agentCats"] = cats
        return clean(raw)
    }

    /// The pair as it is stored: the JSON text of two cat IDs (valid IDs are plain letters, so nothing needs escaping).
    var pairText: String { "[\"\(pair[0])\",\"\(pair[1])\"]" }

    /// Writes what differs from `old` (everything, when there is no `old`), and removes the agent-coat keys that are no longer in the map (an agent that
    /// "Reset to defaults" dropped, a key the clean-up refused). Only a cleaned value is ever passed in, so nothing that did not go through the clean-up is stored.
    func save(to store: any CatSettingsBacking, replacing old: CatDisplaySettings? = nil) {
        if old?.mode != mode { store.set(mode.rawValue, forKey: Key.mode) }
        if old?.pair != pair { store.set(pairText, forKey: Key.pair) }
        for (id, cat) in agentCats.sorted(by: { $0.key < $1.key }) where old?.agentCats[id] != cat { store.set(cat, forKey: Key.agentCat(id)) }
        for key in store.allKeys() where key.hasPrefix(Key.agentCatPrefix) && agentCats[String(key.dropFirst(Key.agentCatPrefix.count))] == nil {
            store.removeObject(forKey: key)
        }
    }
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `bash scripts/test-cat-display.sh 2>&1 | grep -c "✓"; bash scripts/test-cat-display.sh 2>&1 | tail -1`
Expected: `47`, then `All tests passed.`

Run: `bash scripts/test-cat-settings.sh 2>&1 | tail -1; bash scripts/test-cat-settings-store.sh 2>&1 | tail -1`
Expected: `All tests passed.` twice (A's programs still build and pass with the new protocol requirement).

- [ ] **Step 5: Prove the test bites (one-off, never committed)**

Two of the same coat make cat 2 the next one in the 16's order. Make it the one after that and see the fixture fail.

Run: `sed -i '' 's/firstIndex(of: second)! + 1)/firstIndex(of: second)! + 2)/' NotchBuddy/Sources/App/CatDisplay.swift && bash scripts/test-cat-display.sh 2>&1 | grep -c "✗"`
Expected: `3`.

Run: `sed -i '' 's/firstIndex(of: second)! + 2)/firstIndex(of: second)! + 1)/' NotchBuddy/Sources/App/CatDisplay.swift && bash scripts/test-cat-display.sh 2>&1 | tail -1`
Expected: `All tests passed.`

- [ ] **Step 6: Commit**

```bash
git add NotchBuddy/Sources/App/CatDisplay.swift NotchBuddy/Sources/App/CatSettings.swift tests/CatDisplayTests.swift tests/CatSettingsSupport.swift scripts/test-cat-display.sh scripts/render-cat-settings.swift
git commit -m "feat(cat): the display settings, cleaned and keyed

CatDisplaySettings is the Swift port of cleanDisplaySettings: the mode (One cat, A cat for each agent, Two cats), the pair and the agents' coats, with the
UserDefaults keys cat.displayMode, cat.pair (strict JSON text) and cat.agentCat.<pillId>. The store protocol lists its keys. Replays display-cases.json.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 4: The agents' coats in Swift: `agentCatFor`, the dice and Reset to defaults (stage 2)

**Agent:** `nm-implementer-light`. The code is given in full; the tests prove it.

**Files:**
- Create: `NotchBuddy/Sources/App/CatAgentCats.swift`, `tests/CatAgentCatsTests.swift`, `scripts/test-cat-agent-cats.sh`

**Interfaces:**
- Consumes: Task 3's `CatDisplaySettings` (`cleanAgentCats`, `isAgentPill`, `defaultAgentCat`, `defaultAgentCats`), `CatSettings.catIdOf`, `CatPresets.ids`, `CatRNG`; B-0's `pickCat`, `agentCatFor`, `rerollAgentCat`, `assignAgentCats` and `tests/fixtures/cat/agent-cat-cases.json` (`cases`, `rerolls`, `assigns`, each row naming its random source `rand` (`{seed}`, `{values}` or `{none}`) and the number of `draws`).
- Produces: `CatAgentCats.pickCat(taken:rand:avoid:) -> String`; `CatAgentCats.agentCatFor(_ pillId: String, _ agentCats: [String: String], mainCat: String, rand: () -> Double) -> CatAgentCats.Pick` (`cat`, `agentCats`, `assigned`); `rerollAgentCat(...) -> (cat: String, agentCats: [String: String])`; `assignAgentCats(_ pillIds: [String], _ agentCats: [String: String], mainCat: String, rand: () -> Double) -> [String: String]`.

- [ ] **Step 1: Write the failing tests**

The program replays the 34, 11 and 6 rows with the random source each names and the number of draws each makes (a port that draws one more or one fewer drifts from the rows after it), adds a source that misbehaves (NaN, infinities, a huge number), and checks the rules the fixture states in words: a new agent never gets Shrimpy or Momo while the defaults are in force, nor the Main cat; a stored coat is never changed by itself; with all 16 taken the least-used is chosen without drawing; and 2000 random islands keep the invariants.

**Create `scripts/test-cat-agent-cats.sh`**:

```bash
#!/usr/bin/env bash
# Cat agent coats: giving an agent its cat (agentCatFor, the dice, Reset to defaults) against agent-cat-cases.json, with the random source the rows name and
# how many numbers each call draws, and the rules the fixture cannot write down (a random source that misbehaves, defaults that count as taken).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-agent-cats.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift \
    tests/CatTestSupport.swift tests/CatAgentCatsTests.swift \
    -o "$TEST_DIR/cat-agent-cats-tests"
"$TEST_DIR/cat-agent-cats-tests"
```

**Create `tests/CatAgentCatsTests.swift`**:

```swift
import Foundation

@main
enum CatAgentCatsTests {
    typealias A = CatAgentCats

    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func map(_ x: Any?) -> [String: String] { (x as? [String: String]) ?? [:] }

    /// The random source a fixture row names: `{seed: n}` is the contract's seeded generator, `{values: [...]}` those numbers and then 0, and `{none: true}`
    /// must never be called. It counts its draws.
    final class Source {
        var draws = 0, forbidden = false
        private let rng: CatRNG?, values: [Double]?, none: Bool
        init(_ spec: Any?) {
            let s = spec as? [String: Any] ?? [:]
            rng = (s["seed"] as? NSNumber).map { CatRNG(seed: UInt32(truncating: $0)) }
            values = (s["values"] as? [NSNumber])?.map(\.doubleValue)
            none = s["none"] as? Bool ?? false
        }
        func next() -> Double {
            draws += 1
            if none { forbidden = true; return 0 }
            if let rng { return rng.next() }
            if let values { return draws <= values.count ? values[draws - 1] : 0 }
            return 0
        }
    }

    @MainActor static func main() {
        let fx = CT.fixture("agent-cat-cases.json")

        CT.section("the frozen values: the 16 cat IDs and the default coats")
        CT.check("the cat IDs are the contract's", CatPresets.ids, fx["ids"] as! [String])
        CT.checkJSON("the default coats are the fixture's", got: CatDisplaySettings.defaultAgentCats, want: fx["defaults"]!)

        CT.section("agentCatFor: \(rows(fx["cases"]).count) rows, and how many numbers each draws")
        var diffs: [String] = []
        for c in rows(fx["cases"]) {
            let src = Source(c["rand"])
            let got = A.agentCatFor(c["pill"] as! String, map(c["agentCats"]), mainCat: c["mainCat"] as! String, rand: src.next)
            let json: [String: Any] = ["cat": got.cat, "agentCats": got.agentCats, "assigned": got.assigned]
            var d = CT.diffs(json, c["out"]!)
            if src.draws != c["draws"] as! Int { d.append("draws \(src.draws) vs \(c["draws"]!)") }
            if src.forbidden { d.append("rand was called when it must not be") }
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("every row is as the fixture says, with the same number of draws", diffs)

        CT.section("rerollAgentCat, the dice: \(rows(fx["rerolls"]).count) rows")
        diffs = []
        for c in rows(fx["rerolls"]) {
            let src = Source(c["rand"])
            let got = A.rerollAgentCat(c["pill"] as! String, map(c["agentCats"]), mainCat: c["mainCat"] as! String, rand: src.next)
            var d = CT.diffs(["cat": got.cat, "agentCats": got.agentCats] as [String: Any], c["out"]!)
            if src.draws != c["draws"] as! Int { d.append("draws \(src.draws) vs \(c["draws"]!)") }
            if src.forbidden { d.append("rand was called when it must not be") }
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("every row is as the fixture says", diffs)

        CT.section("assignAgentCats, Reset to defaults and the first launch: \(rows(fx["assigns"]).count) rows")
        diffs = []
        for c in rows(fx["assigns"]) {
            let src = Source(c["rand"])
            let got = A.assignAgentCats((c["pills"] as? [String]) ?? [], map(c["agentCats"]), mainCat: c["mainCat"] as! String, rand: src.next)
            var d = CT.diffs(["agentCats": got] as [String: Any], c["out"]!)
            if src.draws != c["draws"] as! Int { d.append("draws \(src.draws) vs \(c["draws"]!)") }
            if src.forbidden { d.append("rand was called when it must not be") }
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("every row is as the fixture says", diffs)

        CT.section("a random source that misbehaves (JSON cannot write NaN or infinity)")
        func first(_ r: Double, taken: [String] = ["shrimpy", "momo"]) -> String { A.pickCat(taken: taken, rand: { r }) }
        CT.check("NaN is the first free coat", first(.nan), "ginger")
        CT.check("infinity is the first free coat", first(.infinity), "ginger")
        CT.check("minus infinity is the first free coat", first(-.infinity), "ginger")
        CT.check("a huge number is the last free coat", first(1e300), "noodle")
        CT.check("a tiny negative number is the first free coat", first(-1e-300), "ginger")
        CT.check("just under 1 is the last free coat", first(0.99999999), "noodle")

        CT.section("the rules the fixture states in words")
        let a = A.agentCatFor("agent_gemini", [:], mainCat: "ginger", rand: { 0 })
        CT.check("a new agent never gets Shrimpy or Momo while Claude Code and Codex are on their defaults, nor the Main cat", [a.cat, a.assigned], ["midnight", true] as [AnyHashable])
        let again = A.agentCatFor("agent_gemini", a.agentCats, mainCat: "ginger", rand: { Double.nan })
        CT.check("and keeps it: asked again it gives the stored coat and draws nothing", [again.cat, again.assigned] as [AnyHashable], [a.cat, false] as [AnyHashable])
        let crowded = Dictionary(uniqueKeysWithValues: CatPresets.ids.dropFirst(2).enumerated().map { ("agent_x\(String(format: "%02d", $0.offset))", $0.element) })
        let full = A.agentCatFor("agent_new", crowded, mainCat: "shrimpy", rand: { fatalError("all 16 are taken: nothing is drawn") })
        CT.check("with all 16 taken the least-used coat is chosen without drawing: Shrimpy (used by Claude Code and the Main cat) is not the least", full.cat, "momo")
        CT.checkTrue("the choice for a new agent is always one of the 16 and is stored", CatPresets.ids.contains(full.cat) && full.assigned)

        CT.section("every call keeps the invariants: a coat from the 16, stored once chosen, never changed by itself, free when one is free")
        var rng = CatRNG(seed: 99), bad: [String] = []
        for round in 0..<2000 {
            var stored: [String: String] = [:]
            for i in 0..<Int(rng.next() * 18) { stored["agent_s\(i)"] = CatPresets.ids[Int(rng.next() * 16)] }
            if rng.next() < 0.3 { stored["integration_claude"] = CatPresets.ids[Int(rng.next() * 16)] }
            let main = CatPresets.ids[Int(rng.next() * 16)], draw = CatRNG(seed: UInt32(round))
            let got = A.agentCatFor("agent_new", stored, mainCat: main, rand: draw.next)
            let used = Set(CatDisplaySettings.defaultAgentCats.merging(stored) { _, s in s }.values).union([main])
            if !CatPresets.ids.contains(got.cat) { bad.append("round \(round): not a coat") }
            if used.count < 16 && used.contains(got.cat) { bad.append("round \(round): \(got.cat) is taken but a coat is free") }
            if got.assigned && got.agentCats["agent_new"] != got.cat { bad.append("round \(round): assigned but not stored") }
            let second = A.agentCatFor("agent_new", got.agentCats, mainCat: main, rand: { fatalError("a stored coat draws nothing") })
            if got.assigned && second.cat != got.cat { bad.append("round \(round): the coat changed by itself") }
            let dice = A.rerollAgentCat("agent_new", got.agentCats, mainCat: main, rand: CatRNG(seed: UInt32(round + 5)).next)
            if dice.cat == got.cat || dice.agentCats["agent_new"] != dice.cat { bad.append("round \(round): the dice gave the same coat or did not store it") }
        }
        CT.checkRows("2000 random islands", bad)

        CT.finish()
    }
}
```

Run: `chmod +x scripts/test-cat-agent-cats.sh`
Expected: no output.

Run: `bash scripts/test-cat-agent-cats.sh 2>&1 | tail -2`
Expected: FAIL: `error opening input file 'NotchBuddy/Sources/App/CatAgentCats.swift'`.

- [ ] **Step 2: Write the implementation**

`rand` is called once, and only when a coat is chosen at random (a free one exists); the least-used rule, stored coats, defaults and a pill that is not an agent draw nothing. A number that is not finite is 0, and the index is held to the last free coat before it becomes an `Int` (a huge number would trap).

**Create `NotchBuddy/Sources/App/CatAgentCats.swift`**:

```swift
import Foundation

// Giving agents their cats (Settings → Cat → Display, A cat for each agent): the coat of an agent pill is the one stored for it, else its default (Claude Code
// is Shrimpy, Codex is Momo), else a coat chosen when the agent is first seen, at random from those no other agent and not the Main cat wears. Port of the
// "Display modes: giving agents their cats" section of design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/agent-cat-cases.json pins it,
// including how many random numbers each call draws. Random numbers come in only through `rand`, which the app gives `Double.random(in: 0..<1)` and a test a
// counted seeded source. Foundation only.

enum CatAgentCats {
    /// What `agentCatFor` returns: the coat, the cleaned map (with the pill added when `assigned`), and whether the map gained the pill, which is the cue to
    /// store it and never change it by itself afterwards.
    struct Pick: Equatable {
        var cat: String
        var agentCats: [String: String]
        var assigned: Bool
    }

    /// One coat for a new agent. `taken` lists the cat IDs already in use (a coat used twice is listed twice), `rand` returns 0 up to, not including, 1, and `avoid`
    /// is a coat that is never chosen. A coat nobody uses is chosen at random (`rand` is called once, and only then); when every coat is in use the least-used one
    /// is chosen, ties broken in the 16's order (`rand` is not called). A `rand` that is not a number is 0, one under 0 is the first free coat and one of 1 or more is
    /// the last.
    static func pickCat(taken: [String], rand: () -> Double, avoid: String? = nil) -> String {
        var use: [String: Int] = [:]
        for c in taken { use[c, default: 0] += 1 }
        let pool = CatPresets.ids.filter { $0 != avoid }, free = pool.filter { use[$0] == nil }
        if !free.isEmpty {
            let r = rand(), x = floor(r.isFinite ? r * Double(free.count) : 0)
            return free[Int(min(Double(free.count - 1), max(0, x)))]
        }
        var best = pool[0]
        for c in pool where use[c, default: 0] < use[best, default: 0] { best = c }
        return best
    }

    /// The cat of an agent pill: its stored coat, else its default, else a coat chosen now: random, from those used neither by another agent (a stored one, or a
    /// default that no stored coat has replaced) nor as the Main cat; when all 16 are taken, the least-used (see `pickCat`). A pill that is not an agent pill (an
    /// integration, or an ID that is not a pill ID) gets the Main cat and is never stored.
    static func agentCatFor(_ pillId: String, _ agentCats: [String: String], mainCat: String, rand: () -> Double) -> Pick {
        let map = CatDisplaySettings.cleanAgentCats(agentCats), main = CatSettings.catIdOf(mainCat)
        guard CatDisplaySettings.isAgentPill(pillId) else { return Pick(cat: main, agentCats: map, assigned: false) }
        if let own = map[pillId] { return Pick(cat: own, agentCats: map, assigned: false) }
        if let d = CatDisplaySettings.defaultAgentCat(pillId) { return Pick(cat: d, agentCats: map, assigned: false) }
        let inUse = CatDisplaySettings.defaultAgentCats.merging(map) { _, stored in stored }
        let cat = pickCat(taken: Array(inUse.values) + [main], rand: rand), next = CatDisplaySettings.cleanAgentCats(map.merging([pillId: cat]) { _, new in new })
        return Pick(cat: cat, agentCats: next, assigned: next[pillId] != nil)
    }

    /// The dice button: a new random coat for one agent. Its current coat (stored or default) is never chosen again, and the rest is `agentCatFor`'s rule, with
    /// this agent's own coat set aside. Always stored, a default agent included.
    static func rerollAgentCat(_ pillId: String, _ agentCats: [String: String], mainCat: String, rand: () -> Double) -> (cat: String, agentCats: [String: String]) {
        let map = CatDisplaySettings.cleanAgentCats(agentCats), main = CatSettings.catIdOf(mainCat)
        guard CatDisplaySettings.isAgentPill(pillId) else { return (main, map) }
        var eff = CatDisplaySettings.defaultAgentCats.merging(map) { _, stored in stored }
        let current = eff.removeValue(forKey: pillId)
        let cat = pickCat(taken: Array(eff.values) + [main], rand: rand, avoid: current)
        return (cat, CatDisplaySettings.cleanAgentCats(map.merging([pillId: cat]) { _, new in new }))
    }

    /// `agentCatFor` for each pill in turn (integrations are skipped): the map after every agent has a coat. "Reset to defaults" is this with an empty map.
    static func assignAgentCats(_ pillIds: [String], _ agentCats: [String: String], mainCat: String, rand: () -> Double) -> [String: String] {
        var map = CatDisplaySettings.cleanAgentCats(agentCats)
        for id in pillIds { map = agentCatFor(id, map, mainCat: mainCat, rand: rand).agentCats }
        return map
    }
}
```

- [ ] **Step 3: Run it to see it pass**

Run: `bash scripts/test-cat-agent-cats.sh 2>&1 | grep -c "✓"; bash scripts/test-cat-agent-cats.sh 2>&1 | tail -1`
Expected: `16`, then `All tests passed.`

- [ ] **Step 4: Prove the test bites (one-off, never committed)**

When all 16 are taken the least-used coat is chosen and a tie goes to the first in the 16's order. Let a tie go to the last and see the rows fail.

Run: `sed -i '' 's/for c in pool where use\[c, default: 0\] < use\[best, default: 0\]/for c in pool where use[c, default: 0] <= use[best, default: 0]/' NotchBuddy/Sources/App/CatAgentCats.swift && bash scripts/test-cat-agent-cats.sh 2>&1 | grep -c "✗"`
Expected: `4`.

Run: `sed -i '' 's/for c in pool where use\[c, default: 0\] <= use\[best, default: 0\]/for c in pool where use[c, default: 0] < use[best, default: 0]/' NotchBuddy/Sources/App/CatAgentCats.swift && bash scripts/test-cat-agent-cats.sh 2>&1 | tail -1`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/App/CatAgentCats.swift tests/CatAgentCatsTests.swift scripts/test-cat-agent-cats.sh
git commit -m "feat(cat): giving an agent its cat

CatAgentCats ports agentCatFor, the dice (rerollAgentCat) and assignAgentCats (Reset to defaults): the stored coat, else the default (Claude Code Shrimpy, Codex
Momo), else a random coat no other agent and not the Main cat wears, else the least-used. Replays agent-cat-cases.json with the random source and the number
of draws of every row.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 5: The cast in Swift: `castOf` and `cast-cases.json` (stages 2 and 3)

**Agent:** `nm-implementer-light`. The code is given in full; the tests prove it.

**Files:**
- Create: `NotchBuddy/Sources/App/CatCast.swift`, `tests/CatCastTests.swift`, `scripts/test-cat-cast.sh`

**Interfaces:**
- Consumes: Task 3's `CatDisplayMode` and `CatDisplaySettings` (`cleanPair`, `cleanAgentCats`, `isPillId`, `isAgentPill`, `defaultAgentCat`), `CatSettings.catIdOf`, `CatState`; B-0's `castOf` and `busyRank` and `tests/fixtures/cat/cast-cases.json` (`modes`, `pillRow`, `states`, `busyRank`, `cases`: 136 rows).
- Produces: `CatCast.of(_ mode: CatDisplayMode, tasks: [CatCast.Pill], focusId: String?, mainCat: Any?, pair: Any?, agentCats: Any?) -> CatCast.Result` with `big`, `second` (nil outside Two cats mode), `pills`, `drop` and `greeting` (`cat`, `pair`, `sessions`); `CatCast.Pill(id:state:last:)`, `Spot`, `PillCat`, `Greeting`; `CatCast.busyRank(_:)`; `CatCast.pillRow` (4).

- [ ] **Step 1: Write the failing tests**

The program replays the 136 rows (44 scenarios, the rankings and the hostile islands, in each of the three modes, and four unknown modes) through the app's own types, adds a time that is not finite, states the rules in words, and runs 500 hostile islands in each mode (never more than four pills, nothing shown twice, an integration is never cat 2, cat 2 only in Two cats mode).

**Create `scripts/test-cat-cast.sh`**:

```bash
#!/usr/bin/env bash
# Cat cast: which cat appears where in each display mode (CatCast.of, busyRank) against cast-cases.json, and the inputs the fixture cannot write (a time that is
# not a number, a hostile island).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-cast.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatCast.swift \
    tests/CatTestSupport.swift tests/CatCastTests.swift \
    -o "$TEST_DIR/cat-cast-tests"
"$TEST_DIR/cat-cast-tests"
```

**Create `tests/CatCastTests.swift`**:

```swift
import Foundation

@main
enum CatCastTests {
    typealias C = CatCast

    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }

    /// A JSON number; a boolean, text and null are not numbers (the contract takes them as 0).
    static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    /// The fixture's island, in the app's own types: a state that is not one of the eleven is idle, a time that is not a number is 0, and an entry that is not
    /// an object with an ID is skipped (the app never builds one).
    static func pills(_ raw: Any?) -> [C.Pill] {
        (raw as? [Any] ?? []).compactMap { entry in
            guard let t = entry as? [String: Any], let id = t["id"] as? String else { return nil }
            return C.Pill(id: id, state: (t["state"] as? String).flatMap { CatState(rawValue: $0) } ?? .idle, last: number(t["last"]) ?? 0)
        }
    }

    @MainActor static func main() {
        let fx = CT.fixture("cast-cases.json")

        CT.section("the frozen values: the modes, the states, the row and the ranks")
        CT.check("the modes", CatDisplayMode.allCases.map(\.rawValue), fx["modes"] as! [String])
        CT.check("the 11 states", CatState.allCases.map(\.rawValue), fx["states"] as! [String])
        CT.check("the row and the grid hold four", C.pillRow, fx["pillRow"] as! Int)
        var diffs: [String] = []
        for r in rows(fx["busyRank"]) {
            let got = (r["state"] as? String).flatMap { CatState(rawValue: $0) }.map { C.busyRank($0) } ?? 3
            if got != r["rank"] as! Int { diffs.append("\(r["state"]!): \(got)") }
        }
        CT.checkRows("busyRank: waiting for you 0, error 1, busy 2, anything else 3 (a state that is not one is idle)", diffs)

        CT.section("castOf: \(rows(fx["cases"]).count) rows, 44 scenarios, rankings and hostile islands in each of the three modes, and four unknown modes")
        diffs = []
        for c in rows(fx["cases"]) {
            let input = c["input"] as? [String: Any] ?? [:]
            let got = C.of(CatDisplaySettings.modeOf(c["mode"]), tasks: pills(input["tasks"]), focusId: input["focusId"] as? String, mainCat: input["mainCat"], pair: input["pair"], agentCats: input["agentCats"])
            let d = CT.diffs(got.json, c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"]!) [\(c["mode"]!)]: \(d.first!)") }
        }
        CT.checkRows("every row comes out as the fixture says", diffs)

        CT.section("a time that is not finite (JSON cannot write it): the pill is as if it had never had an event")
        func two(_ lasts: [Double]) -> String? {
            let ps = lasts.enumerated().map { C.Pill(id: "agent_\(["a", "b", "c"][$0.offset])", state: .working, last: $0.element) }
            return C.of(.two, tasks: [C.Pill(id: "integration_claude", state: .working, last: 5)] + ps, focusId: "integration_claude", mainCat: "shrimpy", pair: nil, agentCats: nil).second?.pill
        }
        CT.check("the most recent of the busy agents is cat 2", two([10, 30, 20]), "agent_b")
        CT.check("NaN is 0: the others win", two([.nan, 3, 2]), "agent_b")
        CT.check("infinity is 0 too (it is not a time)", two([.infinity, 3, 2]), "agent_b")
        CT.check("with all times 0 the first in the app's order wins", two([.nan, .infinity, -.infinity]), "agent_a")

        CT.section("the rules in words")
        let island = [C.Pill(id: "integration_claude", state: .working, last: 100), C.Pill(id: "agent_codex", state: .approval, last: 90), C.Pill(id: "agent_gemini", state: .thinking, last: 95),
                      C.Pill(id: "integration_stripe", state: .idle, last: 1)]
        let r = C.of(.two, tasks: island, focusId: "integration_claude", mainCat: "ginger", pair: ["momo", "latte"], agentCats: nil)
        CT.check("Two cats: cat 1 is the focused pill's, cat 2 the agent that waits for you, and the pair's coats are the cats", [r.big.pill, r.big.cat, r.second?.pill, r.second?.cat], ["integration_claude", "momo", "agent_codex", "latte"])
        CT.check("the second agent leaves the row, and the row wears the Main cat", r.pills.map { "\($0.pill)=\($0.cat)" }, ["agent_gemini=ginger", "integration_stripe=ginger"])
        CT.check("the drop view and the ghost wear the big cat's coat", r.drop, "momo")
        CT.check("the greeting: the Main cat falls in and the pair arrives together", [r.greeting.cat] + (r.greeting.pair ?? []), ["ginger", "momo", "latte"])
        let p = C.of(.perAgent, tasks: island, focusId: "agent_gemini", mainCat: "ginger", pair: nil, agentCats: ["agent_gemini": "snow"])
        CT.check("A cat for each agent: the big cat wears the focused agent's, the row each agent's own and integrations the Main cat", [p.big.cat] + p.pills.map(\.cat), ["snow", "shrimpy", "momo", "ginger"])
        CT.check("and the session cats are the row's cats, with the Main cat for the empty cell", p.greeting.sessions, ["shrimpy", "momo", "ginger", "ginger"])
        let o = C.of(.one, tasks: island, focusId: "agent_gemini", mainCat: "ginger", pair: ["momo", "latte"], agentCats: ["agent_gemini": "snow"])
        CT.check("One cat: the Main cat everywhere, whatever else is stored", [o.big.cat, o.drop] + o.pills.map(\.cat) + o.greeting.sessions, ["ginger", "ginger", "ginger", "ginger", "ginger", "ginger", "ginger", "ginger", "ginger"])
        CT.checkTrue("and no second cat, no pair", o.second == nil && o.greeting.pair == nil)

        CT.section("an island that is wrong in every way never throws and shows nothing twice")
        var bad: [String] = []
        var seed: UInt64 = 3
        func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        let ids = ["integration_claude", "agent_codex", "agent_gemini", "agent_x", "integration_stripe", "ai_openai", "Bad ID", "__proto__", "", "agent_"]
        for n in 0..<500 {
            let ps = (0..<Int(next() * 9)).map { _ in C.Pill(id: ids[Int(next() * Double(ids.count))], state: CatState.allCases[Int(next() * 11)], last: next() < 0.2 ? .nan : next() * 100) }
            let focus: String? = next() < 0.2 ? nil : ids[Int(next() * Double(ids.count))]
            for mode in CatDisplayMode.allCases {
                let r = C.of(mode, tasks: ps, focusId: focus, mainCat: "tiger", pair: "junk", agentCats: [ids[Int(next() * 4)]: "tiger"])
                let shown = r.pills.map(\.pill) + [r.big.pill, r.second?.pill].compactMap { $0 }
                if r.pills.count > 4 { bad.append("island \(n) \(mode): more than four pills") }
                if Set(r.pills.map(\.pill)).count != r.pills.count { bad.append("island \(n) \(mode): a pill twice in the row") }
                if r.pills.contains(where: { $0.pill == r.big.pill || $0.pill == r.second?.pill }) { bad.append("island \(n) \(mode): a pill in the row and the big spots") }
                if shown.contains(where: { !CatDisplaySettings.isPillId($0) }) { bad.append("island \(n) \(mode): a name that is not a pill ID") }
                if let s = r.second?.pill, !CatDisplaySettings.isAgentPill(s) { bad.append("island \(n) \(mode): an integration is cat 2") }
                if (mode == .two) != (r.second != nil) { bad.append("island \(n) \(mode): cat 2 is there only in Two cats mode") }
                if r.greeting.sessions.count != 4 || !CatPresets.ids.contains(r.big.cat) { bad.append("island \(n) \(mode): not four sessions or not a coat") }
            }
        }
        CT.checkRows("500 islands in each mode", bad)

        CT.finish()
    }
}
```

Run: `chmod +x scripts/test-cat-cast.sh`
Expected: no output.

Run: `bash scripts/test-cat-cast.sh 2>&1 | tail -2`
Expected: FAIL: `error opening input file 'NotchBuddy/Sources/App/CatCast.swift'`.

- [ ] **Step 2: Write the implementation**

The cast reads stored coats and defaults only and never draws a random number: an agent with neither wears the Main cat until `agentCatFor` has given it one (Task 9 does that when the agent first appears). The busiest other agent is the first agent pill other than the focused one by `busyRank`, then the most recent `last`, then its place in the app's order.

**Create `NotchBuddy/Sources/App/CatCast.swift`**:

```swift
import Foundation

// Which cat appears where (the "cast"): a cat stands for an agent's pill, the big cat shows the focused pill, and `CatCast.of` says, for the chosen display mode,
// which coat each place wears. Port of the "Display modes: which cat appears where" section of design/prototype/cat-core.js (the tie-breaker);
// tests/fixtures/cat/cast-cases.json pins it. It reads stored coats and defaults only and never draws a random number: an agent with neither wears the Main cat
// until `CatAgentCats.agentCatFor` has given it a coat, which the app does when it first sees the agent. Foundation only.
//   one:      the Main cat everywhere.
//   perAgent: the focused agent's cat is the big cat (the Main cat when the focus is an integration or nothing); every agent pill wears its agent's cat;
//             integration pills wear the Main cat.
//   two:      the pair: cat 1 is the big cat and shows the focused pill, cat 2 shows the busiest other agent; pills wear the Main cat.

enum CatCast {
    /// The most pills the row and the 2x2 grid hold (`others.prefix(4)`).
    static let pillRow = 4

    /// One pill of the island, in the app's own order: its ID, the state its cat shows, and the time of its last event (ms, any one clock; not a number is 0).
    struct Pill: Equatable {
        var id: String
        var state: CatState
        var last: Double
    }
    /// The coat a place wears and the pill it shows (nil: none, for the big cat when nothing is focused, and for cat 2 when there is no other agent).
    struct Spot: Equatable { var pill: String?; var cat: String }
    struct PillCat: Equatable { var pill: String; var cat: String }
    /// The launch greeting: `cat` falls in (the Main cat in every mode), `pair` is nil or, in Two cats mode, the pair that arrives together, and `sessions` are
    /// the four session cats in the grid's cell order (top left, top right, bottom left, bottom right).
    struct Greeting: Equatable { var cat: String; var pair: [String]?; var sessions: [String] }

    /// `big`: the big cat, compact or expanded. `second`: nil, or in Two cats mode pair cat 2 and the busiest other agent. `pills`: the row and the 2x2 grid, the
    /// tasks other than the focused one (and, in Two cats mode, other than cat 2's), the first four, in the app's order. `drop`: the drop view's and the drag ghost's coat,
    /// the big cat's.
    struct Result: Equatable {
        var mode: CatDisplayMode
        var big: Spot
        var second: Spot?
        var pills: [PillCat]
        var drop: String
        var greeting: Greeting

        /// As the fixtures hold it, a JSON-shaped dictionary.
        var json: [String: Any] {
            func spot(_ s: Spot) -> [String: Any] { ["pill": s.pill ?? NSNull(), "cat": s.cat] }
            return ["mode": mode.rawValue, "big": spot(big), "second": second.map(spot) ?? NSNull(), "pills": pills.map { ["pill": $0.pill, "cat": $0.cat] },
                    "drop": drop, "greeting": ["cat": greeting.cat, "pair": greeting.pair ?? NSNull(), "sessions": greeting.sessions] as [String: Any]]
        }
    }

    /// How busy an agent is, for the busiest-other rule: 0 waits for you (an approval or a question), 1 an error, 2 working, thinking or searching, 3 anything else.
    static func busyRank(_ s: CatState) -> Int {
        s == .approval || s == .question ? 0 : s == .error ? 1 : s.isBusy ? 2 : 3
    }

    /// The cast of one mode. `tasks` are the island's pills in the app's order (an ID that is not a pill ID is skipped, and a pill listed twice counts once),
    /// `focusId` the focused pill, `mainCat`, `pair` and `agentCats` as stored (they are cleaned here, so a raw value is fine). The busiest other agent (Two cats mode)
    /// is the agent pill other than the focused one that ranks first by `busyRank`, then by the most recent `last`, then by its place in `tasks`; an integration is
    /// never chosen, and with no other agent pill `second.pill` is nil (cat 2 idles, with no badge).
    static func of(_ mode: CatDisplayMode, tasks: [Pill], focusId: String?, mainCat: Any?, pair: Any?, agentCats: Any?) -> Result {
        let main = CatSettings.catIdOf(mainCat), pr = CatDisplaySettings.cleanPair(pair), map = CatDisplaySettings.cleanAgentCats(agentCats)
        var seen = Set<String>(), list: [Pill] = []
        for t in tasks where CatDisplaySettings.isPillId(t.id) && !seen.contains(t.id) {
            seen.insert(t.id)
            list.append(Pill(id: t.id, state: t.state, last: t.last.isFinite ? t.last : 0))
        }
        let focus = focusId.flatMap { CatDisplaySettings.isPillId($0) ? $0 : nil }
        func catOf(_ id: String?) -> String {
            guard mode == .perAgent, let id, CatDisplaySettings.isAgentPill(id) else { return main }
            return map[id] ?? CatDisplaySettings.defaultAgentCat(id) ?? main
        }
        let big = Spot(pill: focus, cat: mode == .two ? pr[0] : catOf(focus))
        var second: Spot?
        if mode == .two {
            var best: (id: String, rank: Int, last: Double, at: Int)?
            for (i, t) in list.enumerated() where t.id != focus && CatDisplaySettings.isAgentPill(t.id) {
                let rank = busyRank(t.state)
                if let b = best, !(rank < b.rank || (rank == b.rank && (t.last > b.last || (t.last == b.last && i < b.at)))) { continue }
                best = (t.id, rank, t.last, i)
            }
            second = Spot(pill: best?.id, cat: pr[1])
        }
        let pills = list.filter { $0.id != focus && $0.id != second?.pill }.prefix(pillRow).map { PillCat(pill: $0.id, cat: catOf($0.id)) }
        let sessions = (0..<4).map { pills.indices.contains($0) ? pills[$0].cat : main }
        return Result(mode: mode, big: big, second: second, pills: Array(pills), drop: big.cat,
                      greeting: Greeting(cat: main, pair: mode == .two ? pr : nil, sessions: sessions))
    }
}
```

- [ ] **Step 3: Run it to see it pass**

Run: `bash scripts/test-cat-cast.sh 2>&1 | grep -c "✓"; bash scripts/test-cat-cast.sh 2>&1 | tail -1`
Expected: `18`, then `All tests passed.`

- [ ] **Step 4: Prove the test bites (one-off, never committed)**

Swap the waiting-for-you rank and the error rank and see the rankings fail.

Run: `sed -i '' 's/s == .approval || s == .question ? 0 : s == .error ? 1 : s.isBusy ? 2 : 3/s == .error ? 0 : s == .approval || s == .question ? 1 : s.isBusy ? 2 : 3/' NotchBuddy/Sources/App/CatCast.swift && bash scripts/test-cat-cast.sh 2>&1 | grep -c "✗"`
Expected: `2`.

Run: `sed -i '' 's/s == .error ? 0 : s == .approval || s == .question ? 1 : s.isBusy ? 2 : 3/s == .approval || s == .question ? 0 : s == .error ? 1 : s.isBusy ? 2 : 3/' NotchBuddy/Sources/App/CatCast.swift && bash scripts/test-cat-cast.sh 2>&1 | tail -1`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/App/CatCast.swift tests/CatCastTests.swift scripts/test-cat-cast.sh
git commit -m "feat(cat): the cast of each display mode

CatCast.of is the Swift port of castOf: which coat the big cat, cat 2, the row and the 2x2 grid, the drop view and the greeting wear in One cat, A cat for each
agent and Two cats mode, and the busiest-other-agent rule. Replays cast-cases.json (136 rows) and 500 hostile islands.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 6: The store holds the display settings, and each pill remembers its last event (stage 2)

**Agent:** `nm-implementer`. The code is given in full; this task changes the store, `AppState` and the hook server, builds, and starts the wiring program.

**Files:**
- Create: `tests/CatWiringTests.swift`, `scripts/test-cat-wiring.sh`
- Modify: `NotchBuddy/Sources/App/CatSettingsStore.swift`, `NotchBuddy/Sources/App/AppState.swift`, `NotchBuddy/Sources/App/HookServer.swift`, `tests/CatSettingsStoreTests.swift`, `scripts/test-cat-settings-store.sh`, `scripts/render-cat-settings.sh`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (by `xcodegen`)

**Interfaces:**
- Consumes: Tasks 3 to 5 (`CatDisplaySettings`, `CatAgentCats`).
- Produces: on `CatSettingsStore`: `display: CatDisplaySettings` (published), `init(backing:config:rand:)` (the random source is injected; `Double.random(in: 0..<1)` by default), `updateDisplay(_:)`, `setDisplayMode(_:)`, `setPairCat(_:slot:)`, `setAgentCat(_:for:)`, `rerollAgentCat(for:)`, `resetAgentCats(for:)`, `ensureAgentCat(for:) -> String` (the first sight of an agent pill: gives it its coat and stores it, once) and `ensureAgentCats(for:)` (once at load); on `AppState`: `pillLastEvent: [String: Double]` and `touchPill(_:at:)`, called for every hook event the pill gets (B-0 interface §3); and the wiring program `scripts/test-cat-wiring.sh`, which pins what no test program can run (the app's files), and grows with each later task.

- [ ] **Step 1: Write the failing tests**

The store's tests: the display settings are loaded from what is stored, only the key that changed is written, a setting that is wrong in every way still loads, the first sight of an agent gives it one coat (one draw, one key, never again), the dice and "Reset to defaults" store, and a restart finds the same coats and draws nothing. The wiring program pins the three places `HookServer` touches a pill and where `AppState` keeps the times.

**Edit `scripts/render-cat-settings.sh`**, find this text (it occurs exactly once):

```bash
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatSettings.swift $APP/CatSettingsStore.swift $APP/CatSettingsView.swift \
    scripts/render-cat-settings.swift \
    -o "$BUILD_DIR/render-cat-settings"
```

and replace it with:

```bash
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatSettingsStore.swift $APP/CatSettingsView.swift \
    scripts/render-cat-settings.swift \
    -o "$BUILD_DIR/render-cat-settings"
```

**Edit `scripts/test-cat-settings-store.sh`**, find this text (it occurs exactly once):

```bash
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatSettings.swift $APP/CatSettingsStore.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/CatSettingsStoreTests.swift \
    -o "$TEST_DIR/cat-settings-store-tests"
```

and replace it with:

```bash
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatSettingsStore.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/CatSettingsStoreTests.swift \
    -o "$TEST_DIR/cat-settings-store-tests"
```

**Edit `tests/CatSettingsStoreTests.swift`**, find this text (it occurs exactly once):

```swift
    @MainActor static func engine(_ id: String, _ cfg: CatConfig) -> CatEngine {
        CatEngine(CatPresets.byID(id), now: { 0 }, rand: { 0.5 }, cfg: cfg, quiet: true)
    }

```

and replace it with:

```swift
    @MainActor static func engine(_ id: String, _ cfg: CatConfig) -> CatEngine {
        CatEngine(CatPresets.byID(id), now: { 0 }, rand: { 0.5 }, cfg: cfg, quiet: true)
    }

    /// A random source that counts its draws, on the contract's seeded generator.
    final class Dice {
        var draws = 0
        private let rng: CatRNG
        init(_ seed: UInt32) { rng = CatRNG(seed: seed) }
        func next() -> Double { draws += 1; return rng.next() }
    }

    /// B: the display mode, the pair and the agents' coats are held, saved and given out by the same store.
    @MainActor static func displaySettings() {
        CT.section("display settings: the store starts from what is stored, saves only what changed and cleans what it is given")
        let mem = MemoryBacking()
        mem.values = ["cat.displayMode": "two", "cat.pair": "[\"noodle\",\"leo\"]", "cat.agentCat.agent_zed": "snow", "cat.character": "latte"]
        let dice = Dice(5)
        let store = CatSettingsStore(backing: mem, config: CatConfig(), rand: dice.next)
        CT.check("the stored display settings are loaded", store.display, CatDisplaySettings(mode: .two, pair: ["noodle", "leo"], agentCats: ["agent_zed": "snow"]))
        CT.check("and the Cat settings beside them", store.settings.character, "latte")
        CT.check("nothing was written yet, and nothing was drawn", [mem.writes.count, dice.draws], [0, 0])
        store.setDisplayMode(.perAgent)
        CT.check("the mode", [store.display.mode.rawValue, mem.values["cat.displayMode"] as? String ?? ""], ["perAgent", "perAgent"])
        store.setDisplayMode(.perAgent)
        CT.check("the same mode again writes nothing", mem.writes, ["cat.displayMode"])
        store.setPairCat("ginger", slot: 1)
        CT.check("cat 2 of the pair, saved as JSON text", [store.display.pair.joined(separator: ","), mem.values["cat.pair"] as? String ?? ""], ["noodle,ginger", "[\"noodle\",\"ginger\"]"])
        store.setPairCat("noodle", slot: 1)
        CT.check("the same coat for both is repaired: cat 2 becomes the next coat", store.display.pair, ["noodle", "shrimpy"])
        store.setAgentCat("blue", for: "agent_zed")
        CT.check("an agent's coat, one key", [store.display.agentCats["agent_zed"] ?? "", mem.writes.last ?? ""], ["blue", "cat.agentCat.agent_zed"])
        store.setCharacter("momo")
        CT.check("the Main cat is another row: no agent's coat moves with it", [store.display.agentCats["agent_zed"] ?? "", mem.writes.last ?? ""], ["blue", "cat.character"])

        CT.section("the first sight of an agent gives it a coat once, and it keeps it")
        let first = store.ensureAgentCat(for: "agent_gemini")
        CT.checkTrue("a coat of the 16, not Shrimpy or Momo (Claude Code's and Codex's, and the Main cat is Momo), not Blue (Zed's)", CatPresets.ids.contains(first) && !["shrimpy", "momo", "blue"].contains(first))
        CT.check("it is stored, with one draw", [store.display.agentCats["agent_gemini"] ?? "", mem.values["cat.agentCat.agent_gemini"] as? String ?? "", "\(dice.draws)"], [first, first, "1"])
        let writes = mem.writes.count
        CT.check("asked again it gives the same coat, draws nothing and writes nothing", [store.ensureAgentCat(for: "agent_gemini"), "\(dice.draws)", "\(mem.writes.count - writes)"], [first, "1", "0"])
        CT.check("an integration gets the Main cat and nothing is stored or drawn", [store.ensureAgentCat(for: "integration_stripe"), "\(store.display.agentCats.count)", "\(dice.draws)"], ["momo", "2", "1"])
        CT.check("Claude Code is Shrimpy and Codex is Momo without a draw", [store.ensureAgentCat(for: "integration_claude"), store.ensureAgentCat(for: "agent_codex"), "\(dice.draws)"], ["shrimpy", "momo", "1"])
        store.rerollAgentCat(for: "agent_gemini")
        CT.checkTrue("the dice gives another coat, stores it and draws once", store.display.agentCats["agent_gemini"] != first && dice.draws == 2 && mem.values["cat.agentCat.agent_gemini"] as? String == store.display.agentCats["agent_gemini"])
        store.resetAgentCats(for: ["agent_gemini", "integration_claude", "agent_cursor"])
        CT.check("Reset to defaults: the agents in the list start again, and Zed, which was not in it, loses its coat", Set(store.display.agentCats.keys), ["agent_gemini", "agent_cursor"])
        CT.checkTrue("Zed's key is gone from the store too", mem.values["cat.agentCat.agent_zed"] == nil)

        CT.section("once at load: every agent pill that exists gets its coat, and the map is saved in one go")
        let loadMem = MemoryBacking(), loadDice = Dice(11)
        let loaded = CatSettingsStore(backing: loadMem, config: CatConfig(), rand: loadDice.next)
        loaded.ensureAgentCats(for: ["integration_claude", "agent_gemini", "agent_antigravity", "integration_stripe", "agent_gemini"])
        CT.check("two new agents, two draws, two keys", [loaded.display.agentCats.count, loadDice.draws, loadMem.writes.count], [2, 2, 2])
        CT.checkTrue("they have different coats", Set(loaded.display.agentCats.values).count == 2)
        let restartDice = Dice(99)
        let again = CatSettingsStore(backing: loadMem, config: CatConfig(), rand: restartDice.next)
        again.ensureAgentCats(for: ["agent_gemini", "agent_antigravity"])
        CT.check("a restart finds the same coats", again.display, loaded.display)
        CT.check("and draws nothing, and writes nothing", [restartDice.draws, loadMem.writes.count], [0, 2])

        CT.section("a store that is wrong in every way still loads the display settings")
        let wild = MemoryBacking()
        wild.values = ["cat.displayMode": 3, "cat.pair": "[\"momo\",", "cat.agentCat.agent_a": "tiger", "cat.agentCat.integration_claude": 9]
        let tough = CatSettingsStore(backing: wild, config: CatConfig())
        CT.check("One cat, Shrimpy and Momo, Claude Code's coat is its default and Agent A has none", tough.display, CatDisplaySettings(mode: .one, pair: ["shrimpy", "momo"], agentCats: ["integration_claude": "shrimpy"]))
    }

```

**Edit `tests/CatSettingsStoreTests.swift`**, find this text (it occurs exactly once):

```swift
        e.useCharacter("tiger")
        CT.check("an unknown ID is Shrimpy", e.p.name, "shrimpy")
        CT.finish()
    }
```

and replace it with:

```swift
        e.useCharacter("tiger")
        CT.check("an unknown ID is Shrimpy", e.p.name, "shrimpy")
        displaySettings()
        CT.finish()
    }
```

**Create `scripts/test-cat-wiring.sh`**:

```bash
#!/usr/bin/env bash
# Cat wiring (sub-project B): what no test program can run, because the app's windows and servers are not in it: where the app's own files call the pure
# parts, pinned as source text (the last event of each pill, the coat each cat view is given, the kittens' hook events, and the App Store split).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/CatWiringTests.swift \
    -o "$TEST_DIR/cat-wiring-tests"
"$TEST_DIR/cat-wiring-tests"
```

**Create `tests/CatWiringTests.swift`**:

```swift
import Foundation

// Source pins for the app files no test program can compile (HookServer, AppState and the SwiftUI views need the whole app). Each says where a call must be, so a
// missed call site fails here and not on the owner's screen. Run from the repository root.

@main
enum CatWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
    /// The offset of the first `needle`, or -1.
    static func at(_ needle: String, in text: String) -> Int { text.range(of: needle)?.lowerBound.utf16Offset(in: text) ?? -1 }

    @MainActor static func main() {
        CT.section("each pill's last event: every hook event the pill gets touches it (Two cats mode's busiest-other rule reads it)")
        let hook = source("HookServer.swift"), app = source("AppState.swift")
        CT.checkTrue("the sources were read", hook.contains("final class HookServer") && app.contains("final class AppState"))
        CT.check("the event, the permission request and the question request each touch their pill", count("state.touchPill(", in: hook), 3)
        CT.checkTrue("an event touches its pill before a pending approval can end the handling early", at("state.touchPill(agentId)", in: hook) > 0 && at("state.touchPill(agentId)", in: hook) < at("if !resolved { return }", in: hook))
        CT.checkTrue("AppState keeps the times in a dictionary that is not published", app.contains("var pillLastEvent: [String: Double] = [:]") && !app.contains("@Published var pillLastEvent"))
        CT.checkTrue("on the clock the sleep timer and the engines use", app.contains("func touchPill(_ id: String, at ms: Double = CACurrentMediaTime() * 1000)"))

        CT.finish()
    }
}
```

Run: `chmod +x scripts/test-cat-wiring.sh`
Expected: no output.

Run: `bash scripts/test-cat-settings-store.sh 2>&1 | grep -c "error:"`
Expected: FAIL: `8` (the store has no display settings and no injected random source yet).

Run: `bash scripts/test-cat-wiring.sh 2>&1 | tail -1`
Expected: FAIL: `4 test(s) failed.`

- [ ] **Step 2: Write the implementation**

The store keeps `settings` and `display` side by side and cleans each with its own function. `HookServer` touches the pill at the top of `processEvent` (before a pending approval can end the handling early), and in `processPermissionRequest` and `processQuestionRequest` once the pill is known. The times are kept in a dictionary that is **not** published: the events that set it change the tasks too, and the views redraw for those.

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
import SwiftUI
import Combine


```

and replace it with:

```swift
import SwiftUI
import Combine
import QuartzCore


```

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
    var lastMouseMove: Date = .now
    var lastActivity: Date = .now
    var isPresent: Bool = true

```

and replace it with:

```swift
    var lastMouseMove: Date = .now
    var lastActivity: Date = .now
    /// When each pill last had a hook event, in ms on the `CACurrentMediaTime()` clock (`touchPill`). Two cats mode picks the busiest other agent with it. Not
    /// published: the events that set it change the tasks too, and the views redraw for those.
    var pillLastEvent: [String: Double] = [:]
    func touchPill(_ id: String, at ms: Double = CACurrentMediaTime() * 1000) { pillLastEvent[id] = ms }
    var isPresent: Bool = true

```

**Edit `NotchBuddy/Sources/App/CatSettingsStore.swift`**, find this text (it occurs exactly once):

```swift

    @Published private(set) var settings: CatSettings
    private let backing: any CatSettingsBacking
    /// The engines' shared settings, which this store feeds; Settings' previews read it too.
    let config: CatConfig

    init(backing: any CatSettingsBacking = UserDefaults.standard, config: CatConfig = .shared) {
        self.backing = backing
        self.config = config
        settings = CatSettings.load(from: backing)
        config.apply(settings)
    }
```

and replace it with:

```swift

    @Published private(set) var settings: CatSettings
    /// Settings → Cat → Display: the mode, the pair and the agents' coats. Cleaned by its own `CatDisplaySettings.clean`, beside the Cat settings.
    @Published private(set) var display: CatDisplaySettings
    private let backing: any CatSettingsBacking
    /// Where a new agent's random coat comes from: `Double.random` in the app, a counted seeded source in a test.
    private let rand: () -> Double
    /// The engines' shared settings, which this store feeds; Settings' previews read it too.
    let config: CatConfig

    init(backing: any CatSettingsBacking = UserDefaults.standard, config: CatConfig = .shared, rand: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.backing = backing
        self.config = config
        self.rand = rand
        settings = CatSettings.load(from: backing)
        display = CatDisplaySettings.load(from: backing)
        config.apply(settings)
    }
```

**Edit `NotchBuddy/Sources/App/CatSettingsStore.swift`**, find this text (it occurs exactly once):

```swift
    /// "Apply to every cat": the motion, collar and personality of cat `id` go to all 16.
    func applyToAll(from id: String) { update { $0 = $0.applyingToAll(from: id) } }
}

```

and replace it with:

```swift
    /// "Apply to every cat": the motion, collar and personality of cat `id` go to all 16.
    func applyToAll(from id: String) { update { $0 = $0.applyingToAll(from: id) } }

    // MARK: Display

    /// Changes the display settings the same way `update` changes the Cat settings: the closure edits a copy, the copy is cleaned, and when it differs it is
    /// published and saved (only the keys that changed).
    func updateDisplay(_ change: (inout CatDisplaySettings) -> Void) {
        var next = display
        change(&next)
        next = CatDisplaySettings.clean(next.json)
        guard next != display else { return }
        next.save(to: backing, replacing: display)
        display = next
    }
    func setDisplayMode(_ mode: CatDisplayMode) { updateDisplay { $0 = $0.withMode(mode) } }
    /// Cat 1 (`slot` 0) or cat 2 (`slot` 1) of Two cats mode's pair.
    func setPairCat(_ id: String, slot: Int) { updateDisplay { $0 = $0.withPairCat(id, slot: slot) } }
    /// The picker of "Cats for your agents".
    func setAgentCat(_ id: String, for pillId: String) { updateDisplay { $0 = $0.withAgentCat(pillId, id) } }
    /// The dice: a new random coat for one agent, never its current one, always stored.
    func rerollAgentCat(for pillId: String) {
        let rolled = CatAgentCats.rerollAgentCat(pillId, display.agentCats, mainCat: settings.character, rand: rand)
        updateDisplay { $0.agentCats = rolled.agentCats }
    }
    /// "Reset to defaults": the agents in the list start again, Claude Code as Shrimpy, Codex as Momo and every other one with a new random coat.
    func resetAgentCats(for pillIds: [String]) {
        let map = CatAgentCats.assignAgentCats(pillIds, [:], mainCat: settings.character, rand: rand)
        updateDisplay { $0.agentCats = map }
    }
    /// The first sight of an agent pill: it gets its coat now, before anything is drawn, and keeps it. Returns the coat. Safe to call for any pill (an integration
    /// gets the Main cat and nothing is stored) and as often as you like (a stored coat is never changed).
    @discardableResult
    func ensureAgentCat(for pillId: String) -> String {
        let pick = CatAgentCats.agentCatFor(pillId, display.agentCats, mainCat: settings.character, rand: rand)
        if pick.assigned { updateDisplay { $0.agentCats = pick.agentCats } }
        return pick.cat
    }
    /// Once at load: every agent pill that exists gets its coat, and the map is saved once.
    func ensureAgentCats(for pillIds: [String]) {
        let map = CatAgentCats.assignAgentCats(pillIds, display.agentCats, mainCat: settings.character, rand: rand)
        updateDisplay { $0.agentCats = map }
    }
}

```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
        }

        let focused = state.focusId == agentId

```

and replace it with:

```swift
        }

        state.touchPill(agentId)   // the pill's last event: Two cats mode's busiest-other rule reads it
        let focused = state.focusId == agentId

```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
        }

        let tool = payload["tool_name"] as? String ?? "Tool"
        let toolInput = payload["tool_input"] as? [String: Any] ?? [:]
```

and replace it with:

```swift
        }

        state.touchPill(pillId)
        let tool = payload["tool_name"] as? String ?? "Tool"
        let toolInput = payload["tool_input"] as? [String: Any] ?? [:]
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
        }

        // Displace any previous question waiting for an answer.
        if pendingQuestionFD >= 0 {
```

and replace it with:

```swift
        }

        state.touchPill(pillId)
        // Displace any previous question waiting for an answer.
        if pendingQuestionFD >= 0 {
```

- [ ] **Step 3: Run them to see them pass**

Run: `bash scripts/test-cat-settings-store.sh 2>&1 | grep -c "✓"; bash scripts/test-cat-settings-store.sh 2>&1 | tail -1`
Expected: `55`, then `All tests passed.`

Run: `bash scripts/test-cat-wiring.sh 2>&1 | tail -1`
Expected: `All tests passed.`

- [ ] **Step 4: Build**

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `Created project at …` and `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/App/CatSettingsStore.swift NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/HookServer.swift tests/CatSettingsStoreTests.swift tests/CatWiringTests.swift scripts/test-cat-settings-store.sh scripts/render-cat-settings.sh scripts/test-cat-wiring.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): the store holds the display settings; each pill remembers its last event

CatSettingsStore loads and saves the display mode, the pair and the agents' coats beside the Cat settings, gives a new agent its coat the first time it is seen (one
draw, stored, never changed by itself), and has the dice and Reset to defaults. AppState keeps when each pill last had a hook event (the busiest-other rule of Two
cats mode reads it) and HookServer touches it on every event the pill gets. tests/CatWiringTests.swift starts: the source pins of the app files.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Settings → Cat → Display: Main cat, the picker and its preview, the pair, the agents' list (stage 2)

**Agent:** `nm-implementer`. The code is given in full; this task builds the Settings rows, draws them into a PNG without launching the app, and looks at them.

**Files:**
- Create: `NotchBuddy/Sources/App/CatAgentList.swift`, `NotchBuddy/Sources/App/CatIslandLayout.swift`, `NotchBuddy/Sources/App/CatDisplayPreview.swift`, `NotchBuddy/Sources/App/CatSettingsSection.swift`, `tests/CatAgentListTests.swift`, `scripts/test-cat-agent-list.sh`
- Modify: `NotchBuddy/Sources/App/CatSettingsView.swift`, `NotchBuddy/Sources/App/SettingsView.swift` (one line), `scripts/render-cat-settings.sh`, `scripts/render-cat-settings.swift`, `tests/CatWiringTests.swift`, `tests/CatSettingsTests.swift` (two of A's pins), `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (by `xcodegen`)

**Interfaces:**
- Consumes: Tasks 3 to 6 (`CatDisplaySettings`, `CatCast`, `CatAgentCats`, `CatSettingsStore.display` and its setters, `AppState.pillLastEvent`), A's `CatPreviewView` and `WindowVisibility`.
- Produces: `CatAgentList.rows(agents:display:main:lookup:)` (the rows of "Cats for your agents": the agents on the island, the most recent event first, then the agents that are only stored); `CatDisplaySample` (the preview's sample island: five pills, Claude Code focused and working, Codex waiting for you) with `cast(_:main:)`; `CatIslandLayout.compactX(_ mode:)` (the compact island's cats in the left ear: One cat and A cat for each agent `[40]` as they ship, Two cats `[30, 54]`); `DisplayPreviewView`; `CatSettingsView(store:alwaysActive:agents:lookup:)`; `CatSettingsSection` (the app's host, which hands Settings the island's agent pills); and the render script's `--mode`, `--pair` and `--agents`.

- [ ] **Step 1: Write the failing tests for the pure parts**

The rows (the most recent event first, a pill with no event after those that had one, stored agents after, integrations are not agents, names made from an ID), the sample island's cast in each mode, and the compact island's cat positions.

**Create `scripts/test-cat-agent-list.sh`**:

```bash
#!/usr/bin/env bash
# Cat agent list: the rows of "Cats for your agents" (most recent first, stored agents after), the Display preview's sample island, and the compact island's
# cat positions.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-agent-list.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift \
    $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatIslandLayout.swift \
    tests/CatTestSupport.swift tests/CatAgentListTests.swift \
    -o "$TEST_DIR/cat-agent-list-tests"
"$TEST_DIR/cat-agent-list-tests"
```

**Create `tests/CatAgentListTests.swift`**:

```swift
import Foundation

@main
enum CatAgentListTests {
    typealias L = CatAgentList
    typealias D = CatDisplaySettings

    @MainActor static func main() {
        CT.section("the rows: the agents on the island, the most recent event first; integrations are not agents")
        let agents = [L.Agent(id: "integration_stripe", name: "Stripe", color: "#0570DE", last: 900), L.Agent(id: "integration_claude", name: "Claude Code", color: "#E07950", last: 10),
                      L.Agent(id: "agent_gemini", name: "Gemini CLI", color: "#8AB4F8", last: 50), L.Agent(id: "agent_codex", name: "Codex", color: "#2DD4BF", last: 30),
                      L.Agent(id: "ai_openai", name: "OpenAI", color: "#10A37F", last: 70)]
        let display = D(mode: .perAgent, pair: ["shrimpy", "momo"], agentCats: ["agent_gemini": "latte"])
        let rows = L.rows(agents: agents, display: display, main: "ginger")
        CT.check("Gemini CLI (50), then Codex (30), then Claude Code (10)", rows.map(\.id), ["agent_gemini", "agent_codex", "integration_claude"])
        CT.check("their coats: stored, then the default, then the default", rows.map(\.cat), ["latte", "momo", "shrimpy"])
        CT.check("they are on the island, and keep the name and colour the island shows", [rows[0].present, rows[0].name == "Gemini CLI", rows[0].color == "#8AB4F8"], [true, true, true])

        CT.section("a pill with no event yet comes after the pills that had one, in the island's order")
        let quiet = [L.Agent(id: "agent_a", name: "A", color: "#111111"), L.Agent(id: "agent_b", name: "B", color: "#222222", last: 5), L.Agent(id: "agent_c", name: "C", color: "#333333")]
        CT.check("B, then A and C as the island lists them", L.rows(agents: quiet, display: D(), main: "ginger").map(\.id), ["agent_b", "agent_a", "agent_c"])
        CT.check("a time that is NaN counts as no event", L.rows(agents: [L.Agent(id: "agent_a", name: "A", color: "#111111", last: .nan), L.Agent(id: "agent_b", name: "B", color: "#222222", last: 1)], display: D(), main: "ginger").map(\.id), ["agent_a", "agent_b"])
        CT.check("an agent listed twice is one row", L.rows(agents: quiet + quiet, display: D(), main: "ginger").count, 3)
        CT.check("a new agent with no stored coat wears the Main cat until it is given one", L.rows(agents: quiet, display: D(), main: "ginger").map(\.cat), ["ginger", "ginger", "ginger"])

        CT.section("agents that are only stored come after, in code-point order, named by the pill catalog when it knows them")
        let stored = D(mode: .perAgent, pair: ["shrimpy", "momo"], agentCats: ["agent_zed": "snow", "agent_alpha": "blue", "agent_gemini": "latte", "ai_openai": "puff", "agent_codex": "momo"])
        let known: (String) -> (name: String, color: String)? = { $0 == "agent_codex" ? ("Codex", "#2DD4BF") : nil }
        let all = L.rows(agents: [agents[3]], display: stored, main: "ginger", lookup: known)
        CT.check("Codex is on the island; Alpha, Gemini and Zed are not; the AI provider is no agent", all.map(\.id), ["agent_codex", "agent_alpha", "agent_gemini", "agent_zed"])
        CT.check("the stored ones are not present, with a name made from the ID and the grey", [all[1].present, all[1].name, all[1].color], [false, "Alpha", L.fallbackColor] as [AnyHashable])
        CT.check("and wear their coats", all.map(\.cat), ["momo", "blue", "latte", "snow"])
        CT.check("a stored Codex that is not on the island is named by the catalog", L.rows(agents: [], display: stored, main: "ginger", lookup: known).first { $0.id == "agent_codex" }.map { [$0.name, $0.color] }, ["Codex", "#2DD4BF"])

        CT.section("names made from an ID")
        CT.check("agent_my-tool is My tool", L.title("agent_my-tool"), "My tool")
        CT.check("agent_gemini is Gemini", L.title("agent_gemini"), "Gemini")
        CT.check("integration_claude is Claude Code", L.title("integration_claude"), "Claude Code")
        CT.check("nothing after the prefix is the ID itself", L.title("agent_"), "agent_")

        CT.section("nothing to list")
        CT.check("no agents and nothing stored: no rows", L.rows(agents: [], display: D(), main: "ginger"), [])

        CT.section("the Display preview's sample island: what each mode shows")
        let one = CatDisplaySample.cast(D(), main: "ginger"), per = CatDisplaySample.cast(D(mode: .perAgent), main: "ginger"), two = CatDisplaySample.cast(D(mode: .two), main: "ginger")
        CT.check("One cat: the Main cat everywhere, the big cat and the four others in the row", [one.big.cat] + one.pills.map(\.cat), ["ginger", "ginger", "ginger", "ginger", "ginger"])
        CT.check("A cat for each agent: Claude Code Shrimpy, Codex Momo, and the others a coat of their own that is not taken", [per.big.cat, per.pills[0].cat, per.pills[1].cat], ["shrimpy", "momo", per.pills[1].cat])
        CT.checkTrue("the sample's two new agents wear different coats, not Shrimpy, Momo or the Main cat", { let c = [per.pills[1].cat, per.pills[2].cat]; return Set(c).count == 2 && !c.contains("shrimpy") && !c.contains("momo") && !c.contains("ginger") }())
        CT.check("Two cats: the pair, and Codex, which waits for you, is cat 2", [two.big.cat, two.second?.cat ?? "", two.second?.pill ?? ""], ["shrimpy", "momo", "agent_codex"])
        CT.check("and Codex has left the row", two.pills.map(\.pill), ["agent_gemini", "agent_antigravity", "integration_stripe"])
        CT.check("the preview never stores a coat", CatDisplaySample.coats(D(), main: "ginger").count > 0 && D().agentCats.isEmpty, true)
        CT.check("it is the same every time", CatDisplaySample.cast(D(mode: .perAgent), main: "ginger"), per)

        CT.section("the compact island's cats: what ships stays, and Two cats has two in the left ear")
        CT.check("One cat and A cat for each agent: one cat, 40 pt in", [CatIslandLayout.compactX(.one), CatIslandLayout.compactX(.perAgent)], [[40], [40]])
        CT.check("Two cats: 30 and 54 pt in", CatIslandLayout.compactX(.two), [30, 54])

        CT.finish()
    }
}
```

Run: `chmod +x scripts/test-cat-agent-list.sh`
Expected: no output.

Run: `bash scripts/test-cat-agent-list.sh 2>&1 | tail -2`
Expected: FAIL: `error opening input file 'NotchBuddy/Sources/App/CatAgentList.swift'`.

- [ ] **Step 2: Write the pure parts**

**Create `NotchBuddy/Sources/App/CatAgentList.swift`**:

```swift
import Foundation

// The "Cats for your agents" list of Settings → Cat → Display (A cat for each agent mode): one row per agent NotchMeow has seen, most recent first. The rows are
// built here, from plain values, so the order and the coats are tested without the app; `CatSettingsView` draws them. Foundation only.

enum CatAgentList {
    /// An agent pill on the island now: its ID, the name and the colour it shows, and the time of its last event (ms; 0 when it has had none).
    struct Agent: Equatable {
        var id: String
        var name: String
        var color: String
        var last: Double = 0
    }

    /// One row: the agent, the coat it wears (stored, else its default, else the Main cat), and whether it is on the island now.
    struct Row: Equatable {
        var id: String
        var name: String
        var color: String
        var cat: String
        var present: Bool
    }

    /// The colour of an agent that is not on the island and has no pill definition: a neutral grey.
    static let fallbackColor = "#8D9098"

    /// A readable name for an agent that is only in the store: `agent_my-tool` is "My tool", `integration_claude` is "Claude Code".
    static func title(_ id: String) -> String {
        if id == "integration_claude" { return "Claude Code" }
        let words = id.dropFirst(id.hasPrefix("agent_") ? 6 : 0).split(whereSeparator: { $0 == "-" || $0 == "_" }).joined(separator: " ")
        return words.isEmpty ? id : words.prefix(1).uppercased() + words.dropFirst()
    }

    /// The agents on the island first, the most recent event first (a pill with no event yet comes after those that had one, in the island's order), then the agents
    /// that are only stored, in code-point order of their IDs. Integrations and AI providers are not agents and are not listed. `lookup` names and colours a stored
    /// agent that is not on the island (the app asks the pill catalog).
    static func rows(agents: [Agent], display: CatDisplaySettings, main: String, lookup: (String) -> (name: String, color: String)? = { _ in nil }) -> [Row] {
        var out: [Row] = [], seen = Set<String>()
        let present = agents.enumerated().filter { CatDisplaySettings.isAgentPill($0.element.id) }
            .sorted { a, b in a.element.last.isFinite && b.element.last.isFinite && a.element.last != b.element.last ? a.element.last > b.element.last : a.offset < b.offset }
        for (_, a) in present where seen.insert(a.id).inserted {
            out.append(Row(id: a.id, name: a.name, color: a.color, cat: display.catFor(agent: a.id, main: main), present: true))
        }
        for id in display.agentCats.keys.sorted() where CatDisplaySettings.isAgentPill(id) && !seen.contains(id) {
            let known = lookup(id)
            out.append(Row(id: id, name: known?.name ?? title(id), color: known?.color ?? fallbackColor, cat: display.catFor(agent: id, main: main), present: false))
        }
        return out
    }
}

/// The sample island the Display preview of Settings draws: five pills with a state each, the first focused. In Two cats mode the agent waiting for you is cat 2.
enum CatDisplaySample {
    struct Pill: Equatable {
        var id: String
        var name: String
        var color: String
        var state: CatState
    }
    static let pills = [
        Pill(id: "integration_claude", name: "Claude Code", color: "#E07950", state: .working),
        Pill(id: "agent_codex", name: "Codex", color: "#2DD4BF", state: .approval),
        Pill(id: "agent_gemini", name: "Gemini CLI", color: "#8AB4F8", state: .thinking),
        Pill(id: "agent_antigravity", name: "Antigravity", color: "#E879F9", state: .idle),
        Pill(id: "integration_stripe", name: "Stripe", color: "#0570DE", state: .idle),
    ]
    static let focus = "integration_claude"

    /// The coats the sample agents wear: the stored ones, and for a sample agent with none the one the app would give it (a fixed random source, so the preview is
    /// the same every time). Nothing is stored.
    static func coats(_ display: CatDisplaySettings, main: String) -> [String: String] {
        CatAgentCats.assignAgentCats(pills.map(\.id), display.agentCats, mainCat: main, rand: CatRNG(seed: 3).next)
    }

    /// The cast of the sample island in the chosen mode: what the preview draws.
    static func cast(_ display: CatDisplaySettings, main: String) -> CatCast.Result {
        CatCast.of(display.mode, tasks: pills.enumerated().map { CatCast.Pill(id: $1.id, state: $1.state, last: Double(100 - $0 * 10)) }, focusId: focus,
                   mainCat: main, pair: display.pair, agentCats: coats(display, main: main))
    }
}
```

**Create `NotchBuddy/Sources/App/CatIslandLayout.swift`**:

```swift
import Foundation

// Where the cats sit in the island, as numbers: one place for the compact notch's and (from the Two cats layout) the expanded overview's, read by the views, the
// hit test, the greeting, the Settings preview and the contact sheets, so they cannot disagree. Foundation only. One cat keeps the numbers that ship.

enum CatIslandLayout {
    /// The compact island's cats in the left ear, as the distance of each centre from the island's left edge (pt; the head width is `IslandRestingLayout.botDiameter`, 20
    /// on a 32 pt strip). One cat and A cat for each agent: the one big cat, 40 pt in, as it has always been. Two cats: two cats side by side, 30 and 54 pt in
    /// (the prototype's numbers), which the 80 pt ear holds.
    static func compactX(_ mode: CatDisplayMode) -> [Double] { mode == .two ? [30, 54] : [40] }
}
```

- [ ] **Step 3: Run them to see them pass**

Run: `bash scripts/test-cat-agent-list.sh 2>&1 | grep -c "✓"; bash scripts/test-cat-agent-list.sh 2>&1 | tail -1`
Expected: `25`, then `All tests passed.`

- [ ] **Step 4: Write the failing pins for the Settings section**

The wiring program pins that the group is titled Main cat, Display comes first, the pair and the agents' list are shown only in their modes, Settings hosts the section through `CatSettingsSection`, and every preview is paused unless Settings is on screen. A's two pins on the Cat section (`CatSettingsTests.swift`) said `CatSettingsView()`; they say `CatSettingsSection()` now.

**Edit `tests/CatSettingsTests.swift`**, find this text (it occurs exactly once):

```swift
        func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/" + file, encoding: .utf8)) ?? "" }
        let view = source("CatSettingsView.swift"), settingsView = source("SettingsView.swift")
        CT.checkTrue("Settings has a Cat entry in its sidebar and shows the section", settingsView.contains("title: \"Cat\"") && settingsView.contains(".tag(\"cat\")") && settingsView.contains("CatSettingsView()"))
        CT.checkTrue("the section saves nothing itself: every change goes through the store", view.contains("store.setCharacter") && !view.contains("UserDefaults") && !view.contains("@AppStorage"))
        CT.checkTrue("the previews pause when the window is not on screen", view.contains("paused: !active") && view.contains("WindowVisibility(visible: $windowVisible)"))
        CT.checkTrue("the previews are silent: they have no sound hook", !view.contains("onSound") && !view.contains("SoundEngine"))
        CT.checkTrue("Settings names the Cat section once", settingsView.components(separatedBy: "CatSettingsView").count == 2)

        CT.section("the collar in the app (source pins): the big cat, the small cats, the greeting's cats and the Settings rows")
```

and replace it with:

```swift
        func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/" + file, encoding: .utf8)) ?? "" }
        let view = source("CatSettingsView.swift"), settingsView = source("SettingsView.swift")
        CT.checkTrue("Settings has a Cat entry in its sidebar and shows the section", settingsView.contains("title: \"Cat\"") && settingsView.contains(".tag(\"cat\")") && settingsView.contains("CatSettingsSection()"))
        CT.checkTrue("the section saves nothing itself: every change goes through the store", view.contains("store.setCharacter") && !view.contains("UserDefaults") && !view.contains("@AppStorage"))
        CT.checkTrue("the previews pause when the window is not on screen", view.contains("paused: !active") && view.contains("WindowVisibility(visible: $windowVisible)"))
        CT.checkTrue("the previews are silent: they have no sound hook", !view.contains("onSound") && !view.contains("SoundEngine"))
        CT.checkTrue("Settings names the Cat section once (through CatSettingsSection, which hosts CatSettingsView with the island's agents)", settingsView.components(separatedBy: "CatSettingsSection").count == 2 && !settingsView.contains("CatSettingsView"))

        CT.section("the collar in the app (source pins): the big cat, the small cats, the greeting's cats and the Settings rows")
```

**Edit `tests/CatWiringTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkTrue("on the clock the sleep timer and the engines use", app.contains("func touchPill(_ id: String, at ms: Double = CACurrentMediaTime() * 1000)"))

        CT.finish()
    }
```

and replace it with:

```swift
        CT.checkTrue("on the clock the sleep timer and the engines use", app.contains("func touchPill(_ id: String, at ms: Double = CACurrentMediaTime() * 1000)"))

        CT.section("Settings → Cat: Display is first, the character is the Main cat, and the app hosts the section with the agents the island has")
        let view = source("CatSettingsView.swift"), settings = source("SettingsView.swift"), section = source("CatSettingsSection.swift"), preview = source("CatDisplayPreview.swift")
        CT.checkTrue("the sources were read", view.contains("struct CatSettingsView") && settings.contains("struct SettingsView") && section.contains("CatSettingsSection") && preview.contains("DisplayPreviewView"))
        CT.checkTrue("the group is titled Main cat, and nothing is titled Character any more", view.contains("GroupBox(\"Main cat\")") && !view.contains("GroupBox(\"Character\")"))
        CT.checkTrue("Display is the first group, then the pair or the agents, then the Main cat", at("displayGroup\n", in: view) > 0 && at("displayGroup\n", in: view) < at("pairGroup }", in: view) && at("agentsGroup }", in: view) < at("characterGroup\n", in: view))
        CT.checkTrue("the pair is shown only in Two cats mode and the agents' list only in A cat for each agent", view.contains("if store.display.mode == .two { pairGroup }") && view.contains("if store.display.mode == .perAgent { agentsGroup }"))
        CT.checkTrue("Settings hosts the section through CatSettingsSection, which reads the agents from AppState", settings.contains("case \"cat\":          CatSettingsSection()") && section.contains("@ObservedObject private var app = AppState.shared") && section.contains("isAgentPill"))
        CT.checkTrue("the Display preview animates only while Settings is visible (paused unless active), at 30 fps", preview.contains("TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active))"))
        CT.checkTrue("and every Settings preview gets `active` from the window's visibility", count("active: active", in: view) >= 5)

        CT.finish()
    }
```

Run: `bash scripts/test-cat-wiring.sh 2>&1 | tail -1; bash scripts/test-cat-settings.sh 2>&1 | tail -1`
Expected: FAIL: `7 test(s) failed.` and `2 test(s) failed.`

- [ ] **Step 5: Write the Settings rows**

The Display group is first: a small live picture of the compact notch in the chosen mode (the sample island drawn with the real renderer, in the places `CatCast` and `CatIslandLayout` give; it animates only while `active`), a segmented picker, and a note. In Two cats mode a group "Your two cats" has a preview and a menu for cat 1 and cat 2; in A cat for each agent mode a group "Cats for your agents" has a row for each agent (its colour, a live preview wearing its collar colour, a menu of the 16, a dice) and a "Reset to defaults" under them. The existing Character group is titled "Main cat" and, in the other modes only, says in one more line what it is now. Every row is built from the existing styles (a `GroupBox`, a label of 130 pt and a control, grey 11 pt notes). `CatSettingsSection` is the one place that reads `AppState`: it hands `CatSettingsView` the island's agent pills.

**Create `NotchBuddy/Sources/App/CatDisplayPreview.swift`**:

```swift
import SwiftUI
import QuartzCore

// Settings → Cat → Display: a small live picture of the compact notch in the chosen mode. It draws a sample island (`CatDisplaySample`: five pills, Claude Code
// working, Codex waiting for you) with the real cats of the real renderer, in the places the cast (`CatCast`) and the layout (`CatIslandLayout`) give them, so what it
// shows is what the notch will show. It draws only while it is `active` (the Settings window is on screen and the key window), like the other previews.

struct DisplayPreviewView: View {
    let display: CatDisplaySettings
    /// The Main cat: the character picked in Settings.
    let main: String
    let active: Bool
    let config: CatConfig
    @StateObject private var herd = DisplayPreviewHerd()

    /// The real compact island on a notch of 185 pt: 345 by 32 pt, drawn 1.3 times as big.
    static let island = (w: 345.0, h: 32.0), scale = 1.3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                let cast = CatDisplaySample.cast(display, main: main)
                context.withCGContext { cg in herd.draw(cg, cast: cast, config: config, dpr: Double(context.environment.displayScale)) }
            }
        }
        .frame(width: Self.island.w * Self.scale, height: Self.island.h * Self.scale)
        .accessibilityHidden(true)
    }
}

/// The preview's engines, one for each place a cat can be (the big cat, cat 2 and the four cells of the grid). A place keeps its engine when its coat changes.
@MainActor
final class DisplayPreviewHerd: ObservableObject {
    private var engines: [String: CatEngine] = [:]

    private func engine(_ slot: String, _ coat: String, _ config: CatConfig) -> CatEngine {
        let e = engines[slot] ?? CatEngine(CatPresets.byID(coat), now: { CACurrentMediaTime() * 1000 }, cfg: config, quiet: true)
        engines[slot] = e
        e.useCharacter(coat)
        return e
    }

    func draw(_ cg: CGContext, cast: CatCast.Result, config: CatConfig, dpr: Double) {
        let W = DisplayPreviewView.island.w, H = DisplayPreviewView.island.h, k = DisplayPreviewView.scale
        cg.saveGState()
        cg.scaleBy(x: k, y: k)
        cg.fill(CatDraw.roundRect(0, 0, W, H, 14), CatDraw.black(1))
        cg.fill(CatDraw.roundRect(80, 0, W - 160, H, 10), CatDraw.rgb([24, 25, 28]))   // the notch, a shade lighter than the island so the two ears can be seen
        func pill(_ id: String?) -> CatDisplaySample.Pill? { CatDisplaySample.pills.first { $0.id == id } }
        func cat(_ slot: String, _ coat: String, _ id: String?, cx: Double, cy: Double, d: Double, big: Bool) {
            let e = engine(slot, coat, config), state = pill(id)?.state ?? .idle
            e.setState(state)
            e.collar = big ? CatRules.bigCatCollar(colour: pill(id)?.color, state: state) : pill(id)?.color
            e.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: e.lastTime))
            var options = CatDrawOptions(badge: big)
            if big { options.badgeSide = -1; options.earCeiling = 0 }   // never under the camera housing; the top of the island is the top of the screen
            options.collar = e.collarPaint(dpr: dpr * k)
            let laid = CatRenderer.draw(cg, e.look(), cx: cx, cy: cy, D: d, options)
            e.base = laid.base
            e.mouthPoint = laid.mouth
        }
        let xs = CatIslandLayout.compactX(cast.mode)
        cat("big", cast.big.cat, cast.big.pill, cx: xs[0], cy: H / 2, d: 20, big: true)
        if let second = cast.second { cat("second", second.cat, second.pill, cx: xs[1], cy: H / 2, d: 20, big: true) }
        for (i, p) in cast.pills.enumerated() {
            cat("grid\(i)", p.cat, p.pill, cx: W - 40 + (i % 2 == 1 ? 8 : -8), cy: H / 2 + (i < 2 ? -8 : 8), d: 12, big: false)
        }
        cg.restoreGState()
    }
}
```

**Edit `NotchBuddy/Sources/App/CatSettingsView.swift`**, find this text (it occurs exactly once):

```swift
// a label of 130 pt and a control, grey 11 pt notes): no existing row changes. Everything it shows is `CatSettingsStore.settings`, and every change
// goes through the store, which cleans it, saves it and hands it to the engines, so a cat in the notch changes while you drag a slider.
// Each cat keeps its own motion override and personality: the rows below the character grid are for the character that is picked.

struct CatSettingsView: View {
    @ObservedObject var store: CatSettingsStore
```

and replace it with:

```swift
// a label of 130 pt and a control, grey 11 pt notes): no existing row changes. Everything it shows is `CatSettingsStore.settings`, and every change
// goes through the store, which cleans it, saves it and hands it to the engines, so a cat in the notch changes while you drag a slider.
// Each cat keeps its own motion override and personality: the rows below the character grid are for the character that is picked.
// Display (sub-project B) sits at the top: One cat, A cat for each agent or Two cats, with a small live picture of the compact notch in that mode, the pair's two
// pickers in Two cats mode and the list "Cats for your agents" in A cat for each agent mode. The character is the Main cat.

struct CatSettingsView: View {
    @ObservedObject var store: CatSettingsStore
```

**Edit `NotchBuddy/Sources/App/CatSettingsView.swift`**, find this text (it occurs exactly once):

```swift
    @State private var windowVisible = true
    /// The offscreen render script has no window to report: it asks for live previews outright.
    private let alwaysActive: Bool

    init(store: CatSettingsStore = .shared, alwaysActive: Bool = false) {
        self.store = store
        self.alwaysActive = alwaysActive
    }

    private var active: Bool { alwaysActive || windowVisible }
```

and replace it with:

```swift
    @State private var windowVisible = true
    /// The offscreen render script has no window to report: it asks for live previews outright.
    private let alwaysActive: Bool
    /// The agent pills on the island now, for "Cats for your agents" (the app's `CatSettingsSection` reads them from `AppState`), and how to name and colour an
    /// agent that is only stored.
    private let agents: [CatAgentList.Agent]
    private let lookup: (String) -> (name: String, color: String)?

    init(store: CatSettingsStore = .shared, alwaysActive: Bool = false, agents: [CatAgentList.Agent] = [], lookup: @escaping (String) -> (name: String, color: String)? = { _ in nil }) {
        self.store = store
        self.alwaysActive = alwaysActive
        self.agents = agents
        self.lookup = lookup
    }

    private var active: Bool { alwaysActive || windowVisible }
```

**Edit `NotchBuddy/Sources/App/CatSettingsView.swift`**, find this text (it occurs exactly once):

```swift

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            characterGroup
            motionGroup
            personalityGroup
```

and replace it with:

```swift

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            displayGroup
            if store.display.mode == .two { pairGroup }
            if store.display.mode == .perAgent { agentsGroup }
            characterGroup
            motionGroup
            personalityGroup
```

**Edit `NotchBuddy/Sources/App/CatSettingsView.swift`**, find this text (it occurs exactly once):

```swift
        .background(WindowVisibility(visible: $windowVisible))
    }

    // MARK: Character

    private var characterGroup: some View {
        GroupBox("Character") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    // A head of Ø60 and more is where fur lines show, so the chosen cat is drawn big (the 16 below are Ø36).
```

and replace it with:

```swift
        .background(WindowVisibility(visible: $windowVisible))
    }

    // MARK: Display

    private var modeNote: String {
        switch store.display.mode {
        case .one: return "One cat: the Main cat shows every agent, as it always has."
        case .perAgent: return "Every agent has its own cat, so you can tell them apart at a glance. Claude Code is Shrimpy and Codex is Momo; every other agent gets a random coat the first time it appears, and keeps it."
        case .two: return "Your two cats side by side: the first shows the agent you are looking at, the second the busiest other agent. They go to sleep together."
        }
    }

    private var displayGroup: some View {
        GroupBox("Display") {
            VStack(alignment: .leading, spacing: 10) {
                DisplayPreviewView(display: store.display, main: id, active: active, config: store.config)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    Text("Show").frame(width: 130, alignment: .leading)
                    Picker("", selection: Binding(get: { store.display.mode }, set: { store.setDisplayMode($0) })) {
                        Text("One cat").tag(CatDisplayMode.one)
                        Text("A cat for each agent").tag(CatDisplayMode.perAgent)
                        Text("Two cats").tag(CatDisplayMode.two)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 340)
                }
                Text(modeNote)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    /// A cat's name in a menu, and the cat it picks.
    private func catPicker(_ selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(CatPresets.ids, id: \.self) { Text(CatPresets.byID($0).label).tag($0) }
        }
        .labelsHidden()
        .frame(width: 160)
    }

    // MARK: The pair (Two cats)

    private var pairGroup: some View {
        GroupBox("Your two cats") {
            VStack(alignment: .leading, spacing: 8) {
                pairRow("Cat 1", slot: 0)
                pairRow("Cat 2", slot: 1)
                Text("If both are the same coat, cat 2 becomes the next one.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func pairRow(_ label: String, slot: Int) -> some View {
        let cat = store.display.pair[slot]
        return HStack(spacing: 8) {
            Text(label).frame(width: 130, alignment: .leading)
            CatPreviewView(id: cat, head: 28, active: active, config: store.config)
                .frame(width: 44, height: 36)
            catPicker(Binding(get: { cat }, set: { store.setPairCat($0, slot: slot) }))
        }
    }

    // MARK: Cats for your agents (A cat for each agent)

    private var agentRows: [CatAgentList.Row] { CatAgentList.rows(agents: agents, display: store.display, main: id, lookup: lookup) }

    private var agentsGroup: some View {
        let rows = agentRows
        return GroupBox("Cats for your agents") {
            VStack(alignment: .leading, spacing: 8) {
                if rows.isEmpty {
                    Text("No agent has shown up yet. Each one is listed here the first time it sends an event.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                ForEach(rows, id: \.id) { agentRow($0) }
                HStack(spacing: 10) {
                    Button("Reset to defaults") { store.resetAgentCats(for: rows.map(\.id)) }
                        .disabled(rows.isEmpty)
                    Text("Claude Code is Shrimpy and Codex is Momo; every other agent gets a new random coat.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func agentRow(_ row: CatAgentList.Row) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Color(CatDraw.color(row.color))).frame(width: 8, height: 8)
            Text(row.name).lineLimit(1).frame(width: 112, alignment: .leading)
            CatPreviewView(id: row.cat, head: 28, active: active, config: store.config, agentColor: row.color)
                .frame(width: 44, height: 36)
            catPicker(Binding(get: { row.cat }, set: { store.setAgentCat($0, for: row.id) }))
            Button("🎲") { store.rerollAgentCat(for: row.id) }
                .help("Roll a new random coat for \(row.name)")
                .accessibilityLabel("Roll a new coat for \(row.name)")
        }
    }

    // MARK: Main cat

    private var characterGroup: some View {
        GroupBox("Main cat") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    // A head of Ø60 and more is where fur lines show, so the chosen cat is drawn big (the 16 below are Ø36).
```

**Edit `NotchBuddy/Sources/App/CatSettingsView.swift`**, find this text (it occurs exactly once):

```swift
                        Text("The cat that lives in your notch and in the small pills. Each one keeps its own motion and personality.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 8)], spacing: 8) {
```

and replace it with:

```swift
                        Text("The cat that lives in your notch and in the small pills. Each one keeps its own motion and personality.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        if store.display.mode != .one {
                            Text("In this display mode it is the cat of the integration pills (Stripe, Music, Vercel…), and of the notch when no agent is in focus.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 8)], spacing: 8) {
```

**Create `NotchBuddy/Sources/App/CatSettingsSection.swift`**:

```swift
import SwiftUI

// Settings → Cat in the app: `CatSettingsView` with the agents the island has now, so "Cats for your agents" follows them as they come and go. The view itself
// takes plain values (the render script has no app state), so this wrapper is the only place that reads `AppState`.

struct CatSettingsSection: View {
    @ObservedObject private var app = AppState.shared

    var body: some View {
        let agents = app.tasks.filter { CatDisplaySettings.isAgentPill($0.id) }.map {
            CatAgentList.Agent(id: $0.id, name: PillCatalog.definition(for: $0.id)?.name ?? $0.name, color: $0.color, last: app.pillLastEvent[$0.id] ?? 0)
        }
        CatSettingsView(agents: agents, lookup: { id in PillCatalog.definition(for: id).map { ($0.name, $0.color) } })
    }
}
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`**, find this text (it occurs exactly once):

```swift
        case "integrations": integrationsSection
        case "shortcuts":    ShortcutsSettingsView()
        case "cat":          CatSettingsView()
        default:             generalSection
        }
```

and replace it with:

```swift
        case "integrations": integrationsSection
        case "shortcuts":    ShortcutsSettingsView()
        case "cat":          CatSettingsSection()
        default:             generalSection
        }
```

- [ ] **Step 6: The script that draws Settings takes the new rows**

`--mode one|perAgent|two` picks the display mode, `--pair momo,latte` the two cats of Two cats mode, and `--agents` lists the preview's five sample pills (and gives the new ones their coats) as the agents Settings has seen, so "Cats for your agents" has rows. The store it draws is a dictionary and a `CatConfig` of its own: nothing the user saved is read or changed.

**Edit `scripts/render-cat-settings.sh`**, find this text (it occurs exactly once):

```bash
# Draws Settings → Cat into a PNG without launching NotchMeow (see scripts/render-cat-settings.swift).
#   bash scripts/render-cat-settings.sh --out settings.png [--height 1500] [--width 520] [--character momo] [--preset chill] [--fur] [--collar band]
set -euo pipefail
cd "$(dirname "$0")/.."
```

and replace it with:

```bash
# Draws Settings → Cat into a PNG without launching NotchMeow (see scripts/render-cat-settings.swift).
#   bash scripts/render-cat-settings.sh --out settings.png [--height 1500] [--width 520] [--character momo] [--preset chill] [--fur] [--collar band]
#                                       [--mode one|perAgent|two] [--pair momo,latte] [--agents]
set -euo pipefail
cd "$(dirname "$0")/.."
```

**Edit `scripts/render-cat-settings.sh`**, find this text (it occurs exactly once):

```bash
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatSettingsStore.swift $APP/CatSettingsView.swift \
    scripts/render-cat-settings.swift \
    -o "$BUILD_DIR/render-cat-settings"
```

and replace it with:

```bash
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatIslandLayout.swift $APP/CatSettingsStore.swift $APP/CatDisplayPreview.swift $APP/CatSettingsView.swift \
    scripts/render-cat-settings.swift \
    -o "$BUILD_DIR/render-cat-settings"
```

**Edit `scripts/render-cat-settings.swift`**, find this text (it occurs exactly once):

```swift
// Run it through scripts/render-cat-settings.sh:
//   bash scripts/render-cat-settings.sh [--out settings.png] [--height 1500] [--width 520] [--character momo] [--preset chill] [--fur] [--collar band]

final class MemoryBacking: CatSettingsBacking {
```

and replace it with:

```swift
// Run it through scripts/render-cat-settings.sh:
//   bash scripts/render-cat-settings.sh [--out settings.png] [--height 1500] [--width 520] [--character momo] [--preset chill] [--fur] [--collar band]
//                                       [--mode one|perAgent|two] [--pair momo,latte] [--agents]
//   --mode picks the display mode; --pair the two cats of Two cats mode; --agents lists the Display preview's five sample pills (and gives the new ones their coats)
//   as the agents Settings has seen, so "Cats for your agents" has rows.

final class MemoryBacking: CatSettingsBacking {
```

**Edit `scripts/render-cat-settings.swift`**, find this text (it occurs exactly once):

```swift
    @MainActor static func main() {
        var out = "cat-settings.png", height = 1500.0, width = 520.0, character = "momo", preset = "chill", fur = false, collar = "off"
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
```

and replace it with:

```swift
    @MainActor static func main() {
        var out = "cat-settings.png", height = 1500.0, width = 520.0, character = "momo", preset = "chill", fur = false, collar = "off"
        var mode = "one", pair = "shrimpy,momo", withAgents = false
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
```

**Edit `scripts/render-cat-settings.swift`**, find this text (it occurs exactly once):

```swift
            case "--fur": fur = true
            case "--collar": collar = it.next() ?? collar
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

and replace it with:

```swift
            case "--fur": fur = true
            case "--collar": collar = it.next() ?? collar
            case "--mode": mode = it.next() ?? mode
            case "--pair": pair = it.next() ?? pair
            case "--agents": withAgents = true
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

**Edit `scripts/render-cat-settings.swift`**, find this text (it occurs exactly once):

```swift
        store.setFurLines(fur)
        store.setCollar(collar)
        let host = NSHostingView(rootView: ScrollView { CatSettingsView(store: store, alwaysActive: true).padding(20) }.frame(width: width, height: height))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
```

and replace it with:

```swift
        store.setFurLines(fur)
        store.setCollar(collar)
        store.setDisplayMode(CatDisplaySettings.modeOf(mode))
        for (slot, cat) in pair.split(separator: ",").map(String.init).enumerated() { store.setPairCat(cat, slot: slot) }
        let agents = withAgents ? CatDisplaySample.pills.filter { CatDisplaySettings.isAgentPill($0.id) }.enumerated().map { CatAgentList.Agent(id: $1.id, name: $1.name, color: $1.color, last: Double(100 - $0 * 10)) } : []
        store.ensureAgentCats(for: agents.map(\.id))
        let host = NSHostingView(rootView: ScrollView { CatSettingsView(store: store, alwaysActive: true, agents: agents).padding(20) }.frame(width: width, height: height))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
```

- [ ] **Step 7: Run the pins, draw Settings in each mode and look**

Run: `bash scripts/test-cat-wiring.sh 2>&1 | tail -1; bash scripts/test-cat-settings.sh 2>&1 | tail -1`
Expected: `All tests passed.` twice.

Run: `mkdir -p "${TMPDIR:-/tmp}/b-mac-1" && for m in one perAgent two; do bash scripts/render-cat-settings.sh --out "${TMPDIR:-/tmp}/b-mac-1/settings-$m.png" --mode $m --agents --height 1700 | tail -1 | cut -c1-6; done`
Expected: `wrote ` three times. Look at the three PNGs: the Display group is first, with a black strip (the compact notch with its two ears and the notch in the middle) showing the chosen mode: **One cat** the Main cat (Momo) on the left and four Momos in the grid on the right; **A cat for each agent** Shrimpy (Claude Code) on the left and four different cats in the grid (Codex is Momo), with the group "Cats for your agents" under it (Claude Code, Codex, Gemini CLI and Antigravity, each with its colour dot, a live cat, a menu and a dice, and "Reset to defaults" below); **Two cats** two cats side by side in the left ear, an amber dot on the second (Codex waits for you), three cats in the grid, and the group "Your two cats". The group below is titled "Main cat", with one more grey line in the last two modes. The pickers and sliders may come out blank in this offscreen bitmap; the cats and the layout do not.

- [ ] **Step 8: Build**

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `Created project at …` and `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add NotchBuddy/Sources/App/CatAgentList.swift NotchBuddy/Sources/App/CatIslandLayout.swift NotchBuddy/Sources/App/CatDisplayPreview.swift NotchBuddy/Sources/App/CatSettingsSection.swift NotchBuddy/Sources/App/CatSettingsView.swift NotchBuddy/Sources/App/SettingsView.swift tests/CatAgentListTests.swift tests/CatWiringTests.swift tests/CatSettingsTests.swift scripts/test-cat-agent-list.sh scripts/render-cat-settings.sh scripts/render-cat-settings.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): Settings → Cat → Display

A Display picker at the top (One cat, A cat for each agent, Two cats) with a small live picture of the compact notch in that mode, the pair's two pickers, and the
list Cats for your agents (colour, live preview, picker, dice, Reset to defaults), built from the existing row styles. The Character row is the Main cat. The
previews are paused unless Settings is on screen. render-cat-settings.sh draws any mode.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Owner checkpoint 1: the eyes and Settings

No code and no commit. The session reports; the main session sends the owner the images and asks the questions below, then relays the owner's reply to the session.

- [ ] **Step 1: Collect the images**

Run: `mkdir -p .claude/checkpoints/b-mac-1 && cp "${TMPDIR:-/tmp}/b-mac-1/eyes-1x.png" "${TMPDIR:-/tmp}/b-mac-1/eyes-2x.png" "${TMPDIR:-/tmp}/b-mac-1/settings-one.png" "${TMPDIR:-/tmp}/b-mac-1/settings-perAgent.png" "${TMPDIR:-/tmp}/b-mac-1/settings-two.png" .claude/checkpoints/b-mac-1/ && ls .claude/checkpoints/b-mac-1`
Expected: `eyes-1x.png`, `eyes-2x.png`, `settings-one.png`, `settings-perAgent.png` and `settings-two.png`. (The folder is the worktree's own and is never committed.)

Run: `for f in scripts/test-cat-*.sh; do printf '%-42s' "$f"; bash "$f" 2>&1 | tail -1; done`
Expected: twenty-three lines: the contract's ends `✓ two generator runs write identical bytes` and the other twenty-two end `All tests passed.`

- [ ] **Step 2: What the owner looks at**

1. **The eyes** (`eyes-1x.png` and `eyes-2x.png`, next to the prototype page's own small-eye sheets from B-0): are the coloured eyes right at Ø12 to Ø24 on every coat: the size of the iris and the pupil, the catchlight, the rim, and the kittens' rounder eyes? Do Midnight, Oreo and Mocha glow as the ink pills did (a flat lighter iris, no rim, a thin slit; B-0's checkpoint changed them)? At 1× is a Ø12 eye still readable and not muddy? The numbers belong to the contract (`SMALL_EYE` in `cat-core.js`); a change is one edit there, a regenerated fixture and the same change on Windows, and both apps pick it up.
2. **Settings** (the three `settings-*.png`): is Display the right place and size at the top of the Cat section? Does the preview say what each mode does? Are "Your two cats" and "Cats for your agents" clear (the dice, Reset to defaults)? Is the Main cat's extra line right?
3. **The numbers:** the frame bench was 1.70 to 1.84 ms before the eyes and 1.82 to 1.85 ms after on a quiet machine, about 0.12 ms more with the eyes (budget 2 ms).

Record the owner's answers in the PR description.

---

### Task 9: The cast in the app: a new agent gets its cat, the island reads the cast (stage 3)

**Agent:** `nm-implementer`. The code is given in full; this task changes `AppState`, the hook server and the launch, and builds twice.

**Files:**
- Create: `NotchBuddy/Sources/App/CatCast+App.swift`
- Modify: `NotchBuddy/Sources/App/AppState.swift`, `NotchBuddy/Sources/App/HookServer.swift`, `NotchBuddy/Sources/App/AppDelegate.swift`, `tests/CatWiringTests.swift`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (by `xcodegen`)

**Interfaces:**
- Consumes: Tasks 5 and 6 (`CatCast.of`, `CatSettingsStore.display`, `ensureAgentCat(for:)`, `ensureAgentCats(for:)`, `AppState.pillLastEvent`).
- Produces: `AppState.cast: CatCast.Result` (the island's tasks in the app's order, the focused pill `focusTask`, each pill's last event, the stored settings), `AppState.displayMode`, `AppState.agentName(for:)`, `AppState.giveCoat(to:)`; a new agent pill gets its coat **when it is created** (`HookServer.upsertExternalAgent`, `upsertWorkspaceTask`, and `AppState.addTask`, `loadIntegrationTasks`, `toggleIntegration`) and every pill that exists at launch gets one once (`AppDelegate`), before anything is drawn; and `AppState` redraws the views that read the cast when the display mode, the pair, an agent's coat or the Main cat changes (not for a personality slider).

- [ ] **Step 1: Write the failing pins**

**Edit `tests/CatWiringTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkTrue("and every Settings preview gets `active` from the window's visibility", count("active: active", in: view) >= 5)

        CT.finish()
    }
```

and replace it with:

```swift
        CT.checkTrue("and every Settings preview gets `active` from the window's visibility", count("active: active", in: view) >= 5)

        CT.section("A cat for each agent: a new agent pill gets its coat when it is created, and once at launch; the island reads the cast again when Settings changes it")
        let delegate = source("AppDelegate.swift"), cast = source("CatCast+App.swift")
        CT.checkTrue("the sources were read", delegate.contains("applicationDidFinishLaunching") && cast.contains("var cast: CatCast.Result"))
        CT.check("the pill creation sites in the hook server (a third-party agent, and a workspace pill) give a coat", count("giveCoat(to: id)", in: hook), 2)
        CT.check("the pill creation sites in AppState (addTask, loading the declared pills, switching one on) give a coat", count("giveCoat(to:", in: app), 3)
        CT.checkTrue("at launch every pill that exists gets its coat, after the store is made and before the island is set up", at("ensureAgentCats(for: AppState.shared.tasks.map(\\.id))", in: delegate) > at("_ = CatSettingsStore.shared", in: delegate) && at("ensureAgentCats(for: AppState.shared.tasks.map(\\.id))", in: delegate) < at("setupIsland()", in: delegate))
        CT.checkTrue("the cast reads the focused pill (focusTask), each pill's last event and the stored settings", cast.contains("focusId: focusTask?.id") && cast.contains("pillLastEvent[$0.id]") && cast.contains("store.display.agentCats") && cast.contains("store.settings.character"))
        CT.checkTrue("AppState watches the display settings and the Main cat, and not the sliders", app.contains("store.$display") && app.contains("$settings.map(\\.character).removeDuplicates()"))

        CT.finish()
    }
```

Run: `bash scripts/test-cat-wiring.sh 2>&1 | tail -1`
Expected: FAIL: `6 test(s) failed.`

- [ ] **Step 2: Write the implementation**

A pill is "first created" in five places; each calls `giveCoat(to:)`, which asks the store to give an agent pill its coat (an integration is left alone, and a stored coat is never changed, so a third-party agent whose pill is removed after its `Stop` and created again keeps its cat). `AppState` listens to `store.$display` and to the Main cat only: the cast is made from the island and Settings, so a change of either is a change of this object.

**Create `NotchBuddy/Sources/App/CatCast+App.swift`**:

```swift
import Foundation

// The app's way into the cast: the island's own state and Settings, read as `CatCast`'s plain values. Nothing here is in the contract, and the test programs do not
// compile this file (`tests/CatWiringTests.swift` pins where the views and the hook server call it).

extension AppState {
    /// Which cat appears where on the island right now: the big cat, cat 2 (Two cats mode), the pills and the 2x2 grid, the drop view and the drag ghost, and the
    /// greeting. The big cat shows the focused pill (`focusTask`, as everything else does); each pill's last event is `pillLastEvent`.
    var cast: CatCast.Result {
        let store = CatSettingsStore.shared
        return CatCast.of(store.display.mode,
                          tasks: tasks.map { CatCast.Pill(id: $0.id, state: CatState(rawValue: $0.state.rawValue) ?? .idle, last: pillLastEvent[$0.id] ?? 0) },
                          focusId: focusTask?.id, mainCat: store.settings.character, pair: store.display.pair, agentCats: store.display.agentCats)
    }

    /// A pill that has just been created gets its coat now, before anything draws it, and keeps it: an agent pill is given one if it has none (Claude Code is
    /// Shrimpy and Codex is Momo; every other agent a random coat that no other agent and not the Main cat wears), and any other pill is left alone.
    func giveCoat(to pillId: String) { CatSettingsStore.shared.ensureAgentCat(for: pillId) }
}
```

**Edit `NotchBuddy/Sources/App/AppDelegate.swift`**, find this text (it occurs exactly once):

```swift
        // The cat settings are read before the first cat is made, so the notch opens with the cat the user picked.
        _ = CatSettingsStore.shared
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarItem()
```

and replace it with:

```swift
        // The cat settings are read before the first cat is made, so the notch opens with the cat the user picked.
        _ = CatSettingsStore.shared
        // Every agent pill that exists at launch has its cat before anything is drawn (a new one gets its coat when it is created).
        CatSettingsStore.shared.ensureAgentCats(for: AppState.shared.tasks.map(\.id))
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarItem()
```

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
    /// True while the idle cat is asleep: ten minutes with no agent event (`CatSleepClock`). The cat then shows `.sleeping` instead of `.idle`.
    @Published var catAsleep = false

    // Real notch dimensions (set by IslandWindowController on launch)
```

and replace it with:

```swift
    /// True while the idle cat is asleep: ten minutes with no agent event (`CatSleepClock`). The cat then shows `.sleeping` instead of `.idle`.
    @Published var catAsleep = false
    /// Settings → Cat → Display and the Main cat: when either changes, the island's views read the cast again (`storeWatch`).
    private var storeWatch: AnyCancellable?

    // Real notch dimensions (set by IslandWindowController on launch)
```

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
        // Always load integration pills
        loadIntegrationTasks()
    }

```

and replace it with:

```swift
        // Always load integration pills
        loadIntegrationTasks()

        // The cast (`cast`) is made from the island and from Settings → Cat, so a change of the display mode, the pair, an agent's coat or the Main cat is a change of
        // this object too: the views that read the cast redraw. (Dragging a personality slider is not.)
        let store = CatSettingsStore.shared
        storeWatch = store.$display.map { _ in () }.dropFirst()
            .merge(with: store.$settings.map(\.character).removeDuplicates().dropFirst().map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
    }

```

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
        guard !tasks.contains(where: { $0.id == task.id }) else { return }
        tasks.append(task)
        if focusId == nil { focusId = task.id }
        syncMode()
```

and replace it with:

```swift
        guard !tasks.contains(where: { $0.id == task.id }) else { return }
        tasks.append(task)
        giveCoat(to: task.id)
        if focusId == nil { focusId = task.id }
        syncMode()
```

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
                                     state: .idle, steps: [], source: def.source, isIntegration: true)
                tasks.append(task)
            }
            if !shouldLoad && loaded {
```

and replace it with:

```swift
                                     state: .idle, steps: [], source: def.source, isIntegration: true)
                tasks.append(task)
                giveCoat(to: def.id)
            }
            if !shouldLoad && loaded {
```

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
                                     state: .idle, steps: [], source: def.source, isIntegration: true)
                tasks.append(task)
                sortTasksByCatalog()
            }
```

and replace it with:

```swift
                                     state: .idle, steps: [], source: def.source, isIntegration: true)
                tasks.append(task)
                giveCoat(to: def.id)
                sortTasksByCatalog()
            }
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
            state.tasks.append(task)
        }
        if state.focusId == nil { state.focusId = id }
        state.syncMode()
```

and replace it with:

```swift
            state.tasks.append(task)
        }
        state.giveCoat(to: id)   // a new agent gets its cat before it is drawn (A cat for each agent mode)
        if state.focusId == nil { state.focusId = id }
        state.syncMode()
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
            state.tasks.insert(task, at: 0)
        }
        if state.focusId == nil { state.focusId = id }
        state.syncMode()
```

and replace it with:

```swift
            state.tasks.insert(task, at: 0)
        }
        state.giveCoat(to: id)
        if state.focusId == nil { state.focusId = id }
        state.syncMode()
```

- [ ] **Step 3: Run the pins, and build both targets**

Run: `bash scripts/test-cat-wiring.sh 2>&1 | tail -1`
Expected: `All tests passed.`

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `Created project at …` and `** BUILD SUCCEEDED **`.

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3`
Expected: the last lines end with `** BUILD SUCCEEDED **` (the App Store build compiles the same files without the GitHub-only code).

- [ ] **Step 4: Commit**

```bash
git add NotchBuddy/Sources/App/CatCast+App.swift NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/HookServer.swift NotchBuddy/Sources/App/AppDelegate.swift tests/CatWiringTests.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): a new agent gets its cat, and the island reads the cast

AppState.cast turns the island and Settings into CatCast's values. A new agent pill is given its coat when it is created (and every pill once at launch), so it is
never drawn before it has one. The views that read the cast redraw when the display mode, the pair, an agent's coat or the Main cat changes.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Every cat view takes its coat (stage 3)

**Agent:** `nm-implementer-deep`. One missed call site would show an agent's cat as the Main cat on the next frame, so every site has its own pin; the greeting's session cats get a parameter and a pixel test.

**Files:**
- Modify: `NotchBuddy/Sources/App/BotCanvasView.swift`, `IslandRootView.swift`, `IslandViewContent.swift`, `IslandWindowController.swift`, `UploadCanvasView.swift`, `GreetingCanvasView.swift`, `CatGreetingRenderer.swift`, `CatEngine.swift`, `tests/CatRendererTests.swift`, `tests/CatSettingsStoreTests.swift`, `tests/CatWiringTests.swift`

**Interfaces:**
- Consumes: Task 9's `AppState.cast`.
- Produces: `BotCanvasView(state:cat:particleOverhang:)`, `MiniBotCanvasView(task:cat:isDancing:)`, `AgentPill(task:cat:state:swapping:onTap:)`, `MusicPill(task:cat:…)`, `UploadCanvasView(state:cat:)`; `CatGreetingRenderer.draw(_:t:leave:engine:end:sessions:)` (the coats of the four session cats in the grid's cell order; nil: the engine's coat four times, as it always drew); the row of pills, the 2×2 grid and the drop view and ghost read the cast; and `CatEngine.useCharacter` ignores a kitten (the "latent" item of A's final report: a kitten's engine could be turned into an adult).

- [ ] **Step 1: Write the failing tests**

The greeting's session cats: no coats is the engine's coat four times, four Momos are the same pixels as a Momo greeting's grid whoever falls in, each cell has its own coat, and a short list leaves the rest to the engine. The engine: a kitten stays a kitten. The pins: one test per call site (the big cat, the pill cats, the pills, the row and the grid, the greeting, the drop view, the drag ghost), and that no file in the app still re-reads the Main cat each frame.

**Edit `tests/CatRendererTests.swift`**, find this text (it occurs exactly once):

```swift
        }

        CT.section("the greeting's session cats wear collars in the prototype's colours when a style is set, and none by default")
        do {
```

and replace it with:

```swift
        }

        CT.section("the greeting's session cats wear the coats they are given (the cast's), and the Main cat when they are given none")
        do {
            func grid(_ engineCoat: String, _ sessions: [String]?) -> [UInt8] {
                let e = CatEngine(CatPresets.byID(engineCoat), now: { 0 }, rand: { 0.5 }, cfg: CatConfig(), quiet: true)
                return render(640, 150) { CatGreetingRenderer.draw($0, t: CatGreeting.greetEnd + 0.3, leave: CatGreeting.GT.leave, engine: e, end: CatGreeting.Compact(), sessions: sessions) }
            }
            func right(_ px: [UInt8]) -> [UInt8] { (0..<150).flatMap { y in (320..<640).flatMap { x in (0..<4).map { px[(y * 640 + x) * 4 + $0] } } } }
            CT.checkTrue("no sessions is the engine's coat four times, as the greeting always drew", right(grid("shrimpy", nil)) == right(grid("shrimpy", ["shrimpy", "shrimpy", "shrimpy", "shrimpy"])))
            CT.checkTrue("four Momos in the grid are the same pixels as a Momo greeting's grid, whoever falls in", right(grid("shrimpy", Array(repeating: "momo", count: 4))) == right(grid("momo", nil)))
            CT.checkTrue("and they differ from four Shrimpies", right(grid("shrimpy", Array(repeating: "momo", count: 4))) != right(grid("shrimpy", nil)))
            let mixed = right(grid("shrimpy", ["momo", "ginger", "shrimpy", "latte"]))
            CT.checkTrue("each cell has its own coat: a mixed grid is none of the uniform ones", mixed != right(grid("shrimpy", nil)) && mixed != right(grid("shrimpy", Array(repeating: "momo", count: 4))))
            CT.checkTrue("a list that is too short leaves the rest to the engine's coat", right(grid("shrimpy", ["momo"])) != right(grid("shrimpy", nil)) && right(grid("shrimpy", [])) == right(grid("shrimpy", nil)))
        }

        CT.section("the greeting's session cats wear collars in the prototype's colours when a style is set, and none by default")
        do {
```

**Edit `tests/CatSettingsStoreTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkJSON("a second store on the same keys reads the same settings back", got: CatSettingsStore(backing: mem, config: CatConfig()).settings.json, want: store.settings.json)

        CT.section("the character switches a live engine without a restart")
        let e = engine("shrimpy", cfg)
```

and replace it with:

```swift
        CT.checkJSON("a second store on the same keys reads the same settings back", got: CatSettingsStore(backing: mem, config: CatConfig()).settings.json, want: store.settings.json)

        CT.section("a kitten is never turned into an adult: useCharacter leaves it alone")
        do {
            let kit = CatEngine(CatPresets.kitten(of: CatPresets.byID("momo")), now: { 0 }, rand: { 0.5 }, cfg: CatConfig(), quiet: true)
            kit.useCharacter("shrimpy")
            CT.check("still Momo's kitten", [kit.p.kitten == true, kit.p.base ?? ""], [true, "momo"] as [AnyHashable])
        }

        CT.section("the character switches a live engine without a restart")
        let e = engine("shrimpy", cfg)
```

**Edit `tests/CatWiringTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkTrue("AppState watches the display settings and the Main cat, and not the sliders", app.contains("store.$display") && app.contains("$settings.map(\\.character).removeDuplicates()"))

        CT.finish()
    }
```

and replace it with:

```swift
        CT.checkTrue("AppState watches the display settings and the Main cat, and not the sliders", app.contains("store.$display") && app.contains("$settings.map(\\.character).removeDuplicates()"))

        CT.section("every cat view takes its coat from the cast, one test per call site: nothing follows the Main cat on its own, so a per-agent coat is never overwritten")
        let sources = ((try? FileManager.default.contentsOfDirectory(atPath: "NotchBuddy/Sources/App")) ?? []).filter { $0.hasSuffix(".swift") }.sorted()
        let followers = sources.filter { source($0).contains("useCharacter(CatConfig.shared.character)") }
        CT.check("no file in the app still re-reads the Main cat each frame (\(sources.count) files)", followers, [])
        let canvas = source("BotCanvasView.swift"), island = source("IslandRootView.swift"), content = source("IslandViewContent.swift"), controller = source("IslandWindowController.swift")
        let greetingView = source("GreetingCanvasView.swift"), upload = source("UploadCanvasView.swift"), greeting = source("CatGreetingRenderer.swift")
        func lines(_ text: String, containing needle: String) -> [String] { text.components(separatedBy: "\n").filter { $0.contains(needle) } }
        CT.checkTrue("the big cat: the view has a `cat` and draws it (BotCanvasView)", canvas.contains("let cat: String") && canvas.contains("engine.useCharacter(cat)"))
        CT.check("the big cat: both BotPlacement branches pass the cast's big cat", count("BotCanvasView(state: state, cat: state.cast.big.cat", in: island), 2)
        CT.checkTrue("the pill cats: the view has a `cat`, draws it, and every MiniBotCanvasView( in the app is given one", canvas.contains("MiniBotCanvasView") && canvas.contains("engine.useCharacter(cat)   // the cast's coat for this pill") && (lines(content, containing: "MiniBotCanvasView(") + lines(island, containing: "MiniBotCanvasView(")).allSatisfy { $0.contains("cat:") })
        CT.checkTrue("the pills: the row and the music pill are given the cast's coat for their pill", content.contains("AgentPill(task: task, cat: pill.cat, state: state") && content.contains("MusicPill(task: task, cat: pill.cat, state: state") && content.contains("let cat: String"))
        CT.checkTrue("the row and the 2x2 grid are the cast's pills, and nothing filters the focused pill out by hand any more", content.contains("state.cast.pills") && island.contains("state.cast.pills") && !content.contains("filter { $0.id != state.focusId }") && !island.contains("filter { $0.id != state.focusId }"))
        CT.checkTrue("the greeting: the Main cat falls in and the session cats are the cast's", greetingView.contains("engine.useCharacter(greeting.cat)") && greetingView.contains("sessions: greeting.sessions") && greeting.contains("sessions: [String]? = nil"))
        CT.checkTrue("the drop view: given the cast's drop coat, and draws it", island.contains("UploadCanvasView(state: state, cat: state.cast.drop)") && upload.contains("let cat: String") && upload.contains("catEngine.useCharacter(cat)"))
        CT.checkTrue("the drag ghost: the cast's drop coat", controller.contains("BotCanvasView(state: AppState.shared, cat: AppState.shared.cast.drop)"))

        CT.finish()
    }
```

Run: `bash scripts/test-cat-renderer.sh 2>&1 | grep -c "error:"`
Expected: FAIL: `2` (two compile errors: the greeting renderer's draw has no sessions argument yet).

Run: `bash scripts/test-cat-settings-store.sh 2>&1 | tail -1; bash scripts/test-cat-wiring.sh 2>&1 | tail -1`
Expected: FAIL: `1 test(s) failed.` and `9 test(s) failed.`

- [ ] **Step 2: The engine, the greeting's session cats**

**Edit `NotchBuddy/Sources/App/CatEngine.swift`**, find this text (it occurs exactly once):

```swift
    func pm() -> CatMultipliers { Personality.multipliers(pers) }

    /// Turns this cat into another coat: the one picked in Settings. Nothing else changes (the state, the pose and the schedule stay), so a
    /// running engine shows the new cat on its next frame. An unknown ID is Shrimpy, like a stored one.
    func useCharacter(_ id: String) {
        let next = CatPresets.byID(id)
        if next.name != p.name { p = next }
```

and replace it with:

```swift
    func pm() -> CatMultipliers { Personality.multipliers(pers) }

    /// Turns this cat into another coat: the one picked in Settings, or the agent's own. Nothing else changes (the state, the pose and the schedule stay), so a
    /// running engine shows the new cat on its next frame. An unknown ID is Shrimpy, like a stored one. A kitten is never turned: its coat is its parent's as a kitten
    /// (`CatPresets.kitten(of:)`), and a kitten's view makes a new engine when the parent's coat changes.
    func useCharacter(_ id: String) {
        guard p.kitten != true else { return }
        let next = CatPresets.byID(id)
        if next.name != p.name { p = next }
```

**Edit `NotchBuddy/Sources/App/CatGreetingRenderer.swift`**, find this text (it occurs exactly once):

```swift

    /// Draws the greeting at `t` seconds. `engine` is the cat's engine (it blinks and flicks an ear by itself, and has been updated for this frame);
    /// `leave` is when the island starts to collapse (infinity while the pointer holds it open); `end` is the compact island it collapses into.
    static func draw(_ cg: CGContext, t: Double, leave: Double, engine e: CatEngine, end: Greeting.Compact) {
        let P = Greeting.pose(t, leave: leave, into: end), X = P.x, Y = P.y, D = P.hb * 1.34, p = e.p
        let st = Greeting.streakTime(t)
```

and replace it with:

```swift

    /// Draws the greeting at `t` seconds. `engine` is the cat's engine (it blinks and flicks an ear by itself, and has been updated for this frame);
    /// `leave` is when the island starts to collapse (infinity while the pointer holds it open); `end` is the compact island it collapses into. `sessions` are the
    /// coats of the four session cats in the grid's cell order (the cast's `greeting.sessions`: in A cat for each agent mode the agents' own cats, so the glide hands over
    /// to the real grid without a change); nil: all four wear the engine's coat, the Main cat.
    static func draw(_ cg: CGContext, t: Double, leave: Double, engine e: CatEngine, end: Greeting.Compact, sessions: [String]? = nil) {
        let P = Greeting.pose(t, leave: leave, into: end), X = P.x, Y = P.y, D = P.hb * 1.34, p = e.p
        let st = Greeting.streakTime(t)
```

**Edit `NotchBuddy/Sources/App/CatGreetingRenderer.swift`**, find this text (it occurs exactly once):

```swift
        CatRenderer.draw(cg, look, cx: X, cy: Y, D: D, o)
        let slots = Greeting.miniSlots(minis: P.minis, glide: Greeting.miniGlide(t, leave: leave), width: end.width, height: end.height)
        drawMinis(cg, slots, preset: p, scale: end.miniScale, collarStyle: e.collarStyle)
    }

```

and replace it with:

```swift
        CatRenderer.draw(cg, look, cx: X, cy: Y, D: D, o)
        let slots = Greeting.miniSlots(minis: P.minis, glide: Greeting.miniGlide(t, leave: leave), width: end.width, height: end.height)
        let coats = (0..<4).map { i in sessions.flatMap { $0.indices.contains(i) ? CatPresets.byID($0[i]) : nil } ?? p }
        drawMinis(cg, slots, presets: coats, scale: end.miniScale, collarStyle: e.collarStyle)
    }

```

**Edit `NotchBuddy/Sources/App/CatGreetingRenderer.swift`**, find this text (it occurs exactly once):

```swift
    /// takes over when the last beat is over). Each is drawn the way the real grid draws one: a cat of head width 12 pt scaled about its own centre
    /// by the strip's `miniScale`. `slot.d` already holds the pop and that scale, so the head width drawn is `slot.d / scale`.
    private static func drawMinis(_ cg: CGContext, _ slots: [Greeting.Mini], preset: CatPreset, scale k: Double, collarStyle: String) {
        guard k > 0 else { return }
        for (i, s) in slots.enumerated() where s.d >= Greeting.miniMinD {
```

and replace it with:

```swift
    /// takes over when the last beat is over). Each is drawn the way the real grid draws one: a cat of head width 12 pt scaled about its own centre
    /// by the strip's `miniScale`. `slot.d` already holds the pop and that scale, so the head width drawn is `slot.d / scale`.
    private static func drawMinis(_ cg: CGContext, _ slots: [Greeting.Mini], presets: [CatPreset], scale k: Double, collarStyle: String) {
        guard k > 0 else { return }
        for (i, s) in slots.enumerated() where s.d >= Greeting.miniMinD {
```

**Edit `NotchBuddy/Sources/App/CatGreetingRenderer.swift`**, find this text (it occurs exactly once):

```swift
            var options = CatDrawOptions(badge: false)
            if collarStyle != "off" { options.collar = CatCollarPaint(style: collarStyle, color: miniColors[i % miniColors.count]) }
            CatRenderer.draw(cg, CatLook(preset: preset, pose: pose, color: Theme.Greeting.tintRGB), cx: 0, cy: 0, D: s.d / k, options)
            cg.restoreGState()
        }
```

and replace it with:

```swift
            var options = CatDrawOptions(badge: false)
            if collarStyle != "off" { options.collar = CatCollarPaint(style: collarStyle, color: miniColors[i % miniColors.count]) }
            CatRenderer.draw(cg, CatLook(preset: presets[i % presets.count], pose: pose, color: Theme.Greeting.tintRGB), cx: 0, cy: 0, D: s.d / k, options)
            cg.restoreGState()
        }
```

**Edit `NotchBuddy/Sources/App/GreetingCanvasView.swift`**, find this text (it occurs exactly once):

```swift
            let t = timeline.date.timeIntervalSince(startDate)
            Canvas { context, size in
                engine.useCharacter(CatConfig.shared.character)   // Settings → Cat → Character
                engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                let end = CatGreeting.Compact(width: Double(state.notchWidth) + 160, height: Double(state.notchHeight))
                context.withCGContext { cg in
                    CatGreetingRenderer.draw(cg, t: t, leave: tc, engine: engine, end: end)
                }
            }
```

and replace it with:

```swift
            let t = timeline.date.timeIntervalSince(startDate)
            Canvas { context, size in
                let greeting = state.cast.greeting
                engine.useCharacter(greeting.cat)   // the Main cat falls in, in every display mode
                engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                let end = CatGreeting.Compact(width: Double(state.notchWidth) + 160, height: Double(state.notchHeight))
                context.withCGContext { cg in
                    CatGreetingRenderer.draw(cg, t: t, leave: tc, engine: engine, end: end, sessions: greeting.sessions)
                }
            }
```

- [ ] **Step 3: The big cat, the pill cats, the row and the grid, the drop view and the drag ghost**

Each cat view takes its coat as a parameter and draws it: `engine.useCharacter(cat)` in place of `useCharacter(CatConfig.shared.character)`. The row of pills and the grid are the cast's `pills` (the tasks other than the focused one, the first four, with their coats): in One cat mode that is `tasks.filter { $0.id != focusId }.prefix(4)` as before.

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**, find this text (it occurs exactly once):

```swift
struct BotCanvasView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat = 0

```

and replace it with:

```swift
struct BotCanvasView: View {
    @ObservedObject var state: AppState
    /// The coat this cat wears: the cast's (`AppState.cast`), the Main cat in One cat mode. A view never reads the Main cat itself, so a per-agent coat is not
    /// overwritten on the next frame.
    let cat: String
    var particleOverhang: CGFloat = 0

```

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**, find this text (it occurs exactly once):

```swift
                // One clock on both sides of dt: CACurrentMediaTime() here and in the engine (the old code mixed it with the timeline's date).
                let dt = CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                engine.useCharacter(CatConfig.shared.character)   // Settings → Cat → Character
                let look = lookAt(state: state)
                engine.lookX = look.x
```

and replace it with:

```swift
                // One clock on both sides of dt: CACurrentMediaTime() here and in the engine (the old code mixed it with the timeline's date).
                let dt = CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                engine.useCharacter(cat)   // the cast's coat: Settings → Cat → Main cat, or the agent's own
                let look = lookAt(state: state)
                engine.lookX = look.x
```

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**, find this text (it occurs exactly once):

```swift
struct MiniBotCanvasView: View {
    let task: AgentTask
    var isDancing: Bool = false
    @StateObject private var engine: CatEngine

    init(task: AgentTask, isDancing: Bool = false) {
        self.task = task
        self.isDancing = isDancing
        _engine = StateObject(wrappedValue: {
            let e = CatEngine.live(mini: true)
            e.collar = task.color
            return e
```

and replace it with:

```swift
struct MiniBotCanvasView: View {
    let task: AgentTask
    /// The coat this cat wears: the cast's, for this pill.
    let cat: String
    var isDancing: Bool = false
    @StateObject private var engine: CatEngine

    init(task: AgentTask, cat: String, isDancing: Bool = false) {
        self.task = task
        self.cat = cat
        self.isDancing = isDancing
        _engine = StateObject(wrappedValue: {
            let e = CatEngine.live(CatPresets.byID(cat), mini: true)
            e.collar = task.color
            return e
```

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**, find this text (it occurs exactly once):

```swift
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                let dt = CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                engine.useCharacter(CatConfig.shared.character)   // Settings → Cat → Character
                engine.setState(task.state.shown(asleep: AppState.shared.catAsleep))   // an idle pill's cat sleeps with the big one
                engine.setDancing(isDancing)
```

and replace it with:

```swift
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                let dt = CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                engine.useCharacter(cat)   // the cast's coat for this pill
                engine.setState(task.state.shown(asleep: AppState.shared.catAsleep))   // an idle pill's cat sleeps with the big one
                engine.setDancing(isDancing)
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
                } else if uploadActive {
                    ZStack(alignment: .topLeading) {
                        UploadCanvasView(state: state)
                            .frame(width: islandWidth, height: islandHeight)
                            .clipShape(IslandShape(width: islandWidth, height: islandHeight,
```

and replace it with:

```swift
                } else if uploadActive {
                    ZStack(alignment: .topLeading) {
                        UploadCanvasView(state: state, cat: state.cast.drop)
                            .frame(width: islandWidth, height: islandHeight)
                            .clipShape(IslandShape(width: islandWidth, height: islandHeight,
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
                    // cx = 36 + 526*t: bot center at fill right edge (bar left=36, width=526)
                    let uploadCx = 36 + CGFloat(t * (2 - t)) * 526
                    BotCanvasView(state: state, particleOverhang: 0)
                        .frame(width: canvasSize, height: canvasSize)
                        .opacity(state.isDraggingBot ? 0 : opacity)
```

and replace it with:

```swift
                    // cx = 36 + 526*t: bot center at fill right edge (bar left=36, width=526)
                    let uploadCx = 36 + CGFloat(t * (2 - t)) * 526
                    BotCanvasView(state: state, cat: state.cast.big.cat, particleOverhang: 0)
                        .frame(width: canvasSize, height: canvasSize)
                        .opacity(state.isDraggingBot ? 0 : opacity)
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
                .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
            } else {
                BotCanvasView(state: state, particleOverhang: overhang)
                    .frame(width: canvasSize, height: canvasSize + overhang)
                    .opacity(state.isDraggingBot ? 0 : opacity)
```

and replace it with:

```swift
                .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
            } else {
                BotCanvasView(state: state, cat: state.cast.big.cat, particleOverhang: overhang)
                    .frame(width: canvasSize, height: canvasSize + overhang)
                    .opacity(state.isDraggingBot ? 0 : opacity)
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
    @ObservedObject var state: AppState

    private var others: [AgentTask] {
        Array(state.tasks.filter { $0.id != state.focusId }.prefix(4))
    }

```

and replace it with:

```swift
    @ObservedObject var state: AppState

    /// The pills of the grid with the coat the cast gives each: the tasks other than the focused one (and, in Two cats mode, other than cat 2's), the first four.
    private var others: [(task: AgentTask, cat: String)] {
        state.cast.pills.compactMap { p in state.tasks.first { $0.id == p.pill }.map { ($0, p.cat) } }
    }

```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
        let cols = [GridItem(.fixed(12), spacing: 4), GridItem(.fixed(12), spacing: 4)]
        LazyVGrid(columns: cols, spacing: 4) {
            ForEach(others) { task in
                MiniBotCanvasView(task: task)
                    .frame(width: 12 / 0.6, height: 12 / 0.6)
                    .frame(width: 12, height: 12, alignment: .center)
```

and replace it with:

```swift
        let cols = [GridItem(.fixed(12), spacing: 4), GridItem(.fixed(12), spacing: 4)]
        LazyVGrid(columns: cols, spacing: 4) {
            ForEach(others, id: \.task.id) { other in
                MiniBotCanvasView(task: other.task, cat: other.cat)
                    .frame(width: 12 / 0.6, height: 12 / 0.6)
                    .frame(width: 12, height: 12, alignment: .center)
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
    @State private var swapping = false

    private var others: [AgentTask] {
        state.tasks.filter { $0.id != state.focusId }
    }

    private var displayTasks: [AgentTask] {
        Array(others.prefix(4))
    }

```

and replace it with:

```swift
    @State private var swapping = false

    /// The pills of the row with the coat the cast gives each: the tasks other than the focused one (and, in Two cats mode, other than cat 2's), the first four.
    private var displayPills: [(task: AgentTask, cat: String)] {
        state.cast.pills.compactMap { p in state.tasks.first { $0.id == p.pill }.map { ($0, p.cat) } }
    }

```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
            Spacer(minLength: 0)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(displayTasks) { task in
                    #if !APPSTORE
                    if task.id == "integration_music" {
                        MusicPill(task: task, state: state, swapping: $swapping) {
                            swapping = true
                            state.setFocus(task.id)
```

and replace it with:

```swift
            Spacer(minLength: 0)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(displayPills, id: \.task.id) { pill in
                    let task = pill.task
                    #if !APPSTORE
                    if task.id == "integration_music" {
                        MusicPill(task: task, cat: pill.cat, state: state, swapping: $swapping) {
                            swapping = true
                            state.setFocus(task.id)
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
                        }
                    } else {
                        AgentPill(task: task, state: state, swapping: $swapping) {
                            swapping = true
                            state.setFocus(task.id)
```

and replace it with:

```swift
                        }
                    } else {
                        AgentPill(task: task, cat: pill.cat, state: state, swapping: $swapping) {
                            swapping = true
                            state.setFocus(task.id)
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
                    }
                    #else
                    AgentPill(task: task, state: state, swapping: $swapping) {
                        swapping = true
                        state.setFocus(task.id)
```

and replace it with:

```swift
                    }
                    #else
                    AgentPill(task: task, cat: pill.cat, state: state, swapping: $swapping) {
                        swapping = true
                        state.setFocus(task.id)
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
struct AgentPill: View {
    let task: AgentTask
    @ObservedObject var state: AppState
    @Binding var swapping: Bool
```

and replace it with:

```swift
struct AgentPill: View {
    let task: AgentTask
    /// The coat the pill's cat wears: the cast's.
    let cat: String
    @ObservedObject var state: AppState
    @Binding var swapping: Bool
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
                        .stroke(Color(hex: effectiveColor).opacity(isHovered ? 0.55 : 0.14), lineWidth: 1)
                    HStack(spacing: 0) {
                        MiniBotCanvasView(task: task)
                            .frame(width: 22 / 0.6, height: 22 / 0.6)
                            .frame(width: 22, height: 22, alignment: .center)
```

and replace it with:

```swift
                        .stroke(Color(hex: effectiveColor).opacity(isHovered ? 0.55 : 0.14), lineWidth: 1)
                    HStack(spacing: 0) {
                        MiniBotCanvasView(task: task, cat: cat)
                            .frame(width: 22 / 0.6, height: 22 / 0.6)
                            .frame(width: 22, height: 22, alignment: .center)
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
struct MusicPill: View {
    let task: AgentTask
    @ObservedObject var state: AppState
    @Binding var swapping: Bool
```

and replace it with:

```swift
struct MusicPill: View {
    let task: AgentTask
    /// The coat the pill's cat wears: the cast's (the Main cat, for an integration).
    let cat: String
    @ObservedObject var state: AppState
    @Binding var swapping: Bool
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
            // Mini cat at leading edge
            HStack(spacing: 0) {
                MiniBotCanvasView(task: task, isDancing: isPlaying)
                    .frame(width: 22 / 0.6, height: 22 / 0.6)
                    .frame(width: 22, height: 22, alignment: .center)
```

and replace it with:

```swift
            // Mini cat at leading edge
            HStack(spacing: 0) {
                MiniBotCanvasView(task: task, cat: cat, isDancing: isPlaying)
                    .frame(width: 22 / 0.6, height: 22 / 0.6)
                    .frame(width: 22, height: 22, alignment: .center)
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
    @ObservedObject var state: AppState

    var others: [AgentTask] {
        state.tasks.filter { $0.id != state.focusId }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(others.prefix(4).enumerated()), id: \.1.id) { idx, task in
                MiniBotCanvasView(task: task)
                    .frame(width: 16 / 0.6, height: 16 / 0.6)
                    .frame(width: 16, height: 16)
```

and replace it with:

```swift
    @ObservedObject var state: AppState

    var others: [(task: AgentTask, cat: String)] {
        state.cast.pills.compactMap { p in state.tasks.first { $0.id == p.pill }.map { ($0, p.cat) } }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(others.enumerated()), id: \.1.task.id) { idx, other in
                MiniBotCanvasView(task: other.task, cat: other.cat)
                    .frame(width: 16 / 0.6, height: 16 / 0.6)
                    .frame(width: 16, height: 16)
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, find this text (it occurs exactly once):

```swift

    var body: some View {
        BotCanvasView(state: AppState.shared)
            .frame(width: canvasSize, height: canvasSize)
            .scaleEffect(scale)
```

and replace it with:

```swift

    var body: some View {
        BotCanvasView(state: AppState.shared, cat: AppState.shared.cast.drop)
            .frame(width: canvasSize, height: canvasSize)
            .scaleEffect(scale)
```

**Edit `NotchBuddy/Sources/App/UploadCanvasView.swift`**, find this text (it occurs exactly once):

```swift
struct UploadCanvasView: View {
    @ObservedObject var state: AppState
    @State private var fileIcon: NSImage? = nil
    @StateObject private var driver = UploadCatDriver(engine: .live())
```

and replace it with:

```swift
struct UploadCanvasView: View {
    @ObservedObject var state: AppState
    /// The coat of the cat that catches the file: the cast's, which is the big cat's.
    let cat: String
    @State private var fileIcon: NSImage? = nil
    @StateObject private var driver = UploadCatDriver(engine: .live())
```

**Edit `NotchBuddy/Sources/App/UploadCanvasView.swift`**, find this text (it occurs exactly once):

```swift
    /// Draws the cat where the sequence puts it and returns its layout (the file's flight ends at the mouth in it). The driver steps the cat first.
    private func drawCat(ctx: GraphicsContext, f: USFrame) -> CatGeometry.Layout? {
        let cat = driver.engine
        cat.useCharacter(CatConfig.shared.character)   // Settings → Cat → Character
        driver.follow(f, file: state.droppedFile?.name ?? "file")
        var laid: CatGeometry.Layout?
        // The sequence's squeeze rides along once the cat is a dot on the progress bar; the catch's own squash does the rest.
        let squeezeX = f.t >= USC.T_SHRINK_END ? f.sx : 1, squeezeY = f.t >= USC.T_SHRINK_END ? f.sy : 1
        var look = cat.look()
        look.pose.sx *= squeezeX; look.pose.sy *= squeezeY; look.pose.tilt += f.tilt
        look.badge = nil
        ctx.withCGContext { cg in
            laid = CatRenderer.draw(cg, look, cx: f.x, cy: f.y + f.hop, D: f.d, CatDrawOptions(fur: cat.cfg.furLines))
        }
        if let L = laid { cat.base = L.base; cat.mouthPoint = L.mouth }
        return laid
    }
```

and replace it with:

```swift
    /// Draws the cat where the sequence puts it and returns its layout (the file's flight ends at the mouth in it). The driver steps the cat first.
    private func drawCat(ctx: GraphicsContext, f: USFrame) -> CatGeometry.Layout? {
        let catEngine = driver.engine
        catEngine.useCharacter(cat)   // the cast's coat
        driver.follow(f, file: state.droppedFile?.name ?? "file")
        var laid: CatGeometry.Layout?
        // The sequence's squeeze rides along once the cat is a dot on the progress bar; the catch's own squash does the rest.
        let squeezeX = f.t >= USC.T_SHRINK_END ? f.sx : 1, squeezeY = f.t >= USC.T_SHRINK_END ? f.sy : 1
        var look = catEngine.look()
        look.pose.sx *= squeezeX; look.pose.sy *= squeezeY; look.pose.tilt += f.tilt
        look.badge = nil
        ctx.withCGContext { cg in
            laid = CatRenderer.draw(cg, look, cx: f.x, cy: f.y + f.hop, D: f.d, CatDrawOptions(fur: catEngine.cfg.furLines))
        }
        if let L = laid { catEngine.base = L.base; catEngine.mouthPoint = L.mouth }
        return laid
    }
```

- [ ] **Step 4: Run the programs to see them pass**

Run: `bash scripts/test-cat-renderer.sh 2>&1 | tail -1; bash scripts/test-cat-settings-store.sh 2>&1 | tail -1; bash scripts/test-cat-wiring.sh 2>&1 | tail -1`
Expected: `All tests passed.` three times.

Run: `for f in scripts/test-cat-engine.sh scripts/test-cat-greeting.sh scripts/test-cat-upload.sh scripts/test-cat-devpanel.sh; do bash "$f" 2>&1 | tail -1; done`
Expected: `All tests passed.` four times (the programs that compile the engine and the greeting are untouched).

- [ ] **Step 5: Build both targets**

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add NotchBuddy/Sources/App/BotCanvasView.swift NotchBuddy/Sources/App/IslandRootView.swift NotchBuddy/Sources/App/IslandViewContent.swift NotchBuddy/Sources/App/IslandWindowController.swift NotchBuddy/Sources/App/UploadCanvasView.swift NotchBuddy/Sources/App/GreetingCanvasView.swift NotchBuddy/Sources/App/CatGreetingRenderer.swift NotchBuddy/Sources/App/CatEngine.swift tests/CatRendererTests.swift tests/CatSettingsStoreTests.swift tests/CatWiringTests.swift
git commit -m "feat(cat): every cat view takes its coat from the cast

The big cat, the pill cats, the 2x2 grid, the greeting's four session cats, the drop view and the drag ghost are each handed their coat, so the per-frame follow
the Main cat can no longer overwrite an agent's. One test per call site, and no file re-reads the Main cat. A kitten's engine ignores useCharacter.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Two cats: the layout, cat 2, the pair's greeting and the island sheet (stage 4)

**Agent:** `nm-implementer-deep`. Layout numbers, a new view, the overview's card, the hit test and the greeting have to agree; nothing may change in One cat and A cat for each agent mode.

**Files:**
- Create: `NotchBuddy/Sources/App/PairCatViews.swift`
- Modify: `NotchBuddy/Sources/App/CatIslandLayout.swift`, `CatCast+App.swift`, `IslandRootView.swift`, `BotCanvasView.swift`, `IslandWindowController.swift`, `IslandViewContent.swift`, `CatGreeting.swift`, `CatGreetingRenderer.swift`, `GreetingCanvasView.swift`, `tests/CatAgentListTests.swift`, `tests/CatGreetingTests.swift`, `tests/CatRendererTests.swift`, `tests/CatWiringTests.swift`, `scripts/render-cats.sh`, `scripts/render-cats.swift` (the `--island` sheet), `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (by `xcodegen`)

**Interfaces:**
- Consumes: Task 5's `CatCast` (`second`), Task 7's `CatIslandLayout.compactX`, Task 9's `AppState.cast` and Task 10's views.
- Produces: `CatIslandLayout.pairExpanded(botX:botD:cy:) -> PairExpanded` (cat 1 18 pt left of where the one cat is, cat 2 Ø46, 40 pt right of it and 8 lower, which leaves a 6 pt gap between the two heads, the text 21 pt after cat 2's edge: 142 pt into the card instead of 108), `CatIslandLayout.stateWords(_:)`; `botPosition(…, display:)` (the big cat moves in Two cats mode only); `SecondCatPlacement`, `PairCatCanvasView`, `secondCatPlace(…)` (compact: Ø20 at 54 pt in the left ear; expanded overview: Ø46; a tap in the overview focuses its agent); the overview's second line ("Codex · waiting for you", or "No other agent") in Two cats mode only; `CatGreeting.Compact.botInset` (40, or 30 for the pair) and `CatGreeting.pairPop(_:leave:)`; `CatGreetingRenderer.draw(…, pair:)` (the second cat pops in beside the settled one); `bash scripts/render-cats.sh --island`.

- [ ] **Step 1: Write the failing tests**

The layout numbers (the prototype's, with its 6 pt gap between the heads, and the text keeps its 21 pt gap), the greeting's settled position and the pair's pop (a back-eased pop that starts 0.24 s after the fold begins, whole at 0.42 s, never while the pointer holds the island open), the rendered second cat (24 pt beside the first, 0.8 s into the fold; nothing without a pair), and the pins: `botPosition` moves cat 1 only in Two cats mode and all three of its users pass the display mode; cat 2 is placed once with the cats' mask and fade; a tap focuses its agent in the overview only; the ticker's old paddings stay when there is no cat 2; both badges stay clear of each other.

**Edit `tests/CatAgentListTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.check("One cat and A cat for each agent: one cat, 40 pt in", [CatIslandLayout.compactX(.one), CatIslandLayout.compactX(.perAgent)], [[40], [40]])
        CT.check("Two cats: 30 and 54 pt in", CatIslandLayout.compactX(.two), [30, 54])

        CT.finish()
```

and replace it with:

```swift
        CT.check("One cat and A cat for each agent: one cat, 40 pt in", [CatIslandLayout.compactX(.one), CatIslandLayout.compactX(.perAgent)], [[40], [40]])
        CT.check("Two cats: 30 and 54 pt in", CatIslandLayout.compactX(.two), [30, 54])
        CT.check("the greeting settles its cat where the pair's first cat lives, and the second pops in 24 pt (1.2 of Ø20) beside it", [CatIslandLayout.compactX(.two)[0], CatIslandLayout.compactX(.two)[1] - CatIslandLayout.compactX(.two)[0]], [30, 24])

        CT.section("the overview's left card in Two cats mode: the numbers of the prototype, and the text keeps its gap")
        let shippingLeading = CatIslandLayout.oneTextLeading, p = CatIslandLayout.pairExpanded(botX: 68, botD: 58, cy: 101)
        CT.check("cat 1 moves 18 pt left and keeps its size", [p.cat1X, p.cat1D], [50, 58])
        CT.check("cat 2 is 46 across, 40 pt right of where the one cat was and 8 pt lower", [p.cat2X, p.cat2Y, p.cat2D], [108, 109, 46])
        CT.check("the text starts 21 pt after cat 2's edge, 142 pt into the card", p.textLeading, 142)
        CT.check("as it starts 21 pt after the one cat's edge, 108 pt into the card, as it ships", 68 + 58 / 2 + CatIslandLayout.textGap - CatIslandLayout.cardX, shippingLeading)
        CT.checkTrue("the two heads do not touch: a 6 pt gap between cat 1's right edge and cat 2's left edge", (p.cat2X - p.cat2D / 2) - (p.cat1X + p.cat1D / 2) == 6)
        CT.check("what cat 2's agent is doing, in words", [CatIslandLayout.stateWords(.approval), CatIslandLayout.stateWords(.question), CatIslandLayout.stateWords(.thinking)], ["waiting for you", "has a question", "thinking"])
        CT.check("every one of the 11 states has words", CatState.allCases.map { CatIslandLayout.stateWords($0) }.filter { $0.isEmpty }, [])

        CT.finish()
```

**Edit `tests/CatGreetingTests.swift`**, find this text (it occurs exactly once):

```swift
        }
        CT.checkTrue("every slot is finite, before the start and after the end, held open, on a strip of any height", slotsFinite)
        CT.finish()
    }
```

and replace it with:

```swift
        }
        CT.checkTrue("every slot is finite, before the start and after the end, held open, on a strip of any height", slotsFinite)
        CT.section("Two cats mode: the settled cat is 30 pt in, and the second cat pops in beside it as the island folds")
        let two = G.Compact(width: 288, height: 32, botInset: 30), one = G.Compact(width: 288, height: 32)
        let settled = G.pose(G.length + 1, leave: G.GT.leave, into: two), alone = G.pose(G.length + 1, leave: G.GT.leave, into: one)
        CT.check("the greeting's cat ends 30 pt from the island's left edge, where the pair's first cat lives", settled.x, 320 - 144 + 30)
        CT.check("and 40 pt, as it always did, when nothing says otherwise", alone.x, 320 - 144 + 40)
        CT.check("a Compact made the old way has the old inset", [G.Compact().botInset, G.Compact(width: 288, height: 32).botInset], [40, 40])
        CT.checkNear("the pose is the same but for x: the greeting's own beats are untouched", G.pose(2.0, leave: G.GT.leave, into: two).x, G.pose(2.0, leave: G.GT.leave, into: one).x)
        CT.checkNear("the pop has not started when the island begins to fold", G.pairPop(G.GT.leave + 0.1), 0)
        CT.checkNear("it is whole 0.42 s after", G.pairPop(G.GT.leave + 0.42), 1)
        CT.checkTrue("it overshoots on the way, like the session cats' pop", (0..<18).map { G.pairPop(G.GT.leave + 0.24 + Double($0) * 0.01) }.max()! > 1.02)
        CT.check("it never starts while the pointer holds the island open", [G.pairPop(5, leave: .infinity), G.pairPop(100, leave: .infinity)], [0.0, 0.0])
        CT.checkNear("and a greeting cut short pops from its own fold", G.pairPop(1.0 + 0.42, leave: 1.0), 1)

        CT.finish()
    }
```

**Edit `tests/CatRendererTests.swift`**, find this text (it occurs exactly once):

```swift
        }

        CT.section("the greeting's session cats wear collars in the prototype's colours when a style is set, and none by default")
        do {
```

and replace it with:

```swift
        }

        CT.section("Two cats mode: the greeting's second cat pops in beside the settled one, and without a pair nothing is there")
        do {
            let two = CatGreeting.Compact(width: 288, height: 32, botInset: 30)
            func settle(_ pair: String?, _ after: Double) -> [UInt8] {
                let e = CatEngine(CatPresets.byID("shrimpy"), now: { 0 }, rand: { 0.5 }, cfg: CatConfig(), quiet: true)
                return render(640, 150) { CatGreetingRenderer.draw($0, t: CatGreeting.GT.leave + after, leave: CatGreeting.GT.leave, engine: e, end: two, pair: pair) }
            }
            let x2 = 320 - 144 + 30 + 24
            CT.checkTrue("0.8 s into the fold the second cat is there, 24 pt beside the first", alpha(settle("momo", 0.8), x2, 16, 640) > 200 && alpha(settle(nil, 0.8), x2, 16, 640) == 0)
            CT.checkTrue("and the first cat is where the pair's first cat lives, 30 pt from the island's edge", alpha(settle("momo", 0.8), 320 - 144 + 30, 16, 640) > 200)
            CT.checkTrue("it has not popped in when the fold begins", settle("momo", 0.1) == settle(nil, 0.1))
            CT.checkTrue("a different coat is a different cat", settle("momo", 0.8) != settle("ginger", 0.8))
        }

        CT.section("the greeting's session cats wear collars in the prototype's colours when a style is set, and none by default")
        do {
```

**Edit `tests/CatWiringTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkTrue("the drag ghost: the cast's drop coat", controller.contains("BotCanvasView(state: AppState.shared, cat: AppState.shared.cast.drop)"))

        CT.finish()
    }
```

and replace it with:

```swift
        CT.checkTrue("the drag ghost: the cast's drop coat", controller.contains("BotCanvasView(state: AppState.shared, cat: AppState.shared.cast.drop)"))

        CT.section("Two cats: cat 1 moves and cat 2 appears in that mode only; One cat and A cat for each agent keep the layout that ships")
        let pair = source("PairCatViews.swift"), cast2 = source("CatCast+App.swift")
        CT.checkTrue("the sources were read", pair.contains("struct SecondCatPlacement") && island.contains("func botPosition"))
        CT.checkTrue("botPosition takes the display mode (One cat by default) and moves cat 1 only in Two cats mode: 30 pt in the compact island, 18 pt left in the overview", island.contains("display: CatDisplayMode = .one") && island.contains("CatIslandLayout.compactX(display)[0]") && island.contains("if display == .two && view == .overview"))
        CT.check("the three users of botPosition (the placement, the look-at and the slap's hit test) pass the display mode", count("display: state.displayMode", in: island) + count("display: state.displayMode", in: canvas) + count("display: s.displayMode", in: controller), 3)
        CT.check("cat 2 is placed once, beside the big cat, with the same mask and the same fade for the greeting and the upload view", count("SecondCatPlacement(state: state", in: island), 1)
        CT.checkTrue("cat 2 is drawn only when the cast has one (Two cats mode), and shows the agent's state, asleep with the big cat", pair.contains("if let second = cast.second") && pair.contains("(task?.state ?? .idle).shown(asleep: state.catAsleep)"))
        CT.checkTrue("tapping cat 2 focuses its agent, in the overview only", pair.contains("state.setFocus(id)") && pair.contains(".allowsHitTesting(!place.compact && task != nil)") && pair.contains("guard state.view == .overview"))
        CT.checkTrue("the overview's text starts where CatIslandLayout says only when there is a cat 2, with the old paddings otherwise", content.contains("guard second != nil, let l = IslandConst.viewLayouts[.overview] else { return CGFloat(CatIslandLayout.oneTextLeading) }") && content.contains(".padding(.top, second == nil ? 6 : 4)") && content.contains(".padding(.top, second == nil ? 6 : 0)") && content.contains("if let second { secondLine(second) }"))
        CT.checkTrue("both cats' badges stay clear of each other: cat 1's on its left, cat 2's on its right when expanded and on its left in the compact island", canvas.contains("} else if state.displayMode == .two {") && pair.contains("options.badgeSide = compact ? -1 : 1"))
        CT.checkTrue("the greeting hands the pair to the renderer, and the settled cat is where the pair's first cat lives", greetingView.contains("pair: greeting.pair?[1]") && greetingView.contains("botInset: CatIslandLayout.compactX(state.cast.mode)[0]"))
        CT.checkTrue("the display mode comes from Settings", cast2.contains("var displayMode: CatDisplayMode { CatSettingsStore.shared.display.mode }"))

        CT.finish()
    }
```

Run: `bash scripts/test-cat-agent-list.sh 2>&1 | grep -c "error:"; bash scripts/test-cat-greeting.sh 2>&1 | grep -c "error:"; bash scripts/test-cat-renderer.sh 2>&1 | grep -c "error:"`
Expected: FAIL: three numbers above 0, the compile errors of the three programs (the dry run read `22`, `18` and `4`: the pair's layout, the greeting's inset and the renderer's pair argument do not exist yet).

Run: `bash scripts/test-cat-wiring.sh 2>&1 | tail -1`
Expected: FAIL: `10 test(s) failed.`

- [ ] **Step 2: The layout numbers and the greeting**

`CatGreeting.Compact` gains `botInset` (40: the contract's, unchanged; the app passes 30 in Two cats mode, where the pair's first cat lives) and `pairPop`; the renderer draws the second cat at 1.2 head widths from the settled one, popping in as the island folds.

**Edit `NotchBuddy/Sources/App/CatGreeting.swift`**, find this text (it occurs exactly once):

```swift
    struct Compact {
        var width = CatGreeting.compact, height = CatGreeting.notchH, botCenterY = 16.0, botDiameter = 20.0
        init() {}
        init(width: Double, height: Double) {
            self.width = width; self.height = height; botCenterY = height / 2; botDiameter = min(20, max(0, height - 6))
        }
        /// How much the compact island's mini grid shrinks on a strip shorter than 32 pt: `IslandRestingLayout.miniGridScale`, which the compact view uses.
```

and replace it with:

```swift
    struct Compact {
        var width = CatGreeting.compact, height = CatGreeting.notchH, botCenterY = 16.0, botDiameter = 20.0
        /// How far the settled cat is from the island's left edge: 40 pt, or 30 pt when two cats share the left ear (Two cats mode: `CatIslandLayout.compactX`).
        var botInset = 40.0
        init() {}
        init(width: Double, height: Double, botInset: Double = 40) {
            self.width = width; self.height = height; botCenterY = height / 2; botDiameter = min(20, max(0, height - 6)); self.botInset = botInset
        }
        /// How much the compact island's mini grid shrinks on a strip shorter than 32 pt: `IslandRestingLayout.miniGridScale`, which the compact view uses.
```

**Edit `NotchBuddy/Sources/App/CatGreeting.swift`**, find this text (it occurs exactly once):

```swift
        return Glide(grid: CatEase.inOut.at(seg(t, leave + GT3.glide0, leave + GT3.glide1)), four: CatEase.back.at(seg(t, leave + GT3.four0, leave + GT3.glide1)))
    }

    /// The prototype's row: head width, spacing, the first cat's inset from the island's right edge, and how far it sits below the strip's middle (pt).
```

and replace it with:

```swift
        return Glide(grid: CatEase.inOut.at(seg(t, leave + GT3.glide0, leave + GT3.glide1)), four: CatEase.back.at(seg(t, leave + GT3.four0, leave + GT3.glide1)))
    }

    /// Two cats mode: how far the second cat's pop-in has got (0 to a little over 1) `t` seconds in, when the island starts to fold at `leave`: it pops in beside the cat
    /// that has settled, from 0.24 s to 0.42 s after the fold begins, with the same overshoot as the session cats. Never (0) while the pointer holds the island open.
    static func pairPop(_ t: Double, leave: Double = GT.leave) -> Double { leave.isFinite ? CatEase.back.at(seg(t, leave + 0.24, leave + 0.42)) : 0 }

    /// The prototype's row: head width, spacing, the first cat's inset from the island's right edge, and how far it sits below the strip's middle (pt).
```

**Edit `NotchBuddy/Sources/App/CatGreeting.swift`**, find this text (it occurs exactly once):

```swift
    static func collapsePose(_ t: Double, leave tc: Double = GT.leave, into end: Compact = Compact()) -> Pose {
        let a = islandBase(tc), from = fallPose(tc, a)
        let e = CatEase.inOut.at(seg(t, tc, tc + GT.collapse)), bx = 320 - end.width / 2 + 40, bk = seg(t, tc + 0.14, tc + 0.26)
        let hands = 1 - seg(t, tc, tc + 0.15)
        return Pose(iw: lerp(a.iw, end.width, e), ih: lerp(a.ih, end.height, e), hb: lerp(a.hb, end.botDiameter / 1.34, e), x: lerp(from.x, bx, e), y: lerp(from.y, end.botCenterY, e),
```

and replace it with:

```swift
    static func collapsePose(_ t: Double, leave tc: Double = GT.leave, into end: Compact = Compact()) -> Pose {
        let a = islandBase(tc), from = fallPose(tc, a)
        let e = CatEase.inOut.at(seg(t, tc, tc + GT.collapse)), bx = 320 - end.width / 2 + end.botInset, bk = seg(t, tc + 0.14, tc + 0.26)
        let hands = 1 - seg(t, tc, tc + 0.15)
        return Pose(iw: lerp(a.iw, end.width, e), ih: lerp(a.ih, end.height, e), hb: lerp(a.hb, end.botDiameter / 1.34, e), x: lerp(from.x, bx, e), y: lerp(from.y, end.botCenterY, e),
```

**Edit `NotchBuddy/Sources/App/CatGreetingRenderer.swift`**, find this text (it occurs exactly once):

```swift
    /// `leave` is when the island starts to collapse (infinity while the pointer holds it open); `end` is the compact island it collapses into. `sessions` are the
    /// coats of the four session cats in the grid's cell order (the cast's `greeting.sessions`: in A cat for each agent mode the agents' own cats, so the glide hands over
    /// to the real grid without a change); nil: all four wear the engine's coat, the Main cat.
    static func draw(_ cg: CGContext, t: Double, leave: Double, engine e: CatEngine, end: Greeting.Compact, sessions: [String]? = nil) {
        let P = Greeting.pose(t, leave: leave, into: end), X = P.x, Y = P.y, D = P.hb * 1.34, p = e.p
        let st = Greeting.streakTime(t)
```

and replace it with:

```swift
    /// `leave` is when the island starts to collapse (infinity while the pointer holds it open); `end` is the compact island it collapses into. `sessions` are the
    /// coats of the four session cats in the grid's cell order (the cast's `greeting.sessions`: in A cat for each agent mode the agents' own cats, so the glide hands over
    /// to the real grid without a change); nil: all four wear the engine's coat, the Main cat. `pair`: in Two cats mode the coat of the second cat of the pair, which pops in
    /// beside the settled one (give `end` a `botInset` of 30, where the pair's first cat lives); nil: no second cat.
    static func draw(_ cg: CGContext, t: Double, leave: Double, engine e: CatEngine, end: Greeting.Compact, sessions: [String]? = nil, pair: String? = nil) {
        let P = Greeting.pose(t, leave: leave, into: end), X = P.x, Y = P.y, D = P.hb * 1.34, p = e.p
        let st = Greeting.streakTime(t)
```

**Edit `NotchBuddy/Sources/App/CatGreetingRenderer.swift`**, find this text (it occurs exactly once):

```swift
        CatRenderer.draw(cg, look, cx: X, cy: Y, D: D, o)
        let slots = Greeting.miniSlots(minis: P.minis, glide: Greeting.miniGlide(t, leave: leave), width: end.width, height: end.height)
        let coats = (0..<4).map { i in sessions.flatMap { $0.indices.contains(i) ? CatPresets.byID($0[i]) : nil } ?? p }
        drawMinis(cg, slots, presets: coats, scale: end.miniScale, collarStyle: e.collarStyle)
```

and replace it with:

```swift
        CatRenderer.draw(cg, look, cx: X, cy: Y, D: D, o)
        let slots = Greeting.miniSlots(minis: P.minis, glide: Greeting.miniGlide(t, leave: leave), width: end.width, height: end.height)
        // Two cats mode: the pair arrives together, the second cat popping in beside the one that has settled (`pair` is its coat).
        if let pair {
            let pop = Greeting.pairPop(t, leave: leave)
            if pop > 0.02 {
                var pose = CatPose(); pose.tint = 0.6
                CatRenderer.draw(cg, CatLook(preset: CatPresets.byID(pair), pose: pose, color: Theme.Greeting.tintRGB), cx: X + D * 1.2, cy: Y, D: D * pop, CatDrawOptions(badge: false))
            }
        }
        let coats = (0..<4).map { i in sessions.flatMap { $0.indices.contains(i) ? CatPresets.byID($0[i]) : nil } ?? p }
        drawMinis(cg, slots, presets: coats, scale: end.miniScale, collarStyle: e.collarStyle)
```

**Edit `NotchBuddy/Sources/App/CatIslandLayout.swift`**, find this text (it occurs exactly once):

```swift
    /// (the prototype's numbers), which the 80 pt ear holds.
    static func compactX(_ mode: CatDisplayMode) -> [Double] { mode == .two ? [30, 54] : [40] }
}

```

and replace it with:

```swift
    /// (the prototype's numbers), which the 80 pt ear holds.
    static func compactX(_ mode: CatDisplayMode) -> [Double] { mode == .two ? [30, 54] : [40] }

    /// The overview's left card in Two cats mode. The island's cards sit 10 pt in from its left edge; the one big cat is at `IslandConst.viewLayouts[.overview].botX` (68),
    /// 58 across, and the ticker's text starts 21 pt after its edge (108 pt into the card). With two cats the first moves 18 pt left, the second (46 across, 8 pt lower) sits
    /// beside it 40 pt to the right of where the one cat was, which leaves a 6 pt gap between the two heads (the prototype's numbers: cat 2 at 114 where the one cat is at 74),
    /// and the text starts 21 pt after the second's edge.
    struct PairExpanded: Equatable {
        var cat1X: Double, cat1D: Double
        var cat2X: Double, cat2Y: Double, cat2D: Double
        /// Where the ticker's text starts, in points from the left edge of the card.
        var textLeading: Double
    }
    static let cardX = 10.0, oneTextLeading = 108.0, textGap = 21.0, pairCat2D = 46.0
    /// `botX`, `botD` and `cy` are where `botPosition` puts the one big cat in the overview.
    static func pairExpanded(botX: Double, botD: Double, cy: Double) -> PairExpanded {
        let cat2X = botX + 40
        return PairExpanded(cat1X: botX - 18, cat1D: botD, cat2X: cat2X, cat2Y: cy + 8, cat2D: pairCat2D, textLeading: cat2X + pairCat2D / 2 + textGap - cardX)
    }

    /// What cat 2's agent is doing, for the second line of the overview's ticker ("Codex · waiting for you").
    static func stateWords(_ s: CatState) -> String {
        switch s {
        case .idle: return "idle"
        case .working: return "working"
        case .thinking: return "thinking"
        case .searching: return "searching"
        case .approval: return "waiting for you"
        case .question: return "has a question"
        case .error: return "hit an error"
        case .finished: return "finished"
        case .ratelimit: return "rate limited"
        case .sleeping: return "asleep"
        case .dizzy: return "dizzy"
        }
    }
}

```

- [ ] **Step 3: Cat 2, the overview's card and the greeting's hand-over**

`PairCatCanvasView` is a full engine of its own (the big cat's kind) in the coat the cast gives it, in the state of the agent it shows, collared in that agent's colour when it is busy, asleep with the big cat, looking at the pointer. In the compact island its badge sits on its left (the right faces the camera housing); expanded it sits on its right and cat 1's on its left. In One cat and A cat for each agent mode `cast.second` is nil and none of this draws.

**Create `NotchBuddy/Sources/App/PairCatViews.swift`**:

```swift
import SwiftUI
import QuartzCore

// Two cats mode: pair cat 2, beside the big cat, showing the busiest other agent (`CatCast.Result.second`). In the compact island it is a second Ø20 cat in the left
// ear (`CatIslandLayout.compactX`); in the expanded overview it is a Ø46 cat beside the big one, which you can tap to bring its agent into focus. It exists only in
// Two cats mode: in the other two modes `AppState.cast.second` is nil and nothing here is drawn.

/// Where cat 2 sits, in island coordinates, or nil when it is not shown (any view but the overview, the greeting and the upload view draw their own cats).
@MainActor
func secondCatPlace(state: AppState, islandW: CGFloat, islandH: CGFloat) -> (cx: CGFloat, cy: CGFloat, d: CGFloat, compact: Bool)? {
    switch state.mode {
    case .hidden: return nil
    case .compact:
        let resting = IslandRestingLayout(width: islandW, height: islandH)
        return (CGFloat(CatIslandLayout.compactX(.two)[1]), resting.botCenterY, resting.botDiameter, true)
    case .expanded:
        guard state.view == .overview else { return nil }
        let one = botPosition(mode: .expanded, view: .overview, islandW: islandW, islandH: islandH, uploadProgress: 0)
        let pair = CatIslandLayout.pairExpanded(botX: Double(one.0), botD: Double(one.2), cy: Double(one.1))
        return (CGFloat(pair.cat2X), CGFloat(pair.cat2Y), CGFloat(pair.cat2D), false)
    }
}

struct SecondCatPlacement: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    let islandH: CGFloat

    var body: some View {
        let cast = state.cast
        if let second = cast.second, let place = secondCatPlace(state: state, islandW: islandW, islandH: islandH) {
            let task = second.pill.flatMap { id in state.tasks.first { $0.id == id } }
            let canvas = place.d / 0.6
            PairCatCanvasView(state: state, task: task, cat: second.cat, compact: place.compact, centre: CGPoint(x: place.cx, y: place.cy), islandW: islandW)
                .frame(width: canvas, height: canvas)
                .position(x: place.cx, y: place.cy)
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: place.cx)
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: place.cy)
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: canvas)
                .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
                // Tapping cat 2 in the overview focuses its agent, like tapping a pill. Everywhere else the cat is only drawn.
                .contentShape(Circle().size(width: place.d, height: place.d).offset(x: place.cx - place.d / 2, y: place.cy - place.d / 2))
                .allowsHitTesting(!place.compact && task != nil)
                .onTapGesture {
                    guard let id = task?.id else { return }
                    state.setFocus(id)
                    SoundEngine.shared.play("blip")
                }
        }
    }
}

/// The second cat: a full engine of its own (the big cat's kind), in the coat the cast gives it, in the state of the agent it shows (idle with no badge when there is no
/// other agent), wearing that agent's colour as a collar when it is busy, and asleep with the big cat.
struct PairCatCanvasView: View {
    @ObservedObject var state: AppState
    let task: AgentTask?
    let cat: String
    let compact: Bool
    /// Where the cat is, in island coordinates, and how wide the island is: the cat looks at the pointer from there.
    let centre: CGPoint
    let islandW: CGFloat
    @StateObject private var engine = CatEngine.live()

    var body: some View {
        TimelineView(.animation(paused: state.mode == .hidden)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                let dt = CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                engine.useCharacter(cat)   // the pair's second coat
                let shown = (task?.state ?? .idle).shown(asleep: state.catAsleep)
                engine.setState(shown)
                engine.collar = CatRules.bigCatCollar(colour: task?.color, state: CatState(rawValue: shown.rawValue) ?? .idle)
                let screen = NSScreen.main ?? NSScreen.screens[0]
                let look = CatGeometry.cursorLook(dx: Double(state.mousePosition.x - (screen.frame.midX - islandW / 2 + centre.x)), dy: Double(state.mousePosition.y - centre.y))
                engine.lookX = look.x
                engine.lookY = look.y
                engine.update(dt: dt)
                let D = Double(size.width) * 0.6, cx = Double(size.width) / 2, cy = Double(size.height) / 2
                var options = CatDrawOptions(badge: task != nil)
                options.badgeSide = compact ? -1 : 1              // in the compact island the right side faces the camera housing
                if compact { options.earCeiling = cy - Double(centre.y) }   // the top of the island is the top of the screen
                options.collar = engine.collarPaint(dpr: Double(context.environment.displayScale))
                var laid: CatGeometry.Layout?
                context.withCGContext { cg in laid = CatRenderer.draw(cg, engine.look(), cx: cx, cy: cy, D: D, options) }
                if let laid {
                    engine.base = laid.base
                    engine.mouthPoint = laid.mouth
                }
            }
        }
    }
}
```

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**, find this text (it occurs exactly once):

```swift
                    options.badgeSide = -1                       // never under the camera housing
                    options.earCeiling = cy - Double(restingY(state: state))   // the top of the island is the top of the screen
                }
                let L = drawCat(context, engine, cx: cx, cy: cy, D: D, options)
```

and replace it with:

```swift
                    options.badgeSide = -1                       // never under the camera housing
                    options.earCeiling = cy - Double(restingY(state: state))   // the top of the island is the top of the screen
                } else if state.displayMode == .two {
                    options.badgeSide = -1                       // in Two cats mode cat 1's badge sits on its left, clear of cat 2
                }
                let L = drawCat(context, engine, cx: cx, cy: cy, D: D, options)
```

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**, find this text (it occurs exactly once):

```swift
        let (botCx, botCy, _, _) = botPosition(mode: state.mode, view: state.view,
                                               islandW: islandW, islandH: actualH,
                                               uploadProgress: state.uploadProgress)
        return (islandW, botCx, botCy)
    }
```

and replace it with:

```swift
        let (botCx, botCy, _, _) = botPosition(mode: state.mode, view: state.view,
                                               islandW: islandW, islandH: actualH,
                                               uploadProgress: state.uploadProgress, display: state.displayMode)
        return (islandW, botCx, botCy)
    }
```

**Edit `NotchBuddy/Sources/App/CatCast+App.swift`**, find this text (it occurs exactly once):

```swift
    }

    /// A pill that has just been created gets its coat now, before anything draws it, and keeps it: an agent pill is given one if it has none (Claude Code is
    /// Shrimpy and Codex is Momo; every other agent a random coat that no other agent and not the Main cat wears), and any other pill is left alone.
```

and replace it with:

```swift
    }

    /// The display mode Settings has: where the big cat sits (`botPosition`) depends on it, and so does the hit test of a slap.
    var displayMode: CatDisplayMode { CatSettingsStore.shared.display.mode }

    /// What the island calls an agent: the pill catalog's name (Codex, Gemini CLI), Claude Code for the Claude Code pill, else the name the pill came with.
    func agentName(for pillId: String) -> String {
        pillId == "integration_claude" ? "Claude Code" : PillCatalog.definition(for: pillId)?.name ?? tasks.first { $0.id == pillId }?.name ?? pillId
    }

    /// A pill that has just been created gets its coat now, before anything draws it, and keeps it: an agent pill is given one if it has none (Claude Code is
    /// Shrimpy and Codex is Momo; every other agent a random coat that no other agent and not the Main cat wears), and any other pill is left alone.
```

**Edit `NotchBuddy/Sources/App/GreetingCanvasView.swift`**, find this text (it occurs exactly once):

```swift
                engine.useCharacter(greeting.cat)   // the Main cat falls in, in every display mode
                engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                let end = CatGreeting.Compact(width: Double(state.notchWidth) + 160, height: Double(state.notchHeight))
                context.withCGContext { cg in
                    CatGreetingRenderer.draw(cg, t: t, leave: tc, engine: engine, end: end, sessions: greeting.sessions)
                }
            }
```

and replace it with:

```swift
                engine.useCharacter(greeting.cat)   // the Main cat falls in, in every display mode
                engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                let end = CatGreeting.Compact(width: Double(state.notchWidth) + 160, height: Double(state.notchHeight), botInset: CatIslandLayout.compactX(state.cast.mode)[0])
                context.withCGContext { cg in
                    CatGreetingRenderer.draw(cg, t: t, leave: tc, engine: engine, end: end, sessions: greeting.sessions, pair: greeting.pair?[1])
                }
            }
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
                // The top of the strip is the top of the screen, so this mask cannot give the cat's
                // ears any headroom: BotCanvasView fits them under that edge (CatDrawOptions.earCeiling).
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: islandWidth,
```

and replace it with:

```swift
                // The top of the strip is the top of the screen, so this mask cannot give the cat's
                // ears any headroom: BotCanvasView fits them under that edge (CatDrawOptions.earCeiling).
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: islandWidth,
                                      height: state.mode == .expanded ? 320 : islandHeight)
                }
                .opacity(uploadActive || greetingActive ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: uploadActive || greetingActive)

            // Two cats mode: cat 2, beside the big cat (nothing at all in the other modes).
            SecondCatPlacement(state: state, islandW: islandWidth, islandH: islandHeight)
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: islandWidth,
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift

    var body: some View {
        let (cx, cy, diameter, opacity) = botPosition(mode: state.mode, view: state.view, islandW: islandW, islandH: islandH, uploadProgress: state.uploadProgress, hasNotch: state.hasNotch)
        let canvasSize = diameter / 0.6
        let overhang: CGFloat = 40
```

and replace it with:

```swift

    var body: some View {
        let (cx, cy, diameter, opacity) = botPosition(mode: state.mode, view: state.view, islandW: islandW, islandH: islandH, uploadProgress: state.uploadProgress, hasNotch: state.hasNotch, display: state.displayMode)
        let canvasSize = diameter / 0.6
        let overhang: CGFloat = 40
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
}

func botPosition(mode: IslandMode, view: IslandView, islandW: CGFloat, islandH: CGFloat, uploadProgress: Double, hasNotch: Bool = true) -> (CGFloat, CGFloat, CGFloat, Double) {
    let resting = IslandRestingLayout(width: islandW, height: islandH)
    switch mode {
```

and replace it with:

```swift
}

/// Where the big cat sits, in island coordinates: x, y, head width and opacity. `display` is the display mode: in Two cats mode cat 1 moves to make room for cat 2
/// (`CatIslandLayout`), in the compact island and in the overview only; One cat and A cat for each agent are exactly as they have always been.
func botPosition(mode: IslandMode, view: IslandView, islandW: CGFloat, islandH: CGFloat, uploadProgress: Double, hasNotch: Bool = true, display: CatDisplayMode = .one) -> (CGFloat, CGFloat, CGFloat, Double) {
    let resting = IslandRestingLayout(width: islandW, height: islandH)
    switch mode {
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
        return hasNotch ? (46, 16, 6, 0)
            : (islandW / 2, resting.botCenterY, resting.botDiameter, 1)
    case .compact: return (40, resting.botCenterY, resting.botDiameter, 1)
    case .expanded:
        let layout = IslandConst.viewLayouts[view]!
```

and replace it with:

```swift
        return hasNotch ? (46, 16, 6, 0)
            : (islandW / 2, resting.botCenterY, resting.botDiameter, 1)
    case .compact: return (CGFloat(CatIslandLayout.compactX(display)[0]), resting.botCenterY, resting.botDiameter, 1)
    case .expanded:
        let layout = IslandConst.viewLayouts[view]!
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
            return (cx, layout.botY ?? 103, diameter, 1)
        }
        let cx = layout.botX
        let cy: CGFloat
        if let fixedY = layout.botY {
```

and replace it with:

```swift
            return (cx, layout.botY ?? 103, diameter, 1)
        }
        var cx = layout.botX
        let cy: CGFloat
        if let fixedY = layout.botY {
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
            let cardH: CGFloat = 84
            cy = headerBottom + (islandH - headerBottom - cardH) / 2 + cardH / 2
        }
        return (cx, cy, diameter, 1)
```

and replace it with:

```swift
            let cardH: CGFloat = 84
            cy = headerBottom + (islandH - headerBottom - cardH) / 2 + cardH / 2
        }
        if display == .two && view == .overview {
            cx = CGFloat(CatIslandLayout.pairExpanded(botX: Double(cx), botD: Double(diameter), cy: Double(cy)).cat1X)
        }
        return (cx, cy, diameter, 1)
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift

    var agent: AgentTask? { state.focusTask }

    var body: some View {
```

and replace it with:

```swift

    var agent: AgentTask? { state.focusTask }

    /// Two cats mode only: cat 2 and the agent it shows. The cats take more of the left card, so the text starts further right (`CatIslandLayout`) and gains a
    /// second line for cat 2's agent. In the other modes `second` is nil and the card is exactly what it has always been.
    private var second: CatCast.Spot? { state.cast.second }
    private var textLeading: CGFloat {
        guard second != nil, let l = IslandConst.viewLayouts[.overview] else { return CGFloat(CatIslandLayout.oneTextLeading) }
        return CGFloat(CatIslandLayout.pairExpanded(botX: Double(l.botX), botD: Double(l.botDiameter), cy: 0).textLeading)
    }

    /// Cat 2's line under the ticker: "Codex · waiting for you", in the colour of the state when it needs you.
    private func secondLine(_ s: CatCast.Spot) -> some View {
        let task = s.pill.flatMap { id in state.tasks.first { $0.id == id } }
        let words = task.map { "\(state.agentName(for: $0.id)) · \(CatIslandLayout.stateWords(CatState(rawValue: $0.state.rawValue) ?? .idle))" } ?? "No other agent"
        let colour: String = {
            switch task?.state {
            case .approval: return "#F5A524"
            case .question: return "#22D3EE"
            case .error: return "#F4505E"
            default: return "#8E939C"
            }
        }()
        return Text(words)
            .font(.system(size: 11))
            .foregroundColor(Color(hex: colour))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, textLeading)
            .padding(.trailing, 12)
            .padding(.top, 2)
    }

    var body: some View {
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
                                }
                            }
                            .padding(.top, 6)
                            .padding(.leading, 108)
                            .padding(.trailing, 36)

```

and replace it with:

```swift
                                }
                            }
                            .padding(.top, second == nil ? 6 : 4)
                            .padding(.leading, textLeading)
                            .padding(.trailing, 36)

```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
                            })
                                .frame(height: 44)
                                .padding(.top, 6)
                                .padding(.leading, 108)
                                .padding(.trailing, 12)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
```

and replace it with:

```swift
                            })
                                .frame(height: 44)
                                .padding(.top, second == nil ? 6 : 0)
                                .padding(.leading, textLeading)
                                .padding(.trailing, 12)
                            if let second { secondLine(second) }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, find this text (it occurs exactly once):

```swift
        let (cx, cy, diameter, _) = botPosition(mode: s.mode, view: s.view,
                                                  islandW: islandW, islandH: islandH,
                                                  uploadProgress: s.uploadProgress, hasNotch: s.hasNotch)
        let radius = (diameter / 0.6) / 2
        // botPosition cy is from island TOP; panel AppKit coords have y=0 at bottom
```

and replace it with:

```swift
        let (cx, cy, diameter, _) = botPosition(mode: s.mode, view: s.view,
                                                  islandW: islandW, islandH: islandH,
                                                  uploadProgress: s.uploadProgress, hasNotch: s.hasNotch, display: s.displayMode)
        let radius = (diameter / 0.6) / 2
        // botPosition cy is from island TOP; panel AppKit coords have y=0 at bottom
```

- [ ] **Step 4: Run the programs to see them pass**

Run: `bash scripts/test-cat-agent-list.sh 2>&1 | tail -1; bash scripts/test-cat-greeting.sh 2>&1 | tail -1; bash scripts/test-cat-renderer.sh 2>&1 | tail -1; bash scripts/test-cat-wiring.sh 2>&1 | tail -1`
Expected: `All tests passed.` four times.

- [ ] **Step 5: The island in the three modes, drawn without the app**

A new mode of `render-cats.sh`: the compact strip and the expanded overview for each display mode, made of the real cats in the places the app's own numbers give (`CatIslandLayout`, `CatCast`, the overview's 68-pt cat and 42-pt card top), with the sample island of Settings' preview. The texts and the cards are a mock to judge the room the cats take, not their look.

**Edit `scripts/render-cats.sh`**, find this text (it occurs exactly once):

```bash
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
    scripts/render-cats.swift \
    -o "$BUILD_DIR/render-cats"
```

and replace it with:

```bash
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatIslandLayout.swift \
    scripts/render-cats.swift \
    -o "$BUILD_DIR/render-cats"
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
//                                                                  --scale is the device pixel ratio the readability floors are in: try 1 and 2
//   bash scripts/render-cats.sh --dance --cats shrimpy,momo        one beat of the Apple Music dance in eight frames: the hop alone, then with the head-bob and ears
//   bash scripts/render-cats.sh --eyes --scale 1                   the compact cats' eyes: today's flat ink eyes next to the coloured small eyes, every coat and its kitten at Ø12
//                                                                  to Ø24 (--scale is the device pixel ratio: look at 1 and 2)
```

and replace it with:

```swift
//                                                                  --scale is the device pixel ratio the readability floors are in: try 1 and 2
//   bash scripts/render-cats.sh --dance --cats shrimpy,momo        one beat of the Apple Music dance in eight frames: the hop alone, then with the head-bob and ears
//   bash scripts/render-cats.sh --island --scale 2                 the compact and the expanded island in the three display modes (One cat, A cat for each agent, Two cats), a mock
//                                                                  made of the real cats and the app's own layout numbers (CatIslandLayout) and cast (CatCast)
//   bash scripts/render-cats.sh --eyes --scale 1                   the compact cats' eyes: today's flat ink eyes next to the coloured small eyes, every coat and its kitten at Ø12
//                                                                  to Ø24 (--scale is the device pixel ratio: look at 1 and 2)
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case dance
        case eyes
    }

```

and replace it with:

```swift
        case dance
        case eyes
        case island
    }

```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
            case "--dance": a.mode = .dance
            case "--eyes": a.mode = .eyes
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

and replace it with:

```swift
            case "--dance": a.mode = .dance
            case "--eyes": a.mode = .eyes
            case "--island": a.mode = .island
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case .dance: sheet = danceSheet(a)
        case .eyes: sheet = eyeSheet(a)
        }
        sheet.write(to: a.out)
```

and replace it with:

```swift
        case .dance: sheet = danceSheet(a)
        case .eyes: sheet = eyeSheet(a)
        case .island: sheet = islandSheet(a)
        }
        sheet.write(to: a.out)
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
    private static func slotW(_ d: Double) -> Double { max(62, d * 2.2) }

    // MARK: Small eyes: today's ink eyes next to the coloured ones

```

and replace it with:

```swift
    private static func slotW(_ d: Double) -> Double { max(62, d * 2.2) }

    // MARK: The island in the three display modes

    /// The island as the app lays it out, in a mock: the compact strip (345 by 32 pt, a notch of 185 in the middle) and the expanded overview (640 by 160) for each
    /// display mode, with the sample island of Settings' Display preview (`CatDisplaySample`). The cats are the real ones in the places `CatIslandLayout`, `CatCast` and the
    /// app's `botPosition` give them; the texts and the cards are drawn the way the prototype draws its mock, to judge the room they leave, not their look.
    @MainActor static func islandSheet(_ a: Args) -> Sheet {
        let rowH = 196.0, left = 150.0, cw = 345.0, ew = 640.0, gap = 28.0
        let sheet = Sheet(width: left + cw + gap + ew + 16, height: rowH * 3 + 8, scale: a.scale)
        let cg = sheet.cg
        for (i, mode) in CatDisplayMode.allCases.enumerated() {
            let top = Double(i) * rowH + 8
            let display = CatDisplaySettings(mode: mode, pair: CatDisplaySettings.defaultPair, agentCats: [:])
            let cast = CatDisplaySample.cast(display, main: "shrimpy")
            let name = ["one": "One cat", "perAgent": "A cat for each agent", "two": "Two cats"][mode.rawValue]!
            CatDraw.text(cg, name, x: 14, y: top + 20, size: 12, bold: true, color: CatDraw.white(0.9), anchor: .left)
            drawCompact(cg, cast, ox: left, oy: top + 10)
            drawExpanded(cg, cast, ox: left + cw + gap, oy: top)
        }
        return sheet
    }

    /// A cat on its own fake clock for 1.2 s, then drawn: `coat` in `state`, `d` across, centred at (cx, cy).
    @MainActor private static func drawIslandCat(_ cg: CGContext, _ coat: String, _ state: CatState, colour: String?, big: Bool, cx: Double, cy: Double, d: Double, top: Double? = nil, badgeSide: Double = 1, seed: UInt32) {
        let s = scene(CatPresets.byID(coat), profile: "playful", D: d, seed: seed, state: state, mini: !big, quiet: true)
        for _ in 0..<72 { s.step() }
        s.e.collar = big ? CatRules.bigCatCollar(colour: colour, state: state) : colour
        var options = CatDrawOptions(badge: big)
        options.badgeSide = badgeSide
        if let top { options.earCeiling = top }
        CatRenderer.draw(cg, s.e.look(time: s.clock.t / 1000), cx: cx, cy: cy, D: d, options)
    }

    private static func samplePill(_ id: String?) -> CatDisplaySample.Pill? { CatDisplaySample.pills.first { $0.id == id } }

    @MainActor static func drawCompact(_ cg: CGContext, _ cast: CatCast.Result, ox: Double, oy: Double) {
        let W = 345.0, H = 32.0
        cg.fill(CatDraw.roundRect(ox, oy, W, H, 14), CatDraw.black(1))
        cg.fill(CatDraw.roundRect(ox + 80, oy, W - 160, H, 10), CatDraw.rgb([24, 25, 28]))
        let xs = CatIslandLayout.compactX(cast.mode)
        func big(_ spot: CatCast.Spot, _ x: Double, _ seed: UInt32) {
            let p = samplePill(spot.pill)
            drawIslandCat(cg, spot.cat, p?.state ?? .idle, colour: p?.color, big: true, cx: ox + x, cy: oy + H / 2, d: 20, top: -H / 2 + 0, badgeSide: -1, seed: seed)
        }
        big(cast.big, xs[0], 1)
        if let second = cast.second { big(second, xs[1], 2) }
        for (i, p) in cast.pills.enumerated() {
            let sp = samplePill(p.pill)
            drawIslandCat(cg, p.cat, sp?.state ?? .idle, colour: sp?.color, big: false, cx: ox + W - 40 + (i % 2 == 1 ? 8 : -8), cy: oy + H / 2 + (i < 2 ? -8 : 8), d: 12, seed: UInt32(10 + i))
        }
    }

    @MainActor static func drawExpanded(_ cg: CGContext, _ cast: CatCast.Result, ox: Double, oy: Double) {
        let W = 640.0, H = 160.0, two = cast.second != nil
        cg.fill(CatDraw.roundRect(ox, oy, W, H, 22), CatDraw.black(1))
        let card = CatDraw.rgb([19, 20, 23])
        cg.fill(CatDraw.roundRect(ox + CatIslandLayout.cardX, oy + 42, 322, 84, 12), card)
        cg.fill(CatDraw.roundRect(ox + 342, oy + 42, 288, 84, 12), card)
        // the cats: where botPosition puts the one big cat (68, 101, 58 across), and the pair's
        let cy = 101.0, one = CatIslandLayout.pairExpanded(botX: 68, botD: 58, cy: cy)
        let bigPill = samplePill(cast.big.pill)
        drawIslandCat(cg, cast.big.cat, bigPill?.state ?? .idle, colour: bigPill?.color, big: true, cx: ox + (two ? one.cat1X : 68), cy: oy + cy, d: 58, badgeSide: two ? -1 : 1, seed: 3)
        if let second = cast.second {
            let p = samplePill(second.pill)
            drawIslandCat(cg, second.cat, p?.state ?? .idle, colour: p?.color, big: true, cx: ox + one.cat2X, cy: oy + one.cat2Y, d: one.cat2D, badgeSide: 1, seed: 4)
        }
        // the left card's text, from where the layout says it starts
        let lead = ox + CatIslandLayout.cardX + (two ? one.textLeading : CatIslandLayout.oneTextLeading), titleY = oy + 42 + 4 + (two ? 4 : 6) + 8, tickerY = titleY + 8 + (two ? 0 : 6)
        CatDraw.text(cg, bigPill?.name ?? "Nothing in focus", x: lead, y: titleY, size: 12, bold: true, color: CatDraw.white(0.95), anchor: .left)
        CatDraw.text(cg, "Edit CatFace.swift", x: lead - 10 * 0.0, y: tickerY + 8, size: 10.5, bold: false, color: CatDraw.white(0.4), anchor: .left)
        CatDraw.text(cg, "Run the cat tests", x: lead, y: tickerY + 30, size: 12, bold: false, color: CatDraw.white(0.85), anchor: .left)
        if let second = cast.second {
            let p = samplePill(second.pill)
            let words = p.map { "\($0.name) · \(CatIslandLayout.stateWords($0.state))" } ?? "No other agent"
            let tone: [Double] = p?.state == .approval ? [245, 165, 36] : [142, 147, 156]
            CatDraw.text(cg, words, x: lead, y: tickerY + 44 + 2 + 7, size: 11, bold: false, color: CatDraw.rgb(tone), anchor: .left)
        }
        // the right card: the row of pills, two by two, each with its cat
        for (i, p) in cast.pills.enumerated() {
            let x = ox + 342 + 8 + Double(i % 2) * (134 + 4), y = oy + 42 + 12 + Double(i / 2) * 32, sp = samplePill(p.pill)
            cg.fill(CatDraw.roundRect(x, y, 134, 28, 14), CatDraw.rgb([14, 15, 17]))
            drawIslandCat(cg, p.cat, sp?.state ?? .idle, colour: sp?.color, big: false, cx: x + 8 + 11, cy: y + 14, d: 22, seed: UInt32(20 + i))
            CatDraw.text(cg, sp?.name ?? p.pill, x: x + 67, y: y + 14, size: 10, bold: true, color: CatDraw.rgb([107, 112, 121]))
        }
    }

    // MARK: Small eyes: today's ink eyes next to the coloured ones

```

Run: `mkdir -p "${TMPDIR:-/tmp}/b-mac-2" && bash scripts/render-cats.sh --island --scale 2 --out "${TMPDIR:-/tmp}/b-mac-2/island.png"`
Expected: `wrote …/b-mac-2/island.png` (the folder has to exist: the renderer does not make it and stops on a nil without it). Look at it: three rows, **One cat** (Shrimpy alone in the left ear, four Shrimpies in the grid, one cat in the overview's left card and four pills with Shrimpy), **A cat for each agent** (Shrimpy on the left, a different cat for Codex, Gemini CLI and Antigravity in the grid and the pills, Stripe in the Main cat) and **Two cats** (two Ø20 cats side by side in the left ear with an amber dot on the second; in the overview Ø58 and Ø46 cats side by side with a small gap between the heads, the text starting further right, a second amber line "Codex · waiting for you" under the ticker, and three pills: Codex has left the row and the grid).

- [ ] **Step 6: Build both targets**

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `Created project at …` and `** BUILD SUCCEEDED **`.

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add NotchBuddy/Sources/App/PairCatViews.swift NotchBuddy/Sources/App/CatIslandLayout.swift NotchBuddy/Sources/App/CatCast+App.swift NotchBuddy/Sources/App/IslandRootView.swift NotchBuddy/Sources/App/BotCanvasView.swift NotchBuddy/Sources/App/IslandWindowController.swift NotchBuddy/Sources/App/IslandViewContent.swift NotchBuddy/Sources/App/CatGreeting.swift NotchBuddy/Sources/App/CatGreetingRenderer.swift NotchBuddy/Sources/App/GreetingCanvasView.swift tests/CatAgentListTests.swift tests/CatGreetingTests.swift tests/CatRendererTests.swift tests/CatWiringTests.swift scripts/render-cats.sh scripts/render-cats.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): Two cats mode

Compact: two Ø20 cats in the left ear. Expanded: cat 1 at Ø58 and cat 2 at Ø46 side by side, the ticker's text further right with a second line for cat 2's agent;
tapping cat 2 focuses its agent; the second agent leaves the row and the grid; the greeting settles its cat where the pair's first cat lives and the second pops in
beside it. One cat and A cat for each agent keep the shipping layout (pinned). render-cats.sh --island draws the three modes without the app.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Kittens in Swift: the reducer, the order, the slots, from `kitten-cases.json` (stage 5)

**Agent:** `nm-implementer-light`. The code is given in full; the tests prove it.

**Files:**
- Create: `NotchBuddy/Sources/App/CatKittens.swift`, `tests/CatKittensTests.swift`, `scripts/test-cat-kittens.sh`

**Interfaces:**
- Consumes: Task 3's `CatDisplayMode` and `CatDisplaySettings.modeOf`, `CatRules.toolState` and `CatRules.sleepAfterMs`; B-0's `kittenStep`, `kittenOrder`, `kittenView`, `kittenSlots`, `kittenPlaceOf`, `cleanKittens`, `KITTEN_PLACES` and `tests/fixtures/cat/kitten-cases.json` (`limits`, `states`, `places`, `scripts`: 21 scripts of 105 events, `order`, `views`, `cleans`, `slots`: 35 rows, `placeOf`).
- Produces: `CatKittens.Kitten(id:type:session:state:born:last:until:)` and `CatKittens.State` (`working`, `searching`, `approval`, `leaving`); `CatKittens.Event` with its constructors `.start`, `.tool`, `.permission`, `.resolved`, `.stop`, `.end`, `.sweep`, `.tick`; `CatKittens.step(_:_:) -> [Kitten]` (pure: the time is in the event, an event whose time is not finite changes nothing); `order(_:)`, `view(_:now:)`, `clean(_:)`; `slots(_ place: String, _ kittens: [Kitten]) -> Slots` (`shown`, `more`, `moreAt`, `label`; `json` for the fixtures), `placeOf(_:expanded:) -> String`; `places`, `max` (8), `leaveMs` (600), `isKittenId`.

- [ ] **Step 1: Write the failing tests**

The program replays the fixture one event at a time and compares the whole list after each of the 105 events, then the order, the view, the clean-up, the places and the 35 slot rows. It adds what JSON cannot write: a time that is NaN or infinite changes nothing (not even the leaving kittens that are due), the app's own sequences (a tool event with no `agent_id` belongs to the parent, a second stop changes nothing, a start after the stop is a new kitten, one session ending leaves the other's), and 4000 seeded events that must keep the list's rules (at most 8, no repeated ID, a leaving kitten has a time, a tick drops only what is due).

**Create `scripts/test-cat-kittens.sh`**:

```bash
#!/usr/bin/env bash
# Cat kittens: the reducer (CatKittens.step), the order, the view, the places and the slots against kitten-cases.json, and what the fixture cannot write (a time that is
# not finite, a fuzz of events that must keep the list's invariants).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-kittens.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatKittens.swift \
    tests/CatTestSupport.swift tests/CatKittensTests.swift \
    -o "$TEST_DIR/cat-kittens-tests"
"$TEST_DIR/cat-kittens-tests"
```

**Create `tests/CatKittensTests.swift`**:

```swift
import Foundation

@main
enum CatKittensTests {
    typealias K = CatKittens

    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }

    /// A JSON number (a boolean, text and null are not numbers).
    static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    /// The fixture's kitten list, in the app's types: an entry that is not an object, has no text id, a state that is not one of the four or a time that is not a number is
    /// not a kitten (the app never builds one); `clean` does the rest, as the contract's `cleanKittens` does.
    static func kittens(_ raw: Any?) -> [K.Kitten] {
        (raw as? [Any] ?? []).compactMap { entry in
            guard let k = entry as? [String: Any], let id = k["id"] as? String, let s = k["state"] as? String, let state = K.State(rawValue: s), let born = number(k["born"]), let last = number(k["last"]) else { return nil }
            return K.Kitten(id: id, type: k["type"] as? String ?? "", session: k["session"] as? String, state: state, born: born, last: last, until: number(k["until"]))
        }
    }

    static func json(_ list: [K.Kitten]) -> [[String: Any]] {
        list.map { ["id": $0.id, "type": $0.type, "session": $0.session ?? NSNull(), "state": $0.state.rawValue, "born": $0.born, "last": $0.last, "until": $0.until ?? NSNull()] as [String: Any] }
    }

    /// The fixture's event, or nil when it is not an object, has no time that is a number, or is of a type the app does not have.
    static func event(_ raw: Any?) -> K.Event? {
        guard let e = raw as? [String: Any], let t = number(e["t"]) else { return nil }
        let kind = (e["type"] as? String).flatMap { K.Kind(rawValue: $0) } ?? .tick   // an unknown type only brings the time
        return K.Event(kind: kind, t: t, id: e["id"] as? String, agentType: e["agentType"] as? String, session: e["session"] as? String, tool: e["tool"] as? String)
    }

    @MainActor static func main() {
        let fx = CT.fixture("kitten-cases.json")

        CT.section("the frozen values: the limits, the four states and the places")
        let limits = fx["limits"] as! [String: Any]
        CT.check("at most 8 kittens per agent", K.max, limits["max"] as! Int)
        CT.checkNear("a farewell lasts 600 ms", K.leaveMs, number(limits["leaveMs"])!)
        CT.checkNear("a kitten whose stop never came goes with the sleep timer: ten minutes", CatRules.sleepAfterMs, number(limits["sleepAfterMs"])!)
        CT.check("the four states", K.State.allCases.map(\.rawValue), fx["states"] as! [String])
        var diffs: [String] = []
        for (name, want) in fx["places"] as! [String: [String: Any]] {
            guard let p = K.places[name] else { diffs.append("\(name): missing"); continue }
            var got: [String: Any] = ["unit": p.unit, "max": p.max]
            for (key, value) in [("d", p.d), ("x0", p.x0), ("y0", p.y0), ("step", p.step), ("moreSize", p.moreSize)] where want[key] != nil { got[key] = value }
            if want["align"] != nil { got["align"] = p.centred ? "center" : "start" }
            if want["moreAt"] != nil { got["moreAt"] = p.moreAt }
            if let l = p.label { got["label"] = ["x": l.x, "y": l.y, "size": l.size] }
            let d = CT.diffs(got, want)
            if !d.isEmpty { diffs.append("\(name): \(d.first!)") }
        }
        CT.check("the five places", Set(K.places.keys), Set((fx["places"] as! [String: Any]).keys))
        CT.checkRows("every place's numbers are the fixture's", diffs)

        CT.section("kittenStep: \(rows(fx["scripts"]).count) scripts, one event at a time, the whole list compared after each")
        diffs = []
        var steps = 0
        for script in rows(fx["scripts"]) {
            var list = kittens(script["from"])
            for (n, step) in rows(script["steps"]).enumerated() {
                list = event(step["ev"]).map { K.step(list, $0) } ?? K.clean(list)
                steps += 1
                let d = CT.diffs(json(list), step["list"]!)
                if !d.isEmpty { diffs.append("\(script["name"]!), step \(n + 1): \(d.first!)"); break }
            }
        }
        CT.checkRows("every step of all \(rows(fx["scripts"]).count) scripts (\(steps) events) leaves the list the fixture says", diffs)

        CT.section("kittenOrder, kittenView and cleanKittens")
        diffs = []
        for r in rows(fx["order"]) {
            let got = K.order(kittens(r["list"])).map(\.id), want = r["out"] as! [String]
            if got != want { diffs.append("\(r["name"]!): \(got)") }
        }
        CT.checkRows("order: an approval first, then the newest (\(rows(fx["order"]).count) rows)", diffs)
        diffs = []
        for r in rows(fx["views"]) {
            let got = K.view(kittens(r["list"]), now: number(r["now"]) ?? .nan).map(\.id), want = r["out"] as! [String]
            if got != want { diffs.append("\(r["name"]!): \(got)") }
        }
        CT.checkRows("view: a leaving kitten is hidden from its time, and a time that is not a number hides nothing (\(rows(fx["views"]).count) rows)", diffs)
        diffs = []
        for r in rows(fx["cleans"]) {
            let d = CT.diffs(json(K.clean(kittens(r["raw"]))), r["out"]!)
            if !d.isEmpty { diffs.append("\(r["name"]!): \(d.first!)") }
        }
        CT.checkRows("clean (\(rows(fx["cleans"]).count) rows)", diffs)

        CT.section("kittenPlaceOf and kittenSlots: \(rows(fx["placeOf"]).count) places of a mode, \(rows(fx["slots"]).count) slot rows")
        diffs = []
        for r in rows(fx["placeOf"]) {
            let got = K.placeOf(CatDisplaySettings.modeOf(r["mode"]), expanded: r["expanded"] as! Bool)
            if got != r["out"] as! String { diffs.append("\(r["mode"]!) \(r["expanded"]!): \(got)") }
        }
        CT.checkRows("the place for the big cat and cat 2, in every mode (an unknown mode is One cat)", diffs)
        diffs = []
        for r in rows(fx["slots"]) {
            // the loose kittens of the fixture: an entry that is not an object or has no text id is skipped, and a state that is not text is working
            let loose: [K.Kitten] = (r["kittens"] as? [Any] ?? []).compactMap { entry in
                guard let k = entry as? [String: Any], let id = k["id"] as? String else { return nil }
                return K.Kitten(id: id, state: (k["state"] as? String).flatMap { K.State(rawValue: $0) } ?? .working, born: 0, last: 0)
            }
            let place = r["place"].map { ($0 as? String) ?? "\($0)" } ?? "nil"
            let d = CT.diffs(K.slots(place, loose).json, r["out"]!)
            if !d.isEmpty { diffs.append("\(r["name"]!): \(d.first!)") }
        }
        CT.checkRows("every slot row comes out as the fixture says (the label of the pair, the overflow, an unknown place shows nothing)", diffs)

        CT.section("a time that is not finite (JSON cannot write it): the event changes nothing, not even the leaving kittens that are due")
        let list = [K.Kitten(id: "a", state: .working, born: 1, last: 1), K.Kitten(id: "b", state: .leaving, born: 2, last: 2, until: 5)]
        for bad in [Double.nan, .infinity, -.infinity] {
            CT.check("start, stop, end, sweep and tick at \(bad)", [K.step(list, .start(id: "c", t: bad)), K.step(list, .stop(id: "a", t: bad)), K.step(list, .end(t: bad)), K.step(list, .sweep(t: bad)), K.step(list, .tick(t: bad))], Array(repeating: list, count: 5))
        }
        CT.check("a due leaving kitten goes at the next event of any kind", K.step(list, .tick(t: 6)).map(\.id), ["a"])
        CT.check("and stays until its time", K.step(list, .tick(t: 4)).map(\.id), ["a", "b"])
        CT.check("the view hides a kitten from its time without any event", K.view(list, now: 5).map(\.id), ["a"])

        CT.section("what the app sends: a Claude Code that sends no agent_id, a stop twice, a start after the stop, two sessions in one pill")
        var l: [K.Kitten] = []
        l = K.step(l, .start(id: "s1", agentType: "Explore", session: "A", t: 1))
        l = K.step(l, .tool(id: nil, tool: "Grep", t: 2))
        CT.check("a tool event with no agent_id belongs to the parent: the kitten stays as it was", l.map { [$0.id, $0.state.rawValue] }, [["s1", "working"]])
        l = K.step(l, .tool(id: "s1", tool: "WebSearch", t: 3))
        CT.check("a search tool is searching, and the next tool of another kind is working", [l[0].state.rawValue, K.step(l, .tool(id: "s1", tool: "Edit", t: 4))[0].state.rawValue], ["searching", "working"])
        l = K.step(l, .permission(id: "s1", t: 5))
        CT.check("a permission request is an approval, and it is first in the order", [l[0].state.rawValue, K.order(K.step(l, .start(id: "s2", t: 6))).map(\.id).first ?? ""], ["approval", "s1"])
        l = K.step(l, .stop(id: "s1", t: 10))
        let stopped = K.step(l, .stop(id: "s1", t: 20))
        CT.check("a second stop for a kitten that is leaving changes nothing", stopped, l)
        CT.check("a start after the stop is a new kitten", K.step(l, .start(id: "s1", t: 11)).map { [$0.id, $0.state.rawValue, "\($0.born)"] }, [["s1", "working", "11.0"]])
        var two = K.step(K.step([], .start(id: "a1", session: "A", t: 1)), .start(id: "b1", session: "B", t: 2))
        two = K.step(two, .start(id: "n1", t: 3))
        CT.check("one session ending takes its kittens and those with no session, and leaves the other session's", K.step(two, .end(session: "A", t: 4)).map(\.id), ["b1"])

        CT.section("the list keeps its rules whatever arrives: at most 8, no repeats, a leaving kitten has a time, nothing the events did not start")
        var rng = CatRNG(seed: 21), bad: [String] = []
        let ids = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "", String(repeating: "x", count: 129)], sessions: [String?] = [nil, "A", "B", ""]
        var t = 0.0
        var fuzz: [K.Kitten] = []
        for n in 0..<4000 {
            t += rng.next() < 0.1 ? 700 : rng.next() * 40
            let id = ids[Int(rng.next() * Double(ids.count))], session = sessions[Int(rng.next() * Double(sessions.count))]
            let ev: K.Event
            switch Int(rng.next() * 9) {
            case 0: ev = .start(id: id, agentType: String(repeating: "t", count: Int(rng.next() * 100)), session: session, t: t)
            case 1: ev = .tool(id: id, tool: rng.next() < 0.5 ? "Grep" : "Edit", t: t)
            case 2: ev = .permission(id: id, t: t)
            case 3: ev = .resolved(id: id, t: t)
            case 4: ev = .stop(id: id, t: t)
            case 5: ev = .end(session: session, t: t)
            case 6: ev = .sweep(t: t + (rng.next() < 0.05 ? 700_000 : 0))
            case 7: ev = .tick(t: t)
            default: ev = .start(id: id, session: session, t: t)
            }
            fuzz = K.step(fuzz, ev)
            if fuzz.count > K.max { bad.append("event \(n): \(fuzz.count) kittens") }
            if Set(fuzz.map(\.id)).count != fuzz.count { bad.append("event \(n): an id twice") }
            if fuzz.contains(where: { $0.state == .leaving && $0.until == nil || $0.state != .leaving && $0.until != nil }) { bad.append("event \(n): a leaving kitten with no time, or a time without leaving") }
            if fuzz.contains(where: { !K.isKittenId($0.id) || !$0.born.isFinite || !$0.last.isFinite }) { bad.append("event \(n): a kitten that is not one") }
            if K.step(fuzz, .tick(t: t)) != fuzz.filter({ $0.state != .leaving || ($0.until ?? 0) > t }) { bad.append("event \(n): a tick changed more than the due kittens") }
            if bad.count > 5 { break }
        }
        CT.checkRows("4000 events from a seeded source", bad)

        CT.finish()
    }
}
```

Run: `chmod +x scripts/test-cat-kittens.sh`
Expected: no output.

Run: `bash scripts/test-cat-kittens.sh 2>&1 | tail -2`
Expected: FAIL: `error opening input file 'NotchBuddy/Sources/App/CatKittens.swift'`.

- [ ] **Step 2: Write the implementation**

The reducer is pure and nothing runs by itself: a leaving kitten is dropped by the next event of any kind, and `view` hides it from its `until` on, so a hidden island costs nothing and the view is right between events. At most 8 are kept (a ninth start drops the oldest by `born`). An event for an ID with no kitten, or for one that is already leaving, changes nothing, so a late tool event cannot bring a kitten back.

**Create `NotchBuddy/Sources/App/CatKittens.swift`**:

```swift
import Foundation

// Subagents shown as kittens beside their parent. Each agent pill keeps a list of kittens and `CatKittens.step` is the one reducer that changes it; the rest says what
// to draw (`view`, `order`) and where (`slots`, `placeOf`). Port of the "Kittens" section of design/prototype/cat-core.js (the tie-breaker);
// tests/fixtures/cat/kitten-cases.json pins it. It is pure: the time is in the event (ms on any one clock), nothing is read from a clock, nothing is changed in place, and
// nothing runs by itself: a leaving kitten is dropped by the next event and `view` hides it from its `until` on, so a hidden island costs nothing. Kittens are never stored.
// Foundation only.

enum CatKittens {
    /// At most this many kittens are tracked per agent; when a ninth starts, the oldest (by `born`) is dropped.
    static let max = 8
    /// A kitten that has stopped plays a happy blink for this long (ms), then goes.
    static let leaveMs = 600.0

    enum State: String, CaseIterable, Sendable { case working, searching, approval, leaving }

    /// One subagent: its `agent_id`, its `agent_type`, the session it belongs to (nil when the hook did not say), its state, the times of its start and its last event, and,
    /// once it is leaving, the time it is removed.
    struct Kitten: Equatable, Sendable {
        var id: String
        var type = ""
        var session: String?
        var state = State.working
        var born: Double
        var last: Double
        var until: Double?
    }

    /// The hook events that change a list. `start` is SubagentStart; `tool` a Pre or PostToolUse with an agent_id; `permission` a PermissionRequest from a subagent and
    /// `resolved` its answer; `stop` SubagentStop; `end` the parent's Stop or the session's end (every kitten, or one session's); `sweep` the cat's sleep timer firing;
    /// `tick` only the time.
    enum Kind: String, Sendable { case start, tool, permission, resolved, stop, end, sweep, tick }

    struct Event: Sendable {
        var kind: Kind
        /// ms, on the one clock every event uses. An event whose time is not finite changes nothing.
        var t: Double
        var id: String?
        var agentType: String?
        var session: String?
        var tool: String?

        static func start(id: String?, agentType: String? = nil, session: String? = nil, t: Double) -> Event { Event(kind: .start, t: t, id: id, agentType: agentType, session: session) }
        static func tool(id: String?, tool: String?, t: Double) -> Event { Event(kind: .tool, t: t, id: id, tool: tool) }
        static func permission(id: String?, t: Double) -> Event { Event(kind: .permission, t: t, id: id) }
        static func resolved(id: String?, t: Double) -> Event { Event(kind: .resolved, t: t, id: id) }
        static func stop(id: String?, t: Double) -> Event { Event(kind: .stop, t: t, id: id) }
        static func end(session: String? = nil, t: Double) -> Event { Event(kind: .end, t: t, session: session) }
        static func sweep(t: Double) -> Event { Event(kind: .sweep, t: t) }
        static func tick(t: Double) -> Event { Event(kind: .tick, t: t) }
    }

    // MARK: Cleaning

    /// An agent_id (or a session ID) is text, not empty and at most 128 characters.
    static func isKittenId(_ v: String?) -> Bool { v.map { !$0.isEmpty && $0.count <= 128 } ?? false }
    private static func typeOfAgent(_ v: String?) -> String { v.map { String($0.prefix(64)) } ?? "" }
    private static func sessionOf(_ v: String?) -> String? { isKittenId(v) ? v : nil }

    /// A kitten list as an app may hold it, made safe: entries that repeat an id (the first wins), have no valid id or a time that is not finite are dropped, a type is
    /// cut at 64 characters, a session that is not an ID is none, and only a leaving kitten has a time to go (`until`).
    static func clean(_ list: [Kitten]) -> [Kitten] {
        var out: [Kitten] = [], seen = Set<String>()
        for k in list where isKittenId(k.id) && !seen.contains(k.id) && k.born.isFinite && k.last.isFinite {
            seen.insert(k.id)
            out.append(Kitten(id: k.id, type: typeOfAgent(k.type), session: sessionOf(k.session), state: k.state, born: k.born, last: k.last, until: k.state == .leaving && (k.until?.isFinite ?? false) ? k.until : nil))
        }
        return out
    }

    private static func cap(_ list: inout [Kitten]) {
        while list.count > max {
            var oldest = 0
            for i in 1..<list.count where list[i].born < list[oldest].born { oldest = i }
            list.remove(at: oldest)
        }
    }

    // MARK: The reducer

    /// The reducer. `list` is one pill's kittens, the result a new list. Every event first drops the leaving kittens whose time is up. An event for an id with no kitten, or
    /// for a kitten that is already leaving, changes nothing: a late tool event must not bring back a kitten that has gone, and without a SubagentStart there is nothing to
    /// show. An event with a time that is not finite returns the list as it is (cleaned). A repeated `start` for an id that is there only refreshes it. `end` with a
    /// session takes only that session's kittens and the ones with no session (two sessions of one agent share a pill); without one it takes every kitten. `sweep` takes a
    /// kitten whose last event is ten minutes or more old (its stop never came). Never throws.
    static func step(_ list: [Kitten], _ ev: Event) -> [Kitten] {
        var l = clean(list)
        guard ev.t.isFinite else { return l }
        let t = ev.t
        func active(_ id: String?) -> Int? { id.flatMap { id in l.firstIndex { $0.id == id && $0.state != .leaving } } }
        l = l.filter { $0.state != .leaving || ($0.until ?? 0) > t }
        switch ev.kind {
        case .start:
            guard isKittenId(ev.id), let id = ev.id else { break }
            if let i = l.firstIndex(where: { $0.id == id }) {
                if l[i].state != .leaving {
                    l[i].last = t
                    let type = typeOfAgent(ev.agentType)
                    if !type.isEmpty { l[i].type = type }
                    if let s = sessionOf(ev.session) { l[i].session = s }
                    break
                }
                l.remove(at: i)
            }
            l.append(Kitten(id: id, type: typeOfAgent(ev.agentType), session: sessionOf(ev.session), state: .working, born: t, last: t, until: nil))
            cap(&l)
        case .tool:
            if let i = active(ev.id) { l[i].state = CatRules.toolState(ev.tool) == .searching ? .searching : .working; l[i].last = t }
        case .permission:
            if let i = active(ev.id) { l[i].state = .approval; l[i].last = t }
        case .resolved:
            if let i = active(ev.id) { if l[i].state == .approval { l[i].state = .working }; l[i].last = t }
        case .stop:
            if let i = active(ev.id) { l[i].state = .leaving; l[i].last = t; l[i].until = t + leaveMs }
        case .end:
            if let q = sessionOf(ev.session) { l = l.filter { $0.session != nil && $0.session != q } } else { l = [] }
        case .sweep:
            l = l.filter { t - $0.last < CatRules.sleepAfterMs }
        case .tick: break
        }
        return l
    }

    // MARK: What to draw

    /// The order kittens are shown in: a kitten waiting on an approval first, then the newest (by `born`; a later place in the list first when they tie).
    static func order(_ list: [Kitten]) -> [Kitten] {
        clean(list).enumerated().sorted { a, b in
            if (a.element.state == .approval) != (b.element.state == .approval) { return a.element.state == .approval }
            if a.element.born != b.element.born { return a.element.born > b.element.born }
            return a.offset > b.offset
        }.map(\.element)
    }

    /// What is drawn at `now` (ms): the kittens in `order`, without a leaving kitten whose time is up. A `now` that is not finite hides nothing.
    static func view(_ list: [Kitten], now: Double) -> [Kitten] {
        order(clean(list).filter { $0.state != .leaving || !now.isFinite || ($0.until ?? 0) > now })
    }

    // MARK: Where they sit

    /// The places kittens go, and the numbers: every number is a multiple of a unit, `D` (the parent's head width, from its head centre, x right and y down) or `H` (the pill's
    /// height, from the pill's trailing edge, so x is negative inside it, and the middle of its height). The numbers are the brainstorm mockup's, divided by its parent's size.
    struct PlaceSpec: Equatable, Sendable {
        var unit: String
        var max: Int
        var d = 0.0, x0 = 0.0, y0 = 0.0, step = 0.0
        var centred = false
        /// Where the "+N" label is centred (default: the next slot after the last one drawn) and its text height.
        var moreAt: [Double]?
        var moreSize = 0.0
        /// The pair in the compact island has no room beside it: only a count "×N", drawn by cat 2 of the pair, at this spot.
        var label: (x: Double, y: Double, size: Double)?
        static func == (a: PlaceSpec, b: PlaceSpec) -> Bool {
            a.unit == b.unit && a.max == b.max && a.d == b.d && a.x0 == b.x0 && a.y0 == b.y0 && a.step == b.step && a.centred == b.centred && a.moreAt == b.moreAt && a.moreSize == b.moreSize
                && a.label?.x == b.label?.x && a.label?.y == b.label?.y && a.label?.size == b.label?.size
        }
    }
    static let places: [String: PlaceSpec] = [
        "bigExpanded": PlaceSpec(unit: "D", max: 3, d: 15.0 / 58, x0: 24.0 / 58, y0: 34.0 / 58, step: 18.0 / 58, moreSize: 0.2),
        "bigCompact": PlaceSpec(unit: "D", max: 2, d: 12.0 / 20, x0: 22.0 / 20, y0: 5.0 / 20, step: 13.0 / 20, moreAt: [42.0 / 20, -10.0 / 20], moreSize: 0.25),
        "pairCompact": PlaceSpec(unit: "D", max: 0, label: (1.1, 0.3, 0.5)),
        "pairExpanded": PlaceSpec(unit: "D", max: 3, d: 15.0 / 58, x0: 0, y0: 34.0 / 58, step: 18.0 / 58, centred: true, moreAt: [0, 50.0 / 58], moreSize: 0.2),
        "pill": PlaceSpec(unit: "H", max: 3, d: 15.0 / 28, x0: -17.5 / 28, y0: 0, step: -16.0 / 28, moreSize: 0.36),
    ]

    /// The place kittens go for the big cat (and, in Two cats mode, for cat 2): `bigExpanded` or `bigCompact`; in Two cats mode `pairExpanded` or `pairCompact`. An agent pill
    /// uses `pill`.
    static func placeOf(_ mode: CatDisplayMode, expanded: Bool) -> String { mode == .two ? (expanded ? "pairExpanded" : "pairCompact") : (expanded ? "bigExpanded" : "bigCompact") }

    struct Slot: Equatable, Sendable { var id: String; var state: String; var x: Double; var y: Double; var d: Double }
    struct More: Equatable, Sendable { var x: Double; var y: Double; var size: Double }
    struct Label: Equatable, Sendable { var text: String; var x: Double; var y: Double; var size: Double }
    /// `shown` the first `max` kittens, `more` how many are left over (the "+N"), `moreAt` where that label goes (nil when none is left over), `label` the pair's "×N" (nil
    /// unless the place has one and there is a kitten). An unknown place shows nothing.
    struct Slots: Equatable, Sendable {
        var place: String
        var unit: String?
        var count: Int
        var shown: [Slot]
        var more: Int
        var moreAt: More?
        var label: Label?

        /// As the fixtures hold it, a JSON-shaped dictionary.
        var json: [String: Any] {
            ["place": place, "unit": unit ?? NSNull(), "count": count, "shown": shown.map { ["id": $0.id, "state": $0.state, "x": $0.x, "y": $0.y, "d": $0.d] as [String: Any] }, "more": more,
             "moreAt": moreAt.map { ["x": $0.x, "y": $0.y, "size": $0.size] as [String: Any] } ?? NSNull(),
             "label": label.map { ["text": $0.text, "x": $0.x, "y": $0.y, "size": $0.size] as [String: Any] } ?? NSNull()]
        }
    }

    /// The slots for one parent's kittens in one place. `kittens` is what `view` returned (already in order).
    static func slots(_ place: String, _ kittens: [Kitten]) -> Slots {
        let list = kittens.filter { isKittenId($0.id) }, count = list.count
        guard let p = places[place] else { return Slots(place: place, unit: nil, count: count, shown: [], more: 0, moreAt: nil, label: nil) }
        let n = Swift.min(count, p.max), more = p.label != nil ? 0 : count - n
        func x(_ i: Int) -> Double { p.centred ? p.x0 + (Double(i) - Double(n - 1) / 2) * p.step : p.x0 + Double(i) * p.step }
        return Slots(place: place, unit: p.unit, count: count,
                     shown: list.prefix(n).enumerated().map { Slot(id: $1.id, state: $1.state.rawValue, x: x($0), y: p.y0, d: p.d) }, more: more,
                     moreAt: more > 0 ? More(x: p.moreAt?[0] ?? p.x0 + Double(p.max) * p.step, y: p.moreAt?[1] ?? p.y0, size: p.moreSize) : nil,
                     label: p.label.flatMap { count > 0 ? Label(text: "×\(count)", x: $0.x, y: $0.y, size: $0.size) : nil })
    }
}
```

- [ ] **Step 3: Run it to see it pass**

Run: `bash scripts/test-cat-kittens.sh 2>&1 | grep -c "✓"; bash scripts/test-cat-kittens.sh 2>&1 | tail -1`
Expected: `25`, then `All tests passed.`

- [ ] **Step 4: Prove the test bites (one-off, never committed)**

Run: `sed -i '' 's/static let max = 8/static let max = 9/' NotchBuddy/Sources/App/CatKittens.swift && bash scripts/test-cat-kittens.sh 2>&1 | grep -c "✗"`
Expected: `2` (the two failing checks are "at most 8 kittens per agent" and "every step of all 21 scripts … leaves the list the fixture says").

Run: `sed -i '' 's/static let max = 9/static let max = 8/' NotchBuddy/Sources/App/CatKittens.swift && bash scripts/test-cat-kittens.sh 2>&1 | tail -1`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/App/CatKittens.swift tests/CatKittensTests.swift scripts/test-cat-kittens.sh
git commit -m "feat(cat): the kittens' rules

CatKittens is the Swift port of kittenStep, kittenOrder, kittenView, kittenSlots, kittenPlaceOf and cleanKittens: one pure reducer over a pill's kitten list (start,
tool, permission, resolved, stop, end, sweep, tick), at most 8, a farewell of 600 ms that needs no timer, and the places and slots of every drawing. Replays
kitten-cases.json event by event, and adds a time that is not finite and a 4000-event fuzz.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 13: Kittens in the app: the hook events, the lists and the sleep timer's sweep (stage 5)

**Agent:** `nm-implementer-deep`. The hook server's approval paths (answered, dismissed, displaced) and the App Store split are where a mistake hides; the scripted events go to a socket of the test's own.

**Files:**
- Create: `NotchBuddy/Sources/App/CatKittenHooks.swift`, `NotchBuddy/Sources/App/CatKittens+App.swift`, `tests/CatKittenHooksTests.swift`, `scripts/test-cat-kitten-hooks.sh`, `scripts/fake-subagent-events.py`, `tests/kitten_socket_server.py`, `tests/fixtures/mac/subagent-scenarios.json`
- Modify: `NotchBuddy/Sources/App/AppState.swift`, `HookServer.swift`, `CatSleep+App.swift`, `IslandTypes.swift`, `tests/CatWiringTests.swift`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (by `xcodegen`)

**Interfaces:**
- Consumes: Task 12's `CatKittens`, Task 6's `AppState.touchPill`, the hook server's own pill routing (`agentId`, `pillId`).
- Produces: `CatKittenHooks.event(name:payload:now:)` (`SubagentStart` adds a kitten; `PreToolUse` and `PostToolUse` that carry an `agent_id` set its state; `SubagentStop` makes it leave; the parent's `Stop`, `StopFailure`, `SessionEnd` and `Interrupt` take its session's kittens; anything else is nil), `permission(payload:now:)`, `resolved(subagentId:now:)`, `subagentId(_:)`, `sessionId(_:)`; `AppState.kittens: [String: [CatKittens.Kitten]]` (published, never stored, one list for each pill), `kittenEvent(_:_:)`, `sweepKittens(at:)`, `kittenView(_:at:)`; `ApprovalInfo.subagentId`; `scripts/fake-subagent-events.py` (five scripted scenarios: `life`, `fallback`, `lost-stop`, `crowd`, `two-sessions`, in `tests/fixtures/mac/subagent-scenarios.json`).

- [ ] **Step 1: The scripted scenarios, the sender and the test's socket**

One file holds the scenarios in the hooks' own words, and three programs read it: the sender (for the owner's check on a real build, which sends each step's `event` through the app's socket as the `nm-hook` relay does), the tests (which send it to a socket of their own and replay what arrived), and the contact sheets. Each step says what to say, when it happens on the app's clock (`at`), how long the sender waits, the list of kittens after it (`kittens`, in list order) and, after a farewell, what is drawn a moment later (`view`). The test's socket records every line it is sent and answers like the app (`{"ok":true}`, and an allow for a permission request).

**Create `tests/fixtures/mac/subagent-scenarios.json`**:

```json
{
 "version": 1,
 "note": "Scripted subagent events for the kittens, in the hooks' own words. scripts/fake-subagent-events.py sends the `event` of each step through the NotchMeow socket (a real app, for the owner's check); tests/CatKittenHooksTests.swift replays what a local socket received through CatKittenHooks and CatKittens and checks `kittens` (the list after the step, in list order) and, where there is a `view`, what is drawn `viewAt` ms later; scripts/render-cats.sh --island --kittens draws the island after each step. `at` is the step's time in ms on the app's clock; `wait_ms` is how long the sender waits after it; `internal` is what the app does by itself (an approval answered, the sleep timer's sweep).",
 "common": {
  "term_program": "vscode",
  "cwd": "/tmp/notchmeow-demo",
  "session_id": "S1"
 },
 "scenarios": {
  "life": {
   "about": "A subagent's whole life: two start, one searches, one waits on an approval, the answer, a farewell, a late event that must not bring it back, and the parent's stop with a stop that never came.",
   "steps": [
    {
     "say": "the Claude Code pill appears",
     "at": 0,
     "wait_ms": 800,
     "event": {
      "hook_event_name": "SessionStart"
     },
     "kittens": []
    },
    {
     "say": "an Explore subagent starts: a kitten, working",
     "at": 1000,
     "wait_ms": 900,
     "event": {
      "hook_event_name": "SubagentStart",
      "agent_id": "a1",
      "agent_type": "Explore"
     },
     "kittens": [
      "a1:working"
     ]
    },
    {
     "say": "a second subagent starts",
     "at": 2000,
     "wait_ms": 900,
     "event": {
      "hook_event_name": "SubagentStart",
      "agent_id": "a2",
      "agent_type": "general-purpose"
     },
     "kittens": [
      "a1:working",
      "a2:working"
     ]
    },
    {
     "say": "the first one searches (Grep, with its agent_id)",
     "at": 3000,
     "wait_ms": 1200,
     "event": {
      "hook_event_name": "PreToolUse",
      "agent_id": "a1",
      "agent_type": "Explore",
      "tool_name": "Grep",
      "tool_input": {
       "pattern": "kitten"
      }
     },
     "kittens": [
      "a1:searching",
      "a2:working"
     ]
    },
    {
     "say": "a tool event without an agent_id is the parent's: no kitten changes",
     "at": 4000,
     "wait_ms": 900,
     "event": {
      "hook_event_name": "PreToolUse",
      "tool_name": "Edit",
      "tool_input": {
       "file_path": "/tmp/notchmeow-demo/a.swift"
      }
     },
     "kittens": [
      "a1:searching",
      "a2:working"
     ]
    },
    {
     "say": "the first one reads (Read): back to working",
     "at": 5000,
     "wait_ms": 900,
     "event": {
      "hook_event_name": "PreToolUse",
      "agent_id": "a1",
      "tool_name": "Read",
      "tool_input": {
       "file_path": "/tmp/notchmeow-demo/a.swift"
      }
     },
     "kittens": [
      "a1:working",
      "a2:working"
     ]
    },
    {
     "say": "the second one asks to run a command: its kitten waits on the approval (answer the card in the island)",
     "at": 6000,
     "wait_ms": 1500,
     "event": {
      "hook_event_name": "PermissionRequest",
      "agent_id": "a2",
      "tool_name": "Bash",
      "tool_input": {
       "command": "echo kittens"
      }
     },
     "kittens": [
      "a1:working",
      "a2:approval"
     ]
    },
    {
     "say": "the approval is answered: the kitten is back to work",
     "at": 9000,
     "wait_ms": 900,
     "internal": {
      "type": "resolved",
      "id": "a2"
     },
     "kittens": [
      "a1:working",
      "a2:working"
     ]
    },
    {
     "say": "the first one stops: a happy blink, then it leaves",
     "at": 10000,
     "wait_ms": 1000,
     "event": {
      "hook_event_name": "SubagentStop",
      "agent_id": "a1",
      "agent_type": "Explore"
     },
     "kittens": [
      "a1:leaving",
      "a2:working"
     ],
     "viewAt": 700,
     "view": [
      "a2:working"
     ]
    },
    {
     "say": "a late tool event from the first one brings nothing back",
     "at": 11000,
     "wait_ms": 900,
     "event": {
      "hook_event_name": "PostToolUse",
      "agent_id": "a1",
      "tool_name": "Read",
      "tool_input": {
       "file_path": "/tmp/notchmeow-demo/a.swift"
      }
     },
     "kittens": [
      "a2:working"
     ]
    },
    {
     "say": "the parent stops: the second one's stop never came, and it goes too",
     "at": 12000,
     "wait_ms": 1200,
     "event": {
      "hook_event_name": "Stop",
      "last_assistant_message": "Done."
     },
     "kittens": []
    }
   ]
  },
  "fallback": {
   "about": "A Claude Code that sends no agent_id on tool events: the kitten still appears at the start and leaves at the stop, in the working pose.",
   "steps": [
    {
     "say": "the pill appears",
     "at": 0,
     "wait_ms": 800,
     "event": {
      "hook_event_name": "SessionStart"
     },
     "kittens": []
    },
    {
     "say": "a subagent starts",
     "at": 1000,
     "wait_ms": 900,
     "event": {
      "hook_event_name": "SubagentStart",
      "agent_id": "a1",
      "agent_type": "Explore"
     },
     "kittens": [
      "a1:working"
     ]
    },
    {
     "say": "its searches arrive without an agent_id: the kitten stays working",
     "at": 2000,
     "wait_ms": 900,
     "event": {
      "hook_event_name": "PreToolUse",
      "tool_name": "Grep",
      "tool_input": {
       "pattern": "x"
      }
     },
     "kittens": [
      "a1:working"
     ]
    },
    {
     "say": "and so do its edits",
     "at": 3000,
     "wait_ms": 900,
     "event": {
      "hook_event_name": "PreToolUse",
      "tool_name": "Edit",
      "tool_input": {
       "file_path": "/tmp/notchmeow-demo/a.swift"
      }
     },
     "kittens": [
      "a1:working"
     ]
    },
    {
     "say": "it stops and leaves",
     "at": 4000,
     "wait_ms": 1000,
     "event": {
      "hook_event_name": "SubagentStop",
      "agent_id": "a1",
      "agent_type": "Explore"
     },
     "kittens": [
      "a1:leaving"
     ],
     "viewAt": 700,
     "view": []
    },
    {
     "say": "the parent stops",
     "at": 5000,
     "wait_ms": 800,
     "event": {
      "hook_event_name": "Stop"
     },
     "kittens": []
    }
   ]
  },
  "lost-stop": {
   "about": "A stop that never comes: the kitten stays until the cat's ten-minute sleep timer sweeps it (nothing runs by itself).",
   "steps": [
    {
     "say": "the pill appears",
     "at": 0,
     "wait_ms": 800,
     "event": {
      "hook_event_name": "SessionStart"
     },
     "kittens": []
    },
    {
     "say": "two subagents start",
     "at": 1000,
     "wait_ms": 600,
     "event": {
      "hook_event_name": "SubagentStart",
      "agent_id": "a1",
      "agent_type": "Explore"
     },
     "kittens": [
      "a1:working"
     ]
    },
    {
     "say": "the second",
     "at": 2000,
     "wait_ms": 600,
     "event": {
      "hook_event_name": "SubagentStart",
      "agent_id": "a2",
      "agent_type": "Plan"
     },
     "kittens": [
      "a1:working",
      "a2:working"
     ]
    },
    {
     "say": "the first stops; the second's stop is lost",
     "at": 3000,
     "wait_ms": 900,
     "event": {
      "hook_event_name": "SubagentStop",
      "agent_id": "a1",
      "agent_type": "Explore"
     },
     "kittens": [
      "a1:leaving",
      "a2:working"
     ],
     "viewAt": 700,
     "view": [
      "a2:working"
     ]
    },
    {
     "say": "nothing happens for 5 minutes: the kitten is still there",
     "at": 303000,
     "wait_ms": 600,
     "internal": {
      "type": "tick"
     },
     "kittens": [
      "a2:working"
     ]
    },
    {
     "say": "the cat falls asleep, ten minutes after the last event: the sweep takes the kitten",
     "at": 700000,
     "wait_ms": 600,
     "internal": {
      "type": "sweep"
     },
     "kittens": []
    }
   ]
  },
  "crowd": {
   "about": "Nine subagents start: at most eight are kept, and the oldest is dropped first.",
   "steps": [
    {
     "say": "the pill appears",
     "at": 0,
     "wait_ms": 600,
     "event": {
      "hook_event_name": "SessionStart"
     },
     "kittens": []
    },
    {
     "say": "subagent 1 starts",
     "at": 1000,
     "wait_ms": 500,
     "event": {
      "hook_event_name": "SubagentStart",
      "agent_id": "a1",
      "agent_type": "Explore"
     },
     "kittens": [
      "a1:working"
     ]
    },
    {
     "say": "subagent 2 starts",
     "at": 2000,
     "wait_ms": 500,
     "event": {
      "hook_event_name": "SubagentStart",
      "agent_id": "a2",
      "agent_type": "Explore"
     },
     "kittens": [
      "a1:working",
      "a2:working"
     ]
    },
    {
     "say": "subagent 3 starts",
     "at": 3000,
     "wait_ms": 500,
     "event": {
      "hook_event_name": "SubagentStart",
      "agent_id": "a3",
      "agent_type": "Explore"
     },
     "kittens": [
      "a1:working",
      "a2:working",
      "a3:working"
     ]
    },
    {
     "say": "subagent 4 starts",
     "at": 4000,
     "wait_ms": 500,
     "event": {
      "hook_event_name": "SubagentStart",
      "agent_id": "a4",
      "agent_type": "Explore"
     },
     "kittens": [
      "a1:working",
      "a2:working",
      "a3:working",
      "a4:working"
     ]
    },
    {
     "say": "subagent 5 starts",
     "at": 5000,
     "wait_ms": 500,
     "event": {
      "hook_event_name": "SubagentStart",
      "agent_id": "a5",
      "agent_type": "Explore"
     },
     "kittens": [
      "a1:working",
      "a2:working",
      "a3:working",
      "a4:working",
      "a5:working"
     ]
    },
    {
     "say": "subagent 6 starts",
     "at": 6000,
     "wait_ms": 500,
     "event": {
      "hook_event_name": "SubagentStart",
      "agent_id": "a6",
      "agent_type": "Explore"
     },
     "kittens": [
      "a1:working",
      "a2:working",
      "a3:working",
      "a4:working",
      "a5:working",
      "a6:working"
     ]
    },
    {
     "say": "subagent 7 starts",
     "at": 7000,
     "wait_ms": 500,
     "event": {
      "hook_event_name": "SubagentStart",
      "agent_id": "a7",
      "agent_type": "Explore"
     },
     "kittens": [
      "a1:working",
      "a2:working",
      "a3:working",
      "a4:working",
      "a5:working",
      "a6:working",
      "a7:working"
     ]
    },
    {
     "say": "subagent 8 starts",
     "at": 8000,
     "wait_ms": 500,
     "event": {
      "hook_event_name": "SubagentStart",
      "agent_id": "a8",
      "agent_type": "Explore"
     },
     "kittens": [
      "a1:working",
      "a2:working",
      "a3:working",
      "a4:working",
      "a5:working",
      "a6:working",
      "a7:working",
      "a8:working"
     ]
    },
    {
     "say": "subagent 9 starts",
     "at": 9000,
     "wait_ms": 500,
     "event": {
      "hook_event_name": "SubagentStart",
      "agent_id": "a9",
      "agent_type": "Explore"
     },
     "kittens": [
      "a2:working",
      "a3:working",
      "a4:working",
      "a5:working",
      "a6:working",
      "a7:working",
      "a8:working",
      "a9:working"
     ]
    }
   ]
  },
  "two-sessions": {
   "about": "Two sessions of one agent share a pill: one session's Stop takes its own kittens and leaves the other's.",
   "steps": [
    {
     "say": "the pill appears",
     "at": 0,
     "wait_ms": 600,
     "event": {
      "hook_event_name": "SessionStart",
      "session_id": "A"
     },
     "kittens": []
    },
    {
     "say": "a subagent of session A",
     "at": 1000,
     "wait_ms": 600,
     "event": {
      "hook_event_name": "SubagentStart",
      "agent_id": "a1",
      "agent_type": "Explore",
      "session_id": "A"
     },
     "kittens": [
      "a1:working"
     ]
    },
    {
     "say": "a subagent of session B",
     "at": 2000,
     "wait_ms": 600,
     "event": {
      "hook_event_name": "SubagentStart",
      "agent_id": "b1",
      "agent_type": "Explore",
      "session_id": "B"
     },
     "kittens": [
      "a1:working",
      "b1:working"
     ]
    },
    {
     "say": "session B stops",
     "at": 3000,
     "wait_ms": 800,
     "event": {
      "hook_event_name": "Stop",
      "session_id": "B"
     },
     "kittens": [
      "a1:working"
     ]
    },
    {
     "say": "session A stops",
     "at": 4000,
     "wait_ms": 800,
     "event": {
      "hook_event_name": "Stop",
      "session_id": "A"
     },
     "kittens": []
    }
   ]
  }
 }
}
```

**Create `scripts/fake-subagent-events.py`**:

```python
#!/usr/bin/env python3
"""Sends scripted subagent hook events through NotchMeow's socket, the way the nm-hook relay does, so a running Debug build shows its kittens.

  python3 scripts/fake-subagent-events.py --list                      the scenarios
  python3 scripts/fake-subagent-events.py --scenario life             send one (default: life) to the app's socket
  python3 scripts/fake-subagent-events.py --scenario life --print     print the payloads instead of sending them
  python3 scripts/fake-subagent-events.py --sock /path/nm.sock        another socket (the App Store build's is ~/Library/Containers/<id>/Data/nm.sock)

The scenarios are tests/fixtures/mac/subagent-scenarios.json (the same file the tests and the contact sheets use). This is for the owner's check on a real build: the
tests send it to a socket of their own and never to the app. Each event is one connection, newline-delimited JSON, as the relay sends it; a PermissionRequest is held
open by the app until the card is answered (or --permission-timeout runs out), like Claude Code's own.
"""
import argparse, json, os, socket, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
SCENARIOS = os.path.join(HERE, "..", "tests", "fixtures", "mac", "subagent-scenarios.json")
DEFAULT_SOCK = os.path.expanduser("~/Library/Application Support/NotchMeow/nm.sock")


def payloads(data, name):
    """The payloads of one scenario in order: the common fields, then the step's event, with what to say and how long to wait."""
    out = []
    for step in data["scenarios"][name]["steps"]:
        if "event" in step:
            out.append((step["say"], {**data["common"], **step["event"]}, step.get("wait_ms", 600)))
        else:
            out.append((step["say"] + "  [the app does this by itself: " + json.dumps(step.get("internal")) + "]", None, step.get("wait_ms", 600)))
    return out


def send(sock_path, payload, permission_timeout):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(permission_timeout if payload.get("hook_event_name") == "PermissionRequest" else 5)
    try:
        s.connect(sock_path)
        s.sendall((json.dumps(payload) + "\n").encode())
        reply = b""
        while not reply.endswith(b"\n"):
            chunk = s.recv(4096)
            if not chunk:
                break
            reply += chunk
        return reply.decode().strip()
    finally:
        s.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--scenario", default="life")
    ap.add_argument("--sock", default=DEFAULT_SOCK)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--print", dest="dry", action="store_true", help="print the payloads, send nothing")
    ap.add_argument("--speed", type=float, default=1.0, help="2 waits half as long between events")
    ap.add_argument("--permission-timeout", type=float, default=120.0)
    a = ap.parse_args()
    data = json.load(open(SCENARIOS))
    if a.list:
        for name, sc in data["scenarios"].items():
            print(f"{name:14s} {len(sc['steps']):2d} steps  {sc['about']}")
        return 0
    if a.scenario not in data["scenarios"]:
        print(f"no scenario {a.scenario!r}: try --list", file=sys.stderr)
        return 2
    for say, payload, wait in payloads(data, a.scenario):
        print("-", say, flush=True)
        if payload is not None:
            if a.dry:
                print("  " + json.dumps(payload, sort_keys=True))
            else:
                try:
                    reply = send(a.sock, payload, a.permission_timeout)
                except OSError as e:
                    print(f"  could not reach {a.sock}: {e}", file=sys.stderr)
                    return 1
                print("  ->", reply or "(closed)", flush=True)
        if not a.dry:
            time.sleep(wait / 1000 / a.speed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

**Create `tests/kitten_socket_server.py`**:

```python
#!/usr/bin/env python3
"""A stand-in for NotchMeow's socket, for the kitten tests: records every JSON line it is sent, in order, one per connection, and answers like the app does
(`{"ok":true}`, and for a PermissionRequest an immediate allow, as if the card had been answered). Usage: kitten_socket_server.py SOCKET RECEIVED.jsonl"""
import json, os, socket, sys

path, out = sys.argv[1], sys.argv[2]
if os.path.exists(path):
    os.unlink(path)
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(path)
srv.listen(8)
open(out, "w").close()
while True:
    conn, _ = srv.accept()
    with conn:
        raw = b""
        while not raw.endswith(b"\n"):
            chunk = conn.recv(4096)
            if not chunk:
                break
            raw += chunk
        try:
            payload = json.loads(raw)
        except ValueError:
            payload = {}
        with open(out, "a") as f:
            f.write(json.dumps(payload, sort_keys=True) + "\n")
        reply = '{"permissionDecision":"allow"}' if payload.get("hook_event_name") == "PermissionRequest" else '{"ok":true}'
        conn.sendall((reply + "\n").encode())
```

Run: `chmod +x scripts/fake-subagent-events.py`
Expected: no output.

Run: `python3 scripts/fake-subagent-events.py --list | cut -c1-30`
Expected: five lines, `life           11 steps  A sub…`, `fallback        6 steps  A Cla…`, `lost-stop       6 steps  A sto…`, `crowd          10 steps  Nine…` and `two-sessions    5 steps  Two…`.

Run: `python3 scripts/fake-subagent-events.py --scenario fallback --print | sed -n 3,4p`
Expected: the second step's words and its payload: `- a subagent starts` and `  {"agent_id": "a1", "agent_type": "Explore", "cwd": "/tmp/notchmeow-demo", "hook_event_name": "SubagentStart", "session_id": "S1", "term_program": "vscode"}`.

- [ ] **Step 2: Write the failing tests**

The test script starts the stand-in socket, sends every scenario to it with `fake-subagent-events.py`, and then builds the Swift program, which replays what the socket received through `CatKittenHooks` and `CatKittens` and checks, after each step, the list the scenario says (and, after a farewell, what is drawn 700 ms later). It also checks the hooks' words one by one: which events carry a kitten event and which are the parent's own, an `agent_id` that is not text, empty or 129 characters, a `Stop` that names a subagent. The wiring pins: the hook server turns the events into kitten events once (after the pill's last event, before a pending approval can end the handling), the pill an event belongs to gets them, a request from a subagent is remembered and its kitten is resolved when the card is answered, dismissed or displaced, no kitten call sits inside an `#if` block (the App Store build installs `SubagentStart` and `SubagentStop` too), the sleep timer sweeps, both relays (`nm-hook.py` of the GitHub build and of the App Store build) forward the hook's payload whole, so a subagent's `agent_id` and `agent_type` reach the island, and there is no timer and no polling.

**Create `scripts/test-cat-kitten-hooks.sh`**:

```bash
#!/usr/bin/env bash
# Cat kitten hooks: the scripted subagent events (tests/fixtures/mac/subagent-scenarios.json) are sent by scripts/fake-subagent-events.py to a socket of the test's own
# (never the app's), and what that socket received is replayed through CatKittenHooks and CatKittens: the start, the tool events with and without an agent_id, a
# permission request, the stop, a stop that never comes and the parent's stop. Nothing here launches or touches NotchMeow.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-kitten-hooks.XXXXXX")"
SOCK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nmk.XXXXXX")"
[ "${#SOCK_DIR}" -le 80 ] || { rm -rf "$SOCK_DIR"; SOCK_DIR="$(mktemp -d /tmp/nmk.XXXXXX)"; }   # a socket path holds 103 bytes
SERVER=""
trap '[ -z "$SERVER" ] || { kill "$SERVER" 2>/dev/null; wait "$SERVER" 2>/dev/null; } || true; rm -rf "$TEST_DIR" "$SOCK_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

python3 tests/kitten_socket_server.py "$SOCK_DIR/s" "$SOCK_DIR/received.jsonl" &
SERVER=$!
for _ in $(seq 1 50); do [ -S "$SOCK_DIR/s" ] && break; sleep 0.1; done
[ -S "$SOCK_DIR/s" ] || { echo "the test socket did not come up"; exit 1; }
mkdir -p "$TEST_DIR/received"
for name in $(python3 scripts/fake-subagent-events.py --list | awk '{print $1}'); do
    : > "$SOCK_DIR/received.jsonl"
    python3 scripts/fake-subagent-events.py --scenario "$name" --sock "$SOCK_DIR/s" --speed 100000 > /dev/null
    cp "$SOCK_DIR/received.jsonl" "$TEST_DIR/received/$name.jsonl"
done
export NM_KITTEN_RECEIVED="$TEST_DIR/received"

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift \
    $APP/CatKittens.swift $APP/CatKittenHooks.swift \
    tests/CatTestSupport.swift tests/CatKittenHooksTests.swift \
    -o "$TEST_DIR/cat-kitten-hooks-tests"
"$TEST_DIR/cat-kitten-hooks-tests"
```

**Create `tests/CatKittenHooksTests.swift`**:

```swift
import Foundation

@main
enum CatKittenHooksTests {
    typealias K = CatKittens
    typealias H = CatKittenHooks

    static func dict(_ x: Any?) -> [String: Any] { x as? [String: Any] ?? [:] }
    static func shown(_ list: [K.Kitten]) -> [String] { list.map { "\($0.id):\($0.state.rawValue)" } }

    /// What the hook server does with one payload: a permission request goes to `permission`, every other event to `event`, and an event that carries no kitten event
    /// changes nothing (not even a tick).
    static func apply(_ list: [K.Kitten], _ payload: [String: Any], at t: Double) -> [K.Kitten] {
        let name = payload["hook_event_name"] as? String ?? ""
        let ev = name == "PermissionRequest" ? H.permission(payload: payload, now: t) : H.event(name: name, payload: payload, now: t)
        return ev.map { K.step(list, $0) } ?? list
    }

    @MainActor static func main() {
        CT.section("the hooks' words: which events carry a kitten event, and which are the parent's own")
        let start = H.event(name: "SubagentStart", payload: ["agent_id": "a1", "agent_type": "Explore", "session_id": "S1"], now: 7)
        CT.check("SubagentStart with an agent_id adds a kitten, with its type and session", [start?.kind.rawValue, start?.id, start?.agentType, start?.session], ["start", "a1", "Explore", "S1"])
        CT.check("the session can be a conversation_id", H.event(name: "SubagentStart", payload: ["agent_id": "a1", "conversation_id": "C9"], now: 0)?.session, "C9")
        CT.check("SubagentStop", H.event(name: "SubagentStop", payload: ["agent_id": "a1"], now: 1)?.kind, .stop)
        for name in ["PreToolUse", "PostToolUse"] {
            let ev = H.event(name: name, payload: ["agent_id": "a1", "tool_name": "Grep"], now: 2)
            CT.check("\(name) with an agent_id sets the kitten's state from the tool", [ev?.kind.rawValue, ev?.id, ev?.tool], ["tool", "a1", "Grep"])
            CT.checkTrue("\(name) without one is the parent's own event", H.event(name: name, payload: ["tool_name": "Grep"], now: 2) == nil)
        }
        CT.check("a permission request from a subagent", H.permission(payload: ["agent_id": "a1"], now: 3)?.kind, .permission)
        CT.checkTrue("a permission request from the parent is not a kitten event", H.permission(payload: ["tool_name": "Bash"], now: 3) == nil)
        CT.check("a request answered is the kitten back to work", H.resolved(subagentId: "a1", now: 4).kind, .resolved)
        for name in ["Stop", "StopFailure", "SessionEnd", "Interrupt"] {
            CT.check("\(name) of the parent takes its session's kittens", [H.event(name: name, payload: ["session_id": "S1"], now: 5)?.kind.rawValue, H.event(name: name, payload: ["session_id": "S1"], now: 5)?.session], ["end", "S1"])
        }
        CT.check("a Stop with no session takes every kitten", H.event(name: "Stop", payload: [:], now: 5)?.session, nil)
        CT.checkTrue("a Stop that names a subagent is not the parent's", H.event(name: "Stop", payload: ["agent_id": "a1"], now: 5) == nil)
        for name in ["SessionStart", "UserPromptSubmit", "Notification", "PostToolUseFailure", "SomethingNew", ""] {
            CT.checkTrue("\(name.isEmpty ? "an unnamed event" : name) is no kitten event", H.event(name: name, payload: ["agent_id": "a1"], now: 6) == nil)
        }

        CT.section("an agent_id that is not one: not text, empty, or longer than 128 characters is the parent's own")
        for (label, v) in [("a number", 7 as Any), ("null", NSNull()), ("an empty string", ""), ("a list", ["a"]), ("129 characters", String(repeating: "x", count: 129))] {
            CT.checkTrue("\(label): SubagentStart, a tool event, a permission request and a stop make no kitten event", H.event(name: "SubagentStart", payload: ["agent_id": v], now: 1) == nil && H.event(name: "PreToolUse", payload: ["agent_id": v], now: 1) == nil && H.permission(payload: ["agent_id": v], now: 1) == nil && H.event(name: "SubagentStop", payload: ["agent_id": v], now: 1) == nil)
        }
        CT.check("128 characters is an ID", H.subagentId(["agent_id": String(repeating: "x", count: 128)])?.count, 128)
        CT.check("a type that is not text is no type", H.event(name: "SubagentStart", payload: ["agent_id": "a", "agent_type": 7], now: 1)?.agentType, nil)

        guard let dir = ProcessInfo.processInfo.environment["NM_KITTEN_RECEIVED"] else { print("NM_KITTEN_RECEIVED is not set: run this through scripts/test-cat-kitten-hooks.sh"); exit(2) }
        let data = CT.fixtureURL("subagent-scenarios.json", dir: "mac")
        let fx = try! JSONSerialization.jsonObject(with: Data(contentsOf: data)) as! [String: Any]
        let common = dict(fx["common"]), scenarios = dict(fx["scenarios"])

        CT.section("the scripted events, through a socket and back: \(scenarios.count) scenarios, each step's list and, after a farewell, what is drawn")
        for name in scenarios.keys.sorted() {
            let steps = dict(scenarios[name])["steps"] as! [[String: Any]]
            let text = (try? String(contentsOfFile: dir + "/\(name).jsonl", encoding: .utf8)) ?? ""
            var received = text.split(separator: "\n").map { dict(try? JSONSerialization.jsonObject(with: Data($0.utf8))) }.makeIterator()
            var list: [K.Kitten] = [], problems: [String] = []
            for (n, step) in steps.enumerated() {
                let at = (step["at"] as! NSNumber).doubleValue
                if let sent = step["event"] as? [String: Any] {
                    guard let got = received.next() else { problems.append("step \(n + 1): the socket received nothing"); break }
                    let want = common.merging(sent) { _, s in s }
                    if !CT.diffs(got, want).isEmpty { problems.append("step \(n + 1): the socket received \(got) and not \(want)"); break }
                    list = apply(list, got, at: at)
                } else if let inner = step["internal"] as? [String: Any] {
                    switch inner["type"] as? String {
                    case "resolved": list = K.step(list, H.resolved(subagentId: inner["id"] as! String, now: at))
                    case "sweep": list = K.step(list, .sweep(t: at))
                    default: list = K.step(list, .tick(t: at))
                    }
                }
                if shown(list) != step["kittens"] as! [String] { problems.append("step \(n + 1) (\(step["say"]!)): \(shown(list)) and not \(step["kittens"]!)") }
                if let view = step["view"] as? [String], let after = step["viewAt"] as? NSNumber, shown(K.view(list, now: at + after.doubleValue)) != view {
                    problems.append("step \(n + 1): \(after) ms later \(shown(K.view(list, now: at + after.doubleValue))) is drawn and not \(view)")
                }
            }
            if received.next() != nil { problems.append("the socket received more than the scenario has") }
            CT.checkRows("\(name): \(steps.count) steps, \(text.split(separator: "\n").count) events sent", problems)
        }

        CT.section("the farewell needs no timer: the view hides the kitten when its time is up, and the next event of any kind drops it")
        var l = apply([], ["hook_event_name": "SubagentStart", "agent_id": "a1"], at: 0)
        l = apply(l, ["hook_event_name": "SubagentStop", "agent_id": "a1"], at: 100)
        CT.check("at 699 ms it is still waving, at 700 it is gone from the view, and it is still in the list", [K.view(l, now: 699).count, K.view(l, now: 700).count, l.count], [1, 0, 1])
        CT.check("a tool event of the parent does not touch the list (no kitten event), a start does", [apply(l, ["hook_event_name": "PreToolUse", "tool_name": "Edit"], at: 900).count, apply(l, ["hook_event_name": "SubagentStart", "agent_id": "a2"], at: 900).count], [1, 1])

        CT.finish()
    }
}
```

**Edit `tests/CatWiringTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkTrue("the display mode comes from Settings", cast2.contains("var displayMode: CatDisplayMode { CatSettingsStore.shared.display.mode }"))

        CT.finish()
    }
```

and replace it with:

```swift
        CT.checkTrue("the display mode comes from Settings", cast2.contains("var displayMode: CatDisplayMode { CatSettingsStore.shared.display.mode }"))

        CT.section("Kittens: the hook server turns the subagent events into kitten events in both builds, the sleep timer sweeps, nothing runs by itself")
        let kittenApp = source("CatKittens+App.swift"), kittenHooks = source("CatKittenHooks.swift"), kittenCore = source("CatKittens.swift"), sleepApp = source("CatSleep+App.swift"), types = source("IslandTypes.swift")
        /// How many `#if` blocks are open at an offset of a file: 0 means the code is in every build (the App Store's included).
        func depth(_ text: String, at offset: Int) -> Int {
            guard offset >= 0 else { return -1 }   // the anchor is not there: not "in every build"
            var d = 0
            for line in String(text.utf16.prefix(offset))!.components(separatedBy: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("#if ") { d += 1 } else if t.hasPrefix("#endif") { d -= 1 }
            }
            return d
        }
        CT.checkTrue("the sources were read", kittenApp.contains("func kittenEvent") && kittenHooks.contains("enum CatKittenHooks") && kittenCore.contains("enum CatKittens") && sleepApp.contains("CatSleepClock"))
        CT.check("processEvent turns a hook event into a kitten event once, after the pill's last event and before a pending approval can end the handling", [count("CatKittenHooks.event(name: name, payload: payload", in: hook), at("CatKittenHooks.event(name: name, payload: payload", in: hook) > at("state.touchPill(agentId)", in: hook) ? 1 : 0, at("CatKittenHooks.event(name: name, payload: payload", in: hook) < at("if !resolved { return }", in: hook) ? 1 : 0], [1, 1, 1])
        CT.check("the events reach the pill the event belongs to (agentId), a permission request the pill that owns it (pillId)", [count("state.kittenEvent(agentId, kitten)", in: hook), count("state.kittenEvent(pillId, kitten)", in: hook)], [1, 1])
        CT.checkTrue("a request from a subagent is remembered in the approval (subagentId), and its kitten is resolved when the card is answered, dismissed or displaced", types.contains("var subagentId: String? = nil") && hook.contains("subagentId: askedBy") && count("resolveApprovalKitten(", in: hook) == 4)
        CT.checkTrue("the hook server's kitten calls are in every build: none sits inside an #if block (the App Store build installs SubagentStart and SubagentStop too)", ["CatKittenHooks.event(name: name, payload: payload", "CatKittenHooks.permission(payload: payload", "resolveApprovalKitten(state.pendingApproval)"].allSatisfy { depth(hook, at: at($0, in: hook)) == 0 })
        CT.check("both installers (the GitHub build's and the App Store build's) list SubagentStart and SubagentStop", count("(\"SubagentStart\", 10), (\"SubagentStop\", 10)", in: hook), 2)
        CT.checkTrue("both relays forward the hook's payload whole (they add fields and remove none), so a subagent's agent_id and agent_type reach the island", count("s.sendall((json.dumps(payload)", in: hook) >= 4 && !hook.contains("payload.pop(") && !hook.contains("del payload[") && !hook.contains("payload.clear("))
        CT.checkTrue("the kitten files have no build condition at all", [kittenApp, kittenHooks, kittenCore].allSatisfy { !$0.contains("#if") })
        CT.checkTrue("the sleep timer's sweep: when the cat falls asleep the kittens whose stop never came go", sleepApp.contains("if asleep { app?.sweepKittens() }") && kittenApp.contains(".sweep(t: ms)"))
        CT.checkTrue("a pill that goes takes its kittens, and they are never stored", app.contains("kittens[id] = nil") && app.contains("@Published var kittens: [String: [CatKittens.Kitten]] = [:]") && !kittenApp.contains("UserDefaults") && !kittenCore.contains("UserDefaults"))
        CT.checkTrue("no timer and no polling anywhere in the kitten code: a farewell ends because the view stops drawing it", [kittenApp, kittenHooks, kittenCore].allSatisfy { !$0.contains("Timer") && !$0.contains("asyncAfter") && !$0.contains("DispatchWorkItem") && !$0.contains("Task {") })
        let sender = (try? String(contentsOfFile: "scripts/test-cat-kitten-hooks.sh", encoding: .utf8)) ?? ""
        CT.checkTrue("the tests send the scripted events to a socket of their own, never the app's", count("fake-subagent-events.py --scenario", in: sender) == 1 && sender.contains("--sock \"$SOCK_DIR/s\"") && !sender.contains("Application Support"))

        CT.finish()
    }
```

Run: `chmod +x scripts/test-cat-kitten-hooks.sh`
Expected: no output.

Run: `bash scripts/test-cat-kitten-hooks.sh 2>&1 | tail -2`
Expected: FAIL: `error opening input file 'NotchBuddy/Sources/App/CatKittenHooks.swift'`.

Run: `bash scripts/test-cat-wiring.sh 2>&1 | tail -1`
Expected: FAIL: `7 test(s) failed.`

- [ ] **Step 3: Write the hooks' words, the lists and the hook server's calls**

`HookServer.processEvent` hands every hook event to `CatKittenHooks.event` right after it touches the pill, so a `SubagentStop` or a parent's `Stop` still reaches the kittens while an approval is pending. A `PermissionRequest` that carries an `agent_id` makes its kitten wait on the approval and is remembered in the `ApprovalInfo`; the kitten is resolved when the card is answered, dismissed, or displaced by the next request. A pill that goes (`removeTask`) takes its kittens. The sleep timer's sweep rides the existing `onChange` of the sleep clock. The parent's cat behaves exactly as before.

**Create `NotchBuddy/Sources/App/CatKittenHooks.swift`**:

```swift
import Foundation

// What a hook event does to the kittens: the one place that reads the hooks' words. `SubagentStart` adds a kitten, a `PreToolUse` or `PostToolUse` that carries an
// `agent_id` sets its state, a `PermissionRequest` that carries one makes it wait on an approval, `SubagentStop` makes it leave, and the parent's own Stop (or the session
// ending) takes all of them. An event without an `agent_id` is the parent's own and is not a kitten event: that is the fallback for a Claude Code that sends none (kittens still
// appear at the start and leave at the stop, in the working pose). The app (`HookServer`) calls this and hands the result to `CatKittens.step`. Foundation only.

enum CatKittenHooks {
    /// The subagent an event belongs to: its `agent_id` (text, 1 to 128 characters), or nil when the event is the parent's own.
    static func subagentId(_ payload: [String: Any]) -> String? {
        (payload["agent_id"] as? String).flatMap { CatKittens.isKittenId($0) ? $0 : nil }
    }

    /// The session an event belongs to, as the hook server reads it (`session_id`, else `conversation_id`), or nil when it has none.
    static func sessionId(_ payload: [String: Any]) -> String? {
        ["session_id", "conversation_id"].compactMap { payload[$0] as? String }.first { CatKittens.isKittenId($0) }
    }

    /// The kitten event a hook event carries at `now` (ms on the app's clock), or nil when it carries none. `PermissionRequest` is `permission(payload:now:)`, because the
    /// hook server handles it apart.
    static func event(name: String, payload: [String: Any], now: Double) -> CatKittens.Event? {
        switch name {
        case "SubagentStart":
            return subagentId(payload).map { .start(id: $0, agentType: payload["agent_type"] as? String, session: sessionId(payload), t: now) }
        case "SubagentStop":
            return subagentId(payload).map { .stop(id: $0, t: now) }
        case "PreToolUse", "PostToolUse":
            return subagentId(payload).map { .tool(id: $0, tool: payload["tool_name"] as? String, t: now) }
        case "Stop", "StopFailure", "SessionEnd", "Interrupt":
            // the parent's turn or session is over: no kittens (those of its other sessions stay). A Stop that names a subagent is not the parent's.
            return subagentId(payload) == nil ? .end(session: sessionId(payload), t: now) : nil
        default:
            return nil
        }
    }

    /// A permission request from a subagent: its kitten waits on an approval.
    static func permission(payload: [String: Any], now: Double) -> CatKittens.Event? {
        subagentId(payload).map { .permission(id: $0, t: now) }
    }

    /// The request was answered, or dismissed, or displaced by the next one: the kitten is back to work.
    static func resolved(subagentId id: String, now: Double) -> CatKittens.Event { .resolved(id: id, t: now) }
}
```

**Create `NotchBuddy/Sources/App/CatKittens+App.swift`**:

```swift
import Foundation
import QuartzCore

// The app's way into the kittens: each agent pill's list in `AppState`, the clock the events are stamped with, and the sleep timer's sweep. Nothing here is in the
// contract, and the test programs do not compile this file (`tests/CatWiringTests.swift` pins where the hook server and the sleep clock call it).

extension AppState {
    /// Applies one kitten event to a pill's list (`CatKittens.step`). A pill with no kittens left has no entry. Never stored.
    func kittenEvent(_ pillId: String, _ event: CatKittens.Event) {
        let next = CatKittens.step(kittens[pillId] ?? [], event)
        if next.isEmpty { if kittens[pillId] != nil { kittens[pillId] = nil } } else if kittens[pillId] != next { kittens[pillId] = next }
    }

    /// The cat's ten-minute sleep timer fired: a kitten whose stop never came, and whose last event is ten minutes old, goes (`CatKittens.step`'s sweep).
    func sweepKittens(at ms: Double = CACurrentMediaTime() * 1000) {
        for pill in Array(kittens.keys) { kittenEvent(pill, .sweep(t: ms)) }
    }

    /// What to draw for a pill's kittens at `ms`: the list in order, without a farewell that is over. Called from the canvases, which redraw on their own: no timer is needed.
    func kittenView(_ pillId: String, at ms: Double = CACurrentMediaTime() * 1000) -> [CatKittens.Kitten] {
        CatKittens.view(kittens[pillId] ?? [], now: ms)
    }
}
```

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
    /// True while the idle cat is asleep: ten minutes with no agent event (`CatSleepClock`). The cat then shows `.sleeping` instead of `.idle`.
    @Published var catAsleep = false
    /// Settings → Cat → Display and the Main cat: when either changes, the island's views read the cast again (`storeWatch`).
    private var storeWatch: AnyCancellable?
```

and replace it with:

```swift
    /// True while the idle cat is asleep: ten minutes with no agent event (`CatSleepClock`). The cat then shows `.sleeping` instead of `.idle`.
    @Published var catAsleep = false
    /// Each agent pill's subagents, shown as kittens beside its cat (`CatKittens`, changed only by `kittenEvent`). Never stored: a restart starts with none.
    @Published var kittens: [String: [CatKittens.Kitten]] = [:]
    /// Settings → Cat → Display and the Main cat: when either changes, the island's views read the cast again (`storeWatch`).
    private var storeWatch: AnyCancellable?
```

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
        }
        // Undeclared or declared-but-not-active: remove
        tasks.removeAll { $0.id == id }
        if focusId == id { focusId = mainPillId }
```

and replace it with:

```swift
        }
        // Undeclared or declared-but-not-active: remove
        kittens[id] = nil
        tasks.removeAll { $0.id == id }
        if focusId == id { focusId = mainPillId }
```

**Edit `NotchBuddy/Sources/App/CatSleep+App.swift`**, find this text (it occurs exactly once):

```swift
    /// feeds `stateChanged`, and when the clock puts the cat to sleep or wakes it, `AppState.catAsleep` follows.
    func attach(to app: AppState) {
        onChange = { [weak app] asleep in app?.catAsleep = asleep }
        app.$tasks.combineLatest(app.$focusId, app.$stateOverride)
            .map { tasks, focus, forced -> CatState in
```

and replace it with:

```swift
    /// feeds `stateChanged`, and when the clock puts the cat to sleep or wakes it, `AppState.catAsleep` follows.
    func attach(to app: AppState) {
        // When the cat falls asleep (ten minutes with no agent event) a kitten whose stop never came goes too: the only cleanup besides the parent's stop and its session ending.
        onChange = { [weak app] asleep in
            app?.catAsleep = asleep
            if asleep { app?.sweepKittens() }
        }
        app.$tasks.combineLatest(app.$focusId, app.$stateOverride)
            .map { tasks, focus, forced -> CatState in
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
    private init() {}

    // MARK: - Approval fd helpers

    @MainActor
    private func cancelApprovalFDSource() {
        approvalFDSource?.cancel()
        approvalFDSource = nil
```

and replace it with:

```swift
    private init() {}

    // MARK: - Approval fd helpers

    /// An approval that a subagent asked for is over (answered, dismissed or displaced): its kitten is back to work.
    @MainActor
    private func resolveApprovalKitten(_ info: ApprovalInfo?) {
        guard let info, let subagent = info.subagentId else { return }
        AppState.shared.kittenEvent(info.pillId, CatKittenHooks.resolved(subagentId: subagent, now: CACurrentMediaTime() * 1000))
    }

    @MainActor
    private func cancelApprovalFDSource() {
        approvalFDSource?.cancel()
        approvalFDSource = nil
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
        cancelApprovalFDSource()
        pendingApprovalFD = -1
        let state = AppState.shared
        let pillId = state.pendingApproval?.pillId ?? "integration_claude"
        state.pendingApproval = nil
        state.isPinned = false
        state.updateTask(id: pillId, state: .working)
        clearPillBadge(id: pillId)
```

and replace it with:

```swift
        cancelApprovalFDSource()
        pendingApprovalFD = -1
        let state = AppState.shared
        let pillId = state.pendingApproval?.pillId ?? "integration_claude"
        resolveApprovalKitten(state.pendingApproval)
        state.pendingApproval = nil
        state.isPinned = false
        state.updateTask(id: pillId, state: .working)
        clearPillBadge(id: pillId)
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
            return
        }

        state.touchPill(agentId)   // the pill's last event: Two cats mode's busiest-other rule reads it
        let focused = state.focusId == agentId

        // While a permission request is pending, dismiss when the resolving event arrives,
        // then continue normal processing. Only skip normal processing when unresolved.
```

and replace it with:

```swift
            return
        }

        state.touchPill(agentId)   // the pill's last event: Two cats mode's busiest-other rule reads it
        // A subagent's start, tools and stop, and the parent's own stop, change this pill's kittens (CatKittenHooks). The parent's cat behaves as it always has.
        if let kitten = CatKittenHooks.event(name: name, payload: payload, now: CACurrentMediaTime() * 1000) { state.kittenEvent(agentId, kitten) }
        let focused = state.focusId == agentId

        // While a permission request is pending, dismiss when the resolving event arrives,
        // then continue normal processing. Only skip normal processing when unresolved.
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
        activeSessionId = sessionId

        upsertWorkspaceTask(id: pillId, projectName: projectName, cwd: cwd)
        state.updateTask(id: pillId, state: .approval)
        state.pendingApproval = ApprovalInfo(sessionId: sessionId, tool: tool,
                                              command: command, inputKey: inputKey, pillId: pillId)
        state.isPinned = true
        SoundEngine.shared.play("approval")

        // Approval always forces the island open — user must be able to respond.
```

and replace it with:

```swift
        activeSessionId = sessionId

        upsertWorkspaceTask(id: pillId, projectName: projectName, cwd: cwd)
        state.updateTask(id: pillId, state: .approval)
        // The request this one displaces is answered as far as its kitten goes; a request from a subagent makes its kitten wait on this approval.
        resolveApprovalKitten(state.pendingApproval)
        let askedBy = CatKittenHooks.subagentId(payload)
        if let kitten = CatKittenHooks.permission(payload: payload, now: CACurrentMediaTime() * 1000) { state.kittenEvent(pillId, kitten) }
        state.pendingApproval = ApprovalInfo(sessionId: sessionId, tool: tool,
                                              command: command, inputKey: inputKey, pillId: pillId, subagentId: askedBy)
        state.isPinned = true
        SoundEngine.shared.play("approval")

        // Approval always forces the island open — user must be able to respond.
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
        }

        let state = AppState.shared
        let pillId = state.pendingApproval?.pillId ?? "integration_claude"
        state.pendingApproval = nil
        state.isPinned = false
        state.updateTask(id: pillId, state: .working)
        clearPillBadge(id: pillId)
```

and replace it with:

```swift
        }

        let state = AppState.shared
        let pillId = state.pendingApproval?.pillId ?? "integration_claude"
        resolveApprovalKitten(state.pendingApproval)
        state.pendingApproval = nil
        state.isPinned = false
        state.updateTask(id: pillId, state: .working)
        clearPillBadge(id: pillId)
```

**Edit `NotchBuddy/Sources/App/IslandTypes.swift`**, find this text (it occurs exactly once):

```swift
    /// Pill that owns this approval: "integration_claude", "agent_cursor", or "agent_codex".
    var pillId: String
}

```

and replace it with:

```swift
    /// Pill that owns this approval: "integration_claude", "agent_cursor", or "agent_codex".
    var pillId: String
    /// The subagent that asked (the request's `agent_id`), when one did: its kitten waits on this approval.
    var subagentId: String? = nil
}

```

- [ ] **Step 4: Run them to see them pass**

Run: `bash scripts/test-cat-kitten-hooks.sh 2>&1 | grep -c "✓"; bash scripts/test-cat-kitten-hooks.sh 2>&1 | tail -1`
Expected: `36`, then `All tests passed.`

Run: `bash scripts/test-cat-wiring.sh 2>&1 | tail -1; bash scripts/test-cat-sleep.sh 2>&1 | tail -1`
Expected: `All tests passed.` twice.

- [ ] **Step 5: Prove the test bites (one-off, never committed)**

Stop treating the parent's `Stop` as the end of its kittens and see the scenarios fail.

Run: `sed -i '' 's/case "Stop", "StopFailure", "SessionEnd", "Interrupt":/case "StopFailure", "SessionEnd", "Interrupt":/' NotchBuddy/Sources/App/CatKittenHooks.swift && bash scripts/test-cat-kitten-hooks.sh 2>&1 | grep -c "✗"`
Expected: `4`.

Run: `sed -i '' 's/case "StopFailure", "SessionEnd", "Interrupt":/case "Stop", "StopFailure", "SessionEnd", "Interrupt":/' NotchBuddy/Sources/App/CatKittenHooks.swift && bash scripts/test-cat-kitten-hooks.sh 2>&1 | tail -1`
Expected: `All tests passed.`

- [ ] **Step 6: Build both targets**

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `Created project at …` and `** BUILD SUCCEEDED **`.

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **` (the kitten code is in both builds: Claude Code's hooks exist in both).

- [ ] **Step 7: Commit**

```bash
git add NotchBuddy/Sources/App/CatKittenHooks.swift NotchBuddy/Sources/App/CatKittens+App.swift NotchBuddy/Sources/App/IslandTypes.swift NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/CatSleep+App.swift NotchBuddy/Sources/App/HookServer.swift tests/CatKittenHooksTests.swift tests/CatWiringTests.swift tests/kitten_socket_server.py tests/fixtures/mac/subagent-scenarios.json scripts/test-cat-kitten-hooks.sh scripts/fake-subagent-events.py NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): subagents become kittens in the app's state

SubagentStart, the tool and permission events that carry an agent_id, SubagentStop, the parent's Stop and the sleep timer's sweep turn into kitten events on the pill
they belong to (CatKittenHooks, applied by HookServer.processEvent and processPermissionRequest, in both builds). A subagent's approval is remembered and its kitten
resolved when the card is answered, dismissed or displaced. Five scripted scenarios go through a socket of the test's own and back; fake-subagent-events.py sends
them to a real build for the owner's check.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Kittens drawn at every place, the sheets and the frame bench (stage 5)

**Agent:** `nm-implementer-deep`. One function draws a parent's kittens, a layer puts it in the island, and the pill's title has to keep clear; the sheets are the proof.

**Files:**
- Create: `NotchBuddy/Sources/App/CatKittenDraw.swift`, `NotchBuddy/Sources/App/KittenViews.swift`
- Modify: `NotchBuddy/Sources/App/CatKittens.swift` (`State.catState`), `CatIslandLayout.swift`, `IslandRootView.swift`, `IslandViewContent.swift`, `tests/CatKittensTests.swift`, `tests/CatAgentListTests.swift`, `tests/CatWiringTests.swift`, `scripts/test-cat-agent-list.sh`, `scripts/render-cats.sh`, `scripts/render-cats.swift` (the `--kittens` sheet and `--bench-kittens`), `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (by `xcodegen`)

**Interfaces:**
- Consumes: Tasks 12 and 13 (`CatKittens.slots`, `AppState.kittens` and `kittenView`), Task 11's `CatIslandLayout` and `secondCatPlace`, Task 9's `AppState.cast`.
- Produces: `CatKittens.State.catState` (its own state, and a happy `finished` while it leaves); `CatIslandLayout.kittenBox(_:)`, `kittenParents(…)`, `pillKittenReserve(_:pillHeight:)`; `CatKittenHerd` and `CatKittenDraw.draw(…)` (each kitten is `CatPresets.kitten(of:)` of its parent's coat with an engine of its own, its own state badge, the parent's collar in the agent's colour, and "+N" and "×N" labels); `KittenLayerView` and `KittenPlacement` (the big cat's kittens beside it in the compact island and in a row under it in the overview; in Two cats mode each cat's under it, and in the compact island one count by cat 2 for both); the pills' kittens at their trailing end (the title keeps clear); `render-cats.sh --kittens --scenario NAME [--mode …] [--both] [--steps …]` and `--bench-kittens`.

- [ ] **Step 1: Write the failing tests**

The kitten's cat state; the kitten layer's boxes (every kitten, "+N" and "×N" of five places with 0 to 9 kittens fit inside their box); which cats have kittens and where (One cat and A cat for each agent: the big cat's; Two cats: each cat's expanded, one count by cat 2 compact); what a pill reserves for its kittens. The pins: no kitten file gives an engine `useCharacter`, every kitten has its own badge and collar and blinks happily while it leaves, one placement draws the big cat's and the pair's kittens with the same mask and fade as the cats, a pill draws its own at its trailing end and its title keeps clear, the layers run no timer and pause when the island is hidden, and the parent's coat reaches the layer from the cast.

**Edit `scripts/test-cat-agent-list.sh`**, find this text (it occurs exactly once):

```bash
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift \
    $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatIslandLayout.swift \
    tests/CatTestSupport.swift tests/CatAgentListTests.swift \
    -o "$TEST_DIR/cat-agent-list-tests"
```

and replace it with:

```bash
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift \
    $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatKittens.swift $APP/CatIslandLayout.swift \
    tests/CatTestSupport.swift tests/CatAgentListTests.swift \
    -o "$TEST_DIR/cat-agent-list-tests"
```

**Edit `tests/CatAgentListTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.check("every one of the 11 states has words", CatState.allCases.map { CatIslandLayout.stateWords($0) }.filter { $0.isEmpty }, [])

        CT.finish()
    }
```

and replace it with:

```swift
        CT.check("every one of the 11 states has words", CatState.allCases.map { CatIslandLayout.stateWords($0) }.filter { $0.isEmpty }, [])

        CT.section("which cats have kittens, and where: One cat and A cat for each agent the big cat, Two cats each cat (expanded) or a count by cat 2 (compact)")
        let bigAt = (x: 40.0, y: 16.0, d: 20.0), secondAt = (x: 54.0, y: 16.0, d: 20.0)
        let parentsOne = CatIslandLayout.kittenParents(.one, expanded: false, big: bigAt, second: nil)
        CT.check("One cat, compact: the big cat's, tucked beside it", parentsOne.map { [$0.place, "\($0.cat)", "\($0.unit)", "\($0.countsBoth)"] }, [["bigCompact", "0", "20.0", "false"]])
        CT.check("A cat for each agent, expanded: the big cat's, in a row under it", CatIslandLayout.kittenParents(.perAgent, expanded: true, big: (68, 101, 58), second: nil).map(\.place), ["bigExpanded"])
        let parentsTwo = CatIslandLayout.kittenParents(.two, expanded: false, big: bigAt, second: secondAt)
        CT.check("Two cats, compact: one layer, by cat 2, counting both cats' kittens", parentsTwo.map { [$0.place, "\($0.cat)", "\($0.x)", "\($0.countsBoth)"] }, [["pairCompact", "1", "54.0", "true"]])
        CT.check("Two cats, expanded: each cat's, centred under it", CatIslandLayout.kittenParents(.two, expanded: true, big: (50, 101, 58), second: (108, 109, 46)).map { [$0.place, "\($0.cat)", "\($0.unit)"] }, [["pairExpanded", "0", "58.0"], ["pairExpanded", "1", "46.0"]])
        CT.check("Two cats with no cat 2 to hang a count on: nothing", CatIslandLayout.kittenParents(.two, expanded: false, big: bigAt, second: nil), [])

        CT.section("the kitten layer's boxes hold every kitten, every \"+N\" and the pair's \"×N\", whatever the count")
        var outside: [String] = []
        for place in ["bigExpanded", "bigCompact", "pairExpanded", "pairCompact", "pill"] {
            let box = CatIslandLayout.kittenBox(place)
            for count in 0...9 {
                let list = (0..<count).map { CatKittens.Kitten(id: "k\($0)", state: .working, born: Double($0), last: 0) }
                let s = CatKittens.slots(place, list)
                var inside = s.shown.allSatisfy { $0.x - $0.d / 2 >= box.x0 && $0.x + $0.d / 2 <= box.x1 && $0.y - $0.d / 2 >= box.y0 && $0.y + $0.d / 2 <= box.y1 }
                if let m = s.moreAt { inside = inside && m.x - m.size * 1.4 >= box.x0 && m.x + m.size * 1.4 <= box.x1 && m.y - m.size >= box.y0 && m.y + m.size <= box.y1 }
                if let l = s.label { inside = inside && l.x - l.size * 1.4 >= box.x0 && l.x + l.size * 1.4 <= box.x1 && l.y - l.size >= box.y0 && l.y + l.size <= box.y1 }
                if !inside { outside.append("\(place) with \(count)") }
            }
        }
        CT.checkRows("five places, 0 to 9 kittens", outside)
        CT.check("a pill with three kittens reserves their width: 3 slots of 16/28, from the edge to the third's far side and a little more", CatIslandLayout.pillKittenReserve(CatKittens.slots("pill", (0..<3).map { CatKittens.Kitten(id: "k\($0)", state: .working, born: Double($0), last: 0) }), pillHeight: 28), (17.5 / 28 + 2 * 16.0 / 28 + 15.0 / 56 + 0.2) * 28)
        CT.checkTrue("with a fourth, the '+N' after the third is reserved too", CatIslandLayout.pillKittenReserve(CatKittens.slots("pill", (0..<5).map { CatKittens.Kitten(id: "k\($0)", state: .working, born: Double($0), last: 0) }), pillHeight: 28) > 3 * 16.0 + 17.5)
        CT.check("and a pill without kittens reserves nothing", CatIslandLayout.pillKittenReserve(CatKittens.slots("pill", []), pillHeight: 28), 0)

        CT.finish()
    }
```

**Edit `tests/CatKittensTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkNear("a kitten whose stop never came goes with the sleep timer: ten minutes", CatRules.sleepAfterMs, number(limits["sleepAfterMs"])!)
        CT.check("the four states", K.State.allCases.map(\.rawValue), fx["states"] as! [String])
        var diffs: [String] = []
        for (name, want) in fx["places"] as! [String: [String: Any]] {
```

and replace it with:

```swift
        CT.checkNear("a kitten whose stop never came goes with the sleep timer: ten minutes", CatRules.sleepAfterMs, number(limits["sleepAfterMs"])!)
        CT.check("the four states", K.State.allCases.map(\.rawValue), fx["states"] as! [String])
        CT.check("the cat state each shows: its own, and a happy finished while it leaves", K.State.allCases.map(\.catState), [.working, .searching, .approval, .finished])
        var diffs: [String] = []
        for (name, want) in fx["places"] as! [String: [String: Any]] {
```

**Edit `tests/CatWiringTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkTrue("the tests send the scripted events to a socket of their own, never the app's", count("fake-subagent-events.py --scenario", in: sender) == 1 && sender.contains("--sock \"$SOCK_DIR/s\"") && !sender.contains("Application Support"))

        CT.finish()
    }
```

and replace it with:

```swift
        CT.checkTrue("the tests send the scripted events to a socket of their own, never the app's", count("fake-subagent-events.py --scenario", in: sender) == 1 && sender.contains("--sock \"$SOCK_DIR/s\"") && !sender.contains("Application Support"))

        CT.section("Kittens are drawn at every place by one function, in their parent's coat, and a kitten is never given useCharacter")
        let layers = source("KittenViews.swift"), draw = source("CatKittenDraw.swift"), pillSource = content
        CT.checkTrue("the sources were read", layers.contains("struct KittenLayerView") && draw.contains("enum CatKittenDraw"))
        CT.checkTrue("no kitten file gives an engine useCharacter: a kitten's coat is its parent's as a kitten, made with CatPresets.kitten(of:), and a new engine when the parent's coat changes", !layers.contains("useCharacter(") && !draw.contains("useCharacter(") && draw.contains("CatPresets.kitten(of: CatPresets.byID(parentCat))") && draw.contains("e.coat == parentCat"))
        CT.checkTrue("every kitten has its own state badge, wears the parent's collar colour and blinks happily while it leaves", draw.contains("CatDrawOptions(badge: true)") && draw.contains("e.collar = colour") && draw.contains("(CatKittens.State(rawValue: k.state) ?? .working).catState"))
        CT.check("the big cat's and the pair's kittens are drawn by one placement in the island, with the same mask and the same fade as the cats", [count("KittenPlacement(state: state", in: island), count("CatIslandLayout.kittenParents(", in: layers)], [1, 1])
        CT.checkTrue("an agent pill draws its own kittens at its trailing end, and its title keeps clear of them", pillSource.contains("KittenLayerView(state: state, pills: [task.id], parentCat: cat, place: \"pill\", unit: 28, colour: task.color)") && pillSource.contains(".padding(.trailing, kittenReserve)"))
        CT.checkTrue("the layers redraw with their canvas, pause when the island is hidden and run no timer of their own", layers.contains("paused: state.mode == .hidden") && ![layers, draw].contains { $0.contains("Timer") || $0.contains("asyncAfter") || $0.contains("DispatchWorkItem") })
        CT.checkTrue("the parent's coat reaches the layer from the cast (the big cat's, cat 2's and the pill's)", layers.contains("cat: spot.cat") && pillSource.contains("parentCat: cat"))

        CT.finish()
    }
```

Run: `bash scripts/test-cat-kittens.sh 2>&1 | grep -c "error:"; bash scripts/test-cat-agent-list.sh 2>&1 | grep -c "error:"`
Expected: FAIL: two numbers above 0, the compile errors of the two programs (the dry run read `10` and `20`: the kittens' state, box, parents and the pill's reserve do not exist yet).

Run: `bash scripts/test-cat-wiring.sh 2>&1 | tail -1`
Expected: FAIL: `7 test(s) failed.`

- [ ] **Step 2: The pure parts**

**Edit `NotchBuddy/Sources/App/CatIslandLayout.swift`**, find this text (it occurs exactly once):

```swift
    }

    /// What cat 2's agent is doing, for the second line of the overview's ticker ("Codex · waiting for you").
    static func stateWords(_ s: CatState) -> String {
```

and replace it with:

```swift
    }

    /// The box a place's kittens, their "+N" and the pair's "×N" can be drawn in, in the place's unit, from the parent's head centre (or, for `pill`, from the pill's trailing edge and the
    /// middle of its height): x from `x0` to `x1`, y from `y0` to `y1`. The kitten layer is a transparent canvas of this size, so it covers no more of the island than it needs.
    static func kittenBox(_ place: String) -> (x0: Double, y0: Double, x1: Double, y1: Double) {
        switch place {
        case "bigExpanded": return (-0.2, 0.25, 2.1, 1.0)
        case "bigCompact": return (0.6, -1.0, 2.8, 0.7)
        case "pairExpanded": return (-1.0, 0.25, 1.0, 1.1)
        case "pairCompact": return (0.3, -0.3, 2.1, 0.9)
        case "pill": return (-3.0, -0.55, 0.15, 0.55)
        default: return (0, 0, 0, 0)
        }
    }

    /// One layer of kittens: which cat is the parent (0 the big cat, 1 cat 2), the place, the unit (the parent's head width), where the parent is, and whether the layer counts
    /// both cats' kittens (the pair's "×N" in the compact island).
    struct KittenParent: Equatable {
        var cat: Int
        var place: String
        var unit: Double
        var x: Double, y: Double
        var countsBoth = false
    }

    /// The layers of kittens for a mode, in the compact island or in the overview. One cat and A cat for each agent: the big cat's, tucked beside it (compact) or in a row under it.
    /// Two cats, expanded: each cat's under it. Two cats, compact: there is no room beside the pair, so one layer by cat 2 draws a count of both cats' kittens.
    static func kittenParents(_ mode: CatDisplayMode, expanded: Bool, big: (x: Double, y: Double, d: Double), second: (x: Double, y: Double, d: Double)?) -> [KittenParent] {
        let place = CatKittens.placeOf(mode, expanded: expanded)
        guard mode == .two else { return [KittenParent(cat: 0, place: place, unit: big.d, x: big.x, y: big.y)] }
        guard let second else { return [] }
        if !expanded { return [KittenParent(cat: 1, place: place, unit: second.d, x: second.x, y: second.y, countsBoth: true)] }
        return [KittenParent(cat: 0, place: place, unit: big.d, x: big.x, y: big.y), KittenParent(cat: 1, place: place, unit: second.d, x: second.x, y: second.y)]
    }

    /// How much of a pill's trailing end its kittens and their "+N" take (in pt, for a pill `h` high): the pill's title keeps clear of them.
    static func pillKittenReserve(_ slots: CatKittens.Slots, pillHeight h: Double) -> Double {
        guard let last = slots.shown.last else { return 0 }
        let kittens = -last.x + last.d / 2 + 0.2
        return max(kittens, slots.moreAt.map { -$0.x + $0.size * 1.0 } ?? 0) * h
    }

    /// What cat 2's agent is doing, for the second line of the overview's ticker ("Codex · waiting for you").
    static func stateWords(_ s: CatState) -> String {
```

**Edit `NotchBuddy/Sources/App/CatKittens.swift`**, find this text (it occurs exactly once):

```swift
    static let leaveMs = 600.0

    enum State: String, CaseIterable, Sendable { case working, searching, approval, leaving }

    /// One subagent: its `agent_id`, its `agent_type`, the session it belongs to (nil when the hook did not say), its state, the times of its start and its last event, and,
```

and replace it with:

```swift
    static let leaveMs = 600.0

    enum State: String, CaseIterable, Sendable {
        case working, searching, approval, leaving

        /// The state a kitten's cat shows: its own, and a happy `finished` while it leaves (the farewell).
        var catState: CatState {
            switch self {
            case .working: return .working
            case .searching: return .searching
            case .approval: return .approval
            case .leaving: return .finished
            }
        }
    }

    /// One subagent: its `agent_id`, its `agent_type`, the session it belongs to (nil when the hook did not say), its state, the times of its start and its last event, and,
```

Run: `bash scripts/test-cat-kittens.sh 2>&1 | tail -1; bash scripts/test-cat-agent-list.sh 2>&1 | tail -1`
Expected: `All tests passed.` twice.

- [ ] **Step 3: The drawing and the layers**

`CatKittenDraw.draw` is the one function the app's layers and the contact sheets draw kittens with. A kitten's engine is made on first sight in the herd, and again when the parent's coat changes: it is never given `useCharacter` (that would make it an adult). `KittenLayerView` is a transparent canvas the size of the place's box, redrawn like the other cat canvases (30 fps, paused while the island is hidden): a farewell ends because `kittenView` stops listing the kitten, with no timer. `KittenPlacement` sits in the island's container after the cats with their mask and fade; the pills' kittens are an overlay at the pill's trailing end, and the pill's title keeps clear of them (4 pt clear of the pill's own cat, which ends 30 pt from the pill's left end, and the width they take at the trailing end).

**Create `NotchBuddy/Sources/App/CatKittenDraw.swift`**:

```swift
import Combine
import CoreGraphics
import Foundation

// Draws a parent's kittens (`CatKittens.slots` says where): each is its parent's cat as a kitten (`CatPresets.kitten(of:)`) with its own engine and state badge, the parent's
// collar in the agent's colour, a happy blink while it leaves, and "+N" or "×N" labels. The app's kitten layers and the contact sheets draw through this one function, so what
// the sheets show is what the island draws. A kitten's coat is its parent's: a kitten's engine is never given `useCharacter` (it would make it an adult), and when the parent's coat
// changes the herd makes a new engine.

/// The engines of the kittens, one for each kitten ID. It belongs to one layer (one parent in one place).
@MainActor
final class CatKittenHerd: ObservableObject {
    private var engines: [String: (coat: String, engine: CatEngine)] = [:]
    /// Where the engines' dice come from: `Double.random` in the app, a seeded source on a contact sheet.
    var rand: () -> Double = { Double.random(in: 0..<1) }

    /// The kitten's engine, made on first sight and again when the parent's coat changes. `now` is the clock the engine reads (ms).
    func engine(_ id: String, parentCat: String, now: @escaping () -> Double, cfg: CatConfig? = nil) -> CatEngine {
        if let e = engines[id], e.coat == parentCat { return e.engine }
        let engine = CatEngine(CatPresets.kitten(of: CatPresets.byID(parentCat)), mini: true, now: now, rand: rand, cfg: cfg)
        engines[id] = (parentCat, engine)
        return engine
    }

    /// Forgets the engines of kittens that are gone.
    func keep(_ ids: Set<String>) {
        if engines.keys.contains(where: { !ids.contains($0) }) { engines = engines.filter { ids.contains($0.key) } }
    }
}

@MainActor
enum CatKittenDraw {
    /// Draws `slots` (from `CatKittens.slots`) for a parent whose head centre (or, for a pill, trailing edge and middle) is `origin`, in units of `unit` px. `advance` moves a
    /// kitten's engine on by a frame (the app reads the real clock, a contact sheet its own); `colour` is the agent's, worn as the collar in Settings' style.
    static func draw(_ cg: CGContext, _ slots: CatKittens.Slots, parentCat: String, origin: (x: Double, y: Double), unit: Double, colour: String?, dpr: Double,
                     herd: CatKittenHerd, now: @escaping () -> Double, cfg: CatConfig? = nil, advance: (CatEngine) -> Void) {
        herd.keep(Set(slots.shown.map(\.id)))
        for k in slots.shown {
            let e = herd.engine(k.id, parentCat: parentCat, now: now, cfg: cfg)
            e.setState((CatKittens.State(rawValue: k.state) ?? .working).catState)
            e.collar = colour
            advance(e)
            var options = CatDrawOptions(badge: true)
            options.collar = e.collarPaint(dpr: dpr)
            CatRenderer.draw(cg, e.look(), cx: origin.x + k.x * unit, cy: origin.y + k.y * unit, D: k.d * unit, options)
        }
        if let m = slots.moreAt { label(cg, "+\(slots.more)", x: origin.x + m.x * unit, y: origin.y + m.y * unit, size: m.size * unit) }
        if let l = slots.label { label(cg, l.text, x: origin.x + l.x * unit, y: origin.y + l.y * unit, size: l.size * unit) }
    }

    /// A small dark pill with a number in it, centred on (x, y): the "+N" of kittens that do not fit and the "×N" of the pair.
    static func label(_ cg: CGContext, _ text: String, x: Double, y: Double, size: Double) {
        let sz = max(8, size), w = Double(text.count) * sz * 0.62 + sz * 0.9, h = sz * 1.3
        cg.fill(CatDraw.roundRect(x - w / 2, y - h / 2, w, h, h / 2), CatDraw.rgb([42, 44, 49]))
        CatDraw.text(cg, text, x: x, y: y + 0.5, size: sz, bold: true, color: CatDraw.rgb([207, 208, 212]))
    }
}
```

**Create `NotchBuddy/Sources/App/KittenViews.swift`**:

```swift
import SwiftUI
import QuartzCore

// Kittens on the island: a transparent layer over a parent that draws that parent's kittens (`CatKittenDraw`), in the place `CatKittens.placeOf` says. A layer redraws with
// the canvas it is, so a farewell ends when `AppState.kittenView` stops listing the kitten: there is no timer, and a hidden island pauses it like every other cat.

/// One parent's kittens in one place. `pills` are the pills whose kittens it draws (the pair's compact label counts both cats'), `parentCat` the coat they are kittens of,
/// `unit` the parent's head width (a pill's height for `pill`).
struct KittenLayerView: View {
    @ObservedObject var state: AppState
    let pills: [String]
    let parentCat: String
    let place: String
    let unit: CGFloat
    let colour: String?
    @StateObject private var herd = CatKittenHerd()

    var body: some View {
        let box = CatIslandLayout.kittenBox(place), u = Double(unit)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: state.mode == .hidden)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                let now = CACurrentMediaTime() * 1000
                let list = pills.flatMap { state.kittenView($0, at: now) }
                let slots = CatKittens.slots(place, list)
                context.withCGContext { cg in
                    CatKittenDraw.draw(cg, slots, parentCat: parentCat, origin: (-box.x0 * u, -box.y0 * u), unit: u, colour: colour, dpr: Double(context.environment.displayScale), herd: herd,
                                       now: { CACurrentMediaTime() * 1000 }) { e in e.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: e.lastTime)) }
                }
            }
        }
        .frame(width: (box.x1 - box.x0) * u, height: (box.y1 - box.y0) * u)
        .allowsHitTesting(false)
    }
}

/// The kittens beside the big cat and cat 2 in the compact island and in the overview (the other views draw no kittens). Nothing is drawn, and nothing runs, while no agent has one.
struct KittenPlacement: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    let islandH: CGFloat

    var body: some View {
        let cast = state.cast
        let compact = state.mode == .compact, overview = state.mode == .expanded && state.view == .overview
        if compact || overview, !state.kittens.isEmpty {
            let one = botPosition(mode: state.mode, view: state.view, islandW: islandW, islandH: islandH, uploadProgress: 0, hasNotch: state.hasNotch, display: cast.mode)
            let two = secondCatPlace(state: state, islandW: islandW, islandH: islandH)
            let parents = CatIslandLayout.kittenParents(cast.mode, expanded: overview, big: (Double(one.0), Double(one.1), Double(one.2)), second: two.map { (Double($0.cx), Double($0.cy), Double($0.d)) })
            ZStack(alignment: .topLeading) {
                ForEach(parents, id: \.cat) { parent in
                    let spot = parent.cat == 0 ? cast.big : cast.second
                    let pills = parent.countsBoth ? [cast.big.pill, cast.second?.pill].compactMap { $0 } : [spot?.pill].compactMap { $0 }
                    if !pills.isEmpty, let spot {
                        layer(pills: pills, cat: spot.cat, place: parent.place, unit: CGFloat(parent.unit), centre: CGPoint(x: parent.x, y: parent.y), colour: parent.countsBoth ? nil : colour(spot.pill))
                    }
                }
            }
            .frame(width: islandW, height: islandH, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }

    private func colour(_ pill: String?) -> String? { pill.flatMap { id in state.tasks.first { $0.id == id }?.color } }

    private func layer(pills: [String], cat: String, place: String, unit: CGFloat, centre: CGPoint, colour: String?) -> some View {
        let box = CatIslandLayout.kittenBox(place), u = Double(unit)
        return KittenLayerView(state: state, pills: pills, parentCat: cat, place: place, unit: unit, colour: colour)
            .position(x: centre.x + CGFloat((box.x0 + box.x1) / 2 * u), y: centre.y + CGFloat((box.y0 + box.y1) / 2 * u))
    }
}
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
            // Two cats mode: cat 2, beside the big cat (nothing at all in the other modes).
            SecondCatPlacement(state: state, islandW: islandWidth, islandH: islandHeight)
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: islandWidth,
```

and replace it with:

```swift
            // Two cats mode: cat 2, beside the big cat (nothing at all in the other modes).
            SecondCatPlacement(state: state, islandW: islandWidth, islandH: islandHeight)
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: islandWidth,
                                      height: state.mode == .expanded ? 320 : islandHeight)
                }
                .opacity(uploadActive || greetingActive ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: uploadActive || greetingActive)

            // Subagents, as kittens beside their parent's cat (nothing at all while no agent has one).
            KittenPlacement(state: state, islandW: islandWidth, islandH: islandHeight)
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: islandWidth,
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
    private var effectiveColor: String { task.color }

    // VS Code pill always shows "VS Code" label regardless of active project name
    private var displayName: String {
```

and replace it with:

```swift
    private var effectiveColor: String { task.color }

    /// How much of the pill's trailing end its kittens take (0 with none).
    private var kittenReserve: CGFloat {
        CGFloat(CatIslandLayout.pillKittenReserve(CatKittens.slots("pill", state.kittenView(task.id)), pillHeight: 28))
    }

    // VS Code pill always shows "VS Code" label regardless of active project name
    private var displayName: String {
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, find this text (it occurs exactly once):

```swift
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity)
```

and replace it with:

```swift
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, kittenReserve > 0 ? 34 : 0)    // with kittens at the trailing end the title keeps clear of them and of the pill's own cat (which ends at 30 pt)
                        .padding(.trailing, kittenReserve)
                        .frame(maxWidth: .infinity, alignment: .center)
                    // The pill's subagents, as up to three small kittens at its trailing end (and "+N").
                    if state.kittens[task.id] != nil {
                        let box = CatIslandLayout.kittenBox("pill")
                        KittenLayerView(state: state, pills: [task.id], parentCat: cat, place: "pill", unit: 28, colour: task.color)
                            .offset(x: CGFloat(box.x1 * 28))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(maxWidth: .infinity)
```

Run: `bash scripts/test-cat-wiring.sh 2>&1 | tail -1`
Expected: `All tests passed.`

- [ ] **Step 4: The sheets, drawn without the app**

`--kittens --scenario NAME` draws the island after each step of a scripted scenario (the same file the tests and the sender use, through the same `CatKittenHooks` and `CatKittens.step`), the compact strip and the overview side by side; `--mode` picks the display mode and `--both` gives Codex's pill the same kittens. `--bench-kittens` adds eight kittens to the frame bench.

**Edit `scripts/render-cats.sh`**, find this text (it occurs exactly once):

```bash
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatIslandLayout.swift \
    scripts/render-cats.swift \
    -o "$BUILD_DIR/render-cats"
```

and replace it with:

```bash
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatKittens.swift $APP/CatKittenHooks.swift $APP/CatKittenDraw.swift \
    $APP/CatIslandLayout.swift \
    scripts/render-cats.swift \
    -o "$BUILD_DIR/render-cats"
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
//   bash scripts/render-cats.sh --stage --cats shrimpy,momo        the big cats on stage panels, like the prototype's Cats section
//   bash scripts/render-cats.sh --states --cats shrimpy            the 11 states, in both motion styles, after 1.2 s in each
//   bash scripts/render-cats.sh --bench                            frame time of twelve small cats plus the big one
//   bash scripts/render-cats.sh --emotes --cats shrimpy,momo       every emote at its peak, in both motion styles
```

and replace it with:

```swift
//   bash scripts/render-cats.sh --stage --cats shrimpy,momo        the big cats on stage panels, like the prototype's Cats section
//   bash scripts/render-cats.sh --states --cats shrimpy            the 11 states, in both motion styles, after 1.2 s in each
//   bash scripts/render-cats.sh --bench-kittens                    the same with eight kittens drawn as well (three under the big cat, two beside it, three at pill ends)
//   bash scripts/render-cats.sh --bench                            frame time of twelve small cats plus the big one
//   bash scripts/render-cats.sh --emotes --cats shrimpy,momo       every emote at its peak, in both motion styles
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
//   bash scripts/render-cats.sh --island --scale 2                 the compact and the expanded island in the three display modes (One cat, A cat for each agent, Two cats), a mock
//                                                                  made of the real cats and the app's own layout numbers (CatIslandLayout) and cast (CatCast)
//   bash scripts/render-cats.sh --eyes --scale 1                   the compact cats' eyes: today's flat ink eyes next to the coloured small eyes, every coat and its kitten at Ø12
//                                                                  to Ø24 (--scale is the device pixel ratio: look at 1 and 2)
```

and replace it with:

```swift
//   bash scripts/render-cats.sh --island --scale 2                 the compact and the expanded island in the three display modes (One cat, A cat for each agent, Two cats), a mock
//                                                                  made of the real cats and the app's own layout numbers (CatIslandLayout) and cast (CatCast)
//   bash scripts/render-cats.sh --kittens --scenario life [--mode one|perAgent|two] [--both] [--steps 2,4,7]
//                                                                  the island after each step of a scripted subagent scenario (tests/fixtures/mac/subagent-scenarios.json), the
//                                                                  compact strip and the overview side by side; --both gives Codex's pill the same kittens
//   bash scripts/render-cats.sh --eyes --scale 1                   the compact cats' eyes: today's flat ink eyes next to the coloured small eyes, every coat and its kitten at Ø12
//                                                                  to Ø24 (--scale is the device pixel ratio: look at 1 and 2)
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case eyes
        case island
    }

```

and replace it with:

```swift
        case eyes
        case island
        case kittens
        case benchKittens
    }

```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        var kittens: [Double] = [16, 40]
        var mode = Mode.ladder
    }

```

and replace it with:

```swift
        var kittens: [Double] = [16, 40]
        var mode = Mode.ladder
        var scenario = "life"
        var display = CatDisplayMode.one
        var both = false
        var steps: [Int]?
    }

```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
            case "--eyes": a.mode = .eyes
            case "--island": a.mode = .island
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

and replace it with:

```swift
            case "--eyes": a.mode = .eyes
            case "--island": a.mode = .island
            case "--kittens": a.mode = .kittens
            case "--bench-kittens": a.mode = .benchKittens
            case "--scenario": a.scenario = it.next() ?? a.scenario
            case "--steps": a.steps = (it.next() ?? "").split(separator: ",").compactMap { Int($0) }
            case "--both": a.both = true
            case "--mode": a.display = CatDisplayMode(rawValue: it.next() ?? "") ?? .one
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case .states: sheet = states(a)
        case .bench: bench(); return
        case .emotes: sheet = emotes(a)
        case .mouths: sheet = mouths(a)
```

and replace it with:

```swift
        case .states: sheet = states(a)
        case .bench: bench(); return
        case .benchKittens: bench(kittens: 8); return
        case .emotes: sheet = emotes(a)
        case .mouths: sheet = mouths(a)
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case .eyes: sheet = eyeSheet(a)
        case .island: sheet = islandSheet(a)
        }
        sheet.write(to: a.out)
```

and replace it with:

```swift
        case .eyes: sheet = eyeSheet(a)
        case .island: sheet = islandSheet(a)
        case .kittens: sheet = kittenSheet(a)
        }
        sheet.write(to: a.out)
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
    static func cpuNow() -> Double { Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9 }

    @MainActor static func bench() {
        let sheet = Sheet(width: 640, height: 220, scale: 2)
        let states = CatState.allCases
```

and replace it with:

```swift
    static func cpuNow() -> Double { Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9 }

    @MainActor static func bench(kittens: Int = 0) {
        let sheet = Sheet(width: 640, height: 220, scale: 2)
        let states = CatState.allCases
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        }
        let big = scene(CatPresets.byID("shrimpy"), profile: "playful", D: 66, state: .working)
        var times: [Double] = []
        for f in 0..<600 {
```

and replace it with:

```swift
        }
        let big = scene(CatPresets.byID("shrimpy"), profile: "playful", D: 66, state: .working)
        // kittens (Ø15, with their state badges), drawn at 30 fps like the small cats: they are small cats too
        let kits = (0..<kittens).map { i -> (CatEngine, Clock, () -> Void, Double) in
            let (e, c, s) = scene(CatPresets.kitten(of: CatPresets.byID(["shrimpy", "momo", "ginger"][i % 3])), profile: "playful", D: 15, seed: UInt32(40 + i), state: [CatState.working, .searching, .approval][i % 3], mini: true)
            return (e, c, s, 30 + Double(i) * 30)
        }
        var times: [Double] = []
        for f in 0..<600 {
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
                CatRenderer.draw(sheet.cg, cats[i].0.look(time: cats[i].1.t / 1000), cx: cats[i].4, cy: 30, D: cats[i].3, CatDrawOptions(badge: true))
            }
            big.step()
            CatRenderer.draw(sheet.cg, big.e.look(time: big.clock.t / 1000), cx: 320, cy: 130, D: 66, CatDrawOptions())
```

and replace it with:

```swift
                CatRenderer.draw(sheet.cg, cats[i].0.look(time: cats[i].1.t / 1000), cx: cats[i].4, cy: 30, D: cats[i].3, CatDrawOptions(badge: true))
            }
            for i in kits.indices where f % 2 == 0 {
                kits[i].2()
                CatRenderer.draw(sheet.cg, kits[i].0.look(time: kits[i].1.t / 1000), cx: kits[i].3, cy: 75, D: 15, CatDrawOptions(badge: true))
            }
            big.step()
            CatRenderer.draw(sheet.cg, big.e.look(time: big.clock.t / 1000), cx: 320, cy: 130, D: 66, CatDrawOptions())
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        times.sort()
        let avg = times.reduce(0, +) / Double(times.count)
        print(String(format: "12 small cats (30 fps) + the big one (60 fps), update and draw, CPU time: avg %.2f ms, p95 %.2f ms, max %.2f ms per frame (%d frames)", avg, times[Int(Double(times.count) * 0.95)], times.last!, times.count))
    }

```

and replace it with:

```swift
        times.sort()
        let avg = times.reduce(0, +) / Double(times.count)
        print(String(format: "12 small cats (30 fps)%@ + the big one (60 fps), update and draw, CPU time: avg %.2f ms, p95 %.2f ms, max %.2f ms per frame (%d frames)", kittens > 0 ? " + \(kittens) kittens (30 fps)" : "", avg, times[Int(Double(times.count) * 0.95)], times.last!, times.count))
    }

```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
    private static func samplePill(_ id: String?) -> CatDisplaySample.Pill? { CatDisplaySample.pills.first { $0.id == id } }

    @MainActor static func drawCompact(_ cg: CGContext, _ cast: CatCast.Result, ox: Double, oy: Double) {
        let W = 345.0, H = 32.0
        cg.fill(CatDraw.roundRect(ox, oy, W, H, 14), CatDraw.black(1))
```

and replace it with:

```swift
    private static func samplePill(_ id: String?) -> CatDisplaySample.Pill? { CatDisplaySample.pills.first { $0.id == id } }

    /// The kittens of a scene, by pill, and the time they are drawn at (ms).
    struct KittenScene {
        var lists: [String: [CatKittens.Kitten]] = [:]
        var now = 0.0
    }

    /// One parent's kittens in one place, settled for 0.75 s on a fake clock and then drawn.
    @MainActor static func drawKittens(_ cg: CGContext, _ list: [CatKittens.Kitten], place: String, parentCat: String, origin: (x: Double, y: Double), unit: Double, colour: String?) {
        let clock = Clock(), herd = CatKittenHerd(), rng = CatRNG(seed: 5), slots = CatKittens.slots(place, list), scratch = Sheet(width: 4, height: 4, scale: 1).cg
        herd.rand = { rng.next() }
        func go(_ into: CGContext) {
            CatKittenDraw.draw(into, slots, parentCat: parentCat, origin: origin, unit: unit, colour: colour, dpr: 2, herd: herd, now: { clock.t }) { e in e.update(dt: 1.0 / 60) }
        }
        for _ in 0..<45 { clock.t += 1000.0 / 60; go(scratch) }
        go(cg)
    }

    @MainActor static func drawKittenLayers(_ cg: CGContext, _ cast: CatCast.Result, expanded: Bool, big: (x: Double, y: Double, d: Double), second: (x: Double, y: Double, d: Double)?, ox: Double, oy: Double, kit: KittenScene) {
        for parent in CatIslandLayout.kittenParents(cast.mode, expanded: expanded, big: big, second: second) {
            let spot = parent.cat == 0 ? cast.big : cast.second
            let pills = parent.countsBoth ? [cast.big.pill, cast.second?.pill].compactMap { $0 } : [spot?.pill].compactMap { $0 }
            let list = pills.flatMap { CatKittens.view(kit.lists[$0] ?? [], now: kit.now) }
            guard !list.isEmpty, let spot else { continue }
            drawKittens(cg, list, place: parent.place, parentCat: spot.cat, origin: (ox + parent.x, oy + parent.y), unit: parent.unit, colour: parent.countsBoth ? nil : samplePill(spot.pill)?.color)
        }
    }

    @MainActor static func drawCompact(_ cg: CGContext, _ cast: CatCast.Result, ox: Double, oy: Double, kit: KittenScene = KittenScene()) {
        let W = 345.0, H = 32.0
        cg.fill(CatDraw.roundRect(ox, oy, W, H, 14), CatDraw.black(1))
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
            drawIslandCat(cg, p.cat, sp?.state ?? .idle, colour: sp?.color, big: false, cx: ox + W - 40 + (i % 2 == 1 ? 8 : -8), cy: oy + H / 2 + (i < 2 ? -8 : 8), d: 12, seed: UInt32(10 + i))
        }
    }

    @MainActor static func drawExpanded(_ cg: CGContext, _ cast: CatCast.Result, ox: Double, oy: Double) {
        let W = 640.0, H = 160.0, two = cast.second != nil
        cg.fill(CatDraw.roundRect(ox, oy, W, H, 22), CatDraw.black(1))
```

and replace it with:

```swift
            drawIslandCat(cg, p.cat, sp?.state ?? .idle, colour: sp?.color, big: false, cx: ox + W - 40 + (i % 2 == 1 ? 8 : -8), cy: oy + H / 2 + (i < 2 ? -8 : 8), d: 12, seed: UInt32(10 + i))
        }
        let ys = oy - oy + H / 2
        drawKittenLayers(cg, cast, expanded: false, big: (xs[0], ys, 20), second: xs.count > 1 ? (xs[1], ys, 20) : nil, ox: ox, oy: oy, kit: kit)
    }

    @MainActor static func drawExpanded(_ cg: CGContext, _ cast: CatCast.Result, ox: Double, oy: Double, kit: KittenScene = KittenScene()) {
        let W = 640.0, H = 160.0, two = cast.second != nil
        cg.fill(CatDraw.roundRect(ox, oy, W, H, 22), CatDraw.black(1))
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
            cg.fill(CatDraw.roundRect(x, y, 134, 28, 14), CatDraw.rgb([14, 15, 17]))
            drawIslandCat(cg, p.cat, sp?.state ?? .idle, colour: sp?.color, big: false, cx: x + 8 + 11, cy: y + 14, d: 22, seed: UInt32(20 + i))
            CatDraw.text(cg, sp?.name ?? p.pill, x: x + 67, y: y + 14, size: 10, bold: true, color: CatDraw.rgb([107, 112, 121]))
        }
    }

```

and replace it with:

```swift
            cg.fill(CatDraw.roundRect(x, y, 134, 28, 14), CatDraw.rgb([14, 15, 17]))
            drawIslandCat(cg, p.cat, sp?.state ?? .idle, colour: sp?.color, big: false, cx: x + 8 + 11, cy: y + 14, d: 22, seed: UInt32(20 + i))
            let list = CatKittens.view(kit.lists[p.pill] ?? [], now: kit.now), slots = CatKittens.slots("pill", list)
            let reserve = CatIslandLayout.pillKittenReserve(slots, pillHeight: 28)
            // with kittens the title keeps clear of them and of the pill's own cat (its right edge is at 30 pt: the title starts 34 pt in), and is cut at the end when it does not fit (6 pt a letter)
            let full = sp?.name ?? p.pill, room = reserve > 0 ? 134 - 34 - reserve : 134, fit = max(1, Int(room / 6.2)), shown = reserve > 0 && full.count > fit ? String(full.prefix(max(1, fit - 1))) + "…" : full
            CatDraw.text(cg, shown, x: reserve > 0 ? x + 34 + room / 2 : x + 67, y: y + 14, size: 10, bold: true, color: CatDraw.rgb([107, 112, 121]))
            if !list.isEmpty { drawKittens(cg, list, place: "pill", parentCat: p.cat, origin: (x + 134, y + 14), unit: 28, colour: sp?.color) }
        }
        let pairAt = CatIslandLayout.pairExpanded(botX: 68, botD: 58, cy: cy)
        drawKittenLayers(cg, cast, expanded: true, big: (cast.second != nil ? pairAt.cat1X : 68, cy, 58), second: cast.second != nil ? (pairAt.cat2X, pairAt.cat2Y, pairAt.cat2D) : nil, ox: ox, oy: oy, kit: kit)
    }

    /// The island after each step of a scripted subagent scenario: the compact strip and the overview, in the chosen mode (default One cat), with the step's words.
    @MainActor static func kittenSheet(_ a: Args) -> Sheet {
        let data = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "tests/fixtures/mac/subagent-scenarios.json"))) as! [String: Any]
        let common = data["common"] as! [String: Any], scenario = (data["scenarios"] as! [String: Any])[a.scenario] as! [String: Any]
        let steps = scenario["steps"] as! [[String: Any]]
        let pick = a.steps ?? Array(1...steps.count)
        let rowH = 176.0, left = 400.0, cw = 345.0, ew = 640.0, gap = 24.0
        func short(_ s: String) -> String { s.count > 62 ? String(s.prefix(60)) + "…" : s }
        let sheet = Sheet(width: left + cw + gap + ew + 16, height: rowH * Double(pick.count) + 28, scale: a.scale)
        let cg = sheet.cg
        CatDraw.text(cg, "\(a.scenario): \(scenario["about"] as! String)", x: 14, y: 14, size: 11, bold: true, color: CatDraw.white(0.9), anchor: .left)
        let display = CatDisplaySettings(mode: a.display, pair: CatDisplaySettings.defaultPair, agentCats: [:])
        let cast = CatDisplaySample.cast(display, main: "shrimpy")
        var list: [CatKittens.Kitten] = []
        for (n, step) in steps.enumerated() {
            let at = (step["at"] as! NSNumber).doubleValue
            if let sent = step["event"] as? [String: Any] {
                let payload = common.merging(sent) { _, s in s }, name = payload["hook_event_name"] as? String ?? ""
                let ev = name == "PermissionRequest" ? CatKittenHooks.permission(payload: payload, now: at) : CatKittenHooks.event(name: name, payload: payload, now: at)
                if let ev { list = CatKittens.step(list, ev) }
            } else if let inner = step["internal"] as? [String: Any] {
                switch inner["type"] as? String {
                case "resolved": list = CatKittens.step(list, CatKittenHooks.resolved(subagentId: inner["id"] as! String, now: at))
                case "sweep": list = CatKittens.step(list, .sweep(t: at))
                default: list = CatKittens.step(list, .tick(t: at))
                }
            }
            guard let row = pick.firstIndex(of: n + 1) else { continue }
            let top = 28 + Double(row) * rowH
            var kit = KittenScene(lists: ["integration_claude": list], now: at + 300)
            if a.both { kit.lists["agent_codex"] = list }
            CatDraw.text(cg, short("\(n + 1). \(step["say"] as! String)"), x: 14, y: top + 14, size: 10.5, bold: false, color: CatDraw.white(0.8), anchor: .left)
            CatDraw.text(cg, list.map { "\($0.id): \($0.state.rawValue)" }.joined(separator: ", "), x: 14, y: top + 32, size: 9.5, bold: false, color: CatDraw.white(0.5), anchor: .left)
            drawCompact(cg, cast, ox: left, oy: top + 10, kit: kit)
            drawExpanded(cg, cast, ox: left + cw + gap, oy: top, kit: kit)
        }
        return sheet
    }

```

Run: `mkdir -p "${TMPDIR:-/tmp}/b-mac-2" && bash scripts/render-cats.sh --kittens --scenario life --steps 2,4,7,9,11 --scale 2 --out "${TMPDIR:-/tmp}/b-mac-2/life-one.png"`
Expected: `wrote …/b-mac-2/life-one.png`. Look at it: five rows of the life of two subagents in One cat mode. Step 2: one kitten tucked beside the big cat in the compact strip and under it in the overview. Step 4: two (the first with a search badge). Step 7: the second one with an amber approval dot. Step 9: the first one waving (a happy blink) beside a working one. Step 11: no kitten at all (the parent stopped, and the second one's stop never came).

Run: `bash scripts/render-cats.sh --kittens --scenario crowd --steps 3,5,10 --both --scale 2 --out "${TMPDIR:-/tmp}/b-mac-2/crowd-one.png"`
Expected: `wrote …/b-mac-2/crowd-one.png`. Look at it: with 2, 4 and 8 kittens: at most two beside the big cat in the compact strip with a "+N", at most three under it in the overview with a "+N", and in the Codex pill up to three small kittens at the trailing end (and a "+N") with the pill's title cut to keep clear of them.

Run: `bash scripts/render-cats.sh --kittens --scenario life --steps 4,7,9 --mode two --both --scale 2 --out "${TMPDIR:-/tmp}/b-mac-2/life-two.png"`
Expected: `wrote …/b-mac-2/life-two.png`. Look at it: Two cats mode: in the compact strip a count "×4" by the second cat (both cats' kittens), and in the overview each cat's kittens in a row under it.

Run: `RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench 2>&1 | tail -1; RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench-kittens 2>&1 | tail -1`
Expected: two lines. The first is the frame bench again (avg about 1.8 to 2.0 ms: it moves by 0.1 ms with the machine's other work, so read it twice if it is above 2.0); the second reads `12 small cats (30 fps) + 8 kittens (30 fps) + the big one (60 fps), update and draw, CPU time: avg 2.4 to 2.5 ms, …` (the dry run read 2.35 to 2.50 ms: about 0.07 ms for each kitten, on a 16.7 ms frame; Open question 9).

- [ ] **Step 5: Build the app's two targets**

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `Created project at …` and `** BUILD SUCCEEDED **`.

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add NotchBuddy/Sources/App/CatKittenDraw.swift NotchBuddy/Sources/App/KittenViews.swift NotchBuddy/Sources/App/CatKittens.swift NotchBuddy/Sources/App/CatIslandLayout.swift NotchBuddy/Sources/App/IslandRootView.swift NotchBuddy/Sources/App/IslandViewContent.swift tests/CatKittensTests.swift tests/CatAgentListTests.swift tests/CatWiringTests.swift scripts/test-cat-agent-list.sh scripts/render-cats.sh scripts/render-cats.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): kittens beside their parent, wherever it is drawn

A subagent is its parent's cat as a kitten with its own engine and state badge, the parent's collar in the agent's colour, and a happy blink while it leaves. Up to
three under the big cat in the overview and two beside it in the compact island (with a +N), a count by the pair in the compact island, each cat's under it in
the pair's overview, and up to three at an agent pill's trailing end. render-cats.sh --kittens draws the scripted scenarios without the app, --bench-kittens measures
them.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 15: Owner checkpoint 2: the modes and the kittens

No code and no commit. The session reports; the main session sends the owner the images next to the prototype page (B-0's) and the Windows twin's, and asks the questions below.

- [ ] **Step 1: Collect the images**

Run: `mkdir -p .claude/checkpoints/b-mac-2 && cp "${TMPDIR:-/tmp}/b-mac-2/island.png" "${TMPDIR:-/tmp}/b-mac-2/life-one.png" "${TMPDIR:-/tmp}/b-mac-2/crowd-one.png" "${TMPDIR:-/tmp}/b-mac-2/life-two.png" .claude/checkpoints/b-mac-2/ && ls .claude/checkpoints/b-mac-2`
Expected: `crowd-one.png`, `island.png`, `life-one.png` and `life-two.png`.

- [ ] **Step 2: What the owner looks at**

1. **The three modes** (`island.png`): One cat looks as it ships (the eyes aside); A cat for each agent shows a different cat for each agent in the grid and the row; Two cats has two Ø20 cats in the left ear and cat 1 at Ø58 beside cat 2 at Ø46 in the overview, with a 6 pt gap between the two heads (B-0's checkpoint moved cat 2 from 99 to 108 pt). Judge the room: the badge of cat 1 on its left (it sits close to the island's left edge), the text starting further right and the second line fitting in the card's 84 pt, the second amber line.
2. **The kittens** (`life-one.png`, `crowd-one.png`, `life-two.png`): the kitten's size and place beside and under the big cat, the waving blink, the approval dot, "+N" and "×N"; at the pills' trailing end the title is cut to keep clear: is that acceptable for a pill with three kittens?
3. **The numbers:** with eight kittens drawn the frame bench reads about 2.4 ms against 1.8 without (Open question 9).
4. **The notch Mac:** in the compact island the pair's "×N" sits at 76 pt from the island's left edge, and the ear is 80 pt wide: part of a long count may sit under the camera housing. The numbers are in `CatKittens.places` (a contract number: `pairCompact`) and `CatIslandLayout.compactX`.

The owner's real-build checks are listed in Task 17; this one is about the look.

---

### Task 16: Docs, CI and the final checks

**Agent:** `nm-implementer-light`. Everything is given in full: the docs, one CI step for each new script, and the checks.

**Files:**
- Modify: `CLAUDE.md`, `ARCHITECT.md`, `docs/INTEGRATIONS.md` (in French), `README.md`, `.github/workflows/build.yml`

**Interfaces:**
- Consumes: Tasks 1 to 14.
- Produces: the repository's own account of the Mac side of sub-project B, and CI that runs its eight new test programs.

- [ ] **Step 1: The two agent guides**

**Edit `CLAUDE.md`**, find this text (it occurs exactly once):

```markdown
- `docs/superpowers/specs/` — the NotchMeow design spec: decisions, sub-projects, identity values.
```

and replace it with:

```markdown
- Sub-project B on the Mac: `CatSmallEye.swift` (the coloured small eyes, drawn in `CatFace.drawEyes`: the black coats' Midnight, Oreo and Mocha are flat, rimless and glowing, picked by the coat's ID; `CatLook.inkEyes` keeps the old ink ones for the contact sheet and the icons), `CatDisplay.swift` (the display mode, the pair and the agents' coats: the keys `cat.displayMode`, `cat.pair` and `cat.agentCat.<pillId>`), `CatAgentCats.swift` (a new agent's cat), `CatCast.swift` (which cat appears where: `AppState.cast`), `CatIslandLayout.swift` (every layout number of Two cats mode and the kitten boxes), `PairCatViews.swift` (cat 2), `CatKittens.swift` (the kittens' rules), `CatKittenHooks.swift` (the hooks' words: `SubagentStart` and the events that carry an `agent_id`), `CatKittenDraw.swift` and `KittenViews.swift` (drawing them), and `CatDisplayPreview.swift` and `CatAgentList.swift` (Settings → Cat → Display). **Each cat view takes its coat as a parameter from `AppState.cast`; nothing reads the Main cat on its own, and a kitten is never given `useCharacter`.** The tests are `scripts/test-cat-{small-eye,display,agent-cats,cast,agent-list,kittens,kitten-hooks,wiring}.sh` (`test-cat-wiring.sh` pins where the app files that no test program can compile call the pure parts); `render-cats.sh --eyes`, `--island` and `--kittens` and `render-cat-settings.sh --mode …` draw the checkpoint images without the app; `scripts/fake-subagent-events.py` sends scripted subagent events to a running build and is only for the owner's check.
- `docs/superpowers/specs/` — the NotchMeow design spec: decisions, sub-projects, identity values.
```

**Edit `ARCHITECT.md`**, find this text (it occurs exactly once):

```markdown
see `docs/CAT-CONTRACT.md`, "Display modes, agent coats, kittens and small eyes".
```

and replace it with:

```markdown
see `docs/CAT-CONTRACT.md`, "Display modes, agent coats, kittens and small eyes". **On the Mac** it is built: Settings → Cat → Display (`CatSettingsView`, `CatDisplayPreview`) picks One cat, A cat for each agent or Two cats and is stored by `CatDisplaySettings` (`cat.displayMode`, `cat.pair`, `cat.agentCat.<pillId>`); a new agent pill gets its coat when `HookServer` or `AppState` creates it (`CatAgentCats`, through `CatSettingsStore`); `AppState.cast` (`CatCast`) hands every cat view its coat; Two cats adds `PairCatViews.swift` and the numbers of `CatIslandLayout`; and `HookServer.processEvent` and `processPermissionRequest` turn `SubagentStart` and the tool and permission events that carry an `agent_id` into kittens (`CatKittenHooks`, `CatKittens`, drawn by `CatKittenDraw`), swept by the cat's sleep timer, in both builds.
```

- [ ] **Step 2: The subagent kittens in `docs/INTEGRATIONS.md` (French) and the roadmap**

**Edit `docs/INTEGRATIONS.md`**, find this text (it occurs exactly once):

```markdown
| `SubagentStart` / `SubagentStop` | afficher « + sous-agent » dans le défilé |
```

and replace it with:

```markdown
| `SubagentStart` | afficher « + sous-agent » dans le défilé, et un chaton à côté du chat de l'agent (voir « Sous-agents : les chatons ») |
| `SubagentStop` | afficher « • sous-agent terminé » dans le défilé ; le chaton part (voir plus bas) |
```

**Edit `docs/INTEGRATIONS.md`**, find this text (it occurs exactly once):

```markdown
## 1bis. Jauge de forfait Claude (statusLine)
```

and replace it with:

```markdown
### Sous-agents : les chatons

Un sous-agent de Claude Code (ou de Codex, sur Mac) est un **chaton** du chat de son agent : il apparaît à côté de ce chat, montre son propre état, et part avec un clin d'œil content. Rien à installer : ce sont les hooks déjà branchés, et `nm-hook` transmet la charge utile telle quelle (`agent_id`, `agent_type`, `session_id`).

| Hook | Effet sur les chatons |
|---|---|
| `SubagentStart` | un chaton, en train de travailler, sur la pastille de l'agent parent |
| `PreToolUse` / `PostToolUse` **avec** `agent_id` | état du chaton : `searching` pour un outil de recherche (`tests/fixtures/cat/search-tools.json`), `working` pour les autres ; **sans** `agent_id` l'événement est celui du parent et aucun chaton ne change |
| `PermissionRequest` **avec** `agent_id` | le chaton attend l'approbation (la carte reste celle du parent, comme avant) ; il se remet au travail quand la carte est traitée, fermée ou remplacée |
| `SubagentStop` | un clin d'œil content (0,6 s), puis le chaton disparaît |
| `Stop`, `StopFailure`, `SessionEnd`, `Interrupt` du parent | les chatons de la session disparaissent (ceux d'une autre session de la même pastille restent) |
| le minuteur de sommeil du chat (10 minutes) | balaie les chatons dont la dernière activité date de 10 minutes ou plus : un arrêt qui n'est jamais venu |

- Au plus 8 chatons par agent (le plus ancien part le premier) ; aucun n'est enregistré. Un chaton est le chat de son parent en chaton (même pelage, même collier à la couleur de l'agent). Placement : jusqu'à 3 sous le grand chat (étendu), 2 à côté (compact), un compteur « ×N » à côté de la paire (compact, mode Deux chats), jusqu'à 3 au bout d'une pastille d'agent, puis « +N ».
- Si une version de Claude Code n'envoie pas `agent_id` sur les événements d'outils, les chatons apparaissent quand même au démarrage et partent à l'arrêt, en train de travailler : c'est un chemin prévu, pas une panne. Que les événements d'outils d'un sous-agent portent `agent_id` vient de la documentation de Claude Code, pas d'une session enregistrée : à vérifier avec un vrai agent.
- Gemini CLI et Antigravity n'envoient aucun événement de sous-agent : pas de chaton. Codex n'a pas encore de hooks sous Windows et Linux.
- Les mêmes hooks existent dans la version App Store (Claude Code seulement) : les chatons y sont aussi.
- Vérifier sans agent : `python3 scripts/fake-subagent-events.py --scenario life` envoie des événements scriptés à l'app qui tourne (réservé à la vérification du propriétaire, sur une version Debug) ; les tests, eux, les envoient à une socket qui leur est propre (`scripts/test-cat-kitten-hooks.sh`).

## 1bis. Jauge de forfait Claude (statusLine)
```

**Edit `README.md`**, find this text (it occurs exactly once; if the Windows and Linux plan changed this row first, set its status to `in progress` and keep its other words):

```markdown
| B | One cat per agent, a single chosen cat, or both together, plus kittens for Claude Code subagents | planned |
```

and replace it with:

```markdown
| B | One cat per agent, a single chosen cat, or two together, plus kittens for Claude Code subagents and coloured small eyes | in progress (macOS built, Windows and Linux next) |
```

- [ ] **Step 3: One CI step for each new script**

**Edit `.github/workflows/build.yml`**, find this text (it occurs exactly once):

```yaml
      - name: Cat sleep timer
        run: bash scripts/test-cat-sleep.sh
```

and replace it with:

```yaml
      - name: Cat sleep timer
        run: bash scripts/test-cat-sleep.sh

      - name: Cat small eyes (the coloured eyes of the compact detail level)
        run: bash scripts/test-cat-small-eye.sh

      - name: Cat display settings (mode, pair, agents' coats)
        run: bash scripts/test-cat-display.sh

      - name: Cat agent coats (a new agent's cat, the dice, Reset to defaults)
        run: bash scripts/test-cat-agent-cats.sh

      - name: Cat cast (which cat appears where)
        run: bash scripts/test-cat-cast.sh

      - name: Cat agent list and island layout
        run: bash scripts/test-cat-agent-list.sh

      - name: Cat kittens (the reducer, the order, the slots)
        run: bash scripts/test-cat-kittens.sh

      - name: Cat kitten hooks (scripted subagent events through a test socket)
        run: bash scripts/test-cat-kitten-hooks.sh

      - name: Cat wiring (source pins of the app files)
        run: bash scripts/test-cat-wiring.sh
```

- [ ] **Step 4: The final checks**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|fixture files match|identical bytes"; node scripts/check-fixtures-additive.mjs 6c14947 2>&1 | tail -1`
Expected: `# tests 231`, `# pass 231`, `# fail 0`, `✓ 14 fixture files match cat-core.js`, `✓ two generator runs write identical bytes`, then `✓ fixtures changed only by addition since 6c14947`.

Run: `for f in scripts/test-cat-*.sh; do printf '%-42s' "$f"; bash "$f" 2>&1 | tail -1; done`
Expected: twenty-five lines: the contract's ends `✓ two generator runs write identical bytes` and the other twenty-four (`agent-cats`, `agent-list`, `cast`, `devpanel`, `display`, `effects`, `engine`, `frame-meter`, `fur`, `geometry`, `greeting`, `kitten-hooks`, `kittens`, `personality`, `presets`, `renderer`, `rules`, `settings-store`, `settings`, `sleep`, `small-eye`, `theme`, `upload`, `wiring`) end `All tests passed.`

Run: `bash scripts/check-no-leftovers.sh 2>&1 | grep -c "✓"`
Expected: `5`.

Run: `d="${TMPDIR:-/tmp}/b-mac-icons"; bash scripts/gen-icons.sh "$d" | tail -1 | cut -c1-30; n=0; for f in $(cd "$d" && find . -type f | sort); do cmp -s "$d/$f" "$f" || n=$((n+1)); done; echo "$n icon files differ"`
Expected: `wrote the 18 icon files under`, then `0 icon files differ`.

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath NotchBuddy/build/release build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3`
Expected: `Created project at …` and `** BUILD SUCCEEDED **`.

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3; xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **` twice.

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/release/Build/Products/Release/NotchMeow.app release 2>&1 | tail -2; bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Debug/NotchMeow.app debug 2>&1 | tail -2; bash scripts/check-app-binary.sh NotchBuddy/build/store/Build/Products/Debug/NotchMeow.app appstore 2>&1 | tail -2`
Expected: six lines. Release: `✓ FoundationModels is weak-linked` and `✓ No AI base-URL override in this Release build`. Debug: `✓ The cat panel, the Claude Code engine and its override are in this Debug build` and `✓ FoundationModels is weak-linked`. App Store: `✓ No cat panel and no Claude Code engine in this build` and `✓ FoundationModels is weak-linked`.

Run: `RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench 2>&1 | tail -1; RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench-kittens 2>&1 | tail -1`
Expected: two lines. The frame bench about 1.8 to 2.0 ms on average (the budget is 2 ms; the dry runs read between 1.83 and 2.10 on a machine that was also busy, so run it again on a quiet machine if it reads above 2.0), and with eight kittens about 2.4 to 2.5 ms.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md ARCHITECT.md docs/INTEGRATIONS.md README.md .github/workflows/build.yml
git commit -m "docs(cat): sub-project B on the Mac

CLAUDE.md and ARCHITECT.md say where the display modes, the cast, the layout and the kittens live; docs/INTEGRATIONS.md (French) describes the subagent kittens
and how to try them; the README's roadmap row for B is in progress; CI runs the eight new test programs.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

**After Task 16**, the session dispatches `nm-reviewer-deep` over the whole branch (`git diff notchmeow/rebrand...HEAD`), with the Review Focus, the Global Constraints and these cross-task contracts to check: every name in the interface tables above is the one the later tasks use; no cat view reads the Main cat on its own; no kitten call is inside an `#if`; the stored values never skip the clean-up; nothing in the plan launched an app or wrote to `UserDefaults.standard`. Fix what it finds, re-run the checks above, and report.

---

### Task 17: Owner checkpoint 3: the final report and the manual checks

No code and no commit. The session reports; the main session sends the owner the images of `.claude/checkpoints/b-mac-2/` and, if they changed, `b-mac-1/`, next to the prototype page and the Windows twin's, and asks the owner to run the Debug build (`NotchBuddy/build/Build/Products/Debug/NotchMeow.app`; quit the installed app first) and check, on a notch Mac and, if there is one, a Mac without a notch:

1. **Settings → Cat → Display.** The picker has three modes and the preview animates while Settings is key and stops when it is closed or another app is key (Activity Monitor shows no CPU for a closed Settings window); the pair pickers appear in Two cats mode only and the agents' list in A cat for each agent mode only; picking a coat, the dice and Reset to defaults work; quit and relaunch: every choice is still there (`defaults read io.github.aikusan.notchmeow cat.displayMode`, `cat.pair` and `cat.agentCat.agent_gemini`). A hand-edited bad value (`defaults write io.github.aikusan.notchmeow cat.pair '["momo",'`, `cat.displayMode -int 3`) opens Settings on Shrimpy and Momo, One cat.
2. **A cat for each agent.** Claude Code is Shrimpy and Codex is Momo; a Gemini CLI event (`nm_agent` through the socket) gets a coat of its own on its first event and keeps it after a restart; a hairball, a hover and a poke are the big cat's as before; the greeting's four session cats are the agents' cats and hand over to the grid without a change.
3. **Two cats.** Cat 1 shows the focused agent, cat 2 the busiest other one (an approval first), and both sleep together; tapping cat 2 brings its agent into focus; the second agent has left the pills and the grid; the overview shows the two heads with a 6 pt gap between them, and the greeting settles cat 1 at 30 pt and cat 2 pops in beside it (Open question 4).
4. **Kittens, with a real agent.** In Claude Code run a task that starts subagents (a `Task` tool call): a kitten appears beside the cat at `SubagentStart`, shows searching, working and approval, and leaves with a happy blink at `SubagentStop`; the parent's cat behaves as before; at the parent's `Stop` any kitten left goes. **This confirms the Risk of the spec** (tool events inside a subagent carry `agent_id`): if they do not, kittens still appear and leave but stay in the working pose (the planned fallback).
5. **Kittens, without one.** `python3 scripts/fake-subagent-events.py --scenario life` (then `fallback`, `lost-stop`, `crowd`, `two-sessions`) shows the same on the Debug build; answer the approval card when it comes.
6. **The pills.** A pill with kittens draws up to three at its trailing end and keeps its title clear of them.
7. **One cat unchanged.** With One cat the island, the overview, the pills and the greeting look as before, except the coloured small eyes.
8. **The App Store build** has kittens for Claude Code; **a Release build** has no "Cats (Debug)…" item.
9. **CPU** with the island hidden and Settings closed: 0 %; the frame readout (`tail -f ~/Library/Logs/NotchMeow/cat-frames.log`) under 2 ms with the usual cats.

Record the owner's answers in the PR description. The open numbers are the pair's "×N" label beside the camera housing (Open question 7), the kittens' frame cost (Open question 9) and the pill titles cut by three kittens (Open question 8).

## Parity with Windows/Linux

**macOS is the primary platform: it gets at least what Windows and Linux gets.** The two plans build the same stages in the same order from the same contract (`cat-core.js` and B-0's five fixtures), and the main session reads them together. This section was first written against B-0's "Interface for the app plans", then **checked line by line against the finished Windows twin** (`docs/superpowers/plans/2026-10-08-b-tauri-display-kittens.md`, 14 tasks, whose own "Parity with macOS" was checked against this plan), and then updated for B-0's merge (`e00ad3d`) and the owner's answers ("The owner's answers (2026-10-08)" below): **the Windows plan moves** on the bright eyes, the pair's gap, the ticker's word and the sweep. Where they agree the table says so; the paragraphs after it list every place they differ and which side moves.

| Topic | macOS (this plan) | Windows and Linux (the twin) |
|---|---|---|
| Small eyes | `CatSmallEye` replays all 265 rows plus a real NaN, the floors, the black coats' own checks and a brute-force pupil test; **the black coats (Midnight, Oreo, Mocha, kittens too) glow**: a flat lighter iris, no rim, a 0.12 pupil, picked by the coat's ID (`smallEye`'s new `cat` input, B-0's checkpoint); drawn in the compact branch of `CatFace.drawEyes`; sheets at 1× and 2× (`render-cats.sh --eyes`); the frame bench before and after (1.70 and 1.82 ms). **The icons keep ink eyes** (`CatLook.inkEyes`: a pixel-identity check of the 18 icon files; without it six differ). | `smalleye.ts` and the compact branch of `renderer.ts` (`DrawOptions.eyes: "ink"` keeps the old pills for the sheet and the bench); a `?dev` Small eyes panel; bench 0.48 and 0.52 ms in headless Chromium. The Windows icon files are drawn with the Mac renderer (`gen-icons.sh`), so the identity check here covers them. **The Windows plan takes the same bright-eye rule** (the `cat` input and a flat, rimless iris in `smallEyeDraw`). |
| The display clean-up | `CatDisplaySettings` (`CatDisplay.swift`), replaying `display-cases.json`; the UserDefaults keys `cat.displayMode`, `cat.pair` (strict JSON text) and `cat.agentCat.<pillId>`; the store lists its keys. | `display.ts` and `clean_display_settings` / `clean_cat_block` in `cat_settings.rs`, carried through `settings.rs`'s `sanitized` (the three keys sit in the `cat` block, so a save must keep them: its Review Focus 1). |
| Settings → Cat → Display | The Display picker with a live picture of the compact notch (the sample island drawn with the real renderer), "Your two cats", "Cats for your agents" (colour, live preview wearing the agent's collar, picker, dice, Reset to defaults), "Character" renamed "Main cat". Previews are paused unless Settings is on screen **and the key window**. | The same rows in `settings/display.ts` and `settings/cat.ts`; previews stop when Settings is unfocused. |
| An agent's coat | `CatAgentCats` (`agentCatFor`, the dice, `assignAgentCats`) with `Double.random` in the app and the contract's seeded source in the tests; a new agent gets its coat in the five places a pill is created and once at launch. | `agentcat.ts`; `agentCatFor` in `upsertExternalAgent` and once at load, with `Math.random`. |
| Every cat view takes its coat | `AppState.cast`; `BotCanvasView(cat:)`, `MiniBotCanvasView(cat:)`, the greeting's `sessions:`, `UploadCanvasView(cat:)`, the ghost; **one source pin for each call site and a guard that no file re-reads the Main cat**; `useCharacter` ignores a kitten. | `BotEngine.setCoat` and a collar style looked up per coat (`catCfg.collars`: the Mac already did); the canvases of `island/island.ts`, `cat/greeting.ts`, `cat/minibots.ts` and `upload/canvas.ts` take the cat from `State.cast`; `sites.test.mjs` pins each site. |
| The pill's last event | `AppState.pillLastEvent`, touched by `HookServer` on every event, permission request and question. | A last-event time per pill in `State` (its Task 8). |
| Two cats | Compact: Ø20 at 30 and 54 pt. Overview: Ø58 and Ø46 side by side (50 and 108 pt, 8 lower, **a 6 pt gap between the heads**), the text 34 pt further right with a second line, tap to focus (`PairCatViews.swift`, `CatIslandLayout`); the second agent leaves the row and the grid; the greeting settles cat 1 at 30 pt and pops cat 2 in beside it. One cat and A cat for each agent are pinned as they ship. | The same numbers from its own single-cat positions (`PAIR.expanded` **56 and 114 once it moves** from 105, `dy` -3 and +5: 58 apart, 8 lower, as here: 50 and 108); the greeting settles cat 1 10 px left, at 30, as here; a click on cat 2 focuses its agent in the overview only, as here. |
| Kittens | `CatKittens` replays all 105 events of the 21 scripts, plus a time that is not finite and a 4000-event fuzz; `HookServer` turns `SubagentStart`, the tool and permission events that carry an `agent_id`, `SubagentStop`, the parent's Stop, StopFailure, SessionEnd and Interrupt, and the sleep timer's sweep into events, **in both builds**; a subagent's approval is remembered and resolved (answered, dismissed by the card's own resolving event or the 115-second timeout, or displaced); a subagent's own Stop ends nothing. | `kittens.ts`, `island/subagents.ts` (`kittenEventOf`) and `island/hooks.ts`; the same rules (StopFailure ends them, a subagent's own Stop does not, `ApprovalInfo.agentId` resolved by Allow, Deny and the 108-second timeout); **no Codex kittens: Codex has no hooks there**. |
| Drawing them | One function (`CatKittenDraw`) for the app's layers and the sheets: Ø15 under a Ø58 cat, Ø12 beside a Ø20 cat, Ø15 in a 28-high pill, "+N" and "×N", the parent's collar, a happy blink while leaving. Compact island and overview only. | `kittendraw.ts` and an overlay canvas, from `kittenSlots`: the same places, the same two views. |
| Checking it | Images without the app (`render-cats.sh --eyes`, `--island`, `--kittens`, `render-cat-settings.sh --mode`), source pins for the app files, the scripted events through a socket of the test's own (`test-cat-kitten-hooks.sh`) and, for the owner, `fake-subagent-events.py` against a Debug build. | The `?dev` page, `/?display=<mode>` and a dev-only `window.__nm.hook(...)` that feeds the real hook handler in a headless browser; a zero-frame check of the hidden island. |
| Frame time | `--bench` before and after the eyes (about 0.12 ms more: 1.70 and 1.82 ms on a quiet machine) and `--bench-kittens` (about 2.4 ms with eight kittens). | The `?dev` readout (0.52 ms and 1.58 ms with eight kittens, a different machine and a software canvas: only comparable with itself). |
| Owner checkpoints | Three: after the eyes and Settings, after the modes and kittens, and a final one. | Three, with the pictures drawn from the Vite dev server. |

**Where the two plans differ, and which side moves** (all small; none blocks either plan):

1. **One word of the ticker's second line: settled, Windows moves.** Both use the same table ("Codex · waiting for you", "hit an error", "rate limited", "asleep", "No other agent") except the question: here **"has a question"**, which is the prototype's own `STATE_TXT`; the twin had **"asking you"**. The owner chose "has a question" on both, so the Windows plan moves (one string in `views.ts` and its test). Open question 17.
2. **When the sweep runs.** Here the cat's one-shot sleep timer is armed only for an idle cat (`CatRules.sleepDelay`), so the sweep runs when the cat falls asleep: ten quiet minutes with nothing happening and nothing waiting. A kitten whose stop never came under a parent that is still working is removed by the parent's `Stop` or its session's end, not by the timer. The twin also ran its sweep when the timer fires under a working cat. Making the Mac's timer fire for a working cat would change `CatRules` and `sequence-cases.json` (the sleep contract), which this plan does not touch. **Settled: the sweep runs when the cat falls asleep, as here, and the Windows plan moves to match.** Open question 16.
3. **The order of "Cats for your agents".** Here most recent first (then the island's order, then the stored-only agents); on Windows and Linux a fixed order (Claude Code, then the others by ID), because that Settings window is a separate webview that cannot see the island's pills (its Open question 1). *Platform difference, on purpose.*
4. **A pin that the relay passes `agent_id` through.** The twin tests that its relay keeps `agent_id` and `agent_type`; this plan now has the same safeguard as a source pin in Task 13 (both Python relays in `HookServer.swift` send `json.dumps(payload)` and remove no field).
5. **Docs, CI and the roadmap.** Only this plan edits the root `README.md`'s roadmap row, `docs/INTEGRATIONS.md` and `.github/workflows/build.yml` (eight new CI steps); the Windows plan edits `windows/README.md` and, in `CLAUDE.md` and `ARCHITECT.md`, other lines than this plan does (it appends to the Windows bullet and the Windows sentence; this plan adds a bullet before the `docs/superpowers/specs/` line and extends the `docs/CAT-CONTRACT.md` sentence), so a merge has no conflict. The main session sets the roadmap row's final status when both plans have landed.
6. **Interrupt.** The Mac also ends a session's kittens on `Interrupt`; Windows has no such hook event. *Mac-only extra.*
7. **B-0's checkpoint changes, in both plans.** The black coats' bright eyes (a new `cat` input to `smallEye` and a flat, rimless iris) and the pair's gap (cat 2 at 114 in the prototype: 108 pt here, 114 px on Windows, 58 apart on both) are in this plan's Tasks 1, 2, 11 and 14; the Windows plan takes the same two changes.
8. **The frame budget.** Eight kittens cost the Mac about 0.6 ms a frame on top of the cats (about 2.4 ms against 1.8 ms; its Open question 9) and Windows about 1 ms in a software canvas; both leave the call to the owner at Checkpoint 2.

**What both do the same, on purpose:** the contract and the three modes' frozen IDs; the layout numbers of the pair and the kittens (B-0's, the gap included); the coloured eyes for every compact cat, the black coats' glowing; the kitten state mapping (a leaving kitten blinks happily); kittens for agent pills only; the busiest-other rule; kittens in the compact island and the overview and not in the other expanded views (its Open question 2, this plan's 3); the One cat row and grid unchanged (here proved by the first case of `cast-cases.json`, six tasks with the focus first, whose `pills` are the old `filter` and `prefix(4)`); and "Character" renamed "Main cat".

**What only the Mac has:** kittens from Codex (the Mac has Codex's `SubagentStart`); the `useCharacter` guard for a kitten; the identity check of the icons (it also protects the Windows icons); `fake-subagent-events.py` for a real build. **What only Windows and Linux have:** the Rust twin of the clean-up and `sanitized` keeping the three keys; `CatBlock`; `window.__nm` and `?display=` in the dev server; the headless zero-frame check (the Mac proves the same rule by a source pin that the kitten layers pause with a hidden island and run no timer).

---

## Open questions for the owner

Each has the answer this plan assumes, so nothing blocks. A different answer changes one small thing, named in each.

1. **The icons keep their ink eyes.** The coloured eyes are for the app's cats; `gen-icons.swift` draws with `inkEyes = true`, so the 18 shipped files regenerate byte for byte (without it six small files differ). **Assumed: yes; the owner confirmed it** (the black coats' bright eyes change nothing here: the icons are ink). Regenerating them with the new eyes is the icons sub-project's call.
2. **Two cats in the overview: the numbers.** Derived from the prototype's: cat 1 18 pt left of where the one cat is (50 pt), cat 2 Ø46, 40 pt right of it (108 pt: the prototype's 114, which leaves a 6 pt gap between the two heads, B-0's checkpoint) and 8 lower, the text starting 21 pt after cat 2's edge (142 pt into the card instead of 108), and the second line fitting in the card's 84 pt by tightening two paddings (4 and 0 instead of 6 and 6) in Two cats mode only. They live in one place (`CatIslandLayout.pairExpanded`); judged on `island.png` at checkpoint 2.
3. **Cat 2 and the kittens exist in the compact island and in the overview only.** The other expanded views (approval, question, chat, mail, upload, settings) show cat 1 and no kittens, as they show the big cat today; a subagent's permission request is the parent's card as before, and its kitten shows the approval in the overview and the compact island. **Assumed: yes.**
4. **The greeting in Two cats mode.** The spec says the Main cat is the one that falls in and the pair arrives together: the Main cat falls in and settles at 30 pt, and cat 2 (the pair's second coat) pops in beside it as the island folds; when the Main cat is not the pair's first, cat 1 changes coat at the hand-over (invisible with the defaults, where both are Shrimpy). The alternative is for the pair's first cat to fall in, which changes the cast's contract. **Assumed: as the prototype.**
5. **Which events end the kittens.** The contract names the parent's `Stop` and `SessionEnd`; the hook server also takes `StopFailure` and `Interrupt` (a turn ended in error or stopped by the user), and ignores a `Stop` that names a subagent. **Assumed: yes.** A session's end takes that session's kittens only (two sessions of one agent share a pill).
6. **A subagent's approval.** `PermissionRequest` events with an `agent_id` make the kitten wait on an approval; the card, the sound, the focus pull and the ticker stay exactly as they are (the parent's). The kitten is back to work when the card is answered, dismissed or displaced. **Assumed: yes.**
7. **The pair's "×N" in the compact island** sits at 76 pt from the island's left edge (cat 2 at 54 pt plus 1.1 of its width), and the ear is 80 pt wide: a count of two digits may reach under the camera housing. The numbers are contract numbers (`pairCompact`) and `CatIslandLayout.compactX`. Judged on a notch Mac at checkpoint 3.
8. **A pill with kittens keeps its title clear of them:** 4 pt clear of its own cat and the width the kittens take at the trailing end, so a name is cut as soon as the kittens take much room ("Antigr…"). **Assumed: OK;** the alternative is to draw the kittens over the title.
9. **The kittens' frame cost.** One kitten costs about 0.07 ms a frame; eight kittens with the twelve small cats and the big one read about 2.4 ms against 1.8 ms. The spec's 2 ms budget is for the cats without kittens, and a frame is 16.7 ms. **Assumed: OK.** The alternative is to redraw the kittens at 20 fps (one number in `KittenLayerView`).
10. **"Cats for your agents" lists** the agent pills on the island (most recent event first, then those that had none, in the island's order) and then the agents that are only stored (code-point order). The island forgets an agent after its session; the store does not, so an agent the user ran last week is still listed with its coat. **Assumed: yes.**
11. **"Reset to defaults"** gives Claude Code Shrimpy and Codex Momo (their defaults, nothing stored) and every other listed agent a new random coat, and removes the stored coats of agents that are not in the list (there are none: the list is the stored agents too). **Assumed: yes.**
12. **A coat is chosen once.** A new agent's random coat avoids the coats the other agents and the Main cat wear **at that moment**; it never changes by itself. If the user changes the Main cat later to a coat an agent wears, the two share a coat until the user rolls the dice. **Assumed: yes.**
13. **Only cat 1 is slapped and dragged.** The slap, the drag-to-attach and the hover love emote are the big cat's; cat 2 is drawn and tappable (to focus its agent) but ignores the hover and the pointer's clicks otherwise. **Assumed: yes.**
14. **The README's roadmap row for B** is edited by this plan only (the Windows plan leaves the root `README.md`, `docs/INTEGRATIONS.md` and the CI file alone); the step keeps the row's other words, so the main session sets its final status when both plans have landed. **Assumed: yes.**
15. **Helpers beyond B-0's list:** `CatSmallEye.K`, `CatDisplaySettings.catFor`, `CatAgentList`, `CatDisplaySample`, `CatIslandLayout`, `CatKittenHooks`, `CatKittenDraw`, `CatKittens.State.catState`. Each is small, and each stops two files reading a rule two ways. **Assumed: keep.**
16. **The sweep runs when the cat falls asleep, not when a working cat's ten quiet minutes pass.** The spec says "the cat's existing 10-minute sleep timer"; on the Mac that timer is armed only for an idle cat, so the kittens whose stop never came go when the cat falls asleep, and a kitten left behind under a parent that is still working goes with the parent's `Stop` or its session's end (a working parent that stays silent for ten minutes keeps its kitten until then). The Windows twin also sweeps under a working cat. Arming the Mac's timer for a working cat would change the sleep contract (`CatRules`, `sequence-cases.json`), so this plan does not. **Assumed: OK; the owner chose it, and the Windows plan moves to match.** The alternative is a one-line sweep of the stale kittens in `HookServer.processEvent`, which would also remove a live subagent that has been quiet for ten minutes inside a long tool call.
17. **The ticker's second line says "has a question"** for an agent that asks you something (the prototype's `STATE_TXT`); the Windows twin says "asking you". Every other word is the same on both ("waiting for you", "hit an error", "rate limited", "asleep", "No other agent"). **Assumed: "has a question" on both; the owner chose it**, so the Windows plan moves (one string in `views.ts` and its test).

## The owner's answers (2026-10-08)

The owner read this plan and approved it, with these answers to its open questions:

- **Open question 16 (the sweep): it runs when the cat falls asleep**, as Task 13 has it. The Windows plan moves to match (it also swept under a working cat).
- **Open question 1 (the icons): they keep their ink eyes** (`CatLook.inkEyes` and the 18-file identity check of Tasks 2 and 16).
- **Open question 17 (the ticker's word): "has a question" on both apps.** The Windows plan moves.
- **Every other open question (2 to 15): approved as assumed.**

B-0 was merged as `e00ad3d` with two changes made at its owner checkpoint after this plan was first drafted. The plan follows both, and the affected steps were replayed from a fresh clone at `e00ad3d` (see "Dry run"):

1. **Bright small eyes for the black coats.** `SMALL_EYE.bright` (`midnight`, `oreo`, `mocha`) and `brightPupil.w` 0.12; `smallEye` takes the coat's ID as `cat` and returns `flat: true` and `rim: 0` for a bright coat. *Task 1* (the port: its replay is now 265 rows, with the new checks), *Task 2* (the renderer passes the coat's ID and draws the flat lighter iris with no rim; the sheets and the tests), the Global Constraints, Review Focus 5, the checkpoint's questions and the Parity table. The icons keep their ink eyes.
2. **The expanded Two cats pair has a gap.** Cat 2 moves from 99 to 108 pt (the prototype's 105 to 114), 8 lower and Ø46 as before, and the text that starts after it moves by the same 9 pt, to 142 pt into the card. *Tasks 11 and 14* (`pairExpanded`, the layout tests, the island and kitten sheets), Open question 2 and the Parity table. On `island.png` the second line still fits the card and both badges stay clear.

Base and Task 0: B-0 is in the history, so the plan applies nothing of it; Task 0 checks `git merge-base --is-ancestor e00ad3d HEAD` and the contract reads `# tests 231`.

## Self-review

- **Spec coverage.** §1: the three modes and their frozen IDs, the Display picker with its live preview, the pair, the agents' list, "Main cat" and the storage keys (Tasks 3, 6, 7), the first-sight coat, the dice and Reset to defaults (Tasks 4, 6, 9). §2: the cast of every place (Tasks 5, 9, 10), the busiest-other rule and the second agent leaving the row (Tasks 5 and 11), the layouts (Task 11), the tap on cat 2 (Task 11), sessions as one pill (Task 13). §3: the data (Tasks 12 and 13), the fallback (the `fallback` scenario), the look and the placement table (Tasks 12 and 14), the clean-up (the parent's stop, the sleep timer's sweep, 8 per agent). §4: Tasks 1 and 2 (the black coats' bright eyes included), the frame bench before and after. §5 step 2 in its order (with the two moves said above), the Mac notes (each view takes its coat; `useCharacter` is never called on a kitten), the three checkpoints (Tasks 8, 15, 17), the fake events through a socket and the scripted images without the app. Out of scope and left out: per-session pills, Codex hooks on Windows/Linux, kitten sounds, the desktop cat, the wardrobe, kitten names.
- **Placeholders.** None: every code step is a **Create** or **Edit** block generated from the files the dry run ran (the docs of Task 16 are written in full), and every `Run:` line has its expected output.
- **Type consistency.** `CatDisplaySettings` (Task 3) is what `CatAgentCats` (Task 4), `CatCast` (Task 5), the store (Task 6), `CatAgentList` and the preview (Task 7) use; `CatCast.Result` (Task 5) is what `AppState.cast` (Task 9), the views (Tasks 10 and 11), `CatKittenDraw`'s callers and `KittenPlacement` (Task 14) read; `CatKittens.Kitten`, `Event` and `Slots` (Task 12) are what `CatKittenHooks`, `AppState.kittens` (Task 13) and the layers (Task 14) use; `CatIslandLayout`'s numbers (Tasks 7, 11 and 14) are the ones the views and the sheets read.
- **Review Focus.** Lines 1 to 6 each have their tests, named in the line.
- **What this plan deliberately does not do:** touch `cat-core.js`, a fixture of `tests/fixtures/cat/` or anything under `windows/`; launch the app; store a kitten; change a coat by itself; draw kittens in the overview-less expanded views; give kittens sounds.


---

## Dry run (2026-10-08)

The plan was run before it was handed over: every task was built and checked in a throwaway clone while the plan was written, and then **the finished file was replayed from the top in a fresh clone**, so that every block applies and every `Run:` line prints what its `Expected:` says. After the owner approved the plan and B-0 was merged (`e00ad3d`), it was brought up to B-0's contract (the black coats' bright eyes and the pair's gap, see "The owner's answers") and **replayed again from the top in a fresh clone of `notchmeow/rebrand` at `e00ad3d`, with nothing of B-0 to apply first**. Nothing was committed or pushed (in a clone or in the main checkout), no NotchMeow app was started, nothing was installed or downloaded, and no network was used. The only file this work added to the main checkout is this plan.

**Set-up.** `git clone --local --shared` of this repository at `e00ad3d`, in the session scratchpad, with `TMPDIR` pointing at an empty folder of its own (so that nothing a former run left behind could make a step pass). A clone has no `windows/node_modules` and no Docker; nothing here needs either. Task 0's base check passes on it (`git merge-base --is-ancestor e00ad3d HEAD`), the contract reads `# tests 231`, and commit steps are not run in a clone, so its `git status` lists every earlier task's files.

**Method.** A small runner reads the plan's text in order, applies each **Create** block and each **Edit** block (it fails when a find text occurs other than once), runs Task 0's `bash` block and every `Run:` line, and prints each command's output next to the plan's `Expected:` line; it then compares every backticked literal of every `Expected:` line with the output. The whole plan replayed with **34 Create blocks, 154 Edit blocks and 105 `Run:` lines, 0 failed edits, 0 commands that exited non-zero and 0 literals missing** (about 24 minutes, most of it the Debug, App Store and Release builds); the 14 commit steps were skipped. The 74 paths in the plan's `git add` lines are exactly the 74 files the run changed or created (none missing, none extra). The pictures were looked at from the replay: the small-eye sheets at 1× and 2× (the black coats glow), Settings in the three modes, the island in the three modes (the pair's gap, the second line inside the card, both badges clear) and the kitten sheets.

| Task | Agent | What the run printed (the plan's Expected) |
|---|---|---|
| 0 | the session | `B-0 (e00ad3d) is in the base`; the six B-0 files; contract 231/231, 14 fixture files, fixtures additive; seventeen test lines; the frame bench 1.82 ms; the Debug build |
| 1 | light | red: `error opening input file`; 41 checks pass; with `closeBelow` at 0.2, 3 fail |
| 2 | nm-implementer | red: 2 compile errors; renderer tests pass; with the compact branch off, 4 fail; the sheets and the dev panel drawn; **icons 0 differ** (6 differ without `inkEyes`); bench 2.10 ms on a busy machine (see below); Debug build |
| 3 | light | 47 checks pass; with the next-coat rule off by one, 3 fail |
| 4 | light | 16 pass; with the tie rule changed, 4 fail |
| 5 | light | 18 pass; with the ranking changed, 2 fail |
| 6 | nm-implementer | red: 8 compile errors and 4 pins; the store's 55 pass, the pins pass; Debug build |
| 7 | nm-implementer | `CatAgentList` 25 pass; red: 7 pins and 2 of A's Settings pins; green; the three Settings sheets; Debug build |
| 8 | the session | five images collected; twenty-three test lines |
| 9 | nm-implementer | red: 6 pins; green; Debug and App Store builds |
| 10 | nm-implementer-deep | red: 2 compile errors, 1 store check, 9 pins; green; the four engine and greeting programs; both builds |
| 11 | nm-implementer-deep | red: 22, 18 and 4 compile errors, 10 pins; four programs green (the pair at 108 pt, the text at 142 pt, a 6 pt gap); `island.png`; both builds |
| 12 | light | 25 pass; with the cap at 9, 2 fail |
| 13 | nm-implementer-deep | five scenarios listed; red: the hooks' file missing, 7 pins; 36 pass; wiring and sleep green; with the parent's `Stop` dropped, 4 fail; both builds |
| 14 | nm-implementer-deep | red: 10 and 20 compile errors, 7 pins; green; the three kitten sheets; bench 1.91 ms, and 2.47 ms with eight kittens; both builds |
| 15 | the session | four images collected |
| 16 | light | contract 231/231; twenty-five test lines; leftovers guard 5; icons 0 differ; Release, Debug and App Store builds; the six `check-app-binary.sh` lines; bench 2.00 ms and 2.47 ms |

**The frame bench.** The replay ran on a busy machine (load average about 7): its readings were 1.82 ms before the eyes (Task 0), 2.10 after them (Task 2), 1.91 and 2.00 later, and 2.47 with eight kittens. Read back to back on that machine, the base against the finished tree, three times: **1.79 to 1.84 ms before and 1.92 to 1.96 after**, so the eyes cost about 0.12 ms, as on the quiet machine of the first replay (1.70 to 1.78 before, 1.82 to 1.85 after, 2.35 to 2.40 with eight kittens). The plan therefore asks for under 2 ms on a quiet machine and says to read "after" next to a fresh "before".

**What the dry run changed in the plan** (each was a defect in an earlier draft, found because a step failed, printed something else or drew something wrong, and is fixed in the text):

- **B-0's merge and the owner's checkpoint.** Task 0 now checks that `e00ad3d` is in the history and nothing of B-0 is applied; the contract reads `# tests 231` (Tasks 0 and 16); the fixture has 6 more `smallEye` rows (265, Task 1: the test goes from 22 to 41 checks and its bite still fails 3). **The black coats' eyes** (Tasks 1 and 2): `CatSmallEye.eye` takes the coat's ID, a bright eye is `flat` with `rim` 0, `CatFace` passes the preset's name and fills the lighter iris colour flat; the iris-colour test knows the black coats, a new section checks the flat iris at three points, and the bite of Task 2's step 5 reads 4 instead of 3. **The pair's gap** (Tasks 11 and 14): `pairExpanded` puts cat 2 at `botX + 40` (108 pt), so the text starts at 142 pt, and the layout test now says the heads are 6 pt apart.
- **A probe that landed on an antialiased edge.** The first flat-iris test sampled 0.96 of the iris's half-width, which at Ø16 is a boundary pixel and read a blend of iris and fur; it samples 0.45, 0.8 and 0.9.
- **The icons.** Coloured eyes would have redrawn six of the 18 shipped icon files. `CatLook.inkEyes` keeps the ink eyes for the contact sheet and the icons (Task 2), and a pixel-identity check of the 18 files is in Tasks 2 and 16 (Open question 1: the owner confirmed it).
- **Four older tests pinned numbers these tasks move** and move with them, each by a named, exact edit: the renderer's flat-fill probe (the iris is wider than the ink pill) and its iris sample, and A's two Settings pins (`CatSettingsView()` is now `CatSettingsSection()`).
- **A pin crashed instead of failing.** The wiring test's `#if`-depth helper trapped when the anchor it looks for did not exist yet, so Task 13's red run printed `Trace/BPT trap` and no count; it now answers "not in every build" and the red run counts 7.
- **The island sheet needs its folder.** `render-cats.sh --island` stops on a nil unwrap when `b-mac-2` does not exist; the Run line makes it (Task 11), and Task 15's copy then finds the file.
- **A pill's title overlapped its own cat** once the kittens took room: the crowd sheet showed "odex" under the cat. The title now starts 34 pt in (the pill's cat ends at 30 pt) and is cut ("Co…") instead; the sheet and the app agree (Task 14, Open question 8).
- **A kitten's "+N" box was too narrow** for a two-digit count, and one placement condition had a precedence mistake (`A && B || C`, now `CatIslandLayout.kittenParents`): both found while drawing the sheets and fixed before the plan was written (Task 14).
- **Swift 6 and the build.** `@MainActor` on the second cat's placement, a `withCGContext` capture and an exact compare of `-2.2e-16` with zero (now `checkNear`) are fixed in the given code; `check-app-binary.sh` takes `<app> <mode>`, and its Debug mode prints the cat-panel line second to last (`tail -2`).
- **Expected counts and text** were corrected to the real output many times: swiftc's missing-file message (`error opening input file`), the passing counts and the failing counts of every "prove it bites" step (several mutations fail two or three checks, not one), the compile-error counts of the red steps, the test-line counts of the loops (17, 23, 25) and the frame times (the bench moves by 0.1 to 0.2 ms with the machine's load, so the plan gives ranges).
- **The Windows twin.** Its finished plan was read for the Parity section: one new pin (both relays forward the payload whole, so `agent_id` reaches the island, Task 13) and two open questions came out of it (16 and 17, both since answered by the owner).

**Not run, and owed.**

- **Any commit step.** The 14 `git add` and `git commit` blocks were skipped and have to be run by the executing session in its worktree; Task 16's `git status` and `git diff` lines assume the earlier tasks are committed.
- **The app itself.** No NotchMeow window was opened, so the real island with a real hook event from a real Claude Code (and whether Claude Code puts `agent_id` on a subagent's tool events and permission requests), the pointer, the tap on cat 2, the launch greeting's hand-over in the real window, the sleep timer in real time, a notch Mac's camera housing next to the pair's "×N" and the 0 % CPU rule in Activity Monitor are the checkpoints' lists for the owner, not something this run proved. The cats, the island's numbers and the kittens were drawn by the real renderer and layout code in the contact-sheet programs, the hooks by the real mapping on a socket of the test's own, and the wiring by source pins.
- **Signing.** The three builds are unsigned (`CODE_SIGNING_ALLOWED=NO`); a signed Release or App Store archive is the owner's.
- **Windows and Linux.** Nothing under `windows/` is touched; the twin has its own dry run and takes the same two B-0 changes.

The throwaway clones and the pictures' folders were moved to the Trash afterwards (`trash`, never `rm -rf`).
