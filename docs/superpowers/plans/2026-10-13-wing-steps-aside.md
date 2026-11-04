# The right wing steps aside: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the compact island on the Mac, a pointer over the right wing (the grid of agent cats beside the notch) fades the grid out in about 0.15 s and lets clicks through to the third-party menu-bar icons under it; the grid comes back about 1 s after the pointer leaves. It ships in 0.9.1.

**Architecture:** macOS cannot move other apps' status items, so the island gets out of their way. The rules (which part of the wing counts, the fade, the 1 s return, when it applies) are one pure Foundation file, `IslandWing.swift`, tested on a fake clock. The app side is small and adds nothing that runs: `IslandWindowController.pollFrame` already runs at 60 Hz while the island is on screen and 10 Hz while it is hidden, already reads the pointer, and already flips `panel.ignoresMouseEvents`; it now feeds `IslandWing.Yield` the pointer and its own clock, takes the wing out of "the island" while the grid is faded (so the click-through toggle that is already there hands the mouse to the menu bar, and hover no longer opens the island from the wing), and publishes one flag, `AppState.wingYielded`, that the view fades the grid and the ear's black with.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSPanel`, `NSEvent.pressedMouseButtons`), CoreGraphics, XcodeGen, `swiftc` test programs, Bash.

**Spec:** the owner's approved design of 2026-10-13, restated under "The design" below (there is no spec file). The compact island, its wings and the poll are described in `docs/SPEC.md` §2 to §3 (in French), `ARCHITECT.md` and `CLAUDE.md`.

**Base:** a new branch `mac/wing-steps-aside` in a git worktree, from `notchmeow/rebrand` at `ee5f509` or later (`git merge-base --is-ancestor ee5f509 HEAD` must succeed). It touches nothing under `windows/`, no fixture, `cat-core.js` or generated theme file.

## The design (the owner's choice, 2026-10-13)

- With the pointer over the compact island's **right wing**, the agent grid fades out within about **0.15 s**.
- While it is faded, the wing's area **passes clicks through** to the menu-bar icons underneath.
- The **main cat** (the left wing) stays.
- The grid comes back about **1 s after the pointer leaves** that area.
- Hovering the **notch or the main cat** still opens the island, as today. Hovering the **right wing no longer opens it**.
- **Mac only.** The Windows and Linux island sits at the top of the screen with no menu bar under it, so there is nothing to step aside for there (`windows/` is untouched).

## The click-through mechanism, and why

macOS has no per-region click-through for one window: a window either takes the mouse everywhere (`ignoresMouseEvents == false`; a view's `hitTest` returning `nil` only decides which view inside the window gets it, and the event does not fall through to the app below) or nowhere. Three ways to get a click-through wing:

1. **A global `mouseMoved` monitor that toggles `ignoresMouseEvents`.** Needs a second watcher of the pointer next to the one the panel already has, alive while the compact island shows a wing.
2. **A separate panel for the wing**, click-through while faded. Two windows to keep aligned with one shape that springs open and folds, a second level, Spaces and fullscreen behaviour to get right, and the fade split across two windows.
3. **The panel's existing poll.** `pollFrame` already decides, on every tick, whether the pointer is "in the island" and flips `ignoresMouseEvents` to `!inIsland` (`shouldAcceptMouse`). **Chosen.** The wing's yield is one more input to that decision: while the wing is faded and the pointer is over it, the pointer is not "in the island", so the toggle that is already there makes the panel ignore the mouse, and the existing hover logic (`fsm.mouseEntered`, `mouseLeft`) sees the wing as outside, so hover does not open the island from it. No new timer, monitor, window or notification. The poll runs at 60 Hz while the island is on screen (the pass-through starts within one 16.7 ms tick of the pointer arriving) and 10 Hz while it is hidden, where the wing is inactive and `IslandWing.Yield.step` returns at once without asking anything (no `NSEvent` call, no cast): 0 % CPU when hidden is as it was.

The poll is a 60 Hz sampler of `NSEvent.mouseLocation`, which keeps working while the panel ignores the mouse, so the pointer is still seen on the wing and still seen leaving it. A pointer coming from the menu-bar side meets a panel that is already ignoring (it only accepts the mouse inside the island), and one coming from the notch side flips it on the first tick; a click in that one tick over the wing is the only thing the design cannot catch (a click on the notch's side of the boundary, which opens the island as a click on the notch would).

**What the wing is, in every mode.** The right wing is the compact island's right ear: from the notch's right edge to the island's right edge, the strip's whole height (80 pt wide, 32 pt on a notch screen; the same 80 pt on a screen without a notch, where the bar's middle is 80 wide). It holds the **grid** of agent cats (`CompactMiniGrid`, centred 40 pt in from the right edge) in the three display modes:

- **One cat:** the grid shows the other agents; the big cat and its kittens are in the left ear.
- **A cat for each agent:** the same grid; the big cat's coat follows the focus.
- **Two cats:** the grid shows the agents other than the focused one and cat 2's; **both cats (30 and 54 pt in) and the "×N" kitten count are in the left ear** (`CatIslandLayout.compactX`, `kittenBox("pairCompact")`), so Two cats' right wing is the grid exactly as in the other modes and nothing of cat 2 moves.
- **Kittens:** in the compact island they sit beside the big cat (`bigCompact`) or by cat 2 (`pairCompact`), x 52 to 96 pt in from the island's left edge, inside the left ear and the notch; none is ever in the right wing.
- **No right wing:** when the grid has no cat (no pill besides the focused one, `AppState.hasMiniGrid` false) nothing fades and the island behaves exactly as today, hover included. The same holds in the greeting's tail (the session cats are drawn in the grid's place), while the cat's head is being dragged, and in the hidden and expanded modes.

**The ear's black fades with the grid.** The island's black fill covers the menu-bar icons as much as the grid does, so fading the grid alone would give a click-through the owner could not see. The right ear's black fades with the grid (Open question 1); nothing else of the island's look changes.

## Global Constraints

Every task's requirements include this section.

- **Swift 6, SwiftUI and AppKit, no third-party dependencies.** `IslandWing.swift` stays Foundation and CoreGraphics only, with no timer, no `NSEvent`, no clock of its own.
- **0 % CPU when the island is hidden, and no polling of its own.** No new `Timer`, `DispatchSourceTimer`, display link or `NSEvent` monitor. The one watcher is `IslandWindowController.pollFrame`, whose rates (`IslandPoller`: 60 Hz on screen, 10 Hz hidden) are not changed. A wing that is not active asks nothing.
- **Never restyle a shipping view.** The only visible change is the fade of the right wing's grid and black. The island's shape, size, cats, kittens, pills, springs and every other view are as they are in `main`. `CompactMiniGrid` is not edited.
- **Frozen values.** Pill IDs, cat IDs, the display mode IDs `one`, `perAgent`, `two`, UserDefaults keys and every contract string (`nm-hook`, `nm.sock`, `nm_kind`, `nm_agent`) are untouched. This plan stores nothing.
- **Hover opens the island from the notch and the main cat only; a hover on the right wing never opens it while the grid has a cat.** Everything else about when the island opens, collapses and hides (`IslandStateMachine`) is as it was.
- **A mouse button held when the pointer reaches the wing never starts the fade** (a file being dragged in from Finder, a drag that began elsewhere): the wing is the island's as before, so a drop on it lands as it always did.
- **The numbers:** fade out 0.15 s (`IslandWing.fadeOut`), return 1 s after the pointer left (`IslandWing.returnDelay`), fade in 0.25 s (`IslandWing.fadeIn`, the grid's existing fade; Open question 2).
- **Never edit `NotchBuddy.xcodeproj` by hand.** The task that adds a Swift file to the app runs `cd NotchBuddy && xcodegen` and commits the regenerated `project.pbxproj`.
- **No `UserDefaults` suite and no write to `UserDefaults.standard` or `~/Library` in a test or script.** Tests run through `scripts/test-*.sh`, which set `NM_LOG_DIR` to a temp folder.
- **Models and commits** (CLAUDE.md, "Working with AI agents", 2026-10-12): Haiku 5.5 first, Sonnet 5.5 only on a named trigger, never Opus or Fable. Each commit is local only, never pushed, lists only the files its task names, and ends with the `Co-Authored-By` line of the model that did the task: `Claude Haiku 5.5` for `nm-implementer-light` and `nm-implementer`, `Claude Sonnet 5.5` for `nm-implementer-deep`.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app. A Debug or App Store **build** in the worktree is fine and is only built; the scripts that draw a PNG (`render-cats.sh`) are not the app and may run. No task sends a hook event to the app's socket.
  2. Install nothing. No network calls, no downloads.
  3. Use `trash`, never `rm -rf`, for anything you delete by hand; put scratch files under `${TMPDIR:-/tmp}` in a folder with a unique name. (The test and render scripts clean their own `mktemp` folders with `rm -rf` in a `trap`, as every `scripts/test-*.sh` does: that is the repo's convention, not a command an agent runs.)
  4. No `UserDefaults` suite and no write to `UserDefaults.standard` or `~/Library` in a test or script.
  5. Never edit `design/prototype/cat-core.js`, a fixture of `tests/fixtures/`, `shared/theme.json`, a generated theme file or anything under `windows/`.
  6. Never push. Commit only in a task's commit step, after checking the worktree and the branch.
  7. Haiku 5.5 for every task except Task 2 (Sonnet 5.5); never Opus or Fable.
  8. Never rename a frozen ID, and write no `Coucou` or `Mochi` name anywhere (`scripts/check-no-leftovers.sh` must stay green).
  9. If a command is denied by a permission prompt, stop and report it. Do not look for a workaround.

## Review Focus

The design says what the wing does. It is silent on these inputs and conditions, and each would bite a person first, most likely first. Each names the test that pins it.

1. **A file dragged in from Finder, or a drag that began elsewhere, across the wing.** Expected: the wing does not step aside while a mouse button is held when the pointer arrives, so the drop lands on the island as it does today; and a click or button press over an already faded wing does not bring it back. Tests: Task 1 ("the mouse button held"), Task 2's pin on `buttonDown`.
2. **A wing with nothing in it, or whose last cat leaves while the pointer is over it, and the greeting's tail.** Expected: an empty wing does nothing (hover opens the island from it as today); a wing that had cats and loses them under the pointer stays faded until the pointer leaves; the greeting tail and a drag of the cat's head never fade. Tests: Task 1 ("when it must not step aside"), Task 2's pins on `hasMiniGrid`, `isActive`'s arguments and the identical rule in `CompactMiniGrid`.
3. **The pointer on the boundaries: notch, cat, the 6 pt hover slop, the island's edge and a screen with no notch.** Expected: the notch, the left ear and the main cat still open the island; the wing's left edge is the notch's right edge; the band the hover area adds to the right, top and bottom is the wing's too, so no strip beside it opens the island; the screen without a notch has the same 80 pt wing and no slop. Tests: Task 1 ("the wing's rectangle": 7 rows), Task 2's pin on `slop: hoverRect.maxX - islandRect.maxX`.
4. **The island leaving compact while the grid is faded** (an approval opens it, a hotkey, the 60 s hide, the cat's drag). Expected: the grid and the ear's black are back at once, the panel returns to its normal click-through, and the next compact island starts from rest even if the pointer is still over the wing (it fades again). Tests: Task 1 ("when it must not step aside"), Task 3's pin on the mask (width 0 outside compact) and the always-present mask.
5. **A clock that jumps** (sleep and wake, a time that is not a number) **and the pointer crossing in and out quickly.** Expected: no crash; a clock that runs backwards never brings the grid back early; the pointer returning inside the second keeps the grid away and restarts the second. Tests: Task 1 ("a clock that is not a time", "a pointer that comes back within the second", the 20000-tick fuzz).

---

## File Structure

| Path | Responsibility |
|---|---|
| `NotchBuddy/Sources/App/IslandWing.swift` (new) | The pure rules: `IslandWing.rect`, `isActive`, `Yield.step`, `fadeOut`, `fadeIn`, `returnDelay`. |
| `NotchBuddy/Sources/App/IslandWindowController.swift` | One stored property and one block in `pollFrame`: feeds `Yield`, publishes `wingYielded`, keeps the wing out of `inIsland` while faded. |
| `NotchBuddy/Sources/App/AppState.swift` | `@Published var wingYielded`. |
| `NotchBuddy/Sources/App/CatCast+App.swift` | `AppState.hasMiniGrid`. |
| `NotchBuddy/Sources/App/IslandRootView.swift` | The grid's fade, the always-present mask on the island's black, `wingAnimation`. |
| `scripts/render-cats-wing.swift`, `render-cats.swift`, `render-cats.sh` | `render-cats.sh --wing`: the faded state, drawn without the app. |
| `tests/IslandWingTests.swift`, `scripts/test-island-wing.sh` (new) | The pure rules on a fake clock. |
| `tests/IslandWingWiringTests.swift`, `scripts/test-island-wing-wiring.sh` (new) | Source pins of the app-side call sites. |
| `.github/workflows/build.yml`, `docs/SPEC.md`, `CLAUDE.md` | CI steps, the French spec paragraph, one line of the map. |

## Tasks and agents

CLAUDE.md: the lightest model that fits. **Haiku 5.5 first; Sonnet 5.5 only on a named trigger.** Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion` (the deep agent also `superpowers:systematic-debugging`); reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). Effort: **medium** for light tasks (code given in full), **high** for `nm-implementer` and for every review.

