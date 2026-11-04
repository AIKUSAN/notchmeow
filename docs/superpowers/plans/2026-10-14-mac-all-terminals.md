# All terminals on the Mac: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Mac island shows Claude Code sessions from every terminal (Terminal, iTerm, Ghostty, Warp, kitty and the rest), as the Windows and Linux app already does, and not only the ones started from VS Code and Cursor; every VS Code, Cursor, Codex and tagged-agent behaviour that ships stays as it is.

**Architecture:** Today `HookServer` repeats one editor test in three places (`processEvent`, `processPermissionRequest` and the `--ask` question path): a Claude Code event whose `term_program` or `bundle_id` is not VS Code or Cursor is logged "Ignored", and its permission request or question is answered `ask` at once, so the terminal asks as if NotchMeow were not there. This plan pulls the routing into one pure Foundation file, `HookOrigin.swift` (which pill an event belongs to, the name of the app the user is in, the app to bring forward), tested by `scripts/test-hook-origin.sh`, and makes the three places call it. **Everything that is not Cursor, Codex or a tagged agent is Claude Code** and goes to the Claude Code pill, whatever terminal it came from. The pill keeps its ID (`integration_claude`) and its "VS Code" label (never restyle what ships; the Windows app labels it the same). Two words that were VS Code's alone become the app the session runs in: the notes "Handled in …" and "Still waiting in …" (`HookOrigin.note`), and the pill's tap, which brings that app forward (GitHub build only, like the other terminal routes). A wiring test pins the call sites, a script sends a scripted terminal session to a Debug build for the owner's check, and the docs say what is true.

**Tech Stack:** Swift 6 (a pure Foundation file, SwiftUI and AppKit call sites), `swiftc` test programs, Bash, Python 3 (the fake-events script, standard library only), XcodeGen.

**Spec:** the owner's decision of 2026-10-14, "Rounds, Prerequisite round" in `docs/superpowers/specs/2026-10-14-agent-sidekick-design.md` (widen the Mac to Claude Code sessions in every terminal, as Windows does). There is no spec file of its own. The rules it keeps are in `CLAUDE.md` ("Never block Claude Code", "Never approve without an explicit click", "Never restyle what ships") and `docs/INTEGRATIONS.md`.

**Base:** a new branch `mac/all-terminals` in a git worktree, from `notchmeow/rebrand` at `793b502` or later (`git merge-base --is-ancestor 793b502 HEAD` must succeed, and this plan file must be in the tree: the owner commits it first). Nothing under `windows/` changes, and no fixture of `tests/fixtures/` or `design/prototype/` is touched.

## Why upstream limited it (the research behind this plan)

Read in the code on 2026-10-14; the plan keeps every one of these in mind.

- **It is not a limit of the hooks.** Claude Code's hooks fire from any terminal, the relay (`nm-hook.py`) already adds `term_program` (`TERM_PROGRAM`) and `bundle_id` (`__CFBundleIdentifier`) to every event, and the Windows app has always handled every terminal (`windows/src/island/hooks.ts`: "no terminal filter"). The filter is the original app's, from its first release (`af080da`), where the Claude Code pill **was** the "VS Code" pill.
- **That is the real reason.** `PillCatalog` names `integration_claude` "VS Code" in the category "Where you code"; `IslandViewContent` forces the label "VS Code" on it, its tap opens VS Code, its integration card offers "Open Visual Studio Code", and the notes say "Handled in VS Code". "A VS Code or Cursor event" was how the original told "my editor's session" from noise. Nothing else depended on the filter: the ⌃⌥T terminal-forward (`IslandWindowController.performJumpToTerminal`) never reads `term_program` (it brings the first running terminal forward), and the Gemini and Antigravity pill taps already do the same.
- **What the filter also kept out**, and now comes in as on Windows: Claude Code runs started by other tools (a terminal inside JetBrains or Zed, a script's headless `claude -p`, `ssh` and `tmux` sessions with no bundle ID). They have a session, steps and approvals like any other. **A chat's own Claude Code run (sub-project E3) is not one of them:** `ClaudeHookRouting.route` filters it out before the routing, and a test pins that order.
- **The cost, accepted:** two Claude Code sessions at once (VS Code and a terminal, or two terminals) share the one Claude Code pill and the island's single "active session", so the island shows the last one that spoke. This is how the Mac already behaves for two VS Code windows and how Windows behaves for everything. An approval still closes only on its own session's events (`sessionId == pending.sessionId`, pinned).

## Global Constraints

Every task's requirements include this section.

- **Swift 6, SwiftUI and AppKit; no third-party dependencies.** Shell scripts are Bash 3.2 compatible (macOS). The fake-events script is Python 3 standard library only.
- **Never block Claude Code.** The relay and the server's answering are untouched: no new reply, and the 115 s give-up stays. A terminal session's permission request now waits, like VS Code's, for the approval card, up to about 118 s, while NotchMeow runs and a card is open (owner's decision at the checkpoint, 2026-10-14: option A, the card for terminal sessions as for VS Code and Windows). It never waits when NotchMeow is not running (the relay's connect fails and it exits at once), and a request the app cannot show still answers `ask` at once.
- **Never approve without an explicit click; never overwrite `~/.claude/settings.json`.** No task reads or writes the real `~/.claude`, `~/.gemini` or `~/.codex`, and no task installs a hook.
- **Never restyle a shipping view.** The pill keeps its ID `integration_claude` and its label "VS Code". The notes and the pill's tap change only for a session that is not in VS Code, Cursor or Codex; for those three every string and route is byte for byte what it was.
- **Frozen values.** Pill IDs, cat IDs, display mode IDs, UserDefaults keys and every contract string (`nm-hook`, `nm.sock`, `nm_kind`, `nm_agent`, the bundle identifiers) are untouched. This plan stores nothing.
- **0 % CPU when the island is hidden, and no polling of its own.** `HookOrigin` is a pure function: no `Timer`, no monitor, no `NSWorkspace`, no clock. `AppState.hostBundleIds` is set by the events that already arrive and is not `@Published`.
- **The App Store build gains nothing it cannot do:** bringing a terminal forward is under `#if !APPSTORE`, as every other terminal route is; Codex stays the GitHub build's.
- **Never edit `NotchBuddy.xcodeproj` by hand.** Task 1 adds one Swift file to the app, so it runs `cd NotchBuddy && xcodegen` and commits the regenerated `project.pbxproj` (6 inserted lines). The test files are test programs and are not in the project.
- **No `UserDefaults` suite and no write to `UserDefaults.standard` or `~/Library` in a test or script.** Tests run through `scripts/test-*.sh`, which set `NM_LOG_DIR` to a temp folder (`CT.section` stops a test program run by hand).
- **Models and commits** (CLAUDE.md, "Working with AI agents", 2026-10-12): Haiku 5.5 first, Sonnet 5.5 only on a named trigger, never Opus or Fable. Each commit is local only, never pushed, lists only the files its task names, and ends with `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>` (`Claude Sonnet 5.5` for a task handed to `nm-implementer-deep`).
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app, and **never run the real `claude`**. A Debug or App Store **build** in the worktree is fine and is only built. No task sends a hook event to the app's socket: `scripts/test-fake-terminal-events.sh` sends only to a socket of its own, and `scripts/fake-terminal-events.py` against the real socket is the owner's check (Task 4).
  2. Install nothing. No network calls, no downloads, no `docker build` or `docker pull`.
  3. Use `trash`, never `rm -rf`, for anything you delete by hand; put scratch files under `${TMPDIR:-/tmp}` in a folder with a unique name. (The test scripts clean their own `mktemp` folders with `rm -rf` in a `trap`, as every `scripts/test-*.sh` does: that is the repo's convention, not a command an agent runs.)
  4. No `UserDefaults` suite and no write to `UserDefaults.standard` or `~/Library` in a test or script.
  5. Never edit `design/prototype/cat-core.js`, a fixture of `tests/fixtures/`, `shared/theme.json`, a generated theme file or anything under `windows/`.
  6. Never push. Commit only in a task's commit step, after checking the worktree and the branch.
  7. Haiku 5.5 for every task; Sonnet 5.5 (`nm-implementer-deep`) only for a task Haiku failed twice, with the trigger named in the ledger; never Opus or Fable.
  8. Never rename a frozen ID, and write no `Coucou` or `Mochi` name anywhere (`scripts/check-no-leftovers.sh` must stay green).
  9. Never read, print or write the real `~/.claude/settings.json` (or anything in the real `~/.claude`, `~/.gemini`, `~/.codex`), by hand or in a script.
  10. If a command is denied by a permission prompt, stop and report it. Do not look for a workaround.

## Review Focus

The goal says what changes. It is silent on these conditions, and each would bite a person first, most likely first. Each names the test that pins it.

1. **A Claude Code session with no terminal facts at all** (`ssh`, `tmux`, a script's headless `claude -p`, an app that sets neither `TERM_PROGRAM` nor a bundle ID). Expected: it shows on the Claude Code pill, its approval card says "Handled in the terminal." / "Still waiting in the terminal.", and the pill's tap falls back to VS Code's route as before, never to a crash or a wrong app. Tests: Task 1 ("nothing known", "tmux with nothing else"), Task 2 (the tap's order is pinned).
2. **A chat's own Claude Code run must still never appear as a session.** It has no `nm_agent` and, run from the app, no terminal facts, so the widened routing would take it for a terminal session if the chat filter did not come first. Expected: the filter stays before the routing in `processEvent`, and `processPermissionRequest` and the question path still hand it to the chat. Test: Task 2 ("a chat's own run is filtered before the routing").
3. **Two sessions on the one pill (VS Code and a terminal, or two terminals).** Expected: one session's `Stop` or `PostToolUse` never closes the other's approval card. Test: Task 2 (the resolving events still compare `sessionId`).
4. **Cursor, Codex and tagged agents.** Expected: a Cursor bundle ID in any letter case is Cursor and another ToDesktop app is not; a Codex tag is Codex in the GitHub build and an ordinary external agent in the App Store build; a tagged agent's permission request and question are still answered `ask` at once and its events keep its own pill, **even when it runs in a terminal** (before, the question path let a tagged agent that ran inside VS Code through to the Claude Code pill; now it answers `ask`, the one deliberate difference, and only a hand-made payload can reach it because only Claude Code and Codex install the `--ask` hook). Tests: Task 1 (the pill rows), Task 2 (the three `.external` answers).
5. **The App Store build.** Expected: it builds, brings no app forward, and keeps Codex out. Tests: Task 2 (both builds, the `#if !APPSTORE` pin).

---

## File Structure

| Path | Responsibility |
|---|---|
| `NotchBuddy/Sources/App/HookOrigin.swift` (new) | The pure rules: `route`, `pillId`, `isVSCode`, `hostName`, `note`, `terminalBundleId` (Task 1). |
| `tests/HookOriginTests.swift` (new), `scripts/test-hook-origin.sh` (new) | The rules against their cases (Task 1). |
| `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`, `.github/workflows/build.yml` | The new file in the project, and the CI steps (Tasks 1 to 3). |
| `NotchBuddy/Sources/App/HookServer.swift`, `IslandTypes.swift`, `AppState.swift`, `IslandViewContent.swift` | The three entry points call the rules; `ApprovalInfo.host`; `AppState.hostBundleIds`; the pill's tap (Task 2). |
| `tests/HookOriginWiringTests.swift` (new), `scripts/test-hook-origin-wiring.sh` (new) | The source pins of those call sites (Task 2). |
| `scripts/fake-terminal-events.py` (new), `scripts/test-fake-terminal-events.sh` (new) | The owner's scripted terminal session, and its test against a socket of its own (Task 3). |
| `docs/QA-MAC.md`, `docs/INTEGRATIONS.md`, `CLAUDE.md` | The wording that is now true, and the map bullet (Task 3). |

## Tasks and agents

CLAUDE.md: the lightest model that fits. **Haiku 5.5 first; Sonnet 5.5 only on a named trigger.** Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion` (the deep agent also `superpowers:systematic-debugging`); reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). Effort: **high** for `nm-implementer` and every review.

| # | Task | Agent, model, effort | Review |
|---|---|---|---|
| 0 | Worktree and baseline | the session | none |
| 1 | The pure routing rules and their test | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 2 | The three entry points, the notes and the pill's tap, with the wiring pins | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 3 | The fake terminal session, and the docs | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| After 3 | The whole branch: the routing against the old behaviour, the chat filter, the privacy and approval rules | `nm-reviewer-deep`, Sonnet 5.5, high (trigger 4: it is the code that decides which agent sessions may raise an approval card) | none |
| 4 | **Owner checkpoint:** the owner sends a fake `Apple_Terminal` session to a Debug build and looks at the island | the main session and the owner | none |

**No task needs Sonnet up front.** Every code block is given in full and was applied in the dry run. Task 2 edits a 2,400-line file at eight places, but every edit is a find-and-replace given in full and nothing designs a platform API. If a Haiku task's expected output differs and the cause is not obvious, or it fails twice, hand that task to `nm-implementer-deep` (trigger 2) and say so in the ledger.

## Execution

One worktree chat session runs the whole plan: branch `mac/all-terminals`, model **Haiku 5.5 at high effort**. **This is not trigger 5**: it is one app, four small tasks, no concurrency and no platform API to design. Nothing is pushed. It edits `HookServer.swift` and `IslandViewContent.swift`, so it should not run beside another plan that does.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up (it carries the owner's advance approval of the brief in step 3):

   > Run `git switch -c mac/all-terminals notchmeow/rebrand`, then Task 0 of `docs/superpowers/plans/2026-10-14-mac-all-terminals.md`: only its Steps 1 and 2 (the base checks: `git merge-base --is-ancestor 793b502 HEAD` must succeed and the plan file must exist). Read `CLAUDE.md`, `ARCHITECT.md` and that plan. If a base check fails, say so and stop. Reply "ready" and stop. Do not start Task 1. The owner approves in advance the controller brief the main session will send as your next message.

2. **Model.** Once the owner starts the chip, the main session sets that session to Haiku 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-14-mac-all-terminals.md` with `superpowers:subagent-driven-development`, task by task, on branch `mac/all-terminals`. Dispatch each task to the agent the plan's "Tasks and agents" table names (Haiku 5.5 first; Sonnet 5.5 only for a task Haiku failed twice, and then the trigger goes in the ledger), then to `nm-reviewer`; fix what the review finds before the next task. Rules for you and for every subagent (put the plan's SUBAGENT RULES block in every brief):
>
> - **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder (under `.claude/worktrees/`), the second `mac/all-terminals`. If either is wrong, stop and report. Commit with `git commit -F <file>`, never `-m`, with the trailer of the model that did the task. Never push.
> - **Ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-14-mac-all-terminals/progress.md`: one line per task with its agent, model, commit hash, test lines and review verdict, and any escalation to `nm-implementer-deep` with the trigger.
> - **Briefs are task-sized.** A brief carries one task: its text, the Global Constraints, the SUBAGENT RULES and the files it names. Never hand a subagent the whole plan.
> - **Reviews** read `git diff notchmeow/rebrand...HEAD` (three dots), narrowed to the task's files, never `..` and never a diff against a moving working tree.
> - **Every shell block in the plan passes `bash -n` before it is run**, and a script you write passes it too.
> - **Servers and processes.** Stop a server only by the PID you saved when you started it. Never launch, quit or replace a NotchMeow app: the builds are builds. Never run the real `claude`. Install and download nothing. Never read the real `~/.claude`.
> - **Stop and report on any refusal** (a denied command, a permission prompt): do not look for a workaround.
> - **Ping the main session.** The main session's name in the agent list is `NotchMeow — fork research & cat design`. At the owner checkpoint (Task 4), at the end, and whenever you stop (a refusal, a failed check, a question), send your report to it with `SendMessage` addressed to that name, as well as writing it in your own chat, so the main session can double-check the work (its own clone, merge and full checks) before anything reaches the owner.
> - **Owner checkpoint.** Run Tasks 1 to 3, dispatch `nm-reviewer-deep` over the whole branch, fix what it finds, then stop and report to the main session (Task 4): say which Debug build to run, the exact command of Task 4, and what to look for.
>
> Report: the commits; the output of `bash scripts/test-hook-origin.sh`, `bash scripts/test-hook-origin-wiring.sh`, `bash scripts/test-fake-terminal-events.sh`, `bash scripts/test-ask-question.sh`, `bash scripts/test-claude-code.sh`, `bash scripts/test-cat-wiring.sh`, `bash scripts/test-cat-kitten-hooks.sh`, `bash scripts/test-island-wing-wiring.sh`, `bash scripts/test-cat-desktop-wiring.sh` and `bash scripts/check-no-leftovers.sh`; the Debug and App Store build lines; and anything you could not settle.

Before any follow-up turn (a fix round, a question, a resumed run), the main session checks the session is still on its configured model and effort.

## How to run this plan

**Blocks.** A code step is either **Create `path`** (the file's exact content) or **Edit `path`** (a find text that occurs exactly once, and its replacement). Apply an edit by replacing the find text with the replacement and nothing else; if the find text occurs zero or two times, stop and report: the tree is not what the plan expects. Never type a block from memory and never "improve" one. Every `Run:` line is run from the repository root (the worktree's top folder); `Expected: FAIL` and `Expected: PASS` say which way it must go, and the text after it says what to see.

**Mac commands.** The test programs are `swiftc` programs run through `scripts/test-*.sh`; none needs Xcode. A build is `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO` (the App Store target is `-scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store`, with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`). A build only builds: do not open the app. Pipe a build through `grep -E "BUILD|error:"`.

