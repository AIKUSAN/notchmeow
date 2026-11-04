# H-mac: The Desktop Cat in the macOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sub-project H on the Mac. The user drags the big cat out of the notch, or uses the menu-bar item, **⌃⌥D** or a Settings switch, and the cat lives on the desktop as a companion: a borderless floating panel that never takes focus, on every Space, click-through everywhere except the cat's body. It watches the cursor, shows its role's state badge, its agent's kittens and its collar, dances to Apple Music and sleeps like the notch cat. It flies into the notch for every approval or question and back out when they are answered. A click opens the island, a double-click sends it home, a drag moves it, and its right-click menu has Open the notch, Send home and Size. It costs under 1 % of a core idle and awake and nothing while it cannot be seen.

**Architecture:** Every rule is a pure Foundation file tested against H-0's fixture by a `swiftc` program, the way A and B did it: `DesktopCatSpots` (screens, `screenKey`, `clampSpot`, `spotFor`, `rememberSpot`), `DesktopCatSettings` (`cleanDesktopSettings` and the three UserDefaults keys), `DesktopCatTrip` (`desktopStep`, `desktopFlightAt` with the flight's clock, `desktopFps`, `desktopKittenSlots`), `DesktopCatLayout` (the window around the cat and the body that takes the mouse), `DesktopCatInput` (a click that waits one double-click interval, the drag, the right-click menu), `DesktopCatDrop` (a window attaches, empty desktop places the cat) and `DesktopCatPacer` (one timer, re-armed only when the target changes). `CatSettingsStore` holds the desktop settings beside the Cat and Display settings. `DesktopCatController` is the app's side: it owns the trip's phase (`DesktopCatTrip.step` decides, it carries out the act), the flight's clock, the `DesktopCatPanel`, the mouse monitors and the one frame timer, and it publishes the phase as `AppState.desktopPhase`, which empties the notch's big-cat spot, its kittens and its hit area while the cat is out. One function, `DesktopCatDraw.draw`, draws the cat in the app and on the contact sheets. Nothing is checked by launching the app: the images come from `render-cats.sh` (`--desktop`, `--desktop-flight`) and `render-cat-settings.sh`, the cost from `render-cats.sh --bench-desktop`, and the wiring from source pins.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, AppKit (`NSPanel`, `NSEvent` monitors, `DispatchSourceTimer`), Combine, CoreGraphics, Carbon hot keys (existing), XcodeGen, `swiftc` test programs, Bash.

**Spec:** `docs/superpowers/specs/2026-10-08-desktop-cat-design.md` (all of it; §4 gives the order and the three owner checkpoints). The contract is H-0's, merged as `99e3be1`: the desktop rules in `design/prototype/cat-core.js`, `tests/fixtures/cat/desktop-cases.json` and `docs/CAT-CONTRACT.md`, "The desktop cat (H-0)" (its plan, `docs/superpowers/plans/2026-10-08-h0-desktop-cat-contract.md`, has the interface). The format and the Mac code's conventions are B-mac's (`docs/superpowers/plans/2026-10-08-b-mac-display-kittens.md`). The Windows and Linux twin is `docs/superpowers/plans/2026-10-12-h-tauri-desktop-cat.md`; "Parity with Windows/Linux" below lists where the two differ.

**Base:** a new branch `h-mac/desktop-cat` in a git worktree, from `notchmeow/rebrand` at H-0's merge, **`99e3be1` or later** (`git merge-base --is-ancestor 99e3be1 HEAD` must succeed). H-0 is merged and this plan applies nothing of it: it added the desktop section of `cat-core.js`, `desktop-cases.json` (the contract's suite reads `# tests 284`) and the contract's section, and `node scripts/check-fixtures-additive.mjs 1627851` proves no older fixture changed. This plan never edits `cat-core.js`, a fixture of `tests/fixtures/cat/`, `shared/theme.json`, a generated theme file or anything under `windows/`.

## Global Constraints

Every task's requirements include this section. Values are copied from the spec and from H-0's contract; the lines marked "(plan decision)" are choices this plan makes where the spec is silent, and are listed again under "Open questions for the owner".

- **Swift 6, SwiftUI and AppKit, no third-party dependencies.** The cat is drawn in code (`CatRenderer`), no images. The pure files (`DesktopCatSpots`, `DesktopCatSettings`, `DesktopCatTrip`, `DesktopCatLayout`, `DesktopCatInput`, `DesktopCatDrop`, `DesktopCatPacer`) stay Foundation-only and carry no build condition; `DesktopCatDraw` knows only CoreGraphics and the cat's drawing files.
- **0 % CPU when hidden, and almost nothing while it sits there.** The notch's own rule is unchanged. The desktop cat has **one** repeating `DispatchSourceTimer`, re-armed only when `DesktopCatTrip.fps` changes (`DesktopCatPacer`) and cancelled at 0; **no `Timer`, no display link, no polling**. The mouse is watched by `NSEvent` mouse-moved monitors that exist only while the cat is drawn and visible (not upstream's 60 Hz timer). A lone click and a flight that ends while the cat cannot be seen each use one one-shot. Frame rates (`DESKTOP_FPS`): **60** in motion (a flight, dragging, an emote, a kitten arriving or leaving, the dance), **20** while an agent works or the cursor is within 150 pt, **5** idle and awake, **0.5** asleep (one frame every 2 s), **0** at home, in the notch for an alert, with the screens asleep or locked, or covered by a fullscreen app. Target: **under 1 % of a core idle and awake, about nothing asleep** (`render-cats.sh --bench-desktop`).
- **Never restyle a shipping view.** The only change in the notch is the empty big-cat spot while the cat is out (the cat, its glow, its kittens and its hit area); the pills, the grid, Two cats' cat 2 and every other view stay as they are. Settings gets one new group, "Desktop", under Display. The attach on a drop over another app's window is **the code that shipped, unchanged**, behind a pure rule (`DesktopCatDrop`) that only adds the case "no window: place the cat". Never rename a pill ID or a contract string (`nm-hook`, `nm.sock`, `nm_kind`, `nm_agent`, bundle identifiers).
- **Frozen contract values.** Cat IDs (`shrimpy`, `momo`, `ginger`, `midnight`, `latte`, `patches`, `blue`, `snow`, `oreo`, `mocha`, `silver`, `cloud`, `leo`, `button`, `puff`, `noodle`), the display mode IDs (`one`, `perAgent`, `two`), the collar styles, the pill IDs, **the size IDs `small`, `medium` and `large`**, **the shortcut action ID `desktop`**, the seven phase IDs and eleven act IDs of the trip, and the UserDefaults keys: A's, B's (`cat.displayMode`, `cat.pair`, `cat.agentCat.<pillId>`) and H's three, `cat.desktop.on` (a Bool), `cat.desktop.size` (the size ID) and `cat.desktop.spots` (the JSON text of screen key to `{x, y}`).
- **Stored values never throw and never skip the clean-up.** Every desktop value read from UserDefaults goes through `DesktopCatSettings.clean` (H-0's `cleanDesktopSettings`, a clean-up of its own: `CatSettings.clean`, `CatDisplaySettings.clean` and their fixtures are as they were), and a value is written only after it was cleaned. `on` is true only for the **boolean** true (the text "true" and the number 1 are off: the stored object is read as it is, never `UserDefaults.bool(forKey:)`), a size that is not one of the three is `medium`, `cat.desktop.spots` is strict JSON text (`Personality.isStrictJSON`), a key is kept only when `isScreenKey` accepts it (matched as a whole string: a trailing newline is not a key) and at most 32 arrangements are kept.
- **Fixtures decide.** Numbers compare within **1e-9**; strings, booleans, nulls and shapes compare exactly. `cat-core.js` is the tie-breaker; this plan never edits it or a fixture. JSON cannot hold NaN, infinity or `undefined`, so each port adds its own tests for a time, a spot, a screen or a distance that is not finite. Swift's `rounded()` is not `Math.floor(v + 0.5)`: `screenKey` rounds half up with `(v + 0.5).rounded(.down)`. There are no pixel tests of the look: it is checked on the contact sheets.
- **Coordinates.** Points, y down, the origin at the top left of the main screen (`DesktopCatScreens` converts from AppKit's bottom-left origin: `yTop = primaryHeight - frame.maxY`, and `NSScreen.screens[0]`, not `NSScreen.main`, is the screen with the menu bar). A spot is the head centre.
- **The desktop cat ships in Debug, Release and App Store builds** (spec §3, "Mac"), **⌃⌥D included**. The App Store build has no attach, so there **any drop that is not on the island places the cat**, even over another app's window; the dance is the notch's rule (`#if !APPSTORE`, no dance in the App Store build). `scripts/check-app-binary.sh` finds the marker `NM_DESKTOP_CAT_PANEL` in all three builds (it is longer than 15 bytes on purpose: Swift keeps a shorter string inside the code, where `strings` cannot see it; the first draft's `NM_DESKTOP_CAT` was missing from the Release binary).
- **The big cat's role is kept.** The desktop cat shows exactly what the big cat shows in the notch: `AppState.cast.big` (One cat, the Main cat; A cat for each agent, the focused agent's cat, whose coat follows the focus; Two cats, cat 1), `AppState.effectiveState`, the collar of the working agent's colour, its kittens. The engine takes its coat as a parameter from the cast (`useCharacter(state.cast.big.cat)`); nothing reads the Main cat on its own, and a kitten is never given `useCharacter`. Small eyes are a notch-only look below Ø28: the desktop sizes (Ø48 and up) always draw full detail.
- **Never block Claude Code, no telemetry, no network.** Nothing here sends or receives anything.
- **Never edit `NotchBuddy.xcodeproj` by hand.** A task that adds a Swift file to the app runs `cd NotchBuddy && xcodegen` before it builds and commits the regenerated `project.pbxproj`. A new Swift file that a test or render script compiles is added to that script's list.
- **No `UserDefaults` suite, and no `UserDefaults.standard` write, in any test or script.** A test builds `CatSettingsStore(backing:config:rand:)` on a `MemoryBacking` (a dictionary). The tests never register a hot key except `HotKeyCenterTests`, which already does, under combinations nobody uses.
- **Nothing of Coucou's comes back**, and the names Coucou and Mochi appear in no new code (`mocha` is a coat). No sound is added for the trip (sound Stage 3 can add them).
- **Models and commits** (CLAUDE.md, "Working with AI agents", 2026-10-12): Haiku 5.5 first, Sonnet 5.5 only on a named trigger, never Opus or Fable. Each commit is local only, never pushed, lists only the files its task names, and ends with the `Co-Authored-By` line of the model that did the task: `Claude Haiku 5.5` for `nm-implementer-light` and `nm-implementer`, `Claude Sonnet 5.5` for `nm-implementer-deep`.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app. A Debug, Release or App Store **build** in the worktree is fine and is only built; the scripts that draw a PNG (`render-cats.sh`, `render-cat-settings.sh`, `render-cat-panel.sh`) are not the app and may run. No task sends a hook event to the app's socket.
  2. Install nothing. No network calls, no downloads (`npx --no-install` only; this plan needs neither `npm` nor `cargo`).
  3. Use `trash`, never `rm -rf`, for anything you delete by hand; put scratch files under `${TMPDIR:-/tmp}` with a unique folder name. (The test scripts clean their own `mktemp` folders with `rm -rf` in a `trap`, as every `scripts/test-*.sh` does: that is the repo's convention, not a command an agent runs.)
  4. No `UserDefaults` suite and no write to `UserDefaults.standard` or to `~/Library` in a test or script; tests write no log outside a temp `NM_LOG_DIR`.
  5. Never edit `design/prototype/cat-core.js`, a fixture of `tests/fixtures/cat/`, `shared/theme.json`, a generated theme file or anything under `windows/`.
  6. Never push. Commit only in a task's commit step, after checking the worktree and the branch.
  7. Haiku 5.5 for every task except Task 5 (Sonnet 5.5); never Opus or Fable.
  8. Never rename a frozen ID, and write no `Coucou` or `Mochi` name anywhere in code, comments, scripts or tests (`scripts/check-no-leftovers.sh` must stay green).
  9. If a command is denied by a permission prompt, stop and report it. Do not look for a workaround.

## Review Focus

The spec says what the desktop cat does. It is silent on these inputs and conditions, and each would bite a person first, most likely first. Each line names the test that pins it.

1. **A monitor that is unplugged, or a laptop that comes back alone.** A cat remembered on a screen that is gone must not sit off screen, and a laptop alone and a laptop with a monitor each keep their own spot; moving the Dock must not forget the spot; the menu bar and the Dock must never cover the cat. Expected: the spot goes to the main screen's default, each arrangement keeps its own, the clamp keeps the head 24 pt inside the visible frame. Tests: Task 1 (the 54 clamps, 13 `spotFor` and 8 `rememberSpot` rows, "a screen too small for the cat", "a thousand arrangements") and Task 4 (AppKit's screens turned into the contract's).
2. **A click that must not be eaten, and a click that must be.** Everything outside the cat's body has to reach the app underneath, the cat's body (head, badge, kittens) has to take the mouse, and a drag must not lose the mouse when the cursor outruns the window. Expected: `ignoresMouseEvents` flips with the body's shape and stays off while dragging; a double-click never also opens the island. Tests: Task 4 (`hits` at the edges, the corners, the hearts' room, the kittens' gaps; the click machine) and Task 5's pins.
3. **A drop that is not on the desktop.** A drop on another app's window still attaches exactly as today (and not at all in the App Store build, where it places the cat), a drop on the island, or on a window whose context cannot be captured, does nothing, and a drop beside every screen goes to the default spot. Tests: Task 4 (`DesktopCatDropTests`) and Task 5's pins on the shipped attach code.
4. **An alert in the middle of everything.** An approval that lands while the cat flies out, flies home, sits at the notch, or is home; an alert cleared mid-flight; a `sendHome` during an alert; the island opening or folding while the cat flies to the notch. Expected: the cat turns around without a jump, a cat that is home never comes out for an alert, the flight aims at the notch spot as it is each frame. Tests: Task 3 (the 63 steps and 11 trips, "turned at any moment, the cat is exactly where it was") and Task 6.
5. **A cat nobody can see.** Screens asleep or locked, a fullscreen Space, a covered window, the cat at home or at the notch: the timer must be cancelled, the monitors removed, and a flight that ends in the meantime must still end. Expected: 0 fps, no timer, no monitors, `flightDone` still arrives once. Tests: Task 3 (the 39 frame-rate rows), Task 4 (the pacer), Task 10's pins and the bench.
6. **A hand-edited or half-written store.** `cat.desktop.on` as the text "true" or the number 1, a size in the wrong case, `cat.desktop.spots` cut off, with a trailing comma, with a key that is not a screen key or a spot beyond 100000. Expected: off, `medium`, `{}`, never a throw, and Settings still opens. Tests: Task 1 (the 41 settings rows, "a store that is wrong in every way still loads") and Task 2.

---

## File Structure

| Path | Responsibility |
|---|---|
| `NotchBuddy/Sources/App/DesktopCatSpots.swift` | New. `DesktopSize`, `DesktopRect`, `DesktopScreen`, `DesktopSpot`, and `DesktopCatSpots`: the screens, `screenKey`, `isScreenKey`, `clampSpot`, `defaultSpot`, `spotFor`, `rememberSpot`, `cleanSpots`. Foundation only. |
| `NotchBuddy/Sources/App/DesktopCatSettings.swift` | New. `DesktopCatSettings` (the clean-up, the edits, the three UserDefaults keys, load and save). Foundation only. |
| `NotchBuddy/Sources/App/DesktopCatTrip.swift` | New. `DesktopPhase`, `DesktopAct`, `DesktopEvent`, `DesktopCatTrip.step`, `flightAt`, `Flight` (the flight's clock), `fps`, `kittenSlots`. Foundation only. |
| `NotchBuddy/Sources/App/DesktopCatLayout.swift`, `DesktopCatInput.swift`, `DesktopCatDrop.swift`, `DesktopCatPacer.swift` | New. The window around the cat and its body shape; click, drag and the right-click menu, kittens arriving or leaving, the notch spot; the drop rule; the one-timer governor and what hides the cat. Foundation only. |
| `NotchBuddy/Sources/App/DesktopCatDraw.swift` | New. The one function that draws the desktop cat (the app and the sheets). |
| `NotchBuddy/Sources/App/DesktopCatPanel.swift`, `DesktopCatScreensApp.swift`, `DesktopCatController.swift` | New. The floating panel and its view; `NSScreen` as the contract's screens; the trip, the timer, the mouse and the links to the island, the store and the hook state. |
| `NotchBuddy/Sources/App/CatSettingsStore.swift`, `CatSettingsView.swift` | The store holds `desktop` and its setters; Settings → Cat gets the "Desktop" group. |
| `NotchBuddy/Sources/App/AppState.swift`, `IslandRootView.swift`, `KittenViews.swift`, `IslandWindowController.swift`, `AppDelegate.swift` | `desktopPhase`; the big cat's spot and its kittens are empty while it is out; the drop, the hit test, a click from the desktop, ⌃⌥D; the controller is made and started, and the menu-bar item. |
| `NotchBuddy/Sources/App/ShortcutLogic.swift` | The `desktop` action, appended last (Carbon identifies a hot key by its index in `allCases`), ⌃⌥D, on by default. |
| `NotchBuddy/Sources/App/DesktopCatDevModel.swift`, `DesktopCatDevPanel.swift`, `CatDevPanel.swift` | New, and one line in the existing panel. The live Desktop section of the Debug-only "Cats (Debug)…" panel: a mock desktop with the cat, a button that fires the alert flight, the size picker and a readout of the frame rate and cost. Compiled out of Release and App Store (marker `NM_CAT_DEV_DESKTOP`). |
| `tests/DesktopCatSettingsTests.swift`, `DesktopCatTripTests.swift`, `DesktopCatLayoutTests.swift`, `DesktopCatInputTests.swift`, `DesktopCatDropTests.swift`, `DesktopCatPacerTests.swift`, `DesktopCatDevModelTests.swift`, `DesktopCatWiringTests.swift` | New. One program each (the wiring program is the source pins of the app files no test program can compile). |
| `tests/CatSettingsStoreTests.swift`, `tests/ShortcutTests.swift`, `tests/HotKeyCenterTests.swift` | New sections (the store's desktop settings); the counts and sets of the shortcut tests with the sixth default-on action. |
| `scripts/test-cat-desktop-settings.sh`, `test-cat-desktop-trip.sh`, `test-cat-desktop-layout.sh`, `test-cat-desktop-input.sh`, `test-cat-desktop-drop.sh`, `test-cat-desktop-pacer.sh`, `test-cat-desktop-devpanel.sh`, `test-cat-desktop-wiring.sh` | New. One script for each new test program. |
| `scripts/render-cats.sh`, `render-cats.swift`, `render-cats-desktop.swift`, `render-cat-settings.sh`, `render-cat-panel.sh`, `check-app-binary.sh`, `test-cat-settings-store.sh` | `--desktop [--shapes]`, `--desktop-flight` and `--bench-desktop` (the sheets live in the new extension file); the compile lists gain the new files (and `render-cat-settings.sh` the `CatKittens.swift` it never listed); the desktop cat's marker is checked in all three builds, and the dev panel's Desktop section's marker is proved absent from Release and App Store. |
| `.github/workflows/build.yml`, `CLAUDE.md`, `ARCHITECT.md`, `README.md`, `docs/SPEC.md` | One CI step for each new script; the Mac lines; the roadmap row; the French spec: the drag, "Le chat de bureau" and ⌃⌥D. |
| `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` | Regenerated by `xcodegen`, never by hand. |

**Order of tasks.** The spec's step 1 is Tasks 1 and 2; step 2 (the panel and its click-through), step 3 (dragging out, the flight, sending home) and the controller's skeleton are Task 5; step 4 (alerts) is Task 6; step 5 (what it shows) is Task 7; step 6 (the frame-rate rule, the bench and the Debug panel's live Desktop section) is Task 10; step 7 (menu-bar item, Settings switch, ⌃⌥D) is Tasks 8 and 12; step 8 (docs) is Task 13. **Three things moved against the spec's list.** (1) **The pure ports come first** (Tasks 3 and 4: the trip, the layout, the click machine, the drop rule and the pacer), because the app's class is then a thin carrier of tested rules, as B-mac did with its pure files. (2) **The Settings switch moves forward** (Task 8) so that checkpoint 1 can show it; the menu-bar item and ⌃⌥D stay in step 7's place (Task 12). (3) **The controller is one class that Tasks 5 to 12 build up in stages**: Task 5 lands it whole enough to carry the cat (window, click-through, drag, flight, home, menu, a fixed 20 fps) and each later task adds its own regions, so each task has code that a reviewer can reject on its own.

## Tasks and agents

CLAUDE.md: the lightest model that fits. **Haiku 5.5 first; Sonnet 5.5 only on a named trigger.** The code is given in full in every task and its tests prove it, so every task except one is Haiku. **Task 5 is `nm-implementer-deep` (Sonnet 5.5, high): trigger 1**, platform APIs and concurrency the task must get right rather than copy (an `NSPanel` that never takes focus, joins every Space and stays out of fullscreen, click-through that follows a shape, `NSEvent` monitors, Swift 6 main-actor isolation of the event handlers). If a Haiku task's expected output differs and the cause is not obvious, or it fails twice, hand that task to `nm-implementer-deep` (trigger 2) and say so in the ledger. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion` (the deep agent also `superpowers:systematic-debugging`); reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). Effort: **medium** for light tasks (code given in full), **high** for `nm-implementer` and for every review.

| # | Task | Agent, model, effort | Review |
|---|---|---|---|
| 0 | Worktree and baseline | the session | none |
| 1 | Settings and clean-up port: screens, `screenKey`, spots, `cleanDesktopSettings` (step 1) | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 2 | The store holds the desktop settings (step 1) | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 3 | The trip in Swift: `desktopStep`, the flight and its clock, `desktopFps`, the kittens' slots | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 4 | The window's geometry, the mouse rules, the drop rule and the pacer (pure) | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 5 | The panel and its click-through, dragging out, the flight and sending home (steps 2 and 3) | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `nm-reviewer` |
| 6 | Alerts: the cat flies to the notch and back, and the flight strip (step 4) | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 7 | What it shows: badge, kittens, collar, eyes, dance and sleep (step 5) | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 8 | The Settings switch (moved forward from step 7) | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 9 | **Owner checkpoint 1:** S, M and L on a desktop mock, and the Settings switch | the main session and the owner | none |
| 10 | The frame-rate rule, what hides the cat, the bench, and the Debug panel's Desktop section (step 6) | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 11 | **Owner checkpoint 2:** the alert flight and the bench numbers | the main session and the owner | none |
| 12 | The menu-bar item and ⌃⌥D (step 7) | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 13 | Docs, CI and the final checks (step 8) | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| After 13 | The whole branch: cross-task contracts, privacy and security rules, the Review Focus | `nm-reviewer-deep`, Sonnet 5.5, high | none |
| 14 | **Owner checkpoint 3:** sign-off, then the owner's real-build checks | the main session and the owner | none |

## Execution

One worktree chat session runs the whole plan: branch `h-mac/desktop-cat`, model **Sonnet 5.5 at high effort** (trigger 5: an app plan with hard integration, several platform APIs and many cross-task interfaces; `ARCHITECT.md`). Nothing is pushed. It runs in a worktree of its own, in parallel with the Windows and Linux twin, which touches nothing under `NotchBuddy/`.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run `git switch -c h-mac/desktop-cat notchmeow/rebrand`, then Task 0 of `docs/superpowers/plans/2026-10-12-h-mac-desktop-cat.md`: only its Steps 1 to 3 (the base checks: `git merge-base --is-ancestor 99e3be1 HEAD` must succeed, H-0 is merged and nothing of it is applied). Read `CLAUDE.md`, `ARCHITECT.md`, that plan, `docs/superpowers/specs/2026-10-08-desktop-cat-design.md` and `docs/CAT-CONTRACT.md` ("The desktop cat (H-0)"). If a base check fails, say so and stop. Reply "ready" and stop. Do not start Task 1.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-12-h-mac-desktop-cat.md` with `superpowers:subagent-driven-development`, task by task, on branch `h-mac/desktop-cat`. Dispatch each task to the agent the plan's "Tasks and agents" table names (Haiku 5.5 first; Sonnet 5.5 only for Task 5 and for a task Haiku failed twice), then to `nm-reviewer`; fix what the review finds before the next task. Rules for you and for every subagent (put the plan's SUBAGENT RULES block in every brief):
>
> - **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder (under `.claude/worktrees/`), the second `h-mac/desktop-cat`. If either is wrong, stop and report. Commit with `git commit -F <file>`, never `-m`, with the trailer of the model that did the task. Never push.
> - **Ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-12-h-mac-desktop-cat/progress.md` (the SDD plugin's scripts are refused by auto mode, so you write it by hand): one line per task with its agent, model, commit hash, test lines and review verdict, and any escalation to `nm-implementer-deep` with the trigger.
> - **Briefs are task-sized.** A brief carries one task: its text, the Global Constraints, the SUBAGENT RULES and the files it names. Never hand a subagent the whole plan.
> - **Reviews** read `git diff notchmeow/rebrand...HEAD` (three dots), narrowed to the task's files, never `..` and never a diff against a moving working tree.
> - **Every shell block in the plan passes `bash -n` before it is run**, and a script you write passes it too.
> - **Servers and processes.** Stop a server only by the PID you saved when you started it. Never launch, quit or replace a NotchMeow app: the builds are builds, the PNGs come from `render-cats.sh` and `render-cat-settings.sh`. Install and download nothing.
> - **Stop and report on any refusal** (a denied command, a permission prompt): do not look for a workaround.
> - **Owner checkpoints.** Run Tasks 1 to 8, then stop and report to the main session for owner checkpoint 1 (Task 9: copy the pictures into `.claude/checkpoints/h-mac/` of the worktree, which is gitignored, and say what to look for). After the owner's reply run Task 10, then stop again for checkpoint 2 (Task 11). Then run Tasks 12 and 13, dispatch `nm-reviewer-deep` over the whole branch, fix what it finds, and stop for checkpoint 3 (Task 14).
>
> Report: the commits; the output of every `bash scripts/test-cat-*.sh`, `bash scripts/test-shortcuts.sh`, `bash scripts/test-hotkeys.sh` and `bash scripts/check-no-leftovers.sh`; the Debug, Release and App Store build lines and the three `check-app-binary.sh` lines; the bench lines; the paths of the PNGs of each checkpoint; and anything you could not settle.

Before any follow-up turn (a fix round, a question, a resumed run), the main session checks the session is still on its configured model and effort.

## How to run this plan

**Blocks.** A code step is either **Create `path`** (the file's exact content) or **Edit `path`** (a find text that occurs exactly once, and its replacement). Apply an edit by replacing the find text with the replacement and nothing else; if the find text occurs zero or two times, stop and report: the tree is not what the plan expects. Never type a block from memory and never "improve" one. Every `Run:` line is run from the repository root (the worktree's top folder); `Expected: FAIL` and `Expected: PASS` say which way it must go, and the text after it says what to see. A test program's failing run prints `✗` lines, and its last line is `N test(s) failed.`; a passing one ends `All tests passed.` A compile that cannot find a file prints `error opening input file` (a red run before the code exists). A new script is made executable with the `chmod +x` line that follows its block.

**Mac commands.** The test programs are `swiftc` programs run through `scripts/test-cat-*.sh`; none needs Xcode. A build is `cd NotchBuddy && xcodegen && cd ..` and then `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO`; the Release build is `-configuration Release -derivedDataPath NotchBuddy/build/release` and the App Store target `-scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store`, each with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` (git ignores `NotchBuddy/build/`). Add `2>&1 | tail -3` to read the last lines. **Never start a built app.** The scripts that draw a PNG write wherever `--out` says; this plan writes them under `${TMPDIR:-/tmp}/h-mac-1` and `h-mac-2`, and the checkpoints copy the ones the owner sees to `.claude/checkpoints/h-mac/` of the worktree (never committed). The bench wants an optimised build: `RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench-desktop`.

**Looking at an image.** Several steps end with "look at it". The agent that ran the step opens the PNG with its file reader and says in one sentence what it sees against the thing named; a blank or broken image is a failed step. The owner's look is the checkpoint.

**Stages of one file.** Tasks 5 to 12 build `DesktopCatController.swift`, `DesktopCatWiringTests.swift`, `IslandWindowController.swift`, `AppDelegate.swift`, `render-cats.swift` and `render-cats-desktop.swift` up in stages. Each later task's **Edit** blocks are written against the file exactly as the earlier tasks left it; apply them in the order the plan gives them.

**Dry-run clones.** A throwaway clone made with `git clone --local --shared` has no `windows/node_modules` and no Docker; nothing here needs either. Commit steps are not run in a clone, so a `git status` there shows every earlier task's files.

---
## Tasks

### Task 0: Worktree and baseline

No code and no commit: this makes sure the base is the one the plan expects. Its first three steps are what the chip's prompt runs before the model is set (see "Execution").

- [ ] **Step 1: Put the session's worktree on the plan's branch**

```bash
git status                                    # must be clean
git switch -c h-mac/desktop-cat notchmeow/rebrand
git merge-base --is-ancestor 99e3be1 HEAD && echo "H-0 (99e3be1) is in the base"
git log --oneline -6                          # H-0's merge is in the history
```

Expected: `H-0 (99e3be1) is in the base`. If that line is missing, the worktree was cut from an older base: stop and tell the owner. Every later command runs from the root of this worktree. Never push.

- [ ] **Step 2: Check that H-0's files are there and the contract is green**

Run: `for f in design/prototype/cat-core.js tests/fixtures/cat/desktop-cases.json docs/CAT-CONTRACT.md; do test -f $f && echo "ok $f"; done; grep -c "function desktopStep" design/prototype/cat-core.js`
Expected: three `ok …` lines and `1`. If a line is missing, the base is not H-0's merge: stop and tell the owner.

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|fixture files match|identical bytes"`
Expected: `# tests 284`, `# pass 284`, `# fail 0`, `✓ 15 fixture files match cat-core.js` and `✓ two generator runs write identical bytes`.

Run: `node scripts/check-fixtures-additive.mjs 1627851 2>&1 | tail -1`
Expected: `✓ fixtures changed only by addition since 1627851`.

- [ ] **Step 3: Check that the Mac cat tests are green, read the frame time, and build**

```bash
for f in scripts/test-cat-*.sh; do printf '%-42s' "$f"; bash "$f" 2>&1 | tail -1; done
```

Expected: twenty-five lines: `scripts/test-cat-contract.sh` ends `✓ two generator runs write identical bytes` and the other twenty-four end `All tests passed.`

Run: `bash scripts/test-shortcuts.sh 2>&1 | tail -1; bash scripts/test-hotkeys.sh 2>&1 | tail -1`
Expected: two lines, `Shortcuts: … cases passed` and `HotKeyCenter: … cases passed`. Task 12 changes both programs, so write the two counts down.

Run: `RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench 2>&1 | tail -1`
Expected: one line, `12 small cats (30 fps) + the big one (60 fps), update and draw, CPU time: avg 1.8x ms, p95 …` (the dry run read 1.82 ms; it moves by 0.1 to 0.2 ms with the machine's load). The notch's own cost must not move: it is read again in Task 13.

```bash
cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `Created project at …` and the last lines end with `** BUILD SUCCEEDED **` (a few minutes on a cold build). The build only builds: do not open the app.

**A defect found at the base** (the dry run): `bash scripts/render-cat-settings.sh` does not compile on `notchmeow/rebrand` (`CatIslandLayout.swift` needs `CatKittens`, which the script's list never named). Task 2 adds the file to the list, because Task 8's Settings picture needs the script.

- [ ] **Step 4: Read the base once**

Read, without changing: `NotchBuddy/Sources/App/IslandWindowController.swift` (`finishDrag` inside `startKeyMonitor`, `windowContextAtPoint`, `windowBoundsAtScreenPoint`, `isBotHit`, `handleHotKey`), `IslandRootView.swift` (`BotPlacement`, `botPosition`), `KittenViews.swift` (`KittenPlacement`), `BotCanvasView.swift` (the big cat's engine, collar and dance), `CatSettingsStore.swift`, `CatDisplay.swift` (the pattern `DesktopCatSettings` follows), `ShortcutLogic.swift`, `HotKeyCenter.swift`, `AppDelegate.swift`, `CatKittenDraw.swift`, and H-0's section of `docs/CAT-CONTRACT.md`. Nothing to report.

---

### Task 1: Settings and clean-up port: screens, `screenKey`, spots, `cleanDesktopSettings` (step 1)

**Agent:** `nm-implementer-light` (Haiku 5.5, medium). The code is given in full; the tests prove it.

**Files:**
- Create: `NotchBuddy/Sources/App/DesktopCatSpots.swift`, `NotchBuddy/Sources/App/DesktopCatSettings.swift`, `tests/DesktopCatSettingsTests.swift`, `scripts/test-cat-desktop-settings.sh`
- Modify: `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated by `xcodegen`)

**Interfaces:**
- Consumes: H-0's `desktopSizeOf`, `DESKTOP_SIZES`, `DESKTOP_MARGIN`, `DESKTOP_DEFAULT`, `MAX_DESKTOP_SPOTS`, `screenKey`, `isScreenKey`, `defaultDesktopSpot`, `clampSpot`, `cleanDesktopSpots`, `spotFor`, `rememberSpot`, `cleanDesktopSettings` (`docs/CAT-CONTRACT.md`, "The desktop cat (H-0)"), `tests/fixtures/cat/desktop-cases.json` (keys `sizes`, `sizeIds`, `defaultSize`, `sizeCases`, `margin`, `defaultSpot`, `maxSpots`, `screenKeys`, `isScreenKey`, `clamps`, `defaultSpots`, `spotFor`, `remembers`, `spotMaps`, `settingsDefaults`, `settingsCases`), `Personality.isStrictJSON`, A's `CatSettingsBacking`.
- Produces: `DesktopSize` (`small`, `medium`, `large`, raw values frozen; `d`, `DesktopSize.of(_:)`), `DesktopRect`, `DesktopScreen` (`frame`, `visible`, `main`), `DesktopSpot`; `DesktopCatSpots.screens(_ raw: Any?)`, `tidy`, `screenKey`, `isScreenKey`, `clampSpot(_:_:size:)`, `defaultSpot(_:size:)`, `mainScreen`, `contains`, `isValid`, `spot(_:)`, `cleanSpots(_:)`, `spotFor(_:_:size:)`, `rememberSpot(_:_:_:size:)` and the constants `margin`, `maxSpots`; `DesktopCatSettings` with `on`, `size`, `spots`; `clean(_ raw: Any?)`, `isTrue`, `json`, `withOn`, `withSize`, `remembering(_:on:)`, `spot(on:)`, `Key`, `load(from:)`, `save(to:replacing:)`, `spotsText`.

- [ ] **Step 1: Write the failing tests**

The program replays the fixture (17 sizes, 19 screen keys, 30 key strings, 54 clamps, 8 default spots, 19 stored maps, 13 `spotFor`, 8 `rememberSpot` and 41 stored blocks), pins the frozen values, adds what the fixture cannot write (a NaN, a boolean for a number, a screen too small for the cat, a thousand arrangements), tests the edits, and runs the UserDefaults keys through a dictionary store (the keys it writes, only what changed, a store that is wrong in every way).

**Create `tests/DesktopCatSettingsTests.swift`**:

```swift
import Foundation

@main
enum DesktopCatSettingsTests {
    typealias S = DesktopCatSpots
    typealias Cfg = DesktopCatSettings

    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    /// A fixture spot (`{x, y}` or null) as JSON, for comparing.
    static func spotJSON(_ s: DesktopSpot?) -> Any { s.map { ["x": $0.x, "y": $0.y] as [String: Any] } ?? NSNull() }
    static func mapJSON(_ m: [String: DesktopSpot]) -> [String: Any] { m.mapValues { ["x": $0.x, "y": $0.y] as [String: Any] } }

    @MainActor static func main() {
        let fx = CT.fixture("desktop-cases.json")

        CT.section("the frozen values: the three sizes, the margin, the default spot and the cap")
        let sizes = fx["sizes"] as! [String: Any]
        CT.check("the size IDs, in order", DesktopSize.allCases.map(\.rawValue), fx["sizeIds"] as! [String])
        CT.check("the head widths", DesktopSize.allCases.map(\.d), DesktopSize.allCases.map { (sizes[$0.rawValue] as! NSNumber).doubleValue })
        CT.check("the default size", DesktopSize.of(nil).rawValue, fx["defaultSize"] as! String)
        CT.checkNear("the margin", S.margin, (fx["margin"] as! NSNumber).doubleValue)
        let ds = fx["defaultSpot"] as! [String: Any]
        CT.checkNear("the default spot across", S.defaultAcross, (ds["x"] as! NSNumber).doubleValue)
        CT.checkNear("and down (a third)", S.defaultDown, (ds["y"] as! NSNumber).doubleValue, tol: 1e-9)
        CT.check("at most 32 arrangements are remembered", S.maxSpots, fx["maxSpots"] as! Int)

        CT.section("desktopSizeOf: \(rows(fx["sizeCases"]).count) stored values")
        var diffs: [String] = []
        for c in rows(fx["sizeCases"]) where DesktopSize.of(c["raw"]).rawValue != c["out"] as! String { diffs.append("\(c["raw"] ?? "nil"): \(DesktopSize.of(c["raw"]).rawValue)") }
        CT.checkRows("every stored size is as the fixture says", diffs)

        CT.section("screenKey: \(rows(fx["screenKeys"]).count) arrangements")
        diffs = []
        for c in rows(fx["screenKeys"]) {
            let got = S.screenKey(S.screens(c["screens"]))
            if got != c["out"] as! String { diffs.append("\(c["name"] as! String): \"\(got)\"") }
        }
        CT.checkRows("every key is as the fixture says, whichever order the screens come in", diffs)
        CT.check("half rounds up, also below zero (not Swift's rounded())", [S.round(2.5), S.round(-2.5), S.round(-0.4), S.round(0.49999)], [3, -2, 0, 0])
        let frame = DesktopRect(x: -2.5, y: 0.5, w: 100.5, h: 50.49)
        CT.check("so a frame is written rounded half up", S.screenKey([DesktopScreen(frame: frame, visible: frame)]), "-2,1,101,50")

        CT.section("isScreenKey: \(rows(fx["isScreenKey"]).count) strings")
        diffs = []
        for c in rows(fx["isScreenKey"]) where S.isScreenKey(c["key"]) != c["out"] as! Bool { diffs.append("\(c["key"] ?? "nil"): \(S.isScreenKey(c["key"]))") }
        CT.checkRows("only what screenKey writes is a key", diffs)
        CT.checkTrue("a number, nothing and a trailing newline are not keys", !S.isScreenKey(7) && !S.isScreenKey(nil) && !S.isScreenKey("0,0,100,100\n") && !S.isScreenKey("٠,0,100,100"))

        CT.section("clampSpot: \(rows(fx["clamps"]).count) spots")
        diffs = []
        for c in rows(fx["clamps"]) {
            let got = S.clampSpot(S.spot(c["spot"]), S.screens(c["screens"]), size: DesktopSize.of(c["size"]))
            let d = CT.diffs(spotJSON(got), c["out"] ?? NSNull())
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every spot is held where the cat may sit, 24 pt from the head's edge", diffs)

        CT.section("defaultDesktopSpot: \(rows(fx["defaultSpots"]).count) arrangements")
        diffs = []
        for c in rows(fx["defaultSpots"]) {
            let d = CT.diffs(spotJSON(S.defaultSpot(S.screens(c["screens"]), size: DesktopSize.of(c["size"]))), c["out"] ?? NSNull())
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("the first spot is on the main screen, whichever marks it", diffs)

        CT.section("cleanDesktopSpots: \(rows(fx["spotMaps"]).count) stored maps")
        diffs = []
        for c in rows(fx["spotMaps"]) {
            let d = CT.diffs(mapJSON(S.cleanSpots(c["raw"])), c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every map is cleaned as the fixture says (text, bad keys, bad spots, the cap of 32)", diffs)

        CT.section("spotFor: \(rows(fx["spotFor"]).count) cases")
        diffs = []
        for c in rows(fx["spotFor"]) {
            let got = S.spotFor(S.cleanSpots(c["spots"]), S.screens(c["screens"]), size: DesktopSize.of(c["size"]))
            let d = CT.diffs(spotJSON(got), c["out"] ?? NSNull())
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("a laptop alone and a laptop with a monitor each keep their own spot", diffs)

        CT.section("rememberSpot: \(rows(fx["remembers"]).count) cases")
        diffs = []
        for c in rows(fx["remembers"]) {
            let got = S.rememberSpot(S.cleanSpots(c["spots"]), S.screens(c["screens"]), S.spot(c["spot"]) ?? DesktopSpot(x: .nan, y: .nan), size: DesktopSize.of(c["size"]))
            let d = CT.diffs(mapJSON(got), c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("the clamped spot is kept for this arrangement and the others stay; the map keeps 32 and the one just written", diffs)

        CT.section("cleanDesktopSettings: \(rows(fx["settingsCases"]).count) stored blocks")
        let defaults = Cfg.clean(nil)
        CT.checkJSON("the defaults are the fixture's", got: defaults.json, want: fx["settingsDefaults"]!)
        diffs = []
        for c in rows(fx["settingsCases"]) {
            let d = CT.diffs(Cfg.clean(c["raw"]).json, c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every block is cleaned as the fixture says (on as text or as the number 1 is off)", diffs)

        CT.section("what the fixture cannot write: numbers that are not numbers, and a cat with nowhere to sit")
        let laptop = S.screens([["frame": ["x": 0, "y": 0, "w": 1512, "h": 982], "visible": ["x": 0, "y": 37, "w": 1512, "h": 875], "main": true]])
        CT.check("one usable screen", laptop.count, 1)
        CT.check("a NaN spot is no spot: it goes to the default", S.clampSpot(DesktopSpot(x: .nan, y: 5), laptop, size: .medium), S.defaultSpot(laptop, size: .medium))
        CT.check("so does infinity", S.clampSpot(DesktopSpot(x: .infinity, y: 5), laptop, size: .medium), S.defaultSpot(laptop, size: .medium))
        CT.check("and a spot past the limit", S.clampSpot(DesktopSpot(x: 200000, y: 5), laptop, size: .medium), S.defaultSpot(laptop, size: .medium))
        CT.check("no screens, no spot", [S.clampSpot(DesktopSpot(x: 5, y: 5), [], size: .medium) == nil, S.defaultSpot([], size: .medium) == nil, S.spotFor([:], [], size: .medium) == nil], [true, true, true])
        CT.check("a screen with a NaN frame is not a screen", S.tidy([DesktopScreen(frame: DesktopRect(x: .nan, y: 0, w: 100, h: 100), visible: DesktopRect(x: 0, y: 0, w: 100, h: 100))]).count, 0)
        CT.check("nor is one with no width", S.tidy([DesktopScreen(frame: DesktopRect(x: 0, y: 0, w: 0.5, h: 100), visible: DesktopRect(x: 0, y: 0, w: 1, h: 1))]).count, 0)
        CT.check("a visible frame that is NaN is the frame", S.tidy([DesktopScreen(frame: DesktopRect(x: 0, y: 0, w: 100, h: 100), visible: DesktopRect(x: .nan, y: 0, w: 100, h: 100))])[0].visible, DesktopRect(x: 0, y: 0, w: 100, h: 100))
        CT.check("twenty screens count as sixteen", S.tidy((0..<20).map { DesktopScreen(frame: DesktopRect(x: Double($0) * 10, y: 0, w: 10, h: 10), visible: DesktopRect(x: Double($0) * 10, y: 0, w: 10, h: 10)) }).count, 16)
        CT.check("a boolean is not a number in a spot", S.spot(["x": true, "y": 1]) == nil, true)
        let tiny = DesktopScreen(frame: DesktopRect(x: 0, y: 0, w: 60, h: 60), visible: DesktopRect(x: 0, y: 0, w: 60, h: 60), main: true)
        CT.check("a screen too small for the cat holds its centre", S.clampSpot(DesktopSpot(x: 1, y: 1), [tiny], size: .large), DesktopSpot(x: 30, y: 30))
        CT.check("a remembered spot over a thousand arrangements stays under 32", S.cleanSpots((0..<1000).reduce(into: [String: Any]()) { $0["\($1),0,100,100"] = ["x": 1, "y": 1] }).count, 32)

        CT.section("the edits: each changes one thing and returns a clean value")
        let base = Cfg.clean(["on": true, "size": "large", "spots": ["0,0,1512,982": ["x": 300, "y": 400]]])
        CT.check("on", base.withOn(false), Cfg(on: false, size: .large, spots: base.spots))
        CT.check("size", base.withSize(.small).size, .small)
        CT.check("remembering a spot", base.remembering(DesktopSpot(x: 5, y: 5), on: laptop).spots, ["0,0,1512,982": DesktopSpot(x: 72, y: 109)])
        CT.check("the spot to use now", base.spot(on: laptop), DesktopSpot(x: 300, y: 400))
        CT.check("the input is never touched", base, Cfg.clean(["on": true, "size": "large", "spots": ["0,0,1512,982": ["x": 300, "y": 400]]]))

        CT.section("the UserDefaults keys, through a dictionary store")
        let store = MemoryBacking()
        CT.check("an empty store loads the defaults", Cfg.load(from: store), Cfg())
        store.values = ["cat.desktop.on": true, "cat.desktop.size": "small", "cat.desktop.spots": "{\"0,0,1512,982\":{\"x\":300,\"y\":400}}", "cat.character": "momo"]
        let loaded = Cfg.load(from: store)
        CT.check("what is stored is loaded (and the other cat keys are not read)", loaded, Cfg(on: true, size: .small, spots: ["0,0,1512,982": DesktopSpot(x: 300, y: 400)]))
        let fresh = MemoryBacking()
        loaded.save(to: fresh)
        CT.check("the keys it writes: the three", fresh.writes, ["cat.desktop.on", "cat.desktop.size", "cat.desktop.spots"])
        CT.check("the switch is a real Bool, the size a word and the spots strict JSON text", [fresh.values["cat.desktop.on"] as? Bool ?? false, fresh.values["cat.desktop.size"] as? String ?? "", fresh.values["cat.desktop.spots"] as? String ?? ""] as [AnyHashable], [true, "small", "{\"0,0,1512,982\":{\"x\":300,\"y\":400}}"] as [AnyHashable])
        CT.check("and loads back as it was", Cfg.load(from: fresh), loaded)
        let before = fresh.writes.count
        loaded.withSize(.large).save(to: fresh, replacing: loaded)
        CT.check("only the key that changed is written", Array(fresh.writes[before...]), ["cat.desktop.size"])
        loaded.save(to: fresh, replacing: loaded)
        CT.check("nothing that did not change is written", fresh.writes.count, before + 1)
        let many = Cfg(spots: ["1,0,100,100": DesktopSpot(x: 2, y: 3), "0,0,100,100": DesktopSpot(x: 1, y: 1)])
        CT.check("the same map is always the same text, keys in order", many.spotsText, "{\"0,0,100,100\":{\"x\":1,\"y\":1},\"1,0,100,100\":{\"x\":2,\"y\":3}}")

        CT.section("a store that is wrong in every way still loads")
        let wild = MemoryBacking()
        wild.values = ["cat.desktop.on": 1, "cat.desktop.size": 96, "cat.desktop.spots": Data("x".utf8)]
        CT.check("a number for on, a number for the size and data for the spots: the defaults", Cfg.load(from: wild), Cfg())
        wild.values = ["cat.desktop.on": "true", "cat.desktop.size": "Large", "cat.desktop.spots": "{\"0,0,100,100\":"]
        CT.check("text for on, a size in the wrong case and cut-off JSON: the defaults", Cfg.load(from: wild), Cfg())
        wild.values = ["cat.desktop.spots": "{\"0,0,100,100\":{\"x\":1,\"y\":2},}"]
        CT.check("JSON with a comma before the closing brace is not JSON", Cfg.load(from: wild).spots, [:])
        CT.finish()
    }
}
```

**Create `scripts/test-cat-desktop-settings.sh`**:

```bash
#!/usr/bin/env bash
# Desktop cat settings (sub-project H): the screens, the key and the spots (screenKey, clampSpot, spotFor, rememberSpot), the stored block (cleanDesktopSettings) and its three
# UserDefaults keys against desktop-cases.json, and what the fixture cannot write (a NaN, a boolean, a screen too small, a thousand arrangements).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-desktop-settings.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/DesktopCatSettingsTests.swift \
    -o "$TEST_DIR/desktop-settings-tests"
"$TEST_DIR/desktop-settings-tests"
```

```bash
chmod +x scripts/test-cat-desktop-settings.sh
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash scripts/test-cat-desktop-settings.sh 2>&1 | grep -E "error opening input file" | head -2`
Expected: FAIL: `error opening input file` (the two Swift files do not exist yet).

- [ ] **Step 3: Write the code**

`DesktopCatSpots` is the port of H-0's sizes and spots. Three things a port gets wrong are in it on purpose: `round` is `floor(v + 0.5)` and not Swift's `rounded()`, `isScreenKey` matches the whole string byte by byte (an ICU `$` would let a trailing newline through, and `٠` is not a digit), and `tidy` sorts by frame with the index as the tie-break, because JavaScript's sort is stable and Swift's is not.

**Create `NotchBuddy/Sources/App/DesktopCatSpots.swift`**:

```swift
import Foundation

// Where the desktop cat sits (sub-project H): the screens, the key an arrangement of them is remembered under, and the spot kept for each. Port of the "The desktop cat: size,
// frame rate and kittens" (sizes) and "spots on the screens" sections of design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/desktop-cases.json pins it.
// Coordinates are points, y down, the origin at the top left of the main screen. The Mac converts from AppKit's bottom-left origin (`DesktopCatScreens` in
// DesktopCatLayout.swift: `yTop = primaryHeight - frame.maxY`). A spot is the cat's head centre. Foundation only; nothing here knows about AppKit, UserDefaults or the app.

/// The desktop cat's three sizes. The raw values are frozen contract values, like the cat IDs: they are stored. `medium` is the default.
enum DesktopSize: String, CaseIterable, Sendable {
    case small, medium, large

    /// The head width in points (`DESKTOP_SIZES`).
    var d: Double {
        switch self {
        case .small: return 48
        case .medium: return 64
        case .large: return 96
        }
    }

    /// A stored size to one of the three; anything else (a wrong case, a number, a space) is `medium`.
    static func of(_ v: Any?) -> DesktopSize { (v as? String).flatMap { DesktopSize(rawValue: $0) } ?? .medium }
}

struct DesktopRect: Equatable, Sendable {
    var x: Double, y: Double, w: Double, h: Double
}

/// A screen: `frame` the whole screen, `visible` what the menu bar and the Dock leave, `main` the one with the menu bar.
struct DesktopScreen: Equatable, Sendable {
    var frame: DesktopRect
    var visible: DesktopRect
    var main = false
}

/// The cat's head centre.
struct DesktopSpot: Equatable, Sendable {
    var x: Double, y: Double
}

enum DesktopCatSpots {
    /// The cat keeps this many points between its head and the edge of the visible frame, so it never sits under the menu bar or the Dock.
    static let margin = 24.0
    /// The first spot ever: this fraction of the main screen's visible frame across (right of centre) and down (a third, below the notch).
    static let defaultAcross = 0.6, defaultDown = 1.0 / 3
    /// A stored map keeps the spots of at most this many screen arrangements (the first by code-point order of their keys).
    static let maxSpots = 32
    /// A spot's coordinates are no larger than this; a frame's no larger than `rectLimit`; at most `maxScreens` screens count.
    static let spotLimit = 1e5, rectLimit = 1e6, maxScreens = 16

    // MARK: Raw values (the fixtures and a hand-edited file hold anything)

    /// A JSON number: a boolean, text and null are not numbers, and neither are NaN and infinity.
    static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }

    static func isValid(_ s: DesktopSpot) -> Bool { s.x.isFinite && s.y.isFinite && abs(s.x) <= spotLimit && abs(s.y) <= spotLimit }

    /// `{x, y}` of two numbers no larger than 100000 in size, reduced to those two; anything else is not a spot.
    static func spot(_ raw: Any?) -> DesktopSpot? {
        guard let o = raw as? [String: Any], let x = number(o["x"]), let y = number(o["y"]) else { return nil }
        let s = DesktopSpot(x: x, y: y)
        return isValid(s) ? s : nil
    }

    static func isValid(_ r: DesktopRect) -> Bool {
        [r.x, r.y, r.w, r.h].allSatisfy { $0.isFinite && abs($0) <= rectLimit } && r.w >= 1 && r.h >= 1
    }

    static func rect(_ raw: Any?) -> DesktopRect? {
        guard let o = raw as? [String: Any], let x = number(o["x"]), let y = number(o["y"]), let w = number(o["w"]), let h = number(o["h"]) else { return nil }
        let r = DesktopRect(x: x, y: y, w: w, h: h)
        return isValid(r) ? r : nil
    }

    /// The screens that are screens, as `tidy` makes them, from a raw list of `{frame, visible, main}` (at most 256 entries are looked at).
    static func screens(_ raw: Any?) -> [DesktopScreen] {
        var out: [DesktopScreen] = []
        for entry in (raw as? [Any] ?? []).prefix(256) {
            guard let s = entry as? [String: Any], let f = rect(s["frame"]) else { continue }
            let main = (s["main"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false
            out.append(DesktopScreen(frame: f, visible: rect(s["visible"]) ?? f, main: main))
        }
        return tidy(out)
    }

    /// The screens that are usable, sorted by frame and at most 16: a screen without a usable frame is dropped, and a visible frame that is outside its frame
    /// is the frame (otherwise it is held inside it). Idempotent.
    static func tidy(_ list: [DesktopScreen]) -> [DesktopScreen] {
        var out: [(Int, DesktopScreen)] = []
        for (i, s) in list.enumerated() where isValid(s.frame) {
            let f = s.frame, v = s.visible
            let x0 = isValid(v) ? max(v.x, f.x) : 0, y0 = isValid(v) ? max(v.y, f.y) : 0
            let x1 = isValid(v) ? min(v.x + v.w, f.x + f.w) : 0, y1 = isValid(v) ? min(v.y + v.h, f.y + f.h) : 0
            let visible = isValid(v) && x1 > x0 && y1 > y0 ? DesktopRect(x: x0, y: y0, w: x1 - x0, h: y1 - y0) : f
            out.append((i, DesktopScreen(frame: f, visible: visible, main: s.main)))
        }
        // JavaScript's sort is stable; Swift's is not guaranteed to be, so ties keep their order by index.
        out.sort { a, b in
            let p = a.1.frame, q = b.1.frame
            if p.x != q.x { return p.x < q.x }
            if p.y != q.y { return p.y < q.y }
            if p.w != q.w { return p.w < q.w }
            if p.h != q.h { return p.h < q.h }
            return a.0 < b.0
        }
        return out.prefix(maxScreens).map(\.1)
    }

    // MARK: The key

    /// `floor(v + 0.5)`: half up, not Swift's `rounded()` (which rounds half away from zero and differs below zero).
    static func round(_ v: Double) -> Double { (v + 0.5).rounded(.down) }

    /// The key an arrangement is remembered under: the frames rounded to whole points, sorted, written `x,y,w,h` and joined with `|`. The order the screens come in, the
    /// visible frames and the main flag do not matter (moving the Dock must not forget the spot). No usable screen: "".
    static func screenKey(_ screens: [DesktopScreen]) -> String {
        tidy(screens).map { s in [s.frame.x, s.frame.y, s.frame.w, s.frame.h].map { Int(round($0)) } }
            .sorted { a, b in a.lexicographicallyPrecedes(b) }
            .map { $0.map(String.init).joined(separator: ",") }
            .joined(separator: "|")
    }

    /// True for exactly the strings `screenKey` writes: the whole string (a trailing newline is not a key), no leading zeros or -0, positive sizes, frames in sorted order,
    /// at most 16.
    static func isScreenKey(_ v: Any?) -> Bool {
        guard let key = v as? String else { return false }
        let parts = key.split(separator: "|", omittingEmptySubsequences: false)
        guard (1...maxScreens).contains(parts.count) else { return false }
        func digits(_ s: Substring, signed: Bool) -> Double? {
            var u = Array(s.utf8)
            let negative = signed && u.first == 0x2D
            if negative { u.removeFirst() }
            guard (1...7).contains(u.count), u.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
            let value = Double(String(decoding: u, as: UTF8.self))!
            return negative ? -value : value
        }
        var list: [DesktopScreen] = []
        for part in parts {
            let f = part.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count == 4, let x = digits(f[0], signed: true), let y = digits(f[1], signed: true), let w = digits(f[2], signed: false), let h = digits(f[3], signed: false) else { return false }
            let r = DesktopRect(x: x, y: y, w: w, h: h)
            list.append(DesktopScreen(frame: r, visible: r))
        }
        return screenKey(list) == key
    }

    // MARK: Where the cat may sit

    static func contains(_ r: DesktopRect, _ p: DesktopSpot) -> Bool { p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h }

    /// The screen with the menu bar: the one marked main, else the one holding the origin, else the first by frame. Nil with no screens.
    static func mainScreen(_ list: [DesktopScreen]) -> DesktopScreen? {
        let s = tidy(list)
        return s.first { $0.main } ?? s.first { contains($0.frame, DesktopSpot(x: 0, y: 0)) } ?? s.first
    }

    /// The point held inside a screen's visible frame, `d / 2` plus the margin from every edge; a frame too small for that holds the centre.
    private static func place(_ s: DesktopScreen, _ p: DesktopSpot, _ d: Double) -> DesktopSpot {
        let v = s.visible, m = margin + d / 2
        func at(_ lo: Double, _ len: Double, _ c: Double) -> Double { len <= 2 * m ? lo + len / 2 : min(max(c, lo + m), lo + len - m) }
        return DesktopSpot(x: at(v.x, v.w, p.x), y: at(v.y, v.h, p.y))
    }

    /// The first spot ever, on the main screen. Nil with no screens.
    static func defaultSpot(_ screens: [DesktopScreen], size: DesktopSize) -> DesktopSpot? {
        guard let s = mainScreen(screens) else { return nil }
        let v = s.visible
        return place(s, DesktopSpot(x: v.x + v.w * defaultAcross, y: v.y + v.h * defaultDown), size.d)
    }

    /// Keeps a spot where the cat may sit: on the screen whose frame holds it, inside that screen's visible frame. A spot on no screen (its screen was unplugged, or it is
    /// not a spot) goes to the main screen's default spot. Nil with no screens.
    static func clampSpot(_ spot: DesktopSpot?, _ screens: [DesktopScreen], size: DesktopSize) -> DesktopSpot? {
        let list = tidy(screens)
        guard !list.isEmpty else { return nil }
        if let p = spot, isValid(p), let s = list.first(where: { contains($0.frame, p) }) { return place(s, p, size.d) }
        return defaultSpot(list, size: size)
    }

    // MARK: The stored map

    /// A stored map from screen key to spot, cleaned. It may be a dictionary or the JSON text of one (the Mac stores text; text that is not strict JSON is `{}`). A key
    /// `isScreenKey` refuses is dropped, and so is a value that is not a spot. The result holds at most 32 spots, the first by code-point order of the keys.
    static func cleanSpots(_ raw: Any?) -> [String: DesktopSpot] {
        var v = raw
        if let text = v as? String {
            let data = Data(text.utf8)
            v = Personality.isStrictJSON(data) ? try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) : nil
        }
        guard let map = v as? [String: Any] else { return [:] }
        var out: [String: DesktopSpot] = [:]
        for key in map.keys.filter({ isScreenKey($0) }).sorted(by: { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes(Array($1.unicodeScalars.map(\.value))) }) {
            if out.count >= maxSpots { break }
            if let s = spot(map[key]) { out[key] = s }
        }
        return out
    }

    /// The spot to use now: the one remembered for this arrangement, held where the cat may sit, else the default spot. Nil with no screens.
    static func spotFor(_ spots: [String: DesktopSpot], _ screens: [DesktopScreen], size: DesktopSize) -> DesktopSpot? {
        let list = tidy(screens)
        guard !list.isEmpty else { return nil }
        if let s = spots[screenKey(list)] { return clampSpot(s, list, size: size) }
        return defaultSpot(list, size: size)
    }

    /// The map after the cat was released at `spot` on these screens: this arrangement's spot is the clamped one, the others stay. The map keeps at most 32 arrangements
    /// and always keeps the one just written. With no screens nothing changes.
    static func rememberSpot(_ spots: [String: DesktopSpot], _ screens: [DesktopScreen], _ spot: DesktopSpot, size: DesktopSize) -> [String: DesktopSpot] {
        let m = cleanSpots(spots.mapValues { ["x": $0.x, "y": $0.y] })
        guard let c = clampSpot(spot, screens, size: size) else { return m }
        let k = screenKey(screens)
        let others = m.keys.filter { $0 != k }.sorted { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes(Array($1.unicodeScalars.map(\.value))) }
        var out: [String: DesktopSpot] = [:]
        for q in others.prefix(maxSpots - 1) { out[q] = m[q] }
        out[k] = c
        return out
    }
}
```

`DesktopCatSettings` is the port of `cleanDesktopSettings`, and the Mac's three UserDefaults keys. It reads `on` as the object it is, so the number 1 and the text "true" stay off.

**Create `NotchBuddy/Sources/App/DesktopCatSettings.swift`**:

```swift
import Foundation

// What the desktop cat saves, and how it is cleaned: whether it is out, its size, and its spot for each arrangement of screens. Port of `cleanDesktopSettings` in
// design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/desktop-cases.json pins it. It is a clean-up of its own, as `CatDisplaySettings.clean` is: `CatSettings.clean`,
// `CatDisplaySettings.clean` and every line of their fixtures are as they were, and the store cleans the same stored block with each function it needs. A preferences file can be
// hand-edited or half written, so everything read back goes through `DesktopCatSettings.clean`: raw in, clean out, never a throw. The UserDefaults keys are `cat.desktop.on` (a
// Bool), `cat.desktop.size` (`small`, `medium` or `large`) and `cat.desktop.spots` (the JSON text of the map): `DesktopCatSettings.Key`. Foundation only.

struct DesktopCatSettings: Equatable, Sendable {
    /// Whether the cat is out on the desktop. The trip stores `DESKTOP_PHASE_INFO[phase].on`, so quitting mid-flight home leaves the cat in the notch.
    var on = false
    var size = DesktopSize.medium
    /// The spot remembered for each arrangement of screens, by `DesktopCatSpots.screenKey`.
    var spots: [String: DesktopSpot] = [:]

    // MARK: Cleaning

    /// `true` only for the boolean true: the number 1 and the text "true" are off (`UserDefaults.bool(forKey:)` would turn both into true, so the stored object is read as it is).
    static func isTrue(_ v: Any?) -> Bool {
        guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return false }
        return n.boolValue
    }

    /// Everything the desktop cat saves, cleaned. `raw` is a dictionary shaped like `{on, size, spots}`; anything else gives the defaults. Never throws.
    static func clean(_ raw: Any?) -> DesktopCatSettings {
        let r = raw as? [String: Any] ?? [:]
        return DesktopCatSettings(on: isTrue(r["on"]), size: DesktopSize.of(r["size"]), spots: DesktopCatSpots.cleanSpots(r["spots"]))
    }

    /// The settings as the fixtures hold them, a JSON-shaped dictionary.
    var json: [String: Any] { ["on": on, "size": size.rawValue, "spots": spots.mapValues { ["x": $0.x, "y": $0.y] } as [String: Any]] }

    // MARK: Edits

    /// What one control changes: each takes this clean value and returns a new clean one with one thing changed, and never touches its input.
    func withOn(_ on: Bool) -> DesktopCatSettings { var s = self; s.on = on; return s }
    func withSize(_ size: DesktopSize) -> DesktopCatSettings { var s = self; s.size = size; return s }
    /// The cat was released at `spot`: this arrangement's spot is the clamped one (`DesktopCatSpots.rememberSpot`).
    func remembering(_ spot: DesktopSpot, on screens: [DesktopScreen]) -> DesktopCatSettings {
        var s = self
        s.spots = DesktopCatSpots.rememberSpot(spots, screens, spot, size: size)
        return s
    }
    /// The spot to put the cat on now (`DesktopCatSpots.spotFor`).
    func spot(on screens: [DesktopScreen]) -> DesktopSpot? { DesktopCatSpots.spotFor(spots, screens, size: size) }

    // MARK: UserDefaults

    enum Key {
        static let on = "cat.desktop.on", size = "cat.desktop.size", spots = "cat.desktop.spots"
        static let all = [on, size, spots]
    }

    /// What is stored, cleaned. Only the keys that are there are read, each as the object it is (an `on` of `1` stays a number, so it is off). Nothing here can throw.
    static func load(from store: any CatSettingsBacking) -> DesktopCatSettings {
        var raw: [String: Any] = [:]
        for (key, field) in [(Key.on, "on"), (Key.size, "size"), (Key.spots, "spots")] { if let v = store.object(forKey: key) { raw[field] = v } }
        return clean(raw)
    }

    /// The map as it is stored: the JSON text of screen key to `{x, y}`, keys in order, so the same map is always the same text.
    var spotsText: String {
        let object = spots.mapValues { ["x": $0.x, "y": $0.y] } as [String: Any]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Writes what differs from `old` (everything, when there is no `old`). Only a cleaned value is ever passed in, so nothing that did not go through the clean-up is stored.
    func save(to store: any CatSettingsBacking, replacing old: DesktopCatSettings? = nil) {
        if old?.on != on { store.set(on, forKey: Key.on) }
        if old?.size != size { store.set(size.rawValue, forKey: Key.size) }
        if old?.spots != spots { store.set(spotsText, forKey: Key.spots) }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `bash scripts/test-cat-desktop-settings.sh 2>&1 | tail -3`
Expected: PASS, `All tests passed.`

Run: `bash scripts/test-cat-desktop-settings.sh 2>&1 | grep -c "✓"`
Expected: a count of 48 `✓` lines.

- [ ] **Step 5: Prove the tests bite**

Two mistakes a port makes, put in by hand and taken out again: rounding the way Swift does, and a map that keeps the arrangement it is about to overwrite.

```bash
F=NotchBuddy/Sources/App/DesktopCatSpots.swift
cp "$F" "${TMPDIR:-/tmp}/h-mac-spots.keep"
sed -i '' 's/(v + 0.5).rounded(.down)/v.rounded()/' "$F"
bash scripts/test-cat-desktop-settings.sh 2>&1 | grep -E "✗|failed"
cp "${TMPDIR:-/tmp}/h-mac-spots.keep" "$F"
sed -i '' 's/let others = m.keys.filter { \$0 != k }/let others = m.keys/' "$F"
bash scripts/test-cat-desktop-settings.sh 2>&1 | grep -E "✗|failed"
cp "${TMPDIR:-/tmp}/h-mac-spots.keep" "$F"
bash scripts/test-cat-desktop-settings.sh 2>&1 | tail -1
```

Expected: FAIL with the first mistake (`every key is as the fixture says`, `half rounds up…` and `so a frame is written rounded half up`, then `3 test(s) failed.`), FAIL with the second (`the clamped spot is kept for this arrangement…`, `1 test(s) failed.`), and `All tests passed.` once the file is back.

- [ ] **Step 6: Commit**

The two files are new, so the project is regenerated and its file is committed with them.

```bash
cd NotchBuddy && xcodegen > /dev/null && cd ..
```

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and h-mac/desktop-cat: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/h-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(cat): the desktop cat's screens, spots and stored settings, from desktop-cases.json

DesktopCatSpots (screenKey, isScreenKey, clampSpot, spotFor, rememberSpot, cleanSpots) and DesktopCatSettings (cleanDesktopSettings and the keys cat.desktop.on, cat.desktop.size and cat.desktop.spots) against desktop-cases.json, with the inputs the fixture cannot write.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/DesktopCatSpots.swift NotchBuddy/Sources/App/DesktopCatSettings.swift tests/DesktopCatSettingsTests.swift scripts/test-cat-desktop-settings.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F "$MSG"
git status --short   # nothing of this task is left over
```


---

### Task 2: The store holds the desktop settings (step 1)

**Agent:** `nm-implementer-light` (Haiku 5.5, medium). The edits are given in full.

**Files:**
- Modify: `NotchBuddy/Sources/App/CatSettingsStore.swift`, `tests/CatSettingsStoreTests.swift`, `scripts/test-cat-settings-store.sh`, `scripts/render-cat-settings.sh`

**Interfaces:**
- Consumes: Task 1's `DesktopCatSettings`, `DesktopSpot`, `DesktopScreen`, `DesktopSize`; A's `CatSettingsStore`, `CatSettingsBacking`.
- Produces: `CatSettingsStore.desktop` (published, read-only outside), `updateDesktop(_:)`, `setDesktopOn(_:)`, `setDesktopSize(_:)`, `rememberDesktopSpot(_:on:)`. Every change is cleaned (`DesktopCatSettings.clean`) before it is published or saved, and only the keys that changed are written.

- [ ] **Step 1: Write the failing test**

The store's test gets a section: the stored block is loaded, nothing is written at load, the switch is stored as a real Bool, the size and the clamped spot are stored, the Main cat's row writes no desktop key, a bad value is cleaned, a second store reads the same back, and a store that is wrong in every way loads the defaults without writing.

**Edit `tests/CatSettingsStoreTests.swift`**, find this text (it occurs exactly once):

```swift
        func next() -> Double { draws += 1; return rng.next() }
```

and replace it with:

```swift
        func next() -> Double { draws += 1; return rng.next() }
    }

    /// H: whether the desktop cat is out, its size and its spots are held, saved and cleaned by the same store.
    @MainActor static func desktopSettings() {
        CT.section("desktop settings: the store starts from what is stored, saves only what changed and cleans what it is given")
        let laptop = DesktopCatSpots.screens([["frame": ["x": 0, "y": 0, "w": 1512, "h": 982], "visible": ["x": 0, "y": 37, "w": 1512, "h": 875], "main": true]])
        let mem = MemoryBacking()
        mem.values = ["cat.desktop.on": true, "cat.desktop.size": "large", "cat.desktop.spots": "{\"0,0,1512,982\":{\"x\":300,\"y\":400}}", "cat.character": "latte"]
        let store = CatSettingsStore(backing: mem, config: CatConfig())
        CT.check("the stored desktop settings are loaded", store.desktop, DesktopCatSettings(on: true, size: .large, spots: ["0,0,1512,982": DesktopSpot(x: 300, y: 400)]))
        CT.check("and the Cat settings beside them", store.settings.character, "latte")
        CT.check("nothing was written yet", mem.writes.count, 0)
        store.setDesktopOn(false)
        CT.check("the switch, stored as a real Bool", [store.desktop.on, mem.values["cat.desktop.on"] as? Bool ?? true], [false, false])
        store.setDesktopOn(false)
        CT.check("the same switch again writes nothing", mem.writes, ["cat.desktop.on"])
        store.setDesktopSize(.small)
        CT.check("the size", [store.desktop.size.rawValue, mem.values["cat.desktop.size"] as? String ?? ""], ["small", "small"])
        store.rememberDesktopSpot(DesktopSpot(x: 5, y: 5), on: laptop)
        CT.check("a released spot is stored clamped, for this arrangement", [store.desktop.spots["0,0,1512,982"] == DesktopSpot(x: 48, y: 85)], [true])
        CT.check("as text with its keys in order", mem.values["cat.desktop.spots"] as? String ?? "", "{\"0,0,1512,982\":{\"x\":48,\"y\":85}}")
        store.setCharacter("momo")
        CT.check("the Main cat is another row: no desktop key moves with it", mem.writes.last ?? "", "cat.character")
        store.updateDesktop { $0.size = DesktopSize.of("Huge"); $0.spots["nonsense"] = DesktopSpot(x: 1, y: 1) }
        CT.check("a bad value is cleaned before it is stored or used", [store.desktop.size.rawValue, "\(store.desktop.spots.count)"], ["medium", "1"])
        CT.check("a second store on the same keys reads the same settings back", CatSettingsStore(backing: mem, config: CatConfig()).desktop, store.desktop)
        let wild = MemoryBacking()
        wild.values = ["cat.desktop.on": 1, "cat.desktop.size": 96, "cat.desktop.spots": 7]
        CT.check("a store that is wrong in every way still loads the defaults", CatSettingsStore(backing: wild, config: CatConfig()).desktop, DesktopCatSettings())
        CT.check("and loading wrote nothing", wild.writes.count, 0)
```

**Edit `tests/CatSettingsStoreTests.swift`**, find this text (it occurs exactly once):

```swift
        displaySettings()
```

and replace it with:

```swift
        displaySettings()
        desktopSettings()
```

**Edit `scripts/test-cat-settings-store.sh`**, find this text (it occurs exactly once):

```bash
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatSettingsStore.swift \
```

and replace it with:

```bash
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/CatSettingsStore.swift \
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-settings-store.sh 2>&1 | grep -E "error:" | head -2`
Expected: FAIL with compile errors (`CatSettingsStore` has no member `desktop`).

- [ ] **Step 3: Write the code**

The store loads the block with the others, and a change is one edit of one field, cleaned the way `update` and `updateDisplay` clean theirs.

**Edit `NotchBuddy/Sources/App/CatSettingsStore.swift`**, find this text (it occurs exactly once):

```swift
    @Published private(set) var display: CatDisplaySettings
```

and replace it with:

```swift
    @Published private(set) var display: CatDisplaySettings
    /// Settings → Cat → Cat on the desktop and the cat's own menu: whether the big cat is out, its size and its spot for each arrangement of screens. Cleaned by its own
    /// `DesktopCatSettings.clean`, beside the Cat settings and the Display settings.
    @Published private(set) var desktop: DesktopCatSettings
```

**Edit `NotchBuddy/Sources/App/CatSettingsStore.swift`**, find this text (it occurs exactly once):

```swift
        display = CatDisplaySettings.load(from: backing)
```

and replace it with:

```swift
        display = CatDisplaySettings.load(from: backing)
        desktop = DesktopCatSettings.load(from: backing)
```

**Edit `NotchBuddy/Sources/App/CatSettingsStore.swift`**, find this text (it occurs exactly once):

```swift
        updateDisplay { $0.agentCats = map }
    }
}
```

and replace it with:

```swift
        updateDisplay { $0.agentCats = map }
    }

    // MARK: The desktop cat

    /// Changes the desktop settings the same way `update` changes the Cat settings: the closure edits a copy, the copy is cleaned, and when it differs it is published and
    /// saved (only the keys that changed).
    func updateDesktop(_ change: (inout DesktopCatSettings) -> Void) {
        var next = desktop
        change(&next)
        next = DesktopCatSettings.clean(next.json)
        guard next != desktop else { return }
        next.save(to: backing, replacing: desktop)
        desktop = next
    }
    /// Whether the cat is out. The trip stores `DESKTOP_PHASE_INFO[phase].on` (`DesktopPhase.on`), so a cat that quit mid-flight home is home at the next launch.
    func setDesktopOn(_ on: Bool) { updateDesktop { $0 = $0.withOn(on) } }
    func setDesktopSize(_ size: DesktopSize) { updateDesktop { $0 = $0.withSize(size) } }
    /// The cat was released at `spot` (AppKit's coordinates already turned into the contract's: `DesktopCatScreens`): this arrangement keeps the clamped spot.
    func rememberDesktopSpot(_ spot: DesktopSpot, on screens: [DesktopScreen]) { updateDesktop { $0 = $0.remembering(spot, on: screens) } }
}
```

- [ ] **Step 4: Run the test to see it pass, and the Settings sheet to see it draw**

Run: `bash scripts/test-cat-settings-store.sh 2>&1 | tail -3`
Expected: PASS, `All tests passed.`

`scripts/render-cat-settings.sh` compiles `CatSettingsStore.swift`, so it gets the two new files. At the base it also lacks `CatKittens.swift` (see Task 0), which is added here because Task 8 draws Settings with it.

**Edit `scripts/render-cat-settings.sh`**, find this text (it occurs exactly once):

```bash
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatIslandLayout.swift $APP/CatSettingsStore.swift $APP/CatDisplayPreview.swift $APP/CatSettingsView.swift \
```

and replace it with:

```bash
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatKittens.swift $APP/CatIslandLayout.swift $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/CatSettingsStore.swift $APP/CatDisplayPreview.swift $APP/CatSettingsView.swift \
```

Run: `mkdir -p "${TMPDIR:-/tmp}/h-mac-1" && bash scripts/render-cat-settings.sh --out "${TMPDIR:-/tmp}/h-mac-1/settings-base.png" 2>&1 | tail -1`
Expected: `wrote …/h-mac-1/settings-base.png`. Look at it: Settings → Cat as it was (Display first), no Desktop group yet.

- [ ] **Step 5: Build the app**

The two files of Task 1 and this task's store edit are compiled into the app for the first time.

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. Do not open the app.

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and h-mac/desktop-cat: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/h-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(cat): the store holds the desktop cat's settings

CatSettingsStore.desktop with setDesktopOn, setDesktopSize and rememberDesktopSpot, cleaned and saved the way the Cat and Display settings are; render-cat-settings.sh lists the files it compiles (including CatKittens.swift, which it lacked).

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/CatSettingsStore.swift tests/CatSettingsStoreTests.swift scripts/test-cat-settings-store.sh scripts/render-cat-settings.sh
git commit -F "$MSG"
git status --short   # nothing of this task is left over
```


---

### Task 3: The trip in Swift: `desktopStep`, the flight and its clock, `desktopFps`, the kittens' slots

**Agent:** `nm-implementer-light` (Haiku 5.5, medium). The code is given in full; the tests prove it.

**Files:**
- Create: `NotchBuddy/Sources/App/DesktopCatTrip.swift`, `tests/DesktopCatTripTests.swift`, `scripts/test-cat-desktop-trip.sh`
- Modify: `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated)

**Interfaces:**
- Consumes: H-0's `DESKTOP_PHASES`, `DESKTOP_PHASE_INFO`, `DESKTOP_EVENTS`, `DESKTOP_ACTS`, `DESKTOP_NEXT`, `desktopStep`, `DESKTOP_FLIGHT_MS`, `DESKTOP_ARC`, `desktopFlightAt`, `DESKTOP_FPS`, `DESKTOP_NEAR`, `desktopFps`, `DESKTOP_KITTEN_PLACE`, `desktopKittenSlots`, and the fixture's `phaseIds`, `phases`, `events`, `acts`, `flightMs`, `arc`, `steps`, `trips`, `flights`, `fps`, `near`, `fpsCases`, `kittenPlace`, `kittenSlots`, `kittenSizes`; Task 1's `DesktopSpot`, `DesktopCatSpots.isValid` and `.number`; B's `CatKittens` (`Kitten`, `State`, `Slots`, `isKittenId`), `CatEase.inOut`.
- Produces: `DesktopPhase` (the seven phases: `flight`, `dir`, `drawn`, `notchEmpty`, `on`), `DesktopAct`, `DesktopEvent`; `DesktopCatTrip.step(_ state:_ event:)` and `step(rawState:rawEvent:)` returning `(state, act)`; `flightAt(from:to:t:)`, `flightMs`; `DesktopCatTrip.Flight` (`start`, `home`, `notchEnd`, `desktopEnd`, `progress(at:)`, `isDone(at:)`, `position(at:)`, `turned(at:)`, `withNotchEnd(_:)`, `withDesktopEnd(_:)`); `FpsInput` and `fps(_:)`, `fps(raw:)` with the constants `fpsMotion`, `fpsActive`, `fpsIdle`, `fpsAsleep`, `fpsOff`, `near`; `kittenSlots(_:side:)` returning `CatKittens.Slots` with place `"desktop"` (B's `CatKittens.places` is untouched).

- [ ] **Step 1: Write the failing tests**

The program replays all 89 `steps` rows (the 63 pairs of seven phases and nine events, and input that is neither), the 11 `trips`, the 89 `flights`, the 39 `fpsCases`, the 21 `kittenSlots` and the 12 `kittenSizes`, and adds what the fixture cannot write: a NaN spot, a `t` or a clock that is not a number, a cursor distance of NaN or infinity, and the flight's clock (a turn at any moment leaves the cat exactly where it was).

**Create `tests/DesktopCatTripTests.swift`**:

```swift
import Foundation

@main
enum DesktopCatTripTests {
    typealias T = DesktopCatTrip

    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func num(_ v: Any?) -> Double { (v as! NSNumber).doubleValue }
    static func step(_ r: (state: DesktopPhase, act: DesktopAct?)) -> [String: Any] { ["state": r.state.rawValue, "act": r.act?.rawValue ?? NSNull()] }
    static func spot(_ x: Double, _ y: Double) -> DesktopSpot { DesktopSpot(x: x, y: y) }

    /// The fixture's kittens, in the app's types: an entry that is not an object with a text id is not a kitten (the app never builds one); a state that is not text is working.
    static func kittens(_ raw: Any?) -> [CatKittens.Kitten] {
        (raw as? [Any] ?? []).compactMap { entry in
            guard let k = entry as? [String: Any], let id = k["id"] as? String else { return nil }
            return CatKittens.Kitten(id: id, state: (k["state"] as? String).flatMap { CatKittens.State(rawValue: $0) } ?? .working, born: 0, last: 0)
        }
    }

    @MainActor static func main() {
        let fx = CT.fixture("desktop-cases.json")

        CT.section("the frozen values: the seven phases, their table, the nine events, the eleven acts, the flight and the frame rates")
        CT.check("the phases, in order", DesktopPhase.allCases.map(\.rawValue), fx["phaseIds"] as! [String])
        var diffs: [String] = []
        let table = fx["phases"] as! [String: [String: Any]]
        for p in DesktopPhase.allCases {
            let row = table[p.rawValue]!
            let got: [String: Any] = ["flight": p.flight, "dir": p.dir?.rawValue ?? NSNull(), "drawn": p.drawn, "notchEmpty": p.notchEmpty, "on": p.on]
            let d = CT.diffs(got, row)
            if !d.isEmpty { diffs.append("\(p.rawValue): \(d.first!)") }
            if p.drawn && !p.notchEmpty { diffs.append("\(p.rawValue): two copies of one cat") }
        }
        CT.checkRows("what each phase means is the fixture's, and a drawn phase has an empty notch spot", diffs)
        CT.check("the acts, in order", DesktopAct.allCases.map(\.rawValue), fx["acts"] as! [String])
        CT.checkNear("the flight takes 600 ms", T.flightMs, num(fx["flightMs"]))
        let arc = fx["arc"] as! [String: Any]
        CT.check("the arc bows a quarter of the distance, at most 90 points", [T.arcLift, T.arcMax], [num(arc["lift"]), num(arc["max"])])
        let fps = fx["fps"] as! [String: Any]
        CT.check("the frame rates", [T.fpsMotion, T.fpsActive, T.fpsIdle, T.fpsAsleep, T.fpsOff], [num(fps["motion"]), num(fps["active"]), num(fps["idle"]), num(fps["asleep"]), num(fps["off"])])
        CT.checkNear("near is 150 points", T.near, num(fx["near"]))

        CT.section("desktopStep: \(rows(fx["steps"]).count) rows, every phase and event, and input that is neither")
        diffs = []
        for c in rows(fx["steps"]) {
            let d = CT.diffs(step(T.step(rawState: c["state"], rawEvent: c["event"])), c["out"]!)
            if !d.isEmpty { diffs.append("\(c["state"] ?? "nil") + \(c["event"] ?? "nil"): \(d.first!)") }
        }
        CT.checkRows("every step is as the fixture says", diffs)

        CT.section("trips: \(rows(fx["trips"]).count) scripts of events, the state and the act after each")
        for c in rows(fx["trips"]) {
            var s = DesktopPhase(rawValue: c["from"] as! String) ?? .home
            var got: [[String: Any]] = []
            for e in c["events"] as! [Any] { let r = T.step(rawState: s.rawValue, rawEvent: e); s = r.state; got.append(step(r)) }
            CT.checkJSON(c["name"] as! String, got: got, want: c["out"]!)
        }

        CT.section("the typed machine is the raw one: a spot that is NaN is not a spot")
        CT.checkJSON("a drag out with a NaN spot changes nothing", got: step(T.step(.home, .dragOut(spot(.nan, 1)))), want: step((.home, nil)))
        CT.checkJSON("so does a move to infinity", got: step(T.step(.onDesktop, .move(spot(.infinity, 1)))), want: step((.onDesktop, nil)))
        CT.checkJSON("a move to a real spot is the move act", got: step(T.step(.onDesktop, .move(spot(10, 20)))), want: step((.onDesktop, .move)))
        CT.checkTrue("an alert while the cat is home does not take it out", T.step(.home, .alertOn).act == nil && T.step(.home, .alertOn).state == .home)
        CT.checkTrue("an alert while it flies home does not turn it round", T.step(.flyingHome, .alertOn).state == .flyingHome)

        CT.section("desktopFlightAt: \(rows(fx["flights"]).count) points on the arc")
        diffs = []
        for c in rows(fx["flights"]) {
            let t: Double = (c["t"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() ? .nan : $0.doubleValue } ?? .nan   // text and null are not numbers: t is 0
            let p = T.flightAt(from: DesktopCatSpots.spot(c["from"]), to: DesktopCatSpots.spot(c["to"]), t: t)
            let d = CT.diffs(["x": p.x, "y": p.y, "scale": p.scale], c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"] as! String) at \(c["t"] ?? "nil"): \(d.first!)") }
        }
        CT.checkRows("every point is as the fixture says (eased, bowed upwards, full size)", diffs)
        CT.checkTrue("a t that is NaN is the start", T.flightAt(from: spot(10, 20), to: spot(100, 200), t: .nan).x == 10)
        CT.checkTrue("and infinity is the end", abs(T.flightAt(from: spot(10, 20), to: spot(100, 200), t: .infinity).x - 100) < 1e-9)

        CT.section("the flight's clock: it runs 600 ms, a turn does not make the cat jump, and the notch end can move")
        let fl = T.Flight.start(.out, notch: spot(756, 16), desktop: spot(907, 328), at: 1000)
        CT.check("it starts at the notch", [fl.position(at: 1000).x, fl.position(at: 1000).y], [756, 16])
        CT.checkNear("and ends at the desktop spot", fl.position(at: 1600).x, 907)
        CT.check("progress is held to 0...1 and a clock that is NaN is the start", [fl.progress(at: 900), fl.progress(at: 1300), fl.progress(at: 9999), fl.progress(at: .nan)], [0, 0.5, 1, 0])
        CT.check("done at 600 ms and not before", [fl.isDone(at: 1599), fl.isDone(at: 1600)], [false, true])
        let inbound = T.Flight.start(.in, notch: spot(756, 16), desktop: spot(907, 328), at: 0)
        CT.check("the notch end of an out flight is its start, of an in flight its end", [fl.notchEnd, fl.desktopEnd, inbound.notchEnd], [spot(756, 16), spot(907, 328), spot(756, 16)])
        var worst = 0.0
        for ms in stride(from: 1000.0, through: 1600.0, by: 25) {
            let before = fl.position(at: ms), after = fl.turned(at: ms).position(at: ms)
            worst = max(worst, hypot(before.x - after.x, before.y - after.y))
        }
        CT.checkTrue("turned at any moment, the cat is exactly where it was (worst jump \(worst))", worst < 1e-9)
        let back = fl.turned(at: 1200)
        CT.check("a turned flight flies the other way", back.dir.rawValue, "in")
        CT.checkNear("and has the same time left to go as it had come (200 ms of 600 become 400 to go)", back.progress(at: 1200), 1 - fl.progress(at: 1200))
        CT.checkNear("it reaches the notch after the remaining time", back.position(at: 1200 + 0.2 * 600 * 2).x, 756, tol: 1e-6)
        CT.checkTrue("turned twice, it is the flight it was", fl.turned(at: 1200).turned(at: 1200).position(at: 1400).x - fl.position(at: 1400).x < 1e-9)
        let moved = fl.withNotchEnd(spot(700, 300))
        CT.check("the notch end moves and the desktop end stays", [moved.from, moved.to], [spot(700, 300), spot(907, 328)])
        CT.check("an in flight changes its end instead", inbound.withNotchEnd(spot(700, 300)).to, spot(700, 300))
        CT.check("the desktop end moves too (the screens changed) and the notch end stays", [fl.withDesktopEnd(spot(500, 500)).from, fl.withDesktopEnd(spot(500, 500)).to, inbound.withDesktopEnd(spot(500, 500)).from, inbound.withDesktopEnd(spot(500, 500)).to], [spot(756, 16), spot(500, 500), spot(500, 500), spot(756, 16)])
        let drop = T.Flight.home(from: spot(400, 400), notch: spot(756, 16), at: 50)
        CT.check("a cat dropped on the notch flies from the drop point, inwards", [drop.position(at: 50) == spot(400, 400), drop.dir == .in], [true, true])

        CT.section("desktopFps: \(rows(fx["fpsCases"]).count) rows")
        diffs = []
        for c in rows(fx["fpsCases"]) where T.fps(raw: c["input"]) != num(c["out"]) { diffs.append("\(c["name"] as! String): \(T.fps(raw: c["input"]))") }
        CT.checkRows("every rate is as the fixture says (only `true` counts for a flag, sleep beats the cursor, hidden beats everything)", diffs)
        CT.check("the typed rule: a cursor that is NaN is not near", T.fps(.init(phase: .onDesktop, cursorDist: .nan)), 5)
        CT.check("infinity is not near", T.fps(.init(phase: .onDesktop, cursorDist: .infinity)), 5)
        CT.check("150 points is near", T.fps(.init(phase: .onDesktop, cursorDist: 150)), 20)
        CT.check("a phase of nothing draws nothing", T.fps(.init(phase: nil, dragging: true)), 0)

        CT.section("the kittens' slots: \(rows(fx["kittenSlots"]).count) rows, and the same in points at each size")
        diffs = []
        for c in rows(fx["kittenSlots"]) {
            let side = (c["side"] as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.intValue } ?? 1
            let d = CT.diffs(T.kittenSlots(kittens(c["kittens"]), side: side).json, c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every slot is as the fixture says (up to three, then +N, mirrored on the left; things that are not kittens are skipped)", diffs)
        diffs = []
        for c in rows(fx["kittenSizes"]) {
            let size = DesktopSize(rawValue: c["size"] as! String)!
            let slots = T.kittenSlots((0..<(c["count"] as! Int)).map { CatKittens.Kitten(id: "k\($0)", state: [.approval, .searching, .working][$0 % 3], born: 0, last: 0) }, side: 1)
            let got: [String: Any] = ["size": size.rawValue, "d": size.d, "count": slots.count,
                                      "shown": slots.shown.map { ["id": $0.id, "state": $0.state, "x": $0.x * size.d, "y": $0.y * size.d, "d": $0.d * size.d] as [String: Any] }, "more": slots.more,
                                      "moreAt": slots.moreAt.map { ["x": $0.x * size.d, "y": $0.y * size.d, "size": $0.size * size.d] as [String: Any] } ?? NSNull()]
            let d = CT.diffs(got, c)
            if !d.isEmpty { diffs.append("\(size.rawValue) \(c["count"] ?? ""): \(d.first!)") }
        }
        CT.checkRows("one table serves Ø48, Ø64 and Ø96", diffs)
        CT.check("B's table is untouched: the big cat's kittens are still where they were", CatKittens.places["bigExpanded"]?.max, 3)
        CT.check("and the desktop is not one of its places", CatKittens.places["desktop"] == nil, true)
        let ids = (0..<5).map { CatKittens.Kitten(id: "k\($0)", state: .working, born: 0, last: 0) }
        CT.checkTrue("on the left the whole row mirrors, the +N too", T.kittenSlots(ids, side: -1).moreAt!.x == -T.kittenSlots(ids, side: 1).moreAt!.x && T.kittenSlots(ids, side: -1).shown.allSatisfy { $0.x < 0 })
        CT.checkTrue("a kitten with an empty id is skipped", T.kittenSlots([CatKittens.Kitten(id: "", state: .working, born: 0, last: 0)], side: 1).count == 0)
        CT.finish()
    }
}
```

**Create `scripts/test-cat-desktop-trip.sh`**:

```bash
#!/usr/bin/env bash
# Desktop cat trip (sub-project H): the seven phases and desktopStep (63 pairs and input that is neither), the trips, desktopFlightAt and the flight's clock (a turn does not make
# the cat jump), desktopFps and desktopKittenSlots against desktop-cases.json, and what the fixture cannot write (NaN, infinity, a clock that is not a number).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-desktop-trip.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatKittens.swift \
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/DesktopCatTripTests.swift \
    -o "$TEST_DIR/desktop-trip-tests"
"$TEST_DIR/desktop-trip-tests"
```

```bash
chmod +x scripts/test-cat-desktop-trip.sh
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash scripts/test-cat-desktop-trip.sh 2>&1 | grep -E "error opening input file" | head -2`
Expected: FAIL: `error opening input file`.

- [ ] **Step 3: Write the code**

The machine is a `switch` over (phase, event) that lists exactly the 27 pairs the contract lists; every other pair falls to `default` and changes nothing. `Flight` is the app's clock for a flight: `turned(at:)` swaps the ends and starts at progress `1 - t`, and because the arc is the same both ways the cat does not move.

**Create `NotchBuddy/Sources/App/DesktopCatTrip.swift`**:

```swift
import Foundation

// The desktop cat's trip (sub-project H): the seven phases and the one machine that moves between them, the flight between the notch and the desktop, the frame rate the cat
// aims for, and where its kittens sit. Port of "The desktop cat: the trip" and "size, frame rate and kittens" in design/prototype/cat-core.js (the tie-breaker);
// tests/fixtures/cat/desktop-cases.json pins it. Foundation only, pure, and nothing here throws. The app's side (windows, clocks, events) is `DesktopCatController`.

/// The phases of the trip. The raw values are frozen contract values, like the cat IDs.
enum DesktopPhase: String, CaseIterable, Sendable {
    case home, flyingOut, onDesktop, retracting, atNotchForAlert, returning, flyingHome

    /// Which way a flight goes: `out` towards the desktop spot, `in` towards the notch spot.
    enum Dir: String, Sendable { case out, `in` }

    /// The cat is in the air.
    var flight: Bool { dir != nil }
    var dir: Dir? {
        switch self {
        case .flyingOut, .returning: return .out
        case .retracting, .flyingHome: return .in
        case .home, .onDesktop, .atNotchForAlert: return nil
        }
    }
    /// The desktop window draws the cat.
    var drawn: Bool { self != .home && self != .atNotchForAlert }
    /// The big cat's spot in the notch is empty: never two copies of one cat (drawn implies notchEmpty).
    var notchEmpty: Bool { drawn }
    /// What Settings stores as "the cat is out": `home` and `flyingHome` are off, so quitting mid-flight leaves the cat home.
    var on: Bool {
        switch self {
        case .home, .flyingHome: return false
        case .flyingOut, .onDesktop, .retracting, .atNotchForAlert, .returning: return true
        }
    }
}

/// What the app does on a transition. `turn` reverses the flight in progress, `keep` lets it go on, and so on: see `docs/CAT-CONTRACT.md`, "The desktop cat (H-0)".
enum DesktopAct: String, CaseIterable, Sendable {
    case place, flyOut, flyHome, retract, turn, keep, land, dock, goHome, move, resettle
}

/// The events the machine takes. `dragOut` and `move` carry the spot (the head centre, y down).
enum DesktopEvent: Equatable, Sendable {
    case dragOut(DesktopSpot), move(DesktopSpot)
    case toggle, sendHome, alertOn, alertOff, flightDone, launch, screensChanged
}

enum DesktopCatTrip {
    // MARK: The machine

    /// phase → event → (next phase, act). An event that is not listed makes no sense in that phase and changes nothing.
    private static func next(_ s: DesktopPhase, _ e: DesktopEvent) -> (DesktopPhase, DesktopAct)? {
        switch (s, e) {
        case (.home, .dragOut): return (.onDesktop, .place)
        case (.home, .toggle), (.home, .launch): return (.flyingOut, .flyOut)

        case (.flyingOut, .toggle), (.flyingOut, .sendHome): return (.flyingHome, .turn)
        case (.flyingOut, .alertOn): return (.retracting, .turn)
        case (.flyingOut, .flightDone): return (.onDesktop, .land)
        case (.flyingOut, .screensChanged): return (.flyingOut, .resettle)

        case (.onDesktop, .move): return (.onDesktop, .move)
        case (.onDesktop, .toggle), (.onDesktop, .sendHome): return (.flyingHome, .flyHome)
        case (.onDesktop, .alertOn): return (.retracting, .retract)
        case (.onDesktop, .screensChanged): return (.onDesktop, .resettle)

        case (.retracting, .toggle), (.retracting, .sendHome): return (.flyingHome, .keep)
        case (.retracting, .alertOff): return (.returning, .turn)
        case (.retracting, .flightDone): return (.atNotchForAlert, .dock)

        case (.atNotchForAlert, .toggle), (.atNotchForAlert, .sendHome): return (.home, .goHome)
        case (.atNotchForAlert, .alertOff): return (.returning, .flyOut)

        case (.returning, .toggle), (.returning, .sendHome): return (.flyingHome, .turn)
        case (.returning, .alertOn): return (.retracting, .turn)
        case (.returning, .flightDone): return (.onDesktop, .land)
        case (.returning, .screensChanged): return (.returning, .resettle)

        case (.flyingHome, .toggle): return (.flyingOut, .turn)
        case (.flyingHome, .flightDone): return (.home, .dock)
        default: return nil
        }
    }

    /// The next phase and what the app does, or the same phase and `nil` when the event makes no sense there. A `dragOut` or `move` whose spot is not a spot changes nothing
    /// either. Pure, and it never throws.
    static func step(_ state: DesktopPhase, _ event: DesktopEvent) -> (state: DesktopPhase, act: DesktopAct?) {
        switch event {
        case .dragOut(let s), .move(let s): if !DesktopCatSpots.isValid(s) { return (state, nil) }
        default: break
        }
        guard let n = next(state, event) else { return (state, nil) }
        return (n.0, n.1)
    }

    /// The same machine for raw input (the fixtures, a notification's payload): a state that is not a phase counts as `home`; an event that is not an object with a known
    /// `type` changes nothing; `dragOut` and `move` need a valid `spot`.
    static func step(rawState: Any?, rawEvent: Any?) -> (state: DesktopPhase, act: DesktopAct?) {
        let s = (rawState as? String).flatMap { DesktopPhase(rawValue: $0) } ?? .home
        guard let e = event(rawEvent) else { return (s, nil) }
        return step(s, e)
    }

    static func event(_ raw: Any?) -> DesktopEvent? {
        guard let o = raw as? [String: Any], let type = o["type"] as? String else { return nil }
        switch type {
        case "dragOut": return DesktopCatSpots.spot(o["spot"]).map { .dragOut($0) }
        case "move": return DesktopCatSpots.spot(o["spot"]).map { .move($0) }
        case "toggle": return .toggle
        case "sendHome": return .sendHome
        case "alertOn": return .alertOn
        case "alertOff": return .alertOff
        case "flightDone": return .flightDone
        case "launch": return .launch
        case "screensChanged": return .screensChanged
        default: return nil
        }
    }

    // MARK: The flight

    /// The flight between the notch spot and the desktop spot takes this long (ms).
    static let flightMs = 600.0
    /// The arc bows `lift` of the distance away from the straight line, never more than `max` points, always upwards (a vertical flight bows to the right).
    static let arcLift = 0.25, arcMax = 90.0

    /// Where the cat is `t` (0 to 1, held to that range; NaN is 0) of the way along a flight: a quadratic arc eased in and out, with the cat at full size the whole way.
    /// The path is the same both ways: the position at `(from, to, t)` is the position at `(to, from, 1 - t)`, which is what makes a turn seamless.
    static func flightAt(from: DesktopSpot?, to: DesktopSpot?, t: Double) -> (x: Double, y: Double, scale: Double) {
        func ok(_ s: DesktopSpot?) -> DesktopSpot { s.flatMap { DesktopCatSpots.isValid($0) ? $0 : nil } ?? DesktopSpot(x: 0, y: 0) }
        let f = ok(from), g = ok(to)
        let k = t.isNaN ? 0 : min(max(t, 0), 1), q = CatEase.inOut.at(k)
        let dx = g.x - f.x, dy = g.y - f.y, len = hypot(dx, dy)
        var nx = 0.0, ny = 0.0
        if len > 0 {
            nx = dy / len; ny = -dx / len
            if ny > 0 || (ny == 0 && nx < 0) { nx = -nx; ny = -ny }
        }
        let lift = min(len * arcLift, arcMax), cx = (f.x + g.x) / 2 + nx * lift, cy = (f.y + g.y) / 2 + ny * lift, u = 1 - q
        return (u * u * f.x + 2 * u * q * cx + q * q * g.x, u * u * f.y + 2 * u * q * cy + q * q * g.y, 1)
    }

    /// A flight in progress: its ends, which way it goes and its clock. The app keeps one while the phase is a flight; `turned` and `withNotchEnd` are what `turn` and a change
    /// of the notch spot (compact or expanded) do to it.
    struct Flight: Equatable, Sendable {
        var from: DesktopSpot
        var to: DesktopSpot
        var dir: DesktopPhase.Dir
        /// On the clock the app reads (ms).
        var startMs: Double

        /// The flight as `out` or `in`: for `out` the notch is the start, for `in` it is the end.
        static func start(_ dir: DesktopPhase.Dir, notch: DesktopSpot, desktop: DesktopSpot, at ms: Double) -> Flight {
            dir == .out ? Flight(from: notch, to: desktop, dir: dir, startMs: ms) : Flight(from: desktop, to: notch, dir: dir, startMs: ms)
        }
        /// A flight that starts where the cat is on screen (a cat dropped on the notch flies the last bit from the drop point).
        static func home(from point: DesktopSpot, notch: DesktopSpot, at ms: Double) -> Flight { Flight(from: point, to: notch, dir: .in, startMs: ms) }

        var notchEnd: DesktopSpot { dir == .out ? from : to }
        var desktopEnd: DesktopSpot { dir == .out ? to : from }

        /// 0 to 1; a clock that is not a number is the start.
        func progress(at ms: Double) -> Double {
            let t = (ms - startMs) / DesktopCatTrip.flightMs
            return t.isNaN ? 0 : min(max(t, 0), 1)
        }
        func isDone(at ms: Double) -> Bool { progress(at: ms) >= 1 }
        func position(at ms: Double) -> DesktopSpot {
            let p = DesktopCatTrip.flightAt(from: from, to: to, t: progress(at: ms))
            return DesktopSpot(x: p.x, y: p.y)
        }
        /// `turn`: the flight keeps its clock, swaps its ends and carries on from progress `1 - t`, retracing its own path: the cat does not jump.
        func turned(at ms: Double) -> Flight {
            Flight(from: to, to: from, dir: dir == .out ? .in : .out, startMs: ms - (1 - progress(at: ms)) * DesktopCatTrip.flightMs)
        }
        /// The screens changed (`resettle`): the desktop end moves to the new spot and the notch end stays; the flight keeps its clock.
        func withDesktopEnd(_ spot: DesktopSpot) -> Flight {
            var f = self
            if dir == .out { f.to = spot } else { f.from = spot }
            return f
        }
        /// The notch spot moved (the island opened for an alert, or folded): the flight keeps its clock and its desktop end, and aims at the new notch end.
        func withNotchEnd(_ spot: DesktopSpot) -> Flight {
            var f = self
            if dir == .out { f.from = spot } else { f.to = spot }
            return f
        }
    }

    // MARK: Frame rate

    static let fpsMotion = 60.0, fpsActive = 20.0, fpsIdle = 5.0, fpsAsleep = 0.5, fpsOff = 0.0
    /// The cursor is "near" the cat within this many points of the cat's centre (inclusive).
    static let near = 150.0

    /// What the cat is doing. `phase` nil counts as not drawn. `cursorDist` is nil when the app cannot know it.
    struct FpsInput: Equatable, Sendable {
        var phase: DesktopPhase?
        var hidden = false, dragging = false, emote = false, kittenMotion = false, dance = false, asleep = false, working = false
        var cursorDist: Double?
    }

    /// The frame rate the app aims for, in this order: 0 when the phase is not drawn on the desktop or the cat cannot be seen (`hidden`); 60 for any motion (a flight
    /// included); 0.5 asleep (a still frame redrawn every 2 s); 20 working or with the cursor near; else 5. Sleep beats the cursor, and hidden beats everything.
    static func fps(_ i: FpsInput) -> Double {
        guard let phase = i.phase, phase.drawn, !i.hidden else { return fpsOff }
        if phase.flight || i.dragging || i.emote || i.kittenMotion || i.dance { return fpsMotion }
        if i.asleep { return fpsAsleep }
        if i.working || (i.cursorDist.map { $0.isFinite && $0 <= near } ?? false) { return fpsActive }
        return fpsIdle
    }

    /// The same rule for raw input: only `true` counts for a flag, and `cursorDist` only as a finite number; anything that is not an object, or has no phase, draws nothing.
    static func fps(raw: Any?) -> Double {
        guard let o = raw as? [String: Any] else { return fpsOff }
        func flag(_ k: String) -> Bool { DesktopCatSettings.isTrue(o[k]) }
        return fps(FpsInput(phase: (o["phase"] as? String).flatMap { DesktopPhase(rawValue: $0) }, hidden: flag("hidden"), dragging: flag("dragging"), emote: flag("emote"),
                            kittenMotion: flag("kittenMotion"), dance: flag("dance"), asleep: flag("asleep"), working: flag("working"), cursorDist: DesktopCatSpots.number(o["cursorDist"])))
    }

    // MARK: Kittens

    /// Where the desktop cat's kittens sit, in units of D (the head width, from the head centre, x right and y down): up to 3 of 0.3 D in a row at the lower right, then a "+N"
    /// at the next slot. A table of its own: `CatKittens.places` (which both apps copy and pin) is untouched.
    static let kittenMax = 3
    static let kittenD = 0.3, kittenX0 = 0.82, kittenY0 = 0.22, kittenStep = 0.33, kittenMoreSize = 0.2

    /// The slots for the cat's kittens (already in order). `side` -1 puts them on the left (a cat in the right half of its screen keeps them on screen); anything else is the right.
    static func kittenSlots(_ kittens: [CatKittens.Kitten], side: Int) -> CatKittens.Slots {
        let m = side == -1 ? -1.0 : 1.0
        let list = kittens.filter { CatKittens.isKittenId($0.id) }, count = list.count, n = min(count, kittenMax), more = count - n
        return CatKittens.Slots(
            place: "desktop", unit: "D", count: count,
            shown: list.prefix(n).enumerated().map { CatKittens.Slot(id: $1.id, state: $1.state.rawValue, x: m * (kittenX0 + Double($0) * kittenStep), y: kittenY0, d: kittenD) },
            more: more,
            moreAt: more > 0 ? CatKittens.More(x: m * (kittenX0 + Double(kittenMax) * kittenStep), y: kittenY0, size: kittenMoreSize) : nil,
            label: nil)
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `bash scripts/test-cat-desktop-trip.sh 2>&1 | tail -3`
Expected: PASS, `All tests passed.`

- [ ] **Step 5: Prove the tests bite**

A turn that keeps its progress instead of mirroring it (the cat jumps), and an alert that clears mid-flight and does not turn the cat round.

```bash
F=NotchBuddy/Sources/App/DesktopCatTrip.swift
cp "$F" "${TMPDIR:-/tmp}/h-mac-trip.keep"
sed -i '' 's/startMs: ms - (1 - progress(at: ms)) \* DesktopCatTrip.flightMs/startMs: ms - progress(at: ms) * DesktopCatTrip.flightMs/' "$F"
bash scripts/test-cat-desktop-trip.sh 2>&1 | grep -E "✗|failed"
cp "${TMPDIR:-/tmp}/h-mac-trip.keep" "$F"
sed -i '' 's/case (.retracting, .alertOff): return (.returning, .turn)/case (.retracting, .alertOff): return (.returning, .keep)/' "$F"
bash scripts/test-cat-desktop-trip.sh 2>&1 | grep -E "✗|failed"
cp "${TMPDIR:-/tmp}/h-mac-trip.keep" "$F"
bash scripts/test-cat-desktop-trip.sh 2>&1 | tail -1
```

Expected: FAIL with the first (`turned at any moment, the cat is exactly where it was (worst jump …)`, `and has the same time left…`, `it reaches the notch…`, `3 test(s) failed.`), FAIL with the second (`every step is as the fixture says`, `an alert that clears mid-flight turns the cat around`, `2 test(s) failed.`), and `All tests passed.` once the file is back.

- [ ] **Step 6: Commit**

```bash
cd NotchBuddy && xcodegen > /dev/null && cd ..
```

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and h-mac/desktop-cat: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/h-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(cat): the desktop cat's trip, flight, frame rate and kittens' slots, from desktop-cases.json

DesktopCatTrip: desktopStep (89 rows and 11 trips), desktopFlightAt and the flight's clock, desktopFps and desktopKittenSlots, with the inputs the fixture cannot write.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/DesktopCatTrip.swift tests/DesktopCatTripTests.swift scripts/test-cat-desktop-trip.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F "$MSG"
git status --short   # nothing of this task is left over
```


---

### Task 4: The window's geometry, the mouse rules, the drop rule and the pacer (pure)

**Agent:** `nm-implementer-light` (Haiku 5.5, medium). The code is given in full; the tests prove it.

**Files:**
- Create: `NotchBuddy/Sources/App/DesktopCatLayout.swift`, `DesktopCatInput.swift`, `DesktopCatDrop.swift`, `DesktopCatPacer.swift`; `tests/DesktopCatLayoutTests.swift`, `DesktopCatInputTests.swift`, `DesktopCatDropTests.swift`, `DesktopCatPacerTests.swift`; `scripts/test-cat-desktop-layout.sh`, `test-cat-desktop-input.sh`, `test-cat-desktop-drop.sh`, `test-cat-desktop-pacer.sh`
- Modify: `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated)

**Interfaces:**
- Consumes: Tasks 1 and 3 (`DesktopSpot`, `DesktopScreen`, `DesktopCatSpots`, `DesktopSize`, `DesktopCatTrip.kittenSlots`, `DesktopPhase`), B's `CatKittens` and `CatKittenDraw.labelWidth`'s formula.
- Produces: `DesktopCatScreens` (`AppKitScreen`, `primaryHeight`, `contract`, `spot(fromAppKit:_:primaryHeight:)`, `appKit(_:primaryHeight:)`), `DesktopCatFrame`, `DesktopCatLayout` (`frame(d:slots:)`, `side(of:screens:)`, `hits(_:d:slots:badge:)`, `origin(spot:frame:primaryHeight:)`, `labelWidth`, `notchSpot(screenFrame:islandW:cx:cy:)`); `DesktopCatClicks` (`down`, `dragged`, `up`, `timer`, `waitUntil`, `Out`) and `DesktopCatMenu` (`entries(size:shortcut:)`), `DesktopKittenWatch` (`observe(_:now:)`: the kittens are in motion for 600 ms after any change to the list, an arrival or a leave); `DesktopDrop` and `DesktopCatDrop.decide(point:screens:size:onIsland:windowUnder:contextCaptured:appStore:)`; `DesktopCatPacer` (`target(_:)` returning `.none`, `.stop` or `.arm(interval:leeway:)`, `interval`, `leeway`, `coreShare`) and `DesktopCatVisibility` (`hidden`).

**The numbers are plan decisions** (listed under "Open questions"): the window is the cat's square canvas (`D / 0.6`, as everywhere in the app) with room for hearts above it (`D * 40 / 58`, the island's 40 pt at Ø58) and, on the kittens' side, as far as the last kitten or "+N" reaches; the body that takes the mouse is the head circle of radius `0.55 D`, the badge's circle (centre `(0.7 D, -0.46 D)`, radius `0.2 D`, where `CatGeometry.layout` puts it) and the kittens' circles and label, nothing else; the kittens go to the left when the cat is in the right half of its screen's visible frame; a click acts after `NSEvent.doubleClickInterval`; a drag starts after more than 4 pt (the value both apps share); the double-click interval is `NSEvent.doubleClickInterval`, and 0.5 s when it is not a usable number; the drop rule is in the file's comments.

- [ ] **Step 1: Write the failing tests**

Four programs. The layout's checks every size and side (the window holds the canvas and every kitten, wider only on the kittens' side), the screen conversion (the Dock and the menu bar come out of the visible frame, a monitor above or beside the laptop), `side`, and `hits` at the edge of every shape; the input's, the click machine (a lone click, a double-click, a drag past 4 pt, a double-click's second press that turns into a drag, a time or an interval that is not a number), the kitten watch (a change of the list is motion for 600 ms, a clock that goes backwards is not), the menu and the notch spot; the drop's, every outcome in both builds; the pacer's, the intervals, the re-arming and what hides the cat.

**Create `tests/DesktopCatLayoutTests.swift`**:

```swift
import Foundation

@main
enum DesktopCatLayoutTests {
    typealias L = DesktopCatLayout
    typealias Sc = DesktopCatScreens
    typealias T = DesktopCatTrip

    static func spot(_ x: Double, _ y: Double) -> DesktopSpot { DesktopSpot(x: x, y: y) }
    static func kittens(_ n: Int) -> [CatKittens.Kitten] { (0..<n).map { CatKittens.Kitten(id: "k\($0)", state: .working, born: 0, last: 0) } }
    static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> DesktopRect { DesktopRect(x: x, y: y, w: w, h: h) }

    @MainActor static func main() {
        // A MacBook with a monitor above it and one to its right, as AppKit reports them: the origin at the bottom left of the main screen.
        let laptop = Sc.AppKitScreen(frame: rect(0, 0, 1512, 982), visible: rect(0, 78, 1512, 875))   // the Dock at the bottom, the menu bar on top
        let right = Sc.AppKitScreen(frame: rect(1512, -100, 2560, 1440), visible: rect(1512, -100, 2560, 1415))

        CT.section("AppKit's screens become the contract's: y flips around the main screen's top edge")
        CT.check("the main screen's height", Sc.primaryHeight([laptop, right]), 982)
        let c = Sc.contract([laptop, right])
        CT.check("the laptop: frame at the top left, the menu bar's 29 pt and the Dock's 78 pt taken out of the visible frame", [c[0].frame, c[0].visible], [rect(0, 0, 1512, 982), rect(0, 29, 1512, 875)])
        CT.check("the monitor to its right: its bottom (AppKit y -100) is 100 pt below the laptop's, so its top is 258 pt above it", [c[1].frame, c[1].visible], [rect(1512, 982 - 1340, 2560, 1440), rect(1512, 982 - 1340 + 25, 2560, 1415)])
        CT.check("only the first is the main one", [c[0].main, c[1].main], [true, false])
        CT.check("the key of the arrangement is the contract's (the Dock moving does not change it)", DesktopCatSpots.screenKey(c), "0,0,1512,982|1512,-358,2560,1440")
        CT.check("no screens, no conversion", [Double(Sc.contract([]).count), Sc.primaryHeight([])], [0, 0])
        CT.check("a point both ways", [Sc.spot(fromAppKit: 100, 900, primaryHeight: 982), spot(100, 82)], [spot(100, 82), spot(100, 82)])
        let back = Sc.appKit(spot(100, 82), primaryHeight: 982)
        CT.check("and back", [back.x, back.y], [100, 900])
        CT.checkTrue("the cat sits where the contract's clamp says, on the laptop's visible frame", DesktopCatSpots.clampSpot(spot(5, 5), c, size: .medium) == spot(56, 29 + 56))

        CT.section("the window: the canvas, the hearts above, and the kittens on their side, and no larger")
        for size in DesktopSize.allCases {
            let d = size.d, half = d / 0.6 / 2
            let none = L.frame(d: d, slots: T.kittenSlots([], side: 1))
            CT.checkNear("\(size.rawValue): with no kittens the window is the canvas wide (\(d / 0.6))", none.w, d / 0.6)
            CT.checkNear("\(size.rawValue): and the canvas plus the hearts tall", none.h, d / 0.6 + d * 40 / 58, tol: 1e-9)
            CT.check("\(size.rawValue): the head is centred across and sits one canvas-half below the hearts", [none.headX, none.headY], [half, half + d * 40 / 58])
            for side in [1, -1] {
                for n in [1, 3, 4, 8] {
                    let slots = T.kittenSlots(kittens(n), side: side)
                    let f = L.frame(d: d, slots: slots)
                    let reach = slots.shown.map { abs($0.x) * d + $0.d * d / 2 * 1.1 }.max() ?? 0
                    let farSide = side == 1 ? f.w - f.headX : f.headX, nearSide = side == 1 ? f.headX : f.w - f.headX
                    CT.checkTrue("\(size.rawValue), \(n) kittens, side \(side): the window holds the last kitten, and is wider than the canvas only on the kittens' side", farSide >= reach - 1e-9 && abs(nearSide - half) < 1e-9 && abs(f.h - none.h) < 1e-9 && abs(f.headY - none.headY) < 1e-9)
                }
            }
            let four = T.kittenSlots(kittens(4), side: 1), f4 = L.frame(d: d, slots: four)
            CT.checkTrue("\(size.rawValue): the +N label is inside the window too", f4.w - f4.headX >= four.moreAt!.x * d + L.labelWidth("+1", four.moreAt!.size * d) / 2 - 1e-9)
            CT.checkTrue("\(size.rawValue): three kittens and a +N fit in under three heads' width beyond the canvas", L.frame(d: d, slots: T.kittenSlots(kittens(8), side: 1)).w < d / 0.6 + 2.2 * d)
        }

        CT.section("the window on the screen: its head is exactly on the spot")
        let f = L.frame(d: 64, slots: T.kittenSlots(kittens(2), side: 1))
        let o = L.origin(spot: spot(900, 300), frame: f, primaryHeight: 982)
        CT.checkNear("left of the window plus the head's offset is the spot's x", o.x + f.headX, 900)
        CT.checkNear("top of the window (AppKit's y up) minus the head's offset is the spot's AppKit y", o.y + f.h - f.headY, 982 - 300)

        CT.section("which side the kittens go on: left in the right half of the screen, so they stay on it")
        CT.check("the left half keeps them on the right", L.side(of: spot(300, 400), screens: c), 1)
        CT.check("the right half sends them to the left", L.side(of: spot(1300, 400), screens: c), -1)
        CT.check("the exact middle of the visible frame is still the left half", L.side(of: spot(756, 400), screens: c), 1)
        CT.check("on the monitor, its own halves count", [L.side(of: spot(1600, 400), screens: c), L.side(of: spot(3900, 400), screens: c)], [1, -1])
        CT.check("a spot on no screen has the default", L.side(of: spot(9000, 9000), screens: c), 1)
        CT.check("no screens, the default", L.side(of: spot(1, 1), screens: []), 1)

        CT.section("the body takes the mouse; everything else passes through")
        let d = 64.0, two = T.kittenSlots(kittens(2), side: 1), many = T.kittenSlots(kittens(8), side: 1), noKit = T.kittenSlots([], side: 1)
        CT.checkTrue("the middle of the head", L.hits(spot(0, 0), d: d, slots: noKit, badge: false))
        CT.checkTrue("just inside the head circle, and just outside", L.hits(spot(0.55 * d - 0.5, 0), d: d, slots: noKit, badge: false) && !L.hits(spot(0.55 * d + 0.5, 0), d: d, slots: noKit, badge: false))
        CT.checkTrue("the corners of the canvas pass through (the window is a square, the cat a circle)", !L.hits(spot(d / 0.6 / 2 - 1, d / 0.6 / 2 - 1), d: d, slots: noKit, badge: true) && !L.hits(spot(-d / 0.6 / 2 + 1, -d / 0.6 / 2 + 1), d: d, slots: noKit, badge: true))
        CT.checkTrue("the hearts' room above the cat passes through", !L.hits(spot(0, -d * 1.2), d: d, slots: noKit, badge: true))
        CT.checkTrue("the badge takes the mouse when there is one, and not when there is none", L.hits(spot(0.7 * d, -0.46 * d), d: d, slots: noKit, badge: true) && !L.hits(spot(0.7 * d, -0.46 * d), d: d, slots: noKit, badge: false))
        CT.checkTrue("a kitten takes it, the gap between two does not", L.hits(spot(0.82 * d, 0.22 * d), d: d, slots: two, badge: false) && L.hits(spot(1.15 * d, 0.22 * d), d: d, slots: two, badge: false) && !L.hits(spot(1.4 * d, 0.22 * d), d: d, slots: two, badge: false))
        CT.checkTrue("the third kitten's place is empty with two", !L.hits(spot(1.48 * d, 0.22 * d), d: d, slots: two, badge: false))
        CT.checkTrue("the +N label takes it", L.hits(spot(1.81 * d, 0.22 * d), d: d, slots: many, badge: false))
        CT.checkTrue("on the left the kittens are on the left", L.hits(spot(-0.82 * d, 0.22 * d), d: d, slots: T.kittenSlots(kittens(2), side: -1), badge: false) && !L.hits(spot(0.82 * d, 0.22 * d), d: d, slots: T.kittenSlots(kittens(2), side: -1), badge: false))
        CT.checkTrue("a point that is NaN is nowhere", !L.hits(spot(.nan, 0), d: d, slots: noKit, badge: true) && !L.hits(spot(0, .infinity), d: d, slots: noKit, badge: true))
        var inside = 0, total = 0
        let fr = L.frame(d: d, slots: many)
        for ix in stride(from: -fr.headX, through: fr.w - fr.headX, by: 2) { for iy in stride(from: -fr.headY, through: fr.h - fr.headY, by: 2) { total += 1; if L.hits(spot(ix, iy), d: d, slots: many, badge: true) { inside += 1 } } }
        CT.checkTrue("only a small part of the window is body (\(inside) of \(total) sample points): the rest is click-through", Double(inside) / Double(total) < 0.35 && inside > 0)
        CT.finish()
    }
}
```

**Create `scripts/test-cat-desktop-layout.sh`**:

```bash
#!/usr/bin/env bash
# Desktop cat layout (sub-project H): AppKit's screens as the contract's, the window around the cat for each size and side, which side the kittens go on and the shape of the body that takes the mouse.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-desktop-layout.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatKittens.swift \
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/DesktopCatLayout.swift $APP/DesktopCatDrop.swift $APP/DesktopCatPacer.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/DesktopCatLayoutTests.swift \
    -o "$TEST_DIR/desktop-layout-tests"
"$TEST_DIR/desktop-layout-tests"
```

```bash
chmod +x scripts/test-cat-desktop-layout.sh
```

**Create `tests/DesktopCatInputTests.swift`**:

```swift
import Foundation

@main
enum DesktopCatInputTests {
    typealias C = DesktopCatClicks
    static func spot(_ x: Double, _ y: Double) -> DesktopSpot { DesktopSpot(x: x, y: y) }

    @MainActor static func main() {
        CT.section("a lone click acts only after the double-click interval")
        var c = C(interval: 0.5)
        CT.check("a press does nothing yet", c.down(at: 10, spot(5, 5)), [])
        CT.check("nor does the release: the click is waiting", c.up(at: 10.05, spot(5, 5)), [])
        CT.check("it waits until the interval after the release", c.waitUntil, 10.55)
        CT.check("the timer too early does nothing", c.timer(at: 10.3), [])
        CT.check("and on time it is a click", c.timer(at: 10.55), [.click])
        CT.check("only once", c.timer(at: 11), [])
        CT.check("nothing waits any more", c.waitUntil, nil)

        CT.section("a double-click sends it home and never also clicks")
        c = C(interval: 0.5)
        _ = c.down(at: 20, spot(5, 5)); _ = c.up(at: 20.05, spot(5, 5))
        CT.check("the second press inside the interval", c.down(at: 20.3, spot(5, 5)), [])
        CT.check("its release is the double-click", c.up(at: 20.35, spot(5, 5)), [.doubleClick])
        CT.check("the pending click is gone: the timer does nothing", c.timer(at: 21), [])
        _ = c.down(at: 30, spot(5, 5)); _ = c.up(at: 30.05, spot(5, 5))
        CT.check("a second press after the interval is a new click and the first one is delivered first", c.down(at: 31, spot(5, 5)), [.click])
        CT.check("and that one is waiting in its turn", c.up(at: 31.05, spot(5, 5)), [])
        CT.check("a double-click interval that is not a number is half a second", C(interval: .nan).interval, 0.5)

        CT.section("a drag moves it and never clicks")
        c = C(interval: 0.5)
        _ = c.down(at: 40, spot(100, 100))
        CT.check("4 points or less is still a press", c.dragged(spot(102, 103)), [])
        CT.check("past 4 points the drag begins, with the first move", c.dragged(spot(110, 100)), [.dragBegan, .dragMoved(spot(110, 100))])
        CT.check("it follows", c.dragged(spot(120, 130)), [.dragMoved(spot(120, 130))])
        CT.check("the release ends it where the mouse is", c.up(at: 41, spot(125, 135)), [.dragEnded(spot(125, 135))])
        CT.check("no click comes later", c.timer(at: 42), [])
        CT.check("a release or a drag with no press does nothing", [c.up(at: 43, spot(1, 1)), c.dragged(spot(1, 1))], [[], []])
        c = C(interval: 0.5)
        _ = c.down(at: 50, spot(0, 0)); _ = c.up(at: 50.1, spot(0, 0)); _ = c.down(at: 50.2, spot(0, 0))
        CT.check("the second press of a double-click can still turn into a drag", c.dragged(spot(30, 0)), [.dragBegan, .dragMoved(spot(30, 0))])
        CT.check("and then it is only a drag", c.up(at: 50.5, spot(30, 0)), [.dragEnded(spot(30, 0))])

        CT.section("the right-click menu")
        let m = DesktopCatMenu.entries(size: .medium, shortcut: "⌃⌥D")
        CT.check("Open the notch, Send home, Size and the shortcut's line", m.count, 6)
        CT.check("the first two", [m[0], m[1]], [.action(title: "Open the notch", .openNotch, checked: false), .action(title: "Send home", .sendHome, checked: false)])
        if case .submenu(let title, let sizes) = m[3] {
            CT.check("the Size menu", title, "Size")
            CT.check("with the current size ticked", sizes, [.action(title: "Small", .size(.small), checked: false), .action(title: "Medium", .size(.medium), checked: true), .action(title: "Large", .size(.large), checked: false)])
        } else { CT.checkTrue("the fourth entry is the Size menu", false) }
        CT.check("the last line shows the shortcut", m[5], .note("Out or home: ⌃⌥D"))
        CT.check("with no shortcut (off, or the platform has none) there is no line", DesktopCatMenu.entries(size: .large, shortcut: nil).count, 4)
        CT.check("and an empty shortcut is none", DesktopCatMenu.entries(size: .small, shortcut: "").count, 4)

        CT.section("kittens in motion for 600 ms after any change to the list, and the notch spot")
        func k(_ id: String, _ state: CatKittens.State = .working) -> CatKittens.Kitten { CatKittens.Kitten(id: id, state: state, born: 0, last: 0) }
        var w = DesktopKittenWatch()
        CT.check("no kittens, nothing changed", w.observe([], now: 1000), false)
        CT.check("a kitten arrives: motion", w.observe([k("a")], now: 2000), true)
        CT.check("still, 599 ms later", w.observe([k("a")], now: 2599), true)
        CT.check("at 600 ms it is over", w.observe([k("a")], now: 2600), false)
        CT.check("a kitten state change that is not a leave is not a change of the list", w.observe([k("a", .searching)], now: 5000), false)
        CT.check("a second one arrives: motion again", w.observe([k("a"), k("b")], now: 6000), true)
        CT.check("one starts to leave: the list changed", w.observe([k("a"), k("b", .leaving)], now: 7000), true)
        CT.check("and goes: it changed once more", w.observe([k("a")], now: 7400), true)
        CT.check("quiet again 600 ms later", w.observe([k("a")], now: 8000), false)
        CT.check("the last one goes: motion, then none", [w.observe([], now: 9000), w.observe([], now: 9700)], [true, false])
        CT.check("a clock that is not a number is not motion, and changes nothing", [w.observe([k("z")], now: .nan), w.observe([k("z")], now: 20000)], [false, true])
        CT.check("a clock that goes backwards is not motion", w.observe([k("z")], now: 19000), false)
        let screen = DesktopRect(x: 0, y: 0, w: 1512, h: 982)
        CT.check("the notch spot is the island's left edge plus the cat's x, on the screen's top", DesktopCatLayout.notchSpot(screenFrame: screen, islandW: 200, cx: 50, cy: 15), spot(756 - 100 + 50, 15))
        CT.check("on a second screen it follows that screen", DesktopCatLayout.notchSpot(screenFrame: DesktopRect(x: 1512, y: -358, w: 2560, h: 1440), islandW: 200, cx: 50, cy: 15), spot(1512 + 1280 - 100 + 50, -343))
        CT.finish()
    }
}
```

**Create `scripts/test-cat-desktop-input.sh`**:

```bash
#!/usr/bin/env bash
# Desktop cat input (sub-project H): a click that waits one double-click interval, the double-click, the drag, the right-click menu, kittens arriving or leaving and the notch spot.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-desktop-input.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatKittens.swift \
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/DesktopCatLayout.swift $APP/DesktopCatInput.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/DesktopCatInputTests.swift \
    -o "$TEST_DIR/desktop-input-tests"
"$TEST_DIR/desktop-input-tests"
```

```bash
chmod +x scripts/test-cat-desktop-input.sh
```

**Create `tests/DesktopCatDropTests.swift`**:

```swift
import Foundation

@main
enum DesktopCatDropTests {
    typealias D = DesktopCatDrop
    static func spot(_ x: Double, _ y: Double) -> DesktopSpot { DesktopSpot(x: x, y: y) }

    @MainActor static func main() {
        let screens = DesktopCatSpots.screens([["frame": ["x": 0, "y": 0, "w": 1512, "h": 982], "visible": ["x": 0, "y": 37, "w": 1512, "h": 875], "main": true]])
        func decide(_ p: DesktopSpot, island: Bool = false, window: Bool = false, captured: Bool = false, store: Bool = false, size: DesktopSize = .medium) -> DesktopDrop {
            D.decide(point: p, screens: screens, size: size, onIsland: island, windowUnder: window, contextCaptured: captured, appStore: store)
        }

        CT.section("a drop on another app's window attaches it, exactly as today (the GitHub build)")
        CT.check("a window whose context was captured: attach", decide(spot(600, 400), window: true, captured: true), .attach)
        CT.check("a window whose context could not be captured: nothing happens and the cat stays home", decide(spot(600, 400), window: true, captured: false), .stayHome)
        CT.check("the same window on the island itself: still nothing", decide(spot(600, 20), island: true, window: true, captured: true), .stayHome)

        CT.section("a drop on empty desktop places the cat")
        CT.check("where it was dropped", decide(spot(600, 400)), .place(spot(600, 400)))
        CT.check("held where the cat may sit: not under the menu bar", decide(spot(600, 5)), .place(spot(600, 37 + 56)))
        CT.check("and not past the edge", decide(spot(1510, 980), size: .large), .place(spot(1512 - 72, 912 - 72)))
        CT.check("a drop on the island does nothing", decide(spot(756, 20), island: true), .stayHome)
        CT.check("a drop beside the screens goes to the default spot", decide(spot(9000, 9000)), .place(DesktopCatSpots.defaultSpot(screens, size: .medium)!))
        CT.check("a point that is NaN does nothing", decide(spot(.nan, 5)), .stayHome)
        CT.check("with no screen there is nowhere to sit", D.decide(point: spot(5, 5), screens: [], size: .medium, onIsland: false, windowUnder: false, contextCaptured: false, appStore: false), .stayHome)

        CT.section("the App Store build has no attach: any drop that is not on the island places the cat")
        CT.check("over a window", decide(spot(600, 400), window: true, captured: false, store: true), .place(spot(600, 400)))
        CT.check("even if a capture were claimed", decide(spot(600, 400), window: true, captured: true, store: true), .place(spot(600, 400)))
        CT.check("on empty desktop", decide(spot(600, 400), store: true), .place(spot(600, 400)))
        CT.check("on the island: nothing", decide(spot(756, 20), island: true, store: true), .stayHome)
        CT.finish()
    }
}
```

**Create `scripts/test-cat-desktop-drop.sh`**:

```bash
#!/usr/bin/env bash
# Desktop cat drop (sub-project H): what happens when the big cat is let go after a drag from the notch: attach as today, place on empty desktop, or nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-desktop-drop.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatKittens.swift \
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/DesktopCatLayout.swift $APP/DesktopCatDrop.swift $APP/DesktopCatPacer.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/DesktopCatDropTests.swift \
    -o "$TEST_DIR/desktop-drop-tests"
"$TEST_DIR/desktop-drop-tests"
```

```bash
chmod +x scripts/test-cat-desktop-drop.sh
```

**Create `tests/DesktopCatPacerTests.swift`**:

```swift
import Foundation

@main
enum DesktopCatPacerTests {
    typealias P = DesktopCatPacer

    /// What a timer is told, as numbers: `arm` compares exactly, and a tenth of 0.05 is not exactly 0.005.
    static func armed(_ a: P.Action) -> [Double]? { if case .arm(let i, let l) = a { return [i, l] }; return nil }
    static func same(_ a: [Double]?, _ b: [Double]) -> Bool { a.map { zip($0, b).allSatisfy { abs($0 - $1) < 1e-12 } && $0.count == b.count } ?? false }

    @MainActor static func main() {
        CT.section("the intervals: one timer at the target's rate, none for a target of nothing")
        CT.check("60, 20, 5 and 0.5 frames a second", [60, 20, 5, 0.5].map { P.interval($0)! }, [1.0 / 60, 0.05, 0.2, 2])
        CT.check("0, a negative rate, NaN and infinity mean no timer", [P.interval(0) == nil, P.interval(-5) == nil, P.interval(.nan) == nil, P.interval(.infinity) == nil], [true, true, true, true])
        CT.checkNear("the slack is a tenth of the interval", P.leeway(0.2), 0.02)
        CT.checkNear("and at most 0.2 s", P.leeway(2), 0.2)

        CT.section("the pacer re-arms the timer only when the target changes")
        var p = P()
        CT.check("a new pacer has no timer", p.fps, 0)
        CT.check("a target of 0 on a pacer with no timer does nothing", p.target(0), .none)
        CT.checkTrue("20 fps arms a 50 ms timer", same(armed(p.target(20)), [0.05, 0.005]))
        CT.check("20 again does nothing", p.target(20), .none)
        CT.checkTrue("5 fps arms 200 ms", same(armed(p.target(5)), [0.2, 0.02]))
        CT.checkTrue("60 fps while it flies", same(armed(p.target(60)), [1.0 / 60, 1.0 / 600]))
        CT.checkTrue("asleep: one frame every two seconds", same(armed(p.target(0.5)), [2, 0.2]))
        CT.check("hidden: the timer is cancelled", p.target(0), .stop)
        CT.check("and stays cancelled", p.target(0), .none)
        CT.check("a target that is NaN is nothing", { var q = P(); _ = q.target(5); return q.target(.nan) }(), .stop)
        CT.checkTrue("it is back at 5 when the cat can be seen again", same(armed(p.target(5)), [0.2, 0.02]))

        CT.section("what a rate costs: milliseconds a frame times frames a second")
        CT.checkNear("0.4 ms at 5 fps is 0.2 % of a core", P.coreShare(msPerFrame: 0.4, fps: 5), 0.002)
        CT.checkNear("2 ms at 60 fps is 12 %", P.coreShare(msPerFrame: 2, fps: 60), 0.12)

        CT.section("hidden: any one reason hides the cat")
        var v = DesktopCatVisibility()
        CT.check("visible to begin with", v.hidden, false)
        v.screensAsleep = true; CT.check("the displays are asleep", v.hidden, true)
        v = DesktopCatVisibility(); v.locked = true; CT.check("the session is locked", v.hidden, true)
        v = DesktopCatVisibility(); v.covered = true; CT.check("a fullscreen app covers it", v.hidden, true)
        CT.check("and the rule feeds the frame rate: hidden beats a flight", DesktopCatTrip.fps(.init(phase: .flyingOut, hidden: DesktopCatVisibility(covered: true).hidden)), 0)
        CT.finish()
    }
}
```

**Create `scripts/test-cat-desktop-pacer.sh`**:

```bash
#!/usr/bin/env bash
# Desktop cat pacer (sub-project H): the frame-rate target as one timer that is re-armed only when it changes, and what hides the cat.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-desktop-pacer.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatKittens.swift \
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/DesktopCatLayout.swift $APP/DesktopCatDrop.swift $APP/DesktopCatPacer.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/DesktopCatPacerTests.swift \
    -o "$TEST_DIR/desktop-pacer-tests"
"$TEST_DIR/desktop-pacer-tests"
```

```bash
chmod +x scripts/test-cat-desktop-pacer.sh
```

- [ ] **Step 2: Run them to see them fail**

Run: `for n in layout input drop pacer; do bash scripts/test-cat-desktop-$n.sh 2>&1 | grep -o "error opening input file" | sort -u; done`
Expected: four lines, each `error opening input file`.

- [ ] **Step 3: Write the code**

**Create `NotchBuddy/Sources/App/DesktopCatLayout.swift`**:

```swift
import Foundation

// The desktop cat's geometry (sub-project H): AppKit's screens turned into the contract's, the window around the cat, which side its kittens go on, and the shape of its body.
// Everything is in points. A "spot" is the head centre in the contract's coordinates (y down, the origin at the top left of the main screen); a point "relative to the head"
// has x right and y down from that centre. The window is sized for the cat, its badge and its kittens, and no larger: the clicks outside `hits` pass through it
// (`DesktopCatPanel`). Foundation only; `tests/DesktopCatLayoutTests.swift` pins every number.

enum DesktopCatScreens {
    /// A screen as AppKit reports it: `NSScreen.frame` and `visibleFrame`, bottom-left origin. `NSScreen.screens[0]` is the one with the menu bar.
    struct AppKitScreen: Equatable, Sendable {
        var frame: DesktopRect
        var visible: DesktopRect
    }

    /// The height of the main screen: AppKit's y of its top edge. Every conversion flips around it.
    static func primaryHeight(_ screens: [AppKitScreen]) -> Double { screens.first.map { $0.frame.y + $0.frame.h } ?? 0 }

    /// AppKit's screens as the contract's: `yTop = primaryHeight - frame.maxY`, the first one marked main. The result is not tidied here: `DesktopCatSpots` tidies it.
    static func contract(_ screens: [AppKitScreen]) -> [DesktopScreen] {
        let top = primaryHeight(screens)
        func flip(_ r: DesktopRect) -> DesktopRect { DesktopRect(x: r.x, y: top - (r.y + r.h), w: r.w, h: r.h) }
        return screens.enumerated().map { DesktopScreen(frame: flip($1.frame), visible: flip($1.visible), main: $0 == 0) }
    }

    /// An AppKit point (`NSEvent.mouseLocation`) as a spot, and back.
    static func spot(fromAppKit x: Double, _ y: Double, primaryHeight: Double) -> DesktopSpot { DesktopSpot(x: x, y: primaryHeight - y) }
    static func appKit(_ s: DesktopSpot, primaryHeight: Double) -> (x: Double, y: Double) { (s.x, primaryHeight - s.y) }
}

/// The window around the cat, in points: its size, and where the head centre is inside it (y down from the window's top).
struct DesktopCatFrame: Equatable, Sendable {
    var w: Double, h: Double
    var headX: Double, headY: Double
}

enum DesktopCatLayout {
    /// The cat is drawn in a square of D / 0.6 (the head, the ears, the whiskers and the badge are inside it), as everywhere in the app.
    static let canvasK = 1 / 0.6
    /// Room above the canvas for the hearts of a happy cat: 40 pt at the island's Ø58 head, in proportion at the other sizes.
    static let heartsK = 40.0 / 58.0
    /// The body takes the mouse inside the head circle (a little larger than the head, for the ears), the badge's circle and the kittens' circles.
    static let headK = 0.55, badgeX = 0.7, badgeY = -0.46, badgeK = 0.2

    /// The width of a "+N" or "×N" label of size `size` (`CatKittenDraw.labelWidth`).
    static func labelWidth(_ text: String, _ size: Double) -> Double { let sz = max(8, size); return Double(text.count) * sz * 0.62 + sz * 0.9 }

    /// Where a kitten's circle or the "+N" sits, in points relative to the head: the slots are in units of D.
    private static func shapes(_ slots: CatKittens.Slots, d: Double) -> (circles: [(x: Double, y: Double, r: Double)], label: (x: Double, y: Double, halfW: Double, halfH: Double)?) {
        let circles = slots.shown.map { (x: $0.x * d, y: $0.y * d, r: $0.d * d / 2 * 1.1) }
        guard let m = slots.moreAt else { return (circles, nil) }
        let size = m.size * d, text = "+\(slots.more)", sz = max(8, size)
        return (circles, (m.x * d, m.y * d, labelWidth(text, size) / 2, sz * 1.3 / 2))
    }

    /// The window for a cat of head width `d` with these kittens (`DesktopCatTrip.kittenSlots`, already mirrored for the side): the canvas, the hearts above and, on the
    /// kittens' side, as far as the last kitten or "+N" reaches.
    static func frame(d: Double, slots: CatKittens.Slots) -> DesktopCatFrame {
        let half = d * canvasK / 2, top = half + d * heartsK
        var left = -half, right = half
        let s = shapes(slots, d: d)
        for c in s.circles { left = min(left, c.x - c.r); right = max(right, c.x + c.r) }
        if let l = s.label { left = min(left, l.x - l.halfW); right = max(right, l.x + l.halfW) }
        return DesktopCatFrame(w: right - left, h: top + half, headX: -left, headY: top)
    }

    /// The side the kittens go on: the left (-1) when the cat is in the right half of its screen's visible frame, so they stay on the screen; else the right (1).
    static func side(of spot: DesktopSpot, screens: [DesktopScreen]) -> Int {
        let list = DesktopCatSpots.tidy(screens)
        guard let s = list.first(where: { DesktopCatSpots.contains($0.frame, spot) }) else { return 1 }
        return spot.x > s.visible.x + s.visible.w / 2 ? -1 : 1
    }

    /// Whether the mouse is on the cat's body: `p` is relative to the head (x right, y down). `badge` says the cat shows one.
    static func hits(_ p: DesktopSpot, d: Double, slots: CatKittens.Slots, badge: Bool) -> Bool {
        guard p.x.isFinite, p.y.isFinite else { return false }
        if hypot(p.x, p.y) <= d * headK { return true }
        if badge && hypot(p.x - d * badgeX, p.y - d * badgeY) <= d * badgeK { return true }
        let s = shapes(slots, d: d)
        if s.circles.contains(where: { hypot(p.x - $0.x, p.y - $0.y) <= $0.r }) { return true }
        if let l = s.label, abs(p.x - l.x) <= l.halfW, abs(p.y - l.y) <= l.halfH { return true }
        return false
    }

    /// The window's bottom-left corner in AppKit's coordinates, for a cat whose head centre is at `spot`.
    static func origin(spot: DesktopSpot, frame: DesktopCatFrame, primaryHeight: Double) -> (x: Double, y: Double) {
        let c = DesktopCatScreens.appKit(spot, primaryHeight: primaryHeight)
        return (c.x - frame.headX, c.y - (frame.h - frame.headY))
    }
}
```

**Create `NotchBuddy/Sources/App/DesktopCatInput.swift`**:

```swift
import Foundation

// What the mouse does to the desktop cat (sub-project H), as pure rules: a click waits one double-click interval before it acts (so a double-click never also opens the island),
// a drag begins after 3 points, and the right-click menu is a list the view turns into an NSMenu. Also the little pure rules the controller needs: where the notch spot is, and
// whether a kitten is arriving or leaving. Foundation only; `tests/DesktopCatInputTests.swift` pins them.

/// Press, drag, release and the one-shot timer, as events in; what the cat should do, as events out. The view feeds it the mouse and schedules one timer for `waitUntil`: nothing polls.
struct DesktopCatClicks: Equatable, Sendable {
    /// A press that moves further than this (points) is a drag, not a click (the same on Windows and Linux).
    static let dragThreshold = 4.0

    enum Out: Equatable, Sendable {
        case dragBegan
        case dragMoved(DesktopSpot)
        case dragEnded(DesktopSpot)
        /// A single click, a double-click interval after the release: open the island at the notch with a happy reaction.
        case click
        /// Two clicks inside the interval: send the cat home.
        case doubleClick
    }

    private enum Phase: Equatable, Sendable {
        case idle
        case pressed(second: Bool, from: DesktopSpot)
        case dragging
        case waiting(until: Double)
    }
    private var phase = Phase.idle
    /// `NSEvent.doubleClickInterval`, in seconds.
    var interval: Double

    init(interval: Double) { self.interval = interval.isFinite && interval > 0 ? interval : 0.5 }

    /// The time the one-shot timer must fire at to turn a lone click into a `click`; nil when no click is waiting.
    var waitUntil: Double? { if case .waiting(let t) = phase { return t } else { return nil } }

    /// Times are seconds on one clock (the event's timestamp); a time that is not a number counts as the end of the wait.
    mutating func down(at t: Double, _ p: DesktopSpot) -> [Out] {
        if case .waiting(let until) = phase, t.isFinite, t <= until { phase = .pressed(second: true, from: p); return [] }
        var out: [Out] = []
        if case .waiting = phase { out.append(.click) }   // the wait is over and the timer has not run yet
        phase = .pressed(second: false, from: p)
        return out
    }

    mutating func dragged(_ p: DesktopSpot) -> [Out] {
        switch phase {
        case .pressed(_, let from) where hypot(p.x - from.x, p.y - from.y) > Self.dragThreshold:
            phase = .dragging
            return [.dragBegan, .dragMoved(p)]
        case .dragging: return [.dragMoved(p)]
        default: return []
        }
    }

    mutating func up(at t: Double, _ p: DesktopSpot) -> [Out] {
        switch phase {
        case .pressed(let second, _):
            if second { phase = .idle; return [.doubleClick] }
            phase = .waiting(until: (t.isFinite ? t : 0) + interval)
            return []
        case .dragging: phase = .idle; return [.dragEnded(p)]
        default: return []
        }
    }

    /// The one-shot timer ran.
    mutating func timer(at t: Double) -> [Out] {
        guard case .waiting(let until) = phase, !t.isFinite || t >= until else { return [] }
        phase = .idle
        return [.click]
    }
}

/// The right-click menu: Open the notch, Send home, Size ▸ Small, Medium, Large (the current one ticked) and, on the Mac, a line showing the shortcut.
enum DesktopCatMenu {
    enum Action: Equatable, Sendable { case openNotch, sendHome, size(DesktopSize) }
    enum Entry: Equatable, Sendable {
        case action(title: String, Action, checked: Bool)
        case submenu(title: String, [Entry])
        case separator
        /// A line that does nothing, shown greyed.
        case note(String)
    }

    /// `shortcut` is the display string of the `desktop` shortcut ("⌃⌥D") when it is on, nil when it is off or the platform has none.
    static func entries(size: DesktopSize, shortcut: String?) -> [Entry] {
        var list: [Entry] = [
            .action(title: "Open the notch", .openNotch, checked: false),
            .action(title: "Send home", .sendHome, checked: false),
            .separator,
            .submenu(title: "Size", [
                .action(title: "Small", .size(.small), checked: size == .small),
                .action(title: "Medium", .size(.medium), checked: size == .medium),
                .action(title: "Large", .size(.large), checked: size == .large),
            ]),
        ]
        if let shortcut, !shortcut.isEmpty { list += [.separator, .note("Out or home: \(shortcut)")] }
        return list
    }
}

extension DesktopCatTrip {
}

/// Whether the kittens are in motion (`kittenMotion` of `FpsInput`): for 600 ms (`KITTEN_LEAVE_MS`, a kitten's farewell) after **any change to the kitten list**, an arrival or a leave (a kitten
/// that starts to leave changes the list: it is marked `leaving`; one that is gone changes it too). A watch is kept by the controller and asked once per frame; `now` is on the kittens' clock (ms).
struct DesktopKittenWatch: Equatable, Sendable {
    static let motionMs = 600.0
    private var signature: [String] = []
    private var changedAt: Double?

    mutating func observe(_ kittens: [CatKittens.Kitten], now: Double) -> Bool {
        guard now.isFinite else { return false }
        let sig = kittens.map { "\($0.id)|\($0.state == .leaving)" }
        if sig != signature { signature = sig; changedAt = now }
        return changedAt.map { now >= $0 && now - $0 < Self.motionMs } ?? false
    }
}

extension DesktopCatLayout {
    /// The big cat's spot in the notch, in the contract's coordinates: `screenFrame` is the island's screen (contract coordinates), `islandW` the island's width and (`cx`, `cy`)
    /// where `botPosition` puts the cat inside it (from the island's top left). The island is centred on its screen and glued to its top.
    static func notchSpot(screenFrame: DesktopRect, islandW: Double, cx: Double, cy: Double) -> DesktopSpot {
        DesktopSpot(x: screenFrame.x + screenFrame.w / 2 - islandW / 2 + cx, y: screenFrame.y + cy)
    }
}
```

**Create `NotchBuddy/Sources/App/DesktopCatDrop.swift`**:

```swift
import Foundation

// What happens when the big cat is let go after a drag from the notch (sub-project H). Today a drop on another app's window attaches that window to a chat; H adds one more
// outcome, a drop on empty desktop places the cat there. The rule is pure so it can be tested: attaching must keep working exactly as it does today. Foundation only.

enum DesktopDrop: Equatable, Sendable {
    /// Another app's window is under the cat and its context was captured: attach it to the chat, as before.
    case attach
    /// Empty desktop: the cat lives here, at the clamped spot.
    case place(DesktopSpot)
    /// Nothing happens and the cat stays in the notch: the drop was on the island, on a window that could not be attached, or there is no screen to sit on.
    case stayHome
}

enum DesktopCatDrop {
    /// `point` is the cat's head in the contract's coordinates, `windowUnder` that another app's window is there (`windowBoundsAtScreenPoint`), `contextCaptured` that attaching
    /// it worked (`windowContextAtPoint`, only asked when `windowUnder`), and `onIsland` that the point is on the island itself. The App Store build has no attach, and so any
    /// drop that is not on the island places the cat there.
    static func decide(point: DesktopSpot, screens: [DesktopScreen], size: DesktopSize, onIsland: Bool, windowUnder: Bool, contextCaptured: Bool, appStore: Bool) -> DesktopDrop {
        if onIsland { return .stayHome }
        if !appStore && windowUnder { return contextCaptured ? .attach : .stayHome }
        guard let spot = DesktopCatSpots.clampSpot(point, screens, size: size), DesktopCatSpots.isValid(point) else { return .stayHome }
        return .place(spot)
    }
}
```

**Create `NotchBuddy/Sources/App/DesktopCatPacer.swift`**:

```swift
import Foundation

// The desktop cat's frame-rate governor (sub-project H): the target `DesktopCatTrip.fps` gives becomes one repeating timer at that rate, re-armed only when the target changes,
// and no timer at all when the cat cannot be seen. Nothing polls: what raises the rate (the cursor coming near, a click, an agent event, a kitten) calls the controller, which
// asks again. Also `DesktopCatVisibility`, what "cannot be seen" means. Foundation only.

struct DesktopCatPacer: Equatable, Sendable {
    /// The target now; 0 means no timer.
    private(set) var fps = 0.0

    enum Action: Equatable, Sendable {
        case none
        /// Cancel the timer: the cat is not drawn or cannot be seen.
        case stop
        /// Replace the timer with one that fires every `interval` seconds, with `leeway` seconds of slack so the system can coalesce wake-ups.
        case arm(interval: Double, leeway: Double)
    }

    /// The time between frames for a target, nil for a target that means no frames (0, negative, NaN, infinity).
    static func interval(_ fps: Double) -> Double? { fps.isFinite && fps > 0 ? 1 / fps : nil }

    
    static func leeway(_ interval: Double) -> Double { min(interval * 0.1, 0.2) }

    /// The new target. Nothing is asked of the timer when it did not change.
    mutating func target(_ new: Double) -> Action {
        let clean = Self.interval(new) == nil ? 0 : new
        guard clean != fps else { return .none }
        fps = clean
        guard let i = Self.interval(clean) else { return .stop }
        return .arm(interval: i, leeway: Self.leeway(i))
    }

    /// The share of one core a rate costs when a frame takes `msPerFrame` milliseconds of CPU: the bench's number.
    static func coreShare(msPerFrame: Double, fps: Double) -> Double { msPerFrame * fps / 1000 }
}

/// Why the cat cannot be seen. Any one of them hides it (frame rate 0 and no timer).
struct DesktopCatVisibility: Equatable, Sendable {
    /// The displays are asleep (`NSWorkspace.screensDidSleepNotification`) or the screen saver runs.
    var screensAsleep = false
    /// The session is locked or switched away (`com.apple.screenIsLocked`, `NSWorkspace.sessionDidResignActiveNotification`).
    var locked = false
    /// The window is not on screen: a fullscreen app's Space is active, or something covers it (`NSWindow.occlusionState` has no `.visible`).
    var covered = false

    var hidden: Bool { screensAsleep || locked || covered }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `for n in layout input drop pacer; do printf '%-8s' $n; bash scripts/test-cat-desktop-$n.sh 2>&1 | tail -1; done`
Expected: four lines, each ending `All tests passed.`

- [ ] **Step 5: Prove the tests bite**

A click that fires without waiting for a possible second click, and a drop that attaches in the App Store build.

```bash
F=NotchBuddy/Sources/App/DesktopCatInput.swift
cp "$F" "${TMPDIR:-/tmp}/h-mac-input.keep"
sed -i '' 's/phase = .waiting(until: (t.isFinite ? t : 0) + interval)/phase = .idle; return [.click]/' "$F"
bash scripts/test-cat-desktop-input.sh 2>&1 | grep -E "failed"
cp "${TMPDIR:-/tmp}/h-mac-input.keep" "$F"
G=NotchBuddy/Sources/App/DesktopCatDrop.swift
cp "$G" "${TMPDIR:-/tmp}/h-mac-drop.keep"
sed -i '' 's/if !appStore \&\& windowUnder/if windowUnder/' "$G"
bash scripts/test-cat-desktop-drop.sh 2>&1 | grep -E "failed"
cp "${TMPDIR:-/tmp}/h-mac-drop.keep" "$G"
bash scripts/test-cat-desktop-input.sh 2>&1 | tail -1; bash scripts/test-cat-desktop-drop.sh 2>&1 | tail -1
```

Expected: FAIL with each mistake (`N test(s) failed.`), and two lines of `All tests passed.` once the files are back.

- [ ] **Step 6: Commit**

```bash
cd NotchBuddy && xcodegen > /dev/null && cd ..
```

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and h-mac/desktop-cat: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/h-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(cat): the desktop cat's window geometry, click rules, drop rule and pacer

DesktopCatLayout (the window around the cat, its side and its body shape), DesktopCatInput (click, double-click, drag and the right-click menu), DesktopCatDrop (a window attaches, empty desktop places the cat) and DesktopCatPacer (one timer, re-armed only when the target changes), each with its test program.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/DesktopCatLayout.swift NotchBuddy/Sources/App/DesktopCatInput.swift NotchBuddy/Sources/App/DesktopCatDrop.swift NotchBuddy/Sources/App/DesktopCatPacer.swift tests/DesktopCatLayoutTests.swift tests/DesktopCatInputTests.swift tests/DesktopCatDropTests.swift tests/DesktopCatPacerTests.swift scripts/test-cat-desktop-layout.sh scripts/test-cat-desktop-input.sh scripts/test-cat-desktop-drop.sh scripts/test-cat-desktop-pacer.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F "$MSG"
git status --short   # nothing of this task is left over
```


---

### Task 5: The panel and its click-through, dragging out, the flight and sending home (steps 2 and 3)

**Agent:** `nm-implementer-deep` (**Sonnet 5.5, high; trigger 1**: an `NSPanel` that never takes focus, joins every Space and stays out of fullscreen, click-through that follows a shape, `NSEvent` monitors and Swift 6 main-actor isolation). The code is given in full, but the agent must understand it: this is the one class every later task builds on. Commit trailer `Claude Sonnet 5.5`.

**Files:**
- Create: `NotchBuddy/Sources/App/DesktopCatDraw.swift`, `DesktopCatPanel.swift`, `DesktopCatScreensApp.swift`, `DesktopCatController.swift`; `tests/DesktopCatWiringTests.swift`; `scripts/test-cat-desktop-wiring.sh`
- Modify: `NotchBuddy/Sources/App/AppState.swift`, `IslandRootView.swift`, `IslandWindowController.swift`, `AppDelegate.swift`; `scripts/check-app-binary.sh`; `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated)

**Interfaces:**
- Consumes: Tasks 1 to 4 (everything pure), Task 2's `CatSettingsStore.desktop`; the island's `botPosition`, `islandSize`, `IslandWindowController.notchScreen()`, `windowBoundsAtScreenPoint`, `windowContextAtPoint`, `expand(to:)`, `fsm.click()`, `defaultView()`; `AppState.cast`, `effectiveState`, `CatEngine.live`, `CatSleepClock.shared.wake`.
- Produces: `AppState.desktopPhase` (published; `DesktopPhase.notchEmpty` is true while the cat is out); `DesktopCatController` (`start()`, `toggle()`, `sendHome()`, `dragOut(to:)`, `isOut`, `send(_:)`, `draw(_:dpr:)`, the mouse and menu entry points); `DesktopCatPanel` (marker `NM_DESKTOP_CAT_PANEL`) and `DesktopCatView`; `DesktopCatDraw.draw`; `DesktopCatScreens.AppKitScreen.all`; `IslandWindowController.desktop`, `islandRectOnScreen()`, `openFromDesktop()`, `finishBotDrag(at:)`.

**What this task builds, and what it leaves to the later ones.** The controller carries the cat from the first drag to the last double-click: the window and its click-through, the drag out of the notch (`place`), the flight out and home, turning round mid-flight, the click, the double-click, the drag on the desktop, the right-click menu, the size, the screens changing, and the cat that flies out again after the greeting. It runs at a fixed 20 fps while it is drawn (Task 10 replaces that with the rule), draws no collar, kittens or dance (Task 7), does not react to an alert (Task 6: the machine and its acts are in, the Combine sink is not) or to the Settings switch (Task 8: the size is followed, the switch is not) and has no menu-bar item or hot key (Task 12). The regions that later tasks add are exactly the ones the Edit blocks of Tasks 6 to 12 touch.

**The design in six lines.**
- **One entry into the machine.** `send(_:)` asks `DesktopCatTrip.step`, sets the phase, carries out the act and stores `phase.on`, so quitting mid-flight home leaves the cat home. Every caller (a drag, a double-click, the menu, the later switch, the hot key, an alert) sends an event.
- **Click-through follows the body.** The panel starts with `ignoresMouseEvents = true`; a global and a local mouse-moved monitor (only while the cat is drawn) flip it from `DesktopCatLayout.hits` on every move, and it stays off while the cat is being dragged. A hover on the body wakes a sleeping cat.
- **The flight is `Flight` and the island.** Its notch end is recomputed from the island's own numbers every frame (`notchSpot()`), so the flight follows the island as it opens or folds; the cat flies at full size; a turn keeps the clock.
- **The window follows the head.** `layoutWindow()` sizes the panel for the cat and its kittens (`DesktopCatLayout.frame`) and puts the head on the spot; the view is flipped, so it draws with the contract's y.
- **Dragging out.** The island's existing drag of the big cat ends in `finishBotDrag(at:)`: a window attaches exactly as before, empty desktop places the cat, the island itself and a window that could not be attached do nothing. A drag of the cat on the desktop starts only while it is `onDesktop` (a cat in the air cannot be picked up) and ends in `move`, or in `sendHome` when it is let go on the island.
- **The notch is empty.** `AppState.desktopPhase` makes the big cat's place draw nothing and its hit test fail while `notchEmpty`; `isDraggingBot` hides the ghost as before.

- [ ] **Step 1: Write the failing wiring test**

These are source pins, because no test program can compile the controller, the panel or the island: a missed call site fails here and not on the owner's desktop. Stage 5 pins the window, the one timer, the one entry into the machine, the notch's empty spot, the drag and the app's wiring; later tasks add their own sections.

**Create `tests/DesktopCatWiringTests.swift`**:

```swift
import Foundation

// Source pins for the desktop cat's app files, which no test program can compile (the controller, the panel, the island and the delegate need the whole app). Each says where a
// call must be, so a missed call site fails here and not on the owner's desktop. Run from the repository root.

@main
enum DesktopCatWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }

    @MainActor static func main() {
        let ctl = source("DesktopCatController.swift"), panel = source("DesktopCatPanel.swift"), island = source("IslandWindowController.swift"), root = source("IslandRootView.swift")
        let kittens = source("KittenViews.swift"), app = source("AppState.swift"), delegate = source("AppDelegate.swift"), view = source("CatSettingsView.swift"), store = source("CatSettingsStore.swift")
        let shortcuts = source("ShortcutLogic.swift")

        CT.section("the window: a floating, non-activating panel that is never key, on every Space, outside fullscreen and the window cycle, click-through until the mouse is over the body")
        CT.checkTrue("the sources were read", ctl.contains("final class DesktopCatController") && panel.contains("final class DesktopCatPanel"))
        CT.checkTrue("borderless and non-activating, floating, never key or main", panel.contains("styleMask: [.borderless, .nonactivatingPanel]") && panel.contains("level = .floating") && panel.contains("override var canBecomeKey: Bool { false }") && panel.contains("override var canBecomeMain: Bool { false }"))
        CT.checkTrue("every Space, not the window cycle, and NOT a fullscreen auxiliary (it steps aside over a fullscreen app)", panel.contains("[.canJoinAllSpaces, .stationary, .ignoresCycle]") && !panel.contains("fullScreenAuxiliary]") && !panel.contains(".fullScreenAuxiliary,"))
        CT.checkTrue("click-through to begin with, and it does not hide when the app deactivates", panel.contains("ignoresMouseEvents = true") && panel.contains("hidesOnDeactivate = false"))
        CT.checkTrue("the body decides: the panel takes the mouse only over `hits`, or while dragging", ctl.contains("DesktopCatLayout.hits(rel") && ctl.contains("panel?.ignoresMouseEvents = !(over || dragging)"))
        CT.checkTrue("the marker is in the binary of every build: no #if around the panel", panel.contains("static let marker = \"NM_DESKTOP_CAT_PANEL\"") && !panel.contains("#if"))

        CT.section("nothing polls: one timer at the rule's rate, the mouse monitors only while the cat is drawn and visible, one-shots for the click and for a flight that ends unseen")
        CT.checkTrue("only a change of the target re-arms the one timer (DesktopCatPacer)", ctl.contains("switch pacer.target(fps)") && count("DispatchSource.makeTimerSource", in: ctl) == 1)
        CT.checkTrue("no Timer, no CADisplayLink and no sleeping loop", !ctl.contains("Timer.scheduledTimer") && !ctl.contains("CADisplayLink") && !ctl.contains("usleep") && !ctl.contains("Thread.sleep"))
        CT.checkTrue("the mouse monitors are mouse-moved event monitors, added only when the cat is drawn and not hidden, and removed otherwise", ctl.contains("matching: [.mouseMoved, .leftMouseDragged]") && ctl.contains("let want = phase.drawn") && ctl.contains("NSEvent.removeMonitor"))
        CT.checkTrue("a frame is skipped, not made, when the cat is not drawn", ctl.contains("guard phase.drawn else { return }") && count("guard phase.drawn", in: ctl) >= 2)
        CT.checkTrue("a slow frame does not slow the cat down: dt is held to 0.25 s, not the island's 0.05 s", count("maxDt: 0.25", in: ctl) == 2)

        CT.section("the trip: every event goes through desktopStep, and what Settings stores is the phase's `on`")
        CT.checkTrue("one entry point into the machine", ctl.contains("DesktopCatTrip.step(phase, event)") && count("DesktopCatTrip.step(", in: ctl) == 1)
        CT.checkTrue("the stored switch follows the phase, so quitting mid-flight home leaves the cat home", ctl.contains("if phase.on != was.on { store.setDesktopOn(phase.on) }"))
        CT.checkTrue("the menu item and ⌃⌥D toggle through the store: the store's switch against the phase", ctl.contains("func toggle() { store.setDesktopOn(!phase.on) }"))
        CT.checkTrue("the surprised emote comes first, then the flight starts after it", ctl.contains("emote(.surprised)") && ctl.contains("startMs: now + Self.surpriseMs"))
        CT.checkTrue("a turn keeps the flight's clock (turned), the notch end follows the island every frame, the screens move the desktop end", ctl.contains(".turned(at: now)") && ctl.contains("f.withNotchEnd(notchSpot())") && ctl.contains("f.withDesktopEnd(s)"))
        CT.checkTrue("a cat that was out flies out again once the greeting is over", ctl.contains("$0.0 != .greeting && !$0.1") && ctl.contains("send(.launch)"))
        CT.checkTrue("a click acts one double-click interval later, a double-click sends it home, a release on the island sends it home", ctl.contains("DesktopCatClicks(interval: NSEvent.doubleClickInterval)") && ctl.contains("case .doubleClick:") && ctl.contains("if onIsland(p) { send(.sendHome) } else { send(.move(drop)) }"))

        CT.section("the notch's spot is empty while the cat is out: the cat, its kittens and its hit area; nothing else of the island changes")
        CT.checkTrue("AppState publishes the phase", app.contains("@Published var desktopPhase = DesktopPhase.home"))
        CT.checkTrue("the big cat's place draws nothing while the notch is empty (and is the shipping view otherwise)", root.contains("if !state.desktopPhase.notchEmpty { catSpot }") && count("BotCanvasView(state: state, cat: state.cast.big.cat", in: root) == 2)
        CT.checkTrue("the slap and the drag start cannot hit an empty spot", island.contains("guard !s.desktopPhase.notchEmpty else { return false }"))

        CT.section("the drag: a window attaches as before, empty desktop places the cat, and the App Store build has no attach")
        CT.checkTrue("the drop goes through DesktopCatDrop", island.contains("DesktopCatDrop.decide(point:") && island.contains("self.finishBotDrag(at: mouse)"))
        CT.checkTrue("the attach is the code that shipped, inside #if !APPSTORE", island.contains("state.promptContext = ctx") && island.contains("ClaudeService.shared.clearConversation(state: state)") && island.contains("expand(to: .prompt)"))
        CT.checkTrue("the window under the cursor is asked first and its context only when there is one", island.contains("let windowUnder = windowBoundsAtScreenPoint(mouse) != nil") && island.contains("let context = windowUnder ? windowContextAtPoint(mouse) : nil"))
        CT.checkTrue("a place sends dragOut to the desktop cat, and a click opens the island", island.contains("desktop?.dragOut(to: spot)") && island.contains("func openFromDesktop()"))
        CT.checkTrue("the App Store flag comes from the build", ctl.contains("static let isAppStoreBuild = true") && ctl.contains("static let isAppStoreBuild = false"))

        CT.section("the app makes the cat once, after the island, and Settings and the store know it")
        CT.checkTrue("AppDelegate makes it after the island is set up and starts it", delegate.contains("DesktopCatController(island: island)") && delegate.contains("island.desktop = cat") && delegate.contains("cat.start()"))
        CT.checkTrue("the store holds the desktop settings and cleans them", store.contains("@Published private(set) var desktop: DesktopCatSettings") && store.contains("DesktopCatSettings.clean(next.json)"))
        CT.finish()
    }
}
```

**Create `scripts/test-cat-desktop-wiring.sh`**:

```bash
#!/usr/bin/env bash
# Desktop cat wiring (sub-project H): where the app's own files call the pure parts, pinned as source text (the panel, the click-through, the one timer, the trip's one entry point, the
# empty notch spot, the drop rule and the App Store split). The controller and the island need the whole app, so no test program can run them.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-desktop-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 tests/CatTestSupport.swift tests/DesktopCatWiringTests.swift -o "$TEST_DIR/desktop-wiring-tests"
"$TEST_DIR/desktop-wiring-tests"
```

```bash
chmod +x scripts/test-cat-desktop-wiring.sh
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-desktop-wiring.sh 2>&1 | tail -3`
Expected: FAIL: `the sources were read` and the pins after it, and a last line `N test(s) failed.` (the files do not exist yet).

- [ ] **Step 3: Write the code**

`DesktopCatDraw` is the one function that draws the cat (the app and the sheets of Tasks 6, 7 and 10): the big cat at full detail, the music dance applied around the head, and the kittens through `CatKittenDraw`. It only draws; the caller has moved the engines on.

**Create `NotchBuddy/Sources/App/DesktopCatDraw.swift`**:

```swift
import CoreGraphics
import Foundation
import QuartzCore

// Draws the desktop cat (sub-project H): the big cat at full detail (whiskers, stripes, fur lines if they are on, realistic eyes: small eyes are a notch-only look below Ø28),
// its state badge, its collar in the working agent's colour, the music dance and its agent's kittens. The desktop window and the contact sheets draw through this one function, so
// what the sheets show is what the desktop draws. It only draws: the caller has already moved the engines on by a frame. Needs the app's drawing files and nothing of AppKit.

@MainActor
enum DesktopCatDraw {
    struct Scene {
        /// The head width in points.
        var d: Double
        /// The head centre in the context's coordinates (y down).
        var head: (x: Double, y: Double)
        /// The kittens' places (`DesktopCatTrip.kittenSlots`).
        var slots: CatKittens.Slots
        /// The coat the kittens are kittens of: the cat's own.
        var parentCat: String
        /// The working agent's colour: the collar, the kittens' collars. nil when the cat is idle.
        var colour: String?
        /// Pixels per point.
        var dpr: Double
    }

    /// Draws one frame. `advance` moves a kitten's engine on by a frame (the app reads the real clock, a contact sheet its own); `now` is the clock the kittens' engines read (ms).
    static func draw(_ cg: CGContext, _ engine: CatEngine, _ scene: Scene, herd: CatKittenHerd, now: @escaping () -> Double, cfg: CatConfig? = nil, advance: (CatEngine) -> Void) {
        var options = CatDrawOptions()
        options.fur = engine.cfg.furLines                       // Settings → Cat → Fur lines
        options.collar = engine.collarPaint(dpr: scene.dpr)     // Settings → Cat → Collar
        cg.saveGState()
        if engine.dancingLevel > 0.001 {
            CatEffects.applyDance(cg, level: engine.dancingLevel, seconds: CACurrentMediaTime(), pivotX: scene.head.x, pivotY: scene.head.y + scene.d * 0.45, size: scene.d / 2)
        }
        let layout = CatRenderer.draw(cg, engine.look(), cx: scene.head.x, cy: scene.head.y, D: scene.d, options)
        cg.restoreGState()
        engine.base = layout.base
        engine.mouthPoint = layout.mouth
        CatKittenDraw.draw(cg, scene.slots, parentCat: scene.parentCat, origin: scene.head, unit: scene.d, colour: scene.colour, dpr: scene.dpr, herd: herd, now: now, cfg: cfg, advance: advance)
    }
}
```

The panel and its view. The marker string is in every build, and the panel has no `#if`: **the desktop cat ships in the App Store build too.**

**Create `NotchBuddy/Sources/App/DesktopCatPanel.swift`**:

```swift
import AppKit

// The desktop cat's window (sub-project H): a borderless, non-activating floating panel that is never key, so it never steals focus. It joins every Space, stays out of fullscreen Spaces
// (no `.fullScreenAuxiliary`: it steps aside over a fullscreen app) and out of the window cycle. Clicks pass through everywhere except the cat's body: the controller flips
// `ignoresMouseEvents` from the mouse position (`DesktopCatLayout.hits`), so the panel takes the mouse only while it is over the body. The marker string below is in every build
// (Debug, Release and App Store), and scripts/check-app-binary.sh proves it.

final class DesktopCatPanel: NSPanel {
    /// In every build's binary: `check-app-binary.sh` looks for it. It is longer than 15 bytes on purpose: Swift keeps a shorter string inside the code, where `strings` cannot see it.
    static let marker = "NM_DESKTOP_CAT_PANEL"

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        identifier = NSUserInterfaceItemIdentifier(Self.marker)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating                                         // above windows, below the island and the menus
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]   // every Space, not fullscreen ones, not in the window cycle
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true                                 // click-through until the mouse is over the body
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The cat's view: flipped (y down, like the contract and every canvas), it draws what the controller says and hands the mouse to it.
final class DesktopCatView: NSView {
    weak var controller: DesktopCatController?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        MainActor.assumeIsolated { controller?.draw(cg, dpr: Double(window?.backingScaleFactor ?? 2)) }
    }

    override func mouseDown(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseDown(event) } }
    override func mouseDragged(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseDragged(event) } }
    override func mouseUp(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseUp(event) } }
    override func rightMouseDown(with event: NSEvent) { MainActor.assumeIsolated { controller?.showMenu(with: event, in: self) } }
}
```

`NSScreen` as the contract's screens (the one with the menu bar first).

**Create `NotchBuddy/Sources/App/DesktopCatScreensApp.swift`**:

```swift
import AppKit

// The app's way into the contract's screens: `NSScreen.screens` as `DesktopCatScreens` takes them. Nothing here is in the contract, and the test programs do not compile this file.

extension DesktopCatScreens.AppKitScreen {
    /// The screens now, the one with the menu bar first.
    @MainActor static var all: [DesktopCatScreens.AppKitScreen] {
        NSScreen.screens.map { s in
            DesktopCatScreens.AppKitScreen(frame: DesktopRect(x: Double(s.frame.minX), y: Double(s.frame.minY), w: Double(s.frame.width), h: Double(s.frame.height)),
                                           visible: DesktopRect(x: Double(s.visibleFrame.minX), y: Double(s.visibleFrame.minY), w: Double(s.visibleFrame.width), h: Double(s.visibleFrame.height)))
        }
    }
}
```

The controller, as of this task. `dt` is held to 0.25 s and not the island's 0.05 s (`maxDt: 0.25`): at 5 fps a frame is 0.2 s, and a cat that is told only 0.05 s of it would move four times too slowly.

**Create `NotchBuddy/Sources/App/DesktopCatController.swift`**:

```swift
import AppKit
import Combine
import QuartzCore

// The desktop cat (sub-project H): the big cat living on the desktop. This is the app's side of the contract: it owns the trip's phase (`DesktopCatTrip.step` decides, this carries
// out the act), the flight's clock, the window (`DesktopCatPanel`), the mouse, the frame timer (`DesktopCatPacer`) and the links to the island, the store and the hook state. Every
// rule it follows is a pure file with a test program; nothing here is run by one, so `tests/DesktopCatWiringTests.swift` pins where it is called from. Nothing polls: one timer runs
// only while the cat is drawn and visible, at the rate `DesktopCatTrip.fps` says, and the mouse monitors exist only while it is.

@MainActor
final class DesktopCatController: NSObject {
    #if APPSTORE
    static let isAppStoreBuild = true
    #else
    static let isAppStoreBuild = false
    #endif

    /// An emote counts as motion (60 fps) for this long: the longest emote of `EMOUTH` in `cat-core.js` (love and proud), shared with the Windows and Linux app.
    static let emoteMs = 1800.0
    /// The surprised emote of an alert plays this long before the cat flies to the notch.
    static let surpriseMs = 450.0

    private let state: AppState
    private let store: CatSettingsStore
    private weak var island: IslandWindowController?
    private let engine: CatEngine
    private let herd = CatKittenHerd()

    private(set) var phase = DesktopPhase.home {
        didSet { if phase != oldValue { state.desktopPhase = phase } }
    }
    private var flight: DesktopCatTrip.Flight?
    /// The desktop spot (the head centre, contract coordinates) and where the head is now (the flight's position, or the drag's).
    private var spot: DesktopSpot?
    private var position = DesktopSpot(x: 0, y: 0)
    private var cursor = DesktopSpot(x: 0, y: 0)
    private var cursorDist: Double?
    private var frame = DesktopCatFrame(w: 100, h: 100, headX: 50, headY: 50)
    private var lastSlots = DesktopCatTrip.kittenSlots([], side: 1)
    private var screens: [DesktopScreen] = []
    private var primaryHeight = 0.0

    private var panel: DesktopCatPanel?
    private var catView: DesktopCatView?
    private var pacer = DesktopCatPacer()
    private var timer: DispatchSourceTimer?
    private var visibility = DesktopCatVisibility()
    private var monitors: [Any] = []
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var cancellables = Set<AnyCancellable>()
    private var retargetQueued = false
    private var flightDoneItem: DispatchWorkItem?
    /// A change of the kitten list (an arrival or a leave) is motion for 600 ms (`DesktopKittenWatch`).
    private var kittenWatch = DesktopKittenWatch()
    private var lastAlert = false

    private var clicks = DesktopCatClicks(interval: NSEvent.doubleClickInterval)
    private var clickItem: DispatchWorkItem?
    private var dragging = false
    private var grab = DesktopSpot(x: 0, y: 0)
    private var emoteUntil = 0.0
    private var overBody = false
    private var lastSize = DesktopSize.medium

    init(state: AppState = .shared, store: CatSettingsStore = .shared, island: IslandWindowController) {
        self.state = state
        self.store = store
        self.island = island
        engine = CatEngine.live(CatPresets.byID(state.cast.big.cat))
        super.init()
        lastSize = store.desktop.size
        refreshScreens()
    }

    private var nowMs: Double { CACurrentMediaTime() * 1000 }

    // MARK: Start

    /// Subscribes to everything the cat reacts to. Called once, after the island is set up. A cat that was out flies out again once the greeting is over.
    func start() {
        // The Settings switch, the menu-bar item and ⌃⌥D all end up in the store: the cat follows it.
        store.$desktop.dropFirst().removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] d in MainActor.assumeIsolated { self?.settingsChanged(d) } }
            .store(in: &cancellables)
        // After the greeting: a cat that was out flies back out.
        state.$view.combineLatest(state.$greetingTail).filter { $0.0 != .greeting && !$0.1 }.first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { if self?.store.desktop.on == true { self?.send(.launch) } } }
            .store(in: &cancellables)
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.refreshScreens()
            self?.send(.screensChanged)
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { handler() } }
        tokens.append((center, token))
    }

    // MARK: Controls (the menu-bar item, ⌃⌥D, the Settings switch and the cat's own menu all end here)

    /// Out if it is home, home if it is out: the menu-bar item and ⌃⌥D.
    func toggle() { store.setDesktopOn(!phase.on) }
    func sendHome() { send(.sendHome) }
    /// The big cat was dropped on empty desktop at `spot` (`DesktopCatDrop`).
    func dragOut(to spot: DesktopSpot) { send(.dragOut(spot)) }
    /// "Bring the cat home" while it is out, "Cat on the desktop" while it is home: the menu-bar item's title.
    var isOut: Bool { phase.on }

    private func settingsChanged(_ d: DesktopCatSettings) {
        if d.size != lastSize {
            lastSize = d.size
            if let s = spot, phase.drawn { spot = DesktopCatSpots.clampSpot(s, screens, size: d.size); if let c = spot { store.rememberDesktopSpot(c, on: screens) } }
            if flight == nil, let s = spot { position = s }
            tick()
        }
    }

    // MARK: The trip

    /// One event into the machine, and its act carried out.
    func send(_ event: DesktopEvent) {
        let was = phase
        let r = DesktopCatTrip.step(phase, event)
        phase = r.state
        if let act = r.act { perform(act, event) }
        if phase.on != was.on { store.setDesktopOn(phase.on) }   // what Settings stores; quitting mid-flight home leaves the cat home
        updateMonitors()
        retarget()
    }

    private func perform(_ act: DesktopAct, _ event: DesktopEvent) {
        let now = nowMs
        switch act {
        case .place:
            if case .dragOut(let p) = event, let c = DesktopCatSpots.clampSpot(p, screens, size: store.desktop.size) {
                spot = c; position = c; flight = nil
                store.rememberDesktopSpot(c, on: screens)
                show()
                emote(.happy)
            }
        case .flyOut:
            let target = ensureSpot()
            flight = .start(.out, notch: notchSpot(), desktop: target, at: now)
            position = notchSpot()
            show()
        case .flyHome:
            let from = position
            flight = DesktopCatTrip.Flight(from: from, to: notchSpot(), dir: .in, startMs: now)
            show()
        case .retract:
            emote(.surprised)
            flight = DesktopCatTrip.Flight(from: position, to: notchSpot(), dir: .in, startMs: now + Self.surpriseMs)
        case .turn:
            flight = (flight ?? DesktopCatTrip.Flight(from: position, to: notchSpot(), dir: .in, startMs: now)).turned(at: now)
        case .keep:
            break
        case .land:
            flight = nil
            if let s = spot { position = s }
        case .dock, .goHome:
            flight = nil
            hide()
        case .move:
            if case .move(let p) = event {
                spot = DesktopCatSpots.clampSpot(p, screens, size: store.desktop.size)
                if let c = spot { position = c; store.rememberDesktopSpot(c, on: screens) }
            }
        case .resettle:
            spot = store.desktop.spot(on: screens)
            if let s = spot {
                if let f = flight { flight = f.withDesktopEnd(s) } else { position = s }
            }
        }
        tick()
    }

    /// The remembered spot for the screens now, else the first spot ever.
    private func ensureSpot() -> DesktopSpot {
        if let s = spot { return s }
        let s = store.desktop.spot(on: screens) ?? DesktopSpot(x: 600, y: 300)
        spot = s
        return s
    }

    /// The big cat's place in the notch, in the contract's coordinates, for the island as it is now (compact, or open for an alert).
    private func notchSpot() -> DesktopSpot {
        let screen = IslandWindowController.notchScreen() ?? NSScreen.main ?? NSScreen.screens[0]
        let (islandW, islandH) = islandSize(mode: state.mode, view: state.view, progress: state.uploadProgress, nw: state.notchWidth, nh: state.notchHeight)
        let h: CGFloat = (state.mode == .expanded && state.view == .prompt) ? min(300, 240 + CGFloat(state.chatHistory.count) * 40) : islandH
        let (cx, cy, _, _) = botPosition(mode: state.mode, view: state.view, islandW: islandW, islandH: h, uploadProgress: state.uploadProgress, hasNotch: state.hasNotch, display: state.displayMode)
        let f = screen.frame
        let frame = DesktopRect(x: Double(f.minX), y: primaryHeight - Double(f.maxY), w: Double(f.width), h: Double(f.height))
        return DesktopCatLayout.notchSpot(screenFrame: frame, islandW: Double(islandW), cx: Double(cx), cy: Double(cy))
    }

    private func refreshScreens() {
        let list = DesktopCatScreens.AppKitScreen.all
        primaryHeight = DesktopCatScreens.primaryHeight(list)
        screens = DesktopCatScreens.contract(list)
    }

    // MARK: The window

    private func ensurePanel() -> DesktopCatPanel {
        if let p = panel { return p }
        let p = DesktopCatPanel(), v = DesktopCatView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        v.controller = self
        p.contentView = v
        panel = p; catView = v
        let token = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: p, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.occlusionChanged() }
        }
        tokens.append((NotificationCenter.default, token))
        return p
    }

    private func show() {
        let p = ensurePanel()
        layoutWindow()
        p.orderFrontRegardless()
    }

    private func hide() {
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
        overBody = false
    }

    /// The window around the cat, at the head's position: sized for the cat, its badge and its kittens, and no larger.
    private func layoutWindow() {
        guard let p = panel, let v = catView else { return }
        let side = DesktopCatLayout.side(of: position, screens: screens)
        lastSlots = DesktopCatTrip.kittenSlots(kittensNow(), side: side)
        let f = DesktopCatLayout.frame(d: store.desktop.size.d, slots: lastSlots)
        let o = DesktopCatLayout.origin(spot: position, frame: f, primaryHeight: primaryHeight)
        let rect = NSRect(x: o.x, y: o.y, width: f.w, height: f.h)
        frame = f
        if p.frame != rect { p.setFrame(rect, display: false); v.frame = NSRect(origin: .zero, size: rect.size) }
    }

    private func kittensNow() -> [CatKittens.Kitten] { [] }

    // MARK: Frames

    /// One frame: the flight moves on, the engines move on, the window follows the head, and the view is asked to draw.
    private func tick() {
        guard phase.drawn else { return }
        let now = nowMs
        if let f = flight {
            let f2 = f.withNotchEnd(notchSpot())
            flight = f2
            position = f2.position(at: now)
            if f2.isDone(at: now) { send(.flightDone); return }
        }
        prepareEngine()
        engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime, maxDt: 0.25))   // a slow frame (5 fps) must not slow the cat down
        layoutWindow()
        catView?.needsDisplay = true
        retarget()
    }

    /// The cat shows what the big cat shows: the cast's coat, the role's state, the working agent's colour as a collar, the music dance, and where the cursor is.
    private func prepareEngine() {
        engine.useCharacter(state.cast.big.cat)
        engine.setState(state.effectiveState)
        let look = CatGeometry.cursorLook(dx: cursor.x - position.x, dy: cursor.y - position.y)
        engine.lookX = look.x
        engine.lookY = look.y
    }

    private var dancing: Bool { false }

    func draw(_ cg: CGContext, dpr: Double) {
        guard phase.drawn else { return }
        let pillColour: String? = nil
        let scene = DesktopCatDraw.Scene(d: store.desktop.size.d, head: (frame.headX, frame.headY), slots: lastSlots, parentCat: state.cast.big.cat, colour: pillColour, dpr: dpr)
        DesktopCatDraw.draw(cg, engine, scene, herd: herd, now: { CACurrentMediaTime() * 1000 }) { e in
            e.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: e.lastTime, maxDt: 0.25))
        }
    }

    private func emote(_ e: BotEmote) {
        engine.triggerEmote(e)
        emoteUntil = nowMs + Self.emoteMs
        scheduleRetarget()
    }

    // MARK: The frame rate (nothing polls)

    private func scheduleRetarget() {}

    /// Until the frame-rate rule is in (`DesktopCatTrip.fps`), a cat that is drawn runs at 20 frames a second and a cat at home runs nothing.
    private func retarget() { arm(phase.drawn ? DesktopCatTrip.fpsActive : DesktopCatTrip.fpsOff) }

    /// The one timer: replaced only when the target changes (`DesktopCatPacer`), cancelled at 0.
    private func arm(_ fps: Double) {
        switch pacer.target(fps) {
        case .none: break
        case .stop:
            timer?.cancel(); timer = nil
        case .arm(let interval, let leeway):
            timer?.cancel()
            let t = DispatchSource.makeTimerSource(queue: .main)
            t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(Int(leeway * 1000)))
            t.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.tick() } }
            t.resume()
            timer = t
        }
    }

    private func occlusionChanged() {}
    private func visibilityChanged() { updateMonitors(); retarget() }

    // MARK: The mouse

    /// The mouse monitors exist only while the cat is drawn and can be seen: a mouse-moved event monitor, not a 60 Hz timer.
    private func updateMonitors() {
        let want = phase.drawn
        if want && monitors.isEmpty {
            let moved: @Sendable (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.mouseMoved() } }
            if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: moved) { monitors.append(g) }
            if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { e in moved(e); return e }) { monitors.append(l) }
            mouseMoved()
        } else if !want && !monitors.isEmpty {
            monitors.forEach { NSEvent.removeMonitor($0) }
            monitors = []
            panel?.ignoresMouseEvents = true
            overBody = false
            cursorDist = nil
        }
    }

    private func mouseSpot() -> DesktopSpot {
        let m = NSEvent.mouseLocation
        return DesktopCatScreens.spot(fromAppKit: Double(m.x), Double(m.y), primaryHeight: primaryHeight)
    }

    /// Takes the mouse only over the body; a hover wakes a sleeping cat; the distance feeds the frame rate.
    private func mouseMoved() {
        cursor = mouseSpot()
        let rel = DesktopSpot(x: cursor.x - position.x, y: cursor.y - position.y)
        cursorDist = hypot(rel.x, rel.y)
        let over = phase.drawn && DesktopCatLayout.hits(rel, d: store.desktop.size.d, slots: lastSlots, badge: engine.badge != nil)
        if over != overBody || dragging {
            overBody = over
            panel?.ignoresMouseEvents = !(over || dragging)
            if over { CatSleepClock.shared.wake("hover") }
        }
        scheduleRetarget()
    }

    func mouseDown(_ event: NSEvent) {
        CatSleepClock.shared.wake("click")
        cursor = mouseSpot()
        grab = DesktopSpot(x: cursor.x - position.x, y: cursor.y - position.y)
        handle(clicks.down(at: event.timestamp, cursor))
    }

    func mouseDragged(_ event: NSEvent) { cursor = mouseSpot(); handle(clicks.dragged(cursor)) }

    func mouseUp(_ event: NSEvent) {
        cursor = mouseSpot()
        handle(clicks.up(at: event.timestamp, cursor))
        if let until = clicks.waitUntil {   // a lone click acts after one double-click interval: one one-shot, not a poll
            clickItem?.cancel()
            let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self.map { $0.handle($0.clicks.timer(at: ProcessInfo.processInfo.systemUptime)) } } }
            clickItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, until - event.timestamp), execute: item)
        }
    }

    private func handle(_ outs: [DesktopCatClicks.Out]) {
        for out in outs {
            switch out {
            case .dragBegan:
                clickItem?.cancel()
                guard phase == .onDesktop else { break }   // a cat in flight cannot be picked up
                dragging = true
                retarget()
            case .dragMoved(let p):
                guard dragging else { break }
                position = DesktopSpot(x: p.x - grab.x, y: p.y - grab.y)
                tick()
            case .dragEnded(let p):
                guard dragging else { break }
                dragging = false
                let drop = DesktopSpot(x: p.x - grab.x, y: p.y - grab.y)
                if onIsland(p) { send(.sendHome) } else { send(.move(drop)) }   // let go on the notch: home; else the spot is clamped and saved
                panel?.ignoresMouseEvents = true; overBody = false
                mouseMoved()
            case .click:
                emote(.happy)
                island?.openFromDesktop()
            case .doubleClick:
                clickItem?.cancel()
                send(.sendHome)
            }
        }
    }

    private func onIsland(_ p: DesktopSpot) -> Bool {
        guard let r = island?.islandRectOnScreen() else { return false }
        let m = DesktopCatScreens.appKit(p, primaryHeight: primaryHeight)
        return r.insetBy(dx: -6, dy: -6).contains(CGPoint(x: m.x, y: m.y))
    }

    // MARK: The right-click menu

    func showMenu(with event: NSEvent, in view: NSView) {
        let shortcut: String? = nil
        let menu = NSMenu()
        func add(_ entries: [DesktopCatMenu.Entry], to menu: NSMenu) {
            for e in entries {
                switch e {
                case .separator: menu.addItem(.separator())
                case .note(let text): let i = NSMenuItem(title: text, action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i)
                case .action(let title, let a, let checked):
                    let i = NSMenuItem(title: title, action: #selector(menuPicked(_:)), keyEquivalent: "")
                    i.target = self; i.tag = Self.tag(a); i.state = checked ? .on : .off
                    menu.addItem(i)
                case .submenu(let title, let sub):
                    let i = NSMenuItem(title: title, action: nil, keyEquivalent: ""), m = NSMenu(title: title)
                    add(sub, to: m); i.submenu = m; menu.addItem(i)
                }
            }
        }
        add(DesktopCatMenu.entries(size: store.desktop.size, shortcut: shortcut), to: menu)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private static func tag(_ a: DesktopCatMenu.Action) -> Int {
        switch a {
        case .openNotch: return 1
        case .sendHome: return 2
        case .size(let s): return 10 + DesktopSize.allCases.firstIndex(of: s)!
        }
    }

    @objc private func menuPicked(_ item: NSMenuItem) {
        switch item.tag {
        case 1: island?.openFromDesktop()
        case 2: send(.sendHome)
        case 10...12: store.setDesktopSize(DesktopSize.allCases[item.tag - 10])
        default: break
        }
    }
}
```

`AppState` publishes the phase.

**Edit `NotchBuddy/Sources/App/AppState.swift`**, find this text (it occurs exactly once):

```swift
    @Published var catAsleep = false
```

and replace it with:

```swift
    @Published var catAsleep = false
    /// Where the desktop cat's trip is (`DesktopCatController`). While the cat is out (`DesktopPhase.notchEmpty`) the big cat's spot in the notch, its kittens and its hit area are empty:
    /// there are never two copies of one cat.
    @Published var desktopPhase = DesktopPhase.home
```

While the cat is out the big cat's place in the notch draws nothing. The existing `body` becomes `catSpot`, untouched.

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**, find this text (it occurs exactly once):

```swift

    var body: some View {
        let (cx, cy, diameter, opacity) = botPosition(mode: state.mode, view: state.view, islandW: islandW, islandH: islandH, uploadProgress: state.uploadProgress, hasNotch: state.hasNotch, display: state.displayMode)
```

and replace it with:

```swift

    /// While the cat lives on the desktop (`DesktopPhase.notchEmpty`) its spot in the notch is empty; everything else is as it ships.
    var body: some View {
        if !state.desktopPhase.notchEmpty { catSpot }
    }

    @ViewBuilder private var catSpot: some View {
        let (cx, cy, diameter, opacity) = botPosition(mode: state.mode, view: state.view, islandW: islandW, islandH: islandH, uploadProgress: state.uploadProgress, hasNotch: state.hasNotch, display: state.displayMode)
```

The island: the drop (`finishBotDrag(at:)` keeps the attach code as it shipped, behind `DesktopCatDrop`), the hit test of an empty spot, the island's rectangle on screen and a click from the desktop.

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, find this text (it occurs exactly once):

```swift
    private var botHoverStartPos: CGPoint = .zero
```

and replace it with:

```swift
    private var botHoverStartPos: CGPoint = .zero

    /// The desktop cat (sub-project H): a drag of the big cat that ends on empty desktop places it there, and ⌃⌥D takes it out or brings it home. Set by `AppDelegate`.
    weak var desktop: DesktopCatController?
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, find this text (it occurs exactly once):

```swift
                object: state.soundEnabled ? BotEmote.happy : BotEmote.annoyed)
```

and replace it with:

```swift
                object: state.soundEnabled ? BotEmote.happy : BotEmote.annoyed)
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, find this text (it occurs exactly once):

```swift
                #if !APPSTORE
                if let ctx = self.windowContextAtPoint(mouse) {
                    self.state.promptContext = ctx
                    ClaudeService.shared.clearConversation(state: self.state)
                    SoundEngine.shared.play("approve")
                    NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
                    self.expand(to: .prompt)
                }
                #endif
```

and replace it with:

```swift
                self.finishBotDrag(at: mouse)
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, find this text (it occurs exactly once):

```swift
                self.state.lastExternalApp = app
            }
        }
    }
```

and replace it with:

```swift
                self.state.lastExternalApp = app
            }
        }
    }

    /// The big cat was let go at `mouse` (AppKit's coordinates). A drop on another app's window attaches that window to a chat, exactly as before (not in the App Store build);
    /// a drop on no window places the cat on the desktop (`DesktopCatDrop` decides, and tests it); a drop on the island, or on a window that could not be attached, does nothing.
    private func finishBotDrag(at mouse: NSPoint) {
        let kit = DesktopCatScreens.AppKitScreen.all
        let top = DesktopCatScreens.primaryHeight(kit)
        #if !APPSTORE
        let windowUnder = windowBoundsAtScreenPoint(mouse) != nil
        let context = windowUnder ? windowContextAtPoint(mouse) : nil
        #else
        let windowUnder = false
        #endif
        let onIsland = islandRectOnScreen().insetBy(dx: -6, dy: -6).contains(mouse)
        #if !APPSTORE
        let captured = context != nil
        #else
        let captured = false
        #endif
        switch DesktopCatDrop.decide(point: DesktopCatScreens.spot(fromAppKit: Double(mouse.x), Double(mouse.y), primaryHeight: top), screens: DesktopCatScreens.contract(kit),
                                     size: CatSettingsStore.shared.desktop.size, onIsland: onIsland, windowUnder: windowUnder, contextCaptured: captured, appStore: DesktopCatController.isAppStoreBuild) {
        case .attach:
            #if !APPSTORE
            if let ctx = context {
                state.promptContext = ctx
                ClaudeService.shared.clearConversation(state: state)
                SoundEngine.shared.play("approve")
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
                expand(to: .prompt)
            }
            #endif
        case .place(let spot):
            desktop?.dragOut(to: spot)
        case .stayHome:
            break
        }
    }

    /// The island's rectangle on screen, in AppKit's coordinates (the same rectangle the poll uses for the mouse).
    func islandRectOnScreen() -> CGRect {
        guard let panel = window as? IslandPanel else { return .zero }
        return panel.currentIslandFrame(nw: notchW, nh: notchH).offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
    }

    /// A click on the desktop cat opens the island at the notch, like a click on the notch.
    func openFromDesktop() {
        CatSleepClock.shared.wake("click")
        guard state.mode != .expanded else { return }
        if fsm.state == .home { expand(to: defaultView()) } else { fsm.click() }
    }
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, find this text (it occurs exactly once):

```swift
        let s = AppState.shared
        let panelH = window?.frame.height ?? 320
```

and replace it with:

```swift
        let s = AppState.shared
        guard !s.desktopPhase.notchEmpty else { return false }   // the big cat is on the desktop: its spot in the notch is empty
        let panelH = window?.frame.height ?? 320
```

The delegate makes the controller once, after the island and its greeting have started, and starts it.

**Edit `NotchBuddy/Sources/App/AppDelegate.swift`**, find this text (it occurs exactly once):

```swift
    private(set) var islandController: IslandWindowController?
```

and replace it with:

```swift
    private(set) var islandController: IslandWindowController?
    /// The desktop cat (sub-project H), made once the island exists.
    private(set) var desktopCat: DesktopCatController?
```

**Edit `NotchBuddy/Sources/App/AppDelegate.swift`**, find this text (it occurs exactly once):

```swift
        islandController?.fsm.launch()
```

and replace it with:

```swift
        islandController?.fsm.launch()
        if let island = islandController {
            let cat = DesktopCatController(island: island)
            island.desktop = cat
            desktopCat = cat
            cat.start()   // a cat that was out flies back out once the greeting is over
        }
```

The binary check: the desktop cat's marker must be in every build, whatever the mode.

**Edit `scripts/check-app-binary.sh`**, find this text (it occurs exactly once):

```bash
has() { grep -qF -- "$1" "$STRINGS"; }
```

and replace it with:

```bash
has() { grep -qF -- "$1" "$STRINGS"; }
# The desktop cat (sub-project H) is in every build, Debug, Release and App Store: its panel carries this marker.
if [ -n "${2:-}" ]; then
    has NM_DESKTOP_CAT_PANEL || { echo "✗ the desktop cat (NM_DESKTOP_CAT_PANEL) is missing from this build" >&2; exit 1; }
    echo "✓ The desktop cat is in this build"
fi
```

- [ ] **Step 4: Run the wiring test and the build**

Run: `bash scripts/test-cat-desktop-wiring.sh 2>&1 | tail -3`
Expected: PASS, `All tests passed.`

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `Created project at …` and `** BUILD SUCCEEDED **`. Do not open the app.

Run: `bash -n scripts/check-app-binary.sh && bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Debug/NotchMeow.app debug`
Expected: three lines: `✓ The desktop cat is in this build`, `✓ The cat panel, the Claude Code engine and its override are in this Debug build` and a `FoundationModels` line.

- [ ] **Step 5: Prove the pins bite**

The one mistake that would cost the owner the most: a panel that is a fullscreen auxiliary (it would sit over a fullscreen app) and one that can become key (it would take the focus).

```bash
F=NotchBuddy/Sources/App/DesktopCatPanel.swift
cp "$F" "${TMPDIR:-/tmp}/h-mac-panel.keep"
sed -i '' 's/\[.canJoinAllSpaces, .stationary, .ignoresCycle\]/[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]/; s/override var canBecomeKey: Bool { false }/override var canBecomeKey: Bool { true }/' "$F"
bash scripts/test-cat-desktop-wiring.sh 2>&1 | grep -E "✗|failed"
cp "${TMPDIR:-/tmp}/h-mac-panel.keep" "$F"
bash scripts/test-cat-desktop-wiring.sh 2>&1 | tail -1
```

Expected: FAIL (`borderless and non-activating, floating, never key or main` and `every Space, not the window cycle, and NOT a fullscreen auxiliary…`, `2 test(s) failed.`), and `All tests passed.` once the file is back.

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and h-mac/desktop-cat: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/h-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(cat): the desktop cat's panel, click-through, drag out, flight and send home

DesktopCatController carries the trip (desktopStep, the flight's clock, place, move, home), the non-activating floating DesktopCatPanel, the mouse monitors that decide what takes the mouse, the right-click menu and a fixed 20 fps; the island empties the big cat's spot while it is out, the drop goes through DesktopCatDrop (a window still attaches as before) and the binary check finds NM_DESKTOP_CAT_PANEL in every build.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/DesktopCatDraw.swift NotchBuddy/Sources/App/DesktopCatPanel.swift NotchBuddy/Sources/App/DesktopCatScreensApp.swift NotchBuddy/Sources/App/DesktopCatController.swift NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/IslandRootView.swift NotchBuddy/Sources/App/IslandWindowController.swift NotchBuddy/Sources/App/AppDelegate.swift tests/DesktopCatWiringTests.swift scripts/test-cat-desktop-wiring.sh scripts/check-app-binary.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F "$MSG"
git status --short   # nothing of this task is left over
```


---

### Task 6: Alerts: the cat flies to the notch and back, and the flight strip (step 4)

**Agent:** `nm-implementer` (Haiku 5.5, high). The edits are given in full.

**Files:**
- Create: `scripts/render-cats-desktop.swift`
- Modify: `NotchBuddy/Sources/App/DesktopCatController.swift`, `DesktopCatTrip.swift`, `tests/DesktopCatWiringTests.swift`, `tests/DesktopCatTripTests.swift`, `scripts/render-cats.sh`, `scripts/render-cats.swift`

**Interfaces:**
- Consumes: Task 5's controller (`send`, `perform(.retract)` with its surprised emote and the flight that starts after it, `perform(.turn)`), Task 3's machine and flight.
- Produces: the alert sink (something needs the user, or nothing does any more → `.alertOn` or `.alertOff`, only on a change and not for the value at start); `DesktopCatTrip.alert(pendingApproval:pendingQuestion:chatApproval:pillStates:)` (the pure rule, with its tests in `DesktopCatTripTests`, written in this task's Step 2); `render-cats.sh --desktop-flight` (the alert flight as a strip of frames) and the extension file `render-cats-desktop.swift` the later sheets live in.

**What the machine already does** (Task 3's tests, H-0's trips): an approval that lands while the cat is on the desktop gives the surprised emote and a flight into the notch spot (`retracting`), then it sits at the notch while the user answers (`atNotchForAlert`: its panel is hidden and the notch shows it again); when both are clear it flies back to its spot (`returning`); an alert that clears mid-flight turns the cat around from progress `1 - t` without a jump; a `sendHome` during an alert ends the trip at home; an approval that lands while the cat is home, or while it flies home, does not take it out; a take-out while an approval is already pending flies it out and waits for the next alert (the contract's note). This task only connects the app's alerts to it. **What counts as an alert** (the Windows and Linux app's triggers, so the Mac has at least as many): `pendingApproval`, `pendingQuestion`, **a chat's approval card** (`AppState.chatApproval`, the Claude Code chat's Agent level; behind `#if !APPSTORE` because the App Store build has no chat engine) and **any pill whose state is `approval` or `question`**. The surprised beat before the flight is **450 ms** (`DesktopCatController.surpriseMs`, the value both apps share).

- [ ] **Step 1: Write the failing pin**

**Edit `tests/DesktopCatWiringTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkTrue("the menu item and ⌃⌥D toggle through the store: the store's switch against the phase", ctl.contains("func toggle() { store.setDesktopOn(!phase.on) }"))
```

and replace it with:

```swift
        CT.checkTrue("the menu item and ⌃⌥D toggle through the store: the store's switch against the phase", ctl.contains("func toggle() { store.setDesktopOn(!phase.on) }"))
        CT.checkTrue("an approval, a question, a chat's approval card or a pill in approval or question state turns into alertOn and alertOff, only on a change", ctl.contains("DesktopCatTrip.alert(pendingApproval: state.pendingApproval != nil, pendingQuestion: state.pendingQuestion != nil, chatApproval: chat") && ctl.contains("let chat = state.chatApproval != nil") && ctl.contains("state.tasks.map { CatState(rawValue: $0.state.rawValue) ?? .idle }") && ctl.contains("guard let self, self.alerting != self.lastAlert else { return }") && ctl.contains("send(self.lastAlert ? .alertOn : .alertOff)"))
        CT.checkTrue("the chat's approval is behind #if !APPSTORE (the App Store build has no chat engine)", ctl.contains("#if !APPSTORE\n        let chat = state.chatApproval != nil\n        #else\n        let chat = false"))
```

Run: `bash scripts/test-cat-desktop-wiring.sh 2>&1 | grep -E "✗|failed"`
Expected: FAIL: `an approval, a question, a chat's approval card or a pill in approval or question state turns into alertOn and alertOff, only on a change` and `the chat's approval is behind #if !APPSTORE…`, `2 test(s) failed.`

- [ ] **Step 2: Write the code**

First the pure rule and its test (Task 3's files gain a section each): what needs the user is an approval, a question, a chat's approval card or a pill in the approval or question state; an error, a rate limit or a dizzy cat is not an alert.

**Edit `NotchBuddy/Sources/App/DesktopCatTrip.swift`**, find this text (it occurs exactly once):

```swift

    // MARK: Kittens
```

and replace it with:

```swift

    // MARK: Alerts

    /// Whether something needs the user: a pending approval or question, a chat's approval card, or any pill in the approval or question state. The cat flies into the notch while
    /// this is true and back out when it is not.
    static func alert(pendingApproval: Bool, pendingQuestion: Bool, chatApproval: Bool, pillStates: [CatState]) -> Bool {
        pendingApproval || pendingQuestion || chatApproval || pillStates.contains { $0 == .approval || $0 == .question }
    }

    // MARK: Kittens
```

**Edit `tests/DesktopCatTripTests.swift`**, find this text (it occurs exactly once):

```swift

        CT.section("desktopFps: \(rows(fx["fpsCases"]).count) rows")
```

and replace it with:

```swift

        CT.section("what needs the user: an approval, a question, a chat's approval card, or a pill in approval or question state")
        CT.check("nothing", T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: false, pillStates: [.idle, .working, .finished]), false)
        CT.check("an approval", T.alert(pendingApproval: true, pendingQuestion: false, chatApproval: false, pillStates: []), true)
        CT.check("a question", T.alert(pendingApproval: false, pendingQuestion: true, chatApproval: false, pillStates: []), true)
        CT.check("the Claude chat's Agent approval card", T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: true, pillStates: []), true)
        CT.check("a pill in the approval state, with no card pending", T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: false, pillStates: [.working, .approval]), true)
        CT.check("a pill that asks a question", T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: false, pillStates: [.question]), true)
        CT.check("an error or a rate limit is not an alert", T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: false, pillStates: [.error, .ratelimit, .dizzy]), false)

        CT.section("desktopFps: \(rows(fx["fpsCases"]).count) rows")
```


The sink: `alerting` is `DesktopCatTrip.alert(…)` over the four triggers; `AppState`'s `objectWillChange` fires before a change, so `receive(on:)` reads the state after it settled, and only a change of `alerting` against the last value (`lastAlert`, read once at start, so a cat taken out while an approval waits is not turned around by it) is an event.

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**, find this text (it occurs exactly once):

```swift
    func start() {
```

and replace it with:

```swift
    func start() {
        // Something needs the user (an approval, a question, a chat's approval card, a pill in approval or question state) or nothing does any more: only a change is an event.
        lastAlert = alerting
        state.objectWillChange.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated {
                guard let self, self.alerting != self.lastAlert else { return }
                self.lastAlert = self.alerting
                self.send(self.lastAlert ? .alertOn : .alertOff)
            } }
            .store(in: &cancellables)
```

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**, find this text (it occurs exactly once):

```swift
        tokens.append((center, token))
```

and replace it with:

```swift
        tokens.append((center, token))
    }

    /// What the notch calls an alert: `pendingApproval` or `pendingQuestion`, a chat's approval card (the GitHub build's Claude Code chat) and any pill in the approval or question state.
    private var alerting: Bool {
        #if !APPSTORE
        let chat = state.chatApproval != nil
        #else
        let chat = false
        #endif
        return DesktopCatTrip.alert(pendingApproval: state.pendingApproval != nil, pendingQuestion: state.pendingQuestion != nil, chatApproval: chat,
                                    pillStates: state.tasks.map { CatState(rawValue: $0.state.rawValue) ?? .idle })
```

The flight strip lives in an extension of the sheet program, so the file `render-cats.swift` stays a list of modes. `mockDesktop`, `drawFrame`, `sheetKittens` and `drawDesktopCat` are the helpers the later sheets share; the strip draws the alert's arc dotted and the cat at 0, 20, 40, 60, 80 and 100 % of it, after one frame of surprise, with the engine's real emote.

**Create `scripts/render-cats-desktop.swift`**:

```swift
import CoreGraphics
import Foundation

// The desktop cat's sheets (sub-project H), part of scripts/render-cats.sh: a mock desktop with the cat at each size, the alert flight as a strip of frames, and the bench. They draw
// through `DesktopCatDraw` and the layout, the trip and the pacer of the app, so what the sheets show is what the desktop draws. Run through scripts/render-cats.sh (see the list at the top
// of scripts/render-cats.swift).

extension RenderCats {

    /// A mock desktop in points: a wallpaper, a menu bar, one app window (the click-through shape is easy to see against it) and, for the flight, the notch.
    @MainActor static func mockDesktop(_ cg: CGContext, x: Double, y: Double, w: Double, h: Double, notch: Bool = false) {
        cg.saveGState()
        cg.clip(to: CGRect(x: x, y: y, width: w, height: h))
        let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [CatDraw.rgb([38, 52, 92]), CatDraw.rgb([120, 74, 120])] as CFArray, locations: [0, 1])!
        cg.drawLinearGradient(grad, start: CGPoint(x: x, y: y), end: CGPoint(x: x + w, y: y + h), options: [])
        cg.fill(CatDraw.roundRect(x + 24, y + h * 0.42, w * 0.46, h * 0.46, 8), CatDraw.white(0.88))
        cg.fill(CatDraw.roundRect(x + 24, y + h * 0.42, w * 0.46, 20, 8), CatDraw.white(0.7))
        cg.fill(CatDraw.roundRect(x, y, w, 24, 0), CatDraw.black(0.45))
        if notch { cg.fill(CatDraw.roundRect(x + w / 2 - 58, y - 12, 116, 36, 12), CatDraw.black(1)) }
        cg.restoreGState()
    }

    /// The window the app would make around a cat at `head`, dashed, and (with `shapes`) the body that takes the mouse in green.
    @MainActor static func drawFrame(_ cg: CGContext, head: (x: Double, y: Double), d: Double, slots: CatKittens.Slots, shapes: Bool) {
        let f = DesktopCatLayout.frame(d: d, slots: slots)
        cg.saveGState()
        cg.setStrokeColor(CatDraw.white(0.55)); cg.setLineWidth(1); cg.setLineDash(phase: 0, lengths: [4, 3])
        cg.stroke(CGRect(x: head.x - f.headX, y: head.y - f.headY, width: f.w, height: f.h))
        cg.restoreGState()
        guard shapes else { return }
        var p = -f.headY
        while p < f.h - f.headY {
            var q = -f.headX
            while q < f.w - f.headX {
                if DesktopCatLayout.hits(DesktopSpot(x: q, y: p), d: d, slots: slots, badge: true) { cg.fill(CatDraw.roundRect(head.x + q, head.y + p, 2, 2, 0), CatDraw.rgb([60, 220, 120], 0.35)) }
                q += 2
            }
            p += 2
        }
    }

    /// Kittens of every state for the sheets.
    static func sheetKittens(_ n: Int) -> [CatKittens.Kitten] {
        (0..<n).map { CatKittens.Kitten(id: "k\($0)", state: [.approval, .searching, .working][$0 % 3], born: 0, last: 0) }
    }

    /// A desktop cat on a mock desktop: a big cat on a fake clock, settled for 1.5 s, then drawn by the one function the app draws with.
    @MainActor static func drawDesktopCat(_ cg: CGContext, coat: String, state: CatState, d: Double, head: (x: Double, y: Double), kittens: Int, side: Int, colour: String?, frames: Int = 90, emote: String? = nil, shapes: Bool = false) {
        let (e, clock, _) = scene(CatPresets.byID(coat), profile: "playful", D: d, state: state)
        e.collar = colour
        let rng = CatRNG(seed: 5), herd = CatKittenHerd()
        herd.rand = { rng.next() }
        let slots = DesktopCatTrip.kittenSlots(sheetKittens(kittens), side: side)
        let scratch = Sheet(width: 4, height: 4, scale: 1).cg
        let sceneValue = DesktopCatDraw.Scene(d: d, head: head, slots: slots, parentCat: coat, colour: colour, dpr: 2)
        if let emote { e.emote(emote) }
        for _ in 0..<frames {
            clock.t += 1000.0 / 60
            e.update(dt: 1.0 / 60)
            DesktopCatDraw.draw(scratch, e, sceneValue, herd: herd, now: { clock.t }) { $0.update(dt: 1.0 / 60) }
        }
        drawFrame(cg, head: head, d: d, slots: slots, shapes: shapes)
        DesktopCatDraw.draw(cg, e, sceneValue, herd: herd, now: { clock.t }) { $0.update(dt: 1.0 / 60) }
    }

    /// The alert flight as a strip of frames: the surprised cat on the desktop, then the arc to the notch at 0, 20, 40, 60, 80 and 100 %.
    @MainActor static func flightSheet(_ a: Args) -> Sheet {
        let pw = 300.0, ph = 330.0, n = 7.0, coat = a.cats.first ?? "shrimpy", d = DesktopSize.medium.d
        let sheet = Sheet(width: pw * n, height: ph + 28, scale: a.scale)
        let notch = DesktopSpot(x: pw / 2 + 56, y: 56), desk = DesktopSpot(x: pw - 70, y: 230)
        let flight = DesktopCatTrip.Flight(from: desk, to: notch, dir: .in, startMs: 0)
        for i in 0..<Int(n) {
            let ox = Double(i) * pw, oy = 28.0
            mockDesktop(sheet.cg, x: ox + 4, y: oy + 4, w: pw - 8, h: ph - 8, notch: true)
            // the arc, dotted, from the desktop spot to the notch
            for k in 0...30 {
                let p = flight.position(at: Double(k) / 30 * DesktopCatTrip.flightMs)
                sheet.cg.fill(CatDraw.circle(ox + p.x, oy + p.y, 1.5), CatDraw.white(0.5))
            }
            let t = i == 0 ? 0 : Double(i - 1) / 5
            let p = flight.position(at: t * DesktopCatTrip.flightMs)
            drawDesktopCat(sheet.cg, coat: coat, state: .approval, d: d, head: (ox + p.x, oy + p.y), kittens: 0, side: 1, colour: "#E07950", frames: i == 0 ? 20 : 20 + i * 4, emote: "surprised")
            CatDraw.text(sheet.cg, i == 0 ? "alert: surprised" : "\(Int(t * 100)) %", x: ox + pw / 2, y: 14, size: 12, bold: true, color: CatDraw.white(0.8))
        }
        return sheet
    }

}
```

**Edit `scripts/render-cats.sh`**, find this text (it occurs exactly once):

```bash
    scripts/render-cats.swift \
```

and replace it with:

```bash
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/DesktopCatLayout.swift $APP/DesktopCatInput.swift $APP/DesktopCatPacer.swift $APP/DesktopCatDraw.swift \
    scripts/render-cats.swift scripts/render-cats-desktop.swift \
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
//                                                                  to Ø24 (--scale is the device pixel ratio: look at 1 and 2)
```

and replace it with:

```swift
//                                                                  to Ø24 (--scale is the device pixel ratio: look at 1 and 2)
//   bash scripts/render-cats.sh --desktop-flight --scale 2         sub-project H: the alert flight as a strip of frames: surprised on the desktop, then the arc to the notch
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case benchKittens
```

and replace it with:

```swift
        case benchKittens
        case desktopFlight
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
            case "--bench-kittens": a.mode = .benchKittens
```

and replace it with:

```swift
            case "--bench-kittens": a.mode = .benchKittens
            case "--desktop-flight": a.mode = .desktopFlight
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case .benchKittens: bench(kittens: 8); return
```

and replace it with:

```swift
        case .benchKittens: bench(kittens: 8); return
        case .desktopFlight: sheet = flightSheet(a)
```

- [ ] **Step 3: Run the pin, draw the strip, build**

Run: `bash scripts/test-cat-desktop-wiring.sh 2>&1 | tail -1; bash scripts/test-cat-desktop-trip.sh 2>&1 | tail -1`
Expected: two lines, `All tests passed.` (the wiring pins, and the trip's program with the new `alert` section).

Run: `mkdir -p "${TMPDIR:-/tmp}/h-mac-2" && bash scripts/render-cats.sh --desktop-flight --scale 2 --out "${TMPDIR:-/tmp}/h-mac-2/flight.png" 2>&1 | tail -1`
Expected: `wrote …/h-mac-2/flight.png`. Look at it: seven panels, a mock desktop with the notch at the top of each; the first shows the surprised cat on the desktop, and the next six the cat on its dotted arc towards the notch at 0, 20, 40, 60, 80 and 100 %, with the alert badge. The arc bows to the right and upwards. A blank or broken image is a failed step.

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. Do not open the app.

- [ ] **Step 4: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and h-mac/desktop-cat: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/h-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(cat): the desktop cat flies to the notch for an alert and back

The controller turns an approval, a question, a chat's approval card and any pill in the approval or question state into alertOn and alertOff (only on a change; DesktopCatTrip.alert), the surprised beat is 450 ms, and render-cats.sh --desktop-flight draws the alert flight as a strip of frames.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/DesktopCatController.swift NotchBuddy/Sources/App/DesktopCatTrip.swift tests/DesktopCatWiringTests.swift tests/DesktopCatTripTests.swift scripts/render-cats-desktop.swift scripts/render-cats.sh scripts/render-cats.swift
git commit -F "$MSG"
git status --short   # nothing of this task is left over
```


---

### Task 7: What it shows: badge, kittens, collar, eyes, dance and sleep (step 5)

**Agent:** `nm-implementer` (Haiku 5.5, high). The edits are given in full.

**Files:**
- Modify: `NotchBuddy/Sources/App/DesktopCatController.swift`, `KittenViews.swift`, `tests/DesktopCatWiringTests.swift`, `scripts/render-cats.swift`, `scripts/render-cats-desktop.swift`

**Interfaces:**
- Consumes: Task 5's controller, B's `AppState.kittenView`, `CatRules.bigCatCollar`, `CatSleepClock`, `engine.setDancing`, Task 3's `kittenSlots`, Task 4's `DesktopCatLayout.frame`.
- Produces: the desktop cat's kittens (up to 3 beside it, then "+N", on its left in the right half of the screen), the collar in the working agent's colour, the Apple Music dance (not in the App Store build), and `render-cats.sh --desktop [--shapes]`. The state badge, the realistic eyes (no small eyes at Ø48 and up), the cursor-watching and the ten-minute sleep (and a hover or a click waking it) were in Task 5's engine and monitors; the kittens' sweep when the cat falls asleep is B's, unchanged.

**What "travels with it" means in the notch.** The big cat's kittens belong to its role's agent (`state.cast.big.pill`); while the cat is out its spot in the notch has none (`KittenPlacement` skips the big cat's layer; in Two cats mode the compact "×N" holds cat 2's kittens only). They come back with the cat.

- [ ] **Step 1: Write the failing pin**

**Edit `tests/DesktopCatWiringTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkTrue("the big cat's place draws nothing while the notch is empty (and is the shipping view otherwise)", root.contains("if !state.desktopPhase.notchEmpty { catSpot }") && count("BotCanvasView(state: state, cat: state.cast.big.cat", in: root) == 2)
```

and replace it with:

```swift
        CT.checkTrue("the big cat's place draws nothing while the notch is empty (and is the shipping view otherwise)", root.contains("if !state.desktopPhase.notchEmpty { catSpot }") && count("BotCanvasView(state: state, cat: state.cast.big.cat", in: root) == 2)
        CT.checkTrue("its kittens go with it, and the pair's count holds cat 2's only", kittens.contains("!($0.cat == 0 && state.desktopPhase.notchEmpty && !$0.countsBoth)") && kittens.contains("let bigPill = state.desktopPhase.notchEmpty ? nil : cast.big.pill"))
```

Run: `bash scripts/test-cat-desktop-wiring.sh 2>&1 | grep -E "✗|failed"`
Expected: FAIL: `its kittens go with it, and the pair's count holds cat 2's only`, `1 test(s) failed.`

- [ ] **Step 2: Write the code**

The controller reads the kittens of `cast.big.pill` for the frame and for the window, wears the collar the notch's big cat wears, and dances by the notch's rule without its mode conditions.

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**, find this text (it occurs exactly once):

```swift
    private func kittensNow() -> [CatKittens.Kitten] { [] }
```

and replace it with:

```swift
    private func kittensNow() -> [CatKittens.Kitten] { state.cast.big.pill.map { state.kittenView($0, at: nowMs) } ?? [] }
```

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**, find this text (it occurs exactly once):

```swift
        engine.setState(state.effectiveState)
```

and replace it with:

```swift
        engine.setState(state.effectiveState)
        engine.collar = CatRules.bigCatCollar(colour: state.focusTask?.color, state: CatState(rawValue: state.effectiveState.rawValue) ?? .idle)
        engine.setDancing(dancing)
```

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**, find this text (it occurs exactly once):

```swift
    private var dancing: Bool { false }
```

and replace it with:

```swift
    /// The Apple Music dance, as the notch's big cat does it (not in the App Store build).
    private var dancing: Bool {
        #if !APPSTORE
        guard state.musicPlaying, state.activeIntegrations.contains("integration_music") else { return false }
        return [BotState.idle, .working, .thinking, .searching, .finished].contains(state.effectiveState)
        #else
        return false
        #endif
    }
```

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**, find this text (it occurs exactly once):

```swift
        let pillColour: String? = nil
```

and replace it with:

```swift
        let pillColour = state.cast.big.pill.flatMap { id in state.tasks.first { $0.id == id }?.color }
```

The notch's kitten layer: while the cat is out the big cat's kittens are not drawn there.

**Edit `NotchBuddy/Sources/App/KittenViews.swift`**, find this text (it occurs exactly once):

```swift
                ForEach(parents, id: \.cat) { parent in
                    let spot = parent.cat == 0 ? cast.big : cast.second
                    let pills = parent.countsBoth ? [cast.big.pill, cast.second?.pill].compactMap { $0 } : [spot?.pill].compactMap { $0 }
```

and replace it with:

```swift
                ForEach(parents.filter { !($0.cat == 0 && state.desktopPhase.notchEmpty && !$0.countsBoth) }, id: \.cat) { parent in
                    let spot = parent.cat == 0 ? cast.big : cast.second
                    // The big cat's kittens travel with it: while it is on the desktop its spot in the notch has none (the pair's count then holds cat 2's only).
                    let bigPill = state.desktopPhase.notchEmpty ? nil : cast.big.pill
                    let pills = parent.countsBoth ? [bigPill, cast.second?.pill].compactMap { $0 } : [spot?.pill].compactMap { $0 }
```

The sheet: the three sizes on a mock desktop, idle and with kittens, and one in the right half of its screen; `--shapes` adds the body that takes the mouse (green) inside the window (dashed).

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
//   bash scripts/render-cats.sh --desktop-flight --scale 2         sub-project H: the alert flight as a strip of frames: surprised on the desktop, then the arc to the notch
```

and replace it with:

```swift
//   bash scripts/render-cats.sh --desktop-flight --scale 2         sub-project H: the alert flight as a strip of frames: surprised on the desktop, then the arc to the notch
//   bash scripts/render-cats.sh --desktop [--shapes] --scale 2    the desktop cat at Ø48, Ø64 and Ø96 on a mock desktop, idle and with kittens, and one in the right half of its screen;
//                                                                  --shapes shows the body that takes the mouse (green) inside the window (dashed)
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case desktopFlight
```

and replace it with:

```swift
        case desktopFlight
        case desktop
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        var steps: [Int]?
```

and replace it with:

```swift
        var steps: [Int]?
        var shapes = false
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
            case "--desktop-flight": a.mode = .desktopFlight
```

and replace it with:

```swift
            case "--desktop-flight": a.mode = .desktopFlight
            case "--desktop": a.mode = .desktop
            case "--shapes": a.shapes = true
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case .desktopFlight: sheet = flightSheet(a)
```

and replace it with:

```swift
        case .desktopFlight: sheet = flightSheet(a)
        case .desktop: sheet = desktopSheet(a)
```

**Edit `scripts/render-cats-desktop.swift`**, find this text (it occurs exactly once):

```swift

    /// The alert flight as a strip of frames: the surprised cat on the desktop, then the arc to the notch at 0, 20, 40, 60, 80 and 100 %.
```

and replace it with:

```swift

    /// The three sizes on a mock desktop, with and without kittens, and one in the right half of its screen (its kittens on its left).
    @MainActor static func desktopSheet(_ a: Args) -> Sheet {
        let pw = 400.0, ph = 330.0, cols = 4.0, rows = 2.0, coat = a.cats.first ?? "shrimpy"
        let sheet = Sheet(width: pw * cols, height: ph * rows + 28, scale: a.scale)
        let labels = ["Small Ø48", "Medium Ø64", "Large Ø96", "Medium, right half"]
        for (ci, size) in [DesktopSize.small, .medium, .large, .medium].enumerated() {
            for row in 0..<2 {
                let ox = Double(ci) * pw, oy = 28 + Double(row) * ph
                mockDesktop(sheet.cg, x: ox + 6, y: oy + 6, w: pw - 12, h: ph - 12)
                let right = ci == 3
                let head = (x: ox + (right ? pw - 150 : 190), y: oy + 150)
                drawDesktopCat(sheet.cg, coat: coat, state: row == 0 ? .idle : .working, d: size.d, head: head, kittens: row == 0 ? 0 : (ci == 1 ? 5 : 3), side: right ? -1 : 1, colour: row == 0 ? nil : "#E07950", shapes: a.shapes)
                if row == 0 { CatDraw.text(sheet.cg, labels[ci], x: ox + pw / 2, y: 14, size: 12, bold: true, color: CatDraw.white(0.8)) }
            }
        }
        return sheet
    }

    /// The alert flight as a strip of frames: the surprised cat on the desktop, then the arc to the notch at 0, 20, 40, 60, 80 and 100 %.
```

- [ ] **Step 3: Run the pin, draw the sheets, build**

Run: `bash scripts/test-cat-desktop-wiring.sh 2>&1 | tail -1`
Expected: `All tests passed.`

Run: `bash scripts/render-cats.sh --desktop --scale 2 --out "${TMPDIR:-/tmp}/h-mac-1/desktop.png" 2>&1 | tail -1; bash scripts/render-cats.sh --desktop --shapes --scale 2 --out "${TMPDIR:-/tmp}/h-mac-1/desktop-shapes.png" 2>&1 | tail -1`
Expected: two `wrote …` lines. Look at both: four columns (Small Ø48, Medium Ø64, Large Ø96 and Medium in the right half of its screen), two rows (idle with no kittens; working with a state badge, a collar in the agent's colour and three kittens, five at Medium so a "+2" shows). In the right-half column the kittens are on the cat's left. In `desktop-shapes.png` the dashed window holds the cat, its badge and its kittens and no more, and the green body is the head, the badge and the kittens only.

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. Do not open the app.

- [ ] **Step 4: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and h-mac/desktop-cat: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/h-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(cat): the desktop cat shows its kittens, collar and dance

The controller draws the big cat's kittens, the working agent's collar and the Apple Music dance; the notch's kitten layer skips the big cat while it is out; render-cats.sh --desktop draws the three sizes on a mock desktop, with the body that takes the mouse on request.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/DesktopCatController.swift NotchBuddy/Sources/App/KittenViews.swift tests/DesktopCatWiringTests.swift scripts/render-cats.swift scripts/render-cats-desktop.swift
git commit -F "$MSG"
git status --short   # nothing of this task is left over
```


---

### Task 8: The Settings switch (moved forward from step 7)

**Agent:** `nm-implementer-light` (Haiku 5.5, medium). The edits are given in full.

**Files:**
- Modify: `NotchBuddy/Sources/App/CatSettingsView.swift`, `NotchBuddy/Sources/App/DesktopCatController.swift`, `tests/DesktopCatWiringTests.swift`

**Interfaces:**
- Consumes: Task 2's `store.desktop.on` and `setDesktopOn`, Task 5's `send(.toggle)`.
- Produces: Settings → Cat → Desktop, a switch "Cat on the desktop" bound to the store; the controller follows the store: the switch moving against the phase's `on` is a `toggle` (the same path the menu-bar item and ⌃⌥D take in Task 12).

**Why it moved.** The spec puts the Settings switch in step 7, after the frame-rate rule, but checkpoint 1 is "pictures of S, M and L on a desktop mock, plus the Settings switch". The switch is a few lines, so it comes first.

- [ ] **Step 1: Write the failing pins**

**Edit `tests/DesktopCatWiringTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkTrue("the menu item and ⌃⌥D toggle through the store: the store's switch against the phase", ctl.contains("func toggle() { store.setDesktopOn(!phase.on) }"))
```

and replace it with:

```swift
        CT.checkTrue("the menu item and ⌃⌥D toggle through the store: the store's switch against the phase", ctl.contains("func toggle() { store.setDesktopOn(!phase.on) }"))
        CT.checkTrue("and the Settings switch is the same toggle: the store's switch against the phase", ctl.contains("if d.on != phase.on { send(.toggle) }"))
```

**Edit `tests/DesktopCatWiringTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkTrue("the store holds the desktop settings and cleans them", store.contains("@Published private(set) var desktop: DesktopCatSettings") && store.contains("DesktopCatSettings.clean(next.json)"))
```

and replace it with:

```swift
        CT.checkTrue("the store holds the desktop settings and cleans them", store.contains("@Published private(set) var desktop: DesktopCatSettings") && store.contains("DesktopCatSettings.clean(next.json)"))
        CT.checkTrue("Settings has the switch under the Display picker, bound to the store", view.contains("desktopGroup") && view.contains("Toggle(\"Cat on the desktop\"") && view.contains("store.setDesktopOn($0)"))
```

Run: `bash scripts/test-cat-desktop-wiring.sh 2>&1 | grep -E "✗|failed"`
Expected: FAIL: the Settings pin and the controller's (`and the Settings switch is the same toggle…`), `2 test(s) failed.`

- [ ] **Step 2: Write the code**

The group is a new `GroupBox` between Display and the pair; no existing row changes. The controller already follows the size; now it follows the switch too.

**Edit `NotchBuddy/Sources/App/CatSettingsView.swift`**, find this text (it occurs exactly once):

```swift
            displayGroup
```

and replace it with:

```swift
            displayGroup
            desktopGroup
```

**Edit `NotchBuddy/Sources/App/CatSettingsView.swift`**, find this text (it occurs exactly once):

```swift
                Text(modeNote)
```

and replace it with:

```swift
                Text(modeNote)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    // MARK: Desktop (sub-project H)

    /// The switch under the Display picker: the big cat out on the desktop, or home in the notch. The cat's own right-click menu picks its size.
    private var desktopGroup: some View {
        GroupBox("Desktop") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Cat on the desktop", isOn: Binding(get: { store.desktop.on }, set: { store.setDesktopOn($0) }))
                Text("The big cat leaves the notch and lives on your desktop. It watches the cursor, dances to music and sleeps, and it flies back to the notch when an approval or a question needs you. You can also drag it out of the notch.")
```

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**, find this text (it occurs exactly once):

```swift
    private func settingsChanged(_ d: DesktopCatSettings) {
```

and replace it with:

```swift
    private func settingsChanged(_ d: DesktopCatSettings) {
        if d.on != phase.on { send(.toggle) }   // the switch moved; the phase's own persisting does not come back here, it agrees already
```

- [ ] **Step 3: Run the pins, draw Settings, build**

Run: `bash scripts/test-cat-desktop-wiring.sh 2>&1 | tail -1`
Expected: `All tests passed.`

Run: `bash scripts/render-cat-settings.sh --out "${TMPDIR:-/tmp}/h-mac-1/settings.png" 2>&1 | tail -1`
Expected: `wrote …/h-mac-1/settings.png`. Look at it: Settings → Cat with Display first, then a "Desktop" group holding "Cat on the desktop" and a short note, then the Main cat. (The system controls may come out blank in this offscreen bitmap, as they do for every Settings sheet; the layout and the text do not.)

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. Do not open the app.

Run: `bash scripts/test-cat-settings-store.sh 2>&1 | tail -1`
Expected: `All tests passed.`

- [ ] **Step 4: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and h-mac/desktop-cat: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/h-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(cat): Settings → Cat → Desktop: the switch for the desktop cat

A "Desktop" group under Display with the "Cat on the desktop" switch, bound to the store; the controller follows the store's switch against the trip's phase.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/CatSettingsView.swift NotchBuddy/Sources/App/DesktopCatController.swift tests/DesktopCatWiringTests.swift
git commit -F "$MSG"
git status --short   # nothing of this task is left over
```


---

### Task 9: Owner checkpoint 1: the cat at S, M and L, and the Settings switch

No code and no commit. The session reports; the main session sends the owner the images and asks the questions below, then relays the owner's reply to the session.

- [ ] **Step 1: Collect the images**

```bash
mkdir -p .claude/checkpoints/h-mac && cp "${TMPDIR:-/tmp}/h-mac-1/desktop.png" "${TMPDIR:-/tmp}/h-mac-1/desktop-shapes.png" "${TMPDIR:-/tmp}/h-mac-1/settings.png" .claude/checkpoints/h-mac/ && ls .claude/checkpoints/h-mac
```

Expected: `desktop-shapes.png`, `desktop.png` and `settings.png`. (The folder is the worktree's own and is gitignored.)

```bash
for f in scripts/test-cat-*.sh; do printf '%-42s' "$f"; bash "$f" 2>&1 | tail -1; done
```

Expected: thirty-three lines: the contract's ends `✓ two generator runs write identical bytes` and the other thirty-two end `All tests passed.`

- [ ] **Step 2: What the owner looks at**

1. **The cat on a desktop** (`desktop.png`): is it the big cat, at full detail (whiskers, stripes, the realistic eyes) at Ø48, Ø64 and Ø96? Is the badge where the notch's big cat has it, and are the kittens (up to three, then "+N") in the right place beside it, and on its left in the right half of the screen? Is the collar in the agent's colour? Are the three sizes the ones you want (Ø64 is the default)? The numbers are `DesktopSize` (frozen contract values: a different size is a change in `cat-core.js`, the fixture and both apps).
2. **The window and what takes the mouse** (`desktop-shapes.png`): the dashed rectangle is the panel's window, sized for the cat, its badge and its kittens and no larger (the hearts of a happy cat rise into the room above); the green is the only part that takes the mouse, the head circle, the badge and the kittens. Is anything you would click missing from the green (the ear tips?), or anything you would not expect inside it? The numbers are `DesktopCatLayout` (`headK`, `badgeK`, the kittens' circles), one place.
3. **Settings** (`settings.png`): is "Desktop" under Display the right place and size for the switch? Is the note enough? The size is picked in the cat's own right-click menu, as the spec says.
4. **Not in the pictures, for the owner's real-build checks at the end:** the drag out of the notch, the flight, Spaces, a fullscreen app, two monitors and the CPU.

Record the owner's answers in the PR description.

---

### Task 10: The frame-rate rule, what hides the cat, the bench, and the Debug panel's Desktop section (step 6)

**Agent:** `nm-implementer` (Haiku 5.5, high). The code and the edits are given in full. If the cause of a failure is not obvious after one try, hand it to `nm-implementer-deep` (trigger 2).

**Files:**
- Create: `NotchBuddy/Sources/App/DesktopCatDevModel.swift`, `DesktopCatDevPanel.swift`; `tests/DesktopCatDevModelTests.swift`; `scripts/test-cat-desktop-devpanel.sh`
- Modify: `NotchBuddy/Sources/App/DesktopCatController.swift`, `CatDevPanel.swift`; `tests/DesktopCatWiringTests.swift`; `scripts/render-cats.swift`, `scripts/render-cats-desktop.swift`, `scripts/render-cat-panel.sh`, `scripts/check-app-binary.sh`; `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated)

**Interfaces:**
- Consumes: Task 3's `DesktopCatTrip.fps`, `FpsInput` and `Flight`; Task 4's `DesktopCatPacer`, `DesktopCatVisibility` and `DesktopKittenWatch`; Task 5's `arm(_:)`, the mouse monitors, `flight` and `DesktopCatDraw`; the existing Debug-only `CatDevView` ("Cats (Debug)…", `#if DEBUG && !APPSTORE`, marker `NM_CAT_DEV_PANEL`).
- Produces: the controller asks `DesktopCatTrip.fps` what the cat is doing and re-arms the one timer only when the answer changes; anything that can change the answer (a state, a kitten, sleep, an emote, the cursor coming near, a click) asks again once per run-loop turn (`scheduleRetarget`), never by polling; **what hides the cat**: the screens asleep, the session locked, the window covered or on another Space (`occlusionState`); a cat that cannot be seen has no timer and no mouse monitors, and a flight that ends meanwhile still ends (one one-shot); `render-cats.sh --bench-desktop`; **the live Desktop section of the Debug panel** (`DesktopCatDevModel` and `DesktopCatDevView`): a mock desktop with the cat, a button that fires the alert flight into the notch and one that clears it, the size picker, the kittens, and a readout of the frame rate the rule picks and what a frame costs. It is compiled out of Release and App Store builds, and `check-app-binary.sh` proves it with its own marker, `NM_CAT_DEV_DESKTOP`.

**The rule at work.** The input is `{phase, hidden, dragging, emote (for 1.8 s after one starts: the longest emote of `EMOUTH` in `cat-core.js`, love and proud), kittenMotion (600 ms after any change to the kitten list: an arrival or a leave), dance, asleep (the sleep clock's), working (the focus agent works, thinks or searches), cursorDist}`. Sleep beats the cursor and hidden beats everything (the contract's order). A cat at home or in the notch for an alert is not drawn: 0 fps and no timer, which is how "0 % CPU when the island is hidden" extends to the desktop cat. **The bench** draws the real cat at each size and reports **two rows at each of Ø48, Ø64 and Ø96**, the same two Windows and Linux report: idle and awake without kittens (5 fps, **held under 1 % of a core**) and 5 fps with three kittens (reported, not held); a third line adds asleep, working with kittens and the 60 fps of a flight.

- [ ] **Step 1: Write the failing pins and the failing dev-panel test**

**Edit `tests/DesktopCatWiringTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkTrue("no Timer, no CADisplayLink and no sleeping loop", !ctl.contains("Timer.scheduledTimer") && !ctl.contains("CADisplayLink") && !ctl.contains("usleep") && !ctl.contains("Thread.sleep"))
        CT.checkTrue("the mouse monitors are mouse-moved event monitors, added only when the cat is drawn and not hidden, and removed otherwise", ctl.contains("matching: [.mouseMoved, .leftMouseDragged]") && ctl.contains("let want = phase.drawn") && ctl.contains("NSEvent.removeMonitor"))
        CT.checkTrue("a frame is skipped, not made, when the cat is not drawn", ctl.contains("guard phase.drawn else { return }") && count("guard phase.drawn", in: ctl) >= 2)
        CT.checkTrue("a slow frame does not slow the cat down: dt is held to 0.25 s, not the island's 0.05 s", count("maxDt: 0.25", in: ctl) == 2)
```

and replace it with:

```swift
        CT.checkTrue("and the target comes from desktopFps", ctl.contains("arm(DesktopCatTrip.fps(input))"))
        CT.checkTrue("no Timer, no CADisplayLink and no sleeping loop", !ctl.contains("Timer.scheduledTimer") && !ctl.contains("CADisplayLink") && !ctl.contains("usleep") && !ctl.contains("Thread.sleep"))
        CT.checkTrue("the mouse monitors are mouse-moved event monitors, added only when the cat is drawn and not hidden, and removed otherwise", ctl.contains("matching: [.mouseMoved, .leftMouseDragged]") && ctl.contains("let want = phase.drawn") && ctl.contains("NSEvent.removeMonitor"))
        CT.checkTrue("from the frame-rate rule on, the monitors also stop while the cat is hidden", ctl.contains("let want = phase.drawn && !visibility.hidden"))
        CT.checkTrue("a frame is skipped, not made, when the cat is not drawn", ctl.contains("guard phase.drawn else { return }") && count("guard phase.drawn", in: ctl) >= 2)
        CT.checkTrue("a slow frame does not slow the cat down: dt is held to 0.25 s, not the island's 0.05 s", count("maxDt: 0.25", in: ctl) == 2)
        CT.checkTrue("the Debug-only cat panel has a Desktop section, compiled out of Release and App Store, with its own marker", source("CatDevPanel.swift").contains("DesktopCatDevView()") && source("DesktopCatDevPanel.swift").contains("#if DEBUG && !APPSTORE") && source("DesktopCatDevModel.swift").contains("#if DEBUG && !APPSTORE") && source("DesktopCatDevModel.swift").contains("static let marker = \"NM_CAT_DEV_DESKTOP\""))
        CT.checkTrue("hidden is the screens asleep, the session locked or the window covered", ctl.contains("screensDidSleepNotification") && ctl.contains("com.apple.screenIsLocked") && ctl.contains("occlusionState.contains(.visible)"))
```

**Create `tests/DesktopCatDevModelTests.swift`**:

```swift
import Foundation

@main
enum DesktopCatDevModelTests {
    final class Clock { var t = 10_000.0 }

    @MainActor static func main() {
        let clock = Clock()
        let rng = CatRNG(seed: 3)
        let m = DesktopCatDevModel(now: { clock.t }, rand: { rng.next() })
        func run(ms: Double) { var left = ms; while left > 0 { clock.t += 16; left -= 16; m.advance() } }

        CT.section("the Debug-only Desktop section: a mock desktop driven by the real rules")
        CT.checkTrue("its marker is longer than 15 bytes (a shorter string hides in the code, where the binary check cannot see it)", DesktopCatDevModel.marker.utf8.count > 15)
        CT.check("it starts on the desktop, at the desktop spot, at Medium with three kittens", [m.phase.rawValue, "\(m.position == DesktopCatDevModel.desk)", m.size.rawValue, "\(m.kittens)"], ["onDesktop", "true", "medium", "3"])
        CT.check("the rule picks 5 fps for a cat that sits there", m.fps(), 5)
        m.pick(size: .large); m.pick(kittens: 99)
        CT.check("a size and a number of kittens (held to 8)", [m.size.rawValue, "\(m.kittens)"], ["large", "8"])
        m.pick(kittens: -4)
        CT.check("and not below 0", m.kittens, 0)

        CT.section("an alert: the surprised beat, the flight into the notch, then the cat sits in the notch and nothing is drawn")
        m.fireAlert()
        CT.check("retracting, in the air: 60 fps", [m.phase.rawValue, "\(m.fps())"], ["retracting", "60.0"])
        run(ms: 200)
        CT.check("during the surprised beat (450 ms) the cat has not moved yet", m.position == DesktopCatDevModel.desk, true)
        run(ms: 450 + 600)
        CT.check("it has docked in the notch: the cat is not drawn, no frames", [m.phase.rawValue, "\(m.fps())", "\(m.flight == nil)"], ["atNotchForAlert", "0.0", "true"])
        CT.check("and the button state follows", m.alertIsOn, true)

        CT.section("the alert clears: the cat flies back out; cleared mid-flight it turns round without a jump")
        m.clearAlert()
        CT.check("returning", m.phase.rawValue, "returning")
        run(ms: 300)
        let before = m.position
        m.fireAlert()
        let after = m.flight!.position(at: clock.t)
        CT.checkTrue("an alert that lands mid-flight turns it round at the same place (jump \(hypot(before.x - after.x, before.y - after.y)))", hypot(before.x - after.x, before.y - after.y) < 25)
        CT.check("it is retracting again", m.phase.rawValue, "retracting")
        m.clearAlert()
        run(ms: 1500)
        CT.check("and lands back on its spot", [m.phase.rawValue, "\(m.position == DesktopCatDevModel.desk)"], ["onDesktop", "true"])
        CT.check("5 fps again", m.fps(), 5)

        CT.section("home: the toggle sends it into the notch and nothing runs")
        m.toggle()
        run(ms: 1200)
        CT.check("home, not drawn, 0 fps", [m.phase.rawValue, "\(m.fps())"], ["home", "0.0"])
        CT.checkTrue("the readout names the phase and the rate", m.readout.hasPrefix("home") && m.readout.contains("0.0 fps"))
        CT.finish()
    }
}
```

**Create `scripts/test-cat-desktop-devpanel.sh`**:

```bash
#!/usr/bin/env bash
# Desktop cat dev panel (sub-project H): the Debug-only Desktop section's model: an alert flight on a mock desktop (the surprised beat, the flight into the notch, the cat in the notch, the flight back, a turn
# without a jump) and the frame rate the rule picks, driven by the same pure rules the real desktop cat uses. Compiled with DEBUG, like the cat panel's own test.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-desktop-devpanel.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -D DEBUG \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatKittens.swift $APP/CatKittenDraw.swift $APP/CatIslandLayout.swift \
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/DesktopCatPacer.swift $APP/DesktopCatDraw.swift $APP/DesktopCatDevModel.swift \
    tests/CatTestSupport.swift tests/DesktopCatDevModelTests.swift \
    -o "$TEST_DIR/desktop-devpanel-tests"
"$TEST_DIR/desktop-devpanel-tests"
```

```bash
chmod +x scripts/test-cat-desktop-devpanel.sh
```

Run: `bash scripts/test-cat-desktop-wiring.sh 2>&1 | grep -E "✗|failed"; bash scripts/test-cat-desktop-devpanel.sh 2>&1 | grep -o "error opening input file" | sort -u`
Expected: FAIL: `and the target comes from desktopFps`, `from the frame-rate rule on, the monitors also stop while the cat is hidden`, `the Debug-only cat panel has a Desktop section…` and `hidden is the screens asleep, the session locked or the window covered`, `4 test(s) failed.`, then `error opening input file` for the dev panel's program.

- [ ] **Step 2: Write the code**

The controller: the rate, the visibility notifications (screens asleep or awake, the session locked or back, the screen locked through the distributed notification, the Space changing and the window's occlusion), the monitors' extra condition, and the one-shot for a flight that ends unseen. The stub of Task 5 (`retarget` at a fixed 20 fps) goes.

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**, find this text (it occurs exactly once):

```swift
            .store(in: &cancellables)
        // After the greeting: a cat that was out flies back out.
```

and replace it with:

```swift
            .store(in: &cancellables)
        // Anything that can change the frame rate (a state, a kitten, sleep) asks again once per run-loop turn; a cat at home ignores it.
        state.objectWillChange.sink { [weak self] _ in MainActor.assumeIsolated { self?.scheduleRetarget() } }.store(in: &cancellables)
        // After the greeting: a cat that was out flies back out.
```

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**, find this text (it occurs exactly once):

```swift
            self?.send(.screensChanged)
        }
    }
```

and replace it with:

```swift
            self?.send(.screensChanged)
        }
        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.visibility.screensAsleep = true; self?.visibilityChanged() }
        observe(ws, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.visibility.screensAsleep = false; self?.visibilityChanged() }
        observe(ws, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.visibility.locked = true; self?.visibilityChanged() }
        observe(ws, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.visibility.locked = false; self?.visibilityChanged() }
        observe(ws, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in self?.occlusionChanged() }
        let dc = DistributedNotificationCenter.default()
        observe(dc, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.visibility.locked = true; self?.visibilityChanged() }
        observe(dc, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.visibility.locked = false; self?.visibilityChanged() }
    }
```

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**, find this text (it occurs exactly once):

```swift
    private func scheduleRetarget() {}

    /// Until the frame-rate rule is in (`DesktopCatTrip.fps`), a cat that is drawn runs at 20 frames a second and a cat at home runs nothing.
    private func retarget() { arm(phase.drawn ? DesktopCatTrip.fpsActive : DesktopCatTrip.fpsOff) }
```

and replace it with:

```swift
    private func scheduleRetarget() {
        guard phase.drawn || timer != nil, !retargetQueued else { return }
        retargetQueued = true
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.retargetQueued = false; self?.retarget() } }
    }

    /// Asks `DesktopCatTrip.fps` what the cat is doing, and re-arms the one timer only when the answer changed.
    private func retarget() {
        let now = nowMs
        let busy = CatState(rawValue: state.effectiveState.rawValue)?.isBusy ?? false
        let input = DesktopCatTrip.FpsInput(phase: phase, hidden: visibility.hidden, dragging: dragging, emote: now < emoteUntil,
                                            kittenMotion: kittenWatch.observe(kittensNow(), now: now), dance: dancing, asleep: state.catAsleep,
                                            working: busy, cursorDist: cursorDist)
        arm(DesktopCatTrip.fps(input))
        // A flight that ends while the cat cannot be seen still ends: one one-shot for its end, not a poll.
        flightDoneItem?.cancel(); flightDoneItem = nil
        if timer == nil, let f = flight, phase.flight {
            let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.send(.flightDone) } }
            flightDoneItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, (f.startMs + DesktopCatTrip.flightMs - nowMs) / 1000), execute: item)
        }
    }
```

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**, find this text (it occurs exactly once):

```swift
    private func occlusionChanged() {}
    private func visibilityChanged() { updateMonitors(); retarget() }
```

and replace it with:

```swift
    // MARK: Visibility

    private func occlusionChanged() {
        visibility.covered = panel.map { !$0.occlusionState.contains(.visible) } ?? false
        visibilityChanged()
    }

    private func visibilityChanged() {
        updateMonitors()
        retarget()
        if !visibility.hidden { tick() }
    }
```

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**, find this text (it occurs exactly once):

```swift
        let want = phase.drawn
```

and replace it with:

```swift
        let want = phase.drawn && !visibility.hidden
```

The bench, with its two rows at each size, and a non-zero exit when a size is over 1 % idle and awake.

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
//                                                                  --shapes shows the body that takes the mouse (green) inside the window (dashed)
```

and replace it with:

```swift
//                                                                  --shapes shows the body that takes the mouse (green) inside the window (dashed)
//   bash scripts/render-cats.sh --bench-desktop                    the desktop cat's frame cost at each size and what it is at each frame rate (idle and awake must be under 1 % of a core)
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case desktop
    }
```

and replace it with:

```swift
        case desktop
        case benchDesktop
    }
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
            case "--shapes": a.shapes = true
```

and replace it with:

```swift
            case "--shapes": a.shapes = true
            case "--bench-desktop": a.mode = .benchDesktop
```

**Edit `scripts/render-cats.swift`**, find this text (it occurs exactly once):

```swift
        case .desktop: sheet = desktopSheet(a)
```

and replace it with:

```swift
        case .desktop: sheet = desktopSheet(a)
        case .benchDesktop: benchDesktop(); return
```

**Edit `scripts/render-cats-desktop.swift`**, find this text (it occurs exactly once):

```swift

}
```

and replace it with:

```swift

    /// The desktop cat's cost: update and draw at each size, and what that costs at the frame rate the rule picks for what the cat is doing. Idle and awake (5 fps, no kittens: kittens
    /// exist only while their agent works, which is 20 fps) must stay under 1 % of a core; asleep is about nothing; the busy rates are reported.
    @MainActor static func benchDesktop() {
        func measure(_ size: DesktopSize, state: CatState, kittens: Int) -> (avg: Double, p95: Double) {
            let sheet = Sheet(width: 400, height: 300, scale: 2)
            let (e, clock, _) = scene(CatPresets.byID("shrimpy"), profile: "playful", D: size.d, state: state)
            e.collar = state == .idle || state == .sleeping ? nil : "#E07950"
            let rng = CatRNG(seed: 5), herd = CatKittenHerd()
            herd.rand = { rng.next() }
            let value = DesktopCatDraw.Scene(d: size.d, head: (150, 150), slots: DesktopCatTrip.kittenSlots(sheetKittens(kittens), side: 1), parentCat: "shrimpy", colour: "#E07950", dpr: 2)
            var times: [Double] = []
            for f in 0..<600 {
                let start = cpuNow()
                sheet.cg.clear(CGRect(x: 0, y: 0, width: 400, height: 300))
                clock.t += 1000.0 / 60
                e.update(dt: 1.0 / 60)
                DesktopCatDraw.draw(sheet.cg, e, value, herd: herd, now: { clock.t }) { $0.update(dt: 1.0 / 60) }
                if f >= 60 { times.append((cpuNow() - start) * 1000) }
            }
            times.sort()
            return (times.reduce(0, +) / Double(times.count), times[Int(Double(times.count) * 0.95)])
        }
        func pct(_ ms: Double, _ fps: Double) -> Double { DesktopCatPacer.coreShare(msPerFrame: ms, fps: fps) * 100 }
        var failed = false
        for size in DesktopSize.allCases {
            let idle = measure(size, state: .idle, kittens: 0), withKittens = measure(size, state: .idle, kittens: 3)
            let asleep = measure(size, state: .sleeping, kittens: 0), busy = measure(size, state: .working, kittens: 3)
            let ok = pct(idle.avg, DesktopCatTrip.fpsIdle) < 1
            if !ok { failed = true }
            print(String(format: "Ø%.0f idle, no kittens: %.2f ms a frame, %.0f fps: %.2f %% of a core (held, under 1 %%: %@)", size.d, idle.avg, DesktopCatTrip.fpsIdle, pct(idle.avg, DesktopCatTrip.fpsIdle), ok ? "yes" : "NO"))
            print(String(format: "Ø%.0f %.0f fps with three kittens: %.2f ms a frame (p95 %.2f): %.2f %% of a core (reported, not held)", size.d, DesktopCatTrip.fpsIdle, withKittens.avg, withKittens.p95, pct(withKittens.avg, DesktopCatTrip.fpsIdle)))
            print(String(format: "Ø%.0f also: asleep %.1f fps %.2f %%; working with three kittens %.0f fps %.2f %%; in motion %.0f fps %.2f %%", size.d, DesktopCatTrip.fpsAsleep, pct(asleep.avg, DesktopCatTrip.fpsAsleep),
                         DesktopCatTrip.fpsActive, pct(busy.avg, DesktopCatTrip.fpsActive), DesktopCatTrip.fpsMotion, pct(busy.avg, DesktopCatTrip.fpsMotion)))
        }
        print(failed ? "FAIL: a size costs 1 % of a core or more while idle and awake" : "ok: idle and awake is under 1 % of a core at every size; hidden, home and the notch's folded island draw nothing (0 fps)")
        if failed { exit(1) }
    }
}
```

The Debug panel's Desktop section. The model drives the **real rules** on a mock desktop (`DesktopCatTrip.step`, the flight's clock with the 450 ms surprised beat, `desktopFps`, `DesktopCatDraw`): fire the alert and the cat flies into the notch and stays there (nothing is drawn, 0 fps); clear it and it flies back; clear or fire it mid-flight and it turns round without a jump. The view gives the frame rate to its timeline from the rule, four times a second.

**Create `NotchBuddy/Sources/App/DesktopCatDevModel.swift`**:

```swift
import Combine
import CoreGraphics
import Foundation
import QuartzCore

#if DEBUG && !APPSTORE

// What the Debug-only cat panel's Desktop section shows and does (sub-project H), with no SwiftUI in it: a mock desktop with the big cat on it, driven by the same pure rules the real
// desktop cat uses (`DesktopCatTrip.step`, the flight's clock, `desktopFps`, `DesktopCatDraw`): fire an alert and watch it fly into the notch, clear it and watch it fly back, pick a size,
// and read the frame rate the rule picks and what a frame costs. tests/DesktopCatDevModelTests.swift drives it; DesktopCatDevPanel.swift draws it. Debug builds only:
// `scripts/check-app-binary.sh` proves a Release build and an App Store build do not contain it. Nothing here touches the app's cats, the store or the island.

@MainActor
final class DesktopCatDevModel: ObservableObject {
    /// In a Debug build and in no other (20 bytes: a shorter string would hide in the code where `strings` cannot see it).
    static let marker = "NM_CAT_DEV_DESKTOP"
    /// The mock desktop, in points (y down), with the notch at the top and the cat's spot below it.
    static let stage = (w: 420.0, h: 260.0)
    static let notch = DesktopSpot(x: 210, y: 34), desk = DesktopSpot(x: 300, y: 170)

    let cfg = CatConfig()
    let now: () -> Double
    private let engine: CatEngine
    private let herd = CatKittenHerd()

    private(set) var phase = DesktopPhase.onDesktop
    private(set) var flight: DesktopCatTrip.Flight?
    private(set) var position = DesktopCatDevModel.desk
    @Published private(set) var size = DesktopSize.medium
    @Published private(set) var kittens = 3
    /// Milliseconds of the last frames' update and draw, smoothed: the readout's "what a frame costs".
    private(set) var frameMs = 0.0
    private var emoteUntil = 0.0
    private var lastMs: Double

    init(now: @escaping () -> Double = { CACurrentMediaTime() * 1000 }, rand: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.now = now
        engine = CatEngine(CatPresets.byID("shrimpy"), now: now, rand: rand, cfg: cfg, state: .idle)
        herd.rand = rand
        lastMs = now()
    }

    // MARK: Controls

    func pick(size s: DesktopSize) { size = s }
    /// 0 to 8 kittens beside the cat.
    func pick(kittens n: Int) { kittens = min(max(n, 0), 8) }
    func fireAlert() { send(.alertOn) }
    func clearAlert() { send(.alertOff) }
    func toggle() { send(.toggle) }
    var alertIsOn: Bool { phase == .retracting || phase == .atNotchForAlert }

    /// One event into the machine, and its act carried out on the mock: the same mapping the real controller makes.
    func send(_ e: DesktopEvent) {
        let t = now()
        let r = DesktopCatTrip.step(phase, e)
        phase = r.state
        switch r.act {
        case .retract?:
            engine.emote("surprised"); emoteUntil = t + 1800
            flight = .init(from: position, to: Self.notch, dir: .in, startMs: t + 450)
        case .flyOut?: flight = .start(.out, notch: Self.notch, desktop: Self.desk, at: t); position = Self.notch
        case .flyHome?: flight = .init(from: position, to: Self.notch, dir: .in, startMs: t)
        case .turn?: flight = (flight ?? .init(from: position, to: Self.notch, dir: .in, startMs: t)).turned(at: t)
        case .land?: flight = nil; position = Self.desk
        case .dock?, .goHome?: flight = nil
        default: break
        }
        objectWillChange.send()
    }

    // MARK: A frame

    /// What the rule says now.
    func fps() -> Double {
        DesktopCatTrip.fps(.init(phase: phase, emote: now() < emoteUntil, working: false, cursorDist: nil))
    }

    /// Moves the mock on by the real time since the last frame: the flight, the engine, a flight that is done.
    func advance() {
        let t = now()
        if let f = flight {
            position = f.position(at: t)
            if f.isDone(at: t) { send(.flightDone) }
        }
        engine.useCharacter("shrimpy")
        engine.setState(phase == .retracting || phase == .atNotchForAlert ? CatState.approval : CatState.idle)
        engine.update(dt: CatEngine.frameDelta(now: t / 1000, last: engine.lastTime, maxDt: 0.25))
    }

    /// Draws the mock desktop's cat (nothing when it is in the notch: the real notch would show it) and times the frame.
    func draw(_ cg: CGContext, dpr: Double) {
        let start = CACurrentMediaTime()
        guard phase.drawn else { return }
        let slots = DesktopCatTrip.kittenSlots((0..<kittens).map { CatKittens.Kitten(id: "k\($0)", state: [CatKittens.State.approval, .searching, .working][$0 % 3], born: 0, last: 0) }, side: 1)
        let scene = DesktopCatDraw.Scene(d: size.d, head: (position.x, position.y), slots: slots, parentCat: "shrimpy", colour: "#E07950", dpr: dpr)
        DesktopCatDraw.draw(cg, engine, scene, herd: herd, now: now, cfg: cfg) { $0.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: $0.lastTime, maxDt: 0.25)) }
        frameMs = frameMs == 0 ? (CACurrentMediaTime() - start) * 1000 : frameMs * 0.9 + (CACurrentMediaTime() - start) * 100
    }

    /// The readout: the phase, the rate the rule picks and what a frame costs, and what that is as a share of a core.
    var readout: String {
        let f = fps()
        let share = DesktopCatPacer.coreShare(msPerFrame: frameMs, fps: f) * 100
        return String(format: "%@ · rule: %.1f fps · a frame %.2f ms · %.2f %% of a core", phase.rawValue, f, frameMs, share)
    }
}

#endif
```

**Create `NotchBuddy/Sources/App/DesktopCatDevPanel.swift`**:

```swift
import SwiftUI
import QuartzCore

#if DEBUG && !APPSTORE

/// The Desktop section of the Debug-only cat panel (sub-project H): a mock desktop with the big cat, buttons that fire the alert flight into the notch and clear it, the size picker, the kittens,
/// and a live readout of the frame rate the rule picks and what a frame costs. The real desktop cat is not touched. Compiled in Debug builds only (`DesktopCatDevModel.marker`).
struct DesktopCatDevView: View {
    @StateObject private var model = DesktopCatDevModel()

    var body: some View {
        GroupBox("Desktop") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button("Fire an alert") { model.fireAlert() }.disabled(model.alertIsOn)
                    Button("Clear the alert") { model.clearAlert() }.disabled(!model.alertIsOn)
                    Picker("", selection: Binding(get: { model.size }, set: { model.pick(size: $0) })) {
                        Text("Small Ø48").tag(DesktopSize.small)
                        Text("Medium Ø64").tag(DesktopSize.medium)
                        Text("Large Ø96").tag(DesktopSize.large)
                    }.pickerStyle(.segmented).frame(maxWidth: 300)
                    Stepper("Kittens: \(model.kittens)", value: Binding(get: { model.kittens }, set: { model.pick(kittens: $0) }), in: 0...8).frame(maxWidth: 150)
                }
                // The frame rate follows the rule: the outer view looks again four times a second and gives the inner one its interval, so a cat that is not drawn runs nothing.
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let fps = model.fps()
                    VStack(alignment: .leading, spacing: 6) {
                        TimelineView(.animation(minimumInterval: 1 / max(fps, 0.5), paused: fps == 0)) { timeline in
                            Canvas { context, size in
                                _ = timeline.date
                                model.advance()
                                context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [Color(red: 0.15, green: 0.2, blue: 0.36), Color(red: 0.47, green: 0.29, blue: 0.47)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                                context.fill(Path(roundedRect: CGRect(x: size.width / 2 - 58, y: -12, width: 116, height: 36), cornerRadius: 12), with: .color(.black))
                                context.withCGContext { cg in model.draw(cg, dpr: Double(context.environment.displayScale)) }
                            }
                            .frame(width: DesktopCatDevModel.stage.w, height: DesktopCatDevModel.stage.h)
                            .accessibilityIdentifier(DesktopCatDevModel.marker)
                        }
                        Text(model.readout).font(.system(size: 11).monospacedDigit()).foregroundColor(.secondary)
                    }
                }
                Text("A mock desktop: the notch at the top, the cat's spot below it. The alert flight, the frame rate and the cost are the real rules and the real drawing function; the app's own desktop cat is untouched.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

#endif
```

The panel gets the section (one line), and its picture script the files the section needs.

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`**, find this text (it occurs exactly once):

```swift
            greetingBox
```

and replace it with:

```swift
            greetingBox
            DesktopCatDevView()
```

**Edit `scripts/render-cat-panel.sh`**, find this text (it occurs exactly once):

```bash
    $APP/CatDevModel.swift $APP/CatDevPanel.swift \
```

and replace it with:

```bash
    $APP/CatDevModel.swift $APP/CatDevPanel.swift \
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatKittens.swift $APP/CatKittenDraw.swift $APP/CatIslandLayout.swift \
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/DesktopCatPacer.swift $APP/DesktopCatDraw.swift $APP/DesktopCatDevModel.swift $APP/DesktopCatDevPanel.swift \
```

The binary check: the Desktop section's marker must be in a Debug build and in no other.

**Edit `scripts/check-app-binary.sh`**, find this text (it occurs exactly once):

```bash
panel=0; has NM_CAT_DEV_PANEL && panel=1
```

and replace it with:

```bash
panel=0; has NM_CAT_DEV_PANEL && panel=1
# The Desktop section of the cat panel (sub-project H) is Debug-only too.
devdesk=0; has NM_CAT_DEV_DESKTOP && devdesk=1
```

**Edit `scripts/check-app-binary.sh`**, find this text (it occurs exactly once):

```bash
        [ "$panel" = 0 ] || { echo "✗ the Debug-only cat panel (NM_CAT_DEV_PANEL) is in this build" >&2; exit 1; }
        [ "$override" = 0 ] || { echo "✗ the Debug-only Claude Code path override (NM_CLAUDE_CODE_PATH_OVERRIDE) is in this build" >&2; exit 1; }
```

and replace it with:

```bash
        [ "$panel" = 0 ] || { echo "✗ the Debug-only cat panel (NM_CAT_DEV_PANEL) is in this build" >&2; exit 1; }
        [ "$devdesk" = 0 ] || { echo "✗ the Debug-only Desktop section of the cat panel (NM_CAT_DEV_DESKTOP) is in this build" >&2; exit 1; }
        [ "$override" = 0 ] || { echo "✗ the Debug-only Claude Code path override (NM_CLAUDE_CODE_PATH_OVERRIDE) is in this build" >&2; exit 1; }
```

**Edit `scripts/check-app-binary.sh`**, find this text (it occurs exactly once):

```bash
        [ "$panel" = 0 ] || { echo "✗ the Debug-only cat panel (NM_CAT_DEV_PANEL) is in this build" >&2; exit 1; }
        [ "$override" = 0 ] || { echo "✗ the Debug-only Claude Code path override is in this build" >&2; exit 1; }
```

and replace it with:

```bash
        [ "$panel" = 0 ] || { echo "✗ the Debug-only cat panel (NM_CAT_DEV_PANEL) is in this build" >&2; exit 1; }
        [ "$devdesk" = 0 ] || { echo "✗ the Debug-only Desktop section of the cat panel (NM_CAT_DEV_DESKTOP) is in this build" >&2; exit 1; }
        [ "$override" = 0 ] || { echo "✗ the Debug-only Claude Code path override is in this build" >&2; exit 1; }
```

**Edit `scripts/check-app-binary.sh`**, find this text (it occurs exactly once):

```bash
        [ "$panel" = 1 ] || { echo "✗ the cat panel (NM_CAT_DEV_PANEL) is missing from this Debug build" >&2; exit 1; }
```

and replace it with:

```bash
        [ "$panel" = 1 ] || { echo "✗ the cat panel (NM_CAT_DEV_PANEL) is missing from this Debug build" >&2; exit 1; }
        [ "$devdesk" = 1 ] || { echo "✗ the cat panel's Desktop section (NM_CAT_DEV_DESKTOP) is missing from this Debug build" >&2; exit 1; }
```

- [ ] **Step 3: Run the pins, the dev panel's test, the bench, the panel's picture and the build**

Run: `bash scripts/test-cat-desktop-wiring.sh 2>&1 | tail -1; bash scripts/test-cat-desktop-devpanel.sh 2>&1 | tail -1`
Expected: two lines, `All tests passed.`

Run: `RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench-desktop 2>&1 | tail -10`
Expected: ten lines: for each of Ø48, Ø64 and Ø96 `Ø… idle, no kittens: … (held, under 1 %: yes)`, `Ø… 5 fps with three kittens: … (reported, not held)` and `Ø… also: …`, then `ok: idle and awake is under 1 % of a core at every size; hidden, home and the notch's folded island draw nothing (0 fps)`. The dry run read, on a busy machine: idle without kittens 0.27, 0.37 and 0.61 % of a core (0.54, 0.73 and 1.22 ms a frame at 5 fps); 5 fps with three kittens 0.48, 0.60 and **1.41 %** (reported); asleep 0.04 to 0.08 %; working with kittens 2.1, 2.6 and 6.0 % at 20 fps; a flight at 60 fps 6.2, 7.8 and 17.9 %. Write the lines down: they are checkpoint 2's numbers. A size over 1 % idle without kittens makes the script exit 1: stop and report (Open question 7 names the options).

Run: `bash scripts/render-cat-panel.sh --out "${TMPDIR:-/tmp}/h-mac-2/panel.png" 2>&1 | tail -1`
Expected: `wrote …/h-mac-2/panel.png`. Look at it: the panel as before, with a new "Desktop" group between Greeting and "Every coat, at every size": a mock desktop (a blue-violet gradient with the notch at the top), the big cat on it with its kittens, a readout line (`onDesktop · rule: 5.0 fps · a frame … ms · … % of a core`), the two buttons, the size picker and the kittens stepper. The system controls may come out blank in this offscreen bitmap; the cat, the readout and the layout do not.

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. Do not open the app.

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Debug/NotchMeow.app debug`
Expected: the same three lines as Task 5 (the Debug check now also needs `NM_CAT_DEV_DESKTOP`, so a Debug build without the Desktop section fails it). Task 13 proves the Release and App Store builds hold neither marker.

- [ ] **Step 4: Commit**

```bash
cd NotchBuddy && xcodegen > /dev/null && cd ..
```

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and h-mac/desktop-cat: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/h-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(cat): the desktop cat's frame-rate rule, what hides it, the bench and the Debug panel's Desktop section

The controller asks desktopFps what the cat is doing and re-arms its one timer only when the answer changes; the screens asleep or locked and a covered window hide it (no timer, no mouse monitors); render-cats.sh --bench-desktop reports idle without kittens (held under 1 %) and 5 fps with three kittens at each size; the Debug-only cat panel gets a live Desktop section (compiled out of Release and App Store, proved by check-app-binary.sh).

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/DesktopCatController.swift NotchBuddy/Sources/App/DesktopCatDevModel.swift NotchBuddy/Sources/App/DesktopCatDevPanel.swift NotchBuddy/Sources/App/CatDevPanel.swift tests/DesktopCatWiringTests.swift tests/DesktopCatDevModelTests.swift scripts/test-cat-desktop-devpanel.sh scripts/render-cats.swift scripts/render-cats-desktop.swift scripts/render-cat-panel.sh scripts/check-app-binary.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F "$MSG"
git status --short   # nothing of this task is left over
```


---

### Task 11: Owner checkpoint 2: the alert flight and the bench numbers

No code and no commit. The session reports; the main session sends the owner the image and the numbers and asks the questions below.

- [ ] **Step 1: Collect the image and the numbers**

```bash
cp "${TMPDIR:-/tmp}/h-mac-2/flight.png" "${TMPDIR:-/tmp}/h-mac-2/panel.png" .claude/checkpoints/h-mac/ && RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench-desktop > .claude/checkpoints/h-mac/bench.txt 2>&1; ls .claude/checkpoints/h-mac; cat .claude/checkpoints/h-mac/bench.txt
```

Expected: `bench.txt`, `desktop-shapes.png`, `desktop.png`, `flight.png`, `panel.png` and `settings.png`, then the ten bench lines.

- [ ] **Step 2: What the owner looks at**

1. **The alert flight** (`flight.png`): the first panel is the cat on the desktop as the alert arrives (surprised, with the alert badge); the next six are the flight into the notch, 0 to 100 %. Does the arc look right (a quarter of the distance, at most 90 pt, bowing upwards and, for a vertical flight, to the right), is the cat the same size all the way (it must be: the spec keeps it at full size), and is the surprised beat before the flight right (**450 ms**, the value both apps share)? The flight takes 0.6 s (`DESKTOP_FLIGHT_MS`, the contract), and flying back out after the alert is the same arc the other way, from the notch spot as it is at that moment (compact, or open for the alert). An alert that clears mid-flight turns the cat round with no jump (pinned by the tests).
2. **The numbers** (`bench.txt`): two rows at each size, the same two Windows and Linux report. Idle and awake **without kittens** (5 fps) is held under 1 % of a core (the dry run read 0.27, 0.37 and 0.61 %); 5 fps **with three kittens** is reported and not held (0.48, 0.60 and 1.41 %: Ø96 with three kittens is the one that passes 1 %, and it exists only while an agent works, which is the 20 fps row); about nothing asleep, and nothing at all when the cat is at home, in the notch for an alert, or cannot be seen. A busy cat (an agent working, 20 fps) costs 2 to 6 %, and 60 fps in a flight 7 to 19 %, for 0.6 s at a time or while the music plays. The bench draws into a bitmap, not into the window, so the owner's Activity Monitor check at the end is the real number.
3. **The Debug panel** (`panel.png`): "Cats (Debug)…" has a live Desktop section: a mock desktop with the cat, a button that fires the alert flight into the notch and one that clears it, the size picker, the kittens, and the frame rate the rule picks with what a frame costs. Open it on a Debug build to watch the flight move (it is compiled out of Release and App Store).
4. **Not in the picture:** the flight in the real window, over a fullscreen app (the cat steps aside), across Spaces and with a monitor unplugged are the owner's real-build checks.

---

### Task 12: The menu-bar item and ⌃⌥D (step 7)

**Agent:** `nm-implementer-light` (Haiku 5.5, medium). The edits are given in full.

**Files:**
- Modify: `NotchBuddy/Sources/App/ShortcutLogic.swift`, `IslandWindowController.swift`, `AppDelegate.swift`, `DesktopCatController.swift`; `tests/ShortcutTests.swift`, `tests/HotKeyCenterTests.swift`, `tests/DesktopCatWiringTests.swift`

**Interfaces:**
- Consumes: Task 5's `DesktopCatController.toggle()` and `isOut`, `IslandWindowController.desktop`; A's `ShortcutAction`, `ShortcutLogic`, `HotKeyCenter`.
- Produces: the shortcut action `desktop` (**frozen ID**), appended last (Carbon identifies a hot key by its index in `allCases`), default ⌃⌥D (key code 2 with ⌃⌥), **on by default**, in the App Store build too, with no "off at first" note; the menu-bar item "Cat on the desktop", which becomes "Bring the cat home" while the cat is out (`NSMenuDelegate.menuNeedsUpdate`); the cat's right-click menu shows the shortcut's line when it is on.

**The sixth default-on shortcut changes the tests' counts.** The existing programs pin the set that is on at first (five), the App Store set (four), "all eight", the number of actions and the order. They change with it, and they are the proof that the new action is appended and that nothing else moved: `HotKeyCenterTests` needs one more key (the ISO section key, 10, with all four modifiers: nobody binds it) for the eighth action besides the island shortcut.

- [ ] **Step 1: Write the failing tests**

**Edit `tests/ShortcutTests.swift`**, find this text (it occurs exactly once):

```swift
        check(ShortcutAction.allCases.first == .toggleIsland && ShortcutAction.allCases.last == .muteToggle,
```

and replace it with:

```swift
        check(ShortcutAction.allCases.first == .toggleIsland && ShortcutAction.allCases.last == .desktop,
```

**Edit `tests/ShortcutTests.swift`**, find this text (it occurs exactly once):

```swift
    /// The owner's decision: five on, three off. The off ones keep their combinations so that turning one on is a click.
    static func testDefaultsOnAndOff() {
        let on: Set<ShortcutAction> = [.goToAlert, .attachFrontWindow, .nextPill, .prevPill, .muteToggle]
```

and replace it with:

```swift
    /// The owner's decision: five on, three off, and since sub-project H the desktop cat's ⌃⌥D on as well (six on). The off ones keep their combinations so that turning one on is a click.
    static func testDefaultsOnAndOff() {
        let on: Set<ShortcutAction> = [.goToAlert, .attachFrontWindow, .nextPill, .prevPill, .muteToggle, .desktop]
```

**Edit `tests/ShortcutTests.swift`**, find this text (it occurs exactly once):

```swift
            check(Set(ShortcutLogic.activeSpecs(appStore: false, in: ud).keys) == on, "a fresh store registers exactly the five")
            check(Set(ShortcutLogic.activeSpecs(appStore: true, in: ud).keys) == [.goToAlert, .nextPill, .prevPill, .muteToggle],
                  "and four in the App Store build, which has no front-window shortcut")
```

and replace it with:

```swift
            check(Set(ShortcutLogic.activeSpecs(appStore: false, in: ud).keys) == on, "a fresh store registers exactly the six")
            check(Set(ShortcutLogic.activeSpecs(appStore: true, in: ud).keys) == [.goToAlert, .nextPill, .prevPill, .muteToggle, .desktop],
                  "and five in the App Store build, which has no front-window shortcut and does have the desktop cat")
            check(ShortcutLogic.hotKey(for: .desktop, in: ud) == ShortcutSpec(keyCode: 2, nsFlags: ctrlOpt), "⌃⌥D is the desktop cat's")
```

**Edit `tests/ShortcutTests.swift`**, find this text (it occurs exactly once):

```swift
            check(normal.count == 5 && normal[.toggleIsland] == nil && normal[.openChat] == nil && normal[.jumpToTerminal] == nil,
                  "five are on at first: not the island shortcut, the chat or the terminal")
            check(ShortcutLogic.activeSpecs(appStore: true, in: ud).count == 4, "four in the App Store build")
```

and replace it with:

```swift
            check(normal.count == 6 && normal[.toggleIsland] == nil && normal[.openChat] == nil && normal[.jumpToTerminal] == nil,
                  "six are on at first: not the island shortcut, the chat or the terminal")
            check(ShortcutLogic.activeSpecs(appStore: true, in: ud).count == 5, "five in the App Store build")
```

**Edit `tests/ShortcutTests.swift`**, find this text (it occurs exactly once):

```swift
            check(Set(ShortcutLogic.activeSpecs(appStore: false, in: ud).keys) == Set(ShortcutAction.allCases), "all eight are on")
```

and replace it with:

```swift
            check(Set(ShortcutLogic.activeSpecs(appStore: false, in: ud).keys) == Set(ShortcutAction.allCases), "all nine are on")
```

**Edit `tests/HotKeyCenterTests.swift`**, find this text (it occurs exactly once):

```swift
    /// F13 to F19: keys with no function on any keyboard that sold in years.
    static let fKeys: [UInt16] = [105, 107, 113, 106, 64, 79, 80]
```

and replace it with:

```swift
    /// F13 to F19 and the ISO section key: keys with no function on any keyboard that sold in years, with all four modifiers held.
    static let fKeys: [UInt16] = [105, 107, 113, 106, 64, 79, 80, 10]
```

**Edit `tests/HotKeyCenterTests.swift`**, find this text (it occurs exactly once):

```swift
        check(actions.count == 7, "seven actions besides the island shortcut")
```

and replace it with:

```swift
        check(actions.count == 8, "eight actions besides the island shortcut")
```

**Edit `tests/HotKeyCenterTests.swift`**, find this text (it occurs exactly once):

```swift
        // Start: what is on at first is registered (five of the eight), and a press runs the right action, once.
        let onAtFirst = actions.filter { $0.enabledByDefault }
        check(onAtFirst.count == 5, "five are on at first")
        var pressed: [ShortcutAction] = []
        center.start { pressed.append($0) }
        check(center.registered == Set(onAtFirst), "only the five that are on at first are registered")
```

and replace it with:

```swift
        // Start: what is on at first is registered (six of the nine), and a press runs the right action, once.
        let onAtFirst = actions.filter { $0.enabledByDefault }
        check(onAtFirst.count == 6, "six are on at first")
        var pressed: [ShortcutAction] = []
        center.start { pressed.append($0) }
        check(center.registered == Set(onAtFirst), "only the six that are on at first are registered")
```

**Edit `tests/HotKeyCenterTests.swift`**, find this text (it occurs exactly once):

```swift
        // "Turn all on" with the real thing behind it: the other three are registered, and delivered.
```

and replace it with:

```swift
        // "Turn all on" with the real thing behind it: the other three are registered (the desktop cat's is on already), and delivered.
```

**Edit `tests/HotKeyCenterTests.swift`**, find this text (it occurs exactly once):

```swift
        check(center.registered == Set(ShortcutAction.allCases), "all eight are registered")
```

and replace it with:

```swift
        check(center.registered == Set(ShortcutAction.allCases), "all nine are registered")
```

**Edit `tests/HotKeyCenterTests.swift`**, find this text (it occurs exactly once):

```swift
        check(center.registered.count == 7, "the others stay")
```

and replace it with:

```swift
        check(center.registered.count == 8, "the others stay")
```

**Edit `tests/HotKeyCenterTests.swift`**, find this text (it occurs exactly once):

```swift
        check(center.registered.count == 7 && !center.registered.contains(.muteToggle),
              "eight are on, the refused one is not registered: \(center.registered.count)")
```

and replace it with:

```swift
        check(center.registered.count == 8 && !center.registered.contains(.muteToggle),
              "nine are on, the refused one is not registered: \(center.registered.count)")
```

**Edit `tests/DesktopCatWiringTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkTrue("a place sends dragOut to the desktop cat, and a click opens the island", island.contains("desktop?.dragOut(to: spot)") && island.contains("func openFromDesktop()"))
```

and replace it with:

```swift
        CT.checkTrue("a place sends dragOut to the desktop cat, and a click opens the island", island.contains("desktop?.dragOut(to: spot)") && island.contains("func openFromDesktop()"))
        CT.checkTrue("⌃⌥D toggles it", island.contains("desktop?.toggle()"))
```

**Edit `tests/DesktopCatWiringTests.swift`**, find this text (it occurs exactly once):

```swift
        CT.checkTrue("Settings has the switch under the Display picker, bound to the store", view.contains("desktopGroup") && view.contains("Toggle(\"Cat on the desktop\"") && view.contains("store.setDesktopOn($0)"))
```

and replace it with:

```swift
        CT.checkTrue("Settings has the switch under the Display picker, bound to the store", view.contains("desktopGroup") && view.contains("Toggle(\"Cat on the desktop\"") && view.contains("store.setDesktopOn($0)"))
        CT.checkTrue("the action is appended, never inserted, and handled", shortcuts.contains("case desktop ") && island.contains("case .desktop:"))
```

Run: `bash scripts/test-shortcuts.sh 2>&1 | grep -E "error:" | head -2; bash scripts/test-hotkeys.sh 2>&1 | grep -E "error:" | head -2`
Expected: FAIL with compile errors (`ShortcutAction` has no member `desktop`).

- [ ] **Step 2: Write the code**

The action is a new `case` after `muteToggle` with its name, its default-on state and its combination.

**Edit `NotchBuddy/Sources/App/ShortcutLogic.swift`**, find this text (it occurs exactly once):

```swift
    case muteToggle         // ⌃⌥M: mute or unmute sounds
```

and replace it with:

```swift
    case muteToggle         // ⌃⌥M: mute or unmute sounds
    case desktop            // ⌃⌥D: the big cat out on the desktop, or home in the notch. On by default; in the App Store build too. The action ID is frozen.
```

**Edit `NotchBuddy/Sources/App/ShortcutLogic.swift`**, find this text (it occurs exactly once):

```swift
        case .muteToggle:        return "Mute or unmute sounds"
```

and replace it with:

```swift
        case .muteToggle:        return "Mute or unmute sounds"
        case .desktop:           return "Cat on the desktop"
```

**Edit `NotchBuddy/Sources/App/ShortcutLogic.swift`**, find this text (it occurs exactly once):

```swift
        case .goToAlert, .attachFrontWindow, .nextPill, .prevPill, .muteToggle: return true
```

and replace it with:

```swift
        case .goToAlert, .attachFrontWindow, .nextPill, .prevPill, .muteToggle, .desktop: return true
```

**Edit `NotchBuddy/Sources/App/ShortcutLogic.swift`**, find this text (it occurs exactly once):

```swift
        case .toggleIsland, .goToAlert, .attachFrontWindow, .nextPill, .prevPill, .muteToggle:
```

and replace it with:

```swift
        case .toggleIsland, .goToAlert, .attachFrontWindow, .nextPill, .prevPill, .muteToggle, .desktop:
```

**Edit `NotchBuddy/Sources/App/ShortcutLogic.swift`**, find this text (it occurs exactly once):

```swift
        .muteToggle:        ShortcutSpec(keyCode: 46, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥M
```

and replace it with:

```swift
        .muteToggle:        ShortcutSpec(keyCode: 46, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥M
        .desktop:           ShortcutSpec(keyCode: 2,  nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥D
```

⌃⌥D toggles the cat. The delegate adds the menu-bar item and updates its title when the menu opens.

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, find this text (it occurs exactly once):

```swift
                object: state.soundEnabled ? BotEmote.happy : BotEmote.annoyed)

        }
```

and replace it with:

```swift
                object: state.soundEnabled ? BotEmote.happy : BotEmote.annoyed)

        case .desktop:
            desktop?.toggle()
        }
```

**Edit `NotchBuddy/Sources/App/AppDelegate.swift`**, find this text (it occurs exactly once):

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
```

and replace it with:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
```

**Edit `NotchBuddy/Sources/App/AppDelegate.swift`**, find this text (it occurs exactly once):

```swift
        menu.addItem(withTitle: "Open NotchMeow", action: #selector(openIsland), keyEquivalent: "")
```

and replace it with:

```swift
        menu.addItem(withTitle: "Open NotchMeow", action: #selector(openIsland), keyEquivalent: "")
        // The desktop cat (sub-project H): "Cat on the desktop" while it is home, "Bring the cat home" while it is out (`menuNeedsUpdate`).
        let desktopItem = NSMenuItem(title: "Cat on the desktop", action: #selector(toggleDesktopCat), keyEquivalent: "")
        desktopItem.tag = Self.desktopItemTag
        menu.addItem(desktopItem)
```

**Edit `NotchBuddy/Sources/App/AppDelegate.swift`**, find this text (it occurs exactly once):

```swift
        statusItem?.menu = menu
    }
```

and replace it with:

```swift
        menu.delegate = self
        statusItem?.menu = menu
    }

    private static let desktopItemTag = 4207

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: Self.desktopItemTag)?.title = desktopCat?.isOut == true ? "Bring the cat home" : "Cat on the desktop"
    }

    @objc private func toggleDesktopCat() { desktopCat?.toggle() }
```

The cat's right-click menu now shows the shortcut's line.

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**, find this text (it occurs exactly once):

```swift
        let shortcut: String? = nil
```

and replace it with:

```swift
        let shortcut = ShortcutLogic.isEnabled(.desktop) ? ShortcutLogic.displayString(for: ShortcutLogic.hotKey(for: .desktop)) : nil
```

- [ ] **Step 3: Run the tests and the build**

Run: `bash scripts/test-shortcuts.sh 2>&1 | tail -1; bash scripts/test-hotkeys.sh 2>&1 | tail -1; bash scripts/test-cat-desktop-wiring.sh 2>&1 | tail -1`
Expected: `Shortcuts: 508 cases passed` (Task 0 read 496: the new action adds its own checks to every loop over the actions), `HotKeyCenter: 19 cases passed` (the same count, with nine actions registered) and `All tests passed.` Every combination in the defaults table stays unique and usable (`ShortcutLogic.duplicates(in: defaults).isEmpty`): ⌃⌥D is the only new one.

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. Do not open the app.

- [ ] **Step 4: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and h-mac/desktop-cat: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/h-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(cat): the desktop cat's menu-bar item and the desktop shortcut, ⌃⌥D

The shortcut action desktop (appended last, on by default, in the App Store build too), the menu-bar item "Cat on the desktop" that becomes "Bring the cat home" while it is out, and the shortcut's line in the cat's menu; the shortcut tests count the sixth default-on action.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/ShortcutLogic.swift NotchBuddy/Sources/App/IslandWindowController.swift NotchBuddy/Sources/App/AppDelegate.swift NotchBuddy/Sources/App/DesktopCatController.swift tests/ShortcutTests.swift tests/HotKeyCenterTests.swift tests/DesktopCatWiringTests.swift
git commit -F "$MSG"
git status --short   # nothing of this task is left over
```


---

### Task 13: Docs, CI and the final checks (step 8)

**Agent:** `nm-implementer-light` (Haiku 5.5, medium). Everything is given in full: the docs, one CI step for each new script, and the checks.

**Files:**
- Modify: `CLAUDE.md`, `ARCHITECT.md`, `README.md`, `docs/SPEC.md` (in French), `.github/workflows/build.yml`

- [ ] **Step 1: The docs**

`docs/SPEC.md` is in French. §8 said a drag dropped elsewhere than on a window goes back into the notch (that was the old behaviour); it now places the cat, and a new subsection, "Le chat de bureau", says what the cat does, what it stores and how the frame rate works. §13.1's table and sentences gain the `desktop` action (six shortcuts are on at first).

**Edit `docs/SPEC.md`**, find this text (it occurs exactly once):

```markdown
- **Glisser** le bonhomme (> 7 pt) : un bonhomme flottant Ø 54 suit le curseur (Surpris + `pop`), celui du notch disparaît. Lâché sur une fenêtre d'une autre app → **attache** (voir INTEGRATIONS §4). Lâché ailleurs → revient dans le notch en 420 ms en rétrécissant.
```

and replace it with:

```markdown
- **Glisser** le bonhomme (> 7 pt) : un bonhomme flottant Ø 54 suit le curseur (Surpris + `pop`), celui du notch disparaît. Lâché sur une fenêtre d'une autre app → **attache** (voir INTEGRATIONS §4, pas dans le build App Store). Lâché sur le bureau, sur aucune fenêtre → le chat **reste sur le bureau** (voir « Le chat de bureau » ci-dessous). Lâché sur l'île elle-même, ou sur une fenêtre qui n'a pas pu être attachée → rien ne se passe et le chat reste dans le notch.
```

**Edit `docs/SPEC.md`**, find this text (it occurs exactly once):

```markdown
- Plusieurs fichiers : même flux, libellé « 3 fichiers ».
```

and replace it with:

```markdown
- Plusieurs fichiers : même flux, libellé « 3 fichiers ».

### Le chat de bureau

Le gros chat peut quitter le notch et vivre sur le bureau (sous-projet H ; le contrat : `docs/CAT-CONTRACT.md`, « The desktop cat (H-0) »). Même rôle que dans le notch : One cat, le Main cat ; A cat for each agent, le chat de l'agent en focus ; Two cats, le chat 1 (le chat 2 reste dans le notch). Sa place dans le notch est **vide** tant qu'il est dehors, ses chatons et sa zone de clic aussi : jamais deux copies d'un même chat.

- **Sortir** : glisser le gros chat hors du notch et le lâcher sur le bureau (§8), ou l'élément « Cat on the desktop » de la barre de menus, **⌃⌥D** (activé par défaut, dans le build App Store aussi), ou l'interrupteur Réglages → Cat → Desktop. Le chat vole jusqu'à sa dernière place (arc de 0,6 s, taille pleine) ; la première fois, un peu sous le notch, à droite du centre.
- **Rentrer** : double-clic, « Send home » dans son menu, le même élément de la barre de menus (« Bring the cat home »), ⌃⌥D, l'interrupteur, ou le lâcher sur l'île.
- **Alertes** : quand une approbation ou une question arrive (`pendingApproval`, `pendingQuestion`), le chat fait l'émote Surpris puis vole jusqu'à sa place du notch ; quand les deux sont réglées, il retourne à sa place. Une alerte qui arrive pendant qu'il est dans le notch ne le sort pas. Une alerte réglée en plein vol le fait faire demi-tour sans saut.
- **Fenêtre** : un `NSPanel` sans bordure qui ne prend jamais le focus (`.nonactivatingPanel`, jamais key), au niveau `.floating`, sur tous les Spaces (`.canJoinAllSpaces`), hors du cycle des fenêtres, **sans** `.fullScreenAuxiliary` : il s'efface devant une app plein écran. Les clics traversent partout sauf sur le corps du chat (cercle de la tête, pastille d'état, chatons). Un clic ouvre l'île (après un délai de double-clic) avec une émote Content ; un double-clic le renvoie ; le glisser le déplace (la place est ramenée dans la zone visible, à 24 pt du bord de la tête, et enregistrée par disposition d'écrans) ; le menu du clic droit : Open the notch, Send home, Size ▸ Small, Medium, Large, et la ligne du raccourci.
- **Ce qu'il montre** : le chat complet (moustaches, rayures, fourrure si activée, yeux réalistes), la pastille d'état de son rôle, les chatons de son agent (3 puis « +N », à droite, ou à gauche quand le chat est dans la moitié droite de l'écran), le collier à la couleur de l'agent, il regarde le curseur, danse sur Apple Music (pas dans le build App Store) et s'endort après dix minutes comme le chat du notch. Tailles : Ø 48, Ø 64 (défaut) et Ø 96.
- **Fréquence** (`DesktopCatTrip.fps`) : 60 images/s en mouvement (vol, glisser, émote, chaton qui arrive ou part, danse), 20 si un agent travaille ou si le curseur est à moins de 150 pt, 5 au repos, 0,5 endormi, 0 quand le chat est chez lui, quand l'écran est éteint ou verrouillé, ou quand une app plein écran le couvre. Un seul minuteur (`DesktopCatPacer`), remplacé seulement quand la cible change, et des moniteurs de souris qui n'existent que tant que le chat est dehors et visible. `scripts/render-cats.sh --bench-desktop` mesure le coût : moins de 1 % d'un cœur au repos.
- **Stockage** : `cat.desktop.on` (Bool), `cat.desktop.size` (`small`, `medium`, `large`) et `cat.desktop.spots` (JSON : disposition d'écrans → place), nettoyés par `DesktopCatSettings.clean` (`cleanDesktopSettings`). Une place dont l'écran a disparu retourne à la place par défaut de l'écran principal.
```

**Edit `docs/SPEC.md`**, find this text (it occurs exactly once):

```markdown

- Cinq raccourcis sont activés au départ (`goToAlert`, `attachFrontWindow`, `nextPill`, `prevPill`, `muteToggle`) ; `toggleIsland` (comme avant), `openChat` et `jumpToTerminal` sont désactivés mais gardent leur combinaison, pour qu'un clic les active (décision du propriétaire, 2026-10-05). Réglages → Shortcuts dit pourquoi sous la ligne tant qu'elle est désactivée (`ShortcutAction.offAtFirstNote`). « Reset to defaults » revient à cet état.
```

and replace it with:

```markdown
| Chat sur le bureau (`desktop`) | ⌃⌥D | `shortcut.desktop.…` | Activé (build App Store inclus) |

- Six raccourcis sont activés au départ (`goToAlert`, `attachFrontWindow`, `nextPill`, `prevPill`, `muteToggle`, `desktop`) ; `toggleIsland` (comme avant), `openChat` et `jumpToTerminal` sont désactivés mais gardent leur combinaison, pour qu'un clic les active (décision du propriétaire, 2026-10-05). Réglages → Shortcuts dit pourquoi sous la ligne tant qu'elle est désactivée (`ShortcutAction.offAtFirstNote`). « Reset to defaults » revient à cet état.
```

**Edit `docs/SPEC.md`**, find this text (it occurs exactly once):

```markdown
- `muteToggle` coupe ou rétablit les sons (son `tick` et émote).
```

and replace it with:

```markdown
- `muteToggle` coupe ou rétablit les sons (son `tick` et émote).
- `desktop` sort le gros chat sur le bureau, ou le ramène dans le notch (comme l'élément de la barre de menus et l'interrupteur de Réglages → Cat). L'ID de l'action est un contrat gelé, comme les IDs de chats.
```

**Edit `CLAUDE.md`**, find this text (it occurs exactly once):

```markdown
- Sub-project B on the Mac: `CatSmallEye.swift` (the coloured small eyes, drawn in `CatFace.drawEyes`: the black coats' Midnight, Oreo and Mocha are flat, rimless and glowing, picked by the coat's ID; `CatLook.inkEyes` keeps the old ink ones for the contact sheet and the icons), `CatDisplay.swift` (the display mode, the pair and the agents' coats: the keys `cat.displayMode`, `cat.pair` and `cat.agentCat.<pillId>`), `CatAgentCats.swift` (a new agent's cat), `CatCast.swift` (which cat appears where: `AppState.cast`), `CatIslandLayout.swift` (every layout number of Two cats mode and the kitten boxes), `PairCatViews.swift` (cat 2), `CatKittens.swift` (the kittens' rules), `CatKittenHooks.swift` (the hooks' words: `SubagentStart` and the events that carry an `agent_id`), `CatKittenDraw.swift` and `KittenViews.swift` (drawing them), and `CatDisplayPreview.swift` and `CatAgentList.swift` (Settings → Cat → Display). **Each cat view takes its coat as a parameter from `AppState.cast`; nothing reads the Main cat on its own, and a kitten is never given `useCharacter`.** The tests are `scripts/test-cat-{small-eye,display,agent-cats,cast,agent-list,kittens,kitten-hooks,wiring}.sh` (`test-cat-wiring.sh` pins where the app files that no test program can compile call the pure parts); `render-cats.sh --eyes`, `--island` and `--kittens` and `render-cat-settings.sh --mode …` draw the checkpoint images without the app; `scripts/fake-subagent-events.py` sends scripted subagent events to a running build and is only for the owner's check.
```

and replace it with:

```markdown
- Sub-project B on the Mac: `CatSmallEye.swift` (the coloured small eyes, drawn in `CatFace.drawEyes`: the black coats' Midnight, Oreo and Mocha are flat, rimless and glowing, picked by the coat's ID; `CatLook.inkEyes` keeps the old ink ones for the contact sheet and the icons), `CatDisplay.swift` (the display mode, the pair and the agents' coats: the keys `cat.displayMode`, `cat.pair` and `cat.agentCat.<pillId>`), `CatAgentCats.swift` (a new agent's cat), `CatCast.swift` (which cat appears where: `AppState.cast`), `CatIslandLayout.swift` (every layout number of Two cats mode and the kitten boxes), `PairCatViews.swift` (cat 2), `CatKittens.swift` (the kittens' rules), `CatKittenHooks.swift` (the hooks' words: `SubagentStart` and the events that carry an `agent_id`), `CatKittenDraw.swift` and `KittenViews.swift` (drawing them), and `CatDisplayPreview.swift` and `CatAgentList.swift` (Settings → Cat → Display). **Each cat view takes its coat as a parameter from `AppState.cast`; nothing reads the Main cat on its own, and a kitten is never given `useCharacter`.** The tests are `scripts/test-cat-{small-eye,display,agent-cats,cast,agent-list,kittens,kitten-hooks,wiring}.sh` (`test-cat-wiring.sh` pins where the app files that no test program can compile call the pure parts); `render-cats.sh --eyes`, `--island` and `--kittens` and `render-cat-settings.sh --mode …` draw the checkpoint images without the app; `scripts/fake-subagent-events.py` sends scripted subagent events to a running build and is only for the owner's check.
- Sub-project H on the Mac (the desktop cat): the pure rules are `DesktopCatSpots.swift` (screens, `screenKey`, `clampSpot`, `spotFor`), `DesktopCatSettings.swift` (the keys `cat.desktop.on`, `cat.desktop.size` and `cat.desktop.spots`, cleaned by `DesktopCatSettings.clean`), `DesktopCatTrip.swift` (`desktopStep`, the flight and its clock, `desktopFps`, the kittens' slots), `DesktopCatLayout.swift` (the window around the cat and its body shape), `DesktopCatInput.swift` (click, double-click and drag, the right-click menu), `DesktopCatDrop.swift` (a window attaches, empty desktop places the cat) and `DesktopCatPacer.swift` (the one timer); the app's side is `DesktopCatController.swift` (the trip, the frame timer, the mouse), `DesktopCatPanel.swift` (a non-activating floating panel that is never key, on every Space, outside fullscreen), `DesktopCatDraw.swift` (one function draws it, in the app and on the sheets) and `DesktopCatScreensApp.swift`. **It is in Debug, Release and App Store builds** (`check-app-binary.sh` looks for `NM_DESKTOP_CAT_PANEL`), and the notch's big-cat spot, its kittens and its hit area are empty while the cat is out (`AppState.desktopPhase`). The shortcut action ID `desktop` (⌃⌥D, on by default) is frozen like the size IDs. The tests are `scripts/test-cat-desktop-{settings,trip,layout,input,drop,pacer,wiring,devpanel}.sh`; `render-cats.sh --desktop [--shapes]`, `--desktop-flight` and `--bench-desktop` draw and measure it without the app, and the Debug-only "Cats (Debug)…" panel has a live Desktop section (`DesktopCatDevPanel.swift`, marker `NM_CAT_DEV_DESKTOP`, compiled out of Release and App Store).
```

**Edit `ARCHITECT.md`**, find this text (it occurs exactly once):

```markdown
   - **Sub-project H (the desktop cat):** its contract is in `design/prototype/cat-core.js` and `tests/fixtures/cat/desktop-cases.json` (new names only; the prototype's Desktop panel draws it): the trip `desktopStep` (seven phases) with `desktopFlightAt`, `desktopFps`, `screenKey`, `clampSpot` and `spotFor`, `cleanDesktopSettings` and `desktopKittenSlots`; see `docs/CAT-CONTRACT.md`, "The desktop cat (H-0)". The two H app plans build on it.
```

and replace it with:

```markdown
   - **Sub-project H (the desktop cat):** its contract is in `design/prototype/cat-core.js` and `tests/fixtures/cat/desktop-cases.json` (new names only; the prototype's Desktop panel draws it): the trip `desktopStep` (seven phases) with `desktopFlightAt`, `desktopFps`, `screenKey`, `clampSpot` and `spotFor`, `cleanDesktopSettings` and `desktopKittenSlots`; see `docs/CAT-CONTRACT.md`, "The desktop cat (H-0)". The two H app plans build on it. **On the Mac** the cat is `DesktopCatController` (the trip, one timer at `DesktopCatTrip.fps`'s rate, the mouse) in a non-activating floating `DesktopCatPanel`; `AppState.desktopPhase` empties the notch's big-cat spot while it is out; a drag of the big cat ends in `DesktopCatDrop` (a window attaches, empty desktop places the cat); ⌃⌥D, the menu-bar item and Settings → Cat → Desktop all end in the store's `cat.desktop.on`, which the controller follows.
```

**Edit `README.md`**, find this text (it occurs exactly once):

```markdown
| D | Signed releases and the website | planned |
```

and replace it with:

```markdown
| D | Signed releases and the website | planned |
| H | A desktop cat: drag the big cat out of the notch and keep it on the desktop | built on macOS (Windows and Linux: its own plan); real-build checks pending |
```

One CI step for each new script, before the theme check.

**Edit `.github/workflows/build.yml`**, find this text (it occurs exactly once):

```yaml

      - name: Cat theme (no hard-coded theme colours in the drawing code)
```

and replace it with:

```yaml

      - name: Desktop cat settings (screens, spots and the stored block against desktop-cases.json)
        run: bash scripts/test-cat-desktop-settings.sh

      - name: Desktop cat trip (desktopStep, the flight, the frame rate and the kittens' slots)
        run: bash scripts/test-cat-desktop-trip.sh

      - name: Desktop cat layout (the window, the side and the body that takes the mouse)
        run: bash scripts/test-cat-desktop-layout.sh

      - name: Desktop cat input (click, double-click, drag and the menu)
        run: bash scripts/test-cat-desktop-input.sh

      - name: Desktop cat drop (attach as before, or place the cat)
        run: bash scripts/test-cat-desktop-drop.sh

      - name: Desktop cat pacer (one timer, re-armed only when the target changes)
        run: bash scripts/test-cat-desktop-pacer.sh

      - name: Desktop cat wiring (source pins of the app files)
        run: bash scripts/test-cat-desktop-wiring.sh

      - name: Desktop cat dev panel (the Debug-only Desktop section's model: the alert flight on a mock desktop)
        run: bash scripts/test-cat-desktop-devpanel.sh

      - name: Cat theme (no hard-coded theme colours in the drawing code)
```

- [ ] **Step 2: The final checks**

The contract is untouched, the fixtures still only grew, and nothing of the owner's files outside the Mac moved.

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|fixture files match|identical bytes"; node scripts/check-fixtures-additive.mjs 1627851 2>&1 | tail -1`
Expected: `# tests 284`, `# pass 284`, `# fail 0`, `✓ 15 fixture files match cat-core.js`, `✓ two generator runs write identical bytes` and `✓ fixtures changed only by addition since 1627851`.

```bash
git diff notchmeow/rebrand...HEAD --stat -- design tests/fixtures shared windows | tail -1; echo "outside the Mac: $(git diff notchmeow/rebrand...HEAD --name-only -- design tests/fixtures shared windows | wc -l | tr -d " ") files"
```

Expected: `outside the Mac: 0 files` (this plan never edits `cat-core.js`, a fixture, `shared/`, a generated theme file or `windows/`).

```bash
for f in scripts/test-cat-*.sh; do printf '%-42s' "$f"; bash "$f" 2>&1 | tail -1; done
```

Expected: thirty-three lines: the contract's ends `✓ two generator runs write identical bytes` and the other thirty-two (twenty-four of A and B, eight of H) end `All tests passed.`

Run: `bash scripts/test-shortcuts.sh 2>&1 | tail -1; bash scripts/test-hotkeys.sh 2>&1 | tail -1; bash scripts/check-no-leftovers.sh 2>&1 | tail -1`
Expected: `Shortcuts: 508 cases passed`, `HotKeyCenter: 19 cases passed` and the last line of the leftovers guard (`✓ no notification that nothing posts or observes`; five `✓` lines in all).

Run: `RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench 2>&1 | tail -1; RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench-desktop 2>&1 | tail -1`
Expected: the notch's own bench, next to Task 0's (it must not have moved by more than the machine's noise: nothing here touches the notch's drawing), and `ok: idle and awake is under 1 % of a core at every size`.

- [ ] **Step 3: The three builds and the three binary checks**

The Release and App Store builds are what proves the marker is in all three builds: the desktop cat ships in each. The same script also proves the Debug panel's Desktop section (`NM_CAT_DEV_DESKTOP`) is in the Debug build and in neither of the other two (it fails the build check otherwise). (The first draft's marker, `NM_DESKTOP_CAT`, was 14 bytes: Swift keeps a string of 15 bytes or less inside the code, so `strings` could not see it in the Release binary. `NM_DESKTOP_CAT_PANEL` is longer on purpose.)

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath NotchBuddy/build/release build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

```bash
bash scripts/check-app-binary.sh NotchBuddy/build/release/Build/Products/Release/NotchMeow.app release
bash scripts/check-app-binary.sh NotchBuddy/build/store/Build/Products/Debug/NotchMeow.app appstore
bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Debug/NotchMeow.app debug
```

Expected: ten lines in all, in this order. Release: `✓ The desktop cat is in this build`, `✓ No cat panel and no Claude Code override in this build; the Claude Code engine is in it`, `✓ FoundationModels is weak-linked` and `✓ No AI base-URL override in this Release build`. App Store: `✓ The desktop cat is in this build`, `✓ No cat panel and no Claude Code engine in this build` and `✓ FoundationModels is weak-linked`. Debug: `✓ The desktop cat is in this build`, `✓ The cat panel, the Claude Code engine and its override are in this Debug build` and `✓ FoundationModels is weak-linked`. (A SDK without FoundationModels prints `· FoundationModels not linked …` instead; the build machine's Xcode decides.)

- [ ] **Step 4: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and h-mac/desktop-cat: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/h-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
docs(cat): the desktop cat on the Mac: the spec, the guides, the roadmap and CI

docs/SPEC.md (in French): the drag, "Le chat de bureau" and the desktop shortcut; CLAUDE.md, ARCHITECT.md and the README's roadmap row; one CI step for each new test script.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add CLAUDE.md ARCHITECT.md README.md docs/SPEC.md .github/workflows/build.yml
git commit -F "$MSG"
git status --short   # nothing of this task is left over
```


**After Task 13:** dispatch `nm-reviewer-deep` (Sonnet 5.5, high) over `git diff notchmeow/rebrand...HEAD`, with the plan, the spec, H-0's contract section and the Review Focus; fix what it finds (each fix with the agent that wrote the code, then a scoped `nm-reviewer` re-review), and stop for checkpoint 3.

---

### Task 14: Owner checkpoint 3: sign-off, then the owner's real-build checks

No code. The session reports the final state (the commits, the test lines, the three builds and binary checks, the bench lines, the review's verdict), and the main session asks for the owner's sign-off. Then the owner checks a real build, which no test of this plan can do (spec §4, step 3):

1. **Drag out and home.** Drag the big cat out of the notch and drop it on empty desktop: it stays there, and the notch's spot is empty (no second cat, no kittens, no glow). Drop it on another app's window instead: the window is attached to a chat, as before. Double-click it: it flies home. Drop it on the notch: it flies home. Quit and start the app with the cat out: after the greeting it flies out again; quit mid-flight home: it is home at the next start.
2. **An alert's flight and return.** With the cat out, make Claude Code ask for a permission: the cat gives the surprised emote and flies into the notch, the island opens, and the cat sits there while you answer; answer, and it flies back to its spot. Answer while it is still flying in: it turns round with no jump. Send it home during an alert: it ends at home.
3. **Spaces and fullscreen.** Switch Spaces: the cat is on every one. Open a fullscreen app: the cat steps aside (it is not drawn there) and is back when you leave.
4. **Two monitors.** Put the cat on the external monitor, unplug it: the cat is on the laptop's default spot. Plug it back in: it returns to its spot there. (The spots are per arrangement.) Check a drop on the monitor with the notch screen not the main one, if you have such a setup: the attach's window lookup flips around the island's screen, as it always did (Open question 12).
5. **Click-through.** Click an app's button right next to the cat, and through the window's transparent corners: the app gets the click. Click the cat's body: it opens the island with a happy reaction. Drag it by its head, by the badge and by a kitten: all move it.
6. **Sleep, wake, lock and unlock.** Lock the screen with the cat out and awake, wait a minute, unlock: the cat is drawn again and nothing ran meanwhile (Activity Monitor). Leave the cat ten minutes with no agent event: it sleeps; hover it, or click it: it wakes (zoomies in Playful). Sleep the Mac and wake it: the cat is drawn again.
7. **CPU.** In Activity Monitor with the cat out and idle: under 1 % of a core, and about 0 % with the cat asleep, at home, in the notch for an alert or while the screen is locked. With music playing and Apple Music's integration on, the cat dances.
8. **⌃⌥D, the menu-bar item and the switch.** Each takes the cat out and brings it home, and the switch, the menu-bar item's title and the cat's right-click menu agree. The App Store build has all three, and no attach.
9. **Size, and what a restart keeps.** Small, Medium and Large from the cat's menu; quit and start the app: the cat is out or home as you left it, at the same **size** and the same **spot**, and with a different screen arrangement it keeps a spot of its own for each (the spots are per arrangement).

---

## Parity with Windows/Linux

**macOS is the primary platform: it gets at least what Windows and Linux gets.** The two plans build the same eight steps from the same contract (`cat-core.js` and `desktop-cases.json`), and the main session reads them together. This section was written from the spec, because the Windows and Linux plan (`docs/superpowers/plans/2026-10-12-h-tauri-desktop-cat.md`) was drafted at the same time; the main session checks it against that plan line by line before either runs.

| Topic | macOS (this plan) | Windows and Linux (the twin, from the spec) |
|---|---|---|
| The rules | `DesktopCatTrip` (all 89 `steps` rows, the 11 `trips`, the flights, the 39 `fpsCases`, the kittens' slots), `DesktopCatSpots` and `DesktopCatSettings` replay `desktop-cases.json` from `swiftc` programs. | A TypeScript and a Rust port of the same rules, replayed by `npm run check:cat` and the Rust tests. |
| The window | A borderless, non-activating floating `NSPanel` that is never key, on every Space, outside fullscreen, click-through that follows the body (mouse-moved monitors, only while out and visible). | Windows: a second transparent, always-on-top Tauri window skipped in the taskbar, taking the mouse over the body with the island's mechanism. Linux: an overlay-layer surface where layer-shell exists, a small always-on-top window on GNOME (which may ignore the position; Settings says so). |
| Cursor | The cat looks wherever the cursor is, from the mouse-moved monitors. | Windows the same; Wayland gives the cursor only over the app's own surface, so on Linux it looks ahead unless the cursor is over the cat. |
| Frame rate | One `DispatchSourceTimer` at `desktopFps`'s rate, re-armed only on a change; `render-cats.sh --bench-desktop` is the bench. | The `?dev` page measures each rate. |
| Controls | Menu-bar item, Settings → Cat → Desktop, **⌃⌥D** (on by default, in the App Store build too, a frozen action ID). | The tray menu item and the Settings switch; **no global shortcut** (out of scope for Windows and Linux). |
| What travels | Coat, motion, personality, eyes, cursor-watching, state badge, kittens, collar, **the Apple Music dance** (not in the App Store build) and sleep with B's sweep. | The same, **except the music dance on Linux** and the dance's source (the Mac plays from Apple Music). |
| The drop | A window attaches (GitHub build only), a drop on no window places the cat; the App Store build has no attach, so any drop places it. | No attach on Windows and Linux: any drop places the cat. |
| Storage | `cat.desktop.on`, `.size`, `.spots` in UserDefaults, cleaned by `DesktopCatSettings.clean`. | The `desktop` object of the `cat` block of `settings.json`, cleaned by `cleanDesktopSettings`'s port; Rust's `sanitized` keeps it. |
| Tests | Eight `scripts/test-cat-desktop-*.sh` programs, `render-cats.sh --desktop`, `--desktop-flight`, `--bench-desktop`, and the Debug panel's live Desktop section. | The Vite dev server with a headless browser, and Rust tests. |

**Where the Mac has more:** ⌃⌥D, the music dance, the mouse watched everywhere, the attach that still works, one shared drawing function for the app and the sheets. **Where the Mac plan chose something the spec leaves open and the twin should match** (the main session carries each across): the window's numbers and the body's shape (`DesktopCatLayout`: the hearts' room, the head circle at `0.55 D`, the badge and kitten circles), the kittens' side (left in the right half of the screen's visible frame), `place` clamping and saving the spot, a drop on the island doing nothing, a cat in the air not being pickable, and the Settings group's wording (the surprised beat, the drag threshold, the emote's and the kittens' motion times and the alert triggers are now shared values: see "Parity rulings" below).

## Open questions for the owner

Each has the answer this plan assumes, so nothing blocks. A different answer changes one small thing, named in each.

1. **The desktop cat ships in the App Store build, and so does ⌃⌥D.** The spec's Mac section says "It's in Debug, Release and App Store builds; `check-app-binary.sh` keeps passing" and lists ⌃⌥D "on the Mac". The spec is silent on the App Store's drag: this plan says that there, with no attach, **any drop that is not on the island places the cat, even over another app's window**. **Assumed: yes.** Changing it is one flag (`DesktopCatController.isAppStoreBuild` into `DesktopCatDrop`).
2. **A drop places the cat at its clamped spot and remembers it.** H-0's `place` act says "show the cat at `event.spot`"; the plan clamps it (24 pt from the head's edge, off the menu bar and the Dock) and saves it with `rememberSpot`, as `move` does. **Assumed: yes.**
3. **A drop of the big cat on the island, on a window that could not be attached, or beside every screen:** on the island and on an unattachable window nothing happens and the cat stays in the notch (as the attach did, today); a drop beside every screen goes to the default spot. **Assumed: yes.**
4. **The window and the body's shape** (all in `DesktopCatLayout`, one place): the canvas `D / 0.6`, hearts' room `D * 40 / 58`, the body the head circle `0.55 D`, the badge circle (centre `(0.7 D, -0.46 D)`, radius `0.2 D`) and the kittens' circles and label. Judged on `desktop-shapes.png` at checkpoint 1. **Assumed: as drawn.**
5. **Motion that counts for 60 fps:** an emote for **1.8 s** from the moment the app starts it (the longest emote of `EMOUTH`, love and proud; the engine does not say when an emote ends), the kittens for **600 ms after any change to the kitten list** (`KITTEN_LEAVE_MS`: an arrival or a leave, watched by `DesktopKittenWatch`), and the drag. **Assumed: yes** (the owner's parity ruling). One constant each (`emoteMs`, `DesktopKittenWatch.motionMs`).
6. **The idle rate uses a held `dt` of 0.25 s, not the island's 0.05 s** (`maxDt: 0.25`): a cat that draws at 5 fps must still live in real time. The slow breath asleep is one frame every 2 s with that `dt`. **Assumed: yes.**
7. **The frame cost.** Ø96 working with three kittens costs about 3 ms a frame (6 % of a core at 20 fps) and a flight at Ø96 about 19 % for 0.6 s. The spec's "under 1 % idle and awake" is held (0.61 % at Ø96) and measured **without kittens** (they exist only while their agent works, which is 20 fps); 5 fps **with** three kittens is reported next to it (1.41 % at Ø96, not held, as on Windows and Linux) and the busy rates after it. **Assumed: OK.** The alternative, if the owner wants the busy rate lower, is a lower `active` rate in `cat-core.js`, the fixture and both apps (a contract change), or a cached kitten layer.
8. **The launch greeting.** A cat that was out flies out once the island's view is no longer `.greeting` and the greeting's tail is over (`state.$view` and `$greetingTail`). **Assumed: yes**; the owner checks it on a real build (Task 14, check 1).
9. **The menu-bar item's wording:** "Cat on the desktop" while it is home and "Bring the cat home" while it is out (the spec's words), switched by `menuNeedsUpdate`. **Assumed: yes.**
10. **The Settings switch is its own group, "Desktop", under Display** and not a row inside the Display group (no existing group changes); the size is picked in the cat's own menu, as the spec says. **Assumed: yes.**
11. **A cat in the air cannot be picked up:** a drag that starts while it flies is ignored (a click in the air still acts). **Assumed: yes.**
12. **Two monitors and the attach.** The island's attach looks windows up by flipping around the island's own screen (`window?.screen`), which is right when the notch screen is the main one and was always so. The desktop cat's own drop uses the contract's conversion (the main screen's height), and `windowBoundsAtScreenPoint` is the existing function. On a Mac whose notch screen is not the main screen the two disagree, and the owner's two-monitor check looks at it. **Assumed: OK;** fixing the attach's lookup is outside this plan (it would change what ships).
13. **`render-cat-settings.sh` did not compile at the base** (it never listed `CatKittens.swift`); Task 2 adds it. **Assumed: yes.**
14. **The marker `NM_DESKTOP_CAT_PANEL`** is 20 bytes on purpose (a 14-byte string is invisible to `strings` in a Release build). **Assumed: keep.**
15. **The README's roadmap row for H** is edited by this plan only (the Windows plan leaves the root `README.md` alone); the main session sets its final status when both plans have landed. **Assumed: yes.**
16. **Helpers beyond H-0's list:** `DesktopCatLayout`, `DesktopCatInput` (`DesktopCatClicks`, `DesktopCatMenu`), `DesktopCatDrop`, `DesktopCatPacer`, `DesktopCatVisibility`, `DesktopCatTrip.Flight` and `alert`, `DesktopKittenWatch`, `DesktopCatDraw`, and the Debug panel's `DesktopCatDevModel`. Each is small and each stops two files reading a rule two ways. **Assumed: keep.**

17. **Alert triggers** (the owner's parity ruling): an approval, a question, **a chat's approval card** (`AppState.chatApproval`, the GitHub build only: the App Store build has no chat engine) and **any pill in the approval or question state** all take the cat into the notch. A pill that stays in the approval state for a long time therefore keeps the cat in the notch. **Assumed: yes.**
18. **Shared values** (the owner's parity ruling): the surprised beat is 450 ms, a drag starts past 4 pt, an emote counts as motion for 1.8 s and the kittens for 600 ms after any change to their list. Each is one constant (`surpriseMs`, `DesktopCatClicks.dragThreshold`, `emoteMs`, `DesktopKittenWatch.motionMs`). **Assumed: yes.**

## Self-review

- **Spec coverage.** §1: the seven phases and the machine (Task 3), the drag out and the drop rule (Tasks 4 and 5), the menu-bar item, ⌃⌥D and the switch (Tasks 8 and 12), bringing it home by every route (Tasks 5, 8 and 12), alerts (Task 6), the flight and its clock (Tasks 3 and 5), what is remembered (Tasks 1, 2 and 5: on, size, spot per arrangement, `clampSpot`, the launch). §2: what it shows (Task 7: badge, kittens, collar, eyes, cursor, dance, sleep), the sizes and the window's size (Tasks 4 and 5), clicks and the menu (Tasks 4 and 5), hit-testing (Tasks 4 and 5), and nothing of files, slap or hairball (the island's drop view and slap never see it). §3: the rate (Tasks 3 and 10), one timer and monitors only while out (Task 10), the panel's flags (Task 5), all three builds (Task 5, 13), storage (Tasks 1 and 2), frozen IDs (Tasks 1 and 12), controls (Tasks 8 and 12). §4: the order and the three checkpoints (Tasks 9, 11 and 14), the owner's real-build list (Task 14). Out of scope and not built: two cats on the desktop, a walking cat, the wardrobe, file drops on the cat, global shortcuts on Windows and Linux, the trip's sounds.
- **Placeholders.** None: every code step is a **Create** or **Edit** block generated from the files the dry run ran, and every `Run:` line has its expected output.
- **Type consistency.** `DesktopSpot`, `DesktopScreen`, `DesktopSize` (Task 1) are what `DesktopCatSettings` (Task 1), the store (Task 2), the trip (Task 3), the layout, the drop rule (Task 4) and the controller (Task 5) use; `DesktopPhase`, `DesktopEvent`, `DesktopAct` and `Flight` (Task 3) are what the controller sends and carries out; `CatKittens.Slots` (B) is what `kittenSlots` returns, `DesktopCatLayout.frame` sizes the window by and `DesktopCatDraw` draws; `DesktopCatPacer.Action` (Task 4) is what `arm(_:)` (Task 5) acts on.
- **Review Focus.** Lines 1 to 6 each have their tests, named in the line.
- **What this plan deliberately does not do:** touch `cat-core.js`, a fixture of `tests/fixtures/cat/` or anything under `windows/`; launch the app; give the desktop cat a sound, a slap or a hairball; let it take a file; change any shipping view but the empty spot; store a kitten.


---

## Parity rulings (2026-10-12)

A parity check against the Windows and Linux plan (`docs/superpowers/plans/2026-10-12-h-tauri-desktop-cat.md`) found gaps. The coordinator ruled on each; this plan carries them, and the code, the tests, the Expected lines, the parity section and the open questions above already say so.

**Values both plans now share:**

1. **The surprised beat before a flight is 450 ms** (was 250): `DesktopCatController.surpriseMs`; the Debug panel's mock uses the same.
2. **The double-click interval is `NSEvent.doubleClickInterval`;** a value that is not a usable number is 0.5 s (`DesktopCatClicks.init`, pinned by a test).
3. **A drag starts past 4 pt** (was 3): `DesktopCatClicks.dragThreshold`.
4. **An emote counts as motion for 1800 ms,** the longest emote of `EMOUTH` in `cat-core.js` (love and proud): `DesktopCatController.emoteMs`.
5. **A kitten counts as motion for 600 ms (`KITTEN_LEAVE_MS`) after any change to the kitten list,** an arrival or a leave, not only from birth: `DesktopKittenWatch` (Task 4, tested), asked once per frame by the controller.
6. **The hearts' room above the window stays `D * 40 / 58`;** the Windows and Linux plan adopts it.
7. **The bench reports two rows at S, M and L:** idle without kittens (held under 1 %) and 5 fps with three kittens (reported, not held), plus a third line with the rest. At Ø96 the second row is 1.41 % in the dry run.

**Gaps the Mac fills (it must have at least what Windows and Linux has):**

8. **Alert triggers** also cover a chat's approval card (`AppState.chatApproval`, behind `#if !APPSTORE`) and any pill whose state is `approval` or `question`, not only `pendingApproval` and `pendingQuestion`: `DesktopCatTrip.alert(…)` (Task 6, tested) and the sink in the controller, with two pins in the wiring test (Open question 17).
9. **A live Desktop section in the Debug-only "Cats (Debug)…" panel** (Task 10): `DesktopCatDevModel` and `DesktopCatDevView`, a mock desktop with the cat, a button that fires the alert flight, one that clears it, the size picker, the kittens and a live readout of the rate and the cost. Compiled out of Release and App Store; `check-app-binary.sh` proves the marker `NM_CAT_DEV_DESKTOP` is in Debug and in neither of the others; `scripts/test-cat-desktop-devpanel.sh` drives the model.
10. **The real-build checks** (Task 14) gain lock and unlock, and the spot and the size kept after a restart.

## Dry run (2026-10-12)

The plan was run before it was handed over: the pure files and every test of Tasks 1 to 4 were written and run in a throwaway clone while the plan was drafted, then the controller and the island's edits were built in it stage by stage, and **the finished file was replayed from the top in a fresh clone of `notchmeow/rebrand` at `99e3be1`, with nothing of H-0 to apply first**. Nothing was committed or pushed (in a clone or in the main checkout), no NotchMeow app was started, nothing was installed or downloaded, and no network was used. The only file this work added to the main checkout is this plan.

**Set-up.** `git clone --local --shared --branch notchmeow/rebrand` of this repository, in the session scratchpad, with `TMPDIR` pointing at an empty folder of its own. A clone has no `windows/node_modules` and no Docker; nothing here needs either. Task 0's base check passes on it (`git merge-base --is-ancestor 99e3be1 HEAD`), the contract reads `# tests 284`, and commit steps are not run in a clone, so its `git status` lists every earlier task's files.

**Method.** A small runner read the plan's structure in order, applied each **Create** block (30) and each **Edit** block (93; it fails when a find text occurs other than once), made the 8 scripts executable, ran every `Run:` line and fenced shell block that has a command to check (65) and compared every backticked literal of its `Expected:` line with the output. The 62 commands exited 0 and **0 literals were missing at the end** (about 30 minutes, most of it the test loops and the Debug, App Store and Release builds); the 13 commit steps were skipped; the plan was replayed twice, once before and once after the owner's parity rulings of the same day. Every fenced shell block and every `Run:` line also passes `bash -n` (62 fenced blocks and 48 Run lines). The replay's tree matched the working clone's byte for byte (`diff -rq` over `NotchBuddy/Sources`, `tests`, `scripts`, `docs`, `.github` and the four root docs).

| Task | What the run printed (the plan's Expected) |
|---|---|
| 0 | `H-0 (99e3be1) is in the base`; the three H-0 files; contract 284/284, 15 fixture files, fixtures additive; twenty-five test lines; `Shortcuts: 496`, `HotKeyCenter: 19`; the notch bench 1.84 ms; the Debug build |
| 1 | red: `error opening input file`; 48 checks pass; with `round` the Swift way, 3 fail; with the map keeping the old arrangement, 1 fails |
| 2 | red: compile error (no member `desktop`); the store's program passes; `render-cat-settings.sh` draws (after the `CatKittens.swift` fix); Debug build |
| 3 | red: `error opening input file`; 52 checks pass; with a turn that does not mirror its progress, 3 fail (a worst jump of 346.6 pt); with an alert that does not turn the cat, 2 fail |
| 4 | red: four missing-file errors; layout, input, drop and pacer pass; with a click that does not wait, and a drop that attaches in the App Store build, both programs fail |
| 5 | red: 25 pins fail; green; Debug build; `check-app-binary.sh … debug` prints the desktop cat's line; a fullscreen-auxiliary and key-able panel fails 2 pins |
| 6 | red: 2 pins; green, with the trip's program and its new `alert` section; the flight strip drawn (looked at: seven panels, the arc, the alert badge); Debug build |
| 7 | red: 1 pin; green; both desktop sheets drawn (looked at: four columns, kittens mirrored on the left, `+2` at Medium, the dashed window and the green body); Debug build |
| 8 | red: 2 pins; green; the Settings sheet drawn; Debug build; the store's program |
| 9 | the three images collected; thirty-two test lines (thirty-three from Task 10 on) |
| 10 | red: 4 pins and the dev panel's program (`error opening input file`); green; bench, idle without kittens Ø48 0.27 %, Ø64 0.37 %, Ø96 0.61 % of a core, 5 fps with three kittens 0.48, 0.60 and 1.40 %; the panel drawn with its Desktop group; Debug build; the Debug binary check |
| 11 | the flight strip and `bench.txt` collected |
| 12 | red: compile error (no member `desktop`); `Shortcuts: 508`, `HotKeyCenter: 19`, wiring green; Debug build |
| 13 | contract and fixtures; thirty-three test lines; `Shortcuts: 508`, `HotKeyCenter: 19`, leftovers guard (5 `✓`); notch bench 1.89 ms; the Release, App Store and Debug builds; ten `check-app-binary.sh` lines, each build's including `✓ The desktop cat is in this build` |

**What the dry run changed in the plan** (each was a defect in an earlier draft, found because a step failed, printed something else or drew something wrong, and is fixed in the text):

- **The Release binary did not hold the marker.** The first marker, `NM_DESKTOP_CAT`, is 14 bytes, and Swift keeps a string of 15 bytes or fewer inside the code, so `strings` found it in the Debug and App Store binaries and not in the Release one (`✗ the desktop cat … is missing from this build`). `NM_DESKTOP_CAT_PANEL` is 20 bytes (Open question 14), and Task 13's step explains why.
- **`render-cat-settings.sh` does not compile at the base** (`CatKittens.swift` is not in its list): found when Task 2's step first ran it, and fixed in Task 2.
- **The bench's first idle row was the wrong row.** Measured with three kittens drawn, Ø96 idle read 1.6 % of a core and failed the spec's 1 %. Kittens exist only while their agent works (20 fps), so the idle row is measured without them (0.62 to 0.65 %) and the working row, with kittens, is reported and not held (Open question 7).
- **The island's frame delta is wrong at 5 fps.** `CatEngine.frameDelta` holds `dt` to 0.05 s, so a cat drawn every 0.2 s would move four times too slowly; the controller passes `maxDt: 0.25` (Open question 6), and a pin keeps both call sites.
- **The shortcut tests pinned the old set.** `ShortcutTests` and `HotKeyCenterTests` count the five that are on at first, the four of the App Store build, "all eight" and seven F-keys: each moves with the sixth (Task 12 lists every edit), and `HotKeyCenterTests` needs an eighth combination (the ISO section key with all four modifiers).
- **The dev model failed in the app build and not in its own test.** `engine.setState(… ? .approval : .idle)` is ambiguous in the app (`CatState` and `BotState` both have the cases, and `CatEngine+App.swift` adds the second overload), though `swiftc` on the test's list sees one: the model writes `CatState.approval`, and its kittens `CatKittens.State.approval`. The dry run built the app to find it.
- **Swift 6 and the build.** `BotPlacement`'s old `body` became `@ViewBuilder private var catSpot` (an opaque `some View` property with local `let`s needs it); the event monitors' handlers are `MainActor.assumeIsolated` as the island's are; no warning comes from the new files.
- **Expected counts and text** were corrected to the real output: 48 `✓` lines for Task 1, the "N test(s) failed" counts of every bite step, the 25 pins that fail in Task 5's red run, 27 (not 22) pairs in the machine, `Shortcuts: 496` at the base against 508 after Task 12, and ten (not eleven) binary-check lines.

**Not run, and owed.**

- **Any commit step.** The 13 `git add` and `git commit` blocks were skipped and have to be run by the executing session in its worktree.
- **The app itself.** No NotchMeow window was opened, so the real panel (Spaces, a fullscreen app, click-through over a real app, the mouse monitors' reliability, `occlusionState` on a covered window, the greeting's hand-over, the flight into a real island, the hover that wakes a sleeping cat, the menu-bar item's title) and the CPU in Activity Monitor are the checkpoints' lists for the owner (Task 14), not something this run proved. The cat, its window, its body shape, the kittens, the flight and the cost were drawn and measured by the real renderer and layout code in the contact-sheet programs, and the wiring was proved by source pins.
- **Signing.** The three builds are unsigned (`CODE_SIGNING_ALLOWED=NO`); a signed Release or App Store archive is the owner's.
- **Windows and Linux.** Nothing under `windows/` is touched; the twin has its own plan and dry run.

The throwaway clones and the pictures' folders were moved to the Trash afterwards (`trash`, never `rm -rf`).

## The owner's answers (2026-10-13)

- **Approved as assumed:** every open question takes its assumed answer, with the parity rulings of 2026-10-12 applied.
- The `CLAUDE.md` line for the new test script is approved.
- **Runs now,** in parallel with D1; H-tauri starts once Docker is up so its Rust is compiled first.
