# A-mac, Stages 1 to 4: Shrimpy and Momo in the macOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the upstream character in the macOS app with Shrimpy and Momo, drawn in code and animated like the prototype: a still cat at every size and coat, the 11 states in both motion styles, the emotes, the mouth and personality, the new greeting, the four-step file catch, the refused-file hairball and the Playful error hiss then hairball; plus a Debug-only cat panel to pick a coat, a size, a state, an emote, a personality and a motion style and watch the cat live.

**Architecture:** `BotEngine.swift` is replaced by a set of focused files. `CatPresets`, `CatGeometry`, `Personality`, `CatRules`, `MotionProfiles`, `CatEngine` and `CatGreeting` are Foundation-only ports of `design/prototype/cat-core.js` and are tested against the A-0 fixtures in `tests/fixtures/cat/` with `swiftc` programs, the same pattern as the AI tests. `CatRenderer`, `CatFace` and `CatEffects` draw into a `CGContext` (a SwiftUI `Canvas` hands one out through `withCGContext`; the contact-sheet script makes its own bitmap), in a *behind* pass, the head and a *front* pass. The existing canvases (`BotCanvasView`, `MiniBotCanvasView`, `GreetingCanvasView`, `UploadCanvasView`) keep their place and their public shape and only change what they draw inside. A **Debug-only panel** (`CatDevModel`, tested with `swiftc`, and `CatDevPanel`, SwiftUI in a window opened from the menu bar) shows every coat, size, state, emote, personality and motion style live; it sits inside `#if DEBUG && !APPSTORE`, and `scripts/check-app-binary.sh` proves a Release and an App Store build do not contain it. A file the app refuses (apps, archives, disk images, videos, over 25 MB: `CatFileRule`, the app's own refusal rule) is decided **at the drop** and coughed up as a hairball instead of chewed.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, CoreGraphics and CoreText, XcodeGen, `swiftc` test programs, Bash.

**Spec:** `docs/superpowers/specs/2026-10-04-cats-in-app-design.md` (the A-mac row of §1, "Room for later sub-projects", "A-0b, contract additions", §3, the optional collar of the Decisions table, the dev state panel line of §2, §5 and "Stages"). The character rules are in `docs/superpowers/specs/2026-10-03-notchmeow-design.md`, "Sub-project A, steps" §2. The contract is `design/prototype/cat-core.js` with `docs/CAT-CONTRACT.md` and `tests/fixtures/cat/`; the look is `design/prototype/notchmeow.html`. Read all of them before starting.

**Base:** a new branch `a-mac/stages-1-4` in a git worktree, from `notchmeow/rebrand` at `49a9d1a` or later, with A-0 (merged as `f68b25b`) and A-0b (merged as `6adf584`: `earFit`, the compact flat fills and the collar geometry in `cat-core.js` and its fixtures) in its history. `e1/polish` and `perf/hidden-mouse-poll` may merge before it; this plan touches none of their files (`IslandWindowController.swift`, `IslandPoller.swift`, the AI code) and does not read anything from `IslandWindowController` beyond the notification names it already posts. It only *reads* the AI code (`AttachmentRules` and `AICatalog.Limits`, for the refusal rule) and never edits `cat-core.js` or its fixtures. This plan touches nothing under `windows/`.

## Global Constraints

Every task's requirements include this section. Values are copied from the specs.

- **Swift 6, SwiftUI and AppKit, no third-party dependencies.** The cat is drawn in code (`Canvas`/`CGContext`), no images. No Rive, no Lottie.
- **0 % CPU when the island is hidden.** The big cat's `TimelineView` is paused in `.hidden`; the engine has no timers (delayed actions live in a queue the frame loop drains).
- **Never restyle a shipping view.** The cat replaces only what is drawn inside the existing canvases. Hooks, `HookServer`, `AppState` and the island state machine are untouched. Never rename a pill ID or a contract string (`nm-hook`, `nm.sock`, `nm_kind`, `nm_agent`, bundle identifiers, notification names).
- **Cat IDs are frozen, in this order:** `shrimpy`, `momo`, `ginger`, `midnight`, `latte`, `patches`, `blue`, `snow`, `oreo`, `mocha`, `silver`, `cloud`, `leo`, `button`, `puff`, `noodle`. An unknown stored ID falls back to `shrimpy`. `voice`: Shrimpy -1, Momo +1, extra coats 0, kittens +3.
- **Fixtures decide.** Numbers compare within **1e-9 R** (Swift and JavaScript can differ in the last bit of `sin`, `cos` and `pow`); strings, booleans, nulls and the shape of the data compare exactly. There are no pixel tests: the look is checked by eye on the contact sheets next to the prototype. `cat-core.js` is the tie-breaker.
- **Randomness is injected.** The engine never reads a clock or a random source of its own: `now()` (ms) and `rand()` (0 up to, not including, 1) are passed in. The order of `rand()` calls is part of the contract.
- **Detail levels:** head width Ø28 and up draws the full cat; below Ø28 the compact cat (ink eyes; no irises, "M" stripes, cheek bars or whiskers; Momo's white map and Shrimpy's crown band, pads and chin stay) with **flat fills**: no rim, crown or point gradients (A-0b's rule, `CatGeometry.detailLevel(_:override:).flatFill`, which is exactly `!layout().full`, drawn from `flatFillColors` and `FlatFill`; the point mask is 0.86 R by 0.54 R at alpha 0.85). Ears are scaled down at the compact detail (`earScale`, 0.8 at Ø20 and below, **provisional**: the owner confirms it on the stage-1 sheet; it is the contract's number, so a change is made once in `cat-core.js` by the main session and this plan never edits it) on every compact cat, and where a ceiling is given they are fitted under the top of the strip, in the compact notch (`earScale(D) * f`, with A-0b's `earFit`, ported into `CatGeometry.earFit` and tested against the contract's `earFitCases`) (A-0b, merged `6adf584`).
- **Face warp:** the face takes 82 % of the 0.62 rad gaze yaw, 60 % of the 0.5 rad pitch looking up and 32 % looking down; the muzzle stands proud by +0.12 and the nose by another 0.05 R; the outline leans 0.1 rx and the head shifts 0.08 R toward the cursor; the near eye never foreshortens below 55 %; the pupils travel up to 0.24 of the eye width; the cursor curve is tanh over 240 px across and 180 px up and down.
- **Badge:** beside the right ear, 1.4 R right and 0.92 R up; on the left in the compact notch.
- **Mouth:** the upstream slot spring, ω₀ = 2π/0.25 and ζ = 0.6, stepped **at most 1/60 s at a time** like the core (a slow frame is several steps: one step of 0.066 s or more diverges to NaN); six animatable values (open, smile, tongue, round, skew, wavy).
- **No collar in stages 1 to 4.** The agent colour becomes an optional collar (Band and tag, Band, Neckerchief or Off; the default is **Off**) with its Settings rows in stages 5 to 7. Nothing here draws one, and nothing here ports the contract's collar items (`collarGeometry`, `COLLAR_STYLES`, `COLLAR_MIN`, `collarPass` and `collar-cases.json`, A-0b, merged `6adf584`: they are for stage 6); `CatEngine.collar` stays as an unused member for stage 6.
- **Port notes.** Every note of "Notes for ports" in `docs/CAT-CONTRACT.md` applies: the five `rand()` draws of the constructor, the order of draws inside an action, `_base` and `_mouth` set once, frame 0 sampled before any update, an action at frame f running after that frame's update, a zero `ear.cx` counting as missing, `tMs` computed from `f` (or compared within 1e-8), seeds as `UInt32`, `truncatingRemainder` for `wrapA`, and the spring sub-steps above.
- **Hairball** 2.4 s. **Zoomies** 2 s, and they play after an agent finishes **5 minutes** of working, thinking or searching; approval and question pauses don't reset that clock. **File catch, four steps:** open wide while a file hovers; snap wider on the drop while the file flies in; gulp with a squash; chew for 0.85 s with happy eyes. The file is drawn **in front of the cat**, hovering and flying, as in the prototype's catch, and flies along the contract's `flightAt` over `FLIGHT_MS` (380 ms). **Refused files** (the app's existing refusal rule: apps, archives, disk images, videos, over 25 MB; decided at the drop, same on both apps): the catch plays as for any file, then, instead of the gulp and the chew, the cat gags and coughs the file up as a hairball (it takes 120 ms to start heaving and the hairball lasts 2.4 s), and then the existing refusal note shows, 2.52 s after the file arrives. A refused file gets no progress bar, no success check mark and no `approve` chime (the chime moves from the drop to a successful ingest). **Its sound:** the cat plays the existing `annoyed` sound once, when the gag starts (the file has reached its mouth; the heaves follow 120 ms later), and the refusal note plays no sound. The `pop` at the cough is wired later, by sound Stage 3: neither plan adds it now. Any other failure (an unreadable file, a copy error, a folder) keeps today's ending and sound (the `annoyed` sound and the annoyed cat), with no hairball. **Greeting:** the new one (`GT2`), 5.74 s, no upstream sound.
- **Frame time:** twelve small cats plus the big one stay under **2 ms** per frame on the Mac (a Debug-only readout, in the log and in the cat panel). Small cats use the compact detail level.
- **Debug-only dev panel.** The spec's dev state panel is, on the Mac, a window opened from the menu bar ("Cats (Debug)…") in the style of Settings: coat, size, state, emote, personality, motion style, poke, the eleven states, every coat, the file buttons and the greeting, live. `CatDevModel.swift`, `CatDevPanel.swift` and its menu item and window in `AppDelegate.swift` are inside `#if DEBUG && !APPSTORE`, and `scripts/check-app-binary.sh` proves a Release build and an App Store build do not contain them (the marker `NM_CAT_DEV_PANEL`). The panel runs on a `CatConfig` of its own: the app's cats and settings are never touched.
- **Secrets, telemetry, logs:** nothing new touches the Keychain or the network. Tests never write to `~/Library/Logs/NotchMeow`: every `scripts/test-cat-*.sh` exports `NM_LOG_DIR` to a temp folder.
- **Commits:** local only, never pushed, and only the files each task lists. Each commit message ends with the `Co-Authored-By` line of the model that wrote it: `Claude Sonnet 5.5` for `nm-implementer` and `nm-implementer-deep`, `Claude Haiku 4.5` for `nm-implementer-light`.
- **Never edit `NotchBuddy.xcodeproj` by hand.** Tasks that add or remove Swift files run `cd NotchBuddy && xcodegen` and commit the regenerated `project.pbxproj`.

## Review Focus

The spec says what the cats must do. It is silent on these conditions (seven here, because the file rule and the panel are new), and each would bite a person first. Each line names the test that pins it.

1. **A cat squeezed into the compact notch strip.** At Ø20 in a 32 pt strip (Ø18 in a 24 pt strip, on a screen without a notch) a cat that hops with its ears up pushes them off the top of the screen, where they are cut. Expected: the ears are fitted under the strip's top edge. Tests: Task 2 "ear headroom" (five coats in two strips and seven poses against a brute-force walk of the whole ear outline: no tip leaves the strip, and a shrunk ear sits exactly on the fixture's margin; the contract's `earFitCases`) and Task 4 (pixels above the strip stay empty, the renderer's fitted ears sit on the margin, and the ear scale and the fit compose).
2. **A bad frame time, or two clocks.** The old Mac engine subtracted a `CACurrentMediaTime()` from the timeline's date, so `dt` was always its maximum; a sleeping laptop gives a huge `dt`, a clock that steps back a negative one. Expected: `dt` is held to 0 up to 0.05 s and the pose stays finite. Tests: Task 6 "frame time comes from one clock" and "hostile frame times".
3. **A stored value that is not valid:** an unknown cat ID, an unknown motion style, a hand-edited personality (out of range, missing, a string). Expected: Shrimpy, Playful, Balanced and 0 to 1, never a crash and never NaN. Tests: Task 1, Task 5 `sanitized`, Task 6 "motion per cat".
4. **A poke, a drag or a refused file at the wrong moment:** pokes more than 1.7 s apart, a drag that leaves the island and comes back after a drop, a refused file before the cat has been drawn once (no mouth point to spit from), a second drag after a refused drop. Expected: the cat does the sensible thing and nothing crashes. Tests: Task 6 "app-facing behaviour" and Task 14 (the driver).
5. **The greeting cut short, held open, or ending in a real island.** The pointer leaves mid-greeting, or rests on the island; the compact island of a real screen is not the contract's 288 x 32. Expected: no jump, the cat ends at the notch at the real size. Tests: Task 12 and Task 13.
6. **A file at the edge of the refusal rule:** exactly 25 MB (26,214,400 bytes: taken) and one byte more (refused), an extension in capitals (`SETUP.EXE`), an `.app` bundle (a folder: refused by its extension), a file with no extension, a plain folder, a binary file with an unknown extension (an "other failure": no hairball, today's ending). Expected: the cat coughs up exactly the refused ones. Tests: Task 14 (`CatFileRule` against the AI fixture) and Task 14's panel buttons.
7. **The dev panel in a shipped build.** A Release or App Store build that contains the Debug-only panel. Expected: neither does. Tests: Task 9 (`check-app-binary.sh` in `debug`, `release` and `appstore` modes, each proved able to fail).

---

## File Structure

| Path | Responsibility |
|---|---|
| `NotchBuddy/Sources/App/CatPresets.swift` | The 16 coats as `CatPreset` values, the kitten rule, the frozen IDs. |
| `NotchBuddy/Sources/App/CatMath.swift` | `lerp`, `clamp`, `seg`, the easing curves, the seeded PRNG. |
| `NotchBuddy/Sources/App/CatGeometry.swift` | The pose (`CatPose`), the head outline, the face warp, the layout of one cat in one pose, ear headroom (`earFit`) and the flat-fill rule: the contract's A-0b items, ported and tested against its fixtures. |
| `NotchBuddy/Sources/App/CatLook.swift` | What the renderer draws: `CatLook` and its small types (eye shapes, badge, particles, balls, paws), `CatDrawOptions`. |
| `NotchBuddy/Sources/App/CatDrawing.swift` | Colours, gradients, paths and text for the renderer (`CatDraw`). |
| `NotchBuddy/Sources/App/CatEffects.swift` | The glow, afterimages, paws, badge, particles, hairballs and the dance. |
| `NotchBuddy/Sources/App/CatFace.swift` | Eyes, nose, mouth and whiskers. |
| `NotchBuddy/Sources/App/CatRenderer.swift` | `CatRenderer.draw`: the three passes, markings, ears, the head. |
| `NotchBuddy/Sources/App/Personality.swift` | The six traits, the six presets, traits to multipliers. |
| `NotchBuddy/Sources/App/CatRules.swift` | `CatState`, the work clock (zoomies), the sleep timer, search tool names. |
| `NotchBuddy/Sources/App/MotionProfiles.swift` | State, mouth and emote tables; the Classic and Playful profiles. |
| `NotchBuddy/Sources/App/CatEngine.swift` | The engine: pose, tweens, queue, particles, file catch, hairball, zoomies, greeting wave. |
| `NotchBuddy/Sources/App/CatEngine+App.swift` | The app's way in: the real clock, `BotState` and `BotEmote`, sounds. App target only. |
| `NotchBuddy/Sources/App/CatGreeting.swift` | The launch greeting's timeline and the file flight. |
| `NotchBuddy/Sources/App/CatGreetingRenderer.swift` | Draws the greeting into a 640x150 canvas. |
| `NotchBuddy/Sources/App/CatFrameMeter.swift`, `CatFrameReadout.swift` | The frame-time meter and its Debug-only readout. |
| `NotchBuddy/Sources/App/CatFileRule.swift` | Which files the cat coughs up (the app's own refusal rule, decided at the drop) and the label on them. |
| `NotchBuddy/Sources/App/UploadCatDriver.swift` | Turns the upload sequence's frames into the file catch, or, for a refused file, the hairball. |
| `NotchBuddy/Sources/App/CatDevModel.swift`, `CatDevPanel.swift` | The Debug-only cat panel: its model (tested) and its SwiftUI. Inside `#if DEBUG && !APPSTORE`; opened from the menu bar by `AppDelegate.swift`. |
| `NotchBuddy/Sources/App/BotCanvasView.swift`, `GreetingCanvasView.swift`, `UploadCanvasView.swift`, `UploadSequenceEngine.swift`, `IslandRootView.swift` | Existing views: they draw the cat instead of the old character. `BotEngine.swift` is deleted. |
| `scripts/test-cat-*.sh`, `tests/Cat*Tests.swift`, `tests/CatDevModelTests.swift`, `tests/UploadCatDriverTests.swift`, `tests/Cat*Support.swift` | The Swift test programs (one script each) and their shared helpers. |
| `scripts/render-cats.sh`, `scripts/render-cats.swift` | The contact-sheet renderer: ladder, stage, states, emotes, mouths, greeting, catch, and a frame-time bench. |
| `scripts/render-cat-panel.sh`, `scripts/render-cat-panel.swift` | Draws the Debug-only cat panel into a PNG, offscreen, without launching the app. |
| `scripts/check-app-binary.sh` | Also proves the cat panel is in a Debug build and in no Release or App Store build. |
| `.github/workflows/build.yml`, `CLAUDE.md`, `ARCHITECT.md` | One CI step per test script; one pointer each. |

**How the Swift tests load the fixtures.** Every `scripts/test-cat-*.sh` runs from the repository root, compiles the sources it needs together with `tests/CatTestSupport.swift` using `swiftc -swift-version 6`, and runs the program. `CT.fixture("presets.json")` reads `tests/fixtures/cat/<file>` from the current directory with `JSONSerialization` at run time (no embedding, no code generation), and `CT.checkJSON` compares a Swift value, encoded as JSON, with the fixture's value: numbers within 1e-9, everything else exactly, a key that is null counting as absent.

**Agents** (CLAUDE.md: the lightest model that fits). Tasks that are mostly transcription of given code with fixture tests (1, 2, 5, 10, 12, 15) are `nm-implementer-light`. Drawing and engine ports, where a typo in a drawing constant is only caught by eye (3, 4, 6, 7, 13), and the cat panel, whose model is test-first and whose SwiftUI is proven by the build and the offscreen render (9, 11), are `nm-implementer`. The SwiftUI integration tasks that can only be proven by a build and a read of the diff (8, 14) are `nm-implementer-deep`. Task reviews: `nm-reviewer`; the final whole-branch review: `nm-reviewer-deep`. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion` (the deep agent also `superpowers:systematic-debugging`); reviewers load `ponytail:ponytail-review`.

**Stages and tasks.** The engine is ported whole in Task 6, because the fixtures sample whole sequences (the Playful error state hairballs, for example), so the stage a feature belongs to is the stage where you can *see* it in the app or on a sheet.

| Stage | Tasks | What the owner gets |
|---|---|---|
| 1. A still cat at every size, every coat, kittens | 1 presets, 2 geometry, 3 drawing kit and effects, 4 the still cat and the contact sheet | **Owner checkpoint 1** (after Task 4): the contact sheet next to the prototype |
| 2. The 11 states, both motion styles, gaze and face warp | 5 personality and rules, 6 engine and profiles, 7 the states sheet, 8 the app draws the cats, 9 the Debug-only cat panel (coat, size, motion style, state, the eleven states) | A running app with the cats in every existing place, and the panel |
| 3. Emotes, the mouth and personality | 10 emote and mouth sheets and the Debug frame-time readout, 11 the panel's emotes, personality and poke | The emote sheet; the frame-time number; the panel's emotes |
| 4. Greeting, file catch, hairball | 12 greeting timeline, 13 greeting renderer and view (and the panel's greeting), 14 the drop view's catch, the refused file's hairball and the panel's file buttons, 15 CI, docs and the final checks | **Owner checkpoint 2** (after Task 15): the contact sheets and the manual checks |

**Order of tasks:** each task ends with a green test and a commit; tasks 1 to 4 do not touch the app, task 8 swaps the engine in the views.

---

### Task 0: Worktree and baseline

No code and no commit: this makes sure the base is the one the plan expects.

This plan runs in its own worktree chat session on **Sonnet 5.5 at high effort** (`CLAUDE.md`, worktree sessions). The main session starts it in three steps: the session's first turn only does this Task 0 and reports "ready", then the main session sets its model and effort, then sends the controller brief.

- [ ] **Step 1: Put the session's worktree on the plan's branch**

```bash
git status                                   # must be clean
git switch -c a-mac/stages-1-4 notchmeow/rebrand   # notchmeow/rebrand at 49a9d1a or later
git log --oneline -8                         # A-0's merge (f68b25b) and A-0b's merge (6adf584) are in history
```

Every later command runs from the root of this worktree. Never push.

- [ ] **Step 2: Check that A-0 and A-0b are in the base, that this plan is tracked, and that the contract is green**

Run: `git merge-base --is-ancestor f68b25b HEAD && git merge-base --is-ancestor 6adf584 HEAD && git ls-files --error-unmatch docs/superpowers/plans/2026-10-04-a-mac-cats-stages-1-4.md`
Expected: the plan's path is printed and the command exits 0 (A-0 and A-0b are in the history, and the plan is a tracked file of this branch).

If it fails, the worktree was cut from an older base: stop and tell the owner, who re-cuts it from `notchmeow/rebrand` (`49a9d1a` or later).

Run: `test -f design/prototype/cat-core.js && test -f tests/fixtures/cat/presets.json && test -f tests/fixtures/cat/motion-cases.json && bash scripts/test-cat-contract.sh`
Expected: PASS

A-0b put these names in the contract, and Tasks 2 and 4 use exactly them: `EAR_FIT`, `earFit`, `detailLevel`, `FLAT_FILL`, `mixHex` and `flatFillColors` in `design/prototype/cat-core.js`, and the keys `earFit`, `earFitCases`, `flatFill`, `detailLevels` and `flatColors` in `tests/fixtures/cat/geometry-cases.json`. The collar's names (`COLLAR_STYLES`, `collarStyleOf`, `COLLAR_MIN`, `COLLAR_PASS`, `collarGeometry`, `collarPass` and `collar-cases.json`) are there too, and are for stage 6.

- [ ] **Step 3: Check the Mac test scripts that already exist are green**

Run: `bash scripts/test-screen-geometry.sh && bash scripts/check-test-logs.sh`
Expected: PASS

---

### Task 1: The 16 coats, their kittens and the frozen IDs (stage 1)

Agent: `nm-implementer-light`.

**Files:**
- Create: `tests/CatTestSupport.swift`, `tests/CatPresetsTests.swift`, `scripts/test-cat-presets.sh`
- Create: `NotchBuddy/Sources/App/CatPresets.swift`

**Interfaces:**
- Consumes: `tests/fixtures/cat/presets.json` (A-0).
- Produces `struct CatPreset: Encodable, Sendable`: `name`, `label`, `desc?`, `voice: Int`, `coat` (`"tuxedo" | "tabby" | "point" | "calico" | "solid"`), `rx`, `ry`, `n`, `fluff`, `ruff: Ruff?`, `bib?`, `furOpts?`, `earSpread`, `ear: Ear` (`h, bw, rot, tip, tuft, cx?, fold?`), the colours as strings (`top`, `bot`, `light?`, `chinCol?`, `stripe?`, `inner`, `nose`, `noseLine`, `iris: [String]`, `irisR?`, `lidTint?`, `liner`, `ink`, `mouthLine`, `whisk`, `padDot`, `paw`, `bean`, `hair`, `hairDark`, `hairLight`, `white?`, `point?`, `muzzle?`, `earCols?`), `noseW`, `noseH`, `nosePh`, `whisk2: Whisk`, `eye: Eye` (`th, ph, w, h, round`), `pupil0`, `blushAt: [Double]`, `patches?: [Patch]`, `rimLight?`, `hairless?`, `wrinkles?`, `kitten?: Bool`, `base?: String`. All lengths are in units of R, the head radius.
- Produces `enum CatPresets`: `static let ids: [String]` (the 16 frozen IDs), `static let all: [String: CatPreset]`, `static func byID(_ id: String?) -> CatPreset` (an unknown or missing ID gives Shrimpy), `static func kitten(of: CatPreset) -> CatPreset`, and the typealiases `Ruff`, `FurOpts`, `Ear`, `Eye`, `Whisk`, `Patch`.
- Produces the test helpers in `enum CT` (main actor): `section(_:)`, `check(_:_:_:)`, `checkTrue(_:_:)`, `checkNear(_:_:_:tol:)`, `checkRows(_:_:)`, `fixture(_:) -> [String: Any]`, `diffs(_:_:tol:) -> [String]`, `checkJSON(_:got:want:tol:)`, `json(_:) -> Any` (a `Encodable` as the JSON a fixture holds) and `finish() -> Never`. A key that is null counts as absent, so a Swift `nil` and a JSON `null` agree.

- [ ] **Step 1: Write the failing test**

**Create `tests/CatTestSupport.swift`:**

```swift
import Foundation

// Shared helpers for the cat test programs (scripts/test-cat-*.sh compile this file into each one).
// Run from the repository root: fixture paths are relative to it.
// Numbers compare within 1e-9, because Swift and JavaScript can differ in the last bit of sin, cos and pow.

@MainActor
enum CT {
    static var failures = 0
    static let tolerance = 1e-9

    /// Every section starts here, so a test program run by hand (without `NM_LOG_DIR`) stops before it does anything.
    static func section(_ name: String) {
        requireTempLog()
        print(name)
    }

    /// Tests never write to the user's real log: `scripts/test-*.sh` set `NM_LOG_DIR` to a temp folder.
    static func requireTempLog() {
        guard let dir = ProcessInfo.processInfo.environment["NM_LOG_DIR"], !dir.isEmpty, !dir.contains("/Library/Logs") else {
            print("NM_LOG_DIR is not set to a temp folder: run this through its scripts/test-*.sh")
            exit(2)
        }
    }

    static func check<V: Equatable>(_ label: String, _ got: V, _ expected: V) {
        if got == expected {
            print("  ✓ \(label)")
        } else {
            print("  ✗ \(label)")
            print("    got:      \(got)")
            print("    expected: \(expected)")
            failures += 1
        }
    }

    static func checkTrue(_ label: String, _ value: Bool) {
        if value { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
    }

    /// `got` within `tol` of `want`.
    static func checkNear(_ label: String, _ got: Double, _ want: Double, tol: Double = tolerance) {
        if abs(got - want) <= tol { print("  ✓ \(label)") } else {
            print("  ✗ \(label)\n    got:      \(got)\n    expected: \(want)")
            failures += 1
        }
    }

    static func finish() -> Never {
        if failures == 0 {
            print("\nAll tests passed.")
            exit(0)
        }
        print("\n\(failures) test(s) failed.")
        exit(1)
    }

    // MARK: - Fixtures

    /// `tests/fixtures/<dir>/<file>`: the cat fixtures by default, the AI fixtures with `dir: "ai"`.
    static func fixtureURL(_ file: String, dir: String = "cat") -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tests/fixtures/\(dir)")
            .appendingPathComponent(file)
    }

    /// A parsed fixture file (a dictionary at the top level).
    static func fixture(_ file: String, dir: String = "cat") -> [String: Any] {
        let data = try! Data(contentsOf: fixtureURL(file, dir: dir))
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    // MARK: - Deep compare with a tolerance

    /// The differences between two JSON-shaped values; empty when equal. Numbers compare within `tol`,
    /// strings, booleans and the shape of the data compare exactly. A key that is null counts as absent.
    static func diffs(_ got: Any, _ want: Any, tol: Double = tolerance) -> [String] {
        var out: [String] = []
        compare(got, want, "$", tol, &out)
        return out
    }

    static func checkJSON(_ label: String, got: Any, want: Any, tol: Double = tolerance) {
        let d = diffs(got, want, tol: tol)
        if d.isEmpty { print("  ✓ \(label)") } else {
            print("  ✗ \(label) (\(d.count) differences)")
            for line in d.prefix(6) { print("    \(line)") }
            failures += 1
        }
    }

    private static func isBool(_ x: Any) -> Bool {
        guard let n = x as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    private static func compare(_ got: Any, _ want: Any, _ at: String, _ tol: Double, _ out: inout [String]) {
        if got is NSNull && want is NSNull { return }
        if let g = got as? [String: Any], let w = want as? [String: Any] {
            let gk = Set(g.filter { !($0.value is NSNull) }.keys), wk = Set(w.filter { !($0.value is NSNull) }.keys)
            if gk != wk { out.append("\(at): keys \(gk.sorted()) vs \(wk.sorted())") }
            for k in gk.intersection(wk).sorted() { compare(g[k]!, w[k]!, "\(at).\(k)", tol, &out) }
        } else if let g = got as? [Any], let w = want as? [Any] {
            if g.count != w.count { out.append("\(at): length \(g.count) vs \(w.count)") }
            for i in 0..<min(g.count, w.count) { compare(g[i], w[i], "\(at)[\(i)]", tol, &out) }
        } else if let g = got as? String, let w = want as? String {
            if g != w { out.append("\(at): \"\(g)\" vs \"\(w)\"") }
        } else if let g = got as? NSNumber, let w = want as? NSNumber {
            if isBool(g) != isBool(w) { out.append("\(at): \(g) vs \(w) (bool against number)") }
            else if isBool(g) { if g.boolValue != w.boolValue { out.append("\(at): \(g) vs \(w)") } }
            else if !(abs(g.doubleValue - w.doubleValue) <= tol) { out.append("\(at): \(g.doubleValue) vs \(w.doubleValue)") }
        } else {
            out.append("\(at): \(type(of: got)) \(got) vs \(type(of: want)) \(want)")
        }
    }

    /// A Swift `Encodable` as the JSON-shaped value the fixtures hold.
    static func json<E: Encodable>(_ value: E) -> Any {
        let data = try! JSONEncoder().encode(value)
        return try! JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}

// MARK: - Checks for groups of rows

extension CT {
    /// One line for a whole group of rows: ✓ when none differ, else the first few differences.
    static func checkRows(_ label: String, _ diffs: [String]) {
        if diffs.isEmpty { print("  ✓ \(label)") } else {
            print("  ✗ \(label) (\(diffs.count) differences)")
            for d in diffs.prefix(6) { print("    \(d)") }
            failures += 1
        }
    }
}
```

**Create `tests/CatPresetsTests.swift`:**

```swift
import Foundation

@main
enum CatPresetsTests {
    @MainActor static func main() {
        let want = CT.fixture("presets.json")
        let cats = want["cats"] as! [String: Any], kittens = want["kittens"] as! [String: Any]

        CT.section("the frozen IDs")
        CT.check("sixteen IDs, Shrimpy first and Momo second", CatPresets.ids, want["ids"] as! [String])
        CT.check("every ID has a coat", Set(CatPresets.all.keys), Set(CatPresets.ids))

        for id in CatPresets.ids {
            CT.section("coat \(id)")
            let p = CatPresets.byID(id)
            CT.checkJSON("coat resolves like cat-core.js", got: CT.json(p), want: cats[id]!)
            CT.checkJSON("kitten resolves like cat-core.js", got: CT.json(CatPresets.kitten(of: p)), want: kittens[id]!)
        }

        CT.section("voices (sub-project C)")
        CT.check("Shrimpy -1", CatPresets.byID("shrimpy").voice, -1)
        CT.check("Momo +1", CatPresets.byID("momo").voice, 1)
        CT.check("the extra coats 0", CatPresets.ids.dropFirst(2).map { CatPresets.byID($0).voice }, Array(repeating: 0, count: 14))
        CT.check("kittens +3", CatPresets.ids.map { CatPresets.kitten(of: CatPresets.byID($0)).voice }, Array(repeating: 3, count: 16))

        CT.section("an unknown stored ID falls back to Shrimpy")
        for bad in [nil, "", "SHRIMPY", "Momo", "siamese", "calico", "__proto__", "constructor", "momo ", "💥"] as [String?] {
            CT.check("\(bad.map { "\"\($0)\"" } ?? "nil") is Shrimpy", CatPresets.byID(bad).name, "shrimpy")
        }
        CT.check("a known ID is itself", CatPresets.byID("momo").name, "momo")

        CT.section("kittens")
        let k = CatPresets.kitten(of: CatPresets.byID("shrimpy"))
        CT.check("a kitten remembers its parent", k.base, "shrimpy")
        CT.check("a kitten is labelled", k.label, "Shrimpy kitten")
        CT.checkTrue("the parent is not changed", CatPresets.byID("shrimpy").kitten == nil && CatPresets.byID("shrimpy").rx == 1.16)
        CT.finish()
    }
}
```

**Create `scripts/test-cat-presets.sh`:**

```bash
#!/usr/bin/env bash
# Cat presets: the 16 coats, their kittens and the frozen IDs against tests/fixtures/cat/presets.json.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-presets.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/CatPresets.swift \
    tests/CatTestSupport.swift tests/CatPresetsTests.swift \
    -o "$TEST_DIR/cat-presets-tests"
"$TEST_DIR/cat-presets-tests"
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-presets.sh`
Expected: FAIL (swiftc cannot open `NotchBuddy/Sources/App/CatPresets.swift`)

- [ ] **Step 3: Write the presets**

The values are `PRESETS` of `cat-core.js`: Shrimpy and Momo in full, the fourteen other coats as overrides of the shorthair template (as `makeCat` does there), and `kitten(of:)` is `kittenOf`.

**Create `NotchBuddy/Sources/App/CatPresets.swift`:**

```swift
import Foundation

// The cats, as numbers. Every value is in units of R, the head radius, and is the same as in
// design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/presets.json pins them.
// The 16 IDs are frozen contract values: they are stored in settings.

struct CatPreset: Encodable, Sendable {
    struct Ruff: Encodable, Sendable { var rx: Double; var ry: Double; var dy: Double; var col: [String] }
    struct FurOpts: Encodable, Sendable {
        var n: Int; var l0: Double; var l1: Double; var w: Double; var dark: String; var light: String
        var wDark: String?; var wLight: String?
    }
    struct Ear: Encodable, Sendable {
        var h: Double; var bw: Double; var rot: Double; var tip: Double; var tuft: Double
        /// Absent means the default 0.95 (Shrimpy has none).
        var cx: Double?
        /// A folded ear (Button): the tip folds forward and down over the head.
        var fold: Double?
    }
    struct Eye: Encodable, Sendable { var th: Double; var ph: Double; var w: Double; var h: Double; var round: Double }
    struct Whisk: Encodable, Sendable {
        var rows: Int; var cols: Int; var x0: Double; var dx: Double; var y0: Double; var dy: Double; var slope: Double
        var dot: Double; var wcols: [Int]; var a0: Double; var da: Double; var len: Double; var dl: Double
        var droop: Double; var w: Double; var alpha: Double; var brow: Int
    }
    /// A coat patch: x, y, half width, half height, rotation (all R), colour, wobble seed. Stored as a JSON array like the contract.
    struct Patch: Encodable, Sendable {
        var x: Double; var y: Double; var a: Double; var b: Double; var rot: Double; var color: String; var seed: Int
        init(_ x: Double, _ y: Double, _ a: Double, _ b: Double, _ rot: Double, _ color: String, _ seed: Int) {
            self.x = x; self.y = y; self.a = a; self.b = b; self.rot = rot; self.color = color; self.seed = seed
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.unkeyedContainer()
            try c.encode(x); try c.encode(y); try c.encode(a); try c.encode(b); try c.encode(rot); try c.encode(color); try c.encode(seed)
        }
    }

    var name: String
    var label: String
    var desc: String?
    /// A pitch offset in semitones for sub-project C: Shrimpy -1, Momo +1, the extra coats 0, kittens +3.
    var voice: Int
    /// "tuxedo", "tabby", "point", "calico" or "solid".
    var coat: String
    var rx: Double
    var ry: Double
    var n: Double
    var fluff: Double
    var ruff: Ruff?
    var bib: String?
    var furOpts: FurOpts?
    var earSpread: Double
    var ear: Ear
    var top: String
    var bot: String
    var light: String?
    var chinCol: String?
    var stripe: String?
    var rimLight: Int?
    var white: String?
    var point: String?
    var earCols: [String]?
    var muzzle: String?
    var patches: [Patch]?
    var hairless: Int?
    var wrinkles: Int?
    var inner: String
    var nose: String
    var noseLine: String
    var noseW: Double
    var noseH: Double
    var nosePh: Double
    var iris: [String]
    var irisR: [String]?
    var lidTint: String?
    var liner: String
    var ink: String
    var mouthLine: String
    var whisk: String
    var padDot: String
    var whisk2: Whisk
    var eye: Eye
    var pupil0: Double
    var blushAt: [Double]
    var paw: String
    var bean: String
    var hair: String
    var hairDark: String
    var hairLight: String
    var kitten: Bool?
    /// A kitten's parent: the cat ID its personality and motion settings come from.
    var base: String?
}

enum CatPresets {
    typealias Ruff = CatPreset.Ruff
    typealias FurOpts = CatPreset.FurOpts
    typealias Ear = CatPreset.Ear
    typealias Eye = CatPreset.Eye
    typealias Whisk = CatPreset.Whisk
    typealias Patch = CatPreset.Patch

    /// The frozen cat IDs, Shrimpy first and Momo second.
    static let ids = ["shrimpy", "momo", "ginger", "midnight", "latte", "patches", "blue", "snow", "oreo", "mocha", "silver", "cloud", "leo", "button", "puff", "noodle"]

    /// Every coat by ID.
    static let all: [String: CatPreset] = [
        "shrimpy": shrimpy, "momo": momo, "ginger": ginger, "midnight": midnight, "latte": latte, "patches": patches,
        "blue": blue, "snow": snow, "oreo": oreo, "mocha": mocha, "silver": silver, "cloud": cloud, "leo": leo,
        "button": button, "puff": puff, "noodle": noodle,
    ]

    /// A stored cat ID to its preset. An unknown ID (or none) falls back to Shrimpy.
    static func byID(_ id: String?) -> CatPreset {
        guard let id, let p = all[id] else { return shrimpy }
        return p
    }

    /// Kittens keep the parent's coat; rounder head, bigger eyes and ears, shorter muzzle.
    static func kitten(of p: CatPreset) -> CatPreset {
        var k = p
        k.kitten = true; k.base = p.name; k.label = p.label + " kitten"; k.voice = 3
        k.rx = p.rx * 0.97; k.ry = p.ry * 1.02; k.n = 2.05
        k.ear.h *= 1.12; k.ear.bw *= 1.06; k.ear.tuft = 0
        k.eye.w *= 1.2; k.eye.h *= 1.32; k.eye.round = 1; k.eye.th += 0.02
        k.pupil0 = max(p.pupil0, 0.18)
        k.nosePh = p.nosePh + 0.08; k.noseW *= 0.85; k.noseH *= 0.85
        k.whisk2.len *= 0.7; k.whisk2.brow = 1
        if var r = k.ruff { r.rx *= 0.94; r.ry *= 0.92; k.ruff = r }
        return k
    }

    /// The shorthair template for the extra coats; each cat only overrides what differs.
    private static func coat(_ name: String, _ label: String, _ desc: String, _ change: (inout CatPreset) -> Void) -> CatPreset {
        var p = template
        p.name = name; p.label = label; p.desc = desc
        change(&p)
        return p
    }

    private static let template = CatPreset(
        name: "", label: "", voice: 0, coat: "solid", rx: 1.12, ry: 0.9, n: 2.2, fluff: 0,
        earSpread: 0.8, ear: Ear(h: 0.8, bw: 0.5, rot: 0.46, tip: 0.09, tuft: 0, cx: 0.7),
        top: "", bot: "", inner: "", nose: "", noseLine: "", noseW: 0.2, noseH: 0.13, nosePh: -0.42, iris: ["", ""],
        liner: "", ink: "", mouthLine: "", whisk: "", padDot: "",
        whisk2: Whisk(rows: 3, cols: 2, x0: 0.16, dx: 0.065, y0: -0.01, dy: 0.06, slope: 0.02, dot: 0.014, wcols: [0, 1], a0: -0.1, da: 0.2, len: 1.32, dl: 0.1, droop: 0.1, w: 0.021, alpha: 0.95, brow: 2),
        eye: Eye(th: 0.43, ph: -0.02, w: 0.19, h: 0.17, round: 1), pupil0: 0.2, blushAt: [0.55, 0.25],
        paw: "", bean: "", hair: "", hairDark: "", hairLight: "")

    // MARK: - Shrimpy and Momo (full values)

    static let shrimpy = CatPreset(
        name: "shrimpy",
        label: "Shrimpy",
        voice: -1,
        coat: "tabby",
        rx: 1.16,
        ry: 0.92,
        n: 2.2,
        fluff: 1.0,
        ruff: Ruff(rx: 1.3, ry: 0.97, dy: 0.2, col: ["#B49C7A", "#7E6750"]),
        bib: "#F3EEE6",
        furOpts: FurOpts(n: 420, l0: 0.04, l1: 0.05, w: 0.01, dark: "rgba(60,46,36,.28)", light: "rgba(214,190,150,.32)"),
        earSpread: 0.8,
        ear: Ear(h: 0.8, bw: 0.4, rot: 0.44, tip: 0.1, tuft: 1.0),
        top: "#A08A70",
        bot: "#6E5B49",
        light: "#D9B68A",
        chinCol: "#E6D0AD",
        stripe: "#2E241D",
        inner: "#DCC39A",
        nose: "#C07A62",
        noseLine: "#5E3526",
        noseW: 0.19,
        noseH: 0.12,
        nosePh: -0.36,
        iris: ["#C9D18A", "#6F8445"],
        liner: "#231A14",
        ink: "#231A14",
        mouthLine: "#5E3526",
        whisk: "#F7F3EC",
        padDot: "#2E241D",
        whisk2: Whisk(rows: 3, cols: 3, x0: 0.14, dx: 0.065, y0: -0.01, dy: 0.065, slope: 0.022, dot: 0.017, wcols: [1, 2], a0: -0.14, da: 0.2, len: 1.45, dl: 0.12, droop: 0.12, w: 0.022, alpha: 0.95, brow: 3),
        eye: Eye(th: 0.42, ph: -0.02, w: 0.21, h: 0.16, round: 0.0),
        pupil0: 0.08,
        blushAt: [0.6, 0.22],
        paw: "#B89C78",
        bean: "#6B3B2C",
        hair: "#9A8064",
        hairDark: "#5A4634",
        hairLight: "#D2B791")

    static let momo = CatPreset(
        name: "momo",
        label: "Momo",
        voice: 1,
        coat: "tuxedo",
        rx: 1.12,
        ry: 0.9,
        n: 2.2,
        fluff: 0.0,
        furOpts: FurOpts(n: 700, l0: 0.025, l1: 0.03, w: 0.008, dark: "rgba(24,24,27,.45)", light: "rgba(112,114,122,.42)", wDark: "rgba(196,190,184,.55)", wLight: "rgba(255,255,255,.5)"),
        earSpread: 0.8,
        ear: Ear(h: 0.8, bw: 0.56, rot: 0.5, tip: 0.09, tuft: 0.0, cx: 0.62),
        top: "#3D3D41",
        bot: "#3D3D41",
        rimLight: 1,
        white: "#F6F4F1",
        inner: "#B98288",
        nose: "#E89AA6",
        noseLine: "#B86F7C",
        noseW: 0.25,
        noseH: 0.15,
        nosePh: -0.48,
        iris: ["#7E8A45", "#D1B85F"],
        lidTint: "#D9BE62",
        liner: "#16171A",
        ink: "#E4D592",
        mouthLine: "#9A8C88",
        whisk: "#F6F4F1",
        padDot: "rgba(150,142,138,.6)",
        whisk2: Whisk(rows: 3, cols: 2, x0: 0.17, dx: 0.065, y0: -0.01, dy: 0.06, slope: 0.02, dot: 0.014, wcols: [0, 1], a0: -0.1, da: 0.2, len: 1.32, dl: 0.1, droop: 0.1, w: 0.021, alpha: 0.95, brow: 2),
        eye: Eye(th: 0.43, ph: -0.02, w: 0.19, h: 0.17, round: 1.0),
        pupil0: 0.235,
        blushAt: [0.5, 0.32],
        paw: "#F6F4F1",
        bean: "#E89AA6",
        hair: "#56575E",
        hairDark: "#2E2F33",
        hairLight: "#9A9BA2")

    // MARK: - The fourteen extra coats (the shorthair template with overrides)

    static let ginger = coat("ginger", "Ginger", "orange tabby") {
        $0.coat = "tabby"
        $0.top = "#E39B52"
        $0.bot = "#C46F2E"
        $0.light = "#F7DDB8"
        $0.chinCol = "#FCEFDD"
        $0.stripe = "#A9541C"
        $0.inner = "#F2B8A8"
        $0.nose = "#E88E80"
        $0.noseLine = "#A85A4E"
        $0.iris = ["#E9D27A", "#C99A2E"]
        $0.liner = "#3A2416"
        $0.ink = "#3A2416"
        $0.mouthLine = "#A0624A"
        $0.whisk = "#FFF6EA"
        $0.padDot = "#B7682F"
        $0.eye.w = 0.2
        $0.eye.h = 0.16
        $0.eye.round = 0.0
        $0.pupil0 = 0.1
        $0.blushAt = [0.58, 0.22]
        $0.paw = "#F3C894"
        $0.bean = "#E88E80"
        $0.hair = "#D98B45"
        $0.hairDark = "#9C5524"
        $0.hairLight = "#F6CF9E"
    }

    static let midnight = coat("midnight", "Midnight", "black shorthair") {
        $0.top = "#2C2C31"
        $0.bot = "#1F1F23"
        $0.rimLight = 1
        $0.inner = "#6E5A5E"
        $0.nose = "#56474D"
        $0.noseLine = "#2A2024"
        $0.iris = ["#F7D45C", "#D9921C"]
        $0.liner = "#0E0E10"
        $0.ink = "#F2D06A"
        $0.mouthLine = "#77696E"
        $0.whisk = "#D8D8DD"
        $0.padDot = "rgba(140,140,150,.5)"
        $0.eye.w = 0.2
        $0.eye.h = 0.18
        $0.paw = "#2E2E33"
        $0.bean = "#56474D"
        $0.hair = "#38383E"
        $0.hairDark = "#1A1A1D"
        $0.hairLight = "#6A6A72"
    }

    static let latte = coat("latte", "Latte", "Siamese seal point") {
        $0.coat = "point"
        $0.rx = 1.04
        $0.ry = 0.92
        $0.n = 2.0
        $0.top = "#F1E6D4"
        $0.bot = "#DCCBB2"
        $0.point = "#4A3528"
        $0.earCols = ["#4A3528", "#4A3528"]
        $0.ear.h = 0.95
        $0.ear.bw = 0.55
        $0.ear.rot = 0.5
        $0.ear.tip = 0.08
        $0.inner = "#7A5A4E"
        $0.nose = "#3E2C24"
        $0.noseLine = "#2A1C16"
        $0.iris = ["#B9E3FA", "#3F86CF"]
        $0.liner = "#2A1C16"
        $0.ink = "#CFE6F5"
        $0.mouthLine = "#8A7266"
        $0.whisk = "#F5EFE6"
        $0.padDot = "rgba(30,20,15,.5)"
        $0.eye.w = 0.21
        $0.eye.h = 0.15
        $0.eye.round = 0.0
        $0.pupil0 = 0.1
        $0.paw = "#4A3528"
        $0.bean = "#7A5A50"
        $0.hair = "#D8C6AC"
        $0.hairDark = "#8A7058"
        $0.hairLight = "#F4EADA"
    }

    static let patches = coat("patches", "Patches", "calico") {
        $0.coat = "calico"
        $0.top = "#F7F3EE"
        $0.bot = "#E6DFD6"
        $0.earCols = ["#E3994E", "#2C2B2F"]
        $0.patches = [
            Patch(-0.48, -0.36, 0.5, 0.4, 0.3, "#E3994E", 1),
            Patch(0.52, -0.56, 0.55, 0.36, -0.4, "#2C2B2F", 2),
            Patch(0.66, 0.3, 0.22, 0.15, 0.2, "#E3994E", 3),
            Patch(-0.78, 0.36, 0.16, 0.12, -0.3, "#2C2B2F", 4)
        ]
        $0.inner = "#F2B6B8"
        $0.nose = "#F0A0AE"
        $0.noseLine = "#C07884"
        $0.iris = ["#C9DA7A", "#6F9A3A"]
        $0.liner = "#2A2420"
        $0.ink = "#2A2420"
        $0.mouthLine = "#B09A94"
        $0.whisk = "#CFC8C0"
        $0.padDot = "rgba(170,150,140,.55)"
        $0.paw = "#F7F3EE"
        $0.bean = "#F0A0AE"
        $0.hair = "#D9B48C"
        $0.hairDark = "#8A6A4A"
        $0.hairLight = "#F4E6D4"
    }

    static let blue = coat("blue", "Blue", "British shorthair") {
        $0.rx = 1.22
        $0.ry = 0.92
        $0.n = 2.5
        $0.top = "#9AA4B2"
        $0.bot = "#7A8494"
        $0.muzzle = "#A9B2BF"
        $0.ear.h = 0.62
        $0.ear.bw = 0.5
        $0.ear.rot = 0.55
        $0.ear.tip = 0.12
        $0.ear.cx = 0.8
        $0.inner = "#B8A0A8"
        $0.nose = "#6E6C7A"
        $0.noseLine = "#4C4A56"
        $0.noseW = 0.17
        $0.nosePh = -0.4
        $0.iris = ["#F6B44A", "#D2741E"]
        $0.liner = "#2E3038"
        $0.ink = "#2E3038"
        $0.mouthLine = "#5A5C68"
        $0.whisk = "#EEF0F4"
        $0.padDot = "rgba(70,76,90,.45)"
        $0.eye.w = 0.21
        $0.eye.h = 0.19
        $0.pupil0 = 0.22
        $0.paw = "#9AA4B2"
        $0.bean = "#6E6C7A"
        $0.hair = "#8E98A6"
        $0.hairDark = "#5E6878"
        $0.hairLight = "#C2CAD4"
    }

    static let snow = coat("snow", "Snow", "white longhair, odd-eyed") {
        $0.fluff = 1.0
        $0.ruff = Ruff(rx: 1.24, ry: 0.92, dy: 0.16, col: ["#F2EFEA", "#D9D3CA"])
        $0.bib = "#FFFFFF"
        $0.top = "#F5F3EF"
        $0.bot = "#E2DED7"
        $0.ear.h = 0.82
        $0.ear.bw = 0.48
        $0.ear.tuft = 1.0
        $0.inner = "#F4B8BE"
        $0.nose = "#F2A6B0"
        $0.noseLine = "#C9808C"
        $0.iris = ["#BCE4FA", "#4A90D6"]
        $0.irisR = ["#F4DC7A", "#D49A2A"]
        $0.liner = "#3A3433"
        $0.ink = "#3A3433"
        $0.mouthLine = "#C0B4B0"
        $0.whisk = "#D8D2CC"
        $0.padDot = "rgba(180,165,160,.55)"
        $0.paw = "#F5F3EF"
        $0.bean = "#F2A6B0"
        $0.hair = "#EDE8E0"
        $0.hairDark = "#B8B0A6"
        $0.hairLight = "#FFFFFF"
    }

    static let oreo = coat("oreo", "Oreo", "black-and-white tuxedo") {
        $0.coat = "tuxedo"
        $0.top = "#1C1C1F"
        $0.bot = "#131315"
        $0.rimLight = 1
        $0.white = "#F6F4F1"
        $0.furOpts = FurOpts(n: 700, l0: 0.025, l1: 0.03, w: 0.008, dark: "rgba(0,0,0,.5)", light: "rgba(96,98,108,.42)", wDark: "rgba(196,190,184,.55)", wLight: "rgba(255,255,255,.5)")
        $0.ear.h = 0.86
        $0.ear.bw = 0.54
        $0.ear.rot = 0.46
        $0.ear.tip = 0.08
        $0.ear.cx = 0.66
        $0.inner = "#8A646C"
        $0.nose = "#F2A4B2"
        $0.noseLine = "#C27886"
        $0.noseW = 0.22
        $0.noseH = 0.14
        $0.nosePh = -0.46
        $0.iris = ["#7FA82A", "#DDEB5A"]
        $0.liner = "#0B0B0D"
        $0.ink = "#D8EE5E"
        $0.mouthLine = "#A39A98"
        $0.whisk = "#FFFFFF"
        $0.padDot = "rgba(150,142,138,.6)"
        $0.whisk2.x0 = 0.17
        $0.whisk2.len = 1.4
        $0.eye.w = 0.2
        $0.eye.h = 0.18
        $0.pupil0 = 0.22
        $0.paw = "#F6F4F1"
        $0.bean = "#F2A4B2"
        $0.hair = "#2A2A2E"
        $0.hairDark = "#101012"
        $0.hairLight = "#F2F0EC"
    }

    static let mocha = coat("mocha", "Mocha", "tortoiseshell") {
        $0.coat = "calico"
        $0.top = "#30241F"
        $0.bot = "#1F1713"
        $0.rimLight = 1
        $0.earCols = ["#C9772F", "#30241F"]
        $0.patches = [
            Patch(-0.52, -0.5, 0.17, 0.11, 0.6, "#C9772F", 1),
            Patch(-0.4, -0.62, 0.07, 0.05, 0.2, "#E2A866", 2),
            Patch(0.06, -0.62, 0.06, 0.2, 0.1, "#C9772F", 3),
            Patch(0.56, -0.3, 0.15, 0.09, -0.5, "#C9772F", 4),
            Patch(0.84, 0.12, 0.11, 0.08, 0.4, "#E2A866", 5),
            Patch(-0.82, 0.16, 0.14, 0.1, -0.5, "#C9772F", 6),
            Patch(-0.32, 0.6, 0.13, 0.07, 0.25, "#E2A866", 7),
            Patch(0.4, 0.58, 0.11, 0.07, -0.3, "#C9772F", 8),
            Patch(0.36, -0.74, 0.09, 0.05, 0.3, "#E2A866", 9),
            Patch(-0.66, 0.42, 0.07, 0.05, 0.0, "#E2A866", 10)
        ]
        $0.inner = "#7A5A54"
        $0.nose = "#6E4A42"
        $0.noseLine = "#3A2420"
        $0.iris = ["#F6C44C", "#C2761A"]
        $0.liner = "#120C0A"
        $0.ink = "#F2C45C"
        $0.mouthLine = "#8A6E64"
        $0.whisk = "#EADFD0"
        $0.padDot = "rgba(150,120,100,.5)"
        $0.eye.w = 0.2
        $0.eye.h = 0.17
        $0.paw = "#6A4630"
        $0.bean = "#2A1C18"
        $0.hair = "#6A4A34"
        $0.hairDark = "#2A1F1A"
        $0.hairLight = "#D89A58"
    }

    static let silver = coat("silver", "Silver", "silver tabby") {
        $0.coat = "tabby"
        $0.top = "#D6DADF"
        $0.bot = "#A8AEB6"
        $0.light = "#EEF0F2"
        $0.chinCol = "#FFFFFF"
        $0.stripe = "#1D1F23"
        $0.inner = "#E6BDB8"
        $0.nose = "#C2655C"
        $0.noseLine = "#7C3832"
        $0.iris = ["#CBE27A", "#4C983C"]
        $0.liner = "#16171A"
        $0.ink = "#1D1F23"
        $0.mouthLine = "#6E6A6C"
        $0.whisk = "#FFFFFF"
        $0.padDot = "#2A2C30"
        $0.eye.w = 0.2
        $0.eye.h = 0.16
        $0.eye.round = 0.0
        $0.pupil0 = 0.1
        $0.blushAt = [0.58, 0.22]
        $0.paw = "#D6DADF"
        $0.bean = "#C2655C"
        $0.hair = "#BCC1C8"
        $0.hairDark = "#3A3C42"
        $0.hairLight = "#F2F4F6"
    }

    static let cloud = coat("cloud", "Cloud", "Ragdoll") {
        $0.coat = "point"
        $0.fluff = 1.0
        $0.ruff = Ruff(rx: 1.3, ry: 0.98, dy: 0.2, col: ["#F7F2E9", "#DED4C4"])
        $0.bib = "#FFFFFF"
        $0.rx = 1.14
        $0.ry = 0.92
        $0.n = 2.3
        $0.top = "#F4EFE6"
        $0.bot = "#DCD3C6"
        $0.point = "#7D8796"
        $0.earCols = ["#7D8796", "#7D8796"]
        $0.muzzle = "#FBF9F6"
        $0.ear.h = 0.84
        $0.ear.bw = 0.5
        $0.ear.tuft = 1.0
        $0.inner = "#C4A8AE"
        $0.nose = "#D49AA4"
        $0.noseLine = "#A0707A"
        $0.iris = ["#6FA8F2", "#2C64D6"]
        $0.liner = "#232A36"
        $0.ink = "#8FC0F8"
        $0.mouthLine = "#A89CA0"
        $0.whisk = "#FFFFFF"
        $0.padDot = "rgba(110,116,130,.45)"
        $0.eye.w = 0.22
        $0.eye.h = 0.2
        $0.pupil0 = 0.22
        $0.paw = "#FFFFFF"
        $0.bean = "#D49AA4"
        $0.hair = "#E8E2D8"
        $0.hairDark = "#8A92A0"
        $0.hairLight = "#FFFFFF"
    }

    static let leo = coat("leo", "Leo", "Bengal") {
        $0.coat = "calico"
        $0.top = "#D9A050"
        $0.bot = "#B97A30"
        $0.muzzle = "#F4E2C0"
        $0.ear.h = 0.74
        $0.ear.bw = 0.5
        $0.ear.rot = 0.5
        $0.ear.tip = 0.1
        $0.ear.cx = 0.75
        $0.patches = [
            Patch(-0.1, -0.6, 0.024, 0.17, 0.14, "#3E2412", 11),
            Patch(0.1, -0.6, 0.024, 0.17, -0.14, "#3E2412", 12),
            Patch(0.0, -0.7, 0.022, 0.12, 0.0, "#3E2412", 13),
            Patch(-0.84, 0.1, 0.15, 0.022, -0.3, "#3E2412", 14),
            Patch(0.84, 0.1, 0.15, 0.022, 0.3, "#3E2412", 15),
            Patch(-0.6, -0.42, 0.12, 0.095, 0.4, "#4A2A14", 1),
            Patch(-0.6, -0.42, 0.06, 0.045, 0.4, "#9C5E24", 1),
            Patch(0.62, -0.4, 0.12, 0.095, -0.3, "#4A2A14", 2),
            Patch(0.62, -0.4, 0.06, 0.045, -0.3, "#9C5E24", 2),
            Patch(-0.34, -0.76, 0.12, 0.095, 0.2, "#4A2A14", 3),
            Patch(-0.34, -0.76, 0.06, 0.045, 0.2, "#9C5E24", 3),
            Patch(0.36, -0.76, 0.12, 0.095, -0.2, "#4A2A14", 4),
            Patch(0.36, -0.76, 0.06, 0.045, -0.2, "#9C5E24", 4),
            Patch(-0.84, 0.36, 0.12, 0.095, 0.3, "#4A2A14", 5),
            Patch(-0.84, 0.36, 0.06, 0.045, 0.3, "#9C5E24", 5),
            Patch(0.86, 0.36, 0.12, 0.095, -0.3, "#4A2A14", 6),
            Patch(0.86, 0.36, 0.06, 0.045, -0.3, "#9C5E24", 6),
            Patch(-0.55, 0.6, 0.12, 0.095, 0.2, "#4A2A14", 7),
            Patch(-0.55, 0.6, 0.06, 0.045, 0.2, "#9C5E24", 7),
            Patch(0.57, 0.6, 0.12, 0.095, -0.2, "#4A2A14", 8),
            Patch(0.57, 0.6, 0.06, 0.045, -0.2, "#9C5E24", 8)
        ]
        $0.inner = "#E2B49A"
        $0.nose = "#C66E58"
        $0.noseLine = "#7A3A28"
        $0.iris = ["#DADC62", "#6C9A32"]
        $0.liner = "#24160C"
        $0.ink = "#24160C"
        $0.mouthLine = "#7A5034"
        $0.whisk = "#FFF6E6"
        $0.padDot = "#3A2412"
        $0.eye.w = 0.2
        $0.eye.h = 0.15
        $0.eye.round = 0.0
        $0.pupil0 = 0.1
        $0.blushAt = [0.58, 0.24]
        $0.paw = "#E2B470"
        $0.bean = "#4A2C18"
        $0.hair = "#D09048"
        $0.hairDark = "#4A2C16"
        $0.hairLight = "#F2D29A"
    }

    static let button = coat("button", "Button", "Scottish Fold") {
        $0.rx = 1.2
        $0.ry = 0.94
        $0.n = 2.5
        $0.top = "#BCA9B3"
        $0.bot = "#988592"
        $0.ear.h = 0.58
        $0.ear.bw = 0.46
        $0.ear.rot = 0.62
        $0.ear.tip = 0.2
        $0.ear.cx = 0.9
        $0.ear.fold = 1.0
        $0.inner = "#C9A4AC"
        $0.nose = "#B88A96"
        $0.noseLine = "#7E5A66"
        $0.noseW = 0.17
        $0.iris = ["#F8A642", "#C2561A"]
        $0.liner = "#2E2630"
        $0.ink = "#2E2630"
        $0.mouthLine = "#6E6068"
        $0.whisk = "#F4EEF0"
        $0.padDot = "rgba(90,70,80,.4)"
        $0.eye.w = 0.22
        $0.eye.h = 0.21
        $0.pupil0 = 0.24
        $0.paw = "#BCA9B3"
        $0.bean = "#B88A96"
        $0.hair = "#ADA0A6"
        $0.hairDark = "#7A6C74"
        $0.hairLight = "#D8CED2"
    }

    static let puff = coat("puff", "Puff", "Persian") {
        $0.fluff = 1.0
        $0.ruff = Ruff(rx: 1.46, ry: 1.08, dy: 0.2, col: ["#F3E4C8", "#D8C09A"])
        $0.bib = "#FFFFFF"
        $0.rx = 1.24
        $0.ry = 0.94
        $0.n = 2.6
        $0.top = "#EED8B4"
        $0.bot = "#D4B488"
        $0.earSpread = 0.86
        $0.ear.h = 0.5
        $0.ear.bw = 0.42
        $0.ear.rot = 0.62
        $0.ear.tip = 0.12
        $0.ear.cx = 0.8
        $0.ear.tuft = 1.0
        $0.nosePh = -0.3
        $0.noseW = 0.15
        $0.noseH = 0.1
        $0.inner = "#F0B8B0"
        $0.nose = "#E89A94"
        $0.noseLine = "#B06A64"
        $0.iris = ["#F8B04A", "#C8601A"]
        $0.liner = "#3A2A20"
        $0.ink = "#3A2A20"
        $0.mouthLine = "#A88A78"
        $0.whisk = "#FFF8EE"
        $0.padDot = "rgba(170,140,110,.5)"
        $0.whisk2.len = 1.2
        $0.eye.th = 0.45
        $0.eye.w = 0.22
        $0.eye.h = 0.21
        $0.pupil0 = 0.24
        $0.paw = "#F3E4C8"
        $0.bean = "#E89A94"
        $0.hair = "#EAD6B4"
        $0.hairDark = "#B89A70"
        $0.hairLight = "#FFF6E6"
    }

    static let noodle = coat("noodle", "Noodle", "Sphynx") {
        $0.hairless = 1
        $0.wrinkles = 1
        $0.rx = 1.04
        $0.ry = 0.94
        $0.n = 2.0
        $0.top = "#E8C1AE"
        $0.bot = "#CF9F8C"
        $0.earSpread = 0.86
        $0.ear.h = 1.1
        $0.ear.bw = 0.62
        $0.ear.rot = 0.58
        $0.ear.tip = 0.1
        $0.ear.cx = 0.75
        $0.inner = "#EBA898"
        $0.nose = "#D88A7C"
        $0.noseLine = "#A45E50"
        $0.iris = ["#F6F07A", "#C9C42E"]
        $0.liner = "#3A2620"
        $0.ink = "#3A2620"
        $0.mouthLine = "#A87464"
        $0.whisk = "#F4E2D8"
        $0.padDot = "rgba(170,110,95,.4)"
        $0.whisk2.wcols = [1]
        $0.whisk2.len = 0.85
        $0.whisk2.alpha = 0.5
        $0.whisk2.brow = 1
        $0.eye.w = 0.21
        $0.eye.h = 0.15
        $0.eye.round = 0.0
        $0.pupil0 = 0.1
        $0.paw = "#E8C1AE"
        $0.bean = "#D88A7C"
        $0.hair = "#E0B6A2"
        $0.hairDark = "#A87A66"
        $0.hairLight = "#F6DED2"
    }
}
```

- [ ] **Step 4: Run the test**

Run: `bash scripts/test-cat-presets.sh`
Expected: PASS

- [ ] **Step 5: Prove the test bites**

Change Shrimpy's `nosePh: -0.36` to `-0.37` in `CatPresets.swift`, run `bash scripts/test-cat-presets.sh`, and see `$.nosePh: -0.37 vs -0.36` fail for the coat and its kitten. Change it back and run the test again.

- [ ] **Step 6: Commit**

```bash
git add tests/CatTestSupport.swift tests/CatPresetsTests.swift scripts/test-cat-presets.sh NotchBuddy/Sources/App/CatPresets.swift
git commit -m "feat(cat): the 16 coats, their kittens and the frozen IDs in Swift, tested against presets.json

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Geometry in Swift: the pose, the face warp, the layout and ear headroom (stage 1)

Agent: `nm-implementer-light`.

**Files:**
- Create: `tests/CatGeometryTests.swift`, `scripts/test-cat-geometry.sh`
- Create: `NotchBuddy/Sources/App/CatMath.swift`, `NotchBuddy/Sources/App/CatGeometry.swift`

**Interfaces:**
- Consumes: `CatPreset`, `CatPresets` (Task 1); `tests/fixtures/cat/geometry-cases.json` and `warp-cases.json`.
- Produces in `CatMath.swift`: `CatMath.tau`; global `lerp(_:_:_:)`, `clamp(_:_:_:)`, `seg(_:_:_:)` (0 up to 1 over a to b), `wrapA(_:)`, `tm(_:_:_:)` (lo at 0, 1 at 0.5, hi at 1), `hexRGB(_:) -> [Double]` (0...255); `enum CatEase` (`out`, `inOut`, `back`, `lin`, `in`; `at(_ t:) -> Double`); `final class CatRNG` (`init(seed: UInt32)`, `next() -> Double`, a 32-bit LCG: the same sequence as `rng(seed)` in the core).
- Produces in `CatGeometry.swift`: `enum PoseKey: String, CaseIterable` (the 29 animatable properties); `struct CatPose` (all at rest by default, `subscript(PoseKey) -> Double`); `enum CatGeometry` with `Face` (the warp constants), `detailFullMin` (28), `isFull(_ D:)`, `compactEarScale` (0.8), `earScale(_ D:)`, `detailLevel(_ D:override:) -> DetailLevel` (`detail`, `full` and `flatFill`: the compact detail draws flat fills below Ø28), `FlatFill` (the flat drawing's numbers), `mixHex(_:_:_:)`, `flatFillColors(_:) -> FlatColors` (the flat head, ear, ruff and point-mask colours of a coat), `outlineSteps(_ R:)`, `badgeSide(compactNotch:) -> Double`, `cursorLook(dx:dy:) -> (x, y)`, `pupilOffset(yaw:pitch:w:h:)`, `faceAngles(_ s:) -> (yf, pf, pt, fa)`, `supPoints(rx:ry:n:dy:spike:count:steps:bend:)`, `typealias Warp = (Double, Double) -> (Double, Double)`, `makeWarp(_:yaw:pt:R:)`, `momoWhite`, `Ear`, `earGeom(_:_:sd:R:yf:pf:ek:)`, `Eye`, `Nose`, `Badge`, `Options` (`full`, `time`, `badgeSide`, `earScale`), `Layout` and `layout(_:_:cx:cy:D:_:) -> Layout` (head centre, warp, eyes, nose, mouth point, ears and badge in px), `earFit(_ L:_ s:ceiling:margin:minimum:) -> Double` (the factor, 0.35 to 1, that fits the ears under `ceiling`; the margin and minimum are `earFitMargin` and `earFitMinimum`), `passes` (the draw order).
- **Contract items owned by A-0b** (A-0b, merged `6adf584`): `earFit`, `detailLevel`, `FlatFill` and `flatFillColors`. They are in `design/prototype/cat-core.js` as `EAR_FIT`, `earFit`, `detailLevel`, `FLAT_FILL`, `mixHex` and `flatFillColors`, with five keys in `tests/fixtures/cat/geometry-cases.json`: `earFit` (`{margin, minimum}`), `earFitCases` (rows of `cat`, `kitten`, `D`, `cx`, `cy`, `earScale`, `pose`, `ceiling`, `margin`, `minimum` and `fit`), `flatFill` (`headMix`, `earMix`, `ruffMix`, `rimGradient`, `crown` and `point`, each of those two `{rx, ry, alpha}`), `detailLevels` (rows of `D`, `override` and `level`) and `flatColors` (per cat ID: `head`, `ears`, `ruff` and `point`, the last two null when the coat has none), and are explained in `docs/CAT-CONTRACT.md`, "Collar, ear fit and flat fills (A-0b)". Here they are consumed from the contract: this task ports the contract's `earFit` (it solves for the true highest point of the ear's top edge, and a pose that is not a number gives 1) and tests it against `earFit` and `earFitCases`; the flat point mask is the contract's `FLAT_FILL.point` (0.86 R by 0.54 R at alpha 0.85, tuned to the gradient it replaces) with its colour from `flatColors[id].point`, and the head, ear, ruff and crown numbers are the contract's too; `flatFill` is exactly `!layout().full`, so the renderer needs no new switch and the test loops over `detailLevels` and `flatColors`. The compact ear scale is the contract's too: `earScale(D)` on every compact cat, times the fit where a ceiling is given (`earScale(D) * f`), as the prototype page does. This plan never edits `cat-core.js`. The collar items of the contract (`collarGeometry`, `COLLAR_STYLES`, `COLLAR_MIN`, `collarPass`, `collar-cases.json`) are for stage 6: nothing here ports them.

- [ ] **Step 1: Write the failing test**

**Create `tests/CatGeometryTests.swift`:**

```swift
import Foundation

@main
enum CatGeometryTests {
    typealias G = CatGeometry

    static func pose(_ delta: [String: Any]) -> CatPose {
        var s = CatPose()
        for (k, v) in delta {
            guard let key = PoseKey(rawValue: k), let n = v as? NSNumber else { fatalError("unknown pose key \(k)") }
            s[key] = n.doubleValue
        }
        return s
    }
    static func preset(_ cat: String, _ kitten: Bool) -> CatPreset {
        let p = CatPresets.byID(cat)
        return kitten ? CatPresets.kitten(of: p) : p
    }
    static func num(_ x: Any?) -> Double { (x as! NSNumber).doubleValue }

    /// A layout as the fixtures hold it (the warp closure is not data).
    static func json(_ L: G.Layout) -> [String: Any] {
        let nose: [String: Any] = L.nose.visible
            ? ["visible": true, "nx": L.nose.nx, "ny": L.nose.ny, "nf": L.nose.nf, "nw": L.nose.nw, "nh": L.nose.nh, "my": L.nose.my]
            : ["visible": false]
        return [
            "R": L.R, "D": L.D, "full": L.full, "rx": L.rx, "ry": L.ry,
            "base": ["x": L.base.x, "y": L.base.y, "R": L.base.R],
            "at": ["x": L.at.x, "y": L.at.y, "R": L.at.R, "D": L.at.D],
            "head": ["x": L.head.x, "y": L.head.y],
            "yf": L.yf, "pf": L.pf, "pt": L.pt, "fa": L.fa, "steps": L.steps,
            "bend": [L.bend.0, L.bend.1],
            "ruff": ["dx": L.ruff.dx, "dy": L.ruff.dy],
            "eyes": L.eyes.map { ["sd": $0.sd, "visible": $0.visible, "x": $0.x, "y": $0.y, "fx": $0.fx, "fy": $0.fy] as [String: Any] },
            "nose": nose,
            "mouth": L.mouth.map { ["x": $0.x, "y": $0.y] as [String: Any] } ?? NSNull(),
            "ears": L.ears.map { ["sd": $0.sd, "bx": $0.bx, "by": $0.by, "rot": $0.rot, "h": $0.h, "bw": $0.bw, "tip": $0.tip, "cx": $0.cx] as [String: Any] },
            "badge": ["x": L.badge.x, "y": L.badge.y, "k": L.badge.k, "small": L.badge.small, "side": L.badge.side],
        ]
    }

    @MainActor static func main() {
        let geo = CT.fixture("geometry-cases.json"), warp = CT.fixture("warp-cases.json")

        CT.section("detail levels and the compact ear scale")
        let detail = geo["detail"] as! [String: Any]
        CT.check("the full detail starts at Ø28", G.detailFullMin, num(detail["fullMinD"]))
        for c in detail["cases"] as! [[String: Any]] {
            let D = num(c["D"])
            CT.check("Ø\(D) is \(c["detail"]!)", G.isFull(D) ? "full" : "compact", c["detail"] as! String)
        }

        CT.section("the detail levels and the flat drawing (A-0b, merged `6adf584`): `detailLevels`, `flatFill` and `flatColors` of geometry-cases.json")
        let levels = geo["detailLevels"] as! [[String: Any]]
        for c in levels {
            let D = num(c["D"]), over = c["override"] as? String, what = "Ø\(D) \(over ?? "by its width")"
            CT.checkJSON(what, got: CT.json(G.detailLevel(D, override: over)), want: c["level"]!)
            // flatFill is exactly !layout().full: the renderer needs no switch of its own, the override rows included
            let L = G.layout(CatPresets.byID("momo"), CatPose(), cx: 0, cy: 0, D: D, G.Options(full: over.map { $0 == "full" }))
            CT.check("\(what): flatFill is !layout().full", !L.full, (c["level"] as! [String: Any])["flatFill"] as! Bool)
        }
        CT.checkTrue("an override beats the width, both ways", levels.contains { ($0["override"] as? String) == "compact" && num($0["D"]) >= G.detailFullMin } && levels.contains { ($0["override"] as? String) == "full" && num($0["D"]) < G.detailFullMin })
        let crown = ["rx": G.FlatFill.crown.rx, "ry": G.FlatFill.crown.ry, "alpha": G.FlatFill.crown.alpha], point = ["rx": G.FlatFill.point.rx, "ry": G.FlatFill.point.ry, "alpha": G.FlatFill.point.alpha]
        CT.checkJSON("the numbers of the flat drawing", got: ["headMix": G.FlatFill.headMix, "earMix": G.FlatFill.earMix, "ruffMix": G.FlatFill.ruffMix, "rimGradient": G.FlatFill.rimGradient, "crown": crown, "point": point] as [String: Any], want: geo["flatFill"]!)
        let flatColors = geo["flatColors"] as! [String: Any]
        for id in CatPresets.ids { CT.checkJSON("the flat colours of \(id)", got: CT.json(G.flatFillColors(CatPresets.byID(id))), want: flatColors[id]!) }
        let ears = geo["earScale"] as! [String: Any]
        CT.checkNear("the compact ear scale", G.compactEarScale, num(ears["compactMin"]))
        for c in ears["cases"] as! [[String: Any]] { CT.checkNear("ear scale at Ø\(num(c["D"]))", G.earScale(num(c["D"])), num(c["scale"])) }

        CT.section("head and ruff outlines (Shrimpy's fluffy edge is a fixed sum of sines)")
        for o in geo["outline"] as! [[String: Any]] {
            var bend: (Double, Double)?
            if let b = o["bend"] as? [Double] { bend = (b[0], b[1]) }
            let pts = G.supPoints(rx: num(o["rx"]), ry: num(o["ry"]), n: num(o["n"]), dy: num(o["dy"]), spike: num(o["spike"]), count: num(o["count"]), steps: Int(num(o["steps"])), bend: bend)
            let idx = (o["indices"] as! [Int])
            CT.checkJSON(o["name"] as! String, got: idx.map { [pts[$0].0, pts[$0].1] }, want: o["points"]!)
        }

        CT.section("anchors: the full layout of a cat in a pose")
        for (i, c) in (geo["anchors"] as! [[String: Any]]).enumerated() {
            let cat = c["cat"] as! String, kitten = c["kitten"] as! Bool, D = num(c["D"])
            let L = G.layout(preset(cat, kitten), pose(c["pose"] as! [String: Any]), cx: num(c["cx"]), cy: num(c["cy"]), D: D,
                             G.Options(time: num(c["T"]), badgeSide: num(c["badgeSide"]), earScale: num(c["earScale"])))
            CT.checkJSON("\(i): \(cat)\(kitten ? " kitten" : "") Ø\(D)", got: json(L), want: c["layout"]!)
        }
        CT.check("the draw passes: behind, the head, then front", G.passes, geo["passes"] as! [String: [String]])

        CT.section("a missing ear.cx and a zero one both mean 0.95 (the core uses E.cx || .95)")
        var noCx = CatPresets.byID("momo"); noCx.ear.cx = nil
        var zeroCx = CatPresets.byID("momo"); zeroCx.ear.cx = 0
        for (label, p) in [("missing", noCx), ("zero", zeroCx)] { CT.checkNear("a \(label) cx is 0.95", G.earGeom(p, CatPose(), sd: 1, R: 10, yf: 0, pf: 0).cx, 0.95) }
        CT.checkNear("a real cx is kept", G.earGeom(CatPresets.byID("momo"), CatPose(), sd: 1, R: 10, yf: 0, pf: 0).cx, 0.62)

        CT.section("the face warp")
        let face = warp["face"] as! [String: Any]
        CT.checkNear("face yaw share", G.Face.yaw, num(face["yaw"])); CT.checkNear("face pitch share", G.Face.pitch, num(face["pitch"]))
        CT.checkNear("face pitch down share", G.Face.pitchDown, num(face["pitchDown"])); CT.checkNear("head lean", G.Face.lean, num(face["lean"]))
        CT.checkNear("outline bend", G.Face.bend, num(face["bend"])); CT.checkNear("muzzle depth", G.Face.muzzle, num(face["muzzle"]))
        CT.checkNear("nose depth", G.Face.nose, num(face["nose"]))
        let cursor = warp["cursor"] as! [String: Any]
        for c in cursor["cases"] as! [[String: Any]] {
            let g = G.cursorLook(dx: num(c["dx"]), dy: num(c["dy"]))
            CT.checkJSON("cursor \(num(c["dx"])), \(num(c["dy"]))", got: [g.x, g.y], want: [c["x"]!, c["y"]!])
        }
        for c in warp["angles"] as! [[String: Any]] {
            let a = G.faceAngles(pose(["yaw": c["yaw"]!, "pitch": c["pitch"]!, "lift": c["lift"]!, "roll": c["roll"]!]))
            CT.checkJSON("angles yaw \(num(c["yaw"])) pitch \(num(c["pitch"])) lift \(num(c["lift"])) roll \(num(c["roll"]))", got: [a.yf, a.pf, a.pt, a.fa], want: [c["yf"]!, c["pf"]!, c["pt"]!, c["fa"]!])
        }
        for c in warp["pupil"] as! [[String: Any]] {
            let o = G.pupilOffset(yaw: num(c["yaw"]), pitch: num(c["pitch"]), w: num(c["w"]), h: num(c["h"]))
            CT.checkJSON("pupil travel yaw \(num(c["yaw"])) pitch \(num(c["pitch"]))", got: [o.x, o.y], want: c["offset"]!)
        }
        for c in warp["warp"] as! [[String: Any]] {
            let p = CatPresets.byID(c["cat"] as? String), a = G.faceAngles(pose(["yaw": c["yaw"]!, "pitch": c["pitch"]!]))
            let W = G.makeWarp(p, yaw: a.yf, pt: a.pt, R: 1)
            let probes = c["probes"] as! [[Double]]
            CT.checkJSON("warp \(p.name) yaw \(num(c["yaw"])) pitch \(num(c["pitch"]))", got: ["yf": a.yf, "pt": a.pt, "out": probes.map { let q = W($0[0], $0[1]); return [q.0, q.1] }] as [String: Any], want: ["yf": c["yf"]!, "pt": c["pt"]!, "out": c["out"]!] as [String: Any])
        }
        for c in warp["eyes"] as! [[String: Any]] {
            let p = CatPresets.byID(c["cat"] as? String)
            let L = G.layout(p, pose(["yaw": c["yaw"]!]), cx: 0, cy: 0, D: 2 * p.rx)
            CT.checkJSON("eyes \(p.name) yaw \(num(c["yaw"]))", got: json(L)["eyes"]!, want: c["eyes"]!)
        }
        for c in warp["head"] as! [[String: Any]] {
            let p = CatPresets.byID(c["cat"] as? String)
            let L = G.layout(p, pose(["yaw": c["yaw"]!, "pitch": c["pitch"]!]), cx: 0, cy: 0, D: num(c["D"]))
            let j = json(L)
            CT.checkJSON("head \(p.name) yaw \(num(c["yaw"])) pitch \(num(c["pitch"]))", got: ["head": j["head"]!, "bend": j["bend"]!, "ruff": j["ruff"]!, "nose": j["nose"]!, "mouth": j["mouth"]!] as [String: Any],
                         want: ["head": c["head"]!, "bend": c["bend"]!, "ruff": c["ruff"]!, "nose": c["nose"]!, "mouth": c["mouth"]!] as [String: Any])
        }

        CT.section("extreme poses never produce NaN, and a head turned away hides its face")
        var finite = true, hidden = true
        for id in CatPresets.ids {
            for D in [0.0, 1, 12, 66] {
                for (yaw, pitch, roll) in [(0.0, 0.0, 0.0), (1.4, 0.0, 0.0), (-1.6, 0.0, 0.0), (3.0, 0.0, 0.0), (0.0, 2.0, 0.0), (0.0, -2.0, 0.0), (0.0, 0.0, Double.pi), (0.62, 0.5, 3.2)] {
                    var s = CatPose(); s.yaw = yaw; s.pitch = pitch; s.roll = roll; s.lift = 0.28
                    let L = G.layout(CatPresets.byID(id), s, cx: 10, cy: 10, D: D, G.Options(earScale: G.earScale(D)))
                    let nums: [Double] = [L.R, L.head.x, L.head.y, L.fa, L.badge.x, L.badge.y] + L.eyes.flatMap { [$0.x, $0.y, $0.fx, $0.fy] } + L.ears.flatMap { [$0.bx, $0.by, $0.h, $0.bw] }
                    if nums.contains(where: { !$0.isFinite }) { finite = false; print("    NaN: \(id) D\(D) yaw \(yaw) pitch \(pitch) roll \(roll)") }
                    if !L.nose.visible && L.mouth != nil { hidden = false }
                }
            }
        }
        CT.checkTrue("every number is finite for all 16 coats, head widths 0 to 66 and eight extreme poses", finite)
        CT.checkTrue("a nose turned out of sight has no mouth point", hidden)
        var away = CatPose(); away.yaw = 3.0
        let back = G.layout(CatPresets.byID("momo"), away, cx: 0, cy: 0, D: 66)
        CT.checkTrue("a head turned right round shows neither eye nor nose", back.eyes.allSatisfy { !$0.visible } && !back.nose.visible)
        CT.check("the Ø0 head has no size", G.layout(CatPresets.byID("momo"), CatPose(), cx: 0, cy: 0, D: 0).R, 0)

        CT.section("ear headroom: in the compact strip no ear tip leaves the top, a shrunk ear sits exactly on the margin, and a calm cat keeps its ears")
        // The fixture's margin and minimum, not the module's, so the check cannot move with the code. The compact notch: the cat sits at the middle of a
        // 32 pt strip (or 24 pt on a screen without a notch), Ø20 (or Ø18). Five coats, because their ears differ (Noodle's are tall, Puff's and Button's small).
        let fitFixture = geo["earFit"] as! [String: Any], margin = num(fitFixture["margin"]), minimum = num(fitFixture["minimum"])
        func tops(_ L: G.Layout, _ s: CatPose) -> Double { L.ears.map { bruteTop(L, s, $0) }.min()! }
        var shrunk = 0, headroom: [String] = []
        for (strip, D) in [(32.0, 20.0), (24.0, 18.0)] {
            for (earU, earF, oy, tilt) in [(1.0, 0.0, 0.0, 0.0), (1.4, 0.0, 0.0, 0.0), (1.4, 0.0, -0.26, 0.0), (1.22, 0.0, -0.26, 0.0), (1.4, 0.0, -0.3, 0.24), (1.4, 0.0, -0.3, -0.24), (1.1, 0.45, -0.1, 0.1)] {
                var s = CatPose(); s.earU = earU; s.earF = earF; s.oy = oy; s.tilt = tilt
                for id in ["momo", "shrimpy", "noodle", "puff", "button"] {
                    let p = CatPresets.byID(id), ek = G.earScale(D)
                    let L = G.layout(p, s, cx: 40, cy: strip / 2, D: D, G.Options(earScale: ek)), f = G.earFit(L, s, ceiling: 0)
                    let after = G.layout(p, s, cx: 40, cy: strip / 2, D: D, G.Options(earScale: ek * f))
                    let at = "\(id) strip \(strip) Ø\(D) earU \(earU) earF \(earF) oy \(oy) tilt \(tilt)"
                    if f < minimum || f > 1 { headroom.append("\(at): the factor is \(f), not \(minimum) to 1") }
                    if f == 1 {
                        if tops(L, s) < margin - 1e-3 { headroom.append("\(at): an ear that was left alone pokes out at \(tops(L, s))") }
                    } else {
                        shrunk += 1
                        if f > minimum + 1e-9 {
                            if abs(tops(after, s) - margin) > 1e-3 { headroom.append("\(at): the top of the ears is at \(tops(after, s)), not on the margin \(margin)") }
                        } else if tops(after, s) <= tops(L, s) { headroom.append("\(at): held at the minimum, the tips do not come down") }
                    }
                }
            }
        }
        CT.checkRows("5 coats, 2 strips, 7 poses: no ear leaves the strip, and a shrunk ear sits on the margin", headroom)
        CT.checkTrue("the poses do need the fit (\(shrunk) cases)", shrunk > 10)
        var calm = CatPose(); calm.earU = 1
        let calmL = G.layout(CatPresets.byID("momo"), calm, cx: 40, cy: 16, D: 20, G.Options(earScale: G.earScale(20)))
        CT.checkNear("an idle cat in the notch keeps its ears", G.earFit(calmL, calm, ceiling: 0), 1)
        let high = G.layout(CatPresets.byID("momo"), calm, cx: 40, cy: 3, D: 20, G.Options(earScale: 1))
        CT.checkTrue("a cat too close to the top gets smaller ears, never smaller than 0.35", G.earFit(high, calm, ceiling: 0) < 1 && G.earFit(high, calm, ceiling: 0) >= 0.35)

        CT.section("ear headroom against the contract (A-0b, merged `6adf584`): `earFit` and `earFitCases` of geometry-cases.json")
        let contractFit = geo["earFit"] as! [String: Any]
        CT.checkNear("the margin under the ceiling", G.earFitMargin, num(contractFit["margin"]))
        CT.checkNear("the smallest factor", G.earFitMinimum, num(contractFit["minimum"]))
        var fitDiffs: [String] = []
        let fitCases = geo["earFitCases"] as! [[String: Any]]
        for (i, c) in fitCases.enumerated() {
            let s = pose(c["pose"] as! [String: Any]), p = preset(c["cat"] as! String, c["kitten"] as! Bool)
            let L = G.layout(p, s, cx: num(c["cx"]), cy: num(c["cy"]), D: num(c["D"]), G.Options(earScale: num(c["earScale"])))
            let got = G.earFit(L, s, ceiling: num(c["ceiling"]), margin: num(c["margin"]), minimum: num(c["minimum"])), want = num(c["fit"])
            if abs(got - want) > 1e-9 { fitDiffs.append("case \(i) \(p.name) Ø\(num(c["D"])): \(got) vs \(want)") }
        }
        CT.checkRows("\(fitCases.count) contract cases", fitDiffs)

        CT.section("ear fit: a head of width 0, a cat upside down and a pose that is not a number give a number in range, never NaN")
        func fitOf(_ p: CatPreset, _ s: CatPose, D: Double) -> Double {
            G.earFit(G.layout(p, s, cx: 40, cy: 16, D: D, G.Options(earScale: G.earScale(D))), s, ceiling: 0)
        }
        CT.check("a head of width 0 needs no fit", fitOf(CatPresets.byID("momo"), CatPose(), D: 0), 1)
        var weird: [CatPose] = []
        for (k, v) in [("tilt", Double.pi), ("tilt", .nan), ("sy", .infinity), ("sx", .nan), ("tilt", 20)] {
            var s = CatPose(); s[PoseKey(rawValue: k)!] = v
            if k == "tilt" && v == .pi { s.earU = 1.4 }
            if k == "tilt" && v == 20 { s.earU = 9 }
            if k == "sx" { s.oy = .nan }
            weird.append(s)
        }
        for (i, s) in weird.enumerated() {
            let f = fitOf(CatPresets.byID("noodle"), s, D: 20)
            CT.checkTrue("pose \(i): \(f) is finite and between 0.35 and 1", f.isFinite && f >= 0.35 && f <= 1)
        }
        var notANumber = CatPose(); notANumber.tilt = .nan
        CT.check("a tilt that is not a number leaves nothing to fit: 1", fitOf(CatPresets.byID("momo"), notANumber, D: 20), 1)
        CT.finish()
    }

    /// The highest point of an ear in the world (the smallest y), found by walking the whole outline the renderer draws, not by the formula under test.
    static func bruteTop(_ L: G.Layout, _ s: CatPose, _ e: G.Ear) -> Double {
        let R = L.R, h = e.h, bw = e.bw, tip = e.tip, cx = e.cx
        // The three curves of the ear's outline, in ear space: the left side, the top edge and the right side (a start, a control point and an end each).
        let curves: [[(Double, Double)]] = [
            [(-bw, 0.25 * R), (-bw * cx, -h * 0.4), (-tip * 0.9, -h + tip * 1.3)],
            [(-tip * 0.9, -h + tip * 1.3), (0, -h - tip * 0.35), (tip * 0.9, -h + tip * 1.3)],
            [(tip * 0.9, -h + tip * 1.3), (bw * cx, -h * 0.4), (bw, 0.25 * R)],
        ]
        var best = Double.infinity
        for q in curves {
            for i in 0...400 {
                let t = Double(i) / 400, m = 1 - t
                let x = m * m * q[0].0 + 2 * m * t * q[1].0 + t * t * q[2].0, y = m * m * q[0].1 + 2 * m * t * q[1].1 + t * t * q[2].1
                // ear space -> head space (rotate by rot, move to the base) -> world (tilt, squash, head position)
                let hx = e.bx + x * cos(e.rot) - y * sin(e.rot), hy = e.by + x * sin(e.rot) + y * cos(e.rot)
                best = min(best, L.head.y + sin(s.tilt) * s.sx * hx + cos(s.tilt) * s.sy * hy)
            }
        }
        return best
    }
}
```

**Create `scripts/test-cat-geometry.sh`:**

```bash
#!/usr/bin/env bash
# Cat geometry: outlines, anchors, the face warp, gaze maths and ear headroom against geometry-cases.json and warp-cases.json.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-geometry.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/CatMath.swift NotchBuddy/Sources/App/CatPresets.swift NotchBuddy/Sources/App/CatGeometry.swift \
    tests/CatTestSupport.swift tests/CatGeometryTests.swift \
    -o "$TEST_DIR/cat-geometry-tests"
"$TEST_DIR/cat-geometry-tests"
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-geometry.sh`
Expected: FAIL (swiftc cannot open `NotchBuddy/Sources/App/CatMath.swift`)

- [ ] **Step 3: Write the helpers and the geometry**

`CatMath.swift` holds what the core calls its helpers and the seeded PRNG. `CatGeometry.swift` is the "Geometry" section of the core. `earFit` solves, in closed form, how far to shrink the ears so that no ear rises above a ceiling (an ear's height is linear in the ear scale, so no search is needed). It is the contract's `earFit` (A-0b, merged `6adf584`), ported: it solves for the true highest point of the ear's top edge, and a pose that is not a number gives 1, so the contract's version decides, and Step 1 tests this one against the contract's `earFitCases` as well as against a brute-force outline. `detailLevel`, `FlatFill` and `flatFillColors` are the contract's too; Task 4's renderer draws from them.

**Create `NotchBuddy/Sources/App/CatMath.swift`:**

```swift
import Foundation

// The small maths every cat file shares: helpers, the easing curves and the seeded PRNG. Port of the "Helpers" section of
// design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/motion-cases.json pins the easings and the PRNG.

/// The small maths helpers every cat file shares.
enum CatMath {
    static let tau = Double.pi * 2
}

func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, v)) }
/// 0 up to 1 over a to b.
func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a), 0, 1) }
/// An angle wrapped to [-π, π).
func wrapA(_ a: Double) -> Double {
    let tau = CatMath.tau
    return (((a + Double.pi).truncatingRemainder(dividingBy: tau)) + tau).truncatingRemainder(dividingBy: tau) - Double.pi
}
/// Maps a trait to a multiplier: lo at 0, 1 at 0.5, hi at 1.
func tm(_ v: Double, _ lo: Double, _ hi: Double) -> Double { v < 0.5 ? lerp(lo, 1, v / 0.5) : lerp(1, hi, (v - 0.5) / 0.5) }
/// '#RRGGBB' to [r, g, b] in 0...255 (anything unreadable is black).
func hexRGB(_ h: String) -> [Double] {
    let s = h.hasPrefix("#") ? String(h.dropFirst()) : h
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return [0, 0, 0] }
    return [Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF)]
}

/// The easing curves, named like the prototype's `EZ`.
enum CatEase: String {
    case out, inOut, back, lin, `in`
    func at(_ t: Double) -> Double {
        switch self {
        case .out: return 1 - pow(1 - t, 3)
        case .inOut: return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case .back: return 1 + 2.7 * pow(t - 1, 3) + 1.7 * pow(t - 1, 2)
        case .lin: return t
        case .in: return t * t * t
        }
    }
}

/// The seeded PRNG: a 32-bit LCG, the same sequence on every platform. The order of calls is part of the contract.
final class CatRNG {
    private var s: UInt32
    init(seed: UInt32) { s = seed }
    func next() -> Double {
        s = s &* 1103515245 &+ 12345
        return Double(s) / 4294967296
    }
}
```

**Create `NotchBuddy/Sources/App/CatGeometry.swift`:**

```swift
import Foundation

// Everything geometric about a cat, as numbers in and numbers out: the pose, the head outline, the face warp,
// the ears, the eyes, the nose, the mouth point and the badge. Port of the "Geometry" section of
// design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/geometry-cases.json and warp-cases.json pin it.
// Units are R, the head radius, unless a name says px. No drawing here: CatRenderer consumes a `CatLayout`.

// MARK: - Pose

/// The animatable properties of a cat, by name (the engine tweens them by key).
enum PoseKey: String, CaseIterable {
    case yaw, pitch, roll, tilt, open, sx, sy, oy, ox, tint, blush, es, badgeS
    case earL, earR, earU, earF, pupil, mouth, purr, lid, lift, wh, paws
    case smile, tongue, mround, mskew, wavy
}

/// The neutral pose: every animatable property at rest. The engine's pose starts here, and `layout` reads one.
struct CatPose {
    var yaw = 0.0, pitch = 0.0, roll = 0.0, tilt = 0.0, open = 1.0, sx = 1.0, sy = 1.0, oy = 0.0, ox = 0.0
    var tint = 0.0, blush = 0.0, es = 1.0, badgeS = 0.0, earL = 0.0, earR = 0.0, earU = 1.0, earF = 0.0
    var pupil = 0.45, mouth = 0.0, purr = 0.0, lid = 0.0, lift = 0.0, wh = 0.0, paws = 0.0
    var smile = 0.0, tongue = 0.0, mround = 0.0, mskew = 0.0, wavy = 0.0

    subscript(k: PoseKey) -> Double {
        get {
            switch k {
            case .yaw: return yaw
            case .pitch: return pitch
            case .roll: return roll
            case .tilt: return tilt
            case .open: return open
            case .sx: return sx
            case .sy: return sy
            case .oy: return oy
            case .ox: return ox
            case .tint: return tint
            case .blush: return blush
            case .es: return es
            case .badgeS: return badgeS
            case .earL: return earL
            case .earR: return earR
            case .earU: return earU
            case .earF: return earF
            case .pupil: return pupil
            case .mouth: return mouth
            case .purr: return purr
            case .lid: return lid
            case .lift: return lift
            case .wh: return wh
            case .paws: return paws
            case .smile: return smile
            case .tongue: return tongue
            case .mround: return mround
            case .mskew: return mskew
            case .wavy: return wavy
            }
        }
        set {
            switch k {
            case .yaw: yaw = newValue
            case .pitch: pitch = newValue
            case .roll: roll = newValue
            case .tilt: tilt = newValue
            case .open: open = newValue
            case .sx: sx = newValue
            case .sy: sy = newValue
            case .oy: oy = newValue
            case .ox: ox = newValue
            case .tint: tint = newValue
            case .blush: blush = newValue
            case .es: es = newValue
            case .badgeS: badgeS = newValue
            case .earL: earL = newValue
            case .earR: earR = newValue
            case .earU: earU = newValue
            case .earF: earF = newValue
            case .pupil: pupil = newValue
            case .mouth: mouth = newValue
            case .purr: purr = newValue
            case .lid: lid = newValue
            case .lift: lift = newValue
            case .wh: wh = newValue
            case .paws: paws = newValue
            case .smile: smile = newValue
            case .tongue: tongue = newValue
            case .mround: mround = newValue
            case .mskew: mskew = newValue
            case .wavy: wavy = newValue
            }
        }
    }
}

// MARK: - Constants

enum CatGeometry {
    /// Head turn toward the cursor. The face is a real 3D rotation of the head ellipsoid, with the muzzle standing proud of it
    /// so it swings further than the cheeks, and the head outline leans into the turn. yaw/pitch are the share of upstream's
    /// 0.62/0.5 rad gaze the face takes; the pupils carry the rest.
    enum Face {
        static let yaw = 0.82, pitch = 0.6, pitchDown = 0.32, lean = 0.08, bend = 0.1, muzzle = 0.12, nose = 0.05
    }

    /// Head width D (px) from which the full cat is drawn; below it the compact drawing (ink eyes, no irises, stripes or whiskers).
    static let detailFullMin = 28.0
    static func isFull(_ D: Double) -> Bool { detailLevel(D).full }

    // MARK: Detail level and the flat drawing (A-0b, merged `6adf584`)

    /// What the renderer draws at head width D: `detail` ("full" or "compact"), `full`, and `flatFill`, which is on exactly when the cat is compact
    /// (below Ø28). `override` is `layout`'s explicit detail: "full" or "compact" wins over D.
    struct DetailLevel: Encodable, Equatable { var detail: String; var full: Bool; var flatFill: Bool }
    static func detailLevel(_ D: Double, override: String? = nil) -> DetailLevel {
        let full = override.flatMap { $0.isEmpty ? nil : $0 == "full" } ?? (D >= detailFullMin)
        return DetailLevel(detail: full ? "full" : "compact", full: full, flatFill: !full)
    }

    /// The flat drawing the compact detail uses (radii in R), the contract's `FLAT_FILL`. At Ø12 to Ø27 a gradient cannot be seen and costs a shading pass each,
    /// so the head is one fill, each ear one fill, the ruff one fill, there is no rim gradient, and the tabby's crown and the point's mask are one ellipse each.
    /// The point mask (0.86 R by 0.54 R) is tuned to the gradient it replaces: the same total ink.
    enum FlatFill {
        static let headMix = 0.5, earMix = 0.5, ruffMix = 0.6, rimGradient = false
        static let crown = (rx: 0.4, ry: 0.26, alpha: 0.5), point = (rx: 0.86, ry: 0.54, alpha: 0.85)
    }

    /// `a` to `b` by `t`, as [r, g, b] in 0...255, not rounded.
    static func mixHex(_ a: String, _ b: String, _ t: Double) -> [Double] {
        let y = hexRGB(b)
        return hexRGB(a).enumerated().map { lerp($0.element, y[$0.offset], t) }
    }

    /// The flat colours of a coat: the head, the two ears (left, right), the ruff (nil without one) and the point mask (nil unless the coat is `point`),
    /// [r, g, b] in 0...255, not rounded.
    struct FlatColors: Encodable, Equatable { var head: [Double]; var ears: [[Double]]; var ruff: [Double]?; var point: [Double]? }
    static func flatFillColors(_ p: CatPreset) -> FlatColors {
        func ear(_ i: Int) -> [Double] { let c = p.earCols?[i]; return mixHex(c ?? p.top, c ?? p.bot, FlatFill.earMix) }
        return FlatColors(head: mixHex(p.top, p.bot, FlatFill.headMix), ears: [ear(0), ear(1)], ruff: p.ruff.map { mixHex($0.col[1], $0.col[0], FlatFill.ruffMix) },
                          point: p.coat == "point" ? p.point.map(hexRGB) : nil)
    }

    /// The compact ears are scaled down so they keep their headroom in the compact notch: 1 from Ø28 up,
    /// easing down to `compactEarScale` at Ø20 and below. PROVISIONAL: the spec only says "ears scaled down at Ø20".
    static let compactEarScale = 0.8
    static func earScale(_ D: Double) -> Double {
        D >= detailFullMin ? 1 : lerp(compactEarScale, 1, clamp((D - 20) / (detailFullMin - 20), 0, 1))
    }

    /// Outline sample count: small heads (R under 20 px) use fewer points.
    static func outlineSteps(_ R: Double) -> Int { R < 20 ? 72 : 200 }

    /// The badge sits beside the right ear, and moves to the left in the compact notch so it never sits under the camera housing.
    static func badgeSide(compactNotch: Bool) -> Double { compactNotch ? -1 : 1 }

    /// Cursor to gaze: how far the cursor is from the cat in px, to -1…1 (tanh over 240 px across, 180 px up and down).
    static let cursorX = 240.0, cursorY = 180.0
    static func cursorLook(dx: Double, dy: Double) -> (x: Double, y: Double) {
        (tanh(dx / cursorX), -tanh(dy / cursorY))
    }

    /// Pupil travel inside the eye: up to 0.24 of the eye width across and 0.18 of its height up and down.
    static func pupilOffset(yaw: Double, pitch: Double, w: Double, h: Double) -> (x: Double, y: Double) {
        (clamp(yaw / 0.62, -1, 1) * 0.24 * w, -clamp(pitch / 0.5, -1, 1) * 0.18 * h)
    }

    /// The share of the gaze the face takes, and the roll fade: yf, pf, the warp pitch pt and the face opacity fa.
    static func faceAngles(_ s: CatPose) -> (yf: Double, pf: Double, pt: Double, fa: Double) {
        let yf = s.yaw * Face.yaw
        let pf = s.pitch * (s.pitch > 0 ? Face.pitch : Face.pitchDown)
        let pt = wrapA(pf + s.lift + s.roll)
        return (yf, pf, pt, clamp((cos(pt) - 0.05) / 0.3, 0, 1))
    }

    // MARK: Outline

    /// Superellipse outline as points, optionally with a fluffy edge (spike) on the lower half. The fluff is a fixed sum of
    /// sines, so it needs no random numbers and is identical everywhere.
    static func supPoints(rx: Double, ry: Double, n: Double, dy: Double, spike: Double, count: Double, steps: Int = 200, bend: (Double, Double)? = nil) -> [(Double, Double)] {
        let e = 2 / n
        var pts: [(Double, Double)] = []
        pts.reserveCapacity(steps + 1)
        for i in 0...steps {
            let a = Double(i) / Double(steps) * CatMath.tau, c = cos(a), s = sin(a)
            var k = 1.0
            if spike != 0 {
                let low = max(0, s + 0.55) / 1.55
                let vary = 0.55 + 0.45 * sin(a * 5.3 + 1.1) * sin(a * 2.7 + 0.4)
                k += low * spike * vary * pow(abs(cos(a * count)), 1.8)
            }
            var x = sign(c) * pow(abs(c), e) * rx * k
            var y = sign(s) * pow(abs(s), e) * ry * k + dy
            if let bend {
                let tx = x / rx, ty = y / ry
                x += bend.0 * rx * max(0, 1 - ty * ty)
                y += bend.1 * ry * max(0, 1 - tx * tx)
            }
            pts.append((x, y))
        }
        return pts
    }

    private static func sign(_ v: Double) -> Double { v > 0 ? 1 : (v < 0 ? -1 : 0) }

    // MARK: Face warp

    /// Maps a point drawn on the flat front view (units of R) onto the head ellipsoid rotated by yaw and pitch, so markings,
    /// whisker pads and the muzzle turn with the eyes. Points outside the head outline stay put. Identity at rest.
    typealias Warp = (Double, Double) -> (Double, Double)

    static func makeWarp(_ p: CatPreset, yaw: Double, pt: Double, R: Double) -> Warp {
        let a = p.rx, b = p.ry, vm = sin(p.nosePh) - 0.12
        if abs(yaw) < 1e-4 && abs(pt) < 1e-4 { return { x, y in (x * R, y * R) } }
        let cY = cos(yaw), sY = sin(yaw), cP = cos(pt), sP = sin(pt)
        return { x, y in
            let u = x / a, v = -y / b, q = 1 - u * u - v * v
            if q <= 0 { return (x * R, y * R) }
            let du = u / 0.55, dv = (v - vm) / 0.45
            let w = q.squareRoot() + Face.muzzle * exp(-(du * du + dv * dv))
            let u1 = u * cY + w * sY, w1 = w * cY - u * sY, v1 = v * cP + w1 * sP
            return (u1 * a * R, -v1 * b * R)
        }
    }

    /// Momo's white map (the tuxedo blaze, muzzle and chin), as a dense point list so the warp can bend every edge.
    static let momoWhite: [(Double, Double)] = {
        enum Cmd { case m(Double, Double), q(Double, Double, Double, Double), l(Double, Double) }
        let cmds: [Cmd] = [.m(0, -0.6), .q(-0.13, -0.4, -0.17, -0.12), .q(-0.19, 0.1, -0.26, 0.2), .q(-0.5, 0.38, -0.8, 0.36), .l(-1.3, 0.3), .l(-1.3, 1.3), .l(1.3, 1.3), .l(1.3, 0.3), .l(0.8, 0.36), .q(0.5, 0.38, 0.26, 0.2), .q(0.19, 0.1, 0.17, -0.12), .q(0.13, -0.4, 0, -0.6)]
        var out: [(Double, Double)] = [], px = 0.0, py = 0.0
        for c in cmds {
            switch c {
            case .m(let x, let y): px = x; py = y; out.append((px, py))
            case .q(let cx, let cy, let x, let y):
                for i in 1...10 {
                    let t = Double(i) / 10, m = 1 - t
                    out.append((m * m * px + 2 * m * t * cx + t * t * x, m * m * py + 2 * m * t * cy + t * t * y))
                }
                px = x; py = y
            case .l(let x, let y):
                for i in 1...8 {
                    let t = Double(i) / 8
                    out.append((px + (x - px) * t, py + (y - py) * t))
                }
                px = x; py = y
            }
        }
        return out
    }()

    // MARK: Ears

    struct Ear {
        var sd: Double, bx: Double, by: Double, rot: Double, h: Double, bw: Double, tip: Double, cx: Double
    }

    /// One ear, in head-local px before tilt and squash. `ek` is the compact ear scale (earScale), 1 when not compact.
    static func earGeom(_ p: CatPreset, _ s: CatPose, sd: Double, R: Double, yf: Double, pf: Double, ek: Double = 1) -> Ear {
        let E = p.ear, rx = p.rx * R, ry = p.ry * R, th = sd * 0.6 + yf * 0.85, f = max(0.3, cos(th))
        return Ear(sd: sd,
                   bx: sin(th) * p.earSpread * rx + sin(yf) * Face.bend * 0.54 * rx,
                   by: -0.68 * ry - sin(pf + s.lift) * 0.12 * ry,
                   rot: sd * (E.rot + (sd < 0 ? s.earL : s.earR) + 0.95 * s.earF),
                   h: E.h * R * s.earU * (1 - 0.4 * s.earF) * ek,
                   bw: E.bw * R * f * ek,
                   tip: E.tip * R * ek,
                   cx: E.cx.flatMap { $0 == 0 ? nil : $0 } ?? 0.95)   // the core uses E.cx || .95, so a zero counts as missing
    }

    // MARK: Layout

    struct Eye { var sd: Double, visible: Bool, x: Double, y: Double, fx: Double, fy: Double }
    struct Nose { var visible: Bool, nx = 0.0, ny = 0.0, nf = 0.0, nw = 0.0, nh = 0.0, my = 0.0 }
    struct Badge { var x: Double, y: Double, k: Double, small: Bool, side: Double }

    struct Options {
        /// nil: by head width (full from Ø28).
        var full: Bool?
        var time = 0.0
        /// +1 beside the right ear, -1 beside the left; anything in between while the greeting moves it across.
        var badgeSide = 1.0
        var earScale = 1.0
    }

    /// Everything geometric about one cat in one pose, in px: where the head is, the warp, the eyes, the nose and mouth, the ears,
    /// the badge. Drawing code only consumes this.
    struct Layout {
        var R: Double, D: Double, full: Bool, rx: Double, ry: Double
        var base: (x: Double, y: Double, R: Double)
        var at: (x: Double, y: Double, R: Double, D: Double)
        var head: (x: Double, y: Double)
        var yf: Double, pf: Double, pt: Double, fa: Double
        var warp: Warp
        var steps: Int
        var bend: (Double, Double)
        var ruff: (dx: Double, dy: Double)
        var eyes: [Eye]
        var nose: Nose
        var mouth: (x: Double, y: Double)?
        var ears: [Ear]
        var badge: Badge
    }

    /// `p` preset, `s` pose (the engine's), `cx`/`cy` the cat's resting centre, `D` the head width.
    static func layout(_ p: CatPreset, _ s: CatPose, cx cx0: Double, cy cy0: Double, D: Double, _ o: Options = Options()) -> Layout {
        let R = D / (2 * p.rx), full = detailLevel(D, override: o.full.map { $0 ? "full" : "compact" }).full, T = o.time, ek = o.earScale, rx = p.rx * R, ry = p.ry * R
        var cx = cx0, cy = cy0
        let base = (x: cx, y: cy, R: R)
        let purr = s.purr > 0.01 ? sin(T * CatMath.tau * 24) * 0.007 * s.purr : 0
        cx += (s.ox + purr) * R
        cy += s.oy * R
        let at = (x: cx, y: cy, R: R, D: D)
        let (yf, pf, pt, fa) = faceAngles(s)
        cx += sin(s.yaw) * Face.lean * R
        cy -= sin(s.pitch) * Face.lean * 0.8 * R
        let W = makeWarp(p, yaw: yf, pt: pt, R: R)
        let eyes = [-1.0, 1.0].map { sd -> Eye in
            let th = sd * p.eye.th + yf, cp = cos(p.eye.ph + pt)
            let (x, y) = W(sin(sd * p.eye.th) * cos(p.eye.ph) * p.rx, -sin(p.eye.ph) * p.ry)
            return Eye(sd: sd, visible: cos(th) * cp > 0.04, x: x, y: y,
                       fx: clamp(cos(th) / cos(p.eye.th), 0.55, 1.08), fy: clamp(cp / cos(p.eye.ph), 0.18, 1.08))
        }
        var nose = Nose(visible: false)
        var mouth: (x: Double, y: Double)?
        if cos(yf) * cos(p.nosePh + pt) > 0.04 {
            let (nx0, ny0) = W(0, -sin(p.nosePh) * p.ry)
            let nx = nx0 + sin(yf) * Face.nose * R, ny = ny0 - sin(pf) * Face.nose * 0.8 * R
            let nf = max(0.3, cos(yf)), nw = p.noseW * R * nf, nh = p.noseH * R, my = ny + nh / 2
            nose = Nose(visible: true, nx: nx, ny: ny, nf: nf, nw: nw, nh: nh, my: my)
            let lx = nx * s.sx, ly = (my + 0.12 * R) * s.sy, c = cos(s.tilt), sn = sin(s.tilt)
            mouth = (cx + lx * c - ly * sn, cy + lx * sn + ly * c)
        }
        let side = o.badgeSide == 0 ? 1 : o.badgeSide
        return Layout(R: R, D: D, full: full, rx: rx, ry: ry, base: base, at: at, head: (cx, cy), yf: yf, pf: pf, pt: pt, fa: fa,
                      warp: W, steps: outlineSteps(R),
                      bend: (sin(yf) * Face.bend, -sin(pf) * Face.bend * 0.7),
                      ruff: (-sin(s.yaw) * Face.lean * 1.1 * R, sin(s.pitch) * Face.lean * 0.9 * R),
                      eyes: eyes, nose: nose, mouth: mouth,
                      ears: [-1.0, 1.0].map { earGeom(p, s, sd: $0, R: R, yf: yf, pf: pf, ek: ek) },
                      badge: Badge(x: cx + side * 1.4 * R * s.sx, y: cy - 0.92 * R * s.sy, k: s.badgeS * (full ? 1 : 1.25), small: !full, side: side))
    }

    /// The factor (0.35 to 1) to multiply the ear scale by so that no ear rises above `ceiling`, a y in the same coordinates as the layout (the top edge of
    /// the strip the cat lives in, for the compact notch). 1 means the ears already fit, and so does a pose that is not a number; a cat so close to the
    /// ceiling that even the smallest ears would not fit is held at `minimum`. An ear scales about its own base, so its highest point rises in proportion to
    /// the scale and one linear solve replaces a search. The top edge of an ear is a parabola (x = 0.9 tip u, y = -h + tip (0.475 + 0.825 u²) for u in
    /// -1...1, in ear space), and the world height of an ear-space point is y0 + A x + B y, so the highest point is where u = -0.9 A / (1.65 B), held to
    /// -1...1. This is the contract's `earFit` (A-0b, merged `6adf584`), ported with JavaScript's rules for NaN (`jsMin` and `jsMax` pass it on).
    static let earFitMargin = 0.5, earFitMinimum = 0.35
    static func earFit(_ L: Layout, _ s: CatPose, ceiling: Double, margin: Double = earFitMargin, minimum: Double = earFitMinimum) -> Double {
        func jsMin(_ a: Double, _ b: Double) -> Double { a.isNaN || b.isNaN ? .nan : min(a, b) }
        func jsMax(_ a: Double, _ b: Double) -> Double { a.isNaN || b.isNaN ? .nan : max(a, b) }
        let ct = cos(s.tilt), st = sin(s.tilt)
        var f = 1.0
        for e in L.ears {
            let cr = cos(e.rot), sr = sin(e.rot)
            let A = st * s.sx * cr + ct * s.sy * sr, B = ct * s.sy * cr - st * s.sx * sr
            let y0 = L.head.y + st * s.sx * e.bx + ct * s.sy * e.by
            func rise(_ u: Double) -> Double { 0.9 * A * e.tip * u + B * (-e.h + e.tip * (0.475 + 0.825 * u * u)) }   // the top edge at u, above the ear's base (negative: higher up)
            let d = jsMin(jsMin(rise(-1), rise(1)), rise(B > 1e-9 ? jsMax(-1, jsMin(1, -0.9 * A / (1.65 * B))) : 0))
            if y0 + d >= ceiling + margin || d >= -1e-9 { continue }
            f = jsMin(f, jsMax(minimum, (ceiling + margin - y0) / d))
        }
        return f.isFinite ? max(minimum, min(1, f)) : 1
    }

    /// The draw order, as named layers. The renderer draws a *behind* pass, the head, then a *front* pass, so outfits
    /// (sub-project I) can sit behind or in front of the head. Each layer's data comes from `layout`. The collar of stage 6 goes in the
    /// front pass between `foldEars` and `whiskers` (the contract's `collarPass`, "front"); `passes` stays as A-0 pinned it.
    static let passes: [String: [String]] = [
        "behind": ["glow", "zoomTrails", "ruff", "bib", "paws", "ears"],
        "head": ["head", "markings", "tint", "rim", "blush", "eyes", "mouth", "nose"],
        "front": ["foldEars", "whiskers", "badge", "particles", "balls"],
    ]
}
```

- [ ] **Step 4: Run the test**

Run: `bash scripts/test-cat-geometry.sh`
Expected: PASS

- [ ] **Step 5: Prove the tests bite**

Each change below is made on its own, the test run with `bash scripts/test-cat-geometry.sh`, the failure seen, and the change undone before the next. All lines are in `CatGeometry.swift`.

1. Change `static let earFitMargin = 0.5, earFitMinimum = 0.35` to `static let earFitMargin = -3.0, earFitMinimum = 0.35`: the "5 coats, 2 strips, 7 poses" line, "the poses do need the fit (6 cases)" and "the margin under the ceiling" fail (the contract's cases pass their own margin, so they stay green).
2. In `earFit`, change `jsMin(f, jsMax(minimum, (ceiling + margin - y0) / d))` to `jsMin(f, jsMax(minimum, (ceiling - y0) / d))` (the margin forgotten): "92 contract cases" fails (36 differences), and so does the "5 coats" line (23 differences): the shrunk ears now sit on the ceiling and not on the margin, and ears left alone poke into it.
3. In `earFit`, change `rise(B > 1e-9 ? jsMax(-1, jsMin(1, -0.9 * A / (1.65 * B))) : 0)` to `rise(0)` (the draft's solve for the ear's apex, not the top edge): "92 contract cases" (33 differences) and the "5 coats" line (23 differences) fail. A check that only asks that no tip leaves the strip would have passed this, because the apex solve leaves the ears inside it, only less tightly fitted.
4. In `layout`, change `full = detailLevel(D, override: o.full.map { $0 ? "full" : "compact" }).full` to `full = D >= detailFullMin` (the override ignored): "Ø66.0 compact", "Ø12.0 full", "Ø28.0 compact" and "Ø27.999 full" fail on "flatFill is !layout().full".
5. In `earFit`, change `return f.isFinite ? max(minimum, min(1, f)) : 1` to `... : minimum`: "a tilt that is not a number leaves nothing to fit: 1" fails (the in-range checks still pass, which is why that one is exact).
6. In `FlatFill`, change `point = (rx: 0.86, ry: 0.54, alpha: 0.85)` to `point = (rx: 0.5, ry: 0.34, alpha: 0.85)` (the draft's mask): "the numbers of the flat drawing (2 differences)" fails.
7. In `flatFillColors`, change `point: p.coat == "point" ? p.point.map(hexRGB) : nil` to `point: nil`: "the flat colours of latte" and "the flat colours of cloud" fail (1 difference each).

Run the test again once everything is back.

- [ ] **Step 6: Commit**

```bash
git add tests/CatGeometryTests.swift scripts/test-cat-geometry.sh NotchBuddy/Sources/App/CatMath.swift NotchBuddy/Sources/App/CatGeometry.swift
git commit -m "feat(cat): geometry in Swift (outlines, face warp, layout, ear headroom), tested against geometry-cases.json and warp-cases.json

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 3: The drawing kit and the effects around the cat (stage 1)

Agent: `nm-implementer`.

**Files:**
- Create: `tests/CatBitmapSupport.swift`, `tests/CatEffectsTests.swift`, `scripts/test-cat-effects.sh`
- Create: `NotchBuddy/Sources/App/CatLook.swift`, `NotchBuddy/Sources/App/CatDrawing.swift`, `NotchBuddy/Sources/App/CatEffects.swift`

**Interfaces:**
- Consumes: `CatPreset` (Task 1); `CatPose`, `CatGeometry.Layout` (Task 2).
- Produces in `CatLook.swift`: `enum CatEye` (`pill, wide, dot, line, flat, happy, closed, spiral, heart, star, tired, wink`; `isRealistic`), `enum CatBadge` (`dots, bang, question, dot`), `enum CatParticleKind`, `struct CatParticle`, `struct CatBall` (a hairball, or a refused file in fur: `file: String?`), `struct CatPaw`, `struct CatWave`, `struct CatLook` (the one value the renderer needs: `preset`, `pose`, `eye`, `mouthOpen`, `color`, `blushBase`, `time`, `badge`, `badgeColor`, `glowColor`, `glowAlpha`, `particles`, `balls`, `zoomVelocity`, `paws`, `wave`) and `struct CatDrawOptions` (`tint`, `badgeSide`, `earCeiling`, `full`, `glow`, `badge`).
- Produces in `CatDrawing.swift`: `CatDraw.color(_:)` (a preset colour string as a cached `CGColor`), `color(_:alpha:)`, `rgb(_:_:)`, `white(_:)`, `black(_:)`, `mix(_:_:_:)`, `gradient(_:)`, `linear(_:_:from:to:)`, `radial(_:_:center:r0:r1:)` (both padded past their ends, like a Canvas gradient), `poly`, `roundRect`, `ellipse`, `circle`, `heart`, `star`, `quad`, `text(_:_:x:y:size:bold:color:anchor:)`; and the `CGContext` helpers `fill(_:_:)`, `stroke(_:_:width:cap:join:)`, `clip(_:)`. They assume a context whose y axis points down.
- Produces in `CatEffects.swift`: `drawGlow`, `drawZoomTrails`, `wavePaws(pawsOut:wave:rx:ry:)`, `drawPaw`, `drawBadge`, `drawParticles`, `drawFile`, `drawBalls`, `applyDance`.
- Produces the test helper `Bitmap` (`render`, `alpha`, `coverage`, `bounds`).

- [ ] **Step 1: Write the failing test**

**Create `tests/CatBitmapSupport.swift`:**

```swift
import CoreGraphics
import Foundation

/// Draws into a transparent RGBA bitmap whose y axis points down, like a SwiftUI Canvas, so the tests can look at pixels.
enum Bitmap {
    @MainActor static func render(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> [UInt8] {
        let cg = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cg.translateBy(x: 0, y: CGFloat(h))
        cg.scaleBy(x: 1, y: -1)
        draw(cg)
        let p = cg.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
        return Array(UnsafeBufferPointer(start: p, count: w * h * 4))
    }

    /// The alpha (0...255) of the pixel at x, y.
    static func alpha(_ px: [UInt8], _ x: Int, _ y: Int, _ w: Int) -> Int { Int(px[(y * w + x) * 4 + 3]) }

    /// How many pixels are painted at all.
    static func coverage(_ px: [UInt8]) -> Int { stride(from: 3, to: px.count, by: 4).filter { px[$0] > 8 }.count }

    /// The columns and rows where something is painted: left, top, right, bottom (nil when nothing is).
    static func bounds(_ px: [UInt8], _ w: Int) -> (left: Int, top: Int, right: Int, bottom: Int)? {
        var l = Int.max, t = Int.max, r = -1, b = -1
        for i in stride(from: 3, to: px.count, by: 4) where px[i] > 8 {
            let x = (i / 4) % w, y = (i / 4) / w
            l = min(l, x); r = max(r, x); t = min(t, y); b = max(b, y)
        }
        return r < 0 ? nil : (l, t, r, b)
    }
}
```

**Create `tests/CatEffectsTests.swift`:**

```swift
import CoreGraphics
import Foundation

@main
enum CatEffectsTests {
    typealias G = CatGeometry

    @MainActor static func layout(_ D: Double = 100) -> G.Layout {
        G.layout(CatPresets.byID("momo"), CatPose(), cx: 100, cy: 100, D: D, G.Options())
    }
    @MainActor static func cover(_ draw: (CGContext) -> Void) -> Int { Bitmap.coverage(Bitmap.render(200, 200, draw)) }

    @MainActor static func main() {
        let momo = CatPresets.byID("momo")

        CT.section("colours: the strings a preset holds")
        func comps(_ s: String) -> [Double] { CatDraw.color(s).components!.map(Double.init) }
        CT.checkJSON("#RRGGBB", got: comps("#FF8000"), want: [1, 128.0 / 255, 0, 1])
        CT.checkJSON("rgba(r,g,b,a)", got: comps("rgba(150,142,138,.6)"), want: [150.0 / 255, 142.0 / 255, 138.0 / 255, 0.6])
        CT.checkJSON("something unreadable is black", got: comps("nonsense"), want: [0, 0, 0, 1])
        CT.checkNear("an extra alpha multiplies", Double(CatDraw.color("rgba(0,0,0,.5)", alpha: 0.5).alpha), 0.25)
        CT.checkJSON("a mix of two colours", got: CatDraw.mix(CatDraw.color("#000000"), CatDraw.color("#FFFFFF"), 0.5).components!.map(Double.init), want: [0.5, 0.5, 0.5, 1])

        CT.section("text: centred, or starting or ending at x")
        func textBounds(_ anchor: CatDraw.Anchor) -> (left: Int, top: Int, right: Int, bottom: Int) {
            Bitmap.bounds(Bitmap.render(200, 60) { CatDraw.text($0, "Hello", x: 100, y: 30, size: 16, bold: false, color: CatDraw.white(1), anchor: anchor) }, 200)!
        }
        let c = textBounds(.center), l = textBounds(.left), r = textBounds(.right)
        CT.checkTrue("centred text straddles x = 100", c.left < 100 && c.right > 100)
        CT.checkTrue("left-anchored text starts at x", l.left >= 98 && l.left <= 102)
        CT.checkTrue("right-anchored text ends at x", r.right >= 98 && r.right <= 102)
        CT.checkTrue("upright, not mirrored: the glyphs sit around y = 30", c.top > 15 && c.bottom < 45)

        CT.section("the badge")
        let L = layout()
        var s = CatPose(); s.badgeS = 1
        let badgeL = G.layout(momo, s, cx: 100, cy: 100, D: 100, G.Options())
        let small = G.layout(momo, s, cx: 100, cy: 100, D: 20, G.Options())
        for kind in [CatBadge.dots, .bang, .question, .dot] {
            CT.checkTrue("\(kind) draws at full size", cover { CatEffects.drawBadge($0, kind, "#3B9EFF", badgeL, 0.3) } > 100)
            CT.checkTrue("\(kind) draws small", cover { CatEffects.drawBadge($0, kind, "#3B9EFF", small, 0.3) } > 5)
        }
        CT.checkTrue("a bang badge carries its '!' at full size only",
                     cover { CatEffects.drawBadge($0, .bang, "#F5A524", badgeL, 0) } != cover { CatEffects.drawBadge($0, .dot, "#F5A524", badgeL, 0) })
        CT.checkTrue("a hidden badge (scale 0) draws nothing", cover { CatEffects.drawBadge($0, .dots, "#3B9EFF", L, 0) } == 0)

        CT.section("particles: every kind, and nothing before it starts")
        func look(_ kind: CatParticleKind, age: Double) -> CatLook {
            var lk = CatLook(preset: momo)
            lk.particles = [CatParticle(kind: kind, x: 0, y: -0.5, vx: 0, vy: 0, age: age, life: 1.4, size: 0.2, rot: 0.4)]
            return lk
        }
        for kind in [CatParticleKind.heart, .star, .spark, .sweat, .dust, .hair, .z] {
            CT.checkTrue("\(kind) draws mid-life", cover { CatEffects.drawParticles($0, look(kind, age: 0.5), L) } > 5)
            CT.checkTrue("\(kind) waits while its age is negative", cover { CatEffects.drawParticles($0, look(kind, age: -0.1), L) } == 0)
        }

        CT.section("paws: the wave, and a paw drawn by hand")
        let wave = CatWave(now: 1000, start: 450, until: 1550)
        CT.check("no paws out, no paws", CatEffects.wavePaws(pawsOut: 0, wave: wave, rx: 50, ry: 40).count, 0)
        let waving = CatEffects.wavePaws(pawsOut: 1, wave: wave, rx: 50, ry: 40), resting = CatEffects.wavePaws(pawsOut: 1, wave: CatWave(now: 0, start: 0, until: 0), rx: 50, ry: 40)
        CT.checkTrue("the right paw rises when waving and shows its toe beans", waving[1].y < resting[1].y - 20 && waving[1].beans && !resting[1].beans)
        CT.checkTrue("a paw draws, with beans or with toe lines",
                     cover { cg in cg.translateBy(x: 100, y: 100); CatEffects.drawPaw(cg, momo, 50, CatPaw(x: 0, y: 0, k: 1, rot: 0, beans: true)) } > 50
                     && cover { cg in cg.translateBy(x: 100, y: 100); CatEffects.drawPaw(cg, momo, 50, CatPaw(x: 0, y: 0, k: 1, rot: 0, beans: false)) } > 50)
        CT.checkTrue("a paw that is barely out draws nothing", cover { cg in cg.translateBy(x: 100, y: 100); CatEffects.drawPaw(cg, momo, 50, CatPaw(x: 0, y: 0, k: 0.01, rot: 0, beans: false)) } == 0)

        CT.section("hairballs, and a refused file wrapped in fur")
        func ballLook(_ file: String?, age: Double = 0.5) -> CatLook {
            var lk = CatLook(preset: momo)
            lk.balls = [CatBall(x: 0.2, y: 0.8, vx: 0, vy: 0, rot: 0.3, age: age, life: 2.4, file: file, seed: 12345, floor: 1.12)]
            return lk
        }
        CT.checkTrue("a hairball draws", cover { CatEffects.drawBalls($0, ballLook(nil), L) } > 100)
        CT.checkTrue("a file in fur draws, and not the same as a hairball", cover { CatEffects.drawBalls($0, ballLook("EXE"), L) } != cover { CatEffects.drawBalls($0, ballLook(nil), L) })
        func ink(_ age: Double) -> Int { Bitmap.render(200, 200) { CatEffects.drawBalls($0, ballLook(nil, age: age), L) }.reduce(0) { $0 + Int($1) } }
        CT.checkTrue("it fades out over its last half second", ink(2.39) > 0 && ink(2.39) * 5 < ink(0.5))
        let again = Bitmap.render(200, 200) { CatEffects.drawBalls($0, ballLook("EXE"), L) }
        CT.checkTrue("the same ball draws the same strands every frame (seeded)", again == Bitmap.render(200, 200) { CatEffects.drawBalls($0, ballLook("EXE"), L) })

        CT.section("glow, the zoomies' trails, and the dance")
        var glow = CatLook(preset: momo); glow.glowColor = [59, 158, 255]; glow.glowAlpha = 0.4
        CT.checkTrue("a glow draws", cover { CatEffects.drawGlow($0, glow, L) } > 1000)
        glow.glowAlpha = 0.001
        CT.checkTrue("a glow that has faded draws nothing", cover { CatEffects.drawGlow($0, glow, L) } == 0)
        var fast = CatLook(preset: momo); fast.zoomVelocity = 3
        CT.checkTrue("a fast cat leaves afterimages and speed lines", cover { CatEffects.drawZoomTrails($0, fast, L) } > 200)
        fast.zoomVelocity = 1
        CT.checkTrue("a slow one does not", cover { CatEffects.drawZoomTrails($0, fast, L) } == 0)
        fast.zoomVelocity = 3
        CT.checkTrue("and neither does a tiny one (under Ø16)", cover { CatEffects.drawZoomTrails($0, fast, layout(12)) } == 0)
        var moved = false
        _ = Bitmap.render(10, 10) { ctx in
            let before = ctx.ctm
            CatEffects.applyDance(ctx, level: 0, seconds: 0.3, pivotX: 5, pivotY: 5, size: 10)
            CT.checkTrue("at level 0 the dance leaves the context alone", ctx.ctm == before)
            CatEffects.applyDance(ctx, level: 1, seconds: 0.3, pivotX: 5, pivotY: 5, size: 10)
            moved = ctx.ctm != before
        }
        CT.checkTrue("at level 1 it hops and sways around the pivot", moved)
        CT.finish()
    }
}
```

**Create `scripts/test-cat-effects.sh`:**

```bash
#!/usr/bin/env bash
# The cat's drawing kit and effects: colours, text, badge, particles, paws, hairballs, glow, trails and the dance, drawn into bitmaps.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-effects.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    tests/CatTestSupport.swift tests/CatBitmapSupport.swift tests/CatEffectsTests.swift \
    -o "$TEST_DIR/cat-effects-tests"
"$TEST_DIR/cat-effects-tests"
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-effects.sh`
Expected: FAIL (swiftc cannot open `NotchBuddy/Sources/App/CatLook.swift`)

- [ ] **Step 3: Write the types, the drawing kit and the effects**

These are the prototype's `heartP`, `starP`, `drawPaw`, `drawBadge`, `drawParticles`, `drawBalls`, `drawFile` and the glow and afterimage code of `drawCat`, ported from Canvas 2D to `CGContext`. Two Canvas behaviours matter: a Canvas gradient is padded past both ends (so `radial` passes `drawsBeforeStartLocation` and `drawsAfterEndLocation`), and the contexts used here have y pointing down, so `text` flips the text matrix.

**Create `NotchBuddy/Sources/App/CatLook.swift`:**

```swift
import Foundation

// What the renderer draws: the eye shapes, the badge, the particles and hairballs, the paws, and `CatLook`, the one value that holds
// everything it needs to draw a cat. The engine fills them in; the renderer only reads them. They hold no logic.

/// An eye shape. The first four are drawn as the realistic almond eye at full detail; the rest are the expression eyes in the cat's ink colour.
enum CatEye: String, CaseIterable, Sendable {
    case pill, wide, dot, line, flat, happy, closed, spiral, heart, star, tired, wink

    /// Shapes drawn as the realistic almond eye (with iris and pupil) at full detail.
    var isRealistic: Bool { self == .pill || self == .wide || self == .dot || self == .tired }
}

/// The small badge beside the ear.
enum CatBadge: String, Sendable { case dots, bang, question, dot }

enum CatParticleKind: String, Sendable { case heart, star, spark, sweat, dust, hair, z }

/// A particle, in units of R from the cat's resting centre, drawn at `x + vx * age`, `y + vy * age`. A negative age waits to start.
struct CatParticle {
    var kind: CatParticleKind
    var x: Double, y: Double, vx: Double, vy: Double, age: Double, life: Double, size: Double, rot: Double
}

/// A hairball, or a refused file wrapped in fur, in units of R from the cat's resting centre.
struct CatBall {
    var x: Double, y: Double, vx: Double, vy: Double, rot: Double, age: Double, life: Double
    var file: String?
    var seed: Int
    var floor: Double
}


/// Everything the renderer needs to draw one cat besides where and how big: the coat, the pose and what the engine decided about the face.
struct CatLook {
    var preset: CatPreset
    var pose = CatPose()
    var eye: CatEye = .pill
    /// How open the mouth is, 0 (closed) to 1.3 (the engine adds the state's mouth, its motion and the file-catch spring).
    var mouthOpen = 0.0
    /// The state colour, 0...255, for the tint on the lower head.
    var color: [Double] = [230, 233, 238]
    /// The resting blush a personality adds, on top of the pose's.
    var blushBase = 0.0
    /// Seconds, for the motion inside a shape (the spiral eyes, the star eyes, the wavy mouth).
    var time = 0.0
    /// The badge beside the ear, and its colour (a hex string; the state colour).
    var badge: CatBadge?
    var badgeColor = "#FFFFFF"
    /// The soft light behind the cat (0...255 colour and an alpha); drawn only when the options ask for a glow.
    var glowColor: [Double] = [255, 255, 255]
    var glowAlpha = 0.12
    var particles: [CatParticle] = []
    var balls: [CatBall] = []
    /// The cat's sideways speed in R per second, for the zoomies afterimages and speed lines.
    var zoomVelocity = 0.0
    /// Paws drawn behind the head by hand (the greeting); nil: the engine's wave, from `wave`.
    var paws: [CatPaw]?
    var wave: CatWave?
}

/// A paw in the head's frame, in px. `k` is how far it is out (0 hidden, 1 full size).
struct CatPaw { var x: Double, y: Double, k: Double, rot: Double, beans: Bool }

/// The paw wave of `CatEngine.greet`: the clock and the wave window, in ms, plus how far the paws are out (the pose's `paws`).
struct CatWave { var now: Double, start: Double, until: Double }

struct CatDrawOptions {
    /// The state tint on the lower head.
    var tint = true
    /// +1 puts the badge beside the right ear, -1 beside the left (the compact notch).
    var badgeSide = 1.0
    /// The y of the top of the strip the cat lives in (the compact notch). The ears are fitted under it. nil: no limit.
    var earCeiling: Double?
    /// nil: full detail from a head width of Ø28. true or false forces it.
    var full: Bool?
    /// A soft light behind the cat. The island draws its own glow, so the app leaves this off; the contact sheets turn it on.
    var glow = false
    /// The badge, when the cat has one.
    var badge = true
}
```

**Create `NotchBuddy/Sources/App/CatDrawing.swift`:**

```swift
import CoreGraphics
import CoreText
import Foundation

// Colours, paths and text for the cat renderer. Everything draws into a CGContext whose y axis points down (the SwiftUI Canvas's
// `withCGContext` already is, and the contact-sheet script flips its bitmap context to match), so a drawing call here reads like the
// prototype's Canvas 2D call it was ported from.

@MainActor
enum CatDraw {
    // MARK: Colours

    private static var cache: [String: CGColor] = [:]
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    /// A preset colour ("#RRGGBB" or "rgba(r,g,b,a)", the strings the contract holds) as a CGColor, cached.
    static func color(_ s: String) -> CGColor {
        if let c = cache[s] { return c }
        var r = 0.0, g = 0.0, b = 0.0, a = 1.0
        if s.hasPrefix("#") {
            let v = hexRGB(s)
            r = v[0] / 255; g = v[1] / 255; b = v[2] / 255
        } else if s.hasPrefix("rgba(") {
            let n = s.dropFirst(5).dropLast().split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            if n.count >= 3 { r = n[0] / 255; g = n[1] / 255; b = n[2] / 255 }
            if n.count >= 4 { a = n[3] }
        }
        let c = CGColor(colorSpace: space, components: [r, g, b, a])!
        cache[s] = c
        return c
    }

    /// A colour with its alpha multiplied.
    static func color(_ s: String, alpha: Double) -> CGColor {
        let c = color(s)
        return c.copy(alpha: c.alpha * alpha) ?? c
    }

    /// The colour halfway (or `t` of the way) from a to b.
    static func mix(_ a: CGColor, _ b: CGColor, _ t: Double) -> CGColor {
        let x = a.components ?? [0, 0, 0, 1], y = b.components ?? [0, 0, 0, 1]
        return CGColor(colorSpace: space, components: (0..<4).map { CGFloat(lerp(Double(x[$0]), Double(y[$0]), t)) })!
    }

    /// [r, g, b] in 0...255 with an alpha.
    static func rgb(_ c: [Double], _ a: Double = 1) -> CGColor {
        CGColor(colorSpace: space, components: [c[0] / 255, c[1] / 255, c[2] / 255, a])!
    }

    static func white(_ a: Double) -> CGColor { CGColor(colorSpace: space, components: [1, 1, 1, a])! }
    static func black(_ a: Double) -> CGColor { CGColor(colorSpace: space, components: [0, 0, 0, a])! }

    // MARK: Gradients

    static func gradient(_ stops: [(Double, CGColor)]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: stops.map { $0.1 } as CFArray, locations: stops.map { CGFloat($0.0) })!
    }

    /// A linear gradient padded past both ends, like a Canvas gradient.
    static func linear(_ cg: CGContext, _ stops: [(Double, CGColor)], from: (Double, Double), to: (Double, Double)) {
        cg.drawLinearGradient(gradient(stops), start: CGPoint(x: from.0, y: from.1), end: CGPoint(x: to.0, y: to.1),
                              options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// A radial gradient between two concentric circles, padded past both ends like a Canvas gradient.
    static func radial(_ cg: CGContext, _ stops: [(Double, CGColor)], center: (Double, Double), r0: Double, r1: Double) {
        let c = CGPoint(x: center.0, y: center.1)
        cg.drawRadialGradient(gradient(stops), startCenter: c, startRadius: r0, endCenter: c, endRadius: r1,
                              options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    // MARK: Paths

    static func poly(_ pts: [(Double, Double)]) -> CGPath {
        let p = CGMutablePath()
        for (i, q) in pts.enumerated() { i == 0 ? p.move(to: CGPoint(x: q.0, y: q.1)) : p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        p.closeSubpath()
        return p
    }

    /// A rounded rectangle whose radius is held to half the short side, like the prototype's `rr`.
    static func roundRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> CGPath {
        let rr = max(0, min(r, w / 2, h / 2))
        return CGPath(roundedRect: CGRect(x: x, y: y, width: max(0, w), height: max(0, h)), cornerWidth: rr, cornerHeight: rr, transform: nil)
    }

    static func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> CGPath {
        CGPath(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    static func circle(_ x: Double, _ y: Double, _ r: Double) -> CGPath { ellipse(x, y, r, r) }

    /// A heart of size `s`, centred on its middle.
    static func heart(_ s: Double) -> CGPath {
        let q = CGMutablePath()
        q.move(to: CGPoint(x: 0, y: 0.38 * s))
        q.addCurve(to: CGPoint(x: 0, y: -0.38 * s), control1: CGPoint(x: -1.05 * s, y: -0.15 * s), control2: CGPoint(x: -0.5 * s, y: -0.95 * s))
        q.addCurve(to: CGPoint(x: 0, y: 0.38 * s), control1: CGPoint(x: 0.5 * s, y: -0.95 * s), control2: CGPoint(x: 1.05 * s, y: -0.15 * s))
        q.closeSubpath()
        return q
    }

    /// A five-pointed star with the given outer and inner radii, one point straight up.
    static func star(_ outer: Double, _ inner: Double) -> CGPath {
        poly((0..<10).map { k in
            let r = k % 2 == 1 ? inner : outer, a = -Double.pi / 2 + Double(k) * Double.pi / 5
            return (cos(a) * r, sin(a) * r)
        })
    }

    /// A quadratic Bézier from (x0,y0) via (cx,cy) to (x1,y1), as a stroke-able path.
    static func quad(_ x0: Double, _ y0: Double, _ cx: Double, _ cy: Double, _ x1: Double, _ y1: Double) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x0, y: y0))
        p.addQuadCurve(to: CGPoint(x: x1, y: y1), control: CGPoint(x: cx, y: cy))
        return p
    }

    // MARK: Text

    enum Anchor { case center, left, right }

    /// Text centred on (x, y) (or starting or ending at x), in a context whose y axis points down. `bold` uses the heavy system face.
    static func text(_ cg: CGContext, _ s: String, x: Double, y: Double, size: Double, bold: Bool, color: CGColor, anchor: Anchor = .center) {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let left = anchor == .center ? x - b.midX : anchor == .left ? x - b.minX : x - b.maxX
        cg.saveGState()
        cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        cg.textPosition = CGPoint(x: left, y: y + b.midY)
        CTLineDraw(line, cg)
        cg.restoreGState()
    }
}

extension CGContext {
    func fill(_ path: CGPath, _ color: CGColor) {
        setFillColor(color)
        addPath(path)
        fillPath()
    }

    func stroke(_ path: CGPath, _ color: CGColor, width: Double, cap: CGLineCap = .round, join: CGLineJoin = .round) {
        setStrokeColor(color)
        setLineWidth(width)
        setLineCap(cap)
        setLineJoin(join)
        addPath(path)
        strokePath()
    }

    /// Clips to a path for the rest of the current graphics state.
    func clip(_ path: CGPath) {
        addPath(path)
        clip()
    }
}
```

**Create `NotchBuddy/Sources/App/CatEffects.swift`:**

```swift
import CoreGraphics
import Foundation

/// What is drawn around the cat rather than as part of it: the glow, the zoomies' afterimages, the paws, the badge, the particles and
/// the hairballs. Port of the prototype's drawing of the same names.
@MainActor
enum CatEffects {
    typealias G = CatGeometry

    // MARK: Behind the cat, in the world

    static func drawGlow(_ cg: CGContext, _ look: CatLook, _ L: G.Layout) {
        guard look.glowAlpha > 0.005 else { return }
        let g = look.glowColor.map { $0.rounded() }, R = L.R, cx = L.head.x, cy = L.head.y
        cg.saveGState()
        CatDraw.radial(cg, [(0, CatDraw.rgb(g, look.glowAlpha)), (1, CatDraw.rgb(g, 0))], center: (cx, cy), r0: 0, r1: R * 2.3)
        cg.restoreGState()
    }

    /// Afterimages and speed lines behind a cat that is moving fast (the zoomies).
    static func drawZoomTrails(_ cg: CGContext, _ look: CatLook, _ L: G.Layout) {
        let zv = look.zoomVelocity, p = look.preset
        guard abs(zv) > 1.1 && L.D >= 16 else { return }
        let k = min(1, (abs(zv) - 1.1) / 2.5), dir = zv > 0 ? 1.0 : -1.0, R = L.R, cx = L.head.x, cy = L.head.y
        let tint = p.ruff?.col[0] ?? p.top
        for i in 1...3 {
            cg.fill(CatDraw.ellipse(cx - dir * Double(i) * 0.3 * R * k, cy, L.rx, L.ry), CatDraw.color(tint, alpha: 0.2 * k / Double(i)))
        }
        for (yy, l) in [(-0.5, 0.7), (-0.08, 1.0), (0.32, 0.8), (0.68, 0.5)] {
            let x0 = cx - dir * (L.rx + 0.15 * R), y = cy + yy * R
            let line = CGMutablePath()
            line.move(to: CGPoint(x: x0, y: y))
            line.addLine(to: CGPoint(x: x0 - dir * l * 0.75 * R * k, y: y))
            cg.stroke(line, CatDraw.white(0.6 * k), width: max(1, 0.025 * R))
        }
    }

    // MARK: Paws (behind the head, in its frame)

    /// The paws of the engine's wave: both rest at the cheeks, the right one rises and waves with its toe beans out.
    static func wavePaws(pawsOut: Double, wave: CatWave, rx: Double, ry: Double) -> [CatPaw] {
        if pawsOut <= 0.01 { return [] }
        let n = wave.now, bodyH = 2 * ry, waving = wave.start > 0 && n >= wave.start && n < wave.until
        return [-1.0, 1.0].map { sd in
            var x = sd * rx, y = ry * 0.78, rot = 0.0, beans = false
            if sd > 0 && waving {
                let wt = (n - wave.start) / 1000, rise = CatEase.out.at(min(1, wt / 0.18))
                x = lerp(x, rx * 1.12 + cos(13 * wt) * 0.06 * bodyH, rise)
                y = lerp(y, -ry * 0.12 - sin(13 * wt) * 0.12 * bodyH, rise)
                rot = (0.35 + sin(13 * wt) * 0.3) * rise
                beans = rise > 0.5
            } else if sd < 0 && waving {
                y += sin(6 * (n - wave.start) / 1000) * 0.04 * bodyH
            }
            return CatPaw(x: x, y: y, k: pawsOut, rot: rot, beans: beans)
        }
    }

    static func drawPaw(_ cg: CGContext, _ p: CatPreset, _ R: Double, _ q: CatPaw) {
        let k = q.k, w = 0.2 * R * k, h = 0.18 * R * k
        if w < 0.6 { return }
        cg.saveGState()
        cg.translateBy(x: q.x, y: q.y)
        cg.rotate(by: q.rot)
        let toes = [-1.0, 0.0, 1.0].map { (x: $0 * w * 0.55, y: -h * 0.62) }
        let shape = CGMutablePath()
        for t in toes { shape.addEllipse(in: CGRect(x: t.x - w * 0.36, y: t.y - h * 0.38, width: w * 0.72, height: h * 0.76)) }
        shape.addEllipse(in: CGRect(x: -w, y: -h * 0.85, width: w * 2, height: h * 1.7))
        cg.stroke(shape, CatDraw.black(0.28), width: max(0.6, 0.012 * R))
        cg.fill(shape, CatDraw.color(p.paw))
        if q.beans {
            let bean = CatDraw.color(p.bean)
            cg.fill(CatDraw.ellipse(0, h * 0.12, w * 0.42, h * 0.32), bean)
            for t in toes { cg.fill(CatDraw.ellipse(t.x, t.y + h * 0.02, w * 0.16, h * 0.17), bean) }
        } else {
            for s in [-1.0, 1.0] {
                let line = CGMutablePath()
                line.move(to: CGPoint(x: s * w * 0.28, y: -h * 0.85))
                line.addLine(to: CGPoint(x: s * w * 0.24, y: -h * 0.35))
                cg.stroke(line, CatDraw.black(0.25), width: max(0.6, 0.012 * R))
            }
        }
        cg.restoreGState()
    }

    // MARK: In front, in the world

    static func drawBadge(_ cg: CGContext, _ kind: CatBadge, _ colorHex: String, _ L: G.Layout, _ T: Double) {
        let R = L.R, b = L.badge, col = CatDraw.color(colorHex)
        cg.saveGState()
        cg.translateBy(x: b.x, y: b.y)
        cg.scaleBy(x: b.k, y: b.k)
        switch kind {
        case .dots where b.small:
            let r = R * 0.22 * (1 + 0.25 * sin(((T * 2.4).truncatingRemainder(dividingBy: 1)) * CatMath.tau))
            cg.fill(CatDraw.circle(0, 0, R * 0.26), CatDraw.black(1))
            cg.fill(CatDraw.circle(0, 0, r), col)
        case .dots:
            cg.fill(CatDraw.roundRect(-0.36 * R, -0.18 * R, 0.72 * R, 0.36 * R, 0.18 * R), col)
            for i in 0..<3 {
                let ph = ((2.4 * T - 0.22 * Double(i)).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
                let r = 0.055 * R * (1 + 0.4 * max(0, sin(CatMath.tau * ph)))
                cg.fill(CatDraw.circle(Double(i - 1) * 0.18 * R, 0, r), CatDraw.white(1))
            }
        case .bang, .question:
            cg.fill(CatDraw.circle(0, 0, 0.3 * R), CatDraw.black(1))
            cg.fill(CatDraw.circle(0, 0, 0.23 * R), col)
            if !b.small { CatDraw.text(cg, kind == .bang ? "!" : "?", x: 0, y: 0.02 * R, size: 0.32 * R, bold: true, color: CatDraw.white(1)) }
        case .dot:
            cg.fill(CatDraw.circle(0, 0, 0.2 * R), CatDraw.black(1))
            cg.fill(CatDraw.circle(0, 0, 0.135 * R), col)
        }
        cg.restoreGState()
    }

    static func drawParticles(_ cg: CGContext, _ look: CatLook, _ L: G.Layout) {
        let R = L.R, cx = L.base.x, cy = L.base.y, p = look.preset
        for q in look.particles where q.age >= 0 {
            let k = q.age / q.life, al = k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8
            let x = cx + (q.x + q.vx * q.age) * R * 1.3, y = cy + (q.y + q.vy * q.age) * R * 1.3, sz = R * q.size * (1 + 0.4 * k)
            cg.saveGState()
            cg.setAlpha(max(0, al))
            cg.translateBy(x: x, y: y)
            switch q.kind {
            case .heart:
                cg.rotate(by: sin(6 * q.age) * 0.3)
                cg.fill(CatDraw.heart(sz * 1.6), CatDraw.color("#FF4D6D"))
            case .star:
                cg.rotate(by: q.rot + 2 * q.age)
                cg.fill(CatDraw.star(sz, sz * 0.45), CatDraw.color("#F7B32B"))
            case .spark:
                cg.rotate(by: q.rot)
                cg.fill(CatDraw.star(sz * 0.8, sz * 0.18), CatDraw.white(1))
            case .sweat:
                let d = CGMutablePath()
                d.move(to: CGPoint(x: 0, y: -sz))
                d.addQuadCurve(to: CGPoint(x: 0, y: sz * 0.8), control: CGPoint(x: sz * 0.8, y: sz * 0.3))
                d.addQuadCurve(to: CGPoint(x: 0, y: -sz), control: CGPoint(x: -sz * 0.8, y: sz * 0.3))
                cg.fill(d, CatDraw.color("#7CC7FF"))
            case .dust:
                cg.fill(CatDraw.circle(0, 0, sz * (0.6 + k * 0.9)), CatDraw.rgb([225, 225, 232], 0.55))
            case .hair:
                cg.rotate(by: q.rot + q.age * 1.5)
                cg.stroke(CatDraw.quad(-sz * 0.6, 0, 0, -sz * 0.5, sz * 0.6, 0), CatDraw.color(p.hairLight), width: max(0.6, R * 0.014))
            case .z:
                CatDraw.text(cg, "z", x: 0, y: 0, size: 1.9 * sz, bold: true, color: CatDraw.rgb([209, 219, 235]))
            }
            cg.restoreGState()
        }
    }

    /// A small file icon (a folded corner and an extension label), for a refused file wrapped in fur.
    static func drawFile(_ cg: CGContext, x: Double, y: Double, size s: Double, rot: Double, ext: String) {
        cg.saveGState()
        cg.translateBy(x: x, y: y)
        cg.rotate(by: rot)
        let w = s * 0.78, h = s, f = s * 0.24
        cg.fill(CatDraw.poly([(-w / 2, -h / 2), (w / 2 - f, -h / 2), (w / 2, -h / 2 + f), (w / 2, h / 2), (-w / 2, h / 2)]), CatDraw.color("#F4F5F7"))
        cg.fill(CatDraw.poly([(w / 2 - f, -h / 2), (w / 2 - f, -h / 2 + f), (w / 2, -h / 2 + f)]), CatDraw.color("#C9CDD4"))
        cg.fill(CatDraw.roundRect(-w / 2 + s * 0.07, h * 0.06, w - s * 0.14, s * 0.24, s * 0.05), CatDraw.color("#3B9EFF"))
        CatDraw.text(cg, ext, x: 0, y: h * 0.06 + s * 0.125, size: s * 0.15, bold: true, color: CatDraw.white(1))
        cg.restoreGState()
    }

    /// Hairballs (and refused files wrapped in fur) bounce once and roll away.
    static func drawBalls(_ cg: CGContext, _ look: CatLook, _ L: G.Layout) {
        let p = look.preset, R = L.R, cx = L.base.x, cy = L.base.y
        for b in look.balls {
            let a = min(1, (b.life - b.age) / 0.5)
            cg.saveGState()
            cg.translateBy(x: cx + b.x * R, y: cy + b.y * R)
            cg.rotate(by: b.rot)
            cg.setAlpha(max(0, a))
            let r = CatRNG(seed: UInt32(truncatingIfNeeded: b.seed))
            var fw = 0.17 * R, fh = 0.11 * R
            if let file = b.file {
                drawFile(cg, x: 0, y: 0, size: 0.36 * R, rot: 0, ext: file)
                fw = 0.17 * R; fh = 0.2 * R
            } else {
                cg.fill(CatDraw.ellipse(0, 0, fw, fh), CatDraw.color(p.hair))
            }
            for _ in 0..<(b.file != nil ? 26 : 20) {
                let t = r.next() * CatMath.tau, ex = cos(t) * fw, ey = sin(t) * fh, len = (0.03 + r.next() * 0.05) * R
                let strand = CGMutablePath()
                strand.move(to: CGPoint(x: ex * 0.75, y: ey * 0.75))
                strand.addQuadCurve(to: CGPoint(x: ex + cos(t + 0.3) * len, y: ey + sin(t + 0.3) * len), control: CGPoint(x: ex + cos(t + 0.9) * len * 0.6, y: ey + sin(t + 0.9) * len * 0.6))
                cg.stroke(strand, CatDraw.color(r.next() < 0.5 ? p.hairDark : p.hairLight), width: max(0.6, 0.014 * R))
            }
            if b.file == nil {
                cg.saveGState()
                cg.translateBy(x: -fw * 0.3, y: -fh * 0.4)
                cg.rotate(by: -0.3)
                cg.fill(CatDraw.ellipse(0, 0, fw * 0.3, fh * 0.2), CatDraw.white(0.3))
                cg.restoreGState()
            }
            cg.restoreGState()
        }
    }

    // MARK: Apple Music dance

    /// A 112 BPM hop and sway around the bottom of the head. Apply it to the context before drawing; `level` is the engine's dancing level.
    static func applyDance(_ cg: CGContext, level l: Double, seconds: Double, pivotX px: Double, pivotY py: Double, size R: Double) {
        guard l > 0.001 else { return }
        let beat = seconds * 112 / 60, hop = abs(sin(Double.pi * beat)), land = pow(1 - hop, 6)
        cg.translateBy(x: px + 0.08 * R * sin(Double.pi * beat) * l, y: py - 0.20 * R * hop * l)
        cg.rotate(by: 0.10 * sin(Double.pi * beat) * l)
        cg.scaleBy(x: 1 + 0.045 * land * l, y: 1 - 0.06 * land * l)
        cg.translateBy(x: -px, y: -py)
    }
}
```

- [ ] **Step 4: Run the test**

Run: `bash scripts/test-cat-effects.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/CatBitmapSupport.swift tests/CatEffectsTests.swift scripts/test-cat-effects.sh NotchBuddy/Sources/App/CatLook.swift NotchBuddy/Sources/App/CatDrawing.swift NotchBuddy/Sources/App/CatEffects.swift
git commit -m "feat(cat): the drawing kit and the effects around the cat (badge, particles, paws, hairballs, glow, dance)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The still cat at every size, in every coat, and the contact sheet (stage 1)

Agent: `nm-implementer`.

**Files:**
- Create: `tests/CatRendererTests.swift`, `scripts/test-cat-renderer.sh`
- Create: `NotchBuddy/Sources/App/CatFace.swift`, `NotchBuddy/Sources/App/CatRenderer.swift`
- Create: `scripts/render-cats.swift`, `scripts/render-cats.sh`
- Modify (regenerated): `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Tasks 1 to 3: `CatPreset`, `CatGeometry.layout`, `CatLook`, `CatDrawOptions`, `CatDraw`, `CatEffects`; the fixture `tests/fixtures/cat/geometry-cases.json` (its `earFit`, `flatFill` and `flatColors`, read by the test at run time).
- Produces `CatFace`: `drawEyes(_:_:_:)`, `drawNoseAndMouth(_:_:_:)`, `drawWhiskers(_:_:_:_:)`.
- Produces `CatRenderer`: `static func draw(_ cg: CGContext, _ look: CatLook, cx: Double, cy: Double, D: Double, _ o: CatDrawOptions = CatDrawOptions()) -> CatGeometry.Layout` (draws the cat and returns its layout: the engine wants `layout.base` and `layout.mouth` back), `drawEar(_:_:_:R:full:front:)`. `D` is the head width in px; `cy` is the cat's resting centre.
- Produces `scripts/render-cats.sh [--out FILE] [--cats id,id] [--sizes 12,20,66] [--scale 2] [--stage]`: renders a PNG of every coat at every size plus kittens (the default "ladder"), or the big cats on stage panels, with the real `CatRenderer` and no app.

- [ ] **Step 1: Write the failing test**

The test draws every coat (and its kitten) at six sizes, in a rest pose, four turned poses, a squashed pose, a rolled pose and with each of the twelve eye shapes, and asserts that nothing is blank, that drawing is deterministic, that a face rolled over the top of the head fades out, that the compact detail drops the whiskers, that the flat fills the contract names (every coat's head, ears and ruff, the tabby crown band and the point mask) are what reaches the pixels, that the compact ear scale and the ear fit compose (`earScale(D) * f`, and a forced full detail keeps full-size ears), and that in the compact notch no ear is painted above the top of the strip and a shrunk ear sits exactly on the fit's margin.

**Create `tests/CatRendererTests.swift`:**

```swift
import CoreGraphics
import Foundation

@main
enum CatRendererTests {
    @MainActor static func render(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> [UInt8] { Bitmap.render(w, h, draw) }
    static func alpha(_ px: [UInt8], _ x: Int, _ y: Int, _ w: Int) -> Int { Bitmap.alpha(px, x, y, w) }
    static func coverage(_ px: [UInt8]) -> Int { Bitmap.coverage(px) }
    static func num(_ x: Any?) -> Double { (x as! NSNumber).doubleValue }
    static func rgb(_ x: Any?) -> [Double] { (x as! [NSNumber]).map(\.doubleValue) }

    /// The highest point of an ear in the world (the smallest y), found by walking the whole outline the renderer draws (the geometry test walks it the same way).
    static func earTop(_ L: CatGeometry.Layout, _ s: CatPose, _ e: CatGeometry.Ear) -> Double {
        let R = L.R, h = e.h, bw = e.bw, tip = e.tip, cx = e.cx
        let curves: [[(Double, Double)]] = [
            [(-bw, 0.25 * R), (-bw * cx, -h * 0.4), (-tip * 0.9, -h + tip * 1.3)],
            [(-tip * 0.9, -h + tip * 1.3), (0, -h - tip * 0.35), (tip * 0.9, -h + tip * 1.3)],
            [(tip * 0.9, -h + tip * 1.3), (bw * cx, -h * 0.4), (bw, 0.25 * R)],
        ]
        var best = Double.infinity
        for q in curves {
            for i in 0...400 {
                let t = Double(i) / 400, m = 1 - t
                let x = m * m * q[0].0 + 2 * m * t * q[1].0 + t * t * q[2].0, y = m * m * q[0].1 + 2 * m * t * q[1].1 + t * t * q[2].1
                let hx = e.bx + x * cos(e.rot) - y * sin(e.rot), hy = e.by + x * sin(e.rot) + y * cos(e.rot)
                best = min(best, L.head.y + sin(s.tilt) * s.sx * hx + cos(s.tilt) * s.sy * hy)
            }
        }
        return best
    }

    @MainActor static func main() {
        typealias R = CatRenderer
        typealias G = CatGeometry
        let geo = CT.fixture("geometry-cases.json")

        CT.section("every coat draws at every size, in a turned, squashed or rolled pose and with every eye shape")
        var drawn = 0, blank: [String] = []
        for id in CatPresets.ids {
            for kitten in [false, true] {
                let base = CatPresets.byID(id), p = kitten ? CatPresets.kitten(of: base) : base
                for D in [12.0, 16, 20, 28, 44, 66] {
                    let size = Int(D * 3)
                    var poses: [(String, CatPose, CatEye)] = [("rest", CatPose(), .pill)]
                    for (n, yaw, pitch) in [("right", 0.62, 0.0), ("left", -0.62, 0.0), ("up", 0.0, 0.5), ("down", 0.0, -0.5)] {
                        var s = CatPose(); s.yaw = yaw; s.pitch = pitch; poses.append((n, s, .pill))
                    }
                    var sq = CatPose(); sq.sx = 1.12; sq.sy = 0.9; sq.tilt = 0.2; sq.earU = 1.4; sq.earF = 0.6; sq.ox = 0.2; sq.oy = -0.2; sq.blush = 1; sq.tint = 0.7
                    poses.append(("squashed", sq, .happy))
                    var roll = CatPose(); roll.roll = 1.2; poses.append(("rolled", roll, .pill))
                    for e in CatEye.allCases { poses.append(("eye \(e.rawValue)", CatPose(), e)) }
                    for (name, pose, eye) in poses {
                        let px = render(size, size) { cg in
                            R.draw(cg, CatLook(preset: p, pose: pose, eye: eye, mouthOpen: eye == .wide ? 0.5 : 0), cx: Double(size) / 2, cy: Double(size) / 2, D: D)
                        }
                        drawn += 1
                        if coverage(px) == 0 { blank.append("\(p.label) \(D) \(name)") }
                    }
                }
            }
        }
        CT.check("nothing came out blank (\(drawn) drawings)", blank, [])

        CT.section("the same cat draws the same pixels twice")
        let a = render(200, 200) { R.draw($0, CatLook(preset: CatPresets.byID("shrimpy")), cx: 100, cy: 100, D: 120) }
        let b = render(200, 200) { R.draw($0, CatLook(preset: CatPresets.byID("shrimpy")), cx: 100, cy: 100, D: 120) }
        CT.checkTrue("two renders are byte for byte equal", a == b)
        CT.checkTrue("Shrimpy at Ø120 covers a good part of a 200 px square", coverage(a) > 8000)

        CT.section("a face rolled over the top of the head fades out")
        var over = CatPose(); over.roll = Double.pi
        func overRender(_ eye: CatEye) -> [UInt8] {
            render(200, 200) { R.draw($0, CatLook(preset: CatPresets.byID("momo"), pose: over, eye: eye), cx: 100, cy: 100, D: 120) }
        }
        CT.checkTrue("with the face turned away the eye shape makes no difference", overRender(.pill) == overRender(.spiral))
        CT.checkTrue("but the head is still there", coverage(overRender(.pill)) > 5000)

        CT.section("the compact detail drops the whiskers and the irises")
        func atWidth(_ D: Double) -> Int {
            coverage(render(200, 200) { R.draw($0, CatLook(preset: CatPresets.byID("momo")), cx: 100, cy: 100, D: D) })
        }
        CT.checkTrue("the full cat at Ø28 reaches further than the compact one at Ø27.9 (whiskers)", atWidth(28) > atWidth(27.9))

        CT.section("the compact detail draws flat fills (A-0b's rule, G.detailLevel(D).flatFill): a solid coat is one colour across the head below Ø28, and shaded from Ø28")
        func headColours(_ D: Double) -> Set<[Int]> {
            let p = CatPresets.byID("ginger"), unit = D / (2 * p.rx), rx = p.rx * unit, ry = p.ry * unit
            let px = render(120, 120) { R.draw($0, CatLook(preset: p), cx: 60, cy: 60, D: D) }
            // two points of the head, clear of the eyes, the nose, the ears and the edge, even at Ø12
            return Set([(0.55, -0.55), (-0.8, 0.0)].map { fx, fy in
                let x = Int((60 + fx * rx).rounded()), y = Int((60 + fy * ry).rounded()), i = (y * 120 + x) * 4
                return [Int(px[i]), Int(px[i + 1]), Int(px[i + 2])]
            })
        }
        for D in [12.0, 16, 20, 24, 27.9] { CT.checkTrue("Ø\(D): one flat colour at two points of the head", headColours(D).count == 1 && CatGeometry.detailLevel(D).flatFill) }
        for D in [28.0, 44, 66] { CT.checkTrue("Ø\(D): shaded, the two points differ", headColours(D).count > 1 && !CatGeometry.detailLevel(D).flatFill) }

        CT.section("the flat fills reach the drawing: every coat's head, ears and ruff, the tabby crown band and the point mask are the contract's colours and numbers (A-0b, merged `6adf584`)")
        let flatColors = geo["flatColors"] as! [String: [String: Any]], flatFill = geo["flatFill"] as! [String: Any]
        let S = 4, side = 48, cx0 = 24.0, cy0 = 26.0
        // A compact cat (Ø20, below the Ø28 switch) at rest, drawn into a bitmap scaled up by S, so that each flat fill covers whole pixels.
        func shot(_ p: CatPreset) -> (px: [UInt8], L: G.Layout) {
            var layout: G.Layout?
            let px = render(side * S, side * S) { cg in
                cg.scaleBy(x: CGFloat(S), y: CGFloat(S))
                layout = R.draw(cg, CatLook(preset: p), cx: cx0, cy: cy0, D: 20)
            }
            return (px, layout!)
        }
        /// The pixel under the point (x, y) of the drawing: r, g, b and alpha.
        func colour(_ px: [UInt8], _ x: Double, _ y: Double) -> [Double] {
            let i = (Int(y * Double(S)) * side * S + Int(x * Double(S))) * 4
            return [Double(px[i]), Double(px[i + 1]), Double(px[i + 2]), Double(px[i + 3])]
        }
        func isColour(_ c: [Double], _ want: [Double], tol: Double = 1.5) -> Bool { c[3] == 255 && zip(c, want).allSatisfy { abs($0 - $1) <= tol } }
        var flatBad: [String] = [], tabbies = 0, points = 0
        for id in CatPresets.ids {
            let p = CatPresets.byID(id), want = flatColors[id]!, (px, L) = shot(p), headWant = rgb(want["head"]), R1 = L.R
            // The head: the flat colour covers a good part of the head's own ellipse (inside 85 % of it, clear of the ears and the ruff).
            var inside = 0, hits = 0
            for y in 0..<(side * S) {
                for x in 0..<(side * S) {
                    let fx = (Double(x) + 0.5) / Double(S), fy = (Double(y) + 0.5) / Double(S), dx = (fx - L.head.x) / (0.85 * L.rx), dy = (fy - L.head.y) / (0.85 * L.ry)
                    if dx * dx + dy * dy > 1 { continue }
                    inside += 1
                    if isColour(colour(px, fx, fy), headWant) { hits += 1 }
                }
            }
            if Double(hits) < 0.2 * Double(inside) { flatBad.append("\(id): the head's flat colour covers only \(hits) of \(inside) pixels") }
            // The ears: a point on each ear's centre line, four fifths of the way up, which is the ear's outer rim, clear of the inner ear. Patches and Mocha have
            // an ear of each colour, Latte and Cloud dark ears on a light head.
            let earsWant = (want["ears"] as! [[NSNumber]]).map { $0.map(\.doubleValue) }
            for (i, e) in L.ears.enumerated() {
                let ey = -0.8 * e.h + 0.475 * e.tip
                let wx = L.head.x + e.bx - ey * sin(e.rot), wy = L.head.y + e.by + ey * cos(e.rot), c = colour(px, wx, wy)
                if !isColour(c, earsWant[i]) { flatBad.append("\(id): ear \(i) is \(c), not its flat colour \(earsWant[i])") }
            }
            // The ruff: its flat colour is on the screen.
            if let ruff = want["ruff"] as? [NSNumber] {
                let rw = ruff.map(\.doubleValue)
                var n = 0
                for y in 0..<(side * S) { for x in 0..<(side * S) where isColour(colour(px, (Double(x) + 0.5) / Double(S), (Double(y) + 0.5) / Double(S)), rw) { n += 1 } }
                if n < 40 { flatBad.append("\(id): the ruff's flat colour covers only \(n) pixels") }
            }
            // The tabby's crown band: an ellipse of the contract's size, in the stripe colour at the contract's alpha. Two points on the row 0.08 R under its centre:
            // inside it (0.62 of its half-width) the head and the stripe mixed by the alpha, outside it (1.25 of it, still on the head) the plain flat head.
            if p.coat == "tabby" {
                tabbies += 1
                let crown = flatFill["crown"] as! [String: Any], cw = num(crown["rx"]), a = num(crown["alpha"]), y = L.head.y + (-0.88 + 0.08) * R1
                let mixed = zip(headWant, hexRGB(p.stripe ?? "#000000")).map { lerp($0, $1, a) }
                for sd in [-1.0, 1.0] {
                    let inCrown = colour(px, L.head.x + sd * 0.62 * cw * R1, y), outCrown = colour(px, L.head.x + sd * 1.25 * cw * R1, y)
                    if !isColour(inCrown, mixed, tol: 2.5) { flatBad.append("\(id): inside the crown band \(inCrown) is not the stripe at alpha \(a) over the head, \(mixed)") }
                    if !isColour(outCrown, headWant) { flatBad.append("\(id): outside the crown band \(outCrown) is not the flat head \(headWant)") }
                }
            }
            // The point mask: an ellipse of the contract's size, in the coat's point colour at the contract's alpha, at the centre the gradient had. On the forehead
            // between the eyes (x = 0), 0.75 of its height above its centre is inside it and 1.25 above is outside; on the row 0.63 of its height below the centre,
            // under the eyes, where it is 0.78 of its width wide, 0.75 of that is inside it and halfway from there to the edge of the head is outside it.
            if p.coat == "point" {
                points += 1
                let mask = flatFill["point"] as! [String: Any], mw = num(mask["rx"]), mh = num(mask["ry"]), a = num(mask["alpha"])
                let mixed = zip(headWant, rgb(want["point"])).map { lerp($0, $1, a) }
                let my = -sin(p.nosePh) * p.ry - 0.12, half = mw * (1 - 0.63 * 0.63).squareRoot()
                let headHalf = p.rx * pow(1 - pow(abs((my + 0.63 * mh) / p.ry), p.n), 1 / p.n), far = (half + headHalf) / 2   // the head's half-width on that row, from its outline
                var probes: [(String, Double, Double, Bool)] = [("above", 0, my - 0.75 * mh, true), ("far above", 0, my - 1.25 * mh, false)]
                for sd in [-1.0, 1.0] { probes += [("beside", sd * 0.75 * half, my + 0.63 * mh, true), ("far beside", sd * far, my + 0.63 * mh, false)] }
                for (label, x, y, isIn) in probes {
                    let c = colour(px, L.head.x + x * R1, L.head.y + y * R1)
                    if !isColour(c, isIn ? mixed : headWant, tol: isIn ? 2.5 : 1.5) { flatBad.append("\(id): \(label) the point mask \(c) is not \(isIn ? "the point colour at alpha \(a) over the head, \(mixed)" : "the flat head \(headWant)")") }
                }
            }
        }
        CT.check("every coat's flat head, ears and ruff, the \(tabbies) tabbies' crown band and the \(points) point cats' mask reach the drawing", flatBad, [])

        CT.section("every compact cat wears the compact ear scale, and the fit multiplies it: earScale(D) * f (A-0b, merged `6adf584`)")
        let noodle = CatPresets.byID("noodle")
        var hop = CatPose(); hop.earU = 1.4; hop.oy = -0.3; hop.tilt = 0.24
        func drawnAt(_ D: Double, _ o: CatDrawOptions = CatDrawOptions()) -> G.Layout {
            var layout: G.Layout?
            _ = render(80, 80) { layout = R.draw($0, CatLook(preset: noodle, pose: hop), cx: 40, cy: 16, D: D, o) }
            return layout!
        }
        func laidOut(_ D: Double, _ ek: Double) -> G.Layout { G.layout(noodle, hop, cx: 40, cy: 16, D: D, G.Options(earScale: ek)) }
        for D in [12.0, 20, 24, 27.999] { CT.checkNear("Ø\(D) is drawn with the compact ear scale \(G.earScale(D))", drawnAt(D).ears[0].h, laidOut(D, G.earScale(D)).ears[0].h) }
        for D in [28.0, 44, 66] { CT.checkNear("Ø\(D) is drawn with full-size ears", drawnAt(D).ears[0].h, laidOut(D, 1).ears[0].h) }
        CT.checkNear("drawn at full detail, a small cat keeps its full-size ears (scale 1)", drawnAt(20, CatDrawOptions(full: true)).ears[0].h, laidOut(20, 1).ears[0].h)
        CT.checkTrue("and it is the full cat", drawnAt(20, CatDrawOptions(full: true)).full && !drawnAt(20).full)
        let fit = G.earFit(laidOut(20, G.earScale(20)), hop, ceiling: 0)
        CT.checkTrue("this pose needs the fit (\(fit))", fit < 1 && fit > 0.35)
        CT.checkNear("under a ceiling the ears are earScale(D) * f", drawnAt(20, CatDrawOptions(earCeiling: 0)).ears[0].h, laidOut(20, G.earScale(20) * fit).ears[0].h)

        CT.section("ear headroom: in the compact notch no ear leaves the strip, and a shrunk ear sits exactly on the fit's margin")
        // A 32 pt strip with the cat in the middle, Ø20, drawn into a bitmap with 20 px of padding above the strip's top edge. The margin and the minimum are the fixture's.
        let pad = 20, strip = 32, fitFixture = geo["earFit"] as! [String: Any], margin = num(fitFixture["margin"]), minimum = num(fitFixture["minimum"])
        var worst = 0, shrunk = 0, headroom: [String] = []
        for (earU, oy, tilt) in [(1.0, 0.0, 0.0), (1.4, 0.0, 0.0), (1.4, -0.26, 0.0), (1.22, -0.26, 0.0), (1.4, -0.3, 0.24), (1.4, -0.3, -0.24)] {
            var s = CatPose(); s.earU = earU; s.oy = oy; s.tilt = tilt
            for id in ["momo", "shrimpy", "noodle", "puff", "button"] {
                let look = CatLook(preset: CatPresets.byID(id), pose: s), cy = Double(pad) + Double(strip) / 2
                var fitted: G.Layout?, bare: G.Layout?
                let px = render(120, pad + strip) { cg in
                    fitted = R.draw(cg, look, cx: 40, cy: cy, D: 20, CatDrawOptions(earCeiling: Double(pad)))
                }
                _ = render(120, pad + strip) { cg in bare = R.draw(cg, look, cx: 40, cy: cy, D: 20) }
                for y in 0..<pad { for x in 0..<120 { worst = max(worst, alpha(px, x, y, 120)) } }
                // The geometry the renderer fitted, against the same cat drawn without a ceiling: a calm cat keeps its ears, and a shrunk ear has its top on the margin.
                let ratio = fitted!.ears[0].h / bare!.ears[0].h, at = "\(id) earU \(earU) oy \(oy) tilt \(tilt)"
                if earU == 1 && oy == 0 && tilt == 0 && ratio != 1 { headroom.append("\(at): a calm cat keeps its ears, not \(ratio) of them") }
                if ratio < 1 - 1e-9 {
                    shrunk += 1
                    let top = fitted!.ears.map { earTop(fitted!, s, $0) }.min()! - Double(pad)
                    if ratio > minimum + 1e-6 && abs(top - margin) > 1e-3 { headroom.append("\(at): the top of the ears is \(top) under the strip's top, not on the margin \(margin)") }
                }
            }
        }
        CT.check("5 coats, 6 poses: a calm cat keeps its ears, and a shrunk ear sits on the margin \(margin)", headroom, [])
        CT.checkTrue("the hop pushes ears out of the strip, so the fit has work to do (\(shrunk) cases)", shrunk > 5)
        CT.checkTrue("nothing above the strip is painted more than a hair (worst alpha \(worst) of 255)", worst <= 160)

        CT.finish()
    }
}
```

**Create `scripts/test-cat-renderer.sh`:**

```bash
#!/usr/bin/env bash
# The cat renderer draws every coat, size, pose and eye shape without a blank or a crash, deterministically, and keeps its ears in the strip.
# (There are no pixel tests: the look is checked by eye on the contact sheet from scripts/render-cats.sh.)
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-renderer.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatRenderer.swift \
    tests/CatTestSupport.swift tests/CatBitmapSupport.swift tests/CatRendererTests.swift \
    -o "$TEST_DIR/cat-renderer-tests"
"$TEST_DIR/cat-renderer-tests"
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-renderer.sh`
Expected: FAIL (swiftc cannot open `NotchBuddy/Sources/App/CatFace.swift`)

- [ ] **Step 3: Write the face and the renderer**

`CatFace` is the prototype's eye, nose, mouth and whisker drawing; `CatRenderer` is `drawCat` minus the effects (Task 3), split into the three passes: *behind* (ruff, bib, paws, ears), the head (fill, markings warped onto the turning head, tint, rim, blush, face) and *front* (folded ears, whiskers). The compact detail uses flat fills where a gradient would be invisible and would cost a shading pass each (the compact head, ears, ruff, the rim, the tabby crown and the point mask): at Ø12 to Ø27 you cannot tell, and it is most of the saving behind the 2 ms frame budget (Task 10). The rule and its numbers are the contract's (A-0b, merged `6adf584`): the compact detail draws flat fills below Ø28, `flatFill` being exactly `!layout().full`; `CatGeometry.detailLevel(_:override:)`, `FlatFill` and `flatFillColors`, pinned by `geometry-cases.json` and ported in Task 2. The renderer draws the flat head, ears, ruff and point mask from `flatFillColors` (worked out once per draw, the point mask's colour included) and the crown band and the point mask's ellipse from `FlatFill` (crown 0.4 R by 0.26 R at alpha 0.5; point 0.86 R by 0.54 R at alpha 0.85), and the test below proves the effect on pixels. The ears are laid out with `earScale(D)` on every compact cat, times the ear fit's factor where a ceiling is given (`earScale(D) * f`), as the prototype page does. This stage draws no collar: the contract's `collarPass` ("front", between the folded ears and the whiskers) is for stage 6.

**Create `NotchBuddy/Sources/App/CatFace.swift`:**

```swift
import CoreGraphics
import Foundation

/// The face: eyes, nose, mouth and whiskers. Port of the prototype's eye, mouth and whisker drawing; all in the head's frame.
@MainActor
enum CatFace {
    typealias G = CatGeometry

    // MARK: Eyes

    static func drawEyes(_ cg: CGContext, _ look: CatLook, _ L: G.Layout) {
        let p = look.preset, s = look.pose, R = L.R
        let open = s.open * (1 - s.lid), shape = look.eye
        for e in L.eyes where e.visible {
            cg.saveGState()
            cg.translateBy(x: e.x, y: e.y)
            cg.scaleBy(x: e.fx, y: e.fy)
            cg.setAlpha(L.fa)
            if L.full {
                if let light = p.light {
                    cg.saveGState()
                    cg.scaleBy(x: 1.22, y: 1.3)
                    cg.fill(almondPath(p, e.sd, R, 1), CatDraw.color(light))
                    cg.restoreGState()
                }
                if shape.isRealistic || (shape == .wink && e.sd < 0) {
                    almondEye(cg, p, e.sd, R * s.es * (shape == .wide ? 1.12 : 1), pupil: shape == .dot ? 1 : s.pupil,
                              open: shape == .tired ? min(open, 0.42) : open, yaw: s.yaw, pitch: s.pitch)
                } else {
                    inkEye(cg, shape, e.sd, 0.27 * R * s.es, 0.31 * R * s.es, open, look.time, CatDraw.color(p.ink))
                }
            } else {
                inkEye(cg, shape, e.sd, 0.34 * R * s.es, 0.4 * R * s.es, open, look.time, CatDraw.color(p.ink))
            }
            cg.restoreGState()
        }
    }

    private static func almondPath(_ p: CatPreset, _ sd: Double, _ R: Double, _ open: Double) -> CGPath {
        let E = p.eye, w = E.w * R, h = E.h * R * max(open, 0.06), H = E.h * R
        let round = E.round != 0, k = round ? 2.2 : 1.85
        let iy = (round ? 0.04 : 0.12) * H, oy = (round ? -0.04 : -0.18) * H, ix = -sd * w, ox = sd * w
        let q = CGMutablePath()
        q.move(to: CGPoint(x: ix, y: iy))
        q.addQuadCurve(to: CGPoint(x: ox, y: oy), control: CGPoint(x: 0, y: -h * k))
        q.addQuadCurve(to: CGPoint(x: ix, y: iy), control: CGPoint(x: 0, y: H * (0.55 + 0.45 * max(open, 0.06)) * k))
        q.closeSubpath()
        return q
    }

    /// The realistic eye: iris gradient, dilating pupil, Momo's yellow lid ring, catchlights, liner.
    private static func almondEye(_ cg: CGContext, _ p: CatPreset, _ sd: Double, _ R: Double, pupil: Double, open: Double, yaw: Double, pitch: Double) {
        let E = p.eye, w = E.w * R, h = E.h * R
        if open < 0.22 {
            cg.stroke(CatDraw.quad(-w, 0, 0, 0.4 * h, w, 0), CatDraw.color(p.ink, alpha: 0.9), width: max(1, 0.045 * R))
            return
        }
        let outline = almondPath(p, sd, R, open)
        cg.saveGState()
        cg.clip(outline)
        let ir = (sd > 0 ? p.irisR : nil) ?? p.iris
        CatDraw.radial(cg, [(0, CatDraw.color(ir[0])), (1, CatDraw.color(ir[1]))], center: (0, 0), r0: 0, r1: w * 1.1)
        let off = G.pupilOffset(yaw: yaw, pitch: pitch, w: w, h: h)
        cg.fill(CatDraw.ellipse(off.x, off.y, w * (p.pupil0 + 0.5 * pupil), h * 1.1), CatDraw.color("#0E0B09"))
        if let ring = p.lidTint {
            cg.saveGState()
            cg.scaleBy(x: 0.92, y: 0.88)
            cg.stroke(almondPath(p, sd, R, open), CatDraw.color(ring, alpha: 0.85), width: 0.04 * R, join: .miter)
            cg.restoreGState()
        }
        cg.fill(CatDraw.circle(-0.32 * w, -0.32 * h, 0.2 * w), CatDraw.white(0.92))
        cg.fill(CatDraw.circle(0.22 * w, 0.3 * h, 0.09 * w), CatDraw.white(0.92))
        cg.restoreGState()
        cg.stroke(outline, CatDraw.color(p.liner), width: 0.05 * R, join: .miter)
    }

    /// Expression eyes (upstream's shapes), in the cat's ink colour. w and h are the eye's width and height; `sd` is -1 for the left eye.
    private static func inkEye(_ cg: CGContext, _ shape: CatEye, _ sd: Double, _ w: Double, _ h: Double, _ open: Double, _ T: Double, _ ink: CGColor) {
        func pill(_ W: Double, _ H: Double) {
            let hh = max(H * open, 0.3 * W)
            cg.fill(CatDraw.roundRect(-W / 2, -hh / 2, W, hh, min(W, hh) / 2), ink)
        }
        func happy() {
            let a = CGMutablePath()
            a.addArc(center: CGPoint(x: 0, y: 0.18 * h), radius: 0.82 * w, startAngle: 1.12 * Double.pi, endAngle: 1.88 * Double.pi, clockwise: false)
            cg.stroke(a, ink, width: 0.5 * w)
        }
        switch shape {
        case .pill: pill(w, h)
        case .wide: pill(w * 1.16, h * 1.12)
        case .dot: cg.fill(CatDraw.circle(0, 0, 0.45 * w), ink)
        case .line:
            cg.saveGState()
            cg.rotate(by: -sd * 0.2)
            cg.fill(CatDraw.roundRect(-0.78 * w, -0.21 * w, 1.56 * w, 0.42 * w, 0.21 * w), ink)
            cg.restoreGState()
        case .flat: cg.fill(CatDraw.roundRect(-0.72 * w, -0.2 * w, 1.44 * w, 0.4 * w, 0.2 * w), ink)
        case .happy: happy()
        case .closed:
            let a = CGMutablePath()
            a.addArc(center: CGPoint(x: 0, y: -0.08 * h), radius: 0.78 * w, startAngle: 0.15 * Double.pi, endAngle: 0.85 * Double.pi, clockwise: false)
            cg.stroke(a, ink, width: 0.36 * w)
        case .spiral:
            cg.saveGState()
            cg.rotate(by: T * 9 * sd)
            let sp = CGMutablePath()
            var a = 0.0, first = true
            while a < 4.4 * Double.pi {
                let r = 0.06 * w + 0.058 * w * a, pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
                first ? sp.move(to: pt) : sp.addLine(to: pt)
                first = false
                a += 0.2
            }
            cg.stroke(sp, ink, width: 0.22 * w)
            cg.restoreGState()
        case .heart: cg.fill(CatDraw.heart(1.2 * w), CatDraw.color("#FF4D6D"))
        case .star:
            cg.saveGState()
            cg.rotate(by: T * 1.5 * sd)
            cg.fill(CatDraw.star(1.05 * w, 0.46 * w), CatDraw.color("#F7B32B"))
            cg.restoreGState()
        case .tired:
            cg.fill(CatDraw.roundRect(-w / 2, -0.02 * h, w, 0.38 * h, min(w, 0.38 * h) / 2), ink)
            cg.fill(CatDraw.roundRect(-0.62 * w, -0.12 * h - 0.11 * w, 1.24 * w, 0.22 * w, 0.11 * w), ink)
        case .wink:
            sd < 0 ? pill(w, h) : happy()
        }
    }

    // MARK: Nose and mouth

    static func drawNoseAndMouth(_ cg: CGContext, _ look: CatLook, _ L: G.Layout) {
        guard L.nose.visible else { return }
        let p = look.preset, s = look.pose, R = L.R
        let nx = L.nose.nx, ny = L.nose.ny, nf = L.nose.nf, nw = L.nose.nw, nh = L.nose.nh, my = L.nose.my
        cg.saveGState()
        cg.setAlpha(L.fa)
        drawMouth(cg, p, s, R, nx, my, nf, L.full, look.mouthOpen, look.time)
        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: nx - nw / 2, y: ny - nh / 2))
        nose.addQuadCurve(to: CGPoint(x: nx + nw / 2, y: ny - nh / 2), control: CGPoint(x: nx, y: ny - nh * 0.8))
        nose.addQuadCurve(to: CGPoint(x: nx, y: ny + nh / 2), control: CGPoint(x: nx + nw * 0.1, y: ny + nh * 0.6))
        nose.addQuadCurve(to: CGPoint(x: nx - nw / 2, y: ny - nh / 2), control: CGPoint(x: nx - nw * 0.1, y: ny + nh * 0.6))
        cg.fill(nose, CatDraw.color(p.nose))
        if L.full { cg.stroke(nose, CatDraw.color(p.noseLine), width: 0.02 * R) }
        cg.restoreGState()
    }

    /// A closed ω that can smile, frown, skew or wobble, with an optional tongue blep, or an open mouth that runs from a wide D
    /// (meow, hiss, yawn) to a round 'o'.
    private static func drawMouth(_ cg: CGContext, _ p: CatPreset, _ s: CatPose, _ R: Double, _ nx: Double, _ my: Double, _ nf: Double, _ full: Bool, _ mo: Double, _ T: Double) {
        let sm = clamp(s.smile, -1, 1), sk = clamp(s.mskew, -1, 1), tg = clamp(s.tongue, 0, 1), rd = clamp(s.mround, 0, 1), wv = clamp(s.wavy, 0, 1)
        let y0 = my + 0.05 * R, cxm = nx + sk * 0.035 * R * nf, lw = 0.03 * R
        let line = CatDraw.color(p.mouthLine), tongueColor = CatDraw.color("#E8798C")
        if mo > 0.04 {
            let m = min(mo, 1.3)
            let w = 0.13 * R * (0.6 + 0.4 * m) * (1 - 0.45 * rd) * (1 + 0.25 * max(0, sm)) * nf
            let h = 0.21 * R * m * (1 - 0.3 * rd) + 0.012 * R, top = y0 - 0.012 * R
            // The opening hangs under the ω upper lip; as it rounds into an 'o' the lip lifts into the top of the ring.
            let L = 0.055 * R * (1 - rd), ty = top - h * 0.35 * rd, cty = top - h * 0.3 * rd + L, bot = top + h * (1.15 + 0.15 * rd) + L * 0.5
            func lip(_ q: CGMutablePath) {
                q.move(to: CGPoint(x: cxm - w, y: top))
                q.addQuadCurve(to: CGPoint(x: cxm, y: ty), control: CGPoint(x: cxm - w * 0.5, y: cty))
                q.addQuadCurve(to: CGPoint(x: cxm + w, y: top), control: CGPoint(x: cxm + w * 0.5, y: cty))
            }
            let open = CGMutablePath()
            lip(open)
            open.addCurve(to: CGPoint(x: cxm - w, y: top), control1: CGPoint(x: cxm + w, y: bot), control2: CGPoint(x: cxm - w, y: bot))
            open.closeSubpath()
            cg.fill(open, CatDraw.color("#3A1218"))
            cg.saveGState()
            cg.clip(open)
            cg.fill(CatDraw.ellipse(cxm, top + h * 0.95, w * 0.62, h * 0.34), tongueColor)
            cg.restoreGState()
            if m > 0.45 && rd < 0.5 && full {
                for sd in [-1.0, 1.0] {
                    let fx = cxm + sd * w * 0.55, fy = top + L * 0.55
                    cg.fill(CatDraw.poly([(fx - 0.022 * R, fy), (fx + 0.022 * R, fy), (fx, fy + 0.055 * R)]), CatDraw.color("#FBF7F0"))
                }
            }
            if tg > 0.05 {
                let tl = (0.03 + 0.07 * tg) * R, tw = max(w * 0.5, 0.05 * R * nf), tty = top + h * 0.9
                let t = CGMutablePath()
                t.move(to: CGPoint(x: cxm - tw, y: top + h * 0.7))
                t.addLine(to: CGPoint(x: cxm - tw, y: tty + tl * 0.4))
                t.addQuadCurve(to: CGPoint(x: cxm, y: tty + tl * 1.2), control: CGPoint(x: cxm - tw, y: tty + tl * 1.2))
                t.addQuadCurve(to: CGPoint(x: cxm + tw, y: tty + tl * 0.4), control: CGPoint(x: cxm + tw, y: tty + tl * 1.2))
                t.addLine(to: CGPoint(x: cxm + tw, y: top + h * 0.7))
                t.closeSubpath()
                cg.fill(t, tongueColor)
                if full {
                    let c = CGMutablePath()
                    c.move(to: CGPoint(x: cxm, y: top + h * 0.95))
                    c.addLine(to: CGPoint(x: cxm, y: tty + tl * 0.9))
                    cg.stroke(c, CatDraw.rgb([150, 50, 70], 0.6), width: lw * 0.6)
                }
            }
            if full {
                let stem = CGMutablePath()
                stem.move(to: CGPoint(x: nx, y: my))
                stem.addLine(to: CGPoint(x: cxm, y: ty))
                cg.stroke(stem, line, width: lw)
                let upper = CGMutablePath()
                lip(upper)
                cg.stroke(upper, CatDraw.color(p.mouthLine, alpha: 1 - rd), width: lw)
            }
            return
        }
        if !full { return }
        if tg > 0.03 {
            let th = (0.025 + 0.045 * tg) * R
            cg.fill(CatDraw.ellipse(cxm, y0 + 0.035 * R + th * 0.5, 0.042 * R * nf, th), tongueColor)
            let c = CGMutablePath()
            c.move(to: CGPoint(x: cxm, y: y0 + 0.04 * R))
            c.addLine(to: CGPoint(x: cxm, y: y0 + 0.035 * R + th * 0.9))
            cg.stroke(c, CatDraw.rgb([150, 50, 70], 0.55), width: lw * 0.5)
        }
        let mw = 0.15 * R * nf * (1 + 0.18 * max(0, sm))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: nx, y: my))
        path.addLine(to: CGPoint(x: cxm, y: y0))
        if wv > 0.05 {
            path.move(to: CGPoint(x: cxm - mw, y: y0 + 0.03 * R))
            for i in 1...24 {
                let t = Double(i) / 24
                path.addLine(to: CGPoint(x: cxm - mw + 2 * mw * t, y: y0 + 0.03 * R + sin(t * CatMath.tau * 2.5 + T * 6) * 0.022 * R * wv))
            }
        } else {
            let lobe = 0.08 * R * (1 - 0.6 * max(0, -sm)), cL = y0 - sm * 0.05 * R - sk * 0.035 * R, cR = y0 - sm * 0.05 * R + sk * 0.035 * R
            path.move(to: CGPoint(x: cxm - mw, y: cL))
            path.addQuadCurve(to: CGPoint(x: cxm, y: y0), control: CGPoint(x: cxm - mw / 2, y: y0 + lobe))
            path.addQuadCurve(to: CGPoint(x: cxm + mw, y: cR), control: CGPoint(x: cxm + mw / 2, y: y0 + lobe))
        }
        cg.stroke(path, line, width: lw)
    }

    // MARK: Whiskers

    /// How many strokes a hair is drawn with: each is a little thinner and a little fainter than the one before.
    private static let hairSegments = 8

    /// The hairs of one width, gathered so that each segment index is stroked once for all of them (a few strokes, not a hundred and fifty).
    @MainActor private struct Hairs {
        var segments = (0..<hairSegments).map { _ in CGMutablePath() }

        /// Adds one hair, a quadratic from (x0,y0) via (cx,cy) to (x1,y1), as `hairSegments` short lines.
        mutating func add(_ x0: Double, _ y0: Double, _ cx: Double, _ cy: Double, _ x1: Double, _ y1: Double) {
            var px = x0, py = y0
            for i in 1...hairSegments {
                let s = Double(i) / Double(hairSegments), m = 1 - s
                let x = m * m * x0 + 2 * m * s * cx + s * s * x1, y = m * m * y0 + 2 * m * s * cy + s * s * y1
                segments[i - 1].move(to: CGPoint(x: px, y: py))
                segments[i - 1].addLine(to: CGPoint(x: x, y: y))
                px = x; py = y
            }
        }

        /// Strokes every segment: each thinner (from `w0`) and fainter (from alpha `a0`) than the one before, so a hair thins and fades toward its tip.
        func stroke(_ cg: CGContext, _ w0: Double, _ col: String, _ a0: Double) {
            for i in 1...hairSegments {
                let s = Double(i) / Double(hairSegments)
                cg.stroke(segments[i - 1], CatDraw.color(col, alpha: a0 * (1 - 0.7 * s)), width: max(0.35, w0 * (1 - 0.88 * s)))
            }
        }
    }

    /// Whiskers rooted on the pad grid beside the nose, plus eyebrow whiskers. Full detail only.
    static func drawWhiskers(_ cg: CGContext, _ p: CatPreset, _ s: CatPose, _ L: G.Layout) {
        let Wk = p.whisk2, R = L.R, W = L.warp, yf = L.yf, fa = L.fa
        let rand = CatRNG(seed: 29), nzy = -sin(p.nosePh) * p.ry
        var hairs = Hairs(), brows = Hairs()
        for sd in [-1.0, 1.0] {
            let fxs = clamp(cos(yf) + sd * 0.37 * sin(yf), 0.15, 1.3)
            var pts: [(row: Int, col: Int, x: Double, y: Double)] = []
            for row in 0..<Wk.rows {
                for col in 0..<Wk.cols {
                    pts.append((row, col, sd * (Wk.x0 + Double(col) * Wk.dx), nzy + Wk.y0 + Double(row) * Wk.dy + Double(col) * Wk.slope))
                }
            }
            let dot = CatDraw.color(p.padDot, alpha: fa)
            for q in pts { let (X, Y) = W(q.x, q.y); cg.fill(CatDraw.circle(X, Y, Wk.dot * R), dot) }
            for q in pts where Wk.wcols.contains(q.col) {
                let (X, Y) = W(q.x, q.y)
                let jitterA = rand.next(), jitterL = rand.next()
                let ang = Wk.a0 + Double(q.row) * Wk.da + Double(q.col) * 0.04 + (jitterA - 0.5) * 0.06 - s.wh
                let len = (Wk.len - Double(q.row) * Wk.dl - Double(q.col) * 0.05 + (jitterL - 0.5) * 0.1) * R
                let dx = sd * cos(ang) * fxs, dy = sin(ang)
                hairs.add(X, Y, X + dx * len * 0.5, Y + dy * len * 0.5 - 0.05 * R, X + dx * len, Y + dy * len + Wk.droop * len * len / R)
            }
            let ex = sin(sd * p.eye.th) * cos(p.eye.ph) * p.rx, ey = -sin(p.eye.ph) * p.ry
            for k in 0..<Wk.brow {
                let kk = Double(k)
                let (bx, by) = W(ex + sd * (kk * 0.06 - 0.03), ey - p.eye.h * 1.9 - kk * 0.015)
                let th = 1.08 - kk * 0.2 - s.wh * 0.5, len = (0.38 + kk * 0.08) * R
                brows.add(bx, by, bx + sd * (cos(th) * len * 0.45 * fxs + 0.07 * R), by - sin(th) * len * 0.55, bx + sd * cos(th) * len * fxs, by - sin(th) * len)
            }
        }
        hairs.stroke(cg, Wk.w * R, p.whisk, Wk.alpha * fa)
        brows.stroke(cg, Wk.w * 0.7 * R, p.whisk, Wk.alpha * 0.85 * fa)
    }
}
```

**Create `NotchBuddy/Sources/App/CatRenderer.swift`:**

```swift
import CoreGraphics
import Foundation

/// Draws a cat. D is the head width in px. The cat is drawn in three passes, so outfits (sub-project I) can sit behind or in front
/// of the head: *behind* (ruff, bib, paws, ears), the head (with its markings and face), then *front* (folded ears, whiskers).
/// The badge, the particles and the hairballs are drawn last, in the world, not in the head's turning frame.
@MainActor
enum CatRenderer {
    typealias G = CatGeometry

    /// Draws one cat and returns its layout (the engine wants `base` and `mouth` back for the hairball).
    @discardableResult
    static func draw(_ cg: CGContext, _ look: CatLook, cx: Double, cy: Double, D: Double, _ o: CatDrawOptions = CatDrawOptions()) -> G.Layout {
        let p = look.preset, s = look.pose
        let level = G.detailLevel(D, override: o.full.map { $0 ? "full" : "compact" })
        let full = level.full
        let flat = level.flatFill ? G.flatFillColors(p) : nil   // the compact detail's flat colours (A-0b's), worked out once per draw
        let ek = full ? 1.0 : G.earScale(D)
        func layout(_ ek: Double) -> G.Layout {
            G.layout(p, s, cx: cx, cy: cy, D: D, G.Options(full: o.full, time: look.time, badgeSide: o.badgeSide, earScale: ek))
        }
        var L = layout(ek)
        if let ceiling = o.earCeiling {
            let f = G.earFit(L, s, ceiling: ceiling)
            if f < 1 { L = layout(ek * f) }
        }
        if o.glow { CatEffects.drawGlow(cg, look, L) }
        CatEffects.drawZoomTrails(cg, look, L)
        cg.saveGState()
        cg.translateBy(x: L.head.x, y: L.head.y)
        cg.rotate(by: s.tilt)
        cg.scaleBy(x: s.sx, y: s.sy)
        drawBehind(cg, look, L, flat)
        drawHead(cg, look, L, o, flat)
        drawFront(cg, p, s, L, flat)
        cg.restoreGState()
        if o.badge, let kind = look.badge, s.badgeS > 0.01 { CatEffects.drawBadge(cg, kind, look.badgeColor, L, look.time) }
        CatEffects.drawParticles(cg, look, L)
        CatEffects.drawBalls(cg, look, L)
        return L
    }

    // MARK: Behind pass

    private static func drawBehind(_ cg: CGContext, _ look: CatLook, _ L: G.Layout, _ flat: G.FlatColors?) {
        let p = look.preset, R = L.R
        // Ruff and neck bib sit behind the head, with a little parallax.
        if let r = p.ruff {
            cg.saveGState()
            cg.translateBy(x: L.ruff.dx, y: L.ruff.dy)
            let rp = CatDraw.poly(G.supPoints(rx: r.rx * R, ry: r.ry * R, n: 2.4, dy: r.dy * R, spike: 0.06, count: 18, steps: L.steps))
            if L.full {
                cg.saveGState()
                cg.clip(rp)
                CatDraw.radial(cg, [(0, CatDraw.color(r.col[1])), (1, CatDraw.color(r.col[0]))], center: (0, r.dy * R), r0: 0.55 * R, r1: 1.55 * R)
                cg.restoreGState()
            } else if let c = flat?.ruff {
                cg.fill(rp, CatDraw.rgb(c))
            }
            if let bib = p.bib {
                let by = (r.ry + r.dy) * R
                let b = CGMutablePath()
                b.move(to: CGPoint(x: -0.2 * R, y: by * 0.97))
                b.addQuadCurve(to: CGPoint(x: 0, y: by * 0.72), control: CGPoint(x: -0.12 * R, y: by * 0.8))
                b.addQuadCurve(to: CGPoint(x: 0.2 * R, y: by * 0.97), control: CGPoint(x: 0.12 * R, y: by * 0.8))
                b.addQuadCurve(to: CGPoint(x: 0.04 * R, y: by * 0.99), control: CGPoint(x: 0.1 * R, y: by * 1.03))
                b.addLine(to: CGPoint(x: 0, y: by * 1.06))
                b.addLine(to: CGPoint(x: -0.04 * R, y: by * 0.99))
                b.addQuadCurve(to: CGPoint(x: -0.2 * R, y: by * 0.97), control: CGPoint(x: -0.1 * R, y: by * 1.03))
                b.closeSubpath()
                cg.fill(b, CatDraw.color(bib))
            }
            cg.restoreGState()
        }
        let paws = look.paws ?? look.wave.map { CatEffects.wavePaws(pawsOut: look.pose.paws, wave: $0, rx: L.rx, ry: L.ry) } ?? []
        for q in paws { CatEffects.drawPaw(cg, p, R, q) }
        for e in L.ears { drawEar(cg, p, e, R: R, full: L.full, front: false, flat: flat?.ears[e.sd < 0 ? 0 : 1]) }
    }

    /// One ear, in the head's frame. `front` is the folded-ear flap, drawn over the head after it. `flat` is the ear's flat colour at the compact detail.
    static func drawEar(_ cg: CGContext, _ p: CatPreset, _ g: G.Ear, R: Double, full: Bool, front: Bool, flat: [Double]?) {
        let E = p.ear, h = g.h, bw = g.bw, tip = g.tip, cx = g.cx, sd = g.sd
        cg.saveGState()
        cg.translateBy(x: g.bx, y: g.by)
        cg.rotate(by: g.rot)
        func outline(_ k: Double) -> CGPath {
            let q = CGMutablePath()
            q.move(to: CGPoint(x: -bw * k, y: 0.25 * R))
            q.addQuadCurve(to: CGPoint(x: -tip * 0.9, y: -h * k + tip * 1.3), control: CGPoint(x: -bw * k * cx, y: -h * k * 0.4))
            q.addQuadCurve(to: CGPoint(x: tip * 0.9, y: -h * k + tip * 1.3), control: CGPoint(x: 0, y: -h * k - tip * 0.35))
            q.addQuadCurve(to: CGPoint(x: bw * k, y: 0.25 * R), control: CGPoint(x: bw * k * cx, y: -h * k * 0.4))
            q.closeSubpath()
            return q
        }
        let ec = p.earCols.map { sd < 0 ? $0[0] : $0[1] }
        let top = CatDraw.color(ec ?? p.top), bot = CatDraw.color(ec ?? p.bot)
        func fillGradient(_ path: CGPath) {
            if let c = flat {
                // Below Ø28 the ear gradient cannot be seen and costs a shading pass per ear: the contract's flat colour does.
                cg.fill(path, CatDraw.rgb(c))
                return
            }
            cg.saveGState()
            cg.clip(path)
            CatDraw.linear(cg, [(0, top), (1, bot)], from: (0, -h), to: (0, 0.25 * R))
            cg.restoreGState()
        }
        // Folded ear (front pass, drawn over the head): the tip folds forward and down over the inner ear, with a soft crease.
        if front {
            let fw = bw * 0.62, yc = -h + tip * 0.8, ty = -h * 0.05
            let flap = CGMutablePath()
            flap.move(to: CGPoint(x: -fw, y: yc))
            flap.addQuadCurve(to: CGPoint(x: fw, y: yc), control: CGPoint(x: 0, y: yc - fw * 0.75))
            flap.addQuadCurve(to: CGPoint(x: 0, y: ty), control: CGPoint(x: fw * 0.7, y: (yc + ty) / 2))
            flap.addQuadCurve(to: CGPoint(x: -fw, y: yc), control: CGPoint(x: -fw * 0.7, y: (yc + ty) / 2))
            flap.closeSubpath()
            cg.saveGState()
            cg.translateBy(x: 0, y: 0.025 * R)
            cg.fill(flap, CatDraw.black(0.2))
            cg.restoreGState()
            fillGradient(flap)
            if full {
                cg.stroke(CatDraw.quad(-fw * 0.8, yc + 0.02 * R, 0, yc - fw * 0.5, fw * 0.8, yc + 0.02 * R), CatDraw.black(0.2), width: 0.016 * R)
            }
            cg.restoreGState()
            return
        }
        fillGradient(outline(1))
        if p.rimLight != nil {
            cg.stroke(outline(1), CatDraw.white(0.22), width: max(0.8, 0.013 * R), join: .miter)
        }
        cg.fill(outline(0.6), CatDraw.color(p.inner, alpha: 0.9))
        if E.tuft != 0 && full {
            let inner = CatDraw.color(p.inner, alpha: 0.7)
            for k in [-1.0, 0.0, 1.0] {
                let t = CGMutablePath()
                t.move(to: CGPoint(x: k * bw * 0.3, y: 0.06 * R))
                t.addQuadCurve(to: CGPoint(x: k * bw * 0.42 + (k >= 0 ? 1 : -1) * 0.02 * R, y: -h * 0.5), control: CGPoint(x: k * bw * 0.5, y: -h * 0.25))
                cg.stroke(t, inner, width: 0.022 * R)
            }
            let t = CGMutablePath()
            t.move(to: CGPoint(x: 0, y: -h + tip * 0.2))
            t.addLine(to: CGPoint(x: sd * 0.015 * R, y: -h - 0.05 * R))
            cg.stroke(t, CatDraw.color(p.top), width: 0.025 * R)
        }
        cg.restoreGState()
    }

    // MARK: Head pass

    private static func drawHead(_ cg: CGContext, _ look: CatLook, _ L: G.Layout, _ o: CatDrawOptions, _ flat: G.FlatColors?) {
        let p = look.preset, s = look.pose, R = L.R, rx = L.rx, ry = L.ry, fa = L.fa, W = L.warp
        let head = CatDraw.poly(G.supPoints(rx: rx, ry: ry, n: p.n, dy: 0, spike: p.fluff != 0 ? 0.035 : 0, count: 14, steps: L.steps, bend: L.bend))
        if L.full {
            cg.saveGState()
            cg.clip(head)
            CatDraw.linear(cg, [(0, CatDraw.color(p.top)), (1, CatDraw.color(p.bot))], from: (0.45 * rx, -ry), to: (-0.45 * rx, ry))
            cg.restoreGState()
        } else if let c = flat?.head {
            // Below Ø28 the coat's top-to-bottom shading cannot be seen: one flat fill instead of a shading pass.
            cg.fill(head, CatDraw.rgb(c))
        }

        cg.saveGState()
        cg.clip(head)
        cg.setAlpha(fa)
        drawMarkings(cg, p, L, flat)
        cg.setAlpha(1)
        // The state tint, rising from the chin.
        if o.tint && s.tint > 0.01 {
            let c = look.color.map { $0.rounded() }
            CatDraw.linear(cg, [(0, CatDraw.rgb(c, 0.4 * s.tint)), (1, CatDraw.rgb(c, 0))], from: (0, ry), to: (0, -ry * 0.2))
        }
        // A soft edge: dark on dark coats, a rim light on the rest. Nothing happens inside 0.913 R, so the shading starts there.
        // (Below Ø28 it is skipped: it would be a few pixels of shading.)
        if L.full {
            CatDraw.radial(cg, [(0, CatDraw.black(0)), (1, p.rimLight != nil ? CatDraw.white(0.07) : CatDraw.black(0.25))],
                           center: (0, 0), r0: 0.913 * R, r1: 1.35 * R)
        }
        let bl = max(s.blush, look.blushBase)
        if bl > 0.01 {
            for sd in [-1.0, 1.0] { cg.fill(wEll(W, sd * p.blushAt[0], p.blushAt[1], 0.17, 0.1, 14), CatDraw.rgb([255, 120, 150], 0.5 * bl * fa)) }
        }
        CatFace.drawEyes(cg, look, L)
        CatFace.drawNoseAndMouth(cg, look, L)
        cg.restoreGState()
        if p.rimLight != nil { cg.stroke(head, CatDraw.white(0.22), width: max(1, 0.013 * R)) }
    }

    // MARK: Markings (drawn flat, warped onto the turning head)

    private static func wEll(_ W: G.Warp, _ x: Double, _ y: Double, _ a: Double, _ b: Double, _ n: Int = 20) -> CGPath {
        CatDraw.poly((0...n).map { i in let t = Double(i) / Double(n) * CatMath.tau; return W(x + a * cos(t), y + b * sin(t)) })
    }

    private static func wBlob(_ W: G.Warp, _ x: Double, _ y: Double, _ a: Double, _ b: Double, _ rot: Double, _ seed: Double, _ n: Int = 32) -> CGPath {
        let c = cos(rot), s = sin(rot)
        return CatDraw.poly((0...n).map { i in
            let t = Double(i) / Double(n) * CatMath.tau, k = 1 + 0.12 * sin(3 * t + seed) + 0.06 * sin(5 * t + 2 * seed)
            let lx = a * cos(t) * k, ly = b * sin(t) * k
            return W(x + lx * c - ly * s, y + lx * s + ly * c)
        })
    }

    /// A quadratic stroke drawn flat and bent by the warp: (x0,y0) via (cx,cy) to (x1,y1).
    private static func wStroke(_ cg: CGContext, _ W: G.Warp, _ col: CGColor, _ w: Double, _ x0: Double, _ y0: Double, _ cx: Double, _ cy: Double, _ x1: Double, _ y1: Double) {
        let path = CGMutablePath()
        for i in 0...12 {
            let t = Double(i) / 12, m = 1 - t
            let q = W(m * m * x0 + 2 * m * t * cx + t * t * x1, m * m * y0 + 2 * m * t * cy + t * t * y1)
            i == 0 ? path.move(to: CGPoint(x: q.0, y: q.1)) : path.addLine(to: CGPoint(x: q.0, y: q.1))
        }
        cg.stroke(path, col, width: w)
    }

    private static func drawMarkings(_ cg: CGContext, _ p: CatPreset, _ L: G.Layout, _ flat: G.FlatColors?) {
        let R = L.R, W = L.warp, full = L.full
        let ny = -sin(p.nosePh) * p.ry
        switch p.coat {
        case "tuxedo":
            cg.fill(CatDraw.poly(G.momoWhite.map { W($0.0, $0.1) }), CatDraw.color(p.white ?? "#FFFFFF"))
        case "tabby":
            let stripe = CatDraw.color(p.stripe ?? "#000000"), sc = hexRGB(p.stripe ?? "#000000")
            let (bx, by) = W(0, -0.88)
            if full {
                CatDraw.radial(cg, [(0, CatDraw.rgb(sc, 0.9)), (1, CatDraw.rgb(sc, 0))], center: (bx, by), r0: 0, r1: 0.6 * R)
            } else {
                cg.fill(CatDraw.ellipse(bx, by, G.FlatFill.crown.rx * R, G.FlatFill.crown.ry * R), CatDraw.rgb(sc, G.FlatFill.crown.alpha))   // the crown band, without the shading pass
            }
            wStroke(cg, W, stripe, (full ? 0.1 : 0.13) * R, 0, -0.95, 0, -0.62, 0, -0.36)
            if full {
                for i in [-2.0, -1.0, 1.0, 2.0] { wStroke(cg, W, stripe, 0.042 * R, i * 0.05, -0.3 + abs(i) * 0.07, i * 0.09, -0.62, i * 0.17, -0.98) }
                for sd in [-1.0, 1.0] {
                    wStroke(cg, W, stripe, 0.04 * R, sd * 0.62, 0.04, sd * 0.82, -0.02, sd * 1.02, -0.08)
                    wStroke(cg, W, stripe, 0.045 * R, sd * 0.7, 0.3, sd * 0.88, 0.22, sd * 1.1, 0.22)
                    wStroke(cg, W, stripe, 0.045 * R, sd * 0.72, 0.46, sd * 0.9, 0.42, sd * 1.1, 0.46)
                }
            }
            for sd in [-1.0, 1.0] { cg.fill(wEll(W, sd * 0.17, ny + 0.12, 0.26, 0.21), CatDraw.color(p.light ?? p.top)) }
            cg.fill(wEll(W, 0, ny + 0.34, 0.22, 0.16), CatDraw.color(p.chinCol ?? p.top))
        case "point":
            let (mx, my) = W(0, ny - 0.12), pc = hexRGB(p.point ?? "#000000")
            if full {
                cg.saveGState()
                cg.translateBy(x: mx, y: my)
                cg.scaleBy(x: 1.55, y: 1)
                CatDraw.radial(cg, [(0, CatDraw.rgb(pc, 0.97)), (0.6, CatDraw.rgb(pc, 0.82)), (1, CatDraw.rgb(pc, 0))], center: (0, 0), r0: 0.05 * R, r1: 0.66 * R)
                cg.restoreGState()
            } else if let c = flat?.point {
                // The contract's flat mask: the colour is `flatFillColors(p).point`, the size and alpha are `FlatFill.point`.
                cg.fill(CatDraw.ellipse(mx, my, G.FlatFill.point.rx * R, G.FlatFill.point.ry * R), CatDraw.rgb(c, G.FlatFill.point.alpha))
            }
        case "calico":
            for q in p.patches ?? [] { cg.fill(wBlob(W, q.x, q.y, q.a, q.b, q.rot, Double(q.seed)), CatDraw.color(q.color)) }
        default:
            break
        }
        if let m = p.muzzle {
            for sd in [-1.0, 1.0] { cg.fill(wEll(W, sd * 0.16, ny + 0.12, 0.24, 0.19), CatDraw.color(m)) }
            cg.fill(wEll(W, 0, ny + 0.32, 0.2, 0.14), CatDraw.color(m))
        }
        if p.wrinkles != nil && full {
            for (y, w) in [(-0.42, 0.2), (-0.54, 0.27), (-0.66, 0.18)] { wStroke(cg, W, CatDraw.color(p.bot), 0.026 * R, -w, y + 0.03, 0, y - 0.05, w, y + 0.03) }
        }
    }

    // MARK: Front pass

    private static func drawFront(_ cg: CGContext, _ p: CatPreset, _ s: CatPose, _ L: G.Layout, _ flat: G.FlatColors?) {
        let R = L.R
        if p.ear.fold != nil { for e in L.ears { drawEar(cg, p, e, R: R, full: L.full, front: true, flat: flat?.ears[e.sd < 0 ? 0 : 1]) } }
        if L.full && L.fa > 0.01 { CatFace.drawWhiskers(cg, p, s, L) }
    }
}
```

- [ ] **Step 4: Run the test**

Run: `bash scripts/test-cat-renderer.sh`
Expected: PASS

- [ ] **Step 5: Prove the tests bite**

Each change below is made on its own, the test run with `bash scripts/test-cat-renderer.sh`, the failure seen, and the change undone before the next.

In `tests/CatRendererTests.swift`:
1. Replace `CatDrawOptions(earCeiling: Double(pad))` with `CatDrawOptions()`: "nothing above the strip is painted more than a hair (worst alpha 255 of 255)" and "the hop pushes ears out of the strip, so the fit has work to do (0 cases)" fail.

In `CatRenderer.swift`:
2. In `drawHead`, change `if L.full {` (the first one, around the head's fill) to `if true {`, so that every size is shaded: the five "one flat colour" lines fail, and so does "every coat's flat head, ears and ruff, …" (the head's flat colour then covers only 271 of 2888 pixels on Shrimpy).
3. In `drawEar`, change `cg.fill(path, CatDraw.rgb(c))` to `cg.fill(path, top)` (the ears use the coat's own colour): the flat-fill line fails with "ear 0 is [160.0, 138.0, 112.0, 255.0], not its flat colour [135.0, 114.5, 92.5]" for the coats whose ears are not their own colour.
4. In `drawBehind`, change `cg.fill(rp, CatDraw.rgb(c))` to `cg.fill(rp, CatDraw.color(r.col[0]))` (the ruff's outer colour): "the ruff's flat colour covers only 0 pixels" for Shrimpy and Puff, and a handful for Snow and Cloud.
5. In `drawMarkings`, change `CatDraw.rgb(sc, G.FlatFill.crown.alpha)` to `CatDraw.rgb(sc, 0.9)`: "inside the crown band … is not the stripe at alpha 0.5 over the head". Then change `G.FlatFill.crown.rx * R, G.FlatFill.crown.ry * R` to `0.6 * R, G.FlatFill.crown.ry * R`: "outside the crown band … is not the flat head".
6. In `drawMarkings`, change `G.FlatFill.point.rx * R, G.FlatFill.point.ry * R` to `0.5 * R, 0.34 * R` (the draft's mask): "above the point mask" and "beside the point mask" fail on Latte and Cloud. Then change `CatDraw.rgb(c, G.FlatFill.point.alpha)` to `CatDraw.rgb(c, 0.5)`: the same lines fail on the colour.
7. In `draw`, change `let ek = full ? 1.0 : G.earScale(D)` to `let ek = 1.0` (no compact ear scale): the four "is drawn with the compact ear scale" lines fail. Then change it to `let ek = G.isFull(D) ? 1.0 : G.earScale(D)` (a forced full detail ignored): "drawn at full detail, a small cat keeps its full-size ears (scale 1)" fails.
8. In `draw`, change `if f < 1 { L = layout(ek * f) }` to `if f < 1 { L = layout(f) }` (the fit forgets the compact scale): "under a ceiling the ears are earScale(D) * f" fails, and so do the margin line and "nothing above the strip".
9. In `draw`, change `let f = G.earFit(L, s, ceiling: ceiling)` to `let f = G.earFit(L, s, ceiling: ceiling, margin: 0)`: "under a ceiling the ears are earScale(D) * f" and "5 coats, 6 poses: … a shrunk ear sits on the margin 0.5" fail, while "nothing above the strip" still passes (the ears are inside the strip, only less tightly fitted).

Restore each line and run the test again.

- [ ] **Step 6: Write the contact-sheet script**

**Create `scripts/render-cats.swift`:**

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the cats into a PNG contact sheet with the real CatRenderer, without launching the app.
// Run it through scripts/render-cats.sh:
//   bash scripts/render-cats.sh --out cats.png                     every coat at every size, plus kittens
//   bash scripts/render-cats.sh --cats shrimpy,momo --out two.png  only these coats (IDs)
//   bash scripts/render-cats.sh --stage --cats shrimpy,momo        the big cats on stage panels, like the prototype's Cats section
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

@main
enum RenderCats {
    /// A bitmap context whose y axis points down, in points, like a SwiftUI Canvas.
    final class Sheet {
        let cg: CGContext
        let width: Double, height: Double, scale: Double
        init(width: Double, height: Double, scale: Double) {
            self.width = width; self.height = height; self.scale = scale
            let w = Int((width * scale).rounded(.up)), h = Int((height * scale).rounded(.up))
            cg = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            cg.translateBy(x: 0, y: CGFloat(h))
            cg.scaleBy(x: CGFloat(scale), y: CGFloat(-scale))
            cg.setAllowsAntialiasing(true)
            cg.setShouldAntialias(true)
            cg.interpolationQuality = .high
            cg.setFillColor(CGColor(srgbRed: 0.059, green: 0.063, blue: 0.071, alpha: 1))
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        func write(to path: String) {
            let image = cg.makeImage()!
            let url = URL(fileURLWithPath: path)
            let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, image, nil)
            precondition(CGImageDestinationFinalize(dest), "could not write \(path)")
        }
    }

    enum Mode {
        case ladder, stage
    }

    struct Args {
        var out = "cats.png"
        var scale = 2.0
        var cats = CatPresets.ids
        var sizes: [Double] = [12, 16, 20, 24, 28, 44, 66]
        var kittens: [Double] = [16, 40]
        var mode = Mode.ladder
    }

    static func parse() -> Args {
        var a = Args()
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": a.out = it.next() ?? a.out
            case "--scale": a.scale = Double(it.next() ?? "") ?? a.scale
            case "--cats": a.cats = (it.next() ?? "").split(separator: ",").map(String.init).filter { CatPresets.all[$0] != nil }
            case "--sizes": a.sizes = (it.next() ?? "").split(separator: ",").compactMap { Double($0) }
            case "--stage": a.mode = .stage
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        return a
    }

    @MainActor static func main() {
        let a = parse()
        let sheet: Sheet
        switch a.mode {
        case .ladder: sheet = ladder(a)
        case .stage: sheet = stage(a)
        }
        sheet.write(to: a.out)
        print("wrote \(a.out)")
    }








    // MARK: Stage panels: the big cats, the way the prototype shows them

    private static let panelW = 560.0, panelH = 450.0

    @MainActor static func stage(_ a: Args) -> Sheet {
        let sheet = Sheet(width: panelW * Double(a.cats.count), height: panelH, scale: a.scale)
        for (i, id) in a.cats.enumerated() {
            let cg = sheet.cg, ox = Double(i) * panelW, p = CatPresets.byID(id)
            cg.saveGState()
            cg.clip(CatDraw.roundRect(ox + 4, 4, panelW - 8, panelH - 8, 14))
            cg.fill(CatDraw.roundRect(ox, 0, panelW, panelH, 0), CatDraw.black(1))
            CatDraw.text(cg, p.label, x: ox + 40, y: 22, size: 13, bold: true, color: CatDraw.white(0.9))
            CatRenderer.draw(cg, CatLook(preset: p), cx: ox + panelW / 2, cy: panelH * 0.57, D: min(panelW * 0.4, panelH * 0.5))
            cg.restoreGState()
        }
        return sheet
    }

    // MARK: Size ladder: every coat at every size, then its kittens

    private static let rowH = 150.0
    private static func slotW(_ d: Double) -> Double { max(62, d * 2.2) }

    @MainActor static func ladder(_ a: Args) -> Sheet {
        let widths = a.sizes.map(slotW) + a.kittens.map(slotW)
        let sheet = Sheet(width: 150 + widths.reduce(0, +) + 24, height: rowH * Double(a.cats.count) + 8, scale: a.scale)
        let cg = sheet.cg
        for (ri, id) in a.cats.enumerated() {
            let top = Double(ri) * rowH + 4, p = CatPresets.byID(id)
            CatDraw.text(cg, p.label, x: 60, y: top + rowH / 2 - 6, size: 13, bold: true, color: CatDraw.white(0.92))
            CatDraw.text(cg, p.desc ?? id, x: 60, y: top + rowH / 2 + 12, size: 10, bold: false, color: CatDraw.white(0.5))
            var x = 130.0
            let cells: [(Double, CatPreset, String)] = a.sizes.map { ($0, p, "Ø\(Int($0))") } + a.kittens.map { ($0, CatPresets.kitten(of: p), "kitten Ø\(Int($0))") }
            for (d, preset, label) in cells {
                let w = slotW(d), cx = x + w / 2, cy = top + 20 + rowH * 0.42
                cg.fill(CatDraw.roundRect(x + 4, top + 22, w - 8, rowH - 46, 10), CatDraw.black(1))
                CatRenderer.draw(cg, CatLook(preset: preset), cx: cx, cy: cy, D: d)
                CatDraw.text(cg, label, x: cx, y: top + rowH - 10, size: 10, bold: false, color: CatDraw.white(0.55))
                x += w
            }
        }
        return sheet
    }
}
```

**Create `scripts/render-cats.sh`:**

```bash
#!/usr/bin/env bash
# Renders the cats into a PNG contact sheet with the real CatRenderer, without launching the app.
#   bash scripts/render-cats.sh --out cats.png [--cats shrimpy,momo] [--sizes 12,20,66] [--scale 2]
# The other modes (--stage, --states, --emotes, --mouths, --catch, --greeting, --bench) are listed at the top of scripts/render-cats.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-cats.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatRenderer.swift \
    scripts/render-cats.swift \
    -o "$BUILD_DIR/render-cats"
"$BUILD_DIR/render-cats" "$@"
```

- [ ] **Step 7: Render the sheets**

Run: `mkdir -p "${TMPDIR:-/tmp}/a-mac-sheets" && bash scripts/render-cats.sh --out "${TMPDIR:-/tmp}/a-mac-sheets/stage1-ladder.png" && bash scripts/render-cats.sh --stage --cats shrimpy,momo --scale 1 --out "${TMPDIR:-/tmp}/a-mac-sheets/stage1-stage.png"`
Expected: PASS

- [ ] **Step 8: Put the prototype next to it**

Make a folder outside the repo and a Playwright script that screenshots the prototype's size ladder and its two big cats, with its clock frozen so the shots do not move (`playwright-cli` is at `~/.local/bin/playwright-cli`; its `open` refuses `file:` URLs but `run-code` can go to one):

```bash
mkdir -p "$TMPDIR/a-mac-check" && cat > "$TMPDIR/a-mac-check/shots-stage1.js" <<EOF
async page => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.addInitScript(() => {
    let t = 0; const cbs = [];
    performance.now = () => t;
    window.requestAnimationFrame = cb => { cbs.push(cb); return cbs.length; };
    window.__step = (n, dt = 1000 / 60) => { for (let i = 0; i < n; i++) { t += dt; const q = cbs.splice(0); q.forEach(f => f(t)); } };
    Math.random = () => { const x = Math.sin(t * 12.9898 + 78.233) * 43758.5453; return x - Math.floor(x); };
  });
  await page.goto('file://$PWD/design/prototype/notchmeow.html');
  await page.evaluate(() => window.__step(90));
  await page.evaluate(() => { mx = null; });
  await page.evaluate(() => window.__step(60));
  await page.locator('#ladder').screenshot({ path: '$TMPDIR/a-mac-check/proto-ladder.png' });
  await page.locator('#figMomo').screenshot({ path: '$TMPDIR/a-mac-check/proto-momo.png' });
  await page.locator('#figShrimpy').screenshot({ path: '$TMPDIR/a-mac-check/proto-shrimpy.png' });
}
EOF
cd "$TMPDIR/a-mac-check" && ~/.local/bin/playwright-cli -s=amac open about:blank && ~/.local/bin/playwright-cli -s=amac run-code --filename=shots-stage1.js && ~/.local/bin/playwright-cli -s=amac close; cd -
```

- [ ] **Step 9: Look at them, and fix what does not match**

Open `stage1-stage.png` next to `proto-momo.png` and `proto-shrimpy.png`, and `stage1-ladder.png` next to `proto-ladder.png`. The big cats should be the same drawing (the prototype has a faint white glow behind them that the sheet leaves out; the sheet draws the glow only for states). At the small sizes the ears are smaller than the prototype's below Ø28 (that is the compact ear scale, on purpose) and the compact cats have flat shading. Check: all 16 coats and both kitten sizes are there; Ø28 is the first full-detail size (whiskers, irises); Latte and Cloud have their pointed masks; Patches and Mocha their patches; Button's ears fold forward; Noodle has forehead wrinkles. If a coat or a shape differs, fix the renderer (not the fixtures) and re-run the test.

- [ ] **Step 10: Build the app with the new files in it**

The cat files are in the app target now (the app does not use them yet).

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO`
Expected: PASS

- [ ] **Step 11: Commit**

```bash
git add tests/CatRendererTests.swift scripts/test-cat-renderer.sh NotchBuddy/Sources/App/CatFace.swift NotchBuddy/Sources/App/CatRenderer.swift scripts/render-cats.swift scripts/render-cats.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): the still cat renderer (behind, head and front passes, every coat) and the contact-sheet script

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 12: Owner checkpoint 1**

Send the owner `stage1-ladder.png` and `stage1-stage.png` next to `proto-ladder.png`, `proto-momo.png` and `proto-shrimpy.png`. Say plainly that the compact ear scale (0.8 at Ø20 and below, easing to 1 at Ø28) is a number the spec leaves open and is the one thing to confirm on the sheet. **If the owner changes it, stop the session and report the new number.** This plan never edits `cat-core.js` or its fixtures: the main session changes `COMPACT_EAR_SCALE` once, in `design/prototype/cat-core.js`, regenerates `tests/fixtures/cat/` (`node scripts/gen-cat-fixtures.mjs`) and commits both on `notchmeow/rebrand`. Then this branch picks it up: `git merge notchmeow/rebrand`, and set `compactEarScale` in `CatGeometry.swift` to the new number (Task 2's "compact ear scale" check reads the fixture and fails until the two agree). Wait for the owner's answer before Task 5.

---

### Task 5: Personality and the cat's rules (stage 2, ahead of the engine)

Agent: `nm-implementer-light`. Personality is stage 3 in the spec; it comes here because the engine's update loop reads the multipliers on every frame (Balanced is neutral, and the Settings rows come later).

**Files:**
- Create: `tests/CatPersonalityTests.swift`, `tests/CatRulesTests.swift`, `scripts/test-cat-personality.sh`, `scripts/test-cat-rules.sh`
- Create: `NotchBuddy/Sources/App/Personality.swift`, `NotchBuddy/Sources/App/CatRules.swift`

**Interfaces:**
- Consumes: `lerp`, `clamp`, `tm` (Task 2); `tests/fixtures/cat/personality-cases.json`, `sequence-cases.json` (work clock, sleep, wake) and `search-tools.json`.
- Produces `struct CatPersonality: Codable, Equatable, Sendable` (`preset: String` and the six traits `energy`, `curiosity`, `chatty`, `affection`, `sass`, `mischief`, 0.5 by default; `subscript(_ trait: String) -> Double?`), `struct CatMultipliers: Encodable` (`speed`, `hop`, `blinkEvery`, `pupil`, `lid`, `gaze`, `earFlickEvery`, `chatter`, `smile`, `blush`, `slowBlinkEvery`, `skew`, `earBack`, `idle`, `poke`, `pokeHiss`) and `enum Personality`: `traits`, `presets` (Balanced, Chill, Grumpy, Sweet, Hyper, Chatty), `named(_:)` (unknown gives Balanced), `slide(_:trait:value:)` (the value held to 0...1 and the preset becomes `"custom"`; an unknown trait or a non-finite value changes nothing), `sanitized(_ raw: [String: Any])` (a hand-edited settings value: a missing, non-numeric or NaN trait is 0.5, anything else is held to 0...1), `multipliers(_:)` for a `CatPersonality` or a raw dictionary.
- Produces `enum CatState: String, CaseIterable` (`idle, working, thinking, searching, approval, question, error, finished, ratelimit, sleeping, dizzy`; `isBusy`) and `enum CatRules`: `zoomAfterMs` (5 minutes), `WorkClock`, `workClockStep(_:state:nowMs:)`, `zoomiesOnFinish(workedForMs:thresholdMs:)`, `sleepAfterMs` (10 minutes), `sleepDelay(state:quietMs:) -> Double?` (only an idle cat sleeps), `wakeEvents`, `wakes(_:)`, `searchTools`, `isSearchTool(_:)`, `toolState(_:)`.

- [ ] **Step 1: Write the failing tests**

**Create `tests/CatPersonalityTests.swift`:**

```swift
import Foundation

@main
enum CatPersonalityTests {
    @MainActor static func main() {
        let want = CT.fixture("personality-cases.json")

        CT.section("the six traits and the six presets")
        let traits = (want["traits"] as! [[String: Any]]).map { ($0["key"] as! String, $0["label"] as! String, $0["low"] as! String, $0["high"] as! String) }
        CT.checkJSON("traits", got: Personality.traits.map { [$0.key, $0.label, $0.low, $0.high] }, want: traits.map { [$0.0, $0.1, $0.2, $0.3] })
        let presets = want["presets"] as! [String: [String: Any]]
        CT.check("preset order", Personality.presets.map { $0.key }, ["balanced", "chill", "grumpy", "sweet", "hyper", "chatty"])
        for p in Personality.presets {
            let w = presets[p.key]!
            CT.checkJSON("preset \(p.key)", got: ["label": p.label, "energy": p.traits.energy, "curiosity": p.traits.curiosity, "chatty": p.traits.chatty,
                                                   "affection": p.traits.affection, "sass": p.traits.sass, "mischief": p.traits.mischief] as [String: Any], want: w)
        }
        CT.check("Balanced is the default personality", CatPersonality(), Personality.named("balanced"))

        CT.section("traits to multipliers and idle habits")
        for c in want["cases"] as! [[String: Any]] {
            CT.checkJSON(c["name"] as! String, got: CT.json(Personality.multipliers(c["traits"] as! [String: Any])), want: c["out"]!)
        }

        CT.section("moving a slider turns the preset into Custom")
        for c in want["slide"] as! [[String: Any]] {
            let out = Personality.slide(Personality.named(c["from"] as! String), trait: c["trait"] as! String, value: (c["value"] as! NSNumber).doubleValue)
            CT.checkJSON("\(c["from"]!) \(c["trait"]!) \(c["value"]!)", got: CT.json(out), want: c["out"]!)
        }

        CT.section("hostile input never leaves 0 to 1, NaN or a wrong type")
        let hostile: [[String: Any]] = [[:], ["energy": 7, "sass": -3], ["energy": "high", "curiosity": NSNull(), "chatty": true, "affection": [1], "sass": [String: Any](), "mischief": "0.9"],
                                        ["energy": Double.nan, "sass": Double.infinity]]
        for h in hostile {
            let p = Personality.sanitized(h)
            let all = [p.energy, p.curiosity, p.chatty, p.affection, p.sass, p.mischief]
            CT.checkTrue("sanitized \(h.keys.sorted()) stays in 0...1", all.allSatisfy { $0 >= 0 && $0 <= 1 && $0.isFinite })
        }
        CT.check("a missing trait counts as 0.5", Personality.sanitized([:]).energy, 0.5)
        CT.check("an unknown preset name gives Balanced", Personality.named("nonsense"), Personality.named("balanced"))
        CT.check("NaN is not a slider value", Personality.slide(Personality.named("chill"), trait: "sass", value: .nan), Personality.named("chill"))
        CT.finish()
    }
}
```

**Create `scripts/test-cat-personality.sh`:**

```bash
#!/usr/bin/env bash
# Cat personality: the six presets, traits to multipliers and idle habits, and the Custom rule against personality-cases.json.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-personality.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/CatMath.swift NotchBuddy/Sources/App/Personality.swift \
    tests/CatTestSupport.swift tests/CatPersonalityTests.swift \
    -o "$TEST_DIR/cat-personality-tests"
"$TEST_DIR/cat-personality-tests"
```

**Create `tests/CatRulesTests.swift`:**

```swift
import Foundation

@main
enum CatRulesTests {
    static func num(_ x: Any?) -> Double { (x as! NSNumber).doubleValue }

    @MainActor static func main() {
        let seq = CT.fixture("sequence-cases.json"), tools = CT.fixture("search-tools.json")

        CT.section("the work clock earns zoomies after five minutes")
        CT.check("the threshold is five minutes", CatRules.zoomAfterMs, num(seq["zoomAfterMs"]))
        for c in seq["workClock"] as! [[String: Any]] {
            var clock = CatRules.WorkClock()
            var got: [[String: Any]] = []
            for step in c["steps"] as! [[Any]] {
                let t = num(step[0]), st = CatState(rawValue: step[1] as! String)!
                clock = CatRules.workClockStep(clock, state: st, nowMs: t)
                got.append(["tMs": t, "state": st.rawValue, "busySince": clock.busySince.map { $0 as Any } ?? NSNull(), "workedFor": clock.workedFor])
            }
            CT.checkJSON(c["name"] as! String, got: got, want: c["after"]!)
            if let want = c["zoomiesAtFinish"] as? Bool { CT.check("  zoomies at the finish", CatRules.zoomiesOnFinish(workedForMs: clock.workedFor), want) }
        }
        CT.check("the clock stepping backwards never goes negative", CatRules.workClockStep(.init(busySince: 1000), state: .finished, nowMs: 500).workedFor, 0)

        CT.section("only an idle cat sleeps, after ten minutes of quiet")
        let sleep = seq["sleep"] as! [String: Any]
        CT.check("ten minutes", CatRules.sleepAfterMs, num(sleep["afterMs"]))
        var diffs: [String] = []
        for c in sleep["cases"] as! [[String: Any]] {
            let got = CatRules.sleepDelay(state: CatState(rawValue: c["state"] as! String)!, quietMs: num(c["quietMs"]))
            let want = c["delayMs"] as? NSNumber
            if got != want?.doubleValue { diffs.append("\(c["state"]!) quiet \(c["quietMs"]!): \(String(describing: got)) vs \(String(describing: want))") }
        }
        CT.checkRows("\((sleep["cases"] as! [Any]).count) cases, approval and question never sleep", diffs)
        CT.check("a non-finite quiet time counts as 0", CatRules.sleepDelay(state: .idle, quietMs: .nan), CatRules.sleepAfterMs)
        for w in sleep["wake"] as! [[String: Any]] { CT.check("\"\(w["kind"]!)\" wakes: \(w["wakes"]!)", CatRules.wakes(w["kind"] as! String), w["wakes"] as! Bool) }

        CT.section("which tool names mean searching")
        CT.checkJSON("the lists", got: CatRules.searchTools, want: tools["agents"]!)
        for c in tools["cases"] as! [[String: Any]] {
            let name = c["tool"] as! String
            CT.check("\"\(name)\" is \(c["state"]!)", [CatRules.isSearchTool(name) ? "yes" : "no", CatRules.toolState(name).rawValue], [(c["searching"] as! Bool) ? "yes" : "no", c["state"] as! String])
        }
        CT.check("a missing tool name is plain work", CatRules.toolState(nil), CatState.working)
        CT.finish()
    }
}
```

**Create `scripts/test-cat-rules.sh`:**

```bash
#!/usr/bin/env bash
# Cat rules: the work clock and zoomies, the sleep timer, what wakes a cat and the search tool names
# against sequence-cases.json and search-tools.json.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-rules.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/CatRules.swift \
    tests/CatTestSupport.swift tests/CatRulesTests.swift \
    -o "$TEST_DIR/cat-rules-tests"
"$TEST_DIR/cat-rules-tests"
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash scripts/test-cat-personality.sh`
Expected: FAIL (swiftc cannot open `NotchBuddy/Sources/App/Personality.swift`)

Run: `bash scripts/test-cat-rules.sh`
Expected: FAIL (swiftc cannot open `NotchBuddy/Sources/App/CatRules.swift`)

- [ ] **Step 3: Write personality and the rules**

**Create `NotchBuddy/Sources/App/Personality.swift`:**

```swift
import Foundation

// Personality: six traits, 0…1, that bend the behaviour a cat already has. 0.5 is neutral, so the Balanced preset is exactly
// the approved motion (and Classic stays 1:1 with upstream). Any coat can wear any personality. Port of the "Personality"
// section of design/prototype/cat-core.js; tests/fixtures/cat/personality-cases.json pins it.

/// A cat's personality as it is stored: a preset name plus the six traits. Moving a slider makes the preset "custom".
struct CatPersonality: Codable, Equatable, Sendable {
    var preset = "balanced"
    var energy = 0.5
    var curiosity = 0.5
    var chatty = 0.5
    var affection = 0.5
    var sass = 0.5
    var mischief = 0.5

    /// A trait by its key; nil for a name that is not a trait.
    subscript(_ trait: String) -> Double? {
        get {
            switch trait {
            case "energy": return energy
            case "curiosity": return curiosity
            case "chatty": return chatty
            case "affection": return affection
            case "sass": return sass
            case "mischief": return mischief
            default: return nil
            }
        }
        set {
            guard let v = newValue else { return }
            switch trait {
            case "energy": energy = v
            case "curiosity": curiosity = v
            case "chatty": chatty = v
            case "affection": affection = v
            case "sass": sass = v
            case "mischief": mischief = v
            default: break
            }
        }
    }
}

/// What a personality changes, as numbers. The engine reads only these.
/// `speed`, `hop`, `blinkEvery`, `gaze`, `earFlickEvery`, `chatter` and `slowBlinkEvery` are multipliers (1 at neutral);
/// `pupil`, `smile`, `skew`, `blush`, `lid` and `earBack` are added to the resting pose (0 at neutral);
/// `idle` says which idle habits are on; `poke` is the reaction to a poke and `pokeHiss` adds a hiss to it.
struct CatMultipliers: Encodable, Equatable, Sendable {
    struct Idle: Encodable, Equatable, Sendable {
        var yawn: Bool, zoomies: Bool, mew: Bool, purr: Bool, hmph: Bool, wink: Bool
    }
    var speed: Double, hop: Double, blinkEvery: Double, pupil: Double, lid: Double, gaze: Double, earFlickEvery: Double
    var chatter: Double, smile: Double, blush: Double, slowBlinkEvery: Double, skew: Double, earBack: Double
    var idle: Idle
    /// "love" or "annoyed".
    var poke: String
    var pokeHiss: Bool
}

enum Personality {
    /// The six traits, in the order Settings shows them: key, label, low end, high end.
    static let traits: [(key: String, label: String, low: String, high: String)] = [
        ("energy", "Energy", "sleepy", "bouncy"), ("curiosity", "Curiosity", "aloof", "nosy"), ("chatty", "Chattiness", "quiet", "talkative"),
        ("affection", "Affection", "independent", "cuddly"), ("sass", "Sass", "easy-going", "grumpy"), ("mischief", "Mischief", "well-behaved", "troublemaker"),
    ]

    /// The presets, in the order Settings shows them.
    static let presets: [(key: String, label: String, traits: CatPersonality)] = [
        ("balanced", "Balanced", make("balanced", 0.5, 0.5, 0.5, 0.5, 0.5, 0.5)),
        ("chill", "Chill", make("chill", 0.12, 0.35, 0.3, 0.65, 0.3, 0.2)),
        ("grumpy", "Grumpy", make("grumpy", 0.4, 0.3, 0.45, 0.15, 0.95, 0.3)),
        ("sweet", "Sweet", make("sweet", 0.5, 0.55, 0.55, 1, 0.1, 0.3)),
        ("hyper", "Hyper", make("hyper", 1, 0.9, 0.75, 0.5, 0.3, 1)),
        ("chatty", "Chatty", make("chatty", 0.6, 0.7, 1, 0.6, 0.35, 0.5)),
    ]

    private static func make(_ preset: String, _ e: Double, _ cu: Double, _ ch: Double, _ af: Double, _ sa: Double, _ mi: Double) -> CatPersonality {
        CatPersonality(preset: preset, energy: e, curiosity: cu, chatty: ch, affection: af, sass: sa, mischief: mi)
    }

    /// A preset as a cat stores it: its name plus the six traits. An unknown name gives Balanced.
    static func named(_ name: String) -> CatPersonality {
        presets.first { $0.key == name }?.traits ?? presets[0].traits
    }

    /// Moving a slider: the new value (held to 0…1) and the preset becomes "custom". An unknown trait, or a value that is not a
    /// finite number, changes nothing.
    static func slide(_ p: CatPersonality, trait: String, value: Double) -> CatPersonality {
        var q = p
        guard p[trait] != nil, value.isFinite else { return q }
        q[trait] = clamp(value, 0, 1)
        q.preset = "custom"
        return q
    }

    /// Traits as a settings file can hold them (anything at all): a missing, non-numeric or NaN trait becomes 0.5, anything else is
    /// held to 0…1. The preset name is kept when it is a string.
    static func sanitized(_ raw: [String: Any]) -> CatPersonality {
        var p = CatPersonality()
        for t in traits {
            var v = 0.5
            if let n = raw[t.key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite { v = n.doubleValue }
            p[t.key] = clamp(v, 0, 1)
        }
        p.preset = (raw["preset"] as? String) ?? "custom"
        return p
    }

    static func multipliers(_ raw: [String: Any]) -> CatMultipliers { multipliers(sanitized(raw)) }

    static func multipliers(_ p0: CatPersonality) -> CatMultipliers {
        let energy = clamp(p0.energy, 0, 1), sass = clamp(p0.sass, 0, 1), aff = clamp(p0.affection, 0, 1)
        let curiosity = clamp(p0.curiosity, 0, 1), chatty = clamp(p0.chatty, 0, 1), mischief = clamp(p0.mischief, 0, 1)
        return CatMultipliers(
            speed: tm(energy, 0.55, 1.5), hop: tm(energy, 0.45, 1.4), blinkEvery: tm(energy, 1.4, 0.75), pupil: (energy - 0.5) * 0.3,
            lid: max(max(0, 0.5 - energy), max(0, sass - 0.55) * 0.55),
            gaze: tm(curiosity, 0.35, 1.2), earFlickEvery: tm(curiosity, 1.6, 0.6), chatter: tm(chatty, 0.3, 1.4),
            smile: (aff - 0.5) * 0.5 - max(0, sass - 0.5) * 1.1, blush: max(0, aff - 0.6) * 0.9, slowBlinkEvery: tm(aff, 1.6, 0.5),
            skew: max(0, sass - 0.5) * 0.9, earBack: max(0, sass - 0.55) * 0.45,
            idle: .init(yawn: energy < 0.3, zoomies: mischief > 0.75 && energy > 0.7, mew: chatty > 0.7, purr: aff > 0.75, hmph: sass > 0.75, wink: mischief > 0.65),
            poke: aff > 0.75 && sass < 0.4 ? "love" : "annoyed", pokeHiss: sass > 0.7)
    }
}
```

**Create `NotchBuddy/Sources/App/CatRules.swift`:**

```swift
import Foundation

// The small rules around the cat that are not drawing and not motion: the work clock that earns zoomies, the sleep timer, what wakes
// a sleeping cat, and which tool names mean "searching". Port of the "Rules" section of design/prototype/cat-core.js;
// tests/fixtures/cat/sequence-cases.json and search-tools.json pin them.

/// The eleven agent states a cat can be in. The raw values are the strings the contract uses.
enum CatState: String, CaseIterable, Sendable {
    case idle, working, thinking, searching, approval, question, error, finished, ratelimit, sleeping, dizzy

    /// Working, thinking and searching are the states that count as work.
    var isBusy: Bool { self == .working || self == .thinking || self == .searching }
}

enum CatRules {
    /// An agent that finishes after this much working, thinking or searching earns zoomies (ms). The prototype page shortens it to 12 s.
    static let zoomAfterMs = 5.0 * 60 * 1000

    /// The work clock. `busySince` is nil while no run is open; `workedFor` is how long the last finished run lasted.
    struct WorkClock: Equatable {
        var busySince: Double?
        var workedFor: Double
        init(busySince: Double? = nil, workedFor: Double = 0) { self.busySince = busySince; self.workedFor = workedFor }
    }

    /// Working, thinking and searching keep the clock running; approval and question pauses neither stop nor reset it;
    /// every other state ends the run and stores how long it lasted in `workedFor` (never negative, even if the clock steps back).
    /// Pure: pass the clock in, get the next one back.
    static func workClockStep(_ clock: WorkClock, state: CatState, nowMs: Double) -> WorkClock {
        var c = clock
        if state.isBusy {
            if c.busySince == nil { c.busySince = nowMs }
        } else if state != .approval && state != .question {
            c.workedFor = c.busySince.map { max(0, nowMs - $0) } ?? 0
            c.busySince = nil
        }
        return c
    }

    static func zoomiesOnFinish(workedForMs: Double, thresholdMs: Double = zoomAfterMs) -> Bool { workedForMs >= thresholdMs }

    /// An idle cat falls asleep after this long with no agent event (ms).
    static let sleepAfterMs = 10.0 * 60 * 1000

    /// Milliseconds until the cat should fall asleep, for arming a one-shot timer (no polling): ten minutes after the last agent event.
    /// Only an idle cat sleeps, so any other state (approval and question included) gives nil. A negative or non-finite quiet time counts
    /// as 0. 0 means: asleep now.
    static func sleepDelay(state: CatState, quietMs: Double) -> Double? {
        state == .idle ? max(0, sleepAfterMs - max(0, quietMs.isFinite ? quietMs : 0)) : nil
    }

    /// Anything that wakes a sleeping cat. In Playful it wakes with zoomies (see the Playful profile).
    static let wakeEvents = ["hook", "hover", "click"]
    static func wakes(_ kind: String) -> Bool { wakeEvents.contains(kind) }

    /// Tool names that mean "searching" (exact, case-sensitive match on the tool name the hook relay delivers).
    static let searchTools: [String: [String]] = [
        "claude": ["WebSearch", "WebFetch", "Grep", "Glob"],
        "gemini": ["google_web_search", "web_fetch", "grep_search", "search_file_content", "glob"],
        "codex": ["web_search", "grep_files"],
    ]
    private static let searchSet = Set(searchTools.values.flatMap { $0 })
    static func isSearchTool(_ name: String?) -> Bool { name.map { searchSet.contains($0) } ?? false }
    /// The state a tool event puts an agent in: a search tool is searching, any other tool is working.
    static func toolState(_ name: String?) -> CatState { isSearchTool(name) ? .searching : .working }
}
```

- [ ] **Step 4: Run the tests**

Run: `bash scripts/test-cat-personality.sh`
Expected: PASS

Run: `bash scripts/test-cat-rules.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/CatPersonalityTests.swift tests/CatRulesTests.swift scripts/test-cat-personality.sh scripts/test-cat-rules.sh NotchBuddy/Sources/App/Personality.swift NotchBuddy/Sources/App/CatRules.swift
git commit -m "feat(cat): personality (six traits, six presets) and the work clock, sleep timer and search tool rules in Swift

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 6: The engine and both motion profiles (stage 2)

Agent: `nm-implementer`. If a fixture row fails and the cause is not obvious after two attempts, hand the task to `nm-implementer-deep`.

**Files:**
- Create: `tests/CatEngineSupport.swift`, `tests/CatEngineTests.swift`, `scripts/test-cat-engine.sh`
- Create: `NotchBuddy/Sources/App/MotionProfiles.swift`, `NotchBuddy/Sources/App/CatEngine.swift`

**Interfaces:**
- Consumes: Tasks 1, 2, 3 and 5 (`CatPreset`, `CatPose`, `PoseKey`, `CatEase`, `CatRNG`, `CatLook`, `CatEye`, `CatBadge`, `CatParticle`, `CatBall`, `CatWave`, `Personality`, `CatState`, `CatRules`); `tests/fixtures/cat/motion-cases.json` and `sequence-cases.json` (`catch`, `zoomiesAndWake`).
- Produces in `MotionProfiles.swift`: `enum CatTables` (`color`, `tint`, `glow`, `badge`, `mouthKeys`, `mouthRest`, `emoteMouth`, `mouthFx(_:_:)`), `protocol MotionProfile` (`eye`, `enter`, `targets`, `post`, `ambient`, `squash`, `emote`), `CatProfiles.named(_ key:)` (`"classic"` or `"playful"`, else nil), `ClassicProfile` (upstream's timings 1:1) and `PlayfulProfile` (cat body language).
- Produces in `CatEngine.swift`: `final class CatConfig` (`shared`; `character` (default `"shrimpy"`), `motion`, `override: [String: String]`, `pers: [String: CatPersonality]`, `zoomAfter`), `typealias CatKey`, `struct CatTween`, `struct CatTargets`, and `@MainActor final class CatEngine: ObservableObject`:
  - `init(_ p: CatPreset, mini: Bool = false, now: @escaping () -> Double, rand: @escaping () -> Double, cfg: CatConfig? = nil, quiet: Bool = false, state: CatState = .idle)` with a Foundation default for `now` (system uptime in ms) and for `rand`; `quiet` switches off every random idle habit.
  - What the renderer and the views read and set: `s: CatPose`, `state`, `badge`, `eyeOv`, `eyeUntil`, `lookX`, `lookY`, `tgEs` (eye scale target, 1.08 on hover), `isDancing`/`setDancing(_:)`, `dancingLevel`, `lastTime` (seconds, the engine's own clock), `collar` (a hex string, the agent's colour; **unused** in stages 1 to 4: the optional collar, default Off, is drawn from stage 6), `base` and `mouthPoint` (set from the renderer's layout after each draw), `parts`, `balls`.
  - Hooks: `onNote: ((Int, String) -> Void)?` (blinks, flicks, bleps, licks, emotes, zoomies, hairballs), `onSound: ((String) -> Void)?` (`"slap"`, `"annoyed"`, `"greet"`), `onDizzy: (() -> Void)?` (called on the third quick poke instead of the engine going dizzy itself).
  - Actions: `setState(_:force:)`, `emote(_ name: String)` (`love, happy, surprised, proud, wink, yawn, annoyed, hello, zoomies, hairball`; an unknown name is ignored), `slap()`, `blink()`, `greet()`, `interruptGreet()`, `catchOpen(_:)`, `catchDrop()`, `catchArrive()`, `catchReject(_ ext: String)`, `gulp()`, `hairball(_:)`, `zoomies()`, `holdEye(_:)`, and the building blocks `anim(_:_:done:)`, `later(_:_:_:)`, `ov(_:_:)`, `mpose(_:_:_:_:)`.
  - Per frame: `update(dt:)` (`dt` is held to 0...0.25), `computeTargets(_:_:)`, `mouthOpen()`, `eyeShape()`, `look(time:) -> CatLook` (everything the renderer needs), `static func frameDelta(now:last:maxDt:) -> Double` (a frame's time from one clock, held to 0...maxDt), `static let flightMs` (380).
  - `motion`, `prof`, `pers`, `pm()`: the motion style in force (the cat's own override, else the global one; unknown means Playful; a kitten follows its parent) and what its personality changes.

- [ ] **Step 1: Write the failing test**

The reference harness is `makeEngine` in `scripts/gen-cat-fixtures.mjs`: a fake clock starting at 0, `rand = rng(seed)`, the cat with `quiet` and the Balanced personality unless the case says otherwise, and `R` exactly 1. The test replays every fixture row (the easings, the PRNG, the tweens, 110 rest cases, every state and emote over 3 seconds in both styles, 45 s of idle habits for every personality, the four file catches and the zoomies and wake rules) and then checks the behaviour the app depends on: one clock for `dt`, hostile frame times, pokes, dizzy, sounds, motion per cat, a refused file before the first draw, and that a settled cat has nothing queued.

**Create `tests/CatEngineSupport.swift`:**

```swift
import Foundation

/// A clock the tests move by hand, in milliseconds.
@MainActor
final class FakeClock { var t = 0.0 }
```

**Create `tests/CatEngineTests.swift`:**

```swift
import Foundation

@main
enum CatEngineTests {
    static let fps = 60.0
    static func frameMs(_ f: Int) -> Double { Double(f) * 1000 / fps }
    static func num(_ x: Any?) -> Double { (x as! NSNumber).doubleValue }
    static let sampleFrames = [0, 5, 10, 16, 24, 34, 46, 60, 78, 102, 132, 180]

    /// An engine on a fake clock and a seeded rand, the way the fixtures were made (the reference is `makeEngine` in scripts/gen-cat-fixtures.mjs).
    /// R is exactly 1, so a hairball lands in units of R.
    @MainActor static func makeEngine(_ preset: CatPreset, profile: String = "playful", pers: [String: CatPersonality] = [:], seed: UInt32 = 1,
                                      quiet: Bool = true, state: CatState = .idle, zoomAfter: Double = CatRules.zoomAfterMs,
                                      note: ((Int, String) -> Void)? = nil) -> (e: CatEngine, clock: FakeClock, step: (Int) -> Void) {
        let clock = FakeClock(), rng = CatRNG(seed: seed)
        let cfg = CatConfig(motion: profile, override: [:], pers: pers, zoomAfter: zoomAfter)
        let e = CatEngine(preset, now: { clock.t }, rand: { rng.next() }, cfg: cfg, quiet: quiet, state: state)
        e.onNote = note
        let L = CatGeometry.layout(preset, e.s, cx: 0, cy: 0, D: 2 * preset.rx)
        e.base = L.base; e.mouthPoint = L.mouth
        return (e, clock, { f in clock.t = frameMs(f); e.update(dt: 1 / fps) })
    }

    @MainActor static func columns(_ want: [String: Any]) -> [String] { want["columns"] as! [String] }

    /// The engine's numbers for one frame, named like the fixture's columns.
    @MainActor static func row(_ e: CatEngine) -> [String: Any] {
        var r: [String: Any] = ["mouthOpen": e.mouthOpen(), "slotH": e.slotH, "chew": e.chew, "parts": e.parts.count, "balls": e.balls.count,
                                "ballX": e.balls.first?.x ?? 0, "ballY": e.balls.first?.y ?? 0]
        for k in PoseKey.allCases { r[k.rawValue] = e.s[k] }
        return r
    }
    static func wantRow(_ cols: [String], _ v: [Any]) -> [String: Any] { Dictionary(uniqueKeysWithValues: zip(cols, v)) }

    /// Runs from frame 0, calling `start` there, and returns one row per sample frame (the reference is `sample` in the generator).
    @MainActor static func sample(_ preset: CatPreset, profile: String, frames: [Int] = sampleFrames, start: (CatEngine) -> Void) -> [Int: (eye: String, v: [String: Any])] {
        let (e, _, step) = makeEngine(preset, profile: profile)
        start(e)
        var out: [Int: (String, [String: Any])] = [:]
        for f in 0...frames.last! {
            if f > 0 { step(f) }
            if frames.contains(f) { out[f] = (e.eyeShape().rawValue, row(e)) }
        }
        return out
    }

    /// Compares the sampled rows of one case with the fixture's rows for it.
    @MainActor static func compareRows(_ label: String, _ got: [Int: (eye: String, v: [String: Any])], _ rows: [[String: Any]], _ cols: [String]) {
        var diffs: [String] = []
        for r in rows {
            let f = Int(num(r["f"]))
            guard let g = got[f] else { diffs.append("frame \(f) missing"); continue }
            // `tMs` is derived data, exactly f * 1000 / 60, and `f` is the authority: it only has to agree within 1e-8 (the contract's port notes).
            if let t = r["tMs"] as? NSNumber, abs(t.doubleValue - frameMs(f)) > 1e-8 { diffs.append("frame \(f) tMs \(t) vs \(frameMs(f))") }
            for d in CT.diffs(["eye": g.eye, "v": g.v] as [String: Any], ["eye": r["eye"]!, "v": wantRow(cols, r["v"] as! [Any])] as [String: Any]) { diffs.append("frame \(f) \(d)") }
        }
        CT.checkRows(label, diffs)
    }

    @MainActor static func main() {
        let m = CT.fixture("motion-cases.json"), seq = CT.fixture("sequence-cases.json")
        let cols = columns(m)
        let momo = CatPresets.byID("momo")

        CT.section("easing curves and the seeded PRNG")
        for e in m["ease"] as! [[String: Any]] {
            let curve = CatEase(rawValue: e["name"] as! String)!
            for s in e["samples"] as! [[String: Any]] { CT.checkNear("\(e["name"]!) at \(num(s["t"]))", curve.at(num(s["t"])), num(s["v"])) }
        }
        for c in m["prng"] as! [[String: Any]] {
            let seed = UInt32(truncatingIfNeeded: Int(num(c["seed"]))), r = CatRNG(seed: seed)
            CT.checkJSON("rng(\(c["seed"]!))", got: (0..<8).map { _ in r.next() }, want: c["values"]!)
        }

        CT.section("tweens")
        for c in m["tween"] as! [[String: Any]] {
            let prop = PoseKey(rawValue: c["prop"] as! String)!
            let keys: [CatKey] = (c["keys"] as! [[Any]]).map { (num($0[0]), num($0[1]), CatEase(rawValue: $0[2] as! String)!) }
            let (e, _, step) = makeEngine(momo)
            CT.checkNear("\(prop.rawValue) starts at \(num(c["from"]))", e.s[prop], num(c["from"]))
            e.anim(prop, keys)
            var got: [[Double]] = []
            for f in 0...58 { if f > 0 { step(f) }; if f % 2 == 0 { got.append([Double(f), e.s[prop]]) } }
            CT.checkJSON("\(prop.rawValue) tween", got: got, want: c["values"]!)
        }

        CT.section("rest: the targets of every state in both motion styles")
        var restDiffs: [String] = []
        for r in m["rest"] as! [[String: Any]] {
            let profile = r["profile"] as! String, st = CatState(rawValue: r["state"] as! String)!, T = num(r["T"]), look = r["look"] as! [Double]
            let (e, _, _) = makeEngine(momo, profile: profile, state: st)
            e.lookX = look[0]; e.lookY = look[1]
            e.computeTargets(T * 1000, T)
            var targets: [String: Any] = [:]
            for k in PoseKey.allCases where [PoseKey.roll, .open, .ox, .tint, .blush, .badgeS, .lift, .wh, .paws].contains(k) == false { targets[k.rawValue] = e.tg[k] }
            let got: [String: Any] = ["profile": profile, "state": st.rawValue, "T": T, "look": look, "eye": e.prof.eye(st).rawValue, "tint": CatTables.tint[st]!,
                                      "badge": CatTables.badge[st]?.rawValue ?? NSNull(), "color": CatTables.color[st]!, "glow": CatTables.glow[st] ?? NSNull(),
                                      "mfx": e.mfx, "blushBase": e.blushBase, "targets": targets]
            restDiffs += CT.diffs(got, r).map { "\(profile) \(st.rawValue) T \(T) look \(look): \($0)" }
        }
        CT.checkRows("110 rest cases", restDiffs)

        CT.section("enters: each state's entry, sampled over 3 seconds")
        let enters = m["enters"] as! [[String: Any]]
        for profile in ["playful", "classic"] {
            for st in CatState.allCases {
                let rows = enters.filter { $0["profile"] as? String == profile && $0["state"] as? String == st.rawValue }
                let got = sample(momo, profile: profile) { $0.setState(st) }
                compareRows("\(profile) \(st.rawValue)", got, rows, cols)
            }
        }

        CT.section("emotes: every emote sampled over 3 seconds (hairball 2.4 s, zoomies 2 s)")
        let emotes = m["emotes"] as! [[String: Any]]
        for profile in ["playful", "classic"] {
            for name in ["love", "happy", "surprised", "proud", "wink", "yawn", "annoyed", "hello", "zoomies", "hairball"] {
                for cat in (name == "hairball" || name == "zoomies") ? ["momo", "shrimpy"] : ["momo"] {
                    let rows = emotes.filter { $0["profile"] as? String == profile && $0["emote"] as? String == name && $0["cat"] as? String == cat }
                    let got = sample(CatPresets.byID(cat), profile: profile) { $0.emote(name) }
                    compareRows("\(profile) \(cat) \(name)", got, rows, cols)
                }
            }
        }

        CT.section("ambient: 45 s of idle habits for every personality (blinks, flicks, bleps, licks)")
        for a in m["ambient"] as! [[String: Any]] {
            let profile = a["profile"] as! String, persona = a["persona"] as! String
            var log: [[Any]] = []
            let (_, _, step) = makeEngine(momo, profile: profile, pers: ["momo": Personality.named(persona)], seed: 7, quiet: false) { log.append([$0, $1]) }
            for f in 1...(45 * 60) { step(f) }
            CT.checkJSON("\(profile) \(persona)", got: log, want: a["events"]!)
        }

        CT.section("the file catch: open wide, snap on the drop, gulp, chew (and the refused file)")
        let flightFrames = Int((380 / frameMs(1)).rounded(.up))
        CT.check("the flight lasts 23 frames", flightFrames, Int(num((seq["catchHarness"] as! [String: Any])["flightFrames"])))
        let catchFrames = [0, 6, 12, 24, 36, 48, 59, 60, 62, 66, 72, 80, 83, 84, 86, 90, 96, 108, 120, 132, 150, 168, 200, 240]
        for c in seq["catch"] as! [[String: Any]] {
            let profile = c["profile"] as! String, refused = c["refused"] as! Bool
            let (e, _, step) = makeEngine(momo, profile: profile)
            var got: [Int: (eye: String, v: [String: Any])] = [:]
            e.catchOpen(true)
            for f in 0...catchFrames.last! {
                if f > 0 { step(f) }
                if f == 60 { e.catchDrop() }
                if f == 60 + flightFrames { refused ? e.catchReject("EXE") : e.catchArrive() }
                if catchFrames.contains(f) { got[f] = (e.eyeShape().rawValue, row(e)) }
            }
            compareRows("\(profile), \(refused ? "refused (hairball)" : "taken")", got, c["rows"] as! [[String: Any]], cols)
        }

        CT.section("zoomies after five minutes of work, and on waking")
        for c in seq["zoomiesAndWake"] as! [[String: Any]] {
            let profile = c["profile"] as! String
            var log: [[Any]] = []
            let (e, clock, _) = makeEngine(momo, profile: profile) { log.append([$0, $1]) }
            // The harness moves the clock to the stated millisecond, acts, and at the end updates 60 frames.
            for item in c["script"] as! [[Any]] {
                let what = item[1] as! String
                clock.t = num(item[0])
                e.setState(what.hasPrefix("wake:") ? .idle : CatState(rawValue: what)!)
            }
            for _ in 0..<60 { clock.t += 1000 / fps; e.update(dt: 1 / fps) }
            CT.checkJSON("\(profile): \(c["name"]!)", got: log, want: c["log"]!)
        }

        CT.section("frame time comes from one clock (the old Mac engine mixed two)")
        CT.checkNear("a normal frame", CatEngine.frameDelta(now: 10.016, last: 10), 0.016)
        CT.checkNear("a clock that stepped back gives 0", CatEngine.frameDelta(now: 9, last: 10), 0)
        CT.checkNear("a long pause is held to 0.05 s", CatEngine.frameDelta(now: 100, last: 10), 0.05)
        CT.checkNear("NaN gives 0", CatEngine.frameDelta(now: .nan, last: 10), 0)
        CT.checkNear("two different clocks always gave the maximum (the bug this fixes)", CatEngine.frameDelta(now: 7.8e8, last: 12345), 0.05)
        do {
            let (e, clock, step) = makeEngine(momo)
            step(6)
            CT.checkNear("lastTime is the engine's own clock, in seconds", e.lastTime, clock.t / 1000)
            clock.t += 16
            CT.checkNear("so the next frame's dt is the 16 ms between them", CatEngine.frameDelta(now: clock.t / 1000, last: e.lastTime), 0.016)
        }

        CT.section("the mouth spring steps at most 1/60 s: a slow frame is several steps (one big step diverges to NaN)")
        do {
            let (slow, slowClock, _) = makeEngine(momo), (fast, _, fastStep) = makeEngine(momo)
            slow.catchOpen(true); fast.catchOpen(true)
            slowClock.t += 250; slow.update(dt: 0.25)
            for f in 1...15 { fastStep(f) }
            CT.checkNear("one 0.25 s update opens the mouth exactly as fifteen 1/60 s updates do", slow.slotH, fast.slotH)
            for dt in [0.066, 0.1, 0.25] {
                let (e, clock, _) = makeEngine(momo)
                e.catchDrop()
                for _ in 0..<40 { clock.t += dt * 1000; e.update(dt: dt) }
                CT.checkTrue("dt \(dt): the mouth settles near 1.05 and stays finite (\(e.slotH))", e.slotH.isFinite && abs(e.slotH - 1.05) < 0.1)
            }
        }

        CT.section("hostile frame times keep the pose finite")
        for dt in [0.0, -1, .nan, .infinity, 1e9, 0.25, 5] {
            let (e, clock, _) = makeEngine(CatPresets.byID("shrimpy"), state: .working)
            for _ in 0..<30 { clock.t += 16; e.update(dt: dt) }
            CT.checkTrue("update(dt: \(dt)) leaves every pose value finite", PoseKey.allCases.allSatisfy { e.s[$0].isFinite })
        }

        CT.section("the app-facing behaviour: pokes, dizzy, sounds, motion per cat")
        do {
            // Three quick pokes with the app's callback: the engine asks the app to go dizzy and stays as it is.
            let (e, clock, _) = makeEngine(momo)
            var dizzy = 0, sounds: [String] = []
            e.onDizzy = { dizzy += 1 }
            e.onSound = { sounds.append($0) }
            for _ in 0..<3 { clock.t += 200; e.slap(); e.update(dt: 1 / 60) }
            CT.check("the third poke calls onDizzy once", dizzy, 1)
            CT.check("and the engine did not turn dizzy by itself", e.state, CatState.idle)
            clock.t += 100; e.update(dt: 1 / 60)
            CT.check("the pokes before the third play 'slap' and, 60 ms later, 'annoyed'; the third only 'slap'", sounds, ["slap", "slap", "annoyed", "slap", "annoyed"])
        }
        do {
            let (e, clock, _) = makeEngine(momo)
            var sounds: [String] = []
            e.onSound = { sounds.append($0) }
            e.slap()
            CT.check("a poke is heard at once", sounds, ["slap"])
            clock.t += 100; e.update(dt: 1 / 60)
            CT.check("and the annoyed sound follows 60 ms later", sounds, ["slap", "annoyed"])
        }
        do {
            // Without the callback the engine turns dizzy for 3.3 s, then recovers with a happy emote.
            let (e, clock, _) = makeEngine(momo, state: .working)
            for _ in 0..<3 { clock.t += 200; e.slap() }
            CT.check("three quick pokes make the cat dizzy", e.state, CatState.dizzy)
            clock.t += 3400; e.update(dt: 1 / 60)
            CT.check("after 3.3 s it is back to what it was doing", e.state, CatState.working)
            CT.check("and happy about it", e.eyeOv, CatEye.happy)
        }
        do {
            let (e, clock, _) = makeEngine(momo)
            e.slap(); clock.t += 2000; e.slap(); clock.t += 2000; e.slap()
            CT.check("pokes more than 1.7 s apart never add up", e.state, CatState.idle)
        }
        do {
            // A kitten follows its parent's motion style and personality; a personality bends a poke.
            let cfg = CatConfig(motion: "playful", override: ["shrimpy": "classic"], pers: ["momo": Personality.named("grumpy"), "shrimpy": Personality.named("sweet")])
            let kit = CatEngine(CatPresets.kitten(of: CatPresets.byID("shrimpy")), now: { 0 }, rand: { 0.5 }, cfg: cfg, quiet: true)
            CT.check("a kitten of Shrimpy plays Shrimpy's style", kit.motion, "classic")
            CT.check("and wears Shrimpy's personality", kit.pers.preset, "sweet")
            CT.check("a sweet cat answers a poke with love", kit.pm().poke, "love")
            let other = CatEngine(momo, now: { 0 }, rand: { 0.5 }, cfg: cfg, quiet: true)
            CT.check("Momo has no override and follows the global style", other.motion, "playful")
            CT.checkTrue("a grumpy cat hisses at a poke", other.pm().pokeHiss)
            cfg.override["momo"] = "nonsense"
            CT.check("an unknown stored motion style plays Playful", other.motion, "playful")
            cfg.override["momo"] = ""
            CT.check("an empty override means the global style", other.motion, "playful")
        }
        do {
            // An unknown emote is ignored, and a gulp is a catch whose file has already flown.
            let (e, clock, step) = makeEngine(momo)
            e.emote("nonsense"); step(5)
            CT.checkTrue("an unknown emote leaves the pose finite", PoseKey.allCases.allSatisfy { e.s[$0].isFinite })
            e.gulp()
            CT.checkTrue("a gulp opens the mouth wide first", e.catching)
            clock.t += CatEngine.flightMs + 20; e.update(dt: 1 / 60)
            CT.checkTrue("and chews when the file has arrived", !e.catching && e.chewUntil > e.chewStart)
        }
        do {
            // A hairball needs to know where the mouth is: before the first draw there is nowhere to spit it, and that is not an error.
            let clock = FakeClock(), rng = CatRNG(seed: 9)
            let e = CatEngine(momo, now: { clock.t }, rand: { rng.next() }, cfg: CatConfig(), quiet: true)
            e.catchReject("EXE")
            for _ in 0..<200 { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60) }
            CT.checkTrue("a refused file before the first draw makes no ball and no crash", e.balls.isEmpty && PoseKey.allCases.allSatisfy { e.s[$0].isFinite })
        }
        do {
            // 0 % CPU when hidden starts here: a settled cat has nothing queued and nothing tweening, so there is nothing to wake for.
            let (e, clock, _) = makeEngine(momo)
            for _ in 0..<(60 * 10) { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60) }
            CT.checkTrue("after ten quiet seconds an idle cat has no queued actions and no tweens", e.q.isEmpty && e.tw.isEmpty && e.parts.isEmpty && e.balls.isEmpty)
        }
        CT.finish()
    }
}
```

**Create `scripts/test-cat-engine.sh`:**

```bash
#!/usr/bin/env bash
# The cat engine on a fake clock and a seeded rand against motion-cases.json (rest, enters, emotes, ambient habits) and
# sequence-cases.json (the file catch, the zoomies and wake rules).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-engine.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift \
    tests/CatTestSupport.swift tests/CatEngineSupport.swift tests/CatEngineTests.swift \
    -o "$TEST_DIR/cat-engine-tests"
"$TEST_DIR/cat-engine-tests"
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-engine.sh`
Expected: FAIL (swiftc cannot open `NotchBuddy/Sources/App/MotionProfiles.swift`)

- [ ] **Step 3: Write the profiles and the engine**

These are the "State tables", "Mouth", "Motion profiles" and "Engine" sections of the core, ported line by line: the same operations in the same order (the order of `rand()` calls is what the ambient fixtures pin), with closures that receive the engine as an argument rather than capturing it, so a queued action never keeps its engine alive. The app-only members (`tgEs`, the dance level, `collar`, `onSound`, `onDizzy`, `frameDelta`, `gulp`, `holdEye`) sit beside the contract's code and are never touched by the fixtures.

**Create `NotchBuddy/Sources/App/MotionProfiles.swift`:**

```swift
import Foundation

// How a cat moves in each state and emote, in the two motion styles, and the tables that go with them (colours, badges, mouths).
// Classic is upstream's timings 1:1; Playful is cat body language on top of the same engine. Port of the "State tables", "Mouth" and
// "Motion profiles" sections of design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/motion-cases.json pins them.

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
    ]

    /// The six mouth values, in the order the rest mouths list them.
    static let mouthKeys: [PoseKey] = [.mouth, .smile, .tongue, .mround, .mskew, .wavy]
    /// The rest mouth per state: open, smile (-1 frown … 1 smile), tongue, round (D … 'o'), skew, wavy.
    static let mouthRest: [CatState: [Double]] = [
        .idle: [0, 0, 0, 0, 0, 0], .working: [0, 0.05, 0.35, 0, 0, 0], .thinking: [0, -0.15, 0, 0, 0.7, 0], .searching: [0, 0, 0, 0, 0, 0],
        .approval: [0, 0.1, 0, 0.35, 0, 0], .question: [0.13, 0, 0, 1, 0, 0], .error: [0, -0.8, 0, 0, 0, 0], .finished: [0, 1, 0, 0, 0, 0],
        .ratelimit: [0.3, 0, 0.85, 0.2, 0, 0], .sleeping: [0, 0.1, 0, 1, 0, 0], .dizzy: [0, 0, 0.45, 0, 0, 1],
    ]
    /// Emote mouths, shared by both motion styles: the pose to hold and for how long (ms).
    static let emoteMouth: [String: (pose: [(PoseKey, Double)], ms: Double)] = [
        "love": ([(.smile, 0.8)], 1800), "surprised": ([(.mouth, 0.6), (.mround, 1)], 1000), "proud": ([(.smile, 0.75), (.mskew, 0.45)], 1800),
        "wink": ([(.tongue, 0.8), (.smile, 0.4), (.mskew, 0.3)], 1100), "yawn": ([(.tongue, 0.35), (.mround, 0.15)], 1100),
        "happy": ([(.mouth, 0.5), (.smile, 1)], 1300), "annoyed": ([(.smile, -0.7), (.mskew, -0.6)], 850),
    ]

    /// Per-frame mouth motion on top of the rest shape: hunting chatter, meows, panting, snoring.
    static func mouthFx(_ st: CatState, _ T: Double) -> Double {
        switch st {
        case .searching:
            let ph = T.truncatingRemainder(dividingBy: 2.6)
            return ph < 1.1 ? sin(Double.pi * ph / 1.1) * (0.24 + 0.07 * sin(T * CatMath.tau * 9)) : 0
        case .approval:
            let ph = T.truncatingRemainder(dividingBy: 1.4) / 1.4
            return ph < 0.28 ? 0.5 * sin(Double.pi * ph / 0.28) : 0
        case .ratelimit: return 0.07 * sin(T * CatMath.tau * 2.8)
        case .sleeping: return 0.07 * max(0, sin(T * 1.5))
        default: return 0
        }
    }
}

/// One motion style. Profiles are stateless: they act on the engine they are handed.
@MainActor
protocol MotionProfile {
    var key: String { get }
    var label: String { get }
    /// The eye shape the state rests in.
    func eye(_ st: CatState) -> CatEye
    /// The body language when a state starts.
    func enter(_ c: CatEngine, _ st: CatState, _ prev: CatState)
    /// Fills the pose targets for the state and returns the gaze (yaw, pitch) the head eases toward.
    func targets(_ c: CatEngine, _ st: CatState, _ T: Double, _ tg: inout CatTargets) -> (yaw: Double, pitch: Double)
    /// Per-frame motion applied straight to the pose, after the easing.
    func post(_ c: CatEngine, _ st: CatState, _ T: Double, _ kG: Double)
    /// Idle habits a cat has by itself (the engine skips them when it is quiet).
    func ambient(_ c: CatEngine, _ t: Double)
    /// The squash of a poke: how flat (sy) and how wide (sx).
    var squash: (sy: Double, sx: Double) { get }
    func emote(_ c: CatEngine, _ n: String)
}

enum CatProfiles {
    static func named(_ key: String) -> (any MotionProfile)? {
        switch key {
        case "classic": return ClassicProfile()
        case "playful": return PlayfulProfile()
        default: return nil
        }
    }
}

// MARK: - Classic: upstream timings 1:1

@MainActor
struct ClassicProfile: MotionProfile {
    let key = "classic", label = "Classic"
    /// eye, tilt
    static let rest: [CatState: (eye: CatEye, tilt: Double)] = [
        .idle: (.pill, 0), .working: (.pill, 0), .thinking: (.pill, 0), .searching: (.pill, 0), .approval: (.wide, 0), .question: (.pill, 0.17),
        .error: (.flat, 0), .finished: (.happy, 0), .ratelimit: (.tired, 0), .sleeping: (.closed, 0), .dizzy: (.spiral, 0),
    ]
    let squash = (sy: 0.78, sx: 1.16)

    func eye(_ st: CatState) -> CatEye { Self.rest[st]!.eye }

    func enter(_ c: CatEngine, _ st: CatState, _ prev: CatState) {
        switch st {
        case .idle: if prev != .idle { c.blink() }
        case .approval: c.anim(.oy, [(-0.2, 150, .out), (0, 300, .back)])
        case .error: c.anim(.ox, [(0.08, 50, .out), (-0.08, 70, .inOut), (0.05, 70, .inOut), (0, 90, .out)])
        case .finished:
            c.anim(.roll, [(CatMath.tau, 950, .inOut)]) { $0.s.roll = 0 }
            c.later(500, "st") { $0.emit(.spark, 5) }
        case .ratelimit: c.emit(.sweat, 1)
        case .dizzy: c.anim(.roll, [(2 * CatMath.tau, 1300, .inOut)]) { $0.s.roll = 0 }
        default: c.blink()
        }
    }

    func targets(_ c: CatEngine, _ st: CatState, _ T: Double, _ tg: inout CatTargets) -> (yaw: Double, pitch: Double) {
        tg.tilt = Self.rest[st]!.tilt; tg.earL = 0; tg.earR = 0; tg.earU = 1; tg.earF = 0; tg.pupil = 0.45; tg.oy = 0
        var ty = c.lookX * 0.62, tp = c.lookY * 0.5
        if st == .thinking { ty = ty * 0.35 + 0.55 * 0.55; tp = tp * 0.3 + 0.55 * 0.5 }
        if st == .sleeping { ty = 0; tp = -0.14; tg.sy = 1 + 0.035 * sin(1.8 * T); tg.sx = 1 - 0.035 * 0.57 * sin(1.8 * T) }
        if st == .searching { ty = sin(2.6 * T) * 0.6; tp = -0.06 }
        if st == .dizzy { ty = sin(9 * T) * 0.25 }
        if st == .approval { tg.oy = -abs(sin(5.2 * T)) * 0.07 }
        return (ty, tp)
    }

    func post(_ c: CatEngine, _ st: CatState, _ T: Double, _ kG: Double) {
        if c.tw[.ox] == nil { c.s.ox += (0 - c.s.ox) * kG }
    }

    func ambient(_ c: CatEngine, _ t: Double) {
        if t < c.nextAmb { return }
        if c.state == .sleeping { c.emit(.z, 1) }
        if c.state == .ratelimit && !c.mini && c.rand() < 0.5 { c.emit(.sweat, 1) }
        c.nextAmb = t + 1300
    }

    func emote(_ c: CatEngine, _ n: String) {
        let d = 1800.0
        switch n {
        case "love":
            c.ov(.heart, d); c.anim(.blush, [(1, 300, .out), (1, d - 600, .lin), (0, 300, .inOut)]); c.emit(.heart, 4)
            c.anim(.oy, [(-0.1, 160, .out), (0, 300, .back)])
        case "surprised":
            c.ov(.dot, d); c.anim(.oy, [(-0.3, 140, .out), (0, 380, .back)]); c.anim(.es, [(1.25, 120, .out), (1, 500, .inOut)])
        case "proud":
            c.ov(.star, d); c.emit(.star, 5); c.anim(.tilt, [(-0.14, 220, .out), (-0.14, d - 500, .lin), (0, 280, .inOut)])
            c.anim(.blush, [(0.7, 250, .out), (0.7, d - 550, .lin), (0, 300, .inOut)])
        case "wink":
            c.ov(.wink, d); c.anim(.tilt, [(0.12, 160, .out), (0.12, d - 400, .lin), (0, 240, .inOut)])
        case "yawn":
            c.ov(.tired, d); c.anim(.sy, [(1.12, 500, .inOut), (1, 500, .inOut)]); c.anim(.sx, [(0.94, 500, .inOut), (1, 500, .inOut)])
            c.anim(.mouth, [(0.8, 500, .inOut), (0, 500, .inOut)])
            c.later(700) { $0.ov(.closed, 1100); $0.emit(.z, 2) }
        case "happy":
            c.ov(.happy, d); c.anim(.blush, [(0.6, 200, .out), (0, 600, .inOut)])
        case "annoyed":
            c.ov(.line, 800)
        default: break
        }
    }
}

// MARK: - Playful: cat body language

@MainActor
struct PlayfulProfile: MotionProfile {
    let key = "playful", label = "Playful"
    struct Rest { var eye: CatEye, tilt: Double, earL: Double, earR: Double, earU: Double, earF: Double, pupil: Double, oy: Double }
    static let rest: [CatState: Rest] = [
        .idle: Rest(eye: .pill, tilt: 0, earL: 0, earR: 0, earU: 1, earF: 0, pupil: 0.45, oy: 0),
        .working: Rest(eye: .pill, tilt: 0, earL: -0.08, earR: -0.08, earU: 1.1, earF: 0, pupil: 0.5, oy: 0),
        .thinking: Rest(eye: .pill, tilt: 0.14, earL: 0, earR: 0.38, earU: 1, earF: 0, pupil: 0.55, oy: 0),
        .searching: Rest(eye: .wide, tilt: 0, earL: -0.1, earR: -0.1, earU: 1.15, earF: 0, pupil: 0.92, oy: 0.05),
        .approval: Rest(eye: .wide, tilt: 0, earL: -0.12, earR: -0.12, earU: 1.22, earF: 0, pupil: 0.75, oy: 0),
        .question: Rest(eye: .pill, tilt: 0.24, earL: -0.05, earR: 0.5, earU: 1, earF: 0, pupil: 0.7, oy: 0),
        .error: Rest(eye: .flat, tilt: 0, earL: 0, earR: 0, earU: 1, earF: 1, pupil: 0.12, oy: 0),
        .finished: Rest(eye: .happy, tilt: 0, earL: 0.12, earR: 0.12, earU: 1, earF: 0, pupil: 0.45, oy: 0),
        .ratelimit: Rest(eye: .tired, tilt: 0, earL: 0, earR: 0, earU: 0.9, earF: 0.45, pupil: 0.4, oy: 0),
        .sleeping: Rest(eye: .closed, tilt: 0, earL: 0, earR: 0, earU: 1, earF: 0.25, pupil: 0.45, oy: 0.08),
        .dizzy: Rest(eye: .spiral, tilt: 0, earL: 0, earR: 0, earU: 1, earF: 0, pupil: 0.45, oy: 0),
    ]
    let squash = (sy: 0.86, sx: 1.1)

    func eye(_ st: CatState) -> CatEye { Self.rest[st]!.eye }

    func enter(_ c: CatEngine, _ st: CatState, _ prev: CatState) {
        if prev == .sleeping && st != .sleeping && st != .dizzy { c.later(220, "st") { $0.zoomies() } }
        switch st {
        case .idle: if prev != .idle { c.blink() }
        case .working:
            c.blink(); c.twitch(.earL)
            c.later(140, "st") { $0.twitch(.earR) }
        case .thinking: c.blink()
        case .searching: c.anim(.oy, [(0.12, 160, .out), (0.05, 300, .inOut)])
        case .approval:
            c.anim(.oy, [(0.08, 110, .out), (-0.26, 170, .out), (0, 340, .back)])
            c.anim(.sy, [(0.88, 110, .out), (1.1, 170, .out), (1, 340, .back)])
            c.anim(.sx, [(1.08, 110, .out), (0.94, 170, .out), (1, 340, .back)])
            c.anim(.earU, [(1.4, 140, .out), (1.22, 300, .inOut)])
        case .question:
            c.anim(.tilt, [(0.3, 220, .out), (0.24, 300, .inOut)]); c.blink()
        case .error:
            c.anim(.sx, [(1.14, 80, .out), (1, 450, .inOut)]); c.anim(.sy, [(1.1, 80, .out), (1, 450, .inOut)])
            c.anim(.oy, [(0.07, 80, .out), (0, 420, .inOut)]); c.anim(.earF, [(1, 90, .out)])
            c.anim(.wh, [(0.35, 80, .out), (0, 500, .inOut)])
            c.mpose([(.mouth, 0.75), (.smile, -1), (.mround, 0)], 650, 80, 220)
            c.later(900, "st") { $0.hairball() }
        case .finished:
            if CatRules.zoomiesOnFinish(workedForMs: c.workedFor, thresholdMs: c.cfg.zoomAfter) {
                c.later(150, "st") { $0.zoomies() }
                c.later(2200, "st") { $0.emit(.spark, 4) }
                break
            }
            c.anim(.tilt, [(0.16, 260, .inOut), (-0.16, 420, .inOut), (0.08, 320, .inOut), (0, 300, .inOut)])
            c.anim(.blush, [(0.8, 250, .out), (0.8, 900, .lin), (0, 500, .inOut)])
            c.later(350, "st") { $0.emit(.spark, 5) }
        case .ratelimit: c.nextYawn = c.now() + 300
        default: break
        }
    }

    func targets(_ c: CatEngine, _ st: CatState, _ T: Double, _ tg: inout CatTargets) -> (yaw: Double, pitch: Double) {
        let r = Self.rest[st]!
        tg.tilt = r.tilt; tg.earL = r.earL; tg.earR = r.earR; tg.earU = r.earU; tg.earF = r.earF; tg.pupil = r.pupil; tg.oy = r.oy
        var ty = c.lookX * 0.62, tp = c.lookY * 0.5
        if st == .thinking { ty = ty * 0.35 - 0.55 * 0.55; tp = tp * 0.3 + 0.55 * 0.5 }
        if st == .sleeping { ty = 0; tp = -0.14; tg.sy = 1 + 0.04 * sin(1.2 * T); tg.sx = 1 - 0.04 * 0.57 * sin(1.2 * T) }
        if st == .searching { ty = sin(2.2 * T) * 0.55; tg.earL = -0.1 - sin(2.2 * T) * 0.28; tg.earR = -0.1 + sin(2.2 * T) * 0.28 }
        if st == .dizzy { ty = sin(3.5 * T) * 0.2; tg.tilt = sin(7 * T) * 0.12; tg.earL = sin(9 * T) * 0.45; tg.earR = -sin(9 * T + 1) * 0.45 }
        if st == .approval { tg.oy = -pow(max(0, sin(CatMath.tau * T / 1.4)), 4) * 0.09 }
        if st == .working { tg.oy = -pow(abs(sin(Double.pi * 1.6 * T)), 2) * 0.035 }
        return (ty, tp)
    }

    func post(_ c: CatEngine, _ st: CatState, _ T: Double, _ kG: Double) {
        if c.tw[.ox] == nil {
            if st == .searching { c.s.ox = sin(16 * T) * 0.012 }
            else if st == .dizzy { c.s.ox = cos(7 * T) * 0.07 }
            else { c.s.ox += (0 - c.s.ox) * kG }
        }
        if st == .dizzy && c.tw[.oy] == nil { c.s.oy = sin(7 * T) * 0.05 }
    }

    func ambient(_ c: CatEngine, _ t: Double) {
        let st = c.state
        if st == .idle && t >= c.nextBlep {
            if c.tw[.tongue] == nil && c.tw[.mouth] == nil { if c.rand() < 0.55 { c.blep() } else { c.lick() } }
            c.nextBlep = t + c.u(8000, 15000)
        }
        if [.idle, .working, .thinking, .sleeping, .finished, .question].contains(st) && t >= c.nextTw {
            c.twitch(c.rand() < 0.5 ? .earL : .earR)
            c.nextTw = t + (st == .working ? c.u(1500, 3000) : st == .sleeping ? c.u(4000, 8000) : c.u(3000, 7000)) * c.pm().earFlickEvery
        }
        if st == .idle && t >= c.nextSB {
            c.slowBlink()
            c.nextSB = t + c.u(8000, 14000) * c.pm().slowBlinkEvery
        }
        if st == .ratelimit && t >= c.nextYawn { emote(c, "yawn"); c.nextYawn = t + 4800 }
        if st == .sleeping && t >= c.nextAmb { c.emit(.z, 1); c.nextAmb = t + 1600 }
    }

    func emote(_ c: CatEngine, _ n: String) {
        let d = 1800.0
        switch n {
        case "love":
            c.ov(.closed, d)
            c.anim(.purr, [(1, 200, .out), (1, d - 500, .lin), (0, 300, .inOut)])
            c.anim(.blush, [(1, 300, .out), (1, d - 600, .lin), (0, 300, .inOut)])
            c.anim(.earL, [(0.18, 250, .out), (0.18, d - 500, .lin), (0, 250, .inOut)])
            c.anim(.earR, [(0.18, 250, .out), (0.18, d - 500, .lin), (0, 250, .inOut)])
            c.anim(.tilt, [(c.lookX >= 0 ? 0.12 : -0.12, 400, .inOut), (0, 900, .inOut)])
            c.emit(.heart, 3)
        case "surprised":
            c.ov(.dot, 1100)
            c.anim(.earU, [(1.38, 90, .out), (1, 600, .inOut)])
            c.anim(.sx, [(1.12, 80, .out), (1, 500, .inOut)]); c.anim(.sy, [(1.12, 80, .out), (1, 500, .inOut)])
            c.anim(.oy, [(-0.2, 120, .out), (0, 400, .back)])
            c.anim(.pupil, [(1, 100, .out), (1, 700, .lin), (0.45, 400, .inOut)])
            c.anim(.wh, [(0.4, 80, .out), (0, 500, .inOut)])
        case "proud":
            c.ov(.happy, d)
            c.anim(.lift, [(0.28, 260, .out), (0.28, d - 560, .lin), (0, 300, .inOut)])
            c.anim(.earU, [(1.15, 200, .out), (1.15, d - 500, .lin), (1, 300, .inOut)])
            c.emit(.spark, 4)
            c.anim(.blush, [(0.5, 250, .out), (0.5, d - 550, .lin), (0, 300, .inOut)])
        case "wink":
            c.ov(.wink, 1100); c.twitch(.earR)
            c.anim(.tilt, [(0.1, 180, .out), (0.1, 700, .lin), (0, 240, .inOut)])
        case "yawn":
            c.ov(.closed, 1300)
            c.anim(.mouth, [(1, 450, .out), (1, 500, .lin), (0, 350, .inOut)])
            c.anim(.sy, [(1.12, 450, .inOut), (1, 800, .inOut)]); c.anim(.sx, [(0.94, 450, .inOut), (1, 800, .inOut)])
            c.anim(.earF, [(0.75, 450, .inOut), (c.tg.earF, 800, .inOut)])
        case "happy":
            c.ov(.happy, 1400)
            c.anim(.oy, [(-0.06, 120, .out), (0, 160, .inOut), (-0.06, 120, .out), (0, 200, .back)])
            c.anim(.earU, [(1.12, 150, .out), (1, 600, .inOut)])
            c.anim(.blush, [(0.6, 200, .out), (0, 700, .inOut)])
        case "annoyed":
            c.ov(.line, 900)
            c.anim(.earF, [(1, 60, .out), (1, 700, .lin), (c.tg.earF, 400, .inOut)])
            c.anim(.wh, [(0.4, 60, .out), (0, 400, .inOut)])
        default: break
        }
    }
}
```

**Create `NotchBuddy/Sources/App/CatEngine.swift`:**

```swift
import Combine
import Foundation

// The cat engine: a pose that eases toward the targets of the current state, tweens for the one-off moves, a queue of delayed actions,
// particles, and the file catch, the hairball and the zoomies. One class for both motion styles (a `MotionProfile` holds the style).
// Port of the "Engine" section of design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/motion-cases.json and
// sequence-cases.json drive it on a fake clock with a seeded random source and pin every number.
//
// The engine never reads a clock or a random source of its own: `now()` (milliseconds) and `rand()` (0 up to, not including, 1)
// are injected. The order of `rand()` calls is part of the contract: a blink, a flick or a bleep must draw its random numbers at the
// same moment and in the same order as the core, or the random schedule drifts away from the fixtures.

/// The targets the pose eases toward each frame, which the engine's `computeTargets` fills for the current state.
struct CatTargets {
    var yaw = 0.0, pitch = 0.0, tilt = 0.0, sx = 1.0, sy = 1.0, es = 1.0, oy = 0.0
    var earL = 0.0, earR = 0.0, earU = 1.0, earF = 0.0, pupil = 0.45, purr = 0.0, lid = 0.0
    var mouth = 0.0, smile = 0.0, tongue = 0.0, mround = 0.0, mskew = 0.0, wavy = 0.0

    /// A target by pose key; the keys the engine never pulls (roll, open, ox, tint, blush, badgeS, lift, wh, paws) have none, and read as 0.
    subscript(k: PoseKey) -> Double {
        get {
            switch k {
            case .yaw: return yaw
            case .pitch: return pitch
            case .tilt: return tilt
            case .sx: return sx
            case .sy: return sy
            case .es: return es
            case .oy: return oy
            case .earL: return earL
            case .earR: return earR
            case .earU: return earU
            case .earF: return earF
            case .pupil: return pupil
            case .purr: return purr
            case .lid: return lid
            case .mouth: return mouth
            case .smile: return smile
            case .tongue: return tongue
            case .mround: return mround
            case .mskew: return mskew
            case .wavy: return wavy
            default: return 0
            }
        }
        set {
            switch k {
            case .yaw: yaw = newValue
            case .pitch: pitch = newValue
            case .tilt: tilt = newValue
            case .sx: sx = newValue
            case .sy: sy = newValue
            case .es: es = newValue
            case .oy: oy = newValue
            case .earL: earL = newValue
            case .earR: earR = newValue
            case .earU: earU = newValue
            case .earF: earF = newValue
            case .pupil: pupil = newValue
            case .purr: purr = newValue
            case .lid: lid = newValue
            case .mouth: mouth = newValue
            case .smile: smile = newValue
            case .tongue: tongue = newValue
            case .mround: mround = newValue
            case .mskew: mskew = newValue
            case .wavy: wavy = newValue
            default: break
            }
        }
    }
}

/// The settings every engine reads unless it is given its own: the global motion style, a per-cat motion override (by cat ID),
/// a per-cat personality, and how long a run of work earns zoomies (ms).
/// One key of a tween: the value to reach, how long it takes (ms) and the easing.
typealias CatKey = (target: Double, duration: Double, ease: CatEase)

/// A running tween on one pose property. While it runs, the property is not pulled toward its target.
struct CatTween {
    var from: Double
    var keys: [CatKey]
    var i = 0
    var t0: Double
    var done: (@MainActor (CatEngine) -> Void)?
}

@MainActor
final class CatConfig {
    static let shared = CatConfig()
    /// The cat shown in the notch and in the small pills (Settings arrives in stage 5; Shrimpy is the default).
    var character = "shrimpy"
    var motion: String
    var override: [String: String]
    var pers: [String: CatPersonality]
    var zoomAfter: Double

    init(motion: String = "playful", override: [String: String] = [:], pers: [String: CatPersonality] = [:], zoomAfter: Double = CatRules.zoomAfterMs) {
        self.motion = motion; self.override = override; self.pers = pers; self.zoomAfter = zoomAfter
    }
}

@MainActor
final class CatEngine: ObservableObject {
    let p: CatPreset
    let mini: Bool
    let now: () -> Double
    let rand: () -> Double
    let cfg: CatConfig
    let quiet: Bool
    /// Called with (ms, name) for blinks, flicks, bleps, licks, emotes, zoomies and hairballs. Tests collect them.
    var onNote: ((Int, String) -> Void)?
    /// Called with a sound name ("slap", "annoyed", "greet"); the app plays it. The engine itself is silent.
    var onSound: ((String) -> Void)?
    /// Called on the third quick poke instead of the engine turning dizzy itself (the app's state machine owns dizzy).
    var onDizzy: (() -> Void)?

    var s = CatPose()
    var tg = CatTargets()
    var tw: [PoseKey: CatTween] = [:]
    struct Queued { var at: Double; var tag: String?; var fn: @MainActor (CatEngine) -> Void }
    var q: [Queued] = []
    var parts: [CatParticle] = []
    var balls: [CatBall] = []
    var col = hexRGB(CatTables.color[.idle]!), colT = hexRGB(CatTables.color[.idle]!)
    var gc = [255.0, 255.0, 255.0], ga = 0.12
    var state: CatState = .idle
    var badge: CatBadge?
    var eyeOv: CatEye?
    var eyeUntil = 0.0
    var bt = 0
    var lookX = 0.0, lookY = 0.0
    var slaps: [Double] = []
    var dizzyUntil = 0.0
    var saved: CatState?
    var slotH = 0.0, slotT = 0.0, slotV = 0.0, chew = 0.0, chewStart = 0.0, chewUntil = 0.0
    var catching = false
    var waveStart = 0.0, waveUntil = 0.0, greetTok = 0, hbTok = 0, zoomTok = 0, zoomUntil = 0.0, zv = 0.0, mfx = 0.0
    var busySince: Double?, workedFor = 0.0
    var nextBlink = 0.0, nextTw = 0.0, nextSB = 0.0, nextAmb = 0.0, nextYawn = 0.0, nextBlep = 0.0, nextPers = 0.0
    var blushBase = 0.0
    var miniNext = 0.0
    var miniLook = (x: 0.0, y: 0.0)
    var lastOx: Double?
    /// Where the cat rests and where its mouth is, in px: the renderer hands them back after every draw (the hairball starts at the mouth).
    var base: (x: Double, y: Double, R: Double)?
    var mouthPoint: (x: Double, y: Double)?

    // App-level members that are not in the contract (the fixtures leave them alone).
    /// The eye scale the cat eases to: 1.08 while the pointer hovers its head.
    var tgEs = 1.0
    var isDancing = false
    var dancingLevel = 0.0
    /// Seconds on the engine's clock at the end of the last update, so a view can work out `dt` with `CatEngine.frameDelta`.
    var lastTime: Double
    /// The colour of the agent the cat belongs to, a hex string. Unused in stages 1 to 4: the collar is optional, Off by default, and arrives with
    /// its Settings rows in stage 6 (small cats then wear their agent's collar, the big cat the collar of the agent driving its state).
    var collar: String?

    init(_ p: CatPreset, mini: Bool = false, now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime * 1000 },
         rand: @escaping () -> Double = { Double.random(in: 0..<1) }, cfg: CatConfig? = nil, quiet: Bool = false, state: CatState = .idle) {
        self.p = p; self.mini = mini; self.now = now; self.rand = rand; self.cfg = cfg ?? CatConfig.shared; self.quiet = quiet
        let t = now()
        lastTime = t / 1000
        nextBlink = t + u(1500, 3500)
        nextTw = t + u(2000, 5000)
        nextSB = t + u(6000, 10000)
        nextAmb = t + 1300
        nextBlep = t + u(5000, 9000)
        nextPers = t + u(3000, 6000)
        setState(state, force: true)
    }

    /// The motion style in force for this cat: its own override, else the global style; an unknown stored value means Playful.
    var motion: String {
        let override = cfg.override[p.base ?? p.name].flatMap { $0.isEmpty ? nil : $0 }
        let m = override ?? cfg.motion
        return CatProfiles.named(m) != nil ? m : "playful"
    }
    var prof: any MotionProfile { CatProfiles.named(motion)! }
    var pers: CatPersonality { cfg.pers[p.base ?? p.name] ?? Personality.named("balanced") }
    /// What this cat's personality changes.
    func pm() -> CatMultipliers { Personality.multipliers(pers) }

    func u(_ a: Double, _ b: Double) -> Double { a + rand() * (b - a) }
    func note(_ ev: String) { onNote?(Int(now().rounded()), ev) }

    // MARK: Tweens and the queue

    func anim(_ k: PoseKey, _ keys: [CatKey], done: (@MainActor (CatEngine) -> Void)? = nil) {
        tw[k] = CatTween(from: s[k], keys: keys, i: 0, t0: now(), done: done)
    }
    func anim(_ k: PoseKey, _ keys: [CatKey], _ done: @escaping @MainActor (CatEngine) -> Void) { anim(k, keys, done: done) }
    func later(_ d: Double, _ tag: String? = nil, _ fn: @escaping @MainActor (CatEngine) -> Void) { q.append(Queued(at: now() + d, tag: tag, fn: fn)) }
    func ov(_ shape: CatEye, _ d: Double) { eyeOv = shape; eyeUntil = now() + d }
    /// Holds a mouth pose for d ms, then eases back to the state's mouth.
    func mpose(_ v: [(PoseKey, Double)], _ d: Double, _ i: Double = 150, _ o: Double = 250) {
        for (k, val) in v { anim(k, [(val, i, .out), (val, max(0, d - i - o), .lin), (tg[k], o, .inOut)]) }
    }

    // MARK: Small moves

    func blep() { note("blep"); anim(.tongue, [(0.7, 150, .out), (0.7, 1300, .lin), (tg.tongue, 220, .inOut)]) }
    func lick() { note("lick"); anim(.mouth, [(0.16, 90, .out), (tg.mouth, 170, .inOut)]); anim(.tongue, [(1, 90, .out), (tg.tongue, 180, .inOut)]) }
    func slowBlink() { note("slowblink"); anim(.lid, [(0.75, 380, .inOut), (0.75, 320, .lin), (0, 480, .inOut)]) }
    func eyeShape() -> CatEye { if let o = eyeOv, now() < eyeUntil { return o }; return prof.eye(state) }
    func blink() { if tw[.open] != nil { return }; note("blink"); anim(.open, [(0.06, 70, .inOut), (1, 130, .out)]) }
    func twitch(_ ear: PoseKey) {
        note("twitch:\(ear.rawValue)")
        let b = tg[ear]
        anim(ear, [(b + 0.5, 60, .out), (b, 280, .back)])
        anim(.wh, [(0.25, 60, .out), (0, 300, .inOut)])
    }

    func emit(_ kind: CatParticleKind, _ n: Int) {
        for i in 0..<n {
            let z = kind == .z
            let x = (rand() - 0.5) * 0.9 + (z ? 0.55 : 0) + s.ox / 1.3
            let y = -0.85 - rand() * 0.2 + s.oy / 1.3
            let vx = (rand() - 0.5) * 0.35 + (z ? 0.18 : 0)
            let vy = -(0.45 + rand() * 0.35)
            let life = 1.3 + rand() * 0.5, size = 0.15 + rand() * 0.08, rot = rand() * 6
            parts.append(CatParticle(kind: kind, x: x, y: y, vx: vx, vy: vy, age: -0.14 * Double(i), life: life, size: size, rot: rot))
        }
    }

    func setBadge(_ b: CatBadge?) {
        bt += 1
        let tok = bt
        anim(.badgeS, [(0, 90, .inOut)])
        later(100) { c in
            if tok != c.bt { return }
            c.badge = b
            if b != nil { c.anim(.badgeS, [(1, 280, .back)]) }
        }
    }

    // MARK: State

    func setState(_ st: CatState, force: Bool = false) {
        if !force && st == state { return }
        let prev = state
        state = st
        q.removeAll { $0.tag == "st" }
        if st != .dizzy { dizzyUntil = 0 }
        colT = hexRGB(CatTables.color[st]!)
        s.tint = CatTables.tint[st]!
        let b = CatTables.badge[st]
        if b != badge || force { setBadge(b) }
        for k in [PoseKey.oy, .ox, .roll, .sx, .sy, .tilt, .earF, .earU, .lid] + CatTables.mouthKeys { tw[k] = nil }
        s.roll = 0
        let wc = CatRules.workClockStep(CatRules.WorkClock(busySince: busySince, workedFor: workedFor), state: st, nowMs: now())
        busySince = wc.busySince; workedFor = wc.workedFor
        if eyeUntil != .infinity { eyeOv = nil }
        prof.enter(self, st, prev)
    }

    func emote(_ n: String) {
        note("emote:\(n)")
        if n == "hello" { return greet() }
        if n == "zoomies" { return zoomies() }
        if n == "hairball" { return hairball() }
        prof.emote(self, n)
        if n == "annoyed" { later(60) { $0.onSound?("annoyed") } }
        if let m = CatTables.emoteMouth[n] { mpose(m.pose, m.ms) }
    }

    /// A poke: a squash, then annoyed (or love, for an affectionate cat); three quick pokes make the cat dizzy.
    func slap() {
        interruptGreet()
        let t = now()
        slaps = slaps.filter { t - $0 < 1700 }
        slaps.append(t)
        let sq = prof.squash
        anim(.sy, [(sq.sy, 70, .out), (1.1, 130, .out), (1, 170, .inOut)])
        anim(.sx, [(sq.sx, 70, .out), (0.95, 130, .out), (1, 170, .inOut)])
        if state == .dizzy { return }
        onSound?("slap")
        if slaps.count >= 3 {
            slaps = []
            if let onDizzy { onDizzy(); return }
            saved = state; setState(CatState.dizzy); dizzyUntil = t + 3300
            return
        }
        let M = pm()
        if M.poke == "love" { return emote("love") }
        emote("annoyed")
        if M.pokeHiss { mpose([(.mouth, 0.6), (.smile, -1), (.mround, 0)], 500, 60, 180) }
    }

    /// Idle habits that come from personality: yawns, zoomies, mews, purrs, hmphs, winks.
    func persAmbient(_ t: Double) {
        let I = pm().idle
        if state != .idle || t < nextPers { return }
        nextPers = t + u(6000, 11000)
        let r = rand()
        if I.yawn && r < 0.5 { return emote("yawn") }
        if I.zoomies && r < 0.35 { return zoomies() }
        if I.mew && r < 0.6 { return mpose([(.mouth, 0.42), (.mround, 0.4), (.smile, 0.2)], 420, 100, 180) }
        if I.purr && r < 0.55 {
            anim(.lid, [(0.75, 380, .inOut), (0.75, 600, .lin), (0, 480, .inOut)])
            return anim(.purr, [(1, 200, .out), (1, 1000, .lin), (0, 300, .inOut)])
        }
        if I.hmph && r < 0.55 { return mpose([(.smile, -0.85), (.mskew, -0.7)], 1000) }
        if I.wink && r < 0.5 { ov(.wink, 550); blep() }
    }

    // MARK: Greeting wave, file catch, hairball, zoomies

    /// Paw wave, upstream's greet timings with paws for hands.
    func greet() {
        let t = now()
        greetTok += 1
        let tok = greetTok
        waveStart = t + 450; waveUntil = t + 1550
        ov(.happy, 2000)
        anim(.oy, [(-0.06, 220, .out), (0, 220, .back)])
        later(250) { c in
            if tok != c.greetTok { return }
            c.anim(.paws, [(1, 280, .out)])
            c.anim(.sy, [(0.95, 100, .out), (1, 260, .back)]); c.anim(.sx, [(1.04, 100, .out), (1, 260, .back)])
            if c.motion == "playful" { c.anim(.earU, [(1.15, 200, .out), (1.15, 900, .lin), (1, 400, .inOut)]) }
            c.onSound?("greet")
        }
        later(450) { if tok == $0.greetTok { $0.mpose([(.mouth, 0.45), (.mround, 0.45), (.smile, 0.35)], 650, 90, 200) } }
        later(550) { if tok == $0.greetTok { $0.blink() } }
        later(1500) { if tok == $0.greetTok { $0.blink() } }
        later(1550) { c in
            if tok != c.greetTok { return }
            c.waveUntil = 0
            c.anim(.paws, [(0, 200, .inOut)])
        }
        later(1750) { if tok == $0.greetTok { $0.ov(.happy, 300) } }
    }

    func interruptGreet() {
        if s.paws <= 0.01 && now() >= waveUntil { return }
        greetTok += 1
        waveUntil = 0; waveStart = 0
        anim(.paws, [(0, 150, .inOut)])
    }

    /// A dropped file arcs into the cat's mouth over this long (ms).
    static let flightMs = 380.0

    /// File catch, step 1: open wide while a file hovers.
    func catchOpen(_ on: Bool) {
        if on == catching { return }
        catching = on
        if on {
            slotT = 0.55; eyeOv = .wide; eyeUntil = .infinity
            anim(.oy, [(-0.05, 160, .out), (-0.03, 200, .inOut)])
        } else {
            slotT = 0
            if eyeUntil == .infinity { eyeOv = nil; eyeUntil = 0 }
        }
    }

    /// Step 2: snap wider on the drop while the file flies in.
    func catchDrop() { catching = true; slotT = 1.05; eyeOv = .wide; eyeUntil = .infinity }

    /// Steps 3 and 4: gulp with a squash, then chew for 0.85 s with happy eyes.
    func catchArrive() {
        catching = false; slotT = 0
        let t = now()
        chewStart = t + 80; chewUntil = t + 930
        ov(.happy, 1250)
        anim(.sy, [(0.8, 80, .out), (1.16, 130, .out), (1, 220, .back)])
        anim(.sx, [(1.24, 80, .out), (0.92, 130, .out), (1, 220, .back)])
        if motion == "playful" {
            anim(.earU, [(1.15, 150, .out), (1, 500, .inOut)])
            anim(.blush, [(0.6, 200, .out), (0, 800, .inOut)])
        }
        later(950) { $0.lick() }
        later(1000) { $0.emit(.spark, 3) }
    }

    /// The file has been swallowed: it arrives in the mouth in the time a thrown file takes to fly there.
    func gulp() {
        catchDrop()
        later(CatEngine.flightMs) { $0.catchArrive() }
    }

    /// Holds an eye shape until something else sets one (a mini cat with a fixed expression).
    func holdEye(_ shape: CatEye) { eyeOv = shape; eyeUntil = .infinity }

    /// A file the cat cannot take: it is caught, gagged on and coughed back up as a hairball wrapped around the file.
    func catchReject(_ ext: String) {
        catching = false; slotT = 0; eyeOv = nil; eyeUntil = 0
        later(120) { $0.hairball(ext) }
    }

    /// Hairball: ears back, three heaves, then it comes up (with the file, if it was one).
    func hairball(_ file: String? = nil) {
        note("hairball")
        let pl = motion == "playful"
        hbTok += 1
        let tok = hbTok
        ov(.closed, 1300)
        if pl { anim(.earF, [(0.7, 150, .out), (0.7, 1000, .lin), (tg.earF, 400, .inOut)]) }
        anim(.oy, [(0.06, 140, .out), (0, 180, .inOut), (0.07, 140, .out), (0, 180, .inOut), (0.09, 140, .out), (-0.02, 160, .inOut), (0.11, 170, .out), (0, 320, .back)])
        anim(.sy, [(0.92, 140, .out), (1.04, 180, .inOut), (0.9, 140, .out), (1.05, 180, .inOut), (0.88, 140, .out), (1.06, 160, .inOut), (0.86, 170, .out), (1, 320, .back)])
        anim(.sx, [(1.05, 140, .out), (0.98, 180, .inOut), (1.07, 140, .out), (0.97, 180, .inOut), (1.09, 140, .out), (0.96, 160, .inOut), (1.1, 170, .out), (1, 320, .back)])
        anim(.mouth, [(0.22, 140, .out), (0, 180, .inOut), (0.28, 140, .out), (0, 180, .inOut), (0.34, 140, .out), (0, 160, .inOut), (1.05, 170, .out), (1.05, 160, .lin), (tg.mouth, 260, .inOut)])
        anim(.mround, [(0.3, 140, .out), (0.3, 800, .lin), (0, 170, .out), (0, 420, .lin), (tg.mround, 200, .inOut)])
        anim(.smile, [(-0.7, 140, .out), (-0.7, 970, .lin), (0.5, 330, .inOut), (0.5, 700, .lin), (tg.smile, 300, .inOut)])
        later(1110) { c in if tok == c.hbTok { c.spitBall(file) } }
        later(1450) { c in
            if tok != c.hbTok { return }
            c.ov(.happy, 900)
            if pl { c.anim(.blush, [(0.45, 200, .out), (0, 700, .inOut)]) }
            c.later(320) { $0.lick() }
        }
    }

    func spitBall(_ file: String?) {
        guard let m = mouthPoint, let b0 = base else { return }
        let R = b0.R, dir = rand() < 0.5 ? -1.0 : 1.0, mx = (m.x - b0.x) / R, my = (m.y - b0.y) / R
        let vx = dir * u(0.55, 0.85), vy = u(-0.9, -0.6)
        let seed = Int(rand() * 1e9)
        balls.append(CatBall(x: mx, y: my, vx: vx, vy: vy, rot: 0, age: 0, life: file != nil ? 2.6 : 2.4, file: file, seed: seed, floor: p.ruff != nil ? 1.34 : 1.12))
        for i in 0..<4 {
            let x = mx / 1.3 + (rand() - 0.5) * 0.15
            let pvx = (rand() - 0.5) * 0.5, pvy = u(-0.35, -0.15)
            let life = 0.9 + rand() * 0.4, size = 0.12 + rand() * 0.05, rot = rand() * 6
            parts.append(CatParticle(kind: .hair, x: x, y: my / 1.3, vx: pvx, vy: pvy, age: -0.05 * Double(i), life: life, size: size, rot: rot))
        }
    }

    /// Zoomies: pupils blown, ears back, side-to-side dashes with skids, then a happy flop.
    func zoomies() {
        note("zoomies")
        let pl = motion == "playful"
        zoomTok += 1
        let tok = zoomTok
        interruptGreet()
        zoomUntil = now() + 1950
        ov(.wide, 1900)
        anim(.pupil, [(1, 120, .out), (1, 1750, .lin), (tg.pupil, 400, .inOut)])
        anim(.earF, [(0.55, 150, .out), (0.55, 1750, .lin), (tg.earF, 400, .inOut)])
        anim(.ox, [(-0.05, 70, .inOut), (0.04, 70, .inOut), (-0.05, 70, .inOut), (0.04, 70, .inOut), (0, 60, .inOut), (0.88, 240, .in), (0.97, 90, .out), (0.84, 110, .inOut),
                   (-0.88, 380, .inOut), (-0.97, 90, .out), (-0.84, 110, .inOut), (0.3, 320, .inOut), (0, 260, .back)])
        mpose([(.mouth, 0.32), (.tongue, 0.9), (.smile, 0.6), (.mround, 0)], 1950, 150, 300)
        later(670) { c in if tok == c.zoomTok { c.dust(1) } }
        later(1250) { c in if tok == c.zoomTok { c.dust(-1) } }
        later(1950) { c in
            if tok != c.zoomTok { return }
            c.ov(.happy, 900)
            c.anim(.sy, [(0.84, 90, .out), (1.06, 150, .out), (1, 220, .back)])
            c.anim(.sx, [(1.14, 90, .out), (0.96, 150, .out), (1, 220, .back)])
            c.emit(.spark, 3)
            if pl { c.anim(.blush, [(0.5, 200, .out), (0, 800, .inOut)]) }
        }
    }

    func dust(_ dir: Double) {
        let y = (p.ruff != nil ? 1.1 : 0.88) / 1.3
        for i in 0..<4 {
            let x = (s.ox + dir * 0.45) / 1.3 + (rand() - 0.5) * 0.2
            let yy = y + (rand() - 0.5) * 0.06
            let vx = -dir * u(0.12, 0.35), vy = -u(0.03, 0.12)
            let life = 0.55 + rand() * 0.2, size = 0.09 + rand() * 0.05
            parts.append(CatParticle(kind: .dust, x: x, y: yy, vx: vx, vy: vy, age: -Double(i) * 0.04, life: life, size: size, rot: 0))
        }
    }

    // MARK: Frame

    /// How open the mouth is right now: the state's mouth plus its motion, or the file-catch spring and chew, whichever is wider.
    func mouthOpen() -> Double { max(s.mouth + mfx, slotH + chew) }

    /// Fills `tg`, the targets the pose eases toward, for the current state: the profile's rest pose, the state's mouth, the personality,
    /// and the file-catch, wave and zoomies overrides. `t` is the clock in ms, `T` the same in seconds. It reads the engine's inputs
    /// (state, lookX/lookY, personality) and never the tweens, so fixtures can call it directly.
    func computeTargets(_ t: Double, _ T: Double) {
        let st = state, pf = prof
        tg.sx = 1; tg.sy = 1; tg.es = tgEs; tg.purr = 0; tg.lid = 0
        let mo = CatTables.mouthRest[st]!
        for (i, k) in CatTables.mouthKeys.enumerated() { tg[k] = mo[i] }
        mfx = CatTables.mouthFx(st, T)
        var (ty, tp) = pf.targets(self, st, T, &tg)
        // Personality: gaze, resting mouth, lids, ears, bounce, pupils, blush and chatter.
        let M = pm()
        ty *= M.gaze; tp *= M.gaze
        tg.smile += M.smile; tg.mskew += M.skew
        if st != .sleeping { tg.lid = max(tg.lid, M.lid) }
        tg.earF = max(tg.earF, M.earBack); tg.oy *= M.hop; tg.pupil = clamp(tg.pupil + M.pupil, 0.1, 1)
        blushBase = st == .sleeping ? 0 : M.blush
        mfx *= M.chatter
        if mini && ![CatState.thinking, .searching, .sleeping, .dizzy].contains(st) {
            if t > miniNext {
                let x = u(-0.88, 0.88), y = u(-0.55, 0.45)
                miniLook = (x, y)
                miniNext = t + u(500, 2000)
            }
            ty = miniLook.x * 0.62; tp = miniLook.y * 0.5
            tg.sy = 1 + sin(2.2 * T) * 0.04; tg.sx = 1 - sin(2.2 * T) * 0.02
        }
        if catching { tg.earU = 1.25; tg.pupil = 0.95; ty *= 0.3; tp = tp * 0.3 + 0.12 }
        if t > waveStart && t < waveUntil {
            let wt = (t - waveStart) / 1000
            tg.tilt = -0.06 + sin(CatMath.tau * 1.2 * wt) * 0.07
        }
        if t < zoomUntil {
            ty = clamp(zv * 0.25, -0.62, 0.62); tp = -0.05
            tg.tilt = clamp(zv * 0.05, -0.2, 0.2)
            tg.sx = 1 + min(0.16, abs(zv) * 0.045); tg.sy = 1 - min(0.09, abs(zv) * 0.025)
            tg.oy = -abs(sin(T * CatMath.tau * 4.5)) * 0.05 * min(1, abs(zv) / 1.5)
        }
        tg.yaw = ty; tg.pitch = tp
    }

    /// One frame. `dt` is seconds; anything outside 0…0.25 (a sleeping laptop, a clock that stepped back, NaN) is held to that range.
    func update(dt dtIn: Double) {
        let dt = dtIn.isFinite ? min(max(dtIn, 0), 0.25) : 0
        let t = now(), T = t / 1000, st = state, pf = prof
        for k in PoseKey.allCases {
            guard var w = tw[k] else { continue }
            var el = t - w.t0
            while w.i < w.keys.count {
                let key = w.keys[w.i], d = max(1, key.duration)
                if el < d { s[k] = lerp(w.from, key.target, key.ease.at(el / d)); break }
                el -= d; w.t0 += d; w.from = key.target; s[k] = key.target; w.i += 1
            }
            if w.i >= w.keys.count { tw[k] = nil; w.done?(self) } else { tw[k] = w }
        }
        let v = (s.ox - (lastOx ?? s.ox)) / max(dt, 1e-3)
        lastOx = s.ox
        zv += (v - zv) * min(1, dt * 18)
        let due = q.filter { $0.at <= t }
        q = q.filter { $0.at > t }
        for x in due { x.fn(self) }
        computeTargets(t, T)
        let M = pm(), ke = M.speed
        let kL = 1 - pow(0.0025, dt * ke), kG = 1 - pow(0.0008, dt * ke), kC = 1 - pow(0.002, dt)
        for k in [PoseKey.yaw, .pitch] where tw[k] == nil { s[k] += (tg[k] - s[k]) * kL }
        for k in [PoseKey.tilt, .sx, .sy, .es, .oy, .earL, .earR, .earU, .earF, .pupil, .purr, .lid] + CatTables.mouthKeys where tw[k] == nil {
            s[k] += (tg[k] - s[k]) * kG
        }
        pf.post(self, st, T, kG)
        let gT = hexRGB(CatTables.glow[st] ?? "#FFFFFF")
        let gaT = st == .dizzy ? 0 : (st == .idle || st == .sleeping ? 0.12 : 0.42)
        for i in 0..<3 {
            col[i] += (colT[i] - col[i]) * kC
            gc[i] += (gT[i] - gc[i]) * kC
        }
        ga += (gaT - ga) * kC
        if !quiet && t >= nextBlink {
            if st != .sleeping && st != .dizzy {
                blink()
                if rand() < 0.22 { later(230) { $0.blink() } }
            }
            nextBlink = t + (2200 + rand() * 3200) * M.blinkEvery
        }
        if eyeOv != nil && t > eyeUntil { eyeOv = nil }
        if !quiet { pf.ambient(self, t); persAmbient(t) }
        if dizzyUntil != 0 && t > dizzyUntil {
            let b = saved ?? .idle
            dizzyUntil = 0
            setState(b, force: true)
            emote("happy")
        }
        for i in parts.indices { parts[i].age += dt }
        parts.removeAll { $0.age >= $0.life }
        for i in balls.indices {
            balls[i].age += dt
            balls[i].vy += 5.5 * dt
            balls[i].x += balls[i].vx * dt
            balls[i].y += balls[i].vy * dt
            if balls[i].y > balls[i].floor {
                balls[i].y = balls[i].floor
                if balls[i].vy > 0.6 { balls[i].vy *= -0.38; balls[i].vx *= 0.7 } else { balls[i].vy = 0; balls[i].vx *= pow(0.2, dt) }
            }
            balls[i].rot += balls[i].vx * dt * 5
        }
        balls.removeAll { $0.age >= $0.life }
        // Mouth spring, ω₀ = 2π/0.25, ζ = 0.6 (upstream's slot spring), stepped at most 1/60 s at a time like the core: a slow frame is
        // several steps, because one step of 0.066 s or more diverges to NaN.
        let om = CatMath.tau / 0.25
        var r = dt
        while r > 0 {
            let h = min(r, 1.0 / 60), acc = om * om * (slotT - slotH) - 2 * 0.6 * om * slotV
            slotV += acc * h
            slotH = max(0, slotH + slotV * h)
            r -= 1.0 / 60
        }
        chew = t >= chewStart && t < chewUntil ? 0.16 * (0.5 - 0.5 * cos(CatMath.tau * 4.2 * (t - chewStart) / 1000)) : 0
        // Apple Music dance level: fades in over 0.3 s and out over 0.5 s.
        let dancingTarget = isDancing ? 1.0 : 0.0
        if dancingLevel < dancingTarget { dancingLevel = min(dancingTarget, dancingLevel + dt / 0.3) }
        else if dancingLevel > dancingTarget { dancingLevel = max(dancingTarget, dancingLevel - dt / 0.5) }
        lastTime = t / 1000
    }

    /// Everything the renderer needs to draw this cat right now. `time` is seconds for the motion inside shapes (defaults to the engine's clock).
    func look(time: Double? = nil) -> CatLook {
        var l = CatLook(preset: p, pose: s, eye: eyeShape(), mouthOpen: mouthOpen(), color: col, blushBase: blushBase, time: time ?? now() / 1000)
        l.badge = badge
        l.badgeColor = CatTables.color[state]!
        l.glowColor = gc; l.glowAlpha = ga
        l.particles = parts
        l.balls = balls
        l.zoomVelocity = zv
        l.wave = CatWave(now: now(), start: waveStart, until: waveUntil)
        return l
    }

    /// The time between two frames, held to 0…`maxDt` seconds. Both times must come from the engine's own clock (`CatEngine.lastTime`
    /// is on it): mixing two clocks gave the old Mac engine a frame time that was always the maximum.
    static func frameDelta(now: Double, last: Double, maxDt: Double = 0.05) -> Double {
        guard now.isFinite, last.isFinite else { return 0 }
        return max(0, min(maxDt, now - last))
    }

    func setDancing(_ dancing: Bool) { if isDancing != dancing { isDancing = dancing } }
}
```

- [ ] **Step 4: Run the test**

Run: `bash scripts/test-cat-engine.sh`
Expected: PASS

- [ ] **Step 5: Prove the fixtures bite**

In `PlayfulProfile.ambient` change `if c.rand() < 0.55 { c.blep() }` to `if c.rand() < 0.2 { c.blep() }`, run `bash scripts/test-cat-engine.sh`, and see the `ambient` cases fail. Restore it and run the test again. Then, in `CatEngine.update`, replace the `while r > 0 { … }` spring loop by one step with `dt` (`slotV += acc * dt` and so on), and see the "slow frame is several steps" lines fail. Restore it and run the test again.

- [ ] **Step 6: Commit**

```bash
git add tests/CatEngineSupport.swift tests/CatEngineTests.swift scripts/test-cat-engine.sh NotchBuddy/Sources/App/MotionProfiles.swift NotchBuddy/Sources/App/CatEngine.swift
git commit -m "feat(cat): the engine and both motion profiles (states, emotes, mouth, the file catch, hairball, zoomies), tested against the fixtures

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The engine drives the renderer: the states sheet and a frame-time bench (stage 2)

Agent: `nm-implementer`.

**Files:**
- Modify: `tests/CatRendererTests.swift`, `scripts/test-cat-renderer.sh`
- Modify: `scripts/render-cats.swift`, `scripts/render-cats.sh`

**Interfaces:**
- Consumes: `CatEngine.look(time:)`, `CatEngine.update(dt:)`, `CatRenderer.draw` (Tasks 4 and 6).
- Produces `render-cats.sh --states [--cats id,id]` (the 11 states, in both motion styles, after 1.2 s in each), `render-cats.sh --bench` (CPU time per frame of twelve small cats, redrawn at 30 fps like `MiniBotCanvasView`, plus the big one at 60 fps), and `RENDER_CATS_OPT=1` to build the sheet script with `-O`.

- [ ] **Step 1: Extend the renderer test**

The new section runs the engine through every state and emote, for both motion styles and on every coat, and draws a few frames of each: nothing blank, nothing non-finite, and a hairball and particles seen on screen at some point.

**Edit `tests/CatRendererTests.swift`** — replace:

```swift
        CT.checkTrue("nothing above the strip is painted more than a hair (worst alpha \(worst) of 255)", worst <= 160)

        CT.finish()
    }
```

with:

```swift
        CT.checkTrue("nothing above the strip is painted more than a hair (worst alpha \(worst) of 255)", worst <= 160)

        CT.section("the engine drives the renderer: every state and emote on every coat, a few frames each")
        var engineBlank: [String] = [], nonFinite: [String] = [], sawBall = false, sawParticle = false
        for id in CatPresets.ids {
            for profile in ["playful", "classic"] {
                for start in CatState.allCases.map({ "state:" + $0.rawValue }) + ["emote:love", "emote:happy", "emote:surprised", "emote:proud", "emote:wink", "emote:yawn", "emote:annoyed", "emote:hello", "emote:zoomies", "emote:hairball"] {
                    let clock = FakeClock(), rng = CatRNG(seed: 5)
                    let e = CatEngine(CatPresets.byID(id), now: { clock.t }, rand: { rng.next() }, cfg: CatConfig(motion: profile), quiet: true)
                    let L0 = CatGeometry.layout(e.p, e.s, cx: 0, cy: 0, D: 120)
                    e.base = L0.base; e.mouthPoint = L0.mouth
                    if start.hasPrefix("state:") { e.setState(CatState(rawValue: String(start.dropFirst(6)))!) } else { e.emote(String(start.dropFirst(6))) }
                    for frame in 1...150 {
                        clock.t += 1000.0 / 60
                        e.update(dt: 1.0 / 60)
                        if frame % 50 != 0 { continue }
                        if !PoseKey.allCases.allSatisfy({ e.s[$0].isFinite }) { nonFinite.append("\(id) \(profile) \(start) frame \(frame)") }
                        let px = render(240, 240) { R.draw($0, e.look(time: clock.t / 1000), cx: 120, cy: 130, D: 120, CatDrawOptions(glow: true)) }
                        if coverage(px) == 0 { engineBlank.append("\(id) \(profile) \(start) frame \(frame)") }
                        if !e.balls.isEmpty { sawBall = true }
                        if !e.parts.isEmpty { sawParticle = true }
                    }
                }
            }
        }
        CT.check("no state or emote leaves the pose non-finite", nonFinite, [])
        CT.check("nothing came out blank", engineBlank, [])
        CT.checkTrue("a hairball and particles were on screen at some point", sawBall && sawParticle)
        CT.finish()
    }
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-renderer.sh`
Expected: FAIL (`cannot find 'CatEngine' in scope`: the script does not compile the engine yet)

- [ ] **Step 3: Compile the engine into the renderer test**

**Edit `scripts/test-cat-renderer.sh`** — replace:

```bash
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatRenderer.swift \
    tests/CatTestSupport.swift tests/CatBitmapSupport.swift tests/CatRendererTests.swift \
    -o "$TEST_DIR/cat-renderer-tests"
```

with:

```bash
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift tests/CatEngineSupport.swift \
    tests/CatTestSupport.swift tests/CatBitmapSupport.swift tests/CatRendererTests.swift \
    -o "$TEST_DIR/cat-renderer-tests"
```

- [ ] **Step 4: Run the test**

Run: `bash scripts/test-cat-renderer.sh`
Expected: PASS

- [ ] **Step 5: Add the states sheet and the bench to the contact-sheet script**

`scene(...)` builds an engine on a fake clock with a seeded random source, so a sheet looks the same every time. `states` draws every state after 1.2 s, with the glow and the badge, in both motion styles. `bench` times the update and draw of thirteen cats with the thread's CPU time (a busy machine does not inflate it the way it inflates the wall clock).

**Edit `scripts/render-cats.swift`** — replace:

```swift
//   bash scripts/render-cats.sh --cats shrimpy,momo --out two.png  only these coats (IDs)
//   bash scripts/render-cats.sh --stage --cats shrimpy,momo        the big cats on stage panels, like the prototype's Cats section
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

@main
```

with:

```swift
//   bash scripts/render-cats.sh --cats shrimpy,momo --out two.png  only these coats (IDs)
//   bash scripts/render-cats.sh --stage --cats shrimpy,momo        the big cats on stage panels, like the prototype's Cats section
//   bash scripts/render-cats.sh --states --cats shrimpy            the 11 states, in both motion styles, after 1.2 s in each
//   bash scripts/render-cats.sh --bench                            frame time of twelve small cats plus the big one
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

@main
```

**Edit `scripts/render-cats.swift`** — replace:

```swift
    enum Mode {
        case ladder, stage
    }

    struct Args {
```

with:

```swift
    enum Mode {
        case ladder, stage
        case states, bench
    }

    struct Args {
```

**Edit `scripts/render-cats.swift`** — replace:

```swift
            case "--sizes": a.sizes = (it.next() ?? "").split(separator: ",").compactMap { Double($0) }
            case "--stage": a.mode = .stage
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

with:

```swift
            case "--sizes": a.sizes = (it.next() ?? "").split(separator: ",").compactMap { Double($0) }
            case "--stage": a.mode = .stage
            case "--states": a.mode = .states
            case "--bench": a.mode = .bench
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

**Edit `scripts/render-cats.swift`** — replace:

```swift
        case .ladder: sheet = ladder(a)
        case .stage: sheet = stage(a)
        }
        sheet.write(to: a.out)
        print("wrote \(a.out)")
    }








    // MARK: Stage panels: the big cats, the way the prototype shows them
```

with:

```swift
        case .ladder: sheet = ladder(a)
        case .stage: sheet = stage(a)
        case .states: sheet = states(a)
        case .bench: bench(); return
        }
        sheet.write(to: a.out)
        print("wrote \(a.out)")
    }

    // MARK: A cat on a fake clock

    final class Clock { var t = 0.0 }

    /// An engine on a fake clock and a seeded random source, so a sheet looks the same every time.
    @MainActor static func scene(_ preset: CatPreset, profile: String, D: Double, seed: UInt32 = 7, state: CatState = .idle, mini: Bool = false, quiet: Bool = false) -> (e: CatEngine, clock: Clock, step: () -> Void) {
        let clock = Clock(), rng = CatRNG(seed: seed)
        let e = CatEngine(preset, mini: mini, now: { clock.t }, rand: { rng.next() }, cfg: CatConfig(motion: profile), quiet: quiet, state: state)
        func place() { let L = CatGeometry.layout(preset, e.s, cx: 0, cy: 0, D: D); e.base = L.base; e.mouthPoint = L.mouth }
        place()
        return (e, clock, { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60); place() })
    }

    // MARK: States: every state in both motion styles

    @MainActor static func states(_ a: Args) -> Sheet {
        let cell = 190.0, labelW = 130.0, rows = a.cats.count * 2
        let sheet = Sheet(width: labelW + cell * Double(CatState.allCases.count) + 8, height: cell * Double(rows) + 28, scale: a.scale)
        let cg = sheet.cg
        for (ci, st) in CatState.allCases.enumerated() {
            CatDraw.text(cg, st.rawValue, x: labelW + (Double(ci) + 0.5) * cell, y: 14, size: 12, bold: true, color: CatDraw.white(0.8))
        }
        var row = 0
        for id in a.cats {
            for profile in ["playful", "classic"] {
                let top = 28 + Double(row) * cell
                CatDraw.text(cg, "\(CatPresets.byID(id).label) · \(profile)", x: 62, y: top + cell / 2, size: 12, bold: true, color: CatDraw.white(0.85))
                for (ci, st) in CatState.allCases.enumerated() {
                    let x = labelW + Double(ci) * cell
                    let (e, clock, step) = scene(CatPresets.byID(id), profile: profile, D: 110, state: st)
                    for _ in 0..<72 { step() }                       // 1.2 s into the state
                    cg.saveGState()
                    cg.clip(CatDraw.roundRect(x + 3, top + 3, cell - 6, cell - 6, 12))
                    cg.fill(CatDraw.roundRect(x, top, cell, cell, 0), CatDraw.black(1))
                    CatRenderer.draw(cg, e.look(time: clock.t / 1000), cx: x + cell / 2, cy: top + cell * 0.58, D: 110, CatDrawOptions(glow: true))
                    cg.restoreGState()
                }
                row += 1
            }
        }
        return sheet
    }





    // MARK: Frame time: twelve small cats plus the big one

    /// This thread's CPU time in seconds: a busy machine does not inflate it the way it inflates the wall clock.
    static func cpuNow() -> Double { Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9 }

    @MainActor static func bench() {
        let sheet = Sheet(width: 640, height: 220, scale: 2)
        let states = CatState.allCases
        let cats = (0..<12).map { i -> (CatEngine, Clock, () -> Void, Double, Double) in
            let id = CatPresets.ids[i % 4 == 0 ? 0 : (i % 4 == 1 ? 1 : (i % 4 == 2 ? 3 : 4))]
            let d = [12.0, 16, 20, 24][i % 4], (e, c, s) = scene(CatPresets.byID(id), profile: i % 2 == 0 ? "playful" : "classic", D: d, seed: UInt32(i + 1), state: states[i % states.count], mini: true)
            return (e, c, s, d, 60 + Double(i) * 34)
        }
        let big = scene(CatPresets.byID("shrimpy"), profile: "playful", D: 66, state: .working)
        var times: [Double] = []
        for f in 0..<600 {
            let start = cpuNow()
            sheet.cg.clear(CGRect(x: 0, y: 0, width: 640, height: 220))
            for i in cats.indices where f % 2 == 0 {                  // the small cats redraw at 30 fps, like MiniBotCanvasView
                cats[i].2()
                CatRenderer.draw(sheet.cg, cats[i].0.look(time: cats[i].1.t / 1000), cx: cats[i].4, cy: 30, D: cats[i].3, CatDrawOptions(badge: true))
            }
            big.step()
            CatRenderer.draw(sheet.cg, big.e.look(time: big.clock.t / 1000), cx: 320, cy: 130, D: 66, CatDrawOptions())
            if f >= 60 { times.append((cpuNow() - start) * 1000) }
        }
        times.sort()
        let avg = times.reduce(0, +) / Double(times.count)
        print(String(format: "12 small cats (30 fps) + the big one (60 fps), update and draw, CPU time: avg %.2f ms, p95 %.2f ms, max %.2f ms per frame (%d frames)", avg, times[Int(Double(times.count) * 0.95)], times.last!, times.count))
    }

    // MARK: Stage panels: the big cats, the way the prototype shows them
```

**Edit `scripts/render-cats.sh`** — replace:

```bash
trap 'rm -rf "$BUILD_DIR"' EXIT
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatRenderer.swift \
    scripts/render-cats.swift \
    -o "$BUILD_DIR/render-cats"
```

with:

```bash
trap 'rm -rf "$BUILD_DIR"' EXIT
APP=NotchBuddy/Sources/App
# RENDER_CATS_OPT=1 builds with -O (the frame-time number in a Release build); the default is a Debug build.
swiftc -swift-version 6 ${RENDER_CATS_OPT:+-O} \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    scripts/render-cats.swift \
    -o "$BUILD_DIR/render-cats"
```

- [ ] **Step 6: Render the states and compare them with the prototype**

Run: `bash scripts/render-cats.sh --states --cats shrimpy,momo --scale 1 --out "${TMPDIR:-/tmp}/a-mac-sheets/stage2-states.png"`
Expected: PASS

Make a montage of the prototype's states (Shrimpy on the top row, Momo underneath, after 1.2 s in each state, in Playful and then in Classic), with the same frozen clock as in Task 4:

```bash
cat > "$TMPDIR/a-mac-check/shots-states.js" <<EOF
async page => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.addInitScript(() => {
    let t = 0; const cbs = [];
    performance.now = () => t;
    window.requestAnimationFrame = cb => { cbs.push(cb); return cbs.length; };
    window.__step = (n, dt = 1000 / 60) => { for (let i = 0; i < n; i++) { t += dt; const q = cbs.splice(0); q.forEach(f => f(t)); } };
    Math.random = () => { const x = Math.sin(t * 12.9898 + 78.233) * 43758.5453; return x - Math.floor(x); };
  });
  await page.goto('file://$PWD/design/prototype/notchmeow.html');
  const states = ['idle','working','thinking','searching','approval','question','error','finished','ratelimit','sleeping','dizzy'];
  for (const style of ['playful','classic']) {
    await page.evaluate(s => { CFG.motion = s; reenter(); mx = null; }, style);
    const shots = {};
    for (const who of ['Shrimpy','Momo']) {
      shots[who] = [];
      for (const st of states) {
        await page.evaluate(st => { goState(st); mx = null; }, st);
        await page.evaluate(() => window.__step(72));
        shots[who].push(await page.evaluate((who) => {
          const cv = document.getElementById('cv'+who), W = cv.width, H = cv.height, D = Math.min(W*.4, H*.5) / (cv.width / cv.clientWidth);
          const out = document.createElement('canvas'); out.width = 190; out.height = 190; const c = out.getContext('2d');
          c.fillStyle = '#000'; c.fillRect(0,0,190,190);
          const side = D*1.7 * (cv.width/cv.clientWidth);
          c.drawImage(cv, W/2 - side/2, H*.57 - side*.58, side, side, 0, 0, 190, 190);
          return out.toDataURL('image/png');
        }, who));
      }
    }
    await page.evaluate(({shots}) => {
      let m = document.getElementById('montage'); if (m) m.remove();
      m = document.createElement('canvas'); m.id = 'montage'; m.width = 190*11; m.height = 190*2; m.style.display='block'; document.body.prepend(m);
      const c = m.getContext('2d'), imgs = [];
      for (const [ri, who] of ['Shrimpy','Momo'].entries()) shots[who].forEach((d, ci) => { const im = new Image(); im.src = d; imgs.push([im, ci, ri]); });
      return Promise.all(imgs.map(([im]) => new Promise(r => { im.onload = r; }))).then(() => { for (const [im, ci, ri] of imgs) c.drawImage(im, ci*190, ri*190); });
    }, {shots});
    await page.locator('#montage').screenshot({ path: '$TMPDIR/a-mac-check/proto-states-' + style + '.png' });
  }
}
EOF
cd "$TMPDIR/a-mac-check" && ~/.local/bin/playwright-cli -s=amac open about:blank && ~/.local/bin/playwright-cli -s=amac run-code --filename=shots-states.js && ~/.local/bin/playwright-cli -s=amac close; cd -
```

Open `stage2-states.png` next to `proto-states-playful.png` and `proto-states-classic.png`. The eyes, ears, tilt, badge and tint of each state should match (the random moments differ: a blink or an ear flick here and there). Look for: Thinking looks up to the side with the ear swivelled; Searching has wide eyes and radar ears; Error has flat eyes, airplane ears and a frown; Finished sparkles; Ratelimit pants; Sleeping has closed eyes; Dizzy has spirals. If a state differs in a way the fixtures did not catch, fix the renderer.

- [ ] **Step 7: Run the bench, in a Debug and an optimised build**

Run: `bash scripts/render-cats.sh --bench`
Expected: PASS

Run: `RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench`
Expected: PASS

Write both numbers down. On the dry run's machine (busy: load average 5 to 10) the bench printed about 2.7 ms on average (Debug) and 1.8 ms (optimised). The bench rasterises into a bitmap inside the timed region, which the app's `Canvas` may not, so it is a proxy; the real number is the in-app readout of Task 10. Small cats redraw at 30 fps (Task 8) and use the compact detail: that is what keeps the average near the 2 ms budget.

- [ ] **Step 8: Commit**

```bash
git add tests/CatRendererTests.swift scripts/test-cat-renderer.sh scripts/render-cats.swift scripts/render-cats.sh
git commit -m "feat(cat): the engine drives the renderer: the states sheet, a frame-time bench, and renderer tests over every state and emote

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The app draws the cats: the big cat, the small cats, the clock fix and the ear headroom (stage 2)

Agent: `nm-implementer-deep`. These are SwiftUI views: the proof is the build, the test programs and a read of the diff, not a unit test. Do not launch, quit, open or replace the installed NotchMeow app to check them.

**Files:**
- Create: `NotchBuddy/Sources/App/CatEngine+App.swift`
- Replace: `NotchBuddy/Sources/App/BotCanvasView.swift`
- Delete: `NotchBuddy/Sources/App/BotEngine.swift`
- Modify: `NotchBuddy/Sources/App/IslandRootView.swift` (comments only)
- Modify (regenerated): `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Tasks 1 to 7.
- Produces in `CatEngine+App.swift` (app target only): `CatEngine.live(_ preset: CatPreset = CatPresets.byID(CatConfig.shared.character), mini: Bool = false)` (the real clock, `CACurrentMediaTime() * 1000`, real dice, and `onSound` wired to `SoundEngine`), `setState(_ state: BotState, force: Bool = false)`, `triggerEmote(_ e: BotEmote)`, `setPermanentEmote(_:)`, and `typealias EyeShape = CatEye` (`AgentTask.miniEye` still uses the name until stage 7).
- Keeps, unchanged: `BotCanvasView(state:particleOverhang:)`, `MiniBotCanvasView(task:isDancing:)`, `cgColorFromHex`, `CGColor.from`, and every notification they observe (`.triggerEmote`, `.triggerSlap`, `.botBlink`, `.botSetTgEs`, `.botGulp`, `.botGreet`). `.botMorphTo` has no observer any more (the cat has no mailbox body); the places that post it are left alone for stage 7.
- What changes in behaviour: **the clock fix** (`dt` is `CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)`, on one clock on both sides, in the big and the small canvas); **ear headroom** (in the compact notch the canvas passes `earCeiling`, the distance from the cat's centre to the top of the island, so `CatRenderer` fits the ears under it, and the badge moves to the left); the cursor look now uses `CatGeometry.cursorLook` (tanh over 240 px across and 180 px up and down); small cats redraw at 30 fps; a third quick poke calls `onDizzy`, which posts `.botDizzy`, as before. The head is as wide as the bot's diameter (`size.width * 0.6`).

- [ ] **Step 1: Write the app's side of the engine**

**Create `NotchBuddy/Sources/App/CatEngine+App.swift`:**

```swift
import Foundation
import QuartzCore

// The app's way into the cat engine: the real clock, the app's own state and emote types, and the sounds. Nothing here is in the
// contract, and the test programs do not compile this file.

extension CatEngine {
    /// An engine for the app: it reads `CACurrentMediaTime()`, the clock the views use for `dt`, and rolls real dice.
    static func live(_ preset: CatPreset = CatPresets.byID(CatConfig.shared.character), mini: Bool = false) -> CatEngine {
        let e = CatEngine(preset, mini: mini, now: { CACurrentMediaTime() * 1000 })
        e.onSound = { SoundEngine.shared.play($0) }
        return e
    }

    func setState(_ state: BotState, force: Bool = false) {
        if let s = CatState(rawValue: state.rawValue) { setState(s, force: force) }
    }

    /// An emote asked for by the app (a hover, a drop, a finished chat). The triggers are unchanged from before the cats.
    func triggerEmote(_ e: BotEmote) { emote(e.rawValue) }

    /// A mini cat with a permanent emote: it plays the emote once. (Nothing sets one today; stage 7 removes it with `AgentTask.emote`.)
    func setPermanentEmote(_ e: BotEmote?) { if let e { emote(e.rawValue) } }
}

/// The old name of an eye shape, which `AgentTask.miniEye` still uses (stage 7 removes it).
typealias EyeShape = CatEye
```

- [ ] **Step 2: Replace the big and the small canvas, and delete the old engine**

`BotCanvasView.swift` keeps its two views and its helpers; only the engine, the drawing, the clock and the look change. The old `BotEngine.swift` goes.

**Replace `NotchBuddy/Sources/App/BotCanvasView.swift` with:**

```swift
import SwiftUI
import QuartzCore

/// SwiftUI wrapper: a TimelineView drives a Canvas that updates the cat engine and draws it with CatRenderer.
/// The main cat; `MiniBotCanvasView` below is the small one for agent pills.
struct BotCanvasView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat = 0

    // One engine per view instance (main cat)
    @StateObject private var engine = CatEngine.live()

    var body: some View {
        TimelineView(.animation(paused: state.mode == .hidden)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                // One clock on both sides of dt: CACurrentMediaTime() here and in the engine (the old code mixed it with the timeline's date).
                let dt = CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                let look = lookAt(state: state)
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
                let dancing: Bool = {
                    #if !APPSTORE
                    guard AppState.shared.musicPlaying else { return false }
                    guard AppState.shared.activeIntegrations.contains("integration_music") else { return false }
                    let allowed: Set<BotState> = [.idle, .working, .thinking, .searching, .finished]
                    guard allowed.contains(state.effectiveState) else { return false }
                    if state.mode == .compact { return true }
                    return state.mode == .expanded && state.view == .overview && state.focusId == "integration_music"
                    #else
                    return false
                    #endif
                }()
                engine.setDancing(dancing)
                engine.update(dt: dt)

                // The canvas is a square (the bot's diameter over 0.6) plus `particleOverhang` of room above for hearts; the head is as wide as the diameter.
                let D = Double(size.width) * 0.6
                let cx = Double(size.width) / 2, cy = Double(size.height) / 2 + Double(particleOverhang) / 2
                var options = CatDrawOptions()
                if state.mode == .compact {
                    options.badgeSide = -1                       // never under the camera housing
                    options.earCeiling = cy - Double(restingY(state: state))   // the top of the island is the top of the screen
                }
                let L = drawCat(context, engine, cx: cx, cy: cy, D: D, options)
                engine.base = L.base
                engine.mouthPoint = L.mouth
            }
        }
        .onChange(of: state.effectiveState) { _, newState in
            engine.setState(newState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerEmote)) { notif in
            if let emote = notif.object as? BotEmote {
                engine.triggerEmote(emote)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerSlap)) { _ in
            engine.slap()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botBlink)) { _ in
            engine.blink()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botSetTgEs)) { notif in
            if let v = notif.object as? CGFloat {
                engine.tgEs = Double(v)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGulp)) { _ in
            engine.gulp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in
            engine.greet()
        }
        .onAppear {
            engine.onDizzy = { NotificationCenter.default.post(name: .botDizzy, object: nil) }
            engine.setState(state.effectiveState, force: true)
        }
    }

    /// Where the island's resting strip puts the cat, in island coordinates.
    private func restingPlace(state: AppState) -> (islandW: CGFloat, botCx: CGFloat, botCy: CGFloat) {
        let (islandW, islandH) = islandSize(mode: state.mode, view: state.view,
                                             progress: state.uploadProgress,
                                             nw: state.notchWidth, nh: state.notchHeight)
        let actualH: CGFloat = (state.mode == .expanded && state.view == .prompt)
            ? min(300, 240 + CGFloat(state.chatHistory.count) * 40)
            : islandH
        let (botCx, botCy, _, _) = botPosition(mode: state.mode, view: state.view,
                                               islandW: islandW, islandH: actualH,
                                               uploadProgress: state.uploadProgress)
        return (islandW, botCx, botCy)
    }

    private func restingY(state: AppState) -> CGFloat { restingPlace(state: state).botCy }

    /// Where the pointer is, as a look: -1…1 across and up (tanh over 240 px across and 180 px up and down).
    private func lookAt(state: AppState) -> (x: Double, y: Double) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let p = restingPlace(state: state)
        // Island is centered on screen; bot is at botCx within island coords
        let botScreenX = screen.frame.midX - p.islandW / 2 + p.botCx
        // Island top = screen top → bot screen Y = botCy from island top
        return CatGeometry.cursorLook(dx: Double(state.mousePosition.x - botScreenX), dy: Double(state.mousePosition.y - p.botCy))
    }
}

/// Mini cat canvas (for agent pills and the compact grid)
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
        }())
    }

    var body: some View {
        // Small cats redraw 30 times a second: at Ø12 to Ø24 the difference cannot be seen, and a dozen of them are most of the frame time.
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                let dt = CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                engine.setDancing(isDancing)
                engine.update(dt: dt)
                let D = Double(size.width) * 0.6
                let L = drawCat(context, engine, cx: Double(size.width) / 2, cy: Double(size.height) / 2, D: D, CatDrawOptions(badge: false))
                engine.base = L.base
                engine.mouthPoint = L.mouth
            }
        }
        .onChange(of: task.state) { _, newState in
            engine.setState(newState)
        }
        .onAppear {
            engine.setState(task.state, force: true)
            if let emote = task.emote {
                engine.setPermanentEmote(emote)
            }
            // Direct eye override takes priority (e.g. .wide eyes for Research)
            if let eye = task.miniEye {
                engine.holdEye(eye)
            }
        }
    }
}

/// Draws a cat into a SwiftUI canvas context (with the Apple Music dance applied) and returns its layout.
@MainActor
private func drawCat(_ context: GraphicsContext, _ engine: CatEngine, cx: Double, cy: Double, D: Double, _ options: CatDrawOptions) -> CatGeometry.Layout {
    var laid: CatGeometry.Layout?
    let draw = {
        context.withCGContext { cg in
            if engine.dancingLevel > 0.001 {
                let R = D / 2
                CatEffects.applyDance(cg, level: engine.dancingLevel, seconds: CACurrentMediaTime(), pivotX: cx, pivotY: cy + D * 0.45, size: R)
            }
            laid = CatRenderer.draw(cg, engine.look(), cx: cx, cy: cy, D: D, options)
        }
    }
    draw()
    return laid!
}

// MARK: - CGColor from hex string

func cgColorFromHex(_ hex: String) -> CGColor? {
    let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard let val = UInt64(h, radix: 16) else { return nil }
    let r = CGFloat((val >> 16) & 0xFF) / 255
    let g = CGFloat((val >> 8)  & 0xFF) / 255
    let b = CGFloat( val        & 0xFF) / 255
    return CGColor(red: r, green: g, blue: b, alpha: 1)
}

extension CGColor {
    static func from(_ hex: String) -> CGColor {
        cgColorFromHex(hex) ?? CGColor(gray: 0.5, alpha: 1)
    }
}
```

```bash
git rm NotchBuddy/Sources/App/BotEngine.swift
```

- [ ] **Step 3: Update the two comments in `IslandRootView.swift` that describe the old engine and the mask**

The mask in `IslandContainer` cannot give the ears headroom (the top of the strip is the top of the screen); the comment says where that is handled now.

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`** — replace:

```swift
                // Keep idle animations inside the resting strip. Expanded views
                // retain the panel's full height for particles and hands.
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: islandWidth,
```

with:

```swift
                // Keep idle animations inside the resting strip. Expanded views
                // retain the panel's full height for particles and hands.
                // The top of the strip is the top of the screen, so this mask cannot give the cat's
                // ears any headroom: BotCanvasView fits them under that edge (CatDrawOptions.earCeiling).
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: islandWidth,
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`** — replace:

```swift
            }

            // Uploading: no particle overhang (no hearts during upload), positioned directly at cy.
            // BotEngine cy = H/2 + 0 + oy*R + R*0.06 ≈ H/2 (body centered in canvas).
            // With .position(x:y:) placing the frame center at (uploadCx, cy), bot is at cy ✓.
            //
            // Normal: extra 40pt canvas at top for heart particles; position offset up by 20pt;
            // BotEngine compensates with cy = H/2 + particleOverhang/2 + oy*R + R*0.06.
            if isUploading {
                TimelineView(.animation) { tl in
```

with:

```swift
            }

            // Uploading: no particle overhang (no hearts during upload), positioned directly at cy.
            // The cat is drawn at cy = H/2 (centred in the canvas).
            // With .position(x:y:) placing the frame center at (uploadCx, cy), bot is at cy ✓.
            //
            // Normal: extra 40pt canvas at top for heart particles; position offset up by 20pt;
            // BotCanvasView compensates by drawing the cat at cy = H/2 + particleOverhang/2.
            if isUploading {
                TimelineView(.animation) { tl in
```

- [ ] **Step 4: Regenerate the project and build**

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO`
Expected: PASS

If the build says `ambiguous use of 'dizzy'` (or any state name), a `.dizzy` is being read as both `BotState` and `CatState`: name the type (`CatState.dizzy`).

- [ ] **Step 5: Run every test program, old and new**

Run: `bash scripts/check-test-logs.sh && bash scripts/test-screen-geometry.sh && bash scripts/test-cat-presets.sh && bash scripts/test-cat-geometry.sh && bash scripts/test-cat-effects.sh && bash scripts/test-cat-renderer.sh && bash scripts/test-cat-personality.sh && bash scripts/test-cat-rules.sh && bash scripts/test-cat-engine.sh`
Expected: PASS

- [ ] **Step 6: Read the diff for what the build cannot say**

Check by reading: the `TimelineView` in `BotCanvasView` is still `.animation(paused: state.mode == .hidden)`; the engine has no timers (nothing in `CatEngine.swift` uses `DispatchQueue` or `Timer`); `engine.update` runs once per tick; the canvases read `timeline.date` only to redraw on every tick; `lookAt` computes the cat's screen position the way the old `lookX` and `lookY` did.

- [ ] **Step 7: Commit**

```bash
git add NotchBuddy/Sources/App/CatEngine+App.swift NotchBuddy/Sources/App/BotCanvasView.swift NotchBuddy/Sources/App/IslandRootView.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): the app draws Shrimpy: BotCanvasView and MiniBotCanvasView use CatEngine and CatRenderer, one clock for dt, ears fitted in the compact notch

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 9: The Debug-only cat panel: coat, size, motion style, state and the 11 states (stage 2)

Agent: `nm-implementer`. The model is test-first. The SwiftUI is proven by the build, by the binary checks of Steps 7 and 8 and by the offscreen render of Step 9: do not launch the installed NotchMeow app or a built one to check it.

The spec asks for a dev state panel in each app ("Debug-only on the Mac, `?dev` on Windows/Linux; the Mac is the primary app and never gets less"). This is the Mac's. It offers at least what the Windows `?dev` page offers (its States panel, its emote and personality panel, its still ladder, its poke, hairball, file-catch and greeting buttons, its draw-time readout): pick a coat, a size, a state, an emote, a personality and a motion style, and watch the cat live. This task builds the first half (coat, size, motion style, state, the eleven states, the ladder); Task 10 adds the draw-time line, Task 11 the emotes, the personality and the poke, Task 13 the greeting, Task 14 the file-catch buttons.

It is a window opened from the menu bar's menu, like Settings, in the same style: a title, `GroupBox`es, system pickers and buttons. Every cat in it is a real `CatEngine` drawn by the app's own `CatRenderer`, on a `CatConfig` of its own, so the app's cats and settings are never touched. It is compiled in Debug builds only, inside `#if DEBUG && !APPSTORE` (the App Store target defines `APPSTORE` and not `DEBUG` today; the second condition keeps the panel out if that ever changes). `scripts/check-app-binary.sh` proves it: a string marker, `NM_CAT_DEV_PANEL`, must be in a Debug build (`debug`) and in no Release build (`release`) and no App Store build (`appstore`).

**Files:**
- Create: `tests/CatDevModelTests.swift`, `scripts/test-cat-devpanel.sh`
- Create: `NotchBuddy/Sources/App/CatDevModel.swift`, `NotchBuddy/Sources/App/CatDevPanel.swift`
- Create: `scripts/render-cat-panel.swift`, `scripts/render-cat-panel.sh`
- Modify: `NotchBuddy/Sources/App/AppDelegate.swift` (a menu item and a window, inside `#if DEBUG && !APPSTORE`)
- Replace: `scripts/check-app-binary.sh`
- Modify (regenerated): `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CatEngine`, `CatConfig`, `CatState`, `CatProfiles.named(_:)` (Task 6); `CatPresets` (Task 1); `CatRenderer.draw`, `CatDrawOptions`, `CatDraw` (Tasks 3 and 4); `CatGeometry.cursorLook` and `CatEngine.frameDelta` (Tasks 2 and 6); `FakeClock` (`tests/CatEngineSupport.swift`).
- Produces `CatDevModel` (`@MainActor`, `ObservableObject`, in `#if DEBUG && !APPSTORE`): `static let marker` (`"NM_CAT_DEV_PANEL"`), `static let sizes` (Ø12, 16, 20, 24, 28, 44, 66, 120, 180), `cfg` (its own `CatConfig`), `init(now:rand:)` (the engines' clock in ms, which must be the clock the views use for `dt`; real dice by default), published `coat`, `kitten`, `size`, `motion`, `state`, `tint`, `stage` (the big live `CatEngine`) and `strip` (eleven small ones, one per `CatState` in the contract's order), `preset`, and `pick(coat:)` (an unknown ID is Shrimpy), `pick(kitten:)`, `pick(size:)` (a size it does not offer is Ø66), `pick(motion:)` (anything but `"playful"` and `"classic"` is Playful) and `pick(state:)` (moves the stage cat only).
- Produces `CatDevView` (the window's root: a title and a scrolling `CatDevContent`) and `CatDevContent(model:pointer:)` (the sections: Cat, Live cat, The 11 states, Every coat at every size). The cats look at the pointer; a click on a cat pokes it.
- Produces `scripts/render-cat-panel.sh [--out FILE] [--height 2200]`: the panel's own view drawn into a PNG, offscreen, without launching NotchMeow.
- Produces `scripts/check-app-binary.sh APP [release|appstore|debug]`.

- [ ] **Step 1: Write the failing test**

The test drives the model on a fake clock: every coat as a cat and as a kitten, an unknown coat, size and motion style, the stage cat against the strip, the app's own settings left alone, and ten seconds of engine time.

**Create `tests/CatDevModelTests.swift`:**

```swift
import Foundation

@main
enum CatDevModelTests {
    @MainActor static func main() {
        let clock = FakeClock(), rng = CatRNG(seed: 2)
        func model() -> CatDevModel { CatDevModel(now: { clock.t }, rand: { rng.next() }) }

        CT.section("the panel starts on Shrimpy, big, Playful and idle")
        let m = model()
        CT.check("coat", m.coat, "shrimpy"); CT.check("not a kitten", m.kitten, false); CT.check("size", m.size, 66)
        CT.check("motion style", m.motion, "playful"); CT.check("state", m.state, CatState.idle)
        CT.check("the stage cat is Shrimpy", m.stage.p.name, "shrimpy")
        CT.check("eleven small cats, one per state, in the contract's order", m.strip.map(\.state), CatState.allCases)
        CT.check("the marker the binary check looks for", CatDevModel.marker, "NM_CAT_DEV_PANEL")

        CT.section("every coat, as a cat and as a kitten, builds a stage cat and eleven small cats")
        for id in CatPresets.ids {
            for k in [false, true] {
                m.pick(coat: id); m.pick(kitten: k)
                CT.checkTrue("\(id)\(k ? " kitten" : ""): the stage cat and all eleven small ones wear it",
                             m.stage.p.name == id && m.stage.p.kitten == (k ? true : nil) && m.strip.count == 11 && m.strip.allSatisfy { $0.p.name == id && ($0.p.kitten ?? false) == k })
            }
        }
        m.pick(kitten: false)

        CT.section("an unknown coat is Shrimpy and an unknown size is Ø66")
        for bad in ["", "SHRIMPY", "siamese", "💥"] { m.pick(coat: bad); CT.check("\"\(bad)\" is Shrimpy", m.coat, "shrimpy") }
        m.pick(size: 12); CT.check("Ø12 is offered", m.size, 12)
        m.pick(size: 13); CT.check("Ø13 is not: Ø66", m.size, 66)
        CT.check("the sizes run from the mini pill to a close look", [CatDevModel.sizes.first!, CatDevModel.sizes.last!], [12, 180])

        CT.section("a state moves the stage cat only")
        m.pick(state: .approval)
        CT.check("the stage cat is in approval", m.stage.state, CatState.approval)
        CT.check("the small cats stay in their own states", m.strip.map(\.state), CatState.allCases)
        m.pick(coat: "momo")
        CT.check("a new coat keeps the chosen state", m.stage.state, CatState.approval)

        CT.section("a motion style applies to every engine, and an unknown one plays Playful")
        m.pick(motion: "classic")
        CT.checkTrue("the stage cat and the eleven small ones play Classic", ([m.stage] + m.strip).allSatisfy { $0.motion == "classic" })
        m.pick(motion: "nonsense")
        CT.check("an unknown style is Playful", m.motion, "playful")
        CT.checkTrue("and every engine follows", ([m.stage] + m.strip).allSatisfy { $0.motion == "playful" })

        CT.section("the panel never touches the app's own settings")
        CT.check("the shared style is as it was", CatConfig.shared.motion, "playful")
        CT.checkTrue("and it holds no override and no personality", CatConfig.shared.override.isEmpty && CatConfig.shared.pers.isEmpty)
        m.pick(motion: "classic")
        CT.check("even after the panel chose Classic", CatConfig.shared.motion, "playful")

        CT.section("the engines run: every pose stays finite after ten seconds")
        for e in [m.stage] + m.strip { for _ in 0..<(60 * 10) { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60) } }
        CT.checkTrue("twelve cats, all finite", ([m.stage] + m.strip).allSatisfy { e in PoseKey.allCases.allSatisfy { e.s[$0].isFinite } })
        CT.finish()
    }
}
```

**Create `scripts/test-cat-devpanel.sh`:**

```bash
#!/usr/bin/env bash
# The Debug-only cat panel's model: which cat, size, motion style and state it shows, and the engines it builds. It compiles the model with
# -D DEBUG, the way a Debug build does (a Release build has no panel: scripts/check-app-binary.sh proves it).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-devpanel.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -D DEBUG \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatDevModel.swift \
    tests/CatTestSupport.swift tests/CatEngineSupport.swift tests/CatDevModelTests.swift \
    -o "$TEST_DIR/cat-devpanel-tests"
"$TEST_DIR/cat-devpanel-tests"
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-devpanel.sh`
Expected: FAIL (swiftc cannot open `NotchBuddy/Sources/App/CatDevModel.swift`)

- [ ] **Step 3: Write the model**

**Create `NotchBuddy/Sources/App/CatDevModel.swift`:**

```swift
import Combine
import Foundation
import QuartzCore

#if DEBUG && !APPSTORE

/// What the Debug-only cat panel shows and does, with no SwiftUI in it: which cat, at what size, in which motion style, and the engines
/// it draws (one big live cat and eleven small ones, one per state). The panel (CatDevPanel.swift) draws them; tests/CatDevModelTests.swift
/// drives it. Debug builds only: `scripts/check-app-binary.sh` proves that a Release build and an App Store build do not contain it.
@MainActor
final class CatDevModel: ObservableObject {
    /// `scripts/check-app-binary.sh` looks for this string in a built app: it is in a Debug build and in no other.
    static let marker = "NM_CAT_DEV_PANEL"
    /// The head widths the panel offers: the app's own sizes, from the mini pills (Ø12) to the expanded island (Ø66), and two for a closer look.
    static let sizes: [Double] = [12, 16, 20, 24, 28, 44, 66, 120, 180]

    /// The panel's own settings. The app's cats (`CatConfig.shared`) are never touched.
    let cfg: CatConfig
    let now: () -> Double
    let rand: () -> Double

    @Published private(set) var coat = "shrimpy"
    @Published private(set) var kitten = false
    @Published private(set) var size = 66.0
    @Published private(set) var motion = "playful"
    @Published private(set) var state = CatState.idle
    @Published var tint = true
    /// The big live cat, and the eleven small ones, one per state in the contract's order.
    @Published private(set) var stage: CatEngine
    @Published private(set) var strip: [CatEngine] = []

    /// `now` is the engines' clock in ms and must be the same clock the views use for `dt` (CACurrentMediaTime): one clock on both sides.
    init(now: @escaping () -> Double = { CACurrentMediaTime() * 1000 }, rand: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        let cfg = CatConfig()
        self.cfg = cfg; self.now = now; self.rand = rand
        stage = CatEngine(CatPresets.byID("shrimpy"), now: now, rand: rand, cfg: cfg)
        rebuild()
    }

    /// The coat, as a cat or as its kitten.
    var preset: CatPreset {
        let p = CatPresets.byID(coat)
        return kitten ? CatPresets.kitten(of: p) : p
    }

    /// A coat the panel does not know is Shrimpy, like a stored ID the app does not know.
    func pick(coat id: String) { coat = CatPresets.byID(id).name; rebuild() }
    func pick(kitten on: Bool) { kitten = on; rebuild() }
    /// A size the panel does not offer is Ø66, the expanded island's cat.
    func pick(size d: Double) { size = Self.sizes.contains(d) ? d : 66 }
    /// "playful" or "classic"; anything else plays Playful, like a stored style the app does not know.
    func pick(motion style: String) { motion = CatProfiles.named(style) != nil ? style : "playful"; cfg.motion = motion; rebuild() }
    /// The stage cat moves into a state (the eleven small cats each stay in their own).
    func pick(state st: CatState) { state = st; stage.setState(st) }

    /// New engines for the chosen coat, kitten and motion style: the stage cat in the chosen state, and one small cat per state.
    private func rebuild() {
        let p = preset
        stage = make(p, state: state)
        strip = CatState.allCases.map { make(p, state: $0) }
    }

    private func make(_ p: CatPreset, state: CatState) -> CatEngine {
        CatEngine(p, now: now, rand: rand, cfg: cfg, quiet: false, state: state)
    }
}

#endif
```

- [ ] **Step 4: Run the test**

Run: `bash scripts/test-cat-devpanel.sh`
Expected: PASS

- [ ] **Step 5: Write the panel and open it from the menu bar in Debug builds**

`CatDevCell` is one live cat the way the app draws its own (`BotCanvasView`): the engine is updated once per frame from one clock (`CACurrentMediaTime()` on both sides of `dt`), then `CatRenderer` draws it, and the engine gets its `base` and `mouthPoint` back from the layout. The cat looks at the pointer through `CatGeometry.cursorLook` (tanh over 240 px across and 180 px up and down); the ladder redraws when the pointer moves, not every frame. `CatDevContent` is its own view so that `render-cat-panel.sh` can draw it.

**Create `NotchBuddy/Sources/App/CatDevPanel.swift`:**

```swift
import SwiftUI
import QuartzCore

#if DEBUG && !APPSTORE

/// The Debug-only cat panel: pick a coat, a size, a motion style and a state, and watch the cat live next to the eleven states and every coat.
/// It is a window opened from the menu bar (AppDelegate), built from the same pieces as Settings (a title, group boxes, system pickers and
/// buttons). Every cat here is a real `CatEngine` drawn by the app's own `CatRenderer`, on its own `CatConfig`: the app's cats are untouched.
/// Compiled in Debug builds only; `scripts/check-app-binary.sh` proves a Release build and an App Store build do not contain it.
struct CatDevView: View {
    @StateObject private var model = CatDevModel()
    /// Where the pointer is, in the content's coordinate space (nil off the content): the cats look at it.
    @State private var pointer: CGPoint?
    static let space = "catpanel"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cats")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 4)
            Text("Debug builds only. Every cat here is a real engine drawn by the app's own renderer, on its own settings: the app's cats are never touched.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            ScrollView {
                CatDevContent(model: model, pointer: pointer)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .coordinateSpace(name: Self.space)
                    .onContinuousHover(coordinateSpace: .named(Self.space)) { phase in
                        switch phase {
                        case .active(let p): pointer = p
                        case .ended: pointer = nil
                        }
                    }
            }
        }
    }
}

/// The panel's sections. `scripts/render-cat-panel.sh` draws this view to a PNG without launching the app (a ScrollView does not render there).
struct CatDevContent: View {
    @ObservedObject var model: CatDevModel
    let pointer: CGPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            chooser
            liveCat
            statesStrip
            ladder
        }
    }

    // MARK: Choosing

    private var chooser: some View {
        GroupBox("Cat") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Coat", selection: Binding(get: { model.coat }, set: { model.pick(coat: $0) })) {
                    ForEach(CatPresets.ids, id: \.self) { Text(CatPresets.byID($0).label).tag($0) }
                }
                Picker("Size", selection: Binding(get: { model.size }, set: { model.pick(size: $0) })) {
                    ForEach(CatDevModel.sizes, id: \.self) { Text("Ø\(Int($0))").tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Motion", selection: Binding(get: { model.motion }, set: { model.pick(motion: $0) })) {
                    Text("Playful").tag("playful")
                    Text("Classic").tag("classic")
                }
                .pickerStyle(.segmented)
                Toggle("Kitten", isOn: Binding(get: { model.kitten }, set: { model.pick(kitten: $0) }))
                Toggle("State tint on the lower head", isOn: $model.tint)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: The live cat

    private var liveCat: some View {
        GroupBox("Live cat") {
            VStack(alignment: .leading, spacing: 10) {
                CatDevCell(engine: model.stage, D: model.size, width: 360, height: 280, pointer: pointer, tint: model.tint)
                Text("State")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                ChoiceGrid(items: CatState.allCases.map { ($0.rawValue, $0.rawValue) }, selected: model.state.rawValue) {
                    if let st = CatState(rawValue: $0) { model.pick(state: st) }
                }
            }
            .padding(8)
        }
    }

    // MARK: The eleven states

    private var statesStrip: some View {
        GroupBox("The 11 states") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(Array(model.strip.enumerated()), id: \.offset) { _, e in
                    VStack(spacing: 4) {
                        CatDevCell(engine: e, D: 56, width: 120, height: 130, pointer: pointer, tint: model.tint)
                        Text(e.state.rawValue)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: Every coat

    private var ladder: some View {
        GroupBox("Every coat, at every size") {
            ScrollView(.horizontal) {
                CatDevLadder(pointer: pointer, tint: model.tint)
            }
            .padding(8)
        }
    }
}

/// A group of buttons of which one is on.
private struct ChoiceGrid: View {
    let items: [(id: String, label: String)]
    let selected: String?
    let pick: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.id) { item in
                Button(item.label) { pick(item.id) }
                    .buttonStyle(.bordered)
                    .tint(item.id == selected ? .accentColor : nil)
            }
        }
    }
}

/// One live cat on a black card, drawn the way the app draws its own: the engine is updated once per frame from one clock
/// (CACurrentMediaTime on both sides of dt), then `CatRenderer` draws it. The cat looks at the pointer; a click pokes it.
private struct CatDevCell: View {
    let engine: CatEngine
    let D: Double
    let width: Double, height: Double
    let pointer: CGPoint?
    var tint = true

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .named(CatDevView.space)).origin
            let cx = width / 2, cy = height * 0.56
            let gaze = pointer.map { CatGeometry.cursorLook(dx: Double($0.x - origin.x) - cx, dy: Double($0.y - origin.y) - cy) } ?? (x: 0.0, y: 0.0)
            TimelineView(.animation) { timeline in
                Canvas { context, _ in
                    _ = timeline.date   // the Canvas redraws on every tick of the timeline
                    engine.lookX = gaze.x
                    engine.lookY = gaze.y
                    engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                    context.withCGContext { cg in
                        let L = CatRenderer.draw(cg, engine.look(), cx: cx, cy: cy, D: D, CatDrawOptions(tint: tint, glow: true))
                        engine.base = L.base
                        engine.mouthPoint = L.mouth
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { engine.slap() }
    }
}

/// Every coat at Ø12 to Ø66 and as a kitten at Ø16 and Ø40: the ladder of the prototype page and of `render-cats.sh`, still cats that turn
/// to look at the pointer through the face warp (redrawn when the pointer moves, not every frame).
private struct CatDevLadder: View {
    let pointer: CGPoint?
    let tint: Bool

    private static let cells: [(d: Double, label: String, kitten: Bool)] = [
        (12, "Ø12 mini", false), (16, "Ø16", false), (20, "Ø20 compact", false), (24, "Ø24", false), (28, "Ø28 full", false),
        (44, "Ø44", false), (66, "Ø66 expanded", false), (16, "kitten Ø16", true), (40, "kitten Ø40", true),
    ]
    private static func slotW(_ d: Double) -> Double { max(62, d * 2.2) }
    private static let rowH = 150.0
    private static let labelW = 130.0
    private static var width: Double { labelW + cells.map { slotW($0.d) }.reduce(0, +) + 12 }

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .named(CatDevView.space)).origin
            Canvas { context, _ in
                context.withCGContext { cg in
                    for (ri, id) in CatPresets.ids.enumerated() {
                        let top = Double(ri) * Self.rowH, base = CatPresets.byID(id)
                        CatDraw.text(cg, base.label, x: 12, y: top + Self.rowH / 2 - 6, size: 12, bold: true, color: CatDraw.white(0.9), anchor: .left)
                        CatDraw.text(cg, base.desc ?? id, x: 12, y: top + Self.rowH / 2 + 10, size: 10, bold: false, color: CatDraw.white(0.5), anchor: .left)
                        var x = Self.labelW
                        for c in Self.cells {
                            let w = Self.slotW(c.d), cx = x + w / 2, cy = top + 20 + Self.rowH * 0.42
                            cg.fill(CatDraw.roundRect(x + 4, top + 22, w - 8, Self.rowH - 46, 10), CatDraw.black(1))
                            var pose = CatPose()
                            if let p = pointer {
                                let g = CatGeometry.cursorLook(dx: Double(p.x - origin.x) - cx, dy: Double(p.y - origin.y) - cy)
                                pose.yaw = g.x * 0.62; pose.pitch = g.y * 0.5
                            }
                            CatRenderer.draw(cg, CatLook(preset: c.kitten ? CatPresets.kitten(of: base) : base, pose: pose), cx: cx, cy: cy, D: c.d, CatDrawOptions(tint: tint))
                            CatDraw.text(cg, c.label, x: cx, y: top + Self.rowH - 10, size: 10, bold: false, color: CatDraw.white(0.55))
                            x += w
                        }
                    }
                }
            }
            .frame(width: Self.width, height: Self.rowH * Double(CatPresets.ids.count))
        }
        .frame(width: Self.width, height: Self.rowH * Double(CatPresets.ids.count))
        .background(Color(red: 0.059, green: 0.063, blue: 0.071))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#endif
```

`openCatPanel` opens it as Settings opens its window (the island folds away first, and the window sits below it).

**Edit `NotchBuddy/Sources/App/AppDelegate.swift`** — replace:

```swift
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
```

with:

```swift
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        #if DEBUG && !APPSTORE
        menu.addItem(withTitle: "Cats (Debug)…", action: #selector(openCatPanel), keyEquivalent: "")
        #endif
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
```

**Edit `NotchBuddy/Sources/App/AppDelegate.swift`** — replace:

```swift
    /// Centres the window horizontally and keeps its title bar clear of the island panel
```

with:

```swift
    #if DEBUG && !APPSTORE
    private var catPanelWindow: NSWindow?

    /// Debug builds only: the cat panel (coat, size, motion style and state, live). A window like Settings, compiled out of Release and
    /// App Store builds; scripts/check-app-binary.sh proves it.
    @objc private func openCatPanel() {
        if AppState.shared.mode == .expanded { islandController?.collapse() }
        if let w = catPanelWindow, w.isVisible {
            placeBelowIsland(w)
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Cats — NotchMeow (Debug)"
        win.identifier = NSUserInterfaceItemIdentifier(CatDevModel.marker)
        let host = NSHostingView(rootView: CatDevView())
        host.sizingOptions = [.minSize]
        win.contentView = host
        win.contentMinSize = NSSize(width: 700, height: 480)
        win.isReleasedWhenClosed = false
        placeBelowIsland(win)
        catPanelWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    #endif

    /// Centres the window horizontally and keeps its title bar clear of the island panel
```

- [ ] **Step 6: Teach the binary check about the panel**

The checks that already exist stay as they are. The new ones look for the marker in the binary's strings (a Debug build keeps the code in `NotchMeow.debug.dylib`, which the script already globs).

**Replace `scripts/check-app-binary.sh` with:**

```bash
#!/usr/bin/env bash
# Checks a built NotchMeow.app: FoundationModels weak-linked (the app must launch on macOS 15),
# and, for Release builds, the Debug-only AI base-URL override compiled out.
# `release` is the CI check: it also fails when FoundationModels isn't linked at all, which means the
# SDK had none and the Apple on-device provider was silently compiled out. It also fails when the Debug-only
# cat panel (CatDevPanel.swift, marked NM_CAT_DEV_PANEL) is in the binary.
# `appstore` is for a build of the App Store target, even in its Debug configuration: no cat panel either.
# `debug` is the other half of that proof: a Debug build must contain the cat panel, so the checks above can fail.
# Usage: bash scripts/check-app-binary.sh path/to/NotchMeow.app [release|appstore|debug]
set -euo pipefail
APP="$1"
BINS=("$APP"/Contents/MacOS/NotchMeow*)   # Debug builds put the code in NotchMeow.debug.dylib
[ -e "${BINS[0]}" ] || { echo "No binary in $APP/Contents/MacOS" >&2; exit 1; }
weak=0
panel=0
for BIN in "${BINS[@]}"; do
    if grep -q FoundationModels < <(otool -l "$BIN" | grep -A2 'LC_LOAD_DYLIB$'); then
        echo "✗ $(basename "$BIN") links FoundationModels strongly: NotchMeow would not launch on macOS 15" >&2
        exit 1
    fi
    if grep -q FoundationModels < <(otool -l "$BIN" | grep -A2 'LC_LOAD_WEAK_DYLIB'); then weak=1; fi
    if [ "${2:-}" = "release" ] && grep -q NM_AI_BASE_URL_OVERRIDE < <(strings "$BIN"); then
        echo "✗ $(basename "$BIN") still reads NM_AI_BASE_URL_OVERRIDE" >&2
        exit 1
    fi
    if grep -q NM_CAT_DEV_PANEL < <(strings "$BIN"); then panel=1; fi
done
case "${2:-}" in
    release|appstore)
        [ "$panel" = 0 ] || { echo "✗ the Debug-only cat panel (NM_CAT_DEV_PANEL) is in this build" >&2; exit 1; }
        echo "✓ No cat panel in this build" ;;
    debug)
        [ "$panel" = 1 ] || { echo "✗ the cat panel (NM_CAT_DEV_PANEL) is missing from this Debug build" >&2; exit 1; }
        echo "✓ The cat panel is in this Debug build" ;;
esac
if [ "$weak" = 1 ]; then
    echo "✓ FoundationModels is weak-linked"
elif [ "${2:-}" = "release" ]; then
    echo "✗ FoundationModels is not linked at all: the Apple on-device provider was compiled out. Build with Xcode 26 or later (scripts/check-sdk.sh)." >&2
    exit 1
else
    echo "· FoundationModels not linked (this SDK has none: Apple on-device is compiled out)"
fi
[ "${2:-}" = "release" ] && echo "✓ No AI base-URL override in this Release build"
exit 0
```

- [ ] **Step 7: Build the Debug app, and see the panel in it**

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO`
Expected: PASS

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Debug/NotchMeow.app debug`
Expected: PASS

- [ ] **Step 8: Prove that a Release build and an App Store build do not contain it**

The Release build needs `CODE_SIGNING_ALLOWED=NO` (there is no signing identity on a build machine). The App Store target gets its own folder inside `NotchBuddy/build/`, which git ignores.

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
Expected: PASS

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Release/NotchMeow.app release`
Expected: PASS

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO`
Expected: PASS

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/store/Build/Products/Debug/NotchMeow.app appstore`
Expected: PASS

Prove that these checks can fail. The Release build has no panel, so asking it to contain one must fail; the Debug build has one, so asking it to have none must fail:

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Release/NotchMeow.app debug`
Expected: FAIL (the cat panel is missing from this Debug build)

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Debug/NotchMeow.app appstore`
Expected: FAIL (the Debug-only cat panel is in this build)

- [ ] **Step 9: Look at the panel without launching the app**

`render-cat-panel.sh` puts the panel's own view into a window that is never shown and draws it into a bitmap. The cats are live engines, run for 1.5 s first.

**Create `scripts/render-cat-panel.swift`:**

```swift
import AppKit
import SwiftUI

// Draws the Debug-only cat panel (CatDevPanel.swift) into a PNG without launching NotchMeow: the panel's own SwiftUI view goes into a window
// that is never shown, and AppKit lays it out and draws it into a bitmap. The cats are live engines, stepped for 1.5 s before the shot.
// The system controls (pickers, buttons, group boxes) may come out blank in this offscreen bitmap; the cats and the layout do not.
// Run it through scripts/render-cat-panel.sh:  bash scripts/render-cat-panel.sh [--out panel.png] [--height 2200]

@main
struct RenderCatPanel {
    @MainActor static func main() {
        var out = "cat-panel.png", height = 2200.0
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? out
            case "--height": height = Double(it.next() ?? "") ?? height
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        _ = NSApplication.shared
        let host = NSHostingView(rootView: CatDevView())
        host.frame = NSRect(x: 0, y: 0, width: 980, height: height)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = .windowBackgroundColor
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))   // SwiftUI lays out, and the engines run for a moment
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

**Create `scripts/render-cat-panel.sh`:**

```bash
#!/usr/bin/env bash
# Draws the Debug-only cat panel into a PNG without launching NotchMeow (see scripts/render-cat-panel.swift).
#   bash scripts/render-cat-panel.sh --out panel.png [--height 2200]
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-panel.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -D DEBUG \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatDevModel.swift $APP/CatDevPanel.swift \
    scripts/render-cat-panel.swift \
    -o "$BUILD_DIR/render-cat-panel"
"$BUILD_DIR/render-cat-panel" "$@"
```

Run: `mkdir -p "${TMPDIR:-/tmp}/a-mac-sheets" && bash scripts/render-cat-panel.sh --out "${TMPDIR:-/tmp}/a-mac-sheets/stage2-panel.png" --height 1700`
Expected: PASS

Open `stage2-panel.png`. The Cat box has the coat menu, the Ø12 to Ø180 sizes, Playful and Classic, and the kitten and tint toggles. Under it the live cat on a black card and the eleven state buttons, then the eleven small cats (each in its own state: the dots badge of working, thinking and searching, the amber `!` of approval, the cyan `?` of question, the sleeping `z`, the dizzy spirals), then the ladder of every coat at Ø12 to Ø66 and as kittens. The system controls may be blank in some macOS versions' offscreen bitmaps; the cats and the layout are what to check.

- [ ] **Step 10: Commit**

```bash
git add tests/CatDevModelTests.swift scripts/test-cat-devpanel.sh scripts/render-cat-panel.swift scripts/render-cat-panel.sh scripts/check-app-binary.sh NotchBuddy/Sources/App/CatDevModel.swift NotchBuddy/Sources/App/CatDevPanel.swift NotchBuddy/Sources/App/AppDelegate.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): a Debug-only cat panel (coat, size, motion style, state, the eleven states, every coat), and a binary check that keeps it out of Release and App Store builds

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Emotes and the mouth on the sheet, and the Debug frame-time readout (stage 3)

Agent: `nm-implementer-light`.

**Files:**
- Create: `tests/CatFrameMeterTests.swift`, `scripts/test-cat-frame-meter.sh`
- Create: `NotchBuddy/Sources/App/CatFrameMeter.swift`, `NotchBuddy/Sources/App/CatFrameReadout.swift`
- Modify: `NotchBuddy/Sources/App/BotCanvasView.swift`, `NotchBuddy/Sources/App/CatDevPanel.swift`, `scripts/render-cat-panel.sh`, `scripts/render-cats.swift`
- Modify (regenerated): `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CatEngine.emote(_:)`, `CatRenderer.draw`, the pose's six mouth values (Tasks 4 and 6); `CatDevView`, `CatDevCell` and `render-cat-panel.sh` (Task 9).
- Produces `catFrameBudgetMs` (2.0) and `struct CatFrameMeter` (`record(start:duration:)`, `frames`, `summary()`, `readout() -> (line, overBudget)?`): draws that start within 6 ms of the first draw of a group are one frame, and a frame's time is the sum of its draws. In `#if DEBUG` only: `CatFrameReadout.shared.measure(_ draw: () -> Void)`, which times a draw and every two seconds appends a line such as `cat frame: avg 0.85 ms, p95 1.20 ms, max 2.10 ms, up to 13 cats` to `~/Library/Logs/NotchMeow/cat-frames.log` (a separate file, so `nm.log` stays as it is). `CatFrameReadout.shared.latest` is that last line, for the cat panel, which times its own cats the same way and shows it (the Windows `?dev` page shows its draw time too).
- Produces `render-cats.sh --emotes [--cats id,id]` (every emote at its peak, both styles) and `--mouths [--cats id,id]` (closed, smile, frown, skew, blep, wavy, meow, yawn, 'o', hiss).

- [ ] **Step 1: Write the failing test**

**Create `tests/CatFrameMeterTests.swift`:**

```swift
import Foundation

@main
enum CatFrameMeterTests {
    @MainActor static func main() {
        CT.section("draws that come together are one frame")
        var m = CatFrameMeter()
        CT.check("nothing to report before a frame closes", m.summary() == nil, true)
        // Frame 1: thirteen draws, 0.1 ms each, starting within 2 ms of each other. Frame 2 starts 16 ms later.
        for f in 0..<3 {
            let t0 = Double(f) * 0.016
            for i in 0..<13 { m.record(start: t0 + Double(i) * 0.00015, duration: 0.0001) }
        }
        CT.check("two frames have closed (the third is still open)", m.frames.count, 2)
        CT.check("each frame holds thirteen cats", m.frames.map(\.cats), [13, 13])
        CT.checkNear("and adds their times: 13 x 0.1 ms", m.frames[0].ms, 1.3)
        let s = m.summary()!
        CT.checkNear("average", s.avgMs, 1.3); CT.checkNear("worst", s.maxMs, 1.3); CT.check("most cats in a frame", s.cats, 13)

        CT.section("the budget")
        CT.checkTrue("1.3 ms is within the 2 ms budget", m.readout()!.overBudget == false)
        var slow = CatFrameMeter()
        for f in 0..<5 { slow.record(start: Double(f) * 0.016, duration: 0.0031) }
        CT.checkTrue("3.1 ms a frame is over it, and the line says so", slow.readout()!.overBudget && slow.readout()!.line.contains("OVER"))
        CT.check("the budget is 2 ms", catFrameBudgetMs, 2.0)

        CT.section("old frames fall off")
        var long = CatFrameMeter()
        long.keep = 10
        for f in 0..<50 { long.record(start: Double(f) * 0.016, duration: 0.001) }
        CT.check("only the last ten frames are kept", long.frames.count, 10)
        CT.finish()
    }
}
```

**Create `scripts/test-cat-frame-meter.sh`:**

```bash
#!/usr/bin/env bash
# The frame-time meter behind the Debug-only readout: draws that start together add up to one frame, against a 2 ms budget.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-meter.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/CatFrameMeter.swift \
    tests/CatTestSupport.swift tests/CatFrameMeterTests.swift \
    -o "$TEST_DIR/cat-meter-tests"
"$TEST_DIR/cat-meter-tests"
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-frame-meter.sh`
Expected: FAIL (swiftc cannot open `NotchBuddy/Sources/App/CatFrameMeter.swift`)

- [ ] **Step 3: Write the meter and the readout**

**Create `NotchBuddy/Sources/App/CatFrameMeter.swift`:**

```swift
import Foundation

/// The frame-time budget of the cats: twelve small cats plus the big one stay under this many milliseconds of drawing per frame.
let catFrameBudgetMs = 2.0

/// Adds up the time every cat draw takes, frame by frame. The views time each draw and report it here (in Debug builds only); the
/// draws of one display frame come one after the other within a few milliseconds, so a draw that starts within `window` seconds of
/// the first draw of a group belongs to that frame.
struct CatFrameMeter {
    /// One finished frame: how long all its cats took to draw, and how many cats there were.
    struct Frame: Equatable { var ms: Double; var cats: Int }

    var window = 0.006
    /// The last `keep` frames, oldest first.
    private(set) var frames: [Frame] = []
    var keep = 240
    private var groupStart: Double?
    private var groupMs = 0.0
    private var groupCats = 0

    /// A draw that started at `start` (seconds, any steady clock) and took `duration` seconds.
    mutating func record(start: Double, duration: Double) {
        if let g = groupStart, start - g > window { closeGroup() }
        if groupStart == nil { groupStart = start }
        groupMs += duration * 1000
        groupCats += 1
    }

    private mutating func closeGroup() {
        guard groupStart != nil else { return }
        frames.append(Frame(ms: groupMs, cats: groupCats))
        if frames.count > keep { frames.removeFirst(frames.count - keep) }
        groupStart = nil; groupMs = 0; groupCats = 0
    }

    /// Average, worst and 95th-percentile frame, and the most cats seen in one frame. nil until a frame has closed.
    func summary() -> (avgMs: Double, p95Ms: Double, maxMs: Double, cats: Int)? {
        guard !frames.isEmpty else { return nil }
        let sorted = frames.map(\.ms).sorted()
        return (sorted.reduce(0, +) / Double(sorted.count), sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], sorted.last!, frames.map(\.cats).max()!)
    }

    /// One line for the log, and whether the average is over the budget.
    func readout() -> (line: String, overBudget: Bool)? {
        guard let s = summary() else { return nil }
        let over = s.avgMs > catFrameBudgetMs
        return (String(format: "cat frame: avg %.2f ms, p95 %.2f ms, max %.2f ms, up to %d cats%@", s.avgMs, s.p95Ms, s.maxMs, s.cats,
                       over ? " (OVER the \(catFrameBudgetMs) ms budget)" : ""), over)
    }
}
```

**Create `NotchBuddy/Sources/App/CatFrameReadout.swift`:**

```swift
import Foundation
import QuartzCore

#if DEBUG
/// The Debug-only frame-time readout: every cat draw reports its time, and every two seconds a line goes to
/// `~/Library/Logs/NotchMeow/cat-frames.log` (open it with `tail -f`). Release builds do not contain this.
@MainActor
final class CatFrameReadout {
    static let shared = CatFrameReadout()
    private var meter = CatFrameMeter()
    private var lastReport = CACurrentMediaTime()
    /// The last line written to the log: the cat panel shows it.
    private(set) var latest: String?

    func measure(_ draw: () -> Void) {
        let start = CACurrentMediaTime()
        draw()
        let end = CACurrentMediaTime()
        meter.record(start: start, duration: end - start)
        if end - lastReport >= 2, let r = meter.readout() {
            lastReport = end
            latest = r.line
            appendAppLog("cat-frames.log", r.line)
        }
    }
}
#endif
```

- [ ] **Step 4: Run the test**

Run: `bash scripts/test-cat-frame-meter.sh`
Expected: PASS

- [ ] **Step 5: Time every cat draw in a Debug build**

`drawCat` in `BotCanvasView.swift` is the one place both canvases draw a cat; it times the draw in Debug builds and draws it directly in Release.

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`** — replace:

```swift
        }
    }
    draw()
    return laid!
}
```

with:

```swift
        }
    }
    #if DEBUG
    CatFrameReadout.shared.measure(draw)   // twelve small cats plus the big one stay under 2 ms: see CatFrameMeter
    #else
    draw()
    #endif
    return laid!
}
```

- [ ] **Step 6: Show the draw time in the cat panel**

The panel's cats draw through `CatFrameReadout.shared.measure` too, so the panel shows the same number the log does: the average over a frame of all its live cats (the stage cat and the eleven small ones, in one frame) against the 2 ms budget. The render script compiles the readout now.

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`** — replace:

```swift
            Text("Debug builds only. Every cat here is a real engine drawn by the app's own renderer, on its own settings: the app's cats are never touched.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
```

with:

```swift
            Text("Debug builds only. Every cat here is a real engine drawn by the app's own renderer, on its own settings: the app's cats are never touched.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            // The drawing time of the cats on screen (Windows shows its own in `?dev`): twelve small cats plus the big one stay under 2 ms.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(CatFrameReadout.shared.latest ?? "Drawing time: measuring…")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
```

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`** — replace:

```swift
                    context.withCGContext { cg in
                        let L = CatRenderer.draw(cg, engine.look(), cx: cx, cy: cy, D: D, CatDrawOptions(tint: tint, glow: true))
                        engine.base = L.base
                        engine.mouthPoint = L.mouth
                    }
```

with:

```swift
                    CatFrameReadout.shared.measure {
                        context.withCGContext { cg in
                            let L = CatRenderer.draw(cg, engine.look(), cx: cx, cy: cy, D: D, CatDrawOptions(tint: tint, glow: true))
                            engine.base = L.base
                            engine.mouthPoint = L.mouth
                        }
                    }
```

**Edit `scripts/render-cat-panel.sh`** — replace:

```bash
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-panel.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -D DEBUG \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatDevModel.swift $APP/CatDevPanel.swift \
```

with:

```bash
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-panel.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"   # the readout writes a log line: never into ~/Library/Logs
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -D DEBUG \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/AppLog.swift $APP/CatFrameMeter.swift $APP/CatFrameReadout.swift \
    $APP/CatDevModel.swift $APP/CatDevPanel.swift \
```

Run: `bash scripts/render-cat-panel.sh --out "${TMPDIR:-/tmp}/a-mac-sheets/stage3-panel.png" --height 1700`
Expected: PASS

Open `stage3-panel.png`: under the title the line "Drawing time: measuring…" (the panel is drawn for 1.5 s, which is less than the two seconds of a first reading).

- [ ] **Step 7: Add the emotes and mouths sheets**

**Edit `scripts/render-cats.swift`** — replace:

```swift
//   bash scripts/render-cats.sh --states --cats shrimpy            the 11 states, in both motion styles, after 1.2 s in each
//   bash scripts/render-cats.sh --bench                            frame time of twelve small cats plus the big one
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

@main
```

with:

```swift
//   bash scripts/render-cats.sh --states --cats shrimpy            the 11 states, in both motion styles, after 1.2 s in each
//   bash scripts/render-cats.sh --bench                            frame time of twelve small cats plus the big one
//   bash scripts/render-cats.sh --emotes --cats shrimpy,momo       every emote at its peak, in both motion styles
//   bash scripts/render-cats.sh --mouths --cats momo               the six mouth values: closed, smile, frown, tongue, round, wavy, skew, open
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

@main
```

**Edit `scripts/render-cats.swift`** — replace:

```swift
        case ladder, stage
        case states, bench
    }

    struct Args {
```

with:

```swift
        case ladder, stage
        case states, bench
        case emotes, mouths
    }

    struct Args {
```

**Edit `scripts/render-cats.swift`** — replace:

```swift
            case "--states": a.mode = .states
            case "--bench": a.mode = .bench
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

with:

```swift
            case "--states": a.mode = .states
            case "--bench": a.mode = .bench
            case "--emotes": a.mode = .emotes
            case "--mouths": a.mode = .mouths
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

**Edit `scripts/render-cats.swift`** — replace:

```swift
        case .states: sheet = states(a)
        case .bench: bench(); return
        }
        sheet.write(to: a.out)
```

with:

```swift
        case .states: sheet = states(a)
        case .bench: bench(); return
        case .emotes: sheet = emotes(a)
        case .mouths: sheet = mouths(a)
        }
        sheet.write(to: a.out)
```

**Edit `scripts/render-cats.swift`** — replace:

```swift
    }





    // MARK: Frame time: twelve small cats plus the big one
```

with:

```swift
    }

    // MARK: Emotes: every emote at its peak

    /// The emotes and how long after they start the sheet shows them (ms): about when they are most themselves.
    static let emotePeaks: [(name: String, ms: Int)] = [
        ("love", 700), ("happy", 300), ("surprised", 250), ("proud", 700), ("wink", 450), ("yawn", 650), ("annoyed", 300),
        ("hello", 1000), ("zoomies", 900), ("hairball", 1250),
    ]

    @MainActor static func emotes(_ a: Args) -> Sheet {
        let cell = 190.0, labelW = 130.0, rows = a.cats.count * 2
        let sheet = Sheet(width: labelW + cell * Double(emotePeaks.count) + 8, height: cell * Double(rows) + 28, scale: a.scale)
        let cg = sheet.cg
        for (ci, em) in emotePeaks.enumerated() { CatDraw.text(cg, em.name, x: labelW + (Double(ci) + 0.5) * cell, y: 14, size: 12, bold: true, color: CatDraw.white(0.8)) }
        var row = 0
        for id in a.cats {
            for profile in ["playful", "classic"] {
                let top = 28 + Double(row) * cell
                CatDraw.text(cg, "\(CatPresets.byID(id).label) · \(profile)", x: 62, y: top + cell / 2, size: 12, bold: true, color: CatDraw.white(0.85))
                for (ci, em) in emotePeaks.enumerated() {
                    let x = labelW + Double(ci) * cell
                    let (e, clock, step) = scene(CatPresets.byID(id), profile: profile, D: 110, quiet: true)
                    e.emote(em.name)
                    for _ in 0..<Int((Double(em.ms) / (1000.0 / 60)).rounded()) { step() }
                    cg.saveGState()
                    cg.clip(CatDraw.roundRect(x + 3, top + 3, cell - 6, cell - 6, 12))
                    cg.fill(CatDraw.roundRect(x, top, cell, cell, 0), CatDraw.black(1))
                    CatRenderer.draw(cg, e.look(time: clock.t / 1000), cx: x + cell / 2, cy: top + cell * 0.58, D: 110, CatDrawOptions(glow: true))
                    cg.restoreGState()
                }
                row += 1
            }
        }
        return sheet
    }

    // MARK: Mouths: the six values, set by hand

    @MainActor static func mouths(_ a: Args) -> Sheet {
        let cell = 210.0, labelW = 130.0
        let variants: [(String, (inout CatPose) -> Void, Double)] = [
            ("closed", { _ in }, 0), ("smile", { $0.smile = 1 }, 0), ("frown", { $0.smile = -0.8 }, 0), ("skew", { $0.mskew = 0.7; $0.smile = -0.15 }, 0),
            ("blep", { $0.tongue = 0.8; $0.smile = 0.4 }, 0), ("wavy", { $0.wavy = 1; $0.tongue = 0.45 }, 0), ("meow", { $0.smile = 0.1 }, 0.5),
            ("yawn", { $0.tongue = 0.35; $0.mround = 0.15 }, 1), ("'o'", { $0.mround = 1 }, 0.6), ("hiss", { $0.smile = -1 }, 0.75),
        ]
        let sheet = Sheet(width: labelW + cell * Double(variants.count) + 8, height: cell * Double(a.cats.count) + 28, scale: a.scale)
        let cg = sheet.cg
        for (ci, v) in variants.enumerated() { CatDraw.text(cg, v.0, x: labelW + (Double(ci) + 0.5) * cell, y: 14, size: 12, bold: true, color: CatDraw.white(0.8)) }
        for (ri, id) in a.cats.enumerated() {
            let top = 28 + Double(ri) * cell
            CatDraw.text(cg, CatPresets.byID(id).label, x: 62, y: top + cell / 2, size: 12, bold: true, color: CatDraw.white(0.85))
            for (ci, v) in variants.enumerated() {
                let x = labelW + Double(ci) * cell
                var pose = CatPose(); v.1(&pose)
                cg.saveGState()
                cg.clip(CatDraw.roundRect(x + 3, top + 3, cell - 6, cell - 6, 12))
                cg.fill(CatDraw.roundRect(x, top, cell, cell, 0), CatDraw.black(1))
                CatRenderer.draw(cg, CatLook(preset: CatPresets.byID(id), pose: pose, mouthOpen: v.2), cx: x + cell / 2, cy: top + cell * 0.55, D: 150)
                cg.restoreGState()
            }
        }
        return sheet
    }



    // MARK: Frame time: twelve small cats plus the big one
```

- [ ] **Step 8: Render them and compare**

Run: `bash scripts/render-cats.sh --emotes --cats shrimpy,momo --scale 1 --out "${TMPDIR:-/tmp}/a-mac-sheets/stage3-emotes.png" && bash scripts/render-cats.sh --mouths --cats momo,shrimpy --scale 1 --out "${TMPDIR:-/tmp}/a-mac-sheets/stage3-mouths.png"`
Expected: PASS

Make the prototype's emote montage the same way as the states one (Task 7), then open it next to `stage3-emotes.png`:

```bash
cat > "$TMPDIR/a-mac-check/shots-emotes.js" <<EOF
async page => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.addInitScript(() => {
    let t = 0; const cbs = [];
    performance.now = () => t;
    window.requestAnimationFrame = cb => { cbs.push(cb); return cbs.length; };
    window.__step = (n, dt = 1000 / 60) => { for (let i = 0; i < n; i++) { t += dt; const q = cbs.splice(0); q.forEach(f => f(t)); } };
    Math.random = () => { const x = Math.sin(t * 12.9898 + 78.233) * 43758.5453; return x - Math.floor(x); };
  });
  await page.goto('file://$PWD/design/prototype/notchmeow.html');
  const peaks = { love: 700, happy: 300, surprised: 250, proud: 700, wink: 450, yawn: 650, annoyed: 300, hello: 1000, zoomies: 900, hairball: 1250 };
  for (const style of ['playful','classic']) {
    await page.evaluate(s => { CFG.motion = s; reenter(); mx = null; }, style);
    const shots = {};
    for (const who of ['Shrimpy','Momo']) {
      shots[who] = [];
      for (const name of Object.keys(peaks)) {
        await page.evaluate(() => { goState('idle'); mx = null; });
        await page.evaluate(() => window.__step(90));
        await page.evaluate(name => { for (const S of stage) S.e.emote(name); }, name);
        await page.evaluate(n => window.__step(n), Math.round(peaks[name] / (1000 / 60)));
        shots[who].push(await page.evaluate((who) => {
          const cv = document.getElementById('cv'+who), W = cv.width, H = cv.height, D = Math.min(W*.4, H*.5) / (cv.width / cv.clientWidth);
          const out = document.createElement('canvas'); out.width = 190; out.height = 190; const c = out.getContext('2d');
          c.fillStyle = '#000'; c.fillRect(0,0,190,190);
          const side = D*1.7 * (cv.width/cv.clientWidth);
          c.drawImage(cv, W/2 - side/2, H*.57 - side*.58, side, side, 0, 0, 190, 190);
          return out.toDataURL('image/png');
        }, who));
      }
    }
    await page.evaluate(({shots}) => {
      let m = document.getElementById('montage'); if (m) m.remove();
      m = document.createElement('canvas'); m.id = 'montage'; m.width = 190*10; m.height = 190*2; m.style.display='block'; document.body.prepend(m);
      const c = m.getContext('2d'), imgs = [];
      for (const [ri, who] of ['Shrimpy','Momo'].entries()) shots[who].forEach((d, ci) => { const im = new Image(); im.src = d; imgs.push([im, ci, ri]); });
      return Promise.all(imgs.map(([im]) => new Promise(r => { im.onload = r; }))).then(() => { for (const [im, ci, ri] of imgs) c.drawImage(im, ci*190, ri*190); });
    }, {shots});
    await page.locator('#montage').screenshot({ path: '$TMPDIR/a-mac-check/proto-emotes-' + style + '.png' });
  }
}
EOF
cd "$TMPDIR/a-mac-check" && ~/.local/bin/playwright-cli -s=amac open about:blank && ~/.local/bin/playwright-cli -s=amac run-code --filename=shots-emotes.js && ~/.local/bin/playwright-cli -s=amac close; cd -
```

Look for: Love (closed eyes and hearts in Playful, heart eyes in Classic), Happy (smiling eyes, blush), Surprised (round pupils, an "o" mouth), Proud (sparkle; star eyes in Classic), Wink (one eye, a blep), Yawn (a wide mouth with the tongue curled), Annoyed (pinned ears or line eyes, "hmph"), Hello (the paw with its toe beans), Zoomies (the cat dashing to the side), Hairball (heaving, a hairball once it is out). The mouth sheet is checked by eye on its own: ten mouths on each coat.

- [ ] **Step 9: Build the app**

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO`
Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add tests/CatFrameMeterTests.swift scripts/test-cat-frame-meter.sh NotchBuddy/Sources/App/CatFrameMeter.swift NotchBuddy/Sources/App/CatFrameReadout.swift NotchBuddy/Sources/App/BotCanvasView.swift NotchBuddy/Sources/App/CatDevPanel.swift scripts/render-cat-panel.sh scripts/render-cats.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): the emote and mouth sheets, and a Debug-only frame-time readout with its 2 ms budget, in the log and in the cat panel

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 11: The cat panel's emotes, personality and poke (stage 3)

Agent: `nm-implementer`. Same rule as Task 9: the model is tested; the SwiftUI is proven by the build and the offscreen render.

**Files:**
- Modify: `tests/CatDevModelTests.swift`, `NotchBuddy/Sources/App/CatDevModel.swift`, `NotchBuddy/Sources/App/CatDevPanel.swift`

**Interfaces:**
- Consumes: `CatDevModel`, `CatDevContent` and `ChoiceGrid` (Task 9); `CatEngine.emote(_:)`, `slap()`, `onNote`, `pm()` and `Personality.named(_:)` (Tasks 5 and 6).
- Produces on `CatDevModel`: `static let emotes` (love, happy, surprised, proud, wink, yawn, annoyed, hello, zoomies, hairball), published `personality` (a preset key), and `notes` (what the stage cat just did, the last eight; not published, because the engine writes it while a frame is drawn), `pick(personality:)` (an unknown preset is Balanced; it applies to the chosen coat and follows it, and a kitten wears its parent's), `emote(_:)` and `poke()`.
- Produces in the panel: a Personality menu in the Cat box; under the live cat a button for every emote (hairball included), a Poke button (a click on any cat pokes it too, and three quick pokes make it dizzy) and a line with what the stage cat just did ("emote:love, blink, hairball"), so a habit or an emote that fires by itself can be seen and named.

- [ ] **Step 1: Write the failing test**

**Edit `tests/CatDevModelTests.swift`** — replace:

```swift
        CT.section("the engines run: every pose stays finite after ten seconds")
```

with:

```swift
        CT.section("emotes: every emote plays on the stage cat, and the panel notes it")
        m.pick(coat: "momo"); m.pick(motion: "playful")
        CT.check("ten emotes, hairball and zoomies among them", CatDevModel.emotes, ["love", "happy", "surprised", "proud", "wink", "yawn", "annoyed", "hello", "zoomies", "hairball"])
        for name in CatDevModel.emotes {
            m.emote(name)
            CT.checkTrue("\(name) is noted", m.notes.contains("emote:\(name)"))
        }
        CT.checkTrue("the notes keep the last eight, the newest last", m.notes.count == 8 && Array(m.notes.suffix(2)) == ["emote:hairball", "hairball"])
        m.emote("nonsense")
        CT.checkTrue("an unknown emote leaves the pose finite", PoseKey.allCases.allSatisfy { m.stage.s[$0].isFinite })

        CT.section("personality: a preset applies to the stage cat and the small ones, and follows the coat")
        m.pick(personality: "grumpy")
        CT.checkTrue("a grumpy cat hisses at a poke, on the stage and in the strip", ([m.stage] + m.strip).allSatisfy { $0.pm().pokeHiss })
        m.pick(coat: "ginger")
        CT.check("the personality follows the coat", m.personality, "grumpy")
        CT.checkTrue("and the new coat is grumpy", m.stage.pm().pokeHiss)
        m.pick(personality: "sweet")
        CT.check("a sweet cat answers a poke with love", m.stage.pm().poke, "love")
        m.pick(personality: "nonsense")
        CT.check("an unknown personality is Balanced", m.personality, "balanced")
        CT.checkTrue("and every engine follows", ([m.stage] + m.strip).allSatisfy { !$0.pm().pokeHiss && $0.pm().poke == "annoyed" })
        m.pick(personality: "grumpy"); m.pick(kitten: true)
        CT.checkTrue("a kitten wears its parent's personality", m.stage.pm().pokeHiss)
        m.pick(kitten: false); m.pick(personality: "balanced")
        CT.checkTrue("the app's own cats have no personality of the panel's", CatConfig.shared.pers.isEmpty)

        CT.section("a poke: three quick ones make the cat dizzy, then it recovers")
        m.pick(state: .idle)
        for _ in 0..<3 { clock.t += 200; m.poke() }
        CT.check("three quick pokes make the stage cat dizzy", m.stage.state, CatState.dizzy)
        CT.check("the state the panel chose is as it was", m.state, CatState.idle)
        clock.t += 3400; m.stage.update(dt: 1.0 / 60)
        CT.check("and after 3.3 s it is back", m.stage.state, CatState.idle)

        CT.section("the engines run: every pose stays finite after ten seconds")
```

Run: `bash scripts/test-cat-devpanel.sh`
Expected: FAIL (swiftc: `CatDevModel` has no member `emotes`)

- [ ] **Step 2: Add the emotes, the personality and the poke to the model**

**Edit `NotchBuddy/Sources/App/CatDevModel.swift`** — replace:

```swift
    static let sizes: [Double] = [12, 16, 20, 24, 28, 44, 66, 120, 180]
```

with:

```swift
    static let sizes: [Double] = [12, 16, 20, 24, 28, 44, 66, 120, 180]
    /// The emotes of the contract, in the spec's order.
    static let emotes = ["love", "happy", "surprised", "proud", "wink", "yawn", "annoyed", "hello", "zoomies", "hairball"]
```

**Edit `NotchBuddy/Sources/App/CatDevModel.swift`** — replace:

```swift
    @Published private(set) var state = CatState.idle
    @Published var tint = true
```

with:

```swift
    @Published private(set) var state = CatState.idle
    @Published private(set) var personality = "balanced"
    @Published var tint = true
    /// What the stage cat just did, newest last (the last eight): "emote:love", "blink", "hairball"... They are the engine's own notes.
    /// Not published: the engine writes it while a frame is drawn (SwiftUI does not allow a change to be published from there), so the panel reads it on a timer.
    private(set) var notes: [String] = []
```

**Edit `NotchBuddy/Sources/App/CatDevModel.swift`** — replace:

```swift
    func pick(state st: CatState) { state = st; stage.setState(st) }
```

with:

```swift
    func pick(state st: CatState) { state = st; stage.setState(st) }
    /// A preset by name; an unknown name is Balanced, like a stored personality the app does not know. It applies to the chosen coat and follows
    /// it (a kitten wears its parent's). The engines read it as they run, so nothing is rebuilt.
    func pick(personality key: String) { personality = Personality.named(key).preset; cfg.pers = [coat: Personality.named(personality)] }
    /// Plays an emote on the stage cat (an unknown name is ignored by the engine).
    func emote(_ name: String) { stage.emote(name) }
    /// A poke, as a click on a cat does it: three quick ones make it dizzy.
    func poke() { stage.slap() }
```

**Edit `NotchBuddy/Sources/App/CatDevModel.swift`** — replace:

```swift
    private func rebuild() {
        let p = preset
        stage = make(p, state: state)
        strip = CatState.allCases.map { make(p, state: $0) }
    }
```

with:

```swift
    private func rebuild() {
        let p = preset
        cfg.pers = [coat: Personality.named(personality)]
        stage = make(p, state: state)
        stage.onNote = { [weak self] _, event in self?.record(event) }
        strip = CatState.allCases.map { make(p, state: $0) }
        notes = []
    }

    private func record(_ event: String) {
        notes.append(event)
        if notes.count > 8 { notes.removeFirst(notes.count - 8) }
    }
```

- [ ] **Step 3: Run the test**

Run: `bash scripts/test-cat-devpanel.sh`
Expected: PASS

- [ ] **Step 4: Put them in the panel**

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`** — replace:

```swift
                Toggle("Kitten", isOn: Binding(get: { model.kitten }, set: { model.pick(kitten: $0) }))
```

with:

```swift
                Picker("Personality", selection: Binding(get: { model.personality }, set: { model.pick(personality: $0) })) {
                    ForEach(Personality.presets, id: \.key) { Text($0.label).tag($0.key) }
                }
                Toggle("Kitten", isOn: Binding(get: { model.kitten }, set: { model.pick(kitten: $0) }))
```

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`** — replace:

```swift
                ChoiceGrid(items: CatState.allCases.map { ($0.rawValue, $0.rawValue) }, selected: model.state.rawValue) {
                    if let st = CatState(rawValue: $0) { model.pick(state: st) }
                }
```

with:

```swift
                ChoiceGrid(items: CatState.allCases.map { ($0.rawValue, $0.rawValue) }, selected: model.state.rawValue) {
                    if let st = CatState(rawValue: $0) { model.pick(state: st) }
                }
                Text("Emote")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                ChoiceGrid(items: CatDevModel.emotes.map { ($0, $0) }, selected: nil) { model.emote($0) }
                HStack(spacing: 10) {
                    Button("Poke") { model.poke() }
                        .buttonStyle(.bordered)
                    Text("or click a cat. Three quick pokes make it dizzy.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text("What it just did: " + (model.notes.isEmpty ? "nothing yet" : model.notes.joined(separator: ", ")))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(.secondary)
                }
```

- [ ] **Step 5: Build, and look at the panel**

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO`
Expected: PASS

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Debug/NotchMeow.app debug`
Expected: PASS

Run: `bash scripts/render-cat-panel.sh --out "${TMPDIR:-/tmp}/a-mac-sheets/stage3-panel-emotes.png" --height 1700`
Expected: PASS

Open `stage3-panel-emotes.png`: the Personality menu in the Cat box, and under the live cat the emote buttons, the Poke button and the "What it just did" line. To see an emote on the cat itself, use the emotes sheet of Task 10 (`render-cats.sh --emotes`); the panel is for watching them live in a Debug build.

- [ ] **Step 6: Commit**

```bash
git add tests/CatDevModelTests.swift NotchBuddy/Sources/App/CatDevModel.swift NotchBuddy/Sources/App/CatDevPanel.swift
git commit -m "feat(cat): the cat panel plays every emote, wears any personality and takes a poke

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 12: The greeting's timeline in Swift (stage 4)

Agent: `nm-implementer-light`.

**Files:**
- Create: `tests/CatGreetingTests.swift`, `scripts/test-cat-greeting.sh`
- Create: `NotchBuddy/Sources/App/CatGreeting.swift`

**Interfaces:**
- Consumes: `CatEase`, `CatRNG`, `lerp`, `seg` (Task 2), `CatEngine.flightMs` (Task 6); `tests/fixtures/cat/sequence-cases.json` (`greetingTimeline`, `greetingStreaks`, `greetingSamples`, `flight`).
- Produces `enum CatGreeting`: `struct Pose: Encodable` (`iw, ih, hb, x, y, sx, sy, tilt, eye ("dot" | "happy" | "content"), lookX, lookY, handL, handR, wave (-1 = off), open, badge, tint, halo, haloBlue, header, card, fx, minis`, all in a 640x150 space), `GT` and `GT2` (the beats), `length` (5.74 s), `streaks` (sixteen seeded), `streakTime(_:)`, `struct Compact` (`width`, `height`, `botCenterY`, `botDiameter`; the default is the contract's 288 x 32 island with a Ø20 cat at y = 16, `init(width:height:)` is a real screen's compact island), `islandBase(_:)`, `fallPose(_:_:)`, `collapsePose(_:leave:into:)`, `pose(_ t:, leave: Double = GT.leave, into: Compact = Compact()) -> Pose` and `flightAt(from:to:R:k:)`.
- `leave` is when the island starts to collapse: 4.9 s by itself (the contract); earlier when the pointer leaves mid-greeting; `.infinity` while the pointer holds the island open. An early leave starts from the pose the cat is in and carries it to rest on the way, so nothing jumps.

- [ ] **Step 1: Write the failing test**

**Create `tests/CatGreetingTests.swift`:**

```swift
import Foundation

@main
enum CatGreetingTests {
    static func num(_ x: Any?) -> Double { (x as! NSNumber).doubleValue }

    @MainActor static func main() {
        let seq = CT.fixture("sequence-cases.json")
        typealias G = CatGreeting

        CT.section("the timeline's beats")
        let t = seq["greetingTimeline"] as! [String: Any]
        let beats: [String: Double] = [
            "grow": G.GT.grow, "badge": G.GT.badge, "blink2": G.GT.blink2, "tint0": G.GT.tint0, "tint1": G.GT.tint1, "leave": G.GT.leave, "COLLAPSE": G.GT.collapse,
            "v2_fall0": G.GT2.fall0, "v2_land": G.GT2.land, "v2_bounce1": G.GT2.bounce1, "v2_slide0": G.GT2.slide0, "v2_slide1": G.GT2.slide1, "v2_pop0": G.GT2.pop0,
            "v2_wave0": G.GT2.wave0, "v2_wave1": G.GT2.wave1, "v2_back0": G.GT2.back0, "v2_back1": G.GT2.back1, "v2_SLIDE": G.GT2.slide,
            "notchW": G.notchW, "notchH": G.notchH, "compact": G.compact,
        ]
        CT.checkJSON("every beat", got: beats, want: t)
        CT.checkNear("the greeting lasts 5.74 s", G.length, num(seq["greetingLengthS"]))

        CT.section("the streaks")
        CT.checkJSON("sixteen seeded streaks", got: G.streaks.map { ["a": $0.a, "sp": $0.sp, "len": $0.len, "t0": $0.t0, "col": $0.col] as [String: Any] }, want: seq["greetingStreaks"]!)

        CT.section("the pose every 100 ms and at each beat")
        var diffs: [String] = []
        for s in seq["greetingSamples"] as! [[String: Any]] {
            let ms = num(s["tMs"])
            diffs += CT.diffs(CT.json(G.pose(ms / 1000)), s["pose"]!).map { "t \(ms) ms: \($0)" }
        }
        CT.checkRows("\((seq["greetingSamples"] as! [Any]).count) samples", diffs)

        CT.section("a dropped file's flight")
        let fl = seq["flight"] as! [String: Any]
        CT.checkNear("380 ms", CatEngine.flightMs, num(fl["flightMs"]))
        for c in fl["cases"] as! [[String: Any]] {
            let f = c["from"] as! [String: Any], to = c["to"] as! [String: Any]
            let o = G.flightAt(from: (num(f["x"]), num(f["y"])), to: (num(to["x"]), num(to["y"])), R: num(c["R"]), k: num(c["k"]))
            CT.checkJSON("k = \(c["k"]!)", got: ["x": o.x, "y": o.y, "size": o.size, "rot": o.rot] as [String: Any], want: c["out"]!)
        }

        CT.section("leaving early: the pointer left mid-greeting, or holds the island open")
        // An early leave starts from the pose the cat is in; the island always ends compact with the cat at the notch.
        for leave in [1.0, 1.7, 2.0, 3.0] {
            let end = G.pose(leave + 0.34 + 0.1, leave: leave)
            CT.checkNear("leave at \(leave): the island ends compact (width)", end.iw, G.compact)
            CT.checkNear("leave at \(leave): and the cat is at the notch", end.x, 320 - G.compact / 2 + 40)
            CT.checkTrue("leave at \(leave): the cat is back to rest and hands are down", end.sx == 1 && end.sy == 1 && end.tilt == 0 && end.handL == 0 && end.handR == 0)
            let during = G.pose(leave + 0.05, leave: leave), before = G.pose(leave, leave: leave)
            CT.checkTrue("leave at \(leave): no jump at the moment of leaving", abs(during.x - before.x) < 20 && abs(during.y - before.y) < 20 && abs(during.hb - before.hb) < 4)
        }
        // The real compact island of a screen: its width, height and the cat's size follow it.
        let real = G.Compact(width: 344, height: 38)
        let landed = G.pose(G.GT.leave + 0.34 + 0.1, into: real)
        CT.checkNear("a real compact island: the width", landed.iw, 344); CT.checkNear("the height", landed.ih, 38)
        CT.checkNear("the cat settles at x = 40 from the island's left edge", landed.x, 320 - 344 / 2 + 40)
        CT.checkNear("in the middle of the strip", landed.y, 19); CT.checkNear("at the compact size, Ø20", landed.hb * 1.34, 20)
        CT.checkNear("on a 24 pt strip (no notch) the cat is Ø18", G.Compact(width: 80, height: 24).botDiameter, 18)
        CT.checkNear("the contract's compact island is the default", G.pose(5.3, into: G.Compact()).iw, G.compact)
        CT.checkNear("holding the island open keeps the settled pose forever (x)", G.pose(60, leave: .infinity).x, 320)
        CT.checkNear("and the island stays at full width", G.pose(60, leave: .infinity).iw, 640)
        var finite = true
        for ms in stride(from: -500, through: 8000, by: 50) { let p = CT.json(G.pose(Double(ms) / 1000)) as! [String: Any]; if p.values.contains(where: { ($0 as? Double)?.isFinite == false }) { finite = false } }
        CT.checkTrue("every pose from before the start to well after the end is finite", finite)
        CT.finish()
    }
}
```

**Create `scripts/test-cat-greeting.sh`:**

```bash
#!/usr/bin/env bash
# The launch greeting timeline, its streaks and the file flight against sequence-cases.json.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-greeting.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatGreeting.swift \
    tests/CatTestSupport.swift tests/CatGreetingTests.swift \
    -o "$TEST_DIR/cat-greeting-tests"
"$TEST_DIR/cat-greeting-tests"
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-greeting.sh`
Expected: FAIL (swiftc cannot open `NotchBuddy/Sources/App/CatGreeting.swift`)

- [ ] **Step 3: Write the timeline**

The fall, bounce, slide, pop and wave are the core's `fallPose`; `collapsePose` is the core's with two additions that are not in the contract and that the fixtures cannot see (they never leave early and always use the 288 x 32 island): the collapse starts from the actual pose at `leave`, and it ends in the island the screen really has.

**Create `NotchBuddy/Sources/App/CatGreeting.swift`:**

```swift
import Foundation

// The launch greeting: a cat version of Greeting v2, 5.74 s in a 640x150 space. The island grows, the cat falls in with a landing
// squash, bounces, slides aside, pops up for a quick paw wave, slides back, and settles with the badge and the tint; then the island
// collapses to the compact notch. Port of the "Timelines" section of design/prototype/cat-core.js (the tie-breaker);
// tests/fixtures/cat/sequence-cases.json pins the timeline, the streaks and the flight of a dropped file.

enum CatGreeting {
    /// The pose at one moment, all in the 640x150 space: island iw x ih, cat centre x, y and head width hb * 1.34, squash sx/sy, tilt,
    /// eye shape, gaze lookX/lookY, paw raise handL/handR, the wave clock (-1 = off), blink `open`, and the 0...1 fades.
    struct Pose: Encodable, Equatable {
        var iw: Double, ih: Double, hb: Double, x: Double, y: Double, sx: Double, sy: Double, tilt: Double
        var eye: String
        var lookX: Double, lookY: Double, handL: Double, handR: Double, wave: Double, open: Double
        /// The badge, the tint, the halo (gold to blue), the header text, the card, the streaks and the session cats.
        var badge: Double, tint: Double, halo: Double, haloBlue: Double, header: Double, card: Double, fx: Double, minis: Double
    }

    static let notchW = 184.0, notchH = 32.0, compact = 288.0

    /// Where the island ends up and where the cat settles in it. The defaults are the contract's (a 288 x 32 island, a Ø20 cat in the middle
    /// of it); the app passes the real compact island of the screen it is on.
    struct Compact {
        var width = CatGreeting.compact, height = CatGreeting.notchH, botCenterY = 16.0, botDiameter = 20.0
        init() {}
        init(width: Double, height: Double) {
            self.width = width; self.height = height; botCenterY = height / 2; botDiameter = min(20, max(0, height - 6))
        }
    }

    /// The island's beats, shared with the old greeting: when the badge and the tint arrive and when the island leaves.
    enum GT {
        static let grow = 0.45, badge = 2.72, blink2 = 3.8, tint0 = 3.85, tint1 = 4.15, leave = 4.9, collapse = 0.34
    }
    /// The cat's beats: fall, land, bounce, slide aside, pop up and wave, slide back.
    enum GT2 {
        static let fall0 = 0.05, land = 0.62, bounce1 = 1.18, slide0 = 1.25, slide1 = 1.65, pop0 = 1.65, wave0 = 1.72, wave1 = 2.72,
                   back0 = 2.75, back1 = 3.25, slide = 150.0
    }
    static let length = GT.leave + GT.collapse + 0.5

    /// Sixteen colour streaks that burst out when the cat lands; seeded, so they are the same everywhere.
    struct Streak: Equatable { var a: Double, sp: Double, len: Double, t0: Double, col: String }
    static let streaks: [Streak] = {
        let r = CatRNG(seed: 7), cols = ["#3B9EFF", "#F29B38", "#FF5A4E", "#2EC4A0", "#A78BFA"]
        return (0..<16).map { i in
            let a = Double(i) / 16 * CatMath.tau + (r.next() - 0.5) * 0.3
            let sp = 230 + r.next() * 260, len = 6 + r.next() * 9, t0 = 0.08 + r.next() * 0.14
            return Streak(a: a, sp: sp, len: len, t0: t0, col: cols[i % 5])
        }
    }()
    /// Streak time: it starts when the cat lands.
    static func streakTime(_ t: Double) -> Double { t - (GT2.land - 0.1) }

    /// The island and the shared beats: size, blink, badge, tint, halo, header. Everything but the cat's own motion.
    struct Base { var iw: Double, ih: Double, hb: Double, base: Double, open: Double, badge: Double, tint: Double, halo: Double, haloBlue: Double, header: Double, card: Double }

    static func islandBase(_ t: Double) -> Base {
        let gx = seg(t, 0, 0.5), g = sin(Double.pi * gx / 2) + 0.04 * sin(Double.pi * gx) * gx
        let gg = CatEase.back.at(seg(t, 0.02, GT.grow))
        func blink(_ tb: Double) -> Double { let k = seg(t, tb, tb + 0.12); return k > 0 && k < 1 ? 1 - sin(Double.pi * k) * 0.94 : 1 }
        return Base(iw: lerp(notchW, 640, g), ih: lerp(notchH, 150, g), hb: lerp(3, 58, gg), base: lerp(16, 86, CatEase.out.at(seg(t, 0.02, GT.grow))),
                    open: min(blink(1.95), blink(GT.blink2)), badge: CatEase.back.at(seg(t, GT.badge, GT.badge + 0.28)),
                    tint: 0.6 * CatEase.inOut.at(seg(t, GT.tint0, GT.tint1)), halo: CatEase.out.at(seg(t, 0.3, 0.7)), haloBlue: seg(t, GT.tint0, GT.tint1),
                    header: seg(t, 0.35, 0.6), card: seg(t, 0.18, 0.45))
    }

    /// The cat's fall, bounce, slide, pop and wave.
    static func fallPose(_ t: Double, _ B: Base) -> Pose {
        typealias G = GT2
        let hb = B.hb, D = hb * 1.34, base = B.base
        var x = 320.0, y = base, sx = 1.0, sy = 1.0, tilt = 0.0, eye = "dot", lookX = 0.0, lookY = 0.0, wave = -1.0
        let fall = seg(t, G.fall0, G.land)
        y -= (1 - fall * fall) * (base + 70)                                                            // 1 fall in (accelerating)
        let sq = sin(Double.pi * seg(t, G.land, G.land + 0.16))
        sy -= 0.2 * sq; sx += 0.14 * sq; y += D * 0.05 * sq                                              // landing squash
        let b = seg(t, G.land + 0.16, G.bounce1)
        y -= 4 * b * (1 - b) * hb * 0.3; sy += 0.05 * sin(Double.pi * b)                                // 2 small bounce
        let sq2 = sin(Double.pi * seg(t, G.bounce1, G.bounce1 + 0.1))
        sy -= 0.07 * sq2; sx += 0.05 * sq2; y += D * 0.02 * sq2
        let out = CatEase.inOut.at(seg(t, G.slide0, G.slide1)), ret = CatEase.inOut.at(seg(t, G.back0, G.back1))   // 3 slide aside, 5 slide back
        x += G.slide * out * (1 - ret)
        tilt = 0.1 * sin(Double.pi * seg(t, G.slide0, G.slide1)) - 0.1 * sin(Double.pi * seg(t, G.back0, G.back1))
        let ant = sin(Double.pi * seg(t, G.pop0 - 0.1, G.pop0))
        sy -= 0.08 * ant; y += D * 0.03 * ant                                                            // 4 pop up
        let pop = CatEase.back.at(seg(t, G.pop0, G.pop0 + 0.2)) * (1 - CatEase.inOut.at(seg(t, G.back0, G.back0 + 0.2)))
        y -= hb * 0.16 * pop; sy += 0.07 * sin(Double.pi * seg(t, G.pop0, G.pop0 + 0.2))
        let flail = 0.55 * (1 - seg(t, G.land - 0.05, G.land + 0.1)) * (t > G.fall0 ? 1 : 0)             // paws up while falling
        let handL = flail, handR = max(flail, pop)
        if t >= G.wave0 && t < G.wave1 + 0.2 { wave = t - G.wave0 }
        if t >= G.land && t < G.slide0 { eye = "happy" }
        if t >= G.slide0 && t < G.pop0 { lookX = 0.5 * out }
        if t >= G.pop0 && t < G.back0 { eye = "happy"; lookX = 0.3; lookY = -0.4 }
        if t >= G.back0 {
            let k = seg(t, G.back0, G.back1 + 0.1)
            eye = k < 0.9 ? "content" : "dot"
            lookX = lerp(0.3, 0, CatEase.inOut.at(k)); lookY = lerp(-0.4, 0, CatEase.inOut.at(k))
        }
        return Pose(iw: B.iw, ih: B.ih, hb: hb, x: x, y: y, sx: sx, sy: sy, tilt: tilt, eye: eye, lookX: lookX, lookY: lookY, handL: handL, handR: handR, wave: wave,
                    open: B.open, badge: B.badge, tint: B.tint, halo: B.halo, haloBlue: B.haloBlue, header: B.header, card: B.card, fx: 1, minis: 0)
    }

    /// After `leave` the island collapses to the compact notch and the cat settles. When `leave` is the timeline's 4.9 s the cat is already at
    /// rest and this is the contract; an earlier `leave` (the pointer left mid-greeting) carries the cat's pose to rest on the way.
    static func collapsePose(_ t: Double, leave tc: Double = GT.leave, into end: Compact = Compact()) -> Pose {
        let a = islandBase(tc), from = fallPose(tc, a)
        let e = CatEase.inOut.at(seg(t, tc, tc + GT.collapse)), bx = 320 - end.width / 2 + 40, bk = seg(t, tc + 0.14, tc + 0.26)
        let hands = 1 - seg(t, tc, tc + 0.15)
        return Pose(iw: lerp(a.iw, end.width, e), ih: lerp(a.ih, end.height, e), hb: lerp(a.hb, end.botDiameter / 1.34, e), x: lerp(from.x, bx, e), y: lerp(from.y, end.botCenterY, e),
                    sx: lerp(from.sx, 1, e), sy: lerp(from.sy, 1, e), tilt: lerp(from.tilt, 0, e), eye: "dot", lookX: lerp(from.lookX, 0, e), lookY: lerp(from.lookY, 0, e),
                    handL: from.handL * hands, handR: from.handR * hands, wave: from.wave,
                    open: bk > 0 && bk < 1 ? 1 - sin(Double.pi * bk) * 0.94 : 1, badge: a.badge, tint: a.tint, halo: a.halo * (1 - e), haloBlue: a.haloBlue,
                    header: a.header * (1 - seg(t, tc, tc + 0.1)), card: a.card * (1 - seg(t, tc, tc + 0.18)), fx: 1 - seg(t, tc, tc + 0.2),
                    minis: CatEase.back.at(seg(t, tc + 0.24, tc + 0.42)))
    }

    /// The greeting pose at t seconds (0 ... `length`). `leave` is when the island starts to collapse: 4.9 s by itself, earlier when the
    /// pointer leaves, never (infinity) while the pointer holds the island open.
    static func pose(_ t: Double, leave: Double = GT.leave, into end: Compact = Compact()) -> Pose {
        t < leave ? fallPose(t, islandBase(t)) : collapsePose(t, leave: leave, into: end)
    }

    // MARK: A dropped file's flight

    /// Where a file is k (0...1) of the way along its arc from `from` to `to`, how big it is and how it is turned.
    static func flightAt(from: (x: Double, y: Double), to: (x: Double, y: Double), R: Double, k: Double) -> (x: Double, y: Double, size: Double, rot: Double) {
        let q = CatEase.inOut.at(k), cx = (from.x + to.x) / 2, cy = min(from.y, to.y) - 60, u = 1 - q
        return (u * u * from.x + 2 * u * q * cx + q * q * to.x, u * u * from.y + 2 * u * q * cy + q * q * to.y, lerp(R * 0.62, R * 0.14, q), (1 - q) * 0.5 - 0.25)
    }
}
```

- [ ] **Step 4: Run the test**

Run: `bash scripts/test-cat-greeting.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/CatGreetingTests.swift scripts/test-cat-greeting.sh NotchBuddy/Sources/App/CatGreeting.swift
git commit -m "feat(cat): the new greeting's timeline and the file flight in Swift, tested against sequence-cases.json

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 13: The launch greeting, drawn (stage 4)

Agent: `nm-implementer`.

**Files:**
- Modify: `tests/CatRendererTests.swift`, `scripts/test-cat-renderer.sh`, `scripts/render-cats.swift`, `scripts/render-cats.sh`
- Modify: `tests/CatDevModelTests.swift`, `NotchBuddy/Sources/App/CatDevModel.swift`, `NotchBuddy/Sources/App/CatDevPanel.swift`, `scripts/render-cat-panel.sh`
- Create: `NotchBuddy/Sources/App/CatGreetingRenderer.swift`
- Replace: `NotchBuddy/Sources/App/GreetingCanvasView.swift`
- Modify (regenerated): `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CatGreeting.pose`, `CatGreeting.Compact`, `CatGreeting.streaks` (Task 12); `CatRenderer.draw`, `CatEngine` (Tasks 4 and 6).
- Produces `CatGreetingRenderer.draw(_ cg: CGContext, t: Double, leave: Double, engine: CatEngine, end: CatGreeting.Compact, cat label: String? = nil)`: draws the greeting at `t` seconds into a 640x150 canvas (halo, streaks, header, the cat with paws for hands, and the four little cats of the compact grid). The island's black shape is the app's own. The cat's engine is updated by the caller each frame (it blinks and flicks an ear by itself); the greeting sets its pose directly.
- Produces `render-cats.sh --greeting [--cats id]`: the greeting at fourteen beats.
- Produces in the cat panel (Task 9): a Greeting box with the launch greeting in a 640x150 card, a Replay button and a "Collapse now" button that cuts it short the way the pointer leaving the island does (the Windows `?dev` page has both), and `CatDevModel.greeting`, the greeting's own engine, which follows the chosen coat.
- Keeps, unchanged: `GreetingCanvasView(state:)`, its use of `.greetingHover`, `.greetingInterrupt` and `.greetComplete`, and the sounds (`greet` at the wave, `blip` at the badge). The greeting still tells the state machine it is done at 4.6 s; the island collapses from the moment the pointer leaves (`leave`), into the island the screen really has (`state.notchWidth + 160` by `state.notchHeight`).

- [ ] **Step 1: Extend the renderer test**

The new section draws the greeting every 100 ms from 0 to 6 s, as it runs its course, cut short at 1 s and at 2 s, and held open: nothing blank, the cat in the middle at 3.8 s, the header text on both sides, and at the end the cat at the notch and the middle empty.

**Edit `tests/CatRendererTests.swift`** — replace:

```swift
        CT.check("nothing came out blank", engineBlank, [])
        CT.checkTrue("a hairball and particles were on screen at some point", sawBall && sawParticle)
        CT.finish()
    }
```

with:

```swift
        CT.check("nothing came out blank", engineBlank, [])
        CT.checkTrue("a hairball and particles were on screen at some point", sawBall && sawParticle)
        CT.section("the launch greeting draws at every moment, whether it runs its course, is cut short or is held open")
        do {
            let clock = FakeClock(), rng = CatRNG(seed: 4)
            func frame(_ t: Double, leave: Double) -> [UInt8] {
                clock.t = t * 1000
                let e = CatEngine(CatPresets.byID("shrimpy"), now: { clock.t }, rand: { rng.next() }, cfg: CatConfig(), quiet: true)
                return render(640, 150) { CatGreetingRenderer.draw($0, t: t, leave: leave, engine: e, end: CatGreeting.Compact()) }
            }
            var blanks: [String] = []
            for leave in [CatGreeting.GT.leave, 1.0, 2.0, .infinity] {
                for step in stride(from: 0.0, through: 6.0, by: 0.1) where Bitmap.coverage(frame(step, leave: leave)) == 0 && step > 0.5 && step < 5.6 { blanks.append("leave \(leave) at \(step)") }
            }
            CT.check("no moment of the greeting is blank (leave at 4.9 s, at 1 s, at 2 s, and held open)", blanks, [])
            let settled = frame(3.8, leave: CatGreeting.GT.leave)
            CT.checkTrue("the cat sits in the middle at 3.8 s", Bitmap.alpha(settled, 320, 90, 640) > 200)
            CT.checkTrue("the header text is there at 2 s, on the left and on the right", { let f = frame(2, leave: CatGreeting.GT.leave); return (0..<30).contains { y in (20..<120).contains { Bitmap.alpha(f, $0, y, 640) > 100 } } && (0..<30).contains { y in (480..<620).contains { Bitmap.alpha(f, $0, y, 640) > 100 } } }())
            let end = frame(5.7, leave: CatGreeting.GT.leave)
            CT.checkTrue("at the end the cat is at the notch, 40 pt from the island's left edge, and the middle is empty", Bitmap.alpha(end, 320 - 144 + 40, 16, 640) > 200 && Bitmap.alpha(end, 320, 75, 640) == 0)
            let early = frame(1.0 + 0.5, leave: 1.0)
            CT.checkTrue("cut short at 1 s, the cat is already on its way to the notch", Bitmap.coverage(early) > 0)
        }
        CT.finish()
    }
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-renderer.sh`
Expected: FAIL (`cannot find 'CatGreetingRenderer' in scope`)

- [ ] **Step 3: Write the greeting renderer and compile it into the test**

The drawing is the prototype's `drawGreeting` without the island: two halo passes (gold turning blue), the streaks, the header ("NotchMeow" on the left, "Hi! Shrimpy is watching your agents." on the right), the cat, and the session cats. The badge slides from the right ear to the left as the island closes.

**Create `NotchBuddy/Sources/App/CatGreetingRenderer.swift`:**

```swift
import CoreGraphics
import Foundation

/// Draws the launch greeting into a 640x150 canvas: the halo, the streaks, the header, the cat (with paws for hands) and the little
/// session cats. The island's black shape is the app's own (IslandContainer); this draws inside it. The pose comes from `CatGreeting`.
@MainActor
enum CatGreetingRenderer {
    typealias Greeting = CatGreeting

    /// Draws the greeting at `t` seconds. `engine` is the cat's engine (it blinks and flicks an ear by itself, and has been updated for this frame);
    /// `leave` is when the island starts to collapse (infinity while the pointer holds it open); `end` is the compact island it collapses into.
    static func draw(_ cg: CGContext, t: Double, leave: Double, engine e: CatEngine, end: Greeting.Compact, cat label: String? = nil) {
        let P = Greeting.pose(t, leave: leave, into: end), X = P.x, Y = P.y, D = P.hb * 1.34, p = e.p
        let st = Greeting.streakTime(t)
        if P.halo > 0 {
            let bl = P.haloBlue, c = [lerp(232, 59, bl), lerp(195, 158, bl), lerp(154, 255, bl)].map { $0.rounded() }
            for (rad, al) in [(D * 1.3, 0.18), (D * 2.1, 0.07)] {
                CatDraw.radial(cg, [(0, CatDraw.rgb(c, al * P.halo)), (1, CatDraw.rgb(c, 0))], center: (X, Y), r0: 0, r1: rad)
            }
        }
        for sk in Greeting.streaks {
            let q = seg(st, sk.t0, sk.t0 + 0.6)
            if q <= 0 || q >= 1 { continue }
            let dist = sk.sp * CatEase.out.at(q) * 0.9 + 10
            let line = CGMutablePath()
            line.move(to: CGPoint(x: X + cos(sk.a) * (dist - sk.len), y: Y + sin(sk.a) * (dist - sk.len) * 0.42))
            line.addLine(to: CGPoint(x: X + cos(sk.a) * dist, y: Y + sin(sk.a) * dist * 0.42))
            cg.stroke(line, CatDraw.color(sk.col, alpha: (1 - q) * P.fx), width: 1.6)
        }
        if P.header > 0.01 {
            CatDraw.text(cg, "NotchMeow", x: 20, y: 20, size: 13, bold: true, color: CatDraw.white(P.header), anchor: .left)
            CatDraw.text(cg, "Hi! \(label ?? p.label) is watching your agents.", x: 620, y: 20, size: 11.5, bold: false, color: CatDraw.rgb([141, 144, 152], P.header), anchor: .right)
        }
        // The cat: the greeting sets its pose directly each frame; its ears, mouth and idle habits are the engine's own.
        e.s.sx = P.sx; e.s.sy = P.sy; e.s.tilt = P.tilt; e.s.open = P.open
        e.s.yaw = P.lookX * 0.55; e.s.pitch = -P.lookY * 0.45; e.s.roll = 0; e.s.oy = 0; e.s.ox = 0
        e.s.badgeS = P.badge; e.s.tint = P.tint; e.s.paws = 0
        e.eyeOv = P.eye == "happy" ? .happy : P.eye == "content" ? .closed : nil
        e.eyeUntil = .infinity
        var look = e.look()
        look.badge = .dots; look.badgeColor = "#3BA0F5"; look.color = [127, 180, 234]
        let R = D / (2 * p.rx), rx = p.rx * R, ry = p.ry * R
        let on = P.wave >= 0, w = on ? P.wave * CatMath.tau * 4.2 : 0, wa = on ? seg(P.wave, 0, 0.12) * (1 - seg(P.wave, 0.9, 1.0)) : 0
        look.paws = [
            CatPaw(x: lerp(-0.35 * rx, -(rx + 0.22 * R), P.handL), y: lerp(0.85 * ry, 0.62 * ry, P.handL), k: P.handL, rot: -0.2, beans: false),
            CatPaw(x: lerp(0.35 * rx, rx + 0.2 * R, P.handR) + cos(w) * ry * 0.05 * wa, y: lerp(0.85 * ry, 0.05 * ry, P.handR) + sin(w + 0.8) * ry * 0.1 * wa,
                   k: P.handR, rot: 0.3 + sin(w) * 0.45 * wa, beans: true),
        ]
        var o = CatDrawOptions()
        o.badgeSide = 1 - 2 * CatEase.inOut.at(seg(t, leave, leave + Greeting.GT.collapse))
        CatRenderer.draw(cg, look, cx: X, cy: Y, D: D, o)
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
            cg.restoreGState()
        }
    }
}
```

**Edit `scripts/test-cat-renderer.sh`** — replace:

```bash
    $APP/CatFace.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift tests/CatEngineSupport.swift \
    tests/CatTestSupport.swift tests/CatBitmapSupport.swift tests/CatRendererTests.swift \
    -o "$TEST_DIR/cat-renderer-tests"
```

with:

```bash
    $APP/CatFace.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift tests/CatEngineSupport.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
    tests/CatTestSupport.swift tests/CatBitmapSupport.swift tests/CatRendererTests.swift \
    -o "$TEST_DIR/cat-renderer-tests"
```

- [ ] **Step 4: Run the test**

Run: `bash scripts/test-cat-renderer.sh`
Expected: PASS

- [ ] **Step 5: Add the greeting to the contact sheet and compare it with the prototype**

**Edit `scripts/render-cats.swift`** — replace:

```swift
//   bash scripts/render-cats.sh --emotes --cats shrimpy,momo       every emote at its peak, in both motion styles
//   bash scripts/render-cats.sh --mouths --cats momo               the six mouth values: closed, smile, frown, tongue, round, wavy, skew, open
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

@main
```

with:

```swift
//   bash scripts/render-cats.sh --emotes --cats shrimpy,momo       every emote at its peak, in both motion styles
//   bash scripts/render-cats.sh --mouths --cats momo               the six mouth values: closed, smile, frown, tongue, round, wavy, skew, open
//   bash scripts/render-cats.sh --greeting --cats shrimpy          the launch greeting at its beats, island and cat
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

@main
```

**Edit `scripts/render-cats.swift`** — replace:

```swift
        case states, bench
        case emotes, mouths
    }

    struct Args {
```

with:

```swift
        case states, bench
        case emotes, mouths
        case greeting
    }

    struct Args {
```

**Edit `scripts/render-cats.swift`** — replace:

```swift
            case "--emotes": a.mode = .emotes
            case "--mouths": a.mode = .mouths
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

with:

```swift
            case "--emotes": a.mode = .emotes
            case "--mouths": a.mode = .mouths
            case "--greeting": a.mode = .greeting
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

**Edit `scripts/render-cats.swift`** — replace:

```swift
        case .emotes: sheet = emotes(a)
        case .mouths: sheet = mouths(a)
        }
        sheet.write(to: a.out)
```

with:

```swift
        case .emotes: sheet = emotes(a)
        case .mouths: sheet = mouths(a)
        case .greeting: sheet = greeting(a)
        }
        sheet.write(to: a.out)
```

**Edit `scripts/render-cats.swift`** — replace:

```swift
    }



    // MARK: Frame time: twelve small cats plus the big one
```

with:

```swift
    }


    // MARK: The launch greeting at its beats

    @MainActor static func greeting(_ a: Args) -> Sheet {
        let beats: [(Double, String)] = [(0.3, "grows"), (0.62, "lands"), (0.72, "squash"), (1.2, "bounce"), (1.5, "slides aside"), (1.9, "pops up"), (2.3, "waves"),
                                         (2.7, "waves"), (3.0, "slides back"), (3.8, "settles"), (4.5, "badge, tint"), (5.0, "collapses"), (5.2, "collapses"), (5.7, "compact")]
        let cols = 2, rows = (beats.count + 1) / 2, w = 640.0, h = 150.0
        let sheet = Sheet(width: w * Double(cols) + 24, height: (h + 22) * Double(rows * a.cats.count), scale: a.scale)
        let cg = sheet.cg
        var slot = 0
        for id in a.cats {
            for (i, beat) in beats.enumerated() {
                let ox = 8 + Double(i % cols) * (w + 8), oy = 4 + Double(slot + i / cols) * (h + 22)
                let (e, clock, step) = scene(CatPresets.byID(id), profile: "playful", D: 80, quiet: true)
                let scratch = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                let frames = Int((beat.0 * 60).rounded())
                for _ in 0..<frames { step(); CatGreetingRenderer.draw(scratch, t: clock.t / 1000, leave: CatGreeting.GT.leave, engine: e, end: CatGreeting.Compact()) }
                cg.saveGState()
                cg.translateBy(x: ox, y: oy)
                let P = CatGreeting.pose(beat.0)
                cg.fill(CatDraw.roundRect(320 - P.iw / 2, 0, P.iw, P.ih, 24), CatDraw.black(1))
                cg.clip(CatDraw.roundRect(320 - P.iw / 2, 0, P.iw, P.ih, 24))
                CatGreetingRenderer.draw(cg, t: beat.0, leave: CatGreeting.GT.leave, engine: e, end: CatGreeting.Compact())
                cg.restoreGState()
                CatDraw.text(cg, String(format: "%.2f s · %@", beat.0, beat.1), x: ox + 4, y: oy + h + 9, size: 10, bold: false, color: CatDraw.white(0.5), anchor: .left)
            }
            slot += rows
        }
        return sheet
    }

    // MARK: Frame time: twelve small cats plus the big one
```

**Edit `scripts/render-cats.sh`** — replace:

```bash
    $APP/CatFace.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    scripts/render-cats.swift \
    -o "$BUILD_DIR/render-cats"
```

with:

```bash
    $APP/CatFace.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
    scripts/render-cats.swift \
    -o "$BUILD_DIR/render-cats"
```

Run: `bash scripts/render-cats.sh --greeting --cats shrimpy --scale 1 --out "${TMPDIR:-/tmp}/a-mac-sheets/stage4-greeting.png"`
Expected: PASS

The prototype's greeting panel has a clock of its own (`GC.t`); this script steps it to six beats and puts the shots in a montage:

```bash
cat > "$TMPDIR/a-mac-check/shots-greeting.js" <<EOF
async page => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.addInitScript(() => {
    let t = 0; const cbs = [];
    performance.now = () => t;
    window.requestAnimationFrame = cb => { cbs.push(cb); return cbs.length; };
    window.__step = (n, dt = 1000 / 60) => { for (let i = 0; i < n; i++) { t += dt; const q = cbs.splice(0); q.forEach(f => f(t)); } };
    Math.random = () => { const x = Math.sin(t * 12.9898 + 78.233) * 43758.5453; return x - Math.floor(x); };
  });
  await page.goto('file://$PWD/design/prototype/notchmeow.html');
  await page.evaluate(() => window.__step(30));
  const beats = [0.72, 1.9, 2.3, 3.0, 4.5, 5.2], shots = [];
  for (const b of beats) {
    await page.evaluate(b => { GC.cat = 'shrimpy'; gcReplay(); for (let i = 0; i < Math.round(b * 60); i++) window.__step(1); }, b);
    shots.push(await page.evaluate(() => document.getElementById('cvG').toDataURL('image/png')));
  }
  await page.evaluate(shots => {
    let m = document.getElementById('montage'); if (m) m.remove();
    const cv = document.getElementById('cvG'), h = Math.round(640 / cv.width * cv.height);
    m = document.createElement('canvas'); m.id = 'montage'; m.width = 1280; m.height = 3 * h; m.style.display = 'block'; document.body.prepend(m);
    const c = m.getContext('2d'), imgs = shots.map(d => { const im = new Image(); im.src = d; return im; });
    return Promise.all(imgs.map(im => new Promise(r => { im.onload = r; }))).then(() => imgs.forEach((im, i) => c.drawImage(im, (i % 2) * 640, Math.floor(i / 2) * h, 640, h)));
  }, shots);
  await page.locator('#montage').screenshot({ path: '$TMPDIR/a-mac-check/proto-greeting.png' });
}
EOF
cd "$TMPDIR/a-mac-check" && ~/.local/bin/playwright-cli -s=amac open about:blank && ~/.local/bin/playwright-cli -s=amac run-code --filename=shots-greeting.js && ~/.local/bin/playwright-cli -s=amac close; cd -
```

Open `stage4-greeting.png` next to `proto-greeting.png`. The beats to look for: it falls in and lands with a squash (streaks burst), bounces, slides aside, pops up and waves a paw with the toe beans out, slides back, settles with the blue badge and tint, then the island closes to the compact notch with the cat at its left and four little cats at its right.

- [ ] **Step 6: Replace the greeting view**

`GreetingCanvasView.swift` keeps its name, its state-machine hooks and its sounds; the 600 lines that drew the old body, hands, rings and card go, because the timeline and the drawing now live in `CatGreeting` and `CatGreetingRenderer`.

**Replace `NotchBuddy/Sources/App/GreetingCanvasView.swift` with:**

```swift
import SwiftUI
import QuartzCore

// The launch greeting: a cat version of Greeting v2. The timeline is CatGreeting's (5.74 s in a 640x150 space) and the drawing is
// CatGreetingRenderer's; this view only runs the clock, holds the cat's engine and talks to the island's state machine.

private enum GT {
    /// The animation is done: the state machine is told here (when the pointer is not on the island).
    static let end: Double = 4.60
    /// Where the timeline starts to collapse by itself.
    static let autoLeave: Double = CatGreeting.GT.leave
    static let pop0: Double = CatGreeting.GT2.pop0
    static let badge: Double = CatGreeting.GT.badge
}

struct GreetingCanvasView: View {
    @ObservedObject var state: AppState

    @State private var startDate = Date()
    @State private var tc: Double = .infinity   // collapses only when the FSM fires .greetingInterrupt
    @State private var greetFired = false
    @StateObject private var engine = CatEngine.live()

    // Scheduled works (cancellable)
    @State private var soundWork1: DispatchWorkItem? = nil
    @State private var soundWork2: DispatchWorkItem? = nil
    @State private var doneWork:   DispatchWorkItem? = nil

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(startDate)
            Canvas { context, size in
                engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                let end = CatGreeting.Compact(width: Double(state.notchWidth) + 160, height: Double(state.notchHeight))
                context.withCGContext { cg in
                    CatGreetingRenderer.draw(cg, t: t, leave: tc, engine: engine, end: end)
                }
            }
            // Fire greetComplete exactly once at T.end (when no hover)
            .onChange(of: !greetFired && t >= GT.end && tc >= GT.autoLeave) { _, trigger in
                if trigger { fireGreetComplete() }
            }
        }
        .onAppear {
            startDate = Date()
            tc = .infinity
            greetFired = false
            scheduleWorks()
        }
        .onDisappear {
            cancelWorks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .greetingHover)) { _ in
            // Mouse on notch during greeting → hold open (no auto-collapse)
            if tc >= GT.autoLeave { tc = .infinity }
        }
        .onReceive(NotificationCenter.default.publisher(for: .greetingInterrupt)) { _ in
            // Mouse left during greeting → start collapse from current time
            let t = Date().timeIntervalSince(startDate)
            if tc.isInfinite || tc > t { tc = t }
            cancelWorks()   // cancel auto-done timer (FSM already went to .petit)
        }
    }

    private func fireGreetComplete() {
        guard !greetFired else { return }
        greetFired = true
        cancelWorks()
        NotificationCenter.default.post(name: .greetComplete, object: nil)
    }

    private func scheduleWorks() {
        func schedule(_ delay: Double, _ block: @escaping () -> Void) -> DispatchWorkItem {
            let item = DispatchWorkItem(block: block)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return item
        }
        soundWork1 = schedule(GT.pop0)  { SoundEngine.shared.play("greet") }
        soundWork2 = schedule(GT.badge) { SoundEngine.shared.play("blip")  }
        // doneWork is a safety fallback; normal path fires via .onChange
        doneWork = schedule(GT.end + 0.05) { fireGreetComplete() }
    }

    private func cancelWorks() {
        soundWork1?.cancel(); soundWork1 = nil
        soundWork2?.cancel(); soundWork2 = nil
        doneWork?.cancel();   doneWork = nil
    }
}
```

- [ ] **Step 7: Put the greeting in the cat panel**

The greeting sets its cat's pose directly each frame, so the panel gives it an engine of its own, rebuilt with the chosen coat. The card is drawn with the island's black shape (a rounded rectangle here, since the app's own island shape belongs to the island).

**Edit `tests/CatDevModelTests.swift`** — replace:

```swift
        CT.section("the engines run: every pose stays finite after ten seconds")
```

with:

```swift
        CT.section("the greeting's cat is the chosen cat")
        m.pick(coat: "latte")
        CT.check("the greeting engine wears the coat", m.greeting.p.name, "latte")
        m.pick(kitten: true)
        CT.checkTrue("and its kitten", m.greeting.p.kitten == true)
        m.pick(kitten: false)

        CT.section("the engines run: every pose stays finite after ten seconds")
```

**Edit `NotchBuddy/Sources/App/CatDevModel.swift`** — replace:

```swift
    @Published private(set) var strip: [CatEngine] = []
```

with:

```swift
    @Published private(set) var strip: [CatEngine] = []
    /// The cat of the launch greeting (it sets its pose directly each frame, so it is an engine of its own).
    @Published private(set) var greeting: CatEngine
```

**Edit `NotchBuddy/Sources/App/CatDevModel.swift`** — replace:

```swift
        stage = CatEngine(CatPresets.byID("shrimpy"), now: now, rand: rand, cfg: cfg)
        rebuild()
```

with:

```swift
        stage = CatEngine(CatPresets.byID("shrimpy"), now: now, rand: rand, cfg: cfg)
        greeting = CatEngine(CatPresets.byID("shrimpy"), now: now, rand: rand, cfg: cfg)
        rebuild()
```

**Edit `NotchBuddy/Sources/App/CatDevModel.swift`** — replace:

```swift
        strip = CatState.allCases.map { make(p, state: $0) }
        notes = []
```

with:

```swift
        strip = CatState.allCases.map { make(p, state: $0) }
        greeting = make(p, state: .idle)
        notes = []
```

Run: `bash scripts/test-cat-devpanel.sh`
Expected: PASS

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`** — replace:

```swift
            statesStrip
            ladder
        }
    }
```

with:

```swift
            statesStrip
            greetingBox
            ladder
        }
    }
```

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`** — replace:

```swift
    // MARK: Every coat

    private var ladder: some View {
```

with:

```swift
    // MARK: The greeting

    private var greetingBox: some View {
        GroupBox("Greeting") {
            VStack(alignment: .leading, spacing: 10) {
                Text("The launch greeting: the cat falls in with a landing squash, bounces, slides aside, pops up for a paw wave, slides back and settles. Collapse now cuts it short, the way the pointer leaving the island does.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                CatDevGreeting(engine: model.greeting)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Every coat

    private var ladder: some View {
```

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`** — replace:

```swift
/// A group of buttons of which one is on.
```

with:

```swift
/// The launch greeting, replayable: the same timeline and drawing as the island's (`CatGreeting`, `CatGreetingRenderer`) on the island's black
/// shape. Replay starts it again; Collapse now cuts it short, as the pointer leaving the island does.
private struct CatDevGreeting: View {
    let engine: CatEngine
    @State private var start = CACurrentMediaTime()
    @State private var leave = CatGreeting.GT.leave

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Replay") { start = CACurrentMediaTime(); leave = CatGreeting.GT.leave }
                    .buttonStyle(.bordered)
                Button("Collapse now") { leave = min(leave, CACurrentMediaTime() - start) }
                    .buttonStyle(.bordered)
            }
            TimelineView(.animation) { timeline in
                Canvas { context, _ in
                    _ = timeline.date   // the Canvas redraws on every tick of the timeline
                    let t = CACurrentMediaTime() - start
                    engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                    context.withCGContext { cg in
                        let P = CatGreeting.pose(t, leave: leave)
                        let island = CatDraw.roundRect(320 - P.iw / 2, 0, P.iw, P.ih, 24)
                        cg.fill(island, CatDraw.black(1))
                        cg.saveGState()
                        cg.clip(island)
                        CatGreetingRenderer.draw(cg, t: t, leave: leave, engine: engine, end: CatGreeting.Compact())
                        cg.restoreGState()
                    }
                }
            }
            .frame(width: 640, height: 150)
        }
    }
}

/// A group of buttons of which one is on.
```

**Edit `scripts/render-cat-panel.sh`** — replace:

```bash
    $APP/AppLog.swift $APP/CatFrameMeter.swift $APP/CatFrameReadout.swift \
```

with:

```bash
    $APP/AppLog.swift $APP/CatFrameMeter.swift $APP/CatFrameReadout.swift $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
```

Run: `bash scripts/render-cat-panel.sh --out "${TMPDIR:-/tmp}/a-mac-sheets/stage4-panel-greeting.png" --height 2100`
Expected: PASS

Open `stage4-panel-greeting.png`: a Greeting box between the eleven states and the ladder, with Replay and Collapse now and the 640x150 card (the greeting is mid-way after the 1.5 s of the render).

- [ ] **Step 8: Build the app**

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add tests/CatRendererTests.swift scripts/test-cat-renderer.sh scripts/render-cats.swift scripts/render-cats.sh tests/CatDevModelTests.swift scripts/render-cat-panel.sh NotchBuddy/Sources/App/CatGreetingRenderer.swift NotchBuddy/Sources/App/GreetingCanvasView.swift NotchBuddy/Sources/App/CatDevModel.swift NotchBuddy/Sources/App/CatDevPanel.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): the launch greeting: the cat falls in, waves a paw and settles in the real compact island, and replays in the cat panel

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 14: The drop view's mouth catch, the refused file's hairball and the cat panel's file buttons (stage 4)

Agent: `nm-implementer-deep`. The drop view can only be proven by a build, by the unit tests of its pieces and by reading how it is driven; do not launch the installed app or a built one to check it.

**Files:**
- Create: `tests/UploadCatDriverTests.swift`, `scripts/test-cat-upload.sh`
- Create: `NotchBuddy/Sources/App/CatFileRule.swift`, `NotchBuddy/Sources/App/UploadCatDriver.swift`
- Modify: `NotchBuddy/Sources/App/UploadSequenceEngine.swift`, `NotchBuddy/Sources/App/UploadCanvasView.swift`, `NotchBuddy/Sources/App/FileDropView.swift`, `scripts/render-cats.swift`
- Modify: `tests/CatDevModelTests.swift`, `NotchBuddy/Sources/App/CatDevModel.swift`, `NotchBuddy/Sources/App/CatDevPanel.swift`, `scripts/test-cat-devpanel.sh`, `scripts/render-cat-panel.sh`
- Modify (regenerated): `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CatEngine.catchOpen/catchDrop/catchArrive/catchReject/emote/update/look`, `CatEngine.frameDelta`, `CatEngine.flightMs` (Task 6); `CatRenderer.draw` (Task 4); `CatGreeting.flightAt` (Task 12); `USFrame` and `USC` of `UploadSequenceEngine.swift`; the app's own refusal rule, `AttachmentRules.classify(size:ext:head:)` and `AICatalog.Limits.maxFileBytes` (read only: the AI code is not touched); the AI fixture `tests/fixtures/ai/attachment-cases.json`; `CatDevModel` and `CatDevCell` (Tasks 9, 11 and 13).
- Produces `enum CatFileRule`: `refused(ext:size:) -> Bool` (the app's refusal rule from the extension and the size, which are known at the drop) and `label(for name:) -> String` (the extension in capitals, four letters at most, `FILE` when there is none).
- Produces `USFrame.dropped: Bool` (the post-drop timeline is running, as opposed to a file still being dragged over the island; `f.t` alone cannot say, because a long hover has no cap) and `USFrame.refused: Bool`; `UploadSequenceEngine.performDrop(uploadDuration:refused:)`; `USC.COUGH_LEAD_S` (0.12 s), `USC.HAIRBALL_S` (2.4 s), `USC.T_COUGH_END` (the file's arrival plus 2.52 s: the note starts to appear) and `USC.T_REFUSE_DONE` (the cat is at its choose place).
- Produces `UploadCatDriver` (`init(engine:)`, `engine`, `follow(_ f: USFrame, file name: String)`): called once per frame before the cat is drawn. **1.** While a file hovers (`f.zoneOver`, not dropped) the mouth opens wide: `catchOpen(true)`. **2.** On the drop it snaps wider: `catchDrop()`. **3 and 4.** When the file reaches the mouth (`f.t >= USC.T_SUCK_END`, 380 ms after the drop: the length of the contract's flight) it gulps with a squash and chews for 0.85 s with happy eyes, `catchArrive()`, or, for a refused file, `catchReject(label)`: it gags and coughs the file up as a hairball. When the upload finishes (`f.t >= f.progEnd`) a taken file's cat is happy once. A new drag after a drop starts over. The cat follows the pointer with the sequence's look (positive down) turned to the engine's (positive up).
- On the cat panel: `CatDevModel.files` (a PDF, an app, a 30 MB file), `catchFile(named:size:)`, `advance()`, `flight` and `flightProgress`, and a File row of three buttons under the live cat.

**What changes in the drop view, and what does not.**
- **The cat** replaces the Mochi and its mailbox body (`CatRenderer.draw`, head width `f.d`, at `f.x`, `f.y + f.hop`). The sequence's own timeline (zone, bar, check mark, choose buttons) is unchanged for a taken file.
- **The hovering file and its flight:** while a file is dragged over the island its icon sits under the pointer, as before. After the drop it flies along the contract's `flightAt` (380 ms, from the drop to the arrival, the same flight as the prototype's catch and the same one A-tauri uses), and it is drawn **after the cat, so in front of it**, hovering and flying, as in the prototype. The old suction (the strips cut at the mouth line, and the four green sparks) is replaced by that flight; the icon leaves the pointer at the size it had there and shrinks as the flight does, so it does not jump.
- **Refused files, the same on both apps.** *Refused* is the app's existing refusal rule: apps, archives, disk images, videos and anything over 25 MB (`AttachmentRules`, 26,214,400 bytes). The Mac decides it **at the drop** from the extension and the size (`CatFileRule`), instead of waiting for the AI reader's verdict at the end of the upload sequence; A-tauri gets the same verdict from Rust's `ingest_file`. The catch plays as for any file (open wide while hovering, snap wider on the drop, the file flies in). Then, instead of the gulp and the chew, the cat gags and coughs the file up as a **hairball**: it takes 120 ms to start heaving and the hairball lasts 2.4 s, and the refusal note (the choose view with its reader line, `state.dropReaderLine`) starts to appear 2.52 s after the file arrives (A-tauri times its note the same way). A refused file has no progress bar, no tick sounds, no check mark and no `approve` chime.
- **The sounds of a refusal:** the cat plays the existing `annoyed` sound once, when the gag starts (`FileDropHandler`, at the moment the file reaches the mouth: `USC.T_SUCK_END - USC.T_DROP` after the drop, the same moment the driver calls `catchReject`; the heaves follow 120 ms later). The refusal note (the choose view) plays no sound, and nothing else plays: the engine's `catchReject` and `hairball` are silent, and the hairball's `pop` at the cough is wired later, by sound Stage 3: neither plan adds it now.
- **Any other failure** (the AI reader cannot read the file, a copy error, a folder) keeps today's ending, with no hairball: the sequence runs as for a taken file and ends with the `annoyed` sound and the annoyed cat. (`.botReject` is no longer posted: it only ever existed to start a hairball, and nothing observes it. Its name stays declared in `AIService.swift` until the stage-7 sweep.)
- **The `approve` chime moves from the drop to a successful ingest.** It no longer plays when the file is dropped, for any file; it plays at the check mark, and only when the AI's reader did not reject the file (`!state.dropRejected`), which is when the file has been read. A-tauri moved its chime the same way: to the moment `ingest_file` succeeds.

- [ ] **Step 1: Write the failing test**

The test reads the app's refusal rule from the AI fixture, feeds the driver synthetic frames of the sequence on a fake clock for a taken file and for a refused one, and asks the sequence engine for the frames of a refused file and of a taken one.

**Create `tests/UploadCatDriverTests.swift`:**

```swift
import Foundation

@main
enum UploadCatDriverTests {
    static func num(_ x: Any?) -> Double { (x as! NSNumber).doubleValue }

    /// A frame of the upload sequence with only the fields the cat reads.
    static func frame(_ t: Double, hover: Bool = false, dropped: Bool = false, refused: Bool = false, lookX: Double = 0, lookY: Double = 0) -> USFrame {
        var f = USFrame()
        f.t = t; f.zoneOver = hover; f.dropped = dropped; f.refused = refused; f.lookX = lookX; f.lookY = lookY
        if refused { f.progEnd = USC.T_COUGH_END }
        return f
    }

    @MainActor static func main() {
        CT.section("which files the cat coughs up: the app's own refusal rule, decided at the drop")
        let ai = CT.fixture("attachment-cases.json", dir: "ai")
        let reject = ai["rejectExtensions"] as! [String], limit = Int(num(ai["maxFileBytes"]))
        CT.check("25 MB is 26,214,400 bytes", limit, 26_214_400)
        for e in reject {
            CT.checkTrue("\(e): an app, an archive, a disk image or a video, in lower and in upper case", CatFileRule.refused(ext: e, size: 1) && CatFileRule.refused(ext: e.uppercased(), size: 1))
        }
        for e in ["pdf", "txt", "swift", "docx", "png", "jpg", "html", "md", "", "bin", "dat"] {
            CT.checkTrue("\"\(e)\" is taken at 0 bytes and at 1 KB (a binary file with no known extension fails later, with no hairball)", !CatFileRule.refused(ext: e, size: 0) && !CatFileRule.refused(ext: e, size: 1000))
        }
        CT.checkTrue("a file of exactly 25 MB is taken", !CatFileRule.refused(ext: "pdf", size: limit))
        CT.checkTrue("one byte more is refused, whatever it is", CatFileRule.refused(ext: "pdf", size: limit + 1) && CatFileRule.refused(ext: "", size: limit + 1))
        CT.checkTrue("a size that is not a size (negative) is not refused", !CatFileRule.refused(ext: "pdf", size: -5))
        CT.check("the label is the extension in capitals", CatFileRule.label(for: "setup.exe"), "EXE")
        CT.check("the last extension of an archive", CatFileRule.label(for: "archive.tar.gz"), "GZ")
        CT.check("four letters at most", CatFileRule.label(for: "site.webarchive"), "WEBA")
        CT.check("a file with no extension is FILE", CatFileRule.label(for: "Makefile"), "FILE")

        // One cat on a fake clock, for a taken file and for a refused one.
        final class NoteLog { var notes: [String] = [] }
        func scene(_ seed: UInt32) -> (e: CatEngine, d: UploadCatDriver, clock: FakeClock, notes: NoteLog) {
            let clock = FakeClock(), rng = CatRNG(seed: seed), log = NoteLog(), p = CatPresets.byID("shrimpy")
            let e = CatEngine(p, now: { clock.t }, rand: { rng.next() }, cfg: CatConfig(), quiet: true)
            e.onNote = { log.notes.append($1) }
            let L = CatGeometry.layout(p, e.s, cx: 0, cy: 0, D: 2 * p.rx)
            e.base = L.base; e.mouthPoint = L.mouth
            return (e, UploadCatDriver(engine: e), clock, log)
        }
        let (e, d, clock, notes) = scene(3)
        func run(_ frames: Int, _ f: @autoclosure () -> USFrame, file: String = "notes.pdf") { for _ in 0..<frames { clock.t += 1000.0 / 60; d.follow(f(), file: file) } }

        CT.section("1. a file hovers: the mouth opens wide and the eyes widen")
        run(40, frame(1.6, hover: true))
        CT.checkTrue("the cat is catching", e.catching)
        CT.check("with wide eyes", e.eyeShape(), CatEye.wide)
        CT.checkTrue("and the mouth is open (spring settled near 0.55)", abs(e.slotH - 0.55) < 0.05)

        CT.section("the drag leaves the island: the cat relaxes")
        run(30, frame(1.6, hover: false))
        CT.checkTrue("not catching", !e.catching)
        CT.checkTrue("the mouth closes", e.slotH < 0.05)

        CT.section("2. the drop: the mouth snaps wider")
        run(20, frame(1.9, hover: true))
        run(30, frame(USC.T_DROP + 0.1, hover: true, dropped: true))
        CT.checkTrue("still catching, and wider than while hovering (near 1.05)", e.catching && abs(e.slotH - 1.05) < 0.08)

        CT.section("3. the file arrives: a gulp with a squash, then a chew with happy eyes")
        run(1, frame(USC.T_SUCK_END + 0.01, dropped: true))
        CT.checkTrue("the catch is over", !e.catching)
        CT.checkTrue("a chew has started", e.chewUntil > e.chewStart && e.chewUntil - e.chewStart == 850)
        CT.check("with happy eyes", e.eyeShape(), CatEye.happy)
        CT.checkTrue("and a squash (the cat is flatter within a few frames)", { run(3, frame(USC.T_SUCK_END + 0.1, dropped: true)); return e.s.sy < 0.95 || e.s.sx > 1.05 }())
        let arrivals = notes.notes.filter { $0 == "emote:happy" }.count
        run(5, frame(USC.T_SUCK_END + 0.2, dropped: true))
        CT.check("the arrival happens once, not on every frame", e.chewUntil - e.chewStart, 850)
        CT.checkTrue("and a taken file is never coughed up", !notes.notes.contains("hairball"))

        CT.section("the upload finishes: one happy emote")
        var f = frame(USC.T_PROG_START + 2.5, dropped: true); f.progEnd = USC.T_PROG_START + 2.4
        run(3, f)
        CT.check("the cat is happy about it, once", notes.notes.filter { $0 == "emote:happy" }.count, arrivals + 1)

        CT.section("a new drag starts over: it opens wide again")
        run(40, frame(1.6, hover: true))
        CT.checkTrue("catching again", e.catching && abs(e.slotH - 0.55) < 0.06)

        CT.section("the cat follows the pointer (the sequence's look is positive down, the engine's positive up)")
        run(1, frame(1.6, hover: true, lookX: 0.4, lookY: 0.5))
        CT.checkNear("looks across", e.lookX, 0.4); CT.checkNear("and down", e.lookY, -0.5)

        CT.section("a refused file: caught like any file, then the cat gags and coughs it up, with no chew and no celebration")
        let (r, rd, rclock, rnotes) = scene(5)
        func runR(_ frames: Int, _ f: @autoclosure () -> USFrame) { for _ in 0..<frames { rclock.t += 1000.0 / 60; rd.follow(f(), file: "setup.exe") } }
        runR(40, frame(1.6, hover: true))
        CT.checkTrue("1. it opens wide while the file hovers, like any file", r.catching && abs(r.slotH - 0.55) < 0.05 && r.eyeShape() == .wide)
        runR(30, frame(USC.T_DROP + 0.1, dropped: true, refused: true))
        CT.checkTrue("2. it snaps wider on the drop, like any file", r.catching && abs(r.slotH - 1.05) < 0.08)
        runR(1, frame(USC.T_SUCK_END + 0.01, dropped: true, refused: true))
        CT.checkTrue("3. at the arrival it does not gulp or chew: nothing is chewed and the eyes are not happy", !r.catching && r.chewUntil == 0 && r.eyeShape() != .happy)
        var ball: String?
        for i in 0..<Int((USC.COUGH_LEAD_S + USC.HAIRBALL_S) * 60 + 30) {
            rclock.t += 1000.0 / 60
            rd.follow(frame(USC.T_SUCK_END + 0.2 + Double(i) / 60, dropped: true, refused: true), file: "setup.exe")
            if let b = r.balls.first { ball = b.file }
        }
        CT.check("4. it coughs up one hairball", rnotes.notes.filter { $0 == "hairball" }.count, 1)
        CT.check("   with the file in its fur, labelled EXE", ball, "EXE")
        CT.checkTrue("   and it is never happy about it, even long after the progress would have ended", !rnotes.notes.contains("emote:happy"))
        runR(40, frame(1.6, hover: true))
        CT.checkTrue("a new drag after a refused drop starts over: open wide again", r.catching && abs(r.slotH - 0.55) < 0.06)

        CT.section("the sequence of a refused file: no bar, no check mark, no green wash, and the choose view after the hairball")
        let seq = UploadSequenceEngine.shared
        seq.enterZone(x: 300, y: 80)
        seq.performDrop(uploadDuration: 2.4, refused: true)
        func at(_ afterDrop: Double) -> USFrame { seq.frame(at: Date().addingTimeInterval(afterDrop)) }
        let arrive = USC.T_SUCK_END - USC.T_DROP, noteAt = USC.T_COUGH_END - USC.T_DROP, doneAt = USC.T_REFUSE_DONE - USC.T_DROP
        CT.checkNear("the note comes 0.12 s of heaving plus the 2.4 s hairball after the file arrives", USC.T_COUGH_END - USC.T_SUCK_END, 2.52)
        let flying = at(0.2)
        CT.checkTrue("just after the drop the file is in flight, and the frame says dropped and refused", flying.dropped && flying.refused && flying.fileVisible)
        let gagging = at(arrive + 1.0)
        CT.checkTrue("while the cat gags there is no bar, no progress, no check mark and no green wash", gagging.barAlpha == 0 && gagging.barReveal == 0 && gagging.progress == 0 && gagging.check == 0 && gagging.greenWash == 0)
        CT.checkTrue("the file is gone and the note is not there yet", !gagging.fileVisible && gagging.chooseAlpha == 0 && at(noteAt - 0.05).chooseAlpha == 0)
        CT.checkTrue("the cat stays where it caught the file while it gags", abs(gagging.x - at(noteAt - 0.1).x) < 1e-6 && abs(gagging.y - at(noteAt - 0.1).y) < 1e-6)
        CT.checkTrue("the note starts to appear when the hairball is over", at(noteAt + 0.15).chooseAlpha > 0)
        let done = at(doneAt + 0.1)
        CT.checkTrue("and it is fully there once the cat is at its choose place", done.chooseAlpha == 1)
        CT.checkNear("the cat is at its choose place (x)", done.x, USC.CHOOSE_X); CT.checkNear("(y)", done.y, USC.CHOOSE_Y)
        CT.check("the sequence never reaches an upload's end for the cat to celebrate", done.progEnd, USC.T_COUGH_END)
        seq.deactivate()

        CT.section("a taken file keeps the sequence it had: the bar fills and a check mark follows")
        seq.enterZone(x: 300, y: 80)
        seq.performDrop(uploadDuration: 2.4, refused: false)
        let filling = at(USC.T_PROG_START - USC.T_DROP + 1.0)
        CT.checkTrue("the bar fills, and nothing is refused", filling.dropped && !filling.refused && filling.progress > 0 && filling.barAlpha > 0)
        let checked = at(USC.T_PROG_START + 2.4 - USC.T_DROP + 0.4)
        CT.checkTrue("and the check mark comes at the end", checked.check > 0.9)
        seq.deactivate()
        CT.finish()
    }
}
```

**Create `scripts/test-cat-upload.sh`:**

```bash
#!/usr/bin/env bash
# The cat in the drop view: the upload sequence's frames drive the four-step file catch, a refused file is decided at the drop by the app's own
# rule (read from the AI fixtures) and coughed up as a hairball, and the sequence of a refused file has no bar and no check mark.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-upload.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/UploadSequenceEngine.swift $APP/CatFileRule.swift $APP/UploadCatDriver.swift \
    $APP/AI/Core/Attachments.swift $APP/AI/Core/AICatalog.swift $APP/AI/Core/ModelProvider.swift $APP/AI/Core/ContextBudget.swift \
    tests/CatTestSupport.swift tests/CatEngineSupport.swift tests/UploadCatDriverTests.swift \
    -o "$TEST_DIR/cat-upload-tests"
"$TEST_DIR/cat-upload-tests"
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-cat-upload.sh`
Expected: FAIL (swiftc cannot open `NotchBuddy/Sources/App/CatFileRule.swift`)

- [ ] **Step 3: Write the rule and the driver, and teach the sequence about a refused file**

The rule asks the app's own classifier with no bytes: its size and extension checks run before it reads any, so an empty head gives exactly the refusals of "apps, archives, disk images, videos, over 25 MB". `computeRefusedFrame` is the refused file's whole timeline: the cat stays where it caught the file while it gags, then goes to its choose place, and the choose view starts to appear when the hairball is over.

**Create `NotchBuddy/Sources/App/CatFileRule.swift`:**

```swift
import Foundation

/// Which files the cat coughs up, and what it writes on them. The rule is the app's own refusal rule (`AttachmentRules`: apps, archives, disk images
/// and videos by extension, and anything over 25 MB), so there is one list. It is decided at the drop, from what is known then (the extension and the
/// size), instead of waiting for the AI's reader to fail at the end of the upload sequence. A file that fails for any other reason (unreadable, a copy
/// error, a folder) is not refused here: it keeps today's ending, with no hairball.
enum CatFileRule {
    /// `ext` without the dot, in any case; `size` in bytes. No bytes are needed: the rule's size and extension checks run before it reads any.
    static func refused(ext: String, size: Int) -> Bool {
        if case .failure = AttachmentRules.classify(size: size, ext: ext, head: Data()) { return true }
        return false
    }

    /// The label a refused file wears in its fur: the extension in capitals, four letters at most, FILE when it has none.
    static func label(for name: String) -> String {
        let ext = (name as NSString).pathExtension
        return String((ext.isEmpty ? "FILE" : ext).uppercased().prefix(4))
    }
}
```

**Create `NotchBuddy/Sources/App/UploadCatDriver.swift`:**

```swift
import Foundation

/// Drives the cat in the drop view from the upload sequence's frames. The sequence knows where the cat is and when the file is hovering, dropped and
/// arrived; the cat's engine turns that into the file catch: the mouth opens wide while the file hovers, snaps wider on the drop, and when the file
/// arrives (380 ms later, the length of the contract's flight) the cat gulps with a squash and chews with happy eyes, or, for a refused file, gags
/// and coughs it up as a hairball.
@MainActor
final class UploadCatDriver: ObservableObject {
    let engine: CatEngine
    private var dropped = false
    private var arrived = false
    private var celebrated = false

    init(engine: CatEngine) { self.engine = engine }

    /// Advances the cat one frame for the sequence frame `f`; `name` is the dropped file's name (a refused file wears its extension in its fur).
    /// Call it before drawing the cat.
    func follow(_ f: USFrame, file name: String) {
        // The sequence's look is -1…1 with positive down; the engine's is positive up.
        engine.lookX = f.lookX
        engine.lookY = -f.lookY
        if f.dropped {
            if !dropped { dropped = true; engine.catchDrop() }                                                  // 2. snap wider, the file flies in
            if !arrived && f.t >= USC.T_SUCK_END {
                arrived = true
                if f.refused { engine.catchReject(CatFileRule.label(for: name)) } else { engine.catchArrive() }   // 3. gulp and 4. chew, or gag and cough
            }
            if !f.refused && !celebrated && f.t >= f.progEnd { celebrated = true; engine.emote("happy") }       // the upload is done
        } else {
            if dropped { dropped = false; arrived = false; celebrated = false; engine.catchOpen(false) }       // a new drag started
            engine.catchOpen(f.zoneOver)                                                                        // 1. open wide while the file hovers
        }
        engine.update(dt: CatEngine.frameDelta(now: engine.now() / 1000, last: engine.lastTime))
    }
}
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`** — replace:

```swift
    static let ENTRY_T_REF: Double = T_DROP - 0.40  // = 1.55
}
```

with:

```swift
    static let ENTRY_T_REF: Double = T_DROP - 0.40  // = 1.55
    // A refused file (CatFileRule: apps, archives, disk images, videos, over 25 MB) skips the chew, the bar and the check mark. It is caught like any
    // file; when it reaches the mouth the cat gags (it takes 120 ms to start heaving) and coughs it up as a hairball, which lasts 2.4 s (the spec). The
    // refusal note, the choose view, starts to appear when that is over, and the cat goes to its choose place. (A-tauri times its note the same way.)
    static let COUGH_LEAD_S:  Double = 0.12
    static let HAIRBALL_S:    Double = 2.40
    static let T_COUGH_END:   Double = T_SUCK_END + COUGH_LEAD_S + HAIRBALL_S   // 4.85: the note starts to appear
    static let T_REFUSE_DONE: Double = T_COUGH_END + 0.45                       // 5.30: the cat is at its choose place
}
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`** — replace:

```swift
    var zoneOver:    Bool   = false
    var zoneAlpha:   Double = 1
```

with:

```swift
    var zoneOver:    Bool   = false
    /// The file has been dropped (the post-drop timeline is running), as opposed to still being dragged over the island. `t` alone cannot say,
    /// because a long hover has no cap.
    var dropped:     Bool   = false
    /// The dropped file is one the cat refuses (decided at the drop): it is coughed up as a hairball instead of chewed.
    var refused:     Bool   = false
    var zoneAlpha:   Double = 1
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`** — replace:

```swift
    private var dropWallTime:  Double? = nil
```

with:

```swift
    private var dropWallTime:  Double? = nil
    /// The dropped file is one the cat refuses (CatFileRule), decided at the drop.
    private var refused = false
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`** — replace:

```swift
        entryWallTime = now
        dropWallTime  = nil
        isActive      = true
```

with:

```swift
        entryWallTime = now
        dropWallTime  = nil
        refused       = false
        isActive      = true
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`** — replace:

```swift
    func performDrop(uploadDuration ud: Double) {
        uploadDuration = ud
```

with:

```swift
    /// `refused`: the file is one the cat coughs up (CatFileRule), decided by the caller at the drop; the timeline then has no chew, no bar and no
    /// check mark (see `USC.T_COUGH_END`).
    func performDrop(uploadDuration ud: Double, refused isRefused: Bool = false) {
        uploadDuration = ud
        refused = isRefused
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`** — replace:

```swift
    func deactivate() {
        isActive = false
        dropWallTime = nil
    }
```

with:

```swift
    func deactivate() {
        isActive = false
        dropWallTime = nil
        refused = false
    }
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`** — replace:

```swift
    // MARK: - Frame computation (mirrors reference frame(t))
```

with:

```swift
    // MARK: - A refused file

    /// The frame of a refused file: the cat stays where it caught the file while it gags and coughs it up, then goes to its choose place. There is no
    /// chew, no progress bar, no check mark and no green wash, and the choose view with its refusal note starts to appear when the hairball is over.
    private func computeRefusedFrame(t: Double) -> USFrame {
        var f = USFrame()
        f.t = t
        f.cursorX = cursorX; f.cursorY = cursorY
        f.dropped = true; f.refused = true
        f.uploadDuration = 0
        f.progEnd = USC.T_COUGH_END; f.growStart = USC.T_COUGH_END; f.growEnd = USC.T_REFUSE_DONE   // `UploadCatDriver` reads `progEnd`
        let go = usEInOut(usSeg(t, USC.T_COUGH_END, USC.T_REFUSE_DONE))
        f.x = usLerp(sim.bx.v, USC.CHOOSE_X, go); f.y = usLerp(sim.by.v, USC.CHOOSE_Y, go)
        f.d = usLerp(USC.D_BOX, USC.CHOOSE_D, go)
        f.tilt = sim.tilt
        let looking = t < USC.T_SUCK_END
        f.lookX = looking ? max(-1, min(1, (cursorX - f.x) / 200)) : 0
        f.lookY = looking ? max(-1, min(1, ((cursorY + 10) - f.y) / 150)) : 0
        f.fileVisible = looking
        f.suck = usSeg(t, USC.T_SUCK_START, USC.T_SUCK_END)
        f.zoneOver = false
        f.zoneAlpha = 1 - usSeg(t, USC.T_CHEW_END, USC.T_CHEW_END + 0.20)
        f.textAlpha = f.zoneAlpha
        f.greenWash = 0.22 * (1 - usSeg(t, USC.T_DROP, USC.T_SUCK_END))   // the hover glow fades while the file flies in
        f.chooseAlpha = usSeg(t, USC.T_COUGH_END, USC.T_COUGH_END + 0.30)
        return f
    }

    // MARK: - Frame computation (mirrors reference frame(t))
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`** — replace:

```swift
        let entered    = sim.entered >= 0 ? sim.entered : 1e9
        let isDragging = (dropWallTime == nil)
```

with:

```swift
        let entered    = sim.entered >= 0 ? sim.entered : 1e9
        let isDragging = (dropWallTime == nil)
        if refused && !isDragging { return computeRefusedFrame(t: t) }
```

**Edit `NotchBuddy/Sources/App/UploadSequenceEngine.swift`** — replace:

```swift
        // Content alpha values
        f.zoneOver   = sim.entered >= 0 && pt < USC.T_CHEW_END
```

with:

```swift
        // Content alpha values
        f.dropped    = !isDragging
        f.zoneOver   = sim.entered >= 0 && pt < USC.T_CHEW_END
```

- [ ] **Step 4: Run the test**

Run: `bash scripts/test-cat-upload.sh`
Expected: PASS

- [ ] **Step 5: Draw the cat and the file in the drop view**

`drawMochi`, `drawEyeShape` and `usBodyPath` (the mailbox body and its hole) are replaced by `drawCat`, and the suction in `drawFile` by the contract's flight. Nothing else in `drawScene` changes. The cat is drawn first and the file after it, so the file is in front of the cat while it hovers and while it flies.

**Edit `NotchBuddy/Sources/App/UploadCanvasView.swift`** — replace:

```swift
    @ObservedObject var state: AppState
    @State private var fileIcon: NSImage? = nil

    private var engine: UploadSequenceEngine { .shared }
```

with:

```swift
    @ObservedObject var state: AppState
    @State private var fileIcon: NSImage? = nil
    @StateObject private var driver = UploadCatDriver(engine: .live())

    private var engine: UploadSequenceEngine { .shared }
```

**Edit `NotchBuddy/Sources/App/UploadCanvasView.swift`** — replace:

```swift
        // ── Mochi ─────────────────────────────────────────────────
        drawMochi(ctx: &c, f: f)

        // ── File / suction ────────────────────────────────────────
        if f.fileVisible { drawFile(ctx: &c, f: f) }
```

with:

```swift
        // ── The cat ───────────────────────────────────────────────
        let laid = drawCat(ctx: c, f: f)

        // ── The file: under the pointer while it hovers, then along the flight into the cat's mouth. Drawn after the cat, so in front of it, as in the prototype's catch.
        if f.fileVisible { drawFile(ctx: &c, f: f, cat: laid) }
```

**Edit `NotchBuddy/Sources/App/UploadCanvasView.swift`** — replace:

```swift
    // MARK: - Mochi (superellipse body + eyes + mouth)

    private func drawMochi(ctx: inout GraphicsContext, f: USFrame) {
        let R  = f.d / 2 / 1.04
        let m  = f.morph
        let mc = max(0, min(m, 1.0))

        var c = ctx
        c.concatenate(CGAffineTransform(translationX: CGFloat(f.x), y: CGFloat(f.y + f.hop)))
        c.concatenate(CGAffineTransform(rotationAngle: CGFloat(f.tilt)))
        c.concatenate(CGAffineTransform(scaleX: CGFloat(f.sx), y: CGFloat(f.sy)))

        let (bp, rx, ry) = usBodyPath(m: m, R: R)

        // ── Body gradient ──────────────────────────────────────────
        let bodyGrad = Gradient(stops:[
            .init(color: Color(hex:"#EDEDEF"), location:0),
            .init(color: Color(hex:"#C4C5CA"), location:1)
        ])
        c.fill(bp, with: .linearGradient(bodyGrad,
            startPoint:  CGPoint(x:  rx*0.7, y: -ry*0.9),
            endPoint:    CGPoint(x: -rx*0.8, y:  ry*0.9)))

        // ── Edge shadow ────────────────────────────────────────────
        let shadowGrad = Gradient(stops:[
            .init(color: .clear, location:0),
            .init(color: .clear, location:0.62),
            .init(color: Color.black.opacity(0.12), location:1)
        ])
        c.fill(bp, with: .radialGradient(shadowGrad,
            center: CGPoint(x:0,y:0), startRadius: CGFloat(R*0.2), endRadius: CGFloat(R*1.3)))

        // ── Top rim (box mode) ─────────────────────────────────────
        if mc > 0.3 {
            let rimAlpha = max(0, min(1, (mc-0.3)/0.7))
            var rimCtx = c
            rimCtx.clip(to: bp)
            var rim = Path()
            rim.move(to: CGPoint(x: -rx*0.72, y: -ry+0.9))
            rim.addLine(to: CGPoint(x: rx*0.72,  y: -ry+0.9))
            rimCtx.stroke(rim, with: .color(Color.white.opacity(0.6*rimAlpha)),
                          style: StrokeStyle(lineWidth:1.2, lineCap:.round))
        }

        // ── Mouth hole ─────────────────────────────────────────────
        let mh = f.mouth * R * mc
        if mh > 0.3 {
            let mw  = 2*rx - 0.24*R
            let mxO = CGFloat(-mw/2)
            let myO = CGFloat(-ry + 0.10*R)
            let mhr = CGFloat(min(mw/2, mh/2))
            var mCtx = c
            mCtx.clip(to: bp)
            let holeGrad = Gradient(stops:[
                .init(color: Color(red:0.012,green:0.012,blue:0.016), location:0),
                .init(color: Color(red:0.063,green:0.067,blue:0.078), location:1)
            ])
            let holePath = roundedRect(CGRect(x:mxO, y:myO, width:CGFloat(mw), height:CGFloat(mh)), r:Double(mhr))
            mCtx.fill(holePath, with: .linearGradient(holeGrad,
                startPoint: CGPoint(x:0, y:myO),
                endPoint:   CGPoint(x:0, y:myO+CGFloat(mh))))
            // Bottom lip
            if mh > 4 {
                var lip = Path()
                lip.move(to:    CGPoint(x:mxO+mhr,              y:myO+CGFloat(mh)+0.5))
                lip.addLine(to: CGPoint(x:mxO+CGFloat(mw)-mhr,  y:myO+CGFloat(mh)+0.5))
                mCtx.stroke(lip, with: .color(Color.white.opacity(0.55)),
                            style: StrokeStyle(lineWidth:1, lineCap:.round))
            }
        }

        // ── Eyes ───────────────────────────────────────────────────
        let ew = R * 0.25
        let eh = R * (0.62 - 0.16*mc)
        let ey = R * (0.02 + 0.28*mc)
        let sp = R * 0.30
        let lx = f.lookX * R * (0.34 - 0.08*mc)
        let ly = f.lookY * R * (0.16 - 0.09*mc)

        var eCtx = c
        eCtx.clip(to: bp)
        for sd in [-1.0, 1.0] {
            var ec = eCtx
            ec.concatenate(CGAffineTransform(translationX: CGFloat(sd*sp+lx), y: CGFloat(ey+ly)))
            drawEyeShape(ctx: &ec, shape: f.eye, w: CGFloat(ew), h: CGFloat(eh))
        }
    }

    // MARK: - Eye shapes

    private func drawEyeShape(ctx: inout GraphicsContext, shape: USEyeShape, w: CGFloat, h: CGFloat) {
        let ink = Color(red:0.055,green:0.059,blue:0.071)
        switch shape {
        case .pill:
            var p = Path()
            p.addRoundedRect(in: CGRect(x:-w/2, y:-h/2, width:w, height:h),
                             cornerSize: CGSize(width:w/2, height:w/2))
            ctx.fill(p, with: .color(ink))

        case .cup:
            // Flat top + semicircle bottom (cup shape)
            let hh = h * 0.55
            var p = Path()
            p.move(to: CGPoint(x:-w/2, y:-hh/2))
            p.addLine(to: CGPoint(x: w/2, y:-hh/2))
            p.addLine(to: CGPoint(x: w/2, y: hh/2-w/2))
            p.addArc(center: CGPoint(x:0, y:hh/2-w/2), radius:w/2, startAngle:.degrees(0), endAngle:.degrees(180), clockwise:false)
            p.closeSubpath()
            ctx.fill(p, with: .color(ink))

        case .content:
            // Upward arc (content / happy)
            var p = Path()
            p.addArc(center: CGPoint(x:0, y:-h*0.12), radius:w*0.85,
                     startAngle:.degrees(180*0.15), endAngle:.degrees(180*0.85), clockwise:false)
            ctx.stroke(p, with: .color(ink),
                       style: StrokeStyle(lineWidth:w*0.5, lineCap:.round))
        }
    }

    // MARK: - File / suction (drawFile port)

    private func drawFile(ctx: inout GraphicsContext, f: USFrame) {
        let cx = f.cursorX, cy = f.cursorY + 14
        if f.suck <= 0 {
            var fc = ctx; fc.opacity = 0.92
            drawDoc(ctx: &fc, cx: cx, cy: cy, wsc:1, hsc:1)
            return
        }

        let m   = f.mouthRect
        let W0  = 34.0, H0 = 42.0
        let p   = usEIn(f.suck)
        let topY = usLerp(cy - H0/2, m.y - 2, usEInOut(f.suck))
        let hs  = usLerp(1.08, 0.55, usEInOut(f.suck))
        let Hh  = H0 * hs
        let sc  = usLerp(1, 0.55, p)
        let q   = usEOut(f.suck)
        let fCx = usLerp(cx, m.x + m.w/2, usEOut(f.suck))
        let wob = sin(f.suck * .pi * 2) * 0.1 * (1-p)
        let clipY = m.y + m.h * 0.5

        // Use withCGContext for the complex strip clipping
        ctx.withCGContext { cg in
            cg.saveGState()
            // Outer clip: above mouth
            cg.clip(to: CGRect(x:0, y:0, width:640, height:clipY))

            for i in 0..<28 {
                let v0 = Double(i) / 28
                let wsc = usLerp(1, usLerp(0.92, 0.22*m.w/W0, pow(v0,1.2)), q) * sc
                let yy  = topY + v0*Hh
                let hh  = Hh/28 + 0.6

                cg.saveGState()
                cg.translateBy(x: CGFloat(fCx), y: CGFloat(yy))
                cg.rotate(by: CGFloat(wob))
                cg.clip(to: CGRect(x: CGFloat(-W0*wsc/2), y:0, width: CGFloat(W0*wsc), height: CGFloat(hh)))
                cg.translateBy(x: CGFloat(-fCx), y: CGFloat(-yy))
                drawDocCG(cg: cg, cx: fCx, cy: topY+Hh/2, wsc: wsc, hsc: hs, fileIcon: fileIcon)
                cg.restoreGState()
            }
            cg.restoreGState()
        }

        // Green particles
        for i in 0..<4 {
            let a   = Double(i)/4 * .pi*2 + 0.6
            let r0  = 24.0
            let k   = max(0, min(1, (f.suck - Double(i)*0.08) / 0.7))
            guard k > 0 && k < 1 else { continue }
            let sx0 = cx + cos(a)*r0, sy0 = cy + sin(a)*r0
            let ex  = m.x + m.w/2,    ey  = m.y + m.h*0.3
            let kk  = pow(k, 0.7)
            let px  = usLerp(sx0,ex,kk), py = usLerp(sy0,ey,kk) - sin(.pi*k)*6
            let rad = 2.2*(1-k*0.5)
            var pp = Path(); pp.addEllipse(in: CGRect(x:px-rad, y:py-rad, width:rad*2, height:rad*2))
            ctx.fill(pp, with: .color(Color(red:0.204,green:0.831,blue:0.600).opacity(1-k)))
        }
    }
```

with:

```swift
    // MARK: - The cat (the mouth catch)

    /// Draws the cat where the sequence puts it and returns its layout (the file's flight ends at the mouth in it). The driver steps the cat first.
    private func drawCat(ctx: GraphicsContext, f: USFrame) -> CatGeometry.Layout? {
        let cat = driver.engine
        driver.follow(f, file: state.droppedFile?.name ?? "file")
        var laid: CatGeometry.Layout?
        // The sequence's squeeze rides along once the cat is a dot on the progress bar; the catch's own squash does the rest.
        let squeezeX = f.t >= USC.T_SHRINK_END ? f.sx : 1, squeezeY = f.t >= USC.T_SHRINK_END ? f.sy : 1
        var look = cat.look()
        look.pose.sx *= squeezeX; look.pose.sy *= squeezeY; look.pose.tilt += f.tilt
        look.badge = nil
        ctx.withCGContext { cg in
            laid = CatRenderer.draw(cg, look, cx: f.x, cy: f.y + f.hop, D: f.d)
        }
        if let L = laid { cat.base = L.base; cat.mouthPoint = L.mouth }
        return laid
    }

    // MARK: - The file: under the pointer, then in flight

    /// While the file is still dragged over the island it sits under the pointer. After the drop it arcs into the cat's mouth along the contract's
    /// flight (`CatGreeting.flightAt`, 380 ms, from the drop to the arrival: `T_DROP` to `T_SUCK_END`), in front of the cat, as in the prototype. The
    /// icon leaves the pointer at the size it had there and shrinks as the flight does, so it does not jump.
    private func drawFile(ctx: inout GraphicsContext, f: USFrame, cat L: CatGeometry.Layout?) {
        let cx = f.cursorX, cy = f.cursorY + 14
        guard f.dropped else {
            var fc = ctx; fc.opacity = 0.92
            drawDoc(ctx: &fc, cx: cx, cy: cy, wsc: 1, hsc: 1)
            return
        }
        guard let L, let m = L.mouth, L.R > 0 else { return }
        let w = CatGreeting.flightAt(from: (x: cx, y: cy), to: (x: m.x, y: m.y), R: L.R, k: usSeg(f.t, USC.T_DROP, USC.T_SUCK_END))
        let s = w.size / (0.62 * L.R)   // the flight shrinks the file from 0.62 R to 0.14 R: 1 down to 0.23 of its size under the pointer
        let icon = fileIcon
        ctx.withCGContext { cg in
            cg.saveGState()
            cg.translateBy(x: w.x, y: w.y)
            cg.rotate(by: w.rot)
            cg.translateBy(x: -w.x, y: -w.y)
            drawDocCG(cg: cg, cx: w.x, cy: w.y, wsc: s, hsc: s, fileIcon: icon)
            cg.restoreGState()
        }
    }
```

**Edit `NotchBuddy/Sources/App/UploadCanvasView.swift`** — replace:

```swift
// MARK: - Doc icon in CGContext (for suction strips)
```

with:

```swift
// MARK: - Doc icon in CGContext (for the file in flight)
```

**Edit `NotchBuddy/Sources/App/UploadCanvasView.swift`** — replace:

```swift
// MARK: - Superellipse body path (port of reference bodyPath(m, R))

func usBodyPath(m: Double, R: Double) -> (path: Path, rx: Double, ry: Double) {
    let mc = max(0, min(m, 1.0))
    let n  = 2.15 + (5.5-2.15)*mc
    let rx = R * (1.04 - 0.04*mc)
    let ry = R * (0.97 - 0.03*mc)
    var path = Path()
    for i in 0...96 {
        let a  = Double(i)/96 * .pi*2
        let ca = cos(a), sa = sin(a)
        let px = rx * (ca<0 ? -1 : ca>0 ? 1 : 0) * pow(abs(ca), 2/n)
        let py = ry * (sa<0 ? -1 : sa>0 ? 1 : 0) * pow(abs(sa), 2/n)
        if i == 0 { path.move(to:    CGPoint(x:px,y:py)) }
        else       { path.addLine(to: CGPoint(x:px,y:py)) }
    }
    path.closeSubpath()
    return (path, rx, ry)
}

// MARK: - Rounded rect helper (mirrors reference rr())
```

with:

```swift
// MARK: - Rounded rect helper (mirrors reference rr())
```

- [ ] **Step 6: Decide the refusal at the drop, and move the approve chime**

**Edit `NotchBuddy/Sources/App/FileDropView.swift`** — replace:

```swift
        guard let url = urls.first else { return }
        let name = url.lastPathComponent
```

with:

```swift
        guard let url = urls.first else { return }
        let name = url.lastPathComponent

        // Is it a file the cat coughs up? Decided here, at the drop, from what is known now (the extension and the size): the app's own refusal
        // rule, not the AI reader's verdict at the end of the upload sequence.
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let refused = CatFileRule.refused(ext: url.pathExtension, size: bytes)
```

**Edit `NotchBuddy/Sources/App/FileDropView.swift`** — replace:

```swift
        UploadSequenceEngine.shared.performDrop(uploadDuration: dur)
```

with:

```swift
        UploadSequenceEngine.shared.performDrop(uploadDuration: dur, refused: refused)
```

**Edit `NotchBuddy/Sources/App/FileDropView.swift`** — replace:

```swift
        // Drop feedback
        NotificationCenter.default.post(name: .botGulp, object: nil)
        SoundEngine.shared.play("approve")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(0))

        state.uploadDuration = dur
        state.uploadStartTime = Date()
        state.view = .uploading  // canvas stays active: uploadActive covers .uploading
```

with:

```swift
        // Drop feedback. The `approve` chime no longer plays here, for any file: it plays when the file turns out to be readable (at the check mark,
        // below), so a refused file never gets it. A refused file gets no gulp and no happy cat either: the cat gags instead.
        if !refused {
            NotificationCenter.default.post(name: .botGulp, object: nil)
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        }
        NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(0))

        state.uploadDuration = dur
        state.uploadStartTime = refused ? nil : Date()   // nothing uploads for a refused file
        state.view = .uploading  // canvas stays active: uploadActive covers .uploading

        if refused {
            // No progress bar, no tick sounds, no check mark and no `approve` chime. The cat caught the file like any file; when it arrives the cat
            // gags and coughs it up as a hairball (USC.COUGH_LEAD_S + USC.HAIRBALL_S), and then the choose view shows the reader line that says why
            // the file cannot be read (`state.dropReaderLine`, set by `prepareAttachment`).
            // The sounds: `annoyed`, once, as the gag starts (the file has reached the mouth) and nothing after it: the hairball and the choose
            // view's note are silent. Sound Stage 3 wires the `pop` at the cough; it is not added here.
            try? await Task.sleep(nanoseconds: UInt64((USC.T_SUCK_END - USC.T_DROP) * 1_000_000_000))
            SoundEngine.shared.play("annoyed")   // the gag
            try? await Task.sleep(nanoseconds: UInt64((USC.T_REFUSE_DONE - USC.T_SUCK_END + 0.3) * 1_000_000_000))
            state.uploadProgress = 0
            state.view = .choose   // the note: no sound
            return
        }
```

**Edit `NotchBuddy/Sources/App/FileDropView.swift`** — replace:

```swift
        // Canvas shows checkmark at this point
        SoundEngine.shared.play("approve")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
```

with:

```swift
        // Canvas shows checkmark at this point. The file is taken once the AI's reader has read it: that is when the `approve` chime plays. (A
        // file the reader cannot read has no chime; it ends with the annoyed cat below, as before.)
        if !state.dropRejected { SoundEngine.shared.play("approve") }
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
```

**Edit `NotchBuddy/Sources/App/FileDropView.swift`** — replace:

```swift
        // A file the AI can't take: the cat's reject (the hairball hooks onto .botReject).
        if state.dropRejected {
            SoundEngine.shared.play("annoyed")
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.annoyed)
            NotificationCenter.default.post(name: .botReject, object: url.pathExtension.lowercased())
        }
```

with:

```swift
        // Any other file the AI can't take (unreadable, a copy error, a folder) keeps this ending: the sound and the annoyed cat, and no hairball.
        // The hairball is only for the refused files above, decided at the drop.
        if state.dropRejected {
            SoundEngine.shared.play("annoyed")
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.annoyed)
        }
```

- [ ] **Step 7: Add the catch sheet**

**Edit `scripts/render-cats.swift`** — replace:

```swift
//   bash scripts/render-cats.sh --mouths --cats momo               the six mouth values: closed, smile, frown, tongue, round, wavy, skew, open
//   bash scripts/render-cats.sh --greeting --cats shrimpy          the launch greeting at its beats, island and cat
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

@main
```

with:

```swift
//   bash scripts/render-cats.sh --mouths --cats momo               the six mouth values: closed, smile, frown, tongue, round, wavy, skew, open
//   bash scripts/render-cats.sh --greeting --cats shrimpy          the launch greeting at its beats, island and cat
//   bash scripts/render-cats.sh --catch --cats shrimpy             the four-step file catch, and a refused file coughed up as a hairball
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

@main
```

**Edit `scripts/render-cats.swift`** — replace:

```swift
        case emotes, mouths
        case greeting
    }

    struct Args {
```

with:

```swift
        case emotes, mouths
        case greeting
        case catchSheet
    }

    struct Args {
```

**Edit `scripts/render-cats.swift`** — replace:

```swift
            case "--mouths": a.mode = .mouths
            case "--greeting": a.mode = .greeting
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

with:

```swift
            case "--mouths": a.mode = .mouths
            case "--greeting": a.mode = .greeting
            case "--catch": a.mode = .catchSheet
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

**Edit `scripts/render-cats.swift`** — replace:

```swift
        case .mouths: sheet = mouths(a)
        case .greeting: sheet = greeting(a)
        }
        sheet.write(to: a.out)
```

with:

```swift
        case .mouths: sheet = mouths(a)
        case .greeting: sheet = greeting(a)
        case .catchSheet: sheet = catchSheet(a)
        }
        sheet.write(to: a.out)
```

**Edit `scripts/render-cats.swift`** — replace:

```swift
    }


    // MARK: The launch greeting at its beats
```

with:

```swift
    }

    // MARK: The file catch: taken, and refused

    @MainActor static func catchSheet(_ a: Args) -> Sheet {
        let cell = 200.0, labelW = 130.0
        let taken = ["hovering: mouth wide", "dropped: snaps wider", "the file flies in", "gulp", "chew", "lick"]
        let refused = ["hovering: mouth wide", "dropped: snaps wider", "the file flies in", "gags", "coughs it up", "rolls away"]
        let sheet = Sheet(width: labelW + cell * 6 + 8, height: (cell + 20) * Double(a.cats.count * 2) + 8, scale: a.scale)
        let cg = sheet.cg
        var row = 0
        for id in a.cats {
            let preset = CatPresets.byID(id)
            for isRefused in [false, true] {
                let top = 4 + Double(row) * (cell + 20)
                CatDraw.text(cg, "\(preset.label) · \(isRefused ? "refused file" : "taken file")", x: 62, y: top + cell / 2, size: 12, bold: true, color: CatDraw.white(0.85))
                for (ci, label) in (isRefused ? refused : taken).enumerated() {
                    let (e, clock, step) = scene(preset, profile: "playful", D: 110, quiet: true)
                    func run(_ ms: Double) { for _ in 0..<Int((ms / (1000.0 / 60)).rounded()) { step() } }
                    let x = labelW + Double(ci) * cell, cx = x + cell / 2, cy = top + cell * 0.6
                    e.catchOpen(true); run(500)
                    var fileK: Double?                                    // where the file is along its flight, if it is in the air
                    if ci == 0 { fileK = nil }
                    if ci >= 1 { e.catchDrop(); run(ci == 1 ? 100 : 380); fileK = ci == 1 ? 0.25 : 1 }
                    if ci == 2 { e.catchDrop(); fileK = 0.75 }
                    if ci >= 3 {
                        if isRefused { e.catchReject("EXE") } else { e.catchArrive() }
                        run([100.0, 500, 1000][min(ci - 3, 2)] + (isRefused ? [500.0, 800, 1100][min(ci - 3, 2)] : 0))
                        fileK = nil
                    }
                    cg.saveGState()
                    cg.clip(CatDraw.roundRect(x + 3, top + 3, cell - 6, cell - 6, 12))
                    cg.fill(CatDraw.roundRect(x, top, cell, cell, 0), CatDraw.black(1))
                    let L = CatRenderer.draw(cg, e.look(time: clock.t / 1000), cx: cx, cy: cy, D: 110, CatDrawOptions(glow: true))
                    if let k = fileK, let m = L.mouth {
                        let w = CatGreeting.flightAt(from: (x: cx + 70, y: top + 24), to: (x: m.x, y: m.y), R: L.R, k: k)
                        CatEffects.drawFile(cg, x: w.x, y: w.y, size: w.size, rot: w.rot, ext: isRefused ? "EXE" : "PDF")
                    }
                    cg.restoreGState()
                    CatDraw.text(cg, label, x: cx, y: top + cell + 9, size: 10, bold: false, color: CatDraw.white(0.55))
                }
                row += 1
            }
        }
        return sheet
    }

    // MARK: The launch greeting at its beats
```

Run: `bash scripts/render-cats.sh --catch --cats shrimpy,momo --scale 1 --out "${TMPDIR:-/tmp}/a-mac-sheets/stage4-catch.png"`
Expected: PASS

Open `stage4-catch.png`. Each coat has two rows. **Taken file:** the mouth is open wide with wide eyes while the file hovers; it snaps wider on the drop; the file flies in (a small file icon arcs to the mouth); a gulp with a squash and happy eyes; a chew with blush; a lick. **Refused file:** the same three steps, then the cat gags (ears back, closed eyes, heaving), coughs up a hairball with the file wrapped in fur, and the ball rolls away.

- [ ] **Step 8: The cat panel throws files too**

The panel's File row throws a PDF, an app and a 30 MB file at the stage cat with the same rule and the same timeline (the file drops 0.42 s after the mouth opens, flies for 380 ms, then the cat chews it or coughs it up), so the owner can watch a taken file and a refused one, in either motion style and for any coat, without a real drop. The model's timeline runs from `advance()`, which the stage cat's cell calls once per frame. The test comes first; the scripts that compile the model learn about the rule.

**Edit `tests/CatDevModelTests.swift`** — replace:

```swift
        CT.section("the greeting's cat is the chosen cat")
```

with:

```swift
        CT.section("a thrown file: the app's own rule decides at the drop, the flight is 380 ms, and the cat chews it or coughs it up")
        for (name, size, refused) in [("notes.pdf", 80_000, false), ("setup.exe", 5_000_000, true), ("clip.mov", 5, true), ("export.txt", 30 * 1_048_576, true), ("exactly.txt", 26_214_400, false), ("folder", 0, false)] {
            let t = model()
            t.pick(coat: "momo")
            t.catchFile(named: name, size: size)
            CT.checkTrue("\(name): the cat opens wide at once", t.stage.catching)
            clock.t += 100; t.advance()
            CT.checkTrue("\(name): the file has not dropped at 0.1 s", t.flight == nil)
            clock.t += 400; t.advance()
            CT.checkTrue("\(name): it dropped at 0.42 s and is in flight, refused or not as the rule says", t.flight != nil && t.flight?.refused == refused)
            CT.checkTrue("\(name): the flight is under way", (t.flightProgress ?? -1) >= 0 && (t.flightProgress ?? 2) < 1)
            clock.t += CatEngine.flightMs + 10; t.advance()
            CT.checkTrue("\(name): it lands after 380 ms", t.flight == nil && t.flightProgress == nil)
            for _ in 0..<150 { clock.t += 1000.0 / 60; t.stage.update(dt: 1.0 / 60) }
            CT.check("\(name): a refused file is coughed up as a hairball, a taken one chewed", [t.notes.contains("hairball"), t.stage.chewUntil > 0], [refused, !refused])
        }
        CT.check("the panel offers a PDF, an app and a 30 MB file", CatDevModel.files.map(\.name), ["notes.pdf", "setup.exe", "export.txt"])
        CT.check("and the app's rule refuses the last two", CatDevModel.files.map { CatFileRule.refused(ext: ($0.name as NSString).pathExtension, size: $0.size) }, [false, true, true])

        CT.section("the greeting's cat is the chosen cat")
```

**Edit `scripts/test-cat-devpanel.sh`** — replace:

```bash
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatDevModel.swift \
```

with:

```bash
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatFileRule.swift $APP/CatDevModel.swift \
    $APP/AI/Core/Attachments.swift $APP/AI/Core/AICatalog.swift $APP/AI/Core/ModelProvider.swift $APP/AI/Core/ContextBudget.swift \
```

Run: `bash scripts/test-cat-devpanel.sh`
Expected: FAIL (`CatDevModel` has no member `catchFile`)

**Edit `NotchBuddy/Sources/App/CatDevModel.swift`** — replace:

```swift
    /// The emotes of the contract, in the spec's order.
```

with:

```swift
    /// The files the panel can throw at the stage cat: a name and a size, so that the app's own rule (`CatFileRule`) decides what happens, as at a real drop.
    static let files: [(label: String, name: String, size: Int)] = [
        ("A PDF", "notes.pdf", 80_000), ("An app (.exe)", "setup.exe", 5_000_000), ("A 30 MB file", "export.txt", 30 * 1_048_576),
    ]
    /// The emotes of the contract, in the spec's order.
```

**Edit `NotchBuddy/Sources/App/CatDevModel.swift`** — replace:

```swift
    /// Plays an emote on the stage cat (an unknown name is ignored by the engine).
```

with:

```swift
    /// A file thrown at the stage cat. Not published: `advance()` changes it while a frame is drawn.
    struct Flight: Equatable { var ext: String; var refused: Bool; var dropAt: Double }
    private(set) var flight: Flight?
    private var pending: (at: Double, ext: String, refused: Bool)?

    /// The file's name and size decide, as at a real drop: the stage cat opens wide, the file drops 0.42 s later and flies in over `CatEngine.flightMs`,
    /// and when it arrives the cat chews it or, for a refused file, gags and coughs it up as a hairball.
    func catchFile(named name: String, size: Int) {
        pending = (now() + 420, CatFileRule.label(for: name), CatFileRule.refused(ext: (name as NSString).pathExtension, size: size))
        flight = nil
        stage.catchOpen(true)
    }

    /// Once per frame, before the stage cat updates: drops the file when its time has come, and lands it.
    func advance() {
        let t = now()
        if let p = pending, t >= p.at {
            pending = nil
            stage.catchDrop()
            flight = Flight(ext: p.ext, refused: p.refused, dropAt: t)
        }
        if let f = flight, t - f.dropAt >= CatEngine.flightMs {
            flight = nil
            if f.refused { stage.catchReject(f.ext) } else { stage.catchArrive() }
        }
    }

    /// How far the flying file is along its flight, 0 to 1; nil when no file is in the air.
    var flightProgress: Double? { flight.map { clamp((now() - $0.dropAt) / CatEngine.flightMs, 0, 1) } }

    /// Plays an emote on the stage cat (an unknown name is ignored by the engine).
```

**Edit `NotchBuddy/Sources/App/CatDevModel.swift`** — replace:

```swift
        stage = make(p, state: state)
        stage.onNote = { [weak self] _, event in self?.record(event) }
```

with:

```swift
        pending = nil
        flight = nil
        stage = make(p, state: state)
        stage.onNote = { [weak self] _, event in self?.record(event) }
```

Run: `bash scripts/test-cat-devpanel.sh`
Expected: PASS

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`** — replace:

```swift
    let pointer: CGPoint?
    var tint = true

    var body: some View {
        GeometryReader { geo in
```

with:

```swift
    let pointer: CGPoint?
    var tint = true
    /// Called once per frame before the cat updates (the stage cat's file lands from here).
    var onFrame: (() -> Void)?
    /// Drawn over the cat, in front of it, after its whole draw (the flying file).
    var overlay: ((CGContext, CatGeometry.Layout) -> Void)?

    var body: some View {
        GeometryReader { geo in
```

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`** — replace:

```swift
                    engine.lookX = gaze.x
                    engine.lookY = gaze.y
```

with:

```swift
                    onFrame?()
                    engine.lookX = gaze.x
                    engine.lookY = gaze.y
```

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`** — replace:

```swift
                            engine.base = L.base
                            engine.mouthPoint = L.mouth
                        }
```

with:

```swift
                            engine.base = L.base
                            engine.mouthPoint = L.mouth
                            overlay?(cg, L)
                        }
```

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`** — replace:

```swift
                CatDevCell(engine: model.stage, D: model.size, width: 360, height: 280, pointer: pointer, tint: model.tint)
```

with:

```swift
                CatDevCell(engine: model.stage, D: model.size, width: 360, height: 280, pointer: pointer, tint: model.tint,
                           onFrame: { model.advance() },
                           overlay: { cg, L in
                               // The thrown file, along the contract's flight, in front of the cat (the drop view draws it the same way).
                               guard let k = model.flightProgress, let f = model.flight, let m = L.mouth else { return }
                               let w = CatGreeting.flightAt(from: (x: 360 * 0.86, y: 280 * 0.14), to: (x: m.x, y: m.y), R: L.R, k: k)
                               CatEffects.drawFile(cg, x: w.x, y: w.y, size: w.size, rot: w.rot, ext: f.ext)
                           })
```

**Edit `NotchBuddy/Sources/App/CatDevPanel.swift`** — replace:

```swift
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text("What it just did: "
```

with:

```swift
                Text("File")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                ChoiceGrid(items: CatDevModel.files.map { ($0.name, $0.label) }, selected: nil) { name in
                    if let f = CatDevModel.files.first(where: { $0.name == name }) { model.catchFile(named: f.name, size: f.size) }
                }
                Text("The app's own rule decides at the drop: the cat chews a PDF, and coughs the app and the big file up as a hairball.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text("What it just did: "
```

**Edit `scripts/render-cat-panel.sh`** — replace:

```bash
    $APP/CatDevModel.swift $APP/CatDevPanel.swift \
```

with:

```bash
    $APP/CatFileRule.swift $APP/AI/Core/Attachments.swift $APP/AI/Core/AICatalog.swift $APP/AI/Core/ModelProvider.swift $APP/AI/Core/ContextBudget.swift \
    $APP/CatDevModel.swift $APP/CatDevPanel.swift \
```

Run: `bash scripts/render-cat-panel.sh --out "${TMPDIR:-/tmp}/a-mac-sheets/stage4-panel-files.png" --height 1500`
Expected: PASS

- [ ] **Step 9: Build the app**

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO`
Expected: PASS

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Debug/NotchMeow.app debug`
Expected: PASS

- [ ] **Step 10: Read the diff for what the build cannot say**

Check by reading:
- `driver.follow(f, file:)` runs once per drawn frame, before `CatRenderer.draw`; `drawFile` is called after `drawCat`, with the layout `drawCat` returned, and only while `f.fileVisible`; the progress bar and the choose view are untouched.
- In `FileDropHandler.handle` the refusal is decided first, from `CatFileRule`; a refused file returns before the tick sounds, the progress wait and the check mark; `approve` is not posted at the drop any more and plays at the check mark only when `!state.dropRejected`; `.botReject` is not posted; the end of the function (the `annoyed` sound and the annoyed cat for `state.dropRejected`) is as it was.
- The sounds of a refused file: `grep -n 'SoundEngine.shared.play' NotchBuddy/Sources/App/FileDropView.swift` prints four lines, in this order: `annoyed` (the gag: the only sound inside `if refused { ... return }`, once, with `state.view = .choose` after it and nothing else), `tick` (the progress ticks), `approve` (the check mark, guarded by `!state.dropRejected`) and `annoyed` (any other failure). `approve` is not before the `if refused` branch, and nothing in the branch plays `pop`: sound Stage 3 adds it.
- The old `morph`, `cup`, `mouth`, `mouthRect` and `suck` fields of `USFrame` are still computed and no longer read for drawing (stage 7 removes them with the other dead code); `usBodyPath` is gone; nothing under `AI/` changed (`git diff --stat notchmeow/rebrand -- NotchBuddy/Sources/App/AI` prints nothing).

- [ ] **Step 11: Commit**

```bash
git add tests/UploadCatDriverTests.swift scripts/test-cat-upload.sh tests/CatDevModelTests.swift scripts/test-cat-devpanel.sh scripts/render-cat-panel.sh scripts/render-cats.swift NotchBuddy/Sources/App/CatFileRule.swift NotchBuddy/Sources/App/UploadCatDriver.swift NotchBuddy/Sources/App/UploadSequenceEngine.swift NotchBuddy/Sources/App/UploadCanvasView.swift NotchBuddy/Sources/App/FileDropView.swift NotchBuddy/Sources/App/CatDevModel.swift NotchBuddy/Sources/App/CatDevPanel.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(cat): the drop view is the cat's mouth catch, a refused file is decided at the drop and coughed up as a hairball, and the cat panel throws files

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 15: CI, docs and the final checks (stage 4, and the end of this plan)

Agent: `nm-implementer-light`.

**Files:**
- Modify: `.github/workflows/build.yml`, `CLAUDE.md`, `ARCHITECT.md`

**Interfaces:**
- Consumes: every `scripts/test-cat-*.sh` of Tasks 1 to 14, and `scripts/check-app-binary.sh` (Task 9).
- Produces: one CI step per cat test script, next to the cat contract step A-0 added; one pointer in each of `CLAUDE.md` and `ARCHITECT.md`, neutral about Windows (the Windows plan owns the Windows lines of both).
- The Release build that CI already runs ends with `check-app-binary.sh ... release`, which since Task 9 also fails if the Debug-only cat panel is in it.

- [ ] **Step 1: One CI step per test script**

Read the real `.github/workflows/build.yml` first. Other branches add steps to the same list (C1 added "Sound build tests", A-0 added "Cat contract" together with `actions/setup-node`, and E1 and C1b add more), so this edit anchors on the "Cat contract" step alone: its two lines are unique, and nothing around them is part of the anchor.

**Edit `.github/workflows/build.yml`** — replace:

```yaml
      - name: Cat contract (cat-core.js self-checks, fixtures, determinism)
        run: bash scripts/test-cat-contract.sh
```

with:

```yaml
      - name: Cat contract (cat-core.js self-checks, fixtures, determinism)
        run: bash scripts/test-cat-contract.sh

      - name: Cat presets
        run: bash scripts/test-cat-presets.sh

      - name: Cat geometry and the face warp
        run: bash scripts/test-cat-geometry.sh

      - name: Cat drawing kit and effects
        run: bash scripts/test-cat-effects.sh

      - name: Cat renderer
        run: bash scripts/test-cat-renderer.sh

      - name: Cat personality
        run: bash scripts/test-cat-personality.sh

      - name: Cat rules (zoomies, sleep, search tools)
        run: bash scripts/test-cat-rules.sh

      - name: Cat engine (states, emotes, the file catch)
        run: bash scripts/test-cat-engine.sh

      - name: Cat frame-time meter
        run: bash scripts/test-cat-frame-meter.sh

      - name: Cat greeting timeline
        run: bash scripts/test-cat-greeting.sh

      - name: Cat in the drop view (the refusal rule, the catch, a refused file)
        run: bash scripts/test-cat-upload.sh

      - name: Cat panel model (Debug-only panel)
        run: bash scripts/test-cat-devpanel.sh
```

- [ ] **Step 2: Point the docs at the new files, without saying anything about Windows**

The Windows plan owns the Windows lines of both guides: its edit of `ARCHITECT.md` replaces the line that says what Windows draws, and its edit of `CLAUDE.md` adds a pointer under the `windows/` line. So this plan's edits touch other lines, and the Windows line it leaves is the original fact, worded neutrally (no claim about what lands when).

**Edit `CLAUDE.md`** — replace:

```markdown
- `design/prototype/cat-core.js` — everything pure about the cats (presets, face warp, motion, personality, greeting, zoomies and sleep rules), shared by the prototype page and Node. `tests/fixtures/cat/` is generated from it and both apps test against it (`docs/CAT-CONTRACT.md`). If an app and a fixture disagree, `cat-core.js` decides. After changing it, run `node scripts/gen-cat-fixtures.mjs` and commit the fixtures.
```

with:

```markdown
- `design/prototype/cat-core.js` — everything pure about the cats (presets, face warp, motion, personality, greeting, zoomies and sleep rules), shared by the prototype page and Node. `tests/fixtures/cat/` is generated from it and both apps test against it (`docs/CAT-CONTRACT.md`). If an app and a fixture disagree, `cat-core.js` decides. After changing it, run `node scripts/gen-cat-fixtures.mjs` and commit the fixtures.
- `NotchBuddy/Sources/App/Cat*.swift`, `Personality.swift`, `MotionProfiles.swift` — the Mac cats (they replace the old `BotEngine`): `CatPresets` (the 16 coats), `CatGeometry` (pose, face warp, layout), `CatEngine` and the profiles (states, emotes, ears, mouth), `CatRenderer`/`CatFace`/`CatEffects` (drawing into a `CGContext`), `CatGreeting` (the launch greeting), `CatFileRule` (which dropped files the cat coughs up). All of it except the drawing is tested against `tests/fixtures/cat/` by `scripts/test-cat-*.sh`. `bash scripts/render-cats.sh` renders contact sheets without launching the app. A Debug build has a "Cats (Debug)…" item in the menu bar's menu (`CatDevPanel.swift`): every coat, size, state, emote, personality and motion style live. It is compiled out of Release and App Store builds (`scripts/check-app-binary.sh` proves it); `bash scripts/render-cat-panel.sh` draws it into a PNG.
```

**Edit `ARCHITECT.md`** — replace:

```markdown
   - **Today:** the upstream engine draws it (`BotEngine.swift`, `windows/src/mochi/`).
```

with:

```markdown
   - **macOS:** `CatEngine` (with the Playful and Classic motion profiles in `MotionProfiles.swift`) animates a `CatPreset`; `CatRenderer` draws it into a `CGContext` inside the existing canvases (`BotCanvasView`, `MiniBotCanvasView`, `GreetingCanvasView`, `UploadCanvasView`). It replaces `BotEngine.swift`. A file the app refuses is decided at the drop (`CatFileRule`) and coughed up as a hairball. The Debug-only cat panel (`CatDevPanel.swift`) is not in Release or App Store builds.
   - **Windows:** the upstream engine still draws it (`windows/src/mochi/`).
```

- [ ] **Step 3: Run every cat test, the contract and the log check**

Run: `bash scripts/test-cat-contract.sh && bash scripts/test-cat-presets.sh && bash scripts/test-cat-geometry.sh && bash scripts/test-cat-effects.sh && bash scripts/test-cat-renderer.sh && bash scripts/test-cat-personality.sh && bash scripts/test-cat-rules.sh && bash scripts/test-cat-engine.sh && bash scripts/test-cat-frame-meter.sh && bash scripts/test-cat-greeting.sh && bash scripts/test-cat-upload.sh && bash scripts/test-cat-devpanel.sh && bash scripts/check-test-logs.sh`
Expected: PASS

- [ ] **Step 4: Run the Mac tests that were already there**

Every test script exports `NM_LOG_DIR` to a temporary folder itself; `check-test-logs.sh` fails if one did not.

Run: `for t in scripts/test-*.sh; do case "$t" in scripts/test-cat-*) continue;; esac; bash "$t" || exit 1; done`
Expected: PASS

- [ ] **Step 5: Build the targets as CI does, and prove where the cat panel is**

The Release build needs `CODE_SIGNING_ALLOWED=NO` (there is no signing identity on a build machine), and the App Store target compiles the same sources with `APPSTORE` set (the plan-gauge colour code in `BotCanvasView` is behind `#if !APPSTORE`, and the cat panel is behind `#if DEBUG && !APPSTORE`). The App Store target gets a folder of its own inside `NotchBuddy/build/`, which git ignores.

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO`
Expected: PASS

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Debug/NotchMeow.app debug`
Expected: PASS

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
Expected: PASS

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Release/NotchMeow.app release`
Expected: PASS

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO`
Expected: PASS

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/store/Build/Products/Debug/NotchMeow.app appstore`
Expected: PASS

The Release app has no `Cats (Debug)…` item, no `CatDev*` symbol and no `NM_CAT_DEV_PANEL` string, so these three checks together are the proof that the panel is Debug-only.

- [ ] **Step 6: Nothing of the old character is left, and nothing was touched that must not be**

Run: `test ! -e NotchBuddy/Sources/App/BotEngine.swift && ! grep -rn "BotEngine" NotchBuddy/Sources/App/*.swift | grep -v "IslandWindowController.swift"`
Expected: PASS

Run: `test -z "$(git diff --stat notchmeow/rebrand -- NotchBuddy/Sources/App/HookServer.swift NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/IslandStateMachine.swift NotchBuddy/Sources/App/IslandWindowController.swift NotchBuddy/Sources/App/PillCatalog.swift NotchBuddy/Sources/App/AI windows design/prototype tests/fixtures)"`
Expected: PASS

(That also proves the AI code, the contract's `cat-core.js` and every fixture are as the base has them: this plan only reads them.)

(`IslandWindowController.swift` keeps two comments that say `BotEngine`; it also belongs to another branch, so the stage-7 rename sweep takes them.)

- [ ] **Step 7: Render the final sheets and the frame-time numbers**

Run: `d="${TMPDIR:-/tmp}/a-mac-sheets"; mkdir -p "$d" && bash scripts/render-cats.sh --out "$d/final-ladder.png" && bash scripts/render-cats.sh --states --cats shrimpy,momo --scale 1 --out "$d/final-states.png" && bash scripts/render-cats.sh --emotes --cats shrimpy,momo --scale 1 --out "$d/final-emotes.png" && bash scripts/render-cats.sh --mouths --cats momo,shrimpy --scale 1 --out "$d/final-mouths.png" && bash scripts/render-cats.sh --greeting --cats shrimpy,momo --scale 1 --out "$d/final-greeting.png" && bash scripts/render-cats.sh --catch --cats shrimpy,momo --scale 1 --out "$d/final-catch.png" && bash scripts/render-cat-panel.sh --out "$d/final-panel.png" --height 2400 && RENDER_CATS_OPT=1 bash scripts/render-cats.sh --bench`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add .github/workflows/build.yml CLAUDE.md ARCHITECT.md
git commit -m "ci(cat): run the cat test programs in CI; point CLAUDE.md and ARCHITECT.md at the Mac cats

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

- [ ] **Step 9: Whole-branch review**

Dispatch `nm-reviewer-deep` on `git diff notchmeow/rebrand...a-mac/stages-1-4`. Give it the spec, this plan and the Review Focus. It should read for: any stale `BotEngine` or `Mochi` identifier in the files this plan touches; drawing constants that differ from the prototype (compare `CatRenderer.swift`, `CatFace.swift` and `CatEffects.swift` against `design/prototype/notchmeow.html`); that no view's layout or style changed; that the engine still has no timer; that everything of the cat panel is inside `#if DEBUG && !APPSTORE` (including its menu item and window in `AppDelegate.swift`); that a refused file is decided in `FileDropHandler` before anything else, never plays `approve`, has no check mark and no tick sounds, plays `annoyed` once as the gag starts and nothing after it (its note is silent, no `pop`), and that every other failure keeps today's ending and sound; that the file is drawn after the cat.

- [ ] **Step 10: Owner checkpoint 2, and the manual checks only the owner can do**

Send the owner the seven `final-*.png` sheets (ladder, states, emotes, mouths, greeting, catch and the cat panel) next to the prototype page, and ask them to run the Debug build (`NotchBuddy/build/Build/Products/Debug/NotchMeow.app`; quit the installed app first) and check:

1. Every state, driven through the socket (parent spec, Verification): idle, working, thinking, approval (the hop and the `!` badge), question, error (the hiss, then a hairball in Playful), finished, ratelimit, sleeping, dizzy.
2. Hover the cat's head (love), poke it (annoyed), poke it three times fast (dizzy, then happy when it recovers).
3. CPU with the island hidden, in Activity Monitor: 0 %. The frame-time readout: `tail -f ~/Library/Logs/NotchMeow/cat-frames.log` while several agents are running; the average should stay under 2 ms.
4. The compact notch on a Mac with a notch and on one without: the ears are not cut off at the top of the screen while the cat hops for an approval; the badge sits on the left.
5. A real file drop: the mouth opens wide while the file hovers (the icon is in front of the cat), snaps wider on the drop, the file flies into the mouth, the cat gulps and chews, and the `approve` chime plays at the check mark and not at the drop. A refused file (a `.zip`, a `.dmg`, a video, or a file over 25 MB): the same up to the arrival, then the cat gags and coughs up a hairball with the file in its fur (about 2.5 s), and then the choose view shows the refusal note; no progress bar, no check mark, no `approve` chime; the `annoyed` chime plays once, as it starts to gag, and the note after the hairball is silent. A file that is not refused but cannot be read: today's ending (the check mark, then the annoyed cat), with no hairball.
6. The Debug build's menu bar menu has "Cats (Debug)…": pick coats, sizes, states, emotes, personalities and Playful or Classic; click a cat to poke it; the File buttons (a PDF is chewed, an app and a 30 MB file are coughed up); Replay and Collapse now on the greeting. A Release build has no such item.
7. The greeting at launch, and with the pointer leaving the island halfway through.
8. Apple Music playing: the cat dances in the compact notch.

Record the owner's answers in the PR description. The compact ear scale (0.8) is the one open number.

---

## Next plan: stages 5 to 7

What stays, and the interfaces that plan will use. It runs on its own branch from this one.

**Stage 5, the Settings section and persistence.** A new **Cat** section in `SettingsView.swift`, built from the existing row styles (no existing row changes): Character (the 16 cats, Shrimpy first and Momo second, each with a small live preview that animates only while Settings is visible), Motion style, This cat's motion, Personality (the six presets) with the six trait sliders, Apply to every cat, Fur lines. It uses `CatConfig.shared` (`character`, `motion`, `override`, `pers`), `CatPresets.ids` and `byID`, `Personality.presets`, `slide` and `sanitized`, `CatPersonality` (already `Codable`: the small JSON value of the spec), and `CatRenderer.draw` in a `Canvas` with `CatEngine.live(preset)`. Persistence is UserDefaults, `cat.character`, `cat.motionStyle`, `cat.furLines`, `cat.motion.<id>` and `cat.personality.<id>`; an unknown stored ID falls back to Shrimpy and a hand-edited personality goes through `sanitized`. **Fur lines** are the one drawing feature this plan leaves out on purpose: `CatPreset.furOpts` and the seeded strands (`rng(13)` for the head, `rng(7)` for the ruff, as in `furStrands` of the prototype) arrive with their toggle as `CatDrawOptions.fur`. The Debug-only cat panel (Task 9) keeps working on its own `CatConfig`; stage 5 can add the persisted settings to its read-outs but must not make it write them.

**Stage 6, collar, searching and sleeping, music bob and icons.**
- **The collar and its Settings rows land together, and the default is Off.** Three styles, from the contract's `collarGeometry(preset, pose, D, style, {dpr, detail})` (A-0b, merged `6adf584`, with `COLLAR_STYLES`, `collarStyleOf`, `COLLAR_MIN` and `COLLAR_PASS`) and `collar-cases.json` (its keys are `styles`, `min`, `resolve` and `cases`: each style's geometry at Ø12 to Ø66, at pixel ratio 1 and 2, at rest and with the head turned): Band and tag (`tag`), Band (`band`) and Neckerchief (`kerchief`), plus `off`. These four IDs, in this order, are frozen contract values; an unknown stored style, or one that is not a string, falls back to `off` (the contract's `collarStyleOf`). `dpr` is the device pixel ratio (a value that is not above 0 counts as 2), and the geometry is in head-local px, turning with the face warp. Two rows join the Cat section of stage 5: **Collar** (global, for every cat) and **This cat's collar** (follow the global style, or pick one for this cat); **Apply to every cat** copies the collar along with the motion and the personality. Persistence in UserDefaults: `cat.collar` and `cat.collar.<id>`. The renderer draws the collar in the front pass, over the head and the folded ears and under the whiskers (the contract's `collarPass`, `"front"`, the one slot between `foldEars` and `whiskers`; `passes` itself is unchanged), at every size from Ø12 (`CatDrawOptions.collar`, a style and a colour), with the readability floor in device pixels of the contract (`COLLAR_MIN`: a band 3 px thick, a tag 6 px across, a neckerchief 7 px wide and 5 px deep). It draws `CatEngine.collar`, the agent's colour, which `BotCanvasView` and `MiniBotCanvasView` already set (Task 8) and nothing draws before this stage: small cats wear their agent's collar, the big cat wears the collar of the agent driving its state and none when idle, and the coat is never recoloured. With the collar off each mini cat's pill still names its agent.
- **Searching:** `HookServer` maps a tool event through `CatRules.toolState(_:)` (the tool names are `tests/fixtures/cat/search-tools.json`). **Sleeping:** a one-shot timer armed with `CatRules.sleepDelay(state:quietMs:)` and reset by every agent event, woken by `CatRules.wakes(_:)` (hook, hover, click); Playful wakes with zoomies already (the profile does it). Zoomies after five minutes of work already work inside the engine (`workedFor`, `CatConfig.zoomAfter`).
- **The music bob** builds on `setDancing` and `CatEffects.applyDance` (the ears bounce on the beat). **Icons:** a script reusing `CatRenderer` for `AppIcon.appiconset` (Shrimpy and Momo together) and `MenuBarIcon.imageset`.

**Stage 7, theme tokens, dead code and the Mochi rename sweep.** `shared/theme.json` and its generator; remove `AgentTask.emote` and `miniEye` with `setPermanentEmote`, `holdEye` and the `EyeShape` alias, the `.botMorphTo` posts and `fileDragOver` morph code, the `morph`, `cup`, `mouth`, `mouthRect` and `suck` fields of `USFrame` and `UploadSequenceEngine`, the `.botReject` name (nothing posts or observes it after Task 14; it is declared in `AIService.swift`), `engine.greet()`'s `.botGreet` observer (the `hello` emote and the engine's `greet()` stay: the contract's fixtures pin them), and rename every remaining `mochi`/Mochi identifier (the two `BotEngine` comments in `IslandWindowController.swift` included). The cat panel stays: it is Debug-only and useful for every later sub-project.

## Things the spec does not settle, decided here

1. **The engine is ported whole in Task 6, not by stage.** The fixtures sample whole sequences (the Playful error state hairballs 900 ms in, the zoomies rule is part of `setState`), so a partial engine cannot pass them. What belongs to each stage is what you can see: the states in Tasks 7 and 8 and the panel in Task 9, the emotes and mouth in Tasks 10 and 11, the greeting and the catch in Tasks 12 to 14.
2. **The ear headroom lives in the renderer, not in the mask.** The mask in `IslandContainer` clips at the top of the island, which is the top of the screen: it cannot give ears room. `CatGeometry.earFit` shrinks the ears just enough that no tip rises above the strip (a closed-form solve, tested against a brute-force outline and against the contract's cases), and `BotCanvasView` passes the ceiling in the compact notch. `earFit` and the flat-fill rule are the contract's (A-0b, merged `6adf584`): this plan's `CatGeometry` ports its version (`earFit`, `detailLevel`, `FlatFill`, `flatFillColors`) and tests against its fixtures (`earFit`, `earFitCases`, `flatFill`, `detailLevels` and `flatColors`, in Tasks 2 and 4), and the renderer draws the flat fills from those numbers. The Mac draft's maths was the reference implementation that A-0b ported (the contract's `earFit` is the draft taken to the ear's true highest point, and its flat point mask is 0.86 R by 0.54 R, tuned to the gradient it replaces, where the draft's was 0.5 R by 0.34 R). The compact ear scale is the contract's number too, and composes with the fit (`earScale(D) * f`): if the owner changes it at checkpoint 1, the main session changes it once in `cat-core.js` and its fixtures and this branch merges that, so this plan never edits `cat-core.js`.
3. **The 2 ms budget needed some compact-detail shortcuts and 30 fps for small cats.** The bench of Task 7 draws twelve small cats plus the big one and prints the thread's CPU time per frame. On the dry run's busy machine, with all thirteen redrawn at 60 fps, it measured 4.2 ms in a Debug build and 2.8 ms optimised; with the small cats at 30 fps (which `MiniBotCanvasView` now does) it measured 2.7 ms and 1.8 ms. Before the compact shortcuts it was about 5.9 and 4.7 ms of wall-clock time. The shortcuts are invisible below Ø28: flat head, ear and ruff fills, no rim gradient, a flat crown band for tabbies and a flat mask for points. The bench rasterises into a bitmap inside the timed region, which the app's `Canvas` may not, so the number that counts is the in-app readout (Task 10), in the log and in the cat panel. If it shows more than 2 ms, the next levers are a lower rate for the pill cats, `drawingGroup()` on the compact grid, and caching a settled compact cat as an image.
4. **A refused file is decided at the drop, and coughed up in place of the chew.** The extension and the size are known when the file is dropped, so `FileDropHandler` asks `CatFileRule` (the app's own `AttachmentRules`) right away instead of waiting for the AI reader's verdict at the end of the upload sequence. The catch plays as for any file; at the arrival the cat gags (120 ms to start) and coughs a hairball for 2.4 s; the choose view with the refusal note starts to appear 2.52 s after the arrival. No bar, no check mark, no `approve` chime; the `annoyed` chime plays once, as the cat starts to gag, and the note plays none (sound Stage 3 adds the `pop` at the cough; neither plan does now). The cat stays big where it caught the file, which is where the hairball can be seen. A-tauri gets the same verdict from Rust's `ingest_file` and times its note the same way; both read the one rule of `tests/fixtures/ai/attachment-cases.json`.
5. **The greeting collapses into the real compact island and from the real moment of leaving.** `CatGreeting.pose(_:leave:into:)` equals the contract at 4.9 s and in a 288 x 32 island; earlier leaves and other islands carry the cat to rest without a jump.
6. **The four session cats at the end of the greeting are decorative** (the chosen cat, as the old four coloured blobs were); the real compact grid takes over after it.
7. **The Mac has a dev state panel, Debug-only.** The spec's "dev state panel in each app" is a window opened from the menu bar's menu in Debug builds (Tasks 9, 11, 13 and 14), in the style of Settings, with at least what the Windows `?dev` page offers: the coat, size, state, emote, personality and motion style live, a poke, the eleven states, every coat at every size, the file buttons, the greeting with Replay and Collapse now, and the draw time. The hook socket stays the owner's way to drive the real app's states. The panel sits inside `#if DEBUG && !APPSTORE` and `check-app-binary.sh` proves it is in no Release or App Store build.
8. **`CatConfig.shared.character` is `"shrimpy"` until the Settings row exists.** Small cats are the chosen cat, as in display mode 2.
9. **The prototype's greeting minis, the wardrobe and the desktop cat are not drawn.** The renderer keeps the behind and front passes (`CatGeometry.passes`) for them.
10. **The file is drawn in front of the cat, and the old suction is gone.** The prototype draws its catch's file after the cat; so does the drop view, hovering and flying (and so does A-tauri). The old strips cut at the mouth line and the four green sparks were the suction; the contract's `flightAt` replaces them. The icon leaves the pointer at its size there and shrinks by the flight's own ratio (1 down to 0.23), so it does not jump.
11. **The `approve` chime moves from the drop to a successful read.** It played at the drop and again at the check mark; now only at the check mark, and only when the AI's reader did not reject the file (`!state.dropRejected`). A file the reader cannot read (an "other failure") therefore has no chime and keeps the rest of today's ending. A-tauri moved its chime to the moment `ingest_file` succeeds.
12. **`.botReject` is no longer posted.** It only ever existed to start a hairball at the end of the sequence, and nothing observes it; its name stays declared in `AIService.swift` (the AI code is not touched) until the stage-7 sweep.

## Self-review

**Spec coverage.**
- §1 A-mac row: `CatEngine.swift`, `CatRenderer.swift`, `CatPresets.swift`, `MotionProfiles.swift` and `Personality.swift` replace `BotEngine.swift` (Tasks 1 to 8); every member `BotCanvasView`, `MiniBotCanvasView` and `FileDropView` use today is kept (Task 8; `FileDropView` still posts `.botGulp`, `.botMorphTo` and the emotes, all still observed or harmless).
- "Room for later sub-projects": the renderer has the behind and front passes (`CatGeometry.passes`, `CatRenderer`), and the engine keeps dance (`setDancing`, `dancingLevel`, `CatEffects.applyDance`), the head centre (`CatGeometry.Layout.head`), `lookX`/`lookY` and the paw passes (`CatEffects.wavePaws`).
- §3 fixes: the clock bug (Task 8, `CatEngine.frameDelta`, with its tests in Task 6); ear headroom (Tasks 2, 4 and 8); the Debug-only frame-time readout (Task 10). The greeting (Tasks 12 and 13), the four-step file catch and the refused-file hairball (Task 14) and the Playful error hiss then hairball (the profile, Task 6, drawn from Task 3). `engine.greet()` is kept (the `hello` emote, Task 6).
- "A-0b, contract additions" (merged `6adf584`): `earFit` and the compact ear scale composed with it, the flat fills and the spring sub-steps (Tasks 2, 4 and 6), synced to the merged contract's names, keys and numbers (`EAR_FIT`, `earFit`, `detailLevel`, `FLAT_FILL`, `mixHex`, `flatFillColors`; `earFit`, `earFitCases`, `flatFill`, `detailLevels` and `flatColors`); the collar geometry (`collarGeometry`, `COLLAR_STYLES`, `collar-cases.json`, `collarPass`) is for stage 6 and the collar is not drawn here (Global Constraints, "Next plan").
- The dev state panel line of §2: Tasks 9, 10, 11, 13 and 14.
- §5 checks: the contact sheet (Tasks 4, 7, 10, 13, 14), the engine tests against the fixtures (Task 6), the frame time (Tasks 7 and 10). Stages 1 to 4 as grouped above; stages 5 to 7 are out of scope and listed under "Next plan".
- The parent spec's character rules: the detail levels, the face warp, kittens, the badge, the mouth slot spring and the six mouth values, the hairball (also for a refused file) and the zoomies, personality (Balanced by default) are all in the fixtures or the renderer.
- The contract's port notes (`docs/CAT-CONTRACT.md`): the five constructor draws, the order of draws, `_base` and `_mouth`, frame 0, the action after the update (Task 6 tests), a zero `ear.cx` (Task 2), `tMs` from `f` (Task 6), seeds as `UInt32`, `truncatingRemainder` (Tasks 1 and 2), and the spring sub-steps (Task 6, with a slow-frame test).

**Placeholder scan.** No "TBD", no "similar to Task N", every code step has the code. The A-0b items (marked "A-0b, merged `6adf584`") use the merged contract's names and fixture keys, checked against `design/prototype/cat-core.js` and `tests/fixtures/cat/geometry-cases.json`. Manual steps are on purpose (the owner's checks of Task 15 and the by-eye comparisons of Tasks 4, 7, 9, 10, 13 and 14), and say what to look for.

**Type consistency.** `CatLook` (Task 3) is what `CatEngine.look(time:)` (Task 6) returns and `CatRenderer.draw` (Task 4) takes; `CatGeometry.Layout.base` and `.mouth` are what the views hand back to `CatEngine.base` and `.mouthPoint`; `CatEngine.catchReject(_:)` takes the file's label in capitals, which `CatFileRule.label(for:)` makes and `UploadCatDriver` and `CatDevModel` pass; `CatGreeting.Compact` (Task 12) is built by `GreetingCanvasView` (Task 13) from `state.notchWidth` and `state.notchHeight`; `USFrame.dropped` and `.refused` (Task 14) are what `UploadCatDriver.follow(_:file:)` reads; `CatDevModel` (Task 9) is extended in Tasks 11, 13 and 14 by edits that anchor on its own text.

**Review Focus.** Each of the seven lines has its test: 1 in Tasks 2 and 4, 2 in Task 6, 3 in Tasks 1, 5 and 6, 4 in Tasks 6 and 14, 5 in Tasks 12 and 13, 6 in Task 14 (`CatFileRule` against the AI fixture, the model's thrown files), 7 in Task 9 (the three modes of `check-app-binary.sh`, each proved able to fail) and again in Task 15.