**Bite steps.** Some steps break the code on purpose to prove a test fails. Back the file up into a folder you made with `mktemp -d`, change it with the command given, run the test, and copy the backup back; the next step starts from the restored file. After each bite, `git diff --stat` must show only what the task has done so far.

---
## Tasks

### Task 0: Worktree and baseline

No code and no commit. Its first two steps are what the chip's prompt runs before the model is set (see "Execution").

- [ ] **Step 1: Put the session's worktree on the plan's branch**

```bash
git status                                    # must be clean
git switch -c mac/all-terminals notchmeow/rebrand
git merge-base --is-ancestor 793b502 HEAD && echo "the base (793b502) is in the history"
test -f docs/superpowers/plans/2026-10-14-mac-all-terminals.md && echo "the plan is in the tree"
git log --oneline -3
```

Expected: `the base (793b502) is in the history` and `the plan is in the tree`. If either line is missing, the worktree was cut from an older base or before the owner committed this plan: stop and tell the owner. Every later command runs from the root of this worktree. Never push.

- [ ] **Step 2: Check the places this plan edits are as it expects**

```bash
grep -c 'let isVSCodeEditor = !isCursorEditor' NotchBuddy/Sources/App/HookServer.swift
grep -c 'nbLog("Ignored' NotchBuddy/Sources/App/HookServer.swift
grep -c 'guard isCodexRequest || isCursorEditor || isVSCodeEditor else' NotchBuddy/Sources/App/HookServer.swift
grep -c 'Handled in VS Code' NotchBuddy/Sources/App/HookServer.swift
grep -c 'var subagentId: String? = nil' NotchBuddy/Sources/App/IslandTypes.swift
grep -c 'let vscodeBundleId = "com.microsoft.VSCode"' NotchBuddy/Sources/App/IslandViewContent.swift
test -e NotchBuddy/Sources/App/HookOrigin.swift && echo "HookOrigin.swift exists already" || echo "HookOrigin.swift is new"
```

Expected: `3`, `1`, `2`, `2`, `1`, `1`, then `HookOrigin.swift is new`. Anything else: stop and report.

- [ ] **Step 3: Baseline: the checks this plan must not move**

```bash
for t in test-ask-question test-claude-code test-cat-wiring test-cat-kitten-hooks test-island-wing-wiring test-cat-desktop-wiring test-cat-cast test-session-steps; do echo "== $t"; bash scripts/$t.sh 2>&1 | tail -1; done
bash scripts/check-no-leftovers.sh 2>&1 | tail -1
```

Expected: eight `All tests passed.` lines under their `== name` headers, then a `✓` line from the leftovers guard.

- [ ] **Step 4: Read the base once**

Read, without changing: `NotchBuddy/Sources/App/HookServer.swift` (`processEvent` from "Event → AppState", `processPermissionRequest`, and the `--ask` question path that starts "let rawAgent    = payload"), `NotchBuddy/Sources/App/AI/Core/ClaudeHookRouting.swift`, and `NotchBuddy/Sources/App/IslandViewContent.swift` (`openAgentTarget`). Write one sentence in the ledger on where the chat filter sits relative to the editor test.

---

### Task 1: The pure routing rules and their test