| # | Task | Agent, model, effort | Review |
|---|---|---|---|
| 0 | Worktree and baseline | the session | none |
| 1 | The pure rules, their tests and the CI step | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 2 | The panel: the poll feeds the rules, the wing leaves "the island", `wingYielded` | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `nm-reviewer` |
| 3 | The view's fade, the ear's black, and `render-cats.sh --wing` | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 4 | Docs, the last checks and the checkpoint picture | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| After 4 | The whole branch: cross-task contracts, the panel's click-through, the Review Focus | `nm-reviewer-deep`, Sonnet 5.5, high | none |
| 5 | **Owner checkpoint:** the picture, then the real-build checks | the main session and the owner | none |

**Task 2 is Sonnet (trigger 1):** it changes how an `NSPanel` takes and passes the mouse (the `ignoresMouseEvents` toggle, `NSEvent.pressedMouseButtons`, the pointer in the panel's bottom-left coordinates against the island's rectangle and the hover slop) inside a Swift 6 main-actor poll that also drives the island's state machine. The pure rules and their tests are given in full (Task 1), so Haiku does them. If a Haiku task's expected output differs and the cause is not obvious, or it fails twice, hand that task to `nm-implementer-deep` (trigger 2) and say so in the ledger.

## Execution

One worktree chat session runs the whole plan: branch `mac/wing-steps-aside`, model **Haiku 5.5 at high effort**. This is not trigger 5: there are four small tasks, the only platform-API work is Task 2 (which the session hands to `nm-implementer-deep` as a subagent), and the interfaces between tasks are two names (`IslandWing` and `AppState.wingYielded`) given in full. Nothing is pushed. It touches nothing under `windows/`, so it can run beside the other plans.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run `git switch -c mac/wing-steps-aside notchmeow/rebrand`, then Task 0 of `docs/superpowers/plans/2026-10-13-wing-steps-aside.md`: only its Steps 1 and 2 (the base checks: `git merge-base --is-ancestor ee5f509 HEAD` must succeed). Read `CLAUDE.md`, `ARCHITECT.md` and that plan. If a base check fails, say so and stop. Reply "ready" and stop. Do not start Task 1.

2. **Model.** Once the owner starts the chip, the main session sets that session to Haiku 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-13-wing-steps-aside.md` with `superpowers:subagent-driven-development`, task by task, on branch `mac/wing-steps-aside`. Dispatch each task to the agent the plan's "Tasks and agents" table names (Haiku 5.5 first; Sonnet 5.5 only for Task 2 and for a task Haiku failed twice), then to `nm-reviewer`; fix what the review finds before the next task. Rules for you and for every subagent (put the plan's SUBAGENT RULES block in every brief):
>
> - **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder (under `.claude/worktrees/`), the second `mac/wing-steps-aside`. If either is wrong, stop and report. Commit with `git commit -F <file>`, never `-m`, with the trailer of the model that did the task. Never push.
> - **Ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-13-wing-steps-aside/progress.md`: one line per task with its agent, model, commit hash, test lines and review verdict, and any escalation to `nm-implementer-deep` with the trigger.
> - **Briefs are task-sized.** A brief carries one task: its text, the Global Constraints, the SUBAGENT RULES and the files it names. Never hand a subagent the whole plan.
> - **Reviews** read `git diff notchmeow/rebrand...HEAD` (three dots), narrowed to the task's files, never `..` and never a diff against a moving working tree.
> - **Every shell block in the plan passes `bash -n` before it is run**, and a script you write passes it too.
> - **Servers and processes.** Stop a server only by the PID you saved when you started it. Never launch, quit or replace a NotchMeow app: the builds are builds, the picture comes from `render-cats.sh --wing`. Install and download nothing.
> - **Stop and report on any refusal** (a denied command, a permission prompt): do not look for a workaround.
> - **Owner checkpoint.** Run Tasks 1 to 4, dispatch `nm-reviewer-deep` over the whole branch, fix what it finds, then stop and report to the main session (Task 5): copy the three pictures into `.claude/checkpoints/wing/` of the worktree, which is gitignored, and say what to look for.
>
> Report: the commits; the output of `bash scripts/test-island-wing.sh`, `bash scripts/test-island-wing-wiring.sh`, `bash scripts/test-island-poller.sh`, `bash scripts/test-cat-wiring.sh` and `bash scripts/check-no-leftovers.sh`; the Debug and App Store build lines; the paths of the pictures; and anything you could not settle.

Before any follow-up turn (a fix round, a question, a resumed run), the main session checks the session is still on its configured model and effort.

## How to run this plan

**Blocks.** A code step is either **Create `path`** (the file's exact content) or **Edit `path`** (a find text that occurs exactly once, and its replacement). Apply an edit by replacing the find text with the replacement and nothing else; if the find text occurs zero or two times, stop and report: the tree is not what the plan expects. Never type a block from memory and never "improve" one. Every `Run:` line is run from the repository root (the worktree's top folder); `Expected: FAIL` and `Expected: PASS` say which way it must go, and the text after it says what to see.

