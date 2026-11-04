# Fixes after H: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Six small fixes the owner approved on 2026-10-13, after the desktop cat (H) merged, in one branch for 0.9.1: (1) the French words left in code comments go; (2) the approval-card render tool can no longer read the real `~/.claude/settings.json`; (3) `scripts/check-site.sh` catches the holes its ledger listed; (4) `CLAUDE.md` names the desktop cat's light checks as the documented exception to "0 % CPU when the island is hidden"; (5) a file dropped on the notch while the desktop cat is out is caught by that cat, which flies in, plays the catch and flies back, with never two cats, on both apps; (6) in Two cats mode only cat 1 leaves the notch, and a press in cat 2's part of the overlap drags nothing, on both apps.

**Architecture:** Items 1 to 4 are text and shell. Item 5 is one new idea and almost no new machinery: **a file on its way into the island is an alert to the desktop cat.** To `desktopStep` it is `alertOn` and `alertOff`, which already fly the cat to the notch (surprised emote, 0.6 s arc), hold it there (`atNotchForAlert`) and fly it back to its spot (`returning`), so the contract gets no new phase, event or act and every older fixture row stands. What the contract does gain, additively, is the one rule for "something wants the cat at the notch" (`desktopAlert`, with a `fileCatch` input), the one test the catch waits on (`desktopCatchReady`) and one constant (`DESKTOP_CATCH_WAIT_MS`), pinned by new keys and trip rows in `desktop-cases.json`. Each app then (a) feeds `fileCatch` from what it already knows about the drop flow, (b) makes the island's catch canvas draw **no cat of its own** while the desktop cat is out (`notchEmpty`), so the one cat on screen is the desktop cat in the air and then the catch's cat at the notch, and (c) holds a dropped file for at most 1.5 s until the cat has landed. Item 6 moves the Windows/Linux and Mac hit tests onto one pure rule (`bigCatPressed`, `CatIslandLayout.bigCatPressed`) that knows cat 2.

**Tech Stack:** Swift 6, SwiftUI, AppKit, `swiftc` test programs, Bash, `sandbox-exec` (macOS), Node 22 (`--experimental-strip-types`), TypeScript, Tauri/Rust (only run, never edited), XcodeGen.

**Spec:** the owner's approved scope of 2026-10-13, restated under "The six items" below (there is no spec file). The desktop cat's rules are `docs/CAT-CONTRACT.md` "The desktop cat (H-0)", `docs/SPEC.md` "Le chat de bureau" (in French) and `design/prototype/cat-core.js`. The ledger lines these fixes come from are in `.claude/archive/owner-manual-checks.md` (sections D1-tools, D1-site, H-mac, H-tauri).

**Base:** a new branch `fixes/after-h` in a git worktree, from `notchmeow/rebrand` at `9b2039e` or later (`git merge-base --is-ancestor 9b2039e HEAD` must succeed). Item 5 changes `design/prototype/cat-core.js`, `scripts/gen-cat-fixtures.mjs` and `tests/fixtures/cat/desktop-cases.json` (additively; the SUBAGENT RULE that forbids those is lifted for Task 5 only and says so). Nothing under `windows/src-tauri/` changes.

## The six items (the owner's scope, 2026-10-13)

1. **French words left in code comments.** Found by grepping Swift, TypeScript and Rust for French in comments: three, all about the step rows. The step words are English now (`SessionStepText`: "Reads", "Runs"), but `ClaudeChatViews.swift:29` and `windows/src/core/claude.ts:95` still quote the old French "Lit · README.md", and `HookServer.swift:1115` says `// MARK: - French step labels`. Comments only: never a user-facing string, `docs/SPEC.md` (French by design) or a test fixture. The private function `frenchStep` is code, not a comment, and keeps its name (Open question 1). The rest of the app's comments are English: the accented letters left in comments are `Bézier`, `Théodore` and `Raillé` (proper names) and `Zoé`/`é` in two Rust tests' sample data.
2. **The approval-card render tool must never read the real `~/.claude/settings.json`.** `scripts/render-approval-card.sh` already ran the tool with `HOME` set to an empty folder, but the app's "is Claude Code connected" checks use `FileManager.default.homeDirectoryForCurrentUser`, which asks the user database and ignores `$HOME`. The dry run proved the tool does read it: run under a sandbox profile that kills any process opening that file, the tool dies. The fix is two layers in one sourced helper: `CFFIXED_USER_HOME` points Foundation at the empty home (the tool then reads the empty one: the picture is byte-identical), and a `sandbox-exec` profile kills the tool if it ever opens the real `~/.claude`, `~/.gemini` or `~/.codex`. A test proves the fence bites and that the app-style home lookup follows the fake home. The app itself is untouched (the app has no `NM_`-style home override, and adding one would touch the hook installer's code).
3. **Harden `scripts/check-site.sh`:** AudioContext, `new Audio(`, `new Image(`, `ping=`, `http-equiv=refresh`, every `srcset`/`imagesrcset` candidate, and a scan of `docs/assets/img` (no outside URL in any picture or its metadata; an SVG may not run or load anything). `scripts/test-check-site.sh` gets a failing case for each.
4. **A `CLAUDE.md` clause** naming the desktop cat's light checks as the documented exception to "Performance: 0 % CPU when the island is hidden": on Windows and Linux a cursor check at about 10 Hz and a screens/fullscreen check at 2 Hz; on the Mac the mouse-moved monitor; only while the cat is out and awake; all stop when the cat is home, locked or the display is off; under 1 % of a core when idle.
5. **A file dropped while the desktop cat is out: the desktop cat catches it.** Today both apps draw a second cat. See "The file catch" below for what each does and the design.
6. **Two cats mode overlap: only cat 1 leaves.** The Windows/Linux `isBotHit` passes `null` for the second circle, so a press in cat 2's part of the overlap with cat 1 carries cat 1 out of the notch. The Mac's `isBotHit` has no idea cat 2 exists and does the same (a drag out, a window attach drag, the slap). Both move onto one pure rule where the nearer centre wins and a press that is cat 2's drags nothing.

## The file catch (item 5): what each app does today, and the design

**Today, on both apps, two cats show.** Windows/Linux: `island.ts` draws `UploadCanvas` (its own `BotEngine` cat at the notch) whenever the drop flow is on, whatever `State.desktopNotchEmpty` says. The Mac: `IslandContainer` shows `UploadCanvasView(state:cat:)` the same way, and `UploadCanvasView.drawCat` has no look at `state.desktopPhase`; `BotPlacement` is the only view that hides the notch's cat while it is out (`if !state.desktopPhase.notchEmpty`), and it is already hidden during the drop flow. So a file dragged to the notch while the desktop cat is out gives a catch cat at the notch **and** the cat on the desktop. (The ledger noted this for Windows/Linux as M9; the Mac has the same bug.)

**The owner's choice:** the desktop cat flies to the notch as an alert flight does; the catch plays with that cat; it flies back to its spot; never two cats.

**The design, reusing the alert flight:**