**Files:**
- Create: `NotchBuddy/Sources/App/HookOrigin.swift`, `tests/HookOriginTests.swift`, `scripts/test-hook-origin.sh`
- Edit: `.github/workflows/build.yml`, and the regenerated `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces (Task 2 calls these exactly): `HookOrigin.route(rawAgent: String, validAgent: String?, codexEnabled: Bool, bundleId: String) -> HookOrigin.Route`; `enum Route: Equatable { case codex, external(String), cursor, claude }`; `HookOrigin.pillId(_ route: Route) -> String`; `HookOrigin.isVSCode(termProgram:bundleId:) -> Bool`; `HookOrigin.hostName(pillId:termProgram:bundleId:) -> String`; `HookOrigin.note(host:stillWaiting:) -> String`; `HookOrigin.terminalBundleId(termProgram:bundleId:) -> String?`.

- [ ] **Step 1: Write the test first**

**Create `tests/HookOriginTests.swift`**

```swift
import Foundation

// Which pill a hook event belongs to (HookOrigin): the cases HookServer used to decide with three copies of an editor test. Run from the repository root through
// scripts/test-hook-origin.sh.

@main
enum HookOriginTests {
    typealias O = HookOrigin

    static func route(_ agent: String = "", valid: String? = nil, codex: Bool = true, bundle: String = "") -> O.Route {
        O.route(rawAgent: agent, validAgent: valid, codexEnabled: codex, bundleId: bundle)
    }

    @MainActor static func main() {
        CT.section("the pill: a Claude Code event belongs to the Claude Code pill from VS Code and from any terminal")
        CT.check("VS Code", O.pillId(route(bundle: "com.microsoft.VSCode")), "integration_claude")
        CT.check("Terminal", O.pillId(route(bundle: "com.apple.Terminal")), "integration_claude")
        CT.check("iTerm", O.pillId(route(bundle: "com.googlecode.iterm2")), "integration_claude")
        CT.check("Ghostty", O.pillId(route(bundle: "com.mitchellh.ghostty")), "integration_claude")
        CT.check("Warp", O.pillId(route(bundle: "dev.warp.Warp-Stable")), "integration_claude")
        CT.check("a tmux session with no bundle ID at all", O.pillId(route()), "integration_claude")
        CT.check("an event with an empty payload", O.pillId(route("", valid: nil, bundle: "")), "integration_claude")

        CT.section("Cursor, Codex and tagged agents keep their pills")
        CT.check("Cursor, told apart by its bundle ID in any letter case", [O.pillId(route(bundle: "com.todesktop.230313mzl4w4u92")), O.pillId(route(bundle: "COM.TODESKTOP.230313MZL4W4U92"))], ["agent_cursor", "agent_cursor"])
        CT.check("another ToDesktop app is not Cursor", O.pillId(route(bundle: "com.todesktop.123456abc")), "integration_claude")
        CT.check("Codex in the GitHub build", O.pillId(route("codex", valid: "codex", bundle: "com.apple.Terminal")), "agent_codex")
        CT.check("a Codex tag in the App Store build is an ordinary external agent", route("codex", valid: "codex", codex: false), .external("codex"))
        CT.check("a tagged agent", O.pillId(route("gemini", valid: "gemini", bundle: "com.apple.Terminal")), "agent_gemini")
        CT.check("a tag that did not validate is no agent: the event is Claude Code's", route("Bad Agent!", valid: nil), .claude)
        CT.check("a tagged agent from Cursor's window is still that agent", O.pillId(route("gemini", valid: "gemini", bundle: "com.todesktop.230313mzl4w4u92")), "agent_gemini")

        CT.section("the editor test the three call sites repeated")
        CT.checkTrue("TERM_PROGRAM vscode", O.isVSCode(termProgram: "vscode", bundleId: ""))
        CT.checkTrue("a VS Code bundle ID", O.isVSCode(termProgram: "", bundleId: "com.microsoft.VSCode"))
        CT.checkTrue("VS Code Insiders", O.isVSCode(termProgram: "", bundleId: "com.microsoft.VSCodeInsiders"))
        CT.checkTrue("Cursor is not VS Code, even with TERM_PROGRAM vscode", !O.isVSCode(termProgram: "vscode", bundleId: "com.todesktop.230313mzl4w4u92"))
        CT.checkTrue("Terminal is not", !O.isVSCode(termProgram: "Apple_Terminal", bundleId: "com.apple.Terminal"))

        CT.section("where the user is: the words of the notes")
        CT.check("VS Code reads as it always did", O.hostName(pillId: "integration_claude", termProgram: "vscode", bundleId: "com.microsoft.VSCode"), "VS Code")
        CT.check("Cursor", O.hostName(pillId: "agent_cursor", termProgram: "vscode", bundleId: "com.todesktop.230313mzl4w4u92"), "Cursor")
        CT.check("Codex", O.hostName(pillId: "agent_codex", termProgram: "Apple_Terminal", bundleId: "com.apple.Terminal"), "Codex")
        CT.check("Terminal by its bundle ID", O.hostName(pillId: "integration_claude", termProgram: "", bundleId: "com.apple.Terminal"), "Terminal")
        CT.check("Terminal by TERM_PROGRAM alone", O.hostName(pillId: "integration_claude", termProgram: "Apple_Terminal", bundleId: ""), "Terminal")
        CT.check("iTerm", O.hostName(pillId: "integration_claude", termProgram: "iTerm.app", bundleId: "com.googlecode.iterm2"), "iTerm")
        CT.check("Ghostty", O.hostName(pillId: "integration_claude", termProgram: "ghostty", bundleId: "com.mitchellh.ghostty"), "Ghostty")
        CT.check("Warp, whatever its channel", O.hostName(pillId: "integration_claude", termProgram: "WarpTerminal", bundleId: "dev.warp.Warp-Preview"), "Warp")
        CT.check("a terminal we have no name for", O.hostName(pillId: "integration_claude", termProgram: "tmux", bundleId: "org.example.Term"), "the terminal")
        CT.check("nothing known", O.hostName(pillId: "integration_claude", termProgram: "", bundleId: ""), "the terminal")
        CT.check("the two notes", [O.note(host: "VS Code", stillWaiting: false), O.note(host: "Terminal", stillWaiting: true)], ["Handled in VS Code.", "Still waiting in Terminal."])

        CT.section("the app to bring forward")
        CT.check("the app that started the session wins", O.terminalBundleId(termProgram: "Apple_Terminal", bundleId: "com.jetbrains.intellij"), "com.jetbrains.intellij")
        CT.check("TERM_PROGRAM when the relay saw no bundle ID", [O.terminalBundleId(termProgram: "Apple_Terminal", bundleId: ""), O.terminalBundleId(termProgram: "iTerm.app", bundleId: "")], ["com.apple.Terminal", "com.googlecode.iterm2"])
        CT.check("Ghostty and WezTerm", [O.terminalBundleId(termProgram: "ghostty", bundleId: ""), O.terminalBundleId(termProgram: "WezTerm", bundleId: "")], ["com.mitchellh.ghostty", "com.github.wez.wezterm"])
        CT.check("VS Code keeps its own route", O.terminalBundleId(termProgram: "vscode", bundleId: "com.microsoft.VSCode"), nil)
        CT.check("so does Cursor", O.terminalBundleId(termProgram: "vscode", bundleId: "com.todesktop.230313mzl4w4u92"), nil)
        CT.check("tmux with nothing else: no app to name", O.terminalBundleId(termProgram: "tmux", bundleId: ""), nil)

        CT.finish()
    }
}
```

**Create `scripts/test-hook-origin.sh`**

```bash
#!/usr/bin/env bash
# Which pill a hook event belongs to (HookOrigin): VS Code and every terminal reach the Claude Code pill, Cursor, Codex and tagged agents keep theirs, the notes name
# the app the user is in. Pure Foundation; nothing here launches or touches NotchMeow.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-hook-origin.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/HookOrigin.swift \
    tests/CatTestSupport.swift tests/HookOriginTests.swift \
    -o "$TEST_DIR/hook-origin-tests"
"$TEST_DIR/hook-origin-tests"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash -n scripts/test-hook-origin.sh && bash scripts/test-hook-origin.sh`
Expected: FAIL: `error opening input file 'NotchBuddy/Sources/App/HookOrigin.swift' (No such file or directory)`.

- [ ] **Step 3: Write the rules**

**Create `NotchBuddy/Sources/App/HookOrigin.swift`**

```swift
import Foundation

// Which pill a hook event belongs to, and where its user answers: the rules `HookServer` used to hold as three copies of an editor test.
// Claude Code reaches the Claude Code pill (`integration_claude`) from VS Code or from any terminal (Terminal, iTerm, Ghostty, Warp, kitty and the rest),
// as it does on Windows and Linux. Cursor and Codex keep their own pills, and a tagged agent (`nm_agent`) keeps its own.
// Pure Foundation, tested by scripts/test-hook-origin.sh. The pill's ID and its "VS Code" label do not change.

enum HookOrigin {
    enum Route: Equatable {
        case codex
        case external(String)   // a valid `nm_agent`
        case cursor
        case claude             // Claude Code, from VS Code or from a terminal
    }

    static let cursorBundleId = "com.todesktop.230313mzl4w4u92"

    /// `codexEnabled` is false in the App Store build, where a Codex tag is an ordinary external agent. `validAgent` is `rawAgent` once `HookServer.validateAgent` has passed it.
    static func route(rawAgent: String, validAgent: String?, codexEnabled: Bool, bundleId: String) -> Route {
        if codexEnabled && rawAgent == "codex" { return .codex }
        if let agent = validAgent { return .external(agent) }
        if bundleId.lowercased() == cursorBundleId { return .cursor }
        return .claude
    }

    static func pillId(_ route: Route) -> String {
        switch route {
        case .codex: return "agent_codex"
        case .external(let agent): return "agent_\(agent)"
        case .cursor: return "agent_cursor"
        case .claude: return "integration_claude"
        }
    }

    /// The editor test the three call sites used to repeat (Cursor is told apart before it, by its bundle ID).
    static func isVSCode(termProgram: String, bundleId: String) -> Bool {
        bundleId.lowercased() != cursorBundleId && (termProgram.lowercased().contains("vscode") || bundleId.lowercased().contains("vscode"))
    }

    private static let terminalNames: [(bundlePrefix: String, program: String, name: String)] = [
        ("com.apple.terminal", "apple_terminal", "Terminal"),
        ("com.googlecode.iterm2", "iterm.app", "iTerm"),
        ("com.mitchellh.ghostty", "ghostty", "Ghostty"),
        ("dev.warp.", "warpterminal", "Warp"),
        ("net.kovidgoyal.kitty", "kitty", "kitty"),
        ("org.alacritty", "alacritty", "Alacritty"),
        ("com.github.wez.wezterm", "wezterm", "WezTerm"),
        ("co.zeit.hyper", "hyper", "Hyper"),
    ]