**Mac commands.** The test programs are `swiftc` programs run through `scripts/test-*.sh`; none needs Xcode. A build is `cd NotchBuddy && xcodegen && cd ..` and then `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO` (the App Store target is `-scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store`, with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`). A build only builds: do not open the app.

**Looking at an image.** The agent that ran the step opens the PNG with its file reader and says in one sentence what it sees against the thing named; a blank or broken image is a failed step. The owner's look is the checkpoint.

**Bite steps.** Some steps break the code on purpose to prove a test fails. Back the file up into a folder you made with `mktemp -d`, change it with the `sed` given, run the test, and copy the backup back; the next step starts from the real file.

---
## Tasks

### Task 0: Worktree and baseline

No code and no commit. Its first two steps are what the chip's prompt runs before the model is set (see "Execution").

- [ ] **Step 1: Put the session's worktree on the plan's branch**

```bash
git status                                    # must be clean
git switch -c mac/wing-steps-aside notchmeow/rebrand
git merge-base --is-ancestor ee5f509 HEAD && echo "the base (ee5f509) is in the history"
git log --oneline -3
```

Expected: `the base (ee5f509) is in the history`. If that line is missing, the worktree was cut from an older base: stop and tell the owner. Every later command runs from the root of this worktree. Never push.

- [ ] **Step 2: Check the places this plan edits are as it expects**

Run: `grep -c "private var wasInIsland = false" NotchBuddy/Sources/App/IslandWindowController.swift; grep -c "@Published var greetingTail = false" NotchBuddy/Sources/App/AppState.swift; grep -c "state.cast.pills.compactMap" NotchBuddy/Sources/App/IslandRootView.swift; grep -c "let inIsland = hoverRect.contains(local)" NotchBuddy/Sources/App/IslandWindowController.swift`
Expected: four lines, each `1`.

- [ ] **Step 3: Baseline: the tests this plan must not move, and a build**

```bash
bash scripts/test-island-poller.sh 2>&1 | tail -1
bash scripts/test-cat-wiring.sh 2>&1 | tail -1
bash scripts/check-no-leftovers.sh 2>&1 | tail -1
cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"
```

Expected: `IslandPoller: visible … Hz, hidden 10 Hz, shown again … Hz` (visible about 59 to 60), `All tests passed.`, the leftovers guard's last `✓` line, and `** BUILD SUCCEEDED **` (a few minutes on a cold build).

- [ ] **Step 4: Read the base once**

Read, without changing: `NotchBuddy/Sources/App/IslandWindowController.swift` (`pollFrame`, `startPolling`), `IslandPoller.swift`, `IslandRootView.swift` (`IslandContainer.body`, `CompactMiniGrid`), `CatIslandLayout.swift` (`compactX`, `kittenBox`) and `IslandScreenGeometry.swift` (`IslandRestingLayout`). Nothing to report.

---

### Task 1: The pure rules, their tests and the CI step

**Files:**
- Create: `tests/IslandWingTests.swift`, `scripts/test-island-wing.sh`, `NotchBuddy/Sources/App/IslandWing.swift`
- Edit: `.github/workflows/build.yml`
- Regenerated: `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces (Task 2 and Task 3 use these names):
  - `IslandWing.fadeOut: TimeInterval` (0.15), `IslandWing.fadeIn: TimeInterval` (0.25), `IslandWing.returnDelay: TimeInterval` (1.0)
  - `IslandWing.rect(island: CGRect, notchWidth: CGFloat, slop: CGFloat = 0) -> CGRect`
  - `IslandWing.isActive(compact: Bool, greetingTail: Bool, dragging: Bool) -> Bool`
  - `IslandWing.Yield` (`Equatable`, `init()`), `mutating func step(now: TimeInterval, inWing: Bool, active: Bool, buttonDown: () -> Bool, hasWing: () -> Bool) -> IslandWing.Yield.Out`, and `Out { var faded: Bool; var passThrough: Bool }`

- [ ] **Step 1: Write the failing test and its script**

**Create `tests/IslandWingTests.swift`**

```swift
import Foundation

// The compact island's right wing: its rectangle, when it can step aside, and the fade's timing, as plain numbers and a fake clock.
// Run it through scripts/test-island-wing.sh.

@main
enum IslandWingTests {
    /// One tick on the fake clock, with the defaults of a plain hover.
    @MainActor static func tick(_ y: inout IslandWing.Yield, _ t: Double, inWing: Bool, active: Bool = true, button: Bool = false, has: Bool = true) -> IslandWing.Yield.Out {
        y.step(now: t, inWing: inWing, active: active, buttonDown: { button }, hasWing: { has })
    }

    @MainActor static func main() {
        CT.section("the numbers the owner chose")
        CT.checkNear("the grid fades out in 0.15 s", IslandWing.fadeOut, 0.15)
        CT.checkNear("and comes back 1 s after the pointer has left", IslandWing.returnDelay, 1.0)
        CT.checkTrue("it fades back in no faster than it went out, and well within the delay", IslandWing.fadeIn >= IslandWing.fadeOut && IslandWing.fadeIn < IslandWing.returnDelay)

        CT.section("the wing's rectangle: the part beside the notch")
        // A notch screen: the panel is 720 wide, the island 344 (notch 184 plus two ears of 80) by 32, at the top of a panel 320 high (AppKit: y up).
        let island = CGRect(x: 188, y: 288, width: 344, height: 32)
        let wing = IslandWing.rect(island: island, notchWidth: 184)
        CT.check("it starts at the notch's right edge and ends at the island's", [wing.minX, wing.maxX], [452, 532])
        CT.check("and is the strip's height", [wing.minY, wing.maxY], [288, 320])
        CT.checkTrue("the notch, the left ear and the middle of the strip are not in it", !wing.contains(CGPoint(x: 360, y: 300)) && !wing.contains(CGPoint(x: 220, y: 300)) && !wing.contains(CGPoint(x: 451.9, y: 300)))
        CT.checkTrue("its first and last points are", wing.contains(CGPoint(x: 452, y: 300)) && wing.contains(CGPoint(x: 531.9, y: 300)))
        let slopped = IslandWing.rect(island: island, notchWidth: 184, slop: 6)
        CT.check("with the 6 pt hover slop it reaches 6 pt further right, up and down, and not left", [slopped.minX, slopped.maxX, slopped.minY, slopped.maxY], [452, 538, 282, 326])
        let bar = IslandWing.rect(island: CGRect(x: 240, y: 296, width: 240, height: 24), notchWidth: 80)
        CT.check("a screen without a notch: the same rule, around its 80 pt bar", [bar.minX, bar.width, bar.height], [400, 80, 24])
        CT.check("an island narrower than its notch has no wing", IslandWing.rect(island: CGRect(x: 100, y: 0, width: 50, height: 30), notchWidth: 184).width, 0)

        CT.section("when the wing can step aside")
        CT.checkTrue("in the compact island", IslandWing.isActive(compact: true, greetingTail: false, dragging: false))
        CT.checkTrue("not hidden or expanded (compact is false there)", !IslandWing.isActive(compact: false, greetingTail: false, dragging: false))
        CT.checkTrue("not while the greeting's tail draws the session cats", !IslandWing.isActive(compact: true, greetingTail: true, dragging: false))
        CT.checkTrue("not while the cat's head is being dragged", !IslandWing.isActive(compact: true, greetingTail: false, dragging: true))

        CT.section("the fade: in at once, out one second after the pointer has left")
        var y = IslandWing.Yield()
        CT.check("the pointer elsewhere: nothing happens", tick(&y, 0, inWing: false), .init(faded: false, passThrough: false))
        CT.check("the pointer reaches the wing: the grid fades and the mouse passes through on that very tick", tick(&y, 1.0, inWing: true), .init(faded: true, passThrough: true))
        CT.check("it stays while the pointer stays (ten seconds)", tick(&y, 11.0, inWing: true), .init(faded: true, passThrough: true))
        CT.check("the pointer leaves: the grid is still away, and the mouse is no longer passed on", tick(&y, 12.0, inWing: false), .init(faded: true, passThrough: false))
        CT.check("0.9 s later it is still away", tick(&y, 12.9, inWing: false), .init(faded: true, passThrough: false))
        CT.check("1 s after the pointer was first seen away it comes back", tick(&y, 13.0, inWing: false), .init(faded: false, passThrough: false))
        CT.check("and stays", tick(&y, 20.0, inWing: false), .init(faded: false, passThrough: false))

        CT.section("a pointer that comes back within the second keeps the grid away, and the second starts again")
        y = IslandWing.Yield()
        _ = tick(&y, 0, inWing: true)
        _ = tick(&y, 5.0, inWing: false)
        CT.check("back in the wing at 5.8 s: still faded, the mouse passes", tick(&y, 5.8, inWing: true), .init(faded: true, passThrough: true))
        _ = tick(&y, 6.0, inWing: false)
        CT.check("away again at 6.0 s: 0.9 s later it is still away (the count began again)", tick(&y, 6.9, inWing: false), .init(faded: true, passThrough: false))
        CT.check("and gone at 7.0 s", tick(&y, 7.0, inWing: false), .init(faded: false, passThrough: false))

        CT.section("the mouse button held: a file dragged in, or a click that began elsewhere")
        y = IslandWing.Yield()
        CT.check("a button held when the pointer arrives never starts a fade: the wing is the island's, as before", tick(&y, 0, inWing: true, button: true), .init(faded: false, passThrough: false))
        CT.check("and releasing it over the wing then fades it", tick(&y, 0.1, inWing: true), .init(faded: true, passThrough: true))
        CT.check("a button pressed over a faded wing leaves it faded", tick(&y, 0.2, inWing: true, button: true), .init(faded: true, passThrough: true))

        CT.section("when it must not step aside")
        y = IslandWing.Yield()
        _ = tick(&y, 0, inWing: true)
        CT.check("the island leaves compact (hidden, expanded, the greeting's tail, a drag): the grid is back at once", tick(&y, 0.5, inWing: true, active: false), .init(faded: false, passThrough: false))
        CT.check("and the pointer still over the wing starts a new fade when the island is compact again", tick(&y, 0.6, inWing: true), .init(faded: true, passThrough: true))
        y = IslandWing.Yield()
        var asked = 0
        _ = y.step(now: 0, inWing: false, active: true, buttonDown: { false }, hasWing: { asked += 1; return true })
        CT.check("with the pointer away the grid is never asked about", asked, 0)
        var empty = IslandWing.Yield()
        CT.check("a wing with no cat in it: nothing fades and the island is the island's, as before", tick(&empty, 0, inWing: true, has: false), .init(faded: false, passThrough: false))
        _ = y.step(now: 1, inWing: true, active: true, buttonDown: { false }, hasWing: { asked += 1; return true })
        _ = y.step(now: 2, inWing: true, active: true, buttonDown: { false }, hasWing: { asked += 1; return true })
        CT.check("the grid is asked once, when the fade begins, not on every tick after", asked, 1)
        var buttonAsked = 0
        var quiet = IslandWing.Yield()
        for i in 0..<50 { _ = quiet.step(now: Double(i), inWing: i % 2 == 0, active: false, buttonDown: { buttonAsked += 1; return false }, hasWing: { true }) }
        CT.check("an island that is not compact never asks about the mouse button (a hidden island's slow poll costs nothing)", buttonAsked, 0)
        var gone = IslandWing.Yield()
        _ = tick(&gone, 0, inWing: true)
        CT.check("the last cat leaving while the pointer is over the wing does not end the fade", tick(&gone, 1, inWing: true, has: false), .init(faded: true, passThrough: true))

        CT.section("a clock that is not a time")
        var odd = IslandWing.Yield()
        _ = tick(&odd, 0, inWing: true)
        CT.check("NaN resets the wing without a crash", tick(&odd, .nan, inWing: true), .init(faded: false, passThrough: false))
        CT.check("infinity too", tick(&odd, .infinity, inWing: true), .init(faded: false, passThrough: false))
        CT.check("and the next real tick works", tick(&odd, 3, inWing: true), .init(faded: true, passThrough: true))
        _ = tick(&odd, 4, inWing: false)
        CT.check("a clock that runs backwards does not bring the grid back early", tick(&odd, 1, inWing: false), .init(faded: true, passThrough: false))

        CT.section("fuzz: 20000 ticks that must keep the rules")
        var rng = SystemRandomNumberGenerator()
        var f = IslandWing.Yield(), t = 0.0, broke = 0, lastIn = -100.0, wasFaded = false
        for _ in 0..<20000 {
            t += Double.random(in: 0...0.05, using: &rng)
            let inWing = Double.random(in: 0...1, using: &rng) < 0.3, active = Double.random(in: 0...1, using: &rng) < 0.95
            let out = tick(&f, t, inWing: inWing, active: active, button: Double.random(in: 0...1, using: &rng) < 0.05)
            if out.passThrough && !out.faded { broke += 1 }                                  // pass-through is only ever on a faded wing
            if !active && out.faded { broke += 1 }                                           // an inactive island never keeps a fade
            if out.passThrough && !inWing { broke += 1 }                                     // and only with the pointer over it
            if active && inWing && out.faded { lastIn = t }
            if active && !inWing && wasFaded && !out.faded && t - lastIn < IslandWing.returnDelay { broke += 1 }   // never back early
            wasFaded = active && out.faded
        }
        CT.check("no tick broke a rule", broke, 0)

        CT.finish()
    }
}
```

**Create `scripts/test-island-wing.sh`**

```bash
#!/usr/bin/env bash
# The compact island's right wing stepping aside (IslandWing): its rectangle, when it is active, and the fade's timing on a fake clock.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-island-wing.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/IslandWing.swift \
    tests/CatTestSupport.swift tests/IslandWingTests.swift \
    -o "$TEST_DIR/island-wing-tests"
"$TEST_DIR/island-wing-tests"
```

```bash
chmod +x scripts/test-island-wing.sh && bash -n scripts/test-island-wing.sh && echo "script ok"
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash scripts/test-island-wing.sh 2>&1 | tail -3`
Expected: FAIL: a compile error, `error opening input file 'NotchBuddy/Sources/App/IslandWing.swift'`.

- [ ] **Step 3: Write the rules**

**Create `NotchBuddy/Sources/App/IslandWing.swift`**

```swift
import CoreGraphics
import Foundation

// The compact island's right wing steps aside: the rules, as plain numbers and times. The wing is the grid of agent cats beside the notch; on a crowded menu bar it sits on
// other apps' icons, and macOS has no way to move them. While the pointer is over the wing the grid fades and the panel passes the mouse on; the grid comes back
// `returnDelay` seconds after the pointer has left. Foundation only: `IslandWindowController.pollFrame` feeds it the pointer and the clock it already has, so it adds no
// timer, no monitor and no poll (`docs/SPEC.md`, "L'aile droite s'efface").

enum IslandWing {
    /// How long the grid takes to fade out when the pointer arrives (s), and to fade back in (s). The panel stops taking the mouse at once; only the picture fades.
    static let fadeOut: TimeInterval = 0.15
    static let fadeIn: TimeInterval = 0.25
    /// How long the pointer must have been away before the grid comes back (s).
    static let returnDelay: TimeInterval = 1.0

    /// The wing in the panel's coordinates: from the notch's right edge to the island's right edge, the strip's whole height. `island` is the compact island's frame and
    /// `notchWidth` the notch's. `slop` is how far the island's hover area reaches beyond the strip (6 pt on a notch screen, 0 on a screen without one): the wing takes
    /// it on its right, top and bottom, so that no band of the hover area is left beside it, and not on its left, where the notch begins.
    static func rect(island: CGRect, notchWidth: CGFloat, slop: CGFloat = 0) -> CGRect {
        let left: CGFloat = island.midX + notchWidth / 2
        let width: CGFloat = max(0, island.maxX + slop - left)
        return CGRect(x: left, y: island.minY - slop, width: width, height: island.height + 2 * slop)
    }

    /// Whether the wing can step aside now: only in the compact island, not while the greeting's tail still draws the session cats in the grid's place, and not while a
    /// drag of the cat's head is under way.
    static func isActive(compact: Bool, greetingTail: Bool, dragging: Bool) -> Bool { compact && !greetingTail && !dragging }

    /// The wing's memory between two ticks.
    struct Yield: Equatable {
        struct Out: Equatable {
            /// The grid is faded (or fading out).
            var faded: Bool
            /// The pointer is over the faded wing: the panel must not take the mouse, and the island must not count the pointer as over it.
            var passThrough: Bool
        }

        private var faded = false
        /// When the pointer was first seen away from the wing (while faded); nil while it is over the wing.
        private var leftAt: TimeInterval?

        /// One tick. `inWing`: the pointer is inside `rect`. `active`: `isActive`. `buttonDown` says whether a mouse button is held (a file being dragged in, say): then no
        /// fade begins, so a drop on the wing lands as it always did, and a fade that has begun is not undone by it. `hasWing` says whether the grid has any cat in it. Both are
        /// closures, asked only when a fade is about to begin, so a poll tick that is not near the wing costs nothing.
        mutating func step(now: TimeInterval, inWing: Bool, active: Bool, buttonDown: () -> Bool, hasWing: () -> Bool) -> Out {
            guard active, now.isFinite else {
                self = Yield()
                return Out(faded: false, passThrough: false)
            }
            if inWing {
                if !faded && !buttonDown() && hasWing() { faded = true }
                leftAt = nil
                return Out(faded: faded, passThrough: faded)
            }
            if faded {
                let since = leftAt ?? now
                leftAt = since
                if now - since >= IslandWing.returnDelay { self = Yield() }
            }
            return Out(faded: faded, passThrough: false)
        }
    }
}
```

- [ ] **Step 4: Run the test to make sure it passes**

Run: `bash scripts/test-island-wing.sh 2>&1 | tail -3`
Expected: PASS: `✓ no tick broke a rule` and `All tests passed.` (39 `✓` lines).

- [ ] **Step 5: Bite: break three rules on purpose and see each test fail**

```bash
F=NotchBuddy/Sources/App/IslandWing.swift
BITE="$(mktemp -d "${TMPDIR:-/tmp}/wing-bite.XXXXXX")"; cp "$F" "$BITE/IslandWing.swift"
sed -i '' 's/static let returnDelay: TimeInterval = 1.0/static let returnDelay: TimeInterval = 0.5/' "$F"
bash scripts/test-island-wing.sh 2>&1 | tail -1                  # the return delay is 0.5 s
cp "$BITE/IslandWing.swift" "$F"
sed -i '' 's/if !faded \&\& !buttonDown() \&\& hasWing() { faded = true }/if !faded \&\& hasWing() { faded = true }/' "$F"
bash scripts/test-island-wing.sh 2>&1 | tail -1                  # a held button no longer stops the fade
cp "$BITE/IslandWing.swift" "$F"
sed -i '' 's/if !faded \&\& !buttonDown() \&\& hasWing() { faded = true }/if !faded \&\& !buttonDown() { faded = true }/' "$F"
bash scripts/test-island-wing.sh 2>&1 | tail -1                  # an empty wing fades
cp "$BITE/IslandWing.swift" "$F"
bash scripts/test-island-wing.sh 2>&1 | tail -1                  # the real file again
trash "$BITE"
```

Expected: `3 test(s) failed.`, `1 test(s) failed.`, `2 test(s) failed.` and then `All tests passed.`

- [ ] **Step 6: The CI step**

**Edit `.github/workflows/build.yml`**

Find:

```yaml
      - name: Cat wiring (source pins of the app files)
        run: bash scripts/test-cat-wiring.sh
```

Replace with:

```yaml
      - name: Cat wiring (source pins of the app files)
        run: bash scripts/test-cat-wiring.sh

      - name: Island right wing steps aside (the rules and the fade's timing)
        run: bash scripts/test-island-wing.sh

      - name: Island right wing wiring (source pins of the panel, AppState and the view)
        run: bash scripts/test-island-wing-wiring.sh
```

- [ ] **Step 7: Add the file to the app and check the build**

```bash
cd NotchBuddy && xcodegen && cd .. && git diff --stat NotchBuddy/NotchBuddy.xcodeproj | tail -1
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"
```

Expected: `1 file changed, 6 insertions(+)` (the new file, in the Debug and App Store targets) and `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree, mac/wing-steps-aside
git add tests/IslandWingTests.swift scripts/test-island-wing.sh NotchBuddy/Sources/App/IslandWing.swift .github/workflows/build.yml NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
MSG="$(mktemp "${TMPDIR:-/tmp}/wing-msg.XXXXXX")"; printf '%s\n' "feat(island): the rules of the right wing stepping aside" "" "Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>" > "$MSG"; git commit -F "$MSG"; trash "$MSG"
```

---

### Task 2: The panel: the poll feeds the rules, the wing leaves "the island", `wingYielded`

**Files:**
- Create: `tests/IslandWingWiringTests.swift`, `scripts/test-island-wing-wiring.sh`
- Modify: `NotchBuddy/Sources/App/IslandWindowController.swift`, `AppState.swift`, `CatCast+App.swift`

**Interfaces:**
- Consumes (Task 1): `IslandWing.Yield`, `IslandWing.isActive`, `IslandWing.rect`.
- Produces (Task 3 reads it): `AppState.wingYielded: Bool` (`@Published`, set only by the poll); `AppState.hasMiniGrid: Bool`.

**How the panel works today** (read before editing). `pollFrame` runs every tick (`IslandPoller`: 60 Hz while the island is on screen, 10 Hz while it is hidden). It takes `NSEvent.mouseLocation`, makes it panel-local (AppKit: origin bottom left), gets the island's rectangle in that space (`panel.currentIslandFrame`), widens it by 6 pt into `hoverRect` (not on a screen without a notch while the island is not expanded), and sets `inIsland = hoverRect.contains(local)`. Then `shouldAcceptMouse = inIsland || inAttachDrag || attachDragStart != nil` flips `panel.ignoresMouseEvents`, and the same `inIsland` feeds `fsm.mouseEntered()` and `fsm.mouseLeft()` (hover opens the island) and `wasInIsland` (the click handler's gate). The panel therefore ignores the mouse everywhere but over the island: so making the faded wing "not the island" is the whole mechanism.

