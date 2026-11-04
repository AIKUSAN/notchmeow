# Focus awareness (Mac): Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a permission request or a question arrives from a session whose app is the frontmost app, NotchMeow answers "ask" at once so the agent prompts in its own window; the island stays closed and silent, the pill gets a still amber dot (open island and compact notch), and a read-only "Waiting in <app>: <step words>" note sits on the pill's card until the session moves on or 10 minutes pass. Projects shows the same wait as "Waiting in <app>".

**Architecture:** One pure Foundation file, `FocusAware.swift`, holds every decision (the setting, the session's host, the match against the frontmost bundle ID, the marks and their endings, the wording, built on P-mac's `ProjectsRules.waitLabel`). One small app file, `FocusAwareApp.swift`, reads `NSWorkspace.shared.frontmostApplication` once per request, does the session's bookkeeping and records the mark. `HookServer` calls it in its two request handlers right before P-mac's Projects feed (which then gets the host as `waitIn`), ends marks from `processEvent`, and the views read the marks at draw time. No timer, no observer, no poll.

**Tech Stack:** Swift 6, SwiftUI + AppKit, `swiftc` test programs under `tests/` run by `scripts/test-*.sh`.

**Spec:** `docs/superpowers/specs/2026-10-17-focus-awareness-design.md` (binding, including "Calls made after the builder check" 1 to 7). The label rule is `shared/projects-core.js` `waitLabel` and `APP_WAIT_LABEL` (`docs/PROJECTS-CONTRACT.md`), already ported and fixture-tested on the Mac as `ProjectsRules.waitLabel` (P-mac). The Settings row's home is the restyle spec's (`docs/superpowers/specs/2026-10-17-settings-restyle-design.md`, control map: General → General → Island). The Windows/Linux twin is `docs/superpowers/plans/2026-10-17-focus-awareness-tauri.md` and runs after this plan is merged.

**Base:** a new branch `focus/mac` in a git worktree from `main` at `88055777` or later (`git merge-base --is-ancestor 88055777 HEAD` must succeed; P-mac and the Settings restyle are merged there: `grep -c 'static func waitLabel' NotchBuddy/Sources/App/ProjectsRules.swift` prints `1`, `grep -c 'var focusAware: Binding<Bool>? = nil' NotchBuddy/Sources/App/SettingsGeneralPage.swift` prints `1`). If a find text below does not occur exactly once (or as many times as the step says), stop and report; do not guess.

## Refresh 2026-10-22

Redrafted against `main` at `88055777` (first draft: `414d89e6`, 2026-10-17). What changed, and why:

- **Base** moved to `88055777`: P-mac (`5d4cb85b`), the Settings restyle (`50e55140`), the tuck-away, the title-row fix (`a1100f6e`), the Claude App routing and the hooks/Plan usage fix are merged.
- **The `waitLabel` port is gone:** P-mac already ports it (`ProjectsRules.waitLabel`, `appWaitLabel`, fixture-tested). `FocusAware.noteText` calls it; the node drift check and `FocusAware.waitLabel`/`appWaitLabel` are dropped (one function for the label, the spec's "The Projects fit").
- **Old Step 7b is now a normal step (Task 2 Step 5):** P-mac's feed is `ProjectsModel.shared.feedFromHook(payload: payload, waitIn: nil)` (not `feed`), 3 times in `HookServer.swift`, and it sits *before* the ask-at-once check. The step-back goes before it, all three feeds become `…waitIn: waitIn)` with a local `waitIn`, and `tests/ProjectsWiringTests.swift`'s `feedLine` changes to match (its count of 3 and its order pins still hold).
- **New: the `--ask` twin keeps the host in Projects (`FocusAware.twinWaitIn`).** Projects reads the ordinary `PreToolUse` of `AskUserQuestion` as a question ask; without the host it would replace the stepped-back wait with a 130 s card wait, so Projects and the dot would disagree depending on which hook lands first.
- **The Settings row exists already.** The restyle put "Step back when I'm already in the app" in General → General → Island, right after Open on hover, behind an optional binding passed as `nil`. Task 3 makes the binding non-optional, wires `$state.focusAware`, gives the row a help line, and adds the sample to `render-settings.swift`. `SettingsView.swift` is no longer touched.
- **The new key is homed in the control map (Task 1):** `static let defaultsKey = "island.focusAware"` is a key literal that `scripts/test-settings-map.sh` scans, so Task 1 adds it to `SettingsMap.swift`, `tests/SettingsMapTests.swift` (`frozen`) and `tests/fixtures/settings/controls.json` (Windows columns empty until the twin).
- **The note is placed where the Claude Code card actually draws.** The Claude Code pill is an integration pill, so its card is `IntegrationCardView` (the "active session" branch), not `OverviewView`'s own VStack (the first draft's only place, which only non-integration pills reach). Both now get the note.
- **The Claude-only layout (P-mac) needs nothing new:** Claude Code sessions show as project pills and the big card there, the Claude Code pill is not in the grid, and Projects already draws the wait (amber pill and dot, "Waiting in <host>" in the rows, the count, the compact badge) from `waitIn`. The dot and note stay on the agents' pills and the Claude Code card in the agents layout.
- **`focusDot` reuses `AppState.cardWaiting(on:)`** (added since the first draft).
- **`project.pbxproj` is committed** with the new Swift files (it is tracked; `xcodegen` rewrites it).
- **Model:** still Haiku 5.5 at high effort; no CLAUDE.md trigger applies (the new interfaces are one closure in the Projects feed, one map entry, one optional binding made required).

## Global Constraints

Every task's requirements include this section.

- **The only answer this feature sends is the existing `{"permissionDecision":"ask"}`.** It never allows, denies or answers a question. `HookServer.swift` keeps exactly 2 occurrences of `"permissionDecision":"allow"` (pinned).
- **Never block Claude Code.** A stepped-back request is answered on a detached task at once, exactly as the existing ask-at-once paths are; nothing is awaited before the answer.
- **0 % CPU when the island is hidden: no poll, no timer, no observer.** The frontmost app is read once per request (`NSWorkspace.shared.frontmostApplication`), only when the setting is on and the session's host is known, and nowhere else. No `NSWorkspace` notification observer (the spec's anti-goal "A poll, a timer or an observer"), no `Timer`, `asyncAfter` or `DispatchSource` in the new files. The 10-minute end is judged when a view reads a mark.
- **No new permission prompt** (no Accessibility, no Screen Recording). Only the frontmost app's bundle ID is read; it is compared and dropped, never logged, stored or shown. No window title, document name or window content is read.
- **Every doubt is today's behaviour:** no host, a blank bundle ID, an unknown terminal, an unreadable frontmost app: not matched, and the request goes on to today's code unchanged.
- **A stepped-back request is final and touches nothing else:** it does not open, reveal, pin or hold the island, call the desktop cat, play a sound, set a pill badge, change a pill's state, change `focusId`, create a pill, or displace a waiting approval or question card.
- **Projects and the dot say the same thing:** a step-back reaches Projects as `waitIn` (its host words), never as a second wait; the label is `ProjectsRules.waitLabel` in both places.
- **Swift 6, no new dependency.** Pure files import Foundation only. In every build (Debug, Release, App Store); in the App Store build the tagged agents' route is not matched (`githubBuild: false`), Codex has no route there anyway.
- **Never restyle what ships.** The only visible additions are the amber dot, the note line and the Settings row's binding and help line. The approval badge (`PillBadgeView`) is unchanged and wins over the dot. The Projects views are unchanged.
- **Colours come from the theme:** the dot and the note use `Theme.State.color["approval"] ?? "#F5A524"`, the expression P-mac's `ProjectsStyle.amber` holds (that enum is `fileprivate` to `ProjectsViews.swift`, so it is repeated, not shared). No change to `shared/theme.json`.
- **Frozen values untouched:** pill IDs, cat IDs, `nm-hook`, `nm.sock`, `nm_agent`, the relays (no change to the two Python relays in `HookServer.swift`; `scripts/test-hook-relay.sh` stays green unchanged). New names: the key `island.focusAware`, the types below.
- **Models and commits** (CLAUDE.md, "Working with AI agents"): Haiku 5.5 first; Sonnet 5.5 only on a named trigger; never Opus or Fable. Each commit is local, never pushed, lists only its task's files, uses `git commit -F <file>`, and ends with the `Co-Authored-By` line of the model that did the task. A task that ran `xcodegen` after adding a Swift file also commits `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app: the installed app is running and owns the hook socket. No task sends a hook event to the real socket.
  2. Install nothing. No network calls.
  3. Use `trash`, never `rm -rf`, for anything you delete by hand; scratch files go under `${TMPDIR:-/tmp}` in a uniquely named folder.
  4. Never edit `design/prototype/cat-core.js`, `shared/projects-core.js`, `shared/sidekick-core.js`, `shared/theme.json`, a generated theme file, a fixture under `tests/fixtures/` (one exception: Task 1 adds one control to `tests/fixtures/settings/controls.json`), or anything under `windows/`.
  5. Never push. Commit only in a task's commit step, after `git rev-parse --show-toplevel` shows this worktree and `git branch --show-current` shows `focus/mac`.
  6. Never rename a frozen ID; write no `Coucou` or `Mochi` name anywhere.
  7. Never read, print or write the real `~/.claude/settings.json` or anything in the real `~/.claude`, `~/.gemini`, `~/.codex`.
  8. If a command is denied by a permission prompt, stop and report it.

## Review Focus

The spec says what happens; it is silent on these conditions, most likely first. Each names the test that pins it.