    /// Where the user is, in the words of the notes "Handled in …" and "Still waiting in …". VS Code, Cursor and Codex read as they always did.
    static func hostName(pillId: String, termProgram: String, bundleId: String) -> String {
        switch pillId {
        case "agent_cursor": return "Cursor"
        case "agent_codex": return "Codex"
        case "integration_claude":
            if isVSCode(termProgram: termProgram, bundleId: bundleId) { return "VS Code" }
            let b = bundleId.lowercased(), p = termProgram.lowercased()
            return terminalNames.first { b.hasPrefix($0.bundlePrefix) || p == $0.program }?.name ?? "the terminal"
        default: return "the terminal"
        }
    }

    static func note(host: String, stillWaiting: Bool) -> String { stillWaiting ? "Still waiting in \(host)." : "Handled in \(host)." }

    /// The app to bring forward for a Claude Code session that is not in VS Code: the app that started it (the relay's `__CFBundleIdentifier`), else the terminal the
    /// `TERM_PROGRAM` names. nil for VS Code and Cursor, whose routes stay as they were, and when nothing is known.
    static func terminalBundleId(termProgram: String, bundleId: String) -> String? {
        if isVSCode(termProgram: termProgram, bundleId: bundleId) || bundleId.lowercased() == cursorBundleId { return nil }
        if !bundleId.isEmpty { return bundleId }
        let programs = ["apple_terminal": "com.apple.Terminal", "iterm.app": "com.googlecode.iterm2", "ghostty": "com.mitchellh.ghostty",
                        "warpterminal": "dev.warp.Warp-Stable", "wezterm": "com.github.wez.wezterm", "hyper": "co.zeit.hyper"]
        return programs[termProgram.lowercased()]
    }
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `bash scripts/test-hook-origin.sh`
Expected: PASS: 36 `✓` lines under five headings (the pill, "Cursor, Codex and tagged agents keep their pills", the editor test, where the user is, the app to bring forward) and `All tests passed.`

- [ ] **Step 5: Bite: Cursor must stop being Cursor**

```bash
BK="$(mktemp -d "${TMPDIR:-/tmp}/nm-bite.XXXXXX")" && cp NotchBuddy/Sources/App/HookOrigin.swift "$BK/"
sed -i '' 's/if bundleId.lowercased() == cursorBundleId { return .cursor }/_ = 0/' NotchBuddy/Sources/App/HookOrigin.swift
bash scripts/test-hook-origin.sh 2>&1 | grep -E "✗|failed"
cp "$BK/HookOrigin.swift" NotchBuddy/Sources/App/HookOrigin.swift
bash scripts/test-hook-origin.sh 2>&1 | tail -1
```

Expected: `✗ Cursor, told apart by its bundle ID in any letter case` and `1 test(s) failed.`, then after the copy back `All tests passed.`

- [ ] **Step 6: Put the file in the project and the test in CI**

```bash
cd NotchBuddy && xcodegen && cd .. && git diff --stat NotchBuddy/NotchBuddy.xcodeproj | tail -1
```

Expected: `1 file changed, 6 insertions(+)` (the one new app file). Then:

**Edit `.github/workflows/build.yml`**

Find (it occurs once):

```yaml
      - name: Island right wing wiring (source pins of the panel, AppState and the view)
        run: bash scripts/test-island-wing-wiring.sh
```

Replace with:

```yaml
      - name: Island right wing wiring (source pins of the panel, AppState and the view)
        run: bash scripts/test-island-wing-wiring.sh

      - name: Hook routing (VS Code and every terminal reach the Claude Code pill)
        run: bash scripts/test-hook-origin.sh
```


- [ ] **Step 7: Check the file is in the Debug build**

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:"`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree's folder, and mac/all-terminals
MSG="$(mktemp "${TMPDIR:-/tmp}/nm-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(hooks): the rules that say which pill a hook event belongs to

A pure Foundation file: Claude Code from VS Code or from any terminal is the Claude Code
pill, Cursor, Codex and tagged agents keep theirs, and the app the user is in has a name
for the notes and a bundle ID for the pill tap. Not called yet.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/HookOrigin.swift \
  tests/HookOriginTests.swift \
  scripts/test-hook-origin.sh \
  NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj \
  .github/workflows/build.yml
git status --short
git commit -F "$MSG"
```

Expected: `git status --short` lists only the files above (all staged). Never push.

---

### Task 2: The three entry points, the notes and the pill's tap, with the wiring pins

**Files:**
- Create: `tests/HookOriginWiringTests.swift`, `scripts/test-hook-origin-wiring.sh`
- Edit: `NotchBuddy/Sources/App/HookServer.swift`, `NotchBuddy/Sources/App/IslandTypes.swift`, `NotchBuddy/Sources/App/AppState.swift`, `NotchBuddy/Sources/App/IslandViewContent.swift`, `.github/workflows/build.yml`

**Interfaces:**
- Consumes: Task 1's `HookOrigin` (exact signatures above).
- Produces: `ApprovalInfo.host: String` (default `"VS Code"`, so `scripts/render-approval-card.swift` still compiles unchanged); `AppState.hostBundleIds: [String: String]` and `AppState.noteHost(_ pillId: String, _ bundleId: String?)`.

- [ ] **Step 1: Write the wiring test first**

**Create `tests/HookOriginWiringTests.swift`**

```swift
import Foundation

// Source pins for the hook routing, where no test program can compile HookServer (it needs the whole app). Each says where HookOrigin must be called and that the old
// editor-only guards are gone, so a missed call site fails here and not on the owner's screen. Run from the repository root through scripts/test-hook-origin-wiring.sh.

@main
enum HookOriginWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
    /// The offset of the first `needle`, or -1.
    static func at(_ needle: String, in text: String) -> Int { text.range(of: needle)?.lowerBound.utf16Offset(in: text) ?? -1 }

    @MainActor static func main() {
        let hooks = source("HookServer.swift"), rules = source("HookOrigin.swift"), types = source("IslandTypes.swift"), app = source("AppState.swift"), view = source("IslandViewContent.swift")
        CT.section("the sources were read")
        CT.checkTrue("the five files are there", hooks.contains("final class HookServer") && rules.contains("enum HookOrigin") && types.contains("struct ApprovalInfo") && app.contains("final class AppState") && view.contains("private func openAgentTarget"))

        CT.section("the rules are pure")
        CT.checkTrue("HookOrigin.swift imports only Foundation and starts nothing", rules.contains("import Foundation") && !rules.contains("import AppKit") && !rules.contains("import SwiftUI") && !rules.contains("Timer") && !rules.contains("DispatchQueue") && !rules.contains("NSWorkspace"))

        CT.section("the three entry points route through HookOrigin, and the editor-only guards are gone")
        CT.check("an event, a permission request and a question each ask the rule", count("HookOrigin.route(", in: hooks), 3)
        CT.check("no copy of the editor test is left", count("isVSCodeEditor", in: hooks) + count("isCursorEditor", in: hooks) + count("isCodexEvent", in: hooks), 0)
        CT.check("nothing is ignored for its terminal any more", count("nbLog(\"Ignored", in: hooks), 0)
        CT.check("no request is answered \"ask\" for lack of an editor", count("guard isCodexRequest ||", in: hooks), 0)
        CT.check("a tagged agent's permission request and question are still answered ask at once, and its events still get its own pill", count("if case .external = route {", in: hooks), 3)
        CT.checkTrue("a chat's own run is filtered before the routing, as it was", at("ClaudeHookRouting.route(payload: payload, live: ClaudeService.shared.liveClaudeSessions) { return }", in: hooks) > 0 && at("ClaudeHookRouting.route(payload: payload, live: ClaudeService.shared.liveClaudeSessions) { return }", in: hooks) < at("HookOrigin.route(", in: hooks))
        CT.checkTrue("Codex is the GitHub build's only", count("let codexEnabled = true", in: hooks) == 3 && count("let codexEnabled = false", in: hooks) == 3 && count("#if !APPSTORE\n        let codexEnabled = true", in: hooks) == 3)

        CT.section("two sessions on the one pill: an approval is still closed only by its own session's events")
        CT.check("the resolving events still compare the session", count("sessionId == pending.sessionId", in: hooks), 2)

        CT.section("the notes name the app the user is in; VS Code, Cursor and Codex read as they did")
        CT.check("the three notes come from the rule", count("HookOrigin.note(", in: hooks), 3)
        CT.check("no note is spelled in the server", count("Handled in ", in: hooks) + count("Still waiting in ", in: hooks), 0)
        CT.checkTrue("the approval keeps where it came from, and the notes use it", hooks.contains("subagentId: askedBy, host: host)") && hooks.contains("HookOrigin.note(host: pending.host, stillWaiting: false)") && types.contains("var host: String = \"VS Code\""))

        CT.section("a terminal session's pill brings its terminal forward")
        CT.checkTrue("the server notes the host of Claude Code's events only", count("state.noteHost(", in: hooks) == 1 && hooks.contains("if route == .claude { state.noteHost(agentId, HookOrigin.terminalBundleId("))
        CT.checkTrue("AppState holds it unpublished", app.contains("var hostBundleIds: [String: String] = [:]") && !app.contains("@Published var hostBundleIds"))
        CT.checkTrue("the pill's tap uses it first, in the GitHub build only, and VS Code's route follows unchanged", view.contains("case \"integration_claude\":\n            #if !APPSTORE\n") && view.contains("AppState.shared.hostBundleIds[task.id]") && at("AppState.shared.hostBundleIds[task.id]", in: view) < at("let vscodeBundleId = \"com.microsoft.VSCode\"", in: view))

        CT.finish()
    }
}
```

**Create `scripts/test-hook-origin-wiring.sh`**

```bash
#!/usr/bin/env bash
# Hook routing, wiring: where HookServer, ApprovalInfo, AppState and the Claude Code pill's tap call the pure rules (HookOrigin), pinned as source text.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-hook-origin-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/HookOriginWiringTests.swift \
    -o "$TEST_DIR/hook-origin-wiring-tests"
