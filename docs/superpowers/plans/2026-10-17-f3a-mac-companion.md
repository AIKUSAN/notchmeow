# F3a-mac: One Chat and the Companion, in the macOS App (relaunch core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Rewrite 2026-10-22** (Opus 5.5, against `main` at `9c439961`; owner-approved scope of 2026-10-22, relaunch on 2026-11-13, the chat is the critical path). What changed and why:
> - **Scope is the relaunch core only** (spec, "Owner's answers, 2026-10-22", answer 1): one chat with the brain chip and the Folder button, the bigger view (560 pt) and Pop out, saved conversations (50, rename, pin, delete), personality, humour and quiet, the "Right now" view, Fix/Rewrite/Explain, the Companion tab, and "Comes with F3a" renamed "Coming soon". **Out, for a later `F3a-mem-mac` plan (1.1):** the memory's app side (memory screen, file, "Remember this?"), the Day log, the daily recap, Today so far, the sidekick upgrade. Old Tasks 1 (notes and memory), 9 (memory screen and chips) and 11 (recap and Day log) are gone; "Hooks left for F3a-mem-mac" names where that plan plugs in.
> - **Sessions come from the Projects registry** (`ProjectsModel.shared.view()`, a `PJView`; spec call 7 after the builder check): the sidekick-ledger adapter (`CompanionSessions`) is gone. The quiet rule reads `PJView.waiting`, which counts a wait stepped back into its own app (focus awareness, merged).
> - **Settings → AI and chat → Companion** is the hidden tab the restyle reserved (`SettingsRoute.companionTabShown`), built from the kit, with its controls in `SettingsMap.swift` and `tests/fixtures/settings/controls.json` (old Task 12's sidebar row and `GroupBox`es are gone). The Windows control count in `map.test.mjs` is bumped for the Mac-only rows (ruled OK for `island.focusAware`).
> - **The brain chip and Settings → Your AI are one choice** (call 4 after the builder check): Make main and Stop using (`SettingsAI.afterStoppingClaude`) already write `aiChoices`, which the chip reads; this plan only renames the picker's row and pins the shared store.
> - **The chat height** keeps today's 240 + 40 per message and lifts the cap from 300 to 560 (all six places), instead of the old base of 300.
> - **Task 5 is Haiku now:** `ClaudeService` is `@MainActor`, and the turn's prompt is a `Sendable` value captured like today's `system`; no isolation to design. Sonnet stays only on Pop out and Services (trigger 1).
> - **Base** moved from `414d89e6` to `9c439961` (after F3a-0 merges); `openChat` is the chat's shortcut (settled, no new ID); the cloud line's "Settings → AI and chat → Companion" is the contract's (settled).

**Goal:** Sub-project F3a's relaunch core on the Mac: the island's chat becomes one companion for every brain (the Claude plan, an API key, a local model), chosen in the model chip and mirrored in Settings → AI and chat → Your AI, with E3's level chip reduced to a **Folder** control shown only for the Claude plan; a bigger chat view and a **Pop out** window; conversations stored as files (a list with rename, pin, delete, delete all); a system prompt with the cat's personality, humour and the quiet rule, and a **"Right now"** block from the Projects registry; **quick actions** (Fix, Rewrite, Explain) on selected text through macOS Services, on the field or clipboard text, and Explain on a screenshot; and **Settings → AI and chat → Companion**. No memory, no recap, no tool (1.1 and F3b).

**Architecture:** The pure rules the relaunch uses are Swift ports of the F3a-0 contract (`shared/companion-core.js`, `docs/COMPANION-CONTRACT.md`, `tests/fixtures/companion/`), replayed by two test programs: the prompt and "Right now" (`CompanionText`, `CompanionPrompt`, `CompanionRightNow`, which reads a `PJView`'s JSON), and the records, settings and quick actions (`CompanionRecords`, `CompanionQuick`, plus the Mac-only `ChatSizing` and `CompanionChrome` words). On top: `CompanionFiles` (owner-only files, atomic writes) and `CompanionStore` (the conversation list and three `companion.*` defaults), and `Companion`, the app's one holder, which builds each turn's prompt parts on the main actor and hands `ClaudeService` a `Sendable` value its `ChatRunner` closure finishes per target. The views take plain values. Nothing runs while the chat is idle: no timer, no file watcher, no observer.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, AppKit (NSWindow, NSServices, NSPasteboard), Foundation, XcodeGen, `swiftc` test programs, Bash, Python 3 (the existing `tests/fake_local_llm.py`), Node for the Windows settings tests that this plan's count bump touches. No new dependency.

**Spec:** `docs/superpowers/specs/2026-10-17-notchmeow-chat-design.md` (approved 2026-10-22): "Owner's answers, 2026-10-22" and "Refresh 2026-10-22" first; Goals 1 to 3 and 5; "The rules" 4 to 7, 12 and 14 (the parts the relaunch uses); "The chat (Mac)" (One view, Size, Conversation list, The cat, Quick actions, The Sidekick tab's rows reserved for F3a); "The App Store build" (the F3a rows); "Privacy and CPU"; calls 1, 2, 4, 14, 15, 16, 18 of the first list and 3 to 5, 7, 9 of the second. The contract: `docs/superpowers/plans/2026-10-17-f3a-0-companion-contract.md`, "Interface for the app plans". The format is `docs/superpowers/plans/2026-10-15-g2-mac-link.md`'s. Windows and Linux are F3a-tauri.

**Base:** a new branch `f3a/mac-companion` in a git worktree, from `main` at `9c439961` or later, **after F3a-0 is merged** (Task 0 checks `shared/companion-core.js` and the ten fixtures). This plan never edits `shared/`, `design/prototype/cat-core.js`, any fixture under `tests/fixtures/` except `tests/fixtures/settings/controls.json` (Task 9), `docs/COMPANION-CONTRACT.md`, or anything under `windows/` except the four lines Task 9 names (the "Coming soon" twin and the control count).

## Global Constraints

Every task's requirements include this section. Values come from the spec and the contract; lines marked "Plan call:" are this plan's choices where they are silent, listed again under "Plan calls and questions for the owner".

- **Swift 6, SwiftUI and AppKit, no third-party dependency.** Every pure rule is a port of `shared/companion-core.js`, replayed against `tests/fixtures/companion/` by its script; if a port and a fixture disagree, the core decides. Port notes that bite: JS `\d` is ASCII, so write `[0-9]` (ICU's `\d` matches every script's digits); a JS code point is a Swift `unicodeScalars` element; JS `<` on strings compares UTF-16 code units, so sort with `a.utf16.lexicographicallyPrecedes(b.utf16)`; `isDay` uses the days-from-civil algorithm, never `Calendar` or a time zone; JS `=== true` is `as? Bool == true` on a JSON value.
- **Relaunch subset of the contract.** Ported now: the helpers the ported rules use, `isDay`, `personalityLine`, `moodHint`, `companionQuiet`, `memoryTokensFor` (one line, so `quiet-cases.json` replays whole), `promptOf` without its memory paragraph, `rightNowOf`, `cloudNotice`, `needsCloudNotice`, `titleOf`, `conversationClean`, `conversationsKeep`, `cleanCompanionSettings` (all seven fields), `quickRequest`, `quickResultClean` and their constants. **Not ported** (F3a-mem-mac): `noteCheck`, `rememberOffers`, `memory*`, `note*`, `dayLogAdd`, `memoryPromptBlock`, `dailyRecap*`, `acceptPolish`, `recapDismiss`, `recapMuted`. The two `prompt-cases.json` rows that carry a memory are replayed with `useMemory` off against their expected text without the paragraph that starts `What you remember` (Task 1).
- **0 % CPU when the island is hidden, and nothing while the chat is idle.** No `Timer`, display link, `DispatchSourceTimer`, `asyncAfter`, file watcher or observer is added. The conversation index is read on first use; files are written when a reply lands or the user renames, pins or deletes. `scripts/test-companion-wiring.sh` counts these (Task 11).
- **Stored files:** `~/Library/Application Support/NotchMeow/companion/conversations/<id>.json` (the App Store build's container path is the same expression). Folders `0700`, files `0600`, written atomically (a uniquely named temp file in the same folder, created with `O_CREAT | O_EXCL | O_NOFOLLOW`, then `rename`), read with `O_NOFOLLOW`, a symbolic link refused (read as absent, never followed or overwritten). A conversation file over 8 MiB is read as absent and never overwritten without the user's action. **No Keychain item, no UserDefaults value and no log line holds a message, a prompt, a reply or a path.** `AILog`/`nm.log` records event kinds only.
- **What leaves the Mac:** only through the brain the user picked, labelled as today (the caption: local, network or cloud). "Right now" is sent only while See my sessions is on (default on, call 15), and the Companion tab says where it goes (`CompanionChrome.sentTo`). A cloud brain gets the contract's one-time line (`CompanionRightNow.cloudNotice`) the first time "Right now" would be sent to that provider.
- **Sessions knowledge:** "Right now" reads `ProjectsModel.shared.view()` through `CompanionRightNow.text(_ view: PJView)`, which reads only the fields `rightNowOf` reads (a project's `name` and `waiting`; a session's `role`, `label`, `state`, `step`, `waitingInApp`, `note`; the view's `waiting` and `otherAgentSeen`). The registry knows Claude Code sessions only; another agent is the contract's one fixed line.
- **The Claude plan stays E3's.** `ClaudeCodeCommand.arguments`, the environment rules, `ClaudeCodeEngine.swift` and `tests/fixtures/ai/claude-code/` are unchanged byte for byte. Plan call: the companion prompt reaches Claude Code as the leading text block of each turn's user line (the existing `ClaudeCodeSetup.preamble`, joined with E3's recap when there is one), never as a new flag (anti-goal "Breaking … the E3 command lines"). **All of the Claude Code engine stays under `#if !APPSTORE`**: the Folder control, the preamble and the Claude quick path compile out of the App Store build, whose brain chip offers only API keys and local models (Apple on-device included); `scripts/check-app-binary.sh appstore` keeps proving it.
- **Never restyle what ships.** Allowed changes to existing views, all named by the spec: the chat view (`PromptView`) grows (call 1), gains a menu, the conversation list pane and a quick-result card; E3's level chip becomes the Folder control (call 4); the picker's Claude plan row reads "Claude · your plan"; the hidden Companion tab is shown; the Sidekick tab's chip text changes to "Coming soon" (owner). Everything else (pills, cards, the approval card, the other Settings tabs, the other island views) stays as it is in `main`. New views use the existing pieces (`CardBackground`, `PrimaryButton`, `SecondaryButton`, the model chip's capsule, 10.5 pt grey notes; the Settings kit: `SettingsCard`, `SettingRow`, `SwitchRow`, `HelpText`, `WrapRow`).
- **Frozen values:** pill IDs, cat IDs, action IDs (the chat's shortcut is the existing `openChat`, no new ID), the bundle identifiers, the defaults keys already stored (`aiChoices`, `aiClaudeCodeEnabled`, `aiClaudeCodeModel` …), the contract strings. New and frozen from now on: the defaults keys `companion.humor`, `companion.seeSessions`, `companion.cloudNoticeShown`; the Services messages `companionFix`, `companionRewrite`, `companionExplain`; the control ids `companion.humor`, `companion.sessions`, `companion.conversations`, `companion.sawLast`; the marker `NM_COMPANION_STORE_ACTIVE` (24 bytes, every build). The contract's other keys (`useMemory`, `polishRecap`, `recapDismissals`, `lastRecapDay`) are frozen names that F3a-mem-mac stores.
- **Plan call: nothing to migrate (call 3).** The Mac stores no chat today (`AppState.chatHistory` is memory only; E3's sessions are Claude Code's own files, which NotchMeow never reads). "Delete all" removes the new store only.
- **Never block Claude Code, never approve anything.** No hook, approval path or tool is added. E3's chat approval card is unchanged.
- **Never edit `NotchBuddy.xcodeproj` by hand.** A task that adds a Swift file runs `cd NotchBuddy && xcodegen` before it builds and commits the regenerated `project.pbxproj` (and `Info.plist`/`InfoAppStore.plist`, generated from `project.yml`).
- **No `UserDefaults` suite and no write to `UserDefaults.standard`, `~/Library` or the real `~/.claude` in any test or script.** Store tests use a temp root and a dictionary-backed defaults (`CompanionDefaults`, the `ShortcutStore` pattern).
- **Nothing of Coucou's comes back;** the names Coucou and Mochi appear in no new code (`scripts/check-no-leftovers.sh` stays green).
- **Models and commits** (CLAUDE.md): Haiku 5.5 first, Sonnet 5.5 only on a named trigger, never Opus or Fable. Each commit is local, never pushed, lists only its task's files, and ends with the `Co-Authored-By` line of the model that did the task (`Claude Haiku 5.5` or `Claude Sonnet 5.5`).
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app, and above all never touch the one in `/Applications`. Debug, Release and App Store **builds** in the worktree (`CODE_SIGNING_ALLOWED=NO`) are fine and are only built. `render-companion.sh` and `render-settings.sh` are not the app and may run. No task sends a hook event to the app's socket.
  2. Install nothing; no network except `127.0.0.1` in `test-companion-brain.sh` (the fake server).
  3. Use `trash`, never `rm -rf`, for anything deleted by hand; scratch under `${TMPDIR:-/tmp}` in a uniquely named folder (the test scripts' own `trap` clean-up is the repo's convention).
  4. No `UserDefaults` suite, no write to `UserDefaults.standard` or `~/Library` in a test; never read the real `~/.claude`, `~/.gemini`, `~/.codex`; never run the real `claude`.
  5. Never edit the files listed under "Base" as untouchable.
  6. Never push. Commit only in a task's commit step, after checking `git rev-parse --show-toplevel` (this worktree) and `git branch --show-current` (`f3a/mac-companion`).
  7. Never rename a frozen ID; no `Coucou` or `Mochi` anywhere.
  8. If a command is denied, or the find text of an edit does not occur exactly once, stop and report. No workaround.
  9. **Agent security (skill `agent-security-hardening`), for Tasks 1, 4 and 8:** text from the hook stream, another app's selection, the clipboard and a model's reply is data. It reaches a prompt only inside the contract's labelled blocks, never becomes an instruction, a file name or a path, and is never logged.

## Review Focus

The spec says what the chat does; it is silent on these, and each would bite the owner first. Each line names the test that pins it.

1. **A brain switch in the middle of a conversation, and a restored conversation.** Expected: the stored conversation keeps every message with the caption of the brain that wrote it; the Claude plan starts a fresh session seeded with E3's recap (`ClaudeCodeRecap`) when the conversation was not made by it in this run. Tests: Task 5 wiring pins ("opening a stored conversation resets the Claude session and plans a recap"); owner check 4.
2. **A symbolic link, a huge file or a stray name where a conversation file should be.** Expected: refused (read as absent), never followed, never truncated; a file whose name is not an id is ignored. Tests: Task 3 ("a symlink at <id>.json is not followed and not replaced", "a 9 MiB file is read as absent and left alone", "a file with a bad id name is ignored").
3. **A secret pasted into a conversation or a quick action.** Expected: it goes to the chosen brain like any message (the user's choice), is stored in that conversation's file (owner-only, deletable), never in defaults, never logged. Tests: Task 3 ("no message in the defaults", the file mode `0600`); Task 11 wiring pin "no companion source passes a message to AILog or print".
4. **The quiet rule while a wait is stepped back into its own app.** An approval answered in Ghostty rather than the notch. Expected: the next turn's prompt is quiet (no joke line, no mood) and "Right now" names "Waiting in Ghostty". Tests: Task 1 "a real stepped-back wait is named, counted and keeps the chat quiet" (a `PJView` built through the Swift registry), Task 4 wiring pin that `quietNow()` reads `ProjectsModel.shared.view().waiting`.
5. **Text from another app that tries to steer the model, or 50,000 characters.** Expected: the quick request labels it as data, cuts it at 8,000 code points and says so on the card; Replace never pastes by itself. Tests: Task 2 (contract replay of `quickRequest`, including the closing-tag and long-selection rows); Task 8 wiring pins (no `CGEvent`, no `AXUIElement`, no `NSReturnTypes`).

---

## File Structure

| Path | Responsibility |
|---|---|
| `NotchBuddy/Sources/App/CompanionText.swift` | New. Shared pure helpers of the contract: invisible characters, `cutTo`, code points, `lastPart`, `isDay`. Foundation only. |
| `NotchBuddy/Sources/App/CompanionPrompt.swift`, `CompanionRightNow.swift` | New. `personalityLine`, `moodHint`, `quiet`, `memoryTokens`, `promptOf`; `rightNowOf` (from a `PJView` or its JSON), the cloud line. |
| `NotchBuddy/Sources/App/CompanionRecords.swift`, `CompanionQuick.swift` | New. Conversation records, `conversationsKeep`, `CompanionSettings`; the quick actions' requests and result clean-up. |
| `NotchBuddy/Sources/App/ChatSizing.swift`, `CompanionChrome.swift` | New, Mac-only pure: the chat view's height; the Folder control's words, the "sent to" line, the Replace and popped-out notes. |
| `NotchBuddy/Sources/App/CompanionFiles.swift`, `CompanionStore.swift` | New. Owner-only atomic files under a root; the store (conversation index, the three defaults through `CompanionDefaults`). Marker `NM_COMPANION_STORE_ACTIVE`. |
| `NotchBuddy/Sources/App/Companion.swift` | New. The app's one holder: prompt parts for a turn, quiet, mood, sessions view, the cloud line, "What the AI saw last", the quick-action runner. `@MainActor`. |
| `NotchBuddy/Sources/App/CompanionViews.swift` | New. The chat menu, the conversation list pane, the quick-result card, the screenshot chip, the popped-out note. |
| `NotchBuddy/Sources/App/CompanionWindow.swift` | New. The pop-out window (`CompanionWindowController`). |
| `NotchBuddy/Sources/App/CompanionServices.swift` | New. `CompanionServicesProvider` (the three Services). |
| `NotchBuddy/Sources/App/SettingsCompanionPage.swift` | New. The Companion tab (`CompanionTab`), plain values in, and its "What the AI saw last" sheet. |
| `NotchBuddy/Sources/App/ClaudeService.swift` | Edited: the system prompt per turn from `Companion`; the Claude preamble; storing each finished exchange; opening a stored conversation; Explain's first turn; the one-turn quick call; recording what was sent. |
| `NotchBuddy/Sources/App/IslandViewContent.swift` | Edited (`IslandViewContent`'s `.prompt` case, `PromptView`, `ModelPickerView`): the pane switch, the menu, the card, `inWindow`, the picker's Claude row name. |
| `NotchBuddy/Sources/App/ClaudeChatViews.swift` | Edited: `ClaudeLevelChip` and `ClaudeLevelMenu` show the Folder words. |
| `NotchBuddy/Sources/App/IslandRootView.swift`, `BotCanvasView.swift`, `DesktopCatController.swift`, `IslandWindowController.swift`, `SidekickDropApp.swift` | Edited: the six chat-height expressions call `ChatSizing.islandHeight(messages:)`. |
| `NotchBuddy/Sources/App/AppState.swift`, `AppDelegate.swift` | Edited: `chatPane`, `chatPoppedOut`, `quickResult` (all `@Published`, never stored); the Services provider. |
| `NotchBuddy/Sources/App/SettingsRoute.swift`, `SettingsView.swift`, `SettingsSections.swift`, `SettingsMap.swift`, `SettingsSidekick.swift`, `SidekickSettingsView.swift` | Edited: the tab shown, its case and model, four controls, "Coming soon". |
| `NotchBuddy/project.yml`, `scripts/check-app-binary.sh` | Edited: `NSServices` in both targets; the marker in every build. |
| `tests/CompanionPromptTests.swift`, `CompanionRulesTests.swift`, `CompanionStoreTests.swift`, `CompanionBrainTests.swift`, `CompanionWiringTests.swift` and `scripts/test-companion-{prompt,rules,store,brain,wiring}.sh` | New test programs and their scripts. |
| `tests/SettingsRulesTests.swift`, `SettingsMapTests.swift`, `tests/fixtures/settings/controls.json`, `scripts/render-settings.swift`; `windows/src/settings/sidekicktab.ts`, `windows/src/settings/sidekick.ts`, `windows/scripts/settings-tests/pages.test.mjs`, `windows/scripts/settings-tests/map.test.mjs` | Edited by Task 9 only: the Companion tab shown, its four controls, the "Coming soon" twin, the count. |
| `scripts/render-companion.sh`, `render-companion.swift` | New: the pictures without launching the app. |
| `.github/workflows/build.yml`, `CLAUDE.md`, `ARCHITECT.md`, `docs/SPEC.md` | One CI step per new script; the Mac bullet; the paragraph; the French section. |

**Parity with Windows/Linux (F3a-tauri).** The rules and fixtures are shared. The Mac has Services (Windows and Linux use the clipboard and a drop), the Claude plan preamble through E3 (`claude_run.rs` there), Apple on-device as a plain companion, and UserDefaults for `companion.*` (the `companion` block of `settings.json` there). The four Companion controls are Mac-only in `controls.json` until F3a-tauri fills their Windows columns. Mac first: Windows gets nothing here the Mac lacks.

**App Store build.** Everything here is in it except what touches the Claude Code engine (the Folder control, the preamble, the Claude quick path), which stays under `#if !APPSTORE`. Files live in the container. Services need no entitlement.

### Hooks left for F3a-mem-mac (1.1; named, not built)

- `ChatPane` gains `.memory`, and `ChatMenuButton` a "Memory" item (Task 5's types).
- `CompanionPromptInput` gains `useMemory` and `memory`; `CompanionPrompt.promptOf` adds the memory paragraph between conduct and "Right now" (the one place, Task 1); the Task 1 test then replays the two memory rows as they are.
- `CompanionFiles` gains `memoryURL` (the same owner-only `read`/`write`); `CompanionStore.storedKeys` gains `companion.useMemory`, `polishRecap`, `recapDismissals`, `lastRecapDay`; `Companion.turnParts()` reads the memory.
- `ClaudeService.finish(…)`, right after `storeCurrent(state:)`, is where the "Remember this?" offers go; `Sidekick.feed(payload:)` is where the Day log observer goes; a `Companion.start()` (PresenceMonitor and the island's open event) is where the recap goes.
- The Companion tab gains "Memory" and "Daily recap" cards; the Sidekick tab's four "Coming soon" rows light up (Jokes and moods, Quiet times, My main AI, Today so far), each with its line in `SettingsMap.swift`.

## Tasks and agents

**Haiku 5.5 first; Sonnet 5.5 only on a named trigger.** **Tasks 7 and 8 are `nm-implementer-deep` (Sonnet 5.5, high), trigger 1:** Task 7 is an AppKit window that shares one SwiftUI view with the non-activating island panel of an `LSUIElement` app; Task 8 is `NSServices` (the provider object, its selectors, the Info.plist entries, `NSUpdateDynamicServices`), the pasteboard, activating the source app and a one-turn run on every brain. Everything else is normal multi-file coding (`nm-implementer`, Haiku 5.5, high) or docs and CI (`nm-implementer-light`, Haiku 5.5, medium). A Haiku task that fails twice goes to `nm-implementer-deep` (trigger 2), recorded in the ledger. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion` (deep ones also `superpowers:systematic-debugging`), plus the extra skills in the table; reviewers load `ponytail:ponytail-review`.

| # | Task | Agent, model, effort | Extra skills | Review |
|---|---|---|---|---|
| 0 | Worktree and baseline | the session | | none |
| 1 | The prompt and "Right now", ported | `nm-implementer`, Haiku 5.5, high | `agent-security-hardening` | `nm-reviewer` |
| 2 | Records, settings, quick actions, chat sizing, chrome words | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 3 | Files and the store | `nm-implementer`, Haiku 5.5, high | `security-review`, `swift-concurrency-6-2` *(file)* | `nm-reviewer` |
| 4 | The companion in every turn | `nm-implementer`, Haiku 5.5, high | `agent-security-hardening`, `swift-concurrency-6-2` *(file)* | `nm-reviewer` |
| 5 | Stored conversations: the list, the menu, the pane | `nm-implementer`, Haiku 5.5, high | `swiftui-patterns` *(file)* | `nm-reviewer` |
| 6 | One chat for every brain: the Folder control, the picker row, the bigger view | `nm-implementer`, Haiku 5.5, high | `swiftui-patterns` *(file)* | `nm-reviewer` |
| 7 | The pop-out window | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `swiftui-patterns` *(file)* | `nm-reviewer` |
| 8 | Quick actions: Services, the field and the clipboard, the screenshot | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `agent-security-hardening` | `nm-reviewer` |
| 9 | Settings → AI and chat → Companion, the control map, "Coming soon" | `nm-implementer`, Haiku 5.5, high | `accessibility` *(file)* | `nm-reviewer` |
| 10 | The pictures, then **owner checkpoint 1** | `nm-implementer`, Haiku 5.5, high | | the main session and the owner |
| 11 | Binary marker, wiring pins, CI, docs | `nm-implementer-light`, Haiku 5.5, medium | | `nm-reviewer` |
| After 11 | The whole branch, with the security and privacy pass | `nm-reviewer-deep`, Sonnet 5.5, high (trigger 4), with `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` beside it (`model: sonnet`) | `agent-security-hardening`, `security-review` | none |
| 12 | **Owner checkpoint 2:** the pictures again and the real-build checklist | the main session and the owner | | none |

Skills marked *(file)* are read from `~/.claude/plugins/marketplaces/ecc/skills/<name>/SKILL.md` (ARCHITECT.md).

**Size.** About 7 working days: Tasks 1 to 3 one and a half days, Task 4 one, Tasks 5 and 6 one, Task 7 half, Task 8 one and a half, Task 9 one, Tasks 10 and 11 with the review and fixes half a day each. The Mac chat must be merged by 2026-11-05 for F3a2 to join the relaunch (owner); start it the day F3a-0 merges.

## Execution

One worktree chat session runs the plan: branch `f3a/mac-companion`, model **Sonnet 5.5 at high effort** (trigger 5: an app plan with many cross-task interfaces). The three-step start of `ARCHITECT.md` applies:

1. **Setup and stop.** The chip's prompt: "Run `git switch -c f3a/mac-companion main`, then Task 0 of `docs/superpowers/plans/2026-10-17-f3a-mac-companion.md`, Steps 1 to 3 only. Read `CLAUDE.md`, `ARCHITECT.md`, that plan, the spec `docs/superpowers/specs/2026-10-17-notchmeow-chat-design.md` and `docs/COMPANION-CONTRACT.md`. If a base check fails, say so and stop. Reply "ready" and stop. Do not start Task 1. The owner approves in advance the controller brief the main session will send as your next message."
2. **Model.** The main session sets that session to Sonnet 5.5, high.
3. **Brief.** The main session sends the controller brief: run the plan with `superpowers:subagent-driven-development`, task by task; dispatch to the agents of the table; `nm-reviewer` after every task; `nm-reviewer-deep` once over the branch after Task 11; never Opus or Fable; the SUBAGENT RULES in every brief; task-sized briefs only; the ledger at `.superpowers/sdd/2026-10-17-f3a-mac-companion/progress.md` (base commit, then one line per task: agent, model, commit, test lines, review verdict, escalations with their trigger); edits whose find text does not occur exactly once stop the run; reviews read `git diff "$(git merge-base HEAD main)"...HEAD` narrowed to the task's files; every shell block passes `bash -n` before it runs; never launch any NotchMeow build; stop a process only by its saved PID; **ping the main session with `SendMessage`** at checkpoint 1 (after Task 10), at the end (Task 12) and whenever it stops; final report: the commits, every `bash scripts/test-companion-*.sh` and `bash scripts/test-companion-contract.sh`, `bash scripts/test-claude-code.sh`, `bash scripts/test-settings-{rules,map,wiring,ai}.sh`, `cd windows && npm run check:settings`, `bash scripts/test-shortcuts.sh`, `bash scripts/test-u1-wiring.sh`, `bash scripts/check-no-leftovers.sh`, the Debug, Release and App Store build lines with the three `check-app-binary.sh` lines, and the checkpoint PNG paths.

Before any follow-up turn, the main session checks the session is still on its configured model and effort.

## How to run this plan

A test step gives the test program's checks as code or as named assertions with exact values; a code step gives the file, the exact signatures and the values the spec pins, and the implementer writes the bodies. Every `Run:` line runs from the worktree's root. A test program's failing run prints `✗` lines and its last line is `N test(s) failed.`; a passing one ends `All tests passed.` (the `CT` helpers of `tests/CatTestSupport.swift`: `CT.section`, `CT.check`, `CT.checkTrue`, `CT.checkRows`, `CT.diffs`, `CT.fixture(_:dir:)`, `CT.finish()`). A compile that cannot find a file prints `error opening input file` (the red run before the code exists). A new script copies `scripts/test-settings-map.sh`'s head (`set -euo pipefail`, `cd`, a `mktemp -d` folder named `notchmeow-companion-<name>`, its `trap`, `NM_LOG_DIR`) and differs only in its comment and compile line.

**Builds.** `cd NotchBuddy && xcodegen && cd ..`, then `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO`; Release with `-configuration Release -derivedDataPath NotchBuddy/build/release`; App Store with `-scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store`, each with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`. Run a build in the background with its output in a file (two minutes or more) and read `tail -3`. **Never start a built app.**

**Looking at an image.** The agent that ran a render step opens the PNG with its file reader and says in one sentence what it sees against the thing named; a blank image is a failed step.

---

## Tasks

### Task 0: Worktree and baseline

- [ ] **Step 1: Branch**

```bash
git status                                    # must be clean
git switch -c f3a/mac-companion main
git log --oneline -3
```

- [ ] **Step 2: The contract is merged; nothing of the companion exists yet**

Run: `for f in shared/companion-core.js docs/COMPANION-CONTRACT.md scripts/test-companion-contract.sh tests/fixtures/companion/{note,memory,daylog,prompt,quiet,rightnow,conversation,settings,recap,quick}-cases.json; do test -f $f && echo "ok $f"; done; ls NotchBuddy/Sources/App | grep -c '^Companion'`
Expected: thirteen `ok …` lines and `0`. Otherwise F3a-0 is not merged (or a companion has started here): stop and tell the owner.

Run: `bash scripts/test-companion-contract.sh 2>&1 | grep -E "^# fail|✓"`
Expected: `# fail 0`, `✓ 10 fixture files match companion-core.js`, `✓ two generator runs write identical bytes`.

- [ ] **Step 3: Baseline of what this plan touches, and a build**

```bash
for f in scripts/test-claude-code.sh scripts/test-shortcuts.sh scripts/test-u1-wiring.sh scripts/test-ai-providers.sh scripts/test-settings-rules.sh scripts/test-settings-map.sh scripts/test-settings-wiring.sh scripts/test-settings-ai.sh; do printf '%-36s' "$f"; bash "$f" 2>&1 | tail -1; done
(cd windows && npm run check:settings 2>&1 | grep -E "^ℹ (pass|fail)")
bash scripts/check-no-leftovers.sh 2>&1 | grep -c "✗"
grep -c "min(300" NotchBuddy/Sources/App/IslandRootView.swift NotchBuddy/Sources/App/BotCanvasView.swift NotchBuddy/Sources/App/DesktopCatController.swift NotchBuddy/Sources/App/IslandWindowController.swift NotchBuddy/Sources/App/SidekickDropApp.swift
grep -c "companionTabShown = false" NotchBuddy/Sources/App/SettingsRoute.swift
```

Expected: eight lines ending `All tests passed.` (or the script's own pass line), `ℹ fail 0`, `0`, the counts `1`, `1`, `1`, `2`, `1` (the six chat-height expressions Task 6 replaces) and `1`. Then the Debug build: `** BUILD SUCCEEDED **`. Write `git merge-base HEAD main` into the ledger.

---

### Task 1: The prompt and "Right now", ported

**Files:**
- Create: `NotchBuddy/Sources/App/CompanionText.swift`, `CompanionPrompt.swift`, `CompanionRightNow.swift`, `tests/CompanionPromptTests.swift`, `scripts/test-companion-prompt.sh`

**Interfaces:**
- Consumes: the contract (F3a-0 plan, Tasks 1, 3 and 4 "Implement", for the helpers and rules); `PJView` (`ProjectsSnapshot.swift`), `PJRegistry.empty(home:)`, `ProjectsRegistry.eventFrom(_:now:waitIn:)`, `ProjectsRegistry.apply(_:_:)`, `ProjectsSnapshot.view(_:now:steps:)` (tests only).
- Produces:
  - `enum CompanionText` — `static func clean(_ s: String) -> String` (the contract's `INVISIBLE` set out), `cutTo(_ s: String, _ max: Int) -> String`, `codePoints(_ s: String) -> Int`, `lastPart(_ word: String) -> String`, `isDay(_ v: Any?) -> Bool` (a non-`String` is false).
  - `struct CompanionPromptInput: Equatable, Sendable { var catName: String?; var userName: String?; var personality: [String: Double]; var humor: String?; var quiet: Bool; var mood: String?; var seeSessions: Bool; var rightNow: String?; var today: String?; init(); init(json: Any?) }` — `init(json:)` keeps a string only where the contract reads a string, `quiet`/`seeSessions` only when the JSON value is `true`, a trait only when it is a finite number. (`placement` and `contextTokens` belong to the memory paragraph: F3a-mem-mac adds them with it.)
  - `enum CompanionPrompt` — `static let conduct`, `quietLine`, `humorLevels`, `humorLines: [String: String]`, `moods: [String: String]`, `traitWords: [(key: String, low: String, high: String)]` (contract order); `static func personalityLine(_ i: CompanionPromptInput) -> String`, `moodHint(_ state: String?) -> String`, `quiet(waiting: Int, card: Bool) -> Bool`, `quiet(json: Any?) -> Bool` (for the fixture's junk rows), `memoryTokens(placement: String?, contextTokens: Int?) -> Int`, `promptOf(_ i: CompanionPromptInput) -> String` (personality, conduct, "Right now" when `seeSessions` and non-empty, the date when `isDay`; joined by `"\n\n"`).
  - `enum CompanionRightNow` — `static let maxLength = 600`, `head`, `none`, `other`; `static func text(json: Any?) -> String` (`rightNowOf`), `static func text(_ view: PJView) -> String` (= `text(json: view.json)`), `cloudNotice(provider: Any?) -> String`, `needsCloudNotice(placement: String?, seeSessions: Bool, provider: String?, shown: [String]) -> Bool` plus `needsCloudNotice(json: Any?)` for the fixture.

- [ ] **Step 1: Write the script and the test program**

`scripts/test-companion-prompt.sh` (comment "Companion prompt and Right now: tests/fixtures/companion/prompt-cases.json, quiet-cases.json, rightnow-cases.json") compiles:

```bash
swiftc -swift-version 6 \
    $APP/CompanionText.swift $APP/CompanionPrompt.swift $APP/CompanionRightNow.swift \
    $APP/ProjectsRules.swift $APP/ProjectsRegistry.swift $APP/ProjectsSnapshot.swift $APP/HookOrigin.swift \
    tests/CatTestSupport.swift tests/CompanionPromptTests.swift \
    -o "$TEST_DIR/companion-prompt-tests"
"$TEST_DIR/companion-prompt-tests"
```

`tests/CompanionPromptTests.swift` (`@main enum CompanionPromptTests`, `@MainActor static func main()`, ends `CT.finish()`; every fixture row's failures gathered into one `CT.checkRows` per section, as `tests/SidekickRecapTests.swift` does), sections:
- "promptOf: N cases" over `prompt-cases.json` `cases`. A row whose `input.useMemory` is `true` and whose `input.memory` is an object is a **memory row**: compare `promptOf` of its input (memory is not read) with its `expect` split on `"\n\n"` without the part that starts `What you remember`, joined again. `CT.check("memory rows, compared without their memory paragraph", memoryRows, 2)`.
- "quiet, mood, memory tokens" over `quiet-cases.json` (`quiet(json:)`, `moodHint`, `memoryTokens`).
- "rightNowOf, cloudNotice, needsCloudNotice" over `rightnow-cases.json` (`text(json: row["view"])`, `cloudNotice(provider:)`, `needsCloudNotice(json:)`).
- "the order is fixed": `promptOf` with `seeSessions`, `rightNow: "MARK-NOW"`, `today: "2026-10-17"`: `You are Shrimpy` at 0, `How to behave` before `MARK-NOW`, `MARK-NOW` before `Today is 2026-10-17.`
- "quiet: no joke line, no mood": `quiet: true, mood: "finished", humor: "more"` holds `quietLine` and neither `moods["finished"]` nor `humorLines["more"]`.
- "a real view: no path, at most 600 code points": 30 `PreToolUse` events (`session_id` `s0`…`s29`, `cwd` `/Users/sam/Code/project-<i>`, `tool_name` `Bash`) applied to `PJRegistry.empty(home: "/Users/sam")`, `ProjectsSnapshot.view(r, now: T + 100, steps: ["s0": "Edit /Users/sam/Code/project-0/src/main.rs"])`; `text(view)` has at most 600 code points, no `/Users` and no `\`, and its last line ends `more projects`.
- "a real stepped-back wait is named, counted and keeps the chat quiet": one `PermissionRequest` (`s1`, `/Users/sam/Code/site`, `Bash`) through `eventFrom(_, now: T, waitIn: "Ghostty")`; the view at `T + 1000` gives exactly `head + "\n- site: main waiting for approval (Waiting in Ghostty)\nWaiting for the user: 1."`, and `CompanionPrompt.quiet(waiting: view.waiting, card: false)` is `true`.

(`T = 1760000000000`. Build the events the way `tests/ProjectsRegistryTests.swift` does; read it, do not invent another way.)

- [ ] **Step 2: Run to fail** — `bash scripts/test-companion-prompt.sh 2>&1 | tail -2` → `error opening input file`.

- [ ] **Step 3: Implement** the three files to the contract (F3a-0 plan, Task 1 Step 5 for the helpers, Tasks 3 and 4 "Implement"), with the port notes of the Global Constraints. The fixed texts are copied from `shared/companion-core.js` character for character (`CONDUCT`, the humor lines, the quiet line, the moods, `RIGHT_NOW_HEAD`, `RIGHT_NOW_NONE`, `RIGHT_NOW_OTHER`, the cloud line). Every rule returns new values and never throws.

- [ ] **Step 4: Pass** — `bash scripts/test-companion-prompt.sh 2>&1 | tail -1` → `All tests passed.`

- [ ] **Step 5: Commit** — the five files; `feat(companion): F3a-mac the prompt and Right now, ported from the contract`, with the trailer.

---

### Task 2: Records, settings, quick actions, chat sizing and the chrome words

**Files:**
- Create: `NotchBuddy/Sources/App/CompanionRecords.swift`, `CompanionQuick.swift`, `ChatSizing.swift`, `CompanionChrome.swift`, `tests/CompanionRulesTests.swift`, `scripts/test-companion-rules.sh`

**Interfaces:**
- Consumes: Task 1 (`CompanionText`). Nothing of the Claude Code engine: the folder words take the level's key and folder as plain values, so the words exist in every build and the test compiles without E3's files.
- Produces:
  - `struct CompanionMessage: Equatable, Sendable { var role: String; var text: String; var caption: String; var files: [String] }`, `struct CompanionConversation: Equatable, Sendable { var id, title: String; var pinned: Bool; var createdAt, updatedAt: Int; var messages: [CompanionMessage]; var json: [String: Any] }` (`json` adds `"version": 1`; keys in the contract's order).
  - `enum CompanionRecords` — `static let conversationsMax = 50`, `titleMax = 40`, `messagesMax = 1000`, `messageTextMax = 100_000`; `titleOf(_ text: Any?) -> String`, `clean(_ raw: Any?) -> CompanionConversation?`, `keep(_ entries: Any?) -> (keep: [String], evict: [String])`, `static func isId(_ s: String) -> Bool` (the contract's id rule).
  - `struct CompanionSettings: Equatable, Sendable { var humor: String; var useMemory, seeSessions, polishRecap: Bool; var recapDismissals: Int; var lastRecapDay: String; var cloudNoticeShown: [String]; static func clean(_ raw: Any?) -> CompanionSettings; var json: [String: Any] }` (in `CompanionRecords.swift`; all seven fields, as the contract).
  - `struct CompanionQuickRequest: Equatable, Sendable { let system, user: String; let cut: Bool }`; `enum CompanionQuick` — `static let kinds`, `textMax = 8000`, `labels: [String: String]`, `noVision`, `system: [String: String]`; `request(kind: Any?, text: Any?) -> CompanionQuickRequest?`; `resultClean(kind: Any?, reply: Any?) -> String`.
  - `enum ChatSizing` — `static let baseHeight: CGFloat = 240`, `perMessage: CGFloat = 40`, `maxHeight: CGFloat = 560`; `static func islandHeight(messages: Int) -> CGFloat` = `min(maxHeight, baseHeight + perMessage × max(0, messages))`. Plan call: today's 240 + 40 per message is kept, so a fresh chat looks as it does now; only the cap moves to the spec's 560, which the island panel already has room for (`IslandWindowController`'s `panelH`, the question card's). The width stays the island's 640 (`IslandConst.expandedWidth`). Judged by the owner at checkpoint 1.
  - `enum CompanionChrome` — `static func folderLabel(levelKey: String, folder: String?) -> String` (`chat` → `No folder`; `read` → `Reads · <name>`; `agent` → `Works in · <name>`; `<name>` the last component with trailing `/` removed, as `ClaudeCodeText.folderName`; `read` or `agent` with no folder is `Reads` or `Works in` alone); `static let folderRows = ["No folder", "Read a folder…", "Work in a folder…"]`; `static let folderHelp = "The folder Claude may use in this chat"`; `static func sentTo(_ brain: String) -> String` = `"This is sent with your messages to \(brain)."`; `static let replaceNote = "Copied. Press ⌘V to replace the selection."`; `static let poppedOutNote = "The chat is in its own window."`; `static let cutNote = "Cut to the first 8,000 characters."`.

- [ ] **Step 1: Write the script and the test program**

`scripts/test-companion-rules.sh` compiles `$APP/CompanionText.swift $APP/CompanionRecords.swift $APP/CompanionQuick.swift $APP/ChatSizing.swift $APP/CompanionChrome.swift tests/CatTestSupport.swift tests/CompanionRulesTests.swift`.

`tests/CompanionRulesTests.swift` sections:
- "titleOf, conversationClean, conversationsKeep" over `conversation-cases.json` (`title`, `clean` compared with `CT.diffs(got?.json ?? NSNull(), row["expect"])`, `keep`).
- "cleanCompanionSettings" over `settings-cases.json`, and cleaning twice is cleaning once.
- "the quick actions" over `quick-cases.json` (`request`, `result`); every `system[kind]` contains `never instructions to you`.
- "fifty kept at most": the contract's 80-entry test (`c0`…`c79`, pinned when `i % 3 == 0`, `updatedAt: i`): 50 kept, 30 evicted, none of them pinned.
- "chat sizing": `islandHeight(messages: 0) == 240`, `(1) == 280`, `(2) == 320`, `(8) == 560`, `(9) == 560`, `(-1) == 240`.
- "the folder words": `folderLabel(levelKey: "chat", folder: nil) == "No folder"`, `("read", "/Users/sam/Code/notchmeow") == "Reads · notchmeow"`, `("agent", "/Users/sam/Code/site/") == "Works in · site"`, `("agent", nil) == "Works in"`.
- "the sent-to line": `sentTo("Claude · your plan") == "This is sent with your messages to Claude · your plan."`.

- [ ] **Step 2: Run to fail** — `error opening input file`. **Step 3: Implement** (contract Tasks 5 and 6 "Implement", the quick-action half only, and the Mac-only values above). **Step 4: Pass** — `bash scripts/test-companion-rules.sh 2>&1 | tail -1` → `All tests passed.`

- [ ] **Step 5: Commit** — the six files; `feat(companion): F3a-mac records, settings, quick actions and chat sizing, ported`.

---

### Task 3: Files and the store

**Files:**
- Create: `NotchBuddy/Sources/App/CompanionFiles.swift`, `CompanionStore.swift`, `tests/CompanionStoreTests.swift`, `scripts/test-companion-store.sh`

**Interfaces:**
- Consumes: Task 2 (`CompanionRecords`, `CompanionSettings`, `CompanionConversation`).
- Produces:
  - `struct CompanionFiles: Sendable` — `let root: URL` (the `companion` folder); `static func standard() -> CompanionFiles` (`<Application Support>/NotchMeow/companion`); `var conversationsURL: URL`; `func read(_ url: URL, maxBytes: Int) -> Data?` (`open` with `O_RDONLY | O_NOFOLLOW`, `fstat` a regular file of at most `maxBytes`, else `nil`); `func write(_ data: Data, to url: URL) throws` (folders created `0700`; a temp file `.<name>.<random>.tmp` in the same folder opened `O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW` with mode `0600`, written, `fsync`, closed, `rename(2)` over the target; refused with an error when the target is a symbolic link, checked with `lstat`); `func delete(_ url: URL)` (`unlink`, never following a link); `func conversationIds() -> [String]` (the stems of `conversations/*.json` that pass `CompanionRecords.isId`). `static let conversationMax = 8 << 20`. `static let marker = "NM_COMPANION_STORE_ACTIVE"`.
  - `protocol CompanionDefaults { func object(forKey: String) -> Any?; func set(_: Any?, forKey: String) }` with `extension UserDefaults: CompanionDefaults {}`.
  - `@MainActor final class CompanionStore: ObservableObject` — `init(files: CompanionFiles, defaults: CompanionDefaults, now: @escaping () -> Int)` (`now` in ms); `static let shared` (standard files, `UserDefaults.standard`, the wall clock); `static let humorKey = "companion.humor"`, `seeSessionsKey = "companion.seeSessions"`, `cloudNoticeKey = "companion.cloudNoticeShown"`, `static let storedKeys = [humorKey, seeSessionsKey, cloudNoticeKey]` (F3a-mem-mac adds the other four); `@Published private(set) var conversations: [CompanionConversation]` (index order from `CompanionRecords.keep`, read lazily on first use); `@Published private(set) var settings: CompanionSettings` (read once from `storedKeys` through `CompanionSettings.clean`; a key not stored takes the contract's default); `func save(_ c: CompanionConversation) throws` (cleaned, written to `<id>.json` as `JSONSerialization` of `c.json` with `.sortedKeys`; then `keep` decides and the evicted files are deleted); `func conversation(id: String) -> CompanionConversation?`; `func rename(id: String, title: String)`, `func setPinned(id: String, _ pinned: Bool)`, `func delete(id: String)`, `func deleteAll()`; `func update(_ change: (inout CompanionSettings) -> Void)` (cleans, writes back only `storedKeys`); `func newConversationId() -> String` (`UUID().uuidString.lowercased()`, which `isId` accepts).

- [ ] **Step 1: Write the script and the test program**

`scripts/test-companion-store.sh` compiles `$APP/CompanionText.swift $APP/CompanionRecords.swift $APP/CompanionFiles.swift $APP/CompanionStore.swift tests/CatTestSupport.swift tests/CompanionStoreTests.swift` and runs the program with `NM_COMPANION_TEST_ROOT="$TEST_DIR/root"`.

`tests/CompanionStoreTests.swift` (a `final class DictDefaults: CompanionDefaults` holding a dictionary; every store made with `CompanionFiles(root: <temp>)` and `now: { 1_760_000_000_000 }`), checks:
- "owner-only": after `save`, the folders are `0700` and the file `0600` (`stat`).
- "atomic and exclusive": `save` twice leaves one `<id>.json` and no `.tmp` file in the folder.
- "a symlink at <id>.json is not followed and not replaced": make `conversations/abc.json` a link to `<temp>/elsewhere.json` holding a valid record; `conversation(id: "abc")` is `nil`; `save` of `abc` throws and `elsewhere.json` is unchanged.
- "a 9 MiB file is read as absent and left alone": its size is unchanged after `conversations` and `conversation(id:)`.
- "a file with a bad id name is ignored": `conversations/Bad Name.json` and `conversations/abc.json` (valid records); `conversations` lists `abc` only.
- "fifty kept, files deleted": saving 52 unpinned conversations (`updatedAt` 1…52) leaves 50 files, the two oldest gone.
- "delete and delete all remove the files"; "rename and pin are stored and survive a new store on the same root".
- "settings: defaults, update, clean": a fresh `DictDefaults` gives `humor == "little"`, `seeSessions == true`, `cloudNoticeShown == []`; `update { $0.humor = "more"; $0.seeSessions = false }` stores `companion.humor = "more"` and `companion.seeSessions = false`; the dictionary then holds no key outside `storedKeys`.
- "no message and no path in the defaults": after saving a conversation holding `MARKER-MESSAGE` from a folder `/Users/sam/MARKER`, no value in `DictDefaults` contains `MARKER`.

- [ ] **Step 2: Run to fail**, **Step 3: Implement** with POSIX calls through `Darwin` (`open`, `fstat`, `lstat`, `write`, `fsync`, `rename`, `unlink`) and `JSONSerialization`, reading with `JSONSerialization.jsonObject` and `CompanionRecords.clean`. **Step 4: Pass** — `bash scripts/test-companion-store.sh 2>&1 | tail -1` → `All tests passed.`

- [ ] **Step 5: Commit** — the four files plus the regenerated project (`cd NotchBuddy && xcodegen`; the Debug build must succeed); `feat(companion): F3a-mac owner-only files and the conversation store`.

---

### Task 4: The companion in every turn

**Files:**
- Create: `NotchBuddy/Sources/App/Companion.swift`, `tests/CompanionBrainTests.swift`, `scripts/test-companion-brain.sh`, `tests/CompanionWiringTests.swift`, `scripts/test-companion-wiring.sh`
- Modify: `NotchBuddy/Sources/App/ClaudeService.swift`

**Interfaces:**
- Consumes: Tasks 1 to 3; `ClaudeService` (`@MainActor`), `ChatRunner`, `Conversation.request(model:api:vision:placement:contextTokens:system:maxTokens:webSearch:)`, `ClaudeCodeSetup(executable:turn:preamble:)`, `ProjectsModel.shared.view()`, `CatSettingsStore.shared.settings` (`character`, `cats[id]?.personality`), `CatPresets.all[id]?.label`, `resolveUserFirstName()` (`UserIdentity.swift`), `AppState.baseState`, `pendingApproval`, `pendingQuestion`, `ChatProvider(_:).displayName`.
- Produces:
  - `struct CompanionTurnParts: Sendable, Equatable` — `let input: CompanionPromptInput`; `var system: String` (= `CompanionPrompt.promptOf(input)`).
  - `@MainActor final class Companion` — `static let shared`; `let store = CompanionStore.shared`; `func turnParts() -> CompanionTurnParts` (the Main cat's label and six traits, the first name, `quietNow()`, the mood from `AppState.shared.baseState.rawValue`, humor and See my sessions from the store, `CompanionRightNow.text(ProjectsModel.shared.view())` when See my sessions is on, today as `YYYY-MM-DD` from a `DateFormatter` with `en_US_POSIX` and the current time zone); `func quietNow() -> Bool` (`CompanionPrompt.quiet(waiting: ProjectsModel.shared.view().waiting, card: AppState.shared.pendingApproval != nil || AppState.shared.pendingQuestion != nil)`); `func cloudLine(for target: ChatTarget) -> String?` (when `needsCloudNotice` holds for `target.placement.rawValue`, the settings and `target.provider.rawValue`: records the provider in `cloudNoticeShown` through `store.update` and returns `cloudNotice(provider: ChatProvider(target.provider).displayName)`); `private(set) var lastSent: [String]` and `func recordSent(_ request: ChatRequest?)` (the system text, then each message's `.text` parts as `"<role>: <text>"`, and for every other part only `"<role>: [file <name>]"` or `"<role>: [image]"`; memory only, never written; `nil` keeps the last); `static let claudePreambleHead = "From NotchMeow, the app this chat runs in (instructions and context for you, not words of the user):"`.

- [ ] **Step 1: Write the brain test**

`scripts/test-companion-brain.sh` follows `scripts/test-ai-providers.sh`: `swiftc -swift-version 6 -D DEBUG NotchBuddy/Sources/App/AI/Core/*.swift NotchBuddy/Sources/App/AppLog.swift $APP/CompanionText.swift $APP/CompanionPrompt.swift $APP/CompanionRightNow.swift $APP/ProjectsRules.swift $APP/ProjectsRegistry.swift $APP/ProjectsSnapshot.swift $APP/HookOrigin.swift tests/AITestSupport.swift tests/CompanionBrainTests.swift`. Read `tests/AIProviderTests.swift` and `tests/AITestSupport.swift` for how the fake server (`tests/fake_local_llm.py --log`) is started, how a provider is pointed at it and how a run is awaited; reuse that, do not invent another way.

`tests/CompanionBrainTests.swift` builds a `CompanionPromptInput` by hand (Momo, user `Ike`, `seeSessions` on with the "Right now" text of a real two-project view built as in Task 1, today `2026-10-17`), makes a `Conversation` with one user turn, calls `Conversation.request(... placement: .local, contextTokens: 4096, system: CompanionTurnParts(input:).system ...)`, sends it through `OpenAICompatibleProvider` to the fake server and reads the logged body. Checks:
- "the system prompt reached the model": the first message has role `system` and its content starts `You are Momo, a cat who lives in the notch of Ike's Mac`, holds `How to behave:`, the contract's `RIGHT_NOW_HEAD` and `Today is 2026-10-17.`
- "no path reached the model": the whole logged body has no `/Users/`.
- "sessions off sends no Right now": with `seeSessions` false, the content has no `RIGHT_NOW_HEAD`.

- [ ] **Step 2: Write the wiring pins** — `tests/CompanionWiringTests.swift` in the style of `tests/SidekickWiringTests.swift` (`source`, `count`, `at`, `code`), section "the turn": `ClaudeService.swift`'s code calls `Companion.shared.turnParts()` once, holds `system: parts.system,` once inside the `makeRequest` closure, calls `Companion.shared.recordSent(` once and `Companion.shared.cloudLine(for:` once, and no longer holds `makeSystemPrompt` or `let system = systemPrompt`; inside `#if !APPSTORE`, `Companion.claudePreambleHead` once; `Companion.swift` calls `ProjectsModel.shared.view()` and never `Sidekick.shared.engine.ledger`. `scripts/test-companion-wiring.sh` first runs `git diff --quiet "$(git merge-base HEAD main)" -- NotchBuddy/Sources/App/AI/Core/ClaudeCodeEngine.swift tests/fixtures/ai || { echo "✗ E3's engine or the AI fixtures changed" >&2; exit 1; }`, then compiles `tests/CatTestSupport.swift tests/CompanionWiringTests.swift`. Later tasks add sections.

- [ ] **Step 3: Run both to fail.**

- [ ] **Step 4: Implement**
  - `Companion.swift` as in Interfaces.
  - `ClaudeService.swift`: remove `systemPrompt` and `makeSystemPrompt()` (find text `private let systemPrompt = ClaudeService.makeSystemPrompt()` and the doc comment and function under it; the first name now comes through `turnParts`). In `reply(…)`, take `let parts = Companion.shared.turnParts()` before the runner, replace `let system = systemPrompt` by nothing and `contextTokens: details.contextTokens, system: system,` by `contextTokens: details.contextTokens, system: parts.system,`. In the `#if !APPSTORE` block, `preamble: next.turn.resume ? nil : claudeRecap)` becomes `preamble: [Companion.claudePreambleHead + "\n" + parts.system, next.turn.resume ? nil : claudeRecap].compactMap { $0 }.joined(separator: "\n\n"))` with a `// ponytail:` comment: the prompt rides every turn so "Right now" and the date stay current; a resumed session's history grows by it each turn; send it only when it changed if that cost ever shows. In `finish(…)`, in the `.ok, .fallback, .interrupted` branch after the line `state.chatHistory[i].interrupted = result.outcome == .interrupted`, call `Companion.shared.recordSent(notices.built?.request)` and join `Companion.shared.cloudLine(for: answeredBy)` (when it is not `nil`) after the reply's existing `notice` on its own line. `SidekickChat.answer` keeps running first in `send`, unchanged: its rows never reach a model.

- [ ] **Step 5: Pass** — `bash scripts/test-companion-brain.sh 2>&1 | tail -1` and `bash scripts/test-companion-wiring.sh 2>&1 | tail -1` → `All tests passed.`; `bash scripts/test-claude-code.sh`, `bash scripts/test-ai-providers.sh` and `bash scripts/test-sidekick-wiring.sh` still pass; Debug and App Store builds succeed.

- [ ] **Step 6: Commit** — the files plus the regenerated project; `feat(companion): F3a-mac the companion's prompt in every turn, for every brain`.

---

### Task 5: Stored conversations in the chat: the list, the menu, the pane

**Files:**
- Create: `NotchBuddy/Sources/App/CompanionViews.swift`
- Modify: `NotchBuddy/Sources/App/ClaudeService.swift`, `IslandViewContent.swift` (`PromptView`), `AppState.swift`, `tests/CompanionWiringTests.swift`

**Interfaces:**
- Consumes: `CompanionStore` (Task 3), `ClaudeService.clearConversation(state:)`, `SidekickChat.caption`, `ClaudeCodeRecap.text(turns:)`, `ClaudeChatSession.reset()`.
- Produces:
  - `enum ChatPane: Equatable { case chat, conversations }` and `@Published var chatPane: ChatPane = .chat` on `AppState`.
  - `ClaudeService`: `private(set) var conversationID: String?` (made at the first user message of a new chat with `Companion.shared.store.newConversationId()`; `clearConversation` sets it to `nil`); `func storeCurrent(state: AppState)` (builds a `CompanionConversation` from `state.chatHistory`: user and assistant messages with content, skipping the sidekick's status rows (`caption == SidekickChat.caption` and the user row before one, `ClaudeService.isStatusQuestion`); title `CompanionRecords.titleOf` of the first user message; files from that turn's `PreparedFile.name`s; `createdAt` kept from the first save, `updatedAt` now in ms; `try?` save, a failure recorded as `AILog` event kind only) called once in `finish(…)` after the reply's content is set; `func open(conversationID: String, state: AppState)` (calls `clearConversation(state:)` first, then rebuilds `conversation` with `addUser`/`addAssistant` per stored message and `state.chatHistory` with `ChatMessage`s carrying each caption; a stored file name becomes a line `(file: <name>, not kept)` appended to its message's text in the rebuilt `Conversation` only; under `#if !APPSTORE`, `claudeRecap = ClaudeCodeRecap.text(turns:)` of the restored turns, so the next Claude turn starts a fresh session told the story so far; sets `conversationID`).
  - `struct ChatMenuButton: View` (an ellipsis in the model chip's capsule look, left of the Folder control and the model chip) with: New chat (⌘K's action), Conversations, then Pop out (Task 7) and the quick actions (Task 8).
  - `struct ConversationListPane: View` — rows (title, the day of `updatedAt`, a pin mark), newest first with pinned on top; a tap opens it and returns to `.chat`; a context menu with Rename (an inline field), Pin/Unpin, Delete; a footer "Delete all" behind a `confirmationDialog`, which deletes every file; a "Back to the chat" button. An empty list says "No saved conversations yet."

- [ ] **Step 1: Wiring pins.** Add the section "conversations": `ClaudeService.swift`'s code calls `storeCurrent(state:` exactly once, inside `finish(` after `state.chatHistory[i].interrupted`; the body of `open(conversationID:` calls `clearConversation(state:` before anything else and, under `#if !APPSTORE`, `ClaudeCodeRecap.text(`; `PromptView` switches on `state.chatPane` with both cases; `CompanionViews.swift` holds `confirmationDialog` once.

- [ ] **Step 2: Run to fail**, **Step 3: Implement** the pane and the menu in `CompanionViews.swift` and the edits above. `PromptView`'s conversation area becomes `switch state.chatPane` (`.chat` is today's content, unchanged); the input row stays under every pane. ⌘K (`islandNewConversation`) also sets `chatPane = .chat`.

- [ ] **Step 4: Pass** — `bash scripts/test-companion-wiring.sh 2>&1 | tail -1`, `bash scripts/test-claude-code.sh 2>&1 | tail -1`; Debug and App Store builds succeed.

- [ ] **Step 5: Commit** — the files plus the regenerated project; `feat(companion): F3a-mac stored conversations: the list, the menu, opening one`.

---

### Task 6: One chat for every brain: the Folder control, the picker row, the bigger view

**Files:**
- Modify: `NotchBuddy/Sources/App/ClaudeChatViews.swift`, `IslandViewContent.swift` (`ModelPickerView`), `IslandRootView.swift`, `BotCanvasView.swift`, `DesktopCatController.swift`, `IslandWindowController.swift`, `SidekickDropApp.swift`, `tests/CompanionWiringTests.swift`

**Interfaces:**
- Consumes: `ChatSizing`, `CompanionChrome` (Task 2).
- Produces: no new type. Behaviour:
  - The chat view's height is `ChatSizing.islandHeight(messages: <state>.chatHistory.count)` at all six places (find texts: `IslandRootView.swift` `return min(300, base + CGFloat(state.chatHistory.count) * perMsg)`; `BotCanvasView.swift` `? min(300, 240 + CGFloat(state.chatHistory.count) * 40)`; `DesktopCatController.swift` and `SidekickDropApp.swift` `min(300, 240 + CGFloat(state.chatHistory.count) * 40)`; `IslandWindowController.swift` `islandH = min(300, base + CGFloat(s.chatHistory.count) * perMsg)` and `h = min(300, base + CGFloat(s.chatHistory.count) * perMsg)`, dropping the `base`/`perMsg` lets beside them).
  - `ClaudeLevelChip` shows `CompanionChrome.folderLabel(levelKey: state.claudeLevel.key, folder: state.claudeLevel.folder)` in place of `ClaudeCodeText.levelChip(state.claudeLevel)`, with `.accessibilityLabel(CompanionChrome.folderHelp)`; `ClaudeLevelMenu`'s three row titles read `CompanionChrome.folderRows[0…2]` (their notes and the Agent readiness rule stay); the chip still appears only when the brain is the Claude plan (the existing `#if !APPSTORE` test in `PromptView`).
  - `ModelPickerView.name(_:)`: `case .cloud(let p): ChatProvider(p).displayName` becomes `case .cloud(let p): p == .claudeCode ? "Claude · your plan" : ChatProvider(p).displayName` (the chip already reads "Claude · your plan" through `ClaudeCodeText.modelChip`).

- [ ] **Step 1: Wiring pins** — section "one chat": `min(300` occurs 0 times in the five files; `ChatSizing.islandHeight(messages:` occurs once in each of `IslandRootView.swift`, `BotCanvasView.swift`, `DesktopCatController.swift`, `SidekickDropApp.swift` and twice in `IslandWindowController.swift`; `ClaudeChatViews.swift` calls `CompanionChrome.folderLabel(` once and no longer calls `ClaudeCodeText.levelChip(` (the function and its fixture stay: the Windows twin and the E3 tests use them); `IslandViewContent.swift` holds `"Claude · your plan"` once; the picker and Settings write the same store (call 4): `IslandViewContent.swift` holds `state.setChoice(setting, for: feature)` and `SettingsController.swift` holds `state.setChoice(setting, for: .chat)` and `SettingsAI.afterStoppingClaude(state.choice(for: .chat))`, so Make main and Stop using reach the chip with no new code.

- [ ] **Step 2: Run to fail**, **Step 3: Implement**, **Step 4: Pass** — the wiring script; `bash scripts/test-claude-code.sh` (the `levelChip` fixture still passes); `bash scripts/test-island-wing-wiring.sh`, `bash scripts/test-sidekick-drop.sh`, `bash scripts/test-settings-wiring.sh`; Debug and App Store builds.

- [ ] **Step 5: Commit** — `feat(companion): F3a-mac one chat for every brain, the Folder control, a bigger chat view`.

---

### Task 7: The pop-out window

**Files:**
- Create: `NotchBuddy/Sources/App/CompanionWindow.swift`
- Modify: `NotchBuddy/Sources/App/IslandViewContent.swift` (`IslandViewContent`'s `.prompt` case; `PromptView` gains `var inWindow = false`), `AppState.swift` (`@Published var chatPoppedOut = false`), `CompanionViews.swift` (the menu's Pop out, `PoppedOutNote`), `tests/CompanionWiringTests.swift`

**Interfaces:**
- Consumes: `PromptView`, `AppState`, the existing `.islandCollapse` notification.
- Produces: `@MainActor final class CompanionWindowController: NSWindowController, NSWindowDelegate` — `static let shared`; `func popOut()` (makes the window once: `NSWindow` with `[.titled, .closable, .resizable, .miniaturizable]`, title "Chat", content `NSHostingView(rootView: PromptView(state: .shared, inWindow: true))`, min size 420 × 360, default 520 × 640, `setFrameAutosaveName("NotchMeowChat")`, `isReleasedWhenClosed = false`; shows it with `NSApp.activate()` and `makeKeyAndOrderFront`; sets `chatPoppedOut = true`; folds the island with `.islandCollapse`); `func bringBack()` (closes the window); `func windowWillClose(_:)` sets `chatPoppedOut = false`. `PromptView(inWindow: true)` drops the 84-point cat gutter (16 on both sides) and draws no `CardBackground` wash. The one `case .prompt:    PromptView(state: state)` in `IslandViewContent` becomes `case .prompt: if state.chatPoppedOut { PoppedOutNote(state: state) } else { PromptView(state: state) }`, which covers every way the island reaches the chat (the top-bar icon, `openChat`, a hook's `.hookExpand`, a reply): `PoppedOutNote` shows `CompanionChrome.poppedOutNote` with "Show the window" (`popOut()`, which brings it forward) and "Bring it back" (`bringBack()`). The window has no timer and no work of its own while idle.

- [ ] **Step 1: Wiring pins** — section "pop out": `CompanionWindow.swift` makes exactly one `NSWindow(`, sets `setFrameAutosaveName("NotchMeowChat")`, holds no `Timer` or `asyncAfter`; `IslandViewContent.swift`'s `.prompt` case reads `state.chatPoppedOut`; the menu's Pop out calls `CompanionWindowController.shared.popOut()`.

- [ ] **Step 2: Run to fail**, **Step 3: Implement**, **Step 4: Pass** — the wiring script; Debug and App Store builds; Task 10's `window.png` is the visual check.

- [ ] **Step 5: Commit** — the files plus the regenerated project; `feat(companion): F3a-mac the chat pops out into its own window`, with `Co-Authored-By: Claude Sonnet 5.5`.

---

### Task 8: Quick actions: Services, the field and the clipboard, the screenshot

**Files:**
- Create: `NotchBuddy/Sources/App/CompanionServices.swift`
- Modify: `NotchBuddy/project.yml`, `NotchBuddy/Sources/App/AppDelegate.swift`, `Companion.swift` (the runner), `CompanionViews.swift` (`QuickResultCard`, the menu's quick items, the screenshot chip), `ClaudeService.swift` (`explain(request:image:state:)`, `quickReply(_:image:)`, `pendingImage`), `AppState.swift` (`@Published var quickResult: QuickResult?`), `tests/CompanionWiringTests.swift`

**Interfaces:**
- Consumes: `CompanionQuick` (Task 2); `AIService.resolve(.chat)`, `factory()`, `ChatRunner`; under `#if !APPSTORE`, `ClaudeCodeSetup` with a fresh `ClaudeChatSession()` at Chat only; the existing `.hookExpand` notification with `IslandView.prompt` to open the island on the chat; `AIMessages.error(_:target:)`.
- Produces:
  - `project.yml`, in **both** targets' `info.properties`, `NSServices` with three items: `NSMessage` `companionFix` / `companionRewrite` / `companionExplain`, `NSPortName` `NotchMeow`, `NSMenuItem` `{default: <CompanionQuick.labels[kind]>}` (`Fix with NotchMeow`, `Rewrite with NotchMeow`, `Explain with NotchMeow`), `NSSendTypes` `[public.utf8-plain-text, NSStringPboardType]`, no `NSReturnTypes` (call 5: never block the source app).
  - `final class CompanionServicesProvider: NSObject` with `@objc func companionFix(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>)` and the two siblings: each reads `pboard.string(forType: .string)`, notes `NSWorkspace.shared.frontmostApplication?.processIdentifier` as the source, and returns at once after handing `(kind, text, sourcePID)` to `Companion.shared.quick(…)` on the main actor. `AppDelegate`, right after the line `AIService.shared.start()`, sets `NSApp.servicesProvider = CompanionServicesProvider()` and calls `NSUpdateDynamicServices()` once.
  - `struct QuickResult: Equatable { let kind: String; var text: String; var running: Bool; var cut: Bool; var note: String?; let sourcePID: pid_t? }`.
  - `ClaudeService.pendingImage: PreparedFile?` (the first pending attachment whose `kind == .image`); `func quickReply(_ request: CompanionQuickRequest, image: PreparedFile?) async -> (text: String?, error: AIError?, target: ChatTarget?)` — one turn to the chat's routed brain with `request.system` as the system prompt, never touching `chatHistory` or `conversation` (with the Claude plan: a fresh `ClaudeChatSession()` at Chat only, `preamble: request.system`); `func explain(request: CompanionQuickRequest, image: PreparedFile?, state: AppState)` — `clearConversation(state:)`, then a first turn whose user message is `request.user` (the image attached) answered with `request.system` as the system prompt for that turn only; follow-ups are normal companion turns.
  - `Companion.quick(kind: String, text: String?, image: PreparedFile? = nil, sourcePID: pid_t?)`: `CompanionQuick.request`; `nil` → nothing. `explain` and `explainImage` → `ClaudeService.shared.explain(…)` and the island opens on the chat (when the routed target's `details.vision` is false for `explainImage`, the chat shows `CompanionQuick.noVision` and nothing is sent). `fix` and `rewrite` → `state.quickResult = QuickResult(running: true, cut: request.cut …)`, the island opens on the chat, `quickReply`, the reply through `CompanionQuick.resultClean`, `running = false`; a failure sets `note` to `AIMessages.error(…).text`.
  - `QuickResultCard` (in the chat, above the field while `quickResult != nil`): the title "Fixed" or "Rewritten", the text (selectable), `CompanionChrome.cutNote` in grey when `cut`, and **Replace** (only with a `sourcePID`: puts the text on the general pasteboard, activates that app with `NSRunningApplication(processIdentifier:)?.activate()`, sets `note` to `CompanionChrome.replaceNote`; owner, 2026-10-22: no Accessibility), **Copy** (the pasteboard only) and ×.
  - The chat menu's quick items: "Fix", "Rewrite", "Explain" act on the text in the message field when it is not empty, else on the general pasteboard's string (read when the item is chosen, never watched); "Explain the copied screenshot" is enabled when the pasteboard holds an image (read when the menu opens). Text dropped on the chat's field lands in the field (the system's own drop), so the three items cover a text drop (Plan call). An image dropped on the chat keeps E1's attachment flow, and while `pendingImage` is not `nil` a chip "Explain this screenshot" above the field runs `explainImage` with it.

- [ ] **Step 1: Wiring pins** — section "quick actions": `project.yml` holds `companionFix`, `companionRewrite`, `companionExplain` twice each (two targets) and no `NSReturnTypes`; `CompanionServices.swift` declares the three `@objc func companion…(_ pboard: NSPasteboard, userData: String?, error:` and holds no `await`; `AppDelegate.swift` sets `NSApp.servicesProvider` once and calls `NSUpdateDynamicServices()` once; no `Companion*.swift` file calls `CGEvent` or `AXUIElement` (no posting, no Accessibility); the Claude quick path in `ClaudeService.swift` is inside `#if !APPSTORE`; `quickReply` never writes `state.chatHistory` (its body has no `chatHistory`).

- [ ] **Step 2: Run to fail**, **Step 3: Implement**, **Step 4: Pass** — the wiring script; `cd NotchBuddy && xcodegen` then Debug, Release and App Store builds; `plutil -extract NSServices xml1 -o - NotchBuddy/Resources/Info.plist | grep -c companion` → `3`, and the same for `InfoAppStore.plist`.

- [ ] **Step 5: Commit** — the files plus the regenerated `project.pbxproj`, `Info.plist`, `InfoAppStore.plist`; `feat(companion): F3a-mac quick actions: Fix, Rewrite, Explain from any app, and Explain this screenshot`, with `Co-Authored-By: Claude Sonnet 5.5`.

---

### Task 9: Settings → AI and chat → Companion, the control map, "Coming soon"

**Files:**
- Create: `NotchBuddy/Sources/App/SettingsCompanionPage.swift`
- Modify: `NotchBuddy/Sources/App/SettingsRoute.swift`, `SettingsView.swift`, `SettingsSections.swift`, `SettingsMap.swift`, `SettingsSidekick.swift`, `SidekickSettingsView.swift`, `tests/SettingsRulesTests.swift`, `tests/SettingsMapTests.swift`, `tests/fixtures/settings/controls.json`, `scripts/render-settings.swift`, `tests/CompanionWiringTests.swift`; Windows twin: `windows/src/settings/sidekicktab.ts`, `windows/src/settings/sidekick.ts`, `windows/scripts/settings-tests/pages.test.mjs`, `windows/scripts/settings-tests/map.test.mjs`

**Interfaces:**
- Consumes: `CompanionStore` (settings, conversations), `Companion.shared.lastSent`, `AIService.shared.chip(.chat).label`, the kit (`SettingsCard`, `SettingRow`, `SwitchRow`, `HelpText`, `WrapRow`).
- Produces:
  - `struct CompanionTab: View` in `SettingsCompanionPage.swift`, plain values in (it reads neither `AppState` nor `CompanionStore`): `struct Model: Equatable { var humor: String; var seeSessions: Bool; var brain: String; var conversations: Int; var lastSent: [String] }`; `init(model: Model, setHumor: @escaping (String) -> Void, setSeeSessions: @escaping (Bool) -> Void, deleteAll: @escaping () -> Void)`. Cards, in order:
    - "Personality": `SettingRow("Humor")` with a segmented `Picker` Off · A little · More (`off`, `little`, `more`); `HelpText("The cat's traits come from Cat → Personality. While an agent waits for you, it makes no jokes.")`.
    - "What the chat knows": `SwitchRow("See my sessions", help: CompanionChrome.sentTo(model.brain), isOn:)`; `HelpText("Project names and what your Claude Code sessions are doing, never a path or what was written.")`.
    - "Conversations": `SettingRow("\(n) saved")` with "Delete all…" behind a `confirmationDialog`; `HelpText("Kept on this Mac, 50 at most; the oldest unpinned goes first.")`.
    - "What the AI saw last": a "Show" button opening a sheet with `model.lastSent` (monospaced, selectable, scrollable) or "Nothing sent since NotchMeow started."; `HelpText("Kept in memory only, gone when NotchMeow quits.")`. The sheet's root view carries `.accessibilityIdentifier(CompanionFiles.marker)`, so the marker is in every build (the Link view's pattern).
  - `SettingsSections.companion(store: CompanionStore) -> CompanionTab.Model` (brain from `AIService.shared.chip(.chat).label`, `lastSent` from `Companion.shared.lastSent`).
  - `SettingsRoute.swift`: `static let companionTabShown = false` → `true` (its comment: "The Companion tab (F3a)."). `SettingsView.swift`: `EmptyView()   // hidden until its page is ready (SettingsRoute.companionTabShown)` → `CompanionTab(model: SettingsSections.companion(store: companionStore), setHumor: { v in companionStore.update { $0.humor = v } }, setSeeSessions: { v in companionStore.update { $0.seeSessions = v } }, deleteAll: { companionStore.deleteAll() })`, with `@ObservedObject private var companionStore = CompanionStore.shared` on the view.
  - `SettingsMap.swift`, right after `Control(id: "sidekick.today", was: "(new)", homes: [h(.chat, .sidekick, "Today so far")], mac: []),`:

```swift
        Control(id: "companion.humor", was: "(new) Companion: Humor", homes: [h(.chat, .companion, "Personality")], mac: [d("companion.humor")]),
        Control(id: "companion.sessions", was: "(new) Companion: See my sessions, the one-time cloud line", homes: [h(.chat, .companion, "What the chat knows")],
                mac: [d("companion.seeSessions"), d("companion.cloudNoticeShown")]),
        Control(id: "companion.conversations", was: "(new) Companion: Conversations, Delete all", homes: [h(.chat, .companion, "Conversations")],
                mac: [f("~/Library/Application Support/NotchMeow/companion/conversations/<id>.json")]),
        Control(id: "companion.sawLast", was: "(new) Companion: What the AI saw last", homes: [h(.chat, .companion, "What the AI saw last")], mac: []),
```

  - `controls.json`: the same four entries, in the same place (after `sidekick.today`), each with `"winHomes": []` and `"win": []` (Mac-only until F3a-tauri, like `pills.main`); in `"pages"` only (not `"winPages"`: the Windows tab stays hidden until F3a-tauri), the chat tabs gain `"companion"` (find text: the two lines `"pages": [` and the `general` line, then the `agents` line and the `chat` line, which occur together once).
  - `SettingsMapTests.swift`: append to `frozen`, after the `link.device-id` entry, `("companion.humor", "defaults", "\"companion.humor\""), ("companion.seeSessions", "defaults", "\"companion.seeSessions\""), ("companion.cloudNoticeShown", "defaults", "\"companion.cloudNoticeShown\""),`; the tab cap line `SettingsRoute.tabs(page).count <= 4 && SettingsRoute.tabs(page, companion: true).count <= 5` → `SettingsRoute.tabs(page).count <= 5`.
  - `SettingsRulesTests.swift`: "chat tabs" expects `["yourai", "keys", "localmodels", "sidekick", "companion"]`; `CT.check("Companion hidden for now", SettingsRoute.companionTabShown, false)` → `CT.check("Companion shown", SettingsRoute.companionTabShown, true)`; "at most four tabs" → `<= 5` (label "at most five tabs, Companion included"); `CT.check("hidden Companion", M("chat/companion"), .init(page: .chat))` → `CT.check("Companion", M("chat/companion"), .init(page: .chat, tab: .companion))`; `CT.check("hidden Companion is not restored", …, .yourAI)` → `CT.check("Companion is restored", SettingsRoute.tab(for: .chat, stored: "companion"), .companion)`; `("Comes with F3a", .neutral)` → `("Coming soon", .neutral)`; `CT.check("F3a note", SettingsSidekick.comesWithF3a, "Comes with F3a")` → `"Coming soon"`.
  - **"Coming soon"** (owner, 2026-10-22): `SettingsSidekick.swift` `static let comesWithF3a = "Comes with F3a"` → `"Coming soon"` (the identifier stays: the Windows drift test reads it by name); `SidekickSettingsView.swift` `HelpText("Coming with F3a: hold notes` → `HelpText("Coming soon: hold notes`. The Windows twin, in the same commit, because `windows/scripts/settings-tests/drift.test.mjs` pins the two values together: `sidekicktab.ts` `export const COMES_WITH_F3A = "Comes with F3a";` → `"Coming soon"`, `sidekick.ts` `help("Coming with F3a: hold notes` → `help("Coming soon: hold notes`, `pages.test.mjs` `"Coming with F3a: hold notes"` → `"Coming soon: hold notes"`.
  - `map.test.mjs`: `assert.equal(all.length, 53, "the map holds 52 controls and winOnly's screen");` → `assert.equal(all.length, 57, "the map holds 56 controls and winOnly's screen");` (the four Mac-only Companion rows; the same bump as `island.focusAware`'s).
  - `scripts/render-settings.swift`: a `case .companion:` before the chat switch's `default:` (after the `.sidekick` case, whose last line is `example: state == "ready" ? "recap" : nil))`) returning `CompanionTab` with a sample model (`brain: "Claude · your plan"`, `conversations: 12`, three sample `lastSent` lines without a path; `stress` gives a long brain name).

- [ ] **Step 1: Wiring pins** — section "settings": `SettingsCompanionPage.swift` holds no `AppState`, `CompanionStore` or `UserDefaults`, references `CompanionFiles.marker` once and `confirmationDialog` once; `SettingsView.swift` holds `CompanionTab(` once and no `EmptyView()   // hidden until`; no `Companion*.swift` or `SettingsCompanionPage.swift` writes a `companion.` key except `CompanionStore.swift`.

- [ ] **Step 2: Run the settings tests to see the planned failures** — `bash scripts/test-settings-rules.sh`, `test-settings-map.sh` fail on the lines above until Step 3.

- [ ] **Step 3: Implement** the page, the route, the view, the map and the file, the tests' lines, the "Coming soon" twin and the count.

- [ ] **Step 4: Pass** — `bash scripts/test-settings-{rules,map,wiring,ai,contrast}.sh`, `bash scripts/check-settings-render-private.sh`, `bash scripts/test-companion-wiring.sh` → each passes; `cd windows && npm run check:settings` → `ℹ fail 0`; `bash scripts/render-settings.sh --out "${TMPDIR:-/tmp}/f3a-settings" --page chat --tab companion` draws the tab at 415, 720 and 1100 (look at the 415 one: no truncated word or button), and once more with `--stress`; Debug and App Store builds.

- [ ] **Step 5: Commit** — the files plus the regenerated project; `feat(companion): F3a-mac Settings → AI and chat → Companion, its controls in the map, Coming soon`.

---

### Task 10: The pictures, then owner checkpoint 1

**Files:**
- Create: `scripts/render-companion.sh`, `scripts/render-companion.swift`

**Interfaces:**
- Consumes: the views of Tasks 5 to 9, `scripts/render-home-guard.sh`.
- Produces: `bash scripts/render-companion.sh --out DIR [--scale 2]` writing `chat-1.png`, `chat-6.png` and `chat-12.png` (the chat view in the island at 1, 6 and 12 messages: 280, 480 and 560 points), `window.png` (the popped-out window's content at 520 × 640), `popped.png` (the island's note while popped out), `conversations.png`, `quick.png` (a Fixed result card with Replace and the cut note), `folder.png` (the Folder control and its menu for each level), `picker.png` (the model picker with the Claude row) and `cloud-line.png` (a reply with the one-time cloud line). It follows `scripts/render-sidekick.sh`: compiles every app file but `NotchBuddyApp.swift`, runs under `render-home-guard.sh` with a defaults domain of its own deleted at exit and a store root in its temp folder (never the real one). About seven minutes.

- [ ] **Step 1: Write both files**, **Step 2: Run** — `bash scripts/render-companion.sh --out "${TMPDIR:-/tmp}/f3a-pics" 2>&1 | tail -3` → one line per PNG; look at each.

- [ ] **Step 3: Commit** — `test(companion): F3a-mac render script for the pictures`.

- [ ] **Step 4: Owner checkpoint 1.** Copy the PNGs and Task 9's Companion tab pictures to `.claude/checkpoints/f3a-mac/` of the worktree (gitignored), ping the main session with `SendMessage`, and wait. What to look at: the chat heights (240 → 560, the width unchanged?), the pop-out window and the island's note, the conversation list, the quick card's Replace wording, the Folder words, the picker row, the Companion tab, "Coming soon". Questions: the Plan calls below. A change the owner asks for is one task-sized fix with its review, before Task 11.

---

### Task 11: Binary marker, wiring pins, CI and docs

**Files:**
- Modify: `scripts/check-app-binary.sh`, `tests/CompanionWiringTests.swift`, `.github/workflows/build.yml`, `CLAUDE.md`, `ARCHITECT.md`, `docs/SPEC.md`

- [ ] **Step 1: The binary check.** In `scripts/check-app-binary.sh`, after the line `    echo "✓ The Projects view is in this build"` and its `fi`, add a block in the same form: a comment `# The companion's store (sub-project F3a) is in every build too: Settings → Companion carries this marker.`, then under `if [ -n "${2:-}" ]; then`: `has NM_COMPANION_STORE_ACTIVE || { echo "✗ the companion (NM_COMPANION_STORE_ACTIVE) is missing from this build" >&2; exit 1; }` and `echo "✓ The companion is in this build"`. Build Debug, Release and App Store and run the three checks: each prints `✓ The companion is in this build`, and `appstore` still prints its absence lines for the Claude Code engine.

- [ ] **Step 2: The last wiring section** — "nothing runs idle, nothing leaks": over every `Companion*.swift`, `ChatSizing.swift` and `SettingsCompanionPage.swift`: no `Timer`, `asyncAfter`, `DispatchSourceTimer`, `CADisplayLink`, `FSEvents`, `makeFileSystemObjectSource`, `NSFilePresenter`, `NotificationCenter.default.addObserver`; no `AILog.record(` with a message, title or text argument (only event kinds) and no `print(`; no `UserDefaults.standard` outside `CompanionStore.swift`; `CompanionFiles.swift` uses `O_NOFOLLOW` in both its open calls and `O_EXCL` in the write; `ShortcutLogic.swift` has no `companion` case (`openChat` is the chat's shortcut).

- [ ] **Step 3: CI.** In `.github/workflows/build.yml`, right after the step whose `run:` is `bash scripts/test-sidekick-wiring.sh`, add one step per script with the same indentation: `Companion prompt`, `Companion rules`, `Companion store`, `Companion brain`, `Companion wiring`, each `run: bash scripts/test-companion-<name>.sh`.

- [ ] **Step 4: `CLAUDE.md`.** After the bullet that starts with ``- `shared/companion-core.js` — the companion's rules`` (F3a-0's), add a bullet "Sub-project F3a on the Mac (the chat, relaunch core)": the file map (`Companion*.swift`, `ChatSizing.swift`, `SettingsCompanionPage.swift`), the conversation store (path, modes, 50 kept), the three `companion.*` keys, the Claude preamble (never a new flag), "Right now" from `ProjectsModel.shared.view()`, the Services and their messages, the five scripts and `render-companion.sh`, the marker `NM_COMPANION_STORE_ACTIVE`, the Companion tab and its four controls, and the rules: nothing runs idle, nothing of a message or prompt is logged or put in defaults, Replace copies and never pastes, `openChat` is the chat's shortcut, memory and the recap are F3a-mem-mac (1.1).

- [ ] **Step 5: `ARCHITECT.md`.** Append to the paragraph that starts `8. **The companion` (F3a-0's): "**On the Mac** the relaunch core is built: the rules are Swift ports replayed by `scripts/test-companion-prompt.sh` and `-rules`; `CompanionStore` owns the conversation files (owner-only); `Companion` builds each turn's prompt parts on the main actor and `ClaudeService` finishes them per target inside `ChatRunner` (the Claude plan gets them as the turn's preamble); "Right now" reads `ProjectsModel.shared.view()`; Services give Fix, Rewrite and Explain from any app; Settings → AI and chat → Companion holds Humor, See my sessions, Conversations and What the AI saw last."

- [ ] **Step 6: `docs/SPEC.md`.** After `### Le compagnon (sous-projet F1)`'s section, add `### Le chat et le compagnon (sous-projet F3a)` in French: une seule conversation pour tous les cerveaux (le forfait Claude, une clé, un modèle local), le contrôle Dossier pour le forfait Claude, la vue plus grande (240 à 560 points) et la fenêtre détachée, les conversations gardées (50 au plus, renommer, épingler, supprimer), la personnalité du chat, l'humour et la règle du silence (qui compte aussi une attente renvoyée dans l'app de la session), le bloc « Right now » tiré des Projets, les actions rapides (Services, le champ ou le presse-papiers, la capture d'écran ; Replace copie et ramène l'app), Réglages → IA et chat → Compagnon et « Ce que l'IA a vu en dernier » ; la mémoire et le récap du jour viennent en 1.1. Section 10 (Barre de menus et réglages) gets one line for the Companion tab and the "Coming soon" chips.

- [ ] **Step 7: Final checks**

```bash
for f in scripts/test-companion-*.sh scripts/test-claude-code.sh scripts/test-ai-providers.sh scripts/test-sidekick-wiring.sh scripts/test-shortcuts.sh scripts/test-u1-wiring.sh scripts/test-island-wing-wiring.sh scripts/test-sidekick-drop.sh scripts/test-settings-rules.sh scripts/test-settings-map.sh scripts/test-settings-wiring.sh scripts/test-settings-ai.sh; do printf '%-40s' "$f"; bash "$f" 2>&1 | tail -1; done
bash scripts/test-companion-contract.sh 2>&1 | grep -E "^# fail|✓"
(cd windows && npm run check:settings 2>&1 | grep -E "^ℹ fail")
bash scripts/check-no-leftovers.sh | tail -1
git diff --quiet "$(git merge-base HEAD main)" -- shared design docs/COMPANION-CONTRACT.md NotchBuddy/Sources/App/AI/Core/ClaudeCodeEngine.swift $(git ls-tree -d --name-only main tests/fixtures/ | grep -v settings | sed 's|$|/|') && echo "untouched"
git diff --stat "$(git merge-base HEAD main)" -- windows | tail -1
```

Expected: every line passes; `ℹ fail 0`; `untouched`; `4 files changed`.

- [ ] **Step 8: Commit** — `docs(companion): F3a-mac binary marker, wiring pins, CI and docs`. Then the controller dispatches `nm-reviewer-deep` over the branch, with the security and privacy pass (the conversation store, what reaches each brain, "Right now" from the registry, the Services' untrusted text, the Claude preamble, the four Windows lines), and the two `pr-review-toolkit` agents beside it.

---

### Task 12: Owner checkpoint 2: the pictures again, then the real-build checklist

The main session re-renders (`render-companion.sh`, `render-settings.sh --page chat --tab companion`) and gives the owner the checklist for a Debug build he runs himself:
1. Chat on Auto with a cloud key: ask "what are my agents doing?" while a Claude Code session runs: the answer names the project and its state; the one-time cloud line appears once.
2. Settings → AI and chat → Companion → See my sessions off: the same question gets "I can't see your sessions" in spirit; "What the AI saw last" shows no "Right now".
3. Humor on More, then an approval arrives (or is answered in the terminal, stepped back): the next reply makes no joke (the quiet rule).
4. Switch the brain to "Claude · your plan" mid-conversation: the reply comes; the Folder control appears; quit and reopen NotchMeow, open the conversation from the list, ask a follow-up: it knows the earlier turns. Settings → Your AI → Stop using: the chip goes back to Auto.
5. Select text in TextEdit → right-click → Services → Fix with NotchMeow: the island opens with the result; Replace brings TextEdit back with "Press ⌘V"; ⌘V replaces the selection.
6. Copy a screenshot (⌘⌃⇧4), menu → Explain the copied screenshot, on a vision brain and on a text-only local model (the no-vision line).
7. Pop out the chat, fold the island: the window stays; the island's chat shows the note; close the window: the chat is back in the island.
8. Rename, pin, delete one, delete all: the files in `~/Library/Application Support/NotchMeow/companion/conversations/` follow.
9. Activity Monitor with the island hidden and the chat idle: NotchMeow at 0 %.

## Plan calls and questions for the owner

Made by this plan (the contract's apply too):
- **Chat height 240 → 560, 40 points a message; width unchanged at 640.** Keeps today's look for a short chat; judged at checkpoint 1.
- **"Coming soon" on both apps in one commit.** The Windows drift test pins the Mac's chip text to the Windows one, so renaming only the Mac's breaks `npm run check:settings` until F3a-tauri. This plan changes the Windows constant, its help line and its test string too (four lines). *Owner: OK to touch those four Windows lines here (recommended), or keep "Comes with F3a" on the Mac until F3a-tauri lands both?*
- **The four Companion controls are Mac-only in `controls.json`** until F3a-tauri, and the Windows count goes 53 → 57 (the `island.focusAware` precedent).
- **The Claude plan gets the companion prompt as each turn's preamble,** not a new flag, so E3's command lines and fixtures stay as they are; a resumed session's history grows by it each turn (marked `ponytail:` in the code).
- **Explain opens a new conversation** whose first reply uses the explain prompt; follow-ups are normal companion turns.
- **A text drop is covered by the field:** the quick items act on the field's text, else the clipboard.
- **Nothing to migrate** (call 3): no chat is stored on the Mac today.
- **No question needs an answer before Task 1.** The scope, the shortcut, Replace, the stepped-back quiet and the cloud line's words are the owner's answers of 2026-10-22.

## Dry run

Walked each task as its implementer against `main` at `9c439961` (F3a-0 not merged yet, so Task 0's contract checks, the fixture keys and `CLAUDE.md`/`ARCHITECT.md` anchors of Task 11 are the F3a-0 plan's, whose cases were run against a prototype there):
- **Every find text occurs exactly once** (checked with `grep -cF`): `private let systemPrompt = ClaudeService.makeSystemPrompt()`, `let system = systemPrompt`, `contextTokens: details.contextTokens, system: system,`, `preamble: next.turn.resume ? nil : claudeRecap)`, `state.chatHistory[i].interrupted = result.outcome == .interrupted` (`ClaudeService.swift`); `Text(ClaudeCodeText.levelChip(state.claudeLevel))`, `.accessibilityLabel("What Claude may do in this chat")` (`ClaudeChatViews.swift`); `case .prompt:    PromptView(state: state)`, `case .cloud(let p): ChatProvider(p).displayName` (`IslandViewContent.swift`); the six height expressions (1, 1, 1, 1 and 2 in `IslandWindowController.swift`, each line distinct); `AIService.shared.start()` (`AppDelegate.swift`); `static let companionTabShown = false`, `EmptyView()   // hidden until its page is ready (SettingsRoute.companionTabShown)`, `static let comesWithF3a = "Comes with F3a"`, `HelpText("Coming with F3a: hold notes`, the `sidekick.today` control line, the five `SettingsRulesTests.swift` lines, the `SettingsMapTests.swift` cap line and `link.device-id` frozen line, `example: state == "ready" ? "recap" : nil))` (`render-settings.swift`), `    echo "✓ The Projects view is in this build"`; the four Windows lines. **Caught:** the `chat` line of `controls.json` occurs twice (`pages` and `winPages`), so Task 9 anchors it under `"pages": [`; `.padding(.leading, 84)` occurs four times in `IslandViewContent.swift`, so Task 7 changes `PromptView`'s by its `inWindow` property, not by find text.
- **Every name exists or is made earlier:** `ClaudeService` is `@MainActor` (so `turnParts()` is a direct call); `ProjectsModel.view(projectCats:mainCat:)` and `PJView.json` (keys `projects`, `waiting`, `sessionCount`, `otherAgentSeen`); `PJRegistry.empty(home:)`, `ProjectsRegistry.eventFrom(_:now:waitIn:)`, `apply`, `ProjectsSnapshot.view(_:now:steps:…)`, and `HookServer` already passes `waitIn` (focus awareness merged); `AppState.baseState`, `pendingApproval`, `pendingQuestion`, `chatHistory`, `claudeLevel`; `BotState` raw values match the contract's mood keys; `CatSettingsStore.shared.settings.character`, `cats[id].personality` (`CatPersonality`: six traits); `CatPresets.all[id]?.label`; `resolveUserFirstName()`; `ClaudeCodeSetup(executable:turn:preamble:)`, `ClaudeCodeRecap.text(turns:)`, `ClaudeChatSession.reset()`; `ClaudeCodeLevel.key` (`chat`/`read`/`agent`) and `.folder`; `ClaudeCodeText.modelChip` already says "Claude · your plan" in the chip, `ChatProvider(.claudeCode).displayName` is "Claude plan" (hence the picker edit); `ModelPickerView.pick` writes `state.setChoice(setting, for: feature)` and `SettingsController.setChat`/`stopClaude` write the same `aiChoices` through `SettingsAI.afterStoppingClaude`; `PreparedFile.kind` with `AttachmentKind.image`; `ChatRequest.Part` (`text`, `fileText`, `image`, `pdf`); the island panel's `panelH` is 560; `SettingsRoute.tabs(_:companion:)` and `.companion`; the kit's `SwitchRow(_:help:isOn:chip:disabled:)` and `SettingRow(_:help:control:)`; `SettingsMapTests`' `frozen`, key scanner and tab-cap checks; `map.test.mjs`'s count 53 and its `winHomes: []` rows (`pills.main`); `drift.test.mjs` pins `comesWithF3a = "${COMES_WITH_F3A}"`; `tests/fake_local_llm.py --log`; `render-settings.swift` draws `SettingsRoute.tabs(page)`, so a shown Companion tab needs its case; `check-app-binary.sh`'s marker blocks; `.github/workflows/build.yml`'s `test-sidekick-wiring.sh` step; `tests/CatTestSupport.swift`'s `CT` helpers.
- **Dropped as stale:** the sidekick-ledger adapter (`CompanionSessions`), the Day log feed in `Sidekick.swift`, the recap's `PresenceMonitor` and `$mode` subscriptions, the memory screen and chips, the Settings sidebar row with `GroupBox`es, the `companion` shortcut question, and the base `414d89e6`.

## Self-review

- **Spec coverage (relaunch scope):** one chat for every brain and the brain chip = Tasks 4 and 6; the Folder control = Task 6; the bigger view and Pop out = Tasks 6 and 7; saved conversations, rename, pin, delete, delete all = Tasks 3 and 5; personality, humour, moods, quiet (stepped-back waits included) = Tasks 1 and 4; "Right now" from the registry and the cloud line = Tasks 1 and 4; Fix/Rewrite/Explain through Services, the field, the clipboard and a dropped or copied screenshot, Replace copies = Task 8; the Companion tab with its map lines and "What the AI saw last" = Task 9; "Coming soon" = Task 9; App Store build = the `#if !APPSTORE` pins of Tasks 4, 6, 8 and the marker of Task 11; Privacy and CPU = Global Constraints and Task 11's pins. Memory, Day log, recap, Today so far: out by the owner's answer, hooks named.
- **Types:** `CompanionPromptInput`, `CompanionTurnParts.system`, `CompanionRightNow.text(_:)`, `CompanionStore.update`, `storedKeys`, `CompanionQuickRequest`, `ChatPane`, `QuickResult`, `CompanionTab.Model` are defined once and used with the same names after.
- **Proportion:** no function body is written out; the code blocks are compile lines, one map snippet copied into two files, and the final checks.

## Rulings, 2026-10-22 (main session)
- **"Coming soon" on both platforms in Task 9.** The owner chose "Coming soon" (spec, Owner's answers 2026-10-22, question 12). `drift.test.mjs` pins the Mac and Windows strings together, so Task 9 also changes the four Windows lines (`sidekicktab.ts`, `sidekick.ts`, `pages.test.mjs`, and the count in `map.test.mjs`) in the same commit and runs `npm run check:settings`. F3a-tauri's Task 12 then only checks the rename is present; it does not redo it.