- **What starts and ends it.** "A file is on its way in" is true from the first drag-over of the island, through a drop that is waiting for the cat, until the drop flow ends (the choose card is answered, the flow is left, a refused file's note is over). That is the island's own notion of the drop flow: Mac `state.fileDragOver || (UploadSequenceEngine.shared.isActive && mode == .expanded && view in [.upload, .uploading, .choose])`; Windows/Linux `State.fileDragOver || dropWaiting || uploadActive`. It is fed to the machine as the `fileCatch` input of `desktopAlert`, together with the approvals, so an approval that arrives mid-catch keeps the cat at the notch until both are clear. The island keeps the drop view open after a drag that leaves without a drop (the drag session may come back), so the cat stays at the notch until the island folds that view; if the view folds before the cat has landed, the cat turns round mid-flight without a jump (`retracting` + `alertOff` is `returning`, existing behaviour).
- **Where the cat lands.** `notchSpot` already follows the island: for the open upload view it is `viewLayouts[.upload]` (botX 140, botY 104, Ø62 on the Mac; the same numbers in `windows/src/core/layout.ts`), which is exactly where the catch canvas puts its cat, so the dock does not jump.
- **No second cat.** While `notchEmpty` (flying out, on the desktop, retracting, returning) the catch canvas draws **no cat** (Mac `UploadCanvasView.drawCat` returns nil; Windows `UploadCanvas.drawCat` returns), and the file under the pointer still draws. The moment the cat docks (`atNotchForAlert`: `notchEmpty` false) the canvas draws its cat at the notch, and the desktop window has already hidden its copy (`dock` acts `hide`). A frame count in the picture proves one cat in every frame.
- **A drop that lands before the cat has.** The flight is the surprised emote (450 ms) plus 600 ms, so a quick drop can arrive first. The drop waits for `desktopCatchReady(phase)` (the cat is at the notch) for at most `DESKTOP_CATCH_WAIT_MS` (1500 ms), then the catch plays. The wait is a short `Task.sleep`/`setTimeout` loop that exists only during a drop: no timer, no monitor. If the cat has not landed after 1.5 s (a stuck flight) the catch plays without drawing a cat rather than blocking the drop (Open question 4).
- **Contract change, additive only.** No new phase, event or act. New in `cat-core.js`: `DESKTOP_CATCH_WAIT_MS` (1500), `desktopAlert(input)` (the one OR of the alert sources, with `fileCatch`), `desktopCatchReady(phase)` (the cat is at the notch: home or `atNotchForAlert`). New in `desktop-cases.json` (keys and trip rows added; `node scripts/check-fixtures-additive.mjs 9b2039e` proves no old line moved): `catchWaitMs`, `catchNote`, `alertCases`, `catchReady`, and four trips named "a file catch…". The cat at home is untouched: `alertOn` at `home` is already a no-op.
- **Reused, not rebuilt.** `retract`/`flyOut`/`turn`/`dock`/`goHome`, the 450 ms surprise, the flight maths, `notchMoved`, the island's own upload sequence, `FileDropHandler`/`swallow` and the canvas stay as they are.

## Global Constraints

Every task's requirements include this section.

- **Swift 6, SwiftUI and AppKit, TypeScript; no third-party dependencies.** Shell scripts are Bash 3.2 compatible (macOS).
- **0 % CPU when the island is hidden, and no polling of its own.** No new `Timer`, `DispatchSourceTimer`, display link or `NSEvent` monitor; no new `setInterval`. The file catch's wait is a `Task.sleep` / `setTimeout` chain that exists only while a dropped file waits for the cat (at most 1.5 s), and the home cat adds nothing: `alertOn` at `home` does nothing.
- **Never restyle a shipping view.** The only visible change of item 5 is that the catch canvas draws no cat while the desktop cat is out; with the cat home every view is as it was. Item 6 changes which press starts a drag, nothing visible.
- **Frozen values.** Phase IDs, event IDs, act IDs (no addition: the nine events and eleven acts stay), pill IDs, cat IDs, display mode IDs, UserDefaults keys and every contract string are untouched. This plan stores nothing.
- **Never block Claude Code; never overwrite `~/.claude/settings.json`.** Item 2 makes a render tool unable to touch it; no task reads or writes the real one.
- **The contract decides.** `cat-core.js` is the tie-breaker. After Task 5 changes it, `node scripts/gen-cat-fixtures.mjs` regenerates the fixtures and `node scripts/check-fixtures-additive.mjs 9b2039e` must pass; both apps replay the new keys.
- **Never edit `NotchBuddy.xcodeproj` by hand.** No task adds a file to the Xcode target (the new Swift files are test programs and a script helper), so `xcodegen` is not needed; if one is run anyway the project file must not change.
- **No `UserDefaults` suite and no write to `UserDefaults.standard` or `~/Library` in a test or script.** Tests run through `scripts/test-*.sh`, which set `NM_LOG_DIR` to a temp folder.
- **Rust runs only through `windows/scripts/cargo-linux.sh`, offline, with `--target-dir /repo/windows/target/fixes-after-h`, and never builds or pulls an image.** No Rust file changes in this plan; the Rust tests are a regression run.
- **Models and commits** (CLAUDE.md, "Working with AI agents", 2026-10-12): Haiku 5.5 first, Sonnet 5.5 only on a named trigger, never Opus or Fable. Each commit is local only, never pushed, lists only the files its task names, and ends with the `Co-Authored-By` line of the model that did the task: `Claude Haiku 5.5` for `nm-implementer-light` and `nm-implementer`, `Claude Sonnet 5.5` for `nm-implementer-deep`.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app. A Debug or App Store **build** in the worktree is fine and is only built; the scripts that draw a PNG (`render-cats.sh`, `render-approval-card.sh`) are not the app and may run. No task sends a hook event to the app's socket.
  2. Install nothing. No network calls, no downloads, no `docker build` or `docker pull`.
  3. Use `trash`, never `rm -rf`, for anything you delete by hand; put scratch files under `${TMPDIR:-/tmp}` in a folder with a unique name. (The test and render scripts clean their own `mktemp` folders with `rm -rf` in a `trap`, as every `scripts/test-*.sh` does: that is the repo's convention, not a command an agent runs.)
  4. No `UserDefaults` suite and no write to `UserDefaults.standard` or `~/Library` in a test or script.
  5. Never edit `design/prototype/cat-core.js`, `scripts/gen-cat-fixtures.mjs`, a fixture of `tests/fixtures/`, `shared/theme.json`, a generated theme file or anything under `windows/src-tauri/`, **except in Task 5** (which names its files and adds only).
  6. Never push. Commit only in a task's commit step, after checking the worktree and the branch.
  7. Haiku 5.5 for every task; Sonnet 5.5 (`nm-implementer-deep`) only for a task Haiku failed twice, with the trigger named in the ledger; never Opus or Fable.
  8. Never rename a frozen ID, and write no `Coucou` or `Mochi` name anywhere (`scripts/check-no-leftovers.sh` must stay green).
  9. Never read, print or write the real `~/.claude/settings.json` (or anything in the real `~/.claude`, `~/.gemini`, `~/.codex`), by hand or in a script.
  10. If a command is denied by a permission prompt, stop and report it. Do not look for a workaround.

## Review Focus

The six items say what changes. They are silent on these conditions, and each would bite a person first, most likely first. Each names the test that pins it.

1. **A file dragged to the notch while the desktop cat is out, in each of its phases** (on the desktop, mid-flight out, retracting, already at the notch for an approval). Expected: one cat on screen in every frame; the cat is at the notch before the catch plays; an approval that is pending when the catch ends keeps the cat at the notch. Tests: Task 5 (`alertCases`, the four "a file catch" trips, `catchReady`), Tasks 6 and 7 (the island draws no cat while `notchEmpty`), the picture's per-frame count.
2. **The drop view folding before the cat has landed, a drop that is refused, and a drop that lands before the cat has.** Expected: the cat turns round mid-flight and returns (no jump); a refused file still gets its cough with the cat at the notch and the cat returns when the note is over; a quick drop waits up to 1.5 s and then plays (never blocks). Tests: Task 5's trip "a file catch: the drop view folds before the cat has landed", Tasks 6 and 7 (the wait is bounded; the alert holds while the drop waits: `fileDragOver` stays true on the Mac until `handle` runs and `dropWaiting` on Windows/Linux).
3. **The cat at home, and the greeting.** Expected: nothing changes when the cat is home (`alertOn` at `home` is `act: null`; the canvas draws its cat because `notchEmpty` is false; `waitForCat` returns at once). Tests: Task 5's trip "a file catch with the cat at home changes nothing", Tasks 6 and 7's pins.
4. **The overlap in Two cats mode, compact and expanded.** Expected: a press nearer cat 2's centre than cat 1's, inside both circles, is cat 2's and starts no drag, slap or attach on either app; a press only in cat 1's circle still does; with one cat or no second cat nothing differs from today. Tests: Task 8 (`bigCatPressed` rows in both apps, the source pins).
5. **The render guard on a machine where the real home cannot be told, or where `sandbox-exec` is gone.** Expected: the render fails closed with a plain message and runs nothing; it never falls back to an unguarded run. Test: Task 3 (the guard's own refusal is run).
6. **A site image with an XMP block or an SVG with `xmlns`.** Expected: namespace declarations are names, not requests, and pass; any other address, and in an SVG a script, an event handler, `foreignObject`, `@import` or an external `href`, fails. Tests: Task 4 (a clean site with both, and one failing case per rule).

---

## File Structure

| Path | Responsibility |
|---|---|
| `NotchBuddy/Sources/App/ClaudeChatViews.swift`, `HookServer.swift`, `windows/src/core/claude.ts` | Comment fixes (item 1). |
| `scripts/check-no-leftovers.sh` | Keeps the French step words out of the comments. |
| `scripts/render-home-guard.sh` (new), `scripts/render-approval-card.sh`, `scripts/test-render-home-guard.sh` (new), `tests/HomeProbe.swift` (new) | Item 2. |
| `scripts/check-site.sh`, `scripts/test-check-site.sh` | Item 3. |
| `CLAUDE.md` | Item 4's clause, and the map bullet for this plan. |
| `design/prototype/cat-core.js`, `scripts/gen-cat-fixtures.mjs`, `tests/fixtures/cat/desktop-cases.json`, `docs/CAT-CONTRACT.md` | The file catch's contract (Task 5). |
| `NotchBuddy/Sources/App/DesktopCatTrip.swift`, `DesktopCatController.swift`, `FileDropView.swift`, `UploadCanvasView.swift`, `tests/DesktopCatTripTests.swift`, `tests/DesktopCatWiringTests.swift` | The file catch on the Mac (Task 6). |
| `scripts/render-cats.swift`, `scripts/render-cats-desktop.swift` | `render-cats.sh --desktop-catch`: the checkpoint picture (Task 6). |
| `windows/src/cat/desktop.ts`, `windows/src/core/state.ts`, `windows/src/island/desktop.ts`, `windows/src/island/island.ts`, `windows/src/upload/canvas.ts`, `windows/src/cat/devdesktop.ts`, `windows/scripts/cat-tests/desktop-catch.test.mjs` (new), `windows/scripts/cat-tests/desktop-alert.test.mjs` | The file catch on Windows/Linux (Task 7). |
| `NotchBuddy/Sources/App/CatIslandLayout.swift`, `IslandWindowController.swift`, `tests/CatPressTests.swift` (new), `scripts/test-cat-press.sh` (new), `windows/src/core/layout.ts`, `windows/src/island/island.ts`, `windows/scripts/cat-tests/two-cats-overlap.test.mjs` (new) | Item 6 (Task 8). |
| `.github/workflows/build.yml`, `docs/SPEC.md` | CI steps and one French sentence (Task 9). |

## Tasks and agents

CLAUDE.md: the lightest model that fits. **Haiku 5.5 first; Sonnet 5.5 only on a named trigger.** Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion` (the deep agent also `superpowers:systematic-debugging`); reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). Effort: **medium** for light tasks (code given in full), **high** for `nm-implementer` and for every review.

| # | Task | Agent, model, effort | Review |
|---|---|---|---|
| 0 | Worktree and baseline | the session | none |
| 1 | French words in comments, and the guard that keeps them out | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 2 | The `CLAUDE.md` clause | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 3 | The approval-card render tool and the real home | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 4 | `check-site.sh` hardening | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 5 | The file catch's contract (additive) | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 6 | The file catch on the Mac, and the checkpoint sheet | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 7 | The file catch on Windows and Linux | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 8 | Two cats overlap: only cat 1 leaves, both apps | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 9 | CI, the French spec sentence, the last checks and the pictures | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| After 9 | The whole branch: the contract against both ports, the render guard, the Review Focus | `nm-reviewer-deep`, Sonnet 5.5, high (trigger 4) | none |
| 10 | **Owner checkpoint:** the pictures, then the real-build checks | the main session and the owner | none |

**No task needs Sonnet up front.** Every code block is given in full and was applied in the dry run; Tasks 6 and 7 are the only ones with judgement (a `Task.sleep` wait in a main-actor handler, a `setTimeout` chain in the island), and neither designs a platform API. If a Haiku task's expected output differs and the cause is not obvious, or it fails twice, hand that task to `nm-implementer-deep` (trigger 2) and say so in the ledger.

## Execution

One worktree chat session runs the whole plan: branch `fixes/after-h`, model **Haiku 5.5 at high effort**. **This is not trigger 5**, even though item 5 crosses two apps, because the two apps never talk to each other: they meet only at the contract (Task 5), whose three new names and their fixture rows are given in full, and each port is a short edit of files that already exist. There are nine small tasks, no hard integration, no platform API to design and no concurrency beyond one bounded sleep loop. Nothing is pushed. It touches `windows/src/` and the shared contract, so it should not run beside another plan that does.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up (it carries the owner's advance approval of the brief in step 3):

   > Run `git switch -c fixes/after-h notchmeow/rebrand`, then Task 0 of `docs/superpowers/plans/2026-10-13-fixes-after-h.md`: only its Steps 1 and 2 (the base checks: `git merge-base --is-ancestor 9b2039e HEAD` must succeed). Read `CLAUDE.md`, `ARCHITECT.md` and that plan. If a base check fails, say so and stop. Reply "ready" and stop. Do not start Task 1. The owner approves in advance the controller brief the main session will send as your next message.

2. **Model.** Once the owner starts the chip, the main session sets that session to Haiku 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-13-fixes-after-h.md` with `superpowers:subagent-driven-development`, task by task, on branch `fixes/after-h`. Dispatch each task to the agent the plan's "Tasks and agents" table names (Haiku 5.5 first; Sonnet 5.5 only for a task Haiku failed twice, and then the trigger goes in the ledger), then to `nm-reviewer`; fix what the review finds before the next task. Rules for you and for every subagent (put the plan's SUBAGENT RULES block in every brief):
>
> - **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder (under `.claude/worktrees/`), the second `fixes/after-h`. If either is wrong, stop and report. Commit with `git commit -F <file>`, never `-m`, with the trailer of the model that did the task. Never push.
> - **Ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-13-fixes-after-h/progress.md`: one line per task with its agent, model, commit hash, test lines and review verdict, and any escalation to `nm-implementer-deep` with the trigger.
> - **Briefs are task-sized.** A brief carries one task: its text, the Global Constraints, the SUBAGENT RULES and the files it names. Never hand a subagent the whole plan.
> - **Reviews** read `git diff notchmeow/rebrand...HEAD` (three dots), narrowed to the task's files, never `..` and never a diff against a moving working tree.
> - **Every shell block in the plan passes `bash -n` before it is run**, and a script you write passes it too.
> - **Rust** runs only as `windows/scripts/cargo-linux.sh test --workspace --offline --target-dir /repo/windows/target/fixes-after-h` (Task 9, Step 3), never with `docker build` or `docker pull`; if the image is missing or Docker is down, say so and skip it.
> - **Servers and processes.** Stop a server only by the PID you saved when you started it. Never launch, quit or replace a NotchMeow app: the builds are builds, and the pictures come from `render-cats.sh --desktop-catch`. Install and download nothing. Never read the real `~/.claude`.
> - **Stop and report on any refusal** (a denied command, a permission prompt): do not look for a workaround.
> - **Ping the main session.** The main session's id is `local_e2775263-3ecb-4292-8b70-58c9090038a2`. At the owner checkpoint (Task 10), at the end, and whenever you stop (a refusal, a failed check, a question), send your report to it with `SendMessage` as well as writing it in your own chat, so the main session can double-check the work (its own clone, merge and full checks) before anything reaches the owner.
> - **Owner checkpoint.** Run Tasks 1 to 9, dispatch `nm-reviewer-deep` over the whole branch, fix what it finds, then stop and report to the main session (Task 10): copy the pictures into `.claude/checkpoints/fixes-after-h/` of the worktree, which is gitignored, and say what to look for.
>
> Report: the commits; the output of `bash scripts/test-cat-contract.sh`, `bash scripts/test-cat-desktop-trip.sh`, `bash scripts/test-cat-desktop-wiring.sh`, `bash scripts/test-cat-press.sh`, `bash scripts/test-render-home-guard.sh`, `bash scripts/test-check-site.sh`, `bash scripts/check-site.sh`, `bash scripts/check-no-leftovers.sh` and `cd windows && npm run check:cat`; the Debug and App Store build lines; `npx tsc --noEmit`; the Rust test line (or why it was skipped); the paths of the pictures; and anything you could not settle.

Before any follow-up turn (a fix round, a question, a resumed run), the main session checks the session is still on its configured model and effort.

## How to run this plan

**Blocks.** A code step is either **Create `path`** (the file's exact content) or **Edit `path`** (a find text that occurs exactly once, and its replacement). Apply an edit by replacing the find text with the replacement and nothing else; if the find text occurs zero or two times, stop and report: the tree is not what the plan expects. Never type a block from memory and never "improve" one. Every `Run:` line is run from the repository root (the worktree's top folder); `Expected: FAIL` and `Expected: PASS` say which way it must go, and the text after it says what to see.

**Mac commands.** The test programs are `swiftc` programs run through `scripts/test-*.sh`; none needs Xcode. A build is `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO` (the App Store target is `-scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store`, with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`). A build only builds: do not open the app. **Windows/Linux commands** run in `windows/` (`npm run check:cat`, `npx tsc --noEmit`); `windows/node_modules` is already there.

**Looking at an image.** The agent that ran the step opens the PNG with its file reader and says in one sentence what it sees against the thing named; a blank or broken image is a failed step. The owner's look is the checkpoint.

**Bite steps.** Some steps break the code on purpose to prove a test fails. Back the file up into a folder you made with `mktemp -d`, change it with the `sed` given, run the test, and copy the backup back; the next step starts from the real file.

---
## Tasks

### Task 0: Worktree and baseline

No code and no commit. Its first two steps are what the chip's prompt runs before the model is set (see "Execution").

- [ ] **Step 1: Put the session's worktree on the plan's branch**

```bash
git status                                    # must be clean
git switch -c fixes/after-h notchmeow/rebrand
git merge-base --is-ancestor 9b2039e HEAD && echo "the base (9b2039e) is in the history"
git log --oneline -3
```

Expected: `the base (9b2039e) is in the history`. If that line is missing, the worktree was cut from an older base: stop and tell the owner. Every later command runs from the root of this worktree. Never push.

- [ ] **Step 2: Check the places this plan edits are as it expects**

```bash
grep -c "French step labels" NotchBuddy/Sources/App/HookServer.swift
grep -c "Lit ·" NotchBuddy/Sources/App/ClaudeChatViews.swift windows/src/core/claude.ts
grep -c "Performance: 0 % CPU when the island is hidden." CLAUDE.md
grep -c "private func isBotHit" NotchBuddy/Sources/App/IslandWindowController.swift
grep -c "return catClickTarget(x, y, this.botCircle(), null) === 1;" windows/src/island/island.ts
grep -c "static func alert(pendingApproval" NotchBuddy/Sources/App/DesktopCatTrip.swift
grep -c "@@DESKTOP-SECTIONS" scripts/gen-cat-fixtures.mjs
```

Expected: `1`, then two lines, one per file, each ending `:1` (`ClaudeChatViews.swift` and `claude.ts`), then `1`, `1`, `1`, `1`, `1`.

- [ ] **Step 3: Baseline: the checks this plan must not move, and a build**

```bash
bash scripts/test-cat-contract.sh 2>&1 | tail -3
bash scripts/test-cat-desktop-trip.sh 2>&1 | tail -1
bash scripts/test-cat-desktop-wiring.sh 2>&1 | tail -1
bash scripts/test-check-site.sh 2>&1 | tail -1
bash scripts/check-site.sh 2>&1 | tail -2
bash scripts/check-no-leftovers.sh 2>&1 | tail -1
(cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)")
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"
```

Expected: `✓ 15 fixture files match cat-core.js` and `✓ two generator runs write identical bytes` (the contract run also prints the 284 passing tests before them); `All tests passed.` twice; `28 passed, 0 failed`; the two `✓` lines of the site check; the leftovers guard's last `✓` line; `ℹ tests 362`, `ℹ pass 362`, `ℹ fail 0`; and `** BUILD SUCCEEDED **` (a few minutes on a cold build).

- [ ] **Step 4: Read the base once**

Read, without changing: `NotchBuddy/Sources/App/DesktopCatController.swift` (`start`, `alerting`, `notchSpot`), `DesktopCatTrip.swift` (`alert`), `FileDropView.swift` (`FileDropHandler.handle`), `UploadCanvasView.swift` (`drawCat`), `windows/src/island/desktop.ts` (`changed`), `windows/src/island/island.ts` (`onDragDrop`, `swallow`, `isBotHit`), `windows/src/upload/canvas.ts` (`drawCat`) and `design/prototype/cat-core.js` from `desktopStep` to `desktopFlightAt`. Nothing to report.

---

### Task 1: French words in comments, and the guard that keeps them out

**Files:**
- Edit: `scripts/check-no-leftovers.sh`, `NotchBuddy/Sources/App/ClaudeChatViews.swift`, `NotchBuddy/Sources/App/HookServer.swift`, `windows/src/core/claude.ts`

- [ ] **Step 1: Look for French in the comments of the whole app (Swift, TypeScript, Rust)**

```bash
git grep -nP '(*UTF)(//|/\*|^\s*\*|#).*[éèêàùçôîûœ]' -- 'NotchBuddy/Sources/*.swift' 'windows/src/*.ts' 'windows/src-tauri/src/*.rs' 'windows/hook/*.rs' | grep -vE 'Bézier|Théodore|Raillé|é are one scalar'
git grep -nF -e 'Lit ·' -e 'French step' -e 'français' -- '*.swift' '*.ts' '*.rs' ':!docs' ':!tests/fixtures'
```

Expected: the first prints two lines, both sample data of tests and not French (`windows/src-tauri/src/agent_hooks.rs` with `Zoé Smith` and `windows/src-tauri/src/ai/attachments.rs` with `éA`); the second prints exactly three lines: `ClaudeChatViews.swift:29`, `HookServer.swift:1115` and `windows/src/core/claude.ts:95`. Those three are this task. (The grep finds French by its accents and by the words the step rows once used; every other comment in the app is English.)

- [ ] **Step 2: Write the guard first and watch it fail**

**Edit `scripts/check-no-leftovers.sh`**

Find:

```bash
exit "$failed"
```

Replace with:

```bash
# The step words are English now ("Reads · README.md"). The comments that quoted the old French ones ("Lit · README.md", "French step labels") stay gone, in the Mac code and in
# windows/src/core/claude.ts, the one file outside NotchBuddy/ that quoted them.
french="$(grep -nF -e 'Lit ·' -e 'French step' -- NotchBuddy/Sources/App/ClaudeChatViews.swift NotchBuddy/Sources/App/HookServer.swift windows/src/core/claude.ts || true)"
if [ -n "$french" ]; then
    echo "✗ no French step word in the comments"
    echo "$french" | head -8 | sed 's/^/    /'
    failed=1
else
    echo "✓ no French step word in the comments"
fi
exit "$failed"
```

Run: `bash scripts/check-no-leftovers.sh; echo "exit $?"`
Expected: FAIL: `✗ no French step word in the comments`, the three lines, `exit 1`.

- [ ] **Step 3: Fix the three comments**

**Edit `NotchBuddy/Sources/App/ClaudeChatViews.swift`**

Find:

```swift
    /// "Lit · README.md", with a mark when it failed or was stopped.
```

Replace with:

```swift
    /// "Reads · README.md", with a mark when it failed or was stopped.
```

**Edit `windows/src/core/claude.ts`**

Find:

```ts
/** "Lit · README.md", with a mark when the step failed or was stopped. */
```

Replace with:

```ts
/** "Reads · README.md", with a mark when the step failed or was stopped. */
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**

Find:

```swift
    // MARK: - French step labels
```

Replace with:

```swift
    // MARK: - Step labels
```

- [ ] **Step 4: Run the guard to see it pass, and the Mac tests that read those files**

Run: `bash scripts/check-no-leftovers.sh 2>&1 | tail -2; bash scripts/test-session-steps.sh 2>&1 | tail -1; bash scripts/test-claude-code.sh 2>&1 | tail -1; (cd windows && npm run check:claude 2>&1 | tail -2)`
Expected: `✓ no French step word in the comments` as the last line of the first, then `All tests passed.` twice and the Claude check's passing line. No code changed, so the builds are Task 9's.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add scripts/check-no-leftovers.sh NotchBuddy/Sources/App/ClaudeChatViews.swift NotchBuddy/Sources/App/HookServer.swift windows/src/core/claude.ts
cat > "${TMPDIR:-/tmp}/fah-msg-1.txt" <<'EOF'
docs(comments): the step rows' comments quote the English words, and a guard keeps the French ones out

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -F "${TMPDIR:-/tmp}/fah-msg-1.txt"
```

---

### Task 2: The `CLAUDE.md` clause

**Files:**
- Edit: `CLAUDE.md`

- [ ] **Step 1: Name the exception to "0 % CPU when the island is hidden"**

**Edit `CLAUDE.md`**

Find:

```
- Performance: 0 % CPU when the island is hidden.
```

Replace with:

```
- Performance: 0 % CPU when the island is hidden. One documented exception, the desktop cat's light checks, only while the cat is out and awake: on Windows and Linux a cursor check at about 10 Hz and a screens/fullscreen check at 2 Hz, on the Mac the mouse-moved monitor. They stop when the cat is home, locked or the display is off, and cost under 1 % of a core when idle (`windows/README.md`, `docs/SPEC.md`).
```

- [ ] **Step 2: Check it reads once and says what the apps do**

Run: `grep -c "One documented exception, the desktop cat's light checks" CLAUDE.md; grep -c "mouse-moved monitor" CLAUDE.md; grep -c "a cursor read about ten times a second" windows/README.md; grep -c "addGlobalMonitorForEvents(matching: \[.mouseMoved" NotchBuddy/Sources/App/DesktopCatController.swift`
Expected: `1`, `1`, `1`, `1` (the clause is the one in `CLAUDE.md`, and both facts it states are in the code and in `windows/README.md`).

- [ ] **Step 3: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add CLAUDE.md
cat > "${TMPDIR:-/tmp}/fah-msg-2.txt" <<'EOF'
docs(claude): the desktop cat's light checks are the documented exception to 0 % CPU when the island is hidden

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -F "${TMPDIR:-/tmp}/fah-msg-2.txt"
```

---

### Task 3: The approval-card render tool and the real home

**Files:**
- Create: `tests/HomeProbe.swift`, `scripts/render-home-guard.sh`, `scripts/test-render-home-guard.sh`
- Edit: `scripts/render-approval-card.sh`

**Interfaces:**
- Produces: `render_home_guard <fake-home> <program> [args...]` and `render_real_home` (sourced from `scripts/render-home-guard.sh`).

- [ ] **Step 1: Write the failing test and its probe**

**Create `tests/HomeProbe.swift`**

```swift
import Foundation

// A probe for scripts/test-render-home-guard.sh: it asks Foundation for the home folder the way the app's own code does (`homeDirectoryForCurrentUser`, which asks the user database
// and ignores $HOME), and says what it found.
//   HomeProbe          prints the home folder
//   HomeProbe read     prints the text of <home>/.claude/settings.json, or "unreadable"
// Compiled alone with swiftc, so it is top-level code and not an @main type.
let home = FileManager.default.homeDirectoryForCurrentUser
if CommandLine.arguments.dropFirst().first == "read" {
    let file = home.appendingPathComponent(".claude/settings.json").path
    print((try? String(contentsOfFile: file, encoding: .utf8)) ?? "unreadable")
} else {
    print(home.path)
}
```

**Create `scripts/test-render-home-guard.sh`**

```bash
#!/usr/bin/env bash
# Proves that the render tools which build the app's own state never read the real home (scripts/render-home-guard.sh): the app's home lookup follows the fake home inside the
# guard, a program that opens the real ~/.claude, ~/.gemini or ~/.codex is killed before it reads a byte, and the render script runs its tool through the guard. Nothing here
# opens a real file: the programs that try are killed first (a guard that failed would show a file's text only to /dev/null).
#   bash scripts/test-render-home-guard.sh
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/render-home-guard.sh
TMP="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-test-home-guard.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
expect() {   # expect NAME WANTED GOT
    if [ "$2" = "$3" ]; then ok "$1"; else failed=$((failed + 1)); echo "FAIL $1 (wanted [$2], got [$3])"; fi
}

FAKE="$(cd "$TMP" && pwd -P)/home"
mkdir -p "$FAKE/.claude"
echo '{"fake":true}' > "$FAKE/.claude/settings.json"
REAL="$(render_real_home)"
swiftc -swift-version 6 -o "$TMP/probe" tests/HomeProbe.swift || { echo "FAIL the probe does not compile"; exit 1; }

expect "the real home is known, and is not the fake one" yes "$([ -n "$REAL" ] && [ "$REAL" != "$FAKE" ] && echo yes || echo no)"
expect "inside the guard the app's home lookup gives the fake home" "$FAKE" "$(cd "$(render_home_guard "$FAKE" "$TMP/probe")" 2>/dev/null && pwd -P)"
expect "and its read of .claude/settings.json is the fake file" '{"fake":true}' "$(render_home_guard "$FAKE" "$TMP/probe" read)"

# A program that opens the real agent configs is killed (SIGKILL, exit 137) before it reads anything.
for f in .claude/settings.json .gemini/settings.json .codex/hooks.json; do
    render_home_guard "$FAKE" /bin/cat "$REAL/$f" > /dev/null 2>&1; code=$?
    expect "a program that opens the real ~/$f is killed" 137 "$code"
done
render_home_guard "$FAKE" /bin/ls "$REAL/.claude" > /dev/null 2>&1; code=$?
expect "and so is one that lists the real ~/.claude" 137 "$code"
render_home_guard "$FAKE" /bin/cat "$FAKE/.claude/settings.json" > /dev/null 2>&1; code=$?
expect "a program that opens the fake home's file is not" 0 "$code"
render_home_guard "$FAKE" /bin/cat /etc/hosts > /dev/null 2>&1; code=$?
expect "nor one that reads anything else" 0 "$code"

# The guard fails closed: with no way to tell the homes apart it runs nothing.
out="$(render_home_guard "$REAL" /bin/echo ran 2>&1)"; code=$?
expect "given the real home as the fake one, it refuses and runs nothing" "1:render-home-guard: cannot tell the real home from the fake one" "$code:$out"

# The render script runs its tool through the guard, and no script that builds the whole app can skip it.
expect "render-approval-card.sh runs the tool through the guard" 1 "$(grep -c 'render_home_guard "\$BUILD_DIR/home" "\$BUILD_DIR/render-approval-card"' scripts/render-approval-card.sh)"
expect "and no longer runs it with only HOME changed" 0 "$(grep -c 'HOME="\$BUILD_DIR/home" "\$BUILD_DIR' scripts/render-approval-card.sh)"
for f in scripts/*.sh; do
    if grep -q "find \"\$APP\" -name '\*.swift'" "$f"; then
        expect "$f builds the whole app, so it runs through the guard" yes "$(grep -q render_home_guard "$f" && echo yes || echo no)"
    fi
done

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
```

Run: `bash -n scripts/test-render-home-guard.sh && bash scripts/test-render-home-guard.sh 2>&1 | sed -n '1p;$p'`
Expected: FAIL: the first line is `scripts/test-render-home-guard.sh: line 8: scripts/render-home-guard.sh: No such file or directory` (the helper does not exist yet) and the last is `0 passed, 13 failed`.

- [ ] **Step 2: Write the guard**

**Create `scripts/render-home-guard.sh`**

```bash
#!/usr/bin/env bash
# Sourced by the render scripts that build the app's own state (scripts/render-approval-card.sh). It runs a program in a home folder of its own and proves the program never
# reads the real one.
#   . scripts/render-home-guard.sh
#   render_home_guard <fake-home> <program> [args...]
# Why: `FileManager.default.homeDirectoryForCurrentUser` asks the user database and ignores $HOME, so the app's code (the "is Claude Code connected" checks read
# ~/.claude/settings.json) would read the real file whatever $HOME says. Two layers:
#   1. CFFIXED_USER_HOME points Foundation at the fake home, so the program reads the empty one;
#   2. a sandbox profile kills the program the moment it opens anything under the real ~/.claude, ~/.gemini or ~/.codex (the agent configs the app knows), for reading or writing,
#      so a new code path that bypasses layer 1 fails the render loudly instead of reading a file of the owner's.
# macOS only (dscl, sandbox-exec). It fails closed: with no way to fence the real home off, it runs nothing.
render_real_home() { dscl . -read "/Users/$(id -un)" NFSHomeDirectory | awk '{print $2}'; }

render_home_guard() {
    local fake="$1"; shift
    local real profile dir
    real="$(render_real_home)"
    if [ -z "$real" ] || [ "$real" = "$fake" ]; then echo "render-home-guard: cannot tell the real home from the fake one" >&2; return 1; fi
    command -v sandbox-exec > /dev/null || { echo "render-home-guard: sandbox-exec is missing, so the real home cannot be fenced off" >&2; return 1; }
    profile="(version 1)(allow default)"
    for dir in .claude .gemini .codex; do
        profile+="(deny file-read* file-write* (with send-signal SIGKILL) (subpath \"$real/$dir\"))"
    done
    HOME="$fake" CFFIXED_USER_HOME="$fake" sandbox-exec -p "$profile" "$@"
}
```

- [ ] **Step 3: Run the tool through the guard**

**Edit `scripts/render-approval-card.sh`**

Find:

```bash
# (it reads UserDefaults, which for this tool is a domain of its own, and ~/.claude/settings.json, which is the empty home folder below) and it saves a few defaults into
```

Replace with:

```bash
# (it reads UserDefaults, which for this tool is a domain of its own, and ~/.claude/settings.json, which is in the empty home folder below: scripts/render-home-guard.sh points
# Foundation at that folder and kills the tool if it ever opens the real ~/.claude, ~/.gemini or ~/.codex) and it saves a few defaults into
```

**Edit `scripts/render-approval-card.sh`**

Find:

```bash
HOME="$BUILD_DIR/home" "$BUILD_DIR/render-approval-card" "$@"
```

Replace with:

```bash
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/render-approval-card" "$@"
```

- [ ] **Step 4: Run the test to see it pass**

Run: `bash -n scripts/render-home-guard.sh && bash -n scripts/render-approval-card.sh && bash scripts/test-render-home-guard.sh 2>&1 | tail -16`
Expected: PASS: every line `ok`, ending `13 passed, 0 failed`.

- [ ] **Step 5: Run the real tool through the guard**

```bash
OUT="$(mktemp -d "${TMPDIR:-/tmp}/fah-card.XXXXXX")"
bash scripts/render-approval-card.sh --scale 2 --out "$OUT/approval-card.png" 2>&1 | tail -2
cmp "$OUT/approval-card.png" docs/assets/img/approval-card.png && echo "the same picture as the site's"
```

Expected: `wrote …/approval-card.png` (about two minutes: the whole app compiles) and `the same picture as the site's`. The tool is not killed, which proves it no longer opens the real `~/.claude/settings.json`, and the picture is byte for byte the site's own. If `cmp` reports a difference, look at the picture and say what it shows (the black approval card with the `npm test` command and Shrimpy beside it); a difference alone is not a failure. (Before this task the same tool run under the same fence is killed: that is how the dry run found the read.)

- [ ] **Step 6: Bite: a guard without its fence**

```bash
BK="$(mktemp -d "${TMPDIR:-/tmp}/fah-bite.XXXXXX")" && cp scripts/render-home-guard.sh "$BK/g.sh"
sed -i '' 's/for dir in .claude .gemini .codex/for dir in .nothing/' scripts/render-home-guard.sh
bash scripts/test-render-home-guard.sh 2>&1 | tail -1
cp "$BK/g.sh" scripts/render-home-guard.sh && bash scripts/test-render-home-guard.sh 2>&1 | tail -1
```

Expected: `9 passed, 4 failed` on the broken guard (a fence around a folder that is not the real one lets the four kill rows' programs through, and they open the real files only to `/dev/null`), then `13 passed, 0 failed` once the file is back.

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git status --short
git add tests/HomeProbe.swift scripts/render-home-guard.sh scripts/test-render-home-guard.sh scripts/render-approval-card.sh
cat > "${TMPDIR:-/tmp}/fah-msg-3.txt" <<'EOF'
fix(render): the approval-card tool runs in a home of its own and is killed if it opens the real agent configs

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -F "${TMPDIR:-/tmp}/fah-msg-3.txt"
```

---

### Task 4: `check-site.sh` hardening

**Files:**
- Edit: `scripts/test-check-site.sh`, `scripts/check-site.sh`

- [ ] **Step 1: Write the failing cases**

**Edit `scripts/test-check-site.sh`**

Find:

```bash
  echo '(function(){var a=1;console.log(a)})()' > "$d/assets/cats.js"
}
```

Replace with:

```bash
  echo '(function(){var a=1;console.log(a)})()' > "$d/assets/cats.js"
  # Two pictures that name outside addresses only as namespaces: an SVG with xmlns, and a PNG with an XMP block (the real site's coats.png and plan-card.png have one).
  mkdir -p "$d/assets/img"
  echo '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 10 10"><defs><circle id="c" r="3"/></defs><use xlink:href="#c"/><rect width="10" height="10"/></svg>' > "$d/assets/img/a.svg"
  printf '\211PNG\r\n\032\n<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"></rdf:RDF></x:xmpmeta>\n' > "$d/assets/img/b.png"
}
```

**Edit `scripts/test-check-site.sh`**

Find:

```bash
rm -rf "$TMP/one"; mkdir -p "$TMP/one"; echo '<html></html>' > "$TMP/one/index.html"
```

Replace with:

```bash
# Media a script loads or plays, a ping, a refresh, and every candidate of a srcset (the second one is the easy one to miss).
mutate "an AudioContext in the bundle"     assets/cats.js 'var a=new AudioContext();' "AudioContext, new Audio or new Image"
mutate "new Audio in a page"               index.html '<script>new Audio("a.mp3").play()</script>' "AudioContext, new Audio or new Image"
mutate "new Image in the bundle"           assets/cats.js 'var i=new Image();i.src="a.png";' "AudioContext, new Audio or new Image"
mutate "a ping on a link"                  index.html '<a href="testers.html" ping="/track">x</a>' "a ping attribute"
mutate "a ping to another host"            index.html '<A HREF="testers.html" PING="https://example.com/t">x</A>' "a ping attribute"
mutate "a meta refresh"                    index.html '<meta http-equiv="refresh" content="0;url=testers.html">' "a meta refresh"
mutate "a meta refresh, in capitals"       index.html '<META HTTP-EQUIV="Refresh" CONTENT="5">' "a meta refresh"
mutate "a second srcset candidate from another host" index.html '<img src="a.png" srcset="a.png 1x, https://cdn.example.com/b.png 2x" alt="x">' "a srcset candidate"
mutate "a second srcset candidate, protocol-relative" index.html '<img src="a.png" srcset="a.png 1x,//cdn.example.com/b.png 2x" alt="x">' "a srcset candidate"
mutate "a second srcset candidate, a data URI" index.html '<img src="a.png" srcset="a.png 1x, data:image/png;base64,AAAA 2x" alt="x">' "a srcset candidate"
mutate "an imagesrcset candidate"          index.html '<link rel="preload" as="image" imagesrcset="a.png 1x, https://cdn.example.com/b.png 2x">' "a srcset candidate"

# The pictures themselves, and their metadata.
mutate "an SVG that loads from another host" assets/img/a.svg '<image href="https://example.com/a.png"/>' "outside address in the picture"
mutate "an SVG with a protocol-relative address" assets/img/a.svg '<image href="//cdn.example.com/a.png"/>' "an SVG with an outside address"
mutate "an SVG with a script"              assets/img/a.svg '<script>1</script>' "runs or embeds"
mutate "an SVG with a foreignObject"       assets/img/a.svg '<foreignObject><p>x</p></foreignObject>' "runs or embeds"
mutate "an SVG with an event handler"      assets/img/a.svg '<rect onclick="x()"/>' "runs or embeds"
mutate "an SVG with an external href"      assets/img/a.svg '<use href="other.svg#a"/>' "an external href"
mutate "a PNG whose metadata names a host" assets/img/b.png 'Comment https://example.com/track' "outside address in the picture"

rm -rf "$TMP/one"; mkdir -p "$TMP/one"; echo '<html></html>' > "$TMP/one/index.html"
```

Run: `bash -n scripts/test-check-site.sh && bash scripts/test-check-site.sh 2>&1 | tail -1`
Expected: FAIL: `28 passed, 18 failed` (the 18 new cases above fail; the old 28 and the clean site still pass).

- [ ] **Step 2: Write the checks**

**Edit `scripts/check-site.sh`**

Find:

```bash
#      a link (<a href>) may go to GitHub or to the credits' author; every picture has alt text; the old character's name is nowhere, and Coucou's only in the credits.
```

Replace with:

```bash
#      a link (<a href>) may go to GitHub or to the credits' author; every picture has alt text; the old character's name is nowhere, and Coucou's only in the credits;
#      no AudioContext, `new Audio(`, `new Image(`, ping, meta refresh or srcset candidate reaches out, and no picture in assets/img, or its metadata, names an outside address.
```

**Edit `scripts/check-site.sh`**

Find:

```bash
pages() {
  local f html=0
```

Replace with:

```bash
# The first candidate of a srcset or imagesrcset attribute in <tag> that points away (http, https, //, data or javascript), printed; none: returns 1. The second candidate is the
# one a check on the attribute's start misses.
srcset_outside() {
  local attr c
  while IFS= read -r attr; do
    attr="${attr#*=}"; attr="${attr#"${attr%%[![:space:]]*}"}"; attr="${attr#[\"\']}"; attr="${attr%[\"\']}"
    while IFS= read -r c; do
      c="${c#"${c%%[![:space:]]*}"}"; c="${c%%[[:space:]]*}"
      case "$(printf '%s' "$c" | tr 'A-Z' 'a-z')" in
        http:*|https:*|//*|data:*|javascript:*) printf '%s\n' "$c"; return 0 ;;
      esac
    done < <(printf '%s\n' "$attr" | tr ',' '\n')
  done < <(grep -oiE '(image)?srcset[[:space:]]*=[[:space:]]*("[^"]*"|'"'"'[^'"'"']*'"'"')' <<< "$1")
  return 1
}

# Pictures: nothing in a picture or in its metadata may point away. A PNG's XMP block and an SVG name W3C and Adobe namespaces in xmlns declarations, which are names and not
# requests, so those are taken out first; any other address fails, and in an SVG so does anything that runs or loads (a script, a foreignObject, an event handler, @import, an
# external href, javascript: or data:).
images() {
  local f t dir="$SITE/assets/img"
  [ -d "$dir" ] || return 0
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    t="$(LC_ALL=C tr -c '[:print:]' ' ' < "$f" | LC_ALL=C sed -E "s/xmlns(:[A-Za-z0-9_.-]+)?[[:space:]]*=[[:space:]]*(\"[^\"]*\"|'[^']*')//g")"
    grep -qiE 'https?://' <<< "$t" && bad "$f: an outside address in the picture or its metadata"
    case "$f" in
      *.svg|*.SVG)
        grep -qE '(^|[^A-Za-z0-9_:])//[A-Za-z0-9-]+\.[A-Za-z]{2,}' <<< "$t" && bad "$f: an SVG with an outside address (//host)"
        grep -qiE '<script|<foreignObject|[[:space:]]on[a-z]+[[:space:]]*=|@import|javascript:|data:' <<< "$t" && bad "$f: an SVG that runs or embeds something (a script, foreignObject, event handler, @import, javascript: or data:)"
        grep -qiE 'href[[:space:]]*=[[:space:]]*["'"'"']?[[:space:]]*[^#"'"'"' >]' <<< "$t" && bad "$f: an SVG with an external href"
        ;;
    esac
  done
  [ "$fail" -eq 0 ] && echo "✓ $dir: no outside address in any picture or its metadata"
}

pages() {
  local f html=0
```

**Edit `scripts/check-site.sh`**

Find:

```bash
    grep -qE 'document\.cookie|localStorage|sessionStorage|indexedDB' <<< "$t" && bad "$f: a cookie or browser storage"
```

Replace with:

```bash
    grep -qE 'document\.cookie|localStorage|sessionStorage|indexedDB' <<< "$t" && bad "$f: a cookie or browser storage"
    grep -qE 'AudioContext|new[[:space:]]+(Audio|Image)[[:space:]]*\(' <<< "$t" && bad "$f: media that a script loads or plays (AudioContext, new Audio or new Image)"
```

**Edit `scripts/check-site.sh`**

Find:

```bash
            *) grep -qiE '=[[:space:]]*["'"'"']?[[:space:]]*(https?:|//|data:|javascript:)' <<< "$tag" && bad "$f: a tag that loads from outside: ${tag:0:90}" ;;
          esac
        done < <(grep -oiE '<[a-z][^>]*>' <<< "$t")
```

Replace with:

```bash
            *) grep -qiE '=[[:space:]]*["'"'"']?[[:space:]]*(https?:|//|data:|javascript:)' <<< "$tag" && bad "$f: a tag that loads from outside: ${tag:0:90}" ;;
          esac
          # On any tag, <a> included: a ping (the browser posts to it), a meta refresh (it redirects the visitor), and every candidate of a srcset.
          grep -qiE '(^|[[:space:]])ping[[:space:]]*=' <<< "$tag" && bad "$f: a ping attribute (the browser would post to it): ${tag:0:90}"
          grep -qiE 'http-equiv[[:space:]]*=[[:space:]]*["'"'"']?[[:space:]]*refresh' <<< "$tag" && bad "$f: a meta refresh (it redirects the visitor): ${tag:0:90}"
          cand="$(srcset_outside "$tag")" && bad "$f: a srcset candidate that loads from outside: $cand"
        done < <(grep -oiE '<[a-z][^>]*>' <<< "$t")
```

**Edit `scripts/check-site.sh`**

Find:

```bash
        local tag href host
```

Replace with:

```bash
        local tag href host cand
```

**Edit `scripts/check-site.sh`**

Find:

```bash
  --pages-only) pages ;;
  "") bundle; pages ;;
```

Replace with:

```bash
  --pages-only) pages; images ;;
  "") bundle; pages; images ;;
```

- [ ] **Step 3: Run the test to see it pass, and the real site**

Run: `bash -n scripts/check-site.sh && bash scripts/test-check-site.sh 2>&1 | tail -1; bash scripts/check-site.sh 2>&1 | tail -3`
Expected: PASS: `46 passed, 0 failed`; then the three `✓` lines of the real site, the last being `✓ docs/assets/img: no outside address in any picture or its metadata` (the real PNGs' XMP blocks pass because they name only namespaces).

- [ ] **Step 4: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add scripts/check-site.sh scripts/test-check-site.sh
cat > "${TMPDIR:-/tmp}/fah-msg-4.txt" <<'EOF'
test(site): check-site catches AudioContext, new Audio and Image, ping, meta refresh, every srcset candidate and the pictures' addresses

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -F "${TMPDIR:-/tmp}/fah-msg-4.txt"
```

---
### Task 5: The file catch's contract (additive)

This is the one task that edits the shared contract. The SUBAGENT RULE that forbids `cat-core.js`, the generator and the fixtures is lifted for exactly these files, and the edits only add.

**Files:**
- Create: `tests/cat/desktop-catch.test.mjs`
- Edit: `design/prototype/cat-core.js`, `scripts/gen-cat-fixtures.mjs`, `docs/CAT-CONTRACT.md`
- Regenerated: `tests/fixtures/cat/desktop-cases.json`

**Interfaces:**
- Produces (Tasks 6 and 7 port these names):
  - `DESKTOP_CATCH_WAIT_MS` (1500)
  - `desktopAlert(input) -> boolean` (`input`: `{approval, question, chatApproval, pillStates, fileCatch}`, a flag true only when exactly `true`)
  - `desktopCatchReady(phase) -> boolean` (the cat is at the notch: `home` and `atNotchForAlert`)
  - fixture keys `catchWaitMs`, `catchNote`, `alertCases` (`{name, input, out}`), `catchReady` (`{phase, out}`), and four trips named "a file catch: …"

- [ ] **Step 1: Write the failing contract test**

**Create `tests/cat/desktop-catch.test.mjs`**

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';

// The file catch (fixes after H): a file on its way into the island is an alert to the desktop cat. No new phase, event or act; one rule for "something wants the cat at the notch",
// one test the catch waits on, and one constant. docs/CAT-CONTRACT.md, "The file catch".
const core = createRequire(import.meta.url)('../../design/prototype/cat-core.js');
const fx = JSON.parse(fs.readFileSync(new URL('../fixtures/cat/desktop-cases.json', import.meta.url), 'utf8'));
const PHASES = core.DESKTOP_PHASES, INFO = core.DESKTOP_PHASE_INFO;

test('the file catch adds no phase, event or act, and a drop waits longer than the surprise and the flight together', () => {
  assert.equal(PHASES.length, 7);
  assert.equal(core.DESKTOP_EVENTS.length, 9);
  assert.equal(core.DESKTOP_ACTS.length, 11);
  assert.equal(core.DESKTOP_CATCH_WAIT_MS, 1500);
  assert.ok(core.DESKTOP_CATCH_WAIT_MS > core.DESKTOP_FLIGHT_MS + 450, 'the surprise is 450 ms and the flight 600');
});

test('desktopAlert: a flag counts only when it is exactly true, and so does a pill in the approval or question state', () => {
  const a = core.desktopAlert;
  for (const k of ['approval', 'question', 'chatApproval', 'fileCatch']) assert.equal(a({ [k]: true }), true, k);
  assert.equal(a({ pillStates: ['working', 'approval'] }), true);
  assert.equal(a({ pillStates: ['question'] }), true);
  assert.equal(a({ pillStates: ['error', 'ratelimit', 'dizzy', 'idle', 'working', 'finished'] }), false);
  for (const v of ['true', 1, null, [true], {}, undefined]) assert.equal(a({ fileCatch: v, approval: v }), false, JSON.stringify(v));
  for (const v of [null, undefined, 'approval', 1, true, [true], () => true]) assert.equal(a(v), false, String(v));
  assert.equal(a({ pillStates: 'approval' }), false);
  assert.equal(a({ pillStates: [{}, null, 7, ['approval']] }), false);
});

test('desktopCatchReady is the notch spot not being empty, so the island and the desktop never both draw the cat', () => {
  for (const p of PHASES) {
    assert.equal(core.desktopCatchReady(p), !INFO[p].notchEmpty, p);
    assert.equal(core.desktopCatchReady(p), !INFO[p].drawn, p + ': ready exactly when the desktop window does not draw it');
  }
  assert.deepEqual(PHASES.filter(p => core.desktopCatchReady(p)), ['home', 'atNotchForAlert']);
  for (const v of [null, undefined, 7, '', 'Home', 'flying', '__proto__', ['home'], {}]) assert.equal(core.desktopCatchReady(v), true, String(v));
});

test('desktop-cases.json: the file catch keys replay, and the four trips tell the story', () => {
  assert.equal(fx.catchWaitMs, core.DESKTOP_CATCH_WAIT_MS);
  assert.equal(typeof fx.catchNote, 'string');
  for (const c of fx.alertCases) assert.equal(core.desktopAlert(c.input), c.out, c.name);
  for (const c of fx.catchReady) assert.equal(core.desktopCatchReady(c.phase), c.out, JSON.stringify(c.phase));
  assert.ok(fx.alertCases.length >= 20 && fx.catchReady.length >= 15);
  const catches = fx.trips.filter(t => t.name.startsWith('a file catch'));
  assert.equal(catches.length, 4);
  assert.deepEqual(catches[0].out.map(r => r.state), ['retracting', 'atNotchForAlert', 'returning', 'onDesktop']);
  assert.deepEqual(catches[0].out.map(r => r.act), ['retract', 'dock', 'flyOut', 'land']);
  assert.deepEqual(catches[1].out.map(r => r.state), ['retracting', 'returning', 'onDesktop']);
  assert.deepEqual(catches[2].out.map(r => r.state), ['flyingOut', 'retracting', 'atNotchForAlert', 'returning', 'onDesktop']);
  assert.deepEqual(catches[3].out.map(r => `${r.state}:${r.act}`), ['home:null', 'home:null', 'home:null'], 'with the cat at home a file catch changes nothing');
});
```

Run: `node --test tests/cat/desktop-catch.test.mjs 2>&1 | grep -E "^# (pass|fail)"`
Expected: FAIL: `# fail 4` (`core.desktopAlert is not a function` and the like).

- [ ] **Step 2: Add the rules to the core**

**Edit `design/prototype/cat-core.js`**

Find:

```js
Object.assign(api,{DESKTOP_PHASES,DESKTOP_PHASE_INFO,DESKTOP_EVENTS,DESKTOP_ACTS,DESKTOP_NEXT,desktopStep,DESKTOP_FLIGHT_MS,DESKTOP_ARC,desktopFlightAt});
```

Replace with:

```js
// The file catch (fixes after H). A file on its way into the island is an alert to the desktop cat: it flies to the notch as it does for an approval (the surprised emote, then the arc), the
// island's catch plays with that one cat, and it flies back to its spot when the drop flow is over. To desktopStep this is alertOn and alertOff, so there is no new phase, event or act and
// every older fixture row stands. What is new is the one rule for "something wants the cat at the notch", the one test a catch waits on, and one constant.
/** How long a dropped file waits for the desktop cat to be at the notch (ms) before the catch plays anyway. The surprise is 450 ms and the flight 600, so a cat that left at the first sign of the drag is usually there already. */
const DESKTOP_CATCH_WAIT_MS=1500;
/**
 * Whether something wants the desktop cat at the notch: an approval, a question, a chat's approval card, a pill whose state is 'approval' or 'question' (`pillStates`, a list of state
 * names), or a file on its way into the island (`fileCatch`: dragged over it, waiting for the cat, or its drop flow on screen). A flag counts only when it is exactly true; input that is not
 * an object is no alert. Pure, never throws.
 */
function desktopAlert(input){const o=isPlain(input)?input:{};
 return o.approval===true||o.question===true||o.chatApproval===true||o.fileCatch===true||(Array.isArray(o.pillStates)&&o.pillStates.some(s=>s==='approval'||s==='question'))}
/**
 * Whether the big cat is at the notch, so the island may draw it and a catch may play with it: the phases whose notch spot is not empty, home and atNotchForAlert (exactly the phases the
 * desktop window does not draw). A value that is not a phase counts as home.
 */
function desktopCatchReady(phase){const p=DESKTOP_PHASES.includes(phase)?phase:'home';return !DESKTOP_PHASE_INFO[p].notchEmpty}
Object.assign(api,{DESKTOP_PHASES,DESKTOP_PHASE_INFO,DESKTOP_EVENTS,DESKTOP_ACTS,DESKTOP_NEXT,desktopStep,DESKTOP_FLIGHT_MS,DESKTOP_ARC,desktopFlightAt,DESKTOP_CATCH_WAIT_MS,desktopAlert,desktopCatchReady});
```

- [ ] **Step 3: Add the fixture rows, and regenerate**

**Edit `scripts/gen-cat-fixtures.mjs`**

Find:

```js
  // @@DESKTOP-SECTIONS: each task adds its keys to `out` immediately above this line.
```

Replace with:

```js
  // The file catch (fixes after H): a file on its way into the island is an alert to the desktop cat (alertOn and alertOff to the machine above, so no new phase, event or act). New keys and
  // new trip rows only, so the fixture stays additive and `note` is not touched; `catchNote` says what they are. alertCases: desktopAlert(input) is out. catchReady: desktopCatchReady(phase) is out.
  out.catchNote = 'The file catch. A file on its way into the island (dragged over it, waiting for the cat, or its drop flow on screen) is an alert to the desktop cat: alertOn and alertOff to desktopStep, so there is no new phase, event or act. alertCases: desktopAlert(input) is out (a flag counts only when it is exactly true). catchReady: desktopCatchReady(phase) is out (the cat is at the notch). catchWaitMs: how long a dropped file waits for the cat, in ms. The trips named "a file catch" are desktopStep over the events the file catch sends.';
  out.catchWaitMs = core.DESKTOP_CATCH_WAIT_MS;
  out.alertCases = [
    ['nothing', {}], ['an approval', { approval: true }], ['a question', { question: true }], ['the chat\'s approval card', { chatApproval: true }], ['a file on its way in', { fileCatch: true }],
    ['a file and an approval', { fileCatch: true, approval: true }], ['a pill in the approval state', { pillStates: ['working', 'approval'] }], ['a pill that asks a question', { pillStates: ['question'] }],
    ['an error, a rate limit and a dizzy cat are not alerts', { pillStates: ['error', 'ratelimit', 'dizzy', 'idle', 'working', 'finished'] }],
    ['every flag false', { approval: false, question: false, chatApproval: false, fileCatch: false, pillStates: [] }],
    ['a flag as text', { fileCatch: 'true', approval: 'true' }], ['a flag as the number 1', { fileCatch: 1, question: 1 }], ['a flag as null', { fileCatch: null }], ['a flag in a list', { fileCatch: [true] }],
    ['pill states that are not a list', { pillStates: 'approval' }], ['pill states with junk in them', { pillStates: [7, null, {}, ['approval'], 'error'] }], ['a state in the wrong case', { pillStates: ['Approval'] }],
    ['keys that are not flags', { file: true, drop: true, catch: true }], ['null', null], ['text', 'approval'], ['a number', 1], ['true', true], ['a list', [true]],
  ].map(([name, input]) => ({ name, input, out: core.desktopAlert(input) }));
  out.catchReady = [...core.DESKTOP_PHASES, null, 7, '', 'Home', 'flying', '__proto__', ['home'], {}].map(phase => ({ phase, out: core.desktopCatchReady(phase) }));
  out.trips.push(
    trip('a file catch: the cat flies in, the catch plays, the cat flies back', 'onDesktop', ['alertOn', 'flightDone', 'alertOff', 'flightDone'].map(evOf)),
    trip('a file catch: the drop view folds before the cat has landed, and the cat turns round mid-flight', 'onDesktop', ['alertOn', 'alertOff', 'flightDone'].map(evOf)),
    trip('a file catch: the file arrives while the cat is still flying out, and the cat turns round', 'home', ['toggle', 'alertOn', 'flightDone', 'alertOff', 'flightDone'].map(evOf)),
    trip('a file catch: with the cat at home it changes nothing', 'home', ['alertOn', 'alertOff', 'alertOn'].map(evOf)),
  );
  // @@DESKTOP-SECTIONS: each task adds its keys to `out` immediately above this line.
```

Run: `node scripts/gen-cat-fixtures.mjs && git diff --stat tests/fixtures/ && node scripts/check-fixtures-additive.mjs 9b2039e`
Expected: `wrote 15 fixture files to tests/fixtures/cat`; the diff is `tests/fixtures/cat/desktop-cases.json` only (additions); and the additive check ends `✓` with `desktop-cases.json gained …` listing `catchNote`, `catchWaitMs`, `alertCases` and `catchReady` as new keys, and no `✗`.

- [ ] **Step 4: The contract doc**

**Edit `docs/CAT-CONTRACT.md`**

Find:

```
- **Replay the fixture:** `steps` and `trips` (`desktopStep`),
```

Replace with:

```
- **Replay the fixture:** `steps` and `trips` (`desktopStep`, the four "a file catch" trips included), `alertCases` (`desktopAlert`), `catchReady` (`desktopCatchReady`), `catchWaitMs`,
```

**Edit `docs/CAT-CONTRACT.md`**

Find:

```
`settingsDefaults`, `settingsCases` (`cleanDesktopSettings`). See "The desktop cat (H-0)".
```

Replace with:

```
`settingsDefaults`, `settingsCases` (`cleanDesktopSettings`), and from the file catch `catchNote`, `catchWaitMs`, `alertCases` (`desktopAlert`) and `catchReady` (`desktopCatchReady`). See "The desktop cat (H-0)" and "The file catch".
```

**Edit `docs/CAT-CONTRACT.md`**

Find:

```
## The harness
```

Replace with:

```
### The file catch (fixes after H)

A file on its way into the island is an alert to the desktop cat. The cat flies to the notch the way it does for an approval (the surprised emote, then the 600 ms arc), the island's catch plays with that one cat, and the cat flies back to its spot when the drop flow is over. To `desktopStep` this is `alertOn` and `alertOff`: **no phase, event or act was added**, every older row of `desktop-cases.json` stands (`node scripts/check-fixtures-additive.mjs <base>` proves it), and an `alertOn` at `home` still does nothing.

What is new is three names and some fixture keys, all additive:

- `desktopAlert({approval, question, chatApproval, pillStates, fileCatch})` is the one rule for "something wants the cat at the notch": true when any flag is exactly `true`, or `pillStates` (a list of state names) holds `'approval'` or `'question'`. A flag that is text, a number, `null` or a list is false, and input that is not an object is no alert. `fileCatch` is the app's own fact: a file is dragged over the island, a drop is waiting for the cat, or the drop flow (the upload, uploading and choose views) is on screen. Fixture: `alertCases`.
- `desktopCatchReady(phase)` says whether the big cat is at the notch, so the island may draw it and a catch may play with it: the phases whose notch spot is not empty, `home` and `atNotchForAlert`, which are exactly the phases the desktop window does not draw. A value that is not a phase counts as `home`. Fixture: `catchReady`.
- `DESKTOP_CATCH_WAIT_MS` (1500) is how long a dropped file waits for `desktopCatchReady` before the catch plays anyway. The flight is 600 ms and the surprise 450 ms, so a cat that left at the first sign of the drag is usually there already. Fixture: `catchWaitMs`.
- Four trips in `trips` are named "a file catch": the whole catch, the drop view folding before the cat has landed (the cat turns round mid-flight), a file that arrives while the cat is still flying out, and a catch with the cat at home (nothing happens).

**What an app does with it.** It feeds `fileCatch` from the drop flow it already has; it draws no cat of its own in the catch while the cat is not `desktopCatchReady` (never two copies of one cat, as everywhere in H); it holds a dropped file for at most `DESKTOP_CATCH_WAIT_MS` until the cat is ready; and the catch's cat sits where the notch spot is for the open drop view, so the dock does not jump. The island keeps the drop view open after a drag that leaves without a drop (the drag session may come back), so the cat stays at the notch until the island folds that view. The prototype page's Desktop panel is unchanged.

## The harness
```

- [ ] **Step 5: Run the contract, and make the new test bite**

Run: `bash scripts/test-cat-contract.sh 2>&1 | tail -3; node --test tests/cat/desktop-catch.test.mjs 2>&1 | grep -E "^# (pass|fail)"`
Expected: PASS: `✓ 15 fixture files match cat-core.js`, `✓ two generator runs write identical bytes`, and `# pass 4`, `# fail 0` for the new file.

Bite: `BK="$(mktemp -d)"; cp design/prototype/cat-core.js "$BK/c.js"; sed -i '' "s/o.fileCatch===true||//" design/prototype/cat-core.js; node --test tests/cat/desktop-catch.test.mjs 2>&1 | grep -E "^# fail"; cp "$BK/c.js" design/prototype/cat-core.js`
Expected: `# fail` is 2 or more (the rule and the fixture replay), and the file is back afterwards (`git diff --stat design/prototype/cat-core.js` shows the Step 2 edit only).

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git status --short
git add design/prototype/cat-core.js scripts/gen-cat-fixtures.mjs tests/fixtures/cat/desktop-cases.json tests/cat/desktop-catch.test.mjs docs/CAT-CONTRACT.md
cat > "${TMPDIR:-/tmp}/fah-msg-5.txt" <<'EOF'
feat(cat): a file on its way into the island is an alert to the desktop cat (additive contract: desktopAlert, desktopCatchReady, the catch wait)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -F "${TMPDIR:-/tmp}/fah-msg-5.txt"
```

---

### Task 6: The file catch on the Mac, and the checkpoint sheet

**Files:**
- Edit: `NotchBuddy/Sources/App/DesktopCatTrip.swift`, `NotchBuddy/Sources/App/DesktopCatController.swift`, `NotchBuddy/Sources/App/FileDropView.swift`, `NotchBuddy/Sources/App/UploadCanvasView.swift`, `tests/DesktopCatTripTests.swift`, `tests/DesktopCatWiringTests.swift`, `scripts/render-cats.swift`, `scripts/render-cats-desktop.swift`

**Interfaces:**
- Consumes: Task 5's fixture keys (`alertCases`, `catchReady`, `catchWaitMs`) and the names `desktopAlert`, `desktopCatchReady`, `DESKTOP_CATCH_WAIT_MS`.
- Produces: `DesktopCatTrip.alert(…, fileCatch:)` (default `false`), `DesktopCatTrip.alert(raw:)`, `DesktopCatTrip.catchReady(_:)` and `(raw:)`, `DesktopCatTrip.catchWaitMs`, `FileDropHandler.waitForCat(state:)`.

- [ ] **Step 1: Write the failing tests**

**Edit `tests/DesktopCatTripTests.swift`**

Find:

```swift
        CT.section("desktopFps: \(rows(fx["fpsCases"]).count) rows")
```

Replace with:

```swift
        CT.section("the file catch: a file on its way into the island is an alert, and the cat must be at the notch before the catch plays")
        CT.checkNear("a dropped file waits at most 1.5 s for the cat", T.catchWaitMs, num(fx["catchWaitMs"]))
        diffs = []
        for c in rows(fx["alertCases"]) where T.alert(raw: c["input"]) != (c["out"] as! Bool) { diffs.append(c["name"] as! String) }
        CT.checkRows("every alert case (\(rows(fx["alertCases"]).count) rows) is as the fixture says: a flag counts only when it is exactly true", diffs)
        diffs = []
        for c in rows(fx["catchReady"]) where T.catchReady(raw: c["phase"]) != (c["out"] as! Bool) { diffs.append("\(c["phase"] ?? "nil")") }
        CT.checkRows("every phase's readiness (\(rows(fx["catchReady"]).count) rows) is as the fixture says", diffs)
        CT.check("the cat is at the notch at home and while it waits there for an answer, nowhere else", DesktopPhase.allCases.filter { T.catchReady($0) }.map(\.rawValue), ["home", "atNotchForAlert"])
        CT.check("the island and the desktop never both draw: ready is exactly not drawn", DesktopPhase.allCases.allSatisfy { T.catchReady($0) == !$0.drawn }, true)
        CT.check("a file on its way in is an alert", T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: false, pillStates: [], fileCatch: true), true)
        CT.check("a caller that does not know of files is as before", T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: false, pillStates: [.idle]), false)
        CT.check("a file and an approval are one alert until both clear", [T.alert(pendingApproval: true, pendingQuestion: false, chatApproval: false, pillStates: [], fileCatch: false), T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: false, pillStates: [], fileCatch: false)], [true, false])

        CT.section("desktopFps: \(rows(fx["fpsCases"]).count) rows")