"$TEST_DIR/hook-origin-wiring-tests"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash -n scripts/test-hook-origin-wiring.sh && bash scripts/test-hook-origin-wiring.sh 2>&1 | grep -E "✗|failed"`
Expected: FAIL: 13 of the 16 checks print `✗` (the three that already hold are "the five files are there", the pure-file check and the session compare) and the last line is `13 test(s) failed.`

- [ ] **Step 3: Route the three entry points through the rules**

Eight edits to `NotchBuddy/Sources/App/HookServer.swift`, in this order. Each find text occurs once. What they do: (1) `processEvent` asks `HookOrigin.route` instead of the editor test, so a terminal event is no longer "Ignored", and notes the terminal's app; (2) the pending approval's closing note comes from the rule; (3) `processPermissionRequest` asks the rule, still answers a tagged agent `ask` at once, and no longer answers `ask` for lack of an editor; (4) the approval keeps where it came from; (5) and (6) its two notes; (7) the `--ask` question path asks the rule, answering a tagged agent `ask`.

**Edit `NotchBuddy/Sources/App/HookServer.swift`**

Find (it occurs once):

```swift
        let termProgram = payload["term_program"] as? String ?? ""
        let bundleId    = payload["bundle_id"]    as? String ?? ""

        // Cursor identified solely by its stable Electron bundle ID.
        // ToDesktop builds other apps too — do not match on "todesktop" alone.
        let isCursorEditor = bundleId.lowercased() == "com.todesktop.230313mzl4w4u92"
        let isVSCodeEditor = !isCursorEditor && (
            termProgram.lowercased().contains("vscode") ||
            bundleId.lowercased().contains("vscode"))

        // Routing:
        // • "codex" → agent_codex (GitHub build only: workspace pill, approvals in the notch)
        // • other valid nm_agent → external pill (fire-and-forget, no approval card)
        // • Cursor bundle ID → agent_cursor
        // • VS Code → integration_claude
        #if !APPSTORE
        let isCodexEvent = rawAgent == "codex"
        #else
        let isCodexEvent = false
        #endif
        let agentId: String
        let isExternalAgent: Bool
        if isCodexEvent {
            agentId = "agent_codex"
            isExternalAgent = false
        } else if let agent = validAgent {
            agentId = "agent_\(agent)"
            isExternalAgent = true
        } else if isCursorEditor {
            agentId = "agent_cursor"
            isExternalAgent = false
        } else if isVSCodeEditor {
            agentId = "integration_claude"
            isExternalAgent = false
        } else {
            nbLog("Ignored \(name) from \(termProgram.isEmpty ? bundleId : termProgram) (\(projectName))")
            return
        }

        state.touchPill(agentId)   // the pill's last event: Two cats mode's busiest-other rule reads it
        // A subagent's start, tools and stop, and the parent's own stop, change this pill's kittens (CatKittenHooks). The parent's cat behaves as it always has.
        if let kitten = CatKittenHooks.event(name: name, payload: payload, now: CACurrentMediaTime() * 1000) { state.kittenEvent(agentId, kitten) }
        let focused = state.focusId == agentId
```

Replace with:

```swift
        let termProgram = payload["term_program"] as? String ?? ""
        let bundleId    = payload["bundle_id"]    as? String ?? ""

        // Routing (HookOrigin):
        // • "codex" → agent_codex (GitHub build only: workspace pill, approvals in the notch)
        // • other valid nm_agent → external pill (fire-and-forget, no approval card)
        // • Cursor bundle ID (its stable Electron one; ToDesktop builds other apps too) → agent_cursor
        // • anything else is Claude Code, from VS Code or from any terminal → integration_claude
        #if !APPSTORE
        let codexEnabled = true
        #else
        let codexEnabled = false
        #endif
        let route = HookOrigin.route(rawAgent: rawAgent, validAgent: validAgent, codexEnabled: codexEnabled, bundleId: bundleId)
        let agentId = HookOrigin.pillId(route)
        let isExternalAgent: Bool
        if case .external = route { isExternalAgent = true } else { isExternalAgent = false }

        state.touchPill(agentId)   // the pill's last event: Two cats mode's busiest-other rule reads it
        // Which app a terminal session runs in, so the pill's tap brings that app forward (nil for VS Code, whose route is its own).
        if route == .claude { state.noteHost(agentId, HookOrigin.terminalBundleId(termProgram: termProgram, bundleId: bundleId)) }
        // A subagent's start, tools and stop, and the parent's own stop, change this pill's kittens (CatKittenHooks). The parent's cat behaves as it always has.
        if let kitten = CatKittenHooks.event(name: name, payload: payload, now: CACurrentMediaTime() * 1000) { state.kittenEvent(agentId, kitten) }
        let focused = state.focusId == agentId
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**

Find (it occurs once):

```swift
        // While a permission request is pending, dismiss when the resolving event arrives,
        // then continue normal processing. Only skip normal processing when unresolved.
        if let pending = state.pendingApproval, agentId == pending.pillId {
            let handledNote: String
            switch pending.pillId {
            case "agent_cursor": handledNote = "Handled in Cursor."
            case "agent_codex":  handledNote = "Handled in Codex."
            default:             handledNote = "Handled in VS Code."
            }
            var resolved = false
            switch name {
            case "PostToolUse", "PostToolUseFailure":
```

Replace with:

```swift
        // While a permission request is pending, dismiss when the resolving event arrives,
        // then continue normal processing. Only skip normal processing when unresolved.
        if let pending = state.pendingApproval, agentId == pending.pillId {
            let handledNote = HookOrigin.note(host: pending.host, stillWaiting: false)
            var resolved = false
            switch name {
            case "PostToolUse", "PostToolUseFailure":
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**

Find (it occurs once):

```swift
        let rawAgent = payload["nm_agent"] as? String ?? ""
        let termProgram = payload["term_program"] as? String ?? ""
        let bundleId    = payload["bundle_id"]    as? String ?? ""
        let isCursorEditor = bundleId.lowercased() == "com.todesktop.230313mzl4w4u92"
        let isVSCodeEditor = !isCursorEditor && (
            termProgram.lowercased().contains("vscode") ||
            bundleId.lowercased().contains("vscode"))

        // Codex gets the same approval card as Claude Code / Cursor (GitHub build only).
        // Other external agents (any other nm_agent) answer immediately with "ask"
        // so the agent re-asks in its own terminal — they do not get a notch card.
        #if !APPSTORE
        let isCodexRequest = rawAgent == "codex"
        #else
        let isCodexRequest = false
        #endif
        if !isCodexRequest && Self.validateAgent(rawAgent) != nil {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
```

Replace with:

```swift
        let rawAgent = payload["nm_agent"] as? String ?? ""
        let termProgram = payload["term_program"] as? String ?? ""
        let bundleId    = payload["bundle_id"]    as? String ?? ""

        // Codex gets the same approval card as Claude Code / Cursor (GitHub build only).
        // Other external agents (any other nm_agent) answer immediately with "ask"
        // so the agent re-asks in its own terminal — they do not get a notch card.
        // Claude Code gets its card from VS Code and from any terminal (HookOrigin).
        #if !APPSTORE
        let codexEnabled = true
        #else
        let codexEnabled = false
        #endif
        let route = HookOrigin.route(rawAgent: rawAgent, validAgent: Self.validateAgent(rawAgent), codexEnabled: codexEnabled, bundleId: bundleId)
        if case .external = route {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**

Find (it occurs once):

```swift
        }

        // Determine which workspace pill owns the request.
        let pillId: String
        if isCodexRequest {
            pillId = "agent_codex"
        } else if isCursorEditor {
            pillId = "agent_cursor"
        } else {
            pillId = "integration_claude"
        }
        guard isCodexRequest || isCursorEditor || isVSCodeEditor else {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }

        state.touchPill(pillId)
        let tool = payload["tool_name"] as? String ?? "Tool"
```

Replace with:

```swift
        }

        // Determine which workspace pill owns the request.
        let pillId = HookOrigin.pillId(route)
        let host = HookOrigin.hostName(pillId: pillId, termProgram: termProgram, bundleId: bundleId)

        state.touchPill(pillId)
        let tool = payload["tool_name"] as? String ?? "Tool"
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**

Find (it occurs once):

```swift
        let askedBy = CatKittenHooks.subagentId(payload)
        if let kitten = CatKittenHooks.permission(payload: payload, now: CACurrentMediaTime() * 1000) { state.kittenEvent(pillId, kitten) }
        state.pendingApproval = ApprovalInfo(sessionId: sessionId, tool: tool,
                                              command: command, inputKey: inputKey, pillId: pillId, subagentId: askedBy)
        state.isPinned = true
        SoundEngine.shared.play("approval")
```

Replace with:

```swift
        let askedBy = CatKittenHooks.subagentId(payload)
        if let kitten = CatKittenHooks.permission(payload: payload, now: CACurrentMediaTime() * 1000) { state.kittenEvent(pillId, kitten) }
        state.pendingApproval = ApprovalInfo(sessionId: sessionId, tool: tool,
                                              command: command, inputKey: inputKey, pillId: pillId, subagentId: askedBy, host: host)
        state.isPinned = true
        SoundEngine.shared.play("approval")
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**

Find (it occurs once):

```swift

        // Monitor fd: if the editor closes the connection (handled externally), dismiss the card.
        // The cancel handler closes the fd — never close it anywhere else.
        let capturedPillId = pillId
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, self.pendingApprovalFD == fd else { return }
            let note: String
            switch capturedPillId {
            case "agent_cursor": note = "Handled in Cursor."
            case "agent_codex":  note = "Handled in Codex."
            default:             note = "Handled in VS Code."
            }
            self.dismissApprovalCard(note: note)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
```

Replace with:

```swift

        // Monitor fd: if the editor closes the connection (handled externally), dismiss the card.
        // The cancel handler closes the fd — never close it anywhere else.
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, self.pendingApprovalFD == fd else { return }
            self.dismissApprovalCard(note: HookOrigin.note(host: host, stillWaiting: false))
        }
        source.setCancelHandler { close(fd) }
        source.resume()
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**

Find (it occurs once):

```swift
        let captured = fd
        DispatchQueue.main.asyncAfter(deadline: .now() + 115) { [weak self] in
            guard let self, self.pendingApprovalFD == captured else { return }
            let note: String
            switch capturedPillId {
            case "agent_cursor": note = "Still waiting in Cursor."
            case "agent_codex":  note = "Still waiting in Codex."
            default:             note = "Still waiting in VS Code."
            }
            self.dismissApprovalCard(note: note)
        }
    }
```

Replace with:

```swift
        let captured = fd
        DispatchQueue.main.asyncAfter(deadline: .now() + 115) { [weak self] in
            guard let self, self.pendingApprovalFD == captured else { return }
            self.dismissApprovalCard(note: HookOrigin.note(host: host, stillWaiting: true))
        }
    }
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`**

Find (it occurs once):

```swift
        let projectName = aliasProjectName(rawName.isEmpty ? "Session" : rawName)

        let rawAgent    = payload["nm_agent"] as? String ?? ""
        let termProgram = payload["term_program"]  as? String ?? ""
        let bundleId    = payload["bundle_id"]     as? String ?? ""
        let isCursorEditor = bundleId.lowercased() == "com.todesktop.230313mzl4w4u92"
        let isVSCodeEditor = !isCursorEditor && (
            termProgram.lowercased().contains("vscode") ||
            bundleId.lowercased().contains("vscode"))
        #if !APPSTORE
        let isCodexRequest = rawAgent == "codex"
        #else
        let isCodexRequest = false
        #endif
        let pillId: String
        if isCodexRequest {
            pillId = "agent_codex"
        } else if isCursorEditor {
            pillId = "agent_cursor"
        } else {
            pillId = "integration_claude"
        }
        guard isCodexRequest || isCursorEditor || isVSCodeEditor else {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }

        state.touchPill(pillId)
        // Displace any previous question waiting for an answer.