- [ ] **Step 1: Write the wiring test (failing)**

**Create `tests/IslandWingWiringTests.swift`**

```swift
import Foundation

// Source pins for the right wing stepping aside, where no test program can compile the app's files (the panel, AppState and the SwiftUI view need the whole app).
// Each says where a call must be, so a missed call site fails here and not on the owner's screen. Run from the repository root through scripts/test-island-wing-wiring.sh.

@main
enum IslandWingWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
    /// The offset of the first `needle`, or -1.
    static func at(_ needle: String, in text: String) -> Int { text.range(of: needle)?.lowerBound.utf16Offset(in: text) ?? -1 }

    @MainActor static func main() {
        let controller = source("IslandWindowController.swift"), island = source("IslandRootView.swift"), app = source("AppState.swift"), cast = source("CatCast+App.swift"), rules = source("IslandWing.swift")
        CT.section("the sources were read")
        CT.checkTrue("the five files are there", controller.contains("final class IslandWindowController") && island.contains("struct IslandContainer") && app.contains("final class AppState") && cast.contains("var cast: CatCast.Result") && rules.contains("enum IslandWing"))

        CT.section("the rules are pure: no timer, no monitor, no AppKit, no clock of their own")
        CT.checkTrue("IslandWing.swift imports only CoreGraphics and Foundation", rules.contains("import CoreGraphics") && rules.contains("import Foundation") && !rules.contains("import AppKit") && !rules.contains("import SwiftUI"))
        CT.checkTrue("and starts nothing", !rules.contains("Timer") && !rules.contains("DispatchQueue") && !rules.contains("NSEvent") && !rules.contains("CACurrentMediaTime") && !rules.contains("Date()"))

        CT.section("the panel: one step per poll tick, fed by the poll's own pointer and clock, and no new timer or monitor")
        CT.check("the controller holds one wing memory", count("private var wingYield = IslandWing.Yield()", in: controller), 1)
        CT.check("and steps it in exactly one place, from the poll", count("wingYield.step(", in: controller), 1)
        CT.checkTrue("the step is given the wing's active rule, its rectangle with the hover area's slop, the clock, the button state and the grid", controller.contains("IslandWing.isActive(compact: state.mode == .compact, greetingTail: state.greetingTail, dragging: inAttachDrag || attachDragStart != nil)") && controller.contains("IslandWing.rect(island: islandRect, notchWidth: notchW, slop: hoverRect.maxX - islandRect.maxX)") && controller.contains("now: CACurrentMediaTime()") && controller.contains("buttonDown: { NSEvent.pressedMouseButtons != 0 }") && controller.contains("hasWing: { state.hasMiniGrid }"))
        CT.checkTrue("the poll publishes the fade only when it changes", controller.contains("if state.wingYielded != wing.faded { state.wingYielded = wing.faded }"))
        CT.checkTrue("the pointer over the faded wing is not the island's: hover cannot open it, and the click-through below takes the mouse off the panel", controller.contains("let inIsland = hoverRect.contains(local) && !wing.passThrough"))
        CT.checkTrue("the step comes after the island's rectangle and before the click-through toggle and the FSM's enter and leave", at("let islandRect = panel.currentIslandFrame", in: controller) > 0 && at("let islandRect = panel.currentIslandFrame", in: controller) < at("wingYield.step(", in: controller) && at("wingYield.step(", in: controller) < at("let shouldAcceptMouse = inIsland", in: controller) && at("let shouldAcceptMouse = inIsland", in: controller) < at("fsm.mouseEntered()", in: controller))
        CT.check("the panel registers no mouse-moved monitor (the poll that already runs is the only watcher)", count("matching: .mouseMoved", in: controller), 0)
        CT.checkTrue("and the poll still runs at the hidden rate while the island is hidden (the poller is untouched)", controller.contains("poller.run(hidden: state.mode == .hidden)") && controller.contains("modeSubscription = state.$mode"))

        CT.section("a wing is there exactly when a cat is drawn in it: the wing's test and the grid's list are the same rule")
        CT.checkTrue("the grid draws the cast's pills that are tasks, as it always did (the view is untouched)", island.contains("state.cast.pills.compactMap { p in state.tasks.first { $0.id == p.pill }.map { ($0, p.cat) } }"))
        CT.checkTrue("and AppState's hasMiniGrid is that list being non-empty", cast.contains("var hasMiniGrid: Bool { cast.pills.contains { p in tasks.contains { $0.id == p.pill } } }"))

        CT.finish()
    }
}
```