```

**Edit `tests/DesktopCatWiringTests.swift`**

Find:

```swift
        CT.finish()
```

Replace with:

```swift
        CT.section("the file catch: a file on its way into the island is an alert to the cat, the catch draws no cat of its own while the desktop cat is out, and a drop waits for the cat")
        let drop = source("FileDropView.swift"), canvas = source("UploadCanvasView.swift")
        CT.checkTrue("the controller feeds the drop flow to the alert rule, with the approvals", ctl.contains("pillStates: state.tasks.map { CatState(rawValue: $0.state.rawValue) ?? .idle }, fileCatch: fileCatching)") && ctl.contains("state.fileDragOver || (UploadSequenceEngine.shared.isActive && state.mode == .expanded && [IslandView.upload, .uploading, .choose].contains(state.view))"))
        CT.checkTrue("the catch canvas draws no cat while the notch spot is empty", canvas.contains("if state.desktopPhase.notchEmpty { return nil }"))
        CT.checkTrue("a drop waits for the cat before anything is written or played, and checks its token after the wait", drop.contains("await waitForCat(state: state)\n        guard drops.isCurrent(drop) else { return }"))
        CT.checkTrue("the wait is the contract's: the cat is ready, for at most the catch wait", drop.contains("DesktopCatTrip.catchReady(state.desktopPhase)") && drop.contains("DesktopCatTrip.catchWaitMs"))
        CT.checkTrue("the wait comes before `fileDragOver` is cleared, so the alert holds and the cat does not turn round", (drop.range(of: "await waitForCat(state: state)")?.lowerBound ?? drop.endIndex) < (drop.range(of: "state.fileDragOver = false")?.lowerBound ?? drop.startIndex))
        CT.checkTrue("nothing new polls: no Timer in the drop handler", !drop.contains("Timer.") && !drop.contains("DispatchSource"))
        CT.finish()