```

Replace with:

```swift
        let projectName = aliasProjectName(rawName.isEmpty ? "Session" : rawName)

        let rawAgent    = payload["nm_agent"] as? String ?? ""
        let bundleId    = payload["bundle_id"]     as? String ?? ""
        #if !APPSTORE
        let codexEnabled = true
        #else
        let codexEnabled = false
        #endif
        // The question goes to the same pill as the session's other events (HookOrigin): VS Code or any terminal for Claude Code. A tagged agent that is not Codex has
        // no question card (only Claude Code and Codex install the `--ask` hook), so a stray one answers "ask" at once, as a permission request from it does.
        let route = HookOrigin.route(rawAgent: rawAgent, validAgent: Self.validateAgent(rawAgent), codexEnabled: codexEnabled, bundleId: bundleId)
        if case .external = route {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }
        let pillId = HookOrigin.pillId(route)

        state.touchPill(pillId)
        // Displace any previous question waiting for an answer.
```

- [ ] **Step 4: The approval's `host`, and where a terminal session runs**

**Edit `NotchBuddy/Sources/App/IslandTypes.swift`**

Find (it occurs once):

```swift
    /// The subagent that asked (the request's `agent_id`), when one did: its kitten waits on this approval.
    var subagentId: String? = nil
}
```

Replace with:

```swift
    /// The subagent that asked (the request's `agent_id`), when one did: its kitten waits on this approval.
    var subagentId: String? = nil
    /// Where the user is, for the notes "Handled in …" and "Still waiting in …" (`HookOrigin.hostName`).
    var host: String = "VS Code"
}
```

**Edit `NotchBuddy/Sources/App/AppState.swift`**

Find (it occurs once):

```swift
        pillLastEvent[id] = ms
    }
    var isPresent: Bool = true
```

Replace with:

```swift
        pillLastEvent[id] = ms
    }
    /// The app a Claude Code session runs in when it is not VS Code (the relay's `__CFBundleIdentifier`, else the terminal `TERM_PROGRAM` names), by pill; the Claude Code
    /// pill's tap brings it forward. Not published: the events that set it change the tasks too.
    var hostBundleIds: [String: String] = [:]
    func noteHost(_ pillId: String, _ bundleId: String?) {
        if let bundleId { hostBundleIds[pillId] = bundleId } else { hostBundleIds.removeValue(forKey: pillId) }
    }
    var isPresent: Bool = true
```

- [ ] **Step 5: The Claude Code pill's tap brings the session's terminal forward**

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**

Find (it occurs once):

```swift
        switch task.id {
        case "integration_claude":
            let vscodeBundleId = "com.microsoft.VSCode"
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == vscodeBundleId }) {
```

Replace with:

```swift
        switch task.id {
        case "integration_claude":
            #if !APPSTORE
            // A Claude Code session in a terminal: that app comes forward (HookOrigin). VS Code's route, below, is as it was.
            if let id = AppState.shared.hostBundleIds[task.id],
               let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }) {
                app.activate(options: .activateIgnoringOtherApps)
                return
            }
            #endif
            let vscodeBundleId = "com.microsoft.VSCode"
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == vscodeBundleId }) {
```

- [ ] **Step 6: Run the wiring test and the rules, and watch them pass**

Run: `bash scripts/test-hook-origin-wiring.sh && bash scripts/test-hook-origin.sh | tail -1`
Expected: PASS: 16 `✓` lines under six headings and `All tests passed.`, then `All tests passed.`

- [ ] **Step 7: Bite: a copy of the old guard must fail the pin, and so must a host noted for every pill**

```bash
BK="$(mktemp -d "${TMPDIR:-/tmp}/nm-bite.XXXXXX")" && cp NotchBuddy/Sources/App/HookServer.swift "$BK/"
echo '// isVSCodeEditor' >> NotchBuddy/Sources/App/HookServer.swift
bash scripts/test-hook-origin-wiring.sh 2>&1 | grep -E "✗|failed"
cp "$BK/HookServer.swift" NotchBuddy/Sources/App/HookServer.swift
sed -i '' 's/if route == .claude { state.noteHost/if true { state.noteHost/' NotchBuddy/Sources/App/HookServer.swift
bash scripts/test-hook-origin-wiring.sh 2>&1 | grep -E "✗|failed"
cp "$BK/HookServer.swift" NotchBuddy/Sources/App/HookServer.swift
bash scripts/test-hook-origin-wiring.sh | tail -1
```

Expected: `✗ no copy of the editor test is left` and `1 test(s) failed.`; then `✗ the server notes the host of Claude Code's events only` and `1 test(s) failed.`; then `All tests passed.`

- [ ] **Step 8: The tests that guard what already shipped, then both builds**

```bash
for t in test-ask-question test-claude-code test-cat-wiring test-cat-kitten-hooks test-island-wing-wiring test-cat-desktop-wiring test-cat-cast test-session-steps; do echo "== $t"; bash scripts/$t.sh 2>&1 | tail -1; done
bash scripts/check-no-leftovers.sh 2>&1 | tail -1
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD|error:|warning: .*(HookServer|HookOrigin)"
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "BUILD|error:"
```

Expected: eight `All tests passed.` lines, a `✓` leftovers line, then `** BUILD SUCCEEDED **` for the Debug build (and no warning line) and `** BUILD SUCCEEDED **` for the App Store build. If a build warns that a variable in `HookServer.swift` is never used, remove that variable (the dry run needed none removed once the edits above were applied).

- [ ] **Step 9: Put the wiring test in CI**

**Edit `.github/workflows/build.yml`**

Find (it occurs once):

```yaml
      - name: Island right wing wiring (source pins of the panel, AppState and the view)
        run: bash scripts/test-island-wing-wiring.sh

      - name: Hook routing (VS Code and every terminal reach the Claude Code pill)
        run: bash scripts/test-hook-origin.sh
```

Replace with:

```yaml
      - name: Island right wing wiring (source pins of the panel, AppState and the view)
        run: bash scripts/test-island-wing-wiring.sh

      - name: Hook routing (VS Code and every terminal reach the Claude Code pill)
        run: bash scripts/test-hook-origin.sh

      - name: Hook routing wiring (source pins of HookServer, ApprovalInfo, AppState and the pill's tap)
        run: bash scripts/test-hook-origin-wiring.sh
```

- [ ] **Step 10: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree's folder, and mac/all-terminals
MSG="$(mktemp "${TMPDIR:-/tmp}/nm-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(hooks): Claude Code from every terminal reaches the Mac island

HookServer asked "is it VS Code or Cursor?" in three places and ignored, or answered ask
at once, for any other terminal. It now asks HookOrigin: everything that is not Cursor,
Codex or a tagged agent is Claude Code. The pill keeps its ID and its label; the notes
name the app the user is in, and the pill tap brings a terminal session's terminal forward
(GitHub build). The chat filter still comes first. Source pins in a wiring test.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/HookServer.swift \
  NotchBuddy/Sources/App/IslandTypes.swift \
  NotchBuddy/Sources/App/AppState.swift \
  NotchBuddy/Sources/App/IslandViewContent.swift \
  tests/HookOriginWiringTests.swift \
  scripts/test-hook-origin-wiring.sh \
  .github/workflows/build.yml
git status --short
git commit -F "$MSG"
```

Expected: `git status --short` lists only the files above (all staged). Never push.

---

### Task 3: The fake terminal session, and the docs

**Files:**
- Create: `scripts/fake-terminal-events.py`, `scripts/test-fake-terminal-events.sh`
- Edit: `docs/QA-MAC.md`, `docs/INTEGRATIONS.md`, `CLAUDE.md`, `.github/workflows/build.yml`

**Interfaces:**
- Produces: `python3 scripts/fake-terminal-events.py [--term-program P] [--bundle-id B] [--approval] [--print] [--sock PATH] [--speed N]`, the owner's command in Task 4. It reuses `tests/kitten_socket_server.py` (a stand-in socket, existing) for its test.

- [ ] **Step 1: Write the script's test first**

**Create `scripts/test-fake-terminal-events.sh`**

```bash
#!/usr/bin/env bash
# The owner's fake terminal session (scripts/fake-terminal-events.py) is sent to a socket of this test's own, never the app's, and what that socket received is checked:
# the events in order, every one carrying the terminal's TERM_PROGRAM and bundle ID, the permission request only with --approval. Nothing here launches or touches NotchMeow.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-fake-terminal.XXXXXX")"
SOCK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nmt.XXXXXX")"
[ "${#SOCK_DIR}" -le 80 ] || { rm -rf "$SOCK_DIR"; SOCK_DIR="$(mktemp -d /tmp/nmt.XXXXXX)"; }   # a socket path holds 103 bytes
SERVER=""
trap '[ -z "$SERVER" ] || { kill "$SERVER" 2>/dev/null; wait "$SERVER" 2>/dev/null; } || true; rm -rf "$TEST_DIR" "$SOCK_DIR"' EXIT

python3 tests/kitten_socket_server.py "$SOCK_DIR/s" "$SOCK_DIR/received.jsonl" &
SERVER=$!
for _ in $(seq 1 50); do [ -S "$SOCK_DIR/s" ] && break; sleep 0.1; done
[ -S "$SOCK_DIR/s" ] || { echo "the test socket did not come up"; exit 1; }

fail=0
check() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; else echo "  ✗ $1"; echo "    got:      $2"; echo "    expected: $3"; fail=1; fi; }
names() { python3 -I -c 'import json,sys; print(" ".join(json.loads(l)["hook_event_name"] for l in open(sys.argv[1])))' "$1"; }
field() { python3 -I -c 'import json,sys; print(" ".join(sorted({json.loads(l)[sys.argv[2]] for l in open(sys.argv[1])})))' "$1" "$2"; }