1. **The question's two PreToolUse hooks race.** A question arrives through the `--ask` PreToolUse hook while Claude Code's ordinary PreToolUse hook for the same `AskUserQuestion` call runs in parallel. Expected: whichever lands first, the mark stays, and Projects keeps it as "Waiting in <host>" (not a 130 s card wait). Tests: Task 1 (`end` ignores `PreToolUse`/`AskUserQuestion`; `twinWaitIn` gives the mark's host only for that twin of a question mark), Task 2 (pin: `processEvent`'s feed passes `FocusAware.twinWaitIn(…)`).
2. **A Sidekick nudge about a request the owner is already answering in their app.** The ledger is fed the stepped-back `PermissionRequest`, so after 60 s the "still waiting for your OK" nudge would open the island. Expected: no waiting nudge while a step-back mark lives (recaps and the other nudges are unaffected). Test: Task 2 (`SidekickEngineTests`: `stepBackWaiting` true, 120 s pass, no `stuck.waiting`).
3. **A card already waiting when another request steps back.** A card from session A is up; session B's request steps back. Expected: A's card, its fd, its timers and its focus are untouched; B is answered "ask" and marked. And a card's "Handled in …" note for a session that still has a live mark reads the mark's note instead (call 7). Tests: Task 2 wiring pins (the step-back and its return precede the displacement code; `FocusAware.cardNote` in `dismissApprovalCard`), Task 1 (`cardNote`).
4. **The setting off, or no host: the frontmost app is never read.** Expected: with `island.focusAware` false, or a session whose host is unknown, the frontmost closure is not called. Test: Task 1 (`decide` with a counting closure).
5. **Hosts that are close but not exact.** Cursor's Electron app is not VS Code; VS Code Insiders is; a terminal named only by an unknown `TERM_PROGRAM` is no host; a tagged agent whose event names no terminal is no host; NotchMeow's own bundle ID never matches. Test: Task 1 (the host table cases).

Also covered: a stored value that is not a Bool reads as on (Task 1), the 10-minute end with a clock that went backwards (Task 1), a mark replaced by a newer request of the same session (Task 1), the step words never carrying a command or a path (Task 1, `SessionStepText.verb`), the stored key homed once in the control map (Task 1, `test-settings-map.sh`).

---

## File Structure

| Path | Responsibility |
|---|---|
| `NotchBuddy/Sources/App/FocusAware.swift` (new) | The pure rules: setting, host, match, decide, marks, wording, the twin's `waitIn` (Task 1). |
| `NotchBuddy/Sources/App/SessionStepText.swift` (modify) | `verb(tool:)`: the label alone, never the input (Task 1). |
| `tests/FocusAwareTests.swift`, `scripts/test-focus-aware.sh` (new) | The decision table (Task 1). |
| `NotchBuddy/Sources/App/SettingsMap.swift`, `tests/SettingsMapTests.swift`, `tests/fixtures/settings/controls.json` (modify) | The key `island.focusAware` homed in General → General → Island (Task 1). |
| `NotchBuddy/Sources/App/FocusAwareApp.swift` (new) | The frontmost read, the bookkeeping, the clock (Task 2). |
| `NotchBuddy/Sources/App/AppState.swift`, `HookServer.swift`, `Sidekick.swift`, `SidekickEngine.swift` (modify) | The setting and the marks, the two call sites and the Projects `waitIn`, the endings, the card note, the waiting nudge (Task 2). |
| `tests/FocusAwareWiringTests.swift`, `scripts/test-focus-aware-wiring.sh` (new), `tests/SidekickEngineTests.swift`, `tests/ProjectsWiringTests.swift` (modify) | Source pins, the engine case, P-mac's feed line (Tasks 2 and 3). |
| `NotchBuddy/Sources/App/FocusAwareViews.swift` (new), `IslandViewContent.swift`, `IslandRootView.swift`, `SettingsGeneralPage.swift`, `SettingsSections.swift` (modify) | The dot, the note, the Settings binding (Task 3). |
| `scripts/render-focus-aware.swift`, `scripts/render-focus-aware.sh` (new), `scripts/render-settings.swift` (modify) | The checkpoint pictures (Task 3). |
| `.github/workflows/build.yml` (modify) | The two new test scripts in CI (Tasks 1 and 2). |
| `CLAUDE.md`, `ARCHITECT.md`, `docs/SPEC.md` (modify) | The map bullet and the P-mac sentence, the flow paragraph, the French behaviour (Task 4). |

## Tasks and agents

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`, and read `swiftui-patterns` *(file: `~/.claude/plugins/marketplaces/ecc/skills/swiftui-patterns/SKILL.md`)* for Task 3 and `swift-concurrency-6-2` *(file)* for Task 2 (the main-actor hop and the detached answer). Reviewers load `ponytail:ponytail-review`. The final reviewer also loads `security-review` (hooks, a privacy rule) and runs `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` beside it (pass `model: sonnet`, trigger 4).

| # | Task | Agent, model, effort | Trigger | Review |
|---|---|---|---|---|
| 0 | Worktree and baseline | the session | | none |
| 1 | The pure rules, their tests, the key in the control map | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 2 | The app wiring: frontmost read, the two call sites, the Projects `waitIn`, endings, card note, Sidekick | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 3 | The dot, the note, the Settings binding, the pictures | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 3b | **Owner checkpoint 1:** the pictures | the main session and the owner | | none |
| 4 | Docs: CLAUDE.md, ARCHITECT.md, SPEC.md | `nm-implementer-light`, Haiku 5.5, medium | | `nm-reviewer` |
| After 4 | The whole branch: never allow, never block, no observer, privacy, Projects agreement | `nm-reviewer-deep`, Sonnet 5.5, high | 4 | none |
| 5 | **Owner checkpoint 2:** the real-machine check | the main session and the owner | | none |

Why no Sonnet implementer: the platform call is one line (`NSWorkspace.shared.frontmostApplication`), the concurrency is the existing main-actor handler plus the existing detached answer, and every decision is in the pure file; the Projects change is one argument at three existing call sites. If a Haiku task fails twice, hand it to `nm-implementer-deep` (trigger 2) and write the trigger in the ledger.

## Execution

One worktree chat session, branch `focus/mac`, **Haiku 5.5 at high effort** (no app-plan trigger 5: three coding tasks with one interface each). It edits `HookServer.swift`, `AppState.swift`, `IslandViewContent.swift`, `IslandRootView.swift`, `SettingsGeneralPage.swift`, `SettingsSections.swift`, `SettingsMap.swift`, `tests/ProjectsWiringTests.swift`, `tests/SettingsMapTests.swift`, `controls.json`, `build.yml` and `project.pbxproj`: do not run it beside another plan that edits them. The Keychain branch (`fix/keychain-save-in-place`) shares only `build.yml` and `project.pbxproj` (both mechanical to merge: re-run `xcodegen` for the latter). Start it in the three steps of `ARCHITECT.md` (the chip sets up and stops, the main session sets the model and effort, then sends the controller brief). The session pings the main session with `SendMessage` at Task 3b, at the end and whenever it stops. Keep a ledger at `.superpowers/sdd/2026-10-17-focus-mac/progress.md` (one line per task: agent, model, commit, test lines, review verdict). Reviews read `git diff main...HEAD` narrowed to the task's files.

---

### Task 0: Worktree and baseline

- [ ] **Step 1:** `git switch -c focus/mac main` in the new worktree; `git merge-base --is-ancestor 88055777 HEAD && echo ok` prints `ok`.
- [ ] **Step 2:** Anchor counts (each must print `1` unless noted):
  ```bash
  F=NotchBuddy/Sources/App/HookServer.swift
  grep -c '// The Projects registry reads every Claude Code event before the gate below (Projects, P-mac): it never answers anything.' $F
  grep -c '// The Projects registry counts the request before it is answered "ask" just below, a Claude App request included (Projects, P-mac).' $F
  grep -c '// The Projects registry counts the question before it is answered "ask" just below, a Claude App question included (Projects, P-mac).' $F
  grep -c 'ProjectsModel.shared.feedFromHook(payload: payload, waitIn: nil)' $F            # must print 3
  grep -c 'state.touchPill(agentId)   // the pill' $F
  grep -c 'private func dismissApprovalCard(note: String) {' $F
  grep -c '^        state.noteMessage = note$' $F
  grep -c 'let waitIn\|let stepped' $F                                                      # must print 0
  grep -o '"permissionDecision":"allow"' $F | wc -l                                        # must print 2
  grep -c 'HookOrigin.answersAskAtOnce(route: route, rawAgent: rawAgent)' $F                # must print 2
  grep -c 'env.ownCardShown = { let app = AppState.shared' NotchBuddy/Sources/App/Sidekick.swift
  grep -c 'static func waitLabel' NotchBuddy/Sources/App/ProjectsRules.swift
  grep -c 'var focusAware: Binding<Bool>? = nil' NotchBuddy/Sources/App/SettingsGeneralPage.swift
  grep -c 'focusAware: nil,' NotchBuddy/Sources/App/SettingsSections.swift
  grep -c 'static let feedLine = "ProjectsModel.shared.feedFromHook(payload: payload, waitIn: nil)"' tests/ProjectsWiringTests.swift
  grep -c 'TickerView(task: task, onDiffTap: onDiffTap)' NotchBuddy/Sources/App/IslandViewContent.swift
  grep -c 'if let second { secondLine(second) }' NotchBuddy/Sources/App/IslandViewContent.swift
  grep -c '.overlay { if state.sidekickDropPill == other.task.id' NotchBuddy/Sources/App/IslandRootView.swift
  ```
- [ ] **Step 3:** Baseline: `bash scripts/test-hook-origin.sh && bash scripts/test-hook-origin-wiring.sh && bash scripts/test-session-steps.sh && bash scripts/test-sidekick-engine.sh && bash scripts/test-sidekick-wiring.sh && bash scripts/test-hook-relay.sh && bash scripts/test-projects-rules.sh && bash scripts/test-projects-wiring.sh && bash scripts/test-settings-map.sh && bash scripts/test-settings-wiring.sh` all pass. Write the ledger's first line.

---

### Task 1: The pure rules, their tests, the key in the control map

**Files:**
- Create: `NotchBuddy/Sources/App/FocusAware.swift`, `tests/FocusAwareTests.swift`, `scripts/test-focus-aware.sh`
- Modify: `NotchBuddy/Sources/App/SessionStepText.swift`, `NotchBuddy/Sources/App/SettingsMap.swift`, `tests/SettingsMapTests.swift`, `tests/fixtures/settings/controls.json`, `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `HookOrigin.Route`, `HookOrigin.isDesktop(rawAgent:)`, `HookOrigin.desktopBundleId`, `HookOrigin.cursorBundleId`, `HookOrigin.isVSCode(termProgram:bundleId:)`, `HookOrigin.terminalBundleId(termProgram:bundleId:)`, `HookOrigin.hostName(pillId:termProgram:bundleId:)` (`HookOrigin.swift`); `ProjectsRules.waitLabel(_: Any?) -> String` (`ProjectsRules.swift`, P-mac).
- Produces (later tasks rely on these exact names):
  ```swift
  enum FocusAware {
      static let defaultsKey = "island.focusAware"
      static let markLifetime: Double = 600                        // seconds (spec rule 4, APP_WAIT_MS); the Windows twin pins this exact line
      static let endingEvents: [String] = ["PreToolUse", "PostToolUse", "PostToolUseFailure", "UserPromptSubmit", "Stop", "StopFailure", "Interrupt", "SessionEnd"]
      static let marksMax = 64
      static let codexBundleId = "com.openai.codex"
      enum Kind: String, Equatable, Sendable { case permission, question }
      enum Host: Equatable, Sendable { case app(String); case vscodeFamily }
      struct Mark: Equatable, Sendable { var sessionId: String; var pillId: String; var host: String; var kind: Kind; var words: String?; var at: Double }
      struct Marks: Equatable, Sendable {
          private(set) var entries: [Mark]
          init()
          mutating func record(_ mark: Mark)
          mutating func end(sessionId: String, event: String, tool: String)
          func live(now: Double) -> [Mark]
          func forPill(_ pillId: String, now: Double) -> Mark?
          func forSession(_ sessionId: String, now: Double) -> Mark?
          func anyLive(now: Double) -> Bool
      }
      static func enabled(stored: Any?) -> Bool
      static func host(route: HookOrigin.Route, rawAgent: String, termProgram: String, bundleId: String, githubBuild: Bool) -> Host?
      static func matches(_ host: Host, frontmost: String?) -> Bool
      static func decide(enabled: Bool, host: Host?, frontmost: () -> String?) -> Bool
      static func hostWords(route: HookOrigin.Route, rawAgent: String, termProgram: String, bundleId: String) -> String
      static func noteText(host: String, words: String?) -> String
      static func cardNote(_ note: String, mark: Mark?) -> String
      static func showsDot(markLive: Bool, badgeShown: Bool, cardWaiting: Bool) -> Bool
      static func twinWaitIn(event: String, tool: String, mark: Mark?) -> String?
  }
  extension SessionStepText { static func verb(tool: String) -> String? }   // in SessionStepText.swift itself
  ```