**Create `scripts/test-island-wing-wiring.sh`**

```bash
#!/usr/bin/env bash
# The right wing stepping aside, wiring: where the panel's poll, AppState and the island's view call the pure rules (IslandWing), pinned as source text.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-island-wing-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/IslandWingWiringTests.swift \
    -o "$TEST_DIR/island-wing-wiring-tests"
"$TEST_DIR/island-wing-wiring-tests"
```

```bash
chmod +x scripts/test-island-wing-wiring.sh && bash -n scripts/test-island-wing-wiring.sh && echo "script ok"
```

Run: `bash scripts/test-island-wing-wiring.sh 2>&1 | grep -c "✗"`
Expected: FAIL: `7` (the controller's six pins and `hasMiniGrid`).

- [ ] **Step 2: The published flag**

**Edit `NotchBuddy/Sources/App/AppState.swift`**

Find:

```swift
    @Published var greetingTail = false
```

Replace with:

```swift
    @Published var greetingTail = false
    /// True while the compact island's right wing (the grid of agent cats) has stepped aside for the pointer: the grid and the ear's black fade out and the panel passes the
    /// mouse on to the menu bar under them. Set only by `IslandWindowController.pollFrame`, from `IslandWing.Yield`.
    @Published var wingYielded = false
```

- [ ] **Step 3: Whether the wing has a cat**

**Edit `NotchBuddy/Sources/App/CatCast+App.swift`**

Find:

```swift
    /// The display mode Settings has:
```

Replace with:

```swift
    /// Whether the compact island has a right wing at all: a cat in the grid. The same rule as `CompactMiniGrid.others` (the cast's pills that are tasks), which
    /// `IslandWingWiringTests` pins in both places.
    var hasMiniGrid: Bool { cast.pills.contains { p in tasks.contains { $0.id == p.pill } } }

    /// The display mode Settings has:
```

- [ ] **Step 4: The poll**

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**

Find:

```swift
    private var wasInIsland = false
```

Replace with:

```swift
    private var wasInIsland = false
    /// The compact island's right wing stepping aside (`IslandWing`): fed once per poll tick, with no timer or monitor of its own.
    private var wingYield = IslandWing.Yield()
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**

Find:

```swift
        let inIsland = hoverRect.contains(local)

        // Toggle click-through
```

Replace with:

```swift
        // The compact island's right wing steps aside (IslandWing): the pointer over it fades the grid, and the panel passes the mouse on to the menu bar icons under it.
        // The island opens from the notch and the cat, not from the wing. Fed by this poll's own pointer and clock: no timer and no monitor of its own.
        let wingActive = IslandWing.isActive(compact: state.mode == .compact, greetingTail: state.greetingTail, dragging: inAttachDrag || attachDragStart != nil)
        let wingRect = IslandWing.rect(island: islandRect, notchWidth: notchW, slop: hoverRect.maxX - islandRect.maxX)
        let wing = wingYield.step(now: CACurrentMediaTime(), inWing: wingActive && wingRect.contains(local), active: wingActive,
                                  buttonDown: { NSEvent.pressedMouseButtons != 0 }, hasWing: { state.hasMiniGrid })
        if state.wingYielded != wing.faded { state.wingYielded = wing.faded }
        let inIsland = hoverRect.contains(local) && !wing.passThrough

        // Toggle click-through
```

- [ ] **Step 5: Run the pins, the rules and the poller's test**

Run: `bash scripts/test-island-wing-wiring.sh 2>&1 | tail -1; bash scripts/test-island-wing.sh 2>&1 | tail -1; bash scripts/test-island-poller.sh 2>&1 | tail -1; bash scripts/test-cat-wiring.sh 2>&1 | tail -1`
Expected: `All tests passed.` (the wiring test, 13 `✓` lines), `All tests passed.`, `IslandPoller: visible … Hz, hidden 10 Hz, shown again … Hz`, `All tests passed.`

- [ ] **Step 6: Build**

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error|BUILD"`
Expected: `** BUILD SUCCEEDED **` and no `error` line. Without Task 3 the grid does not yet fade; the wing already passes the mouse through and no longer opens the island.

- [ ] **Step 7: Bite: a wing that still opens the island**

```bash
F=NotchBuddy/Sources/App/IslandWindowController.swift
BITE="$(mktemp -d "${TMPDIR:-/tmp}/wing-bite.XXXXXX")"; cp "$F" "$BITE/IslandWindowController.swift"
sed -i '' 's/ \&\& !wing.passThrough$//' "$F"
bash scripts/test-island-wing-wiring.sh 2>&1 | tail -1          # hover would open the island from the faded wing
cp "$BITE/IslandWindowController.swift" "$F"
bash scripts/test-island-wing-wiring.sh 2>&1 | tail -1
trash "$BITE"
```

Expected: `1 test(s) failed.` and then `All tests passed.`

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add tests/IslandWingWiringTests.swift scripts/test-island-wing-wiring.sh NotchBuddy/Sources/App/IslandWindowController.swift NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/CatCast+App.swift
MSG="$(mktemp "${TMPDIR:-/tmp}/wing-msg.XXXXXX")"; printf '%s\n' "feat(island): the right wing passes the mouse through and no longer opens the island" "" "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" > "$MSG"; git commit -F "$MSG"; trash "$MSG"
```

---

### Task 3: The view's fade, the ear's black, and `render-cats.sh --wing`

**Files:**
- Create: `scripts/render-cats-wing.swift`
- Modify: `NotchBuddy/Sources/App/IslandRootView.swift`, `scripts/render-cats.swift`, `scripts/render-cats.sh`, `tests/IslandWingWiringTests.swift`

**Interfaces:**
- Consumes: `AppState.wingYielded` (Task 2), `IslandWing.fadeOut`, `IslandWing.fadeIn`, `IslandWing.rect` (Task 1).
- Produces: `render-cats.sh --wing [--mode one|perAgent|two]`.

The island's black is one `IslandShape`; the grid is a separate view on top of it. Both must fade, or the click-through would show black. The black gets one `.mask` that is **always there** (an always-present modifier keeps the shape's identity, so its open and fold springs are as they were): a full rectangle for the island and a right-hand rectangle for the wing, 80 pt wide in the compact island and 0 wide otherwise, whose opacity is the fade. With `wingYielded` false the mask is fully opaque everywhere, so nothing is drawn differently.

- [ ] **Step 1: Add the view's pins to the wiring test (failing)**

**Edit `tests/IslandWingWiringTests.swift`**

Find:

```swift
        CT.finish()
    }
}
```

Replace with:

```swift
        CT.section("the view: the grid and the ear's black fade with the same animation, and nothing else of the island changes")
        CT.checkTrue("AppState publishes wingYielded and nothing else sets it", app.contains("@Published var wingYielded = false") && count("wingYielded =", in: controller) == 1 && count("wingYielded =", in: island) == 0)
        CT.checkTrue("the grid fades with the wing, after the greeting's fade", island.contains(".animation(.easeInOut(duration: 0.25), value: greetingTail)\n            // The right wing steps aside for the pointer (IslandWing): the grid fades out in 0.15 s and comes back 1 s after the pointer has left.\n            .opacity(state.wingYielded ? 0 : 1)\n            .animation(wingAnimation, value: state.wingYielded)"))
        CT.checkTrue("the animation is quick out and gentler in, from the rules' constants", island.contains(".easeOut(duration: IslandWing.fadeOut) : .easeInOut(duration: IslandWing.fadeIn)"))
        CT.checkTrue("the island's black has one mask, always there, whose right part (the wing, in the compact island only) fades with the grid", count(".mask {", in: island) >= 1 && island.contains(".fill(Color.black)\n                // The right wing steps aside") && island.contains(".frame(width: state.mode == .compact ? max(0, (islandWidth - state.notchWidth) / 2) : 0)") && island.contains(".opacity(state.wingYielded ? 0 : 1)\n                            .animation(wingAnimation, value: state.wingYielded)"))
        CT.checkTrue("the shape's own arguments and the content after it are as they were", island.contains("IslandShape(width: islandWidth, height: islandHeight,\n                        cornerRadius: cornerRadius, topRadius: islandTopRadius)\n                .fill(Color.black)") && island.contains("// Content\n            if state.mode == .expanded {"))

        CT.finish()
    }
}
```

Run: `bash scripts/test-island-wing-wiring.sh 2>&1 | grep -c "✗"`
Expected: FAIL: `3` (the grid's fade, its animation, the mask).

- [ ] **Step 2: The fade and the mask**

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**

Find:

```swift
    private let closeEase  = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.34)