echo "the default session: Apple Terminal"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-terminal-events.py --sock "$SOCK_DIR/s" --speed 100000 > /dev/null
check "the events, in order" "$(names "$SOCK_DIR/received.jsonl")" "SessionStart UserPromptSubmit PreToolUse PostToolUse Stop"
check "every one says Apple_Terminal" "$(field "$SOCK_DIR/received.jsonl" term_program)" "Apple_Terminal"
check "and com.apple.Terminal" "$(field "$SOCK_DIR/received.jsonl" bundle_id)" "com.apple.Terminal"
check "and is no tagged agent" "$(python3 -I -c 'import json,sys; print(sum("nm_agent" in json.loads(l) for l in open(sys.argv[1])))' "$SOCK_DIR/received.jsonl")" "0"

echo "iTerm, with an approval"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-terminal-events.py --sock "$SOCK_DIR/s" --speed 100000 --term-program iTerm.app --bundle-id com.googlecode.iterm2 --approval > /dev/null
check "the permission request is there, before the stop" "$(names "$SOCK_DIR/received.jsonl")" "SessionStart UserPromptSubmit PreToolUse PostToolUse PermissionRequest Stop"
check "every one says iTerm.app" "$(field "$SOCK_DIR/received.jsonl" term_program)" "iTerm.app"

echo "--print sends nothing"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-terminal-events.py --print --sock "$SOCK_DIR/nothing" > /dev/null
check "no connection was made" "$(wc -l < "$SOCK_DIR/received.jsonl" | tr -d ' ')" "0"

echo "an unreachable socket is an error, not a hang"
set +e
python3 scripts/fake-terminal-events.py --sock "$SOCK_DIR/nothing" --speed 100000 > /dev/null 2>&1
check "exit code 1" "$?" "1"
set -e

[ "$fail" = 0 ] && echo && echo "All tests passed." || { echo; echo "tests failed."; exit 1; }
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash -n scripts/test-fake-terminal-events.sh && bash scripts/test-fake-terminal-events.sh; echo "exit $?"`
Expected: FAIL: Python says `can't open file '…/scripts/fake-terminal-events.py'` right after `the default session: Apple Terminal`, and `exit` is not 0.

- [ ] **Step 3: Write the script**

**Create `scripts/fake-terminal-events.py`**

```python
#!/usr/bin/env python3
"""Sends the hook events of a Claude Code session in a terminal through NotchMeow's socket, the way the nm-hook relay does, so a running Debug build shows it.

  python3 scripts/fake-terminal-events.py                              Apple Terminal: a session, a prompt, one step, a stop
  python3 scripts/fake-terminal-events.py --term-program iTerm.app --bundle-id com.googlecode.iterm2
  python3 scripts/fake-terminal-events.py --approval                   also a permission request, held open until you answer the card in the island
  python3 scripts/fake-terminal-events.py --print                      print the payloads instead of sending them
  python3 scripts/fake-terminal-events.py --sock /path/nm.sock         another socket (the App Store build's is ~/Library/Containers/<id>/Data/nm.sock)

This is for the owner's check on a real build, and it never runs `claude`: the tests send it to a socket of their own (scripts/test-fake-terminal-events.sh) and never to the app.
Each event is one connection, newline-delimited JSON, as the relay sends it.
"""
import argparse, json, os, socket, sys, time

DEFAULT_SOCK = os.path.expanduser("~/Library/Application Support/NotchMeow/nm.sock")


def events(term_program, bundle_id, approval):
    common = {"session_id": "fake-term-1", "cwd": "/tmp/notchmeow-fake-terminal", "term_program": term_program, "bundle_id": bundle_id}
    steps = [
        ("the session starts: the Claude Code pill appears", {"hook_event_name": "SessionStart", "source": "startup"}),
        ("a prompt: the cat thinks", {"hook_event_name": "UserPromptSubmit", "prompt": "NM-FAKE: say hello"}),
        ("a step: the cat works, the step row reads Runs · echo NM-FAKE step", {"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": "echo NM-FAKE step"}}),
        ("the step is done", {"hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_input": {"command": "echo NM-FAKE step"}}),
    ]
    if approval:
        steps.append(("a permission request: the card opens and the app waits for your click", {"hook_event_name": "PermissionRequest", "tool_name": "Bash", "tool_input": {"command": "echo NM-FAKE-APPROVAL"}}))
    steps.append(("the turn ends", {"hook_event_name": "Stop", "last_assistant_message": "NM-FAKE done."}))
    return [(say, {**common, **event}) for say, event in steps]


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
    ap.add_argument("--term-program", default="Apple_Terminal")
    ap.add_argument("--bundle-id", default="com.apple.Terminal")
    ap.add_argument("--approval", action="store_true")
    ap.add_argument("--sock", default=DEFAULT_SOCK)
    ap.add_argument("--print", dest="dry", action="store_true", help="print the payloads, send nothing")
    ap.add_argument("--speed", type=float, default=1.0, help="2 waits half as long between events")
    ap.add_argument("--permission-timeout", type=float, default=120.0)
    a = ap.parse_args()
    for say, payload in events(a.term_program, a.bundle_id, a.approval):
        print("-", say, flush=True)
        if a.dry:
            print("  " + json.dumps(payload, sort_keys=True))
            continue
        try:
            reply = send(a.sock, payload, a.permission_timeout)
        except OSError as e:
            print(f"  could not reach {a.sock}: {e}", file=sys.stderr)
            return 1
        print("  ->", reply or "(closed)", flush=True)
        time.sleep(1.5 / a.speed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run it and watch it pass**

Run: `python3 -I -c "import ast;ast.parse(open('scripts/fake-terminal-events.py').read())" && bash scripts/test-fake-terminal-events.sh`
Expected: PASS: 8 `✓` lines under four headings (the default session, iTerm with an approval, `--print`, an unreachable socket) and `All tests passed.`

- [ ] **Step 5: Say what is true in the docs**

The Mac QA brief gets three payloads and a terminal half of step 4; `docs/INTEGRATIONS.md` (in French, like the rest) gets one bullet saying which sessions appear; `CLAUDE.md` gets the map bullet.

**Edit `docs/QA-MAC.md`**

Find (it occurs once):

````bash
{"hook_event_name":"Stop","session_id":"qa-2","cwd":"/tmp/notchmeow-qa-agent","nm_agent":"qa-agent","last_assistant_message":"NM-QA agent done."}
JSON
ls "$QA/payloads"
```
````

Replace with:

````bash
{"hook_event_name":"Stop","session_id":"qa-2","cwd":"/tmp/notchmeow-qa-agent","nm_agent":"qa-agent","last_assistant_message":"NM-QA agent done."}
JSON
cat > "$QA/payloads/terminal-start.json" <<'JSON'
{"hook_event_name":"SessionStart","session_id":"qa-3","cwd":"/tmp/notchmeow-qa-terminal","term_program":"Apple_Terminal","bundle_id":"com.apple.Terminal","source":"startup"}
JSON
cat > "$QA/payloads/terminal-work.json" <<'JSON'
{"hook_event_name":"PreToolUse","session_id":"qa-3","cwd":"/tmp/notchmeow-qa-terminal","term_program":"Apple_Terminal","bundle_id":"com.apple.Terminal","tool_name":"Bash","tool_input":{"command":"echo NM-QA terminal"}}
JSON
cat > "$QA/payloads/terminal-stop.json" <<'JSON'
{"hook_event_name":"Stop","session_id":"qa-3","cwd":"/tmp/notchmeow-qa-terminal","term_program":"Apple_Terminal","bundle_id":"com.apple.Terminal","last_assistant_message":"NM-QA terminal done."}
JSON
ls "$QA/payloads"
```
````

**Edit `docs/QA-MAC.md`**

Find (it occurs once):

```bash
Check: the compact island shows the cat at work, not idle (with several agents the others sit in the grid on its right). Click once on the island's black body, away from any cat or button (a hover never opens the compact island: it only keeps it from hiding), wait 2 s for the overview, then `shot 04-session-open`: the session is listed under the project name `notchmeow-qa`. Move the pointer away. Check: the step row reads `Runs · echo NM-QA step`; copy what you see into the report.