```

Run: `bash scripts/test-cat-desktop-trip.sh 2>&1 | tail -4; bash scripts/test-cat-desktop-wiring.sh 2>&1 | tail -3`
Expected: FAIL: the trip test does not compile (`type 'DesktopCatTrip' has no member 'catchWaitMs'`); the wiring test prints `✗` lines for the four pins on the controller, the canvas and the drop handler.

- [ ] **Step 2: The rules, in the Mac port of the contract**

**Edit `NotchBuddy/Sources/App/DesktopCatTrip.swift`**

Find:

```swift
    /// Whether something needs the user: a pending approval or question, a chat's approval card, or any pill in the approval or question state. The cat flies into the notch while
    /// this is true and back out when it is not.
    static func alert(pendingApproval: Bool, pendingQuestion: Bool, chatApproval: Bool, pillStates: [CatState]) -> Bool {
        pendingApproval || pendingQuestion || chatApproval || pillStates.contains { $0 == .approval || $0 == .question }
    }
```

Replace with:

```swift
    /// Whether something needs the user: a pending approval or question, a chat's approval card, any pill in the approval or question state, or a file on its way into the island
    /// (`fileCatch`: dragged over it, waiting for the cat, or its drop flow on screen). The cat flies into the notch while this is true and back out when it is not
    /// (`desktopAlert` in cat-core.js).
    static func alert(pendingApproval: Bool, pendingQuestion: Bool, chatApproval: Bool, pillStates: [CatState], fileCatch: Bool = false) -> Bool {
        pendingApproval || pendingQuestion || chatApproval || fileCatch || pillStates.contains { $0 == .approval || $0 == .question }
    }

    /// The same rule for raw input: a flag counts only when it is exactly `true`, `pillStates` only as a list of the state names `approval` and `question`, and anything that is not an
    /// object is no alert.
    static func alert(raw: Any?) -> Bool {
        guard let o = raw as? [String: Any] else { return false }
        func flag(_ k: String) -> Bool { DesktopCatSettings.isTrue(o[k]) }
        let pill = (o["pillStates"] as? [Any])?.contains { ($0 as? String) == "approval" || ($0 as? String) == "question" } ?? false
        return flag("approval") || flag("question") || flag("chatApproval") || flag("fileCatch") || pill
    }

    // MARK: The file catch

    /// How long a dropped file waits for the cat to be at the notch before the catch plays anyway (ms): `DESKTOP_CATCH_WAIT_MS`.
    static let catchWaitMs = 1500.0

    /// Whether the big cat is at the notch, so the island may draw it and a catch may play with it: the phases whose notch spot is not empty (`desktopCatchReady`).
    static func catchReady(_ phase: DesktopPhase) -> Bool { !phase.notchEmpty }
    /// The same for raw input: a value that is not a phase counts as home.
    static func catchReady(raw: Any?) -> Bool { catchReady((raw as? String).flatMap { DesktopPhase(rawValue: $0) } ?? .home) }
