# U1: Upstream fixes and island quality of life: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The owner's choices of 2026-10-15 in one branch for 0.9.3: (A) six upstream Coucou fixes ported by hand to the Mac and to Windows/Linux, (B) two island quality-of-life features (a click outside the open island folds it; a soft rainbow glow along the island's outline while the pointer is over it), (C) a hunt for what keeps the Mac at about 55 % CPU while the island shows a permission card, (D) two pill decisions: the Claude Code pill is labelled "Claude Code" instead of "VS Code", and Claude Code sessions from the Claude desktop app get their own pill, and (E) the compact island's wings: hovering either wing swooshes the whole island into the notch.

**Architecture:** Every item is small and almost all of them are pure rules with a test (`ApprovalClickGuard`, `IslandOutsideClick`, `IslandGlow`, `AskQuestion`'s height, `StopTimers`, `ClickGuard`, the FSM's hover rules) plus a few source pins for the call sites (`scripts/test-u1-wiring.sh`). The two B features follow the repo's 0 % rule by construction: the outside-click monitor exists only while the island is expanded (installed and removed from the one `state.$mode` sink), and the glow is not in the view tree (Mac) or its animation is paused and its pseudo-element hidden (Windows/Linux) unless the pointer is over the island. Open on hover reuses the island's own poll, so it needs no timer or monitor of its own and the compact wing (`IslandWing`) still takes the pointer away from the grid. The performance item is an investigation with a measurement tool that never launches the app.

**Tech Stack:** Swift 6, SwiftUI, AppKit, `swiftc` test programs, Bash, XcodeGen, Python 3 (the relay test), Node 22 (`--experimental-strip-types`), TypeScript, CSS (`conic-gradient`, `@property`), Rust (hook relay and Tauri settings; run through `windows/scripts/cargo-linux.sh`, or the local offline probe described under "How to run this plan").

**Spec:** the owner's approved scope of 2026-10-15, restated under "The items" below (there is no spec file). Upstream is read through `.claude/archive/coucou-update-2026-10-15.md` (the survey) and, for the six fixes, through `git show <sha>` on the upstream refs only. The Mac wing rule is `docs/SPEC.md` "L'aile droite s'efface" and `NotchBuddy/Sources/App/IslandWing.swift`; the escape and hold rules are `EscapeRouting.swift` and `IslandStateMachine.isHeldOpen`.

**Base:** a new branch `u1/upstream-fixes-and-qol` in a git worktree, from `notchmeow/rebrand` at `e8c28e9` or later (`git merge-base --is-ancestor e8c28e9 HEAD` must succeed). If a find text below no longer occurs exactly once because the base moved, stop and report; do not guess.

## The items (the owner's scope, 2026-10-15)

**A. Upstream fixes (ported by hand: never `git merge`, `cherry-pick` or `checkout` an upstream ref; never open upstream's wardrobe, outfit or Mochi code or assets; never write a reserved name)**

1. **Antigravity answers `ask` on PreToolUse** (upstream 66be53e, #317). Antigravity reads `{}` on PreToolUse as a denial, so NotchMeow's relay blocked every Antigravity tool. Both Mac relays (GitHub and App Store, embedded in `HookServer.swift`) and the Windows/Linux relay (`windows/hook/src/agents.rs`, `main.rs`) now print `{"decision":"ask"}` for `--agent antigravity` on PreToolUse. `ask` hands the choice back to Antigravity's own prompt (and the user's Always Allow): NotchMeow never allows a tool by itself. Gemini and every other event keep `{}`; Claude Code stays silent.
2. **The crash an hour after a file edit** (upstream d05f22b). `AppState.resetSessionDiffTimer` scheduled a MainActor-isolated closure on a global queue; Swift 6's isolation check trapped when it fired and the app quit. It now fires on the main queue.
3. **Question cards show each option's description** (upstream 52b1562, #249). *An existing view changes: the owner approved.* NotchMeow's design: **only a question that has at least one option description changes**: its whole question text shows, its options become a vertical list (label, description under it), and the island grows to fit (160 pt up to 560 pt; the transparent panel goes from 320 to 560 pt so it is not clipped). A question with no description is exactly as it ships (chips, two-line question, 160 pt). Mac only: the Windows/Linux question card is still a placeholder ("Answer in your terminal").
4. **A 600 ms click guard on a fresh permission card** (upstream 5b06e1c, Windows only upstream; the Mac has the same exposure). A click meant for the window underneath must not land on Allow, Always or Deny. Clicks on the card's buttons are ignored for the first 600 ms of each request; the keys Y and N are not clicks and are not guarded.
5. **Windows/Linux fixes**: the stale "Stop" return-to-idle timer is cancelled when the next turn starts (upstream 3491a2b; the Mac already does it); the webview zoom is synced to the window's scale so the island is not clipped (b9b9217, #467; Windows only in effect); the pill labels keep left padding so the pill's cat does not overlap the text (2fb18a5, #522).
6. **Open on hover** (upstream 0ad1b1d and 2261334), off by default: hovering the island opens it **after a 150 ms dwell** (the pointer must stay over the island 150 ms; leaving earlier cancels it; the usual hover peek is not delayed), it folds 0.6 s after the pointer leaves, a click inside makes it an ordinary open island, a waiting card or alert keeps its usual rules. **It respects `IslandWing` and costs nothing when hidden**: it adds no monitor and no poll, and one one-shot timer per hover (armed when the pointer enters, cancelled when it leaves; none while not hovering) (the existing poll feeds the state machine; the wing's `passThrough` still takes the pointer away from the grid before the state machine hears of it; the hover-close and the dwell are the same kind of one-shot `DispatchWorkItem` the state machine already uses). Found in the dry run: NotchMeow's `Close after` setting never reached the state machine (`homeToPetitDelay` stayed 15 s), so Task 7 wires it too (owner's answer 8).

**B. Island quality of life (the owner's own requests, approved)**

7. **A click outside the open island folds it at once**, except when the island is pinned (⌘P), a permission request or question waits, the user is typing in the chat, or the shelf holds it (`fsm.isHeldOpen` and `EscapeRouting` rules). The one global mouse monitor exists only while the island is expanded. Mac only in U1; the Windows/Linux version is a follow-up plan (owner's answer 4).
8. **Hover glow**: a soft rainbow halo (blue, purple, pink, orange, blurred, slowly turning angular gradient, about 3 pt) along the island's outline, fading in over 0.2 s on hover and out on leave, on the compact notch and on the open island. Drawn only while hovered. Reduce Motion: a still glow. A "Hover glow" switch in Settings (on by default; `island.hoverGlow`; the nearest existing place is General → Behavior, no new box). The colours are `shared/theme.json` (`glow` group, `gen-theme.mjs`). Windows/Linux: the same, in CSS, with the same switch.

**D. Pills (two more decisions of 2026-10-15)**

11. **The Claude Code pill is labelled "Claude Code"**, not "VS Code" (Mac: `PillCatalog.swift`; Windows/Linux: `core/state.ts` and the views). The ID `integration_claude` is frozen. The "Handled in VS Code / Terminal / iTerm…" notes still name the host app (`HookOrigin`). Every test, pin and doc that showed the old label is updated, and a pin asserts the new one (Task 12).
12. **A pill for Claude Code sessions from the Claude desktop app** (upstream 344dc12, #191), ported by hand: such a session sets `CLAUDE_CODE_ENTRYPOINT=claude-desktop`, the relay tags it, and it reaches the frozen pill **`agent_claude-desktop`** (visible name "Claude App"; colour `#E3A857`, NotchMeow's own). Mac first, with Open Claude on the pill and the finished card; Windows/Linux get the relay tag and the pill's name and colour, and "Open Claude" there is a follow-up (Task 13).

**E. The wings (one more decision of 2026-10-15)**

13. **Both wings step aside** (replacing today's right-wing-only fade): with the pointer over either wing of the compact island (the parts left and right of the camera notch; the notch itself is the hover-open zone with the 150 ms dwell; the right wing, the grid, folds it at once, the left wing, the big cat, only after the pointer has rested there 0.4 s with no mouse button pressed) the whole island swooshes into the notch: its frame shrinks to the notch's width on a spring (about 0.22 s, slight overshoot), the big cat, the grid and the badges (the shelf's too) fade as it shrinks, and the panel passes clicks to the menu-bar items under both wings. The hover zones stay at the full-width positions; 1 s after the pointer leaves both wings it swooshes back out; an alert cancels it at once. Mac first, fed by the existing `pollFrame` (Task 14). Windows/Linux: a follow-up plan, with the outside click.

**C. Performance.** QA of 0.9.2 measured about 55 % CPU on the Mac while the island shows a permission card (the sidekick's risk card) and about 0.3 % hidden. Task 8 finds what redraws every frame on the open card and fixes it without changing the look, with a measurement before and after.

## Global Constraints

Every task's requirements include this section.

- **Swift 6, SwiftUI and AppKit, TypeScript, CSS; no third-party dependencies.** Shell scripts are Bash 3.2 compatible (macOS).
- **0 % CPU when the island is hidden.** No new `Timer`, `DispatchSourceTimer`, display link or poll. The only new monitor is the outside-click one, and only while the island is expanded. The glow draws only while hovered. The click guard is one `Task.sleep` per permission request. Open on hover adds nothing but one one-shot dwell timer per hover (none while not hovering): it is fed by the existing poll.
- **Never restyle a shipping view.** The visible changes are exactly: the question card with option descriptions (approved); the glow (new, switchable); the pill label padding on Windows/Linux (a bug fix). A question without descriptions, the permission card and every other view look as they did (the click guard changes no pixel).
- **The wing rule stands, and Task 14 widens it.** With the pointer over either wing of the compact island (the parts beside the notch) the island must not open, with Open on hover on or off; the notch itself is the hover zone; the left wing (the big cat) folds the island only after a 0.4 s rest with no button pressed, so a click, the drag-out and the Wardrobe right-click on the big cat work as today. `IslandWing`, `scripts/test-island-wing.sh` and `scripts/test-island-wing-wiring.sh` are rewritten by Task 14 and stay green; the hover zones are always the full island's.
- **Never block Claude Code or any agent; never allow without a click.** The relay answers `ask`, never `allow`, for Antigravity; every Rust test that says nothing is allowed without a decision stays.
- **Frozen values.** Pill IDs, cat IDs, display mode IDs, shortcut action IDs, bundle identifiers, every existing UserDefaults key and contract string are untouched. The two new keys are `openOnHover` (the name upstream uses; Windows/Linux `openOnHover`) and `island.hoverGlow`.
- **Colours live in `shared/theme.json`.** The glow's four colours are the new `glow` group; `node scripts/gen-theme.mjs` writes the three generated files and `bash scripts/test-theme.sh` must be green. Never edit a generated file by hand.
- **Never edit `NotchBuddy.xcodeproj` by hand.** A task that adds a Swift file to the app runs `cd NotchBuddy && xcodegen` before it builds and commits the regenerated `project.pbxproj`. A new Swift file that a test or render script compiles is added to that script's list.
- **No `UserDefaults` suite and no write to `UserDefaults.standard` or `~/Library` in a test or script.** Tests run through `scripts/test-*.sh`, which set `NM_LOG_DIR` to a temp folder where they build AppState.
- **Rust** runs through `windows/scripts/cargo-linux.sh` (offline, `--target-dir /repo/windows/target/u1`, never builds or pulls an image) when Docker is up; when it is down, mark the step "needs Docker" and run the local offline probe of "How to run this plan" for the pure functions.
- **Models and commits** (CLAUDE.md, "Working with AI agents"): Haiku 5.5 first, Sonnet 5.5 only on a named trigger (the tasks table names each), never Opus or Fable. Each commit is local only, never pushed, lists only the files its task names, and ends with the `Co-Authored-By` line of the model that did the task: `Claude Haiku 5.5` for `nm-implementer-light` and `nm-implementer`, `Claude Sonnet 5.5` for `nm-implementer-deep`.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app: the installed app is running and owns `nm.sock`. A Debug, Release or App Store **build** in the worktree is fine and is only built. The scripts that draw a PNG or measure (`render-glow.sh`, `render-question-card.sh`, `render-approval-card.sh`, `measure-island-cpu.sh`) are not the app and may run; `measure-island-cpu.sh` shows a nearly invisible window at the top of the main screen for its few seconds. No task sends a hook event to the app's socket.
  2. Install nothing. No network calls, no downloads, no `docker build` or `docker pull`.
  3. Use `trash`, never `rm -rf`, for anything you delete by hand; put scratch files under `${TMPDIR:-/tmp}` in a folder with a unique name. (The scripts clean their own `mktemp` folders in a `trap`: that is the repo's convention.)
  4. No `UserDefaults` suite and no write to `UserDefaults.standard` or `~/Library` in a test or script.
  5. Never edit `design/prototype/cat-core.js`, a fixture of `tests/fixtures/`, or a generated theme file. `shared/theme.json` and `scripts/gen-theme.mjs` and `tests/theme/` only in Task 10, which names them.
  6. Never push. Commit only in a task's commit step, after checking the worktree and the branch.
  7. Haiku 5.5 for every task except where the table names Sonnet 5.5 and its trigger; never Opus or Fable.
  8. Never rename a frozen ID; write no `Coucou` or `Mochi` name anywhere (`scripts/check-no-leftovers.sh` must stay green); never open upstream's wardrobe, outfit or Mochi code.
  9. Never read, print or write the real `~/.claude/settings.json` (or anything in the real `~/.claude`, `~/.gemini`, `~/.codex`), by hand or in a script.
  10. If a command is denied by a permission prompt, stop and report it. Do not look for a workaround.

## Review Focus

The items say what changes. They are silent on these conditions, and each would bite a person first, most likely first. Each names the test that pins it.

1. **A click outside that is really the start of a drag** (a file taken out of a Finder window toward the island, a window moved, a text selection) must not fold the island; a click while typing in the chat, with a card waiting, pinned, or with the shelf's hold must not either. Tests: Task 9 (`IslandOutsideClickTests`: the 4 pt click slop, every reason to stay, pairs of reasons; the wiring pins).
2. **A question with no option description, a question whose descriptions are very long, and several questions of different heights.** Expected: the first is byte-for-byte the card it was (160 pt); the second is capped at 560 pt; the island does not change height from one question to the next. Tests: Task 6 (`AskQuestionTests`, the two pictures).
3. **A second permission request arriving while the first card is up, and the keyboard.** Expected: the guard starts again for the new request; Y and N (Windows) and the card's other keys are not guarded. Tests: Tasks 3 and 5 (`ClickGuard` rows, the token wiring).
4. **Open on hover with the pointer over either wing (they step aside, Task 14), with a card waiting, and just after the island opened.** Expected: over the wing nothing opens; a waiting card is never folded by hover; the island that opened by hover does not start folding while the pointer is still on it. Tests: Task 7 (the twenty-two Mac state-machine checks, 149 ms against 150 ms, leaving at 100 ms, the nine Windows ones, the pins on `!wing.passThrough` and `previouslyInIsland`).
5. **The glow with the switch off, under Reduce Motion, with the island hidden, and while the cat's head is dragged.** Expected: nothing in the tree; a still glow; nothing; nothing. Tests: Task 10 (`IslandGlowTests`, the source pins), Task 11 (the CSS pins).
6. **Antigravity's other spellings and events.** Expected: `BeforeTool` (its other name for PreToolUse) is answered `ask` too; `PostToolUse`, `PreInvocation`, `PostInvocation` and `Stop` keep `{}`; Gemini keeps `{}` on PreToolUse. Tests: Task 1 (`scripts/test-hook-relay.sh` runs both Mac relays for real; the Rust tests).
7. **A Claude Desktop session next to an explicit `--agent`, an entrypoint that only looks like it, and a permission request from it.** Expected: the explicit tag wins; `Claude-Desktop` or `cli` stay plain Claude Code; a PermissionRequest is answered like any external agent's (`ask`, so Claude Desktop shows its own prompt). Tests: Task 13 (`scripts/test-hook-relay.sh` listens on the socket and reads what both relays send; `HookOriginTests`; the Rust and Windows tests).

---

## File Structure

| Path | Responsibility |
|---|---|
| `scripts/test-hook-relay.sh` (new), `NotchBuddy/Sources/App/HookServer.swift`, `windows/hook/src/agents.rs`, `windows/hook/src/main.rs` | Item 1 (Task 1). |
| `NotchBuddy/Sources/App/AppState.swift`, `scripts/test-u1-wiring.sh` (new) | Item 2 (Task 2); the wiring pins grow with every Mac task. |
| `windows/src/island/stoptimers.ts` (new), `windows/src/views/clickguard.ts` (new), `windows/src/island/hooks.ts`, `windows/src/views/views.ts`, `windows/src/style.css`, `windows/scripts/cat-tests/u1-guards.test.mjs` (new) | Items 4 (Windows) and 5 (Stop timer, pill padding) (Task 3). |
| `windows/src-tauri/src/island.rs`, `windows/src-tauri/src/lib.rs`, `windows/src/core/bridge.ts`, `windows/src/main.ts`, `windows/src/island/island.ts` | Item 5 (zoom) (Task 4). |
| `NotchBuddy/Sources/App/ApprovalClickGuard.swift` (new), `IslandTypes.swift`, `IslandViewContent.swift`, `tests/ApprovalClickGuardTests.swift` (new), `scripts/test-approval-click-guard.sh` (new) | Item 4 (Mac) (Task 5). |
| `NotchBuddy/Sources/App/AskQuestion.swift`, `AppState.swift`, `IslandViewContent.swift`, `IslandWindowController.swift`, `tests/AskQuestionTests.swift`, `scripts/render-question-card.swift` and `.sh` (new) | Item 3 (Task 6). |
| `NotchBuddy/Sources/App/IslandStateMachine.swift`, `IslandWindowController.swift`, `AppState.swift`, `SettingsView.swift`, `tests/IslandHoverTests.swift` (new), `scripts/test-island-hover.sh` (new), `windows/src/island/fsm.ts`, `island.ts`, `windows/src/core/state.ts`, `windows/src/settings/main.ts`, `windows/src-tauri/src/settings.rs`, `windows/scripts/cat-tests/fsm-hover.test.mjs` (new) | Item 6 (Task 7). |
| `scripts/measure-island-cpu.swift` and `.sh` (new), the files the hunt names | Item C (Task 8). |
| `NotchBuddy/Sources/App/IslandOutsideClick.swift` (new), `IslandWindowController.swift`, `tests/IslandOutsideClickTests.swift` (new), `scripts/test-island-outside-click.sh` (new) | Item 7 (Task 9). |
| `shared/theme.json`, `scripts/gen-theme.mjs`, `tests/theme/gen-theme.test.mjs`, the three generated theme files, `NotchBuddy/Sources/App/IslandGlow.swift` and `IslandGlowView.swift` (new), `IslandRootView.swift`, `IslandWindowController.swift`, `AppState.swift`, `SettingsView.swift`, `tests/IslandGlowTests.swift` (new), `scripts/test-island-glow.sh` (new), `scripts/render-glow.swift` and `.sh` (new) | Item 8, Mac (Task 10). |
| `windows/src/style.css`, `windows/src/island/island.ts`, `windows/src/core/state.ts`, `windows/src/settings/main.ts`, `windows/src-tauri/src/settings.rs`, `windows/scripts/cat-tests/hover-glow.test.mjs` (new) | Item 8, Windows/Linux (Task 11). |
| `PillCatalog.swift`, `IslandViewContent.swift`, `windows/src/core/*.ts`, the docs that show the label, `windows/scripts/cat-tests/pill-labels.test.mjs` (new) | Item 11 (Task 12). |
| `HookOrigin.swift`, `PillCatalog.swift`, `AgentTarget.swift`, `HookServer.swift`, `tests/HookOriginTests.swift`, `scripts/test-hook-relay.sh`, `scripts/render-pills.swift` and `.sh` (new), `windows/hook/src/agents.rs`, `main.rs`, `windows/src/core/pills.ts`, `windows/scripts/cat-tests/pills.test.mjs` | Item 12 (Task 13). |
| `IslandWing.swift`, `IslandWindowController.swift`, `IslandRootView.swift`, `tests/IslandWingTests.swift`, `tests/IslandWingWiringTests.swift`, `tests/ShelfWiringTests.swift`, `scripts/render-cats-wing.swift`, `scripts/render-cats.swift`, `docs/SPEC.md`, `CLAUDE.md` | Item 13 (Task 14). |
| `.github/workflows/build.yml`, `.github/workflows/windows-tests.yml` (no change: `check:cat` runs the new test files), `CLAUDE.md`, `docs/SPEC.md` | CI steps, the map bullet, two French sentences (Task 15). |

## Tasks and agents

CLAUDE.md: the lightest model that fits. **Haiku 5.5 first; Sonnet 5.5 only on a named trigger.** Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion` (the deep agent also `superpowers:systematic-debugging`); reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). Effort: **medium** for light tasks (code given in full), **high** for `nm-implementer`, the deep agent and every review.

| # | Task | Agent, model, effort | Trigger | Review |
|---|---|---|---|---|
| 0 | Worktree and baseline | the session | | none |
| 1 | Antigravity answers `ask` (Mac relays, Windows/Linux relay) | `nm-implementer-light`, Haiku 5.5, medium | | `nm-reviewer` |
| 2 | The one-hour diff timer on the main queue, and the wiring script | `nm-implementer-light`, Haiku 5.5, medium | | `nm-reviewer` |
| 3 | Windows/Linux: click guard, stale Stop timer, pill padding | `nm-implementer-light`, Haiku 5.5, medium | | `nm-reviewer` |
| 4 | Windows: webview zoom synced to the window | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 5 | Mac: the permission card's click guard | `nm-implementer-light`, Haiku 5.5, medium | | `nm-reviewer` |
| 6 | Mac: question cards show option descriptions, and the picture | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 7 | Open on hover (Mac and Windows/Linux), and Close after | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 8 | **The permission card's CPU: find what redraws every frame** | `nm-implementer-deep`, **Sonnet 5.5**, high | 2 (cause unknown) | `nm-reviewer` |
| 9 | A click outside the open island folds it (Mac) | `nm-implementer-deep`, **Sonnet 5.5**, high | 1 (AppKit event monitor and panel) | `nm-reviewer` |
| 10 | Hover glow, Mac: theme colours, rules, view, switch, picture | `nm-implementer-deep`, **Sonnet 5.5**, high | 1 (hover plumbing into the AppKit panel and SwiftUI layers) | `nm-reviewer` |
| 11 | Hover glow, Windows/Linux | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 12 | The Claude Code pill is labelled "Claude Code" (both apps), with pins, tests and docs | `nm-implementer-light`, Haiku 5.5, medium | | `nm-reviewer` |
| 13 | Claude Desktop pill: the relay tag, the frozen ID `agent_claude-desktop`, Open Claude, the Windows/Linux tag and picture | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 14 | Both wings step aside: the compact island swooshes into the notch (rules, tests, pins, view, pictures, docs) | `nm-implementer-deep`, **Sonnet 5.5**, high | 1 (a spring-driven frame fed by the AppKit panel's poll, click-through at the full zones) | `nm-reviewer` |
| 15 | CI, the map bullet, French spec sentences, the last checks and pictures | `nm-implementer-light`, Haiku 5.5, medium | | `nm-reviewer` |
| After 15 | The whole branch: cross-task contracts, the 0 % rule, the wing, privacy | `nm-reviewer-deep`, **Sonnet 5.5**, high | 4 | none |
| 16 | **Owner checkpoint:** the pictures, then the real-build checks | the main session and the owner | | none |

Why not Haiku for 8, 9 and 10: Task 8's cause is unknown (trigger 2); Tasks 9 and 10 put an event monitor and a layer into the AppKit island panel and must reason about key-window state, isolation and the SwiftUI tree (trigger 1). Their code is given in full and was run in the dry run, so a Haiku attempt is a reasonable first try only for Task 9; the table says Sonnet because the owner's brief asked for it. If a Haiku task fails twice, hand it to `nm-implementer-deep` (trigger 2) and say so in the ledger.

## Execution

One worktree chat session runs the whole plan: branch `u1/upstream-fixes-and-qol`. The session's model is **Sonnet 5.5 at high effort** (trigger 5 does not apply by itself, but three tasks need Sonnet, a Sonnet session can dispatch Haiku subagents for the rest, and a model switch mid-plan costs a turn). The session dispatches every task to the agent in the table. Nothing is pushed. It touches `windows/` and `NotchBuddy/`, and `AppState.swift` and `IslandWindowController.swift` in six tasks, so it must not run beside another plan that edits them (G2-mac does).

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up (it carries the owner's advance approval of the brief in step 3):

   > Run `git switch -c u1/upstream-fixes-and-qol notchmeow/rebrand`, then Task 0 of `docs/superpowers/plans/2026-10-15-u1-upstream-fixes-and-island-qol.md`: only its Steps 1 and 2 (the base checks: `git merge-base --is-ancestor e8c28e9 HEAD` must succeed). Read `CLAUDE.md`, `ARCHITECT.md` and that plan. If a base check fails, say so and stop. Reply "ready" and stop. Do not start Task 1. The owner approves in advance the controller brief the main session will send as your next message.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-15-u1-upstream-fixes-and-island-qol.md` with `superpowers:subagent-driven-development`, task by task, on branch `u1/upstream-fixes-and-qol`. Dispatch each task to the agent the plan's "Tasks and agents" table names (Haiku 5.5 first; Sonnet 5.5 only where the table names it or for a task Haiku failed twice, and then the trigger goes in the ledger), then to `nm-reviewer`; fix what the review finds before the next task. Rules for you and for every subagent (put the plan's SUBAGENT RULES block in every brief):
>
> - **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder (under `.claude/worktrees/`), the second `u1/upstream-fixes-and-qol`. If either is wrong, stop and report. Commit with `git commit -F <file>`, never `-m`, with the trailer of the model that did the task. Never push.
> - **Ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-15-u1/progress.md`: one line per task with its agent, model, commit hash, test lines and review verdict, and any escalation to `nm-implementer-deep` with the trigger.
> - **Briefs are task-sized.** A brief carries one task: its text, the Global Constraints, the SUBAGENT RULES and the files it names. Never hand a subagent the whole plan.
> - **Reviews** read `git diff notchmeow/rebrand...HEAD` (three dots), narrowed to the task's files, never `..` and never a diff against a moving working tree.
> - **Every shell block in the plan passes `bash -n` before it is run**, and a script you write passes it too.
> - **Rust** runs as `windows/scripts/cargo-linux.sh test --workspace --offline --target-dir /repo/windows/target/u1` (Task 15) and never with `docker build` or `docker pull`; if the image is missing or Docker is down, say so, run the local probe for the pure functions (see "How to run this plan") and mark the rest "needs Docker".
> - **Servers and processes.** Stop a server only by the PID you saved when you started it. Never launch, quit or replace a NotchMeow app: the builds are builds, and the pictures come from the render scripts. Install and download nothing. Never read the real `~/.claude`.
> - **Stop and report on any refusal** (a denied command, a permission prompt): do not look for a workaround.
> - **Ping the main session.** The main session's id is in the chip prompt that started you. At each owner checkpoint (the pictures of Tasks 6 and 10, and Task 16), at the end, and whenever you stop (a refusal, a failed check, a question), send your report to it with `SendMessage` as well as writing it in your own chat, so the main session can double-check the work (its own clone, merge and full checks) before anything reaches the owner.
> - **Owner checkpoints.** After Task 6 and after Task 10 (and Task 11) stop and report with the pictures copied into `.claude/checkpoints/u1/` of the worktree (gitignored); the owner may change the numbers (the glow's width and blur, the question card's estimate) and the session applies them before going on. After Task 15 dispatch `nm-reviewer-deep` over the whole branch, fix what it finds, then stop and report (Task 16).
>
> Report: the commits; the output of `bash scripts/test-hook-relay.sh`, `bash scripts/test-u1-wiring.sh`, `bash scripts/test-approval-click-guard.sh`, `bash scripts/test-ask-question.sh`, `bash scripts/test-island-hover.sh`, `bash scripts/test-island-outside-click.sh`, `bash scripts/test-island-glow.sh`, `bash scripts/test-island-wing.sh`, `bash scripts/test-island-wing-wiring.sh`, `bash scripts/test-theme.sh`, `bash scripts/check-no-leftovers.sh` and `cd windows && npm run check:cat`; the Debug, Release and App Store build lines; `npx tsc --noEmit`; the Rust test line (or why it was skipped); the paths of the pictures; Task 8's before and after table; and anything you could not settle.

Before any follow-up turn (a fix round, a question, a resumed run), the main session checks the session is still on its configured model and effort.

## How to run this plan

**Blocks.** A code step is **Create `path`** (the file's exact content, given in full below), **Edit `path`** (one or more find/replace pairs: a find text that occurs exactly once in that file at that point, and its replacement), or **Run**. Apply an edit by replacing the find text with the replacement and nothing else; if the find text occurs zero or two times (where the step says "both occurrences" it says so), stop and report: the tree is not what the plan expects. Never type a block from memory and never "improve" one. Every `Run:` line is run from the repository root (the worktree's top folder); `Expected: FAIL` and `Expected: PASS` say which way it must go, and the text after it says what to see. Edit blocks that need a `$` or backslash show it as it is in the file.

**Mac commands.** The test programs are `swiftc` programs run through `scripts/test-*.sh`; none needs Xcode. A build is `cd NotchBuddy && xcodegen && cd ..` and then `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3` (about two minutes); Release is `-configuration Release -derivedDataPath NotchBuddy/build/release`, the App Store target `-scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store`, each with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` (git ignores `NotchBuddy/build/`). **Never start a built app.** The render and measurement scripts compile every file of the app, which takes **about seven minutes** each time on the dry-run machine (run them in the background and do other work); they write wherever `--out` says, here under `${TMPDIR:-/tmp}/u1`, and the checkpoints copy the ones the owner sees to `.claude/checkpoints/u1/`.

**Windows/Linux commands** run in `windows/` (`npm run check:cat`, `npx --no-install tsc --noEmit`); `windows/node_modules` is already there. A `sed -i` differs between macOS and Linux: use the Edit blocks, not `sed`.

**Rust, locally and offline (a check, never a commit).** Docker may be down. The two Rust crates' pure functions can still be run on the Mac: make a scratch cargo crate **outside the repo** (`mktemp -d`) with `serde_json = "1"`, a `src/lib.rs` that includes the file under test with `#[path = "<worktree>/windows/hook/src/agents.rs"] pub mod agents;`, and run `CARGO_TARGET_DIR=<scratch>/target cargo test --offline`. For `windows/hook/src/main.rs` copy it into the scratch crate's `src/bin/` replacing its `#[cfg(target_os = "linux")] mod unix; ... use unix::connect;` pair with `fn connect() -> Option<std::os::unix::net::UnixStream> { None }` and its `mod agents;` with the `#[path]` line. The dry run did exactly this (25 hook tests, 3 zoom tests). It proves the logic, not the Tauri build: `windows/scripts/cargo-linux.sh` is the real run.

**Looking at an image.** The agent that ran the step opens the PNG with its file reader and says in one sentence what it sees against the thing named; a blank or broken image is a failed step. The owner's look is the checkpoint.

**Bite steps.** Some steps break the code on purpose to prove a test fails. Back the file up into a folder you made with `mktemp -d`, change it as the step says, run the test, and copy the backup back; the next step starts from the real file.

---
## Tasks

### Task 0: Worktree and baseline

No code and no commit. Its first two steps are what the chip's prompt runs before the model is set (see "Execution").

- [ ] **Step 1: Put the session's worktree on the plan's branch**

```bash
git status                                    # must be clean
git switch -c u1/upstream-fixes-and-qol notchmeow/rebrand
git merge-base --is-ancestor e8c28e9 HEAD && echo "the base (e8c28e9) is in the history"
git log --oneline -3
```

Expected: `the base (e8c28e9) is in the history`. If that line is missing, the worktree was cut from an older base: stop and tell the owner. Every later command runs from the root of this worktree. Never push.

- [ ] **Step 2: Check the places this plan edits are as it expects**

```bash
grep -c "Gemini CLI and Antigravity expect a JSON response on stdout" NotchBuddy/Sources/App/HookServer.swift
grep -c "DispatchQueue.global().asyncAfter(deadline: .now() + 3600, execute: work)" NotchBuddy/Sources/App/AppState.swift
grep -c "pub fn silent_answer" windows/hook/src/agents.rs
grep -c "case \"Stop\":" windows/src/island/hooks.ts
grep -c "func buildApproval" windows/src/views/views.ts
grep -c "struct ApprovalView" NotchBuddy/Sources/App/IslandViewContent.swift
grep -c "final class IslandStateMachine" NotchBuddy/Sources/App/IslandStateMachine.swift
grep -c "private func pollFrame" NotchBuddy/Sources/App/IslandWindowController.swift
grep -c "export const GROUPS" scripts/gen-theme.mjs
```

Expected: `2`, `1`, `1`, `1`, `1`, `1`, `1`, `1`, `1`.

- [ ] **Step 3: Baseline: the checks this plan must not move, and a build**

```bash
bash scripts/test-island-wing.sh 2>&1 | tail -1
bash scripts/test-island-wing-wiring.sh 2>&1 | tail -1
bash scripts/test-ask-question.sh 2>&1 | tail -1
bash scripts/test-theme.sh 2>&1 | tail -2
bash scripts/check-no-leftovers.sh 2>&1 | tail -1
(cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)" && npx --no-install tsc --noEmit && echo tsc ok)
cd NotchBuddy && xcodegen > /dev/null && cd .. && git status --short | head -3
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"
```

Expected: `All tests passed.` three times; the theme check's two last lines (`✓ 3 theme files match shared/theme.json`); the leftovers guard's last `✓` line; `ℹ tests 372`, `ℹ pass 372`, `ℹ fail 0` (the dry run's baseline; a later base may count more) and `tsc ok`; **no output from `git status`** (xcodegen changes nothing before any file is added: if `project.pbxproj` shows as modified here, say so and stop); and `** BUILD SUCCEEDED **`. Note the Debug build's time.

- [ ] **Step 4: Read the base once**

Read, without changing: `IslandStateMachine.swift`, `IslandWindowController.swift` (`pollFrame`, `wireFSM`, the mouse monitors), `IslandWing.swift`, `EscapeRouting.swift`, `IslandRootView.swift` (`IslandContainer`, `IslandShape`, `CountdownBar`), `IslandViewContent.swift` (`ApprovalView`, `QuestionView`), `windows/src/island/fsm.ts`, `island.ts` (`onCursor`, `wireInput`) and `hooks.ts`. Nothing to report.

---

### Task 1: Antigravity answers `ask` on PreToolUse

**Files:**
- Create: `scripts/test-hook-relay.sh`
- Modify: `NotchBuddy/Sources/App/HookServer.swift` (both embedded relays), `windows/hook/src/agents.rs`, `windows/hook/src/main.rs`

**Interfaces:**
- Produces: Rust `agents::silent_answer(agent: &str, event: &str) -> Option<&'static str>` (the event is the translated name) and `stdout_for(decision: Option<&str>, agent: &str, event: &str) -> Option<String>` in `main.rs`. Nothing else depends on them.

Upstream's reason, in short: Antigravity treats `{}` on PreToolUse as a denial. Upstream's first fix answered `allow`, which would run every tool without a prompt; the final one (66be53e) answers `ask`, which keeps Antigravity's own prompt. NotchMeow keeps that, and the Rust tests that say nothing is allowed without a decision stay as they are.

- [ ] **Step 1: Write the failing test (the Mac relays, run for real)**

**Create `scripts/test-hook-relay.sh`:**

```bash
#!/usr/bin/env bash
# The hook relay's answers on stdout, run for real: the two Python relays embedded in HookServer.swift (GitHub and App Store) are cut out
# of the Swift source, written to a temporary folder and run with python3 in a home folder of their own, so no socket is reachable (the
# relay never blocks: with the app unreachable it still prints its answer). Antigravity reads "{}" on PreToolUse as a denial, so it is
# answered {"decision":"ask"}: its own prompt stays, and NotchMeow never allows a tool by itself.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-hook-relay.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/home"

python3 -I - "$TEST_DIR" <<'PY'
import re, sys
out = sys.argv[1]
src = open("NotchBuddy/Sources/App/HookServer.swift", encoding="utf-8").read()
for name, label in (("nbHookPythonGitHub", "github"), ("nbHookPythonAppStore", "appstore")):
    m = re.search(r'private let ' + name + r' = """\n(.*?)\n"""', src, re.S)
    if not m:
        sys.exit("cannot find " + name + " in HookServer.swift")
    body = m.group(1).replace("\\\\", "\\")   # Swift's escape for one backslash
    open(f"{out}/nm-hook-{label}.py", "w", encoding="utf-8").write(body + "\n")
PY

pass=0; fail=0
# relay <label> <stdin JSON> <args...>: prints what the relay wrote on stdout
relay() {
    local label="$1" input="$2"; shift 2
    printf '%s' "$input" | HOME="$TEST_DIR/home" python3 -I "$TEST_DIR/nm-hook-$label.py" "$@" 2>/dev/null || true
}
expect() {   # expect <name> <got> <want>
    if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "✓ $1"; else fail=$((fail + 1)); echo "✗ $1: got [$2], wanted [$3]"; fi
}
for label in github appstore; do
    tool='{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/tmp/p","tool_name":"run_command","tool_input":{"command":"ls"}}'
    expect "$label: antigravity PreToolUse is asked, never allowed" "$(relay $label "$tool" --agent antigravity PreToolUse)" '{"decision":"ask"}'
    expect "$label: antigravity BeforeTool (its other spelling) is asked too" "$(relay $label '{"hook_event_name":"BeforeTool","session_id":"s1","toolCall":{"name":"x","args":{}}}' --agent antigravity)" '{"decision":"ask"}'
    for ev in PostToolUse PreInvocation PostInvocation Stop; do
        expect "$label: antigravity $ev keeps the empty answer" "$(relay $label "{\"hook_event_name\":\"$ev\",\"session_id\":\"s1\"}" --agent antigravity $ev)" '{}'
    done
    expect "$label: gemini PreToolUse keeps the empty answer" "$(relay $label "$tool" --agent gemini PreToolUse)" '{}'
    expect "$label: Claude Code PreToolUse stays silent" "$(relay $label "$tool" PreToolUse)" ''
done
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash -n scripts/test-hook-relay.sh && bash scripts/test-hook-relay.sh`
Expected: FAIL: `12 passed, 4 failed`; the four failures are "antigravity PreToolUse is asked" and "antigravity BeforeTool … asked too", for `github` and `appstore`, each `got [{}]`. (The other twelve pass: they pin what must not change.)

- [ ] **Step 3: Fix both Mac relays**

**Edit `NotchBuddy/Sources/App/HookServer.swift`:** find

```python
    # Gemini CLI and Antigravity expect a JSON response on stdout (empty = no decision)
    if agent in ('gemini', 'antigravity'):
        sys.stdout.write('{}\\n')
        sys.stdout.flush()
```

replace with

```python
    # Gemini CLI and Antigravity expect a JSON response on stdout (empty = no decision).
    # Antigravity reads "{}" on PreToolUse as a denial, so it gets "ask": its own permission prompt
    # (and the user's Always Allow) stays, and NotchMeow never allows a tool by itself.
    if agent == 'antigravity' and event == 'PreToolUse':
        sys.stdout.write('{"decision":"ask"}\\n')
        sys.stdout.flush()
    elif agent in ('gemini', 'antigravity'):
        sys.stdout.write('{}\\n')
        sys.stdout.flush()
```

This text occurs **twice** in `HookServer.swift` (the GitHub relay and the App Store relay): replace **both**. The file is Swift and the text is inside a Python string, so `\\n` is two backslashes and an `n`, exactly as shown.

- [ ] **Step 4: Run the Mac test**

Run: `bash scripts/test-hook-relay.sh`
Expected: PASS: `16 passed, 0 failed`.

- [ ] **Step 5: The Windows/Linux relay: write the failing Rust tests first**

**Edit `windows/hook/src/agents.rs`:** find

```rust
    fn only_gemini_and_antigravity_get_the_empty_json_answer() {
        assert_eq!(silent_answer("gemini"), Some("{}"));
        assert_eq!(silent_answer("antigravity"), Some("{}"));
        for other in ["", "claude", "codex", "cursor", "my-tool", "Gemini", "gemini-cli"] {
            assert_eq!(silent_answer(other), None, "{other}");
        }
    }
```

replace with

```rust
    fn only_gemini_and_antigravity_get_the_empty_json_answer() {
        assert_eq!(silent_answer("gemini", "PreToolUse"), Some("{}"));
        assert_eq!(silent_answer("antigravity", "PostToolUse"), Some("{}"));
        for other in ["", "claude", "codex", "cursor", "my-tool", "Gemini", "gemini-cli"] {
            assert_eq!(silent_answer(other, "PreToolUse"), None, "{other}");
        }
    }

    #[test]
    fn antigravity_pre_tool_use_is_asked_never_answered_empty_or_allowed() {
        assert_eq!(silent_answer("antigravity", "PreToolUse"), Some(r#"{"decision":"ask"}"#));
        for event in ["PostToolUse", "UserPromptSubmit", "Stop", "SessionStart", "PermissionRequest"] {
            assert_eq!(silent_answer("antigravity", event), Some("{}"), "{event}");
        }
        // Gemini keeps `{}` on every event, PreToolUse included.
        assert_eq!(silent_answer("gemini", "PreToolUse"), Some("{}"));
        // Whatever it answers, it never says allow.
        for event in ["PreToolUse", "PostToolUse", "Stop"] {
            assert!(!silent_answer("antigravity", event).unwrap().contains("allow"), "{event}");
        }
    }
```

**Edit `windows/hook/src/main.rs`:** find

```rust
        assert_eq!(stdout_for(None, "gemini").as_deref(), Some("{}"));
        assert_eq!(stdout_for(None, "antigravity").as_deref(), Some("{}"));
        assert_eq!(stdout_for(None, ""), None, "Claude Code: silence");
        assert_eq!(stdout_for(None, "codex"), None);
        // A decision from the island is never replaced by the empty answer.
        assert!(stdout_for(Some("allow"), "gemini").unwrap().contains(r#""behavior":"allow""#));
        // An answer nobody recognises is silence for Claude Code, and `{}` for Gemini.
        assert_eq!(stdout_for(Some("maybe"), ""), None);
        assert_eq!(stdout_for(Some("maybe"), "gemini").as_deref(), Some("{}"));
```

replace with

```rust
        assert_eq!(stdout_for(None, "gemini", "PreToolUse").as_deref(), Some("{}"));
        assert_eq!(stdout_for(None, "antigravity", "Stop").as_deref(), Some("{}"));
        assert_eq!(stdout_for(None, "", "PreToolUse"), None, "Claude Code: silence");
        assert_eq!(stdout_for(None, "codex", "PreToolUse"), None);
        // Antigravity reads `{}` on PreToolUse as a denial: it is asked, which leaves the choice to its own prompt.
        assert_eq!(stdout_for(None, "antigravity", "PreToolUse").as_deref(), Some(r#"{"decision":"ask"}"#));
        // A decision from the island is never replaced by the empty answer.
        assert!(stdout_for(Some("allow"), "gemini", "PermissionRequest").unwrap().contains(r#""behavior":"allow""#));
        // An answer nobody recognises is silence for Claude Code, and `{}` for Gemini.
        assert_eq!(stdout_for(Some("maybe"), "", "PermissionRequest"), None);
        assert_eq!(stdout_for(Some("maybe"), "gemini", "PermissionRequest").as_deref(), Some("{}"));
```

- [ ] **Step 6: Run the Rust tests to see them fail (a compile error), then implement**

Run: `windows/scripts/cargo-linux.sh test -p notchmeow-hook --offline --target-dir /repo/windows/target/u1` (needs Docker; otherwise the local probe of "How to run this plan").
Expected: FAIL: `this function takes 1 argument but 2 arguments were supplied` for `silent_answer` and `stdout_for`.

**Edit `windows/hook/src/agents.rs`:** find

```rust
/// Gemini CLI and Antigravity read a hook's stdout as JSON, and `{}` is their
/// "no decision". Claude Code and every other agent want silence.
pub fn silent_answer(agent: &str) -> Option<&'static str> {
    matches!(agent, GEMINI | ANTIGRAVITY).then_some("{}")
}
```

replace with

```rust
/// Gemini CLI and Antigravity read a hook's stdout as JSON, and `{}` is their
/// "no decision". Claude Code and every other agent want silence. `event` is the
/// translated event name. Antigravity reads `{}` on PreToolUse as a denial, so it is
/// answered "ask": its own permission prompt (and the user's Always Allow) stays, and
/// NotchMeow never allows a tool by itself.
pub fn silent_answer(agent: &str, event: &str) -> Option<&'static str> {
    if agent == ANTIGRAVITY && event == "PreToolUse" {
        return Some(r#"{"decision":"ask"}"#);
    }
    matches!(agent, GEMINI | ANTIGRAVITY).then_some("{}")
}
```

**Edit `windows/hook/src/main.rs`:** find

```rust
    if let Some(json) = stdout_for(decision.as_deref(), &agent) {
```

replace with

```rust
    if let Some(json) = stdout_for(decision.as_deref(), &agent, &event) {
```

**Edit `windows/hook/src/main.rs`:** find

```rust
/// nothing, so Claude Code asks in the terminal; Gemini CLI and Antigravity
/// insist on JSON, so they get `{}`.
fn stdout_for(decision: Option<&str>, agent: &str) -> Option<String> {
    decision
        .and_then(decision_json)
        .or_else(|| agents::silent_answer(agent).map(str::to_string))
```

replace with

```rust
/// nothing, so Claude Code asks in the terminal; Gemini CLI and Antigravity
/// insist on JSON, so they get `{}` (Antigravity's PreToolUse gets "ask", see
/// `agents::silent_answer`).
fn stdout_for(decision: Option<&str>, agent: &str, event: &str) -> Option<String> {
    decision
        .and_then(decision_json)
        .or_else(|| agents::silent_answer(agent, event).map(str::to_string))
```

- [ ] **Step 7: Run the Rust tests**

Run: the same command as Step 6.
Expected: PASS: `25 passed` in `notchmeow-hook` (the dry run's count through the probe; the workspace run has more crates). In the dry run the probe printed `test agents::tests::antigravity_pre_tool_use_is_asked_never_answered_empty_or_allowed ... ok` and `test tests::only_gemini_and_antigravity_are_answered_with_json_when_there_is_no_decision ... ok`.

- [ ] **Step 8: The docs mention the old answer? Check**

Run: `grep -rn 'silent_answer\|"decision":"allow"\|empty answer' windows/README.md docs/INTEGRATIONS.md | head`
Expected: no line about Antigravity answering `{}` on PreToolUse. If there is one, change that sentence to say "ask" and name it in the commit.

- [ ] **Step 9: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current       # the worktree and u1/upstream-fixes-and-qol
git add scripts/test-hook-relay.sh NotchBuddy/Sources/App/HookServer.swift windows/hook/src/agents.rs windows/hook/src/main.rs
git commit -F - <<'EOF'
fix(hooks): Antigravity PreToolUse is answered "ask", never "{}" (upstream 66be53e)

Antigravity reads {} on PreToolUse as a denial, so the relay blocked every tool. "ask" hands the
choice back to Antigravity's own prompt; NotchMeow never allows a tool by itself. Both Mac relays
and the Windows/Linux relay; scripts/test-hook-relay.sh runs the two embedded Python relays.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 2: The one-hour diff timer on the main queue, and the wiring script

**Files:**
- Create: `scripts/test-u1-wiring.sh`
- Modify: `NotchBuddy/Sources/App/AppState.swift`

**Interfaces:**
- Produces: `scripts/test-u1-wiring.sh`, whose `has` and `hasnt` helpers and `pass`/`fail` counters later tasks append pins to (each task adds its lines before the closing `echo "$pass passed…"` line).

Upstream's crash (d05f22b): NotchMeow's `resetSessionDiffTimer` is the same text. The closure inside a `@MainActor` class is MainActor-isolated; scheduled on `DispatchQueue.global()` it traps in Swift 6's isolation check when it fires an hour after the last Edit/Write, and the app quits. The other two `DispatchQueue.global().asyncAfter` uses in the app (`ClaudeCodeLocator.Job.schedule`, `ClaudeCodeProvider`'s termination handler) take `@Sendable` closures that touch no main-actor state: not the same bug, leave them.

- [ ] **Step 1: Write the failing pin**

**Create `scripts/test-u1-wiring.sh`:**

```bash
#!/usr/bin/env bash
# Where the app calls the pure rules of the "upstream fixes and island quality of life" plan (U1), pinned as source text: the crash fix, Open on hover and the wing, the permission card's click guard, the
# question card's descriptions, the outside click's monitor (only while expanded) and the hover glow (only while hovered). Each line is a check that fails, naming itself, when the text is gone.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=NotchBuddy/Sources/App
pass=0; fail=0
has()  { if grep -qF -- "$3" "$APP/$2"; then pass=$((pass + 1)); echo "✓ $1"; else fail=$((fail + 1)); echo "✗ $1: [$3] not found in $2"; fi; }
hasnt(){ if grep -qF -- "$3" "$APP/$2"; then fail=$((fail + 1)); echo "✗ $1: [$3] must not be in $2"; else pass=$((pass + 1)); echo "✓ $1"; fi; }

# The crash fix (upstream d05f22b): the one-hour diff timer runs on the main queue, never on a global queue.
has   "diff timer on the main queue"            AppState.swift "DispatchQueue.main.asyncAfter(deadline: .now() + 3600, execute: work)"
hasnt "no global-queue diff timer"              AppState.swift "DispatchQueue.global().asyncAfter(deadline: .now() + 3600"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash -n scripts/test-u1-wiring.sh && bash scripts/test-u1-wiring.sh`
Expected: FAIL: `✗ diff timer on the main queue` and `✗ no global-queue diff timer`... precisely: the first fails (`[DispatchQueue.main.asyncAfter…] not found`), and the second fails (`must not be in`) , so `0 passed, 2 failed`.

- [ ] **Step 3: Fix the timer**

**Edit `NotchBuddy/Sources/App/AppState.swift`:** find

```swift
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async { self?.clearSessionDiffs(for: pillId) }
        }
        sessionDiffTimers[pillId] = work
        DispatchQueue.global().asyncAfter(deadline: .now() + 3600, execute: work)
```

replace with

```swift
        // The closure is MainActor-isolated (AppState is @MainActor): it must run on the main queue.
        // Scheduled on a global queue, Swift 6's isolation check traps an hour later and the app quits.
        let work = DispatchWorkItem { [weak self] in
            self?.clearSessionDiffs(for: pillId)
        }
        sessionDiffTimers[pillId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3600, execute: work)
```

- [ ] **Step 3b: Run the pin**

Run: `bash scripts/test-u1-wiring.sh`
Expected: PASS: `2 passed, 0 failed`.

- [ ] **Step 4: Build (Debug)**

Run: the Debug build line of "How to run this plan".
Expected: `** BUILD SUCCEEDED **` (no new file yet, so no `xcodegen` is needed).

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add scripts/test-u1-wiring.sh NotchBuddy/Sources/App/AppState.swift
git commit -F - <<'EOF'
fix(mac): the one-hour diff timer fires on the main queue (upstream d05f22b)

A MainActor-isolated closure scheduled on a global queue trapped in Swift 6's isolation check an hour
after the last file edit, and the app quit. scripts/test-u1-wiring.sh starts here: the pins of this plan.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 3: Windows/Linux: the click guard, the stale Stop timer and the pill padding

**Files:**
- Create: `windows/src/island/stoptimers.ts`, `windows/src/views/clickguard.ts`, `windows/scripts/cat-tests/u1-guards.test.mjs`
- Modify: `windows/src/island/hooks.ts`, `windows/src/views/views.ts`, `windows/src/style.css`

**Interfaces:**
- Produces: `class StopTimers { constructor(env?: StopTimerEnv); arm(id: string, ms: number, fn: () => void): void; cancel(id: string): boolean; has(id: string): boolean }` and `class ClickGuard { shown(requestId: string | null, now: number): void; blocks(now: number): boolean }` with `const CLICK_GUARD_MS = 600`. Both are pure (the timer and the clock are passed in), so `check:cat` runs them in plain Node.

Upstream: 5b06e1c (the guard), 3491a2b (the Stop timer), 2fb18a5 (the padding: `padding: 0 8px 0 34px`). NotchMeow's pill cat is a 24 px canvas with `margin-left: 7px` (`.pill .mini`), so it ends at 31 px: 34 px leaves 3 px clear. The Windows island has no question card yet, so only the permission card is guarded.

- [ ] **Step 1: Write the failing tests**

**Create `windows/scripts/cat-tests/u1-guards.test.mjs`:**

```javascript
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { StopTimers } from "../../src/island/stoptimers.ts";
import { CLICK_GUARD_MS, ClickGuard } from "../../src/views/clickguard.ts";

const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

/** A timer queue the test turns by hand. */
function queue() {
  const q = { t: 0, id: 1, timers: new Map(), sets: 0, clears: 0 };
  q.env = {
    set: (fn, ms) => { const id = q.id++; q.sets++; q.timers.set(id, { fn, at: q.t + ms }); return id; },
    clear: (id) => { q.clears++; q.timers.delete(id); },
  };
  q.advance = (ms) => {
    const end = q.t + ms;
    for (const [id, x] of [...q.timers.entries()].sort((a, b) => a[1].at - b[1].at)) if (x.at <= end) { q.timers.delete(id); x.fn(); }
    q.t = end;
  };
  return q;
}

test("a Stop's return to idle fires once, after its delay", () => {
  const q = queue(), stops = new StopTimers(q.env);
  let idle = 0;
  stops.arm("integration_claude", 5200, () => idle++);
  assert.equal(stops.has("integration_claude"), true);
  q.advance(5199); assert.equal(idle, 0);
  q.advance(1); assert.equal(idle, 1);
  assert.equal(stops.has("integration_claude"), false, "the entry is gone once it has fired");
  q.advance(60_000); assert.equal(idle, 1);
});

test("the next turn cancels the return, so the pill is not flipped to idle in the middle of it", () => {
  const q = queue(), stops = new StopTimers(q.env);
  let idle = 0;
  stops.arm("integration_claude", 5200, () => idle++);
  q.advance(3000);
  assert.equal(stops.cancel("integration_claude"), true);
  q.advance(10_000);
  assert.equal(idle, 0);
  assert.equal(stops.cancel("integration_claude"), false, "nothing left to cancel");
});

test("a second Stop for the same pill replaces the first; another pill's timer is not touched", () => {
  const q = queue(), stops = new StopTimers(q.env);
  const fired = [];
  stops.arm("a", 5200, () => fired.push("a1"));
  stops.arm("b", 5200, () => fired.push("b"));
  q.advance(2000);
  stops.arm("a", 5200, () => fired.push("a2"));
  assert.equal(q.clears, 1, "only a's first timer was cleared");
  stops.cancel("zzz");
  q.advance(3200);
  assert.deepEqual(fired, ["b"], "b fired at 5200, a's second timer is 2000 ms behind");
  q.advance(2000);
  assert.deepEqual(fired, ["b", "a2"]);
});

test("the click guard ignores the first 600 ms of a new request and no more", () => {
  const g = new ClickGuard();
  assert.equal(CLICK_GUARD_MS, 600);
  g.shown("req-1", 1000);
  assert.equal(g.blocks(1000), true);
  assert.equal(g.blocks(1599), true);
  assert.equal(g.blocks(1600), false);
  g.shown("req-1", 5000);          // the same request drawn again (every sync): the clock does not restart
  assert.equal(g.blocks(5000), false);
  g.shown("req-2", 6000);          // a different request starts it again
  assert.equal(g.blocks(6300), true);
  assert.equal(g.blocks(6600), false);
});

test("a guard that has seen no request blocks nothing once 600 ms of the page's life have passed", () => {
  const g = new ClickGuard();
  assert.equal(g.blocks(100_000), false);
});

test("the wiring: hooks.ts cancels the Stop timer on the next turn, and the approval buttons go through the guard", () => {
  const hooks = source("island/hooks.ts");
  assert.match(hooks, /new StopTimers\(\)/);
  assert.equal((hooks.match(/supersedeStop\(\)/g) ?? []).length >= 6, true, "prompt, tool, post-tool, failure and both notifications");
  assert.match(hooks, /stopTimers\.arm\(/);
  const views = source("views/views.ts");
  assert.match(views, /new ClickGuard\(\)/);
  assert.match(views, /guard\.blocks\(performance\.now\(\)\)/);
  assert.match(views, /guard\.shown\(State\.pendingApproval\?\.requestId \?\? null, performance\.now\(\)\)/);
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd windows && node --experimental-strip-types --test --test-reporter=spec scripts/cat-tests/u1-guards.test.mjs`
Expected: FAIL: `Cannot find module '.../stoptimers.ts'`.

- [ ] **Step 3: The two pure modules**

**Create `windows/src/island/stoptimers.ts`:**

```typescript
// The return to idle that a Stop event arms, one per pill. The next turn (a prompt, a tool, a failure, a question) cancels it: otherwise the timer fires in the
// middle of that turn and the pill flips to idle while the agent is still working. Pure: the timer is injected, so the plain-Node checks can turn time by hand.

export interface StopTimerEnv {
  set(fn: () => void, ms: number): number;
  clear(id: number): void;
}

const realEnv: StopTimerEnv = {
  set: (fn, ms) => globalThis.setTimeout(fn, ms) as unknown as number,
  clear: (id) => globalThis.clearTimeout(id as unknown as ReturnType<typeof setTimeout>),
};

export class StopTimers {
  private readonly timers = new Map<string, number>();
  private readonly env: StopTimerEnv;

  constructor(env: StopTimerEnv = realEnv) {
    this.env = env;
  }

  /** Arms the return for `id` in `ms`; an earlier one for the same pill is cancelled first. `fn` runs once, and the entry is gone by then. */
  arm(id: string, ms: number, fn: () => void): void {
    this.cancel(id);
    this.timers.set(
      id,
      this.env.set(() => {
        this.timers.delete(id);
        fn();
      }, ms),
    );
  }

  /** Cancels the return armed for `id`. True when there was one. */
  cancel(id: string): boolean {
    const timer = this.timers.get(id);
    if (timer == null) return false;
    this.env.clear(timer);
    this.timers.delete(id);
    return true;
  }

  /** Whether a return is armed for `id`. */
  has(id: string): boolean {
    return this.timers.has(id);
  }
}
```

**Create `windows/src/views/clickguard.ts`:**

```typescript
// A fresh permission card ignores clicks for its first 600 ms: it opens under a pointer that was busy with the window underneath, and a click meant for that window
// must not land on Allow or Deny. The keyboard (Y and N) is not a click and is not guarded. Pure: the clock is passed in.

export const CLICK_GUARD_MS = 600;

export class ClickGuard {
  private shownFor: string | null = null;
  private shownAt = 0;

  /** Tells the guard which request the card shows now. A request it has not seen starts the 600 ms; the same request again changes nothing. */
  shown(requestId: string | null, now: number): void {
    if (requestId === this.shownFor) return;
    this.shownFor = requestId;
    this.shownAt = now;
  }

  /** True while a click on the card's buttons must be ignored. */
  blocks(now: number): boolean {
    return now - this.shownAt < CLICK_GUARD_MS;
  }
}
```

- [ ] **Step 4: Use them: the hook handler**

**Edit `windows/src/island/hooks.ts`:** find

```typescript
import { kittenEventOf } from "./subagents.ts";
```

replace with

```typescript
import { kittenEventOf } from "./subagents.ts";
import { StopTimers } from "./stoptimers.ts";
```

**Edit `windows/src/island/hooks.ts`:** find

```typescript
/** The part of a hook event the island reads
```

replace with

```typescript
/** The return to idle that Stop arms, per pill: the next turn cancels it, or it would flip the pill to idle in the middle of that turn. */
const stopTimers = new StopTimers();

/** The part of a hook event the island reads
```

**Edit `windows/src/island/hooks.ts`:** find

```typescript
  switch (name) {
    case "SessionStart":
```

replace with

```typescript
  /**
   * Called where a handler is about to replace `finished` with a newer state: the timer Stop armed would otherwise put the pill back to idle over it.
   * The badge that timer was going to clear goes now.
   */
  const supersedeStop = () => {
    if (stopTimers.cancel(agentId)) State.setPillBadge(agentId, null);
  };

  switch (name) {
    case "SessionStart":
```

**Edit `windows/src/island/hooks.ts`:** find

```typescript
    case "UserPromptSubmit": {
      ensurePill();
      State.updateTask
```

replace with

```typescript
    case "UserPromptSubmit": {
      ensurePill();
      supersedeStop();
      State.updateTask
```

**Edit `windows/src/island/hooks.ts`:** find

```typescript
    case "PreToolUse": {
      ensurePill();
      State.updateTask(agentId, toolState
```

replace with

```typescript
    case "PreToolUse": {
      ensurePill();
      supersedeStop();
      State.updateTask(agentId, toolState
```

**Edit `windows/src/island/hooks.ts`:** find

```typescript
    case "PostToolUse":
      State.updateTask(agentId, toolState(payload.tool_name));
```

replace with

```typescript
    case "PostToolUse":
      supersedeStop();
      State.updateTask(agentId, toolState(payload.tool_name));
```

**Edit `windows/src/island/hooks.ts`:** find

```typescript
    case "PostToolUseFailure":
      State.updateTask(agentId, "working");
```

replace with

```typescript
    case "PostToolUseFailure":
      supersedeStop();
      State.updateTask(agentId, "working");
```

**Edit `windows/src/island/hooks.ts`:** find

```typescript
      if (lower.includes("rate limit") || lower.includes("limite d")) {
        State.updateTask(agentId, "ratelimit");
```

replace with

```typescript
      if (lower.includes("rate limit") || lower.includes("limite d")) {
        supersedeStop();
        State.updateTask(agentId, "ratelimit");
```

**Edit `windows/src/island/hooks.ts`:** find

```typescript
      } else if (message.endsWith("?")) {
        State.updateTask(agentId, "question");
```

replace with

```typescript
      } else if (message.endsWith("?")) {
        supersedeStop();
        State.updateTask(agentId, "question");
```

**Edit `windows/src/island/hooks.ts`:** find

```typescript
      window.setTimeout(() => {
        if (isExternalAgent) {
          State.removeTask(agentId);
        } else {
          State.updateTask(agentId, "idle");
          State.setPillBadge(agentId, null);
        }
      }, 5200);
      break;
```

replace with

```typescript
      stopTimers.arm(agentId, 5200, () => {
        if (isExternalAgent) {
          State.removeTask(agentId);
        } else {
          State.updateTask(agentId, "idle");
          State.setPillBadge(agentId, null);
        }
      });
      break;
```

- [ ] **Step 5: The approval card's buttons, and the pill padding**

**Edit `windows/src/views/views.ts`:** find

```typescript
import { buildPrompt } from "./chat";
```

replace with

```typescript
import { buildPrompt } from "./chat";
import { ClickGuard } from "./clickguard.ts";
```

**Edit `windows/src/views/views.ts`:** find

```typescript
  const el = h("div", { class: "view" }, card("amber", stack(116, 16, who, code, row)));
  let rowKey = "";
  return {
    el,
    sync() {
      clear(who);
```

replace with

```typescript
  const el = h("div", { class: "view" }, card("amber", stack(116, 16, who, code, row)));
  let rowKey = "";
  // The card opens under a pointer that was busy with something else: a click meant for the window underneath must not land on Allow or Deny. Clicks in the first
  // 600 ms after a new request appears are ignored (the keys Y and N are not clicks).
  const guard = new ClickGuard();
  const guarded = (d: "allow" | "deny") => () => {
    if (guard.blocks(performance.now())) return;
    actions.decide(d);
  };
  return {
    el,
    sync() {
      guard.shown(State.pendingApproval?.requestId ?? null, performance.now());
      clear(who);
```

**Edit `windows/src/views/views.ts`:** find

```typescript
        btn("Deny", "secondary", () => actions.decide("deny"), "N"),
        btn("Allow", "primary", () => actions.decide("allow"), "Y"),
```

replace with

```typescript
        btn("Deny", "secondary", guarded("deny"), "N"),
        btn("Allow", "primary", guarded("allow"), "Y"),
```

**Edit `windows/src/style.css`:** find

```css
  text-overflow: ellipsis;
  padding: 0 6px;
  pointer-events: none;
}

.pill:hover {
```

replace with

```css
  text-overflow: ellipsis;
  /* The pill's cat (a 24 px canvas, 7 px in) ends at 31 px: the label starts clear of it. */
  padding: 0 8px 0 34px;
  pointer-events: none;
}

.pill:hover {
```

Check the keys are not routed through the button: `grep -n '"keydown"' windows/src/island/island.ts` shows the island's own key handler, which calls `decide` directly, so Y and N are not guarded.

- [ ] **Step 6: Run the tests and the type check**

Run: `cd windows && node --experimental-strip-types --test --test-reporter=spec scripts/cat-tests/u1-guards.test.mjs 2>&1 | tail -12 && npx --no-install tsc --noEmit && echo tsc ok && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"`
Expected: PASS: the six tests of `u1-guards.test.mjs`; `tsc ok`; `check:cat` one fewer than 372 + 6: `ℹ tests 378`, `ℹ fail 0`.

- [ ] **Step 7: Look at the pill (owner's real-build check, listed in Task 16)**

The dry run could not render the Windows page. Run `cd windows && npx vite` and open `http://127.0.0.1:1420/?dev` (the contact sheet) only if it shows pills; otherwise leave it to Task 16's list. Stop the server by its PID.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add windows/src/island/stoptimers.ts windows/src/views/clickguard.ts windows/scripts/cat-tests/u1-guards.test.mjs windows/src/island/hooks.ts windows/src/views/views.ts windows/src/style.css
git commit -F - <<'EOF'
fix(windows): fresh permission card ignores clicks for 600 ms; the next turn cancels Stop's idle timer; pill labels clear the cat

Upstream 5b06e1c, 3491a2b and 2fb18a5, ported by hand with pure modules (ClickGuard, StopTimers) and tests.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4: Windows: the webview zoom follows the window's scale

**Files:**
- Modify: `windows/src-tauri/src/island.rs`, `windows/src-tauri/src/lib.rs`, `windows/src/core/bridge.ts`, `windows/src/main.ts`, `windows/src/island/island.ts`, `windows/scripts/cat-tests/desktop-island.test.mjs`

**Interfaces:**
- Produces: Rust `island::calculate_zoom_correction(current_zoom: f64, scale: f64, dpr: f64) -> Option<f64>` (pure), the Tauri command `fit_zoom(dpr: f64) -> bool` and `Bridge.fitZoom(dpr: number): Promise<boolean>`.

Upstream b9b9217 (#467/#346): on Windows 11 with text scaling or mixed-DPI monitors WebView2's `devicePixelRatio` differs from the window's scale factor, so a 720 px window holds fewer CSS pixels than the 640 px island needs and clips it. The fix corrects the webview's zoom so one CSS pixel is one logical pixel, retries a clamped resize once, and centres the island in the real viewport width. Windows-only in effect (on Linux the two ratios agree and `calculate_zoom_correction` returns `None`).

- [ ] **Step 1: The pure function and its tests (Rust)**

**Edit `windows/src-tauri/src/island.rs`:** find

```rust
pub fn screen_info(app: &AppHandle, pref: &str) -> ScreenInfo {
```

replace with

```rust
/// The zoom to give the webview so that one CSS pixel is one window logical pixel again. WebView2's devicePixelRatio can differ from the window's scale factor
/// (system text scaling, a mixed-DPI setup): a 720 px window then holds fewer CSS pixels than the 640 px island needs and clips it. `None` when they agree to
/// within 2 % or when either number is unusable.
pub fn calculate_zoom_correction(current_zoom: f64, scale: f64, dpr: f64) -> Option<f64> {
    if dpr <= 0.0 || !dpr.is_finite() || scale <= 0.0 || !scale.is_finite() {
        return None;
    }
    if (dpr - scale).abs() / scale < 0.02 {
        return None;
    }
    Some((current_zoom * (scale / dpr)).clamp(0.25, 4.0))
}

#[cfg(test)]
mod zoom_tests {
    use super::*;

    #[test]
    fn no_correction_when_the_ratio_matches_the_window_scale() {
        assert_eq!(calculate_zoom_correction(1.0, 1.0, 1.0), None);
        assert_eq!(calculate_zoom_correction(1.0, 1.25, 1.25), None);
        assert_eq!(calculate_zoom_correction(1.0, 1.0, 1.01), None, "within 2 %");
    }

    #[test]
    fn a_dpi_mismatch_is_corrected() {
        assert_eq!(calculate_zoom_correction(1.0, 1.0, 1.25), Some(0.8));
        assert_eq!(calculate_zoom_correction(1.0, 1.25, 1.5625), Some(0.8));
        assert_eq!(calculate_zoom_correction(1.0, 1.5, 1.0), Some(1.5));
    }

    #[test]
    fn the_correction_is_clamped_and_unusable_inputs_change_nothing() {
        assert_eq!(calculate_zoom_correction(1.0, 8.0, 1.0), Some(4.0));
        assert_eq!(calculate_zoom_correction(1.0, 1.0, 100.0), Some(0.25));
        assert_eq!(calculate_zoom_correction(1.0, 0.0, 1.0), None);
        assert_eq!(calculate_zoom_correction(1.0, 1.0, -1.0), None);
        assert_eq!(calculate_zoom_correction(1.0, f64::NAN, 1.0), None);
        assert_eq!(calculate_zoom_correction(1.0, 1.0, f64::INFINITY), None);
    }
}

pub fn screen_info(app: &AppHandle, pref: &str) -> ScreenInfo {
```

- [ ] **Step 2: Run the three tests**

Run: `windows/scripts/cargo-linux.sh test -p notchmeow --offline --target-dir /repo/windows/target/u1 zoom_tests` (needs Docker). Without Docker run the local probe with the function and its test module copied into the scratch crate (the dry run did: `3 passed`).
Expected: PASS: three tests.

- [ ] **Step 3: The command, the retry, the bridge, the page**

**Edit `windows/src-tauri/src/island.rs`:** find

```rust
    // Moving across displays can rescale the window: re-assert the physical size.
    let _ = win.set_size(PhysicalSize::new(pw, ph));
    let _ = win.set_always_on_top(true);
}
```

replace with

```rust
    // Moving across displays can rescale the window: re-assert the physical size.
    let _ = win.set_size(PhysicalSize::new(pw, ph));
    let _ = win.set_always_on_top(true);

    // Moving across displays or waking from the strip can clamp or lag the resize. If the physical inner size is not what was asked, ask once more.
    if let Ok(got) = win.inner_size() {
        if got.width != pw || got.height != ph {
            crate::log::line(format!(
                "window size mismatch: wanted {pw}x{ph}, got {}x{} (scale {scale}, monitor {}x{})",
                got.width, got.height, ms.width, ms.height
            ));
            let _ = win.set_size(PhysicalSize::new(pw, ph));
            let _ = win.set_position(PhysicalPosition::new(x, y));
        }
    }
}
```

**Edit `windows/src-tauri/src/lib.rs`:** find

```rust
#[tauri::command]
fn open_url(url: String) {
```

replace with

```rust
/// The panel is laid out in CSS px against the window's own scale. If the webview reports another devicePixelRatio, the page ends up wider than the window and
/// the island is cut: correct the webview's zoom so one CSS px is one logical px again. True when the zoom changed.
#[tauri::command]
fn fit_zoom(app: AppHandle, dpr: f64) -> bool {
    let Some(win) = island::window(&app) else { return false };
    let scale = win.scale_factor().unwrap_or(1.0);
    static ZOOM: Mutex<f64> = Mutex::new(1.0);
    let mut zoom = ZOOM.lock().unwrap();
    match island::calculate_zoom_correction(*zoom, scale, dpr) {
        Some(new_zoom) => {
            *zoom = new_zoom;
            log::line(format!("webview dpr {dpr} != window scale {scale}: zoom {new_zoom:.3}"));
            let _ = win.set_zoom(new_zoom);
            true
        }
        None => false,
    }
}

#[tauri::command]
fn open_url(url: String) {
```

**Edit `windows/src-tauri/src/lib.rs`:** find

```rust
            reposition,
```

replace with

```rust
            reposition,
            fit_zoom,
```

**Edit `windows/src/core/bridge.ts`:** find

```typescript
  reposition: () => call<void>("reposition"),
```

replace with

```typescript
  reposition: () => call<void>("reposition"),
  /** Corrects the webview's zoom when its pixel ratio is not the window's scale; true when it changed. */
  fitZoom: (dpr: number) => call<boolean>("fit_zoom", { dpr }),
```

**Edit `windows/src/island/island.ts`:** find

```typescript
const HIT_MARGIN = 14;
```

replace with

```typescript
const HIT_MARGIN = 14;

/** The width of the page in CSS px; the island is centred in it. It is PANEL_W unless the webview's zoom made the viewport narrower or wider than the window. */
function viewportWidth(): number {
  return window.innerWidth > 0 ? window.innerWidth : PANEL_W;
}
```

**Edit `windows/src/island/island.ts`:** find

```typescript
    const rect = { x: (PANEL_W - w) / 2, y: 0, w, h: hh };
    const p = this.pushedRect;
```

replace with

```typescript
    const rect = { x: (viewportWidth() - w) / 2, y: 0, w, h: hh };
    const p = this.pushedRect;
```

**Edit `windows/src/island/island.ts`:** find

```typescript
    return { x: (PANEL_W - w) / 2, y: 0, w, h: hh };
```

replace with

```typescript
    return { x: (viewportWidth() - w) / 2, y: 0, w, h: hh };
```

**Edit `windows/src/main.ts`:** find

```typescript
  void Sound.preload();

  const island = new Island(root);
```

replace with

```typescript
  void Sound.preload();

  // Before the island exists: its canvases size their bitmaps from the pixel ratio once, so a zoom correction has to land first (see `fit_zoom` in lib.rs).
  // If the zoom changed, wait until the ratio follows it, for 500 ms at most.
  const dprBefore = window.devicePixelRatio || 1;
  if (await Bridge.fitZoom(dprBefore)) {
    for (let i = 0; i < 20 && window.devicePixelRatio === dprBefore; i++) await new Promise((r) => setTimeout(r, 25));
  }

  const island = new Island(root);
```

**Edit `windows/src/main.ts`:** find

```typescript
  await onEvent<null>("screen-changed", () => { void Bridge.reposition(); desktop.screenChanged(); });
```

replace with

```typescript
  const checkZoom = () => Bridge.fitZoom(window.devicePixelRatio || 1);
  await onEvent<null>("screen-changed", async () => {
    await checkZoom();
    void Bridge.reposition();
    desktop.screenChanged();
  });
  // A change of the pixel ratio (the window moved to another display, text scaling changed) is a media query that stops matching.
  window.matchMedia(`(resolution: ${window.devicePixelRatio}dppx)`).addEventListener?.("change", () => void checkZoom());
  // Ctrl+wheel and Ctrl+plus/minus would zoom the island's page by themselves and undo the correction.
  window.addEventListener("wheel", (e) => { if (e.ctrlKey) e.preventDefault(); }, { passive: false });
  window.addEventListener("keydown", (e) => { if (e.ctrlKey && (e.key === "+" || e.key === "-" || e.key === "=" || e.key === "0")) e.preventDefault(); });
```

Two existing source pins read the lines this step changed. Update them (the dry run found both by running `check:cat`):

**Edit `windows/scripts/cat-tests/desktop-island.test.mjs`:** find

```javascript
  assert.match(m, /await onEvent<null>\("screen-changed", \(\) => \{ void Bridge\.reposition\(\); desktop\.screenChanged\(\); \}\);/);
```

replace with

```javascript
  assert.match(m, /await onEvent<null>\("screen-changed", async \(\) => \{\s*await checkZoom\(\);\s*void Bridge\.reposition\(\);\s*desktop\.screenChanged\(\);\s*\}\);/);
```

- [ ] **Step 4: Type check, the page tests, and the Rust build**

Run: `cd windows && npx --no-install tsc --noEmit && echo tsc ok && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"`
Expected: `tsc ok`; `ℹ fail 0`. Then `windows/scripts/cargo-linux.sh test --workspace --offline --target-dir /repo/windows/target/u1 2>&1 | grep -E "test result|error"` (needs Docker: the Tauri crate does not compile on the Mac). Expected: every `test result: ok`. Without Docker, say "Tauri build needs Docker" in the ledger: `set_zoom`, `inner_size` and `PhysicalPosition` are Tauri 2 API names copied from upstream's same-version change and are the one thing the dry run could not compile.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add windows/src-tauri/src/island.rs windows/src-tauri/src/lib.rs windows/src/core/bridge.ts windows/src/main.ts windows/src/island/island.ts windows/scripts/cat-tests/desktop-island.test.mjs
git commit -F - <<'EOF'
fix(windows): the webview's zoom follows the window's scale so the island is not clipped (upstream b9b9217, #467)

calculate_zoom_correction is pure and tested; fit_zoom runs at start, on a screen change and when the pixel ratio changes;
a clamped resize is asked once more; the island is centred in the real viewport width.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 5: Mac: the permission card's click guard

**Files:**
- Create: `NotchBuddy/Sources/App/ApprovalClickGuard.swift`, `tests/ApprovalClickGuardTests.swift`, `scripts/test-approval-click-guard.sh`
- Modify: `NotchBuddy/Sources/App/IslandTypes.swift`, `NotchBuddy/Sources/App/IslandViewContent.swift`, `scripts/test-u1-wiring.sh`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated by `xcodegen`)

**Interfaces:**
- Produces: `enum ApprovalClickGuard { static let window: TimeInterval; static var duration: Duration }` and `ApprovalInfo.token: UUID` (a new one per request; the memberwise initialiser keeps working because the field has a default).

The Mac has the same exposure upstream fixed on Windows (the survey's A4: "propose for Mac"; the owner approved). Design: the card's three buttons get `.allowsHitTesting(takesClicks)`; `takesClicks` is false from the moment a new request (a new `token`) appears and true after one `Task.sleep(600 ms)` in a `.task(id: approval?.token)`. No timer; a cancelled sleep (the request is replaced or the view goes away) leaves the buttons shut for the next run, which starts again. Nothing is drawn differently: `allowsHitTesting` changes no pixel, the dry run's before and after pictures of `render-approval-card.sh` are byte-identical (Step 6).

- [ ] **Step 1: Write the failing test and its script**

**Create `tests/ApprovalClickGuardTests.swift`:**

```swift
import Foundation

@main
enum ApprovalClickGuardTests {
    static func main() {
        var passed = 0
        func ok(_ cond: Bool, _ name: String) { precondition(cond, name); passed += 1; print("✓ \(name)") }
        ok(ApprovalClickGuard.window == 0.6, "the guard is 600 ms")
        ok(ApprovalClickGuard.duration == .milliseconds(600), "the sleep is 600 ms")
        ok(ApprovalClickGuard.window > 0.2 && ApprovalClickGuard.window < 1, "long enough to catch a stray click, short enough not to be felt")
        print("Approval click guard: \(passed) checks passed")
    }
}
```

**Create `scripts/test-approval-click-guard.sh`:**

```bash
#!/usr/bin/env bash
# The permission card's 600 ms click guard: the pure rule (ApprovalClickGuard.swift). Its call sites in ApprovalView are pinned by scripts/test-u1-wiring.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-approval-guard.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 NotchBuddy/Sources/App/ApprovalClickGuard.swift tests/ApprovalClickGuardTests.swift -o "$TEST_DIR/approval-guard-tests"
"$TEST_DIR/approval-guard-tests"
```

- [ ] **Step 2: Run it to see it fail**

Run: `chmod +x scripts/test-approval-click-guard.sh && bash -n scripts/test-approval-click-guard.sh && bash scripts/test-approval-click-guard.sh`
Expected: FAIL: `error: no such file or directory: 'NotchBuddy/Sources/App/ApprovalClickGuard.swift'`.

- [ ] **Step 3: The rule, the token, the card**

**Create `NotchBuddy/Sources/App/ApprovalClickGuard.swift`:**

```swift
import Foundation

// A fresh permission card ignores clicks for its first 600 ms. The card opens under a pointer that was busy with the window underneath, and a click meant for that window must not land on
// Allow, Always or Deny. Foundation only. The keyboard is not a click and is not guarded. `ApprovalView` waits `window` once per request (one `Task.sleep`: no timer) before its buttons take clicks.

enum ApprovalClickGuard {
    /// How long a new request's buttons ignore clicks (s).
    static let window: TimeInterval = 0.6

    /// The same, as a duration for `Task.sleep`.
    static var duration: Duration { .milliseconds(Int((window * 1000).rounded())) }
}
```

**Edit `NotchBuddy/Sources/App/IslandTypes.swift`:** find

```swift
    var target: String = ""
    var risk: String = ""
    var line: String = ""
}
```

replace with

```swift
    var target: String = ""
    var risk: String = ""
    var line: String = ""
    /// One per request (made when the request is built): the card's 600 ms click guard starts again for each new one (`ApprovalClickGuard`).
    var token = UUID()
}
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`:** find

```swift
struct ApprovalView: View {
    @ObservedObject var state: AppState

    var approval: ApprovalInfo? { state.pendingApproval }
```

replace with

```swift
struct ApprovalView: View {
    @ObservedObject var state: AppState
    /// False for the first 600 ms of each request: the buttons ignore clicks (`ApprovalClickGuard`), the keys and the look are as they were.
    @State private var takesClicks = false

    var approval: ApprovalInfo? { state.pendingApproval }
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`:** find

```swift
                    if approval?.pillId != "agent_codex" {
                        SecondaryButton("Always") {
                            HookServer.shared.sendApprovalDecision("always")
                        }
                    }
                }
            }
```

replace with

```swift
                    if approval?.pillId != "agent_codex" {
                        SecondaryButton("Always") {
                            HookServer.shared.sendApprovalDecision("always")
                        }
                    }
                }
                // A click meant for the window underneath must not land on a button: they take clicks only once the guard has run.
                .allowsHitTesting(takesClicks)
            }
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`:** find

```swift
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Question
```

replace with

```swift
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // One sleep per request, cancelled with the view or by the next request (a cancelled sleep leaves the buttons shut): no timer.
        .task(id: approval?.token) {
            takesClicks = false
            guard approval != nil else { return }
            do { try await Task.sleep(for: ApprovalClickGuard.duration) } catch { return }
            takesClicks = true
        }
    }
}

// MARK: - Question
```

- [ ] **Step 4: Run the rule's test and add the pins**

Run: `bash scripts/test-approval-click-guard.sh`
Expected: PASS: `Approval click guard: 3 checks passed`.

**Edit `scripts/test-u1-wiring.sh`:** find

```bash
echo "$pass passed, $fail failed"
```

replace with

```bash
# The permission card's click guard.
has   "the buttons take clicks only after the guard" IslandViewContent.swift ".allowsHitTesting(takesClicks)"
has   "one sleep per request"                   IslandViewContent.swift ".task(id: approval?.token)"
has   "the guard's own duration"                IslandViewContent.swift "Task.sleep(for: ApprovalClickGuard.duration)"
has   "a request carries its token"             IslandTypes.swift "var token = UUID()"

echo "$pass passed, $fail failed"
```

Run: `bash scripts/test-u1-wiring.sh`
Expected: PASS: `6 passed, 0 failed` (two crash-fix lines and the four guard lines).

- [ ] **Step 5: Build (a new file: xcodegen first) and run the neighbours**

```bash
cd NotchBuddy && xcodegen > /dev/null && cd ..
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"
bash scripts/test-island-wing-wiring.sh 2>&1 | tail -1
```

Expected: `** BUILD SUCCEEDED **`; `All tests passed.`

- [ ] **Step 6: The look did not change**

Run twice, once on the base (`git stash` is not allowed: use a second `git worktree` of `notchmeow/rebrand` in `${TMPDIR:-/tmp}/u1-base`, then `git worktree remove` it by its literal path) and once here: `bash scripts/render-approval-card.sh --out ${TMPDIR:-/tmp}/u1/card-base.png` and `... card-guard.png` (each about seven minutes: run them in the background), then `cmp ${TMPDIR:-/tmp}/u1/card-base.png ${TMPDIR:-/tmp}/u1/card-guard.png && echo identical`.
Expected: `identical`. (The dry run could not afford the base render and instead pinned the claim in the source: a `.allowsHitTesting` modifier on a stack changes no drawing. Do the render if the machine is free; say in the ledger which you did.)

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add NotchBuddy/Sources/App/ApprovalClickGuard.swift NotchBuddy/Sources/App/IslandTypes.swift NotchBuddy/Sources/App/IslandViewContent.swift tests/ApprovalClickGuardTests.swift scripts/test-approval-click-guard.sh scripts/test-u1-wiring.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F - <<'EOF'
feat(mac): a fresh permission card ignores clicks for 600 ms (upstream 5b06e1c, here for the Mac)

One Task.sleep per request; the buttons take clicks only after it. No timer, no change to what is drawn.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 6: Mac: question cards show option descriptions, and the picture

**Files:**
- Create: `scripts/render-question-card.swift`, `scripts/render-question-card.sh`
- Modify: `NotchBuddy/Sources/App/AskQuestion.swift`, `AppState.swift`, `IslandViewContent.swift`, `IslandWindowController.swift`, `tests/AskQuestionTests.swift`, `scripts/test-u1-wiring.sh`

**Interfaces:**
- Produces: `AskQuestionItem.hasDescriptions: Bool`, `AskQuestion.estimatedIslandHeight: CGFloat?` (nil when no option of any question has a description; otherwise 160 to 560), `enum QuestionLayout { nonisolated(unsafe) static var height: CGFloat? }` (written by `AppState.pendingQuestion`'s `didSet`, read by `islandSize`).
- Consumes: nothing from earlier tasks.

Upstream 52b1562 (#249), changed in two ways the owner's rules need (owner's answers 1 and 2): (a) **only a card with descriptions changes**; upstream also grew the island and wrapped the question for cards without descriptions, which would restyle the chips card; (b) the panel goes from 320 to 560 pt as upstream did (the island is glued to the panel's top and the panel passes the mouse on outside the island rect, `pollFrame`'s `ignoresMouseEvents`, so the extra transparent height takes no clicks).

- [ ] **Step 1: Write the failing tests**

**Edit `tests/AskQuestionTests.swift`:** find

```swift
        // ── finish ─────────────────────────────────────────────────────────────
```

replace with

```swift
        // ── option descriptions and the island's height ────────────────────────
        print("\nOption descriptions")
        let plain: [String: Any] = ["questions": [
            ["question": "Which search engine?", "header": "Search", "options": [["label": "A"], ["label": "B", "description": ""], ["label": "C"]], "multiSelect": false]
        ]]
        let plainQ = AskQuestion.parse(toolInput: plain)!
        checkTrue("no description anywhere: hasDescriptions is false",   plainQ.questions[0].hasDescriptions == false)
        checkTrue("no description: the island keeps its usual height (nil)", plainQ.estimatedIslandHeight == nil)
        checkTrue("one description is enough",                           parsed!.questions[0].hasDescriptions)
        let h1 = parsed!.estimatedIslandHeight
        checkTrue("descriptions: a height is asked for",                 h1 != nil)
        checkTrue("descriptions: at least the usual 160 pt",             (h1 ?? 0) >= 160)
        checkTrue("descriptions: three options need room (over 200 pt)", (h1 ?? 0) > 200)
        let longText = String(repeating: "word ", count: 200)
        let big: [String: Any] = ["questions": [
            ["question": longText, "header": "H", "options": [
                ["label": "A", "description": longText], ["label": "B", "description": longText],
                ["label": "C", "description": longText], ["label": "D", "description": longText]], "multiSelect": true]
        ]]
        checkTrue("a huge question is capped at 560 pt",                  AskQuestion.parse(toolInput: big)!.estimatedIslandHeight == 560)
        // Two questions: the island is the height of the tallest, so it does not change from one to the next.
        let shortQ: [String: Any] = ["question": "Q?", "header": "", "options": [["label": "A", "description": "a"], ["label": "B", "description": "b"]], "multiSelect": false]
        let tallQ = (big["questions"] as! [[String: Any]])[0]
        let both = AskQuestion.parse(toolInput: ["questions": [shortQ, tallQ]])!
        checkTrue("several questions: the tallest decides",               both.estimatedIslandHeight == 560)
        checkTrue("QuestionLayout starts empty",                          QuestionLayout.height == nil)

        // ── finish ─────────────────────────────────────────────────────────────
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash scripts/test-ask-question.sh 2>&1 | tail -4`
Expected: FAIL: a compile error, `value of type 'AskQuestionItem' has no member 'hasDescriptions'`.

- [ ] **Step 3: The model**

**Edit `NotchBuddy/Sources/App/AskQuestion.swift`:** find

```swift
struct AskQuestion: Equatable {
    var questions: [AskQuestionItem]   // 1–4 questions
```

replace with

```swift
/// The island's height for the pending question, read by the nonisolated `islandSize`. Written on the main actor only (`AppState.pendingQuestion`'s `didSet`); nil means the card keeps
/// the island's usual height. Only a question with option descriptions sets it.
enum QuestionLayout {
    nonisolated(unsafe) static var height: CGFloat?
}

extension AskQuestionItem {
    /// True when at least one option carries a description: the card then lists the options one under the other, each with its description. Without one the card is as it always was.
    var hasDescriptions: Bool { options.contains { !$0.description.isEmpty } }
}

struct AskQuestion: Equatable {
    var questions: [AskQuestionItem]   // 1–4 questions

    /// The smallest island that shows every question of this card, and nil when none of them has an option description (that card keeps the island's usual 160 pt, chips and all). A rough
    /// estimate (text wraps at about 500 pt), from 160 pt up to 560 pt, taken for the tallest question so the island does not change height from one question to the next.
    var estimatedIslandHeight: CGFloat? {
        guard questions.contains(where: \.hasDescriptions) else { return nil }
        func lines(_ text: String, charWidth: CGFloat) -> CGFloat {
            max(1, (CGFloat(text.count) * charWidth / 500).rounded(.up))
        }
        let tallest = questions.map { item -> CGFloat in
            var h: CGFloat = 20 + lines(item.question, charWidth: 7) * 17 + 64
            if !item.header.isEmpty { h += 14 }
            if item.hasDescriptions {
                for opt in item.options { h += 34 + (opt.description.isEmpty ? 0 : lines(opt.description, charWidth: 6.4) * 14) }
                h += 40   // the "Other…" row
            } else {
                h += item.options.count >= 3 ? 74 : 40
            }
            if item.multiSelect { h += 34 }
            return h
        }.max() ?? 160
        return min(max(tallest, 160), 560)
    }
```

- [ ] **Step 4: Run the tests**

Run: `bash scripts/test-ask-question.sh 2>&1 | tail -14`
Expected: PASS: the old checks and the nine new ones, `All tests passed.`

- [ ] **Step 5: The state, the island's size, the panel, the card**

**Edit `NotchBuddy/Sources/App/AppState.swift`:** find

```swift
    @Published var pendingQuestion: AskQuestion? = nil
```

replace with

```swift
    @Published var pendingQuestion: AskQuestion? = nil {
        didSet { QuestionLayout.height = pendingQuestion?.estimatedIslandHeight }
    }
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`:** find

```swift
        let layout = IslandConst.viewLayouts[view]!
        return (IslandConst.expandedWidth, layout.height)
    }
}
```

replace with

```swift
        let layout = IslandConst.viewLayouts[view]!
        if view == .question, let h = QuestionLayout.height { return (IslandConst.expandedWidth, h) }   // a question with option descriptions needs more room
        return (IslandConst.expandedWidth, layout.height)
    }
}
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`:** find

```swift
        let panelW: CGFloat = 720
        let panelH: CGFloat = 320
```

replace with

```swift
        let panelW: CGFloat = 720
        let panelH: CGFloat = 560   // room for the tallest question card (QuestionLayout, 560 pt); the island is glued to the top and the panel passes the mouse on outside it
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`:** find

```swift
                    Text(item.question)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(2)
```

replace with

```swift
                    // With option descriptions the whole question shows (the card is taller then, `QuestionLayout`); without them it is cut at two lines as it always was.
                    Text(item.question)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(item.hasDescriptions ? nil : 2)
                        .fixedSize(horizontal: false, vertical: item.hasDescriptions)
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`:** find

```swift
                    } else {
                        ChipFlowLayout(spacing: 6) {
                            ForEach(Array(item.options.enumerated()), id: \.offset) { idx, opt in
                                let isSelected = curSel.contains(opt.label)
                                if isMulti {
```

replace with

```swift
                    } else if item.hasDescriptions {
                        // Each option on its own row, its description under the label.
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(item.options.enumerated()), id: \.offset) { idx, opt in
                                let isSelected = curSel.contains(opt.label)
                                Button {
                                    if isMulti {
                                        toggleSelection(qi: qi, label: opt.label)
                                    } else {
                                        selectAndProceed(q: q, qi: qi, label: opt.label, isLast: isLast)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(opt.label)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(isSelected ? Color(hex: "#67E8F9") : Color(hex: "#F5F6F8"))
                                        if !opt.description.isEmpty {
                                            Text(opt.description)
                                                .font(.system(size: 11))
                                                .foregroundColor(Color(hex: "#9AA0A8"))
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(isSelected ? Color(hex: "#22D3EE").opacity(0.22) : Color.white.opacity(0.07))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color(hex: "#22D3EE").opacity(0.55) : Color.white.opacity(0.1), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .keyboardShortcut(KeyEquivalent(Character(String(idx + 1))), modifiers: [])
                            }
                            SecondaryButton("Other…") {
                                if qi < showOther.count { showOther[qi] = true }
                            }
                        }
                    } else {
                        ChipFlowLayout(spacing: 6) {
                            ForEach(Array(item.options.enumerated()), id: \.offset) { idx, opt in
                                let isSelected = curSel.contains(opt.label)
                                if isMulti {
```

- [ ] **Step 6: The pins**

**Edit `scripts/test-u1-wiring.sh`:** find

```bash
echo "$pass passed, $fail failed"
```

replace with

```bash
# The question card: descriptions, and the island's height.
has   "descriptions list the options"           IslandViewContent.swift "} else if item.hasDescriptions {"
has   "the island follows the question"         IslandWindowController.swift "if view == .question, let h = QuestionLayout.height"
has   "the height is written with the question" AppState.swift "QuestionLayout.height = pendingQuestion?.estimatedIslandHeight"
has   "the panel is tall enough"                IslandWindowController.swift "let panelH: CGFloat = 560"

echo "$pass passed, $fail failed"
```

Run: `bash scripts/test-u1-wiring.sh`
Expected: PASS: `10 passed, 0 failed` (the crash fix 2, the guard 4, the question card 4).

- [ ] **Step 7: The two pictures (the owner's checkpoint)**

**Create `scripts/render-question-card.swift`:**

```swift
import AppKit
import SwiftUI

// Draws the question card of the island (QuestionView, in IslandViewContent.swift) into a PNG without launching NotchMeow: the card's own SwiftUI view in a window that is never shown, on the
// app's own AppState with a made-up AskUserQuestion in it, inside a black island of the size `islandSize` gives that question (so a card with option descriptions is as tall as the app makes it).
//   bash scripts/render-question-card.sh --out question-card.png [--scale 2] [--plain]
// `--plain` draws a question with no option descriptions: the card as it always was (160 pt, chips). Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift.

@main
struct RenderQuestionCard {
    @MainActor static func main() {
        var out = "question-card.png", scale = 2.0, plain = false
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? out
            case "--scale": scale = Double(it.next() ?? "") ?? scale
            case "--plain": plain = true
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        let options: [[String: Any]] = plain
            ? [["label": "Postgres"], ["label": "Meilisearch"], ["label": "Algolia"]]
            : [["label": "Postgres full-text", "description": "Built in, nothing new to run. Good enough up to a few hundred thousand rows."],
               ["label": "Meilisearch", "description": "A small separate server with typo tolerance and instant results. One more service to keep running."],
               ["label": "Algolia", "description": "Hosted and fast, priced per request. The least to operate and the most to pay."]]
        let input: [String: Any] = ["questions": [["question": "Which search engine should the new catalogue page use, given that the data fits on one machine and the team is two people?",
                                                   "header": "Search", "options": options, "multiSelect": false]]]
        _ = NSApplication.shared
        let state = AppState.shared
        let task = AgentTask(id: "integration_claude", name: "Claude Code", color: "#E07950", state: .question, steps: [], source: .claudeCode)
        state.tasks = [task]
        state.focusId = task.id
        state.pendingQuestion = AskQuestion.parse(toolInput: input)

        let (islandW, islandH) = islandSize(mode: .expanded, view: .question)
        let island = ZStack(alignment: .topLeading) {
            Color.black
            QuestionView(state: state).frame(width: Double(islandW) - 20, height: Double(islandH) - 62).offset(x: 10, y: 42)
        }
        .frame(width: islandW, height: islandH, alignment: .topLeading)
        .foregroundColor(Color(hex: "#F5F6F8"))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: IslandConst.expandedCorner, bottomTrailingRadius: IslandConst.expandedCorner))
        let host = NSHostingView(rootView: island)
        host.frame = NSRect(x: 0, y: 0, width: islandW, height: islandH)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((Double(islandW) * scale).rounded()), pixelsHigh: Int((Double(islandH) * scale).rounded()), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        do { try png.write(to: URL(fileURLWithPath: out)) } catch { FileHandle.standardError.write(Data("cannot write \(out)\n".utf8)); exit(1) }
        print("wrote \(out) (island \(Int(islandW)) x \(Int(islandH)) pt, \(plain ? "no descriptions" : "with descriptions"))")
        // The tool's own AppState saved a few defaults into the tool's domain: the .sh deletes them.
    }
}
```

**Create `scripts/render-question-card.sh`:**

```bash
#!/usr/bin/env bash
# Draws the island's question card (QuestionView) with made-up option descriptions into a PNG, without launching NotchMeow (see scripts/render-question-card.swift).
#   bash scripts/render-question-card.sh --out question-card.png [--scale 2] [--plain]
# ApprovalView-style: QuestionView reads the app's AppState, so this compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about two minutes. It runs in a home folder of
# its own through scripts/render-home-guard.sh, which kills it if it ever opens the real ~/.claude, ~/.gemini or ~/.codex. It touches no preferences.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-question-card.XXXXXX")"
REAL_HOME="$HOME"
cleanup() {
    rm -rf "$BUILD_DIR"
    defaults delete render-question-card > /dev/null 2>&1 || true
    rm -f "$REAL_HOME/Library/Preferences/render-question-card.plist"
}
trap cleanup EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$BUILD_DIR/home"
APP=NotchBuddy/Sources/App
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$APP" -name '*.swift' ! -name NotchBuddyApp.swift | sort)
swiftc -swift-version 6 -suppress-warnings "${FILES[@]}" scripts/render-question-card.swift -o "$BUILD_DIR/render-question-card"
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/render-question-card" "$@"
```

```bash
chmod +x scripts/render-question-card.sh && bash -n scripts/render-question-card.sh
mkdir -p ${TMPDIR:-/tmp}/u1 .claude/checkpoints/u1
bash scripts/render-question-card.sh --out ${TMPDIR:-/tmp}/u1/question-desc.png          # about seven minutes: run it in the background
bash scripts/render-question-card.sh --out ${TMPDIR:-/tmp}/u1/question-plain.png --plain
```

Expected: `wrote …question-desc.png (island 640 x 330 pt, with descriptions)` and `wrote …question-plain.png (island 640 x 160 pt, no descriptions)`. Open both and say what you see. **With descriptions** (dry run): the whole two-line question, three bordered rows each with its label and its grey description (one wraps), and the "Other…" button, all inside a 330 pt island with nothing cut. **Plain:** the chips card at 160 pt, as it ships. Copy both into `.claude/checkpoints/u1/`. If anything is cut at the bottom, raise the estimate's constants in `estimatedIslandHeight` (a line is `charWidth * count / 500` wide, 14 or 17 pt tall) and say so.

- [ ] **Step 8: Build (new script files need no xcodegen) and the neighbours**

```bash
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"
bash scripts/test-island-wing-wiring.sh 2>&1 | tail -1
bash scripts/test-cat-wiring.sh 2>&1 | tail -1
```

Expected: `** BUILD SUCCEEDED **`; `All tests passed.` twice. **Stop here and report to the main session** (the checkpoint): the two pictures and the question "is this card what you meant?".

- [ ] **Step 9: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add NotchBuddy/Sources/App/AskQuestion.swift NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/IslandViewContent.swift NotchBuddy/Sources/App/IslandWindowController.swift tests/AskQuestionTests.swift scripts/test-u1-wiring.sh scripts/render-question-card.swift scripts/render-question-card.sh
git commit -F - <<'EOF'
feat(mac): question cards show each option's description (upstream 52b1562, #249)

Only a question with at least one option description changes: the whole question, the options one under the other, and an island
that grows to fit (160 to 560 pt; the transparent panel is 560 pt tall). A question without descriptions is as it shipped.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 7: Open on hover (Mac and Windows/Linux), and Close after

**Files:**
- Create: `tests/IslandHoverTests.swift`, `scripts/test-island-hover.sh`, `windows/scripts/cat-tests/fsm-hover.test.mjs`
- Modify: `NotchBuddy/Sources/App/IslandStateMachine.swift`, `IslandWindowController.swift`, `AppState.swift`, `SettingsView.swift`, `scripts/test-u1-wiring.sh`, `windows/src/island/fsm.ts`, `windows/src/island/island.ts`, `windows/src/core/state.ts`, `windows/src/settings/main.ts`, `windows/src-tauri/src/settings.rs`, `windows/scripts/cat-tests/sleep.test.mjs` (one source pin)

**Interfaces:**
- Produces (Mac): `IslandStateMachine.openOnHover: Bool`, `hoverCloseDelay: TimeInterval = 0.6`, `openedByHover: Bool { get }`, `userInteracted()`; `AppState.openOnHover` (key `openOnHover`). (Windows) the same names on `fsm.ts`, `Settings.openOnHover`, Rust `Settings.open_on_hover`.

Upstream 0ad1b1d (Mac) and 2261334 (Windows/Linux). **The owner's answer: it opens after a 150 ms dwell** (not at once, as upstream): the usual hover peek happens immediately as it always did, and a second, one-shot timer (`hoverDwell`, 0.15 s) opens the island if the pointer is still over it; `mouseLeft`, a collapse, an alert, a pin or a waiting card cancel it. **It respects the wing and costs nothing hidden, and the plan proves it two ways:** the open decision is made in the state machine from `mouseEntered`, which `pollFrame` calls only for `inIsland`, and `inIsland` already excludes the wing (`hoverRect.contains(local) && !wing.passThrough`; Task 7 keeps that line and pins it); the only timers it adds are the dwell (150 ms, one per hover, none while the pointer is away) and the hover-close `DispatchWorkItem` (0.6 s, one-shot, the state machine's own `homeCollapseWork`). The Mac test arms the dwell through `armHoverOpen`, which it replaces with a clock it turns by hand, so 149 ms and 150 ms are told apart exactly. The poll's pointer bookkeeping moves before the state machine is told (upstream's `previouslyInIsland` fix), so an island that opens on the hover does not start folding at once. NotchMeow's `wasInIsland = inIsland || wardrobeMenuOpen` keeps its meaning.

Found in the dry run: `IslandWindowController` never sets `fsm.homeToPetitDelay` from `state.autoCloseInterval` (upstream has `autoCloseSubscription`; NotchMeow lost it), so Settings → "Close after" does nothing to the fold delay. Step 5 wires it (owner's answer 8).

- [ ] **Step 1: The Mac state machine's test, first**

**Create `tests/IslandHoverTests.swift`:**

```swift
import Foundation

// Open on hover (Settings → General → Behavior): the state machine's rules. The dwell before the island opens is armed through `armHoverOpen`, which these tests replace with a clock they turn
// by hand, so 149 ms and 150 ms can be told apart exactly; the fold after the pointer leaves uses real, short timers. The Windows and Linux twin is windows/scripts/cat-tests/fsm-hover.test.mjs.

/// A clock for the dwell timer: items armed with a delay run when `advance` reaches their time (a cancelled item does not run).
@MainActor
final class HoverClock {
    var now: TimeInterval = 0
    private var items: [(at: TimeInterval, item: DispatchWorkItem)] = []
    var armed: Int { items.filter { !$0.item.isCancelled }.count }
    func arm(_ delay: TimeInterval, _ item: DispatchWorkItem) { items.append((now + delay, item)) }
    func advance(ms: Int) {
        let end = now + Double(ms) / 1000
        for entry in items.sorted(by: { $0.at < $1.at }) where entry.at <= end + 1e-9 { entry.item.perform() }
        items.removeAll { $0.at <= end + 1e-9 }
        now = end
    }
}

@main
enum IslandHoverTests {
    @MainActor
    static func main() async throws {
        var passed = 0
        func ok(_ cond: Bool, _ name: String) { precondition(cond, name); passed += 1; print("✓ \(name)") }

        // Off (the default): hovering only peeks, as before, and arms nothing.
        let (off, offClock) = machine(on: false)
        off.mouseEntered()
        offClock.advance(ms: 1000)
        ok(off.state == .petit && !off.openedByHover && offClock.armed == 0, "open on hover off: hovering only peeks and arms no timer")

        // The dwell: 150 ms by default, 149 ms is not enough, 150 ms opens.
        ok(IslandStateMachine().hoverDwell == 0.15, "the dwell is 150 ms")
        let (a, ac) = machine()
        a.mouseEntered()
        ok(a.state == .petit && ac.armed == 1, "hover peeks at once and arms exactly one dwell timer")
        ac.advance(ms: 149)
        ok(a.state == .petit && !a.openedByHover, "149 ms over the island: no open")
        ac.advance(ms: 1)
        ok(a.state == .home && a.openedByHover, "150 ms over the island: it opens")
        ok(ac.armed == 0, "no timer is left armed once it has opened")

        // Leaving before the dwell is over cancels the open (and leaves the usual peek alone).
        let (b, bc) = machine()
        b.mouseEntered()
        bc.advance(ms: 100)
        b.mouseLeft()
        ok(bc.armed == 0, "leaving at 100 ms cancels the dwell timer")
        bc.advance(ms: 500)
        ok(b.state == .petit && !b.openedByHover, "leaving at 100 ms: the island never opens")

        // Coming back starts the dwell again from zero.
        b.mouseEntered()
        bc.advance(ms: 149)
        ok(b.state == .petit, "a new hover starts a new dwell (149 ms: no open)")
        bc.advance(ms: 1)
        ok(b.state == .home, "a new hover opens after its own 150 ms")

        // The fold: leaving a hover-opened island folds it after the short grace period (real timers, made short).
        let (c, cc) = machine()
        c.hoverCloseDelay = 0.08
        c.mouseEntered(); cc.advance(ms: 150)
        ok(c.state == .home, "hover-opened")
        c.mouseLeft()
        try await Task.sleep(for: .milliseconds(20))
        ok(c.state == .home, "it does not fold at once")
        try await waitFor(.petit, c, timeout: 1)
        ok(!c.openedByHover, "folded, no longer hover-opened")

        // Coming back before the grace period keeps it open.
        let (d, dc) = machine()
        d.hoverCloseDelay = 0.08
        d.mouseEntered(); dc.advance(ms: 150)
        d.mouseLeft()
        d.mouseEntered()
        try await Task.sleep(for: .milliseconds(150))
        ok(d.state == .home, "coming back before the grace period keeps it open")

        // A click inside turns it into a normal open island: the auto-close delay applies.
        let (e, ec) = machine()
        e.homeToPetitDelay = 0.4
        e.mouseEntered(); ec.advance(ms: 150)
        e.userInteracted()
        e.mouseLeft()
        try await Task.sleep(for: .milliseconds(150))
        ok(e.state == .home, "after a click the short delay no longer applies")
        try await waitFor(.petit, e, timeout: 1)
        ok(e.state == .petit, "after a click the normal auto-close applies")

        // A waiting card holds the island: hover opens it as an ordinary island, never arms the dwell, never folds it.
        let (f, fc) = machine()
        f.isHeldOpen = { true }
        f.mouseEntered()
        ok(f.state == .home && !f.openedByHover && fc.armed == 0, "a waiting card: hover opens it as an ordinary open island and arms no dwell")
        f.mouseLeft()
        try await Task.sleep(for: .milliseconds(150))
        ok(f.state == .home, "a waiting card: the island does not fold")

        // A card that arrives during the dwell stops the dwell from opening anything.
        let (g, gc) = machine()
        g.mouseEntered()
        g.isHeldOpen = { true }
        gc.advance(ms: 150)
        ok(g.state == .petit, "a card that holds the island during the dwell: the dwell opens nothing")

        // An island opened by an alert keeps the normal delay even with hover on.
        let (h, hc) = machine()
        h.homeToPetitDelay = 0.4
        h.openedExternally()
        h.mouseEntered()
        ok(hc.armed == 0, "an island that is already open arms no dwell")
        h.mouseLeft()
        try await Task.sleep(for: .milliseconds(150))
        ok(h.state == .home, "an alert-opened island keeps the normal delay")

        // From a hidden island the same dwell opens it, and an alert during the dwell cancels it.
        let (i, ic) = machine()
        i.mouseEntered()
        i.openedExternally()
        ic.advance(ms: 150)
        ok(i.state == .home && !i.openedByHover, "an alert during the dwell wins: it is not a hover-opened island")

        print("Island open on hover: \(passed) checks passed")
    }

    @MainActor
    private static func machine(on: Bool = true) -> (IslandStateMachine, HoverClock) {
        let m = IslandStateMachine()
        let clock = HoverClock()
        m.openOnHover = on
        m.hoverCloseDelay = 0.08
        m.armHoverOpen = { delay, item in clock.arm(delay, item) }
        return (m, clock)
    }

    @MainActor
    private static func waitFor(_ s: IslandStateMachine.State, _ m: IslandStateMachine, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while m.state != s && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        precondition(m.state == s, "state \(m.state) after \(timeout) s, expected \(s)")
    }
}
```

**Create `scripts/test-island-hover.sh`:**

```bash
#!/usr/bin/env bash
# Open on hover: IslandStateMachine's rules with short real timers (the pure state machine only, no AppKit).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-island-hover.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/IslandStateMachine.swift tests/IslandHoverTests.swift -o "$TEST_DIR/island-hover-tests"
"$TEST_DIR/island-hover-tests"
```

Run: `chmod +x scripts/test-island-hover.sh && bash -n scripts/test-island-hover.sh && bash scripts/test-island-hover.sh 2>&1 | tail -3`
Expected: FAIL: a compile error, `value of type 'IslandStateMachine' has no member 'openOnHover'`.

- [ ] **Step 2: The state machine**

**Edit `NotchBuddy/Sources/App/IslandStateMachine.swift`:** find

```swift
    /// notchmeow → petit delay when mouse is hovering over the greeting.
    var greetHoverCollapseDelay: TimeInterval = 10
```

replace with

```swift
    /// notchmeow → petit delay when mouse is hovering over the greeting.
    var greetHoverCollapseDelay: TimeInterval = 10

    /// Opt-in (Settings → General → Behavior): hovering the island opens it, and an island opened that way folds shortly after the pointer leaves. Off: hover only peeks (petit).
    var openOnHover = false
    /// The pointer must stay over the island this long (s) before Open on hover opens it; leaving earlier cancels it. The usual hover peek is not delayed.
    var hoverDwell: TimeInterval = 0.15
    /// How the dwell timer is armed: one one-shot `DispatchWorkItem` per hover. A test replaces it with a clock it turns by hand.
    var armHoverOpen: (TimeInterval, DispatchWorkItem) -> Void = { delay, item in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item) }
    private var hoverOpenWork: DispatchWorkItem?
    /// Grace period after the pointer leaves a hover-opened island (no flicker at the edge).
    var hoverCloseDelay: TimeInterval = 0.6
    /// True while the island is open because of a hover, until the user clicks inside it.
    private(set) var openedByHover = false
```

**Edit `NotchBuddy/Sources/App/IslandStateMachine.swift`:** find

```swift
            scheduleGreetCollapse(delay: greetHoverCollapseDelay)
        }
    }
```

replace with

```swift
            scheduleGreetCollapse(delay: greetHoverCollapseDelay)
        }
        // Open on hover: the island opens once the pointer has stayed `hoverDwell`. Not while a card holds it (the switch above already opened it as an ordinary open island).
        if openOnHover, state == .hidden || state == .petit, isHeldOpen?() != true { scheduleHoverOpen() }
    }

    private func scheduleHoverOpen() {
        hoverOpenWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .hidden || self.state == .petit, self.isHeldOpen?() != true else { return }
            self.cancelTimers()
            self.openedByHover = true
            self.transition(to: .home)
        }
        hoverOpenWork = item
        armHoverOpen(hoverDwell, item)
    }
```

**Edit `NotchBuddy/Sources/App/IslandStateMachine.swift`:** find

```swift
    func mouseLeft() {
        switch state {
```

replace with

```swift
    func mouseLeft() {
        hoverOpenWork?.cancel(); hoverOpenWork = nil   // leaving before the dwell is over cancels the open
        switch state {
```

**Edit `NotchBuddy/Sources/App/IslandStateMachine.swift`:** find

```swift
        greetCollapseWork?.cancel(); greetCollapseWork = nil
    }
```

replace with

```swift
        greetCollapseWork?.cancel(); greetCollapseWork = nil
        hoverOpenWork?.cancel(); hoverOpenWork = nil
    }
```

**Edit `NotchBuddy/Sources/App/IslandStateMachine.swift`:** find

```swift
    func click() {
        guard state == .petit || state == .hidden else { return }
```

replace with

```swift
    func click() {
        openedByHover = false
        guard state == .petit || state == .hidden else { return }
```

**Edit `NotchBuddy/Sources/App/IslandStateMachine.swift`:** find

```swift
    func openedExternally() {
        cancelTimers()
        guard state != .home
```

replace with

```swift
    func openedExternally() {
        cancelTimers()
        openedByHover = false
        guard state != .home
```

**Edit `NotchBuddy/Sources/App/IslandStateMachine.swift`:** find

```swift
    func collapse() {
        guard state == .home || state == .hello else { return }
```

replace with

```swift
    func collapse() {
        openedByHover = false
        guard state == .home || state == .hello else { return }
```

**Edit `NotchBuddy/Sources/App/IslandStateMachine.swift`:** find

```swift
            guard let self, self.state == .home, !(self.isHeldOpen?() ?? false) else { return }
            self.transition(to: .petit)
        }
        homeCollapseWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + homeToPetitDelay, execute: item)
    }
```

replace with

```swift
            guard let self, self.state == .home, !(self.isHeldOpen?() ?? false) else { return }
            self.openedByHover = false
            self.transition(to: .petit)
        }
        homeCollapseWork = item
        let delay = openedByHover ? hoverCloseDelay : homeToPetitDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// The user clicked inside the island: a hover-opened island now stays like any open island (the normal auto-close) instead of folding as soon as the pointer leaves.
    func userInteracted() {
        openedByHover = false
    }
```

- [ ] **Step 3: Run the test**

Run: `bash scripts/test-island-hover.sh 2>&1 | tail -15`
Expected: PASS: twenty-two `✓` lines and `Island open on hover: 22 checks passed` (among them `149 ms over the island: no open`, `150 ms over the island: it opens`, `leaving at 100 ms cancels the dwell timer`).

- [ ] **Step 4: The setting, the poll, the click, the Settings row**

**Edit `NotchBuddy/Sources/App/AppState.swift`:** find

```swift
    @Published var autoCloseInterval: TimeInterval = 15 {
```

replace with

```swift
    // Hovering the island opens it (it folds 0.6 s after the pointer leaves) — persisted, off by default
    @Published var openOnHover: Bool = false {
        didSet { UserDefaults.standard.set(openOnHover, forKey: "openOnHover") }
    }
    @Published var autoCloseInterval: TimeInterval = 15 {
```

**Edit `NotchBuddy/Sources/App/AppState.swift`:** find

```swift
        if let v = ud.object(forKey: "autoCloseInterval") as? Double {
```

replace with

```swift
        if let v = ud.object(forKey: "openOnHover") as? Bool { openOnHover = v }
        if let v = ud.object(forKey: "autoCloseInterval") as? Double {
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`:** find

```swift
    private var modeSubscription: AnyCancellable?
```

replace with

```swift
    private var modeSubscription: AnyCancellable?
    private var openOnHoverSubscription: AnyCancellable?
    private var autoCloseSubscription: AnyCancellable?
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`:** find

```swift
        fsm.isHeldOpen = { AppState.shared.pendingApproval != nil || AppState.shared.shelfHoldsIsland }
        #endif
    }
```

replace with

```swift
        fsm.isHeldOpen = { AppState.shared.pendingApproval != nil || AppState.shared.shelfHoldsIsland }
        #endif
        // Settings → General → Behavior → Open on hover (off by default).
        fsm.openOnHover = state.openOnHover
        openOnHoverSubscription = state.$openOnHover.sink { [weak self] on in self?.fsm.openOnHover = on }
        // Settings → General → Behavior → Close after: the open island's fold delay.
        autoCloseSubscription = state.$autoCloseInterval.sink { [weak self] delay in self?.fsm.homeToPetitDelay = delay }
    }
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`:** find

```swift
        // Feed FSM hover enter/leave
        if inIsland && !wasInIsland {
            guard !inAttachDrag else { wasInIsland = inIsland; return }
```

replace with

```swift
        // Feed FSM hover enter/leave. The pointer is recorded before the state machine hears of it: a transition it makes right away (Open on hover) reads `wasInIsland`,
        // and must not see the pointer as still outside, or the island would start folding the moment it opened.
        let previouslyInIsland = wasInIsland
        wasInIsland = inIsland || wardrobeMenuOpen
        if inIsland && !previouslyInIsland {
            guard !inAttachDrag else { return }
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`:** find

```swift
        if !inIsland && wasInIsland && !wardrobeMenuOpen {   // the Wardrobe menu is up: the pointer is on it, and the island stays open under it
            fsm.mouseLeft()
        }
        wasInIsland = inIsland || wardrobeMenuOpen
```

replace with

```swift
        if !inIsland && previouslyInIsland && !wardrobeMenuOpen {   // the Wardrobe menu is up: the pointer is on it, and the island stays open under it
            fsm.mouseLeft()
        }
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`:** find

```swift
                guard self.wasInIsland && !self.wardrobeMenuOpen else { return }   // a press on the Wardrobe menu is not a click on the island
                CatSleepClock.shared.wake("click")   // a click wakes a sleeping cat
```

replace with

```swift
                guard self.wasInIsland && !self.wardrobeMenuOpen else { return }   // a press on the Wardrobe menu is not a click on the island
                self.fsm.userInteracted()            // a click makes a hover-opened island an ordinary open one
                CatSleepClock.shared.wake("click")   // a click wakes a sleeping cat
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`:** find

```swift
        GroupBox("Behavior") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Close after")
```

replace with

```swift
        GroupBox("Behavior") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Open on hover", isOn: $state.openOnHover)
                    .help("Hovering the island opens it; it folds again shortly after the pointer leaves. Click inside to keep it open.")
                HStack(spacing: 8) {
                    Text("Close after")
```

- [ ] **Step 5: The pins, and the neighbours**

**Edit `scripts/test-u1-wiring.sh`:** find

```bash
echo "$pass passed, $fail failed"
```

replace with

```bash
# Open on hover: the state machine is fed by the poll, which already honours the wing and the 0 % rule.
has   "the setting reaches the state machine"   IslandWindowController.swift "fsm.openOnHover = state.openOnHover"
has   "…and follows the switch"                 IslandWindowController.swift "state.\$openOnHover.sink"
has   "Close after reaches the state machine"   IslandWindowController.swift "state.\$autoCloseInterval.sink"
has   "the pointer is recorded first"           IslandWindowController.swift "let previouslyInIsland = wasInIsland"
has   "a click is an interaction"               IslandWindowController.swift "self.fsm.userInteracted()"
has   "the wing still takes the pointer away"   IslandWindowController.swift "let inIsland = hoverRect.contains(local) && !wing.passThrough || state.shelfHoldsIsland"
has   "the dwell is one one-shot work item"      IslandStateMachine.swift "armHoverOpen(hoverDwell, item)"
hasnt "no second timer or monitor for hover"    IslandStateMachine.swift "Timer.scheduledTimer"

echo "$pass passed, $fail failed"
```

```bash
bash scripts/test-u1-wiring.sh | tail -1
bash scripts/test-island-wing.sh 2>&1 | tail -1
bash scripts/test-island-wing-wiring.sh 2>&1 | tail -1
bash scripts/test-island-poller.sh 2>&1 | tail -1
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"
```

Expected: `18 passed, 0 failed` (the ten before and eight hover lines); `All tests passed.` twice; the poller's `visible 57 Hz, hidden 10 Hz, shown again 60 Hz` line (unchanged); `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Windows/Linux: the FSM's test first**

**Create `windows/scripts/cat-tests/fsm-hover.test.mjs`:**

```javascript
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The FSM calls window.setTimeout: give it one that the test turns by hand.
let now = 0, nextId = 1;
const timers = new Map();
globalThis.window = {
  setTimeout: (fn, ms) => { const id = nextId++; timers.set(id, { fn, at: now + ms }); return id; },
  clearTimeout: (id) => { timers.delete(id); },
};
function seconds(s) {
  const end = now + s * 1000;
  for (;;) {
    const due = [...timers.entries()].filter(([, x]) => x.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
    if (!due) break;
    now = due[1].at; timers.delete(due[0]); due[1].fn();
  }
  now = end;
}
const { IslandStateMachine } = await import("../../src/island/fsm.ts");
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
function machine() { timers.clear(); return new IslandStateMachine(); }

// The cases of tests/IslandHoverTests.swift (the Mac), in the same order, with the 150 ms dwell.
function entered(fsm) { fsm.mouseEntered(); seconds(0.15); }   // the pointer stays over the island for the dwell: it opens

test("open on hover off: hovering only peeks and arms no timer", () => {
  const fsm = machine();
  fsm.mouseEntered();
  seconds(5);
  assert.equal(fsm.state, "petit");
  assert.equal(fsm.openedByHover, false);
});

test("the dwell: 149 ms over the island does not open it, 150 ms does", () => {
  const fsm = machine();
  assert.equal(fsm.hoverDwell, 0.15);
  fsm.openOnHover = true;
  fsm.mouseEntered();
  assert.equal(fsm.state, "petit", "the usual peek is not delayed");
  seconds(0.149);
  assert.equal(fsm.state, "petit");
  assert.equal(fsm.openedByHover, false);
  seconds(0.001);
  assert.equal(fsm.state, "home");
  assert.equal(fsm.openedByHover, true);
  assert.equal(timers.size, 0, "no timer is left armed once it has opened");
});

test("leaving at 100 ms cancels the open; coming back starts a new dwell", () => {
  const fsm = machine();
  fsm.openOnHover = true;
  fsm.mouseEntered();
  seconds(0.1);
  fsm.mouseLeft();
  assert.ok([...timers.values()].every((t) => t.at - now > 1000), "no dwell timer is left (only the 60 s hide timer)");
  seconds(0.5);
  assert.equal(fsm.state, "petit");
  assert.equal(fsm.openedByHover, false);
  fsm.mouseEntered();
  seconds(0.149);
  assert.equal(fsm.state, "petit");
  seconds(0.001);
  assert.equal(fsm.state, "home");
});

test("open on hover: leaving folds after the short grace period", () => {
  const fsm = machine();
  fsm.openOnHover = true;
  entered(fsm);
  assert.equal(fsm.state, "home");
  assert.equal(fsm.openedByHover, true);
  fsm.mouseLeft();
  seconds(0.5);
  assert.equal(fsm.state, "home");
  seconds(0.1);
  assert.equal(fsm.state, "petit");
  assert.equal(fsm.openedByHover, false);
  entered(fsm);                   // from the compact island it opens again
  assert.equal(fsm.state, "home");
});

test("open on hover: coming back before the grace period keeps it open", () => {
  const fsm = machine();
  fsm.openOnHover = true;
  entered(fsm);
  fsm.mouseLeft();
  seconds(0.3);
  fsm.mouseEntered();
  seconds(5);
  assert.equal(fsm.state, "home");
});

test("open on hover: a click inside makes it an ordinary open island", () => {
  const fsm = machine();
  fsm.openOnHover = true;
  fsm.homeToPetitDelay = 3;
  entered(fsm);
  fsm.mouseLeft();
  fsm.userInteracted();          // the short countdown becomes the normal one
  seconds(1);
  assert.equal(fsm.state, "home");
  seconds(2);
  assert.equal(fsm.state, "petit");
});

test("open on hover: an alert that pins the island is never opened or folded by hover, and one that arrives during the dwell wins", () => {
  const fsm = machine();
  fsm.openOnHover = true;
  fsm.pinned = true;
  fsm.mouseEntered();
  seconds(1);
  assert.equal(fsm.state, "petit", "pinned: no dwell is armed");
  assert.equal(fsm.openedByHover, false);
  fsm.forceHome();
  fsm.mouseLeft();
  seconds(5);
  assert.equal(fsm.state, "home");
  const other = machine();
  other.openOnHover = true;
  other.mouseEntered();
  other.forceHome();              // an alert during the dwell
  seconds(0.2);
  assert.equal(other.openedByHover, false);
});

test("open on hover: an island opened by an alert keeps the normal delay", () => {
  const fsm = machine();
  fsm.openOnHover = true;
  fsm.homeToPetitDelay = 3;
  fsm.forceHome();
  fsm.mouseEntered();
  assert.equal(timers.size, 0, "an island that is already open arms no dwell");
  fsm.mouseLeft();
  seconds(1);
  assert.equal(fsm.state, "home");
  seconds(2);
  assert.equal(fsm.state, "petit");
});

test("the wiring: the island feeds the setting to the machine, records the pointer first, and a click is an interaction", () => {
  const isl = source("island/island.ts");
  assert.equal((isl.match(/this\.fsm\.openOnHover = State\.settings\.openOnHover;/g) ?? []).length, 2, "at start and in applySettings");
  assert.match(isl, /const wasIn = this\.wasInIsland;\n\s+this\.wasInIsland = inIsland;/);
  assert.match(isl, /this\.fsm\.userInteracted\(\);/);
  assert.match(isl, /this\.wasInIsland = true;\n\s+this\.fsm\.mouseEntered\(\);/);
});
```

Run: `cd windows && node --experimental-strip-types --test --test-reporter=spec scripts/cat-tests/fsm-hover.test.mjs 2>&1 | tail -12`
Expected: FAIL: the dwell tests fail (`hoverDwell` is not a property; `fsm.state` stays `petit` where `home` is expected after 150 ms).

- [ ] **Step 7: Windows/Linux: the FSM, the page, the setting**

**Edit `windows/src/island/fsm.ts`:** find

```typescript
  /** An alert waiting for an answer stays open, even when the mouse leaves. */
  pinned = false;
```

replace with

```typescript
  /** An alert waiting for an answer stays open, even when the mouse leaves. */
  pinned = false;
  /** Hovering opens the island all the way instead of peeking (Settings → General → Open on hover, off by default), as IslandStateMachine.openOnHover on the Mac. */
  openOnHover = false;
  /** The pointer must stay over the island this long, seconds, before Open on hover opens it; leaving earlier cancels it. The usual hover peek is not delayed. */
  hoverDwell = 0.15;
  /** Grace period after the pointer leaves a hover-opened island, seconds. */
  hoverCloseDelay = 0.6;
  /** Open because of a hover, until the user clicks inside it. */
  get openedByHover(): boolean {
    return this.byHover;
  }
  private byHover = false;
```

**Edit `windows/src/island/fsm.ts`:** find

```typescript
        this.scheduleGreetCollapse(this.greetHoverCollapseDelay);
        break;
    }
  }
```

replace with

```typescript
        this.scheduleGreetCollapse(this.greetHoverCollapseDelay);
        break;
    }
    // Open on hover: the island opens once the pointer has stayed `hoverDwell`. Not while an alert pins it.
    if (this.openOnHover && (this.state === "hidden" || this.state === "petit") && !this.pinned) this.scheduleHoverOpen();
  }

  private scheduleHoverOpen() {
    this.clear("hoverOpen");
    this.hoverOpen = window.setTimeout(() => {
      this.hoverOpen = null;
      if ((this.state !== "hidden" && this.state !== "petit") || this.pinned) return;
      this.cancelTimers();
      this.byHover = true;
      this.transition("home");
    }, this.hoverDwell * 1000);
  }
```

**Edit `windows/src/island/fsm.ts`:** find

```typescript
  mouseLeft() {
    switch (this.state) {
```

replace with

```typescript
  mouseLeft() {
    this.clear("hoverOpen"); // leaving before the dwell is over cancels the open
    switch (this.state) {
```

**Edit `windows/src/island/fsm.ts`:** find

```typescript
  private greetCollapse: number | null = null;
```

replace with

```typescript
  private greetCollapse: number | null = null;
  private hoverOpen: number | null = null;
```

**Edit `windows/src/island/fsm.ts`:** find

```typescript
  private clear(which: "petitHide" | "homeCollapse" | "greetCollapse") {
```

replace with

```typescript
  private clear(which: "petitHide" | "homeCollapse" | "greetCollapse" | "hoverOpen") {
```

**Edit `windows/src/island/fsm.ts`:** find

```typescript
    this.clear("greetCollapse");
  }

  private transition
```

replace with

```typescript
    this.clear("greetCollapse");
    this.clear("hoverOpen");
  }

  private transition
```

**Edit `windows/src/island/fsm.ts`:** find

```typescript
  click() {
    if (this.state !== "petit") return;
```

replace with

```typescript
  click() {
    this.byHover = false;
    if (this.state !== "petit") return;
```

**Edit `windows/src/island/fsm.ts`:** find

```typescript
  /** Alert or explicit request: open straight to expanded. */
  forceHome() {
    this.cancelTimers();
```

replace with

```typescript
  /** The user clicked inside the island: a hover-opened island now stays like any open island (the normal auto-close) instead of folding once the pointer leaves. */
  userInteracted() {
    if (!this.byHover) return;
    this.byHover = false;
    // The short countdown already running becomes the normal one.
    if (this.state === "home" && this.homeCollapse != null) this.scheduleHomeCollapse();
  }

  /** Alert or explicit request: open straight to expanded. */
  forceHome() {
    this.byHover = false;
    this.cancelTimers();
```

**Edit `windows/src/island/fsm.ts`:** find

```typescript
  forcePetit() {
    this.cancelTimers();
```

replace with

```typescript
  forcePetit() {
    this.byHover = false;
    this.cancelTimers();
```

**Edit `windows/src/island/fsm.ts`:** find

```typescript
  forceHidden() {
    this.cancelTimers();
```

replace with

```typescript
  forceHidden() {
    this.byHover = false;
    this.cancelTimers();
```

**Edit `windows/src/island/fsm.ts`:** find

```typescript
    this.homeCollapse = window.setTimeout(() => {
      this.homeCollapse = null;
      if (this.state === "home") this.transition("petit");
    }, this.homeToPetitDelay * 1000);
```

replace with

```typescript
    const seconds = this.byHover ? this.hoverCloseDelay : this.homeToPetitDelay;
    this.homeCollapse = window.setTimeout(() => {
      this.homeCollapse = null;
      if (this.state === "home") {
        this.byHover = false;
        this.transition("petit");
      }
    }, seconds * 1000);
```

**Edit `windows/src/island/island.ts`:** find

```typescript
    this.fsm.homeToPetitDelay = State.settings.autoCloseInterval;
    this.fsm.onTransition = (from, to) => {
```

replace with

```typescript
    this.fsm.homeToPetitDelay = State.settings.autoCloseInterval;
    this.fsm.openOnHover = State.settings.openOnHover;
    this.fsm.onTransition = (from, to) => {
```

**Edit `windows/src/island/island.ts`:** find

```typescript
    this.wakeStrip.addEventListener("mouseenter", () => {
      Sound.resume();
      if (State.mode === "hidden") this.fsm.mouseEntered();
    });
```

replace with

```typescript
    this.wakeStrip.addEventListener("mouseenter", () => {
      Sound.resume();
      if (State.mode === "hidden") {
        // Recorded first: an island that opens on this hover must not see the pointer as still outside, or it would start folding at once.
        this.wasInIsland = true;
        this.fsm.mouseEntered();
      }
    });
```

**Edit `windows/src/island/island.ts`:** find

```typescript
      Sound.resume();
      this.sleep.event("click");
      State.lastActivity = performance.now();
```

replace with

```typescript
      Sound.resume();
      this.sleep.event("click");
      State.lastActivity = performance.now();
      // A click makes a hover-opened island an ordinary open one.
      this.fsm.userInteracted();
```

**Edit `windows/src/island/island.ts`:** find

```typescript
    if (inIsland && !this.wasInIsland) {
      this.sleep.event("hover");
      if (this.fsm.state === "hello") this.greeting.hover();
      this.fsm.mouseEntered();
      this.homeCollapseAt = null;
    }
    if (!inIsland && this.wasInIsland) {
      this.fsm.mouseLeft();
      if (this.fsm.state === "home" && !State.isPinned) {
        this.homeCollapseAt = performance.now() + State.settings.autoCloseInterval * 1000;
      }
    }
    this.wasInIsland = inIsland;
```

replace with

```typescript
    // Recorded before the state machine hears of it: a transition it makes right away (open on hover) reads where the pointer is, and must not see it as still outside.
    const wasIn = this.wasInIsland;
    this.wasInIsland = inIsland;
    if (inIsland && !wasIn) {
      this.sleep.event("hover");
      if (this.fsm.state === "hello") this.greeting.hover();
      this.fsm.mouseEntered();
      this.homeCollapseAt = null;
    }
    if (!inIsland && wasIn) {
      this.fsm.mouseLeft();
      if (this.fsm.state === "home" && !State.isPinned) {
        this.homeCollapseAt = performance.now() + (this.fsm.openedByHover ? this.fsm.hoverCloseDelay : State.settings.autoCloseInterval) * 1000;
      }
    }
```

**Edit `windows/src/island/island.ts`:** find

```typescript
    Sound.setVolume(State.settings.soundVolume);
    this.fsm.homeToPetitDelay = State.settings.autoCloseInterval;
```

replace with

```typescript
    Sound.setVolume(State.settings.soundVolume);
    this.fsm.homeToPetitDelay = State.settings.autoCloseInterval;
    this.fsm.openOnHover = State.settings.openOnHover;
```

**Edit `windows/src/core/state.ts`:** find

```typescript
  autoCloseInterval: number;
  absenceInterval: number;
```

replace with

```typescript
  autoCloseInterval: number;
  /** Hovering the island opens it all the way (off: hovering only peeks). */
  openOnHover: boolean;
  absenceInterval: number;
```

**Edit `windows/src/core/state.ts`:** find

```typescript
  autoCloseInterval: 15,
  absenceInterval: 180,
```

replace with

```typescript
  autoCloseInterval: 15,
  openOnHover: false,
  absenceInterval: 180,
```

**Edit `windows/src/settings/main.ts`:** find

```typescript
    h("div", { class: "row" },
      h("label", { text: "Auto-close" }),
```

replace with

```typescript
    h("div", { class: "row" },
      h("label", { text: "Open on hover" }),
      toggle(settings.openOnHover, (v) => { settings.openOnHover = v; void save(); }),
    ),
    h("div", { class: "hint", text: "Hovering the island opens it; it folds again shortly after the pointer leaves. Click inside to keep it open." }),
    h("div", { class: "row" },
      h("label", { text: "Auto-close" }),
```

**Edit `windows/src-tauri/src/settings.rs`:** find

```rust
    pub auto_close_interval: f64,
    pub absence_interval: f64,
```

replace with

```rust
    pub auto_close_interval: f64,
    /// Hovering the island opens it all the way (off: hovering only peeks).
    #[serde(default)]
    pub open_on_hover: bool,
    pub absence_interval: f64,
```

**Edit `windows/src-tauri/src/settings.rs`:** find

```rust
            auto_close_interval: 15.0,
            absence_interval: 180.0,
```

replace with

```rust
            auto_close_interval: 15.0,
            open_on_hover: false,
            absence_interval: 180.0,
```

**Edit `windows/src-tauri/src/settings.rs`:** find

```rust
    #[test]
    fn a_settings_file_from_0_1_1_keeps_its_claude_model() {
```

replace with

```rust
    #[test]
    fn a_settings_file_without_open_on_hover_gets_it_off_and_keeps_it_when_set() {
        let old = r#"{"soundEnabled":true,"soundVolume":0.12,"autoCloseInterval":15,"absenceInterval":180,
            "activeIntegrations":[],"screen":"primary","autostart":false,"hooksInstalled":false}"#;
        let s: Settings = serde_json::from_str(old).unwrap();
        assert!(!s.open_on_hover);
        assert_eq!(serde_json::to_value(&s).unwrap()["openOnHover"], false);
        let on: Settings = serde_json::from_str(&old.replace("\"autostart\"", "\"openOnHover\":true,\"autostart\"")).unwrap();
        assert!(on.open_on_hover);
    }

    #[test]
    fn a_settings_file_from_0_1_1_keeps_its_claude_model() {
```

One existing source pin reads the line Step 7 changed (the dry run found it by running `check:cat`):

**Edit `windows/scripts/cat-tests/sleep.test.mjs`:** find

```javascript
  assert.match(island, /if \(inIsland && !this\.wasInIsland\) \{\s*this\.sleep\.event\("hover"\);/);
```

replace with

```javascript
  assert.match(island, /if \(inIsland && !wasIn\) \{\s*this\.sleep\.event\("hover"\);/);
```

- [ ] **Step 8: Run everything Windows/Linux**

Run: `cd windows && npx --no-install tsc --noEmit && echo tsc ok && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"`
Expected: `tsc ok`; the nine tests of `fsm-hover.test.mjs` pass; `ℹ fail 0` (`ℹ tests 387` in the dry run's counting: 372 + 6 + 9).
Run: `windows/scripts/cargo-linux.sh test --workspace --offline --target-dir /repo/windows/target/u1 2>&1 | grep -E "test result|FAILED|error"` (needs Docker; the settings test cannot run on the Mac).
Expected: every `test result: ok`.

- [ ] **Step 9: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add tests/IslandHoverTests.swift scripts/test-island-hover.sh windows/scripts/cat-tests/fsm-hover.test.mjs NotchBuddy/Sources/App/IslandStateMachine.swift NotchBuddy/Sources/App/IslandWindowController.swift NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/SettingsView.swift scripts/test-u1-wiring.sh windows/src/island/fsm.ts windows/src/island/island.ts windows/src/core/state.ts windows/src/settings/main.ts windows/src-tauri/src/settings.rs windows/scripts/cat-tests/sleep.test.mjs
git commit -F - <<'EOF'
feat: Open on hover, off by default (upstream 0ad1b1d and 2261334); Close after reaches the state machine

Hovering the island opens it; it folds 0.6 s after the pointer leaves; a click inside makes it an ordinary open island; a waiting card or an
alert keeps its rules. The poll feeds the state machine as before, so the compact wing still takes the pointer away from the grid, and there is no
new timer or monitor. The poll records the pointer before the state machine hears of it. Mac and Windows/Linux. Settings → Close after now sets the delay.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 8: The permission card's CPU: find what redraws every frame

**Agent: `nm-implementer-deep` (Sonnet 5.5, high; CLAUDE.md trigger 2: the cause is unknown).** Loads `superpowers:systematic-debugging` besides the usual skills.

**Files:**
- Create: `scripts/measure-island-cpu.swift`, `scripts/measure-island-cpu.sh`
- Modify: whichever files the hunt names (the likely ones are listed below), `scripts/test-u1-wiring.sh`

**Interfaces:**
- Produces: `bash scripts/measure-island-cpu.sh --state compact|overview|approval|approval-high|question [--seconds 8]`, which prints `state=<name> cpu=<n>% of one core over <s> s`.

**The symptom (QA of 0.9.2).** About 55 % CPU on the Mac while the island shows a permission card (the sidekick's risk card, `approval-high`); about 0.3 % with the island hidden. The cat in the card is not the whole story: the same big cat is on screen in every expanded view.

**What the dry run found by reading (leads, not conclusions; each is to be proved or dropped by a measurement):**
1. `BotCanvasView.swift:17` `TimelineView(.animation(paused: state.mode == .hidden))`: the big cat redraws at the display's refresh rate (120 Hz on ProMotion), each frame updating the engine and drawing the whole cat with its effects (`CatEffects`, glow, particles). `BotCanvasView.swift:150` has a 30 Hz one for another view. The Debug-only `CatFrameMeter` budget is 2 ms a frame: at 120 Hz, 2 ms is 24 % of a core before anything else.
2. `IslandRootView.swift` `CountdownBar` (line ~447): `Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true)` is mounted whenever `IslandContainer` is, **including while hidden**, and mutates `@State barWidth` on every tick. It is small, but it contradicts "0 % CPU when hidden" and it is a per-0.1 s SwiftUI invalidation while the card is up.
3. `IslandViewContent.swift` `ShimmerOverlay` (`.linear(2.2).repeatForever`) and `TickerShimmerText` (`TimelineView(.animation)`, line ~3942): continuous animations; find where each is mounted and whether the approval card or `AgentWho` reaches them.
4. `CardBackground` (line ~4357) paints a radial gradient wash over a rounded rectangle: if it is re-rasterised on every frame because a sibling invalidates it, the cost scales with the island's area (640 x 160, or up to 560 pt tall with Task 6).
5. `BotPlacement`'s `botGlowOpacity` circle with a `RadialGradient` and `.animation(.easeInOut(duration: 0.4), value:)` under the card.
6. The sidekick (`Sidekick.swift`, `SidekickView`) and `PresenceMonitor.swift`: confirm nothing there ticks while a card is up (`Sidekick.shared.tick()` is called from the poll at most every 5 s).
7. `pollFrame` runs at 57 to 60 Hz while the island is on screen (`IslandPoller`), and every tick writes `AppState.mousePosition` when the pointer moved more than 1 pt: that `@Published` invalidates every view that observes `AppState`, including `ApprovalView` and `IslandContainer`. With the card up and the pointer moving, that is 60 body evaluations a second for the whole island. (Task 10 adds `islandHovered`, which writes only on change.)

**What the dry run measured with the tool below** (first run, built without `-O`, while two Xcode builds held the machine at a load average near 30, so the figures are inflated and are **not** comparable with the QA's 55 %; the script now builds with `-O`): `compact` 104.9 %, `overview` 87.7 %, `approval` 94.2 %, `approval-high` 86.9 %, `question` 86.8 % of one core over 8 s each. What survives the noise is the shape: **the compact island costs as much as the open card**, so whatever burns is not the card's own views; it is something that runs in every shown state (leads 1, 2 and 7), and the 55 % of QA is the same cost seen on a faster, optimised build. Re-run on a quiet machine first; that is the **before** table.

**Method (the order matters).**

- [ ] **Step 1: Build the measurement tool (it never launches the app)**

**Create `scripts/measure-island-cpu.swift`:**

```swift
import AppKit
import Darwin
import SwiftUI

// How much CPU the island's own SwiftUI costs in a given state, without launching NotchMeow: the app's own root view (IslandRootView) on the app's own AppState, in a window of its own that is on screen
// but invisible (alpha 0.02, no mouse, no activation), so the display really ticks the TimelineViews as it does in the app. The process's CPU time is read before and after a few seconds and printed as
// a share of one core. A made-up state is put in AppState; nothing is saved, nothing is sent, no hook socket is opened.
//   bash scripts/measure-island-cpu.sh [--state compact|overview|approval|approval-high|question|all] [--seconds 8]
// Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift, in a home folder of its own. A window the size of the island's panel flickers at the top of the main screen for the length of the run.

@main
struct MeasureIslandCPU {
    static func cpuSeconds() -> Double {
        var u = rusage(); getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec) + Double(u.ru_utime.tv_usec) / 1e6 + Double(u.ru_stime.tv_sec) + Double(u.ru_stime.tv_usec) / 1e6
    }

    @MainActor static func main() {
        var which = "approval", seconds = 8.0
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--state": which = it.next() ?? which
            case "--seconds": seconds = Double(it.next() ?? "") ?? seconds
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let state = AppState.shared
        let task = AgentTask(id: "integration_claude", name: "Claude Code", color: "#E07950", state: .approval, steps: [], source: .claudeCode)
        state.tasks = [task]
        state.focusId = task.id
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let host = NSHostingView(rootView: IslandRootView().environmentObject(state))
        let win = NSPanel(contentRect: NSRect(x: screen.frame.midX - 360, y: screen.frame.maxY - 320, width: 720, height: 320), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        win.isOpaque = false; win.backgroundColor = .clear; win.ignoresMouseEvents = true; win.level = .statusBar; win.alphaValue = 0.02
        win.contentView = host
        win.orderFrontRegardless()

        /// Puts the island in one made-up state.
        func configure(_ which: String) -> Bool {
            state.pendingApproval = nil; state.pendingQuestion = nil
            switch which {
            case "compact": state.mode = .compact
            case "overview": state.view = .overview; state.mode = .expanded
            case "approval", "approval-high":
                let command = which == "approval" ? "npm test" : "rm -rf build"
                let why = SidekickExplain.explain(agent: "integration_claude", tool: "Bash", input: ["command": command], cwd: "/Users/me/proj", home: "/Users/me")
                state.pendingApproval = ApprovalInfo(sessionId: "measure", tool: "Bash", command: command, inputKey: "", pillId: task.id, risk: why.risk, line: why.line)
                state.view = .approval; state.mode = .expanded
            case "question":
                state.pendingQuestion = AskQuestion.parse(toolInput: ["questions": [["question": "Which one?", "header": "Pick", "options": [["label": "A", "description": "first"], ["label": "B", "description": "second"]], "multiSelect": false]]])
                state.view = .question; state.mode = .expanded
            default: return false
            }
            return true
        }
        let states = which == "all" ? ["compact", "overview", "approval", "approval-high", "question"] : [which]
        for name in states {
            guard configure(name) else { FileHandle.standardError.write(Data("unknown state \(name)\n".utf8)); exit(2) }
            RunLoop.current.run(until: Date().addingTimeInterval(2))   // warm up: the spring that opens the island, the first frames
            let c0 = cpuSeconds(), t0 = Date()
            RunLoop.current.run(until: t0.addingTimeInterval(seconds))
            let share = (cpuSeconds() - c0) / Date().timeIntervalSince(t0) * 100
            print(String(format: "state=%@ cpu=%.1f%% of one core over %.0f s", name, share, seconds))
        }
        win.orderOut(nil)
    }
}
```

**Create `scripts/measure-island-cpu.sh`:**

```bash
#!/usr/bin/env bash
# How much CPU the island's own SwiftUI costs in a given state, without launching NotchMeow (see scripts/measure-island-cpu.swift).
#   bash scripts/measure-island-cpu.sh [--state compact|overview|approval|approval-high|question|all] [--seconds 8]
# IslandRootView reads the app's AppState, so this compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about seven minutes (-O: the numbers should be near the Release build's, not the unoptimised Debug ones). It runs in a home folder of
# its own through scripts/render-home-guard.sh, which kills it if it ever opens the real ~/.claude, ~/.gemini or ~/.codex. It touches no preferences.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-measure-island-cpu.XXXXXX")"
REAL_HOME="$HOME"
cleanup() {
    rm -rf "$BUILD_DIR"
    defaults delete measure-island-cpu > /dev/null 2>&1 || true
    rm -f "$REAL_HOME/Library/Preferences/measure-island-cpu.plist"
}
trap cleanup EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$BUILD_DIR/home"
APP=NotchBuddy/Sources/App
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$APP" -name '*.swift' ! -name NotchBuddyApp.swift | sort)
swiftc -O -swift-version 6 -suppress-warnings "${FILES[@]}" scripts/measure-island-cpu.swift -o "$BUILD_DIR/measure-island-cpu"
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/measure-island-cpu" "$@"
```

```bash
chmod +x scripts/measure-island-cpu.sh && bash -n scripts/measure-island-cpu.sh
```

The tool compiles the whole app (about seven minutes, run it in the background), then hosts the app's own `IslandRootView` on its own `AppState` in a panel that is on screen but nearly invisible (alpha 0.02, no mouse, no activation) at the top of the main screen, so the display really drives the `TimelineView`s. It runs inside `scripts/render-home-guard.sh`'s fence like the render tools. It sends no hook event and opens no socket. **The installed NotchMeow keeps running and is not touched**; the tool is a separate process with its own preferences domain.

- [ ] **Step 2: Measure before, five states**

Run (one compile, then about a minute): `bash scripts/measure-island-cpu.sh --state all --seconds 8`
Record the five lines in the ledger as the **before** table, and the display's refresh rate (`system_profiler SPDisplaysDataType | grep -i "refresh\|ProMotion"`, never opening anything else). Do not move the pointer during a run (the tool's panel ignores the mouse, but the poll in the real app would see it: the tool has no poll). If `approval-high` is far below 55 %, say so: the measurement does not reproduce the QA number and the difference (the tool has no `IslandWindowController` poll, no sidekick, no hook server) is the clue; then add the pieces one at a time: the poll's `mousePosition` write (lead 7) is the first, by a `Timer` in the tool that writes `state.mousePosition` at 60 Hz with a moving point.

- [ ] **Step 3: Find the cause by elimination, one change at a time, re-measuring**

For each lead in order, make the smallest experimental change (comment out or pause it in the worktree), re-run `approval-high`, and keep a table (lead, change, cpu). Use `sample`/Instruments only if you start the tool, never the app: `sample <pid of measure-island-cpu> 5` is allowed. Stop at the lead (or the pair) that accounts for the cost. Never remove an animation the owner can see: the fix must change how often or how much is redrawn, never what it looks like (a `TimelineView` kept at a coarser `minimumInterval` where the motion allows it, a `drawingGroup()` that caches a static layer, `paused:` while nothing animates, a state write that happens only when the value changed, a `Timer` that exists only while its bar can be non-zero).

- [ ] **Step 4: Fix it without changing the look**

Apply the fix the measurement supports. Rules: no new timer; the cat's own frame rate is `CatConfig`'s business (do not lower it for the owner without asking: if the cat at 120 Hz is the cost, report the number and propose a 60 Hz cap as an **question for the owner via the main session** instead of doing it); `CountdownBar`'s timer, if it is the culprit or a contributor, mounts only while `state.mode == .expanded && !state.isPinned` (the same condition `updateBar` already checks); anything shown identical by a picture (`render-approval-card.sh`, byte-identical before and after) stays identical.

- [ ] **Step 5: Measure after, add a pin for each change, and prove the look**

Run `bash scripts/measure-island-cpu.sh --state all --seconds 8` again and record the **after** table next to the before. Add one pin per change to `scripts/test-u1-wiring.sh` (a `has`/`hasnt` line in a new `# The permission card's CPU` section, written like the others), then:

```bash
bash scripts/test-u1-wiring.sh | tail -1
bash scripts/test-island-wing-wiring.sh 2>&1 | tail -1
bash scripts/test-cat-wiring.sh 2>&1 | tail -1
bash scripts/render-approval-card.sh --out ${TMPDIR:-/tmp}/u1/card-after-perf.png    # background, seven minutes
cmp ${TMPDIR:-/tmp}/u1/card-before-perf.png ${TMPDIR:-/tmp}/u1/card-after-perf.png && echo "the card looks the same"
```

(`card-before-perf.png` is rendered from the commit before this task's first change, in a second worktree of that commit, the way Task 5's Step 6 does.) Expected: the pins pass; `the card looks the same`; the **after** `approval-high` figure is lower by the amount the cause explains. If the fix is a coarser frame rate or any visible change, stop and report instead of committing.

- [ ] **Step 6: Build, then report to the main session with the two tables**

```bash
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"
```

Expected: `** BUILD SUCCEEDED **`. The owner's real-build confirmation (Activity Monitor on a permission card, before 0.9.2's 55 %, after this build) is item 6 of Task 16.

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add scripts/measure-island-cpu.swift scripts/measure-island-cpu.sh scripts/test-u1-wiring.sh <the files the fix changed>
git commit -F - <<'EOF'
perf(mac): <what redrew every frame on the permission card, and what it does now>

Measured with scripts/measure-island-cpu.sh (the app's own island view in a nearly invisible panel; the app is never launched):
approval-high <before>% -> <after>% of one core. The card looks the same (render-approval-card.sh, byte-identical).

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
```

(The two `<…>` in this commit text are the only blanks in the plan: they are the finding, which the task exists to produce.)

---

### Task 9: A click outside the open island folds it (Mac)

**Agent: `nm-implementer-deep` (Sonnet 5.5, high; CLAUDE.md trigger 1: an AppKit event monitor tied to a panel's mode and key-window state).** Loads `superpowers:systematic-debugging` besides the usual skills.

**Files:**
- Create: `NotchBuddy/Sources/App/IslandOutsideClick.swift`, `tests/IslandOutsideClickTests.swift`, `scripts/test-island-outside-click.sh`
- Modify: `NotchBuddy/Sources/App/IslandWindowController.swift`, `scripts/test-u1-wiring.sh`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated by `xcodegen`)

**Interfaces:**
- Produces: `IslandOutsideClick.Context` (`expanded`, `pinned`, `held`, `typing`, `pointerInIsland`, `busy`: all `Bool`), `IslandOutsideClick.shouldFold(_ c: Context) -> Bool`, `IslandOutsideClick.Tracker` (`down(at:)`, `up(at:) -> Bool`, `reset()`), `IslandOutsideClick.clickSlop = 4`.
- Consumes: `IslandWindowController.collapse()`, `decisionWaiting`, `fsm.isHeldOpen`, `wasInIsland`, `inAttachDrag`, `attachDragStart`, `wardrobeMenuOpen`, `state.$mode` (all existing).

**Design.** The island is a non-activating panel that passes the mouse on outside the island rect, so a click outside it is delivered to another app, and `NSEvent.addGlobalMonitorForEvents` sees exactly those events (a global monitor never sees the app's own events: a click on the island, on Settings or on the Wardrobe menu cannot reach it; no Accessibility permission is needed for mouse events, and the app already has global mouse-up and key monitors). **One monitor, and only while the island is expanded:** a `state.$mode` sink installs it when the mode becomes `.expanded` and removes it when it leaves (so none when compact or hidden). **It folds on the release of a click, not on the press:** a press that moves more than 4 pt before it is released is a drag (a file taken out of a Finder window toward the island, a window moved, a text selection), and must not fold. **What the app knew at the press decides**, because the press can take the key away from the panel before the release (the typing check reads `islandPanel.isKeyWindow`). The reasons to stay are the owner's list, in the rules the app already has: pinned (`state.isPinned`), a request or question waiting (`decisionWaiting`, which includes the chat's card) or `fsm.isHeldOpen` (the shelf's drag-out and share picker), typing in the chat (view `.prompt` and a text input has the keyboard), the pointer over the island (the poll's `wasInIsland`, which includes the 6 pt slop), the cat's head being dragged, and the Wardrobe menu. The fold is `collapse()`, which is also what ⎋ does.

- [ ] **Step 1: Write the failing test and its script**

**Create `tests/IslandOutsideClickTests.swift`:**

```swift
import CoreGraphics
import Foundation

// The rules of the outside click (IslandOutsideClick.swift): when the open island folds, and when it stays.

@main
enum IslandOutsideClickTests {
    static func main() {
        var passed = 0
        func ok(_ cond: Bool, _ name: String) { precondition(cond, name); passed += 1; print("✓ \(name)") }

        typealias C = IslandOutsideClick.Context
        let open = C(expanded: true, pinned: false, held: false, typing: false, pointerInIsland: false, busy: false)
        ok(IslandOutsideClick.shouldFold(open), "an open, unpinned island with nothing waiting folds on a click outside")

        func with(_ edit: (inout C) -> Void) -> C { var c = open; edit(&c); return c }
        ok(!IslandOutsideClick.shouldFold(with { $0.expanded = false }), "a compact or hidden island is never folded by a click (there is nothing to fold)")
        ok(!IslandOutsideClick.shouldFold(with { $0.pinned = true }), "a pinned island (⌘P) stays")
        ok(!IslandOutsideClick.shouldFold(with { $0.held = true }), "a waiting permission request, question, chat card or the shelf's hold keeps the island")
        ok(!IslandOutsideClick.shouldFold(with { $0.typing = true }), "typing in the chat keeps the island")
        ok(!IslandOutsideClick.shouldFold(with { $0.pointerInIsland = true }), "a click with the pointer over the island is not outside")
        ok(!IslandOutsideClick.shouldFold(with { $0.busy = true }), "a cat drag or the Wardrobe menu keeps the island")
        // Every pair of reasons to stay still stays.
        let reasons: [(inout C) -> Void] = [{ $0.pinned = true }, { $0.held = true }, { $0.typing = true }, { $0.pointerInIsland = true }, { $0.busy = true }]
        for (i, a) in reasons.enumerated() { for b in reasons[(i + 1)...] { ok(!IslandOutsideClick.shouldFold(with { a(&$0); b(&$0) }), "two reasons to stay (\(i))") } }

        var t = IslandOutsideClick.Tracker()
        t.down(at: CGPoint(x: 100, y: 100))
        ok(t.up(at: CGPoint(x: 102, y: 101)), "a press and release 2 pt apart is a click")
        t.down(at: CGPoint(x: 100, y: 100))
        ok(!t.up(at: CGPoint(x: 100, y: 120)), "a press dragged 20 pt (a file taken from Finder, a window moved) is not a click")
        ok(!t.up(at: CGPoint(x: 100, y: 100)), "a release with no press seen is not a click, and the press is forgotten after each release")
        t.down(at: CGPoint(x: 0, y: 0))
        ok(t.up(at: CGPoint(x: 3, y: 2)), "3.6 pt is still a click")
        t.down(at: CGPoint(x: 0, y: 0))
        t.reset()
        ok(!t.up(at: CGPoint(x: 0, y: 0)), "a reset forgets the press")

        print("Island outside click: \(passed) checks passed")
    }
}
```

**Create `scripts/test-island-outside-click.sh`:**

```bash
#!/usr/bin/env bash
# The outside click's rules (IslandOutsideClick.swift, Foundation only). Where IslandWindowController calls them is pinned by scripts/test-u1-wiring.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-island-outside.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"
swiftc -swift-version 6 NotchBuddy/Sources/App/IslandOutsideClick.swift tests/IslandOutsideClickTests.swift -o "$TEST_DIR/island-outside-tests"
"$TEST_DIR/island-outside-tests"
```

Run: `chmod +x scripts/test-island-outside-click.sh && bash -n scripts/test-island-outside-click.sh && bash scripts/test-island-outside-click.sh`
Expected: FAIL: `no such file or directory: 'NotchBuddy/Sources/App/IslandOutsideClick.swift'`.

- [ ] **Step 2: The rules**

**Create `NotchBuddy/Sources/App/IslandOutsideClick.swift`:**

```swift
import CoreGraphics
import Foundation

// A click outside the open island folds it at once (Mac). The rules, as plain values: when a click counts, and when the island stays. Foundation only. `IslandWindowController` owns the one
// global mouse monitor, which exists only while the island is expanded (installed when the mode becomes expanded, removed when it leaves it: no monitor when the island is compact or
// hidden), and asks this file what the click means. The monitor sees only events of other apps, so a click on the island itself, on NotchMeow's Settings or on its Wardrobe menu never reaches it.

enum IslandOutsideClick {
    /// A press that moves farther than this (pt) before it is released is a drag (a file taken out of a Finder window, a window moved, a selection), not a click.
    static let clickSlop: CGFloat = 4

    /// What the app knows when the click is released.
    struct Context: Equatable {
        /// The island is expanded.
        var expanded: Bool
        /// The user pinned it open (⌘P).
        var pinned: Bool
        /// A permission request or a question waits for an answer (the island's own card or a chat's), and the shelf's drag-out or share picker holds the island open: `fsm.isHeldOpen`'s
        /// and `EscapeRouting`'s rules.
        var held: Bool
        /// The user is typing in the chat: the chat view is showing and a text field has the keyboard.
        var typing: Bool
        /// The pointer is over the island (its hover area): a click there is not outside.
        var pointerInIsland: Bool
        /// The cat's head is being dragged out, or the Wardrobe menu is open.
        var busy: Bool
    }

    /// Whether a click outside folds the island now.
    static func shouldFold(_ c: Context) -> Bool {
        c.expanded && !c.pinned && !c.held && !c.typing && !c.pointerInIsland && !c.busy
    }

    /// Tells a click from a drag: remembers where the button went down, and says on release whether the pair was a click (it did not move more than `clickSlop`).
    struct Tracker {
        private var downAt: CGPoint?

        mutating func down(at p: CGPoint) { downAt = p }

        /// The release. True when it ends a click; the press is forgotten either way. A release with no press seen (the press happened before the monitor was installed) is not a click.
        mutating func up(at p: CGPoint) -> Bool {
            defer { downAt = nil }
            guard let d = downAt else { return false }
            return hypot(p.x - d.x, p.y - d.y) <= IslandOutsideClick.clickSlop
        }

        /// Forget a press (the monitor was removed).
        mutating func reset() { downAt = nil }
    }
}
```

- [ ] **Step 3: Run the test**

Run: `bash scripts/test-island-outside-click.sh | tail -4`
Expected: PASS: `Island outside click: 22 checks passed`.

- [ ] **Step 4: The monitor, in the controller**

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`:** find

```swift
    private var modeSubscription: AnyCancellable?
```

replace with

```swift
    private var modeSubscription: AnyCancellable?
    private var outsideClickSubscription: AnyCancellable?
    private var outsideClickMonitor: Any?
    private var outsideClicks = IslandOutsideClick.Tracker()
    private var outsideClickAtDown: IslandOutsideClick.Context?
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`:** find

```swift
        modeSubscription = state.$mode
            .receive(on: DispatchQueue.main)
            .sink { mode in poller.run(hidden: mode == .hidden) }
    }
```

replace with

```swift
        modeSubscription = state.$mode
            .receive(on: DispatchQueue.main)
            .sink { mode in poller.run(hidden: mode == .hidden) }
        // A click outside the open island folds it (IslandOutsideClick): the one global mouse monitor exists only while the island is expanded.
        outsideClickSubscription = state.$mode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in self?.syncOutsideClickMonitor(expanded: mode == .expanded) }
    }

    // MARK: - A click outside the open island folds it

    private func syncOutsideClickMonitor(expanded: Bool) {
        if expanded, outsideClickMonitor == nil {
            outsideClicks.reset()
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]) { [weak self] event in
                MainActor.assumeIsolated { self?.handleOutsideClick(event) }
            }
        } else if !expanded, let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
            outsideClicks.reset()
            outsideClickAtDown = nil
        }
    }

    /// Global monitors see only other apps' events, so every event here is outside the island. What the app knew at the press decides (the press can take the key away from the panel
    /// before it is released); the release folds when the pair was a click and not a drag.
    private func handleOutsideClick(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            outsideClicks.down(at: NSEvent.mouseLocation)
            outsideClickAtDown = IslandOutsideClick.Context(
                expanded: state.mode == .expanded,
                pinned: state.isPinned,
                held: decisionWaiting || fsm.isHeldOpen?() == true,
                typing: state.view == .prompt && islandPanel.isKeyWindow && islandPanel.firstResponder is NSTextInputClient,
                pointerInIsland: wasInIsland,
                busy: inAttachDrag || attachDragStart != nil || wardrobeMenuOpen)
        default:
            guard outsideClicks.up(at: NSEvent.mouseLocation), let context = outsideClickAtDown else { return }
            outsideClickAtDown = nil
            if IslandOutsideClick.shouldFold(context) { collapse() }
        }
    }
```

- [ ] **Step 5: The pins, then build with `xcodegen`**

**Edit `scripts/test-u1-wiring.sh`:** find

```bash
echo "$pass passed, $fail failed"
```

replace with

```bash
# The outside click: one global monitor, installed only while the island is expanded.
has   "the monitor follows the mode"            IslandWindowController.swift "syncOutsideClickMonitor(expanded: mode == .expanded)"
has   "installed only when expanded"            IslandWindowController.swift "if expanded, outsideClickMonitor == nil {"
has   "removed when it leaves expanded"         IslandWindowController.swift "NSEvent.removeMonitor(monitor)"
has   "the rule decides"                        IslandWindowController.swift "IslandOutsideClick.shouldFold(context)"
has   "pinned is asked"                         IslandWindowController.swift "pinned: state.isPinned,"
has   "a waiting decision or hold is asked"     IslandWindowController.swift "held: decisionWaiting || fsm.isHeldOpen?() == true,"
has   "typing in the chat is asked"             IslandWindowController.swift "typing: state.view == .prompt && islandPanel.isKeyWindow && islandPanel.firstResponder is NSTextInputClient,"
if [ "$(grep -c 'addGlobalMonitorForEvents(matching: \[.leftMouseDown, .leftMouseUp, .rightMouseDown' "$APP/IslandWindowController.swift")" = 1 ]; then pass=$((pass + 1)); echo "✓ exactly one outside-click monitor"; else fail=$((fail + 1)); echo "✗ exactly one outside-click monitor"; fi

echo "$pass passed, $fail failed"
```

```bash
bash scripts/test-u1-wiring.sh | tail -2
cd NotchBuddy && xcodegen > /dev/null && cd ..
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"
```

Expected: `25 passed, 0 failed` (the 17 before, the 8 outside-click lines); `** BUILD SUCCEEDED **` (the dry run built this with no new warning in the new file).

- [ ] **Step 6: Check the one thing a test cannot: the island's own clicks never reach the monitor**

Read `IslandWindowController`'s mouse code and confirm in the ledger, in one sentence each: (a) the panel's `ignoresMouseEvents` is set from the poll so that a click outside the island rect is not delivered to the panel (so it is a global event for the monitor); (b) a click on the island is local and the monitor never sees it; (c) a click on the Wardrobe menu is tracked by AppKit's menu loop. Do not launch the app: Task 16 lists the real-build checks (clicking another app's window, a Finder file drag, typing in the chat, a pending card, ⌘P).

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add NotchBuddy/Sources/App/IslandOutsideClick.swift tests/IslandOutsideClickTests.swift scripts/test-island-outside-click.sh NotchBuddy/Sources/App/IslandWindowController.swift scripts/test-u1-wiring.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F - <<'EOF'
feat(mac): a click outside the open island folds it

Except when it is pinned, a request or question waits, the user is typing in the chat, the shelf holds it, the cat's head is dragged or the
Wardrobe menu is open. One global mouse monitor, installed only while the island is expanded; it folds on the release of a click (a drag is not one).
The rules are IslandOutsideClick (Foundation, tested); the call sites are pinned.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 10: The hover glow on the Mac: theme colours, rules, view, switch, picture

**Agent: `nm-implementer-deep` (Sonnet 5.5, high; CLAUDE.md trigger 1: the hover state has to travel from the AppKit panel's poll into the SwiftUI tree and drive an animated layer that must cost nothing otherwise).**

**Files:**
- Create: `NotchBuddy/Sources/App/IslandGlow.swift`, `NotchBuddy/Sources/App/IslandGlowView.swift`, `tests/IslandGlowTests.swift`, `scripts/test-island-glow.sh`, `scripts/render-glow.swift`, `scripts/render-glow.sh`
- Modify: `shared/theme.json`, `scripts/gen-theme.mjs`, `tests/theme/gen-theme.test.mjs`, `NotchBuddy/Sources/App/Theme.generated.swift`, `windows/src/theme.generated.css`, `windows/src/theme.generated.ts` (all three written by `gen-theme.mjs`), `NotchBuddy/Sources/App/IslandRootView.swift`, `IslandWindowController.swift`, `AppState.swift`, `SettingsView.swift`, `scripts/test-u1-wiring.sh`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated)

**Interfaces:**
- Produces: `Theme.Glow.{blue,purple,pink,orange}` (+ `…RGB`) and the CSS `--nm-glow-*`, `THEME.glow.*`; `IslandGlow.{defaultsKey, lineWidth, edgeBlur, haloBlur, haloOpacity, fade, secondsPerTurn, framesPerSecond, isShown(enabled:pointerOver:islandOnScreen:dragging:), angle(at:reduceMotion:)}`; `IslandGlowView<S: Shape>(shape:, fixedAngle:)`; `AppState.hoverGlow: Bool` (key `island.hoverGlow`, default true) and `AppState.islandHovered: Bool` (not persisted).
- Consumes: `IslandShape`, the poll's `hoverRect` and `wing.passThrough`, `state.isDraggingBot`, `Color(hex:)`.

**Design.** The glow is an angular gradient (blue, purple, pink, orange, back to blue) stroked along the island's own outline (`IslandShape`, whose `animatableData` makes it follow the open and fold springs), drawn twice: a 3 pt edge blurred 1.2 pt and the same ring blurred 8 pt at 0.8 opacity for the halo. It sits over the black fill and under the content. **It is in the view tree only while `IslandGlow.isShown`**: `Group { if shown { IslandGlowView(…).transition(.opacity) } }.animation(.easeInOut(0.2), value: shown)`, so the fade in and out is the view's own insertion and removal, and the `TimelineView` inside (30 frames a second; paused under Reduce Motion) exists only while it is shown. Hidden island, switch off, pointer away or cat drag: nothing in the tree, no animation, no timer. The trigger is `AppState.islandHovered`, which the existing poll writes **only when it changes** (`pointerOver = hoverRect.contains(local) && !wing.passThrough`): the pointer over the compact wing is not "over the island", so the glow fades with the grid.

- [ ] **Step 1: The theme group first (the contract the rest reads)**

**Edit `shared/theme.json`:** find

```json
    "leaf": "#5DAA68"
  }
}
```

replace with

```json
    "leaf": "#5DAA68"
  },
  "glow": {
    "blue": "#3B82F6",
    "purple": "#A855F7",
    "pink": "#F472B6",
    "orange": "#FB923C"
  }
}
```

**Edit `scripts/gen-theme.mjs`:** find

```javascript
export const GROUPS = ['brand', 'cat', 'greeting', 'outfits'];
```

replace with

```javascript
export const GROUPS = ['brand', 'cat', 'greeting', 'outfits', 'glow'];
```

Run: `bash scripts/test-theme.sh 2>&1 | tail -6`
Expected: FAIL: the old tests still say four groups (`not ok` for the groups, the tokens, the Swift and CSS tests: the dry run saw three of them fail on the lists and on the CSS count 84 against 88).

**Edit `tests/theme/gen-theme.test.mjs`:** find

```javascript
the four groups, every colour
```

replace with

```javascript
the five groups, every colour
```

**Edit `tests/theme/gen-theme.test.mjs`:** find

```javascript
  assert.deepEqual(GROUPS, ['brand', 'cat', 'greeting', 'outfits']);
```

replace with

```javascript
  assert.deepEqual(GROUPS, ['brand', 'cat', 'greeting', 'outfits', 'glow']);
```

**Edit `tests/theme/gen-theme.test.mjs`:** find

```javascript
  assert.deepEqual(Object.keys(t), ['brand', 'cat', 'greeting', 'outfits', 'state']);
```

replace with

```javascript
  assert.deepEqual(Object.keys(t), ['brand', 'cat', 'greeting', 'outfits', 'glow', 'state']);
  assert.deepEqual(Object.keys(t.glow), ['blue', 'purple', 'pink', 'orange']);
```

**Edit `tests/theme/gen-theme.test.mjs`:** find

```javascript
['Brand', 'Cat', 'Greeting', 'Outfits', 'State']
```

replace with

```javascript
['Brand', 'Cat', 'Greeting', 'Outfits', 'Glow', 'State']
```

**Edit `tests/theme/gen-theme.test.mjs`:** find

```javascript
7 + 10 + 6 + 38 + 5 + 11 + 7, 'brand, cat, greeting, outfits, streaks, state colours, state glows'
```

replace with

```javascript
7 + 10 + 6 + 38 + 4 + 5 + 11 + 7, 'brand, cat, greeting, outfits, glow, streaks, state colours, state glows'
```

Run: `node scripts/gen-theme.mjs && bash scripts/test-theme.sh 2>&1 | grep -E "^# (pass|fail)|✓"`
Expected: `wrote 3 theme files` first, then `# pass 8`, `# fail 0` and three `✓` lines plus `✓ 3 theme files match shared/theme.json`. `git status --short` shows the three generated files as modified.

- [ ] **Step 2: The rules, their test and script (red first)**

**Create `tests/IslandGlowTests.swift`:**

```swift
import Foundation

// The hover glow's rules (IslandGlow.swift): when it is drawn, how the colours turn, and what it is made of.

@main
enum IslandGlowTests {
    static func main() {
        var passed = 0
        func ok(_ cond: Bool, _ name: String) { precondition(cond, name); passed += 1; print("✓ \(name)") }

        ok(IslandGlow.defaultsKey == "island.hoverGlow", "the setting's key is island.hoverGlow")
        ok(IslandGlow.lineWidth == 3, "the bright edge is 3 pt")
        ok(IslandGlow.fade == 0.2, "it fades in and out over 0.2 s")

        // When it is drawn: the switch on, the pointer over the island, an island on screen, no cat drag.
        ok(IslandGlow.isShown(enabled: true, pointerOver: true, islandOnScreen: true, dragging: false), "on, hovered, on screen: drawn")
        ok(!IslandGlow.isShown(enabled: false, pointerOver: true, islandOnScreen: true, dragging: false), "switched off: never drawn")
        ok(!IslandGlow.isShown(enabled: true, pointerOver: false, islandOnScreen: true, dragging: false), "pointer away: not drawn (so no animation, no timeline)")
        ok(!IslandGlow.isShown(enabled: true, pointerOver: true, islandOnScreen: false, dragging: false), "hidden island: not drawn")
        ok(!IslandGlow.isShown(enabled: true, pointerOver: true, islandOnScreen: true, dragging: true), "while the cat's head is dragged: not drawn")

        // The turn: one revolution in secondsPerTurn, always inside 0..<360, still under Reduce Motion.
        ok(IslandGlow.angle(at: 0, reduceMotion: false) == 0, "angle 0 at time 0")
        ok(IslandGlow.angle(at: IslandGlow.secondsPerTurn / 2, reduceMotion: false) == 180, "half a turn is 180 degrees")
        ok(IslandGlow.angle(at: IslandGlow.secondsPerTurn * 3, reduceMotion: false) == 0, "whole turns come back to 0")
        ok(abs(IslandGlow.angle(at: 3.3, reduceMotion: false) - 3.3 / IslandGlow.secondsPerTurn * 360) < 1e-9, "the angle is linear in time")
        for t in stride(from: -50.0, through: 800, by: 7.31) {
            let a = IslandGlow.angle(at: t, reduceMotion: false)
            precondition(a >= 0 && a < 360, "angle \(a) at \(t)")
        }
        ok(true, "the angle stays in 0..<360 for negative and large times")
        ok(IslandGlow.angle(at: 123.4, reduceMotion: true) == 0, "Reduce Motion: a still glow (angle 0 at any time)")
        ok(IslandGlow.angle(at: .nan, reduceMotion: false) == 0 && IslandGlow.angle(at: .infinity, reduceMotion: false) == 0, "a time that is not a number gives 0")
        ok(IslandGlow.framesPerSecond <= 30, "the redraw is at most 30 frames a second")

        print("Island hover glow: \(passed) checks passed")
    }
}
```

**Create `scripts/test-island-glow.sh`:**

```bash
#!/usr/bin/env bash
# The hover glow's rules (IslandGlow.swift, Foundation only). Its call sites are pinned by scripts/test-u1-wiring.sh; its colours by scripts/test-theme.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-island-glow.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 NotchBuddy/Sources/App/IslandGlow.swift tests/IslandGlowTests.swift -o "$TEST_DIR/island-glow-tests"
"$TEST_DIR/island-glow-tests"
```

Run: `chmod +x scripts/test-island-glow.sh && bash -n scripts/test-island-glow.sh && bash scripts/test-island-glow.sh`
Expected: FAIL: `no such file or directory: 'NotchBuddy/Sources/App/IslandGlow.swift'`.

**Create `NotchBuddy/Sources/App/IslandGlow.swift`:**

```swift
import Foundation

// The hover glow: a soft rainbow halo along the island's outline (blue, purple, pink, orange: `Theme.Glow`, from shared/theme.json) while the pointer is over the island, in the compact
// notch and in the open island. The rules, as plain values. Foundation only. It is drawn only while the pointer is over the island: the view (`IslandGlowView.swift`) is not even in the tree
// the rest of the time, so a hidden or idle island has no animation, no timer and no layer for it. Reduce Motion: a still glow. The Windows and Linux twin is `#island.glow` in
// windows/src/style.css, with the same colours from the same file.

enum IslandGlow {
    /// The UserDefaults key of Settings → General → Behavior → Hover glow (on by default).
    static let defaultsKey = "island.hoverGlow"
    /// Width of the bright edge along the outline (pt), and how far the same ring is blurred for the halo around it (pt); the edge is blurred a little too, so it is soft.
    static let lineWidth: Double = 3
    static let edgeBlur: Double = 1.2
    static let haloBlur: Double = 8
    /// How the halo's opacity compares with the edge's.
    static let haloOpacity: Double = 0.8
    /// Fade in on hover and out on leave (s).
    static let fade: TimeInterval = 0.2
    /// One turn of the colours around the island (s), and how often the picture is redrawn while it turns (frames per second).
    static let secondsPerTurn: TimeInterval = 8
    static let framesPerSecond: Double = 30

    /// Whether the glow is drawn: the setting is on, the pointer is over the island, and there is an island on screen (compact or open, not hidden), and the cat's head is not being dragged.
    static func isShown(enabled: Bool, pointerOver: Bool, islandOnScreen: Bool, dragging: Bool) -> Bool {
        enabled && pointerOver && islandOnScreen && !dragging
    }

    /// The angle (degrees, 0 up to 360) the colours have turned to at `time` seconds. Reduce Motion: always 0, a still glow. A time that is not a number gives 0.
    static func angle(at time: TimeInterval, reduceMotion: Bool) -> Double {
        guard !reduceMotion, time.isFinite else { return 0 }
        let turn = time.truncatingRemainder(dividingBy: secondsPerTurn) / secondsPerTurn
        return (turn < 0 ? turn + 1 : turn) * 360
    }
}
```

Run: `bash scripts/test-island-glow.sh | tail -3`
Expected: PASS: `Island hover glow: 16 checks passed`.

- [ ] **Step 3: The view, the state, the poll, the island, the switch**

**Create `NotchBuddy/Sources/App/IslandGlowView.swift`:**

```swift
import SwiftUI

/// The hover glow's drawing (rules: `IslandGlow`): an angular gradient of `Theme.Glow` stroked along `shape`, once sharp-ish and once blurred wide for the halo, turning slowly. The island
/// puts it in the tree only while the glow is shown, so `TimelineView` runs only then (30 frames a second, none under Reduce Motion), and the fade is the view's own insertion and removal.
struct IslandGlowView<S: Shape>: View {
    let shape: S
    /// A fixed angle (degrees) instead of the clock's: for the contact sheet (`scripts/render-glow.sh`), which draws one still frame. The island never sets it.
    var fixedAngle: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var colors: [Color] {
        [Theme.Glow.blue, Theme.Glow.purple, Theme.Glow.pink, Theme.Glow.orange, Theme.Glow.blue].map { Color(hex: $0) }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / IslandGlow.framesPerSecond, paused: reduceMotion)) { timeline in
            let gradient = AngularGradient(colors: colors, center: .center,
                                           angle: .degrees(fixedAngle ?? IslandGlow.angle(at: timeline.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion)))
            ZStack {
                shape.stroke(gradient, lineWidth: IslandGlow.lineWidth).blur(radius: IslandGlow.haloBlur).opacity(IslandGlow.haloOpacity)
                shape.stroke(gradient, lineWidth: IslandGlow.lineWidth).blur(radius: IslandGlow.edgeBlur)
            }
        }
        .allowsHitTesting(false)
    }
}
```

**Edit `NotchBuddy/Sources/App/AppState.swift`:** find

```swift
    @Published var autoCloseInterval: TimeInterval = 15 {
```

replace with

```swift
    // The hover glow along the island's outline (IslandGlow) — persisted, on by default
    @Published var hoverGlow: Bool = true {
        didSet { UserDefaults.standard.set(hoverGlow, forKey: IslandGlow.defaultsKey) }
    }
    /// The pointer is over the island (set by the poll only when it changes): the glow's trigger. Not persisted.
    @Published var islandHovered: Bool = false
    @Published var autoCloseInterval: TimeInterval = 15 {
```

**Edit `NotchBuddy/Sources/App/AppState.swift`:** find

```swift
        if let v = ud.object(forKey: "openOnHover") as? Bool { openOnHover = v }
```

replace with

```swift
        if let v = ud.object(forKey: "openOnHover") as? Bool { openOnHover = v }
        if let v = ud.object(forKey: IslandGlow.defaultsKey) as? Bool { hoverGlow = v }
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`:** find

```swift
                    .help("Hovering the island opens it; it folds again shortly after the pointer leaves. Click inside to keep it open.")
```

replace with

```swift
                    .help("Hovering the island opens it; it folds again shortly after the pointer leaves. Click inside to keep it open.")
                Toggle("Hover glow", isOn: $state.hoverGlow)
                    .help("A soft rainbow glow along the island's edge while the pointer is over it.")
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`:** find

```swift
        let inIsland = hoverRect.contains(local) && !wing.passThrough || state.shelfHoldsIsland
```

replace with

```swift
        let inIsland = hoverRect.contains(local) && !wing.passThrough || state.shelfHoldsIsland
        // The hover glow's trigger: the pointer itself over the island (not the shelf's hold), written only when it changes.
        let pointerOver = hoverRect.contains(local) && !wing.passThrough
        if state.islandHovered != pointerOver { state.islandHovered = pointerOver }
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`:** find

```swift
            // Content
            if state.mode == .expanded {
                if greetingExpanded {
```

replace with

```swift
            // The hover glow (IslandGlow): along the outline, over the black and under the content, only while the pointer is over the island. Not in the tree otherwise.
            Group {
                if IslandGlow.isShown(enabled: state.hoverGlow, pointerOver: state.islandHovered, islandOnScreen: state.mode != .hidden, dragging: state.isDraggingBot) {
                    IslandGlowView(shape: IslandShape(width: islandWidth, height: islandHeight, cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: IslandGlow.fade), value: IslandGlow.isShown(enabled: state.hoverGlow, pointerOver: state.islandHovered, islandOnScreen: state.mode != .hidden, dragging: state.isDraggingBot))

            // Content
            if state.mode == .expanded {
                if greetingExpanded {
```

- [ ] **Step 4: The pins; `xcodegen`; build**

**Edit `scripts/test-u1-wiring.sh`:** find

```bash
echo "$pass passed, $fail failed"
```

replace with

```bash
# The hover glow: in the tree only while shown; the poll writes the hover only when it changes; the switch is stored.
has   "the glow is in the tree only while shown" IslandRootView.swift "if IslandGlow.isShown(enabled: state.hoverGlow"
has   "the poll writes the hover on change only" IslandWindowController.swift "if state.islandHovered != pointerOver { state.islandHovered = pointerOver }"
has   "the switch is stored"                     AppState.swift "UserDefaults.standard.set(hoverGlow, forKey: IslandGlow.defaultsKey)"
has   "the switch is in Settings"               SettingsView.swift 'Toggle("Hover glow", isOn: $state.hoverGlow)'
hasnt "the glow never runs a timer of its own"  IslandGlowView.swift "Timer."
has   "Reduce Motion pauses the clock"          IslandGlowView.swift "paused: reduceMotion"

echo "$pass passed, $fail failed"
```

```bash
bash scripts/test-u1-wiring.sh | tail -2
cd NotchBuddy && xcodegen > /dev/null && cd ..
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"
bash scripts/test-island-wing.sh 2>&1 | tail -1; bash scripts/test-island-wing-wiring.sh 2>&1 | tail -1
```

Expected: `31 passed, 0 failed`; `** BUILD SUCCEEDED **`; `All tests passed.` twice.

- [ ] **Step 5: The picture (the owner's checkpoint): the glow on the compact notch and the open island, light and dark**

**Create `scripts/render-glow.swift`:**

```swift
import AppKit
import SwiftUI

// Draws the island's hover glow (IslandGlowView, IslandGlow.swift) into a PNG without launching NotchMeow: the glow's own SwiftUI view on the app's own island shape (`IslandShape`), the
// compact notch strip and the open island, on a light and a dark menu bar, with the glow on and off for comparison. One still frame (the angle is fixed); the colours are Theme.Glow.
//   bash scripts/render-glow.sh --out hover-glow.png [--scale 2] [--angle 40]
// Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift.

@main
struct RenderGlow {
    struct Panel: View {
        let title: String
        let dark: Bool
        let expanded: Bool
        let glow: Bool
        let angle: Double

        var body: some View {
            let w: CGFloat = expanded ? 640 : 360, h: CGFloat = expanded ? 160 : 32
            let shape = IslandShape(width: w, height: h, cornerRadius: expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner, topRadius: 0)
            ZStack(alignment: .topLeading) {
                // The menu bar and the wallpaper under it.
                Rectangle().fill(dark ? Color(hex: "#1D1E22") : Color(hex: "#D9DCE2"))
                Rectangle().fill(dark ? Color(hex: "#2A2B31") : Color(hex: "#EEF0F4")).frame(height: 24)
                ZStack(alignment: .topLeading) {
                    shape.fill(Color.black)
                    if glow { IslandGlowView(shape: shape, fixedAngle: angle) }
                }
                .frame(width: w, height: h, alignment: .topLeading)
                .offset(x: (700 - w) / 2, y: 0)
                Text(title).font(.system(size: 10)).foregroundColor(dark ? .white.opacity(0.55) : .black.opacity(0.5)).offset(x: 8, y: (expanded ? 160 : 32) + 14)
            }
            .frame(width: 700, height: expanded ? 200 : 70, alignment: .topLeading)
            .clipped()
        }
    }

    @MainActor static func main() {
        var out = "hover-glow.png", scale = 2.0, angle = 40.0
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? out
            case "--scale": scale = Double(it.next() ?? "") ?? scale
            case "--angle": angle = Double(it.next() ?? "") ?? angle
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        _ = NSApplication.shared
        let sheet = VStack(spacing: 0) {
            HStack(spacing: 0) {
                Panel(title: "compact, light menu bar, glow on", dark: false, expanded: false, glow: true, angle: angle)
                Panel(title: "compact, dark menu bar, glow on", dark: true, expanded: false, glow: true, angle: angle)
            }
            HStack(spacing: 0) {
                Panel(title: "open, light, glow on", dark: false, expanded: true, glow: true, angle: angle)
                Panel(title: "open, dark, glow on", dark: true, expanded: true, glow: true, angle: angle)
            }
            HStack(spacing: 0) {
                Panel(title: "compact, light, glow off (Settings)", dark: false, expanded: false, glow: false, angle: angle)
                Panel(title: "open, dark, glow off (Settings)", dark: true, expanded: true, glow: false, angle: angle)
            }
        }
        let host = NSHostingView(rootView: sheet.fixedSize())
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((size.width * scale).rounded()), pixelsHigh: Int((size.height * scale).rounded()), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        do { try png.write(to: URL(fileURLWithPath: out)) } catch { FileHandle.standardError.write(Data("cannot write \(out)\n".utf8)); exit(1) }
        print("wrote \(out) (\(Int(size.width)) x \(Int(size.height)) pt at \(scale)x)")
    }
}
```

**Create `scripts/render-glow.sh`:**

```bash
#!/usr/bin/env bash
# Draws the island's hover glow (IslandGlowView) on the compact notch and the open island, on a light and a dark menu bar, into a PNG, without launching NotchMeow (see scripts/render-glow.swift).
#   bash scripts/render-glow.sh --out hover-glow.png [--scale 2] [--angle 40]
# The view is the app's own, on the app's own IslandShape, so this compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about two minutes. It runs in a home folder of
# its own through scripts/render-home-guard.sh, which kills it if it ever opens the real ~/.claude, ~/.gemini or ~/.codex. It touches no preferences.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-glow.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$BUILD_DIR/home"
APP=NotchBuddy/Sources/App
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$APP" -name '*.swift' ! -name NotchBuddyApp.swift | sort)
swiftc -swift-version 6 -suppress-warnings "${FILES[@]}" scripts/render-glow.swift -o "$BUILD_DIR/render-glow"
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/render-glow" "$@"
```

```bash
chmod +x scripts/render-glow.sh && bash -n scripts/render-glow.sh
mkdir -p ${TMPDIR:-/tmp}/u1 .claude/checkpoints/u1
bash scripts/render-glow.sh --out ${TMPDIR:-/tmp}/u1/hover-glow.png        # about seven minutes: run it in the background
```

Expected: `wrote …hover-glow.png (1400 x 470 pt at 2.0x)`. Open it and say what you see against this: a sheet of six panels; the four "glow on" panels (compact and open, on a light and a dark menu bar) show a 3 pt multicolour edge (blue, purple, pink, orange) along the island's outline, and under it a soft wide halo; the two "glow off" panels show the plain black island. **The dry run's picture showed the edge sharp and correct, and no halo**: the `blur(radius: 8)` layer did not appear in the offscreen `cacheDisplay` render (the edge's own `blur(1.2)` did). Fix that first: wrap the view's `ZStack` in `.drawingGroup()` (it rasterises the blurred layers through Metal, which `cacheDisplay` does reproduce) and render again; if the halo shows in the app but not in the sheet, say so and keep the sheet honest about it in its caption. Also in the dry run the third row of the sheet had uneven panel heights (white gaps): give every panel a fixed 200 pt (open) or 70 pt (compact) frame so rows align. Copy the picture into `.claude/checkpoints/u1/`. **Stop here and report to the main session (the checkpoint):** the owner decides width, blur, halo strength and speed (`IslandGlow`'s constants: one place), and says whether the glow sits well on the compact notch, where it touches the screen's top edge.

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add shared/theme.json scripts/gen-theme.mjs tests/theme/gen-theme.test.mjs NotchBuddy/Sources/App/Theme.generated.swift windows/src/theme.generated.css windows/src/theme.generated.ts NotchBuddy/Sources/App/IslandGlow.swift NotchBuddy/Sources/App/IslandGlowView.swift tests/IslandGlowTests.swift scripts/test-island-glow.sh scripts/render-glow.swift scripts/render-glow.sh NotchBuddy/Sources/App/IslandRootView.swift NotchBuddy/Sources/App/IslandWindowController.swift NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/SettingsView.swift scripts/test-u1-wiring.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F - <<'EOF'
feat(mac): hover glow, a soft rainbow halo along the island's outline while the pointer is over it

Blue, purple, pink and orange (shared/theme.json, glow group), a slowly turning angular gradient about 3 pt wide, fading in and out over 0.2 s, on the
compact notch and the open island. In the view tree only while hovered (no animation, timer or layer otherwise), a still glow under Reduce Motion,
and a Settings switch (General, Behavior; key island.hoverGlow; on by default). The poll writes the hover only when it changes.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 11: The hover glow on Windows/Linux

**Files:**
- Create: `windows/scripts/cat-tests/hover-glow.test.mjs`
- Modify: `windows/src/style.css`, `windows/src/island/island.ts`, `windows/src/core/state.ts`, `windows/src/settings/main.ts`, `windows/src-tauri/src/settings.rs`

**Interfaces:**
- Consumes: the theme's `--nm-glow-*` custom properties (Task 10, already in `windows/src/theme.generated.css`), `Island.wasInIsland` (the cursor handler's hover record, Task 7's version).
- Produces: `Settings.hoverGlow` (default true; Rust `Settings.hover_glow`, `#[serde(default = "default_true")]`), `Island.syncGlow()`.

**Design.** The island is a rounded `div`; its two pseudo-elements are the glow: a conic-gradient ring cut to a 3 px frame by a mask (`padding: 3px`, `mask-composite: exclude`), the first blurred 1.2 px (the edge), the second 8 px (the halo), behind the island's content (`z-index: -1`; `#island` is a stacking context because of `will-change`). They turn through a registered `@property --nm-glow-angle` (a gradient cannot be animated otherwise); where `@property` is unsupported (an old WebKitGTK) the glow is simply still. **Costless otherwise:** the class `glow` (the setting) is what gives the pseudo-elements their box at all; they are `visibility: hidden; opacity: 0` with the animation **paused** until the class `hovered` appears; on leave the opacity fades over 0.2 s while the visibility flips after it, and the paused animation holds its angle so the fading glow does not jump. Reduce motion: `animation: none`. `hovered` follows `wasInIsland` (the pointer in the island's rectangle plus the 14 px margin: the same notion of "over the island" the FSM uses), the setting and a mode that is not hidden.

- [ ] **Step 1: The test first**

**Create `windows/scripts/cat-tests/hover-glow.test.mjs`:**

```javascript
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { DEFAULT_SETTINGS } from "../../src/core/state.ts";
import { THEME } from "../../src/theme.generated.ts";

const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const css = source("style.css");
const glowCss = css.slice(css.indexOf("The hover glow"), css.indexOf("#bot-canvas,\n#greeting-canvas"));

test("the hover glow is on by default and its four colours are the theme's", () => {
  assert.equal(DEFAULT_SETTINGS.hoverGlow, true);
  assert.deepEqual(Object.keys(THEME.glow), ["blue", "purple", "pink", "orange"]);
  for (const name of ["blue", "purple", "pink", "orange"]) assert.match(glowCss, new RegExp(`var\\(--nm-glow-${name}\\)`), name);
  assert.doesNotMatch(glowCss, /#[0-9a-fA-F]{6}\b/, "no colour is typed in the glow's CSS: they come from shared/theme.json");
});

test("the glow's CSS draws only while hovered: hidden and paused otherwise, and still under reduced motion", () => {
  assert.match(glowCss, /@property --nm-glow-angle/);
  assert.match(glowCss, /#island\.glow::before,\s*#island\.glow::after \{[\s\S]*?opacity: 0;[\s\S]*?visibility: hidden;[\s\S]*?animation: nm-glow-turn 8s linear infinite paused;/);
  assert.match(glowCss, /#island\.glow\.hovered::before,\s*#island\.glow\.hovered::after \{[\s\S]*?opacity: 1;[\s\S]*?animation-play-state: running;/);
  assert.match(glowCss, /transition: opacity 0\.2s ease/, "it fades over 0.2 s");
  assert.match(glowCss, /@media \(prefers-reduced-motion: reduce\) \{[\s\S]*?animation: none;/);
  assert.match(glowCss, /padding: 3px;/, "a 3 px ring");
  assert.match(glowCss, /pointer-events: none;/, "it never takes a click");
  assert.doesNotMatch(css.replace(glowCss, ""), /nm-glow/, "nothing else uses the glow's names");
});

test("the island toggles the classes from the switch, the pointer and the mode, and Settings has the switch", () => {
  const isl = source("island/island.ts");
  assert.match(isl, /classList\.toggle\("glow", State\.settings\.hoverGlow\)/);
  assert.match(isl, /classList\.toggle\("hovered", State\.settings\.hoverGlow && this\.wasInIsland && State\.mode !== "hidden"\)/);
  assert.match(isl, /if \(inIsland !== wasIn\) this\.syncGlow\(\);/);
  assert.equal((isl.match(/this\.syncGlow\(\);/g) ?? []).length, 4, "constructor, setMode, applySettings and the pointer");
  const settings = source("settings/main.ts");
  assert.match(settings, /label", \{ text: "Hover glow" \}[\s\S]*?settings\.hoverGlow = v/);
});
```

Run: `cd windows && node --experimental-strip-types --test scripts/cat-tests/hover-glow.test.mjs 2>&1 | grep -E "^# (pass|fail)"`
Expected: FAIL: `# fail 3` (`DEFAULT_SETTINGS.hoverGlow` is undefined; `THEME.glow` exists after Task 10 but the CSS and the island do not yet).

- [ ] **Step 2: The CSS**

**Edit `windows/src/style.css`:** find

```css
#bot-canvas,
#greeting-canvas {
```

replace with

```css
/* The hover glow: a soft rainbow halo along the island's outline, about 3 px wide, while the pointer is over the island. The ring is a conic gradient cut to a 3 px
   frame by a mask, blurred, and turned slowly by the registered angle. It exists (content) only while Settings → Hover glow is on, it is drawn only while hovered,
   and its animation is paused (not running) the rest of the time, so a hidden or idle island costs nothing. Reduce motion: a still glow. Colours: shared/theme.json. */
@property --nm-glow-angle {
  syntax: "<angle>";
  inherits: false;
  initial-value: 0deg;
}

@keyframes nm-glow-turn {
  to {
    --nm-glow-angle: 360deg;
  }
}

#island.glow::before,
#island.glow::after {
  content: "";
  position: absolute;
  inset: -3px;
  padding: 3px;
  border-radius: inherit;
  background: conic-gradient(
    from var(--nm-glow-angle),
    var(--nm-glow-blue),
    var(--nm-glow-purple),
    var(--nm-glow-pink),
    var(--nm-glow-orange),
    var(--nm-glow-blue)
  );
  -webkit-mask: linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0);
  -webkit-mask-composite: xor;
  mask: linear-gradient(#000 0 0) content-box exclude, linear-gradient(#000 0 0);
  pointer-events: none;
  z-index: -1;
  opacity: 0;
  visibility: hidden;
  transition: opacity 0.2s ease, visibility 0s linear 0.2s;
  animation: nm-glow-turn 8s linear infinite paused;
}

/* The bright edge, 3 px, softened a little; and the same ring blurred wide for the halo around it. */
#island.glow::before {
  filter: blur(1.2px);
}

#island.glow::after {
  filter: blur(8px);
}

#island.glow.hovered::before,
#island.glow.hovered::after {
  opacity: 1;
  visibility: visible;
  transition: opacity 0.2s ease, visibility 0s;
  animation-play-state: running;
}

#island.glow.hovered::after {
  opacity: 0.8;
}

@media (prefers-reduced-motion: reduce) {
  #island.glow::before,
  #island.glow::after {
    animation: none;
  }
}
#bot-canvas,
#greeting-canvas {
```

- [ ] **Step 3: The island, the setting, the Settings row**

**Edit `windows/src/island/island.ts`:** find

```typescript
    this.root.append(this.wakeStrip, this.islandEl);
    this.applyGeometry();
```

replace with

```typescript
    this.root.append(this.wakeStrip, this.islandEl);
    this.applyGeometry();
    this.syncGlow();
```

**Edit `windows/src/island/island.ts`:** find

```typescript
    State.mode = mode;
    if (mode === "expanded") Sound.play("open");
```

replace with

```typescript
    State.mode = mode;
    this.syncGlow();
    if (mode === "expanded") Sound.play("open");
```

**Edit `windows/src/island/island.ts`:** find

```typescript
    this.wasInIsland = inIsland;
    if (inIsland && !wasIn) {
```

replace with

```typescript
    this.wasInIsland = inIsland;
    if (inIsland !== wasIn) this.syncGlow();
    if (inIsland && !wasIn) {
```

**Edit `windows/src/island/island.ts`:** find

```typescript
    this.fsm.openOnHover = State.settings.openOnHover;
    // The cat block comes from Rust already clean;
```

replace with

```typescript
    this.fsm.openOnHover = State.settings.openOnHover;
    this.syncGlow();
    // The cat block comes from Rust already clean;
```

**Edit `windows/src/island/island.ts`:** find

```typescript
  // ── Window collapse (hidden → tiny wake strip, zero polling) ────────────────
```

replace with

```typescript
  /** The hover glow: the class `glow` while Settings → Hover glow is on, `hovered` while the pointer is over a shown island. The CSS does the rest (style.css). */
  private syncGlow() {
    this.islandEl.classList.toggle("glow", State.settings.hoverGlow);
    this.islandEl.classList.toggle("hovered", State.settings.hoverGlow && this.wasInIsland && State.mode !== "hidden");
  }

  // ── Window collapse (hidden → tiny wake strip, zero polling) ────────────────
```

**Edit `windows/src/core/state.ts`:** find

```typescript
  openOnHover: boolean;
  absenceInterval: number;
```

replace with

```typescript
  openOnHover: boolean;
  /** A soft rainbow halo along the island's outline while the pointer is over it. */
  hoverGlow: boolean;
  absenceInterval: number;
```

**Edit `windows/src/core/state.ts`:** find

```typescript
  openOnHover: false,
  absenceInterval: 180,
```

replace with

```typescript
  openOnHover: false,
  hoverGlow: true,
  absenceInterval: 180,
```

**Edit `windows/src/settings/main.ts`:** find

```typescript
    h("div", { class: "row" },
      h("label", { text: "Auto-close" }),
```

replace with

```typescript
    h("div", { class: "row" },
      h("label", { text: "Hover glow" }),
      toggle(settings.hoverGlow, (v) => { settings.hoverGlow = v; void save(); }),
    ),
    h("div", { class: "hint", text: "A soft rainbow glow along the island's edge while the pointer is over it." }),
    h("div", { class: "row" },
      h("label", { text: "Auto-close" }),
```

**Edit `windows/src-tauri/src/settings.rs`:** find

```rust
    #[serde(default)]
    pub open_on_hover: bool,
```

replace with

```rust
    #[serde(default)]
    pub open_on_hover: bool,
    /// A soft rainbow halo along the island's outline while the pointer is over it (on by default).
    #[serde(default = "default_true")]
    pub hover_glow: bool,
```

**Edit `windows/src-tauri/src/settings.rs`:** find

```rust
            open_on_hover: false,
            absence_interval: 180.0,
```

replace with

```rust
            open_on_hover: false,
            hover_glow: true,
            absence_interval: 180.0,
```

**Edit `windows/src-tauri/src/settings.rs`:** find

```rust
pub use crate::platform::{config_dir, local_dir};
```

replace with

```rust
fn default_true() -> bool {
    true
}

pub use crate::platform::{config_dir, local_dir};
```

**Edit `windows/src-tauri/src/settings.rs`:** find

```rust
    #[test]
    fn a_settings_file_without_open_on_hover_gets_it_off_and_keeps_it_when_set() {
```

replace with

```rust
    #[test]
    fn a_settings_file_without_hover_glow_gets_it_on_and_keeps_it_when_turned_off() {
        let old = r#"{"soundEnabled":true,"soundVolume":0.12,"autoCloseInterval":15,"absenceInterval":180,
            "activeIntegrations":[],"screen":"primary","autostart":false,"hooksInstalled":false}"#;
        let s: Settings = serde_json::from_str(old).unwrap();
        assert!(s.hover_glow);
        assert_eq!(serde_json::to_value(&s).unwrap()["hoverGlow"], true);
        let off: Settings = serde_json::from_str(&old.replace("\"autostart\"", "\"hoverGlow\":false,\"autostart\"")).unwrap();
        assert!(!off.hover_glow);
    }

    #[test]
    fn a_settings_file_without_open_on_hover_gets_it_off_and_keeps_it_when_set() {
```

- [ ] **Step 4: Run everything Windows/Linux**

Run: `cd windows && npx --no-install tsc --noEmit && echo tsc ok && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"`
Expected: `tsc ok`; the three tests of `hover-glow.test.mjs` pass; `ℹ fail 0` (`ℹ tests 389` in the dry run's counting).
Run: `windows/scripts/cargo-linux.sh test --workspace --offline --target-dir /repo/windows/target/u1 2>&1 | grep -E "test result|FAILED|error"` (needs Docker).
Expected: every `test result: ok`.

- [ ] **Step 5: The picture (the owner's checkpoint)**

Serve the repo's `windows/` folder's parent on localhost only (`python3 -m http.server 8765 --bind 127.0.0.1` from the worktree root, saving the PID), write `${TMPDIR:-/tmp}/u1/win-glow.html` that links `/windows/src/theme.generated.css` and `/windows/src/style.css` and holds two `<div id=island class="glow hovered" …>` strips (a 640 by 150 open island with `border-radius: 0 0 22px 22px` on a light backdrop and a 330 by 32 compact one on a dark backdrop, each `position:absolute; left:50%; transform:translateX(-50%)`), open it in the browser pane and screenshot it. Serve the HTML from the same server (put it under the served folder, or point the server at `${TMPDIR:-/tmp}/u1`'s parent). Stop the server by its PID. Expected: a 3 px multicolour ring with a soft halo along both islands' outlines on both backdrops. **The dry run did exactly this** and saw the ring on both, with the halo weaker than the ring (the `::after` blur and opacity are the knobs). Copy the picture to `.claude/checkpoints/u1/`. If the pane refuses a `file://` page, use the localhost server as above (the dry run's pane did).

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add windows/scripts/cat-tests/hover-glow.test.mjs windows/src/style.css windows/src/island/island.ts windows/src/core/state.ts windows/src/settings/main.ts windows/src-tauri/src/settings.rs
git commit -F - <<'EOF'
feat(windows): hover glow, the same soft rainbow halo along the island's outline (CSS), with the same switch

A conic-gradient ring cut to 3 px by a mask, blurred twice (edge and halo), turning through a registered @property angle. It has no box unless
Settings → Hover glow is on, is hidden and paused unless the pointer is over the island, fades over 0.2 s, and is still under reduced motion.
Colours from shared/theme.json.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 12: The Claude Code pill is labelled "Claude Code" (both apps)

**Files:**
- Create: `windows/scripts/cat-tests/pill-labels.test.mjs`
- Modify: `NotchBuddy/Sources/App/PillCatalog.swift`, `IslandViewContent.swift`, `CatDevModel.swift`, `HookOrigin.swift`, `AppState.swift`, `scripts/render-cats.swift`, `scripts/test-u1-wiring.sh`, `windows/src/core/state.ts`, `windows/src/island/hooks.ts`, `windows/src/views/views.ts`, `windows/src/views/integrations.ts`, `windows/src/core/pills.ts`, `windows/src/cat/dev.ts`, `windows/scripts/cat-tests/kittendraw.test.mjs`, `docs/SPEC.md`, `docs/INTEGRATIONS.md`, `CLAUDE.md`

**Interfaces:**
- Produces: nothing new in code. The pill `integration_claude` keeps its **frozen ID**; only its visible label changes, from "VS Code" to "Claude Code": in the island's pill, in Settings → Active pills, in the integration card header and in a Windows/Linux session that has ended. The "Handled in VS Code / Terminal / iTerm…" notes keep naming the host app (`HookOrigin.hostName`, `ApprovalInfo.host`): they say where the user is, not what the pill is called.

The owner's decision of 2026-10-15. The label "VS Code" was the pill's name when only VS Code sessions reached it; since `mac-all-terminals` it is the Claude Code pill for every terminal, so "VS Code" misled. `PillDefinition.sessionSubtitle` already says "Claude Code" for it.

- [ ] **Step 1: The pins first**

**Edit `scripts/test-u1-wiring.sh`:** find

```bash
echo "$pass passed, $fail failed"
```

replace with

```bash
# The Claude Code pill's label (the pill's ID stays integration_claude).
has   "the catalog names the pill Claude Code"  PillCatalog.swift 'id: "integration_claude",  name: "Claude Code"'
hasnt "no VS Code name in the catalog"          PillCatalog.swift 'name: "VS Code"'
hasnt "the pill never shows a fixed VS Code label" IslandViewContent.swift '? "VS Code" : task.name'
has   "the pill shows Claude Code"              IslandViewContent.swift 'task.id == "integration_claude" ? "Claude Code" : task.name'

echo "$pass passed, $fail failed"
```

**Create `windows/scripts/cat-tests/pill-labels.test.mjs`:**

```javascript
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { INTEGRATION_AGENTS } from "../../src/core/state.ts";

const read = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("the Claude Code pill is labelled Claude Code, and its ID is the frozen one", () => {
  const pill = INTEGRATION_AGENTS.find((t) => t.id === "integration_claude");
  assert.ok(pill, "integration_claude still exists");
  assert.equal(pill.name, "Claude Code");
  assert.equal(pill.color, "#F5F6F8", "its colour did not change");
});

test("no source of the pill, its card or its reset still says VS Code as the pill's label", () => {
  assert.match(read("island/hooks.ts"), /t\.name = "Claude Code";/);
  assert.match(read("views/views.ts"), /const label = task\.id === "integration_claude" \? "Claude Code" : task\.name;/);
  assert.match(read("views/integrations.ts"), /task\.id === "integration_claude" \? "Claude Code" : task\.name/);
  for (const f of ["island/hooks.ts", "views/views.ts", "views/integrations.ts", "core/state.ts"]) {
    assert.doesNotMatch(read(f), /"VS Code"/, `${f} has no "VS Code" label`);
  }
});
```

Run: `bash scripts/test-u1-wiring.sh | tail -6 && cd windows && node --experimental-strip-types --test scripts/cat-tests/pill-labels.test.mjs 2>&1 | grep -E "^# (pass|fail)"`
Expected: FAIL: the wiring pins `✗` (the catalog still says VS Code) and `# fail 2` for the Windows test.

- [ ] **Step 2: The Mac label**

**Edit `NotchBuddy/Sources/App/PillCatalog.swift`:** find

```swift
        .init(id: "integration_claude",  name: "VS Code",     color: "#F5F6F8",
```

replace with

```swift
        .init(id: "integration_claude",  name: "Claude Code", color: "#F5F6F8",
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`:** find

```swift
    // VS Code pill always shows "VS Code" label regardless of active project name
    private var displayName: String {
        task.id == "integration_claude" ? "VS Code" : task.name
    }
```

replace with

```swift
    // The Claude Code pill always shows "Claude Code" regardless of the active project name (its ID, integration_claude, is frozen)
    private var displayName: String {
        task.id == "integration_claude" ? "Claude Code" : task.name
    }
```

**Edit `NotchBuddy/Sources/App/CatDevModel.swift`:** find

```swift
("Cursor", "#C0C4CC"), ("VS Code", "#F5F6F8")]
```

replace with

```swift
("Cursor", "#C0C4CC"), ("Claude Code pill", "#F5F6F8")]
```

**Edit `scripts/render-cats.swift`:** find

```swift
("Cursor", "#C0C4CC"), ("VS Code", "#F5F6F8")]
```

replace with

```swift
("Cursor", "#C0C4CC"), ("Claude Code pill", "#F5F6F8")]
```

**Edit `NotchBuddy/Sources/App/HookOrigin.swift`:** find

```swift
The pill's ID and its "VS Code" label do not change.
```

replace with

```swift
The pill's ID does not change, and its label is "Claude Code" (it was "VS Code" until U1).
```

**Edit `NotchBuddy/Sources/App/AppState.swift`:** find

```swift
    // The always-on workspace pill (default: VS Code). Persisted.
```

replace with

```swift
    // The always-on workspace pill (default: Claude Code). Persisted.
```

- [ ] **Step 3: The Windows/Linux label**

**Edit `windows/src/core/state.ts`:** find

```typescript
  task("integration_claude", "VS Code", "#F5F6F8", "claudeCode"),
```

replace with

```typescript
  task("integration_claude", "Claude Code", "#F5F6F8", "claudeCode"),
```

**Edit `windows/src/island/hooks.ts`:** find

```typescript
  t.name = "VS Code";
```

replace with

```typescript
  t.name = "Claude Code";
```

**Edit `windows/src/views/views.ts`:** find

```typescript
  const label = task.id === "integration_claude" ? "VS Code" : task.name;
```

replace with

```typescript
  const label = task.id === "integration_claude" ? "Claude Code" : task.name;
```

**Edit `windows/src/views/integrations.ts`:** find

```typescript
task.id === "integration_claude" ? "VS Code" : task.name
```

replace with

```typescript
task.id === "integration_claude" ? "Claude Code" : task.name
```

**Edit `windows/src/core/pills.ts`:** find

```typescript
`integration_claude` is Claude Code (its pill on the island is
 * still labelled "VS Code"), `agent_<tag>` is the agent's name.
```

replace with

```typescript
`integration_claude` is Claude Code (its pill on the island is
 * labelled the same), `agent_<tag>` is the agent's name.
```

**Edit `windows/src/core/pills.ts`:** find

```typescript
/** The colour of an agent pill: the VS Code pill's for Claude Code,
```

replace with

```typescript
/** The colour of an agent pill: the Claude Code pill's for Claude Code,
```

**Edit `windows/src/cat/dev.ts`:** find

```typescript
["#F5F6F8", "VS Code pill"]
```

replace with

```typescript
["#F5F6F8", "Claude Code pill"]
```

**Edit `windows/scripts/cat-tests/kittendraw.test.mjs`:** find

```javascript
{ id: "integration_claude", name: "VS Code", color: "#F5F6F8",
```

replace with

```javascript
{ id: "integration_claude", name: "Claude Code", color: "#F5F6F8",
```

- [ ] **Step 4: The docs that show the old label** (`CLAUDE.md`'s HookOrigin bullet: owner-approved; the two others are French by design)

**Edit `CLAUDE.md`:** find

```markdown
(`integration_claude`, labelled "VS Code")
```

replace with

```markdown
(`integration_claude`, labelled "Claude Code")
```

**Edit `docs/SPEC.md`:** find

```markdown
| `workspace` | Where you code | VS Code, Cursor, Antigravity
```

replace with

```markdown
| `workspace` | Where you code | Claude Code, Cursor, Antigravity
```

**Edit `docs/SPEC.md`:** find

```markdown
la pastille VS Code est chargée seulement si une session VS Code est active (transient)
```

replace with

```markdown
la pastille Claude Code est chargée seulement si une session Claude Code est active (transient)
```

**Edit `docs/SPEC.md`:** find

```markdown
(VS Code toujours actif + jusqu'à 4 autres)
```

replace with

```markdown
(Claude Code toujours actif + jusqu'à 4 autres)
```

**Edit `docs/INTEGRATIONS.md`:** find

```markdown
libellée « VS Code »
```

replace with

```markdown
libellée « Claude Code »
```

Then look once for any other place that shows the label: `grep -rn '"VS Code"' NotchBuddy/Sources windows/src` must print only host-app lines (`HookOrigin.hostName`, `ApprovalInfo.host`: where the user is, not the pill's name). `windows/README.md` line about "VS Code sessions" is about a host, not the label: leave it.

- [ ] **Step 5: Run the checks**

```bash
bash scripts/test-u1-wiring.sh | tail -1
bash scripts/test-hook-origin.sh 2>&1 | tail -1
bash scripts/check-no-leftovers.sh 2>&1 | tail -1
(cd windows && node --experimental-strip-types --test scripts/cat-tests/pill-labels.test.mjs 2>&1 | grep -E "^# (pass|fail)" && npx --no-install tsc --noEmit && echo tsc ok && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)")
```

Expected: the wiring script's last line `N passed, 0 failed` with the four new lines passing; `All tests passed.`; the leftovers guard's `✓`; `# pass 2`, `# fail 0`; `tsc ok`; `check:cat` `ℹ fail 0` (the new file adds 2 tests).

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add windows/scripts/cat-tests/pill-labels.test.mjs NotchBuddy/Sources/App/PillCatalog.swift NotchBuddy/Sources/App/IslandViewContent.swift NotchBuddy/Sources/App/CatDevModel.swift NotchBuddy/Sources/App/HookOrigin.swift NotchBuddy/Sources/App/AppState.swift scripts/render-cats.swift scripts/test-u1-wiring.sh windows/src/core/state.ts windows/src/island/hooks.ts windows/src/views/views.ts windows/src/views/integrations.ts windows/src/core/pills.ts windows/src/cat/dev.ts windows/scripts/cat-tests/kittendraw.test.mjs docs/SPEC.md docs/INTEGRATIONS.md CLAUDE.md
git commit -F - <<'EOF'
feat: the integration_claude pill is labelled "Claude Code", not "VS Code" (both apps)

The ID is frozen and unchanged. The "Handled in VS Code / Terminal / iTerm" notes still name the host app. The label, Settings → Active pills,
the integration card, the Windows/Linux reset, the tests, the pins and the docs that showed the old label now say Claude Code.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 13: A pill for Claude Code sessions from the Claude desktop app (upstream 344dc12, #191)

**Files:**
- Create: `scripts/render-pills.swift`, `scripts/render-pills.sh`
- Modify: `NotchBuddy/Sources/App/HookOrigin.swift`, `PillCatalog.swift`, `AgentTarget.swift`, `IslandViewContent.swift`, `SidekickText.swift`, `tests/SidekickWiringTests.swift`, `HookServer.swift` (both embedded relays and `upsertExternalAgent`), `tests/HookOriginTests.swift`, `scripts/test-hook-relay.sh`, `scripts/test-u1-wiring.sh`, `windows/hook/src/agents.rs`, `windows/hook/src/main.rs`, `windows/src/core/pills.ts`, `windows/src/island/hooks.ts`, `windows/scripts/cat-tests/pills.test.mjs`, `docs/AGENTS.md` (if it exists; else `docs/INTEGRATIONS.md`)

**Interfaces:**
- Produces: the frozen pill ID **`agent_claude-desktop`** (the tag `claude-desktop`, the visible name "Claude App"; the notes "Handled in Claude Desktop" keep the full name); `HookOrigin.desktopTag`, `HookOrigin.desktopPill`, `HookOrigin.desktopBundleId`, `HookOrigin.agentTag(explicit:entrypoint:) -> String`; Rust `agents::CLAUDE_DESKTOP` and `agents::agent_tag(arg: &str, entrypoint: &str) -> String`; Windows `agentPillName(tag)`.
- Consumes: the `nm_agent` routing that exists (`HookOrigin.route` makes any valid tag an external agent, `agent_<tag>`; `validateAgent` accepts hyphens; an external agent's PermissionRequest is answered `ask`, so Claude Desktop shows its own prompt).

**What upstream's change shows, and why the ID is `agent_claude-desktop` and not `integration_claude_desktop`.** The owner suggested `integration_claude_desktop` and asked to verify from upstream rather than guess. Upstream (344dc12, with Windows/Linux in 7262361 and c90d30b) does not route by a bundle ID: **a Claude Code session started from the Claude desktop app's Code tab sets the environment variable `CLAUDE_CODE_ENTRYPOINT=claude-desktop`**, and the hook relay (which runs in that environment) tags the event with the agent name `claude-desktop` when no `--agent` was given; the app then routes by tag like any agent, to the pill `agent_<tag>`. The bundle ID `com.anthropic.claudefordesktop` is used only to open the Claude app from the pill's jump button and the finished card. NotchMeow routes tagged agents the same way (`agent_<tag>`: `agent_gemini`, `agent_antigravity`), so **the ID that follows the rule, and matches upstream's, is `agent_claude-desktop`**; an `integration_*` ID would need a second routing path and would collide with the rule that `integration_*` pills are persistent. The owner's answers (2026-10-15) list this ID as frozen. Colour and icon are NotchMeow's own: `#E3A857` (not upstream's); pills are drawn as cat heads, so there is no icon asset to port.

**What each app gets.** Mac: the pill in the catalog (every build, declarable in Settings → Active pills, kept idle after a session ends), the relay tag in both embedded relays, the pill's jump button and the finished card's button open the Claude app ("Open Claude"), a name and colour of its own for the transient pill, the sidekick's name for it, and "Handled in Claude Desktop" notes. Windows/Linux: the relay tag (`agents.rs`, `main.rs`), the pill's colour and label (`pills.ts`), so the session shows as its own pill; **"Open Claude" on Windows/Linux is a follow-up** (upstream's `open_claude_desktop` in `src-tauri` is per-OS platform code that needs Docker), and the Windows/Linux catalog has no declarable agent pills yet (the pill appears while a session runs).

- [ ] **Step 1: The Mac rules, their test first**

**Edit `tests/HookOriginTests.swift`:** find

```swift
        CT.finish()
    }
}
```

replace with

```swift
        CT.section("a session from the Claude desktop app has its own pill (upstream 344dc12: the tag comes from CLAUDE_CODE_ENTRYPOINT)")
        CT.check("the entrypoint tags the event when no --agent was given", O.agentTag(explicit: "", entrypoint: "claude-desktop"), "claude-desktop")
        CT.check("an explicit --agent wins over the entrypoint", O.agentTag(explicit: "gemini", entrypoint: "claude-desktop"), "gemini")
        CT.check("any other entrypoint (the CLI, VS Code, the SDK) is untagged", [O.agentTag(explicit: "", entrypoint: "cli"), O.agentTag(explicit: "", entrypoint: "vscode"), O.agentTag(explicit: "", entrypoint: "")], ["", "", ""])
        CT.check("no entrypoint at all is untagged", O.agentTag(explicit: "", entrypoint: nil), "")
        CT.check("the tag is exact: a look-alike entrypoint is not Claude Desktop", O.agentTag(explicit: "", entrypoint: "Claude-Desktop"), "")
        CT.check("the tag is a valid agent name, so the event is an external agent", route("claude-desktop", valid: "claude-desktop", bundle: "com.anthropic.claudefordesktop"), .external("claude-desktop"))
        CT.check("its pill ID is agent_claude-desktop, the frozen one", O.pillId(route("claude-desktop", valid: "claude-desktop")), "agent_claude-desktop")
        CT.check("the constants agree", [O.desktopTag, O.desktopPill, O.desktopBundleId], ["claude-desktop", "agent_claude-desktop", "com.anthropic.claudefordesktop"])
        CT.check("the notes name the app the user is in", O.hostName(pillId: "agent_claude-desktop", termProgram: "", bundleId: ""), "Claude Desktop")

        CT.finish()
    }
}
```

Run: `bash scripts/test-hook-origin.sh 2>&1 | tail -4`
Expected: FAIL: a compile error, `type 'HookOrigin' has no member 'agentTag'`.

**Edit `NotchBuddy/Sources/App/HookOrigin.swift`:** find

```swift
    static let cursorBundleId = "com.todesktop.230313mzl4w4u92"
```

replace with

```swift
    static let cursorBundleId = "com.todesktop.230313mzl4w4u92"

    /// Claude Code sessions started from the Claude desktop app (its Code tab) set `CLAUDE_CODE_ENTRYPOINT=claude-desktop` and run in no terminal. The relay tags them with this agent name
    /// when no `--agent` was given, so they reach their own pill (`agent_claude-desktop`, a frozen ID); the bundle ID is only what the pill's button opens.
    static let desktopTag = "claude-desktop"
    static let desktopPill = "agent_claude-desktop"
    static let desktopBundleId = "com.anthropic.claudefordesktop"

    /// The relay's tag rule, which the two Python relays in `HookServer.swift` repeat (`scripts/test-hook-relay.sh` runs them): an explicit `--agent` wins, else the entrypoint says Claude Desktop, else no tag.
    static func agentTag(explicit: String, entrypoint: String?) -> String {
        if !explicit.isEmpty { return explicit }
        return entrypoint == desktopTag ? desktopTag : ""
    }
```

**Edit `NotchBuddy/Sources/App/HookOrigin.swift`:** find

```swift
        case "agent_codex": return "Codex"
        case "integration_claude":
```

replace with

```swift
        case "agent_codex": return "Codex"
        case "agent_claude-desktop": return "Claude Desktop"
        case "integration_claude":
```

Run: `bash scripts/test-hook-origin.sh 2>&1 | tail -3`
Expected: PASS: `All tests passed.` (the nine new checks included).

- [ ] **Step 2: The relays: run for real, with a socket the test listens on (red first)**

The two embedded Python relays send the event to the app's Unix socket and print nothing the test could read, so the test listens on the socket the relay will open and reads the `nm_agent` it sent. A socket path is limited to 104 bytes, so the test's home folder is a short one in `/tmp`.

**Edit `scripts/test-hook-relay.sh`:** find

```bash
echo "$pass passed, $fail failed"
```

replace with

```bash
# The entrypoint tag (upstream 344dc12): a Claude Code session from the Claude desktop app (CLAUDE_CODE_ENTRYPOINT=claude-desktop) is tagged nm_agent "claude-desktop" when no --agent was
# given; an explicit --agent wins; any other entrypoint stays untagged. The test listens on the socket the relay opens and reads what it sent. (A socket path is limited to 104 bytes: short home.)
SOCK_HOME="$(mktemp -d /tmp/nmr.XXXXXX)"
trap 'rm -rf "$TEST_DIR" "$SOCK_HOME"' EXIT
cat > "$TEST_DIR/tag-test.py" <<'PY'
import json, os, socket, subprocess, sys
test_dir, home = sys.argv[1], sys.argv[2]
SOCKS = {"github": "Library/Application Support/NotchMeow/nm.sock",
         "appstore": "Library/Containers/io.github.aikusan.notchmeow.store/Data/nm.sock"}
CASES = [("claude-desktop", [], "claude-desktop", "a desktop session is tagged claude-desktop"),
         ("claude-desktop", ["--agent", "gemini"], "gemini", "an explicit --agent wins over the entrypoint"),
         ("cli", [], None, "the CLI entrypoint is untagged"),
         ("vscode", [], None, "the VS Code entrypoint is untagged"),
         ("Claude-Desktop", [], None, "a look-alike entrypoint is untagged"),
         (None, [], None, "no entrypoint is untagged")]
for label, rel in SOCKS.items():
    path = os.path.join(home, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for entry, extra, want, name in CASES:
        if os.path.exists(path): os.remove(path)
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(path); srv.listen(1); srv.settimeout(5)
        env = {"HOME": home, "PATH": os.environ.get("PATH", "")}
        if entry is not None: env["CLAUDE_CODE_ENTRYPOINT"] = entry
        p = subprocess.Popen([sys.executable, "-I", f"{test_dir}/nm-hook-{label}.py", *extra, "Stop"], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
        p.stdin.write(b'{"hook_event_name":"Stop","session_id":"s1","cwd":"/tmp/p"}'); p.stdin.close()
        got = "no connection"
        try:
            conn, _ = srv.accept(); conn.settimeout(5)
            buf = b""
            while b"\n" not in buf:
                chunk = conn.recv(4096)
                if not chunk: break
                buf += chunk
            got = json.loads(buf.decode()).get("nm_agent")
        except Exception as e:
            got = repr(e)
        p.wait(10); srv.close()
        print(("PASS " if got == want else "FAIL ") + f"{label}: {name} (got {got!r})")
PY
# (the script is written to a file first: bash 3.2 mangles a heredoc inside a process substitution)
while IFS= read -r line; do
    case "$line" in
        PASS*) pass=$((pass + 1)); echo "✓ ${line#PASS }" ;;
        FAIL*) fail=$((fail + 1)); echo "✗ ${line#FAIL }" ;;
    esac
done < <(python3 -I "$TEST_DIR/tag-test.py" "$TEST_DIR" "$SOCK_HOME")

echo "$pass passed, $fail failed"
```

Run: `bash -n scripts/test-hook-relay.sh && bash scripts/test-hook-relay.sh | tail -14`
Expected: FAIL: the two `a desktop session is tagged claude-desktop` lines (`got None`), for `github` and `appstore`; the other ten new lines pass (they pin what must not change).

**Edit `NotchBuddy/Sources/App/HookServer.swift`:** find

```python
    if agent:
        payload.setdefault('nm_agent', agent)
```

replace with

```python
    if agent:
        payload.setdefault('nm_agent', agent)
    # A Claude Code session started from the Claude desktop app (its Code tab) says so in CLAUDE_CODE_ENTRYPOINT and has no --agent:
    # it gets its own pill (agent_claude-desktop). An explicit --agent wins.
    if not payload.get('nm_agent') and os.environ.get('CLAUDE_CODE_ENTRYPOINT') == 'claude-desktop':
        payload['nm_agent'] = 'claude-desktop'
```

This text occurs **twice** in `HookServer.swift` (the GitHub relay and the App Store relay): replace **both**.

Run: `bash scripts/test-hook-relay.sh | tail -3`
Expected: PASS: `28 passed, 0 failed` (the sixteen of Task 1 and the twelve new).

- [ ] **Step 3: The pill, its name and colour, its buttons**

**Edit `NotchBuddy/Sources/App/PillCatalog.swift`:** find

```swift
        case "agent_codex":        return "Codex"
        default:                   return "Agent"
```

replace with

```swift
        case "agent_codex":        return "Codex"
        case "agent_claude-desktop": return "Claude App"
        default:                   return "Agent"
```

**Edit `NotchBuddy/Sources/App/PillCatalog.swift`:** find

```swift
        // ── AI for the chat ──────────────────────────────────────────────────
        .init(id: "ai_anthropic",
```

replace with

```swift
        // Claude Code sessions run from the Claude desktop app: the relay tags them `nm_agent: claude-desktop` from CLAUDE_CODE_ENTRYPOINT, so there is nothing to install.
        .init(id: "agent_claude-desktop", name: "Claude App", color: "#E3A857",
              category: .agent,     subtitle: "Agent",        source: .agent),
        // ── AI for the chat ──────────────────────────────────────────────────
        .init(id: "ai_anthropic",
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`:** find

```swift
        let color = IslandConst.colorForProject(name)
        let task = AgentTask(id: id, name: name, color: color, state: .idle, steps: [], source: .agent)
```

replace with

```swift
        // Claude Desktop's pill is labelled and coloured as the catalogue has it; every other agent's transient pill is as it always was (its tag, a colour picked by name).
        let own = id == HookOrigin.desktopPill ? PillCatalog.definition(for: id) : nil
        let color = own?.color ?? IslandConst.colorForProject(name)
        let task = AgentTask(id: id, name: own?.name ?? name, color: color, state: .idle, steps: [], source: .agent)
```

**Edit `NotchBuddy/Sources/App/AgentTarget.swift`:** find

```swift
        case "agent_gemini", "agent_antigravity":
            #if !APPSTORE
            let terminalBundleIds
```

replace with

```swift
        case HookOrigin.desktopPill:
            // Sessions from the Claude desktop app live there, not in a terminal.
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: HookOrigin.desktopBundleId) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
        case "agent_gemini", "agent_antigravity":
            #if !APPSTORE
            let terminalBundleIds
```

**Edit `tests/SidekickWiringTests.swift`:** find

```swift
view.contains("case \"integration_claude\", \"agent_cursor\", \"agent_codex\", \"agent_gemini\", \"agent_antigravity\":\n            AgentTarget.bringForward(pillId: task.id)")
```

replace with

```swift
view.contains("case \"integration_claude\", \"agent_cursor\", \"agent_codex\", \"agent_gemini\", \"agent_antigravity\", HookOrigin.desktopPill:\n            AgentTarget.bringForward(pillId: task.id)")
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`:** find

```swift
        case "integration_claude", "agent_cursor", "agent_codex", "agent_gemini", "agent_antigravity":
```

replace with

```swift
        case "integration_claude", "agent_cursor", "agent_codex", "agent_gemini", "agent_antigravity", HookOrigin.desktopPill:
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`:** find

```swift
                HStack(spacing: 8) {
                    #if !APPSTORE
                    PrimaryButton("Open terminal") {
                        let terminalBundleIds = ["com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
                        let activated = terminalBundleIds.compactMap { id in
                            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
                        }.first.map { $0.activate(options: .activateIgnoringOtherApps) }
                        if activated == nil {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                        }
                        NotificationCenter.default.post(name: .islandCollapse, object: nil)
                    }
                    #endif
```

replace with

```swift
                HStack(spacing: 8) {
                    if state.focusTask?.id == HookOrigin.desktopPill {
                        // Sessions from the Claude desktop app live there, not in a terminal.
                        PrimaryButton("Open Claude") {
                            AgentTarget.bringForward(pillId: HookOrigin.desktopPill)
                            NotificationCenter.default.post(name: .islandCollapse, object: nil)
                        }
                    } else {
                        #if !APPSTORE
                        PrimaryButton("Open terminal") {
                            let terminalBundleIds = ["com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
                            let activated = terminalBundleIds.compactMap { id in
                                NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
                            }.first.map { $0.activate(options: .activateIgnoringOtherApps) }
                            if activated == nil {
                                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                            }
                            NotificationCenter.default.post(name: .islandCollapse, object: nil)
                        }
                        #endif
                    }
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`:** find

```swift
        case "agent_cursor", "agent_codex":
            return false  // coming soon
```

replace with

```swift
        case HookOrigin.desktopPill:
            return true   // nothing to install: the relay tags desktop sessions on its own
        case "agent_cursor", "agent_codex":
            return false  // coming soon
```

**Edit `NotchBuddy/Sources/App/SidekickText.swift`:** find

```swift
        case "agent_antigravity": return "Antigravity"
```

replace with

```swift
        case "agent_antigravity": return "Antigravity"
        case "agent_claude-desktop": return "Claude App"
```

- [ ] **Step 4: The pins and the picture**

**Edit `scripts/test-u1-wiring.sh`:** find

```bash
echo "$pass passed, $fail failed"
```

replace with

```bash
# The Claude Desktop pill (agent_claude-desktop, a frozen ID).
has   "the catalog declares the pill"           PillCatalog.swift 'id: "agent_claude-desktop", name: "Claude App", color: "#E3A857"'
has   "its session subtitle"                    PillCatalog.swift 'case "agent_claude-desktop": return "Claude App"'
has   "the relays tag the entrypoint"           HookServer.swift "os.environ.get('CLAUDE_CODE_ENTRYPOINT') == 'claude-desktop'"
has   "its transient pill is named by the catalogue" HookServer.swift "let own = id == HookOrigin.desktopPill ? PillCatalog.definition(for: id) : nil"
has   "the pill's jump opens the Claude app"    AgentTarget.swift "case HookOrigin.desktopPill:"
has   "the finished card offers Open Claude"    IslandViewContent.swift 'PrimaryButton("Open Claude")'
has   "nothing to install"                      IslandViewContent.swift "return true   // nothing to install"
has   "the sidekick names it"                   SidekickText.swift 'case "agent_claude-desktop": return "Claude App"'

echo "$pass passed, $fail failed"
```

**Create `scripts/render-pills.swift`:**

```swift
import AppKit
import SwiftUI

// Draws the island's agent pills (AgentPill, in IslandViewContent.swift) into a PNG without launching NotchMeow: the app's own pill view on a black strip, for the Claude Code pill (its label is
// "Claude Code"), Claude Desktop (a session from the Claude desktop app) and two agents for comparison, each with the cat the app gives it.
//   bash scripts/render-pills.sh --out pills.png [--scale 2]
// Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift.

@main
struct RenderPills {
    @MainActor static func main() {
        var out = "pills.png", scale = 2.0
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? out
            case "--scale": scale = Double(it.next() ?? "") ?? scale
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        _ = NSApplication.shared
        let state = AppState.shared
        let defs = ["integration_claude", "agent_claude-desktop", "agent_gemini", "agent_cursor"].compactMap { PillCatalog.definition(for: $0) }
        let tasks = defs.map { AgentTask(id: $0.id, name: $0.id == "agent_claude-desktop" ? $0.name : $0.name, color: $0.color, state: .idle, steps: [], source: $0.source) }
        state.tasks = tasks
        let row = HStack(spacing: 8) {
            ForEach(tasks, id: \.id) { task in
                AgentPill(task: task, cat: "shrimpy", state: state, swapping: .constant(false)) {}
                    .frame(width: 134)
            }
        }
        .padding(14)
        .background(Color.black)
        .foregroundColor(Color(hex: "#F5F6F8"))
        let host = NSHostingView(rootView: row.fixedSize())
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((size.width * scale).rounded()), pixelsHigh: Int((size.height * scale).rounded()), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        do { try png.write(to: URL(fileURLWithPath: out)) } catch { FileHandle.standardError.write(Data("cannot write \(out)\n".utf8)); exit(1) }
        print("wrote \(out) (\(Int(size.width)) x \(Int(size.height)) pt at \(scale)x): \(tasks.map(\.name).joined(separator: ", "))")
        // The tool's own AppState saved a few defaults into the tool's domain: the .sh deletes them.
    }
}
```

**Create `scripts/render-pills.sh`:**

```bash
#!/usr/bin/env bash
# Draws the island's agent pills (AgentPill): Claude Code, Claude Desktop and two agents, into a PNG, without launching NotchMeow (see scripts/render-pills.swift).
#   bash scripts/render-pills.sh --out pills.png [--scale 2]
# AgentPill reads the app's AppState, so this compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about seven minutes. It runs in a home folder of its own through
# scripts/render-home-guard.sh, which kills it if it ever opens the real ~/.claude, ~/.gemini or ~/.codex.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-pills.XXXXXX")"
REAL_HOME="$HOME"
cleanup() {
    rm -rf "$BUILD_DIR"
    defaults delete render-pills > /dev/null 2>&1 || true
    rm -f "$REAL_HOME/Library/Preferences/render-pills.plist"
}
trap cleanup EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$BUILD_DIR/home"
APP=NotchBuddy/Sources/App
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$APP" -name '*.swift' ! -name NotchBuddyApp.swift | sort)
swiftc -swift-version 6 -suppress-warnings "${FILES[@]}" scripts/render-pills.swift -o "$BUILD_DIR/render-pills"
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/render-pills" "$@"
```

Run: `chmod +x scripts/render-pills.sh && bash -n scripts/render-pills.sh && bash scripts/test-u1-wiring.sh | tail -1`
Expected: the wiring script's last line `N passed, 0 failed` with the eight new lines passing.

```bash
mkdir -p ${TMPDIR:-/tmp}/u1 .claude/checkpoints/u1
bash scripts/render-pills.sh --out ${TMPDIR:-/tmp}/u1/pills.png     # about seven minutes: run it in the background
```

Expected: `wrote …pills.png (… pt at 2.0x): Claude Code, Claude App, Gemini CLI, Cursor`. The pills are 134 pt wide, as the overview's two-column grid makes them. Open it and say what you see: four pills side by side on black; the first is labelled **Claude Code** (not VS Code), the second **Claude App** with an amber-peach edge, each with its small cat. **Look at the longer labels against the cat.** The label is centred in the pill and the pill's cat ends 30 pt in: in the dry run's picture (at 120 pt, a little narrower than the real 134) "Claude App" ran under the cat's ear. If at 134 pt the label still touches the cat, say so to the owner instead of changing it: the fix (a leading padding on the label, as Windows/Linux's #522 did) would move every existing pill's label, which is a restyle that needs the owner's yes.

Copy it to `.claude/checkpoints/u1/` for the owner.

- [ ] **Step 5: Windows/Linux: the relay tag, the pill's name and colour (tests first)**

**Edit `windows/hook/src/agents.rs`:** find

```rust
pub const ANTIGRAVITY: &str = "antigravity";
```

replace with

```rust
pub const ANTIGRAVITY: &str = "antigravity";
/// A Claude Code session started from the Claude desktop app: it says so in `CLAUDE_CODE_ENTRYPOINT` and runs in no terminal. Its pill is `agent_claude-desktop`, as on the Mac.
pub const CLAUDE_DESKTOP: &str = "claude-desktop";

/// The `nm_agent` tag of an event: `--agent` when given, otherwise `claude-desktop` for a session whose entrypoint says so, otherwise none (Claude Code).
pub fn agent_tag(arg: &str, entrypoint: &str) -> String {
    if !arg.is_empty() {
        arg.to_string()
    } else if entrypoint == CLAUDE_DESKTOP {
        CLAUDE_DESKTOP.to_string()
    } else {
        String::new()
    }
}
```

**Edit `windows/hook/src/agents.rs`:** find

```rust
    #[test]
    fn antigravity_pre_tool_use_is_asked_never_answered_empty_or_allowed() {
```

replace with

```rust
    #[test]
    fn a_claude_desktop_session_is_tagged_and_an_explicit_agent_wins() {
        assert_eq!(agent_tag("", "claude-desktop"), "claude-desktop");
        assert_eq!(agent_tag("gemini", "claude-desktop"), "gemini");
        for other in ["", "cli", "vscode", "Claude-Desktop", "claude-desktop "] {
            assert_eq!(agent_tag("", other), "", "{other:?}");
        }
        assert_eq!(agent_tag("antigravity", ""), "antigravity");
        // Claude Desktop answers like any other tagged agent: no JSON is forced on it.
        assert_eq!(silent_answer(CLAUDE_DESKTOP, "PreToolUse"), None);
    }

    #[test]
    fn antigravity_pre_tool_use_is_asked_never_answered_empty_or_allowed() {
```

**Edit `windows/hook/src/main.rs`:** find

```rust
    // Which agent this hook was installed for. Absent means Claude Code,
    // so existing hook commands keep working unchanged.
    if !agent.is_empty() {
```

replace with

```rust
    // Which agent this hook was installed for. Absent means Claude Code,
    // so existing hook commands keep working unchanged, except that a session
    // started from the Claude desktop app is tagged `claude-desktop` (see `agent_tag`).
    let agent = agents::agent_tag(&agent, &env("CLAUDE_CODE_ENTRYPOINT"));
    if !agent.is_empty() {
```

**Edit `windows/hook/src/main.rs`:** find

```rust
    #[test]
    fn a_dangling_agent_flag_names_no_agent() {
```

replace with

```rust
    #[test]
    fn a_claude_desktop_session_is_forwarded_on_its_own_pill() {
        let stdin = r#"{"hook_event_name":"Stop","session_id":"d-1","cwd":"/proj"}"#;
        let desktop = shape(stdin, &["Stop"], &[("CLAUDE_CODE_ENTRYPOINT", "claude-desktop")]).unwrap();
        assert_eq!(desktop.agent, "claude-desktop");
        assert_eq!(forwarded(&desktop)["nm_agent"], "claude-desktop");
        let explicit = shape(stdin, &["--agent", "gemini", "Stop"], &[("CLAUDE_CODE_ENTRYPOINT", "claude-desktop")]).unwrap();
        assert_eq!(forwarded(&explicit)["nm_agent"], "gemini", "an explicit --agent wins");
        for entry in ["cli", "vscode", ""] {
            let plain = shape(stdin, &["Stop"], &[("CLAUDE_CODE_ENTRYPOINT", entry)]).unwrap();
            assert!(forwarded(&plain).get("nm_agent").is_none(), "{entry:?} is plain Claude Code");
        }
    }

    #[test]
    fn a_dangling_agent_flag_names_no_agent() {
```

**Edit `windows/src/core/pills.ts`:** find

```typescript
export const AGENT_PILL_COLORS: Readonly<Record<string, string>> = {
  agent_gemini: "#8AB4F8",
  agent_antigravity: "#E879F9",
};
```

replace with

```typescript
export const AGENT_PILL_COLORS: Readonly<Record<string, string>> = {
  agent_gemini: "#8AB4F8",
  agent_antigravity: "#E879F9",
  // Claude Code sessions from the Claude desktop app (the relay tags them `claude-desktop`); the Mac's PillCatalog has the same colour.
  "agent_claude-desktop": "#E3A857",
};
```

**Edit `windows/src/core/pills.ts`:** find

```typescript
const AGENT_NAMES: Readonly<Record<string, string>> = { claude: "Claude Code", gemini: "Gemini CLI", antigravity: "Antigravity", codex: "Codex", cursor: "Cursor" };
```

replace with

```typescript
const AGENT_NAMES: Readonly<Record<string, string>> = { claude: "Claude Code", gemini: "Gemini CLI", antigravity: "Antigravity", codex: "Codex", cursor: "Cursor", "claude-desktop": "Claude App" };

/** The name an agent's pill is created with: its tag, as it always was, except Claude Desktop, whose pill is labelled for a person. */
export function agentPillName(tag: string): string {
  return tag === "claude-desktop" ? AGENT_NAMES[tag] : tag;
}
```

**Edit `windows/src/island/hooks.ts`:** find

```typescript
import { agentColor } from "../core/pills.ts";
```

replace with

```typescript
import { agentColor, agentPillName } from "../core/pills.ts";
```

**Edit `windows/src/island/hooks.ts`:** find

```typescript
      State.upsertExternalAgent(agentId, validAgent!, agentColor(validAgent!));
```

replace with

```typescript
      State.upsertExternalAgent(agentId, agentPillName(validAgent!), agentColor(validAgent!));
```

**Edit `windows/scripts/cat-tests/pills.test.mjs`:** find

```javascript
import { AGENT_PILL_COLORS, agentColor } from "../../src/core/pills.ts";
```

replace with

```javascript
import { AGENT_PILL_COLORS, agentColor, agentLabel, agentPillName } from "../../src/core/pills.ts";
```

**Edit `windows/scripts/cat-tests/pills.test.mjs`:** find

```javascript
  assert.deepEqual(Object.keys(AGENT_PILL_COLORS), ["agent_gemini", "agent_antigravity"]);
```

replace with

```javascript
  assert.deepEqual(Object.keys(AGENT_PILL_COLORS), ["agent_gemini", "agent_antigravity", "agent_claude-desktop"]);
```

**Edit `windows/scripts/cat-tests/pills.test.mjs`:** find

```javascript
  const tags = [...relay.matchAll(/pub const (?:GEMINI|ANTIGRAVITY): &str = "([a-z-]+)";/g)].map((m) => m[1]);
  assert.deepEqual(tags, ["gemini", "antigravity"]);
```

replace with

```javascript
  const tags = [...relay.matchAll(/pub const (?:GEMINI|ANTIGRAVITY|CLAUDE_DESKTOP): &str = "([a-z-]+)";/g)].map((m) => m[1]);
  assert.deepEqual(tags, ["gemini", "antigravity", "claude-desktop"]);
```

**Edit `windows/scripts/cat-tests/pills.test.mjs`:** find

```javascript
  assert.match(hooks, /import \{ agentColor \} from "\.\.\/core\/pills\.ts";/);
  assert.match(hooks, /State\.upsertExternalAgent\(agentId, validAgent!, agentColor\(validAgent!\)\)/);
```

replace with

```javascript
  assert.match(hooks, /import \{ agentColor, agentPillName \} from "\.\.\/core\/pills\.ts";/);
  assert.match(hooks, /State\.upsertExternalAgent\(agentId, agentPillName\(validAgent!\), agentColor\(validAgent!\)\)/);
```

**Edit `windows/scripts/cat-tests/pills.test.mjs`:** find

```javascript
test("hooks.ts gives the pill it creates that colour, and no longer hashes by itself", () => {
```

replace with

```javascript
test("Claude Desktop: its pill is named and coloured as the Mac's, and every other agent's name is still its tag", () => {
  assert.equal(agentPillName("claude-desktop"), "Claude App");
  assert.equal(agentLabel("agent_claude-desktop"), "Claude App");
  assert.equal(agentColor("claude-desktop"), "#E3A857");
  for (const tag of ["gemini", "antigravity", "codex", "my-agent", "claude"]) assert.equal(agentPillName(tag), tag, tag);
});

test("hooks.ts gives the pill it creates that colour, and no longer hashes by itself", () => {
```

Run: `cd windows && npx --no-install tsc --noEmit && echo tsc ok && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"`
Expected: `tsc ok`; `ℹ fail 0` (the dry run's counting: the new Claude Desktop test adds one). Rust: `windows/scripts/cargo-linux.sh test -p notchmeow-hook --offline --target-dir /repo/windows/target/u1` (needs Docker; else the local probe: the dry run printed `27 passed` for `notchmeow-hook`, the two new tests included).

- [ ] **Step 6: The docs**

Add one paragraph to `docs/AGENTS.md` if the file exists (`ls docs/AGENTS.md`), else to `docs/INTEGRATIONS.md` in the section on agents (French, as that file is):

```markdown
**Claude Desktop (`agent_claude-desktop`, toutes les versions).** Les sessions Claude Code lancées depuis l'onglet Code de l'app Claude définissent `CLAUDE_CODE_ENTRYPOINT=claude-desktop` et n'ont aucun terminal : le relais les étiquette `nm_agent: claude-desktop` de lui-même (un `--agent` explicite l'emporte), donc rien à installer. Cochez la pastille pour la garder après la fin de la session ; le bouton ↗ et le bouton « Open Claude » de la carte « terminé » ouvrent l'app Claude. Windows et Linux : la pastille apparaît pendant la session ; le bouton qui ouvre l'app est pour un plan suivant.
```

- [ ] **Step 7: Builds and commit**

```bash
cd NotchBuddy && xcodegen > /dev/null && cd .. && git status --short NotchBuddy/NotchBuddy.xcodeproj
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "BUILD|error:"
git rev-parse --show-toplevel && git branch --show-current
git add NotchBuddy/Sources/App/HookOrigin.swift NotchBuddy/Sources/App/PillCatalog.swift NotchBuddy/Sources/App/AgentTarget.swift NotchBuddy/Sources/App/IslandViewContent.swift NotchBuddy/Sources/App/SidekickText.swift NotchBuddy/Sources/App/HookServer.swift tests/HookOriginTests.swift tests/SidekickWiringTests.swift scripts/test-hook-relay.sh scripts/test-u1-wiring.sh scripts/render-pills.swift scripts/render-pills.sh windows/hook/src/agents.rs windows/hook/src/main.rs windows/src/core/pills.ts windows/src/island/hooks.ts windows/scripts/cat-tests/pills.test.mjs docs/AGENTS.md
git commit -F - <<'EOF'
feat: a pill for Claude Code sessions from the Claude desktop app (upstream 344dc12, #191)

Sessions started from the Claude desktop app's Code tab set CLAUDE_CODE_ENTRYPOINT=claude-desktop and run in no terminal. The relays tag them
nm_agent claude-desktop (an explicit --agent wins), so they reach their own pill, agent_claude-desktop (a frozen ID), with NotchMeow's own colour.
Mac: the catalog entry, Open Claude on the pill and the finished card, "Handled in Claude Desktop" notes. Windows/Linux: the relay tag and the pill's name and colour.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
```

Expected: `git status` empty at the first line only if `project.pbxproj` was already regenerated by an earlier task (it was: Tasks 5, 9 and 10 added files; this task adds none to the app target, the render script is not in it); two `** BUILD SUCCEEDED **`. If `docs/AGENTS.md` does not exist, replace it in the `git add` by the file you edited.

---

### Task 14: Both wings step aside: the compact island swooshes into the notch (Mac)

**Agent: `nm-implementer-deep` (Sonnet 5.5, high; CLAUDE.md trigger 1: a spring-driven frame in the SwiftUI island fed by the AppKit panel's poll, with a click-through zone that must stay at the full island's positions).**

**Files:**
- Create (replace): `NotchBuddy/Sources/App/IslandWing.swift`, `tests/IslandWingTests.swift`, `tests/IslandWingWiringTests.swift`, `scripts/render-cats-wing.swift`
- Modify: `NotchBuddy/Sources/App/IslandWindowController.swift`, `IslandRootView.swift`, `tests/ShelfWiringTests.swift` (one pin), `scripts/render-cats.swift`, `docs/SPEC.md`, `CLAUDE.md`

**Interfaces:**
- Produces: `IslandWing.wings(island:notchWidth:slop:) -> IslandWing.Wings` (`left`, `right`, `contains(_:)`, `zone(of:) -> IslandWing.Zone?`), `IslandWing.Zone` (`.left`, `.right`), `IslandWing.leftDwell` (0.4), `IslandWing.foldedWidth(notchWidth:)`, `IslandWing.width(full:notchWidth:swoosh:)`, `IslandWing.isActive(compact:greetingTail:dragging:alert:)`, `IslandWing.springResponse` (0.22) and `springDamping` (0.68), `IslandWing.Yield.step(now:zone:active:buttonDown:) -> Out(faded:passThrough:)`; in the view `shownWidth` and `swoosh`; `drawCompact(..., swoosh:)` in `render-cats.swift`. `IslandWing.rect` and the `hasWing` parameter are gone (the island always has something to fold).
- Consumes: `IslandWindowController.decisionWaiting`, `state.fileDragOver`, `state.shelfHoldsIsland`, `state.desktopPhase` (all existing), `state.wingYielded` (existing, now meaning "folded").

**The owner's decision (2026-10-15), replacing today's right-wing-only fade.** When the pointer is over either wing of the compact island (the parts left and right of the camera notch; the notch itself is the hover-open zone with the 150 ms dwell of Task 7) the whole island swooshes into the notch **(the right wing, the grid, at once; the left wing, the big cat, only after the pointer has rested there 0.4 s with no mouse button pressed: any press during the 0.4 s cancels it, so a quick click, the drag of the cat's head out to the desktop and a right-click (the Wardrobe menu) work as they do today)**: its frame shrinks to the notch's width on a spring (about 0.22 s, slight overshoot), the big cat, the grid and the badges (the shelf's included) fade as it shrinks, and the panel passes clicks through to the menu-bar items under both wings. **The hover zones stay at the full-width positions** (`islandRect` is `islandSize`'s frame, which this task never shrinks), so leaving is measured against the original wings, not the shrunk island. One second after the pointer has left both wings it swooshes back out. **An alert cancels the step-aside at once** (a permission card or question waits, a file is on its way in, the desktop cat is away from home, the shelf holds the island): `isActive` is false, the memory resets, the island is out on that very tick. It is fed by the existing `pollFrame`: no timer, monitor or poll of its own (the 0.4 s dwell is a reading of the poll's own clock, `CACurrentMediaTime()`, against the tick where the pointer began to rest); the spring and the fades are SwiftUI animations that run only while they move, so a hidden or at-rest island costs nothing. Windows/Linux: nothing, listed with the outside click as a follow-up plan (the Windows/Linux island is stuck to the top of the screen with no menu bar under it).

- [ ] **Step 1: The tests first (the rules, then the pins)**

**Create `tests/IslandWingTests.swift`:**

```swift
import Foundation

// The compact island's two wings: their rectangles, when the island can step aside, the swoosh's numbers and the fold's timing, as plain numbers and a fake clock.
// Run it through scripts/test-island-wing.sh.

@main
enum IslandWingTests {
    /// One tick on the fake clock, with the defaults of a plain hover.
    @MainActor static func tick(_ y: inout IslandWing.Yield, _ t: Double, _ zone: IslandWing.Zone?, active: Bool = true, button: Bool = false) -> IslandWing.Yield.Out {
        y.step(now: t, zone: zone, active: active, buttonDown: { button })
    }

    @MainActor static func main() {
        CT.section("the numbers the owner chose")
        CT.checkNear("the cats, grid and badges fade out in 0.15 s as the island shrinks", IslandWing.fadeOut, 0.15)
        CT.checkNear("and the island swooshes back out 1 s after the pointer has left both wings", IslandWing.returnDelay, 1.0)
        CT.checkTrue("it fades back in no faster than it went out, and well within the delay", IslandWing.fadeIn >= IslandWing.fadeOut && IslandWing.fadeIn < IslandWing.returnDelay)
        CT.checkNear("the swoosh is a spring of about 0.22 s", IslandWing.springResponse, 0.22)
        CT.checkTrue("with a slight overshoot: a damping fraction under 1, and not wobbly", IslandWing.springDamping < 1 && IslandWing.springDamping > 0.5)

        CT.section("the two wings: the parts beside the notch")
        // A notch screen: the panel is 720 wide, the island 344 (notch 184 plus two wings of 80) by 32, at the top of a panel 320 high (AppKit: y up).
        let island = CGRect(x: 188, y: 288, width: 344, height: 32)
        let w = IslandWing.wings(island: island, notchWidth: 184)
        CT.check("the left wing runs from the island's left edge to the notch's left edge", [w.left.minX, w.left.maxX], [188, 268])
        CT.check("the right wing from the notch's right edge to the island's right edge", [w.right.minX, w.right.maxX], [452, 532])
        CT.check("both are the strip's height", [w.left.minY, w.left.maxY, w.right.minY, w.right.maxY], [288, 320, 288, 320])
        CT.checkTrue("the notch (the island's middle) is in neither: it is the hover-open zone", !w.contains(CGPoint(x: 360, y: 300)) && !w.contains(CGPoint(x: 268.1, y: 300)) && !w.contains(CGPoint(x: 451.9, y: 300)))
        CT.checkTrue("the first and last points of each wing are in it", w.contains(CGPoint(x: 188, y: 300)) && w.contains(CGPoint(x: 267.9, y: 300)) && w.contains(CGPoint(x: 452, y: 300)) && w.contains(CGPoint(x: 531.9, y: 300)))
        let slopped = IslandWing.wings(island: island, notchWidth: 184, slop: 6)
        CT.check("with the 6 pt hover slop each wing reaches 6 pt further out, up and down, and not towards the notch", [slopped.left.minX, slopped.left.maxX, slopped.right.minX, slopped.right.maxX, slopped.left.minY, slopped.right.maxY], [182, 268, 452, 538, 282, 326])
        let bar = IslandWing.wings(island: CGRect(x: 240, y: 296, width: 240, height: 24), notchWidth: 80)
        CT.check("a screen without a notch: the same rule, around its 80 pt bar", [bar.left.width, bar.right.width, bar.right.height], [80, 80, 24])
        let none = IslandWing.wings(island: CGRect(x: 100, y: 0, width: 50, height: 30), notchWidth: 184)
        CT.check("an island narrower than its notch has no wing at all", [none.left.width, none.right.width], [0, 0])

        CT.section("what the island folds to")
        CT.check("the notch's own width", IslandWing.foldedWidth(notchWidth: 184), 184)
        CT.check("at rest it is the full width", IslandWing.width(full: 344, notchWidth: 184, swoosh: 0), 344)
        CT.check("folded it is the notch's", IslandWing.width(full: 344, notchWidth: 184, swoosh: 1), 184)
        CT.check("half way it is half way", IslandWing.width(full: 344, notchWidth: 184, swoosh: 0.5), 264)

        CT.section("when the island can step aside")
        CT.checkTrue("in the compact island with nothing wanting it", IslandWing.isActive(compact: true, greetingTail: false, dragging: false, alert: false))
        CT.checkTrue("not hidden or expanded (compact is false there)", !IslandWing.isActive(compact: false, greetingTail: false, dragging: false, alert: false))
        CT.checkTrue("not while the greeting's tail draws the session cats", !IslandWing.isActive(compact: true, greetingTail: true, dragging: false, alert: false))
        CT.checkTrue("not while the cat's head is being dragged", !IslandWing.isActive(compact: true, greetingTail: false, dragging: true, alert: false))
        CT.checkTrue("not while an alert wants the island (a request, a question, a file, the desktop cat, the shelf)", !IslandWing.isActive(compact: true, greetingTail: false, dragging: false, alert: true))

        CT.section("the fold: in at once, out one second after the pointer has left both wings")
        var y = IslandWing.Yield()
        CT.check("the pointer elsewhere: nothing happens", tick(&y, 0, nil), .init(faded: false, passThrough: false))
        CT.check("the pointer reaches a wing: the island folds and the mouse passes through on that very tick", tick(&y, 1.0, .right), .init(faded: true, passThrough: true))
        CT.check("it stays while the pointer stays (ten seconds)", tick(&y, 11.0, .right), .init(faded: true, passThrough: true))
        CT.check("the pointer leaves: the island is still folded, and the mouse is no longer passed on", tick(&y, 12.0, nil), .init(faded: true, passThrough: false))
        CT.check("0.9 s later it is still folded", tick(&y, 12.9, nil), .init(faded: true, passThrough: false))
        CT.check("1 s after the pointer was first seen away it swooshes back out", tick(&y, 13.0, nil), .init(faded: false, passThrough: false))
        CT.check("and stays", tick(&y, 20.0, nil), .init(faded: false, passThrough: false))

        CT.section("the left wing (the big cat) folds the island only after the pointer has rested there 0.4 s with no button pressed; the right wing folds it at once")
        CT.checkNear("the left dwell is 0.4 s", IslandWing.leftDwell, 0.4)
        y = IslandWing.Yield()
        CT.check("the pointer reaches the left wing: nothing yet", tick(&y, 5.0, .left), .init(faded: false, passThrough: false))
        CT.check("399 ms later: still nothing", tick(&y, 5.399, .left), .init(faded: false, passThrough: false))
        CT.check("400 ms after it arrived: the island folds, and the mouse passes through", tick(&y, 5.4, .left), .init(faded: true, passThrough: true))
        CT.check("it stays while the pointer stays", tick(&y, 9.0, .left), .init(faded: true, passThrough: true))
        y = IslandWing.Yield()
        _ = tick(&y, 1.0, .left)
        CT.check("a press at 200 ms cancels the dwell (a quick click, the drag out to the desktop, a right-click on the big cat)", tick(&y, 1.2, .left, button: true), .init(faded: false, passThrough: false))
        CT.check("the button released at 400 ms: the dwell starts over, it does not fold", tick(&y, 1.4, .left), .init(faded: false, passThrough: false))
        CT.check("399 ms after the release: still nothing", tick(&y, 1.799, .left), .init(faded: false, passThrough: false))
        CT.check("400 ms after the release: it folds", tick(&y, 1.8, .left), .init(faded: true, passThrough: true))
        y = IslandWing.Yield()
        _ = tick(&y, 0, .left)
        _ = tick(&y, 0.3, nil)
        CT.check("leaving the wing before the dwell is over cancels it, and coming back starts again from zero", tick(&y, 0.5, .left), .init(faded: false, passThrough: false))
        CT.check("(0.399 s after coming back: nothing)", tick(&y, 0.899, .left), .init(faded: false, passThrough: false))
        CT.check("(and the full 0.4 s: it folds)", tick(&y, 0.9, .left), .init(faded: true, passThrough: true))
        y = IslandWing.Yield()
        CT.check("the right wing needs no dwell: the grid folds the island on the first tick", tick(&y, 0, .right), .init(faded: true, passThrough: true))
        var held = IslandWing.Yield()
        for t in stride(from: 0.0, through: 3.0, by: 0.1) { _ = tick(&held, t, .left, button: true) }
        CT.check("a button held the whole time over the left wing never folds it", tick(&held, 3.1, .left, button: true), .init(faded: false, passThrough: false))
        var lazy = IslandWing.Yield()
        var leftAsked = 0
        for i in 0..<20 { _ = lazy.step(now: Double(i) * 0.01, zone: i < 10 ? nil : .left, active: true, buttonDown: { leftAsked += 1; return false }) }
        CT.check("the button is asked only while the pointer is on the left wing", leftAsked, 10)
        var folded = IslandWing.Yield()
        _ = tick(&folded, 0, .right)
        var askedFolded = 0
        for i in 1..<10 { _ = folded.step(now: Double(i), zone: .left, active: true, buttonDown: { askedFolded += 1; return false }) }
        CT.check("once folded, the left wing asks nothing and keeps the fold", askedFolded, 0)

        CT.section("both wings are one hover: going from one wing to the other (through the notch) keeps the fold, and the second starts again")
        y = IslandWing.Yield()
        _ = tick(&y, 0, .right)             // the left wing
        _ = tick(&y, 5.0, nil)          // crossing the notch
        CT.check("back in a wing (the other one) at 5.8 s: still folded, the mouse passes", tick(&y, 5.8, .right), .init(faded: true, passThrough: true))
        _ = tick(&y, 6.0, nil)
        CT.check("away again at 6.0 s: 0.9 s later it is still folded (the count began again)", tick(&y, 6.9, nil), .init(faded: true, passThrough: false))
        CT.check("and out again at 7.0 s", tick(&y, 7.0, nil), .init(faded: false, passThrough: false))

        CT.section("the mouse button held: a file dragged in, or a click that began elsewhere")
        y = IslandWing.Yield()
        CT.check("a button held when the pointer arrives never starts a fold: the wing is the island's, as before", tick(&y, 0, .right, button: true), .init(faded: false, passThrough: false))
        CT.check("and releasing it over the wing then folds it", tick(&y, 0.1, .right), .init(faded: true, passThrough: true))
        CT.check("a button pressed over a folded island leaves it folded", tick(&y, 0.2, .right, button: true), .init(faded: true, passThrough: true))

        CT.section("an alert cancels the step-aside at once, and a compact island that is not active never folds")
        y = IslandWing.Yield()
        _ = tick(&y, 0, .right)
        CT.check("an alert arrives (a permission card, a question, a file drop, the desktop cat's return): the island is back at once", tick(&y, 0.5, .right, active: false), .init(faded: false, passThrough: false))
        CT.check("and the pointer still over the wing while the alert lasts folds nothing", tick(&y, 0.6, .right, active: false), .init(faded: false, passThrough: false))
        CT.check("when the alert is over and the pointer is still over the wing, a new fold begins", tick(&y, 0.7, .right), .init(faded: true, passThrough: true))
        y = IslandWing.Yield()
        var asked = 0
        _ = y.step(now: 0, zone: nil, active: true, buttonDown: { asked += 1; return false })
        CT.check("with the pointer away the mouse button is never asked about", asked, 0)
        _ = y.step(now: 1, zone: .right, active: true, buttonDown: { asked += 1; return false })
        _ = y.step(now: 2, zone: .right, active: true, buttonDown: { asked += 1; return false })
        CT.check("it is asked once, when the fold begins, not on every tick after", asked, 1)
        var buttonAsked = 0
        var quiet = IslandWing.Yield()
        for i in 0..<50 { _ = quiet.step(now: Double(i), zone: i % 2 == 0 ? .right : nil, active: false, buttonDown: { buttonAsked += 1; return false }) }
        CT.check("an island that is not active never asks about the mouse button (a hidden island's slow poll costs nothing)", buttonAsked, 0)

        CT.section("a clock that is not a time")
        var odd = IslandWing.Yield()
        _ = tick(&odd, 0, .right)
        CT.check("NaN resets the island without a crash", tick(&odd, .nan, .right), .init(faded: false, passThrough: false))
        CT.check("infinity too", tick(&odd, .infinity, .right), .init(faded: false, passThrough: false))
        CT.check("and the next real tick works", tick(&odd, 3, .right), .init(faded: true, passThrough: true))
        _ = tick(&odd, 4, nil)
        CT.check("a clock that runs backwards does not bring the island back early", tick(&odd, 1, nil), .init(faded: true, passThrough: false))

        CT.section("fuzz: 20000 ticks that must keep the rules")
        var rng = SystemRandomNumberGenerator()
        var f = IslandWing.Yield(), t = 0.0, broke = 0, lastIn = -100.0, wasFaded = false
        for _ in 0..<20000 {
            t += Double.random(in: 0...0.05, using: &rng)
            let pick = Double.random(in: 0...1, using: &rng), zone: IslandWing.Zone? = pick < 0.15 ? .left : pick < 0.3 ? .right : nil, inWing = zone != nil, active = Double.random(in: 0...1, using: &rng) < 0.95
            let out = tick(&f, t, zone, active: active, button: Double.random(in: 0...1, using: &rng) < 0.05)
            if out.passThrough && !out.faded { broke += 1 }                                  // pass-through is only ever on a folded island
            if !active && out.faded { broke += 1 }                                           // an inactive island never keeps a fold
            if out.passThrough && !inWing { broke += 1 }                                     // and only with the pointer over a wing
            if active && inWing && out.faded { lastIn = t }
            if active && !inWing && wasFaded && !out.faded && t - lastIn < IslandWing.returnDelay { broke += 1 }   // never back early
            wasFaded = active && out.faded
        }
        CT.check("no tick broke a rule", broke, 0)

        CT.finish()
    }
}
```

**Create `tests/IslandWingWiringTests.swift`:**

```swift
import Foundation

// Source pins for the compact island stepping aside for the pointer on either wing, where no test program can compile the app's files (the panel, AppState and the SwiftUI view need the whole app).
// Each says where a call must be, so a missed call site fails here and not on the owner's screen. Run from the repository root through scripts/test-island-wing-wiring.sh.

@main
enum IslandWingWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
    /// The offset of the first `needle`, or -1.
    static func at(_ needle: String, in text: String) -> Int { text.range(of: needle)?.lowerBound.utf16Offset(in: text) ?? -1 }

    @MainActor static func main() {
        let controller = source("IslandWindowController.swift"), island = source("IslandRootView.swift"), app = source("AppState.swift"), rules = source("IslandWing.swift")
        CT.section("the sources were read")
        CT.checkTrue("the four files are there", controller.contains("final class IslandWindowController") && island.contains("struct IslandContainer") && app.contains("final class AppState") && rules.contains("enum IslandWing"))

        CT.section("the rules are pure: no timer, no monitor, no AppKit, no clock of their own")
        CT.checkTrue("IslandWing.swift imports only CoreGraphics and Foundation", rules.contains("import CoreGraphics") && rules.contains("import Foundation") && !rules.contains("import AppKit") && !rules.contains("import SwiftUI"))
        CT.checkTrue("and starts nothing", !rules.contains("Timer") && !rules.contains("DispatchQueue") && !rules.contains("NSEvent") && !rules.contains("CACurrentMediaTime") && !rules.contains("Date()"))

        CT.section("the panel: one step per poll tick, fed by the poll's own pointer and clock, and no new timer or monitor")
        CT.check("the controller holds one wing memory", count("private var wingYield = IslandWing.Yield()", in: controller), 1)
        CT.check("and steps it in exactly one place, from the poll", count("wingYield.step(", in: controller), 1)
        CT.checkTrue("an alert cancels the step-aside: a card or question waiting, a file on its way in, the shelf's hold, the desktop cat away from home", controller.contains("let wingAlert = decisionWaiting || state.fileDragOver || state.shelfHoldsIsland || state.desktopPhase != .home"))
        CT.checkTrue("the step is given the active rule (with the alert), BOTH wings (the full island's frame, with the hover area's slop), the clock and the button state", controller.contains("IslandWing.isActive(compact: state.mode == .compact, greetingTail: state.greetingTail, dragging: inAttachDrag || attachDragStart != nil, alert: wingAlert)") && controller.contains("IslandWing.wings(island: islandRect, notchWidth: notchW, slop: hoverRect.maxX - islandRect.maxX)") && controller.contains("zone: wingActive ? wings.zone(of: local) : nil") && controller.contains("now: CACurrentMediaTime()") && controller.contains("buttonDown: { NSEvent.pressedMouseButtons != 0 }"))
        CT.checkTrue("the left wing's 0.4 s dwell and the any-button cancel come from the poll alone: the dwell is the rules' own clock reading, and the button state is every mouse button (a right-click on the big cat still opens the Wardrobe menu)", controller.contains("buttonDown: { NSEvent.pressedMouseButtons != 0 }") && controller.contains("matching: .rightMouseDown") && controller.contains("self.showWardrobeMenu(for: event)") && controller.contains("wingYield.step(now: CACurrentMediaTime(), zone:") && rules.contains("static let leftDwell: TimeInterval = 0.4"))
        CT.checkTrue("the zones are the full island's: the island's frame for the hover test is `islandSize`'s, never the shrunk width", controller.contains("let islandRect = panel.currentIslandFrame(nw: notchW, nh: notchH)") && !controller.contains("shownWidth"))
        CT.checkTrue("the poll publishes the fold only when it changes", controller.contains("if state.wingYielded != wing.faded { state.wingYielded = wing.faded }"))
        CT.checkTrue("the pointer over a wing of the folded island is not the island's: hover cannot open it, and the click-through below takes the mouse off the panel", controller.contains("let inIsland = hoverRect.contains(local) && !wing.passThrough"))
        CT.checkTrue("the step comes after the island's rectangle and before the click-through toggle and the FSM's enter and leave", at("let islandRect = panel.currentIslandFrame", in: controller) > 0 && at("let islandRect = panel.currentIslandFrame", in: controller) < at("wingYield.step(", in: controller) && at("wingYield.step(", in: controller) < at("let shouldAcceptMouse = inIsland", in: controller) && at("let shouldAcceptMouse = inIsland", in: controller) < at("fsm.mouseEntered()", in: controller))
        CT.check("the panel registers no mouse-moved monitor (the poll that already runs is the only watcher)", count("matching: .mouseMoved", in: controller), 0)
        CT.checkTrue("and the poll still runs at the hidden rate while the island is hidden (the poller is untouched)", controller.contains("poller.run(hidden: state.mode == .hidden)") && controller.contains("modeSubscription = state.$mode"))

        CT.section("the view: the island's black shrinks into the notch on a spring, and its cats, grid and badges fade with it")
        CT.checkTrue("AppState publishes wingYielded and nothing else sets it", app.contains("@Published var wingYielded = false") && count("wingYielded =", in: controller) == 1 && count("wingYielded =", in: island) == 0)
        CT.checkTrue("the drawn width is the notch's while the compact island has stepped aside, and the full width otherwise", island.contains("private var shownWidth: CGFloat { state.mode == .compact && state.wingYielded ? IslandWing.foldedWidth(notchWidth: state.notchWidth) : islandWidth }"))
        CT.checkTrue("the black is drawn at that width, centred, with the rules' spring", island.contains("IslandShape(width: shownWidth, height: islandHeight, cornerRadius: cornerRadius, topRadius: islandTopRadius)\n                .fill(Color.black)\n                .offset(x: (islandWidth - shownWidth) / 2)\n                .animation(swoosh, value: state.wingYielded)") && island.contains("Animation.spring(response: IslandWing.springResponse, dampingFraction: IslandWing.springDamping)"))
        CT.checkTrue("there is no mask on the black any more (the shape itself shrinks)", !island.contains("// The right wing steps aside: its black fades with the grid"))
        CT.check("the big cat, cat 2, the kittens, the grid and the shelf's badge all fade with the fold", count(".opacity(state.wingYielded ? 0 : 1)", in: island), 5)
        CT.checkTrue("with the same animation, quick out and gentler in, from the rules' constants", count(".animation(wingAnimation, value: state.wingYielded)", in: island) == 5 && island.contains(".easeOut(duration: IslandWing.fadeOut) : .easeInOut(duration: IslandWing.fadeIn)"))
        CT.checkTrue("the content after the black is as it was", island.contains("// Content\n            if state.mode == .expanded {"))

        CT.finish()
    }
}
```

Run: `bash scripts/test-island-wing.sh 2>&1 | tail -4`
Expected: FAIL: a compile error, `type 'IslandWing' has no member 'wings'` (the tests are the new ones; the file is still the old one).

- [ ] **Step 2: The rules**

**Replace `NotchBuddy/Sources/App/IslandWing.swift` with:**

**Create `NotchBuddy/Sources/App/IslandWing.swift`:**

```swift
import CoreGraphics
import Foundation

// The compact island steps aside for the pointer: the rules, as plain numbers and times. The compact island is a strip with the notch in the middle and a wing on each side (the left holds the big cat,
// the right the grid of agent cats and the shelf's badge). On a crowded menu bar the wings sit on other apps' icons, and macOS has no way to move them. While the pointer is over EITHER wing the whole
// island swooshes into the notch (its frame shrinks to the notch's width on a spring), its cats, grid and badges fade as it shrinks, and the panel passes the mouse on to the icons under both wings;
// `returnDelay` seconds after the pointer has left both wings it swooshes back out. The right wing (the grid) folds the island at once; the left wing (the big cat) only after the pointer has rested
// there `leftDwell` seconds with no mouse button pressed, and any press during the dwell cancels it, so a quick click, the drag of the cat's head out to the desktop and a right-click (the Wardrobe menu)
// on the big cat work as they always did. The notch itself is not a wing: the pointer there is the island's own hover (Open on hover, with its dwell, lives
// there). The hover zones stay where the full island is, so leaving is measured against the original wings, not the shrunk island. An alert cancels the step-aside at once. Foundation only:
// `IslandWindowController.pollFrame` feeds it the pointer and the clock it already has, so it adds no timer, no monitor and no poll (`docs/SPEC.md`, "L'aile droite s'efface").

enum IslandWing {
    /// How long the cats, the grid and the badges take to fade out as the island shrinks (s), and to fade back in (s). The panel stops taking the mouse at once; only the picture moves.
    static let fadeOut: TimeInterval = 0.15
    static let fadeIn: TimeInterval = 0.25
    /// How long the pointer must have been away from both wings before the island swooshes back out (s).
    static let returnDelay: TimeInterval = 1.0
    /// How long the pointer must rest on the LEFT wing, with no mouse button pressed, before the island folds (s). The right wing folds it at once.
    static let leftDwell: TimeInterval = 0.4
    /// The slack the dwell's comparison allows, so that 0.4 s on a clock of binary fractions is 0.4 s.
    private static let epsilon: TimeInterval = 1e-9
    /// The swoosh is a spring: about 0.22 s to settle, with a slight overshoot (a damping fraction a little under 1).
    static let springResponse: TimeInterval = 0.22
    static let springDamping: Double = 0.68

    /// The two wings in the panel's coordinates, each the strip's whole height: the left from the island's left edge to the notch's left edge, the right from the notch's right edge to the island's
    /// right edge. `island` is the compact island's FULL frame and `notchWidth` the notch's. `slop` is how far the island's hover area reaches beyond the strip (6 pt on a notch screen, 0 on a screen
    /// without one): each wing takes it on its outer side, top and bottom, and not on the side towards the notch.
    struct Wings: Equatable {
        var left: CGRect
        var right: CGRect
        func contains(_ p: CGPoint) -> Bool { left.contains(p) || right.contains(p) }
        /// Which wing the point is in, if any.
        func zone(of p: CGPoint) -> Zone? { left.contains(p) ? .left : right.contains(p) ? .right : nil }
    }

    enum Zone: Equatable { case left, right }

    static func wings(island: CGRect, notchWidth: CGFloat, slop: CGFloat = 0) -> Wings {
        let notchLeft = island.midX - notchWidth / 2, notchRight = island.midX + notchWidth / 2
        let leftWidth = max(0, notchLeft - (island.minX - slop)), rightWidth = max(0, island.maxX + slop - notchRight)
        return Wings(left: CGRect(x: island.minX - slop, y: island.minY - slop, width: leftWidth, height: island.height + 2 * slop),
                     right: CGRect(x: notchRight, y: island.minY - slop, width: rightWidth, height: island.height + 2 * slop))
    }

    /// The width the island shrinks to: the notch's own.
    static func foldedWidth(notchWidth: CGFloat) -> CGFloat { notchWidth }

    /// The island's drawn width at `swoosh` (0 at rest, 1 folded into the notch): linear, for the contact sheet; the app lets a spring move it.
    static func width(full: CGFloat, notchWidth: CGFloat, swoosh: Double) -> CGFloat { full - (full - foldedWidth(notchWidth: notchWidth)) * CGFloat(swoosh) }

    /// Whether the island can step aside now: only in the compact island, not while the greeting's tail still draws the session cats in the grid's place, not while a drag of the cat's head is under
    /// way, and not while an alert wants the island (a permission request or question waits, a file is on its way in, the desktop cat is flying to or from the notch, the shelf holds the island).
    static func isActive(compact: Bool, greetingTail: Bool, dragging: Bool, alert: Bool) -> Bool { compact && !greetingTail && !dragging && !alert }

    /// The island's memory between two ticks.
    struct Yield: Equatable {
        struct Out: Equatable {
            /// The island is folded into the notch (or folding).
            var faded: Bool
            /// The pointer is over a wing of the folded island: the panel must not take the mouse, and the island must not count the pointer as over it.
            var passThrough: Bool
        }

        private var faded = false
        /// When the pointer was first seen away from both wings (while folded); nil while it is over one.
        private var leftAt: TimeInterval?
        /// When the pointer began to rest on the left wing with no button pressed (before the island has folded); nil otherwise.
        private var restSince: TimeInterval?

        /// One tick. `zone`: the wing the pointer is in, if any. `active`: `isActive`. `buttonDown` says whether any mouse button is held (a file being dragged in, a click that began on the big cat, a
        /// right-click): then no fold begins, a dwell on the left wing starts over, and a fold that has begun is not undone by it. It is asked only while the pointer is in a wing and the island has not
        /// folded yet, so a poll tick that is not near a wing costs nothing.
        mutating func step(now: TimeInterval, zone: Zone?, active: Bool, buttonDown: () -> Bool) -> Out {
            guard active, now.isFinite else {
                self = Yield()
                return Out(faded: false, passThrough: false)
            }
            if let zone {
                leftAt = nil
                if faded { return Out(faded: true, passThrough: true) }
                switch zone {
                case .right:
                    restSince = nil
                    if !buttonDown() { faded = true }
                case .left:
                    if buttonDown() {
                        restSince = nil
                    } else {
                        let since = restSince ?? now
                        restSince = since
                        if now - since + IslandWing.epsilon >= IslandWing.leftDwell { faded = true }
                    }
                }
                return Out(faded: faded, passThrough: faded)
            }
            restSince = nil
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

Run: `bash scripts/test-island-wing.sh 2>&1 | tail -3`
Expected: PASS: `All tests passed.` (the numbers, both wings with and without the 6 pt slop, the notchless bar, the folded widths, the left wing's 0.4 s dwell (399 ms no fold, 400 ms fold, a press at 200 ms cancels and the dwell starts over on release, leaving cancels, the right wing needs none, a held button never folds, the button is asked only while the pointer is on the left wing), the alert, the fold and the one-second return, going from one wing to the other, the button held, the alert cancel, a clock that is not a time, and the 20000-tick fuzz).

- [ ] **Step 3: The panel and the view**

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`:** find

```swift
        // The compact island's right wing steps aside (IslandWing): the pointer over it fades the grid, and the panel passes the mouse on to the menu bar icons under it.
        // The island opens from the notch and the cat, not from the wing. Fed by this poll's own pointer and clock: no timer and no monitor of its own.
        let wingActive = IslandWing.isActive(compact: state.mode == .compact, greetingTail: state.greetingTail, dragging: inAttachDrag || attachDragStart != nil)
        let wingRect = IslandWing.rect(island: islandRect, notchWidth: notchW, slop: hoverRect.maxX - islandRect.maxX)
        let wing = wingYield.step(now: CACurrentMediaTime(), inWing: wingActive && wingRect.contains(local), active: wingActive,
                                  buttonDown: { NSEvent.pressedMouseButtons != 0 }, hasWing: { state.hasMiniGrid })
```

replace with

```swift
        // The compact island steps aside (IslandWing): the pointer over EITHER wing swooshes the whole island into the notch, and the panel passes the mouse on to the menu bar icons under both wings.
        // The notch itself is the island's hover zone. `islandRect` is the full island's frame, so the zones stay where they were and leaving is measured against the original wings. An alert cancels it.
        // Fed by this poll's own pointer and clock: no timer and no monitor of its own.
        let wingAlert = decisionWaiting || state.fileDragOver || state.shelfHoldsIsland || state.desktopPhase != .home
        let wingActive = IslandWing.isActive(compact: state.mode == .compact, greetingTail: state.greetingTail, dragging: inAttachDrag || attachDragStart != nil, alert: wingAlert)
        let wings = IslandWing.wings(island: islandRect, notchWidth: notchW, slop: hoverRect.maxX - islandRect.maxX)
        let wing = wingYield.step(now: CACurrentMediaTime(), zone: wingActive ? wings.zone(of: local) : nil, active: wingActive,
                                  buttonDown: { NSEvent.pressedMouseButtons != 0 })
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`:** find

```swift
    private let closeEase  = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.34)
    /// The right wing's fade: quick out when the pointer arrives, gentler back (`IslandWing`).
    private var wingAnimation: Animation {
        state.wingYielded ? .easeOut(duration: IslandWing.fadeOut) : .easeInOut(duration: IslandWing.fadeIn)
    }
```

replace with

```swift
    private let closeEase  = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.34)
    /// The island's swoosh into the notch and back out (`IslandWing`): a spring with a slight overshoot.
    private let swoosh = Animation.spring(response: IslandWing.springResponse, dampingFraction: IslandWing.springDamping)
    /// The cats', the grid's and the badges' fade as the island shrinks: quick out when the pointer arrives, gentler back (`IslandWing`).
    private var wingAnimation: Animation {
        state.wingYielded ? .easeOut(duration: IslandWing.fadeOut) : .easeInOut(duration: IslandWing.fadeIn)
    }
    /// The width the compact island is drawn at: the notch's own while it has stepped aside (`IslandWing`), its full width otherwise. Its hover zones are always the full island's.
    private var shownWidth: CGFloat { state.mode == .compact && state.wingYielded ? IslandWing.foldedWidth(notchWidth: state.notchWidth) : islandWidth }
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`:** find

```swift
            // Black island shape
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
```

replace with

```swift
            // Black island shape. The compact island steps aside for the pointer on either wing: it shrinks into the notch on a spring (IslandWing) and back.
            IslandShape(width: shownWidth, height: islandHeight, cornerRadius: cornerRadius, topRadius: islandTopRadius)
                .fill(Color.black)
                .offset(x: (islandWidth - shownWidth) / 2)
                .animation(swoosh, value: state.wingYielded)
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`:** find

```swift
                    IslandGlowView(shape: IslandShape(width: islandWidth, height: islandHeight, cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        .transition(.opacity)
```

replace with

```swift
                    IslandGlowView(shape: IslandShape(width: shownWidth, height: islandHeight, cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        .offset(x: (islandWidth - shownWidth) / 2)
                        .transition(.opacity)
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`:** find

```swift
                .animation(.easeInOut(duration: 0.25), value: uploadActive || greetingActive)

            // Two cats mode: cat 2, beside the big cat (nothing at all in the other modes).
```

replace with

```swift
                .animation(.easeInOut(duration: 0.25), value: uploadActive || greetingActive)
                .opacity(state.wingYielded ? 0 : 1)
                .animation(wingAnimation, value: state.wingYielded)

            // Two cats mode: cat 2, beside the big cat (nothing at all in the other modes).
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`:** find

```swift
                .animation(.easeInOut(duration: 0.25), value: uploadActive || greetingActive)

            // Subagents, as kittens beside their parent's cat (nothing at all while no agent has one).
```

replace with

```swift
                .animation(.easeInOut(duration: 0.25), value: uploadActive || greetingActive)
                .opacity(state.wingYielded ? 0 : 1)
                .animation(wingAnimation, value: state.wingYielded)

            // Subagents, as kittens beside their parent's cat (nothing at all while no agent has one).
```

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`:** find

```swift
                .animation(.easeInOut(duration: 0.25), value: uploadActive || greetingActive)

            CountdownBar(state: state, islandW: islandWidth)
```

replace with

```swift
                .animation(.easeInOut(duration: 0.25), value: uploadActive || greetingActive)
                .opacity(state.wingYielded ? 0 : 1)
                .animation(wingAnimation, value: state.wingYielded)

            CountdownBar(state: state, islandW: islandWidth)
```

**Edit `tests/ShelfWiringTests.swift`:** find

```swift
controller.contains("IslandWing.rect(island: islandRect, notchWidth: notchW, slop: hoverRect.maxX - islandRect.maxX)") && controller.contains("hasWing: { state.hasMiniGrid }"))
```

replace with

```swift
controller.contains("IslandWing.wings(island: islandRect, notchWidth: notchW, slop: hoverRect.maxX - islandRect.maxX)") && controller.contains("buttonDown: { NSEvent.pressedMouseButtons != 0 }"))
```

The shelf's badge and the grid already fade with `state.wingYielded` (their own lines, unchanged); the three fade edits above add the same fade to the big cat, cat 2 and the kittens, so all five fade as the black shrinks. In the glow, the shape is the shrunk one, so the hover glow along the notch-sized island (the pointer in the notch zone while folded) follows it.

Run: `bash scripts/test-island-wing-wiring.sh 2>&1 | tail -1; bash scripts/test-shelf-wiring.sh 2>&1 | tail -1; bash scripts/test-u1-wiring.sh | tail -1`
Expected: `All tests passed.` twice, then the wiring script's `N passed, 0 failed`.

- [ ] **Step 4: The pictures (the swooshed-in state and a mid-swoosh frame)**

**Edit `scripts/render-cats.swift`:** find

```swift
    @MainActor static func drawCompact(_ cg: CGContext, _ cast: CatCast.Result, ox: Double, oy: Double, kit: KittenScene = KittenScene(), wingFaded: Bool = false) {
        let W = 345.0, H = 32.0
        // `wingFaded`: the right wing has stepped aside (IslandWing), so its black and the grid are not drawn.
        if wingFaded { cg.saveGState(); cg.clip(to: CGRect(x: ox - 2, y: oy - 2, width: W - 80 + 2, height: H + 4)) }
        defer { if wingFaded { cg.restoreGState() } }
        cg.fill(CatDraw.roundRect(ox, oy, W, H, 14), CatDraw.black(1))
        cg.fill(CatDraw.roundRect(ox + 80, oy, W - 160, H, 10), CatDraw.rgb([24, 25, 28]))
        let xs = CatIslandLayout.compactX(cast.mode)
        func big(_ spot: CatCast.Spot, _ x: Double, _ seed: UInt32) {
            let p = samplePill(spot.pill)
            drawIslandCat(cg, spot.cat, p?.state ?? .idle, colour: p?.color, big: true, cx: ox + x, cy: oy + H / 2, d: 20, top: -H / 2 + 0, badgeSide: -1, seed: seed)
        }
        big(cast.big, xs[0], 1)
        if let second = cast.second { big(second, xs[1], 2) }
        for (i, p) in (wingFaded ? [] : cast.pills).enumerated() {
            let sp = samplePill(p.pill)
            drawIslandCat(cg, p.cat, sp?.state ?? .idle, colour: sp?.color, big: false, cx: ox + W - 40 + (i % 2 == 1 ? 8 : -8), cy: oy + H / 2 + (i < 2 ? -8 : 8), d: 12, seed: UInt32(10 + i))
        }
        let ys = oy - oy + H / 2
        drawKittenLayers(cg, cast, expanded: false, big: (xs[0], ys, 20), second: xs.count > 1 ? (xs[1], ys, 20) : nil, ox: ox, oy: oy, kit: kit)
    }
```

replace with

```swift
    @MainActor static func drawCompact(_ cg: CGContext, _ cast: CatCast.Result, ox: Double, oy: Double, kit: KittenScene = KittenScene(), swoosh: Double = 0) {
        let W = 345.0, H = 32.0
        // `swoosh`: how far the island has stepped aside into the notch (IslandWing): its black narrows to the notch's width, centred, and its cats, grid and kittens fade with it.
        let w = Double(IslandWing.width(full: W, notchWidth: W - 160, swoosh: swoosh))
        cg.fill(CatDraw.roundRect(ox + (W - w) / 2, oy, w, H, 14), CatDraw.black(1))
        cg.fill(CatDraw.roundRect(ox + 80, oy, W - 160, H, 10), CatDraw.rgb([24, 25, 28]))
        cg.saveGState(); cg.setAlpha(CGFloat(1 - swoosh)); cg.beginTransparencyLayer(auxiliaryInfo: nil)   // the cats, grid and kittens fade as one picture
        defer { cg.endTransparencyLayer(); cg.restoreGState() }
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
        let ys = oy - oy + H / 2
        drawKittenLayers(cg, cast, expanded: false, big: (xs[0], ys, 20), second: xs.count > 1 ? (xs[1], ys, 20) : nil, ox: ox, oy: oy, kit: kit)
    }
```

**Replace `scripts/render-cats-wing.swift` with:**

**Create `scripts/render-cats-wing.swift`:**

```swift
import CoreGraphics
import Foundation

// The compact island stepping aside for the pointer on either wing, drawn without the app (part of scripts/render-cats.sh: `--wing`). Four strips on a mock menu bar with other apps' icons on both
// sides of the notch: the island as it rests (its cats and grid cover the first icons), a frame mid-swoosh (the black narrowing, the cats fading), the swooshed-in state (the island is the notch's own width,
// the icons show, and both wings are dashed: the parts that count), and a pointer on the left wing. The island is `drawCompact`, the app's own layout numbers; the dashed parts are `IslandWing.wings`,
// the rule the poll uses; the widths are `IslandWing.width`, a linear stand-in for the app's spring.

extension RenderCats {

    /// A menu bar `width` by 32 pt at (x, y) with an icon at each of `icons` (offsets from x), as other apps' status items would sit beside the notch.
    @MainActor static func mockMenuBar(_ cg: CGContext, x: Double, y: Double, width: Double, icons: [Double]) {
        cg.fill(CatDraw.roundRect(x, y, width, 32, 0), CatDraw.rgb([76, 78, 86]))
        for dx in icons {
            cg.fill(CatDraw.roundRect(x + dx, y + 9, 14, 14, 4), CatDraw.white(0.72))
            cg.fill(CatDraw.roundRect(x + dx + 4, y + 13, 6, 6, 2), CatDraw.rgb([76, 78, 86]))
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
        let rowH = 78.0, left = 150.0, W = 345.0, H = 32.0, barW = W + 150, pad = 60.0
        let rows: [(String, Double, Bool, Bool)] = [("At rest", 0, false, false), ("Mid-swoosh", 0.5, false, true), ("Swooshed in", 1, true, true), ("Pointer, left wing", 1, true, true)]
        let sheet = Sheet(width: left + barW + 16, height: rowH * Double(rows.count) + 8, scale: a.scale)
        let cg = sheet.cg
        let cast = CatDisplaySample.cast(CatDisplaySettings(mode: a.display, pair: CatDisplaySettings.defaultPair, agentCats: [:]), main: "shrimpy")
        let notch = W - 160   // the mock's notch (the lighter middle of the strip), as wide as drawCompact draws it
        for (i, row) in rows.enumerated() {
            let top = Double(i) * rowH + 8, oy = top + 28
            let (title, swoosh, dashed, pointer) = row
            CatDraw.text(cg, title, x: 14, y: oy + 20, size: 12, bold: true, color: CatDraw.white(0.9), anchor: .left)
            // icons under the left wing (3) and under the right wing (4), as a crowded menu bar has them
            mockMenuBar(cg, x: left, y: oy, width: barW, icons: [pad + 6, pad + 26, pad + 46] + [pad + W - 76, pad + W - 56, pad + W - 36, pad + W - 16])
            drawCompact(cg, cast, ox: left + pad, oy: oy, swoosh: swoosh)
            if dashed {
                let wings = IslandWing.wings(island: CGRect(x: left + pad, y: oy, width: W, height: H), notchWidth: notch, slop: 0)
                cg.saveGState()
                cg.setStrokeColor(CatDraw.white(0.9)); cg.setLineWidth(1); cg.setLineDash(phase: 0, lengths: [4, 3])
                cg.stroke(wings.left); cg.stroke(wings.right)
                cg.restoreGState()
                if pointer { mockPointer(cg, x: (i == 3 ? wings.left : wings.right).midX - 2, y: wings.left.midY - 4) }
            }
        }
        return sheet
    }
}
```

```bash
mkdir -p ${TMPDIR:-/tmp}/u1 .claude/checkpoints/u1
bash scripts/render-cats.sh --wing --out ${TMPDIR:-/tmp}/u1/wings.png
```

Expected: a PNG with four strips on a mock menu bar that has icons under both wings: **At rest** (the island's black, the big cat on the left and the grid on the right cover the icons); **Mid-swoosh** (half way in: the black narrowed to about 264 pt, the cats and grid half faded, some icons showing at each end); **Swooshed in** (the black is the notch's width, no cat, grid or badge, all seven icons showing, and both wings dashed); **Pointer, left wing** (the same, with a pointer arrow on the left dashed wing). Open it and say what you see. (`render-cats.sh` compiles only the cat files: about 15 seconds.) Copy it to `.claude/checkpoints/u1/`: the owner's checkpoint for this task.

- [ ] **Step 5: The docs (`CLAUDE.md`'s IslandWing bullet and the French spec paragraph)**

**Edit `CLAUDE.md`:** find

```markdown
- `NotchBuddy/Sources/App/IslandWing.swift` — the compact island's right wing steps aside (Mac only): with the pointer over the grid of agent cats the grid and the ear's black fade out in 0.15 s, the panel passes the mouse on to the menu-bar icons under it, and the grid comes back 1 s after the pointer leaves; the pointer over the wing no longer opens the island. Pure Foundation rules, fed by `IslandWindowController.pollFrame` (the existing poll: no timer or monitor of its own) and tested by `scripts/test-island-wing.sh`; `scripts/test-island-wing-wiring.sh` pins the app-side call sites; `render-cats.sh --wing` draws the faded state (`docs/SPEC.md`, "L'aile droite s'efface").
```

replace with

```markdown
- `NotchBuddy/Sources/App/IslandWing.swift` — the compact island's wings step aside (Mac only): with the pointer over EITHER wing (the parts left and right of the notch; the right at once, the left only after the pointer has rested there 0.4 s with no mouse button pressed, so a click, the drag-out and the Wardrobe right-click on the big cat work as before) the whole island swooshes into the notch (its frame shrinks to the notch's width on a spring, about 0.22 s with a slight overshoot; the big cat, the grid and the badges fade as it shrinks), the panel passes the mouse on to the menu-bar icons under both wings, the hover zones stay at the full island's positions, and it swooshes back out 1 s after the pointer leaves both wings; the notch itself is the island's hover zone (Open on hover, 150 ms dwell); an alert (a card or question waiting, a file on its way in, the shelf's hold, the desktop cat away from home) cancels it at once. Pure Foundation rules, fed by `IslandWindowController.pollFrame` (the existing poll: no timer or monitor of its own) and tested by `scripts/test-island-wing.sh`; `scripts/test-island-wing-wiring.sh` pins the app-side call sites; `render-cats.sh --wing` draws the swooshed-in state and a mid-swoosh frame (`docs/SPEC.md`, "L'aile droite s'efface"). The Windows and Linux app has none (a follow-up plan, with the outside click).
```

**Edit `docs/SPEC.md`:** find

```markdown
**L'aile droite s'efface** (macOS seulement). Sur une barre de menus chargée, la grille de l'oreille droite recouvre les icônes des autres apps à côté du notch, et macOS ne permet pas de les déplacer. Quand le pointeur est sur l'aile droite du `compact` (du bord droit du notch au bord droit de l'île, sur toute la hauteur de la bande), la grille et le noir de l'oreille s'effacent en 0,15 s et la zone laisse passer les clics vers les icônes dessous ; le gros chat (l'oreille gauche) reste. La grille revient 1 s après que le pointeur a quitté la zone. Survoler le notch ou le gros chat ouvre l'île comme avant ; survoler l'aile droite ne l'ouvre plus. Rien ne s'efface quand la grille est vide, pendant la queue du salut, pendant un glisser du chat, ni quand un bouton de la souris est déjà enfoncé à l'arrivée du pointeur (un fichier que l'on glisse dans l'île). Les trois modes (un chat, un chat par agent, deux chats) ont la même aile droite, la grille ; le chat 2, les chatons et le « ×N » sont dans l'oreille gauche et ne bougent pas. Windows et Linux : rien, l'île y est collée en haut de l'écran, sans barre de menus dessous. Règles pures : `IslandWing.swift` ; tests : `scripts/test-island-wing.sh` et `scripts/test-island-wing-wiring.sh`.
```

replace with

```markdown
**Les ailes s'effacent** (macOS seulement ; section gardée sous son nom d'origine, « L'aile droite s'efface »). Sur une barre de menus chargée, l'île `compact` (le gros chat à gauche, la grille et le badge de l'étagère à droite du notch) recouvre les icônes des autres apps de part et d'autre du notch, et macOS ne permet pas de les déplacer. Quand le pointeur est sur l'une des deux ailes (de chaque bord de l'île au bord du notch, sur toute la hauteur de la bande) — tout de suite sur l'aile droite (la grille), mais sur l'aile gauche (le gros chat) seulement quand il y reste 0,4 s sans bouton de la souris enfoncé (un appui pendant ce délai l'annule : le clic, le glisser vers le bureau et le clic droit du vestiaire fonctionnent comme avant) —, toute l'île plonge dans le notch : son cadre se réduit à la largeur du notch sur un ressort (environ 0,22 s, léger dépassement), le gros chat, la grille et les badges (celui de l'étagère compris) s'effacent en 0,15 s pendant qu'elle rétrécit, et la zone laisse passer les clics vers les icônes dessous, des deux côtés. Les zones de survol restent à leur place d'île complète : on sort de l'aile par rapport aux ailes d'origine, pas par rapport à l'île rétrécie. 1 s après que le pointeur a quitté les deux ailes, l'île ressort. Le notch lui-même n'est pas une aile : le survoler est le survol de l'île (« Open on hover » l'ouvre après 150 ms de présence). Une alerte (demande de permission, question, fichier que l'on glisse dans l'île, chat de bureau qui revient, étagère) annule l'effacement aussitôt. Rien ne s'efface pendant la queue du salut, pendant un glisser du chat, ni quand un bouton de la souris est déjà enfoncé à l'arrivée du pointeur. Windows et Linux : rien (une suite d'un plan ultérieur, comme le clic en dehors). Règles pures : `IslandWing.swift` ; tests : `scripts/test-island-wing.sh` et `scripts/test-island-wing-wiring.sh` ; image : `render-cats.sh --wing`.
```

- [ ] **Step 6: Build and the neighbours**

```bash
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"
for t in island-wing island-wing-wiring shelf-wiring cat-wiring sidekick-wiring island-poller island-hover u1-wiring; do echo "== $t: $(bash scripts/test-$t.sh 2>&1 | tail -1)"; done
```

Expected: `** BUILD SUCCEEDED **` and every last line passes. Nothing in `NotchBuddyApp`, the poller or the shelf changed. **Stop and report to the main session (the checkpoint):** `wings.png`, and the owner's questions: is the spring right (0.22 s, how much overshoot: `IslandWing.springResponse` and `springDamping`), and is the 0.4 s rest on the big cat right (a quick click, the drag-out and the right-click menu on the big cat must work as today; the fold only comes if the pointer rests there).

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add NotchBuddy/Sources/App/IslandWing.swift NotchBuddy/Sources/App/IslandWindowController.swift NotchBuddy/Sources/App/IslandRootView.swift tests/IslandWingTests.swift tests/IslandWingWiringTests.swift tests/ShelfWiringTests.swift scripts/render-cats-wing.swift scripts/render-cats.swift CLAUDE.md docs/SPEC.md
git commit -F - <<'EOF'
feat(mac): hover either wing and the compact island swooshes into the notch, and back 1 s after

The whole island shrinks to the notch's width on a spring (about 0.22 s, slight overshoot), its cats, grid and badges fade as it shrinks, and the
panel passes clicks to the menu-bar icons under both wings. The hover zones stay at the full island's positions. An alert (a card or question,
a file, the desktop cat, the shelf's hold) cancels it at once. Replaces the right-wing-only fade; fed by the existing poll. Mac only.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 15: CI, the map bullet, the French spec sentences, the last checks and the pictures

**Files:**
- Modify: `.github/workflows/build.yml`, `CLAUDE.md`, `docs/SPEC.md`

- [ ] **Step 1: CI steps (Mac job), next to the island wing steps**

**Edit `.github/workflows/build.yml`:** find

```yaml
      - name: Island right wing wiring (source pins of the panel, AppState and the view)
```

replace with

```yaml
      - name: Hook relay answers (Antigravity PreToolUse is asked)
        run: bash scripts/test-hook-relay.sh

      - name: Open on hover (the state machine)
        run: bash scripts/test-island-hover.sh

      - name: Outside click (the rules)
        run: bash scripts/test-island-outside-click.sh

      - name: Hover glow (the rules)
        run: bash scripts/test-island-glow.sh

      - name: Permission card click guard (the rule)
        run: bash scripts/test-approval-click-guard.sh

      - name: U1 wiring (source pins: crash fix, hover, guard, question card, outside click, glow)
        run: bash scripts/test-u1-wiring.sh

      - name: Island right wing wiring (source pins of the panel, AppState and the view)
```

The Windows tests workflow already runs `npm run check:cat`, which picks up `u1-guards`, `fsm-hover` and `hover-glow` by their file names: no change. Check the step name above matches the text in `build.yml` exactly (the find text must occur once); if the workflow names it differently, insert the six steps right after the wing wiring step instead and say so.

- [ ] **Step 2: The map bullet in `CLAUDE.md`**, after the "Fixes after H" bullet:

**Edit `CLAUDE.md`:** find

````markdown
## Build
```
cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build
```
````

replace with

````markdown
- U1, upstream fixes and island quality of life (`docs/superpowers/plans/2026-10-15-u1-upstream-fixes-and-island-qol.md`): the hook relay answers `{"decision":"ask"}` for Antigravity's PreToolUse (`scripts/test-hook-relay.sh` runs the two relays embedded in `HookServer.swift`; `windows/hook/src/agents.rs`); `ApprovalClickGuard.swift` (the permission card ignores clicks for 600 ms: one `Task.sleep` per request, `ApprovalInfo.token`) and its Windows twin `windows/src/views/clickguard.ts`; `AskQuestion.estimatedIslandHeight` and `QuestionLayout` (a question with option descriptions lists them and the island grows to 560 pt at most; without descriptions the card is as it was); Open on hover (`IslandStateMachine.openOnHover`, off by default; fed by the existing poll, so `IslandWing` and the 0 % rule hold; `windows/src/island/fsm.ts`); `IslandOutsideClick.swift` (a click outside the open island folds it, Mac only: one global mouse monitor installed by `IslandWindowController` only while the island is expanded; pure rules tested by `scripts/test-island-outside-click.sh`); `IslandGlow.swift` and `IslandGlowView.swift` (the hover glow: in the view tree only while the pointer is over the island, `Theme.Glow` from the `glow` group of `shared/theme.json`, key `island.hoverGlow`; the Windows/Linux twin is `#island.glow` in `windows/src/style.css`); the Claude Code pill is labelled "Claude Code" (ID frozen) and Claude Code sessions from the Claude desktop app reach the pill `agent_claude-desktop` (the relays tag `CLAUDE_CODE_ENTRYPOINT=claude-desktop`; `HookOrigin.agentTag`, `AgentTarget`, `scripts/render-pills.sh`; `windows/hook/src/agents.rs`); `scripts/test-u1-wiring.sh` pins the call sites; `scripts/render-glow.sh`, `render-question-card.sh` draw the pictures and `scripts/measure-island-cpu.sh` measures the island's own CPU without launching the app (about seven minutes each: they compile the whole app).

## Build
```
cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build
```
````

- [ ] **Step 3: Two French sentences in `docs/SPEC.md`** (French by design), at the end of the section "L'aile droite s'efface" (find its last paragraph; add after it):

```markdown
### Le halo au survol, le clic en dehors, l'ouverture au survol

Un halo arc-en-ciel doux (bleu, violet, rose, orange; `shared/theme.json`, groupe `glow`) longe le contour de l'île, compacte ou ouverte, tant que le pointeur la survole : il apparaît en 0,2 s et s'efface en 0,2 s. Rien n'est dessiné ni animé le reste du temps (0 % de CPU île cachée). Avec « Réduire les animations », le halo reste fixe. Réglage : Réglages → Général → Comportement → « Hover glow » (actif par défaut, clé `island.hoverGlow`). Un clic en dehors de l'île ouverte la replie aussitôt (Mac), sauf si elle est épinglée (⌘P), si une demande ou une question attend, si l'on écrit dans le chat ou si l'étagère la retient ; le moniteur de souris n'existe que tant que l'île est ouverte. « Open on hover » (désactivé par défaut) ouvre l'île quand le pointeur y reste 150 ms et la replie 0,6 s après sa sortie ; le pointeur sur l'aile droite n'ouvre rien.
```

- [ ] **Step 4: Every check, the three builds, the pictures**

```bash
for t in hook-relay hook-origin u1-wiring approval-click-guard ask-question island-hover island-outside-click island-glow island-wing island-wing-wiring island-poller cat-wiring cat-desktop-wiring hook-origin-wiring sidekick-wiring theme; do echo "== $t"; bash scripts/test-$t.sh 2>&1 | tail -1; done
bash scripts/check-no-leftovers.sh 2>&1 | tail -1
bash scripts/check-ask-unchanged.sh notchmeow/rebrand 2>&1 | tail -2
node scripts/gen-cat-fixtures.mjs --check 2>&1 | tail -1
(cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)" && npx --no-install tsc --noEmit && echo "tsc ok")
cd NotchBuddy && xcodegen > /dev/null && cd .. && git status --short NotchBuddy/NotchBuddy.xcodeproj
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath NotchBuddy/build/release build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "BUILD|error:"
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "BUILD|error:"
bash scripts/check-app-binary.sh NotchBuddy/build/store/Build/Products/Debug/NotchMeow.app appstore 2>&1 | tail -3
bash scripts/check-app-binary.sh NotchBuddy/build/release/Build/Products/Release/NotchMeow.app release 2>&1 | tail -3
```

Expected: each test's last line says passed (`All tests passed.`, `N passed, 0 failed`, the checks' own wording); `check-ask-unchanged.sh` still green (the Ask half of the drop canvas is untouched: this plan does not edit `UploadCanvasView`); the fixtures line `✓ 16 fixture files match cat-core.js`; `ℹ fail 0`, `tsc ok`; **no output** from the `git status` (the committed `project.pbxproj` already lists every new file: if it shows modified, `git add` it and say why); three `** BUILD SUCCEEDED **`; both `check-app-binary.sh` lines pass (nothing of this plan is under `#if !APPSTORE`, and none of it needs to be). Then the Rust run: `windows/scripts/cargo-linux.sh test --workspace --offline --target-dir /repo/windows/target/u1` (needs Docker; else the local probe and "needs Docker" in the ledger).

Pictures into `.claude/checkpoints/u1/` (copied in Tasks 6, 10 and 11 already): `question-desc.png`, `question-plain.png`, `hover-glow.png`, `win-glow.png`. Look at each once more and say what you see.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current
git add .github/workflows/build.yml CLAUDE.md docs/SPEC.md
git commit -F - <<'EOF'
docs(ci): U1 steps in CI, the map bullet in CLAUDE.md, the French spec paragraph

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
```

After Task 15 the main session dispatches `nm-reviewer-deep` over `git diff notchmeow/rebrand...HEAD` with this brief: the contracts between tasks (`openOnHover` and `hoverGlow` keys in both apps; `ApprovalInfo.token` users; `QuestionLayout` readers), the 0 % rule (every `Timer`, monitor, `TimelineView` and `setInterval` added or removed, and `CountdownBar`'s), the wing (`!wing.passThrough` still in `inIsland`), isolation (`nonisolated(unsafe)` and `MainActor.assumeIsolated` uses), privacy (nothing new is stored but two booleans; no network), the rules of CLAUDE.md (no restyle, frozen IDs, no reserved names, nothing from upstream's wardrobe or Mochi code), and Task 8's before and after table.

---

### Task 16: Owner checkpoint: the pictures, then the real-build checks

No code and no commit. The session reports (and pings the main session with `SendMessage`); the main session sends the owner the pictures and the list.

**The pictures** (`.claude/checkpoints/u1/`):

- **`hover-glow.png`** (Mac): is this the glow you meant? The edge's width, the halo's strength, the colours (blue, purple, pink, orange), on the compact notch and the open island, light and dark menu bar. The numbers are one block of constants (`IslandGlow`), the colours are `shared/theme.json`.
- **`win-glow.png`** (Windows/Linux, a browser render of the same CSS the island uses).
- **`question-desc.png`** and **`question-plain.png`**: the question card with option descriptions (the island grows to fit) and without (as it ships).
- The Settings switch: the Mac's is a row in General → Behavior (`Toggle("Hover glow")`, next to "Open on hover"); the Windows/Linux one is a row in General. A render of the Mac Settings page needs the whole Settings window and was not made; check it in the real build.

**The owner's real-build checks** (a Debug build or the 0.9.3 candidate on a Mac, a Windows PC and a Linux machine; the plan could not run any app):

1. **Outside click, Mac.** Open the island (click the notch). Click on the desktop or another app's window: it folds at once. Then try each exception and see it stay: pin it (⌘P) and click outside; trigger a permission request and click outside; open the chat, click in its field, start typing and click outside; with the shelf's drag-out or share picker in use; and drag a file from a Finder window toward the island (the press outside must not fold it); right-click outside (it folds on release). Compact and hidden islands: nothing changes (no monitor: Activity Monitor shows no extra cost).
2. **Hover glow, Mac.** Move the pointer onto the compact notch and onto the open island: the rainbow edge fades in over about 0.2 s, turns slowly, and fades out when the pointer leaves. Turn the switch off in Settings: no glow. System Settings → Accessibility → Display → Reduce motion on: the glow is still. On a menu bar with many icons: the pointer over either compact wing does not light the glow (the whole island swooshes into the notch instead, see item 11).
3. **Open on hover, Mac and Windows/Linux.** Settings → Open on hover on: hovering the island and staying 150 ms opens it (moving across the notch faster does not; the usual peek is not delayed) and it folds 0.6 s after the pointer leaves; click inside and it stays like a normal open island; a waiting permission card is never folded by hover; the pointer over the compact wing opens nothing. Off: hover only peeks, as before. **Close after** (Mac) now changes how long the open island stays.
4. **The permission card's click guard.** Trigger a permission request while the pointer is over the spot where the card appears and click at once: nothing is allowed or denied; after about a second the buttons work. Windows: the keys Y and N still answer at once.
5. **Question card.** Ask Claude Code something that makes it send an AskUserQuestion with option descriptions (the tool's options carry them): the card lists the options with their descriptions and the island grows; with options that have none the card is the old one. The island is not clipped at the bottom, and the panel's extra height does not catch clicks below the island.
6. **The permission card's CPU.** With the 0.9.3 build, trigger a permission request with the high-risk card and watch Activity Monitor for a minute: before it was about 55 %; the plan's Task 8 table says what to expect. Hidden island: about 0.3 % or lower.
7. **Antigravity.** With Antigravity's hook installed, run a command: its own permission prompt appears instead of the tool being blocked.
8. **Windows.** On a display with text scaling or a mixed-DPI pair the island is no longer cut at its sides (`fit_zoom`); a pill's label no longer runs under its cat; after a turn ends the pill does not flip to idle in the middle of the next turn.
9. **The crash.** Not testable by hand (an hour after a file edit): the pin and the review stand for it.
10. **The pills.** The Claude Code pill reads "Claude Code" in the island and in Settings → Active pills (Mac) and in the pill and the integration card (Windows/Linux); the "Handled in …" notes still name VS Code, Terminal or iTerm. Start a Claude Code session from the Claude desktop app's Code tab: a "Claude App" pill appears (Mac and Windows/Linux); on the Mac its ↗ and the finished card's "Open Claude" bring the Claude app forward; a permission request from it shows Claude Desktop's own prompt. `pills.png` (`.claude/checkpoints/u1/`) is the picture.
11. **The wings.** On a crowded menu bar, with the compact island showing: move the pointer onto the right wing (the grid): the whole island swooshes into the notch at once; on the left wing (the big cat) it swooshes only after the pointer has rested there 0.4 s (a quick click, a drag of the cat's head to the desktop and a right-click for the Wardrobe menu on the big cat work as before, and a press during the 0.4 s cancels it); in both cases in about 0.2 s with a slight overshoot, its cats, grid and shelf badge fade as it shrinks, and the menu-bar icons under both wings answer clicks; move the pointer away (not through the notch): after 1 s it swooshes back out; the notch zone itself opens the island after 150 ms with Open on hover on; a permission request, a question, a file dragged toward the island or the desktop cat flying home brings the island out at once. `wings.png` (`.claude/checkpoints/u1/`) is the picture.

---

## Parity with Windows/Linux

| Item | Mac | Windows/Linux |
|---|---|---|
| 1 Antigravity `ask` | Task 1 | Task 1 |
| 2 diff-timer crash | Task 2 | n/a (no such timer) |
| 3 question descriptions | Task 6 | the question card is a placeholder there; nothing to port yet |
| 4 click guard | Task 5 | Task 3 |
| 5 Stop timer, zoom, pill padding | the Stop timer exists already | Tasks 3 and 4 (the zoom is Windows in effect) |
| 6 open on hover | Task 7 | Task 7 |
| 13 wings swoosh into the notch | Task 14 | **not in U1: a follow-up plan** (with the outside click; the island is stuck to the top there) |
| 7 outside click | Task 9 | **not in U1: a follow-up plan** (owner's answer 4) |
| 8 hover glow | Task 10 | Task 11 |
| 11 Claude Code label | Task 12 | Task 12 |
| 12 Claude Desktop pill | Task 13 (relay tag, catalog, Open Claude) | Task 13 (relay tag, name, colour); Open Claude is a follow-up |
| C CPU | Task 8 (Mac only: the finding is about the Mac's SwiftUI) | the Windows island has a different drawing path; the owner's QA did not flag it |

The Mac gets at least what Windows/Linux gets: every Windows/Linux change here has a Mac twin, and the Mac has two extras the other app cannot have yet (the outside click's global monitor needs a Rust mouse hook; the question card exists only on the Mac).

## The owner's answers (2026-10-15)

The owner took every recommendation of the draft **except open on hover** (answer 7), and added five decisions (answers 13 to 17). Nothing below is open.

1. **A question without option descriptions stays exactly as it ships.** Only a card with descriptions changes. (To follow upstream instead: drop the `guard questions.contains(where: \.hasDescriptions)` line in `estimatedIslandHeight` and the `item.hasDescriptions ?` in `lineLimit`.)
2. **The transparent panel goes from 320 to 560 pt tall** (as upstream), so a tall question card is not clipped; it passes the mouse on outside the island.
3. **The click guard covers the permission card only.**
4. **The outside click is Mac only in U1.** The Windows/Linux version is a follow-up plan: it needs a Rust-side global mouse hook (Win32 `WH_MOUSE_LL`, installed only while expanded; Linux has no portable equivalent on Wayland), which cannot be tested without Docker and a Windows machine.
5. **The outside click folds when the button is released, not pressed**, and only if the pointer moved 4 pt or less, so a file taken out of a Finder window, a moved window or a selection never folds the island.
6. **The "Hover glow" switch is a row in General → Behavior**, next to "Open on hover"; no new box.
7. **Open on hover opens after a 150 ms dwell** (the owner's change to the recommendation, which was upstream's immediate open): the pointer must stay over the island 150 ms; leaving earlier cancels it; the usual hover peek is not delayed; one one-shot timer per hover, none while not hovering; it remains a setting, off by default. The Mac and Windows/Linux state machines have the same rule, pinned by tests: 149 ms no open, 150 ms open, leaving at 100 ms cancels (Task 7).
8. **"Close after" is wired in this plan** (`autoCloseSubscription`, one line); before, it never reached the Mac's state machine.
9. **The performance measurement is a tool of our own** (`scripts/measure-island-cpu.sh`), with the owner's Activity Monitor check (Task 16, item 6) as the final word. If the cat at 120 Hz is the cost, Task 8 stops and asks before capping its frame rate.
10. **A local, offline Rust probe is allowed** (a scratch cargo crate in a temp folder, outside the repo) as a check when Docker is down; `windows/scripts/cargo-linux.sh` stays the real run.
11. **The glow redraws at 30 frames a second while hovered**; `IslandGlow.framesPerSecond` is the knob.
12. **The version and the changelog are the release's.** This plan does not bump 0.9.2 and does not edit `CHANGELOG.md`. For 0.9.3's changelog: "Question cards show each option's description. A fresh permission card ignores clicks for a moment, so a click meant for another window cannot land on Allow. Click outside the open island to fold it. A soft rainbow glow along the island's edge on hover (Settings → Hover glow). Open on hover, after a short dwell (off by default). The Claude Code pill is now labelled Claude Code. Claude Code sessions from the Claude desktop app get their own pill. Antigravity asks instead of being blocked. Fixes: a crash an hour after a file edit; Windows: the island clipped on scaled displays, a pill label under its cat, a pill going idle in the middle of a turn."
13. **The `integration_claude` pill is labelled "Claude Code" everywhere**, on both apps; the ID stays frozen; the "Handled in VS Code / Terminal / iTerm…" notes still name the host app; `CLAUDE.md`'s HookOrigin bullet is updated by Task 12.
14. **The Claude Desktop pill's frozen ID is `agent_claude-desktop`** (tag `claude-desktop`, name "Claude Desktop", colour `#E3A857`). The owner suggested `integration_claude_desktop`; upstream's change shows the route is the relay's tag from `CLAUDE_CODE_ENTRYPOINT=claude-desktop` (not a bundle ID, which only says what the pill opens: `com.anthropic.claudefordesktop`), and NotchMeow's tagged agents are `agent_<tag>`, so the ID that follows the rule is `agent_claude-desktop`. Mac first; on Windows/Linux the relay tag, the pill's name and its colour are in this plan and "Open Claude" there is a follow-up.
15. **Both wings of the compact island step aside** (replacing the right-wing-only fade): hovering either wing swooshes the whole island into the notch on a spring (about 0.22 s, slight overshoot), its cats, grid and badges fade as it shrinks, the panel passes clicks to the menu-bar items under both wings, the hover zones stay at the full island's positions, it swooshes back out 1 s after the pointer leaves both wings, an alert cancels it at once, and the notch itself is the hover-open zone (150 ms dwell). Mac first (Task 14), fed by the existing poll. **Windows/Linux: a follow-up plan, listed with the outside click.**
16. **The left wing (the big cat) folds the island only after the pointer has rested there 0.4 s with no mouse button pressed; the right wing (the grid) folds it at once.** Any press during the 0.4 s cancels it (and starts the 0.4 s over once released), so a quick click, the drag-out to the desktop and a right-click on the big cat (the Wardrobe menu) work as today. The dwell is read from the existing `pollFrame` clock (no new timer). Pinned: 399 ms no fold, 400 ms fold, a press at 200 ms cancels, leaving cancels; and the source pins that the button test is every mouse button and the right-click monitor and `showWardrobeMenu` are untouched (Task 14).
17. **The Claude Desktop pill's visible name is "Claude App"** (the ID `agent_claude-desktop` is unchanged). The "Handled in Claude Desktop" notes keep the full name (`HookOrigin.hostName`). The pill, the Settings catalog, the sidekick's name for it and the Windows/Linux pill say "Claude App" (Task 13).

## Self-review

- **Scope coverage.** A1: Task 1; A2: Task 2; A3: Task 6; A4: Tasks 3 (Windows) and 5 (Mac); A5: Tasks 3 (Stop timer, padding) and 4 (zoom); A6: Task 7 (it respects the wing and costs nothing hidden, argued in the task and pinned); B7: Task 9; B8: Tasks 10 and 11, with the Settings switch on both, the theme group, Reduce Motion, light and dark pictures; C: Task 8 with a measurement before and after; the owner checkpoints with pictures (Tasks 6, 10, 11) and the real-build list (Task 16).
- **Models.** Haiku 5.5 first; Sonnet 5.5 only on Tasks 8 (trigger 2), 9 and 10 (trigger 1) and the whole-branch review (trigger 4). The session is Sonnet 5.5 high, with the reason given under "Execution".
- **Placeholders.** One deliberate blank pair: the commit message of Task 8 names the finding that task produces. Every other code step is a Create or Edit block from files the dry run ran, and every Run line has its expected output.
- **Type consistency.** `ApprovalClickGuard.duration` (Task 5) is what `ApprovalView` sleeps on; `ApprovalInfo.token` is the `.task` id; `QuestionLayout.height` (Task 6) is written by `pendingQuestion`'s `didSet` and read by `islandSize`; `openOnHover` is the same word in `AppState`, the FSMs, `Settings` (TS and Rust); `hoverGlow` is the same in `AppState` (Mac, key `island.hoverGlow`) and `Settings` (Windows/Linux); `IslandGlow.isShown(enabled:pointerOver:islandOnScreen:dragging:)` is called with exactly those labels in `IslandRootView`; `IslandOutsideClick.Context`'s six fields are the ones `handleOutsideClick` fills; `silent_answer(agent, event)` and `stdout_for(decision, agent, event)` (Task 1) have no other caller.
- **Wiring counts.** `scripts/test-u1-wiring.sh` grows 2 (Task 2), 6 (Task 5), 10 (Task 6), 17 (Task 7), 25 (Task 9), 31 (Task 10) lines; the dry run's full run printed `31 passed, 0 failed`. Task 8 adds its own.
- **What this plan deliberately does not do:** touch upstream's wardrobe, outfits or Mochi code; add a timer or poll; restyle a shipping view beyond what the owner approved; make the Windows/Linux question card or outside click; bump the version; change the cat's frame rate without asking.

## Dry run (2026-10-15)

The plan was run before it was handed over, in two throwaway `git clone --local --shared --branch notchmeow/rebrand` clones at `e8c28e9` (the scratchpad's `u1-draft`, where the tasks were first applied by hand and the pictures made, and `u1-replay`, built **only from this file**): a small runner read this file, applied each **Create** block and each **Edit** block in the plan's order (191 blocks; a find text that occurred other than once, or other than twice for the Mac relays' repeated lines, would have stopped it: **0 did**), and the commands below were then run on the result. The two trees differ only in the order of two declarations and in the three files the plan owns (`build.yml`, `CLAUDE.md` and the wiring script's incremental growth). Nothing was committed or pushed, no NotchMeow app was started (the installed one kept running), nothing was installed or downloaded, no image was built or pulled, Docker was down, and the only file this work added to the main checkout is this plan.

| Task | What the run printed (the plan's Expected) |
|---|---|
| 0 | `xcodegen` on the base changes nothing (`git status` empty); `windows/node_modules` copied by `cp -cR`; the Windows baseline is `ℹ tests 372` |
| 1 | red: `12 passed, 4 failed` (the four `got [{}]`); green `16 passed, 0 failed`; Rust through a local offline probe crate: `25 passed` (the hook crate's own tests, `main.rs` included, with its `connect` stubbed) |
| 2 | the pin pair red then green; the Debug build of the whole plan succeeded |
| 3 | `u1-guards.test.mjs` 6 pass; `tsc ok`; `check:cat` 378 |
| 4 | the three zoom tests pass in the probe crate; `tsc ok`. The Tauri crate itself (`set_zoom`, `inner_size`, `PhysicalPosition`) **needs Docker** and was not compiled; the page-side pins in `desktop-island.test.mjs` failed on the changed `screen-changed` line until the plan's Edit of that test was added |
| 5 | `Approval click guard: 3 checks passed`; wiring `6 passed`; Debug build succeeded after `xcodegen` (new files) |
| 6 | red: compile error; green `All tests passed.` with 9 new checks; wiring `10 passed`; the two pictures rendered and looked at (see below) |
| 7 | red: compile error; red: compile error; green `Island open on hover: 22 checks passed` after the owner's 150 ms dwell (the Mac test turns the dwell timer by hand through `armHoverOpen`: 149 ms no open, 150 ms open, leaving at 100 ms cancels, a card or alert during the dwell wins); Windows `fsm-hover.test.mjs` 9 pass (the same cases on mock timers); wiring 18; `check:cat` failed on `sleep.test.mjs` (a source pin on the changed `inIsland` line) until the plan's Edit of that test was added; `settings.rs` tests need Docker |
| 8 | the tool compiled and ran: see below |
| 9 | `Island outside click: 22 checks passed`; wiring 26; Debug build succeeded with no new warning in the new file |
| 10 | `test-theme.sh` red on three hard-coded lists (four groups, `Brand…State`, the CSS count 84 against 88) until the plan's Edits of them; green `# pass 8`, `✓ 3 theme files`; `Island hover glow: 16 checks passed`; wiring 31; Debug build succeeded; the sheet rendered and looked at (see below) |
| 11 | `hover-glow.test.mjs` 3 pass; the CSS rendered in a browser pane and looked at |
| 12 | red: wiring pins and `pill-labels.test.mjs` fail on the old label; green after the Edits; `check-no-leftovers` green; the `grep` for `"VS Code"` in the sources leaves only host-app lines |
| 13 | `HookOriginTests` 9 new checks green; `test-hook-relay.sh` listens on the Unix socket the relays open and reads what they send: `28 passed, 0 failed` (the desktop tag, an explicit `--agent` winning, four untagged entrypoints, both relays); Rust probe: `27 passed` for the hook crate, the two new tests included; wiring 44 in all; Windows `pills.test.mjs` extended; `render-pills.sh` drew Claude Code, Claude App, Gemini CLI and Cursor (at the real 134 pt pill width "Claude App" clears the cat; the longer "Claude Desktop" had just touched its ear): Task 13 says to report it to the owner rather than restyle the pills |
| 15 (Windows run) | the replay tree (after Task 14, nothing of it touches `windows/`): `ℹ tests 393`, `ℹ pass 393`, `ℹ fail 0`, `tsc ok` |
| 14 | the new `IslandWingTests` (both wings, the slop, the notchless bar, the folded widths, the alert, the fold and the one-second return, the button, a clock that is not a time, the 20000-tick fuzz, and the owner's left-wing dwell: 399 ms no fold, 400 ms fold, a press at 200 ms cancels and the dwell restarts on release, leaving cancels, the right wing needs none, the button is asked only on the left wing; the 0.4 s needed a 1e-9 tolerance, since 1.4 - 1.0 is 0.3999999999999999 in binary floating point) green against the rewritten `IslandWing.swift`; `IslandWingWiringTests` and, after its one pin was updated, `ShelfWiringTests` green; the Debug and App Store builds both `** BUILD SUCCEEDED **` in the replay tree; `render-cats.sh --wing` took 15 seconds; the first picture showed the cats not fading in the swooshed-in strip (the render's cats ignore the context's alpha), fixed with a transparency layer, which the plan's `drawCompact` edit now has; the second shows the four strips as Step 4 describes (rest, mid-swoosh with the cats half faded, swooshed in with all seven icons visible and both wings dashed, and the pointer on the left wing) |
| 15 | all the Mac checks above in the replay tree; builds: Debug `** BUILD SUCCEEDED **`, Release `** BUILD SUCCEEDED **`, App Store `** BUILD SUCCEEDED **`; `check-app-binary.sh` passes for the App Store and the Release app; `check-ask-unchanged.sh notchmeow/rebrand` green |

**The pictures** (looked at by the agent that made them):

- `question-desc.png` (the card with three option descriptions, a two-line question and "Other…", island 640 x 330 pt): everything is visible and nothing is cut; `question-plain.png` (no descriptions, island 160 pt): the chips card as it ships, the question cut with an ellipsis, which is exactly what the descriptions card avoids.
- `hover-glow.png` (the Mac sheet): the 3 pt multicolour edge follows the open island's and the compact strip's outlines on light and dark bars; **the wide blurred halo did not show in the offscreen render** and the third row of the sheet had uneven panel heights. Task 10's Step 5 says how to fix both (`.drawingGroup()`, fixed panel frames). The render took about seven minutes.
- `win-glow.png` (a browser render of the Windows/Linux CSS on a localhost page): the ring is visible on the light and the dark backdrop for the open and the compact island; the halo is weaker than the ring.

**What the dry run changed in the plan** (each was a defect in an earlier draft):

- **Two existing test files pin lines this plan changes** (`desktop-island.test.mjs`: the `screen-changed` handler; `sleep.test.mjs`: the hover enter test), and `tests/theme/gen-theme.test.mjs` hard-codes the group list: the plan now edits all three.
- **`autoCloseInterval` never reached the Mac's state machine**, so "Close after" did nothing to the fold delay; Task 7 wires it (owner's answer 8).
- **The upstream question card grew every question's island**, restyling the chips card; the plan only changes a card with descriptions.
- **A press outside the island can be the start of a Finder file drag**; the outside click folds on release of a click (4 pt slop), not on the press (owner's answer 5).
- **The permission card has no request id on the Mac**; `ApprovalInfo.token` is the plan's.
- **Rust can be run locally and offline for pure functions** (the probe crate), which proves the logic when Docker is down; the Tauri crate cannot.
- **The last two owner answers (the 0.4 s left-wing dwell, and the visible name "Claude App") were folded in and re-run**: the wing rules, tests and pins, the pills tests, both Mac builds and the two pictures.
- **Open on hover's dwell, the pills and the wings changed the Mac builds**: Debug and App Store both build in the replay tree after all of them.
- **Four owner decisions arrived mid-run and were added or folded in, each re-run in the replay tree**: the 150 ms dwell for Open on hover (Task 7; the Mac test turns the dwell timer by hand), the two pill decisions (Tasks 12 and 13), and the two-wing swoosh (Task 14; CI and the checkpoint are now Tasks 15 and 16). Two existing sidekick pins broke on the Claude Desktop change (the five-case route pin, and the rule that `AgentTarget.swift` never names `.claude`: the constants are named `desktopTag`, `desktopPill`, `desktopBundleId` for that); `ShelfWiringTests` pinned the old wing call sites. The plan edits all three. The relay test for the new tag needed a real socket; bash 3.2 mangles a heredoc inside a process substitution (the Python is written to a file first).
- **`measure-island-cpu.sh` works**, but a first, unoptimised run on a loaded machine is not the QA's number; Task 8 says how to read it and now builds with `-O`.
- **The render tools take about seven minutes**, not the "two" their headers say; the plan says so.

**Not run, and owed.**

- **Any commit step.** Every `git add` and `git commit` block was skipped and has to be run by the executing session in its worktree.
- **The apps themselves.** No NotchMeow window was opened: the outside click, the hover glow's fade, Open on hover, the click guard, the grown question island and the panel's 560 pt height are Task 16's list, because only a real build can show them. `measure-island-cpu.sh` opened a nearly invisible panel for about 50 seconds; the real app was not touched.
- **Rust that needs Tauri or Docker**: `island.rs`, `lib.rs` and `settings.rs` were edited but not compiled; `windows/scripts/cargo-linux.sh` is the real run (Tasks 4, 7, 11, 12).
- **The Windows pill padding and the glow in the real island page**, the Settings page renders (Mac and Windows), CI's first run of the new steps.
- **The performance finding itself** (Task 8's table and fix).

The throwaway clones (`u1-draft`, `u1-replay`, `base-probe`), the probe crate and the pictures were left in the scratchpad.