## Step 5: an approval, which you answer
```

Replace with:

````bash
Check: the compact island shows the cat at work, not idle (with several agents the others sit in the grid on its right). Click once on the island's black body, away from any cat or button (a hover never opens the compact island: it only keeps it from hiding), wait 2 s for the overview, then `shot 04-session-open`: the session is listed under the project name `notchmeow-qa`. Move the pointer away. Check: the step row reads `Runs · echo NM-QA step`; copy what you see into the report.

**The same from a terminal.** Claude Code in Terminal, iTerm, Ghostty or Warp reaches the island just as it does from VS Code (the payload says `term_program` `Apple_Terminal`, not `vscode`):

```bash
"$RELAY" < "$QA/payloads/terminal-start.json"; sleep 1
"$RELAY" < "$QA/payloads/terminal-work.json"; sleep 2
shot 04b-terminal-session
"$RELAY" < "$QA/payloads/terminal-stop.json"; sleep 1
```

Check: the compact notch shows the cat at work again, and the open overview lists `notchmeow-qa-terminal` with the step row `Runs · echo NM-QA terminal`. The two sessions share the Claude Code pill (labelled "VS Code"), so the project name is the last session's. If nothing shows, the terminal session was ignored: that is a FAIL, not a note.

## Step 5: an approval, which you answer
````

**Edit `docs/QA-MAC.md`**

Find (it occurs once):

```bash
| `03-session-compact` | the compact notch with a working session |
| `04-session-open` | the open overview listing `notchmeow-qa` |
| `05-approval`, `06-approval-answered` | the permission card with `echo NM-QA-APPROVAL`, then the island after Allow |
| `07-question`, `08-question-answered` | the question card, then the island after the answer |
```

Replace with:

```bash
| `03-session-compact` | the compact notch with a working session |
| `04-session-open` | the open overview listing `notchmeow-qa` |
| `04b-terminal-session` | the notch with a working session from a terminal (`notchmeow-qa-terminal`) |
| `05-approval`, `06-approval-answered` | the permission card with `echo NM-QA-APPROVAL`, then the island after Allow |
| `07-question`, `08-question-answered` | the question card, then the island after the answer |
```

**Edit `docs/QA-MAC.md`**

Find (it occurs once):

```bash
| 2 | install | | checksum, version, archs, signature |
| 3 | greeting | | screenshots |
| 4 | a session in the island | | |
| 5 | approval answered | | the card text, the contents of approval.out |
| 6 | question answered | | the card text, the contents of question.out |
```

Replace with:

```bash
| 2 | install | | checksum, version, archs, signature |
| 3 | greeting | | screenshots |
| 4 | a session in the island, from VS Code and from a terminal | | the step rows, `04b-terminal-session` |
| 5 | approval answered | | the card text, the contents of approval.out |
| 6 | question answered | | the card text, the contents of question.out |
```

**Edit `docs/INTEGRATIONS.md`**

Find (it occurs once):

```
- `nm-hook [--agent <nom>] <Event>` lit le JSON du hook sur stdin, ajoute le contexte du terminal (`TERM_PROGRAM`, `ITERM_SESSION_ID`, `TERM_SESSION_ID`, `__CFBundleIdentifier`, le tty trouvé en remontant les processus parents, `cwd`) et, si `--agent` est fourni, le champ `nm_agent`, puis l'envoie à l'app.
- **Si l'app ne répond pas en 300 ms, `nm-hook` sort en code 0 sans rien écrire** : Claude Code continue normalement. Jamais de blocage.
- Champ optionnel `nm_agent` : nom en minuscules, chiffres et tirets, 24 caractères au plus. Si absent ou invalide, l'événement va dans la pastille Claude. Voir `docs/AGENTS.md` pour les autres agents.
```

Replace with:

```
- `nm-hook [--agent <nom>] <Event>` lit le JSON du hook sur stdin, ajoute le contexte du terminal (`TERM_PROGRAM`, `ITERM_SESSION_ID`, `TERM_SESSION_ID`, `__CFBundleIdentifier`, le tty trouvé en remontant les processus parents, `cwd`) et, si `--agent` est fourni, le champ `nm_agent`, puis l'envoie à l'app.
- **Si l'app ne répond pas en 300 ms, `nm-hook` sort en code 0 sans rien écrire** : Claude Code continue normalement. Jamais de blocage.
- **Quelles sessions apparaissent (Mac).** Toutes les sessions Claude Code arrivent, depuis VS Code comme depuis n'importe quel terminal (Terminal, iTerm, Ghostty, Warp, kitty…), comme sur Windows et Linux ; avant, seules celles de VS Code et de Cursor étaient affichées. Elles partagent la pastille Claude Code (`integration_claude`, libellée « VS Code »). Cursor et Codex gardent leur pastille (`agent_cursor`, `agent_codex`) et un agent étiqueté `nm_agent` la sienne. Deux sessions à la fois (VS Code et un terminal) partagent donc la même pastille : l'île montre la dernière. Les notes « Handled in … » et « Still waiting in … » nomment l'app où se trouve la session (VS Code, Terminal, iTerm…), et un tap sur la pastille amène cette app devant (version GitHub). La règle est `HookOrigin.swift`, testée par `scripts/test-hook-origin.sh` et `scripts/test-hook-origin-wiring.sh`.
- Champ optionnel `nm_agent` : nom en minuscules, chiffres et tirets, 24 caractères au plus. Si absent ou invalide, l'événement va dans la pastille Claude. Voir `docs/AGENTS.md` pour les autres agents.
```

**Edit `CLAUDE.md`**

Find (it occurs once):

```
- `NotchBuddy/Sources/App/ShortcutLogic.swift` — every keyboard shortcut on the Mac: the global actions and their defaults, stored values and their validation, the island's own keys. Pure Foundation, tested by `scripts/test-shortcuts.sh`; `HotKeyCenter.swift` registers the global ones with Carbon (`docs/SPEC.md` §13). The Windows and Linux app has none.
- `NotchBuddy/Sources/App/IslandWing.swift` — the compact island's right wing steps aside (Mac only): with the pointer over the grid of agent cats the grid and the ear's black fade out in 0.15 s, the panel passes the mouse on to the menu-bar icons under it, and the grid comes back 1 s after the pointer leaves; the pointer over the wing no longer opens the island. Pure Foundation rules, fed by `IslandWindowController.pollFrame` (the existing poll: no timer or monitor of its own) and tested by `scripts/test-island-wing.sh`; `scripts/test-island-wing-wiring.sh` pins the app-side call sites; `render-cats.sh --wing` draws the faded state (`docs/SPEC.md`, "L'aile droite s'efface").
- `docs/SPEC.md`, `docs/INTEGRATIONS.md` — behaviour, views, states, integrations (in French).
- `design/prototype/notchmeow.html` — the cat prototype, the visual source of truth for the characters.
```

Replace with:

```
- `NotchBuddy/Sources/App/ShortcutLogic.swift` — every keyboard shortcut on the Mac: the global actions and their defaults, stored values and their validation, the island's own keys. Pure Foundation, tested by `scripts/test-shortcuts.sh`; `HotKeyCenter.swift` registers the global ones with Carbon (`docs/SPEC.md` §13). The Windows and Linux app has none.
- `NotchBuddy/Sources/App/IslandWing.swift` — the compact island's right wing steps aside (Mac only): with the pointer over the grid of agent cats the grid and the ear's black fade out in 0.15 s, the panel passes the mouse on to the menu-bar icons under it, and the grid comes back 1 s after the pointer leaves; the pointer over the wing no longer opens the island. Pure Foundation rules, fed by `IslandWindowController.pollFrame` (the existing poll: no timer or monitor of its own) and tested by `scripts/test-island-wing.sh`; `scripts/test-island-wing-wiring.sh` pins the app-side call sites; `render-cats.sh --wing` draws the faded state (`docs/SPEC.md`, "L'aile droite s'efface").
- `NotchBuddy/Sources/App/HookOrigin.swift` — which pill a hook event belongs to (Mac): Claude Code from VS Code **and from any terminal** reaches the Claude Code pill (`integration_claude`, labelled "VS Code"), Cursor, Codex and tagged agents keep theirs, and the "Handled in …" notes and the pill's tap name the app the session runs in. Pure Foundation, tested by `scripts/test-hook-origin.sh`; `scripts/test-hook-origin-wiring.sh` pins the call sites in `HookServer`; `scripts/fake-terminal-events.py` sends a scripted terminal session to a running Debug build and is only for the owner's check.
- `docs/SPEC.md`, `docs/INTEGRATIONS.md` — behaviour, views, states, integrations (in French).
- `design/prototype/notchmeow.html` — the cat prototype, the visual source of truth for the characters.
```

- [ ] **Step 6: Put the script's test in CI**

**Edit `.github/workflows/build.yml`**

Find (it occurs once):

```yaml
      - name: Island right wing wiring (source pins of the panel, AppState and the view)
        run: bash scripts/test-island-wing-wiring.sh

      - name: Hook routing (VS Code and every terminal reach the Claude Code pill)
        run: bash scripts/test-hook-origin.sh

      - name: Hook routing wiring (source pins of HookServer, ApprovalInfo, AppState and the pill's tap)
        run: bash scripts/test-hook-origin-wiring.sh
```

Replace with:

```yaml
      - name: Island right wing wiring (source pins of the panel, AppState and the view)
        run: bash scripts/test-island-wing-wiring.sh

      - name: Hook routing (VS Code and every terminal reach the Claude Code pill)
        run: bash scripts/test-hook-origin.sh

      - name: Hook routing wiring (source pins of HookServer, ApprovalInfo, AppState and the pill's tap)
        run: bash scripts/test-hook-origin-wiring.sh

      - name: Fake terminal session (the owner's script, sent to a test socket)
        run: bash scripts/test-fake-terminal-events.sh
```

- [ ] **Step 7: The guards**

```bash
bash scripts/check-no-leftovers.sh 2>&1 | tail -2
bash scripts/test-hook-origin.sh | tail -1 && bash scripts/test-hook-origin-wiring.sh | tail -1 && bash scripts/test-fake-terminal-events.sh | tail -1
git diff --stat
```

Expected: `✓` lines from the leftovers guard, three `All tests passed.`, and a diff stat of only the files this task names.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current     # this worktree's folder, and mac/all-terminals
MSG="$(mktemp "${TMPDIR:-/tmp}/nm-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
docs(hooks): the Mac shows every terminal; a scripted terminal session for the owner

fake-terminal-events.py sends a Claude Code session in a terminal (Apple Terminal by
default) to a running Debug build, like fake-subagent-events.py; its test sends only to a
socket of its own. The Mac QA brief gets a terminal half of step 4, INTEGRATIONS.md says
which sessions appear, and CLAUDE.md has the map bullet.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add scripts/fake-terminal-events.py \
  scripts/test-fake-terminal-events.sh \
  docs/QA-MAC.md \
  docs/INTEGRATIONS.md \
  CLAUDE.md \
  .github/workflows/build.yml
git status --short
git commit -F "$MSG"
```

Expected: `git status --short` lists only the files above (all staged). Never push.

---

### After Task 3: the whole-branch review

Dispatch `nm-reviewer-deep` (Sonnet 5.5, high; trigger 4) over `git diff notchmeow/rebrand...HEAD`. Its brief names: the five Review Focus items; that `HookOrigin.route` must give the same pill as the three old copies for every VS Code, Cursor, Codex and tagged-agent payload (compare the old text with `git show notchmeow/rebrand:NotchBuddy/Sources/App/HookServer.swift`); that the chat filter is first in all three entry points; that nothing reads `~/.claude` or `transcript_path`; and that no approval can be answered without a click. Fix what it finds, and re-run Task 2 Step 8.

---

### Task 4: Owner checkpoint

No code. The worktree session stops here and reports to the main session (and the main session double-checks in its own clone before the owner sees anything).

**What to say to the owner:**

1. Build a Debug app from the branch: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO`, then open `NotchBuddy/build/Build/Products/Debug/NotchMeow.app` (the owner opens the app; no session does).
2. With that app running, from the repository root:

   ```bash
   python3 scripts/fake-terminal-events.py
   ```

   It sends five events as Apple Terminal (`term_program` `Apple_Terminal`, `bundle_id` `com.apple.Terminal`; no real `claude` runs): the Claude Code pill appears, the cat thinks, a step reads `Runs · echo NM-FAKE step`, then the turn ends. **Look for:** the island showing the session under the project `notchmeow-fake-terminal` (before this change nothing appeared, and the log said `Ignored`).
3. Then the approval: `python3 scripts/fake-terminal-events.py --approval`. The card opens on the Claude Code pill with `echo NM-FAKE-APPROVAL`; click **Deny** (or Allow: nothing runs). Leave it unanswered once for two minutes: the note reads **"Still waiting in Terminal."**
4. Other terminals: `python3 scripts/fake-terminal-events.py --term-program iTerm.app --bundle-id com.googlecode.iterm2`, and `--term-program ghostty --bundle-id com.mitchellh.ghostty`.
5. Click the Claude Code pill while Terminal is running: **Terminal comes forward** (not VS Code). With VS Code events (`tests/fixtures/mac/subagent-scenarios.json`, `python3 scripts/fake-subagent-events.py`) the pill still opens VS Code and the note still says "VS Code".

Report: the commits, every test line from the controller brief, both build lines, and the review verdict.

## The owner's answers (2026-10-14)

The owner approved this plan as drafted, as the prerequisite round of sub-project F1.