```

Replace with:

```swift
    private let closeEase  = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.34)
    /// The right wing's fade: quick out when the pointer arrives, gentler back (`IslandWing`).
    private var wingAnimation: Animation {
        state.wingYielded ? .easeOut(duration: IslandWing.fadeOut) : .easeInOut(duration: IslandWing.fadeIn)
    }
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**

Find:

```swift
            IslandShape(width: islandWidth, height: islandHeight,
                        cornerRadius: cornerRadius, topRadius: islandTopRadius)
                .fill(Color.black)

            // Content
```

Replace with:

```swift
            IslandShape(width: islandWidth, height: islandHeight,
                        cornerRadius: cornerRadius, topRadius: islandTopRadius)
                .fill(Color.black)
                // The right wing steps aside: its black fades with the grid (always the same mask, so the shape keeps its identity when the island opens and folds).
                .mask {
                    HStack(spacing: 0) {
                        Rectangle()
                        Rectangle()
                            .frame(width: state.mode == .compact ? max(0, (islandWidth - state.notchWidth) / 2) : 0)
                            .opacity(state.wingYielded ? 0 : 1)
                            .animation(wingAnimation, value: state.wingYielded)
                    }
                }

            // Content
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`**

Find:

```swift
            .opacity(greetingTail ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: greetingTail)
        }
        .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)
```

Replace with:

```swift
            .opacity(greetingTail ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: greetingTail)
            // The right wing steps aside for the pointer (IslandWing): the grid fades out in 0.15 s and comes back 1 s after the pointer has left.
            .opacity(state.wingYielded ? 0 : 1)
            .animation(wingAnimation, value: state.wingYielded)
        }
        .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)
```

- [ ] **Step 3: Run the pins and build**

Run: `bash scripts/test-island-wing-wiring.sh 2>&1 | tail -1; xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error|BUILD"`
Expected: `All tests passed.` (18 `✓` lines) and `** BUILD SUCCEEDED **` with no `error` line.

- [ ] **Step 4: The faded state, drawn without the app**

The picture is the checkpoint image. Why a render script can show it: `drawCompact` is the app's own layout for the compact strip (the cats, `CatIslandLayout`, `CatCast`), and the wing's rectangle is `IslandWing.rect`, the rule the poll uses; what the picture cannot show is the real panel passing a click through, which is the owner's real-build check.

**Create `scripts/render-cats-wing.swift`**

```swift
import CoreGraphics
import Foundation

// The compact island's right wing stepping aside, drawn without the app (part of scripts/render-cats.sh: `--wing`). Two strips on a mock menu bar whose right side holds other
// apps' icons: the island as it rests (the grid and the ear's black cover the first icons), and with the pointer over the wing (the grid and the ear's black gone, the icons
// showing, the part that counts dashed). The island is `drawCompact`, the app's own layout numbers; the dashed part is `IslandWing.rect`, the rule the poll uses.

extension RenderCats {

    /// A menu bar `width` by 32 pt at (x, y) with `count` icons from `firstIcon` on, 20 pt apart, as other apps' status items would sit beside the notch.
    @MainActor static func mockMenuBar(_ cg: CGContext, x: Double, y: Double, width: Double, firstIcon: Double, count: Int) {
        cg.fill(CatDraw.roundRect(x, y, width, 32, 0), CatDraw.rgb([76, 78, 86]))
        for i in 0..<count {
            let ix = x + firstIcon + Double(i) * 20
            cg.fill(CatDraw.roundRect(ix, y + 9, 14, 14, 4), CatDraw.white(0.72))
            cg.fill(CatDraw.roundRect(ix + 4, y + 13, 6, 6, 2), CatDraw.rgb([76, 78, 86]))
        }
    }

    /// A pointer arrow with its tip at (x, y).
    @MainActor static func mockPointer(_ cg: CGContext, x: Double, y: Double) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x, y: y + 16)); p.addLine(to: CGPoint(x: x + 4.5, y: y + 12))
        p.addLine(to: CGPoint(x: x + 8, y: y + 19)); p.addLine(to: CGPoint(x: x + 10.5, y: y + 18)); p.addLine(to: CGPoint(x: x + 7, y: y + 11)); p.addLine(to: CGPoint(x: x + 12, y: y + 11))
        p.closeSubpath()
        cg.addPath(p); cg.setFillColor(CatDraw.white(1)); cg.setStrokeColor(CatDraw.black(1)); cg.setLineWidth(1); cg.drawPath(using: .fillStroke)
    }

    @MainActor static func wingSheet(_ a: Args) -> Sheet {
        let rowH = 78.0, left = 150.0, W = 345.0, H = 32.0, barW = W + 90
        let sheet = Sheet(width: left + barW + 16, height: rowH * 2 + 8, scale: a.scale)
        let cg = sheet.cg
        let cast = CatDisplaySample.cast(CatDisplaySettings(mode: a.display, pair: CatDisplaySettings.defaultPair, agentCats: [:]), main: "shrimpy")
        let notch = W - 160   // the mock's notch (the lighter middle of the strip), as wide as drawCompact draws it
        for (i, faded) in [false, true].enumerated() {
            let top = Double(i) * rowH + 8, oy = top + 28
            CatDraw.text(cg, faded ? "Pointer over the wing" : "At rest", x: 14, y: oy + 20, size: 12, bold: true, color: CatDraw.white(0.9), anchor: .left)
            mockMenuBar(cg, x: left, y: oy, width: barW, firstIcon: W - 76, count: 7)
            drawCompact(cg, cast, ox: left, oy: oy, wingFaded: faded)
            if faded {
                let wing = IslandWing.rect(island: CGRect(x: left, y: oy, width: W, height: H), notchWidth: notch, slop: 0)
                cg.saveGState()
                cg.setStrokeColor(CatDraw.white(0.9)); cg.setLineWidth(1); cg.setLineDash(phase: 0, lengths: [4, 3])
                cg.stroke(wing)
                cg.restoreGState()
                mockPointer(cg, x: wing.midX - 2, y: wing.midY - 4)
            }
        }
        return sheet
    }
}
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
        case desktop
        case benchDesktop
    }
```

