# A-mac, Stages 5 to 7: the Cat Settings, the Collar and the Last Clean-up in the macOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the cats in the macOS app. Stage 5: a **Cat** section in Settings (the character, Playful or Classic, a motion override and a personality for each cat, six trait sliders, Apply to every cat, fur lines) whose values are saved, cleaned and handed to the engines. Stage 6: the agent colour worn as an optional **collar** (three styles and Off, readable from Ø12 up), **searching** for the search tools, **sleeping** after ten minutes with no agent event, and a head-bob and ear bounce for the Apple Music dance. Stage 7: the **theme tokens** in place of the hard-coded colours, the **dead code** and the old names out, and the **Mochi sweep**.

**Architecture:** Everything the spec calls a rule stays a pure Foundation file tested against the shared fixtures by a `swiftc` program, the way stages 1 to 4 did it. `CatSettings` is the Swift port of the contract's `cleanCatSettings` (`settings-cases.json` replays it, plus a real NaN); a stored personality goes through `Personality.clean` and is never decoded. `CatSettingsStore` is the app's single holder of the clean value: it loads UserDefaults through the clean-up, saves only what changed, and hands the result to the engines through the `CatConfig` they already read on every frame. The collar is `CatGeometry.collarGeometry` (replaying `collar-cases.json`) painted by `CatEffects.drawCollar` in the front pass. Sleeping is one one-shot timer (`CatSleepClock`) with a fake clock in its test. The Settings section is plain SwiftUI built from the rows Settings already has, and is checked without launching the app by a script that draws it into a PNG, as the Debug cat panel is.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, CoreGraphics, Combine, XcodeGen, `swiftc` test programs, Bash.

**Spec:** `docs/superpowers/specs/2026-10-04-cats-in-app-design.md`: §3 (searching, sleeping, collar, music, removed dead code), §4 (Settings: rows, defaults, persistence, frozen IDs), §5 (theme tokens and checks), "Stages" 5 to 7 and "Done means". Icons (§5) were done by `a-icons/c-peek` and are not in this plan. The contract is `design/prototype/cat-core.js` with `docs/CAT-CONTRACT.md` and `tests/fixtures/cat/`, **including A-0d's "Stored settings" and `settings-cases.json`** (`docs/superpowers/plans/2026-10-07-a0d-cat-settings-theme.md`, "Interface for the app plans", whose names and shapes are exact and fixed), and `docs/THEME.md` with `Theme.generated.swift`. The stage 1 to 4 plan (`docs/superpowers/plans/2026-10-04-a-mac-cats-stages-1-4.md`) is the format and the source of the Mac code's conventions; its "Next plan: stages 5 to 7" is the brief this plan fills in. The Windows and Linux twin is `docs/superpowers/plans/2026-10-07-a-tauri-cats-stages-5-7.md`; "Parity with Windows/Linux" below lists where the two differ.

**Base:** a new branch `a-mac/stages-5-7` in a git worktree, from `notchmeow/rebrand` **after A-0d is merged** (its branch `a0d/cat-settings-theme` adds `cleanCatSettings`, `cleanPersonality`, `applyToAllCats`, `motionFor`, `collarFor` and `engineCfg` to `cat-core.js`, the fixture `tests/fixtures/cat/settings-cases.json`, `shared/theme.json`, `NotchBuddy/Sources/App/Theme.generated.swift`, `docs/THEME.md`, and the `windows/` theme files) and after `a-icons/c-peek` (merged as `f704178`). This plan never edits `cat-core.js`, a fixture, `shared/theme.json` or a generated file. It touches nothing under `windows/`.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec and from A-0d's interface; the lines marked "(plan decision)" are choices this plan makes where the spec is silent, and are listed again under "Open questions for the owner".

- **Swift 6, SwiftUI and AppKit, no third-party dependencies.** The cat is drawn in code. Foundation-only files (`CatSettings`, `CatSleep`, `CatFur`, the `CatRules` additions) stay Foundation-only.
- **0 % CPU when the island is hidden and Settings is closed.** The sleep timer is one `DispatchWorkItem` that is set when the cat is idle and cancelled or replaced by every event: no repeating timer, no polling. Settings' previews are `TimelineView`s that are **paused** unless the Settings window is on screen (visible, not minimised, not hidden behind other windows) **and the key window** (the Windows app also stops them when Settings is not focused); the Cat section only exists while it is the selected section.
- **Never restyle a shipping view.** The only changes to an existing view are the named ones: one new sidebar entry, **Cat**, **after** Shortcuts (plan decision: nothing that exists moves), and its section; the big and small cats draw a collar and fur lines when Settings asks (default Off); an idle pill's cat sleeps with the big one; the island's glow reads `Theme.State.glow` **only with the owner's OK** (same seven values). No existing Settings row changes. Never rename a pill ID or a contract string (`nm-hook`, `nm.sock`, `nm_kind`, `nm_agent`, bundle identifiers, notification names that are still posted or observed).
- **Frozen contract values.** Cat IDs, in this order: `shrimpy`, `momo`, `ginger`, `midnight`, `latte`, `patches`, `blue`, `snow`, `oreo`, `mocha`, `silver`, `cloud`, `leo`, `button`, `puff`, `noodle` (an unknown stored ID is `shrimpy`). Collar style IDs, in this order: `tag`, `band`, `kerchief`, `off` (an unknown stored global style is `off`). The word for no override is `follow` (an invalid per-cat override is `follow`). The UserDefaults keys: `cat.character`, `cat.motionStyle`, `cat.furLines`, `cat.collar`, `cat.motion.<id>`, `cat.collar.<id>`, `cat.personality.<id>` (the personality is JSON text).
- **The Cat section's rows and defaults (spec §4):** Character `shrimpy` (the 16 cats, Shrimpy first and Momo second, each in a small live preview that animates only while Settings is visible); Motion style Playful or Classic, default Playful; This cat's motion: follow the global style or override it, default Follow; Personality Balanced, Chill, Grumpy, Sweet, Hyper or Chatty (moving any slider turns it into Custom), default Balanced; six trait sliders (Energy, Curiosity, Chattiness, Affection, Sass, Mischief) each 0 to 1, default 0.5; Collar Band and tag, Band, Neckerchief or Off, default Off; This cat's collar: follow or a style, default Follow; Apply to every cat: copies this cat's motion, personality and collar to all 16 (what is stored, not what is in force: a cat that follows keeps following); Fur lines, default Off.
- **Stored values never throw and never skip the clean-up.** Every value read from UserDefaults goes through `CatSettings.clean`, and every personality through `Personality.clean`; `CatPersonality` is `Encodable` only, so a `Decodable` use of it cannot compile. A value is written only after it was cleaned. `furLines` is on only for a real boolean `true` (the number 1 and the text "true" are off). Text that is not strict JSON is not JSON: Foundation's parser also takes a comma before `}` or `]` and a byte-order mark, which the contract's strict parsers refuse, so `Personality.isStrictJSON` refuses them first.
- **Each Settings row is one pure edit** of the clean value (`CatSettings.withCharacter`, `withMotionStyle`, `withCollar`, `withFurLines`, `withCatMotion`, `withCatCollar`, `withPersonality`): it returns a new clean value with that one thing changed (an unknown value is the neutral one, an unknown cat is Shrimpy, a trait is held to 0 to 1) and never touches its input, so a row can only change its own field and the logic is tested without `UserDefaults`.
- **Fixtures decide.** Numbers compare within **1e-9**; strings, booleans, nulls and shapes compare exactly. `cat-core.js` is the tie-breaker; this plan never edits it or a fixture. There are no pixel tests of the look: it is checked on the contact sheets and the section's render. Where a pixel test is used (the floors, the order of the passes, no recolouring) it counts pixels of a colour no coat has.
- **Collar (spec §3 and §4):** three styles and Off drawn from `task.color`, from Ø12 up, in the front pass between the folded ears and the whiskers (the contract's `collarPass`), with the readability floors in **device** pixels of the contract (`COLLAR_MIN`: a band 3 px thick, a tag 6 across, a neckerchief 7 wide and 5 deep). Small cats wear their pill's colour; the big cat wears the colour of the agent driving its state, and none when idle, asleep or dizzy (plan decision, the same as the Windows plan); the coat is never recoloured. With the collar off, each mini cat's pill still names its agent. Its Settings rows land with it, default Off.
- **Searching (spec §3):** a PreToolUse or PostToolUse event whose tool name is in `tests/fixtures/cat/search-tools.json` puts the agent in "searching"; the next tool of any other kind puts it back to "working". **Sleeping (spec §3):** an idle cat sleeps after 10 minutes with no agent event, never during an approval or a question; any hook event, hover or click wakes it, and Playful wakes with zoomies (the engine already does); one one-shot timer is reset on each event, with no polling. **Music (spec §3):** the Apple Music dance bounce drives a head-bob, with the ears bouncing on the beat.
- **Theme (spec §5):** stage 7 replaces exactly the Mac sites of A-0d's inventory (`docs/THEME.md`) with `Theme.*`, keeps every value, and proves it by drawing the contact sheets before and after and comparing the images byte for byte. A site whose value differs from its token: stop and ask. Existing views keep their colours.
- **Dead code (spec §3 and the stage 1 to 4 plan's list):** permanent emotes, `miniEye` and the eye alias, the morph, cup, mouth, mouth-rect and suction of the drop view, the mailbox morph, and the names nothing posts or observes (`.botMorphTo`, `.botReject`, `.botGreet`). Mail sent keeps its wink and `engine.greet()` stays (the contract's fixtures pin the `hello` emote). **The reviews' leftovers that apply to the Mac** (the owner's manual-check lists): an unknown emote changes nothing and is not noted, a refused file clears the chew's queued lick and sparks, the gag's 120 ms and the hairball's 2.4 s live in one place that the engine and the drop view's note both read. **Mochi:** no `mochi` identifier in the Mac code, comments, scripts or tests. Historical plans, specs and the git history are not swept.
- **Out of scope:** icons; sound wiring (sound Stage 3); the Mac `writeJSONFile` symlink fix; sub-projects H, I and B; the Windows and Linux app.
- **No `UserDefaults` suite, and no `UserDefaults.standard` write, in any test or script.** A test builds `CatSettingsStore(backing:config:)` on a dictionary and a `CatConfig` of its own. `CatSettingsStore.shared`, `CatSleepClock.shared` and `CatConfig.shared` are used by the app only.
- **Never edit `NotchBuddy.xcodeproj` by hand.** A task that adds a Swift file runs `cd NotchBuddy && xcodegen` and commits the regenerated `project.pbxproj`. A new Swift file that a test script compiles is added to the script's list; a file that every renderer script compiles (`CatFur.swift`, and in stage 7 `Theme.generated.swift`) is added to all of them.
- **Commits** are local only, never pushed, and only the files each task lists. Each commit message ends with the `Co-Authored-By` line of the model that wrote it: `Claude Sonnet 5.5` for `nm-implementer` and `nm-implementer-deep`, `Claude Haiku 4.5` for `nm-implementer-light`.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app. A Debug, Release or App Store **build** in the worktree is fine and is only built; the scripts that draw a PNG (`render-cats.sh`, `render-cat-settings.sh`, `render-cat-panel.sh`) are not the app and may run.
  2. Install nothing. No network calls, no downloads (`npx --no-install` only; this plan needs neither `npm` nor `cargo`).
  3. Use `trash`, never `rm -rf`, for anything you delete by hand; put scratch files under `${TMPDIR:-/tmp}` with a unique folder name. (The test scripts clean their own `mktemp` folder with `rm -rf` in a `trap`, as every `scripts/test-*.sh` does: that is the repo's convention, not a command an agent runs.)
  4. No `UserDefaults` suite and no write to `UserDefaults.standard` or to `~/Library` in a test or script; tests write no log outside a temp `NM_LOG_DIR`.
  5. Never edit `design/prototype/cat-core.js`, a fixture, `shared/theme.json`, a generated theme file or anything under `windows/`.
  6. Never push. Commit only in a task's commit step.
  7. If a command is denied by a permission prompt, stop and report it. Do not look for a workaround.

## Review Focus

The spec says what Settings, the collar, the sleep and the theme do. It is silent on these inputs and conditions, and each would bite a person first, most likely first. Each line names the test that pins it.

1. **A stored personality or flag that is wrong in a way the platform's own parser forgives.** A hand-edited `cat.personality.momo` with a trailing comma, a byte-order mark, bad JSON, the wrong types or a bare number; `cat.furLines` stored as `1` or `"true"`; a trait that is NaN. Expected: Balanced (or 0.5 for the bad trait), fur lines off, never a throw, never a Settings window that cannot open. Foundation's JSON parser accepts a trailing comma and a byte-order mark, so the plan refuses both itself. Tests: Task 1 (the 47 personality and 37 settings rows of `settings-cases.json`, "JSON text is strict…", "a real NaN or Infinity", "a store that is wrong in every way still loads").
2. **A settings change while the engines are running.** The character changes under a running engine; a cat that does not exist is stored; a slider is dragged 100 times a second; "Apply to every cat" is pressed twice. Expected: the cat on screen becomes the new coat on its next frame with its state and pose intact, an unknown ID is Shrimpy, each slider move writes one key, and doing it twice changes nothing. Tests: Task 2 ("the character switches a live engine…", "what is written is only what changed…") and Task 1 (applyAll rows).
3. **A collar on the smallest cat, on a light coat, on a turned head.** At Ø12 a band must stay 3 device pixels thick on 1x and 2x screens; a light agent colour (VS Code's `#F5F6F8`) on a light coat (Latte, Snow, Cloud) needs its dark edge; the collar must turn with the head and must never recolour the coat. Expected: the contract's floors at every pixel ratio, ink on every coat, the upper head untouched. Tests: Task 6 (164 cases, floors on all 16 coats at pixel ratios 1, 2 and 3) and Task 7 (ink counts on six coats at six sizes, the upper half unchanged, the turn, the pass order).
4. **A cat that falls asleep when it must not, or never wakes.** An approval or a question is waiting on another pill; Apple Music is playing; a timer fires early; an event arrives while asleep; the pointer rests on the island. Expected: no sleep through a card or music, the ten minutes restart on every event, a hover or a click wakes it and hovering an awake cat does not push bedtime back, and at most one timer is ever waiting. Tests: Task 10 (the fake-clock program: nine groups, "no polling…", "something else can keep an idle cat awake…", the pins).
5. **The Settings window closed but still alive.** Settings keeps its window and its views after it is closed, so `onDisappear` never comes and seventeen cats would go on drawing at 30 fps behind a closed window, or behind another app. Expected: the previews are paused unless the window is on screen and the key window. Tests: Task 4 (the source pins on `paused: !active` and `WindowVisibility`) and the owner's check on a real build.
6. **A theme colour that was never the token's.** A hard-coded value that differs from the generated token by one digit would change a pixel. Expected: none changes. Tests: Task 13 (the contact sheets before and after, compared byte for byte; the island glow's seven values proved equal to `Theme.State.glow` before the swap; the source pins) and the final check that the app and menu bar icons still regenerate identically.

---

## File Structure

| Path | Responsibility |
|---|---|
| `NotchBuddy/Sources/App/CatSettings.swift` | New. `CatSettings` (the clean value), its clean-up, Apply to every cat, the resolvers, the UserDefaults keys, load and save through an injected store. Foundation only. |
| `NotchBuddy/Sources/App/CatSettingsStore.swift` | New. The app's single holder of the settings: `CatSettingsStore.shared`, `update`, the Settings rows' setters, and `CatConfig.apply`. |
| `NotchBuddy/Sources/App/CatSettingsView.swift` | New. The Cat section of Settings, the live preview cat, and `WindowVisibility`. |
| `NotchBuddy/Sources/App/CatFur.swift` | New. The seeded fur strands (the prototype's seeds), and when fur is drawn. |
| `NotchBuddy/Sources/App/CatSleep.swift`, `CatSleep+App.swift` | New. The sleep timer (Foundation only, takes its clock and timer) and the app's side of it (real time, `AppState`). |
| `NotchBuddy/Sources/App/Personality.swift`, `CatRules.swift`, `CatEngine.swift`, `CatLook.swift`, `CatGeometry.swift`, `MotionProfiles.swift` | `Personality.clean` and the preset rule; the collar styles, `bigCatCollar`, `shown`, the gag's numbers; `CatConfig` fields, `useCharacter`, `collarPaint`, the dance in `look`, the emote guard and the chew's beats; `CatCollarPaint` and the `fur` and `collar` options; `collarGeometry` and `CatDance`; `CatTables.emoteNames`. |
| `NotchBuddy/Sources/App/CatRenderer.swift`, `CatEffects.swift`, `CatGreetingRenderer.swift`, `CatDevModel.swift`, `CatDevPanel.swift` | Fur and the collar in the passes; `drawCollar`; the greeting's four session cats wear collars; the Debug panel gets Collar, Agent colour and Fur lines. |
| `NotchBuddy/Sources/App/SettingsView.swift`, `AppDelegate.swift`, `AppState.swift`, `HookServer.swift`, `IslandWindowController.swift`, `BotCanvasView.swift`, `GreetingCanvasView.swift`, `UploadCanvasView.swift`, `CatEngine+App.swift` | Existing files with the named changes: the sidebar entry, the store and the clock at launch, `catAsleep`, the search tools and the events that wake, hover and click, the canvases that follow Settings. |
| `NotchBuddy/Sources/App/CatFace.swift`, `CatGreeting.swift`, `MotionProfiles.swift`, `IslandRootView.swift` | Stage 7: `Theme.*` in place of the hard-coded colours (the island glow only with the owner's OK). |
| `NotchBuddy/Sources/App/IslandTypes.swift`, `FileDropView.swift`, `UploadSequenceEngine.swift`, `AI/AIService.swift` | Stage 7: the dead code and the names nothing uses are gone. |
| `scripts/test-cat-settings.sh`, `test-cat-settings-store.sh`, `test-cat-fur.sh`, `test-cat-sleep.sh`, `test-cat-theme.sh`, `check-no-leftovers.sh` | New. One script for each new test program, and the guard that keeps the old names out. |
| `tests/CatSettingsTests.swift`, `CatSettingsStoreTests.swift`, `CatSettingsSupport.swift`, `CatFurTests.swift`, `CatSleepTests.swift`, `CatThemeTests.swift` | New. The test programs (the support file holds the dictionary store both settings programs use). |
| `tests/CatGeometryTests.swift`, `CatRulesTests.swift`, `CatRendererTests.swift`, `CatEffectsTests.swift`, `CatEngineTests.swift`, `CatDevModelTests.swift`, `UploadCatDriverTests.swift` | Existing programs with new sections. |
| `scripts/render-cats.swift`, `scripts/render-cat-settings.sh`, `scripts/render-cat-settings.swift` | The contact sheets gain `--fur`, `--collars` and `--dance`; Settings → Cat is drawn into a PNG without launching the app. |
| `scripts/render-cats.sh`, `render-cat-panel.sh`, `gen-icons.sh`, `test-cat-*.sh` (the ones that compile the renderer or the engine) | One-line additions to their `swiftc` lists (`CatFur.swift`, then `Theme.generated.swift`). |
| `.github/workflows/build.yml`, `CLAUDE.md`, `ARCHITECT.md` | One CI step per new script and one pointer each. (`docs/THEME.md` is not edited: the main session updates it once both stage 7 branches have merged.) |

**Where the work sits.** Stage 5 is Tasks 1 to 5, stage 6 Tasks 6 to 12, stage 7 Tasks 13 to 16. Settings has no stage-5 collar rows: they land with the collar in Task 8, as the spec says.

## Tasks and agents

CLAUDE.md: the lightest model that fits. Tasks whose code and docs are given in full and whose tests prove them (1, 3, 6, 9, 11, 14, 15) are `nm-implementer-light` (Haiku 4.5). Tasks that touch several files with a build, a drawing to look at or a theme to prove (2, 4, 7, 8, 13) are `nm-implementer` (Sonnet 5.5, medium). Task 10 sets a timer, an `ObservableObject`, the hook server and the window controller to work together, so it is `nm-implementer-deep` (Sonnet 5.5, high). Each task is then reviewed by `nm-reviewer`; the whole branch by `nm-reviewer-deep` after Task 15. If a step's expected output differs and the cause is not obvious, hand that task to `nm-implementer-deep`. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion` (the deep agent also `superpowers:systematic-debugging`); reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`).

| # | Task | Agent | Review |
|---|---|---|---|
| 0 | Worktree and baseline | the session | none |
| 1 | Stored settings in Swift: `Personality.clean` and `CatSettings` (stage 5) | `nm-implementer-light` | `nm-reviewer` |
| 2 | Settings feed the engines: the store, `CatConfig`, the live character (stage 5) | `nm-implementer` | `nm-reviewer` |
| 3 | Fur lines: the strands, the renderer, the sheet (stage 5) | `nm-implementer-light` | `nm-reviewer` |
| 4 | The Cat section of Settings, and the script that draws it (stage 5) | `nm-implementer` | `nm-reviewer` |
| 5 | **Owner checkpoint 1:** the Cat section and the fur lines | the main session and the owner | none |
| 6 | The collar's geometry, from `collar-cases.json` (stage 6) | `nm-implementer-light` | `nm-reviewer` |
| 7 | The collar's paint, the readability floors and the collar sheet (stage 6) | `nm-implementer` | `nm-reviewer` |
| 8 | The collar reaches the cats, the greeting, the Debug panel and Settings (stage 6) | `nm-implementer` | `nm-reviewer` |
| 9 | Searching (stage 6) | `nm-implementer-light` | `nm-reviewer` |
| 10 | Sleeping (stage 6) | `nm-implementer-deep` | `nm-reviewer` |
| 11 | The music bob (stage 6) | `nm-implementer-light` | `nm-reviewer` |
| 12 | **Owner checkpoint 2:** the collars at every size, the sleep, the bob, and the island-glow question | the main session and the owner | none |
| 13 | Theme tokens, proved by sheets before and after (stage 7) | `nm-implementer` | `nm-reviewer` |
| 14 | Dead code, the reviews' leftovers, the old names and the guard that keeps them out (stage 7) | `nm-implementer-light` | `nm-reviewer` |
| 15 | CI, docs and the final checks | `nm-implementer-light` | `nm-reviewer` |
| After 15 | The whole branch: cross-task contracts, privacy and security rules, the Review Focus | `nm-reviewer-deep` | none |
| 16 | **Owner checkpoint 3:** the final report and the manual checks | the main session and the owner | none |

## Execution

One worktree chat session runs the whole plan: branch `a-mac/stages-5-7`, model **Sonnet 5.5 at high effort** (`ARCHITECT.md`: a plan with hard integration, a timer, platform windows and many cross-task interfaces). Nothing is pushed. It runs in a worktree of its own, in parallel with the Windows and Linux twin, which touches nothing under `NotchBuddy/`.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run `git switch -c a-mac/stages-5-7 notchmeow/rebrand`, then Task 0 of `docs/superpowers/plans/2026-10-07-a-mac-cats-stages-5-7.md`: only its Steps 1 to 3 (the base checks). Read `CLAUDE.md`, `ARCHITECT.md`, that plan, `docs/superpowers/specs/2026-10-04-cats-in-app-design.md` and `docs/superpowers/plans/2026-10-07-a0d-cat-settings-theme.md` ("Interface for the app plans"). If a base check fails, say so and stop. Reply "ready" and stop. Do not start Task 1.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-07-a-mac-cats-stages-5-7.md` with `superpowers:subagent-driven-development`, task by task, on branch `a-mac/stages-5-7`. Dispatch each task to the agent the plan's "Tasks and agents" table names, then to `nm-reviewer`; fix what the review finds before the next task. Put the plan's SUBAGENT RULES block (Global Constraints) in every brief. Never launch, quit or replace a NotchMeow app: the builds are builds, and the PNGs come from `render-cats.sh`, `render-cat-settings.sh` and `render-cat-panel.sh`. Run Tasks 1 to 4, then stop and report to the main session for owner checkpoint 1 (Task 5: the images it names, and what to look for). After the owner's reply run Tasks 6 to 11, then stop again for checkpoint 2 (Task 12); **the main session answers the island-glow question (Open question 1) in that reply, and you run Task 13's Step 9 only if the answer is yes.** Then run Tasks 13 to 15, dispatch `nm-reviewer-deep` over the whole branch, and stop for checkpoint 3 (Task 16). Commit only as the plan's commit steps say, and never push. The work installs and downloads nothing. Report: the commits; the output of every `bash scripts/test-cat-*.sh`, `bash scripts/check-no-leftovers.sh` and `bash scripts/test-theme.sh`; the Debug, Release and App Store build lines and the three `check-app-binary.sh` lines; the line `identical: …` for each of the six before and after sheets; `0 icon files differ`; the paths of the PNGs of each checkpoint; and anything you could not settle.

Before any follow-up turn (a fix round, a question, a resumed run), the main session checks the session is still on its configured model and effort.

## How to run this plan

**Blocks.** A code step is either **Create `path`** (the file's exact content) or **Edit `path`** (a find text that occurs exactly once, and its replacement). Apply an edit by replacing the find text with the replacement and nothing else; if the find text occurs zero or two times, stop and report: the tree is not what the plan expects. Never type a block from memory and never "improve" one. Every `Run:` line is run from the repository root (the worktree's top folder); `Expected: FAIL` and `Expected: PASS` say which way it must go, and the text after it says what to see. A test program's failing run prints `✗` lines, and its last line is `N test(s) failed.`; a passing one ends `All tests passed.`

**Mac commands.** The test programs are `swiftc` programs run through `scripts/test-cat-*.sh`; none needs Xcode. A build is `cd NotchBuddy && xcodegen && cd ..` and then `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO`; the Release build is `-configuration Release -derivedDataPath NotchBuddy/build/release` and the App Store target `-scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store`, each with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` (git ignores `NotchBuddy/build/`). Add `2>&1 | tail -3` to read the last lines. **Never start a built app.** The scripts that draw PNGs write wherever `--out` says; this plan writes them under `$d`, a scratch folder (`d="${TMPDIR:-/tmp}/a-mac-5-7"`), and the checkpoints copy the ones the owner sees to `.claude/checkpoints/a-cats-5-7/` of the worktree.

**Looking at an image.** Several steps end with "look at it". The agent that ran the step opens the PNG with its file reader and says in one sentence what it sees against the thing named; a blank or broken image is a failed step. The owner's look is the checkpoint.

**Dry-run clones.** A throwaway clone made with `git clone --local --shared` has no `windows/node_modules` and no Docker; nothing here needs either. Commit steps are not run in a clone.

---

## Tasks

### Task 0: Worktree and baseline

No code and no commit: this makes sure the base is the one the plan expects. Its first three steps are what the chip's prompt runs before the model is set (see "Execution").

- [ ] **Step 1: Put the session's worktree on the plan's branch**

```bash
git status                                    # must be clean
git switch -c a-mac/stages-5-7 notchmeow/rebrand
git log --oneline -6                          # A-0d's merge and the icons' merge (f704178) are in the history
```

Every later command runs from the root of this worktree. Never push.

- [ ] **Step 2: Check that A-0d is in the base and the contract and the theme are green**

Run: `for f in design/prototype/cat-core.js tests/fixtures/cat/settings-cases.json tests/fixtures/cat/collar-cases.json tests/fixtures/cat/search-tools.json shared/theme.json NotchBuddy/Sources/App/Theme.generated.swift docs/THEME.md scripts/gen-theme.mjs; do test -f $f && echo "ok $f"; done; grep -c "function cleanCatSettings" design/prototype/cat-core.js`
Expected: eight `ok …` lines and `1`. If a line is missing, A-0d is not merged: stop and tell the owner (the worktree was cut from an older base).

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)"; bash scripts/test-theme.sh 2>&1 | grep -E "^# (tests|pass|fail)"`
Expected: `# tests 138`, `# pass 138`, `# fail 0`, then `# tests 8`, `# pass 8`, `# fail 0` (the contract with nine fixture files, and the theme generator).

- [ ] **Step 3: Check that the Mac cat tests are green and the Mac builds**

Run: `for f in scripts/test-cat-*.sh; do printf '%-42s' "$f"; bash "$f" 2>&1 | tail -1; done`
Expected: twelve lines: `scripts/test-cat-contract.sh` ends `✓ two generator runs write identical bytes` and the other eleven (`devpanel`, `effects`, `engine`, `frame-meter`, `geometry`, `greeting`, `personality`, `presets`, `renderer`, `rules`, `upload`) end `All tests passed.`

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `Created project at …` and the last lines end with `** BUILD SUCCEEDED **` (a few minutes on a cold build). The build only builds: do not open the app.

- [ ] **Step 4: Read the base once**

Read, without changing: `NotchBuddy/Sources/App/SettingsView.swift` (the sidebar and `sectionContent`), `BotCanvasView.swift` (`BotCanvasView`, `MiniBotCanvasView`, `drawCat`), `CatEngine.swift` (`CatConfig`, `CatEngine.look`), `Personality.swift`, `CatRules.swift`, `HookServer.swift` (`processEvent`) and the "Interface for the app plans" of the A-0d plan. Nothing to report.

---

### Task 1: Stored settings in Swift: `Personality.clean` and `CatSettings` (stage 5)

**Agent:** `nm-implementer-light`. The code is given in full; the tests prove it.

**Files:**
- Create: `NotchBuddy/Sources/App/CatSettings.swift`, `tests/CatSettingsTests.swift`, `scripts/test-cat-settings.sh`
- Modify: `NotchBuddy/Sources/App/Personality.swift` (the preset rule, `clean`, `jsonText`, `isStrictJSON`; `CatPersonality` becomes `Encodable` only), `NotchBuddy/Sources/App/CatRules.swift` (the four collar style IDs)

**Interfaces:**
- Consumes: A-0d's `settings-cases.json` (keys `ids`, `follow`, `motionStyles`, `collarStyles`, `defaults`, `cases`, `personalities`, `applyAll`, `derived`) and the contract's rules in "Interface for the app plans" and "Stored settings" of `docs/CAT-CONTRACT.md`.
- Produces `Personality.clean(_ raw: Any?) -> CatPersonality`, `Personality.jsonText(_:) -> String`, `Personality.isStrictJSON(_ data: Data) -> Bool`, `CatPersonality.json`; `Personality.sanitized` follows A-0d's preset rule (a preset name is kept only while it names one of the six and the traits still equal that preset's within 1e-9; anything else is `"custom"`).
- Produces `CatRules.collarStyles` (`["tag", "band", "kerchief", "off"]`) and `CatRules.collarStyleOf(_ v: Any?) -> String`.
- Produces `CatSettings` (`character`, `motionStyle`, `collar`, `furLines`, `cats: [String: CatSettings.Entry]` with `motion`, `collar`, `personality`), `CatSettings.follow`, `.motionStyles`, `.motionStyleOf`, `.motionOverrideOf`, `.collarOverrideOf`, `.catIdOf`, `.clean(_ raw: Any?)`, `applyingToAll(from:)`, `motion(for:)`, `collar(for:)`, `engineCfg`, `json`, `CatSettings.Key` (the UserDefaults keys), `CatSettings.load(from:)`, `save(to:replacing:)`, **the pure edits the Settings rows are written with** (`withCharacter`, `withMotionStyle`, `withCollar`, `withFurLines`, `withCatMotion(_:for:)`, `withCatCollar(_:for:)`, `withPersonality(_:for:)`: each returns a new clean value with one thing changed and never touches its input), and the protocol `CatSettingsBacking` (`object(forKey:)`, `set(_:forKey:)`, `removeObject(forKey:)`, which `UserDefaults` adopts).

- [ ] **Step 1: Write the failing tests**

The program replays `settings-cases.json` (37 stored values, 47 personalities, 5 apply-to-all rows, 3 derived rows), adds the real NaN and infinity that JSON cannot write, checks that each of the seven edits changes one thing and returns a clean value, pins that nothing decodes a `CatPersonality`, and runs the UserDefaults keys through a dictionary store, never through a `UserDefaults` suite.

**Create `scripts/test-cat-settings.sh`**:

```bash
#!/usr/bin/env bash
# Cat settings: the clean-up of what Settings saves (cleanCatSettings, cleanPersonality, Apply to every cat, the resolvers) against
# settings-cases.json, a real NaN, and the UserDefaults keys through an injected dictionary store (no UserDefaults suite).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-settings.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/CatMath.swift NotchBuddy/Sources/App/CatPresets.swift NotchBuddy/Sources/App/Personality.swift \
    NotchBuddy/Sources/App/CatRules.swift NotchBuddy/Sources/App/CatSettings.swift \
    tests/CatTestSupport.swift tests/CatSettingsTests.swift \
    -o "$TEST_DIR/cat-settings-tests"
"$TEST_DIR/cat-settings-tests"
```

**Create `tests/CatSettingsTests.swift`**:

```swift
import Foundation

/// A settings store that lives in a dictionary, so a test run never writes a preferences file. It counts the writes.
final class MemoryBacking: CatSettingsBacking {
    var values: [String: Any] = [:]
    private(set) var writes: [String] = []
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { writes.append(key); values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}

@main
enum CatSettingsTests {
    typealias S = CatSettings

    static func list(_ x: Any?) -> [Any] { x as! [Any] }
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func strings(_ x: Any?) -> [String] { x as! [String] }

    @MainActor static func main() {
        let fx = CT.fixture("settings-cases.json")
        let ids = CatPresets.ids

        CT.section("the frozen words: the cat IDs, follow, the two motion styles and the four collar styles")
        CT.check("the 16 cat IDs, Shrimpy first and Momo second", ids, strings(fx["ids"]))
        CT.check("follow", S.follow, fx["follow"] as! String)
        CT.check("the motion styles, in Settings order", S.motionStyles, strings(fx["motionStyles"]))
        CT.check("the collar styles, in Settings order", CatRules.collarStyles, strings(fx["collarStyles"]))
        CT.checkTrue("follow is an override, never a style", !S.motionStyles.contains(S.follow) && !CatRules.collarStyles.contains(S.follow))

        CT.section("a fresh install: Shrimpy, Playful, collar off, no fur lines, 16 cats that follow the globals and are Balanced")
        CT.checkJSON("the defaults are the fixture's", got: S().json, want: fx["defaults"]!)
        CT.checkJSON("clean(nothing) is the defaults", got: S.clean(nil).json, want: fx["defaults"]!)
        CT.check("16 cats", S().cats.count, 16)

        CT.section("cleanCatSettings: \(rows(fx["cases"]).count) stored values, from nothing to a fully valid one")
        var diffs: [String] = []
        for c in rows(fx["cases"]) {
            let d = CT.diffs(S.clean(c["raw"]).json, c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("every case comes out as the fixture says", diffs)
        let valid = S.clean(rows(fx["cases"]).first { ($0["name"] as! String) == "a fully valid value" }!["raw"])
        CT.checkJSON("cleaning twice changes nothing", got: S.clean(valid.json).json, want: valid.json)

        CT.section("cleanPersonality: \(rows(fx["personalities"]).count) stored personalities (a string is JSON text)")
        diffs = []
        for c in rows(fx["personalities"]) {
            let d = CT.diffs(Personality.clean(c["raw"]).json, c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("every personality comes out as the fixture says", diffs)

        CT.section("a real NaN or Infinity (JSON cannot write them, a dictionary can)")
        let wild = Personality.clean(["energy": 7, "curiosity": -2, "chatty": Double.nan, "affection": Double.infinity, "sass": -Double.infinity, "mischief": 1e300] as [String: Any])
        CT.check("traits: 7 is 1, -2 is 0, NaN and the infinities are 0.5, 1e300 is 1", [wild.energy, wild.curiosity, wild.chatty, wild.affection, wild.sass, wild.mischief], [1, 0, 0.5, 0.5, 0.5, 1])
        CT.check("a NaN trait makes the preset Custom", wild.preset, "custom")
        CT.check("a NaN in the cat's own entry is 0.5 too", S.clean(["cats": ["momo": ["personality": ["energy": Double.nan]]]]).cats["momo"]!.personality.energy, 0.5)
        CT.checkTrue("minus zero is stored as zero", Personality.clean(["energy": -0.0]).energy.sign == .plus)
        var every = true
        for p in [wild, Personality.clean(["energy": Double.nan, "curiosity": Double.nan, "chatty": Double.nan, "affection": Double.nan, "sass": Double.nan, "mischief": Double.nan])] {
            every = every && [p.energy, p.curiosity, p.chatty, p.affection, p.sass, p.mischief].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
        }
        CT.checkTrue("nothing that comes out is NaN, infinite or outside 0 to 1", every)

        CT.section("JSON text is strict: Foundation's two extras are refused, and a comma inside a string is only text")
        CT.check("a comma before the closing brace is not JSON", Personality.clean("{\"energy\":0.2,}"), Personality.named("balanced"))
        CT.check("a byte-order mark is not JSON", Personality.clean("\u{FEFF}{\"energy\":0.2}"), Personality.named("balanced"))
        CT.check("a comma and a brace inside a string are only text", Personality.clean("{\"preset\":\",}\",\"energy\":0.2}").energy, 0.2)
        CT.check("so is an escaped quote followed by them", Personality.clean("{\"preset\":\"a\\\",}\",\"energy\":0.2}").energy, 0.2)
        CT.check("spaces and line breaks around the object are fine", Personality.clean(" \n{\"energy\" : 0.2 ,\n \"sass\":1}\n").sass, 1)

        CT.section("the edits of the Settings rows: each changes one thing, returns a clean value and never touches its input")
        let base = S.clean(["character": "momo", "motionStyle": "classic", "collar": "band", "furLines": true,
                            "cats": ["momo": ["motion": "playful", "collar": "off", "personality": Personality.slide(Personality.named("chill"), trait: "sass", value: 0.9).json]]])
        /// Where two settings differ, as paths of their JSON (`$.cats.momo.motion`).
        func changed(_ a: S, _ b: S) -> [String] { CT.diffs(a.json, b.json).map { String($0.prefix { $0 != ":" }) }.sorted() }
        let edits: [(String, S, [String])] = [
            ("the character", base.withCharacter("noodle"), ["$.character"]),
            ("an unknown character is Shrimpy", base.withCharacter("tiger"), ["$.character"]),
            ("the global motion style", base.withMotionStyle("playful"), ["$.motionStyle"]),
            ("follow is not a global style: Playful", base.withMotionStyle("follow"), ["$.motionStyle"]),
            ("the global collar", base.withCollar("kerchief"), ["$.collar"]),
            ("an unknown collar is off", base.withCollar("scarf"), ["$.collar"]),
            ("fur lines", base.withFurLines(false), ["$.furLines"]),
            ("a cat's own motion", base.withCatMotion("classic", for: "ginger"), ["$.cats.ginger.motion"]),
            ("a bad override is follow, which is what the cat had", base.withCatMotion("Classic", for: "ginger"), []),
            ("a cat's own collar", base.withCatCollar("tag", for: "ginger"), ["$.cats.ginger.collar"]),
            ("off is a collar override of its own", base.withCatCollar("off", for: "ginger"), ["$.cats.ginger.collar"]),
            ("an unknown cat is Shrimpy", base.withCatMotion("classic", for: "tiger"), ["$.cats.shrimpy.motion"]),
            ("a slider moves one trait and the preset", base.withPersonality(Personality.slide(base.cats["ginger"]!.personality, trait: "energy", value: 0.2), for: "ginger"), ["$.cats.ginger.personality.energy", "$.cats.ginger.personality.preset"]),
            ("a slider that is NaN changes nothing", base.withPersonality(Personality.slide(base.cats["ginger"]!.personality, trait: "energy", value: .nan), for: "ginger"), []),
        ]
        for (what, got, paths) in edits { CT.check(what, changed(base, got), paths) }
        CT.check("a preset moves the six traits of one cat and nothing else", changed(base, base.withPersonality(Personality.named("hyper"), for: "ginger")).allSatisfy { $0.hasPrefix("$.cats.ginger.personality.") }, true)
        CT.check("every edit returns a clean value", edits.allSatisfy { S.clean($0.1.json) == $0.1 }, true)
        CT.check("and the input is a value: it is as it was", base == S.clean(base.json), true)

        CT.section("Apply to every cat and the two resolvers")
        diffs = []
        for c in rows(fx["applyAll"]) {
            let out = S.clean(c["settings"]).applyingToAll(from: c["from"] as! String).json
            let d = CT.diffs(out, c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("\(rows(fx["applyAll"]).count) apply-to-all cases", diffs)
        diffs = []
        for c in rows(fx["derived"]) {
            let s = S.clean(c["settings"]), want = c["engineCfg"] as! [String: Any]
            let cfg = s.engineCfg
            var got: [String: Any] = ["motion": cfg.motion, "override": cfg.override]
            got["pers"] = cfg.pers.mapValues { $0.json }
            diffs += CT.diffs(got, want).map { "\(c["name"]!) engineCfg: \($0)" }
            diffs += CT.diffs(ids.map { s.motion(for: $0) }, c["motionFor"]!).map { "\(c["name"]!) motionFor: \($0)" }
            diffs += CT.diffs(ids.map { s.collar(for: $0) }, c["collarFor"]!).map { "\(c["name"]!) collarFor: \($0)" }
        }
        CT.checkRows("\(rows(fx["derived"]).count) derived cases: engineCfg, motionFor and collarFor", diffs)
        var one = S()
        one.cats["momo"]!.personality = Personality.slide(Personality.named("chill"), trait: "sass", value: 0.9)
        CT.check("applying one cat to all copies the personality (Custom stays Custom)", one.applyingToAll(from: "momo").cats["noodle"]!.personality.preset, "custom")
        CT.check("an unknown cat is Shrimpy", one.applyingToAll(from: "tiger").cats["noodle"]!.personality.preset, "balanced")

        CT.section("a stored personality is read by the clean-up and never decoded")
        CT.checkTrue("CatPersonality is not Decodable", !(CatPersonality.self is Decodable.Type))
        let dir = "NotchBuddy/Sources/App"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".swift") }) ?? []
        let decoders = files.filter { f in
            let text = (try? String(contentsOfFile: dir + "/" + f, encoding: .utf8)) ?? ""
            return text.contains("decode(CatPersonality") || text.contains("decode([String: CatPersonality")
        }
        CT.check("no source decodes a CatPersonality (\(files.count) files read)", decoders, [])
        let text = Personality.jsonText(Personality.slide(Personality.named("sweet"), trait: "energy", value: 0.27))
        CT.checkJSON("the text a personality is stored as reads back the same", got: Personality.clean(text).json, want: Personality.slide(Personality.named("sweet"), trait: "energy", value: 0.27).json)
        CT.check("and its keys are sorted, so the text is the same every time", text.hasPrefix("{\"affection\":1,"), true)

        CT.section("UserDefaults keys: cat.character, cat.motionStyle, cat.furLines, cat.collar, cat.motion.<id>, cat.collar.<id>, cat.personality.<id>")
        let mem = MemoryBacking()
        CT.checkJSON("an empty store loads as the defaults", got: S.load(from: mem).json, want: fx["defaults"]!)
        var s = S()
        s.character = "momo"; s.motionStyle = "classic"; s.collar = "band"; s.furLines = true
        s.cats["momo"]!.motion = "playful"; s.cats["momo"]!.collar = "off"
        s.cats["momo"]!.personality = Personality.slide(Personality.named("chill"), trait: "sass", value: 0.9)
        s.save(to: mem)
        CT.check("a first save writes every key (4 globals and 3 per cat)", mem.writes.count, 4 + 3 * 16)
        CT.check("the global keys", [mem.values["cat.character"] as? String, mem.values["cat.motionStyle"] as? String, mem.values["cat.collar"] as? String], ["momo", "classic", "band"])
        CT.check("fur lines is a real Bool", (mem.values["cat.furLines"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue }, true)
        CT.check("a cat's own words, follow included", [mem.values["cat.motion.momo"] as? String, mem.values["cat.collar.momo"] as? String, mem.values["cat.motion.shrimpy"] as? String], ["playful", "off", "follow"])
        CT.check("a personality is JSON text", (mem.values["cat.personality.momo"] as? String).map { $0.hasPrefix("{") }, true)
        CT.checkJSON("it loads back as it was saved", got: S.load(from: mem).json, want: s.json)
        var t = s
        t.cats["momo"]!.personality = Personality.slide(t.cats["momo"]!.personality, trait: "energy", value: 0.3)
        let before = mem.writes.count
        t.save(to: mem, replacing: s)
        CT.check("a change writes only what changed", Array(mem.writes.dropFirst(before)), ["cat.personality.momo"])
        t.save(to: mem, replacing: t)
        CT.check("and a save with nothing new writes nothing", mem.writes.count, before + 1)

        CT.section("a store that is wrong in every way still loads")
        let bad = MemoryBacking()
        bad.values = ["cat.character": 7, "cat.motionStyle": "Classic", "cat.collar": "scarf", "cat.furLines": 1, "cat.motion.momo": "bogus", "cat.collar.momo": ["tag"],
                      "cat.personality.momo": "{", "cat.personality.ginger": "{\"energy\":9,\"preset\":\"chill\"}", "cat.personality.shrimpy": Data("not json".utf8),
                      "cat.motion.tiger": "classic", "cat.personality.noodle": 42]
        let loaded = S.load(from: bad)
        CT.check("the globals fall back", [loaded.character, loaded.motionStyle, loaded.collar, "\(loaded.furLines)"], ["shrimpy", "playful", "off", "false"])
        CT.check("a bad override is follow", [loaded.cats["momo"]!.motion, loaded.cats["momo"]!.collar], ["follow", "follow"])
        CT.check("bad JSON, bytes that are not JSON and a number are Balanced", [loaded.cats["momo"]!.personality, loaded.cats["shrimpy"]!.personality, loaded.cats["noodle"]!.personality], [Personality.named("balanced"), Personality.named("balanced"), Personality.named("balanced")])
        CT.check("an out-of-range trait is held and the name no longer matches", [loaded.cats["ginger"]!.personality.energy, loaded.cats["ginger"]!.personality.chatty], [1, 0.5])
        CT.check("a preset name whose traits changed is custom", loaded.cats["ginger"]!.personality.preset, "custom")
        CT.check("there are still 16 cats and no tiger", [loaded.cats.count, loaded.cats["tiger"] == nil ? 1 : 0], [16, 1])
        CT.finish()
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-settings.sh 2>&1 | head -3`
Expected: FAIL: `<unknown>:0: error: error opening input file 'NotchBuddy/Sources/App/CatSettings.swift' (No such file or directory)`.

- [ ] **Step 3: Write the implementation**

Three notes on what these edits do, because two of them are found by the fixture and not by reading the spec. **Foundation's `JSONSerialization` accepts a comma before a closing brace or bracket and a byte-order mark** (`{"energy":0.2,}` reads as 0.2); `JSON.parse` and every other strict parser refuse both, and the fixture's row "a trailing comma" must be Balanced, so `isStrictJSON` refuses them before the parser runs. **`clamp(-0.0, 0, 1)` keeps the minus sign**, which would be stored as `-0`; `+ 0` turns it into 0. And `CatPersonality` loses `Decodable` on purpose: a stored personality is read by `Personality.clean`, so a `JSONDecoder().decode(CatPersonality…)` cannot compile.

**Edit `NotchBuddy/Sources/App/CatRules.swift`**, find this text (it occurs exactly once):

```swift
    static func wakes(_ kind: String) -> Bool { wakeEvents.contains(kind) }

    /// Tool names that mean "searching" (exact, case-sensitive match on the tool name the hook relay delivers).
    static let searchTools: [String: [String]] = [
```

and replace it with:

```swift
    static func wakes(_ kind: String) -> Bool { wakeEvents.contains(kind) }

    /// The collar styles, frozen contract values that Settings stores, in this order: Band and tag, Band, Neckerchief, and Off (the default).
    static let collarStyles = ["tag", "band", "kerchief", "off"]
    /// A stored collar style to a style. An unknown ID, or anything that is not a string, falls back to "off".
    static func collarStyleOf(_ v: Any?) -> String { (v as? String).flatMap { collarStyles.contains($0) ? $0 : nil } ?? "off" }

    /// Tool names that mean "searching" (exact, case-sensitive match on the tool name the hook relay delivers).
    static let searchTools: [String: [String]] = [
```

**Create `NotchBuddy/Sources/App/CatSettings.swift`**:

```swift
import Foundation

// What the Cat section of Settings saves, and how it is cleaned. Port of the "Stored settings" section of design/prototype/cat-core.js
// (the tie-breaker); tests/fixtures/cat/settings-cases.json pins it. A settings file can be hand-edited, copied from an older build or
// half written, so everything read back goes through `CatSettings.clean` before anything else sees it: raw in, clean out, never a throw.
// Foundation only. The UserDefaults keys are in `CatSettings.Key`, and the app's store (`CatSettingsStore`) is in its own file.

/// What the settings need from a store: `UserDefaults` in the app, a dictionary in the tests, so a test run never writes a preferences file.
protocol CatSettingsBacking {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: CatSettingsBacking {}

struct CatSettings: Equatable, Sendable {
    /// "No override: use the global setting." Stored as this word. It is not a motion style and not a collar style.
    static let follow = "follow"
    /// The motion styles, in the order Settings lists them. Playful is the default; an unknown stored style plays Playful.
    static let motionStyles = ["playful", "classic"]

    /// One cat's own settings: a motion override, a collar override (each "follow" or a style) and its personality.
    struct Entry: Equatable, Sendable {
        var motion = CatSettings.follow
        var collar = CatSettings.follow
        var personality = CatPersonality()
    }

    /// The cat shown in the notch and in the small pills. One of the 16 IDs.
    var character = "shrimpy"
    var motionStyle = "playful"
    /// The collar style for every cat: "tag", "band", "kerchief" or "off" (the default).
    var collar = "off"
    var furLines = false
    /// All 16 cats, always, by ID.
    var cats: [String: Entry] = Dictionary(uniqueKeysWithValues: CatPresets.ids.map { ($0, Entry()) })

    // MARK: Stored words

    /// A stored global motion style to "playful" or "classic"; anything else is "playful".
    static func motionStyleOf(_ v: Any?) -> String { (v as? String).flatMap { motionStyles.contains($0) ? $0 : nil } ?? "playful" }
    /// A cat's own motion: "follow", "playful" or "classic"; anything else is "follow" (no valid override).
    static func motionOverrideOf(_ v: Any?) -> String { (v as? String).flatMap { motionStyles.contains($0) ? $0 : nil } ?? follow }
    /// A cat's own collar: "follow" or one of the four styles ("off" is an override like any other); anything else is "follow".
    static func collarOverrideOf(_ v: Any?) -> String { (v as? String).flatMap { CatRules.collarStyles.contains($0) ? $0 : nil } ?? follow }
    /// A stored cat ID to one of the 16 IDs; anything else (a kitten, a wrong case, a number) is "shrimpy".
    static func catIdOf(_ v: Any?) -> String { (v as? String).flatMap { CatPresets.ids.contains($0) ? $0 : nil } ?? "shrimpy" }

    /// Fur lines are on only for a real boolean true. `1` and "true" are off: `UserDefaults.bool(forKey:)` would say yes to both, so the
    /// stored object is read as it is.
    private static func isTrue(_ v: Any?) -> Bool {
        guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return false }
        return n.boolValue
    }

    // MARK: Cleaning

    /// Everything Settings saves, cleaned. `raw` is a dictionary shaped like
    /// `{character, motionStyle, collar, furLines, cats: {<id>: {motion, collar, personality}}}`; anything else gives the defaults. Never throws;
    /// unknown keys and unknown cats are dropped; the result always holds all 16 cats. Each personality goes through `Personality.clean`.
    static func clean(_ raw: Any?) -> CatSettings {
        let r = raw as? [String: Any] ?? [:], stored = r["cats"] as? [String: Any] ?? [:]
        var out = CatSettings()
        out.character = catIdOf(r["character"])
        out.motionStyle = motionStyleOf(r["motionStyle"])
        out.collar = CatRules.collarStyleOf(r["collar"])
        out.furLines = isTrue(r["furLines"])
        for id in CatPresets.ids {
            let c = stored[id] as? [String: Any] ?? [:]
            out.cats[id] = Entry(motion: motionOverrideOf(c["motion"]), collar: collarOverrideOf(c["collar"]), personality: Personality.clean(c["personality"]))
        }
        return out
    }

    /// "Apply to every cat": every cat gets the motion override, collar override and personality of cat `id` (an unknown ID is Shrimpy). The
    /// character and the global settings stay. A cat that follows keeps following (what is stored is copied, not what is in force).
    func applyingToAll(from id: String) -> CatSettings {
        var out = self
        let from = cats[CatSettings.catIdOf(id)] ?? Entry()
        for c in CatPresets.ids { out.cats[c] = from }
        return out
    }

    /// The motion style a cat plays: its own override, else the global style.
    func motion(for id: String) -> String {
        let m = (cats[CatSettings.catIdOf(id)] ?? Entry()).motion
        return m == CatSettings.follow ? motionStyle : m
    }

    /// The collar style a cat wears (when it has a colour to wear): its own override, else the global style.
    func collar(for id: String) -> String {
        let c = (cats[CatSettings.catIdOf(id)] ?? Entry()).collar
        return c == CatSettings.follow ? collar : c
    }

    /// The shared settings an engine reads (the `CatConfig` fields, without the zoomies clock): the global style, an override for each cat that has
    /// one, and every cat's personality.
    struct EngineCfg: Equatable {
        var motion: String
        var override: [String: String]
        var pers: [String: CatPersonality]
    }
    var engineCfg: EngineCfg {
        var override: [String: String] = [:], pers: [String: CatPersonality] = [:]
        for id in CatPresets.ids {
            guard let c = cats[id] else { continue }
            if c.motion != CatSettings.follow { override[id] = c.motion }
            pers[id] = c.personality
        }
        return EngineCfg(motion: motionStyle, override: override, pers: pers)
    }

    /// The settings as the fixtures hold them, a JSON-shaped dictionary.
    var json: [String: Any] {
        var out: [String: Any] = [:]
        for id in CatPresets.ids {
            guard let c = cats[id] else { continue }
            out[id] = ["motion": c.motion, "collar": c.collar, "personality": c.personality.json] as [String: Any]
        }
        return ["character": character, "motionStyle": motionStyle, "collar": collar, "furLines": furLines, "cats": out]
    }

    // MARK: Edits

    /// What one row of Settings changes. Each takes this clean value and returns a new clean one with one thing changed (an unknown value is the neutral
    /// one, an unknown cat is Shrimpy, a trait is held to 0 to 1), so a row can only change its own field; the input is a value and is never touched.
    func withCharacter(_ id: String) -> CatSettings { var s = self; s.character = CatSettings.catIdOf(id); return s }
    func withMotionStyle(_ style: String) -> CatSettings { var s = self; s.motionStyle = CatSettings.motionStyleOf(style); return s }
    func withCollar(_ style: String) -> CatSettings { var s = self; s.collar = CatRules.collarStyleOf(style); return s }
    func withFurLines(_ on: Bool) -> CatSettings { var s = self; s.furLines = on; return s }
    /// "follow", "playful" or "classic" for one cat.
    func withCatMotion(_ word: String, for id: String) -> CatSettings {
        var s = self; s.cats[CatSettings.catIdOf(id)]?.motion = CatSettings.motionOverrideOf(word); return s
    }
    /// "follow" or a style for one cat ("off" is a style: this cat wears no collar while the global one is on).
    func withCatCollar(_ word: String, for id: String) -> CatSettings {
        var s = self; s.cats[CatSettings.catIdOf(id)]?.collar = CatSettings.collarOverrideOf(word); return s
    }
    /// A personality for one cat (a preset, or the result of moving a slider), cleaned.
    func withPersonality(_ p: CatPersonality, for id: String) -> CatSettings {
        var s = self; s.cats[CatSettings.catIdOf(id)]?.personality = Personality.sanitized(p.json); return s
    }

    // MARK: UserDefaults

    /// The keys: `cat.character`, `cat.motionStyle`, `cat.furLines`, `cat.collar`, and per cat `cat.motion.<id>`, `cat.collar.<id>` and
    /// `cat.personality.<id>` (the personality as JSON text).
    enum Key {
        static let character = "cat.character", motionStyle = "cat.motionStyle", furLines = "cat.furLines", collar = "cat.collar"
        static func motion(_ id: String) -> String { "cat.motion.\(id)" }
        static func collar(_ id: String) -> String { "cat.collar.\(id)" }
        static func personality(_ id: String) -> String { "cat.personality.\(id)" }
    }

    /// What is stored, cleaned. Only the keys that are there are read, and each as the object it is (a `furLines` of `1` stays a number, so the
    /// clean-up can refuse it). Nothing here can throw.
    static func load(from store: any CatSettingsBacking) -> CatSettings {
        var raw: [String: Any] = [:], cats: [String: Any] = [:]
        for (key, field) in [(Key.character, "character"), (Key.motionStyle, "motionStyle"), (Key.collar, "collar"), (Key.furLines, "furLines")] {
            if let v = store.object(forKey: key) { raw[field] = v }
        }
        for id in CatPresets.ids {
            var c: [String: Any] = [:]
            for (key, field) in [(Key.motion(id), "motion"), (Key.collar(id), "collar"), (Key.personality(id), "personality")] {
                if let v = store.object(forKey: key) { c[field] = v }
            }
            if !c.isEmpty { cats[id] = c }
        }
        raw["cats"] = cats
        return clean(raw)
    }

    /// Every stored key with the value it is stored as.
    private func stored() -> [String: AnyHashable] {
        var m: [String: AnyHashable] = [Key.character: character, Key.motionStyle: motionStyle, Key.collar: collar, Key.furLines: furLines]
        for id in CatPresets.ids {
            guard let c = cats[id] else { continue }
            m[Key.motion(id)] = c.motion; m[Key.collar(id)] = c.collar; m[Key.personality(id)] = Personality.jsonText(c.personality)
        }
        return m
    }

    /// Writes what differs from `old` (everything, when there is no `old`). `follow` is stored as the word, and a personality as the JSON text of
    /// the clean object. Only a cleaned value is ever passed in, so nothing that did not go through the clean-up is stored.
    func save(to store: any CatSettingsBacking, replacing old: CatSettings? = nil) {
        let was = old?.stored() ?? [:]
        for (key, value) in stored().sorted(by: { $0.key < $1.key }) where was[key] != value { store.set(value.base, forKey: key) }
    }
}
```

**Edit `NotchBuddy/Sources/App/Personality.swift`**, find this text (it occurs exactly once):

```swift

/// A cat's personality as it is stored: a preset name plus the six traits. Moving a slider makes the preset "custom".
struct CatPersonality: Codable, Equatable, Sendable {
    var preset = "balanced"
    var energy = 0.5
```

and replace it with:

```swift

/// A cat's personality as it is stored: a preset name plus the six traits. Moving a slider makes the preset "custom".
/// Encodable only, on purpose: a stored personality is read by `Personality.clean` and never decoded, because Codable's decoding throws on a value
/// that is bad JSON or has the wrong types, and a settings file can hold anything.
struct CatPersonality: Encodable, Equatable, Sendable {
    var preset = "balanced"
    var energy = 0.5
```

**Edit `NotchBuddy/Sources/App/Personality.swift`**, find this text (it occurs exactly once):

```swift
    var sass = 0.5
    var mischief = 0.5

    /// A trait by its key; nil for a name that is not a trait.
```

and replace it with:

```swift
    var sass = 0.5
    var mischief = 0.5

    /// The personality as the fixtures hold it, a JSON-shaped dictionary.
    var json: [String: Any] {
        ["preset": preset, "energy": energy, "curiosity": curiosity, "chatty": chatty, "affection": affection, "sass": sass, "mischief": mischief]
    }

    /// A trait by its key; nil for a name that is not a trait.
```

**Edit `NotchBuddy/Sources/App/Personality.swift`**, find this text (it occurs exactly once):

```swift
    }

    /// Traits as a settings file can hold them (anything at all): a missing, non-numeric or NaN trait becomes 0.5, anything else is
    /// held to 0…1. The preset name is kept when it is a string.
    static func sanitized(_ raw: [String: Any]) -> CatPersonality {
        var p = CatPersonality()
```

and replace it with:

```swift
    }

    /// Traits as a settings file can hold them (anything at all): a missing, non-numeric, NaN or infinite trait becomes 0.5, anything else is
    /// held to 0…1. The preset name is kept only when it names one of the six presets and the traits are still that preset's (within 1e-9);
    /// anything else, a missing or unknown name included, is "custom". This is the contract's `cleanPersonality`
    /// (tests/fixtures/cat/settings-cases.json pins it).
    static func sanitized(_ raw: [String: Any]) -> CatPersonality {
        var p = CatPersonality()
```

**Edit `NotchBuddy/Sources/App/Personality.swift`**, find this text (it occurs exactly once):

```swift
            var v = 0.5
            if let n = raw[t.key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite { v = n.doubleValue }
            p[t.key] = clamp(v, 0, 1)
        }
        p.preset = (raw["preset"] as? String) ?? "custom"
        return p
    }

```

and replace it with:

```swift
            var v = 0.5
            if let n = raw[t.key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite { v = n.doubleValue }
            p[t.key] = clamp(v, 0, 1) + 0   // + 0 turns a minus zero into 0
        }
        if let name = raw["preset"] as? String, let preset = presets.first(where: { $0.key == name }),
           traits.allSatisfy({ abs((p[$0.key] ?? 0.5) - (preset.traits[$0.key] ?? 0.5)) <= 1e-9 }) {
            p.preset = name
        } else {
            p.preset = "custom"
        }
        return p
    }

    /// A stored personality, whatever it is: an object, or the JSON text (or the bytes) of one. Text that is not JSON, and JSON that is not an
    /// object, give Balanced; an object goes through `sanitized`. Never throws. Every personality read from a settings file comes through here.
    static func clean(_ raw: Any?) -> CatPersonality {
        var v = raw
        if let text = v as? String { v = Data(text.utf8) }
        if let data = v as? Data { v = isStrictJSON(data) ? try? JSONSerialization.jsonObject(with: data) : nil }
        guard let object = v as? [String: Any] else { return named("balanced") }
        return sanitized(object)
    }

    /// The contract says text that is not strict JSON is not JSON. Foundation's parser also takes a comma before a closing brace or bracket and a
    /// byte-order mark, which `JSON.parse` and every other strict parser refuse, so those two are refused here before it runs.
    static func isStrictJSON(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return false }
        var inString = false, escaped = false, comma = false
        for c in bytes {
            if inString {
                if escaped { escaped = false } else if c == 0x5C { escaped = true } else if c == 0x22 { inString = false }
                continue
            }
            switch c {
            case 0x22: inString = true; comma = false
            case 0x2C: comma = true
            case 0x20, 0x09, 0x0A, 0x0D: break
            case 0x7D, 0x5D: if comma { return false }
            default: comma = false
            }
        }
        return true
    }

    /// The text a personality is stored as: its JSON, keys sorted so the same personality is always the same text.
    static func jsonText(_ p: CatPersonality) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? String(data: encoder.encode(p), encoding: .utf8)) ?? "{}"
    }

```

- [ ] **Step 4: Run the tests**

Run: `bash scripts/test-cat-settings.sh 2>&1 | grep -E "✗|passed|failed"; bash scripts/test-cat-settings.sh 2>&1 | grep -c "✓"`
Expected: `All tests passed.` and `61`.

Run: `for t in personality rules engine; do printf '%-12s' $t; bash scripts/test-cat-$t.sh 2>&1 | tail -1; done`
Expected: three lines ending `All tests passed.` (the preset rule changed in `sanitized`; the fixtures of stages 1 to 4 still hold).

- [ ] **Step 5: Prove the strict-JSON test bites (not committed)**

```bash
python3 - <<'PY'
p = 'NotchBuddy/Sources/App/Personality.swift'
s = open(p, encoding='utf-8').read()
was = 'v = isStrictJSON(data) ? try? JSONSerialization.jsonObject(with: data) : nil'
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, 'v = try? JSONSerialization.jsonObject(with: data)'))
PY
bash scripts/test-cat-settings.sh 2>&1 | grep -E "✗|failed"
python3 - <<'PY'
p = 'NotchBuddy/Sources/App/Personality.swift'
s = open(p, encoding='utf-8').read()
was = 'v = try? JSONSerialization.jsonObject(with: data)'
assert s.count(was) == 1
open(p, 'w', encoding='utf-8').write(s.replace(was, 'v = isStrictJSON(data) ? try? JSONSerialization.jsonObject(with: data) : nil'))
PY
bash scripts/test-cat-settings.sh 2>&1 | tail -1
```

Expected: first run `✗ every personality comes out as the fixture says (1 differences)`, `✗ a comma before the closing brace is not JSON`, `✗ a byte-order mark is not JSON` and `3 test(s) failed.`; after putting the line back, `All tests passed.`

- [ ] **Step 6: Commit**

Run: `git status --short`
Expected: ` M NotchBuddy/Sources/App/CatRules.swift`, ` M NotchBuddy/Sources/App/Personality.swift`, `?? NotchBuddy/Sources/App/CatSettings.swift`, `?? scripts/test-cat-settings.sh` and `?? tests/CatSettingsTests.swift`, and nothing else (in a dry-run clone where A-0d was applied but not committed, A-0d's own files show too).

```bash
git add NotchBuddy/Sources/App/CatSettings.swift NotchBuddy/Sources/App/Personality.swift NotchBuddy/Sources/App/CatRules.swift tests/CatSettingsTests.swift scripts/test-cat-settings.sh
git commit -m "feat(cat): the stored cat settings are cleaned in Swift (cleanCatSettings), and a stored personality is never decoded

A port of A-0d's clean-up, replayed against settings-cases.json, with a real NaN test and the UserDefaults keys through a
dictionary store. Personality.sanitized keeps a preset name only while the traits still match it. Foundation's JSON parser
takes a trailing comma and a byte-order mark, so both are refused first. CatPersonality is Encodable only.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Settings feed the engines: the store, `CatConfig`, the live character (stage 5)

**Agent:** `nm-implementer`. The code is given in full; the build and the existing tests are what to read.

**Files:**
- Create: `NotchBuddy/Sources/App/CatSettingsStore.swift`, `tests/CatSettingsSupport.swift`, `tests/CatSettingsStoreTests.swift`, `scripts/test-cat-settings-store.sh`
- Modify: `NotchBuddy/Sources/App/CatEngine.swift` (`CatConfig.furLines`, `CatEngine.p` becomes settable only through `useCharacter`), `NotchBuddy/Sources/App/AppDelegate.swift`, `NotchBuddy/Sources/App/BotCanvasView.swift`, `NotchBuddy/Sources/App/GreetingCanvasView.swift`, `NotchBuddy/Sources/App/UploadCanvasView.swift`, `tests/CatSettingsTests.swift`, `scripts/test-cat-settings.sh`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (by `xcodegen`)

**Interfaces:**
- Consumes: Task 1's `CatSettings`, `CatSettingsBacking`, `Personality.slide`/`named`.
- Produces `CatSettingsStore` (`@MainActor`, `ObservableObject`): `static let shared`, `init(backing:config:)`, `settings`, `config`, `update(_:)`, `setCharacter`, `setMotionStyle`, `setMotionOverride(_:for:)`, `setPreset(_:for:)`, `setTrait(_:_:for:)`, `setFurLines`, `applyToAll(from:)` (each row's setter is one of Task 1's pure edits inside `update`); `CatConfig.apply(_ s: CatSettings)` and `CatConfig.furLines`; `CatEngine.useCharacter(_ id: String)`.

- [ ] **Step 1: Write the failing tests**

The dictionary store moves into a support file both settings programs share. The new program builds a store on a dictionary and a `CatConfig` of its own (never `shared`, never a suite), changes settings and watches engines built on that config.

**Create `scripts/test-cat-settings-store.sh`**:

```bash
#!/usr/bin/env bash
# Cat settings in the app: the store loads what is stored (through an injected dictionary, never a UserDefaults suite), hands it to the engines
# through CatConfig, saves only what changed, and the character switches a running engine.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-settings-store.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatSettings.swift $APP/CatSettingsStore.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/CatSettingsStoreTests.swift \
    -o "$TEST_DIR/cat-settings-store-tests"
"$TEST_DIR/cat-settings-store-tests"
```

**Edit `scripts/test-cat-settings.sh`**, find this text (it occurs exactly once):

```bash
    NotchBuddy/Sources/App/CatMath.swift NotchBuddy/Sources/App/CatPresets.swift NotchBuddy/Sources/App/Personality.swift \
    NotchBuddy/Sources/App/CatRules.swift NotchBuddy/Sources/App/CatSettings.swift \
    tests/CatTestSupport.swift tests/CatSettingsTests.swift \
    -o "$TEST_DIR/cat-settings-tests"
"$TEST_DIR/cat-settings-tests"
```

and replace it with:

```bash
    NotchBuddy/Sources/App/CatMath.swift NotchBuddy/Sources/App/CatPresets.swift NotchBuddy/Sources/App/Personality.swift \
    NotchBuddy/Sources/App/CatRules.swift NotchBuddy/Sources/App/CatSettings.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/CatSettingsTests.swift \
    -o "$TEST_DIR/cat-settings-tests"
"$TEST_DIR/cat-settings-tests"
```

**Create `tests/CatSettingsStoreTests.swift`**:

```swift
import Foundation

@main
enum CatSettingsStoreTests {
    /// Values of different types, as text, so one check can compare them.
    static func d(_ xs: Any...) -> [String] { xs.map { "\($0)" } }

    @MainActor static func engine(_ id: String, _ cfg: CatConfig) -> CatEngine {
        CatEngine(CatPresets.byID(id), now: { 0 }, rand: { 0.5 }, cfg: cfg, quiet: true)
    }

    @MainActor static func main() {
        CT.section("the store starts from what is stored and hands it to the engines")
        let mem = MemoryBacking()
        mem.values = ["cat.character": "momo", "cat.motionStyle": "classic", "cat.motion.shrimpy": "playful",
                      "cat.personality.momo": Personality.jsonText(Personality.named("chill"))]
        let cfg = CatConfig()
        let store = CatSettingsStore(backing: mem, config: cfg)
        CT.check("the character", [store.settings.character, cfg.character], ["momo", "momo"])
        CT.check("the global motion style", cfg.motion, "classic")
        CT.check("only the cat with its own motion has an override", cfg.override, ["shrimpy": "playful"])
        CT.check("every cat has a personality", cfg.pers.count, 16)
        CT.check("Momo is Chill", cfg.pers["momo"], Personality.named("chill"))
        CT.check("a cat that follows plays the global style, one with its own plays that", [engine("momo", cfg).motion, engine("shrimpy", cfg).motion], ["classic", "playful"])
        CT.check("a kitten plays its parent's style and wears its parent's personality", [engine("momo", cfg).pers.preset, CatEngine(CatPresets.kitten(of: CatPresets.byID("shrimpy")), now: { 0 }, rand: { 0.5 }, cfg: cfg, quiet: true).motion], ["chill", "playful"])
        CT.check("nothing was written yet", mem.writes, [])

        CT.section("a change in Settings reaches a running engine on its next frame")
        let momo = engine("momo", cfg)
        store.setMotionStyle("playful")
        CT.check("the global style", [cfg.motion, momo.motion], ["playful", "playful"])
        store.setMotionOverride("classic", for: "momo")
        CT.check("a cat's own motion", [momo.motion, engine("ginger", cfg).motion], ["classic", "playful"])
        store.setMotionOverride("follow", for: "momo")
        CT.check("and follow gives it back", momo.motion, "playful")
        store.setPreset("hyper", for: "momo")
        CT.check("a preset", d(momo.pers.preset, momo.pers.energy), d("hyper", 1.0))
        store.setTrait("sass", 0.9, for: "momo")
        CT.check("a slider turns the preset into Custom and moves one trait", d(momo.pers.preset, momo.pers.sass, momo.pers.energy), d("custom", 0.9, 1.0))
        store.setFurLines(true)
        CT.check("fur lines", [store.settings.furLines, cfg.furLines], [true, true])
        store.applyToAll(from: "momo")
        CT.check("Apply to every cat copies the personality", d(engine("noodle", cfg).pers.preset, engine("noodle", cfg).pers.sass), d("custom", 0.9))
        store.setCharacter("noodle")
        CT.check("the character", cfg.character, "noodle")

        CT.section("what is written is only what changed, and only a cleaned value")
        let before = mem.writes.count
        store.setTrait("sass", 0.4, for: "latte")
        CT.check("one slider move writes one key", Array(mem.writes.dropFirst(before)), ["cat.personality.latte"])
        store.setTrait("sass", 0.4, for: "latte")
        CT.check("the same move again writes nothing", mem.writes.count, before + 1)
        store.update { $0.character = "tiger"; $0.motionStyle = "bogus"; $0.cats["ginger"]!.personality.energy = 7; $0.cats["ginger"]!.motion = "Classic" }
        CT.check("a bad value is cleaned before it is stored or used", d(store.settings.character, store.settings.motionStyle, store.settings.cats["ginger"]!.personality.energy, store.settings.cats["ginger"]!.motion),
                 d("shrimpy", "playful", 1.0, "follow"))
        CT.check("it is stored cleaned too: Shrimpy, and a held trait with its preset turned Custom", d(mem.values["cat.character"] ?? "-", Personality.clean(mem.values["cat.personality.ginger"]).energy, Personality.clean(mem.values["cat.personality.ginger"]).preset),
                 d("shrimpy", 1.0, "custom"))
        CT.check("the bad motion word was never written (follow is the same as no key)", mem.values["cat.motion.ginger"] == nil, true)
        CT.checkJSON("a second store on the same keys reads the same settings back", got: CatSettingsStore(backing: mem, config: CatConfig()).settings.json, want: store.settings.json)

        CT.section("the character switches a live engine without a restart")
        let e = engine("shrimpy", cfg)
        e.setState(.working)
        let pose = e.s
        e.useCharacter("momo")
        CT.check("Momo", e.p.name, "momo")
        CT.check("the state and the pose stay", [e.state.rawValue, "\(e.s.yaw)"], ["working", "\(pose.yaw)"])
        e.useCharacter("momo")
        e.useCharacter("tiger")
        CT.check("an unknown ID is Shrimpy", e.p.name, "shrimpy")
        CT.finish()
    }
}
```

**Create `tests/CatSettingsSupport.swift`**:

```swift
import Foundation

/// A settings store that lives in a dictionary, so a test run never writes a preferences file. It counts the writes, in order.
final class MemoryBacking: CatSettingsBacking {
    var values: [String: Any] = [:]
    private(set) var writes: [String] = []
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { writes.append(key); values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}
```

**Edit `tests/CatSettingsTests.swift`**, find this text (it occurs exactly once):

```swift
import Foundation

/// A settings store that lives in a dictionary, so a test run never writes a preferences file. It counts the writes.
final class MemoryBacking: CatSettingsBacking {
    var values: [String: Any] = [:]
    private(set) var writes: [String] = []
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { writes.append(key); values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}

@main
```

and replace it with:

```swift
import Foundation

@main
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash scripts/test-cat-settings-store.sh 2>&1 | head -3; bash scripts/test-cat-settings.sh 2>&1 | tail -1`
Expected: the first prints `<unknown>:0: error: error opening input file 'NotchBuddy/Sources/App/CatSettingsStore.swift' (No such file or directory)`; the second still ends `All tests passed.` (the support file serves it).

- [ ] **Step 3: Write the store and the engine's side**

`CatConfig` is what every engine reads on every frame (its motion style, its override and personality by cat ID), so handing it the settings is all it takes for a slider to move a cat in the notch. `useCharacter` switches the coat of a running engine without touching its state, pose or schedule, and an unknown ID is Shrimpy.

**Edit `NotchBuddy/Sources/App/CatEngine.swift`**, find this text (it occurs exactly once):

```swift
final class CatConfig {
    static let shared = CatConfig()
    /// The cat shown in the notch and in the small pills (Settings arrives in stage 5; Shrimpy is the default).
    var character = "shrimpy"
    var motion: String
```

and replace it with:

```swift
final class CatConfig {
    static let shared = CatConfig()
    /// The cat shown in the notch and in the small pills (Settings → Cat → Character; Shrimpy is the default).
    var character = "shrimpy"
    var motion: String
```

**Edit `NotchBuddy/Sources/App/CatEngine.swift`**, find this text (it occurs exactly once):

```swift
    var pers: [String: CatPersonality]
    var zoomAfter: Double

    init(motion: String = "playful", override: [String: String] = [:], pers: [String: CatPersonality] = [:], zoomAfter: Double = CatRules.zoomAfterMs) {
```

and replace it with:

```swift
    var pers: [String: CatPersonality]
    var zoomAfter: Double
    /// Settings → Cat → Fur lines: the optional fur strands on a big cat.
    var furLines = false

    init(motion: String = "playful", override: [String: String] = [:], pers: [String: CatPersonality] = [:], zoomAfter: Double = CatRules.zoomAfterMs) {
```

**Edit `NotchBuddy/Sources/App/CatEngine.swift`**, find this text (it occurs exactly once):

```swift
@MainActor
final class CatEngine: ObservableObject {
    let p: CatPreset
    let mini: Bool
    let now: () -> Double
```

and replace it with:

```swift
@MainActor
final class CatEngine: ObservableObject {
    /// The coat. It changes only through `useCharacter`, when the user picks another cat in Settings.
    private(set) var p: CatPreset
    let mini: Bool
    let now: () -> Double
```

**Edit `NotchBuddy/Sources/App/CatEngine.swift`**, find this text (it occurs exactly once):

```swift
    /// What this cat's personality changes.
    func pm() -> CatMultipliers { Personality.multipliers(pers) }

    func u(_ a: Double, _ b: Double) -> Double { a + rand() * (b - a) }
```

and replace it with:

```swift
    /// What this cat's personality changes.
    func pm() -> CatMultipliers { Personality.multipliers(pers) }

    /// Turns this cat into another coat: the one picked in Settings. Nothing else changes (the state, the pose and the schedule stay), so a
    /// running engine shows the new cat on its next frame. An unknown ID is Shrimpy, like a stored one.
    func useCharacter(_ id: String) {
        let next = CatPresets.byID(id)
        if next.name != p.name { p = next }
    }

    func u(_ a: Double, _ b: Double) -> Double { a + rand() * (b - a) }
```

**Create `NotchBuddy/Sources/App/CatSettingsStore.swift`**:

```swift
import Combine
import Foundation

// The app's cat settings: loaded from the store (UserDefaults in the app) when the app starts, handed to the engines through `CatConfig`, and
// saved on every change. Every value goes through `CatSettings.clean` on the way in, so nothing that did not is stored or used. The pure
// part (the clean-up, the keys, load and save) is `CatSettings`; this is the app's single holder of the result.

extension CatConfig {
    /// The settings the engines read: the character, the motion style, each cat's own motion and every personality (engines look them up by
    /// cat ID on every frame, so a change shows on the next one), and the fur-lines switch.
    func apply(_ s: CatSettings) {
        let e = s.engineCfg
        character = s.character
        motion = e.motion
        override = e.override
        pers = e.pers
        furLines = s.furLines
    }
}

@MainActor
final class CatSettingsStore: ObservableObject {
    /// The app's settings, on `UserDefaults.standard` and `CatConfig.shared`. Tests build their own store on a dictionary and a `CatConfig` of their own.
    static let shared = CatSettingsStore()

    @Published private(set) var settings: CatSettings
    private let backing: any CatSettingsBacking
    private let config: CatConfig

    init(backing: any CatSettingsBacking = UserDefaults.standard, config: CatConfig = .shared) {
        self.backing = backing
        self.config = config
        settings = CatSettings.load(from: backing)
        config.apply(settings)
    }

    /// Changes the settings. The closure edits a copy; the copy is cleaned (an unknown cat is Shrimpy, a trait is held to 0 to 1, a bad word is
    /// the neutral one), and when it differs from what is held it is published, saved (only the keys that changed) and handed to the engines.
    func update(_ change: (inout CatSettings) -> Void) {
        var next = settings
        change(&next)
        next = CatSettings.clean(next.json)
        guard next != settings else { return }
        next.save(to: backing, replacing: settings)
        settings = next
        config.apply(next)
    }

    // MARK: The Settings rows

    // Each row of Settings is one of the pure edits of `CatSettings` (`withCharacter` and the others), so a row can only change its own field.
    func setCharacter(_ id: String) { update { $0 = $0.withCharacter(id) } }
    func setMotionStyle(_ style: String) { update { $0 = $0.withMotionStyle(style) } }
    /// "follow", "playful" or "classic" for one cat.
    func setMotionOverride(_ word: String, for id: String) { update { $0 = $0.withCatMotion(word, for: id) } }
    /// One of the six presets for one cat (an unknown name is Balanced).
    func setPreset(_ key: String, for id: String) { update { $0 = $0.withPersonality(Personality.named(key), for: id) } }
    /// Moves one slider of one cat: the value is held to 0 to 1 and the preset becomes "custom".
    func setTrait(_ trait: String, _ value: Double, for id: String) {
        update { s in
            guard let p = s.cats[CatSettings.catIdOf(id)]?.personality else { return }
            s = s.withPersonality(Personality.slide(p, trait: trait, value: value), for: id)
        }
    }
    func setFurLines(_ on: Bool) { update { $0 = $0.withFurLines(on) } }
    /// "Apply to every cat": the motion, collar and personality of cat `id` go to all 16.
    func applyToAll(from id: String) { update { $0 = $0.applyingToAll(from: id) } }
}
```

- [ ] **Step 4: Run the tests**

Run: `bash scripts/test-cat-settings-store.sh 2>&1 | grep -E "✗|passed|failed"; for t in engine devpanel renderer; do printf '%-10s' $t; bash scripts/test-cat-$t.sh 2>&1 | tail -1; done`
Expected: `All tests passed.` for the store, then three lines ending `All tests passed.`

- [ ] **Step 5: The app reads the settings and follows the character**

The settings are read before the first cat is made (`AppDelegate`), and each canvas tells its engine the character on every frame (`useCharacter` is a string compare when nothing changed).

**Edit `NotchBuddy/Sources/App/AppDelegate.swift`**, find this text (it occurs exactly once):

```swift
        // Warm up Keychain cache on main thread BEFORE any poller or view touches it
        _ = KeychainStore.shared
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarItem()
```

and replace it with:

```swift
        // Warm up Keychain cache on main thread BEFORE any poller or view touches it
        _ = KeychainStore.shared
        // The cat settings are read before the first cat is made, so the notch opens with the cat the user picked.
        _ = CatSettingsStore.shared
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarItem()
```

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**, find this text (it occurs exactly once):

```swift
                // One clock on both sides of dt: CACurrentMediaTime() here and in the engine (the old code mixed it with the timeline's date).
                let dt = CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                let look = lookAt(state: state)
                engine.lookX = look.x
```

and replace it with:

```swift
                // One clock on both sides of dt: CACurrentMediaTime() here and in the engine (the old code mixed it with the timeline's date).
                let dt = CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                engine.useCharacter(CatConfig.shared.character)   // Settings → Cat → Character
                let look = lookAt(state: state)
                engine.lookX = look.x
```

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**, find this text (it occurs exactly once):

```swift
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                let dt = CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                engine.setDancing(isDancing)
                engine.update(dt: dt)
```

and replace it with:

```swift
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                let dt = CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                engine.useCharacter(CatConfig.shared.character)   // Settings → Cat → Character
                engine.setDancing(isDancing)
                engine.update(dt: dt)
```

**Edit `NotchBuddy/Sources/App/GreetingCanvasView.swift`**, find this text (it occurs exactly once):

```swift
            let t = timeline.date.timeIntervalSince(startDate)
            Canvas { context, size in
                engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                let end = CatGreeting.Compact(width: Double(state.notchWidth) + 160, height: Double(state.notchHeight))
```

and replace it with:

```swift
            let t = timeline.date.timeIntervalSince(startDate)
            Canvas { context, size in
                engine.useCharacter(CatConfig.shared.character)   // Settings → Cat → Character
                engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                let end = CatGreeting.Compact(width: Double(state.notchWidth) + 160, height: Double(state.notchHeight))
```

**Edit `NotchBuddy/Sources/App/UploadCanvasView.swift`**, find this text (it occurs exactly once):

```swift
    private func drawCat(ctx: GraphicsContext, f: USFrame) -> CatGeometry.Layout? {
        let cat = driver.engine
        driver.follow(f, file: state.droppedFile?.name ?? "file")
        var laid: CatGeometry.Layout?
```

and replace it with:

```swift
    private func drawCat(ctx: GraphicsContext, f: USFrame) -> CatGeometry.Layout? {
        let cat = driver.engine
        cat.useCharacter(CatConfig.shared.character)   // Settings → Cat → Character
        driver.follow(f, file: state.droppedFile?.name ?? "file")
        var laid: CatGeometry.Layout?
```

- [ ] **Step 6: Build**

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `Created project at …` and the last lines end with `** BUILD SUCCEEDED **`. `git diff --stat -- NotchBuddy/NotchBuddy.xcodeproj` lists `project.pbxproj` as changed (the new Swift files are in it).

- [ ] **Step 7: Commit**

```bash
git add NotchBuddy/Sources/App/CatSettingsStore.swift NotchBuddy/Sources/App/CatEngine.swift NotchBuddy/Sources/App/AppDelegate.swift NotchBuddy/Sources/App/BotCanvasView.swift NotchBuddy/Sources/App/GreetingCanvasView.swift NotchBuddy/Sources/App/UploadCanvasView.swift tests/CatSettingsSupport.swift tests/CatSettingsStoreTests.swift tests/CatSettingsTests.swift scripts/test-cat-settings-store.sh scripts/test-cat-settings.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): the cat settings reach the engines, and a new character shows on the next frame

CatSettingsStore loads UserDefaults through the clean-up, saves only what changed and hands the result to CatConfig,
which every engine already reads per frame. CatEngine.useCharacter switches the coat of a running engine.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 3: Fur lines: the strands, the renderer, the sheet (stage 5)

**Agent:** `nm-implementer-light`. The code is given in full; the tests prove the strands against the prototype's own numbers.

**Files:**
- Create: `NotchBuddy/Sources/App/CatFur.swift`, `tests/CatFurTests.swift`, `scripts/test-cat-fur.sh`
- Modify: `NotchBuddy/Sources/App/CatLook.swift` (`CatDrawOptions.fur`), `NotchBuddy/Sources/App/CatRenderer.swift`, `NotchBuddy/Sources/App/BotCanvasView.swift`, `NotchBuddy/Sources/App/UploadCanvasView.swift`, `NotchBuddy/Sources/App/CatGreetingRenderer.swift`, `tests/CatRendererTests.swift`, `scripts/test-cat-renderer.sh`, `scripts/render-cats.sh`, `scripts/render-cat-panel.sh`, `scripts/gen-icons.sh` (each gains `CatFur.swift`), `scripts/render-cats.swift` (the `--fur` sheet), `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (by `xcodegen`)

**Interfaces:**
- Consumes: `CatConfig.furLines` (Task 2), `CatPreset.furOpts`, `CatGeometry.momoWhite`, `CatRNG`.
- Produces `CatFur.strands(for:) -> CatFur.Strands` (`head`, `ruff`), `CatFur.shows(_:R:full:)` (a full-detail cat from a head radius of 30 px, never a hairless one), `CatFur.headWidth(_:R:)`, `CatDrawOptions.fur` (default `false`). Fur is not in the contract (`docs/CAT-CONTRACT.md`: "drawn from seeded noise by the renderer"), so nothing in `cat-core.js` or the fixtures changes.

- [ ] **Step 1: Write the failing strand tests**

The prototype's `furStrands` (`design/prototype/notchmeow.html`, seeds 13 for the head and 7 for the ruff) was run in Node on `cat-core.js`'s presets, with a winding test in place of the canvas's `isPointInPath`, and its numbers are in the test: the strand counts of all 16 coats, the first head strand of Shrimpy and Momo, Shrimpy's first ruff strand, and the 160 strands that lie on Momo's white map. The Mac must draw the same fur as the prototype and the Windows app.

**Create `scripts/test-cat-fur.sh`**:

```bash
#!/usr/bin/env bash
# Cat fur lines: the seeded strands of all 16 coats against the prototype's (same seeds, counts and first strands), and when they are drawn.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-fur.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatFur.swift \
    tests/CatTestSupport.swift tests/CatFurTests.swift \
    -o "$TEST_DIR/cat-fur-tests"
"$TEST_DIR/cat-fur-tests"
```

**Create `tests/CatFurTests.swift`**:

```swift
import CoreGraphics
import Foundation

@main
enum CatFurTests {
    typealias G = CatGeometry
    static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-9 }

    @MainActor static func main() {
        // The strand counts and the first strands below come from running the prototype's `furStrands` (design/prototype/notchmeow.html) in Node on
        // cat-core.js's presets, with a winding test in place of the canvas's isPointInPath: the same seeds (13 for the head, 7 for the ruff).
        let counts: [String: (head: Int, ruff: Int)] = [
            "shrimpy": (254, 300), "momo": (434, 0), "ginger": (251, 0), "midnight": (251, 0), "latte": (248, 0), "patches": (251, 0), "blue": (259, 0), "snow": (251, 300),
            "oreo": (432, 0), "mocha": (251, 0), "silver": (251, 0), "cloud": (252, 300), "leo": (251, 0), "button": (257, 0), "puff": (257, 300), "noodle": (249, 0),
        ]

        CT.section("the strands are the prototype's: same seeds, same counts, same first strands")
        var diffs: [String] = []
        for id in CatPresets.ids {
            let f = CatFur.strands(for: CatPresets.byID(id)), want = counts[id]!
            if f.head.count != want.head || f.ruff.count != want.ruff { diffs.append("\(id): \(f.head.count) head and \(f.ruff.count) ruff, not \(want.head) and \(want.ruff)") }
        }
        CT.checkRows("the head and ruff strand counts of the 16 coats", diffs)
        let s = CatFur.strands(for: CatPresets.byID("shrimpy")), h = s.head[0], r = s.ruff[0]
        CT.checkTrue("Shrimpy's first head strand", close(h.x, -0.3709192420169711) && close(h.y, 0.38896529177203776) && close(h.x2, -0.3897367613151183) && close(h.y2, 0.4340643851551145) && h.color == "rgba(214,190,150,.32)")
        CT.checkTrue("Shrimpy's first ruff strand", close(r.x, 0.35669339683776213) && close(r.y, -0.4974516900928963) && close(r.ux, 0.3009259855363654) && close(r.uy, -0.9536474984127874) && close(r.L, 0.07767893617972732) && r.color == "rgba(214,192,156,.45)")
        let m = CatFur.strands(for: CatPresets.byID("momo"))
        CT.checkTrue("Momo's first head strand", close(m.head[0].x, -0.35812892332673074) && close(m.head[0].y2, 0.4085957288856934) && m.head[0].color == "rgba(255,255,255,.5)")
        CT.check("160 of Momo's strands lie on her white map and use the white colours", m.head.filter { $0.color == "rgba(196,190,184,.55)" || $0.color == "rgba(255,255,255,.5)" }.count, 160)

        CT.section("the strands stay on the head, away from the eyes and the nose, and are built once")
        for id in CatPresets.ids {
            let p = CatPresets.byID(id), f = CatFur.strands(for: p)
            let inside = f.head.allSatisfy { pow($0.x / p.rx, 2) + pow($0.y / p.ry, 2) <= 1 + 1e-12 }
            let nz = (x: 0.0, y: -sin(p.nosePh) * p.ry)
            let clear = f.head.allSatisfy { hypot($0.x - nz.x, $0.y - nz.y - 0.1) >= 0.32 - 1e-12 }
            if !inside || !clear { diffs.append(id) }
        }
        CT.checkRows("no strand outside the head or on the nose, in any coat", diffs)
        CT.checkTrue("the same coat gives the same strands twice", CatFur.strands(for: CatPresets.byID("shrimpy")).head.count == s.head.count)
        CT.checkTrue("a kitten has strands of its own", CatFur.strands(for: CatPresets.kitten(of: CatPresets.byID("shrimpy"))).head[0].x != h.x)

        CT.section("when fur is drawn: a full-detail cat from a head radius of 30 px, never a hairless one")
        CT.checkTrue("Shrimpy at Ø66", CatFur.shows(CatPresets.byID("shrimpy"), R: 33, full: true))
        CT.checkTrue("not below R 30", !CatFur.shows(CatPresets.byID("shrimpy"), R: 29.9, full: true))
        CT.checkTrue("not at the compact detail", !CatFur.shows(CatPresets.byID("shrimpy"), R: 40, full: false))
        CT.checkTrue("not on Noodle, who has no fur", !CatFur.shows(CatPresets.byID("noodle"), R: 40, full: true))
        CT.finish()
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-fur.sh 2>&1 | head -3`
Expected: FAIL: `<unknown>:0: error: error opening input file 'NotchBuddy/Sources/App/CatFur.swift' (No such file or directory)`.

- [ ] **Step 3: Write the strands**

**Create `NotchBuddy/Sources/App/CatFur.swift`**:

```swift
import CoreGraphics
import Foundation

// Optional fur lines (Settings → Cat → Fur lines, off by default): seeded strands on the head and on a ruff, built once per coat. Port of the
// prototype's `furStrands` (design/prototype/notchmeow.html): the same seeds (13 for the head, 7 for the ruff), so the same strands. They are
// not part of the contract (cat-core.js holds no fur): the renderer draws them from seeded noise, and tests/CatFurTests.swift pins them
// against the prototype's own numbers.

enum CatFur {
    /// A head strand, in units of R, from (x, y) to (x2, y2), with its colour ("rgba(...)").
    struct HeadStrand { var x: Double, y: Double, x2: Double, y2: Double, color: String }
    /// A ruff strand, in units of R: centred on (x, y), along (ux, uy), L long.
    struct RuffStrand { var x: Double, y: Double, ux: Double, uy: Double, L: Double, color: String }
    struct Strands { var head: [HeadStrand]; var ruff: [RuffStrand] }

    /// What a coat without its own `furOpts` uses (a flat-coloured shorthair).
    static let fallback = CatPreset.FurOpts(n: 420, l0: 0.04, l1: 0.05, w: 0.01, dark: "rgba(0,0,0,.22)", light: "rgba(255,255,255,.2)", wDark: nil, wLight: nil)

    /// Fur is drawn on a full-detail cat from a head radius of 30 px (a head of Ø60 and more), and never on a hairless coat.
    static func shows(_ p: CatPreset, R: Double, full: Bool) -> Bool { full && R >= 30 && p.hairless == nil }

    /// The stroke width of a head strand, in px.
    static func headWidth(_ p: CatPreset, R: Double) -> Double { max(0.5, (p.furOpts ?? fallback).w * R) }

    @MainActor private static var cache: [String: Strands] = [:]

    /// The strands of a coat (a kitten has its own: its head is another shape), built the first time and kept.
    @MainActor static func strands(for p: CatPreset) -> Strands {
        let key = p.name + (p.kitten == true ? "-kitten" : "")
        if let s = cache[key] { return s }
        let s = build(p)
        cache[key] = s
        return s
    }

    private static func build(_ p: CatPreset) -> Strands {
        let o = p.furOpts ?? fallback, rx = p.rx, ry = p.ry
        var head: [HeadStrand] = [], ruff: [RuffStrand] = []
        // Momo's white map: strands that start on it use the white colours (a winding test, like the canvas's isPointInPath).
        var white: CGPath?
        if p.coat == "tuxedo" {
            let path = CGMutablePath()
            for (i, q) in CatGeometry.momoWhite.enumerated() { i == 0 ? path.move(to: CGPoint(x: q.0 * 100, y: q.1 * 100)) : path.addLine(to: CGPoint(x: q.0 * 100, y: q.1 * 100)) }
            path.closeSubpath()
            white = path
        }
        let eyes = [-1.0, 1.0].map { sd in (x: sin(sd * p.eye.th) * cos(p.eye.ph) * rx, y: -sin(p.eye.ph) * ry) }
        let nose = (x: 0.0, y: -sin(p.nosePh) * ry)
        var rand = CatRNG(seed: 13)
        for _ in 0..<o.n {
            let x = (rand.next() * 2 - 1) * rx, y = (rand.next() * 2 - 1) * ry
            if pow(x / rx, 2) + pow(y / ry, 2) > 1 { continue }
            if eyes.contains(where: { hypot(x - $0.x, (y - $0.y) * 1.25) < 0.3 }) || hypot(x - nose.x, y - nose.y - 0.1) < 0.32 { continue }
            let dx: Double, dy: Double
            if y < -0.32 { dx = x * 0.35; dy = -1 } else { dx = x; dy = y + 0.5 }
            let m = hypot(dx, dy) == 0 ? 1 : hypot(dx, dy)
            let len = o.l0 + rand.next() * o.l1
            let onWhite = white?.contains(CGPoint(x: x * 100, y: y * 100), using: .winding) ?? false
            let dark = rand.next() < 0.55
            head.append(HeadStrand(x: x, y: y, x2: x + dx / m * len, y2: y + dy / m * len,
                                   color: dark ? (onWhite ? o.wDark ?? o.dark : o.dark) : (onWhite ? o.wLight ?? o.light : o.light)))
        }
        if let r = p.ruff {
            let e = 2 / 2.4
            rand = CatRNG(seed: 7)
            for _ in 0..<300 {
                let a = rand.next() * CatMath.tau, c = cos(a), s = sin(a)
                let ex = (c > 0 ? 1.0 : c < 0 ? -1.0 : 0) * pow(abs(c), e) * r.rx, ey = (s > 0 ? 1.0 : s < 0 ? -1.0 : 0) * pow(abs(s), e) * r.ry
                let f = 0.7 + rand.next() * 0.32, x = ex * f, y = ey * f + r.dy
                var dx = ex, dy = ey + 0.35 * max(0, s)
                let m = hypot(dx, dy) == 0 ? 1 : hypot(dx, dy)
                dx /= m; dy /= m
                let j = (rand.next() - 0.5) * 0.5
                let ux = dx * cos(j) - dy * sin(j), uy = dx * sin(j) + dy * cos(j), len = 0.05 + rand.next() * 0.08
                ruff.append(RuffStrand(x: x, y: y, ux: ux, uy: uy, L: len, color: rand.next() < 0.5 ? "rgba(214,192,156,.45)" : "rgba(84,66,50,.38)"))
            }
        }
        return Strands(head: head, ruff: ruff)
    }
}
```

- [ ] **Step 4: Run it**

Run: `bash scripts/test-cat-fur.sh 2>&1 | grep -E "✗|passed|failed"; bash scripts/test-cat-fur.sh 2>&1 | grep -c "✓"`
Expected: `All tests passed.` and `12`.

- [ ] **Step 5: Write the failing renderer tests**

The renderer's tests gain a section: fur is off by default, changes the pixels of a big full-detail cat (Shrimpy's ruff included, Momo's white map), and changes nothing below a head radius of 30, at the compact detail, or on Noodle. `CatDrawOptions` gets its `fur` switch, and every script that compiles the renderer gets `CatFur.swift`.

**Edit `NotchBuddy/Sources/App/CatLook.swift`**, find this text (it occurs exactly once):

```swift
    /// The badge, when the cat has one.
    var badge = true
}

```

and replace it with:

```swift
    /// The badge, when the cat has one.
    var badge = true
    /// Optional fur strands (Settings → Cat → Fur lines), drawn on a full-detail cat from a head radius of 30 px (`CatFur.shows`). Flat colour is the default.
    var fur = false
}

```

**Edit `scripts/gen-icons.sh`**, find this text (it occurs exactly once):

```bash
swiftc -swift-version 6 -O \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
```

and replace it with:

```bash
swiftc -swift-version 6 -O \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
```

**Edit `scripts/render-cat-panel.sh`**, find this text (it occurs exactly once):

```bash
swiftc -swift-version 6 -D DEBUG \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/AppLog.swift $APP/CatFrameMeter.swift $APP/CatFrameReadout.swift $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
    $APP/CatFileRule.swift $APP/AI/Core/Attachments.swift $APP/AI/Core/AICatalog.swift $APP/AI/Core/ModelProvider.swift $APP/AI/Core/ContextBudget.swift \
```

and replace it with:

```bash
swiftc -swift-version 6 -D DEBUG \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/AppLog.swift $APP/CatFrameMeter.swift $APP/CatFrameReadout.swift $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
    $APP/CatFileRule.swift $APP/AI/Core/Attachments.swift $APP/AI/Core/AICatalog.swift $APP/AI/Core/ModelProvider.swift $APP/AI/Core/ContextBudget.swift \
```

**Edit `scripts/render-cats.sh`**, find this text (it occurs exactly once):

```bash
swiftc -swift-version 6 ${RENDER_CATS_OPT:+-O} \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
```

and replace it with:

```bash
swiftc -swift-version 6 ${RENDER_CATS_OPT:+-O} \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
```

**Edit `scripts/test-cat-renderer.sh`**, find this text (it occurs exactly once):

```bash
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift tests/CatEngineSupport.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift $APP/IslandScreenGeometry.swift \
```

and replace it with:

```bash
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift tests/CatEngineSupport.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift $APP/IslandScreenGeometry.swift \
```

**Edit `tests/CatRendererTests.swift`**, find this text (it occurs exactly once):

```swift
            }
        }
        CT.finish()
    }
```

and replace it with:

```swift
            }
        }

        CT.section("fur lines: off by default, and drawn only on a big full-detail cat that has fur")
        func fur(_ id: String, _ D: Double, on: Bool, full: Bool? = nil) -> [UInt8] {
            render(300, 300) { R.draw($0, CatLook(preset: CatPresets.byID(id)), cx: 150, cy: 150, D: D, CatDrawOptions(full: full, fur: on)) }
        }
        let plain = render(300, 300) { R.draw($0, CatLook(preset: CatPresets.byID("shrimpy")), cx: 150, cy: 150, D: 140) }
        CT.checkTrue("plain flat colour is the default", fur("shrimpy", 140, on: false) == plain)
        CT.checkTrue("Shrimpy at Ø140 looks different with fur lines, ruff included", fur("shrimpy", 140, on: true) != plain)
        CT.checkTrue("Momo too (her white map has strand colours of its own)", fur("momo", 140, on: true) != fur("momo", 140, on: false))
        CT.checkTrue("the same fur draws the same pixels twice", fur("momo", 140, on: true) == fur("momo", 140, on: true))
        CT.checkTrue("below a head radius of 30 px nothing changes", fur("shrimpy", 56, on: true) == fur("shrimpy", 56, on: false))
        CT.checkTrue("at the compact detail nothing changes", fur("shrimpy", 140, on: true, full: false) == fur("shrimpy", 140, on: false, full: false))
        CT.checkTrue("Noodle has no fur, so nothing changes", fur("noodle", 140, on: true) == fur("noodle", 140, on: false))
        CT.finish()
    }
```

- [ ] **Step 6: Run it to see it fail**

Run: `bash scripts/test-cat-renderer.sh 2>&1 | grep -E "✗|failed"`
Expected: FAIL: `✗ Shrimpy at Ø140 looks different with fur lines, ruff included`, `✗ Momo too (her white map has strand colours of its own)` and `2 test(s) failed.` (the option exists, the renderer ignores it).

- [ ] **Step 7: Draw the fur**

The head's strands are drawn inside the head clip after the markings and under the state tint, bent by the same warp as the markings; the ruff's are drawn inside the ruff, a little curved. The big cat, the drop view's cat and the greeting's cat read the switch from their engine's `CatConfig`.

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**, find this text (it occurs exactly once):

```swift
                let cx = Double(size.width) / 2, cy = Double(size.height) / 2 + Double(particleOverhang) / 2
                var options = CatDrawOptions()
                if state.mode == .compact {
                    options.badgeSide = -1                       // never under the camera housing
```

and replace it with:

```swift
                let cx = Double(size.width) / 2, cy = Double(size.height) / 2 + Double(particleOverhang) / 2
                var options = CatDrawOptions()
                options.fur = engine.cfg.furLines                // Settings → Cat → Fur lines
                if state.mode == .compact {
                    options.badgeSide = -1                       // never under the camera housing
```

**Edit `NotchBuddy/Sources/App/CatGreetingRenderer.swift`**, find this text (it occurs exactly once):

```swift
        ]
        var o = CatDrawOptions()
        o.badgeSide = 1 - 2 * CatEase.inOut.at(seg(t, leave, leave + Greeting.GT.collapse))
        CatRenderer.draw(cg, look, cx: X, cy: Y, D: D, o)
```

and replace it with:

```swift
        ]
        var o = CatDrawOptions()
        o.fur = e.cfg.furLines
        o.badgeSide = 1 - 2 * CatEase.inOut.at(seg(t, leave, leave + Greeting.GT.collapse))
        CatRenderer.draw(cg, look, cx: X, cy: Y, D: D, o)
```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**, find this text (it occurs exactly once):

```swift
            if f < 1 { L = layout(ek * f) }
        }
        if o.glow { CatEffects.drawGlow(cg, look, L) }
        CatEffects.drawZoomTrails(cg, look, L)
```

and replace it with:

```swift
            if f < 1 { L = layout(ek * f) }
        }
        let fur = o.fur && CatFur.shows(p, R: L.R, full: L.full) ? CatFur.strands(for: p) : nil   // the optional fur strands
        if o.glow { CatEffects.drawGlow(cg, look, L) }
        CatEffects.drawZoomTrails(cg, look, L)
```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**, find this text (it occurs exactly once):

```swift
        cg.rotate(by: s.tilt)
        cg.scaleBy(x: s.sx, y: s.sy)
        drawBehind(cg, look, L, flat)
        drawHead(cg, look, L, o, flat)
        drawFront(cg, p, s, L, flat)
        cg.restoreGState()
```

and replace it with:

```swift
        cg.rotate(by: s.tilt)
        cg.scaleBy(x: s.sx, y: s.sy)
        drawBehind(cg, look, L, flat, fur)
        drawHead(cg, look, L, o, flat, fur)
        drawFront(cg, p, s, L, flat)
        cg.restoreGState()
```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**, find this text (it occurs exactly once):

```swift
    // MARK: Behind pass

    private static func drawBehind(_ cg: CGContext, _ look: CatLook, _ L: G.Layout, _ flat: G.FlatColors?) {
        let p = look.preset, R = L.R
        // Ruff and neck bib sit behind the head, with a little parallax.
```

and replace it with:

```swift
    // MARK: Behind pass

    private static func drawBehind(_ cg: CGContext, _ look: CatLook, _ L: G.Layout, _ flat: G.FlatColors?, _ fur: CatFur.Strands?) {
        let p = look.preset, R = L.R
        // Ruff and neck bib sit behind the head, with a little parallax.
```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**, find this text (it occurs exactly once):

```swift
            } else if let c = flat?.ruff {
                cg.fill(rp, CatDraw.rgb(c))
            }
            if let bib = p.bib {
```

and replace it with:

```swift
            } else if let c = flat?.ruff {
                cg.fill(rp, CatDraw.rgb(c))
            }
            if let fur {
                // Fur strands on the ruff, curved a little, inside its outline.
                cg.saveGState()
                cg.clip(rp)
                for q in fur.ruff {
                    let x = q.x * R, y = q.y * R, len = q.L * R
                    let strand = CGMutablePath()
                    strand.move(to: CGPoint(x: x - q.ux * len * 0.5, y: y - q.uy * len * 0.5))
                    strand.addQuadCurve(to: CGPoint(x: x + q.ux * len * 0.5, y: y + q.uy * len * 0.5), control: CGPoint(x: x - q.uy * len * 0.15, y: y + q.ux * len * 0.15))
                    cg.stroke(strand, CatDraw.color(q.color), width: max(0.6, 0.012 * R))
                }
                cg.restoreGState()
            }
            if let bib = p.bib {
```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**, find this text (it occurs exactly once):

```swift
    // MARK: Head pass

    private static func drawHead(_ cg: CGContext, _ look: CatLook, _ L: G.Layout, _ o: CatDrawOptions, _ flat: G.FlatColors?) {
        let p = look.preset, s = look.pose, R = L.R, rx = L.rx, ry = L.ry, fa = L.fa, W = L.warp
        let head = CatDraw.poly(G.supPoints(rx: rx, ry: ry, n: p.n, dy: 0, spike: p.fluff != 0 ? 0.035 : 0, count: 14, steps: L.steps, bend: L.bend))
```

and replace it with:

```swift
    // MARK: Head pass

    private static func drawHead(_ cg: CGContext, _ look: CatLook, _ L: G.Layout, _ o: CatDrawOptions, _ flat: G.FlatColors?, _ fur: CatFur.Strands?) {
        let p = look.preset, s = look.pose, R = L.R, rx = L.rx, ry = L.ry, fa = L.fa, W = L.warp
        let head = CatDraw.poly(G.supPoints(rx: rx, ry: ry, n: p.n, dy: 0, spike: p.fluff != 0 ? 0.035 : 0, count: 14, steps: L.steps, bend: L.bend))
```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**, find this text (it occurs exactly once):

```swift
        cg.setAlpha(fa)
        drawMarkings(cg, p, L, flat)
        cg.setAlpha(1)
        // The state tint, rising from the chin.
```

and replace it with:

```swift
        cg.setAlpha(fa)
        drawMarkings(cg, p, L, flat)
        if let fur {
            // Fur strands on the head, bent by the warp like the markings, under the state tint.
            let width = CatFur.headWidth(p, R: R)
            for q in fur.head {
                let a = L.warp(q.x, q.y), b = L.warp(q.x2, q.y2), strand = CGMutablePath()
                strand.move(to: CGPoint(x: a.0, y: a.1)); strand.addLine(to: CGPoint(x: b.0, y: b.1))
                cg.stroke(strand, CatDraw.color(q.color), width: width)
            }
        }
        cg.setAlpha(1)
        // The state tint, rising from the chin.
```

**Edit `NotchBuddy/Sources/App/UploadCanvasView.swift`**, find this text (it occurs exactly once):

```swift
        look.badge = nil
        ctx.withCGContext { cg in
            laid = CatRenderer.draw(cg, look, cx: f.x, cy: f.y + f.hop, D: f.d)
        }
        if let L = laid { cat.base = L.base; cat.mouthPoint = L.mouth }
```

and replace it with:

```swift
        look.badge = nil
        ctx.withCGContext { cg in
            laid = CatRenderer.draw(cg, look, cx: f.x, cy: f.y + f.hop, D: f.d, CatDrawOptions(fur: cat.cfg.furLines))
        }
        if let L = laid { cat.base = L.base; cat.mouthPoint = L.mouth }
```

- [ ] **Step 8: Run the renderer tests**

Run: `bash scripts/test-cat-renderer.sh 2>&1 | grep -E "✗|passed|failed"; bash scripts/test-cat-fur.sh 2>&1 | tail -1`
Expected: `All tests passed.` twice.

- [ ] **Step 9: Add the fur sheet and look at it**

`render-cats.sh --fur` draws each coat plain (the default), with fur lines, and with fur lines and the head turned, at Ø150.

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
//   bash scripts/render-cats.sh --greeting --cats shrimpy          the launch greeting at its beats, island and cat
//   bash scripts/render-cats.sh --catch --cats shrimpy             the four-step file catch, and a refused file coughed up as a hairball
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

```

and replace it with:

```swift
//   bash scripts/render-cats.sh --greeting --cats shrimpy          the launch greeting at its beats, island and cat
//   bash scripts/render-cats.sh --catch --cats shrimpy             the four-step file catch, and a refused file coughed up as a hairball
//   bash scripts/render-cats.sh --fur --cats shrimpy,momo          big cats plain and with fur lines (Settings → Cat → Fur lines), at rest and turned
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case greeting
        case catchSheet
    }

```

and replace it with:

```swift
        case greeting
        case catchSheet
        case fur
    }

```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
            case "--greeting": a.mode = .greeting
            case "--catch": a.mode = .catchSheet
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

and replace it with:

```swift
            case "--greeting": a.mode = .greeting
            case "--catch": a.mode = .catchSheet
            case "--fur": a.mode = .fur
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case .greeting: sheet = greeting(a)
        case .catchSheet: sheet = catchSheet(a)
        }
        sheet.write(to: a.out)
```

and replace it with:

```swift
        case .greeting: sheet = greeting(a)
        case .catchSheet: sheet = catchSheet(a)
        case .fur: sheet = furSheet(a)
        }
        sheet.write(to: a.out)
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift



    // MARK: The file catch: taken, and refused
```

and replace it with:

```swift



    // MARK: Fur lines: plain next to fur, big, at rest and with the head turned

    @MainActor static func furSheet(_ a: Args) -> Sheet {
        let cell = 250.0, labelW = 110.0
        var turned = CatPose(); turned.yaw = 0.5; turned.pitch = 0.2
        let variants: [(String, Bool, CatPose)] = [("plain (the default)", false, CatPose()), ("fur lines", true, CatPose()), ("fur lines, head turned", true, turned)]
        let sheet = Sheet(width: labelW + cell * Double(variants.count) + 8, height: cell * Double(a.cats.count) + 28, scale: a.scale)
        let cg = sheet.cg
        for (ci, v) in variants.enumerated() { CatDraw.text(cg, v.0, x: labelW + (Double(ci) + 0.5) * cell, y: 14, size: 12, bold: true, color: CatDraw.white(0.8)) }
        for (ri, id) in a.cats.enumerated() {
            let top = 28 + Double(ri) * cell, preset = CatPresets.byID(id)
            CatDraw.text(cg, preset.label, x: 52, y: top + cell / 2, size: 12, bold: true, color: CatDraw.white(0.85))
            for (ci, v) in variants.enumerated() {
                let x = labelW + Double(ci) * cell
                cg.saveGState()
                cg.clip(CatDraw.roundRect(x + 3, top + 3, cell - 6, cell - 6, 12))
                cg.fill(CatDraw.roundRect(x, top, cell, cell, 0), CatDraw.black(1))
                CatRenderer.draw(cg, CatLook(preset: preset, pose: v.2), cx: x + cell / 2, cy: top + cell * 0.55, D: 150, CatDrawOptions(fur: v.1))
                cg.restoreGState()
            }
        }
        return sheet
    }

    // MARK: The file catch: taken, and refused
```

Run: `d="${TMPDIR:-/tmp}/a-mac-5-7"; mkdir -p "$d" && bash scripts/render-cats.sh --fur --cats shrimpy,momo,cloud,ginger --out "$d/fur.png"`
Expected: `wrote …/a-mac-5-7/fur.png`.

Look at `$d/fur.png`: four coats in three columns. Expected: the plain column has no strands; the fur columns have short seeded strands over the head, Shrimpy's and Cloud's ruffs have curved ones, Momo's white map has pale strands and her black cap dark ones, and the turned head bends the strands with the markings. The strands do not cross the eyes or the nose.

- [ ] **Step 10: Build**

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: the last lines end with `** BUILD SUCCEEDED **`.

- [ ] **Step 11: Commit**

```bash
git add NotchBuddy/Sources/App/CatFur.swift NotchBuddy/Sources/App/CatLook.swift NotchBuddy/Sources/App/CatRenderer.swift NotchBuddy/Sources/App/BotCanvasView.swift NotchBuddy/Sources/App/UploadCanvasView.swift NotchBuddy/Sources/App/CatGreetingRenderer.swift tests/CatFurTests.swift tests/CatRendererTests.swift scripts/test-cat-fur.sh scripts/test-cat-renderer.sh scripts/render-cats.sh scripts/render-cats.swift scripts/render-cat-panel.sh scripts/gen-icons.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): optional fur lines, the prototype's seeded strands, drawn from a head radius of 30 px

CatFur builds the strands once per coat with the prototype's seeds (13 and 7) and is tested against numbers made by
running the prototype's own function. The renderer draws them on the head (warped like the markings) and on the ruff.
render-cats.sh gains --fur.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 4: The Cat section of Settings, and the script that draws it (stage 5)

**Agent:** `nm-implementer`. The code is given in full; the build, the pins and the picture are what to read.

**Files:**
- Create: `NotchBuddy/Sources/App/CatSettingsView.swift`, `scripts/render-cat-settings.sh`, `scripts/render-cat-settings.swift`
- Modify: `NotchBuddy/Sources/App/SettingsView.swift` (three lines: the sidebar entry, its title, its section), `NotchBuddy/Sources/App/CatSettingsStore.swift` (`config` is readable by the section), `tests/CatSettingsTests.swift` (the source pins), `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (by `xcodegen`)

**Interfaces:**
- Consumes: Task 2's `CatSettingsStore` and `CatConfig`, Task 3's `CatDrawOptions.fur`, `Personality.presets` and `.traits`, `CatPresets.ids`.
- Produces `CatSettingsView(store:alwaysActive:)` (the section), `CatPreviewView(id:head:active:config:agentColor:)` (a silent live cat that draws only while `active`) and `WindowVisibility` (reports whether the window it is in is on screen and is the key window). The rows, in the spec's order: **Character** (the 16 cats, Shrimpy first and Momo second, each in a live preview, and **a big live preview of the chosen cat beside them**: the renderer draws fur strands only from a head of Ø60, and the biggest cat in the island is Ø66, so a Ø36 tile can never show the Fur lines switch; the Ø84 preview does, and shows the collar too), **Motion** (Style: Playful or Classic; This cat's motion: follow the style, Playful or Classic), **Personality** (Preset, then the six sliders; the preset menu shows "Custom" once a slider has moved), **Look** (Fur lines), **Every cat** (Apply to every cat). The rows below the character grid edit the **chosen** character: to give another cat its own motion or personality, pick it first.
- Built from the rows Settings already has: a `GroupBox` per topic, a 130 pt label with a control, grey 11 pt notes. No existing row changes; the only edit to `SettingsView.swift` is the entry, its title and its section, **after** Shortcuts.

- [ ] **Step 1: Write the failing pins**

A test program cannot run the Settings window, so these are source pins in the settings program: Settings has the Cat entry and names the section once; the section saves nothing itself (every change goes through the store); the previews pause when the window is not on screen; the previews are silent.

**Edit `tests/CatSettingsTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.check("and its keys are sorted, so the text is the same every time", text.hasPrefix("{\"affection\":1,"), true)

        CT.section("UserDefaults keys: cat.character, cat.motionStyle, cat.furLines, cat.collar, cat.motion.<id>, cat.collar.<id>, cat.personality.<id>")
        let mem = MemoryBacking()
```

and replace it with:

```swift
        CT.check("and its keys are sorted, so the text is the same every time", text.hasPrefix("{\"affection\":1,"), true)

        CT.section("the Cat section of Settings (source pins: no test program can run the Settings window)")
        func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/" + file, encoding: .utf8)) ?? "" }
        let view = source("CatSettingsView.swift"), settingsView = source("SettingsView.swift")
        CT.checkTrue("Settings has a Cat entry in its sidebar and shows the section", settingsView.contains("title: \"Cat\"") && settingsView.contains(".tag(\"cat\")") && settingsView.contains("CatSettingsView()"))
        CT.checkTrue("the section saves nothing itself: every change goes through the store", view.contains("store.setCharacter") && !view.contains("UserDefaults") && !view.contains("@AppStorage"))
        CT.checkTrue("the previews pause when the window is not on screen", view.contains("paused: !active") && view.contains("WindowVisibility(visible: $windowVisible)"))
        CT.checkTrue("the previews are silent: they have no sound hook", !view.contains("onSound") && !view.contains("SoundEngine"))
        CT.checkTrue("Settings names the Cat section once", settingsView.components(separatedBy: "CatSettingsView").count == 2)

        CT.section("UserDefaults keys: cat.character, cat.motionStyle, cat.furLines, cat.collar, cat.motion.<id>, cat.collar.<id>, cat.personality.<id>")
        let mem = MemoryBacking()
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-settings.sh 2>&1 | grep -E "✗|failed"`
Expected: FAIL: four `✗` lines (`Settings has a Cat entry in its sidebar and shows the section`, `the section saves nothing itself: every change goes through the store`, `the previews pause when the window is not on screen` and `Settings names the Cat section once`) and `4 test(s) failed.`

- [ ] **Step 3: Write the section**

Notes on three choices. **The previews pause with the window, not with the view:** Settings keeps its window and its views after it is closed (`isReleasedWhenClosed = false`), so `onDisappear` never comes; `WindowVisibility` watches the window's occlusion state, its minimising, its closing and whether it is the key window instead (the Windows app also stops its previews when Settings is not focused, so the two match). **Each preview owns one engine on the store's `CatConfig`,** so each shows that cat's own motion and personality, and a slider moved in Settings shows on the next frame; the engines are created without a sound hook. **The big previews wear a sample agent colour** (Claude Code's `#E07950`) once a collar style is picked in Task 8. A smaller one sits by the personality rows, so a slider's effect is in view while you drag it.

**Edit `NotchBuddy/Sources/App/CatSettingsStore.swift`**, find this text (it occurs exactly once):

```swift
    @Published private(set) var settings: CatSettings
    private let backing: any CatSettingsBacking
    private let config: CatConfig

    init(backing: any CatSettingsBacking = UserDefaults.standard, config: CatConfig = .shared) {
```

and replace it with:

```swift
    @Published private(set) var settings: CatSettings
    private let backing: any CatSettingsBacking
    /// The engines' shared settings, which this store feeds; Settings' previews read it too.
    let config: CatConfig

    init(backing: any CatSettingsBacking = UserDefaults.standard, config: CatConfig = .shared) {
```

**Create `NotchBuddy/Sources/App/CatSettingsView.swift`**:

```swift
import AppKit
import QuartzCore
import SwiftUI

// Settings → Cat: the character, how it moves, its personality and the fur lines. Built from the rows Settings already has (a GroupBox per topic,
// a label of 110 pt and a control, grey 11 pt notes): no existing row changes. Everything it shows is `CatSettingsStore.settings`, and every change
// goes through the store, which cleans it, saves it and hands it to the engines, so a cat in the notch changes while you drag a slider.
// Each cat keeps its own motion override and personality: the rows below the character grid are for the character that is picked.

struct CatSettingsView: View {
    @ObservedObject var store: CatSettingsStore
    /// True while the Settings window is on screen and the key window (`WindowVisibility` reports it); the previews stop when it is not.
    @State private var windowVisible = true
    /// The offscreen render script has no window to report: it asks for live previews outright.
    private let alwaysActive: Bool

    init(store: CatSettingsStore = .shared, alwaysActive: Bool = false) {
        self.store = store
        self.alwaysActive = alwaysActive
    }

    private var active: Bool { alwaysActive || windowVisible }
    private var id: String { store.settings.character }
    private var entry: CatSettings.Entry { store.settings.cats[id] ?? CatSettings.Entry() }
    private var label: String { CatPresets.byID(id).label }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            characterGroup
            motionGroup
            personalityGroup
            lookGroup
            allCatsGroup
        }
        .background(WindowVisibility(visible: $windowVisible))
    }

    // MARK: Character

    private var characterGroup: some View {
        GroupBox("Character") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    // A head of Ø60 and more is where fur lines show, so the chosen cat is drawn big (the 16 below are Ø36).
                    CatPreviewView(id: id, head: 84, active: active, config: store.config)
                        .frame(width: 130, height: 118)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label).font(.system(size: 13, weight: .semibold))
                        Text(CatPresets.byID(id).desc ?? "").font(.system(size: 11)).foregroundColor(.secondary)
                        Text("The cat that lives in your notch and in the small pills. Each one keeps its own motion and personality.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 8)], spacing: 8) {
                    ForEach(CatPresets.ids, id: \.self) { tile($0) }
                }
            }
            .padding(6)
        }
    }

    private func tile(_ cat: String) -> some View {
        let selected = cat == id, preset = CatPresets.byID(cat)
        return Button { store.setCharacter(cat) } label: {
            VStack(spacing: 0) {
                CatPreviewView(id: cat, head: 36, active: active, config: store.config)
                    .frame(width: 60, height: 52)
                Text(preset.label)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundColor(selected ? .primary : .secondary)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.16) : Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help("\(preset.label), \(preset.desc ?? "")")
        .accessibilityLabel(preset.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Motion

    private var motionGroup: some View {
        GroupBox("Motion") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Style").frame(width: 130, alignment: .leading)
                    Picker("", selection: Binding(get: { store.settings.motionStyle }, set: { store.setMotionStyle($0) })) {
                        Text("Playful").tag("playful")
                        Text("Classic").tag("classic")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                Text("Playful is cat body language. Classic moves 1:1 like the original character.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Text("This cat's motion").frame(width: 130, alignment: .leading)
                    Picker("", selection: Binding(get: { entry.motion }, set: { store.setMotionOverride($0, for: id) })) {
                        Text("Follow the style").tag(CatSettings.follow)
                        Text("Playful").tag("playful")
                        Text("Classic").tag("classic")
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    Text(label).font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    // MARK: Personality

    private var personalityGroup: some View {
        GroupBox("Personality") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    CatPreviewView(id: id, head: 62, active: active, config: store.config)
                        .frame(width: 96, height: 84)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Preset").frame(width: 74, alignment: .leading)
                            Picker("", selection: Binding(get: { entry.personality.preset }, set: { if $0 != "custom" { store.setPreset($0, for: id) } })) {
                                ForEach(Personality.presets, id: \.key) { Text($0.label).tag($0.key) }
                                if entry.personality.preset == "custom" { Text("Custom").tag("custom") }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                        Text("\(label)'s personality. Moving any slider turns it into Custom.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                ForEach(Personality.traits, id: \.key) { trait in slider(trait) }
            }
            .padding(6)
        }
    }

    private func slider(_ trait: (key: String, label: String, low: String, high: String)) -> some View {
        let value = entry.personality[trait.key] ?? 0.5
        return HStack(spacing: 8) {
            Text(trait.label).frame(width: 74, alignment: .leading)
            Text(trait.low).font(.system(size: 10)).foregroundColor(.secondary).frame(width: 70, alignment: .trailing)
            Slider(value: Binding(get: { value }, set: { store.setTrait(trait.key, $0, for: id) }), in: 0...1)
                .frame(minWidth: 80)
            Text(trait.high).font(.system(size: 10)).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
            Text(String(format: "%.2f", value)).font(.system(size: 11).monospacedDigit()).foregroundColor(.secondary).frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: Look

    private var lookGroup: some View {
        GroupBox("Look") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Fur lines", isOn: Binding(get: { store.settings.furLines }, set: { store.setFurLines($0) }))
                Text("Fine fur strands on the big cat. Off keeps the flat colour.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    // MARK: Apply to every cat

    private var allCatsGroup: some View {
        GroupBox("Every cat") {
            HStack(spacing: 10) {
                Button("Apply to every cat") { store.applyToAll(from: id) }
                Text("Copies \(label)'s motion, personality and collar to all 16 cats.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

// MARK: - A small live cat

/// A live cat for Settings. It owns one silent engine on the store's `CatConfig` (so it shows that cat's own motion and personality, and a change
/// in Settings shows on its next frame), and it draws only while `active`: the timeline is paused when the Settings window is not on screen.
struct CatPreviewView: View {
    let id: String
    /// The head width in px.
    let head: Double
    let active: Bool
    let config: CatConfig
    @StateObject private var engine: CatEngine

    init(id: String, head: Double, active: Bool, config: CatConfig) {
        self.id = id; self.head = head; self.active = active; self.config = config
        _engine = StateObject(wrappedValue: CatEngine(CatPresets.byID(id), now: { CACurrentMediaTime() * 1000 }, cfg: config))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                engine.useCharacter(id)
                engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                var options = CatDrawOptions(badge: false)
                options.fur = config.furLines
                context.withCGContext { cg in
                    CatRenderer.draw(cg, engine.look(), cx: Double(size.width) / 2, cy: Double(size.height) / 2 + head * 0.08, D: head, options)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Is the window on screen?

/// Reports whether the window this view is in is on screen and the key window: visible, not minimised, not hidden behind other windows, and the one
/// that has the keyboard (the Windows app also stops its previews when Settings is not focused). Settings keeps its window (and its views) after it is
/// closed, so `onAppear` and `onDisappear` cannot tell; the previews pause on this instead.
struct WindowVisibility: NSViewRepresentable {
    @Binding var visible: Bool

    func makeNSView(context: Context) -> NSView {
        let view = TrackerView()
        view.onChange = { visible = $0 }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TrackerView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens = []
            guard let w = window else { report(false); return }
            let center = NotificationCenter.default
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                         NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                tokens.append(center.addObserver(forName: name, object: w, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.report() } })
            }
            // will-close comes while the window still says it is visible: it is hidden by the time anyone asks again, so report it directly.
            tokens.append(center.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.report(false) } })
            report()
        }

        private func report() {
            guard let w = window else { return report(false) }
            report(w.isVisible && !w.isMiniaturized && w.occlusionState.contains(.visible) && w.isKeyWindow)
        }

        /// Reported on the next turn of the run loop: this can be called while SwiftUI is still updating the view.
        private func report(_ on: Bool) { DispatchQueue.main.async { [weak self] in self?.onChange?(on) } }
    }
}
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`**, find this text (it occurs exactly once):

```swift
                        SettingsSidebarRow(title: "Integrations", icon: "puzzlepiece.extension.fill",        color: "#7C5CFF").tag("integrations")
                        SettingsSidebarRow(title: "Shortcuts",    icon: "keyboard.fill",                     color: "#2FB5A6").tag("shortcuts")
                    }
                    .listStyle(.sidebar)
```

and replace it with:

```swift
                        SettingsSidebarRow(title: "Integrations", icon: "puzzlepiece.extension.fill",        color: "#7C5CFF").tag("integrations")
                        SettingsSidebarRow(title: "Shortcuts",    icon: "keyboard.fill",                     color: "#2FB5A6").tag("shortcuts")
                        SettingsSidebarRow(title: "Cat",          icon: "pawprint.fill",                     color: "#D9A066").tag("cat")
                    }
                    .listStyle(.sidebar)
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`**, find this text (it occurs exactly once):

```swift
        case "integrations": return "Integrations"
        case "shortcuts":    return "Shortcuts"
        default:             return "General"
        }
```

and replace it with:

```swift
        case "integrations": return "Integrations"
        case "shortcuts":    return "Shortcuts"
        case "cat":          return "Cat"
        default:             return "General"
        }
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`**, find this text (it occurs exactly once):

```swift
        case "integrations": integrationsSection
        case "shortcuts":    ShortcutsSettingsView()
        default:             generalSection
        }
```

and replace it with:

```swift
        case "integrations": integrationsSection
        case "shortcuts":    ShortcutsSettingsView()
        case "cat":          CatSettingsView()
        default:             generalSection
        }
```

- [ ] **Step 4: Run the pins and build**

Run: `bash scripts/test-cat-settings.sh 2>&1 | grep -E "✗|passed|failed"`
Expected: `All tests passed.`

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: the last lines end with `** BUILD SUCCEEDED **`.

- [ ] **Step 5: The script that draws the section without launching the app**

It puts `CatSettingsView` in a window that is never shown, on a store of its own (a dictionary and a `CatConfig` of its own: nothing the user saved is read or changed), steps the previews for 1.5 s and draws the window into a PNG, the way `render-cat-panel.sh` draws the Debug panel. The system controls come out in this bitmap on this machine; if a future macOS leaves them blank, the cats and the layout are still there.

**Create `scripts/render-cat-settings.sh`**:

```bash
#!/usr/bin/env bash
# Draws Settings → Cat into a PNG without launching NotchMeow (see scripts/render-cat-settings.swift).
#   bash scripts/render-cat-settings.sh --out settings.png [--height 1500] [--width 520] [--character momo] [--preset chill] [--fur]
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-settings.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatSettings.swift $APP/CatSettingsStore.swift $APP/CatSettingsView.swift \
    scripts/render-cat-settings.swift \
    -o "$BUILD_DIR/render-cat-settings"
"$BUILD_DIR/render-cat-settings" "$@"
```

**Create `scripts/render-cat-settings.swift`**:

```swift
import AppKit
import SwiftUI

// Draws Settings → Cat (CatSettingsView.swift) into a PNG without launching NotchMeow: the section's own SwiftUI view goes into a window that is never
// shown, and AppKit lays it out and draws it into a bitmap. It runs on a store of its own (a dictionary and a CatConfig of its own, no UserDefaults), so
// nothing the user saved is read or changed. The previews are live engines, stepped for 1.5 s before the shot. The system controls (pickers, sliders,
// group boxes, buttons) may come out blank in this offscreen bitmap; the cats and the layout do not.
// Run it through scripts/render-cat-settings.sh:
//   bash scripts/render-cat-settings.sh [--out settings.png] [--height 1500] [--width 520] [--character momo] [--preset chill] [--fur]

final class MemoryBacking: CatSettingsBacking {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}

@main
struct RenderCatSettings {
    @MainActor static func main() {
        var out = "cat-settings.png", height = 1500.0, width = 520.0, character = "momo", preset = "chill", fur = false
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? out
            case "--height": height = Double(it.next() ?? "") ?? height
            case "--width": width = Double(it.next() ?? "") ?? width
            case "--character": character = it.next() ?? character
            case "--preset": preset = it.next() ?? preset
            case "--fur": fur = true
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        _ = NSApplication.shared
        let store = CatSettingsStore(backing: MemoryBacking(), config: CatConfig())
        store.setCharacter(character)
        store.setPreset(preset, for: character)
        store.setFurLines(fur)
        let host = NSHostingView(rootView: ScrollView { CatSettingsView(store: store, alwaysActive: true).padding(20) }.frame(width: width, height: height))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = .windowBackgroundColor
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))   // SwiftUI lays out, and the previews' engines run for a moment
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { FileHandle.standardError.write(Data("no bitmap\n".utf8)); exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        // The offscreen bitmap has no window background (the text is for a dark window): put it on one.
        guard let shot = rep.cgImage,
              let cg = CGContext(data: nil, width: shot.width, height: shot.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        cg.setFillColor(CGColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1))
        cg.fill(CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        cg.draw(shot, in: CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        guard let flat = cg.makeImage(), let png = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    }
}
```

Run: `d="${TMPDIR:-/tmp}/a-mac-5-7"; mkdir -p "$d" && bash scripts/render-cat-settings.sh --out "$d/settings.png" --height 1150 && bash scripts/render-cat-settings.sh --out "$d/settings-narrow.png" --height 1150 --width 440 --character latte --preset hyper --fur`
Expected: `wrote …/settings.png` and `wrote …/settings-narrow.png` (520 pt is the Settings window's default width; 440 pt is its narrowest content).

Look at both. Expected: the Character group shows a big live cat (Ø84) with its name, then 16 tiles with a live cat each, Shrimpy first and Momo second, the chosen one outlined; under it the Motion group (a Playful/Classic control and "This cat's motion"), the Personality group (the big preview, a Preset menu, six sliders each with its low and high word and its value), Look (Fur lines) and "Apply to every cat". At 440 pt nothing is cut off at either side.

- [ ] **Step 6: Commit**

```bash
git add NotchBuddy/Sources/App/CatSettingsView.swift NotchBuddy/Sources/App/CatSettingsStore.swift NotchBuddy/Sources/App/SettingsView.swift tests/CatSettingsTests.swift scripts/render-cat-settings.sh scripts/render-cat-settings.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): the Cat section of Settings: character, motion, personality, fur lines and Apply to every cat

Built from the rows Settings already has, after Shortcuts. Sixteen live previews and a big one that draw only while the
Settings window is on screen. render-cat-settings.sh draws the section into a PNG without launching the app.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Owner checkpoint 1: the Cat section and the fur lines

No code and no commit. The session runs the checks, produces the images and stops; the main session sends them to the owner.

- [ ] **Step 1: The tests and the builds**

Run: `for f in scripts/test-cat-*.sh; do printf '%-42s' "$f"; bash "$f" 2>&1 | tail -1; done`
Expected: fifteen lines: `scripts/test-cat-contract.sh` ends `✓ two generator runs write identical bytes` and the other fourteen (`devpanel`, `effects`, `engine`, `frame-meter`, `fur`, `geometry`, `greeting`, `personality`, `presets`, `renderer`, `rules`, `settings-store`, `settings`, `upload`) end `All tests passed.`

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: The images**

Run: `d="${TMPDIR:-/tmp}/a-mac-5-7"; c=.claude/checkpoints/a-cats-5-7/mac-1; mkdir -p "$d" "$c" && bash scripts/render-cat-settings.sh --out "$c/settings-momo.png" --height 1150 && bash scripts/render-cat-settings.sh --out "$c/settings-latte-hyper-fur.png" --height 1150 --character latte --preset hyper --fur && bash scripts/render-cats.sh --fur --cats shrimpy,momo,cloud,ginger,puff --out "$c/fur.png" && bash scripts/render-cats.sh --out "$c/ladder.png" && ls "$c"`
Expected: four `wrote …` lines and `fur.png`, `ladder.png`, `settings-latte-hyper-fur.png`, `settings-momo.png`. (The ladder is the stage 1 to 4 contact sheet again: every coat at every size, to see that nothing changed with fur off.)

- [ ] **Step 3: Send the owner these, and ask**

Send `settings-momo.png`, `settings-latte-hyper-fur.png` and `fur.png` (and the ladder if they want to compare with checkpoint 1 of stages 1 to 4). Ask:

1. **The look of the Cat section.** Does it read like the other Settings sections? It sits **last** in the sidebar, after Shortcuts (Open question 2). The chosen cat is drawn big beside the 16 tiles (Open question 11). The rows below the character grid edit the chosen cat; is "pick the cat first" clear, or should each row name the cat (it does, in small grey type: "Momo")?
2. **The fur lines.** Does the strand density, length and colour look like the prototype's "Fur lines" option and the Windows `?dev` page? They are the prototype's own seeds; only a head of Ø60 and up shows them.
3. **The 16 tiles.** Are the previews the right size (a Ø36 head in a 60 by 52 pt tile)? Each is a real engine, so a Hyper cat moves more than a Chill one.

The owner's manual checks on a **Debug build** (quit the installed app first; the session never launches it): open Settings → Cat and pick another character: the cat in the notch changes at once; move a slider: the cat's behaviour follows (Energy to the left: sleepier); quit and reopen: the choices are still there (`defaults read io.github.aikusan.notchmeow cat.character`); close Settings and watch Activity Monitor: no CPU for a closed Settings window; hand-edit `cat.personality.momo` to `{` with `defaults write io.github.aikusan.notchmeow cat.personality.momo '{'` and reopen: Settings opens and Momo is Balanced.

Record the answers. Nothing in Tasks 6 to 15 depends on them except a changed look of the Cat section, which would be a fix round.

---
### Task 6: The collar's geometry, from `collar-cases.json` (stage 6)

**Agent:** `nm-implementer-light`. The code is given in full; the fixture proves it.

**Files:**
- Modify: `NotchBuddy/Sources/App/CatGeometry.swift` (`collarGeometry`, `CollarMin`, `collarPass`), `tests/CatGeometryTests.swift`, `tests/CatRulesTests.swift`

**Interfaces:**
- Consumes: the contract's collar (A-0b, merged `6adf584`): `COLLAR_MIN`, `collarStyleOf`, `collarGeometry`, `COLLAR_PASS` and `tests/fixtures/cat/collar-cases.json` (keys `styles`, `min`, `resolve`, `cases`: 164 cases, each style at Ø12 to Ø66, at pixel ratio 1 and 2, at rest and with the head turned); `CatRules.collarStyles` and `collarStyleOf` (Task 1).
- Produces `CatGeometry.collarStyles` (`["tag", "band", "kerchief"]`, the three that are drawn), `CatGeometry.CollarMin` (`band` 3, `tag` 6, `kerchiefW` 7, `kerchiefDrop` 5, in device pixels), `CatGeometry.collarPass` (`"front"`), `CatGeometry.Collar` (`style`, `R`, `width`, `band`, `tag`, `kerchief`, `json`), and two overloads of `CatGeometry.collarGeometry`: `(preset, R:, warp:, style:, dpr:)`, which the renderer calls with the `R` and warp of the cat it already laid out, and `(preset, pose, D:, style:, dpr:, detail:)`, which is the contract's call and makes the layout itself. `nil` for `off` and for a style that is not one of the three; a pixel ratio that is not above 0 counts as 2.

- [ ] **Step 1: Write the failing tests**

The geometry program replays the 164 cases and checks that the floors hold on all 16 coats at Ø12 and pixel ratios 1, 2 and 3 (a band never under 3 device px thick, a tag never under 6 across, a neckerchief never under 7 wide and 5 deep). The rules program replays `resolve` (a stored word to a style).

**Edit `tests/CatGeometryTests.swift`**, find this text (it occurs exactly once):

```swift
        var notANumber = CatPose(); notANumber.tilt = .nan
        CT.check("a tilt that is not a number leaves nothing to fit: 1", fitOf(CatPresets.byID("momo"), notANumber, D: 20), 1)
        CT.finish()
    }
```

and replace it with:

```swift
        var notANumber = CatPose(); notANumber.tilt = .nan
        CT.check("a tilt that is not a number leaves nothing to fit: 1", fitOf(CatPresets.byID("momo"), notANumber, D: 20), 1)

        CT.section("the collar (A-0b, merged `6adf584`): collar-cases.json")
        let col = CT.fixture("collar-cases.json")
        let cases = col["cases"] as! [[String: Any]], floors = col["min"] as! [String: Any]
        CT.check("the styles that are drawn, in the contract's order, then off", G.collarStyles + ["off"], col["styles"] as! [String])
        CT.check("the readability floors, in device pixels", [G.CollarMin.band, G.CollarMin.tag, G.CollarMin.kerchiefW, G.CollarMin.kerchiefDrop],
                 ["band", "tag", "kerchiefW", "kerchiefDrop"].map { num(floors[$0]) })
        CT.check("the collar is drawn in the front pass", G.collarPass, geo["collarPass"] as! String)
        var collarDiffs: [String] = []
        for c in cases {
            let p = preset(c["cat"] as! String, c["kitten"] as! Bool), s = pose(c["pose"] as! [String: Any]), D = num(c["D"]), style = c["style"] as! String
            let got: Any = G.collarGeometry(p, s, D: D, style: style, dpr: num(c["dpr"]))?.json ?? NSNull()
            let d = CT.diffs(got, c["out"] ?? NSNull())
            if !d.isEmpty { collarDiffs.append("\(c["cat"]!) \(style) Ø\(D) dpr \(c["dpr"]!) \(c["pose"]!): \(d.first!)") }
        }
        CT.checkRows("\(cases.count) cases: each style at Ø12 to Ø66, at pixel ratio 1 and 2, at rest and with the head turned", collarDiffs)
        CT.checkTrue("off, and a style nobody knows, have no collar", G.collarGeometry(CatPresets.byID("momo"), CatPose(), D: 20, style: "off") == nil && G.collarGeometry(CatPresets.byID("momo"), CatPose(), D: 20, style: "scarf") == nil)
        CT.checkTrue("a pixel ratio that is not above 0 counts as 2", G.collarGeometry(CatPresets.byID("momo"), CatPose(), D: 20, style: "band", dpr: 0)?.width == G.collarGeometry(CatPresets.byID("momo"), CatPose(), D: 20, style: "band", dpr: 2)?.width
                     && G.collarGeometry(CatPresets.byID("momo"), CatPose(), D: 20, style: "band", dpr: .nan)?.width == G.collarGeometry(CatPresets.byID("momo"), CatPose(), D: 20, style: "band", dpr: 2)?.width)
        // The floors: at Ø12 a band is never thinner than 3 device pixels, a tag never smaller than 6 across, a neckerchief never narrower than 7 or shallower than 5.
        var floorDiffs: [String] = []
        for id in CatPresets.ids {
            for dpr in [1.0, 2, 3] {
                let p = CatPresets.byID(id)
                if let b = G.collarGeometry(p, CatPose(), D: 12, style: "band", dpr: dpr), b.width! * dpr < G.CollarMin.band - 1e-9 { floorDiffs.append("\(id) band at dpr \(dpr): \(b.width! * dpr) px") }
                if let t = G.collarGeometry(p, CatPose(), D: 12, style: "tag", dpr: dpr), t.tag!.r * 2 * dpr < G.CollarMin.tag - 1e-9 { floorDiffs.append("\(id) tag at dpr \(dpr)") }
                if let k = G.collarGeometry(p, CatPose(), D: 12, style: "kerchief", dpr: dpr)?.kerchief {
                    let xs = k.pts.map { $0.x }, drop = k.apex.y - k.pts.map { $0.y }.max()!
                    if (xs.max()! - xs.min()!) * dpr < G.CollarMin.kerchiefW - 1e-9 || drop * dpr < G.CollarMin.kerchiefDrop - 1e-9 { floorDiffs.append("\(id) kerchief at dpr \(dpr)") }
                }
            }
        }
        CT.checkRows("all 16 coats at Ø12 and at pixel ratios 1, 2 and 3 keep the floors of the contract", floorDiffs)
        CT.finish()
    }
```

**Edit `tests/CatRulesTests.swift`**, find this text (it occurs exactly once):

```swift
        for w in sleep["wake"] as! [[String: Any]] { CT.check("\"\(w["kind"]!)\" wakes: \(w["wakes"]!)", CatRules.wakes(w["kind"] as! String), w["wakes"] as! Bool) }

        CT.section("which tool names mean searching")
        CT.checkJSON("the lists", got: CatRules.searchTools, want: tools["agents"]!)
```

and replace it with:

```swift
        for w in sleep["wake"] as! [[String: Any]] { CT.check("\"\(w["kind"]!)\" wakes: \(w["wakes"]!)", CatRules.wakes(w["kind"] as! String), w["wakes"] as! Bool) }

        CT.section("which collar a stored word means (collar-cases.json `resolve`)")
        let collars = CT.fixture("collar-cases.json")
        CT.check("the four styles, in the contract's order", CatRules.collarStyles, collars["styles"] as! [String])
        var resolveDiffs: [String] = []
        for r in collars["resolve"] as! [[String: Any]] where CatRules.collarStyleOf(r["id"] ?? NSNull()) != r["style"] as! String { resolveDiffs.append("\(r["id"] ?? "null") should be \(r["style"]!)") }
        CT.checkRows("\((collars["resolve"] as! [Any]).count) stored words: an unknown style, a wrong case, a number or null is off", resolveDiffs)
        CT.check("a missing value is off", CatRules.collarStyleOf(nil), "off")

        CT.section("which tool names mean searching")
        CT.checkJSON("the lists", got: CatRules.searchTools, want: tools["agents"]!)
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-geometry.sh 2>&1 | grep -E "error" | head -2`
Expected: FAIL: `error: type 'CatGeometryTests.G' (aka 'CatGeometry') has no member 'collarStyles'`.

Run: `bash scripts/test-cat-rules.sh 2>&1 | grep -E "✗|passed|failed"`
Expected: `All tests passed.` (the stored-word rules are Task 1's, and now have their fixture).

- [ ] **Step 3: Write the geometry**

A port of the contract's `collarGeometry`: the ring is the head outline inset by `k` (so the band's outer edge stays inside the head), the band is the 40° to 140° arc left to right, the tag a round disc at centre front, the neckerchief a triangle from the arc's points to an apex below them; every point goes through the face warp, so the collar turns with the head.

**Edit `NotchBuddy/Sources/App/CatGeometry.swift`**, find this text (it occurs exactly once):

```swift
    }

    /// The draw order, as named layers. The renderer draws a *behind* pass, the head, then a *front* pass, so outfits
    /// (sub-project I) can sit behind or in front of the head. Each layer's data comes from `layout`. The collar of stage 6 goes in the
```

and replace it with:

```swift
    }

    // MARK: Collar (the contract's `collarGeometry`, A-0b)

    /// The collar styles that are drawn, in the contract's order (the fourth, "off", draws nothing). Frozen: Settings stores them (`CatRules.collarStyles`).
    static let collarStyles = ["tag", "band", "kerchief"]
    /// The renderer pass the collar is drawn in: between `foldEars` and `whiskers` of the front pass. `passes` itself stays as A-0 pinned it.
    static let collarPass = "front"
    /// The smallest sizes, in DEVICE pixels, so a collar still reads as a colour at Ø12 and Ø20 (the contract's `COLLAR_MIN`).
    enum CollarMin { static let band = 3.0, tag = 6.0, kerchiefW = 7.0, kerchiefDrop = 5.0 }

    /// Where one collar sits, in head-local px (before the tilt and the squash), turning with the face warp.
    /// `band`: a polyline along the lower outline, left to right, inset so its outer edge stays inside the head, drawn `width` thick (tag and band);
    /// `tag`: a round tag at centre front; `kerchief`: a triangle under the chin, `pts` along the lower outline and `apex` below them.
    struct Collar {
        var style: String
        var R: Double
        var width: Double?
        var band: [(x: Double, y: Double)]?
        var tag: (x: Double, y: Double, r: Double)?
        var kerchief: (pts: [(x: Double, y: Double)], apex: (x: Double, y: Double))?

        /// The collar as the fixtures hold it (key `out` of collar-cases.json).
        var json: [String: Any] {
            var out: [String: Any] = ["style": style, "R": R]
            if let width { out["width"] = width }
            if let band { out["band"] = band.map { [$0.x, $0.y] } }
            if let tag { out["tag"] = ["x": tag.x, "y": tag.y, "r": tag.r] }
            if let kerchief { out["kerchief"] = ["pts": kerchief.pts.map { [$0.x, $0.y] }, "apex": [kerchief.apex.x, kerchief.apex.y]] as [String: Any] }
            return out
        }
    }

    /// The collar for a style, given the head's radius `R` (px) and its warp. `dpr` is the device pixel ratio (a value that is not above 0 counts as 2).
    /// nil for "off", and for a style that is not one of the three. This is what the renderer calls (it already has `R` and the warp of the cat it draws).
    static func collarGeometry(_ p: CatPreset, R: Double, warp W: Warp, style: String, dpr dprIn: Double = 2) -> Collar? {
        guard collarStyles.contains(style) else { return nil }
        let dpr = dprIn > 0 ? dprIn : 2
        let width = max(0.1 * R, CollarMin.band / dpr)                       // a tenth of R, never under 3 device px
        let k = max(0.7, min(0.92, 1 - (width / 2 + 0.5 / dpr) / (p.ry * R)))
        let n = 90
        let ring = Array(supPoints(rx: p.rx * k, ry: p.ry * k, n: p.n, dy: 0, spike: 0, count: 0, steps: n).prefix(n))   // R units; index i is i/90 of a turn, y down
        var out = Collar(style: style, R: R)
        if style == "kerchief" {
            let hw = min(p.rx * k, max(0.5 * p.rx, CollarMin.kerchiefW / dpr / R * 0.65))
            let arc = ring.enumerated().filter { $0.element.1 > 0 && abs($0.element.0) <= hw }
                .sorted { $0.element.0 < $1.element.0 || ($0.element.0 == $1.element.0 && $0.offset < $1.offset) }.map { $0.element }
            let (ax, ay) = W(0, p.ry * k)
            let pts = arc.map { W($0.0, $0.1) }, top = pts.map { $0.1 }.max() ?? -Double.infinity
            out.kerchief = (pts.map { (x: $0.0, y: $0.1) }, (x: ax, y: max(ay, top) + max(0.34 * R, CollarMin.kerchiefDrop / dpr)))
        } else {
            let lower = Array(ring[(n * 40 / 360)...(n * 140 / 360)].reversed())   // left to right, 40° to 140°
            out.width = width
            out.band = lower.map { q in let w = W(q.0, q.1); return (x: w.0, y: w.1) }
            if style == "tag" {
                let (x, y) = W(0, p.ry * k)
                out.tag = (x: x, y: y, r: max(0.16 * R, CollarMin.tag / dpr / 2))
            }
        }
        return out
    }

    /// The same for a pose and a head width, the way the contract's `collarGeometry(preset, pose, D, style, {dpr, detail})` is called: it makes the
    /// layout itself to get `R` and the warp. `detail` is as in `layout`.
    static func collarGeometry(_ p: CatPreset, _ s: CatPose, D: Double, style: String, dpr: Double = 2, detail: String? = nil) -> Collar? {
        let L = layout(p, s, cx: 0, cy: 0, D: D, Options(full: detail.map { $0 == "full" }))
        return collarGeometry(p, R: L.R, warp: L.warp, style: style, dpr: dpr)
    }

    /// The draw order, as named layers. The renderer draws a *behind* pass, the head, then a *front* pass, so outfits
    /// (sub-project I) can sit behind or in front of the head. Each layer's data comes from `layout`. The collar of stage 6 goes in the
```

- [ ] **Step 4: Run the tests**

Run: `bash scripts/test-cat-geometry.sh 2>&1 | grep -E "✗|passed|failed|164"`
Expected: `✓ 164 cases: each style at Ø12 to Ø66, at pixel ratio 1 and 2, at rest and with the head turned` and `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/App/CatGeometry.swift tests/CatGeometryTests.swift tests/CatRulesTests.swift
git commit -m "feat(cat): the collar's geometry in Swift, replaying collar-cases.json

Three styles from the contract's collarGeometry (164 cases) with the readability floors in device pixels, checked on all
16 coats at Ø12 and pixel ratios 1, 2 and 3. The renderer-facing overload takes the R and warp it already has.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 7: The collar's paint, the readability floors and the collar sheet (stage 6)

**Agent:** `nm-implementer`. The code is given in full; the pixel counts and the sheet are what to read.

**Files:**
- Modify: `NotchBuddy/Sources/App/CatLook.swift` (`CatCollarPaint`, `CatDrawOptions.collar`), `NotchBuddy/Sources/App/CatEffects.swift` (`drawCollar`), `NotchBuddy/Sources/App/CatRenderer.swift` (the front pass), `tests/CatRendererTests.swift`, `scripts/render-cats.swift` (`--collars`)

**Interfaces:**
- Consumes: Task 6's `CatGeometry.collarGeometry(_:R:warp:style:dpr:)` and `Collar`.
- Produces `CatCollarPaint(style:color:dpr:)` (a style, the agent's `#RRGGBB` colour and the device pixel ratio; the style `off` or an unknown one paints nothing) and `CatDrawOptions.collar` (default `nil`); `CatEffects.drawCollar(_:_:color:full:dpr:)`. The renderer draws the collar **in the front pass, after the folded ears and before the whiskers, at every size from Ø12**; it never recolours the coat.

- [ ] **Step 1: Write the failing tests**

They draw each style on six coats (Shrimpy, Momo, Latte, Midnight, Snow, Puff) at Ø12 to Ø66 and at 1x and 2x, in a green no coat is near, and count the green pixels. The floors are the contract's (a band 3 device px thick, a tag 6 across, a neckerchief 7 wide and 5 deep); the counts below are the least ink measured at Ø12 on those coats (a band 26, a tag 30, a neckerchief 5 on a 1x screen; 56, 60 and 12 on a 2x screen) with a margin. They also check that nothing above the head's middle changes, that the collar turns with the head, and (as a source pin) that it is drawn after the folded ears and before the whiskers.

**Edit `tests/CatRendererTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkTrue("at the compact detail nothing changes", fur("shrimpy", 140, on: true, full: false) == fur("shrimpy", 140, on: false, full: false))
        CT.checkTrue("Noodle has no fur, so nothing changes", fur("noodle", 140, on: true) == fur("noodle", 140, on: false))
        CT.finish()
    }
```

and replace it with:

```swift
        CT.checkTrue("at the compact detail nothing changes", fur("shrimpy", 140, on: true, full: false) == fur("shrimpy", 140, on: false, full: false))
        CT.checkTrue("Noodle has no fur, so nothing changes", fur("noodle", 140, on: true) == fur("noodle", 140, on: false))

        CT.section("the collar: drawn in the front pass from Ø12 up, readable at every size, turning with the head, and the coat is never recoloured")
        let green = "#00FF66"   // no coat is anywhere near it, so the pixels of the collar can be counted
        func collared(_ id: String, _ D: Double, _ style: String?, dpr: Double = 2, yaw: Double = 0) -> [UInt8] {
            let n = Int(D * 3 * dpr)
            var s = CatPose(); s.yaw = yaw
            return render(n, n) { cg in
                cg.scaleBy(x: dpr, y: dpr)
                var o = CatDrawOptions(); o.collar = style.map { CatCollarPaint(style: $0, color: green, dpr: dpr) }
                R.draw(cg, CatLook(preset: CatPresets.byID(id), pose: s), cx: D * 1.5, cy: D * 1.5, D: D, o)
            }
        }
        /// The painted pixels that are green: the collar's colour or its tint (the tag is a lighter tint), which no coat has.
        func ink(_ px: [UInt8]) -> [(x: Int, y: Int)] {
            let w = Int(Double(px.count / 4).squareRoot())
            return stride(from: 0, to: px.count, by: 4).filter { px[$0 + 3] > 200 && px[$0 + 1] > 150 && px[$0] < 170 && px[$0 + 2] < 200 }.map { (($0 / 4) % w, ($0 / 4) / w) }
        }
        let plainCat = collared("shrimpy", 20, nil), none = CatDrawOptions().collar == nil
        CT.checkTrue("no collar is the default", none && collared("shrimpy", 20, nil) == plainCat)
        CT.checkTrue("off, and a style nobody knows, paint nothing", collared("shrimpy", 20, "off") == plainCat && collared("shrimpy", 20, "scarf") == plainCat)
        // The least ink a style may leave at Ø12 on any of these coats, at 1x and at 2x (measured with the contract's floors: a band 3 device px thick, a tag
        // 6 across, a neckerchief 7 wide and 5 deep; the neckerchief's dark edge eats most of a triangle that small, so it has the least).
        let least: [String: (Int, Int)] = ["band": (20, 45), "tag": (24, 50), "kerchief": (4, 10)]
        var weak: [String] = [], recoloured: [String] = []
        for id in ["shrimpy", "momo", "latte", "midnight", "snow", "puff"] {
            for style in ["tag", "band", "kerchief"] {
                for D in [12.0, 16, 20, 28, 44, 66] {
                    for dpr in [1.0, 2] {
                        let on = collared(id, D, style, dpr: dpr), off = collared(id, D, nil, dpr: dpr), n = ink(on).count
                        if D == 12 && n < (dpr == 1 ? least[style]!.0 : least[style]!.1) { weak.append("\(id) \(style) Ø12 at \(Int(dpr))x: \(n) pixels") }
                        if D > 12 && n == 0 { weak.append("\(id) \(style) Ø\(Int(D)) at \(Int(dpr))x: none") }
                        // Above the head's middle (a fifth of the head width above it, because a band 3 px thick at Ø12 reaches the middle row) nothing
                        // differs: the collar sits on the lower head, and the coat is never recoloured.
                        let w = Int(D * 3 * dpr), top = Int((D * 1.5 - D * 0.2) * dpr) * w * 4
                        if Array(on[0..<top]) != Array(off[0..<top]) { recoloured.append("\(id) \(style) Ø\(Int(D)) at \(Int(dpr))x") }
                    }
                }
            }
        }
        CT.checkRows("every style on six coats at Ø12 to Ø66 and at 1x and 2x leaves enough ink (Ø12 at the contract's floors)", weak)
        CT.checkRows("the upper half of the head is the same with and without a collar", recoloured)
        let straight = ink(collared("shrimpy", 66, "band")), turned = ink(collared("shrimpy", 66, "band", yaw: 0.6))
        let midStraight = Double(straight.map(\.x).reduce(0, +)) / Double(straight.count), midTurned = Double(turned.map(\.x).reduce(0, +)) / Double(turned.count)
        CT.checkTrue("the collar turns with the head (its middle moves from \(Int(midStraight)) to \(Int(midTurned)) px)", abs(midTurned - midStraight) > 3)
        let rendererText = (try? String(contentsOfFile: "NotchBuddy/Sources/App/CatRenderer.swift", encoding: .utf8)) ?? ""
        func at(_ s: String) -> Int { rendererText.range(of: s)?.lowerBound.utf16Offset(in: rendererText) ?? -1 }
        CT.checkTrue("the collar is drawn after the folded ears and before the whiskers (source pin)", at("front: true, flat") > 0 && at("front: true, flat") < at("drawCollar") && at("drawCollar") < at("CatFace.drawWhiskers"))
        CT.finish()
    }
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-renderer.sh 2>&1 | grep -E "error" | head -2`
Expected: FAIL: `error: cannot find 'CatCollarPaint' in scope`.

- [ ] **Step 3: Draw the collar**

The paint is the prototype's `drawCollar`: a thin dark edge (`rgba(0,0,0,.42)`, 1.5 device px) keeps a light collar apart from a light coat; the tag is a lighter tint of the colour; at full detail the tag has a highlight and the neckerchief a crease.

**Edit `NotchBuddy/Sources/App/CatEffects.swift`**, find this text (it occurs exactly once):

```swift
    }

    // MARK: Apple Music dance

```

and replace it with:

```swift
    }

    // MARK: The collar

    /// The collar, painted (the prototype's `drawCollar`; the maths is `CatGeometry.collarGeometry`). In the head's frame, in the front pass. A thin
    /// dark edge keeps a light collar apart from a light coat; the tag is a lighter tint of the colour; at full detail the tag has a highlight and the
    /// neckerchief a crease.
    static func drawCollar(_ cg: CGContext, _ g: G.Collar, color: String, full: Bool, dpr: Double) {
        let e1 = 1 / (dpr > 0 ? dpr : 2), edge = CatDraw.black(0.42), base = CatDraw.color(color)
        func tint(_ k: Double) -> CGColor { CatDraw.rgb(hexRGB(color).map { ($0 + (255 - $0) * k).rounded() }) }
        cg.saveGState()
        if let k = g.kerchief, let apex = Optional(k.apex) {
            let path = CGMutablePath()
            for (i, q) in k.pts.enumerated() { i == 0 ? path.move(to: CGPoint(x: q.x, y: q.y)) : path.addLine(to: CGPoint(x: q.x, y: q.y)) }
            path.addLine(to: CGPoint(x: apex.x, y: apex.y))
            path.closeSubpath()
            cg.fill(path, base)
            cg.stroke(path, edge, width: 1.5 * e1)
            if full, k.pts.count > 1 {
                let m = k.pts[k.pts.count >> 1]
                cg.stroke(CatDraw.quad(m.x, m.y + g.R * 0.05, m.x, m.y + g.R * 0.05, apex.x, apex.y - g.R * 0.08), tint(0.45), width: max(e1, g.R * 0.025))
            }
        } else if let band = g.band, let width = g.width, band.count > 1 {
            let path = CGMutablePath()
            for (i, q) in band.enumerated() { i == 0 ? path.move(to: CGPoint(x: q.x, y: q.y)) : path.addLine(to: CGPoint(x: q.x, y: q.y)) }
            cg.stroke(path, edge, width: width + 2 * e1)
            cg.stroke(path, base, width: width)
            if let t = g.tag {
                cg.fill(CatDraw.circle(t.x, t.y, t.r), tint(0.55))
                cg.stroke(CatDraw.circle(t.x, t.y, t.r), edge, width: 1.5 * e1)
                if full { cg.fill(CatDraw.circle(t.x - t.r * 0.3, t.y - t.r * 0.3, t.r * 0.25), CatDraw.white(0.85)) }
            }
        }
        cg.restoreGState()
    }

    // MARK: Apple Music dance

```

**Edit `NotchBuddy/Sources/App/CatLook.swift`**, find this text (it occurs exactly once):

```swift
struct CatWave { var now: Double, start: Double, until: Double }

struct CatDrawOptions {
    /// The state tint on the lower head.
```

and replace it with:

```swift
struct CatWave { var now: Double, start: Double, until: Double }

/// A collar to wear: its style ("tag", "band" or "kerchief"; "off" and anything else draws none), the agent's colour ("#RRGGBB"; the coat is never
/// recoloured) and the device pixel ratio, which the readability floors of the contract are in (a band 3 px thick, a tag 6 across, a neckerchief
/// 7 wide and 5 deep).
struct CatCollarPaint {
    var style: String
    var color: String
    var dpr = 2.0
}

struct CatDrawOptions {
    /// The state tint on the lower head.
```

**Edit `NotchBuddy/Sources/App/CatLook.swift`**, find this text (it occurs exactly once):

```swift
    /// Optional fur strands (Settings → Cat → Fur lines), drawn on a full-detail cat from a head radius of 30 px (`CatFur.shows`). Flat colour is the default.
    var fur = false
}

```

and replace it with:

```swift
    /// Optional fur strands (Settings → Cat → Fur lines), drawn on a full-detail cat from a head radius of 30 px (`CatFur.shows`). Flat colour is the default.
    var fur = false
    /// The collar, drawn in the front pass from Ø12 up. nil: none (the default).
    var collar: CatCollarPaint?
}

```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**, find this text (it occurs exactly once):

```swift
        drawBehind(cg, look, L, flat, fur)
        drawHead(cg, look, L, o, flat, fur)
        drawFront(cg, p, s, L, flat)
        cg.restoreGState()
        if o.badge, let kind = look.badge, s.badgeS > 0.01 { CatEffects.drawBadge(cg, kind, look.badgeColor, L, look.time) }
```

and replace it with:

```swift
        drawBehind(cg, look, L, flat, fur)
        drawHead(cg, look, L, o, flat, fur)
        drawFront(cg, p, s, L, flat, o.collar)
        cg.restoreGState()
        if o.badge, let kind = look.badge, s.badgeS > 0.01 { CatEffects.drawBadge(cg, kind, look.badgeColor, L, look.time) }
```

**Edit `NotchBuddy/Sources/App/CatRenderer.swift`**, find this text (it occurs exactly once):

```swift
    // MARK: Front pass

    private static func drawFront(_ cg: CGContext, _ p: CatPreset, _ s: CatPose, _ L: G.Layout, _ flat: G.FlatColors?) {
        let R = L.R
        if p.ear.fold != nil { for e in L.ears { drawEar(cg, p, e, R: R, full: L.full, front: true, flat: flat?.ears[e.sd < 0 ? 0 : 1]) } }
        if L.full && L.fa > 0.01 { CatFace.drawWhiskers(cg, p, s, L) }
    }
```

and replace it with:

```swift
    // MARK: Front pass

    private static func drawFront(_ cg: CGContext, _ p: CatPreset, _ s: CatPose, _ L: G.Layout, _ flat: G.FlatColors?, _ collar: CatCollarPaint?) {
        let R = L.R
        if p.ear.fold != nil { for e in L.ears { drawEar(cg, p, e, R: R, full: L.full, front: true, flat: flat?.ears[e.sd < 0 ? 0 : 1]) } }
        // The collar sits over the head and the folded ears and under the whiskers (the contract's `collarPass`), at every size from Ø12 up.
        if let collar, let g = G.collarGeometry(p, R: R, warp: L.warp, style: collar.style, dpr: collar.dpr) {
            CatEffects.drawCollar(cg, g, color: collar.color, full: L.full, dpr: collar.dpr)
        }
        if L.full && L.fa > 0.01 { CatFace.drawWhiskers(cg, p, s, L) }
    }
```

- [ ] **Step 4: Run the tests**

Run: `bash scripts/test-cat-renderer.sh 2>&1 | grep -E "✗|passed|failed"; bash scripts/test-cat-effects.sh 2>&1 | tail -1`
Expected: `All tests passed.` twice.

- [ ] **Step 5: The collar sheet**

`render-cats.sh --collars` draws, for each coat, a row per style (Off first) across Ø12 to Ø66 and two turned heads, then a row per style in the six agents' colours at Ø28, on the island's black. `--scale` is the device pixel ratio the floors are measured in, so the same sheet is drawn at 2x and at 1x.

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
//   bash scripts/render-cats.sh --catch --cats shrimpy             the four-step file catch, and a refused file coughed up as a hairball
//   bash scripts/render-cats.sh --fur --cats shrimpy,momo          big cats plain and with fur lines (Settings → Cat → Fur lines), at rest and turned
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

```

and replace it with:

```swift
//   bash scripts/render-cats.sh --catch --cats shrimpy             the four-step file catch, and a refused file coughed up as a hairball
//   bash scripts/render-cats.sh --fur --cats shrimpy,momo          big cats plain and with fur lines (Settings → Cat → Fur lines), at rest and turned
//   bash scripts/render-cats.sh --collars --cats shrimpy,latte --scale 2   the three collar styles at Ø12 to Ø66, turned, and in six agent colours.
//                                                                  --scale is the device pixel ratio the readability floors are in: try 1 and 2
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case catchSheet
        case fur
    }

```

and replace it with:

```swift
        case catchSheet
        case fur
        case collars
    }

```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
            case "--catch": a.mode = .catchSheet
            case "--fur": a.mode = .fur
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

and replace it with:

```swift
            case "--catch": a.mode = .catchSheet
            case "--fur": a.mode = .fur
            case "--collars": a.mode = .collars
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case .catchSheet: sheet = catchSheet(a)
        case .fur: sheet = furSheet(a)
        }
        sheet.write(to: a.out)
```

and replace it with:

```swift
        case .catchSheet: sheet = catchSheet(a)
        case .fur: sheet = furSheet(a)
        case .collars: sheet = collarSheet(a)
        }
        sheet.write(to: a.out)
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
                CatRenderer.draw(cg, CatLook(preset: preset, pose: v.2), cx: x + cell / 2, cy: top + cell * 0.55, D: 150, CatDrawOptions(fur: v.1))
                cg.restoreGState()
            }
        }
```

and replace it with:

```swift
                CatRenderer.draw(cg, CatLook(preset: preset, pose: v.2), cx: x + cell / 2, cy: top + cell * 0.55, D: 150, CatDrawOptions(fur: v.1))
                cg.restoreGState()
            }
        }
        return sheet
    }

    // MARK: Collars: every style at every size, turned, and in the agents' colours

    /// The colours of the agents (the pill catalogue's, as the prototype's collar panel uses them).
    static let agentColors: [(name: String, hex: String)] = [("Claude Code", "#E07950"), ("Gemini CLI", "#8AB4F8"), ("Codex", "#2DD4BF"), ("Antigravity", "#E879F9"), ("Cursor", "#C0C4CC"), ("VS Code", "#F5F6F8")]

    /// Each cat: a row per style (Off first) across the head widths and two turned heads, then a row per style in the six agent colours at Ø28. The sheet's
    /// scale is the device pixel ratio the collar's floors are measured in (a band 3 px thick, a tag 6 across, a neckerchief 7 wide and 5 deep).
    @MainActor static func collarSheet(_ a: Args) -> Sheet {
        let sizes: [Double] = [12, 16, 20, 24, 28, 44, 66], cell = 84.0, labelW = 150.0, dpr = a.scale
        let styles = [("Off", "off"), ("Band and tag", "tag"), ("Band", "band"), ("Neckerchief", "kerchief")]
        var turned = CatPose(); turned.yaw = 0.6; turned.pitch = 0.2
        let columns = sizes.count + 2, rowsPerCat = styles.count + 3
        let sheet = Sheet(width: labelW + cell * Double(columns) + 8, height: 28 + (cell + 8) * Double(rowsPerCat * a.cats.count), scale: a.scale)
        let cg = sheet.cg
        for (ci, d) in sizes.enumerated() { CatDraw.text(cg, "Ø\(Int(d))", x: labelW + (Double(ci) + 0.5) * cell, y: 14, size: 12, bold: true, color: CatDraw.white(0.8)) }
        CatDraw.text(cg, "Ø20 turned", x: labelW + (Double(sizes.count) + 0.5) * cell, y: 14, size: 12, bold: true, color: CatDraw.white(0.8))
        CatDraw.text(cg, "Ø66 turned", x: labelW + (Double(sizes.count) + 1.5) * cell, y: 14, size: 12, bold: true, color: CatDraw.white(0.8))
        func cellAt(_ col: Int, _ row: Int, _ preset: CatPreset, pose: CatPose, D: Double, collar: CatCollarPaint?) {
            let x = labelW + Double(col) * cell, top = 28 + Double(row) * (cell + 8)
            cg.saveGState()
            cg.clip(CatDraw.roundRect(x + 2, top, cell - 4, cell, 10))
            cg.fill(CatDraw.roundRect(x, top, cell, cell, 0), CatDraw.black(1))
            var o = CatDrawOptions(); o.collar = collar
            CatRenderer.draw(cg, CatLook(preset: preset, pose: pose), cx: x + cell / 2, cy: top + cell * 0.5, D: D, o)
            cg.restoreGState()
        }
        for (ri, id) in a.cats.enumerated() {
            let preset = CatPresets.byID(id), first = ri * rowsPerCat
            for (si, style) in styles.enumerated() {
                let row = first + si, top = 28 + Double(row) * (cell + 8)
                CatDraw.text(cg, "\(preset.label) · \(style.0)", x: labelW / 2, y: top + cell / 2, size: 12, bold: true, color: CatDraw.white(0.85))
                let paint = CatCollarPaint(style: style.1, color: agentColors[0].hex, dpr: dpr)
                for (ci, d) in sizes.enumerated() { cellAt(ci, row, preset, pose: CatPose(), D: d, collar: paint) }
                cellAt(sizes.count, row, preset, pose: turned, D: 20, collar: paint)
                cellAt(sizes.count + 1, row, preset, pose: turned, D: 66, collar: paint)
            }
            for (si, style) in styles.dropFirst().enumerated() {
                let row = first + styles.count + si, top = 28 + Double(row) * (cell + 8)
                CatDraw.text(cg, "\(style.0), Ø28, six agents", x: labelW / 2, y: top + cell / 2, size: 11, bold: false, color: CatDraw.white(0.7))
                for (ci, c) in agentColors.enumerated() {
                    cellAt(ci, row, preset, pose: CatPose(), D: 28, collar: CatCollarPaint(style: style.1, color: c.hex, dpr: dpr))
                    CatDraw.text(cg, c.name, x: labelW + (Double(ci) + 0.5) * cell, y: top + cell - 5, size: 8, bold: false, color: CatDraw.white(0.5))
                }
            }
        }
```

Run: `d="${TMPDIR:-/tmp}/a-mac-5-7"; mkdir -p "$d" && bash scripts/render-cats.sh --collars --cats shrimpy,latte --scale 2 --out "$d/collars-2x.png" && bash scripts/render-cats.sh --collars --cats momo --scale 1 --out "$d/collars-1x.png"`
Expected: `wrote …/collars-2x.png` and `wrote …/collars-1x.png`.

Look at both. Expected: Band and tag, Band and Neckerchief show a coloured collar at every size from Ø12 up; at Ø12 and Ø16 the collar is a small coloured mark under the chin; the light colours (Cursor, VS Code) are outlined by the dark edge on Latte; a turned head turns the collar with it; the Off row is the plain cat.

- [ ] **Step 6: Commit**

```bash
git add NotchBuddy/Sources/App/CatLook.swift NotchBuddy/Sources/App/CatEffects.swift NotchBuddy/Sources/App/CatRenderer.swift tests/CatRendererTests.swift scripts/render-cats.swift
git commit -m "feat(cat): the collar is painted in the front pass from Ø12 up, with the contract's readability floors

drawCollar is the prototype's: a dark edge, a lighter tag with a highlight, a creased neckerchief. The renderer draws it after the
folded ears and before the whiskers, never recolours the coat, and the tests count its ink at every size. render-cats.sh gains --collars.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The collar reaches the cats, the greeting, the Debug panel and Settings (stage 6)

**Agent:** `nm-implementer`. The code is given in full; the tests and the picture of the Settings rows are what to read.

**Files:**
- Modify: `NotchBuddy/Sources/App/CatRules.swift` (`bigCatCollar`), `NotchBuddy/Sources/App/CatEngine.swift` (`CatConfig.collar`, `collarOverride`, `collarStyle(for:)`; `CatEngine.collarStyle`, `collarPaint(dpr:)`), `NotchBuddy/Sources/App/CatSettingsStore.swift` (`apply` and the two setters), `NotchBuddy/Sources/App/BotCanvasView.swift`, `NotchBuddy/Sources/App/CatGreetingRenderer.swift`, `NotchBuddy/Sources/App/CatDevModel.swift`, `NotchBuddy/Sources/App/CatDevPanel.swift`, `NotchBuddy/Sources/App/CatSettingsView.swift` (the two rows), `tests/CatRulesTests.swift`, `tests/CatSettingsStoreTests.swift`, `tests/CatSettingsTests.swift`, `tests/CatRendererTests.swift`, `tests/CatDevModelTests.swift`, `scripts/render-cat-settings.swift`, `scripts/render-cat-settings.sh`

**Interfaces:**
- Consumes: Task 7's `CatCollarPaint`, `CatDrawOptions.collar`; Task 2's store; `CatEngine.collar` (the agent colour, a hex string, which `BotCanvasView` and `MiniBotCanvasView` already set).
- Produces `CatRules.bigCatCollar(colour:state:)` (the colour of the agent driving the big cat's state, and none when it is idle, asleep or dizzy), `CatConfig.collar`, `CatConfig.collarOverride`, `CatConfig.collarStyle(for:)`, `CatEngine.collarStyle`, `CatEngine.collarPaint(dpr:) -> CatCollarPaint?` (nil when the style is off or there is no colour to wear), `CatSettingsStore.setCollar(_:)` and `setCollarOverride(_:for:)`; in the Debug panel `CatDevModel.collars`, `.agents`, `pick(collar:)`, `pick(agent:)` and `fur`.
- Settings gets the two rows the spec names, in the **Look** group: **Collar** (Band and tag, Band, Neckerchief or Off; default Off) and **This cat's collar** (Follow the collar, or a style for the chosen cat). Apply to every cat copies the collar along with the motion and the personality (Task 1's `applyingToAll` already does).

- [ ] **Step 1: Write the failing tests**

Five programs gain a section each: the rules (the big cat's collar), the store (the style from Settings and the colour from the agent, an override, `off` as an override, a kitten wearing its parent's, Apply to every cat), the settings pins (the canvases and the Settings rows), the renderer (the greeting's four session cats wear collars in the prototype's colours when a style is set, and none by default) and the Debug panel's model.

**Edit `tests/CatDevModelTests.swift`**, find this text (it occurs exactly once):

```swift
        m.pick(kitten: false)

        CT.section("the engines run: every pose stays finite after ten seconds")
        for e in [m.stage] + m.strip { for _ in 0..<(60 * 10) { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60) } }
```

and replace it with:

```swift
        m.pick(kitten: false)

        CT.section("the collar and the fur lines: the panel's own settings, never the app's")
        let c = model()
        CT.check("the panel starts with no collar and no fur", [c.collar, "\(c.fur)"], ["off", "false"])
        CT.check("four collar styles, Off among them, and the agents' colours", [CatDevModel.collars.map(\.id), CatDevModel.agents.map(\.hex)], [["tag", "band", "kerchief", "off"], ["#E07950", "#8AB4F8", "#2DD4BF", "#E879F9", "#C0C4CC", "#F5F6F8"]])
        c.pick(collar: "band")
        CT.checkTrue("a style reaches the stage cat and the eleven small ones, in the agent's colour", ([c.stage] + c.strip).allSatisfy { $0.collarPaint(dpr: 2)?.style == "band" && $0.collarPaint(dpr: 2)?.color == "#E07950" })
        c.pick(agent: 2)
        CT.checkTrue("another agent colours them all", ([c.stage] + c.strip).allSatisfy { $0.collarPaint(dpr: 2)?.color == "#2DD4BF" })
        c.pick(coat: "momo"); c.pick(kitten: true)
        CT.checkTrue("a new coat or a kitten keeps the collar", ([c.stage] + c.strip + [c.greeting]).allSatisfy { $0.collarPaint(dpr: 2)?.style == "band" && $0.collarPaint(dpr: 2)?.color == "#2DD4BF" })
        c.pick(collar: "scarf"); c.pick(agent: 99)
        CT.check("a style nobody knows is off, an agent nobody knows is the first", [c.collar, CatDevModel.agents[c.agent].hex], ["off", "#E07950"])
        CT.check("the app's own settings stay as they were", [CatConfig.shared.collar, "\(CatConfig.shared.furLines)", "\(CatConfig.shared.collarOverride.count)"], ["off", "false", "0"])

        CT.section("the engines run: every pose stays finite after ten seconds")
        for e in [m.stage] + m.strip { for _ in 0..<(60 * 10) { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60) } }
```

**Edit `tests/CatRendererTests.swift`**, find this text (it occurs exactly once):

```swift
        }

        CT.section("fur lines: off by default, and drawn only on a big full-detail cat that has fur")
        func fur(_ id: String, _ D: Double, on: Bool, full: Bool? = nil) -> [UInt8] {
```

and replace it with:

```swift
        }

        CT.section("the greeting's session cats wear collars in the prototype's colours when a style is set, and none by default")
        do {
            func stand(_ style: String?) -> [UInt8] {
                let cfg = CatConfig()
                if let style { cfg.collar = style }
                let e = CatEngine(CatPresets.byID("shrimpy"), now: { 0 }, rand: { 0.5 }, cfg: cfg, quiet: true)
                return render(640, 150) { CatGreetingRenderer.draw($0, t: CatGreeting.greetEnd + 0.3, leave: CatGreeting.GT.leave, engine: e, end: CatGreeting.Compact()) }
            }
            let plainRow = stand(nil)
            CT.checkTrue("off is what the greeting always drew", stand("off") == plainRow)
            for style in ["tag", "band", "kerchief"] { CT.checkTrue("\(style): the four cats in the grid have collars", stand(style) != plainRow) }
        }

        CT.section("fur lines: off by default, and drawn only on a big full-detail cat that has fur")
        func fur(_ id: String, _ D: Double, on: Bool, full: Bool? = nil) -> [UInt8] {
```

**Edit `tests/CatRulesTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.check("a missing value is off", CatRules.collarStyleOf(nil), "off")

        CT.section("which tool names mean searching")
        CT.checkJSON("the lists", got: CatRules.searchTools, want: tools["agents"]!)
```

and replace it with:

```swift
        CT.check("a missing value is off", CatRules.collarStyleOf(nil), "off")

        CT.section("the big cat wears the collar of the agent driving its state, and none when idle, asleep or dizzy")
        let agent = "#E07950"
        for st in CatState.allCases {
            let none = st == .idle || st == .sleeping || st == .dizzy
            CT.check("\(st.rawValue): \(none ? "no collar" : "the agent's colour")", CatRules.bigCatCollar(colour: agent, state: st), none ? nil : agent)
        }
        CT.check("with no agent colour there is nothing to wear", CatRules.bigCatCollar(colour: nil, state: .working), nil)

        CT.section("which tool names mean searching")
        CT.checkJSON("the lists", got: CatRules.searchTools, want: tools["agents"]!)
```

**Edit `tests/CatSettingsStoreTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.check("the character", cfg.character, "noodle")

        CT.section("what is written is only what changed, and only a cleaned value")
        let before = mem.writes.count
```

and replace it with:

```swift
        CT.check("the character", cfg.character, "noodle")

        CT.section("the collar: the style from Settings, the colour from the agent, nothing when either is missing")
        let wearer = engine("latte", cfg), kit = CatEngine(CatPresets.kitten(of: CatPresets.byID("latte")), now: { 0 }, rand: { 0.5 }, cfg: cfg, quiet: true)
        wearer.collar = "#E07950"; kit.collar = "#2DD4BF"
        CT.check("the default is off: no collar", wearer.collarPaint(dpr: 2) == nil, true)
        store.setCollar("band")
        CT.check("a global style, with the agent's colour and the pixel ratio", d(wearer.collarPaint(dpr: 2)!.style, wearer.collarPaint(dpr: 2)!.color, wearer.collarPaint(dpr: 1)!.dpr), d("band", "#E07950", 1.0))
        CT.check("a cat with no agent colour wears none (the big cat when idle)", { wearer.collar = nil; defer { wearer.collar = "#E07950" }; return wearer.collarPaint(dpr: 2) == nil }(), true)
        store.setCollarOverride("kerchief", for: "latte")
        CT.check("a cat's own style beats the global one, and the kitten wears its parent's", [wearer.collarPaint(dpr: 2)!.style, kit.collarPaint(dpr: 2)!.style, engine("momo", cfg).collarStyle], ["kerchief", "kerchief", "band"])
        store.setCollarOverride("off", for: "latte")
        CT.check("off is a style of its own: no collar on this cat while the global one is on", [wearer.collarPaint(dpr: 2) == nil, engine("momo", cfg).collarStyle == "band"], [true, true])
        store.setCollarOverride("follow", for: "latte")
        CT.check("follow gives the global style back", wearer.collarPaint(dpr: 2)!.style, "band")
        store.setCollar("scarf")
        CT.check("a style nobody knows is off", [store.settings.collar, cfg.collar], ["off", "off"])
        store.setCollar("tag"); store.setCollarOverride("band", for: "ginger"); store.applyToAll(from: "ginger")
        CT.check("Apply to every cat copies the collar too", d(store.settings.cats["noodle"]!.collar, store.settings.cats["latte"]!.collar, cfg.collarOverride.count), d("band", "band", 16))
        store.setCollar("off"); store.setCollarOverride("follow", for: "ginger"); store.applyToAll(from: "ginger")

        CT.section("what is written is only what changed, and only a cleaned value")
        let before = mem.writes.count
```

**Edit `tests/CatSettingsTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkTrue("Settings names the Cat section once", settingsView.components(separatedBy: "CatSettingsView").count == 2)

        CT.section("UserDefaults keys: cat.character, cat.motionStyle, cat.furLines, cat.collar, cat.motion.<id>, cat.collar.<id>, cat.personality.<id>")
        let mem = MemoryBacking()
```

and replace it with:

```swift
        CT.checkTrue("Settings names the Cat section once", settingsView.components(separatedBy: "CatSettingsView").count == 2)

        CT.section("the collar in the app (source pins): the big cat, the small cats, the greeting's cats and the Settings rows")
        let canvases = source("BotCanvasView.swift"), greetingSource = source("CatGreetingRenderer.swift")
        CT.checkTrue("the big cat's collar is the focus task's colour, none when idle", canvases.contains("engine.collar = CatRules.bigCatCollar(colour:") && canvases.contains("state.focusTask?.color"))
        CT.checkTrue("the big and the small cats hand the renderer their collar", canvases.components(separatedBy: "options.collar = engine.collarPaint(dpr:").count == 3)
        CT.checkTrue("the greeting's stand-in cats wear collars from the prototype's colours when a style is set", greetingSource.contains("miniColors") && greetingSource.contains("e.collarStyle"))
        CT.checkTrue("Settings has the two collar rows and no more than the contract's four styles", view.contains("This cat's collar") && view.contains("store.setCollar(") && view.contains("store.setCollarOverride(") && view.contains("Band and tag") && view.contains("Neckerchief"))

        CT.section("UserDefaults keys: cat.character, cat.motionStyle, cat.furLines, cat.collar, cat.motion.<id>, cat.collar.<id>, cat.personality.<id>")
        let mem = MemoryBacking()
```

- [ ] **Step 2: Run them to see them fail**

Run: `for t in rules settings-store; do bash scripts/test-cat-$t.sh 2>&1 | grep -E "error" | head -2; done`
Expected: FAIL: `error: type 'CatRules' has no member 'bigCatCollar'` and `error: value of type 'CatEngine' has no member 'collarPaint'`.

- [ ] **Step 3: Write the wiring**

What each piece does. **The big cat** wears the colour of the agent driving its state, which is the focus task's `color` for every pill (an integration, an agent or a session), and none when idle, asleep or dizzy: those are the cat's own states, not an agent's (plan decision, the same in the Windows plan); the Claude plan detail keeps the plan gauge's colour. **A small cat** wears its own pill's colour all the time (`MiniBotCanvasView` already set it). **The style** is the chosen cat's own, else the global one, resolved by `CatConfig` from the store; a kitten wears its parent's. **The greeting's four session cats** are decorative stand-ins; the prototype draws them with collars in the Gemini CLI, Codex and Claude Code colours, so they do too when a style is set (with Off, the greeting is byte for byte what it was, and the existing test that its last frame is the real compact grid still holds). **The device pixel ratio** is the canvas's `displayScale`, which the readability floors need.

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**, find this text (it occurs exactly once):

```swift
                engine.lookX = look.x
                engine.lookY = look.y
                // The agent colour, kept for the collar of stage 6 (nothing draws it yet): integration pills have a fixed brand colour.
                #if !APPSTORE
                if state.showingPlanDetail {
                    engine.collar = ClaudePlanGauge.color(for: state.claudePlanUsage.flatMap { ClaudePlanGauge.dominantPct($0) })
                } else {
                    engine.collar = (state.focusTask?.isIntegration == true) ? state.focusTask!.color : nil
                }
                #else
                engine.collar = (state.focusTask?.isIntegration == true) ? state.focusTask!.color : nil
                #endif

                // Compute shouldDance per-frame (no observer lag)
```

and replace it with:

```swift
                engine.lookX = look.x
                engine.lookY = look.y
                // The agent colour the collar wears (Settings → Cat → Collar picks the style): the colour of the agent driving the cat's state, and
                // none when it is idle. The Claude plan detail shows the plan gauge's colour.
                #if !APPSTORE
                let agentColour: String? = state.showingPlanDetail
                    ? ClaudePlanGauge.color(for: state.claudePlanUsage.flatMap { ClaudePlanGauge.dominantPct($0) })
                    : state.focusTask?.color
                #else
                let agentColour: String? = state.focusTask?.color
                #endif
                engine.collar = CatRules.bigCatCollar(colour: agentColour, state: CatState(rawValue: state.effectiveState.rawValue) ?? .idle)

                // Compute shouldDance per-frame (no observer lag)
```

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**, find this text (it occurs exactly once):

```swift
                var options = CatDrawOptions()
                options.fur = engine.cfg.furLines                // Settings → Cat → Fur lines
                if state.mode == .compact {
                    options.badgeSide = -1                       // never under the camera housing
```

and replace it with:

```swift
                var options = CatDrawOptions()
                options.fur = engine.cfg.furLines                // Settings → Cat → Fur lines
                options.collar = engine.collarPaint(dpr: Double(context.environment.displayScale))   // Settings → Cat → Collar
                if state.mode == .compact {
                    options.badgeSide = -1                       // never under the camera housing
```

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**, find this text (it occurs exactly once):

```swift
                engine.update(dt: dt)
                let D = Double(size.width) * 0.6
                let L = drawCat(context, engine, cx: Double(size.width) / 2, cy: Double(size.height) / 2, D: D, CatDrawOptions(badge: false))
                engine.base = L.base
                engine.mouthPoint = L.mouth
```

and replace it with:

```swift
                engine.update(dt: dt)
                let D = Double(size.width) * 0.6
                var options = CatDrawOptions(badge: false)
                options.collar = engine.collarPaint(dpr: Double(context.environment.displayScale))   // the pill's agent colour, in Settings → Cat → Collar's style
                let L = drawCat(context, engine, cx: Double(size.width) / 2, cy: Double(size.height) / 2, D: D, options)
                engine.base = L.base
                engine.mouthPoint = L.mouth
```

**Edit `NotchBuddy/Sources/App/CatDevModel.swift`**, find this text (it occurs exactly once):

```swift
    static let emotes = ["love", "happy", "surprised", "proud", "wink", "yawn", "annoyed", "hello", "zoomies", "hairball"]

    /// The panel's own settings. The app's cats (`CatConfig.shared`) are never touched.
    let cfg: CatConfig
```

and replace it with:

```swift
    static let emotes = ["love", "happy", "surprised", "proud", "wink", "yawn", "annoyed", "hello", "zoomies", "hairball"]

    /// The collar styles the panel offers (the contract's order, Off last), and the agent colours a collar can wear (the pill catalogue's, as the
    /// prototype's collar panel has them).
    static let collars: [(id: String, label: String)] = [("tag", "Band and tag"), ("band", "Band"), ("kerchief", "Neckerchief"), ("off", "Off")]
    static let agents: [(name: String, hex: String)] = [("Claude Code", "#E07950"), ("Gemini CLI", "#8AB4F8"), ("Codex", "#2DD4BF"),
                                                         ("Antigravity", "#E879F9"), ("Cursor", "#C0C4CC"), ("VS Code", "#F5F6F8")]

    /// The panel's own settings. The app's cats (`CatConfig.shared`) are never touched.
    let cfg: CatConfig
```

**Edit `NotchBuddy/Sources/App/CatDevModel.swift`**, find this text (it occurs exactly once):

```swift
    @Published private(set) var personality = "balanced"
    @Published var tint = true
    /// What the stage cat just did, newest last (the last eight): "emote:love", "blink", "hairball"... They are the engine's own notes.
    /// Not published: the engine writes it while a frame is drawn (SwiftUI does not allow a change to be published from there), so the panel reads it on a timer.
```

and replace it with:

```swift
    @Published private(set) var personality = "balanced"
    @Published var tint = true
    /// The collar every cat in the panel wears, and which agent's colour it is (an index into `agents`). Off is the default, like the app.
    @Published private(set) var collar = "off"
    @Published private(set) var agent = 0
    /// Fur lines on the cats in the panel (its own switch: the app's is Settings').
    @Published var fur = false { didSet { cfg.furLines = fur } }
    /// What the stage cat just did, newest last (the last eight): "emote:love", "blink", "hairball"... They are the engine's own notes.
    /// Not published: the engine writes it while a frame is drawn (SwiftUI does not allow a change to be published from there), so the panel reads it on a timer.
```

**Edit `NotchBuddy/Sources/App/CatDevModel.swift`**, find this text (it occurs exactly once):

```swift
    /// it (a kitten wears its parent's). The engines read it as they run, so nothing is rebuilt.
    func pick(personality key: String) { personality = Personality.named(key).preset; cfg.pers = [coat: Personality.named(personality)] }
    /// A file thrown at the stage cat. Not published: `advance()` changes it while a frame is drawn.
    struct Flight: Equatable { var ext: String; var refused: Bool; var dropAt: Double }
```

and replace it with:

```swift
    /// it (a kitten wears its parent's). The engines read it as they run, so nothing is rebuilt.
    func pick(personality key: String) { personality = Personality.named(key).preset; cfg.pers = [coat: Personality.named(personality)] }
    /// A collar style; one that is not a style is off, like a stored one. Every engine reads it from the panel's own config on its next frame.
    func pick(collar style: String) { collar = CatRules.collarStyleOf(style); cfg.collar = collar }
    /// An agent colour for the collars; one the panel does not offer is the first.
    func pick(agent i: Int) {
        agent = Self.agents.indices.contains(i) ? i : 0
        for e in [stage, greeting] + strip { e.collar = Self.agents[agent].hex }
    }
    /// A file thrown at the stage cat. Not published: `advance()` changes it while a frame is drawn.
    struct Flight: Equatable { var ext: String; var refused: Bool; var dropAt: Double }
```

**Edit `NotchBuddy/Sources/App/CatDevModel.swift`**, find this text (it occurs exactly once):

```swift

    private func make(_ p: CatPreset, state: CatState) -> CatEngine {
        CatEngine(p, now: now, rand: rand, cfg: cfg, quiet: false, state: state)
    }
}
```

and replace it with:

```swift

    private func make(_ p: CatPreset, state: CatState) -> CatEngine {
        let e = CatEngine(p, now: now, rand: rand, cfg: cfg, quiet: false, state: state)
        e.collar = Self.agents[agent].hex
        return e
    }
}
```

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`**, find this text (it occurs exactly once):

```swift
                    ForEach(Personality.presets, id: \.key) { Text($0.label).tag($0.key) }
                }
                Toggle("Kitten", isOn: Binding(get: { model.kitten }, set: { model.pick(kitten: $0) }))
                Toggle("State tint on the lower head", isOn: $model.tint)
            }
```

and replace it with:

```swift
                    ForEach(Personality.presets, id: \.key) { Text($0.label).tag($0.key) }
                }
                Picker("Collar", selection: Binding(get: { model.collar }, set: { model.pick(collar: $0) })) {
                    ForEach(CatDevModel.collars, id: \.id) { Text($0.label).tag($0.id) }
                }
                .pickerStyle(.segmented)
                Picker("Agent colour", selection: Binding(get: { model.agent }, set: { model.pick(agent: $0) })) {
                    ForEach(Array(CatDevModel.agents.enumerated()), id: \.offset) { Text($0.element.name).tag($0.offset) }
                }
                Toggle("Kitten", isOn: Binding(get: { model.kitten }, set: { model.pick(kitten: $0) }))
                Toggle("Fur lines (from a head width of Ø60)", isOn: $model.fur)
                Toggle("State tint on the lower head", isOn: $model.tint)
            }
```

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`**, find this text (it occurs exactly once):

```swift
        GroupBox("Every coat, at every size") {
            ScrollView(.horizontal) {
                CatDevLadder(pointer: pointer, tint: model.tint)
            }
            .padding(8)
```

and replace it with:

```swift
        GroupBox("Every coat, at every size") {
            ScrollView(.horizontal) {
                CatDevLadder(pointer: pointer, tint: model.tint, collar: model.collar, agent: CatDevModel.agents[model.agent].hex)
            }
            .padding(8)
```

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`**, find this text (it occurs exactly once):

```swift
                    CatFrameReadout.shared.measure {
                        context.withCGContext { cg in
                            let L = CatRenderer.draw(cg, engine.look(), cx: cx, cy: cy, D: D, CatDrawOptions(tint: tint, glow: true))
                            engine.base = L.base
                            engine.mouthPoint = L.mouth
```

and replace it with:

```swift
                    CatFrameReadout.shared.measure {
                        context.withCGContext { cg in
                            var options = CatDrawOptions(tint: tint, glow: true)
                            options.fur = engine.cfg.furLines
                            options.collar = engine.collarPaint(dpr: Double(context.environment.displayScale))
                            let L = CatRenderer.draw(cg, engine.look(), cx: cx, cy: cy, D: D, options)
                            engine.base = L.base
                            engine.mouthPoint = L.mouth
```

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`**, find this text (it occurs exactly once):

```swift
    let pointer: CGPoint?
    let tint: Bool

    private static let cells: [(d: Double, label: String, kitten: Bool)] = [
```

and replace it with:

```swift
    let pointer: CGPoint?
    let tint: Bool
    let collar: String
    let agent: String

    private static let cells: [(d: Double, label: String, kitten: Bool)] = [
```

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`**, find this text (it occurs exactly once):

```swift
            let origin = geo.frame(in: .named(CatDevView.space)).origin
            Canvas { context, _ in
                context.withCGContext { cg in
                    for (ri, id) in CatPresets.ids.enumerated() {
```

and replace it with:

```swift
            let origin = geo.frame(in: .named(CatDevView.space)).origin
            Canvas { context, _ in
                let paint = collar == "off" ? nil : CatCollarPaint(style: collar, color: agent, dpr: Double(context.environment.displayScale))
                context.withCGContext { cg in
                    for (ri, id) in CatPresets.ids.enumerated() {
```

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`**, find this text (it occurs exactly once):

```swift
                                pose.yaw = g.x * 0.62; pose.pitch = g.y * 0.5
                            }
                            CatRenderer.draw(cg, CatLook(preset: c.kitten ? CatPresets.kitten(of: base) : base, pose: pose), cx: cx, cy: cy, D: c.d, CatDrawOptions(tint: tint))
                            CatDraw.text(cg, c.label, x: cx, y: top + Self.rowH - 10, size: 10, bold: false, color: CatDraw.white(0.55))
                            x += w
```

and replace it with:

```swift
                                pose.yaw = g.x * 0.62; pose.pitch = g.y * 0.5
                            }
                            var options = CatDrawOptions(tint: tint)
                            options.collar = paint
                            CatRenderer.draw(cg, CatLook(preset: c.kitten ? CatPresets.kitten(of: base) : base, pose: pose), cx: cx, cy: cy, D: c.d, options)
                            CatDraw.text(cg, c.label, x: cx, y: top + Self.rowH - 10, size: 10, bold: false, color: CatDraw.white(0.55))
                            x += w
```

**Edit `NotchBuddy/Sources/App/CatEngine.swift`**, find this text (it occurs exactly once):

```swift
    /// Settings → Cat → Fur lines: the optional fur strands on a big cat.
    var furLines = false

    init(motion: String = "playful", override: [String: String] = [:], pers: [String: CatPersonality] = [:], zoomAfter: Double = CatRules.zoomAfterMs) {
```

and replace it with:

```swift
    /// Settings → Cat → Fur lines: the optional fur strands on a big cat.
    var furLines = false
    /// Settings → Cat → Collar: the style every cat wears ("tag", "band", "kerchief" or "off", the default), and the cats that have a style of their
    /// own (by cat ID; a cat that follows has no entry).
    var collar = "off"
    var collarOverride: [String: String] = [:]

    /// The collar style a cat wears: its own, else the global one. Anything that is not one of the four styles is "off".
    func collarStyle(for id: String) -> String {
        if let own = collarOverride[id], CatRules.collarStyles.contains(own) { return own }
        return CatRules.collarStyleOf(collar)
    }

    init(motion: String = "playful", override: [String: String] = [:], pers: [String: CatPersonality] = [:], zoomAfter: Double = CatRules.zoomAfterMs) {
```

**Edit `NotchBuddy/Sources/App/CatEngine.swift`**, find this text (it occurs exactly once):

```swift
    /// Seconds on the engine's clock at the end of the last update, so a view can work out `dt` with `CatEngine.frameDelta`.
    var lastTime: Double
    /// The colour of the agent the cat belongs to, a hex string. Unused in stages 1 to 4: the collar is optional, Off by default, and arrives with
    /// its Settings rows in stage 6 (small cats then wear their agent's collar, the big cat the collar of the agent driving its state).
    var collar: String?

```

and replace it with:

```swift
    /// Seconds on the engine's clock at the end of the last update, so a view can work out `dt` with `CatEngine.frameDelta`.
    var lastTime: Double
    /// The colour of the agent the cat belongs to, a hex string: small cats wear their agent's, the big cat the colour of the agent driving its state
    /// and none when idle (`CatRules.bigCatCollar`). It is worn as a collar in the style Settings picks (`collarStyle`); nil: nothing to wear.
    var collar: String?

```

**Edit `NotchBuddy/Sources/App/CatEngine.swift`**, find this text (it occurs exactly once):

```swift
        let next = CatPresets.byID(id)
        if next.name != p.name { p = next }
    }

```

and replace it with:

```swift
        let next = CatPresets.byID(id)
        if next.name != p.name { p = next }
    }

    /// The collar style this cat wears (a kitten wears its parent's).
    var collarStyle: String { cfg.collarStyle(for: p.base ?? p.name) }

    /// The collar to hand to the renderer: this cat's style with its agent colour, or nil when the style is off or there is no colour to wear.
    /// `dpr` is the device pixel ratio the readability floors are in.
    func collarPaint(dpr: Double) -> CatCollarPaint? {
        guard let color = collar, collarStyle != "off" else { return nil }
        return CatCollarPaint(style: collarStyle, color: color, dpr: dpr)
    }

```

**Edit `NotchBuddy/Sources/App/CatGreetingRenderer.swift`**, find this text (it occurs exactly once):

```swift
        CatRenderer.draw(cg, look, cx: X, cy: Y, D: D, o)
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
            cg.restoreGState()
        }
```

and replace it with:

```swift
        CatRenderer.draw(cg, look, cx: X, cy: Y, D: D, o)
        let slots = Greeting.miniSlots(minis: P.minis, glide: Greeting.miniGlide(t, leave: leave), width: end.width, height: end.height)
        drawMinis(cg, slots, preset: p, scale: end.miniScale, collarStyle: e.collarStyle)
    }

    /// The agent colours of the four session cats, in the order of the grid's cells (top left, top right, bottom left, bottom right): the prototype's, the
    /// Gemini CLI, the Codex, a Claude Code kitten and Claude Code. They wear them as collars when Settings picks a style.
    static let miniColors = ["#8AB4F8", "#2DD4BF", "#E07950", "#E07950"]

    /// The session cats: a row of three pops in as the island closes, glides into the compact island's 2x2 grid, and a fourth pops in (the real grid
    /// takes over when the last beat is over). Each is drawn the way the real grid draws one: a cat of head width 12 pt scaled about its own centre
    /// by the strip's `miniScale`. `slot.d` already holds the pop and that scale, so the head width drawn is `slot.d / scale`.
    private static func drawMinis(_ cg: CGContext, _ slots: [Greeting.Mini], preset: CatPreset, scale k: Double, collarStyle: String) {
        guard k > 0 else { return }
        for (i, s) in slots.enumerated() where s.d >= Greeting.miniMinD {
            cg.saveGState()
            cg.translateBy(x: s.x, y: s.y)
            cg.scaleBy(x: k, y: k)
            var pose = CatPose(); pose.tint = 0.6
            var options = CatDrawOptions(badge: false)
            if collarStyle != "off" { options.collar = CatCollarPaint(style: collarStyle, color: miniColors[i % miniColors.count]) }
            CatRenderer.draw(cg, CatLook(preset: preset, pose: pose, color: [127, 180, 234]), cx: 0, cy: 0, D: s.d / k, options)
            cg.restoreGState()
        }
```

**Edit `NotchBuddy/Sources/App/CatRules.swift`**, find this text (it occurs exactly once):

```swift
    static func collarStyleOf(_ v: Any?) -> String { (v as? String).flatMap { collarStyles.contains($0) ? $0 : nil } ?? "off" }

    /// Tool names that mean "searching" (exact, case-sensitive match on the tool name the hook relay delivers).
    static let searchTools: [String: [String]] = [
```

and replace it with:

```swift
    static func collarStyleOf(_ v: Any?) -> String { (v as? String).flatMap { collarStyles.contains($0) ? $0 : nil } ?? "off" }

    /// The colour the big cat wears as its collar: the colour of the agent driving its state, and none when it is idle, asleep or dizzy (those are
    /// the cat's own states, not an agent's) or has no agent. The small cats wear their own agent's colour all the time.
    static func bigCatCollar(colour: String?, state: CatState) -> String? { state == .idle || state == .sleeping || state == .dizzy ? nil : colour }

    /// Tool names that mean "searching" (exact, case-sensitive match on the tool name the hook relay delivers).
    static let searchTools: [String: [String]] = [
```

**Edit `NotchBuddy/Sources/App/CatSettingsStore.swift`**, find this text (it occurs exactly once):

```swift
        pers = e.pers
        furLines = s.furLines
    }
}
```

and replace it with:

```swift
        pers = e.pers
        furLines = s.furLines
        collar = s.collar
        collarOverride = s.cats.compactMap { $0.value.collar == CatSettings.follow ? nil : ($0.key, $0.value.collar) }.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }
}
```

**Edit `NotchBuddy/Sources/App/CatSettingsStore.swift`**, find this text (it occurs exactly once):

```swift
    }
    func setFurLines(_ on: Bool) { update { $0 = $0.withFurLines(on) } }
    /// "Apply to every cat": the motion, collar and personality of cat `id` go to all 16.
    func applyToAll(from id: String) { update { $0 = $0.applyingToAll(from: id) } }
```

and replace it with:

```swift
    }
    func setFurLines(_ on: Bool) { update { $0 = $0.withFurLines(on) } }
    /// The collar for every cat: "tag", "band", "kerchief" or "off" (anything else is off).
    func setCollar(_ style: String) { update { $0 = $0.withCollar(style) } }
    /// "follow" or a style for one cat ("off" is a style: this cat wears no collar while the global one is on).
    func setCollarOverride(_ word: String, for id: String) { update { $0 = $0.withCatCollar(word, for: id) } }
    /// "Apply to every cat": the motion, collar and personality of cat `id` go to all 16.
    func applyToAll(from id: String) { update { $0 = $0.applyingToAll(from: id) } }
```

**Edit `NotchBuddy/Sources/App/CatSettingsView.swift`**, find this text (it occurs exactly once):

```swift
                HStack(spacing: 14) {
                    // A head of Ø60 and more is where fur lines show, so the chosen cat is drawn big (the 16 below are Ø36).
                    CatPreviewView(id: id, head: 84, active: active, config: store.config)
                        .frame(width: 130, height: 118)
                    VStack(alignment: .leading, spacing: 4) {
```

and replace it with:

```swift
                HStack(spacing: 14) {
                    // A head of Ø60 and more is where fur lines show, so the chosen cat is drawn big (the 16 below are Ø36).
                    CatPreviewView(id: id, head: 84, active: active, config: store.config, agentColor: Self.sampleAgent)
                        .frame(width: 130, height: 118)
                    VStack(alignment: .leading, spacing: 4) {
```

**Edit `NotchBuddy/Sources/App/CatSettingsView.swift`**, find this text (it occurs exactly once):

```swift
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    CatPreviewView(id: id, head: 62, active: active, config: store.config)
                        .frame(width: 96, height: 84)
                    VStack(alignment: .leading, spacing: 6) {
```

and replace it with:

```swift
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    CatPreviewView(id: id, head: 62, active: active, config: store.config, agentColor: Self.sampleAgent)
                        .frame(width: 96, height: 84)
                    VStack(alignment: .leading, spacing: 6) {
```

**Edit `NotchBuddy/Sources/App/CatSettingsView.swift`**, find this text (it occurs exactly once):

```swift
    // MARK: Look

    private var lookGroup: some View {
        GroupBox("Look") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Fur lines", isOn: Binding(get: { store.settings.furLines }, set: { store.setFurLines($0) }))
                Text("Fine fur strands on the big cat. Off keeps the flat colour.")
```

and replace it with:

```swift
    // MARK: Look

    private static let collarStyles: [(id: String, label: String)] = [("tag", "Band and tag"), ("band", "Band"), ("kerchief", "Neckerchief"), ("off", "Off")]
    /// The colour the previews' collar wears: Claude Code's, one of the agents' colours.
    private static let sampleAgent = "#E07950"

    private var lookGroup: some View {
        GroupBox("Look") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Collar").frame(width: 130, alignment: .leading)
                    Picker("", selection: Binding(get: { store.settings.collar }, set: { store.setCollar($0) })) {
                        ForEach(Self.collarStyles, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                Text("The colour of an agent, worn as a collar. Small cats wear their agent's; the big cat wears the agent driving its state, and none when idle.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Text("This cat's collar").frame(width: 130, alignment: .leading)
                    Picker("", selection: Binding(get: { entry.collar }, set: { store.setCollarOverride($0, for: id) })) {
                        Text("Follow the collar").tag(CatSettings.follow)
                        ForEach(Self.collarStyles, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    Text(label).font(.system(size: 11)).foregroundColor(.secondary)
                }
                Divider()
                Toggle("Fur lines", isOn: Binding(get: { store.settings.furLines }, set: { store.setFurLines($0) }))
                Text("Fine fur strands on the big cat. Off keeps the flat colour.")
```

**Edit `NotchBuddy/Sources/App/CatSettingsView.swift`**, find this text (it occurs exactly once):

```swift
    let active: Bool
    let config: CatConfig
    @StateObject private var engine: CatEngine

    init(id: String, head: Double, active: Bool, config: CatConfig) {
        self.id = id; self.head = head; self.active = active; self.config = config
        _engine = StateObject(wrappedValue: CatEngine(CatPresets.byID(id), now: { CACurrentMediaTime() * 1000 }, cfg: config))
    }
```

and replace it with:

```swift
    let active: Bool
    let config: CatConfig
    /// The agent colour the preview's collar wears (in the style Settings picks); nil: no collar.
    let agentColor: String?
    @StateObject private var engine: CatEngine

    init(id: String, head: Double, active: Bool, config: CatConfig, agentColor: String? = nil) {
        self.id = id; self.head = head; self.active = active; self.config = config; self.agentColor = agentColor
        _engine = StateObject(wrappedValue: CatEngine(CatPresets.byID(id), now: { CACurrentMediaTime() * 1000 }, cfg: config))
    }
```

**Edit `NotchBuddy/Sources/App/CatSettingsView.swift`**, find this text (it occurs exactly once):

```swift
                var options = CatDrawOptions(badge: false)
                options.fur = config.furLines
                context.withCGContext { cg in
                    CatRenderer.draw(cg, engine.look(), cx: Double(size.width) / 2, cy: Double(size.height) / 2 + head * 0.08, D: head, options)
```

and replace it with:

```swift
                var options = CatDrawOptions(badge: false)
                options.fur = config.furLines
                engine.collar = agentColor
                options.collar = engine.collarPaint(dpr: Double(context.environment.displayScale))
                context.withCGContext { cg in
                    CatRenderer.draw(cg, engine.look(), cx: Double(size.width) / 2, cy: Double(size.height) / 2 + head * 0.08, D: head, options)
```

- [ ] **Step 4: Run the tests**

Run: `for t in rules settings-store settings devpanel renderer; do printf '%-16s' $t; bash scripts/test-cat-$t.sh 2>&1 | tail -1; done`
Expected: five lines ending `All tests passed.`

- [ ] **Step 5: The render script can show a collar**

`render-cat-settings.sh` gains `--collar <style>`, so the section can be drawn with the global collar on.

**Edit `scripts/render-cat-settings.sh`**, find this text (it occurs exactly once):

```bash
#!/usr/bin/env bash
# Draws Settings → Cat into a PNG without launching NotchMeow (see scripts/render-cat-settings.swift).
#   bash scripts/render-cat-settings.sh --out settings.png [--height 1500] [--width 520] [--character momo] [--preset chill] [--fur]
set -euo pipefail
cd "$(dirname "$0")/.."
```

and replace it with:

```bash
#!/usr/bin/env bash
# Draws Settings → Cat into a PNG without launching NotchMeow (see scripts/render-cat-settings.swift).
#   bash scripts/render-cat-settings.sh --out settings.png [--height 1500] [--width 520] [--character momo] [--preset chill] [--fur] [--collar band]
set -euo pipefail
cd "$(dirname "$0")/.."
```

**Edit `scripts/render-cat-settings.swift`**, find this text (it occurs exactly once):

```swift
// group boxes, buttons) may come out blank in this offscreen bitmap; the cats and the layout do not.
// Run it through scripts/render-cat-settings.sh:
//   bash scripts/render-cat-settings.sh [--out settings.png] [--height 1500] [--width 520] [--character momo] [--preset chill] [--fur]

final class MemoryBacking: CatSettingsBacking {
```

and replace it with:

```swift
// group boxes, buttons) may come out blank in this offscreen bitmap; the cats and the layout do not.
// Run it through scripts/render-cat-settings.sh:
//   bash scripts/render-cat-settings.sh [--out settings.png] [--height 1500] [--width 520] [--character momo] [--preset chill] [--fur] [--collar band]

final class MemoryBacking: CatSettingsBacking {
```

**Edit `scripts/render-cat-settings.swift`**, find this text (it occurs exactly once):

```swift
struct RenderCatSettings {
    @MainActor static func main() {
        var out = "cat-settings.png", height = 1500.0, width = 520.0, character = "momo", preset = "chill", fur = false
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
```

and replace it with:

```swift
struct RenderCatSettings {
    @MainActor static func main() {
        var out = "cat-settings.png", height = 1500.0, width = 520.0, character = "momo", preset = "chill", fur = false, collar = "off"
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
```

**Edit `scripts/render-cat-settings.swift`**, find this text (it occurs exactly once):

```swift
            case "--preset": preset = it.next() ?? preset
            case "--fur": fur = true
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

and replace it with:

```swift
            case "--preset": preset = it.next() ?? preset
            case "--fur": fur = true
            case "--collar": collar = it.next() ?? collar
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

**Edit `scripts/render-cat-settings.swift`**, find this text (it occurs exactly once):

```swift
        store.setPreset(preset, for: character)
        store.setFurLines(fur)
        let host = NSHostingView(rootView: ScrollView { CatSettingsView(store: store, alwaysActive: true).padding(20) }.frame(width: width, height: height))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
```

and replace it with:

```swift
        store.setPreset(preset, for: character)
        store.setFurLines(fur)
        store.setCollar(collar)
        let host = NSHostingView(rootView: ScrollView { CatSettingsView(store: store, alwaysActive: true).padding(20) }.frame(width: width, height: height))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
```

Run: `d="${TMPDIR:-/tmp}/a-mac-5-7"; mkdir -p "$d" && bash scripts/render-cat-settings.sh --out "$d/settings-collar.png" --height 1400 --character latte --collar band && bash scripts/render-cat-panel.sh --out "$d/panel.png" --height 1500`
Expected: `wrote …/settings-collar.png` and `wrote …/panel.png`.

Look at both. Expected: the Look group has **Collar** (Band) and **This cat's collar** (Follow the collar), and Latte's big preview wears an orange band under the chin; the Debug panel's Cat group has a Collar control (Band and tag, Band, Neckerchief, Off), an Agent colour menu and a Fur lines switch.

- [ ] **Step 6: Build**

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: the last lines end with `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add NotchBuddy/Sources/App/CatRules.swift NotchBuddy/Sources/App/CatEngine.swift NotchBuddy/Sources/App/CatSettingsStore.swift NotchBuddy/Sources/App/BotCanvasView.swift NotchBuddy/Sources/App/CatGreetingRenderer.swift NotchBuddy/Sources/App/CatDevModel.swift NotchBuddy/Sources/App/CatDevPanel.swift NotchBuddy/Sources/App/CatSettingsView.swift tests/CatRulesTests.swift tests/CatSettingsStoreTests.swift tests/CatSettingsTests.swift tests/CatRendererTests.swift tests/CatDevModelTests.swift scripts/render-cat-settings.swift scripts/render-cat-settings.sh
git commit -m "feat(cat): the agent colour is worn as a collar in the style Settings picks, default Off

Small cats wear their pill's colour; the big cat wears the colour of the agent driving its state and none when idle, asleep or
dizzy. Settings gets Collar and This cat's collar; Apply to every cat copies the collar. The greeting's session cats and the
Debug panel wear it too.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 9: Searching (stage 6)

**Agent:** `nm-implementer-light`. The edit is given in full; the pins prove it.

**Files:**
- Modify: `NotchBuddy/Sources/App/HookServer.swift` (`processEvent`: `PreToolUse` and `PostToolUse`), `NotchBuddy/Sources/App/CatEngine+App.swift` (`BotState.init(_ s: CatState)`), `tests/CatRulesTests.swift`

**Interfaces:**
- Consumes: `CatRules.toolState(_:)` (stage 2: `search-tools.json`'s three lists, replayed by `scripts/test-cat-rules.sh`).
- Produces: a `PreToolUse` or `PostToolUse` event whose tool is a search tool sets the agent's task to `.searching`; any other tool, `.working`. `PostToolUseFailure` stays `.working`. `BotState(_ s: CatState)`.

- [ ] **Step 1: Write the failing pins**

No test program can run the hook server, so these are source pins in the rules program: `PreToolUse` and `PostToolUse` decide with `CatRules.toolState`, a failed tool is plain work, and nothing else in the hook server decides between searching and working.

**Edit `tests/CatRulesTests.swift`**, find this text (it occurs exactly once):

```swift
        }
        CT.check("a missing tool name is plain work", CatRules.toolState(nil), CatState.working)
        CT.finish()
    }
```

and replace it with:

```swift
        }
        CT.check("a missing tool name is plain work", CatRules.toolState(nil), CatState.working)

        CT.section("searching in the app (source pins: no test program can run the hook server)")
        let hook = (try? String(contentsOfFile: "NotchBuddy/Sources/App/HookServer.swift", encoding: .utf8)) ?? ""
        /// The text of one `case "…":` of `processEvent`, up to the next case.
        func eventCase(_ name: String) -> String {
            guard let start = hook.range(of: "        case \"\(name)\":") else { return "" }
            let rest = hook[start.upperBound...]
            return String(rest[..<(rest.range(of: "\n        case \"")?.lowerBound ?? rest.endIndex)])
        }
        CT.checkTrue("PreToolUse puts a search tool in the searching state and any other tool in working", eventCase("PreToolUse").contains("state.updateTask(id: agentId, state: BotState(CatRules.toolState(tool)))"))
        CT.checkTrue("PostToolUse does the same with the tool that finished, so the next tool of any other kind puts the cat back to working", eventCase("PostToolUse").contains("BotState(CatRules.toolState(diffTool))"))
        CT.checkTrue("a failed tool is plain work", eventCase("PostToolUseFailure").contains("state: .working") && !eventCase("PostToolUseFailure").contains("toolState"))
        CT.checkTrue("nothing else in the hook server decides between searching and working", hook.components(separatedBy: "CatRules.toolState").count == 3)
        CT.finish()
    }
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-rules.sh 2>&1 | grep -E "✗|failed"`
Expected: FAIL: `✗ PreToolUse puts a search tool in the searching state and any other tool in working`, `✗ PostToolUse does the same with the tool that finished, so the next tool of any other kind puts the cat back to working`, `✗ nothing else in the hook server decides between searching and working` and `3 test(s) failed.`

- [ ] **Step 3: Make the change**

`PostToolUse` now reads the tool name before it sets the state; a search tool keeps the cat searching until the next tool of any other kind sets it back to working. A tool whose name is not in the lists (Antigravity's are not known: the owner's manual check from stage 1) is plain work, so the cost of a missing name is a cat that stays in "working".

**Edit `NotchBuddy/Sources/App/CatEngine+App.swift`**, find this text (it occurs exactly once):

```swift
// The app's way into the cat engine: the real clock, the app's own state and emote types, and the sounds. Nothing here is in the
// contract, and the test programs do not compile this file.

extension CatEngine {
```

and replace it with:

```swift
// The app's way into the cat engine: the real clock, the app's own state and emote types, and the sounds. Nothing here is in the
// contract, and the test programs do not compile this file.

extension BotState {
    /// The app's state for a cat state (the two enums have the same cases, with the same raw values).
    init(_ s: CatState) { self = BotState(rawValue: s.rawValue) ?? .working }
}

extension CatEngine {
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
            guard tool != "AskUserQuestion" else { break }
            if isExternalAgent { upsertExternalAgent(id: agentId, name: validAgent!) } else { upsertWorkspaceTask(id: agentId, projectName: projectName, cwd: cwd) }
            state.updateTask(id: agentId, state: .working)
            let input = payload["tool_input"] as? [String: Any] ?? [:]
            let step = frenchStep(tool: tool, input: input)
```

and replace it with:

```swift
            guard tool != "AskUserQuestion" else { break }
            if isExternalAgent { upsertExternalAgent(id: agentId, name: validAgent!) } else { upsertWorkspaceTask(id: agentId, projectName: projectName, cwd: cwd) }
            // A search tool (web search, web fetch, grep, glob and the Gemini and Codex ones) is "searching"; any other tool is "working".
            state.updateTask(id: agentId, state: BotState(CatRules.toolState(tool)))
            let input = payload["tool_input"] as? [String: Any] ?? [:]
            let step = frenchStep(tool: tool, input: input)
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift

        case "PostToolUse":
            state.updateTask(id: agentId, state: .working)
            // Live diff for Edit / MultiEdit / Write
            let diffTool = payload["tool_name"] as? String ?? ""
            let diffInput = payload["tool_input"] as? [String: Any] ?? [:]
            if let diff = buildFileDiff(tool: diffTool, input: diffInput, pillId: agentId) {
```

and replace it with:

```swift

        case "PostToolUse":
            let diffTool = payload["tool_name"] as? String ?? ""
            // The tool that just finished decides: a search tool keeps the cat searching, and the next tool of any other kind puts it back to working.
            state.updateTask(id: agentId, state: BotState(CatRules.toolState(diffTool)))
            // Live diff for Edit / MultiEdit / Write
            let diffInput = payload["tool_input"] as? [String: Any] ?? [:]
            if let diff = buildFileDiff(tool: diffTool, input: diffInput, pillId: agentId) {
```

- [ ] **Step 4: Run it and build**

Run: `bash scripts/test-cat-rules.sh 2>&1 | grep -E "✗|passed|failed"`
Expected: `All tests passed.`

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/App/HookServer.swift NotchBuddy/Sources/App/CatEngine+App.swift tests/CatRulesTests.swift
git commit -m "feat(cat): an agent running a search tool is searching, and the next tool puts it back to working

PreToolUse and PostToolUse ask CatRules.toolState, whose lists are search-tools.json (web search, web fetch, grep, glob and
the Gemini and Codex ones).

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 10: Sleeping (stage 6)

**Agent:** `nm-implementer-deep`. The clock and its tests are given in full; the wiring touches the hook server, the window controller, `AppState` and two canvases and must be read as a whole.

**Files:**
- Create: `NotchBuddy/Sources/App/CatSleep.swift`, `NotchBuddy/Sources/App/CatSleep+App.swift`, `tests/CatSleepTests.swift`, `scripts/test-cat-sleep.sh`
- Modify: `NotchBuddy/Sources/App/CatRules.swift` (`shown`), `NotchBuddy/Sources/App/AppState.swift` (`catAsleep`, `baseState`, `effectiveState`), `NotchBuddy/Sources/App/CatEngine+App.swift` (`BotState.shown(asleep:)`), `NotchBuddy/Sources/App/HookServer.swift`, `NotchBuddy/Sources/App/IslandWindowController.swift`, `NotchBuddy/Sources/App/AppDelegate.swift`, `NotchBuddy/Sources/App/BotCanvasView.swift`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (by `xcodegen`)

**Interfaces:**
- Consumes: `CatRules.sleepDelay(state:quietMs:)`, `CatRules.wakes(_:)` and `CatRules.sleepAfterMs` (stage 2: `sequence-cases.json` `sleep`), the engine's Playful wake with zoomies (`zoomiesAndWake`), `AppState.musicPlaying`, `pendingApproval` and `pendingQuestion`.
- Produces `CatSleepClock` (`@MainActor`, Foundation only): `init(now:schedule:keepAwake:)`, `start()`, `stateChanged(_:)`, `agentEvent()`, `wake(_ kind: String)`, `asleep`, `onChange`; `CatRules.shown(_:asleep:)`; `AppState.catAsleep`, `AppState.baseState` and an `effectiveState` that shows `.sleeping` instead of `.idle` while asleep; `BotState.shown(asleep:)`; the app's `CatSleepClock.shared` and `attach(to:)`.
- The rules, as built. **One timer:** set when the cat is idle for what is left of the ten minutes since the last event, cancelled by any other state, replaced by every event; a timer that fires early waits for the rest. **Quiet counts from the last event, a state change or a wake,** so a cat that was busy for an hour does not fall asleep the moment it is idle again. **A hover or a click wakes a sleeping cat** and restarts the ten minutes; on an awake cat they do nothing, so a pointer resting on the island does not push bedtime back. **Something else can keep an idle cat awake** (plan decision): Apple Music playing (it dances, which a sleeping cat cannot) or a card waiting for an answer on any pill; the clock asks when the timer fires and, if so, starts the ten minutes again. **An idle pill's cat sleeps with the big one** (`MiniBotCanvasView` shows `task.state.shown(asleep:)`); a pill in any other state shows its own. Playful wakes with zoomies by the engine's own rule.

- [ ] **Step 1: Write the failing tests**

The program moves a clock and a one-shot timer by hand (`FakeTimers`, which also counts every timer ever set, to show that nothing polls) and checks the nine groups below, then the source pins on the wiring.

**Create `scripts/test-cat-sleep.sh`**:

```bash
#!/usr/bin/env bash
# Cat sleep: the one-shot timer (ten minutes with no agent event, reset by each event, never while busy, no polling), what wakes a sleeping cat,
# and what an idle cat shows, on timers the test moves by hand.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-sleep.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/CatRules.swift NotchBuddy/Sources/App/CatSleep.swift \
    tests/CatTestSupport.swift tests/CatSleepTests.swift \
    -o "$TEST_DIR/cat-sleep-tests"
"$TEST_DIR/cat-sleep-tests"
```

**Create `tests/CatSleepTests.swift`**:

```swift
import Foundation

/// Timers the tests move by hand: a clock in milliseconds and the one-shot timers set on it. It counts every timer ever set, so a test can show that
/// nothing polls.
@MainActor
final class FakeTimers {
    struct Pending { var id: Int; var at: Double; var fire: @MainActor @Sendable () -> Void }
    var t = 0.0
    private(set) var pending: [Pending] = []
    private(set) var scheduled = 0
    private var next = 0

    func schedule(_ afterMs: Double, _ fire: @escaping @MainActor @Sendable () -> Void) -> CatSleepClock.Cancel {
        scheduled += 1; next += 1
        let id = next
        pending.append(Pending(id: id, at: t + afterMs, fire: fire))
        return { [weak self] in MainActor.assumeIsolated { self?.pending.removeAll { $0.id == id } } }
    }

    /// Moves the clock on, firing the timers that fall due on the way, in order.
    func advance(_ ms: Double) {
        let end = t + ms
        while let due = pending.filter({ $0.at <= end }).min(by: { $0.at < $1.at }) {
            pending.removeAll { $0.id == due.id }
            t = max(t, due.at)
            due.fire()
        }
        t = end
    }

    /// Fires the next timer now, before it is due (a scheduler that is early).
    func fireEarly() {
        guard let first = pending.first else { return }
        pending.removeAll { $0.id == first.id }
        first.fire()
    }
}

@main
enum CatSleepTests {
    static let minute = 60_000.0

    @MainActor static func make(keepAwake: @escaping () -> Bool = { false }) -> (clock: CatSleepClock, timers: FakeTimers, changes: Box) {
        let timers = FakeTimers(), box = Box()
        let clock = CatSleepClock(now: { timers.t }, schedule: { timers.schedule($0, $1) }, keepAwake: keepAwake)
        clock.onChange = { box.changes.append($0) }
        clock.start()
        return (clock, timers, box)
    }
    @MainActor final class Box { var changes: [Bool] = [] }

    @MainActor static func main() {
        CT.section("ten minutes with no agent event put an idle cat to sleep")
        do {
            let (clock, timers, box) = make()
            CT.check("a timer is set at the start, the one timer", timers.pending.count, 1)
            timers.advance(10 * minute - 1)
            CT.check("not yet after 9 min 59.999 s", clock.asleep, false)
            timers.advance(1)
            CT.check("asleep at ten minutes", clock.asleep, true)
            CT.check("and the app was told once", box.changes, [true])
            CT.check("the timer is spent: nothing is left pending", timers.pending.count, 0)
        }

        CT.section("every agent event starts the ten minutes again")
        do {
            let (clock, timers, _) = make()
            timers.advance(9 * minute); clock.agentEvent()
            timers.advance(9 * minute)
            CT.check("nine minutes after the event the cat is still awake", clock.asleep, false)
            timers.advance(minute)
            CT.check("ten minutes after it, asleep", clock.asleep, true)
        }

        CT.section("no polling: at most one timer is ever waiting, and an hour of quiet sets one")
        do {
            let (clock, timers, _) = make()
            timers.advance(60 * minute)
            CT.check("an hour with no event: one timer set in all", timers.scheduled, 1)
            let (c2, t2, _) = make()
            var most = 0
            for i in 0..<200 { t2.advance(7_000); if i % 3 == 0 { c2.agentEvent() }; most = max(most, t2.pending.count) }
            CT.check("two hundred events: never more than one timer waiting", most, 1)
            CT.checkTrue("and the first cat went on sleeping", clock.asleep)
        }

        CT.section("only an idle cat sleeps: never during an approval, a question or any other state, and the timer stops")
        for st in CatState.allCases where st != .idle {
            let (clock, timers, _) = make()
            clock.stateChanged(st)
            CT.check("\(st.rawValue): no timer is waiting", timers.pending.count, 0)
            timers.advance(60 * minute)
            CT.check("\(st.rawValue): an hour later the cat has not gone to sleep", clock.asleep, false)
        }
        do {
            let (clock, timers, _) = make()
            clock.stateChanged(.working)
            timers.advance(30 * minute)
            clock.stateChanged(.idle)
            CT.check("back to idle: one timer again", timers.pending.count, 1)
            timers.advance(9 * minute)
            CT.check("the ten minutes count from the return to idle, not from the last event long ago", clock.asleep, false)
            timers.advance(minute)
            CT.check("and the cat sleeps ten minutes after it", clock.asleep, true)
        }

        CT.section("any agent event, a hover or a click wakes a sleeping cat; other kinds do nothing")
        do {
            let (clock, timers, box) = make()
            timers.advance(10 * minute)
            clock.wake("keyboard")
            CT.check("an unknown kind leaves it asleep", clock.asleep, true)
            clock.wake("hover")
            CT.check("a hover wakes it", clock.asleep, false)
            timers.advance(9 * minute)
            CT.check("and the ten minutes start again from the wake", clock.asleep, false)
            timers.advance(minute)
            CT.check("asleep again ten minutes after", clock.asleep, true)
            clock.wake("click")
            CT.check("a click wakes it", clock.asleep, false)
            timers.advance(10 * minute)
            clock.agentEvent()
            CT.check("an agent event wakes it", clock.asleep, false)
            CT.check("each change was reported once, in order", box.changes, [true, false, true, false, true, false])
            let (awake, t2, _) = make()
            t2.advance(5 * minute); awake.wake("hover"); awake.wake("click")
            t2.advance(5 * minute)
            CT.check("hovering an awake cat does not push its bedtime back", awake.asleep, true)
        }
        do {
            let (clock, timers, _) = make()
            timers.advance(10 * minute)
            clock.stateChanged(.dizzy)
            CT.check("a sleeping cat that is made dizzy wakes", clock.asleep, false)
        }

        CT.section("something else can keep an idle cat awake: Apple Music, which makes it dance, or a card that is waiting")
        do {
            var music = true
            let (clock, timers, _) = make(keepAwake: { music })
            timers.advance(10 * minute)
            CT.check("music is playing: the cat stays awake", clock.asleep, false)
            CT.check("and the timer is set again, still one", timers.pending.count, 1)
            timers.advance(10 * minute)
            CT.check("ten minutes later, still playing: awake", clock.asleep, false)
            music = false
            timers.advance(10 * minute)
            CT.check("the music stops: ten minutes later it sleeps", clock.asleep, true)
        }

        CT.section("a timer that fires early waits for the rest, and a state change that raced it is not an error")
        do {
            let (clock, timers, _) = make()
            timers.advance(4 * minute)
            timers.fireEarly()
            CT.check("six minutes early: not asleep", clock.asleep, false)
            CT.check("and a timer waits for the rest", timers.pending.count, 1)
            timers.advance(6 * minute)
            CT.check("it sleeps at the ten minutes", clock.asleep, true)
        }

        CT.section("what an idle cat shows")
        CT.check("idle and asleep shows sleeping", CatRules.shown(.idle, asleep: true), CatState.sleeping)
        CT.check("idle and awake shows idle", CatRules.shown(.idle, asleep: false), CatState.idle)
        for st in CatState.allCases where st != .idle { CT.check("\(st.rawValue) shows itself, asleep or not", [CatRules.shown(st, asleep: true), CatRules.shown(st, asleep: false)], [st, st]) }

        CT.section("sleeping in the app (source pins: no test program can run the island)")
        func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/" + file, encoding: .utf8)) ?? "" }
        let hook = source("HookServer.swift"), app = source("AppState.swift"), island = source("IslandWindowController.swift"), canvases = source("BotCanvasView.swift")
        CT.check("every agent event wakes the cat and resets the timer: events, permission requests and questions", hook.components(separatedBy: "CatSleepClock.shared.agentEvent()").count - 1, 3)
        CT.checkTrue("the app holds whether the cat sleeps, and the cat shows sleeping instead of idle", app.contains("@Published var catAsleep") && app.contains("var baseState: BotState") && app.contains(".shown(asleep: catAsleep)"))
        CT.checkTrue("a hover on the island and a click wake it", island.contains("CatSleepClock.shared.wake(\"hover\")") && island.contains("CatSleepClock.shared.wake(\"click\")"))
        CT.checkTrue("the small cats of idle pills sleep with the big one", canvases.contains("task.state.shown(asleep: AppState.shared.catAsleep)") && canvases.contains("newState.shown(asleep: AppState.shared.catAsleep)"))
        CT.checkTrue("the clock is attached to the app when the island is set up", source("AppDelegate.swift").contains("CatSleepClock.shared.attach(to: AppState.shared)"))
        CT.checkTrue("the app's clock keeps an idle cat awake while music plays or a card waits", source("CatSleep+App.swift").contains("app.musicPlaying") && source("CatSleep+App.swift").contains("app.pendingApproval != nil || app.pendingQuestion != nil"))
        CT.finish()
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-sleep.sh 2>&1 | head -3`
Expected: FAIL: `<unknown>:0: error: error opening input file 'NotchBuddy/Sources/App/CatSleep.swift' (No such file or directory)`.

- [ ] **Step 3: Write the clock**

**Edit `NotchBuddy/Sources/App/CatRules.swift`**, find this text (it occurs exactly once):

```swift
    }

    /// Anything that wakes a sleeping cat. In Playful it wakes with zoomies (see the Playful profile).
    static let wakeEvents = ["hook", "hover", "click"]
```

and replace it with:

```swift
    }

    /// What an idle cat shows: sleeping once the sleep timer has fired, idle otherwise. Every other state shows itself.
    static func shown(_ state: CatState, asleep: Bool) -> CatState { asleep && state == .idle ? .sleeping : state }

    /// Anything that wakes a sleeping cat. In Playful it wakes with zoomies (see the Playful profile).
    static let wakeEvents = ["hook", "hover", "click"]
```

**Create `NotchBuddy/Sources/App/CatSleep.swift`**:

```swift
import Foundation

// The sleep timer: an idle cat falls asleep after ten minutes with no agent event, and any agent event, hover or click wakes it (Playful wakes with
// zoomies: that is the engine's own rule). One one-shot timer, set when the cat is idle and reset by every event, so nothing polls and a hidden
// island costs nothing. The rules themselves are `CatRules` (`sleepDelay`, `wakes`, `shown`; tests/fixtures/cat/sequence-cases.json pins them);
// this class only keeps the time. It takes its clock and its timer from outside, so a test moves both by hand. Foundation only.

@MainActor
final class CatSleepClock {
    /// Cancels a scheduled call.
    typealias Cancel = () -> Void

    private let now: () -> Double
    private let schedule: (_ afterMs: Double, _ fire: @escaping @MainActor @Sendable () -> Void) -> Cancel
    /// True while something else keeps an idle cat awake: Apple Music is playing (it makes the cat dance, which a sleeping cat cannot) or a card
    /// is waiting for the user. Asked when the timer fires; if it says yes the ten minutes start again.
    private let keepAwake: () -> Bool
    private var cancel: Cancel?
    private var state: CatState = .idle
    private var lastEvent: Double
    private(set) var asleep = false
    /// Called when the cat falls asleep (true) or wakes (false).
    var onChange: ((Bool) -> Void)?

    /// `now` is milliseconds, `schedule` runs `fire` once after `afterMs` and returns a way to cancel it.
    init(now: @escaping () -> Double, schedule: @escaping (Double, @escaping @MainActor @Sendable () -> Void) -> Cancel, keepAwake: @escaping () -> Bool = { false }) {
        self.now = now; self.schedule = schedule; self.keepAwake = keepAwake
        lastEvent = now()
    }

    /// Starts the clock: the cat is idle, so the ten minutes begin now.
    func start() { lastEvent = now(); rearm() }

    /// The state the cat would show if it were awake changed. Only an idle cat sleeps: any other state (an approval or a question included) stops the
    /// timer and wakes the cat, and idle starts the ten minutes.
    func stateChanged(_ new: CatState) {
        guard new != state else { return }
        state = new
        lastEvent = now()
        setAsleep(false)
        rearm()
    }

    /// An agent event (any hook event): the cat wakes and the ten minutes start again.
    func agentEvent() {
        lastEvent = now()
        setAsleep(false)
        rearm()
    }

    /// A hover or a click (`CatRules.wakes`) wakes a sleeping cat and restarts the ten minutes. On an awake cat it does nothing: moving the pointer over
    /// the island does not push bedtime back.
    func wake(_ kind: String) {
        guard asleep, CatRules.wakes(kind) else { return }
        lastEvent = now()
        setAsleep(false)
        rearm()
    }

    private func rearm() {
        cancel?(); cancel = nil
        guard !asleep, let delay = CatRules.sleepDelay(state: state, quietMs: now() - lastEvent) else { return }
        cancel = schedule(delay) { [weak self] in self?.fire() }
    }

    private func fire() {
        cancel = nil
        guard let delay = CatRules.sleepDelay(state: state, quietMs: now() - lastEvent) else { return }   // the state changed on the way: nothing to do
        if delay > 1 { cancel = schedule(delay) { [weak self] in self?.fire() }; return }                 // the timer was early: wait for the rest
        if keepAwake() { lastEvent = now(); rearm(); return }
        setAsleep(true)
    }

    private func setAsleep(_ value: Bool) {
        guard value != asleep else { return }
        asleep = value
        onChange?(value)
    }
}
```

- [ ] **Step 4: Run it: the clock passes and only the wiring pins fail**

Run: `bash scripts/test-cat-sleep.sh 2>&1 | grep -E "✗|failed"`
Expected: six `✗` lines, all under "sleeping in the app (source pins…)" (every agent event wakes the cat, the app holds whether the cat sleeps, a hover and a click wake it, the small cats of idle pills sleep with the big one, the clock is attached when the island is set up, the app's clock keeps an idle cat awake) and `6 test(s) failed.`

- [ ] **Step 5: Wire it into the app**

`AppState.catAsleep` is what the clock decides; `effectiveState` (what the big cat shows) is the base state with sleeping instead of idle. The clock watches the base state through Combine (`$tasks`, `$focusId` and `$stateOverride` together, de-duplicated, delivered on the next turn of the run loop because a `@Published` value changes after its publisher fires). Every hook event, permission request and question calls `agentEvent()` (after the chat check: a chat's own Claude Code run is not an agent session); the island's hover and a click on it call `wake`.

**Edit `NotchBuddy/Sources/App/AppDelegate.swift`**, find this text (it occurs exactly once):

```swift
        islandController?.showWindow(nil)
        islandController?.fsm.launch()
        HookServer.shared.start()
        N8nPoller.shared.start()
```

and replace it with:

```swift
        islandController?.showWindow(nil)
        islandController?.fsm.launch()
        CatSleepClock.shared.attach(to: AppState.shared)   // an idle cat falls asleep after ten minutes with no agent event
        HookServer.shared.start()
        N8nPoller.shared.start()
```

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
    // Bot state override
    @Published var stateOverride: BotState? = nil

    // Real notch dimensions (set by IslandWindowController on launch)
```

and replace it with:

```swift
    // Bot state override
    @Published var stateOverride: BotState? = nil
    /// True while the idle cat is asleep: ten minutes with no agent event (`CatSleepClock`). The cat then shows `.sleeping` instead of `.idle`.
    @Published var catAsleep = false

    // Real notch dimensions (set by IslandWindowController on launch)
```

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
    }

    var effectiveState: BotState {
        stateOverride ?? focusTask?.state ?? .idle
    }

```

and replace it with:

```swift
    }

    /// The state the cat would show if it were awake: the override, else the focused task's.
    var baseState: BotState {
        stateOverride ?? focusTask?.state ?? .idle
    }

    /// The state the cat shows: the base state, and sleeping instead of idle once the sleep timer has fired.
    var effectiveState: BotState {
        baseState.shown(asleep: catAsleep)
    }

```

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**, find this text (it occurs exactly once):

```swift
                let dt = CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                engine.useCharacter(CatConfig.shared.character)   // Settings → Cat → Character
                engine.setDancing(isDancing)
                engine.update(dt: dt)
```

and replace it with:

```swift
                let dt = CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                engine.useCharacter(CatConfig.shared.character)   // Settings → Cat → Character
                engine.setState(task.state.shown(asleep: AppState.shared.catAsleep))   // an idle pill's cat sleeps with the big one
                engine.setDancing(isDancing)
                engine.update(dt: dt)
```

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**, find this text (it occurs exactly once):

```swift
        }
        .onChange(of: task.state) { _, newState in
            engine.setState(newState)
        }
        .onAppear {
            engine.setState(task.state, force: true)
            if let emote = task.emote {
                engine.setPermanentEmote(emote)
```

and replace it with:

```swift
        }
        .onChange(of: task.state) { _, newState in
            engine.setState(newState.shown(asleep: AppState.shared.catAsleep))
        }
        .onAppear {
            engine.setState(task.state.shown(asleep: AppState.shared.catAsleep), force: true)
            if let emote = task.emote {
                engine.setPermanentEmote(emote)
```

**Edit `NotchBuddy/Sources/App/CatEngine+App.swift`**, find this text (it occurs exactly once):

```swift
    /// The app's state for a cat state (the two enums have the same cases, with the same raw values).
    init(_ s: CatState) { self = BotState(rawValue: s.rawValue) ?? .working }
}

```

and replace it with:

```swift
    /// The app's state for a cat state (the two enums have the same cases, with the same raw values).
    init(_ s: CatState) { self = BotState(rawValue: s.rawValue) ?? .working }

    /// What a cat in this state shows: sleeping instead of idle once the sleep timer has fired (`CatRules.shown`).
    func shown(asleep: Bool) -> BotState { BotState(CatRules.shown(CatState(rawValue: rawValue) ?? .idle, asleep: asleep)) }
}

```

**Create `NotchBuddy/Sources/App/CatSleep+App.swift`**:

```swift
import Combine
import Foundation
import QuartzCore

// The app's way into the sleep clock: real time, a one-shot timer on the main queue, what keeps an idle cat awake, and the link to `AppState`.
// Nothing here is in the contract, and the test programs do not compile this file.

extension CatSleepClock {
    /// The app's clock. An idle cat stays awake while Apple Music plays (it dances, which a sleeping cat cannot) and while a card waits for an answer.
    static let shared = CatSleepClock(
        now: { CACurrentMediaTime() * 1000 },
        schedule: { afterMs, fire in
            let item = DispatchWorkItem { MainActor.assumeIsolated { fire() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + afterMs / 1000, execute: item)
            return { item.cancel() }
        },
        keepAwake: {
            let app = AppState.shared
            #if !APPSTORE
            if app.musicPlaying { return true }
            #endif
            return app.pendingApproval != nil || app.pendingQuestion != nil
        })

    private static var subscriptions = Set<AnyCancellable>()

    /// Starts the clock and keeps it in step with the app: the state the cat would show if it were awake (the override, else the focused task's)
    /// feeds `stateChanged`, and when the clock puts the cat to sleep or wakes it, `AppState.catAsleep` follows.
    func attach(to app: AppState) {
        onChange = { [weak app] asleep in app?.catAsleep = asleep }
        app.$tasks.combineLatest(app.$focusId, app.$stateOverride)
            .map { tasks, focus, forced -> CatState in
                let state = forced ?? (tasks.first { $0.id == focus } ?? tasks.first)?.state ?? .idle
                return CatState(rawValue: state.rawValue) ?? .idle
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in MainActor.assumeIsolated { self?.stateChanged(state) } }
            .store(in: &Self.subscriptions)
        start()
    }
}
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
        #if !APPSTORE
        // The events of a chat's own Claude Code run are not a session: the chat's stream already shows its steps.
        if case .chat = ClaudeHookRouting.route(payload: payload, live: ClaudeService.shared.liveClaudeSessions) { return }
        #endif
        let sessionId = payload["session_id"] as? String
                     ?? payload["conversation_id"] as? String
                     ?? "unknown"
        let cwd = payload["cwd"] as? String ?? ""
```

and replace it with:

```swift
        #if !APPSTORE
        // The events of a chat's own Claude Code run are not a session: the chat's stream already shows its steps.
        if case .chat = ClaudeHookRouting.route(payload: payload, live: ClaudeService.shared.liveClaudeSessions) { return }
        #endif
        CatSleepClock.shared.agentEvent()   // any agent event wakes a sleeping cat and starts its ten minutes again
        let sessionId = payload["session_id"] as? String
                     ?? payload["conversation_id"] as? String
                     ?? "unknown"
        let cwd = payload["cwd"] as? String ?? ""
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
            processChatPermission(fd: fd, sessionID: chatSession, payload: payload)
            return
        }
        #endif
        let sessionId = payload["session_id"] as? String
                     ?? payload["conversation_id"] as? String
                     ?? "unknown"
        let cwd       = payload["cwd"]        as? String ?? ""
```

and replace it with:

```swift
            processChatPermission(fd: fd, sessionID: chatSession, payload: payload)
            return
        }
        #endif
        CatSleepClock.shared.agentEvent()
        let sessionId = payload["session_id"] as? String
                     ?? payload["conversation_id"] as? String
                     ?? "unknown"
        let cwd       = payload["cwd"]        as? String ?? ""
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**, find this text (it occurs exactly once):

```swift
            }
            return
        }
        #endif
        let sessionId = payload["session_id"] as? String
                     ?? payload["conversation_id"] as? String
                     ?? "unknown"
        let cwd       = payload["cwd"]        as? String ?? ""
```

and replace it with:

```swift
            }
            return
        }
        #endif
        CatSleepClock.shared.agentEvent()
        let sessionId = payload["session_id"] as? String
                     ?? payload["conversation_id"] as? String
                     ?? "unknown"
        let cwd       = payload["cwd"]        as? String ?? ""
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, find this text (it occurs exactly once):

```swift
                NotificationCenter.default.post(name: .greetingHover, object: nil)
            }
            fsm.mouseEntered()
        }
```

and replace it with:

```swift
                NotificationCenter.default.post(name: .greetingHover, object: nil)
            }
            CatSleepClock.shared.wake("hover")   // a hover wakes a sleeping cat
            fsm.mouseEntered()
        }
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, find this text (it occurs exactly once):

```swift
            MainActor.assumeIsolated {
                guard self.wasInIsland else { return }
                self.pendingIslandClick = true
                self.hoverTimer?.cancel()
```

and replace it with:

```swift
            MainActor.assumeIsolated {
                guard self.wasInIsland else { return }
                CatSleepClock.shared.wake("click")   // a click wakes a sleeping cat
                self.pendingIslandClick = true
                self.hoverTimer?.cancel()
```

- [ ] **Step 6: Run the tests and build**

Run: `bash scripts/test-cat-sleep.sh 2>&1 | grep -E "✗|passed|failed"; bash scripts/test-cat-rules.sh 2>&1 | tail -1`
Expected: `All tests passed.` twice.

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `Created project at …` and the last lines end with `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Build the App Store target too**

`CatSleep+App.swift` reads `AppState.musicPlaying`, which does not exist in the App Store build; it is behind `#if !APPSTORE`.

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3`
Expected: the last lines end with `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add NotchBuddy/Sources/App/CatSleep.swift NotchBuddy/Sources/App/CatSleep+App.swift NotchBuddy/Sources/App/CatRules.swift NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/CatEngine+App.swift NotchBuddy/Sources/App/HookServer.swift NotchBuddy/Sources/App/IslandWindowController.swift NotchBuddy/Sources/App/AppDelegate.swift NotchBuddy/Sources/App/BotCanvasView.swift tests/CatSleepTests.swift scripts/test-cat-sleep.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): an idle cat falls asleep after ten minutes with no agent event, on one one-shot timer

Never during an approval or a question or while music plays; any hook event, hover or click wakes it (Playful with zoomies, the
engine's rule). The clock takes its time and timer from outside, so its test moves both by hand and shows that nothing polls.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 11: The music bob (stage 6)

**Agent:** `nm-implementer-light`. The code is given in full; the tests and the sheet prove it.

**Files:**
- Modify: `NotchBuddy/Sources/App/CatGeometry.swift` (`CatDance`, `CatPose` becomes `Equatable`), `NotchBuddy/Sources/App/CatEffects.swift` (`applyDance` uses `CatDance`), `NotchBuddy/Sources/App/CatEngine.swift` (`look`), `tests/CatEffectsTests.swift`, `tests/CatEngineTests.swift`, `scripts/render-cats.swift` (`--dance`)

**Interfaces:**
- Consumes: the existing Apple Music dance (`setDancing`, `dancingLevel`, `CatEffects.applyDance`: a 112 BPM hop, sway and squash of the whole cat).
- Produces `CatDance.bpm` (112), `CatDance.beat(_:)`, `CatDance.curves(_:)` (`hop`: 0 on the beat and 1 half a beat later; `land`: 1 on the beat, gone a moment later), `CatDance.pose(_:level:seconds:)`: the head tips back a little on the way up and nods down on the landing, the ears stretch with the hop and flop outward as the cat lands. `CatEngine.look` hands the renderer the dance pose; **the engine's own pose, which the fixtures pin, is not touched.** Windows and Linux have no Apple Music, so this is Mac only.

- [ ] **Step 1: Write the failing tests**

**Edit `tests/CatEffectsTests.swift`**, find this text (it occurs exactly once):

```swift
        }
        CT.checkTrue("at level 1 it hops and sways around the pivot", moved)
        CT.finish()
    }
```

and replace it with:

```swift
        }
        CT.checkTrue("at level 1 it hops and sways around the pivot", moved)

        CT.section("the music bob: the head nods and the ears bounce on the 112 BPM beat of the dance")
        let beatS = 60.0 / CatDance.bpm
        CT.check("the beat is 112 beats a minute", CatDance.bpm, 112)
        CT.checkNear("the curves repeat every beat: a hop", CatDance.curves(0.123).hop, CatDance.curves(0.123 + beatS).hop)
        CT.checkNear("and the landing", CatDance.curves(0.123).land, CatDance.curves(0.123 + 3 * beatS).land)
        CT.checkNear("the cat is on the ground on the beat (no hop, a full landing)", CatDance.curves(5 * beatS).hop, 0)
        CT.checkNear("and at the top half a beat later (the landing has gone)", CatDance.curves(5.5 * beatS).land, 0)
        let rest = CatPose()
        CT.checkTrue("at level 0 the pose comes back as it went in", CatDance.pose(rest, level: 0, seconds: 0.4) == rest && CatDance.pose(rest, level: 0.0005, seconds: 0.4) == rest)
        let landing = CatDance.pose(rest, level: 1, seconds: 5 * beatS), top = CatDance.pose(rest, level: 1, seconds: 5.5 * beatS)
        CT.checkTrue("on the landing the head nods down and the ears flop outward", landing.pitch < -0.1 && landing.earL > 0.15 && landing.earR == landing.earL)
        CT.checkTrue("at the top of the hop the head tips back a little and the ears stand taller", top.pitch > 0.05 && top.earU > 1.1 && top.earL == 0)
        CT.checkTrue("half the level moves the pose half as far", abs(CatDance.pose(rest, level: 0.5, seconds: 5 * beatS).pitch - landing.pitch / 2) < 1e-12)
        var worst = 0.0, finite = true
        for i in 0..<2000 {
            let q = CatDance.pose(rest, level: Double(i % 11) / 10, seconds: Double(i) * 0.0173)
            worst = max(worst, abs(q.pitch), abs(q.earL), abs(q.earU - 1))
            finite = finite && [q.pitch, q.earL, q.earR, q.earU].allSatisfy(\.isFinite)
        }
        CT.checkTrue("it stays small and finite at every moment and level (largest move \(String(format: "%.2f", worst)))", finite && worst < 0.3)
        var tilted = rest; tilted.tilt = 0.3; tilted.earF = 0.5; tilted.yaw = 0.4
        let moved2 = CatDance.pose(tilted, level: 1, seconds: 5 * beatS)
        CT.checkTrue("everything else about the pose is left alone", moved2.tilt == 0.3 && moved2.earF == 0.5 && moved2.yaw == 0.4 && moved2.sx == 1 && moved2.oy == 0)
        CT.finish()
    }
```

**Edit `tests/CatEngineTests.swift`**, find this text (it occurs exactly once):

```swift
            CT.checkTrue("after ten quiet seconds an idle cat has no queued actions and no tweens", e.q.isEmpty && e.tw.isEmpty && e.parts.isEmpty && e.balls.isEmpty)
        }
        CT.finish()
    }
```

and replace it with:

```swift
            CT.checkTrue("after ten quiet seconds an idle cat has no queued actions and no tweens", e.q.isEmpty && e.tw.isEmpty && e.parts.isEmpty && e.balls.isEmpty)
        }
        do {
            // The music bob rides on what the renderer is given, not on the engine's own pose: the fixtures never see it.
            let (e, clock, _) = makeEngine(momo)
            for _ in 0..<120 { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60) }
            let landing = 5 * 60.0 / CatDance.bpm
            CT.checkTrue("not dancing: the look's pose is the engine's pose", e.look(time: landing).pose.pitch == e.s.pitch && e.look(time: landing).pose.earL == e.s.earL)
            e.setDancing(true)
            for _ in 0..<60 { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60) }
            CT.check("dancing for a second: the level is full", e.dancingLevel, 1)
            let bob = e.look(time: landing).pose
            CT.checkTrue("on the landing the look's head nods and its ears flop", bob.pitch < e.s.pitch - 0.1 && bob.earL > e.s.earL + 0.15)
            let before = e.s
            _ = e.look(time: landing)
            CT.checkTrue("the engine's own pose is not touched (the fixtures stay valid)", e.s == before)
            e.setDancing(false)
            for _ in 0..<60 { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60) }
            CT.checkTrue("and when the music stops it fades out", e.dancingLevel == 0 && e.look(time: landing).pose.pitch == e.s.pitch)
        }
        CT.finish()
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash scripts/test-cat-effects.sh 2>&1 | grep -E "error" | head -2`
Expected: FAIL: `error: cannot find 'CatDance' in scope`.

- [ ] **Step 3: Write the bob**

**Edit `NotchBuddy/Sources/App/CatEffects.swift`**, find this text (it occurs exactly once):

```swift
    static func applyDance(_ cg: CGContext, level l: Double, seconds: Double, pivotX px: Double, pivotY py: Double, size R: Double) {
        guard l > 0.001 else { return }
        let beat = seconds * 112 / 60, hop = abs(sin(Double.pi * beat)), land = pow(1 - hop, 6)
        cg.translateBy(x: px + 0.08 * R * sin(Double.pi * beat) * l, y: py - 0.20 * R * hop * l)
        cg.rotate(by: 0.10 * sin(Double.pi * beat) * l)
```

and replace it with:

```swift
    static func applyDance(_ cg: CGContext, level l: Double, seconds: Double, pivotX px: Double, pivotY py: Double, size R: Double) {
        guard l > 0.001 else { return }
        let beat = CatDance.beat(seconds), (hop, land) = CatDance.curves(seconds)
        cg.translateBy(x: px + 0.08 * R * sin(Double.pi * beat) * l, y: py - 0.20 * R * hop * l)
        cg.rotate(by: 0.10 * sin(Double.pi * beat) * l)
```

**Edit `NotchBuddy/Sources/App/CatEngine.swift`**, find this text (it occurs exactly once):

```swift
    /// Everything the renderer needs to draw this cat right now. `time` is seconds for the motion inside shapes (defaults to the engine's clock).
    func look(time: Double? = nil) -> CatLook {
        var l = CatLook(preset: p, pose: s, eye: eyeShape(), mouthOpen: mouthOpen(), color: col, blushBase: blushBase, time: time ?? now() / 1000)
        l.badge = badge
        l.badgeColor = CatTables.color[state]!
```

and replace it with:

```swift
    /// Everything the renderer needs to draw this cat right now. `time` is seconds for the motion inside shapes (defaults to the engine's clock).
    func look(time: Double? = nil) -> CatLook {
        let seconds = time ?? now() / 1000
        // While Apple Music plays the head bobs and the ears bounce on the beat. That rides on what the renderer is given: the engine's own pose, which the
        // fixtures pin, is not touched.
        var l = CatLook(preset: p, pose: CatDance.pose(s, level: dancingLevel, seconds: seconds), eye: eyeShape(), mouthOpen: mouthOpen(), color: col, blushBase: blushBase, time: seconds)
        l.badge = badge
        l.badgeColor = CatTables.color[state]!
```

**Edit `NotchBuddy/Sources/App/CatGeometry.swift`**, find this text (it occurs exactly once):

```swift

/// The neutral pose: every animatable property at rest. The engine's pose starts here, and `layout` reads one.
struct CatPose {
    var yaw = 0.0, pitch = 0.0, roll = 0.0, tilt = 0.0, open = 1.0, sx = 1.0, sy = 1.0, oy = 0.0, ox = 0.0
    var tint = 0.0, blush = 0.0, es = 1.0, badgeS = 0.0, earL = 0.0, earR = 0.0, earU = 1.0, earF = 0.0
```

and replace it with:

```swift

/// The neutral pose: every animatable property at rest. The engine's pose starts here, and `layout` reads one.
struct CatPose: Equatable {
    var yaw = 0.0, pitch = 0.0, roll = 0.0, tilt = 0.0, open = 1.0, sx = 1.0, sy = 1.0, oy = 0.0, ox = 0.0
    var tint = 0.0, blush = 0.0, es = 1.0, badgeS = 0.0, earL = 0.0, earR = 0.0, earU = 1.0, earF = 0.0
```

**Edit `NotchBuddy/Sources/App/CatGeometry.swift`**, find this text (it occurs exactly once):

```swift
            }
        }
    }
}
```

and replace it with:

```swift
            }
        }
    }
}

// MARK: - The Apple Music dance

/// The Apple Music dance rides on a 112 BPM beat: the whole cat hops, sways and squashes to it (`CatEffects.applyDance`), and its head and ears bob
/// to it (`pose`, which the engine adds to the pose it hands the renderer). Not in the contract: the prototype has no music.
enum CatDance {
    static let bpm = 112.0

    /// How many beats have passed after `seconds`.
    static func beat(_ seconds: Double) -> Double { seconds * bpm / 60 }

    /// Where the cat is in a beat: `hop` is 0 on the beat and 1 half a beat later (how high it is), `land` is 1 on the beat and gone a moment later (how
    /// hard it lands).
    static func curves(_ seconds: Double) -> (hop: Double, land: Double) {
        let hop = abs(sin(Double.pi * beat(seconds)))
        return (hop, pow(1 - hop, 6))
    }

    /// The head-bob and the ear bounce, added to a pose: the head tips back a little on the way up and nods down on the landing, the ears stretch
    /// with the hop and flop outward as the cat lands. `level` is the engine's dancing level, 0 to 1 (it fades in over 0.3 s and out over 0.5 s); at 0
    /// the pose comes back as it was. Nothing else about the pose changes.
    static func pose(_ p: CatPose, level l: Double, seconds: Double) -> CatPose {
        guard l > 0.001 else { return p }
        let (hop, land) = curves(seconds)
        var q = p
        q.pitch += l * (0.08 * hop - 0.16 * land)
        q.earU *= 1 + l * 0.14 * hop
        q.earL += l * 0.2 * land
        q.earR += l * 0.2 * land
        return q
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `for t in effects engine geometry; do printf '%-10s' $t; bash scripts/test-cat-$t.sh 2>&1 | tail -1; done`
Expected: three lines ending `All tests passed.` (the fixtures of the engine still hold: with the dance off, `look` hands over the pose unchanged).

- [ ] **Step 5: The dance sheet**

`render-cats.sh --dance` draws one beat in eight frames, ten beats in, the hop alone (what the app drew before) and then with the head-bob and the ears.

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
//   bash scripts/render-cats.sh --collars --cats shrimpy,latte --scale 2   the three collar styles at Ø12 to Ø66, turned, and in six agent colours.
//                                                                  --scale is the device pixel ratio the readability floors are in: try 1 and 2
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

```

and replace it with:

```swift
//   bash scripts/render-cats.sh --collars --cats shrimpy,latte --scale 2   the three collar styles at Ø12 to Ø66, turned, and in six agent colours.
//                                                                  --scale is the device pixel ratio the readability floors are in: try 1 and 2
//   bash scripts/render-cats.sh --dance --cats shrimpy,momo        one beat of the Apple Music dance in eight frames: the hop alone, then with the head-bob and ears
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case fur
        case collars
    }

```

and replace it with:

```swift
        case fur
        case collars
        case dance
    }

```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
            case "--fur": a.mode = .fur
            case "--collars": a.mode = .collars
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

and replace it with:

```swift
            case "--fur": a.mode = .fur
            case "--collars": a.mode = .collars
            case "--dance": a.mode = .dance
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case .fur: sheet = furSheet(a)
        case .collars: sheet = collarSheet(a)
        }
        sheet.write(to: a.out)
```

and replace it with:

```swift
        case .fur: sheet = furSheet(a)
        case .collars: sheet = collarSheet(a)
        case .dance: sheet = danceSheet(a)
        }
        sheet.write(to: a.out)
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
                CatRenderer.draw(cg, CatLook(preset: preset, pose: v.2), cx: x + cell / 2, cy: top + cell * 0.55, D: 150, CatDrawOptions(fur: v.1))
                cg.restoreGState()
            }
        }
```

and replace it with:

```swift
                CatRenderer.draw(cg, CatLook(preset: preset, pose: v.2), cx: x + cell / 2, cy: top + cell * 0.55, D: 150, CatDrawOptions(fur: v.1))
                cg.restoreGState()
            }
        }
        return sheet
    }

    // MARK: The music dance: one beat in eight frames, with and without the head-bob

    @MainActor static func danceSheet(_ a: Args) -> Sheet {
        let frames = 8, cell = 170.0, labelW = 190.0, D = 90.0, beat = 60 / CatDance.bpm
        let sheet = Sheet(width: labelW + cell * Double(frames) + 8, height: 28 + cell * Double(a.cats.count * 2), scale: a.scale)
        let cg = sheet.cg
        for f in 0..<frames { CatDraw.text(cg, String(format: "%.0f%% of the beat", Double(f) / Double(frames) * 100), x: labelW + (Double(f) + 0.5) * cell, y: 14, size: 11, bold: true, color: CatDraw.white(0.8)) }
        var row = 0
        for id in a.cats {
            for bob in [false, true] {
                let top = 28 + Double(row) * cell, preset = CatPresets.byID(id)
                CatDraw.text(cg, "\(preset.label) · \(bob ? "head-bob and ears" : "the hop alone")", x: labelW / 2, y: top + cell / 2, size: 12, bold: true, color: CatDraw.white(0.85))
                for f in 0..<frames {
                    let (e, _, step) = scene(preset, profile: "playful", D: D, quiet: true)
                    e.setDancing(true)
                    for _ in 0..<90 { step() }                                      // 1.5 s: the dance is at its full level
                    let seconds = 10 * beat + Double(f) / Double(frames) * beat      // frame f of one beat, ten beats in
                    let level = e.dancingLevel
                    if !bob { e.dancingLevel = 0 }                                   // the hop alone: the engine hands the renderer its own pose
                    let look = e.look(time: seconds)
                    e.dancingLevel = level
                    let x = labelW + Double(f) * cell, cx = x + cell / 2, cy = top + cell * 0.5
                    cg.saveGState()
                    cg.clip(CatDraw.roundRect(x + 2, top + 2, cell - 4, cell - 4, 10))
                    cg.fill(CatDraw.roundRect(x, top, cell, cell, 0), CatDraw.black(1))
                    CatEffects.applyDance(cg, level: level, seconds: seconds, pivotX: cx, pivotY: cy + D * 0.45, size: D / 2)
                    CatRenderer.draw(cg, look, cx: cx, cy: cy, D: D)
                    cg.restoreGState()
                }
                row += 1
            }
        }
```

Run: `d="${TMPDIR:-/tmp}/a-mac-5-7"; mkdir -p "$d" && bash scripts/render-cats.sh --dance --cats shrimpy,momo --out "$d/dance.png"`
Expected: `wrote …/dance.png`.

Look at it. Expected: in the second row of each cat the head dips and the ears flop outward on the landing (0 % of the beat) and stand taller at the top of the hop (50 %); the first row has the same hop with still ears.

- [ ] **Step 6: Commit**

```bash
git add NotchBuddy/Sources/App/CatGeometry.swift NotchBuddy/Sources/App/CatEffects.swift NotchBuddy/Sources/App/CatEngine.swift tests/CatEffectsTests.swift tests/CatEngineTests.swift scripts/render-cats.swift
git commit -m "feat(cat): the Apple Music dance bobs the head and bounces the ears on the beat

CatDance gives the renderer a pose with the head nod and the ear bounce; the engine's own pose, which the fixtures pin, is
untouched. render-cats.sh gains --dance.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 12: Owner checkpoint 2: the collars at every size, the sleep, the bob, and the island glow

No code and no commit. The session runs the checks, produces the images and stops; the main session sends them to the owner and brings back the answer to the island-glow question.

- [ ] **Step 1: The tests and the builds**

Run: `for f in scripts/test-cat-*.sh; do printf '%-42s' "$f"; bash "$f" 2>&1 | tail -1; done`
Expected: sixteen lines: `scripts/test-cat-contract.sh` ends `✓ two generator runs write identical bytes` and the other fifteen (`devpanel`, `effects`, `engine`, `frame-meter`, `fur`, `geometry`, `greeting`, `personality`, `presets`, `renderer`, `rules`, `settings-store`, `settings`, `sleep`, `upload`) end `All tests passed.`

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: The images**

Run: `c=.claude/checkpoints/a-cats-5-7/mac-2; mkdir -p "$c" && bash scripts/render-cats.sh --collars --cats shrimpy,momo,latte,midnight,snow --scale 2 --out "$c/collars-2x.png" && bash scripts/render-cats.sh --collars --cats shrimpy,latte --scale 1 --out "$c/collars-1x.png" && bash scripts/render-cats.sh --dance --cats shrimpy,momo --out "$c/dance.png" && bash scripts/render-cats.sh --states --cats shrimpy,momo --out "$c/states.png" && bash scripts/render-cat-settings.sh --out "$c/settings-collar.png" --height 1400 --character latte --collar band && bash scripts/render-cat-panel.sh --out "$c/panel.png" --height 1500 && ls "$c"`
Expected: six `wrote …` lines and `collars-1x.png`, `collars-2x.png`, `dance.png`, `panel.png`, `settings-collar.png`, `states.png`. (`states.png` includes the sleeping state the clock now puts an idle cat in, and searching.)

- [ ] **Step 3: Send the owner these, and ask**

Send the six images. Ask:

1. **The collars at every size** (`collars-2x.png`, and `collars-1x.png` for a screen that is not Retina). Does each style read at Ø12 and Ø16 and on the compact notch's Ø20? Do the light agent colours (Cursor, VS Code) read on the light coats (Latte, Snow)? **At Ø12 on a 1x screen the neckerchief has only 5 to 9 pixels of colour inside its dark edge: that is the contract's floor (7 wide, 5 deep) and its 1.5 px edge. If it is not enough, the floor changes once in `cat-core.js` and its fixture and both apps pick it up.** Every Mac with a notch is Retina.
2. **The look of the paint.** The band, the tag with its highlight, the neckerchief with its crease: as the prototype?
3. **The music bob** (`dance.png`): the head nod and the ears' bounce, second row of each cat. Enough, too much, or not visible?
4. **Open question 1, the island's glow:** `IslandRootView.swift` draws the glow behind the cat from seven literals (`#3B9EFF` … `#F59E0B`). May stage 7 swap them for `Theme.State.glow`? The values are the same, and the plan proves it before the swap. **Answer yes or no: Task 13's Step 9 runs only on yes.**
5. **Open questions 4, 6 and 10:** the big cat wears no collar when idle, asleep or dizzy and no `isIntegration` test decides it (a pill's colour for any pill); the greeting's four session cats wear collars (the Gemini CLI, Codex and Claude Code colours of the prototype) when a style is on; the pills' small cats wear their pill's colour. OK?
6. **Open question 9:** the Settings previews pause when the window is not the key window. OK?

The owner's manual checks on a **Debug build** (quit the installed app first; the session never launches it): in Settings → Cat pick Band and tag, then Neckerchief, then Off: the big cat wears the colour of the agent driving it while that agent works (and none when idle), the pills' small cats wear their pill's colour, and "This cat's collar" overrides it for the chosen cat; drive the socket with a `PreToolUse` event for `WebSearch` (searching, the indigo badge) and then `Edit` (working); leave the app idle for ten minutes (or temporarily: not part of this plan): the cat sleeps, and a hover wakes it (Playful: with zoomies); with Apple Music playing the idle cat dances and does not sleep.

Record the answers. A changed floor or a changed look of the collar is a fix round.

---
### Task 13: Theme tokens, proved by sheets before and after (stage 7)

**Agent:** `nm-implementer`. The edits are given in full; the byte-for-byte comparison of the sheets is the proof.

**Files:**
- Modify: `NotchBuddy/Sources/App/CatFace.swift`, `CatEffects.swift`, `CatGreetingRenderer.swift`, `CatGreeting.swift`, `MotionProfiles.swift`, `CatDevPanel.swift` (and, only with the owner's OK, `IslandRootView.swift`); `scripts/gen-icons.sh`, `render-cat-panel.sh`, `render-cat-settings.sh`, `render-cats.sh`, `test-cat-devpanel.sh`, `test-cat-effects.sh`, `test-cat-engine.sh`, `test-cat-greeting.sh`, `test-cat-renderer.sh`, `test-cat-settings-store.sh`, `test-cat-upload.sh` (each gains `Theme.generated.swift`)
- Create: `tests/CatThemeTests.swift`, `scripts/test-cat-theme.sh`

**Interfaces:**
- Consumes: A-0d's `Theme.generated.swift` (`enum Theme { enum Brand, Cat, Greeting, State }`): `Theme.Cat.pupil` (`"#0E0B09"`) and `Theme.Cat.pupilRGB` (`[Double]`), the same for `mouthInside`, `tongue`, `teeth`, `heart`, `star`, `sweat`, `paper`, `paperFold`, `paperLabel`; `Theme.Greeting.badge`, `tint`, `haloGold`, `haloBlue`, `headerDim` (each with `…RGB`), `Theme.Greeting.streaks` (five hex strings); `Theme.State.color` and `.glow` (`[String: String]`, keyed by `CatState.rawValue`); `Theme.Brand.pageRGB`. The table "Hard-coded colours today" in `docs/THEME.md` is the list of sites; every Mac site in it is replaced here, and no other.
- Produces no new API. **No pixel changes:** every value is the one that is hard-coded today.
- A site whose value differs from its token: **stop and ask**, do not change a value. (The one numeric site, the Debug panel's page colour `0.059, 0.063, 0.071`, is 15, 16 and 18 out of 255 once rounded, which is `Theme.Brand.pageRGB`.) `scripts/render-cats.swift` keeps its own page colour for the contact sheets: it is a script, not a Mac site of the table.

- [ ] **Step 1: Draw the sheets before any change**

Six sheets cover the sites: the ladder (every coat at every size: the pupil, the flat fills), `--states` (the state colours, the glows, the badges), `--emotes` (heart, star, sweat), `--mouths` (inside of the mouth, tongue, teeth), `--catch` (the paper, its fold and its label) and `--greeting` (the badge, the tint, the halo, the header text and the streaks). They use a fake clock and seeded random numbers, so a sheet is the same bytes every run.

Run: `d="${TMPDIR:-/tmp}/a-mac-theme"; mkdir -p "$d/before" "$d/after"; bash scripts/render-cats.sh --out "$d/before/ladder.png" && bash scripts/render-cats.sh --states --cats shrimpy,momo --out "$d/before/states.png" && bash scripts/render-cats.sh --emotes --cats shrimpy,momo --out "$d/before/emotes.png" && bash scripts/render-cats.sh --mouths --cats shrimpy,momo --out "$d/before/mouths.png" && bash scripts/render-cats.sh --catch --cats shrimpy --out "$d/before/catch.png" && bash scripts/render-cats.sh --greeting --cats shrimpy --out "$d/before/greeting.png"; ls "$d/before"`
Expected: six `wrote …` lines and `catch.png`, `emotes.png`, `greeting.png`, `ladder.png`, `mouths.png`, `states.png`.

- [ ] **Step 2: Write the failing pins**

A source-pin program: none of the files holds a hex literal that is a theme colour, none holds the greeting's RGB triples or the panel's `0.059`, and each uses the tokens it should (21 uses in six files). It also holds **the reverse guard for the colours the Windows app copies**: `windows/src/core/pills.ts` reads `PillCatalog.swift` for the collar colours of Gemini CLI (`#8AB4F8`) and Antigravity (`#E879F9`), so the Mac pins its own two values and a change to either is deliberate.

**Create `scripts/test-cat-theme.sh`**:

```bash
#!/usr/bin/env bash
# Cat theme: the Mac's character, branding and greeting colours come from Theme.generated.swift and no hex literal of one is left in the drawing code
# (source pins). That no pixel changed is proved by comparing contact sheets drawn before and after (docs/THEME.md).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-theme.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 tests/CatTestSupport.swift tests/CatThemeTests.swift -o "$TEST_DIR/cat-theme-tests"
"$TEST_DIR/cat-theme-tests"
```

**Create `tests/CatThemeTests.swift`**:

```swift
import Foundation

// The Mac's character, branding and greeting colours come from Theme.generated.swift (shared/theme.json, and the state colours of cat-core.js), not from
// hex literals in the drawing code. These are source pins: they read the files, so they fail the day a colour is typed in again. That stage 7 changed
// no pixel is proved separately, by drawing the contact sheets before and after and comparing the images byte for byte.

@main
enum CatThemeTests {
    static let dir = "NotchBuddy/Sources/App/"
    static func source(_ file: String) -> String { (try? String(contentsOfFile: dir + file, encoding: .utf8)) ?? "" }

    /// Every "#RRGGBB" string in a text, upper-cased.
    static func hexes(_ text: String) -> Set<String> {
        var found = Set<String>()
        var rest = Substring(text)
        while let q = rest.firstIndex(of: "\"") {
            let after = rest.index(after: q)
            guard let end = rest[after...].firstIndex(of: "\"") else { break }
            let s = rest[after..<end]
            if s.count == 7, s.hasPrefix("#"), s.dropFirst().allSatisfy(\.isHexDigit) { found.insert(s.uppercased()) }
            rest = rest[rest.index(after: end)...]
        }
        return found
    }

    @MainActor static func main() {
        let theme = hexes(source("Theme.generated.swift"))
        CT.checkTrue("the generated theme file is there and holds colours (\(theme.count))", theme.count > 30)

        CT.section("no hex literal that is a theme colour is left in the drawing code")
        let files = ["CatFace.swift", "CatEffects.swift", "CatGreeting.swift", "CatGreetingRenderer.swift", "MotionProfiles.swift", "CatDevPanel.swift"]
        var leftovers: [String] = []
        for f in files { for h in hexes(source(f)).intersection(theme).sorted() { leftovers.append("\(f) has \(h)") } }
        CT.checkRows("\(files.count) files: the cat's details, the greeting, the state colours and the glows", leftovers)

        CT.section("the colours as numbers: no RGB triple of the greeting, no 0.059 of the panel's page")
        var triples: [String] = []
        for (f, text) in [("CatGreetingRenderer.swift", "141, 144, 152"), ("CatGreetingRenderer.swift", "127, 180, 234"), ("CatGreetingRenderer.swift", "232, 195, 154"),
                          ("CatGreetingRenderer.swift", "lerp(232"), ("CatDevPanel.swift", "red: 0.059")] where source(f).contains(text) { triples.append("\(f) has \(text)") }
        CT.checkRows("the header text, the tint, the halo's two ends and the panel's page colour", triples)

        CT.section("and each file uses the token it should")
        let uses: [(String, [String])] = [
            ("CatFace.swift", ["Theme.Cat.pupil", "Theme.Cat.heart", "Theme.Cat.star", "Theme.Cat.tongue", "Theme.Cat.mouthInside", "Theme.Cat.teeth"]),
            ("CatEffects.swift", ["Theme.Cat.heart", "Theme.Cat.star", "Theme.Cat.sweat", "Theme.Cat.paper", "Theme.Cat.paperFold", "Theme.Cat.paperLabel"]),
            ("CatGreetingRenderer.swift", ["Theme.Greeting.badge", "Theme.Greeting.tintRGB", "Theme.Greeting.haloGoldRGB", "Theme.Greeting.haloBlueRGB", "Theme.Greeting.headerDimRGB"]),
            ("CatGreeting.swift", ["Theme.Greeting.streaks"]),
            ("MotionProfiles.swift", ["Theme.State.color", "Theme.State.glow"]),
            ("CatDevPanel.swift", ["Theme.Brand.pageRGB"]),
        ]
        var missing: [String] = []
        for (f, names) in uses { for n in names where !source(f).contains(n) { missing.append("\(f) does not use \(n)") } }
        CT.checkRows("six files, twenty-one uses of a token", missing)

        CT.section("the pill colours the Windows app copies: windows/src/core/pills.ts reads PillCatalog.swift, so a change here is deliberate")
        let catalog = source("PillCatalog.swift")
        func pill(_ id: String) -> String? {
            guard let r = catalog.range(of: "id: \"\(id)\"") else { return nil }
            let rest = catalog[r.upperBound...]
            guard let c = rest.range(of: "color: \"") else { return nil }
            return String(rest[c.upperBound...].prefix(7))
        }
        CT.check("Gemini CLI's pill is #8AB4F8 and Antigravity's is #E879F9 (the collars Windows draws for them)", [pill("agent_gemini"), pill("agent_antigravity")], ["#8AB4F8", "#E879F9"])
        CT.finish()
    }
}
```

- [ ] **Step 3: Run it to see it fail**

Run: `bash scripts/test-cat-theme.sh 2>&1 | grep -E "✗|failed"`
Expected: FAIL: three `✗` lines (`6 files: the cat's details, the greeting, the state colours and the glows`, `the header text, the tint, the halo's two ends and the panel's page colour`, `six files, twenty-one uses of a token`) and `3 test(s) failed.`

- [ ] **Step 4: Replace the sites**

Each is the same colour: `CatFace.swift` and `CatEffects.swift` for the cat's details, `CatGreetingRenderer.swift` for the greeting's, `CatGreeting.swift` for the streaks, `MotionProfiles.swift` builds `CatTables.color` and `CatTables.glow` from `Theme.State` (keyed by the state's raw value), and the Debug panel's page colour is `Theme.Brand.pageRGB` over 255. The halo's `lerp` runs between the two ends in the theme (`haloGold` to `haloBlue`).

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`**, find this text (it occurs exactly once):

```swift
        }
        .frame(width: Self.width, height: Self.rowH * Double(CatPresets.ids.count))
        .background(Color(red: 0.059, green: 0.063, blue: 0.071))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
```

and replace it with:

```swift
        }
        .frame(width: Self.width, height: Self.rowH * Double(CatPresets.ids.count))
        .background(Color(red: Theme.Brand.pageRGB[0] / 255, green: Theme.Brand.pageRGB[1] / 255, blue: Theme.Brand.pageRGB[2] / 255))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
```

**Edit `NotchBuddy/Sources/App/CatEffects.swift`**, find this text (it occurs exactly once):

```swift
            case .heart:
                cg.rotate(by: sin(6 * q.age) * 0.3)
                cg.fill(CatDraw.heart(sz * 1.6), CatDraw.color("#FF4D6D"))
            case .star:
                cg.rotate(by: q.rot + 2 * q.age)
                cg.fill(CatDraw.star(sz, sz * 0.45), CatDraw.color("#F7B32B"))
            case .spark:
                cg.rotate(by: q.rot)
```

and replace it with:

```swift
            case .heart:
                cg.rotate(by: sin(6 * q.age) * 0.3)
                cg.fill(CatDraw.heart(sz * 1.6), CatDraw.color(Theme.Cat.heart))
            case .star:
                cg.rotate(by: q.rot + 2 * q.age)
                cg.fill(CatDraw.star(sz, sz * 0.45), CatDraw.color(Theme.Cat.star))
            case .spark:
                cg.rotate(by: q.rot)
```

**Edit `NotchBuddy/Sources/App/CatEffects.swift`**, find this text (it occurs exactly once):

```swift
                d.addQuadCurve(to: CGPoint(x: 0, y: sz * 0.8), control: CGPoint(x: sz * 0.8, y: sz * 0.3))
                d.addQuadCurve(to: CGPoint(x: 0, y: -sz), control: CGPoint(x: -sz * 0.8, y: sz * 0.3))
                cg.fill(d, CatDraw.color("#7CC7FF"))
            case .dust:
                cg.fill(CatDraw.circle(0, 0, sz * (0.6 + k * 0.9)), CatDraw.rgb([225, 225, 232], 0.55))
```

and replace it with:

```swift
                d.addQuadCurve(to: CGPoint(x: 0, y: sz * 0.8), control: CGPoint(x: sz * 0.8, y: sz * 0.3))
                d.addQuadCurve(to: CGPoint(x: 0, y: -sz), control: CGPoint(x: -sz * 0.8, y: sz * 0.3))
                cg.fill(d, CatDraw.color(Theme.Cat.sweat))
            case .dust:
                cg.fill(CatDraw.circle(0, 0, sz * (0.6 + k * 0.9)), CatDraw.rgb([225, 225, 232], 0.55))
```

**Edit `NotchBuddy/Sources/App/CatEffects.swift`**, find this text (it occurs exactly once):

```swift
        cg.rotate(by: rot)
        let w = s * 0.78, h = s, f = s * 0.24
        cg.fill(CatDraw.poly([(-w / 2, -h / 2), (w / 2 - f, -h / 2), (w / 2, -h / 2 + f), (w / 2, h / 2), (-w / 2, h / 2)]), CatDraw.color("#F4F5F7"))
        cg.fill(CatDraw.poly([(w / 2 - f, -h / 2), (w / 2 - f, -h / 2 + f), (w / 2, -h / 2 + f)]), CatDraw.color("#C9CDD4"))
        cg.fill(CatDraw.roundRect(-w / 2 + s * 0.07, h * 0.06, w - s * 0.14, s * 0.24, s * 0.05), CatDraw.color("#3B9EFF"))
        CatDraw.text(cg, ext, x: 0, y: h * 0.06 + s * 0.125, size: s * 0.15, bold: true, color: CatDraw.white(1))
        cg.restoreGState()
```

and replace it with:

```swift
        cg.rotate(by: rot)
        let w = s * 0.78, h = s, f = s * 0.24
        cg.fill(CatDraw.poly([(-w / 2, -h / 2), (w / 2 - f, -h / 2), (w / 2, -h / 2 + f), (w / 2, h / 2), (-w / 2, h / 2)]), CatDraw.color(Theme.Cat.paper))
        cg.fill(CatDraw.poly([(w / 2 - f, -h / 2), (w / 2 - f, -h / 2 + f), (w / 2, -h / 2 + f)]), CatDraw.color(Theme.Cat.paperFold))
        cg.fill(CatDraw.roundRect(-w / 2 + s * 0.07, h * 0.06, w - s * 0.14, s * 0.24, s * 0.05), CatDraw.color(Theme.Cat.paperLabel))
        CatDraw.text(cg, ext, x: 0, y: h * 0.06 + s * 0.125, size: s * 0.15, bold: true, color: CatDraw.white(1))
        cg.restoreGState()
```

**Edit `NotchBuddy/Sources/App/CatFace.swift`**, find this text (it occurs exactly once):

```swift
        CatDraw.radial(cg, [(0, CatDraw.color(ir[0])), (1, CatDraw.color(ir[1]))], center: (0, 0), r0: 0, r1: w * 1.1)
        let off = G.pupilOffset(yaw: yaw, pitch: pitch, w: w, h: h)
        cg.fill(CatDraw.ellipse(off.x, off.y, w * (p.pupil0 + 0.5 * pupil), h * 1.1), CatDraw.color("#0E0B09"))
        if let ring = p.lidTint {
            cg.saveGState()
```

and replace it with:

```swift
        CatDraw.radial(cg, [(0, CatDraw.color(ir[0])), (1, CatDraw.color(ir[1]))], center: (0, 0), r0: 0, r1: w * 1.1)
        let off = G.pupilOffset(yaw: yaw, pitch: pitch, w: w, h: h)
        cg.fill(CatDraw.ellipse(off.x, off.y, w * (p.pupil0 + 0.5 * pupil), h * 1.1), CatDraw.color(Theme.Cat.pupil))
        if let ring = p.lidTint {
            cg.saveGState()
```

**Edit `NotchBuddy/Sources/App/CatFace.swift`**, find this text (it occurs exactly once):

```swift
            cg.stroke(sp, ink, width: 0.22 * w)
            cg.restoreGState()
        case .heart: cg.fill(CatDraw.heart(1.2 * w), CatDraw.color("#FF4D6D"))
        case .star:
            cg.saveGState()
            cg.rotate(by: T * 1.5 * sd)
            cg.fill(CatDraw.star(1.05 * w, 0.46 * w), CatDraw.color("#F7B32B"))
            cg.restoreGState()
        case .tired:
```

and replace it with:

```swift
            cg.stroke(sp, ink, width: 0.22 * w)
            cg.restoreGState()
        case .heart: cg.fill(CatDraw.heart(1.2 * w), CatDraw.color(Theme.Cat.heart))
        case .star:
            cg.saveGState()
            cg.rotate(by: T * 1.5 * sd)
            cg.fill(CatDraw.star(1.05 * w, 0.46 * w), CatDraw.color(Theme.Cat.star))
            cg.restoreGState()
        case .tired:
```

**Edit `NotchBuddy/Sources/App/CatFace.swift`**, find this text (it occurs exactly once):

```swift
        let sm = clamp(s.smile, -1, 1), sk = clamp(s.mskew, -1, 1), tg = clamp(s.tongue, 0, 1), rd = clamp(s.mround, 0, 1), wv = clamp(s.wavy, 0, 1)
        let y0 = my + 0.05 * R, cxm = nx + sk * 0.035 * R * nf, lw = 0.03 * R
        let line = CatDraw.color(p.mouthLine), tongueColor = CatDraw.color("#E8798C")
        if mo > 0.04 {
            let m = min(mo, 1.3)
```

and replace it with:

```swift
        let sm = clamp(s.smile, -1, 1), sk = clamp(s.mskew, -1, 1), tg = clamp(s.tongue, 0, 1), rd = clamp(s.mround, 0, 1), wv = clamp(s.wavy, 0, 1)
        let y0 = my + 0.05 * R, cxm = nx + sk * 0.035 * R * nf, lw = 0.03 * R
        let line = CatDraw.color(p.mouthLine), tongueColor = CatDraw.color(Theme.Cat.tongue)
        if mo > 0.04 {
            let m = min(mo, 1.3)
```

**Edit `NotchBuddy/Sources/App/CatFace.swift`**, find this text (it occurs exactly once):

```swift
            open.addCurve(to: CGPoint(x: cxm - w, y: top), control1: CGPoint(x: cxm + w, y: bot), control2: CGPoint(x: cxm - w, y: bot))
            open.closeSubpath()
            cg.fill(open, CatDraw.color("#3A1218"))
            cg.saveGState()
            cg.clip(open)
```

and replace it with:

```swift
            open.addCurve(to: CGPoint(x: cxm - w, y: top), control1: CGPoint(x: cxm + w, y: bot), control2: CGPoint(x: cxm - w, y: bot))
            open.closeSubpath()
            cg.fill(open, CatDraw.color(Theme.Cat.mouthInside))
            cg.saveGState()
            cg.clip(open)
```

**Edit `NotchBuddy/Sources/App/CatFace.swift`**, find this text (it occurs exactly once):

```swift
                for sd in [-1.0, 1.0] {
                    let fx = cxm + sd * w * 0.55, fy = top + L * 0.55
                    cg.fill(CatDraw.poly([(fx - 0.022 * R, fy), (fx + 0.022 * R, fy), (fx, fy + 0.055 * R)]), CatDraw.color("#FBF7F0"))
                }
            }
```

and replace it with:

```swift
                for sd in [-1.0, 1.0] {
                    let fx = cxm + sd * w * 0.55, fy = top + L * 0.55
                    cg.fill(CatDraw.poly([(fx - 0.022 * R, fy), (fx + 0.022 * R, fy), (fx, fy + 0.055 * R)]), CatDraw.color(Theme.Cat.teeth))
                }
            }
```

**Edit `NotchBuddy/Sources/App/CatGreeting.swift`**, find this text (it occurs exactly once):

```swift
    struct Streak: Equatable { var a: Double, sp: Double, len: Double, t0: Double, col: String }
    static let streaks: [Streak] = {
        let r = CatRNG(seed: 7), cols = ["#3B9EFF", "#F29B38", "#FF5A4E", "#2EC4A0", "#A78BFA"]
        return (0..<16).map { i in
            let a = Double(i) / 16 * CatMath.tau + (r.next() - 0.5) * 0.3
```

and replace it with:

```swift
    struct Streak: Equatable { var a: Double, sp: Double, len: Double, t0: Double, col: String }
    static let streaks: [Streak] = {
        let r = CatRNG(seed: 7), cols = Theme.Greeting.streaks
        return (0..<16).map { i in
            let a = Double(i) / 16 * CatMath.tau + (r.next() - 0.5) * 0.3
```

**Edit `NotchBuddy/Sources/App/CatGreetingRenderer.swift`**, find this text (it occurs exactly once):

```swift
        let st = Greeting.streakTime(t)
        if P.halo > 0 {
            let bl = P.haloBlue, c = [lerp(232, 59, bl), lerp(195, 158, bl), lerp(154, 255, bl)].map { $0.rounded() }
            for (rad, al) in [(D * 1.3, 0.18), (D * 2.1, 0.07)] {
                CatDraw.radial(cg, [(0, CatDraw.rgb(c, al * P.halo)), (1, CatDraw.rgb(c, 0))], center: (X, Y), r0: 0, r1: rad)
```

and replace it with:

```swift
        let st = Greeting.streakTime(t)
        if P.halo > 0 {
            let bl = P.haloBlue, c = (0..<3).map { lerp(Theme.Greeting.haloGoldRGB[$0], Theme.Greeting.haloBlueRGB[$0], bl).rounded() }
            for (rad, al) in [(D * 1.3, 0.18), (D * 2.1, 0.07)] {
                CatDraw.radial(cg, [(0, CatDraw.rgb(c, al * P.halo)), (1, CatDraw.rgb(c, 0))], center: (X, Y), r0: 0, r1: rad)
```

**Edit `NotchBuddy/Sources/App/CatGreetingRenderer.swift`**, find this text (it occurs exactly once):

```swift
        if P.header > 0.01 {
            CatDraw.text(cg, "NotchMeow", x: 20, y: 20, size: 13, bold: true, color: CatDraw.white(P.header), anchor: .left)
            CatDraw.text(cg, "Hi! \(p.label) is watching your agents.", x: 620, y: 20, size: 11.5, bold: false, color: CatDraw.rgb([141, 144, 152], P.header), anchor: .right)
        }
        // The cat: the greeting sets its pose directly each frame; its ears, mouth and idle habits are the engine's own.
```

and replace it with:

```swift
        if P.header > 0.01 {
            CatDraw.text(cg, "NotchMeow", x: 20, y: 20, size: 13, bold: true, color: CatDraw.white(P.header), anchor: .left)
            CatDraw.text(cg, "Hi! \(p.label) is watching your agents.", x: 620, y: 20, size: 11.5, bold: false, color: CatDraw.rgb(Theme.Greeting.headerDimRGB, P.header), anchor: .right)
        }
        // The cat: the greeting sets its pose directly each frame; its ears, mouth and idle habits are the engine's own.
```

**Edit `NotchBuddy/Sources/App/CatGreetingRenderer.swift`**, find this text (it occurs exactly once):

```swift
        e.eyeUntil = .infinity
        var look = e.look()
        look.badge = .dots; look.badgeColor = "#3BA0F5"; look.color = [127, 180, 234]
        let R = D / (2 * p.rx), rx = p.rx * R, ry = p.ry * R
        let on = P.wave >= 0, w = on ? P.wave * CatMath.tau * 4.2 : 0, wa = on ? seg(P.wave, 0, 0.12) * (1 - seg(P.wave, 0.9, 1.0)) : 0
```

and replace it with:

```swift
        e.eyeUntil = .infinity
        var look = e.look()
        look.badge = .dots; look.badgeColor = Theme.Greeting.badge; look.color = Theme.Greeting.tintRGB
        let R = D / (2 * p.rx), rx = p.rx * R, ry = p.ry * R
        let on = P.wave >= 0, w = on ? P.wave * CatMath.tau * 4.2 : 0, wa = on ? seg(P.wave, 0, 0.12) * (1 - seg(P.wave, 0.9, 1.0)) : 0
```

**Edit `NotchBuddy/Sources/App/CatGreetingRenderer.swift`**, find this text (it occurs exactly once):

```swift
            var options = CatDrawOptions(badge: false)
            if collarStyle != "off" { options.collar = CatCollarPaint(style: collarStyle, color: miniColors[i % miniColors.count]) }
            CatRenderer.draw(cg, CatLook(preset: preset, pose: pose, color: [127, 180, 234]), cx: 0, cy: 0, D: s.d / k, options)
            cg.restoreGState()
        }
```

and replace it with:

```swift
            var options = CatDrawOptions(badge: false)
            if collarStyle != "off" { options.collar = CatCollarPaint(style: collarStyle, color: miniColors[i % miniColors.count]) }
            CatRenderer.draw(cg, CatLook(preset: preset, pose: pose, color: Theme.Greeting.tintRGB), cx: 0, cy: 0, D: s.d / k, options)
            cg.restoreGState()
        }
```

**Edit `NotchBuddy/Sources/App/MotionProfiles.swift`**, find this text (it occurs exactly once):

```swift
enum CatTables {
    /// The state colour, which also tints the lower head and colours the badge.
    static let color: [CatState: String] = [
        .idle: "#E6E9EE", .working: "#3B9EFF", .thinking: "#8B5CF6", .searching: "#6366F1", .approval: "#F5A524", .question: "#22D3EE",
        .error: "#F4505E", .finished: "#34D399", .ratelimit: "#FB923C", .sleeping: "#94A3B8", .dizzy: "#F472B6",
    ]
    static let tint: [CatState: Double] = [
        .idle: 0, .working: 0.72, .thinking: 0.72, .searching: 0.72, .approval: 0.78, .question: 0.75,
        .error: 0.78, .finished: 0.35, .ratelimit: 0.72, .sleeping: 0.32, .dizzy: 0.7,
    ]
    static let glow: [CatState: String] = [
        .working: "#3B9EFF", .thinking: "#A78BFA", .searching: "#6366F1", .approval: "#F5A524", .error: "#F4505E", .finished: "#34D399", .ratelimit: "#F59E0B",
    ]
    static let badge: [CatState: CatBadge] = [
        .working: .dots, .thinking: .dots, .searching: .dots, .approval: .bang, .question: .question, .error: .dot, .finished: .dot, .ratelimit: .dot,
```

and replace it with:

```swift
enum CatTables {
    /// The state colour, which also tints the lower head and colours the badge.
    static let color: [CatState: String] = Dictionary(uniqueKeysWithValues: CatState.allCases.map { ($0, Theme.State.color[$0.rawValue] ?? "#FFFFFF") })
    static let tint: [CatState: Double] = [
        .idle: 0, .working: 0.72, .thinking: 0.72, .searching: 0.72, .approval: 0.78, .question: 0.75,
        .error: 0.78, .finished: 0.35, .ratelimit: 0.72, .sleeping: 0.32, .dizzy: 0.7,
    ]
    static let glow: [CatState: String] = Dictionary(uniqueKeysWithValues: Theme.State.glow.compactMap { name, hex in CatState(rawValue: name).map { ($0, hex) } })
    static let badge: [CatState: CatBadge] = [
        .working: .dots, .thinking: .dots, .searching: .dots, .approval: .bang, .question: .question, .error: .dot, .finished: .dot, .ratelimit: .dot,
```

- [ ] **Step 5: Every script that compiles one of these files compiles the theme too**

The generated file is Foundation-free Swift with no imports, so it is one more file in each `swiftc` list, next to `CatMath.swift`.

**Edit `scripts/gen-icons.sh`**, find this text (it occurs exactly once):

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -O \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
```

and replace it with:

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -O \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
```

**Edit `scripts/render-cat-panel.sh`**, find this text (it occurs exactly once):

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -D DEBUG \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/AppLog.swift $APP/CatFrameMeter.swift $APP/CatFrameReadout.swift $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
```

and replace it with:

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -D DEBUG \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/AppLog.swift $APP/CatFrameMeter.swift $APP/CatFrameReadout.swift $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
```

**Edit `scripts/render-cat-settings.sh`**, find this text (it occurs exactly once):

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatSettings.swift $APP/CatSettingsStore.swift $APP/CatSettingsView.swift \
```

and replace it with:

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatSettings.swift $APP/CatSettingsStore.swift $APP/CatSettingsView.swift \
```

**Edit `scripts/render-cats.sh`**, find this text (it occurs exactly once):

```bash
# RENDER_CATS_OPT=1 builds with -O (the frame-time number in a Release build); the default is a Debug build.
swiftc -swift-version 6 ${RENDER_CATS_OPT:+-O} \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
```

and replace it with:

```bash
# RENDER_CATS_OPT=1 builds with -O (the frame-time number in a Release build); the default is a Debug build.
swiftc -swift-version 6 ${RENDER_CATS_OPT:+-O} \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
```

**Edit `scripts/test-cat-devpanel.sh`**, find this text (it occurs exactly once):

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -D DEBUG \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatFileRule.swift $APP/CatDevModel.swift \
    $APP/AI/Core/Attachments.swift $APP/AI/Core/AICatalog.swift $APP/AI/Core/ModelProvider.swift $APP/AI/Core/ContextBudget.swift \
```

and replace it with:

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -D DEBUG \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatFileRule.swift $APP/CatDevModel.swift \
    $APP/AI/Core/Attachments.swift $APP/AI/Core/AICatalog.swift $APP/AI/Core/ModelProvider.swift $APP/AI/Core/ContextBudget.swift \
```

**Edit `scripts/test-cat-effects.sh`**, find this text (it occurs exactly once):

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    tests/CatTestSupport.swift tests/CatBitmapSupport.swift tests/CatEffectsTests.swift \
    -o "$TEST_DIR/cat-effects-tests"
```

and replace it with:

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    tests/CatTestSupport.swift tests/CatBitmapSupport.swift tests/CatEffectsTests.swift \
    -o "$TEST_DIR/cat-effects-tests"
```

**Edit `scripts/test-cat-engine.sh`**, find this text (it occurs exactly once):

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift \
    tests/CatTestSupport.swift tests/CatEngineSupport.swift tests/CatEngineTests.swift \
```

and replace it with:

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift \
    tests/CatTestSupport.swift tests/CatEngineSupport.swift tests/CatEngineTests.swift \
```

**Edit `scripts/test-cat-greeting.sh`**, find this text (it occurs exactly once):

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatGreeting.swift $APP/IslandScreenGeometry.swift \
    tests/CatTestSupport.swift tests/CatGreetingTests.swift \
```

and replace it with:

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatGreeting.swift $APP/IslandScreenGeometry.swift \
    tests/CatTestSupport.swift tests/CatGreetingTests.swift \
```

**Edit `scripts/test-cat-renderer.sh`**, find this text (it occurs exactly once):

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift tests/CatEngineSupport.swift \
```

and replace it with:

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift tests/CatEngineSupport.swift \
```

**Edit `scripts/test-cat-settings-store.sh`**, find this text (it occurs exactly once):

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatSettings.swift $APP/CatSettingsStore.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/CatSettingsStoreTests.swift \
```

and replace it with:

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatSettings.swift $APP/CatSettingsStore.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/CatSettingsStoreTests.swift \
```

**Edit `scripts/test-cat-upload.sh`**, find this text (it occurs exactly once):

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/UploadSequenceEngine.swift $APP/CatFileRule.swift $APP/UploadCatDriver.swift \
    $APP/AI/Core/Attachments.swift $APP/AI/Core/AICatalog.swift $APP/AI/Core/ModelProvider.swift $APP/AI/Core/ContextBudget.swift \
```

and replace it with:

```bash
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/UploadSequenceEngine.swift $APP/CatFileRule.swift $APP/UploadCatDriver.swift \
    $APP/AI/Core/Attachments.swift $APP/AI/Core/AICatalog.swift $APP/AI/Core/ModelProvider.swift $APP/AI/Core/ContextBudget.swift \
```

- [ ] **Step 6: Run the pins and every cat test**

Run: `bash scripts/test-cat-theme.sh 2>&1 | grep -E "✗|passed|failed"; for f in scripts/test-cat-*.sh; do printf '%-42s' "$f"; bash "$f" 2>&1 | tail -1; done | grep -v "All tests passed"`
Expected: `All tests passed.`, then only the contract's line `scripts/test-cat-contract.sh            ✓ two generator runs write identical bytes` (every other program ends `All tests passed.`; the theme and fixture checks of the engine and the greeting replay unchanged).

- [ ] **Step 7: Draw the sheets again and compare them byte for byte**

Run: `d="${TMPDIR:-/tmp}/a-mac-theme"; bash scripts/render-cats.sh --out "$d/after/ladder.png" && bash scripts/render-cats.sh --states --cats shrimpy,momo --out "$d/after/states.png" && bash scripts/render-cats.sh --emotes --cats shrimpy,momo --out "$d/after/emotes.png" && bash scripts/render-cats.sh --mouths --cats shrimpy,momo --out "$d/after/mouths.png" && bash scripts/render-cats.sh --catch --cats shrimpy --out "$d/after/catch.png" && bash scripts/render-cats.sh --greeting --cats shrimpy --out "$d/after/greeting.png"; for f in "$d"/before/*.png; do cmp "$f" "$d/after/$(basename "$f")" && echo "identical: $(basename "$f")"; done`
Expected: six `wrote …` lines, then six lines, `identical: catch.png`, `identical: emotes.png`, `identical: greeting.png`, `identical: ladder.png`, `identical: mouths.png`, `identical: states.png`. **No pixel changed.** A `cmp` message instead means a value differs from its token: stop and ask.

- [ ] **Step 8: The app and menu bar icons still regenerate identically, and the app builds**

`gen-icons.sh` draws the icons with the same renderer, so it also compiles the theme now.

Run: `d="${TMPDIR:-/tmp}/a-mac-theme"; bash scripts/gen-icons.sh "$d/icons" >/dev/null && n=0; bad=0; for f in $(cd "$d/icons" && find . -type f); do n=$((n+1)); cmp -s "$d/icons/$f" "$f" || { bad=$((bad+1)); echo "DIFFERS $f"; }; done; echo "$n icon files compared, $bad differ"`
Expected: `18 icon files compared, 0 differ`.

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Only if the owner said yes at checkpoint 2: the island's glow**

The island draws the glow behind the cat from the same seven colours (`GLOW` in the contract), in existing island code. First prove they are the same values:

```bash
python3 - <<'PY'
import re
src = open('NotchBuddy/Sources/App/IslandRootView.swift').read()
theme = open('NotchBuddy/Sources/App/Theme.generated.swift').read()
old = dict(re.findall(r'case \.(\w+):\s+return Color\(hex: "(#[0-9A-F]{6})"\)', src))
glow = dict(re.findall(r'"(\w+)": "(#[0-9A-F]{6})"', re.search(r'static let glow: \[String: String\] = \[(.*?)\]', theme).group(1)))
assert old == glow, (old, glow)
print("the island glow's", len(old), "colours are Theme.State.glow")
PY
```

Expected: `the island glow's 7 colours are Theme.State.glow`. If it asserts, stop and ask. Then swap them (a state with no glow stays white):

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
    }

    private func botGlowColor(_ s: BotState) -> Color {
        switch s {
        case .working:   return Color(hex: "#3B9EFF")
        case .thinking:  return Color(hex: "#A78BFA")
        case .searching: return Color(hex: "#6366F1")
        case .approval:  return Color(hex: "#F5A524")
        case .error:     return Color(hex: "#F4505E")
        case .finished:  return Color(hex: "#34D399")
        case .ratelimit: return Color(hex: "#F59E0B")
        default:         return Color.white
        }
    }

```

and replace it with:

```swift
    }

    /// The glow behind the cat: the state's glow colour (`Theme.State.glow`, the colours the contract pins), white for a state with none.
    private func botGlowColor(_ s: BotState) -> Color {
        Theme.State.glow[s.rawValue].map { Color(hex: $0) } ?? Color.white
    }

```

**Edit `tests/CatThemeTests.swift`**, find this text (it occurs exactly once):

```swift

        CT.section("no hex literal that is a theme colour is left in the drawing code")
        let files = ["CatFace.swift", "CatEffects.swift", "CatGreeting.swift", "CatGreetingRenderer.swift", "MotionProfiles.swift", "CatDevPanel.swift"]
        var leftovers: [String] = []
        for f in files { for h in hexes(source(f)).intersection(theme).sorted() { leftovers.append("\(f) has \(h)") } }
```

and replace it with:

```swift

        CT.section("no hex literal that is a theme colour is left in the drawing code")
        let files = ["CatFace.swift", "CatEffects.swift", "CatGreeting.swift", "CatGreetingRenderer.swift", "MotionProfiles.swift", "CatDevPanel.swift", "IslandRootView.swift"]
        var leftovers: [String] = []
        for f in files { for h in hexes(source(f)).intersection(theme).sorted() { leftovers.append("\(f) has \(h)") } }
```

**Edit `tests/CatThemeTests.swift`**, find this text (it occurs exactly once):

```swift
            ("MotionProfiles.swift", ["Theme.State.color", "Theme.State.glow"]),
            ("CatDevPanel.swift", ["Theme.Brand.pageRGB"]),
        ]
        var missing: [String] = []
        for (f, names) in uses { for n in names where !source(f).contains(n) { missing.append("\(f) does not use \(n)") } }
        CT.checkRows("six files, twenty-one uses of a token", missing)

        CT.section("the pill colours the Windows app copies: windows/src/core/pills.ts reads PillCatalog.swift, so a change here is deliberate")
```

and replace it with:

```swift
            ("MotionProfiles.swift", ["Theme.State.color", "Theme.State.glow"]),
            ("CatDevPanel.swift", ["Theme.Brand.pageRGB"]),
            ("IslandRootView.swift", ["Theme.State.glow"]),   // only with the owner's OK: same values, no change of look
        ]
        var missing: [String] = []
        for (f, names) in uses { for n in names where !source(f).contains(n) { missing.append("\(f) does not use \(n)") } }
        CT.checkRows("seven files, twenty-two uses of a token", missing)

        CT.section("the pill colours the Windows app copies: windows/src/core/pills.ts reads PillCatalog.swift, so a change here is deliberate")
```

Run: `bash scripts/test-cat-theme.sh 2>&1 | grep -E "✗|passed|failed"; xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `All tests passed.` (seven files, twenty-two uses of a token) and `** BUILD SUCCEEDED **`. If the owner said no, skip this step and leave `IslandRootView.swift` as it is.

- [ ] **Step 10: Commit**

```bash
git add NotchBuddy/Sources/App/CatFace.swift NotchBuddy/Sources/App/CatEffects.swift NotchBuddy/Sources/App/CatGreetingRenderer.swift NotchBuddy/Sources/App/CatGreeting.swift NotchBuddy/Sources/App/MotionProfiles.swift NotchBuddy/Sources/App/CatDevPanel.swift tests/CatThemeTests.swift scripts/test-cat-theme.sh scripts/gen-icons.sh scripts/render-cat-panel.sh scripts/render-cat-settings.sh scripts/render-cats.sh scripts/test-cat-devpanel.sh scripts/test-cat-effects.sh scripts/test-cat-engine.sh scripts/test-cat-greeting.sh scripts/test-cat-renderer.sh scripts/test-cat-settings-store.sh scripts/test-cat-upload.sh
git add NotchBuddy/Sources/App/IslandRootView.swift   # only if the owner said yes to the island's glow
git commit -m "refactor(cat): the cat's details, the greeting and the state colours come from Theme.generated.swift

Every Mac site of the theme inventory is a token now, with the same value: six contact sheets drawn before and after are
byte for byte identical, and the app and menu bar icons regenerate identically. A source-pin program fails the day one is
typed in again.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Dead code, the reviews' leftovers, the old names and the guard that keeps them out (stage 7)

**Agent:** `nm-implementer-light`. The edits are given in full; the guard script, the tests and the builds prove them.

**Files:**
- Create: `scripts/check-no-leftovers.sh`
- Modify: `NotchBuddy/Sources/App/IslandTypes.swift` (`AgentTask.emote` and `miniEye`), `BotCanvasView.swift` (the permanent emote, the eye override and the `.botGreet` observer), `CatEngine+App.swift` (`setPermanentEmote` and the `EyeShape` alias), `CatEngine.swift` (`holdEye`; then the emote guard, the chew's beats and the gag's number), `IslandRootView.swift` (`greetNotif`), `IslandWindowController.swift` (the `.botMorphTo` posts and names, `.botGreet`, two comments that say `BotEngine`), `FileDropView.swift` (a `.botMorphTo` post), `AppState.swift` (a comment), `AI/AIService.swift` (`.botReject`), `UploadSequenceEngine.swift` (`morph`, `cup`, `mouth`, `mouthRect` and `suck`; then the gag's and the hairball's numbers), `CatRules.swift` (`gagMs`, `hairballMs`), `MotionProfiles.swift` (`CatTables.emoteNames`), `CatDevModel.swift` (it offers `emoteNames`), `tests/CatEngineTests.swift`, `tests/UploadCatDriverTests.swift`, `tests/CatDevModelTests.swift`

**Interfaces:**
- Produces `scripts/check-no-leftovers.sh`: five checks over `NotchBuddy/`, `scripts/` and `tests/`: no `mochi` in any case, no `BotEngine`, no `setPermanentEmote`/`miniEye`/`holdEye`/`EyeShape`, no `USEyeShape`/`USMouthRect`/`morph`/`botMorphTo`/`mailbox`, no `botReject`/`botGreet`/`greetNotif`. It prints a `✓` or a `✗` line each and exits 1 on a `✗`. It is the Mac's twin of the Windows plan's `names.test.mjs` and `deadcode.test.mjs`.
- Produces `CatRules.gagMs` (120) and `CatRules.hairballMs` (2400), `CatTables.emoteNames` (the ten emotes, in the panel's order).
- What goes, and what stays. **Goes:** permanent emotes and `AgentTask.emote`; `AgentTask.miniEye`, `holdEye` and the `EyeShape` alias; the drop view's `morph`, `cup`/`USEyeShape`, `mouth` (its spring and the `MOUTH_*` constants), `mouthRect`/`USMouthRect` and `suck`; the `.botMorphTo` posts and name (nothing observes it); `.botReject` (nothing posts or observes it); `.botGreet` and its two observers (nothing posts it). **Stays:** `engine.greet()` and the `hello` emote (the fixtures pin them), `BotEmote` and `.triggerEmote`, mail sent's wink, `AppState.fileDragOver` (the drop zone's hover glow still reads it), and a refused 4 GB file still being copied to the inbox (behaviour, as today).
- **The reviews' leftovers, checked against the Mac code** (the owner's manual-check lists of stages 1 to 4 and the Windows plan's Task 16, item by item). **Applies, fixed here:** (1) *an unknown emote still logs*: `emote("nope")` changed nothing but wrote `emote:nope` in the engine's notes; it now returns first; (2) *a one-shot lick can fire inside the hairball tail*: two drops close together (a taken file, then a refused one while the cat still chews) left the chew's lick and sparks queued, so the cat licked its lips while it was gagging; a refusal now clears them; (3) *the catch's numbers live in two places*: the drop view's refusal note waits on `COUGH_LEAD_S` and `HAIRBALL_S`, which repeated the engine's 120 ms and 2.4 s; both now read `CatRules`. **Does not apply to the Mac:** *a very late refusal snaps the timeline back* (the Mac decides a refusal at the drop, so none arrives late); *`Greeting` reads `performance.now()`* (the Mac's greeting is a pure timeline `CatGreeting` driven by the view's clock); *unused `UploadFrame` and `eIn`* (the Mac's `usEIn` is used by the progress curve); *the dev readout says twelve small cats and draws eleven* (the Mac's bench draws twelve small cats and the Debug panel's readout only reports the drawing time). **Left as it is on purpose:** a slow reader can hear `approve` and then `annoyed` (plan-mandated at stage 4); and *the whisker taper*, which the Mac strokes in 8 segments where the prototype and the Windows app use 16: the dry run measured that 16 redraws 11 of the 18 shipped icon files (the Windows ones too, since `gen-icons.sh` draws them with this renderer), and icons are another sub-project's, so the taper stays and Open question 14 asks.
- **Mochi.** The sweep finds nothing to rename in the Mac code: stages 1 to 4 replaced `BotEngine.swift` and its `mochi` names, and a case-insensitive search of `NotchBuddy/`, `scripts/`, `tests/` and `.github/` finds none (the cat coat `mocha` is another word). The two `BotEngine` comments in `IslandWindowController.swift` are the last old name and change here. The guard keeps it true. Shared files outside the Mac code that still say Mochi (`docs/SPEC.md`, `CHANGELOG.md`, `LICENSE-ASSETS.md`, the issue template) are not code: see Open question 8.

- [ ] **Step 1: Write the guard and see it fail**

**Create `scripts/check-no-leftovers.sh`**:

```bash
#!/usr/bin/env bash
# Stage 7 of sub-project A, kept true: the old character's names and the cat's dead code stay out of the Mac code, its scripts and its tests.
#   - no "mochi" in any form (Done means: no mochi/Mochi identifiers remain; the cat coat "mocha" is another word);
#   - no BotEngine (the engine the cats replaced);
#   - none of the dead names the sweep removed: permanent emotes, miniEye and the eye alias, the morph and cup eyes, the mailbox morph, the mouth rect and
#     the suction, and the notifications nothing posts or observes (.botMorphTo, .botReject, .botGreet).
# Historical plans, specs and the git history keep their words; this reads only code, scripts and tests.
# Usage: bash scripts/check-no-leftovers.sh
set -euo pipefail
cd "$(dirname "$0")/.."
SELF="check-no-leftovers.sh"
failed=0
check() {   # check <description> <grep -E pattern> [extra grep flags]
    local what="$1" pattern="$2"; shift 2
    local hits
    hits="$(grep -rInE "$@" --include='*.swift' --include='*.sh' --include='*.yml' --include='*.plist' --include='*.json' --exclude="$SELF" \
        --exclude-dir=build --exclude-dir=fixtures -- "$pattern" NotchBuddy scripts tests 2>/dev/null || true)"
    if [ -n "$hits" ]; then
        echo "✗ $what"
        echo "$hits" | head -8 | sed 's/^/    /'
        failed=1
    else
        echo "✓ $what"
    fi
}
check 'no "mochi" in the Mac code, scripts and tests' 'mochi' -i
check "no BotEngine: the cats replaced it" 'BotEngine'
check "no permanent emote, miniEye or eye alias" 'setPermanentEmote|miniEye|holdEye|\bEyeShape\b'
check "no mailbox morph, cup eye, mouth rect or suction in the drop view" 'USEyeShape|USMouthRect|\bmorph\b|botMorphTo|mailbox'
check "no notification that nothing posts or observes" 'botReject|botGreet|greetNotif'
exit "$failed"
```

Run: `bash scripts/check-no-leftovers.sh; echo "exit $?"`
Expected: FAIL: `✓ no "mochi" in the Mac code, scripts and tests`, then four `✗` lines (`no BotEngine: the cats replaced it`, `no permanent emote, miniEye or eye alias`, `no mailbox morph, cup eye, mouth rect or suction in the drop view`, `no notification that nothing posts or observes`), each with up to eight hits, and `exit 1`.

- [ ] **Step 2: Remove the dead code**

The drop view's frame loses the fields nothing reads (`UploadCanvasView` and `UploadCatDriver` use `x`, `y`, `d`, `sx`, `sy`, `tilt`, `hop`, `lookX`, `lookY`, `fileVisible`, `zoneAlpha` and the rest of the frame, which stay), and the simulation loses the mouth spring that only fed them. The cat in the drop view is the engine's, so none of this changes what the cat does.

**Edit `NotchBuddy/Sources/App/AI/AIService.swift`**, find this text (it occurs exactly once):

```swift
}

extension Notification.Name {
    /// A dropped file the AI can't read (object: its extension). The cat's hairball hooks here.
    static let botReject = Notification.Name("notchMeow.botReject")
}

```

and replace it with:

```swift
}


```

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
    var uploadDuration: Double = 2.4

    // File drag-over state (mailbox morph glow + mouth spring)
    @Published var fileDragOver: Bool = false

```

and replace it with:

```swift
    var uploadDuration: Double = 2.4

    // File drag-over state (the drop zone's hover glow)
    @Published var fileDragOver: Bool = false

```

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**, find this text (it occurs exactly once):

```swift
            engine.gulp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in
            engine.greet()
        }
        .onAppear {
            engine.onDizzy = { NotificationCenter.default.post(name: .botDizzy, object: nil) }
```

and replace it with:

```swift
            engine.gulp()
        }
        .onAppear {
            engine.onDizzy = { NotificationCenter.default.post(name: .botDizzy, object: nil) }
```

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`**, find this text (it occurs exactly once):

```swift
        .onAppear {
            engine.setState(task.state.shown(asleep: AppState.shared.catAsleep), force: true)
            if let emote = task.emote {
                engine.setPermanentEmote(emote)
            }
            // Direct eye override takes priority (e.g. .wide eyes for Research)
            if let eye = task.miniEye {
                engine.holdEye(eye)
            }
        }
    }
```

and replace it with:

```swift
        .onAppear {
            engine.setState(task.state.shown(asleep: AppState.shared.catAsleep), force: true)
        }
    }
```

**Edit `NotchBuddy/Sources/App/CatEngine+App.swift`**, find this text (it occurs exactly once):

```swift
    /// An emote asked for by the app (a hover, a drop, a finished chat). The triggers are unchanged from before the cats.
    func triggerEmote(_ e: BotEmote) { emote(e.rawValue) }

    /// A mini cat with a permanent emote: it plays the emote once. (Nothing sets one today; stage 7 removes it with `AgentTask.emote`.)
    func setPermanentEmote(_ e: BotEmote?) { if let e { emote(e.rawValue) } }
}

/// The old name of an eye shape, which `AgentTask.miniEye` still uses (stage 7 removes it).
typealias EyeShape = CatEye

```

and replace it with:

```swift
    /// An emote asked for by the app (a hover, a drop, a finished chat). The triggers are unchanged from before the cats.
    func triggerEmote(_ e: BotEmote) { emote(e.rawValue) }
}

```

**Edit `NotchBuddy/Sources/App/CatEngine.swift`**, find this text (it occurs exactly once):

```swift
    }

    /// Holds an eye shape until something else sets one (a mini cat with a fixed expression).
    func holdEye(_ shape: CatEye) { eyeOv = shape; eyeUntil = .infinity }

    /// A file the cat cannot take: it is caught, gagged on and coughed back up as a hairball wrapped around the file.
    func catchReject(_ ext: String) {
```

and replace it with:

```swift
    }

    /// A file the cat cannot take: it is caught, gagged on and coughed back up as a hairball wrapped around the file.
    func catchReject(_ ext: String) {
```

**Edit `NotchBuddy/Sources/App/FileDropView.swift`**, find this text (it occurs exactly once):

```swift
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        }
        NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(0))

        state.uploadDuration = dur
```

and replace it with:

```swift
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        }

        state.uploadDuration = dur
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
    // topRadius > 0 → convex expanded corners; < 0 → concave ear cutouts
    @State private var islandTopRadius: CGFloat = 0
    @State private var greetNotif: Bool = false

    private let openSpring = Animation.spring(response: 0.5, dampingFraction: 0.72)
```

and replace it with:

```swift
    // topRadius > 0 → convex expanded corners; < 0 → concave ear cutouts
    @State private var islandTopRadius: CGFloat = 0

    private let openSpring = Animation.spring(response: 0.5, dampingFraction: 0.72)
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift
            cornerRadius     = state.mode == .expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner
            islandTopRadius  = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in
            greetNotif.toggle()
        }
    }
```

and replace it with:

```swift
            cornerRadius     = state.mode == .expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner
            islandTopRadius  = 0
        }
    }
```

**Edit `NotchBuddy/Sources/App/IslandTypes.swift`**, find this text (it occurs exactly once):

```swift
    var source: AgentSource
    var isIntegration: Bool = false  // true for persistent integration pills
    var emote: BotEmote? = nil
    var miniEye: EyeShape? = nil
    var pillBadge: PillBadge? = nil  // alert badge shown on pill when not focused
    var sessionCwd: String?  = nil  // last known working directory (Claude Code sessions)
```

and replace it with:

```swift
    var source: AgentSource
    var isIntegration: Bool = false  // true for persistent integration pills
    var pillBadge: PillBadge? = nil  // alert badge shown on pill when not focused
    var sessionCwd: String?  = nil  // last known working directory (Claude Code sessions)
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, find this text (it occurs exactly once):

```swift
                UploadSequenceEngine.shared.enterZone(x: iLoc.x, y: iLoc.y)
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.upload)
                NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(1))
            }
        }
```

and replace it with:

```swift
                UploadSequenceEngine.shared.enterZone(x: iLoc.x, y: iLoc.y)
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.upload)
            }
        }
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, find this text (it occurs exactly once):

```swift
                AppState.shared.fileDragOver = false
                // Do NOT collapse — drag session still active; island stays open.
                NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(0))
                UploadSequenceEngine.shared.exitZone()
            }
```

and replace it with:

```swift
                AppState.shared.fileDragOver = false
                // Do NOT collapse — drag session still active; island stays open.
                UploadSequenceEngine.shared.exitZone()
            }
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, find this text (it occurs exactly once):

```swift
        }

        // .botDizzy — posted by BotEngine.slap() on 3rd hit; show confused view + recover after 3.3s
        NotificationCenter.default.addObserver(forName: .botDizzy, object: nil, queue: .main) { [weak self] _ in
            self?.handleDizzy()
```

and replace it with:

```swift
        }

        // .botDizzy — posted by CatEngine.slap() on 3rd hit; show confused view + recover after 3.3s
        NotificationCenter.default.addObserver(forName: .botDizzy, object: nil, queue: .main) { [weak self] _ in
            self?.handleDizzy()
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, find this text (it occurs exactly once):

```swift
    }

    // MARK: - Dizzy recovery (triggered by BotEngine.slap via .botDizzy)

    private func handleDizzy() {
```

and replace it with:

```swift
    }

    // MARK: - Dizzy recovery (triggered by CatEngine.slap via .botDizzy)

    private func handleDizzy() {
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, find this text (it occurs exactly once):

```swift
    static let triggerSlap      = Notification.Name("notchBuddy.triggerSlap")
    static let botDizzy         = Notification.Name("notchBuddy.botDizzy")
    static let botGreet         = Notification.Name("notchBuddy.botGreet")
    static let botBlink         = Notification.Name("notchBuddy.botBlink")
    static let botSetTgEs       = Notification.Name("notchBuddy.botSetTgEs")
    static let botGulp          = Notification.Name("notchBuddy.botGulp")
    static let botMorphTo       = Notification.Name("notchBuddy.botMorphTo")
    static let islandAction     = Notification.Name("notchBuddy.islandAction")
    static let islandCollapse   = Notification.Name("notchBuddy.islandCollapse")
```

and replace it with:

```swift
    static let triggerSlap      = Notification.Name("notchBuddy.triggerSlap")
    static let botDizzy         = Notification.Name("notchBuddy.botDizzy")
    static let botBlink         = Notification.Name("notchBuddy.botBlink")
    static let botSetTgEs       = Notification.Name("notchBuddy.botSetTgEs")
    static let botGulp          = Notification.Name("notchBuddy.botGulp")
    static let islandAction     = Notification.Name("notchBuddy.islandAction")
    static let islandCollapse   = Notification.Name("notchBuddy.islandCollapse")
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`**, find this text (it occurs exactly once):

```swift
    static let LOCK_IN:  Double = 60
    static let LOCK_OUT: Double = 90
    static let MOUTH_AJAR: Double = 0.20
    static let MOUTH_OPEN: Double = 0.42
    static let MOUTH_MAX:  Double = 0.50
    // Phase timestamps (t_ref, drop = 1.95)
    static let T_DROP:       Double = 1.95
    static let T_SUCK_START: Double = 2.03
    static let T_SUCK_END:   Double = 2.33
    static let T_CLOSE_END:  Double = 2.42
    static let T_CHEW1:      Double = 2.60
    static let T_CHEW_END:   Double = 2.88
```

and replace it with:

```swift
    static let LOCK_IN:  Double = 60
    static let LOCK_OUT: Double = 90
    // Phase timestamps (t_ref, drop = 1.95)
    static let T_DROP:       Double = 1.95
    static let T_SUCK_START: Double = 2.03
    static let T_SUCK_END:   Double = 2.33
    static let T_CHEW1:      Double = 2.60
    static let T_CHEW_END:   Double = 2.88
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`**, find this text (it occurs exactly once):

```swift
    var by:      USSpring = USSpring(v: USC.REST_Y)
    var tilt:    Double = 0
    var mouth:   USSpring = USSpring(v: 0)
    var locked:  Bool = false
    var lockAt:  Double = -9
```

and replace it with:

```swift
    var by:      USSpring = USSpring(v: USC.REST_Y)
    var tilt:    Double = 0
    var locked:  Bool = false
    var lockAt:  Double = -9
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`**, find this text (it occurs exactly once):

```swift
// ============================================================

enum USEyeShape { case pill, cup, content }

struct USMouthRect { var x,y,w,h: Double }

struct USFrame {
    var t: Double = 0
    var cursorX: Double = 600; var cursorY: Double = 280
    var morph: Double = 0
    var x: Double = USC.REST_X; var y: Double = USC.REST_Y; var d: Double = USC.D_BOX
    var sx: Double = 1; var sy: Double = 1; var tilt: Double = 0; var hop: Double = 0
    var mouth: Double = 0
    var mouthRect = USMouthRect(x:0,y:0,w:0,h:0)
    var eye: USEyeShape = .pill
    var lookX: Double = 0; var lookY: Double = 0
    var fileVisible: Bool = true; var suck: Double = 0
    var zoneOver:    Bool   = false
    /// The file has been dropped (the post-drop timeline is running), as opposed to still being dragged over the island. `t` alone cannot say,
```

and replace it with:

```swift
// ============================================================

struct USFrame {
    var t: Double = 0
    var cursorX: Double = 600; var cursorY: Double = 280
    var x: Double = USC.REST_X; var y: Double = USC.REST_Y; var d: Double = USC.D_BOX
    var sx: Double = 1; var sy: Double = 1; var tilt: Double = 0; var hop: Double = 0
    var lookX: Double = 0; var lookY: Double = 0
    var fileVisible: Bool = true
    var zoneOver:    Bool   = false
    /// The file has been dropped (the post-drop timeline is running), as opposed to still being dragged over the island. `t` alone cannot say,
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`**, find this text (it occurs exactly once):

```swift
        sim.tilt = usLerp(sim.tilt, tiltTarget, 1 - pow(0.0005, dt))

        // Mouth — post-drop close only after drop has actually happened
        let t = sim.t
        if !isDragging && t >= USC.T_SUCK_END {
            sim.mouth.v = max(0, usLerp(USC.MOUTH_MAX, 0, usEIn(usSeg(t, USC.T_SUCK_END, USC.T_CLOSE_END))))
        } else {
            var mt = 0.0
            if sim.entered >= 0 {
                mt = (sim.locked || !isDragging) ? USC.MOUTH_OPEN : USC.MOUTH_AJAR
            }
            if !isDragging && t < USC.T_SUCK_END { mt = USC.MOUTH_MAX }
            sim.mouth.step(target: mt, response:0.25, damping:0.60, dt:dt)
            if sim.mouth.v < 0 { sim.mouth.v = 0 }
        }
    }

```

and replace it with:

```swift
        sim.tilt = usLerp(sim.tilt, tiltTarget, 1 - pow(0.0005, dt))

    }

```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`**, find this text (it occurs exactly once):

```swift
        f.lookY = looking ? max(-1, min(1, ((cursorY + 10) - f.y) / 150)) : 0
        f.fileVisible = looking
        f.suck = usSeg(t, USC.T_SUCK_START, USC.T_SUCK_END)
        f.zoneOver = false
        f.zoneAlpha = 1 - usSeg(t, USC.T_CHEW_END, USC.T_CHEW_END + 0.20)
```

and replace it with:

```swift
        f.lookY = looking ? max(-1, min(1, ((cursorY + 10) - f.y) / 150)) : 0
        f.fileVisible = looking
        f.zoneOver = false
        f.zoneAlpha = 1 - usSeg(t, USC.T_CHEW_END, USC.T_CHEW_END + 0.20)
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`**, find this text (it occurs exactly once):

```swift
        f.growEnd   = growEnd

        let entered    = sim.entered >= 0 ? sim.entered : 1e9
        let isDragging = (dropWallTime == nil)
        if refused && !isDragging { return computeRefusedFrame(t: t) }
```

and replace it with:

```swift
        f.growEnd   = growEnd

        let isDragging = (dropWallTime == nil)
        if refused && !isDragging { return computeRefusedFrame(t: t) }
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`**, find this text (it occurs exactly once):

```swift
        // so long hovers don't accidentally trigger post-drop visuals.
        let pt = isDragging ? min(t, USC.T_DROP - USC.DT) : t

        // Morph: 0→1 (entry), 1→0 (shrink to ball), 0→1 (grow back to box at choose)
        var morph: Double
        if pt < USC.T_CHEW_END {
            morph = usEBack(usSeg(pt, entered, entered + 0.38))
        } else if pt < growStart {
            morph = 1 - usEOut(usSeg(pt, USC.T_CHEW_END, USC.T_SHRINK_END))
        } else {
            morph = usEBack(usSeg(pt, growStart, growEnd))
        }
        morph = max(0, min(morph, 1.08))
        f.morph = morph

        // Position / diameter
```

and replace it with:

```swift
        // so long hovers don't accidentally trigger post-drop visuals.
        let pt = isDragging ? min(t, USC.T_DROP - USC.DT) : t

        // Position / diameter
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`**, find this text (it occurs exactly once):

```swift
            ? -5 * sin(.pi * usSeg(pt, sim.lockAt, sim.lockAt + 0.15)) : 0

        f.mouth = sim.mouth.v

        // Eyes
        var eye: USEyeShape = .pill
        if sim.locked && pt < USC.T_SUCK_END { eye = .cup }
        if pt >= USC.T_SUCK_END && pt < USC.T_CHEW_END + 0.10 { eye = .content }
        if pt >= progEnd && pt < growEnd + 0.30 { eye = .content }
        f.eye = eye

        let lkx = pt < USC.T_SUCK_END ? cursorX - x : (pt < USC.T_PROG_START ? 0.0 : 40.0)
        let lky = pt < USC.T_SUCK_END ? (cursorY+10) - y : 0.0
```

and replace it with:

```swift
            ? -5 * sin(.pi * usSeg(pt, sim.lockAt, sim.lockAt + 0.15)) : 0

        let lkx = pt < USC.T_SUCK_END ? cursorX - x : (pt < USC.T_PROG_START ? 0.0 : 40.0)
        let lky = pt < USC.T_SUCK_END ? (cursorY+10) - y : 0.0
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`**, find this text (it occurs exactly once):

```swift

        f.fileVisible = pt < USC.T_SUCK_END
        f.suck = usSeg(pt, USC.T_SUCK_START, USC.T_SUCK_END)

        // Content alpha values
```

and replace it with:

```swift

        f.fileVisible = pt < USC.T_SUCK_END

        // Content alpha values
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`**, find this text (it occurs exactly once):

```swift
        f.greenWash = max(hoverGreen, uploadGreen)
        f.chooseAlpha = usSeg(pt, growStart+0.15, growEnd)

        // Mouth rect in island coords (used by drawFile for clipping)
        let R  = d / 2 / 1.04
        let mc = max(0, min(morph, 1.0))
        let rx = R * (1.04 - 0.04*mc)
        let ry = R * (0.97 - 0.03*mc)
        let mh = f.mouth * R * mc
        let mw = 2*rx - 0.24*R
        let mxOff = -mw/2
        let myOff = -ry + 0.10*R
        f.mouthRect = USMouthRect(
            x: x + mxOff * sx,
            y: y + f.hop + myOff * sy,
            w: mw * sx,
            h: mh * sy
        )
        return f
    }
```

and replace it with:

```swift
        f.greenWash = max(hoverGreen, uploadGreen)
        f.chooseAlpha = usSeg(pt, growStart+0.15, growEnd)
        return f
    }
```

- [ ] **Step 3: Run the guard, build and run every test**

Run: `bash scripts/check-no-leftovers.sh; echo "exit $?"`
Expected: five `✓` lines and `exit 0`.

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error|warning: .*(entered|never used)|BUILD"`
Expected: `** BUILD SUCCEEDED **` and no warning about an unused value.

Run: `for f in scripts/test-cat-*.sh scripts/test-screen-geometry.sh; do printf '%-42s' "$f"; bash "$f" 2>&1 | tail -1; done | grep -v "All tests passed"`
Expected: the contract's `✓ two generator runs write identical bytes` and `scripts/test-screen-geometry.sh         Island screen geometry and resting layout: 13 cases passed` (every cat program, `test-cat-upload.sh` with its drop-view tests among them, ends `All tests passed.`).

- [ ] **Step 4: Write the failing tests for the leftovers**

The engine program gains a section (an unknown emote is not noted; a refused file arriving 0.2 s into a chew leaves one lick, after the hairball has started to come up; the gag takes the engine's own 120 ms); the drop view's program pins that its two numbers are the engine's; the Debug panel's program that an unknown emote is not noted and that it offers the engine's emotes.

**Edit `tests/CatDevModelTests.swift`**, find this text (it occurs exactly once):

```swift
        m.emote("nonsense")
        CT.checkTrue("an unknown emote leaves the pose finite", PoseKey.allCases.allSatisfy { m.stage.s[$0].isFinite })

        CT.section("personality: a preset applies to the stage cat and the small ones, and follows the coat")
```

and replace it with:

```swift
        m.emote("nonsense")
        CT.checkTrue("an unknown emote leaves the pose finite", PoseKey.allCases.allSatisfy { m.stage.s[$0].isFinite })
        CT.checkTrue("and is not noted", !m.notes.contains("emote:nonsense"))
        CT.check("the panel offers the engine's emotes", CatDevModel.emotes, CatTables.emoteNames)

        CT.section("personality: a preset applies to the stage cat and the small ones, and follows the coat")
```

**Edit `tests/CatEngineTests.swift`**, find this text (it occurs exactly once):

```swift
            CT.checkTrue("and when the music stops it fades out", e.dancingLevel == 0 && e.look(time: landing).pose.pitch == e.s.pitch)
        }
        CT.finish()
    }
```

and replace it with:

```swift
            CT.checkTrue("and when the music stops it fades out", e.dancingLevel == 0 && e.look(time: landing).pose.pitch == e.s.pitch)
        }

        CT.section("the small things the reviews left for stage 7: an unknown emote, the chew's beats in a hairball, and one place for the gag's numbers")
        do {
            var notes: [(Int, String)] = []
            let (e, clock, step) = makeEngine(momo, note: { notes.append(($0, $1)) })
            e.emote("nope"); e.emote("")
            CT.check("an unknown emote is not noted, and a known one is", notes.map(\.1), [])
            e.emote("love")
            CT.check("love is", notes.map(\.1), ["emote:love"])
            CT.check("the ten emotes the panel offers are the engine's", CatTables.emoteNames, ["love", "happy", "surprised", "proud", "wink", "yawn", "annoyed", "hello", "zoomies", "hairball"])
            _ = (clock, step)
        }
        do {
            // A file is taken and chewed, and a refused one arrives while the cat is still chewing (the drop view decides at the drop, so this is two drops
            // close together): the chew's lick and sparks, queued for 0.95 s and 1 s after the first arrival, must not fire inside the hairball.
            var notes: [(Int, String)] = []
            let (e, clock, step) = makeEngine(momo, note: { notes.append(($0, $1)) })
            step(1)
            e.catchArrive()
            for f in 2...13 { step(f) }                       // 0.2 s into the chew
            let rejectAt = Int(clock.t.rounded())
            e.catchReject("EXE")
            for f in 14...200 { step(f) }
            let licks = notes.filter { $0.1 == "lick" }.map { $0.0 - rejectAt }
            CT.checkTrue("the chew's lick (0.95 s after the first arrival) is gone, and the cat licks its lips once, after the hairball starts to come up: \(licks)", licks.count == 1 && licks[0] > 1700)
            let gag = notes.first { $0.1 == "hairball" }.map { $0.0 - rejectAt } ?? -1
            CT.checkTrue("the gag takes the engine's own 120 ms (to the next frame, \(gag) ms) before the heaves start", gag >= Int(CatRules.gagMs) && gag < Int(CatRules.gagMs) + 17)
            CT.check("and the hairball lasts the engine's own 2.4 s", CatRules.hairballMs, 2400)
        }
        CT.finish()
    }
```

**Edit `tests/UploadCatDriverTests.swift`**, find this text (it occurs exactly once):

```swift
        let arrive = USC.T_SUCK_END - USC.T_DROP, noteAt = USC.T_COUGH_END - USC.T_DROP, doneAt = USC.T_REFUSE_DONE - USC.T_DROP
        CT.checkNear("the note comes 0.12 s of heaving plus the 2.4 s hairball after the file arrives", USC.T_COUGH_END - USC.T_SUCK_END, 2.52)
        let flying = at(0.2)
        CT.checkTrue("just after the drop the file is in flight, and the frame says dropped and refused", flying.dropped && flying.refused && flying.fileVisible)
```

and replace it with:

```swift
        let arrive = USC.T_SUCK_END - USC.T_DROP, noteAt = USC.T_COUGH_END - USC.T_DROP, doneAt = USC.T_REFUSE_DONE - USC.T_DROP
        CT.checkNear("the note comes 0.12 s of heaving plus the 2.4 s hairball after the file arrives", USC.T_COUGH_END - USC.T_SUCK_END, 2.52)
        CT.check("and those two numbers are the engine's own (one place), not copies", [USC.COUGH_LEAD_S * 1000, USC.HAIRBALL_S * 1000], [CatRules.gagMs, CatRules.hairballMs])
        let flying = at(0.2)
        CT.checkTrue("just after the drop the file is in flight, and the frame says dropped and refused", flying.dropped && flying.refused && flying.fileVisible)
```

Run: `for t in engine upload devpanel; do bash scripts/test-cat-$t.sh 2>&1 | grep -E "error" | head -1; done`
Expected: FAIL, three lines: `error: type 'CatTables' has no member 'emoteNames'`, `error: type 'CatRules' has no member 'gagMs'` and `error: type 'CatTables' has no member 'emoteNames'`.

- [ ] **Step 5: Make the three changes**

**Edit `NotchBuddy/Sources/App/CatDevModel.swift`**, find this text (it occurs exactly once):

```swift
    ]
    /// The emotes of the contract, in the spec's order.
    static let emotes = ["love", "happy", "surprised", "proud", "wink", "yawn", "annoyed", "hello", "zoomies", "hairball"]

    /// The collar styles the panel offers (the contract's order, Off last), and the agent colours a collar can wear (the pill catalogue's, as the
```

and replace it with:

```swift
    ]
    /// The emotes of the contract, in the spec's order.
    static let emotes = CatTables.emoteNames

    /// The collar styles the panel offers (the contract's order, Off last), and the agent colours a collar can wear (the pill catalogue's, as the
```

**Edit `NotchBuddy/Sources/App/CatEngine.swift`**, find this text (it occurs exactly once):

```swift

    func emote(_ n: String) {
        note("emote:\(n)")
        if n == "hello" { return greet() }
```

and replace it with:

```swift

    func emote(_ n: String) {
        guard CatTables.emoteNames.contains(n) else { return }   // an unknown emote changes nothing and is not noted
        note("emote:\(n)")
        if n == "hello" { return greet() }
```

**Edit `NotchBuddy/Sources/App/CatEngine.swift`**, find this text (it occurs exactly once):

```swift
            anim(.blush, [(0.6, 200, .out), (0, 800, .inOut)])
        }
        later(950) { $0.lick() }
        later(1000) { $0.emit(.spark, 3) }
    }

```

and replace it with:

```swift
            anim(.blush, [(0.6, 200, .out), (0, 800, .inOut)])
        }
        later(950, "catch") { $0.lick() }
        later(1000, "catch") { $0.emit(.spark, 3) }
    }

```

**Edit `NotchBuddy/Sources/App/CatEngine.swift`**, find this text (it occurs exactly once):

```swift
    func catchReject(_ ext: String) {
        catching = false; slotT = 0; eyeOv = nil; eyeUntil = 0
        later(120) { $0.hairball(ext) }
    }

```

and replace it with:

```swift
    func catchReject(_ ext: String) {
        catching = false; slotT = 0; eyeOv = nil; eyeUntil = 0
        q.removeAll { $0.tag == "catch" }   // the chew of an earlier file: its lick and sparks must not fire inside the hairball
        later(CatRules.gagMs) { $0.hairball(ext) }
    }

```

**Edit `NotchBuddy/Sources/App/CatEngine.swift`**, find this text (it occurs exactly once):

```swift
        let vx = dir * u(0.55, 0.85), vy = u(-0.9, -0.6)
        let seed = Int(rand() * 1e9)
        balls.append(CatBall(x: mx, y: my, vx: vx, vy: vy, rot: 0, age: 0, life: file != nil ? 2.6 : 2.4, file: file, seed: seed, floor: p.ruff != nil ? 1.34 : 1.12))
        for i in 0..<4 {
            let x = mx / 1.3 + (rand() - 0.5) * 0.15
```

and replace it with:

```swift
        let vx = dir * u(0.55, 0.85), vy = u(-0.9, -0.6)
        let seed = Int(rand() * 1e9)
        balls.append(CatBall(x: mx, y: my, vx: vx, vy: vy, rot: 0, age: 0, life: file != nil ? 2.6 : CatRules.hairballMs / 1000, file: file, seed: seed, floor: p.ruff != nil ? 1.34 : 1.12))
        for i in 0..<4 {
            let x = mx / 1.3 + (rand() - 0.5) * 0.15
```

**Edit `NotchBuddy/Sources/App/CatRules.swift`**, find this text (it occurs exactly once):

```swift

enum CatRules {
    /// An agent that finishes after this much working, thinking or searching earns zoomies (ms). The prototype page shortens it to 12 s.
    static let zoomAfterMs = 5.0 * 60 * 1000
```

and replace it with:

```swift

enum CatRules {
    /// The refused file's two numbers that more than one place waits on: after the file reaches the cat's mouth it takes this long (ms) to start heaving,
    /// and its hairball then lasts this long. The engine plays them and the drop view's refusal note appears when they are over, so both read these.
    static let gagMs = 120.0, hairballMs = 2400.0

    /// An agent that finishes after this much working, thinking or searching earns zoomies (ms). The prototype page shortens it to 12 s.
    static let zoomAfterMs = 5.0 * 60 * 1000
```

**Edit `NotchBuddy/Sources/App/MotionProfiles.swift`**, find this text (it occurs exactly once):

```swift
        .ratelimit: [0.3, 0, 0.85, 0.2, 0, 0], .sleeping: [0, 0.1, 0, 1, 0, 0], .dizzy: [0, 0, 0.45, 0, 0, 1],
    ]
    /// Emote mouths, shared by both motion styles: the pose to hold and for how long (ms).
    static let emoteMouth: [String: (pose: [(PoseKey, Double)], ms: Double)] = [
```

and replace it with:

```swift
        .ratelimit: [0.3, 0, 0.85, 0.2, 0, 0], .sleeping: [0, 0.1, 0, 1, 0, 0], .dizzy: [0, 0, 0.45, 0, 0, 1],
    ]
    /// The emotes the engine knows, in the order the Debug panel offers them. Anything else is ignored.
    static let emoteNames = ["love", "happy", "surprised", "proud", "wink", "yawn", "annoyed", "hello", "zoomies", "hairball"]
    /// Emote mouths, shared by both motion styles: the pose to hold and for how long (ms).
    static let emoteMouth: [String: (pose: [(PoseKey, Double)], ms: Double)] = [
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`**, find this text (it occurs exactly once):

```swift
    // file; when it reaches the mouth the cat gags (it takes 120 ms to start heaving) and coughs it up as a hairball, which lasts 2.4 s (the spec). The
    // refusal note, the choose view, starts to appear when that is over, and the cat goes to its choose place. (A-tauri times its note the same way.)
    static let COUGH_LEAD_S:  Double = 0.12
    static let HAIRBALL_S:    Double = 2.40
    static let T_COUGH_END:   Double = T_SUCK_END + COUGH_LEAD_S + HAIRBALL_S   // 4.85: the note starts to appear
    static let T_REFUSE_DONE: Double = T_COUGH_END + 0.45                       // 5.30: the cat is at its choose place
```

and replace it with:

```swift
    // file; when it reaches the mouth the cat gags (it takes 120 ms to start heaving) and coughs it up as a hairball, which lasts 2.4 s (the spec). The
    // refusal note, the choose view, starts to appear when that is over, and the cat goes to its choose place. (A-tauri times its note the same way.)
    static let COUGH_LEAD_S:  Double = CatRules.gagMs / 1000        // the engine's own numbers (CatRules): one place
    static let HAIRBALL_S:    Double = CatRules.hairballMs / 1000
    static let T_COUGH_END:   Double = T_SUCK_END + COUGH_LEAD_S + HAIRBALL_S   // 4.85: the note starts to appear
    static let T_REFUSE_DONE: Double = T_COUGH_END + 0.45                       // 5.30: the cat is at its choose place
```

- [ ] **Step 6: Run every test and the bench**

Run: `for f in scripts/test-cat-*.sh; do printf '%-42s' "$f"; bash "$f" 2>&1 | tail -1; done | grep -v "All tests passed"; bash scripts/render-cats.sh --bench`
Expected: only the contract's `✓ two generator runs write identical bytes`, then one line `12 small cats (30 fps) + the big one (60 fps), update and draw, CPU time: avg … ms, p95 … ms, max … ms per frame (540 frames)`: the average is still about 2.7 ms in this Debug build on a busy machine (1.8 ms optimised, with `RENDER_CATS_OPT=1`), the stage 1 to 4 number: nothing in this task touches the drawing.

- [ ] **Step 7: Commit**

```bash
git add scripts/check-no-leftovers.sh NotchBuddy/Sources/App/IslandTypes.swift NotchBuddy/Sources/App/BotCanvasView.swift NotchBuddy/Sources/App/CatEngine+App.swift NotchBuddy/Sources/App/CatEngine.swift NotchBuddy/Sources/App/IslandRootView.swift NotchBuddy/Sources/App/IslandWindowController.swift NotchBuddy/Sources/App/FileDropView.swift NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/AI/AIService.swift NotchBuddy/Sources/App/UploadSequenceEngine.swift NotchBuddy/Sources/App/CatRules.swift NotchBuddy/Sources/App/MotionProfiles.swift NotchBuddy/Sources/App/CatDevModel.swift tests/CatEngineTests.swift tests/UploadCatDriverTests.swift tests/CatDevModelTests.swift
git commit -m "chore(cat): the dead code of the old character is gone, the reviews' leftovers are fixed, and a guard keeps the old names out

Permanent emotes, miniEye and the eye alias, the drop view's morph, cup, mouth, mouth rect and suction, and the notifications
nothing posts or observes (.botMorphTo, .botReject, .botGreet). An unknown emote is not noted, a refused file clears the chew's
beats, the gag's and the hairball's numbers are in one place. No mochi and no BotEngine remain in
the Mac code, scripts or tests: check-no-leftovers.sh fails the day one comes back.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 15: CI, docs and the final checks

**Agent:** `nm-implementer-light`. The text is given in full.

**Files:**
- Modify: `.github/workflows/build.yml` (six steps), `CLAUDE.md` (one bullet), `ARCHITECT.md` (a sentence)

- [ ] **Step 1: The CI steps and the pointers**

One CI step for each new script, next to the cat steps of stages 1 to 4; one bullet in `CLAUDE.md`'s "Where things are" and a sentence in `ARCHITECT.md`'s Character flow. `docs/THEME.md` is **not** edited here, and neither is the Windows plan's: it still says the apps do not use the tokens yet, and the main session updates it once both stage 7 branches have merged (two plans editing one paragraph would conflict).

**Edit `.github/workflows/build.yml`**, find this text (it occurs exactly once):

```yaml
      - name: Cat panel model (Debug-only panel)
        run: bash scripts/test-cat-devpanel.sh

      - name: Test chat parsing
```

and replace it with:

```yaml
      - name: Cat panel model (Debug-only panel)
        run: bash scripts/test-cat-devpanel.sh

      - name: Cat settings (the clean-up, the UserDefaults keys, Apply to every cat)
        run: bash scripts/test-cat-settings.sh

      - name: Cat settings in the app (the store, the engines, the character)
        run: bash scripts/test-cat-settings-store.sh

      - name: Cat fur lines
        run: bash scripts/test-cat-fur.sh

      - name: Cat sleep timer
        run: bash scripts/test-cat-sleep.sh

      - name: Cat theme (no hard-coded theme colours in the drawing code)
        run: bash scripts/test-cat-theme.sh

      - name: No leftovers (no mochi, no BotEngine, no dead cat code)
        run: bash scripts/check-no-leftovers.sh

      - name: Test chat parsing
```

**Edit `ARCHITECT.md`**, find this text (it occurs exactly once):

```markdown
   - **macOS:** `CatEngine` (with the Playful and Classic motion profiles in `MotionProfiles.swift`) animates a `CatPreset`; `CatRenderer` draws it into a `CGContext` inside the existing canvases (`BotCanvasView`, `MiniBotCanvasView`, `GreetingCanvasView`, `UploadCanvasView`). It replaces `BotEngine.swift`. A file the app refuses is decided at the drop (`CatFileRule`) and coughed up as a hairball. The Debug-only cat panel (`CatDevPanel.swift`) is not in Release or App Store builds.
   - **Windows:** the cat is drawn from the contract (`windows/src/cat/`): `BotEngine` animates a `CatPreset` with the Playful and Classic profiles (`motion/`), and `renderer.ts` draws it in Canvas 2D inside the existing canvases. Checked by `npm run check:cat` against `tests/fixtures/cat/`.
   - **Sub-project A:** both apps now draw Shrimpy and Momo (stages 1–4). `design/prototype/notchmeow.html` is the visual source of truth, and `design/prototype/cat-core.js` holds its pure maths. Both apps are tested against the fixtures generated from it in `tests/fixtures/cat/` (see `docs/CAT-CONTRACT.md`). The Cat settings both apps store are cleaned by `cleanCatSettings` (`settings-cases.json`), and `shared/theme.json` feeds the generated theme files (`docs/THEME.md`).

## Code map (graphify)
```

and replace it with:

```markdown
   - **macOS:** `CatEngine` (with the Playful and Classic motion profiles in `MotionProfiles.swift`) animates a `CatPreset`; `CatRenderer` draws it into a `CGContext` inside the existing canvases (`BotCanvasView`, `MiniBotCanvasView`, `GreetingCanvasView`, `UploadCanvasView`). It replaces `BotEngine.swift`. A file the app refuses is decided at the drop (`CatFileRule`) and coughed up as a hairball. The Debug-only cat panel (`CatDevPanel.swift`) is not in Release or App Store builds.
   - **Windows:** the cat is drawn from the contract (`windows/src/cat/`): `BotEngine` animates a `CatPreset` with the Playful and Classic profiles (`motion/`), and `renderer.ts` draws it in Canvas 2D inside the existing canvases. Checked by `npm run check:cat` against `tests/fixtures/cat/`.
   - **Sub-project A:** both apps now draw Shrimpy and Momo (stages 1–4). `design/prototype/notchmeow.html` is the visual source of truth, and `design/prototype/cat-core.js` holds its pure maths. Both apps are tested against the fixtures generated from it in `tests/fixtures/cat/` (see `docs/CAT-CONTRACT.md`). The Mac app's Settings → Cat (stages 5 to 7) is loaded by `CatSettingsStore` through `CatSettings.clean` and handed to the engines through `CatConfig.shared`; it draws the optional fur lines and the collar (the agent's `task.color`, in the style the user picks), puts an idle cat to sleep after ten minutes with one one-shot timer, and bobs the head and ears to Apple Music. The Cat settings both apps store are cleaned by `cleanCatSettings` (`settings-cases.json`), and `shared/theme.json` feeds the generated theme files (`docs/THEME.md`).

## Code map (graphify)
```

**Edit `CLAUDE.md`**, find this text (it occurs exactly once):

```markdown
- `NotchBuddy/Sources/App/AI/Core/ClaudeCode*.swift`, `ClaudeChat*.swift`, `ClaudeStreamParser.swift`, `ClaudeHookRouting.swift`, with `ClaudeChatViews.swift` and `ClaudeCodeActions.swift` — "Use my Claude plan" (sub-project E3): a chat runs the user's own Claude Code (`claude -p`, stream-json) at one of three levels (Chat only, Read-only, Agent), and Agent's approvals show as a card in the chat. NotchMeow never signs in to Claude.ai and never reads Claude Code's credentials. The Windows/Linux port is `windows/src-tauri/src/ai/claude_*.rs` with `windows/src/core/claude.ts`. Both are tested against `tests/fixtures/ai/claude-code/` (a fake `claude`, transcripts, the expected arguments and environment; `reference.py` decides when they disagree) by `scripts/test-claude-code.sh`, the Rust tests and `npm run check:claude`. Tests only ever run the fake. `SessionStepText.swift` and `windows/src/core/steps.ts` hold the step words the island and the chat share (`scripts/test-session-steps.sh`).
- All of the Claude Code engine is under `#if !APPSTORE`: the App Store build has no engine, no locator and no Connect Claude box, and `scripts/check-app-binary.sh appstore` proves it. Only a Debug build reads `NM_CLAUDE_CODE_PATH_OVERRIDE`, which points it at the fake `claude`.
- `docs/superpowers/specs/` — the NotchMeow design spec: decisions, sub-projects, identity values.
- `windows/` — the Tauri app for Windows and Linux: Rust in `src-tauri/`, TypeScript in `src/`, the `notchmeow-hook` relay in `hook/`. `windows/README.md` lists what differs from the Mac.
```

and replace it with:

```markdown
- `NotchBuddy/Sources/App/AI/Core/ClaudeCode*.swift`, `ClaudeChat*.swift`, `ClaudeStreamParser.swift`, `ClaudeHookRouting.swift`, with `ClaudeChatViews.swift` and `ClaudeCodeActions.swift` — "Use my Claude plan" (sub-project E3): a chat runs the user's own Claude Code (`claude -p`, stream-json) at one of three levels (Chat only, Read-only, Agent), and Agent's approvals show as a card in the chat. NotchMeow never signs in to Claude.ai and never reads Claude Code's credentials. The Windows/Linux port is `windows/src-tauri/src/ai/claude_*.rs` with `windows/src/core/claude.ts`. Both are tested against `tests/fixtures/ai/claude-code/` (a fake `claude`, transcripts, the expected arguments and environment; `reference.py` decides when they disagree) by `scripts/test-claude-code.sh`, the Rust tests and `npm run check:claude`. Tests only ever run the fake. `SessionStepText.swift` and `windows/src/core/steps.ts` hold the step words the island and the chat share (`scripts/test-session-steps.sh`).
- All of the Claude Code engine is under `#if !APPSTORE`: the App Store build has no engine, no locator and no Connect Claude box, and `scripts/check-app-binary.sh appstore` proves it. Only a Debug build reads `NM_CLAUDE_CODE_PATH_OVERRIDE`, which points it at the fake `claude`.
- `NotchBuddy/Sources/App/CatSettings.swift` is the Mac port of `cleanCatSettings` (`scripts/test-cat-settings.sh` replays `tests/fixtures/cat/settings-cases.json`), `CatSettingsStore.swift` the app's one holder of the Cat settings (the UserDefaults keys `cat.*`, `CatConfig.shared`) and `CatSettingsView.swift` the Cat section of Settings. Every stored personality goes through `Personality.clean`, and `CatPersonality` is not `Decodable` on purpose. `CatFur.swift` draws the optional fur lines, `CatSleep.swift` is the ten-minute sleep timer (one one-shot timer, no polling), the collar is `CatGeometry.collarGeometry` and `CatEffects.drawCollar`, and the cats' colours come from `Theme.generated.swift`. `bash scripts/render-cat-settings.sh`, and `render-cats.sh --fur`, `--collars` and `--dance`, draw the section and the sheets without launching the app; `bash scripts/check-no-leftovers.sh` keeps `mochi`, `BotEngine` and the removed dead code out.
- `docs/superpowers/specs/` — the NotchMeow design spec: decisions, sub-projects, identity values.
- `windows/` — the Tauri app for Windows and Linux: Rust in `src-tauri/`, TypeScript in `src/`, the `notchmeow-hook` relay in `hook/`. `windows/README.md` lists what differs from the Mac.
```

- [ ] **Step 2: The final checks**

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)"; bash scripts/test-theme.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓ 3"`
Expected: `# tests 138`, `# pass 138`, `# fail 0`, then `# tests 8`, `# pass 8`, `# fail 0` and `✓ 3 theme files match shared/theme.json` (this plan changed neither the contract nor the theme source).

Run: `for f in scripts/test-cat-*.sh scripts/test-screen-geometry.sh scripts/check-no-leftovers.sh; do printf '%-42s' "$f"; bash "$f" 2>&1 | tail -1; done`
Expected: twenty lines: `scripts/test-cat-contract.sh` ends `✓ two generator runs write identical bytes`, `scripts/test-screen-geometry.sh` ends `13 cases passed`, `scripts/check-no-leftovers.sh` ends `✓ no notification that nothing posts or observes`, and the other seventeen end `All tests passed.`

Run: `git status --short | grep -v "^??" ; git diff --stat -- design tests/fixtures shared windows | tail -1`
Expected: nothing is modified outside the files the tasks list (in a dry-run clone, A-0d's own uncommitted files show too), and `git diff --stat` prints nothing: `cat-core.js`, the fixtures, `shared/theme.json` and `windows/` are as the base has them.

- [ ] **Step 3: The three builds and the binary checks**

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath NotchBuddy/build/release build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3; bash scripts/check-app-binary.sh NotchBuddy/build/release/Build/Products/Release/NotchMeow.app release`
Expected: `** BUILD SUCCEEDED **`, `✓ No cat panel and no Claude Code override in this build; the Claude Code engine is in it`, `✓ FoundationModels is weak-linked` and `✓ No AI base-URL override in this Release build`.

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Debug/NotchMeow.app debug`
Expected: `✓ The cat panel, the Claude Code engine and its override are in this Debug build` and `✓ FoundationModels is weak-linked` (the Debug build of Step 4 of Task 14).

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3; bash scripts/check-app-binary.sh NotchBuddy/build/store/Build/Products/Debug/NotchMeow.app appstore`
Expected: `** BUILD SUCCEEDED **`, `✓ No cat panel and no Claude Code engine in this build` and `✓ FoundationModels is weak-linked`.

- [ ] **Step 4: The icons are untouched**

Run: `d="${TMPDIR:-/tmp}/a-mac-final"; bash scripts/gen-icons.sh "$d/icons" >/dev/null && n=0; bad=0; for f in $(cd "$d/icons" && find . -type f); do n=$((n+1)); cmp -s "$d/icons/$f" "$f" || { bad=$((bad+1)); echo "DIFFERS $f"; }; done; echo "$n icon files compared, $bad differ"`
Expected: `18 icon files compared, 0 differ` (the renderer's changes of stages 5 to 7 are invisible with the collar and the fur off).

- [ ] **Step 5: The final images**

Run: `c=.claude/checkpoints/a-cats-5-7/mac-3; mkdir -p "$c" && bash scripts/render-cats.sh --out "$c/ladder.png" && bash scripts/render-cats.sh --states --cats shrimpy,momo --out "$c/states.png" && bash scripts/render-cats.sh --emotes --cats shrimpy,momo --out "$c/emotes.png" && bash scripts/render-cats.sh --collars --cats shrimpy,momo,latte --scale 2 --out "$c/collars.png" && bash scripts/render-cat-settings.sh --out "$c/settings.png" --height 1400 --character momo --collar tag --fur && bash scripts/render-cat-panel.sh --out "$c/panel.png" --height 1500 && bash scripts/render-cats.sh --bench`
Expected: six `wrote …` lines and one line `12 small cats (30 fps) + the big one (60 fps), update and draw, CPU time: avg … ms, p95 … ms, max … ms per frame (540 frames)`: the draw time is the stage 1 to 4 bench's (about 2.7 ms in this Debug build on a busy machine, 1.8 ms with `RENDER_CATS_OPT=1`); the collar and the fur are off in the bench, so it must not be slower.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/build.yml CLAUDE.md ARCHITECT.md docs/THEME.md
git commit -m "ci(cat): run the new cat programs and the leftovers guard; point CLAUDE.md, ARCHITECT.md and THEME.md at stages 5 to 7

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Whole-branch review**

Dispatch `nm-reviewer-deep` on `git diff notchmeow/rebrand...a-mac/stages-5-7`. Give it the spec, this plan, A-0d's "Interface for the app plans" and the Review Focus. It should read for: that every value read from UserDefaults goes through `CatSettings.clean` and every personality through `Personality.clean` (a search for `decode(CatPersonality`, `UserDefaults.standard.bool(forKey: "cat` and `.string(forKey: "cat`: none outside `CatSettings.swift`); that no timer other than the one-shot sleep timer exists in the new code and the Settings previews are paused when the window is off screen; that nothing the plan adds runs while the island is hidden; that no existing Settings row, pill, card or chat view changed other than as the Global Constraints name; that `HookServer.swift`'s wake and search edits sit after the chat check and change no routing; that the collar's pass is where the contract says and its floors are the contract's; that the theme swap changed no value; that no `mochi`, `Mochi` or `Coucou` name came in; and that the Windows plan's names for the same rules match (`bigCatCollar`, the ten minutes, `follow`). Fix what it finds, then Task 16.

---

### Task 16: Owner checkpoint 3: the final report and the manual checks

No code and no commit. The session reports; the main session sends the owner the images of `.claude/checkpoints/a-cats-5-7/mac-3/` next to the prototype page and the Windows twin's, and asks the owner to run the Debug build (`NotchBuddy/build/Build/Products/Debug/NotchMeow.app`; quit the installed app first) and check, on a notch Mac and, if there is one, a Mac without a notch:

1. **Settings → Cat.** Every row: the 16 previews (and that they stop when Settings is closed: Activity Monitor shows no CPU for a closed Settings window), Playful and Classic and "This cat's motion", a preset and each slider (the cat in the notch follows while you drag), Fur lines (on the big cat only), Collar and "This cat's collar", Apply to every cat. Quit and reopen: every choice is still there. A hand-edited bad value (`defaults write io.github.aikusan.notchmeow cat.personality.momo '{'`, `defaults write io.github.aikusan.notchmeow cat.furLines -int 1`) opens Settings with Momo Balanced and fur lines off.
2. **The collar.** On: the big cat while an agent works, none when idle; the pills' small cats; the compact grid; the greeting at launch (its four session cats). Off: nothing, as before.
3. **Searching and sleeping.** A `WebSearch` event shows searching and the next `Edit` working; ten minutes idle and the cat sleeps (the pills' cats too); a hover or a click wakes it, with zoomies in Playful; an approval or a question waiting, or Apple Music playing, keeps it awake.
4. **The music bob.** Apple Music playing: the cat in the compact notch dances with its head and ears.
5. **The drop view** (the dead code of the old morph is gone): an ordinary file, a refused file (a `.zip`, a `.dmg`, a video, a 30 MB file) and a folder, as at stages 1 to 4: nothing changed.
6. **CPU** with the island hidden and Settings closed: 0 %; the frame readout (`tail -f ~/Library/Logs/NotchMeow/cat-frames.log`) under 2 ms.
7. **A Release build** has no "Cats (Debug)…" item and no cat panel.

Record the owner's answers in the PR description. The open numbers are the neckerchief's floor at Ø12 on a 1x screen (Open question 5) and the compact ear scale from stages 1 to 4.

---

## Parity with Windows/Linux

**macOS is the primary platform: it gets at least what Windows and Linux gets.** The two plans build the same three stages from the same contract (`cat-core.js`, `settings-cases.json`, `collar-cases.json`, `search-tools.json`, `theme.json`); this section was written against the finished Windows plan (`docs/superpowers/plans/2026-10-07-a-tauri-cats-stages-5-7.md`, 17 tasks, three owner checkpoints) and its own "Parity with macOS" list. Every item that list asks the Mac to match is here unless named under "Left out".

| Topic | macOS (this plan) | Windows and Linux |
|---|---|---|
| The clean-up and persistence | `CatSettings` in Swift (UserDefaults keys `cat.*`), replays `settings-cases.json` and adds a real NaN test. Every stored personality goes through `Personality.clean`; `CatPersonality` is not `Decodable`. **The Mac also refuses a trailing comma and a byte-order mark in a stored personality, which Foundation's parser accepts and the contract's strict parsers do not.** | `settings.ts` and the `cat` block of `settings.rs` as `serde_json::Value`, each replaying the same fixture. |
| Pure edit helpers | `CatSettings.withCharacter`, `withMotionStyle`, `withCollar`, `withFurLines`, `withCatMotion`, `withCatCollar`, `withPersonality` (Task 1); the store's setters are these inside `update`; a test shows each changes one thing. | The same seven, in `settings.ts`. |
| The Settings rows | The spec's rows in one section **after** Shortcuts: Character, Motion, This cat's motion, Personality and six sliders, Collar and This cat's collar, Apply to every cat, Fur lines. The rows below the grid edit the chosen cat. | The same rows, order and defaults. |
| The big preview | **Yes:** a Ø84 live preview of the chosen cat beside the 16 tiles (fur lines show from a head of Ø60, and the island's cat is at most Ø66), and a smaller one by the sliders. | A Ø84 big preview. |
| Previews only while Settings is visible | `WindowVisibility`: on screen **and the key window** (occlusion, minimising, closing, key). | `VisibleLoop`: page visibility and focus (the window is created hidden and kept). |
| Fur lines | The prototype's seeded strands (13 and 7), drawn from a head radius of 30 px, tested against numbers made by running the prototype's own function. | The same seeds, in `renderer.ts`. |
| The collar | `collarGeometry` replaying all 164 cases, floors checked on all 16 coats at pixel ratios 1, 2 and 3, painted like the prototype, in the front pass from Ø12. **The big cat wears the focus pill's `color` in every state except idle, asleep and dizzy, with no `isIntegration` test** (every pill, an external agent included, has a colour); the pills' small cats wear their own colour. The greeting's four session cats wear collars. | The same rule (`bigCatCollar`), the same geometry; `AGENT_PILL_COLORS` gives Gemini CLI and Antigravity the Mac's colours (the Mac already has them). |
| The pill colours Windows copies | **A reverse guard:** `tests/CatThemeTests.swift` pins `agent_gemini` `#8AB4F8` and `agent_antigravity` `#E879F9` in `PillCatalog.swift`, so a change on the Mac is deliberate (`windows/src/core/pills.ts` reads the file and `windows-tests.yml` runs when it changes). | `pills.test.mjs` reads `PillCatalog.swift`. |
| Checking it | `render-cats.sh --collars` at 1x and 2x, `render-cat-settings.sh` and `render-cat-panel.sh` draw the images with no app; a pixel test counts the collar's ink at every size; the Debug panel has Collar, Agent colour and Fur lines. | The `?dev` page in a browser. |
| Searching | `HookServer` asks `CatRules.toolState` on `PreToolUse` and `PostToolUse`. | `hooks.ts` and `base.ts`, the same list. |
| Sleeping | `CatSleepClock`: **every idle cat** (the big one and the pills' small ones) sleeps; one one-shot timer, re-set by an event, a state change or a wake, never polling; an approval or a question on any pill, or Apple Music, keeps it awake; one fake-clock program. | `SleepClock`: one timer armed at start and on every waking event; `State.shownState` covers the pills and the grid; the same rule, the same wake events. |
| The music bob | `CatDance`: the head nods and **the ears bounce** (stretch with the hop, flop out on the landing) on the 112 BPM beat, with the dancing level's 0.3 s and 0.5 s fades. **Mac only in use**: it follows the real Apple Music pill. | `danceEars` (`earU` up to 0.14) and a `?dev` button; no music source exists on Windows and Linux yet (their Open question 2). |
| Theme tokens | Every Mac site of A-0d's inventory is a `Theme.*`, proved by six contact sheets drawn before and after and compared byte for byte, and by the icons regenerating identically. The island's glow only with the owner's OK. | A recording canvas and a `?dev` fingerprint; the glow, Task 14, only with the owner's OK. |
| Dead code and the reviews' leftovers | The Mac's list and `scripts/check-no-leftovers.sh` (Mochi, `BotEngine`, the removed names) in CI; the leftovers that apply to the Mac are fixed (Task 14). | `deadcode.test.mjs`, `names.test.mjs` and `leftovers.test.mjs`; its own list (`CATCH`, the late refusal, `Greeting`'s clock). |
| Owner checkpoints | Three, at the same points: after Settings, after the collars, and a final one, with images drawn without launching the app. | Three, with the `?dev` page. |

**Left out of the Mac plan, and why.** From the Windows list: the `CATCH` table (the Mac's drop view derives its note's time from `COUGH_LEAD_S` and `HAIRBALL_S`, now read from the engine's `CatRules`, so there is no second table to merge); the late-refusal hold (the Mac decides a refusal at the drop); `Greeting` taking a clock (the Mac's greeting is a pure timeline driven by the view's clock); the dev readout's "twelve" (the Mac's bench draws twelve); the `isIntegration` flag of external agents (the Mac's pills have colours however they are flagged, and Task 8 drops the test); a Rust twin of the clean-up and a hidden-but-alive window signal built on the page (the Mac has Swift and AppKit's window notifications); the Windows CSS theme file (no Mac site). **docs/THEME.md** is not edited by either plan.

**What only the Mac gets:** the music bob follows a real music source; the strict-JSON refusal (Windows' parsers are strict already); the collar sheet at 1x and 2x and the floor test; the leftovers guard and the identical-icons check.

---

## Open questions for the owner

Each has the answer this plan assumes, so nothing blocks. A different answer changes one small thing, named in each.

1. **The island's glow.** `IslandRootView.swift` draws the glow behind the cat from seven hex literals, the same seven as `Theme.State.glow`. May stage 7 swap them (a state with no glow stays white; no change of look; the plan proves the values equal before the swap)? **Assumed: yes.** On no, skip Task 13's Step 9. *Asked at checkpoint 2.* (The Windows plan asks the same, for its seven literals.)
2. **Where the Cat section sits in Settings.** The spec only says "a new Cat section". It is the **last** entry in the sidebar, after Shortcuts, so nothing that exists moves. Assumed: last. The change is one line in `SettingsView.swift`.
3. **Which cat the rows edit.** The motion, personality and collar rows below the character grid edit the **chosen** character (small grey type names it); to give another cat its own motion or personality, pick it first. This is what "Apply to every cat copies *this* cat's…" means. The alternative, a second picker for "the cat being edited", adds a control for a rare job.
4. **No collar on the big cat when idle, asleep or dizzy.** The spec says "none when idle". Asleep and dizzy are the cat's own states, not an agent's, so the big cat wears none then either (the Windows plan makes the same call). Assumed: yes.
5. **The neckerchief at Ø12 on a 1x screen.** The contract's floor (7 wide, 5 deep) and its 1.5 px dark edge leave 5 to 9 pixels of colour; on a 2x screen, 12 to 24. Every Mac with a notch is 2x. Judge it on `collars-1x.png` at checkpoint 2. If it is not enough, the floor changes once in `cat-core.js` and `collar-cases.json` and both apps pick it up.
6. **The greeting's four session cats wear collars** (the prototype's Gemini CLI, Codex and Claude Code colours) when a style is on, so the greeting's hand-over to the real grid, whose cats wear their pill's colour, does not lose the collar. With Off the greeting is byte for byte what it was. Assumed: yes.
7. **What keeps an idle cat awake.** The spec says "never during an approval or a question". The plan adds Apple Music playing (it dances, which a sleeping cat cannot) and counts a card waiting on *any* pill, not only the focused one. And a hover or a click wakes a sleeping cat but does not push back the bedtime of an awake one. Assumed: yes to all three. **Sleeping covers every idle cat,** the pills' small cats as well as the big one (the Windows plan decides the same).
8. **Mochi in the shared files.** The Mac code, comments, scripts and tests have no `mochi` left (a case-insensitive search finds none; the guard keeps it so). Outside code, `docs/SPEC.md` (the French spec: "Le personnage : Mochi"), `CHANGELOG.md` (upstream's release notes), `.github/ISSUE_TEMPLATE/feature_request.md` ("A new idea for Mochi") and the two files that name the rule (`CLAUDE.md`, `LICENSE-ASSETS.md`) still say it. Historical text stays. **The issue template is a public page that contradicts `LICENSE-ASSETS.md`'s "contains none of the reserved names": a one-line change for a docs chore after the stages merge (the Windows plan makes the same call).** Assumed: leave the rest, fix the template and the SPEC lines then.
9. **The Settings previews pause when the window is not the key window,** not only when it is hidden (the Windows previews stop when Settings is unfocused). On the Mac that means the 17 cats freeze while another app has the keyboard, even if Settings is still visible beside it. Assumed: yes. The change is one condition in `WindowVisibility`.
10. **The collar over the integration pills' colours.** The small cats in the pills wear their pill's colour whatever their state, Resend green and Stripe blue included, because "small cats wear their agent's collar" and every pill has a colour. With the collar Off (the default) nothing changes. The big cat's collar has no `isIntegration` test: any focused pill that is not idle, asleep or dizzy gives it its colour. Assumed: OK.
11. **A big preview beside the 16 tiles** (a Ø84 head), because fur lines only show on a head of Ø60 or more and a Ø36 tile can never show them. Assumed: keep it (the Windows plan has the same). Without it the Fur lines switch is invisible in Settings.
12. **The ear bounce goes with the music bob.** The spec says "the ears bouncing on the beat". `CatDance` adds it to the head-bob (the existing dance moved the whole cat, ears riding along). Assumed: keep it; judge it on `dance.png` at checkpoint 2.
13. **The Settings preview's sample colour.** The big previews wear Claude Code's `#E07950` once a collar style is picked. It is a sample, not an agent's colour.
14. **The Mac's whisker taper (Mac only).** `CatFace.swift` strokes a whisker in 8 segments, a stage 1 choice that batches the hairs; the prototype and the Windows app use 16. A smoother taper is invisible below a head of about Ø60, but **16 segments redraw 11 of the 18 icon files** (the Windows icons too, because `gen-icons.sh` draws them with the Mac renderer), which the dry run measured. Icons are another sub-project's, so this plan leaves the 8 and keeps the identical-icons check true. Assumed: leave it. If the owner says change it, it is one constant and one source-pin test, together with regenerating the icons in the icons sub-project, not here.

## Self-review

- **Spec coverage.** §3: searching (Task 9), sleeping (Task 10), collar (Tasks 6 to 8), music (Task 11), removed dead code (Task 14), the existing fixes were stages 1 to 4. §4: the Cat section's nine rows (Tasks 4 and 8), persistence and frozen IDs (Tasks 1 and 2, the Global Constraints), "the preview animates only while Settings is visible" (Task 4). §5: the theme tokens and the checks (Task 13), the contact sheets (`--fur`, `--collars`, `--dance`), CPU. "Done means": the chosen cat everywhere (Task 2), Settings rows persist (Tasks 1, 2 and 4), no `mochi` identifiers (Task 14), the owner's checkpoints (Tasks 5, 12 and 16). A-0d's interface: every function of the table has its Swift port (Task 1) and its replay; the theme sites are the inventory's (Task 13). Icons are out of scope and proved untouched.
- **Placeholders.** None: every code step is a **Create** or **Edit** block generated from the files the dry run ran, and every `Run:` line has its expected output.
- **Type consistency.** `CatSettings` and its `Entry` (Task 1) are what `CatSettingsStore` (Task 2) and `CatSettingsView` (Tasks 4 and 8) use; `CatConfig.collar`, `collarOverride`, `furLines` and `collarStyle(for:)` are what `CatEngine.collarPaint` (Task 8) and the previews read; `CatCollarPaint` (Task 7) is what `drawCat`, the greeting and the panel build; `CatGeometry.Collar` (Task 6) is what `CatEffects.drawCollar` (Task 7) takes; `CatSleepClock` (Task 10) takes closures, and its app instance feeds `AppState.catAsleep`; `BotState.shown(asleep:)` and `CatRules.shown` (Task 10) agree.
- **Review Focus.** Lines 1 to 6 each have their tests, named in the line.
- **What this plan deliberately does not do:** icons, sound, `writeJSONFile`, H, I and B, anything under `windows/`, an edit to `cat-core.js`, a fixture or `shared/theme.json`, the Mac's whisker taper (8 segments; Open question 14), and a Mochi rename outside code.

## Dry run

The plan was run, as written, before it was handed over. Nothing was committed, pushed, launched, quit or replaced.

**How.** A `git clone --local --shared` of `notchmeow/rebrand` at `f704178` (the icons' merge: A-0d's plan is committed there, its code is not), with `windows/node_modules` linked from the main checkout for A-0d's Windows-side checks (this plan needs none of it: its node programs use only Node's own modules). A-0d was applied first, exactly as written: every Create and Edit block, every Run line and its one bash block fenced with four backticks (it writes `docs/THEME.md`), with 0 failures to apply and 26 Expected lines checked. Then this plan, task by task, in document order, by a throwaway script that did four things: it applied each **Create** block (and checked the file did not exist), applied each **Edit** block (and checked that the text to find matched exactly once), ran every `Run:` line and every bash block, and printed what came out next to the plan's `Expected:` line. It skipped `git add` and `git commit`. `xcodegen` and `xcodebuild` ran for the Debug, App Store and Release schemes, each with its own `-derivedDataPath` and `CODE_SIGNING_ALLOWED=NO`; `check-app-binary.sh` ran in `release`, `debug` and `appstore` modes. There was no network, no install and no `UserDefaults` suite, and the only apps launched were the `swiftc` test programs and the contact-sheet renderers.

**Result of the last run, on a fresh clone and on the text as it stands here.** 205 (20 **Create** and 185 **Edit**) Create and Edit blocks applied, 0 failed to apply; 72 (69 `Run:` lines and 3 bash blocks that are not commits) `Run:` lines and bash blocks ran; 69 Expected lines were compared and each matched. The tree it ended with is the tree the plan was generated from (compared file by file: no difference outside `project.pbxproj`, which `xcodegen` writes). Every path in a `git add` line exists, and every file the tasks changed is in some task's `git add` list.

| Task | What ran | Outcome |
|---|---|---|
| 0 | A-0d's files present; the contract (138 tests) and theme (8) programs; the 11 cat programs; Debug build | as expected |
| 1 | red (no `CatSettings.swift`), green with 61 `✓`, three older programs green, the strict-JSON mutation (3 `✗`, then green) | as expected (the count was 47 in the first draft) |
| 2 | store program red then green; engine, panel and renderer programs; Debug build | as expected |
| 3 | fur program 12 `✓`; renderer 2 `✗` then green; `fur.png`; Debug build | as expected |
| 4 | 4 `✗` then green; Debug build; `settings.png` and `settings-narrow.png` | as expected |
| 5 | all 15 test programs; Debug build; four images (checkpoint 1) | as expected |
| 6 | geometry red, then 164 cases green; rules green | as expected |
| 7 | renderer red, then green with the effects program; `collars-2x.png`, `collars-1x.png` | as expected |
| 8 | rules and store red, then five programs green; `settings-collar.png`, `panel.png`; Debug build | as expected |
| 9 | 3 `✗` then green; Debug build | as expected |
| 10 | sleep program red, 6 source-pin `✗`, then sleep and rules green; Debug and App Store builds | as expected |
| 11 | effects red, then effects, engine and geometry green; `dance.png` | as expected |
| 12 | all 16 test programs; Debug build; six images (checkpoint 2) | as expected |
| 13 | six sheets before and after, byte for byte identical; theme program 3 `✗`, then green; 18 of 18 icon files identical; the glow's 7 colours equal `Theme.State.glow`; builds | as expected (a `✗` count of four was three) |
| 14 | guard red (4 `✗`), then 5 `✓`; Debug build with no warning; all programs; 3 compile errors, then green; bench 2.56 ms average | as expected; the whisker change was dropped here (item 9 below) |
| 15 | contract and theme; all 20 lines; Release, Debug and App Store builds with `check-app-binary.sh`; icons 18 of 18 identical; six images and the bench (2.55 ms) | as expected once item 9 was fixed (11 of 18 differed before) |
| 16 | no commands: the owner's final look | - |

**What the dry run changed in the plan** (each is now in the text above):

1. **Foundation's `JSONSerialization` accepts a comma before a closing brace and a byte-order mark.** The fixture row "a trailing comma" failed on the first port, so Task 1 gained `isStrictJSON`, a note saying why, and Step 5, which puts the lenient line back and shows three tests fail.
2. **`clamp(-0.0, 0, 1)` keeps the minus sign** and would have stored `-0`; the port adds `+ 0`.
3. **A new Swift file needs `xcodegen` before `xcodebuild`** ("cannot find `CatSleepClock` in scope"). Every task that adds a file now runs `cd NotchBuddy && xcodegen` first, and says so in the Global Constraints.
4. **The collar's ink counts are measured, not guessed.** The first thresholds of the pixel test were wrong; a probe drew every style on six coats at Ø12 to Ø66 and the least ink at Ø12 (band 20 and 45 pixels, tag 24 and 50, neckerchief 4 and 10, at 1x and 2x) became the floors. "The upper half of the head is unchanged" is cut a fifth of the head's width above the centre, where the collar can no longer reach.
5. **Two tests were tuned to what the engine does.** The theme test's check that the generated file "holds colours" asks for more than 30, which is what `Theme.generated.swift` has; the gag's timing test measures to the next frame (the engine steps at 60 fps), not to the millisecond.
6. **The Settings preview at Ø62 never showed fur** (fur starts at a head radius of 30 px, which a Ø62 preview does not reach and a Ø84 one does), so the big preview is Ø84 and Open question 11 says why.
7. **Removing `morph` from the drop view left an unused `entered`**, which the build warned about; the edit removes it and Task 14's build line greps for the warning.
8. **Counts and wording in `Expected:` lines**: Task 1 Step 4 prints 61 `✓` lines, not 47; Task 5 and Task 12 list fifteen and sixteen test lines; Task 13's red run shows three `✗` lines, not four; Task 2 no longer claims a line count for `project.pbxproj`; Task 1's `git status` says that a clone where A-0d was not committed shows A-0d's files too.
9. **The whisker taper.** Task 14 first set `hairSegments` to 16, as the prototype and the Windows app draw it. Task 15's identical-icons check then found **11 of the 18 shipped icon files different** (the Mac's, and the Windows ones, which `gen-icons.sh` draws with this renderer). The change was dropped, the taper stays at 8, and Open question 14 asks the owner. This is why Task 15's check is in the plan: without it the icons would have changed under a plan that says it leaves them alone.
10. **A-0d's own plan** had one block a three-backtick reader skips (the four-backtick bash block that writes `docs/THEME.md`); a script that misses it fails at Task 13, which reads `shared/theme.json` and `docs/THEME.md` side by side. Nothing to change in A-0d; the dry run runs it.

**What a real worktree does differently.** The commit steps run there; the clone ran none, so `git status` in the clone showed A-0d's files too (the plan says so where it matters). `xcodegen` regenerates `project.pbxproj` and the plan never edits it by hand. The first Debug build of a fresh `-derivedDataPath` takes a few minutes; the others are incremental.

## The owner's answers (2026-10-07)

- **Plan:** approved, run in a worktree session on Sonnet 5.5, effort high, in parallel with the Windows/Linux twin, on `notchmeow/rebrand` after A-0d (merged as `ac30fac`; the icon swap `f704178` is in the base too).
- **Question 14, the whisker taper:** keep 8 segments, so the approved icons stay byte for byte.
- **Questions 2 to 13:** as assumed. **Question 1, the island glow,** is asked at checkpoint 2 (Task 12), as planned.
- The feature-request template's old character name was fixed separately (`2a07b50`), so question 8 leaves only `docs/SPEC.md` for a later docs pass.