```

- [ ] **Step 3: The controller feeds the drop flow**

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`**

Find:

```swift
        return DesktopCatTrip.alert(pendingApproval: state.pendingApproval != nil, pendingQuestion: state.pendingQuestion != nil, chatApproval: chat,
                                    pillStates: state.tasks.map { CatState(rawValue: $0.state.rawValue) ?? .idle })
    }
```

Replace with:

```swift
        return DesktopCatTrip.alert(pendingApproval: state.pendingApproval != nil, pendingQuestion: state.pendingQuestion != nil, chatApproval: chat,
                                    pillStates: state.tasks.map { CatState(rawValue: $0.state.rawValue) ?? .idle }, fileCatch: fileCatching)
    }

    /// A file is on its way into the island: dragged over it, or its drop flow (the upload, uploading and choose views) is on screen. To the desktop cat that is an alert: it flies to the notch to
    /// catch the file, the island's catch plays with that cat (the canvas draws none of its own while the notch spot is empty), and it flies back when the flow is over. A drop that is waiting
    /// for the cat keeps `fileDragOver` true (`FileDropHandler.handle` clears it once the catch begins), so the alert holds and the cat does not turn round. The island keeps the drop view open
    /// after a drag that leaves without a drop, so the cat stays until the island folds it.
    private var fileCatching: Bool {
        state.fileDragOver || (UploadSequenceEngine.shared.isActive && state.mode == .expanded && [IslandView.upload, .uploading, .choose].contains(state.view))
    }
```

- [ ] **Step 4: A drop waits for the cat, and the catch draws none of its own**

**Edit `NotchBuddy/Sources/App/FileDropView.swift`**

Find:

```swift
    @MainActor
    static func handle(urls: [URL], state: AppState) async {
        guard let url = urls.first else { return }
        let drop = drops.begin()
```

Replace with:

```swift
    /// A file dropped while the desktop cat is out waits until the cat is at the notch (`DesktopCatTrip.catchReady`), at most `DesktopCatTrip.catchWaitMs`; with the cat home it does not wait at
    /// all. A short sleep loop that exists only for the length of a drop: no timer.
    @MainActor
    static func waitForCat(state: AppState) async {
        let start = ProcessInfo.processInfo.systemUptime
        while !DesktopCatTrip.catchReady(state.desktopPhase), (ProcessInfo.processInfo.systemUptime - start) * 1000 < DesktopCatTrip.catchWaitMs {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @MainActor
    static func handle(urls: [URL], state: AppState) async {
        guard let url = urls.first else { return }
        let drop = drops.begin()
        // The desktop cat flies to the notch to catch this file (a file on its way in is an alert to it: `DesktopCatController.fileCatching`). A drop that lands before the cat has waits for
        // it; `fileDragOver` stays true meanwhile (it is cleared below), so the alert holds. A newer drop or a left drop flow ends the wait's turn.
        await waitForCat(state: state)
        guard drops.isCurrent(drop) else { return }
```

**Edit `NotchBuddy/Sources/App/UploadCanvasView.swift`**

Find:

```swift
    private func drawCat(ctx: GraphicsContext, f: USFrame) -> CatGeometry.Layout? {
        let catEngine = driver.engine
```

Replace with:

```swift
    private func drawCat(ctx: GraphicsContext, f: USFrame) -> CatGeometry.Layout? {
        // The big cat is on the desktop (or in the air): it flies in to catch the file, and until it has landed the island draws no cat of its own (never two cats). The file under the pointer
        // still draws. At home `notchEmpty` is false and this is the shipping canvas.
        if state.desktopPhase.notchEmpty { return nil }
        let catEngine = driver.engine
```

- [ ] **Step 5: Run the tests and the builds**

Run: `bash scripts/test-cat-desktop-trip.sh 2>&1 | tail -3; bash scripts/test-cat-desktop-wiring.sh 2>&1 | tail -3; bash scripts/test-cat-upload.sh 2>&1 | tail -1`
Expected: PASS: `All tests passed.` three times (the trip test now has the "file catch" section with 8 `✓`).

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"; xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "BUILD|error:"`
Expected: `** BUILD SUCCEEDED **` twice.

- [ ] **Step 6: The checkpoint sheet: the catch as a strip of frames**

**Edit `scripts/render-cats-desktop.swift`**

Find:

```swift
    /// The desktop cat's cost: update and draw at each size, and what that costs at the frame rate the rule picks for what the cat is doing. Idle and awake (5 fps, no kittens: kittens
```

Replace with:

```swift
    /// The file catch as a strip of frames: the cat on its desktop spot, a file dragged to the notch (the cat is surprised), the arc in at 50 %, the catch at the notch, the arc back at 50 %, and the
    /// cat on its spot again. Each frame is one phase of the trip. The desktop cat is drawn while the phase is `drawn`, the catch's cat at the notch while the cat is `catchReady` (the island draws
    /// none of its own before that), and the sheet counts the cats in every frame and fails if a frame shows other than one.
    @MainActor static func desktopCatchSheet(_ a: Args) -> Sheet {
        let pw = 300.0, ph = 330.0, coat = a.cats.first ?? "shrimpy", d = DesktopSize.medium.d
        let notch = DesktopSpot(x: pw / 2 + 56, y: 56), desk = DesktopSpot(x: pw - 70, y: 230)
        let inbound = DesktopCatTrip.Flight(from: desk, to: notch, dir: .in, startMs: 0), outbound = DesktopCatTrip.Flight(from: notch, to: desk, dir: .out, startMs: 0)
        let half = 0.5 * DesktopCatTrip.flightMs
        let frames: [(phase: DesktopPhase, label: String, head: DesktopSpot?, file: Bool)] = [
            (.onDesktop, "on its spot", desk, false),
            (.retracting, "a file is dragged in: surprised", desk, true),
            (.retracting, "flying to the notch, 50 %", inbound.position(at: half), true),
            (.atNotchForAlert, "the catch, at the notch", nil, true),
            (.returning, "flying back, 50 %", outbound.position(at: half), false),
            (.onDesktop, "back on its spot", desk, false),
        ]
        let sheet = Sheet(width: pw * Double(frames.count), height: ph + 28, scale: a.scale)
        for (i, f) in frames.enumerated() {
            let ox = Double(i) * pw, oy = 28.0
            mockDesktop(sheet.cg, x: ox + 4, y: oy + 4, w: pw - 8, h: ph - 8, notch: true)
            if f.file { sheet.cg.fill(CatDraw.roundRect(ox + notch.x + 26, oy + notch.y + 30, 16, 20, 3), CatDraw.white(0.92)) }
            var cats = 0
            if f.phase.drawn, let p = f.head {
                drawDesktopCat(sheet.cg, coat: coat, state: .working, d: d, head: (ox + p.x, oy + p.y), kittens: 0, side: 1, colour: "#E07950", badge: true, emote: i == 1 ? "surprised" : nil)
                cats += 1
            }
            if DesktopCatTrip.catchReady(f.phase) {
                drawDesktopCat(sheet.cg, coat: coat, state: .idle, d: d * 0.8, head: (ox + notch.x, oy + notch.y), kittens: 0, side: 1, colour: nil, badge: false, emote: "happy")
                cats += 1
            }
            if (f.head != nil) != f.phase.drawn || cats != 1 {
                FileHandle.standardError.write(Data("frame \(i + 1) (\(f.phase.rawValue)) shows \(cats) cat(s)\n".utf8))
                exit(1)
            }
            CatDraw.text(sheet.cg, f.label, x: ox + pw / 2, y: 14, size: 12, bold: true, color: CatDraw.white(0.8))
            CatDraw.text(sheet.cg, "cats on screen: \(cats)", x: ox + pw / 2, y: oy + ph - 14, size: 11, bold: false, color: CatDraw.white(0.9))
        }
        return sheet
    }

    /// The desktop cat's cost: update and draw at each size, and what that costs at the frame rate the rule picks for what the cat is doing. Idle and awake (5 fps, no kittens: kittens
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
        case desktopFlight
        case desktop
```