Replace with:

```swift
        case desktop
        case benchDesktop
        case wing
    }
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
            case "--bench-desktop": a.mode = .benchDesktop
```

Replace with:

```swift
            case "--bench-desktop": a.mode = .benchDesktop
            case "--wing": a.mode = .wing
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
        case .benchDesktop: benchDesktop(); return
```

Replace with:

```swift
        case .benchDesktop: benchDesktop(); return
        case .wing: sheet = wingSheet(a)
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
    @MainActor static func drawCompact(_ cg: CGContext, _ cast: CatCast.Result, ox: Double, oy: Double, kit: KittenScene = KittenScene()) {
        let W = 345.0, H = 32.0
```

Replace with:

```swift
    @MainActor static func drawCompact(_ cg: CGContext, _ cast: CatCast.Result, ox: Double, oy: Double, kit: KittenScene = KittenScene(), wingFaded: Bool = false) {
        let W = 345.0, H = 32.0
        // `wingFaded`: the right wing has stepped aside (IslandWing), so its black and the grid are not drawn.
        if wingFaded { cg.saveGState(); cg.clip(to: CGRect(x: ox - 2, y: oy - 2, width: W - 80 + 2, height: H + 4)) }
        defer { if wingFaded { cg.restoreGState() } }
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
        for (i, p) in cast.pills.enumerated() {
            let sp = samplePill(p.pill)
            drawIslandCat(cg, p.cat, sp?.state ?? .idle, colour: sp?.color, big: false, cx: ox + W - 40
```

Replace with:

```swift
        for (i, p) in (wingFaded ? [] : cast.pills).enumerated() {
            let sp = samplePill(p.pill)
            drawIslandCat(cg, p.cat, sp?.state ?? .idle, colour: sp?.color, big: false, cx: ox + W - 40
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
//   bash scripts/render-cats.sh --bench-desktop 
```

Replace with:

```swift
//   bash scripts/render-cats.sh --wing [--mode one|perAgent|two]   the compact island's right wing stepping aside: at rest, and with the pointer over it (the grid and the ear's black gone, the menu bar's icons showing)
//   bash scripts/render-cats.sh --bench-desktop 
```

**Edit `scripts/render-cats.sh`**

Find:

```bash
scripts/render-cats.swift scripts/render-cats-desktop.swift \
```

Replace with:

```bash
scripts/render-cats.swift scripts/render-cats-desktop.swift scripts/render-cats-wing.swift \
```

**Edit `scripts/render-cats.sh`**

Find:

```bash
    $APP/CatIslandLayout.swift \
```

Replace with:

```bash
    $APP/CatIslandLayout.swift $APP/IslandWing.swift \
```

- [ ] **Step 5: Draw it in the three display modes and look**

```bash
mkdir -p "${TMPDIR:-/tmp}/wing-1"
bash -n scripts/render-cats.sh && for m in one perAgent two; do bash scripts/render-cats.sh --wing --mode $m --scale 2 --out "${TMPDIR:-/tmp}/wing-1/wing-$m.png" 2>&1 | tail -1; done
```

Expected: three lines `wrote …/wing-1/wing-one.png`, `…wing-perAgent.png`, `…wing-two.png`. Open each and say in one sentence what you see. Expected to see, in each: two strips on a grey menu bar with seven small icons on its right. The top strip ("At rest") has the black island with the grid of small cats in its right ear, covering the first four icons. The bottom strip ("Pointer over the wing") has the same left ear and notch, the right ear's black and the grid gone, those four icons showing, a dashed rectangle exactly where the right ear was and a pointer in it. In the Two cats picture both cats are in the left ear on both strips.

- [ ] **Step 6: The other render modes are as they were**

Run: `bash scripts/render-cats.sh --island --scale 2 --out "${TMPDIR:-/tmp}/wing-1/island.png" 2>&1 | tail -1`
Expected: `wrote …/wing-1/island.png` (open it: the compact and expanded islands in three modes, with the grid drawn in each compact strip).

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add scripts/render-cats-wing.swift scripts/render-cats.swift scripts/render-cats.sh NotchBuddy/Sources/App/IslandRootView.swift tests/IslandWingWiringTests.swift
MSG="$(mktemp "${TMPDIR:-/tmp}/wing-msg.XXXXXX")"; printf '%s\n' "feat(island): the right wing's grid and black fade out" "" "Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>" > "$MSG"; git commit -F "$MSG"; trash "$MSG"
```

---

### Task 4: Docs, the last checks and the checkpoint picture

**Files:** Modify `docs/SPEC.md`, `CLAUDE.md`.

- [ ] **Step 1: The spec paragraph (French, as the spec is) and the map line**

**Edit `docs/SPEC.md`**

Find:

```text
Grille compact : pastilles Ø 9,5 autour du point (largeur − 27, hN/2), écart ±6. 1 agent : centré. 2 : côte à côte. 3 : deux en haut, un en bas. 4 : carré.
```

Replace with:

```text
Grille compact : pastilles Ø 9,5 autour du point (largeur − 27, hN/2), écart ±6. 1 agent : centré. 2 : côte à côte. 3 : deux en haut, un en bas. 4 : carré.

**L'aile droite s'efface** (macOS seulement). Sur une barre de menus chargée, la grille de l'oreille droite recouvre les icônes des autres apps à côté du notch, et macOS ne permet pas de les déplacer. Quand le pointeur est sur l'aile droite du `compact` (du bord droit du notch au bord droit de l'île, sur toute la hauteur de la bande), la grille et le noir de l'oreille s'effacent en 0,15 s et la zone laisse passer les clics vers les icônes dessous ; le gros chat (l'oreille gauche) reste. La grille revient 1 s après que le pointeur a quitté la zone. Survoler le notch ou le gros chat ouvre l'île comme avant ; survoler l'aile droite ne l'ouvre plus. Rien ne s'efface quand la grille est vide, pendant la queue du salut, pendant un glisser du chat, ni quand un bouton de la souris est déjà enfoncé à l'arrivée du pointeur (un fichier que l'on glisse dans l'île). Les trois modes (un chat, un chat par agent, deux chats) ont la même aile droite, la grille ; le chat 2, les chatons et le « ×N » sont dans l'oreille gauche et ne bougent pas. Windows et Linux : rien, l'île y est collée en haut de l'écran, sans barre de menus dessous. Règles pures : `IslandWing.swift` ; tests : `scripts/test-island-wing.sh` et `scripts/test-island-wing-wiring.sh`.
```

**Edit `docs/SPEC.md`**

Find:

```text
Clic sur le bonhomme en compact → `expanded` tout de suite.
```

Replace with:

```text
Clic sur le bonhomme en compact → `expanded` tout de suite. Le survol de l'aile droite (la grille) n'ouvre pas : elle s'efface (voir plus haut).
```

**Edit `CLAUDE.md`**

Find:

```text
The Windows and Linux app has none.
```

Replace with:

```text
The Windows and Linux app has none.
- `NotchBuddy/Sources/App/IslandWing.swift` — the compact island's right wing steps aside (Mac only): with the pointer over the grid of agent cats the grid and the ear's black fade out in 0.15 s, the panel passes the mouse on to the menu-bar icons under it, and the grid comes back 1 s after the pointer leaves; the pointer over the wing no longer opens the island. Pure Foundation rules, fed by `IslandWindowController.pollFrame` (the existing poll: no timer or monitor of its own) and tested by `scripts/test-island-wing.sh`; `scripts/test-island-wing-wiring.sh` pins the app-side call sites; `render-cats.sh --wing` draws the faded state (`docs/SPEC.md`, "L'aile droite s'efface").
```

- [ ] **Step 2: Every test this plan touches, the leftovers guard and the builds**

```bash
for f in scripts/test-island-wing.sh scripts/test-island-wing-wiring.sh scripts/test-island-poller.sh scripts/test-cat-wiring.sh scripts/test-cat-cast.sh scripts/test-cat-agent-list.sh scripts/test-cat-kittens.sh scripts/test-screen-geometry.sh; do printf '%-44s' "$f"; bash "$f" 2>&1 | tail -1; done
bash scripts/check-no-leftovers.sh 2>&1 | tail -2
cd NotchBuddy && xcodegen && cd .. && git status --short NotchBuddy/NotchBuddy.xcodeproj
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "BUILD|error:"
```

Expected: eight lines ending `All tests passed.` (the island poller's ends `IslandPoller: visible … Hz, hidden 10 Hz, shown again … Hz`; the screen geometry's, whatever it ended on at Task 0), the leftovers guard's `✓` lines, no output from `git status --short` (Task 1 committed the regenerated project file, and regenerating it again changes nothing), and two `** BUILD SUCCEEDED **` lines (Debug and App Store: the wing is in both builds).

- [ ] **Step 3: Collect the checkpoint pictures**

```bash
mkdir -p .claude/checkpoints/wing && cp "${TMPDIR:-/tmp}/wing-1/wing-one.png" "${TMPDIR:-/tmp}/wing-1/wing-perAgent.png" "${TMPDIR:-/tmp}/wing-1/wing-two.png" .claude/checkpoints/wing/ && ls .claude/checkpoints/wing
```

Expected: the three PNGs. (The folder is the worktree's own and is gitignored.)

- [ ] **Step 4: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add docs/SPEC.md CLAUDE.md
MSG="$(mktemp "${TMPDIR:-/tmp}/wing-msg.XXXXXX")"; printf '%s\n' "docs: the right wing steps aside" "" "Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>" > "$MSG"; git commit -F "$MSG"; trash "$MSG"
```