The rules, exactly:

- `enabled(stored:)`: `stored as? Bool ?? true` (absent or not a Bool reads as on, spec rule 8).
- `host`: a Claude app session (`HookOrigin.isDesktop(rawAgent:)`) is `.app(HookOrigin.desktopBundleId)` whatever the route. Else by route: `.codex` → `.app(codexBundleId)`; `.cursor` → `.app(HookOrigin.cursorBundleId)`; `.claude` → the session host below; `.external` → the session host below when `githubBuild`, else `nil`. **Session host:** `isVSCode` → `.vscodeFamily`; `bundleId` equal to Cursor's (case-insensitive) → `.app(cursorBundleId)`; else `HookOrigin.terminalBundleId(...)` as `.app`, `nil` when it is `nil`.
- `matches`: `false` for a `nil` or empty `frontmost`. `.app(id)`: equal ignoring case. `.vscodeFamily`: the lower-cased frontmost contains `vscode`.
- `decide`: `enabled && host != nil && matches(host!, frontmost: frontmost())`, calling `frontmost` only when the first two hold.
- `hostWords`: a Claude app session → `"Claude App"`; `.cursor` → `"Cursor"`; `.codex` → `"Codex"`; `.claude` and `.external` → `HookOrigin.hostName(pillId: "integration_claude", termProgram:, bundleId:)` (so a tagged agent in iTerm reads "iTerm"). Plan call: a tagged agent is named by its terminal, because its pill's own `hostName` is always "the terminal" and the spec names the host the owner is in.
- `noteText`: `ProjectsRules.waitLabel(host)`, then `": \(words)"` when `words` is non-nil and non-empty (spec rule 5, call 5). One label function for the note, the Projects rows and the Claude App wait (the spec's "The Projects fit"); `ProjectsRules` is pinned to `projects-core.js` by P-mac's fixtures.
- `cardNote`: the mark's `noteText(host:words:)` when `mark` is non-nil, else `note` (call 7).
- `showsDot`: `markLive && !badgeShown && !cardWaiting` (call 3: a waiting card wins; the badge place holds one thing).
- `twinWaitIn`: `mark?.host` when `event == "PreToolUse" && tool == "AskUserQuestion" && mark?.kind == .question`, else `nil`. Plan call: Projects reads that twin as a question ask (`projects-core.js` `projectEventFrom`); with the host it stays the same stepped-back wait whichever hook lands first.
- `Marks.record`: drops the entry with the same `pillId` and `sessionId` (a newer request replaces it), drops entries older than `markLifetime` measured from the new mark's `at`, appends, then keeps the newest `marksMax`.
- `Marks.end`: removes every entry of `sessionId` when `event` is in `endingEvents`, except `event == "PreToolUse" && tool == "AskUserQuestion"`, which ends nothing (Review Focus 1).
- `Marks.live(now:)`: entries with `now - at < markLifetime`; an entry with `at > now` (the clock went back) is live. `forPill`/`forSession`: the newest live entry (largest `at`) for that ID, or `nil`. `anyLive`: `!live(now:).isEmpty`.
- `SessionStepText.verb(tool:)`: move the `labels` table out of `line(tool:input:)` into `private static let labels: [String: String]` (same entries, `line` reads it, its output unchanged); `verb` returns `labels[tool]`, or for `mcp__server__tool` the same `"server · tool"` form `line` builds, else `nil`. It never reads an input, so it never carries a command, a path or a prompt. Plan call: Bash's verb is the table's plain "Runs" (the "Tests"/"Finds" inference needs the command).

- [ ] **Step 1: Write the failing test** `tests/FocusAwareTests.swift` (`@main enum FocusAwareTests`, `CT.section`/`CT.check`/`CT.checkTrue`/`CT.finish()` from `tests/CatTestSupport.swift`). Cases, with these exact values:

  ```swift
  // setting
  CT.check("key", FocusAware.defaultsKey, "island.focusAware")
  CT.checkTrue("absent reads on", FocusAware.enabled(stored: nil))
  CT.checkTrue("true", FocusAware.enabled(stored: true)); CT.checkTrue("false", !FocusAware.enabled(stored: false))
  CT.checkTrue("a string reads on", FocusAware.enabled(stored: "no"))
  // host table (githubBuild true unless named)
  let H = { (r: HookOrigin.Route, a: String, t: String, b: String) in FocusAware.host(route: r, rawAgent: a, termProgram: t, bundleId: b, githubBuild: true) }
  CT.check("Claude app", H(.claude, "claude-desktop", "", ""), .app("com.anthropic.claudefordesktop"))
  CT.check("Claude app wins over a terminal it names", H(.claude, "claude-desktop", "iTerm.app", "com.googlecode.iterm2"), .app("com.anthropic.claudefordesktop"))
  CT.check("terminal by bundle", H(.claude, "", "Apple_Terminal", "com.apple.Terminal"), .app("com.apple.Terminal"))
  CT.check("terminal by TERM_PROGRAM only", H(.claude, "", "iTerm.app", ""), .app("com.googlecode.iterm2"))
  CT.check("Ghostty", H(.claude, "", "ghostty", ""), .app("com.mitchellh.ghostty"))
  CT.check("unknown TERM_PROGRAM, no bundle: no host", H(.claude, "", "someterm", ""), nil)
  CT.check("nothing named: no host", H(.claude, "", "", ""), nil)
  CT.check("VS Code", H(.claude, "", "vscode", "com.microsoft.VSCode"), .vscodeFamily)
  CT.check("Cursor route", H(.cursor, "", "vscode", "com.todesktop.230313mzl4w4u92"), .app("com.todesktop.230313mzl4w4u92"))
  CT.check("Codex", H(.codex, "codex", "", ""), .app("com.openai.codex"))
  CT.check("tagged agent in iTerm", H(.external("gemini"), "gemini", "iTerm.app", "com.googlecode.iterm2"), .app("com.googlecode.iterm2"))
  CT.check("tagged agent naming no terminal", H(.external("gemini"), "gemini", "", ""), nil)
  CT.check("App Store: tagged agents not matched", FocusAware.host(route: .external("gemini"), rawAgent: "gemini", termProgram: "iTerm.app", bundleId: "com.googlecode.iterm2", githubBuild: false), nil)
  CT.check("App Store: the Claude app still matched", FocusAware.host(route: .claude, rawAgent: "claude-desktop", termProgram: "", bundleId: "", githubBuild: false), .app("com.anthropic.claudefordesktop"))
  // match
  CT.checkTrue("same bundle", FocusAware.matches(.app("com.apple.Terminal"), frontmost: "com.apple.Terminal"))
  CT.checkTrue("case-insensitive", FocusAware.matches(.app("com.apple.Terminal"), frontmost: "com.apple.terminal"))
  CT.checkTrue("another app", !FocusAware.matches(.app("com.apple.Terminal"), frontmost: "com.googlecode.iterm2"))
  CT.checkTrue("VS Code Insiders", FocusAware.matches(.vscodeFamily, frontmost: "com.microsoft.VSCodeInsiders"))
  CT.checkTrue("Cursor is not VS Code", !FocusAware.matches(.vscodeFamily, frontmost: "com.todesktop.230313mzl4w4u92"))
  CT.checkTrue("NotchMeow itself never", !FocusAware.matches(.app("com.apple.Terminal"), frontmost: "io.github.aikusan.notchmeow") && !FocusAware.matches(.vscodeFamily, frontmost: "io.github.aikusan.notchmeow"))
  CT.checkTrue("no frontmost", !FocusAware.matches(.app("x"), frontmost: nil) && !FocusAware.matches(.vscodeFamily, frontmost: ""))
  // decide reads the frontmost app only when it may step back
  var reads = 0; let fm: () -> String? = { reads += 1; return "com.apple.Terminal" }
  CT.checkTrue("off: no step back", !FocusAware.decide(enabled: false, host: .app("com.apple.Terminal"), frontmost: fm)); CT.check("off: not read", reads, 0)
  CT.checkTrue("no host: no step back", !FocusAware.decide(enabled: true, host: nil, frontmost: fm)); CT.check("no host: not read", reads, 0)
  CT.checkTrue("on and matched", FocusAware.decide(enabled: true, host: .app("com.apple.Terminal"), frontmost: fm)); CT.check("read once", reads, 1)
  // words
  CT.check("Claude App words", FocusAware.hostWords(route: .claude, rawAgent: "claude-desktop", termProgram: "", bundleId: ""), "Claude App")
  CT.check("VS Code words", FocusAware.hostWords(route: .claude, rawAgent: "", termProgram: "vscode", bundleId: ""), "VS Code")
  CT.check("iTerm words", FocusAware.hostWords(route: .claude, rawAgent: "", termProgram: "iTerm.app", bundleId: ""), "iTerm")
  CT.check("Cursor words", FocusAware.hostWords(route: .cursor, rawAgent: "", termProgram: "", bundleId: ""), "Cursor")
  CT.check("Codex words", FocusAware.hostWords(route: .codex, rawAgent: "codex", termProgram: "", bundleId: ""), "Codex")
  CT.check("tagged agent named by its terminal", FocusAware.hostWords(route: .external("gemini"), rawAgent: "gemini", termProgram: "ghostty", bundleId: ""), "Ghostty")
  CT.check("note with words", FocusAware.noteText(host: "VS Code", words: "Runs"), "Waiting in VS Code: Runs")
  CT.check("note without words", FocusAware.noteText(host: "iTerm", words: nil), "Waiting in iTerm")
  CT.check("empty words are none", FocusAware.noteText(host: "iTerm", words: ""), "Waiting in iTerm")
  CT.check("blank host", FocusAware.noteText(host: "  ", words: "Runs"), "Waiting in Claude App: Runs")
  for h in ["VS Code", "", "a/b\\c", "\u{202E}evil", "x".repeat(70), "the terminal"] {
      CT.check("one label with Projects: \(h.debugDescription)", FocusAware.noteText(host: h, words: nil), ProjectsRules.waitLabel(h))
  }
  CT.check("verb Bash", SessionStepText.verb(tool: "Bash"), "Runs")
  CT.check("verb Edit", SessionStepText.verb(tool: "Edit"), "Edits")
  CT.check("verb mcp", SessionStepText.verb(tool: "mcp__github__create_issue"), "github · create_issue")
  CT.check("verb unknown", SessionStepText.verb(tool: "AskUserQuestion"), nil)
  CT.check("line unchanged", SessionStepText.line(tool: "Bash", input: ["command": "npm test"]), "Tests · npm test")
  // card note and dot
  let m = FocusAware.Mark(sessionId: "S1", pillId: "integration_claude", host: "iTerm", kind: .permission, words: "Edits", at: 1000)
  CT.check("card note replaced while marked", FocusAware.cardNote("Handled in iTerm.", mark: m), "Waiting in iTerm: Edits")
  CT.check("card note kept without a mark", FocusAware.cardNote("Handled in iTerm.", mark: nil), "Handled in iTerm.")
  CT.checkTrue("dot", FocusAware.showsDot(markLive: true, badgeShown: false, cardWaiting: false))
  CT.checkTrue("badge wins", !FocusAware.showsDot(markLive: true, badgeShown: true, cardWaiting: false))
  CT.checkTrue("card wins", !FocusAware.showsDot(markLive: true, badgeShown: false, cardWaiting: true))
  CT.checkTrue("no mark", !FocusAware.showsDot(markLive: false, badgeShown: false, cardWaiting: false))
  // the --ask hook's twin keeps the host in Projects
  var q = m; q.kind = .question
  CT.check("twin of a question mark: its host", FocusAware.twinWaitIn(event: "PreToolUse", tool: "AskUserQuestion", mark: q), "iTerm")
  CT.check("twin of a permission mark: nil", FocusAware.twinWaitIn(event: "PreToolUse", tool: "AskUserQuestion", mark: m), nil)
  CT.check("another tool: nil", FocusAware.twinWaitIn(event: "PreToolUse", tool: "Bash", mark: q), nil)
  CT.check("another event: nil", FocusAware.twinWaitIn(event: "PostToolUse", tool: "AskUserQuestion", mark: q), nil)
  CT.check("no mark: nil", FocusAware.twinWaitIn(event: "PreToolUse", tool: "AskUserQuestion", mark: nil), nil)
  // marks
  var marks = FocusAware.Marks(); marks.record(m)
  CT.check("live at 599 s", marks.forPill("integration_claude", now: 1599)?.sessionId, "S1")
  CT.check("gone at 600 s", marks.forPill("integration_claude", now: 1600), nil)
  CT.check("a clock behind the mark keeps it", marks.forSession("S1", now: 900)?.sessionId, "S1")
  var n = m; n.words = "Runs"; n.at = 1100; marks.record(n)
  CT.check("a newer request of the session replaces it", marks.entries.count, 1); CT.check("newest words", marks.forSession("S1", now: 1200)?.words, "Runs")
  marks.end(sessionId: "S1", event: "PreToolUse", tool: "AskUserQuestion"); CT.check("the --ask twin ends nothing", marks.entries.count, 1)
  marks.end(sessionId: "S1", event: "Notification", tool: ""); CT.check("a notification ends nothing", marks.entries.count, 1)
  marks.end(sessionId: "S2", event: "Stop", tool: ""); CT.check("another session's stop ends nothing", marks.entries.count, 1)
  for ev in FocusAware.endingEvents { var k = FocusAware.Marks(); k.record(n); k.end(sessionId: "S1", event: ev, tool: "Bash"); CT.check("\(ev) ends it", k.entries.count, 0) }
  var many = FocusAware.Marks(); for i in 0..<70 { many.record(.init(sessionId: "S\(i)", pillId: "p", host: "h", kind: .question, words: nil, at: Double(i))) }
  CT.check("at most 64 kept, the newest", [many.entries.count, Int(many.entries.first!.at)], [64, 6])
  CT.checkTrue("anyLive", many.anyLive(now: 100) && !FocusAware.Marks().anyLive(now: 0))
  CT.finish()
  ```
  (`"x".repeat(70)` is `String(repeating: "x", count: 70)`.)

- [ ] **Step 2: Write `scripts/test-focus-aware.sh`** in the shape of `scripts/test-projects-rules.sh` (`set -euo pipefail`, `cd "$(dirname "$0")/.."`, a `mktemp -d` `TEST_DIR` with an `EXIT` trap, `export NM_LOG_DIR="$TEST_DIR/logs"`). It compiles `HookOrigin.swift`, `SessionStepText.swift`, `FocusAware.swift` plus the exact `swiftc` source list of `scripts/test-projects-rules.sh` (`ProjectsRules.swift` needs `SidekickText.swift` and the cat files for its own cat pick) and `tests/CatTestSupport.swift tests/FocusAwareTests.swift`, then runs the program. The header comment says: the focus-awareness rules (`FocusAware.swift`), whose label is P-mac's `ProjectsRules.waitLabel`; nothing here launches NotchMeow.
- [ ] **Step 3: Run it to see it fail.** `bash scripts/test-focus-aware.sh` → compile error (`FocusAware` not found).
- [ ] **Step 4: Implement** `FocusAware.swift` (Foundation only, no clock: every time is a parameter; a header comment naming the spec and the Windows twin `windows/src/core/focusaware.ts`) and `SessionStepText.verb(tool:)` per the rules above.
- [ ] **Step 5: Run.** `bash scripts/test-focus-aware.sh` → every line `✓`, exit 0. `bash scripts/test-session-steps.sh` still passes (the moved table changes no output).
- [ ] **Step 6: The key in the control map.** `bash scripts/test-settings-map.sh` now fails ("no key literal outside the frozen list": `island.focusAware`). Fix it in three places, each right after the `island.openOnHover` entry (the map's order is checked):
  - `SettingsMap.swift`: `Control(id: "island.focusAware", was: "(new) Focus awareness: Step back when I'm already in the app", homes: [h(.general, .general, "Island")], mac: [d("island.focusAware")]),`
  - `tests/fixtures/settings/controls.json`: the same control, `"winHomes": [], "win": []` (the Windows twin fills them), `"mac": [{ "key": "island.focusAware", "store": "defaults" }]`.
  - `tests/SettingsMapTests.swift` `frozen`: `("island.focusAware", "defaults", "\"island.focusAware\""),` after the `island.hoverGlow` tuple.
  Run `bash scripts/test-settings-map.sh` → passes.
- [ ] **Step 7: CI.** In `.github/workflows/build.yml`, after the step named `Hook routing wiring (source pins of HookServer, ApprovalInfo, AppState and the pill's tap)`, add:
  ```yaml
      - name: Focus awareness rules (FocusAware)
        run: bash scripts/test-focus-aware.sh
  ```
- [ ] **Step 8: Commit** `NotchBuddy/Sources/App/FocusAware.swift NotchBuddy/Sources/App/SessionStepText.swift NotchBuddy/Sources/App/SettingsMap.swift tests/FocusAwareTests.swift tests/SettingsMapTests.swift tests/fixtures/settings/controls.json scripts/test-focus-aware.sh .github/workflows/build.yml` with `feat(focus): the pure rules of focus awareness and its key (Mac)`.

---

### Task 2: The app wiring

**Files:**
- Create: `NotchBuddy/Sources/App/FocusAwareApp.swift`, `tests/FocusAwareWiringTests.swift`, `scripts/test-focus-aware-wiring.sh`
- Modify: `NotchBuddy/Sources/App/AppState.swift`, `HookServer.swift`, `Sidekick.swift`, `SidekickEngine.swift`, `tests/SidekickEngineTests.swift`, `tests/ProjectsWiringTests.swift`, `.github/workflows/build.yml`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (by `xcodegen`)

**Interfaces:**
- Consumes: everything Task 1 produces; `AppState.touchPill(_:)`, `AppState.noteHost(_:session:_:)`, `HookOrigin.hostBundleId(rawAgent:termProgram:bundleId:)`, `HookOrigin.pillId(_:)`, `Sidekick.shared.feed(payload:)`, `ProjectsModel.shared.feedFromHook(payload:waitIn:)`, `nbLog(_:)`.
- Produces:
  ```swift
  // AppState
  @Published var focusAware: Bool = true            // didSet saves under FocusAware.defaultsKey
  @Published var focusMarks = FocusAware.Marks()
  // FocusAwareApp.swift
  @MainActor enum FocusAwareApp {
      nonisolated static func now() -> Double           // Date().timeIntervalSinceReferenceDate (wall clock: a Mac asleep 10 min reads the mark as old)
      static func stepBack(payload: [String: Any], route: HookOrigin.Route, kind: FocusAware.Kind) -> FocusAware.Mark?   // non-nil: stepped back, and this is its mark
  }
  // SidekickEngine.Env
  var stepBackWaiting: () -> Bool = { false }
  ```

- [ ] **Step 1: Write the failing engine case** in `tests/SidekickEngineTests.swift`: add `var stepBack = false` to `World` (beside `ownCard`), `env.stepBackWaiting = { w.stepBack }` in `make` (beside `env.ownCardShown`), and after the existing `do { … }` block whose check reads "the clock fires at 60 s with nobody looking: the nudge shows", a new block:
  ```swift
  do {
      let w = World(), e = make(w)
      w.stepBack = true
      e.feed(payload: hook("SessionStart"))
      e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
      w.advance(120 * sec); e.envChanged()
      CT.check("a request that stepped back to its own app gets no waiting nudge", w.presented.map(\.kind).filter { $0 == "stuck.waiting" }, [])
  }
  ```
  Run `bash scripts/test-sidekick-engine.sh` → compile error (`stepBackWaiting`).
- [ ] **Step 2: The engine.** `SidekickEngine.Env` gains `var stepBackWaiting: () -> Bool = { false }` with a doc line ("a request stepped back to its own app (focus awareness) and still waits there: the waiting nudge is not for it"); `stuckContext()` passes `cardShown: env.ownCardShown() || env.stepBackWaiting()`. `SKShowInput`'s `ownCard: env.ownCardShown(),` is NOT changed (Plan call: only the waiting nudge is held back; recaps and the other nudges show as today). In `Sidekick.swift`, after the line starting `env.ownCardShown = { let app = AppState.shared`, add `env.stepBackWaiting = { AppState.shared.focusMarks.anyLive(now: FocusAwareApp.now()) }`. Re-run the engine test → passes.
- [ ] **Step 3: AppState.** After the `hoverGlow` property (`@Published var hoverGlow: Bool = true {` and its `didSet` line): `@Published var focusAware: Bool = true { didSet { UserDefaults.standard.set(focusAware, forKey: FocusAware.defaultsKey) } }` (comment: "Settings → General → Island → Step back when I'm already in the app (FocusAware) — persisted, on by default") and `@Published var focusMarks = FocusAware.Marks()` (comment: "the sessions that stepped back to their own app, in memory only; ended by FocusAware.Marks.end and read for age by the views"). In the load function, after `if let v = ud.object(forKey: IslandGlow.defaultsKey) as? Bool { hoverGlow = v }`: `focusAware = FocusAware.enabled(stored: ud.object(forKey: FocusAware.defaultsKey))`.
- [ ] **Step 4: FocusAwareApp.swift** (`import AppKit`). `stepBack`, in this order:
  1. `guard AppState.shared.focusAware else { return nil }`.
  2. Read `rawAgent` (`nm_agent`), `termProgram` (`term_program`), `bundleId` (`bundle_id`) and `sessionId` (`session_id` ?? `conversation_id` ?? `"unknown"`) from `payload`, as `HookServer` does.
  3. `githubBuild` is `true`, `false` under `#if APPSTORE`. `let host = FocusAware.host(route:rawAgent:termProgram:bundleId:githubBuild:)`.
  4. `guard FocusAware.decide(enabled: true, host: host, frontmost: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }) else { return nil }`. This is the file's only read of the frontmost app.
  5. `let pillId = HookOrigin.pillId(route)`; `state.focusMarks.record(FocusAware.Mark(sessionId:, pillId:, host: FocusAware.hostWords(...), kind:, words: kind == .permission ? SessionStepText.verb(tool: payload["tool_name"] as? String ?? "") : nil, at: now()))`. Recorded **before** the feed, so the Sidekick's evaluation already sees it.
  6. `state.touchPill(pillId)`; when `route == .claude`, `state.noteHost(pillId, session: sessionId, HookOrigin.hostBundleId(rawAgent: rawAgent, termProgram: termProgram, bundleId: bundleId))` (so the pill's tap still brings that app forward); `Sidekick.shared.feed(payload: payload)`.
  7. `nbLog("\(kind == .permission ? "PermissionRequest" : "Question") stepped back [\(pillId)]")` — the pill only, never the app's name or bundle ID. Return the mark.
  It creates no pill, sets no badge or state, touches no `focusId`, `isPinned`, `view`, sound or desktop cat, and does not feed Projects (the handler does, Step 5).
- [ ] **Step 5: HookServer, the two request handlers and their Projects feed.** In `processPermissionRequest`, the line right after `// The Projects registry counts the request before it is answered "ask" just below, a Claude App request included (Projects, P-mac).` is `ProjectsModel.shared.feedFromHook(payload: payload, waitIn: nil)`. Replace that one line with:
  ```swift
        // Focus awareness: the session's app is in front, so its own prompt is the place to answer (FocusAwareApp); Projects counts it as "Waiting in <host>".
        let stepped = FocusAwareApp.stepBack(payload: payload, route: route, kind: (payload["tool_name"] as? String) == "AskUserQuestion" ? .question : .permission)
        let waitIn = stepped?.host
        ProjectsModel.shared.feedFromHook(payload: payload, waitIn: waitIn)
        if stepped != nil {   // "ask" at once, no card, no sound
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }
  ```
  In `processQuestionRequest`, do the same to the feed line right after `// The Projects registry counts the question before it is answered "ask" just below, a Claude App question included (Projects, P-mac).`, with `kind: .question`. Both sit after the chat filter and before the ask-at-once check, any displacement, card, pin, sound or `expandIfNeeded` (rule 2, rule 7, call 6). A Claude App request now feeds Projects with `waitIn: "Claude App"`, which the core guards to `''` for a Claude App event (`docs/PROJECTS-CONTRACT.md`): still one entry, "Waiting in Claude App".
- [ ] **Step 6: HookServer, the endings and the twin.** In `processEvent`, right after the line `state.touchPill(agentId)   // the pill's last event: Two cats mode's busiest-other rule reads it`, add:
  ```swift
        state.focusMarks.end(sessionId: sessionId, event: name, tool: payload["tool_name"] as? String ?? "")   // a session that stepped back moves on (FocusAware, rule 4)
  ```
  Then replace the line right after `// The Projects registry reads every Claude Code event before the gate below (Projects, P-mac): it never answers anything.` (`ProjectsModel.shared.feedFromHook(payload: payload, waitIn: nil)`) with:
  ```swift
        // The --ask hook's ordinary PreToolUse twin keeps a stepped-back question's host, whichever of the two lands first (FocusAware.twinWaitIn).
        let waitIn = FocusAware.twinWaitIn(event: name, tool: payload["tool_name"] as? String ?? "", mark: state.focusMarks.forSession(sessionId, now: FocusAwareApp.now()))
        ProjectsModel.shared.feedFromHook(payload: payload, waitIn: waitIn)
  ```
  The ending runs before the pending-approval gate, so a session's resolving event ends its mark before its card's note is chosen.
- [ ] **Step 7: P-mac's feed pin.** In `tests/ProjectsWiringTests.swift`, change `static let feedLine = "ProjectsModel.shared.feedFromHook(payload: payload, waitIn: nil)"` to `static let feedLine = "ProjectsModel.shared.feedFromHook(payload: payload, waitIn: waitIn)"`. Nothing else in that file changes: the three feeds, their order pins and the negative controls hold. Run `bash scripts/test-projects-wiring.sh` → passes.
- [ ] **Step 8: HookServer, the card note (call 7).** In `dismissApprovalCard(note:)` (the first `let pillId = state.pendingApproval?.pillId ?? "integration_claude"` in the file, right under `private func dismissApprovalCard(note: String) {`; the second is in the click handler and is not touched), add after that line `let askedSession = state.pendingApproval?.sessionId`, and replace its line `        state.noteMessage = note` (8 spaces; the question card's line has 12 and is not touched) with:
  ```swift
        state.noteMessage = FocusAware.cardNote(note, mark: askedSession.flatMap { state.focusMarks.forSession($0, now: FocusAwareApp.now()) })
  ```
- [ ] **Step 9: Write the wiring pins** `tests/FocusAwareWiringTests.swift` (shape of `tests/IslandTuckAwayWiringTests.swift`: `source(_:)`, `count(_:in:)`, an `at(_:in:from:)` helper returning the offset or `-1`) and `scripts/test-focus-aware-wiring.sh` (shape of `scripts/test-island-tuck-away-wiring.sh`). Pins:
  - `FocusAware.swift` imports only Foundation and contains no `Timer`, `DispatchQueue`, `asyncAfter`, `Date()`, `NSWorkspace`.
  - `FocusAwareApp.swift`: `count("NSWorkspace.shared.frontmostApplication") == 1`; contains none of `notificationCenter`, `addObserver`, `didActivateApplication`, `Timer`, `asyncAfter`, `DispatchSource`, `"allow"`, `ProjectsModel`; `focusMarks.record(` comes before `Sidekick.shared.feed(payload: payload)`; the `nbLog(` line does not contain `bundleIdentifier`, `frontmost` or `host`.
  - `HookServer.swift`: `FocusAwareApp.stepBack(payload: payload, route: route, kind:` occurs 2 times; the first after `func processPermissionRequest`, then `ProjectsModel.shared.feedFromHook(payload: payload, waitIn: waitIn)`, then `if stepped != nil {`, then `#"{"permissionDecision":"ask"}"#`, then the first `HookOrigin.answersAskAtOnce(route: route, rawAgent: rawAgent)` after it, in that order; the second the same after `func processQuestionRequest`.
  - `HookServer.swift`: `state.focusMarks.end(sessionId: sessionId, event: name, tool:` occurs once, after `state.touchPill(agentId)` and before `HookOrigin.pendingVerdict(`; `FocusAware.twinWaitIn(event: name,` occurs once, after the `end` line and before `HookOrigin.pendingVerdict(`; `count("waitIn: nil") == 0`; `FocusAware.cardNote(note, mark:` occurs once, inside `dismissApprovalCard`.
  - `HookServer.swift`: `count("\"permissionDecision\":\"allow\"") == 2` (unchanged); `count("HookOrigin.answersAskAtOnce(route: route, rawAgent: rawAgent)") == 2` (unchanged).
  - `AppState.swift`: `@Published var focusAware: Bool = true`, `forKey: FocusAware.defaultsKey`, `focusAware = FocusAware.enabled(stored: ud.object(forKey: FocusAware.defaultsKey))`, `@Published var focusMarks = FocusAware.Marks()`.
  - `Sidekick.swift`: `env.stepBackWaiting = { AppState.shared.focusMarks.anyLive(now: FocusAwareApp.now()) }`; `SidekickEngine.swift`: `cardShown: env.ownCardShown() || env.stepBackWaiting()`, and `ownCard: env.ownCardShown(),` unchanged.
  End with `CT.finish()`. Run `bash scripts/test-focus-aware-wiring.sh` → all `✓`.
- [ ] **Step 10: Compile the app.** `cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet` → `BUILD SUCCEEDED` (no launch). Then `bash scripts/test-sidekick-wiring.sh`, `bash scripts/test-hook-origin-wiring.sh`, `bash scripts/test-u1-wiring.sh`, `bash scripts/test-hook-relay.sh`, `bash scripts/test-projects-wiring.sh`, `bash scripts/test-projects-model.sh`, `bash scripts/test-focus-aware.sh` all pass (the Sidekick pin "an event, a permission request and a question each feed it, once" still counts 3 in `HookServer.swift`: the step-back's feed lives in `FocusAwareApp.swift`).
- [ ] **Step 11: CI.** After the Task 1 step in `build.yml`:
  ```yaml
      - name: Focus awareness wiring (source pins of HookServer, AppState, the Sidekick and the views)
        run: bash scripts/test-focus-aware-wiring.sh
  ```
- [ ] **Step 12: Commit** the nine files and `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` with `feat(focus): step back to the session's app when it is in front (Mac)`.

---

### Task 3: The dot, the note, the Settings binding, the pictures

**Files:**
- Create: `NotchBuddy/Sources/App/FocusAwareViews.swift`, `scripts/render-focus-aware.swift`, `scripts/render-focus-aware.sh`
- Modify: `NotchBuddy/Sources/App/IslandViewContent.swift` (`AgentPill`, `OverviewView`, `IntegrationCardView`), `IslandRootView.swift` (`IslandContainer`, `CompactMiniGrid`), `SettingsGeneralPage.swift`, `SettingsSections.swift`, `scripts/render-settings.swift`, `tests/FocusAwareWiringTests.swift`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (by `xcodegen`)

**Interfaces:**
- Consumes: `AppState.focusMarks`, `AppState.focusAware`, `AppState.cardWaiting(on:)`, `FocusAwareApp.now()`, `FocusAware.showsDot`, `FocusAware.noteText`, `Marks.forPill`; `Theme.State.color["approval"]`; `AppState.cast.big.pill`, `AppState.cast.second?.pill`, `AppState.displayMode`, `AppState.desktopPhase.notchEmpty`, `CatIslandLayout.compactX(_:)`, `IslandRestingLayout(width:height:)` (`botDiameter`, `botCenterY`).
- Produces:
  ```swift
  struct FocusWaitDot: View { let size: CGFloat; var ring: Bool = false }      // amber (Theme.State.color["approval"] ?? "#F5A524"); ring = a dark #0B0C0E circle 2 pt wider behind it
  struct FocusWaitNote: View { let mark: FocusAware.Mark; let leading: CGFloat }   // one read-only line: FocusAware.noteText, 11 pt, amber
  struct FocusWaitCompactDots: View { @ObservedObject var state: AppState; let islandW: CGFloat; let islandH: CGFloat }
  extension AppState { @MainActor func focusDot(_ pillId: String) -> Bool }   // in FocusAwareViews.swift
  ```

`focusDot(_:)` is `FocusAware.showsDot(markLive: focusMarks.forPill(id, now: FocusAwareApp.now()) != nil, badgeShown: tasks.first { $0.id == id }?.pillBadge != nil, cardWaiting: cardWaiting(on: id))`.

Plan calls (the spec leaves size and place to the builder): the open-island dot is 8 pt amber on a 10 pt dark ring, no icon and no glow, at the badge's place (`.offset(x: 3, y: -3)` at the pill's top-trailing corner), so it reads apart from the 12 pt "!" approval badge; the compact dot is a plain 5 pt amber dot. No animation anywhere (rule 5, call 2).

Where each shows (dry-run against P-mac's overview):
- **Agents layout** (other agents, or no live project): the dot on any agent pill in the right card's grid (`AgentPill`), on the compact grid's cells, and beside the compact big cat and cat 2; the note under the ticker of the focused pill's card: `IntegrationCardView`'s active-session branch (the Claude Code pill, which is an integration pill, and the other catalog pills) and `OverviewView`'s own card (non-integration pills, where in Two cats mode it takes cat 2's line while it lives). The Claude Code card's Projects count capsule ("N" and the amber "M waiting") and the open section's row ("Waiting in iTerm") read the same wait, built by the same `ProjectsRules.waitLabel`.
- **Claude-only layout** (P-mac: Claude alone with a live project, not Two cats): nothing from this task. The Claude Code pill is filtered out of the grid and the left card is `ProjectBigCard`; Projects already draws the step-back from `waitIn` (amber project pill and dot that pulses while open, the big card's amber step line, "Waiting in <host>" in the rows, the waiting count). Another agent's pill in that grid still gets its dot (`otherPill` is `AgentPill`).
- **Compact:** Projects' amber count sits at `islandWidth - 66` (14 pt), the mini grid spans `islandWidth - 54` to `- 26`, the big cat at `x = 40` (`30`/`54` in Two cats mode): the dots never overlap the count. A Claude Code step-back shows both the dot by the big cat and the count, as the spec's call 2 and "The Projects fit" ask.

- [ ] **Step 1: Write the failing pins** (append to `tests/FocusAwareWiringTests.swift`):
  - `IslandViewContent.swift`: `AgentPill` contains `} else if state.focusDot(task.id) {` right after the `PillBadgeView(badge: badge, taskColor: effectiveColor)` block (the badge wins by construction), with `FocusWaitDot(size: 8, ring: true)`; `OverviewView` contains `state.focusMarks.forPill(agent.id, now: FocusAwareApp.now())` before `} else if let second { secondLine(second) }`; `IntegrationCardView` contains `appState.focusMarks.forPill(task.id, now: FocusAwareApp.now())` after `TickerView(task: task, onDiffTap: onDiffTap)`; `count("FocusWaitNote(mark:") == 2`; `PillBadgeView` is unchanged (its three colours and icons still present).
  - `IslandRootView.swift`: `CompactMiniGrid` contains `state.focusDot(other.task.id)`; `IslandContainer` contains `FocusWaitCompactDots(state: state, islandW: islandWidth, islandH: islandHeight)` inside an `if state.mode == .compact`, followed by `.opacity(greetingTail ? 0 : 1)` and `.opacity(state.wingYielded ? 0 : 1)`.
  - `FocusAwareViews.swift`: `Theme.State.color["approval"]` and `FocusAware.noteText(host: mark.host, words: mark.words)`; no `TimelineView`, `withAnimation`, `repeatForever`, `Timer`, `onTapGesture`, `Button`.
  - `SettingsGeneralPage.swift`: `var focusAware: Binding<Bool>` without `?`; `SwitchRow("Step back when I'm already in the app", help:` occurs once, after `SwitchRow("Open on hover"` and before `SwitchRow("Hover glow"`, with `isOn: model.focusAware)`; no `if let focusAware`. `SettingsSections.swift`: `focusAware: $state.focusAware,`. `scripts/render-settings.swift`: `focusAware: .constant(true)`.
  Run `bash scripts/test-focus-aware-wiring.sh` → those pins fail.
- [ ] **Step 2: `FocusAwareViews.swift`** (`import SwiftUI`): `FocusWaitDot`, `FocusWaitNote`, `FocusWaitCompactDots` and `AppState.focusDot`. `FocusWaitNote` is `Text(FocusAware.noteText(host: mark.host, words: mark.words))` (read-only: no button, no tap of its own) with `.font(.system(size: 11))`, `.foregroundColor(Color(hex: Theme.State.color["approval"] ?? "#F5A524"))`, `.lineLimit(1).truncationMode(.tail)`, `.padding(.leading, leading).padding(.trailing, 12).padding(.top, 2)` (the style of `OverviewView.secondLine`, the card's existing one-line note). `FocusWaitCompactDots` draws a 5 pt `FocusWaitDot` for the big cat (`state.cast.big.pill`) at `x = compactX(state.displayMode)[0] + d * 0.42`, `y = IslandRestingLayout(width:height:).botCenterY - d * 0.42` with `d = botDiameter`, and in Two cats mode for cat 2 (`state.cast.second?.pill`) at `compactX[1]` the same way, each only when `state.focusDot(pill)`; nothing for the big cat while `state.desktopPhase.notchEmpty`; `.allowsHitTesting(false)`.
- [ ] **Step 3: The pill.** In `AgentPill.body`, the existing `if let badge = task.pillBadge { PillBadgeView(...).offset(x: 3, y: -3) }` gains `} else if state.focusDot(task.id) { FocusWaitDot(size: 8, ring: true).offset(x: 3, y: -3) }`. Nothing else in `AgentPill` or `PillBadgeView` changes.
- [ ] **Step 4: The compact grid.** In `CompactMiniGrid`, the cell's existing `.overlay { if state.sidekickDropPill == other.task.id … }` is followed by `.overlay(alignment: .topTrailing) { if state.focusDot(other.task.id) { FocusWaitDot(size: 5).offset(x: 2, y: -2) } }`. In `IslandContainer`, right after the `CompactMiniGrid` group's last `.animation(wingAnimation, value: state.wingYielded)` (the one right after `.opacity(state.wingYielded ? 0 : 1)` that follows `.animation(.easeInOut(duration: 0.25), value: greetingTail)`), add the compact dots group: `Group { if state.mode == .compact { FocusWaitCompactDots(state: state, islandW: islandWidth, islandH: islandHeight) } }`, then `.opacity(greetingTail ? 0 : 1)` and `.opacity(state.wingYielded ? 0 : 1)` with the same animations the grid uses (they fade with the wing and wait for the greeting like the grid).
- [ ] **Step 5: The note.** In `OverviewView`, replace `if let second { secondLine(second) }` with:
  ```swift
  if let mark = state.focusMarks.forPill(agent.id, now: FocusAwareApp.now()) {
      FocusWaitNote(mark: mark, leading: textLeading)
  } else if let second { secondLine(second) }
  ```
  In `IntegrationCardView`'s active-session branch, after the `TickerView(task: task, onDiffTap: onDiffTap)` view and its four modifiers (`.frame(height: 44)`, `.padding(.top, 6)`, `.padding(.leading, 108)`, `.padding(.trailing, 12)`), add `if let mark = appState.focusMarks.forPill(task.id, now: FocusAwareApp.now()) { FocusWaitNote(mark: mark, leading: 108) }`. Plan call: the card's 98 pt holds the extra line (the same height `secondLine` takes in Two cats mode). The idle branch gets no note: a session that asks has already sent `SessionStart` or `UserPromptSubmit`, so its card is the active one.
- [ ] **Step 6: Settings.** In `SettingsGeneralPage.swift`: `var focusAware: Binding<Bool>? = nil` becomes `var focusAware: Binding<Bool>` (its comment: "Step back when I'm already in the app (focus awareness): right after Open on hover"), and the `if let focusAware = model.focusAware { SwitchRow("Step back when I'm already in the app", isOn: focusAware) }` block becomes:
  ```swift
                SwitchRow("Step back when I'm already in the app", help: "When an agent asks for permission or a question while its app is in front, it asks there: the island stays closed and quiet, and an amber dot on its pill shows it is waiting.", isOn: model.focusAware)
  ```
  (The help sentence is a Plan call; the label is the spec's.) In `SettingsSections.swift`, `focusAware: nil,` becomes `focusAware: $state.focusAware,`. In `scripts/render-settings.swift`, `openOnHover: .constant(false), hoverGlow: .constant(true),` becomes `openOnHover: .constant(false), focusAware: .constant(true), hoverGlow: .constant(true),`.
- [ ] **Step 7: Run the pins and the build.** `bash scripts/test-focus-aware-wiring.sh` → all `✓`. `cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet` → `BUILD SUCCEEDED`. `bash scripts/test-u1-wiring.sh`, `bash scripts/test-cat-wiring.sh`, `bash scripts/test-projects-wiring.sh`, `bash scripts/test-settings-wiring.sh`, `bash scripts/test-settings-map.sh` and `bash scripts/test-settings-contrast.sh` still pass.
- [ ] **Step 8: The pictures.** `scripts/render-focus-aware.sh` is a copy of `scripts/render-pills.sh` (whole-app compile through `scripts/render-home-guard.sh`, its own defaults domain `render-focus-aware` deleted on exit) building `scripts/render-focus-aware.swift`, which draws one PNG (`--out`, `--scale`, default `focus-aware.png`, 2x) on black with four labelled rows: (1) four `AgentPill`s: Claude Code with a live mark (the dot), Gemini with a live mark and `pillBadge = .approval` (the badge only), Cursor with a live mark and a pending approval on it (no dot), Codex plain; (2) `CompactMiniGrid` with Claude Code focused and Gemini marked, plus `FocusWaitCompactDots` on a 240 × 32 compact strip with the focused Claude Code marked; (3) `IntegrationCardView` for Claude Code at 322 × 98, working with two steps, a mark `host: "iTerm", words: "Edits"`; (4) `OverviewView`'s card for a tagged agent pill (non-integration) at 640 × 98 with a mark `host: "Ghostty", words: "Runs"`. Marks are recorded with `at: FocusAwareApp.now()`; no Projects session is fed, so the agents layout draws. Run `bash scripts/render-focus-aware.sh --out "${TMPDIR:-/tmp}/focus-aware.png"` (about seven minutes) → `wrote …`, and `bash scripts/render-settings.sh --page general --tab general --width 720 --out "${TMPDIR:-/tmp}/focus-settings"` → the General tab with the row, then `bash scripts/check-settings-render-private.sh` passes. Open the PNGs and check by eye: the dot on Claude Code only in row 1, the badge alone on Gemini, nothing on Cursor; the 5 pt dots in row 2; "Waiting in iTerm: Edits" under the ticker in row 3 and "Waiting in Ghostty: Runs" in row 4; the switch and its help in the Island card, between Open on hover and Hover glow.
- [ ] **Step 9: Commit** the ten source files and `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` with `feat(focus): the waiting dot, the note and the Settings switch (Mac)`.

---

### Task 3b: Owner checkpoint 1

- [ ] The main session sends the owner the two pictures from Task 3 Step 8 and asks: the dot's size and place, the compact dots, the note's line and wording on both cards, the Settings row and its help line, and the "Questions for the owner" below. Changes go back to Task 3; nothing proceeds until the owner says go.

---

### Task 4: Docs

**Files:** Modify `CLAUDE.md`, `ARCHITECT.md`, `docs/SPEC.md`.

- [ ] **Step 1: CLAUDE.md.** Add one bullet to "Where things are", after the `HookOrigin.swift` bullet:
  > - `NotchBuddy/Sources/App/FocusAware.swift` — focus awareness (Mac): when a permission request or a question comes from a session whose app is the frontmost app (app level: the Claude app, a terminal by its bundle ID or `TERM_PROGRAM`, the VS Code family, Cursor, Codex; a tagged agent by the terminal its event names, GitHub build only), `FocusAwareApp.stepBack` answers the existing `{"permissionDecision":"ask"}` at once from `HookServer`'s two handlers; no card, no sound, the island stays as it is, and a mark (`AppState.focusMarks`, memory only) shows a still amber dot on the pill (open island and compact notch; a badge or a waiting card wins) and the note "Waiting in <host>: <verb>" on the pill's card (`IntegrationCardView` and `OverviewView`), ended by the session's next PreToolUse (not `AskUserQuestion`'s), PostToolUse, PostToolUseFailure, UserPromptSubmit, Stop, StopFailure, Interrupt or SessionEnd, or 10 minutes judged at read time. The frontmost app is read once per request (`NSWorkspace.shared.frontmostApplication`), only with the setting on (`island.focusAware`, Settings → General → Island, on by default) and a known host: no observer, no timer, never logged. Projects gets the same wait: the request handlers feed it `waitIn: stepped?.host`, and `processEvent` passes `FocusAware.twinWaitIn` so the `--ask` hook's own PreToolUse keeps the host; the label is `ProjectsRules.waitLabel` in both, and the Claude-only layout shows the wait through Projects alone. The Sidekick's waiting nudge is held back while a mark lives (`SidekickEngine.Env.stepBackWaiting`). Tests: `scripts/test-focus-aware.sh`, `scripts/test-focus-aware-wiring.sh`; picture: `scripts/render-focus-aware.sh`.
  In the "Sub-project P on the Mac" bullet, replace `passes `waitIn` as `nil`: the three Projects feeds in `HookServer` pass nil today, and none is yet wired from `HookOrigin.hostName(...)`, the focus-awareness plan's call A)` with `passes `waitIn`: the step-back's host from the two request handlers, and in `processEvent` only `FocusAware.twinWaitIn`'s for the `--ask` hook's twin)`.
- [ ] **Step 2: ARCHITECT.md.** In "Main flows", item 1 ("Agent sessions"), add a sub-bullet after the `- **Windows:** `island/hooks.ts` updates `core/state.ts`.` line:
  > - **Focus awareness:** before building a card, `HookServer` asks `FocusAwareApp.stepBack`: when the session's app is the frontmost app (read once, at the request), the request is answered "ask" and only marked (an amber dot and a read-only note; Projects counts it as "Waiting in <host>"), so the agent prompts in its own window. Windows/Linux: `windows/src/core/focusaware.ts`, the foreground read in Rust.
- [ ] **Step 3: docs/SPEC.md.** In "## 3. Règles de comportement", add a new numbered item after the last one:
  > **Se retirer quand on est déjà dans l'app** (Réglages → Général → Île → « Step back when I'm already in the app », activé par défaut, clé `island.focusAware`). Quand une demande de permission ou une question arrive d'une session dont l'app est au premier plan (au niveau de l'app, pas de la fenêtre ni de l'onglet : l'app Claude, un terminal reconnu par son identifiant ou son `TERM_PROGRAM`, la famille VS Code, Cursor, Codex, et un agent étiqueté par le terminal que nomme son événement), NotchMeow répond aussitôt « ask » : l'agent pose la question dans sa propre fenêtre, l'île ne s'ouvre pas et ne fait aucun son. La pastille de l'agent porte un petit point ambre immobile (aussi dans le notch compact ; un badge ou une carte en attente passe avant), et la carte de la pastille affiche la note « Waiting in <app>: <verbe> » sans bouton, jusqu'au prochain événement de la session (PreToolUse, PostToolUse, PostToolUseFailure, UserPromptSubmit, Stop, StopFailure, Interrupt ou SessionEnd) ou 10 minutes au plus, jugées à la lecture. Projets montre la même attente (« Waiting in <app> », comptée parmi les attentes) ; dans la disposition Claude seul, c'est Projets qui la montre. L'app au premier plan est lue une seule fois, à l'arrivée de la demande, jamais enregistrée ni journalisée ; aucun observateur, aucun minuteur. Dans le doute (hôte inconnu, terminal non reconnu), tout reste comme avant. Une carte déjà ouverte n'est pas touchée. Le compagnon ne relance pas « still waiting for your OK » pour une demande retirée. Règles pures : `FocusAware.swift` (miroir : `windows/src/core/focusaware.ts`).
- [ ] **Step 4:** `bash scripts/test-focus-aware.sh && bash scripts/test-focus-aware-wiring.sh` still pass. **Commit** the three files with `docs(focus): focus awareness in CLAUDE.md, ARCHITECT.md and SPEC.md`.

---

### After Task 4: whole-branch review

`nm-reviewer-deep` (Sonnet 5.5, high, trigger 4) on `git diff main...HEAD`, with `security-review` loaded and `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` beside it (`model: sonnet`). It checks: the only new answer is "ask"; the answer is never awaited behind anything; the frontmost app is read in one place, only on the step-back path, and appears in no log line, mark or published value; no observer or timer was added; a stepped-back request changes no pin, view, focus, sound, badge or pill state; the App Store build matches no tagged agent; the dot never shows with a badge or a waiting card; the request handlers feed the Projects model once each, with the step-back's host, and `processEvent` once, with `twinWaitIn`; the Claude-only layout draws nothing of this feature; `island.focusAware` is homed once in the control map.

---

### Task 5: Owner checkpoint 2: the real machine

The owner runs a Debug build (the main session never launches or replaces the app). Checks, each with the expected result:

1. Terminal in front, `python3 scripts/fake-terminal-events.py --approval` run from Terminal → the script prints the "ask" reply at once (`{"permissionDecision":"ask"}`), the island stays closed and silent, the Claude Code pill shows the amber dot (open the island to see it; it is also on the compact notch), the Claude Code card shows "Waiting in Terminal: Runs"; the `Stop` that follows removes the dot and the note.
2. The same with `--term-program iTerm.app --bundle-id com.googlecode.iterm2` while Terminal is in front → the card opens and waits for a click, as today.
3. Settings → General → Island → the switch off, then check 1 again → the card opens, as today.
4. A real Claude Code session in VS Code, VS Code in front, a tool that needs approval → VS Code asks; the island stays closed; the dot shows. With Safari in front → the card, as today.
5. A Claude app session (Code tab), Claude in front, a question → the app asks; dot and "Waiting in Claude App". With another app in front → nothing visible from this feature, as today (Projects still counts the Claude App wait, as it does today).
6. Claude Code alone with a live project (the Claude-only layout), check 1 again → the project pill turns amber and its row reads "Waiting in Terminal"; the compact notch shows the amber count and the dot by the big cat.

---

## Questions for the owner

**Owner's answers, 2026-10-22:** 1, keep the spec's per-session rule (a mark ends at the session's next event; Projects may show a subagent's wait a little longer); 2, keep both the card's note and the session row's "Waiting in <host>". Both are settled: the checkpoint does not reopen them.

1. **A subagent's request ends earlier on the pill than in Projects.** The spec ends a mark at the session's next event (rule 4); Projects ends a wait per asker (the main agent or one subagent). When a subagent's request steps back and the main agent keeps working, the dot and note go at the main agent's next PreToolUse while the Projects row still says "Waiting in <host>" (up to 10 minutes or that subagent's next event). Recommended: keep the spec's session rule (the dot never claims a wait that is over; the case is rare). Alternative: key marks by asker like Projects (a `by` field and one more test case).
2. **Agents layout with the Projects section open:** the Claude Code card's note reads "Waiting in iTerm: Runs" and the section's row for that session reads "Waiting in iTerm". Same label function, two granularities (the pill's card and the session row). Recommended: keep both. Alternative: hide the card's note while the section is open.

---

## For the Windows/Linux twin (`2026-10-17-focus-awareness-tauri.md`, not edited here)

- Base: from `main` after this plan merges; its check `static let markLifetime: Double = 600` still holds.
- Its drift pin on `static let appWaitLabel = "Waiting in Claude App"` in `FocusAware.swift` must move to `ProjectsRules.swift` (`static let appWaitLabel`), or to `windows/src/projects/core.ts`.
- Drop its own `waitLabel` port: P-tauri is merged; reuse `windows/src/projects/core.ts` `waitLabel` (the generated `projects-core.js` copy).
- Its Step 5b ("only if P-tauri is merged") is now unconditional: check how `island/hooks.ts` feeds `State.projects` today and pass the step-back's host as `waitIn`. If its tagged-agent `--ask` questions ever step back, it needs the `twinWaitIn` rule too (its plan covers permission requests only).
- Settings: the Windows Settings were restyled (`windows/src/settings/general.ts`, General has no tabs, an Island card). The row goes after Open on hover there; fill `winHomes` (`general`, `null`, `Island`) and `win` (`focusAware`, `settings`) of the `island.focusAware` control in `tests/fixtures/settings/controls.json` (this plan adds it with both empty), and add `focusAware` to `FROZEN.settings` in `windows/scripts/settings-tests/map.test.mjs`; the `drift.test.mjs` and `settings.rs` save rules as the restyle requires.
- Views: on Windows the Claude Code card and the Claude-only layout (P-tauri) follow the same split as here: the note on the agents-layout card, nothing new where Projects already draws the wait.

---

## Self-review

- Spec coverage: goals 1 to 6 → Tasks 1 to 3 (goal 6's Windows/Linux half is the other plan); rules 1 to 8 → Task 1 (decide, host, marks, wording, setting) and Task 2 (placement, answer, bookkeeping, a card already up); "Which hosts can be matched" (Mac) → Task 1's table; the Projects fit → Task 1 (`noteText` on `ProjectsRules.waitLabel`, `twinWaitIn`) and Task 2 Steps 5 to 7 (`waitIn` in all three feeds); the island section → Task 3 (both cards, the grid, compact; the Claude-only layout through Projects); Settings → Task 1 (the map) and Task 3 (the binding); calls 1 to 10 and 1 to 7 after the builder check → Task 1 (calls 3, 5, 6, 7, 8, 9 after check 3), Task 2 (calls 1, 2, 6, 7, 10), Task 3 (calls 2 and 3 after the check); the Sidekick check left to the builder → Task 2 Step 2; `touchPill` not revealing the island → it only feeds the tuck-away count (`AppState.agentActivity`), and no pill is created.
- Type consistency: `FocusAware.Mark.host` is the `waitIn` passed to Projects and the `noteText` host; `markLifetime` is the name the twin pins; `cardWaiting(on:)` is AppState's existing method.
- Proportion: one pure file, one app file, small view edits; code is given only where an exact text is pinned (the call-site blocks, the twin feed, the Settings row).

## Dry run

Walked each task as its implementer, against `main` at `88055777`:

- Present once each: the three Projects comment lines in `HookServer.swift` (each followed by `ProjectsModel.shared.feedFromHook(payload: payload, waitIn: nil)`, 3 in all, each before the ask-at-once check in its handler); `state.touchPill(agentId)   // the pill's last event`; `private func dismissApprovalCard(note: String) {`; the 8-space `state.noteMessage = note` (the 12-space one is in `dismissQuestionCard`); no `let waitIn` or `let stepped` yet. `let pillId = state.pendingApproval?.pillId ?? "integration_claude"` occurs **twice** (lines 75 and 768): Task 2 Step 8 names the one in `dismissApprovalCard`.
- `HookServer.swift` has 2 `"permissionDecision":"allow"` and 2 `answersAskAtOnce(route: route, rawAgent: rawAgent)`; `sendLine` is `private` in `HookServer`, so the answer is sent from `HookServer.swift` and `FocusAwareApp` only decides.
- `tests/SidekickWiringTests.swift` pins 3 `Sidekick.shared.feed(payload: payload)` in `HookServer.swift`, and that a stray tagged-agent request is "never fed" (its feed is after the `.external` check): the step-back's feed lives in `FocusAwareApp.swift`, so both hold. `tests/HookOriginWiringTests.swift`'s order pins (`noteHost` before the first `state.touchPill(pillId)` after the handler; `respectsCard` counts) are untouched: `FocusAwareApp` holds its own `touchPill`/`noteHost`. `tests/ClaudeCodeWiringTests.swift` (the router before `let sessionId`) is untouched.
- `tests/ProjectsWiringTests.swift`: `feedLine` drives the count (3), the order pins (feed after the chat filter, before the gate or the ask at once) and the negative controls (comment out one feed); changing the constant to `…waitIn: waitIn)` keeps every pin true with the new code.
- `projects-core.js` `projectEventFrom`: a `PreToolUse` with `tool_name` `AskUserQuestion` is a `question`; `waitIn` is guarded to `''` for a Claude App event and a non-blank `waitIn` makes the ask `inApp` (ends at 10 min): hence `twinWaitIn` and no double count for the Claude App.
- `ProjectsRules.waitLabel(_: Any?)` exists (P-mac), `appWaitLabel = "Waiting in Claude App"`; `scripts/test-projects-rules.sh` lists the files `ProjectsRules.swift` needs to compile (`SidekickText.swift` and the cat files), which `test-focus-aware.sh` copies.
- Settings: `SettingsGeneralPage.swift` already has `var focusAware: Binding<Bool>? = nil` and the row inside `if let focusAware = model.focusAware`, after Open on hover and before Hover glow in the Island card; `SettingsSections.swift` passes `focusAware: nil,`; `render-settings.swift`'s sample omits it (the default `nil`). `SwitchRow(_:help:isOn:)` exists. `scripts/test-settings-map.sh` scans `\w*Key\s*=\s*"…"`, so `static let defaultsKey = "island.focusAware"` fails it until Task 1 Step 6; its `frozen` list, `SettingsMap.controls` and `controls.json` must agree in order; `windows/scripts/settings-tests/map.test.mjs` accepts `"winHomes": [], "win": []` (as `pills.main` has).
- The views: `integration_claude` is created with `isIntegration: true` (`AppState.loadIntegrationTasks`), so its card is `IntegrationCardView` (`TickerView(task: task, onDiffTap: onDiffTap)` once, in the active-session branch); `OverviewView`'s own VStack (`if let second { secondLine(second) }` once) is for non-integration pills. In the Claude-only layout `AgentPillsView` drops `integration_claude` from the grid and the left card is `ProjectBigCard`. `AppState.cardWaiting(on:)`, `Theme.State.color["approval"]` (`ProjectsStyle` is `fileprivate`), `CatIslandLayout.compactX`, `IslandRestingLayout.botDiameter`/`botCenterY`, `CatCast.Spot.pill`, `ProjectsLayout.badgeCenter` (`islandWidth - 66`) and `ProjectsLayout.contentHeight` (98) exist.
- `SidekickEngine.Env.ownCardShown` and `stuckContext()`'s `cardShown: env.ownCardShown()`; `SKStuckContext.cardShown` only holds back the waiting nudge (`SidekickStuck.swift`, `stuckStep` index 2).
- `touchPill` sends `agentActivity`, which only re-arms the tuck-away count; the step-back calls no `upsertWorkspaceTask`, so it creates no pill.
- `project.pbxproj` is tracked and P-mac's commits include it; the Keychain branch touches `build.yml`, `project.pbxproj`, `ClaudeService.swift`, `KeychainWrite.swift`, `tests/SettingsWiringTests.swift`: only the first two overlap with this plan.
- `scripts/fake-terminal-events.py --approval` already sends a held `PermissionRequest` with `term_program`/`bundle_id`, so the owner's check needs no new script.