Replace with:

```swift
        case desktopFlight
        case desktopCatch
        case desktop
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
            case "--desktop-flight": a.mode = .desktopFlight
```

Replace with:

```swift
            case "--desktop-flight": a.mode = .desktopFlight
            case "--desktop-catch": a.mode = .desktopCatch
```

**Edit `scripts/render-cats.swift`**

Find:

```swift
        case .desktopFlight: sheet = flightSheet(a)
```

Replace with:

```swift
        case .desktopFlight: sheet = flightSheet(a)
        case .desktopCatch: sheet = desktopCatchSheet(a)
```

**Edit `scripts/render-cats.swift`**

Find:

```
//   bash scripts/render-cats.sh --desktop [--shapes] --scale 2
```

Replace with:

```
//   bash scripts/render-cats.sh --desktop-catch --scale 2         fixes after H: the file catch as a strip of frames: the cat flies in, the catch plays at the notch, the cat flies back
//   bash scripts/render-cats.sh --desktop [--shapes] --scale 2
```

Run: `OUT="$(mktemp -d "${TMPDIR:-/tmp}/fah-catch.XXXXXX")"; bash scripts/render-cats.sh --desktop-catch --scale 2 --out "$OUT/catch.png" 2>&1 | tail -2; bash scripts/render-cats.sh --desktop-flight --scale 1 --out "$OUT/flight.png" 2>&1 | tail -1`
Expected: `wrote …/catch.png` and `wrote …/flight.png` (the alert flight sheet still draws).

Open `catch.png` and say what you see: six panels, each a mock desktop with the menu bar and a window, the black notch at the top and a **single** cat in each: on its spot (right), surprised with a small file icon at the notch, mid-arc towards the notch, **in the notch with the desktop spot empty** and the file about to be caught, mid-arc back, and on its spot again; every panel is captioned `cats on screen: 1`. A panel with two cats, or none, is a failed step.

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git status --short
git add NotchBuddy/Sources/App/DesktopCatTrip.swift NotchBuddy/Sources/App/DesktopCatController.swift NotchBuddy/Sources/App/FileDropView.swift NotchBuddy/Sources/App/UploadCanvasView.swift tests/DesktopCatTripTests.swift tests/DesktopCatWiringTests.swift scripts/render-cats.swift scripts/render-cats-desktop.swift
cat > "${TMPDIR:-/tmp}/fah-msg-6.txt" <<'EOF'
feat(desktop-cat): the desktop cat flies to the notch to catch a dropped file, the island's catch draws no second cat, and a drop waits for the cat (Mac)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -F "${TMPDIR:-/tmp}/fah-msg-6.txt"
```

---

### Task 7: The file catch on Windows and Linux

**Files:**
- Create: `windows/scripts/cat-tests/desktop-catch.test.mjs`
- Edit: `windows/src/cat/desktop.ts`, `windows/src/core/state.ts`, `windows/src/island/desktop.ts`, `windows/src/island/island.ts`, `windows/src/upload/canvas.ts`, `windows/src/cat/devdesktop.ts`, `windows/scripts/cat-tests/desktop-alert.test.mjs`

**Interfaces:**
- Consumes: Task 5's fixture keys and names.
- Produces: `desktopAlert`, `desktopCatchReady`, `DESKTOP_CATCH_WAIT_MS` (in `cat/desktop.ts`), `State.fileCatch(): boolean`.

- [ ] **Step 1: Write the failing test**

**Create `windows/scripts/cat-tests/desktop-catch.test.mjs`**

```js
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { DESKTOP_CATCH_WAIT_MS, DESKTOP_PHASES, DESKTOP_PHASE_INFO, defaultDesktopSettings, desktopAlert, desktopCatchReady } from "../../src/cat/desktop.ts";
import { DesktopTrip } from "../../src/cat/desktoptrip.ts";
import { State } from "../../src/core/state.ts";
import { load } from "./util.mjs";

// The file catch (fixes after H): a file on its way into the island is an alert to the desktop cat. The rules are the contract's (tests/fixtures/cat/desktop-cases.json), the island feeds
// `fileCatch` from the drop flow, and the catch canvas draws no cat of its own while the desktop cat is out.
const fx = load("desktop-cases.json");
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const LAPTOP = [{ frame: { x: 0, y: 0, w: 1512, h: 982 }, visible: { x: 0, y: 37, w: 1512, h: 875 }, main: true }];
const NOTCH = { x: 756, y: 16 };
function world() {
  const w = { settings: defaultDesktopSettings(), sent: [], empty: [] };
  w.env = { body: (m) => w.sent.push(m), notchSpot: () => NOTCH, screens: () => LAPTOP, settings: () => w.settings, save: (s) => { w.settings = s; }, notchEmpty: (e) => w.empty.push(e) };
  w.trip = new DesktopTrip(w.env);
  return w;
}

test("the wait, desktopAlert and desktopCatchReady are the fixture's", () => {
  assert.equal(DESKTOP_CATCH_WAIT_MS, fx.catchWaitMs);
  for (const c of fx.alertCases) assert.equal(desktopAlert(c.input), c.out, c.name);
  for (const c of fx.catchReady) assert.equal(desktopCatchReady(c.phase), c.out, JSON.stringify(c.phase));
  assert.deepEqual(DESKTOP_PHASES.filter((p) => desktopCatchReady(p)), ["home", "atNotchForAlert"]);
  for (const p of DESKTOP_PHASES) assert.equal(desktopCatchReady(p), !DESKTOP_PHASE_INFO[p].drawn, `${p}: ready exactly when the desktop window does not draw the cat`);
  assert.equal(desktopAlert(Object.freeze({ fileCatch: true })), true, "a frozen input is read, not changed");
});

test("a file catch through the trip: the cat flies in surprised, the notch holds the cat for the catch, an approval keeps it there, and it flies back out when both are clear", () => {
  const w = world();
  w.trip.dragOut({ x: 400, y: 300 });
  assert.equal(w.trip.phase, "onDesktop");
  w.sent.length = 0;
  w.trip.alert(desktopAlert({ fileCatch: true }));
  assert.equal(w.trip.phase, "retracting");
  assert.deepEqual(w.sent.map((m) => [m.k, m.dir, m.emote]), [["fly", "in", "surprised"]]);
  assert.equal(w.empty.at(-1), true, "the notch's spot stays empty while the cat flies");
  w.trip.flightDone();
  assert.equal(w.trip.phase, "atNotchForAlert");
  assert.equal(w.sent.at(-1).k, "hide", "the desktop window gives the cat up: the catch's cat at the notch is the only one");
  assert.equal(w.empty.at(-1), false, "and the notch's spot holds the cat, so the island may draw it");
  assert.equal(desktopCatchReady(w.trip.phase), true);
  const n = w.sent.length;
  assert.equal(w.trip.alert(desktopAlert({ fileCatch: false, approval: true })), null, "the drop flow ends while an approval waits: the alert stays on");
  assert.equal(w.sent.length, n);
  w.trip.alert(desktopAlert({ fileCatch: false, approval: false }));
  assert.equal(w.trip.phase, "returning");
  assert.deepEqual([w.sent.at(-1).k, w.sent.at(-1).dir], ["fly", "out"]);
  w.trip.flightDone();
  assert.equal(w.trip.phase, "onDesktop");
});

test("with the cat at home a file catch changes nothing: no message, no save, no change of the notch's spot", () => {
  const w = world();
  w.trip.alert(desktopAlert({ fileCatch: true }));
  w.trip.alert(desktopAlert({ fileCatch: false }));
  assert.equal(w.trip.phase, "home");
  assert.equal(w.sent.length + w.empty.length, 0);
  assert.equal(w.settings.on, false);
});

test("State.fileCatch is, until the island says otherwise, the drag being over the island", () => {
  State.fileDragOver = false;
  assert.equal(State.fileCatch(), false);
  State.fileDragOver = true;
  assert.equal(State.fileCatch(), true);
  State.fileDragOver = false;
});

test("the island feeds the drop flow to the alert rule, the catch canvas draws no cat while the cat is out, and a drop waits for the cat with a bounded chain of timeouts", () => {
  const b = source("island/desktop.ts");
  assert.match(b, /this\.trip\.alert\(desktopAlert\(\{ approval: State\.attentionNeeded, fileCatch: State\.fileCatch\(\) \}\)\);\s*this\.trip\.notchMoved\(\);/);
  const isl = source("island/island.ts");
  assert.match(isl, /State\.fileCatch = \(\) => State\.fileDragOver \|\| this\.dropWaiting \|\| this\.uploadActive;/, "the drag, a drop that waits for the cat, or the drop flow on screen");
  assert.match(isl, /this\.whenCatIsHere\(\(\) => this\.swallow\(path\)\);/, "the catch starts when the cat is here");
  const wait = isl.slice(isl.indexOf("private whenCatIsHere"), isl.indexOf("private swallow"));
  assert.match(wait, /State\.desktopNotchEmpty && performance\.now\(\) - t0 < DESKTOP_CATCH_WAIT_MS/, "bounded by the contract's wait");
  assert.doesNotMatch(wait, /setInterval|requestAnimationFrame/, "no interval and no frame loop: a chain of timeouts that lasts as long as one drop");
  assert.match(isl, /import \{ DESKTOP_CATCH_WAIT_MS \} from "\.\.\/cat\/desktop";/);
  const canvas = source("upload/canvas.ts");
  assert.match(canvas, /if \(!f\.fileVisible\) this\.cat\.fileArrived\(\);\s*\/\/[^\n]*\n\s*if \(State\.desktopNotchEmpty\) return;/, "the file still arrives; the cat is not drawn while it is on the desktop");
  assert.match(source("cat/devdesktop.ts"), /so does a file dragged onto the notch/);
});
```

Run: `cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (pass|fail)"`
Expected: FAIL: `ℹ fail 1` (the new file does not load: `desktopAlert` is not exported by `cat/desktop.ts`).

- [ ] **Step 2: The rules, in the Windows/Linux port of the contract**

**Edit `windows/src/cat/desktop.ts`**

Find:

```ts
export const defaultDesktopSettings = (): DesktopSettings => cleanDesktopSettings(null);
```

Replace with:

```ts
export const defaultDesktopSettings = (): DesktopSettings => cleanDesktopSettings(null);

// ── The file catch (fixes after H) ─────────────────────────────────────────────

/** How long a dropped file waits for the desktop cat to be at the notch (ms) before the catch plays anyway. */
export const DESKTOP_CATCH_WAIT_MS = 1500;

/**
 * Whether something wants the desktop cat at the notch: an approval, a question, a chat's approval card, a pill whose state is "approval" or "question" (`pillStates`), or a file on its way
 * into the island (`fileCatch`: dragged over it, waiting for the cat, or its drop flow on screen). A flag counts only when it is exactly `true`; input that is not an object is no alert. To the
 * trip it is `alertOn` / `alertOff`: the file catch adds no phase, event or act.
 */
export function desktopAlert(input: unknown): boolean {
  const o: Record<string, unknown> = isPlain(input) ? input : {};
  return o.approval === true || o.question === true || o.chatApproval === true || o.fileCatch === true
    || (Array.isArray(o.pillStates) && o.pillStates.some((s) => s === "approval" || s === "question"));
}

/** Whether the big cat is at the notch, so the island may draw it and a catch may play with it: home and atNotchForAlert, the phases the desktop window does not draw. Not a phase: home. */
export function desktopCatchReady(phase: unknown): boolean {
  const p: DesktopPhase = (DESKTOP_PHASES as readonly unknown[]).includes(phase) ? (phase as DesktopPhase) : "home";
  return !DESKTOP_PHASE_INFO[p].notchEmpty;
}
```

- [ ] **Step 3: The island feeds the drop flow, waits for the cat, and draws none of its own**

**Edit `windows/src/core/state.ts`**

Find:

```ts
  uploadDuration = 2.4;
  fileDragOver = false;
```

Replace with:

```ts
  uploadDuration = 2.4;
  fileDragOver = false;
  /**
   * Whether a file is on its way into the island: dragged over it, a drop waiting for the desktop cat, or its drop flow on screen. To the desktop cat that is an alert (cat/desktop.ts
   * `desktopAlert`): it flies in to catch the file and back when the flow is over. The island replaces this with the full rule; until it does, the drag alone counts.
   */
  fileCatch: () => boolean = () => this.fileDragOver;
```

**Edit `windows/src/island/desktop.ts`**

Find:

```ts
import { DESKTOP_PHASE_INFO, desktopSizeOf, spotOf } from "../cat/desktop";
```

Replace with:

```ts
import { DESKTOP_PHASE_INFO, desktopAlert, desktopSizeOf, spotOf } from "../cat/desktop";
```

**Edit `windows/src/island/desktop.ts`**

Find:

```ts
    this.trip.alert(State.attentionNeeded);
```

Replace with:

```ts
    this.trip.alert(desktopAlert({ approval: State.attentionNeeded, fileCatch: State.fileCatch() }));
```

**Edit `windows/src/island/island.ts`**

Find:

```ts
import { forgetDrop } from "../core/feature";
```

Replace with:

```ts
import { forgetDrop } from "../core/feature";
import { DESKTOP_CATCH_WAIT_MS } from "../cat/desktop";
```

**Edit `windows/src/island/island.ts`**

Find:

```ts
  private uploadCanvas!: UploadCanvas;
```

Replace with:

```ts
  private uploadCanvas!: UploadCanvas;
  /** A file was dropped and the catch is waiting for the desktop cat to reach the notch (`whenCatIsHere`); the file is still "on its way in" to the desktop cat meanwhile. */
  private dropWaiting = false;
```

**Edit `windows/src/island/island.ts`**

Find:

```ts
      cancel: () => this.setView(State.defaultView()),
    });

    this.clipEl = h(
```

Replace with:

```ts
      cancel: () => this.setView(State.defaultView()),
    });
    // A file on its way in is an alert to the desktop cat (cat/desktop.ts `desktopAlert`): the drag over the island, a drop waiting for the cat, or the drop flow on screen.
    State.fileCatch = () => State.fileDragOver || this.dropWaiting || this.uploadActive;

    this.clipEl = h(
```

**Edit `windows/src/island/island.ts`**

Find:

```ts
        this.swallow(path);
```

Replace with:

```ts
        this.whenCatIsHere(() => this.swallow(path));
```

**Edit `windows/src/island/island.ts`**

Find:

```ts
  /**
   * The cat eats the file. Nothing here waits on the file system: the copy into
```

Replace with:

```ts
  /**
   * A file was dropped. If the desktop cat is out it is flying to the notch to catch it (a file on its way in is an alert to it: `State.fileCatch`), and the catch waits for it, at most
   * `DESKTOP_CATCH_WAIT_MS`, so the island never draws a second cat. With the cat home it runs at once. A short chain of timeouts that exists only for the length of one drop: no interval.
   * `dropWaiting` keeps the alert on meanwhile (`State.fileDragOver` is already false), so the cat does not turn round.
   */
  private whenCatIsHere(run: () => void) {
    const t0 = performance.now();
    this.dropWaiting = true;
    const wait = () => {
      if (State.desktopNotchEmpty && performance.now() - t0 < DESKTOP_CATCH_WAIT_MS) {
        window.setTimeout(wait, 50);
        return;
      }
      this.dropWaiting = false;
      run();
    };
    wait();
  }

  /**
   * The cat eats the file. Nothing here waits on the file system: the copy into
```

**Edit `windows/src/upload/canvas.ts`**

Find:

```ts
    if (!f.fileVisible) this.cat.fileArrived();
```

Replace with:

```ts
    if (!f.fileVisible) this.cat.fileArrived();
    // The big cat is on the desktop (or in the air): it flies in to catch the file, and until it has landed the island draws no cat of its own (never two cats). At home this is the shipping canvas.
    if (State.desktopNotchEmpty) return;
```

**Edit `windows/src/cat/devdesktop.ts`**

Find:

```ts
"An approval arrives while the cat is on the desktop: it gives the surprised emote,
```

Replace with:

```ts
"An approval arrives while the cat is on the desktop (so does a file dragged onto the notch: the same alert to the cat, which flies in to catch the file and flies back when the catch is over): it gives the surprised emote,
```

**Edit `windows/scripts/cat-tests/desktop-alert.test.mjs`**