The version and the changelog line are the release's, not this plan's (Open question 4). Then the session dispatches `nm-reviewer-deep` over `git diff notchmeow/rebrand...HEAD`, fixes what it finds, and stops for Task 5.

---

### Task 5: Owner checkpoint: the picture, then the real-build checks

No code and no commit. The session reports; the main session sends the owner the pictures and the list.

**The picture** (`.claude/checkpoints/wing/wing-*.png`): is the faded state what you meant: the grid and the black of the right ear gone, the icons underneath showing, the main cat (left ear) and the notch untouched? Is the dashed part (the part that counts: from the notch's right edge to the island's right edge, the strip's height) the part you want? In Two cats both cats are in the left ear.

**The owner's real-build checks** (a Debug build or the 0.9.1 candidate, on a notch Mac whose menu bar has third-party icons to the right of the notch; the plan could not run the app):

1. **The click-through.** Start a task so the compact island shows with agent cats in its right wing. Move the pointer onto the grid: it fades within about a fifth of a second and the icons under it show. Click one of those icons: its menu opens (and the island does not open).
2. **The return.** Move the pointer off the wing: the grid is back after about a second, not sooner. Move it back before the second ends: the grid stays away and the second starts again.
3. **The notch still opens it.** Hover the notch, and hover the main cat in the left ear: the island opens as before. Hover the wing only: it does not open. Click the notch or the main cat: it opens.
4. **No wing, no change.** With only one agent (so the grid is empty), hover the right ear: the island opens as it did in 0.9.0, and nothing fades.
5. **All three modes.** One cat, A cat for each agent, Two cats (Settings → Cat → Display): the right wing is the grid in each, and cat 2 and the kittens (start a subagent) stay in the left ear and never fade.
6. **A file dragged in.** Drag a file from Finder across the right wing into the island: it is accepted as before (the wing does not fade while the button is held).
7. **The island opening and folding looks as it did.** Open and fold it several times (hover the notch, wait, move away; an approval): the black shape's spring and corners are the same as 0.9.0, with no flash or clipping at the right edge.
8. **Hidden costs nothing.** Let the island hide (no tasks): Activity Monitor shows NotchMeow at 0 % as before.
9. **A second screen without a notch.** On an external display the compact bar has the same 80 pt wings: the same check 1 to 3 there.

---

## Parity with Windows/Linux

None, and none is wanted: the Windows and Linux island sits at the top of the screen with no menu bar under it, so nothing is covered. `windows/` is untouched. (CLAUDE.md: the Mac gets at least what the others get; this is a Mac-only extra, like Windows OCR is Windows-only.)

## Open questions for the owner

Each has the answer this plan assumes, so nothing blocks. A different answer changes one small thing, named in each.

1. **The right ear's black fades with the grid.** The design says the grid fades; the island's black fill covers the icons as much as the cats do, so fading only the grid would pass the click through to icons nobody can see. **Assumed: the black of the right ear fades too** (the mask in Task 3). If only the grid should fade, Task 3 drops the mask and the dashed ear stays black.
2. **The grid comes back with a 0.25 s fade** (the grid's existing fade), after the 1 s. The design names only the 0.15 s out and the 1 s return. **Assumed: 0.25 s** (`IslandWing.fadeIn`).
3. **A mouse button held when the pointer arrives never starts the fade** (a file dragged in), and a wing with no cat in it never fades. Neither is in the design; both keep what ships working. **Assumed: yes.**
4. **The version and the changelog line are the release's.** This plan does not bump 0.9.0 and does not edit `CHANGELOG.md` (`scripts/set-version.sh`, `scripts/check-versions.sh`). For 0.9.1's changelog: "In the compact island the right wing steps aside (macOS): with the pointer over the agent grid it fades and lets clicks through to the menu-bar icons under it, and comes back a second after the pointer leaves. The notch and the main cat still open the island." **Assumed: yes.**
5. **A new bullet in `CLAUDE.md`** (the map of the app's files), as the earlier plans did for their test scripts. **Assumed: yes.**
6. **One click in the first tick.** A click that lands in the 16.7 ms between the pointer reaching the wing from the notch side and the next poll tick is taken by the panel as a click on the island. Not worth a second mechanism. **Assumed: OK.**

## Self-review

- **Design coverage.** The fade in about 0.15 s (`IslandWing.fadeOut`, the view's animation: Tasks 1 and 3), the click-through while faded (the poll's `ignoresMouseEvents` toggle now sees the wing as outside the island: Task 2), the main cat stays (the wing is the right ear only; Task 1's rectangle rows, Task 3's pictures), the grid back 1 s after the pointer leaves (`returnDelay`: Task 1), hover on the notch and the cat opens and hover on the wing does not (`inIsland … && !wing.passThrough`: Task 2), Mac only (stated; `windows/` untouched).
- **Modes.** One cat, A cat for each agent, Two cats, kittens, no wing, the greeting's tail, a drag, a screen with no notch: "The click-through mechanism, and why", Task 1's rows and Task 3's three pictures.
- **Placeholders.** None: every code step is a **Create** or **Edit** block from the files the dry run ran, and every `Run:` line has its expected output.
- **Type consistency.** `IslandWing.Yield.step(now:inWing:active:buttonDown:hasWing:)` and `Out { faded, passThrough }` (Task 1) are what the poll calls (Task 2); `AppState.wingYielded` (Task 2) is what the view reads (Task 3); `IslandWing.fadeOut`, `fadeIn` and `rect` (Task 1) are what the view and the picture use.
- **Review Focus.** Lines 1 to 5 each have their tests, named in the line.
- **What this plan deliberately does not do:** a second window, a mouse monitor, a timer; touch `CompactMiniGrid`, the island's size or shape, the state machine, the poller's rates or anything under `windows/`; store a setting; bump the version.

## Dry run (2026-10-13)

The plan was run before it was handed over, in a throwaway `git clone --local --shared --branch notchmeow/rebrand` at `ee5f509` (the scratchpad's `wing-replay`), by a small runner that read this file: it applied each **Create** block (7) and each **Edit** block (21) of Tasks 1 to 4 in the plan's order, failing when a find text occurred other than once, and the commands below were run by hand between the steps. Nothing was committed or pushed, no NotchMeow app was started, nothing was installed or downloaded, and the only file this work added to the main checkout is this plan.

| Task | What the run printed (the plan's Expected) |
|---|---|
| 0 | the four greps print `1`; `ee5f509` is an ancestor of `HEAD` |
| 1 | red: `error opening input file`; green: 39 `✓`, `All tests passed.`; the three bites print `3 test(s) failed.`, `1 test(s) failed.`, `2 test(s) failed.`; `xcodegen` adds `1 file changed, 6 insertions(+)` to the project |
| 2 | red: 7 `✗`; green: 13 `✓`, and `test-island-wing.sh`, `test-island-poller.sh` (visible 59 Hz, hidden 10 Hz, shown again 60 Hz) and `test-cat-wiring.sh` still pass; Debug build `** BUILD SUCCEEDED **`; the bite prints `1 test(s) failed.` |
| 3 | red: 3 `✗`; green: 18 `✓`; Debug build succeeded; `--wing` drawn in One cat, A cat for each agent and Two cats (looked at: both strips, the faded one with the icons showing, the dashed wing and the pointer, both cats in the left ear in Two cats); `--island` still draws |
| 4 | the eight test lines end as expected; the leftovers guard's `✓` lines; the project file unchanged by a second `xcodegen`; Debug and App Store builds `** BUILD SUCCEEDED **` |

**What the dry run changed in the plan** (each was a defect in an earlier draft):

- **`test-cat-wiring.sh` failed after the first draft of Task 2.** The first draft made `CompactMiniGrid` read a new `AppState.miniGridPills`; the existing pin "the row and the 2x2 grid are the cast's pills" wants `state.cast.pills` in `IslandRootView.swift`. The view is now untouched, `AppState.hasMiniGrid` is the same rule written out once more, and `IslandWingWiringTests` pins both texts.
- **`CGRect.midX` needs CoreGraphics:** `IslandWing.swift` imports it (and splits one expression the type checker would not take).
- **The mouse-button and cat tests were eager.** `step` took `buttonDown: Bool`, which made every 10 Hz hidden tick ask `NSEvent.pressedMouseButtons`; it is a closure now, asked only when a fade is about to begin, with a test that a non-compact island never asks.
- **`xcodebuild ... | tail -1` prints an empty line;** the build steps grep for `BUILD|error:`.
- **Commit steps use `git commit -F`** with a message file written by the step itself (the first draft had a placeholder that is not shell).

**Not run, and owed.**

- **Any commit step.** The four `git add` and `git commit` blocks were skipped and have to be run by the executing session in its worktree.
- **The app itself.** No NotchMeow window was opened, so the real panel (the pass-through to another app's menu-bar icon, the poll's first tick, `NSEvent.pressedMouseButtons` during a Finder drag, the mask's effect on the open and fold springs, a second screen) is Task 5's list for the owner, not something this run proved. The faded state was drawn by the real layout code and the pure rule; the wiring was proved by source pins.
- **Release build and signing.** Only the Debug and App Store builds ran (unsigned); a Release build adds nothing that is conditional on this code.
- **Windows and Linux.** Nothing under `windows/` is touched.

The throwaway clones and the pictures' folders were moved to the Trash afterwards (`trash`, never `rm -rf`).


## The owner's answers (2026-10-13)

- **Approved as assumed:** every open question takes its assumed answer, the `CLAUDE.md` bullet included. Runs now, for 0.9.1.
