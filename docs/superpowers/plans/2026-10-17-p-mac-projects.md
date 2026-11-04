# P-mac: Projects on the Mac Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sub-project P on the Mac. Every Claude Code project with a live session shows in the notch: project pills (Claude only) or an expandable Claude panel (with other agents), a Projects screen opened from a folder icon, a menu-bar item and an optional ⌃⌥P, a cat per project, waiting projects first with a pulsing amber dot and a small amber count on the compact notch, Pin / Unpin on a right-click, and a peek after 0.4 s of hover. All of it comes from the hook events NotchMeow already receives. No key, no sign-in, no network, no file read.

**Architecture:** The sidekick's shape (F1-0 → F1-mac). `shared/projects-core.js` is ported to three pure Foundation files (`ProjectsRules`, `ProjectsRegistry`, `ProjectsSnapshot`), each replayed against `tests/fixtures/projects/` by a `swiftc` program, plus one pure file for the Mac's own island rules and words (`ProjectsLayout`). `ProjectsModel` (main actor, in memory only) holds the registry, the last step of each session, the pin, the last click, the panel's open state and the layout, and owns the one one-shot timer that runs only while the island is expanded. `HookServer` feeds it at the top of its three handlers, before a Claude App request is answered "ask". The views take plain values (`PJView`, `PJProject`), so `scripts/render-projects.sh` draws every layout without the app, and the island and Settings wire them in last.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, AppKit (`NSMenu`, the island's existing `NSEvent` monitors), Combine (`$mode`, `$focusId` sinks), XcodeGen, `swiftc` test programs, Bash, Python 3 (standard library, the owner's fake-events script).

**Spec:** `docs/superpowers/specs/2026-10-17-projects-view-design.md` (binding: goals 1 to 7, the anti-goals, rules 1 to 12, "The island (Mac)", "Settings (Mac)", calls 1 to 11). **Contract (the source of truth, merged as `39513b7e`):** `shared/projects-core.js`, `tests/fixtures/projects/` (8 files), `docs/PROJECTS-CONTRACT.md`. If this plan and the core disagree, the core is right. **Focus awareness:** the spec `docs/superpowers/specs/2026-10-17-focus-awareness-design.md`'s call A (`waitIn`, "Waiting in <host>") was folded into P-0. Reading the front app on the Mac belongs to the focus-awareness plan, not to this one: P-mac only consumes `waitIn`. `ProjectsModel.feed(payload:waitIn:)` takes it as an optional argument (through `feedFromHook(payload:waitIn:)`, Task 8), and every call site this plan writes passes `nil`. The focus-awareness plan will pass `HookOrigin.hostName(...)` at the PermissionRequest and question call sites when it steps back. Coordination: the step-back decision is made after the route is known, while this plan feeds right after the chat-run filter; whichever of the two plans merges second moves the request handlers' Projects feed to just after the step-back decision (still before `HookOrigin.answersAskAtOnce`) and passes the host there. `docs/superpowers/plans/2026-10-17-focus-awareness-mac.md`, written beside this one, still does not mention it (checked against `d9f9caca`), and is itself stale on Settings (its Task 3 edits `SettingsView.swift`'s Behavior toggles, which moved to `SettingsGeneralPage.swift` and `SettingsSections.swift` with the Settings restyle); it needs its own refresh before it runs. Both plans edit `HookServer.swift`, `AppState.swift`, `IslandViewContent.swift` and `IslandRootView.swift`: run them one after the other, never side by side.

**Base:** a new branch `p/mac-projects` in a git worktree, from `main` at `d9f9caca` or later (`git merge-base --is-ancestor d9f9caca HEAD` and `git merge-base --is-ancestor 39513b7e HEAD` must both succeed: the Settings restyle and P-0 are merged). This plan never edits `shared/projects-core.js`, a fixture under `tests/fixtures/projects/`, `design/prototype/cat-core.js`, `shared/theme.json`, a generated theme file or anything under `windows/`.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec and the contract. A line marked "Plan call" is a choice this plan makes where the spec leaves one; each is listed again under "Plan calls" at the end.

- **Swift 6, SwiftUI and AppKit, no third-party dependency.** The four pure files (`ProjectsRules`, `ProjectsRegistry`, `ProjectsSnapshot`, `ProjectsLayout`) are Foundation only (`ProjectsLayout` also imports CoreGraphics, as `ShelfBadge` does) and depend on no other app file. `ProjectsRules` carries its own copies of FNV-1a and the cat's LCG (Plan call: no compile dependency; the tests pin both copies to `SK.fnv1a` and `CatRNG`).
- **The contract's constants, verbatim** (`ProjectsRules`): `QUIET_IDLE_MS 600000`, `DIM_MS 1800000`, `REMOVE_MS 7200000`, `FINISHED_MS 5200`, `APP_WAIT_MS 600000`, `CARD_APPROVAL_MS 120000`, `CARD_QUESTION_MS 130000`, `PEEK_DWELL_MS 400`, `AGO_TICK_MS 60000`, `SUBAGENTS_MAX 8`, `SESSIONS_MAX 64`, `NAME_MAX 60`, `STEP_MAX 80`, `PROJECT_CATS_MAX 256`, `APP_WAIT_LABEL "Waiting in Claude App"`, `HOME_NAME "Home"`, `STATES ["approval","question","working","finished","idle"]`, `CAT_IDS` the 16 cat IDs in cat-core's order, `PROJECT_ALIASES` `notch-buddy`, `notchbuddy`, `notch_buddy` → `Notch Buddy`. Boundaries are inclusive on the later side (at exactly 10 min a session is idle, at exactly 5200 ms no longer finished, at exactly 120 s a card's approval is closed, at exactly 2 h gone).
- **Porting rules (where Swift and JavaScript differ; every port follows them):**
  1. A "code point" is a Unicode scalar: count and cut with `unicodeScalars`, never `count` on `String` (grapheme clusters).
  2. Text order is UTF-16 code-unit order (JS `<` and the default `sort()`): compare `Array(a.utf16)` lexicographically. Never Swift's `String <`.
  3. Every sort that JS does with `Array.prototype.sort` is stable: break ties on the input index explicitly.
  4. JSON values from `JSONSerialization`: a number is an `NSNumber` that is not a `CFBoolean` and is finite; a boolean is only a `CFBoolean`; text is only `String`. `NSNumber(1) as? Bool` must not read as true.
  5. The invisible set (`INVISIBLE`): U+0000–001F, U+007F–009F, U+00AD, U+061C, U+180E, U+200B–200F, U+202A–202E, U+2028, U+2029, U+2060, U+2066–2069, U+FEFF, U+FFF9–FFFB, U+E0000–E007F.
  6. JavaScript whitespace (`\s`, `trim()`): U+0009–000D, U+0020, U+00A0, U+1680, U+2000–200A, U+2028, U+2029, U+202F, U+205F, U+3000, U+FEFF.
  7. Insertion-ordered sets (`[...new Set(x)]`) become arrays with first-seen order.
- **Privacy (spec call 1, anti-goal 2).** A session's full `cwd` and the home folder live in `ProjectsModel`'s memory only: never shown, logged, stored or sent. Nothing a view shows carries a `/` or `\`. No prompt, `transcript_path`, tool input or output, notification message, assistant text or command is kept by anything this plan adds. Projects files call no `appendAppLog`/`nbLog`. The only stored value is a project's cat, as `cat.projectCat.<catKey>` (spec "Settings (Mac)", contract "What never leaves memory"). Pins, the last click and the panel's open state are memory only (call 5).
- **Step words (call 4).** Plan call: a session's step is `SessionStepText.line(tool:input:)` with the tool input reduced to its `path` and `file_path` keys, taken from `PreToolUse` only (not for `AskUserQuestion`), then `ProjectsRules.cleanStep`. So a command or a search query never becomes a step ("Runs", "Searches", "Reads · README.md"; with the command gone, Bash is always "Runs", since `SessionStepText`'s finer verbs such as "Tests" need the command), which the spec's anti-goal ("no command") asks for; the existing pill ticker is unchanged.
- **0 % CPU when hidden.** No poll, no repeating timer. One one-shot timer (`ProjectsModel`'s tick), armed only while the island is expanded, whose deadline is the nearest of the next "… ago" minute (`AGO_TICK_MS`) and the next time-based boundary (a `finished` ending, an ask ending, a quiet-idle moment); it is cancelled when the island folds. The waiting dot's pulse and every project cat run in a `TimelineView` that is `paused` unless the island is expanded and the view is on screen: `active` is exactly `state.mode == .expanded && state.view == .overview` for the overview's pills, big card, panel and peek, and `state.mode == .expanded && state.view == .projects` for the screen (pinned in Tasks 9 and 10). The compact badge is still (no animation). Time-based states are computed when the island reads the model (spec "Time-based states").
- **Waiting is a count, never an alert (call 7).** A waiting project moves first, pulses while the island is expanded and adds to the compact count; it never opens or holds the island, never calls the desktop cat, never plays a sound, never touches `wingAlert`, `isHeldOpen` or `isHoverHeld`, and never calls `fsm.agentActivity()` or `userInteracted()` (so the tuck-away count, `IslandTuckAway`, sees only what `HookServer` already reports: a waiting project does not keep a tucked-away island up). Sessions with notch cards keep their alerts exactly as today.
- **Never block Claude Code.** The feed is synchronous, in memory, on the main actor; it never delays a reply. A Claude App PermissionRequest is still answered `{"permissionDecision":"ask"}` at once, as today; the feed only comes first.
- **Never restyle what ships.** The only changes to shipped views: the folder icon in the top bar (after `plus`), the chevron and "N projects · M waiting" in the Claude Code card's title row (with other agents), the expanded section under the two panels, the Claude-only layout, the compact waiting badge, the right-click Pin / Unpin item on a project pill, the "Project cats" card in Settings → Cat → Agents' cats (the tab that holds the Display card since the Settings restyle; the spec's "Settings → Cat → Display"), the menu-bar item and the shortcut row in Settings → General → Shortcuts (listed by `ShortcutLogic.available()`, no view edit). With other agents and the panel folded, the overview is exactly as it ships except the title row's chevron and count (anti-goal 5 and the spec's own exception).
- **Frozen values.** Pill IDs, cat IDs, display mode IDs, the existing action IDs and every existing UserDefaults key are unchanged. New: the action ID **`projects`** (final, call 11; appended last to `ShortcutAction` because Carbon identifies a hot key by its index in `allCases`), its keys `shortcut.projects.keyCode/.flags/.enabled`, and `cat.projectCat.<catKey>`. The contract's state words, roles, hosts and layouts are read, never renamed. Keep the name `wardrobeMenuOpen` in `IslandWindowController` (pinned eight times in `tests/WardrobeWiringTests.swift`, `tests/IslandWingWiringTests.swift` and `scripts/test-u1-wiring.sh`): the Pin menu reuses that flag, and so gets the holds a menu already has (`isHoverHeld` for Open on hover, the wing's alert, the outside click's `busy`, the tuck-away hold).
- **In every build** (Debug, Release, App Store): the marker `NM_PROJECTS_VIEW_ACTIVE` (23 bytes) is in `ProjectsModel`, and `scripts/check-app-binary.sh` looks for it in all three. Nothing of Projects is under `#if !APPSTORE` except the one existing-style block in the new `AgentTarget.bringForward(session:)` that activates a running terminal (as the pill's own tap is GitHub-build-only there).
- **Waiting amber** is `Theme.State.color["approval"]` (`#F5A524`, already generated from cat-core's states), for **both** waiting states, `approval` and `question` (spec goal 5: a waiting project's dot is amber); the other dots use `Theme.State.color` for `working`, `finished`, `idle`. Plan call: no `shared/theme.json` change, so nothing under `windows/` is touched.
- **Never edit `NotchBuddy.xcodeproj` by hand.** A task that adds a Swift file to the app runs `cd NotchBuddy && xcodegen` and commits the regenerated `project.pbxproj`. A file a test or render script compiles is added to that script's list.
- **No `UserDefaults.standard` write and no suite in any test or script.** Store tests use `MemoryBacking` (`tests/CatSettingsSupport.swift`). Tests write logs only under a temp `NM_LOG_DIR`.
- **Nothing of Coucou's.** No Coucou or Mochi name in new code; `bash scripts/check-no-leftovers.sh` stays green.
- **Models and commits** (CLAUDE.md, "Working with AI agents"): Haiku 5.5 first; Sonnet 5.5 only on a named trigger; never Opus or Fable for implementation. Each commit is local, never pushed, lists only its task's files, is written with `git commit -F <file>`, and ends with `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>` (or `Claude Sonnet 5.5` for `nm-implementer-deep`).
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app, and never open the installed one. A Debug, Release or App Store build in the worktree is only built (`CODE_SIGNING_ALLOWED=NO`); the render scripts are not the app and may run. No task sends a hook event to the app's socket.
  2. Install nothing, download nothing, make no network call.
  3. Use `trash`, never `rm -rf`, for anything you delete by hand; scratch files go under `${TMPDIR:-/tmp}` in a unique folder. (Test scripts clean their own `mktemp` folders in a `trap`: the repo's convention.)
  4. No `UserDefaults` suite and no write to `UserDefaults.standard` or `~/Library` in a test or script.
  5. Never edit `shared/projects-core.js`, `tests/fixtures/projects/`, `design/prototype/cat-core.js`, `shared/theme.json`, a generated theme file or anything under `windows/`.
  6. Never push. Commit only in a task's commit step, after `git rev-parse --show-toplevel` (this worktree) and `git branch --show-current` (`p/mac-projects`).
  7. Never rename a frozen ID; no `Coucou` or `Mochi` anywhere.
  8. If a command is refused by a permission prompt, or an Edit's find text occurs zero or two times, stop and report. Do not look for a workaround.
  9. After any edit to an app file, run every `scripts/test-*-wiring.sh` and `scripts/test-u1-wiring.sh`; a pin you break is fixed by changing the code back, unless the task names that pin as one to update.

## Review Focus

The spec is silent on these inputs and conditions; each would bite a person first, most likely first. Each line names the test that pins it.

1. **A Claude App session's approval never reaches the count.** Its PermissionRequest is answered "ask" at the top of `processPermissionRequest`; a feed placed after that return (where the sidekick's is) would never see it, and "M waiting" would stay 0 for the owner's main use. Expected: the Claude App request is counted, labelled "Waiting in Claude App", and still answered at once. Tests: Task 8's pins (the feed precedes `HookOrigin.answersAskAtOnce` in both request handlers) and Task 5 ("a Claude App approval counts once and is still in-app").
2. **The island hidden or compact keeps working.** `IslandRootView` stacks every `IslandView` and only fades the inactive ones, so a pulsing dot, a project cat or the screen's list left in the tree runs while hidden. Expected: nothing of Projects ticks unless the island is expanded and the view is showing; the one timer exists only while expanded, and never twice. Tests: Task 5 ("the tick: armed on open, one at a time, cancelled on fold, re-armed on fire") and Task 9/10/11 pins (`paused:` on every Projects `TimelineView`, `if state.view == .projects` around the screen).
3. **More projects than cells.** Seven live projects in a 2×2 grid or in a row of three. Expected: the first cells in pill order, the last cell "+N" that opens the Projects screen, a waiting project never pushed out of view (it is first). Tests: Task 3 (`gridCells`, `panelCells`: 0, 1, 3, 4, 5, 7 projects, with and without other pills) and Task 6's `--island claude --many` picture.
4. **A pinned or clicked project ends while the island is open.** Expected: the card moves to the next project at once (call 8), the pin is dropped with its project, the expanded section hides and the island returns to 160 pt when no project is left, and the Claude-only layout falls back to today's card. Tests: Task 5 ("a pin goes with its project", "the last project ends: panel hidden, extra height 0") and Task 3 (`usesProjects` with 0 projects).
5. **The compact notch already crowded.** A shelf badge, a 2×2 grid, Two cats mode and kittens share the strip. Expected: the amber count sits in the right wing's free inner end (between the notch and the grid), never over the shelf badge or a grid cell, fades with the wing, and a click on it opens Projects, not the shelf or the home view. While the wing rule is active the right wing folds the island at once and passes the mouse on (`IslandWing`, U1), so, exactly as for the shelf badge, the click lands only while the wing is inactive (an alert, the greeting's tail, a drag); the count itself is what matters, and Projects is always reachable from the folder icon, the menu-bar item and ⌃⌥P. Tests: Task 3 (`badgeCenter`, `badgeHitRect` clear of `ShelfBadge.hitRect` and of the grid's span at 32 pt and 24 pt), Task 11's pins (click order, the badge fades with `wingYielded`) and Task 6's `--badge` picture with the shelf badge on.

---

## File Structure

| Path | Responsibility |
|---|---|
| `NotchBuddy/Sources/App/ProjectsRules.swift` | New. Constants, text helpers, `fnv1a`, `normPath`, `projectOf`, `projectNames`, `rolesOf`, `sessionOrder`, `projectId`, `cleanStep`, `waitLabel`, `agoOf`, `projectStateOf`, `claudeOnly`, `islandLayout`, `isCatKey`, `cleanProjectCats`, `projectCatOf`. Foundation only. |
| `NotchBuddy/Sources/App/ProjectsRegistry.swift` | New. `PJEvent`, `PJPending`, `PJSubagent`, `PJSession`, `PJRegistry`, `ProjectsRegistry.eventFrom/apply/prune/liveAsk/sessionStateAt`. Foundation only. |
| `NotchBuddy/Sources/App/ProjectsSnapshot.swift` | New. `PJSubagentRow`, `PJSessionRow`, `PJProject`, `PJView`, `PJOrderKey`, `PJBigCard`, `ProjectsSnapshot.view/projectOrder/bigCardOf/waitingCount`. Foundation only. |
| `NotchBuddy/Sources/App/ProjectsLayout.swift` | New. The Mac's island rules and words: cells, layout use, panel, big cat coat, the compact badge's place, the words. Foundation + CoreGraphics. |
| `NotchBuddy/Sources/App/ProjectCatSettings.swift` | New. Load and save `cat.projectCat.<catKey>`; `ProjectCatList.rows` for Settings. Foundation only. |
| `NotchBuddy/Sources/App/CatSettingsStore.swift` | `projectCats`, `setProjectCat`, `resetProjectCat`. |
| `NotchBuddy/Sources/App/ProjectsModel.swift` | New. The app's one holder (registry, steps, pin, click, panel, layout, the tick), `ProjectsClock.nextDelay`, `ProjectsStep.line`. Foundation + Combine. |
| `NotchBuddy/Sources/App/ProjectsModel+App.swift` | New. `ProjectsModel.shared` (real home, wall clock, `DispatchQueue` one-shot), the `$mode`/`$focusId` sinks, `AppState.bigCatCoat`, `AppState.projectKittens`. Not compiled by tests. |
| `NotchBuddy/Sources/App/ProjectsViews.swift` | New. `ProjectCatView`, `ProjectStateDot`, `ProjectPill`, `ProjectMoreCell`, `ProjectPillGrid`, `ProjectBigCard`, `ProjectsPanel`, `ProjectRows`, `ProjectsScreenContent`, `ProjectsPeek`, `ProjectsBadgeView`, `ProjectKittenLayer`. Plain values in, closures out. |
| `NotchBuddy/Sources/App/ProjectsScreen.swift` | New. `ProjectsScreenHost` (the `.projects` island view wired to the model and the jump). |
| `NotchBuddy/Sources/App/HookServer.swift`, `AppState.swift`, `AgentTarget.swift` | The three feeds; `questionSessionId`; `bringForward(session:)`. |
| `NotchBuddy/Sources/App/IslandTypes.swift`, `IslandViewContent.swift`, `IslandRootView.swift`, `IslandWindowController.swift`, `KittenViews.swift`, `BotCanvasView.swift`, `AppDelegate.swift`, `ShortcutLogic.swift` | `.projects` view and layout, the overview's two layouts, the top bar icon, the island height, the big cat's coat, state and kittens, the badge, the Pin menu, the peek, the menu-bar item, `projects` shortcut. |
| `NotchBuddy/Sources/App/CatSettingsView.swift`, `CatSettingsSection.swift` | The "Project cats" card on the Agents' cats tab (`CatSettingsView(tab:)`), built from the Settings kit. |
| `NotchBuddy/Sources/App/SettingsMap.swift`, `tests/fixtures/settings/controls.json`, `tests/SettingsMapTests.swift` | The new stored key and the card's home, under the existing `cat.display` control (Mac columns only). |
| `tests/ProjectsRulesTests.swift`, `ProjectsRegistryTests.swift`, `ProjectsLayoutTests.swift`, `ProjectCatsTests.swift`, `ProjectsModelTests.swift`, `ProjectsLeakTests.swift`, `ProjectsWiringTests.swift` | New test programs. |
| `tests/fixtures/mac/projects-scenarios.json` | New. Scripted sessions with typed expectations: replayed by `ProjectsModelTests`, drawn by `render-projects.sh`, sent by `fake-projects-events.py`. |
| `scripts/test-projects-{rules,registry,layout,cats,model,leak,wiring}.sh`, `scripts/test-fake-projects-events.sh` | New, one per program, plus the fake script's test. |
| `scripts/render-projects.sh`, `scripts/render-projects.swift`, `scripts/check-projects-render-private.sh` | New. The checkpoint pictures, and the greps that keep them free of real names, paths and app state. |
| `scripts/fake-projects-events.py` | New. The owner's scripted run on a Debug build. |
| `scripts/render-cat-settings.sh`, `scripts/test-cat-settings-store.sh`, `scripts/render-settings.swift`, `tests/CatWiringTests.swift`, `tests/DesktopCatWiringTests.swift`, `tests/ShortcutTests.swift`, `tests/HotKeyCenterTests.swift`, `scripts/check-app-binary.sh` | Compile lists; the Cat tab's sample projects; the three big-cat pins this plan changes on purpose; the twelfth action (the eleventh besides the island shortcut); the marker. |
| `.github/workflows/build.yml`, `CLAUDE.md`, `ARCHITECT.md`, `docs/SPEC.md` | CI steps; the Mac bullet; flow 7; "Les projets" and the shortcut row. |
| `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` | Regenerated by `xcodegen` only. |

## Tasks and agents

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion` (the deep agent also `superpowers:systematic-debugging`), and read `swift-concurrency-6-2` *(file)* for Tasks 5, 10 and 11 and `swiftui-patterns` *(file)* for Tasks 6, 9, 10, 11 and 12 (ARCHITECT.md, "Extra skills by kind of work"); Task 12 also reads `docs/superpowers/specs/2026-10-17-settings-restyle-design.md` (the kit's rules: words whole, buttons never cut, at 415 pt). Reviewers load `ponytail:ponytail-review`. A Haiku task whose failure has no obvious cause, or that fails twice, goes to `nm-implementer-deep` (trigger 2), noted in the ledger.

| # | Task | Agent, model, effort | Review |
|---|---|---|---|
| 0 | Worktree and baseline | the session | none |
| 1 | `ProjectsRules`: paths, names, roles, steps, cats, layout switch | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 2 | `ProjectsRegistry` and `ProjectsSnapshot`: events, registry, states, the view, order | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 3 | `ProjectsLayout`: the island's cells, layout use, badge place, words | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 4 | Project cats: storage, the store, Settings rows (pure) | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 5 | `ProjectsModel`, the one tick, the scenarios, the leak test | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 6 | The views and `render-projects.sh` | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 7 | **Owner checkpoint 1:** the pictures | the main session and the owner | none |
| 8 | The hook path and the per-session jump | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 9 | The Projects screen: `.projects`, the folder icon, the menu-bar item, ⌃⌥P, the marker | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 10 | The overview's two layouts: Claude only, the chevron and expanded section, the island height, the big cat's coat, state and kittens | `nm-implementer-deep`, **Sonnet 5.5, high (triggers 1 and 5)** | `nm-reviewer` |
| 11 | The peek, Pin / Unpin, the compact waiting badge | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `nm-reviewer` |
| 12 | Settings → Cat → Agents' cats: Project cats, and the control map | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 13 | `fake-projects-events.py` and its test | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 14 | **Owner checkpoint 2:** the scripted run on a Debug build | the main session and the owner | none |
| 15 | Docs, CI, binary markers, final checks | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 16 | Whole-branch review | `nm-reviewer-deep`, Sonnet 5.5, high, with `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` (`model: sonnet`, trigger 4), and `security-review` for the privacy rules | none |
| 17 | **Owner checkpoint 3:** sign-off and the owner's real-build checks | the main session and the owner | none |

**Why Sonnet for 10 and 11 (trigger 1):** Task 10 animates the island's height inside a non-activating, click-through `NSPanel` whose hit tests (`currentIslandFrame`, `isBotHit`) and the big cat's place (`botPosition`) all read `islandSize`, and it changes the coat and kittens the big cat is given; Task 11 adds a menu popped from the existing right-click monitor over SwiftUI-reported frames, a click route in the mouse-up monitor, and a hover dwell inside the panel, without disturbing the island's hover timers. Both touch many cross-task interfaces (trigger 5).

## Execution

One worktree chat session runs the plan: branch `p/mac-projects`, **Sonnet 5.5 at high effort** (trigger 5: an app plan with hard integration and many cross-task interfaces). It runs in its own worktree; the Windows/Linux twin (P-tauri) touches nothing under `NotchBuddy/`.

1. **Setup and stop.** The chip's prompt (it carries the owner's advance approval of the controller brief below):

   > Run `git switch -c p/mac-projects main`, then Task 0 Steps 1 to 3 of `docs/superpowers/plans/2026-10-17-p-mac-projects.md`. Read `CLAUDE.md`, `ARCHITECT.md`, that plan, `docs/superpowers/specs/2026-10-17-projects-view-design.md` and `docs/PROJECTS-CONTRACT.md`. If a base check fails, say so and stop. Reply "ready" and stop. Do not start Task 1. The owner approves in advance the controller brief the main session will send next.

2. **Model.** The main session sets that session to Sonnet 5.5, high (`set_session_model`, `set_session_effort`).
3. **Controller brief** (sent as the next message):

   > Run `docs/superpowers/plans/2026-10-17-p-mac-projects.md` with `superpowers:subagent-driven-development`, task by task, on branch `p/mac-projects`. Dispatch each task to the agent its "Tasks and agents" row names, then `nm-reviewer`; fix what the review finds before the next task. Put the plan's SUBAGENT RULES block, the Global Constraints and only that task's text in every brief. Before every commit check `git rev-parse --show-toplevel` (this worktree) and `git branch --show-current` (`p/mac-projects`); commit with `git commit -F <file>`; never push. Keep a manual ledger at `.superpowers/sdd/2026-10-17-p-mac-projects/progress.md` (one line per task: agent, model, commit, test lines, verdict, any escalation and its trigger). Reviews read `git diff main...HEAD` narrowed to the task's files. Every ```` ```bash ```` block passes `bash -n` before it runs. Stop a process only by the PID you saved. Never launch, quit or replace a NotchMeow app. Stop and report on any refusal. At each owner checkpoint, at the end, and whenever you stop, send your report with `SendMessage` to the main session (id given with this brief) as well as writing it here. Stop after Task 6 for checkpoint 1 (copy the PNGs to `.claude/checkpoints/p-mac/` in the worktree and say what to look at), after Task 13 for checkpoint 2, and after Task 16 for checkpoint 3. Report: the commits; the output of every `bash scripts/test-projects-*.sh`, `bash scripts/test-fake-projects-events.sh`, all `scripts/test-*-wiring.sh`, `scripts/test-u1-wiring.sh`, `scripts/test-shortcuts.sh`, `scripts/test-hotkeys.sh`, `scripts/test-cat-settings-store.sh`, `scripts/test-settings-map.sh`, `scripts/check-settings-render-private.sh`, `scripts/test-projects-contract.sh`, `scripts/check-no-leftovers.sh`; the three build lines and the three `check-app-binary.sh` lines; the PNG paths (the render scripts' and `render-settings.sh`'s).

Before any follow-up turn the main session checks the session is still on Sonnet 5.5, high.

---

### Task 0: Worktree and baseline

**Files:** none.

- [ ] **Step 1: Check the base.** Run `git merge-base --is-ancestor 39513b7e HEAD && echo P-0-merged`. Expected: `P-0-merged`.
- [ ] **Step 2: The contract is green.** Run `bash scripts/test-projects-contract.sh`. Expected: every line passes, exit 0.
- [ ] **Step 3: The pins are green.** Run `for s in scripts/test-*-wiring.sh scripts/test-u1-wiring.sh scripts/test-shortcuts.sh scripts/test-hotkeys.sh scripts/test-cat-settings-store.sh scripts/test-settings-map.sh scripts/test-settings-rules.sh scripts/check-settings-render-private.sh; do bash "$s" >/dev/null || echo "FAIL $s"; done` (the glob includes `test-settings-wiring.sh`, `test-island-wing-wiring.sh` and `test-island-tuck-away-wiring.sh`). Expected: no `FAIL` line. Record the result in the ledger.

---

### Task 1: `ProjectsRules`: paths, names, roles, steps, cats, the layout switch

**Files:**
- Create: `NotchBuddy/Sources/App/ProjectsRules.swift`
- Create: `tests/ProjectsRulesTests.swift`, `scripts/test-projects-rules.sh`

**Interfaces:**
- Consumes: nothing (the contract, `docs/PROJECTS-CONTRACT.md`, and `shared/projects-core.js` lines 17–205 and 341–489 are the specification).
- Produces (every later task uses these exact names):

```swift
enum ProjectsRules {
    static let version = 1
    static let quietIdleMs = 600_000.0, dimMs = 1_800_000.0, removeMs = 7_200_000.0, finishedMs = 5_200.0
    static let appWaitMs = 600_000.0, cardApprovalMs = 120_000.0, cardQuestionMs = 130_000.0
    static let peekDwellMs = 400.0, agoTickMs = 60_000.0
    static let subagentsMax = 8, sessionsMax = 64, nameMax = 60, stepMax = 80, projectCatsMax = 256
    static let appWaitLabel = "Waiting in Claude App", homeName = "Home"
    static let states = ["approval", "question", "working", "finished", "idle"]
    static let catIds: [String]            // the 16, cat-core's order
    static let aliases: [String: String]   // lower-case folder name → product name

    static func isInvisible(_ u: Unicode.Scalar) -> Bool        // porting rule 5
    static func isJSSpace(_ u: Unicode.Scalar) -> Bool          // porting rule 6
    static func jsTrim(_ s: String) -> String
    static func utf16Less(_ a: String, _ b: String) -> Bool     // porting rule 2
    static func cutTo(_ s: String, _ max: Int) -> String        // whole when it fits, else max-1 scalars + "…"
    static func cleanName(_ s: Any?) -> String                  // invisible out, cutTo(nameMax); "" unless String
    static func hostText(_ s: Any?) -> String                   // invisible, "/" and "\" out, jsTrim, cutTo(nameMax)
    static func fnv1a(_ s: String) -> String                    // 8 lower-case hex digits
    static func lcg(seed: UInt32) -> () -> Double               // cat-core line 31: s = s &* 1103515245 &+ 12345; s / 2^32

    static func normPath(_ cwd: Any?) -> String
    struct Place: Equatable, Sendable { var root: String; var worktree: String }
    static func projectOf(_ cwd: Any?, roots: [Any], home: Any?) -> Place?
    struct Named: Equatable, Sendable { var root: String; var name: String; var catKey: String }
    static func projectNames(_ roots: [Any], home: Any?) -> [Named]
    struct RoleIn: Sendable { var id: String; var worktree: Any?; var seq: Double }
    struct Role: Equatable, Sendable { var id: String; var role: String; var label: String }
    static func rolesOf(_ sessions: [RoleIn]) -> [Role]
    struct OrderRow: Sendable { var id: String; var role: String; var seq: Double; var lastAt: Double }
    static func sessionOrder(_ rows: [OrderRow]) -> [String]
    static func projectId(root: String) -> String               // "p-" + fnv1a(root)

    static func cleanStep(_ text: Any?) -> String
    static func waitLabel(_ host: Any?) -> String
    static func agoOf(now: Double, lastAt: Double) -> Int       // whole minutes, never below 0
    static func projectStateOf(_ states: [String]) -> String

    static func claudeOnly(activePills: [Any], otherAgentSeen: Bool) -> Bool
    enum Layout: String, Sendable { case projects, agents }
    static func islandLayout(current: Layout?, claudeOnly: Bool, open: Bool) -> Layout

    static func isCatKey(_ k: String) -> Bool
    static func cleanProjectCats(_ raw: Any?) -> [String: String]   // keys in utf16 order, at most 256
    static func sortedCatKeys(_ cats: [String: String]) -> [String] // the same order, for callers that list them
    static func projectCatOf(_ catKey: Any?, projectCats: Any?, mainCat: Any?) -> (cat: String, stored: Bool)
}
```

- [ ] **Step 1: Write the failing test program `tests/ProjectsRulesTests.swift`** (`@main enum ProjectsRulesTests`, `@MainActor static func main()`, using `CT` from `tests/CatTestSupport.swift`, `CT.fixture(_, dir: "projects")`, `CT.diffs`, `CT.checkRows`, `CT.finish()`). Sections and their assertions:
  - "constants": each value above equals the Global Constraints' value; `catIds == CatPresets.ids`; `fnv1a("") == "811c9dc5"`, `fnv1a("a") == "e40c292c"`, and `fnv1a(x) == SK.fnv1a(x)` for `["", "a", "notchmeow", "/Users/sam/Code/notchmeow", "é🐱"]`; the first 5 values of `lcg(seed: 42)` equal `CatRNG(seed: 42).next()` × 5.
  - "project-cases.json": every row of `projectOf` (compare `Place` as `{root, worktree}` or `NSNull` to `expect`), `names` (`[{root,name,catKey}]`), `roles` (`[{id,role,label}]`; a fixture session's `worktree` is passed as the raw JSON value), `order` (ids), `ids` (`projectId(root:)`). One `CT.checkRows` per group, labelled with the group and the count.
  - "cat-cases.json": `cat` rows → `projectCatOf(catKey, projectCats:, mainCat:)` as `{cat, stored}`; `clean` rows → `cleanProjectCats(raw)` compared as a dictionary **and** its key order compared to `Object.keys` order of `expect` (read the expected order with `JSONSerialization`'s dictionary keys sorted by `utf16Less`, which is how the core writes them).
  - "claude-only-cases.json": `claudeOnly` rows (`activePills` as `[Any]` when it is an array, else `[]`; `otherAgentSeen` true only for a `CFBoolean` true); `layout` rows (`current` → `Layout(rawValue:)`, `NSNull` → nil).
  - "step-cases.json": `steps` rows → `cleanStep(text)` (the `views` group is Task 2's).
  - "what the fixtures cannot write": `cutTo("ab🐱c", 3) == "ab…"` counts the cat as one scalar; `cleanName(42) == ""`; `utf16Less("🐱", "\u{FF5E}") == true` (the cat's lead surrogate 0xD83D sorts before 0xFF5E in UTF-16, while scalar order puts U+FF5E first); `projectCatOf` for 300 names (`"p\(i)"`) × the 16 main cats equals `CatAgentCats.pickCat(taken: [main], rand: CatRNG(seed: UInt32(fnv1a(name), radix: 16)!).next)`.

- [ ] **Step 2: Write `scripts/test-projects-rules.sh`** in the shape of `scripts/test-sidekick-ledger.sh` (temp dir, `NM_LOG_DIR`, `swiftc -swift-version 6`). Compile list: `$APP/ProjectsRules.swift`, `$APP/SidekickText.swift`, and for the pins `$APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift` plus whatever those need to compile (copy the head of `scripts/test-cat-agent-cats.sh`'s list), then `tests/CatTestSupport.swift tests/ProjectsRulesTests.swift`.

- [ ] **Step 3: Run it to see it fail.** Run `bash scripts/test-projects-rules.sh`. Expected: a compile error naming `ProjectsRules`.

- [ ] **Step 4: Implement `ProjectsRules.swift`** as a line-for-line port of the core's functions named above, following the porting rules. Notes where the core's text is easy to misread: `normPath` upper-cases only a lower-case drive letter followed by `/` or the end; `projectOf`'s worktree marker is `/.claude/worktrees/` (root = text before the first, name = first segment after the last, through `cleanName`; an empty root is `/`); a root equal to the home folder is skipped as a candidate; `/` and `X:` match only themselves; `projectNames` keeps duplicate roots, counts collisions by `catKey`, builds `fitName(head, tail, num)` exactly as the core does (core lines 59–64) and records every given name as taken; `rolesOf` sorts by `seq` with the index as tie-break; `cleanStep` replaces each invisible scalar by a space, splits on runs of JS whitespace, keeps the last non-empty `/`- or `\`-separated part of a word that holds one (`…` when none), joins with one space, then `cutTo(stepMax)`; `waitLabel` is `appWaitLabel` when `hostText` is empty, else `"Waiting in \(h)"`; `cleanProjectCats` accepts only `[String: Any]`, keeps a key when `isCatKey` and its value is a `String` in `catIds`, sorts by `utf16Less`, keeps the first 256; `projectCatOf` uses `mainCat` when it is a `catIds` member else `"shrimpy"`, returns `(main, false)` for a key that is not a valid cat key, the stored coat when present, else `free[clamp(floor(r × free.count))]` with `free = catIds` without `main` and `r` the first value of `lcg(seed: UInt32(fnv1a(catKey), radix: 16)!)`.

- [ ] **Step 5: Run it to see it pass.** Run `bash scripts/test-projects-rules.sh`. Expected: every section `✓`, exit 0.

- [ ] **Step 6: Commit** `ProjectsRules.swift`, the test, the script: `feat(projects): port the Projects rules for paths, names, roles, steps and cats (P-mac)`.

---

### Task 2: `ProjectsRegistry` and `ProjectsSnapshot`: events, the registry, states, the view

**Files:**
- Create: `NotchBuddy/Sources/App/ProjectsRegistry.swift`, `NotchBuddy/Sources/App/ProjectsSnapshot.swift`
- Create: `tests/ProjectsRegistryTests.swift`, `scripts/test-projects-registry.sh`

**Interfaces:**
- Consumes: Task 1's `ProjectsRules` (all of it).
- Produces:

```swift
struct PJEvent: Equatable, Sendable {
    var at: Double; var agent: String; var kind: String
    var sessionId = "", cwd = "", subagentId = "", subagentType = ""
    var fromApp = false; var termProgram = "", bundleId = "", waitIn = ""; var stepped = false
    var json: [String: Any] { get }          // the core's keys, in its order
}
struct PJPending: Equatable, Sendable { var by: String; var kind: String; var at: Double; var inApp: Bool; var waitIn: String }
struct PJSubagent: Equatable, Sendable { var id: String; var type: String; var state: String; var born: Double; var last: Double }
struct PJSession: Equatable, Sendable {
    var id: String; var cwd: String; var root: String; var worktree: String
    var seq: Int; var startedAt: Double; var lastAt: Double
    var run: String; var finishedAt: Double?
    var pending: [PJPending]; var fromApp: Bool; var termProgram: String; var bundleId: String; var subagents: [PJSubagent]
    init(json: [String: Any])                 // lenient: a field of the wrong type takes its default; root and cwd through normPath
    var json: [String: Any] { get }
}
struct PJRegistry: Equatable, Sendable {
    var version = 1; var home: String; var sessions: [PJSession] = []; var otherAgentSeen = false; var nextSeq = 1
    static func empty(home: Any?) -> PJRegistry   // home through normPath
}
enum ProjectsRegistry {
    static func eventFrom(_ payload: Any?, now: Double, waitIn: Any? = nil) -> PJEvent?
    static func apply(_ registry: PJRegistry, _ event: PJEvent) -> PJRegistry
    static func prune(_ registry: PJRegistry, now: Double) -> PJRegistry
    static func liveAsk(_ e: PJPending, now: Double) -> Bool
    struct SessionState: Equatable, Sendable { var state: String; var dim: Bool; var gone: Bool; var waitingInApp: Bool; var json: [String: Any] { get } }
    static func sessionStateAt(_ s: PJSession, now: Double?) -> SessionState
}

struct PJSubagentRow: Equatable, Sendable { var id: String; var type: String; var state: String; var json: [String: Any] { get } }
struct PJSessionRow: Equatable, Sendable {
    var id: String; var role: String; var label: String; var state: String; var dim: Bool; var waitingInApp: Bool
    var note: String; var step: String; var host: String; var lastAt: Double; var agoMin: Int; var subagents: [PJSubagentRow]
    var json: [String: Any] { get }
}
struct PJProject: Equatable, Sendable {
    var id: String; var name: String; var catKey: String; var cat: String; var state: String; var dim: Bool
    var waiting: Int; var sessionCount: Int; var lastAt: Double; var agoMin: Int; var step: String; var host: String; var sessions: [PJSessionRow]
    var json: [String: Any] { get }
}
struct PJView: Equatable, Sendable { var projects: [PJProject]; var waiting: Int; var sessionCount: Int; var otherAgentSeen: Bool; var json: [String: Any] { get } }
struct PJOrderKey: Equatable, Sendable { var id: String; var state: String; var lastAt: Double }
struct PJBigCard: Equatable, Sendable { var project: String?; var pinned: String?; var clicked: String?; var json: [String: Any] { get } }
enum ProjectsSnapshot {
    static func view(_ r: PJRegistry, now: Double?, steps: [String: String] = [:], projectCats: [String: String] = [:], mainCat: String? = nil) -> PJView
    static func projectOrder(_ keys: [PJOrderKey]) -> [String]
    static func bigCardOf(_ keys: [PJOrderKey], pinned: String?, clicked: String?) -> PJBigCard
    static func waitingCount(_ counts: [Int]) -> Int   // the sum of the counts that are ≥ 0
    static func wholeCount(_ v: Any?) -> Int           // a non-negative whole JSON number, else 0 (the fixture's "x", 1.5, -1)
}
```

- [ ] **Step 1: Write the failing test program `tests/ProjectsRegistryTests.swift`.** Sections:
  - "event-cases.json": each row → `eventFrom(payload, now:, waitIn: c["waitIn"])?.json ?? NSNull()` against `expect` (a row whose `now` is not a number expects `NSNull`).
  - "registry-cases.json, cases": start from `PJRegistry.empty(home:)`; a step with `payload` applies `eventFrom(payload, now: at, waitIn: step["waitIn"])` when non-nil; a step with `view` compares `ProjectsSnapshot.view(r, now: at).json` whole to `view`, and, where present, `notes` (`label:note` of every row) — one row per failing case.
  - "registry-cases.json, caps": replay `events`; compare only the keys `expect` names: `sessions` as `"\(id)#\(seq)"` in registry order, `subagents` as `{sessionId: [ids]}`, `lastAt` as `{sessionId: lastAt}`, `nextSeq`.
  - "registry-cases.json, presentation": replay `payloads`, then `view(r, now: at, steps: opts.steps ?? [:], projectCats: opts.projectCats ?? [:], mainCat: opts.mainCat)` (`at` null or absent → `nil`) against `view` whole.
  - "state-cases.json": `sessions` rows → `sessionStateAt(PJSession(json:), now:)` (`now` absent or null → nil); `projects` rows → `projectStateOf`; `agoCases` → `agoOf`.
  - "order-cases.json": `order` (ids), `bigCard` (`{project, pinned, clicked}`; a fixture project with no `state` is `""`, with no `lastAt` is 0), `waiting` (`waitingCount(projects.map { wholeCount($0["waiting"]) })`).
  - "step-cases.json, views": the one view case, whole.
  - "what the fixtures cannot write": an event with `at: .nan` or `.infinity` reads as the newest `lastAt` (nothing pruned, `lastAt` unchanged); `eventFrom(_, now: .nan) == nil`; `sessionStateAt(_, now: .infinity)` reads the session's own `lastAt`; `apply` never changes the registry it is given (compare a copy before and after); a payload whose `session_id` is the number 7 gives `nil`; `otherAgentSeen` is set by a Codex event and the registry gains no session.

- [ ] **Step 2: Write `scripts/test-projects-registry.sh`** (compile `ProjectsRules.swift ProjectsRegistry.swift ProjectsSnapshot.swift tests/CatTestSupport.swift tests/ProjectsRegistryTests.swift`).
- [ ] **Step 3: Run it to see it fail.** Expected: compile error naming `ProjectsRegistry`.
- [ ] **Step 4: Implement `ProjectsRegistry.swift` and `ProjectsSnapshot.swift`** as ports of core lines 177–443 with the porting rules. Easy-to-miss points: `eventFrom` maps a valid `nm_agent` other than `claude`/`claude-desktop` (pattern `^[a-z0-9-]{1,24}$`), or Cursor's bundle (lower-cased) when not from the app, to `kind: "other"` with every other field empty; `idText` cuts with `…` at 128, `subTypeText` hard-cuts at 64 with `/`, `\` → `-`; `kind` becomes `question` for `PreToolUse`/`PermissionRequest` with `tool_name == "AskUserQuestion"` and for a `Notification` whose `jsTrim(message)` ends with `?`; `waitIn` is `cutTo(hostText(waitIn), 32)` and `stepped` is "raw `waitIn` is a `String` whose `jsTrim` is non-empty", both empty/false for `fromApp`; `apply` prunes first at the event's time (non-finite → newest `lastAt`, 0 when empty), files a first-seen ask with no usable `cwd` under the home folder when one is known, ignores an `end` for an unknown session, trims to 64 sessions by `lessActive` (first minimal in index order) and drops the event when the new session itself was trimmed, and follows the core's `switch` exactly (a pending entry `inApp` is `s.fromApp || ev.stepped`); the view's subagent order is approval first, then `born` descending, then index descending; `newest` prefers the larger `lastAt`, then the larger `seq`; `hostOf` is `claude-app` / `vscode` (term program or bundle contains `vscode`, never Cursor's bundle) / `terminal`; `projectOrder` puts `approval`/`question` first, then `lastAt` descending, then `utf16Less` on ids; `bigCardOf` takes the first strictly larger `lastAt`.
- [ ] **Step 5: Run it to see it pass.** Expected: every section `✓`.
- [ ] **Step 6: Commit** the two sources, the test, the script: `feat(projects): port the registry, the states and the view (P-mac)`.

---

### Task 3: `ProjectsLayout`: the island's cells, layout use, badge place and words

**Files:**
- Create: `NotchBuddy/Sources/App/ProjectsLayout.swift`
- Create: `tests/ProjectsLayoutTests.swift`, `scripts/test-projects-layout.sh`

**Interfaces:**
- Consumes: `ProjectsRules.Layout`, `ProjectsRules.peekDwellMs`; `ShelfBadge` (for the clearance test only).
- Produces:

```swift
enum ProjectsLayout {
    static let gridCapacity = 4          // the Claude-only right card: the existing 2×2 pill grid
    static let panelColumns = 3          // the expanded section: one row of three columns
    static let panelExtra: CGFloat = 92  // the expanded section's height under the two panels (Plan call)
    static let screenHeight: CGFloat = 240
    nonisolated(unsafe) static var extraHeight: CGFloat = 0   // read by islandSize for .overview; written only by ProjectsModel

    enum Cell: Equatable, Sendable { case project(String), more(Int), pill(String) }
    static func gridCells(projects: [String], otherPills: [String], capacity: Int = gridCapacity) -> [Cell]
    static func panelCells(projects: [String], columns: Int = panelColumns) -> [Cell]
    static func usesProjects(layout: ProjectsRules.Layout, focusId: String?, projectCount: Int, twoCats: Bool) -> Bool   // false in Two cats mode (Plan call 26)
    static func panelShown(panelOpen: Bool, layout: ProjectsRules.Layout, focusId: String?, projectCount: Int) -> Bool
    static func bigCoat(castCoat: String, usesProjects: Bool, expandedOverview: Bool, projectCat: String?) -> String
    static func bigState(castState: String, usesProjects: Bool, expandedOverview: Bool, projectState: String?) -> String   // the big card project's state (owner's answer 3), else the cast's

    // The compact waiting badge: the right wing's inner end, between the notch and the grid.
    static let badgeDiameter: CGFloat = 14, badgeInset: CGFloat = 66, badgeHitSlop: CGFloat = 4
    static func badgeShown(compact: Bool, waiting: Int, greetingTail: Bool) -> Bool
    static func badgeScale(height: CGFloat) -> CGFloat                    // ShelfBadge.scale's rule
    static func badgeCenter(islandWidth: CGFloat, height: CGFloat) -> CGPoint
    static func badgeHitRect(island: CGRect) -> CGRect

    static let peekDwell: Double = ProjectsRules.peekDwellMs / 1000

    // The words (exact copy).
    static func hostWord(_ host: String) -> String     // "claude-app" "Claude App", "vscode" "VS Code", else "Terminal"
    static func agoWord(_ minutes: Int) -> String      // 0 "now"; 1…59 "\(m) min ago"; ≥ 60 "\(m / 60) h ago"
    static func sessionsWord(_ n: Int) -> String       // "1 session" / "\(n) sessions"
    static func projectsWord(_ n: Int) -> String       // "1 project" / "\(n) projects"
    static func waitingWord(_ n: Int) -> String        // "\(n) waiting"
    static func moreWord(_ n: Int) -> String           // "+\(n)"
    static func subagentWord(_ type: String) -> String // the type, or "subagent" when empty
    static func rowDetail(note: String, step: String) -> String   // the note when there is one, else the step
    static func menuTitle(_ projects: Int) -> String   // "Projects" / "Projects (\(n))"
    static func pinTitle(pinned: Bool) -> String       // "Unpin" / "Pin"
    static func badgeLabel(_ waiting: Int) -> String   // "Projects, \(n) waiting" (accessibility)
    static let emptyScreen = "No Claude Code session is running."
    static let emptySettings = "No Claude Code project is running. Each one is listed here while it runs, and keeps the cat you give it."
}
```

- [ ] **Step 1: Write the failing test program `tests/ProjectsLayoutTests.swift`.** Assertions:
  - `gridCells`: 0 projects + pills `["a","b"]` → `[.pill("a"), .pill("b")]` truncated to capacity; 3 projects + 2 pills → 3 projects then `.pill(first)`; 4 projects + pills → 4 projects, no pill; 5 → `p1, p2, p3, .more(2)`; 7 → `p1, p2, p3, .more(4)`.
  - `panelCells`: 1 → `[p1]`; 3 → 3 projects; 4 → `p1, p2, .more(2)`; 7 → `p1, p2, .more(5)`.
  - `usesProjects`: true only for `.projects` with focus `nil` or `"integration_claude"`, at least 1 project and `twoCats == false`; false with focus `"integration_github"`, with 0 projects, for `.agents`, and with `twoCats: true` (Two cats mode keeps today's overview).
  - `panelShown`: true only for `panelOpen` and `.agents` and focus `"integration_claude"` and ≥ 1 project.
  - `bigCoat`: the project's cat only when `usesProjects && expandedOverview && projectCat != nil`; the cast's otherwise (four rows). `bigState`: the same four rows with states (`bigState(castState: "working", usesProjects: true, expandedOverview: true, projectState: "approval") == "approval"`, `… projectState: "idle"` → `"idle"` even while the cast says `working`, and the cast's state whenever `usesProjects` or `expandedOverview` is false or `projectState` is nil).
  - Badge: `badgeShown` false when not compact, when `waiting == 0`, under the greeting's tail; `badgeCenter(islandWidth: 344, height: 32) == CGPoint(x: 278, y: 16)` (the compact island is the 184 pt fallback notch plus 160); for an island `CGRect(x: 0, y: 0, width: 344, height: 32)` and `(…, height: 24)`: `badgeHitRect` does not intersect `ShelfBadge.hitRect(island:)`, its `minX` is ≥ `island.maxX - 80` (right of the notch) and its `maxX` is ≤ `island.maxX - 54 - 1` (left of the grid's span, centred 40 pt in, 2 cells of 12 pt plus a 4 pt gap: 26…54 pt in).
  - Words: every function above, both branches, with the exact strings; `agoWord(59) == "59 min ago"`, `agoWord(60) == "1 h ago"`, `agoWord(125) == "2 h ago"`.
- [ ] **Step 2: Write `scripts/test-projects-layout.sh`** (compile `ProjectsRules.swift ProjectsLayout.swift ShelfBadge.swift tests/CatTestSupport.swift tests/ProjectsLayoutTests.swift`).
- [ ] **Step 3: Run it to see it fail.**
- [ ] **Step 4: Implement `ProjectsLayout.swift`.** `gridCells`: when `projects.count <= capacity`, the projects then the other pills up to `capacity`; else the first `capacity - 1` projects and `.more(count - (capacity - 1))`. `panelCells`: the same rule with `columns`, no pills. `badgeCenter`: `(islandWidth - badgeInset, height / 2)`. `badgeHitRect`: a square of side `2 × (badgeDiameter / 2 × badgeScale(island.height) + badgeHitSlop)` centred on `(island.maxX - badgeInset, island.midY)`.
- [ ] **Step 5: Run it to see it pass.**
- [ ] **Step 6: Commit**: `feat(projects): the island's cells, badge place and words (P-mac)`.

---

### Task 4: Project cats: storage, the store, the Settings rows

**Files:**
- Create: `NotchBuddy/Sources/App/ProjectCatSettings.swift`, `tests/ProjectCatsTests.swift`, `scripts/test-projects-cats.sh`
- Modify: `NotchBuddy/Sources/App/CatSettingsStore.swift` (a fourth group beside `wardrobe`), `scripts/test-cat-settings-store.sh` (add `$APP/ProjectsRules.swift $APP/ProjectCatSettings.swift` to its list), `scripts/render-cat-settings.sh` (the same two files, inserted right before `$APP/CatSettingsStore.swift`; Task 12 adds `$APP/ProjectsLayout.swift` at the same place, because `CatSettingsView` then reads `ProjectsLayout.emptySettings` and `scripts/render-site.sh` still calls this script: `tests/SettingsWiringTests.swift` pins the run that starts at `$APP/SettingsRoute.swift` and ends at `$APP/CatDisplayPreview.swift`, so nothing may go inside it). `render-settings.sh` compiles every app file and needs no edit.

**Interfaces:**
- Consumes: `ProjectsRules.cleanProjectCats`, `isCatKey`, `projectCatOf`, `sortedCatKeys`; `CatSettingsBacking` (`object(forKey:)`, `set(_:forKey:)`, `removeObject(forKey:)`, `allKeys()`, as `CatDisplaySettings.load/save` use them).
- Produces:

```swift
enum ProjectCatSettings {
    static let prefix = "cat.projectCat."
    static func key(_ catKey: String) -> String
    static func load(from store: any CatSettingsBacking) -> [String: String]     // cleaned; never writes
    static func save(_ cats: [String: String], to store: any CatSettingsBacking, replacing old: [String: String])   // only changed keys; removes keys no longer held
}
enum ProjectCatList {
    struct Live: Equatable, Sendable { var catKey: String; var name: String }   // a live project, in pill order
    struct Row: Equatable, Sendable { var catKey: String; var name: String; var cat: String; var stored: Bool; var live: Bool }
    static func rows(live: [Live], stored: [String: String], main: String) -> [Row]
}
// CatSettingsStore:
@Published private(set) var projectCats: [String: String]
func setProjectCat(_ catId: String, for catKey: String)
func resetProjectCat(for catKey: String)
```

- [ ] **Step 1: Write the failing test `tests/ProjectCatsTests.swift`:** on a `MemoryBacking`: `load` of `["cat.projectCat.notchmeow": "momo", "cat.projectCat.a/b": "momo", "cat.projectCat.x": "Momo", "cat.projectCat.__proto__": "leo", "cat.agentCat.agent_codex": "leo"]` is `["notchmeow": "momo"]` and writes nothing (the backing's keys are unchanged); a `CatSettingsStore(backing:config:)` loads it; `setProjectCat("leo", for: "site")` stores `cat.projectCat.site = "leo"` and publishes; `setProjectCat("bogus", for: "site")` changes nothing; `setProjectCat("leo", for: "a/b")` stores nothing; `resetProjectCat(for: "site")` removes the key; 257 stored keys load as the first 256 in `utf16Less` order; `rows`: live projects first in input order, one row per `catKey` (two live projects sharing a key make one row, the first name), each `cat` from `projectCatOf(catKey, projectCats: stored, mainCat: main).cat`, `stored` true only for a stored key, then stored-only keys in `utf16Less` order with `name == catKey` and `live == false`.
- [ ] **Step 2: Write `scripts/test-projects-cats.sh`** (the compile list of `scripts/test-cat-settings-store.sh` plus `ProjectsRules.swift ProjectCatSettings.swift`, `tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/ProjectCatsTests.swift`).
- [ ] **Step 3: Run it to see it fail.**
- [ ] **Step 4: Implement** `ProjectCatSettings.swift` and the store's group in the pattern of `updateWardrobe`: edit a copy, clean it with `ProjectsRules.cleanProjectCats`, return when unchanged, save only the changed keys, publish. `setProjectCat` refuses a key that is not `isCatKey` and an ID not in `catIds` (the clean-up does it). The store's `init` loads it with the others.
- [ ] **Step 5: Run** `bash scripts/test-projects-cats.sh`, `bash scripts/test-cat-settings-store.sh`, `bash scripts/test-settings-wiring.sh` and `bash scripts/render-cat-settings.sh --out "${TMPDIR:-/tmp}/p-mac-settings.png"`. Expected: all pass, the PNG is written.
- [ ] **Step 6: Commit**: `feat(projects): store each project's cat by its folder name (P-mac)`.

---

### Task 5: `ProjectsModel`, the one tick, the scenarios, the leak test

**Files:**
- Create: `NotchBuddy/Sources/App/ProjectsModel.swift`, `tests/fixtures/mac/projects-scenarios.json`, `tests/ProjectsModelTests.swift`, `tests/ProjectsLeakTests.swift`, `scripts/test-projects-model.sh`, `scripts/test-projects-leak.sh`

**Interfaces:**
- Consumes: Tasks 1–3 (`ProjectsRegistry.eventFrom/apply/liveAsk`, `ProjectsSnapshot.view/bigCardOf`, `ProjectsRules.islandLayout/claudeOnly/cleanStep`, `ProjectsLayout.panelShown/usesProjects/panelExtra/extraHeight`); `SessionStepText.line(tool:input:)`.
- Produces:

```swift
enum ProjectsStep {
    /// The step a PreToolUse leaves on its session: SessionStepText's words with the input reduced to "path" and "file_path"; nil for AskUserQuestion or another event.
    static func line(payload: [String: Any]) -> String?
}
enum ProjectsClock {
    /// Milliseconds until the nearest of: the next whole minute after `now` (AGO_TICK_MS), a shown `finished` ending, an open ask ending, a working session turning idle. Only boundaries strictly after `now` count (one at exactly `now` has already passed: the contract's later-side boundaries); the result is never below 50 ms.
    static func nextDelay(_ r: PJRegistry, now: Double) -> Double
}
@MainActor final class ProjectsModel: ObservableObject {
    static let marker = "NM_PROJECTS_VIEW_ACTIVE"
    typealias Cancel = @MainActor () -> Void
    typealias Schedule = @MainActor (_ afterMs: Double, _ fire: @escaping @MainActor () -> Void) -> Cancel
    init(home: String, now: @escaping @MainActor () -> Double, schedule: @escaping Schedule)

    private(set) var registry: PJRegistry             // not @Published: feed sends objectWillChange only when the visible summary changes
    private(set) var steps: [String: String]          // memory only; a key leaves with its session
    @Published private(set) var pinned: String?
    @Published private(set) var clicked: String?
    @Published var panelOpen = false                  // the expanded section, remembered while the app runs
    @Published private(set) var layout: ProjectsRules.Layout = .agents
    @Published private(set) var panelShown = false
    private(set) var tickArmed = false                // for the tests

    func feed(payload: [String: Any], waitIn: String? = nil)   // sends objectWillChange only when view()'s display values (projects' ids, names, states, waiting, counts, steps, rows; otherAgentSeen) differ from before the event
    func view(projectCats: [String: String] = [:], mainCat: String? = nil) -> PJView     // at now()
    func bigCard(in view: PJView) -> PJProject?       // bigCardOf with the held pin and click; reads only
    func reconcile(_ view: PJView)                    // stores bigCardOf's pinned and clicked back (a pin goes with its project)
    func select(_ projectId: String)                  // a click on a pill: the big card's project
    func togglePin(_ projectId: String)               // one pin at a time
    func isPinned(_ projectId: String) -> Bool
    func refreshLayout(activePills: [String], open: Bool, focusId: String?)   // islandLayout, panelShown, ProjectsLayout.extraHeight; remembers activePills and focusId
    func relayout(open: Bool)                         // refreshLayout with the last activePills and focusId
    func islandExpanded(_ expanded: Bool)             // arms the one tick (reconcile + re-arm on fire), or cancels it
}
```

- [ ] **Step 1: Write `tests/fixtures/mac/projects-scenarios.json`.** Shape: `{"version": 1, "note": …, "home": "/Users/sam", "scenarios": {<name>: {"about": …, "steps": [{"say": …, "at": <ms from 1760000000000>, "wait_ms": …, "event": <full hook payload>, "waitIn"?: <host>, "expect"?: {"projects": ["<name>:<state>:<waiting>", …], "rows": {"<name>": ["<label>:<state>", …]}, "waiting": <n>, "layout": "projects"|"agents"}}]}}}`. A `cwd` that starts with `~` stands for the home folder (the test and the script replace it). Paths are made up under `/tmp/nm-projects-demo/`. Five scenarios: `two-projects` (a main session and a side session in `notchmeow/.claude/worktrees/p-mac`, two subagents, a second project `site`, Stop then finished then idle at 5.2 s), `claude-app-wait` (`nm_agent: "claude-desktop"`: a PermissionRequest counted as `approval` with note "Waiting in Claude App", ended by its next PreToolUse), `collide-and-home` (`/tmp/nm-projects-demo/a/site` and `/tmp/nm-projects-demo/b/site` named `site — a` and `site — b`; a session at `~` named `Home`), `other-agent` (a Codex event `nm_agent: "codex"`: layout `agents`, no session), `end` (SessionEnd for the last session: no project left). Each `expect` is typed by hand and must agree with the core (Task 2's port is the check).
- [ ] **Step 2: Write the failing `tests/ProjectsModelTests.swift`.** With a fake clock (`var t`) and a fake `schedule` that records `(afterMs, fire)` and counts live timers:
  - "scenarios": replay every scenario through `feed(payload:waitIn:)` at `t = 1760000000000 + at`, with `refreshLayout(activePills: ["integration_claude"], open: false, focusId: "integration_claude")` after each step; check each `expect` (projects short form from `view()`, rows, waiting, layout).
  - "steps": a PreToolUse `Bash` with `command: "rm -rf /x"` leaves step `"Runs"`; `Read` with `file_path: "/Users/sam/a/README.md"` leaves `"Reads · README.md"`; `AskUserQuestion` leaves the previous step; a UserPromptSubmit with a prompt leaves no step; a SessionEnd drops the session's key from `steps`.
  - "pin and click": `togglePin(a)` then `togglePin(b)` → only `b` pinned; `bigCard` is the pin, else the click, else the most recent; after SessionEnd of `b`'s last session and `reconcile(view())`, `pinned == nil` and the card is the next project.
  - "a Claude App approval counts once and is still in-app": feeding a `claude-desktop` PermissionRequest gives `view().waiting == 1`, the row's `waitingInApp`, note `"Waiting in Claude App"`.
  - "layout": `refreshLayout` while `open: true` keeps the current layout; folded it follows `claudeOnly`; `panelShown` and `ProjectsLayout.extraHeight` (`92` or `0`) follow `ProjectsLayout.panelShown`; the last project ending sets both to false/0.
  - "the tick": `islandExpanded(true)` arms exactly one timer with `afterMs == ProjectsClock.nextDelay(registry, now: t)`; a second `islandExpanded(true)` leaves one; firing re-arms one; `islandExpanded(false)` cancels it (0 live) and `tickArmed == false`; nothing is ever armed while folded, whatever is fed.
  - "nextDelay": empty registry at `t` → 60000; a session finished at `t - 1000` → 4200; an open card approval at `t - 119000` → 1000; a working session quiet since `t - 599000` → 1000; at exactly the boundary nothing is due at 0: finished at `t - 5200`, a card approval at `t - 120000`, a card question at `t - 130000`, a working session quiet since `t - 600000` each → 60000 (the next minute); a boundary 10 ms ahead (finished at `t - 5190`) → 50 (the floor).
  - "publishing": a subscriber counting `objectWillChange` sees one send for an event that adds a project or changes a state, step or waiting count, and none for an event that changes nothing shown (a second identical `PreToolUse` for the same session and step).
  - "the big cat follows the big card" (owner's answer 3): with no pin and no click the big card is the most recent project, so a project that just started waiting is the big card and `bigCard(in: view())?.state` is `"approval"` (a PermissionRequest) or `"question"` (an `AskUserQuestion`); with a calm project pinned (`working` or `idle`) and another project waiting, `bigCard` is the pinned one, its state is calm, and `view().waiting >= 1`.
  - "open and the last project ends": `islandExpanded(true)`, `refreshLayout(…, open: true, …)` with the panel shown, then a SessionEnd for the last session: `relayout(open: true)` after the feed (what the app calls after every feed, Task 9) leaves `panelShown == false` and `ProjectsLayout.extraHeight == 0`; firing the tick does the same by itself.
- [ ] **Step 3: Write the failing `tests/ProjectsLeakTests.swift`.** Plant the marker `zqLEAKqz` in: a parent folder of `cwd` (`/Users/sam/zqLEAKqz/proj`), `prompt`, `message`, `last_assistant_message`, `transcript_path`, `tool_input.command`, `tool_input.query`, `tool_response`. Feed a session's whole life through a model whose `home` is `/Users/sam`. Assert: no display string of `view()` (every `name`, `catKey`, `label`, `note`, `step`, `type`, `host`) contains the marker or a `/` or `\`; `steps` values contain neither; after `CatSettingsStore(backing: MemoryBacking()).setProjectCat("leo", for: view().projects[0].catKey)` no backing key or value contains the marker; the temp `NM_LOG_DIR` holds no file containing the marker; the script runs the program with `HOME` set to a fresh empty temp folder and checks after the run that it is still empty (`find "$TEST_HOME" -mindepth 1 | wc -l` is 0).
- [ ] **Step 4: Write `scripts/test-projects-model.sh` and `scripts/test-projects-leak.sh`** (compile `ProjectsRules ProjectsRegistry ProjectsSnapshot ProjectsLayout ShelfBadge SessionStepText ProjectsModel`, the leak test also the store's list from Task 4 and `tests/CatSettingsSupport.swift`).
- [ ] **Step 5: Run both to see them fail.**
- [ ] **Step 6: Implement `ProjectsModel.swift`.** `feed`: `eventFrom(payload, now: now(), waitIn: waitIn)`, `apply`, then the step (`ProjectsStep.line`) for that session, then drop `steps` keys whose session left, then `reconcile(view())`. `view` passes `steps` to `ProjectsSnapshot.view`. `islandExpanded(true)` cancels any timer, then arms one at `ProjectsClock.nextDelay`; its `fire` sends `objectWillChange` (the "… ago" words and the time-based states changed), reconciles, calls `relayout(open: true)` and re-arms if still expanded. `feed` compares the display values of `view()` before and after the event and sends `objectWillChange` only when they differ. No `Timer`, no `asyncAfter` and no `Task.sleep` in this file: the only scheduling is the injected `schedule`.
- [ ] **Step 7: Run** `bash scripts/test-projects-model.sh && bash scripts/test-projects-leak.sh`. Expected: all `✓`.
- [ ] **Step 8: Commit**: `feat(projects): the model, its one tick and the leak test (P-mac)`.

---

### Task 6: The views and `render-projects.sh`

**Files:**
- Create: `NotchBuddy/Sources/App/ProjectsViews.swift`, `scripts/render-projects.sh`, `scripts/render-projects.swift`, `scripts/check-projects-render-private.sh`

**Interfaces:**
- Consumes: `PJProject`, `PJSessionRow`, `PJSubagentRow`, `PJView` (Task 2), `ProjectsLayout` (Task 3), `CatEngine`, `CatPresets`, `CatRenderer`, `CatDrawOptions`, `CatKittens`, `CatKittenDraw`, `CatIslandLayout.kittenBox`, `Theme.State.color`; `Color(hex:)` (an app helper in `IslandRootView.swift`; the render file defines its own copy, as `render-shelf.swift` does).
- Produces (plain values in, closures out; no view reads `AppState` or `ProjectsModel`):

```swift
struct ProjectCatView: View { init(cat: String, state: String, head: Double, active: Bool) }   // a CatEngine like CatPreviewView; TimelineView paused unless active
struct ProjectStateDot: View { init(state: String, size: CGFloat = 7, animate: Bool) }          // approval and question: Theme.State.color["approval"] (amber), pulsing only while animate; else Theme.State.color[state]
struct ProjectPill: View { init(project: PJProject, active: Bool, onTap: @escaping () -> Void, onHover: @escaping (Bool) -> Void, onFrame: @escaping (CGRect) -> Void = { _ in }) }   // AgentPill's capsule, sizes and colours; onFrame gets its frame in the "nm.island" coordinate space (a GeometryReader background), so the view never names ProjectsHits
struct ProjectMoreCell: View { init(count: Int, onTap: @escaping () -> Void) }
struct ProjectPillGrid: View { init(cells: [ProjectsLayout.Cell], projects: [PJProject], pill: @escaping (String) -> AnyView, active: Bool, onSelect: @escaping (String) -> Void, onMore: @escaping () -> Void, onHover: @escaping (String, Bool) -> Void, onFrame: @escaping (String, CGRect) -> Void = { _, _ in }) }
struct ProjectBigCard: View { init(project: PJProject, animate: Bool, onOpen: @escaping () -> Void) }   // title row (dot, name, "· N sessions"), step line, host · ago, ↗
struct ProjectsPanel: View { init(cells: [ProjectsLayout.Cell], projects: [PJProject], selected: PJProject?, active: Bool, onSelect: @escaping (String) -> Void, onMore: @escaping () -> Void, onHover: @escaping (String, Bool) -> Void, onFrame: @escaping (String, CGRect) -> Void = { _, _ in }) }
struct ProjectRows: View { init(project: PJProject, active: Bool, onRow: @escaping (String) -> Void) }   // one project's session rows and indented subagent rows
struct ProjectsScreenContent: View { init(view: PJView, active: Bool, onRow: @escaping (String) -> Void) }   // one section per project; empty state
struct ProjectsPeek: View { init(project: PJProject, active: Bool) }
struct ProjectsBadgeView: View { init(count: Int, height: CGFloat = 32) }
struct ProjectKittenLayer: View { init(subagents: [PJSubagentRow], parentCat: String, place: String, unit: CGFloat, active: Bool) }
```

- [ ] **Step 1: Write `scripts/render-projects.sh` and `scripts/render-projects.swift`** in the shape of `render-shelf.{sh,swift}` (`ImageRenderer`, scale 2, `--out DIR`). The compile list is the files of `render-cat-settings.sh`'s list from `CatMath.swift` up to and including `CatSettingsStore.swift` (with Task 4's `ProjectsRules.swift ProjectCatSettings.swift`; not the Settings kit files after it) plus `CatKittenDraw.swift ProjectsRegistry.swift ProjectsSnapshot.swift ProjectsLayout.swift ShelfBadge.swift ShelfBadgeView.swift ProjectsViews.swift`. The data comes from `tests/fixtures/mac/projects-scenarios.json` replayed through `ProjectsRegistry`/`ProjectsSnapshot` (never hand-made rows). Parts, each one PNG:
  - `--island claude`: a 720 × 160 stand-in island (black, the header's three tab icons plus the folder icon, `CardBackground`'s look as a stand-in) with `ProjectCatView` at the big cat's place (`x 68`, `y 101`, head `58`), `ProjectBigCard` in the 322 pt left card and `ProjectPillGrid` in the right card; `--many` uses 7 projects (the "+N" cell).
  - `--island agents` (folded: today's Claude Code card with the chevron and "2 projects · 1 waiting") and `--island agents-open` (the 252 pt island with `ProjectsPanel`).
  - `--screen` and `--screen --empty` (240 pt).
  - `--peek` (over the left card).
  - `--badge` (the compact 344 × 32 strip with a 2×2 grid stand-in, `ShelfBadgeView(count: 3)` and `ProjectsBadgeView(count: 2)`; also at 24 pt).
  - `--all` writes every part.
- [ ] **Step 1b: Write `scripts/check-projects-render-private.sh`** in the shape of `scripts/check-settings-render-private.sh` (plain greps, comment lines skipped, `✓`/`✗` lines, exit 1 on a failure): `render-projects.swift`/`.sh` never read the host name, the user or the environment (the same `HOSTREAD` pattern); they and `ProjectsViews.swift` name no `AppState`, `ProjectsModel.shared`, `ProjectsHits`, `UserDefaults`, `KeychainStore`, `HookServer`, `NSHomeDirectory`, `homeDirectoryForCurrentUser` or `NSUserName`; no real person or device name (`ike`, `lorenz`, `tazan`, `raill`) in the three files.
- [ ] **Step 2: Run it to see it fail.** `bash scripts/render-projects.sh --all --out "${TMPDIR:-/tmp}/p-mac-pics"`. Expected: a compile error naming `ProjectBigCard`.
- [ ] **Step 3: Implement `ProjectsViews.swift`.** Copy the look of what ships, never restyle it: `ProjectPill` is `AgentPill`'s capsule (height 28, fill `#0E0F11`, stroke at 0.14, hover 0.18/0.55, `MiniBotCanvasView`'s 22 pt cat place at leading 8) with `ProjectCatView` in the cat's place, the name (10 pt semibold) and a `ProjectStateDot` where `PillBadgeView` sits; `ProjectBigCard` uses the overview's title row fonts and colours (12 pt semibold `#F5F6F8`, 11 pt `#8E939C`), the step in 11 pt `#B0B5BE`, the bottom line `hostWord · agoWord`, the ↗ button as the overview draws it; a dimmed project or row is drawn at 0.5 opacity; `ProjectRows` shows `label`, `ProjectStateDot`, `rowDetail(note:step:)` (the note in the waiting amber), `hostWord`, `agoWord`, then each subagent indented 16 pt with a `ProjectCatView` of the project's coat at head 12 (Plan call: a still small cat, not the kitten engine) and `subagentWord(type)`; `ProjectsScreenContent` scrolls vertically, one section per project (cat 20, name, `waitingWord` when > 0), `ProjectsLayout.emptyScreen` when there is none; `ProjectsBadgeView` is `ShelfBadgeView`'s shape in `Theme.State.color["approval"]` with black text and `badgeLabel` for accessibility; `ProjectKittenLayer` maps rows to `CatKittens.Kitten(id:, type:, session: nil, state: approval → .approval else .working, born: 0, last: 0)` and draws them with `CatKittenDraw.draw` as `KittenLayerView` does, in a `TimelineView` paused unless `active`. Every `TimelineView` in this file has `paused: !active` (or `!animate`).
- [ ] **Step 4: Run** `bash scripts/check-projects-render-private.sh` and `bash scripts/render-projects.sh --all --out "${TMPDIR:-/tmp}/p-mac-pics"`. Expected: every check `✓`; one `wrote …` line per picture, exit 0. Look at each picture: no `/` in any text, nothing clipped at 7 projects, the amber count clear of the shelf badge and the grid.
- [ ] **Step 5: Commit** the views, the two render files and the privacy check: `feat(projects): the views and their pictures (P-mac)`.

---

### Task 7: Owner checkpoint 1: the pictures

**Files:** none (the PNGs go to `.claude/checkpoints/p-mac/`, gitignored).

- [ ] **Step 1:** Run `bash scripts/render-projects.sh --all --out .claude/checkpoints/p-mac` and `node scripts/print-projects-tables.mjs > .claude/checkpoints/p-mac/rules.txt` (the contract's tables, for reference).
- [ ] **Step 2:** Send the owner (through the main session) the list of pictures with what to judge: the Claude-only card and pills against the shipping overview's style; the folded with-other-agents card (only the chevron and the count are new); the expanded section's height (92 pt) and its row of three; the screen's rows and empty state; the peek's place; the badge's place beside the shelf badge; the Plan calls of this plan that change something visible (cells and "+N", the badge's place, the step words without commands, the integrations in the Claude-only grid, the peek inside the island).
- [ ] **Step 3:** Wait for the owner's answer. Changes to look or wording go back to Task 3 or 6 before Task 8 starts.

---

### Task 8: The hook path and the per-session jump

**Files:**
- Create: `NotchBuddy/Sources/App/ProjectsModel+App.swift`, `tests/ProjectsWiringTests.swift`, `scripts/test-projects-wiring.sh`
- Modify: `NotchBuddy/Sources/App/HookServer.swift` (three feeds; `questionSessionId`), `NotchBuddy/Sources/App/AppState.swift` (`var questionSessionId: String = ""` beside `questionPillId`), `NotchBuddy/Sources/App/AgentTarget.swift` (a new function), `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (xcodegen)

**Interfaces:**
- Consumes: `ProjectsModel` (Task 5), `Sidekick.realHome`, `AppState.sessionHosts`, `HookOrigin.desktopBundleId`.
- Produces:

```swift
extension ProjectsModel {
    static let shared: ProjectsModel   // home: Sidekick.realHome; now: wall-clock ms (Date().timeIntervalSince1970 * 1000); schedule: one DispatchWorkItem on .main with asyncAfter(deadline:), returning its cancel
    func feedFromHook(payload: [String: Any], waitIn: String?)   // feed, then relayout(open: AppState.shared.mode == .expanded), so the last project ending while open drops the section and its height at once
}
enum AgentTarget { @MainActor static func bringForward(session sessionId: String) }   // new, below bringForward(pillId:)
// AppState
var questionSessionId: String
```

- [ ] **Step 1: Write the failing `tests/ProjectsWiringTests.swift`** (the `SidekickWiringTests` helpers: `source`, `count`, `at`, `code`). Pins:
  - `count("ProjectsModel.shared.feedFromHook(payload: payload, waitIn: nil)", in: hooks) == 3`; `feedFromHook`'s body is `feed(payload: payload, waitIn: waitIn)` followed by `relayout(open: AppState.shared.mode == .expanded)`.
  - In `processEvent`: the feed comes after `ClaudeHookRouting.route(payload: payload` (inside `#if !APPSTORE`) and before `if let pending = state.pendingApproval, agentId == pending.pillId {`.
  - In `processPermissionRequest` and in `processQuestionRequest`: the feed comes after that handler's `ClaudeHookRouting.route(payload: payload` and **before** its `if HookOrigin.answersAskAtOnce(route: route, rawAgent: rawAgent) {`.
  - `processQuestionRequest` sets `state.questionSessionId = sessionId` next to `state.questionPillId = pillId`.
  - `AgentTarget.swift` contains `static func bringForward(session sessionId: String)` after `let vscodeBundleId = "com.microsoft.VSCode"`'s first occurrence, reads `AppState.shared.sessionHosts[sessionId]`, and still has exactly four `"            #if !APPSTORE\n"` (12 spaces).
  - No view or controller file (`IslandViewContent.swift`, `IslandRootView.swift`, `KittenViews.swift`, `BotCanvasView.swift`, `AppDelegate.swift`, `IslandWindowController.swift`, `CatSettingsSection.swift`, `ProjectsViews.swift`, `ProjectsScreen.swift`) contains `.registry` or `.cwd` (none does today): the registry and the paths stay inside `ProjectsModel*.swift`, `ProjectsRegistry.swift` and `ProjectsSnapshot.swift`. Later tasks keep this pin green.
  - `ProjectsModel+App.swift` is the only Projects file with `asyncAfter`, it has exactly one, and no Projects file has `Timer`, `Task.sleep`, `appendAppLog`, `nbLog`, `print(` or `UserDefaults`.
- [ ] **Step 2: Write `scripts/test-projects-wiring.sh`** (compile `tests/CatTestSupport.swift tests/ProjectsWiringTests.swift`). Run it: it fails.
- [ ] **Step 3: Implement.** Add the feed line once in each handler at the places the pins name (the comment above it: the registry reads every Claude Code event, including a Claude App request that is answered "ask" just below). Add `questionSessionId`. Write `bringForward(session:)`: the host is `AppState.shared.sessionHosts[sessionId] ?? .noApp`; the Claude app by bundle ID as the pill's route does (`openApplication`), else (GitHub build, inside an 8-space `#if !APPSTORE`) activate the running app with that bundle ID, else VS Code's route, the same three lines as the pill's. Write `ProjectsModel+App.swift`'s `shared`. Run `cd NotchBuddy && xcodegen`.
- [ ] **Step 4: Run** `bash scripts/test-projects-wiring.sh`, every `scripts/test-*-wiring.sh`, `scripts/test-u1-wiring.sh`, `bash scripts/test-hook-origin.sh`, then `cd NotchBuddy && xcodebuild -scheme NotchBuddy -configuration Debug build CODE_SIGNING_ALLOWED=NO | tail -3`. Expected: all pass, `** BUILD SUCCEEDED **`.
- [ ] **Step 5: Commit** (with `project.pbxproj`): `feat(projects): feed the registry from every Claude Code hook, and jump to a session's app (P-mac)`.

---

### Task 9: The Projects screen: `.projects`, the folder icon, the menu-bar item, ⌃⌥P, the marker

**Files:**
- Create: `NotchBuddy/Sources/App/ProjectsScreen.swift`
- Modify: `IslandTypes.swift` (`case projects` after `sidekick`; `viewLayouts[.projects] = ViewLayout(height: 240, botX: 54, botY: nil, botDiameter: 46, agentMode: .none)`), `IslandViewContent.swift` (the dispatch), `IslandRootView.swift` (`TabButton(icon: "folder.fill", view: .projects, state: state)` after the `plus` tab), `IslandWindowController.swift` (`openProjects()`, the `.projects` hot key), `AppDelegate.swift` (the menu item, a `projectsItemTag` beside `shelfItemTag`), `ShortcutLogic.swift` (`projects`: the case, `displayName`, `enabledByDefault`, `offAtFirstNote`, `defaults`), `ProjectsModel+App.swift` (the `$mode` sink), `tests/ShortcutTests.swift`, `tests/HotKeyCenterTests.swift`, `tests/ProjectsWiringTests.swift`, `project.pbxproj`

**Interfaces:**
- Consumes: `ProjectsScreenContent` (Task 6), `ProjectsModel.shared` (Task 8), `AgentTarget.bringForward(session:)`, `ProjectsLayout.menuTitle`.
- Produces:

```swift
struct ProjectsScreenHost: View   // ProjectsScreenContent(view: model.appView(), active: state.mode == .expanded && state.view == .projects, onRow:)
extension ProjectsModel { func appView() -> PJView }   // view(projectCats: CatSettingsStore.shared.projectCats, mainCat: CatSettingsStore.shared.settings.character)
// IslandWindowController
func openProjects()        // fsm.openedExternally(); expand(to: .projects)
// ShortcutAction
case projects              // appended LAST; ⌃⌥P (keyCode 35, ctrlOpt); off by default; displayName "Open Projects"; offered in the App Store build
```

- [ ] **Step 1: Update the failing tests first.** `tests/ShortcutTests.swift`: `allCases.last == .projects`; the off-by-default set gains `.projects`; the two "tried" lists gain `.projects` at the end; `ShortcutLogic.hotKey(for: .projects, in: ud) == ShortcutSpec(keyCode: 35, nsFlags: ctrlOpt)` and off; `ShortcutAction.projects.rawValue == "projects"` and `displayName == "Open Projects"`; offered with `appStore: true`. `tests/HotKeyCenterTests.swift`: `fKeys` gains an eleventh key, `120` (F2, held with all four modifiers like the others; the file already uses 90 and 96 elsewhere); `actions.count == 10` becomes `11` ("eleven actions besides the island shortcut"); "all eleven are registered" becomes "all twelve"; both `center.registered.count == 10` ("the others stay" and "all but the refused one are registered") become `11`; the six on at first stay six. `tests/ShortcutTests.swift` also: `allCases.last == .wardrobe` becomes `.projects`; "all eleven are on" becomes "all twelve"; `.projects` gains an `offAtFirstNote` check in the shelf's style (`offAtFirstNote?.contains("Projects") == true`), and the "has no note" loop (line 117) gains `&& action != .projects`; the App Store counts stay (six and five on at first: `projects` is off). `tests/ProjectsWiringTests.swift`: `IslandViewContent` builds `ProjectsScreenHost()` only inside `if state.view == .projects`; the header has the folder `TabButton` after `TabButton(icon: "plus", view: .upload, state: state)`; `AppDelegate` sets the item's title with `ProjectsLayout.menuTitle(` in `menuNeedsUpdate`; the hot key's `case .projects:` folds when the island already shows `.projects`, else `openWithKeyboard(.projects)`; `ProjectsModel.marker` is referenced by `ProjectsScreen.swift` (so it is linked in every build); `ProjectsScreenHost` passes `active: state.mode == .expanded && state.view == .projects`; `feedFromHook` (Task 8) still ends with `relayout(open: AppState.shared.mode == .expanded)`.
- [ ] **Step 2: Run** `bash scripts/test-shortcuts.sh; bash scripts/test-hotkeys.sh; bash scripts/test-projects-wiring.sh`. Expected: failures naming `projects`.
- [ ] **Step 3: Implement.** The menu item `Projects` with a tag of its own beside the Shelf item, titled `ProjectsLayout.menuTitle(model.appView().projects.count)` in `menuNeedsUpdate`, action `openProjects`. A row's click: if `AppState.shared.pendingApproval?.sessionId == id`, expand to `.approval`; else if a question is pending and `questionSessionId == id`, expand to `.question`; else `AgentTarget.bringForward(session: id)`. The `$mode` sink in `ProjectsModel+App.swift` calls `islandExpanded(mode == .expanded)` and, when not expanded, `refreshLayout(activePills: [mainPillId] + activeIntegrations, open: false, focusId: focusId)`; it also refreshes on `$focusId` (`relayout`), and `feedFromHook` relayouts after each feed. ShortcutLogic: the default in `defaults` (`.projects: ShortcutSpec(keyCode: 35, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥P`), `enabledByDefault` false written as a line of its own, `case .projects: return false`, because `tests/WardrobeWiringTests.swift` line 83 pins the literal `case .toggleIsland, .openChat, .jumpToTerminal, .shelf, .wardrobe: return false` (and `offAtFirstNote`'s nil list likewise stays as it is, with `case .projects:` returning the note on its own lines), `offAtFirstNote` "Off at first: turn it on to open Projects with one key.". The row in Settings → General → Shortcuts comes from `ShortcutLogic.available()` (`ShortcutsSettingsView`), so no view changes; the control map's `shortcuts.global` already covers `shortcut.<id>.*` (its `was` text, the spec's wording, keeps "(11 actions)": Plan call 24). Run `xcodegen`.
- [ ] **Step 4: Run** the three tests, every wiring script, `bash scripts/test-settings-map.sh`, the Debug build, and `bash scripts/render-settings.sh --page general --tab shortcuts --out "${TMPDIR:-/tmp}/p-mac-shortcuts"`. Expected: pass, `** BUILD SUCCEEDED **`, and the 415 pt picture shows "Open Projects" with its off note, words whole.
- [ ] **Step 5: Commit**: `feat(projects): the Projects screen, its folder icon, menu item and shortcut (P-mac)`.

---

### Task 10: The overview's two layouts, the island height, the big cat's coat, state and kittens

**Files:**
- Modify: `IslandViewContent.swift` (`OverviewView`), `IslandRootView.swift` (`islandHeight` on `panelShown`, the two `BotCanvasView` coats, `BotPlacement` observing the model, the content frame's `isTall`), `BotCanvasView.swift` (its four reads of `state.effectiveState` become `state.bigCatState`; it observes the model), `IslandWindowController.swift` (`islandSize`), the free function `botPosition` (in `IslandRootView.swift`), `KittenViews.swift` (`KittenPlacement`), `ProjectsModel+App.swift`, `tests/CatWiringTests.swift` (line 50's pin, on purpose), `tests/DesktopCatWiringTests.swift` (line 63's pin, on purpose), `tests/ProjectsWiringTests.swift`

**Interfaces:**
- Consumes: Tasks 3, 5, 6, 9 (`ProjectsLayout.usesProjects/panelShown/gridCells/panelCells/bigCoat/bigState/extraHeight/panelExtra`, `ProjectsModel.shared.select/bigCard/panelOpen/panelShown/layout`, `ProjectPillGrid`, `ProjectBigCard`, `ProjectsPanel`, `ProjectKittenLayer`, `AgentTarget.bringForward(session:)`).
- Produces:

```swift
extension AppState {
    var bigCatCoat: String { get }                 // ProjectsLayout.bigCoat(castCoat: cast.big.cat, usesProjects:, expandedOverview: mode == .expanded && view == .overview, projectCat: big card's cat)
    var bigCatState: BotState { get }              // BotState(rawValue: ProjectsLayout.bigState(castState: effectiveState.rawValue, usesProjects:, expandedOverview:, projectState: big card's state)).shown(asleep: catAsleep), else effectiveState
    var projectKittens: [PJSubagentRow]? { get }   // the big card project's subagents (all its sessions'), only while the overview uses projects; else nil
}
// usesProjects here is ProjectsLayout.usesProjects(layout:focusId:projectCount:twoCats: cast.second != nil)
```

- [ ] **Step 1: Write the failing pins** in `tests/ProjectsWiringTests.swift`: `islandSize` adds `ProjectsLayout.extraHeight` only for `view == .overview`; `botPosition` computes the overview cat's centre from `min(islandH, layout.height)`, so the cat does not move when the section opens; `IslandRootView` animates `islandHeight` with `openSpring` on `.onChange(of: projects.panelShown)` and both `BotPlacement` branches use `BotCanvasView(state: state, cat: state.bigCatCoat`; `bigCatCoat` starts from `cast.big.cat`; `BotCanvasView.swift` has no `state.effectiveState` left and reads `state.bigCatState` in its four places (the collar, the emote gate, the `.onChange`, the forced `setState`), and `bigCatState` falls back to `effectiveState`; `BotPlacement`, `KittenPlacement` and `BotCanvasView` each hold `@ObservedObject private var projects = ProjectsModel.shared` (so a pill click changes the coat, the kittens and the state at once); `KittenPlacement` keeps its existing lines and adds one branch that, when `state.projectKittens` is non-nil, draws `ProjectKittenLayer` for the big cat **instead of** the big cat's own kitten layer (never both), and draws nothing while `state.desktopPhase.notchEmpty`; in `IslandContainer`'s view stack `isTall` gains `|| (v == .overview && projects.panelShown)` (like `(v == .shelf && active)`), so the 98 pt content frame grows with the section; every Projects view in the overview gets `active: state.mode == .expanded && state.view == .overview`; `usesProjects(` is always called with `twoCats: state.cast.second != nil`; `OverviewView` shows `ProjectBigCard` and `ProjectPillGrid` only when `ProjectsLayout.usesProjects(` is true and the shipping left and right cards otherwise; the chevron's button toggles `panelOpen` with `withAnimation(.spring(response: 0.3, dampingFraction: 0.8))` (the island's existing spring for view switches). Change `tests/CatWiringTests.swift` line 50 and the second half of `tests/DesktopCatWiringTests.swift` line 63 to count `"BotCanvasView(state: state, cat: state.bigCatCoat"` twice (labels unchanged in meaning: the big cat's coat comes from the cast, through the Projects rule; line 63 keeps its `if !state.desktopPhase.notchEmpty { catSpot }` half as it is). `CatWiringTests` line 119's counts (one `KittenPlacement(state: state` in the island, one `CatIslandLayout.kittenParents(` in `KittenViews.swift`) must stay 1 and 1: the project branch goes inside the existing `KittenPlacement`. Run them: they fail.
- [ ] **Step 2: Implement the Claude-only layout.** In `OverviewView`, when `ProjectsLayout.usesProjects(layout:focusId:projectCount:twoCats:)` holds (`twoCats: state.cast.second != nil`): the left card's content is `ProjectBigCard(project: big card, animate: expanded, onOpen: { bringForward(session: newest session of that project) })` (the card's tap and its ↗), the right card is `ProjectPillGrid(cells: gridCells(projects: view ids, otherPills: the cast's pills that are not integration_claude), …)` where a `.pill` cell draws the existing `AgentPill` with the cast's coat and its existing tap, a `.project` tap calls `select`, `.more` opens `.projects`. Otherwise everything is exactly as it ships (Plan call 7: today's card when no project is live or the focus is another pill; Plan call 26: and in Two cats mode).
- [ ] **Step 3: Implement the with-other-agents layout.** In the Claude Code card's title row (only for `agent.id == "integration_claude"`, only with ≥ 1 live project, only when not `usesProjects`): after the source label, `projectsWord(n)` and, when > 0, ` · waitingWord(m)` in the amber, and a `chevron.down` / `chevron.up` button (9 pt, `#8E939C`) before the step counter; a tap on the card's `CardBackground` layer toggles too. Under the `HStack` of the two cards, `ProjectsPanel` when `ProjectsModel.shared.panelShown`, height `ProjectsLayout.panelExtra`, with `.transition(.opacity.combined(with: .move(edge: .top)))`. `refreshLayout` runs on `panelOpen` changes too, so `panelShown` and `extraHeight` follow `panelShown(panelOpen:layout:focusId:projectCount:)`.
- [ ] **Step 4: Implement the height, the coat, the state and the kittens** as the pins say. The big cat follows the big card's project entirely in the Claude-only card (owner's answer 3: one cat, one project). With no pin and no click the big card is the most recent project (`bigCardOf`), so a project that starts waiting becomes the big card and the cat shows it; with a calm project pinned, other waiting projects still show by their pulsing amber dot, the amber count and the notch card. With other agents, in Two cats mode, or folded, the big cat is exactly today's. `islandSize`'s `.expanded` branch: `layout.height + (view == .overview ? ProjectsLayout.extraHeight : 0)` (the question's branch first, unchanged).
- [ ] **Step 5: Run** `bash scripts/test-projects-wiring.sh`, `bash scripts/test-cat-wiring.sh`, `bash scripts/test-cat-desktop-wiring.sh`, every other wiring script, `bash scripts/test-island-wing.sh`, `bash scripts/test-island-outside-click.sh`, and the Debug build. Expected: all pass. Run `bash scripts/render-projects.sh --island agents-open --out "${TMPDIR:-/tmp}/p-mac-pics"` again (unchanged views).
- [ ] **Step 6: Commit**: `feat(projects): project pills when Claude is alone, the expandable Claude panel otherwise (P-mac)`.

---

### Task 11: The peek, Pin / Unpin, the compact waiting badge

**Files:**
- Modify: `IslandViewContent.swift` (the peek overlay), `IslandRootView.swift` (the badge; the named coordinate space `"nm.island"` on `IslandContainer`'s root `ZStack`), `IslandWindowController.swift` (the right-click branch, the badge click), `ProjectsModel+App.swift` (`ProjectsHits`), `tests/ProjectsWiringTests.swift`

**Interfaces:**
- Consumes: `ProjectsLayout.badgeShown/badgeCenter/badgeHitRect/peekDwell/pinTitle`, `ProjectsBadgeView`, `ProjectsPeek`, `ProjectsModel.togglePin/isPinned`, `openProjects()`.
- Produces:

```swift
@MainActor enum ProjectsHits { static var pillFrames: [String: CGRect] }   // project id → frame in "nm.island" coordinates; written through ProjectPill's onFrame at the island's call sites, cleared when the island folds
// IslandWindowController
private func showProjectPinMenu(for event: NSEvent) -> Bool   // before showWardrobeMenu in the right-click monitor
private func clickedProjectsBadge(_ event: NSEvent) -> Bool
```

- [ ] **Step 1: Write the failing pins** in `tests/ProjectsWiringTests.swift`: the right-click monitor asks `showProjectPinMenu(for: event)` first and `showWardrobeMenu(for: event)` second; `showProjectPinMenu` sets `wardrobeMenuOpen = true` with a `defer` that clears it, pops one `NSMenu` whose single item's title is `ProjectsLayout.pinTitle(`, and returns false unless `state.mode == .expanded` and the point is in a `ProjectsHits.pillFrames` rectangle; the mouse-up monitor checks `clickedProjectsBadge(event)` (then `openProjects()`) before `clickedShelfBadge(event)`; the island draws `ProjectsBadgeView` only inside `if ProjectsLayout.badgeShown(compact: state.mode == .compact,` with `.opacity(state.wingYielded ? 0 : 1)`; `ShelfBadge.isShown` still occurs once in `IslandRootView.swift`; no Projects line touches `wingAlert`, `isHeldOpen`, `isHoverHeld`, `fsm.reveal`, `hookExpand`, `agentActivity`, `userInteracted` or `IslandTuckAway`; the peek's dwell is one `Task.sleep` per hover-in, cancelled on hover-out, and the peek is a view inside the island (no `NSPopover`, no `.popover(`, no new `NSWindow`/`NSPanel`).
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement the peek.** `OverviewView` keeps `@State var peekId: String?`; a pill's `onHover(true)` starts `Task { try? await Task.sleep(for: .milliseconds(Int(ProjectsLayout.peekDwell * 1000))); if still hovering, peekId = id }`, `onHover(false)` cancels it and clears `peekId`. `ProjectsPeek` is drawn over the left card (Claude only) or over the two cards (from the expanded section), the same 322 × 84 card frame, inside the island (Plan call: no popover window, so the panel's hit testing and hover rules are unchanged). It hides when the island folds: `.onChange(of: state.mode)` sets `peekId = nil` and cancels the dwell task when the mode leaves `.expanded` (pinned).
- [ ] **Step 4: Implement Pin / Unpin.** `ProjectPill` already reports its frame in `"nm.island"` through its `onFrame` closure (Task 6); the island's call sites (`ProjectPillGrid` and `ProjectsPanel` in `OverviewView`) pass `onFrame: { id, rect in ProjectsHits.pillFrames[id] = rect }`, so `ProjectsViews.swift` never names `ProjectsHits` (the render script does not compile `ProjectsModel+App.swift`). The right-click monitor converts `event.locationInWindow` to island coordinates with `currentIslandFrame` (x minus its `minX`, y measured down from its `maxY`) and, on a hit, pops `NSMenu` with one item, "Pin" or "Unpin", whose action calls `ProjectsModel.shared.togglePin(id)`.
- [ ] **Step 5: Implement the badge** at `ProjectsLayout.badgeCenter(islandWidth:height:)`, after `CompactMiniGrid` and beside the shelf badge's block, with `ProjectsModel.shared.appView().waiting` as its count (read when the island draws: no timer, Plan call 6). `clickedProjectsBadge` mirrors `clickedShelfBadge` with `ProjectsLayout.badgeHitRect`.
- [ ] **Step 6: Run** every wiring script (`test-shelf-wiring.sh`, `test-wardrobe-wiring.sh`, `test-u1-wiring.sh`, `test-island-wing-wiring.sh`, `test-island-tuck-away-wiring.sh` included), `bash scripts/test-island-outside-click.sh`, `bash scripts/test-shelf-drop.sh`, `bash scripts/render-projects.sh --badge --peek --out "${TMPDIR:-/tmp}/p-mac-pics"` and the Debug build. Expected: all pass.
- [ ] **Step 7: Commit**: `feat(projects): peek on hover, pin a project, and the compact waiting count (P-mac)`.

---

### Task 12: Settings → Cat → Agents' cats: Project cats, and the control map

The spec's "Settings → Cat → Display" is today the **Agents' cats** tab of the Cat page (`SettingsRoute.tabs(.cat)` = Look, Outfits, Personality, Agents' cats; the Display card, "Your two cats" and "Cats for your agents" live there). "Project cats" is a card on that tab, after the agents' list, built from the Settings kit like its neighbours (Plan call 22).

**Files:**
- Modify: `NotchBuddy/Sources/App/CatSettingsView.swift` (an `init` parameter `projects: [ProjectCatList.Live] = []`, appended after `tab:`; `projectsGroup` and `projectRow`), `NotchBuddy/Sources/App/CatSettingsSection.swift` (observes `ProjectsModel.shared`, passes the live projects), `NotchBuddy/Sources/App/SettingsMap.swift` and `tests/fixtures/settings/controls.json` (the `cat.display` control gains the card and the key), `tests/SettingsMapTests.swift` (the frozen list gains the key), `scripts/render-settings.swift` (`SettingsSamples.catView` gains `state:` and sample projects), `scripts/render-cat-settings.sh` (`$APP/ProjectsLayout.swift` before `$APP/CatSettingsStore.swift`, beside Task 4's two files, outside the run `SettingsWiringTests` pins), `tests/ProjectsWiringTests.swift`

**Interfaces:**
- Consumes: `ProjectCatList.rows/Live/Row`, `CatSettingsStore.projectCats/setProjectCat/resetProjectCat` (Task 4), `ProjectsModel.appView()` (Task 9), `ProjectsLayout.emptySettings` (Task 3); in `CatSettingsView`: `CatPreviewView(id:head:active:config:)`, the private `catPicker(_:)`, `SettingsCard`, `HelpText`, `WrapRow`, `active`, `store`, `id` (the Main cat).
- Produces: `CatSettingsView(store:alwaysActive:agents:lookup:wardrobeDay:tab:projects:)`; `SettingsSamples.catView(tab:state:stress:)` in the render tool.

- [ ] **Step 1: Write the failing pins.**
  - `tests/ProjectsWiringTests.swift`: `CatSettingsSection` has `@ObservedObject private var projects = ProjectsModel.shared`, builds `ProjectCatList.Live(catKey: $0.catKey, name: $0.name)` from `projects.appView().projects` (no `cwd`, no root: only `catKey` and `name`) and passes `projects:`; in `CatSettingsView`'s body `projectsGroup` comes after `if store.display.mode == .perAgent { agentsGroup }` and before the closing of `if shows(.agentCats) {`, on a line of its own (so it shows in every display mode: Plan call 18); `projectsGroup` holds `SettingsCard("Project cats")`, `HelpText(ProjectsLayout.emptySettings)` under `if rows.isEmpty`, and `ForEach(rows, id: \.catKey)`; `projectRow` holds `CatPreviewView(id: row.cat, head: 28, active: active, config: store.config)`, `catPicker(Binding(get: { row.cat }, set: { store.setProjectCat($0, for: row.catKey) }))`, and `Button("Reset") { store.resetProjectCat(for: row.catKey) }` inside `if row.stored`, all three inside one `WrapRow {`; the text between `private var projectsGroup` and the end of `projectRow` has no `lineLimit` and no `.frame(width:` on the name, and `CatSettingsView.swift` keeps exactly one `.lineLimit(1)` (today's, in the Main cat card) and no `GroupBox(`.
  - `tests/SettingsMapTests.swift`: `frozen` gains `("cat.projectCat.<catKey>", "defaults", "\"cat.projectCat.\"")` after the `cat.agentCat.<pillId>` entry.
  - Run `bash scripts/test-projects-wiring.sh; bash scripts/test-settings-map.sh`. Expected: the new pins fail, and the map test fails with `cat.projectCat.<catKey> (defaults): one control` (0).
- [ ] **Step 2: Register the key and the card** (Plan call 23: inside the existing `cat.display` control, never a new control, because `windows/scripts/settings-tests/map.test.mjs` pins the map at 52 entries and this plan never edits `windows/`). In `SettingsMap.swift`, `cat.display`'s `homes` gains `h(.cat, .agentCats, "Project cats")` last and its `mac` gains `d("cat.projectCat.<catKey>")` last; `was` is unchanged. In `controls.json`, the same two additions in that control's `"homes"` and `"mac"` arrays, in the same order and the file's one-object-per-line style; `"winHomes"` and `"win"` are not touched (P-tauri adds the Windows key to this same control). The card name must be a string literal in a Settings file: Step 3 writes it.
- [ ] **Step 3: Implement the card.** `projectsGroup`: `let rows = ProjectCatList.rows(live: projects, stored: store.projectCats, main: id)`; `SettingsCard("Project cats") { if rows.isEmpty { HelpText(ProjectsLayout.emptySettings) }; ForEach(rows, id: \.catKey) { projectRow($0) }; HelpText("Each project wears the cat you give it, by its folder's name. A project without one gets a cat that is not the Main cat.") }`. `projectRow` in `agentRow`'s shape without the colour dot: a leading `VStack(alignment: .leading, spacing: 6)` with `Text(row.name).fixedSize(horizontal: false, vertical: true)` (the name wraps, never cut) and the `WrapRow { preview .frame(width: 44, height: 36); picker; Reset }` (so at 415 pt the Reset button drops to its own line rather than being cut), `.frame(maxWidth: .infinity, alignment: .leading)`. A stored-only row looks like a live one (its name is the stored folder name). In `CatSettingsSection`: the observed model and the `projects:` argument, nothing else changes (`tab: tab` stays as it is, pinned by `SettingsWiringTests`).
- [ ] **Step 4: The pictures' samples.** In `scripts/render-settings.swift`, `catView(tab:stress:)` becomes `catView(tab:state:stress:)` (its call site in `page(_:tab:state:stress:)` passes `state`): for `state == "empty"` no project at all (the empty sentence shows); otherwise two live projects, `ProjectCatList.Live(catKey: "notchmeow", name: "notchmeow")` and `Live(catKey: "site", name: "site — a")`, and `store.setProjectCat("leo", for: "old-site")` (a stored-only row with Reset); with `stress`, the first live name is `"a-rather-long-project-folder-name-for-the-column"`. Plain sample values only: no `AppState`, no `ProjectsModel`, no `UserDefaults` (`scripts/check-settings-render-private.sh`).
- [ ] **Step 5: Run** `bash scripts/test-projects-wiring.sh`, `bash scripts/test-settings-map.sh`, `bash scripts/test-settings-wiring.sh`, `bash scripts/test-cat-wiring.sh`, `bash scripts/check-settings-render-private.sh`, `node --experimental-strip-types --test windows/scripts/settings-tests/map.test.mjs` (read-only: it must still pass with 52 entries), `bash scripts/render-cat-settings.sh --mode perAgent --out "${TMPDIR:-/tmp}/p-mac-cat.png"` (it must still compile), then `bash scripts/render-settings.sh --page cat --tab agentcats --out "${TMPDIR:-/tmp}/p-mac-settings"` and the same with `--states empty` and with `--stress`, and the Debug build. Expected: all pass, `** BUILD SUCCEEDED **`; at 415, 720 and 1100 pt the card shows every name whole and no cut button, the empty picture shows the empty sentence, the stress picture wraps the long name.
- [ ] **Step 6: Commit**: `feat(projects): Settings → Cat → Agents' cats gains Project cats (P-mac)`.

---

### Task 13: `fake-projects-events.py` and its test

**Files:**
- Create: `scripts/fake-projects-events.py`, `scripts/test-fake-projects-events.sh`

**Interfaces:**
- Consumes: `tests/fixtures/mac/projects-scenarios.json` (Task 5), `tests/kitten_socket_server.py`.
- Produces: `python3 scripts/fake-projects-events.py [--list] [--scenario NAME|all] [--print] [--sock PATH] [--speed X] [--permission-timeout S]`, in the shape of `scripts/fake-subagent-events.py` (default socket `~/Library/Application Support/NotchMeow/nm.sock`; one connection per event; a `cwd` starting with `~` expanded with `os.path.expanduser`; `waitIn` steps print a note that the focus-awareness feature, not this script, decides a step-back, and send the payload unchanged).

- [ ] **Step 1: Write `scripts/test-fake-projects-events.sh`** in the shape of `scripts/test-fake-terminal-events.sh` (its own socket under a short temp folder, `tests/kitten_socket_server.py`, the server's PID saved and killed in the `trap`). Checks: `--list` names the five scenarios; `--scenario two-projects --speed 100000` sends that scenario's `hook_event_name`s in order; every payload carries a `session_id` and a `cwd`; `--scenario collide-and-home` sends a `cwd` equal to `$HOME` (expanded) and none with a literal `~`; `--print` sends nothing (the received file stays empty); `--scenario nope` exits 2.
- [ ] **Step 2: Run it to see it fail** (the script is missing).
- [ ] **Step 3: Write the script.** Standard library only; `python3 -I` safe.
- [ ] **Step 4: Run** `bash scripts/test-fake-projects-events.sh`. Expected: every check `✓`.
- [ ] **Step 5: Commit**: `test(projects): the owner's scripted Projects run (P-mac)`.

---

### Task 14: Owner checkpoint 2: the scripted run on a Debug build

**Files:** none.

- [ ] **Step 1:** The main session asks the owner (or, if the owner asks it to, does it by hand on the owner's Mac) to run the worktree's Debug build and then `python3 scripts/fake-projects-events.py --scenario all`. What to look at, scenario by scenario: `two-projects` (two pills, the side session's worktree name, the kittens beside the big cat, finished then idle), `claude-app-wait` (the amber dot moves the project first and pulses, "Waiting in Claude App" in the screen, the compact count, the notch never opens by itself), `collide-and-home` (`site — a`, `site — b`, `Home`), `other-agent` (the island switches to today's two panels at the next fold, the chevron and the expanded section), `end` (the project leaves at once). Also: Pin / Unpin on a right-click, the peek after 0.4 s, a row's click bringing its app forward, ⌃⌥P once turned on in Settings → General → Shortcuts, and Settings → Cat → Agents' cats → Project cats (a coat change shows on the pill at once; Reset on a stored row).
- [ ] **Step 2:** Changes go back to the owning task before Task 15.

---

### Task 15: Docs, CI, binary markers, final checks

**Files:**
- Modify: `scripts/check-app-binary.sh` (`has NM_PROJECTS_VIEW_ACTIVE` in every build, in the shelf block's style), `.github/workflows/build.yml` (one step per new script, after "Projects contract": rules, registry, layout, cats, model, leak, wiring, fake events, and `check-projects-render-private.sh`), `CLAUDE.md` (one bullet, "Sub-project P on the Mac (Projects)", in the style of the G1 and I Mac bullets: the files, the pins, the scripts, "in every build", the marker, memory-only registry, `waitIn` from the focus-awareness plan), `ARCHITECT.md` (flow 7: the Mac is built, in the style of flow 6's "On the Mac it is built"), `docs/SPEC.md` (a new "### Les projets (sous-projet P)" after "Le compagnon" in French: the two layouts, the screen, the four polish items, what is never shown or kept, and the "Project cats" card in Réglages → Cat → Agents' cats; a `projects` row in the views table after the `shelf` row (`| \`projects\` | 240 | 54, 46 | l'écran Projets (sous-projet P) : une section par projet (chat, nom, nombre en attente), ses sessions en lignes, les sous-agents en retrait ; état vide | — |`); the ⌃⌥P row in the table of 13.1 and its line under it, in the `shelf` row's style)

- [ ] **Step 1:** Make the edits.
- [ ] **Step 2: Run the final checks.** Every `scripts/test-projects-*.sh`, `scripts/test-fake-projects-events.sh`, `scripts/test-projects-contract.sh`, every `scripts/test-*-wiring.sh`, `scripts/test-u1-wiring.sh`, `scripts/test-shortcuts.sh`, `scripts/test-hotkeys.sh`, `scripts/test-cat-settings-store.sh`, `scripts/test-settings-map.sh`, `scripts/test-settings-rules.sh`, `scripts/check-settings-render-private.sh`, `scripts/check-projects-render-private.sh`, `node --experimental-strip-types --test windows/scripts/settings-tests/map.test.mjs`, `scripts/test-island-wing.sh`, `scripts/test-island-outside-click.sh`, `scripts/test-island-tuck-away.sh`, `scripts/test-shelf-drop.sh`, `scripts/check-no-leftovers.sh`, `git diff --quiet main -- shared tests/fixtures/projects design windows && echo untouched`; the three builds with `CODE_SIGNING_ALLOWED=NO` (`-scheme NotchBuddy -configuration Debug`, `-scheme NotchBuddy -configuration Release`, `-scheme NotchMeowAppStore`, as `.github/workflows/build.yml` builds them), then `bash scripts/check-app-binary.sh <app> debug`, `… release` and `… appstore` (each must print the Projects line). Optional, about seven minutes each: `bash scripts/measure-island-cpu.sh --state compact` and `--state overview`, numbers into the report.
- [ ] **Step 3: Commit**: `docs(projects): CLAUDE.md, ARCHITECT.md, SPEC.md and CI for P-mac`.

---

### Task 16: Whole-branch review

- [ ] Dispatch `nm-reviewer-deep` over `git diff main...HEAD`, with the spec, the contract, this plan's Global Constraints and Review Focus; beside it `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` (`model: sonnet`) on the same diff, and the `security-review` skill on the privacy rules (no path, prompt or command shown, logged or stored; the feed before ask-at-once never delays the reply). Fix what they find (each fix through the owning task's agent and `nm-reviewer`), then re-run Task 15 Step 2.

### Task 17: Owner checkpoint 3

- [ ] The report to the owner: commits, test lines, build and marker lines, the pictures, the measure numbers if run, the Plan calls, and the manual checks still owed (a real Claude App session, a real terminal session with a notch card, a session closed without `SessionEnd` dimming at 30 min). Merging is the owner's call.

---

## Plan calls

1. `ProjectsRules` carries its own FNV-1a and LCG, pinned to `SK.fnv1a` and `CatRNG`: the pure files compile alone.
2. Registry times are wall-clock milliseconds (`Date()`), as the fixtures' epochs and the "… ago" labels need.
3. Step words: `SessionStepText` with the input reduced to `path`/`file_path`, PreToolUse only, `AskUserQuestion` skipped: never a command or query (the spec's anti-goal).
4. The feed is the first thing after the chat-run filter in each handler, so a Claude App request is counted before it is answered "ask"; `waitIn` is `nil` until the focus-awareness plan supplies it.
5. One one-shot tick while expanded, due at the nearest of the next minute and the next time-based boundary, so `finished` ends at 5.2 s on screen rather than up to a minute late.
6. The compact count is read when the island draws (no timer while compact), so it can lag until the next event or redraw.
7. The Claude-only layout is used only while the focus is Claude Code (or none) and a project is live; otherwise the overview is today's.
8. The Claude-only right card is the existing 2×2 grid: projects first, the remaining cells for the other pills (integrations); with more than 4 projects, 3 projects and "+N", which opens the screen.
9. The expanded section is one row of three columns (more → "+N"), 92 pt under the two panels, island height 160 → 252.
10. The peek is drawn inside the island over the cards, not in a popover window.
11. Pin / Unpin is an `NSMenu` from the existing right-click monitor, hit-tested on frames the pills report, reusing the `wardrobeMenuOpen` hold.
12. The shortcut is ⌃⌥P (key code 35), "Open Projects", off by default, in every build.
13. The menu-bar item counts live projects: "Projects (N)".
14. The `.projects` view is 240 pt high with the cat at the shelf view's place.
15. A subagent's head in the screen and the peek is a still small cat in the project's coat (Ø12), not the kitten engine; beside the big cat the real kittens are drawn.
16. (Changed by the owner, 2026-10-20.) In the Claude-only card the big cat follows the big card's project entirely: coat, kittens and state (`projectStateOf` of that project, through `ProjectsLayout.bigState`). With other agents, in Two cats mode or folded it is today's cat.
17. Host and age words: "Claude App", "VS Code", "Terminal"; "now", "N min ago", "N h ago".
18. "Project cats" shows in every display mode (on the Agents' cats tab, outside the mode conditions that pick the pair or the agents' list).
19. No Debug panel: the render script and the fake-events script cover the checks.
20. The waiting amber and the dots use `Theme.State.color`; `shared/theme.json` is unchanged.
21. The waiting badge sits in the right wing's free inner end (centre 66 pt from the island's right edge), so the shelf badge and its pins are untouched.
22. "Project cats" is a card on Settings → Cat → Agents' cats, after the agents' list: the spec's "Settings → Cat → Display" became that tab with the Settings restyle, and the agents' coats are picked there.
23. The stored key and the card join the existing `cat.display` control of the control map (`SettingsMap.swift`, `controls.json`, Mac columns only) rather than a new control: the Windows map test pins 52 entries and this plan never edits `windows/`; P-tauri adds its `win` key to the same control.
24. The `shortcuts.global` control keeps its `was` text "(11 actions)" (the restyle spec's first-column wording, not a count any test reads); `shortcut.<id>.*` already covers the new action's keys.
25. The compact badge's click mirrors the shelf badge's: with the wing rule active the right wing folds at once and passes the mouse on, so the click lands only while the wing is inactive; Projects is always reachable from the folder icon, the menu-bar item and ⌃⌥P.
26. Two cats mode keeps today's overview: `usesProjects` is false while the cast has a second cat, so the pair's layout (`CatIslandLayout`) is never mixed with the project card.

## Owner's answers (2026-10-20)

1. Claude only: the service pills keep their cells beside the project pills (Plan call 8 confirmed).
2. Step words: command and search text stay hidden (Plan call 3 confirmed).
3. The big cat in the Claude-only card follows the big card's project entirely: coat, kittens and state (Plan call 16 changed). One cat, one project: with no pin and no click the big card is the most recent project (`bigCardOf`), so a project that starts waiting becomes the big card and the cat shows it waiting; when a calm project is pinned, other waiting projects still show by their pulsing amber dot, the amber count and the approval card. With other agents the big cat is today's. Tests: Task 3 (`bigState`) and Task 5 ("the big cat follows the big card").
4. The compact amber count stays a signal (Plan call 25 confirmed); Projects opens from the folder icon, the menu-bar item and ⌃⌥P.

## Dry run

First walk, against the tree at `414d89e6` (2026-10-17):

- Checked present: `HookServer.processEvent` / `processPermissionRequest` / `processQuestionRequest`, their `ClaudeHookRouting.route` filters and `HookOrigin.answersAskAtOnce` early returns (the Sidekick feed sits after that return, so the Projects feed cannot copy its place: Review Focus 1); `SessionStepText.line(tool:input:)` (Bash keeps the command, hence Plan call 3); `CatKittens.Kitten` fields and `CatKittenDraw.draw` as `KittenLayerView` calls it; `AgentPill` and `PillBadgeView` sizes; `IslandConst.viewLayouts` (force-unwrapped, so `.projects` needs an entry); `islandSize` and `QuestionLayout`'s `nonisolated(unsafe)` static (copied for `extraHeight`); `botPosition`'s centre from `islandH` (hence the `min(islandH, layout.height)` guard); `IslandRootView`'s `ForEach(IslandView.allCases …)` stack (hence the `if state.view == .projects` guard); `ShelfBadge` geometry (grid 26…54 pt in, badge 7…21 pt in: the new badge at 59…73 pt fits); `ShortcutAction` order and `udKeyCode` naming (⌃⌥P free); `CatSettingsStore`'s `updateWardrobe` pattern and `CatDisplaySettings.load/save` prefix scan; `MemoryBacking` in `tests/CatSettingsSupport.swift`; `CT.fixture(_, dir:)`; `CatRNG` and `CatAgentCats.pickCat`; `Sidekick.realHome`; `AppState.sessionHosts`, `questionPillId`, `mainPillId`, `activeIntegrations`, `$mode`, `$focusId`; `Theme.State.color["approval"] == "#F5A524"`; `tests/kitten_socket_server.py`; the fixtures' shapes (`registry-cases.json`'s `cases`/`caps`/`presentation`, `event-cases.json`'s optional `waitIn`, absent and null `now`, `waiting` values `"x"`, `1.5`, `-1`, `activePills` given as a string).
- Changed after the walk: the feed moved before `answersAskAtOnce`; `AgentTarget` gets a new function instead of a refactor (four wiring tests pin its `case "integration_claude":` text and count four 12-space `#if !APPSTORE`); the waiting badge moved off the shelf badge's slot (three `ShelfWiringTests` pins and the grid's span); `wardrobeMenuOpen` kept by name; the big cat's coat pin named as one Task 10 updates on purpose (the refresh below found a second); `ProjectsRules` given its own FNV-1a and LCG so `test-cat-settings-store.sh` and `render-cat-settings.sh` need only two more files; the porting rules added for code points, UTF-16 order, stable sorts and `NSNumber` booleans (the fixtures exercise all four); Task 7's table command fixed to `node scripts/print-projects-tables.mjs`.
- Also fixed: `HotKeyCenterTests` registers one F key per action (10 today, a fixed list), so Task 9 names the eleventh key and the three counts it changes.
- Also fixed: the compact island's width in Task 3's test (344 pt: the 184 pt fallback notch plus 160, not 345) and Task 15's App Store build (`-scheme NotchMeowAppStore`, as CI builds it; `check-app-binary.sh` takes `debug|release|appstore`).
- Not checkable before the code exists: whether `NSMenu.popUpContextMenu` over a SwiftUI-reported frame needs a coordinate flip on a screen without a notch (Task 11's Sonnet agent checks it on the Debug build's geometry, and the owner at checkpoint 3).

### Refresh against `main` at `d9f9caca` (2026-10-20, 89 commits later)

What it builds is unchanged (spec and P-0 contract as before). Checked and changed:

- **Unchanged since `414d89e6`, re-grepped:** `HookServer.swift` (the three handlers, `ClaudeHookRouting.route(payload: payload`, `if HookOrigin.answersAskAtOnce(route: route, rawAgent: rawAgent) {`, `if let pending = state.pendingApproval, agentId == pending.pillId {`, `state.questionPillId = pillId`), `AgentTarget.swift` (four 12-space `#if !APPSTORE`, `case "integration_claude":`), `IslandRootView.swift`, `IslandWindowController.swift` (`islandSize` is still the free function there; `wardrobeMenuOpen`, `showWardrobeMenu(for: event)`, `clickedShelfBadge`, `currentIslandFrame`, `openWithKeyboard`), `KittenViews.swift`, `IslandTypes.swift` (`.shelf` 176 pt, botX 54, Ø46), `ShortcutLogic.swift` (eleven actions, `wardrobe` last, ⌃⌥P free), `ShelfBadge.swift`, `CatSettingsStore.swift`, `SessionStepText.swift`, `CatAgentCats.pickCat`, `SK.fnv1a`, `CatRNG` (a `final class` in `CatMath.swift`), `Sidekick.realHome`, `AppState.sessionHosts` (`HookOrigin.TapHost`, `.noApp`), `$mode`/`$focusId`, `QuestionLayout.height` (in `AskQuestion.swift`), `check-app-binary.sh`'s shelf block, every script and fixture Tasks 1–13 copy. `AppState.swift`, `AppDelegate.swift` and `IslandViewContent.swift` changed only in Settings lines (window size, `openFullSettings` tags) that no task touches. `git merge-base --is-ancestor 39513b7e HEAD`, `test-projects-contract.sh` and `test-settings-map.sh` pass at `d9f9caca`.
- **Settings (Task 12 rewritten):** Settings → Cat → Display is gone; Cat has Look, Outfits, Personality, Agents' cats (`SettingsRoute`, `CatSettingsView(tab:)` with `shows(_:)`, `CatSettingsSection(tab: tab ?? .look)` from `SettingsSections.swift`). The card moved to the Agents' cats tab and to the kit (`SettingsCard`, `HelpText`, `WrapRow`; no `GroupBox`, no fixed name width). New: the key's registration in `SettingsMap.swift`, `controls.json` and `SettingsMapTests.frozen`, inside `cat.display` because `windows/scripts/settings-tests/map.test.mjs` pins 52 entries (`cat.agentCat.<pillId>` is registered the same way, with the literal `"cat.agentCat."`); `SettingsWiringTests` requires each map card to be a literal in a Settings file. Pictures now from `render-settings.sh --page cat --tab agentcats` (`--states empty`, `--stress`) with plain samples (`check-settings-render-private.sh`); the old `render-cat-settings.sh --projects` part is dropped.
- **Task 4:** `render-cat-settings.sh` now carries the Settings kit files, and `SettingsWiringTests` pins that run verbatim, so the two new files go before `CatSettingsStore.swift`.
- **Task 9:** the note property is `offAtFirstNote` (not `offNote`); the default goes in `ShortcutLogic.defaults`; `HotKeyCenterTests` has a fourth count (`registered.count == 10` in the conflict check) and `ShortcutTests` has `allCases.last == .wardrobe` and "all eleven are on"; the row appears in General → Shortcuts by itself (`ShortcutLogic.available()`), checked with `render-settings.sh --page general --tab shortcuts`.
- **Task 10:** the coat pin is `CatWiringTests` line 50 (was 49), and `DesktopCatWiringTests` line 63 counts the same literal: both are named; `KittenPlacement`'s counts at line 119 must stay 1 and 1.
- **Island rules re-read:** the wing (right wing folds at once: the badge's click is the shelf badge's, Review Focus 5 and Plan call 25), the outside click (its `busy` already reads `wardrobeMenuOpen`), Open on hover (`isHoverHeld` already reads it), the tuck-away timer (predates `414d89e6`; new constraint and pin: Projects never calls `agentActivity` or `userInteracted`). `wardrobeMenuOpen` is pinned eight times in three files (was "four tests").
- **Coordination:** `2026-10-17-focus-awareness-mac.md` still does not mention Projects and is stale on Settings itself (it edits `SettingsView.swift`'s toggles); the two plans run one after the other. Base moved to `d9f9caca`; baseline and final checks gained the Settings scripts.
- **Review round (2026-10-20), applied with the owner's answers:** Plan call 16 changed (the big cat's state from the big card's project: `ProjectsLayout.bigState`, `AppState.bigCatState`, `BotCanvasView`'s four `effectiveState` reads, no test pins them); `isTall` gains the overview while the section shows (`IslandRootView.swift`'s content frame, checked at the `ForEach(IslandView.allCases` stack); `ProjectPill`/`ProjectPillGrid`/`ProjectsPanel` take `onFrame`, so `ProjectsHits` stays in the app file; the "no lineLimit" pin is scoped to the new card (`CatSettingsView.swift` line 224 keeps its `.lineLimit(1)`); `render-cat-settings.sh` gains `ProjectsLayout.swift` (called by `render-site.sh`); `ShortcutTests` line 117 and `WardrobeWiringTests` line 83 handled; Two cats keeps today's overview (Plan call 26); `feedFromHook` relayouts after every feed and the tick relayouts on fire; placements and `BotCanvasView` observe the model and the project kittens replace the big cat's own; `nextDelay` counts only boundaries after `now`, floor 50 ms; minor: no "Tests" step word, question dots amber, a `projects` row in SPEC.md's views table, publish only on visible change, a `.registry`/`.cwd` pin, `check-projects-render-private.sh`, `peekId` cleared on fold, `active` defined and pinned, the leak test's empty temp `HOME` check.