Find:

```js
  assert.match(b, /this\.trip\.alert\(State\.attentionNeeded\);\s*this\.trip\.notchMoved\(\);/);
```

Replace with:

```js
  assert.match(b, /this\.trip\.alert\(desktopAlert\(\{ approval: State\.attentionNeeded, fileCatch: State\.fileCatch\(\) \}\)\);\s*this\.trip\.notchMoved\(\);/);
```

- [ ] **Step 4: Run the checks**

Run: `cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; npx tsc --noEmit; echo "tsc exit $?"`
Expected: PASS: `ℹ tests 367`, `ℹ pass 367`, `ℹ fail 0` (362 and the five of the new file) and `tsc exit 0`.

Bite: `cd windows && BK="$(mktemp -d)" && cp src/upload/canvas.ts "$BK/c.ts" && sed -i '' '/if (State.desktopNotchEmpty) return;/d' src/upload/canvas.ts && npm run check:cat 2>&1 | grep -E "^ℹ fail"; cp "$BK/c.ts" src/upload/canvas.ts; git diff --stat src/upload/canvas.ts`
Expected: `ℹ fail 1` (the canvas pin), and the file is back (the diff stat shows the Step 3 edit only).

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git status --short
git add windows/src/cat/desktop.ts windows/src/core/state.ts windows/src/island/desktop.ts windows/src/island/island.ts windows/src/upload/canvas.ts windows/src/cat/devdesktop.ts windows/scripts/cat-tests/desktop-catch.test.mjs windows/scripts/cat-tests/desktop-alert.test.mjs
cat > "${TMPDIR:-/tmp}/fah-msg-7.txt" <<'EOF'
feat(desktop-cat): the desktop cat flies to the notch to catch a dropped file, the catch draws no second cat, and a drop waits for the cat (Windows and Linux)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -F "${TMPDIR:-/tmp}/fah-msg-7.txt"
```

---
### Task 8: Two cats overlap, only cat 1 leaves (both apps)

**Files:**
- Create: `tests/CatPressTests.swift`, `scripts/test-cat-press.sh`, `windows/scripts/cat-tests/two-cats-overlap.test.mjs`
- Edit: `NotchBuddy/Sources/App/CatIslandLayout.swift`, `NotchBuddy/Sources/App/IslandWindowController.swift`, `windows/src/core/layout.ts`, `windows/src/island/island.ts`

**Interfaces:**
- Produces: `CatIslandLayout.HitCircle`, `CatIslandLayout.bigCatPressed(x:y:cat1:cat2:)` (Mac); `bigCatPressed(x, y, c1, c2)` in `windows/src/core/layout.ts`.

**The bug, on both apps.** Windows/Linux: `isBotHit` is `catClickTarget(x, y, botCircle(), null) === 1`, so with the second circle `null` every press inside cat 1's circle is "on the big cat", including the part cat 2 covers. The Mac: `isBotHit` is cat 1's circle alone and never looks at cat 2. On both, a press there starts the drag out of the notch (the desktop cat's, or the window-attach drag), the slap and the love hover. `pressed()` on Windows already hands that part to cat 2 (`catClickTarget` with both circles); the press-start test did not.

- [ ] **Step 1: Write the failing tests**

**Create `tests/CatPressTests.swift`**

```swift
import Foundation

// Two cats mode: a press in cat 2's part of the overlap with cat 1 drags nothing out of the notch (CatIslandLayout.bigCatPressed), with the island's own numbers, and the island's hit test is
// that rule. Run it through scripts/test-cat-press.sh.
@main
enum CatPressTests {
    typealias H = CatIslandLayout.HitCircle

    @MainActor static func main() {
        CT.section("the expanded overview: cat 1 (Ø58, circle 29) and cat 2 (Ø46, circle 23), 40 pt apart")
        let c1 = H(x: 50, y: 101, r: 29), c2 = H(x: 90, y: 109, r: 23)
        func p(_ x: Double, _ y: Double, second: H? = c2) -> Bool { CatIslandLayout.bigCatPressed(x: x, y: y, cat1: c1, cat2: second) }
        CT.check("a press only cat 1 covers is on the big cat", p(30, 101), true)
        CT.check("a press in the overlap, nearer cat 1's centre, is still the big cat's", p(70, 104), true)
        CT.check("a press in the overlap, nearer cat 2's centre, is cat 2's: it drags nothing", p(72, 105), false)
        CT.check("a press only cat 2 covers is not the big cat", p(105, 109), false)
        CT.check("a press outside both is not", p(200, 101), false)
        CT.check("a tie goes to cat 1", CatIslandLayout.bigCatPressed(x: 70, y: 105, cat1: H(x: 60, y: 105, r: 20), cat2: H(x: 80, y: 105, r: 20)), true)
        CT.check("without a second cat the old rule holds: cat 1's circle alone, edge included", [p(72, 105, second: nil), p(79, 101, second: nil), p(79.5, 101, second: nil)], [true, true, false])

        CT.section("the compact island: two Ø20 heads 24 pt apart, each with the canvas circle of 16.7 pt")
        let k1 = H(x: 30, y: 16, r: 20 / 0.6 / 2), k2 = H(x: 54, y: 16, r: 20 / 0.6 / 2)
        func q(_ x: Double) -> Bool { CatIslandLayout.bigCatPressed(x: x, y: 16, cat1: k1, cat2: k2) }
        CT.check("left of the overlap, cat 1's", q(15), true)
        CT.check("in the overlap, nearer cat 1", q(40), true)
        CT.check("in the overlap, exactly between the two, cat 1's (a tie)", q(42), true)
        CT.check("in the overlap, nearer cat 2: not the big cat", q(44), false)
        CT.check("right of the overlap, cat 2's only", q(65), false)

        CT.section("the island's hit test is that rule, with cat 2's circle when there is a second cat")
        let island = (try? String(contentsOfFile: "NotchBuddy/Sources/App/IslandWindowController.swift", encoding: .utf8)) ?? ""
        CT.checkTrue("it asks the rule", island.contains("CatIslandLayout.bigCatPressed("))
        CT.checkTrue("with cat 2's place when Two cats shows a second cat", island.contains("s.cast.second != nil") && island.contains("secondCatPlace(state: s, islandW: islandW, islandH: islandH)"))
        CT.checkTrue("and no longer with cat 1's circle alone", !island.contains("return dx*dx + dy*dy <= radius * radius"))
        CT.finish()
    }
}
```

**Create `scripts/test-cat-press.sh`**

```bash
#!/usr/bin/env bash
# Two cats mode: a press in cat 2's part of the overlap with cat 1 drags nothing out of the notch (CatIslandLayout.bigCatPressed), and the island's hit test is that rule.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-press.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift \
    $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatKittens.swift $APP/CatIslandLayout.swift \
    tests/CatTestSupport.swift tests/CatPressTests.swift \
    -o "$TEST_DIR/cat-press-tests"
"$TEST_DIR/cat-press-tests"
```

**Create `windows/scripts/cat-tests/two-cats-overlap.test.mjs`**

```js
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { bigCatPressed, catClickTarget } from "../../src/core/layout.ts";

// Two cats mode: a press in cat 2's part of the overlap with cat 1 drags nothing out of the notch. The numbers are the island's expanded overview: cat 1 (Ø58, circle 29) and cat 2 (Ø46,
// circle 23), 40 px apart.
const island = fs.readFileSync(new URL("../../src/island/island.ts", import.meta.url), "utf8");
const c1 = { cx: 50, cy: 101, r: 29 }, c2 = { cx: 90, cy: 109, r: 23 };

test("a press only cat 1 covers is on the big cat, and so is one in the overlap nearer cat 1", () => {
  assert.equal(bigCatPressed(30, 101, c1, c2), true);
  assert.equal(bigCatPressed(70, 104, c1, c2), true);
});

test("a press in the overlap nearer cat 2 is cat 2's: it is not on the big cat, so it drags nothing out of the notch", () => {
  assert.equal(catClickTarget(72, 105, c1, c2), 2);
  assert.equal(bigCatPressed(72, 105, c1, c2), false);
  assert.equal(bigCatPressed(72, 105, c1, null), true, "the old test (no second circle) took it for the big cat");
  assert.equal(bigCatPressed(105, 109, c1, c2), false, "a press only cat 2 covers is not the big cat either");
  assert.equal(bigCatPressed(200, 101, c1, c2), false);
});

test("without a second cat nothing differs from before", () => {
  for (const [x, y] of [[30, 101], [72, 105], [79, 101], [79.5, 101], [200, 101]]) assert.equal(bigCatPressed(x, y, c1, null), catClickTarget(x, y, c1, null) === 1, `${x},${y}`);
});

test("the island's press-start test is that rule, with cat 2's circle when a second cat is shown", () => {
  assert.match(island, /return bigCatPressed\(x, y, this\.botCircle\(\), this\.cast\.second\?\.pill \? this\.bot2Circle\(\) : null\);/);
  assert.doesNotMatch(island, /catClickTarget\(x, y, this\.botCircle\(\), null\)/);
  assert.match(island, /const hit = catClickTarget\(x, y, this\.botCircle\(\), second\?\.pill \? this\.bot2Circle\(\) : null\);/, "a click's own test is as it was");
});
```

Run: `bash scripts/test-cat-press.sh 2>&1 | tail -3; cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (pass|fail)"`
Expected: FAIL: the Mac test does not compile (`HitCircle` is not a member of `CatIslandLayout`); the Windows file does not load (`bigCatPressed` is not exported by `layout.ts`) and the run shows `ℹ fail 1`.

- [ ] **Step 2: The rule, on the Mac**

**Edit `NotchBuddy/Sources/App/CatIslandLayout.swift`**

Find:

```swift
    static func secondBesideBig(_ mode: CatDisplayMode, overview: Bool) -> Bool { mode == .two && overview }
```

Replace with:

```swift
    static func secondBesideBig(_ mode: CatDisplayMode, overview: Bool) -> Bool { mode == .two && overview }

    /// A circle a press can land in, in any one coordinate space (both circles of a test must use the same one).
    struct HitCircle: Equatable, Sendable { var x: Double, y: Double, r: Double }

    /// Whether a press at (x, y) is on the big cat. Where cat 1's circle and cat 2's overlap (Two cats mode: `cat2` is given) the cat whose centre is nearer wins and a tie goes to cat 1, the
    /// same rule as Windows' `catClickTarget`; a press that is cat 2's is not on the big cat and drags nothing out of the notch. Without a second cat it is cat 1's circle alone, as it was.
    static func bigCatPressed(x: Double, y: Double, cat1: HitCircle, cat2: HitCircle?) -> Bool {
        func d(_ c: HitCircle) -> Double { (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y) }
        guard d(cat1) <= cat1.r * cat1.r else { return false }
        guard let c2 = cat2, d(c2) <= c2.r * c2.r else { return true }
        return d(c2) >= d(cat1)
    }
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**

Find:

```swift
        let dx = windowPoint.x - botX
        let dy = windowPoint.y - botY
        return dx*dx + dy*dy <= radius * radius
    }
```

Replace with:

```swift
        // Two cats mode: where cat 2's circle overlaps cat 1's, the nearer centre wins, and a press that is cat 2's is not on the big cat (it drags nothing out of the notch, slaps nothing).
        // Cat 2's circle is its tap shape in the overview (Ø46) and, like cat 1's, the canvas-sized circle in the compact island.
        var second: CatIslandLayout.HitCircle?
        if s.cast.second != nil, let place = secondCatPlace(state: s, islandW: islandW, islandH: islandH) {
            second = .init(x: Double(islandMinX + place.cx), y: Double(panelH - place.cy), r: Double(place.compact ? place.d / 0.6 / 2 : place.d / 2))
        }
        return CatIslandLayout.bigCatPressed(x: Double(windowPoint.x), y: Double(windowPoint.y), cat1: .init(x: Double(botX), y: Double(botY), r: Double(radius)), cat2: second)
    }
```

- [ ] **Step 3: The rule, on Windows and Linux**

**Edit `windows/src/core/layout.ts`**

Find:

```ts
  return in1 && in2 ? (d(c2) < d(c1) ? 2 : 1) : in2 ? 2 : in1 ? 1 : 0;
}
```

Replace with:

```ts
  return in1 && in2 ? (d(c2) < d(c1) ? 2 : 1) : in2 ? 2 : in1 ? 1 : 0;
}

/** Whether a press is on the big cat: the cat the press hits is cat 1. In Two cats mode (`c2` given) a press in cat 2's part of the overlap is cat 2's, so it drags nothing out of the notch. */
export function bigCatPressed(x: number, y: number, c1: Circle, c2: Circle | null): boolean {
  return catClickTarget(x, y, c1, c2) === 1;
}
```

**Edit `windows/src/island/island.ts`**

Find:

```ts
  catClickTarget, islandSize,
```

Replace with:

```ts
  bigCatPressed, catClickTarget, islandSize,
```

**Edit `windows/src/island/island.ts`**

Find:

```ts
  private isBotHit(x: number, y: number): boolean {
    return catClickTarget(x, y, this.botCircle(), null) === 1;
  }
```

Replace with:

```ts
  /** A press on the big cat (a drag out of the notch, the love hover). In Two cats mode a press in cat 2's part of the overlap is cat 2's: it is not on the big cat. */
  private isBotHit(x: number, y: number): boolean {
    return bigCatPressed(x, y, this.botCircle(), this.cast.second?.pill ? this.bot2Circle() : null);
  }
```

- [ ] **Step 4: Run the checks**

Run: `bash scripts/test-cat-press.sh 2>&1 | tail -2; (cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; npx tsc --noEmit; echo "tsc exit $?"); xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"`
Expected: PASS: `All tests passed.`; `ℹ tests 371`, `ℹ pass 371`, `ℹ fail 0` (367 and the four of the new file) and `tsc exit 0`; `** BUILD SUCCEEDED **`.

Bite (Windows): `cd windows && BK="$(mktemp -d)" && cp src/island/island.ts "$BK/i.ts" && sed -i '' 's/return bigCatPressed(x, y, this.botCircle(), this.cast.second?.pill ? this.bot2Circle() : null);/return bigCatPressed(x, y, this.botCircle(), null);/' src/island/island.ts && npm run check:cat 2>&1 | grep -E "^ℹ fail"; cp "$BK/i.ts" src/island/island.ts`
Expected: `ℹ fail 1`, and the file is back afterwards.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git status --short
git add NotchBuddy/Sources/App/CatIslandLayout.swift NotchBuddy/Sources/App/IslandWindowController.swift tests/CatPressTests.swift scripts/test-cat-press.sh windows/src/core/layout.ts windows/src/island/island.ts windows/scripts/cat-tests/two-cats-overlap.test.mjs
cat > "${TMPDIR:-/tmp}/fah-msg-8.txt" <<'EOF'
fix(cat): in Two cats mode a press in cat 2's part of the overlap drags nothing out of the notch (Mac and Windows/Linux)

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -F "${TMPDIR:-/tmp}/fah-msg-8.txt"
```

---

### Task 9: CI, the French spec sentence, the map bullet, the last checks and the pictures

**Files:**
- Edit: `.github/workflows/build.yml`, `docs/SPEC.md`, `CLAUDE.md`

- [ ] **Step 1: The CI steps, the spec sentence and the map bullet**

**Edit `.github/workflows/build.yml`**

Find:

```yaml
      - name: Desktop cat wiring (source pins of the app files)
        run: bash scripts/test-cat-desktop-wiring.sh
```

Replace with:

```yaml
      - name: Desktop cat wiring (source pins of the app files)
        run: bash scripts/test-cat-desktop-wiring.sh

      - name: "Cat press (Two cats: a press in cat 2's part of the overlap drags nothing)"
        run: bash scripts/test-cat-press.sh

      - name: Render home guard (the approval-card tool never opens the real agent configs)
        run: bash scripts/test-render-home-guard.sh
```

**Edit `docs/SPEC.md`**

Find:

```
Une alerte réglée en plein vol le fait faire demi-tour sans saut.
```

Replace with:

```
Une alerte réglée en plein vol le fait faire demi-tour sans saut. **Un fichier** glissé vers l'île compte aussi comme une alerte pour le chat : il fait l'émote Surpris, vole jusqu'à sa place du notch et c'est lui qui attrape le fichier (l'île ne dessine alors aucun chat à elle : jamais deux chats ; un fichier déposé avant l'arrivée du chat l'attend 1,5 s au plus), puis il retourne à sa place quand la vue d'envoi est repliée ou le choix fait (le contrat : `docs/CAT-CONTRACT.md`, « The file catch »).
```

**Edit `CLAUDE.md`**

Find:

```
`bash scripts/check-site.sh` fails on a stale bundle or any outside request, and the Windows tests workflow runs it.
```

Replace with:

```
`bash scripts/check-site.sh` fails on a stale bundle or any outside request, and the Windows tests workflow runs it.
- Fixes after H (`docs/superpowers/plans/2026-10-13-fixes-after-h.md`): `scripts/render-home-guard.sh` runs a render tool in a home folder of its own and kills it if it opens the real `~/.claude`, `~/.gemini` or `~/.codex` (`scripts/test-render-home-guard.sh`; `render-approval-card.sh`, the one tool that builds the whole app, goes through it). A file on its way into the island is an alert to the desktop cat (`desktopAlert`, `desktopCatchReady` and `DESKTOP_CATCH_WAIT_MS` in `cat-core.js`, replayed from `desktop-cases.json`; `DesktopCatTrip.alert(fileCatch:)` on the Mac, `State.fileCatch` on Windows/Linux): the cat flies in to catch the file, the island's catch draws no cat of its own while the desktop cat is out, and a drop waits for the cat for at most 1.5 s; `bash scripts/render-cats.sh --desktop-catch` draws it. `CatIslandLayout.bigCatPressed` (Mac) and `bigCatPressed` in `windows/src/core/layout.ts` are the one press-start test of the big cat, so a press in cat 2's part of the overlap in Two cats mode drags nothing out of the notch (`scripts/test-cat-press.sh`).
```

- [ ] **Step 2: Every check this plan touches, and the builds**

```bash
bash scripts/test-cat-contract.sh 2>&1 | tail -2
bash scripts/test-cat-desktop-trip.sh 2>&1 | tail -1
bash scripts/test-cat-desktop-wiring.sh 2>&1 | tail -1
bash scripts/test-cat-press.sh 2>&1 | tail -1
bash scripts/test-cat-wiring.sh 2>&1 | tail -1
bash scripts/test-render-home-guard.sh 2>&1 | tail -1
bash scripts/test-check-site.sh 2>&1 | tail -1
bash scripts/check-site.sh 2>&1 | tail -3
bash scripts/check-no-leftovers.sh 2>&1 | tail -1
node scripts/check-fixtures-additive.mjs 9b2039e 2>&1 | tail -2
(cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1; npx tsc --noEmit; echo "tsc exit $?")
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "BUILD|error:"
git diff --stat notchmeow/rebrand...HEAD -- NotchBuddy/NotchBuddy.xcodeproj | tail -1
```

Expected: the contract's two `✓` lines; `All tests passed.` five times (trip, wiring, press, cat wiring) and the guard's `13 passed, 0 failed`; `46 passed, 0 failed`; the site's three `✓` lines; the leftovers guard's last `✓` (`no French step word in the comments`); the additive check's `✓` with no `✗`; `ℹ tests 371`, `ℹ pass 371`, `ℹ fail 0`; the AI and Claude checks' passing lines; `tsc exit 0`; `** BUILD SUCCEEDED **` twice; and nothing from the last line (the Xcode project did not change).

- [ ] **Step 3: Rust as a regression run (nothing under `windows/src-tauri/` changed)**

Run: `windows/scripts/cargo-linux.sh test --workspace --offline --target-dir /repo/windows/target/fixes-after-h 2>&1 | grep -E "^test result|error"`
Expected: every `test result: ok.` (the last dry run of H had 265 and 24 tests passing) and no `error`. This uses the existing `notchmeow-linux-dev` image and never builds or pulls one; if Docker is down, or the image or the crates are missing (offline), say so and skip, and do not look for another way.

- [ ] **Step 4: The checkpoint pictures**

```bash
OUT=.claude/checkpoints/fixes-after-h; mkdir -p "$OUT"
bash scripts/render-cats.sh --desktop-catch --scale 2 --out "$OUT/mac-file-catch.png" 2>&1 | tail -1
bash scripts/render-cats.sh --desktop-flight --scale 1 --out "$OUT/mac-alert-flight.png" 2>&1 | tail -1
bash scripts/render-approval-card.sh --scale 2 --out "$OUT/approval-card-from-the-guarded-tool.png" 2>&1 | tail -1
ls -la "$OUT"
```

Expected: three `wrote …` lines and three PNGs. Open `mac-file-catch.png` and say what you see (six panels, one cat in each, captioned `cats on screen: 1`: on its spot, surprised, mid-arc to the notch, in the notch with the desktop spot empty, mid-arc back, on its spot again). Open `approval-card-from-the-guarded-tool.png`: the approval card with `npm test` and Shrimpy. `.claude/checkpoints/` is gitignored.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git status --short
git add .github/workflows/build.yml docs/SPEC.md CLAUDE.md
cat > "${TMPDIR:-/tmp}/fah-msg-9.txt" <<'EOF'
docs(ci): CI runs the press and render-guard tests; the spec and the map name the file catch and the guard

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git commit -F "${TMPDIR:-/tmp}/fah-msg-9.txt"
```

The version and the changelog line are the release's, not this plan's (Open question 8). Then the session dispatches `nm-reviewer-deep` over `git diff notchmeow/rebrand...HEAD`, fixes what it finds, and stops for Task 10.

---

### Task 10: Owner checkpoint: the pictures, then the real-build checks

No code and no commit. The session reports (and pings the main session with `SendMessage`); the main session sends the owner the pictures and the list.

**The pictures** (`.claude/checkpoints/fixes-after-h/`):

- **`mac-file-catch.png`** is the one checkpoint for item 5, and it is a render, not the app: it draws the trip's own phases with the app's own layout, flight and drawing code, six moments, and refuses to be made if any moment shows other than one cat. Is this what you meant: the desktop cat gets surprised, flies to the notch, **is** the cat of the catch there (the desktop spot empty), and flies back to its spot, never two? Windows and Linux have no sheet of their own because they run the same contract rows (`desktop-cases.json`, the four "a file catch" trips) through the same flight (`desktopFlightAt`, whose strip is in `npx vite` then `http://127.0.0.1:1420/?dev` under "The alert flight"); a render cannot show the island's own canvas drawing no cat, which is the owner's real-build check 1 below.
- `mac-alert-flight.png` is the alert flight as it already was, for comparison; `approval-card-from-the-guarded-tool.png` is the approval card drawn by the tool that now cannot open the real `~/.claude`.

**The owner's real-build checks** (a Debug build or the 0.9.1 candidate on a Mac, a Windows PC and a Linux machine; the plan could not run any app):

1. **The catch, Mac.** Put the cat on the desktop (⌃⌥D). Drag a file from Finder to the notch: the cat is surprised and flies into the notch as it does for an approval, the island opens on the drop view, and the cat in it catches the file. **Count the cats in every moment: one.** Choose "Ask Claude" (or Cancel): the cat flies back to the spot it left. Try, each time counting cats: a drop made quickly, before the cat has landed (it waits at most 1.5 s and the catch plays); a refused file (a `.dmg`: the cat coughs it up as a hairball, and flies back after the note); dragging in and then away without dropping (the island keeps the drop view, so the cat stays until it folds); an approval pending while a file is caught (the cat stays until both are clear); the cat mid-flight out when the file arrives (it turns round without a jump); Two cats mode and A cat for each agent (the cat that leaves is the Main cat, the focused agent's cat, or cat 1).
2. **The catch with the cat home.** Everything as in 0.9.0: the island's catch cat, no wait, no flight.
3. **The catch, Windows.** The same walk. Also the tray's "Send home" and a drop on the notch while a catch is on.
4. **The catch, Linux.** KDE Plasma (layer shell) the same walk; on GNOME the native drag sends no move, so say whether the cat flies in at all there (it may not: report what you see).
5. **Two cats mode, both apps, compact and expanded.** Press and drag from cat 2's side of the overlap: nothing leaves the notch (and nothing slaps). Press cat 1's far side: it still drags out; a click on cat 2 in the open overview still brings its agent into focus.
6. **Idle cost.** With the cat out and the island hidden, Activity Monitor or Task Manager stays under 1 % of a core, and 0 % with the cat home; a file catch adds nothing afterwards.
7. **The render tool.** On any Mac: `bash scripts/render-approval-card.sh --out /tmp/card.png` still draws the card (about two minutes), and a second run with `sandbox-exec` missing (rename it in a throwaway shell's `PATH`) refuses with `render-home-guard: sandbox-exec is missing`.
8. **The site check on the Windows runner.** The first "Site checks" run on the next push passes with the new image scan (the LF rule in `.gitattributes` keeps the PNGs' bytes).
9. **`CLAUDE.md`.** Read the new Performance clause once: it says what you meant.

---

## Parity with Windows/Linux

Item 5 and item 6 are on both apps from one contract and one pure rule each (Task 5's fixture rows, Task 8's `bigCatPressed` tests), so neither app gets less than the other. Items 1 to 4 are repository-wide. The Mac has one extra that Windows/Linux cannot have: the checkpoint sheet is a Mac render (`render-cats.sh`), and the Windows `?dev` page only gets a sentence in its existing alert-flight section (Task 7), because the catch's one new fact, the island's canvas drawing no cat, is not something either contact sheet draws. The render guard is macOS-only because the tool it fences is.

## Open questions for the owner

Each has the answer this plan assumes, so nothing blocks. A different answer changes one small thing, named in each.

1. **`frenchStep` keeps its name.** It is a private function (code, not a comment) with one caller; the scope said comments only. **Assumed: keep.** To rename it to `stepLine`, change the two places in `HookServer.swift`.
2. **The catch starts at the first drag-over, not at the drop, and ends when the drop view is folded or answered.** So the cat is at the notch by the time most drops land, and it stays through the "choose" card (the cat of the catch is the cat you are talking to), flying back once you answer. **Assumed: yes.** To fly back at the check mark instead, `fileCatch` would end when the upload finishes: Mac `fileCatching` and Windows `State.fileCatch` drop the `.choose` view, one line each.
3. **The same surprised emote as an approval.** A file is not an approval, but the owner asked for "as an alert flight does". **Assumed: yes.** A different emote needs a new act (it is the contract's `retract`), so it would be a follow-up with a fixture row.
4. **A drop that lands before the cat has waits at most 1.5 s**, then the catch plays with no cat drawn rather than blocking (a stuck flight). **Assumed: fine.** A longer or shorter wait is `DESKTOP_CATCH_WAIT_MS` and `catchWaitMs`.
5. **A drag that leaves without a drop keeps the cat at the notch until the island folds the drop view**, because the island deliberately keeps that view open while the drag session may come back (`UploadSequenceEngine.exitZone`, Windows `leave`). **Assumed: OK**, as it is how the island already behaves.
6. **The render guard is a `sandbox-exec` fence plus `CFFIXED_USER_HOME`, not an app-side `NM_` home override.** The app has `NM_LOG_DIR` and Debug-only `NM_CLAUDE_CODE_PATH_OVERRIDE`/`NM_AI_BASE_URL_OVERRIDE` but no home override, and one would touch about a dozen sites including the hook installer's writers. `sandbox-exec` is deprecated but present on every supported macOS, and the guard fails closed where it is missing. **Assumed: yes.**
7. **Cat 2's press circle on the Mac** is the same canvas-sized circle as cat 1's in the compact island (16.7 pt) and the tap shape (Ø46) in the overview. **Assumed: yes.** It changes only the width of the overlap, one expression in `IslandWindowController.isBotHit`.
8. **The version and the changelog line are the release's.** This plan does not bump 0.9.0 and does not edit `CHANGELOG.md`. For 0.9.1's changelog: "A file dropped on the notch while the cat is on your desktop is caught by that cat: it flies in, plays the catch and flies back (before, a second cat appeared). In Two cats mode a press on the second cat no longer carries the first one out of the notch. Under the hood: French comments, a stricter site check, and the approval-card render tool can no longer read your real Claude Code settings." **Assumed: yes.**
9. **A new bullet in `CLAUDE.md`** (the map of the app's files) and the French sentence in `docs/SPEC.md`, as earlier plans did. **Assumed: yes.**

## Self-review

- **Scope coverage.** Item 1: Task 1 (the three comments and the guard); item 2: Task 3; item 3: Task 4 (every named hole, one failing case each, plus the real site passing); item 4: Task 2; item 5: Tasks 5 (contract), 6 (Mac), 7 (Windows/Linux) and the picture; item 6: Task 8 (both apps, a test each).
- **Mac answer for item 5.** Stated under "The file catch": the Mac has the same two-cat bug as Windows/Linux, and both ports get the same fix.
- **Contract.** Additive only: no phase, event or act; three new names; new keys and four trips; `check-fixtures-additive.mjs` in Tasks 5 and 9.
- **Models.** Every task is Haiku 5.5; the one Sonnet is the whole-branch review (trigger 4). The session is Haiku 5.5 high and not trigger 5, with the reason given under "Execution".
- **Placeholders.** None: every code step is a **Create** or **Edit** block from files the dry run ran, and every `Run:` line has its expected output.
- **Type consistency.** `desktopAlert`/`desktopCatchReady`/`DESKTOP_CATCH_WAIT_MS` (Task 5) are what Task 7 imports and what Task 6 ports as `alert(raw:)`/`catchReady`/`catchWaitMs`; `State.fileCatch` (Task 7) is what `island/desktop.ts` and `island.ts` use; `bigCatPressed` (Task 8) has the same name and rule in both apps.
- **What this plan deliberately does not do:** add a phase, event or act; poll; edit the hook installer or the app's home lookups; touch `windows/src-tauri/`; rename `frenchStep`; draw a Windows contact sheet; bump the version.

## Dry run (2026-10-13)

The plan was run before it was handed over, in a throwaway `git clone --local --shared --branch notchmeow/rebrand` at `9b2039e` (the scratchpad's `fah-dry`, with `windows/node_modules` copied by `cp -cR`), by a small runner that read this file: it applied each **Create** block (8) and each **Edit** block (51) in the plan's order, failing when a find text occurred other than once, and ran `bash -n` on all 17 bash blocks (0 problems). The commands below were run by hand. Nothing was committed or pushed, no NotchMeow app was started, nothing was installed or downloaded, no image was built or pulled, and the only file this work added to the main checkout is this plan.

| Task | What the run printed (the plan's Expected) |
|---|---|
| 0 | baseline: contract 284 tests and `✓ 15 fixture files`, `28 passed, 0 failed`, check:cat 362 |
| 1 | the accent grep prints the two Rust sample lines; the guard is red then green |
| 3 | red (a pristine clone with the new test): `0 passed, 13 failed`; green `13 passed, 0 failed`; the bite `9 passed, 4 failed`; the real tool through the guard wrote the card, **byte-identical to `docs/assets/img/approval-card.png`**. Before the fix the same tool, built from `9b2039e` and run under the same fence, is killed (exit 137): it does read `~/.claude/settings.json` |
| 4 | red `28 passed, 18 failed`; green `46 passed, 0 failed`; the real `docs` passes all three `✓`, XMP-carrying PNGs included |
| 5 | red `# fail 4`; green 288 contract tests; `check-fixtures-additive.mjs`: `desktop-cases.json: 529 old lines unchanged, 48 lines added (new keys: catchNote, catchWaitMs, alertCases, catchReady)` |
| 6 | red: compile error; green: the trip test's 8 new `✓` and `All tests passed.` for trip, wiring, upload; Debug and App Store builds `** BUILD SUCCEEDED **`; `--desktop-catch` drawn and looked at (six panels, one cat each, captions `cats on screen: 1`) and `--desktop-flight` still draws |
| 7 | red `ℹ fail 1`; green `ℹ tests 367` (371 after Task 8), `tsc exit 0`, `check:ai` and `check:claude` pass |
| 8 | red: Mac compile error, Windows `ℹ fail 1`; green `All tests passed.` (15 `✓`) and `ℹ pass 371` |
| 9 | the eight Mac checks, `46 passed`, the three site `✓`, additive `✓`, the Xcode project file unchanged; Rust through `cargo-linux.sh test --workspace --offline --target-dir /repo/windows/target/fixes-after-h`: `265 passed` and `24 passed`, no error |

**What the dry run changed in the plan** (each was a defect in an earlier draft):

- **The tool really reads the real `~/.claude/settings.json`.** The first draft assumed the tool needed only a fake `$HOME`; the fence test showed `HOME` is ignored and `CFFIXED_USER_HOME` is what Foundation honours, so the guard has both layers.
- **`srcset_outside` missed the last candidate** (`printf '%s'` without a newline made `read` skip the final line); it prints `'%s\n'` now.
- **A single-file `swiftc` probe cannot be `@main`;** `HomeProbe.swift` is top-level code. The guard test compares physical paths (`/var` against `/private/var`).
- **`catchSheet` already existed** in `render-cats.swift` (the cat's own file-catch states); the new one is `desktopCatchSheet`.
- **The Windows red state is one failing file, not one per test** (`ℹ fail 1`), and `exitZone` on the Mac keeps the engine active, so the cat stays until the island folds the drop view (Open question 5).

**Not run, and owed.**

- **Any commit step.** Every `git add` and `git commit` block was skipped and has to be run by the executing session in its worktree.
- **The apps themselves.** No NotchMeow window was opened, so the real catch (the flight into the open drop view, the canvas drawing no cat while `notchEmpty`, the drop wait on a real Finder drag, WebView2/WebKitGTK drag events, GNOME) is Task 10's list for the owner. The catch was proved by the contract rows, source pins, the Windows trip test and the Mac render, not by the app.
- **Release build and signing.** Only the Debug and App Store builds ran (unsigned); a Release build adds nothing conditional on this code.
- **CI.** The Windows runner's run of the new `check-site.sh` image scan (Git Bash `tr`/`sed`) and the macOS runner's `sandbox-exec` guard test are CI's first runs.

The throwaway clones (`fah-dry`, `fah-red`) and `fah-probe` were left in the scratchpad.

## The owner's answers (2026-10-13)

- **Approved as assumed:** every open question takes its assumed answer, the `CLAUDE.md` clause and map bullet included. Runs now, for 0.9.1.
- **Base:** `notchmeow/rebrand` at `80f4d46` or later (the wing fix merged after the dry run). If a find text no longer matches because of it, stop and report.
